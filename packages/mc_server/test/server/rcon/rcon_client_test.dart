// 判据：RconClient.java:17-21（类型常量）、:108-119（send 帧）、:121-123（失败回包）、
// :125-134（响应拆包）。原版无客户端类，本测试校验的是对偶实现与原版线格式逐字节一致。
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:mc_server/mc_server.dart';
import 'package:test/test.dart';

void main() {
  group('encode：帧布局照 RconClient.java:112-117 离线递推', () {
    test('鉴权帧 requestId=1 type=3 payload="test"', () {
      // len = 4("test") + 10 = 14 = 0x0E；三处 int 皆 Integer.reverseBytes（小端）。
      final bytes = RconClient.encode(1, RconClient.SERVERDATA_AUTH, 'test');
      expect(bytes, <int>[
        0x0E, 0x00, 0x00, 0x00, // length
        0x01, 0x00, 0x00, 0x00, // requestId
        0x03, 0x00, 0x00, 0x00, // type = SERVERDATA_AUTH
        0x74, 0x65, 0x73, 0x74, // "test"
        0x00, 0x00, // 两个结尾 0
      ]);
    });

    test('指令帧 requestId=2 type=2 payload="list"', () {
      final bytes =
          RconClient.encode(2, RconClient.SERVERDATA_EXECCOMMAND, 'list');
      expect(bytes, <int>[
        0x0E, 0x00, 0x00, 0x00,
        0x02, 0x00, 0x00, 0x00,
        0x02, 0x00, 0x00, 0x00, // SERVERDATA_EXECCOMMAND
        0x6C, 0x69, 0x73, 0x74, // "list"
        0x00, 0x00,
      ]);
    });

    test('失败帧 requestId=-1 → FF FF FF FF（RconClient.java:121-123）', () {
      final bytes = RconClient.encode(-1, RconClient.SERVERDATA_AUTH_RESPONSE, '');
      expect(bytes, <int>[
        0x0A, 0x00, 0x00, 0x00,
        0xFF, 0xFF, 0xFF, 0xFF,
        0x02, 0x00, 0x00, 0x00,
        0x00, 0x00,
      ]);
    });
  });

  test('鉴权成功：mock 回 (requestId, 2, "")', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final done = _serveOnce(server, (frame, socket) async {
      expect(frame.type, RconClient.SERVERDATA_AUTH);
      expect(frame.payload, 'secret');
      // RconClient.java:84 —— 成功回 requestid 原样。
      socket.add(RconClient.encode(
          frame.requestId, RconClient.SERVERDATA_AUTH_RESPONSE, ''));
      await socket.flush();
    });
    final client = await RconClient.connect('127.0.0.1', server.port);
    expect(await client.authenticate('secret'), isTrue);
    await client.close();
    await done;
    await server.close();
  });

  test('鉴权失败：mock 回 (-1, 2, "")', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final done = _serveOnce(server, (frame, socket) async {
      // RconClient.java:121-123 —— 失败回 -1。
      socket.add(RconClient.encode(
          RconClient.SERVERDATA_AUTH_FAILURE, RconClient.SERVERDATA_AUTH_RESPONSE, ''));
      await socket.flush();
    });
    final client = await RconClient.connect('127.0.0.1', server.port);
    expect(await client.authenticate('secret'), isFalse);
    await client.close();
    await done;
    await server.close();
  });

  test('execCommand 返回响应负载（type=0）', () async {
    const response = 'There are 0 of a max of 20 players online';
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final done = _serveOnce(server, (frame, socket) async {
      expect(frame.type, RconClient.SERVERDATA_EXECCOMMAND);
      expect(frame.payload, 'list');
      socket.add(RconClient.encode(
          frame.requestId, RconClient.SERVERDATA_RESPONSE_VALUE, response));
      await socket.flush();
    });
    final client = await RconClient.connect('127.0.0.1', server.port);
    expect(await client.execCommand('list'), response);
    await client.close();
    await done;
    await server.close();
  });
}

/// 接受一次连接、读一帧、交给 [handler]，随后收尾。
Future<void> _serveOnce(
  ServerSocket server,
  Future<void> Function(RconPacket frame, Socket socket) handler,
) async {
  final socket = await server.first;
  final iterator = StreamIterator<Uint8List>(socket);
  final frame = await _readFrame(iterator);
  await handler(frame, socket);
  await iterator.cancel();
  socket.destroy();
}

Future<RconPacket> _readFrame(StreamIterator<Uint8List> iterator) async {
  final buffer = <int>[];
  Future<void> need(int n) async {
    while (buffer.length < n) {
      if (!await iterator.moveNext()) throw StateError('连接已关闭');
      buffer.addAll(iterator.current);
    }
  }

  await need(4);
  final length =
      PktUtils.intFromByteArray(Uint8List.fromList(buffer.sublist(0, 4)), 0, 4);
  await need(4 + length);
  final body = Uint8List.fromList(buffer.sublist(4, 4 + length));
  return RconPacket(
    PktUtils.intFromByteArray(body, 0, length),
    PktUtils.intFromByteArray(body, 4, length),
    PktUtils.stringFromByteArray(body, 8, length),
  );
}
