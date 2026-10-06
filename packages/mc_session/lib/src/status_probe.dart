import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mc_wire/mc_wire.dart';

/// 26.2 status ping（tasks 5.2 探测入口；remote-play「状态探测与协议号实测」）。
///
/// 握手 protocolVersion 字段在 STATUS intent 下服务器不校验，填 0；
/// 真实协议号从响应 JSON 的 `version.protocol` 取（判据：
/// `ServerHandshakePacketListenerImpl` 的校验只在 LOGIN 分支；实测过程见 change notes 1.1）。
final class ServerInfo {
  ServerInfo({
    required this.protocolId,
    required this.versionName,
    required this.motd,
    required this.playersOnline,
    required this.playersMax,
    required this.rawJson,
  });

  final int protocolId;
  final String versionName;
  final String motd;
  final int playersOnline;
  final int playersMax;

  /// 原始 JSON（原样保留，未识别字段不丢失）。
  final String rawJson;

  static ServerInfo parse(String json) {
    final obj = jsonDecode(json) as Map<String, dynamic>;
    final version = obj['version'] as Map<String, dynamic>?;
    final players = obj['players'] as Map<String, dynamic>?;
    return ServerInfo(
      protocolId: (version?['protocol'] as num?)?.toInt() ?? 0,
      versionName: version?['name'] as String? ?? '?',
      motd: jsonEncode(obj['description'] ?? ''),
      playersOnline: (players?['online'] as num?)?.toInt() ?? 0,
      playersMax: (players?['max'] as num?)?.toInt() ?? 0,
      rawJson: json,
    );
  }
}

final class PingFailure implements Exception {
  PingFailure(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// 持久订阅的帧读取器（probe/短连接用；会话内 WireConnection 自带解帧）。
class _FrameReader {
  final BytesBuilder _pending = BytesBuilder();
  late StreamSubscription<Uint8List> _sub;

  _FrameReader(Socket socket) {
    // 短连接对端随时可能 RST（destroy/超时/服务器踢）——错误必须就地消化，
    // 否则会以未处理异步错误的形式逃出调用方（实测被测试运行器记到
    // 别的用例头上）。
    _sub = socket.listen(
      _pending.add,
      onError: (Object _) {},
      cancelOnError: true,
    );
  }

  Future<Uint8List> next() async {
    while (true) {
      final bytes = _pending.toBytes();
      final parsed = _tryVarIntFull(bytes, 0);
      if (parsed != null) {
        final (len, next) = parsed;
        if (bytes.length - next >= len) {
          final frame = Uint8List.sublistView(bytes, next, next + len);
          _pending.clear();
          _pending.add(bytes.sublist(next + len));
          return frame;
        }
      }
      await Future<void>.delayed(const Duration(microseconds: 200));
    }
  }

  void cancel() => _sub.cancel();
}

(int, int)? _tryVarIntFull(List<int> bytes, int offset) {
  var result = 0;
  var shift = 0;
  var i = offset;
  while (i < bytes.length) {
    final b = bytes[i++];
    result |= (b & 0x7F) << shift;
    if ((b & 0x80) == 0) return (result, i);
    shift += 7;
    if (shift >= 35) return null;
  }
  return null;
}

/// 对目标做一次 status ping 并断开（独立短连接，不占用会话）。
Future<ServerInfo> pingServer(
  String host,
  int port, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  final Socket socket;
  try {
    socket = await Socket.connect(host, port, timeout: timeout);
  } on SocketException catch (e) {
    throw PingFailure('无法连接到 $host:$port（${e.message}）');
  }
  final reader = _FrameReader(socket);
  try {
    final w = ByteWriter();
    // handshake：id 0 + varint version(0) + utf host + ushort port + varint intent=STATUS
    final body = ByteWriter();
    body.writeVarInt(0);
    body.writeUtf(host, 255);
    body.writeUnsignedShort(port);
    body.writeVarInt(ClientIntent.status.id);
    w.writeVarInt(body.length + 1); // 帧长 = 包体 + 包 id 字节
    w.writeVarInt(0); // 包 id
    w.writeBytes(body.takeBytes());
    // status request：包 id 0，空体
    w.writeVarInt(1);
    w.writeVarInt(0);
    socket.add(w.takeBytes());

    final response = await reader.next().timeout(timeout);
    final r = ByteReader(response);
    if (r.readVarInt() != 0) {
      throw PingFailure('status 响应包 id 非法');
    }
    final json = r.readUtf();
    final info = ServerInfo.parse(json);

    // ping/pong：包 id 1 + long（可选步骤，失败不影响结果）
    final now = DateTime.now().microsecondsSinceEpoch;
    final pw = ByteWriter();
    final pingBody = ByteWriter();
    pingBody.writeVarInt(1);
    pingBody.writeLong(now);
    pw.writeVarInt(pingBody.length);
    pw.writeBytes(pingBody.takeBytes());
    socket.add(pw.takeBytes());
    await reader.next().timeout(timeout);

    return info;
  } on FormatException catch (e) {
    throw PingFailure('服务器响应无法解析（${e.message}）');
  } on TimeoutException {
    throw PingFailure('连接 $host:$port 超时');
  } finally {
    reader.cancel();
    socket.destroy();
  }
}
