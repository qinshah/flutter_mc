# Design

## Context

现有输入层：`lib/game/key_map.dart`（KeyMapping 对应物，判据 `KeyMapping.java:57`
releaseAll）、`game_screen.dart` 的 Focus+Listener 键盘接入、指针"原生近似"
（onPointerMove 断流判越界）。无游戏内屏幕；无触控；`lib/screens/` 只有菜单链。
fscraft 提供三样参考实现：`ui/touch_hud.dart`（多点触控 HUD）、
`game_page.dart:736-741`（PopScope 拦截返回）、`ui/creative_inventory_dialog.dart`
（点选替换热键栏槽位）。

## Goals / Non-Goals

**Goals**
- Esc/E → 屏幕切换流程逐行对齐 26.2；pointer_lock 调用时机由该流程驱动。
- PauseScreen 布局与按钮可复现官方截图（联机形态）。
- 创造物品栏点选可替换手持，联机上行 SetCreativeModeSlotPacket。
- 触屏设备（ohos/Android）可操作：移动/跳/潜行/开背包/开暂停。

**Non-Goals**（另行 change 或登记债）
- startAttack/startUseItem 全量逻辑（右键工作台等）——本期只留 keybind 分发骨架。
- AdvancementsScreen / StatsScreen / SocialInteractionsScreen 内容——按钮置灰 + 债。
- hotbar HUD（触控图中的热键栏属 GUI hud 能力，另行 change）。
- Windows/ohos 的指针真捕获——等 pointer_lock 上游支持。

## Decisions

### D1. 屏幕模型 = 单槽位字段，不走 Navigator 子路由

原版是 `Gui.screen` 可空字段（`Gui.java:264`），`KeyboardHandler.java:516` 用
`screen() == null` 门控游戏输入——"当前有没有屏幕"是被多方查询的**状态**，不是路由栈。
Dart 侧翻译为 `Gui` 类持有 `Screen?`，渲染为 GameScreen 内 Stack 覆盖层。
备选（fscraft 把暂停菜单推成独立路由）被否：路由栈语义会把 `screen()` 查询变成
Navigator 状态查询，且引入滑动返回样式问题。**不引入 go_router**：原版不是 URL
导航，Navigator 保留给菜单链（`routes.dart`）已足够；不新增架构规则。

### D2. 系统返回手势 = Esc

`PopScope(canPop:false)` 拦截（判据 fscraft `game_page.dart:736-741`；Java 判据
`KeyboardHandler.java:534`）：无 screen → pauseGame（开 PauseScreen）；有 screen →
关闭当前 screen（Screen.onClose 语义）。游戏内屏幕不走路由 ⇒ 无滑动返回需要禁用。

### D3. pointer_lock 调用时机完全照 Gui.setScreen

`MouseCapture.instance`（包 API：`capture()` / `release()` / `takeDelta()` /
`isSupported` / `onStateChanged`）。时机（判据 `Gui.java:269-281`）：

```
setScreen(screen != null): releaseMouse() + KeyMapping.releaseAll()
setScreen(null):           restoreToggleStatesOnScreenClosed() + grabMouse()
grabMouse (MouseHandler.java:404): 置 grabbed、居中基准、ignoreFirstMove、
                            gui.setScreen(null)（幂等递归照抄）
```

- macOS（`isSupported=true`）：视角位移改从 `takeDelta()` 每帧取（替代近似）。
- `isSupported=false`（Windows "not yet"、ohos/Android 不适用）：保留现有
  onPointerMove 近似——**翻译债**，不叫自由设计。
- 包在失焦时自行 drop capture 并发 onStateChanged → 接 `KeyMapping.releaseAll()`
  （对齐 player-input spec 的失焦 requirement 与原版 `setWindowActive` 路径）。

### D4. PauseScreen 走联机分支

`PauseScreen.java:157-161`：`hasSingleplayerServer()=false` → 选项按钮 204 全宽、
无"对局域网开放"；`:164-175` disconnect 文案取 `disconnectButtonLabel(false)`
（"断开连接"）。截图（官方单人）仅作布局与视觉参照。进度/统计/四图标按钮按源码
创建但 `active=false`，债登记见 progress.md。控件布局照 `GridLayout(2 列)` 语义用
Flutter 等价排版；`SpriteIconButton` 20 宽 + 15×15 sprite 进 mc_ui。

### D5. 创造物品栏：组件借 fscraft，上行照原版

- 组件与交互照 fscraft `creative_inventory_dialog.dart`（列表 + 搜索 + 点选），
  落位 `lib/screens/inventory/creative_mode_inventory_screen.dart`（路径对齐
  `client/gui/screens/inventory/CreativeModeInventoryScreen.java`）。
- 点选 → 替换当前选中热键栏槽位（本地状态）+ 联机上行照
  `MultiPlayerGameMode.handleCreativeModeItemAdd`（`:491-495`）：
  `hasInfiniteMaterials()` 为真才发 `ServerboundSetCreativeModeSlotPacket(slot, stack)`。
- E 开/关判据 `Minecraft.java:1983-1990`（`keyInventory.consumeClick()`）；
  `isServerControlledInventory()` 分支本期恒 false（服务器未下发时）。
- 玩家侧新增最小 `Inventory.selectedSlot` 状态（完整 Inventory 类登记债）。

### D6. 触控 hub：mc_ui 提供组件，app 壳接线

- `mc_ui`（Flutter 例外包）新增：触控按钮样式（新 UI 图：半透明深底 + 白描边圆角、
  白色单色图标）与 TouchHud（D-pad ◆=跳/▲▼◀▶=移动、潜行、Esc、E 按钮）。无 Java
  对应物，属输入采集自由设计，注释标明。
- 显隐：app 壳 `game_screen.dart` 记录最近 InputSource（`PointerDeviceKind.touch/
  stylus` → touch），`visible = source == touch`（fscraft `game_page.dart:393-446`
  口径）。
- 语义等价：按钮 down/up 翻译成 KeyMapping 集合的 add/remove（与键盘同一路径，
  `key_map.dart:update`），双击跳 = 既有 player-input 飞行窗口语义复用。
- T/Input/Enter/BackSp/丢弃/使用等按钮不进本期（聊天与 use 逻辑未实现）。

### D7. 翻译债载体迁移

`docs/translation-debt.md` 全量迁入 `openspec/progress.md`：按大类分组、每债一条
checkbox，未勾选 = 未完成；"命名/路径偏离"表同迁。translation-debt 能力 spec 的
清单路径同步修订。删除 `docs/` 目录。

## 判据清单（审查门禁）

| 判据 | 行号 |
|---|---|
| `Gui.setScreen`（release/grab 时机、releaseAll、init） | `Gui.java:264-284` |
| `MouseHandler.grabMouse / releaseMouse` | `MouseHandler.java:404-429` |
| 点击游戏区重新捕获 | `MouseHandler.java:80-88` |
| Esc → pauseGame / screen.keyPressed | `KeyboardHandler.java:534-537`、`:483-503` |
| `keyInventory` → InventoryScreen | `Minecraft.java:1983-1990` |
| `handleKeybinds` 分发骨架 | `Minecraft.java:1950-2030` |
| PauseScreen 按钮与布局 | `PauseScreen.java:55-175` |
| 联机分支（无单人服务器） | `PauseScreen.java:157-162` |
| 创造点选上行 | `MultiPlayerGameMode.java:491-495` |
| `KeyMapping.releaseAll` | `KeyMapping.java:57` |
| 数字键热键栏 | `Minecraft.java:1969-1976` |
| 滚轮切槽 | `MouseHandler.onScroll:208-215` + `ScrollWheelHandler.java:31-42` |
| 手持槽位上行 | `MultiPlayerGameMode.java:305-307/:317-323` |
| SetCarriedItem 包 | `ServerboundSetCarriedItemPacket.java:25-27`（id=53，GameProtocols.java:114） |
| 物品注册序表 | `Items.java` 注册序（`tool/gen_item_registry_26_2.py` 生成） |

## Risks / Trade-offs

- [pointer_lock 仅 macOS+Web，Windows/ohos 无真捕获] → isSupported 分支 + 现有近似
  兜底；债登记；上游更新时回访（记忆项：定期回访 flutter_scene/依赖 upstream）。
- [capture 失败/意外释放（Cmd+Tab）] → onStateChanged 收 released 即按失焦处理
  （releaseAll），不假设 capture 常驻。
- [PauseScreen 置灰按钮与官方截图观感差异] → 截图为单人形态，联机分支本就少按钮；
  债登记"进度/统计不可达"。
- [触控按钮语义绕过 KeyMapping 会产生两套输入路径] → D6 强制同路径；测试断言
  触控 down/up 后输入标志与键盘等价。

## Migration Plan

纯增量：新文件 + game_screen 接线改造；pointer_lock 失败自动降级近似，不阻塞现有
桌面链路。progress.md 迁移后删 docs/，一次提交内完成，无回滚面。

## Open Questions

无（InventoryScreen 的 isServerControlledInventory 分支服务器未下发即恒 false，
已按现状收窄）。
