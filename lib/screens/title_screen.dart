import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mc_ui/mc_ui.dart';

import 'screen.dart';

/// gui/screens/TitleScreen.java 的对应：标题区（文字版 MINECRAFT/JAVA
/// EDITION）、主按钮组、图标按钮、右上倾斜 splash、底部版本/版权 overlay。
/// backend adaptation：无 panorama 背景、logo 为文字版（资源管线接入后替换，
/// 见 design D2）；单人游戏 / Realms / 图标按钮本期禁用占位。
class TitleScreen extends StatelessWidget {
  const TitleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final s = mcScaleForWidth(constraints.maxWidth);
    final gap = SizedBox(height: 4 * s);
    return McScreen(
      body: (context) => Stack(
        children: [
          // 标题区：文字版 logo + 副标。
          Positioned(
            top: 26 * s,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Text(
                  'MINECRAFT',
                  style: TextStyle(
                    fontSize: 11 * s,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5 * s,
                    color: const Color(0xFFD8D8D8),
                    shadows: [
                      Shadow(offset: Offset(1.5 * s, 1.5 * s), color: const Color(0xFF3F3F3F)),
                    ],
                  ),
                ),
                SizedBox(height: 2 * s),
                Text(
                  'J A V A   E D I T I O N',
                  style: TextStyle(
                    fontSize: 3.5 * s,
                    letterSpacing: 1 * s,
                    color: const Color(0xFFD8D8D8),
                  ),
                ),
              ],
            ),
          ),
          // splash：黄色斜置文本（占位文案，正式清单随资源 change）。
          Positioned(
            top: 48 * s,
            right: 48 * s,
            child: Transform.rotate(
              angle: -0.3,
              child: Text(
                'Random splash!',
                style: TextStyle(
                  color: const Color(0xFFFFFF00),
                  fontSize: 4 * s,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          // 主按钮组。
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MCButton(
                  width: 200 * s,
                  height: 20 * s,
                  label: '单人游戏',
                  onPress: null,
                ),
                gap,
                MCButton(
                  width: 200 * s,
                  height: 20 * s,
                  label: '多人游戏',
                  onPress: () => Navigator.pushNamed(context, '/multiplayer'),
                ),
                gap,
                MCButton(
                  width: 200 * s,
                  height: 20 * s,
                  label: 'Minecraft Realms',
                  onPress: null,
                ),
                gap,
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MCIconButton(
                      size: 20 * s,
                      onPress: null,
                      child: Icon(Icons.accessibility_new, size: 12 * s, color: const Color(0xFF9E9E9E)),
                    ),
                    SizedBox(width: 4 * s),
                    MCIconButton(
                      size: 20 * s,
                      onPress: null,
                      child: Icon(Icons.language, size: 12 * s, color: const Color(0xFF9E9E9E)),
                    ),
                    SizedBox(width: 4 * s),
                    MCIconButton(
                      size: 20 * s,
                      onPress: null,
                      child: Icon(Icons.person, size: 12 * s, color: const Color(0xFF9E9E9E)),
                    ),
                  ],
                ),
                gap,
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MCButton(
                      width: 98 * s,
                      height: 20 * s,
                      label: '选项…',
                      onPress: () => Navigator.pushNamed(context, '/settings/video'),
                    ),
                    SizedBox(width: 4 * s),
                    MCButton(
                      width: 98 * s,
                      height: 20 * s,
                      label: '退出游戏',
                      onPress: kIsWeb ? null : () => SystemNavigator.pop(),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 底部 overlay：左下版本、右下版权。
          Positioned(
            left: 2 * s,
            bottom: 2 * s,
            child: Text(
              'Minecraft 26.2',
              style: TextStyle(color: const Color(0xFFE0E0E0), fontSize: 8 * s, height: 1.0),
            ),
          ),
          Positioned(
            right: 2 * s,
            bottom: 2 * s,
            child: Text(
              '© Mojang AB 请勿二次分发！',
              style: TextStyle(color: const Color(0xFFE0E0E0), fontSize: 8 * s, height: 1.0),
            ),
          ),
        ],
      ),
    );
      });
  }
}
