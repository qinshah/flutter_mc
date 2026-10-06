import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'collision.dart';
import 'input_state.dart';
import 'player.dart';

/// 玩家运动学常量（原版**每刻值**换算到每秒；判据 `mc-sources/minecraft-26.2`）。
///
/// - 重力 0.08 /刻 —— `Attributes.GRAVITY` 默认值（Attributes.java:56）→ ×400 = 32 block/s²
/// - 跳跃初速 0.42 /刻 —— `Attributes.JUMP_STRENGTH` 默认值（Attributes.java:59），
///   同值亦见 `LivingEntity.BASE_JUMP_POWER`（LivingEntity.java:172）→ ×20 = 8.4 block/s
/// - 空气阻力 0.98 /刻 —— `Entity.getAirDrag()`（Entity.java:1536）
/// - 终端速度 —— 0.08 / (1 − 0.98) = 3.92 block/刻 → 78.4 block/s
/// - 行走/疾跑/潜行 —— 4.317 / 5.612 / 1.295 block/s（`Player.createAttributes()` 的
///   `MOVEMENT_SPEED` 0.1，Player.java:209，配地面摩擦的稳态速度）
class PlayerMotion {
  static const double gravity = 32.0;
  static const double jumpVelocity = 8.4;
  static const double terminalVelocity = -78.4;

  /// 每刻空气阻力 → 连续阻尼系数：`k = -ln(0.98) × 20 ≈ 0.404 /s`。
  static const double airDragPerTick = 0.98;

  static const double walkSpeed = 4.317;
  static const double sprintSpeed = 5.612;
  static const double sneakSpeed = 1.295;

  /// 创造飞行·水平摩擦（REF: `LivingEntity.travelInAir` 空中分支：
  /// `blockFriction = 1.0` × `airDrag = 0.91`）。
  static const double flyFriction = 0.91;

  /// 创造飞行·竖直速度保留系数（REF: `Player.travel` 飞行分支的
  /// `originalMovementY * 0.6`——它覆盖 `travelInAir` 的重力与竖直摩擦，故无重力）。
  static const double flyVerticalRetain = 0.6;

  // —— 行走/跳跃的竖直运动学（REF: `LivingEntity.travelInAir` 空中分支）——
  //
  // **逐刻递推**（格/刻，20 刻/秒）。原版一**刻**内的顺序是关键：
  //   1. `jumpFromGround()`：vy = Math.max(jumpPower, vy)          [源码 2370]
  //   2. `handleRelativeFrictionAndCalculateMovement`：**先 move() 位移**
  //      （源码 2657），用的还是**未扣重力**的 vy
  //   3. `travelInAir`：movementY -= getEffectiveGravity()        （源码 2460）
  //   4. `setDeltaMovement(... * verticalFriction)` = ×0.98（源码 2474）
  //
  // **顺序不能换**：先减重力再位移会让每刻都吃一次重力，累积后跳高从 1.2522 格
  // 掉到 0.9969 格——恰好差 0.0031 够不到 1 格高方块（2026-10-07 实测）。
  // 阻尼模型（×0.98/tick）与连续化 exp(-k·dt) 每子步只差 ~1e-6，不是根因。
  /// 每刻重力（`Attributes.GRAVITY` 默认值）。**单位是"格/刻²"**，
  /// 即每刻把竖直速度减 0.08 格/刻（= 1.6 格/秒²，与 [gravity] 同源不同口径）。
  static const double gravityPerTick = 0.08;

  /// 每刻竖直空气阻力（`travelInAir` 的 `verticalFriction`，非 omnidirectional 时）。
  static const double verticalFrictionPerTick = 0.98;

  /// 每刻时长（秒）。
  static const double tickSeconds = 1.0 / 20.0;

  /// 固定步长（照 fscraft）：渲染帧率变化不影响物理结果。
  static const double fixedStep = 1 / 120;

  /// 单帧最多补算步数（防"卡顿一下补算几百步"造成瞬移）。
  static const int maxStepsPerFrame = 12;

  static final double airDamping = -math.log(airDragPerTick) * 20.0;
}

/// 玩家控制器：读 [InputState] → 重力/跳跃 → 碰撞求解 → 写 [Player]。
///
/// **纯逻辑**：不 import Flutter / flutter_scene，所以运动学可以完整单测
/// （引擎侧的按键与节点变换在 app 壳的 `game_screen.dart` 里接）。
///
/// 简化点（标注）：水平方向按输入**直接赋值目标速度**（无加速/摩擦惯性）——
/// 原版 `LivingEntity.travel` 的加速度与地面摩擦链（0.91 摩擦）留作后续切片。
/// 竖直方向照原版**逐刻**语义（先减重力、再乘空气阻力），故终端速度与原版一致。
class PlayerController {
  PlayerController({
    required this.world,
    required this.player,
    VoxelCollision? collision,
    this.abilities,
    this.onFlyingToggled,
  }) : collision = collision ?? VoxelCollision(world);

  final CollisionWorld world;
  final Player player;
  final VoxelCollision collision;

  /// 服务器权威 abilities（mayfly/flyingSpeed）；null=未知（按不可飞处理）。
  final AbilitiesSnapshot? abilities;

  /// 双击空格切换飞行后回调（app 壳 → session.sendAbilities 上报）。
  final void Function(bool flying)? onFlyingToggled;

  // —— 双击空格窗口（REF: LocalPlayer.aiStep：jumpTriggerTime=7 刻 = 0.35s）——
  bool _wasJumping = false;
  double _jumpTriggerSeconds = 0;

  /// 创造飞行（本地意图；可行性以 [abilities] 的 mayfly 为准）。
  bool flying = false;

  double _accumulator = 0;

  /// 竖直刻速度（`格/刻`）。对外的 [Player.velocity]（格/秒）由它 ×20 换算。
  double _vyTicks = 0;

  /// 距下一个刻边界的时间（秒）。竖直运动学只在此边界推进。
  double _verticalTickAccum = 0;

  /// 本刻是否已起跳（原版 `noJumpDelay = 10` 的轻量替身：防止按住空格
  /// 在一个刻内重复注入初速；原版是 10 刻冷却，本期只保证"每刻至多一次"）。
  bool _jumpedThisTick = false;

  /// 用一帧的真实 `dt` 驱动：内部按 [PlayerMotion.fixedStep] 固定步长累加。
  void tick(double dt, InputState input) {
    // 视角**每帧只应用一次**：`lookDelta` 是"这一帧转了多少"，若放进固定步长
    // 会让灵敏度随帧率浮动。
    if (input.lookDelta.x != 0 || input.lookDelta.y != 0) {
      player.applyLook(input.lookDelta);
    }

    _accumulator +=
        dt.clamp(0.0, PlayerMotion.fixedStep * PlayerMotion.maxStepsPerFrame);
    var steps = 0;
    while (_accumulator >= PlayerMotion.fixedStep &&
        steps < PlayerMotion.maxStepsPerFrame) {
      _step(PlayerMotion.fixedStep, input);
      _accumulator -= PlayerMotion.fixedStep;
      steps++;
    }
    if (steps == PlayerMotion.maxStepsPerFrame) _accumulator = 0;
  }

  /// 一个固定步长的物理推进。
  void _step(double dt, InputState input) {
    // —— 双击空格切飞行（REF: LocalPlayer.aiStep，jumpTriggerTime=7 刻）——
    final mayfly = abilities?.mayfly ?? false;
    if (mayfly) {
      if (!_wasJumping && input.jump) {
        if (_jumpTriggerSeconds <= 0) {
          _jumpTriggerSeconds = 0.35;
        } else {
          flying = !flying;
          onFlyingToggled?.call(flying);
          if (flying && player.onGround) {
            // 原版 `jumpFromGround()`：注入 0.42 格/刻，随后同样被 `Player.travel`
            // 的 ×0.6 收尾——直接写 player.velocity 会被下一步覆盖，故加在刻速度上。
            _flyVelocity.y += PlayerMotion.jumpVelocity / 20.0;
          }
          _jumpTriggerSeconds = 0;
        }
      }
    }
    _wasJumping = input.jump;
    if (_jumpTriggerSeconds > 0) _jumpTriggerSeconds -= dt;

    if (flying && mayfly) {
      _flyingStep(dt, input);
      return;
    }

    // —— 水平：输入是玩家本地坐标（y 前、x 右），按 yaw 转到世界系 ——
    final speed = input.sneak
        ? PlayerMotion.sneakSpeed
        : input.sprint
            ? PlayerMotion.sprintSpeed
            : PlayerMotion.walkSpeed;
    if (input.isMoving) {
      final forward = Vector3(-math.sin(player.yaw), 0, -math.cos(player.yaw));
      final right = Vector3(math.cos(player.yaw), 0, -math.sin(player.yaw));
      final desired = forward * input.move.y + right * input.move.x;
      final len = desired.length;
      if (len > 0) {
        final dir = desired / len;
        player.velocity.x = dir.x * speed;
        player.velocity.z = dir.z * speed;
      }
    } else {
      player.velocity.x = 0;
      player.velocity.z = 0;
    }

    // —— 竖直：刻边界递推（REF 见PlayerMotion 处的时序注释）——
    //
    // 碰撞求解在 1/120s 固定步内跑（细步长防穿墙），但**竖直运动学只在刻边界推进**
    // —— 否则每子步都吃一次重力，累积后跳高从1.2522 掉到 0.9969 格（跳不上 1 格）。
    // `_pendingVerticalSteps` 记录"到下一个刻边界还剩几格竖直要积分"。
    final jumpPower =
        PlayerMotion.jumpVelocity; // 格/秒（= 0.42 格/刻 × 20）
    if (input.jump && player.onGround && !_jumpedThisTick) {
      // `jumpFromGround()`：`Math.max(jumpPower, movement.y)`（源码 2372）——
      // 注入取较大者，MUST NOT 把已有的上升速度改小。
      final vyTicks = _vyTicks > 0 ? _vyTicks : jumpPower / 20.0;
      _vyTicks = vyTicks;
      _jumpedThisTick = true;
      player.onGround = false;
    }

    _verticalTickAccum += dt;
    while (_verticalTickAccum >= PlayerMotion.tickSeconds) {
      _verticalTickAccum -= PlayerMotion.tickSeconds;
      _advanceVerticalTick(jumpPower);
    }

    // —— 位移与碰撞 ——（`VoxelCollision.move` 内部已按最长轴拆子步）
    // 竖直位移用**本刻未扣重力**的刻速度 `_vyTicks`（原版 `move()` 在
    // `travelInAir` 扣重力之前调用，见 handleRelativeFrictionAndCalculateMovement）。
    final result = collision.move(
      player.bounds,
      player.velocity.x * dt,
      _vyTicks * 20.0 * dt,
      player.velocity.z * dt,
    );
    // 被挡的轴速度清零（贴墙滑动由 collision 的逐轴求解保证）。
    if (result.hitX) player.velocity.x = 0;
    if (result.hitZ) player.velocity.z = 0;

    player.applyMove(result);
    if (result.hitY) {
      // 撞到顶面 ⇒ 竖直刻速度归零（原版 `move()` 拦住位移后不再积累下落速度）。
      _vyTicks = 0;
      player.velocity.y = 0;
    }
    // **着地判定用"脚下探针"而非 `hitY`**：`collision.move` 的 `hitY` 只在
    // `dy < 0`（真的下沉）时才为真，站着不动 `dy == 0` ⇒ 永远撞不到 ⇒
    // `onGround` 会在 true/false 间闪烁。`hasBlockBelow` 是独立探针（原版
    // `Entity.groundState` 同义），站立不动时依然为真——这才是正确的口径。
    final grounded = result.hasBlockBelow && _vyTicks <= 0;
    if (grounded) {
      // 稳定着地：竖直速度归零，避免残留 vy 影响下次起跳。
      _vyTicks = 0;
      player.velocity.y = 0;
    }
    player.onGround = grounded;
  }

  /// 推进一个刻的竖直运动学（REF 见 [PlayerMotion] 的时序注释）。
  ///
  /// 顺序严格照原版：**先按当前速度积分位置，再扣重力、乘阻力**。
  /// 反过来做会让跳高掉到 0.9969 格（跳不上 1 格高方块）。
  void _advanceVerticalTick(double jumpPower) {
    // ① 位移（由调用方在固定步内用 `_vyTicks` 积分进位置）；
    //    这里只更新速度——位置积分在 `_step` 的 collision.move 里按 dt 摊还。
    // ② 扣重力（`travelInAir`：movementY -= getEffectiveGravity()）
    var vy = _vyTicks - PlayerMotion.gravityPerTick;
    // ③ 乘竖直摩擦（`setDeltaMovement(... * verticalFriction)`）
    vy *= PlayerMotion.verticalFrictionPerTick;
    // 下落限速：`terminalVelocity` 是**下落**终端速度（负值，格/秒），换算成格/刻。
    if (vy < PlayerMotion.terminalVelocity / 20.0) {
      vy = PlayerMotion.terminalVelocity / 20.0;
    }
    _vyTicks = vy;
    player.velocity.y = vy * 20.0; // 对外暴露仍用格/秒
  }

  /// 飞行固定步（REF: `LivingEntity.travelInAir` 空中分支 + `Player.travel`
  /// 飞行分支 + `LocalPlayer.aiStep` 的竖直注入 + `Player.getFlyingSpeed`）。
  ///
  /// **原版逐刻递推**（`格/刻` 单位，20 刻/秒；速度源是服务器下发的
  /// [AbilitiesSnapshot.flyingSpeed]，默认 0.05——`Abilities.DEFAULT_FLYING_SPEED`）：
  ///
  /// - 水平：`travelInAir` 在不在地面时`blockFriction = 1.0`，故摩擦
  ///   `1.0 × 0.91 = 0.91`；`moveRelative(getFlyingSpeed())` 先注入
  ///   `flyingSpeed × (疾跑 ? 2 : 1)`，再整体乘摩擦。
  ///   终速 `0.05×0.91/0.09 = 0.5056 格/刻 ≈ 10.11 格/秒`（疾跑 ≈ 20.22）。
  /// - 竖直：`LocalPlayer.aiStep` 先注入 `inputYa × flyingSpeed × 3.0`
  ///   （**不含疾跑倍率**——原版该行直接调`abilities.getFlyingSpeed()`），
  ///   随后 `Player.travel` 用 `originalMovementY × 0.6` 覆盖掉 `travelInAir`
  ///   算出的重力与竖直摩擦结果。故**无重力**，竖直终速
  ///   `0.15×0.6/0.4 = 0.225 格/刻 = 4.5 格/秒`。
  ///
  /// 用 1/20s 量子精确复刻该逐刻递推（固定步 1/120s，用刻累加器取整），
  /// 位移换算：`格/刻 × (dt × 20)`。
  ///
  /// **不卡边**（原版 `makeStuckInBlock` 对 `abilities.flying` 豁免）；撞墙时
  /// **不清零速度**（原版 `Entity.move` 只拦位置、不改 deltaMovement，清零会让
  /// 贴墙飞行像"撞停"）。
  void _flyingStep(double dt, InputState input) {
    final flyingSpeed = abilities?.flyingSpeed ?? 0.05; // 格/刻²
    final inputYa = (input.jump ? 1.0 : 0.0) - (input.sneak ? 1.0 : 0.0);

    _flyAccumTicks += dt * 20.0;
    while (_flyAccumTicks >= 1.0) {
      _flyAccumTicks -= 1.0;

      // —— 水平（REF: `LivingEntity.travelInAir` 空中分支）——
      if (input.isMoving) {
        final forward = Vector3(-math.sin(player.yaw), 0, -math.cos(player.yaw));
        final right = Vector3(math.cos(player.yaw), 0, -math.sin(player.yaw));
        final dir = (forward * input.move.y + right * input.move.x).normalized();
        final accel = flyingSpeed * (input.sprint ? 2.0 : 1.0);
        _flyVelocity.x = (_flyVelocity.x + dir.x * accel) * PlayerMotion.flyFriction;
        _flyVelocity.z = (_flyVelocity.z + dir.z * accel) * PlayerMotion.flyFriction;
      } else {
        _flyVelocity.x *= PlayerMotion.flyFriction;
        _flyVelocity.z *= PlayerMotion.flyFriction;
      }

      // —— 竖直：注入后由 `Player.travel` 收尾乘 0.6（重力被覆盖 ⇒ 无重力）——
      _flyVelocity.y =
          (_flyVelocity.y + inputYa * flyingSpeed * 3.0) * PlayerMotion.flyVerticalRetain;
    }

    final vxPerSec = _flyVelocity.x * 20.0;
    final vyPerSec = _flyVelocity.y * 20.0;
    final vzPerSec = _flyVelocity.z * 20.0;
    final result = collision.move(
      player.bounds,
      vxPerSec * dt,
      vyPerSec * dt,
      vzPerSec * dt,
    );
    // 原版 `Entity.move` 撞墙只拦位置、不改速度——**故这里不清零**。
    player.velocity.setValues(vxPerSec, vyPerSec, vzPerSec);
    player.applyMove(result);
    player.onGround = result.hitY && result.hasBlockBelow;
  }

  /// 双击窗口剩余秒数（只读诊断视图；原版 `jumpTriggerTime` 剩余刻数 ÷ 20）。
  double get jumpTriggerSeconds => _jumpTriggerSeconds;

  /// 上一固定步结束时是否按住跳跃（只读诊断视图）。
  bool get wasJumping => _wasJumping;

  /// 飞行速度（`格/刻`；与 [Player.velocity]的 `格/秒` 分开承载）。
  final Vector3 _flyVelocity = Vector3.zero();
  double _flyAccumTicks = 0;
}


/// abilities 快照（app 壳每帧从会话同步；纯数据便于控制器单测）。
class AbilitiesSnapshot {
  AbilitiesSnapshot({this.mayfly = false, this.flyingSpeed = 0.05});
  bool mayfly;
  double flyingSpeed;
}
