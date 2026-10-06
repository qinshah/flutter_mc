import 'package:flutter/material.dart';
import 'package:mc_ui/mc_ui.dart';

import '../screen.dart';

/// 原版 `DirectJoinServerScreen` 的简化对应：仅地址输入。
/// "加入"为占位提示（连接由 join-and-render 接入）。
class DirectJoinServerScreen extends StatefulWidget {
  const DirectJoinServerScreen({super.key});

  @override
  State<DirectJoinServerScreen> createState() => _DirectJoinServerScreenState();
}

class _DirectJoinServerScreenState extends State<DirectJoinServerScreen> {
  final _address = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final s = mcGuiScale(MediaQuery.sizeOf(context)).toDouble();
    return McScreen(
      title: '直接连接',
      body: (context) => Column(
        children: [
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 60 * s, vertical: 8 * s),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '服务器地址',
                    style: TextStyle(color: const Color(0xFF9E9E9E), fontSize: 7 * s, height: 1.0),
                  ),
                  SizedBox(height: 2 * s),
                  MCEditBox(
                    controller: _address,
                    width: double.infinity,
                    height: 20 * s,
                    hintText: '例如 127.0.0.1:25565',
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(4 * s),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                MCButton(
                  width: 98 * s,
                  height: 20 * s,
                  label: '加入服务器',
                  onPress: () {
                    if (_address.text.trim().isEmpty) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('连接 ${_address.text.trim()}（join-and-render 接入）'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                ),
                SizedBox(width: 4 * s),
                MCButton(
                  width: 98 * s,
                  height: 20 * s,
                  label: '取消',
                  onPress: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
