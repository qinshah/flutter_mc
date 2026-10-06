import 'state_identity_26_2.dart';
import 'mesh_semantics.dart';

/// 26.2 的网格语义实现：stateId → 身份串（官方 data generator 生成的
/// `state_identity_26_2.dart`，32366 个 state 与区块调色板同一注册表）
/// → 按方块名启发式分类。
///
/// **首版简化**（design D2）：渲染层/十字/遮挡分类是名字启发式
/// （液体→translucent，叶/玻璃→cutout，已知植物名单→cross，其余→opaque 并
/// 遮挡邻居）；未识别 state 按 opaque 处理。后续对齐原版
/// `BlockRenderLayer`/`BlockShapes` 注册表。
class BlockSemanticsV262 implements MeshSemantics {
  const BlockSemanticsV262();

  static const Set<String> _crossNames = {
    'short_grass', 'tall_grass', 'fern', 'large_fern', 'dead_bush',
    'dandelion', 'poppy', 'blue_orchid', 'allium', 'azure_bluet',
    'red_tulip', 'orange_tulip', 'white_tulip', 'pink_tulip',
    'oxeye_daisy', 'cornflower', 'lily_of_the_valley', 'wither_rose',
    'sunflower', 'lilac', 'rose_bush', 'peony', 'wheat', 'carrots',
    'potatoes', 'beetroots', 'sugar_cane', 'brown_mushroom',
    'red_mushroom', 'torch', 'soul_torch', 'redstone_torch',
    'oak_sapling', 'spruce_sapling', 'birch_sapling', 'jungle_sapling',
    'acacia_sapling', 'cherry_sapling', 'dark_oak_sapling', 'bamboo_sapling',
  };

  static bool _isCrossName(String name) =>
      _crossNames.contains(name) ||
      name.endsWith('_sapling') ||
      name.endsWith('_flower') ||
      name.contains('torch_flower');

  static bool _isTranslucentName(String name) =>
      name == 'water' || name == 'lava' || name.startsWith('flowing_');

  static bool _isCutoutName(String name) =>
      name.contains('leaves') || name == 'glass' || name.endsWith('_glass');

  /// 薄皮/贴地方块（26.2 新增一批）：leaf_litter、petals、carpet 等。
  /// 原版是贴地薄片；首版按十字面片渲染（已知简化：形态应为贴地薄片），
  /// 关键是**不遮挡邻居、不按实心立方体画**——否则会渲染成大色块实心体
  /// 并把相邻方块面错误剔除（2026-10-07 实测：leaf_litter 红色大板+穿帮）。
  static bool _isFlatGroundCover(String name) =>
      name == 'leaf_litter' ||
      name == 'pink_petals' ||
      name == 'wildflowers' ||
      name == 'bush' ||
      name == 'firefly_bush' ||
      name == 'short_dry_grass' ||
      name == 'tall_dry_grass' ||
      name.endsWith('_carpet') ||
      name.endsWith('_petals') ||
      name.endsWith('_bush');

  /// 身份串 → 方块名（去命名空间与属性）：`minecraft:grass_block[snowy=true]`
  /// → `grass_block`。
  static String blockNameOf(int stateId) {
    final identity = kBlockStateIdentity262[stateId];
    if (identity == null) return 'unknown';
    var name = identity;
    final colon = name.indexOf(':');
    if (colon >= 0) name = name.substring(colon + 1);
    final bracket = name.indexOf('[');
    if (bracket >= 0) name = name.substring(0, bracket);
    return name;
  }

  @override
  int layerIndexOf(int stateId) {
    final name = blockNameOf(stateId);
    if (_isTranslucentName(name)) return 2;
    if (_isCrossName(name) || _isCutoutName(name) || _isFlatGroundCover(name)) {
      return 1;
    }
    return 0;
  }

  @override
  bool isCross(int stateId) {
    final name = blockNameOf(stateId);
    return _isCrossName(name) || _isFlatGroundCover(name);
  }

  @override
  bool hidesNeighbors(int stateId) {
    if (stateId == 0) return false;
    final name = blockNameOf(stateId);
    return !_isTranslucentName(name) &&
        !_isCutoutName(name) &&
        !_isCrossName(name) &&
        !_isFlatGroundCover(name);
  }

  @override
  String nameOf(int stateId) => blockNameOf(stateId);

  /// 物理：是否可碰撞（非空气/液体/十字植物/薄皮；叶与玻璃可碰撞——照原版）。
  bool isCollidable(int stateId) {
    if (stateId == 0) return false;
    final name = blockNameOf(stateId);
    return !_isTranslucentName(name) &&
        !_isCrossName(name) &&
        !_isFlatGroundCover(name);
  }
}
