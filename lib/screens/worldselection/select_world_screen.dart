// 世界选择屏：`net/minecraft/client/gui/screens/worldselection/SelectWorldScreen.java` 的对应。
//
// 判据：
//   SelectWorldScreen.java:41      —— 标题 `selectWorld.title`
//   SelectWorldScreen.java:80-104  —— 底部按钮组：进入世界（`LevelSummary.PLAY_WORLD`）、
//                                    创建新的世界（`selectWorld.create`）、编辑（`selectWorld.edit`）、
//                                    删除（`selectWorld.delete`）、重新创建（`selectWorld.recreate`）、
//                                    返回（`CommonComponents.GUI_BACK`）
//   SelectWorldScreen.java:147-160 —— **未选中条目时上述按钮全禁用**
//                                    （`playWorldButton.active = false` 等）
//
// 本仓差异（登记为翻译债，见 openspec/progress.md）：
//   * 列表条目是**本地服务器实例**（宿主概念），原版是存档 `LevelSummary`；
//   * 原版的搜索框（`:55` `selectWorld.search`）本期未做；
//   * 原版的「重新创建」（`:98-101`）本期未做。
//
// 进入世界走的是"选中 → 按进入 → 才启动服务器"（用户要求：不许一进屏就起服占端口）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mc_ui/mc_ui.dart';

import '../../platform/server_host/local_server_config.dart';
import '../../platform/server_host/local_server_host.dart';
import '../../routes.dart';
import '../multiplayer/local_server_config_dialog.dart';
import '../screen.dart';
import 'edit_world_screen.dart';

class SelectWorldScreen extends StatefulWidget {
  const SelectWorldScreen({super.key, required this.manager});

  final LocalServerManager manager;

  @override
  State<SelectWorldScreen> createState() => _SelectWorldScreenState();
}

class _SelectWorldScreenState extends State<SelectWorldScreen> {
  /// 选中条目下标；-1 = 未选中（此时按钮组全禁用，判据 `SelectWorldScreen.java:147-160`）。
  int _selected = -1;
  bool _busy = false;

  List<LocalServerConfig> get _worlds => widget.manager.configs;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final s = mcScaleForWidth(constraints.maxWidth);
      final hasSelection = _selected >= 0 && _selected < _worlds.length;
      final gap = SizedBox(width: 4 * s);

      return McScreen(
        title: '选择世界',
        body: (context) => Column(
          children: [
            Expanded(
              child: _worlds.isEmpty
                  ? Center(
                      child: Text(
                        '暂无世界，点击下方"创建新的世界"',
                        style: TextStyle(
                          color: const Color(0xFF9E9E9E),
                          fontSize: 8 * s,
                          height: 1.0,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.symmetric(horizontal: 6 * s),
                      itemCount: _worlds.length,
                      itemBuilder: (context, i) => _WorldRow(
                        scale: s,
                        config: _worlds[i],
                        selected: i == _selected,
                        onTap: () => setState(() => _selected = i),
                      ),
                    ),
            ),
            SizedBox(height: 4 * s),
            Padding(
              padding: EdgeInsets.all(4 * s),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: MCButton(
                          height: 20 * s,
                          label: '进入世界',
                          onPress: hasSelection ? () => _enter(_selected) : null,
                        ),
                      ),
                      gap,
                      Expanded(
                        child: MCButton(
                          height: 20 * s,
                          label: '创建新的世界',
                          onPress: _busy ? null : _create,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 4 * s),
                  Row(
                    children: [
                      Expanded(
                        child: MCButton(
                          height: 20 * s,
                          label: '编辑',
                          onPress: hasSelection && !_busy
                              ? () => _edit(_selected)
                              : null,
                        ),
                      ),
                      gap,
                      Expanded(
                        child: MCButton(
                          height: 20 * s,
                          label: '删除',
                          onPress: hasSelection && !_busy
                              ? () => _delete(_selected)
                              : null,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 4 * s),
                  Row(
                    children: [
                      Expanded(
                        child: MCButton(
                          height: 20 * s,
                          label: '返回',
                          onPress: () => Navigator.pop(context),
                        ),
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

  /// 进入世界：跳"进世界"形态的本地服务器屏（**选中的这一刻才启动服务器**）。
  /// 该屏退出游戏后会停服并返回本屏。
  Future<void> _enter(int index) async {
    if (_busy) return;
    final config = _worlds[index];
    await Navigator.pushNamed(
      context,
      '/multiplayer/local',
      arguments: LocalServerArgs(manager: widget.manager, config: config, playMode: true),
    );
    if (mounted) setState(() {}); // 回来后刷新条目状态（服务器可能已停）
  }

  /// 创建新的世界（原版 `selectWorld.create` → `CreateWorldScreen`）：
  /// **先编辑草稿**（不入库、不落盘），用户按"保存"确认后才真正创建并进入。
  Future<void> _create() async {
    setState(() => _busy = true);
    final draft = widget.manager.newConfigDraft();
    final saved = await showLocalServerConfigDialog(context, config: draft);
    if (!mounted) return;
    if (saved != true) {
      // 取消 → 什么都没建（旧实现在这里已经把世界写进 instances.json 了，是 bug）。
      setState(() => _busy = false);
      return;
    }
    widget.manager.insertConfig(draft);
    setState(() {
      _busy = false;
      _selected = _worlds.indexOf(draft);
    });
    await _enter(_selected);
  }

  /// 编辑（原版 `selectWorld.edit` → `EditWorldScreen`）：**只能改名**
  /// ——世界生成参数是创建时固化的（判据 `EditWorldScreen.java:41/57/71/74-76`）。
  Future<void> _edit(int index) async {
    final changed = await showEditWorldScreen(context, config: _worlds[index]);
    if (changed == true) {
      widget.manager.saveConfigs();
      if (mounted) setState(() {});
    }
  }

  /// 删除（原版 `selectWorld.delete` → 删除确认屏）：确认后移除条目并删掉实例目录。
  Future<void> _delete(int index) async {
    final config = _worlds[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除世界'),
        content: SingleChildScrollView(
          child: Text(
            '确定删除"${config.name}"？\n\n'
            '该世界的实例目录（含存档与配置）会被一并删除，无法撤销。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final dir = widget.manager.instanceDirectoryFor(config).dir;
    widget.manager.removeConfig(config);
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } on FileSystemException {
      // 删不掉（被占用等）不阻断：条目已移除，目录留给用户手动清理。
    }
    if (mounted) setState(() => _selected = -1);
  }
}

/// 条目行（原版 `WorldSelectionList.WorldListEntry` 的简化形态）。
class _WorldRow extends StatelessWidget {
  const _WorldRow({
    required this.scale,
    required this.config,
    required this.selected,
    required this.onTap,
  });

  final double scale;
  final LocalServerConfig config;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Padding(
      padding: EdgeInsets.only(bottom: 3 * s),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 28 * s,
          padding: EdgeInsets.symmetric(horizontal: 4 * s),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF3A3A3A) : const Color(0xFF1D1D1D),
            border: Border.all(
              color: selected ? const Color(0xFFFFFFFF) : const Color(0xFF5A5A5A),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  config.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xFFE0E0E0),
                    fontSize: 7 * s,
                    height: 1.0,
                  ),
                ),
              ),
              Text(
                'MC ${config.mcVersion} · 127.0.0.1:${config.port} · ${_gamemodeLabel(config.gamemode)}',
                style: TextStyle(
                  color: const Color(0xFF9E9E9E),
                  fontSize: 6 * s,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 游戏模式中文名（取值名照 `GameType.java:17-20`）。
  static String _gamemodeLabel(String gamemode) => switch (gamemode) {
        'creative' => '创造',
        'adventure' => '冒险',
        'spectator' => '旁观',
        _ => '生存',
      };
}
