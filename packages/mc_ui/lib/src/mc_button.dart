import 'package:flutter/material.dart';

import 'mc_face_painter.dart';

/// 原版 `gui/components/Button` 的 Flutter 对应：灰底黑框斜面按钮、居中标签。
/// 禁用态标签变灰且不触发回调；可用态按下时底面提亮（可见反馈）。
/// 宽高为最终像素；缺省时取父级约束（调用方按缩放档位传值，见 app 壳 McScreen）。
class MCButton extends StatefulWidget {
  const MCButton({
    super.key,
    required this.onPress,
    required this.label,
    this.enabled = true,
    this.width,
    this.height = 20,
  });

  final VoidCallback? onPress;
  final String label;
  final bool enabled;
  final double? width;
  final double height;

  @override
  State<MCButton> createState() => _MCButtonState();
}

class _MCButtonState extends State<MCButton> {
  bool _pressed = false;

  bool get _effectiveEnabled => widget.enabled && widget.onPress != null;

  @override
  Widget build(BuildContext context) {
    final enabled = _effectiveEnabled;
    return ConstrainedBox(
      constraints: BoxConstraints.tightFor(width: widget.width, height: widget.height),
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTap: enabled ? widget.onPress : null,
        child: CustomPaint(
          painter: McFacePainter(enabled: enabled, pressed: _pressed),
          child: Center(
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: enabled ? const Color(0xFFE0E0E0) : const Color(0xFF9E9E9E),
                fontSize: widget.height * 0.42,
                height: 1.0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
