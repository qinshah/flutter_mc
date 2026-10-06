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
  }) : collision = collision ?? VoxelCollision(world);

  final CollisionWorld world;
  final Player player;
  final VoxelCollision collision;

  double _accumulator = 0;

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

    // —— 竖直：原版逐刻语义（先减重力，再乘空气阻力） ——
    if (input.jump && player.onGround) {
      player.velocity.y = PlayerMotion.jumpVelocity;
      player.onGround = false;
    }
    player.velocity.y = (player.velocity.y - PlayerMotion.gravity * dt) *
        math.exp(-PlayerMotion.airDamping * dt);
    if (player.velocity.y < PlayerMotion.terminalVelocity) {
      player.velocity.y = PlayerMotion.terminalVelocity;
    }

    // —— 位移与碰撞 ——（`VoxelCollision.move` 内部已按最长轴拆子步）
    final result = collision.move(
      player.bounds,
      player.velocity.x * dt,
      player.velocity.y * dt,
      player.velocity.z * dt,
    );
    // 被挡的轴速度清零（贴墙滑动由 collision 的逐轴求解保证）。
    if (result.hitX) player.velocity.x = 0;
    if (result.hitZ) player.velocity.z = 0;
    if (result.hitY) player.velocity.y = 0;

    player.applyMove(result);
    // 着地：竖直被挡且脚下有方块（原版 onGround 口径）。
    player.onGround = result.hitY && result.hasBlockBelow;
  }
}
