/// mc_wire —— MC 协议传输核心。
///
/// 纯 Dart、无 Flutter 依赖、无 GPU 类型、isolate 可跑（"无 GPU 模块纪律"的
/// 传输层成员）。本包不认识任何具体包类型与版本号：VarInt/分帧/zlib/协议阶段
/// 状态机骨架/包登记表接口在此；26.2 的包类型与编解码在 `mc_protocol_v26_2`，
/// 会话编排在 `mc_session`。
library;

export 'src/byte_reader.dart';
export 'src/byte_writer.dart';
export 'src/connection.dart';
export 'src/frame_codec.dart';
export 'src/framing.dart';
export 'src/packet_registry.dart';
export 'src/protocol_phase.dart';
