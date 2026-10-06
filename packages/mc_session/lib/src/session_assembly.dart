import 'package:mc_protocol_v26_2/mc_protocol_v26_2.dart';

import 'remote_session.dart';
import 'server_address.dart';
import 'server_list.dart';
import 'session_isolate.dart';

/// 版本未注册（装配点拒绝，绝不回退猜测）。
class UnsupportedProtocolError implements Exception {
  UnsupportedProtocolError(this.protocol);

  final int protocol;

  @override
  String toString() =>
      '不支持的协议版本: $protocol（已注册: ${SessionAssembly.registeredProtocols.toList()..sort()}）。'
      '新版本 = 新增 mc_protocol_v<主>_<次> 包 + 在装配点注册接入。';
}

/// 一个协议版本的实现（装配点的注册值）。
///
/// **装配点适配（无原版对应物）**：原版的协议版本选择藏在 `Connection`/
/// `ServerStatus` 的握手参数里，本仓把它上收成注册表，好让业务代码不按版本号分支。
///
/// 两个入口对应两种宿主：纯 Dart 宿主/单测走 [createSession]（同 isolate），
/// app 壳走 [spawn]（worker isolate，design D3：会话整体跑在 worker，网格化不占
/// 主线程）。
class SessionProtocol {
  const SessionProtocol({required this.protocolId});

  /// 该版本实测协议号（握手与 status 校验用）。
  final int protocolId;

  /// 同 isolate 建会话（**不连接**；纯 Dart 宿主与单测用）。
  RemoteSession createSession({
    required String host,
    required int port,
    required String playerName,
    int? viewDistance,
  }) =>
      RemoteSession(
        host: host,
        port: port,
        playerName: playerName,
        protocolId: protocolId,
        viewDistance: viewDistance,
      );

  /// worker isolate 里建会话并**发起连接**（连接结果经事件流回传，失败折叠为
  /// `SessionClosed`）。
  Future<SessionHandle> spawn({
    required String host,
    required int port,
    required String playerName,
    int? viewDistance,
  }) =>
      spawnSession(
        host: host,
        port: port,
        playerName: playerName,
        protocolId: protocolId,
        viewDistance: viewDistance,
      );
}

/// 版本装配点（多版本口径：协议实现的唯一选择处；禁版本号 if 分支）。
///
/// 新增协议版本 = 新增 mc_protocol_v<主>_<次> 包 + 在 [register] 注册该版本的
/// [SessionProtocol]。业务代码只经 [connectFor] 拿会话句柄，看不见协议号。
class SessionAssembly {
  SessionAssembly._();

  static final Map<int, SessionProtocol> _registry = {
    ProtocolV262.measuredProtocolId: SessionProtocol(
      protocolId: ProtocolV262.measuredProtocolId,
    ),
  };

  static Set<int> get registeredProtocols => Set.unmodifiable(_registry.keys);

  /// 注册一个协议版本的实现（新增版本只改这里，不碰业务代码）。
  static void register(int protocol, SessionProtocol implementation) =>
      _registry[protocol] = implementation;

  static bool isSupported(int protocol) => _registry.containsKey(protocol);

  /// 按协议版本建一个**同 isolate** 的会话（不连接）；未注册版本明确拒绝。
  static RemoteSession createSession({
    required String host,
    required int port,
    required String playerName,
    required int protocol,
    int? viewDistance,
  }) {
    final implementation = _registry[protocol];
    if (implementation == null) {
      throw UnsupportedProtocolError(protocol);
    }
    return implementation.createSession(
      host: host,
      port: port,
      playerName: playerName,
      viewDistance: viewDistance,
    );
  }

  /// 装配点入口（design D1）：按服务器列表条目的 `ip`（`host[:port]`）与缓存协议号，
  /// 起一个 worker isolate 会话并**发起连接**，返回 [SessionHandle]。
  ///
  /// 不等待"进服成功"——服务器的下行（`JoinedGame` 等）由 `handle.events` 流出，
  /// 连接失败同样经事件流（`SessionClosed`）回传，调用方据此决定推进还是报错。
  ///
  /// 协议号取 [ServerData.protocol]（status 探测成功后由响应回写）；未注册的版本**同步**
  /// 抛 [UnsupportedProtocolError]（在 spawn 任何 isolate / 发起任何网络连接之前；同步
  /// 而不是返回失败 Future，是为了让配置错误立刻炸掉而不是被未 await 的 Future 吞掉）。
  static Future<SessionHandle> connectFor(
    ServerData server, {
    required String playerName,
    int? viewDistance,
  }) {
    final implementation = _registry[server.protocol];
    if (implementation == null) {
      throw UnsupportedProtocolError(server.protocol);
    }
    final address = ServerAddress.parseString(server.ip);
    return implementation.spawn(
      host: address.host,
      port: address.port,
      playerName: playerName,
      viewDistance: viewDistance,
    );
  }
}
