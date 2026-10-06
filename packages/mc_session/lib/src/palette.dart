import 'dart:typed_data';

import 'package:mc_wire/mc_wire.dart';

/// 26.x 线上调色板容器解码（判据 = minecraft-common-26.3-sources
/// `PalettedContainer.Data.write/read` + `Strategy.java` + `*Palette.java`；
/// 26.2 侧判据 = `FriendlyByteBuf.writeFixedSizeLongArray`，与 26.3 common 一致）。
///
/// 线上形态：
/// 1. `byte bits`（声明的存储位宽）；
/// 2. 调色板：bits==0 → 单值（varint 全局 id）；bits 1..8（方块）/1..3（生物群系）→
///    `varint size + size 个 varint 全局 id`；更大 → 全局调色板（无线上调色板数据，
///    存储位宽 = ceillog2(注册表大小)，由会话侧从 registry 数据推得）；
/// 3. **定长** long 数组（无长度前缀！长度由 bits 与条目数推出）。
///
/// 位打包（`SimpleBitStorage`）：每 long 低位在前、**不跨 long**；
/// `entriesPerLong = 64 ~/ bits`，longCount = ceil(entryCount / entriesPerLong)。
final class PalettedContainerDecoder {
  PalettedContainerDecoder({
    required this.entryCount,
    required this.maxIndirectBits,
  });

  /// 4096（方块）/ 64（生物群系）。
  final int entryCount;

  /// 间接调色板的最大声明位宽（方块 8 / 生物群系 3）；超过即全局调色板。
  final int maxIndirectBits;

  /// 从 [buffer] 当前位置读一个容器，返回 [entryCount] 个全局 id（按
  /// `index = (y * axisSize + z) * axisSize + x` 顺序；维度语义由调用方解释）。
  ///
  /// **声明字节就是存储位宽**（判据：`PalettedContainer.Data.write` 的
  /// `writeByte(storage.getBits())` 与 `read` 的 `createOrReuseData(bits)`——
  /// 全局段的 `Configuration.Global` 的 bitsInMemory 与声明值一致，
  /// 无需客户端另知注册表大小；2026-10-01 真机验收订正）。
  Uint16List decode(ByteReader r) {
    final declaredBits = r.readUnsignedByte();
    final storageBits = declaredBits;

    // 调色板
    var palette = Uint16List(0); // 空 = 全局直读
    var singleValue = -1;
    if (declaredBits == 0) {
      singleValue = r.readVarInt();
    } else if (declaredBits <= maxIndirectBits) {
      final size = r.readVarInt();
      palette = Uint16List(size);
      for (var i = 0; i < size; i++) {
        palette[i] = r.readVarInt();
      }
    }

    // 定长 long 数组
    final longCount = _longCount(storageBits);
    final longs = Uint64List(longCount);
    for (var i = 0; i < longCount; i++) {
      longs[i] = r.readLong();
    }

    final out = Uint16List(entryCount);
    if (declaredBits == 0) {
      if (singleValue < 0) throw const FormatException('单值调色板缺值');
      for (var i = 0; i < entryCount; i++) {
        out[i] = singleValue;
      }
      return out;
    }

    final entriesPerLong = 64 ~/ storageBits;
    final mask = (1 << storageBits) - 1;
    for (var i = 0; i < entryCount; i++) {
      final longIdx = i ~/ entriesPerLong;
      final offset = (i % entriesPerLong) * storageBits;
      final raw = (longs[longIdx] >> offset) & mask;
      out[i] = palette.isEmpty ? raw : palette[raw];
    }
    return out;
  }

  int _longCount(int bits) {
    if (bits == 0) return 0;
    final entriesPerLong = 64 ~/ bits;
    return (entryCount + entriesPerLong - 1) ~/ entriesPerLong;
  }
}
