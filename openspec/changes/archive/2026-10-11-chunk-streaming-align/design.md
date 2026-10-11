# Design

## 判据清单（实现前对照，全部来自 mc-sources/minecraft-26.2）

| # | 判据 | 位置 | 用途 |
|---|---|---|---|
| J1 | `calculateStorageRange = max(2, viewRange) + 3` | `ClientChunkCache.java:151-153` | 存储半径换算 |
| J2 | `viewRange = chunkRadius*2+1`；容量 = `viewRange²` | `ClientChunkCache.java:209-212` | 存储环容量 |
| J3 | 索引 = `floorMod(z, viewRange)*viewRange + floorMod(x, viewRange)` | `ClientChunkCache.java:222-224` | 环索引（模运算=自动顶替） |
| J4 | 写入越界（切比雪夫距离 > chunkRadius）拒绝 + warn | `ClientChunkCache.java:100-103` | 越界拒收 |
| J5 | `replace` 顶替旧列 → `level.unload(oldChunk)` | `ClientChunkCache.java:226-238` | 顶替即卸载 |
| J6 | `drop`：ForgetLevelChunk → 卸载 | `ClientChunkCache.java:58-66`、`ClientPacketListener.java:898-901` | 忘记列 |
| J7 | `updateViewCenter(x,z)` / `updateViewRadius(r)` | `ClientChunkCache.java:124-149`；`ClientPacketListener.java:2314-2330` | 窗口几何更新；半径变化重建环并迁移存活列 |
| J8 | `inRange = |x-center| <= radius && |z-center| <= radius` | `ClientChunkCache.java:298-300` | 窗口判定（切比雪夫） |
| J9 | 未加载列 = `EmptyLevelChunk`（空气） | `ClientChunkCache.java:40,68-77` | 查询语义 |
| J10 | 批次计时器常量：初值 2,000,000 ns/列、预算 7,000,000 ns/tick、权重上限 49、钳制系数 3 | `ChunkBatchSizeCalculator.java:7-11,13-27` | 期望速率计算 |
| J11 | `onBatchFinished(batchSize)`：nanosPerChunk=耗时/size，钳制 [agg/3, agg×3] 后并入加权平均，权重 min(49, +1) | `ChunkBatchSizeCalculator.java:16-25` | 采样并入 |
| J12 | `getDesiredChunksPerTick() = 7_000_000 / aggregatedNanosPerChunk` | `ChunkBatchSizeCalculator.java:29-31` | 应答值 |
| J13 | `handleChunkBatchFinished` → 应答 `ServerboundChunkBatchReceived(getDesiredChunksPerTick())` | `ClientPacketListener.java:2356-2359` | 应答语义（现实现把 batchSize 当 desired，双错） |
| J14 | 窗口几何包：Center（id 94）→ updateViewCenter；Radius（id 95）→ updateViewRadius | `GameProtocols.java`（注册序）、`ClientPacketListener.java:2314-2330` | 现 `remote_session.dart:487` 丢弃此二包 |
| J15 | `handleChunkBatchStart` → 计时起点 | `ClientPacketListener.java:2352-2354` | 计时锚点 |

## 差异表（原版 vs 现状）

| 行为 | 原版 | 现状 | 后果 |
|---|---|---|---|
| 区块存储 | 固定容量存储环（J1-J3），顶旧即卸（J5） | 无界 `Map`，只增不减 | 超视距列滞留，内存与渲染面数无界 |
| 越界写入 | 拒收 + warn（J4） | 照单全收 | 窗口外列挤占资源 |
| 窗口几何 | Center/Radius 包驱动（J7、J14） | 包被丢弃（`remote_session.dart:487`） | 客户端无窗口概念，全靠服务器 Forget 包 |
| 忘记列 | `drop` → unload（J6） | 已实现（唯一卸载路径） | 服务器包延迟/缺失时列滞留 |
| 未加载查询 | EmptyLevelChunk 空气（J9） | `isCollidable` 返回 false（一致） | ✓ 已对齐（2026-10-11 门禁拆除） |
| 批次应答 | 客户端计时（J10-J13） | `min(batchSize, 500)` 原样回传 | 语义与算法双错 |
| 卸载事件 | 顶替/忘记/缩窗统一卸载 | 仅 ForgetLevelChunk 一条路 | 渲染端清理不完整 |

## 落点与映射（Java → Dart，一类一文件）

| 原版类 | Dart 落点 | 说明 |
|---|---|---|
| `client/multiplayer/ClientChunkCache.java` | `packages/mc_session/lib/src/client_chunk_cache.dart` | 存储环（含 Storage 内部类同文件，Java 内部类不必拆文件）；元素类型 `RemoteChunkColumn`（纯数据，可跨 isolate） |
| `client/multiplayer/ChunkBatchSizeCalculator.java` | `packages/mc_session/lib/src/chunk_batch_size_calculator.dart` | 常量逐项照抄（J10-J12）；`Util.getNanos()` → `Stopwatch`（微秒×1000，注释标注换算） |
| `ClientPacketListener` 的 chunk 处理面 | `packages/mc_session/lib/src/remote_session.dart`（既有） | Center/Radius/批次/忘记列分流改造 |

## 方案要点

1. **存储环跑在会话 isolate**（区块摄入已在那里；环的几何更新也随包在那里处理）。事件契约扩展：`ChunkUnloaded` 增加"顶替/缩窗"来源（现有字段够用：x、z）；新增 `ViewGeometryChanged` 事件（center/radius）供 app 壳可选消费（渲染端目前不需要 center，但网格化优先级未来可按 center 排序）。
2. **`RemoteSession._chunks` 改由存储环承载**：`_handleChunk` 先 `replaceWithPacketData`（越界拒收走 J4），接受才发 `ChunkLoaded`；被顶替列发 `ChunkUnloaded`（J5）。
3. **app 壳 `game_screen.dart`**：`_columns` 的增删完全跟随事件（加载/卸载），删除一切本地推断卸载；`_unmountColumn` 已有脏队列清理逻辑，复用。
4. **批次应答**：`ChunkBatchFinished` 分流改走 `ChunkBatchSizeCalculator`（J13）；`ChunkBatchStart` 记时（J15）。Paper 实测不发批次包（2026-10-11 取证：9 分钟 0 条）——计算器仍按原版实现，等批次包到来即正确工作，不引入自造分支。
5. **非目标（本轮不做）**：光照引擎（原版 `queueLightUpdate` 面我们不建模）、`onChunkLoaded` 的 tint/entity 侧（无对应物）、网格化 budget 调优（渲染后端自由设计区，性能阶段另行处理）。
6. **单测黄金值**：J1-J3 的容量换算（viewRadius=10 → chunkRadius=13 → 容量 27²=729）；J10-J12 递推（初值 2,000,000、单批采样后均值与期望速率的离线算例）；J8 inRange 边界（切比雪夫等号成立时在窗口内）。
