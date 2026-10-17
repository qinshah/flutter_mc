import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mc_session/mc_session.dart';
import 'package:mc_ui/mc_ui.dart';
import 'package:path_provider/path_provider.dart';

import '../../platform/server_host/local_server_config.dart';
import '../../platform/server_host/local_server_host.dart';
import '../../routes.dart';
import '../confirm_screen.dart';
import '../screen.dart';
import 'join_flow.dart';
import 'local_server_config_dialog.dart';
import 'manage_server_screen.dart';
import 'server_selection_list.dart';

/// gui/screens/multiplayer/JoinMultiplayerScreen.java 的对应：真实服务器列表、
/// 逐条探测、列表管理入口（添加/编辑/删除/直连）。
/// "加入服务器"经版本装配点连接：成功进游戏屏（/game），失败就地 SnackBar。
class JoinMultiplayerScreen extends StatefulWidget {
  const JoinMultiplayerScreen({
    super.key,
    this.serverList,
    this.localManager,
    this.enablePing = true,
    this.connector,
  });

  /// 注入口（测试用）；缺省取应用文档目录下的游戏目录。
  final ServerList? serverList;

  /// 本地服务器宿主注入口（测试用）；缺省取全应用单例。
  final LocalServerManager? localManager;

  /// 测试用：关闭真实网络探测（保持"正在探测…"确定性状态）。
  final bool enablePing;

  /// 连接注入点（测试替换真实 isolate 会话）；缺省走版本装配点。
  final JoinConnector? connector;

  @override
  State<JoinMultiplayerScreen> createState() => _JoinMultiplayerScreenState();
}

class _JoinMultiplayerScreenState extends State<JoinMultiplayerScreen> {
  ServerList? _list;
  var _selected = -1;

  /// 本地服务器宿主（全局单例；测试/未初始化环境为 null，此时不渲染本地区块）。
  LocalServerManager? _local;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    var list = widget.serverList;
    if (list == null) {
      try {
        final docs = await getApplicationDocumentsDirectory();
        list = ServerList(Directory('${docs.path}/game'))..load();
      } catch (_) {
        // 测试/异常环境（无平台插件）：保持未就绪状态，界面显示空态提示。
      }
    } else {
      list.load();
    }
    // 本地服务器条目来自宿主（独立于 servers.dat，见 spec「列表文件不被污染」）。
    LocalServerManager? local = widget.localManager;
    if (local == null) {
      try {
        local = localServerManager;
        // 触发读盘
      } catch (_) {
        local = null;
      }
    }
    local?.configs; // 触发读盘
    if (!mounted) return;
    setState(() {
      _list = list;
      _local = local;
    });
    if (widget.enablePing) _pingAll();
  }

  void _pingAll() {
    // 测试注入 enablePing=false：真实 socket 在测试的 FakeAsync 区等不到事件，
    // 一旦发起就会把整个用例挂死。
    if (!widget.enablePing || _list == null) return;
    _pingAllAsync();
  }

  Future<void> _pingAllAsync() async {
    final list = _list;
    if (list == null) return;
    for (var i = 0; i < list.length; i++) {
      final server = list[i];
      final port = _parsePort(server.ip);
      final host = server.ip.contains(':')
          ? server.ip.substring(0, server.ip.lastIndexOf(':'))
          : server.ip;
      try {
        server.pingInfo = await pingServer(host, port);
        server.pingFailed = false;
        server.protocol = server.pingInfo!.protocolId;
      } catch (_) {
        server.pingInfo = null;
        server.pingFailed = true;
      }
      if (mounted) setState(() {});
    }
  }

  int _parsePort(String ip) {
    final i = ip.lastIndexOf(':');
    if (i < 0) return 25565;
    return int.tryParse(ip.substring(i + 1)) ?? 25565;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final s = mcScaleForWidth(constraints.maxWidth);
    final gap = SizedBox(width: 4 * s);
    final hasSelection = _list != null && _selected >= 0 && _selected < _list!.length;

    Widget button(String label, {VoidCallback? onPress, bool needsSelection = false}) {
      return MCButton(
        height: 20 * s,
        label: label,
        onPress: needsSelection && !hasSelection ? null : onPress,
      );
    }

    return McScreen(
      title: '多人游戏',
      body: (context) => Column(
        children: [
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      // 本地服务器条目：来自宿主，独立于 servers.dat（spec「列表文件不被污染」）。
                      if (_local != null && _local!.configs.isNotEmpty) ...[
                        _sectionLabel(s, '本地服务器'),
                        for (final config in _local!.configs)
                          _LocalServerEntry(
                            config: config,
                            running: _local!.processFor(config).isRunning,
                            onTap: () => _openLocal(config),
                          ),
                        SizedBox(height: 4 * s),
                      ],
                      Expanded(
                        child: _list == null || _list!.isEmpty
                            ? Center(
                                child: Text(
                                  '暂无服务器，点击下方"添加服务器"',
                                  style: TextStyle(
                                    color: const Color(0xFF9E9E9E),
                                    fontSize: 8 * s,
                                    height: 1.0,
                                  ),
                                ),
                              )
                            : ServerSelectionList(
                                servers: _list!.servers,
                                selectedIndex: _selected,
                                onSelected: (i) => setState(() => _selected = i),
                              ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '正在你的本地网络中寻找游戏',
                  style: TextStyle(color: const Color(0xFF9E9E9E), fontSize: 7 * s, height: 1.0),
                ),
                SizedBox(height: 12 * s),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(4 * s),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: button(
                        '加入服务器',
                        needsSelection: true,
                        onPress: _joinSelected,
                      ),
                    ),
                    gap,
                    Expanded(
                      child: button(
                        '直接连接',
                        onPress: () => Navigator.pushNamed(context, '/multiplayer/direct'),
                      ),
                    ),
                    gap,
                    Expanded(
                      child: button(
                        '添加服务器',
                        onPress: () => _openManage(null),
                      ),
                    ),
                    gap,
                    // 新建本地世界：创建宿主实例并进入其条目屏（design.md D8 的 UI 形态）。
                    Expanded(
                      child: button(
                        '新建本地世界',
                        onPress: _local == null ? null : _createLocal,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 4 * s),
                Row(
                  children: [
                    Expanded(
                      child: button(
                        '编辑',
                        needsSelection: true,
                        onPress: () => _openManage(_selected),
                      ),
                    ),
                    gap,
                    Expanded(
                      child: button(
                        '删除',
                        needsSelection: true,
                        onPress: _confirmDelete,
                      ),
                    ),
                    gap,
                    Expanded(child: button('刷新', onPress: _pingAll)),
                    gap,
                    Expanded(
                      child: button('返回', onPress: () => Navigator.pop(context)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
      });
  }

  Future<void> _joinSelected() async {
    final server = _list![_selected];
    await joinServer(
      context,
      server: server,
      connector: widget.connector ?? defaultJoinConnector,
    );
  }

  Future<void> _openManage(int? editIndex) async {
    await Navigator.pushNamed(
      context,
      '/multiplayer/manage',
      arguments: ManageServerArgs(list: _list!, editIndex: editIndex),
    );
    setState(_pingAll);
  }

  Future<void> _confirmDelete() async {
    final server = _list![_selected];
    final confirmed = await Navigator.pushNamed(
      context,
      '/multiplayer/confirm',
      arguments: ConfirmArgs(
        message: '确定要删除 "${server.name}" 吗？\n该操作不可撤销。',
      ),
    );
    if (confirmed == true) {
      setState(() {
        _list!.removeAt(_selected);
        _selected = -1;
      });
    }
  }

  Future<void> _createLocal() async {
    final local = _local;
    if (local == null) return;
    // 先编辑草稿，用户确认后才入库（取消则什么都不建）。
    final draft = local.newConfigDraft();
    final saved = await showLocalServerConfigDialog(context, config: draft);
    if (!mounted || saved != true) return;
    local.insertConfig(draft);
    await _openLocal(draft);
  }

  Future<void> _openLocal(LocalServerConfig config) async {
    final local = _local;
    if (local == null) return;
    await Navigator.pushNamed(
      context,
      '/multiplayer/local',
      arguments: LocalServerArgs(manager: local, config: config),
    );
    if (mounted) setState(() {});
  }
}

/// 分区块标题（本地服务器 / 已保存的服务器）。
Widget _sectionLabel(double s, String text) => Padding(
      padding: EdgeInsets.fromLTRB(4 * s, 4 * s, 4 * s, 2 * s),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: TextStyle(color: const Color(0xFF9E9E9E), fontSize: 6 * s),
        ),
      ),
    );

/// 本地服务器列表条目（形态对齐 `ServerSelectionList` 的单行变体）。
class _LocalServerEntry extends StatelessWidget {
  const _LocalServerEntry({
    required this.config,
    required this.running,
    required this.onTap,
  });

  final LocalServerConfig config;
  final bool running;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = mcScaleForWidth(MediaQuery.sizeOf(context).width);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.fromLTRB(4 * s, 0, 4 * s, 2 * s),
        padding: EdgeInsets.all(4 * s),
        decoration: BoxDecoration(
          color: const Color(0xAA000000),
          border: Border.all(color: const Color(0x00000000), width: s),
        ),
        child: Row(
          children: [
            Icon(Icons.dns,
                size: 12 * s,
                color: running ? const Color(0xFF55FF55) : const Color(0xFF8B8B8B)),
            SizedBox(width: 6 * s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    config.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: const Color(0xFFE0E0E0), fontSize: 8 * s, height: 1.0),
                  ),
                  SizedBox(height: 3 * s),
                  Text(
                    '本地 · ${running ? "运行中" : "已停止"} · '
                    '127.0.0.1:${config.port} · MC ${config.mcVersion}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: const Color(0xFF9E9E9E), fontSize: 7 * s, height: 1.0),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
