# Tasks

## 1. 求解器对齐（collision.dart）

- [x] 1.1 `move` 重写为 `Entity.collide` 对应物：expandTowards 收集 → collideWithShapes（axisStepOrder 判据 Direction.java:379-381）→ step-up（候选高度 Entity.java:1183-1197）→ onGround = yCollision && dy<0（:1146）
- [x] 1.2 删除 `hasBlockBelow` 探针 / `_layerBlocked*` / `substeps`（vanilla 无子步）；世界底/顶虚空语义（无隐形地板）

## 2. 调用方适配

- [x] 2.1 `local_player.dart`：行走/飞行分支着地判定改 collide 口径（只在本子步有竖直位移时更新）；落地不清零 vy（原版负收敛）；撞顶清零保留；删撞墙清速度
- [x] 2.2 测试重写：game_physics 23 项（axisStepOrder 双向、贴地稳定 100 刻、平台边缘 vanilla 语义、dy=0 契约）；jump_height 3 项旧语义断言改原版口径（vy 负收敛、再跳越 1 格）

## 2.5 实机反馈修复（2026-10-11 第二轮）

- [x] 2.5.1 `collideAlongAxis` 对齐 `VoxelShape.collideX`（VoxelShape.java:251-300）：**穿透形状完全不参与本轴阻挡**（旧"锁死 0"把贴墙滑行轴一并锁死 = 实机"贴墙动不了"）；截停值 = 精确贴面（删自造 eps 回退；原版 `distance=min(distance,newDistance)` 无回退）
- [x] 2.5.2 `Player.position` 换 `Vec3`（新建 lib/world/phys/vec3.dart，判据 Vec3.java:41-43 double 不可变 + Entity.setPos）——旧 vector_math Vector3 是 **float32**，|x|>64 后 ulp 4e-6 ≫ eps 1e-7，贴面静止被舍入进墙内触发穿透分支（实机卡墙的土壤）；渲染边界才转 float32（interpolatedPosition）
- [x] 2.5.3 回归测试 collision_repro_test 4 项：贴墙平移 50 步、门洞通行、关门对照、微穿透状态滑行+逃离+不穿出

## 3. 验收

- [x] 3.1 analyze 全仓 0 issue；root 102 + mc_render 19 + mc_session 36 全绿
- [ ] 3.2 实机手感验收（用户）：栅栏跳不上、台阶/楼梯自动上步、贴墙推挤不抽搐、上下楼梯顺滑
