import 'dart:typed_data';

import 'package:mc_wire/mc_wire.dart';
import 'package:test/test.dart';

void main() {
  group('VarInt 边界与往返', () {
    const cases = [0, 1, 127, 128, 255, 16383, 16384, 65535, 0x7FFFFFFF, -1, -2147483648];
    for (final v in cases) {
      test('roundtrip $v', () {
        final w = ByteWriter()..writeVarInt(v);
        final r = ByteReader(w.takeBytes());
        expect(r.readVarInt(), v);
        expect(r.hasRemaining, isFalse);
      });
    }

    test('-1 编码为 5 字节（0xFFFFFFFF）', () {
      final w = ByteWriter()..writeVarInt(-1);
      expect(w.length, 5);
    });

    test('超过 5 字节即拒绝', () {
      final bytes = Uint8List.fromList([0x80, 0x80, 0x80, 0x80, 0x80, 0x01]);
      expect(() => ByteReader(bytes).readVarInt(), throwsA(isA<VarIntTooLongException>()));
    });

    test('剩余不足即溢出报错', () {
      // 0x80 = 续传位已置位但字节流结束
      expect(() => ByteReader(Uint8List.fromList([0x80])).readVarInt(), throwsRangeError);
    });
  });

  group('VarLong 边界与往返', () {
    const cases = [0, 1, 127, 128, 16383, 0x7FFFFFFFFFFFFFFF, -1, -9223372036854775808];
    for (final v in cases) {
      test('roundtrip $v', () {
        final w = ByteWriter()..writeVarLong(v);
        final r = ByteReader(w.takeBytes());
        expect(r.readVarLong(), v);
      });
    }

    test('-1 编码为 10 字节', () {
      final w = ByteWriter()..writeVarLong(-1);
      expect(w.length, 10);
    });
  });

  group('定宽数大端', () {
    test('unsignedShort BE', () {
      final w = ByteWriter()..writeUnsignedShort(0x1234);
      expect(w.takeBytes(), [0x12, 0x34]);
    });

    test('int BE 与符号', () {
      final w = ByteWriter()..writeInt(-1);
      expect(w.takeBytes(), [0xFF, 0xFF, 0xFF, 0xFF]);
    });

    test('long BE 往返', () {
      final w = ByteWriter()..writeLong(0x0102030405060708);
      final r = ByteReader(w.takeBytes());
      expect(r.readLong(), 0x0102030405060708);
    });
  });

  group('utf 与 byteArray', () {
    test('ascii 与多字节往返', () {
      const s = 'A Minecraft Server 中文 🎮';
      final w = ByteWriter()..writeUtf(s);
      final r = ByteReader(w.takeBytes());
      expect(r.readUtf(), s);
    });

    test('utf 超长按字符数拒绝', () {
      final w = ByteWriter()..writeUtf('中' * 10);
      final r = ByteReader(w.takeBytes());
      expect(() => r.readUtf(5), throwsFormatException);
    });

    test('byteArray 往返与上限', () {
      final data = Uint8List.fromList(List.generate(300, (i) => i % 256));
      final w = ByteWriter()..writeByteArray(data);
      final r = ByteReader(w.takeBytes());
      expect(r.readByteArray(maxLength: 1024), data);
    });
  });

  group('Optional 前缀', () {
    test('有值/无值', () {
      final w = ByteWriter();
      w.writeOptional<int>(null, (v) => w.writeInt(v));
      w.writeOptional<int>(42, w.writeInt);
      final r = ByteReader(w.takeBytes());
      expect(r.readOptional(r.readInt), isNull);
      expect(r.readOptional(r.readInt), 42);
    });
  });
}
