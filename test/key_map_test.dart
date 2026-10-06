import 'package:flutter/services.dart';
import 'package:flutter_mc/game/input_state.dart';
import 'package:flutter_mc/game/key_map.dart';
import 'package:flutter_test/flutter_test.dart';

/// tasks 3.2 的输入半边：键位映射（原版 KeyMapping）→ 移动意图。
///
/// 键映射抽在 `KeyMap` 里就是为了能这样测——不必起 GPU / SceneView。
void main() {
  InputState pressedInput(List<LogicalKeyboardKey> keys) {
    final input = InputState();
    KeyMap.apply(keys.toSet(), input);
    return input;
  }

  test('WASD：前/后/左/右各自映射到本地坐标的 y/x', () {
    expect(pressedInput([LogicalKeyboardKey.keyW]).move.y, 1);
    expect(pressedInput([LogicalKeyboardKey.keyS]).move.y, -1);
    expect(pressedInput([LogicalKeyboardKey.keyD]).move.x, 1);
    expect(pressedInput([LogicalKeyboardKey.keyA]).move.x, -1);
    expect(pressedInput([]).isMoving, isFalse);
  });

  test('方向键与 WASD 等价', () {
    expect(pressedInput([LogicalKeyboardKey.arrowUp]).move.y, 1);
    expect(pressedInput([LogicalKeyboardKey.arrowDown]).move.y, -1);
    expect(pressedInput([LogicalKeyboardKey.arrowRight]).move.x, 1);
    expect(pressedInput([LogicalKeyboardKey.arrowLeft]).move.x, -1);
  });

  test('反方向同按相互抵消（W+S 不走，A+D 不横移）', () {
    final opposite = pressedInput([LogicalKeyboardKey.keyW, LogicalKeyboardKey.keyS]);
    expect(opposite.move.y, 0);
    expect(opposite.isMoving, isFalse);

    final both = pressedInput([LogicalKeyboardKey.keyA, LogicalKeyboardKey.keyD]);
    expect(both.move.x, 0);
  });

  test('斜向：前+右同时成立（长度由控制器归一化，不在映射层）', () {
    final diagonal =
        pressedInput([LogicalKeyboardKey.keyW, LogicalKeyboardKey.keyD]);
    expect(diagonal.move.y, 1);
    expect(diagonal.move.x, 1);
  });

  test('空格跳、Shift 潜行、Ctrl 疾跑', () {
    expect(pressedInput([LogicalKeyboardKey.space]).jump, isTrue);
    expect(pressedInput([]).jump, isFalse);

    expect(pressedInput([LogicalKeyboardKey.shiftLeft]).sneak, isTrue);
    expect(pressedInput([LogicalKeyboardKey.shiftRight]).sneak, isTrue);
    expect(pressedInput([LogicalKeyboardKey.controlLeft]).sprint, isTrue);
    expect(pressedInput([LogicalKeyboardKey.controlRight]).sprint, isTrue);
  });

  group('按键集合维护（别名键同按不误停）', () {
    final pressed = <LogicalKeyboardKey>{};

    test('按下入集合、抬起出集合、重复事件不改变状态', () {
      expect(KeyMap.update(pressed, _down(LogicalKeyboardKey.keyW)), isTrue);
      expect(pressed, contains(LogicalKeyboardKey.keyW));
      // 长按的重复事件：集合里已有，不算变化。
      expect(KeyMap.update(pressed, _repeat(LogicalKeyboardKey.keyW)), isFalse);
      expect(KeyMap.update(pressed, _up(LogicalKeyboardKey.keyW)), isTrue);
      expect(pressed, isEmpty);
    });

    test('W 与 ↑ 同按：松开 ↑ 后仍朝前走', () {
      KeyMap.update(pressed, _down(LogicalKeyboardKey.keyW));
      KeyMap.update(pressed, _down(LogicalKeyboardKey.arrowUp));
      final input = InputState();
      KeyMap.apply(pressed, input);
      expect(input.move.y, 1);

      KeyMap.update(pressed, _up(LogicalKeyboardKey.arrowUp));
      KeyMap.apply(pressed, input);
      expect(input.move.y, 1, reason: 'W 还按着，不该停');
    });
  });
}

KeyDownEvent _down(LogicalKeyboardKey key) =>
    KeyDownEvent(physicalKey: PhysicalKeyboardKey.keyW, logicalKey: key, timeStamp: Duration.zero);

KeyRepeatEvent _repeat(LogicalKeyboardKey key) =>
    KeyRepeatEvent(physicalKey: PhysicalKeyboardKey.keyW, logicalKey: key, timeStamp: Duration.zero);

KeyUpEvent _up(LogicalKeyboardKey key) =>
    KeyUpEvent(physicalKey: PhysicalKeyboardKey.keyW, logicalKey: key, timeStamp: Duration.zero);
