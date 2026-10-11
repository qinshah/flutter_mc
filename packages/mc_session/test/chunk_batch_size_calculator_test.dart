import 'package:test/test.dart';
import 'package:mc_session/mc_session.dart';

/// 黄金值全部**离线手算**（判据 `ChunkBatchSizeCalculator.java:9-31`），
/// 不断言"实现自身的输出"。
///
/// 递推口径：agg' = (agg*w + clamp(t/size, agg/3, agg*3)) / (w+1)，w' = min(49, w+1)。
/// 测试注入微秒时钟（1 µs = 1000 ns）。
void main() {
  group('ChunkBatchSizeCalculator（判据 ChunkBatchSizeCalculator.java）', () {
    test('初值：期望速率 = 7e6 / 2e6 = 3.5 列/刻（:9、:29-31）', () {
      final c = ChunkBatchSizeCalculator(nowUs: () => 0);
      expect(c.getDesiredChunksPerTick(), 3.5);
      expect(c.oldSamplesWeight, 1); // :10
    });

    test('首采样未触发钳制：agg 保持 2e6，期望速率仍 3.5（:16-25）', () {
      var t = 0;
      final c = ChunkBatchSizeCalculator(nowUs: () => t);
      c.onBatchStart(); // t=0
      t = 20_000; // 20ms = 2e7 ns
      c.onBatchFinished(10); // 2e7/10 = 2e6 ns/列 ∈ [agg/3, agg*3]，不钳制
      expect(c.oldSamplesWeight, 2); // :24
      expect(c.getDesiredChunksPerTick(), closeTo(3.5, 1e-9));
    });

    test('上钳制边界（恰为 agg×3，含端点）：手算 agg=10e6/3，期望速率 2.1', () {
      var t = 0;
      final c = ChunkBatchSizeCalculator(nowUs: () => t);
      c.onBatchStart();
      t = 20_000;
      c.onBatchFinished(10); // agg 仍 2e6，w=2
      c.onBatchStart();
      t = 80_000; // 60ms = 6e7 ns / 10 = 6e6 = agg*3（恰在边界，clamp 含端点）
      c.onBatchFinished(10);
      // agg = (2e6*2 + 6e6) / 3 = 10e6/3
      expect(c.getDesiredChunksPerTick(), closeTo(7e6 / (10e6 / 3), 1e-9));
      expect(c.getDesiredChunksPerTick(), closeTo(2.1, 1e-9));
    });

    test('下钳制：采样低于 agg/3 时被钳到下界', () {
      var t = 0;
      final c = ChunkBatchSizeCalculator(nowUs: () => t);
      c.onBatchStart();
      t = 20_000;
      c.onBatchFinished(10); // agg=2e6, w=2
      c.onBatchStart();
      t = 80_000;
      c.onBatchFinished(10); // agg=10e6/3 ≈ 3.333e6, w=3
      c.onBatchStart();
      t = 81_000; // 1ms = 1e6 ns / 10 = 1e5 ns/列 < agg/3 = 1.111e6 → 钳到下界
      c.onBatchFinished(10);
      // agg = (10e6/3*3 + 10e6/9) / 4 = (10e6 + 1.111e6) / 4 = 11111111.11 / 4
      const expectedAgg = 11111111.111111112 / 4;
      expect(c.getDesiredChunksPerTick(), closeTo(7e6 / expectedAgg, 1e-9));
    });

    test('权重封顶 49（:24：Math.min(49, w+1)）', () {
      var t = 0;
      final c = ChunkBatchSizeCalculator(nowUs: () => t);
      for (var i = 0; i < 100; i++) {
        c.onBatchStart();
        t += 20_000; // 每批 20ms/10 列 = 2e6 ns/列
        c.onBatchFinished(10);
      }
      expect(c.oldSamplesWeight, 49);
    });

    test('batchSize=0 不采样（:17 `if (batchSize > 0)`）', () {
      final c = ChunkBatchSizeCalculator(nowUs: () => 0);
      c.onBatchFinished(0);
      expect(c.oldSamplesWeight, 1);
      expect(c.getDesiredChunksPerTick(), 3.5);
    });
  });
}
