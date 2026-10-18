// 承载接口的**契约测试**（change android-subprocess-jvm-host / tasks 3.4）：
// 两块承载（桌面子进程 / Android `:jvm` 子进程）共用 `DedicatedServerCarrier` 这条面，
// 这里断言的是**规格**要求的分支，而不是某一块实现的输出：
//   · 「进程生命周期可控可观测」：所有承载优雅停止超时后 SHALL 回落强制终止。
//   · 「输出与退出码经承载层回传」/「就绪判定仍只认原版就绪行」：
//       Android 承载的日志取自实例日志文件，就绪以 `DedicatedServer.java:246` 为唯一判据；
//       退出码取自子进程结果文件（真实退出码，撤销"回传 0"退化）。
//   · 「上一会话残留可检出」：pidFile 未清（子进程未退净）时 MUST NOT 重入承载逻辑。
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show MethodCall, MethodChannel;
import 'package:flutter_mc/platform/server_host/android_subprocess_jvm_host.dart';
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
  });

  group('日志来源与就绪判定（Android :jvm 子进程承载）', () {
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

      // 通道桩：模拟子进程行为——startJvmService 后写 pidFile；killPid 记录调用。
      final kills = <int>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(_kChannel),
              (MethodCall call) async {
        switch (call.method) {
          case 'startJvmService':
            // 子进程异步写 pidFile（照真实 child：启动后上报 pid）。
            Future<void>(() async {
              await Future<void>.delayed(const Duration(milliseconds: 100));
              File('${root.path}/sandbox.pid').writeAsStringSync('4321');
              // 子进程自写心跳（父进程判活依据；一次写入 12s 内测试结束，视作新鲜）。
              File('${root.path}/sandbox-child-heartbeat')
                  .writeAsStringSync(DateTime.now().toIso8601String());
            });
            return null;
          case 'nativeLibraryDir':
            return '${tmp.path}/nativelib';
          case 'killPid':
            kills.add(call.arguments['pid'] as int);
            return 0;
          default:
            return null;
        }
      });

      final carrier = AndroidSubprocessJvmHost(
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
      final log = _sessionLog(instanceDir);
      log.writeAsStringSync('[12:00:00] Preparing level "world"\n',
          mode: FileMode.append);
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

      // 收尾：停机行 → 模拟子进程退净（哨兵删 pidFile → 结果文件）→ 状态归 stopped。
      log.writeAsStringSync('[Server thread/INFO]: Stopping server\n',
          mode: FileMode.append);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      File('${root.path}/sandbox.pid').deleteSync();
      File('${root.path}/sandbox-result.txt')
          .writeAsStringSync('mainExitCode=0\nstopConfirmed=true\n');
      await starting;
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(carrier.state, ServerState.stopped, reason: '停机行后子进程退净 ⇒ stopped');
      expect(carrier.exitCode, 0, reason: '退出码取自结果文件（真实退出码）');
      expect(kills, isEmpty, reason: '正常退净不需要强杀');
      await carrier.dispose();
    });

    test('退出码可观测：结果文件里的非 0 退出码透传（撤销"回传 0"退化）', () async {
      final root = Directory('${tmp.path}/local_server');
      final config = LocalServerConfig(id: 'a', name: '世界', port: 25565);
      final instanceDir = InstanceDirectory(Directory('${root.path}/servers/a'));
      instanceDir.createLayout();
      File('${instanceDir.dir.path}/server.properties')
          .writeAsStringSync('enable-rcon=false\n');
      final jar = _fakeServerJar(tmp);
      _fakeInstalledJre(root, major: 25);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(_kChannel),
              (MethodCall call) async {
        switch (call.method) {
          case 'startJvmService':
            Future<void>(() async {
              await Future<void>.delayed(const Duration(milliseconds: 100));
              File('${root.path}/sandbox.pid').writeAsStringSync('4321');
              // 子进程自写心跳（父进程判活依据；一次写入 12s 内测试结束，视作新鲜）。
              File('${root.path}/sandbox-child-heartbeat')
                  .writeAsStringSync(DateTime.now().toIso8601String());
            });
            return null;
          case 'nativeLibraryDir':
            return '';
          default:
            return null;
        }
      });

      final carrier = AndroidSubprocessJvmHost(
        config: config,
        instanceDirectory: instanceDir,
        jreRoot: Directory('${root.path}/jre'),
      );
      final starting = carrier.start(ServerArtifacts(
        jar: jar,
        javaExecutable: '${root.path}/jre/25/bin/java',
        javaMajor: 25,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 400));

      // 异常退出（无停机行）：结果文件回传非 0（vmExited 路径）→ 死亡监视转 failed。
      final log = _sessionLog(instanceDir);
      log.writeAsStringSync('Done (2.345s)! For help, type "help"\n',
          mode: FileMode.append);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      // 子进程收尾：结果文件（exit 拦截层写）+ pidFile 清理。
      File('${root.path}/sandbox.pid').deleteSync();
      File('${root.path}/sandbox-result.txt').writeAsStringSync(
          'mainExitCode=0\nstopConfirmed=false\nexitStatus=70\nvmExited=true\n');
      await Future<void>.delayed(const Duration(milliseconds: 600));

      expect(carrier.state, ServerState.failed,
          reason: '无原版停机行 ⇒ 非优雅收尾，转 failed（spec「崩溃可观测」）');
      expect(carrier.exitCode, 70,
          reason: '退出码取自 exit 拦截层回传的真实 OS 退出码，MUST 与优雅停止可区分'
              '（spec「退出码可观测」）');

      await starting;
      await carrier.dispose();
    });

    test('优雅停止超时回落强制终止：nativeKill 下发 + 强杀后归 stopped（exitCode 137）',
        () async {
      final root = Directory('${tmp.path}/local_server');
      final config = LocalServerConfig(id: 'a', name: '世界', stopTimeoutSeconds: 1);
      final instanceDir = InstanceDirectory(Directory('${root.path}/servers/a'));
      instanceDir.createLayout();
      // 不启用 RCON：停止只能走"等待 + 超时强杀"分支。
      File('${instanceDir.dir.path}/server.properties')
          .writeAsStringSync('enable-rcon=false\n');
      final jar = _fakeServerJar(tmp);
      _fakeInstalledJre(root, major: 25);

      final kills = <int>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(_kChannel),
              (MethodCall call) async {
        switch (call.method) {
          case 'startJvmService':
            Future<void>(() async {
              await Future<void>.delayed(const Duration(milliseconds: 100));
              File('${root.path}/sandbox.pid').writeAsStringSync('4321');
              // 子进程自写心跳（父进程判活依据；一次写入 12s 内测试结束，视作新鲜）。
              File('${root.path}/sandbox-child-heartbeat')
                  .writeAsStringSync(DateTime.now().toIso8601String());
            });
            return null;
          case 'nativeLibraryDir':
            return '';
          case 'killPid':
            kills.add(call.arguments['pid'] as int);
            return 0;
          default:
            return null;
        }
      });

      final carrier = AndroidSubprocessJvmHost(
        config: config,
        instanceDirectory: instanceDir,
        jreRoot: Directory('${root.path}/jre'),
      );
      final starting = carrier.start(ServerArtifacts(
        jar: jar,
        javaExecutable: '${root.path}/jre/25/bin/java',
        javaMajor: 25,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(carrier.state, ServerState.starting);

      // 无 RCON、子进程永不退净 → 超时 → 强杀回落（pidFile 由承载层清理）。
      await carrier.stop();

      expect(kills, [4321],
          reason: '超时后对承载子进程 nativeKill（spec「提供强制终止」）');
      expect(carrier.state, ServerState.stopped, reason: '强杀即终止（与桌面子进程承载同构）');
      expect(carrier.exitCode, 137, reason: '137 = 128+SIGKILL，强杀可观测');
      expect(File('${root.path}/sandbox.pid').existsSync(), isFalse,
          reason: 'SIGKILL 下子进程不会自删 pidFile，承载层负责清理');

      starting.catchError((Object _) {});
      await carrier.dispose();
    });

    test('上一会话残留可检出：pidFile 存在且心跳新鲜 ⇒ 拒绝重入（spec 新增场景）',
        () async {
      final root = Directory('${tmp.path}/local_server');
      final config = LocalServerConfig(id: 'a', name: '世界');
      final instanceDir = InstanceDirectory(Directory('${root.path}/servers/a'));
      instanceDir.createLayout();
      File('${instanceDir.dir.path}/server.properties')
          .writeAsStringSync('enable-rcon=false\n');
      final jar = _fakeServerJar(tmp);
      _fakeInstalledJre(root, major: 25);

      var serviceStarts = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(_kChannel),
              (MethodCall call) async {
        switch (call.method) {
          case 'startJvmService':
            serviceStarts++;
            return null;
          case 'nativeLibraryDir':
            return '';
          default:
            return null;
        }
      });

      final carrier = AndroidSubprocessJvmHost(
        config: config,
        instanceDirectory: instanceDir,
        jreRoot: Directory('${root.path}/jre'),
      );

      // 模拟"上一会话子进程还活着"：pidFile 残留 + child 心跳新鲜。
      File('${root.path}/sandbox.pid').writeAsStringSync('4321');
      File('${root.path}/sandbox-child-heartbeat')
          .writeAsStringSync(DateTime.now().toIso8601String());

      await expectLater(
        carrier.start(ServerArtifacts(
          jar: jar,
          javaExecutable: '${root.path}/jre/25/bin/java',
          javaMajor: 25,
        )),
        throwsStateError,
        reason: '上一承载子进程未退净时 MUST NOT 重入承载逻辑（spec「上一会话残留可检出」）',
      );
      expect(serviceStarts, 0, reason: '拒绝重入 ⇒ 不得 startService');
      expect(carrier.state, ServerState.failed);
      await carrier.dispose();
    });

    test('死会话的 pidFile 磁盘残留自动清理（心跳已停 ⇒ 视为上一 app 会话残留）',
        () async {
      final root = Directory('${tmp.path}/local_server');
      final config = LocalServerConfig(id: 'a', name: '世界', port: 25565);
      final instanceDir = InstanceDirectory(Directory('${root.path}/servers/a'));
      instanceDir.createLayout();
      File('${instanceDir.dir.path}/server.properties')
          .writeAsStringSync('enable-rcon=false\n');
      final jar = _fakeServerJar(tmp);
      _fakeInstalledJre(root, major: 25);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(_kChannel),
              (MethodCall call) async {
        switch (call.method) {
          case 'startJvmService':
            Future<void>(() async {
              await Future<void>.delayed(const Duration(milliseconds: 100));
              File('${root.path}/sandbox.pid').writeAsStringSync('4321');
              // 子进程自写心跳（父进程判活依据；一次写入 12s 内测试结束，视作新鲜）。
              File('${root.path}/sandbox-child-heartbeat')
                  .writeAsStringSync(DateTime.now().toIso8601String());
            });
            return null;
          case 'nativeLibraryDir':
            return '';
          default:
            return null;
        }
      });

      final carrier = AndroidSubprocessJvmHost(
        config: config,
        instanceDirectory: instanceDir,
        jreRoot: Directory('${root.path}/jre'),
      );

      // pidFile 残留 + child 心跳陈旧（上次 app 会话被 force-stop，child 来不及自删）。
      File('${root.path}/sandbox.pid').writeAsStringSync('999');
      final stale = DateTime.now().subtract(const Duration(minutes: 5));
      final childHeartbeat = File('${root.path}/sandbox-child-heartbeat')
        ..writeAsStringSync('stale');
      childHeartbeat.setLastModifiedSync(stale);

      await carrier.start(ServerArtifacts(
        jar: jar,
        javaExecutable: '${root.path}/jre/25/bin/java',
        javaMajor: 25,
      ));
      expect(carrier.state, ServerState.starting,
          reason: '死会话残留自动清理后正常起承载');

      // 收尾：停机行 → 子进程退净 → stopped。
      final log = _sessionLog(instanceDir);
      log.writeAsStringSync('Done (2.345s)! For help, type "help"\n',
          mode: FileMode.append);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      log.writeAsStringSync('[Server thread/INFO]: Stopping server\n',
          mode: FileMode.append);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      File('${root.path}/sandbox.pid').deleteSync();
      File('${root.path}/sandbox-result.txt')
          .writeAsStringSync('mainExitCode=0\nstopConfirmed=true\n');
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(carrier.state, ServerState.stopped);
      await carrier.dispose();
    });
  });
}


/// 取当前会话的日志文件（carrier 每会话生成 `host-console-<时间戳>.log`，取最新）。
File _sessionLog(InstanceDirectory instanceDir) {
  final logs = Directory('${instanceDir.dir.path}/logs')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.contains('host-console-'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return logs.last;
}

/// 伪造一份**结构真实**的被托管 jar：真 zip + 主清单 `Main-Class`。
///
/// 主类故意用 `org.bukkit.craftbukkit.Main`（= 已打补丁的服务端 jar 的主类，区别于
/// paperclip 引导 jar 的 `io.papermc.paperclip.Main`）——换 jar 后主类必须**跟随清单**
/// 而非残留硬编码（归档 change tasks 9.3 的验证口径在契约层的等价物）。
File _fakeServerJar(Directory tmp) {
  const manifest = 'Manifest-Version: 1.0\r\n'
      'Main-Class: org.bukkit.craftbukkit.Main\r\n'
      '\r\n';
  final archive = Archive()
    ..add(ArchiveFile.bytes('META-INF/MANIFEST.MF', manifest.codeUnits));
  return File('${tmp.path}/server.jar')
    ..writeAsBytesSync(ZipEncoder().encode(archive));
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
