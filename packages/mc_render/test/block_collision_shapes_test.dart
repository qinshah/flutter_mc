import 'package:test/test.dart';
import 'package:mc_render/mc_render.dart';

/// 黄金值对照 mc-sources/minecraft-26.2 Block 类常量
/// （判据见 openspec/changes/block-collision-shapes/design.md J1-J9）。
double _maxY(VoxelShape s) {
  var m = 0.0;
  for (final b in s.boxes) {
    if (b.maxY > m) m = b.maxY;
  }
  return m;
}

void main() {
  test('整块与空形状', () {
    expect(BlockCollisionShapes.shapeFor('minecraft:stone').boxes, hasLength(1));
    expect(BlockCollisionShapes.shapeFor('minecraft:air').isEmpty, isTrue);
    expect(BlockCollisionShapes.shapeFor('minecraft:water[level=0]').isEmpty, isTrue);
    // 带属性的无碰撞方块同样识别。
    expect(BlockCollisionShapes.shapeFor('minecraft:oak_sapling[stage=1]').isEmpty, isTrue);
    // 未覆盖族兜底整块（翻译债）。
    expect(BlockCollisionShapes.shapeFor('minecraft:smithing_table').boxes, hasLength(1));
  });

  test('栅栏：碰撞高 1.5，连接驱动横臂（判据 FenceBlock.java:37）', () {
    final fence = BlockCollisionShapes.shapeFor(
        'minecraft:oak_fence[east=false,north=false,south=false,waterlogged=false,west=false]');
    expect(_maxY(fence), 1.5, reason: '无连接只有中心柱，高 1.5（跳不上）');
    expect(fence.boxes, hasLength(1)); // 仅中心柱 (0.375..0.625)²
    expect(fence.boxes.first.minX, closeTo(0.375, 1e-9));

    final connected = BlockCollisionShapes.shapeFor(
        'minecraft:oak_fence[east=true,north=true,south=false,waterlogged=false,west=false]');
    expect(connected.boxes, hasLength(3), reason: '柱 + 北臂 + 东臂');
    expect(_maxY(connected), 1.5);
  });

  test('玻璃板：同栅栏机制但高 1.0', () {
    final pane = BlockCollisionShapes.shapeFor(
        'minecraft:glass_pane[east=false,north=false,south=false,waterlogged=false,west=false]');
    expect(_maxY(pane), closeTo(1.0, 1e-9));
  });

  test('半砖：top/bottom/double（判据 SlabBlock.java:35-36）', () {
    final bottom = BlockCollisionShapes.shapeFor('minecraft:stone_slab[type=bottom,waterlogged=false]');
    expect(_maxY(bottom), closeTo(0.5, 1e-9));
    final top = BlockCollisionShapes.shapeFor('minecraft:stone_slab[type=top,waterlogged=false]');
    expect(_maxY(top), closeTo(1.0, 1e-9));
    final bottomMin = bottom.boxes.first.minY;
    expect(bottomMin, 0.0);
    final topMin = top.boxes.first.minY;
    expect(topMin, closeTo(0.5, 1e-9));
    final doubleSlab = BlockCollisionShapes.shapeFor('minecraft:stone_slab[type=double,waterlogged=false]');
    expect(_maxY(doubleSlab), 1.0);
  });

  test('楼梯：straight 底半 + facing 半边梯级（判据 StairBlock.java:40-48, :76-89）', () {
    final north = BlockCollisionShapes.shapeFor(
        'minecraft:oak_stairs[facing=north,half=bottom,shape=straight,waterlogged=false]');
    // 底半全格 + 北半上层 = 2 盒；最高 1.0。
    expect(_maxY(north), 1.0);
    expect(north.boxes, hasLength(2));
    // 北半上层盒 z ∈ [0, 0.5]。
    final step = north.boxes.last;
    expect(step.minY, closeTo(0.5, 1e-9));
    expect(step.minZ, 0.0);
    expect(step.maxZ, closeTo(0.5, 1e-9));

    // facing=east：梯级在东半（x 0.5..1）。
    final east = BlockCollisionShapes.shapeFor(
        'minecraft:oak_stairs[facing=east,half=bottom,shape=straight,waterlogged=false]');
    final eastStep = east.boxes.last;
    expect(eastStep.minX, closeTo(0.5, 1e-9));

    // inner_left（facing=north）：底半 + 北半边 + 西半边 = 上层 3/4 缺东南象限。
    final inner = BlockCollisionShapes.shapeFor(
        'minecraft:oak_stairs[facing=north,half=bottom,shape=inner_left,waterlogged=false]');
    expect(inner.boxes, hasLength(3), reason: '底半 + 两个半格');

    // outer_left（facing=north）：底半 + 西北象限（1/4 上块）。
    final outer = BlockCollisionShapes.shapeFor(
        'minecraft:oak_stairs[facing=north,half=bottom,shape=outer_left,waterlogged=false]');
    expect(outer.boxes, hasLength(2));
    final q = outer.boxes.last;
    expect(q.minX, 0.0);
    expect(q.maxX, closeTo(0.5, 1e-9));
    expect(q.minZ, 0.0);
    expect(q.maxZ, closeTo(0.5, 1e-9));

    // half=top：整体 y 镜像（base 在上半，梯级在下半）。
    final topStairs = BlockCollisionShapes.shapeFor(
        'minecraft:oak_stairs[facing=north,half=top,shape=straight,waterlogged=false]');
    final base = topStairs.boxes.first;
    expect(base.minY, closeTo(0.5, 1e-9));
    expect(base.maxY, 1.0);
  });

  test('楼梯旋转方向：BLOCK_ROT_Y_* 复合（N→E 顺时针；Shapes.java:390-403）', () {
    // outer_right（facing=north）key = cw(north) = east → rotate(OUTER, Y_90)：
    // 西北象限 → 东北象限（x 0.5..1, z 0..0.5）。StairBlock.java:88/:40。
    final outerRight = BlockCollisionShapes.shapeFor(
        'minecraft:oak_stairs[facing=north,half=bottom,shape=outer_right,waterlogged=false]');
    final q = outerRight.boxes.last;
    expect(q.minX, closeTo(0.5, 1e-9), reason: 'outer_right 梯级在东北象限');
    expect(q.maxX, closeTo(1.0, 1e-9));
    expect(q.minZ, 0.0);
    expect(q.maxZ, closeTo(0.5, 1e-9));

    // inner_right（facing=north）：底半 + 北半 + 东半；并集 = 上层缺西南象限
    // （原版 INNER = STRAIGHT ∪ rot90(STRAIGHT)，StairBlock.java:42；合并后
    // 分解为半条，逐点采样验证并集）。
    final innerRight = BlockCollisionShapes.shapeFor(
        'minecraft:oak_stairs[facing=north,half=bottom,shape=inner_right,waterlogged=false]');
    expect(innerRight.boxes, hasLength(3));
    bool coversUpper(double x, double z) => innerRight.boxes.any((b) =>
        b.minY == 0.5 && x >= b.minX && x <= b.maxX && z >= b.minZ && z <= b.maxZ);
    expect(coversUpper(0.25, 0.25), isTrue, reason: '西北象限有梯级');
    expect(coversUpper(0.75, 0.25), isTrue, reason: '东北象限有梯级');
    expect(coversUpper(0.75, 0.75), isTrue, reason: '东南象限有梯级');
    expect(coversUpper(0.25, 0.75), isFalse, reason: 'inner 缺西南象限');

    // straight 四向：梯级半格随 facing（S = Y_180、W = Y_270）。
    BlockBox stepOf(String facing) => BlockCollisionShapes.shapeFor(
            'minecraft:oak_stairs[facing=$facing,half=bottom,shape=straight,waterlogged=false]')
        .boxes
        .last;
    final south = stepOf('south');
    expect(south.minZ, closeTo(0.5, 1e-9), reason: 'facing=south 梯级在南半');
    expect(south.maxZ, closeTo(1.0, 1e-9));
    final west = stepOf('west');
    expect(west.minX, 0.0, reason: 'facing=west 梯级在西半');
    expect(west.maxX, closeTo(0.5, 1e-9));

    // half=top 的 outer：象限落到下半（INVERT_Y 复合，StairBlock.java:46）。
    final topOuter = BlockCollisionShapes.shapeFor(
        'minecraft:oak_stairs[facing=north,half=top,shape=outer_left,waterlogged=false]');
    final tq = topOuter.boxes.last;
    expect(tq.minY, 0.0);
    expect(tq.maxY, closeTo(0.5, 1e-9));
    expect(tq.minX, 0.0);
    expect(tq.maxX, closeTo(0.5, 1e-9));
    expect(tq.minZ, 0.0);
    expect(tq.maxZ, closeTo(0.5, 1e-9));
  });

  test('雪片：层高 0.125×n（判据 SnowLayerBlock.java:31）', () {
    expect(
      _maxY(BlockCollisionShapes.shapeFor('minecraft:snow[layers=1]')),
      closeTo(0.125, 1e-9),
    );
    expect(
      _maxY(BlockCollisionShapes.shapeFor('minecraft:snow[layers=4]')),
      closeTo(0.5, 1e-9),
    );
    expect(
      _maxY(BlockCollisionShapes.shapeFor('minecraft:snow[layers=8]')),
      1.0,
    );
  });

  test('耕地/土径 0.9375、灵魂沙 0.875、地毯 0.0625（J8）', () {
    expect(
      _maxY(BlockCollisionShapes.shapeFor('minecraft:farmland[moisture=0]')),
      closeTo(15 / 16, 1e-9),
    );
    expect(
      _maxY(BlockCollisionShapes.shapeFor('minecraft:dirt_path')),
      closeTo(15 / 16, 1e-9),
    );
    expect(
      _maxY(BlockCollisionShapes.shapeFor('minecraft:soul_sand')),
      closeTo(14 / 16, 1e-9),
    );
    expect(
      _maxY(BlockCollisionShapes.shapeFor('minecraft:white_carpet')),
      closeTo(1 / 16, 1e-9),
    );
  });

  test('栅栏门：关闭横贯 1.5、开启碰撞为空（判据 FenceGateBlock.java:105-108）', () {
    final closed = BlockCollisionShapes.shapeFor(
        'minecraft:oak_fence_gate[facing=north,in_wall=false,open=false,powered=false]');
    expect(_maxY(closed), 1.5);
    expect(closed.boxes, hasLength(1));
    final open = BlockCollisionShapes.shapeFor(
        'minecraft:oak_fence_gate[facing=north,in_wall=false,open=true,powered=false]');
    expect(open.isEmpty, isTrue, reason: '开启的门不阻挡（getCollisionShape → empty）');
  });
}
