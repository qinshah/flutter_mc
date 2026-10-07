import 'dart:math' as pi_lib;
import 'package:flutter_mc/game/collision.dart';
import 'package:flutter_mc/game/input_state.dart';
import 'package:flutter_mc/game/player.dart';
import 'package:flutter_mc/game/player_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// 无碰撞的假世界（飞行运动学测试用；恒不加载=碰撞豁免走联机口径）。
class EmptyWorld implements CollisionWorld {
  @override
  bool isCollidable(int bx, int by, int bz) => false;
  @override
  bool isColumnLoaded(int cx, int cz) => true;
  @override
  int get worldHeight => 384;
}

/// 飞行 1 秒后的**竖直位移**（含首帧相位，与真实 tick 驱动一致）。
///
/// 判据黄金值见下方测试：逐字翻译 `Player.travel` + `LivingEntity` 得
/// 6.5625 格/秒（原版创造飞行确实很慢，别按"看起来不对"去调）。
double _flyFor(void Function(InputState) setup, {double flyingSpeed = 0.05}) {
  final controller = PlayerController(
    world: EmptyWorld(),
    player: Player(),
    abilities: AbilitiesSnapshot(mayfly: true, flyingSpeed: flyingSpeed),
  );
  controller.player.position.y = 100;
  controller.flying = true;
  final input = InputState();
  setup(input);
  const dt = 1 / 120;
  for (var i = 0; i < 120; i++) {
    controller.tick(dt, input);
  }
  return controller.player.position.y - 100;
}

/// 飞行 1 秒后的**水平位移**（yaw=0 时落在 −Z 分量）。
double _flyForHorizontal(void Function(InputState) setup, {double flyingSpeed = 0.05}) {
  final controller = PlayerController(
    world: EmptyWorld(),
    player: Player(),
    abilities: AbilitiesSnapshot(mayfly: true, flyingSpeed: flyingSpeed),
  );
  controller.player.position.y = 100;
  controller.flying = true;
  final input = InputState();
  setup(input);
  const dt = 1 / 120;
  for (var i = 0; i < 120; i++) {
    controller.tick(dt, input);
  }
  return controller.player.position.z;
}

void main() {
  test('视角：原版公式（灵敏度 0.5，10px → 1.5°）', () {
    final player = Player();
    player.applyLook(Vector2(10, 20), sensitivity: 0.5);
    const degToRad = pi_lib.pi / 180.0;
    expect(player.yaw, closeTo(-1.5 * degToRad, 1e-9));
    expect(player.pitch, closeTo(3.0 * degToRad, 1e-9)); // 20px
    // pitch 钳制 ±90°。
    player.applyLook(Vector2(0, 10000), sensitivity: 0.5);
    expect(player.pitch, closeTo(pi_lib.pi / 2 - 0.0018, 1e-6));
  });

  test('双击空格：窗口内第二按切换飞行并回调；mayfly=false 不切换', () {
    final toggles = <bool>[];
    final controller = PlayerController(
      world: EmptyWorld(),
      player: Player(),
      abilities: AbilitiesSnapshot(mayfly: true, flyingSpeed: 0.05),
      onFlyingToggled: toggles.add,
    );
    final input = InputState();
    const dt = 1 / 120;

    // 第一按（1 步）→ 进窗口。
    input.jump = true;
    controller.tick(dt, input);
    input.jump = false;
    controller.tick(dt, input);
    expect(controller.flying, isFalse);
    expect(toggles, isEmpty);

    // 窗口内（<0.35s）第二按 → 切飞行。
    for (var i = 0; i < 10; i++) {
      controller.tick(dt, input);
    }
    input.jump = true;
    controller.tick(dt, input);
    expect(controller.flying, isTrue);
    expect(toggles, [true]);

    // 第三按（窗口已重置）不切换。
    input.jump = false;
    for (var i = 0; i < 10; i++) {
      controller.tick(dt, input);
    }
    input.jump = true;
    controller.tick(dt, input);
    expect(controller.flying, isTrue);
    expect(toggles, [true]);
  });

  test('mayfly=false：双击无效', () {
    var called = false;
    final controller = PlayerController(
      world: EmptyWorld(),
      player: Player(),
      abilities: AbilitiesSnapshot(mayfly: false),
      onFlyingToggled: (_) => called = true,
    );
    final input = InputState();
    const dt = 1 / 120;
    input.jump = true;
    controller.tick(dt, input);
    input.jump = false;
    for (var i = 0; i < 10; i++) {
      controller.tick(dt, input);
    }
    input.jump = true;
    controller.tick(dt, input);
    expect(controller.flying, isFalse);
    expect(called, isFalse);
  });

  // 黄金值全部由原版逐刻递推离线算出（判据 mc-sources/minecraft-26.2）：
  //   竖直 v=(v+0.15)*0.6  ← LocalPlayer.aiStep 注入 ×3.0 + Player.travel 收尾 ×0.6
  //   水平 v=(v+0.05)*0.91 ← travelInAir 空中分支摩擦 1.0×0.91（疾跑时 0.10）
  //
  // **为什么是 19 刻而不是 20 刻**：刻累加器每子步累加 `dt×20 = 1/6`，浮点上
  // 120 次累加得19.999999999999996 < 20 ⇒ 第 1 秒末只触发 19 刻（残余 1.0 会
  // 在下一子步立刻补上，故长期速率仍精确 20 刻/秒，只是相位差一刻）。
  // 理论终速：竖直 4.5 格/秒、水平 10.11（疾跑 20.22），1 秒尚未收敛到终速。

  test('飞行竖直：逐字翻译 Player.travel → 上下严格对称、6.5625 格/秒', () {
    // 判据 mc-sources/minecraft-26.2，逐字翻译（顺序不可换）：
    //   LivingEntity:2656  moveRelative(getFrictionInfluencedSpeed) —— δ + input×flySpeed
    //   LivingEntity:2658  move(MoverType.SELF, deltaMovement)   —— 位移用**注入值**
    //   Player:1398setDeltaMovement(y = originalMovementY × 0.6)
    //
    // **收尾的 ×0.6 覆盖 travelInAir 的扣重力结果**（不是相乘、也不是 max）。
    // 原版离线递推黄金值（1 秒 = 20 刻，含首帧相位）：上升 +6.5625 / 下降 -6.5625。
    // **竖直与水平来源不同**（2026-10-07 用户反馈"慢得像蜗牛"后查实）：
    // - 竖直：`inputYa * abilities.getFlyingSpeed() * 3.0F`（`LocalPlayer.java:844`）
    //   = 0.15 格/刻 —— 这是**客户端本地预测**的独立一段，在 `super.aiStep()`
    //   之前跑，不经过 `getInputVector`。
    // - 水平：`getFlyingSpeed() = abilities.flyingSpeed`（`Player.java:1952-1958`）
    //   = 0.05 格/刻（疾跑 ×2），经 `moveRelative` 注入。
    final up = _flyFor((i) => i.jump = true);
    final down = _flyFor((i) => i.sneak = true);
    expect(up, closeTo(6.5625, 1e-3));
    expect(down, closeTo(-6.5625, 1e-3));
    // **上下严格对称**——这是用户实机反馈的问题（"上升和下降速度不一样"）。
    expect(up, closeTo(-down, 1e-6));

    // 松手：不再注入，vy 按 ×0.6 指数衰减 ⇒ 原地悬停（无重力，原版如此）。
    // `Player.travel` 的 ×0.6 覆盖了 travelInAir 的扣重力，故不会自由落体。
    final idle = _flyFor((i) {});
    expect(idle.abs(), lessThan(1e-6));
  });

  test('飞行水平：getFlyingSpeed=abilities.flyingSpeed（疾跑×2）→ 5.8744 格/秒', () {
    // 判据 `Player.java:1952-1958`：
    //   isSprinting() ? abilities.getFlyingSpeed() * 2.0F : abilities.getFlyingSpeed();
    // 注入 0.05（疾跑 0.10）→ move 用未衰减值 → × airDrag 0.91
    // （`LivingEntity.travelInAir` 空中分支 2474）。
    // 原版离线递推黄金值（1 秒 = 19 刻相位，尚未收敛到终速）：5.8744 格。
    // 终速 0.05×0.91/0.09 = 0.5056 格/刻 = 10.11 格/秒（疾跑 20.22）。
    // yaw=0 时前方向是 −Z，故位移为负。
    final walk = _flyForHorizontal((i) => i.move.y = 1);
    expect(walk, closeTo(-5.8744, 1e-3));

    // **疾跑 ×2**——判据 `Player.java:1954`（被 Player 覆盖，基类 LivingEntity:2707
    // 的 getSpeed()×0.1 是载具分支，不要抄它——早先错抄导致飞行比行走还慢）。
    final run = _flyForHorizontal((i) { i.move.y = 1; i.sprintToggle = true; });
    expect(run, closeTo(-11.7487, 1e-3),
        reason: '判据：飞行疾跑 ×2（Player.java:1954）');

    // 松手：airDrag ×0.91/刻 衰减，速度不清零（原版惯性）。
    final idle = _flyForHorizontal((i) {});
    expect(idle.abs(), lessThan(1e-6),
        reason: '松手后 airDrag 指数衰减到0（不清零是原版惯性，但会趋 0）');
  });

  test('飞行：abilities.flyingSpeed 同时驱动水平与竖直', () {
    // 判据（2026-10-07 查实，推翻早先"水平不读它"的判断）：
    // - 竖直：`LocalPlayer.java:844` `inputYa * abilities.getFlyingSpeed() * 3.0F`
    //   ⇒ 读 `Abilities.flyingSpeed`（默认 0.05）。
    // - 水平：`Player.java:1952-1958` `getFlyingSpeed()` = `abilities.flyingSpeed`
    //   ⇒ 读 `Abilities.flyingSpeed`（疾跑 ×2）。
    final fast = PlayerController(
      world: EmptyWorld(),
      player: Player(),
      abilities: AbilitiesSnapshot(mayfly: true, flyingSpeed: 0.1),
    );
    fast.player.position.y = 100;
    fast.flying = true;
    final normal = PlayerController(
      world: EmptyWorld(),
      player: Player(),
      abilities: AbilitiesSnapshot(mayfly: true, flyingSpeed: 0.05),
    );
    normal.player.position.y = 100;
    normal.flying = true;

    // 竖直：flyingSpeed 加倍 ⇒ 位移加倍。
    final vFast = _flyFor((c) { c.jump = true; }, flyingSpeed: 0.1);
    final vNormal = _flyFor((c) { c.jump = true; }, flyingSpeed: 0.05);
    expect(vFast, closeTo(vNormal * 2, 1e-3),
        reason: '判据：竖直注入 ∝ abilities.flyingSpeed');

    // 水平：flyingSpeed 加倍 ⇒ 位移加倍。
    final hFast = _flyForHorizontal((c) { c.move.y = 1; }, flyingSpeed: 0.1);
    final hNormal = _flyForHorizontal((c) { c.move.y = 1; }, flyingSpeed: 0.05);
    expect(hFast, closeTo(hNormal * 2, 1e-3),
        reason: '判据：水平 getFlyingSpeed() = abilities.flyingSpeed');
  });
}
