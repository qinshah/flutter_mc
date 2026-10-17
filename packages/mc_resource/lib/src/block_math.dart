/// `net/minecraft/core/BlockMath.java` 的 Dart 对应物（纯 Dart）。
///
/// **表示注记**（自由设计：JOML `Matrix4f` 是外部库，不在 mc-sources 判据内；
/// 本路径的全部变换——`VANILLA_UV_TRANSFORM_*` 的 ±90° 四元数与
/// `BlockModelRotation` 的 `OctahedralGroup`——都是**符号置换矩阵**，故用
/// [OctahedralGroup] 元素表示，语义逐项对应原版矩阵运算）。
library;

import 'direction.dart';
import 'octahedral_group.dart';

/// `VANILLA_UV_TRANSFORM_LOCAL_TO_GLOBAL`（判据 `BlockMath.java:13-28`）：
/// 面局部 UV 坐标系 → 世界坐标系。四个 ±90° 四元数对应的群元素：
///
/// - `rotateY(+π/2)`：`(x,y,z) → (z,y,−x)` = `ROT_90_Y_POS`
/// - `rotateY(−π/2)`：`(x,y,z) → (−z,y,x)` = `ROT_90_Y_NEG`
/// - `rotateY(π)`：`(x,y,z) → (−x,y,−z)` = `ROT_180_FACE_XZ`
/// - `rotateX(−π/2)`：`(x,y,z) → (x,z,−y)` = `ROT_90_X_NEG`
/// - `rotateX(+π/2)`：`(x,y,z) → (x,−z,y)` = `ROT_90_X_POS`
OctahedralGroup uvTransformLocalToGlobal(Direction side) => switch (side) {
      Direction.south => OctahedralGroup.identity,
      Direction.east => OctahedralGroup.rot90YPos,
      Direction.west => OctahedralGroup.rot90YNeg,
      Direction.north => OctahedralGroup.rot180FaceXZ,
      Direction.up => OctahedralGroup.rot90XNeg,
      Direction.down => OctahedralGroup.rot90XPos,
    };

/// `VANILLA_UV_TRANSFORM_GLOBAL_TO_LOCAL`（判据 `BlockMath.java:29-30`：
/// 逐项取逆）。
OctahedralGroup uvTransformGlobalToLocal(Direction side) =>
    uvTransformLocalToGlobal(side).inverse();

/// `BlockMath.getFaceTransformation`（判据 `BlockMath.java:47-57`）。
///
/// 把「原面局部 UV 坐标系」映射到「旋转后新面的局部 UV 坐标系」：
/// `GTL[newSide] ∘ (G ∘ LTG[originalSide])`（`Transformation.compose(a, b)`
/// 是 **a 先、b 后**，判据 `Transformation.java:64-68` 矩阵 `this·that`）。
///
/// `newSide` 由 `faceAction` 作用于 (0,0,1) 后取最近方向（:54-55）——群元素
/// 下即 [OctahedralGroup.rotate]（轴对齐，精确）。
OctahedralGroup getFaceTransformation(
  OctahedralGroup transformation,
  Direction originalSide,
) {
  if (transformation.isIdentity) {
    return transformation;
  }

  final faceAction =
      transformation.compose(uvTransformLocalToGlobal(originalSide));
  final newSide = faceAction.rotate(Direction.south);
  return uvTransformGlobalToLocal(newSide).compose(faceAction);
}
