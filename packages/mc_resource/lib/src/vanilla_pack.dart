import 'dart:io';
import 'dart:typed_data';

/// 资源包字节来源抽象（原版 `server.packs` 的 PackResources 对应物的最小面）。
/// 纯 Dart：应用侧的 bundle 来源经 [CallbackPackSource] 注入，本包不依赖 Flutter。
abstract interface class PackSource {
  /// 读取相对路径的字节；缺失返回 null，不抛异常。
  Future<Uint8List?> read(String path);
}

/// 目录来源：root 即某版本资源目录（如 `assets/vanilla/26_2`）。
class DirectoryPackSource implements PackSource {
  DirectoryPackSource(this.root);

  final Directory root;

  @override
  Future<Uint8List?> read(String path) async {
    final f = File('${root.path}/$path');
    if (!f.existsSync()) return null;
    return f.readAsBytesSync();
  }
}

/// 回调来源：应用侧注入（如经 rootBundle 读打包资产）。
class CallbackPackSource implements PackSource {
  CallbackPackSource(this._read);

  final Future<Uint8List?> Function(String path) _read;

  @override
  Future<Uint8List?> read(String path) => _read(path);
}

/// 版本键化的原版资源包（对应原版 VanillaPackResources 的读取面）。
/// 版本即提取目录名（如 "26_2"）；未来"应用内按版本下载 jar"只是新 PackSource。
class VanillaPack {
  VanillaPack({required this.version, required this.source});

  final String version;
  final PackSource source;

  factory VanillaPack.fromDirectory(String dir) {
    final version = dir.split('/').last;
    return VanillaPack(version: version, source: DirectoryPackSource(Directory(dir)));
  }

  /// 应用 bundle 语境下的完整资产路径（app 壳构造 CallbackPackSource 时用）。
  static String bundlePath(String version, String path) =>
      'assets/vanilla/$version/$path';

  Future<Uint8List?> read(String path) => source.read(path);

  Future<String?> readString(String path) async {
    final bytes = await source.read(path);
    if (bytes == null) return null;
    return String.fromCharCodes(bytes);
  }
}
