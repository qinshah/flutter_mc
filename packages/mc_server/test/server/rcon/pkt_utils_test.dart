// 判据：PktUtils.java:6/:7/:9/:20/:24/:28/:32（相对 mc-sources/minecraft-26.2/net/minecraft/）。
import 'dart:typed_data';

import 'package:mc_server/mc_server.dart';
import 'package:test/test.dart';

void main() {
  group('PktUtils.intFromByteArray（小端，最高字节带符号）', () {
    test('读回 4 字节小端整数', () {
      // 0x01020304 的小端字节序
      final b = Uint8List.fromList([0x04, 0x03, 0x02, 0x01]);
      expect(PktUtils.intFromByteArray(b, 0, 4), 0x01020304);
    });

    test('最高字节带符号（Java byte 语义）', () {
      final b = Uint8List.fromList([0x00, 0x00, 0x00, 0xFF]);
      expect(PktUtils.intFromByteArray(b, 0, 4), -16777216);
    });

    test('offset 越过可读范围返回 0（PktUtils.java:25 的空值分支）', () {
      final b = Uint8List.fromList([1, 2, 3]);
      expect(PktUtils.intFromByteArray(b, 0, 3), 0);
    });
  });

  test('PktUtils.intFromNetworkByteArray（大端）', () {
    final b = Uint8List.fromList([0x01, 0x02, 0x03, 0x04]);
    expect(PktUtils.intFromNetworkByteArray(b, 0, 4), 0x01020304);
  });

  group('PktUtils.stringFromByteArray（以 0 终止，UTF-8）', () {
    test('在首个 0 处截断', () {
      final b = Uint8List.fromList([0x68, 0x69, 0x00, 0x78]);
      expect(PktUtils.stringFromByteArray(b, 0, 4), 'hi');
    });

    test('无 0 则扫描上界为 length-1（不含）', () {
      // max = length-1 = 2，循环在 i==max 时停止，故取 [0,2) = "hi"（PktUtils.java:13-16）。
      final b = Uint8List.fromList([0x68, 0x69, 0x78, 0x00]);
      expect(PktUtils.stringFromByteArray(b, 0, 3), 'hi');
    });
  });

  test('PktUtils.toHexString（PktUtils.java:32）', () {
    expect(PktUtils.toHexString(0x00), '00');
    expect(PktUtils.toHexString(0x0f), '0f');
    expect(PktUtils.toHexString(0xf0), 'f0');
    // Java 的 byte 为有符号：0xFF 作为 byte 是 -1，(b & 240)>>>4 = 15，b & 15 = 15 -> "ff"
    expect(PktUtils.toHexString(0xff), 'ff');
  });
}
