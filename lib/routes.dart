import 'package:flutter/material.dart';
import 'package:mc_session/mc_session.dart';

import 'game/game_screen.dart';
import 'screens/confirm_screen.dart';
import 'screens/multiplayer/direct_join_server_screen.dart';
import 'screens/multiplayer/join_multiplayer_screen.dart';
import 'screens/multiplayer/manage_server_screen.dart';
import 'screens/options/video_settings_screen.dart';
import 'screens/title_screen.dart';

/// 游戏屏路由的参数：会话句柄 + 服务器显示名（断开提示用）。
///
/// 句柄由装配点（`SessionAssembly.connectFor`）产出，游戏屏是它的消费方。
class GameArgs {
  const GameArgs({required this.session, required this.serverName});

  final SessionHandle session;
  final String serverName;
}

/// 路由唯一事实来源（能力 client-screens：菜单页面链路 + /game 游戏屏）。
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
    case '/game':
      final args = settings.arguments! as GameArgs;
      return MaterialPageRoute<String>(
        builder: (_) => GameScreen(session: args.session),
      );
    case '/multiplayer/confirm':
      final args = settings.arguments! as ConfirmArgs;
      return MaterialPageRoute<bool>(
        builder: (_) => ConfirmScreen(args: args),
      );
  }
  return null;
};
