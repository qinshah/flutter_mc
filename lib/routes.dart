import 'package:flutter/material.dart';

import 'screens/confirm_screen.dart';
import 'screens/multiplayer/direct_join_server_screen.dart';
import 'screens/multiplayer/join_multiplayer_screen.dart';
import 'screens/multiplayer/manage_server_screen.dart';
import 'screens/options/video_settings_screen.dart';
import 'screens/title_screen.dart';

/// 路由唯一事实来源（能力 client-screens：菜单页面链路）。
/// 主链路三条命名路由；多人游戏的管理子屏经 onGenerateRoute 传参。
final Map<String, WidgetBuilder> mcRoutes = {
  '/': (context) => const TitleScreen(),
  '/multiplayer': (context) => const JoinMultiplayerScreen(),
  '/settings/video': (context) => const VideoSettingsScreen(),
};

Route<dynamic>? Function(RouteSettings) mcOnGenerateRoute = (settings) {
  switch (settings.name) {
    case '/multiplayer/manage':
      final args = settings.arguments! as ManageServerArgs;
      return MaterialPageRoute<void>(
        builder: (_) => ManageServerScreen(args: args),
      );
    case '/multiplayer/direct':
      return MaterialPageRoute<void>(
        builder: (_) => const DirectJoinServerScreen(),
      );
    case '/multiplayer/confirm':
      final args = settings.arguments! as ConfirmArgs;
      return MaterialPageRoute<bool>(
        builder: (_) => ConfirmScreen(args: args),
      );
  }
  return null;
};
