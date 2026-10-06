import 'package:flutter/material.dart';

import 'mc_face_painter.dart';

/// 原版 `gui/components/AbstractSliderButton` 的 Flutter 对应：水平滑块。
/// 取值归一化 0.0–1.0，拖动实时回调 [onChanged]；标签以
/// "名称: 值"显示调用方经 [valueText] 格式化的当前值。
class MCSliderButton extends StatefulWidget {
  const MCSliderButton({
    super.key,
    required this.label,
    required this.value,
    required this.valueText,
    required this.onChanged,
    this.enabled = true,
    this.width,
    this.height = 20,
  });

  final String label;

  /// 归一化取值（0.0–1.0）。
  final double value;
  final String Function(double value) valueText;
  final ValueChanged<double> onChanged;
  final bool enabled;
  final double? width;
  final double height;

  @override
  State<MCSliderButton> createState() => _MCSliderButtonState();
}

class _MCSliderButtonState extends State<MCSliderButton> {
  static const double _handleWidth = 8;

  late double _value = widget.value.clamp(0.0, 1.0);
  bool _pressed = false;

  bool get _effectiveEnabled => widget.enabled;

  @override
  void didUpdateWidget(MCSliderButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      _value = widget.value.clamp(0.0, 1.0);
    }
  }

  void _apply(double localDx) {
    final track = context.size!.width - 2 - _handleWidth;
    final v = ((localDx - 1 - _handleWidth / 2) / track).clamp(0.0, 1.0);
    if (v != _value) setState(() => _value = v);
    widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _effectiveEnabled;
    return ConstrainedBox(
      constraints: BoxConstraints.tightFor(width: widget.width, height: widget.height),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final handleX = 1.0 + _value * (constraints.maxWidth - 2 - _handleWidth);
          return GestureDetector(
            onTapDown: enabled
                ? (d) {
                    setState(() => _pressed = true);
                    _apply(d.localPosition.dx);
                  }
                : null,
            onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
            onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
            onHorizontalDragUpdate: enabled
                ? (d) => _apply(d.localPosition.dx)
                : null,
            child: CustomPaint(
              painter: McFacePainter(
                enabled: enabled,
                pressed: _pressed,
                face: McFacePainter.faceTrough,
                handleX: handleX,
                handleWidth: _handleWidth,
              ),
              child: Center(
                child: Text(
                  '${widget.label}: ${widget.valueText(_value)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: enabled
                        ? const Color(0xFFE0E0E0)
                        : const Color(0xFF9E9E9E),
                    fontSize: widget.height * 0.42,
                    height: 1.0,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
