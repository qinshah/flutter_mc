// 端口设置对话框单测（宿主侧 UI；判据见 lib/screens/multiplayer/local_server_ports_dialog.dart）。
//
// 断言用户要求的口径：**三个端口全部可用才允许按"确定"**（旧实现在被占用时"确定"照样可点）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_mc/platform/server_host/local_server_config.dart';
import 'package:flutter_mc/platform/server_host/local_server_host.dart';
import 'package:flutter_mc/screens/multiplayer/local_server_ports_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;

  /// 宿主"资产目录为空"（jar 未入库，判据与仓库里是否放了 jar 无关）。
  LocalServerManager noAssetManager(Directory root) => LocalServerManager(
        root,
        bundledJarLister: (_) async => const <String>[],
      );

  setUp(() => tmp = Directory.systemTemp.createTempSync('ports_dialog'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  LocalServerConfig configWith(
          {required int port, required int rcon, required int management}) =>
      LocalServerConfig(
        id: 'a',
        name: '世界',
        port: port,
        rconPort: rcon,
        managementServerPort: management,
      );

  Future<void> open(
    WidgetTester tester,
    LocalServerManager manager,
    LocalServerConfig config,
    Future<bool> Function(int) checker, {
    Future<LocalPortHolder?> Function(int)? holderFinder,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => showLocalServerPortsDialog(
              ctx,
              manager: manager,
              config: config,
              portChecker: checker,
              holderFinder: holderFinder,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  TextButton confirmButton(WidgetTester tester) =>
      tester.widget<TextButton>(find.widgetWithText(TextButton, '确定'));

  testWidgets('三个端口都可用：三处显示"可用"，确定可点', (tester) async {
    final manager = noAssetManager(Directory('${tmp.path}/host'));
    final config = configWith(port: 25565, rcon: 25575, management: 25585);
    await open(tester, manager, config, (_) async => true);

    expect(find.text('可用'), findsNWidgets(3));
    expect(confirmButton(tester).onPressed, isNotNull);
  });

  testWidgets('有端口被占用：确定**禁用**（用户要求：确保能用才给确定）', (tester) async {
    final manager = noAssetManager(Directory('${tmp.path}/host'));
    final config = configWith(port: 25565, rcon: 25575, management: 25585);
    // 管理服务器端口被占（实测正是它先撞：Paper 生成世界前就绑它）；
    // 占用者不是本宿主名下的服务器（外部进程，我们无权停）→ 不给停止按钮。
    await open(tester, manager, config, (port) async => port != 25585,
        holderFinder: (_) async => null);

    expect(find.text('可用'), findsNWidgets(2));
    expect(find.textContaining('非本地服务器进程'), findsOneWidget);
    expect(confirmButton(tester).onPressed, isNull,
        reason: '有端口被占用时 MUST NOT 允许确定');
  });

  testWidgets('端口重复或非法：确定禁用', (tester) async {
    final manager = noAssetManager(Directory('${tmp.path}/host'));
    final config = configWith(port: 25565, rcon: 25565, management: 25585);
    await open(tester, manager, config, (_) async => true);

    expect(find.text('与另一个端口重复'), findsNWidgets(2));
    expect(confirmButton(tester).onPressed, isNull);
  });

  testWidgets('被本宿主名下的服务器占用：给**红色**停止按钮，停掉后自动解禁确定', (tester) async {
    final manager = noAssetManager(Directory('${tmp.path}/host'));
    final config = configWith(port: 25565, rcon: 25575, management: 25585);
    // 管理端口被占；占用者是"上次会话残留的孤儿"（内存里查不到，正是用户遇到的形态）。
    var stopped = false;
    await open(
      tester,
      manager,
      config,
      (port) async => port != 25585 || stopped,
      holderFinder: (port) async => port == 25585
          ? LocalPortHolder(
              label: '残留的世界',
              graceful: false,
              stop: () async => stopped = true,
            )
          : null,
    );

    // 只知道被占、停不掉 = 用户抱怨的旧行为；现在必须有红色停止按钮。
    final stopButton = find.widgetWithText(TextButton, '停止该服务器（残留的世界）');
    expect(stopButton, findsOneWidget, reason: '占用者是本宿主服务器时须给停止按钮');
    expect(confirmButton(tester).onPressed, isNull);
    final color = tester.widget<TextButton>(stopButton).style?.foregroundColor
        ?.resolve(<WidgetState>{});
    expect(color, const Color(0xFFE05252), reason: '停止按钮须是红色');

    await tester.tap(stopButton);
    await tester.pumpAndSettle();

    expect(stopped, isTrue, reason: '按钮须真的发出停止动作');
    // 停掉后重新校验 → 可用 → 确定解禁。
    expect(find.text('可用'), findsNWidgets(3));
    expect(confirmButton(tester).onPressed, isNotNull);
  });

  testWidgets('改端口后重新校验：从占用改成可用即可确定', (tester) async {
    final manager = noAssetManager(Directory('${tmp.path}/host'));
    final config = configWith(port: 25565, rcon: 25575, management: 25585);
    await open(tester, manager, config, (port) async => port != 25585,
        holderFinder: (_) async => null);
    expect(confirmButton(tester).onPressed, isNull);

    // 把管理端口改成空闲值 → 三处都可用 → 确定解禁。
    await tester.enterText(
        find.byType(TextField).at(2), '25599');
    await tester.pumpAndSettle();
    expect(find.text('可用'), findsNWidgets(3));
    expect(confirmButton(tester).onPressed, isNotNull);
  });
}
