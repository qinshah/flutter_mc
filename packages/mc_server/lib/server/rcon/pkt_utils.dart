// 逐行翻译 net/minecraft/server/rcon/PktUtils.java。
//
// 判据（路径均相对 mc-sources/minecraft-26.2/net/minecraft/）：
//   PktUtils.java:6   —— MAX_PACKET_SIZE = 1460
//   PktUtils.java:7   —— HEX_CHAR 表
//   PktUtils.java:9   —— stringFromByteArray（以 0 终止，UTF-8 解码）
//   PktUtils.java:20  —— intFromByteArray 重载（缺省 length = 数组长度）
//   PktUtils.java:24  —— intFromByteArray（小端，最高字节带符号）
//   PktUtils.java:28  —— intFromNetworkByteArray（大端）
//   PktUtils.java:32  —— toHexString
import 'dart:convert';
import 'dart:typed_data';

class PktUtils {
  /// PktUtils.java:6
  static const int MAX_PACKET_SIZE = 1460;

  /// PktUtils.java:7（原版为 char[16]）
  static const String HEX_CHAR = '0123456789abcdef';

  /// PktUtils.java:9-18：从 [offset] 起扫描至第一个 0 或 [length]-1，按 UTF-8 解码。
  ///
  /// 原版循环条件为 `0 != b[i] && i < max`（先读 b[i] 再判 i<max）；此处等价改写为
  /// `i < max && b[i] != 0`，仅省去越界读，判定结果相同。
  /// JDK 的 `new String(byte[],int,int,UTF_8)` 遇畸形字节以替换字符处理，
  /// 故用 `allowMalformed: true` 对齐（不抛异常）。
  static String stringFromByteArray(Uint8List b, int offset, int length) {
    final max = length - 1;
    var i = offset > max ? max : offset;
    while (i < max && b[i] != 0) {
      i++;
    }
    return utf8.decode(b.sublist(offset, i), allowMalformed: true);
  }

  /// PktUtils.java:20-22
  static int intFromByteArray(Uint8List b, int offset, [int? length]) =>
      intFromByteArrayImpl(b, offset, length ?? b.length);

  /// PktUtils.java:24-26：小端，最高字节（offset+3）按 Java byte 的符号扩展。
  static int intFromByteArrayImpl(Uint8List b, int offset, int length) {
    if (0 > length - offset - 4) return 0;
    return (_signed(b[offset + 3]) << 24) |
        ((b[offset + 2] & 0xFF) << 16) |
        ((b[offset + 1] & 0xFF) << 8) |
        (b[offset] & 0xFF);
  }

  /// PktUtils.java:28-30：大端，最高字节（offset）带符号。
  static int intFromNetworkByteArray(Uint8List b, int offset, int length) {
    if (0 > length - offset - 4) return 0;
    return (_signed(b[offset]) << 24) |
        ((b[offset + 1] & 0xFF) << 16) |
        ((b[offset + 2] & 0xFF) << 8) |
        (b[offset + 3] & 0xFF);
  }

  /// PktUtils.java:32-34：把 1 字节转成 2 位十六进制字符串。
  static String toHexString(int b) =>
      HEX_CHAR[(b & 0xF0) >> 4] + HEX_CHAR[b & 0x0F];

  /// Java 的 `byte` 是有符号的（Dart 的 Uint8List 元素为 0..255），按需还原符号。
  static int _signed(int v) => v >= 128 ? v - 256 : v;
}
