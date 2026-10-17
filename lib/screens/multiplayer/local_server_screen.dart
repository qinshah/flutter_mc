// 本地服务器条目屏：状态 / 启动停止 / 日志面板 / 配置编辑 / "启动并进入世界"。
//
// 原版对应物：这是 `gui/screens/Multiplayer` 里"条目 → 详情"的形态在**宿主**场景下的
// 落地——原版没有"托管本地服务端"的界面，本屏属第三类自由设计「运行时宿主」的 UI 呈现
//（design.md D8：进程承载、就绪判定、生命周期与 EULA 对话框都在 app 壳）。
// 进世界复用既有 `remote-play` 通路（`join_flow.dart` 的 joinServer），无新代码路径（spec 4.2）。
import 'dart:async';
import 'dart:io' show SocketException;

import 'package:flutter/material.dart';
import 'package:mc_server/mc_server.dart';
import 'package:mc_session/mc_session.dart';
import 'package:mc_ui/mc_ui.dart';

import '../../platform/server_host/artifact_resolver.dart';
import '../../platform/server_host/dedicated_server_process.dart';
import '../../platform/server_host/eula_gate.dart';
import '../../platform/server_host/instance_directory.dart';
import '../../platform/server_host/local_server_config.dart';
import '../../platform/server_host/local_server_host.dart';
import '../screen.dart';
import 'join_flow.dart';
import 'local_server_config_dialog.dart';
import 'local_server_ports_dialog.dart';

/// 就绪等待上限（首次启动要拉 vanilla jar 与 libraries，给足时间；超时即报未就绪）。
const Duration kReadyTimeout = Duration(minutes: 5);

class LocalServerScreen extends StatefulWidget {
  const LocalServerScreen({
    super.key,
    required this.manager,
    required this.config,
    this.playMode = false,
  });

  final LocalServerManager manager;
  final LocalServerConfig config;

  /// 进世界模式（单机世界列表的「进入世界」）：
  /// 进屏即走启动流程 → 等就绪 → 连入；**不显示日志/RCON 控制台**；
  /// 退出游戏（`/game` 返回）后**停止服务器**并返回上层。
  /// 管理形态（`false`，多人游戏 → 本地服务器）则保留日志与控制台，由用户手动启停。
  final bool playMode;

  @override
  State<LocalServerScreen> createState() => _LocalServerScreenState();
}

class _LocalServerScreenState extends State<LocalServerScreen> {
  ServerArtifacts? _artifacts;
  String? _artifactError;
  bool _resolving = true;

  ServerState _state = ServerState.stopped;
  int? _exitCode;
  StreamSubscription<ServerState>? _stateSub;
  StreamSubscription<String>? _logSub;
  final List<String> _logs = <String>[];
  final ScrollController _scroll = ScrollController();
  bool _busy = false;
  final TextEditingController _command = TextEditingController();

  DedicatedServerProcess get _process =>
      widget.manager.processFor(widget.config);

  InstanceDirectory get _dir =>
      widget.manager.instanceDirectoryFor(widget.config);

  @override
  void initState() {
    super.initState();
    _attach();
    unawaited(_resolve());
    if (widget.playMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_start(join: true));
      });
    }
  }

  void _attach() {
    final p = _process;
    _state = p.state;
    _exitCode = p.exitCode;
    _logs
      ..clear()
      ..addAll(p.recentLogs);
    _stateSub = p.stateChanges.listen((s) {
      if (!mounted) return;
      setState(() {
        _state = s;
        _exitCode = p.exitCode;
      });
      // 就绪即说明 paperclip 的引导产物已下齐 → 回写共享缓存给后续世界复用
      // （只在共享目录还空着时做；不 await，避免拖住状态刷新）。
      if (s == ServerState.ready) unawaited(_dir.pushSharedCache());
    });
    _logSub = p.logLines.listen((line) {
      if (!mounted) return;
      setState(() {
        _logs.add(line);
        if (_logs.length > 500) _logs.removeAt(0);
      });
      _autoScroll();
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _logSub?.cancel();
    _scroll.dispose();
    _command.dispose();
    super.dispose();
  }

  void _autoScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  /// 产物解析（版本锚点 + jar + JVM）。失败时入口置灰并展示原因（spec 3.1 的降级）。
  Future<void> _resolve() async {
    setState(() => _resolving = true);
    try {
      final arts = await widget.manager.resolveArtifacts(widget.config);
      if (!mounted) return;
      setState(() {
        _artifacts = arts;
        _artifactError = null;
        _resolving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _artifacts = null;
        _artifactError = e.toString();
        _resolving = false;
      });
    }
  }

  bool get _canStart =>
      !_busy && !_resolving && _artifactError == null && _artifacts != null;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final s = mcScaleForWidth(constraints.maxWidth);
      return McScreen(
        title: widget.playMode
            ? '进入世界：${widget.config.name}'
            : '本地服务器：${widget.config.name}',
        body: (context) => widget.playMode ? _playBody(s) : _manageBody(s),
      );
    });
  }

  /// 进世界形态：只有状态与进度，**不显示日志/RCON**（用户要求单机不露这些）。
  Widget _playBody(double s) {
    final text = switch (_state) {
      ServerState.stopped => '正在准备…',
      // "需下载依赖"只在**真缺依赖**时才说（判据见 `InstanceDirectory.hasCachedDependencies`）：
      // 依赖已在实例目录里时 paperclip 直接复用缓存，不再下载。旧版这里是写死文案，每次进世界
      // 都这么提示，属于误导。
      ServerState.starting => _dir.hasCachedDependencies
          ? '正在启动本地服务器…'
          : '正在启动本地服务器…（首次启动需下载运行依赖，可能较久）',
      ServerState.ready => '正在进入世界…',
      ServerState.stopping => '正在停止本地服务器…',
      ServerState.failed => '启动失败（退出码 ${_exitCode ?? "?"}）',
    };
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 6 * s),
          child: _statusBar(s),
        ),
        SizedBox(height: 4 * s),
        Expanded(
          child: Center(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: const Color(0xFFE0E0E0), fontSize: 7 * s),
            ),
          ),
        ),
        if (_artifactError != null)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 6 * s),
            child: Text(
              _artifactError!,
              style: TextStyle(color: const Color(0xFFFF8080), fontSize: 6 * s),
            ),
          ),
        Padding(
          padding: EdgeInsets.all(4 * s),
          child: Row(
            children: [
              Expanded(
                child: MCButton(
                  height: 20 * s,
                  label: '取消并返回',
                  onPress: _abort,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 管理形态（多人游戏 → 本地服务器）：状态 + 日志 + RCON + 启停/配置。
  Widget _manageBody(double s) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 6 * s),
          child: _statusBar(s),
        ),
        SizedBox(height: 4 * s),
        Expanded(child: _logPanel(s)),
        SizedBox(height: 4 * s),
        if (_artifactError != null)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 6 * s),
            child: Text(
              _artifactError!,
              style: TextStyle(color: const Color(0xFFFF8080), fontSize: 6 * s),
            ),
          ),
        Padding(
          padding: EdgeInsets.all(4 * s),
          child: Row(
            children: [
              Expanded(child: _primaryButton(s)),
              SizedBox(width: 4 * s),
              Expanded(
                child: MCButton(
                  height: 20 * s,
                  label: '启动并进入世界',
                  onPress: _canStart ? () => _start(join: true) : null,
                ),
              ),
              SizedBox(width: 4 * s),
              Expanded(
                child: MCButton(
                  height: 20 * s,
                  label: '配置…',
                  onPress: _busy ? null : _editConfig,
                ),
              ),
              SizedBox(width: 4 * s),
              Expanded(
                child: MCButton(
                  height: 20 * s,
                  label: '刷新产物',
                  onPress: _busy ? null : _resolve,
                ),
              ),
              SizedBox(width: 4 * s),
              Expanded(
                child: MCButton(
                  height: 20 * s,
                  label: '返回',
                  onPress: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 取消并返回（进世界形态）：已起（或在起）就停服，避免留下孤儿进程占端口。
  Future<void> _abort() async {
    if (_process.isRunning || _state == ServerState.starting) {
      await _process.stop();
    }
    if (mounted) Navigator.maybePop(context);
  }

  Widget _statusBar(double s) {
    final text = switch (_state) {
      ServerState.stopped => '已停止',
      ServerState.starting => '启动中…',
      ServerState.ready => '可连接（端口 ${_process.listeningPort ?? widget.config.port}）',
      ServerState.stopping => '停止中…',
      ServerState.failed => '已失败（退出码 ${_exitCode ?? "?"}）',
    };
    return Row(
      children: [
        Expanded(
          child: Text(
            '状态：$text',
            style: TextStyle(
              color: _state == ServerState.failed
                  ? const Color(0xFFFF8080)
                  : const Color(0xFFE0E0E0),
              fontSize: 7 * s,
            ),
          ),
        ),
        Text(
          '127.0.0.1:${_process.listeningPort ?? widget.config.port}',
          style: TextStyle(color: const Color(0xFF9E9E9E), fontSize: 6 * s),
        ),
      ],
    );
  }

  Widget _primaryButton(double s) {
    final running = _state == ServerState.starting || _state == ServerState.ready;
    if (running || _state == ServerState.stopping) {
      return MCButton(
        height: 20 * s,
        label: _state == ServerState.stopping ? '停止中…' : '停止服务器',
        onPress: _busy || _state == ServerState.stopping ? null : _stop,
      );
    }
    return MCButton(
      height: 20 * s,
      label: '启动服务器',
      onPress: _canStart ? () => _start(join: false) : null,
    );
  }

  Widget _logPanel(double s) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 6 * s),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0B0B),
        border: Border.all(color: const Color(0xFF3F3F3F)),
      ),
      child: Column(
        children: [
          Expanded(
            child: _logs.isEmpty
                ? Center(
                    child: Text(
                      '（暂无日志）',
                      style: TextStyle(color: const Color(0xFF757575), fontSize: 6 * s),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: EdgeInsets.all(3 * s),
                    itemCount: _logs.length,
                    itemBuilder: (context, i) => Text(
                      _logs[i],
                      style: TextStyle(
                        color: const Color(0xFFB0B0B0),
                        fontSize: 5.5 * s,
                        height: 1.15,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
          ),
          // 指令输入：经原版 RCON 通道下发（spec「指令走 RCON」）。
          Padding(
            padding: EdgeInsets.all(3 * s),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _command,
                    style: TextStyle(color: const Color(0xFFE0E0E0), fontSize: 6 * s),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '控制台指令（经 RCON 下发，如 list / time set day）',
                      hintStyle: TextStyle(color: const Color(0xFF757575), fontSize: 6 * s),
                    ),
                    onSubmitted: (_) => _sendCommand(),
                  ),
                ),
                SizedBox(width: 4 * s),
                MCButton(
                  height: 18 * s,
                  width: 50 * s,
                  label: '发送',
                  onPress: _state == ServerState.ready ? _sendCommand : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // —— 启动流程 ——

  Future<void> _start({required bool join}) async {
    if (_busy) return;
    if (_artifacts == null) {
      await _resolve();
      if (_artifacts == null) return;
    }

    // 实例目录**先建**：`eula.txt` 与 `server.properties` 都要落在这个目录里，
    // 而原版 `Properties.store`/`File` 写盘**不建父目录**（`packages/mc_server` 的
    // `Properties.storeFile` 逐行照抄 JDK，不做 Dart 侧的"顺手建目录"）。
    //   —— 真机缺陷：先前的顺序是"EULA 同意 → 建目录"，点同意即写
    //   `servers/<id>/eula.txt`（目录尚不存在）→ FileSystemException，起服失败。
    _dir.createLayout();
    // 共享缓存 → 本实例：共享目录已有 paperclip 引导产物时先复制进来，
    // 这样**新世界首启不再走网络**（否则每建一个世界都要重下约 166MB）。
    await _dir.pullSharedCache();

    // EULA 硬门槛（spec「EULA 同意为启动硬门槛」）：未同意不写 eula=true、不启动。
    final gate = widget.manager.eulaGateFor(widget.config);
    if (!gate.agreed) {
      final agreed = await _askEula();
      if (agreed != true) return;
      gate.agree();
    }

    // 端口预检：**三个端口都要查**（游戏端口 + RCON + 管理服务器）。见 `_ensurePortsFree`。
    if (!await _ensurePortsFree()) return;

    // 宿主管理的配置键（含端口变更的落地）。
    _dir.ensureProperties(widget.config);

    setState(() => _busy = true);
    try {
      await _process.start(_artifacts!);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _snack('启动失败：$e');
      }
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);

    if (!join) return;
    final ready = await _waitReady();
    if (!mounted) return;
    if (!ready) {
      // 报**真实**原因（端口被占是实测最常见的一种），不一律说"未就绪超时"。
      _snack('服务端启动失败：${_failureReason()}');
      // 进世界模式下起不来就该收掉，别把端口占着（用户要求）。
      if (widget.playMode) {
        final process = _process;
        Navigator.maybePop(context);
        await process.stop();
      }
      return;
    }
    await _joinWorld();

    // 退出游戏即**静默**停服（**仅单人进世界路径**）：`joinServer` 内部 `await` 了 '/game'
    // 那次 push，返回即代表玩家已离开世界。先退回世界列表、再停服——不留"正在停止…"画面
    // （用户要求"静默"，也顺手避免端口被上一局占着导致下一局冲突）。
    // 多人 → 本地服务器那条管理路径仍由用户手动启停。
    if (widget.playMode) {
      final process = _process;
      if (mounted) Navigator.maybePop(context);
      await process.stop();
    }
  }

  /// 等待原版就绪行（design D4）或失败。
  Future<bool> _waitReady() {
    if (_state == ServerState.ready) return Future<bool>.value(true);
    final completer = Completer<bool>();
    late StreamSubscription<ServerState> sub;
    sub = _process.stateChanges.listen((s) {
      if (s == ServerState.ready) {
        if (!completer.isCompleted) completer.complete(true);
      } else if (s == ServerState.failed || s == ServerState.stopped) {
        if (!completer.isCompleted) completer.complete(false);
      }
    });
    return completer.future
        .timeout(kReadyTimeout, onTimeout: () => false)
        .whenComplete(sub.cancel);
  }

  /// 进入世界：复用既有 `remote-play` 通路（`joinServer` 内部 push '/game'）。
  Future<void> _joinWorld() async {
    final port = _process.listeningPort ?? widget.config.port;
    final server = ServerData(
      name: widget.config.name,
      ip: '127.0.0.1:$port',
    );
    await joinServer(context, server: server, connector: defaultJoinConnector);
  }

  Future<void> _stop() async {
    setState(() => _busy = true);
    try {
      await _process.stop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 经 RCON 下发一条指令并回显原版响应（spec「指令走 RCON」）。
  Future<void> _sendCommand() async {
    final command = _command.text.trim();
    if (command.isEmpty) return;
    _command.clear();
    RconClient? client;
    try {
      final props = DedicatedServerProperties(
          Settings.loadFromFile(_dir.serverProperties.path));
      client = await RconClient.connect('127.0.0.1', props.rconPort,
          timeout: const Duration(seconds: 3));
      final ok = await client.authenticate(props.rconPassword);
      if (!ok) throw const SocketException('RCON 鉴权失败');
      final output = await client.execCommand(command);
      if (mounted) {
        setState(() => _logs.add('> $command\n$output'));
        _autoScroll();
      }
    } catch (e) {
      if (mounted) _snack('RCON 下发失败：$e');
    } finally {
      await client?.close();
    }
  }

  // —— 对话框（沿用系统默认样式 + 可滚动内容，见用户偏好）——

  Future<bool?> _askEula() => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Minecraft 最终用户许可协议'),
          content: SingleChildScrollView(
            child: Text(
              '要运行本地服务器，你必须同意 Minecraft 最终用户许可协议（EULA）。\n\n'
              '全文：${EulaGate.url}\n\n'
              '点击"同意"表示你接受该协议，并会在实例目录写入 eula=true。\n'
              '可随时在配置中撤回。',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('不同意'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('同意'),
            ),
          ],
        ),
      );

  /// 起服前**三个端口**的可用性预检；任一被占即弹「端口设置」对话框——
  /// 三个端口都实时校验、**全部可用才允许按确定**，占用者是本宿主实例时给红色停止按钮。
  ///
  /// 为什么三个都要查（实测教训）：Paper 在**生成世界之前**就会绑管理服务器端口
  /// （崩溃栈 `JsonRpc.create` → `java.net.BindException: Address already in use`），
  /// 而本仓各实例默认同端口（25565/25575/25585）——只查游戏端口时，控制端口一撞就是
  /// "整个服务端起不来"，旧实现还把它误报成"未就绪超时"。返回 false ＝ 用户取消。
  Future<bool> _ensurePortsFree() async {
    final ports = <int>[
      widget.config.port,
      widget.config.rconPort,
      widget.config.managementServerPort,
    ];
    var allFree = true;
    for (final port in ports) {
      if (!await widget.manager.isPortAvailable(port)) {
        allFree = false;
        break;
      }
    }
    if (allFree) return true;
    if (!mounted) return false;
    final chosen = await showLocalServerPortsDialog(
      context,
      manager: widget.manager,
      config: widget.config,
    );
    if (chosen == null) return false;
    widget.config
      ..port = chosen.serverPort
      ..rconPort = chosen.rconPort
      ..managementServerPort = chosen.managementServerPort;
    widget.manager.saveConfigs();
    if (mounted) setState(() {});
    return true;
  }

  /// 从捕获的输出里挑出**真正的**失败原因（找不到才回落到超时文案）。
  ///
  /// 实测教训：进程因端口被占早退（BindException）时，旧文案一律说"未在 300 秒内就绪"，
  /// 把排查方向带偏。
  String _failureReason() {
    final tail = _process.recentLogs.reversed.take(80).toList();
    for (final line in tail) {
      if (line.contains('Address already in use') ||
          line.contains(DedicatedServerProcess.bindFailedMarker)) {
        return '端口被占用（java.net.BindException: Address already in use）'
            '——请改端口或先停掉占用者';
      }
    }
    for (final line in tail) {
      final match = RegExp(r'ERROR\]: (.+)$').firstMatch(line);
      if (match != null) return match.group(1)!;
    }
    return '未在 ${kReadyTimeout.inSeconds} 秒内就绪（未见到原版就绪行）';
  }

  Future<void> _editConfig() async {
    final changed = await showLocalServerConfigDialog(
      context,
      config: widget.config,
      // 已生成的世界：种子/极限模式只读（创建时固化）。
      worldExists: _dir.worldExists,
    );
    if (changed == true) {
      widget.manager.saveConfigs();
      if (!mounted) return;
      setState(() {});
      await _resolve(); // 配置变更（版本/产物路径）后重解析
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }
}
