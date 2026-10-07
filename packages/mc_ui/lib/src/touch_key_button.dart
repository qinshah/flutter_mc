import 'package:flutter/material.dart';

/// 触控按钮（**无 Java 对应物——输入事件采集自由设计**，Java 版无触屏 UI；
/// 外观按用户新触控 UI 图：半透明深底 + 白色描边圆角矩形 + 白色单色内容）。
///
/// **为什么用 [Listener] 而不是 GestureDetector**（判据 fscraft
/// `touch_hud.dart:16-21` 注释）：Listener 直接吃原始指针事件、不参与手势
/// 竞技场——多点触控下多个按钮可**同时**按住，且不会因轻微移动被判成拖拽丢事件。
/// `HitTestBehavior.opaque` 把落在本控件上的指针吸住，不再穿透场景层转视角。
///
/// **按下语义由调用方注入**（onDown/onUp 对应"按下/抬起"两个沿），本控件
/// 不含任何游戏逻辑（判据同 fscraft TouchHud："只做手势→输入的翻译"）。
class TouchKeyButton extends StatefulWidget {
  const TouchKeyButton({
    super.key,
    required this.label,
    required this.onDown,
    required this.onUp,
    this.width = 56,
    this.height = 48,
  });

  /// 按钮内容文字（触控图口径：Esc / F3 / T / E / ▲ / ◆ 等；贴图资源
  /// 补齐后换成单色图标）。
  final String label;

  /// 按下沿（等价键位 down）。
  final VoidCallback onDown;

  /// 抬起沿（等价键位 up）；控件被移出树时也会触发（防按键卡死）。
  final VoidCallback onUp;

  final double width;
  final double height;

  @override
  State<TouchKeyButton> createState() => _TouchKeyButtonState();
}

class _TouchKeyButtonState extends State<TouchKeyButton> {
  bool _down = false;

  @override
  void dispose() {
    // 控件销毁时若还按着，必须补一次抬起沿——否则键位集合里永久残留。
    if (_down) widget.onUp();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) {
        if (!_down) {
          _down = true;
          widget.onDown();
        }
      },
      onPointerUp: (_) {
        if (_down) {
          _down = false;
          widget.onUp();
        }
      },
      onPointerCancel: (_) {
        if (_down) {
          _down = false;
          widget.onUp();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        width: widget.width,
        height: widget.height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          // **空闲透明**（用户约定 2026-10-07：按下才显半透明底），白描边常显。
          color: _down
              ? const Color(0x66FFFFFF) // 按下：半透明提亮（可见反馈）
              : Colors.transparent,
          border: Border.all(
            color: Colors.white.withValues(alpha: _down ? 1.0 : 0.7),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          widget.label,
          maxLines: 1,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            height: 1.0,
            decoration: TextDecoration.none,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
