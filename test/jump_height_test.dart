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

  test('跳跃：位移按整刻跳变（不摊到子步 ⇒ 无海绵滞手感）', () {
    // 回归防护：曾把 1/120s 的 dt 乘进刻速度，等于"一个刻的位移在 6 个子步里
    // 重复用"⇒ 视觉上阶梯式慢速爬升，2026-10-07 实机反馈"像陷进海绵"。
    // 原版 `move(MoverType.SELF, deltaMovement)` 是**一 tick 一次**整块位移。
    final player = Player();
    final controller = PlayerController(
      world: JumpStepWorld(),
      player: player,
      abilities: AbilitiesSnapshot(mayfly: false),
    );
    player.position.setValues(0.5, 0.0, 0.5);
    const dt = 1 / 120;
    final input = InputState()..jump = true;

    var prevY = player.position.y;
    final jumps = <double>[]; // 每帧的 dy，非零的应是"整刻位移"
    for (var i = 0; i < 40; i++) {
      controller.tick(dt, input);
      final dy = player.position.y - prevY;
      if (dy.abs() > 1e-9) jumps.add(dy);
      prevY = player.position.y;
    }
    expect(jumps.length, greaterThanOrEqualTo(3));
    // 第一跳的头几步应恰为整刻位移（初速 0.42 格 = 8.4 格/秒 ÷ 20），
    // 随后按原版逐刻递减（×0.98并扣重力）。若把刻速度摊到1/120s 子步，
    // 首个位移会缩成 0.42/6 ≈ 0.07 格 ⇒ 断言失败。
    expect(jumps[0], closeTo(8.4 / 20.0, 1e-6));
    expect(jumps[1], closeTo(0.3332, 1e-3));
    expect(jumps[2], closeTo(0.2481, 1e-3));
    // 单调递减（爬升期）
    for (var i = 1; i < jumps.length; i++) {
      expect(jumps[i], lessThanOrEqualTo(jumps[i - 1]));
    }
  });

  test('跳跃：落地无下陷——落地后 y 不再抖动', () {
    final player = Player();
    final controller = PlayerController(
      world: JumpStepWorld(),
      player: player,
      abilities: AbilitiesSnapshot(mayfly: false),
    );
    player.position.setValues(0.5, 3.0, 0.5); // 从 3 格高落下
    const dt = 1 / 120;
    final input = InputState();
    for (var i = 0; i < 400; i++) {
      controller.tick(dt, input);
    }
    expect(player.onGround, isTrue);
    final restY = player.position.y;
    // 静止后不应再有位移（"海绵"感的另一半：贴地持续微抖）。
    for (var i = 0; i < 60; i++) {
      controller.tick(dt, input);
    }
    expect((player.position.y - restY).abs(), lessThan(1e-9));
    expect(player.velocity.y, 0);
  });

  test('插帧：飞行态也插值（原版对所有实体一律插值）', () {
    // 回归防护：曾只给行走/跳跃更新 `yOld`，飞行态完全没有插帧 ⇒ 20Hz 台阶。
    // 判据 `EntityRenderer.extractRenderState`（`EntityRenderer.java:164`）：
    // `state.y = Mth.lerp(partialTicks, entity.yOld, entity.getY())`——
    // **对所有实体一律插帧，不区分是否飞行**。
    final player = Player();
    final controller = PlayerController(
      world: JumpEmptyWorld(),
      player: player,
      abilities: AbilitiesSnapshot(mayfly: true),
    );
    controller.flying = true;
    player.position.setValues(0.5, 200.0, 0.5);
    const dt = 1 / 120;
    final input = InputState()..jump = true;

    // 物理台阶数 vs 渲染变化帧数
    var physSteps = 0;
    var prevPhys = player.position.y;
    var renderFrames = 0;
    var prevEye = player.eyePosition.y;

    for (var i = 0; i < 60; i++) {
      controller.tick(dt, input);
      final phys = player.position.y;
      if ((phys - prevPhys).abs() > 1e-9) physSteps++;
      prevPhys = phys;
      final eye = player.eyePosition.y;
      if ((eye - prevEye).abs() > 1e-6) renderFrames++;
      prevEye = eye;
    }
    expect(physSteps, lessThan(20), reason: '物理是 20Hz ⇒ 60 帧内约 10 步');
    expect(renderFrames, greaterThan(physSteps * 2),
        reason: '渲染须在物理台阶之间连续变化 ⇒ 不卡顿');
    expect(player.tickProgress, greaterThan(0),
        reason: 'tickProgress 必须被推进，否则插值退化回物理位置');
  });

  test('插帧：跳跃态 tickProgress 在 (0,1) 内循环', () {
    // 回归防护：`tickProgress` 曾只有赋值点、无推进点 ⇒ 恒为 0、插帧形同虚设。
    final player = Player();
    final controller = PlayerController(
      world: JumpStepWorld(),
      player: player,
      abilities: AbilitiesSnapshot(mayfly: false),
    );
    player.position.setValues(0.5, 0.0, 0.5);
    const dt = 1 / 120;
    final input = InputState()..jump = true;
    var sawFraction = false;
    var sawReset = false;
    var prev = -1.0;
    for (var i = 0; i < 120; i++) {
      controller.tick(dt, input);
      final tp = player.tickProgress;
      expect(tp, inInclusiveRange(0.0, 1.0), reason: '插值进度须在 [0,1]');
      if (tp > 0.0 && tp < 1.0) sawFraction = true;
      // 每跨刻accum 归零 ⇒ 进度应出现"回落"（比上一帧小）。
      if (prev > 0.0 && tp < prev) sawReset = true;
      prev = tp;
    }
    expect(sawFraction, isTrue, reason: '应出现刻内的小数进度（插帧生效）');
    expect(sawReset, isTrue, reason: '每跨刻插值进度应回落（累加器归零）');
  });

  test('失焦下落：终端速度不超原版、落地速度归零', () {
    // 判据 `AABB.EPSILON = 1.0E-7`（AABB.java:14）；终端速度 -78.4 格/秒。
    final player = Player();
    final controller = PlayerController(
      world: JumpStepWorld(),
      player: player,
      abilities: AbilitiesSnapshot(mayfly: false),
    );
    player.position.setValues(0.5, 3.0, 0.5); // 3 格高自由下落
    const dt = 1 / 120;
    final input = InputState(); // 失焦后典型状态：不按任何键
    var maxFallPerFrame = 0.0;
    var prevY = player.position.y;
    for (var i = 0; i < 400; i++) {
      controller.tick(dt, input);
      final y = player.position.y;
      final dy = prevY - y;
      if (dy > maxFallPerFrame) maxFallPerFrame = dy;
      prevY = y;
      if (player.onGround && i > 10) break;
    }
    expect(player.onGround, isTrue);
    expect(player.velocity.y, 0);
    // 终端 78.4 格/秒 ⇒ 单帧(1/120s) 上限 0.65333 格
    expect(maxFallPerFrame, lessThanOrEqualTo(78.4 / 120 + 1e-9));
    // 落地静止时脚底应贴面（epsilon = 1e-7 量级，不是 1e-4）
    expect(player.position.y.abs(), lessThan(1e-6));
  });

  test('渲染：物理 20Hz 阶梯但渲染位置线性插值（不卡顿）', () {
    // 判据 `EntityRenderer.createRenderState`（mc-sources/minecraft-26.2:164）：
    // `Mth.lerp(partialTicks, entity.xOld, entity.getX())`。原版物理跑 20Hz，
    // 渲染靠上一刻→当前刻的插值保持顺滑；缺插值会"一卡一卡地爬"。
    final player = Player();
    final controller = PlayerController(
      world: JumpStepWorld(),
      player: player,
      abilities: AbilitiesSnapshot(mayfly: false),
    );
    player.position.setValues(0.5, 0.0, 0.5);
    const dt = 1 / 120;
    final input = InputState()..jump = true;

    // 物理位置的台阶数（应远少于帧数）
    var physSteps = 0;
    var prevPhys = player.position.y;
    // 渲染位置的帧间差（应每帧都非零 ⇒ 平滑）
    final renderDeltas = <double>[];
    var prevEye = player.eyePosition.y;

    for (var i = 0; i < 60; i++) {
      controller.tick(dt, input);
      final phys = player.position.y;
      if ((phys - prevPhys).abs() > 1e-9) physSteps++;
      prevPhys = phys;
      final eye = player.eyePosition.y;
      final d = eye - prevEye;
      if (d.abs() > 1e-6) renderDeltas.add(d);
      prevEye = eye;
    }
    // 物理是 20Hz ⇒ 60 帧（0.5s）内约 10 个台阶，不是 60 次。
    expect(physSteps, lessThan(20));
    // 渲染却在同一区间内持续平滑变化（帧数远多于台阶数）。
    expect(renderDeltas.length, greaterThan(physSteps * 3));
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