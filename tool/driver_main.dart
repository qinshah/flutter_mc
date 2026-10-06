// 调试入口（不用于发行）：启用 flutter driver 扩展，供 dart MCP 的
// flutter_driver_command 驱动界面、复现运行期问题（规则：调试用 dart MCP）。
//
// 用法：flutter run -t tool/driver_main.dart -d macos
import 'package:flutter/material.dart';
import 'package:flutter_driver/driver_extension.dart';

import 'package:flutter_mc/routes.dart';

void main() {
  enableFlutterDriverExtension();
  runApp(const _DriverApp());
}

class _DriverApp extends StatelessWidget {
  const _DriverApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(title: 'flutter_mc (driver)', routes: mcRoutes);
  }
}
