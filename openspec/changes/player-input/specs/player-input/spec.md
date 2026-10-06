# Spec Delta

## Purpose

定义玩家输入控制的契约：鼠标视角换算（原版灵敏度公式）、双击空格切换创造飞行（jumpTriggerTime 窗口语义）、abilities 服务器权威摄入、输入标志与飞行状态的上报（变更即发）。

## ADDED Requirements

### Requirement: 鼠标视角按原版公式换算

视角 SHALL 由指针位移驱动：`sens = (0.6×灵敏度 + 0.2)³ × 8.0`（灵敏度默认 0.5）、`xRot += dy × 0.15`、`yRot += dx × 0.15`（度/像素），pitch SHALL 钳制 ±90°。

#### Scenario: 灵敏度默认值下的转角

- **WHEN** 灵敏度为默认 0.5 且鼠标横向移动 10 像素
- **THEN** yaw 变化 1.5°（0.15×10×1.0）

### Requirement: 双击空格切换创造飞行

当服务器下发的 abilities 允许飞行（mayfly）时：上刻未按、本刻按下空格 SHALL 记 7 个固定步的判定窗口；窗口内再次按下 SHALL 切换 flying（起飞瞬间在地面则补一次起跳），窗口过期则重新等待双击。切换 SHALL 经 ServerboundPlayerAbilitiesPacket 上报。mayfly 为假时 MUST NOT 触发。旁观态恒飞行的规则本期不实现（无旁观模式）。

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
