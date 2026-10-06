import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mc_ui/mc_ui.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('输入实时同步 controller', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(_host(SizedBox(
      width: 200,
      height: 20,
      child: MCEditBox(controller: controller),
    )));

    await tester.enterText(find.byType(MCEditBox), 'localhost');
    await tester.pump();
    expect(controller.text, 'localhost');
  });

  testWidgets('边框：失焦灰、聚焦白', (tester) async {
    await tester.pumpWidget(_host(SizedBox(
      width: 200,
      height: 20,
      child: MCEditBox(controller: TextEditingController()),
    )));
    InputDecoration decorationOf() =>
        tester.widget<TextField>(find.byType(TextField)).decoration!;
    expect(
      decorationOf().enabledBorder!.borderSide.color,
      MCEditBox.colorBorder,
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(
      decorationOf().focusedBorder!.borderSide.color,
      MCEditBox.colorBorderFocused,
    );
  });

  testWidgets('禁用态不接受输入', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(_host(SizedBox(
      width: 200,
      height: 20,
      child: MCEditBox(controller: controller, enabled: false),
    )));
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(controller.text, '');
  });
}
