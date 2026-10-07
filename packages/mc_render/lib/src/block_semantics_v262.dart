import 'state_identity_26_2.dart';
import 'mesh_semantics.dart';

/// 26.2 的网格语义实现：stateId → 身份串（官方 data generator 生成的
/// `state_identity_26_2.dart`，32366 个 state 与区块调色板同一注册表）
/// → 按方块名启发式分类。
///
/// ## 判据可得性（spec「渲染判据缺失时须记录来源」）
///
/// 原版把"方块 → 渲染层"的完整注册表放在 **`BlockRenderLayer`**，该类**已编译进
/// 客户端渲染库**，`mc-sources` 中**不存在**（2026-10-07 全树 grep 零命中）。
/// 因此本实现**无法**照抄该注册表。
///
/// 替代判据（均可追到来源）：
/// - **渲染层判据入口**照抄 `ChunkSectionLayer.byTransparency`（源码树内**可抄**）：
///   `t.hasTranslucent ? TRANSLUCENT : t.hasTransparent ? CUTOUT : SOLID`。
/// - **十字面片**由 [crossBlocks] 提供——构建期从 jar 内 88 个"parent 指向
///   cross 系模板"的模型推导（见 `mc_resource.BlockModels.crossTemplateParents`），
///   而非手写方块名名单。
/// - 仍保留少量名字启发式作为**兜底**（液体名、叶/玻璃名），已在各方法注释标明。
class BlockSemanticsV262 implements MeshSemantics {
  const BlockSemanticsV262({
    this.crossBlocks = const {},
    this.flatGroundCover = const {},
  });

  /// **判据驱动**的十字面片方块名集合（构建期由模型 parent 链推导后注入）。
  ///
  /// 取代原版的 40 项手写 `_crossNames`——那类名单必然漏（`kelp`/`seagrass`
  /// 就曾在其中缺席，导致渲染成青蓝"冰柱"）。
  final Set<String> crossBlocks;

  /// **判据驱动**的贴地薄片方块名（构建期从模型的贴地 `elements` 推导后注入）。
  final Set<String> flatGroundCover;

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

  /// 判据驱动优先（[BlockSemanticsV262.crossBlocks]，来自模型 parent 链），
  /// 兜底才用名字启发式——兜底只覆盖"模型缺失"的场景，不是主判据。
  bool _isCrossName(String name) =>
      crossBlocks.contains(name) ||
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
  bool _isFlatGroundCover(String name) =>
      // 判据驱动优先（模型的贴地薄片 `elements`），兜底才是手写名单。
      flatGroundCover.contains(name) ||
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

  /// 身份串 → 方块名（供构建期扫描用；判据同[blockNameOf]）。
  static String blockNameOfStateIdentity(String identity) =>
      blockNameOfIdentity(identity);

  /// 身份串 → 方块名（去命名空间与属性）。
  static String blockNameOfIdentity(String identity) {
    var name = identity;
    final colon = name.indexOf(':');
    if (colon >= 0) name = name.substring(colon + 1);
    final bracket = name.indexOf('[');
    if (bracket >= 0) name = name.substring(0, bracket);
    return name;
  }

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
