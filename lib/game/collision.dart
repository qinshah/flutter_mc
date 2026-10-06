import 'dart:math' as math;

/// 碰撞世界查询接口（app 壳内由 ClientWorld 实现；纯 Dart 可单测）。
abstract interface class CollisionWorld {
  /// 该格是否阻挡实体（非空气/液体/十字植物）。
  bool isCollidable(int bx, int by, int bz);

  /// 列 (cx, cz) 是否已加载。
  bool isColumnLoaded(int cx, int cz);

  /// 世界高度（0..worldHeight）。
  int get worldHeight;
}

/// 实体轴对齐包围盒（移植自 fscraft collision.dart）。宽 0.6 / 高 1.8，
/// [position] 是盒子底面中心（原版实体的 posY 在脚底）。
class Aabb {
  Aabb(this.centerX, this.minY, this.centerZ, double width, double height)
      : halfWidth = width / 2,
        maxY = minY + height;

  double centerX;
  double minY;
  double centerZ;

  final double halfWidth;
  double maxY;

  double get minX => centerX - halfWidth;
  double get x1 => centerX + halfWidth;
  double get minZ => centerZ - halfWidth;
  double get z1 => centerZ + halfWidth;

  static const double eyeHeight = 1.62;
  static const double playerWidth = 0.6;
  static const double playerHeight = 1.8;

  factory Aabb.player(double x, double y, double z) =>
      Aabb(x, y, z, playerWidth, playerHeight);

  bool intersects(Aabb other) =>
      minX < other.x1 &&
      x1 > other.minX &&
      minY < other.maxY &&
      maxY > other.minY &&
      minZ < other.z1 &&
      z1 > other.minZ;
}

/// 一次逐轴求解的结果。
class MoveResult {
  const MoveResult({
    required this.centerX,
    required this.minY,
    required this.centerZ,
    required this.hitX,
    required this.hitY,
    required this.hitZ,
    required this.hasBlockBelow,
  });

  final double centerX;
  final double minY;
  final double centerZ;
  final bool hitX;
  final bool hitY;
  final bool hitZ;
  final bool hasBlockBelow;

  bool get onGround => hitY && hasBlockBelow;
}

/// 逐轴 AABB ↔ 体素网格碰撞求解（移植自 fscraft collision.dart）。
///
/// **联机构造必须 `unloadedPassable: true`**：原版客户端在未加载区可走，
/// 掉落由服务器权威位置回拉纠正；否则视距边缘会出现隐形空气墙。
class VoxelCollision {
  VoxelCollision(this.world, {this.epsilon = 1e-4, this.unloadedPassable = true});

  final CollisionWorld world;
  final bool unloadedPassable;
  final double epsilon;

  static const double _groundProbe = 0.1;

  MoveResult move(Aabb box, double dx, double dy, double dz) {
    var x = box.centerX;
    var y = box.minY;
    var z = box.centerZ;
    final height = box.maxY - box.minY;
    final halfWidth = box.halfWidth;

    var hitX = false;
    var hitY = false;
    var hitZ = false;

    if (dy > 0) {
      final top = y + height;
      for (var by = top.ceil(); by <= (top + dy).floor(); by++) {
        if (_layerBlockedY(by, x, z, halfWidth)) {
          y = by - height - epsilon;
          hitY = true;
          break;
        }
      }
      if (!hitY) y += dy;
    } else if (dy < 0) {
      for (var by = y.floor(); by >= (y + dy).floor(); by--) {
        if (_layerBlockedY(by, x, z, halfWidth)) {
          y = by + 1.0 + epsilon;
          hitY = true;
          break;
        }
      }
      if (!hitY) y += dy;
    }

    if (dx > 0) {
      final edge = x + halfWidth;
      for (var bx = edge.ceil(); bx <= (edge + dx).floor(); bx++) {
        if (_layerBlockedX(bx, y, z, height, halfWidth)) {
          x = bx - halfWidth - epsilon;
          hitX = true;
          break;
        }
      }
      if (!hitX) x += dx;
    } else if (dx < 0) {
      final edge = x - halfWidth;
      for (var bx = edge.floor(); bx >= (edge + dx).floor(); bx--) {
        if (_layerBlockedX(bx, y, z, height, halfWidth)) {
          x = bx + 1.0 + halfWidth + epsilon;
          hitX = true;
          break;
        }
      }
      if (!hitX) x += dx;
    }

    if (dz > 0) {
      final edge = z + halfWidth;
      for (var bz = edge.ceil(); bz <= (edge + dz).floor(); bz++) {
        if (_layerBlockedZ(bz, x, y, halfWidth, height)) {
          z = bz - halfWidth - epsilon;
          hitZ = true;
          break;
        }
      }
      if (!hitZ) z += dz;
    } else if (dz < 0) {
      final edge = z - halfWidth;
      for (var bz = edge.floor(); bz >= (edge + dz).floor(); bz--) {
        if (_layerBlockedZ(bz, x, y, halfWidth, height)) {
          z = bz + 1.0 + halfWidth + epsilon;
          hitZ = true;
          break;
        }
      }
      if (!hitZ) z += dz;
    }

    final hasBlockBelow = dy > 0 ? false : _hasBlockBelow(x, y, z, halfWidth);

    return MoveResult(
      centerX: x,
      minY: y,
      centerZ: z,
      hitX: hitX,
      hitY: hitY,
      hitZ: hitZ,
      hasBlockBelow: hasBlockBelow,
    );
  }

  bool _layerBlockedY(int by, double x, double z, double halfWidth) {
    if (by < 0) return true;
    if (by >= world.worldHeight) return false;
    for (var bz = (z - halfWidth).floor();
        bz <= (z + halfWidth - epsilon).floor();
        bz++) {
      for (var bx = (x - halfWidth).floor();
          bx <= (x + halfWidth - epsilon).floor();
          bx++) {
        if (world.isCollidable(bx, by, bz)) return true;
      }
    }
    return false;
  }

  bool _layerBlockedX(int bx, double y, double z, double height, double halfWidth) {
    for (var by = y.floor(); by <= (y + height - epsilon).floor(); by++) {
      if (by < 0) return true;
      if (by >= world.worldHeight) continue;
      for (var bz = (z - halfWidth).floor();
          bz <= (z + halfWidth - epsilon).floor();
          bz++) {
        if (world.isCollidable(bx, by, bz)) return true;
      }
    }
    return false;
  }

  bool _layerBlockedZ(int bz, double x, double y, double halfWidth, double height) {
    for (var by = y.floor(); by <= (y + height - epsilon).floor(); by++) {
      if (by < 0) return true;
      if (by >= world.worldHeight) continue;
      for (var bx = (x - halfWidth).floor();
          bx <= (x + halfWidth - epsilon).floor();
          bx++) {
        if (world.isCollidable(bx, by, bz)) return true;
      }
    }
    return false;
  }

  bool _hasBlockBelow(double cx, double y, double cz, double halfWidth) {
    final by = (y - _groundProbe).floor();
    if (by < 0) return true;
    if (by >= world.worldHeight) return false;
    final x0 = (cx - halfWidth).floor();
    final x1 = (cx + halfWidth - epsilon).floor();
    final z0 = (cz - halfWidth).floor();
    final z1 = (cz + halfWidth - epsilon).floor();
    for (var bz = z0; bz <= z1; bz++) {
      for (var bx = x0; bx <= x1; bx++) {
        if (world.isCollidable(bx, by, bz)) return true;
      }
    }
    return false;
  }
}

/// 高速移动按轴拆步（隧穿防护）。
List<List<double>> substeps(double dx, double dy, double dz,
    {double maxStep = 0.4}) {
  final maxLen = math.max(dx.abs(), math.max(dy.abs(), dz.abs()));
  if (maxLen <= maxStep) {
    return [
      [dx, dy, dz]
    ];
  }
  final n = (maxLen / maxStep).ceil();
  return [
    for (var i = 0; i < n; i++) [dx / n, dy / n, dz / n]
  ];
}
