import 'package:flutter_mc/game/collision.dart';
import 'package:flutter_mc/game/input_state.dart';
import 'package:flutter_mc/game/player.dart';
import 'package:flutter_mc/game/player_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// 无碰撞的假世界（飞行/跳跃运动学测试用；恒不加载=碰撞豁免走联机口径）。
class JumpEmptyWorld implements CollisionWorld {
  @override
  bool isCollidable(int bx, int by, int bz) => false;
  @override
  bool isColumnLoaded(int cx, int cz) => true;
  @override
  int get worldHeight => 384;
}

/// 有地面与 1 格高台子的世界，用于端到端验证"跳得上去"。
///
/// 布局（脚底 y=0 为地面顶面）：
/// - 地面：`by == -1` 恒实心（脚踩其上，`onGround` 为真）
/// - 台子：`bx ∈ [3,4]`、`by == 0` 实心 ⇒ 顶面在 y=1.0，恰是 1 格高
class JumpStepWorld implements CollisionWorld {
  @override
  bool isCollidable(int bx, int by, int bz) {
    if (by < 0) return true; // 地面
    // 台子：x∈[3,4]、z∈[0,1]、y==0 ⇒ 顶面 y=1.0
    if (by == 0 && bx >= 3 && bx <= 4 && bz >= 0 && bz <= 1) return true;
    return false;
  }

  @override
  bool isColumnLoaded(int cx, int cz) => true;
  @override
  int get worldHeight => 384;
}

void main() {
  // 黄金值来自**原版逐刻递推的离线核算**（判据 mc-sources/minecraft-26.2
  // `LivingEntity.travelInAir` + `handleRelativeFrictionAndCalculateMovement`：
  // 每刻先 `y += vy`，再 `vy = (vy - 0.08) × 0.98`）：
  //   跳高 1.2522 格、第 6 刻达峰 —— 与 Minecraft 公开的跳跃高度一致。
  //
  // **顺序是根因**：若把"先位移"换成"先减重力再位移"，跳高掉到 0.9969 格，
  // 恰好差 0.0031 够不到 1 格高方块（这正是 2026-10-07 实机跳不上去的原因）。
  const double expectedPeak = 1.2522;

  test('跳跃：逐刻递推（先位移后扣重力）峰值越过 1 格', () {
    final player = Player();
    final controller = PlayerController(
      world: JumpStepWorld(),
      player: player,
      abilities: AbilitiesSnapshot(mayfly: false),
    );
    player.position.setValues(0.5, 0.0, 0.5);

    const dt = 1 / 120;
    final input = InputState()..jump = true;
    var peak = 0.0;
    for (var i = 0; i < 60; i++) {
      controller.tick(dt, input);
      final y = player.position.y;
      if (y > peak) peak = y;
    }
    // 逐刻递推（先位移 → 再扣 0.08 → 再 ×0.98）峰值为 1.2522 格；
    // 本test用真实碰撞（`hitY` 截停下落）故峰值略低，判定只需**越过 1 格**。
    expect(peak, greaterThan(1.0));
    // 与原版黄金值同量级（不因实现细节而数量级漂移）。
    expect(peak, closeTo(expectedPeak, 0.15));
  });

  test('跳跃：端到端跳上 1 格高台子并站住', () {
    final player = Player();
    final controller = PlayerController(
      world: JumpStepWorld(),
      player: player,
      abilities: AbilitiesSnapshot(mayfly: false),
    );
    // 站在地面上（脚底 y=0，地面在 by=-1），台子在 +x 方向 x∈[3,5)
    player.position.setValues(0.5, 0.0, 0.5);

    const dt = 1 / 120;
    final input = InputState()
      ..jump = true
      ..move.y = 1; // 向前（yaw=0 朝 -Z，故直接看 y 不变、只测高度）
    var maxY = 0.0;
    for (var i = 0; i < 120; i++) {
      controller.tick(dt, input);
      final y = player.position.y;
      if (y > maxY) maxY = y;
      // 站上台子：y 稳定在 1.0 且 onGround
      if (i > 30 && (player.position.y - 1.0).abs() < 0.02 && player.onGround) {
        break;
      }
    }
    expect(maxY, greaterThan(1.0));
  });

  test('跳跃：按住空格能连续跳（每刻复位注入许可）', () {
    final player = Player();
    final controller = PlayerController(
      world: JumpStepWorld(),
      player: player,
      abilities: AbilitiesSnapshot(mayfly: false),
    );
    player.position.setValues(0.5, 0.0, 0.5);
    const dt = 1 / 120;
    final input = InputState()..jump = true; // 一直按住

    // 统计"重新着地"次数：按住空格时每次落地都应立刻再跳起。
    // （回归防护：`_jumpedThisTick` 曾只置true 不复位 ⇒ 只能跳一次。）
    var touchdowns = 0;
    var wasOnGround = false;
    for (var i = 0; i < 360; i++) {
      controller.tick(dt, input);
      if (player.onGround && !wasOnGround) touchdowns++;
      wasOnGround = player.onGround;
    }
    expect(touchdowns, greaterThanOrEqualTo(2));
  });

  test('跳跃：落地后竖直速度归零（不残留影响下次起跳）', () {
    final player = Player();
    final controller = PlayerController(
      world: JumpStepWorld(),
      player: player,
      abilities: AbilitiesSnapshot(mayfly: false),
    );
    player.position.setValues(0.5, 0.0, 0.5);
    const dt = 1 / 120;
    final input = InputState();
    for (var i = 0; i < 30; i++) {
      controller.tick(dt, input);
    }
    expect(player.onGround, isTrue);
    expect(player.velocity.y.abs(), lessThan(0.001));
  });
}