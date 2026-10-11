library;

import 'dart:typed_data';

import 'block_pos.dart';

/// 26.2 包类型的 Dart 侧载体。命名与判据类名对应（见各类的 `REF:` 注释）；
/// 未覆盖字段的包以 raw 形态保留字节（"未知数据原样保留"纪律）。

import 'package:mc_wire/mc_wire.dart';


// —— handshake ——

/// REF: `ClientIntentionPacket.java`。
final class ClientIntention {
  ClientIntention({
    required this.protocolVersion,
    required this.hostName,
    required this.port,
    required this.intent,
  });

  final int protocolVersion;
  final String hostName;
  final int port;
  final int intent; // 1=STATUS, 2=LOGIN

  Uint8List encodeBody() {
    final w = ByteWriter();
    w.writeVarInt(protocolVersion);
    w.writeUtf(hostName, 255);
    w.writeUnsignedShort(port);
    w.writeVarInt(intent);
    return w.takeBytes();
  }
}

// —— status ——

/// REF: `ClientboundStatusResponsePacket.java`（JSON 字符串原样保留）。
final class StatusResponse {
  StatusResponse(this.json);
  final String json;
}

/// REF: `ClientboundPongResponsePacket.java`。
final class StatusPongResponse {
  StatusPongResponse(this.payload);
  final int payload;
}

// —— login ——

/// REF: `ClientboundLoginDisconnectPacket.java`（Component = 网络 NBT，原样保留）。
final class LoginDisconnect {
  LoginDisconnect(this.reasonNbt);
  final Uint8List reasonNbt;
}

/// REF: `ClientboundHelloPacket.java` —— 收到即判 online-mode（remote-play 裁决）。
final class LoginHelloEncryption {
  LoginHelloEncryption(this.serverId, this.publicKey, this.challenge, this.shouldAuthenticate);
  final String serverId;
  final Uint8List publicKey;
  final Uint8List challenge;
  final bool shouldAuthenticate;
}

/// REF: `ClientboundLoginFinishedPacket.java`（GAME_PROFILE + sessionId）。
final class LoginFinished {
  LoginFinished(this.uuid, this.name);
  final List<int> uuid; // 16 字节
  final String name;
}

/// REF: `ClientboundLoginCompressionPacket.java`。
final class LoginCompression {
  LoginCompression(this.threshold);
  final int threshold;
}

/// REF: `ClientboundCustomQueryPacket.java`。
final class LoginCustomQuery {
  LoginCustomQuery(this.messageId, this.identifier, this.payload);
  final int messageId;
  final String identifier;
  final Uint8List payload;
}

/// REF: `ClientboundCookieRequestPacket.java`（cookie 目录成对包）。
final class CookieRequest {
  CookieRequest(this.key);
  final String key;
}

// —— common（config/play 共用） ——

/// REF: `ClientboundKeepAlivePacket.java` / `ServerboundKeepAlivePacket.java`（long）。
final class KeepAlive {
  KeepAlive(this.id);
  final int id;
}

/// REF: `ClientboundPingPacket.java`（long）→ `ServerboundPongPacket.java`（int，按参考源码）。
final class Ping {
  Ping(this.id);
  final int id;
}

/// REF: `ClientboundDisconnectPacket.java`（Component = 网络 NBT，原样保留）。
final class Disconnect {
  Disconnect(this.reasonNbt);
  final Uint8List reasonNbt;
}

/// REF: `ServerboundResourcePackPacket.java`（writeEnum = varint 序；DECLINED 即可终结
/// 服务器的资源包任务，判据 ServerConfigurationPacketListenerImpl.handleResourcePackResponse）。
enum ResourceResponseAction { accepted, declined, failed, acceptedDeferred, invalidUrl, invalidHash, discarded }

final class ResourcePackResponse {
  ResourcePackResponse(this.uuid, this.action);
  final List<int> uuid; // 16 字节
  final ResourceResponseAction action;
}

// —— configuration ——

/// REF: `ClientboundRegistryDataPacket.java` + `RegistrySynchronization.PackedRegistryEntry`。
final class RegistryData {
  RegistryData(this.registryName, this.entries);
  final String registryName;
  final List<RegistryEntry> entries;
}

final class RegistryEntry {
  RegistryEntry(this.id, this.dataNbt);
  final String id;

  /// 网络 NBT（根无名字）；null = 无数据。
  final Uint8List? dataNbt;
}

/// REF: `ClientboundFinishConfigurationPacket.java`（空）。
final class FinishConfiguration {
  const FinishConfiguration();
}

/// REF: `ClientboundUpdateTagsPacket.java`（双层 map，tag 集合为 varint 数组）。
final class UpdateTags {
  UpdateTags(this.data);
  final Map<String, Map<String, List<int>>> data;
}

/// REF: `ClientboundCodeOfConductPacket.java`。
final class CodeOfConduct {
  CodeOfConduct(this.text);
  final String text;
}

// —— play：clientbound ——

/// REF: `CommonPlayerSpawnInfo.java` + `ClientboundLoginPacket.java`。
final class GameLogin {
  GameLogin({
    required this.playerId,
    required this.levelNames,
    required this.maxPlayers,
    required this.chunkRadius,
    required this.simulationDistance,
    required this.dimensionType,
    required this.dimension,
    required this.hashedSeed,
    required this.gameType,
    required this.previousGameType,
    required this.isDebug,
    required this.isFlat,
    required this.portalCooldown,
    required this.seaLevel,
  });

  final int playerId;
  final List<String> levelNames;
  final int maxPlayers;
  final int chunkRadius;
  final int simulationDistance;
  final String dimensionType;
  final String dimension;
  final int hashedSeed;
  final int gameType;
  final int previousGameType; // -1 = null
  final bool isDebug;
  final bool isFlat;
  final int portalCooldown;
  final int seaLevel;
}

/// REF: `ClientboundLevelChunkWithLightPacket.java` + `ClientboundLevelChunkPacketData.java`
/// + `ClientboundLightUpdatePacketData.java`。调色板 buffer 交给 mc_session 解码。
final class LevelChunkWithLight {
  LevelChunkWithLight({
    required this.x,
    required this.z,
    required this.heightmapTypes,
    required this.heightmapData,
    required this.sectionsBuffer,
    required this.blockEntities,
    required this.skyYMask,
    required this.blockYMask,
    required this.emptySkyYMask,
    required this.emptyBlockYMask,
    required this.skyUpdates,
    required this.blockUpdates,
  });

  final int x;
  final int z;

  /// heightmap 类型 id（varint 序，26.2 枚举序）→ long 数组。
  final List<int> heightmapTypes;
  final List<Uint8List> heightmapData;

  /// 各 section 的调色板串接 buffer（≤ 2 MiB）。
  final Uint8List sectionsBuffer;

  final List<BlockEntityInfo> blockEntities;

  /// 光照：四个 bitset（long 数组）+ 两个 2048 字节数组列表。
  final List<int> skyYMask;
  final List<int> blockYMask;
  final List<int> emptySkyYMask;
  final List<int> emptyBlockYMask;
  final List<Uint8List> skyUpdates;
  final List<Uint8List> blockUpdates;
}

final class BlockEntityInfo {
  BlockEntityInfo(this.packedXZ, this.y, this.type, this.tagNbt);
  final int packedXZ;
  final int y;
  final int type;
  final Uint8List? tagNbt;
}

/// REF: `ClientboundBlockUpdatePacket.java`（varint 状态号 = BLOCK_STATE_REGISTRY）。
final class BlockUpdate {
  BlockUpdate(this.pos, this.stateId);
  final McBlockPos pos;
  final int stateId;
}

/// REF: `ClientboundSectionBlocksUpdatePacket.java`（varlong 打包：低 12 位段内坐标）。
final class SectionBlocksUpdate {
  SectionBlocksUpdate(this.sectionX, this.sectionY, this.sectionZ, this.packedChanges);
  final int sectionX;
  final int sectionY;
  final int sectionZ;
  final List<int> packedChanges;
}

/// REF: `ClientboundForgetLevelChunkPacket.java`。
final class ForgetLevelChunk {
  ForgetLevelChunk(this.x, this.z);
  final int x;
  final int z;
}

/// REF: `ClientboundChunkBatchStartPacket.java`（空）/ `ClientboundChunkBatchFinishedPacket.java`。
final class ChunkBatchStart {
  const ChunkBatchStart();
}

final class ChunkBatchFinished {
  ChunkBatchFinished(this.batchSize);
  final int batchSize;
}

/// REF: `ClientboundSetTimePacket.java` + `world/clock/ClockNetworkState.java`
/// （26.2 时间同步：服务器约每秒发一次；clock id 为内置 world_clock registry
/// 序号——overworld=0、the_end=1，判据 `WorldClocks.java` 注册顺序）。
final class SetTime {
  SetTime({required this.gameTime, required this.clocks});

  /// 全局游戏时间（世界年龄，不含日夜语义）。
  final int gameTime;

  /// clock id → (totalTicks 昼夜总 tick, partialTick 小数部分, rate 流速)。
  final Map<int, ClockNetworkState> clocks;
}

final class ClockNetworkState {
  const ClockNetworkState({
    required this.totalTicks,
    required this.partialTick,
    required this.rate,
  });

  final int totalTicks;
  final double partialTick;
  final double rate;
}

/// REF: `ClientboundPlayerPositionPacket.java`（PositionMoveRotation + Relative bitset）。
final class PlayerPosition {
  PlayerPosition({
    required this.teleportId,
    required this.x,
    required this.y,
    required this.z,
    required this.yRot,
    required this.xRot,
    required this.dx,
    required this.dy,
    required this.dz,
    required this.relativeFlags,
  });

  final int teleportId;
  final double x;
  final double y;
  final double z;
  final double yRot;
  final double xRot;
  final double dx;
  final double dy;
  final double dz;

  /// Relative 枚举位掩码（X=0,Y=1,Z=2,Y_ROT=3,X_ROT=4,DELTA_X=5..8）。
  final List<int> relativeFlags; // long 数组（bitSet 原样）
}

/// REF: `ClientboundEntityPositionSyncPacket.java`。
final class EntityPositionSync {
  EntityPositionSync({
    required this.entityId,
    required this.x,
    required this.y,
    required this.z,
    required this.dx,
    required this.dy,
    required this.dz,
    required this.yRot,
    required this.xRot,
    required this.onGround,
  });

  final int entityId;
  final double x;
  final double y;
  final double z;
  final double dx;
  final double dy;
  final double dz;
  final double yRot;
  final double xRot;
  final bool onGround;
}

/// REF: `ClientboundSetChunkCacheCenterPacket.java` / `...RadiusPacket.java` /
/// `...SetSimulationDistancePacket.java`。
final class ViewDistanceUpdate {
  ViewDistanceUpdate(this.a, this.b);
  final int a;
  final int b;
}

/// REF: `ClientboundGameEventPacket.java`（event ubyte + float value）。
final class GameEvent {
  GameEvent(this.event, this.value);
  final int event;
  final double value;
}

// —— play：serverbound ——

/// REF: `ServerboundMovePlayerPacket.java`（四种变体，flags = onGround|horizontalCollision<<1）。
///
/// 四个变体是独立类型——包 id 由变体决定（登记表按类型查 id），字段顺序：
/// `[pos?] [rot?] flags`。
abstract base class MovePlayer {
  MovePlayer({required this.onGround, required this.horizontalCollision});

  factory MovePlayer.pos(double x, double y, double z,
      {required bool onGround, required bool horizontalCollision}) = _MovePlayerPos;

  factory MovePlayer.posRot(double x, double y, double z, double yRot, double xRot,
      {required bool onGround, required bool horizontalCollision}) = _MovePlayerPosRot;

  factory MovePlayer.rot(double yRot, double xRot,
      {required bool onGround, required bool horizontalCollision}) = _MovePlayerRot;

  factory MovePlayer.statusOnly({required bool onGround, required bool horizontalCollision}) =
      _MovePlayerStatusOnly;

  bool get hasPos;
  bool get hasRot;
  double get x;
  double get y;
  double get z;
  double get yRot;
  double get xRot;
  final bool onGround;
  final bool horizontalCollision;

  void encodeBody(ByteWriter w) {
    if (hasPos) {
      w.writeDouble(x);
      w.writeDouble(y);
      w.writeDouble(z);
    }
    if (hasRot) {
      w.writeFloat(yRot);
      w.writeFloat(xRot);
    }
    w.writeUnsignedByte((onGround ? 1 : 0) | (horizontalCollision ? 2 : 0));
  }
}

final class _MovePlayerPos extends MovePlayer {
  _MovePlayerPos(double x, double y, double z,
      {required super.onGround, required super.horizontalCollision})
      : _x = x,
        _y = y,
        _z = z;

  final double _x;
  final double _y;
  final double _z;
  @override
  double get x => _x;
  @override
  double get y => _y;
  @override
  double get z => _z;
  @override
  bool get hasPos => true;
  @override
  bool get hasRot => false;
  @override
  double get yRot => 0;
  @override
  double get xRot => 0;
}

final class _MovePlayerPosRot extends MovePlayer {
  _MovePlayerPosRot(double x, double y, double z, double yRot, double xRot,
      {required super.onGround, required super.horizontalCollision})
      : _x = x,
        _y = y,
        _z = z,
        _yRot = yRot,
        _xRot = xRot;

  final double _x;
  final double _y;
  final double _z;
  final double _yRot;
  final double _xRot;
  @override
  double get x => _x;
  @override
  double get y => _y;
  @override
  double get z => _z;
  @override
  double get yRot => _yRot;
  @override
  double get xRot => _xRot;
  @override
  bool get hasPos => true;
  @override
  bool get hasRot => true;
}

final class _MovePlayerRot extends MovePlayer {
  _MovePlayerRot(double yRot, double xRot,
      {required super.onGround, required super.horizontalCollision})
      : _yRot = yRot,
        _xRot = xRot;

  final double _yRot;
  final double _xRot;
  @override
  bool get hasPos => false;
  @override
  bool get hasRot => true;
  @override
  double get x => 0;
  @override
  double get y => 0;
  @override
  double get z => 0;
  @override
  double get yRot => _yRot;
  @override
  double get xRot => _xRot;
}

final class _MovePlayerStatusOnly extends MovePlayer {
  _MovePlayerStatusOnly({required super.onGround, required super.horizontalCollision});

  @override
  bool get hasPos => false;
  @override
  bool get hasRot => false;
  @override
  double get x => 0;
  @override
  double get y => 0;
  @override
  double get z => 0;
  @override
  double get yRot => 0;
  @override
  double get xRot => 0;
}

/// REF: `ServerboundPlayerLoadedPacket.java`（空）。
final class PlayerLoaded {
  const PlayerLoaded();
}

/// REF: `ServerboundClientTickEndPacket.java`（空）。
final class ClientTickEnd {
  const ClientTickEnd();
}

/// REF: `ServerboundChunkBatchReceivedPacket.java`（float）。
final class ChunkBatchReceived {
  ChunkBatchReceived(this.desiredChunksPerTick);
  final double desiredChunksPerTick;
}

/// REF: `ServerboundPlayerActionPacket.java`。
/// action：0=START_DESTROY 1=ABORT 2=STOP 3=DROP_ALL 4=DROP_ITEM 5=RELEASE_USE 6=SWAP_ITEM。
final class PlayerAction {
  PlayerAction(this.action, this.pos, this.direction, this.sequence);
  final int action;
  final McBlockPos pos;
  final int direction;
  final int sequence;
}

/// REF: `ServerboundUseItemOnPacket.java`（BlockHitResult + sequence）。
final class UseItemOn {
  UseItemOn({
    required this.hand,
    required this.pos,
    required this.direction,
    required this.cursorX,
    required this.cursorY,
    required this.cursorZ,
    required this.insideBlock,
    required this.worldBorderHit,
    required this.sequence,
  });

  final int hand;
  final McBlockPos pos;
  final int direction;
  final double cursorX;
  final double cursorY;
  final double cursorZ;
  final bool insideBlock;
  final bool worldBorderHit;
  final int sequence;
}

/// REF: `ServerboundSwingPacket.java`（varint hand：0 主手 1 副手）。
final class Swing {
  Swing(this.hand);
  final int hand;
}

/// REF: `ServerboundAcceptTeleportationPacket.java`（varint）。
final class AcceptTeleportation {
  AcceptTeleportation(this.id);
  final int id;
}

/// REF: `ServerboundClientInformationPacket.java` + `ClientInformation.java`（26.3 common 源码）。
final class ClientInformation {
  ClientInformation({
    this.language = 'en_us',
    this.viewDistance = 8,
    this.chatVisibility = 0,
    this.chatColors = true,
    this.modelCustomisation = 0,
    this.mainHand = 1, // RIGHT（Player.DEFAULT_MAIN_HAND）
    this.textFilteringEnabled = false,
    this.allowsListing = false,
    this.particleStatus = 0,
  });

  final String language;
  final int viewDistance;
  final int chatVisibility;
  final bool chatColors;
  final int modelCustomisation;
  final int mainHand;
  final bool textFilteringEnabled;
  final bool allowsListing;
  final int particleStatus;

  void encodeBody(ByteWriter w) {
    w.writeUtf(language, 16);
    w.writeByte(viewDistance);
    w.writeVarInt(chatVisibility);
    w.writeBool(chatColors);
    w.writeUnsignedByte(modelCustomisation);
    w.writeVarInt(mainHand);
    w.writeBool(textFilteringEnabled);
    w.writeBool(allowsListing);
    w.writeVarInt(particleStatus);
  }
}

/// REF: `ServerboundSelectKnownPacks.java`（空列表即可让服务器走原版数据路径）。
final class SelectKnownPacks {
  const SelectKnownPacks();
}

/// REF: `ServerboundCookieResponsePacket.java`（key 原样回 + 空 cookie）。
final class CookieResponse {
  const CookieResponse(this.key);
  final String key;
}

/// REF: `ServerboundCustomQueryAnswerPacket.java`（transactionId + 无 payload）。
final class CustomQueryAnswer {
  CustomQueryAnswer(this.messageId);
  final int messageId;
}

/// REF: `ServerboundLoginAcknowledgedPacket.java`（空）。
final class LoginAcknowledged {
  const LoginAcknowledged();
}

/// REF: `ServerboundHelloPacket.java`（utf(16) + UUID 16 字节）。
final class ServerboundHello {
  ServerboundHello(this.name, this.uuid);
  final String name;
  final List<int> uuid;
}

// —— 玩家输入与能力（能力 player-input，2026-10-07）——

/// 输入标志（REF: `world/entity/player/Input.java`：7 位打包，1=forward /
/// 2=backward / 4=left / 8=right / 16=jump / 32=shift / 64=sprint）。
class PlayerInputFlags {
  PlayerInputFlags({
    this.forward = false,
    this.backward = false,
    this.left = false,
    this.right = false,
    this.jump = false,
    this.shift = false,
    this.sprint = false,
  });

  final bool forward;
  final bool backward;
  final bool left;
  final bool right;
  final bool jump;
  final bool shift;
  final bool sprint;

  /// 位打包/解出（Input.STREAM_CODEC 口径）。
  static PlayerInputFlags fromByte(int flags) => PlayerInputFlags(
        forward: (flags & 1) != 0,
        backward: (flags & 2) != 0,
        left: (flags & 4) != 0,
        right: (flags & 8) != 0,
        jump: (flags & 16) != 0,
        shift: (flags & 32) != 0,
        sprint: (flags & 64) != 0,
      );

  int pack() =>
      (forward ? 1 : 0) |
      (backward ? 2 : 0) |
      (left ? 4 : 0) |
      (right ? 8 : 0) |
      (jump ? 16 : 0) |
      (shift ? 32 : 0) |
      (sprint ? 64 : 0);

  @override
  bool operator ==(Object other) =>
      other is PlayerInputFlags &&
      other.pack() == pack();

  @override
  int get hashCode => pack();
}

/// REF: `ServerboundPlayerInputPacket.java`（Input 标志字节）。
final class PlayerInputPacket {
  PlayerInputPacket(this.input);
  final PlayerInputFlags input;
}

/// REF: `ClientboundPlayerAbilitiesPacket.java`（标志字节 invulnerable1 /
/// flying2 / canFly4 / instabuild8 + float flyingSpeed + float walkingSpeed）。
final class PlayerAbilitiesIn {
  PlayerAbilitiesIn({
    required this.invulnerable,
    required this.flying,
    required this.mayfly,
    required this.instabuild,
    required this.flyingSpeed,
    required this.walkingSpeed,
  });

  final bool invulnerable;
  final bool flying;
  final bool mayfly;
  final bool instabuild;
  final double flyingSpeed;
  final double walkingSpeed;
}

/// REF: `ServerboundPlayerAbilitiesPacket.java`（仅 1 字节，bit2=flying）。
final class PlayerAbilitiesOut {
  PlayerAbilitiesOut({required this.flying});
  final bool flying;
}

/// REF: `ServerboundSetCarriedItemPacket.java`（单字段 `slot: short`，
/// `write` = writeShort，`:25-27`）。
final class SetCarriedItem {
  SetCarriedItem({required this.slot});
  final int slot;
}

/// REF: `ServerboundSetCreativeModeSlotPacket.java`（record `slotNum: short` +
/// `itemStack: ItemStack`，经 `validatedStreamCodec(OPTIONAL_UNTRUSTED_STREAM_CODEC)`）。///
/// ItemStack 线上格式（判据 `ItemStack.java:170-195` `createOptionalStreamCodec`）：
/// VarInt count（≤0 即空栈）→ Item holder（VarInt 注册序 id，`Item.java:104`
/// `holderRegistry(Registries.ITEM)`）→ DataComponentPatch。本仓创造点选只发
/// **无补丁的普通物品**：patch 走 `DataComponentPatch.java:100-103` 空补丁 =
/// 两个 VarInt 0（DELIMITED 与普通 STREAM_CODEC 对空补丁编码相同）。
/// 完整组件补丁编解码未实现（债，见 openspec/progress.md §8）。
/// REF: `ServerboundPlayerCommandPacket.java`（varint entityId + enum action +
/// varint data，`:33-37` write）。Action 序数照原版枚举顺序（`:60-68`）：
/// STOP_SLEEPING=0、**START_SPRINTING=1、STOP_SPRINTING=2**、
/// START_RIDING_JUMP=3、STOP_RIDING_JUMP=4、OPEN_INVENTORY=5、START_FALL_FLYING=6。
final class PlayerCommand {
  PlayerCommand({required this.entityId, required this.action, this.data = 0});
  final int entityId;
  final int action;

  /// 原版仅骑乘跳跃用（`data`），其余恒 0。
  final int data;
}

final class SetCreativeModeSlot {
  SetCreativeModeSlot({
    required this.slotNum,
    required this.itemId,
    required this.count,
  });

  /// 目标槽位（原版 `short slotNum`；-1 = 丢弃）。
  final int slotNum;

  /// 物品注册序 id（`Item.java:104` holderRegistry 序）。
  final int itemId;

  /// 栈数量（`ItemStack.getCount()`）。
  final int count;
}
