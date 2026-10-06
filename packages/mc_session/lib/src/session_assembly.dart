import 'package:mc_protocol_v26_2/mc_protocol_v26_2.dart';

import 'remote_session.dart';
import 'server_address.dart';
import 'server_list.dart';

/// 版本未注册（装配点拒绝，绝不回退猜测）。
class UnsupportedProtocolError implements Exception {
  UnsupportedProtocolError(this.protocol);

  final int protocol;

  @override
  String toString() =>
      '不支持的协议版本: $protocol（已注册: ${SessionAssembly.registeredProtocols.toList()..sort()}）。'
      '新版本 = 新增 mc_protocol_v<主>_<次> 包 + 在装配点注册接入。';
}

/// 协议实现工厂：装配点按 protocol 取出的"实现"本身。
///
/// 当前 26.2 的实现就是 [RemoteSession]（编解码同源，见 [SessionAssembly] 注释）；
/// 第二个协议版本落地时，新版本包提供自己的工厂在此注册。
typedef RemoteSessionFactory = RemoteSession Function({
  required String host,
  required int port,
  required String playerName,
  required int protocolId,
});

/// 版本装配点（多版本口径：协议实现的唯一选择处；禁版本号 if 分支）。
///
/// 现状只注册 26.2 一个实现；新增协议版本 = 新增 mc_protocol_v<主>_<次> 包 +
/// 在 [register] 注册该版本的工厂。会话编排（RemoteSession）当前与 26.2 编解码
/// 同源，版本抽象在第二个真实实现落地时上收（届时工厂体换成各自的会话实现）。
class SessionAssembly {
  SessionAssembly._();

  static final Map<int, RemoteSessionFactory> _registry = {
    ProtocolV262.measuredProtocolId: RemoteSession.new,
  };

  static Set<int> get registeredProtocols => Set.unmodifiable(_registry.keys);

  /// 注册一个协议版本的实现（新增版本只改这里，不碰业务代码）。
  static void register(int protocol, RemoteSessionFactory factory) =>
      _registry[protocol] = factory;

  static bool isSupported(int protocol) => _registry.containsKey(protocol);

  /// 按协议版本建会话；未注册版本明确拒绝（不回退默认实现）。
  static RemoteSession createSession({
    required String host,
    required int port,
    required String playerName,
    required int protocol,
  }) {
    final factory = _registry[protocol];
    if (factory == null) {
      throw UnsupportedProtocolError(protocol);
    }
    return factory(
      host: host,
      port: port,
      playerName: playerName,
      protocolId: protocol,
    );
  }

  /// 装配点入口（design D1）：按服务器列表条目的 `ip`（`host[:port]`）与缓存协议号
  /// 建会话并完成连接（握手/登录/进服的下行事件由 `session.events` 流出）。
  ///
  /// 协议号取 [ServerData.protocol]——status 探测成功后由响应回写；未注册的版本在
  /// **发起任何网络连接之前**就抛 [UnsupportedProtocolError]。
  static Future<RemoteSession> connectFor(
    ServerData server, {
    required String playerName,
  }) async {
    final address = ServerAddress.parseString(server.ip);
    final session = createSession(
      host: address.host,
      port: address.port,
      playerName: playerName,
      protocol: server.protocol,
    );
    await session.connect();
    return session;
  }
}
