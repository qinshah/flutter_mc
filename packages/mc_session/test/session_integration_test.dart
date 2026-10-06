import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:mc_session/mc_session.dart';
import 'package:mc_protocol_v26_2/mc_protocol_v26_2.dart';
import 'package:mc_wire/mc_wire.dart';
import 'package:test/test.dart';

import 'mock_login_server.dart';

/// 端到端集成（tasks 5.8 / 7.3）：真实 Socket + 脚本化 mock server。
///
/// 主流程测试走通 ping → 登录 → 配置 → 进服 → 收 chunk → 心跳/传送 →
/// 移动 → 优雅断开；7.3 组验证断线路径（服务器停机、心跳超时、online-mode
/// 拒绝、连接拒绝）均干净回退（SessionClosed + 事件流收口，不悬挂不崩溃）。
///
/// mock server 工作在**裸帧层**（共用脚本见 mock_login_server.dart）；
/// 26.2 编解码的字节正确性已由 mc_protocol_v26_2 的单测逐包验证，本测试
/// 验证的是**会话编排**。
void main() {
  late ServerSocket server;

  setUp(() async {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  });

  tearDown(() async {
    await server.close();
  });

  /// 起会话并收集事件，返回 (events, done)。
  (List<SessionEvent>, Future<void>) listenEvents(RemoteSession session) {
    final events = <SessionEvent>[];
    final done = Completer<void>();
    session.events.listen(events.add, onDone: done.complete);
    return (events, done.future);
  }

  test('ping → 登录 → 配置 → 进服 → 收 chunk → 移动 → 断开 全流程', () async {
    final session = RemoteSession(
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      playerName: 'flutter_mc',
    );
    final (events, done) = listenEvents(session);

    server.listen((client) {
      final mock = MockLoginClient(client);
      unawaited(() async {
        await mock.runToPlay();

        // 9) chunk batch + 单段 chunk + finished → 等 chunk batch received
        mock.send(PlayClientbound.chunkBatchStart, (_) {});
        mock.send(PlayClientbound.levelChunkWithLight, (w) => _chunkBody(w, 0, 0));
        mock.send(PlayClientbound.chunkBatchFinished, (w) => w.writeVarInt(10));
        await mock.expectPacket(PlayServerbound.chunkBatchReceived);

        // 10) keep-alive（play）→ 原样回应
        mock.sendPlayKeepAlive(0xABCDEF);
        await mock.expectPacket(PlayServerbound.keepAlive);
        final ka = mock.received[mock.cursor - 1];
        expect(ByteReader(ka.body).readLong(), 0xABCDEF);

        // 11) 传送（teleport id 7，绝对位置）→ 等 accept teleportation
        mock.send(PlayClientbound.playerPosition, (w) {
          w.writeVarInt(7);
          w.writeDouble(8.5);
          w.writeDouble(70.0);
          w.writeDouble(-3.25);
          w.writeDouble(0);
          w.writeDouble(0);
          w.writeDouble(0);
          w.writeFloat(90.0);
          w.writeFloat(0.0);
          w.writeVarInt(0); // 相对标志 bitset：空 = 全绝对
        });
        await mock.expectPacket(PlayServerbound.acceptTeleportation);
        expect(ByteReader(mock.received[mock.cursor - 1].body).readVarInt(), 7);

        // 12) 客户端移动上报（传送确认后调用 updatePlayer）
        session.updatePlayer(8.5, 70.0, -3.25, 90.0, 0.0,
            onGround: true, horizontalCollision: false);
        await mock.expectPacket(PlayServerbound.movePlayerPosRot);

        // 13) 方块更新（服务器权威回显）
        //     y 取 −60：本 mock 的 chunk 只发 **1 个段**，而 overworld 世界从 y=−64
        //     起（见 RemoteChunkColumn.minSectionY），故第 0 段覆盖 −64..−49。
        //     早先用 y=5——那是"世界从 0 起"的旧假设，段索引会越界。
        mock.send(PlayClientbound.blockUpdate, (w) {
          w.writeLong(McBlockPos(5, -60, 9).packLong());
          w.writeVarInt(1);
        });

        // 14) 断开：disconnect + 网络 NBT {text:"Bye"}
        mock.sendDisconnect('Bye');
      }());
    });

    await session.connect();
    session.updatePlayer(0, 0, 0, 0, 0, onGround: true, horizontalCollision: false);
    await done.timeout(const Duration(seconds: 15));

    // —— 断言 ——
    final joined = events.whereType<JoinedGame>().toList();
    expect(joined, hasLength(1), reason: 'events=$events');
    expect(joined.single.login.playerId, 42);

    final chunks = events.whereType<ChunkLoaded>().toList();
    expect(chunks, hasLength(1));
    final chunk = chunks.single.chunk;
    expect(chunk.x, 0);
    expect(chunk.z, 0);
    expect(chunk.sections, hasLength(1));
    // 调色板 [0=air,16=stone]；index 0x2A5 编码为 palette[1]=stone
    expect(chunk.sections[0][0x2A5], 16);
    expect(chunk.sections[0][0], 0);

    final tp = events.whereType<PositionCorrection>().firstWhere((c) => c.isTeleport);
    expect(tp.x, 8.5);
    expect(tp.y, 70.0);
    expect(tp.teleportId, 7);

    final blocks = events.whereType<BlockChanged>().toList();
    expect(blocks, hasLength(1));
    expect(blocks.single.pos.x, 5);
    expect(blocks.single.pos.y, -60);
    expect(blocks.single.stateId, 1);

    expect(events.whereType<SessionClosed>().single.reason, contains('Bye'));
  });

  test('pingServer 解析协议号与玩家数（对齐 tasks 1.1 实测形态）', () async {
    server.listen((client) {
      final decoder = FrameDecoder();
      client.listen(
        (data) {
          for (final f in decoder.push(data)) {
            final r = ByteReader(f);
            final id = r.readVarInt();
            if (id == 0) {
              final w = ByteWriter();
              w.writeVarInt(0);
              w.writeUtf(
                '{"version":{"name":"Paper 26.2","protocol":776},'
                '"players":{"max":20,"online":3},"description":{"text":"test"}}',
              );
              client.add(encodeFrame(w.takeBytes()));
          } else if (id == 1) {
            final w = ByteWriter();
            w.writeVarInt(1);
            w.writeLong(42);
            client.add(encodeFrame(w.takeBytes()));
            client.flush().then((_) => client.destroy()); // 干净收口
          }
          }
        },
        // pingProbe 用 destroy() 关连接（带未读数据 → RST），错误就地消化
        onError: (Object _) {},
        onDone: () {},
        cancelOnError: true,
      );
    });

    final info = await pingServer(InternetAddress.loopbackIPv4.address, server.port);
    expect(info.protocolId, 776);
    expect(info.versionName, 'Paper 26.2');
    expect(info.playersOnline, 3);
    expect(info.playersMax, 20);
  });

  // —— 7.3 断网/断线路径 ——

  test('服务器中途停机（socket 直接断开）→ SessionClosed，干净回退', () async {
    final session = RemoteSession(
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      playerName: 'flutter_mc',
    );
    final (events, done) = listenEvents(session);

    server.listen((client) {
      final mock = MockLoginClient(client);
      unawaited(() async {
        await mock.runToPlay();
        // 模拟服务器进程 kill：不给 disconnect 包，直接断 socket
        await Future<void>.delayed(const Duration(milliseconds: 50));
        mock.destroy();
      }());
    });

    await session.connect();
    await done.timeout(const Duration(seconds: 5));

    expect(events.whereType<JoinedGame>(), hasLength(1));
    final closed = events.whereType<SessionClosed>().single;
    expect(closed.reason, isNot(contains('心跳超时')));
  });

  test('心跳超时（30s 原版阈值；测试注入短时长）→ SessionClosed 心跳超时', () async {
    final session = RemoteSession(
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      playerName: 'flutter_mc',
      keepAliveTimeout: const Duration(milliseconds: 400),
    );
    final (events, done) = listenEvents(session);

    server.listen((client) {
      final mock = MockLoginClient(client);
      unawaited(() async {
        await mock.runToPlay();
        // 一次 keep-alive（回应后时钟启动），随后静默——原版服务器 15s/次，
        // 超过阈值无下一次即应判链路死亡
        mock.sendPlayKeepAlive(7);
        await mock.expectPacket(PlayServerbound.keepAlive);
        // 此后不再发任何包，等客户端超时
      }());
    });

    await session.connect();
    await done.timeout(const Duration(seconds: 5));

    expect(events.whereType<JoinedGame>(), hasLength(1));
    expect(events.whereType<SessionClosed>().single.reason, contains('心跳超时'));
  });

  test('online-mode 服务器（Login Hello）→ 明确拒绝 + 可操作提示（design D5）', () async {
    final session = RemoteSession(
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      playerName: 'flutter_mc',
    );
    final (events, done) = listenEvents(session);

    server.listen((client) {
      final mock = MockLoginClient(client);
      unawaited(() async {
        await mock.waitFrames(2); // handshake + hello
        sendLoginHello(mock); // 服务器要求正版认证
      }());
    });

    await session.connect();
    await done.timeout(const Duration(seconds: 5));

    final closed = events.whereType<SessionClosed>().single;
    expect(closed.reason, contains('正版账号'));
    expect(closed.reason, contains('online-mode=false'));
  });

  test('连接拒绝（端口没人听）→ connect 抛错，不悬挂', () async {
    // 起一个立刻关闭的 server 拿到已释放的端口
    final dead = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = dead.port;
    await dead.close();
    await Future<void>.delayed(const Duration(milliseconds: 300)); // 端口沉降

    final session = RemoteSession(
      host: InternetAddress.loopbackIPv4.address,
      port: port,
      playerName: 'flutter_mc',
    );

    await expectLater(
      () => session.connect().timeout(const Duration(seconds: 5)),
      throwsA(anything),
    );
  });
}

// —— chunk 包体（判据：ClientboundLevelChunkWithLightPacket + 26.x 容器格式） ——

void _chunkBody(ByteWriter w, int x, int z) {
  w.writeInt(x);
  w.writeInt(z);
  // heightmaps：空 map
  w.writeVarInt(0);
  // sections：1 段
  final section = ByteWriter();
  // 段头：nonEmptyBlockCount + fluidCount（判据 LevelChunkSection.write）
  section.writeShort(1);
  section.writeShort(0);
  // 方块容器：bits=1，间接调色板 [0=air,16=stone]，4096 条目 → 64 个 long
  section.writeUnsignedByte(1);
  section.writeVarInt(2);
  section.writeVarInt(0);
  section.writeVarInt(16);
  final longs = Uint64List(64);
  longs[0x2A5 ~/ 64] |= 1 << (0x2A5 % 64); // index 0x2A5 → palette[1]=stone
  for (var i = 0; i < 64; i++) {
    section.writeLong(longs[i]); // long 数组顺序 0..N（低 long 在前）
  }
  // 生物群系容器：bits=1，调色板 2 条，64 条目 → 64 long
  section.writeUnsignedByte(1);
  section.writeVarInt(2);
  section.writeVarInt(0);
  section.writeVarInt(1);
  section.writeLong(0); // bits=1 时 64 条目恰好占 1 个 long
  w.writeVarInt(section.length);
  w.writeBytes(section.takeBytes());
  // block entities：0
  w.writeVarInt(0);
  // light：4 bitset 全空 + 空 sky/block 列表
  for (var i = 0; i < 4; i++) {
    w.writeVarInt(0);
  }
  w.writeVarInt(0);
  w.writeVarInt(0);
}
