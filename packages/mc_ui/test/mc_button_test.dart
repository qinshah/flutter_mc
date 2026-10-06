import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mc_ui/mc_ui.dart';

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('零资产可渲染，标签居中', (tester) async {
    await tester.pumpWidget(_host(
      const SizedBox(
        width: 200,
        height: 20,
        child: MCButton(onPress: null, label: '单人游戏'),
      ),
    ));
    expect(find.text('单人游戏'), findsOneWidget);
  });

  testWidgets('点击触发一次回调', (tester) async {
    var calls = 0;
    await tester.pumpWidget(_host(SizedBox(
      width: 200,
      height: 20,
      child: MCButton(onPress: () => calls++, label: '多人游戏'),
    )));
    await tester.tap(find.text('多人游戏'));
    await tester.pump();
    expect(calls, 1);
  });

  testWidgets('禁用态不响应且标签变灰', (tester) async {
    var calls = 0;
    await tester.pumpWidget(_host(SizedBox(
      width: 200,
      height: 20,
      child: MCButton(
        onPress: () => calls++,
        label: 'Minecraft Realms',
        enabled: false,
      ),
    )));
    await tester.tap(find.text('Minecraft Realms'), warnIfMissed: false);
    await tester.pump();
    expect(calls, 0);
    expect(
      tester.widget<Text>(find.text('Minecraft Realms')).style!.color,
      const Color(0xFF9E9E9E),
    );
  });

  testWidgets('按下有可见反馈（底面提亮）', (tester) async {
    await tester.pumpWidget(_host(SizedBox(
      width: 200,
      height: 20,
      child: MCButton(onPress: () {}, label: 'B'),
    )));
    final center = tester.getCenter(find.byType(MCButton));
    McFacePainter painter() => tester
        .widget<CustomPaint>(find.descendant(
          of: find.byType(MCButton),
          matching: find.byType(CustomPaint),
        ))
        .painter as McFacePainter;

    expect(painter().pressed, isFalse);
    final gesture = await tester.startGesture(center);
    await tester.pump();
    expect(painter().pressed, isTrue);
    expect(painter().faceForTest, McFacePainter.facePressed);
    await gesture.up();
    await tester.pump();
    expect(painter().pressed, isFalse);
  });
}
