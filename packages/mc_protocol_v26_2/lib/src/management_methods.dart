// 管理服务器（JSON-RPC）方法名表 + 便捷调用。
//
//   判据：mc-sources/minecraft-26.2/net/minecraft/server/jsonrpc/IncomingRpcMethods.java
//   的 69 处 `.register(methodRegistry, "<name>")`（行 30~362，逐条登记）。方法名是
//   线上协议的一部分（`createRequest` 的 `method` 字段，JsonRPCUtils.java:34），
//   故此处逐个照抄，不得增删改。
//
//   约定：常量名取原版方法名的 lowerCamelCase（点/斜杠/下划线转驼峰，与
//   protocol_ids.dart 的命名惯例一致）；字符串值逐字保留原版方法名。
//
//   `rpc.discover` / `server/status` 的响应形状：
//     rpc.discover   → DiscoveryService.DiscoverResponse：
//                        { "openrpc": "1.3.2", "info": {title, version},
//                          "methods": [...], "components": {"schemas": {...}} }
//                        （DiscoveryService.java:34-35、:65-73）
//     server/status  → ServerStateService.ServerState：
//                        { "started": bool, "players": [...], "version": {...} }
//                        （ServerStateService.java:14-18、:63-73）
import 'jsonrpc_client.dart';

/// 管理服务器 incoming 方法名（IncomingRpcMethods.java 行 30~362 逐条）。
abstract final class ManagementMethods {
  /// IncomingRpcMethods.java:30 —— `rpc.discover`
  static const String rpcDiscover = 'rpc.discover';

  /// IncomingRpcMethods.java:37
  static const String allowlist = 'allowlist';
  /// IncomingRpcMethods.java:42
  static const String allowlistSet = 'allowlist/set';
  /// IncomingRpcMethods.java:47
  static const String allowlistAdd = 'allowlist/add';
  /// IncomingRpcMethods.java:52
  static const String allowlistRemove = 'allowlist/remove';
  /// IncomingRpcMethods.java:56
  static const String allowlistClear = 'allowlist/clear';

  /// IncomingRpcMethods.java:63
  static const String bans = 'bans';
  /// IncomingRpcMethods.java:68
  static const String bansSet = 'bans/set';
  /// IncomingRpcMethods.java:73
  static const String bansAdd = 'bans/add';
  /// IncomingRpcMethods.java:78
  static const String bansRemove = 'bans/remove';
  /// IncomingRpcMethods.java:82
  static const String bansClear = 'bans/clear';

  /// IncomingRpcMethods.java:89
  static const String ipBans = 'ip_bans';
  /// IncomingRpcMethods.java:94
  static const String ipBansSet = 'ip_bans/set';
  /// IncomingRpcMethods.java:99
  static const String ipBansAdd = 'ip_bans/add';
  /// IncomingRpcMethods.java:104
  static const String ipBansRemove = 'ip_bans/remove';
  /// IncomingRpcMethods.java:108
  static const String ipBansClear = 'ip_bans/clear';

  /// IncomingRpcMethods.java:115
  static const String players = 'players';
  /// IncomingRpcMethods.java:120
  static const String playersKick = 'players/kick';

  /// IncomingRpcMethods.java:127
  static const String operators = 'operators';
  /// IncomingRpcMethods.java:132
  static const String operatorsSet = 'operators/set';
  /// IncomingRpcMethods.java:137
  static const String operatorsAdd = 'operators/add';
  /// IncomingRpcMethods.java:142
  static const String operatorsRemove = 'operators/remove';
  /// IncomingRpcMethods.java:146
  static const String operatorsClear = 'operators/clear';

  /// IncomingRpcMethods.java:153
  static const String serverStatus = 'server/status';
  /// IncomingRpcMethods.java:158
  static const String serverSave = 'server/save';
  /// IncomingRpcMethods.java:162
  static const String serverStop = 'server/stop';
  /// IncomingRpcMethods.java:167
  static const String serverSystemMessage = 'server/system_message';

  /// IncomingRpcMethods.java:174
  static const String serversettingsAutosave = 'serversettings/autosave';
  /// IncomingRpcMethods.java:179
  static const String serversettingsAutosaveSet = 'serversettings/autosave/set';
  /// IncomingRpcMethods.java:183
  static const String serversettingsDifficulty = 'serversettings/difficulty';
  /// IncomingRpcMethods.java:188
  static const String serversettingsDifficultySet =
      'serversettings/difficulty/set';
  /// IncomingRpcMethods.java:192
  static const String serversettingsEnforceAllowlist =
      'serversettings/enforce_allowlist';
  /// IncomingRpcMethods.java:197
  static const String serversettingsEnforceAllowlistSet =
      'serversettings/enforce_allowlist/set';
  /// IncomingRpcMethods.java:201
  static const String serversettingsUseAllowlist =
      'serversettings/use_allowlist';
  /// IncomingRpcMethods.java:206
  static const String serversettingsUseAllowlistSet =
      'serversettings/use_allowlist/set';
  /// IncomingRpcMethods.java:210
  static const String serversettingsMaxPlayers = 'serversettings/max_players';
  /// IncomingRpcMethods.java:215
  static const String serversettingsMaxPlayersSet =
      'serversettings/max_players/set';
  /// IncomingRpcMethods.java:219
  static const String serversettingsPauseWhenEmptySeconds =
      'serversettings/pause_when_empty_seconds';
  /// IncomingRpcMethods.java:224
  static const String serversettingsPauseWhenEmptySecondsSet =
      'serversettings/pause_when_empty_seconds/set';
  /// IncomingRpcMethods.java:228
  static const String serversettingsPlayerIdleTimeout =
      'serversettings/player_idle_timeout';
  /// IncomingRpcMethods.java:233
  static const String serversettingsPlayerIdleTimeoutSet =
      'serversettings/player_idle_timeout/set';
  /// IncomingRpcMethods.java:237
  static const String serversettingsAllowFlight = 'serversettings/allow_flight';
  /// IncomingRpcMethods.java:242
  static const String serversettingsAllowFlightSet =
      'serversettings/allow_flight/set';
  /// IncomingRpcMethods.java:246
  static const String serversettingsMotd = 'serversettings/motd';
  /// IncomingRpcMethods.java:251
  static const String serversettingsMotdSet = 'serversettings/motd/set';
  /// IncomingRpcMethods.java:255
  static const String serversettingsSpawnProtectionRadius =
      'serversettings/spawn_protection_radius';
  /// IncomingRpcMethods.java:260
  static const String serversettingsSpawnProtectionRadiusSet =
      'serversettings/spawn_protection_radius/set';
  /// IncomingRpcMethods.java:264
  static const String serversettingsForceGameMode =
      'serversettings/force_game_mode';
  /// IncomingRpcMethods.java:269
  static const String serversettingsForceGameModeSet =
      'serversettings/force_game_mode/set';
  /// IncomingRpcMethods.java:273
  static const String serversettingsGameMode = 'serversettings/game_mode';
  /// IncomingRpcMethods.java:278
  static const String serversettingsGameModeSet = 'serversettings/game_mode/set';
  /// IncomingRpcMethods.java:282
  static const String serversettingsViewDistance =
      'serversettings/view_distance';
  /// IncomingRpcMethods.java:287
  static const String serversettingsViewDistanceSet =
      'serversettings/view_distance/set';
  /// IncomingRpcMethods.java:291
  static const String serversettingsSimulationDistance =
      'serversettings/simulation_distance';
  /// IncomingRpcMethods.java:296
  static const String serversettingsSimulationDistanceSet =
      'serversettings/simulation_distance/set';
  /// IncomingRpcMethods.java:300
  static const String serversettingsAcceptTransfers =
      'serversettings/accept_transfers';
  /// IncomingRpcMethods.java:305
  static const String serversettingsAcceptTransfersSet =
      'serversettings/accept_transfers/set';
  /// IncomingRpcMethods.java:309
  static const String serversettingsStatusHeartbeatInterval =
      'serversettings/status_heartbeat_interval';
  /// IncomingRpcMethods.java:314
  static const String serversettingsStatusHeartbeatIntervalSet =
      'serversettings/status_heartbeat_interval/set';
  /// IncomingRpcMethods.java:318
  static const String serversettingsOperatorUserPermissionLevel =
      'serversettings/operator_user_permission_level';
  /// IncomingRpcMethods.java:323
  static const String serversettingsOperatorUserPermissionLevelSet =
      'serversettings/operator_user_permission_level/set';
  /// IncomingRpcMethods.java:327
  static const String serversettingsHideOnlinePlayers =
      'serversettings/hide_online_players';
  /// IncomingRpcMethods.java:332
  static const String serversettingsHideOnlinePlayersSet =
      'serversettings/hide_online_players/set';
  /// IncomingRpcMethods.java:336
  static const String serversettingsStatusReplies =
      'serversettings/status_replies';
  /// IncomingRpcMethods.java:341
  static const String serversettingsStatusRepliesSet =
      'serversettings/status_replies/set';
  /// IncomingRpcMethods.java:345
  static const String serversettingsEntityBroadcastRange =
      'serversettings/entity_broadcast_range';
  /// IncomingRpcMethods.java:350
  static const String serversettingsEntityBroadcastRangeSet =
      'serversettings/entity_broadcast_range/set';

  /// IncomingRpcMethods.java:357
  static const String gamerules = 'gamerules';
  /// IncomingRpcMethods.java:362
  static const String gamerulesUpdate = 'gamerules/update';
}

/// 便捷调用：`rpc.discover`，返回原版 `DiscoverResponse` 的 JSON 对象。
///
/// 判据 DiscoveryService.java:16（入参只有 schema registry，故请求不带 `params`）、
/// :34-35（`info.title`/`info.version`）、:65-73（`openrpc`/`info`/`methods`/`components`）。
Future<Map<String, dynamic>> discover(JsonRpcClient client) async {
  final result = await client.call(ManagementMethods.rpcDiscover);
  return (result as Map).cast<String, dynamic>();
}

/// 便捷调用：`server/status`，返回原版 `ServerStateService.ServerState` 的 JSON 对象。
///
/// 判据 ServerStateService.java:14-18（无入参）、:63-73（`started`/`players`/`version`）。
Future<Map<String, dynamic>> serverStatus(JsonRpcClient client) async {
  final result = await client.call(ManagementMethods.serverStatus);
  return (result as Map).cast<String, dynamic>();
}
