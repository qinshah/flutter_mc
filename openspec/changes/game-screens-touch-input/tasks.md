# Tasks

## 1. 翻译债载体迁移（先行，独立可验收）

- [x] 1.1 新建 `openspec/progress.md`：按大类迁移 `docs/translation-debt.md` 全部 9 类债 + 命名/路径偏离表为 checkbox（未勾选 = 未完成），保留原版行号与现状列
- [x] 1.2 删除 `docs/translation-debt.md` 与 `docs/` 目录；全仓 grep 确认无残留引用（spec 修订 1.3、代码注释中的 `docs/translation-debt.md` 引用一并改指 `openspec/progress.md`）
- [x] 1.3 按 translation-debt spec delta 修订 `openspec/specs/translation-debt/spec.md`（清单路径 + checkbox 口径）；本次 change 补齐的债项（PauseScreen 置灰按钮、指针近似降级、最小 Inventory、Windows/ohos 无真捕获）登记为未勾选项

## 2. 依赖与基础设施

- [x] 2.1 app 壳 `pubspec.yaml` 添加 `pointer_lock: ^0.4.2+1`（flutter pub add），确认 macOS 构建通过；记录 `isSupported` 在各目标平台的实际返回值（macOS=true，Windows/Linux=false 白名单，ohos/Android/iOS=false——`pointer_lock_method_channel.dart:28`；另按用户决策 MouseHandler 加 `_isDesktop` 门控，移动端不参与捕获）
- [x] 2.2 新建 `lib/client/gui/screen.dart`（Screen 基类：title、keyPressed/onClose 语义）与 `lib/client/gui/gui.dart`（单槽位 `Gui.screen` 字段 + setScreen：screen!=null → 解除捕获 + KeyMapping.releaseAll；null → 恢复切换态 + 捕获；判据 `Gui.java:264-284`）
- [x] 2.3 `MouseHandler` 对应物（判据 `MouseHandler.java:404-429`、`:80-88`）：grabMouse/releaseMouse 包装 pointer_lock，`isSupported=false` 走现有 onPointerMove 近似并注释登记翻译债；grab 的居中基准、ignoreFirstMove、幂等 setScreen(null) 照抄

## 3. 屏幕流程接线

- [x] 3.1 `game_screen.dart` 接入 `Gui`：PopScope(canPop:false) → 无 screen 时 pauseGame / 有 screen 时关闭当前屏（判据 `KeyboardHandler.java:534-537`、`:483-503`）；游戏键位与指针按 `screen() == null` 门控（`:516` 口径）
- [x] 3.2 keybind 分发骨架 `Minecraft.handleKeybinds` 对应（判据 `Minecraft.java:1950-1990`）：本期实现 keyInventory 分支（E → 创造物品栏），togglePerspective/attack/use 等留空分支并注释待补
- [x] 3.3 点击游戏区且无 screen 时重新捕获（`MouseHandler.java:80-88`）；pointer_lock onStateChanged released → releaseAll（失焦等价处理）

## 4. PauseScreen

- [x] 4.1 mc_ui 新增 SpriteIconButton（20 宽、15×15 图标 + tooltip 语义，判据 `PauseScreen.java:102-137` 口径）
- [x] 4.2 `lib/client/gui/screens/pause_screen.dart`：联机形态布局——标题"游戏菜单"、"回到游戏"204 全宽（→ setScreen(null)+grabMouse，判据 `:95-98`）、进度/统计半宽置灰、四图标置灰（报告漏洞按 `:107` isSideSeries 口径）、"选项..."全宽（`:161` 联机分支）、"断开连接"全宽（`:164-175` disconnectButtonLabel(false) → 断开会话回标题屏）
- [x] 4.3 Esc 在 PauseScreen 内 = 关闭并重新捕获；截图对照验收（联机形态按钮集合）

## 5. 创造物品栏

- [x] 5.1 玩家侧最小 Inventory：`lib/world/entity/player/inventory.dart` 的 `selectedSlot` 状态（判据 `Inventory.setSelectedSlot` 口径；完整 Inventory 登记翻译债）
- [x] 5.2 `lib/client/gui/screens/inventory/creative_mode_inventory_screen.dart`：组件照 fscraft `creative_inventory_dialog.dart`（列表+搜索+点选），点选 → 替换选中槽位 + E 开/关（判据 `Minecraft.java:1983-1990`）
- [x] 5.3 `mc_protocol_v26_2` 确认/补 `ServerboundSetCreativeModeSlotPacket` 编解码；mc_session 接 `handleCreativeModeItemAdd` 判据（`MultiPlayerGameMode.java:491-495`：hasInfiniteMaterials 才发，slot=选中槽位）
- [ ] 5.4 联机实测：点选后服务器侧手持变更（第三方视角或服务端日志）

## 6. 触控 hub

- [x] 6.1 mc_ui 新增触控按钮样式控件（半透明深底+白描边圆角+单色图标，按用户新 UI 图；Listener+opaque，多点同时按住，判据 fscraft touch_hud 口径）
- [x] 6.2 mc_ui 新增 TouchHub 组件：左下 D-pad（▲▼◀▶+中央◆跳）、右下潜行、顶部 Esc/E；只做手势→键位翻译，按钮语义注入，无游戏逻辑；未命中区域指针穿透场景层
- [x] 6.3 app 壳 InputSource 检测（touch/stylus → touch）：`visible = source == touch`（fscraft `game_page.dart:393-446` 口径）；hub 接线到 KeyMapping 同一路径（down/up → 集合 add/remove），双击跳复用 player-input 飞行窗口
- [ ] 6.4 ohos/触屏实测：多点前进+跳、hub 显隐切换、Esc/E 按钮触发屏幕流程

## 7. 验证

- [x] 7.1 单测：KeyMapping 触控等价性（触控 down/up 后输入标志 == 键盘同键位）；Gui.setScreen 时序（开屏 releaseAll+解捕获、关屏恢复+捕获，黄金序列断言）
- [ ] 7.2 macOS 全链路实测两遍：E 开物品栏点选→手持变更→服务器确认；Esc→暂停→回到游戏→重新捕获；指针出窗视角连续（takeDelta）
- [ ] 7.3 对照截图验收 PauseScreen 布局（联机形态）；全仓 grep 确认无 `docs/translation-debt.md` 残留、无"简化"注释未登记 progress.md
