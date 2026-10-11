import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:mc_protocol_v26_2/mc_protocol_v26_2.dart';
import 'package:mc_wire/mc_wire.dart';
import 'package:test/test.dart' show fail;

/// 集成测试共用的脚本化 mock server 侧客户端（tasks 5.8 / 7.3）。
///
/// 工作在**裸帧层**（读 varint id + 手工编包）：26.2 编解码的字节正确性由
/// mc_protocol_v26_2 单测逐包验证，这里只编排会话时序（notes 1.2 清单）。
final class MockLoginClient {
  MockLoginClient(this._socket) {
    _decoder = FrameDecoder();
    _decodeCodec = FrameCodec();
    _socket.listen(
      (data) {
        for (final f in _decoder.push(data)) {
          final pkt = _decodeCodec.decode(f);
          final r = ByteReader(pkt);
          final id = r.readVarInt();
          received.add(ServerFrame(id, Uint8List.fromList(r.readRemaining())));
        }
      },
      // 断线路径测试里客户端 socket 会被 reset——错误必须就地消化，
      // 否则逃逸出测试 zone 被记到下一条用例头上
      onError: (Object _) {},
      onDone: () {},
      cancelOnError: true,
    );
  }

  final Socket _socket;
  late final FrameDecoder _decoder;
  late final FrameCodec _decodeCodec;
  final FrameCodec _encodeCodec = FrameCodec();

  /// 收到的服务器侧帧（id + 包体）。
  final List<ServerFrame> received = [];

  /// 顺序断言游标（[expectPacket] 递增）。
  int cursor = 0;

  bool _compressed = false;

  /// 发一个包（id 前缀 + body；压缩协商后自动带前缀）。
  void send(int id, [void Function(ByteWriter w)? body]) {
    final w = ByteWriter();
    w.writeVarInt(id);
    body?.call(w);
    if (_compressed) {
      _encodeCodec.threshold = 256;
      _socket.add(encodeFrame(_encodeCodec.encode(w.takeBytes())));
    } else {
      _socket.add(encodeFrame(w.takeBytes()));
    }
  }

  /// 等待客户端发来指定 id 的包（顺序对齐 [cursor]）。
  Future<void> expectPacket(int id,
      {Duration timeout = const Duration(seconds: 5)}) async {
    final deadline = DateTime.now().add(timeout);
    while (cursor >= received.length || received[cursor].id != id) {
      if (DateTime.now().isAfter(deadline)) {
        fail('等待包 $id 超时；已收到 ${received.map((f) => f.id).toList()}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    cursor++;
  }

  /// 等待累计收到 [n] 帧。
  Future<void> waitFrames(int n,
      {Duration timeout = const Duration(seconds: 5)}) async {
    final deadline = DateTime.now().add(timeout);
    while (received.length < n) {
      if (DateTime.now().isAfter(deadline)) {
        fail('等待 $n 帧超时；已收到 ${received.length}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  /// 把会话推到 play 阶段（notes 1.2 时序）：压缩 → login finished/ack →
  /// client information → known packs → registry ×2 → tags → finish/ack →
  /// play login → 配置完成、进入 play。**不等 playerLoaded**：2026-10-11 起
  /// 客户端按原版 LevelLoadTracker 就绪状态机改为命令驱动发送（session 命令
  /// sendPlayerLoaded），登录流不再自动发送——mock 只负责把会话推进到 play。
  Future<void> runToPlay() async {
    await waitFrames(2); // handshake + hello
    cursor = 2;

    // 1) 压缩协商（此后所有帧带 uncompressedSize 前缀）
    send(3, (w) => w.writeVarInt(256)); // login_compression
    _compressed = true;
    _decodeCodec.threshold = 256;

    // 2) login finished → 等客户端 login acknowledged
    send(2, (w) {
      for (var i = 0; i < 16; i++) {
        w.writeUnsignedByte(i);
      }
      w.writeUtf('flutter_mc', 16);
      for (var i = 0; i < 16; i++) {
        w.writeUnsignedByte(0xF0 | i); // sessionId UUID
      }
    });
    await expectPacket(LoginServerbound.loginAcknowledged);

    // 3) 配置阶段：客户端应主动发 client information
    await expectPacket(ConfigurationServerbound.clientInformation);

    // 4) known packs 请求 → 等回应（空列表）
    send(ConfigurationClientbound.selectKnownPacks, (w) => w.writeVarInt(0));
    await expectPacket(ConfigurationServerbound.selectKnownPacks);

    // 5) registry data ×2 + tags
    send(ConfigurationClientbound.registryData, (w) {
      w.writeUtf('minecraft:block');
      w.writeVarInt(4);
      for (final e in const [
        'minecraft:air',
        'minecraft:stone',
        'minecraft:dirt',
        'minecraft:grass_block',
      ]) {
        w.writeUtf(e);
        w.writeBool(false);
      }
    });
    send(ConfigurationClientbound.registryData, (w) {
      w.writeUtf('minecraft:worldgen/biome');
      w.writeVarInt(2);
      for (final e in const ['minecraft:plains', 'minecraft:desert']) {
        w.writeUtf(e);
        w.writeBool(false);
      }
    });
    send(ConfigurationClientbound.updateTags, (w) => w.writeVarInt(0));

    // 6) finish configuration → 等客户端 acknowledge
    send(ConfigurationClientbound.finishConfiguration, (_) {});
    await expectPacket(ConfigurationServerbound.finishConfiguration);

    // 7) play：login 包
    send(PlayClientbound.login, _writeGameLogin);
  }

  /// 发 play keep-alive（服务器侧 15s 节奏的模拟）。
  void sendPlayKeepAlive(int challenge) =>
      send(PlayClientbound.keepAlive, (w) => w.writeLong(challenge));

  /// 粗暴断开（模拟服务器停机/进程 kill）。
  void destroy() => _socket.destroy();

  /// 服务器主动断开 + 网络 NBT 理由（优雅断开）。
  void sendDisconnect(String text) =>
      send(PlayClientbound.disconnect, (w) => w.writeBytes(nbtText(text)));
}

/// online-mode 服务器的加密协商包（REF: ClientboundHelloPacket）。
void sendLoginHello(MockLoginClient client) {
  client.send(LoginClientbound.hello, (w) {
    w.writeUtf('', 20); // serverId
    w.writeByteArray(List<int>.generate(64, (i) => i)); // publicKey
    w.writeByteArray([1, 2, 3, 4]); // challenge
    w.writeBool(true); // shouldAuthenticate
  });
}

void _writeGameLogin(ByteWriter w) {
  w.writeInt(42);
  w.writeBool(false);
  w.writeVarInt(1);
  w.writeUtf('minecraft:overworld');
  w.writeVarInt(20);
  w.writeVarInt(12);
  w.writeVarInt(10);
  w.writeBool(false);
  w.writeBool(true);
  w.writeBool(false);
  w.writeUtf('minecraft:overworld');
  w.writeUtf('minecraft:overworld');
  w.writeLong(12345);
  w.writeUnsignedByte(1);
  w.writeUnsignedByte(0xFF);
  w.writeBool(false);
  w.writeBool(false);
  w.writeBool(false);
  w.writeVarInt(0);
  w.writeVarInt(63);
  w.writeBool(false);
  w.writeBool(false);
}

/// 网络 NBT：{text: [text]}（判据 ClientboundDisconnectPacket 的 Component 形态）。
Uint8List nbtText(String text) {
  final b = BytesBuilder();
  b.addByte(10);
  b.addByte(8); // TAG_String
  final name = 'text'.codeUnits;
  final len = ByteData(2)..setUint16(0, name.length, Endian.big);
  b.add(len.buffer.asUint8List());
  b.add(Uint8List.fromList(name));
  final value = text.codeUnits;
  final vlen = ByteData(2)..setUint16(0, value.length, Endian.big);
  b.add(vlen.buffer.asUint8List());
  b.add(Uint8List.fromList(value));
  b.addByte(0); // end
  return b.takeBytes();
}

final class ServerFrame {
  ServerFrame(this.id, this.body);

  final int id;
  final Uint8List body;
}
