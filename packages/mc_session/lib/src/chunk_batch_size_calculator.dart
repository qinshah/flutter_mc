/// `client/multiplayer/ChunkBatchSizeCalculator.java` 的 Dart 对应物（逐行翻译）。
///
/// 客户端按**实测批次耗时**计算"期望每刻列数"并应答服务器——判据
/// `ClientPacketListener.java:2356-2359`：`onBatchFinished(packet.batchSize())`
/// → 应答 `getDesiredChunksPerTick()`。MUST NOT 把服务器的 batchSize 直接当
/// 期望速率回传（2026-10-11 前的错实现，语义与算法双错）。
///
/// 判据常量（`ChunkBatchSizeCalculator.java:7-11`）：
/// - 累计均值初值 2,000,000 纳秒/列
/// - 预算 7,000,000 纳秒/刻 ⇒ 期望速率 = 7e6 ÷ 累计均值（初批 ≈ 3.5 列/刻）
/// - 采样权重自 1 起累加、上限 49；单次采样钳制在累计均值的 1/3..3 倍
///
/// **单位换算（债）**：原版 `Util.getNanos()` 是纳秒单调钟；Dart `Stopwatch`
/// 只有微秒精度 ⇒ `elapsedMicroseconds × 1000` 补齐量纲。采样本身是毫秒级，
/// 微秒精度足够。
class ChunkBatchSizeCalculator {
  ChunkBatchSizeCalculator({int Function()? nowUs})
      : _nowUs = nowUs ?? _defaultNowUs,
        _chunkBatchStartTimeUs = (nowUs ?? _defaultNowUs)(); // :11 构造即起表

  static const int maxOldSamplesWeight = 49; // :7
  static const int clampCoefficient = 3; // :8（仅以 /3.0、*3.0 出现在表达式，字面量保留作对照）

  final int Function() _nowUs;

  /// 默认时钟：进程级单调 Stopwatch（对应原版 `Util.getNanos()` 的单调语义）。
  static final Stopwatch _clock = Stopwatch()..start();
  static int _defaultNowUs() => _clock.elapsedMicroseconds;

  double _aggregatedNanosPerChunk = 2000000.0; // :9
  int _oldSamplesWeight = 1; // :10
  int _chunkBatchStartTimeUs;

  void onBatchStart() {
    _chunkBatchStartTimeUs = _nowUs(); // :13-15
  }

  void onBatchFinished(int batchSize) {
    if (batchSize > 0) {
      final batchDurationNs = (_nowUs() - _chunkBatchStartTimeUs) * 1000;
      final nanosPerChunk = batchDurationNs / batchSize;
      final clampedNanosPerChunk = nanosPerChunk
          .clamp(
            _aggregatedNanosPerChunk / 3.0,
            _aggregatedNanosPerChunk * 3.0,
          )
          .toDouble(); // :17-23
      _aggregatedNanosPerChunk =
          (_aggregatedNanosPerChunk * _oldSamplesWeight + clampedNanosPerChunk) /
              (_oldSamplesWeight + 1);
      _oldSamplesWeight = _min(_oldSamplesWeight + 1, maxOldSamplesWeight); // :24
    }
  }

  /// 期望每刻列数（:29-31）：7,000,000 纳秒预算 ÷ 累计均值。
  double getDesiredChunksPerTick() => 7000000.0 / _aggregatedNanosPerChunk;

  /// 采样权重（测试观测口；原版 `oldSamplesWeight` 字段，:10/:24）。
  int get oldSamplesWeight => _oldSamplesWeight;

  static int _min(int a, int b) => a < b ? a : b;
}
