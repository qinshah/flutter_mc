import 'package:flutter/material.dart';


/// 原版物品槽位（`gui/screens/inventory/AbstractContainerScreen` 的 slot 视觉：
/// 20×20 GUI 像素、内凹深底；选中时白色高亮描边，判据 hotbar 高亮
/// `Hud.java` 的 selected 纹理口径）。
///
/// 内容 [child] 由调用方注入（物品图标 = 图集 sprite，见 app 壳 block_icon）；
/// [onTap] 为空时纯展示。
class MCItemSlot extends StatelessWidget {
  const MCItemSlot({
    super.key,
    this.child,
    this.selected = false,
    this.onTap,
    this.size = 20,
  });

  final Widget? child;
  final bool selected;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final slot = Container(
      width: size,
      height: size,
      // 原版槽位：深灰内凹底 + 深边框（未选中）。
      decoration: BoxDecoration(
        color: const Color(0xFF8B8B8B),
        border: Border.all(
          color: selected ? const Color(0xFFFFFFFF) : const Color(0xFF373737),
          width: selected ? 2 : 1,
        ),
      ),
      alignment: Alignment.center,
      child: child,
    );
    if (onTap == null) return slot;
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: slot);
  }
}

/// 9 格热键栏（原版 `Hud` 的 hotbar 渲染：底部居中一行 20×20 槽位，
/// 选中槽白色外扩描边）。
///
/// 槽位内容 [icons]（可为 null = 空槽）；选中/点击回调由 app 壳接线
/// （数字键/滚轮/点选的判据在 app 壳：`Minecraft.java:1969-1981` 与
/// `MouseHandler.onScroll`）。组件本身无游戏逻辑。
class MCHotbar extends StatelessWidget {
  const MCHotbar({
    super.key,
    required this.icons,
    required this.selectedIndex,
    this.onSelect,
    this.slotSize = 20,
  });

  /// 9 个槽位的图标 widget（null = 空槽）。
  final List<Widget?> icons;

  /// 当前选中槽位（0-8）。
  final int selectedIndex;

  /// 点击选择（触屏用；键盘/滚轮在输入层）。
  final void Function(int index)? onSelect;

  final double slotSize;

  @override
  Widget build(BuildContext context) {
    assert(icons.length == 9);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 9; i++)
          MCItemSlot(
            selected: i == selectedIndex,
            size: slotSize,
            onTap: onSelect == null ? null : () => onSelect!(i),
            child: icons[i],
          ),
      ],
    );
  }
}
