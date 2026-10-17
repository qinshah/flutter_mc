import 'package:flutter_test/flutter_test.dart';
import 'package:mc_ui/mc_ui.dart';

void main() {
  // 判据 ChatComponent.java:484-497（AlphaCalculator.timeBased）：
  // alpha = clamp(10 × (1 − Δ/200刻), 0, 1)²——180 刻（9s）全显，
  // 最后 20 刻（1s）二次淡出，200 刻（10s）消失。
  group('MCChatComponent 淡出曲线（timeBased 逐值）', () {
    final base = DateTime(2026, 10, 17, 12);

    double alphaAfter(int ms) {
      final m = GuiMessage('t', at: base);
      return MCChatComponent.alphaOf(m, base.add(Duration(milliseconds: ms)));
    }

    test('9s 内全显', () {
      expect(alphaAfter(0), 1.0);
      expect(alphaAfter(5000), 1.0);
      expect(alphaAfter(8999), closeTo(1.0, 1e-9));
    });

    test('最后 1s 二次淡出（t² 曲线）', () {
      // Δ=9.5s ⇒ t = clamp(10−9.5) = 0.5 ⇒ alpha = 0.25
      expect(alphaAfter(9500), closeTo(0.25, 1e-9));
      // Δ=9.9s ⇒ t = 0.1 ⇒ alpha = 0.01
      expect(alphaAfter(9900), closeTo(0.01, 1e-9));
    });

    test('10s 整消失（clamp 到 0）', () {
      expect(alphaAfter(10000), 0.0);
      expect(alphaAfter(20000), 0.0);
    });
  });
}
