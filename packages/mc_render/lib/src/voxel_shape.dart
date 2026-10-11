

import 'dart:math' as math;

/// `net/minecraft/world/phys/shapes/VoxelShape.java` + `Shapes.java` 的 Dart
/// 对应物（碰撞用核心子集）。
///
/// **表示**：0..1 格内坐标的轴对齐盒并集（原版为离散区间优化的
/// ArrayVoxelShape；此处盒列表——并集/逐轴 clip 语义一致，优化结构为债）。
class BlockBox {
  const BlockBox(this.minX, this.minY, this.minZ, this.maxX, this.maxY, this.maxZ);

  final double minX;
  final double minY;
  final double minZ;
  final double maxX;
  final double maxY;
  final double maxZ;
}

class VoxelShape {
  VoxelShape(this.boxes);

  /// 并集内的盒（格内 0..1 坐标）。
  final List<BlockBox> boxes;

  bool get isEmpty => boxes.isEmpty;

  /// 全格实心（判据 `Shapes.block()`）。
  factory VoxelShape.full() => VoxelShape(const [BlockBox(0, 0, 0, 1, 1, 1)]);

  /// `Shapes.or`（并集；盒列表直接拼接——并集语义由 collide 的逐盒处理保证）。
  static VoxelShape or(VoxelShape a, VoxelShape b) => VoxelShape([...a.boxes, ...b.boxes]);

  /// `Block.column(sizeXZ, minY, maxY)`（Block.java:177-185）：x/z 居中、
  /// 像素坐标 ÷16。
  factory VoxelShape.column(double sizeXZ, double minY, double maxY) {
    final half = sizeXZ / 2 / 16;
    return VoxelShape([
      BlockBox(0.5 - half, minY / 16, 0.5 - half, 0.5 + half, maxY / 16, 0.5 + half),
    ]);
  }

  /// `Block.box(minX, minY, minZ, maxX, maxY, maxZ)`（像素 → /16，Block.java:160-162）。
  factory VoxelShape.box(double minX, double minY, double minZ, double maxX, double maxY, double maxZ) {
    return VoxelShape([
      BlockBox(minX / 16, minY / 16, minZ / 16, maxX / 16, maxY / 16, maxZ / 16),
    ]);
  }

  /// 绕 Y 轴顺时针 90° 旋转（俯视 x→z 方向）：(x,z) → (z, 1-x)。
  VoxelShape rotateY90() => VoxelShape([
        for (final b in boxes)
          BlockBox(b.minZ, b.minY, 1 - b.maxX, b.maxZ, b.maxY, 1 - b.minX),
      ]);

  /// 绕 X 轴镜像 y（`OctahedralGroup.INVERT_Y` 用于楼梯 half=top）。
  VoxelShape invertY() => VoxelShape([
        for (final b in boxes)
          BlockBox(b.minX, 1 - b.maxY, b.minZ, b.maxX, 1 - b.minY, b.maxZ),
      ]);
}

/// 实体包围盒（世界坐标）——碰撞求解用；与 app 壳 `Aabb` 解耦（mc_render 纯 Dart）。
class CollisionAabb {
  const CollisionAabb(this.minX, this.minY, this.minZ, this.maxX, this.maxY, this.maxZ);

  final double minX;
  final double minY;
  final double minZ;
  final double maxX;
  final double maxY;
  final double maxZ;

  /// `AABB.expandTowards(dx, dy, dz)`。
  CollisionAabb expandTowards(double dx, double dy, double dz) => CollisionAabb(
        dx < 0 ? minX + dx : minX,
        dy < 0 ? minY + dy : minY,
        dz < 0 ? minZ + dz : minZ,
        dx > 0 ? maxX + dx : maxX,
        dy > 0 ? maxY + dy : maxY,
        dz > 0 ? maxZ + dz : maxZ,
      );

  /// `AABB.move(dx, dy, dz)`。
  CollisionAabb move(double dx, double dy, double dz) =>
      CollisionAabb(minX + dx, minY + dy, minZ + dz, maxX + dx, maxY + dy, maxZ + dz);
}

/// `Shapes.collide(axis, box, shapes, movement)` 的盒列表等价实现。
///
/// 语义（判据 `VoxelShape.collideX`，VoxelShape.java:251-300——**逐形状体素
/// 扫描**：只扫描盒在轴上**占据格之外**的体素，首个实心格
/// `newDistance = 体素边缘 − 盒边缘`，`newDistance >= -1e-7` 才截停）：
///
/// - 前方/贴面的盒：截停到 `表面 − 盒边缘`（贴面=0；原版允许 ≤ 1e-7 的负值
///   微调回贴，此处钳到 0——位置已是 double（Vec3），float32 抖动不复存在，
///   钳 0 与原版差异 ≤ 1e-7 不可观测）；
/// - **已穿透的盒（近缘落后盒远缘 > eps）：完全不参与本轴阻挡**——原版扫描
///   从盒占据格之后开始，穿透体素不在扫描范围。平移滑行/逃离/穿出全部放行
///   （2026-10-11 实机"贴墙卡死"的根因即旧实现的穿透锁死把滑行轴一并锁死）；
///   穿入方向继续深入时由**下一块**墙在贴面处截停（与原版一致，穿不出墙外）。
/// - 其余两轴的重叠判定含 1e-7 收缩（`findIndex(min+eps)`/`findIndex(max−eps)`
///   的区间等价），仅边缘接触的盒不算重叠。
double collideAlongAxis({
  required CollisionAabb box,
  required List<BlockBox> colliders,
  required int axis, // 0=x 1=y 2=z
  required double movement,
  double epsilon = 1.0E-7,
}) {
  if (movement == 0.0) return 0.0;
  var allowed = movement;
  for (final b in colliders) {
    if (!_overlapsOtherAxes(box, b, axis, epsilon)) continue;
    final boxMin = _axisMin(box, axis);
    final boxMax = _axisMax(box, axis);
    final bMin = _boxMin(b, axis);
    final bMax = _boxMax(b, axis);
    if (movement > 0) {
      if (bMin >= boxMax - epsilon) {
        // 未穿透（前方或贴面）：截停到表面（贴面=0，不回退）。
        final candidate = math.max(0.0, bMin - boxMax);
        if (candidate < allowed) allowed = candidate;
      }
      // else：轴向已穿透 → 跳过（判据见函数头注释）。
    } else {
      if (bMax <= boxMin + epsilon) {
        final candidate = math.min(0.0, bMax - boxMin);
        if (candidate > allowed) allowed = candidate;
      }
    }
  }
  return allowed;
}

bool _overlapsOtherAxes(CollisionAabb box, BlockBox b, int axis, double eps) {
  switch (axis) {
    case 0:
      return box.minY < b.maxY - eps &&
          box.maxY > b.minY + eps &&
          box.minZ < b.maxZ - eps &&
          box.maxZ > b.minZ + eps;
    case 1:
      return box.minX < b.maxX - eps &&
          box.maxX > b.minX + eps &&
          box.minZ < b.maxZ - eps &&
          box.maxZ > b.minZ + eps;
    default:
      return box.minX < b.maxX - eps &&
          box.maxX > b.minX + eps &&
          box.minY < b.maxY - eps &&
          box.maxY > b.minY + eps;
  }
}

double _axisMin(CollisionAabb b, int axis) => axis == 0 ? b.minX : (axis == 1 ? b.minY : b.minZ);
double _axisMax(CollisionAabb b, int axis) => axis == 0 ? b.maxX : (axis == 1 ? b.maxY : b.maxZ);
double _boxMin(BlockBox b, int axis) => axis == 0 ? b.minX : (axis == 1 ? b.minY : b.minZ);
double _boxMax(BlockBox b, int axis) => axis == 0 ? b.maxX : (axis == 1 ? b.maxY : b.maxZ);
