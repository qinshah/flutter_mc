// 2026-10-11 用户实机反馈复现：
// ① 贴着墙走会卡死（只有朝向远离墙时才能动）；
// ② 房子门口卡住（门洞应可通行）。
//
// 判据对照（mc-sources/minecraft-26.2）：
// - VoxelShape.collideX（:251-300）：每形状按体素格扫描盒**占据格之外**的格子，
//   首个实心格 newDistance = 边缘 − 盒边；`newDistance >= -1e-7` 才截停——
//   即已深度穿透（< -1e-7）的形状**不阻挡**；截停值允许轻微负值（≈ -1e-7）。
// - 门：DoorBlock 形状由 open/facing/hinge 决定，open=true 是 3/16 薄板贴框，
//   门洞可通行（DoorBlock.java SHAPE_BY_STATUS）。
import 'package:flutter_mc/game/collision.dart';
import 'package:mc_render/mc_render.dart';
import 'package:flutter_test/flutter_test.dart';

/// 世界：地板 y<0 全实心；可注册额外方块。
class _World implements CollisionWorld {
  final Map<(int, int, int), VoxelShape> extra = {};

  @override
  VoxelShape? collisionShapeAt(int bx, int by, int bz) {
    final e = extra[(bx, by, bz)];
    if (e != null) return e;
    if (by < 0) return VoxelShape.full();
    return null;
  }
  @override
  double blockFrictionAt(int bx, int by, int bz) => 0.6;
  @override
  String? blockIdentityAt(int bx, int by, int bz) => null;

  @override
  bool isCollidable(int bx, int by, int bz) => collisionShapeAt(bx, by, bz) != null;

  @override
  bool isColumnLoaded(int cx, int cz) => true;

  @override
  int get worldHeight => 384;
}

void main() {
  test('贴墙平移：沿墙方向分量不被墙面截停（用户反馈①）', () {
    final world = _World();
    // 墙：x∈[1,2] 一列，y=0..2，z 无限延伸（逐格注册 20 格）。
    for (var z = -10; z <= 10; z++) {
      for (var y = 0; y <= 2; y++) {
        world.extra[(1, y, z)] = VoxelShape.full();
      }
    }
    final collision = VoxelCollision(world);
    // 玩家贴墙：centerX=0.7 ⇒ maxX = 1.0 恰好贴住墙面。
    final box = Aabb.player(0.7, 0.0, 5.0);
    // 朝墙斜走：dx=0.06 进墙、dz=0.12 沿墙。
    var (cx, cy, cz) = (box.centerX, box.minY, box.centerZ);
    for (var i = 0; i < 50; i++) {
      final r = collision.move(box, 0.06, -0.02, 0.12, wasOnGround: true);
      box
        ..centerX = r.centerX
        ..minY = r.minY
        ..centerZ = r.centerZ;
      (cx, cy, cz) = (r.centerX, r.minY, r.centerZ);
      // 位置不得穿透墙（maxX ≤ 1 + 1e-6）。
      expect(box.maxX, lessThanOrEqualTo(1.0 + 1e-6));
    }
    // 50 步后必须沿墙前进（z 至少走了 50×0.1 = 5 格）。
    expect(cz, greaterThan(5.0),
        reason: '贴墙 50 步后 z=$cz：沿墙分量被截停 = 卡死复现');
  });

  test('门洞通行：开着的门 = 薄板贴框，门洞 1 宽可通过（用户反馈②）', () {
    final world = _World();
    // 墙 z∈[0,1]（一格厚），x=0..3，y=0..2；门洞在 x=1（上下两格都是门）。
    for (var x = 0; x <= 3; x++) {
      for (var y = 0; y <= 2; y++) {
        if (x == 1 && y <= 1) continue; // 门洞：门块单独注册
        world.extra[(x, y, 0)] = VoxelShape.full();
      }
    }
    // 开着的门（open=true，facing=south，hinge=left）：原版 = 3/16 薄板
    // 贴在门框侧（判据 DoorBlock.java），**不挡 1 宽门洞**。
    // 我们的形状表现在还没有 door 条目 ⇒ 兜底整块 ⇒ 必然卡死。
    final openDoor = BlockCollisionShapes.shapeFor(
        'minecraft:oak_door[half=lower,facing=south,hinge=left,open=true,powered=false]');
    world.extra[(1, 0, 0)] = openDoor;
    world.extra[(1, 1, 0)] = BlockCollisionShapes.shapeFor(
        'minecraft:oak_door[half=upper,facing=south,hinge=left,open=true,powered=false]');

    final collision = VoxelCollision(world);
    final box = Aabb.player(1.5, 0.0, -2.0);
    for (var i = 0; i < 120; i++) {
      final r = collision.move(box, 0.0, -0.02, 0.14, wasOnGround: true);
      box
        ..centerX = r.centerX
        ..minY = r.minY
        ..centerZ = r.centerZ;
    }
    // 2.4 格的直线前进：必须穿门而过（z > 1，即门块 z∈[0,1] 已在身后）。
    expect(box.centerZ, greaterThan(1.0),
        reason: 'z=${box.centerZ}：卡在门口（open 门形状缺失/整块兜底）');
  });

  test('关着的门挡路（对照）', () {
    final world = _World();
    final closedDoor = BlockCollisionShapes.shapeFor(
        'minecraft:oak_door[half=lower,facing=south,hinge=left,open=false,powered=false]');
    expect(closedDoor, isNotNull);
    world.extra[(1, 0, 0)] = closedDoor;
    final collision = VoxelCollision(world);
    final box = Aabb.player(1.5, 0.0, -1.5);
    final r = collision.move(box, 0.0, 0.0, 0.3, wasOnGround: true);
    expect(r.centerZ, lessThan(-0.7), reason: '关门必须挡在门洞前');
  });

  test('微穿透状态：贴墙滑行与逃离放行，仅深入被下一块墙截停（用户反馈①根因）', () {
    final world = _World();
    // 两格厚墙：x∈[1,2] 与 x∈[2,3]，y=0..2。
    for (var z = -10; z <= 10; z++) {
      for (var y = 0; y <= 2; y++) {
        world.extra[(1, y, z)] = VoxelShape.full();
        world.extra[(2, y, z)] = VoxelShape.full();
      }
    }
    final collision = VoxelCollision(world);
    // 玩家已微穿透第一层墙（float32 大坐标抖动的复刻：maxX = 1.0005）。
    final box = Aabb.player(0.7005, 0.0, 5.0);
    var escaped = 0.0;
    for (var i = 0; i < 50; i++) {
      final r = collision.move(box, 0.06, -0.02, 0.12, wasOnGround: true);
      box
        ..centerX = r.centerX
        ..minY = r.minY
        ..centerZ = r.centerZ;
      if (i < 25) escaped = box.centerZ;
    }
    // 沿墙平移不受穿透影响（vanilla 体素扫描语义：穿透形状不参与阻挡）。
    expect(escaped, greaterThan(2.5), reason: '穿透状态下沿墙滑行被锁死 = 复现');
    // 深入方向被**第二层**墙贴面截停，不得穿出墙外。
    expect(box.maxX, lessThanOrEqualTo(3.0 + 1e-9));
  });

  test('贴面位置带 float 半宽偏移：中心 = 墙面 − float32(0.6)/2（服务器回拉根因）', () {
    // 判据：EntityDimensions.makeBoundingBox（EntityDimensions.java:19-22）
    //   float w = this.width / 2.0F;  // 0.6F → 半宽 0.30000001192092896
    //   new AABB(x - w, y, z - w, x + w, y + h, z + w);
    // 客户端与服务器都按此 float 语义建盒。贴面时盒子边缘停在墙面，
    // 上报的中心 = 墙面 − w。服务器重建盒后 `AABB.intersects` 严格不等式
    // 判穿透：中心若按 double 半宽（0.3）取值，服务器盒边缘 = 墙面 +
    // 1.1920917586394353e-08 → 判 CLIPPED_INTO_BLOCK 回拉抽搐
    // （Paper hasNewCollision 实测，docs/walk-jitter-diagnosis.md）。
    final world = _World();
    // 墙：x∈[1,2] 一列，y=0..2（实机场景墙面 z=241.0 平移到 x=1.0）。
    for (var z = -10; z <= 10; z++) {
      for (var y = 0; y <= 2; y++) {
        world.extra[(1, y, z)] = VoxelShape.full();
      }
    }
    final collision = VoxelCollision(world);
    // 从 2.3006194501184 逼近（复刻实机 from=241.3006194501184：盒缘离墙面
    // 还差 6.19e-4，向 -x 前进；墙面取 x=2.0，即墙块 x∈[1,2] 的 +x 侧面）。
    final box = Aabb.player(2.3006194501184, 0.0, 5.0);
    for (var i = 0; i < 20; i++) {
      final r = collision.move(box, -0.03, -0.02, 0.0, wasOnGround: true);
      box
        ..centerX = r.centerX
        ..minY = r.minY
        ..centerZ = r.centerZ;
    }
    // 黄金值：float32(0.6)/2 = 0.30000001192092896，
    // 贴面中心 ≥ 2.0 + 0.30000001192092896 = 2.300000011920928955078125
    // （服务器按同一语义重建盒后不穿透 = 被接受）。
    final serverMin = box.centerX - 0.300000011920928955078125;
    expect(serverMin, greaterThanOrEqualTo(2.0),
        reason: '服务器重建盒 min=$serverMin < 墙面 2.0（穿透）'
            ' → 必被 CLIPPED_INTO_BLOCK 回拉（贴面中心 ${box.centerX}）');
    // 旧 double 半宽实现的贴面值 2.3 恰好是本 bug：必须不再出现。
    expect(box.centerX, isNot(equals(2.3)));
    // 盒边缘贴面（不深穿）：minX ≥ 2.0。
    expect(box.minX, greaterThanOrEqualTo(2.0));
  });
}
