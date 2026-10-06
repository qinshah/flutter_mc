import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_mc/routes.dart';
import 'package:flutter_mc/screens/multiplayer/join_flow.dart';
import 'package:flutter_mc/screens/multiplayer/join_multiplayer_screen.dart';
import 'package:flutter_mc/screens/multiplayer/manage_server_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mc_session/mc_session.dart';
import 'package:mc_ui/mc_ui.dart';

/// tasks 3.4 验证：多人屏加入的两条分支（失败报错 / 成功进游戏屏）+ 路由。
///
/// 用**注入的假连接器**：`SessionHandle` 的构造器已公开，脚本化事件流即可覆盖两条
/// 分支，不必起真服务器、也不必起 GPU（`/game` 在测试里替换成占位屏）。
void main() {
  final openPorts = <ReceivePort>[];
  tearDown(() {
    for (final port in openPorts) {
      port.close();
    }
    openPorts.clear();
  });

  SessionHandle handleOf(Stream<SessionEvent> events) {
    final port = ReceivePort();
    openPorts.add(port);
    return SessionHandle(port.sendPort, events);
  }

  GameLogin login() => GameLogin(
        playerId: 1,
        levelNames: const ['overworld'],
        maxPlayers: 20,
        chunkRadius: 10,
        simulationDistance: 10,
        dimensionType: 'minecraft:overworld',
        dimension: 'minecraft:overworld',
        hashedSeed: 0,
        gameType: 0,
        previousGameType: -1,
        isDebug: false,
        isFlat: false,
        portalCooldown: 0,
        seaLevel: 63,
      );

  Future<void> pumpMs(WidgetTester tester, [int ms = 300]) async {
    await tester.pump(Duration(milliseconds: ms));
    await tester.pump(Duration(milliseconds: ms));
  }

  /// 装好多人屏、经 UI 添加一台服务器并选中（与 screens_test 同一手法）。
  Future<void> pumpScreen(
    WidgetTester tester, {
    required JoinConnector connector,
    void Function(GameArgs args)? onGame,
  }) async {
    final tmp = Directory.systemTemp.createTempSync('fmc_join_flow_test');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final list = ServerList(tmp)..load();

    await tester.pumpWidget(
      MaterialApp(
        home: JoinMultiplayerScreen(
          serverList: list,
          enablePing: false,
          connector: connector,
        ),
        onGenerateRoute: (settings) {
          // 管理屏走真实实现（"添加服务器"要用）。
          if (settings.name == '/multiplayer/manage') {
            final args = settings.arguments! as ManageServerArgs;
            return MaterialPageRoute<void>(
              builder: (_) => ManageServerScreen(args: args),
            );
          }
          // 真 /game 需要 GPU（Scene.initializeStaticResources），测试里换成占位屏，
          // 断言的是"确实带参数路由到了 /game"。
          if (settings.name == '/game') {
            final args = settings.arguments! as GameArgs;
            onGame?.call(args);
            return MaterialPageRoute<String>(
              builder: (_) => const Scaffold(body: Text('游戏屏占位')),
            );
          }
          return null;
        },
      ),
    );
    await pumpMs(tester);

    await tester.tap(find.text('添加服务器'));
    await pumpMs(tester);
    await tester.enterText(find.byType(MCEditBox).at(0), '测试服');
    await tester.enterText(find.byType(MCEditBox).at(1), '127.0.0.1:25565');
    await tester.tap(find.text('完成'));
    await tester.pump(const Duration(seconds: 1));
    await pumpMs(tester);
    await tester.tap(find.text('测试服'));
    await pumpMs(tester);
  }

  testWidgets('连接失败（SessionClosed）→ 留在列表并 SnackBar 给出原因', (tester) async {
    await pumpScreen(
      tester,
      connector: (server, playerName) async =>
          handleOf(Stream.value(const SessionClosed('连接失败：Connection refused'))),
    );

    await tester.tap(find.text('加入服务器'));
    await pumpMs(tester);

    expect(find.textContaining('无法加入'), findsOneWidget);
    expect(find.textContaining('Connection refused'), findsOneWidget);
    // 失败不进游戏屏。
    expect(find.text('游戏屏占位'), findsNothing);
  });

  testWidgets('未注册协议版本 → SnackBar 给出可操作提示，且不发连接', (tester) async {
    await pumpScreen(
      tester,
      connector: (server, playerName) async => throw UnsupportedProtocolError(340),
    );

    await tester.tap(find.text('加入服务器'));
    await pumpMs(tester);

    expect(find.textContaining('不支持的协议版本'), findsOneWidget);
    expect(find.text('游戏屏占位'), findsNothing);
  });

  testWidgets('进服成功（JoinedGame）→ 路由到 /game 并携带同一会话句柄', (tester) async {
    GameArgs? pushed;
    final handle = handleOf(Stream.value(JoinedGame(login())));

    await pumpScreen(
      tester,
      connector: (server, playerName) async => handle,
      onGame: (args) => pushed = args,
    );

    await tester.tap(find.text('加入服务器'));
    await pumpMs(tester);

    expect(find.text('游戏屏占位'), findsOneWidget);
    expect(pushed, isNotNull);
    expect(identical(pushed!.session, handle), isTrue, reason: '句柄必须原样交给游戏屏');
    expect(pushed!.serverName, '测试服');
  });
}
