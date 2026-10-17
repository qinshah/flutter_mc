# player-input Specification

## Purpose

定义玩家输入控制的契约：鼠标视角换算（原版灵敏度公式）、双击空格切换创造飞行（jumpTriggerTime 窗口语义）、abilities 服务器权威摄入、输入标志与飞行状态的上报（变更即发）、失焦不残留按键与指针捕获。

## Requirements

### Requirement: 鼠标视角按原版公式换算

视角 SHALL 由指针位移驱动：`sens = (0.6×灵敏度 + 0.2)³ × 8.0`（灵敏度默认 0.5）、`xRot += dy × 0.15`、`yRot += dx × 0.15`（度/像素），pitch SHALL 钳制 ±90°。

#### Scenario: 灵敏度默认值下的转角

- **WHEN** 灵敏度为默认 0.5 且鼠标横向移动 10 像素
- **THEN** yaw 变化 1.5°（0.15×10×1.0）

### Requirement: 双击空格切换创造飞行

当服务器下发的 abilities 允许飞行（mayfly）时：上刻未按、本刻按下空格 SHALL 记 7 个固定步的判定窗口；窗口内再次按下 SHALL 切换 flying（起飞瞬间在地面则补一次起跳），窗口过期则重新等待双击。切换 SHALL 经 ServerboundPlayerAbilitiesPacket 上报。mayfly 为假时 MUST NOT 触发。旁观态恒飞行不实现（本项目无旁观模式）。

#### Scenario: 双击切飞、三连击不抖动

- **WHEN** mayfly=true，双击空格后立刻第三次按下
- **THEN** 第一次双击切换为飞行并上报；第三下不再切换（窗口已被重置，重新计双击）

### Requirement: abilities 以服务器下发为准

会话 SHALL 解析服务器下发的 PlayerAbilities（mayfly/flying/flyingSpeed），作为飞行可行性与飞行物理参数的唯一来源；本地切换飞行只改变上报意图，物理使能以最近一次下发为准。

#### Scenario: 生存模式双击无效

- **WHEN** 服务器下发 mayfly=false 时双击空格
- **THEN** 不切换飞行、不上报

### Requirement: 输入标志变更即上报

会话 SHALL 维护上次上报的输入标志（前/后/左/右/跳/潜行/疾跑 7 位），仅在其变化时发送 ServerboundPlayerInputPacket（照原版 lastSentInput 口径，而非每刻重发）。

#### Scenario: 静止不上行

- **WHEN** 输入标志长时间不变
- **THEN** 不产生 PlayerInput 包（移动位置仍按既有 MovePlayer 口径上行）

### Requirement: 失焦不残留按键状态

应用 SHALL 在窗口失去焦点（应用进入非活跃生命周期状态）时立即清空"当前按下的按键"集合与尚未消费的帧内输入（如鼠标位移）。此后 MUST NOT 继续产生任何按键相关的移动/飞行上行，直到玩家重新按下该键。系统 MUST NOT 因此触发操作系统的"无效按键"提示（即不得留下有keyDown 无 keyUp 的未配对按键）。

#### Scenario: 失焦后按键不卡住

- **WHEN** 玩家按住 W 前进中切到其它应用（窗口失焦），随后切回并松开所有键
- **THEN** 失焦瞬间 W 即被释放；切回后玩家不会继续自行前进，也不会出现系统按键提示音

#### Scenario: 失焦后不产生移动上行

- **WHEN** 窗口失焦时玩家正按住前进键
- **THEN** 失焦后 SHALL NOT 再发送"前进"输入标志；按键状态恢复为全部松开

### Requirement: 游戏区点击即恢复焦点与指针捕获

游戏区 SHALL 在被点击时把键盘焦点取回本屏，使失焦后无需切换窗口即可恢复键盘操作。
指针 SHALL 在游戏进行中被捕获到窗口内并隐藏光标，避免光标移出窗口导致相对位移失真；
SHALL 提供解除捕获的按键（`Esc`），解除时同样清空按键状态。

指针捕获 SHALL 分级实现：平台支持真捕获时（`pointer_lock` 的 `isSupported`，当前仅
macOS 与 Web 浏览器）SHALL 使用 pointer_lock 捕获指针并以相对位移（`takeDelta` 口径）
驱动视角；不支持的平台（Windows 上游未支持、ohos/Android 无指针）SHALL 保留原生近似
（指针越界即停止响应位移）作为降级路径，且 SHALL 在代码登记为翻译债。降级路径的其余
语义（点击恢复焦点、Esc 解除、清空按键）与真捕获路径完全一致。

pointer_lock 的 capture/release 调用时机 SHALL 由游戏内屏幕的打开/关闭判据链决定
（见 in-game-screens 能力），MUST NOT 散落随意调用。包在失焦时自行释放捕获 SHALL
被接住并等价处理为失焦：清空按键状态。

#### Scenario: 失焦后点击即恢复

- **WHEN** 玩家失焦后点击游戏画面
- **THEN** 键盘焦点回到本屏，随后按键能正常控制移动与视角

#### Scenario: Esc 解除指针捕获并清空按键

- **WHEN** 指针被捕获时按下 `Esc`
- **THEN** 指针捕获解除、光标恢复可见，且当前按下的按键全部视为松开

#### Scenario: 指针捕获下视角连续

- **WHEN** 指针被捕获且光标已移出窗口边界
- **THEN** 视角 SHALL 继续按相对位移变化，MUST NOT 停止响应

#### Scenario: macOS 真捕获以相对位移驱动

- **WHEN** macOS 上 `isSupported` 为真且指针被捕获
- **THEN** 视角位移 SHALL 来自 pointer_lock 的相对增量，MUST NOT 依赖绝对光标位置

#### Scenario: 不支持平台的降级一致

- **WHEN** 在 ohos/Windows 降级路径下失焦
- **THEN** 按键清空、捕获解除语义与 macOS 真捕获路径完全一致

#### Scenario: 捕获被系统意外释放

- **WHEN** 捕获中发生 Cmd+Tab 等系统级释放（onStateChanged released）
- **THEN** 按全部按键已松开处理，恢复捕获前 MUST NOT 产生移动/飞行上行
