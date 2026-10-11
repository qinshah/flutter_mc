import 'dart:typed_data';

import 'package:mc_render/mc_render.dart';

/// 碰撞世界查询接口（app 壳内由 SessionCollisionWorld 实现；纯 Dart 可单测）。
abstract interface class CollisionWorld {
  /// 该格的碰撞形状（`BlockStateBase.getCollisionShape` 对应物）；
  /// 未加载/无碰撞返回 null（空气语义）。
  VoxelShape? collisionShapeAt(int bx, int by, int bz);

  /// 该格方块的摩擦（`BlockBehaviourProperties.friction`；判据
  /// `travelInAir` 的 `blockFriction` 采样，LivingEntity.java:2451-2453）。
  /// 未加载返回默认 0.6（与碰撞同口径：未加载 = 空气/常规地面）。
  double blockFrictionAt(int bx, int by, int bz);

  /// 该格的身份串（诊断穿透探针用；null = 未加载/无解析）。
  String? blockIdentityAt(int bx, int by, int bz);

  /// 该格是否阻挡（**仅射线等布尔场景用**；实体求解走 [collisionShapeAt]）。
  bool isCollidable(int bx, int by, int bz);

  /// 列 (cx, cz) 是否已加载。
  bool isColumnLoaded(int cx, int cz);

  /// 世界高度。
  int get worldHeight;
}

/// 实体轴对齐包围盒（宽 0.6 / 高 1.8，[centerX]/[centerZ] 是盒子底面中心，
/// [minY] 是脚底——原版实体的 posY 在脚底）。
class Aabb {
  /// Java `float` 语义模拟：写入 Float32List 即按 float32 舍入，读出即
  /// 拓宽回 double——等价于 Java 的 `(double)(float)v`。
  static double _asF32(double v) => Float32List.fromList([v])[0];

  /// 建盒语义 = `EntityDimensions.makeBoundingBox`（判据
  /// EntityDimensions.java:19-22）：`width`/`height` 是 **float** 字段，
  /// 半宽走 float 除法 `float w = this.width / 2.0F`，高度以 float 拓宽
  /// 参与加法 `y + h`。故 0.6F 的半宽是 **0.30000001192092896** 而非
  /// double 的 0.3，1.8F 是 1.7999999523162842 而非 1.8。
  /// 差值 ~1.19e-8 不是数值噪声：客户端与服务器按同一 float 语义建盒，
  /// 贴面时上报的中心坐标必须落在 float 半宽决定的阈值上
  /// （241.0 + 0.30000001192092896），否则被服务器判为 CLIPPED_INTO_BLOCK
  /// 回拉抽搐（docs/walk-jitter-diagnosis.md）。
  Aabb(this.centerX, this.minY, this.centerZ, double width, double height)
      : halfWidth = _asF32(width) / 2, // float w = width / 2.0F
        maxY = minY + _asF32(height); // y + (float)height

  double centerX;
  double minY;
  double centerZ;

  final double halfWidth;
  double maxY;

  double get minX => centerX - halfWidth;
  double get x1 => centerX + halfWidth;
  double get maxX => x1;
  double get minZ => centerZ - halfWidth;
  double get z1 => centerZ + halfWidth;
  double get maxZ => z1;

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

/// 一次碰撞求解的结果（判据 `Entity.collide`/`Entity.move`，Entity.java:1139-1146）。
class MoveResult {
  const MoveResult({
    required this.centerX,
    required this.minY,
    required this.centerZ,
    required this.xCollision,
    required this.yCollision,
    required this.zCollision,
  });

  final double centerX;
  final double minY;
  final double centerZ;

  /// `movement.x != movementStep.x` 等（Entity.java:1143-1145）。
  final bool xCollision;
  final bool yCollision;
  final bool zCollision;

  /// `yCollision && movement.y < 0.0`（Entity.java:1146 onGroundAfterCollision）。
  bool onGroundOf(double movementY) => yCollision && movementY < 0;
}

/// 实体移动碰撞求解（判据 `Entity.collide` + `collideWithShapes`，
/// Entity.java:1139-1263 + `Attributes.STEP_HEIGHT`，Attributes.java:98-99）。
class VoxelCollision {
  VoxelCollision(this.world, {this.epsilon = 1.0E-7, this.unloadedPassable = true});

  final CollisionWorld world;

  /// 联机构造 `unloadedPassable: true`：未加载区按空气（原版客户端语义，
  /// `ClientChunkCache.java:76` EmptyLevelChunk），掉落由服务器回拉纠正。
  final bool unloadedPassable;

  /// `AABB.EPSILON`（AABB.java:14）。
  final double epsilon;

  /// 玩家步高（判据 `Attributes.STEP_HEIGHT` 默认 0.6，Attributes.java:98-99；
  /// 26.2 实体无载具/缓速项链场景，常量足够）。
  static const double maxUpStep = 0.6;

  /// `Entity.move(MoverType, Vec3)` 的碰撞半边：返回截停后的位移落点与
  /// 各轴碰撞标志。[wasOnGround] = 原版 `this.onGround()`（step-up 条件之一）。
  MoveResult move(Aabb box, double dx, double dy, double dz, {required bool wasOnGround}) {
    final aabb = CollisionAabb(box.minX, box.minY, box.minZ, box.maxX, box.maxY, box.maxZ);
    final colliders = _collectColliders(aabb.expandTowards(dx, dy, dz));

    // `collideWithShapes`（判据 J1，Entity.java:1249-1263）。
    var (rx, ry, rz) = _collideWithShapes(dx, dy, dz, aabb, colliders);
    final xCollision = rx != dx;
    final yCollision = ry != dy;
    final zCollision = rz != dz;
    final onGroundAfterCollision = yCollision && dy < 0.0; // Entity.java:1146

    // 自动上步（判据 J2-J4，Entity.java:1144-1181）。
    if (maxUpStep > 0.0 && (onGroundAfterCollision || wasOnGround) && (xCollision || zCollision)) {
      final groundedAabb = onGroundAfterCollision ? aabb.move(0, ry, 0) : aabb;
      var stepUpAabb = groundedAabb.expandTowards(dx, maxUpStep, dz);
      if (!onGroundAfterCollision) {
        stepUpAabb = stepUpAabb.expandTowards(0, -1.0E-5, 0); // Entity.java:1154-1155
      }
      final stepColliders = _collectColliders(stepUpAabb);
      final candidates = _collectCandidateStepUpHeights(
          groundedAabb, stepColliders, maxUpStep, ry); // Entity.java:1183-1197

      for (final h in candidates) {
        final (sx, sy, sz) = _collideWithShapes(dx, h, dz, groundedAabb, stepColliders);
        if (sx * sx + sz * sz > rx * rx + rz * rz) {
          final drop = aabb.minY - groundedAabb.minY; // Entity.java:1168-1170
          rx = sx;
          ry = sy - drop;
          rz = sz;
          break;
        }
      }
    }

    // 本帧着地状态由调用方按 `result.onGroundOf(dy)` 维护（vanilla 20Hz move
    // 口径：着地只在竖直位移非零的结算点更新）。

    return MoveResult(
      centerX: box.centerX + rx,
      minY: box.minY + ry,
      centerZ: box.centerZ + rz,
      xCollision: rx != dx,
      yCollision: ry != dy,
      zCollision: rz != dz,
    );
  }

  /// `collideWithShapes`（Entity.java:1249-1263）：空 colliders 原样返回；
  /// 按 `Direction.axisStepOrder`（Direction.java:379-381，|x|<|z| ⇒ YZX 否则
  /// YXZ）逐轴 `Shapes.collide`，零分量轴跳过。
  (double, double, double) _collideWithShapes(
      double dx, double dy, double dz, CollisionAabb box, List<BlockBox> colliders) {
    if (colliders.isEmpty) return (dx, dy, dz);
    var (rx, ry, rz) = (0.0, 0.0, 0.0);
    // Direction.java:379-381：Y 恒先；|x| < |z| ⇒ 后 Z 前 X，否则后 X 前 Z。
    final yFirst = [1];
    final rest = (dx.abs() < dz.abs()) ? [2, 0] : [0, 2];
    for (final axis in [...yFirst, ...rest]) {
      final m = axis == 0 ? dx : (axis == 1 ? dy : dz);
      if (m == 0.0) continue; // Entity.java:1256
      final resolved = collideAlongAxis(
          box: box.move(rx, ry, rz), colliders: colliders, axis: axis, movement: m, epsilon: epsilon);
      if (axis == 0) {
        rx = resolved;
      } else if (axis == 1) {
        ry = resolved;
      } else {
        rz = resolved;
      }
    }
    return (rx, ry, rz);
  }

  /// `collectCandidateStepUpHeights`（Entity.java:1183-1197）：collider 的 Y
  /// 坐标相对盒底 ∈ [0, maxUpStep] 且 != 已消化的 y 位移，升序去重。
  List<double> _collectCandidateStepUpHeights(
      CollisionAabb box, List<BlockBox> colliders, double maxStepHeight, double stepHeightToSkip) {
    final candidates = <double>{};
    for (final c in colliders) {
      for (final coord in [c.minY, c.maxY]) {
        final rel = coord - box.minY;
        if (rel >= 0.0 && rel != stepHeightToSkip && rel <= maxStepHeight) {
          candidates.add(rel);
        }
      }
    }
    final list = candidates.toList()..sort();
    return list;
  }

  /// 扫掠区域内的全部碰撞盒（世界坐标）。
  List<BlockBox> _collectColliders(CollisionAabb swept) {
    final out = <BlockBox>[];
    final bx0 = swept.minX.floor();
    final bx1 = swept.maxX.floor();
    final by0 = swept.minY.floor();
    final by1 = swept.maxY.floor();
    final bz0 = swept.minZ.floor();
    final bz1 = swept.maxZ.floor();
    for (var by = by0; by <= by1; by++) {
      for (var bz = bz0; bz <= bz1; bz++) {
        for (var bx = bx0; bx <= bx1; bx++) {
          final shape = world.collisionShapeAt(bx, by, bz);
          if (shape == null) continue;
          for (final b in shape.boxes) {
            out.add(BlockBox(b.minX + bx, b.minY + by, b.minZ + bz, b.maxX + bx, b.maxY + by, b.maxZ + bz));
          }
        }
      }
    }
    return out;
  }
}
