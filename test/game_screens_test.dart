import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_mc/client/gui/gui.dart';
import 'package:flutter_mc/client/gui/screens/screen.dart';
import 'package:flutter_mc/client/mouse_handler.dart';
import 'package:flutter_mc/game/key_map.dart';
import 'package:flutter_mc/world/entity/player/input.dart';
import 'package:pointer_lock/pointer_lock.dart';

/// game-screens-touch-input 的黄金序列测试。
///
/// 断言的是**判据的调用顺序**（照 mc-sources 行号），不是"我们的实现行为"——
/// 测试失败时先怀疑实现、改实现去对齐这里的顺序。

void main() {
  // pointer_lock 在测试环境无平台实现：注入假平台（isSupported=false ⇒
  // capture/release 为 no-op），避免 MissingPluginException 异步抛出。
  setUp(() {
    PointerLockPlatform.instance = _FakePlatform();
  });

  group('Gui.setScreen 黄金序列（判据 Gui.java:235-284）', () {
    late List<String> calls;
    late RecordingMouseHandler mouse;
    late Gui gui;

    setUp(() {
      calls = [];
      mouse = RecordingMouseHandler(calls);
      gui = Gui(
        mouseHandler: mouse,
        releaseAllKeys: () => calls.add('releaseAllKeys'),
        restoreToggleStatesOnScreenClosed: () => calls.add('restoreToggles'),
        guiScaledSize: () => (width: 320, height: 240),
        disconnectFromWorld: () {},
      );
      mouse.gui = gui;
    });

    test('开屏：releaseMouse → releaseAllKeys → added → init', () {
      final screen = RecordingScreen(calls);
      gui.setScreen(screen);
      // 判据顺序 `Gui.java:269-272`（releaseMouse :270 → releaseAll :271 →
      // init :272；added 在 :266 赋值后立即调，先于 release 分支）。
      expect(calls, ['added', 'releaseMouse', 'releaseAllKeys', 'init']);
      expect(gui.screen(), same(screen));
    });

    test('关屏：removed → restoreToggles → grabMouse', () {
      final screen = RecordingScreen(calls);
      gui.setScreen(screen);
      calls.clear();
      gui.setScreen(null);
      // 判据顺序 `Gui.java:241`（旧屏 removed）→ `:276`（restoreToggles）→
      // `:280`（grabMouse）。
      expect(calls, ['removed', 'restoreToggles', 'grabMouse']);
      expect(gui.screen(), isNull);
    });

    test('换屏：旧屏 removed → 新屏 added → release 路径', () {
      gui.setScreen(RecordingScreen(calls));
      calls.clear();
      final b = RecordingScreen(calls);
      gui.setScreen(b);
      expect(calls, ['removed', 'added', 'releaseMouse', 'releaseAllKeys', 'init']);
      expect(gui.screen(), same(b));
    });

    test('Esc 走 Screen.keyPressed → onClose → setScreen(null)', () {
      final screen = RecordingScreen(calls);
      gui.setScreen(screen);
      calls.clear();
      final handled = screen.keyPressed(const KeyDownEvent(
        logicalKey: LogicalKeyboardKey.escape,
        physicalKey: PhysicalKeyboardKey.escape,
        timeStamp: Duration.zero,
      ));
      expect(handled, isTrue); // 判据 `Screen.java:127-131`
      expect(calls, ['removed', 'restoreToggles', 'grabMouse']);
    });
  });

  group('MouseHandler 点击重捕获（判据 MouseHandler.java:80-88）', () {
    test('无屏 + 未捕获 + 按下 → grabMouse', () async {
      final calls = <String>[];
      final mouse = RecordingMouseHandler(calls);
      final gui = Gui(
        mouseHandler: mouse,
        releaseAllKeys: () {},
        restoreToggleStatesOnScreenClosed: () {},
        guiScaledSize: () => (width: 320, height: 240),
        disconnectFromWorld: () {},
      );
      mouse.gui = gui;
      expect(mouse.onButton(true), isTrue);
      await Future<void>.delayed(Duration.zero); // unawaited(grabMouse) 落地
      expect(calls.contains('grabMouse'), isTrue);
      expect(mouse.isMouseGrabbed(), isTrue);
    });

    test('已捕获时再按下不重复 grab（:406 幂等）', () async {
      final calls = <String>[];
      final mouse = RecordingMouseHandler(calls);
      final gui = Gui(
        mouseHandler: mouse,
        releaseAllKeys: () {},
        restoreToggleStatesOnScreenClosed: () {},
        guiScaledSize: () => (width: 320, height: 240),
        disconnectFromWorld: () {},
      );
      mouse.gui = gui;
      mouse.onButton(true);
      await Future<void>.delayed(Duration.zero);
      calls.clear();
      expect(mouse.onButton(true), isFalse);
      expect(calls, isEmpty);
    });
  });

  group('触控按钮与键盘等价（touch-input spec：同一条 KeyMapping 路径）', () {
    test('虚拟按下 W+空格 的 Input 与键盘路径完全一致', () {
      final viaTouch = Input();
      final viaKeyboard = Input();

      // 触控路径：按钮 down/up → 集合 add/remove（app 壳 _setVirtualKey 的同款逻辑）。
      final touchPressed = <LogicalKeyboardKey>{};
      touchPressed.add(LogicalKeyboardKey.keyW);
      touchPressed.add(LogicalKeyboardKey.space);
      KeyMap.apply(touchPressed, viaTouch);

      // 键盘路径：KeyMap.update 事件流。
      final kbPressed = <LogicalKeyboardKey>{};
      KeyMap.update(kbPressed, const KeyDownEvent(
        logicalKey: LogicalKeyboardKey.keyW,
        physicalKey: PhysicalKeyboardKey.keyW,
        timeStamp: Duration.zero,
      ));
      KeyMap.update(kbPressed, const KeyDownEvent(
        logicalKey: LogicalKeyboardKey.space,
        physicalKey: PhysicalKeyboardKey.space,
        timeStamp: Duration.zero,
      ));
      KeyMap.apply(kbPressed, viaKeyboard);

      expect(viaTouch.move.y, viaKeyboard.move.y); // 前
      expect(viaTouch.jump, viaKeyboard.jump); // 跳
      expect(viaTouch.move.y, 1);
      expect(viaTouch.jump, isTrue);

      // 抬起后同样归零（按钮 up = 键盘 keyUp）。
      touchPressed.remove(LogicalKeyboardKey.keyW);
      KeyMap.apply(touchPressed, viaTouch);
      kbPressed.remove(LogicalKeyboardKey.keyW);
      KeyMap.apply(kbPressed, viaKeyboard);
      expect(viaTouch.move.y, 0);
      expect(viaTouch.move.y, viaKeyboard.move.y);
    });
  });
}

/// 记录调用序的 MouseHandler（假平台下走 super：grab/release 的
/// `_mouseGrabbed` 状态转移是被测语义的一部分，不能替身掉）。
class RecordingMouseHandler extends MouseHandler {
  RecordingMouseHandler(this.calls)
      : super(isWindowActive: () => true, onLookDelta: (_, _) {});

  final List<String> calls;

  @override
  Future<void> grabMouse() async {
    calls.add('grabMouse');
    await super.grabMouse(); // pointer_lock 为 no-op 假平台；递归 setScreen(null) 幂等
  }

  @override
  Future<void> releaseMouse() async {
    calls.add('releaseMouse');
    await super.releaseMouse();
  }
}

/// 记录调用序的 Screen。
class RecordingScreen extends Screen {
  RecordingScreen(this.calls) : super('测试屏');

  final List<String> calls;

  @override
  void added() => calls.add('added');

  @override
  void removed() => calls.add('removed');

  @override
  void init(int width, int height) => calls.add('init');

  @override
  Widget buildWidget(BuildContext context) => const SizedBox.shrink();
}

final class _FakePlatform extends PointerLockPlatform {
  @override
  bool get isSupported => false;

  @override
  Stream<Offset> get deltas => const Stream.empty();

  @override
  Stream<CaptureState> get stateChanges => const Stream.empty();

  @override
  Future<void> capture() async {}

  @override
  Future<void> release() async {}

  @override
  Future<void> reset() async {}
}
