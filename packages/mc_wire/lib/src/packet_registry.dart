import 'dart:typed_data';

import 'byte_reader.dart';
import 'byte_writer.dart';
import 'protocol_phase.dart';

/// 包编解码器 —— 版本无关的抽象：把 `(phase, packetId)` 翻译为具体类型
/// 的活儿由版本包（如 `mc_protocol_v26_2`）以数据驱动登记表完成。
abstract interface class PacketCodec<T> {
  T decode(ByteReader r);

  void encode(ByteWriter w, T packet);
}

/// 服务器 → 客户端方向的已解码包。
class InboundPacket<T> {
  InboundPacket(this.phase, this.packetId, this.body, {this.value});

  final ProtocolPhase phase;

  /// 线上包 id（版本包登记表按它查 codec）。
  final int packetId;

  /// 解码后的业务值；未登记包为 null。
  final T? value;

  /// 原始包体（未登记包靠它"跳过+留档"）。
  final Uint8List body;
}

/// 客户端 → 服务器方向的待编码包。
///
/// 版本包定义具体包类型时，用它携带"包 id + 已编码好的包体"或交给
/// [PacketRegistry] 按类型编码。
class OutboundPacket {
  OutboundPacket(this.phase, this.packetId, List<int> body)
      : body = Uint8List.fromList(body);

  final ProtocolPhase phase;
  final int packetId;

  /// 已编码的包体（不含包 id 前缀）。
  final Uint8List body;
}

/// 未登记包的处置记录 —— 「未知包不致命」的承载（remote-play spec）。
class UnknownPacketStats {
  final Map<String, int> _counts = {};

  void record(ProtocolPhase phase, int packetId) {
    final key = '${phase.name}/0x${packetId.toRadixString(16)}';
    _counts[key] = (_counts[key] ?? 0) + 1;
  }

  /// `(阶段/id) → 次数`。
  Map<String, int> snapshot() => Map.unmodifiable(_counts);
}

/// 版本无关的包路由：登记表查得到 → 交给 codec 解码；查不到 → 跳过 + 计数。
class PacketRegistry {
  final UnknownPacketStats unknownStats = UnknownPacketStats();

  final Map<ProtocolPhase, Map<int, PacketCodec<Object?>>> _inbound = {};
  final Map<ProtocolPhase, Map<Object?, int>> _outboundIds = {};
  final Map<ProtocolPhase, Map<Object?, PacketCodec<Object?>>> _outboundCodecs = {};

  /// 登记一个 inbound 包（版本包在初始化时按 26.2 判据逐包登记）。
  void registerInbound(
    ProtocolPhase phase,
    int packetId,
    PacketCodec<Object?> codec,
  ) {
    _inbound.putIfAbsent(phase, () => {})[packetId] = codec;
  }

  /// 登记一个 outbound 包类型（[type] 通常是具体包类型的 runtimeType 或枚举值）。
  void registerOutbound(
    ProtocolPhase phase,
    int packetId,
    Object? type,
    PacketCodec<Object?> codec,
  ) {
    _outboundIds.putIfAbsent(phase, () => {})[type] = packetId;
    _outboundCodecs.putIfAbsent(phase, () => {})[type] = codec;
  }

  /// 按线上包 id 解 inbound；未登记返回 null（调用侧拿原始包体做跳过处理）。
  InboundPacket<Object?> decodeInbound(ProtocolPhase phase, int packetId, Uint8List body) {
    final codec = _inbound[phase]?[packetId];
    if (codec == null) {
      unknownStats.record(phase, packetId);
      return InboundPacket<Object?>(phase, packetId, body);
    }
    final r = ByteReader(body);
    return InboundPacket<Object?>(phase, packetId, body, value: codec.decode(r));
  }

  /// 把具体包类型编码成线上包；未登记抛错（写侧写不出未登记的包是编程错误）。
  Uint8List encodeOutbound(ProtocolPhase phase, Object? type, Object? packet) {
    final id = _outboundIds[phase]?[type];
    final codec = _outboundCodecs[phase]?[type];
    if (id == null || codec == null) {
      throw StateError('outbound 包未登记：${phase.name}/$type');
    }
    final w = ByteWriter();
    w.writeVarInt(id);
    codec.encode(w, packet);
    return w.takeBytes();
  }
}
