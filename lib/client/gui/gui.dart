import 'package:flutter/foundation.dart' show VoidCallback;

import '../mouse_handler.dart';
import 'screens/screen.dart';
import 'screens/pause_screen.dart';

/// `net/minecraft/client/gui/Gui.java` 的 Dart 对应物（本 change 用到的语义子集：
/// 单槽位 screen 状态 + setScreen 的捕获/按键清空调用时序 + pauseGame）。
///
/// 原版 Gui 持有 `Minecraft`；本仓把被依赖项收窄为构造期注入的三件：
/// [mouseHandler]（`this.minecraft.mouseHandler` 对应）、[releaseAllKeys]
/// （`KeyMapping.releaseAll()` 对应——按键集合由输入采集层持有，见 key_map）、
/// [restoreToggleStatesOnScreenClosed]（`KeyMapping.restoreToggleStatesOnScreenClosed`
/// 对应，判据 `KeyMapping.java:63-69`：切屏关闭时恢复"切换式按键"的激活态，
/// 本仓对应 sprint toggle）。
///
/// **判据（`Gui.java`）**：
/// - `:231-233` `screen()` 可空查询（`KeyboardHandler.java:516` 用它门控游戏输入）；
/// - `:235-284` `setScreen`：旧屏 `removed()`（:240-241）→ 赋值 `this.screen`
///   （:264）→ 新屏 `added()`（:265-267）→ 非空走 releaseMouse + releaseAll +
///   `screen.init(w, h)`（:269-272）；空走 stopTextInput + 恢复切换态按键 +
///   声音恢复 + grabMouse（:273-281）。
/// - `:318-325` `setPauseScreen`：仅 `screen == null` 时开 `PauseScreen`；
///   联机（无单人服务器）`canGameReallyBePaused = false`（`Minecraft.java:1671`）
///   ⇒ 恒 `PauseScreen(true)`。
class Gui {
  Gui({
    required this.mouseHandler,
    required this.releaseAllKeys,
    required this.restoreToggleStatesOnScreenClosed,
    required this.guiScaledSize,
    required this.disconnectFromWorld,
    this.onChanged,
  });

  final MouseHandler mouseHandler;

  /// `KeyMapping.releaseAll()` 的对应物（判据 `KeyMapping.java:57-61`）。
  final VoidCallback releaseAllKeys;

  /// `KeyMapping.restoreToggleStatesOnScreenClosed()` 的对应物
  /// （判据 `KeyMapping.java:63-69`）。
  final VoidCallback restoreToggleStatesOnScreenClosed;

  /// GUI 缩放尺寸（原版 `getWindow().getGuiScaledWidth/Height`，
  /// `:272` `screen.init(...)` 的入参）。
  final ({int width, int height}) Function() guiScaledSize;

  /// `Minecraft.disconnectFromWorld` 的对应物（PauseScreen 断开按钮用，
  /// 判据 `PauseScreen.java:171` `disconnectFromWorld(...)`）。
  final VoidCallback disconnectFromWorld;

  /// 屏幕变化通知（原版 GUI 每帧重绘 screen；Flutter 侧由宿主 setState——
  /// 渲染后端差异的对应物，不改变 setScreen 的调用时序）。
  final VoidCallback? onChanged;

  Screen? _screen;

  /// 当前屏幕（判据 `:231-233`；null = 游戏中）。
  Screen? screen() => _screen;

  /// 打开/关闭屏幕（判据 `:235-284`）。
  void setScreen(Screen? screen) {
    // :240-244 旧屏离屏 / 输入类型复位（setLastInputType——Flutter 侧无对应，
    // 输入来源检测由触控能力独立完成，不依赖该字段）。
    if (_screen != null) {
      _screen!.removed();
    }
    // :246-262 screen == null 的兜底分支：原版按 level/player 状态回 TitleScreen
    // / DeathScreen / 聊天屏。本仓联机、玩家存活 ⇒ 维持 null（死亡屏另行 change；
    // 断线走会话事件而非本分支）。
    _screen = screen; // :264
    if (_screen != null) {
      _screen!.gui = this; // 原版 Screen 构造即持 minecraft；此处在赋值后回填。
      _screen!.added(); // :265-267
    }

    if (screen != null) {
      mouseHandler.releaseMouse(); // :270
      releaseAllKeys(); // :271 `KeyMapping.releaseAll()`
      final size = guiScaledSize();
      _screen!.init(size.width, size.height); // :272
    } else {
      // :274 `textInputManager().stopTextInput()` —— 文本输入管理器未实现（债，
      // 聊天屏属后续 change）。
      restoreToggleStatesOnScreenClosed(); // :276
      // :279 `soundManager.resume()` —— 无音频子系统（债）。
      mouseHandler.grabMouse(); // :280
    }
    // :283 `updateTitle()` —— 窗口标题管理未实现（债）。
    onChanged?.call();
  }

  /// 打开暂停菜单（判据 `:318-325` `setPauseScreen` + `Minecraft.java:1670-1673`
  /// `pauseGame`）。
  ///
  /// [suppressPauseMenu] 对应 `suppressPauseMenuIfWeReallyArePausing`（调试键
  /// 语义）。本仓联机 ⇒ `canGameReallyBePaused = false`（`Minecraft.java:1671`
  /// `hasSingleplayerServer() && !isPublished()`，无单人服务器 ⇒ false）
  /// ⇒ 恒 `PauseScreen(true)`（showPauseMenu）。已有屏幕时 MUST NOT 重复开
  /// （原版仅 `screen == null` 时生效）。
  void pauseGame({bool suppressPauseMenu = false}) {
    if (_screen != null) return; // :319
    // :322 联机分支：canGameReallyBePaused=false → new PauseScreen(true)。
    setScreen(PauseScreen(disconnectFromWorld, showPauseMenu: true));
  }
}
