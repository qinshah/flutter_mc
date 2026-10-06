import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mc_ui/mc_ui.dart';

import 'package:flutter_mc/routes.dart';

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

  testWidgets('多人游戏往返：示例条目、提示区、仅返回可用', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('多人游戏'));
    await tester.pumpAndSettle();

    expect(find.text('正在你的本地网络中寻找游戏'), findsOneWidget);
    expect(find.text('localhost'), findsOneWidget);
    expect(find.text('无法连接至服务器'), findsOneWidget);
    MCButton buttonOf(String label) =>
        tester.widget<MCButton>(find.widgetWithText(MCButton, label));
    for (final label in ['加入服务器', '直接连接', '添加服务器', '编辑', '删除', '刷新']) {
      expect(buttonOf(label).onPress, isNull, reason: label);
    }
    expect(buttonOf('返回').onPress, isNotNull);

    await tester.tap(find.text('返回'));
    await tester.pumpAndSettle();
    expect(find.text('MINECRAFT'), findsOneWidget);
  });

  testWidgets('视频设置：控件可交互，完成后重进回默认值', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('选项…'));
    await tester.pumpAndSettle();

    expect(find.text('视频设置'), findsOneWidget);
    expect(find.text('显示'), findsOneWidget);
    expect(find.text('品质与性能'), findsOneWidget);

    // 循环按钮：垂直同步 关→开。
    await tester.tap(find.text('垂直同步: 关'));
    await tester.pump();
    expect(find.text('垂直同步: 开'), findsOneWidget);

    // 滑条：最大帧率拖到最右。
    await tester.drag(find.byKey(const Key('video.max-fps')), const Offset(600, 0));
    await tester.pump();
    expect(find.text('最大帧率: 无限制'), findsOneWidget);

    // 完成 → 回标题屏。
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.text('MINECRAFT'), findsOneWidget);

    // 重进：无持久化，回到默认值。
    await tester.tap(find.text('选项…'));
    await tester.pumpAndSettle();
    expect(find.text('垂直同步: 关'), findsOneWidget);
    expect(find.text('最大帧率: 无限制'), findsOneWidget);
  });
}
