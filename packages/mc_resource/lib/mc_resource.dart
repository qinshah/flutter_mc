/// mc_resource —— 资源包读取抽象（骨架）。
///
/// 目标：PackResources 式、来源可插拔的资源读取（本机目录 / zip /
/// 未来应用内下载 jar），覆盖方块贴图、模型 JSON、字体、语言文件等。
/// 纯 Dart；[VanillaPack] 提供版本键读取，[BlockModels] 解析方块模型贴图，
/// [BlockAtlas] 加载构建期图集清单（贴图路径 → UV 矩形）。
library;

export 'src/atlas_uv.dart';
export 'src/block_geometry.dart';
export 'src/block_math.dart';
export 'src/block_model_rotation.dart';
export 'src/block_models.dart';
export 'src/direction.dart';
export 'src/face_bakery.dart';
export 'src/face_info.dart';
export 'src/octahedral_group.dart';
export 'src/symmetric_group3.dart';
export 'src/vanilla_pack.dart';
