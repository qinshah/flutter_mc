/// BlockPos / ChunkPos 的线上打包形态（判据：`FriendlyByteBuf.readBlockPos` →
/// `BlockPos.asLong`；`readChunkPos` → `ChunkPos.unpack`）。
///
/// 位布局（判据：BlockPos.getX/getY/getZ：Y bit 0..11、Z bit 12..37、
/// X bit 38..63，各段算术移位符号扩展）：
/// - BlockPos：y 12 位（bit 0..11）、z 26 位（bit 12..37）、x 26 位（bit 38..63）；
/// - ChunkPos：x 高 32 位、z 低 32 位。
library;

import 'dart:typed_data';

final class McBlockPos {
  const McBlockPos(this.x, this.y, this.z);

  final int x;
  final int y;
  final int z;

  static McBlockPos unpackLong(int l) {
    // 有符号段提取：对 o 位偏移、k 位宽的段，(l << (64-o-k)) >> (64-k) 算术移位符号扩展。
    final x = l >> 38; // 26 位，bit 38..63
    final y = (l << 52) >> 52; // 12 位，bit 0..11
    final z = (l << 26) >> 38; // 26 位，bit 12..37
    return McBlockPos(x, y, z);
  }

  int packLong() {
    final y12 = y & 0xFFF; // bit 0..11
    final z26 = (z & 0x3FFFFFF) << 12; // bit 12..37
    final x26 = (x & 0x3FFFFFF) << 38; // bit 38..63
    return x26 | z26 | y12;
  }

  @override
  String toString() => 'McBlockPos($x, $y, $z)';
}

final class McChunkPos {
  const McChunkPos(this.x, this.z);

  final int x;
  final int z;

  static McChunkPos unpackLong(int l) => McChunkPos(l >> 32, l.toSigned(32));

  int packLong() => (x << 32) | (z & 0xFFFFFFFF);

  @override
  String toString() => 'McChunkPos($x, $z)';
}

/// Uint8List 快照工具（从 Reader 切出的视图可能是大缓冲的子段，登记前固化）。
Uint8List snapshot(List<int> bytes) => Uint8List.fromList(bytes);
