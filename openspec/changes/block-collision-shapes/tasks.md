# Tasks

## 1. 形状体系（mc_render）

- [x] 1.1 `voxel_shape.dart`：BlockBox / VoxelShape（盒并集、column/box 构造、rotateY90/invertY、or）；`collideAlongAxis`（Shapes.collide 等价：方向感知、EPSILON 1e-7、穿透锁死不回推）
- [x] 1.2 `block_collision_shapes.dart`：身份串 → 形状（空名单/整块兜底/半砖/楼梯 facing×half×shape/栅栏族 1.5/玻璃板族 1.0/墙近似（债）/栅栏门/雪片/地毯/耕地/土径/灵魂沙）；身份串解析缓存
- [x] 1.3 mc_render 黄金测试 9 项（栅栏 1.5/连接臂、玻璃板 1.0、半砖、楼梯 straight/inner/outer/top 镜像、雪片 0.125n、耕地/土径/灵魂沙/地毯、门开关）
- [x] 1.4 `SessionCollisionWorld.collisionShapeAt`（身份串查询，未加载/无碰撞 null）
- [x] 1.4b 门（`_door`，DoorBlock.java:55/:85-91：open → hinge 旋向缘 3/16 薄板）与活板门（`_trapdoor`，TrapDoorBlock.java:51/:77-79：closed half 底/顶水平板、open facing 竖板）——缺失时整块兜底 = 实机"门口卡死"根因
- [ ] 1.5 翻译债（progress.md）：未覆盖族兜底整块、wall tall/short 臂近似、gate in_wall 高度、楼梯旋转改用 Shapes.rotate 精确映射（现为语义直写+单测锁定）
