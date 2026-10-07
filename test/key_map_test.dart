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

  test('空格跳、Shift 潜行（按住式）', () {
    expect(pressedInput([LogicalKeyboardKey.space]).jump, isTrue);
    expect(pressedInput([]).jump, isFalse);

    expect(pressedInput([LogicalKeyboardKey.shiftLeft]).sneak, isTrue);
    expect(pressedInput([LogicalKeyboardKey.shiftRight]).sneak, isTrue);
  });

  group('加速（Ctrl）为切换式：按一次激活、松开移动键取消', () {
    test('按下 Ctrl 产生边沿（sprintPressed），松开不产生', () {
      var prevHeld = false;
      final input = InputState();

      // 第一帧按下 ⇒ 边沿
      KeyMap.apply({LogicalKeyboardKey.controlLeft}, input,
          sprintPrevHeld: prevHeld);
      expect(input.sprintPressed, isTrue);
      input.toggleSprint();
      expect(input.sprint, isTrue);

      // 下一帧仍按着 ⇒ 无边沿（不重复切换）
      prevHeld = true;
      KeyMap.apply({LogicalKeyboardKey.controlLeft}, input,
          sprintPrevHeld: prevHeld);
      expect(input.sprintPressed, isFalse);
      expect(input.sprint, isTrue, reason: '按住期间保持激活');

      // 松开 Ctrl ⇒ 也不该取消（它是切换式，不是按住式）
      KeyMap.apply({}, input, sprintPrevHeld: prevHeld);
      expect(input.sprint, isTrue,
          reason: '松开 Ctrl 不取消激活——否则又变回按住式');
    });

    test('松开移动键取消激活', () {
      final input = InputState()
        ..move.y = 1
        ..toggleSprint();
      expect(input.sprint, isTrue);
      input.clearSprintWhenNotMoving();
      expect(input.sprint, isTrue, reason: '仍在移动 ⇒ 保持激活');

      input.move.y = 0; // 松开 W
      input.clearSprintWhenNotMoving();
      expect(input.sprint, isFalse, reason: '松开移动键 ⇒ 取消激活');
    });
  });

  group('releaseAll（失焦清键；判据 KeyMapping.releaseAll）', () {
    test('清空全部按下的键，返回是否真的清掉了东西', () {
      final pressed = <LogicalKeyboardKey>{
        LogicalKeyboardKey.keyW,
        LogicalKeyboardKey.controlLeft,
      };
      expect(KeyMap.releaseAll(pressed), isTrue);
      expect(pressed, isEmpty);
      // 已经空了 ⇒ 返回 false（调用方据此跳过重算）
      expect(KeyMap.releaseAll(pressed), isFalse);
    });

    test('releaseAll 后移动意图归零（失焦不再产生前进上行）', () {
      final pressed = <LogicalKeyboardKey>{LogicalKeyboardKey.keyW};
      final input = InputState();
      KeyMap.apply(pressed, input);
      expect(input.isMoving, isTrue,
          reason: '判据：releaseAll 语义是把键视为【松开】，不是忽略');

      KeyMap.releaseAll(pressed);
      KeyMap.apply(pressed, input);
      expect(input.isMoving, isFalse);
      expect(input.jump, isFalse);
      expect(input.sneak, isFalse);
      expect(input.sprint, isFalse,
          reason: '失焦时加速（切换式）也应回到未激活');
    });
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
