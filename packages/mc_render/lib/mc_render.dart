/// mc_render —— 原版渲染数据半边的翻译落点。
///
/// 模型烘焙与区块编译：区块（mc_session 调色板 stateId）→ 分区网格
/// （顶点/UV/索引纯数据，fscraft mesher 移植版：引擎空间手性、反向绕序、
/// 面朝向明暗）。GPU 上传由 app 壳的 flutter_scene 适配层完成。
/// 首版简化：整块立方体 + 面剔除，无 AO/平滑光照（见 mesher.dart 文件头）。
library;

export 'src/block_geometry_mesh.dart';
export 'src/block_semantics_v262.dart';
export 'src/chunk_mesh_data.dart';
export 'src/mesh_semantics.dart';
export 'src/mesher.dart';
export 'src/state_identity_26_2.dart';
export 'src/uv_rect.dart';
