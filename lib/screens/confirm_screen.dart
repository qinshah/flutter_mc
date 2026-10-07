import 'package:flutter/material.dart';
import 'package:mc_ui/mc_ui.dart';

import 'screen.dart';

/// 原版 `gui/screens/ConfirmScreen` 的简化对应：正文 + 确认/取消两按钮。
/// 返回 true=确认，false/退栈=取消。
class ConfirmScreen extends StatelessWidget {
  const ConfirmScreen({super.key, required this.args});

  final ConfirmArgs args;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final s = mcScaleForWidth(constraints.maxWidth);
    return McScreen(
      body: (context) => Column(
        children: [
          Expanded(
            child: Center(
              child: Text(
                args.message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: const Color(0xFFE0E0E0),
                  fontSize: 8 * s,
                  height: 1.4,
                ),
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
                  label: args.confirmLabel,
                  onPress: () => Navigator.pop(context, true),
                ),
                SizedBox(width: 4 * s),
                MCButton(
                  width: 98 * s,
                  height: 20 * s,
                  label: '取消',
                  onPress: () => Navigator.pop(context, false),
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

class ConfirmArgs {
  ConfirmArgs({required this.message, this.confirmLabel = '删除'});
  final String message;
  final String confirmLabel;
}
