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
- [ ] 3.3 **判定点**：若 3.1 实机视角跟手性不足（如边界处有明显延迟/跳变），再引入 `window_manager` 的 `setPointerLock()` 替换；否则不引依赖；验证：实机对比 + 决定是否改 `pubspec.yaml`
- [ ] 3.4 确认未引入任何新依赖（除 D3 判定为必要时）；验证：`git diff pubspec.yaml` 为空或仅含已论证的插件

## 4. 验收

- [ ] 4.1 全仓回归：`dart analyze` 零 issue + `flutter test` 全绿；验证：全绿
- [ ] 4.2 真机（Paper 26.2 + dart MCP）连续游玩 ≥10 分钟：切出/切回反复，键盘始终可用、无系统按键提示音、视角不失效；验证：实机观察 + 日志