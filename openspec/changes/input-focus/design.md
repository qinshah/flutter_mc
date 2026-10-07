# Design

## Context

见 proposal.md - Why。此处只记录**验证过的能力边界**，因为它决定了方案分界。

实测结论（`flutter/packages/flutter/lib/src` 全树搜索）：
- **Flutter 框架无指针锁定 API** —— 搜不到 `PointerLock` / `pointerLock` / `lockPointer`。
  `MouseRegion` 只提供进入/悬停/滚轮/退出回调，不含指针捕获。
- **`AppLifecycleState` 原生可用** —— `services/binding.dart` 确认状态机含
  `resumed / inactive / hidden / paused / detached`，其中 `resumed → inactive`
  正是 macOS 窗口失焦的信号。这是清理按键的可靠依据，无需插件。

现状代码：`game_screen.dart` 第 603-608 行 `KeyboardListener(focusNode: _focus, autofocus: true, …)`
嵌套 `Listener(onPointerMove: …)`。`_pressed` 集合由 `KeyMap.update` 维护，只在收到 KeyUp 时移除。

## 判据清单（审查门禁必需，进入实现前已核对）

| 判据 | 位置 | 用到的地方 |
|---|---|---|
| `grabMouse()` 只在窗口活跃时抓指针、抓后指针回中心 | `MouseHandler.java:404-417` | 指针捕获的实现语义 |
| `releaseMouse()` 解除并把指针位置记为窗口中心 | `MouseHandler.java:422-428` | `Esc` 解除路径 |
| `RESTORE_KEY_STATE_AFTER_MOUSE_GRAB = !ON_OSX` | `InputQuirks.java:11` | **macOS 原版不重置按键**——见 D1 的修正 |
| `KeyMapping.setAll()` / `releaseAll()` | `KeyMapping.java:47` / `:57` | 失焦时清按键的**语义对应物**（非逐行） |
| `cursorEntered()` 置 `ignoreFirstMove` | `MouseHandler.java:430` | 重新进入窗口时不产生视角跳变 |

**重要修正（推翻原 design 的一处判断）**：原以为"抓鼠标时原版会重置按键状态
（`RESTORE_KEY_STATE_AFTER_MOUSE_GRAB`）"，但该常量为 `!ON_OSX` ⇒ **macOS 原版明确
不做**。所以我们的"失焦清按键"不是照抄这一处，而是补macOS 平台原版同样存在的
"失焦后收不到 KeyUp"缺口——它属于**平台差异**（原版 GLFW 在 macOS 上也会丢 KeyUp，
但原版靠 `KeyMapping.releaseAll()` 在别处兜住），落在纪律允许的自由设计范围内，
但**语义仍照原版**：清空全部按键状态。

## Goals / Non-Goals

- 目标：失焦即清空按键与未消费输入（消除卡键与系统提示音），**用Flutter 原生**。
- 目标：点击游戏区即恢复键盘焦点，**用 Flutter 原生**。
- 目标：指针捕获（锁鼠标、藏光标、`Esc` 解除）—— 原生不可行时才引插件。
- 非目标：不实现原版的连续输入捕获 API（`MouseHandler.releaseMouse` 的服务端协同）——本项目无指针锁定服务端语义。

## Decisions

- **D1 失焦清键用 `AppLifecycleState`，不引插件**。在 `initState` 挂
  `WidgetsBindingObserver`，`didChangeAppLifecycleState` 里遇到 `inactive/paused/hidden/detached`
  即调`KeyMap.clear(_pressed)` + `_input.endFrame()` + 同步一次 `sendInputFlags`（全松开）。
  *备选*：`RawKeyboard.instance` 的按键集合。**否决**——它同样依赖 KeyUp，
  失焦时一样漏收，解决不了根因。
- **D2 点击抢焦点用 `GestureDetector` 包游戏区**。在 `SceneView` 之上铺一层
  `Listener(behavior: translucent, onPointerDown: (_) => _focus.requestFocus())`，
  覆盖整屏。*备选*：`FocusScope`/`FocusTraversalGroup` 自动焦点。**否决**——它们仍需先有
  一次焦点进入事件，对"点了空白区"不生效。
- **D3 指针捕获：先用原生近似，不满足才引 `window_manager`**。
  原生可行方案：当指针离开窗口边界（`onPointerHover` 收不到事件即视为离开）时，
  **把相对位移反向补偿回中心**（经典"虚拟光标锁"），实现零依赖的捕获手感。
  *判定标准*：若此方案在实机验收中视角跟手性不足（例如边界处有明显延迟感），
  再引 `window_manager.setPointerLock()`（macOS 有原生 `CGAssociateMouseAndMouseCursorPosition`）。
  这是**唯一可能新增的依赖**，且仅在 D3 原生方案实测不达标时才引入。
  *语义对照*：原版 `grabMouse()`（`MouseHandler.java:404`）做三件事——指针移回窗口
  中心、记录`ignoreFirstMove`（避免回中那一下产生视角跳变）、关闭屏幕 GUI。
  原生方案 MUST 覆盖前两件（回中补偿 + 忽略第一次移动），第三件在我们这里天然成立。
- **D4 `Esc` 解除捕获**。`Esc` 在 macOS 上是系统级"退出全屏"键，Flutter 仍能收到
  `KeyDownEvent`；在 `_onKey` 里识别 `escape` 解除捕获并清键（与 D1 共用清理函数）。

## Risks / Trade-offs

- [`inactive` 在部分平台也会因通知中心/控制中心弹出而短暂触发，导致误清键]
  → 误清的后果是"松手"，最坏是玩家停一下，不会产生卡键；可接受。实机确认 macOS 上
  是否会被系统面板误触发。
- [D3 的虚拟光标补偿在窗口很大时边界处会有"回中"跳变] → 补偿量按越界深度逐帧限幅，
  并在 `_trace` 下打点核对。
- [`_pressed` 清空后，若失焦期间玩家实际按了键，切回后第一帧可能读到"仍按住"]
  → 切回时（`resumed`）同样清一次，等玩家重新按下。

## Migration Plan

纯 app 壳改动。仅当 D3 判定引入插件时才动 `pubspec.yaml`，回滚 = 移依赖 + 单文件 revert。

## Open Questions

D3 的"原生虚拟光标锁是否够用"需要实机手感判定，属验收期决策，不影响 spec 与其余任务拆分。
若验收不过，追加一个子任务引`window_manager`。