import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mc_ui/mc_ui.dart';

/// 触控控件测试（touch-input 能力 / mc-ui-components 新增 requirement）：
/// ① 按下/抬起沿各发一次；② 控件销毁时补抬起沿（防键位卡死）；
/// ③ 多点同时按住两个按钮（Listener 不参与手势竞技场的语义验证）。
void main() {
  testWidgets('TouchKeyButton：down/up 沿各一次', (tester) async {
    var downCount = 0;
    var upCount = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: TouchKeyButton(
            label: '◆',
            onDown: () => downCount++,
            onUp: () => upCount++,
          ),
        ),
      ),
    ));

    final center = tester.getCenter(find.byType(TouchKeyButton));
    final gesture = await tester.startGesture(center);
    await tester.pump();
    expect(downCount, 1);
    expect(upCount, 0);

    await gesture.up();
    await tester.pump();
    expect(downCount, 1);
    expect(upCount, 1);
  });

  testWidgets('TouchKeyButton：按住时销毁 → 补一次抬起沿', (tester) async {
    var upCount = 0;
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: TouchKeyButton(
            key: key,
            label: '▲',
            onDown: () {},
            onUp: () => upCount++,
          ),
        ),
      ),
    ));

    await tester.startGesture(tester.getCenter(find.byType(TouchKeyButton)));
    await tester.pump();

    // 直接换树销毁按钮（指针未抬起）。
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Container())));
    await tester.pump();
    expect(upCount, 1, reason: '销毁时必须补抬起沿，否则键位集合永久残留');
  });

  testWidgets('TouchHub：多点同时按住前进与跳跃（同一条键位路径的入口）',
      (tester) async {
    final forward = <bool>[];
    final jump = <bool>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TouchHub(
          bindings: TouchHubBindings(
            onForward: forward.add,
            onBack: (_) {},
            onLeft: (_) {},
            onRight: (_) {},
            onJump: jump.add,
            onSneak: (_) {},
            onEscape: () {},
            onInventory: () {},
          ),
        ),
      ),
    ));

    // 按内容定位：W（前）与 Space（跳）——hub 按钮直接显示键盘键值。
    final forwardPoint = tester.getCenter(find.text('W'));
    final jumpPoint = tester.getCenter(find.text('Space'));

    final g1 = await tester.startGesture(forwardPoint);
    final g2 = await tester.startGesture(jumpPoint);
    await tester.pump();
    expect(forward, [true], reason: '多点触控下两按钮必须同时处于按下态');
    expect(jump, [true]);

    await g1.up();
    await g2.up();
    await tester.pump();
    expect(forward, [true, false]);
    expect(jump, [true, false]);
  });
}
