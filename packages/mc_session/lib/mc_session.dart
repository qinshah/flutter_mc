/// mc_session —— 传输无关的联机会话编排与世界状态摄入。
///
/// 纯 Dart、无 Flutter 依赖、isolate 可跑（design D3：会话整体跑在 worker isolate）。
/// 依赖 mc_wire（传输核心）与 mc_protocol_v26_2（26.2 编解码）；重构时本包是
/// "会活过重构"的主体——jar 桥落地时换掉版本包即可。
library;

export 'src/chunk_batch_size_calculator.dart';
export 'src/client_chunk_cache.dart';
export 'src/palette.dart';
export 'src/remote_chunk.dart';
export 'src/remote_session.dart';
export 'src/server_address.dart';
export 'src/server_list.dart';
export 'src/session_assembly.dart';
export 'src/session_isolate.dart';
export 'src/status_probe.dart';

// 事件流公开面里的版本包类型：JoinedGame.login 的类型是 26.2 包的 GameLogin，
// 调用方（lib/）只经本包接触它（隔离红线）——再导出而不是让调用方 import 版本包。
export 'package:mc_protocol_v26_2/mc_protocol_v26_2.dart' show GameLogin, PlayerAbilitiesIn;
