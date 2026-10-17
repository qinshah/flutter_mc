

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

  @override
  bool operator ==(Object other) =>
      other is BlockBox &&
      minX == other.minX &&
      minY == other.minY &&
      minZ == other.minZ &&
      maxX == other.maxX &&
      maxY == other.maxY &&
      maxZ == other.maxZ;

  @override
  int get hashCode => Object.hash(minX, minY, minZ, maxX, maxY, maxZ);
}

class VoxelShape {
  VoxelShape(this.boxes);

  /// 并集内的盒（格内 0..1 坐标）。
  final List<BlockBox> boxes;

  bool get isEmpty => boxes.isEmpty;

  /// 全格实心（判据 `Shapes.block()`）。
  factory VoxelShape.full() => VoxelShape(const [BlockBox(0, 0, 0, 1, 1, 1)]);

  /// `Shapes.or`（并集）。原版基于离散体素集，重复/相邻部分天然吞并；盒列表
  /// 表示下做精确规范化——完全重复的盒去重、共面贴合且其余轴对齐的盒并成
  /// 极大盒。合并是并集恒等的（StairBlock 的 OUTER→STRAIGHT→INNER 复合依赖
  /// 此语义，StairBlock.java:40-42）。
  static VoxelShape or(VoxelShape a, VoxelShape b) =>
      VoxelShape(_mergeBoxes([...a.boxes, ...b.boxes]));

  /// 极大盒合并：反复寻找可合并对直至不动点（形状均为盒列表，规模极小）。
  static List<BlockBox> _mergeBoxes(List<BlockBox> input) {
    final boxes = input.toList();
    var changed = true;
    while (changed) {
      changed = false;
      for (var i = 0; i < boxes.length && !changed; i++) {
        for (var j = i + 1; j < boxes.length; j++) {
          final m = _tryMerge(boxes[i], boxes[j]);
          if (m != null) {
            boxes
              ..removeAt(j)
              ..removeAt(i)
              ..insert(i, m);
            changed = true;
            break;
          }
        }
      }
    }
    return boxes;
  }

  /// 两盒可合并（全等，或共面贴合且其余轴区间相等）则返回并盒，否则 null。
  static BlockBox? _tryMerge(BlockBox a, BlockBox b) {
    if (a == b) return a;
    for (final axis in const ['x', 'y', 'z']) {
      final (aLo, aHi, bLo, bHi) = switch (axis) {
        'x' => (a.minX, a.maxX, b.minX, b.maxX),
        'y' => (a.minY, a.maxY, b.minY, b.maxY),
        _ => (a.minZ, a.maxZ, b.minZ, b.maxZ),
      };
      final touching = (aHi == bLo || bHi == aLo);
      final restEqual = switch (axis) {
        'x' => a.minY == b.minY && a.maxY == b.maxY && a.minZ == b.minZ && a.maxZ == b.maxZ,
        'y' => a.minX == b.minX && a.maxX == b.maxX && a.minZ == b.minZ && a.maxZ == b.maxZ,
        _ => a.minX == b.minX && a.maxX == b.maxX && a.minY == b.minY && a.maxY == b.maxY,
      };
      if (restEqual && touching) {
        return switch (axis) {
          'x' => BlockBox(math.min(aLo, bLo), a.minY, a.minZ, math.max(aHi, bHi), a.maxY, a.maxZ),
          'y' => BlockBox(a.minX, math.min(aLo, bLo), a.minZ, a.maxX, math.max(aHi, bHi), a.maxZ),
          _ => BlockBox(a.minX, a.minY, math.min(aLo, bLo), a.maxX, a.maxY, math.max(aHi, bHi)),
        };
      }
    }
    return null;
  }

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

  // —— Shapes.rotate(shape, OctahedralGroup)（Shapes.java:301-330）的 Y 轴
  //    子集：新轴 i 取 source 轴 permutation.permute(i) 的坐标（SymmetricGroup3
  //    .permute，SymmetricGroup3.java:59-70），invert 时绕块中心 0.5 翻转
  //    （flipAxisIfNeeded，Shapes.java:333-345）。盒并集表示下对每盒逐点映射
  //    精确等价（映射是仿射双射）。四个 group 的置换/翻转位见
  //    OctahedralGroup.java:34-42，别名见 :65-73。

  /// `BLOCK_ROT_Y_90`（= ROT_90_Y_NEG，P321 + invertX）：(x,y,z) → (1−z, y, x)，
  /// 俯视顺时针（N→E，rotateHorizontal 的 EAST 项，Shapes.java:396）。
  VoxelShape rotateY90() => VoxelShape([
        for (final b in boxes)
          BlockBox(1 - b.maxZ, b.minY, b.minX, 1 - b.minZ, b.maxY, b.maxX),
      ]);

  /// `BLOCK_ROT_Y_180`（= ROT_180_FACE_XZ，P123 + invertX/invertZ）：
  /// (x,y,z) → (1−x, y, 1−z)。
  VoxelShape rotateY180() => VoxelShape([
        for (final b in boxes)
          BlockBox(1 - b.maxX, b.minY, 1 - b.maxZ, 1 - b.minX, b.maxY, 1 - b.minZ),
      ]);

  /// `BLOCK_ROT_Y_270`（= ROT_90_Y_POS，P321 + invertZ）：(x,y,z) → (z, y, 1−x)。
  VoxelShape rotateY270() => VoxelShape([
        for (final b in boxes)
          BlockBox(b.minZ, b.minY, 1 - b.maxX, b.maxZ, b.maxY, 1 - b.minX),
      ]);

  /// `OctahedralGroup.INVERT_Y`（OctahedralGroup.java:42，P123 + invertY）：
  /// (x,y,z) → (x, 1−y, z)。用于楼梯 half=top（StairBlock.java:46-48）。
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
