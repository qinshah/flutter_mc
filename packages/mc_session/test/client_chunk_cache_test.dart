import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:mc_session/mc_session.dart';

RemoteChunkColumn _column(int x, int z) => RemoteChunkColumn(
      x: x,
      z: z,
      sections: List.generate(24, (_) => Uint16List(4096)),
      skyLight: {},
      blockLight: {},
      heightmapTypes: [],
      heightmapData: [],
    );

void main() {
  group('ClientChunkCache（判据 ClientChunkCache.java）', () {
    test('容量换算黄金值：viewRadius=10 → chunkRadius=13 → 729（J1-J2）', () {
      final cache = ClientChunkCache(
        serverChunkRadius: 10,
        onUnload: (_) {},
        onChunkLoaded: (_, _) {},
      );
      expect(cache.storageRadius, 13); // max(2,10)+3 = 13（:151-153）
      expect(cache.capacity, 27 * 27); // (2*13+1)² = 729（:209-212）

      // 下限：viewRadius=0 → max(2,0)+3 = 5（:151-153）
      final tiny = ClientChunkCache(
        serverChunkRadius: 0,
        onUnload: (_) {},
        onChunkLoaded: (_, _) {},
      );
      expect(tiny.storageRadius, 5);
    });

    test('inRange 切比雪夫边界：等号在窗内、超 1 拒收（J4、J8）', () {
      final loaded = <(int, int), int>{};
      final cache = ClientChunkCache(
        serverChunkRadius: 10, // 存储半径 = max(2,10)+3 = 13
        onUnload: (c) => loaded.remove((c.x, c.z)),
        onChunkLoaded: (x, z) => loaded[(x, z)] = (loaded[(x, z)] ?? 0) + 1,
      );

      // 存储半径 13 的切比雪夫边界：|x-center| == 13 在窗内
      expect(cache.replaceWithPacketData(_column(13, 0)), isNotNull);
      expect(cache.replaceWithPacketData(_column(-13, -13)), isNotNull);
      expect(loaded.length, 2);

      // 超 1：拒收（返回 null、无加载事件）
      expect(cache.replaceWithPacketData(_column(14, 0)), isNull);
      expect(loaded.length, 2);
      expect(cache.loadedChunkCount, 2);
    });

    test('顶替即卸载：中心移动后同索引写入挤掉旧列（J3、J5、J7）', () {
      final unloaded = <RemoteChunkColumn>[];
      final cache = ClientChunkCache(
        serverChunkRadius: 2, // chunkRadius=5, viewRange=11
        onUnload: unloaded.add,
        onChunkLoaded: (_, _) {},
      );

      final a = _column(0, 0);
      expect(cache.replaceWithPacketData(a), isNotNull);
      expect(cache.loadedChunkCount, 1);

      // 窗口中心移到 (11,0)：(11,0) 入窗，getIndex(11,0) = floorMod(0,11)*11 +
      // floorMod(11,11) = 0 —— 与 (0,0) 同槽（环索引随中心移动发生碰撞）。
      // 注意：inRange 窗内坐标的索引天然唯一，顶替只发生在中心移动之后。
      cache.updateViewCenter(11, 0);
      final b = _column(11, 0);
      expect(cache.replaceWithPacketData(b), isNotNull);
      expect(unloaded, [a]); // 旧列被顶替即卸载
      expect(cache.loadedChunkCount, 1);
      expect(cache.getChunk(11, 0), same(b));
    });

    test('同坐标重发：原位换数据，不触发卸载（:112-115）', () {
      final unloaded = <RemoteChunkColumn>[];
      final cache = ClientChunkCache(
        serverChunkRadius: 2,
        onUnload: unloaded.add,
        onChunkLoaded: (_, _) {},
      );

      final v1 = _column(3, 4);
      final v2 = _column(3, 4);
      cache.replaceWithPacketData(v1);
      cache.replaceWithPacketData(v2);
      expect(unloaded, isEmpty); // 原位更新无卸载
      expect(cache.loadedChunkCount, 1);
      expect(cache.getChunk(3, 4), same(v2));
    });

    test('drop：ForgetLevelChunk 卸载既有列；未持有列无害空操作（J6）', () {
      final unloaded = <RemoteChunkColumn>[];
      final cache = ClientChunkCache(
        serverChunkRadius: 2,
        onUnload: unloaded.add,
        onChunkLoaded: (_, _) {},
      );

      final a = _column(1, 2);
      cache.replaceWithPacketData(a);
      cache.drop(1, 2);
      expect(unloaded, [a]);
      expect(cache.loadedChunkCount, 0);

      // 不在环内 / 未持有：无回调、无异常
      cache.drop(1, 2);
      cache.drop(9999, 9999);
      expect(unloaded.length, 1);
    });

    test('updateViewCenter 后越界写入被拒（J7、J4）', () {
      final cache = ClientChunkCache(
        serverChunkRadius: 2,
        onUnload: (_) {},
        onChunkLoaded: (_, _) {},
      );
      cache.updateViewCenter(10, 10);

      // chunkRadius=5：(15,10) 恰在边界内
      expect(cache.replaceWithPacketData(_column(15, 10)), isNotNull);
      // (16,10) 超出 → 拒收
      expect(cache.replaceWithPacketData(_column(16, 10)), isNull);
    });

    test('缩窗迁移存活列、卸载窗外列（J7）', () {
      final unloaded = <RemoteChunkColumn>[];
      final cache = ClientChunkCache(
        serverChunkRadius: 10,
        onUnload: unloaded.add,
        onChunkLoaded: (_, _) {},
      );

      final near = _column(0, 0);
      final far = _column(9, 0);
      cache.replaceWithPacketData(near);
      cache.replaceWithPacketData(far);
      expect(cache.loadedChunkCount, 2);

      cache.updateViewRadius(2); // chunkRadius 13 → 5
      expect(cache.storageRadius, 5);
      expect(unloaded, [far]); // 窗外列被卸载（偏差见类注释：原版静默丢弃）
      expect(cache.loadedChunkCount, 1);
      expect(cache.getChunk(0, 0), same(near)); // 存活列已迁移
      expect(cache.getChunk(9, 0), isNull);
    });
  });
}
