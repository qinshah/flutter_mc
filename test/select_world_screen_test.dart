// 世界选择屏单测（原版 `client/gui/screens/worldselection/SelectWorldScreen.java` 的对应）。
//
// 断言的是**原版行为**：未选中条目时按钮组禁用（`SelectWorldScreen.java:147-160`）；
// 以及用户要求的"进世界列表不起服、不占端口"（实例目录与进程都不该在这里产生）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_mc/platform/server_host/local_server_host.dart';
import 'package:flutter_mc/screens/worldselection/select_world_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mc_ui/mc_ui.dart';

void main() {
  late Directory tmp;

  /// 宿主"资产目录为空"（jar 未入库，单测须与仓库里是否放了 jar 无关）。
  LocalServerManager noAssetManager(Directory root) => LocalServerManager(
        root,
        bundledJarLister: (_) async => const <String>[],
      );

  setUp(() => tmp = Directory.systemTemp.createTempSync('select_world'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  testWidgets('未选中条目时按钮组禁用，选中后可用（判据 SelectWorldScreen.java:147-160）',
      (tester) async {
    final manager = noAssetManager(Directory('${tmp.path}/host'));
    manager.addConfig(name: '我的世界');

    await tester.pumpWidget(MaterialApp(
      home: SelectWorldScreen(manager: manager),
    ));
    await tester.pump();

    expect(find.text('选择世界'), findsOneWidget);
    expect(find.text('我的世界'), findsOneWidget);

    MCButton buttonOf(String label) =>
        tester.widget<MCButton>(find.widgetWithText(MCButton, label));

    // 原版：无选中时 playWorld/edit/delete 全禁用。
    expect(buttonOf('进入世界').onPress, isNull);
    expect(buttonOf('编辑').onPress, isNull);
    expect(buttonOf('删除').onPress, isNull);
    // 创建与返回始终可用。
    expect(buttonOf('创建新的世界').onPress, isNotNull);
    expect(buttonOf('返回').onPress, isNotNull);

    // 选中条目的这一刻才启用。
    await tester.tap(find.text('我的世界'));
    await tester.pump();
    expect(buttonOf('进入世界').onPress, isNotNull);
    expect(buttonOf('编辑').onPress, isNotNull);
    expect(buttonOf('删除').onPress, isNotNull);
  });

  testWidgets('进世界列表不建实例目录、不起服占端口（用户要求）', (tester) async {
    final manager = noAssetManager(Directory('${tmp.path}/host'));
    final config = manager.addConfig(name: '我的世界');
    final instanceDir = manager.instanceDirectoryFor(config).dir;

    await tester.pumpWidget(MaterialApp(
      home: SelectWorldScreen(manager: manager),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(instanceDir.existsSync(), isFalse,
        reason: '进列表 MUST NOT 建实例目录（起服才建）');
    expect(manager.processFor(config).isRunning, isFalse,
        reason: '进列表 MUST NOT 起服');
  });

  testWidgets('点"创建新的世界"后取消＝什么都没建（回归：曾先落盘再弹表）', (tester) async {
    final manager = noAssetManager(Directory('${tmp.path}/host'));

    await tester.pumpWidget(MaterialApp(
      home: SelectWorldScreen(manager: manager),
    ));
    await tester.pump();
    expect(manager.configs, isEmpty);

    await tester.tap(find.widgetWithText(MCButton, '创建新的世界'));
    await tester.pumpAndSettle();

    // 弹的是**草稿**编辑框（原版 `CreateWorldScreen` 也是先编辑 `WorldCreationUiState`）。
    expect(find.text('本地服务器配置'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(manager.configs, isEmpty, reason: '取消 MUST NOT 创建世界（不入库、不落盘）');
    expect(File('${tmp.path}/host/instances.json').existsSync(), isFalse,
        reason: '取消 MUST NOT 写 instances.json');
  });
}
