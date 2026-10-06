import 'dart:typed_data';

import 'package:mc_wire/mc_wire.dart';
import 'package:mc_protocol_v26_2/mc_protocol_v26_2.dart';

import 'palette.dart';

/// 一列 chunk 的**服务器权威世界状态**（传输无关；渲染侧由应用适配层转换为
/// 它自己的 ChunkColumn——mc_session 不依赖任何渲染类型）。
///
/// 状态号是**服务器（26.2）registry 的状态号空间**；身份解释在应用适配层。
final class RemoteChunkColumn {
  RemoteChunkColumn({
    required this.x,
    required this.z,
    required this.sections,
    required this.skyLight,
    required this.blockLight,
    required this.heightmapTypes,
    required this.heightmapData,
    this.minSectionY = kOverworldMinSectionY,
  });

  /// overworld 的最低段号：世界底 y = −64（26.x 世界高 384 = −64..320）。
  static const int kOverworldMinSectionY = -4;

  /// 本列最低段的段号（`sectionY`）。**段号是世界坐标 y 的函数**：
  /// `sectionY = (worldY >> 4)`，而世界底不一定是 0——overworld 从 −64 起。
  ///
  /// 这是 4.1 端到端实测挖出来的坑：漏了它会让段索引整体偏 64 格，
  /// 客户端"站在幻影地面上"，与服务器权威位置持续背离（服务器狂刷
  /// `moved too quickly`）。非 overworld 维度（下界/末地 minY=0）需要按
  /// 维度类型传值，本切片只支持 overworld。
  final int minSectionY;

  /// 本列最低段的方块 y（世界坐标）。
  int get minY => minSectionY * 16;

  final int x;
  final int z;

  /// 自底向上的 section 状态数组，每段 4096 个状态号（index = (y*16+z)*16+x）。
  final List<Uint16List> sections;

  /// 光照段数据：key = 光照段索引（chunk 段索引偏移 -1，即含上下两个邻接段），
  /// value = 2048 字节（每字节两半字节：低 4 位 = (y<<8 | lz<<4 | lx) 的低 nibble？——
  /// 布局与原版 DataLayer 一致：index = y*256 + lz*16 + lx，低 nibble 在偶数 index）。
  /// 直接原样保存服务器字节，语义由适配层解释。
  final Map<int, Uint8List> skyLight;
  final Map<int, Uint8List> blockLight;

  final List<int> heightmapTypes;
  final List<Uint8List> heightmapData;

  /// 取方块状态（世界坐标；chunk 内局部坐标）。
  ///
  /// `worldY` 是**世界坐标**（可为负：overworld 从 −64 起），段索引要减
  /// [minSectionY]；段内局部 y 用 `& 15`（对负数同样成立）。
  int stateAt(int localX, int worldY, int localZ) {
    final sectionIdx = (worldY >> 4) - minSectionY;
    if (sectionIdx < 0 || sectionIdx >= sections.length) return 0;
    final localY = worldY & 15;
    return sections[sectionIdx][(localY << 8) | (localZ << 4) | localX];
  }

  /// 应用一次方块更新（服务器权威回显）；返回是否真的变化。
  bool applyBlockUpdate(McBlockPos pos, int stateId) {
    // 世界坐标 → 本列局部
    final localX = pos.x & 15;
    final localZ = pos.z & 15;
    return _setLocal(localX, pos.y, localZ, stateId);
  }

  /// 应用段内批量更新（packed：低 12 位段内局部，高位状态号）。
  bool applySectionChanges(int sectionX, int sectionY, int sectionZ, List<int> packed) {
    if (sectionX != x || sectionZ != z) return false;
    var changed = false;
    for (final p in packed) {
      final local = p & 0xFFF;
      final stateId = p >>> 12;
      final lx = (local >> 8) & 15;
      final ly = (local >> 4) & 15;
      final lz = local & 15;
      changed |= _setLocal(lx, (sectionY << 4) | ly, lz, stateId);
    }
    return changed;
  }

  bool _setLocal(int lx, int worldY, int lz, int stateId) {
    final sectionIdx = (worldY >> 4) - minSectionY;
    if (sectionIdx < 0 || sectionIdx >= sections.length) return false;
    final idx = ((worldY & 15) << 8) | (lz << 4) | lx;
    if (sections[sectionIdx][idx] == stateId) return false;
    sections[sectionIdx][idx] = stateId;
    return true;
  }
}

/// chunk 包 → [RemoteChunkColumn] 的解调色板摄入（design D2；tasks 5.3）。
final class ChunkIngestor {
  ChunkIngestor({
    this.sectionCount = 24, // 26.x 默认世界高 384（-64..320）
    this.minSectionY = RemoteChunkColumn.kOverworldMinSectionY,
  });

  final int sectionCount;

  /// 本维度最低段号（overworld −4）；见 [RemoteChunkColumn.minSectionY]。
  final int minSectionY;

  RemoteChunkColumn ingest(LevelChunkWithLight packet) {
    final blockDecoder = PalettedContainerDecoder(entryCount: 4096, maxIndirectBits: 8);
    final biomeDecoder = PalettedContainerDecoder(entryCount: 64, maxIndirectBits: 3);

    final r = ByteReader(packet.sectionsBuffer);
    final sections = <Uint16List>[];
    var sectionIdx = 0;
    while (r.hasRemaining) {
      if (sectionIdx >= sectionCount) {
        throw FormatException('chunk ${packet.x}/${packet.z} 的 section 数超出 $sectionCount');
      }
      // 段头部：short nonEmptyBlockCount + short fluidCount（判据：
      // LevelChunkSection.write —— 2026-10-01 真机验收补上，漏读会整体错位）
      r.readShort();
      r.readShort();
      final states = blockDecoder.decode(r);
      biomeDecoder.decode(r); // 生物群系：当前不消费，仅推进游标
      sections.add(states);
      sectionIdx++;
    }

    // 光照：bitset 索引 i 对应光照段（chunk 段索引 - 1，即含上下邻接段）
    final sky = _lightMap(packet.skyYMask, packet.skyUpdates);
    final block = _lightMap(packet.blockYMask, packet.blockUpdates);

    return RemoteChunkColumn(
      x: packet.x,
      z: packet.z,
      minSectionY: minSectionY,
      sections: sections,
      skyLight: sky,
      blockLight: block,
      heightmapTypes: packet.heightmapTypes,
      heightmapData: packet.heightmapData,
    );
  }

  Map<int, Uint8List> _lightMap(List<int> mask, List<Uint8List> arrays) {
    final out = <int, Uint8List>{};
    var arrayIdx = 0;
    for (var i = 0; i < mask.length * 64; i++) {
      final set = (mask[i >> 6] >> (i & 63)) & 1 == 1;
      if (set) {
        if (arrayIdx >= arrays.length) break;
        out[i] = arrays[arrayIdx++];
      }
    }
    return out;
  }

}
