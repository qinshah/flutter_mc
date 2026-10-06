import 'dart:io';
import 'dart:typed_data';

import 'byte_reader.dart';
import 'byte_writer.dart';

/// zlib 帧内压缩层 —— 登录阶段 `ClientboundLoginCompressionPacket` 协商阈值后启用
/// （REF: mc-sources/minecraft-26.2 `network/protocol/login/ClientboundLoginCompressionPacket.java`、
/// `network/compression/CompressionThreshold` 语义）。
///
/// 压缩发生在**帧体内部**：帧体 = `varint uncompressedSize + payload`。
/// - `uncompressedSize == 0`：payload 是**未压缩**的原文（小于阈值时这样发）；
/// - 否则 payload 是 zlib 压缩流，解压后长度 MUST 等于 `uncompressedSize`
///   （REF: `CompressionDecoder`——长度不符即断连，这里同样抛异常）。
class FrameCodec {
  FrameCodec({this.threshold = 0});

  /// 协商出的压缩阈值（字节）。0 = 未压缩（登录/状态阶段）。
  int threshold;

  /// 帧体（明文包字节）→ 线上帧体（按阈值决定是否压缩）。
  ///
  /// 阈值 0 = 压缩未协商：帧体即明文包字节，**无前缀**（原版语义：SetCompression
  /// 之前连接上不存在 uncompressedSize 字段）。阈值 >0 时所有帧都带前缀，
  /// 小于阈值的前缀为 0。
  Uint8List encode(List<int> packetBytes) {
    if (threshold <= 0) {
      return Uint8List.fromList(packetBytes);
    }
    if (packetBytes.length < threshold) {
      final w = ByteWriter();
      w.writeVarInt(0);
      w.writeBytes(packetBytes);
      return w.takeBytes();
    }
    final compressed = zlib.encode(packetBytes) as Uint8List;
    final w = ByteWriter();
    w.writeVarInt(packetBytes.length);
    w.writeBytes(compressed);
    return w.takeBytes();
  }

  /// 线上帧体 → 明文包字节。
  ///
  /// 阈值 0（未协商压缩）时帧体就是明文包字节，直接透传；协商后**每一帧**都带
  /// `uncompressedSize` 前缀（原版语义：SetCompression 之后的帧格式整体切换）。
  Uint8List decode(List<int> frameBody) {
    if (threshold <= 0) {
      return Uint8List.fromList(frameBody);
    }
    final r = ByteReader(Uint8List.fromList(frameBody));
    final uncompressedSize = r.readVarInt();
    final payload = r.readRemaining();
    if (uncompressedSize == 0) {
      return payload;
    }
    final decompressed = zlib.decode(payload) as Uint8List?;
    if (decompressed == null || decompressed.length != uncompressedSize) {
      throw FormatException(
        '压缩帧长度不符：声明 $uncompressedSize，实际 ${decompressed?.length}',
      );
    }
    return decompressed;
  }
}
