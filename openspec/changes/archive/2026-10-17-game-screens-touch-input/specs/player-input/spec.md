# Spec Delta

## MODIFIED Requirements

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
