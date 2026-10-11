# Design

## 判据清单（mc-sources/minecraft-26.2）

| # | 判据 | 位置 |
|---|---|---|
| J1 | travel 总入口与分支（飞行/水/岩浆/空气） | LivingEntity.java:2411-2449 |
| J2 | travelInAir：blockFriction 采样（:2451-2453）→ handleRelativeFrictionAndCalculateMovement（:2454）→ 扣重力 → ×0.98（:2472-2474） | LivingEntity.java:2449-2474 |
| J3 | handleRelativeFrictionAndCalculateMovement：moveRelative(getFrictionInfluencedSpeed(friction), input) 先位移后摩擦 | LivingEntity.java:2655-2665 |
| J4 | getFrictionInfluencedSpeed：friction>0.6 → speed × 0.21600002/friction³ | LivingEntity.java:2699-2701 |
| J5 | getFluidFallingAdjustedMovement / waterMovementDown | LivingEntity.java:2667-2697 |
| J6 | 方块摩擦值：Blocks.java `.friction(0.98F)`（冰 :2929、蓝冰 :1886? 核对）、黏液 0.8 + bounceRestitution :2838 | Blocks.java |
| J7 | moveRelative（Entity.java:1741-）：input 归一 × 速度注入 deltaMovement | Entity.java:1741-1752 |

## 方案要点

- `LocalPlayer` 重写为 travel 全链：`_travel(input)` 分支（飞行/水中/空气）；黄金值 = 离线逐刻递推（含摩擦收敛终速：普通 4.317、疾跑 5.612 的稳态来源即 0.6 摩擦公式）。
- 方块摩擦表：按站立方块（脚下 y-0.5 采样，判据 `getBlockSpeedFactor`/friction 采样点）查身份串 → 摩擦值；未列方块默认 0.6。
- 流体查询：身份串 `minecraft:water[level=n]` 等；waterlogged 属性方块的内部水不产生流体 travel（首切片债）。
- game_screen 拆分：KeyboardHandler 对应物（键位状态机 + 分流）从 state 中抽出，运动装配收敛 LocalPlayer。
