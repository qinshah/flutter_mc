import 'remote_chunk.dart';

/// `client/multiplayer/ClientChunkCache.java` 的 Dart 对应物（逐行翻译）。
///
/// **固定容量存储环**——客户端"超视距列及时卸载"的原版机制：容量有限、
/// 索引按模运算分布，新列写入自动顶替环上同索引旧列并触发卸载回调，
/// 完全不依赖服务器 ForgetLevelChunk 补发。
///
/// 判据（mc-sources/minecraft-26.2 `ClientChunkCache.java`）：
/// - `calculateStorageRange = max(2, viewRange) + 3`（:151-153）
/// - 容量 = `(2*chunkRadius+1)²`（:209-212 viewRange = chunkRadius*2+1）
/// - 索引 = `floorMod(z, viewRange)*viewRange + floorMod(x, viewRange)`（:222-224）
/// - 写入越界（切比雪夫距离 > chunkRadius）拒收 + warn（:100-103）
/// - 顶替旧列 → `level.unload`（:226-238）
/// - `drop`（ForgetLevelChunk 路径，:58-66）
/// - `updateViewCenter/updateViewRadius`（:124-149；缩窗重建环并迁移存活列）
/// - 未加载列查询 = `EmptyLevelChunk` 空气语义（:40,68-77；本侧返回 null，
///   空气语义由碰撞层承载——`SessionCollisionWorld` 未加载列不阻挡）
class ClientChunkCache {
  ClientChunkCache({
    required int serverChunkRadius,
    required void Function(RemoteChunkColumn chunk) onUnload,
    required void Function(int x, int z) onChunkLoaded,
  })  : _onUnload = onUnload, // ignore: prefer_initializing_formals
        _onChunkLoaded = onChunkLoaded, // ignore: prefer_initializing_formals
        _storage = _Storage(_calculateStorageRange(serverChunkRadius));

  final void Function(RemoteChunkColumn chunk) _onUnload;
  final void Function(int x, int z) _onChunkLoaded;
  _Storage _storage;

  /// 服务器窗口几何更新（`SetChunkCacheCenter`；判据 :124-127）。
  void updateViewCenter(int x, int z) {
    _storage.viewCenterX = x;
    _storage.viewCenterZ = z;
  }

  /// 服务器视距更新（`SetChunkCacheRadius`；判据 :129-149）。
  ///
  /// 半径变化时重建存储环，仍在新窗口内的列迁移，窗口外的列**卸载**。
  /// **偏差（债）**：原版迁移时对窗口外的列静默丢弃（不回调 unload）；
  /// 我们 MUST 发卸载事件——渲染端的事件契约要求"卸载必达"，否则网格
  /// 滞留（spec：缩窗迁移存活列）。服务器随后仍会补发 ForgetLevelChunk，
  /// `drop` 对已不存在的列是无害空操作。
  void updateViewRadius(int viewRange) {
    final newChunkRadius = _calculateStorageRange(viewRange);
    if (_storage.chunkRadius == newChunkRadius) return;

    final newStorage = _Storage(newChunkRadius)
      ..viewCenterX = _storage.viewCenterX
      ..viewCenterZ = _storage.viewCenterZ;

    for (var i = 0; i < _storage.chunks.length; i++) {
      final chunk = _storage.chunks[i];
      if (chunk == null) continue;
      if (newStorage.inRange(chunk.x, chunk.z)) {
        newStorage.replace(newStorage.getIndex(chunk.x, chunk.z), chunk, _onUnload);
      } else {
        _onUnload(chunk); // 缩窗卸载（见上方偏差注释）
      }
    }

    _storage = newStorage;
  }

  /// 服务器下发一个列（`replaceWithPacketData`，判据 :97-119）。
  ///
  /// 越界拒收返回 null；接受则顶替/原位更新并回调 [onChunkLoaded]
  /// （原版 `level.onChunkLoaded` 的 tint/entity 面本侧不建模，仅事件透传）。
  RemoteChunkColumn? replaceWithPacketData(RemoteChunkColumn chunk) {
    if (!_storage.inRange(chunk.x, chunk.z)) {
      // 判据 :100-103：原版 LOGGER.warn 同文。
      // ignore: avoid_print
      print("[CHUNK-CACHE] Ignoring chunk since it's not in the view range: "
          '${chunk.x}, ${chunk.z}');
      return null;
    }

    final index = _storage.getIndex(chunk.x, chunk.z);
    final existing = _storage.chunks[index];
    if (!_isValidChunk(existing, chunk.x, chunk.z)) {
      _storage.replace(index, chunk, _onUnload);
    } else {
      // 原位换数据（:112-115）：同坐标重发不触发卸载——与原版
      // `chunk.replaceWithPacketData(...)` + `refreshEmptySections` 的
      // "对象身份不变、无 unload"语义对齐。
      _storage.chunks[index] = chunk;
    }

    _onChunkLoaded(chunk.x, chunk.z);
    return chunk;
  }

  /// ForgetLevelChunk 路径（判据 :58-66；`ClientPacketListener.java:898-901`）。
  ///
  /// 原版语义：不在窗口内 / 该索引不是这个坐标 = 无害空操作。
  void drop(int x, int z) {
    if (!_storage.inRange(x, z)) return;
    final index = _storage.getIndex(x, z);
    final existing = _storage.chunks[index];
    if (existing != null && _isValidChunk(existing, x, z)) {
      _storage.drop(index, existing, _onUnload);
    }
  }

  /// 查询列（判据 :68-77）。不在环内返回 null（空气语义由碰撞层承载）。
  RemoteChunkColumn? getChunk(int x, int z) {
    if (_storage.inRange(x, z)) {
      final chunk = _storage.chunks[_storage.getIndex(x, z)];
      if (_isValidChunk(chunk, x, z)) return chunk;
    }
    return null;
  }

  /// 已持有列数（`getLoadedChunksCount`，:159-161）。
  int get loadedChunkCount => _storage.chunkCount;

  /// 存储环容量（`gatherStats` 口径，:155-157；测试/诊断用）。
  int get capacity => _storage.chunks.length;

  /// 存储半径（测试/诊断用）。
  int get storageRadius => _storage.chunkRadius;

  /// 窗口中心（测试/诊断用）。
  (int, int) get viewCenter => (_storage.viewCenterX, _storage.viewCenterZ);

  static int _calculateStorageRange(int viewRange) =>
      (viewRange > 2 ? viewRange : 2) + 3; // :151-153

  static bool _isValidChunk(RemoteChunkColumn? chunk, int x, int z) {
    if (chunk == null) return false;
    return chunk.x == x && chunk.z == z; // :49-56
  }
}

/// `ClientChunkCache.Storage` 内部类（:195-323）。
class _Storage {
  _Storage(this.chunkRadius)
      : viewRange = chunkRadius * 2 + 1,
        chunks =
            List<RemoteChunkColumn?>.filled((chunkRadius * 2 + 1) * (chunkRadius * 2 + 1), null);

  final int chunkRadius;

  /// 环边长（`viewRange = chunkRadius*2+1`，:211）。
  final int viewRange;

  final List<RemoteChunkColumn?> chunks;

  int viewCenterX = 0;
  int viewCenterZ = 0;
  int chunkCount = 0;

  /// `Math.floorMod` → Dart 的 `%` 对负 int 同样给出非负结果，语义一致（:222-224）。
  int getIndex(int chunkX, int chunkZ) =>
      (chunkZ % viewRange) * viewRange + (chunkX % viewRange);

  /// 切比雪夫距离窗口（:298-300）。
  bool inRange(int chunkX, int chunkZ) =>
      (chunkX - viewCenterX).abs() <= chunkRadius &&
      (chunkZ - viewCenterZ).abs() <= chunkRadius;

  /// 顶替写入：被顶掉的旧列触发卸载（:226-238 的 `level.unload`）。
  void replace(int index, RemoteChunkColumn newChunk, void Function(RemoteChunkColumn) onUnload) {
    final removed = chunks[index];
    chunks[index] = newChunk;
    if (removed != null) {
      chunkCount--;
      onUnload(removed);
    }
    chunkCount++;
  }

  /// 卸载（:240-247）。
  void drop(int index, RemoteChunkColumn oldChunk, void Function(RemoteChunkColumn) onUnload) {
    if (identical(chunks[index], oldChunk)) {
      chunks[index] = null;
      chunkCount--;
      onUnload(oldChunk);
    }
  }
}
