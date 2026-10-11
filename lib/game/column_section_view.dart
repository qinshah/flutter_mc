import 'package:mc_render/mc_render.dart';
import 'package:mc_session/mc_session.dart';

/// 「服务器列 + 段层号」→ 网格器要的 16³ 段视图。
///
/// 原版对应物：`net.minecraft.client.renderer.chunk.RenderSectionRegion`
/// （区块编译期按段切片读世界的那层视图，`getBlockState(BlockPos)`；判据
/// `mc-sources/minecraft-26.2`）。移植自 fscraft `ColumnSectionView`。
///
/// **为什么在 app 壳而不是 mc_render**：mc_render 不得 import mc_session（红线），
/// 只认自己的 `SectionView` 接口；把 mc_session 的列数据适配成段视图是应用适配层
/// 的活。同理，`_neighborsOf` 也只在本层做。
///
/// **段号口径 = 绝对段号**（对齐原版 `SectionPos` 的世界 Y/16，含负数）：
/// `RemoteChunkColumn.sections` 的数组下标是列内相对段号（0 = `minSectionY`
/// 段），换算只发生在本类内部——`stateAt` 一直按绝对段号算 `_baseY`（负段号
/// × 16 = 负世界 Y，语义正确），但 `isEmpty` 曾按"相对下标"直取
/// `sections[sectionY]`，与 `stateAt` 差了 `minSectionY`（overworld 4 段）：
/// 表现为"段内容是绝对段 s，空判却查绝对段 s−4"——悬空段（下方 4 段是空气）
/// 被误判空而跳过、绝对段 −4..−1（y<0 深板岩）从不渲染。2026-10-12 统一为
/// 绝对段号后此类错位不再可能发生。
class ColumnSectionView implements SectionView {
  ColumnSectionView(this.column, this.sectionY) : _baseY = sectionY * 16;

  final RemoteChunkColumn column;

  /// 绝对段号（世界 Y / 16，可为负；0 = y 0..15）。
  final int sectionY;

  final int _baseY;

  @override
  int stateAt(int lx, int ly, int lz) => column.stateAt(lx, _baseY + ly, lz);

  /// 该段是否全空。
  ///
  /// 简化点（标注）：mc_session 的 `RemoteChunkColumn` 没有原版
  /// `LevelChunkSection.hasOnlyAir` 的对应物——段头部读到的 `nonEmptyBlockCount`
  /// 在 `ChunkIngestor` 里被丢弃了，所以这里按"全 0 扫描"判定。
  /// 26.2 的内部 id 空间不变量：`0 = minecraft:air`（`state_identity_26_2` 第 0 项），
  /// 所以 `!= 0` 即非空气。一次网格化只问一次，4096 次读的代价可接受。
  @override
  bool get isEmpty {
    // 绝对段号 → 列内相对下标（`sections[0]` = `minSectionY` 段）。
    final idx = sectionY - column.minSectionY;
    if (idx < 0 || idx >= column.sections.length) return true;
    for (final state in column.sections[idx]) {
      if (state != 0) return false;
    }
    return true;
  }
}

/// 取 [column] 的 [sectionY] 段的六个相邻段（未加载 / 越界的邻居为 null，
/// 网格器按空气处理）。[sectionY] 为绝对段号（同 [ColumnSectionView]）。
///
/// 邻居是**段**而不是列：竖直方向取同列的上下段，水平方向取相邻列的**同层**段。
/// 这与原版 3×3×3 的 `RenderSectionRegion` 同构（区块编译只读得到的那一圈）。
SectionNeighbors neighborsOf(
  RemoteChunkColumn column,
  int sectionY,
  Map<(int, int), RemoteChunkColumn> loaded,
) {
  ColumnSectionView? at(RemoteChunkColumn? c, int sy) {
    // 绝对段号 → 相对下标越界判定（同 [ColumnSectionView.isEmpty]）。
    if (c == null ||
        sy < c.minSectionY ||
        sy >= c.minSectionY + c.sections.length) {
      return null;
    }
    return ColumnSectionView(c, sy);
  }

  return SectionNeighbors(
    negX: at(loaded[(column.x - 1, column.z)], sectionY),
    posX: at(loaded[(column.x + 1, column.z)], sectionY),
    negY: at(column, sectionY - 1),
    posY: at(column, sectionY + 1),
    negZ: at(loaded[(column.x, column.z - 1)], sectionY),
    posZ: at(loaded[(column.x, column.z + 1)], sectionY),
  );
}
