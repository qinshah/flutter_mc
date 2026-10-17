// 产物解析：按实例配置的 `mcVersion` / `javaMajor` 解析 jar 与 JVM。
//
//   ⚠ 属第三类自由设计「运行时宿主（JVM 托管）」（AGENTS.md）：原版把服务端与 JRE 视为
//   进程自身已具备之物（`Main.java:72-73` 只解析 `-jar` 与 `--nogui` 之类的选项），
//   "到哪儿找 jar / 用哪个 JVM"在原版里由外层脚本决定，无 Java 可抄，故为承载方式豁免。
//   被托管物（服务端本体）照旧是翻译债（openspec/progress.md 第 14 项）。
//
// 口径（design.md D5）：
//   * 桌面**不捆绑 JRE**：探测系统 JDK 主版本，满足即用；不满足按"缺产物"报出并给指引。
//   * jar 现阶段由构建期资产携带（git 不追踪），或由用户在产物目录放置；缺失时入口置灰并
//     提示放置位置；**MUST NOT** 静默替换为其他版本（spec「产物解析与缺失降级」）。
import 'dart:io';

import 'local_server_config.dart';

/// 解析产物缺失（含期望位置），供 UI 置灰 + 报缺。
class ArtifactMissingException implements Exception {
  ArtifactMissingException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 解析出的可执行产物。
class ServerArtifacts {
  const ServerArtifacts({
    required this.jar,
    required this.javaExecutable,
    required this.javaMajor,
  });

  final File jar;
  final String javaExecutable;
  final int javaMajor;
}

/// JVM 主版本探测（可注入，便于单测；生产实现走 `java -version`）。
typedef JavaMajorProbe = int Function(String executable);

/// 系统 JVM 可执行文件定位（可注入；返回 null 表示找不到）。
typedef JavaExecutableLocator = String? Function();

/// 构建期资产目录下的 jar 键枚举（可注入；生产实现走 `AssetManifest`）。
/// 入参是资产目录前缀（如 `assets/server/26_2/`）；返回目录下出现的资产键。
typedef BundledJarLister = Future<List<String>> Function(String dirPrefix);

/// 构建期资产里的 jar 载入器（可注入；生产实现走 `rootBundle`）。
/// 返回 null 表示该资产不存在。
typedef BundledJarLoader = Future<List<int>?> Function(String assetKey);

class ArtifactResolver {
  ArtifactResolver({
    required this.root,
    JavaMajorProbe? javaProbe,
    JavaExecutableLocator? javaLocator,
    this.bundledJarLister,
    this.bundledJarLoader,
  })  : _javaProbe = javaProbe ?? probeSystemJavaMajor,
        _javaLocator = javaLocator ?? _resolveSystemJavaExecutable;

  /// 应用私有根（`local_server_host.dart` 下的 `local_server/`）。
  final Directory root;

  final JavaMajorProbe _javaProbe;
  final JavaExecutableLocator _javaLocator;

  /// 构建期资产目录的键枚举器（null 与 [bundledJarLoader] 任一为空即跳过资产回退）。
  final BundledJarLister? bundledJarLister;

  /// 构建期资产的 jar 载入器（null 与 [bundledJarLister] 任一为空即跳过资产回退）。
  final BundledJarLoader? bundledJarLoader;

  /// 用户放置 / 未来下载产物落地的目录（期望位置口径）。
  Directory get artifactsDir => Directory('${root.path}/artifacts');

  /// 期望位置说明（报缺时呈现给用户）。
  String get expectedJarLocation =>
      '${artifactsDir.path}/ 下放置 paper-$_versionLabel.jar';

  String _versionLabel = '<版本>';

  /// 版本目录标记：`26.2` → `26_2`（仓库既有惯例，与 `assets/vanilla/26_2` 一致）。
  static String _assetDirLabel(String mcVersion) =>
      mcVersion.replaceAll('.', '_');

  /// 解析（失败抛 [ArtifactMissingException]）。
  Future<ServerArtifacts> resolve(LocalServerConfig config) async {
    _versionLabel = config.mcVersion;
    final jar = await _resolveJar(config);
    final executable = _javaLocator();
    if (executable == null) {
      throw ArtifactMissingException(
        '未找到可用的 Java 运行环境：请安装 JDK ${config.javaMajor}（设置 JAVA_HOME 或让 `java` 进入 PATH）。',
      );
    }
    final major = _javaProbe(executable);
    if (major < config.javaMajor) {
      throw ArtifactMissingException(
        '系统 Java 主版本为 ${major < 0 ? "未知" : major}，本服务器需要 Java ${config.javaMajor}'
        '（Paper ${config.mcVersion} 判据见实测日志 logs/latest.log:1）。请升级 JDK 或为实例指定更高的 javaMajor。',
      );
    }
    return ServerArtifacts(
      jar: jar,
      javaExecutable: executable,
      javaMajor: major,
    );
  }

  /// jar 解析顺序：配置显式指定 → 产物目录（按 mcVersion 匹配）→ 构建期资产。
  Future<File> _resolveJar(LocalServerConfig config) async {
    final explicit = config.jarPath;
    if (explicit != null && explicit.isNotEmpty) {
      final file = File(explicit);
      if (file.existsSync()) return file;
      throw ArtifactMissingException(
        '实例配置指定的 jar 不存在：$explicit。请修正路径或留空以按版本自动解析。',
      );
    }

    artifactsDir.createSync(recursive: true);
    final jars = artifactsDir.existsSync()
        ? artifactsDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith('.jar'))
            .toList()
        : <File>[];
    if (jars.isNotEmpty) {
      final matched = jars
          .where((f) => f.uri.pathSegments.last.contains(config.mcVersion))
          .toList();
      if (matched.isEmpty) {
        // 有 jar 但版本对不上：拒绝（MUST NOT 静默替换）。
        final names = jars.map((f) => f.uri.pathSegments.last).join('、');
        throw ArtifactMissingException(
          '产物目录中找不到 ${config.mcVersion} 的 jar（现有：$names）。'
          '请放置 $expectedJarLocation。',
        );
      }
      // 多份同版本时取文件名默认排序首个（确定性）。
      matched.sort((a, b) => a.path.compareTo(b.path));
      return matched.first;
    }

    // 构建期资产：`assets/server/<label>/` 下的**任意** `.jar`。
    //   —— 不写死文件名：pubspec 逐目录声明（`assets/server/26_2/`），目录下所有文件
    //   都在 AssetManifest 里，落地的 jar 叫什么由携带者决定（本仓约定 `paper-<版本>.jar`，
    //   但用户可能放 `paper-26.2-129.jar` 之类；两者都应可用）。
    final lister = bundledJarLister;
    final loader = bundledJarLoader;
    if (lister != null && loader != null) {
      final dirPrefix = 'assets/server/${_assetDirLabel(config.mcVersion)}/';
      final keys = (await lister(dirPrefix))
          .where((k) => k.toLowerCase().endsWith('.jar'))
          .toList()
        ..sort();
      for (final key in keys) {
        final bytes = await loader(key);
        if (bytes != null) {
          final target =
              File('${artifactsDir.path}/server-${config.mcVersion}.jar');
          target.writeAsBytesSync(bytes, flush: true);
          return target;
        }
      }
    }

    throw ArtifactMissingException(
      '缺少 ${config.mcVersion} 的服务端产物。请将 Paper jar 放置于：$expectedJarLocation'
      '（产物因许可原因不入库；详见 README「本地服务器」）。',
    );
  }

  /// 系统 JVM 定位：`JAVA_HOME/bin/java` 优先，其次 PATH 上的 `java`。
  static String? _resolveSystemJavaExecutable() {
    final home = Platform.environment['JAVA_HOME'];
    if (home != null && home.isNotEmpty) {
      final candidate =
          File('$home/bin/java${Platform.isWindows ? '.exe' : ''}');
      if (candidate.existsSync()) return candidate.path;
    }
    final which = Process.runSync(
      Platform.isWindows ? 'where' : 'which',
      <String>['java'],
    );
    if (which.exitCode == 0) {
      final first = which.stdout.toString().trim().split('\n').first.trim();
      if (first.isNotEmpty) return first;
    }
    return null;
  }

  /// `java -version`（JDK 把版本行写 stderr）→ 主版本号；失败返回 -1。
  ///
  /// 解析 `version "25.0.2"` / `version "1.8.0_392"` 两种形态：前者取 `25`，
  /// 后者（旧式 1.x）取 `x`。属宿主承载方式（无原版对应物）。
  static int probeSystemJavaMajor(String executable) {
    try {
      final result = Process.runSync(executable, const <String>['-version']);
      final text = '${result.stdout}\n${result.stderr}';
      final match = RegExp(r'version "(\d+)(?:\.(\d+))?').firstMatch(text);
      if (match == null) return -1;
      final first = int.tryParse(match.group(1)!) ?? -1;
      if (first == 1 && match.group(2) != null) {
        return int.tryParse(match.group(2)!) ?? -1;
      }
      return first;
    } catch (_) {
      return -1;
    }
  }
}
