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

  test('栅栏门：关闭横贯、开启两端柱（债：in_wall 高度未建模）', () {
    final closed = BlockCollisionShapes.shapeFor(
        'minecraft:oak_fence_gate[facing=north,in_wall=false,open=false,powered=false]');
    expect(_maxY(closed), 1.5);
    final open = BlockCollisionShapes.shapeFor(
        'minecraft:oak_fence_gate[facing=north,in_wall=false,open=true,powered=false]');
    expect(open.boxes, hasLength(2), reason: '开启只剩两端门柱');
  });
}
