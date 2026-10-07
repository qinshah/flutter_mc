import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'package:flutter_mc/game/collision.dart';
import 'package:flutter_mc/world/entity/player/abilities.dart';
import 'package:flutter_mc/world/entity/player/input.dart';
import 'package:flutter_mc/world/entity/player/player.dart';

/// 本地玩家：读 [Input] → 重力/跳跃 → 碰撞求解 → 写 [Player]。
///
/// 判据：`net.minecraft.client.player.LocalPlayer`
/// （mc-sources/minecraft-26.2/.../client/player/LocalPlayer.java:117）。
///
/// **纯逻辑**：不 import Flutter / flutter_scene，所以运动学可以完整单测
/// （引擎侧的按键与节点变换在 app 壳的 `game_screen.dart` 里接）。
///
/// 简化点（标注）：水平方向按输入**直接赋值目标速度**（无加速/摩擦惯性）——
/// 原版 `LivingEntity.travel` 的加速度与地面摩擦链（0.91 摩擦）留作后续切片。
/// 竖直方向照原版**逐刻**语义（先减重力、再乘空气阻力），故终端速度与原版一致。
class LocalPlayer {

/// —— 运动常量（判据 mc-sources/minecraft-26.2）——（原版**每刻值**换算到每秒；判据 `mc-sources/minecraft-26.2`）。
///
/// - 重力 0.08 /刻 —— `Attributes.GRAVITY` 默认值（Attributes.java:56）→ ×400 = 32 block/s²
/// - 跳跃初速 0.42 /刻 —— `Attributes.JUMP_STRENGTH` 默认值（Attributes.java:59），
///   同值亦见 `LivingEntity.BASE_JUMP_POWER`（LivingEntity.java:172）→ ×20 = 8.4 block/s
/// - 空气阻力 0.98 /刻 —— `Entity.getAirDrag()`（Entity.java:1536）
/// - 终端速度 —— 0.08 / (1 − 0.98) = 3.92 block/刻 → 78.4 block/s
/// - 行走/疾跑/潜行 —— 4.317 / 5.612 / 1.295 block/s（`Player.createAttributes()` 的
///   `MOVEMENT_SPEED` 0.1，Player.java:209，配地面摩擦的稳态速度）
  static const double gravity = 32.0;
  static const double jumpVelocity = 8.4;
  static const double terminalVelocity = -78.4;


  ///

  /// 创造飞行的**竖直**注入系数（判据 `LocalPlayer.aiStep`，`LocalPlayer.java:844`）：
  /// `setDeltaMovement(add(0, inputYa * abilities.getFlyingSpeed() * 3.0F, 0))`。
  ///
  /// **注意与水平的速度来源不同**（这是 2026-10-07 踩过的坑）：
  /// - 竖直：`abilities.getFlyingSpeed() × 3`（客户端本地预测，`LocalPlayer.java:833-845`，
  ///   在 `super.aiStep()` **之前**独立执行，**不经过** `getInputVector`）
  /// - 水平：`getFrictionInfluencedSpeed` → 空中返回 `getFlyingSpeed()`
  ///   = `abilities.flyingSpeed`（疾跑 ×2，`Player.java:1952-1958`）
  ///
  /// 早先误把两者统一成 `getSpeed() × 0.1`（0.01 格/刻），比原版慢 15 倍
  /// （原版竖直是 0.05×3 = 0.15 格/刻）⇒ 实机反馈"飞行慢得像蜗牛"。
  static const double flyVerticalInputScale = 3.0;

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
  LocalPlayer({
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
  final Abilities? abilities;

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

  /// 飞行用的刻累加器（判据同竖直：`Player.travel` 每 tick 一次 `move()`，
  /// `Player.java:1395-1400`）。与 [_verticalTickAccum] 分开是因为两条路径
  /// 不能同时推进（飞行时行走分支直接 return）。
  double _flyTickAccum = 0;

  /// 本刻是否已起跳（原版 `noJumpDelay = 10` 的轻量替身：防止按住空格
  /// 在一个刻内重复注入初速；原版是 10 刻冷却，本期只保证"每刻至多一次"）。
  bool _jumpedThisTick = false;

  /// 本刻**未衰减**的水平位移（格/刻），供 `collision.move` 用。
  /// 原版 `move()` 在 `travelInAir` 的 `×0.91` 之前调用，故位移取衰减前的值。
  double _flyVelocityThisTickX = 0;
  double _flyVelocityThisTickY = 0;
  double _flyVelocityThisTickZ = 0;

  /// 本帧跨过刻边界时攒下的**整刻竖直位移**（格）。
  /// 原版一 tick 一次 `move()`，故必须整块结算——摊到 1/120s 子步会产生
  /// "阶梯式爬升"的滞手感（2026-10-07 实机：落地/起跳像陷进海绵）。
  double _pendingVertical = 0;

  /// 用一帧的真实 `dt` 驱动：内部按 [fixedStep] 固定步长累加。
  void tick(double dt, Input input) {
    // 视角**每帧只应用一次**：`lookDelta` 是"这一帧转了多少"，若放进固定步长
    // 会让灵敏度随帧率浮动。
    if (input.lookDelta.x != 0 || input.lookDelta.y != 0) {
      player.applyLook(input.lookDelta);
    }

    _accumulator +=
        dt.clamp(0.0, fixedStep * maxStepsPerFrame);
    var steps = 0;
    while (_accumulator >= fixedStep &&
        steps < maxStepsPerFrame) {
      _step(fixedStep, input);
      _accumulator -= fixedStep;
      steps++;
    }
    if (steps == maxStepsPerFrame) _accumulator = 0;
  }

  /// 一个固定步长的物理推进。
  void _step(double dt, Input input) {
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
            _flyVelocity.y += jumpVelocity / 20.0;
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
    final speed = input.shift
        ? sneakSpeed
        : input.sprint
            ? sprintSpeed
            : walkSpeed;
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
        jumpVelocity; // 格/秒（= 0.42 格/刻 × 20）
    if (input.jump && player.onGround && !_jumpedThisTick) {
      // `jumpFromGround()`：`Math.max(jumpPower, movement.y)`（源码 2372）——
      // 注入取较大者，MUST NOT 把已有的上升速度改小。
      final vyTicks = _vyTicks > 0 ? _vyTicks : jumpPower / 20.0;
      _vyTicks = vyTicks;
      _jumpedThisTick = true;
      player.onGround = false;
    }

    _verticalTickAccum += dt;
    while (_verticalTickAccum >= tickSeconds) {
      _verticalTickAccum -= tickSeconds;
      // 跨刻 ⇒ 上一刻的落点成为插值起点（判据 `EntityRenderer` 的 `xOld`）。
      player.yOld = player.position.y;
      _advanceVerticalTick(jumpPower);
      // 新的一刻 ⇒ 允许再次注入跳跃初速（原版 `noJumpDelay = 10` 是 10 刻冷却，
      // 本期只保证"每刻至多注入一次"，按住空格即可连续跳）。
      _jumpedThisTick = false;
    }

    // 对外暴露的竖直速度 = 刻速度 ×20（与 [Player.velocity] 的格/秒口径一致）。
    player.velocity.y = _vyTicks * 20.0;

    // —— 竖直位移：按**整刻**结算，不摊到 1/120s 子步 ——
    //
    // 原版 `handleRelativeFrictionAndCalculateMovement` 里`move(MoverType.SELF,
    // deltaMovement)` 用的是 `deltaMovement`（**每刻位移**），一 tick 一次。
    // 若把 1/120s 的 dt 乘进刻速度，就等于"一个刻的位移在 6 个子步里重复用"，
    // 视觉上就成了**阶梯式慢速爬升**——手感像陷进海绵（2026-10-07 实机反馈）。
    //
    // `_pendingVertical` 记录"本帧跨过刻边界时攒下的整刻位移"，在子步里
    // **只结算一次**，其余子步竖直位移为 0（水平照旧逐子步求交，防穿墙）。
    final result = collision.move(
      player.bounds,
      player.velocity.x * dt,
      _pendingVertical,
      player.velocity.z * dt,
    );
    _pendingVertical = 0;
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
    _advanceTickProgress();
  }

  /// 推进渲染插值进度（判据 `EntityRenderer.extractRenderState`，
  /// `EntityRenderer.java:164-165`：`Mth.lerp(partialTicks, yOld, getY())`）。
  ///
  /// 原版对**所有**实体一律插帧，不区分行走/跳跃/飞行 ⇒ 我们也 MUST 在
  /// 每条物理路径上推进，否则该状态在渲染上是 20Hz 台阶（表现为卡顿）。
  void _advanceTickProgress() {
    final accum = flying && _flyTickAccum > 0
        ? _flyTickAccum
        : _verticalTickAccum;
    player.tickProgress =
        (accum / tickSeconds).clamp(0.0, 1.0);
  }

  /// 推进一个刻的竖直运动学（REF 见 [PlayerMotion] 的时序注释）。
  ///
  /// 顺序严格照原版：**先按当前速度积分位置，再扣重力、乘阻力**。
  /// 反过来做会让跳高掉到 0.9969 格（跳不上 1 格高方块）。
  void _advanceVerticalTick(double jumpPower) {
    // ① **位移**：原版此刻调`move()`，用的是**本刻未扣重力**的 vy（源码 2657）。
    // 累加到 `_pendingVertical`，由本帧的下一次 `collision.move` **整块**结算。
    _pendingVertical += _vyTicks;
    // ② 扣重力（`travelInAir`：movementY -= getEffectiveGravity()`）
    var vy = _vyTicks - gravityPerTick;
    // ③ 乘竖直摩擦（`setDeltaMovement(... * verticalFriction)`）
    vy *= verticalFrictionPerTick;
    // 下落限速：`terminalVelocity` 是**下落**终端速度（负值，格/秒），换算成格/刻。
    if (vy < terminalVelocity / 20.0) {
      vy = terminalVelocity / 20.0;
    }
    _vyTicks = vy;
    player.velocity.y = vy * 20.0; // 对外暴露仍用格/秒
  }

  /// 飞行固定步（REF: `LivingEntity.travelInAir` 空中分支 + `Player.travel`
  /// 飞行分支 + `LocalPlayer.aiStep` 的竖直注入 + `Player.getFlyingSpeed`）。
  ///
  /// **原版逐刻递推**（`格/刻` 单位，20 刻/秒；速度源是服务器下发的
  /// [Abilities.flyingSpeed]，默认 0.05——`Abilities.DEFAULT_FLYING_SPEED`）：
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
  void _flyingStep(double dt, Input input) {
    // `inputYa` = `jump - sneak`（判据 `LocalPlayer.java:834-840`：
    // shift → -1、jump → +1，相加）。
    final inputYa = (input.jump ? 1.0 : 0.0) - (input.shift ? 1.0 : 0.0);
    // 竖直注入量（判据 `LocalPlayer.java:844`）：
    // `inputYa * abilities.getFlyingSpeed() * 3.0F`—— 服务器下发的
    // `Abilities.flyingSpeed`（默认 0.05）× 3 = 0.15 格/刻。
    final flyingSpeedPerTick =
        (abilities?.flyingSpeed ?? 0.05) * flyVerticalInputScale;

    _flyTickAccum += dt;
    while (_flyTickAccum >= tickSeconds) {
      _flyTickAccum -= tickSeconds;
      // 跨刻 ⇒ 上一刻落点成为插值起点（判据 `EntityRenderer.java:164` 的 `yOld`，
      // 原版对飞行实体同样插帧）。
      player.yOld = player.position.y;

      // —— 逐字翻译 `LivingEntity.handleRelativeFrictionAndCalculateMovement` + `travelInAir`——
      //
      // 判据 mc-sources/minecraft-26.2：
      //   LivingEntity:2656  moveRelative(getFrictionInfluencedSpeed(friction), input)
      //   LivingEntity:2658  move(MoverType.SELF, getDeltaMovement())
      //   LivingEntity:2460  movementY -= getEffectiveGravity()
      //   LivingEntity:2474  setDeltaMovement(× verticalFriction)      // 0.98
      //   Player:1952-1958   getFlyingSpeed() = abilities.flyingSpeed（疾跑 ×2）
      //
      // 顺序不可换：先按**未扣重力**的速度位移，再扣重力，最后乘摩擦。
      // `getFrictionInfluencedSpeed` 空中返回 `getFlyingSpeed()`（:2699），**不读**
      // 服务器下发的 `flyingSpeed`；**竖直**才读它（`LocalPlayer.java:844`）。

      // ① moveRelative：`setDeltaMovement(δ + input × getFlyingSpeed())`
      //   判据 Entity:1741 `moveRelative` → `setDeltaMovement(deltaMovement.add(delta))`
      // **判据 `Player.getFlyingSpeed()`（`Player.java:1952-1958`）**：
      //   if (this.abilities.flying && !this.isPassenger()) {
      //     return this.isSprinting()
      //         ? this.abilities.getFlyingSpeed() * 2.0F
      //         : this.abilities.getFlyingSpeed();
      //   }
      // 即：创造飞行（非载具）的水平注入 = `abilities.flyingSpeed`
      // （默认 0.05 格/刻，`Abilities.java:13/20`），疾跑 ×2。
      // 经 `moveRelative`（`Entity.java:1741`）注入，input 长度 > 1 时
      // 按 `getInputVector`（`Entity.java:1752`）归一化折算。
      //
      // **别抄基类 `LivingEntity.getFlyingSpeed()`（`LivingEntity.java:2707-2709`）**
      // ——它的 `getSpeed() × 0.1` 分支是给**被玩家骑乘的载具**用的，
      // Player 覆盖了它。2026-10-07 实测 bug：错抄基类得到 0.01 格/刻，
      // 飞行终速只有 2.02 格/秒，比行走（4.32 格/秒）还慢一半多。
      // `Abilities.walkingSpeed`（判据 `Player.java:639`
      // `setBaseValue(abilities.getWalkingSpeed())`）只喂地面行走，**不参与飞行**。
      // 判据 `Player.java:1952-1958`（见上）：flyingSpeed，疾跑 ×2。
      final flyingSpeedBase = abilities?.flyingSpeed ?? 0.05;
      final flySpeed = input.sprint ? flyingSpeedBase * 2.0 : flyingSpeedBase;
      if (input.isMoving) {
        final forward = Vector3(-math.sin(player.yaw), 0, -math.cos(player.yaw));
        final right = Vector3(math.cos(player.yaw), 0, -math.sin(player.yaw));
        final dir = (forward * input.move.y + right * input.move.x).normalized();
        _flyVelocity.x += dir.x * flySpeed;
        _flyVelocity.z += dir.z * flySpeed;
      }
      // 竖直：判据 `LocalPlayer.java:833-845` —— **独立于水平**的一段：
      //   if (abilities.flying && isControlledCamera()) {
      //     int inputYa = (shift ? -1 : 0) + (jump ? 1 : 0);
      //     if (inputYa != 0)
      //       setDeltaMovement(deltaMovement.add(0, inputYa * abilities.getFlyingSpeed() * 3.0F, 0));
      //   }
      // 它在 `super.aiStep()` 之前跑，**不经过** `getInputVector`，
      // 所以水平那套 `length > 1.0` 归一化不适用于竖直。
      if (inputYa != 0) {
        _flyVelocity.y += inputYa * flyingSpeedPerTick;
      }

      // ② move：位移用**未扣重力、未乘摩擦**的速度（`deltaMovement` 原值）。
      _flyVelocityThisTickX = _flyVelocity.x;
      _flyVelocityThisTickY = _flyVelocity.y;
      _flyVelocityThisTickZ = _flyVelocity.z;

      // travelInAir（2460/2474）：扣重力 → 乘竖直摩擦。水平同理 × 0.91（airDrag）。
      _flyVelocity.y =
          (_flyVelocity.y - gravityPerTick) * verticalFrictionPerTick;
      _flyVelocity.x *= flyFriction;
      _flyVelocity.z *= flyFriction;

      // ③ `Player.travel` 飞行收尾（Player.java:1398）：
      //   setDeltaMovement(y = originalMovementY * 0.6)
      // 逐字翻译——**不引入原版没有的 `Math.max`**。原版就是拿 ① 注入后的
      // 速度乘 0.6，之前自行解读成"max(injected, afterGravity)"会导致松手时
      // 速度被锁死（实测收敛到 0.0002，飞行变失重悬浮）。
      _flyVelocity.y =
          _flyVelocityThisTickY * flyVerticalRetain;
    }

    // 位移用**本刻未衰减**的速度（② `move(MoverType.SELF, deltaMovement)`），
    // 衰减后的速度留到下一刻（③ 在 `move` 之后）。
    //
    // 原版一 tick 一次 `move()`，本实现同理（刻累加器在 `_step` 内推进）——
    // 刻内未跨刻的子步位移为 0，与"原版一个 tick 只move 一次"完全一致。
    final vxPerTick = _flyVelocityThisTickX;
    final vyPerTick = _flyVelocityThisTickY;
    final vzPerTick = _flyVelocityThisTickZ;
    // 竖直位移**不在这里乘 dt**：原版 `super.travel` 的 `move()` 用的就是
    // `deltaMovement`（每刻位移），上面已按 `injected` 逐刻累加进
    // `_pendingVertical`，此处整块结算。早先误用 `vyPerSec * dt`，等于
    // 既摊到子步又叠加刻末速度 ⇒ 速度偏高（实测 4.22 格/秒，原版应7.5）。
    final result = collision.move(
      player.bounds,
      vxPerTick,
      vyPerTick,
      vzPerTick,
    );
    _flyVelocityThisTickX = 0;
    _flyVelocityThisTickY = 0;
    _flyVelocityThisTickZ = 0;
    // 原版 `Entity.move` 撞墙只拦位置、不改速度——**故这里不清零**。
    //
    // 暴露的速度是 `deltaMovement` 的原值：x/z 用 ③衰减**后**的值（本刻
    // move 用的是衰减前、已存进 `_flyVelocityThisTick*`），y 用 `Player.travel`
    // 收尾后的值（`originalMovementY × 0.6`）。×20 换算成格/秒供上层用。
    player.velocity.setValues(
      _flyVelocity.x * 20.0,
      _flyVelocity.y * 20.0,
      _flyVelocity.z * 20.0,
    );
    player.applyMove(result);
    player.onGround = result.hitY && result.hasBlockBelow;
    // 飞行态也要插帧（判据 `EntityRenderer.java:164` 对所有实体一律插值）。
    _advanceTickProgress();
  }

  /// 双击窗口剩余秒数（只读诊断视图；原版 `jumpTriggerTime` 剩余刻数 ÷ 20）。
  double get jumpTriggerSeconds => _jumpTriggerSeconds;

  /// 上一固定步结束时是否按住跳跃（只读诊断视图）。
  bool get wasJumping => _wasJumping;

  /// 飞行速度（`格/刻`；与 [Player.velocity]的 `格/秒` 分开承载）。
  final Vector3 _flyVelocity = Vector3.zero();
}
