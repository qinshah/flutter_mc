import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'package:flutter_mc/game/collision.dart';
import 'package:flutter_mc/world/entity/player/inventory.dart';
import 'package:flutter_mc/world/phys/vec3.dart';

/// 玩家状态（移植自 fscraft player.dart，去掉存档面：位置由服务器校正驱动）。
/// 纯数据 + 纯逻辑：不 import flutter_scene。
/// [position] 是脚底中心（原版实体的 posY 在脚底）。
class Player {
  Player({
    this.position = Vec3.zero,
    this.yaw = 0,
    this.pitch = 0,
  }) : inventory = Inventory();

  /// **double 位置**（判据 `Entity.xPos/yPos/zPos` 是 double；`Vec3.java:41-43`
  /// 字段亦 double）。渲染边界才转 float32（[interpolatedPosition]）。
  Vec3 position;
  Vector3 velocity = Vector3.zero();

  /// `Entity.setPos(x, y, z)`：整体替换（Vec3 不可变，原版同款）。
  void setPos(double x, double y, double z) => position = Vec3(x, y, z);

  Aabb get bounds => Aabb.player(position.x, position.y, position.z);

  void applyMove(MoveResult r) {
    setPos(r.centerX, r.minY, r.centerZ);
  }

  /// 物品栏（原版 `player.getInventory()`；当前为最小实现——仅选中槽位，
  /// 判据 `Inventory.java:66-76/:130-132`，完整实现见翻译债 §8）。
  final Inventory inventory;

  /// yaw 绕 y 轴（弧度，0 = 朝 -Z），pitch 正值向下。
  double yaw;
  double pitch;

  bool onGround = false;

  /// 上一**刻**的脚底 y（渲染插值的起点）。
  ///
  /// 判据 `EntityRenderer.createRenderState`（mc-sources/minecraft-26.2:164）：
  /// `state.x = Mth.lerp(partialTicks, entity.xOld, entity.getX())`——原版客户端
  /// 物理只跑 20Hz，但渲染用「上一刻位置 → 当前刻位置」按 `partialTicks` 线性插值，
  /// 于是视觉上依旧顺滑。
  ///
  /// **缺了插值会怎样**：物理严格照原版 20Hz 推进（这才是跳得上一格的关键），
  /// 但画面每tick（1/20 秒）才跳一次 ⇒ 高帧率下表现为"一卡一卡地爬"。
  double yOld = 0;

  /// 刻进度 [0,1)：本刻已过的比例，由 [LocalPlayer] 每子步推进。
  double tickProgress = 0;

  /// 渲染用的插值位置（脚底）。
  Vector3 get interpolatedPosition {
    if (tickProgress <= 0) {
      // 渲染边界：double → float32 只发生在这里（GPU 侧本就 float32）。
      return Vector3(position.x, position.y, position.z);
    }
    return Vector3(
      position.x,
      yOld + (position.y - yOld) * tickProgress,
      position.z,
    );
  }

  /// 渲染用的插值眼睛位置（相机用这个，物理仍用 [position]）。
  Vector3 get eyePosition {
    final p = interpolatedPosition;
    return Vector3(p.x, p.y + Aabb.eyeHeight, p.z);
  }

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
