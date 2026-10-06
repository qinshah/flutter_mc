import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mc_ui/mc_ui.dart';

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('点击触发回调并渲染注入内容', (tester) async {
    var calls = 0;
    await tester.pumpWidget(_host(MCIconButton(
      onPress: () => calls++,
      size: 20,
      child: const Icon(Icons.language, size: 12),
    )));
    expect(find.byIcon(Icons.language), findsOneWidget);
    await tester.tap(find.byType(MCIconButton));
    await tester.pump();
    expect(calls, 1);
  });

  testWidgets('禁用态不响应', (tester) async {
    var calls = 0;
    await tester.pumpWidget(_host(MCIconButton(
      onPress: () => calls++,
      enabled: false,
      size: 20,
      child: const Icon(Icons.accessibility_new, size: 12),
    )));
    await tester.tap(find.byType(MCIconButton), warnIfMissed: false);
    await tester.pump();
    expect(calls, 0);
  });
}
