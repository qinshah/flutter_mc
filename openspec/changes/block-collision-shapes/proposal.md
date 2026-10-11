# Proposal

## Why

客户端碰撞是布尔整块网格（`isCollidable`），与原版 VoxelShape 体系完全脱节：栅栏能跳上去（原版 1.5 高跳不上）、台阶/半砖是整块、无自动上步。用户实测：与方块碰撞抽搐、不规则方块碰撞表现与原版不符。

## What Changes

- 新建 VoxelShape 对应物（`net/minecraft/world/phys/shapes/` → mc_render 纯 Dart）：盒列表并集 + `Shapes.collide` 逐轴截停语义（EPSILON 1.0E-7）。
- 新建方块碰撞形状库：26.2 状态身份串（`kBlockStateIdentity262`，32366 状态含全部属性）→ 碰撞形状。首切片覆盖族：整块、空（常见无碰撞名单）、半砖、楼梯（facing/half/shape 全组合）、栅栏/栅栏门/玻璃板/铁栏杆（连接属性驱动，collisionHeight 1.5/1.0）、墙（简化，债）、雪片（1~8 层）、地毯、耕地/土径（0.9375）、灵魂沙（0.875）；未覆盖族兜底整块（翻译债登记）。
- `SessionCollisionWorld` 提供 `collisionShapeAt(bx, by, bz)`。

## Capabilities

### New Capabilities
- `block-collision-shapes`: 方块碰撞形状体系——按方块状态的体素形状与逐轴截停查询。

### Modified Capabilities

## Impact

- `packages/mc_render/lib/src/`：新增 `voxel_shape.dart`、`block_collision_shapes.dart`（形状库判据全部来自 Block 类源码常量）。
- `lib/game/session_collision_world.dart`：新增形状查询（`isCollidable` 保留兼容，entity-collide-step-up change 切换消费）。
- 栅栏跳不上、台阶半高、楼梯几何的黄金测试。
