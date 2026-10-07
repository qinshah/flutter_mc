import 'dart:async' show unawaited;
import 'dart:io' show Platform;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:pointer_lock/pointer_lock.dart';

import 'gui/gui.dart';

/// `net/minecraft/client/MouseHandler.java` 的 Dart 对应物（本 change 用到的
/// 语义子集：grabMouse / releaseMouse / 点击重捕获 / 相对位移消费）。
///
/// **环境差异**：原版经 GLFW `InputConstants.grabOrReleaseMouse`（212995 捕获 /
/// 212993 释放）实现真指针锁；Flutter 无此 API，故用 `pointer_lock` 替代
/// （macOS 原生捕获；`isSupported=false` 平台由 app 壳走原生近似降级——翻译债，
/// 见 `openspec/progress.md` §10）。**调用时机照原版，逐行对应**。
///
/// 判据：
/// - `:404-420` `grabMouse()`：仅窗口活跃时执行；`mouseGrabbed` 幂等；基准点
///   置屏幕中心；`ignoreFirstMove = true`；GLFW 212995；回 `gui.setScreen(null)`；
///   `missTime = 10000`（missTime 未实现——攻击节奏相关，债）。
/// - `:422-429` `releaseMouse()`：`mouseGrabbed = false`；GLFW 212993。
/// - `:80-88` 鼠标按键路径：无屏幕且未捕获时，**按下**即捕获。
/// - `:396-398` `setIgnoreFirstMove()`。
class MouseHandler {
  MouseHandler({required this.isWindowActive, required this.onLookDelta});

  /// 窗口是否活跃（判据 `:405` `minecraft.isWindowActive()` 的对应物；
  /// app 壳以"应用生命周期处于 resumed"为准注入）。
  final bool Function() isWindowActive;

  /// 视角增量出口（判据 `turnPlayer` 路径：`MouseHandler` 的累计位移 →
  /// `player.turn(dx, dy)`；app 壳把它加进 `Input.lookDelta`，换算公式在
  /// player-input 能力里已有判据，此处只搬运像素增量）。
  final void Function(double dx, double dy) onLookDelta;

  /// 宿主 Gui（原版经 `this.minecraft.gui` 间接持有；`:415` 回 setScreen(null)
  /// 用。装配点构造后回填——原版 Minecraft 对 Gui 与 MouseHandler 同为双向持有）。
  late Gui gui;

  bool _mouseGrabbed = false;

  /// 判据 `:397` `ignoreFirstMove`：捕获/回中那一下不算视角转动。
  bool _ignoreFirstMove = false;

  /// 是否走 pointer_lock 真捕获（`isSupported=false` 的平台由 app 壳降级）。
  bool get usesNativeLock => PointerLock.instance.isSupported;

  /// 指针捕获仅 PC 参与（**用户决策 2026-10-07：pointer_lock 只有 PC 需要，
  /// 移动端不接**）。移动端无鼠标指针，grabMouse/onButton 全部 no-op，
  /// 视角走触控拖动（采集自由设计）。
  static bool get _isDesktop =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  bool get isDesktop => _isDesktop;

  bool isMouseGrabbed() => _mouseGrabbed;

  /// 判据 `:404-420`。
  Future<void> grabMouse() async {
    if (!_isDesktop) return; // 移动端无指针捕获（用户决策，非原版行为差）
    if (!isWindowActive()) return; // :405
    if (_mouseGrabbed) return; // :406
    // :407-409 `RESTORE_KEY_STATE_AFTER_MOUSE_GRAB` → `KeyMapping.setAll()`：
    //   该 quirk 仅非 macOS（`InputQuirks.java:11`）；macOS 路径不重置按键，
    //   失焦缺口由 app 壳生命周期回调兜住（player-input 能力）。
    _mouseGrabbed = true; // :411
    // :412-413 基准点置屏幕中心（xpos/ypos 原版有字段；本仓该基准只被
    //   `drawDebugMouseInfo` 用，未实现——不引入未使用字段）。
    // :414 `InputConstants.grabOrReleaseMouse(window, 212995, ...)`。
    //   pointer_lock 捕获失败不抛（isSupported=false 时 no-op）。
    await PointerLock.instance.capture();
    // :415 `this.minecraft.gui.setScreen(null)` —— 递归但幂等（此时 screen 已为
    //   null，再次进入走 else 分支 → grabMouse → mouseGrabbed 已 true → 返回）。
    gui.setScreen(null);
    // :416 `missTime = 10000` —— missTime（攻击空挥计时）未实现，债。
    _ignoreFirstMove = true; // :417
  }

  /// 判据 `:422-429`。
  Future<void> releaseMouse() async {
    if (!_mouseGrabbed) return; // :423
    _mouseGrabbed = false; // :424
    // :425-427 基准点回中 + GLFW 212993。
    await PointerLock.instance.release();
  }

  /// 鼠标按键路径（判据 `:80-88`：`screen() == null` 且未捕获时，**按下**触发
  /// `grabMouse()`）。返回是否发生了捕获——app 壳据此让"重新捕获的那次点击"
  /// 不再下发为攻击/使用。
  bool onButton(bool pressed) {
    if (!_isDesktop) return false; // 移动端不参与捕获
    if (gui.screen() != null) return false; // :86 屏幕打开 → 交给屏幕处理
    if (!_mouseGrabbed && pressed) {
      // :84 —— 异步点火（原版同步；捕获是平台调用，等待返回不改变语义）。
      unawaited(grabMouse());
      return true;
    }
    return false;
  }

  /// 每帧取相对位移并送 [onLookDelta]（判据 `turnPlayer` 路径 + pointer_lock
  /// 的 pull 模型：固定步长里同步 `takeDelta` 一次）。真捕获平台取 pointer_lock
  /// 的累计增量；降级平台不动（app 壳走 onPointerMove 近似，勿双计）。
  void pollMovement() {
    if (!usesNativeLock) return;
    if (!_mouseGrabbed) return;
    if (_ignoreFirstMove) {
      _ignoreFirstMove = false;
      PointerLock.instance.takeDelta(); // 排掉回中那一下（`:417` ignoreFirstMove）
      return;
    }
    final d = PointerLock.instance.takeDelta();
    if (d != Offset.zero) {
      onLookDelta(d.dx, d.dy);
    }
  }

  /// 失焦/意外释放（`onStateChanged released`）后的状态复位。原版 GLFW 失焦
  /// 自动 `releaseMouse()`（`:406/422` 口径），此处等价收口。
  void onCaptureLostExternally() {
    if (!_mouseGrabbed) return;
    _mouseGrabbed = false;
    _ignoreFirstMove = false;
  }

  void dispose() {
    if (_mouseGrabbed) {
      unawaited(PointerLock.instance.release());
      _mouseGrabbed = false;
    }
  }
}
