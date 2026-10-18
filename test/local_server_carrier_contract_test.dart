// 承载接口的**契约测试**（change android-embedded-jvm-host / tasks 4.2）：
// 两块承载（桌面子进程 / Android 进程内 JVM）共用 `DedicatedServerCarrier` 这条面，
// 这里断言的是**规格**要求的分支，而不是某一块实现的输出：
//   · 「进程生命周期可控可观测」的**超时处置随承载方式**：
//       进程外 MAY 回落强制终止；进程内 MUST NOT 声称可单独强杀 → 转报告失败。
//   · 「输出与退出码经承载层回传」/「就绪判定仍只认原版就绪行」：
//       Android 进程内承载的日志取自实例日志文件，就绪仍以
//       `DedicatedServer.java:246` 的行为唯一判据。
import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show MethodCall, MethodChannel;
import 'package:flutter_mc/platform/server_host/android_embedded_jvm_host.dart';
import 'package:flutter_mc/platform/server_host/artifact_resolver.dart';
import 'package:flutter_mc/platform/server_host/dedicated_server_process.dart';
import 'package:flutter_mc/platform/server_host/instance_directory.dart';
import 'package:flutter_mc/platform/server_host/local_server_config.dart';
import 'package:flutter_test/flutter_test.dart';

const String _kChannel = 'flutter_mc/jvm_host';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('carrier_contract'));
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(_kChannel), null);
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('超时处置随承载方式（spec「进程生命周期可控可观测」）', () {
    test('进程外承载（桌面）：优雅停止超时后 MAY 回落到强制终止', () async {
      final instanceDir = InstanceDirectory(Directory('${tmp.path}/servers/a'));
      instanceDir.createLayout();

      // 一个"拒绝优雅停止"的假可执行文件：忽略一切参数、长时间不退。
      final script = File('${tmp.path}/fake-java.sh')
        ..writeAsStringSync('#!/bin/sh\nsleep 30\n');
      Process.runSync('chmod', <String>['+x', script.path]);
      final jar = File('${tmp.path}/server.jar')..writeAsStringSync('');

      final config = LocalServerConfig(
        id: 'a',
        name: '世界',
        // 不启用 RCON：停止只能走"等待 + 超时强杀"分支。
        stopTimeoutSeconds: 1,
      );
      File('${instanceDir.dir.path}/server.properties')
          .writeAsStringSync('enable-rcon=false\n');

      final carrier = DedicatedServerProcess(
        config: config,
        instanceDirectory: instanceDir,
      );
      await carrier.start(ServerArtifacts(
        jar: jar,
        javaExecutable: script.path,
        javaMajor: 25,
      ));
      expect(carrier.isRunning, isTrue);

      await carrier.stop();
      // 等待退出码回传（强杀后由 OS 通知）。
      await Future<void>.delayed(const Duration(milliseconds: 800));

      // 强杀 → 进程真的没了 → 状态归"已停止"（异常退出也没有残余）。
      expect(carrier.state, ServerState.stopped,
          reason: '进程外承载超时后回落强杀，服务端应已终止');
      await carrier.dispose();
    });

    test('进程内承载（Android）：优雅停止超时 MUST NOT 强杀，转报告失败并保留日志与状态',
        () async {
      final root = Directory('${tmp.path}/local_server');
      final config = LocalServerConfig(
        id: 'a',
        name: '世界',
        stopTimeoutSeconds: 1,
      );
      final instanceDir = InstanceDirectory(Directory('${root.path}/servers/a'));
      instanceDir.createLayout();
      File('${instanceDir.dir.path}/server.properties')
          .writeAsStringSync('enable-rcon=false\n');
      final jar = _fakeServerJar(tmp);
      _fakeInstalledJre(root, major: 25);

      // 通道桩：除 launchJvm 外一律立即应答；launchJvm 挂起（模拟 JVM 一直在跑）。
      final neverEnds = Completer<int>();
      final calls = <String>[];
      final runMainCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(_kChannel),
              (MethodCall call) async {
        calls.add(call.method);
        switch (call.method) {
          case 'escapeNamespaceReady':
            return true;
          case 'redirectStdio':
          case 'chdir':
          case 'createJvm':
            return 0;
          case 'dlopen':
            return 1;
          case 'runMain':
            runMainCalls.add(call);
            return neverEnds.future;
          default:
            return null;
        }
      });

      final carrier = AndroidEmbeddedJvmHost(
        config: config,
        instanceDirectory: instanceDir,
        jreRoot: Directory('${root.path}/jre'),
      );
      final starting = carrier.start(ServerArtifacts(
        jar: jar,
        javaExecutable: '${root.path}/jre/25/bin/java',
        javaMajor: 25,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(calls, contains('escapeNamespaceReady'),
          reason: '进程内承载先确认 linker 命名空间绕行可用（不可用即显式报错）');
      expect(calls, contains('redirectStdio'),
          reason: '日志来源为承载层重定向到实例日志文件（design D4）');
      expect(calls, contains('createJvm'),
          reason: '经 JNI_CreateJavaVM 在进程内建 VM（不经 launcher，故无 execve）');
      expect(calls, contains('runMain'), reason: '随后调用被托管 jar 的主类');
      // 主类取自 jar 清单（tasks 9.3），而非硬编码：桩 jar 用的是"已打补丁的服务端
      // jar"的主类（区别于 paperclip），清单写谁就该调谁。
      expect(runMainCalls.single.arguments['className'],
          'org.bukkit.craftbukkit.Main',
          reason: 'Main-Class 必须来自 jar 的 META-INF/MANIFEST.MF（真 java -jar 同口径），'
              '换 jar 后跟随新清单值');
      expect(carrier.state, ServerState.starting);

      await carrier.stop();
      expect(carrier.state, ServerState.failed,
          reason: '进程内无从单独终止该 JVM：超时转报告失败（不强杀）');
      expect(carrier.exitCode, isNull,
          reason: 'JVM 未结束 → 无退出码；状态与日志保留可观测');

      neverEnds.complete(0); // 收尾，避免挂起的 future 留在测试里
      await starting;
      await carrier.dispose();
    });
  });

  group('日志来源与就绪判定（Android 进程内承载）', () {
    test('就绪仍只认原版就绪行，端口取原版日志行（判据 DedicatedServer.java:246 / :210）',
        () async {
      final root = Directory('${tmp.path}/local_server');
      final config = LocalServerConfig(id: 'a', name: '世界', port: 25565);
      final instanceDir = InstanceDirectory(Directory('${root.path}/servers/a'));
      instanceDir.createLayout();
      File('${instanceDir.dir.path}/server.properties')
          .writeAsStringSync('enable-rcon=false\n');
      final jar = _fakeServerJar(tmp);
      _fakeInstalledJre(root, major: 25);

      final neverEnds = Completer<int>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(_kChannel),
              (MethodCall call) async {
        switch (call.method) {
          case 'escapeNamespaceReady':
            return true;
          case 'redirectStdio':
          case 'chdir':
          case 'createJvm':
            return 0;
          case 'dlopen':
            return 1;
          case 'runMain':
            return neverEnds.future;
          default:
            return null;
        }
      });

      final carrier = AndroidEmbeddedJvmHost(
        config: config,
        instanceDirectory: instanceDir,
        jreRoot: Directory('${root.path}/jre'),
      );
      final starting = carrier.start(ServerArtifacts(
        jar: jar,
        javaExecutable: '${root.path}/jre/25/bin/java',
        javaMajor: 25,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 300));

      // 非就绪行不足以判就绪。
      final log = File('${instanceDir.dir.path}/logs/host-console.log');
      log.writeAsStringSync('[12:00:00] Preparing level "world"\n', mode: FileMode.append);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(carrier.state, ServerState.starting,
          reason: '未出现原版就绪行时不得判就绪（MUST NOT 以"进程已启动"替代）');

      // 原版监听端口行 + 原版就绪行（判据 DedicatedServer.java:210 / :246）。
      log.writeAsStringSync(
        'Starting Minecraft server on *:25565\n'
        'Done (2.345s)! For help, type "help"\n',
        mode: FileMode.append,
      );
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(carrier.state, ServerState.ready);
      expect(carrier.listeningPort, 25565);
      expect(carrier.recentLogs, contains('Done (2.345s)! For help, type "help"'));

      neverEnds.complete(0);
      await starting;
      await carrier.dispose();
    });

    test('生命周期不以主类 main 返回值判停：就绪认就绪行，停机认原版停机行'
        '（判据 Main.java:201-217 / DedicatedServer.java:246 / MinecraftServer.java:650）',
        () async {
      final root = Directory('${tmp.path}/local_server');
      final config = LocalServerConfig(id: 'a', name: '世界', port: 25565);
      final instanceDir = InstanceDirectory(Directory('${root.path}/servers/a'));
      instanceDir.createLayout();
      File('${instanceDir.dir.path}/server.properties')
          .writeAsStringSync('enable-rcon=false\n');
      final jar = _fakeServerJar(tmp);
      _fakeInstalledJre(root, major: 25);

      // 预置"上一次运行"的日志（日志是同实例目录下**追加写**共用的文件）：
      // 本次起服的读取起点 MUST 落在本次分界行之后，否则会把上一次的停机行当成本次的。
      Directory('${instanceDir.dir.path}/logs').createSync(recursive: true);
      File('${instanceDir.dir.path}/logs/host-console.log').writeAsStringSync(
          '[old] Done (1.000s)! For help, type "help"\n'
          '[Server thread/INFO]: Stopping server\n');

      // 桩：`runMain` **立即**返回 0 —— 模拟 paperclip：主类 main 另起 Server thread 后即刻返回。
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(_kChannel),
              (MethodCall call) async {
        switch (call.method) {
          case 'escapeNamespaceReady':
            return true;
          case 'redirectStdio':
          case 'chdir':
          case 'createJvm':
            return 0;
          case 'dlopen':
            return 1;
          case 'runMain':
            return 0;
          default:
            return null;
        }
      });

      final carrier = AndroidEmbeddedJvmHost(
        config: config,
        instanceDirectory: instanceDir,
        jreRoot: Directory('${root.path}/jre'),
      );
      await carrier.start(ServerArtifacts(
        jar: jar,
        javaExecutable: '${root.path}/jre/25/bin/java',
        javaMajor: 25,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 300));

      // 关键断言：main 已返回，但服务端仍在同一 JVM 的 Server thread 上跑 → 状态不得变。
      expect(carrier.state, ServerState.starting,
          reason: 'main 返回 ≠ 服务端结束：不得据此判停（否则真机上就绪行到达前就被误判 stopped）');

      final log = File('${instanceDir.dir.path}/logs/host-console.log');
      log.writeAsStringSync('Done (2.345s)! For help, type "help"\n',
          mode: FileMode.append);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(carrier.state, ServerState.ready, reason: '就绪仍只认原版就绪行');

      // 停机：原版 `stopServer()` 的 `Stopping server`（MinecraftServer.java:650）。
      log.writeAsStringSync('[Server thread/INFO]: Stopping server\n',
          mode: FileMode.append);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(carrier.state, ServerState.stopped, reason: '停机只认原版停机行');
      expect(carrier.exitCode, 0,
          reason: '进程内拿不到真实退出码，优雅停机回传 0（登记 progress.md 16.3）');

      await carrier.dispose();
    });

    test('进程内承载的 reap 为空操作（宿主终止即服务端终止，MUST NOT 残留孤儿进程）',
        () async {
      final root = Directory('${tmp.path}/local_server');
      final config = LocalServerConfig(id: 'a', name: '世界');
      final instanceDir = InstanceDirectory(Directory('${root.path}/servers/a'));
      final carrier = AndroidEmbeddedJvmHost(
        config: config,
        instanceDirectory: instanceDir,
        jreRoot: Directory('${root.path}/jre'),
      );
      carrier.reap(); // 不应抛错、不应尝试终止任何东西
      expect(carrier.state, ServerState.stopped);
      await carrier.dispose();
    });
  });
}

/// 伪造一份"已安装的 arm64 JRE"，让 Android 承载的路径口径可解析
/// （不依赖真实产物：产物因许可原因不入库）。
void _fakeInstalledJre(Directory root, {required int major}) {
  final jre = Directory('${root.path}/jre/$major')..createSync(recursive: true);
  File('${jre.path}/release')
      .writeAsStringSync('OS_ARCH="aarch64"\nJAVA_VERSION="25.0.2"\n'); // 口径照 FCLauncher.getJavaLibDir
  File('${jre.path}/version').writeAsStringSync('3');
  File('${jre.path}/bin/java').createSync(recursive: true);
  File('${jre.path}/lib/aarch64/jli/libjli.so').createSync(recursive: true);
  File('${jre.path}/lib/aarch64/server/libjvm.so').createSync(recursive: true);
}

/// 伪造一份**结构真实**的被托管 jar：真 zip + 主清单 `Main-Class`。
///
/// 主类故意用 `org.bukkit.craftbukkit.Main`（= 已打补丁的服务端 jar 的主类，区别于
/// paperclip 引导 jar 的 `io.papermc.paperclip.Main`）——换 jar 后主类必须**跟随清单**
/// 而非残留硬编码（tasks 9.3 的验证口径在契约层的等价物）。
File _fakeServerJar(Directory tmp) {
  const manifest = 'Manifest-Version: 1.0\r\n'
      'Main-Class: org.bukkit.craftbukkit.Main\r\n'
      '\r\n';
  final archive = Archive()
    ..add(ArchiveFile.bytes('META-INF/MANIFEST.MF', manifest.codeUnits));
  return File('${tmp.path}/server.jar')
    ..writeAsBytesSync(ZipEncoder().encode(archive));
}
