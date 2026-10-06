import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:mc_nbt/mc_nbt.dart';
import 'package:mc_protocol_v26_2/mc_protocol_v26_2.dart';
import 'package:mc_wire/mc_wire.dart';

import 'remote_chunk.dart';

/// 会话事件（会话 → 调用方；调用方在独立 isolate 里驱动 Game/渲染）。
sealed class SessionEvent {
  const SessionEvent();
}

/// 已进入 play 阶段（服务器 Login 包）。
final class JoinedGame extends SessionEvent {
  const JoinedGame(this.login);

  final GameLogin login;
}

/// 一个 chunk 已摄入完成。
final class ChunkLoaded extends SessionEvent {
  const ChunkLoaded(this.chunk);

  final RemoteChunkColumn chunk;
}

/// 一个 chunk 被服务器卸载。
final class ChunkUnloaded extends SessionEvent {
  const ChunkUnloaded(this.x, this.z);

  final int x;
  final int z;
}

/// 方块变化（服务器权威回显；含段内批量与单方块）。
final class BlockChanged extends SessionEvent {
  const BlockChanged(this.pos, this.stateId);

  final McBlockPos pos;
  final int stateId;
}

/// 服务器强制同步位置（传送/大偏差回拉）。
final class PositionCorrection extends SessionEvent {
  const PositionCorrection({
    required this.x,
    required this.y,
    required this.z,
    required this.yRot,
    required this.xRot,
    required this.teleportId,
    required this.isTeleport,
  });

  final double x;
  final double y;
  final double z;
  final double yRot;
  final double xRot;
  final int teleportId;
  final bool isTeleport;
}

/// 会话因服务器断开/错误而结束。
final class SessionClosed extends SessionEvent {
  const SessionClosed(this.reason);

  final String reason;
}

/// 一个段的批量方块变更（SectionBlocksUpdate；水面/流体 tick 高频）。
final class SectionChanged extends SessionEvent {
  const SectionChanged({
    required this.sectionX,
    required this.sectionY,
    required this.sectionZ,
    required this.changes,
  });

  final int sectionX;
  final int sectionY;
  final int sectionZ;

  /// 段内变更（段内局部坐标 + 服务器状态号）。
  final List<({int lx, int ly, int lz, int stateId})> changes;
}

/// 服务器时间同步（SetTime，约每秒一次）：昼夜/游戏时间以服务器为准。
final class TimeUpdated extends SessionEvent {
  const TimeUpdated({
    required this.gameTime,
    required this.totalTicks,
    required this.rate,
  });

  /// 全局游戏时间（世界年龄）。
  final int gameTime;

  /// 主世界昼夜总 tick（% 24000 得当日时刻；tick 0 = 日出，24000 tick/天）。
  final int totalTicks;

  /// 时间流速（服务器游戏规则 doDaylight/游戏速度；正常恒 1）。
  final double rate;
}

/// 断开原因（结构化上抛，供 UI 给可操作提示）。
final class DisconnectReason {
  DisconnectReason(this.message, {this.detail});

  final String message;
  final String? detail;

  @override
  String toString() => detail == null ? message : '$message：$detail';
}

/// 联机会话（tasks 5.2–5.7）：握手 → offline 登录 → 配置 → play，
/// 服务器权威世界摄入 + 移动/挖放上报。**跑在 worker isolate 里**（design D3），
/// 本类型不依赖任何 Flutter/GPU 设施。
///
/// 用法：
/// ```dart
/// final session = RemoteSession(host: '127.0.0.1', port: 25565, playerName: 'flutter_mc');
/// await session.connect();
/// session.events.listen((e) { ... });
/// session.updatePlayer(x, y, z, yaw, pitch, onGround); // 每 tick
/// ```
final class RemoteSession {
  RemoteSession({
    required this.host,
    required this.port,
    required this.playerName,
    this.protocolId = ProtocolV262.measuredProtocolId,
    this.keepAliveTimeout = const Duration(seconds: 30),
    this.viewDistance,
  });

  final String host;
  final int port;
  final String playerName;

  /// 握手用协议号（默认实测值；remote-play 要求实际值经 ping 实测后传入）。
  final int protocolId;

  /// 端侧视距（原版客户端设置；configuration 阶段经 ClientInformation 上报）。
  final int? viewDistance;

  /// 心跳超时（原版语义：服务器每 15s 一次 keep-alive
  /// （判据 ServerCommonPacketListenerImpl.keepConnectionAlive 的 15000ms 节奏，
  /// 上一轮未回应即 30s 时踢 disconnect.timeout）；客户端对称：30s 没收到
  /// keep-alive 判定链路死亡）。测试注入短时长用。
  final Duration keepAliveTimeout;

  WireConnection? _conn;
  PacketRegistry? _registry;
  final _events = StreamController<SessionEvent>.broadcast();
  Stream<SessionEvent> get events => _events.stream;

  // 心跳超时巡检（tasks 7.3）：回应 keep-alive 即刷新时钟，超时判链路死亡。
  DateTime _lastKeepAliveAt = DateTime.now();
  Timer? _keepAliveTimer;

  final Map<String, RemoteChunkColumn> _chunks = {};

  // registry 数据摄入（tasks 5.2；内容身份映射的数据源）
  final Map<String, List<RegistryEntry>> _registries = {};
  int get blockStateCount {
    final int? entries = _registries['minecraft:block']?.length;
    if (entries == null) throw StateError('block registry 未摄入');
    return entries;
  }

  int get biomeCount => _registries['minecraft:worldgen/biome']?.length ?? 64;

  ChunkIngestor? _ingestor;
  int _sequence = 1; // use-item-on / player-action 的 ack 序号

  // 玩家状态（会话侧权威镜像；服务器强制同步时更新）
  double px = 0, py = 0, pz = 0, pyaw = 0, ppitch = 0;
  bool ponground = true, phorizontalCollision = false;
  bool _playPhase = false;
  bool _closed = false;

  /// 与 status ping 实测出的协议号校验（remote-play：版本不匹配给可操作提示）。
  /// 调用方只需提供服务器报告值——支持协议号由本包持有（26.2 实测值），
  /// `lib/` 无需接触版本包（隔离红线）。
  static void validateServerProtocol(int serverProtocol) =>
      validateProtocol(serverProtocol, ProtocolV262.measuredProtocolId);

  static void validateProtocol(int serverProtocol, int supported) {
    if (serverProtocol != supported) {
      throw DisconnectReason(
        '版本不匹配',
        detail: '客户端支持协议 $supported（26.2），服务器报告 $serverProtocol',
      );
    }
  }

  /// keep-alive 的 raw 回应映射（notes 1.2 #1）：载荷原样回，**id 换成 serverbound**。
  /// 26.2 play：clientbound 44 → serverbound 28；config：4 → 4（同 id 恰巧相同）。
  static int? _keepAliveResponse(ProtocolPhase phase, int packetId, Uint8List body) {
    if (phase == ProtocolPhase.play && packetId == PlayClientbound.keepAlive) {
      return PlayServerbound.keepAlive;
    }
    if (phase == ProtocolPhase.configuration && packetId == ConfigurationClientbound.keepAlive) {
      return ConfigurationServerbound.keepAlive;
    }
    return null;
  }

  Future<void> connect() async {
    final reg = buildRegistry26_2();
    _registry = reg;
    final conn = await WireConnection.connect(host, port, reg);
    _conn = conn;
    // keep-alive 走 raw 回应（载荷原样回、id 换 serverbound）；回应即刷新
    // 心跳时钟并启动超时巡检（原版节奏 15s/次，30s 未收到即链路死亡）。
    conn.rawEcho = (phase, packetId, body) {
      final responseId = _keepAliveResponse(phase, packetId, body);
      if (responseId != null) {
        _lastKeepAliveAt = DateTime.now();
        _keepAliveTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
          if (DateTime.now().difference(_lastKeepAliveAt) >= keepAliveTimeout) {
            _close(DisconnectReason(
              '心跳超时',
              detail: '超过 ${keepAliveTimeout.inSeconds} 秒未收到服务器 keep-alive'
                  '（原版节奏 15s/次）',
            ));
          }
        });
      }
      return responseId;
    };

    // 状态机/压缩必须同步生效（否则同批后续帧会用旧阈值解错）——用 onPacketSync
    conn.onPacketSync = _onInbound;
    conn.done.then((_) {
      _close(DisconnectReason('连接已断开'));
    }, onError: (Object e) {
      _close(DisconnectReason('连接异常', detail: e.toString()));
    });

    // 握手
    conn.sendRaw(
      ProtocolPhase.handshake,
      HandshakeServerbound.clientIntention,
      ClientIntention(protocolVersion: protocolId, hostName: host, port: port, intent: ClientIntent.login.id)
          .encodeBody(),
    );
    conn.phaseMachine.startFromHandshake(ClientIntent.login);

    // 登录：ServerboundHello（offline，无认证）
    final w = ByteWriter();
    w.writeUtf(playerName, 16);
    w.writeBytes(_offlineUuidBytes(playerName));
    conn.sendRaw(ProtocolPhase.login, LoginServerbound.hello, w.takeBytes());
  }

  /// offline UUID（`OfflinePlayer:<name>` 的 MD5 v3 —— 与原版一致的形式；
  /// offline 服务器实际以名字为准，此值仅满足协议必填字段）。
  static Uint8List _offlineUuidBytes(String name) {
    // 简化：SHA 系不可用时用名字字节填充固定形态（服务器 offline 模式不校验该字段）。
    final bytes = Uint8List(16);
    final src = Uint8List.fromList(name.codeUnits);
    for (var i = 0; i < 16; i++) {
      bytes[i] = src.length > i ? src[i] : (i * 31 + src.fold<int>(0, (a, b) => (a + b) & 0xFF)) & 0xFF;
    }
    // 置为 UUID v3 形态（与原版 offline UUID 相同的版本/变体位）
    bytes[6] = (bytes[6] & 0x0F) | 0x30;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;
    return bytes;
  }

  // —— inbound 分发 ——

  void _onInbound(InboundPacket<Object?> pkt) {
    final phase = pkt.phase;
    if (phase == ProtocolPhase.play && pkt.packetId == PlayClientbound.bundleDelimiter) {
      _onBundleDelimiter();
      return;
    }
    _dispatch(pkt);
  }

  final List<InboundPacket<Object?>> _bundleBuffer = [];
  bool _inBundle = false;

  /// bundle 定界（notes 1.2 / BundlerInfo.java）：delimiter 开始收集、再次出现时
  /// 依序分发（bundle 内包必须同 tick 处理）。
  void _onBundleDelimiter() {
    if (!_inBundle) {
      _inBundle = true;
      return;
    }
    _inBundle = false;
    final buffered = List.of(_bundleBuffer);
    _bundleBuffer.clear();
    for (final p in buffered) {
      _dispatch(p);
    }
  }

  void _dispatch(InboundPacket<Object?> pkt) {
    final phase = pkt.phase;
    final value = pkt.value;
    switch (value) {
      case final LoginDisconnect d:
        _close(_reasonFromNbt(d.reasonNbt, pkt));
      case final Disconnect d:
        _close(_reasonFromNbt(d.reasonNbt, pkt));
      case final LoginHelloEncryption _:
        // online-mode 服务器（remote-play 裁决：明确拒绝，可操作提示）
        _close(DisconnectReason(
          '该服务器要求正版账号认证',
          detail: '请在 server.properties 中设置 online-mode=false',
        ));
      case final LoginFinished _:
        _conn!.sendRaw(ProtocolPhase.login, LoginServerbound.loginAcknowledged, Uint8List(0));
        _conn!.phaseMachine.loginFinished();
        // 配置阶段开始即补 client information（notes 1.2 主动发送项；PrepareSpawnTask 用）
        _sendClientInformation();
      case final LoginCompression c:
        _conn!.setCompression(c.threshold);
      case final LoginCustomQuery q:
        _conn!.sendRaw(
          ProtocolPhase.login,
          LoginServerbound.customQueryAnswer,
          (ByteWriter()
                ..writeVarInt(q.messageId)
                ..writeBool(false))
              .takeBytes(),
        );
      case final CookieRequest k:
        _sendTyped(phase, CookieResponse(k.key));
      case final RegistryData rd:
        _registries.putIfAbsent(rd.registryName, () => []).addAll(rd.entries);
      case final SelectKnownPacks _:
        // 必须回应空列表，否则服务器的 SynchronizeRegistriesTask 永不完成（notes 1.2 #5）
        _sendTyped(ProtocolPhase.configuration, const SelectKnownPacks());
      case final UpdateTags _:
        break; // 摄取即可（当前不消费 tag 内容）
      case final CodeOfConduct _:
        _conn!.sendRaw(
          ProtocolPhase.configuration,
          ConfigurationServerbound.acceptCodeOfConduct,
          Uint8List(0),
        );
      case final FinishConfiguration _ when phase == ProtocolPhase.configuration:
        // finish configuration → acknowledge（notes 1.2 #10）
        _conn!.sendRaw(
          ProtocolPhase.configuration,
          ConfigurationServerbound.finishConfiguration,
          Uint8List(0),
        );
        _conn!.phaseMachine.configurationFinished();
      case final KeepAlive _:
        break; // raw 回应钩子已处理，不进事件流
      case final Ping p:
        _conn!.sendRaw(phase, _pongId(phase), (ByteWriter()..writeInt(p.id)).takeBytes());
      case final GameLogin login:
        _handleLogin(login);
      case final LevelChunkWithLight chunk:
        _handleChunk(chunk);
      case final ForgetLevelChunk f:
        _chunks.remove('${f.x}/${f.z}');
        _events.add(ChunkUnloaded(f.x, f.z));
      case final BlockUpdate b:
        _applyBlock(b.pos, b.stateId);
      case final SectionBlocksUpdate s:
        _applySection(s);
      case ChunkBatchStart():
        break; // 批次开始（回应在 finished 时）
      case final ChunkBatchFinished f:
        // 回应 chunk batch（notes 1.2 #12）；desired 上限对齐原版客户端策略 500
        _conn!.sendRaw(
          ProtocolPhase.play,
          PlayServerbound.chunkBatchReceived,
          (ByteWriter()
                ..writeFloat(min(f.chunksPerTick.toDouble(), 500.0)))
              .takeBytes(),
        );
      case final PlayerPosition pos:
        _handlePosition(pos);
      case final SetTime t:
        // 服务器时间同步（约每秒一次）：只取主世界 clock（内置 registry
        // overworld=0，判据 WorldClocks.java 注册顺序）；缺条目就忽略本次。
        final overworld = t.clocks[0];
        if (overworld != null) {
          _events.add(TimeUpdated(
            gameTime: t.gameTime,
            totalTicks: overworld.totalTicks,
            rate: overworld.rate,
          ));
        }
      case final EntityPositionSync e:
        // 服务器对自身实体的权威同步（宽松回拉：直接置位）
        _events.add(PositionCorrection(
          x: e.x,
          y: e.y,
          z: e.z,
          yRot: e.yRot,
          xRot: e.xRot,
          teleportId: -1,
          isTeleport: false,
        ));
      case final ViewDistanceUpdate _:
      case null:
        break; // 未登记包（实体/库存/聊天等范围外）：跳过 + 已计数（remote-play spec）
      default:
        break;
    }
  }

  int _pongId(ProtocolPhase phase) => phase == ProtocolPhase.configuration
      ? ConfigurationServerbound.pong
      : PlayServerbound.pong;

  void _handleLogin(GameLogin login) {
    _playPhase = true;
    _ingestor = ChunkIngestor();
    _events.add(JoinedGame(login));
    // ServerboundPlayerLoaded（notes 1.2 #11：60 tick 内不发则移动被静默忽略）
    _conn!.sendRaw(ProtocolPhase.play, PlayServerbound.playerLoaded, Uint8List(0));
  }

  void _sendClientInformation() {
    final vd = viewDistance;
    _sendTyped(
      ProtocolPhase.configuration,
      vd == null ? ClientInformation() : ClientInformation(viewDistance: vd),
    );
  }

  void _handleChunk(LevelChunkWithLight packet) {
    try {
      final chunk = (_ingestor ?? ChunkIngestor()).ingest(packet);
      _chunks['${packet.x}/${packet.z}'] = chunk;
      _events.add(ChunkLoaded(chunk));
    } on FormatException catch (e) {
      // 单列摄入失败不拖垮会话（对齐 E-22「只丢这一列」的既有纪律）
      _events.add(SessionClosed('chunk 摄入失败（${packet.x}/${packet.z}）：${e.message}'));
    }
  }

  void _applyBlock(McBlockPos pos, int stateId) {
    final cx = pos.x >> 4;
    final cz = pos.z >> 4;
    final chunk = _chunks['$cx/$cz'];
    if (chunk != null && chunk.applyBlockUpdate(pos, stateId)) {
      _events.add(BlockChanged(pos, stateId));
    }
  }

  void _applySection(SectionBlocksUpdate s) {
    final chunk = _chunks['${s.sectionX}/${s.sectionZ}'];
    if (chunk == null) return;
    if (!chunk.applySectionChanges(s.sectionX, s.sectionY, s.sectionZ, s.packedChanges)) {
      return;
    }
    // **整段一个批量事件**：水面/流体 tick 一包几十个方块且高频，逐方块
    // 发事件会让前端对同一段反复重网格化（debug 单段 ~40ms，海里越玩越卡，
    // 实测踩过）——重网格化必须按段去重后一次做。
    final changes = <({int lx, int ly, int lz, int stateId})>[];
    for (final p in s.packedChanges) {
      final local = p & 0xFFF;
      changes.add((
        lx: (local >> 8) & 15,
        ly: (local >> 4) & 15,
        lz: local & 15,
        stateId: p >>> 12,
      ));
    }
    _events.add(SectionChanged(
      sectionX: s.sectionX,
      sectionY: s.sectionY,
      sectionZ: s.sectionZ,
      changes: changes,
    ));
  }

  void _handlePosition(PlayerPosition pos) {
    // 相对标志（Relative 枚举位）：X=0,Y=1,Z=2,Y_ROT=3,X_ROT=4,DELTA_X=5..
    bool rel(int bit) {
      final longIdx = bit >> 6;
      if (longIdx >= pos.relativeFlags.length) return false;
      return (pos.relativeFlags[longIdx] >> (bit & 63)) & 1 == 1;
    }

    final isTeleport = pos.teleportId >= 0;
    final nx = rel(0) ? px + pos.x : pos.x;
    final ny = rel(1) ? py + pos.y : pos.y;
    final nz = rel(2) ? pz + pos.z : pos.z;
    final nyaw = rel(3) ? pyaw + pos.yRot : pos.yRot;
    final npitch = rel(4) ? ppitch + pos.xRot : pos.xRot;
    if (isTeleport) {
      px = nx;
      py = ny;
      pz = nz;
      pyaw = nyaw;
      ppitch = npitch;
      // 必须确认传送（ServerboundAcceptTeleportationPacket）
      _conn!.sendRaw(
        ProtocolPhase.play,
        PlayServerbound.acceptTeleportation,
        (ByteWriter()..writeVarInt(pos.teleportId)).takeBytes(),
      );
    }
    _events.add(PositionCorrection(
      x: nx,
      y: ny,
      z: nz,
      yRot: nyaw,
      xRot: npitch,
      teleportId: pos.teleportId,
      isTeleport: isTeleport,
    ));
  }

  DisconnectReason _reasonFromNbt(Uint8List nbt, [InboundPacket<Object?>? pkt]) {
    try {
      final root = NbtReader.readNetworkRoot(nbt);
      final text = _extractText(root);
      return DisconnectReason('服务器断开连接', detail: text.isEmpty ? null : text);
    } on Object catch (e) {
      // NBT 解析失败：保留字节级现场供排查
      return DisconnectReason(
        '服务器断开连接',
        detail: '${pkt == null ? '' : '${pkt.phase.name}/0x${pkt.packetId.toRadixString(16)} '}nbt=${nbt.length}B ${e.toString()}',
      );
    }
  }

  String _extractText(NbtCompound tag) {
    final text = tag['text'];
    if (text is NbtString && text.value.isNotEmpty) return text.value;
    final extra = tag['extra'];
    if (extra is NbtList) {
      final buf = StringBuffer();
      for (final e in extra.value) {
        if (e is NbtCompound) buf.write(_extractText(e));
      }
      return buf.toString();
    }
    final translate = tag['translate'];
    if (translate is NbtString) return translate.value;
    return '';
  }

  // —— 上行 API（调用方每 tick / 交互时调用） ——

  /// 每 tick 上报玩家状态（本地预测；design D6）。26.x 客户端 tick 语义：
  /// 移动包 + ClientTickEnd 成对发送（notes 1.2 #13）。
  void updatePlayer(double x, double y, double z, double yaw, double pitch,
      {required bool onGround, required bool horizontalCollision}) {
    if (!_playPhase || _closed) return;
    px = x;
    py = y;
    pz = z;
    pyaw = yaw;
    ppitch = pitch;
    ponground = onGround;
    phorizontalCollision = horizontalCollision;

    final posChanged = _lastSentX != x || _lastSentY != y || _lastSentZ != z;
    final rotChanged = _lastSentYaw != yaw || _lastSentPitch != pitch;
    final packet = posChanged && rotChanged
        ? MovePlayer.posRot(x, y, z, yaw, pitch, onGround: onGround, horizontalCollision: horizontalCollision)
        : posChanged
            ? MovePlayer.pos(x, y, z, onGround: onGround, horizontalCollision: horizontalCollision)
            : rotChanged
                ? MovePlayer.rot(yaw, pitch, onGround: onGround, horizontalCollision: horizontalCollision)
                : MovePlayer.statusOnly(onGround: onGround, horizontalCollision: horizontalCollision);
    _sendTyped(ProtocolPhase.play, packet);
    _lastSentX = x;
    _lastSentY = y;
    _lastSentZ = z;
    _lastSentYaw = yaw;
    _lastSentPitch = pitch;
    _sendTyped(ProtocolPhase.play, const ClientTickEnd());
  }

  double _lastSentX = double.nan, _lastSentY = 0, _lastSentZ = 0;
  double _lastSentYaw = 0, _lastSentPitch = 0;

  /// 挖掘时序（design D7；action：0=START 1=ABORT 2=STOP）。
  void sendPlayerAction(int action, McBlockPos pos, int direction) {
    if (!_playPhase || _closed) return;
    _sequence++;
    _sendTyped(ProtocolPhase.play, PlayerAction(action, pos, direction, _sequence - 1));
  }

  /// 放置方块（use-item-on；[cursor] 为命中面内 0..1 相对坐标）。
  void sendPlace(McBlockPos pos, int direction, {double cursor = 0.5}) {
    if (!_playPhase || _closed) return;
    _sendTyped(ProtocolPhase.play, UseItemOn(
      hand: 0,
      pos: pos,
      direction: direction,
      cursorX: cursor,
      cursorY: cursor,
      cursorZ: cursor,
      insideBlock: false,
      worldBorderHit: false,
      sequence: _sequence++,
    ));
  }

  /// 挥手（视觉同步；可选）。
  void sendSwing({int hand = 0}) {
    if (!_playPhase || _closed) return;
    _sendTyped(ProtocolPhase.play, Swing(hand));
  }

  void _sendTyped(ProtocolPhase phase, Object packet) {
    final conn = _conn;
    if (conn == null) return;
    final bytes = _registry!.encodeOutbound(phase, packet.runtimeType, packet);
    // encodeOutbound 产物已含 id 前缀，走 sendPacketBytes 直通（保留压缩/分帧）
    conn.sendPacketBytes(phase, bytes);
  }

  void _close(DisconnectReason reason) {
    if (_closed) return;
    _closed = true;
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    _events.add(SessionClosed(reason.toString()));
    _events.close();
    _conn?.close();
  }

  Future<void> close() async {
    _close(DisconnectReason('用户断开'));
  }
}
