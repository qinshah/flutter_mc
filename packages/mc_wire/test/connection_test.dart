import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:mc_wire/mc_wire.dart';
import 'package:test/test.dart';

/// 端到端传输层测试：真实 Socket + 回环 server（无需版本包）。
void main() {
  late ServerSocket server;
  late WireConnection conn;

  setUp(() async {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  });

  tearDown(() async {
    await server.close();
  });

  test('握手帧原样到达 server；raw 回应钩子自动回 pong', () async {
    final gotFrames = <Uint8List>[];
    server.listen((client) {
      var buffer = BytesBuilder();
      client.listen((data) {
        buffer.add(data);
        var bytes = buffer.toBytes();
        // 简易解帧（server 侧测试桩）：读到完整帧就记录并回 pong
        while (true) {
          final len = _tryVarInt(bytes);
          if (len == null) break;
          final bodyStart = len.next;
          if (bytes.length - bodyStart < len.value) break;
          final frame = Uint8List.sublistView(bytes, bodyStart, bodyStart + len.value);
          gotFrames.add(frame);
          client.add(encodeFrame(frame)); // echo（含包 id），模拟 pong 回应
          buffer = BytesBuilder()..add(bytes.sublist(bodyStart + len.value));
          bytes = buffer.toBytes();
        }
      });
    });

    conn = await WireConnection.connect(
      InternetAddress.loopbackIPv4.address,
      server.port,
      PacketRegistry(),
    );

    // 客户端发 handshake（id 0x00 + varint intent）与 ping（id 0x01 + long）
    conn.sendRaw(ProtocolPhase.handshake, 0x00, [0x01]);
    conn.sendRaw(ProtocolPhase.handshake, 0x01, [0x01, 0x02]);

    final received = <InboundPacket<Object?>>[];
    final sub = conn.inbound.listen(received.add);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    sub.cancel();

    // server 收到两帧（粘包正确拆分）
    expect(gotFrames, hasLength(2));
    // echo 的两帧以未登记包身份到达客户端（registry 里没登记 0x00/0x01）
    expect(received, hasLength(2));
    expect(received[0].packetId, 0x00);
    expect(received[1].packetId, 0x01);
    expect(received[1].body, [0x01, 0x02]);

    await conn.close();
  });

  test('raw 回应钩子：登记 keep-alive 形态的 echo', () async {
    var echoed = 0;
    server.listen((client) {
      client.listen((data) {
        // 只 echo 第一帧：真实服务器不会回应 keep-alive 的回应，
        // 全量 echo 会与 raw 回应钩子形成回声循环
        if (echoed++ == 0) client.add(data);
      });
    });

    conn = await WireConnection.connect(
      InternetAddress.loopbackIPv4.address,
      server.port,
      PacketRegistry(),
    );
    // 假装 play/0x23 是 keep-alive：回应换用 serverbound id 0x24（载荷原样）
    conn.rawEcho = (phase, id, body) =>
        phase == ProtocolPhase.play && id == 0x23 ? 0x24 : null;
    // 但回应发生在 play 阶段判定——先让状态机到位
    conn.phaseMachine.startFromHandshake(ClientIntent.login);
    conn.phaseMachine.loginFinished();
    conn.phaseMachine.configurationFinished();

    final received = <InboundPacket<Object?>>[];
    final sub = conn.inbound.listen(received.add);

    // 模拟 server 下发 keep-alive（echo server 会把它原样弹回来）
    conn.sendRaw(ProtocolPhase.play, 0x23, [0xAB]);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    // 钩子把弹回的 keep-alive 转成了 raw 回应（不再进 inbound 流）
    expect(received.where((p) => p.packetId == 0x23), isEmpty);
    sub.cancel();
    await conn.close();
  });

  test('压缩开启后的端到端往返', () async {
    server.listen((client) {
      client.listen((data) => client.add(data)); // echo all
    });

    conn = await WireConnection.connect(
      InternetAddress.loopbackIPv4.address,
      server.port,
      PacketRegistry(),
    );
    conn.setCompression(64);
    final payload = List.filled(200, 0x55);

    final received = <InboundPacket<Object?>>[];
    final sub = conn.inbound.listen(received.add);
    conn.sendRaw(ProtocolPhase.configuration, 0x10, payload);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(received, hasLength(1));
    expect(received[0].body, payload); // 压缩→解压后字节一致
    sub.cancel();
    await conn.close();
  });
}

class _Len {
  const _Len(this.value, this.next);
  final int value;
  final int next;
}

_Len? _tryVarInt(List<int> bytes) {
  var result = 0;
  var shift = 0;
  var i = 0;
  while (i < bytes.length) {
    final b = bytes[i++];
    result |= (b & 0x7F) << shift;
    if ((b & 0x80) == 0) return _Len(result, i);
    shift += 7;
    if (shift >= 35) return null;
  }
  return null;
}
