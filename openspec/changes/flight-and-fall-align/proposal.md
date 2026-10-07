# Proposal

## Why

用户要求把**跳跃、飞行、失焦下落**三态都对齐原版，重点查**速度**与**视角插帧**。
本轮审查（2026-10-07）发现两类偏差：

1. **飞行完全没有插帧** —— `player.yOld` / `tickProgress` 只在行走/跳跃路径更新
   （`player_controller.dart:224`），`_flyingStep` 里从不更新⇒ 20Hz 物理在渲染上
   表现为台阶。判据 `EntityRenderer.extractRenderState`（`EntityRenderer.java:164`）
   对**所有**实体一律 `Mth.lerp(partialTicks, yOld, getY())`，**不区分是否飞行**。
2. **`tickProgress` 从未推进** —— 全仓只有赋值点、没有推进点，插值进度恒为 0 ⇒
   `interpolatedPosition` 直接返回 `position`，插帧形同虚设（行走/跳跃也没真正插上）。

失焦下落路径经实测**已正确**（单帧最大下落 70.20 格/秒 ≤ 终端 78.4；落地 vy=0、
onGround 稳定），无需改动，但需补回归测试固化。

## What Changes

- `_flyingStep` 每跨刻记 `yOld`、每子步推进 `tickProgress`（对齐
  `EntityRenderer.java:164-165` 对全体实体插帧的语义）。
- `tickProgress` 在行走/跳跃路径同样补上推进（当前缺失）。
- 落地静止时的 `y=0.0001` 偏移：查证原版 AABB 是否同样带 epsilon，若一致则保留
  并写明理由。
- 新增回归测试：三态速度黄金值 + 飞行插帧有效性（渲染位置每帧连续变化）。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `remote-play`: 「移动为本地预测加服务器校正」补入**三态（跳跃/飞行/失焦下落）
  的速度与渲染插值**须照原版逐刻递推与插帧。

## Impact

- `lib/game/player_controller.dart`（`_flyingStep` 与 `_step` 补插帧字段推进）
- `test/jump_height_test.dart`（新增飞行插帧与失焦下落回归）
- 不改协议与包边界。