/// [ServerAddress] 的对应：`client.multiplayer.resolver.ServerAddress`
/// （判据 `mc-sources/minecraft-26.2`）。
///
/// 原版语义：地址串 = `host[:port]`，IPv6 字面量必须写成 `[::1]` / `[::1]:25565`；
/// 未写端口回落 25565；解析失败回落哨兵地址 `server.invalid:25565`（原版 `INVALID`）。
/// 原版基于 Guava `HostAndPort`，本类是那套切分规则的 Dart 平移。
///
/// 简化点（标注）：原版 `getHost()` 走 `IDN.toASCII` 做国际化域名（punycode）转码，
/// Dart 标准库无对应实现，本版直接返回原串——ASCII 域名与字面 IP 行为一致，
/// 非 ASCII 域名不做转码（后续如需要，在 app 壳接第三方 IDN 实现注入）。
class ServerAddress {
  const ServerAddress(this.host, this.port);

  /// 原版 `withDefaultPort(25565)`：地址串未写端口时的缺省端口。
  static const int defaultPort = 25565;

  /// 原版 `INVALID`：解析失败的哨兵地址（连接它必然失败，交由 socket 层报错）。
  static const ServerAddress invalid =
      ServerAddress('server.invalid', defaultPort);

  final String host;
  final int port;

  /// 原版 `parseString`：`HostAndPort.fromString(input).withDefaultPort(25565)`；
  /// host 为空或切分/端口非法一律回落 [invalid]。
  static ServerAddress parseString(String? input) {
    if (input == null) return invalid;
    final parts = _trySplit(input);
    if (parts == null || parts.host.isEmpty) return invalid;
    return ServerAddress(parts.host, parts.port ?? defaultPort);
  }

  /// 原版 `parsePort`：`Integer.parseInt(str.trim())`，失败回落 25565。
  static int parsePort(String str) => int.tryParse(str.trim()) ?? defaultPort;

  /// 原版 `isValidAddress`：能切出非空 host 即视为合法（不含端口范围校验）。
  static bool isValidAddress(String input) {
    final parts = _trySplit(input);
    return parts != null && parts.host.isNotEmpty;
  }

  /// Guava `HostAndPort.fromString` 的切分规则（端口越界/非法视作解析失败）：
  /// - `[...]` 开头的走方括号形态，`]` 后只允许 `:port` 或结束
  /// - 恰好一个 `:` 时切成 host/port；0 个或 2 个以上冒号视作裸主机名 / IPv6 字面量
  static ({String host, int? port})? _trySplit(String input) {
    String host;
    String? portString;

    if (input.startsWith('[')) {
      final close = input.lastIndexOf(']');
      if (close < 0) return null;
      host = input.substring(1, close);
      final rest = input.substring(close + 1);
      if (rest.isEmpty) {
        portString = null;
      } else if (rest.startsWith(':')) {
        portString = rest.substring(1);
      } else {
        return null;
      }
    } else {
      final colon = input.indexOf(':');
      if (colon >= 0 && input.indexOf(':', colon + 1) < 0) {
        host = input.substring(0, colon);
        portString = input.substring(colon + 1);
      } else {
        host = input;
        portString = null;
      }
    }

    if (portString == null) return (host: host, port: null);
    final port = int.tryParse(portString);
    if (port == null || port < 0 || port > 65535) return null;
    return (host: host, port: port);
  }

  @override
  String toString() => host.contains(':') ? '[$host]:$port' : '$host:$port';

  @override
  bool operator ==(Object other) =>
      other is ServerAddress && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);
}
