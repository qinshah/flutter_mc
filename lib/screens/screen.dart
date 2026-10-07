import 'package:flutter/material.dart';

/// 简化版原版 scaled GUI：按屏幕短边取整数缩放档位
/// （原版 `Window.calculateScale` 的简化，见 change game-menu-screens design D3）。
/// 所有界面以原版 GUI 像素布局，乘以该档位落到实际像素。
int mcGuiScale(Size size) => (size.shortestSide / 240).floor().clamp(1, 4);

/// 组件宽度断点的 GUI 档位（判据口径同 [mcGuiScale]，但分母取**组件自身宽度**
/// 而非屏幕分辨率——用户约定 2026-10-07：按钮等控件尺寸用 LayoutBuilder 的
/// 组件断点，窗口/分屏/平板自适应）。280 = 204 宽按钮 + 两侧留白的经验宽度。
double mcScaleForWidth(double width) =>
    (width / 280).floor().clamp(1, 4).toDouble();

/// [McScreen] 提供的 GUI 档位（body 子树经 [of] 读取）。
class McScaleScope extends InheritedWidget {
  const McScaleScope({super.key, required this.scale, required super.child});

  final double scale;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<McScaleScope>()!.scale;

  @override
  bool updateShouldNotify(McScaleScope old) => old.scale != scale;
}

/// gui/screens/Screen.java 的简化对应：暗底、可选居中标题与头部渐变线。
/// backend adaptation：无 panorama 背景与原版纹理，资源管线接入后替换。
class McScreen extends StatelessWidget {
  const McScreen({super.key, this.title, required this.body});

  final String? title;
  final WidgetBuilder body;

  @override
  Widget build(BuildContext context) {
    // Scaffold 提供SnackBar 等界面服务；Material(transparency) 为整棵界面树
    // 提供默认文本样式上下文（缺它时 debug 构建下 Text 画黄色双下划线）。
    // 档位由 **McScreen 自身宽度**的 LayoutBuilder 断点决定（非屏幕分辨率）。
    return Scaffold(
      backgroundColor: const Color(0xFF17130F),
      body: Material(
        type: MaterialType.transparency,
        child: LayoutBuilder(
          builder: (context, constraints) => McScaleScope(
            scale: mcScaleForWidth(constraints.maxWidth),
            child: SafeArea(
              child: Builder(builder: (context) {
                final s = McScaleScope.of(context);
                return Column(
                  children: [
                    if (title != null) ...[
                      SizedBox(height: 10 * s),
                      Text(
                        title!,
                        style: TextStyle(
                          color: const Color(0xFFE0E0E0),
                          fontSize: 8 * s,
                          height: 1.0,
                        ),
                      ),
                      SizedBox(height: 6 * s),
                      Container(
                        height: s,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Color(0x00FFFFFF),
                              Color(0x40FFFFFF),
                              Color(0x00FFFFFF)
                            ],
                          ),
                        ),
                      ),
                    ],
                    Expanded(child: Builder(builder: body)),
                  ],
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
