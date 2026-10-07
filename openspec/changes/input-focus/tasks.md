# Tasks

## 1. 失焦清键（治键盘提示音与卡键）

- [x] 1.1 `key_map.dart`：新增 `static void clear(Set<LogicalKeyboardKey> pressed)` 清空当前按下的键；验证：`dart analyze` 零 issue
- [x] 1.2 `game_screen.dart`：实现 `WidgetsBindingObserver`，在 `didChangeAppLifecycleState`遇到 `inactive/paused/hidden/detached` 时清空 `_pressed`、`_input.endFrame()`、并同步一次全松开的 `sendInputFlags`；验证：单测或实机——失焦后不再产生移动上行
- [x] 1.3 `resumed`（切回）时同样清一次，避免切回瞬间读到失焦期间的"仍按住"；验证：实机——失焦期间按键、切回后不移动

## 2. 焦点恢复

- [x] 2.1 游戏区铺一层 `Listener(behavior: translucent, onPointerDown: (_) => _focus.requestFocus())` 覆盖整屏，点空白区也能取回焦点；验证：单测——点击后 `_focus.hasFocus` 为真
- [ ] 2.2 验证失焦 → 点游戏区 → 键盘立即可用；验证：实机截图 + 日志

## 3. 指针捕获（先原生，不达标才引插件）

- [x] 3.1 实现原生虚拟光标锁：指针移出窗口边界（`onPointerHover` 断流）时把相对位移反向补偿回中心，逐帧限幅避免跳变；`_trace` 下打点核对边界行为；验证：实机——指针移出窗口视角仍连续
- [x] 3.2 `Esc` 解除捕获并恢复光标（复用 1.1 的清键函数）；验证：实机——Esc 后光标可见且按键全松
- [x] 3.3 ~~**判定点**：若 3.1 实机视角跟手性不足，再引入 `window_manager`~~ ⇒
  **用户 2026-10-07 决定：鼠标捕获先不解决**（键盘提示音优先）。原生近似代码保留
  在 `game_screen.dart`（`_pointerCaptured` / `_ignoreNextMove` / `_handlePointerMove`），
  未引`window_manager`。真指针锁改列为后续债，不在本change验收范围。；验证：实机对比 + 决定是否改 `pubspec.yaml`
- [x] 3.4 确认未引入任何新依赖；验证：`git diff pubspec.yaml` 无输出 ✅

## 4. 验收

- [x] 4.1 全仓回归：`dart analyze` 零 issue + `flutter test` **56 项全绿**（含新增 2 项
  `releaseAll` 单测）
- [x] 4.2 真机验收：**系统"无效键盘输入"提示音已消失**（用户 2026-10-07 确认
  "声音没了"）。根因是 `KeyboardListener` 无条件 `return KeyEventResult.ignored`
  （`keyboard_listener.dart:77`）⇒ 事件按文档 "propagated to … even non-Flutter ones"
  漏回 macOS。改用 `Focus` + 返回 `handled` 阻断冒泡，语义对齐原版 GLFW 独占消费
  （判据 `KeyMapping.click/set`，`KeyMapping.java:30/34`）。
- [ ] 4.3 真机（**需用户**）：按住 W 切到别的应用再切回，确认不再自动前进且能立即
      重新按住 W（验证 `releaseAll` 那条路径）；此路径无法自动验证