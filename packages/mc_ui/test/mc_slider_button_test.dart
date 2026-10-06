import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mc_ui/mc_ui.dart';

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('拖动从最左到最右：取值单调升至 1.0，标签随之更新', (tester) async {
    final values = <double>[];
    await tester.pumpWidget(_host(SizedBox(
      width: 200,
      height: 20,
      child: MCSliderButton(
        label: '最大帧率',
        value: 0,
        valueText: (v) => v >= 1 ? '无限制' : '${(v * 100).round()}%',
        onChanged: values.add,
      ),
    )));

    expect(find.text('最大帧率: 0%'), findsOneWidget);
    await tester.drag(find.byType(MCSliderButton), const Offset(400, 0));
    await tester.pump();

    expect(values, isNotEmpty);
    for (var i = 1; i < values.length; i++) {
      expect(values[i], greaterThanOrEqualTo(values[i - 1]));
    }
    expect(values.last, 1.0);
    expect(find.text('最大帧率: 无限制'), findsOneWidget);
  });

  testWidgets('禁用态不响应拖动', (tester) async {
    final values = <double>[];
    await tester.pumpWidget(_host(SizedBox(
      width: 200,
      height: 20,
      child: MCSliderButton(
        label: '亮度',
        value: 0.5,
        valueText: (v) => '${(v * 100).round()}%',
        onChanged: values.add,
        enabled: false,
      ),
    )));
    await tester.drag(find.byType(MCSliderButton), const Offset(200, 0));
    await tester.pump();
    expect(values, isEmpty);
    expect(find.text('亮度: 50%'), findsOneWidget);
  });
}
