// 本地服务器宿主层单测（tasks 3.1/3.2/3.4/3.6 + spec「版本锚点与客户端同版」）。
//
// 断言的是**原版判据**推出的黄金值（键名/默认值/就绪行），不是"我的实现输出"。
import 'dart:io';

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter_mc/platform/server_host/artifact_resolver.dart';
import 'package:flutter_mc/platform/server_host/dedicated_server_process.dart';
import 'package:flutter_mc/platform/server_host/eula_gate.dart';
import 'package:flutter_mc/platform/server_host/instance_directory.dart';
import 'package:flutter_mc/platform/server_host/local_server_config.dart';
import 'package:flutter_mc/platform/server_host/local_server_host.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mc_server/mc_server.dart';
import 'package:mc_session/mc_session.dart';

void main() {
  // 读到真实 `AssetManifest` 才能校验生产资产路径（`rootBundle` 需绑定已初始化）。
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('local_server_host'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('实例目录初始化（tasks 3.2，判据 DedicatedServerProperties.java）', () {
    test('首启配置：三项故意差异 + 控制面开启键 + 原版目录名', () {
      final config = LocalServerConfig(id: 'a', name: '世界');
      final dir = InstanceDirectory(Directory('${tmp.path}/servers/a'));
      dir.createLayout();
      dir.writeInitialPropertiesIfAbsent(config);

      // D6：根下沿用原版文件名，不自造。
      for (final name in const <String>[
        'world',
        'logs',
        'plugins',
        'config',
        'cache',
        'libraries',
        '.paper',
      ]) {
        expect(Directory('${dir.dir.path}/$name').existsSync(), isTrue,
            reason: '缺少原版目录名 $name');
      }

      final props = Settings.loadFromFile(dir.serverProperties.path);

      // 三项故意差异（design.md D7）。
      expect(props['online-mode'], 'false'); // 原版默认 true（:56），离线客户端需 false
      expect(props['server-ip'], ''); // :58 默认，保持一致
      expect(props['server-port'], '25565'); // :72 默认；冲突时改

      // 世界/玩法项：原版默认值逐键（判据同 `DedicatedServerProperties.java`）。
      expect(props['gamemode'], 'survival'); // :68-70 默认 GameType.SURVIVAL
      expect(props['difficulty'], 'easy'); // :65-67 默认 Difficulty.EASY
      expect(props['hardcore'], 'false'); // :87 默认 false
      // :135 默认 ""＝服务端随机（原版创建世界的种子框留空同口径）。
      expect(props['level-seed'], '');
      // :63 原版默认 false；**本仓恒 true**（本地服务器就是单机形态：游戏模式以世界设定为准，
      // 否则存档里的旧模式会压过配置——见 tasks 7.4 的实测根因）。不暴露给用户改。
      expect(props['force-gamemode'], 'true');

      // 控制面开启项（原版两通道默认皆关闭）。
      expect(props['enable-rcon'], 'true'); // 原版 :84 默认 false
      expect(props['rcon.port'], '25575'); // :85 默认
      expect(SecurityConfig.isValid(props['rcon.password'] ?? ''), isTrue,
          reason: 'RCON 口令须非空且 40 字符字母数字（SecurityConfig.java:8-10）');
      expect(props['management-server-enabled'], 'true'); // 原版 :73 默认 false
      expect(props['management-server-host'], 'localhost'); // :74 默认
      expect(props['management-server-port'], '25585'); // :75 默认为 0（临时端口），宿主取定值
      expect(
          SecurityConfig.isValid(props['management-server-secret'] ?? ''), isTrue,
          reason: 'management-server-secret 须为 40 字符字母数字（:76）');
      // 原版 :77 默认 true，但 keystore 为空 → JsonRpc.java:19 走 TLS 分支会抛异常；
      // 本机自托管无证书，故显式关闭。
      expect(props['management-server-tls-enabled'], 'false');
      expect(props['management-server-allowed-origins'], ''); // :80 默认

      // 注释头照 Settings.java:63。
      expect(
          File(dir.serverProperties.path).readAsStringSync(),
          contains('#Minecraft server properties'));
    });

    test('未知键不被丢弃，且端口变更落盘、密钥不变', () {
      final config = LocalServerConfig(id: 'b', name: '世界');
      final dir = InstanceDirectory(Directory('${tmp.path}/servers/b'));
      dir.createLayout();
      dir.writeInitialPropertiesIfAbsent(config);

      final first = Settings.loadFromFile(dir.serverProperties.path);
      // 用户/后续版本追加的未知键。
      File(dir.serverProperties.path).writeAsStringSync(
        '${File(dir.serverProperties.path).readAsStringSync()}'
        'unknown-future-key=keep-me\n',
      );

      config.port = 25566; // 端口冲突后改端口
      config.gamemode = 'creative'; // 玩法（游戏模式）变更也须落到 server.properties
      config.difficulty = 'hard';
      config.levelSeed = '12345'; // 种子变更也须落盘
      dir.ensureProperties(config);

      final second = Settings.loadFromFile(dir.serverProperties.path);
      expect(second['server-port'], '25566', reason: '改端口须落到 server.properties');
      expect(second['gamemode'], 'creative', reason: '改游戏模式须落到 gamemode 键');
      expect(second['difficulty'], 'hard', reason: '改难度须落到 difficulty 键');
      expect(second['level-seed'], '12345', reason: '改种子须落到 level-seed 键');
      expect(second['unknown-future-key'], 'keep-me',
          reason: '未知键 MUST 原样保留（spec「未知键不被丢弃」）');
      expect(second['rcon.password'], first['rcon.password'],
          reason: 'RCON 口令首启后固定，不随启动换');
      expect(second['management-server-secret'], first['management-server-secret']);
    });

    test('依赖缓存判据：createLayout 建的空目录不算"已有依赖"，有内容才算', () {
      final dir = InstanceDirectory(Directory('${tmp.path}/servers/cache'));
      dir.createLayout();
      expect(dir.hasCachedDependencies, isFalse,
          reason: 'createLayout 只建空目录，此时仍属"首次启动需下载"');
      File('${dir.dir.path}/libraries/marker.jar').writeAsStringSync('x');
      expect(dir.hasCachedDependencies, isTrue,
          reason: 'paperclip 的依赖落地后即视为已缓存，不再提示需下载');
    });

    test('共享缓存：新实例从 shared 复制进来（不再走网络），已有实例回写播种', () async {
      final shared = Directory('${tmp.path}/shared');
      // 模拟"第一个世界"已下齐：实例里有内容，共享目录还空着 → 回写播种。
      final first = InstanceDirectory(Directory('${tmp.path}/servers/first'),
          sharedDir: shared);
      first.createLayout();
      File('${first.dir.path}/libraries/a.jar').writeAsStringSync('lib');
      Directory('${first.dir.path}/versions/26.2').createSync(recursive: true);
      File('${first.dir.path}/versions/26.2/b.jar').writeAsStringSync('ver');
      expect(await first.pushSharedCache(), 2);
      expect(File('${shared.path}/libraries/a.jar').existsSync(), isTrue);

      // 新世界：实例目录刚建出来是空的 → 从 shared 复制进来，无需下载。
      final second = InstanceDirectory(Directory('${tmp.path}/servers/second'),
          sharedDir: shared);
      second.createLayout();
      expect(second.hasCachedDependencies, isFalse, reason: '复制前确实还没有');
      expect(await second.pullSharedCache(), 2);
      expect(second.hasCachedDependencies, isTrue, reason: '复制后即为"已缓存"');
      expect(File('${second.dir.path}/libraries/a.jar').readAsStringSync(), 'lib');

      // 幂等：两边都有内容时互不覆盖/不再复制。
      expect(await first.pushSharedCache(), 0);
      expect(await second.pullSharedCache(), 0);
    });
  });

  group('EULA 门槛（tasks 3.3，判据 Eula.java:35/:44 + Main.java:113-121）', () {
    test('未同意不写 eula=true；同意后持久化；撤回后重新要求同意', () {
      final dir = InstanceDirectory(Directory('${tmp.path}/servers/c'));
      dir.createLayout();
      final gate = EulaGate(dir);

      // 首次：文件不存在 → 未同意（原版口径会写回 eula=false，MUST NOT 写 true）。
      expect(gate.agreed, isFalse);
      expect(dir.eulaFile.existsSync(), isTrue);
      expect(
          Properties.loadFile(dir.eulaFile.path)['eula'], 'false',
          reason: '未同意时 eula 必须为 false（spec「未同意不启动」）');

      // 用户明确同意 → 写 true 并持久化。
      gate.agree();
      expect(gate.agreed, isTrue);
      expect(Properties.loadFile(dir.eulaFile.path)['eula'], 'true');

      // 撤回 → 回到未同意。
      gate.revoke();
      expect(gate.agreed, isFalse);
      expect(Properties.loadFile(dir.eulaFile.path)['eula'], 'false');
    });

    test('实例目录尚未创建时读/写 EULA 都不抛（回归：真机起服 FileSystemException）', () {
      // 真机首次启动的状态：实例目录还不存在。原版 `Properties.store` 不建父目录
      // （`Properties.storeFile` 逐行照抄 JDK），旧实现下 `gate.agreed` 走
      // "读失败 → saveDefaults 写回 eula=false" 就抛 FileSystemException，起服失败。
      final dir = InstanceDirectory(Directory('${tmp.path}/servers/fresh'));
      expect(dir.dir.existsSync(), isFalse, reason: '前提：目录尚未建');

      final gate = EulaGate(dir);
      expect(gate.agreed, isFalse);
      expect(dir.eulaFile.existsSync(), isTrue,
          reason: '未同意时写回 eula=false（Eula.java:36-38）');

      gate.agree();
      expect(gate.agreed, isTrue);
      expect(Properties.loadFile(dir.eulaFile.path)['eula'], 'true');
    });
  });

  group('产物解析（tasks 3.1，design.md D5）', () {
    test('缺 jar：报缺并给出期望位置', () async {
      final resolver = ArtifactResolver(
        root: Directory('${tmp.path}/root'),
        javaLocator: () => '/usr/bin/java',
        javaProbe: (_) => 25,
      );
      await expectLater(
        resolver.resolve(LocalServerConfig(id: 'a', name: 'w')),
        throwsA(isA<ArtifactMissingException>()
            .having((e) => e.message, 'message', contains('缺少 26.2'))
            .having((e) => e.message, 'message', contains('artifacts'))),
      );
    });

    test('有 jar 但版本不符：拒绝，不静默替换', () async {
      final root = Directory('${tmp.path}/root');
      Directory('${root.path}/artifacts').createSync(recursive: true);
      File('${root.path}/artifacts/paper-26.3-1.jar').writeAsStringSync('x');
      final resolver = ArtifactResolver(
        root: root,
        javaLocator: () => '/usr/bin/java',
        javaProbe: (_) => 25,
      );
      await expectLater(
        resolver.resolve(LocalServerConfig(id: 'a', name: 'w')),
        throwsA(isA<ArtifactMissingException>()
            .having((e) => e.message, 'message', contains('26.3'))),
      );
    });

    test('JVM 主版本不足：报缺并要求升级', () async {
      final root = Directory('${tmp.path}/root');
      Directory('${root.path}/artifacts').createSync(recursive: true);
      File('${root.path}/artifacts/paper-26.2-1.jar').writeAsStringSync('x');
      final resolver = ArtifactResolver(
        root: root,
        javaLocator: () => '/usr/bin/java',
        javaProbe: (_) => 21, // 低于 Paper 26.2 所需的 25
      );
      await expectLater(
        resolver.resolve(LocalServerConfig(id: 'a', name: 'w')),
        throwsA(isA<ArtifactMissingException>()
            .having((e) => e.message, 'message', contains('Java 25'))),
      );
    });

    test('找不到 JVM：报缺并给指引', () async {
      final root = Directory('${tmp.path}/root');
      Directory('${root.path}/artifacts').createSync(recursive: true);
      File('${root.path}/artifacts/paper-26.2-1.jar').writeAsStringSync('x');
      final resolver = ArtifactResolver(root: root, javaLocator: () => null);
      await expectLater(
        resolver.resolve(LocalServerConfig(id: 'a', name: 'w')),
        throwsA(isA<ArtifactMissingException>()
            .having((e) => e.message, 'message', contains('未找到可用的 Java'))),
      );
    });

    test('产物齐备：返回 jar 与 JVM', () async {
      final root = Directory('${tmp.path}/root');
      Directory('${root.path}/artifacts').createSync(recursive: true);
      final jar = File('${root.path}/artifacts/paper-26.2-129.jar')
        ..writeAsStringSync('x');
      final resolver = ArtifactResolver(
        root: root,
        javaLocator: () => '/usr/bin/java',
        javaProbe: (_) => 25,
      );
      final artifacts = await resolver.resolve(LocalServerConfig(id: 'a', name: 'w'));
      expect(artifacts.jar.path, jar.path);
      expect(artifacts.javaMajor, 25);
    });

    test('构建期资产回退：枚举资产目录下任意 .jar（不写死文件名）后落地到产物目录', () async {
      final root = Directory('${tmp.path}/root');
      // 资产里放的是 `paper-26.2.jar`（用户实际放置的名字），不是约定的 `server.jar`：
      // 枚举器返回该目录的键表，解析器取首个 `.jar` 落地。
      final resolver = ArtifactResolver(
        root: root,
        javaLocator: () => '/usr/bin/java',
        javaProbe: (_) => 25,
        bundledJarLister: (dirPrefix) async => dirPrefix == 'assets/server/26_2/'
            ? <String>['assets/server/26_2/.gitkeep', 'assets/server/26_2/paper-26.2.jar']
            : <String>[],
        bundledJarLoader: (key) async =>
            key == 'assets/server/26_2/paper-26.2.jar' ? <int>[1, 2, 3] : null,
      );
      final artifacts = await resolver.resolve(LocalServerConfig(id: 'a', name: 'w'));
      expect(artifacts.jar.existsSync(), isTrue);
      expect(artifacts.jar.readAsBytesSync(), <int>[1, 2, 3]);
    });

    test('第二次解析命中已落地的产物，不再重复读资产（回归：别每次进世界都重写 64MB）',
        () async {
      final root = Directory('${tmp.path}/root');
      var loadCalls = 0;
      final resolver = ArtifactResolver(
        root: root,
        javaLocator: () => '/usr/bin/java',
        javaProbe: (_) => 25,
        bundledJarLister: (_) async => <String>['assets/server/26_2/paper-26.2.jar'],
        bundledJarLoader: (key) async {
          loadCalls++;
          return <int>[1, 2, 3];
        },
      );
      final config = LocalServerConfig(id: 'a', name: 'w');
      final first = await resolver.resolve(config);
      expect(loadCalls, 1, reason: '首次：从构建期资产落地');
      final second = await resolver.resolve(config);
      expect(second.jar.path, first.jar.path);
      expect(loadCalls, 1, reason: '第二次：产物目录已命中，MUST NOT 再读资产');
    });
  });

  group('版本锚点（spec「版本锚点与客户端同版」/ tasks 5.2）', () {
    test('协议与客户端锚点不同：拒绝并报出两侧版本', () async {
      final manager = LocalServerManager(Directory('${tmp.path}/root'));
      final config = LocalServerConfig(id: 'a', name: 'w', protocol: 775);
      await expectLater(
        manager.resolveArtifacts(config),
        throwsA(isA<VersionAnchorMismatchException>()
            .having((e) => e.serverVersion, 'serverVersion', 775)
            .having((e) => e.clientVersions, 'clientVersions',
                contains(SessionAssembly.registeredProtocols.first))),
      );
    });

    test('协议与客户端锚点一致：越过锚点校验（此处因缺产物而报缺，非锚点错）', () async {
      // 注入"资产目录为空"，让该用例与仓库里是否放了 jar（未入库）无关。
      final manager = LocalServerManager(
        Directory('${tmp.path}/root'),
        bundledJarLister: (_) async => const <String>[],
      );
      final config = LocalServerConfig(
        id: 'a',
        name: 'w',
        protocol: SessionAssembly.registeredProtocols.first,
      );
      await expectLater(
        manager.resolveArtifacts(config),
        throwsA(isA<ArtifactMissingException>()),
      );
    });
  });

  group('就绪/监听/绑定失败判据（tasks 3.4 / 3.6，原版行号）', () {
    test('就绪行只认 DedicatedServer.java:246 的原版输出', () {
      // 原版实际形态：[12:00:00] [Server thread/INFO]: Done (4.619s)! For help, type "help"
      expect(
        DedicatedServerProcess.readyLine.hasMatch(
            '[12:00:00] [Server thread/INFO]: Done (4.619s)! For help, type "help"'),
        isTrue,
      );
      // 进程已起但世界仍在加载：不算就绪。
      expect(
        DedicatedServerProcess.readyLine.hasMatch(
            '[12:00:00] [Server thread/INFO]: Preparing level "world"'),
        isFalse,
      );
      // "进程存活"或端口可连不能替代就绪行。
      expect(
        DedicatedServerProcess.readyLine
            .hasMatch('[12:00:00] [Server thread/INFO]: Starting server'),
        isFalse,
      );
    });

    test('监听端口行（DedicatedServer.java:210）取到实际端口', () {
      final match = DedicatedServerProcess.listeningLine.firstMatch(
          '[12:00:00] [Server thread/INFO]: Starting Minecraft server on *:25565');
      expect(match?.group(1), '25565');
    });

    test('绑定失败标记（DedicatedServer.java:215）', () {
      expect(DedicatedServerProcess.bindFailedMarker, '**** FAILED TO BIND TO PORT!');
    });
  });

  group('端口可用性（tasks 3.6）', () {
    test('已占用端口判为不可用，空闲端口判为可用', () async {
      final manager = LocalServerManager(Directory('${tmp.path}/root'));
      final socket = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      final busy = socket.port;
      expect(await manager.isPortAvailable(busy), isFalse);
      await socket.close();
      expect(await manager.isPortAvailable(busy), isTrue);
    });
  });

  // 回归：真机运行时"说没有 paper"（资产 jar 写死成 `server.jar`，用户放的是
  // `paper-26.2.jar`）。用**生产** rootBundle + AssetManifest 走一遍解析，证明
  // 资产目录下**任意** `.jar` 都能被枚举并落地。jar 未入库（.gitignore），
  // 源目录里没有时跳过（CI 上不存在，与 mc_resource 的既有口径一致）。
  group('真实资产清单（回归：资产 jar 不写死文件名）', () {
    test('资产目录里的 jar 出现在 AssetManifest，且能被生产解析器落地', () async {
      final assetDir = Directory('assets/server/26_2');
      final files = assetDir.existsSync()
          ? assetDir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.toLowerCase().endsWith('.jar'))
              .toList()
          : <File>[];
      if (files.isEmpty) return; // 未放置 jar（gitignore），跳过

      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final keys = manifest
          .listAssets()
          .where((k) => k.startsWith('assets/server/26_2/'))
          .toList();
      for (final f in files) {
        expect(keys, contains('assets/server/26_2/${f.uri.pathSegments.last}'),
            reason: 'pubspec 声明了 assets/server/26_2/，清单应含目录下全部文件');
      }

      // 生产解析路径：jarPath 为空 → 走资产回退。
      final manager = LocalServerManager(Directory('${tmp.path}/prod'));
      final artifacts = await manager.resolveArtifacts(
          LocalServerConfig(id: 'a', name: 'w'));
      expect(artifacts.jar.existsSync(), isTrue, reason: '资产 jar 应落地到产物目录');
      expect(artifacts.jar.lengthSync(), files.first.lengthSync(),
          reason: '落地的 jar 字节数应与资产一致');
    });
  });
}
