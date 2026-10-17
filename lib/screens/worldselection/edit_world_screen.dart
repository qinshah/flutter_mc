// 编辑世界：`net/minecraft/client/gui/screens/worldselection/EditWorldScreen.java` 的对应。
//
// 判据：
//   EditWorldScreen.java:41 —— 名称标签 `selectWorld.enterName`（NAME_LABEL）
//   EditWorldScreen.java:57/:71 —— 唯一的输入框 `nameEdit`（EditBox，宽 200）
//   EditWorldScreen.java:74/:76 —— 保存键 = **重命名**（`selectWorld.edit.save`），且名字为空时禁用
//   EditWorldScreen.java:75 —— 取消键（`CommonComponents.GUI_CANCEL`）
//
// 语义要点（用户要求"语义级翻译原版"）：原版编辑**已有世界**只能改名（+重置图标/打开文件夹/
// 备份/优化），**改不了**世界生成参数（种子/极限模式在创建时固化进 `level.dat`）。
// 要换世界生成参数只能新建世界（原版的「重新创建」本期未做，见 `openspec/progress.md`）。
//
// 本仓差异：形式是对话框（用户偏好系统默认对话框样式 + 可滚动内容），控件仍是
// `MCEditBox`/`MCButton`；原版的重置图标/打开文件夹/备份/优化未做（登记为债）。
import 'package:flutter/material.dart';
import 'package:mc_ui/mc_ui.dart';

import '../../platform/server_host/local_server_config.dart';

/// 打开"编辑世界"（改名）；用户按保存则已写回 `config.name` 并返回 true。
Future<bool?> showEditWorldScreen(
  BuildContext context, {
  required LocalServerConfig config,
}) =>
    showDialog<bool>(
      context: context,
      builder: (ctx) => EditWorldScreen(config: config),
    );

class EditWorldScreen extends StatefulWidget {
  const EditWorldScreen({super.key, required this.config});

  final LocalServerConfig config;

  @override
  State<EditWorldScreen> createState() => _EditWorldScreenState();
}

class _EditWorldScreenState extends State<EditWorldScreen> {
  late final TextEditingController _name =
      TextEditingController(text: widget.config.name);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// 名字为空时禁用保存（判据 `EditWorldScreen.java:76`：
  /// `renameButton.active = !StringUtil.isBlank(newName)`）。
  bool get _canSave => _name.text.trim().isNotEmpty;

  void _save() {
    if (!_canSave) return;
    widget.config.name = _name.text.trim();
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('编辑世界'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 60,
                    child: Text('名称', style: const TextStyle(fontSize: 13)),
                  ),
                  Expanded(
                    child: MCEditBox(
                      controller: _name,
                      width: double.infinity,
                      height: 30,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                '原版编辑已有世界只能改名字/图标；种子、极限模式等世界生成参数在创建时固化。',
                style: TextStyle(fontSize: 12, color: Color(0xFF9E9E9E)),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        // 名字随输入变化实时决定可否保存（原版 setResponder 同法）。
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _name,
          builder: (context, value, _) => TextButton(
            onPressed: value.text.trim().isEmpty ? null : _save,
            child: const Text('保存'),
          ),
        ),
      ],
    );
  }
}
