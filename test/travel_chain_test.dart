// 2026-10-11 用户实机反馈三症状的回归测试（黄金值 = 原版 26.2 递推）：
//
// ① 走出高方块下落过快 —— 根因：着地不清 vy ⇒ 站立时 vy 收敛到 −3.92 格/刻
//   （终端速度），走出悬空 = 瞬时满速下坠。原版 `Entity.move` 的 restitute
//   （Entity.java:793-795/:851-853，restitution=0）每刻落地清零 vy ⇒ 站立 vy
//   恒为 −0.0784，走出后逐刻递推 −0.0784、(−0.0784−0.08)×0.98 = −0.155448…
// ② 跳跃未落地水平移动过快 —— 原版空中注入 = `getFlyingSpeed()` = 0.02 格/刻
//   （LivingEntity.java:2699-2701）+ 0.91 阻力（动量渐变），非全速直赋。
// ③ 对着墙按 W 抽搐 —— restitute 撞墙清轴后每刻只重新注入 0.1，位置必须
//   恒定；贴墙滑行（沿墙分量）不得被锁死。
//
// **方向约定**：本仓 yaw=0 时 forward = (−sin, −cos) = **−Z**；右 = +X。
import 'package:flutter_mc/client/player/local_player.dart';
import 'package:flutter_mc/game/collision.dart';
import 'package:flutter_mc/world/entity/player/abilities.dart';
import 'package:flutter_mc/world/entity/player/input.dart';
import 'package:flutter_mc/world/entity/player/player.dart';
import 'package:flutter_mc/world/phys/vec3.dart';
import 'package:mc_render/mc_render.dart';
import 'package:flutter_test/flutter_test.dart';

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

/// 每帧 dt=1/60（2 个固定步），[ticks] 个整刻。
void _runTicks(LocalPlayer c, Input input, int ticks) {
  const dt = 1 / 60.0;
  for (var i = 0; i < ticks * 3; i++) {
    c.tick(dt, input);
  }
}

void main() {
  test('① 站立 vy = −0.0784/刻（restitute 清零），走出高塔慢加速', () {
    final world = _World();
    // 5 格高塔顶平台：单块 (0,4,0)，顶面 y=5，四周悬空。
    world.extra[(0, 4, 0)] = VoxelShape.full();
    final player = Player(position: const Vec3(0.5, 5.0, 0.5));
    final c = LocalPlayer(
      world: world,
      player: player,
      abilities: Abilities(mayfly: false),
    );
    final input = Input();
    _runTicks(c, input, 10); // 站稳
    expect(player.onGround, isTrue);

    // 站立 vy = −0.0784×20 = −1.568 格/秒（不是收敛到终端 −78.4）。
    // 容差 1e-6：velocity 是渲染诊断用的 float32 Vector3。
    expect(player.velocity.y, closeTo(-1.568, 1e-6),
        reason: '站立 vy=${player.velocity.y}：restitute 缺失时收敛到 −78.4');

    // 向前走（yaw=0 ⇒ −Z）走出平台，逐刻记录下落位移。
    input.move.y = 1.0;
    final ys = <double>[player.position.y];
    for (var i = 0; i < 8; i++) {
      _runTicks(c, input, 1);
      ys.add(player.position.y);
    }
    final drops = [for (var i = 1; i < ys.length; i++) ys[i - 1] - ys[i]];
    // 悬空后的下落递推（格/刻）：0.0784、0.155448、0.231339、0.306213…
    // 第一刻位移 < 0.2（原版慢加速）；绝不能是终端 3.92。
    final falling = drops.where((d) => d > 1e-6).toList();
    expect(falling, isNotEmpty, reason: '走出平台后必须下落');
    expect(falling.first, lessThan(0.2),
        reason: '走出方块第一刻下落 ${falling.first}：restitute 缺失 = 瞬时终端');
    // 第二刻比第一刻大（加速中），且符合递推比例。
    if (falling.length >= 2) {
      expect(falling[1], greaterThan(falling.first));
    }
  });

  test('② 跳跃未落地：空中急转靠 0.02/刻渐变（1 刻内动量仍前进）', () {
    final world = _World();
    final player = Player(position: const Vec3(100.5, 0.0, 100.5));
    final c = LocalPlayer(
      world: world,
      player: player,
      abilities: Abilities(mayfly: false),
    );
    // yaw = π ⇒ forward = +Z，地面加速 10 刻建立动量。
    player.yaw = 3.141592653589793;
    final input = Input()..move.y = 1.0;
    _runTicks(c, input, 10);
    // player.velocity = 摩擦后的 deltaMovement（原版口径）；稳态位移
    // 0.1/(1−0.546) = 0.2203 格/刻 ⇒ velocity = ×0.546×20 = 2.406 格/秒。
    expect(player.velocity.z, closeTo(2.406, 0.15),
        reason: '地面稳态 velocity=${player.velocity.z}');

    // 起跳（1 刻）。
    input.jump = true;
    _runTicks(c, input, 1);
    input.jump = false;
    expect(player.onGround, isFalse);

    // 空中**反向**输入：原版空中注入 −0.02/刻 + 动量 ×0.91 ⇒ 1 刻后位移
    // 仍为前进方向（+Z）；旧实现（直赋全速）1 帧即反向 = "空中移动过快"。
    input.move.y = -1.0;
    final zStart = player.position.z;
    _runTicks(c, input, 1);
    final moved = player.position.z - zStart;
    expect(moved, greaterThan(0.0),
        reason: '空中 1 刻就反向位移 $moved = 直赋全速（旧实现），原版靠 0.02/刻渐变');
  });

  test('③ 对着墙按 W（正对）：位置恒定不抽搐', () {
    final world = _World();
    // 墙：z∈[1,2] 一片（玩家正前方，yaw=π ⇒ forward=+Z），y=0..2。
    for (var x = 90; x <= 110; x++) {
      for (var y = 0; y <= 2; y++) {
        world.extra[(x, y, 1)] = VoxelShape.full();
      }
    }
    final player = Player(position: const Vec3(100.5, 0.0, -0.3));
    player.yaw = 3.141592653589793;
    final c = LocalPlayer(
      world: world,
      player: player,
      abilities: Abilities(mayfly: false),
    );
    final input = Input()..move.y = 1.0;
    _runTicks(c, input, 20); // 走到贴墙（z + float32(0.6)/2 = 1.0）
    // 贴面中心 = 墙面 − float32(0.6)/2 = 0.699999988079071
    // （EntityDimensions.java:20：float w = width / 2.0F）。
    expect(player.position.z + 0.30000001192092896, closeTo(1.0, 1e-15),
        reason: '精确贴面');

    final zStable = player.position.z;
    for (var i = 0; i < 120; i++) {
      _runTicks(c, input, 1);
      expect((player.position.z - zStable).abs(), lessThan(1e-9),
          reason: '第 $i 刻 z=${player.position.z}：对着墙按 W 振荡 = 抽搐');
    }
  });

  test('③b 贴墙斜向（前+朝墙分量）：沿墙滑行不被锁死', () {
    final world = _World();
    // 墙：x∈[2,3] 一列（玩家右侧），y=0..2；玩家沿 −Z 滑行。
    for (var z = -40; z <= 10; z++) {
      for (var y = 0; y <= 2; y++) {
        world.extra[(2, y, z)] = VoxelShape.full();
      }
    }
    final player = Player(position: const Vec3(1.7, 0.0, 5.0));
    final c = LocalPlayer(
      world: world,
      player: player,
      abilities: Abilities(mayfly: false),
    );
    // W（前 = −Z）+ D（右 = +X 朝墙）。
    final input = Input()
      ..move.y = 1.0
      ..move.x = 1.0;
    _runTicks(c, input, 20);
    for (var i = 0; i < 60; i++) {
      _runTicks(c, input, 1);
      // 不得穿墙。
      expect(player.position.x + 0.3, lessThanOrEqualTo(2.0 + 1e-9),
          reason: '第 $i 刻穿墙 x=${player.position.x}');
    }
    // 沿墙滑行了相当距离（60 刻 × ~0.2 ≈ 12 格），未锁死。
    expect(5.0 - player.position.z, greaterThan(6.0),
        reason: '贴墙滑行距离不足（锁死）: Δz=${5.0 - player.position.z}');
  });

  test('疾跑跳纵向助推 = 前进方向 ×0.2（LivingEntity.java:2378-2381）', () {
    final world = _World();
    final player = Player(position: const Vec3(100.5, 0.0, 100.5));
    player.yaw = 3.141592653589793; // forward = +Z
    final c = LocalPlayer(
      world: world,
      player: player,
      abilities: Abilities(mayfly: false),
    );
    final input = Input()
      ..move.y = 1.0
      ..sprint = true;
    _runTicks(c, input, 20); // 建立疾跑
    expect(c.isSprinting, isTrue);
    final vzBefore = player.velocity.z;
    input.jump = true;
    _runTicks(c, input, 1);
    input.jump = false;
    // 起跳那刻：注入 0.2 格/刻助推 + 落地前摩擦 0.91 ⇒ z 速度增幅 ≈ +3.64 格/秒。
    expect(player.velocity.z, greaterThan(vzBefore + 2.0),
        reason: 'z 速度 ${player.velocity.z} vs 起跳前 $vzBefore：疾跑跳助推缺失');
  });
}
