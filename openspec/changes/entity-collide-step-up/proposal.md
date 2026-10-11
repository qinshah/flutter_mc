# Proposal

## Why

实体碰撞求解与原版 `Entity.collide` 不对齐：无自动上步、onGround 靠独立探针（站方块边缘时与整刻竖直结算错拍 ⇒ 实测"卡进方块又卡回"的抽搐）、逐轴顺序固定。碰撞形状体系（block-collision-shapes change）落地后，求解器切换为原版形状语义。

## What Changes

- `VoxelCollision.move` 重写为 `Entity.collide` 对应物：`collideWithShapes`（`Direction.axisStepOrder(movement)` 分量排序逐轴 + `Shapes.collide` 截停，EPSILON 1.0E-7，判据 Entity.java:1249-1263）。
- 自动上步：`maxUpStep = 0.6`（Attributes.STEP_HEIGHT，判据 Entity.java:1144-1177 候选台阶高度重试 + Attributes.java:98-99）。
- onGround 语义对齐：`yCollision && movement.y < 0`（Entity.java:1146），删除 `hasBlockBelow` 0.1 探针。
- `LocalPlayer` 行走/飞行分支的着地判定改读新语义；渲染插值不动。
- game_screen 拆分（穿插落点）：碰撞世界适配（SessionCollisionWorld）已在独立文件；本次把求解器常量与 step 属性移入 collision/local_player 域。

## Capabilities

### New Capabilities
- `entity-collide`: 实体移动碰撞求解——逐轴形状截停、自动上步、着地语义。

### Modified Capabilities

## Impact

- `lib/game/collision.dart`（重写 move + MoveResult）、`lib/client/player/local_player.dart`（着地判定替换）。
- 黄金测试：栅栏跳不上（1.5 > 1.25 跳高）、0.5 台阶/楼梯自动上步、平台上 onGround 无抖动（抽搐回归测试）。
