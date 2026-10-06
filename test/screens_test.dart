import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mc_session/mc_session.dart';
import 'package:mc_ui/mc_ui.dart';

import 'package:flutter_mc/routes.dart';
import 'package:flutter_mc/screens/multiplayer/join_multiplayer_screen.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(routes: mcRoutes));
    await tester.pumpAndSettle();
  }

  testWidgets('冷启动进标题屏：标题区与主按钮组可见', (tester) async {
    await pumpApp(tester);
    expect(find.text('MINECRAFT'), findsOneWidget);
    expect(find.text('J A V A   E D I T I O N'), findsOneWidget);
    expect(find.text('Random splash!'), findsOneWidget);
    expect(find.text('单人游戏'), findsOneWidget);
    expect(find.text('多人游戏'), findsOneWidget);
    expect(find.text('Minecraft 26.2'), findsOneWidget);
    expect(find.text('© Mojang AB 请勿二次分发！'), findsOneWidget);
  });

  testWidgets('标题屏按钮可用性：单人/Realms/图标钮禁用占位', (tester) async {
    await pumpApp(tester);
    MCButton buttonOf(String label) =>
        tester.widget<MCButton>(find.widgetWithText(MCButton, label));
    expect(buttonOf('单人游戏').onPress, isNull);
    expect(buttonOf('Minecraft Realms').onPress, isNull);
    expect(buttonOf('多人游戏').onPress, isNotNull);
    expect(buttonOf('选项…').onPress, isNotNull);
    expect(buttonOf('退出游戏').onPress, isNotNull);
    expect(tester.widget<MCIconButton>(find.byType(MCIconButton).first).onPress, isNull);
  });

  testWidgets('多人游戏往返：空态提示与返回', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('多人游戏'));
    await tester.pumpAndSettle();

    expect(find.textContaining('暂无服务器'), findsOneWidget);
    expect(find.text('正在你的本地网络中寻找游戏'), findsOneWidget);
    await tester.tap(find.text('返回'));
    await tester.pumpAndSettle();
    expect(find.text('MINECRAFT'), findsOneWidget);
  });

  testWidgets('列表管理：添加→选中→删除确认→持久化', (tester) async {
    // 含 TextField（光标闪烁）：不用 pumpAndSettle，统一固定时长 pump。
    Future<void> pumpMs(WidgetTester t, [int ms = 350]) async {
      await t.pump(Duration(milliseconds: ms));
      await t.pump(Duration(milliseconds: ms));
    }

    final tmp = Directory.systemTemp.createTempSync('fmc_server_list_test');
    addTearDown(() {
      tmp.deleteSync(recursive: true);
    });
    final list = ServerList(tmp)..load();

    await tester.pumpWidget(MaterialApp(
      home: JoinMultiplayerScreen(serverList: list, enablePing: false),
      onGenerateRoute: mcOnGenerateRoute,
    ));
    await pumpMs(tester);
    expect(find.textContaining('暂无服务器'), findsOneWidget);

    // 添加服务器：名称+地址 → 完成。
    await tester.tap(find.text('添加服务器'));
    await pumpMs(tester);
    await tester.enterText(find.byType(MCEditBox).at(0), '测试服');
    await tester.enterText(find.byType(MCEditBox).at(1), '127.0.0.1:25565');
    await tester.tap(find.text('完成'));
    await tester.pump(const Duration(seconds: 1)); // pop 转场收尾
    await pumpMs(tester);
    expect(find.text('测试服'), findsOneWidget);
    expect(find.text('正在探测…'), findsOneWidget);

    // 选中 → 加入服务器/编辑/删除可用。
    await tester.tap(find.text('测试服'));
    await pumpMs(tester);
    MCButton buttonOf(String label) =>
        tester.widget<MCButton>(find.widgetWithText(MCButton, label));
    expect(buttonOf('加入服务器').onPress, isNotNull);
    expect(buttonOf('编辑').onPress, isNotNull);
    expect(buttonOf('删除').onPress, isNotNull);
    expect(buttonOf('刷新').onPress, isNotNull);

    // 删除二次确认：确认屏的"删除"按钮（底部行也有同名按钮，取最后命中）。
    await tester.tap(find.text('删除').last);
    await pumpMs(tester);
    expect(find.textContaining('确定要删除'), findsOneWidget);
    await tester.tap(find.widgetWithText(MCButton, '删除').last);
    await pumpMs(tester);
    expect(find.textContaining('暂无服务器'), findsOneWidget);

    final reloaded = ServerList(tmp)..load();
    expect(reloaded.length, 0);
  });

  testWidgets('视频设置：控件可交互，完成后重进回默认值', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('选项…'));
    await tester.pumpAndSettle();

    expect(find.text('视频设置'), findsOneWidget);
    expect(find.text('显示'), findsOneWidget);
    expect(find.text('品质与性能'), findsOneWidget);

    await tester.tap(find.text('垂直同步: 关'));
    await tester.pump();
    expect(find.text('垂直同步: 开'), findsOneWidget);

    await tester.drag(find.byKey(const Key('video.max-fps')), const Offset(600, 0));
    await tester.pump();
    expect(find.text('最大帧率: 无限制'), findsOneWidget);

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.text('MINECRAFT'), findsOneWidget);

    await tester.tap(find.text('选项…'));
    await tester.pumpAndSettle();
    expect(find.text('垂直同步: 关'), findsOneWidget);
    expect(find.text('最大帧率: 无限制'), findsOneWidget);
  });
}
