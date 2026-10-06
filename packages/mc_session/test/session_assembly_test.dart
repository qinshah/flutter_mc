import 'package:mc_session/mc_session.dart';
import 'package:test/test.dart';

/// tasks 1.1 验证：装配点注册表（注册/未注册两分支）+ 地址解析（原版
/// `client.multiplayer.resolver.ServerAddress` 语义）。
void main() {
  group('SessionAssembly 注册表', () {
    test('现状只注册一个协议实现（26.2），新增版本改装配点而非业务代码', () {
      expect(SessionAssembly.registeredProtocols, hasLength(1));
    });

    test('注册分支：按条目协议号建出对应实现的会话，参数原样传入', () {
      final protocol = SessionAssembly.registeredProtocols.single;
      final session = SessionAssembly.createSession(
        host: '127.0.0.1',
        port: 25566,
        playerName: 'flutter_mc',
        protocol: protocol,
      );

      expect(SessionAssembly.isSupported(protocol), isTrue);
      expect(session.host, '127.0.0.1');
      expect(session.port, 25566);
      expect(session.playerName, 'flutter_mc');
      expect(session.protocolId, protocol);
    });

    test('未注册分支：createSession 抛 UnsupportedProtocolError，不回退默认实现', () {
      expect(SessionAssembly.isSupported(999999), isFalse);
      expect(
        () => SessionAssembly.createSession(
          host: '127.0.0.1',
          port: 25565,
          playerName: 'flutter_mc',
          protocol: 999999,
        ),
        throwsA(
          isA<UnsupportedProtocolError>()
              .having((e) => e.protocol, 'protocol', 999999),
        ),
      );
    });

    test('connectFor：未注册版本在 spawn isolate 之前同步拒绝', () {
      final server = ServerData(name: '旧版服务器', ip: '127.0.0.1:25565', protocol: 340);

      expect(
        () => SessionAssembly.connectFor(server, playerName: 'flutter_mc'),
        throwsA(isA<UnsupportedProtocolError>()),
      );
    });

    test('connectFor：注册版本起 worker isolate 会话，连接失败经事件流回传', () async {
      final protocol = SessionAssembly.registeredProtocols.single;
      // 端口 1 无服务 → 连接失败折叠为 SessionClosed（不抛、不悬挂）。
      final server = ServerData(name: '空端口', ip: '127.0.0.1:1', protocol: protocol);

      final handle = await SessionAssembly.connectFor(
        server,
        playerName: 'flutter_mc',
      );
      addTearDown(handle.close);
      expect(handle.commands, isNotNull);

      expect(await handle.events.first, isA<SessionClosed>());
    });
  });

  group('ServerAddress（原版 resolver.ServerAddress）', () {
    test('parseString：host[:port]，未写端口回落 25565', () {
      expect(
        ServerAddress.parseString('example.com'),
        const ServerAddress('example.com', 25565),
      );
      expect(
        ServerAddress.parseString('example.com:25566'),
        const ServerAddress('example.com', 25566),
      );
      expect(
        ServerAddress.parseString('127.0.0.1:25565'),
        const ServerAddress('127.0.0.1', 25565),
      );
    });

    test('parseString：IPv6 字面量（方括号带端口 / 不带端口 / 裸写）', () {
      expect(ServerAddress.parseString('[::1]'), const ServerAddress('::1', 25565));
      expect(
        ServerAddress.parseString('[::1]:25566'),
        const ServerAddress('::1', 25566),
      );
      // Guava 语义：2 个以上冒号且无方括号 ⇒ 整串视作主机名（无端口）
      expect(ServerAddress.parseString('::1'), const ServerAddress('::1', 25565));
    });

    test('parseString：解析失败一律回落 INVALID（server.invalid:25565）', () {
      expect(ServerAddress.parseString(null), ServerAddress.invalid);
      expect(ServerAddress.parseString(''), ServerAddress.invalid);
      expect(ServerAddress.parseString(':25565'), ServerAddress.invalid);
      expect(ServerAddress.parseString('example.com:'), ServerAddress.invalid);
      expect(ServerAddress.parseString('example.com:70000'), ServerAddress.invalid);
      expect(ServerAddress.parseString('example.com:-1'), ServerAddress.invalid);
      expect(ServerAddress.parseString('[::1'), ServerAddress.invalid);
      expect(ServerAddress.parseString('[::1]x'), ServerAddress.invalid);
    });

    test('parsePort：非数字回落 25565（原版语义）', () {
      expect(ServerAddress.parsePort(' 25566 '), 25566);
      expect(ServerAddress.parsePort('abc'), 25565);
    });

    test('isValidAddress：能切出非空 host 即合法', () {
      expect(ServerAddress.isValidAddress('example.com'), isTrue);
      expect(ServerAddress.isValidAddress(':25565'), isFalse);
    });
  });
}
