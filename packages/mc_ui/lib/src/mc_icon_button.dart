import 'package:flutter/material.dart';

import 'mc_face_painter.dart';

/// 原版 `gui/components/ImageButton` 形态的方形小按钮：内容 [child]
/// 由调用方注入（本期为占位图标；资源管线接入后注入贴图）。
/// 与 [MCButton] 相同的可用/禁用语义。
class MCIconButton extends StatefulWidget {
  const MCIconButton({
    super.key,
    required this.onPress,
    this.child,
    this.enabled = true,
    this.size = 20,
  });

  final VoidCallback? onPress;
  final Widget? child;
  final bool enabled;
  final double size;

  @override
  State<MCIconButton> createState() => _MCIconButtonState();
}

class _MCIconButtonState extends State<MCIconButton> {
  bool _pressed = false;

  bool get _effectiveEnabled => widget.enabled && widget.onPress != null;

  @override
  Widget build(BuildContext context) {
    final enabled = _effectiveEnabled;
    return ConstrainedBox(
      constraints: BoxConstraints.tightFor(width: widget.size, height: widget.size),
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
  }
}
