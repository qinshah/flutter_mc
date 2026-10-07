/// `net/minecraft/world/entity/player/Inventory.java` 的 Dart 对应物
/// （**最小实现**：仅创造点选需要的选中槽位状态；完整 36 格物品栏、
/// carried/drag 语义、装备栏未实现——翻译债，见 `openspec/progress.md` §8）。
///
/// 判据：
/// - `:31` `SELECTION_SIZE = 9`；
/// - `:66-68` `getSelectedSlot()`；
/// - `:70-76` `setSelectedSlot(selected)`：`isHotbarSlot` 不合法即抛
///   `IllegalArgumentException`；
/// - `:130-132` `isHotbarSlot(slot)` = `slot >= 0 && slot < 9`。
class Inventory {
  /// 热键栏大小（判据 `Inventory.java:31`）。
  static const int selectionSize = 9;

  int _selected = 0;

  int getSelectedSlot() => _selected;

  void setSelectedSlot(int selected) {
    if (!isHotbarSlot(selected)) {
      throw ArgumentError('Invalid selected slot'); // 判据 :72
    }
    _selected = selected;
  }

  /// 判据 `Inventory.java:130-132`。
  static bool isHotbarSlot(int slot) => slot >= 0 && slot < 9;
}
