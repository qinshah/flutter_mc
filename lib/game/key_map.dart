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
  static void apply(Set<LogicalKeyboardKey> pressed, InputState input) {
    input
      ..move.y = (_held(pressed, forward) ? 1 : 0) - (_held(pressed, back) ? 1 : 0)
      ..move.x = (_held(pressed, right) ? 1 : 0) - (_held(pressed, left) ? 1 : 0)
      ..jump = _held(pressed, jump)
      ..sneak = _held(pressed, sneak)
      ..sprint = _held(pressed, sprint);
  }

  static bool _held(Set<LogicalKeyboardKey> pressed, List<LogicalKeyboardKey> keys) =>
      keys.any(pressed.contains);
}
