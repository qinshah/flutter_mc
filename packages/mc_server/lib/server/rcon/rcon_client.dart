// 原版 RCON 只有**服务端**（net/minecraft/server/rcon/thread/RconClient.java 处理入站连接），
// 不存在客户端类；本文件是同一**线格式**的对偶实现——请求帧编码、报文类型、字节序逐项照原版，
// 不含任何自造字段。原版无客户端这一事实不属三类自由设计，故此处以「同一线格式的对称实现」
// 落位（记录于本注释与包 README）。
//
// 判据（相对 mc-sources/minecraft-26.2/net/minecraft/）：
//   RconClient.java:17-21 —— 报文类型常量
//   RconClient.java:108-119 —— send：`[len=bytes+10][requestid][cmd][bytes][0][0]`，三个 int 用
//                              Integer.reverseBytes（即小端）
//   RconClient.java:121-123 —— sendAuthFailure：`send(-1, 2, "")`
//   RconClient.java:79-90  —— 鉴权成功回 `send(requestid, 2, "")`；失败回 `-1`
//   RconClient.java:125-134 —— sendCmdResponse：响应按 4096 **字符** 拆多包（type=0）
//   RconClient.java:48-63  —— 读入侧按 `pktsize = intFromByteArray(buf,0,read)`、`offset` 逐 4 字节推进
//
// 原版服务端的读取按"一次 read 恰好一包"假设（:55 `pktsize != read - 4`）；本客户端改为按
// 长度前缀读满整包，仅在 TCP 粘包/拆包时更稳，不改线格式。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'pkt_utils.dart';

/// 一条 RCON 报文（解码后）。
class RconPacket {
  final int requestId;
  final int type;
  final String payload;
  const RconPacket(this.requestId, this.type, this.payload);
}

class RconClient {
  // RconClient.java:17-21
  static const int SERVERDATA_AUTH = 3;
  static const int SERVERDATA_EXECCOMMAND = 2;
  static const int SERVERDATA_RESPONSE_VALUE = 0;
  static const int SERVERDATA_AUTH_RESPONSE = 2;
  static const int SERVERDATA_AUTH_FAILURE = -1;

  final Socket _socket;
  final StreamIterator<Uint8List> _reader;
  final List<int> _buffer = <int>[];

  RconClient._(this._socket) : _reader = StreamIterator<Uint8List>(_socket);

  /// 连接 RCON 服务端（原版默认端口见 RconThread.java:41 / DedicatedServerProperties.java:85）。
  static Future<RconClient> connect(String host, int port,
      {Duration? timeout}) async {
    final socket = timeout == null
        ? await Socket.connect(host, port)
        : await Socket.connect(host, port, timeout: timeout);
    return RconClient._(socket);
  }

  /// 编码一帧（照 RconClient.java:108-119；便于单测断言黄金字节）。
  static Uint8List encode(int requestId, int type, String payload) {
    final bytes = utf8.encode(payload);
    final out = BytesBuilder();
    void writeIntLE(int v) {
      // Integer.reverseBytes(v) 的等价：小端 4 字节。
      out.addByte(v & 0xFF);
      out.addByte((v >> 8) & 0xFF);
      out.addByte((v >> 16) & 0xFF);
      out.addByte((v >> 24) & 0xFF);
    }

    writeIntLE(bytes.length + 10); // :112
    writeIntLE(requestId); // :113
    writeIntLE(type); // :114
    out.add(bytes); // :115
    out.addByte(0); // :116
    out.addByte(0); // :117
    return out.toBytes();
  }

  /// 鉴权：发 `SERVERDATA_AUTH`（:79-90）。
  ///
  /// 成功判定照原版服务端的两种回包：成功回 `send(requestid, type=2, "")`（:84），
  /// 失败回 `send(-1, 2, "")`（:121-123）——故"回包 requestid == 我方 requestid"即成功。
  Future<bool> authenticate(String password, {int requestId = 1}) async {
    _socket.add(encode(requestId, SERVERDATA_AUTH, password));
    await _socket.flush();
    final response = await readPacket();
    return response.requestId == requestId;
  }

  /// 执行一条指令：发 `SERVERDATA_EXECCOMMAND`（:64-78）。
  ///
  /// 服务端响应为 `SERVERDATA_RESPONSE_VALUE`（type=0）。原版 `sendCmdResponse`（:125-134）
  /// 在响应超过 4096 **字符** 时拆成多包；本方法只读**第一包**，需要完整输出时由调用方循环
  /// 调用 [readPacket] 续读（原版无客户端，续读策略无判据，故不做隐式推断）。
  Future<String> execCommand(String command, {int requestId = 2}) async {
    _socket.add(encode(requestId, SERVERDATA_EXECCOMMAND, command));
    await _socket.flush();
    final packet = await readPacket();
    return packet.payload;
  }

  /// 读满一包并解码（照 RconClient.java:48-63 的字段推进）。
  Future<RconPacket> readPacket() async {
    final lengthBytes = await _readBytes(4);
    final length =
        PktUtils.intFromByteArray(Uint8List.fromList(lengthBytes), 0, 4);
    final bodyBytes = Uint8List.fromList(await _readBytes(length));
    final requestId = PktUtils.intFromByteArray(bodyBytes, 0, length);
    final type = PktUtils.intFromByteArray(bodyBytes, 4, length);
    final payload = PktUtils.stringFromByteArray(bodyBytes, 8, length);
    return RconPacket(requestId, type, payload);
  }

  Future<List<int>> _readBytes(int n) async {
    while (_buffer.length < n) {
      if (!await _reader.moveNext()) {
        throw const SocketException('RCON 连接已关闭');
      }
      _buffer.addAll(_reader.current);
    }
    final result = _buffer.sublist(0, n);
    _buffer.removeRange(0, n);
    return result;
  }

  Future<void> close() async {
    await _reader.cancel();
    _socket.destroy();
  }
}
