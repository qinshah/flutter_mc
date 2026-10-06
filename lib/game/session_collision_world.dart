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

  /// 世界高度：26.x 默认 384（24 段 × 16），与 `ChunkIngestor` 的段数一致。
  static const int kWorldHeight = 384;

  static const BlockSemanticsV262 _semantics = BlockSemanticsV262();

  @override
  int get worldHeight => kWorldHeight;

  @override
  bool isColumnLoaded(int cx, int cz) => _columns.containsKey((cx, cz));

  @override
  bool isCollidable(int bx, int by, int bz) {
    if (by < 0 || by >= kWorldHeight) return false;
    final column = _columns[(bx >> 4, bz >> 4)];
    if (column == null) return false; // 未加载：不阻挡
    return _semantics.isCollidable(column.stateAt(bx & 15, by, bz & 15));
  }
}
