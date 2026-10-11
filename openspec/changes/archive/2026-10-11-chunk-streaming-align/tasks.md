# Tasks

## 1. mc_session：存储环与批次计算器（纯 Dart，逐行翻译）

- [x] 1.1 新建 `packages/mc_session/lib/src/client_chunk_cache.dart`：`ClientChunkCache`（含 Storage），判据 J1-J9——`calculateStorageRange`、模索引、`inRange`、`replace`（顶替→卸载回调）、`drop`、`updateViewCenter/updateViewRadius`（缩窗重建+迁移存活列）；元素 `RemoteChunkColumn`，卸载经回调上抛
- [x] 1.2 新建 `packages/mc_session/lib/src/chunk_batch_size_calculator.dart`：判据 J10-J12——常量 2,000,000/7,000,000/49/3 逐项照抄，`onBatchStart/onBatchFinished/getDesiredChunksPerTick`
- [x] 1.3 单测：容量换算黄金值（viewRadius=10 → chunkRadius=13 → 729）；inRange 切比雪夫边界（等号在内、超 1 在外）；顶替产生卸载回调；缩窗迁移存活列
- [x] 1.4 单测：批次计算器离线递推黄金值（初批应答 ≈ 3.5 列/刻、钳制路径、权重封顶 49 后均值收敛），对照 Java 语义手算

## 2. mc_session：会话分流改造

- [x] 2.1 `remote_session.dart`：`SetChunkCacheCenter`/`SetChunkCacheRadius` 分流（现 `:487` 丢弃）→ 存储环 `updateViewCenter/updateViewRadius`；越界拒收打 warn（J4）；半径变化产生批量卸载事件
- [x] 2.2 `remote_session.dart`：`_handleChunk` 走存储环 `replaceWithPacketData`；被顶替列发 `ChunkUnloaded`（J5）；`ForgetLevelChunk` 走 `drop`（J6）；`_chunks` 无界 Map 删除
- [x] 2.3 `remote_session.dart`：`ChunkBatchStart/Finished` 接 `ChunkBatchSizeCalculator`，应答改发 `getDesiredChunksPerTick()`（J13、J15；现 `min(batchSize,500)` 删除）
- [x] 2.4 事件契约：窗口更新透传主 isolate（`ViewGeometryChanged`，字段 center x/z + radius）；`session_isolate.dart` 分发接线
- [x] 2.5 mc_session 全量测试绿；`flutter analyze` 0 issue

## 3. app 壳：消费新事件

- [x] 3.1 `game_screen.dart`：`_columns` 增删完全跟随 ChunkLoaded/ChunkUnloaded（含顶替/缩窗来源）；消费 `ViewGeometryChanged`（暂存字段，供网格化优先级未来按 center 排序）
- [x] 3.2 删除一切本地推断卸载/门禁残留；诊断日志对齐（[VIEW] 窗口几何 + [CHUNK] load/unload；来源标注按原版不做——vanilla 在此层不区分卸载来源，事件统一）

## 4. 端到端验收

- [x] 4.1 macOS 实测（AUTOJOIN + AUTOWALK 飞行疾跑跑图 ≥10 分钟）：cols 峰值 587 ≤ 729 ✓、unload 1903 次 ✓、零异常 ✓、零越界拒收 ✓、窗口几何持续跟随（view center == 玩家列）
- [x] 4.2 验证"及时卸载"：跑图往返同一区域，第二次经过时列仍在（未误卸）且超视距列已卸
- [x] 4.3 验证"参差不齐"改善：dirty 峰值 5700（基线 ~10k，约 -45%）
- [x] 4.5 遗留（超出本 change，另立修复）：服务器 teleport 拒绝循环（collision-reject 静默回拉，10 分钟 51 次）致"相信位置"与真实位置背离 ⇒ 窗口跟不上 ⇒ 脚下列缺失（截图 2026-10-11 14:03 大洞）。修复（2026-10-11 第二轮实施）：根因 = 登录即发 PlayerLoaded（服务端立刻接受移动）+ 出生列未到客户端已起飞 ⇒ 嵌入服务器侧实地 ⇒ collision-reject 弹跳（开局 4 秒 51 次）。修复 = 逐行翻译 LevelLoadTracker 就绪状态机（新建 lib/client/multiplayer/level_load_tracker.dart，判据 ClientPacketListener.java:2656-2669 + LevelLoadTracker.java 全文）：就绪（玩家列段已网格化 / 30s 超时 / y 超界豁免）才发 PlayerLoaded 并开始物理；GameEvent(13) 透传驱动阶段迁移。实测：teleport 51 → 2 次（残留 2 次开局瞬弹、无循环），就绪时 cols=401
- [x] 4.4 全仓测试 + analyze 零 issue；翻译债登记：光照引擎/`onChunkLoaded` tint 面未建模（design 非目标）
