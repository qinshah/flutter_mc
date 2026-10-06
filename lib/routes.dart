import 'package:flutter/material.dart';

import 'screens/multiplayer/join_multiplayer_screen.dart';
import 'screens/options/video_settings_screen.dart';
import 'screens/title_screen.dart';

/// 路由唯一事实来源（能力 client-screens：菜单页面链路）。
final Map<String, WidgetBuilder> mcRoutes = {
  '/': (context) => const TitleScreen(),
  '/multiplayer': (context) => const JoinMultiplayerScreen(),
  '/settings/video': (context) => const VideoSettingsScreen(),
};
