library;

import 'dart:typed_data';

import 'package:mc_nbt/mc_nbt.dart';
import 'package:mc_wire/mc_wire.dart';

import 'block_pos.dart';
import 'packets.dart';
import 'protocol_ids.dart' as ids;

/// 26.2 包编解码器与登记表（tasks 4.x）。
///
/// 每个编解码器注明判据类名（宪法五）；登记顺序无关紧要——数值 id 来自
/// `protocol_ids.dart` 的注册序推导，这里按 id 显式登记。

// —— 通用小工具 ——

String _readIdentifier(ByteReader r) => r.readUtf(32767);

/// 【形态 A】bool 前缀可选 NBT：`bool present + [类型字节 + 负载]`。
/// 用于 registry data entry 的 data（判据：RegistrySynchronization.PackedRegistryEntry
/// 用 `ByteBufCodecs.TAG.apply(ByteBufCodecs::optional)`，optional 即 bool 哨兵）。
Uint8List? _readOptionalNbtWithBool(ByteReader r) {
  if (!r.readBool()) return null;
  return _readRawTagSized(r);
}

/// 【形态 B】首字节即标签号的可选 NBT：`0 = null`，无 presence bool。
/// 用于 chunk 包的 block entity tag（判据：ClientboundLevelChunkPacketData.
/// BlockEntityInfo 用 `FriendlyByteBuf.readNbt` → `NbtIo.readAnyTag`，
/// 首字节 0 = null）。曾误用形态 A 导致非空 tag 整体错位 1 字节
/// （实测 chunk #73 刷怪笼 tag 触发解码崩溃）。
Uint8List? _readOptionalNbtRaw(ByteReader r) {
  final start = r.position;
  final rest = r.readRemaining();
  if (rest.isEmpty || rest[0] == 0) {
    r.position = start + 1;
    return null;
  }
  final parsed = NbtReader.readNetworkTagSized(rest);
  r.position = start + parsed.end; // 回退到 NBT 结束处（后面还有别的条目）
  return Uint8List.sublistView(rest, 0, parsed.end);
}

/// 从当前位置读一个非空网络 NBT 标签并定位到其结束处（原样保留字节）。
/// NBT 无长度前缀，用解析器自限界求出结束偏移。
Uint8List _readRawTagSized(ByteReader r) {
  final start = r.position;
  final rest = r.readRemaining();
  final parsed = NbtReader.readNetworkTagSized(rest);
  r.position = start + parsed.end;
  return Uint8List.sublistView(rest, 0, parsed.end);
}

void _writeNbtRaw(ByteWriter w, Uint8List raw) => w.writeBytes(raw);

/// bitSet（varint long 数组）。
List<int> _readBitSet(ByteReader r) {
  final longs = r.readVarInt();
  final out = <int>[];
  for (var i = 0; i < longs; i++) {
    out.add(r.readLong());
  }
  return out;
}

class _RawCodec extends PacketCodecBase<Object?> {
  _RawCodec();

  @override
  Object? decodeBody(ByteReader r) => r.readRemaining();

  @override
  void encodeBody(ByteWriter w, Object? packet) {
    w.writeBytes((packet as Uint8List?) ?? Uint8List(0));
  }
}

/// 半成品编解码基类：子类只处理**包体**（id 前缀由登记表处理）。
abstract class PacketCodecBase<T> implements PacketCodec<T> {
  @override
  T decode(ByteReader r) => decodeBody(r);

  T decodeBody(ByteReader r);

  @override
  void encode(ByteWriter w, T packet) => encodeBody(w, packet);

  void encodeBody(ByteWriter w, T packet);
}

// —— 各阶段编解码 ——

class _ClientIntentionCodec extends PacketCodecBase<ClientIntention> {
  @override
  ClientIntention decodeBody(ByteReader r) => throw UnsupportedError('客户端不发此包的解码');

  @override
  void encodeBody(ByteWriter w, ClientIntention p) => w.writeBytes(p.encodeBody());
}

class _StatusResponseCodec extends PacketCodecBase<StatusResponse> {
  @override
  StatusResponse decodeBody(ByteReader r) => StatusResponse(r.readUtf());

  @override
  void encodeBody(ByteWriter w, StatusResponse p) => w.writeUtf(p.json);
}

class _StatusPongResponseCodec extends PacketCodecBase<StatusPongResponse> {
  @override
  StatusPongResponse decodeBody(ByteReader r) => StatusPongResponse(r.readLong());

  @override
  void encodeBody(ByteWriter w, StatusPongResponse p) => w.writeLong(p.payload);
}

class _PingRequestCodec extends PacketCodecBase<StatusPongResponse> {
  @override
  StatusPongResponse decodeBody(ByteReader r) => throw UnsupportedError('客户端不发 status ping request 的解码');

  @override
  void encodeBody(ByteWriter w, StatusPongResponse p) => w.writeLong(p.payload);
}

class _LoginDisconnectCodec extends PacketCodecBase<LoginDisconnect> {
  @override
  LoginDisconnect decodeBody(ByteReader r) => LoginDisconnect(r.readRemaining());

  @override
  void encodeBody(ByteWriter w, LoginDisconnect p) => _writeNbtRaw(w, p.reasonNbt);
}

class _LoginHelloCodec extends PacketCodecBase<LoginHelloEncryption> {
  @override
  LoginHelloEncryption decodeBody(ByteReader r) => LoginHelloEncryption(
        r.readUtf(20),
        r.readByteArray(),
        r.readByteArray(),
        r.readBool(),
      );

  @override
  void encodeBody(ByteWriter w, LoginHelloEncryption p) => throw UnsupportedError('客户端只写不读');
}

class _LoginFinishedCodec extends PacketCodecBase<LoginFinished> {
  @override
  LoginFinished decodeBody(ByteReader r) {
    final uuid = r.readBytes(16);
    final name = r.readUtf(16);
    r.readBytes(16); // sessionId UUID（读了即丢）
    return LoginFinished(snapshot(uuid), name);
  }

  @override
  void encodeBody(ByteWriter w, LoginFinished p) => throw UnsupportedError('客户端只写不读');
}

class _LoginCompressionCodec extends PacketCodecBase<LoginCompression> {
  @override
  LoginCompression decodeBody(ByteReader r) => LoginCompression(r.readVarInt());

  @override
  void encodeBody(ByteWriter w, LoginCompression p) => w.writeVarInt(p.threshold);
}

class _LoginCustomQueryCodec extends PacketCodecBase<LoginCustomQuery> {
  @override
  LoginCustomQuery decodeBody(ByteReader r) {
    final messageId = r.readVarInt();
    final identifier = _readIdentifier(r);
    return LoginCustomQuery(messageId, identifier, snapshot(r.readRemaining()));
  }

  @override
  void encodeBody(ByteWriter w, LoginCustomQuery p) => throw UnsupportedError('客户端只写不读');
}

class _CookieRequestCodec extends PacketCodecBase<CookieRequest> {
  @override
  CookieRequest decodeBody(ByteReader r) => CookieRequest(_readIdentifier(r));

  @override
  void encodeBody(ByteWriter w, CookieRequest p) => w.writeUtf(p.key);
}

class _KeepAliveCodec extends PacketCodecBase<KeepAlive> {
  @override
  KeepAlive decodeBody(ByteReader r) => KeepAlive(r.readLong());

  @override
  void encodeBody(ByteWriter w, KeepAlive p) => w.writeLong(p.id);
}

class _PingCodec extends PacketCodecBase<Ping> {
  @override
  Ping decodeBody(ByteReader r) => Ping(r.readLong());

  @override
  void encodeBody(ByteWriter w, Ping p) => w.writeInt(p.id); // SB Pong 为 int（REF: ServerboundPongPacket）
}

class _DisconnectCodec extends PacketCodecBase<Disconnect> {
  @override
  Disconnect decodeBody(ByteReader r) => Disconnect(r.readRemaining());

  @override
  void encodeBody(ByteWriter w, Disconnect p) => _writeNbtRaw(w, p.reasonNbt);
}

class _RegistryDataCodec extends PacketCodecBase<RegistryData> {
  @override
  RegistryData decodeBody(ByteReader r) {
    final registryName = _readIdentifier(r);
    final count = r.readVarInt();
    final entries = <RegistryEntry>[];
    for (var i = 0; i < count; i++) {
      final id = _readIdentifier(r);
      final data = _readOptionalNbtWithBool(r);
      entries.add(RegistryEntry(id, data));
    }
    return RegistryData(registryName, entries);
  }

  @override
  void encodeBody(ByteWriter w, RegistryData p) => throw UnsupportedError('客户端只写不读');
}

class _FinishConfigurationCodec extends PacketCodecBase<FinishConfiguration> {
  @override
  FinishConfiguration decodeBody(ByteReader r) => const FinishConfiguration();

  @override
  void encodeBody(ByteWriter w, FinishConfiguration p) {}
}

class _UpdateTagsCodec extends PacketCodecBase<UpdateTags> {
  @override
  UpdateTags decodeBody(ByteReader r) {
    final registryCount = r.readVarInt();
    final data = <String, Map<String, List<int>>>{};
    for (var i = 0; i < registryCount; i++) {
      final registry = _readIdentifier(r);
      final tagCount = r.readVarInt();
      final tags = <String, List<int>>{};
      for (var j = 0; j < tagCount; j++) {
        final tag = _readIdentifier(r);
        final len = r.readVarInt();
        final values = <int>[];
        for (var k = 0; k < len; k++) {
          values.add(r.readVarInt());
        }
        tags[tag] = values;
      }
      data[registry] = tags;
    }
    return UpdateTags(data);
  }

  @override
  void encodeBody(ByteWriter w, UpdateTags p) => throw UnsupportedError('客户端只写不读');
}

class _CodeOfConductCodec extends PacketCodecBase<CodeOfConduct> {
  @override
  CodeOfConduct decodeBody(ByteReader r) => CodeOfConduct(r.readUtf());

  @override
  void encodeBody(ByteWriter w, CodeOfConduct p) => w.writeUtf(p.text);
}

class _ClientInformationCodec extends PacketCodecBase<ClientInformation> {
  @override
  ClientInformation decodeBody(ByteReader r) => throw UnsupportedError('客户端只写不读');

  @override
  void encodeBody(ByteWriter w, ClientInformation p) => p.encodeBody(w);
}

class _SelectKnownPacksCodec extends PacketCodecBase<SelectKnownPacks> {
  @override
  SelectKnownPacks decodeBody(ByteReader r) {
    final count = r.readVarInt();
    for (var i = 0; i < count; i++) {
      _readIdentifier(r);
      r.readUtf(); // version
    }
    return const SelectKnownPacks();
  }

  @override
  void encodeBody(ByteWriter w, SelectKnownPacks p) => w.writeVarInt(0); // 空列表
}

class _ResourcePackResponseCodec extends PacketCodecBase<ResourcePackResponse> {
  @override
  ResourcePackResponse decodeBody(ByteReader r) => throw UnsupportedError('客户端只写不读');

  @override
  void encodeBody(ByteWriter w, ResourcePackResponse p) {
    w.writeBytes(p.uuid);
    w.writeVarInt(p.action.index);
  }
}

class _GameLoginCodec extends PacketCodecBase<GameLogin> {
  @override
  GameLogin decodeBody(ByteReader r) {
    final playerId = r.readInt();
    r.readBool(); // hardcore
    final levelCount = r.readVarInt();
    final levelNames = <String>[];
    for (var i = 0; i < levelCount; i++) {
      levelNames.add(_readIdentifier(r));
    }
    final maxPlayers = r.readVarInt();
    final chunkRadius = r.readVarInt();
    final simulationDistance = r.readVarInt();
    r.readBool(); // reducedDebugInfo
    r.readBool(); // showDeathScreen
    r.readBool(); // doLimitedCrafting
    // CommonPlayerSpawnInfo
    final dimensionType = _readIdentifier(r);
    final dimension = _readIdentifier(r);
    final hashedSeed = r.readLong();
    final gameType = r.readUnsignedByte();
    final previousGameType = r.readUnsignedByte();
    final isDebug = r.readBool();
    final isFlat = r.readBool();
    // lastDeathLocation: optional GlobalPos（identifier + long）
    if (r.readBool()) {
      _readIdentifier(r);
      r.readLong();
    }
    final portalCooldown = r.readVarInt();
    final seaLevel = r.readVarInt();
    r.readBool(); // onlineMode
    r.readBool(); // enforcesSecureChat
    return GameLogin(
      playerId: playerId,
      levelNames: levelNames,
      maxPlayers: maxPlayers,
      chunkRadius: chunkRadius,
      simulationDistance: simulationDistance,
      dimensionType: dimensionType,
      dimension: dimension,
      hashedSeed: hashedSeed,
      gameType: gameType,
      previousGameType: previousGameType == 0xFF ? -1 : previousGameType,
      isDebug: isDebug,
      isFlat: isFlat,
      portalCooldown: portalCooldown,
      seaLevel: seaLevel,
    );
  }

  @override
  void encodeBody(ByteWriter w, GameLogin p) => throw UnsupportedError('客户端只写不读');
}

class _LevelChunkWithLightCodec extends PacketCodecBase<LevelChunkWithLight> {
  @override
  LevelChunkWithLight decodeBody(ByteReader r) {
    final x = r.readInt();
    final z = r.readInt();
    // heightmaps: map（varint count）of (varint type + long array)
    final hmCount = r.readVarInt();
    final hmTypes = <int>[];
    final hmData = <Uint8List>[];
    for (var i = 0; i < hmCount; i++) {
      hmTypes.add(r.readVarInt());
      final longCount = r.readVarInt();
      final bytes = ByteWriter();
      for (var j = 0; j < longCount; j++) {
        bytes.writeLong(r.readLong());
      }
      hmData.add(bytes.takeBytes());
    }
    // sections buffer
    final size = r.readVarInt();
    if (size > 2097152) throw FormatException('chunk buffer 超限：$size');
    final buffer = snapshot(r.readBytes(size));
    // block entities
    final beCount = r.readVarInt();
    final blockEntities = <BlockEntityInfo>[];
    for (var i = 0; i < beCount; i++) {
      final packedXZ = r.readUnsignedByte();
      final y = r.readShort();
      final type = r.readVarInt();
      final tag = _readOptionalNbtRaw(r);
      blockEntities.add(BlockEntityInfo(packedXZ, y, type, tag));
    }
    // light
    final skyYMask = _readBitSet(r);
    final blockYMask = _readBitSet(r);
    final emptySkyYMask = _readBitSet(r);
    final emptyBlockYMask = _readBitSet(r);
    Uint8List readLayer() {
      final len = r.readVarInt();
      return snapshot(r.readBytes(len.clamp(0, 2048)));
    }

    final skyCount = r.readVarInt();
    final skyUpdates = <Uint8List>[for (var i = 0; i < skyCount; i++) readLayer()];
    final blockCount = r.readVarInt();
    final blockUpdates = <Uint8List>[for (var i = 0; i < blockCount; i++) readLayer()];

    return LevelChunkWithLight(
      x: x,
      z: z,
      heightmapTypes: hmTypes,
      heightmapData: hmData,
      sectionsBuffer: buffer,
      blockEntities: blockEntities,
      skyYMask: skyYMask,
      blockYMask: blockYMask,
      emptySkyYMask: emptySkyYMask,
      emptyBlockYMask: emptyBlockYMask,
      skyUpdates: skyUpdates,
      blockUpdates: blockUpdates,
    );
  }

  @override
  void encodeBody(ByteWriter w, LevelChunkWithLight p) => throw UnsupportedError('客户端只写不读');
}

class _BlockUpdateCodec extends PacketCodecBase<BlockUpdate> {
  @override
  BlockUpdate decodeBody(ByteReader r) => BlockUpdate(
        McBlockPos.unpackLong(r.readLong()),
        r.readVarInt(),
      );

  @override
  void encodeBody(ByteWriter w, BlockUpdate p) => throw UnsupportedError('客户端只写不读');
}

class _SectionBlocksUpdateCodec extends PacketCodecBase<SectionBlocksUpdate> {
  @override
  SectionBlocksUpdate decodeBody(ByteReader r) {
    // ChunkSectionPos.asLong：x 22 位 @42、z 22 位 @20、y 20 位 @0（判据：SectionPos.STREAM_CODEC）
    final l = r.readLong();
    final sx = l >> 42;
    final sz = (l << 22) >> 42;
    final sy = (l << 44) >> 44;
    final count = r.readVarInt();
    final changes = <int>[];
    for (var i = 0; i < count; i++) {
      changes.add(r.readVarLong());
    }
    return SectionBlocksUpdate(sx, sy, sz, changes);
  }

  @override
  void encodeBody(ByteWriter w, SectionBlocksUpdate p) => throw UnsupportedError('客户端只写不读');
}

class _ForgetLevelChunkCodec extends PacketCodecBase<ForgetLevelChunk> {
  @override
  ForgetLevelChunk decodeBody(ByteReader r) {
    final pos = McChunkPos.unpackLong(r.readLong());
    return ForgetLevelChunk(pos.x, pos.z);
  }

  @override
  void encodeBody(ByteWriter w, ForgetLevelChunk p) => w.writeLong(McChunkPos(p.x, p.z).packLong());
}

class _ChunkBatchStartCodec extends PacketCodecBase<ChunkBatchStart> {
  @override
  ChunkBatchStart decodeBody(ByteReader r) => const ChunkBatchStart();

  @override
  void encodeBody(ByteWriter w, ChunkBatchStart p) {}
}

class _ChunkBatchFinishedCodec extends PacketCodecBase<ChunkBatchFinished> {
  @override
  ChunkBatchFinished decodeBody(ByteReader r) => ChunkBatchFinished(r.readVarInt());

  @override
  void encodeBody(ByteWriter w, ChunkBatchFinished p) => w.writeVarInt(p.chunksPerTick);
}

class _SetTimeCodec extends PacketCodecBase<SetTime> {
  @override
  SetTime decodeBody(ByteReader r) {
    final gameTime = r.readLong();
    final count = r.readVarInt();
    final clocks = <int, ClockNetworkState>{};
    for (var i = 0; i < count; i++) {
      final id = r.readVarInt();
      final totalTicks = r.readVarLong();
      final partialTick = r.readFloat();
      final rate = r.readFloat();
      clocks[id] = ClockNetworkState(
        totalTicks: totalTicks,
        partialTick: partialTick,
        rate: rate,
      );
    }
    return SetTime(gameTime: gameTime, clocks: clocks);
  }

  @override
  void encodeBody(ByteWriter w, SetTime p) {
    w.writeLong(p.gameTime);
    w.writeVarInt(p.clocks.length);
    p.clocks.forEach((id, c) {
      w.writeVarInt(id);
      w.writeVarLong(c.totalTicks);
      w.writeFloat(c.partialTick);
      w.writeFloat(c.rate);
    });
  }
}

class _PlayerPositionCodec extends PacketCodecBase<PlayerPosition> {
  @override
  PlayerPosition decodeBody(ByteReader r) {
    final id = r.readVarInt();
    final x = r.readDouble();
    final y = r.readDouble();
    final z = r.readDouble();
    final dx = r.readDouble();
    final dy = r.readDouble();
    final dz = r.readDouble();
    final yRot = r.readFloat();
    final xRot = r.readFloat();
    final flags = _readBitSet(r);
    return PlayerPosition(
      teleportId: id,
      x: x,
      y: y,
      z: z,
      dx: dx,
      dy: dy,
      dz: dz,
      yRot: yRot,
      xRot: xRot,
      relativeFlags: flags,
    );
  }

  @override
  void encodeBody(ByteWriter w, PlayerPosition p) => throw UnsupportedError('客户端只写不读');
}

class _EntityPositionSyncCodec extends PacketCodecBase<EntityPositionSync> {
  @override
  EntityPositionSync decodeBody(ByteReader r) {
    final entityId = r.readVarInt();
    final x = r.readDouble();
    final y = r.readDouble();
    final z = r.readDouble();
    final dx = r.readDouble();
    final dy = r.readDouble();
    final dz = r.readDouble();
    final yRot = r.readFloat();
    final xRot = r.readFloat();
    final onGround = r.readBool();
    return EntityPositionSync(
      entityId: entityId,
      x: x,
      y: y,
      z: z,
      dx: dx,
      dy: dy,
      dz: dz,
      yRot: yRot,
      xRot: xRot,
      onGround: onGround,
    );
  }

  @override
  void encodeBody(ByteWriter w, EntityPositionSync p) => throw UnsupportedError('客户端只写不读');
}

class _CacheCenterCodec extends PacketCodecBase<ViewDistanceUpdate> {
  @override
  ViewDistanceUpdate decodeBody(ByteReader r) => ViewDistanceUpdate(r.readVarInt(), r.readVarInt());

  @override
  void encodeBody(ByteWriter w, ViewDistanceUpdate p) => throw UnsupportedError('客户端只写不读');
}

class _SingleVarintCodec extends PacketCodecBase<ViewDistanceUpdate> {
  @override
  ViewDistanceUpdate decodeBody(ByteReader r) => ViewDistanceUpdate(r.readVarInt(), 0);

  @override
  void encodeBody(ByteWriter w, ViewDistanceUpdate p) => throw UnsupportedError('客户端只写不读');
}

class _GameEventCodec extends PacketCodecBase<GameEvent> {
  @override
  GameEvent decodeBody(ByteReader r) => GameEvent(r.readUnsignedByte(), r.readFloat());

  @override
  void encodeBody(ByteWriter w, GameEvent p) => throw UnsupportedError('客户端只写不读');
}

class _MovePlayerCodec extends PacketCodecBase<MovePlayer> {
  @override
  MovePlayer decodeBody(ByteReader r) => throw UnsupportedError('客户端只写不读');

  @override
  void encodeBody(ByteWriter w, MovePlayer p) => p.encodeBody(w);
}

class _PlayerLoadedCodec extends PacketCodecBase<PlayerLoaded> {
  @override
  PlayerLoaded decodeBody(ByteReader r) => const PlayerLoaded();

  @override
  void encodeBody(ByteWriter w, PlayerLoaded p) {}
}

class _ClientTickEndCodec extends PacketCodecBase<ClientTickEnd> {
  @override
  ClientTickEnd decodeBody(ByteReader r) => const ClientTickEnd();

  @override
  void encodeBody(ByteWriter w, ClientTickEnd p) {}
}

class _ChunkBatchReceivedCodec extends PacketCodecBase<ChunkBatchReceived> {
  @override
  ChunkBatchReceived decodeBody(ByteReader r) => throw UnsupportedError('客户端只写不读');

  @override
  void encodeBody(ByteWriter w, ChunkBatchReceived p) => w.writeFloat(p.desiredChunksPerTick);
}

class _PlayerInputCodec extends PacketCodecBase<PlayerInputPacket> {
  @override
  PlayerInputPacket decodeBody(ByteReader r) =>
      throw UnsupportedError('客户端只写不读');

  @override
  void encodeBody(ByteWriter w, PlayerInputPacket p) {
    w.writeUnsignedByte(p.input.pack());
  }
}

class _PlayerAbilitiesInCodec extends PacketCodecBase<PlayerAbilitiesIn> {
  @override
  PlayerAbilitiesIn decodeBody(ByteReader r) {
    final flags = r.readUnsignedByte();
    final flyingSpeed = r.readFloat();
    final walkingSpeed = r.readFloat();
    return PlayerAbilitiesIn(
      invulnerable: (flags & 1) != 0,
      flying: (flags & 2) != 0,
      mayfly: (flags & 4) != 0,
      instabuild: (flags & 8) != 0,
      flyingSpeed: flyingSpeed,
      walkingSpeed: walkingSpeed,
    );
  }

  @override
  void encodeBody(ByteWriter w, PlayerAbilitiesIn p) =>
      throw UnsupportedError('客户端只读不写');
}

class _PlayerAbilitiesOutCodec extends PacketCodecBase<PlayerAbilitiesOut> {
  @override
  PlayerAbilitiesOut decodeBody(ByteReader r) =>
      throw UnsupportedError('客户端只写不读');

  @override
  void encodeBody(ByteWriter w, PlayerAbilitiesOut p) {
    w.writeUnsignedByte(p.flying ? 2 : 0);
  }
}

class _PlayerActionCodec extends PacketCodecBase<PlayerAction> {
  @override
  PlayerAction decodeBody(ByteReader r) => throw UnsupportedError('客户端只写不读');

  @override
  void encodeBody(ByteWriter w, PlayerAction p) {
    w.writeVarInt(p.action);
    w.writeLong(p.pos.packLong());
    w.writeUnsignedByte(p.direction);
    w.writeVarInt(p.sequence);
  }
}

class _UseItemOnCodec extends PacketCodecBase<UseItemOn> {
  @override
  UseItemOn decodeBody(ByteReader r) => throw UnsupportedError('客户端只写不读');

  @override
  void encodeBody(ByteWriter w, UseItemOn p) {
    w.writeVarInt(p.hand);
    w.writeLong(p.pos.packLong());
    w.writeVarInt(p.direction);
    w.writeFloat(p.cursorX);
    w.writeFloat(p.cursorY);
    w.writeFloat(p.cursorZ);
    w.writeBool(p.insideBlock);
    w.writeBool(p.worldBorderHit);
    w.writeVarInt(p.sequence);
  }
}

class _SwingCodec extends PacketCodecBase<Swing> {
  @override
  Swing decodeBody(ByteReader r) => throw UnsupportedError('客户端只写不读');

  @override
  void encodeBody(ByteWriter w, Swing p) => w.writeVarInt(p.hand);
}

class _AcceptTeleportationCodec extends PacketCodecBase<AcceptTeleportation> {
  @override
  AcceptTeleportation decodeBody(ByteReader r) => throw UnsupportedError('客户端只写不读');

  @override
  void encodeBody(ByteWriter w, AcceptTeleportation p) => w.writeVarInt(p.id);
}

class _LoginAcknowledgedCodec extends PacketCodecBase<LoginAcknowledged> {
  @override
  LoginAcknowledged decodeBody(ByteReader r) => throw UnsupportedError('客户端只写不读');

  @override
  void encodeBody(ByteWriter w, LoginAcknowledged p) {}
}

class _HelloCodec extends PacketCodecBase<ServerboundHello> {
  @override
  ServerboundHello decodeBody(ByteReader r) => throw UnsupportedError('客户端只写不读');

  @override
  void encodeBody(ByteWriter w, ServerboundHello p) {
    w.writeUtf(p.name, 16);
    w.writeBytes(p.uuid);
  }
}

class _CustomQueryAnswerCodec extends PacketCodecBase<CustomQueryAnswer> {
  @override
  CustomQueryAnswer decodeBody(ByteReader r) => throw UnsupportedError('客户端只写不读');

  @override
  void encodeBody(ByteWriter w, CustomQueryAnswer p) {
    w.writeVarInt(p.messageId);
    w.writeBool(false); // 无 payload
  }
}

class _CookieResponseCodec extends PacketCodecBase<CookieResponse> {
  @override
  CookieResponse decodeBody(ByteReader r) => throw UnsupportedError('客户端只写不读');

  @override
  void encodeBody(ByteWriter w, CookieResponse p) {
    w.writeUtf(p.key);
    w.writeBool(false); // 无 payload
  }
}

/// 构建 26.2 的包登记表（供 mc_session 装配进 [WireConnection]）。
PacketRegistry buildRegistry26_2() {
  final reg = PacketRegistry();
  void inb(ProtocolPhase phase, int id, PacketCodecBase<Object?> codec) {
    reg.registerInbound(phase, id, codec);
  }

  void outb(ProtocolPhase phase, int id, Object type, PacketCodecBase<Object?> codec) {
    reg.registerOutbound(phase, id, type, codec);
  }

  // —— handshake（SB）——
  outb(ProtocolPhase.handshake, ids.HandshakeServerbound.clientIntention, ClientIntention,
      _ClientIntentionCodec());

  // —— status ——
  inb(ProtocolPhase.status, 0, _StatusResponseCodec());
  inb(ProtocolPhase.status, 1, _StatusPongResponseCodec());
  outb(ProtocolPhase.status, 0, StatusRequest, _RawCodec());
  outb(ProtocolPhase.status, 1, StatusPongResponse, _PingRequestCodec());

  // —— login ——
  inb(ProtocolPhase.login, ids.LoginClientbound.loginDisconnect, _LoginDisconnectCodec());
  inb(ProtocolPhase.login, ids.LoginClientbound.hello, _LoginHelloCodec());
  inb(ProtocolPhase.login, ids.LoginClientbound.loginFinished, _LoginFinishedCodec());
  inb(ProtocolPhase.login, ids.LoginClientbound.loginCompression, _LoginCompressionCodec());
  inb(ProtocolPhase.login, ids.LoginClientbound.customQuery, _LoginCustomQueryCodec());
  inb(ProtocolPhase.login, ids.LoginClientbound.cookieRequest, _CookieRequestCodec());
  outb(ProtocolPhase.login, ids.LoginServerbound.hello, ServerboundHello, _HelloCodec());
  outb(ProtocolPhase.login, ids.LoginServerbound.customQueryAnswer, CustomQueryAnswer,
      _CustomQueryAnswerCodec());
  outb(ProtocolPhase.login, ids.LoginServerbound.loginAcknowledged, LoginAcknowledged,
      _LoginAcknowledgedCodec());
  outb(ProtocolPhase.login, ids.LoginServerbound.cookieResponse, CookieResponse,
      _CookieResponseCodec());

  // —— configuration ——
  inb(ProtocolPhase.configuration, ids.ConfigurationClientbound.cookieRequest, _CookieRequestCodec());
  inb(ProtocolPhase.configuration, ids.ConfigurationClientbound.disconnect, _DisconnectCodec());
  inb(ProtocolPhase.configuration, ids.ConfigurationClientbound.finishConfiguration,
      _FinishConfigurationCodec());
  inb(ProtocolPhase.configuration, ids.ConfigurationClientbound.keepAlive, _KeepAliveCodec());
  inb(ProtocolPhase.configuration, ids.ConfigurationClientbound.ping, _PingCodec());
  inb(ProtocolPhase.configuration, ids.ConfigurationClientbound.registryData, _RegistryDataCodec());
  inb(ProtocolPhase.configuration, ids.ConfigurationClientbound.updateTags, _UpdateTagsCodec());
  inb(ProtocolPhase.configuration, ids.ConfigurationClientbound.selectKnownPacks,
      _SelectKnownPacksCodec());
  inb(ProtocolPhase.configuration, ids.ConfigurationClientbound.codeOfConduct, _CodeOfConductCodec());
  outb(ProtocolPhase.configuration, ids.ConfigurationServerbound.clientInformation, ClientInformation,
      _ClientInformationCodec());
  outb(ProtocolPhase.configuration, ids.ConfigurationServerbound.finishConfiguration,
      FinishConfiguration, _FinishConfigurationCodec());
  outb(ProtocolPhase.configuration, ids.ConfigurationServerbound.keepAlive, KeepAlive, _KeepAliveCodec());
  outb(ProtocolPhase.configuration, ids.ConfigurationServerbound.pong, Ping, _PingCodec());
  outb(ProtocolPhase.configuration, ids.ConfigurationServerbound.resourcePack, ResourcePackResponse,
      _ResourcePackResponseCodec());
  outb(ProtocolPhase.configuration, ids.ConfigurationServerbound.selectKnownPacks, SelectKnownPacks,
      _SelectKnownPacksCodec());
  outb(ProtocolPhase.configuration, ids.ConfigurationServerbound.acceptCodeOfConduct, CodeOfConduct,
      _CodeOfConductCodec());
  outb(ProtocolPhase.configuration, ids.ConfigurationServerbound.cookieResponse, CookieResponse,
      _CookieResponseCodec());

  // —— play：clientbound ——
  inb(ProtocolPhase.play, ids.PlayClientbound.keepAlive, _KeepAliveCodec());
  inb(ProtocolPhase.play, ids.PlayClientbound.ping, _PingCodec());
  inb(ProtocolPhase.play, ids.PlayClientbound.disconnect, _DisconnectCodec());
  inb(ProtocolPhase.play, ids.PlayClientbound.login, _GameLoginCodec());
  inb(ProtocolPhase.play, ids.PlayClientbound.levelChunkWithLight, _LevelChunkWithLightCodec());
  inb(ProtocolPhase.play, ids.PlayClientbound.blockUpdate, _BlockUpdateCodec());
  inb(ProtocolPhase.play, ids.PlayClientbound.sectionBlocksUpdate, _SectionBlocksUpdateCodec());
  inb(ProtocolPhase.play, ids.PlayClientbound.forgetLevelChunk, _ForgetLevelChunkCodec());
  inb(ProtocolPhase.play, ids.PlayClientbound.chunkBatchStart, _ChunkBatchStartCodec());
  inb(ProtocolPhase.play, ids.PlayClientbound.chunkBatchFinished, _ChunkBatchFinishedCodec());
  inb(ProtocolPhase.play, ids.PlayClientbound.setTime, _SetTimeCodec());
  inb(ProtocolPhase.play, ids.PlayClientbound.playerPosition, _PlayerPositionCodec());
  inb(ProtocolPhase.play, ids.PlayClientbound.playerRotation, _RawCodec());
  inb(ProtocolPhase.play, ids.PlayClientbound.entityPositionSync, _EntityPositionSyncCodec());
  inb(ProtocolPhase.play, ids.PlayClientbound.setChunkCacheCenter, _CacheCenterCodec());
  inb(ProtocolPhase.play, ids.PlayClientbound.setChunkCacheRadius, _SingleVarintCodec());
  inb(ProtocolPhase.play, ids.PlayClientbound.setSimulationDistance, _SingleVarintCodec());
  inb(ProtocolPhase.play, ids.PlayClientbound.gameEvent, _GameEventCodec());
  inb(ProtocolPhase.play, ids.PlayClientbound.updateTags, _UpdateTagsCodec());
  inb(ProtocolPhase.play, ids.PlayClientbound.respawn, _RawCodec());
  inb(ProtocolPhase.play, ids.PlayClientbound.playerAbilities, _PlayerAbilitiesInCodec());

  // —— play：serverbound ——
  outb(ProtocolPhase.play, ids.PlayServerbound.keepAlive, KeepAlive, _KeepAliveCodec());
  outb(ProtocolPhase.play, ids.PlayServerbound.pong, Ping, _PingCodec());
  outb(ProtocolPhase.play, ids.PlayServerbound.clientInformation, ClientInformation,
      _ClientInformationCodec());
  // 变体是独立的具体类型（私有实现类），按 runtimeType 查 id：
  // pos→30 / posRot→31 / rot→32 / statusOnly→33（判据：GameProtocols 注册序）
  final movePos = MovePlayer.pos(0, 0, 0, onGround: false, horizontalCollision: false);
  final movePosRot =
      MovePlayer.posRot(0, 0, 0, 0, 0, onGround: false, horizontalCollision: false);
  final moveRot = MovePlayer.rot(0, 0, onGround: false, horizontalCollision: false);
  final moveStatus = MovePlayer.statusOnly(onGround: false, horizontalCollision: false);
  outb(ProtocolPhase.play, ids.PlayServerbound.movePlayerPos, movePos.runtimeType, _MovePlayerCodec());
  outb(ProtocolPhase.play, ids.PlayServerbound.movePlayerPosRot, movePosRot.runtimeType,
      _MovePlayerCodec());
  outb(ProtocolPhase.play, ids.PlayServerbound.movePlayerRot, moveRot.runtimeType, _MovePlayerCodec());
  outb(ProtocolPhase.play, ids.PlayServerbound.movePlayerStatusOnly, moveStatus.runtimeType,
      _MovePlayerCodec());
  outb(ProtocolPhase.play, ids.PlayServerbound.playerLoaded, PlayerLoaded, _PlayerLoadedCodec());
  outb(ProtocolPhase.play, ids.PlayServerbound.clientTickEnd, ClientTickEnd, _ClientTickEndCodec());
  outb(ProtocolPhase.play, ids.PlayServerbound.chunkBatchReceived, ChunkBatchReceived,
      _ChunkBatchReceivedCodec());
  outb(ProtocolPhase.play, ids.PlayServerbound.playerAction, PlayerAction, _PlayerActionCodec());
  outb(ProtocolPhase.play, ids.PlayServerbound.useItemOn, UseItemOn, _UseItemOnCodec());
  outb(ProtocolPhase.play, ids.PlayServerbound.playerInput, PlayerInputPacket,
      _PlayerInputCodec());
  outb(ProtocolPhase.play, ids.PlayServerbound.playerAbilities, PlayerAbilitiesOut,
      _PlayerAbilitiesOutCodec());
  outb(ProtocolPhase.play, ids.PlayServerbound.swing, Swing, _SwingCodec());
  outb(ProtocolPhase.play, ids.PlayServerbound.acceptTeleportation, AcceptTeleportation,
      _AcceptTeleportationCodec());

  return reg;
}

/// status 请求的哨兵类型（空包体）。
final class StatusRequest {
  const StatusRequest();
}
