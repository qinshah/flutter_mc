// 管理服务器客户端的对偶实现测试。
//
// 原版只有服务端（AuthenticationHandler / ManagementServer / JsonRPCUtils），
// 故本测试用一个**本地 mock WebSocket 服务端**复现原版接入与信封语义，断言客户端：
//   * 以 `Authorization: Bearer <secret>`（AuthenticationHandler.java:31、:79-85）接入，
//     或
//   * 以 `Sec-WebSocket-Protocol: minecraft-v1,<secret>` + 允许的 Origin
//     （AuthenticationHandler.java:29-30、:87-95、:101-104）接入；
//   * 发出的请求 JSON 与 `JsonRPCUtils.createRequest`（:27-46）逐字节一致；
//   * `rpc.discover` 响应形状与 `DiscoveryService.DiscoverResponse`（:65-73）一致。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mc_protocol_v26_2/mc_protocol_v26_2.dart';
import 'package:test/test.dart';

/// 本地 mock 管理服务器：WS 路径 `/`（ManagementServer.java:116），
/// 按 [respond] 回 JSON-RPC 响应，并把收到的原始请求串记进 [received]。
class _MockManagementServer {
  final HttpServer _http;

  /// 按到达顺序记录客户端发来的原始 JSON 文本。
  final List<String> received = <String>[];

  _MockManagementServer._(this._http);

  int get port => _http.port;

  static Future<_MockManagementServer> start({
    required bool expectBearer,
    required String secret,
    required Map<String, dynamic> Function(Map<String, dynamic> request)
        respond,
  }) async {
    final http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final mock = _MockManagementServer._(http);
    http.listen((request) async {
      // 判据 AuthenticationHandler.java:79-99：先看 Bearer，再看子协议 + Origin。
      if (expectBearer) {
        expect(request.headers.value('authorization'), 'Bearer $secret');
        expect(request.headers.value('sec-websocket-protocol'), isNull);
      } else {
        // 照 AuthenticationHandler.java:111-113 的解析：前缀匹配后 trim。
        final protoHeader = request.headers.value('sec-websocket-protocol');
        expect(protoHeader, isNotNull);
        expect(protoHeader!.startsWith('minecraft-v1,'), isTrue);
        expect(protoHeader.substring('minecraft-v1,'.length).trim(), secret);
        expect(request.headers.value('origin'), 'http://localhost');
      }
      expect(request.uri.path, '/'); // ManagementServer.java:116

      final ws = await WebSocketTransformer.upgrade(
        request,
        protocolSelector:
            expectBearer ? null : (List<String> _) => 'minecraft-v1',
      );
      ws.listen((data) {
        final text = data.toString();
        mock.received.add(text);
        final req = jsonDecode(text) as Map<String, dynamic>;
        ws.add(jsonEncode(respond(req)));
      });
    });
    return mock;
  }

  Future<void> close() => _http.close(force: true);
}

/// 原版 `createSuccessResult`（JsonRPCUtils.java:15-21）形状的成功响应。
Map<String, dynamic> _success(Object? id, Object? result) =>
    <String, dynamic>{'jsonrpc': '2.0', 'id': id, 'result': result};

void main() {
  const secret = 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789AbCd'; // 40 字符字母数字

  test('方法名常量逐字对齐原版 IncomingRpcMethods.java', () {
    // 抽样核对（含点、斜杠、下划线三种形态）。
    expect(ManagementMethods.rpcDiscover, 'rpc.discover');
    expect(ManagementMethods.serverStatus, 'server/status');
    expect(ManagementMethods.serverStop, 'server/stop');
    expect(ManagementMethods.serverSystemMessage, 'server/system_message');
    expect(ManagementMethods.playersKick, 'players/kick');
    expect(
      ManagementMethods.serversettingsPauseWhenEmptySeconds,
      'serversettings/pause_when_empty_seconds',
    );
    expect(ManagementMethods.ipBans, 'ip_bans');
    expect(ManagementMethods.gamerulesUpdate, 'gamerules/update');
  });

  test('Bearer 路径：discover + server/status，请求 JSON 逐字对齐', () async {
    final mock = await _MockManagementServer.start(
      expectBearer: true,
      secret: secret,
      respond: (req) {
        final id = req['id'];
        switch (req['method']) {
          case 'rpc.discover':
            // DiscoveryService.java:34-35、:65-73。
            return _success(id, <String, dynamic>{
              'openrpc': '1.3.2',
              'info': <String, dynamic>{
                'title': 'Minecraft Server JSON-RPC',
                'version': '3.0.0',
              },
              'methods': <Object?>[],
              'components': <String, dynamic>{'schemas': <String, dynamic>{}},
            });
          case 'server/status':
            // ServerStateService.java:63-73。
            return _success(id, <String, dynamic>{
              'started': true,
              'players': <Object?>[],
              'version': <String, dynamic>{
                'name': '26.2',
                'protocol': 776,
              },
            });
          default:
            return _success(id, null);
        }
      },
    );

    final client = await JsonRpcClient.connect(
      Uri.parse('ws://127.0.0.1:${mock.port}/'),
      secret: secret,
    );

    final discovered = await discover(client);
    expect(discovered['openrpc'], '1.3.2');
    expect((discovered['info'] as Map)['version'], '3.0.0');
    expect(
      mock.received[0],
      '{"jsonrpc":"2.0","id":1,"method":"rpc.discover"}',
    );

    final status = await serverStatus(client);
    expect(status['started'], isTrue);
    expect(mock.received[1], '{"jsonrpc":"2.0","id":2,"method":"server/status"}');

    await client.close();
    await mock.close();
  });

  test('子协议路径：minecraft-v1,<secret> + Origin', () async {
    final mock = await _MockManagementServer.start(
      expectBearer: false,
      secret: secret,
      respond: (req) => _success(req['id'], <String, dynamic>{
        'openrpc': '1.3.2',
        'info': <String, dynamic>{'title': 'x', 'version': '3.0.0'},
        'methods': <Object?>[],
        'components': <String, dynamic>{'schemas': <String, dynamic>{}},
      }),
    );

    final client = await JsonRpcClient.connect(
      Uri.parse('ws://127.0.0.1:${mock.port}/'),
      secret: secret,
      useSubprotocol: true,
      origin: 'http://localhost',
    );

    final discovered = await discover(client);
    expect(discovered['openrpc'], '1.3.2');
    expect(
      mock.received[0],
      '{"jsonrpc":"2.0","id":1,"method":"rpc.discover"}',
    );

    await client.close();
    await mock.close();
  });

  test('带 params 的请求：params 为数组（JsonRPCUtils.java:35-43）', () async {
    final mock = await _MockManagementServer.start(
      expectBearer: true,
      secret: secret,
      respond: (req) => _success(req['id'], true),
    );

    final client = await JsonRpcClient.connect(
      Uri.parse('ws://127.0.0.1:${mock.port}/'),
      secret: secret,
    );

    await client.call(ManagementMethods.playersKick, <Object?>[
      <String, dynamic>{'name': 'Steve'},
    ]);
    expect(
      mock.received[0],
      '{"jsonrpc":"2.0","id":1,"method":"players/kick",'
      '"params":[{"name":"Steve"}]}',
    );

    await client.close();
    await mock.close();
  });

  test('错误响应 → JsonRpcException（JsonRPCUtils.java:48-61）', () async {
    final mock = await _MockManagementServer.start(
      expectBearer: true,
      secret: secret,
      respond: (req) => <String, dynamic>{
        'jsonrpc': '2.0',
        'id': req['id'],
        'error': <String, dynamic>{
          'code': -32601,
          'message': 'Method not found',
        },
      },
    );

    final client = await JsonRpcClient.connect(
      Uri.parse('ws://127.0.0.1:${mock.port}/'),
      secret: secret,
    );

    await expectLater(
      client.call('no/such'),
      throwsA(
        isA<JsonRpcException>()
            .having((e) => e.code, 'code', -32601)
            .having((e) => e.message, 'message', 'Method not found'),
      ),
    );

    await client.close();
    await mock.close();
  });
}
