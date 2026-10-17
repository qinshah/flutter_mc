# Spec Delta

## ADDED Requirements

### Requirement: 游戏内屏幕为单槽位模型

会话 SHALL 持有至多一个"当前游戏内屏幕"（对应原版 `Gui.screen` 可空字段）。屏幕存在
与否 SHALL 门控游戏输入：无屏幕时才处理游戏键位与指针捕获（判据
`KeyboardHandler.java:516` 口径）。打开新屏幕 SHALL 替换当前屏幕；屏幕 SHALL 经
`PopScope(canPop:false)` 拦截系统返回手势充当 Esc，游戏内屏幕 MUST NOT 使用
Navigator 子路由（因此不存在滑动返回样式问题）。

#### Scenario: 打开屏幕即接管输入

- **WHEN** 游戏中按下 E 打开物品栏
- **THEN** 游戏键位（W/A/S/D 等）停止作用于玩家，指针捕获解除，光标可见

#### Scenario: 系统返回手势充当 Esc

- **WHEN** 无游戏内屏幕时触发系统返回（手势/返回键）
- **THEN** 等价于按 Esc：打开暂停菜单而非退出游戏路由

### Requirement: setScreen 的指针捕获与按键清空调用时机

打开游戏内屏幕 SHALL 依次：解除指针捕获、清空全部按键状态（`KeyMapping.releaseAll`
判据 `Gui.java:269-272`）；关闭屏幕回到游戏 SHALL：恢复切换态按键、重新捕获指针
（判据 `Gui.java:273-281`）。捕获 SHALL 居中为基准并忽略首次位移
（`MouseHandler.java:404-418` 口径）。游戏区被点击且无屏幕时 SHALL 重新捕获
（`MouseHandler.java:80-88` 口径）。

#### Scenario: 关闭暂停菜单即重新捕获

- **WHEN** 在暂停菜单点"回到游戏"
- **THEN** 屏幕关闭、按键状态清空后恢复、指针被捕获并隐藏光标

#### Scenario: 点击画面重新捕获

- **WHEN** 指针未被捕获且游戏区被点击
- **THEN** 指针被捕获，本次点击 MUST NOT 同时触发攻击/使用

### Requirement: Esc 打开暂停菜单

无屏幕时按 Esc SHALL 打开暂停菜单（判据 `KeyboardHandler.java:534-537` pauseGame）。
有屏幕时 Esc SHALL 关闭当前屏幕（Screen.onClose 语义，判据
`KeyboardHandler.java:483-503` screen.keyPressed 路径）。

#### Scenario: Esc 开、再 Esc 关

- **WHEN** 游戏中按 Esc，随后再按 Esc
- **THEN** 先打开暂停菜单；再按则关闭并重新捕获指针

### Requirement: E 打开创造物品栏

玩家具有无限材料（服务器下发 abilities 口径）时按 E SHALL 打开创造物品栏
（判据 `Minecraft.java:1983-1990`）；关闭后返回游戏。创造物品栏内点选物品 SHALL
替换当前选中的热键栏槽位（本地），并 SHALL 上行
`ServerboundSetCreativeModeSlotPacket(slot, stack)`（判据
`MultiPlayerGameMode.java:491-495`，仅 `hasInfiniteMaterials` 为真时发送）。
玩家 SHALL 维护选中槽位状态（对应原版 `Inventory.setSelectedSlot` 口径；
完整物品栏实现另行补齐，属翻译债）。创造物品栏 UI SHALL 采用原版语义（参考官方
截图）：顶部热键栏镜像行（点选切槽）、搜索框、9 列槽位网格滚动；物品图标为图集
sprite 采样。

#### Scenario: 点选替换手持并上行

- **WHEN** 创造物品栏中点选"石头"且当前选中第 0 格
- **THEN** 关闭后第 0 格为石头；期间发出 SetCreativeModeSlot 包（slot=选中槽位，
  stack=石头）

#### Scenario: 无限材料为假不发上行

- **WHEN** 服务器未授予创造/无限材料时点选物品
- **THEN** MUST NOT 发送 SetCreativeModeSlot 包

### Requirement: 热键栏 HUD 与槽位切换

游戏 SHALL 在底部居中常显 9 格热键栏（原版 `Hud` hotbar；屏幕打开时被覆盖层遮住）。
槽位切换 SHALL 支持三种来源，均写入同一选中槽位状态（`Inventory.setSelectedSlot`
判据 `Inventory.java:70-76`）：数字键 1-9（判据 `Minecraft.java:1969-1976`
`keyHotbarSlots[i].consumeClick()`）、滚轮（判据 `MouseHandler.onScroll:208-215` +
`ScrollWheelHandler.getNextScrollWheelSelection:31-42`：`step = signum(wheel)`、
`current -= step`、负数回绕 +9、超界回绕 −9）、点选。选中槽位变化 SHALL 在每刻
检查并上行 `ServerboundSetCarriedItemPacket(short slot)`（判据
`MultiPlayerGameMode.tick:305-307` → `ensureHasSentCarriedItem:317-323`，变化才发）。

#### Scenario: 数字键切槽

- **WHEN** 按 3 键
- **THEN** 选中槽位变为 2（第 3 格高亮）

#### Scenario: 滚轮循环切换

- **WHEN** 选中槽位为 0 时向上滚
- **THEN** 选中槽位回绕到 8（`getNextScrollWheelSelection` 回绕口径）

#### Scenario: 切槽上行

- **WHEN** 选中槽位由 2 变为 3
- **THEN** 发出 SetCarriedItem 包（slot=3）；再次 tick 无变化则不发

### Requirement: PauseScreen 布局按联机形态复原

暂停菜单 SHALL 按 `PauseScreen.java:55-175` 复原联机形态（`hasSingleplayerServer=
false`，判据 `:157-162`）：标题"游戏菜单"；"回到游戏"全宽（点击 = 关闭屏幕 +
重新捕获，判据 `:95-98`）；进度/统计半宽并排；四个图标按钮一排；"选项..."全宽；
底部"断开连接"全宽（`disconnectButtonLabel(false)` 口径，断开回标题屏）。
进度/统计/图标按钮本期 SHALL 置灰（对应屏幕未实现，登记翻译债），MUST NOT 省略占位。

#### Scenario: 回到游戏按钮

- **WHEN** 点击暂停菜单的"回到游戏"
- **THEN** 关闭暂停菜单并恢复游戏，指针重新捕获

#### Scenario: 断开连接按钮

- **WHEN** 点击底部断开按钮
- **THEN** 会话断开并返回标题屏幕
