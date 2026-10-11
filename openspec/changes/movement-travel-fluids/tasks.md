# Tasks

## 1. travel 链（行走）——2026-10-11 提前落地

实机三症状（走出高方块瞬时终端下坠 / 空中移动过快 / 贴墙抽搐卡死）的根因就是
缺 travel 全链与 restitute，经用户要求按源码对齐，随实机修复一并实施。

- [x] 1.1 逐行翻译 `LivingEntity.travelInAir`（:2449-2477）行走全链：`_travelWalkingTick` 每刻一次（注入 → move 整刻位移 → restitute 清零 → 重力 → 摩擦），与飞行路径同构（刻累加器 + 渲染插值）
- [x] 1.2 方块摩擦表（`BlockCollisionShapes.frictionFor`：ice 族 0.98 / 蓝冰 0.989 / 黏液 0.8 / 默认 0.6）+ 冰面 f>0.6 的 f³ 公式分支 + `CollisionWorld.blockFrictionAt`（`getOnPos(0.500001)` 脚下采样）
- [x] 1.3 restitute（Entity.java:793-795/:851-853）碰撞轴清零（行走全轴；飞行仅水平轴——Y 被 `Player.travel` 的 originalMovementY×0.6 覆盖）
- [x] 1.4 疾跑跳助推（LivingEntity.java:2378-2381；我们 yaw 约定与原版 yRot 差 180°，助推 = 前进方向 ×0.2）
- [x] 1.5 回归测试 `travel_chain_test` 5 项（站立 vy=−0.0784、走出慢加速递推、空中 0.02/刻渐变、正对墙 120 刻位置恒定、贴墙斜向滑行 12+ 格、疾跑跳助推）

## 2. 流体与拆分（待实现）

- [ ] 2.1 流体 travel 分支（水/岩浆：`travelInFluid` + `getFluidFallingAdjustedMovement`）
- [ ] 2.2 game_screen 拆分：KeyboardHandler 对应物抽出、运动装配收敛 LocalPlayer 域
- [ ] 2.3 灵魂沙/蜂蜜等属性型减速（独立属性修饰符，非 friction）
