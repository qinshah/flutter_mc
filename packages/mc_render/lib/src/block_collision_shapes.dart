import 'voxel_shape.dart';

/// 方块碰撞形状库：26.2 状态身份串（`minecraft:name[k=v,...]`，见
/// `state_identity_26_2.dart`）→ [VoxelShape]。
///
/// 判据（mc-sources/minecraft-26.2 Block 类常量，逐项见
/// `openspec/changes/block-collision-shapes/design.md` J1-J9）：
/// - 栅栏族 `CrossCollisionBlock`：post = column(0.25, 0, collisionHeight)，
///   四向臂厚 0.25 居中（CrossCollisionBlock.java:30-46 + Block.java:177-203；
///   FenceBlock.java:37 collisionHeight=1.5，玻璃板/铁栏杆族 1.0）
/// - 半砖 column(16,0,8)/(16,8,16)（SlabBlock.java:35-36）
/// - 楼梯（StairBlock.java:40-48）：NORTH 基准 OUTER/STRAIGHT/INNER 经
///   `Shapes.rotate`（BLOCK_ROT_Y_90/180/270，见 `voxel_shape.dart`）旋出四向
///   map，half=top 复合 INVERT_Y；getShape 分派 :76-89
/// - 雪片 column(16,0,layers*2/16)（SnowLayerBlock.java:31）；地毯 1/16
///   （CarpetBlock.java:17）；耕地/土径 15/16（FarmLandBlock.java:36 /
///   DirtPathBlock.java:23）；灵魂沙 14/16（SoulSandBlock.java:15）
///
/// **债**（progress.md 第 13 类）：未覆盖族兜底整块（原版是每方块白名单）；
/// wall 的碰撞臂用栅栏参数近似；脚手架整块化（原版随 bottom/support 变化）。
class BlockCollisionShapes {
  BlockCollisionShapes._();

  static final Map<String, VoxelShape> _cache = {};

  /// 身份串（如 `minecraft:oak_stairs[facing=east,half=bottom,shape=straight]`）
  /// → 碰撞形状。
  static VoxelShape shapeFor(String identity) {
    final cached = _cache[identity];
    if (cached != null) return cached;
    final shape = _build(identity);
    _cache[identity] = shape;
    return shape;
  }

  static VoxelShape _build(String identity) {
    final name = _nameOf(identity);
    final props = _propsOf(identity);

    switch (name) {
      case 'minecraft:air':
      case 'minecraft:water':
      case 'minecraft:lava':
      case 'minecraft:bubble_column':
      case 'minecraft:fire':
      case 'minecraft:soul_fire':
      case 'minecraft:redstone_wire':
      case 'minecraft:sugar_cane':
      case 'minecraft:vine':
      case 'minecraft:glow_lichen':
      case 'minecraft:dead_bush':
      case 'minecraft:short_grass':
      case 'minecraft:fern':
      case 'minecraft:large_fern':
      case 'minecraft:tall_grass':
      case 'minecraft:sweet_berry_bush':
      case 'minecraft:nether_wart':
      case 'minecraft:wheat':
      case 'minecraft:carrots':
      case 'minecraft:potatoes':
      case 'minecraft:beetroots':
      case 'minecraft:melon_stem':
      case 'minecraft:pumpkin_stem':
      case 'minecraft:attached_melon_stem':
      case 'minecraft:attached_pumpkin_stem':
      case 'minecraft:dandelion':
      case 'minecraft:poppy':
      case 'minecraft:blue_orchid':
      case 'minecraft:allium':
      case 'minecraft:azure_bluet':
      case 'minecraft:red_tulip':
      case 'minecraft:orange_tulip':
      case 'minecraft:white_tulip':
      case 'minecraft:pink_tulip':
      case 'minecraft:oxeye_daisy':
      case 'minecraft:cornflower':
      case 'minecraft:lily_of_the_valley':
      case 'minecraft:wither_rose':
      case 'minecraft:torchflower':
      case 'minecraft:sunflower':
      case 'minecraft:lilac':
      case 'minecraft:rose_bush':
      case 'minecraft:peony':
      case 'minecraft:oak_sapling':
      case 'minecraft:spruce_sapling':
      case 'minecraft:birch_sapling':
      case 'minecraft:jungle_sapling':
      case 'minecraft:acacia_sapling':
      case 'minecraft:cherry_sapling':
      case 'minecraft:dark_oak_sapling':
      case 'minecraft:pale_oak_sapling':
      case 'minecraft:rail':
      case 'minecraft:powered_rail':
      case 'minecraft:detector_rail':
      case 'minecraft:activator_rail':
      case 'minecraft:torch':
      case 'minecraft:wall_torch':
      case 'minecraft:soul_torch':
      case 'minecraft:soul_wall_torch':
      case 'minecraft:redstone_torch':
      case 'minecraft:redstone_wall_torch':
      case 'minecraft:lever':
      case 'minecraft:tripwire':
      case 'minecraft:tripwire_hook':
      case 'minecraft:structure_void':
        return VoxelShape([]);
      case 'minecraft:snow':
        final layers = int.tryParse(props['layers'] ?? '1') ?? 1;
        return VoxelShape.column(16, 0, layers * 2);
      case 'minecraft:white_carpet':
      case 'minecraft:orange_carpet':
      case 'minecraft:magenta_carpet':
      case 'minecraft:light_blue_carpet':
      case 'minecraft:yellow_carpet':
      case 'minecraft:lime_carpet':
      case 'minecraft:pink_carpet':
      case 'minecraft:gray_carpet':
      case 'minecraft:light_gray_carpet':
      case 'minecraft:cyan_carpet':
      case 'minecraft:purple_carpet':
      case 'minecraft:blue_carpet':
      case 'minecraft:brown_carpet':
      case 'minecraft:green_carpet':
      case 'minecraft:red_carpet':
      case 'minecraft:black_carpet':
      case 'minecraft:moss_carpet':
        return VoxelShape.column(16, 0, 1);
      case 'minecraft:farmland':
      case 'minecraft:dirt_path':
        return VoxelShape.column(16, 0, 15);
      case 'minecraft:soul_sand':
        return VoxelShape.column(16, 0, 14);
      case 'minecraft:scaffolding':
        return _scaffolding(props);
      // —— 门（DoorBlock.java:55 SHAPES = rotateHorizontal(boxZ(16, 13, 16))，
      //     :85-91 doorDirection = open ? hinge 旋向 : facing）——
      case 'minecraft:oak_door':
      case 'minecraft:spruce_door':
      case 'minecraft:birch_door':
      case 'minecraft:jungle_door':
      case 'minecraft:acacia_door':
      case 'minecraft:dark_oak_door':
      case 'minecraft:mangrove_door':
      case 'minecraft:cherry_door':
      case 'minecraft:bamboo_door':
      case 'minecraft:crimson_door':
      case 'minecraft:warped_door':
      case 'minecraft:iron_door':
      case 'minecraft:copper_door':
      case 'minecraft:exposed_copper_door':
      case 'minecraft:weathered_copper_door':
      case 'minecraft:oxidized_copper_door':
        return _door(props);
      // —— 活板门（TrapDoorBlock.java:51 SHAPES = rotateAll(boxZ(16, 13, 16))，
      //     :78 closed → half(top=DOWN 面板/ bottom=UP 面板)，open → facing 竖板）——
      case 'minecraft:oak_trapdoor':
      case 'minecraft:spruce_trapdoor':
      case 'minecraft:birch_trapdoor':
      case 'minecraft:jungle_trapdoor':
      case 'minecraft:acacia_trapdoor':
      case 'minecraft:dark_oak_trapdoor':
      case 'minecraft:mangrove_trapdoor':
      case 'minecraft:cherry_trapdoor':
      case 'minecraft:bamboo_trapdoor':
      case 'minecraft:crimson_trapdoor':
      case 'minecraft:warped_trapdoor':
      case 'minecraft:iron_trapdoor':
      case 'minecraft:copper_trapdoor':
      case 'minecraft:exposed_copper_trapdoor':
      case 'minecraft:weathered_copper_trapdoor':
      case 'minecraft:oxidized_copper_trapdoor':
        return _trapdoor(props);
    }

    // —— 半砖（*_slab，type=top/bottom/double；double 兜底 full）——
    if (name.endsWith('_slab') || name == 'minecraft:smooth_stone_slab') {
      return switch (props['type']) {
        'top' => VoxelShape.column(16, 8, 16),
        'double' => VoxelShape.full(),
        _ => VoxelShape.column(16, 0, 8),
      };
    }

    // —— 楼梯（*_stairs）——
    if (name.endsWith('_stairs')) {
      return _stair(props);
    }

    // —— 栅栏/玻璃板/铁栏杆族（连接属性驱动）——
    final double? collisionHeight = switch (name) {
      _ when name.endsWith('_fence') => 1.5,
      _ when name.endsWith('_pane') || name == 'minecraft:iron_bars' => 1.0,
      _ => null,
    };
    if (collisionHeight != null) {
      return _crossCollision(props, collisionHeight);
    }
    if (name.endsWith('_fence_gate')) {
      return _fenceGate(props);
    }
    if (name.endsWith('_wall') && name != 'minecraft:wall') {
      // 债：WallBlock 的 tall/short 臂简化为栅栏参数（1.5 高语义保持）。
      return _crossCollision(props, 1.5);
    }
    if (name == 'minecraft:wall') {
      return _crossCollision(props, 1.5);
    }

    // 兜底：整块（债，progress.md 已登记）。
    return VoxelShape.full();
  }

  /// `DoorBlock.getShape`（DoorBlock.java:85-91）。
  ///
  /// 门板 = 3/16 厚、贴 [dir] 缘的整块高薄板（`boxZ(16,13,16)` 经
  /// `rotateHorizontal`：NORTH→z∈[0,3]…EAST→x∈[13,16]，DoorBlock.java:55）。
  /// 关：`doorDirection = facing`；开：hinge=LEFT → facing 顺时针，
  /// hinge=RIGHT → 逆时针（:87-89）。`half`（upper/lower）不影响本格形状。
  static VoxelShape _door(Map<String, String> props) {
    final facing = props['facing'] ?? 'north';
    final dir = props['open'] == 'true'
        ? (props['hinge'] == 'right' ? _ccw(facing) : _cw(facing))
        : facing;
    return _edgePanel(dir);
  }

  /// `TrapDoorBlock.getShape`（TrapDoorBlock.java:77-79）。
  ///
  /// 关：half=bottom → 底部水平板 y∈[0,3]；half=top → 顶部 y∈[13,16]。
  /// 开：竖板贴 facing 缘（与关门同构，`SHAPES.get(FACING)`）。
  static VoxelShape _trapdoor(Map<String, String> props) {
    if (props['open'] == 'true') {
      return _edgePanel(props['facing'] ?? 'north');
    }
    final top = props['half'] == 'top';
    return VoxelShape([
      BlockBox(0, top ? 13 / 16 : 0, 0, 1, top ? 1 : 3 / 16, 1),
    ]);
  }

  /// 贴 [dir] 缘的 3/16 厚薄板（`boxZ(16, 13, 16)` 各旋向；门/开态活板门共用）。
  static VoxelShape _edgePanel(String dir) {
    const t = 3 / 16;
    return switch (dir) {
      'north' => VoxelShape([const BlockBox(0, 0, 0, 1, 1, t)]),
      'south' => VoxelShape([const BlockBox(0, 0, 1 - t, 1, 1, 1)]),
      'east' => VoxelShape([const BlockBox(1 - t, 0, 0, 1, 1, 1)]),
      _ => VoxelShape([const BlockBox(0, 0, 0, t, 1, 1)]), // west
    };
  }

  /// `Direction.clockWise`（俯视顺时针：N→E→S→W）。
  static String _cw(String d) => switch (d) {
        'north' => 'east',
        'east' => 'south',
        'south' => 'west',
        _ => 'north',
      };

  /// `Direction.counterClockWise`。
  static String _ccw(String d) => switch (d) {
        'north' => 'west',
        'west' => 'south',
        'south' => 'east',
        _ => 'north',
      };

  /// `BlockBehaviourProperties.friction`（Blocks.java；判据行号）：
  /// ICE/PACKED_ICE/FROSTED_ICE 0.98（:1886/:2929/:3601）、BLUE_ICE 0.989（:4077）、
  /// SLIME_BLOCK 0.8（:2838）、默认 0.6。
  /// **债**：灵魂沙/蜂蜜的减速是独立属性修饰符（非 friction），未实现。
  static double frictionFor(String identity) {
    final name = _nameOf(identity);
    return switch (name) {
      'minecraft:blue_ice' => 0.989,
      'minecraft:ice' || 'minecraft:packed_ice' || 'minecraft:frosted_ice' => 0.98,
      'minecraft:slime_block' => 0.8,
      _ => 0.6,
    };
  }

  /// `CrossCollisionBlock.makeShapes`（判据 J1-J4）。
  static VoxelShape _crossCollision(Map<String, String> props, double height) {
    var shape = VoxelShape.column(4, 0, height * 16); // post：4px 居中
    bool on(String k) => props[k] == 'true';
    if (on('north')) {
      shape = VoxelShape.or(shape, VoxelShape.box(6, 0, 0, 10, height * 16, 8));
    }
    if (on('south')) {
      shape = VoxelShape.or(shape, VoxelShape.box(6, 0, 8, 10, height * 16, 16));
    }
    if (on('west')) {
      shape = VoxelShape.or(shape, VoxelShape.box(0, 0, 6, 8, height * 16, 10));
    }
    if (on('east')) {
      shape = VoxelShape.or(shape, VoxelShape.box(8, 0, 6, 16, height * 16, 10));
    }
    return shape;
  }

  /// `FenceGateBlock.getCollisionShape`（FenceGateBlock.java:105-108）：
  /// 开启 → 空；关闭 → `SHAPE_COLLISION`（:51 `column(16, 4, 0, 24)`：
  /// 全宽、4/16 厚居中、1.5 高）。`in_wall` 只改视觉 shape（:47-50），不影响碰撞。
  static VoxelShape _fenceGate(Map<String, String> props) {
    if (props['open'] == 'true') return VoxelShape([]);
    final facing = props['facing'] ?? 'north';
    final alongZ = facing == 'north' || facing == 'south';
    return alongZ
        ? VoxelShape.box(0, 0, 6, 16, 24, 10)
        : VoxelShape.box(6, 0, 0, 10, 24, 16);
  }

  // —— 楼梯（StairBlock.java:40-48 的逐行对应：NORTH 基准形状经
  //     Shapes.rotate 旋出四向 map，top 变体复合 INVERT_Y）——

  /// `StairBlock.SHAPE_OUTER`（:40）：底半 + 西北象限。
  static final VoxelShape _stairOuter = VoxelShape.or(
    VoxelShape.column(16, 0, 8),
    VoxelShape.box(0, 8, 0, 8, 16, 8),
  );

  /// `StairBlock.SHAPE_STRAIGHT`（:41）：OUTER ∪ rotate(OUTER, BLOCK_ROT_Y_90)。
  static final VoxelShape _stairStraight = VoxelShape.or(_stairOuter, _stairOuter.rotateY90());

  /// `StairBlock.SHAPE_INNER`（:42）：STRAIGHT ∪ rotate(STRAIGHT, BLOCK_ROT_Y_90)。
  static final VoxelShape _stairInner = VoxelShape.or(_stairStraight, _stairStraight.rotateY90());

  /// `StairBlock.SHAPE_BOTTOM_*`（:43-45）= `Shapes.rotateHorizontal`
  /// （Shapes.java:390-403：N 基准、E = BLOCK_ROT_Y_90、S = BLOCK_ROT_Y_180、
  /// W = BLOCK_ROT_Y_270）。
  static final Map<String, VoxelShape> _stairBottomOuter = _rotateHorizontal(_stairOuter);
  static final Map<String, VoxelShape> _stairBottomStraight = _rotateHorizontal(_stairStraight);
  static final Map<String, VoxelShape> _stairBottomInner = _rotateHorizontal(_stairInner);

  /// `StairBlock.SHAPE_TOP_*`（:46-48）= rotateHorizontal(shape, INVERT_Y)。
  /// INVERT_Y 仅翻 y 轴，与 Y 旋转复合可交换 ⇒ 逐方向先旋转后 y 镜像精确等价。
  static final Map<String, VoxelShape> _stairTopOuter = {
    for (final e in _stairBottomOuter.entries) e.key: e.value.invertY(),
  };
  static final Map<String, VoxelShape> _stairTopStraight = {
    for (final e in _stairBottomStraight.entries) e.key: e.value.invertY(),
  };
  static final Map<String, VoxelShape> _stairTopInner = {
    for (final e in _stairBottomInner.entries) e.key: e.value.invertY(),
  };

  /// `StairBlock.getShape`（StairBlock.java:76-89）。
  static VoxelShape _stair(Map<String, String> props) {
    final facing = props['facing'] ?? 'north';
    final isBottom = props['half'] != 'top';
    final shape = props['shape'] ?? 'straight';

    // :79-83 的 map 选择（OUTER_LEFT 与 OUTER_RIGHT、INNER_LEFT 与
    // INNER_RIGHT 同 map，方向差在 key 上）。
    final (bottom, top) = switch (shape) {
      'outer_left' || 'outer_right' => (_stairBottomOuter, _stairTopOuter),
      'inner_left' || 'inner_right' => (_stairBottomInner, _stairTopInner),
      _ => (_stairBottomStraight, _stairTopStraight),
    };

    // :85-89 的 map key：STRAIGHT/OUTER_LEFT/INNER_RIGHT → facing；
    // INNER_LEFT → ccw；OUTER_RIGHT → cw。
    final key = switch (shape) {
      'inner_left' => _ccw(facing),
      'outer_right' => _cw(facing),
      _ => facing,
    };

    return (isBottom ? bottom : top)[key]!;
  }

  /// `Shapes.rotateHorizontal`（Shapes.java:390-403）。
  static Map<String, VoxelShape> _rotateHorizontal(VoxelShape north) => {
        'north': north,
        'east': north.rotateY90(),
        'south': north.rotateY180(),
        'west': north.rotateY270(),
      };

  /// 脚手架（原版碰撞随 bottom/support 变化，首切片：整格半高柱——债）。
  static VoxelShape _scaffolding(Map<String, String> props) {
    return VoxelShape.full();
  }

  static String _nameOf(String identity) {
    final bracket = identity.indexOf('[');
    return bracket < 0 ? identity : identity.substring(0, bracket);
  }

  static Map<String, String> _propsOf(String identity) {
    final bracket = identity.indexOf('[');
    if (bracket < 0) return const {};
    final body = identity.substring(bracket + 1, identity.lastIndexOf(']'));
    final out = <String, String>{};
    for (final pair in body.split(',')) {
      final eq = pair.indexOf('=');
      if (eq > 0) out[pair.substring(0, eq)] = pair.substring(eq + 1);
    }
    return out;
  }
}
