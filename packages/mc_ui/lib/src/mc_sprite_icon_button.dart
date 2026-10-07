import 'package:flutter/material.dart';

import 'mc_face_painter.dart';

/// 原版 `gui/components/SpriteIconButton` 的 Flutter 对应
/// （判据 `PauseScreen.java:102-137`：`.width(20).sprite(icon, 15, 15)
/// .withTootip()` —— 20 宽方按钮、15×15 居中 sprite、带 tooltip）。
///
/// sprite 内容由调用方注入 child（**资产不入库**红线：官方贴图经资源抽象注入；
/// 资源管线补齐前用文字/占位图形）。可用/禁用语义与 [MCIconButton] 一致。
class MCSpriteIconButton extends StatefulWidget {
  const MCSpriteIconButton({
    super.key,
    required this.onPress,
    this.child,
    this.enabled = true,
    this.width = 20,
    this.height = 20,
    this.tooltip,
  });

  final VoidCallback? onPress;
  final Widget? child;
  final bool enabled;

  /// 判据 `.width(20)`（`PauseScreen.java:103/:114/:125/:133`）。
  final double width;
  final double height;

  /// 判据 `.withTootip()`（原版拼写如此）；无资产期用文字呈现。
  final String? tooltip;

  @override
  State<MCSpriteIconButton> createState() => _MCSpriteIconButtonState();
}

class _MCSpriteIconButtonState extends State<MCSpriteIconButton> {
  bool _pressed = false;

  bool get _effectiveEnabled => widget.enabled && widget.onPress != null;

  @override
  Widget build(BuildContext context) {
    final enabled = _effectiveEnabled;
    Widget button = ConstrainedBox(
      constraints: BoxConstraints.tightFor(
          width: widget.width, height: widget.height),
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTap: enabled ? widget.onPress : null,
        child: CustomPaint(
          painter: McFacePainter(enabled: enabled, pressed: _pressed),
          child: Center(child: widget.child),
        ),
      ),
    );
    if (widget.tooltip != null) {
      button = Tooltip(message: widget.tooltip!, child: button);
    }
    return button;
  }
}
