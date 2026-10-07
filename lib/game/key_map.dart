import 'package:flutter/services.dart';

import 'input_state.dart';

/// 按键 → 移动意图的映射（键位照原版 `client.KeyMapping`）。
///
/// 单独成文件是为了**可测**：本文件不碰引擎、不碰会话，`flutter_test` 里就能验证
/// "W/↑ 前、S/↓ 后、A/← 左、D/→ 右、空格跳、Shift 潜行、Ctrl 疾跑"，
/// 不必起 GPU/SceneView。
class KeyMap {
  static const List<LogicalKeyboardKey> forward = [
    LogicalKeyboardKey.keyW,
    LogicalKeyboardKey.arrowUp,
  ];
  static const List<LogicalKeyboardKey> back = [
    LogicalKeyboardKey.keyS,
    LogicalKeyboardKey.arrowDown,
  ];
  static const List<LogicalKeyboardKey> left = [
    LogicalKeyboardKey.keyA,
    LogicalKeyboardKey.arrowLeft,
  ];
  static const List<LogicalKeyboardKey> right = [
    LogicalKeyboardKey.keyD,
    LogicalKeyboardKey.arrowRight,
  ];
  static const List<LogicalKeyboardKey> jump = [LogicalKeyboardKey.space];
  static const List<LogicalKeyboardKey> sneak = [
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
  ];
  static const List<LogicalKeyboardKey> sprint = [
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
  ];

  /// 清空"当前按住的键"集合（判据 `KeyMapping.releaseAll()`，`KeyMapping.java:57`）。
  ///
  /// **为什么需要**：macOS 窗口失焦后不再投递 KeyUp ⇒ `_pressed` 里的键永久卡在
  /// "按下"态（这同时解释了系统"无效按键"提示音：有 keyDown 无 keyUp 配对）。
  /// 原版靠 GLFW 之外的路径兜住这个缺口；我们 MUST 自己清。
  ///
  /// 语义照原版 `releaseAll()`：把全部按键视为**松开**（不是"忽略"，是**释放**）。
  /// 返回是否真的清掉了什么，供调用方决定是否需要重算输入。
  static bool releaseAll(Set<LogicalKeyboardKey> pressed) {
    if (pressed.isEmpty) return false;
    pressed.clear();
    return true;
  }

  /// 维护"当前按住的键"集合。返回是否真的发生了变化（重复事件不算）。
  static bool update(Set<LogicalKeyboardKey> pressed, KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      return pressed.add(event.logicalKey);
    }
    if (event is KeyUpEvent) {
      return pressed.remove(event.logicalKey);
    }
    return false;
  }

  /// 由**按键集合**重算移动意图。
  ///
  /// 用集合而不是"按下加、抬起减"，是为了让别名键（W 与 ↑）同按时，
  /// 松开其中一个不会把意图误清零。
  ///
  /// [sprintPrevHeld] 是**上一帧**Ctrl 是否按着，用于取边沿——加速是**切换式**
  /// （按一次激活，松开移动键取消，见 [InputState.sprintToggle]），需要"新按下"事件。
  static void apply(
    Set<LogicalKeyboardKey> pressed,
    InputState input, {
    bool sprintPrevHeld = false,
  }) {
    final sprintHeld = _held(pressed, sprint);
    input
      ..move.y = (_held(pressed, forward) ? 1 : 0) - (_held(pressed, back) ? 1 : 0)
      ..move.x = (_held(pressed, right) ? 1 : 0) - (_held(pressed, left) ? 1 : 0)
      ..jump = _held(pressed, jump)
      ..sneak = _held(pressed, sneak)
      // 边沿：这一帧按下、上一帧没按 ⇒ 切换激活态。
      ..sprintPressed = sprintHeld && !sprintPrevHeld
      ..sprintToggle = input.sprintToggle;
  }

  /// 取当前 Ctrl 是否按着（供下一帧做边沿比较）。
  static bool sprintHeld(Set<LogicalKeyboardKey> pressed) =>
      _held(pressed, sprint);

  static bool _held(Set<LogicalKeyboardKey> pressed, List<LogicalKeyboardKey> keys) =>
      keys.any(pressed.contains);
}
