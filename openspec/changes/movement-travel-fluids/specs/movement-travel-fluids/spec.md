# Spec Delta

## ADDED Requirements

### Requirement: 摩擦驱动的加速度模型

地面/空中水平运动 SHALL 经原版 travel 链：`moveRelative(getFrictionInfluencedSpeed(blockFriction), input)` 注入 → `move()` 位移 → 乘空气/方块摩擦衰减；`getFrictionInfluencedSpeed` 在 `blockFriction > 0.6` 时按 `speed × 0.21600002 / friction³` 放大（冰面）。摩擦值 SHALL 取自站立方块的方块摩擦属性（默认 0.6）。

#### Scenario: 冰面滑行

- **WHEN** 玩家在冰面松开按键
- **THEN** 速度按 0.98 摩擦缓慢衰减（滑行），与普通地面 0.6 的急停不同

### Requirement: 流体浮力与游泳

实体进入水/岩浆 SHALL 走 travel 流体分支：重力按流体口径折减、下浇速度 `waterMovementDown`（默认 -0.03）、按 space 注入上浮，落水速度经 `getFluidFallingAdjustedMovement` 缓冲。

#### Scenario: 落水缓冲与浮起

- **WHEN** 玩家从高处落入深水并按住跳跃
- **THEN** 不受摔落伤害，且持续上浮至水面
