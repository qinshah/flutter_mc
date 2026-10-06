import 'package:vector_math/vector_math.dart';

/// 一帧的玩家输入（**Flutter 输入是本项目三处自由设计之一**，故本类型无原版对应物，
/// 只把原版 `client.KeyMapping` 的语义面收敛成纯数据，便于无 Flutter 单测）。
///
/// 语义对齐原版（判据 `mc-sources/minecraft-26.2`）：
/// - `move` 是**玩家本地坐标**：`y` = 前后（+1 前）、`x` = 左右（+1 右）——
///   原版 `player.xxa`（左右）/`zzz`（前后）同一口径
/// - `jump` = 原版 `KeyMapping` 的 `key.jump`（空格）
/// - `sneak` / `sprint` = 原版 `key.shift` / `key.sprint`（本切片只用它们影响速度）
/// - `lookDelta` 是**这一帧转了多少**（鼠标位移，不是绝对角度），
///   与 `Player.applyLook` 的入参同一口径
class InputState {
  InputState();

  /// 本地移动意图：`x` 右为正，`y` 前为正（两者都在 [-1,1]）。
  final Vector2 move = Vector2.zero();

  /// 本帧的鼠标位移（右为正、下为正）。
  final Vector2 lookDelta = Vector2.zero();

  bool jump = false;
  bool sneak = false;
  bool sprint = false;

  bool get isMoving => move.x != 0 || move.y != 0;

  /// 一帧结束后清掉"消费型"输入（鼠标位移），按住的键保留（原版按键是持续状态）。
  void endFrame() => lookDelta.setZero();
}
