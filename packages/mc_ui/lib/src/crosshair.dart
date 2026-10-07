import 'package:flutter/material.dart';

/// 十字准星（屏幕中心）。
///
/// **判据**（mc-sources/minecraft-26.2）：
/// - `Hud.java:447`：`blitSprite(RenderPipelines.CROSSHAIR, CROSSHAIR_SPRITE,
///   (guiWidth - 15) / 2, (guiHeight - 15) / 2, 15, 15)` —— 15×15 GUI 像素，
///   屏幕正中；
/// - `RenderPipelines.java:798`：`ColorTargetState(BlendFunction.INVERT)` ——
///   准星像素对**背景取反色**（保证亮暗背景上都可见）。
///
/// **实现**：白色十字 + `BlendMode.difference` —— `result = |dst − src|`，
/// src 为纯白时即 `1 − dst` = 背景取反，与原版 INVERT 混合同义。
/// 不用 `BackdropFilter`（`ImageFilter.matrix` 是 4×4 **几何**变换，
/// 无颜色滤镜——2026-10-07 踩坑："matrix4 must have 16 entries"）。
///
/// **合成层约束**：本 widget 必须与场景在同一合成层（Stack 直连、中间无
/// saveLayer 类包装），difference 才能混到场景像素。
///
/// **落位**：mc_ui（用户指定）；纯 CustomPaint 实现，不依赖 flutter_scene。
class Crosshair extends StatelessWidget {
  const Crosshair({super.key});

  /// GUI 像素口径：准星 15×15、臂厚 1 GUI 像素（原版贴图 15×15 内的十字形）。
  static const double size = 15;

  @override
  Widget build(BuildContext context) {
    final s = mcGuiScaleOf(context);
    return IgnorePointer(
      child: Center(
        child: CustomPaint(
          size: Size(size * s, size * s),
          painter: _CrosshairPainter(arm: s),
        ),
      ),
    );
  }
}

/// 白十字（竖臂 ∪ 横臂）+ difference 混合 = 对背景取反。
class _CrosshairPainter extends CustomPainter {
  _CrosshairPainter({required this.arm});

  final double arm;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..blendMode = BlendMode.difference;
    final w = size.width, h = size.height;
    final cx = w / 2, cy = h / 2;
    canvas.drawRect(Rect.fromLTWH(cx - arm / 2, 0, arm, h), paint); // 竖臂
    canvas.drawRect(Rect.fromLTWH(0, cy - arm / 2, w, arm), paint); // 横臂
  }

  @override
  bool shouldRepaint(covariant _CrosshairPainter old) => old.arm != arm;
}

/// GUI 缩放档位（**宽度**口径——横屏时 shortestSide = 高度，会随设备高度
/// 变小导致准星偏小（2026-10-07 实机：手机上显小）；浮点 clamp，档位平滑）。
double mcGuiScaleOf(BuildContext context) =>
    (MediaQuery.sizeOf(context).width / 280).clamp(1.0, 3.0);
