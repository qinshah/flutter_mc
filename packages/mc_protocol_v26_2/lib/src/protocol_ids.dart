/// 26.2 线上包 id 表 —— **由参考源码各 `*Protocols.java` 的 `addPacket` 注册顺序推出**
/// （`IdDispatchCodec` 按登记序分配数值 id；判据 = mc-sources/minecraft-26.2）。
///
/// 注意 clientbound play 的 bundle 定界包占用 id 0（`GameProtocols.java:133` 的
/// `withBundlePacket` 在链首注册 delimiter，见 `ProtocolInfoBuilder.withBundlePacket`），
/// 因此 clientbound play 全部 +1；serverbound 无 bundle 机制。
library;

import 'package:mc_wire/mc_wire.dart';

/// 阶段 id 表（按方向分）。命名对齐原版 `*PacketTypes` 常量（去前缀）。
abstract final class PlayClientbound {
  /// `GameProtocols.java:133` 的 bundle 定界包。
  static const int bundleDelimiter = 0;

  /// `CLIENTBOUND_ADD_ENTITY`（注册序 0，因 delimiter 占 0 而 +1）。
  static const int addEntity = 1;
  static const int blockUpdate = 8; // 7 + 1
  static const int chunkBatchFinished = 11; // 10 + 1
  static const int chunkBatchStart = 12; // 11 + 1
  static const int disconnect = 32; // 31 + 1
  static const int entityPositionSync = 35; // 34 + 1
  static const int forgetLevelChunk = 37; // 36 + 1
  static const int gameEvent = 38; // 37 + 1
  static const int keepAlive = 44; // 43 + 1
  static const int levelChunkWithLight = 45; // 44 + 1
  static const int lightUpdate = 48; // 47 + 1
  static const int login = 49; // 48 + 1
  static const int ping = 61; // 60 + 1
  static const int playerAbilities = 64; // 63 + 1
  static const int playerPosition = 72; // 71 + 1
  static const int playerRotation = 73; // 72 + 1
  static const int respawn = 82; // 81 + 1
  static const int sectionBlocksUpdate = 84; // 83 + 1
  static const int setChunkCacheCenter = 94; // 93 + 1
  static const int setChunkCacheRadius = 95; // 94 + 1
  static const int setDefaultSpawnPosition = 97; // 96 + 1
  static const int setHealth = 104; // 103 + 1
  static const int setSimulationDistance = 111; // 110 + 1
  static const int setTime = 113; // 112 + 1
  static const int updateTags = 134; // 133 + 1
}

abstract final class PlayServerbound {
  static const int acceptTeleportation = 0;
  static const int chunkBatchReceived = 11;
  static const int clientTickEnd = 13;
  static const int clientInformation = 14;
  static const int confirmTeleportation = acceptTeleportation;
  static const int keepAlive = 28;
  static const int movePlayerPos = 30;
  static const int movePlayerPosRot = 31;
  static const int movePlayerRot = 32;
  static const int movePlayerStatusOnly = 33;
  static const int playerAction = 41;
  static const int playerLoaded = 44;
  static const int pong = 45;
  static const int swing = 63;
  static const int useItemOn = 66;
}

abstract final class ConfigurationClientbound {
  static const int cookieRequest = 0;
  static const int customPayload = 1;
  static const int disconnect = 2;
  static const int finishConfiguration = 3;
  static const int keepAlive = 4;
  static const int ping = 5;
  static const int registryData = 7;
  static const int resourcePackPop = 8;
  static const int resourcePackPush = 9;
  static const int updateEnabledFeatures = 12;
  static const int updateTags = 13;
  static const int selectKnownPacks = 14;
  static const int codeOfConduct = 19;
}

abstract final class ConfigurationServerbound {
  static const int clientInformation = 0;
  static const int cookieResponse = 1;
  static const int customPayload = 2;
  static const int finishConfiguration = 3;
  static const int keepAlive = 4;
  static const int pong = 5;
  static const int resourcePack = 6;
  static const int selectKnownPacks = 7;
  static const int acceptCodeOfConduct = 9;
}

abstract final class LoginClientbound {
  static const int loginDisconnect = 0;
  static const int hello = 1;

  /// 收到即判 online-mode（remote-play：仅 offline-mode）。
  static const int helloEncryption = hello;
  static const int loginFinished = 2;
  static const int loginCompression = 3;
  static const int customQuery = 4;
  static const int cookieRequest = 5;
}

abstract final class LoginServerbound {
  static const int hello = 0;
  static const int key = 1;
  static const int customQueryAnswer = 2;
  static const int loginAcknowledged = 3;
  static const int cookieResponse = 4;
}

abstract final class HandshakeServerbound {
  static const int clientIntention = 0;
}

/// 客户端意图（判据：`ClientIntent.java` —— 已由 mc_wire 的 [ClientIntent] 表达）。
final class ProtocolV262 {
  /// 26.2 协议号（tasks 1.1 实测；登记表见 docs/design.md §14.1）。
  /// 仅作为**默认值**：握手实际使用的值必须以 status ping 实测为准（remote-play）。
  static const int measuredProtocolId = 776;
}
