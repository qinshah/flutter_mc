import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mc_ui/mc_ui.dart';

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('点按前进一格并回绕到首值', (tester) async {
    final picked = <String>[];
    await tester.pumpWidget(_host(SizedBox(
      width: 200,
      height: 20,
      child: MCCycleButton<String>(
        label: '垂直同步',
        values: const ['关', '开'],
        valueText: (v) => v,
        onChanged: picked.add,
      ),
    )));

    expect(find.text('垂直同步: 关'), findsOneWidget);
    await tester.tap(find.text('垂直同步: 关'));
    await tester.pump();
    expect(find.text('垂直同步: 开'), findsOneWidget);
    expect(picked, ['开']);

    await tester.tap(find.text('垂直同步: 开'));
    await tester.pump();
    expect(find.text('垂直同步: 关'), findsOneWidget);
    expect(picked, ['开', '关']);
  });

  testWidgets('禁用态不响应点按', (tester) async {
    final picked = <String>[];
    await tester.pumpWidget(_host(SizedBox(
      width: 200,
      height: 20,
      child: MCCycleButton<String>(
        label: '预设',
        values: const ['自定义', '低', '高'],
        valueText: (v) => v,
        onChanged: picked.add,
        enabled: false,
      ),
    )));
    await tester.tap(find.text('预设: 自定义'), warnIfMissed: false);
    await tester.pump();
    expect(picked, isEmpty);
    expect(find.text('预设: 自定义'), findsOneWidget);
  });
}
