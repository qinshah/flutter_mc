// 调试入口（不用于发行）：启用 flutter driver 扩展，供 dart MCP 的
// flutter_driver_command 驱动界面、复现运行期问题（规则：调试用 dart MCP）。
//
// 用法：
//   flutter run -t tool/driver_main.dart -d macos
//   flutter run -t tool/driver_main.dart -d macos --dart-define=AUTOJOIN=127.0.0.1:25565
//
// AUTOJOIN：首帧后**走生产路径**（SessionAssembly → /game）自动加入该地址。
// 用途是端到端验收——本机驱动点击/hit-test 不稳定时，把"连接 + 渲染"这条链路
// 与"菜单点击"解耦；菜单接线本身由 test/join_flow_test.dart 的 widget 测试覆盖。
import 'package:flutter/material.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:mc_session/mc_session.dart';

import 'package:flutter_mc/routes.dart';
import 'package:flutter_mc/screens/multiplayer/join_flow.dart';

const String _autoJoin = String.fromEnvironment('AUTOJOIN');

void main() {
  enableFlutterDriverExtension();
  runApp(const _DriverApp());
}

class _DriverApp extends StatefulWidget {
  const _DriverApp();

  @override
  State<_DriverApp> createState() => _DriverAppState();
}

class _DriverAppState extends State<_DriverApp> {
  final _navigator = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    if (_autoJoin.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoJoinServer());
  }

  Future<void> _autoJoinServer() async {
    final context = _navigator.currentContext;
    if (context == null) return;
    debugPrint('[AUTOJOIN] 加入 $_autoJoin');
    await joinServer(
      context,
      server: ServerData(name: _autoJoin, ip: _autoJoin),
      connector: defaultJoinConnector,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_mc (driver)',
      navigatorKey: _navigator,
      routes: mcRoutes,
      // 传参路由（/multiplayer/manage、/multiplayer/direct、/multiplayer/confirm、
      // /game）都在 onGenerateRoute 里，调试入口必须一并接上，否则驱动不进游戏屏。
      onGenerateRoute: mcOnGenerateRoute,
    );
  }
}
