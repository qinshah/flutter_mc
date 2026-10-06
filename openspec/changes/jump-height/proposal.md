# Proposal

## Why

实机验收发现玩家**跳不上 1 格高的方块**：空格有起跳动画与竖直速度，但高度差一点点够不到方块顶面。定量的根因是本地物理把原版的**逐刻递推**换成了连续化阻尼（`exp(-k·dt)`），两者每子步只差 ~1e-6，但累积后最大跳高落在 **0.9969 格**——恰好差 0.0031 够不到 1 格。这是 `remote-play` 移动预测契约的直接违约：移动语义要求"照原版单玩家本地计算"，而当前实现引入了非原版的积分方式。

## What Changes

- 玩家竖直运动改为**逐刻（1/20s）递推**，照原版 `LivingEntity.aiStep` 的时序：每个刻边界先按 `jumpFromGround` 注入初速（取 `Math.max(jumpPower, 当前 vy)`），再减重力、再乘空气阻力 ×0.98。固定步长（1/120s）仍用于碰撞求解，但**运动学积分只在刻边界推进**，避免连续化与原版语义漂移。
- 跳跃初速按 `Attributes.JUMP_STRENGTH`（0.42/刻 = 8.4 格/秒）与 `getBlockJumpFactor()`（玩家默认 1.0）取值，不再直接赋值覆盖既有竖直速度。
- 新增跳跃高度的单测黄金值：以逐刻递推离线算出「跳上 1 格 / 1 格台阶」的判定，MUST 在回归中守住。

**非目标**：不实现鞘翅/激流/跳跃药水等状态效果（无 MobEffects）；不改水平行走与飞行（已在 `player-input` 切片对齐）。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `remote-play`: 「移动为本地预测加服务器校正」的跳跃语义从"连续化阻尼近似"改为"逐刻递推照原版"，并新增"跳上 1 格高方块"的可验证场景。

## Impact

- `lib/game/player_controller.dart`（竖直积分改为刻边界递推；新增跳跃初速注入口径）
- `lib/game/player.dart`（可能需要暴露刻级速度换算，与 `player_controller` 的 `格/刻`口径对齐）
- `test/`（新增跳跃高度黄金值单测；`game_physics_test.dart` 中若有依赖旧积分口径的断言需按新口径重标）
- 不改协议与包边界：纯 app 壳物理改动，`packages/` 无需变更