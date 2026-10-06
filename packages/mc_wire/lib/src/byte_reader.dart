import 'dart:convert';
import 'dart:typed_data';

/// 网络字节读游标 —— 语义对齐原版 `FriendlyByteBuf` 的读侧
/// （REF: mc-sources/minecraft-26.2 `network/FriendlyByteBuf` 与 `network/codec/`）。
///
/// 位宽与字节序纪律：多字节定宽数一律**大端**；`varInt`/`varLong` 是 LEB128 变体
/// （每字节低 7 位有效、最高位为续传标志），上限分别为 5 / 10 字节——超限即抛
/// [VarIntTooLongException]，不得静默截断。
///
/// 本类型不认识任何具体包类型（mc_wire 的版本无关纪律）；字符串一律标准 UTF-8
/// （26.2 协议侧如此；NBT 侧的 modified UTF-8 是 `mc_nbt` 的事，两套不混用）。
class ByteReader {
  ByteReader(this._bytes) : _pos = 0;

  final Uint8List _bytes;
  int _pos;

  /// 已读字节数。
  int get position => _pos;

  /// 重定位游标（探测式解析后回退用；配合 [readRemaining] 做自限界
  /// 子格式解析——NBT 这类无长度前缀的形态靠解析器自身求结束偏移）。
  set position(int value) {
    if (value < 0 || value > _bytes.length) {
      throw RangeError('position 越界: $value');
    }
    _pos = value;
  }

  /// 剩余可读字节数。
  int get remaining => _bytes.length - _pos;

  bool get hasRemaining => _pos < _bytes.length;

  /// 读完剩余字节（包体里"剩下都是载荷"的形态用）。
  Uint8List readRemaining() {
    final r = Uint8List.sublistView(_bytes, _pos);
    _pos = _bytes.length;
    return r;
  }

  void _need(int n) {
    if (_bytes.length - _pos < n) {
      throw RangeError('ByteReader 溢出：需 $n 字节，剩余 ${_bytes.length - _pos}');
    }
  }

  int readUnsignedByte() {
    _need(1);
    return _bytes[_pos++];
  }

  int readByte() => readUnsignedByte().toSigned(8);

  bool readBool() => readUnsignedByte() != 0;

  int readUnsignedShort() {
    _need(2);
    final v = (_bytes[_pos] << 8) | _bytes[_pos + 1];
    _pos += 2;
    return v;
  }

  int readShort() => readUnsignedShort().toSigned(16);

  int readInt() {
    _need(4);
    final v = (_bytes[_pos] << 24) |
        (_bytes[_pos + 1] << 16) |
        (_bytes[_pos + 2] << 8) |
        _bytes[_pos + 3];
    _pos += 4;
    return v.toSigned(32);
  }

  int readLong() {
    _need(8);
    var v = 0;
    for (var i = 0; i < 8; i++) {
      v = (v << 8) | _bytes[_pos + i];
    }
    _pos += 8;
    return v;
  }

  double readFloat() {
    _need(4);
    final v = ByteData.sublistView(_bytes, _pos, _pos + 4).getFloat32(0, Endian.big);
    _pos += 4;
    return v;
  }

  double readDouble() {
    _need(8);
    final v = ByteData.sublistView(_bytes, _pos, _pos + 8).getFloat64(0, Endian.big);
    _pos += 8;
    return v;
  }

  /// 读 VarInt（上限 5 字节；结果按 32 位有符号解释）。
  int readVarInt() {
    var result = 0;
    var shift = 0;
    while (true) {
      _need(1);
      final b = _bytes[_pos++];
      result |= (b & 0x7F) << shift;
      if ((b & 0x80) == 0) break;
      shift += 7;
      if (shift >= 35) throw VarIntTooLongException();
    }
    return result.toSigned(32);
  }

  /// 读 VarLong（上限 10 字节；结果按 64 位有符号解释）。
  int readVarLong() {
    var result = 0;
    var shift = 0;
    while (true) {
      _need(1);
      final b = _bytes[_pos++];
      result |= (b & 0x7F) << shift;
      if ((b & 0x80) == 0) break;
      shift += 7;
      if (shift >= 70) throw VarIntTooLongException();
    }
    return result; // Dart int 即 64 位
  }

  /// 读定长字节数组。
  Uint8List readBytes(int length) {
    _need(length);
    final r = Uint8List.sublistView(_bytes, _pos, _pos + length);
    _pos += length;
    return r;
  }

  /// 读 `varint 长度 + 字节` 形态的字节数组
  /// （REF: `FriendlyByteBuf.readByteArray`；可选上限校验）。
  Uint8List readByteArray({int? maxLength}) {
    final length = readVarInt();
    if (maxLength != null && length > maxLength) {
      throw FormatException('byteArray 超上限：$length > $maxLength');
    }
    return readBytes(length);
  }

  /// 读 `varint 字节长 + UTF-8` 字符串（[maxLength] 按字符数校验，
  /// 对齐 `FriendlyByteBuf.readUtf(maxLength)` 的语义）。
  String readUtf([int maxLength = 32767]) {
    final byteLen = readVarInt();
    final raw = readBytes(byteLen);
    final s = utf8.decode(raw, allowMalformed: false);
    if (s.length > maxLength) {
      throw FormatException('utf 超上限：${s.length} > $maxLength');
    }
    return s;
  }

  /// 读布尔前缀的可选结构：`present ? readBody() : null`（原版 Optional 形态）。
  T? readOptional<T>(T Function() readBody) => readBool() ? readBody() : null;
}

class VarIntTooLongException implements Exception {
  const VarIntTooLongException();

  @override
  String toString() => 'VarInt/VarLong 超过字节上限';
}
