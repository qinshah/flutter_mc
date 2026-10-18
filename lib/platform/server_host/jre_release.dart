// JRE `release` 文件读取（承载方式，无原版对应物；属第三类自由设计「运行时宿主」）。
//
//   口径照参考实现 `FCLauncher.readJREReleaseProperties` / `getJavaLibDir`
//   （`FCLauncher.java:77-107`）：JRE 的 `release` 是 Java 运行时自带的键值文本，
//   `OS_ARCH` 用来定位 `lib/<arch>`，`JAVA_VERSION` 用来判主版本。
//
//   独立成文件的原因：`artifact_resolver.dart`（产物解析，纯 dart:io）与
//   `android_embedded_jvm_host.dart`（承载实现，依赖 Flutter 通道）都要读它，
//   放在任一侧都会引入不必要的依赖或环。故此处只做"读文件 + 解析"。

import 'dart:convert';
import 'dart:io';

/// JRE `release` 文件的读取与解析。
class JreRelease {
  JreRelease._();

  /// 读 `OS_ARCH`（如 `aarch64`）；读不到返回 null。
  static String? osArch(Directory jreDir) => _value(jreDir, 'OS_ARCH');

  /// 读 `JAVA_VERSION`（如 `25.0.2`、`1.8.0_392`）；读不到返回 null。
  static String? javaVersion(Directory jreDir) => _value(jreDir, 'JAVA_VERSION');

  /// 从 `JAVA_VERSION` 解析 Java 主版本；读不到或解析失败返回 null。
  ///
  /// 兼容两种形态：`25.0.2` → 25；旧式 `1.8.0_392` → 8。
  static int? javaMajor(Directory jreDir) {
    final version = javaVersion(jreDir);
    if (version == null || version.isEmpty) return null;
    final parts = version.split(RegExp(r'[._]'));
    final first = int.tryParse(parts.first);
    if (first == null) return null;
    if (first == 1 && parts.length > 1) return int.tryParse(parts[1]);
    return first;
  }

  static String? _value(Directory jreDir, String key) {
    final release = File('${jreDir.path}/release');
    if (!release.existsSync()) return null;
    for (final line in const LineSplitter().convert(release.readAsStringSync())) {
      if (line.startsWith('$key=')) {
        return line.substring(key.length + 1).replaceAll('"', '').trim();
      }
    }
    return null;
  }
}
