import 'package:flutter/material.dart';

import 'touch_key_button.dart';

/// 触控 hub 的按钮绑定（**纯回调数据类，无游戏逻辑**）。
///
/// 移动/跳/潜行是**持续语义**（down/up 两个沿，等价键位按下/抬起——与键盘
/// 进同一条 KeyMapping 路径，判据 in-game-screens / touch-input 能力）；
/// Esc / E 是**瞬时语义**（tap，对应原版 consumeClick 边沿）。
class TouchHubBindings {
  const TouchHubBindings({
    required this.onForward,
    required this.onBack,
    required this.onLeft,
    required this.onRight,
    required this.onJump,
    required this.onSneak,
    required this.onEscape,
    required this.onInventory,
  });

  /// 持续语义：down=true 按下 / false 抬起。
  final void Function(bool down) onForward;
  final void Function(bool down) onBack;
  final void Function(bool down) onLeft;
  final void Function(bool down) onRight;
  final void Function(bool down) onJump;

  /// 持续语义：潜行。
  final void Function(bool down) onSneak;

  /// 瞬时语义：Esc（开/关暂停菜单）。
  final VoidCallback onEscape;

  /// 瞬时语义：E（开/关物品栏）。
  final VoidCallback onInventory;
}

/// 触控控件 hub（**无 Java 对应物——输入事件采集自由设计**；按钮直接显示
/// **对应键盘键值**——W/A/S/D、Space、Shift、Esc、E——用户约定 2026-10-07：
/// 不用图形图标，按键值即语义）。
///
/// 布局：左下 D-pad（W/A/S/D）、右下 Space（上）/Shift（下）纵排 + E 在其左、
/// Esc 在顶部左。**尺寸固定**（用户约定 2026-10-07 第二次反馈：改回固定值，
/// 不做组件宽度断点——上一版按 `maxWidth/9` 放大的效果不好）。
///
/// 组件只做"手势 → 键位语义"翻译（[TouchHubBindings] 注入），MUST NOT 含游戏
/// 逻辑。**hub 不铺满拦截**：只有按钮本身 [TouchKeyButton.opaque] 吸指针，
/// 按钮之间/之外的指针穿透给场景层转视角。
class TouchHub extends StatelessWidget {
  const TouchHub({super.key, required this.bindings});

  final TouchHubBindings bindings;

  // 固定尺寸（逻辑像素；手机横屏 / 桌面窗口同一套）。
  // 62 → 42：用户约定 2026-10-07 连续两轮缩到 2/3。
  static const double _key = 42; // D-pad 键帽
  static const double _gap = 5; // 键距
  static const double _pad = 11; // 距屏幕边距

  @override
  Widget build(BuildContext context) {
    Widget keyBtn(String label, void Function(bool down) onEdge,
            {double? width, double? height}) =>
        TouchKeyButton(
          label: label,
          width: width ?? _key,
          height: height ?? _key,
          onDown: () => onEdge(true),
          onUp: () => onEdge(false),
        );

    Widget empty() => const SizedBox(width: _key, height: _key);

    Widget cell(Widget? w) => Padding(
          padding: const EdgeInsets.all(_gap / 2),
          child: w ?? empty(),
        );

    // —— 左下：D-pad（W/A/S/D，无中央键） ——
    final dpad = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          cell(null),
          cell(keyBtn('W', bindings.onForward)),
          cell(null),
        ]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          cell(keyBtn('A', bindings.onLeft)),
          cell(empty()),
          cell(keyBtn('D', bindings.onRight)),
        ]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          cell(null),
          cell(keyBtn('S', bindings.onBack)),
          cell(null),
        ]),
      ],
    );

    // —— 右下：Space（上）/ Shift（下）纵排 ——
    final moveCluster = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        keyBtn('Space', bindings.onJump, width: _key * 1.5),
        const SizedBox(height: _gap),
        keyBtn('Shift', bindings.onSneak, width: _key * 1.5),
      ],
    );

    return SafeArea(
      child: Stack(
        children: [
          // —— 顶部左：Esc ——
          Positioned(
            left: _pad,
            top: _pad * 0.5,
            child: TouchKeyButton(
              label: 'Esc',
              width: _key * 1.25,
              height: _key * 0.72,
              onDown: bindings.onEscape,
              // 瞬时语义：以"按下沿"触发一次；抬起沿给空操作。
              onUp: () {},
            ),
          ),
          // —— 左下：D-pad ——
          Positioned(left: _pad, bottom: _pad, child: dpad),
          // —— 右下：E + Space/Shift 纵排 ——
          Positioned(
            right: _pad,
            bottom: _pad,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                TouchKeyButton(
                  label: 'E',
                  width: _key * 0.9,
                  height: _key,
                  onDown: bindings.onInventory,
                  onUp: () {},
                ),
                const SizedBox(width: _gap),
                moveCluster,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
