import 'package:flutter/material.dart';
import 'package:mc_session/mc_session.dart';
import 'package:mc_ui/mc_ui.dart';

import '../screen.dart';
import 'join_flow.dart';

/// 原版 `DirectJoinServerScreen` 的简化对应：仅地址输入。
/// "加入服务器"经版本装配点连接：成功进游戏屏（/game），失败就地 SnackBar。
class DirectJoinServerScreen extends StatefulWidget {
  const DirectJoinServerScreen({super.key, this.connector});

  /// 连接注入点（测试替换真实 isolate 会话）；缺省走版本装配点。
  final JoinConnector? connector;

  @override
  State<DirectJoinServerScreen> createState() => _DirectJoinServerScreenState();
}

class _DirectJoinServerScreenState extends State<DirectJoinServerScreen> {
  // 默认本机 Paper（实测常用入口）。
  final _address = TextEditingController(text: '127.0.0.1:25565');

  /// 直连没有列表条目：按输入地址临时构造一条（协议号用锚点默认值，
  /// 真正的版本校验在装配点与握手）。
  Future<void> _join() async {
    final address = _address.text.trim();
    if (address.isEmpty) return;
    await joinServer(
      context,
      server: ServerData(name: address, ip: address),
      connector: widget.connector ?? defaultJoinConnector,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final s = mcScaleForWidth(constraints.maxWidth);
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
                  onPress: _join,
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
      });
  }
}
