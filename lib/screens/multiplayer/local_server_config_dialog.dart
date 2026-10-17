// 本地服务器实例配置对话框（宿主侧 UI，无原版对应物——属第三类自由设计「运行时宿主」）。
//
// 但**控件选型照原版**：枚举/布尔项用 `MCCycleButton`（原版 `gui/components/CycleButton`，
// 单人创建世界界面正是这么做的——`CreateWorldScreen.java:651-671` 的 gameMode / difficulty /
// allowCommands 三个 CycleButton）；文本项用 `MCEditBox`（原版 `gui/components/EditBox`）。
// **不**用裸 `TextField`——那是 Flutter 原生控件，不是 MC 界面的形态。
//
// 抽成独立组件是因为两个入口都要用：本地服务器屏的「配置…」，
// 以及"创建世界"时刻（原版在创建世界时就要选游戏模式，见 `CreateWorldScreen`）。
import 'package:flutter/material.dart';
import 'package:mc_ui/mc_ui.dart';

import '../../platform/server_host/local_server_config.dart';

/// 编辑 [config]；用户点"保存"则改动已写回 `config` 并返回 true（调用方负责 `saveConfigs()`）。
///
/// [worldExists] 为真时（实例的 `world/level.dat` 已存在）把**世界生成类**项置为只读：
/// 种子与极限模式是创建时固化的（原版写进 `level.dat`，改了不生效）。
Future<bool?> showLocalServerConfigDialog(
  BuildContext context, {
  required LocalServerConfig config,
  bool worldExists = false,
}) =>
    showDialog<bool>(
      context: context,
      builder: (ctx) =>
          LocalServerConfigDialog(config: config, worldExists: worldExists),
    );

class LocalServerConfigDialog extends StatefulWidget {
  const LocalServerConfigDialog({
    super.key,
    required this.config,
    this.worldExists = false,
  });

  final LocalServerConfig config;

  /// 世界是否已生成（决定世界生成类项是否只读，见上）。
  final bool worldExists;

  @override
  State<LocalServerConfigDialog> createState() => LocalServerConfigDialogState();
}

class LocalServerConfigDialogState extends State<LocalServerConfigDialog> {
  /// 游戏模式取值（序列化名照 `GameType.java:17-20` 的 `getName()`）。
  static const List<String> _gamemodes = <String>[
    'survival', // GameType.java:17
    'creative', // GameType.java:18
    'adventure', // GameType.java:19
    'spectator', // GameType.java:20
  ];
  static const Map<String, String> _gamemodeLabels = <String, String>{
    'survival': '生存',
    'creative': '创造',
    'adventure': '冒险',
    'spectator': '旁观',
  };

  /// 难度取值（序列化名照 `Difficulty.java:13-16` 的 `getSerializedName()`）。
  static const List<String> _difficulties = <String>[
    'peaceful', // Difficulty.java:13
    'easy', // Difficulty.java:14
    'normal', // Difficulty.java:15
    'hard', // Difficulty.java:16
  ];
  static const Map<String, String> _difficultyLabels = <String, String>{
    'peaceful': '和平',
    'easy': '简单',
    'normal': '普通',
    'hard': '困难',
  };

  static const double _h = 30;

  late final Map<String, TextEditingController> _fields;

  // 世界/玩法项：枚举与布尔，用 CycleButton（不进文本字段）。
  late String _gamemode = widget.config.gamemode;
  late String _difficulty = widget.config.difficulty;
  late bool _hardcore = widget.config.hardcore;

  @override
  void initState() {
    super.initState();
    final c = widget.config;
    _fields = <String, TextEditingController>{
      'name': TextEditingController(text: c.name),
      'mcVersion': TextEditingController(text: c.mcVersion),
      'protocol': TextEditingController(text: '${c.protocol}'),
      'javaMajor': TextEditingController(text: '${c.javaMajor}'),
      'port': TextEditingController(text: '${c.port}'),
      'rconPort': TextEditingController(text: '${c.rconPort}'),
      'managementServerPort':
          TextEditingController(text: '${c.managementServerPort}'),
      'jvmArgs': TextEditingController(text: c.jvmArgs.join(' ')),
      'stopTimeoutSeconds':
          TextEditingController(text: '${c.stopTimeoutSeconds}'),
      'jarPath': TextEditingController(text: c.jarPath ?? ''),
      'levelSeed': TextEditingController(text: c.levelSeed),
    };
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _save() {
    final c = widget.config;
    c.name = _fields['name']!.text.trim().isEmpty
        ? c.name
        : _fields['name']!.text.trim();
    c.gamemode = _gamemode;
    // 极限模式下难度锁死为困难（原版 `WorldCreationUiState.java:139`：
    // `getDifficulty()` 在 hardcore 时直接返回 `Difficulty.HARD`）。
    c.difficulty = _hardcore ? 'hard' : _difficulty;
    c.hardcore = _hardcore;
    // 种子：空串 = 服务端随机（原版 `CreateWorldScreen.java:766-775` 的 seedEdit 同口径）。
    // 世界已生成时这两项已固化，不改写（界面也置了只读）。
    if (!widget.worldExists) {
      c.levelSeed = _fields['levelSeed']!.text.trim();
    }
    c.mcVersion = _fields['mcVersion']!.text.trim();
    c.protocol = int.tryParse(_fields['protocol']!.text.trim()) ?? c.protocol;
    c.javaMajor = int.tryParse(_fields['javaMajor']!.text.trim()) ?? c.javaMajor;
    c.port = int.tryParse(_fields['port']!.text.trim()) ?? c.port;
    c.rconPort = int.tryParse(_fields['rconPort']!.text.trim()) ?? c.rconPort;
    c.managementServerPort =
        int.tryParse(_fields['managementServerPort']!.text.trim()) ??
            c.managementServerPort;
    final args = _fields['jvmArgs']!.text.trim();
    c.jvmArgs = args.isEmpty ? c.jvmArgs : args.split(RegExp(r'\s+'));
    c.stopTimeoutSeconds =
        int.tryParse(_fields['stopTimeoutSeconds']!.text.trim()) ??
            c.stopTimeoutSeconds;
    final jarPath = _fields['jarPath']!.text.trim();
    c.jarPath = jarPath.isEmpty ? null : jarPath;
    Navigator.pop(context, true);
  }

  /// 分区标题（MC 界面的分组标签形态）。
  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4),
        child: Text(
          title,
          style: const TextStyle(
            color: Color(0xFFFFFF00),
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      );

  /// 带标签的文本行（原版 EditBox：`gui/components/EditBox`）。
  Widget _edit(String key, String label,
          {String? hint, bool enabled = true, Key? fieldKey}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 150,
              child: Text(label, style: const TextStyle(fontSize: 13)),
            ),
            Expanded(
              child: MCEditBox(
                key: fieldKey,
                controller: _fields[key],
                width: double.infinity,
                height: _h,
                hintText: hint,
                enabled: enabled,
              ),
            ),
          ],
        ),
      );

  /// 枚举行（原版 CycleButton：`gui/components/CycleButton`）。
  Widget _cycle(String label, List<String> values, Map<String, String> texts,
          String current, ValueChanged<String> onChanged,
          {bool enabled = true}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: SizedBox(
          height: _h,
          child: MCCycleButton<String>(
            width: double.infinity,
            height: _h,
            label: label,
            values: values,
            valueText: (v) => texts[v] ?? v,
            initialIndex: values.indexOf(current).clamp(0, values.length - 1),
            enabled: enabled,
            onChanged: onChanged,
          ),
        ),
      );

  /// 布尔行（原版 `CycleButton.onOffBuilder`，`CreateWorldScreen.java:673-676` 的用法）。
  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged,
          {bool enabled = true, Key? fieldKey}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: SizedBox(
          height: _h,
          child: MCCycleButton<bool>(
            key: fieldKey,
            width: double.infinity,
            height: _h,
            label: label,
            values: const <bool>[false, true],
            valueText: (v) => v ? '开' : '关',
            initialIndex: value ? 1 : 0,
            enabled: enabled,
            onChanged: onChanged,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('本地服务器配置'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _section('世界'),
              _edit('name', '名称'),
              // 世界已生成时：种子与极限模式已固化（写进 level.dat），只读并说明。
              if (widget.worldExists)
                const Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Text(
                    '世界已生成：种子与极限模式已固化，改了不生效（原版编辑已有世界只能改名）。',
                    style: TextStyle(fontSize: 12, color: Color(0xFF9E9E9E)),
                  ),
                ),
              // 种子（原版 `CreateWorldScreen.java:738-775` 的 SEED_LABEL/seedEdit：
              // 空值即显示 `selectWorld.seedInfo` 提示——留空 = 随机）。
              _edit('levelSeed', '种子',
                  hint: '留空 = 随机',
                  fieldKey: const Key('localServer.seed'),
                  enabled: !widget.worldExists),
              _cycle('游戏模式', _gamemodes, _gamemodeLabels, _gamemode,
                  (v) => setState(() => _gamemode = v)),
              // 极限模式时难度锁死（`CreateWorldScreen.java:670`：
              // `difficultyButton.active = !isHardcore`）。
              _cycle('难度', _difficulties, _difficultyLabels,
                  _hardcore ? 'hard' : _difficulty,
                  (v) => setState(() => _difficulty = v),
                  enabled: !_hardcore),
              _toggle('极限模式', _hardcore, (v) => setState(() => _hardcore = v),
                  fieldKey: const Key('localServer.hardcore'),
                  enabled: !widget.worldExists),

              _section('服务端端口'),
              _edit('port', '服务端端口'),
              _edit('rconPort', 'RCON 端口'),
              _edit('managementServerPort', '管理服务器端口'),

              _section('高级（产物与 JVM）'),
              _edit('mcVersion', 'MC 版本（产物命名口径）'),
              _edit('protocol', '协议号（须与客户端锚点一致）'),
              _edit('javaMajor', '所需 Java 主版本'),
              _edit('jvmArgs', 'JVM 参数（空格分隔）'),
              _edit('stopTimeoutSeconds', '停止等待上限（秒）'),
              _edit('jarPath', 'jar 路径（留空=按版本解析）'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        TextButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }
}
