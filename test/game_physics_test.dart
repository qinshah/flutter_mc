import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'package:flutter_mc/game/collision.dart';
import 'package:flutter_mc/game/player.dart';

// ---------------------------------------------------------------------------
// 测试常量（对照 mc-sources/minecraft-26.2 只读参考源码）
// ---------------------------------------------------------------------------

/// VoxelCollision 默认贴合量：落到方块顶面后停在 `顶面 + epsilon`。
const double _epsilon = 1e-4;

/// 每格方块占 1.0，所以方块层 `by` 的顶面是 `by + 1.0`。
const double _floorTopY = 64.0;

/// 地板方块所在层（顶面 y = 64）。
const int _floorBlockY = 63;

/// 玩家站在地板上的静止高度。
const double _standY = _floorTopY + _epsilon;

/// LivingEntity.DEFAULT_BASE_GRAVITY = 0.08（格/刻²）。
///
/// 重力积分本身不在 collision.dart / player.dart 里（那两处只管几何求解与
/// 玩家状态），它属于呼叫方的移动循环；因此测试自行按原版常量积分。
const double _gravity = 0.08;

/// LivingEntity.BASE_JUMP_POWER = 0.42（格/刻）。
const double _jumpPower = 0.42;

/// `Player.position` / `eyePosition` / `lookDirection` 都是
/// `package:vector_math/vector_math.dart` 的 `Vector3`——它用 `Float32List`
/// 存数据（float64 版本是 `vector_math_64`），而 `Aabb` / `MoveResult` 是 double。
/// 所以凡是跟玩家身上的向量打交道，容差要按 float32 给：y≈64 时 ulp ≈ 7.6e-6。
const double _f32Tol = 1e-4;

/// 假的世界查询：用 `Map<(bx,by,bz), bool>` 记录"哪一格是实心"（缺省 = 空气）。
class _FakeWorld implements CollisionWorld {
  _FakeWorld({this.worldHeight = 384});

  @override
  final int worldHeight;

  final Map<(int, int, int), bool> _blocks = {};

  /// isCollidable 被查询的次数。
  int collidableQueries = 0;

  /// isColumnLoaded 被查询的次数（当前求解从不查询，见"记录语义"用例）。
  int columnLoadedQueries = 0;

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
  bool isCollidable(int bx, int by, int bz) {
    collidableQueries++;
    if (by < 0 || by >= worldHeight) return false;
    return _blocks[(bx, by, bz)] ?? false;
  }

  @override
  bool isColumnLoaded(int cx, int cz) {
    columnLoadedQueries++;
    return true;
  }
}

/// 平坦地板世界：仅 `_floorBlockY` 一层实心，±8 格范围。
_FakeWorld _flatWorld() {
  final world = _FakeWorld();
  world.fillLayer(_floorBlockY, minX: -8, maxX: 8, minZ: -8, maxZ: 8);
  return world;
}

void main() {
  // -------------------------------------------------------------------------
  // 1. AABB 常量与玩家盒几何
  // -------------------------------------------------------------------------

  test('AABB 常量：玩家宽 0.6 / 高 1.8 / 眼睛高 1.62', () {
    // 原版依据：EntityTypes 玩家 sized(0.6F, 1.8F)，
    // Avatar.DEFAULT_EYE_HEIGHT = 1.62F（Entity.java 用 position.y + eyeHeight）。
    expect(Aabb.playerWidth, 0.6);
    expect(Aabb.playerHeight, 1.8);
    expect(Aabb.eyeHeight, 1.62);

    final box = Aabb.player(1, 64, 2);
    expect(box.halfWidth, closeTo(0.3, 1e-12));
    expect(box.minX, closeTo(0.7, 1e-12));
    expect(box.x1, closeTo(1.3, 1e-12));
    expect(box.minZ, closeTo(1.7, 1e-12));
    expect(box.z1, closeTo(2.3, 1e-12));
    // [minY] 是脚底，[maxY] 是头顶。
    expect(box.minY, 64.0);
    expect(box.maxY, closeTo(64.0 + 1.8, 1e-12));
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

  test('MoveResult.onGround = hitY && hasBlockBelow', () {
    const grounded = MoveResult(
      centerX: 0,
      minY: 64,
      centerZ: 0,
      hitX: false,
      hitY: true,
      hitZ: false,
      hasBlockBelow: true,
    );
    expect(grounded.onGround, isTrue);
    expect(
      const MoveResult(
        centerX: 0,
        minY: 64,
        centerZ: 0,
        hitX: false,
        hitY: false,
        hitZ: false,
        hasBlockBelow: true,
      ).onGround,
      isFalse,
      reason: '有支撑但本刻没发生竖直碰撞 → 不算着地',
    );
    expect(
      const MoveResult(
        centerX: 0,
        minY: 64,
        centerZ: 0,
        hitX: false,
        hitY: true,
        hitZ: false,
        hasBlockBelow: false,
      ).onGround,
      isFalse,
      reason: '竖直撞了但不是向下撞出的支撑',
    );
  });

  // -------------------------------------------------------------------------
  // 2. 自由下落
  // -------------------------------------------------------------------------

  test('自由下落：无地面时受重力，y 逐刻递减且 onGround 为假', () {
    final collision = VoxelCollision(_FakeWorld()); // 空世界
    final player = Player(position: Vector3(0.5, 70.0, 0.5));

    var vy = 0.0;
    var previousY = player.position.y;
    for (var tick = 0; tick < 10; tick++) {
      vy -= _gravity;
      final r = collision.move(player.bounds, 0, vy, 0);

      expect(r.hitY, isFalse, reason: '空世界里不该撞到任何东西');
      expect(r.hasBlockBelow, isFalse, reason: '脚下没有实心方块');
      expect(r.onGround, isFalse);
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

  test('自由下落：落到方块顶面后停住，onGround 为真', () {
    final collision = VoxelCollision(_flatWorld());
    final player = Player(position: Vector3(0.5, 70.0, 0.5));

    var vy = 0.0;
    MoveResult? last;
    var landed = false;
    for (var tick = 0; tick < 100 && !landed; tick++) {
      vy -= _gravity;
      last = collision.move(player.bounds, 0, vy, 0);
      if (last.onGround) vy = 0; // 落地竖直速度清零（呼叫方职责）
      player.applyMove(last);
      landed = last.onGround;
    }

    expect(landed, isTrue, reason: '100 刻内应当落地');
    expect(last!.hitY, isTrue);
    expect(last.hasBlockBelow, isTrue);
    expect(last.onGround, isTrue);
    // 停在方块顶面 + epsilon（写回 float32 位置，容差放宽到 float32）。
    expect(player.position.y, closeTo(_standY, _f32Tol));
    expect(player.position.y, greaterThanOrEqualTo(_floorTopY));

    // 再推一刻重力仍然停在同一高度（不穿地、不抖动）。
    final rest = collision.move(player.bounds, 0, -_gravity, 0);
    expect(rest.hitY, isTrue);
    expect(rest.minY, closeTo(_standY, 1e-12));
    expect(rest.onGround, isTrue);
  });

  // -------------------------------------------------------------------------
  // 3. 跳跃
  // -------------------------------------------------------------------------

  test('跳跃：起跳初速度使 y 上升，随后回落并重新落地', () {
    final collision = VoxelCollision(_flatWorld());
    final player = Player(position: Vector3(0.5, _standY, 0.5));

    // 位置存的是 float32，先记下实际静止高度，后续期望值都基于它算。
    final startY = player.position.y;
    expect(startY, closeTo(_standY, _f32Tol));

    // 起跳：一拍 0.42 格/刻的向上位移。
    var vy = _jumpPower;
    var r = collision.move(player.bounds, 0, vy, 0);
    expect(r.hitY, isFalse);
    expect(player.position.y, startY, reason: '求解不写回玩家，applyMove 之前位置不变');
    expect(r.minY, closeTo(startY + _jumpPower, 1e-9), reason: 'y 上升 0.42');
    expect(r.onGround, isFalse, reason: '上升中 hasBlockBelow 被强制为假');
    player.applyMove(r);
    var peak = player.position.y;

    var landed = false;
    for (var tick = 0; tick < 100 && !landed; tick++) {
      vy -= _gravity;
      r = collision.move(player.bounds, 0, vy, 0);
      if (r.onGround) vy = 0;
      player.applyMove(r);
      if (player.position.y > peak) peak = player.position.y;
      landed = r.onGround;
    }

    expect(landed, isTrue, reason: '跳起后必须落回地面');
    expect(peak, greaterThan(startY + 0.5), reason: '确实跳起来了');
    expect(peak, lessThan(startY + 2.0), reason: '跳跃高度约 1.1~1.4 格');
    expect(player.position.y, closeTo(startY, _f32Tol), reason: '落回方块顶面');
  });

  test('起跳后立刻受重力：第二拍位移已小于起跳初速度', () {
    final collision = VoxelCollision(_flatWorld());
    final player = Player(position: Vector3(0.5, _standY, 0.5));
    final startY = player.position.y;
    var vy = _jumpPower - _gravity; // 0.34
    final r = collision.move(player.bounds, 0, vy, 0);
    expect(r.minY, closeTo(startY + 0.34, 1e-9));
    expect(r.minY, lessThan(startY + _jumpPower));
  });

  // -------------------------------------------------------------------------
  // 4. 水平撞墙与逐轴求解顺序
  // -------------------------------------------------------------------------

  test('撞墙：贴墙轴位移被吃掉，另一轴仍可动', () {
    final world = _flatWorld();
    // bx=5 的两层高墙（脚层 64、头层 65），覆盖玩家的 bz 范围。
    world.fillLayer(64, minX: 5, maxX: 5, minZ: -8, maxZ: 8);
    world.fillLayer(65, minX: 5, maxX: 5, minZ: -8, maxZ: 8);
    final collision = VoxelCollision(world);
    final player = Player(position: Vector3(4.0, _standY, 0.5));

    // 斜着往墙里撞：+X 撞墙、+Z 是空地，同时带一刻重力保持贴地。
    final r = collision.move(player.bounds, 1.0, -_gravity, 0.5);

    expect(r.hitX, isTrue, reason: '+X 被墙挡住');
    expect(r.hitZ, isFalse, reason: '+Z 没有障碍');
    // x 被推到墙面外侧：面 x=5.0 − 半宽 0.3 − epsilon。
    expect(r.centerX, closeTo(5.0 - 0.3 - _epsilon, 1e-9));
    expect(r.centerX + 0.3, lessThan(5.0), reason: '玩家盒不得进入墙体');
    // z 轴位移照常走完（另一轴仍可动）。
    expect(r.centerZ, closeTo(1.0, 1e-9));
    // 竖直方向贴地，没有漂移。
    expect(r.minY, closeTo(_standY, 1e-12));
    expect(r.onGround, isTrue);
  });

  test('逐轴顺序 Y→X→Z：Z 轴用 X 求解后的新位置判碰撞', () {
    final world = _flatWorld();
    world.setSolid(5, 64, 1); // 单格柱子，只在 bx=5、bz=1 挡路
    final collision = VoxelCollision(world);
    final player = Player(position: Vector3(4.0, _standY, 0.5));

    final r = collision.move(player.bounds, 1.0, -_gravity, 1.0);

    // X 先解：出发时 z∈[0.2,0.8] 只看 bz=0，柱子不在这一列 → x 走满到 5.0。
    expect(r.hitX, isFalse);
    expect(r.centerX, closeTo(5.0, 1e-9));
    // Z 后解：用 x=5.0 复查时会覆盖 bx=5 → 撞上柱子，z 位移被吃掉。
    // （若顺序反过来先解 Z，x=4.0 时只查 bx=3，z 会一路走完 1.5。）
    expect(r.hitZ, isTrue);
    expect(r.centerZ, closeTo(1.0 - 0.3 - _epsilon, 1e-9));
    expect(r.minY, closeTo(_standY, 1e-12), reason: '竖直轴最先解，不受水平影响');
  });

  // -------------------------------------------------------------------------
  // 5. 台阶/贴地
  // -------------------------------------------------------------------------

  test('贴地水平移动：脚在方块上时竖直位置不漂移', () {
    final collision = VoxelCollision(_flatWorld());
    final player = Player(position: Vector3(0.5, _standY, 0.5));

    final r = collision.move(player.bounds, 0.25, -_gravity, 0.25);
    player.applyMove(r);

    expect(r.hitX, isFalse);
    expect(r.hitZ, isFalse);
    expect(r.hitY, isTrue, reason: '重力下探到地面');
    expect(r.minY, closeTo(_standY, 1e-12), reason: '贴地走不产生竖直漂移');
    expect(r.hasBlockBelow, isTrue);
    expect(r.onGround, isTrue);
    expect(r.centerX, closeTo(0.75, 1e-9));
    expect(r.centerZ, closeTo(0.75, 1e-9));
    expect(player.position.y, closeTo(_standY, _f32Tol));
  });

  test('记录语义：贴地但 dy=0 时 onGround 为假（见报告可疑点 1）', () {
    final collision = VoxelCollision(_flatWorld());
    final player = Player(position: Vector3(0.5, _standY, 0.5));

    final r = collision.move(player.bounds, 0.25, 0, 0);

    expect(r.hasBlockBelow, isTrue, reason: '脚下确实是实心方块');
    expect(r.hitY, isFalse, reason: 'dy=0 时竖直分支整体不执行，hitY 保持初值 false');
    expect(r.onGround, isFalse, reason: 'onGround = hitY && hasBlockBelow');
    // 水平移动不受影响。
    expect(r.centerX, closeTo(0.75, 1e-9));
    expect(r.minY, player.position.y, reason: 'dy=0 时 y 原样返回（float32 位置照抄）');
  });

  test(
    '记录语义：求解只查 isCollidable；isColumnLoaded/unloadedPassable 目前是死参数（待对齐原版未加载区语义）',
    () {
      final world = _FakeWorld();
      // 玩家脚底中心 (0.5, 64, 0.5) 占 x∈[0.2,0.8]；墙要放**下一格** x∈[1,2)
      // 才是"正前方"。放在 (0,...) 是玩家已经站进去的那一格，求解器不处理初始重叠。
      world.setSolid(1, 64, 0);
      final collision = VoxelCollision(world, unloadedPassable: false);

      final r = collision.move(Aabb.player(0.5, 64.0, 0.5), 1.0, 0, 0);

      expect(r.hitX, isTrue, reason: '同一条查询路径照常判碰撞');
      expect(world.collidableQueries, greaterThan(0));
      expect(world.columnLoadedQueries, 0, reason: '当前实现从不查询列加载状态');
    },
  );

  // -------------------------------------------------------------------------
  // 6. 玩家 look
  // -------------------------------------------------------------------------

  test('applyLook：鼠标右移 yaw 减小、下移 pitch 增大', () {
    final player = Player();
    expect(player.yaw, 0);
    expect(player.pitch, 0);

    // 默认灵敏度 0.0022。
    player.applyLook(Vector2(1, 0));
    expect(player.yaw, closeTo(-0.0022, 1e-12), reason: '鼠标右移 → yaw 减小 → 视线右转');
    expect(player.pitch, closeTo(0, 1e-12));

    player.applyLook(Vector2(-3, 2));
    expect(
      player.yaw,
      closeTo(-0.0022 + 3 * 0.0022, 1e-12),
      reason: '鼠标左移反向加回',
    );
    expect(
      player.pitch,
      closeTo(2 * 0.0022, 1e-12),
      reason: '鼠标下移 → pitch 增大（正值向下）',
    );

    final custom = Player()..applyLook(Vector2(1, 0), sensitivity: 0.1);
    expect(custom.yaw, closeTo(-0.1, 1e-12), reason: '灵敏度可注入');
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
    d = player.lookDirection;
    expect(d.y, closeTo(-1, 1e-6), reason: 'pitch=+π/2 → 视线朝下');
    expect(d.length, closeTo(1, 1e-6));

    // 钳制范围内的任意角度都是单位向量（float32 存储，容差 1e-6）。
    for (final yaw in [0.0, 0.7, -2.3, 3.1]) {
      for (final pitch in [0.0, 1.2, -1.5, 1.5689]) {
        final v = Player(yaw: yaw, pitch: pitch).lookDirection;
        expect(v.length, closeTo(1, 1e-6), reason: 'yaw=$yaw pitch=$pitch');
      }
    }
  });

  test('eyePosition：在脚底之上 1.62 格（float32 向量，容差 1e-4）', () {
    final player = Player(position: Vector3(1, 64, 2));
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
    final player = Player(position: Vector3(0.5, 70.0, 0.5));

    final r = collision.move(player.bounds, 0.25, -_gravity, -0.25);
    // 求解本身不改玩家。
    expect(player.position, Vector3(0.5, 70.0, 0.5));
    player.applyMove(r);

    // 位置写回 float32 的 Vector3，所以逐轴按 float32 容差比较
    // （x/z 这两个值本身能被 float32 精确表示，y 不能）。
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

    collision.move(box, 0.3, -_gravity, 0.3);

    expect([box.centerX, box.minY, box.centerZ, box.maxY], before);
  });

  // -------------------------------------------------------------------------
  // 8. 隧穿防护（substeps）
  // -------------------------------------------------------------------------

  test('substeps：小位移一步，大位移按最长轴拆步且总和不变', () {
    final small = substeps(0.1, -0.2, 0.3);
    expect(small, hasLength(1));
    expect(small.single[0], 0.1);
    expect(small.single[1], -0.2);
    expect(small.single[2], 0.3);

    final steps = substeps(1.0, 0, -0.2);
    expect(steps, hasLength(3), reason: 'ceil(1.0 / 0.4) = 3');
    var sx = 0.0;
    var sy = 0.0;
    var sz = 0.0;
    for (final s in steps) {
      expect(s[0].abs(), lessThanOrEqualTo(0.4 + 1e-12));
      expect(s[1].abs(), lessThanOrEqualTo(0.4 + 1e-12));
      expect(s[2].abs(), lessThanOrEqualTo(0.4 + 1e-12));
      sx += s[0];
      sy += s[1];
      sz += s[2];
    }
    expect(sx, closeTo(1.0, 1e-12));
    expect(sy, closeTo(0.0, 1e-12));
    expect(sz, closeTo(-0.2, 1e-12));

    // 只按最长轴决定步数：竖直大位移同样拆步。
    expect(substeps(0, -1.2, 0), hasLength(3));
    expect(substeps(0, 0.4, 0), hasLength(1), reason: '恰好等于 maxStep 不拆');
  });

  // -------------------------------------------------------------------------
  // 9. 世界边界
  // -------------------------------------------------------------------------

  test('世界底部（by < 0）视为阻挡：不会掉出世界', () {
    final collision = VoxelCollision(_FakeWorld());
    final player = Player(position: Vector3(0.5, 3.0, 0.5));

    final r = collision.move(player.bounds, 0, -10.0, 0);

    expect(r.hitY, isTrue);
    // 向下分支把 by<0 当实心层处理：y = by + 1 + epsilon = -1 + 1 + epsilon，
    // 也就是"有效地面顶面在 y=0"（见报告可疑点 4）。
    expect(r.minY, closeTo(_epsilon, 1e-9));
    expect(r.onGround, isTrue);
  });

  test('世界顶部（by >= worldHeight）不阻挡：跳起不会被天花板意外卡住', () {
    // 用一个矮世界（高 80）把玩家放到贴顶位置。
    final world = _FakeWorld(worldHeight: 80)
      ..fillLayer(_floorBlockY, minX: -8, maxX: 8, minZ: -8, maxZ: 8);
    final collision = VoxelCollision(world);

    // 贴顶时向上推：_layerBlockedY 在 by >= worldHeight 返回 false。
    final high = Player(position: Vector3(0.5, 79.0, 0.5));
    final r = collision.move(high.bounds, 0, 0.5, 0);
    expect(r.hitY, isFalse);
    expect(r.minY, closeTo(79.5, 1e-9));

    // 对照：同一个世界里的地板仍然正常判碰撞。
    final standing = Player(position: Vector3(0.5, _standY, 0.5));
    expect(collision.move(standing.bounds, 0, -_gravity, 0).hitY, isTrue);
  });

  // -------------------------------------------------------------------------
  // 10. 水平边界：走上方块边缘
  // -------------------------------------------------------------------------

  test('走下平台边缘：竖直轴先用移动前的 x 判定，下一拍才下落', () {
    final world = _FakeWorld();
    // 只铺 x∈[-8,0] 的地板，玩家从边缘走出去。
    world.fillLayer(_floorBlockY, minX: -8, maxX: 0, minZ: -8, maxZ: 8);
    final collision = VoxelCollision(world);
    final player = Player(position: Vector3(0.5, _standY, 0.5));

    // 第一拍：还在平台上（x∈[0.2,0.8] 覆盖 bx=0）。
    final onPlate = collision.move(player.bounds, 0, -_gravity, 0);
    expect(onPlate.hitY, isTrue);
    expect(onPlate.onGround, isTrue);
    player.applyMove(onPlate);

    // 第二拍：水平走出平台。Y 轴最先解、用的是移动前的 x=0.5，
    // 所以这一拍仍判到脚下的方块；hasBlockBelow 却用移动后的 x=1.5，
    // 于是 hitY 真、hasBlockBelow 假 → onGround 假（竖直/水平判定基准不同）。
    final offPlate = collision.move(player.bounds, 1.0, -_gravity, 0);
    expect(offPlate.centerX, closeTo(1.5, 1e-9));
    expect(offPlate.hitX, isFalse);
    expect(offPlate.hitY, isTrue, reason: 'Y 轴用移动前的 x=0.5 判到了脚下方块');
    expect(
      offPlate.hasBlockBelow,
      isFalse,
      reason: 'hasBlockBelow 用移动后的 x=1.5：脚下已悬空',
    );
    expect(offPlate.onGround, isFalse);
    expect(offPlate.minY, closeTo(_standY, 1e-12), reason: '这一拍还没开始掉');
    player.applyMove(offPlate);

    // 第三拍：仍然没有支撑，开始下落（起点是 float32 写回后的高度）。
    final falling = collision.move(player.bounds, 0, -_gravity, 0);
    expect(falling.hitY, isFalse);
    expect(falling.onGround, isFalse);
    expect(
      falling.minY,
      closeTo(player.position.y - _gravity, 1e-9),
      reason: '自由下落一拍',
    );
  });

  test('记录语义：水平轴顺序恒为 X→Z（原版按 |dx|/|dz| 选 YXZ/YZX，待对齐）', () {
    final world = _flatWorld();
    world.setSolid(5, 64, 1); // 单格柱子 (x=5, z=1)
    final collision = VoxelCollision(world);
    final player = Player(position: Vector3(4.0, _standY, 0.5));

    // |dz| = 1.0 > |dx| = 0.8：原版 Direction.axisStepOrder 会选 YZX（先 Z），
    // 本实现固定 Y→X→Z。两者结果不同，这里断言实现的实际结果。
    final r = collision.move(player.bounds, 0.8, -_gravity, 1.0);

    // 实现的 X→Z：X 先走（bz=0 没柱子）→ x=4.8；再用 x=4.8 解 Z，
    // 复查覆盖 bx=5 → 撞柱子，z 位移被吃掉。
    expect(r.hitX, isFalse);
    expect(r.centerX, closeTo(4.8, 1e-9));
    expect(r.hitZ, isTrue);
    expect(r.centerZ, closeTo(1.0 - 0.3 - _epsilon, 1e-9));
    // 原版 YZX 会是：Z 先走完到 1.5，再由 z=1.5 解 X 撞柱子 → hitX 真。
    expect(r.hitZ && !r.hitX, isTrue, reason: '固定 X→Z 的可观测后果');
  });
}
