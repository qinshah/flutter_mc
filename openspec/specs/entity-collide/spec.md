# entity-collide Specification

## Purpose
TBD - created by archiving change entity-collide-step-up. Update Purpose after archive.

## Requirements

### Requirement: 逐轴形状截停求解

实体移动 SHALL 按 `collideWithShapes` 语义求解：收集扫掠区域内全部碰撞形状，按 movement 分量排序的轴序逐轴截停（`Direction.axisStepOrder`），轴内用 1.0E-7 精度留隙；无碰撞形状时位移原样返回。

#### Scenario: 贴墙移动截停在墙前

- **WHEN** 实体向墙面移动超过剩余间隙
- **THEN** 该轴位移被截停在墙前 1.0E-7 处，其它轴位移不受影响

### Requirement: 自动上步

实体着地或落地结算时发生水平碰撞，SHALL 按 `maxUpStep`（玩家 0.6）尝试上步：对每个候选台阶高度重解算，取水平位移可行且最大者；上步量超过 `maxUpStep` 的障碍不适用。

#### Scenario: 走上半砖不跳

- **WHEN** 玩家在地面走向 0.5 高的半砖
- **THEN** 自动上步登上半年块，无需跳跃

#### Scenario: 栅栏不可上步

- **WHEN** 玩家走向 1.5 高的栅栏
- **THEN** 上步失败（0.6 < 1.5），被挡住

### Requirement: 着地语义

onGround SHALL 等于"本次移动被 Y 轴截停且位移向下"（`yCollision && movement.y < 0`），MUST NOT 使用独立探针推断；站着不动时 onGround SHALL 保持稳定（不抖动）。

#### Scenario: 平台站立无抖动

- **WHEN** 玩家静止站在实心方块顶面
- **THEN** onGround 每刻稳定为 true，无 true/false 交替
