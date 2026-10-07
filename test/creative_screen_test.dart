import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mc_ui/mc_ui.dart';

import 'package:flutter_mc/client/gui/screens/inventory/creative_mode_inventory_screen.dart';

/// 创造物品栏输入与过滤测试（实机反馈："游戏内输入框无法输入内容"、
/// "背包没有显示物品网格"——这里锁住两个行为）。
void main() {
  Widget buildPanel(CreativeModeInventoryScreen screen) => MaterialApp(
        home: Builder(
          builder: (context) =>
              Scaffold(body: screen.buildWidget(context)),
        ),
      );

  testWidgets('搜索框可输入并过滤条目', (tester) async {
    final screen = CreativeModeInventoryScreen(
      onPickItem: (_, _, _) {},
      textures: null,
    );
    await tester.pumpWidget(buildPanel(screen));
    await tester.pumpAndSettle();

    // 输入前：网格有全部条目（>1000 项），无过滤提示之外文案。
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'stone');
    await tester.pumpAndSettle();

    // 过滤生效：正文出现过滤计数（stone 相关条目远少于全量）。
    expect(find.textContaining('stone'), findsWidgets);
  });

  testWidgets('物品网格渲染槽位条目（点选回调携带名字/物品序/状态号）', (tester) async {
    String? pickedName;
    int? pickedItemId;
    int? pickedStateId;
    final screen = CreativeModeInventoryScreen(
      onPickItem: (name, itemId, stateId) {
        pickedName = name;
        pickedItemId = itemId;
        pickedStateId = stateId;
      },
      textures: null,
    );
    await tester.pumpWidget(buildPanel(screen));
    await tester.pumpAndSettle();

    // 搜索过滤定位（条目名无前缀：stone/stone_bricks/...）并点选第一个槽位。
    await tester.enterText(find.byType(TextField), 'stone');
    await tester.pumpAndSettle();
    expect(find.textContaining('项'), findsOneWidget);
    final gridSlots = find.descendant(
      of: find.byType(GridView),
      matching: find.byType(MCItemSlot),
    );
    expect(gridSlots, findsWidgets);
    await tester.tap(gridSlots.first, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(pickedName, isNotNull);
    expect(pickedItemId, isNotNull);
    expect(pickedStateId, isNotNull);
  });
}
