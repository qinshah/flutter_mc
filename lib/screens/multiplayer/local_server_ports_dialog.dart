// 端口设置对话框（宿主侧 UI，无原版对应物——属第三类自由设计「运行时宿主」）。
//
// 为什么需要它（实测教训）：Paper 在**生成世界之前**就绑管理服务器端口
// （崩溃栈 `JsonRpc.create` → `java.net.BindException: Address already in use`，
// 见 `net/minecraft/server/Main.java` 传 `jsonRpcServer` 那条链），而本仓各实例默认同端口
// （25565 / 25575 / 25585）——只查游戏端口时，控制端口一撞就"整个服务端起不来"。
//
// 交互口径（用户要求）：
//   * **三个端口都实时校验**；全部可用（且互不重复）才允许按「确定」；
//   * 被占用且占用者是**本宿主的另一个实例**时，该行给**红色**「停止该服务器」按钮，
//     停掉后自动重新校验；
//   * 占用者是外部进程时不给停止按钮（我们无权停它），只能改端口。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:mc_ui/mc_ui.dart';

import '../../platform/server_host/local_server_config.dart';
import '../../platform/server_host/local_server_host.dart';

/// 用户在对话框里最终确认的三个端口。
typedef LocalServerPorts = ({int serverPort, int rconPort, int managementServerPort});

/// 打开端口设置对话框；用户按「确定」返回新端口，取消返回 null。
Future<LocalServerPorts?> showLocalServerPortsDialog(
  BuildContext context, {
  required LocalServerManager manager,
  required LocalServerConfig config,
  Future<bool> Function(int port)? portChecker,

  /// 占用者反查（默认 `LocalServerManager.findPortHolder`，含**上次会话残留的孤儿**）；
  /// 测试可注入确定性实现。
  Future<LocalPortHolder?> Function(int port)? holderFinder,
}) =>
    showDialog<LocalServerPorts>(
      context: context,
      builder: (ctx) => LocalServerPortsDialog(
        manager: manager,
        config: config,
        portChecker: portChecker,
        holderFinder: holderFinder,
      ),
    );

class LocalServerPortsDialog extends StatefulWidget {
  const LocalServerPortsDialog({
    super.key,
    required this.manager,
    required this.config,
    this.portChecker,
    this.holderFinder,
  });

  final LocalServerManager manager;
  final LocalServerConfig config;

  /// 端口可用性检查；缺省走 [LocalServerManager.isPortAvailable]（真实绑包探测）。
  /// 可在 widget 测试里注入确定性实现——真实 socket 的 future 在 `testWidgets` 的
  /// 受控事件循环里不会完成（需 `tester.runAsync`），注入可免去这层麻烦。
  final Future<bool> Function(int port)? portChecker;

  /// 占用者反查；缺省走 [LocalServerManager.findPortHolder]。
  final Future<LocalPortHolder?> Function(int port)? holderFinder;

  @override
  State<LocalServerPortsDialog> createState() => _LocalServerPortsDialogState();
}

/// 单个端口的校验结果。
sealed class _PortState {
  const _PortState();
}

/// 还没查/正在查。
class _Checking extends _PortState {
  const _Checking();
}

/// 不是 1..65535 的整数。
class _Invalid extends _PortState {
  const _Invalid();
}

/// 与本对话框里的另一个端口重复。
class _Duplicate extends _PortState {
  const _Duplicate();
}

/// 可用。
class _Free extends _PortState {
  const _Free();
}

/// 被占用；[holder] 非空表示占用者是本宿主名下的本地服务器（可停——含上次会话的孤儿）。
class _Busy extends _PortState {
  const _Busy(this.holder);

  final LocalPortHolder? holder;
}

class _LocalServerPortsDialogState extends State<LocalServerPortsDialog> {
  static const double _h = 30;

  late final TextEditingController _server;
  late final TextEditingController _rcon;
  late final TextEditingController _management;

  final Map<String, _PortState> _states = <String, _PortState>{
    'server': const _Checking(),
    'rcon': const _Checking(),
    'management': const _Checking(),
  };

  /// 竞态护栏：异步校验返回时若已发起新的校验轮次，丢弃旧结果。
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _server = TextEditingController(text: '${widget.config.port}');
    _rcon = TextEditingController(text: '${widget.config.rconPort}');
    _management = TextEditingController(text: '${widget.config.managementServerPort}');
    for (final controller in <TextEditingController>[_server, _rcon, _management]) {
      controller.addListener(_revalidate);
    }
    _revalidate();
  }

  @override
  void dispose() {
    for (final controller in <TextEditingController>[_server, _rcon, _management]) {
      controller
        ..removeListener(_revalidate)
        ..dispose();
    }
    super.dispose();
  }

  int? _parse(TextEditingController controller) {
    final value = int.tryParse(controller.text.trim());
    if (value == null || value < 1 || value > 65535) return null;
    return value;
  }

  /// 重新校验三个端口（编辑即触发）。**全部可用才允许确定。**
  Future<void> _revalidate() async {
    final generation = ++_generation;
    final raw = <String, int?>{
      'server': _parse(_server),
      'rcon': _parse(_rcon),
      'management': _parse(_management),
    };
    final valid = raw.values.whereType<int>().toList();
    final failed = <String, _PortState>{};
    for (final entry in raw.entries) {
      final port = entry.value;
      if (port == null) {
        failed[entry.key] = const _Invalid();
      } else if (valid.where((p) => p == port).length > 1) {
        failed[entry.key] = const _Duplicate();
      }
    }
    // 先落"非法/重复"的结论，剩下的再查占用（避免空窗期让确定可点）。
    if (mounted && generation == _generation) {
      setState(() {
        for (final entry in raw.entries) {
          _states[entry.key] = failed[entry.key] ?? const _Checking();
        }
      });
    }
    for (final entry in raw.entries) {
      if (failed.containsKey(entry.key)) continue;
      final port = entry.value!;
      final check = widget.portChecker ?? widget.manager.isPortAvailable;
      final free = await check(port);
      final findHolder = widget.holderFinder ?? widget.manager.findPortHolder;
      failed[entry.key] =
          free ? const _Free() : _Busy(await findHolder(port));
    }
    if (!mounted || generation != _generation) return;
    setState(() {
      _states
        ..clear()
        ..addAll(failed);
    });
  }

  bool get _canConfirm =>
      _states.values.every((state) => state is _Free);

  Future<void> _stopHolder(_Busy busy) async {
    final holder = busy.holder;
    if (holder == null) return;
    await holder.stop();
    await _revalidate();
  }

  /// 一行：端口名 / 输入框 / 校验状态（+ 占用时的红色停止按钮）。
  Widget _row(String key, String label, TextEditingController controller) {
    final state = _states[key] ?? const _Checking();
    final (String text, Color color) = switch (state) {
      _Checking() => ('校验中…', const Color(0xFF9E9E9E)),
      _Invalid() => ('端口须是 1–65535 的整数', const Color(0xFFFF8080)),
      _Duplicate() => ('与另一个端口重复', const Color(0xFFFF8080)),
      _Free() => ('可用', const Color(0xFF7FD07F)),
      _Busy(holder: final holder) => (
          holder == null
              ? '被占用（非本地服务器进程，请改端口）'
              : '被本地服务器"${holder.label}"占用',
          const Color(0xFFFF8080),
        ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 110,
                child: Text(label, style: const TextStyle(fontSize: 13)),
              ),
              SizedBox(
                width: 110,
                child: MCEditBox(
                  controller: controller,
                  width: 110,
                  height: _h,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(text, style: TextStyle(fontSize: 12, color: color)),
              ),
            ],
          ),
          // 红色停止按钮：只在占用者是本宿主实例时出现（外部进程我们无权停）。
          if (state is _Busy && state.holder != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 110, top: 2),
                child: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFE05252),
                  ),
                  onPressed: () => _stopHolder(state),
                  child: Text('停止该服务器（${state.holder!.label}）'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('端口设置'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '服务端要绑这三个端口；任何一个被占用都起不来。\n'
                '三个都显示"可用"后才能按确定。',
                style: TextStyle(fontSize: 12, color: Color(0xFF9E9E9E)),
              ),
              const SizedBox(height: 6),
              _row('server', '服务端端口', _server),
              _row('rcon', 'RCON 端口', _rcon),
              _row('management', '管理服务器端口', _management),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: _canConfirm
              ? () => Navigator.pop(
                    context,
                    (
                      serverPort: _parse(_server)!,
                      rconPort: _parse(_rcon)!,
                      managementServerPort: _parse(_management)!,
                    ),
                  )
              : null,
          child: const Text('确定'),
        ),
      ],
    );
  }
}
