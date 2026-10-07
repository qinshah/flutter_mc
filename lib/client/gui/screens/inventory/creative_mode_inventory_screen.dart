import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:mc_render/mc_render.dart';
import 'package:mc_ui/mc_ui.dart';

import '../../../../game/block_icon.dart';
import '../../../../game/block_textures.dart';
import '../../../../world/item/items_26_2.dart' show kItemRegistry262;
import '../screen.dart';

/// `net/minecraft/client/gui/screens/inventory/CreativeModeInventoryScreen.java`
/// 的 Dart 对应物（**组件由 mc_ui 提供 + UI 语义参考原版截图**：搜索框 +
/// 9 列槽位网格滚动，居中面板——用户约定 2026-10-07：不放热键栏镜像行、
/// 不满屏；完整原版——分类页签 / carried 拖拽 / 无限取用拖放 / 销毁格——
/// 未实现，翻译债 `openspec/progress.md` §8）。
///
/// **交互判据**：
/// - E 开/关：`Minecraft.java:1983-1990`（`keyInventory.consumeClick()`）；
/// - E 关闭：`AbstractContainerScreen.java:486-489`（`keyInventory.matches`
///   → `onClose()`）；Esc 关闭走 `Screen.keyPressed` 基类；
/// - 点选 → 替换当前选中热键栏槽位 + 上行（`MultiPlayerGameMode.java:491-495`，
///   `hasInfiniteMaterials` 门控在会话侧）。
///
/// **内容集**：`kBlockStateIdentity262` 全部方块（1196 个，去重取首个 stateId），
/// 经**内置**物品注册序表 `kItemRegistry262`（判据 `Items.java` 注册顺序，由
/// `tool/gen_item_registry_26_2.py` 生成——item 不是同步注册表，原版客户端同样
/// 内置此序）解析 itemId；无对应物品的方块不列出。
class CreativeModeInventoryScreen extends Screen {
  CreativeModeInventoryScreen({
    required this.onPickItem,
    required this.textures,
  }) : super('创造模式物品栏');

  /// 点选回调（app 壳接线：替换选中槽位 + sendCreativeModeSlot 上行）。
  final void Function(String blockName, int itemId, int stateId) onPickItem;

  /// 贴图表（图标采样用；未解析方块显示兜底 UV）。
  final BlockTextures? textures;

  /// 全部可列条目（首次访问构建并缓存：身份表去重 → 内置物品注册序表映射）。
  List<_CreativeEntry>? _entries;

  List<_CreativeEntry> _buildEntries() {
    final seen = <String>{};
    final entries = <_CreativeEntry>[];
    kBlockStateIdentity262.forEach((stateId, identity) {
      final name = BlockSemanticsV262.blockNameOf(stateId);
      if (name == 'minecraft:air' || !seen.add(name)) return;
      // blockNameOf 返回去前缀名（`stone`），注册表键带 `minecraft:` 前缀。
      final itemId = kItemRegistry262['minecraft:$name'];
      if (itemId == null) return; // 非物品方块（空气等）不列
      entries.add(_CreativeEntry(
        name: name,
        stateId: stateId,
        itemId: itemId,
      ));
    });
    return entries;
  }

  /// 判据 `AbstractContainerScreen.java:486-489`：E 关闭本屏。
  @override
  bool keyPressed(KeyEvent event) {
    if (super.keyPressed(event)) return true; // Esc → onClose（基类判据）
    if (event.logicalKey == LogicalKeyboardKey.keyE) {
      onClose();
      return true;
    }
    return false;
  }

  @override
  Widget buildWidget(BuildContext context) {
    // 用户约定 2026-10-07：**居中面板**（非满屏）、无顶部热键栏镜像行
    //（参考官方 UI 图：创造物品栏 = 搜索框 + 槽位网格）。
    return _CreativePanel(screen: this);
  }
}

class _CreativeEntry {
  const _CreativeEntry({
    required this.name,
    required this.stateId,
    required this.itemId,
  });

  final String name; // `minecraft:stone`
  final int stateId; // 贴图采样用（首个 stateId）
  final int itemId; // 物品注册序（上行用）
}

class _CreativePanel extends StatefulWidget {
  const _CreativePanel({required this.screen});

  final CreativeModeInventoryScreen screen;

  @override
  State<_CreativePanel> createState() => _CreativePanelState();
}

class _CreativePanelState extends State<_CreativePanel> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final screen = widget.screen;
    final entries = screen._entries ??= screen._buildEntries();
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? entries
        : entries.where((e) => e.name.contains(q)).toList(growable: false);

    // 居中面板：宽度 = min(视口-32, 380)，格子 = 面板宽 1/9（钳 30..44）——
    // 手机/桌面都是这个量级，不再随满屏宽度放大（用户约定：上一版太大）。
    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: LayoutBuilder(
          builder: (context, viewport) {
            final panelW = math.min(viewport.maxWidth - 32, 380.0);
            final slot = (panelW / 9).clamp(30.0, 44.0);
            return Container(
              width: panelW,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xE6202018),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF3A3A32), width: 1),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // —— 搜索框（原版 `搜索物品`） ——
                  TextField(
                    autofocus: true,
                    style: const TextStyle(
                        color: Color(0xFFE0E0E0), fontSize: 13),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: '搜索物品',
                      hintStyle:
                          TextStyle(color: Color(0xFF8A8A94), fontSize: 12),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                  const SizedBox(height: 6),
                  // —— 9 列槽位网格滚动（可见 5 行，原版网格量级） ——
                  SizedBox(
                    height: slot * 5 + 8,
                    child: GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 9,
                        mainAxisSpacing: 2,
                        crossAxisSpacing: 2,
                        childAspectRatio: 1,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final e = filtered[i];
                        return MCItemSlot(
                          size: slot,
                          onTap: () =>
                              screen.onPickItem(e.name, e.itemId, e.stateId),
                          child: BlockIcon(
                            stateId: e.stateId,
                            textures: screen.textures,
                            size: slot * 0.8,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${filtered.length} 项',
                    style: const TextStyle(
                        color: Color(0xFF9A9AA4), fontSize: 11),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
