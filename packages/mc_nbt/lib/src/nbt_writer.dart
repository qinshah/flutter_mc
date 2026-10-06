import 'dart:io';
import 'dart:typed_data';

import 'java_utf.dart';
import 'nbt_tag.dart';

/// NBT 序列化（全大端，逐字节对照 Java `DataOutputStream` / `CompressedStreamTools`）。
///
/// 设计上只有一条不可让步的性质：**写出来的字节必须能被原版 1.12.2 原样读回**，
/// 因此这里不做任何"顺手规范化"——列表元素类型原样写、标签顺序原样写、
/// 字符串一律走 Java modified UTF-8。
///
/// 压缩只有一种情况要记牢：**region 负载只用 zlib（type 2）**，与原版 1.12.2 一致
/// （gzip 只在 `level.dat` / `playerdata` 这类独立文件上用，design.md §4.6）。
abstract final class NbtWriter {
  /// 根 = `[类型 10][空名字][负载]`（原版 `CompressedStreamTools#writeUnnamedTag` + 空名字）。
  static Uint8List writeRoot(NbtCompound compound) {
    final writer = _Writer();
    writer.writeUint8(NbtTagType.compound);
    writer.writeEmptyName();
    writer.writeCompoundPayload(compound);
    return writer.takeBytes();
  }

  /// 写进调用方给的 [BytesBuilder]（避免为了拼一段 NBT 多分配一次）。
  static void writeRootTo(NbtCompound compound, BytesBuilder out) {
    out.add(writeRoot(compound));
  }

  /// gzip 压缩的裸 NBT 字节（`level.dat` / `playerdata` / `servers.dat`）。
  static Uint8List writeGzipBytes(NbtCompound compound) =>
      Uint8List.fromList(gzip.encode(writeRoot(compound)));

  /// 写 gzip 压缩的 NBT 文件，必要时建父目录（原版 `CompressedStreamTools#write` 同样如此）。
  static void writeGzipFile(NbtCompound compound, File file) {
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(writeGzipBytes(compound), flush: true);
  }

  /// zlib 压缩的裸 NBT 字节（`.mca` 的 slot 负载）。
  static Uint8List writeZlibBytes(NbtCompound compound) =>
      Uint8List.fromList(zlib.encode(writeRoot(compound)));
}

/// 大端写入器。
///
/// [BytesBuilder] 用默认的 `copy: true`：`copy: false` 会直接持有我们传入的
/// `Uint8List` 视图，而本类复用一个 8 字节的暂存缓冲 —— 那样会写出串位的垃圾。
final class _Writer {
  final BytesBuilder _out = BytesBuilder();
  final Uint8List _scratch = Uint8List(8);
  late final ByteData _scratchData = ByteData.sublistView(_scratch);

  Uint8List takeBytes() => _out.takeBytes();

  Uint8List _take(int count) => Uint8List.fromList(_scratch.sublist(0, count));

  void writeUint8(int value) => _out.addByte(value & 0xff);

  void writeInt16(int value) {
    _scratchData.setInt16(0, value);
    _out.add(_take(2));
  }

  void writeInt32(int value) {
    _scratchData.setInt32(0, value);
    _out.add(_take(4));
  }

  void writeInt64(int value) {
    _scratchData.setInt64(0, value);
    _out.add(_take(8));
  }

  /// `setFloat32` 会按 IEEE-754 就近舍入到单精度 —— 这正是 Java `writeFloat` 的行为，
  /// 也是"读出来的 f32 再写回去必须逐位相同"的保证。
  void writeFloat32(double value) {
    _scratchData.setFloat32(0, value);
    _out.add(_take(4));
  }

  void writeFloat64(double value) {
    _scratchData.setFloat64(0, value);
    _out.add(_take(8));
  }

  /// 根标签的名字固定是空串：即"2 字节大端长度 0"（原版 `writeUnnamedTag` 写 `""`）。
  void writeEmptyName() => _out.add(const <int>[0, 0]);

  void writeJavaUtf(String value) => _out.add(JavaUtf.encode(value));

  void writeCompoundPayload(NbtCompound compound) {
    for (final key in compound.keys) {
      final tag = compound[key]!;
      writeUint8(tag.type);
      writeJavaUtf(key);
      writePayload(tag);
    }
    writeUint8(NbtTagType.end); // compound 的结束标记
  }

  /// 列表负载：`[元素类型][元素个数][元素…]`。
  ///
  /// 元素类型**原样写出、不做规范化**（原版 1.12.2 会把空列表的类型改写成 0，
  /// 我们不做这件事）：真实存档里空列表本来就都是 0，写出来与原版逐字节相同；
  /// 而 mod 写出的非 0 类型则原样保留，不丢信息（design.md §4.5）。
  void writeListPayload(NbtList list) {
    writeUint8(list.elementType);
    writeInt32(list.length);
    for (final element in list.value) {
      writePayload(element);
    }
  }

  void writePayload(NbtTag tag) {
    switch (tag) {
      case NbtEnd():
        throw NbtFormatException('END 标签不是数据，不能作为负载写出');
      case NbtByte():
        writeUint8(tag.value);
      case NbtShort():
        writeInt16(tag.value);
      case NbtInt():
        writeInt32(tag.value);
      case NbtLong():
        writeInt64(tag.value);
      case NbtFloat():
        writeFloat32(tag.value);
      case NbtDouble():
        writeFloat64(tag.value);
      case NbtByteArray():
        writeInt32(tag.value.length);
        _out.add(tag.value);
      case NbtString():
        writeJavaUtf(tag.value);
      case NbtList():
        writeListPayload(tag);
      case NbtCompound():
        writeCompoundPayload(tag);
      case NbtIntArray():
        writeInt32(tag.value.length);
        _out.add(_int32Bytes(tag.value));
      case NbtLongArray():
        writeInt32(tag.value.length);
        final buffer = Uint8List(tag.value.length * 8);
        final data = ByteData.sublistView(buffer);
        for (var i = 0; i < tag.value.length; i++) {
          data.setInt64(i * 8, tag.value[i]);
        }
        _out.add(buffer);
    }
  }

  /// 批量转大端：逐元素 `setInt32` + 逐个 `add` 会产生大量小分配，
  /// 一次成型再整体追加（`HeightMap` 与 `TileTicks` 都会走这条）。
  static Uint8List _int32Bytes(Int32List values) {
    final buffer = Uint8List(values.length * 4);
    final data = ByteData.sublistView(buffer);
    for (var i = 0; i < values.length; i++) {
      data.setInt32(i * 4, values[i]);
    }
    return buffer;
  }
}
