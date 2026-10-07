import 'package:flutter/material.dart' show BuildContext, Widget;
import 'package:flutter/services.dart' show KeyEvent, LogicalKeyboardKey;

import '../gui.dart';

/// `net/minecraft/client/gui/screens/Screen.java` 的 Dart 对应物（本 change 用到的
/// 语义子集）。原版 Screen 是 GUI 屏幕基类：持有 `Minecraft`、标题、尺寸，
/// `keyPressed` 处理 Esc 关闭，`onClose` 回 `gui.setScreen(null)`。
///
/// **判据**（`Screen.java`）：
/// - `:127-131` `keyPressed`：`event.isEscape() && shouldCloseOnEsc()` → `onClose()`
///   并返回已消费；
/// - `:198-200` `shouldCloseOnEsc()` 默认 `true`；
/// - `:202-204` `onClose()` = `this.minecraft.gui.setScreen(null)`；
/// - `:82` `init(width, height)`；`:416` `added()`（进屏回调）；
///   `removed()`（离屏回调，`Gui.java:241` 调用）。
///
/// 差异：原版标题是 `Component`（i18n），本仓暂用中文字符串直取（资源抽象另行
/// 补齐，属 GUI 屏幕翻译债的组成部分）；`Minecraft` 引用收窄为 [gui]（会话装配
/// 时的等价物）。
abstract class Screen {
  Screen(this.title);

  /// 屏幕标题（原版 `Component title`，`Screen.java:82` 字段）。
  final String title;

  /// 宿主 Gui（原版 `this.minecraft` 的收窄对应物），进屏时由 [Gui] 回填。
  Gui? gui;

  /// GUI 缩放尺寸（原版 `this.width/height`，`init` 注入）。
  int width = 0;
  int height = 0;

  /// 进屏回调（判据 `Screen.java:416` `added()`，`Gui.java:266` 调用）。
  void added() {}

  /// 离屏回调（判据 `Screen.removed()`，`Gui.java:241` 调用）。
  void removed() {}

  /// 初始化（判据 `Screen.java` `init(width, height)`，`Gui.java:272` 调用）。
  void init(int width, int height) {
    this.width = width;
    this.height = height;
  }

  /// Esc 是否关闭本屏（判据 `Screen.java:198-200`）。
  bool shouldCloseOnEsc() => true;

  /// 关闭本屏（判据 `Screen.java:202-204`：`minecraft.gui.setScreen(null)`）。
  void onClose() {
    gui?.setScreen(null);
  }

  /// 键盘按下分发（判据 `Screen.java:127-131`）。
  ///
  /// 事件类型用 Flutter 的 [KeyEvent]（输入采集自由设计；语义——Esc → onClose
  /// 并标记已消费——照原版）。
  bool keyPressed(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.escape && shouldCloseOnEsc()) {
      onClose();
      return true;
    }
    return false;
  }

  /// 键盘抬起分发（判据 `KeyboardHandler.java:486` `screen.keyReleased(event)`——
  /// 原版 KeyUp 与 KeyDown 分流：KeyDown/Repeat → keyPressed、KeyUp → keyReleased；
  /// 缺了这条分流会把"松开 Esc"当成"再按一次 Esc"⇒ 菜单开完立刻关）。
  bool keyReleased(KeyEvent event) => false;

  /// 屏幕的 Flutter 呈现（原版 `extractRenderState` 渲染路径的对应物；
  /// app 壳在 `Gui.screen() != null` 时把它叠进 Stack。自由设计——渲染后端
  /// 用 Flutter 替代原版 GUI 绘制，布局数值仍照原版 GUI 像素）。
  Widget buildWidget(BuildContext context);
}
