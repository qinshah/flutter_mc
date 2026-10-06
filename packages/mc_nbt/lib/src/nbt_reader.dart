import 'dart:io';
import 'dart:typed_data';

import 'java_utf.dart';
import 'nbt_tag.dart';

/// NBT 反序列化（全大端，逐字节对照 Java `DataInputStream` / `CompressedStreamTools`）。
///
/// 三条来自原版的行为约定：
/// 1. **根必须是命名的 COMPOUND**（`CompressedStreamTools#readUnnamedTag` + "Root tag must be
///    a named compound tag"）；根名字读了就丢 —— 原版也丢。
/// 2. **嵌套深度上限 512**（`NBTBase#readPayload` 里 `if (depth > 512) throw`）。
///    没有这条，一个几 KB 的畸形文件就能把栈打穿。
/// 3. **列表可以"有元素却把元素类型写成 END"** 是损坏（原版 "Missing type on ListTag"）；
///    反过来"空列表 + 任意类型"是合法的，原样保留（design.md §4.5）。
///
/// 额外加了一条原版没有的防护：**任何集合长度都要与剩余字节数对得上**。
/// 原版用 `NBTSizeTracker` 限制总读取量；我们直接拿"每个元素至少占 1 字节"来卡，
/// 这样畸形长度（例如声称有 20 亿个 int）在**分配之前**就被拒绝，不会 OOM。
abstract final class NbtReader {
  /// 与原版 `NBTBase#readPayload` 的 `depth > 512` 一致。
  static const int maxDepth = 512;

  /// 读一个裸 NBT（根 = `[类型 10][空名字][负载]`）。
  ///
  /// 允许缓冲区尾部有多余字节（原版也允许）：`.mca` 的负载是按扇区对齐的，
  /// 调用方通常已经把精确区间切出来了，多切几个字节不该报错。
  static NbtCompound readRoot(Uint8List bytes) => _Cursor(bytes).readRoot();

  /// 读**网络 NBT**（协议线上形态）：根 = `[类型 10][负载]`，
  /// **没有根名字段**（判据：`FriendlyByteBuf.readNbt` → `NbtIo.read` 的网络变体）。
  ///
  /// 允许缓冲区尾部有多余字节（线上包常把 NBT 放在包体中间，长度由调用方切好）。
  static NbtCompound readNetworkRoot(Uint8List bytes) =>
      _Cursor(bytes).readNetworkRoot();

  /// 读单个网络 NBT 标签并**报告消费到的偏移**（线上包里 NBT 后面还有别的
  /// 字段时的唯一正确读法——NBT 无长度前缀，只能靠解析器自限界）。
  ///
  /// 返回 `(tag, end)`：[end] 是标签负载结束后的字节偏移（即下一字段的起点）。
  /// 输入格式 = `[类型字节][负载]`（无名字；调用方已消费掉 optional 的 bool）。
  static ({NbtTag tag, int end}) readNetworkTagSized(Uint8List bytes) {
    final c = _Cursor(bytes);
    final type = c.readUint8();
    final tag = c.readPayload(type, 0);
    return (tag: tag, end: c.offset);
  }

  /// 读 gzip 压缩的 NBT：`level.dat`、`level.dat_old`、`playerdata/*.dat`。
  static NbtCompound readGzip(Uint8List compressed) =>
      readRoot(_gunzip(compressed));

  /// 读 gzip 压缩的 NBT 文件。
  static NbtCompound readGzipFile(File file) =>
      readGzip(file.readAsBytesSync());

  /// 读 zlib 压缩的 NBT：`.mca` 里 slot 的负载（type 2）。
  static NbtCompound readZlib(Uint8List compressed) =>
      readRoot(_unzlib(compressed));

  /// 嗅探式读文件：gzip 魔数 `1F 8B` → 先解压；否则当裸 NBT 读。
  ///
  /// 原版 `CompressedStreamTools#read(File)` 也是先看头部再决定解不解压，
  /// 因为 `servers.dat` 这类文件既可能是 gzip 也可能是裸 NBT。
  static NbtCompound readFile(File file) {
    final bytes = file.readAsBytesSync();
    final isGzip = bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b;
    return readRoot(isGzip ? _gunzip(bytes) : bytes);
  }

  static Uint8List _gunzip(Uint8List compressed) {
    try {
      return Uint8List.fromList(gzip.decode(compressed));
    } on FormatException catch (e) {
      throw NbtFormatException('gzip 解压失败：${e.message}');
    }
  }

  static Uint8List _unzlib(Uint8List compressed) {
    try {
      return Uint8List.fromList(zlib.decode(compressed));
    } on FormatException catch (e) {
      throw NbtFormatException('zlib 解压失败：${e.message}');
    }
  }
}

/// 只读游标。所有多字节整数都是**大端**（Java `DataInputStream`）。
final class _Cursor {
  _Cursor(this._bytes) : _data = ByteData.sublistView(_bytes);

  final Uint8List _bytes;
  final ByteData _data;
  int _offset = 0;

  int get offset => _offset;
  int get remaining => _bytes.length - _offset;

  void _need(int count) {
    if (_offset + count > _bytes.length) {
      throw NbtFormatException(
        '被截断：还需要 $count 字节，只剩 $remaining 字节',
        offset: _offset,
      );
    }
  }

  int readUint8() {
    _need(1);
    return _bytes[_offset++];
  }

  int readInt8() {
    _need(1);
    return _data.getInt8(_offset++);
  }

  int readInt16() {
    _need(2);
    final v = _data.getInt16(_offset);
    _offset += 2;
    return v;
  }

  int readInt32() {
    _need(4);
    final v = _data.getInt32(_offset);
    _offset += 4;
    return v;
  }

  int readInt64() {
    _need(8);
    final v = _data.getInt64(_offset);
    _offset += 8;
    return v;
  }

  /// `getFloat32` 出来的 `double` 是 f32 的**精确值**，写回去时 `setFloat32` 会四舍五入到
  /// 同一个 f32 —— 因此 float 标签的往返是逐位无损的。
  double readFloat32() {
    _need(4);
    final v = _data.getFloat32(_offset);
    _offset += 4;
    return v;
  }

  double readFloat64() {
    _need(8);
    final v = _data.getFloat64(_offset);
    _offset += 8;
    return v;
  }

  /// 返回**视图**而不是拷贝：字节数组是区块里体积最大的部分（`Blocks` 4096 × 16 段），
  /// 拷贝一遍纯属浪费 —— 视图与整块解压缓冲同生共死，峰值内存反而更低。
  Uint8List readBytes(int count) {
    _need(count);
    final view = Uint8List.sublistView(_bytes, _offset, _offset + count);
    _offset += count;
    return view;
  }

  String readJavaUtf() {
    final result = JavaUtf.decodeFrom(_bytes, _offset);
    _offset = result.nextOffset;
    return result.value;
  }

  /// 读一个集合长度并做合法性检查（负数是损坏；超过剩余字节数也是损坏）。
  int readLength(String what, int bytesPerElement) {
    final offsetBefore = _offset;
    final n = readInt32();
    if (n < 0) {
      throw NbtFormatException(
        '$what 的长度为负（$n）：原版同样视为损坏',
        offset: offsetBefore,
      );
    }
    if (n * bytesPerElement > remaining) {
      throw NbtFormatException(
        '$what 声称有 $n 个元素（至少需 ${n * bytesPerElement} 字节），'
        '但只剩 $remaining 字节 —— 判定为损坏，拒绝分配',
        offset: offsetBefore,
      );
    }
    return n;
  }

  NbtCompound readNetworkRoot() {
    final type = readUint8();
    if (type != NbtTagType.compound) {
      throw NbtFormatException(
        '网络 NBT 根必须是 COMPOUND（类型 10），实际是 ${NbtTagType.nameOf(type)}',
        offset: 0,
      );
    }
    // 网络形态：没有根名字段，直接进负载
    return _compound(0);
  }

  NbtCompound readRoot() {
    final type = readUint8();
    if (type != NbtTagType.compound) {
      throw NbtFormatException(
        '根标签必须是 COMPOUND（类型 10），实际是 ${NbtTagType.nameOf(type)}：'
        '原版 CompressedStreamTools 会抛 "Root tag must be a named compound tag"',
        offset: 0,
      );
    }
    readJavaUtf(); // 根名字读了就丢（原版也丢），但必须消费掉
    final root = _compound(0);
    return root;
  }

  NbtTag readPayload(int tagId, int depth) {
    if (depth > NbtReader.maxDepth) {
      throw NbtFormatException(
        'NBT 嵌套深度超过 ${NbtReader.maxDepth}（原版 NBTBase#readPayload 的上限）',
        offset: _offset,
      );
    }
    switch (tagId) {
      case NbtTagType.byte:
        return NbtByte(readInt8());
      case NbtTagType.short:
        return NbtShort(readInt16());
      case NbtTagType.int32:
        return NbtInt(readInt32());
      case NbtTagType.int64:
        return NbtLong(readInt64());
      case NbtTagType.float32:
        return NbtFloat(readFloat32());
      case NbtTagType.float64:
        return NbtDouble(readFloat64());
      case NbtTagType.byteArray:
        final n = readLength('BYTE_ARRAY', 1);
        return NbtByteArray(readBytes(n));
      case NbtTagType.string:
        return NbtString(readJavaUtf());
      case NbtTagType.list:
        return _list(depth);
      case NbtTagType.compound:
        return _compound(depth);
      case NbtTagType.intArray:
        final n = readLength('INT_ARRAY', 4);
        final values = Int32List(n);
        for (var i = 0; i < n; i++) {
          values[i] = readInt32();
        }
        return NbtIntArray(values);
      case NbtTagType.longArray:
        final n = readLength('LONG_ARRAY', 8);
        final values = List<int>.filled(n, 0);
        for (var i = 0; i < n; i++) {
          values[i] = readInt64();
        }
        return NbtLongArray(values);
      default:
        throw NbtFormatException(
          '非法 NBT 标签号 $tagId（合法范围 0..12）',
          offset: _offset - 1,
        );
    }
  }

  NbtList _list(int depth) {
    final elementType = readUint8();
    // 每个元素至少 1 字节，故元素数不可能超过剩余字节数。
    final count = readLength('LIST', 1);
    if (elementType == NbtTagType.end && count > 0) {
      throw NbtFormatException(
        '列表声明了 $count 个元素，元素类型却是 END（原版 Missing type on ListTag）',
        offset: _offset,
      );
    }
    final list = NbtList(elementType);
    for (var i = 0; i < count; i++) {
      // 元素类型已由文件头给定，逐个元素时不再重复读类型号。
      list.add(readPayload(elementType, depth + 1));
    }
    return list;
  }

  NbtCompound _compound(int depth) {
    final compound = NbtCompound();
    while (true) {
      final tagId = readUint8();
      if (tagId == NbtTagType.end) return compound;
      final name = readJavaUtf();
      compound[name] = readPayload(tagId, depth + 1);
    }
  }
}
