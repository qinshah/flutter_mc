// 本地服务器宿主（app 壳）：把"解析产物 → 初始化实例目录 → EULA 门槛 → 起进程 → 停进程"
// 串成一条链，并持有跨屏存活的进程与配置。
//
//   ⚠ 属第三类自由设计「运行时宿主（JVM 托管）」（AGENTS.md）：原版把这套"拉起并托管一个
//   服务端进程"的工作交给外层脚本/运维，无 Java 可抄；豁免的**只是承载方式**，被托管物
//   （服务端本体）照旧登记为翻译债（openspec/progress.md 第 14 项）。
//
// 布局（design.md D6，根下沿用原版文件名，不自造）：
//   <appSupport>/local_server/
//     ├─ instances.json             宿主自造：实例清单（**不写 servers.dat**，spec「列表文件不被污染」）
//     ├─ artifacts/                 产物目录（用户放置 / 构建期资产落地 / 未来下载）
//     └─ servers/<id>/              实例根 = 服务端进程工作目录（原版 Main 的 ".")
//          ├─ server.properties / eula.txt / world/ / logs/ ...（沿用原版文件名）
import 'dart:async';
import 'dart:convert' show LineSplitter;
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:mc_session/mc_session.dart';
import 'package:path_provider/path_provider.dart';

import 'android_subprocess_jvm_host.dart';
import 'artifact_resolver.dart';
import 'dedicated_server_process.dart';
import 'eula_gate.dart';
import 'instance_directory.dart';
import 'local_server_config.dart';

/// 版本锚点不一致（spec「版本锚点与客户端同版」）：拒绝启动并报出两侧版本。
class VersionAnchorMismatchException implements Exception {
  VersionAnchorMismatchException(this.serverVersion, this.clientVersions);

  final int serverVersion;
  final Set<int> clientVersions;

  @override
  String toString() =>
      '版本锚点不一致：服务端协议 $serverVersion，客户端锚点协议 ${clientVersions.toList()..sort()}。'
      '本地服务器必须与客户端同版（MUST NOT 降级到其他版本）。';
}

/// 占用某端口的一个本地服务器（本宿主名下）。
///
/// 有两个来源：**本次会话**里的实例（有进程句柄，可优雅停），以及**上次会话残留**的
/// 孤儿进程（只能用 PID 强杀）。
class LocalPortHolder {
  LocalPortHolder({required this.label, required this.graceful, required this.stop});

  /// 展示名（实例名；孤儿且实例已删时给目录 id）。
  final String label;

  /// true = 经 RCON 优雅停止；false = 孤儿进程，只能强杀。
  final bool graceful;

  /// 停掉它。
  final Future<void> Function() stop;
}

/// 本地服务器管理器：进程与配置的持有者（跨屏存活）。
class LocalServerManager {
  /// [bundledJarLister]/[bundledJarLoader] 缺省走生产实现（`AssetManifest` + `rootBundle`）；
  /// 单测注入"无资产"以让"缺产物"用例与仓库里是否放了 jar 无关（jar 未入库）。
  LocalServerManager(
    this.root, {
    BundledJarLister? bundledJarLister,
    BundledJarLoader? bundledJarLoader,
  })  : bundledJarLister = bundledJarLister ?? listBundledJarAssets,
        bundledJarLoader = bundledJarLoader ?? loadBundledJar;

  /// 应用私有根（调用方注入，见 main.dart 用 `getApplicationSupportDirectory()`）。
  final Directory root;

  /// 构建期资产目录（`assets/server/<label>/`）的 jar 键枚举器。
  final BundledJarLister bundledJarLister;

  /// 构建期资产的 jar 载入器。
  final BundledJarLoader bundledJarLoader;

  /// 承载接口与状态枚举在本文件内经 `dedicated_server_carrier.dart` 使用；转出给调用方。
  late final LocalServerConfigStore _store =
      LocalServerConfigStore(File('${root.path}/instances.json'));
  final Map<String, DedicatedServerCarrier> _processes =
      <String, DedicatedServerCarrier>{};
  List<LocalServerConfig>? _cache;

  Directory get artifactsDir => Directory('${root.path}/artifacts');

  /// 实例清单（首次调用读盘）。
  List<LocalServerConfig> get configs => _cache ??= _store.load();

  void saveConfigs() => _store.save(configs);

  LocalServerConfig addConfig({String? name}) {
    final config = newConfigDraft(name: name);
    insertConfig(config);
    return config;
  }

  /// 生成一个**未入库、未落盘**的实例草稿。
  ///
  /// 给"先填表、用户确认后才创建"的流程用（原版创建世界同理：`CreateWorldScreen` 只是编辑
  /// 一份 `WorldCreationUiState`，按"创建"才真正落盘）。草稿用的 id 与 [addConfig] 同口径。
  LocalServerConfig newConfigDraft({String? name}) => LocalServerConfig(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name ?? '本地世界',
      );

  /// 把草稿入库并落盘（用户确认创建时调用）。
  void insertConfig(LocalServerConfig config) {
    configs.add(config);
    saveConfigs();
  }

  void removeConfig(LocalServerConfig config) {
    final process = _processes.remove(config.id);
    process?.reap();
    unawaited(process?.dispose());
    configs.remove(config);
    saveConfigs();
  }

  InstanceDirectory instanceDirectoryFor(LocalServerConfig config) => InstanceDirectory(
        Directory('${root.path}/servers/${config.id}'),
        // paperclip 的引导产物跨实例共享（见 `InstanceDirectory.sharedDir`）：
        // 否则每建一个新世界都要重下一遍 libraries/versions/cache（实测各约 166MB）。
        sharedDir: Directory('${root.path}/shared'),
      );

  EulaGate eulaGateFor(LocalServerConfig config) =>
      EulaGate(instanceDirectoryFor(config));

  /// 取（或建）该实例的**承载**句柄。
  ///
  /// 这是"运行时宿主"的**装配点**：按平台选承载实现，业务代码不按平台 / 版本号分支。
  ///   · 桌面 → 子进程承载（[DedicatedServerProcess]，`Process.start(java -jar …)`）
  ///   · Android → 专用子进程承载（[AndroidSubprocessJvmHost]，`:jvm` 子进程内
  ///     dlopen JRE + `JNI_CreateJavaVM`；一次会话一个子进程，绕开"一进程一台 VM"）
  /// 两者共用 [DedicatedServerCarrier] 这条契约面（spec「与桌面承载层共享同一契约面」）。
  DedicatedServerCarrier processFor(LocalServerConfig config) =>
      _processes.putIfAbsent(config.id, () => _createCarrier(config));

  DedicatedServerCarrier _createCarrier(LocalServerConfig config) {
    final instanceDirectory = instanceDirectoryFor(config);
    if (Platform.isAndroid) {
      return AndroidSubprocessJvmHost(
        config: config,
        instanceDirectory: instanceDirectory,
        jreRoot: Directory('${root.path}/jre'),
      );
    }
    return DedicatedServerProcess(
      config: config,
      instanceDirectory: instanceDirectory,
    );
  }

  /// 产物解析（含版本锚点校验）。
  ///
  /// 版本锚点经**装配点**判定（`SessionAssembly.isSupported`）——不在此处按版本号分支，
  /// 与 spec「版本包接入模式」一致；客户端锚点 = 装配点已注册的协议集合。
  ///
  /// Android 上无系统 JVM：解析前先确保 arm64 JRE 已由构建期资产安装到应用私有目录
  /// （spec「JRE 产物按客户端锚点主版本提供」「产物安装于应用私有目录」）。
  Future<ServerArtifacts> resolveArtifacts(LocalServerConfig config) async {
    if (!SessionAssembly.isSupported(config.protocol)) {
      throw VersionAnchorMismatchException(
          config.protocol, SessionAssembly.registeredProtocols);
    }
    if (Platform.isAndroid) {
      await AndroidJreInstaller(jreRoot: Directory('${root.path}/jre'))
          .ensureInstalled(config.javaMajor);
    }
    final resolver = ArtifactResolver(
      root: root,
      bundledJarLister: bundledJarLister,
      bundledJarLoader: bundledJarLoader,
    );
    return resolver.resolve(config);
  }

  /// 构建期资产目录（`assets/server/<label>/`）下的 jar 键。
  ///
  /// 不能写死文件名：用户放的是 `paper-26.2.jar` / `paper-26.2-129.jar` 之类，
  /// pubspec 逐目录声明后目录下**所有**文件都在 `AssetManifest` 里，故按前缀枚举。
  /// 清单不可读（非 Flutter 宿主/绑定未初始化）视为无资产，由解析器落到"报缺"。
  static Future<List<String>> listBundledJarAssets(String dirPrefix) async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      return manifest
          .listAssets()
          .where((key) => key.startsWith(dirPrefix))
          .toList(growable: false);
    } catch (_) {
      return const <String>[];
    }
  }

  /// 构建期资产携带的 jar（`assets/server/<版本>/` 下的 jar，见 pubspec.yaml）。
  /// 资产缺失返回 null（不抛），由解析器落到"报缺并提示放置位置"。
  static Future<List<int>?> loadBundledJar(String assetKey) async {
    try {
      final data = await rootBundle.load(assetKey);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (_) {
      return null;
    }
  }

  /// 占用 [port] 的本地服务器；内存里查不到时用系统工具反查**残留孤儿**。
  ///
  /// 为什么要反查孤儿（实测）：Dart 的子进程不随父进程退出而死，应用被强杀、或开发期
  /// 热重启都会丢掉 Dart 侧的进程句柄，而 OS 进程照旧占着 25565/25575/25585
  /// （实测到 `pid 31798` PPID=1 的残留 java 进程）。旧实现只查本次会话的进程表，
  /// 于是端口面板"只知道被占、停不掉"。
  ///
  /// 防误杀：PID 复用/别人的 java 进程都可能占着该端口，故必须再确认该进程的 **cwd
  /// 落在本宿主根下**（我们的服务端工作目录就是 `<root>/servers/<id>`）。
  /// 本反查依赖 `lsof`，仅 macOS/Linux 可用。
  Future<LocalPortHolder?> findPortHolder(int port) async {
    final inMemory = localHolderOf(port);
    if (inMemory != null) {
      return LocalPortHolder(
        label: inMemory.name,
        graceful: true,
        stop: () => processFor(inMemory).stop(),
      );
    }
    if (!Platform.isMacOS && !Platform.isLinux) return null;

    final pid = await _listeningPidOn(port);
    if (pid == null) return null;
    final cwd = await _processCwd(pid);
    if (cwd == null || !_isUnderRoot(cwd)) return null;

    final id = _instanceIdFromCwd(cwd);
    var name = id ?? '未知实例';
    for (final config in configs) {
      if (config.id == id) {
        name = config.name;
        break;
      }
    }
    return LocalPortHolder(
      label: name,
      graceful: false,
      stop: () async {
        // 孤儿进程没有 RCON 凭据可用（口令在实例目录里，但优雅停止只对活着的连接有意义），
        // 直接 SIGTERM→短暂等待→SIGKILL，确保端口释放。
        Process.killPid(pid, ProcessSignal.sigterm);
        await Future<void>.delayed(const Duration(milliseconds: 800));
        Process.killPid(pid, ProcessSignal.sigkill);
      },
    );
  }

  /// 清掉**上次会话残留**的服务端进程（孤儿），返回被清理的 PID 列表。
  ///
  /// 应用启动时调用：保证"应用退出＝服务端一起停"即使在强杀/热重启这类钩子不触发的
  /// 路径下也成立（spec「MUST NOT 残留孤儿进程」）。同样以 **cwd 在宿主根下** 为唯一判据，
  /// 不误杀其他 java 程序。
  Future<List<int>> reapLeftovers() async {
    if (!Platform.isMacOS && !Platform.isLinux) return const <int>[];
    final killed = <int>[];
    final pids = await _javaPids();
    for (final pid in pids) {
      // 本次会话自己起的实例不动（它们有句柄，由停机流程负责）。
      // 仅进程外（桌面）承载有 OS PID 可比对；进程内承载与宿主同进程，无需排除。
      if (_processes.values.any((p) =>
          p is DedicatedServerProcess && p.pid == pid && p.isRunning)) {
        continue;
      }
      final cwd = await _processCwd(pid);
      if (cwd == null || !_isUnderRoot(cwd)) continue;
      Process.killPid(pid, ProcessSignal.sigterm);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!Process.killPid(pid, ProcessSignal.sigkill)) continue;
      killed.add(pid);
    }
    return killed;
  }

  /// `lsof -t -nP -iTCP:<port> -sTCP:LISTEN` → 监听该端口的首个 PID。
  Future<int?> _listeningPidOn(int port) async {
    final result = await Process.run('lsof', <String>[
      '-t', '-nP', '-iTCP:$port', '-sTCP:LISTEN',
    ]);
    for (final line in const LineSplitter().convert(result.stdout.toString())) {
      final pid = int.tryParse(line.trim());
      if (pid != null) return pid;
    }
    return null;
  }

  /// 该进程的工作目录（`lsof -a -p <pid> -d cwd -Fn` 的 `n<path>` 行）。
  Future<String?> _processCwd(int pid) async {
    final result = await Process.run('lsof', <String>[
      '-a', '-p', '$pid', '-d', 'cwd', '-Fn',
    ]);
    for (final line in const LineSplitter().convert(result.stdout.toString())) {
      if (line.startsWith('n')) return line.substring(1);
    }
    return null;
  }

  /// 候选 java 进程：`pgrep -f java`（再用 cwd 过滤，故此处放宽即可）。
  Future<List<int>> _javaPids() async {
    final result = await Process.run('pgrep', <String>['-f', 'java']);
    return const LineSplitter()
        .convert(result.stdout.toString())
        .map(int.tryParse)
        .whereType<int>()
        .toList();
  }

  bool _isUnderRoot(String path) =>
      path == root.path || path.startsWith('${root.path}${Platform.pathSeparator}');

  /// cwd 形如 `<root>/servers/<id>` → 取 `<id>`（不是该形态则 null）。
  String? _instanceIdFromCwd(String cwd) {
    final segments = cwd.split(Platform.pathSeparator);
    final serversIndex = segments.lastIndexOf('servers');
    if (serversIndex < 0 || serversIndex + 1 >= segments.length) return null;
    return segments[serversIndex + 1];
  }

  /// 占用 [port] 的**本宿主**实例（没有则 null）。
  ///
  /// 用途：端口冲突时给"就地停掉它"的入口（用户要求红色停止按钮）。
  /// 判据用进程自报的**实际**监听端口（`listeningPort`，原版 `DedicatedServer.java:210`），
  /// 未回显时回落配置值。
  LocalServerConfig? localHolderOf(int port) {
    for (final config in configs) {
      final process = processFor(config);
      if (process.isRunning && (process.listeningPort ?? config.port) == port) {
        return config;
      }
    }
    return null;
  }

  /// 端口是否可用（宿主承载方式）：以"能否绑定全部接口"近似服务端 `server-ip` 为空时
  /// 绑 `*` 的语义（判据 `DedicatedServer.java:210` 的 `*` 分支）。
  Future<bool> isPortAvailable(int port) async {
    try {
      final socket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      await socket.close();
      return true;
    } on SocketException {
      return false;
    }
  }

  /// 从当前可用端口中挑一个（冲突时给用户改端口的备选）。
  Future<int> suggestPort(int from) async {
    for (var port = from + 1; port <= 65535; port++) {
      if (await isPortAvailable(port)) return port;
    }
    return from;
  }

  /// 回收全部已启动实例（应用退出/宿主重载时调用，spec「MUST NOT 残留孤儿进程」）。
  void reapAll() {
    for (final process in _processes.values) {
      process.reap();
    }
  }
}

/// 全应用单例（app 壳装配点，与 `routes.dart` 的装配同层）。
///
/// 宿主天然要跨屏存活（进程句柄不能随页面销毁而丢），故用单例持有；测试直接
/// `new LocalServerManager(tmpDir)`，不走这里。
LocalServerManager? _singleton;

LocalServerManager get localServerManager {
  final manager = _singleton;
  if (manager == null) {
    throw StateError('本地服务器宿主未初始化：请在 main() 中 await initLocalServerHost()');
  }
  return manager;
}

/// 在 `main()` 里初始化（根取应用私有目录，path_provider 的 `getApplicationSupportDirectory`）。
Future<LocalServerManager> initLocalServerHost() async {
  final support = await getApplicationSupportDirectory();
  final manager = _singleton ??= LocalServerManager(
    Directory('${support.path}/local_server'),
  );
  // 上次会话若被强杀/开发期热重启，服务端子进程会脱离父进程（PPID=1）继续占端口；
  // 每次都清一遍才是"应用退出＝服务端一起停"的可靠保证（spec「MUST NOT 残留孤儿进程」）。
  try {
    final killed = await manager.reapLeftovers();
    if (killed.isNotEmpty) {
      debugPrint('[LOCAL-SERVER-HOST] 已清理上次会话残留的服务端进程：$killed');
    }
  } catch (e) {
    debugPrint('[LOCAL-SERVER-HOST] 残留进程清理失败：$e');
  }
  return manager;
}
