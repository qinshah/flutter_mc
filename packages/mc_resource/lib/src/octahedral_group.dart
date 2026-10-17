import 'direction.dart';
import 'symmetric_group3.dart';

/// `com/mojang/math/OctahedralGroup.java` 的 Dart 对应物（纯 Dart，
/// 本实现引用到的群元素子集）。
///
/// 八面体群：48 个「轴置换 + 轴翻转」的正交变换。方块模型烘焙
/// （blockstate 变体的 x/y/z 旋转）与 `BlockMath` 的 uvlock 面变换
/// 全部落在该群内，故用群元素表示 3x3 变换矩阵。
///
/// **向量映射语义**（判据 `OctahedralGroup.java:156-162` 的 `rotate(Vector3i)`）：
/// 先置换（`new_i = old_{permute(i)}`，`SymmetricGroup3.permuteVector`），
/// 再按输出轴乘翻转符号。
///
/// 只列出本仓库烘焙路径引用的常量（判据 `OctahedralGroup.java:16-73`，
/// BLOCK_ROT_* 别名在 :65-73）；其余 39 个元素当前无引用，未列出。
class OctahedralGroup {
  const OctahedralGroup(
    this.name,
    this.permutation,
    this.invertX,
    this.invertY,
    this.invertZ,
  );

  final String name;
  final SymmetricGroup3 permutation;
  final bool invertX;
  final bool invertY;
  final bool invertZ;

  static const identity = OctahedralGroup(
      'identity', SymmetricGroup3.p123, false, false, false);

  // —— 原版常量（OctahedralGroup.java:34-39）——
  static const rot90XNeg =
      OctahedralGroup('rot_90_x_neg', SymmetricGroup3.p132, false, false, true);
  static const rot90XPos =
      OctahedralGroup('rot_90_x_pos', SymmetricGroup3.p132, false, true, false);
  static const rot90YNeg =
      OctahedralGroup('rot_90_y_neg', SymmetricGroup3.p321, true, false, false);
  static const rot90YPos =
      OctahedralGroup('rot_90_y_pos', SymmetricGroup3.p321, false, false, true);
  static const rot90ZNeg =
      OctahedralGroup('rot_90_z_neg', SymmetricGroup3.p213, false, true, false);
  static const rot90ZPos =
      OctahedralGroup('rot_90_z_pos', SymmetricGroup3.p213, true, false, false);

  // —— 原版常量（OctahedralGroup.java:17-19）——
  static const rot180FaceXY = OctahedralGroup(
      'rot_180_face_xy', SymmetricGroup3.p123, true, true, false);
  static const rot180FaceXZ = OctahedralGroup(
      'rot_180_face_xz', SymmetricGroup3.p123, true, false, true);
  static const rot180FaceYZ = OctahedralGroup(
      'rot_180_face_yz', SymmetricGroup3.p123, false, true, true);

  // —— 方块旋转别名（OctahedralGroup.java:65-73）——
  static const blockRotX90 = rot90XNeg;
  static const blockRotX180 = rot180FaceYZ;
  static const blockRotX270 = rot90XPos;
  static const blockRotY90 = rot90YNeg;
  static const blockRotY180 = rot180FaceXZ;
  static const blockRotY270 = rot90YPos;
  static const blockRotZ90 = rot90ZNeg;
  static const blockRotZ180 = rot180FaceXY;
  static const blockRotZ270 = rot90ZPos;

  /// `inverts(axis)`（判据 `OctahedralGroup.java:164-170`）。
  bool inverts(Axis axis) => switch (axis) {
        Axis.x => invertX,
        Axis.y => invertY,
        Axis.z => invertZ,
      };

  /// `compose`（判据 `OctahedralGroup.java:81-97` 的 CAYLEY_TABLE 构造）：
  ///
  /// - `composedPermutation = second.permutation.compose(first.permutation)`
  ///   （:88）⇒ `(a ∘ b).permute(i) = b.permute(a.permute(i))`；
  /// - `composedInvertX = first.inverts(X) ^ second.inverts(first.permutation
  ///   .permuteAxis(X))`（:89-91）⇒ 输出轴 r：`a.invert(r) ^ b.invert(p_a(r))`。
  ///
  /// 复合的施加顺序是 **b 先、a 后**（与矩阵乘 `T(a)·T(b)` 一致；推导见
  /// [Quadrant.fromXYAngles] 的用法——先 x 后 y）。
  OctahedralGroup compose(OctahedralGroup b) {
    final p = permutation;
    final pb = b.permutation;
    return OctahedralGroup(
      '$name+${b.name}',
      _byPermute(
        pb.permute(p.permute(0)),
        pb.permute(p.permute(1)),
        pb.permute(p.permute(2)),
      ),
      invertX ^ b.inverts(Axis.byOrdinal(p.permute(0))),
      invertY ^ b.inverts(Axis.byOrdinal(p.permute(1))),
      invertZ ^ b.inverts(Axis.byOrdinal(p.permute(2))),
    );
  }

  /// `inverse`（判据 `OctahedralGroup.java:98-100`：compose 后为 identity 者）。
  OctahedralGroup inverse() {
    final p = permutation;
    // 逆元的置换是 p⁻¹，翻转位取 p⁻¹ 处的原翻转位（由 compose 公式反解）。
    final q = p.inverse();
    return OctahedralGroup(
      '${name}_inv',
      q,
      inverts(Axis.byOrdinal(q.permute(0))),
      inverts(Axis.byOrdinal(q.permute(1))),
      inverts(Axis.byOrdinal(q.permute(2))),
    );
  }

  /// `rotate(Direction)`（判据 `OctahedralGroup.java:142-154`）：
  /// 新轴 = `permutation.inverse().permuteAxis(oldAxis)`，新正负按新轴翻转位。
  Direction rotate(Direction facing) {
    final newAxis =
        Axis.byOrdinal(permutation.inverse().permute(facing.axis.index));
    final newDirection =
        inverts(newAxis) ? facing.axisDirection.opposite : facing.axisDirection;
    return Direction.fromAxisAndDirection(newAxis, newDirection);
  }

  /// `rotate(Vector3i)` 的连续坐标版：把 0..1 方块内坐标绕块中心 (0.5,0.5,0.5)
  /// 施加群变换（先置换后翻转，判据 `OctahedralGroup.java:156-162`；中心平移
  /// 对应 `BlockMath.blockCenterToCorner` / `FaceBakery` 的 `BLOCK_MIDDLE`）。
  ({double x, double y, double z}) rotatePoint(
      ({double x, double y, double z}) v) {
    final px = _flip(permutation.permute(0), v);
    final py = _flip(permutation.permute(1), v);
    final pz = _flip(permutation.permute(2), v);
    return (
      x: _shift(px, invertX),
      y: _shift(py, invertY),
      z: _shift(pz, invertZ),
    );
  }

  static double _shift(double centered, bool invert) =>
      centered * (invert ? -1.0 : 1.0) + 0.5;

  /// 取第 [axisIndex] 个输入分量（0..1 坐标），转到中心对称坐标。
  static double _flip(int axisIndex, ({double x, double y, double z}) v) =>
      switch (axisIndex) {
        0 => v.x - 0.5,
        1 => v.y - 0.5,
        _ => v.z - 0.5,
      };

  bool get isIdentity =>
      identical(permutation, SymmetricGroup3.p123) &&
      !invertX &&
      !invertY &&
      !invertZ;

  @override
  String toString() => name;

  static SymmetricGroup3 _byPermute(int p0, int p1, int p2) =>
      SymmetricGroup3.values
          .firstWhere((r) => r.p0 == p0 && r.p1 == p1 && r.p2 == p2);
}
