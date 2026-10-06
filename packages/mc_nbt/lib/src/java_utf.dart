import 'dart:typed_data';

import 'nbt_tag.dart';

/// Java **modified UTF-8**（`DataOutputStream#writeUTF` / `DataInputStream#readUTF`）。
///
/// NBT 的字符串**不是**标准 UTF-8：它带 2 字节大端长度前缀，且编码规则是 Java
/// 自己的一套（design.md §4.5 的第 2 条陷阱）。差别只有两处，但两处都会让原版读串：
///
/// | 字符 | 标准 UTF-8 | Java modified UTF-8 |
/// |---|---|---|
/// | `U+0000` | `00` | `C0 80`（**两字节**，标准编码器会拒绝这种 overlong 形式） |
/// | `U+10000` 以上 | 4 字节（按码点） | **6 字节**（先拆成 UTF-16 代理对，各自 3 字节） |
///
/// 长度前缀是**编码后的字节数**，因此"中文字符串的字节数"绝不能拿
/// `utf8.encode(...).length` 去算。上限 65535 字节，超了原版写不出来（会抛
/// `UTFDataFormatException`），我们也抛。
///
/// BMP 内的字符（含全部常用汉字）两种编码的字节恰好相同 —— 所以
/// "用真实存档跑一遍没问题" **不足以证明**这个实现是对的，
/// `test/world/nbt/java_utf_test.dart` 里用的是带 `U+0000` 与 emoji 的向量。
abstract final class JavaUtf {
  /// `writeUTF` 的长度前缀是 `unsigned short`，故 65535 字节是硬上限。
  static const int maxBytes = 65535;

  /// 编码为 `[2 字节大端长度][modified UTF-8 负载]`。
  static Uint8List encode(String value) {
    // Dart 的 String 就是 UTF-16 码元序列，与 Java String 语义一致：
    // 代理对（非 BMP 字符）在这里天然是**两个**码元，会被各自编成 3 字节，正合 Java 规则。
    final units = value.codeUnits;
    final out = Uint8List(2 + units.length * 3); // 上界：每码元最多 3 字节
    var n = 2; // 前 2 字节留给长度前缀，负载从偏移 2 开始
    for (final unit in units) {
      if (unit >= 0x0001 && unit <= 0x007f) {
        out[n++] = unit;
      } else if (unit <= 0x07ff) {
        // 含 U+0000：Java 把它编成 C0 80，而不是单个 00。
        out[n++] = 0xc0 | (unit >> 6);
        out[n++] = 0x80 | (unit & 0x3f);
      } else {
        out[n++] = 0xe0 | (unit >> 12);
        out[n++] = 0x80 | ((unit >> 6) & 0x3f);
        out[n++] = 0x80 | (unit & 0x3f);
      }
    }
    final length = n - 2;
    if (length > maxBytes) {
      throw NbtFormatException(
        'Java modified UTF-8 字符串超过 $maxBytes 字节（实际 $length）：'
        '原版 DataOutputStream#writeUTF 同样会抛 UTFDataFormatException',
      );
    }
    out[0] = (length >> 8) & 0xff;
    out[1] = length & 0xff;
    return Uint8List.sublistView(out, 0, n);
  }

  /// 从 [bytes] 的 [offset] 处解出一个字符串。
  ///
  /// 返回 `(value, nextOffset)` —— 保持纯函数，不持有游标状态，
  /// 便于 NBT 读取器与测试共用（读取器自己管游标）。
  static ({String value, int nextOffset}) decodeFrom(
    Uint8List bytes,
    int offset,
  ) {
    if (offset < 0 || offset + 2 > bytes.length) {
      throw NbtFormatException('字符串长度前缀被截断', offset: offset);
    }
    final length = (bytes[offset] << 8) | bytes[offset + 1];
    final start = offset + 2;
    final end = start + length;
    if (end > bytes.length) {
      throw NbtFormatException(
        '字符串负载被截断：声明 $length 字节，实际只剩 ${bytes.length - start} 字节',
        offset: offset,
      );
    }

    // 先收集 UTF-16 码元，最后一次性成串 —— 与 Java `readUTF` 的流程一致。
    final units = <int>[];
    var i = start;
    while (i < end) {
      final first = bytes[i];
      if (first < 0x80) {
        // Java 的 readUTF 对裸 00 是**宽容**的（它只按首字节分支解码，不做 overlong 检查）。
        // 我们跟着宽容：写出去时永远是 C0 80，但读到裸 00 不报错。
        units.add(first);
        i++;
      } else if ((first & 0xe0) == 0xc0) {
        if (i + 1 >= end) {
          throw NbtFormatException(
            'modified UTF-8 两字节序列被截断',
            offset: i,
          );
        }
        final second = bytes[i + 1];
        if ((second & 0xc0) != 0x80) {
          throw NbtFormatException(
            'modified UTF-8 续字节非法：0x${second.toRadixString(16)}',
            offset: i + 1,
          );
        }
        units.add(((first & 0x1f) << 6) | (second & 0x3f));
        i += 2;
      } else if ((first & 0xf0) == 0xe0) {
        if (i + 2 >= end) {
          throw NbtFormatException(
            'modified UTF-8 三字节序列被截断',
            offset: i,
          );
        }
        final second = bytes[i + 1];
        final third = bytes[i + 2];
        if ((second & 0xc0) != 0x80 || (third & 0xc0) != 0x80) {
          throw NbtFormatException('modified UTF-8 续字节非法', offset: i + 1);
        }
        units.add(((first & 0x0f) << 12) |
            ((second & 0x3f) << 6) |
            (third & 0x3f));
        i += 3;
      } else {
        throw NbtFormatException(
          'modified UTF-8 首字节非法：0x${first.toRadixString(16)}',
          offset: i,
        );
      }
    }
    return (value: String.fromCharCodes(units), nextOffset: end);
  }

  /// 解码一个**独占整个缓冲区**的字符串（缓冲区必须恰好只有一个字符串）。
  static String decode(Uint8List bytes) {
    final result = decodeFrom(bytes, 0);
    if (result.nextOffset != bytes.length) {
      throw NbtFormatException(
        '字符串之后还有 ${bytes.length - result.nextOffset} 字节多余数据',
        offset: result.nextOffset,
      );
    }
    return result.value;
  }
}
