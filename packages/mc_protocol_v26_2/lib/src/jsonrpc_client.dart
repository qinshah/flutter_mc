// 管理服务器客户端：JSON-RPC 2.0 over WebSocket。
//
//   ⚠ 原版只有**服务端**（`server/jsonrpc/**`：ManagementServer / Connection / AuthenticationHandler）；
//   本文件是其线协议的**对偶实现**——信封字段、鉴权头、子协议、路径逐项照原版，不含自造字段。
//   （管理服务器本身是 26.2 特性，故落在版本包 `mc_protocol_v26_2`，见 design.md D8。）
//
// 判据（相对 mc-sources/minecraft-26.2/net/minecraft/）：
//   JsonRPCUtils.java:12-13 —— JSON_RPC_VERSION = "2.0"、OPEN_RPC_VERSION = "1.3.2"
//   JsonRPCUtils.java:27-46 —— createRequest：`jsonrpc`,`id`（非 null 才带）,`method`,`params`
//                              （仅当非空才带，且为数组）
//   JsonRPCUtils.java:15-21 —— createSuccessResult：`jsonrpc`,`id`,`result`
//   JsonRPCUtils.java:48-61 —— createError：`error.code` / `error.message` / `error.data`（非空才带）
//   AuthenticationHandler.java:31   —— BEARER_PREFIX = "Bearer "
//   AuthenticationHandler.java:29-30 —— 子协议值 "minecraft-v1"、头前缀 "minecraft-v1,"
//   AuthenticationHandler.java:106-114 —— Bearer / Sec-WebSocket-Protocol 的取值与 trim
//   AuthenticationHandler.java:101-104 —— 子协议路径要求 Origin ∈ allowedOrigins
//   AuthenticationHandler.java:111-113 —— 服务端解析子协议头：`startsWith("minecraft-v1,")`
//                                          后对余下部分 trim（故 `minecraft-v1,<secret>` 与
//                                          `minecraft-v1, <secret>` 皆接受）
//   AuthenticationHandler.java:70-74 —— 子协议鉴权成功后服务端回 `Sec-WebSocket-Protocol: minecraft-v1`
//   ManagementServer.java:116 —— WebSocket 路径为 "/"
//   JsonRpc.java:19/:21/:37-42 —— tls-enabled 为真走 TLS（wss），否则明文（ws）
//   Connection.java:146-155 —— 出站请求 id 自增；:149 五秒等待上限
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 远端返回的 JSON-RPC error 对象（JsonRPCUtils.java:48-61）。
class JsonRpcException implements Exception {
  final int? code;
  final String message;
  final String? data;

  JsonRpcException(this.code, this.message, this.data);

  factory JsonRpcException.fromJson(Map<String, dynamic> json) => JsonRpcException(
        json['code'] is int ? json['code'] as int : null,
        json['message']?.toString() ?? '',
        json['data']?.toString(),
      );

  @override
  String toString() => 'JsonRpcException($code, $message, $data)';
}

class JsonRpcClient {
  /// JsonRPCUtils.java:12
  static const String jsonRpcVersion = '2.0';

  /// JsonRPCUtils.java:13
  static const String openRpcVersion = '1.3.2';

  /// AuthenticationHandler.java:29
  static const String subprotocolValue = 'minecraft-v1';

  /// AuthenticationHandler.java:30
  static const String subprotocolHeaderPrefix = 'minecraft-v1,';

  /// AuthenticationHandler.java:31
  static const String bearerPrefix = 'Bearer ';

  /// Connection.java:149（5000L）
  static const Duration defaultTimeout = Duration(milliseconds: 5000);

  final WebSocket _socket;
  final Duration _timeout;
  int _nextId = 0;
  final Map<int, Completer<Object?>> _pending = <int, Completer<Object?>>{};
  late final StreamSubscription<dynamic> _subscription;

  JsonRpcClient._(this._socket, this._timeout) {
    _subscription = _socket.listen(_onData, onDone: _onDone, onError: _onError);
  }

  /// 连接管理服务器（路径 "/"，见 ManagementServer.java:116）。
  ///
  /// [useSubprotocol] 为假走 `Authorization: Bearer <secret>`；为真走
  /// `Sec-WebSocket-Protocol: minecraft-v1,<secret>`，此路径原版还要求 Origin 在
  /// allowedOrigins 内（AuthenticationHandler.java:89-90），故须提供 [origin]。
  static Future<JsonRpcClient> connect(
    Uri uri, {
    required String secret,
    bool useSubprotocol = false,
    String? origin,
    Duration timeout = defaultTimeout,
  }) async {
    Map<String, dynamic>? headers;
    List<String>? protocols;
    if (useSubprotocol) {
      protocols = <String>[subprotocolValue, secret];
      if (origin != null) headers = <String, dynamic>{'Origin': origin};
    } else {
      headers = <String, dynamic>{'Authorization': '$bearerPrefix$secret'};
    }
    final socket = await WebSocket.connect(
      uri.toString(),
      headers: headers,
      protocols: protocols,
    ).timeout(timeout);
    return JsonRpcClient._(socket, timeout);
  }

  /// 发起一次请求（照 JsonRPCUtils.java:27-46 的信封；`params` 为空时不带该字段）。
  Future<Object?> call(String method,
      [List<Object?> params = const <Object?>[]]) async {
    final id = ++_nextId; // Connection.java:147 的自增事务 id
    final request = <String, Object?>{
      'jsonrpc': jsonRpcVersion,
      'id': id,
      'method': method,
    };
    if (params.isNotEmpty) request['params'] = params;

    final completer = Completer<Object?>();
    _pending[id] = completer;
    _socket.add(jsonEncode(request));
    try {
      return await completer.future.timeout(_timeout);
    } finally {
      _pending.remove(id);
    }
  }

  void _onData(dynamic data) {
    if (data is! String) return;
    final decoded = jsonDecode(data);
    if (decoded is! Map<String, dynamic>) return;
    final id = decoded['id'];
    if (id is! int) {
      // 无 id 即通知（如 server/status 心跳）。本客户端不消费：宿主就绪判定取原版
      // stdout 就绪行（design.md D4），不依赖心跳。
      return;
    }
    final completer = _pending.remove(id);
    if (completer == null) return;
    final error = decoded['error'];
    if (error is Map) {
      completer.completeError(
          JsonRpcException.fromJson(error.cast<String, dynamic>()));
    } else {
      completer.complete(decoded['result']);
    }
  }

  void _onDone() {
    _failAll(StateError('管理服务器连接已关闭'));
  }

  void _onError(Object error, StackTrace stackTrace) {
    _failAll(error);
  }

  void _failAll(Object error) {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pending.clear();
  }

  Future<void> close() async {
    await _subscription.cancel();
    await _socket.close();
  }
}
