# Design

## 判据清单（mc-sources/minecraft-26.2）

| # | 判据 | 位置 |
|---|---|---|
| J1 | `CrossCollisionBlock(postWidth, postHeight, wallWidth, wallHeight, collisionHeight, props)`；collision = `makeShapes(postWidth, collisionHeight, wallWidth, 0, collisionHeight)` | CrossCollisionBlock.java:30-46 |
| J2 | post = `Block.column(sizeXZ, minY, maxY)` = 居中柱（Block.java:177-185） | Block.java:177-185 |
| J3 | arm = `Block.boxZ(sizeX, minY, maxY, minZ, maxZ)` = x 居中条（Block.java:200-203），四向 `Shapes.rotateHorizontal` | Block.java:200-203；CrossCollisionBlock.java:49 |
| J4 | FenceBlock：`super(4.0F, 16.0F, 4.0F, 16.0F, 24.0F)` ⇒ collision：post (0.375,0,0.375)~(0.625,1.5,0.625)，臂厚 0.25、y 0..1.5 | FenceBlock.java:37 |
| J5 | Slab：`SHAPE_BOTTOM = column(16,0,8)`、`SHAPE_TOP = column(16,8,16)` | SlabBlock.java:35-36 |
| J6 | Stair（StairBlock.java:40-48）：OUTER = or(column(16,0,8), box(0,8,0,8,16,8))；STRAIGHT = or(OUTER, rotateY90(OUTER))；INNER = or(STRAIGHT, rotateY90(STRAIGHT))；TOP = INVERT_Y（整体 y 镜像）；`getVisualShape` 按 facing/half/shape 取 | StairBlock.java:40-48, :76-82 |
| J7 | Snow：`SHAPES = boxes(8, h -> column(16,0,h*2))` ⇒ 高 0.125×layers；`HEIGHT_IMPASSABLE=5` | SnowLayerBlock.java:29-32 |
| J8 | SoulSand = column(16,0,14)=0.875；FarmLand/DirtPath = column(16,0,15)=0.9375；Carpet = column(16,0,1)=0.0625 | SoulSandBlock.java:15、FarmLandBlock.java:36、DirtPathBlock.java:23、CarpetBlock.java:17 |
| J9 | 身份串全表：`kBlockStateIdentity262`（32366 状态含全部属性键值） | packages/mc_render/lib/src/state_identity_26_2.dart |

## 方案要点

- **形状表示**：`VoxelShape` = 世界格内（0..1）盒列表并集。vanilla 的离散区间优化（ArrayVoxelShape）简化为盒列表——语义一致（并集、逐轴 clip），标注债。
- **族解析**：身份串 → `(name, props)` → 形状函数。楼梯几何直写（facing 半边梯级 + outer/inner 角块），旋转映射用单测锁定 vanilla 行为（facing=上升方向，梯级在 facing 半边）。
- **无碰撞名单**（反白名单，未列默认整块）：air、水/岩浆/气泡柱、花/苗/草丛/蕨/枯灌木/作物（小麦/胡萝卜/土豆/甜菜/西瓜/南瓜梗）、火把/灯笼?（灯笼有碰撞! 只列确定项）、导线/中继器?（中继器有碰撞 0.0625——先不列）、铁轨三类、甘蔗、藤蔓、结构空位。名单保守，漏的植物暂时实心（债）。
- **wall 简化（债）**：WallBlock 自有 tall/short 臂形状（:55 起）——首切片用 fence 参数近似（post 0.25 / 高 1.5 / 臂 0.25×1.5），本质语义（1.5 高不可跳）保持。
- **落点**：mc_render（方块域纯 Dart）；`SessionCollisionWorld.collisionShapeAt` 供实体碰撞消费（entity-collide-step-up change 切换）。
