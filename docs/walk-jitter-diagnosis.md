# 怼墙行走"原地抽搐"问题总结（2026-10-11 诊断，2026-10-12 根因修复）

## 症状

- 玩家沿障碍物行走时，位置原地抽搐、无法顺滑滑动；
- **栅栏（fence）不抽搐**，其余障碍物（高出地面一格的草方块台阶、dirt_path 等）均抽搐；
- 场景：浅水区、贴着高出脚下一格的草方块直走、无跳、无疾跑。

## 根因（2026-10-12 实锤）

**客户端建盒半宽用了 double `0.3`，原版是 float 语义 `float32(0.6)/2 = 0.30000001192092896`。**

判据：`EntityDimensions.makeBoundingBox`（EntityDimensions.java:19-22）——

```java
float w = this.width / 2.0F;   // 0.6F → 0.30000001192092896（float 除法）
return new AABB(x - w, y, z - w, x + w, y + h, z + w);
```

证据链（Paper 服务器 + FailProbe 探针实测）：

1. 服务器拒绝路径 = `hasNewCollision` → `CLIPPED_INTO_BLOCK`（log=false 静默）→
   `internalTeleport(startX/Y/Z)` 回拉（ServerGamePacketListenerImpl.java:1678-1685, 1760-1761）
   ——这就是抽搐循环：客户端贴面 → 被拒 → 弹回 → 再走 → 再被拒。
2. 服务器按 float 语义重建玩家盒：上报 z=241.3 时盒 `minZ = 240.99999998807908`，
   对整块墙面（`AABB.intersects` 严格不等式，CollisionUtil.java:1449）**穿透 1.19e-8 可见** → 拒绝；
   实测接受阈值 = `241.30000001192093`（= 墙面 + float 半宽）。
3. vanilla 客户端用同一 float 半宽建盒 → 贴面时上报的中心 = 墙面 + 0.30000001192092896，
   恰好落在阈值上 → 被接受，无循环。我们用 double 0.3 → 贴面中心恰为墙面 + 0.3，
   差 1.19e-8 → 每次贴面必被拒。**vanilla 不抽搐、我们抽搐的全部差异就在这 1.19e-8。**

修复：`Aabb` 构造按 `EntityDimensions.makeBoundingBox` 的 float 语义
（`lib/game/collision.dart`，半宽 = float32(0.6)/2，头顶 = y + float32(1.8) = 1.7999999523162842）。
回归：5 个碰撞测试 + 全量 105 测试全绿；实机 AUTOWALK=walk 怼墙直走不再抽搐（2026-10-12）。

教训：**Java float 字段参与 double 运算时的舍入差不是数值噪声，是判据的一部分。**
建盒、尺寸、眼高等原版以 float 存储的量，翻译时必须保持 float32 舍入语义。

## 诊断过程关键节点

- 客户端对 `PositionCorrection` 的回拉应用注释掉后抽搐消失 → 证明抽搐由服务器下发的传送造成；
- 穿透探针（客户端本地 `deflate 1e-5` 口径）零命中 → 本地碰撞无穿透，问题在**上报值的边界语义**；
- Paper 反编译 + moonrise float32 尺寸 + FailProbe 插件（PlayerFailMoveEvent/PlayerMoveEvent/
  PlayerTeleportEvent 全精度）从服务器侧实锤拒绝原因与阈值；
- `VoxelShape.collideX` 负方向分支（VoxelShape.java:288-303）确认 vanilla 客户端同样精确贴面
  ——排除"vanilla 不到贴面态"假说后，唯一差异收敛到建盒半宽。

## 关键观察

| 障碍物 | 是否抽搐 |
|---|---|
| 栅栏 | 否 |
| 高出地面一格的草方块台阶 | 是 |
| dirt_path 等同类台阶 | 是 |

栅栏不抽搐的原因（修复后推断）：栅栏碰撞形状 1.5 格高，玩家盒与栅栏侧面接触时
1e-7 量级的差异不改变判定结果；整块方块的整格判定对 1.19e-8 敏感。

## 过程中的附带修复（已保留，与本症状独立）

1. `SectionBlocksUpdate` 段内坐标解码 Y/Z 位序修正（判据 `SectionPos.java:100-110`：X=bit8-11、Z=bit4-7、Y=bit0-3），并补黄金回归测试；
2. `ClientTickEnd` 每刻漏发补上（判据 `Minecraft.java:1930`，原版客户端每 tick 无条件发送）。

## 当前状态

- **已修复**：`Aabb` float 建盒语义（`lib/game/collision.dart`），实机验证通过；
- 诊断设施保留（TRACE 门控）：`[PENETRATE]` 穿透探针、`[GRID]` 拒绝时刻本地 3×3×3 身份串转储、
  `[SEND]` 上行报文记录、`AUTOWALK=walk` 纯行走探针变体；
- 服务器侧 FailProbe 插件（`PlayerFailMoveEvent` 全精度取证）保留在 Paper plugins（诊断用，可随时移除）。

## 遗留翻译债（与本 bug 独立，已登记 openspec/progress.md）

- 水物理分支缺失：vanilla `LivingEntity.travel` 三分支（air/water/lava），我们只有 air
  （`travelInWater` 未翻译）。当前场景（浅水直走）行为与 vanilla 有偏差，但不是抽搐根因。
