/// `net/minecraft/client/renderer/block/dispatch/BlockModelRotation.java`
/// 的 Dart 对应物（本实现用到的子集，纯 Dart）。
///
/// blockstate 变体旋转（`x`/`y`/`z` 角度 + `uvlock`）烘焙成的模型状态：
/// - 变换本体 = 角度复合出的 [OctahedralGroup]（判据 `Variant.java:73-76`
///   的 `asModelState` → `BlockModelRotation.get(Quadrant.fromXYZAngles(...))`；
///   角度 → 群元素见 `Quadrant.java:9-12` 的 R90/R180/R270 映射，复合顺序见
///   `Quadrant.fromXYZAngles`（`Quadrant.java:57-59`）：**x 先、y 后、z 最后**）。
/// - `uvlock=true` 时面变换走 `WithUvLock`（判据 `BlockModelRotation.java:55-75`），
///   否则用 [ModelState] 默认的 NO_TRANSFORM（判据 `ModelState.java:15-21`）。
library;

import 'block_math.dart';
import 'direction.dart';
import 'octahedral_group.dart';

/// blockstate 变体的模型旋转状态（`BlockModelRotation` + uvlock 标记）。
class BlockModelRotation {
  BlockModelRotation._(this.group, this.uvLock);

  /// 群元素形式的变换（`transformation()`，判据 `BlockModelRotation.java:24-28`：
  /// `new Matrix4f(orientation.transformation())`）。
  final OctahedralGroup group;

  /// `uvlock`（`withUvLock()`，判据 `BlockModelRotation.java:46-48`）。
  final bool uvLock;

  /// `BlockModelRotation.get(Quadrant.fromXYZAngles(x, y, z))` +
  /// `uvLock ? rotation.withUvLock() : rotation`（判据 `Variant.java:73-76`）。
  factory BlockModelRotation.fromAngles(int xDeg, int yDeg, int zDeg,
      {required bool uvLock}) {
    return BlockModelRotation._(
      _fromXYZAngles(_quadrant(xDeg), _quadrant(yDeg), _quadrant(zDeg)),
      uvLock,
    );
  }

  /// `Quadrant.CODEC`（判据 `Quadrant.java:14-21`：positiveModulo 360 后只认
  /// 0/90/180/270，其余非法）。非法角度返回 null（原版该 blockstate 解析失败，
  /// 模型不加载 ⇒ 调用方回退无几何）。
  static BlockModelRotation? tryFromAngles(int xDeg, int yDeg, int zDeg,
      {required bool uvLock}) {
    final x = _tryQuadrant(xDeg);
    if (x == null) return null;
    final y = _tryQuadrant(yDeg);
    if (y == null) return null;
    final z = _tryQuadrant(zDeg);
    if (z == null) return null;
    return BlockModelRotation._(_fromXYZAngles(x, y, z), uvLock);
  }

  /// `BlockModelRotation.inverseFaceTransformation(face)`（烘焙 UV 用，
  /// 判据 `FaceBakery.java:85`）：
  /// - 非 uvlock：NO_TRANSFORM（`ModelState.java:19-21` 默认）→ 返回 null
  ///   表示恒等；
  /// - uvlock：`inverseFaceMapping[face]`（`BlockModelRotation.java:30-34`
  ///   的 `getFaceTransformation(...).invertAffine`）。
  OctahedralGroup? inverseFaceTransformation(Direction face) {
    if (!uvLock) return null;
    return getFaceTransformation(group, face).inverse();
  }

  /// `Quadrant.fromXYZAngles`（判据 `Quadrant.java:57-59`）：
  /// `z.rotationZ.compose(y.rotationY.compose(x.rotationX))`。
  static OctahedralGroup _fromXYZAngles(int x, int y, int z) {
    final gx = _rotX(x), gy = _rotY(y), gz = _rotZ(z);
    return gz.compose(gy.compose(gx));
  }

  static int _quadrant(int degrees) {
    final m = degrees % 360;
    return switch (m) {
      0 || 90 || 180 || 270 => m,
      _ => throw ArgumentError(
          'Invalid rotation $degrees found, only 0/90/180/270 allowed'),
    };
  }

  static int? _tryQuadrant(int degrees) => switch (degrees % 360) {
        0 || 90 || 180 || 270 => degrees % 360,
        _ => null,
      };

  /// `Quadrant` 的 rotationX/rotationY/rotationZ 映射
  /// （判据 `Quadrant.java:9-12` + `OctahedralGroup.java:65-73`）。
  static OctahedralGroup _rotX(int q) => switch (q) {
        0 => OctahedralGroup.identity,
        90 => OctahedralGroup.blockRotX90,
        180 => OctahedralGroup.blockRotX180,
        _ => OctahedralGroup.blockRotX270,
      };

  static OctahedralGroup _rotY(int q) => switch (q) {
        0 => OctahedralGroup.identity,
        90 => OctahedralGroup.blockRotY90,
        180 => OctahedralGroup.blockRotY180,
        _ => OctahedralGroup.blockRotY270,
      };

  static OctahedralGroup _rotZ(int q) => switch (q) {
        0 => OctahedralGroup.identity,
        90 => OctahedralGroup.blockRotZ90,
        180 => OctahedralGroup.blockRotZ180,
        _ => OctahedralGroup.blockRotZ270,
      };
}
