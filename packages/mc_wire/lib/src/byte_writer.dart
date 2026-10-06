import 'dart:convert';
import 'dart:typed_data';

/// 网络字节写出器 —— [ByteReader] 的镜像，语义对齐原版 `FriendlyByteBuf` 写侧。
///
/// 多字节定宽数一律大端；`varInt`/`varLong` 为 LEB128 变体。
/// 版本无关：本类型不认识任何具体包类型。
class ByteWriter {
  final BytesBuilder _builder = BytesBuilder();

  Uint8List takeBytes() => _builder.takeBytes();

  Uint8List toBytes() => _builder.toBytes();

  int get length => _builder.length;

  void writeUnsignedByte(int v) => _builder.addByte(v & 0xFF);

  void writeByte(int v) => writeUnsignedByte(v.toSigned(8));

  void writeBool(bool v) => _builder.addByte(v ? 1 : 0);

  void writeUnsignedShort(int v) {
    _builder.addByte((v >> 8) & 0xFF);
    _builder.addByte(v & 0xFF);
  }

  void writeShort(int v) => writeUnsignedShort(v.toSigned(16) & 0xFFFF);

  void writeInt(int v) {
    final u = v.toSigned(32) & 0xFFFFFFFF;
    _builder.addByte((u >> 24) & 0xFF);
    _builder.addByte((u >> 16) & 0xFF);
    _builder.addByte((u >> 8) & 0xFF);
    _builder.addByte(u & 0xFF);
  }

  void writeLong(int v) {
    for (var i = 7; i >= 0; i--) {
      _builder.addByte((v >> (8 * i)) & 0xFF);
    }
  }

  void writeFloat(double v) {
    final b = ByteData(4)..setFloat32(0, v, Endian.big);
    _builder.add(b.buffer.asUint8List());
  }

  void writeDouble(double v) {
    final b = ByteData(8)..setFloat64(0, v, Endian.big);
    _builder.add(b.buffer.asUint8List());
  }

  void writeVarInt(int value) {
    var v = value.toSigned(32) & 0xFFFFFFFF;
    while (true) {
      if ((v & ~0x7F) == 0) {
        _builder.addByte(v);
        return;
      }
      _builder.addByte((v & 0x7F) | 0x80);
      v >>>= 7;
    }
  }

  void writeVarLong(int value) {
    var v = value;
    while (true) {
      if ((v & ~0x7F) == 0) {
        _builder.addByte(v & 0x7F);
        return;
      }
      _builder.addByte((v & 0x7F) | 0x80);
      v = v >>> 7; // 64 位无符号右移：负数（如 -1 = 全 1）也按位处理
    }
  }

  void writeBytes(List<int> bytes) => _builder.add(bytes);

  /// `varint 字节长 + UTF-8`（REF: `FriendlyByteBuf.writeUtf(String, int)`；
  /// [maxLength] 按字符数校验）。
  void writeUtf(String s, [int maxLength = 32767]) {
    final raw = utf8.encode(s);
    if (s.length > maxLength) {
      throw FormatException('utf 超上限：${s.length} > $maxLength');
    }
    writeVarInt(raw.length);
    _builder.add(raw);
  }

  /// `varint 长度 + 字节` 形态（REF: `FriendlyByteBuf.writeByteArray`）。
  void writeByteArray(List<int> bytes) {
    writeVarInt(bytes.length);
    _builder.add(bytes);
  }

  /// 布尔前缀的可选结构。
  void writeOptional<T>(T? value, void Function(T) writeBody) {
    if (value == null) {
      writeBool(false);
    } else {
      writeBool(true);
      writeBody(value);
    }
  }
}
