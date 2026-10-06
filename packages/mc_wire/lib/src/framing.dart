import 'dart:typed_data';

import 'byte_reader.dart';
import 'byte_writer.dart';

/// VarInt 长度前缀分帧 —— MC 协议 TCP 层的唯一分帧形态
/// （REF: mc-sources/minecraft-26.2 `network/FriendlyByteBuf` 的
/// `readVarIntByteArray`/`writeVarIntByteArray` 用法、`network/Connection`）。
///
/// 帧 = `varint bodyLen + body`。[FrameDecoder] 接受任意切分的字节流
/// （粘包/半包/一包多帧都正确处理），产出完整帧体；[encodeFrame] 是它的镜像。
class FrameDecoder {
  final BytesBuilder _pending = BytesBuilder();

  /// 喂入一段字节流，返回其中能凑齐的完整帧体（可能 0 个、1 个或多个）。
  List<Uint8List> push(List<int> data) {
    _pending.add(data);
    final frames = <Uint8List>[];
    while (true) {
      final bytes = _pending.toBytes();
      final lenResult = _tryReadVarInt(bytes, 0);
      if (lenResult == null) break; // 长度前缀还不完整
      final bodyLen = lenResult.value;
      if (bodyLen < 0 || bodyLen > maxFrameLength) {
        throw FormatException('帧长非法：$bodyLen');
      }
      final bodyStart = lenResult.next;
      if (bytes.length - bodyStart < bodyLen) break; // 包体还不完整
      frames.add(Uint8List.sublistView(bytes, bodyStart, bodyStart + bodyLen));
      _pending.clear();
      _pending.add(bytes.sublist(bodyStart + bodyLen));
    }
    return frames;
  }

  /// 对端关流时若还有半帧，说明截断了。
  bool get hasPartialFrame => _pending.toBytes().isNotEmpty;

  static const int maxFrameLength = 1 << 24; // 16 MiB，防御性上限

  static _VarInt? _tryReadVarInt(List<int> bytes, int offset) {
    var result = 0;
    var shift = 0;
    var i = offset;
    while (i < bytes.length) {
      final b = bytes[i++];
      result |= (b & 0x7F) << shift;
      if ((b & 0x80) == 0) return _VarInt(result.toSigned(32), i);
      shift += 7;
      if (shift >= 35) throw const VarIntTooLongException();
    }
    return null;
  }
}

class _VarInt {
  const _VarInt(this.value, this.next);
  final int value;
  final int next;
}

/// [FrameDecoder] 的镜像：帧体 → `varint len + body`。
Uint8List encodeFrame(List<int> body) {
  final w = ByteWriter();
  w.writeVarInt(body.length);
  w.writeBytes(body);
  return w.takeBytes();
}
