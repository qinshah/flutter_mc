import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'byte_reader.dart';
import 'byte_writer.dart';
import 'frame_codec.dart';
import 'framing.dart';
import 'packet_registry.dart';
import 'protocol_phase.dart';

/// 原始回应钩子 —— 对某些"服务器下发、客户端必须原样回应载荷"的包
/// （keep-alive：回应同载荷；判据见 change notes 1.2 清单），由版本包声明
/// "(阶段, 入站包 id) → 回应包 id"，本连接层负责执行（载荷原样回传）。
///
/// 回应包 id 由钩子给出，因为 clientbound 与 serverbound 的 keep-alive id **不同**
/// （26.2 play：44 → 28；config：4 → 4）。返回 null = 不回应。
typedef RawEchoHook = int? Function(ProtocolPhase phase, int packetId, Uint8List body);

/// 一条指向服务器的连接：Socket → 分帧 → 解压 → 包登记表 → 事件流。
///
/// 本类是 mc_wire 的传输核心：不认识具体包语义；协议阶段由调用方
/// （mc_session）驱动 [phaseMachine] 并据此切换登记表与压缩配置。
class WireConnection {
  WireConnection._(this._socket, this.registry);

  final Socket _socket;
  final PacketRegistry registry;
  final FrameDecoder _frameDecoder = FrameDecoder();
  final FrameCodec frameCodec = FrameCodec();
  final ProtocolPhaseMachine phaseMachine = ProtocolPhaseMachine();
  final _inbound = StreamController<InboundPacket<Object?>>.broadcast();
  final _done = Completer<void>();

  /// 服务器主动要求回应的 raw 回应钩子（见 [RawEchoHook]）。
  RawEchoHook? rawEcho;

  /// **同步**入站回调 —— 在解帧循环内联调用（原版 netty 管线语义：状态机/压缩
  /// 等会话状态变更必须先于同批后续帧生效）。与 [inbound] 流并存；
  /// 状态敏感消费方（mc_session）MUST 用本回调，流只供旁路观察。
  void Function(InboundPacket<Object?> packet)? onPacketSync;

  Stream<InboundPacket<Object?>> get inbound => _inbound.stream;

  Future<void> get done => _done.future;

  static Future<WireConnection> connect(
    String host,
    int port,
    PacketRegistry registry, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final socket = await Socket.connect(host, port, timeout: timeout);
    final conn = WireConnection._(socket, registry);
    socket.listen(
      conn._onData,
      onError: (Object e) => conn._close(e),
      onDone: () => conn._close(null),
    );
    return conn;
  }

  void _onData(Uint8List data) {
    try {
      final frames = _frameDecoder.push(data);
      for (final frame in frames) {
        final packetBytes = frameCodec.decode(frame);
        final r = _PacketHeader.read(packetBytes);
        if (rawEcho != null) {
          final responseId = rawEcho!(phaseMachine.phase, r.packetId, r.body);
          if (responseId != null) {
            sendRaw(phaseMachine.phase, responseId, r.body);
            continue;
          }
        }
        final InboundPacket<Object?> packet;
        try {
          packet = registry.decodeInbound(phaseMachine.phase, r.packetId, r.body);
        } on Object catch (e) {
          // 带上阶段与包 id 的现场信息（验收排查的关键证据）
          if (Platform.environment['MC_DUMP_FAIL'] == '1') {
            // 调试逃生门：dump 解码失败的包体供离线剖析（验收期临时手段）
            // ignore: avoid_print
            print('[wire] dump body=${r.body.length}B -> /tmp/fail_dump.bin');
            File('/tmp/fail_dump.bin').writeAsBytesSync(r.body);
          }
          throw FormatException(
            '解码失败 ${phaseMachine.phase.name}/0x${r.packetId.toRadixString(16)} '
            'body=${r.body.length}B: $e',
          );
        }
        onPacketSync?.call(packet);
        _inbound.add(packet);
      }
    } on Object catch (e) {
      _close(e);
    }
  }

  /// 设置压缩阈值（登录阶段收到 SetCompression 时调用；0 = 关闭）。
  void setCompression(int threshold) {
    frameCodec.threshold = threshold;
  }

  /// 发送原始包：`varint 包 id + body`（调用方按版本包编好 body；
  /// 类型化 send 由 mc_protocol_v26_2 在登记表之上提供）。
  void sendRaw(ProtocolPhase phase, int packetId, List<int> body) {
    final w = ByteWriter();
    w.writeVarInt(packetId);
    w.writeBytes(body);
    _socket.add(encodeFrame(frameCodec.encode(w.takeBytes())));
  }

  /// 发送**已含 id 前缀**的整包（登记表 encodeOutbound 的产物直通）。
  void sendPacketBytes(ProtocolPhase phase, List<int> fullPacket) {
    _socket.add(encodeFrame(frameCodec.encode(fullPacket)));
  }

  bool _closed = false;

  void _close(Object? error) {
    if (_closed) return;
    _closed = true;
    try {
      _socket.destroy();
    } finally {
      if (error != null) {
        _done.completeError(error);
      } else {
        _done.complete();
      }
      _inbound.close();
    }
  }

  Future<void> close() async {
    if (!_closed) {
      try {
        await _socket.flush();
      } on Object {
        // flush 对已毁 socket 抛错属正常路径，吞掉后仍走关闭收尾
      }
      _close(null);
    }
    try {
      await _done.future;
    } on Object {
      // 连接异常时 done 以错误收口，错误已由监听方（done.then 的 onError）
      // 消费；close() 的调用方不该再被同一个错误二次炸到（曾以未处理
      // 异步错误形式逃出会话、被测试运行器记到别的用例头上）。
    }
  }
}

class _PacketHeader {
  _PacketHeader(this.packetId, this.body);

  final int packetId;
  final Uint8List body;

  static _PacketHeader read(Uint8List packetBytes) {
    final r = ByteReader(packetBytes);
    final id = r.readVarInt();
    return _PacketHeader(id, r.readRemaining());
  }
}
