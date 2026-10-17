import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'package:flutter_mc/game/collision.dart';
import 'package:flutter_mc/world/entity/player/abilities.dart';
import 'package:flutter_mc/world/entity/player/input.dart';
import 'package:flutter_mc/world/entity/player/player.dart';

/// 本地玩家：读 [Input] → travel 链 → 碰撞求解 → 写 [Player]。
///
/// 判据：`net.minecraft.client.player.LocalPlayer`
/// （mc-sources/minecraft-26.2/.../client/player/LocalPlayer.java:117）。
///
/// **纯逻辑**：不 import Flutter / flutter_scene，所以运动学可以完整单测
/// （引擎侧的按键与节点变换在 app 壳的 `game_screen.dart` 里接）。
///
/// 行走 = **逐刻 travel 链**（2026-10-11 对齐重写，判据 `LivingEntity.travelInAir`
/// LivingEntity.java:2449-2477 + `handleRelativeFrictionAndCalculateMovement`
/// :2654-2666 + `Entity.move` 的 restitute Entity.java:793-795）：
/// 注入（moveRelative）→ move（整刻位移，每刻一次）→ **碰撞轴清零**
/// （restituteMovementAfterCollisions，restitution=0）→ 扣重力 → 乘摩擦。
/// 飞行 = `Player.travel` 飞行分支（Player.java:1398）+ `LocalPlayer.aiStep`
/// 竖直注入（:833-845），逐刻递推照旧。
class LocalPlayer {
  /// 穿透探针开关（与 app 壳的 TRACE 共用 define）。
  static const bool kTracePenetrate = bool.fromEnvironment('TRACE');


/// —— 运动常量（判据 mc-sources/minecraft-26.2）——
///
/// - 重力 0.08 /刻 —— `Attributes.GRAVITY` 默认值（Attributes.java:56）
/// - 跳跃初速 0.42 /刻 —— `Attributes.JUMP_STRENGTH` 默认值（Attributes.java:59）
/// - 空气阻力 0.91（水平）/ 0.98（竖直）—— `travelInAir`（:2472-2475）
/// - 行走注入 = `MOVEMENT_SPEED` 0.1（Player.java:209）× 疾跑 1.3
///   （LivingEntity.java:157-158 ADD_MULTIPLIED_TOTAL）× 潜行 0.3
///   （`Attributes.SNEAKING_SPEED` 默认）；
///   **空中注入 = `getFlyingSpeed()` = 0.02**（LivingEntity.java:2699-2701，
///   Player 未覆盖步行态）——这是"跳跃/空中转向明显慢于地面"的原版语义。
/// - 地面摩擦 = blockFriction(默认 0.6) × airDrag(0.91) = 0.546（:2450-2453/:2473）
  static const double jumpVelocity = 8.4; // 0.42 格/刻 × 20（格/秒口径，对外）

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
    this.onSprintingChanged,
  }) : collision = collision ?? VoxelCollision(world);

  final CollisionWorld world;
  final Player player;
  final VoxelCollision collision;

  /// 服务器权威 abilities（mayfly/flyingSpeed）；null=未知（按不可飞处理）。
  final Abilities? abilities;

  /// 双击空格切换飞行后回调（app 壳 → session.sendAbilities 上报）。
  final void Function(bool flying)? onFlyingToggled;

  /// 加速态变化回调（app 壳 → session.sendSprinting 上报；判据
  /// `LocalPlayer.sendIsSprintingIfNeeded`，`LocalPlayer.java:304-309`）。
  final void Function(bool sprinting)? onSprintingChanged;

  // —— 加速状态机（判据 `LocalPlayer.aiStep`，`LocalPlayer.java:764-790`）——

  /// 双击 W 的判定窗口（判据 `Options.java:623` `sprintWindow` 默认 **7 刻**）。
  static const int sprintWindowTicks = 7;

  int _sprintTriggerTicks = 0;

  /// 上刻末的"有前进冲动"采样（判据 `LocalPlayer.java:741`：
  /// `hasForwardImpulse` 在 `input.tick()` **之前**采样——即上刻末状态。
  /// 双击 W 依赖这个滞后一刻的口径：松开的那个刻置窗口，再按的刻起跑）。
  bool _forwardImpulsePrevTick = false;

  /// 上刻末的潜行键采样（判据 `LocalPlayer.java:740` `wasShiftKeyDown`）。
  bool _wasShiftKeyDown = false;

  /// 上一次 `move()` 是否发生水平碰撞（判据 `shouldStopRunSprinting` 的
  /// `horizontalCollision`；`minorHorizontalCollision` 未实现按 false，债）。
  bool _horizontalCollision = false;

  /// 位置上行读（`ServerboundMovePlayerPacket` 的 flags 位）。
  bool get horizontalCollision => _horizontalCollision;

  bool _sprinting = false;

  /// 是否正在加速（`Player.isSprinting()`；速度倍率与上行都读它）。
  bool get isSprinting => _sprinting;

  /// 判据 `Player.setSprinting` → 状态变化经 [onSprintingChanged] 上行
  /// （`sendIsSprintingIfNeeded`，`LocalPlayer.java:304-309`：变了才发）。
  void _setSprinting(bool value) {
    if (_sprinting == value) return;
    _sprinting = value;
    onSprintingChanged?.call(value);
  }

  /// 每刻推进一次加速状态机（原版在 `aiStep`，20Hz）。
  void _tickSprint(Input input) {
    // `LocalPlayer.java:730-731`
    if (_sprintTriggerTicks > 0) _sprintTriggerTicks--;

    // `:764-766`：潜行（上刻采样）/后退 → 取消双击窗口。
    // 子集：`isSlowDueToUsingItem` 未实现（使用物品不存在），恒 false——债。
    if (_wasShiftKeyDown || input.move.y < 0) {
      _sprintTriggerTicks = 0;
    }

    // `canStartSprinting`（`LocalPlayer.java:1095-1102`）。子集：
    // - `isSprintingPossible`（:1089-1093）：`hasEnoughFood...` 对创造恒 true、
    //   `isMobilityRestricted`/浅水未实现——债；
    // - `isSlowDueToUsingItem`、`isFallFlying` 同上恒 false；
    // - `isMovingSlowly`（:650-652）子集 = 潜行中（爬行未实现）。
    final hasForwardImpulseNow = input.move.y > 1e-5; // ClientInput.java:17
    final canStartSprinting = !_sprinting && hasForwardImpulseNow && !input.shift;
    if (canStartSprinting) {
      // `:769-775`——`hasForwardImpulse` 是**上刻**采样（:741）：
      // 双击 W = 松开的那个刻置窗口（窗口 tick 数），窗口内再按 W
      // （本刻 current=true、上刻=false）⇒ 起跑。
      if (!_forwardImpulsePrevTick) {
        if (_sprintTriggerTicks > 0) {
          _setSprinting(true);
        } else {
          _sprintTriggerTicks = sprintWindowTicks;
        }
      }

      // `:777-779`——Ctrl **按住**即加速（`KeyboardInput.java:31` 按住式）。
      if (input.sprint) {
        _setSprinting(true);
      }
    }

    // `:782-790` + `shouldStopRunSprinting`（`:883-885`）。子集：
    // `!isSprintingPossible` 未实现恒 false；`minorHorizontalCollision` 恒 false
    // （即任何水平碰撞都停——原版跨半砖这类"轻微碰撞"不停，债）。
    if (_sprinting) {
      if (!hasForwardImpulseNow || _horizontalCollision) {
        _setSprinting(false);
      }
    }

    // `:739-741` 的采样基准供下一刻使用。
    _wasShiftKeyDown = input.shift;
    _forwardImpulsePrevTick = hasForwardImpulseNow;
  }

  // —— 双击空格窗口（REF: LocalPlayer.aiStep：jumpTriggerTime=7 刻 = 0.35s）——
  bool _wasJumping = false;
  double _jumpTriggerSeconds = 0;

  /// 创造飞行（本地意图；可行性以 [abilities] 的 mayfly 为准）。
  bool flying = false;

  double _accumulator = 0;

  /// **deltaMovement（格/刻）**——原版 `Entity.getDeltaMovement()` 对应物。
  /// 行走/飞行共用一条状态（两条路径不会同时推进）。
  ///
  /// **着地不清零的历史教训（2026-10-11）**：曾把竖直状态单独放在 `_vyTicks`
  /// 且落地不清零 ⇒ 站立时 vy 收敛到 −3.92（终端速度），走出方块 = 瞬时满速
  /// 下坠。原版 `Entity.move` 的 restitute（Entity.java:793-795/:851，
  /// restitution=0）在**每次落地/撞墙时把碰撞轴清零**，站立 vy 每刻停在
  /// −0.0784，走出后从慢速正常加速。
  final Vector3 _deltaMovement = Vector3.zero();

  /// 行走 travel 链的刻累加器（每刻一次，`travel` 20Hz 口径）。
  double _walkTickAccum = 0;

  /// 飞行用的刻累加器（判据同竖直：`Player.travel` 每 tick 一次 `move()`，
  /// `Player.java:1395-1400`）。与 [_verticalTickAccum] 分开是因为两条路径
  /// 不能同时推进（飞行时行走分支直接 return）。
  double _flyTickAccum = 0;

  /// 加速状态机的刻累加器（每刻一次，`aiStep` 口径）。
  double _sprintTickAccum = 0;

  /// 本刻是否已起跳（原版 `noJumpDelay = 10` 的轻量替身：防止按住空格
  /// 在一个刻内重复注入初速；原版是 10 刻冷却，本期只保证"每刻至多一次"）。
  bool _jumpedThisTick = false;

  /// 本刻**未衰减**的水平位移（格/刻），供 `collision.move` 用。
  /// 原版 `move()` 在 `travelInAir` 的 `×0.91` 之前调用，故位移取衰减前的值。
  double _flyMoveThisTickX = 0;
  double _flyMoveThisTickY = 0;
  double _flyMoveThisTickZ = 0;

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
    // —— 加速状态机：每刻一次（原版 `aiStep` 20Hz；飞行/行走共用）——
    // 阈值带 epsilon：6×(1/120) 的浮点和可能略小于 0.05，会导致状态机
    // 偶发晚一拍（2026-10-07 实测）。
    _sprintTickAccum += dt;
    while (_sprintTickAccum >= tickSeconds - 1e-9) {
      _sprintTickAccum -= tickSeconds;
      _tickSprint(input);
    }

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
            _deltaMovement.y += jumpVelocity / 20.0;
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

    _walkingStep(dt, input);
  }

  /// 跨刻快照：当前落点成为本刻渲染插值的起点（三轴）。
  ///
  /// 判据 `Entity.setOldPos`（Entity.java:1824-1830，`xOld = x; yOld = y; …`），
  /// 调用点对应 `ClientLevel.java:482/497` 每刻实体 tick 入口的
  /// `setOldPosAndRot()`。
  void _snapshotOldPos() {
    player.xOld = player.position.x;
    player.yOld = player.position.y;
    player.zOld = player.position.z;
  }

  /// 行走固定步：**每刻一次 travel 链**（原版 20Hz；与飞行路径同构——
  /// 刻内未跨刻的子步不产生位移，渲染插值由 [Player.tickProgress] 平滑）。
  void _walkingStep(double dt, Input input) {
    _walkTickAccum += dt;
    while (_walkTickAccum >= tickSeconds - 1e-9) {
      _walkTickAccum -= tickSeconds;
      // 跨刻 ⇒ 上一刻的落点成为插值起点（判据 `ClientLevel.java:482`：
      // 每刻实体 tick 入口 `entity.setOldPosAndRot()`——三轴一并记录）。
      _snapshotOldPos();
      _travelWalkingTick(input);
      // 新的一刻 ⇒ 允许再次注入跳跃初速（原版 `noJumpDelay` 是 10 刻冷却，
      // 本期只保证"每刻至多注入一次"）。
      _jumpedThisTick = false;
    }
    _advanceTickProgress();
  }

  /// 一个行走刻的 **travel 链**（逐行对应 `LivingEntity.travelInAir`，
  /// LivingEntity.java:2449-2477）：
  ///
  /// ```java
  /// :2450-2453  blockFriction = onGround ? 脚下方块摩擦 : 1.0
  /// :2454       movement = handleRelativeFrictionAndCalculateMovement(input, f)
  ///               └ :2656 moveRelative(getFrictionInfluencedSpeed(f), input)
  ///               └ :2658 move(MoverType.SELF, deltaMovement)      ← 每刻一次
  /// :2458-2460  movementY = movement.y − getEffectiveGravity()     （0.08）
  /// :2472-2475  setDeltaMovement(x × (f×0.91), movementY × 0.98, z × (f×0.91))
  /// ```
  ///
  /// 外加 `Entity.move` 的 **restitute**（Entity.java:793-795/:851-853，
  /// 本地玩家 authoritative ⇒ 恒执行；restitution=0 ⇒ **碰撞轴清零**）：
  /// 落地/撞顶清 vy、撞墙清 v.x/v.z。三个实机症状全部源于此前缺这一环：
  /// ① 着地不清 vy ⇒ 站立时 vy 收敛到 −3.92（终端速度），走出方块 = 瞬时
  ///    满速下坠（原版每刻落地清零 ⇒ 走出后从 −0.0784 慢加速）；
  /// ② 空中注入 = `getFlyingSpeed()` 0.02 格/刻 + 0.91 阻力（惯性渐变），
  ///    而非每步直赋全速；
  /// ③ 撞墙轴不清 ⇒ 旧实现每子步重新赋全速再被截停（贴墙抽搐）。
  void _travelWalkingTick(Input input) {
    final v = _deltaMovement;

    // ① `jumpFromGround()`（LivingEntity.java:2370-2381；aiStep 在 travel 前调用）。
    if (input.jump && player.onGround && !_jumpedThisTick) {
      final jumpPower = jumpVelocity / 20.0; // 0.42 格/刻
      v.y = math.max(jumpPower, v.y);
      if (_sprinting) {
        // :2378-2381 疾跑跳纵向助推。原版 yRot（0=+Z）的 (−sin, +cos) 换算到
        // 我们的 yaw（0=−Z，yRot = 180° − yaw）：sin(yRot)=sin(yaw)、
        // cos(yRot)=−cos(yaw) ⇒ 助推 = (−sin(yaw), −cos(yaw))×0.2
        //（与前进方向 (−sin, −cos) 同向，恰为前进 ×0.2）。
        v.x -= math.sin(player.yaw) * 0.2;
        v.z -= math.cos(player.yaw) * 0.2;
      }
      _jumpedThisTick = true;
    }

    // ② blockFriction（:2450-2453；`getOnPos(0.500001)` = 脚下采样，Entity.java:1059-1061）。
    final belowY = (player.bounds.minY - 0.500001).floor();
    final f = player.onGround
        ? world.blockFrictionAt(
            player.position.x.floor(), belowY, player.position.z.floor())
        : 1.0;

    // ③ moveRelative 注入（`getFrictionInfluencedSpeed` :2695-2701：
    //    地面常规 f=0.6（不满足 >0.6）→ getSpeed() 原值；冰面 f>0.6 →
    //    speed × 0.216/f³；**空中 → getFlyingSpeed() = 0.02**）。
    final base = (abilities?.walkingSpeed ?? 0.1) *
        (_sprinting ? 1.3 : 1.0) * // 疾跑 +0.3 ADD_MULTIPLIED_TOTAL（:157-158）
        (input.shift ? 0.3 : 1.0); // 潜行 ×0.3（Attributes.SNEAKING_SPEED 默认）
    final injection = player.onGround
        ? (f > 0.6 ? base * 0.21600002 / (f * f * f) : base)
        : 0.02;
    if (input.isMoving) {
      final forward = Vector3(-math.sin(player.yaw), 0, -math.cos(player.yaw));
      final right = Vector3(math.cos(player.yaw), 0, -math.sin(player.yaw));
      var desired = forward * input.move.y + right * input.move.x;
      // `getInputVector`（Entity.java:1752-1756）：len² > 1 先归一化。
      if (desired.length2 > 1.0) desired = desired.normalized();
      v.x += desired.x * injection;
      v.z += desired.z * injection;
    }

    // ④ move（:2658——每刻一次，整刻位移；扫掠/步高在 collision.move 内）。
    final dy = v.y;
    final result = collision.move(
      player.bounds,
      v.x,
      v.y,
      v.z,
      wasOnGround: player.onGround,
    );
    player.applyMove(result);

    // ⑤ restitute（Entity.java:793-795 → :851-853；restitution=0 ⇒ 清零）。
    if (result.xCollision) v.x = 0;
    if (result.zCollision) v.z = 0;
    if (result.yCollision) v.y = 0;
    // onGround（Entity.java:772-776：verticalCollisionBelow，本地权威恒评）。
    player.onGround = result.yCollision && dy < 0;
    _horizontalCollision = result.xCollision || result.zCollision;

    // ⑥ 重力 + 摩擦（:2458-2460/:2472-2475）。
    final movementY = v.y - gravityPerTick;
    final friction = f * flyFriction; // blockFriction × airDrag(0.91)
    v.x *= friction;
    v.z *= friction;
    v.y = movementY * verticalFrictionPerTick; // 0.98

    // 对外暴露（格/秒口径，诊断/上行参考）。
    player.velocity.setValues(v.x * 20.0, v.y * 20.0, v.z * 20.0);
    _checkPenetration('walk');
  }

  /// **穿透探针**（TRACE 开启时生效；2026-10-11 实机"怼墙抽搐"取证）。
  ///
  /// 以服务器的口径自查（`isEntityCollidingWithAnythingNew`，
  /// ServerGamePacketListenerImpl.java:1216-1231）：盒 deflated 1e-5 后与方块
  /// 形状求交——若我们的预测落点穿透了任何方块，服务器必然拒绝并回拉（表现
  /// 为原地抽搐）。打点带方块身份串，直接定位形状分歧的方块。
  void _checkPenetration(String path) {
    if (!kTracePenetrate) return;
    // 双口径：
    // - GATE：服务器 gate2 同口径（deflate 1e-5 后严格相交）——穿透 >1e-5 必被拒；
    // - P0：零容差严格相交——专捕 0 < 穿透 ≤ 1e-5 的**微穿透**。深度量级直接
    //   分流结论：~1e-13 = 精确贴面的浮点噪声（vanilla 行为，服务器不可能拒）；
    //   ~1e-6 = 剪裁残差是真 bug（客户端碰撞没贴准）。
    _checkPenetrationEps(path, 'GATE', 1.0E-5);
    _checkPenetrationEps(path, 'P0', 0.0);
  }

  void _checkPenetrationEps(String path, String tag, double eps) {
    final b = player.bounds;
    final minX = b.minX + eps, maxX = b.x1 - eps;
    final minY = b.minY + eps, maxY = b.maxY - eps;
    final minZ = b.minZ + eps, maxZ = b.z1 - eps;
    for (var by = minY.floor(); by <= maxY.floor(); by++) {
      for (var bz = minZ.floor(); bz <= maxZ.floor(); bz++) {
        for (var bx = minX.floor(); bx <= maxX.floor(); bx++) {
          final shape = world.collisionShapeAt(bx, by, bz);
          if (shape == null || shape.isEmpty) continue;
          for (final box in shape.boxes) {
            final wbx0 = box.minX + bx, wbx1 = box.maxX + bx;
            final wby0 = box.minY + by, wby1 = box.maxY + by;
            final wbz0 = box.minZ + bz, wbz1 = box.maxZ + bz;
            if (minX < wbx1 && maxX > wbx0 && minY < wby1 && maxY > wby0 && minZ < wbz1 && maxZ > wbz0) {
              // 穿透深度 = 三轴重叠中最小者（全精度）。
              final ox = math.min(maxX, wbx1) - math.max(minX, wbx0);
              final oy = math.min(maxY, wby1) - math.max(minY, wby0);
              final oz = math.min(maxZ, wbz1) - math.max(minZ, wbz0);
              // ignore: avoid_print
              print('[PENETRATE$tag/$path] pos=(${player.position.x},'
                  '${player.position.y},${player.position.z}) '
                  'block=($bx,$by,$bz) ${world.blockIdentityAt(bx, by, bz)} '
                  'depth=($ox,$oy,$oz)');
            }
          }
        }
      }
    }
  }

  /// 推进渲染插值进度（判据 `EntityRenderer.extractRenderState`，
  /// `EntityRenderer.java:164-165`：`Mth.lerp(partialTicks, yOld, getY())`）。
  ///
  /// 原版对**所有**实体一律插帧，不区分行走/跳跃/飞行 ⇒ 我们也 MUST 在
  /// 每条物理路径上推进，否则该状态在渲染上是 20Hz 台阶（表现为卡顿）。
  void _advanceTickProgress() {
    // 各物理路径推进各自的累加器（飞行时 _walkTickAccum 是陈值，不可读）。
    final accum = flying ? _flyTickAccum : _walkTickAccum;
    player.tickProgress = (accum / tickSeconds).clamp(0.0, 1.0);
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
      // 跨刻 ⇒ 上一刻落点成为插值起点（判据 `ClientLevel.java:482`：
      // 每刻实体 tick 入口 `entity.setOldPosAndRot()`——三轴一并记录；
      // `EntityRenderer.java:164-166` 对飞行实体同样三轴插帧）。
      _snapshotOldPos();

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
      // 疾跑 ×2（判据 `Player.java:1952-1958`：`isSprinting()` 状态机裁决）。
      final flySpeed = _sprinting ? flyingSpeedBase * 2.0 : flyingSpeedBase;
      if (input.isMoving) {
        final forward = Vector3(-math.sin(player.yaw), 0, -math.cos(player.yaw));
        final right = Vector3(math.cos(player.yaw), 0, -math.sin(player.yaw));
        final dir = (forward * input.move.y + right * input.move.x).normalized();
        _deltaMovement.x += dir.x * flySpeed;
        _deltaMovement.z += dir.z * flySpeed;
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
        _deltaMovement.y += inputYa * flyingSpeedPerTick;
      }

      // ② move：位移用**未扣重力、未乘摩擦**的速度（`deltaMovement` 原值）。
      _flyMoveThisTickX = _deltaMovement.x;
      _flyMoveThisTickY = _deltaMovement.y;
      _flyMoveThisTickZ = _deltaMovement.z;

      // travelInAir（2460/2474）：扣重力 → 乘竖直摩擦。水平同理 × 0.91（airDrag）。
      _deltaMovement.y =
          (_deltaMovement.y - gravityPerTick) * verticalFrictionPerTick;
      _deltaMovement.x *= flyFriction;
      _deltaMovement.z *= flyFriction;

      // ③ `Player.travel` 飞行收尾（Player.java:1398）：
      //   setDeltaMovement(y = originalMovementY * 0.6)
      // 逐字翻译——**不引入原版没有的 `Math.max`**。原版就是拿 ① 注入后的
      // 速度乘 0.6，之前自行解读成"max(injected, afterGravity)"会导致松手时
      // 速度被锁死（实测收敛到 0.0002，飞行变失重悬浮）。
      _deltaMovement.y =
          _flyMoveThisTickY * flyVerticalRetain;
    }

    // 位移用**本刻未衰减**的速度（② `move(MoverType.SELF, deltaMovement)`），
    // 衰减后的速度留到下一刻（③ 在 `move` 之后）。
    //
    // 原版一 tick 一次 `move()`，本实现同理（刻累加器在 `_step` 内推进）——
    // 刻内未跨刻的子步位移为 0，与"原版一个 tick 只move 一次"完全一致。
    final vxPerTick = _flyMoveThisTickX;
    final vyPerTick = _flyMoveThisTickY;
    final vzPerTick = _flyMoveThisTickZ;
    // 竖直位移**不在这里乘 dt**：原版 `super.travel` 的 `move()` 用的就是
    // `deltaMovement`（每刻位移），上面已按 `injected` 逐刻累加进
    // `_pendingVertical`，此处整块结算。早先误用 `vyPerSec * dt`，等于
    // 既摊到子步又叠加刻末速度 ⇒ 速度偏高（实测 4.22 格/秒，原版应7.5）。
    final result = collision.move(
      player.bounds,
      vxPerTick,
      vyPerTick,
      vzPerTick,
      wasOnGround: player.onGround,
    );
    _flyMoveThisTickX = 0;
    _flyMoveThisTickY = 0;
    _flyMoveThisTickZ = 0;
    // restitute（Entity.java:793-795/:851-853，restitution=0 ⇒ 清零；本地玩家
    // authoritative 恒跑）：撞墙清水平轴。**Y 不清**——`Player.travel` 飞行
    // 收尾用 originalMovementY × 0.6（Player.java:1398-1399，original 是 move
    // 前的值）覆盖竖直轴，与原版一致。
    if (result.xCollision) _deltaMovement.x = 0;
    if (result.zCollision) _deltaMovement.z = 0;
    // 暴露的速度是 `deltaMovement` 的当前值（本刻 move 用的是衰减前、已存进
    // `_flyMoveThisTick*` 的原值）。×20 换算成格/秒供上层用。
    player.velocity.setValues(
      _deltaMovement.x * 20.0,
      _deltaMovement.y * 20.0,
      _deltaMovement.z * 20.0,
    );
    player.applyMove(result);
    // 着地同行走口径（Entity.java:1146）：yCollision && dy<0，
    // 只在竖直位移非零的结算点更新。
    if (vyPerTick != 0) {
      player.onGround = result.onGroundOf(vyPerTick);
    }
    // 水平碰撞供加速状态机用（飞行疾跑撞墙同样停，:883-885）。
    _horizontalCollision = result.xCollision || result.zCollision;
    // 飞行态也要插帧（判据 `EntityRenderer.java:164` 对所有实体一律插值）。
    _advanceTickProgress();
  }

  /// 双击窗口剩余秒数（只读诊断视图；原版 `jumpTriggerTime` 剩余刻数 ÷ 20）。
  double get jumpTriggerSeconds => _jumpTriggerSeconds;

  /// 上一固定步结束时是否按住跳跃（只读诊断视图）。
  bool get wasJumping => _wasJumping;

}
