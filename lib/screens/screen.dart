import 'package:flutter/material.dart';

/// 简化版原版 scaled GUI：按屏幕短边取整数缩放档位
/// （原版 `Window.calculateScale` 的简化，见 change game-menu-screens design D3）。
/// 所有界面以原版 GUI 像素布局，乘以该档位落到实际像素。
int mcGuiScale(Size size) => (size.shortestSide / 240).floor().clamp(1, 4);

/// gui/screens/Screen.java 的简化对应：暗底、可选居中标题与头部渐变线。
/// backend adaptation：无 panorama 背景与原版纹理，资源管线接入后替换。
class McScreen extends StatelessWidget {
  const McScreen({super.key, this.title, required this.body});

  final String? title;
  final WidgetBuilder body;

  @override
  Widget build(BuildContext context) {
    final s = mcGuiScale(MediaQuery.sizeOf(context)).toDouble();
    // Scaffold 提供SnackBar 等界面服务；Material(transparency) 为整棵界面树
    // 提供默认文本样式上下文（缺它时 debug 构建下 Text 画黄色双下划线）。
    return Scaffold(
      backgroundColor: const Color(0xFF17130F),
      body: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          child: Column(
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
                      colors: [Color(0x00FFFFFF), Color(0x40FFFFFF), Color(0x00FFFFFF)],
                    ),
                  ),
                ),
              ],
              Expanded(child: Builder(builder: body)),
            ],
          ),
        ),
      ),
    );
  }
}
