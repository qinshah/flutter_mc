import 'package:vector_math/vector_math.dart';

/// 一帧的玩家输入（**Flutter 输入是本项目三处自由设计之一**，故本类型无原版对应物，
/// 只把原版 `client.KeyMapping` 的语义面收敛成纯数据，便于无 Flutter 单测）。
///
/// 语义对齐原版（判据 `mc-sources/minecraft-26.2`）：
/// - `move` 是**玩家本地坐标**：`y` = 前后（+1 前）、`x` = 左右（+1 右）——
///   原版 `player.xxa`（左右）/`zzz`（前后）同一口径
/// - `jump` = 原版 `KeyMapping` 的 `key.jump`（空格）
/// - `shift` / `sprint` = 原版 `key.shift` / `key.sprint`（本切片只用它们影响速度）
/// - `lookDelta` 是**这一帧转了多少**（鼠标位移，不是绝对角度），
///   与 `Player.applyLook` 的入参同一口径
class Input {
  Input();

  /// 本地移动意图：`x` 右为正，`y` 前为正（两者都在 [-1,1]）。
  final Vector2 move = Vector2.zero();

  /// 本帧的鼠标位移（右为正、下为正）。
  final Vector2 lookDelta = Vector2.zero();

  bool jump = false;
  bool shift = false;

  /// 加速（跑/飞）激活态 —— **切换式**，非按住式。
  ///
  /// 用户手感约定（2026-10-07）：Ctrl 按**一次**切换为激活，**松开移动键时取消**。
  /// 原版是按住式（`key.sprint` 的 `KeyMapping`），此处按产品需求改为 toggle，
  /// 是"玩家输入取自 Flutter"这处自由设计的范围内。
  ///
  /// 语义差异（相对原版）：原版松手 Ctrl 即停；本实现激活后一直保持到
  /// 移动键松开，好处是长距离奔跑/飞行不必一直按住 Ctrl。
  bool sprintToggle = false;

  /// 本帧是否**按下**了加速键（边沿事件，用于切换 [_sprintToggle]）。
  bool sprintPressed = false;

  /// 加速生效中。
  bool get sprint => sprintToggle;

  bool get isMoving => move.x != 0 || move.y != 0;

  /// 切换加速态（Ctrl 边沿）。[LocalPlayer] 每帧调用。
  void toggleSprint() {
    sprintToggle = !sprintToggle;
  }

  /// 加速键松开时收起激活态（用户约定：松开移动键取消激活）。
  ///
  /// 注意条件是"**移动键松开**"而非"Ctrl 松开"——Ctrl 是切换式，松开它不应
  /// 取消激活（否则又变回按住式）；真正取消的时机是玩家不再给移动输入。
  void clearSprintWhenNotMoving() {
    if (!isMoving) sprintToggle = false;
  }

  /// 一帧结束后清掉"消费型"输入（鼠标位移），按住的键保留（原版按键是持续状态）。
  void endFrame() => lookDelta.setZero();
}
