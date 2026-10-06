import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'collision.dart';

/// 玩家状态（移植自 fscraft player.dart，去掉存档面：位置由服务器校正驱动）。
/// 纯数据 + 纯逻辑：不 import flutter_scene。
/// [position] 是脚底中心（原版实体的 posY 在脚底）。
class Player {
  Player({
    Vector3? position,
    this.yaw = 0,
    this.pitch = 0,
  }) : position = position ?? Vector3.zero();

  Vector3 position;
  Vector3 velocity = Vector3.zero();

  /// yaw 绕 y 轴（弧度，0 = 朝 -Z），pitch 正值向下。
  double yaw;
  double pitch;

  bool onGround = false;

  Aabb get bounds => Aabb.player(position.x, position.y, position.z);

  void applyMove(MoveResult r) {
    position.setValues(r.centerX, r.minY, r.centerZ);
  }

  Vector3 get eyePosition =>
      Vector3(position.x, position.y + Aabb.eyeHeight, position.z);

  Vector3 get lookDirection {
    final cosPitch = math.cos(pitch);
    return Vector3(
      -math.sin(yaw) * cosPitch,
      -math.sin(pitch),
      -math.cos(yaw) * cosPitch,
    );
  }

  void clampPitch() {
    const limit = math.pi / 2 - 0.0018;
    pitch = pitch.clamp(-limit, limit);
  }

  /// 应用视角增量（REF: `MouseHandler.turnPlayer` + `Entity.turn`：
  /// sens = (0.6s+0.2)³×8.0，转向 0.15°/像素 → 弧度；sensitivity 为设置滑条
  /// 0..1，默认 0.5 时恰为 1.0）。
  void applyLook(Vector2 lookDelta, {double sensitivity = 0.5}) {
    final ss = sensitivity * 0.6 + 0.2;
    final sens = ss * ss * ss * 8.0;
    const degToRad = math.pi / 180.0;
    yaw -= lookDelta.x * 0.15 * sens * degToRad;
    pitch += lookDelta.y * 0.15 * sens * degToRad;
    yaw = _wrapAngle(yaw);
    clampPitch();
  }

  static double _wrapAngle(double a) {
    const twoPi = math.pi * 2;
    var v = a % twoPi;
    if (v <= -math.pi) v += twoPi;
    if (v > math.pi) v -= twoPi;
    return v;
  }
}
