// Android 进程内 JVM 承载（第三类自由设计「运行时宿主（JVM 托管）」的承载方式实现）。
//
//   与桌面的子进程承载（`dedicated_server_process.dart`）**并列**，共用
//   `dedicated_server_carrier.dart` 那条契约面；装配点在 `local_server_host.dart`。
//
//   为什么不是子进程：Android 没有系统 JVM，且 targetSdk >= 29 的进程**不能 `execve`
//   应用可写目录中的文件**（W^X）。故改走 native 动态加载：`dlopen` JRE 的 `.so` →
//   `JNI_CreateJavaVM` 在进程内建 VM → 调被托管 jar 主类 → 全程无子进程、无 `execve`
//   （真机实测 `JLI_Launch` 必然 execve 顶替进程映像，见 design.md D1）。
//   native 实现在 `android/app/src/main/cpp/`（许可登记见该目录 third_party/NOTICE.md）。
//
//   口径（均为判据，不自定义信号）：
//     · 就绪：只认原版就绪行，判据 `server/dedicated/DedicatedServer.java:246`
//       （`Done ({})! For help, type "help"`）——与桌面完全一致。
//     · 监听端口：判据 `DedicatedServer.java:210`（`Starting Minecraft server on {}:{}`）。
//     · 绑定失败：判据 `DedicatedServer.java:215`（`**** FAILED TO BIND TO PORT!`）。
//     · 停机：判据 `MinecraftServer.java:650`（`Stopping server`）——**不是**主类 `main`
//       的返回值（原版 `Main.main` 另起 Server thread 跑服务端后即返回，见 `Main.java:201-217`）。
//     · 启动失败：判据 `Main.java:227`（`Failed to start the minecraft server`）——
//       进程内拿不到子进程退出码，故用原版致命日志替代。
//     · `--nogui`：判据 `server/Main.java:72`。
//     · 日志**来源**不同于桌面：native 侧把 fd 1/2 重定向到实例日志文件，本类增量 tail 该
//       文件（design D4）；判定文本不变。
//     · 停止超时：进程内**不强杀**（无从单独终止该 JVM），转报告失败并保留日志与状态
//       （spec「进程内承载的生命周期释放口径」/「进程生命周期可控可观测」）。
//
//   ⚠ 被托管物（服务端本体）照旧是翻译债（openspec/progress.md）；此处豁免的只是承载方式。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart'
    show MethodChannel, MissingPluginException, PlatformException;
import 'package:mc_server/mc_server.dart';

import 'artifact_resolver.dart';
import 'dedicated_server_carrier.dart';
import 'instance_directory.dart';
import 'jar_manifest.dart';
import 'jre_release.dart';
import 'local_server_config.dart';

/// 承载层通道（与 Kotlin `JvmHostChannel.CHANNEL` 同名）。
const String _kChannelName = 'flutter_mc/jvm_host';

/// 通道薄封装：承载层的 native 能力 + JRE 解包。
class _JvmHostChannel {
  _JvmHostChannel._();
  static final _JvmHostChannel instance = _JvmHostChannel._();
  static const MethodChannel _channel = MethodChannel(_kChannelName);

  Future<T?> invoke<T>(String method, [Map<String, Object?>? args]) =>
      _channel.invokeMethod<T>(method, args);
}

/// arm64 JRE 产物安装器（构建期资产 → 应用私有目录）。
///
/// 口径：照桌面 jar 的同一套"缺产物→入口置灰 + 给出补齐途径"（spec「产物解析与缺失降级」
/// 「产物安装于应用私有目录」「JRE 产物按客户端锚点主版本提供」）。
/// 解包在 Android 侧完成（Kotlin `JvmHostChannel.unpackJre`，照参考实现
/// `RuntimeUtils.installJava` 的口径：先 universal 再 `bin-<arch>`，最后落 `version`）。
class AndroidJreInstaller {
  AndroidJreInstaller({required this.jreRoot});

  /// JRE 安装根（`<本地服务器根>/jre`）。
  final Directory jreRoot;

  /// 某主版本的 JRE 目录（`<jreRoot>/<major>`）。
  Directory jreDirFor(int major) => Directory('${jreRoot.path}/$major');

  /// 构建期资产目录（`android/app/src/main/assets/jre/<major>/`）。
  static String assetDirFor(int major) => 'jre/$major';

  /// 首期只带 arm64（design D2/D3）。
  static const String archSuffix = 'arm64';

  /// 确保该主版本的 JRE 已安装；未安装则从构建期资产解包。
  ///
  /// 缺资产时抛 [ArtifactMissingException]（含期望位置），由调用方走"入口置灰 + 报缺"。
  Future<void> ensureInstalled(int major) async {
    final dir = jreDirFor(major);
    if (_isInstalled(dir)) return;

    try {
      await _JvmHostChannel.instance.invoke<void>('unpackJre', <String, Object?>{
        'assetDir': assetDirFor(major),
        'targetDir': dir.path,
        'archSuffix': archSuffix,
      });
    } on PlatformException catch (e) {
      throw ArtifactMissingException(
        '缺少 arm64 的 Java $major 运行环境（${e.message}）。'
        '期望位置：${dir.path}，来源为构建期资产 ${assetDirFor(major)}/'
        '（universal.tar.xz + bin-$archSuffix.tar.xz，产物因许可原因不入库）。',
      );
    } on MissingPluginException catch (_) {
      throw ArtifactMissingException(
        '当前平台不支持进程内 JVM 承载：未注册通道 $_kChannelName。',
      );
    }

    if (!_isInstalled(dir)) {
      throw ArtifactMissingException(
        'Java $major 运行环境安装后仍不完整（缺 release 文件）。期望位置：${dir.path}。',
      );
    }
  }

  bool _isInstalled(Directory dir) =>
      File('${dir.path}/release').existsSync() &&
      File('${dir.path}/version').existsSync();
}

/// Android 进程内 JVM 承载。
///
/// 生命周期释放口径（spec「进程内承载的生命周期释放口径」）：
///   · 宿主应用进程终止 → 被托管服务端一并终止（同一进程），MUST NOT 残留孤儿进程；
///   · [reap] 因此是**空操作**——无从单独终止进程内的 JVM。
class AndroidEmbeddedJvmHost implements DedicatedServerCarrier {
  AndroidEmbeddedJvmHost({
    required this.config,
    required this.instanceDirectory,
    required this.jreRoot,
  });

  final LocalServerConfig config;
  final InstanceDirectory instanceDirectory;

  /// JRE 安装根（`<本地服务器根>/jre`）。
  final Directory jreRoot;

  // ── 与原版判据一一对应（前三项真身在 [DedicatedServerCarrier]，两块承载共用一份） ──
  /// 就绪行（判据 `DedicatedServer.java:246`）。
  static final RegExp readyLine = DedicatedServerCarrier.readyLine;
  /// 绑定失败标记（判据 `DedicatedServer.java:215`）。
  static const String bindFailedMarker = DedicatedServerCarrier.bindFailedMarker;
  /// 监听端口日志行（判据 `DedicatedServer.java:210`）。
  static final RegExp listeningLine = DedicatedServerCarrier.listeningLine;

  /// 停机标记（判据 `MinecraftServer.java:650`：`stopServer()` 首行的
  /// `LOGGER.info("Stopping server")`）。
  ///
  /// ⚠ 进程内承载**不能**用主类 `main` 的返回值判停：原版 `Main.main` 经
  /// `MinecraftServer.spin` **另起 "Server thread" 线程**跑 `runServer()`（判据
  /// `Main.java:201-217` / `MinecraftServer.java:307`）后即刻返回——`main` 返回 ≠ 服务端结束
  /// （真机实测：`main` 返回之后原版就绪行才打出来）。故停机只认这条原版停机行。
  ///
  /// 该串在源码里只此一处（`Stopping singleplayer server as player logged out` 不含此子串）。
  static final RegExp shutdownMarker = RegExp(r'Stopping server');

  /// 启动失败标记（判据 `Main.java:227`：`Failed to start the minecraft server`，
  /// 前面带 `LogUtils.FATAL_MARKER`）。进程内拿不到"进程退出码"，故用这条原版致命日志
  /// 作为启动失败判据（桌面承载用子进程退出码）。
  static const String fatalStartMarker = 'Failed to start the minecraft server';

  ServerState _state = ServerState.stopped;
  int? _exitCode;
  bool _bindFailed = false;
  int? _actualPort;

  final List<String> _recent = <String>[];
  static const int _maxRecentLines = 500;

  final StreamController<ServerState> _stateController =
      StreamController<ServerState>.broadcast();
  final StreamController<String> _logController =
      StreamController<String>.broadcast();
  final Completer<int> _exitCompleter = Completer<int>();

  Timer? _tailTimer;
  int _logOffset = 0;
  String _pending = '';

  @override
  ServerState get state => _state;
  @override
  int? get exitCode => _exitCode;
  @override
  bool get bindFailed => _bindFailed;
  @override
  bool get isRunning =>
      _state == ServerState.starting || _state == ServerState.ready;
  @override
  List<String> get recentLogs => List<String>.unmodifiable(_recent);
  @override
  int? get listeningPort => _actualPort;
  @override
  Stream<ServerState> get stateChanges => _stateController.stream;
  @override
  Stream<String> get logLines => _logController.stream;

  @override
  Future<void> start(
    ServerArtifacts artifacts, {
    /// 诊断用：仅由取证入口（`/jvm-selftest`）传入。为 true 时只创建进程内 JVM
    /// （`JNI_CreateJavaVM`）并读 `java.version`，**不调用主类**——用于验证"不经 launcher 建 VM"这条路线。
    bool diagnosticCreateVmOnly = false,
  }) async {
    if (_state == ServerState.starting || _state == ServerState.ready) return;
    _state = ServerState.starting;
    _exitCode = null;
    _bindFailed = false;
    _actualPort = null;
    _emitState();

    // 0) 载体可用性：逃逸命名空间不可用即**显式报错**，不静默降级（spec「不依赖 execve」）。
    final nsReady = await _JvmHostChannel.instance
        .invoke<bool>('escapeNamespaceReady') ??
        false;
    if (!nsReady) {
      _state = ServerState.failed;
      _emitState();
      throw StateError(
        '载体不可用：linker 命名空间绕行未成功（该设备 linker 私有 API 不可用）。'
        '详见 logcat 的 mc_jvm_host 输出。',
      );
    }

    // 1) JRE 路径口径（照 FCLauncher.getJavaLibDir / getJvmLibDir / getLibraryPath）。
    final installer = AndroidJreInstaller(jreRoot: jreRoot);
    final jreDir = installer.jreDirFor(config.javaMajor);
    final arch = JreRelease.osArch(jreDir);
    if (arch == null || arch.isEmpty) {
      _state = ServerState.failed;
      _emitState();
      throw StateError('无法从 ${jreDir.path}/release 读出 OS_ARCH，JRE 不可用。');
    }
    final jrePath = jreDir.path;
    // `lib/<arch>` 只在**存在**时才用，否则落 `lib`——口径照参考实现
    // `FCLauncher.getJavaLibDir`（`FCLauncher.java:100-105`）的"逐个候选目录存在性判定"。
    // 实测该 arm64 产物是**扁平 `lib/`** 布局（`libjli.so`、`server/libjvm.so` 直接在 `lib/` 下），
    // 并无 `lib/aarch64`；盲目用 `lib/<arch>` 会让 LD_LIBRARY_PATH 指到不存在的目录。
    final archDir = Directory('$jrePath/lib/$arch');
    final javaLibDir = archDir.existsSync() ? archDir.path : '$jrePath/lib';
    final jliDir = File('$javaLibDir/jli/libjli.so').existsSync()
        ? '$javaLibDir/jli'
        : javaLibDir;
    final jvmSub =
        File('$javaLibDir/server/libjvm.so').existsSync() ? 'server' : 'client';
    final jvmLibDir = '$javaLibDir/$jvmSub';
    // 应用 native 库目录 MUST 进 LD_LIBRARY_PATH：JRE 的库依赖 `libc++_shared.so`，
    // 实测 `libnet.so`/`libnio.so`/`libzip.so` 等因找不到它而装载失败，进而 JVM 起不来
    // （真机日志：`libnio.so: dlopen failed: library "libnet.so" not found ... classloader-namespace`）。
    // 口径照参考实现 `FCLauncher.appendCommonPaths`（`FCLauncher.java:146-174`）末尾追加 nativeLibraryDir。
    final nativeLibDir = await _JvmHostChannel.instance
            .invoke<String>('nativeLibraryDir') ??
        '';
    final libraryPath = '$javaLibDir:$jliDir:$jvmLibDir:'
        '/system/lib64:/vendor/lib64:/vendor/lib64/hw:$nativeLibDir';

    // 2) 环境（口径照参考实现 FCLauncher.addCommonEnv）。
    await _setEnv('HOME', instanceDirectory.dir.path);
    await _setEnv('JAVA_HOME', jrePath);
    await _setEnv('PATH', '$jrePath/bin:/system/bin');
    await _setEnv('LD_LIBRARY_PATH', libraryPath);
    final cacheDir = Directory('${jreRoot.path}/tmp')..createSync(recursive: true);
    await _setEnv('TMPDIR', cacheDir.path);
    await _setEnv('TMP', cacheDir.path);

    // 3) stdout/stderr 重定向到实例日志文件（design D4：日志**来源**变化，判定文本不变）。
    Directory('${instanceDirectory.dir.path}/logs').createSync(recursive: true);
    final logFile = File('${instanceDirectory.dir.path}/logs/host-console.log');
    // 每次起服写一条分界（日志是追加写，不分界就看不出哪段属于哪次启动）。
    try {
      logFile.writeAsStringSync(
        '==== 承载启动 ${DateTime.now().toIso8601String()} ====\n',
        mode: FileMode.append,
      );
    } catch (_) {}
    final rc = await _JvmHostChannel.instance
            .invoke<int>('redirectStdio', <String, Object?>{'path': logFile.path}) ??
        -1;
    if (rc != 0) {
      _state = ServerState.failed;
      _emitState();
      throw StateError('重定向 stdio 失败（错误码 $rc）。');
    }

    // 4) dlopen 链（口径照参考实现 FCLauncher.setUpJavaRuntime）。
    await _dlopen('$jliDir/libjli.so');
    await _dlopen('$jvmLibDir/libjvm.so');
    for (final so in _allSoFiles(jreDir)) {
      await _dlopen(so);
    }

    // 5) 更新 linker 的 LD_LIBRARY_PATH（JRE 内部 NEEDED 解析；照 FCLauncher.launch）。
    await _JvmHostChannel.instance
        .invoke<void>('setLdLibraryPath', <String, Object?>{'path': libraryPath});

    // 6) 切工作目录（原版服务端的工作目录即它的 "."）。
    await _JvmHostChannel.instance
        .invoke<int>('chdir', <String, Object?>{'path': instanceDirectory.dir.path});

    // 7) 日志增量 tail（在被托管 JVM 输出之前就开始）。
    //
    //    ⚠ 日志文件是**追加写**、跨多次起服共用（与桌面承载同口径），故读取起点 MUST 落在
    //    **本次起服的分界行之后**——否则会把上一次运行的输出当成本次的，其中若含原版停机行
    //    （`MinecraftServer.java:650`）就会**一上来就误判"已停止"**（真机已踩到）。
    _logOffset = logFile.existsSync() ? logFile.lengthSync() : 0;
    _pending = '';
    _tailTimer = Timer.periodic(
        const Duration(milliseconds: 250), (_) => _drainLog(logFile));

    // 7.5) 保活：起服即起前台服务（spec「长期运行以前台服务保活」的第一个场景：
    //      退到后台不断线）。停服在 [_onExit] 里撤销，不留空转服务（第二个场景）。
    await _JvmHostChannel.instance.invoke<void>('startKeepAlive');

    // 8) 创建进程内 JVM：`JNI_CreateJavaVM`（**不 exec**）。
    //
    // 为什么不用 `JLI_Launch`：真机实测它必然 `execve(<jre>/bin/java)` 把整个应用进程映像顶替
    // （atexit 探针不触发、crash 缓冲区为空、events 里无 am_kill），与"进程内承载"对立。
    // VM 选项口径照真 `java` 启动器：classpath / java.home / library.path / 堆参数，
    // 另加 `--enable-native-access=ALL-UNNAMED`（被托管 jar 的 MANIFEST 要求，见其 `Enable-Native-Access`）。
    final vmOptions = <String>[
      '-Djava.home=$jrePath',
      '-Djava.library.path=$javaLibDir',
      '-Djava.class.path=${artifacts.jar.path}',
      '-Duser.home=${instanceDirectory.dir.path}',
      '-Djava.io.tmpdir=${cacheDir.path}',
      ...config.jvmArgs,
      '--enable-native-access=ALL-UNNAMED',
      // ⚠ 宿主侧的**故意偏离**（有判据、已登记 progress.md 16.3）：
      //   被托管服务端（Paper）启动时会检查 `java.version` 并要求"GA 版本"，非 GA 即拒绝启动
      //   （判据：`org/bukkit/craftbukkit/Main.class` 读取 `java.version`，文案
      //    "Unsupported Java detected (...)"）。而 Android 上不存在 GA 版 OpenJDK——
      //   arm64 JRE 皆自行构建，VM 自报 `25.0.5-internal`。
      //   处置：用**被托管物自己提供的官方开关** `Paper.IgnoreJavaVersion`（同一判据文件里，
      //   配套文案 "but the check was skipped. Proceed with caution!"），而不是伪造 `java.version`
      //   （实测 `-Djava.version=` 被 HotSpot 忽略：该属性是 VM 内建只读属性）。
      '-DPaper.IgnoreJavaVersion=true',
    ];
    final createRc = await _JvmHostChannel.instance
            .invoke<int>('createJvm', <String, Object?>{'options': vmOptions}) ??
        -1;
    if (createRc != 0) {
      _state = ServerState.failed;
      _emitState();
      throw StateError('创建进程内 JVM 失败（JNI_CreateJavaVM 返回码 $createRc）。');
    }
    if (diagnosticCreateVmOnly) {
      // 只建 VM 的判别实验：java.version 已由 native 侧打到实例日志（stdout 已重定向）。
      _exitCode = 0;
      return;
    }

    // 9) 调用被托管 jar 的主类——主类**从 jar 自身的 `META-INF/MANIFEST.MF` 读**
    //    （真 `java -jar` 亦然：JDK 启动器经 `JarFile.getManifest()` 取主清单的
    //    `Main-Class`，语义见 `jar_manifest.dart`）。读不到 ⇒ 显式失败，等价于
    //    `java -jar` 的 "no main manifest attribute"（它随即以退出码 1 终止；
    //    进程内无 OS 退出码，等价处置为报错并置 failed）。
    //
    //    ⚠ **不等待也不据此判停**：原版 `Main.main` 经 `MinecraftServer.spin` 另起
    //    "Server thread" 跑 `runServer()` 后即刻返回（判据 `Main.java:201-217`），而服务端
    //    是**同一 JVM 里**那条线程在跑——`main` 返回 ≠ 服务端结束（真机实测：`main` 返回
    //    之后原版就绪行才打出来）。故此处 unawaited：只记它的返回值，状态全由原版日志行驱动
    //    （就绪 `DedicatedServer.java:246` / 停机 `MinecraftServer.java:650`）。
    final String? mainClass = JarManifest.readMainClassSync(artifacts.jar);
    if (mainClass == null) {
      _state = ServerState.failed;
      _emitState();
      throw StateError(
        '被托管 jar 缺少 Main-Class（${artifacts.jar.path} 的 META-INF/MANIFEST.MF）'
        '——与 java -jar 的 "no main manifest attribute" 等价，拒绝启动。',
      );
    }
    _note('主类（取自 jar 清单 META-INF/MANIFEST.MF）：$mainClass');
    unawaited(_JvmHostChannel.instance
        .invoke<int>('runMain', <String, Object?>{
          'className': mainClass,
          'args': <String>['--nogui'], // 判据 server/Main.java:72
        })
        .then((code) {
      _note('主类 $mainClass.main 返回（退出码 $code）——不据此判停，'
          '服务端仍在同一 JVM 的 Server thread 上运行，等待原版停机行');
    }).catchError((Object e) {
      _note('调用主类失败：$e');
    }));
    return; // start() 至此返回；就绪/停止由日志行异步驱动（与桌面承载同口径）
  }

  Future<void> _setEnv(String name, String value) => _JvmHostChannel.instance
      .invoke<void>('setEnv', <String, Object?>{'name': name, 'value': value});

  Future<void> _dlopen(String path) => _JvmHostChannel.instance
      .invoke<int>('dlopen', <String, Object?>{'path': path})
      .then((_) {});

  /// JRE 目录下全部 `.so`（照参考实现 `FCLauncher.locateLibs` 递归口径）。
  ///
  /// 目的：把 JRE 内部库预加载进进程，避免运行期 NEEDED 解析不到。
  /// 个别库（如 AWT/X11 相关）在 headless 服务端下加载失败属正常，native 侧只记日志不中断。
  static List<String> _allSoFiles(Directory jreDir) {
    final out = <String>[];
    if (!jreDir.existsSync()) return out;
    for (final entity in jreDir.listSync(recursive: true, followLinks: false)) {
      if (entity is File && entity.path.endsWith('.so')) out.add(entity.path);
    }
    return out;
  }

  /// 增量读取日志文件并按行派发（就绪行 / 端口行 / 绑定失败均在此识别）。
  void _drainLog(File logFile) {
    if (!logFile.existsSync()) return;
    final length = logFile.lengthSync();
    if (length < _logOffset) _logOffset = 0; // 被截断/重建
    if (length == _logOffset) return;

    final raf = logFile.openSync();
    try {
      raf.setPositionSync(_logOffset);
      final bytes = raf.readSync(length - _logOffset);
      _logOffset = length;
      _pending += utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return;
    } finally {
      raf.closeSync();
    }

    final lines = _pending.split('\n');
    _pending = lines.removeLast(); // 末段可能是半行
    for (final line in lines) {
      final trimmed = line.endsWith('\r') ? line.substring(0, line.length - 1) : line;
      _onLine(trimmed);
    }
  }

  void _onLine(String line) {
    _recent.add(line);
    if (_recent.length > _maxRecentLines) {
      _recent.removeRange(0, _recent.length - _maxRecentLines);
    }
    if (!_logController.isClosed) _logController.add(line);

    if (!_bindFailed && line.contains(bindFailedMarker)) {
      _bindFailed = true; // DedicatedServer.java:215
      _emitState();
    }
    final listening = listeningLine.firstMatch(line);
    if (listening != null) {
      _actualPort = int.tryParse(listening.group(1)!);
      _emitState();
    }
    if (_state == ServerState.starting && readyLine.hasMatch(line)) {
      _state = ServerState.ready; // 只认原版就绪行（DedicatedServer.java:246）
      _emitState();
    }
    // 启动失败：原版致命日志（Main.java:227）。放在就绪判定之后——正常路径不会出现它。
    if (_state == ServerState.starting && line.contains(fatalStartMarker)) {
      _onFailed(-1);
      return;
    }
    // 停机：原版停机行（MinecraftServer.java:650）。**取代**"main 返回值"判停。
    if (shutdownMarker.hasMatch(line) &&
        _state != ServerState.stopped &&
        _state != ServerState.failed) {
      _onStopped();
    }
  }

  /// 向日志流补一条**宿主侧**说明（非原版输出，用于解释判据来源）。
  void _note(String text) {
    _recent.add('# $text');
    if (_recent.length > _maxRecentLines) {
      _recent.removeRange(0, _recent.length - _maxRecentLines);
    }
    if (!_logController.isClosed) _logController.add('# $text');
    debugPrint('[AndroidEmbeddedJvmHost] $text');
  }

  /// 收尾公共部分：停 tail、撤保活。
  void _finishTail() {
    _tailTimer?.cancel();
    _tailTimer = null;
    unawaited(_JvmHostChannel.instance.invoke<void>('stopKeepAlive'));
  }

  /// 服务端已停（判据为原版停机行，见 [shutdownMarker]）。
  ///
  /// 进程内**拿不到真实退出码**（JVM 随宿主进程存亡，不会退出），故优雅停机的等价回传值
  /// 取 0；这条差异已登记 `openspec/progress.md` 16.3。
  void _onStopped() {
    _finishTail();
    _exitCode = 0;
    _state = ServerState.stopped;
    _emitState();
    if (!_exitCompleter.isCompleted) _exitCompleter.complete(0);
  }

  /// 启动失败（原版致命日志触发）：转 [ServerState.failed] 并回传非 0，日志保留。
  void _onFailed(int code) {
    _finishTail();
    _exitCode = code;
    _state = ServerState.failed;
    _emitState();
    if (!_exitCompleter.isCompleted) _exitCompleter.complete(code);
  }

  /// 优雅停止：经原版 RCON 下发 `stop` → 等待退出。
  ///
  /// **超时不上强杀**（进程内无从单独终止该 JVM）：转报告失败并保留日志与状态
  /// （spec「进程生命周期可控可观测」的进程内分支 / 「进程内承载的生命周期释放口径」）。
  @override
  Future<void> stop() async {
    if (!isRunning) return;
    _state = ServerState.stopping;
    _emitState();

    await _sendStopViaRcon();

    var exited = true;
    try {
      await _exitCompleter.future
          .timeout(Duration(seconds: config.stopTimeoutSeconds));
    } on TimeoutException {
      exited = false;
    }
    if (!exited) {
      _state = ServerState.failed;
      _emitState();
    }
  }

  /// 经原版 RCON 通道下发 `stop`（与桌面同源；口令/端口取自实例 `server.properties`，
  /// 翻译件 `DedicatedServerProperties`，判据 `DedicatedServerProperties.java:85-86`）。
  Future<bool> _sendStopViaRcon() async {
    try {
      final props = DedicatedServerProperties(
          Settings.loadFromFile(instanceDirectory.serverProperties.path));
      if (!props.enableRcon || props.rconPassword.isEmpty) return false;
      final client = await RconClient.connect('127.0.0.1', props.rconPort,
          timeout: const Duration(seconds: 3));
      try {
        final ok = await client.authenticate(props.rconPassword);
        if (!ok) return false;
        await client.execCommand('stop');
        return true;
      } finally {
        await client.close();
      }
    } catch (_) {
      return false; // 未就绪/通道不可用：退回"等待"路径（不强杀）
    }
  }

  /// 进程内承载下为**空操作**：服务端与宿主同进程，宿主终止即服务端终止，
  /// 「MUST NOT 残留孤儿进程」自然成立（spec「进程内承载的生命周期释放口径」）。
  @override
  void reap() {}

  void _emitState() {
    if (!_stateController.isClosed) _stateController.add(_state);
  }

  @override
  Future<void> dispose() async {
    _tailTimer?.cancel();
    _tailTimer = null;
    await _stateController.close();
    await _logController.close();
  }
}
