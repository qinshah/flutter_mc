# Proposal

## Why

客户端进入游戏后没有任何"游戏内屏幕"（暂停菜单、物品栏）与触控操作：Esc/E 无响应、
触屏设备（ohos/Android）完全无法操作。同时指针捕获仍是"原生近似"（`game_screen.dart`
onPointerMove 断流判越界），转视角在指针出窗时会失真。本轮把这两块一次补齐：屏幕流程
照 26.2 源码逐行复原，触控为自由设计（输入采集类），UI 暂借 fscraft 自定义组件。

## What Changes

- **游戏内屏幕框架（逐行复原）**：翻译 `Gui.setScreen`（`Gui.java:264-284`）为单槽位
  screen 模型——`screen != null` 时 releaseMouse + `KeyMapping.releaseAll()`，`null` 时
  grabMouse；`MouseHandler.grabMouse/releaseMouse`（`MouseHandler.java:404/422`）；
  Esc（`KeyboardHandler.java:534` → pauseGame）、E（`Minecraft.java:1983` → 物品栏）。
- **pointer_lock 真捕获**：app 壳新增 `pointer_lock: ^0.4.2+1`；capture/release 的调用
  时机完全由 `Gui.setScreen` 判据链决定；macOS 真捕获，`isSupported=false` 平台
  （Windows 未支持 / ohos 不适用）保留现有近似并登记翻译债。
- **PauseScreen 全量复原**：按 `PauseScreen.java:55-175` + 官方截图；走联机分支
  （`hasSingleplayerServer=false` → 选项 204 全宽、无局域网按钮，`:161`）；进度/统计/
  四个图标按钮先置灰并登记翻译债。
- **创造物品栏（组件借 fscraft）**：E 开/关，点选 → 替换当前选中热键栏槽位；联机上行
  照 `MultiPlayerGameMode.handleCreativeModeItemAdd`（`MultiPlayerGameMode.java:491-495`）
  → `ServerboundSetCreativeModeSlotPacket(slot, clicked)`。
- **触控 hub（自由设计·输入采集）**：mc_ui 新增触控按钮样式（按用户新 UI 图：半透明
  深底 + 白描边圆角）与 TouchHud（D-pad、跳、潜行、Esc、E 等）；按最近输入类型
  （touch vs 键鼠）显隐（参考 fscraft `game_page.dart:393-446` 口径）；触控按钮按下
  等价于对应 KeyMapping 键按下（语义复原、采集自由）。
- **系统返回 = Esc**：`PopScope(canPop:false)` 拦截系统返回/手势充当 Esc（fscraft
  `game_page.dart:736-741` 口径）；游戏内屏幕不走 Navigator 子路由，无滑动返回问题。
  **不引入 go_router**：原版是单槽位 screen 字段而非 URL 路由（见 design.md）。
- **翻译债迁移**：`docs/translation-debt.md` 迁入 `openspec/progress.md`（按大类
  checkbox，未勾选 = 未完成），删除 `docs/`，同步修订 translation-debt 能力的清单路径。

## Capabilities

### New Capabilities
- `in-game-screens`: 游戏内屏幕框架——Gui/Screen 单槽位模型、Esc/E 键流程、PauseScreen
  布局与按钮、创造物品栏点选替换与 SetCreativeModeSlotPacket 上行。
- `touch-input`: 触控输入采集——输入类型检测驱动 hub 显隐、触控按钮 → KeyMapping
  等价按下、系统返回手势充当 Esc。

### Modified Capabilities
- `player-input`: "指针捕获" requirement 升级——pointer_lock 真捕获为主路径，
  `isSupported=false` 平台保留原生近似为降级路径。
- `mc-ui-components`: 新增触控按钮样式与 TouchHub 组件 requirement（mc_ui 唯一
  Flutter 例外的范畴内）。
- `translation-debt`: 清单载体由 `docs/translation-debt.md` 变更为
  `openspec/progress.md`（checkbox 进度口径）。

## Impact

- app 壳 `lib/`：`game/game_screen.dart`（pop 拦截、hub 接线、takeDelta 接线）、
  新增 `client/gui/gui.dart` 等（路径照 `net/minecraft/client/gui/` 对齐）、
  `screens/pause_screen.dart`、`screens/inventory/creative_mode_inventory_screen.dart`。
- `packages/mc_ui`：触控按钮样式 + TouchHud。
- `packages/mc_session` / `mc_protocol_v26_2`：`ServerboundSetCreativeModeSlotPacket`
  编解码（若未注册则补）。
- `pubspec.yaml`：新增 pointer_lock 依赖。
- 流程文档：`openspec/progress.md`（新）、`docs/translation-debt.md`（删）。
