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
/// - 楼梯（StairBlock.java:40-48）：OUTER = 底半 + facing∩left 象限；
///   STRAIGHT = 底半 + facing 半边；INNER = 底半 + facing/left/right 三半边；
///   half=top 整体 y 镜像
/// - 雪片 column(16,0,layers*2/16)（SnowLayerBlock.java:31）；地毯 1/16
///   （CarpetBlock.java:17）；耕地/土径 15/16（FarmLandBlock.java:36 /
///   DirtPathBlock.java:23）；灵魂沙 14/16（SoulSandBlock.java:15）
///
/// **债**：未覆盖族兜底整块（原版是每方块白名单）；wall 的 tall/short 臂用
/// 栅栏参数近似（1.5 高语义保持）；fence_gate 的 in_wall 高度未建模。
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

  /// `FenceGateBlock`：关闭 = 横贯门条（1.5 高）；开启 = 两端门柱。
  /// 债：in_wall（墙内 1.0 高）未建模。
  static VoxelShape _fenceGate(Map<String, String> props) {
    final facing = props['facing'] ?? 'north';
    final alongZ = facing == 'north' || facing == 'south';
    if (props['open'] == 'true') {
      return alongZ
          ? VoxelShape.or(
              VoxelShape.box(0, 0, 6, 2, 24, 10), VoxelShape.box(14, 0, 6, 16, 24, 10))
          : VoxelShape.or(
              VoxelShape.box(6, 0, 0, 10, 24, 2), VoxelShape.box(6, 0, 14, 10, 24, 16));
    }
    return alongZ
        ? VoxelShape.box(0, 0, 6, 16, 24, 10)
        : VoxelShape.box(6, 0, 0, 10, 24, 16);
  }

  /// `StairBlock`（判据 J6 + StairBlock.java:76-89 的分派：
  /// STRAIGHT/OUTER_LEFT/INNER_RIGHT → map[facing]；INNER_LEFT →
  /// map[getCounterClockWise(facing)]；OUTER_RIGHT → map[getClockWise(facing)]；
  /// map 基准（NORTH）= 底半 + facing∩left 象限（OUTER）/ facing 半边（STRAIGHT）
  /// / facing+left 半边（INNER）；half=top 整体 y 镜像）。
  static VoxelShape _stair(Map<String, String> props) {
    final facing = props['facing'] ?? 'north';
    final isTop = props['half'] == 'top';
    final shape = props['shape'] ?? 'straight';
    final left = _leftOf(facing);
    final right = _rightOf(facing);

    // 上层半边集合（inner_left 缺 right 半边、inner_right 缺 left 半边）与
    // outer 的单象限（facing ∩ side）。
    final halfGrids = <String>[];
    BlockBox? quadrant;
    switch (shape) {
      case 'outer_left':
        quadrant = _quadrant(facing, left);
      case 'outer_right':
        quadrant = _quadrant(facing, right);
      case 'inner_left':
        halfGrids.addAll([facing, left]);
      case 'inner_right':
        halfGrids.addAll([facing, right]);
      default:
        halfGrids.add(facing);
    }

    // 下半块 base（bottom: y0..0.5 / top: y0.5..1）+ 上层梯级（y 镜像）。
    final boxes = <BlockBox>[];
    final (baseMinY, baseMaxY) = isTop ? (0.5, 1.0) : (0.0, 0.5);
    boxes.add(BlockBox(0, baseMinY, 0, 1, baseMaxY, 1));
    final (stepMinY, stepMaxY) = isTop ? (0.0, 0.5) : (0.5, 1.0);

    for (final dir in halfGrids) {
      boxes.add(_halfGridBox(dir, stepMinY, stepMaxY));
    }
    if (quadrant != null) {
      boxes.add(BlockBox(quadrant.minX, stepMinY, quadrant.minZ, quadrant.maxX, stepMaxY, quadrant.maxZ));
    }
    return VoxelShape(boxes);
  }

  /// 沿轴半格（y 用给定的梯级范围）。
  static BlockBox _halfGridBox(String dir, double minY, double maxY) => switch (dir) {
        'north' => BlockBox(0, minY, 0, 1, maxY, 0.5),
        'south' => BlockBox(0, minY, 0.5, 1, maxY, 1),
        'west' => BlockBox(0, minY, 0, 0.5, maxY, 1),
        _ => BlockBox(0.5, minY, 0, 1, maxY, 1),
      };

  /// 两个方向半格的交象限：E/W 成员给 x 半边、N/S 成员给 z 半边。
  static BlockBox _quadrant(String facing, String side) {
    final facingIsX = facing == 'east' || facing == 'west';
    final westDir = facingIsX ? facing : side;
    final northDir = facingIsX ? side : facing;
    final (x0, x1) = westDir == 'west' ? (0.0, 0.5) : (0.5, 1.0);
    final (z0, z1) = northDir == 'north' ? (0.0, 0.5) : (0.5, 1.0);
    return BlockBox(x0, 0, z0, x1, 1, z1);
  }

  /// 脚手架（原版碰撞随 bottom/support 变化，首切片：整格半高柱——债）。
  static VoxelShape _scaffolding(Map<String, String> props) {
    return VoxelShape.full();
  }

  static String _opposite(String dir) => switch (dir) {
        'north' => 'south',
        'south' => 'north',
        'west' => 'east',
        _ => 'west',
      };

  /// 面朝 [facing] 时的左侧（facing=north ⇒ 左 = west）。
  static String _leftOf(String facing) => switch (facing) {
        'north' => 'west',
        'south' => 'east',
        'west' => 'south',
        _ => 'north',
      };

  static String _rightOf(String facing) => _opposite(_leftOf(facing));

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
