// 本地服务器 UI 单测（tasks 3.1 的"界面报缺 + 入口置灰"、4.1 的"列表中作为条目呈现"）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_mc/platform/server_host/local_server_config.dart';
import 'package:flutter_mc/platform/server_host/local_server_host.dart';
import 'package:flutter_mc/screens/multiplayer/join_multiplayer_screen.dart';
import 'package:flutter_mc/screens/multiplayer/local_server_config_dialog.dart';
import 'package:flutter_mc/screens/multiplayer/local_server_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mc_session/mc_session.dart';
import 'package:mc_ui/mc_ui.dart';

void main() {
  late Directory tmp;

  /// 宿主"资产目录为空"（jar 未入库，单测须与仓库里是否放了 jar 无关）。
  LocalServerManager noAssetManager(Directory root) => LocalServerManager(
        root,
        bundledJarLister: (_) async => const <String>[],
      );

  setUp(() => tmp = Directory.systemTemp.createTempSync('local_server_screen'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  testWidgets('缺产物：界面报缺且启动入口置灰（tasks 3.1）', (tester) async {
    final manager = noAssetManager(Directory('${tmp.path}/host'));
    final config = LocalServerConfig(id: 'a', name: '世界');
    await tester.pumpWidget(MaterialApp(
      home: LocalServerScreen(manager: manager, config: config),
    ));
    await tester.pump(); // 让 _resolve 的异步结果落地
    await tester.pump(const Duration(milliseconds: 200));

    // 报缺并给出期望位置（spec「缺产物时明确报缺」）。
    expect(find.textContaining('缺少 26.2'), findsOneWidget);
    expect(find.textContaining('artifacts'), findsOneWidget);

    // 入口置灰：启动与"启动并进入世界"都不可按。
    final start = tester.widget<MCButton>(find.widgetWithText(MCButton, '启动服务器'));
    expect(start.onPress, isNull, reason: '缺产物时入口 MUST 置灰');
    final join = tester
        .widget<MCButton>(find.widgetWithText(MCButton, '启动并进入世界'));
    expect(join.onPress, isNull);

    // 状态区（"启动中/可连接"的呈现位）与日志面板存在。
    expect(find.textContaining('状态：已停止'), findsOneWidget);
    expect(find.text('（暂无日志）'), findsOneWidget);
    // 配置编辑入口始终可用（D7 所列可编辑项）。
    expect(
        tester.widget<MCButton>(find.widgetWithText(MCButton, '配置…')).onPress,
        isNotNull);
  });

  testWidgets('进世界形态（playMode）：缺产物时安全降级、不崩、不露日志面板', (tester) async {
    final manager = noAssetManager(Directory('${tmp.path}/host'));
    final config = LocalServerConfig(id: 'a', name: '世界');
    await tester.pumpWidget(MaterialApp(
      home: LocalServerScreen(manager: manager, config: config, playMode: true),
    ));
    await tester.pump(); // initState 的 post-frame 回调会触发 _start(join: true)
    await tester.pump(const Duration(milliseconds: 300));

    // 走同一启动流程；产物缺失即报缺并停在该屏，不进入连接、不抛异常。
    expect(find.textContaining('缺少 26.2'), findsOneWidget);
    expect(find.textContaining('状态：已停止'), findsOneWidget);
    // 单机不露日志/RCON（用户要求）。
    expect(find.text('（暂无日志）'), findsNothing);
    expect(find.text('启动并进入世界'), findsNothing);
    expect(find.text('取消并返回'), findsOneWidget);
  });

  testWidgets('配置对话框：玩法项用 mc_ui 组件（CycleButton/EditBox），保存写回配置', (tester) async {
    final manager = noAssetManager(Directory('${tmp.path}/host'));
    final config = LocalServerConfig(id: 'a', name: '世界');
    await tester.pumpWidget(MaterialApp(
      home: LocalServerScreen(manager: manager, config: config),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.widgetWithText(MCButton, '配置…'));
    await tester.pumpAndSettle();

    // 枚举/布尔玩法项用 CycleButton（原版 `gui/components/CycleButton`；
    // 单机创建世界界面同样如此，`CreateWorldScreen.java:651-671`）。
    expect(find.byType(MCCycleButton<String>), findsNWidgets(2), // 游戏模式 / 难度
        reason: '游戏模式与难度须是 CycleButton，不是文本输入');
    expect(find.byType(MCCycleButton<bool>), findsNWidgets(1), // 极限模式
        reason: '布尔玩法项须是 on/off CycleButton');
    expect(find.textContaining('游戏模式: 生存'), findsOneWidget);
    expect(find.textContaining('难度: 简单'), findsOneWidget);
    // 单机就是强制游戏模式：不该把 force-gamemode 交给用户选（用户要求）。
    expect(find.textContaining('强制游戏模式'), findsNothing);

    // 种子：文本项（原版 `CreateWorldScreen.java:766-775` 的 seedEdit），留空=随机。
    expect(find.text('种子'), findsOneWidget);
    // 文本项用 MCEditBox（原版 EditBox），不是裸 Flutter TextField。
    expect(find.byType(MCEditBox), findsWidgets);

    // CycleButton 前进一格：生存 → 创造。
    await tester.tap(find.textContaining('游戏模式: 生存'));
    await tester.pump();
    expect(find.textContaining('游戏模式: 创造'), findsOneWidget);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(config.gamemode, 'creative', reason: '保存须写回配置（随后落 server.properties）');
    expect(config.difficulty, 'easy');
  });

  testWidgets('已生成的世界：种子与极限模式在配置里只读（创建时固化）', (tester) async {
    final config = LocalServerConfig(id: 'a', name: '世界');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => showLocalServerConfigDialog(
              ctx,
              config: config,
              worldExists: true,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('世界已生成'), findsOneWidget);
    // 种子输入框与极限模式开关都不可交互（按 Key 精确定位，同 video 设置的既有惯例）。
    expect(
        tester
            .widget<MCEditBox>(find.byKey(const Key('localServer.seed')))
            .enabled,
        isFalse,
        reason: '世界已生成时种子只读');
    expect(
        tester
            .widget<MCCycleButton<bool>>(
                find.byKey(const Key('localServer.hardcore')))
            .enabled,
        isFalse,
        reason: '世界已生成时极限模式只读');
    // 游戏模式/难度仍可改（服务端属性，改了生效）。
    expect(
        tester
            .widget<MCCycleButton<String>>(
                find.widgetWithText(MCCycleButton<String>, '游戏模式: 生存'))
            .enabled,
        isTrue);
  });

  testWidgets('服务器列表呈现本地服务器条目与新建入口（tasks 4.1）', (tester) async {
    final manager = LocalServerManager(Directory('${tmp.path}/host'));
    manager.addConfig(name: '我的世界');
    await tester.pumpWidget(MaterialApp(
      home: JoinMultiplayerScreen(
        serverList: ServerList(Directory('${tmp.path}/game')),
        localManager: manager,
        enablePing: false,
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('本地服务器'), findsOneWidget);
    expect(find.text('我的世界'), findsOneWidget);
    expect(find.textContaining('本地 · 已停止'), findsOneWidget);
    expect(find.text('新建本地世界'), findsOneWidget);
    // 远端列表仍独立呈现（本地条目只此一处，不进 servers.dat）。
    expect(find.textContaining('暂无服务器'), findsOneWidget);
  });
}
