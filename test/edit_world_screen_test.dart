// 编辑世界单测（原版 `client/gui/screens/worldselection/EditWorldScreen.java` 的对应）。
//
// 断言原版语义：**已有世界只能改名**（名字为空则禁用保存，判据 `EditWorldScreen.java:76`），
// 且该屏不提供任何世界生成参数项。
import 'package:flutter/material.dart';
import 'package:flutter_mc/platform/server_host/local_server_config.dart';
import 'package:flutter_mc/screens/worldselection/edit_world_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mc_ui/mc_ui.dart';

void main() {
  Future<void> open(WidgetTester tester, LocalServerConfig config) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => showEditWorldScreen(ctx, config: config),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  TextButton saveButton(WidgetTester tester) =>
      tester.widget<TextButton>(find.widgetWithText(TextButton, '保存'));

  testWidgets('只改名：没有种子/游戏模式等世界生成项', (tester) async {
    final config = LocalServerConfig(id: 'a', name: '我的世界');
    await open(tester, config);

    expect(find.text('编辑世界'), findsOneWidget);
    // 原版此处只有"名称"一个 EditBox，没有任何世界生成参数控件（下方的提示文案只是说明）。
    expect(find.byType(MCEditBox), findsOneWidget);
    expect(find.textContaining('游戏模式'), findsNothing);
    expect(find.byType(MCCycleButton<bool>), findsNothing);
    expect(find.byType(MCCycleButton<String>), findsNothing);
    expect(saveButton(tester).onPressed, isNotNull);
  });

  testWidgets('名字清空则禁用保存（判据 EditWorldScreen.java:76）', (tester) async {
    final config = LocalServerConfig(id: 'a', name: '我的世界');
    await open(tester, config);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(saveButton(tester).onPressed, isNull,
        reason: '原版 `renameButton.active = !isBlank(newName)`');

    await tester.enterText(find.byType(TextField), '新名字');
    await tester.pump();
    expect(saveButton(tester).onPressed, isNotNull);
  });

  testWidgets('保存写回新名字', (tester) async {
    final config = LocalServerConfig(id: 'a', name: '我的世界');
    await open(tester, config);

    await tester.enterText(find.byType(TextField), '新名字');
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();

    expect(config.name, '新名字');
  });
}
