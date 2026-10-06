import 'package:flutter/material.dart';
import 'package:mc_ui/mc_ui.dart';

import '../screen.dart';
import 'server_selection_list.dart';

/// gui/screens/multiplayer/JoinMultiplayerScreen.java 的对应：标题、
/// 服务器列表、LAN 搜索提示、底部两排操作按钮。
/// 本期为视觉与导航骨架：除"返回"外底部按钮禁用占位（连接能力随后续 change）。
class JoinMultiplayerScreen extends StatelessWidget {
  const JoinMultiplayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = mcGuiScale(MediaQuery.sizeOf(context)).toDouble();
    final gap = SizedBox(width: 4 * s);
    return McScreen(
      title: '多人游戏',
      body: (context) => Column(
        children: [
          Expanded(
            child: Column(
              children: [
                const ServerSelectionList(),
                const Spacer(),
                Text(
                  '正在你的本地网络中寻找游戏',
                  style: TextStyle(color: const Color(0xFFE0E0E0), fontSize: 8 * s, height: 1.0),
                ),
                SizedBox(height: 3 * s),
                Text(
                  'O o o',
                  style: TextStyle(color: const Color(0xFF9E9E9E), fontSize: 8 * s, height: 1.0),
                ),
                SizedBox(height: 24 * s),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(4 * s),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: MCButton(height: 20 * s, label: '加入服务器', onPress: null)),
                    gap,
                    Expanded(child: MCButton(height: 20 * s, label: '直接连接', onPress: null)),
                    gap,
                    Expanded(child: MCButton(height: 20 * s, label: '添加服务器', onPress: null)),
                  ],
                ),
                SizedBox(height: 4 * s),
                Row(
                  children: [
                    Expanded(child: MCButton(height: 20 * s, label: '编辑', onPress: null)),
                    gap,
                    Expanded(child: MCButton(height: 20 * s, label: '删除', onPress: null)),
                    gap,
                    Expanded(child: MCButton(height: 20 * s, label: '刷新', onPress: null)),
                    gap,
                    Expanded(
                      child: MCButton(
                        height: 20 * s,
                        label: '返回',
                        onPress: () => Navigator.pop(context),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
