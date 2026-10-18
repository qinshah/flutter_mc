// 进程生命周期：启动 / 停止 / 状态 / 日志（宿主承载方式，第三类自由设计）。
//
//   ⚠ 原版无对应物：原版 `server/Main.java` 只负责解析命令行并 start 服务端，把
//   "进程如何被拉起、stdout 如何被采集、何时算就绪"留给外层脚本/控制台；Dart 侧要自己
//   把这层做出来，故属第三类自由设计「运行时宿主」。被托管物本身仍是翻译债。
//
// 关键口径（均为**原版判据**，不自定义信号）：
//   * 启动命令行：`java <jvmArgs> -jar <jar> --nogui`——`--nogui` 照 `Main.java:72`
//     （`nogui` 选项名即 `nogui`），其余为宿主承载方式。
//   * 就绪判定：**只认原版就绪行**，判据 `server/dedicated/DedicatedServer.java:246`
//     （`Done ({})! For help, type "help"`）。不用"进程存活"或端口探测替代（design D4）。
//   * 监听端口日志行判据 `DedicatedServer.java:210`（`Starting Minecraft server on {}:{}`）。
//   * 绑定失败日志行判据 `DedicatedServer.java:215`（`**** FAILED TO BIND TO PORT!`）。
//   * 优雅停止：经**原版 RCON** 通道下发 `stop`（design D10），超时才强杀。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mc_server/mc_server.dart';

import 'artifact_resolver.dart';
import 'dedicated_server_carrier.dart';
import 'instance_directory.dart';
import 'local_server_config.dart';

// 承载接口与状态枚举的真身在 dedicated_server_carrier.dart；此处转出，使既有
// `import 'dedicated_server_process.dart'` 的调用方照旧拿到 `ServerState`。
export 'dedicated_server_carrier.dart' show DedicatedServerCarrier, ServerState;

/// 桌面子进程承载：`Process.start(java, [...jvmArgs, '-jar', jar, '--nogui'])`。
///
/// 与 Android 的进程内 JVM 承载（`android_embedded_jvm_host.dart`）共用
/// [DedicatedServerCarrier] 这条契约面（spec「与桌面承载层共享同一契约面」）。
class DedicatedServerProcess implements DedicatedServerCarrier {
  DedicatedServerProcess({
    required this.config,
    required this.instanceDirectory,
  });

  final LocalServerConfig config;
  final InstanceDirectory instanceDirectory;

  /// 就绪行（判据 `DedicatedServer.java:246`）：`Done (<耗时>)! For help, type "help"`。
  /// 真身在 [DedicatedServerCarrier]（两块承载共用一份）。
  static final RegExp readyLine = DedicatedServerCarrier.readyLine;

  /// 绑定失败标记（判据 `DedicatedServer.java:215`）。
  static const String bindFailedMarker = DedicatedServerCarrier.bindFailedMarker;

  /// 监听端口日志行（判据 `DedicatedServer.java:210`），用于回显**实际**监听端口。
  static final RegExp listeningLine = DedicatedServerCarrier.listeningLine;

  Process? _process;
  ServerState _state = ServerState.stopped;
  int? _exitCode;
  bool _bindFailed = false;

  /// 日志保留上限（宿主环形缓冲；完整日志同时落 `logs/host-console.log`）。
  static const int _maxRecentLines = 500;
  final List<String> _recent = <String>[];

  final StreamController<ServerState> _stateController =
      StreamController<ServerState>.broadcast();
  final StreamController<String> _logController =
      StreamController<String>.broadcast();
  IOSink? _consoleSink;

  @override
  ServerState get state => _state;
  @override
  int? get exitCode => _exitCode;
  @override
  bool get bindFailed => _bindFailed;
  @override
  bool get isRunning => _state == ServerState.starting || _state == ServerState.ready;

  /// 最近日志（供 UI 面板初次渲染）。
  @override
  List<String> get recentLogs => List<String>.unmodifiable(_recent);

  @override
  Stream<ServerState> get stateChanges => _stateController.stream;
  @override
  Stream<String> get logLines => _logController.stream;

  /// 实际监听端口：以原版日志行为准（`DedicatedServer.java:210`）；未就绪时为 null。
  @override
  int? get listeningPort => _actualPort;
  int? _actualPort;

  @override
  Future<void> start(ServerArtifacts artifacts) async {
    if (_process != null) return;
    _state = ServerState.starting;
    _exitCode = null;
    _bindFailed = false;
    _actualPort = null;
    _emitState();

    // stdout/stderr 采集 + 落日志（"stdout/stderr 入管道并同时落日志"）。
    Directory('${instanceDirectory.dir.path}/logs').createSync(recursive: true);
    _consoleSink = File('${instanceDirectory.dir.path}/logs/host-console.log')
        .openWrite(mode: FileMode.append);

    final process = await Process.start(
      artifacts.javaExecutable,
      <String>[
        ...config.jvmArgs,
        '-jar', artifacts.jar.path,
        '--nogui', // Main.java:72 的 nogui 选项
      ],
      workingDirectory: instanceDirectory.dir.path,
    );
    _process = process;

    void consume(Stream<List<int>> stream) {
      stream
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen(_onLine);
    }

    consume(process.stdout);
    consume(process.stderr);

    unawaited(process.exitCode.then(_onExit));
  }

  void _onLine(String line) {
    _recent.add(line);
    if (_recent.length > _maxRecentLines) {
      _recent.removeRange(0, _recent.length - _maxRecentLines);
    }
    _consoleSink?.writeln(line);
    if (!_logController.isClosed) _logController.add(line);

    if (!_bindFailed && line.contains(bindFailedMarker)) {
      _bindFailed = true; // 端口冲突等绑定失败（DedicatedServer.java:215）
      _emitState();
    }
    final listening = listeningLine.firstMatch(line);
    if (listening != null) {
      _actualPort = int.tryParse(listening.group(1)!);
      _emitState();
    }
    if (_state == ServerState.starting &&
        readyLine.hasMatch(line)) {
      // 就绪：只认原版就绪行（design D4 / spec「就绪判定以原版输出为准」）。
      _state = ServerState.ready;
      _emitState();
    }
  }

  void _onExit(int code) {
    _exitCode = code;
    _process = null;
    // 正常停止（stopping）或自然退出（0）都归"已停止"；异常退出归"失败"并暴露退出码。
    _state = (_state == ServerState.stopping || code == 0)
        ? ServerState.stopped
        : ServerState.failed;
    _emitState();
  }

  /// 优雅停止：经 RCON 下发 `stop` → 等待退出 → 超时上限后才强杀（design D10）。
  @override
  Future<void> stop() async {
    final process = _process;
    if (process == null) return;
    _state = ServerState.stopping;
    _emitState();

    await _sendStopViaRcon();

    final exited = await process.exitCode
        .timeout(Duration(seconds: config.stopTimeoutSeconds))
        .then((_) => true)
        .catchError((_) => false);
    if (!exited) {
      process.kill(ProcessSignal.sigkill);
    }
  }

  /// 回收孤儿：应用退出/宿主重载时若进程仍存活则强杀（spec「MUST NOT 残留孤儿进程」）。
  @override
  void reap() {
    _process?.kill(ProcessSignal.sigkill);
  }

  /// 当前进程的 OS PID（未启动则为 null）。用于跨会话清理残留孤儿时排除"本次会话的自己"。
  int? get pid => _process?.pid;

  /// 经原版 RCON 通道下发 `stop`。RCON 口令/端口取自实例 `server.properties`
  /// （翻译件 `DedicatedServerProperties`，判据 `DedicatedServerProperties.java:85-86`）。
  Future<bool> _sendStopViaRcon() async {
    RconClient? client;
    try {
      final props = DedicatedServerProperties(
          Settings.loadFromFile(instanceDirectory.serverProperties.path));
      if (!props.enableRcon || props.rconPassword.isEmpty) return false;
      client = await RconClient.connect('127.0.0.1', props.rconPort,
          timeout: const Duration(seconds: 3));
      final ok = await client.authenticate(props.rconPassword);
      if (!ok) return false;
      await client.execCommand('stop');
      return true;
    } catch (_) {
      return false; // 未就绪/通道不可用：退回"等待 + 强杀"路径
    } finally {
      await client?.close();
    }
  }

  void _emitState() {
    if (!_stateController.isClosed) _stateController.add(_state);
  }

  @override
  Future<void> dispose() async {
    _consoleSink?.close();
    await _stateController.close();
    await _logController.close();
  }
}
