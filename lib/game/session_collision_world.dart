import 'package:mc_render/mc_render.dart';
import 'package:mc_session/mc_session.dart';

import 'collision.dart';
/// 碰撞查询的会话世界适配。
///
/// 原版对应物：`client.multiplayer.ClientLevel` 的 `getBlockState` 那一面——碰撞读的是
/// **客户端世界镜像**，不是服务器（本地预测的全部依据）。
///
/// 未加载列按**不阻挡**处理：原版客户端在未加载区不会把玩家卡住，与
/// `VoxelCollision` 的联机口径（`unloadedPassable`）一致。
class SessionCollisionWorld implements CollisionWorld {
  SessionCollisionWorld(this._columns);

  final Map<(int, int), RemoteChunkColumn> _columns;

  /// 世界竖直范围：26.x overworld 从 −64 起、高 384（= −64..320）。
  ///
  /// **必须写成世界坐标**：早先把下界当 0 用，等于把整个世界往上抬了 64 格
  /// （见 `RemoteChunkColumn.minSectionY`）。`worldHeight` 供底层求解判"顶上没东西"。
  static const int kMinY = -64;
  static const int kMaxY = 320;
  static const int kWorldHeight = kMaxY;

  static const BlockSemanticsV262 _semantics = BlockSemanticsV262();

  @override
  int get worldHeight => kWorldHeight;

  @override
  bool isColumnLoaded(int cx, int cz) => _columns.containsKey((cx, cz));

  /// 该格的方块状态号（未加载/越界返回 null）。供调试射线用。
  int? stateAtBlock(int bx, int by, int bz) {
    if (by < kMinY || by >= kMaxY) return null;
    final column = _columns[(bx >> 4, bz >> 4)];
    if (column == null) return null;
    return column.stateAt(bx & 15, by, bz & 15);
  }

  @override
  bool isCollidable(int bx, int by, int bz) {
    if (by < kMinY || by >= kMaxY) return false;
    final column = _columns[(bx >> 4, bz >> 4)];
    if (column == null) return false; // 未加载：不阻挡
    return _semantics.isCollidable(column.stateAt(bx & 15, by, bz & 15));
  }

  /// 该格的碰撞形状（判据 `BlockStateBase.getCollisionShape`；身份串 →
  /// `BlockCollisionShapes`，覆盖族见 block-collision-shapes change）。
  /// 未加载/越界返回 null（空气语义）。
  @override
  VoxelShape? collisionShapeAt(int bx, int by, int bz) {
    if (by < kMinY || by >= kMaxY) return null;
    final column = _columns[(bx >> 4, bz >> 4)];
    if (column == null) return null;
    final identity = kBlockStateIdentity262[column.stateAt(bx & 15, by, bz & 15)];
    if (identity == null) return null;
    final shape = BlockCollisionShapes.shapeFor(identity);
    return shape.isEmpty ? null : shape;
  }

  @override
  String? blockIdentityAt(int bx, int by, int bz) {
    if (by < kMinY || by >= kMaxY) return null;
    final column = _columns[(bx >> 4, bz >> 4)];
    if (column == null) return null;
    return kBlockStateIdentity262[column.stateAt(bx & 15, by, bz & 15)];
  }

  @override
  double blockFrictionAt(int bx, int by, int bz) {
    if (by < kMinY || by >= kMaxY) return 0.6;
    final column = _columns[(bx >> 4, bz >> 4)];
    if (column == null) return 0.6; // 未加载：空气语义 ⇒ 默认摩擦
    final identity = kBlockStateIdentity262[column.stateAt(bx & 15, by, bz & 15)];
    if (identity == null) return 0.6;
    return BlockCollisionShapes.frictionFor(identity);
  }
}
