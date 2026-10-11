# Proposal

## Why

`LocalPlayer` 水平运动是"输入直接赋目标速度"的简化（无加速度/摩擦/方块摩擦差异），且无流体物理——与原版 `LivingEntity.travel` 全链（blockFriction → moveRelative → move → ×摩擦）和水/岩浆分支（浮力、游泳）不对齐。冰面打滑、水中游泳、落水缓冲等原版表现全部缺失。

## What Changes

- 逐行翻译 `LivingEntity.travel` 全链：`handleRelativeFrictionAndCalculateMovement`（:2655-2665）、`getFrictionInfluencedSpeed`（:2699-2701）、`blockFriction` 采样（:2451-2453）、`travelInAir`（:2449-2474）。
- 方块摩擦值落地（Blocks.java：默认 0.6、冰/蓝冰/浮冰 0.98、黏液 0.8 + bounceRestitution、灵魂沙 0.4? 按源码核对）。
- 流体分支：水的 `getFluidFallingAdjustedMovement`（:2667-）与 `travel` 水上/水下运动（:2500-2540），游泳上行（space 注入）。
- game_screen 拆分（穿插落点）：输入装配抽 `KeyboardHandler` 对应物，运动装配收敛进 `LocalPlayer` 域。

## Capabilities

### New Capabilities
- `movement-travel-fluids`: 实体 travel 全链——方块摩擦、加速度模型、流体浮力与游泳。

### Modified Capabilities

## Impact

- `lib/client/player/local_player.dart`（运动模型重写，黄金值按离线递推重算）、新增方块摩擦表（mc_render 或会话侧身份串消费）。
- 状态号 → 摩擦/流体的查询依赖 state_identity（复用 block-collision-shapes 的解析面）。
