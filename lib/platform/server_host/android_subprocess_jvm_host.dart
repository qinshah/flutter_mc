// Android 专用子进程承载（第三类自由设计「运行时宿主（JVM 托管）」的承载方式实现）。
//
//   与桌面的子进程承载（`dedicated_server_process.dart`）**并列**，共用
//   `dedicated_server_carrier.dart` 那条契约面；装配点在 `local_server_host.dart`。
//
//   承载范式（change `android-subprocess-jvm-host`）：被托管 JVM 装在应用专用 `:jvm`
//   **子进程**里（`JvmHostService`，manifest `android:process=":jvm"`），一次会话一个
//   子进程、会话结束即自杀——每会话全新 VM，绕开 JNI"一进程一台 VM"对二次起服的限制
//   （旧"宿主进程内承载"已删除，真机 bug：第二次启动静默夭折）。
//
//   口径（均为判据，与桌面完全一致）：
//     · 就绪：只认原版就绪行，判据 `server/dedicated/DedicatedServer.java:246`；
//     · 监听端口：判据 `DedicatedServer.java:210`；绑定失败：判据 `DedicatedServer.java:215`；
//     · 停机：判据 `MinecraftServer.java:650`（`Stopping server`）——停机行出现后子进程
//       哨兵留存盘窗口再自杀，状态转 stopped 以 **pidFile 消失**（子进程退净）为准；
//     · 启动失败：判据 `Main.java:227`（`Failed to start the minecraft server`）；
//     · 退出码：**真实 OS 退出码**——子进程经结果文件回传 `mainExitCode`（撤销旧进程内
//       承载"回传 0"的退化，spec「退出码可观测」）；强杀回落取 137（128+SIGKILL）。
//     · `--nogui`：判据 `server/Main.java:72`。
//
//   通道四件套（design D2）：Intent extras（启动参数）/ pidFile（判活与判死）/ 日志文件
//   （增量 tail）/ RCON（控制面，与桌面同源）。
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

/// 通道薄封装：承载层的平台能力（起停 `:jvm` 子进程、强杀、nativeLibraryDir）。
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

  /// 首期只带 arm64（design D2/D3，归档 change）。
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

/// Android 专用子进程承载（`:jvm`）。
///
/// 生命周期释放口径（spec「专用子进程承载的生命周期释放口径」）：
///   · 宿主终止 → force stop 全杀 + 子进程心跳 watchdog 兜底自杀；
///   · 停止超时 → `nativeKill` 强杀回落（与桌面子进程承载同构）；
///   · 二次起服 → 全新子进程全新 VM，上一会话残留经 pidFile 检出（spec「二次起服」
///     「上一会话残留可检出」）。
class AndroidSubprocessJvmHost implements DedicatedServerCarrier {
  AndroidSubprocessJvmHost({
    required this.config,
    required this.instanceDirectory,
    required this.jreRoot,
  });

  final LocalServerConfig config;
  final InstanceDirectory instanceDirectory;

  /// JRE 安装根（`<本地服务器根>/jre`）。
  final Directory jreRoot;

  // ── 与原版判据一一对应（真身在 [DedicatedServerCarrier]，两块承载共用一份） ──
  /// 就绪行（判据 `DedicatedServer.java:246`）。
  static final RegExp readyLine = DedicatedServerCarrier.readyLine;
  /// 绑定失败标记（判据 `DedicatedServer.java:215`）。
  static const String bindFailedMarker = DedicatedServerCarrier.bindFailedMarker;
  /// 监听端口日志行（判据 `DedicatedServer.java:210`）。
  static final RegExp listeningLine = DedicatedServerCarrier.listeningLine;

  /// 停机标记（判据 `MinecraftServer.java:650`）。子进程哨兵据此自杀；本侧据此转
  /// "等子进程退净"。
  static final RegExp shutdownMarker = RegExp(r'Stopping server');

  /// 启动失败标记（判据 `Main.java:227`，前面带 `LogUtils.FATAL_MARKER`）。
  static const String fatalStartMarker = 'Failed to start the minecraft server';

  ServerState _state = ServerState.stopped;
  int? _exitCode;
  bool _bindFailed = false;
  int? _actualPort;
  /// 本会话是否见过原版停机行（判据 `MinecraftServer.java:650`）——**优雅与否由
  /// 本侧对原版日志的观察判定**（与「就绪判定以原版输出为准」同一哲学），不信
  /// 子进程快照（.tmp 在 main 返回时写，早于停机行，快照恒 false，实测踩过）。
  bool _stopLineSeen = false;

  final List<String> _recent = <String>[];
  static const int _maxRecentLines = 500;

  final StreamController<ServerState> _stateController =
      StreamController<ServerState>.broadcast();
  final StreamController<String> _logController =
      StreamController<String>.broadcast();

  Timer? _tailTimer;
  Timer? _heartbeatTimer;
  Timer? _exitWaitTimer;
  int? _childPid; // 子进程上报的 pid（pidFile 首次出现时读取）
  int _logOffset = 0;
  String _pending = '';

  late final File _pidFile =
      File('${jreRoot.parent.path}/sandbox.pid');
  late final File _heartbeatFile =
      File('${jreRoot.parent.path}/sandbox-heartbeat');
  /// 子进程自写的心跳（每 5s touch）：**残留检查**只认它——parent 心跳反映主进程
  /// 活性（force-stop 前几秒仍在写，不能证明 child 存活）。
  late final File _childHeartbeatFile =
      File('${jreRoot.parent.path}/sandbox-child-heartbeat');
  late final File _resultFile =
      File('${jreRoot.parent.path}/sandbox-result.txt');

  /// 本会话日志文件：**每会话一个**（`host-console-<时间戳>.log`，与原版按次滚动的
  /// latest.log 机制一致）。为什么不用共享追加文件：子进程的 stdout 存在用户态缓冲、
  /// exit 时才 flush——跨会话共用一个文件会让上一会话的停机行落在本会话分界之后
  /// （落盘顺序与真实时序错位），下一会话 tail 读到即秒判停（实测踩过）。
  late File _logFile;

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
  Future<void> start(ServerArtifacts artifacts) async {
    if (_state == ServerState.starting || _state == ServerState.ready) return;
    _state = ServerState.starting;
    _exitCode = null;
    _bindFailed = false;
    _actualPort = null;
    _stopLineSeen = false;
    _emitState();

    // 0) 上一会话残留检查（spec「上一会话残留可检出」）：pidFile 存在 ⇒ 上一子进程
    //    未退净。心跳文件超过 watchdog 超时未更新 ⇒ 那是死会话的磁盘残留（如上一次
    //    app 会话被 force-stop，子进程来不及自删），清掉即可；心跳仍新鲜 ⇒ 子进程
    //    可能活着，拒绝在旧进程上重入承载逻辑。
    if (_pidFile.existsSync()) {
      final childHeartbeatAge = _fileAge(_childHeartbeatFile);
      if (childHeartbeatAge == null || childHeartbeatAge > const Duration(seconds: 30)) {
        _note('检出上一会话 pidFile 残留（child 心跳已停 ${childHeartbeatAge ?? "∞"}），按死会话清理');
        _pidFile.deleteSync();
      } else {
        _state = ServerState.failed;
        _emitState();
        throw StateError('上一承载子进程未退净（pid=${_pidFile.readAsStringSync().trim()}，'
            'child 心跳 ${childHeartbeatAge.inSeconds}s 前仍更新）。请等待其退出或重启应用。');
      }
    }

    // 0.5) 本会话日志文件（每会话一个，杜绝跨会话串扰，见 _logFile 注释）——
    //      MUST 在 computeServiceParams（需要 logPath）之前创建。
    Directory('${instanceDirectory.dir.path}/logs').createSync(recursive: true);
    _logFile = File('${instanceDirectory.dir.path}/logs/'
        'host-console-${DateTime.now().millisecondsSinceEpoch}.log');
    _logFile.writeAsStringSync(
      '==== 承载启动（子进程）${DateTime.now().toIso8601String()} ====\n',
      mode: FileMode.append,
    );
    _logOffset = _logFile.lengthSync();
    _pending = '';
    _childPid = null;

    // 1) 产物安装 + 承载参数（JRE 路径推导照 FCLauncher 口径，见 computeServiceParams）。
    final installer = AndroidJreInstaller(jreRoot: jreRoot);
    await installer.ensureInstalled(config.javaMajor);
    final params = await computeServiceParams(artifacts);

    // 上一会话的结果文件（含 .tmp 基础行）是陈旧数据，清掉（本会话退出码只认本会话）。
    if (_resultFile.existsSync()) _resultFile.deleteSync();
    final baseTmp = File('${_resultFile.path}.tmp');
    if (baseTmp.existsSync()) baseTmp.deleteSync();
    _tailTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      _watchChildDeath(); // 死亡监视独立于日志增量（子进程死亡时不一定有新日志）
      _drainLog(_logFile);
    });

    // 3) 心跳（design D4）：主进程周期性 touch，子进程 watchdog 超时自杀兜底孤儿。
    _heartbeatFile.parent.createSync(recursive: true);
    _touchHeartbeat();
    _heartbeatTimer = Timer.periodic(
        const Duration(seconds: 5), (_) => _touchHeartbeat());

    // 4) 起 `:jvm` 承载子进程（阻塞耗时操作在子进程内完成，本调用立即返回）。
    await _JvmHostChannel.instance.invoke<void>('startJvmService',
        <String, Object?>{'params': params});
    _note('承载子进程已启动，等待 pidFile 与原版日志行');
    return; // 就绪/停止由日志行 + pidFile 异步驱动（与桌面承载同口径）
  }

  /// 计算传给 `JvmHostService` 的承载参数（路径推导照 FCLauncher 口径；
  /// 主类取自 jar 自身的 `META-INF/MANIFEST.MF`——真 `java -jar` 亦然）。
  Future<Map<String, Object>> computeServiceParams(ServerArtifacts artifacts) async {
    final jrePath = Directory('${jreRoot.path}/${config.javaMajor}').path;
    final arch = JreRelease.osArch(Directory(jrePath));
    if (arch == null || arch.isEmpty) {
      throw StateError('无法从 $jrePath/release 读出 OS_ARCH，JRE 不可用。');
    }
    final archDir = Directory('$jrePath/lib/$arch');
    final javaLibDir = archDir.existsSync() ? archDir.path : '$jrePath/lib';
    final jliDir = File('$javaLibDir/jli/libjli.so').existsSync()
        ? '$javaLibDir/jli'
        : javaLibDir;
    final jvmSub =
        File('$javaLibDir/server/libjvm.so').existsSync() ? 'server' : 'client';
    final jvmLibDir = '$javaLibDir/$jvmSub';
    final workDir = instanceDirectory.dir.path;
    final cacheDir = Directory('${jreRoot.path}/tmp')..createSync(recursive: true);
    final mainClass = JarManifest.readMainClassSync(artifacts.jar);
    if (mainClass == null) {
      throw ArtifactMissingException(
        '被托管 jar 缺少 Main-Class（${artifacts.jar.path} 的 META-INF/MANIFEST.MF）'
        '——与 java -jar 的 "no main manifest attribute" 等价，拒绝启动。',
      );
    }
    return <String, Object>{
      'workDir': workDir,
      'logPath': _logFile.path,
      'pidFile': _pidFile.path,
      'heartbeatPath': _heartbeatFile.path,
      'childHeartbeatPath': _childHeartbeatFile.path,
      'resultPath': _resultFile.path,
      'jrePath': jrePath,
      'pathEnv': '$jrePath/bin:/system/bin',
      'ldLibraryPath': '$javaLibDir:$jliDir:$jvmLibDir:'
          '/system/lib64:/vendor/lib64:/vendor/lib64/hw:${await _nativeLibraryDir()}',
      'tmpDir': cacheDir.path,
      'jliLib': '$jliDir/libjli.so',
      'jvmLib': '$jvmLibDir/libjvm.so',
      'mainClass': mainClass,
      'mainArgs': <String>['--nogui'], // 判据 server/Main.java:72
      'vmOptions': <String>[
        '-Djava.home=$jrePath',
        '-Djava.library.path=$javaLibDir',
        '-Djava.class.path=${artifacts.jar.path}',
        '-Duser.home=$workDir',
        '-Djava.io.tmpdir=${cacheDir.path}',
        ...config.jvmArgs,
        '--enable-native-access=ALL-UNNAMED',
        '-DPaper.IgnoreJavaVersion=true',
      ],
    };
  }

  /// 应用 native 库目录（JRE 部分库依赖 `libc++_shared.so`；取不到留空——单测环境无通道）。
  Future<String> _nativeLibraryDir() async {
    try {
      return await _JvmHostChannel.instance
              .invoke<String>('nativeLibraryDir') ??
          '';
    } catch (_) {
      return '';
    }
  }

  void _touchHeartbeat() {
    try {
      _heartbeatFile.writeAsStringSync(DateTime.now().toIso8601String());
    } catch (_) {}
  }

  /// 文件年龄；不存在返回 null（视为陈旧）。
  Duration? _fileAge(File f) {
    try {
      return DateTime.now().difference(f.statSync().modified);
    } catch (_) {
      return null;
    }
  }

  /// 子进程退净判定（三条件任一即成立；design D3/D5）：
  ///   · pidFile 消失（哨兵兜底路径自删）；
  ///   · 结果文件出现（**正常路径**：被托管 JVM 收尾后自行 System.exit，其 shutdown hook
  ///     在 exit 前写结果——哨兵的"删 pidFile"跑不过它，实测踩过）；
  ///   · child 心跳陈旧 >12s（心跳 5s 间隔；SIGKILL/MIUI 回收等来不及收尾的死亡）。
  bool _childGoneDetected() {
    if (!_pidFile.existsSync()) return true;
    if (_resultFile.existsSync()) return true;
    final age = _fileAge(_childHeartbeatFile);
    return age == null || age > const Duration(seconds: 12);
  }

  /// 增量读取日志文件并按行派发（就绪行 / 端口行 / 绑定失败 / 停机行 / 启动失败）。
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
      raf.close();
    }

    final lines = _pending.split('\n');
    _pending = lines.removeLast(); // 末段可能是半行
    for (final line in lines) {
      final trimmed = line.endsWith('\r') ? line.substring(0, line.length - 1) : line;
      _onLine(trimmed);
    }
  }

  /// 死亡监视（spec「崩溃可观测」）：子进程退净（结果文件出现 / pidFile 消失 / 心跳停）
  /// 且没有停机行驱动的收尾流程在跑 ⇒ 子进程异常死亡（启动失败后 `System.exit` / crash
  /// ——exit 拦截在子进程侧已关闭）⇒ 读结果文件转 failed，MUST NOT 卡在 starting/ready。
  void _watchChildDeath() {
    if (_childPid == null) {
      try {
        if (_pidFile.existsSync()) {
          _childPid = int.tryParse(_pidFile.readAsStringSync().trim());
        }
      } catch (_) {}
      return;
    }
    if (_exitWaitTimer != null) return; // 停机收尾流程在跑，由它负责
    if (_state != ServerState.starting && _state != ServerState.ready) return;
    if (!_childGoneDetected()) return;
    _note('承载子进程 pid=$_childPid 在无停机行的情况下消失（异常死亡）');
    _onChildGone(killedByUs: false);
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
    // 启动失败：原版致命日志（Main.java:227）→ 转 failed 并回收子进程。
    if (_state == ServerState.starting && line.contains(fatalStartMarker)) {
      _onFatal();
      return;
    }
    // 停机：原版停机行（MinecraftServer.java:650）→ 等子进程退净（哨兵留存盘窗口）。
    // ⚠ 标记在任何状态下都要记（stop() 会先把 state 置 stopping——此时停机行才到达，
    // 若仅在 ready 下记录会漏记，实测踩过）；状态迁移只在 ready 时做。
    if (shutdownMarker.hasMatch(line)) {
      _stopLineSeen = true;
      if (_state == ServerState.ready && _exitWaitTimer == null) {
        _state = ServerState.stopping;
        _emitState();
        _awaitChildExit();
      }
    }
  }

  /// 轮询子进程退净（三条件判定，见 [_childGoneDetected]）→ 读结果文件收尾。
  void _awaitChildExit() {
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    _exitWaitTimer = Timer.periodic(const Duration(milliseconds: 250), (t) {
      if (_childGoneDetected()) {
        t.cancel();
        _exitWaitTimer = null;
        _onChildGone(killedByUs: false);
        return;
      }
      if (DateTime.now().isAfter(deadline)) {
        t.cancel();
        _exitWaitTimer = null;
        // 未退净（哨兵失效）→ 强杀回落（spec「提供强制终止」），不走 stop() 的超时路径。
        _forceKillChild();
      }
    });
  }

  /// 收尾公共部分：停 tail、停心跳。
  void _finishTimers() {
    _tailTimer?.cancel();
    _tailTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// 子进程已退净 → 读结果文件取真实退出码（design D5）。
  ///
  /// 退出码口径：结果文件 `mainExitCode` 优先（runMain 返回值）；无该行但
  /// `vmExited=true`（被托管 JVM 自己 System.exit）→ 停机行确认过 = 优雅（其
  /// `abnormalExit ? 70 : 0` 约定，判据 DedicatedServer.onServerExit），未确认 = 70；
  /// 什么都没有 = 异常死亡（-1）；被我方强杀 = 137。
  void _onChildGone({required bool killedByUs}) {
    if (_state == ServerState.stopped) return; // stop() 与退出轮询双路触发，防重入
    _finishTimers();
    var exitCode = killedByUs ? 137 : -1; // 137 = 128+SIGKILL
    // 优雅与否 = 本侧是否见过原版停机行（判据 MinecraftServer.java:650）。
    final stopConfirmed = _stopLineSeen;
    try {
      if (_resultFile.existsSync()) {
        final text = _resultFile.readAsStringSync();
        // 退出码口径：exitStatus 优先（被托管 JVM 自己 System.exit(status) 的真实值，
        // native 拦截层写入；判据 DedicatedServer.onServerExit 的 `abnormalExit ? 70 : 0`），
        // 其次 mainExitCode（runMain 返回值），最后 vmExited 推导。
        final exitStatus = RegExp(r'exitStatus=(-?\d+)').firstMatch(text);
        final main = RegExp(r'mainExitCode=(-?\d+)').firstMatch(text);
        final vmExited = RegExp(r'vmExited=(\w+)').firstMatch(text);
        if (exitStatus != null) {
          exitCode = int.parse(exitStatus.group(1)!);
        } else if (main != null) {
          exitCode = int.parse(main.group(1)!);
        } else if (vmExited != null && vmExited.group(1) == 'true') {
          exitCode = stopConfirmed ? 0 : 70;
        }
      }
    } catch (_) {}
    _exitCode = exitCode;
    _state = stopConfirmed || killedByUs ? ServerState.stopped : ServerState.failed;
    _note('子进程已退净（exitCode=$_exitCode stopConfirmed=$stopConfirmed）');
    _emitState();
  }

  /// 启动失败（原版致命日志触发）：转 failed、回传非 0，并回收子进程（它不会再有停机行）。
  void _onFatal() {
    _state = ServerState.failed;
    _exitCode = -1;
    _emitState();
    _forceKillChild();
    _finishTimers();
  }

  /// 强杀子进程（`nativeKill`，design D6）并清理 pidFile（SIGKILL 下子进程不会自删）。
  void _forceKillChild() {
    var pid = 0;
    try {
      if (_pidFile.existsSync()) {
        pid = int.tryParse(_pidFile.readAsStringSync().trim()) ?? 0;
      }
    } catch (_) {}
    if (pid > 0) {
      try {
        _JvmHostChannel.instance.invoke<void>(
            'killPid', <String, Object?>{'pid': pid});
        _note('已对承载子进程 pid=$pid 强制终止');
      } catch (e) {
        _note('强制终止失败：$e');
      }
    }
    try {
      if (_pidFile.existsSync()) _pidFile.deleteSync();
    } catch (_) {}
  }

  /// 向日志流补一条**宿主侧**说明（非原版输出，用于解释判据来源）。
  void _note(String text) {
    _recent.add('# $text');
    if (_recent.length > _maxRecentLines) {
      _recent.removeRange(0, _recent.length - _maxRecentLines);
    }
    if (!_logController.isClosed) _logController.add('# $text');
    debugPrint('[AndroidSubprocessJvmHost] $text');
  }

  /// 优雅停止：经原版 RCON 下发 `stop` → 等子进程退净；超时回落强杀
  /// （spec「进程生命周期可控可观测」：所有承载均可强制终止）。
  @override
  Future<void> stop() async {
    if (!isRunning && _state != ServerState.stopping) return;
    _state = ServerState.stopping;
    _emitState();

    await _sendStopViaRcon();

    try {
      await _waitChildExit()
          .timeout(Duration(seconds: config.stopTimeoutSeconds));
    } on TimeoutException {
      // 超时回落强杀（design D6）：强杀后 pidFile 不会被子进程自删，由本侧清理。
      _forceKillChild();
      _finishTimers();
      _exitCode = 137;
      _state = ServerState.stopped;
      _emitState();
      _note('优雅停止超时，已强制终止承载子进程');
      return;
    }
    _onChildGone(killedByUs: false);
  }

  /// 等待子进程退净（三条件判定，见 [_childGoneDetected]）。
  Future<void> _waitChildExit() async {
    while (!_childGoneDetected()) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
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
      return false; // 未就绪/通道不可用：退回"等待"路径
    }
  }

  /// 回收承载子进程（应用退出/实例删除时调用，spec「MUST NOT 残留孤儿进程」）：
  /// pidFile 在 ⇒ 子进程可能仍活着 ⇒ 强杀并清理。
  @override
  void reap() {
    if (_pidFile.existsSync()) {
      _forceKillChild();
    }
    _finishTimers();
  }

  void _emitState() {
    if (!_stateController.isClosed) _stateController.add(_state);
  }

  @override
  Future<void> dispose() async {
    _tailTimer?.cancel();
    _heartbeatTimer?.cancel();
    _exitWaitTimer?.cancel();
    await _stateController.close();
    await _logController.close();
  }
}
