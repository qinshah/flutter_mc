/// `com/mojang/math/SymmetricGroup3.java` 的 Dart 对应物（纯 Dart）。
///
/// 三元素对称群 S3 的六个置换，用于 [OctahedralGroup] 的轴置换分量。
///
/// **置换语义**（判据 `SymmetricGroup3.java:72-84` 的 `permuteVector`）：
/// 对向量施加 `p` 的结果是 `new_i = old_{p_i}`（新分量 i 取旧分量 `permute(i)`）。
library;

import 'direction.dart';

/// S3 的六个置换（判据 `SymmetricGroup3.java:12-17`）。
enum SymmetricGroup3 {
  p123(0, 1, 2),
  p213(1, 0, 2),
  p132(0, 2, 1),
  p312(2, 0, 1),
  p231(1, 2, 0),
  p321(2, 1, 0);

  const SymmetricGroup3(this.p0, this.p1, this.p2);

  final int p0;
  final int p1;
  final int p2;

  /// `permute(i)`（判据 `SymmetricGroup3.java:59-66`）。
  int permute(int i) => switch (i) {
        0 => p0,
        1 => p1,
        2 => p2,
        _ => throw ArgumentError('Must be 0, 1 or 2, but got $i'),
      };

  /// `permuteAxis`（判据 `SymmetricGroup3.java:48-52`：`VALUES[permute(axis)]`）。
  Axis permuteAxis(Axis axis) => Axis.byOrdinal(permute(axis.index));

  /// `compose`（判据 `SymmetricGroup3.java:23-38` 的 CAYLEY_TABLE）：
  /// `(a ∘ b).permute(i) = a.permute(b.permute(i))`——与表构造
  /// `p_i = first.permute(second.p_i)`（`second.p_i = second.permute(i)`）逐项等价。
  SymmetricGroup3 compose(SymmetricGroup3 b) => values.firstWhere(
        (r) => identical(
            r,
            _byPermute(permute(b.p0), permute(b.p1), permute(b.p2))),
      );

  /// `inverse`（判据 `SymmetricGroup3.java:39-42`：compose 后为 P123 者）。
  SymmetricGroup3 inverse() => values
      .firstWhere((r) => identical(compose(r), p123));

  static SymmetricGroup3 _byPermute(int p0, int p1, int p2) => values.firstWhere(
      (r) => r.p0 == p0 && r.p1 == p1 && r.p2 == p2);
}
