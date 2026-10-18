import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mc_session/mc_session.dart';

import 'game/game_screen.dart';
import 'platform/server_host/local_server_config.dart';
import 'platform/server_host/local_server_host.dart';
import 'screens/confirm_screen.dart';
import 'screens/multiplayer/direct_join_server_screen.dart';
import 'screens/multiplayer/join_flow.dart';
import 'screens/multiplayer/join_multiplayer_screen.dart';
import 'screens/multiplayer/local_server_screen.dart';
import 'screens/multiplayer/manage_server_screen.dart';
import 'screens/options/video_settings_screen.dart';
import 'screens/local_server_jvm_selftest_screen.dart';
import 'screens/title_screen.dart';
import 'screens/worldselection/select_world_screen.dart';

/// 游戏屏路由的参数：会话句柄 + 服务器显示名（断开提示用）。
///
/// 句柄由装配点（`SessionAssembly.connectFor`）产出，游戏屏是它的消费方。
class GameArgs {
  const GameArgs({
    required this.session,
    required this.events,
    required this.serverName,
  });

  final SessionHandle session;

  /// **已缓冲**的会话事件流（见 `join_flow.dart`）：会话的 broadcast 流不缓存，
  /// 晚订阅会丢掉初始位姿，故由加入流程先挂转发再交给游戏屏。
  final Stream<SessionEvent> events;

  final String serverName;
}

/// 本地服务器屏路由参数（宿主侧条目，见 `platform/server_host/`）。
class LocalServerArgs {
  const LocalServerArgs({
    required this.manager,
    required this.config,
    this.playMode = false,
  });

  final LocalServerManager manager;
  final LocalServerConfig config;

  /// 进世界模式（单机世界列表的「进入世界」）：进屏即启动 → 等就绪 → 连入；
  /// 不显示日志/RCON 控制台；退出游戏（`/game` 返回）后停止服务器并返回上层。
  final bool playMode;
}

/// 路由唯一事实来源（能力 client-screens：菜单页面链路 + /game 游戏屏）。
/// 主链路三条命名路由；多人游戏的管理子屏经 onGenerateRoute 传参。
final Map<String, WidgetBuilder> mcRoutes = {
  '/': (context) => const TitleScreen(),
  '/multiplayer': (context) => const JoinMultiplayerScreen(),
  '/settings/video': (context) => const VideoSettingsScreen(),
  '/autojoin': (context) => const _AutoJoinScreen(),
  // 宿主承载层真机取证（`--dart-define=MC_JVM_SELFTEST=1`），与 /autojoin 同性质。
  '/jvm-selftest': (context) => const LocalServerJvmSelfTestScreen(),
};

/// 自动进服（`--dart-define=AUTOJOIN=<ip:port>`，取证脚本用）。
///
/// 免去手动点 UI：启动即以给定地址走 [joinServer]（成功后其内部 push '/game'），
/// 失败原因直接打日志——探针场景无需 UI 反馈。
class _AutoJoinScreen extends StatefulWidget {
  const _AutoJoinScreen();

  @override
  State<_AutoJoinScreen> createState() => _AutoJoinScreenState();
}

class _AutoJoinScreenState extends State<_AutoJoinScreen> {
  @override
  void initState() {
    super.initState();
    final addr = const String.fromEnvironment('AUTOJOIN');
    final server = ServerData(name: addr, ip: addr);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // join_flow.dart 的公共流程（与"直接连接"按钮同一入口）。
      joinServer(context, server: server, connector: defaultJoinConnector);
    });
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('AUTOJOIN...')));
}

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
        builder: (_) => GameScreen(session: args.session, events: args.events),
      );
    case '/multiplayer/confirm':
      final args = settings.arguments! as ConfirmArgs;
      return MaterialPageRoute<bool>(
        builder: (_) => ConfirmScreen(args: args),
      );
    case '/singleplayer':
      // 单人游戏 → 世界列表（原版 `SelectWorldScreen`）。参数为宿主管理器。
      final manager = settings.arguments! as LocalServerManager;
      return MaterialPageRoute<void>(
        builder: (_) => SelectWorldScreen(manager: manager),
      );
    case '/multiplayer/local':
      final args = settings.arguments! as LocalServerArgs;
      return MaterialPageRoute<void>(
        builder: (_) => LocalServerScreen(
          manager: args.manager,
          config: args.config,
          playMode: args.playMode,
        ),
      );
  }
  return null;
};
