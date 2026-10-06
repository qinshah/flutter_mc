import 'package:flutter/material.dart';

/// MC 风格控件面的程序化绘制（backend adaptation：原版为 widgets.png 贴图，
/// 资源管线接入前以纯代码呈现同构外观——灰底、黑外框、上亮下暗斜面棱线）。
class McFacePainter extends CustomPainter {
  McFacePainter({
    required this.enabled,
    this.pressed = false,
    this.face = faceEnabled,
    this.handleX,
    this.handleWidth = 8,
  });

  // 对照原版截图取色的固定灰阶。
  static const Color border = Color(0xFF000000);
  static const Color faceEnabled = Color(0xFF6F6F6F);
  static const Color facePressed = Color(0xFF8A8A8A);
  static const Color faceDisabled = Color(0xFF4C4C4C);
  static const Color faceTrough = Color(0xFF5A5A5A);
  static const Color bevelLight = Color(0xFFA6A6A6);
  static const Color bevelDark = Color(0xFF565656);

  final bool enabled;
  final bool pressed;
  final Color face;

  /// 滑块手柄：null 表示不画；x 为手柄左缘（像素），宽度 [handleWidth]。
  final double? handleX;
  final double handleWidth;

  /// 当前有效底面色（paint 实际使用的取值，供测试断言）。
  Color get faceForTest =>
      enabled ? (pressed ? facePressed : face) : faceDisabled;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Offset.zero & size;
    final fill = Paint()..color = border;
    canvas.drawRect(outer, fill);

    final inner = outer.deflate(1);
    final effectiveFace = enabled
        ? (pressed ? facePressed : face)
        : faceDisabled;
    canvas.drawRect(inner, Paint()..color = effectiveFace);

    final light = enabled ? bevelLight : const Color(0xFF6E6E6E);
    final dark = enabled ? bevelDark : const Color(0xFF3A3A3A);
    // 上亮、下暗、左亮、右暗的斜面棱线。
    canvas
      ..drawRect(
        Rect.fromLTWH(inner.left, inner.top, inner.width, 1),
        Paint()..color = light,
      )
      ..drawRect(
        Rect.fromLTWH(inner.left, inner.bottom - 1, inner.width, 1),
        Paint()..color = dark,
      )
      ..drawRect(
        Rect.fromLTWH(inner.left, inner.top, 1, inner.height),
        Paint()..color = light,
      )
      ..drawRect(
        Rect.fromLTWH(inner.right - 1, inner.top, 1, inner.height),
        Paint()..color = dark,
      );

    final hx = handleX;
    if (hx != null) {
      final handle = Rect.fromLTWH(hx, inner.top + 1, handleWidth, inner.height - 2)
        ..intersect(inner);
      if (!handle.isEmpty) {
        canvas
          ..drawRect(handle, Paint()..color = border)
          ..drawRect(
            handle.deflate(1),
            Paint()..color = enabled ? facePressed : faceDisabled,
          )
          ..drawRect(
            Rect.fromLTWH(handle.left + 1, handle.top + 1, handle.width - 2, 1),
            Paint()..color = enabled ? bevelLight : const Color(0xFF6E6E6E),
          );
      }
    }
  }

  @override
  bool shouldRepaint(McFacePainter oldDelegate) =>
      oldDelegate.enabled != enabled ||
      oldDelegate.pressed != pressed ||
      oldDelegate.face != face ||
      oldDelegate.handleX != handleX;
}
