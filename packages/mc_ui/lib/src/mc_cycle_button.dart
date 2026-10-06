import 'package:flutter/material.dart';

import 'mc_face_painter.dart';

/// 原版 `gui/components/CycleButton` 的 Flutter 对应：点按在有序值中
/// 前进一格、到末尾回绕首值；标签以"名称: 当前值"显示。
class MCCycleButton<T> extends StatefulWidget {
  const MCCycleButton({
    super.key,
    required this.label,
    required this.values,
    required this.valueText,
    required this.onChanged,
    this.initialIndex = 0,
    this.enabled = true,
    this.width,
    this.height = 20,
  });

  final String label;
  final List<T> values;
  final String Function(T value) valueText;
  final ValueChanged<T> onChanged;
  final int initialIndex;
  final bool enabled;
  final double? width;
  final double height;

  @override
  State<MCCycleButton<T>> createState() => _MCCycleButtonState<T>();
}

class _MCCycleButtonState<T> extends State<MCCycleButton<T>> {
  late int _index = widget.initialIndex.clamp(0, widget.values.length - 1);

  bool get _effectiveEnabled => widget.enabled;

  void _advance() {
    setState(() => _index = (_index + 1) % widget.values.length);
    widget.onChanged(widget.values[_index]);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _effectiveEnabled;
    return ConstrainedBox(
      constraints: BoxConstraints.tightFor(width: widget.width, height: widget.height),
      child: GestureDetector(
        onTap: enabled ? _advance : null,
        child: CustomPaint(
          painter: McFacePainter(enabled: enabled),
          child: Center(
            child: Text(
              '${widget.label}: ${widget.valueText(widget.values[_index])}',
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
