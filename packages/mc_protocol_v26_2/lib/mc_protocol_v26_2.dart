/// mc_protocol_v26_2 —— MC Java 26.2 协议的包类型与编解码。
///
/// 数值包 id 由参考源码 `*Protocols.java` 的注册顺序推出（见 `protocol_ids.dart`）；
/// 字段布局逐包注明判据类名（宪法五）。纯 Dart，依赖 mc_wire。
library;

export 'src/block_pos.dart';
export 'src/jsonrpc_client.dart';
export 'src/management_methods.dart';
export 'src/packets.dart';
export 'src/protocol_ids.dart';
export 'src/registry.dart';
