# Proposal

## Why

实机游玩时出现两个同源问题：**玩着玩着键盘与鼠标突然完全失效**，但点击 Flutter 调试按钮仍有动画；且**按任何键macOS 都会发出"无效键盘输入"的提示音**（无论当时能否控制游戏）。根因是同一个：`game_screen` 的 `KeyboardListener` 只依赖 `autofocus: true`，从不主动管理焦点——窗口失焦后 macOS 不再投递 KeyUp，`KeyMap` 维护的 `_pressed` 集合永久卡在"按下"态（这同时解释了提示音：有 keyDown 无 keyUp 配对）。鼠标走独立的 `Listener` 通路，所以按钮仍可点，这正是"键盘失效但按钮正常"的原因。

## What Changes

- **失焦即清空按键状态**：监听 `AppLifecycleState`（`inactive`/`paused`/`hidden`/`detached`），进入这些状态时清空 `_pressed` 并重置帧内消费型输入。这消除"卡住的按键"与 macOS 提示音。
- **点击即抢回焦点**：游戏区内任意点击（而非仅可交互控件）主动 `requestFocus` 回 `_focus`，使失焦后无需切窗口即可恢复。
- **指针锁定**：进入游戏后锁定鼠标指针到窗口内并隐藏光标，`Esc` 解除；解除时同步清空按键状态（对应原版 `mouseHandler.releaseMouse()` 语义）。这是"视角控制能持续生效"的前提，也避免光标跑出窗口导致 `onPointerMove` 相对位移失真。

**优先 Flutter 原生**：先用 `AppLifecycleState` + `FocusNode.requestFocus` + `MouseRegion`/`PointerBinding` 的原生能力实现。仅当原生无法满足"指针锁定"时，才引入 `window_manager` 插件——该依赖尚不存在，属于按需引入而非默认。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `player-input`: 新增"失焦不残留按键"与"指针捕获"两项契约——视角与移动输入的上报不得因失焦而失真。

## Impact

- `lib/game/game_screen.dart`（生命周期监听、点击抢焦点、指针锁定、按键状态清理）
- `lib/game/key_map.dart`（可能需要暴露"清空已按下集合"的能力，供失焦时复位）
- `pubspec.yaml`：**仅在原生指针锁定不可行时**才增 `window_manager`；其余不改
- 不改协议与包边界（纯 app 壳输入层）