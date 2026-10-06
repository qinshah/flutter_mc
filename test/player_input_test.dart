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

  test('飞行竖直：原版注入×3.0 与 Player.travel 收尾×0.6 → 4.50 格/秒且无重力', () {
    final controller = PlayerController(
      world: EmptyWorld(),
      player: Player(),
      abilities: AbilitiesSnapshot(mayfly: true, flyingSpeed: 0.05),
    );
    controller.player.position.y = 100; // 远离世界底部（y<0 视为实心）
    final input = InputState();
    controller.flying = true;
    input.jump = true; // 升

    const dt = 1 / 120;
    for (var i = 0; i < 120; i++) {
      controller.tick(dt, input); // 1 秒 = 20 刻
    }
    expect(controller.player.velocity.y, closeTo(4.4997, 0.001));
    expect(controller.player.position.y - 100, closeTo(3.9375, 0.002));

    // 松手：原版 ×0.6/刻 衰减，很慢（60 子步→2.72e-2，360 子步→2.2e-13 格/秒）；
    // 且**无重力**——不回落（`Player.travel` 用 originalMovementY×0.6 覆盖了重力）。
    //
    // 注：这里不再手算"应当几刻"——刻累加器存在整刻相位偏移（见上方注释），
    // 子步数↔ 刻数不是稳定映射，故直接以实现实测值固化为回归黄金值。
    input.jump = false;
    final yAt1s = controller.player.position.y;
    for (var i = 0; i < 60; i++) {
      controller.tick(dt, input);
    }
    expect(controller.player.velocity.y.abs(), closeTo(2.7208e-2, 1e-5));
    for (var i = 0; i < 300; i++) {
      controller.tick(dt, input);
    }
    expect(controller.player.velocity.y.abs(), closeTo(2.1992e-13, 1e-15));
    expect(controller.player.position.y, greaterThan(yAt1s));
  });

  test('飞行水平：疾跑倍率生效（第1秒末 8.43 / 16.85 格/秒，比值≈2）', () {
    Vector3 afterOneSecond({required bool sprint}) {
      final controller = PlayerController(
        world: EmptyWorld(),
        player: Player(),
        abilities: AbilitiesSnapshot(mayfly: true, flyingSpeed: 0.05),
      );
      controller.player.position.y = 100;
      controller.flying = true;
      final input = InputState()
        ..move.y = 1 // 一直向前
        ..sprint = sprint;
      const dt = 1 / 120;
      for (var i = 0; i < 120; i++) {
        controller.tick(dt, input);
      }
      return controller.player.velocity;
    }

    final walk = afterOneSecond(sprint: false);
    final run = afterOneSecond(sprint: true);
    // yaw=0 时朝 −Z，故水平速度落在 z 分量。
    expect(walk.z.abs(), closeTo(8.4262, 0.002));
    expect(run.z.abs(), closeTo(16.8523, 0.002));
    // 疾跑≈2×：Player.getFlyingSpeed 的 isSprinting ? flyingSpeed*2 : flyingSpeed。
    expect(run.z.abs() / walk.z.abs(), closeTo(2.0, 0.01));

    // 无水平输入时按 ×0.91/刻 衰减（不清零）。
    final controller = PlayerController(
      world: EmptyWorld(),
      player: Player(),
      abilities: AbilitiesSnapshot(mayfly: true, flyingSpeed: 0.05),
    );
    controller.player.position.y = 100;
    controller.flying = true;
    final input = InputState()..move.y = 1;
    const dt = 1 / 120;
    for (var i = 0; i < 120; i++) {
      controller.tick(dt, input);
    }
    // 松手：×0.91/刻 衰减（120 子步→1.278，600 子步→6.76e-4 格/秒）——原版水平
    // 惯性衰减同样很慢，这是"贴墙飞"手感的关键：速度不清零、只是慢慢泄掉。
    input.move.y = 0;
    for (var i = 0; i < 120; i++) {
      controller.tick(dt, input);
    }
    expect(controller.player.velocity.z.abs(), closeTo(1.2778, 1e-3));
    for (var i = 0; i < 480; i++) {
      controller.tick(dt, input);
    }
    expect(controller.player.velocity.z.abs(), closeTo(6.7572e-4, 1e-7));
  });

  test('飞行：flyingSpeed 由服务器下发驱动（非硬编码 0.05）', () {
    final controller = PlayerController(
      world: EmptyWorld(),
      player: Player(),
      abilities: AbilitiesSnapshot(mayfly: true, flyingSpeed: 0.1),
    );
    controller.player.position.y = 100;
    controller.flying = true;
    final input = InputState()..jump = true;
    const dt = 1 / 120;
    for (var i = 0; i < 120; i++) {
      controller.tick(dt, input);
    }
    // flyingSpeed 加倍 ⇒竖直终速也加倍（原版竖直同样吃 abilities.getFlyingSpeed）。
    expect(controller.player.velocity.y, closeTo(9.0, 0.05));
  });
}
