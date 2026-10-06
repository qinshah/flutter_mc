# Proposal

## Why

游玩体验的下一块：鼠标视角与创造飞行。原版判据已读齐（MouseHandler.turnPlayer 灵敏度公式、LocalPlayer.aiStep 双击空格切飞行、tick 内 lastSentInput 变更即发 PlayerInput、切换飞行上报 ServerboundPlayerAbilitiesPacket）。服务器为创造模式，abilities 链路可端到端验证。

## What Changes

- mc_protocol_v26_2：新增三个包编解码——clientbound PlayerAbilities（标志位+飞行速度，我们此前完全不解析）、serverbound PlayerAbilities（1 字节 flying 位，id 40）、serverbound PlayerInput（7 布尔位打包，id 43）
- mc_session：会话持有 abilities 状态（mayfly/flying/flyingSpeed，随下发更新）；`sendAbilities(flying)` 与 `sendInputFlagsIfChanged(...)`（变更即发，照原版 lastSentInput 口径）
- app 壳：鼠标视角（原版灵敏度公式 `(0.6s+0.2)³×8.0` + 0.15°/像素 + pitch ±90°）；双击空格切飞行（7 固定步窗口，照 jumpTriggerTime）；飞行物理分支（无重力、空格升/Shift 降、flyingSpeed、不卡边豁免）；指针捕获沿用全屏 Listener（pointer-lock 留后）

## Capabilities

### New Capabilities

- `player-input`：视角控制、飞行切换与输入上报的契约

### Modified Capabilities

（无——remote-play 的移动上行契约不变，本次为增补能力）

## Impact

- `packages/mc_protocol_v26_2/`（+3 编解码）、`packages/mc_session/`（状态+2 API）、`lib/game/`（控制器飞行分支、双击窗口）、`lib/game/game_screen.dart`（鼠标视角+abilities 接线）
- 服务器需创造/OP 才有 mayfly（用户确认其服务器为创造）
