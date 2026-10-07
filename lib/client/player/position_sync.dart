import '../../world/entity/player/player.dart';

/// `LocalPlayer.sendPosition()`（`LocalPlayer.java:265-302`）的 Dart 对应物。
///
/// **为什么必须存在**：26.2 的移动是**客户端权威上报**——服务器靠
/// `ServerboundMovePlayerPacket` 系列更新它相信的玩家位置，区块流窗口、
/// 反作弊、无关方块交互校验全挂在那个位置上。缺了它，服务器把区块持续
/// 发在**旧位置**周围：客户端飞出去后脚下列永远不再下发（2026-10-07 实机
/// 日志：服务器持续 load 距玩家 10 区块、以旧位置为中心的环）。
///
/// **判据（逐行）**：
/// - `:274` `move = lengthSquared(dPos) > square(2.0E-4) || positionReminder >= 20`；
/// - `:275` `rot = deltaYRot != 0.0 || deltaXRot != 0.0`；
/// - `:276-283` move&&rot → PosRot、move → Pos、rot → Rot、
///   onGround/horizontalCollision 变了 → StatusOnly；
/// - `:286-299` move/rot 后更新基准；`positionReminder` 每 tick 自增。
///
/// **换算**：本应用 yaw 0 = 朝 −Z（弧度），原版 yRot 0 = 朝 +Z（度）
/// ⇒ `yRot = 180 − yaw°`（PositionCorrection 的逆变换）；pitch 同度数直取。
///
/// **偏差（债）**：原版 `positionReminder` 按 tick（20 tps）计，本仓按帧计
/// ——静止时位置保底上报频率 3Hz 而非 1Hz，只多不少，无害。
class PositionSync {
  double _xLast = 0;
  double _yLast = 0;
  double _zLast = 0;
  double _yRotLast = 0;
  double _xRotLast = 0;
  int _positionReminder = 0;
  bool _lastOnGround = false;
  bool _lastHorizontalCollision = false;
  bool _baselined = false;

  /// 上行一个位置帧。[yawDeg]/[pitchDeg] 是原版口径的度数。
  void tick({
    required Player player,
    required double yawDeg,
    required double pitchDeg,
    required bool horizontalCollision,
    required void Function(MoveVariant variant, double x, double y, double z,
        double yRot, double xRot, bool onGround, bool horizontalCollision)
        send,
  }) {
    final x = player.position.x;
    final y = player.position.y;
    final z = player.position.z;

    // 首帧只立基准（原版字段初值 0，首个 tick 天然产生一次 move+rot 全量
    // PosRot——这里显式立基准避免把"从 0 到出生点"当成一次移动上报）。
    if (!_baselined) {
      _baselined = true;
      _xLast = x;
      _yLast = y;
      _zLast = z;
      _yRotLast = yawDeg;
      _xRotLast = pitchDeg;
      return;
    }

    // 判据 `:268-275`。
    final dx = x - _xLast;
    final dy = y - _yLast;
    final dz = z - _zLast;
    final dyRot = yawDeg - _yRotLast;
    final dxRot = pitchDeg - _xRotLast;
    _positionReminder++;
    const eps = 2.0e-4;
    final move = dx * dx + dy * dy + dz * dz > eps * eps ||
        _positionReminder >= 20; // :274
    final rot = dyRot != 0.0 || dxRot != 0.0; // :275

    // 判据 `:276-283`。
    if (move && rot) {
      send(MoveVariant.posRot, x, y, z, yawDeg, pitchDeg, player.onGround,
          horizontalCollision);
    } else if (move) {
      send(MoveVariant.pos, x, y, z, yawDeg, pitchDeg, player.onGround,
          horizontalCollision);
    } else if (rot) {
      send(MoveVariant.rot, x, y, z, yawDeg, pitchDeg, player.onGround,
          horizontalCollision);
    } else if (_lastOnGround != player.onGround ||
        _lastHorizontalCollision != horizontalCollision) {
      send(MoveVariant.statusOnly, x, y, z, yawDeg, pitchDeg, player.onGround,
          horizontalCollision);
    }

    // 判据 `:286-299`。
    if (move) {
      _xLast = x;
      _yLast = y;
      _zLast = z;
      _positionReminder = 0;
    }
    if (rot) {
      _yRotLast = yawDeg;
      _xRotLast = pitchDeg;
    }
    _lastOnGround = player.onGround;
    _lastHorizontalCollision = horizontalCollision;
  }
}

/// `ServerboundMovePlayerPacket` 的四个变体（`Pos/PosRot/Rot/StatusOnly`）。
enum MoveVariant { pos, posRot, rot, statusOnly }
