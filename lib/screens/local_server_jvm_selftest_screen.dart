// 宿主承载层的**真机取证**入口（`--dart-define=MC_JVM_SELFTEST=1` 时经 `/jvm-selftest` 进入）。
//
//   与既有 `/autojoin`（`--dart-define=AUTOJOIN=<ip:port>`）同性质：免去手动点 UI，
//   启动即按**真实流程**跑一遍并逐步打日志——探针场景无需 UI 反馈。
//
//   它**不是** spike（不另写承载实现），走的就是生产路径：
//     实例初始化 → EULA 门槛 → 产物解析（Android 上含 arm64 JRE 安装）→ 承载启动 →
//     等原版就绪行 → RCON 控制面 → 优雅停止 → 退出码。
//   用途：验证 spec「载体在应用进程内承载 JVM」「产物安装于应用私有目录」
//   「输出与退出码经承载层回传」「控制面只走原版通道」在真机成立。
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mc_server/mc_server.dart';
import 'package:mc_session/mc_session.dart' show ServerData;

import '../platform/server_host/dedicated_server_carrier.dart';
import '../platform/server_host/local_server_config.dart';
import '../platform/server_host/local_server_host.dart';
import 'multiplayer/join_flow.dart'
    show defaultJoinConnector, joinServer, kPlayerName;

/// 自检实例用的端口（避开默认 25565/25575/25585，防止与用户实例冲突）。
const int kSelfTestPort = 25566;
const int kSelfTestRconPort = 25576;
const int kSelfTestManagementPort = 25586;

/// 等原版就绪行的上限（首启 paperclip 要拉依赖，给足时间）。
const Duration kSelfTestReadyTimeout = Duration(minutes: 10);

/// 取证模式（`--dart-define=MC_JVM_SELFTEST_MODE`）：
///   · 空 / `full` —— 正常全流程（起 Paper → 就绪 → RCON → 停止）
///   · `client`    —— 起服就绪后经**生产 joinServer 流程**连入 `127.0.0.1:<端口>`
///                    （与 AUTOJOIN 同一入口），用 RCON `list` 看到玩家作为
///                    "客户端已连入"的证据（tasks 8.1 的客户端连接判据）。
///   · `soak`      —— 见 [kSelfTestSoakSecs]（前台服务/退后台取证用保持窗口）。
const String kSelfTestMode = String.fromEnvironment('MC_JVM_SELFTEST_MODE');

/// soak 保持秒数（`--dart-define=MC_JVM_SELFTEST_SOAK_SECS`）：就绪（及 client 模式
/// 连入）后让服务端**持续运行**这么多秒再停止——供前台服务/退后台取证
/// （tasks 6.1/6.2「退到后台不断线」「服务可常驻不被回收」）。0 或未设 = 不保持。
final int kSelfTestSoakSecs =
    int.tryParse(const String.fromEnvironment('MC_JVM_SELFTEST_SOAK_SECS')) ??
    0;

class LocalServerJvmSelfTestScreen extends StatefulWidget {
  const LocalServerJvmSelfTestScreen({super.key});

  @override
  State<LocalServerJvmSelfTestScreen> createState() =>
      _LocalServerJvmSelfTestScreenState();
}

class _LocalServerJvmSelfTestScreenState
    extends State<LocalServerJvmSelfTestScreen> {
  final List<String> _lines = <String>[];
  String _verdict = '运行中…';

  static void _log(String line) {
    // 前缀便于 `adb logcat` 过滤：`adb logcat | grep JVM-SELFTEST`。
    debugPrint('[JVM-SELFTEST] $line');
  }

  void _append(String line) {
    _log(line);
    if (mounted) setState(() => _lines.add(line));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  Future<void> _run() async {
    final manager = localServerManager;
    final config = LocalServerConfig(
      id: 'selftest',
      name: 'JVM 自检',
      port: kSelfTestPort,
      rconPort: kSelfTestRconPort,
      managementServerPort: kSelfTestManagementPort,
      // 自检用较小堆，避免受真机内存限制干扰（与承载正确性无关）。
      jvmArgs: const <String>['-Xms1G', '-Xmx2G'],
    );
    DedicatedServerCarrier? carrier;
    var exitCode = -1;
    // twice 模式（tasks 4.1）：**同一 app 会话内连跑两轮**起停——直接回归
    // "退出世界后无法再进"（旧进程内承载的二次起服静默夭折）。
    final cycles = kSelfTestMode == 'twice' ? 2 : 1;
    try {
      _append('主机根：${manager.root.path}');
      for (var cycle = 1; cycle <= cycles; cycle++) {
        if (cycles > 1) _append('—— 第 $cycle/$cycles 轮 ——');

        // 1) 实例初始化（原版文件名；首启写 server.properties）。
        final dir = manager.instanceDirectoryFor(config);
        dir.createLayout();
        // 共享缓存 → 本实例（有则免首启下载；空则不动）。
        final copied = await dir.pullSharedCache();
        dir.writeInitialPropertiesIfAbsent(config);
        dir.ensureProperties(config);
        _append('实例目录：${dir.dir.path}（共享缓存复制 $copied 个文件）');

        // 2) EULA 门槛（复用语义照 Eula.java 的翻译件，不绕过）。
        manager.eulaGateFor(config).agree();
        _append('EULA：已同意（eula=true）');

        // 3) 产物解析：Android 上这一步会先安装 arm64 JRE 到应用私有目录。
        final artifacts = await manager.resolveArtifacts(config);
        _append(
          '产物：jar=${artifacts.jar.path}（${artifacts.jar.lengthSync()} B）'
          ' java=${artifacts.javaExecutable} major=${artifacts.javaMajor}',
        );

        // 4) 承载启动。
        carrier = manager.processFor(config);
        _append('承载实现：${carrier.runtimeType}');
        final ready = Completer<bool>();
        final sub = carrier.stateChanges.listen((s) {
          _append('状态：$s');
          if (s == ServerState.ready && !ready.isCompleted) {
            ready.complete(true);
          }
          if (s == ServerState.failed && !ready.isCompleted) {
            ready.complete(false);
          }
        });
        final started = carrier.start(artifacts);
        // 起 JVM 是阻塞调用：失败时 start 抛错（例如命名空间绕行不可用）。
        unawaited(
          started.catchError((Object e) {
            _append('启动失败：$e');
            if (!ready.isCompleted) ready.complete(false);
          }),
        );

        final ok = await ready.future.timeout(
          kSelfTestReadyTimeout,
          onTimeout: () => false,
        );
        if (!ok) {
          _append(
            '未在时限内就绪。最近日志：'
            '${carrier.recentLogs.reversed.take(30).join(" | ")}',
          );
          _verdict = '失败：未就绪';
          await sub.cancel();
          return;
        }
        _append('已就绪，端口=${carrier.listeningPort}');

        // 5) 控制面：经**原版 RCON** 通道下发 `list`（MUST NOT 自造协议）。
        //
        //    ⚠ RCON 监听与就绪行**不同时**出现：原版 `initServer()` 打完就绪行之后才创建
        //    RCON 监听（判据 `DedicatedServer.java:245` → `:255-258`
        //    `Starting remote control listener` / `RCON running on {}:{}`）。Paper 的实机
        //    输出顺序亦可相反（实测其就绪行打在 RCON 之后），故这里对"监听尚未就绪"的
        //    `Connection refused` 做**重试**，而不当成起服失败。
        final props = DedicatedServerProperties(
          Settings.loadFromFile(dir.serverProperties.path),
        );
        late RconClient client;
        for (var attempt = 1; ; attempt++) {
          try {
            client = await RconClient.connect(
              '127.0.0.1',
              props.rconPort,
              timeout: const Duration(seconds: 3),
            );
            break;
          } on SocketException catch (e) {
            if (attempt >= 15) rethrow; // 上限 ~30 秒
            _append('RCON 尚未监听（第 $attempt 次）：${e.osError?.message}');
            await Future<void>.delayed(const Duration(seconds: 2));
          }
        }
        final authed = await client.authenticate(props.rconPassword);
        _append('RCON 鉴权：$authed');
        final reply = await client.execCommand('list');
        _append('RCON list → $reply');
        await client.close();

        // 5.5) client 模式：经生产 joinServer 流程连入本机托管的服务端（tasks 8.1
        //      判据「客户端 127.0.0.1 连接」）。joinServer 成功后内部 push '/game'；
        //      本屏留在栈下继续取证。玩家在线的证据 = RCON `list` 出现玩家名。
        var playerOnline = false;
        if (kSelfTestMode == 'client') {
          _append('client 模式：经生产 joinServer 连入 127.0.0.1:$kSelfTestPort');
          if (mounted) {
            unawaited(
              joinServer(
                context,
                server: ServerData(
                  name: '127.0.0.1:$kSelfTestPort',
                  ip: '127.0.0.1:$kSelfTestPort',
                ),
                connector: defaultJoinConnector,
              ),
            );
          } else {
            _append('无法发起连入：本屏已不在组件树上');
          }
          for (var attempt = 1; attempt <= 20; attempt++) {
            await Future<void>.delayed(const Duration(seconds: 3));
            try {
              final c = await RconClient.connect(
                '127.0.0.1',
                props.rconPort,
                timeout: const Duration(seconds: 3),
              );
              try {
                if (!await c.authenticate(props.rconPassword)) {
                  _append('RCON 鉴权失败（第 $attempt 次）');
                  continue;
                }
                final list = await c.execCommand('list');
                _append('RCON list（连入后第 $attempt 次）→ $list');
                if (list.contains(kPlayerName)) {
                  playerOnline = true;
                  break;
                }
              } finally {
                await c.close();
              }
            } catch (e) {
              _append('RCON 轮询失败（第 $attempt 次）：$e');
            }
          }
          _append(
            playerOnline
                ? '客户端已连入（RCON list 见玩家 $kPlayerName）'
                : '客户端未连入（RCON list 未出现玩家 $kPlayerName）',
          );
        }

        // 5.6) soak：保持运行（供前台服务/退后台取证；见 [kSelfTestSoakSecs]）。
        if (kSelfTestSoakSecs > 0) {
          _append('soak：保持服务端运行 $kSelfTestSoakSecs 秒（供前台服务/退后台取证）');
          for (var i = 1; i <= kSelfTestSoakSecs; i++) {
            await Future<void>.delayed(const Duration(seconds: 1));
            if (i % 15 == 0) {
              _append(
                'soak：已保持 ${i}s 状态=${carrier.state} 端口=${carrier.listeningPort}',
              );
            }
          }
          _append('soak 结束：状态=${carrier.state}');
        }

        // 6) 优雅停止（RCON `stop`）→ 等退出码回传。
        await carrier.stop();
        await Future<void>.delayed(const Duration(seconds: 2));
        exitCode = carrier.exitCode ?? -1;
        _append('停止后状态=${carrier.state} 退出码=$exitCode');
        final clientOk = kSelfTestMode != 'client' || playerOnline;
        _verdict = carrier.state == ServerState.stopped && clientOk
            ? '通过：启动→就绪(RCON 可用)${kSelfTestMode == 'client' ? '→客户端连入' : ''}→优雅停止(退出码 $exitCode)'
            : '失败：停止后状态=${carrier.state}${clientOk ? '' : '（客户端未连入）'}';
        await sub.cancel();
        if (carrier.state != ServerState.stopped) return; // 任一轮失败即止
      }
    } catch (e, st) {
      _append('异常：$e\n$st');
      _verdict = '失败：$e';
    } finally {
      // 结果落盘，便于从设备取回（adb pull / run-as）。
      try {
        File('${manager.root.path}/selftest-result.txt').writeAsStringSync(
          'verdict: $_verdict\nexitCode: $exitCode\n\n${_lines.join("\n")}\n',
        );
      } catch (_) {}
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'JVM 自检：$_verdict',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  _lines.join('\n'),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
