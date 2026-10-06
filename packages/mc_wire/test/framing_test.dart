import 'dart:typed_data';

import 'package:mc_wire/mc_wire.dart';
import 'package:test/test.dart';

void main() {
  group('分帧：粘包/半包/一包多帧', () {
    test('完整单帧', () {
      final d = FrameDecoder();
      final frames = d.push(encodeFrame([1, 2, 3]));
      expect(frames, hasLength(1));
      expect(frames[0], [1, 2, 3]);
    });

    test('粘包：一包两帧', () {
      final d = FrameDecoder();
      final wire = BytesBuilder()
        ..add(encodeFrame([1]))
        ..add(encodeFrame([2, 2]));
      expect(d.push(wire.toBytes()), [
        [1],
        [2, 2],
      ]);
    });

    test('半包：逐字节喂入', () {
      final d = FrameDecoder();
      final wire = encodeFrame(List.generate(50, (i) => i));
      var got = <Uint8List>[];
      for (final b in wire) {
        got = [...got, ...d.push([b])];
      }
      expect(got, hasLength(1));
      expect(got[0], List.generate(50, (i) => i));
    });

    test('帧长前缀与包体跨切分', () {
      final d = FrameDecoder();
      final wire = encodeFrame(List.filled(300, 7));
      expect(d.push(wire.sublist(0, 1)), isEmpty); // 长度前缀不完整
      expect(d.push(wire.sublist(1, 10)), isEmpty);
      final frames = d.push(wire.sublist(10));
      expect(frames, hasLength(1));
      expect(frames[0].length, 300);
    });

    test('非法帧长拒绝', () {
      final d = FrameDecoder();
      // 0x80 0x80 0x80 0x80 0x08 = VarInt 0x10000000 (256MiB > 上限)
      expect(
        () => d.push([0x80, 0x80, 0x80, 0x80, 0x08]),
        throwsFormatException,
      );
    });
  });

  group('压缩层', () {
    test('阈值内不压缩（uncompressedSize=0）', () {
      final fc = FrameCodec(threshold: 256);
      final payload = List.filled(10, 9);
      final frame = fc.encode(payload);
      // 首字节是 varint 0 → 未压缩原文
      expect(frame[0], 0);
      expect(fc.decode(frame), payload);
    });

    test('阈值外 zlib 往返且长度校验', () {
      final fc = FrameCodec(threshold: 32);
      final payload = List.filled(1000, 0x41);
      final frame = fc.encode(payload);
      expect(frame.length, lessThan(32 + 100)); // 高重复数据应显著变小
      final decoded = fc.decode(frame);
      expect(decoded, payload);
    });

    test('阈值切换（登录阶段 SetCompression 语义）', () {
      final fc = FrameCodec();
      final payload = List.filled(500, 0x41);
      // 未协商：帧体 = 明文包字节，无前缀
      expect(fc.encode(payload), payload);
      // 协商后：所有帧都带 uncompressedSize 前缀
      fc.threshold = 64;
      final compFrame = fc.encode(payload);
      expect(fc.decode(compFrame), payload);
      // 小于阈值的帧也带前缀（前缀 0）
      final small = fc.encode([1, 2, 3]);
      expect(small[0], 0);
      expect(fc.decode(small), [1, 2, 3]);
    });

    test('声明长度与实际不符即拒绝', () {
      final fc = FrameCodec(threshold: 16);
      final good = fc.encode(List.filled(100, 1));
      // 篡改声明长度字段（首字节为压缩帧的 size varint）
      final tampered = Uint8List.fromList(good);
      tampered[0] = 99;
      expect(() => fc.decode(tampered), throwsFormatException);
    });
  });
}
