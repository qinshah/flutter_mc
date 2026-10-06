# Design

## Context

见 proposal.md - Why。此处只记录定位到的**确切判据与顺序**，因为它推翻了最初的直觉。

判据链（`mc-sources/minecraft-26.2`）：
- `LivingEntity.aiStep` 第 3081 行：`if ((this.onGround() || …) && this.noJumpDelay == 0) this.jumpFromGround();`
- `LivingEntity.jumpFromGround`（2370）：`setDeltaMovement(movement.x, Math.max(jumpPower, movement.y), movement.z)`
- `LivingEntity.travel` → `travelInAir`（2449）→ `handleRelativeFrictionAndCalculateMovement`（2655）：
  **先 `move(MoverType.SELF, this.getDeltaMovement())`（位移）**，之后才
  `movementY -= getEffectiveGravity()`（0.08）、再 `setDeltaMovement(… * verticalFriction)`（0.98）
- `Player`/`LivingEntity` 未覆写 `getBlockJumpFactor()`，玩家恒为 1.0
- `Attributes.JUMP_STRENGTH` 默认 0.42（`LivingEntity.java:348` 引用）

**关键**：原版一���内的顺序是「**先按注入后的速度位移，再减重力与摩擦**」。位移用的��
是本刻**尚未扣除重力**的速度，摩擦只影响下一刻。

## Goals / Non-Goals

- 目标：跳跃高度对齐原版逐刻递推（离线核算 **1.2522 格**，与原版公开数据一致），能跳上 1 格方块。
- 目标：竖直积分改为刻边界推进，固定步长（1/120s）只服务碰撞求解。
- 非目标：不实现鞘翅/激流/跳跃药水等状态效果（无 MobEffects体系）。
- 非目标：不动水平行走与飞行（已在 `player-input` 切片对齐原版，勿回归）。

## Decisions

- **D1 刻边界积分，而非连续化**。竖直运动学改为按原版逐刻递推：
  每刻 `y += vy` → `vy = (vy - 0.08) × 0.98`。
  *备选*：保留连续化再放大初速（如 ×1.26凑出 1.25格）。**否决**——那会让"跳跃力属性"
  失去物理含义，且与 `jumpFromGround` 的 `Math.max` 语义冲突；顺序才是原版语义本身。
- **D2 初速口径**。跳跃初速 = `jumpPower / 20.0`（格/刻 → 格/秒），`jumpPower` 取
  `Attributes.JUMP_STRENGTH` 默认 0.42 × `getBlockJumpFactor()`（玩家 1.0）= 8.4 格/秒，
  与既有 `PlayerMotion.jumpVelocity` 一致。注入按 `max(jumpPower, 当前 vy)`。
- **D3 双轨积分**。`_step`（1/120s）内：碰撞求解与水平方向照旧；竖直方向交给刻累加器
  （复用 `player-input` 切片已建的 `_flyAccumTicks` 同类累加器，但独立字段）。
  每个刻边界：先按当前 `vy` 做一次竖直位移，再更新 `vy`。
  *理由*：碰撞需要细步长防穿墙，运动学需要刻对齐；两者目标不同，硬合在一起会互相破坏。
- **D4 `onGround` 语义**。原版 `noJumpDelay = 10`（5 刻内不可再跳）本期**不实现**——
  它只影响连跳手感，不影响最大跳高。落地判定沿用既有 `result.hitY && hasBlockBelow`。

## Risks / Trade-offs

- [刻边界积分与1/120s 碰撞不同步，可能在某帧产生"已越过顶面但碰撞未捕捉"的抖动]
  → 碰撞用玩家 AABB（高 1.8）逐轴求解，跨越 1 格必然被某一子步捕捉；实机验收时观察。
- [`Math.max` 注入在高速下坠时可能不生效（当前 vy 为负）] → 这正是原版语义（下落中按跳不会
  突然获得上升初速），保留。
- [改动波及`game_physics_test.dart` 里依赖旧积分口径的断言] → 按新口径重新离线算黄金值，
  **禁止**为了让旧断言通过而调容差。

## Migration Plan

纯 app 壳物理改动，无数据迁移。回滚 = 单文件 revert。

## Open Questions

无。D1 的顺序判据已从原版源码确认，1.2522 格与原版公开数据吻合，无需再定夺。