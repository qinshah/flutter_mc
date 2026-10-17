import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mc_render/mc_render.dart';
import 'package:vector_math/vector_math.dart';

import 'package:flutter_mc/game/collision.dart';
import 'package:flutter_mc/world/phys/vec3.dart';
import 'package:flutter_mc/world/entity/player/player.dart';

// ---------------------------------------------------------------------------
// 测试常量（对照 mc-sources/minecraft-26.2 只读参考源码）
// ---------------------------------------------------------------------------

/// VoxelCollision 默认贴合量：落到方块顶面后停在 `顶面 + epsilon`。
///
/// **判据 `AABB.EPSILON = 1.0E-7`**（`AABB.java:14`）—— 与 `VoxelCollision`
/// 的默认值同源。测试用同一常量，故实现改量级时本常量同步。
const double _epsilon = 1.0E-7;

/// 每格方块占 1.0，所以方块层 `by` 的顶面是 `by + 1.0`。
const double _floorTopY = 64.0;

/// 地板方块所在层（顶面 y = 64）。
const int _floorBlockY = 63;

/// 玩家站在地板上的静止高度。
const double _standY = _floorTopY + _epsilon;

/// LivingEntity.DEFAULT_BASE_GRAVITY = 0.08（格/刻²）。
const double _gravity = 0.08;

/// LivingEntity.BASE_JUMP_POWER = 0.42（格/刻）。
const double _jumpPower = 0.42;

/// `Player.position` / `eyePosition` / `lookDirection` 都是
/// `package:vector_math/vector_math.dart` 的 `Vector3`——它用 `Float32List`
/// 存数据（float64 版本是 `vector_math_64`），而 `Aabb` / `MoveResult` 是 double。
/// 所以凡是跟玩家身上的向量打交道，容差要按 float32 给：y≈64 时 ulp ≈ 7.6e-6。
const double _f32Tol = 1e-4;

/// 假的世界查询：用 `Map<(bx,by,bz), bool>` 记录"哪一格是实心"（缺省 = 空气）。
/// 实心格的碰撞形状 = 整块立方体（`Shapes.block()`）。
class _FakeWorld implements CollisionWorld {
  _FakeWorld({this.worldHeight = 384});

  @override
  final int worldHeight;

  final Map<(int, int, int), bool> _blocks = {};

  /// collisionShapeAt 被查询的次数。
  int shapeQueries = 0;

  /// isCollidable 被查询的次数（实体求解不再用它——仅射线等布尔场景）。
  int collidableQueries = 0;

  void setSolid(int bx, int by, int bz, [bool solid = true]) {
    _blocks[(bx, by, bz)] = solid;
  }

  /// 在 [minX,maxX]×[minZ,maxZ] 范围铺一层实心方块。
  void fillLayer(
    int by, {
    required int minX,
    required int maxX,
    required int minZ,
    required int maxZ,
  }) {
    for (var bx = minX; bx <= maxX; bx++) {
      for (var bz = minZ; bz <= maxZ; bz++) {
        setSolid(bx, by, bz);
      }
    }
  }

  @override
  VoxelShape? collisionShapeAt(int bx, int by, int bz) {
    shapeQueries++;
    if (by < 0 || by >= worldHeight) return null;
    return (_blocks[(bx, by, bz)] ?? false) ? VoxelShape.full() : null;
  }
  @override
  double blockFrictionAt(int bx, int by, int bz) => 0.6;
  @override
  String? blockIdentityAt(int bx, int by, int bz) => null;

  @override
  bool isCollidable(int bx, int by, int bz) {
    collidableQueries++;
    if (by < 0 || by >= worldHeight) return false;
    return _blocks[(bx, by, bz)] ?? false;
  }

  @override
  bool isColumnLoaded(int cx, int cz) => true;
}

/// 平地世界：地板铺在 `_floorBlockY`（顶面 y=64），范围 ±8。
_FakeWorld _flatWorld() {
  final world = _FakeWorld()
    ..fillLayer(_floorBlockY, minX: -8, maxX: 8, minZ: -8, maxZ: 8);
  return world;
}

void main() {
  // -------------------------------------------------------------------------
  // 1. AABB 常量与玩家盒几何
  // -------------------------------------------------------------------------

  test('AABB 常量：玩家宽 0.6 / 高 1.8 / 眼睛高 1.62', () {
    // 原版依据：EntityTypes 玩家 sized(0.6F, 1.8F)，
    // Avatar.DEFAULT_EYE_HEIGHT = 1.62F（Entity.java 用 position.y + eyeHeight）。
    // 建盒 float 语义（EntityDimensions.java:19-22）：width/height 是 float，
    // 半宽 = float32(0.6)/2 = 0.30000001192092896（非 double 0.3），
    // 头顶 = y + float32(1.8) = y + 1.7999999523162842（非 1.8）。
    const f32HalfWidth = 0.30000001192092896;
    const f32Height = 1.7999999523162842;
    expect(Aabb.playerWidth, 0.6);
    expect(Aabb.playerHeight, 1.8);
    expect(Aabb.eyeHeight, 1.62);

    final box = Aabb.player(1, 64, 2);
    expect(box.halfWidth, f32HalfWidth);
    expect(box.minX, closeTo(1.0 - f32HalfWidth, 1e-15));
    expect(box.x1, closeTo(1.0 + f32HalfWidth, 1e-15));
    expect(box.minZ, closeTo(2.0 - f32HalfWidth, 1e-15));
    expect(box.z1, closeTo(2.0 + f32HalfWidth, 1e-15));
    // [minY] 是脚底，[maxY] 是头顶。
    expect(box.minY, 64.0);
    expect(box.maxY, closeTo(64.0 + f32Height, 1e-15));
  });

  test('Aabb.intersects：相交为真，仅贴面/仅同层不接触为假', () {
    final base = Aabb(0, 0, 0, 1, 1); // x∈[-0.5,0.5] y∈[0,1] z∈[-0.5,0.5]
    expect(base.intersects(Aabb(0.4, 0.5, 0.4, 1, 1)), isTrue, reason: '三轴都重叠');
    expect(
      base.intersects(Aabb(1.0, 0, 0, 1, 1)),
      isFalse,
      reason: 'x 面恰好在 0.5 贴合不算相交',
    );
    expect(
      base.intersects(Aabb(0, 1.0, 0, 1, 1)),
      isFalse,
      reason: 'y 面贴合不算相交',
    );
    expect(
      base.intersects(Aabb(0, 0, 1.0, 1, 1)),
      isFalse,
      reason: 'z 面贴合不算相交',
    );
    expect(base.intersects(Aabb(2.0, 0, 0, 1, 1)), isFalse, reason: '完全分离');
    // intersects 是对称的。
    expect(Aabb(0.4, 0.5, 0.4, 1, 1).intersects(base), isTrue);
  });

  test('MoveResult.onGroundOf = yCollision && movementY < 0（Entity.java:1146）', () {
    const grounded = MoveResult(
      centerX: 0,
      minY: 64,
      centerZ: 0,
      xCollision: false,
      yCollision: true,
      zCollision: false,
    );
    expect(grounded.onGroundOf(-0.08), isTrue);
    expect(grounded.onGroundOf(0.08), isFalse, reason: '向上顶头不是着地');
    expect(
      const MoveResult(
        centerX: 0,
        minY: 64,
        centerZ: 0,
        xCollision: false,
        yCollision: false,
        zCollision: false,
      ).onGroundOf(-0.08),
      isFalse,
    );
    expect(grounded.onGroundOf(0), isFalse, reason: 'dy=0 不产生着地判定（调用方保持上一状态）');
  });

  // -------------------------------------------------------------------------
  // 2. 自由下落
  // -------------------------------------------------------------------------

  test('自由下落：无地面时受重力，y 逐刻递减且无竖直碰撞', () {
    final collision = VoxelCollision(_FakeWorld()); // 空世界
    final player = Player(position: const Vec3(0.5, 70.0, 0.5));

    var vy = 0.0;
    var previousY = player.position.y;
    for (var tick = 0; tick < 10; tick++) {
      vy -= _gravity;
      final r = collision.move(player.bounds, 0, vy, 0, wasOnGround: false);

      expect(r.yCollision, isFalse, reason: '空世界里不该撞到任何东西');
      player.applyMove(r);
      expect(
        player.position.y,
        lessThan(previousY),
        reason: '第 ${tick + 1} 刻应当继续下落',
      );
      previousY = player.position.y;
    }

    // 10 刻重力累积位移 = 0.08 * (1+2+...+10) = 4.4 格。
    expect(player.position.y, closeTo(70.0 - 4.4, _f32Tol));
    expect(player.position.x, 0.5, reason: '纯竖直下落不该产生水平位移');
    expect(player.position.z, 0.5);
  });

  test('自由下落：落到方块顶面后停住，onGround 为真且稳定', () {
    final collision = VoxelCollision(_flatWorld());
    final player = Player(position: const Vec3(0.5, 70.0, 0.5));

    var vy = 0.0;
    MoveResult? last;
    var landed = false;
    for (var tick = 0; tick < 100 && !landed; tick++) {
      vy -= _gravity;
      last = collision.move(player.bounds, 0, vy, 0, wasOnGround: player.onGround);
      player.onGround = last.onGroundOf(vy);
      player.applyMove(last);
      landed = player.onGround;
    }

    expect(landed, isTrue, reason: '100 刻内应当落地');
    expect(last!.yCollision, isTrue);
    expect(last.onGroundOf(vy), isTrue);
    // 停在方块顶面 + epsilon（写回 float32 位置，容差放宽到 float32）。
    expect(player.position.y, closeTo(_standY, _f32Tol));
    expect(player.position.y, greaterThanOrEqualTo(_floorTopY));

    // 再推一刻重力仍然停在同一高度（不穿地、不抖动——原版口径：重力持续
    // 作用、被地面截停，截停后每刻位移归零，位置稳定）。
    final rest = collision.move(player.bounds, 0, -_gravity, 0, wasOnGround: true);
    expect(rest.yCollision, isTrue);
    expect(rest.minY, closeTo(_floorTopY, 1e-12));
    expect(rest.onGroundOf(-_gravity), isTrue);

    // 连续推 100 刻位置逐刻相同（抽搐回归：无探针闪烁）。
    for (var i = 0; i < 100; i++) {
      final r = collision.move(player.bounds, 0, -_gravity, 0, wasOnGround: true);
      expect(r.minY, _floorTopY, reason: '第 $i 刻位置不得变化');
      expect(r.onGroundOf(-_gravity), isTrue);
    }
  });

  // -------------------------------------------------------------------------
  // 3. 跳跃
  // -------------------------------------------------------------------------

  test('跳跃：起跳初速度使 y 上升，随后回落并重新落地', () {
    final collision = VoxelCollision(_flatWorld());
    final player = Player(position: const Vec3(0.5, _standY, 0.5));

    final startY = player.position.y;
    expect(startY, closeTo(_standY, _f32Tol));

    // 起跳：一拍 0.42 格/刻的向上位移。
    var vy = _jumpPower;
    var r = collision.move(player.bounds, 0, vy, 0, wasOnGround: true);
    expect(r.yCollision, isFalse);
    expect(player.position.y, startY, reason: '求解不写回玩家，applyMove 之前位置不变');
    expect(r.minY, closeTo(startY + _jumpPower, 1e-9), reason: 'y 上升 0.42');
    player.applyMove(r);
    var peak = player.position.y;

    var landed = false;
    for (var tick = 0; tick < 100 && !landed; tick++) {
      vy -= _gravity;
      r = collision.move(player.bounds, 0, vy, 0, wasOnGround: player.onGround);
      player.onGround = r.onGroundOf(vy);
      player.applyMove(r);
      if (player.position.y > peak) peak = player.position.y;
      landed = player.onGround;
    }

    expect(landed, isTrue, reason: '跳起后必须落回地面');
    expect(peak, greaterThan(startY + 0.5), reason: '确实跳起来了');
    expect(peak, lessThan(startY + 2.0), reason: '跳跃高度约 1.1~1.4 格');
    expect(player.position.y, closeTo(startY, _f32Tol), reason: '落回方块顶面');
  });

  test('起跳后立刻受重力：第二拍位移已小于起跳初速度', () {
    final collision = VoxelCollision(_flatWorld());
    final player = Player(position: const Vec3(0.5, _standY, 0.5));
    final startY = player.position.y;
    var vy = _jumpPower - _gravity; // 0.34
    final r = collision.move(player.bounds, 0, vy, 0, wasOnGround: false);
    expect(r.minY, closeTo(startY + 0.34, 1e-9));
    expect(r.minY, lessThan(startY + _jumpPower));
  });

  // -------------------------------------------------------------------------
  // 4. 水平撞墙与逐轴求解顺序（判据 Direction.axisStepOrder，
  //    Direction.java:379-381：|x| < |z| ⇒ YZX，否则 YXZ）
  // -------------------------------------------------------------------------

  test('撞墙：贴墙轴位移被吃掉，另一轴仍可动', () {
    final world = _flatWorld();
    // bx=5 的两层高墙（脚层 64、头层 65），覆盖玩家的 bz 范围。
    world.fillLayer(64, minX: 5, maxX: 5, minZ: -8, maxZ: 8);
    world.fillLayer(65, minX: 5, maxX: 5, minZ: -8, maxZ: 8);
    final collision = VoxelCollision(world);
    final player = Player(position: const Vec3(4.0, _standY, 0.5));

    // 斜着往墙里撞：+X 撞墙、+Z 是空地，同时带一刻重力保持贴地。
    final r = collision.move(player.bounds, 1.0, -_gravity, 0.5, wasOnGround: true);

    expect(r.xCollision, isTrue, reason: '+X 被墙挡住');
    expect(r.zCollision, isFalse, reason: '+Z 没有障碍');
    // x 被截到墙面外侧：面 x=5.0 − float32(0.6)/2 = 4.699999988079071
    // （EntityDimensions.java:20：float w = width / 2.0F）。
    const f32HalfWidth = 0.30000001192092896;
    expect(r.centerX, closeTo(5.0 - f32HalfWidth, 1e-15));
    expect(r.centerX + f32HalfWidth, lessThanOrEqualTo(5.0),
        reason: '玩家盒不得进入墙体（贴面=接触，vanilla 语义）');
    // z 轴位移照常走完（另一轴仍可动）。
    expect(r.centerZ, closeTo(1.0, 1e-9));
    // 竖直方向贴地，没有漂移。
    expect(r.minY, closeTo(_floorTopY, 1e-12));
    expect(r.onGroundOf(-_gravity), isTrue);
  });

  test('逐轴顺序 axisStepOrder：|dx| < |dz| ⇒ YZX（Z 先解，X 用新 z 复查）', () {
    final world = _flatWorld();
    world.setSolid(5, 64, 1); // 单格柱子，只在 bx=5、bz=1 挡路
    final collision = VoxelCollision(world);
    final player = Player(position: const Vec3(4.0, _standY, 0.5));

    // |dx| = 0.8 < |dz| = 1.0 ⇒ 原版选 YZX（Y → Z → X）。
    final r = collision.move(player.bounds, 0.8, -_gravity, 1.0, wasOnGround: true);

    // Z 先解：出发时 x∈[3.7,4.3] 不覆盖柱子 bx=5 → z 走满到 2.0。
    expect(r.zCollision, isFalse);
    expect(r.centerZ, closeTo(1.5, 1e-9));
    // X 后解：用 z∈[1.2,1.8] 复查覆盖 bz=1 → 撞上柱子，
    // x 位移被截到 5.0 − float32(0.6)/2（EntityDimensions.java:20）。
    expect(r.xCollision, isTrue);
    expect(r.centerX, closeTo(5.0 - 0.30000001192092896, 1e-15));
    expect(r.minY, closeTo(_floorTopY, 1e-12), reason: '竖直轴最先解，不受水平影响');
  });

  test('逐轴顺序 axisStepOrder：|dx| > |dz| ⇒ YXZ（X 先解，Z 用新 x 复查）', () {
    final world = _flatWorld();
    world.setSolid(5, 64, 1); // 单格柱子 (x=5, z=1)
    final collision = VoxelCollision(world);
    final player = Player(position: const Vec3(4.0, _standY, 0.5));

    // |dx| = 1.0 > |dz| = 0.8 ⇒ 原版选 YXZ（Y → X → Z）。
    final r = collision.move(player.bounds, 1.0, -_gravity, 0.8, wasOnGround: true);

    // X 先解：bz=0 没柱子 → x 走满到 5.0；Z 后解用 x=5.0 复查撞柱子。
    expect(r.xCollision, isFalse);
    expect(r.centerX, closeTo(5.0, 1e-9));
    expect(r.zCollision, isTrue);
    // 截到 1.0 − float32(0.6)/2 = 0.699999988079071（EntityDimensions.java:20）。
    expect(r.centerZ, closeTo(1.0 - 0.30000001192092896, 1e-15));
  });

  // -------------------------------------------------------------------------
  // 5. 台阶/贴地
  // -------------------------------------------------------------------------

  test('贴地水平移动：脚在方块上时竖直位置不漂移', () {
    final collision = VoxelCollision(_flatWorld());
    final player = Player(position: const Vec3(0.5, _standY, 0.5));

    final r = collision.move(player.bounds, 0.25, -_gravity, 0.25, wasOnGround: true);
    player.applyMove(r);

    expect(r.xCollision, isFalse);
    expect(r.zCollision, isFalse);
    expect(r.yCollision, isTrue, reason: '重力下探到地面');
    expect(r.minY, closeTo(_floorTopY, 1e-12), reason: '贴地走不产生竖直漂移');
    expect(r.onGroundOf(-_gravity), isTrue);
    expect(r.centerX, closeTo(0.75, 1e-9));
    expect(r.centerZ, closeTo(0.75, 1e-9));
    expect(player.position.y, closeTo(_standY, _f32Tol));
  });

  test('dy=0：onGroundOf 为假，由调用方保持上一状态（vanilla 20Hz 口径）', () {
    final collision = VoxelCollision(_flatWorld());
    final player = Player(position: const Vec3(0.5, _standY, 0.5));

    final r = collision.move(player.bounds, 0.25, 0, 0, wasOnGround: true);

    // dy=0：竖直分支无碰撞；onGround 语义由调用方保持（local_player 只在
    // dy != 0 的结算点更新——站立时每刻重力给出 dy<0，onGround 稳定）。
    expect(r.yCollision, isFalse);
    expect(r.onGroundOf(0), isFalse);
    expect(r.centerX, closeTo(0.75, 1e-9));
    expect(r.minY, player.position.y, reason: 'dy=0 时 y 原样返回（float32 位置照抄）');
  });

  test('实体求解只查 collisionShapeAt（isCollidable 已不属于求解路径）', () {
    final world = _FakeWorld();
    world.setSolid(1, 64, 0);
    final collision = VoxelCollision(world, unloadedPassable: false);

    final r = collision.move(Aabb.player(0.5, 64.0, 0.5), 1.0, 0, 0, wasOnGround: false);

    expect(r.xCollision, isTrue, reason: '同一条形状查询路径照常判碰撞');
    expect(world.shapeQueries, greaterThan(0));
  });

  // -------------------------------------------------------------------------
  // 6. 玩家 look
  // -------------------------------------------------------------------------

  test('applyLook：鼠标右移 yaw 减小、下移 pitch 增大', () {
    final player = Player();
    expect(player.yaw, 0);
    expect(player.pitch, 0);

    // 原版公式（player-input 切片换用）：sens=(0.6×0.5+0.2)³×8=1.0，0.15°/像素。
    const perPx = 0.15 * math.pi / 180.0;
    player.applyLook(Vector2(1, 0));
    expect(player.yaw, closeTo(-perPx, 1e-9), reason: '鼠标右移 → yaw 减小 → 视线右转');
    expect(player.pitch, closeTo(0, 1e-9));

    player.applyLook(Vector2(-3, 2));
    expect(
      player.yaw,
      closeTo(-perPx + 3 * perPx, 1e-9),
      reason: '鼠标左移反向加回',
    );
    expect(
      player.pitch,
      closeTo(2 * perPx, 1e-9),
      reason: '鼠标下移 → pitch 增大（正值向下）',
    );

    // 灵敏度可注入：s=0.1 → sens=(0.26)³×8=0.140608，1px=0.15°×0.140608。
    final custom = Player()..applyLook(Vector2(1, 0), sensitivity: 0.1);
    expect(
      custom.yaw,
      closeTo(-0.15 * 0.140608 * math.pi / 180, 1e-9),
      reason: '灵敏度可注入',
    );
    expect(custom.pitch, 0);
  });

  test('pitch 钳制在 ±(π/2 − 0.0018) 附近，不越过头顶', () {
    const limit = math.pi / 2 - 0.0018;
    final player = Player();

    player.applyLook(Vector2(0, 1e6));
    expect(player.pitch, closeTo(limit, 1e-12));
    expect(player.pitch, lessThan(math.pi / 2), reason: '不能到正下方正 90°');

    player.applyLook(Vector2(0, -1e7));
    expect(player.pitch, closeTo(-limit, 1e-12));
    expect(player.pitch, greaterThan(-math.pi / 2), reason: '不能到正上方 −90°');
  });

  test('yaw 归一化到 (−π, π]', () {
    final player = Player();

    player.applyLook(Vector2(-1e6, 0)); // yaw 大幅增大
    expect(player.yaw, greaterThan(-math.pi));
    expect(player.yaw, lessThanOrEqualTo(math.pi));

    player.applyLook(Vector2(1e7, 0)); // yaw 大幅减小
    expect(player.yaw, greaterThan(-math.pi));
    expect(player.yaw, lessThanOrEqualTo(math.pi));
  });

  test('lookDirection：单位向量，yaw=0/pitch=0 时朝 −Z', () {
    final player = Player();

    var d = player.lookDirection;
    expect(d.x, closeTo(0, 1e-6));
    expect(d.y, closeTo(0, 1e-6));
    expect(d.z, closeTo(-1, 1e-6), reason: 'yaw=0 朝 −Z');
    expect(d.length, closeTo(1, 1e-6));

    player.yaw = math.pi / 2;
    d = player.lookDirection;
    expect(d.x, closeTo(-1, 1e-6), reason: 'yaw 增大 90° → 朝 −X');
    expect(d.z, closeTo(0, 1e-6));

    player.yaw = math.pi;
    player.pitch = 0;
    d = player.lookDirection;
    expect(d.z, closeTo(1, 1e-6), reason: 'yaw=π → 朝 +Z');
    expect(d.length, closeTo(1, 1e-6));

    player.pitch = math.pi / 2; // 正 pitch 向下
    expect(player.lookDirection.y, closeTo(-1, 1e-6), reason: 'pitch=+π/2 → 视线朝下');

    // 钳制范围内的任意角度都是单位向量（float32 存储，容差 1e-6）。
    for (final yaw in [0.0, 0.7, -2.3, 3.1]) {
      for (final pitch in [0.0, 1.2, -1.5, 1.5689]) {
        final v = Player(yaw: yaw, pitch: pitch).lookDirection;
        expect(v.length, closeTo(1, 1e-6), reason: 'yaw=$yaw pitch=$pitch');
      }
    }
  });

  test('eyePosition：在脚底之上 1.62 格（float32 向量，容差 1e-4）', () {
    final player = Player(position: const Vec3(1, 64, 2));
    expect(player.eyePosition.x, 1.0);
    expect(player.eyePosition.y, closeTo(64 + Aabb.eyeHeight, _f32Tol));
    expect(player.eyePosition.z, 2.0);
    expect(player.eyePosition.y, closeTo(65.62, _f32Tol));
  });

  // -------------------------------------------------------------------------
  // 7. MoveResult → Player 落地
  // -------------------------------------------------------------------------

  test('applyMove：位置落到 minY/centerX/centerZ（脚底中心语义）', () {
    final collision = VoxelCollision(_flatWorld());
    final player = Player(position: const Vec3(0.5, 70.0, 0.5));

    final r = collision.move(player.bounds, 0.25, -_gravity, -0.25, wasOnGround: false);
    // 求解本身不改玩家。
    expect(player.position.x, 0.5);
    expect(player.position.y, 70.0);
    expect(player.position.z, 0.5);
    player.applyMove(r);

    expect(player.position.x, closeTo(r.centerX, _f32Tol));
    expect(player.position.y, closeTo(r.minY, _f32Tol));
    expect(player.position.z, closeTo(r.centerZ, _f32Tol));
    expect(player.position.y, closeTo(70.0 - _gravity, _f32Tol));
    expect(player.position.x, closeTo(0.75, _f32Tol));
    expect(player.position.z, closeTo(0.25, _f32Tol));

    // bounds 以脚底为 minY，头顶 = minY + 1.8；眼睛 = minY + 1.62。
    expect(player.bounds.minY, closeTo(r.minY, _f32Tol));
    expect(player.bounds.centerX, closeTo(r.centerX, _f32Tol));
    expect(player.bounds.centerZ, closeTo(r.centerZ, _f32Tol));
    expect(player.bounds.maxY, closeTo(r.minY + 1.8, _f32Tol));
    // 眼睛 = 插值位置 + 1.62；progress=0 时渲染的是 old（tick 前位置，
    // EntityRenderer.java:164——恒 lerp，无 raw 退化分支）。快照后眼睛应
    // 落在 minY + 1.62。
    player.xOld = player.position.x;
    player.yOld = player.position.y;
    player.zOld = player.position.z;
    expect(player.eyePosition.y, closeTo(r.minY + 1.62, _f32Tol));

    // applyMove 只写位置，不动朝向与速度。
    expect(player.yaw, 0);
    expect(player.pitch, 0);
    expect(player.velocity, Vector3.zero());
  });

  test('移动求解不修改传入的 Aabb（纯函数，靠 applyMove 落地）', () {
    final collision = VoxelCollision(_flatWorld());
    final box = Aabb.player(0.5, _standY, 0.5);
    final before = [box.centerX, box.minY, box.centerZ, box.maxY];

    collision.move(box, 0.3, -_gravity, 0.3, wasOnGround: true);

    expect([box.centerX, box.minY, box.centerZ, box.maxY], before);
  });

  // -------------------------------------------------------------------------
  // 8. 世界边界（vanilla 无隐形地板/天花板：虚空下落由服务器 clampVertical 兜底）
  // -------------------------------------------------------------------------

  test('世界底部以下为虚空：无隐形地板，自由下落穿行（vanilla 语义）', () {
    final collision = VoxelCollision(_FakeWorld());
    final player = Player(position: const Vec3(0.5, 3.0, 0.5));

    final r = collision.move(player.bounds, 0, -10.0, 0, wasOnGround: false);

    expect(r.yCollision, isFalse, reason: 'y<0 无任何碰撞形状');
    expect(r.minY, closeTo(-7.0, 1e-9), reason: '位移原样走完（服务器 clampVertical 兜底）');
  });

  test('世界顶部以上无碰撞形状：不会被天花板意外卡住', () {
    final world = _FakeWorld(worldHeight: 80)
      ..fillLayer(_floorBlockY, minX: -8, maxX: 8, minZ: -8, maxZ: 8);
    final collision = VoxelCollision(world);

    final high = Player(position: const Vec3(0.5, 79.0, 0.5));
    final r = collision.move(high.bounds, 0, 0.5, 0, wasOnGround: false);
    expect(r.yCollision, isFalse);
    expect(r.minY, closeTo(79.5, 1e-9));

    // 对照：同一个世界里的地板仍然正常判碰撞。
    final standing = Player(position: const Vec3(0.5, _standY, 0.5));
    expect(
      collision.move(standing.bounds, 0, -_gravity, 0, wasOnGround: true).yCollision,
      isTrue,
    );
  });

  // -------------------------------------------------------------------------
  // 9. 走下方块边缘（vanilla：Y 先解用移动前位置判地，下一拍才下落）
  // -------------------------------------------------------------------------

  test('走下平台边缘：第一拍仍判到脚下平台（Y 先解），下一拍开始下落', () {
    final world = _FakeWorld();
    // 只铺 x∈[-8,0] 的地板，玩家从边缘走出去。
    world.fillLayer(_floorBlockY, minX: -8, maxX: 0, minZ: -8, maxZ: 8);
    final collision = VoxelCollision(world);
    final player = Player(position: const Vec3(0.5, _standY, 0.5));

    // 第一拍：还在平台上。
    final onPlate = collision.move(player.bounds, 0, -_gravity, 0, wasOnGround: true);
    expect(onPlate.yCollision, isTrue);
    expect(onPlate.onGroundOf(-_gravity), isTrue);
    player.applyMove(onPlate);

    // 第二拍：水平走出平台。colliders 按 expandTowards 一次收集（含新旧两处），
    // Y 先解时 box 还在旧 x（覆盖 bx=0）→ 仍判到平台，截停竖直位移；
    // 随后 X 走满走出平台。onGround = true（yCollision && dy<0）。
    final offPlate = collision.move(player.bounds, 1.0, -_gravity, 0, wasOnGround: true);
    expect(offPlate.centerX, closeTo(1.5, 1e-9));
    expect(offPlate.xCollision, isFalse);
    expect(offPlate.yCollision, isTrue, reason: 'Y 先解：平台仍在盒正下方（旧 x）');
    expect(offPlate.onGroundOf(-_gravity), isTrue);
    expect(offPlate.minY, closeTo(_floorTopY, 1e-12), reason: '这一拍还没开始掉');
    player.applyMove(offPlate);

    // 第三拍：盒已完全离开平台 → 无支撑，开始下落。
    final falling = collision.move(player.bounds, 0, -_gravity, 0, wasOnGround: true);
    expect(falling.yCollision, isFalse);
    expect(falling.onGroundOf(-_gravity), isFalse);
    expect(
      falling.minY,
      closeTo(player.position.y - _gravity, 1e-9),
      reason: '自由下落一拍',
    );
  });
}
