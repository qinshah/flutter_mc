/// mc_nbt —— Minecraft NBT 编解码。
///
/// [NbtReader.readNetworkRoot] 处理协议线上 NBT（根无名字）。
/// 纯 Dart、无 Flutter 依赖、无 GPU 类型，可在 worker isolate 运行。
library;

export 'src/java_utf.dart';
export 'src/nbt_reader.dart';
export 'src/nbt_tag.dart';
export 'src/nbt_writer.dart';
