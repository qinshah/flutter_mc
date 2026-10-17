// 端到端实测（tasks 5.1 / 3.4 / 3.5 / 3.6）：用 `/Users/qshh/Desktop/paperMC` 的**成熟产物**
// 做对照——复制其 libraries/versions（避免 paperclip 首启联网下载），换独立端口起服，
// 走完整链路：起服 → 就绪行 → RCON 下发指令并读原版回显 → 优雅停止 → 端口释放。
//
// 默认跳过（耗时且需要本机 JDK 25 与对照产物）。显式开启：
//   MC_LOCAL_SERVER_E2E=1 flutter test test/local_server_e2e_test.dart
//
// 断言的是**原版行为**（就绪行、RCON 回显、进程退出），不是"我的实现输出"。
import 'dart:async';
import 'dart:io';

import 'package:flutter_mc/platform/server_host/dedicated_server_process.dart';
import 'package:flutter_mc/platform/server_host/local_server_config.dart';
import 'package:flutter_mc/platform/server_host/local_server_host.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mc_server/mc_server.dart';
import 'package:mc_session/mc_session.dart';

/// 对照实例（经验证据，非 mc-sources 判据，见 design.md Context）。
const String kReferenceDir = '/Users/qshh/Desktop/paperMC';
const String kReferenceJar = 'paper-26.2-129.jar';

void main() {
  // 生产资产解析走 `rootBundle`（需绑定已初始化）。
  TestWidgetsFlutterBinding.ensureInitialized();
  final enabled = Platform.environment['MC_LOCAL_SERVER_E2E'] == '1';

  test('起服 → 就绪 → RCON 指令回显 → 优雅停止 → 端口释放', () async {
    final tmp = Directory.systemTemp.createTempSync('local_server_e2e');
    DedicatedServerProcess? process;
    try {
      final hostRoot = Directory('${tmp.path}/host');
      final manager = LocalServerManager(hostRoot);

      // 实例目录 = 对照产物的副本（含 libraries/versions，免首启下载）。
      final instanceDir = manager.instanceDirectoryFor(
          LocalServerConfig(id: 'e2e', name: 'e2e'));
      Directory(instanceDir.dir.path).createSync(recursive: true);
      final copy = Process.runSync('cp', <String>[
        '-R',
        '$kReferenceDir/libraries',
        '$kReferenceDir/versions',
        '$kReferenceDir/cache',
        '$kReferenceDir/config',
        '$kReferenceDir/plugins',
        instanceDir.dir.path,
      ]);
      expect(copy.exitCode, 0, reason: '复制对照产物失败：${copy.stderr}');

      // 独立端口（不动对照实例的 25565）。
      final port = await _freePort();
      final rconPort = await _freePort();
      final managementPort = await _freePort();
      final config = LocalServerConfig(
        id: 'e2e',
        name: 'e2e',
        port: port,
        rconPort: rconPort,
        managementServerPort: managementPort,
        jarPath: '$kReferenceDir/$kReferenceJar',
      );

      // EULA 硬门槛（spec）：写入 eula=true 后才允许启动。
      final gate = manager.eulaGateFor(config);
      gate.agree();
      expect(gate.agreed, isTrue);

      // 实例目录 + 宿主管理的配置键（含开启 RCON / 管理服务器与补空口令）。
      instanceDir.createLayout();
      instanceDir.ensureProperties(config);

      final props = Settings.loadFromFile(instanceDir.serverProperties.path);
      expect(props['enable-rcon'], 'true');
      expect(props['rcon.password']!.isNotEmpty, isTrue);
      expect(props['server-port'], '$port');
      expect(props['management-server-enabled'], 'true');

      // 产物解析（版本锚点 + jar + JVM）。
      final artifacts = await manager.resolveArtifacts(config);
      expect(artifacts.javaMajor >= 25, isTrue,
          reason: 'Paper 26.2 需 Java 25（logs/latest.log:1）');

      // 起服。
      process = manager.processFor(config);
      final ready = Completer<bool>();
      process.stateChanges.listen((s) {
        if (s == ServerState.ready && !ready.isCompleted) ready.complete(true);
        if (s == ServerState.failed && !ready.isCompleted) ready.complete(false);
      });
      await process.start(artifacts);

      final ok = await ready.future.timeout(const Duration(minutes: 5),
          onTimeout: () => false);
      expect(ok, isTrue,
          reason:
              '未在原版就绪行时限内就绪；日志：${process.recentLogs.reversed.take(20)}');
      expect(process.state, ServerState.ready);
      expect(process.listeningPort, port,
          reason: '回显实际监听端口（DedicatedServer.java:210）');
      expect(await manager.isPortAvailable(port), isFalse,
          reason: '就绪后端口应被占用');

      // 用**本应用**连入（spec「单人入口是快捷路径」复用同一 remote-play 通路）：
      // `SessionAssembly.connectFor` 是 app 壳装配点，join_flow 的 defaultJoinConnector 就走它。
      final session = await SessionAssembly.connectFor(
        ServerData(name: config.name, ip: '127.0.0.1:$port'),
        playerName: 'flutter_mc',
      );
      try {
        final joined = Completer<bool>();
        final chunk = Completer<bool>();
        session.events.listen((event) {
          if (event is JoinedGame && !joined.isCompleted) joined.complete(true);
          if (event is ChunkLoaded && !chunk.isCompleted) chunk.complete(true);
          if (event is SessionClosed && !joined.isCompleted) joined.complete(false);
        });
        expect(await joined.future.timeout(const Duration(seconds: 90)),
            isTrue,
            reason: '本应用未能进入 play 阶段（JoinedGame）');
        expect(await chunk.future.timeout(const Duration(seconds: 90)), isTrue,
            reason: '本应用未收到区块数据（ChunkLoaded）');

        // RCON 指令 + 原版回显：此时应看到 1 名玩家在线（本应用刚连入）。
        final client = await RconClient.connect('127.0.0.1', rconPort,
            timeout: const Duration(seconds: 5));
        await client.authenticate(props['rcon.password']!);
        final output = await client.execCommand('list');
        await client.close();
        expect(output, contains('There are 1 of a max of'),
            reason: 'RCON 应返回原版 list 回显（含刚连入的玩家），实际：$output');
      } finally {
        session.close();
      }

      // 优雅停止（经 RCON 下发 stop → 等待退出）。
      await process.stop();
      expect(process.state, ServerState.stopped);
      expect(process.isRunning, isFalse);
      expect(await manager.isPortAvailable(port), isTrue,
          reason: '停止后端口应释放');
      expect(
          File('${instanceDir.dir.path}/logs/host-console.log').existsSync(), isTrue,
          reason: 'stdout 应落日志');
    } finally {
      process?.reap();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 8)), skip: !enabled);

  // 真机运行时路径（用户报「运行时说没有 paper」就是这条）：不设 `jarPath`、不预置
  // libraries/versions——走**生产**资产解析（AssetManifest 枚举 `assets/server/26_2/*.jar`
  // 落地到产物目录），Paper 的 paperclip 自行引导下载依赖（实测 11s 达就绪）。
  //   —— 上一条用例设了 jarPath 并复制对照产物，绕过了资产分支，故它绿≠运行时能用。
  test('资产路径：不设 jarPath、不预置依赖，也能起服到就绪', () async {
    final tmp = Directory.systemTemp.createTempSync('local_server_asset_e2e');
    DedicatedServerProcess? process;
    try {
      // 资产源文件（未入库，不存在则跳过本用例）。
      final assetDir = Directory('assets/server/26_2');
      final assetJars = assetDir.existsSync()
          ? assetDir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.toLowerCase().endsWith('.jar'))
              .toList()
          : <File>[];
      if (assetJars.isEmpty) return;

      final manager = LocalServerManager(Directory('${tmp.path}/host'));
      final port = await _freePort();
      final rconPort = await _freePort();
      final config = LocalServerConfig(
        id: 'asset',
        name: 'asset',
        port: port,
        rconPort: rconPort,
        // 故意不设 jarPath：走资产回退。
      );

      final instanceDir = manager.instanceDirectoryFor(config);
      instanceDir.createLayout();
      manager.eulaGateFor(config).agree();
      instanceDir.ensureProperties(config);

      // 生产资产解析：应把 `assets/server/26_2/<任意名>.jar` 落地到产物目录。
      final artifacts = await manager.resolveArtifacts(config);
      expect(artifacts.jar.existsSync(), isTrue,
          reason: '资产目录里的 jar 应被枚举并落地（现状：${assetJars.map((f) => f.uri.pathSegments.last)}）');
      expect(artifacts.jar.lengthSync(), assetJars.first.lengthSync());

      process = manager.processFor(config);
      final ready = Completer<bool>();
      process.stateChanges.listen((s) {
        if (s == ServerState.ready && !ready.isCompleted) ready.complete(true);
        if (s == ServerState.failed && !ready.isCompleted) ready.complete(false);
      });
      await process.start(artifacts);

      // paperclip 首启要下载 mojang jar + libraries，给足时间。
      final ok = await ready.future.timeout(const Duration(minutes: 6),
          onTimeout: () => false);
      expect(ok, isTrue,
          reason: '资产路径未达就绪行；日志：${process.recentLogs.reversed.take(20)}');
      expect(process.state, ServerState.ready);
      expect(process.listeningPort, port);

      await process.stop();
      expect(process.state, ServerState.stopped);
      expect(await manager.isPortAvailable(port), isTrue);
    } finally {
      process?.reap();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 10)), skip: !enabled);
}

/// 取一个当前空闲的端口（绑定 0 由内核分配后立即释放）。
Future<int> _freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}
