# Design

## 判据清单（mc-sources/minecraft-26.2）

| # | 判据 | 位置 |
|---|---|---|
| J1 | `collideWithShapes`：空 shapes 原样返回；`Direction.axisStepOrder(movement)` 分量排序逐轴，`Shapes.collide(axis, box.move(resolved), shapes, m)` | Entity.java:1249-1263 |
| J2 | step-up：`(onGroundAfterCollision || onGround()) && (xCollision || zCollision)` 时按候选高度重解算，`horizontalDistanceSqr` 更大者胜 | Entity.java:1144-1177 |
| J3 | `collectCandidateStepUpHeights`：collider 的 Y 坐标相对盒底 ∈ [0, maxUpStep] 且 != 本次 y 位移 | Entity.java:1183-1197 |
| J4 | `maxUpStep` = Attributes.STEP_HEIGHT 0.6 | Attributes.java:98-99 |
| J5 | onGround = `yCollision && movement.y < 0` | Entity.java:1146 |
| J6 | EPSILON 1.0E-7 | AABB.java:14 |

## 方案要点

- `MoveResult` 改为携带 `xCollision/yCollision/zCollision` 与新位置；`onGround` 派生字段替换 `hasBlockBelow`。
- 求解输入 = `SessionCollisionWorld.collisionShapeAt`（block-collision-shapes change 产物）；收集范围 = `AABB.expandTowards(movement)` 覆盖格。
- `LocalPlayer._step`：`grounded = result.yCollision && dy < 0`（行走）与飞行分支同口径；删除 `_groundProbe`。
- game_screen 拆分落点：求解器零 Flutter 依赖保持纯 Dart；`Aabb` 的轴访问助手进 collision.dart。
