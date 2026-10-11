# Proposal

## Why

跑图过程中客户端世界"坑坑洼洼"：玩家周围的方块不及时出现、超出视距的方块滞留不卸载、区块加载参差不齐。2026-10-11 实测取证确认这不是网络或服务器问题，而是客户端从未实现原版的区块存储管理——原版靠**固定容量存储环 + 服务器窗口几何（center/radius）**自动完成"收新挤旧"，我们用的是无界 Map 只认服务器卸载包。

## What Changes

- 新建 `ClientChunkCache` 的 Dart 对应物（固定容量存储环，判据 `ClientChunkCache.java`）：写入越出窗口几何直接拒收（:100-103），环上被顶替的列立即卸载（:226-238），容量 = `(max(2,viewRadius)+3)×2+1)` ²（:151-153、:209-212）。
- 消化 `SetChunkCacheCenter`（id 94）/`SetChunkCacheRadius`（id 95）包：更新窗口几何（判据 `ClientPacketListener.java:2314-2330`）。当前二者在 `remote_session.dart:487` 被直接丢弃。
- 新建 `ChunkBatchSizeCalculator` 的 Dart 对应物（判据 `ChunkBatchSizeCalculator.java` 全文）：批次期望速率 = 客户端计时（7ms/tick 预算 ÷ 加权滑动平均 ns/chunk，钳制 [agg/3, agg×3]，权重上限 49）。当前 `remote_session.dart` 把服务器的 batchSize 直接当 desired 回传（语义与算法双错，判据 `ClientPacketListener.java:2356-2359`）。
- 卸载事件契约扩展：存储环顶替、越界拒收、ForgetLevelChunk 三条路径统一产生 ChunkUnloaded（对齐 `Storage.replace:226-238` 的 `level.unload`）。
- 渲染端消费卸载事件清理网格与脏队列（现仅 ForgetLevelChunk 一条路进来）。

## Capabilities

### New Capabilities
- `client-chunk-streaming`: 客户端区块流管理——固定容量存储环、窗口几何（center/radius）维护、批次速率计算与应答、卸载事件契约。

### Modified Capabilities
<!-- 无：remote-play 的端到端契约（装配点/渲染/预测/校正）不变 -->

## Impact

- `packages/mc_session/lib/src/`：新增 `client_chunk_cache.dart`、`chunk_batch_size_calculator.dart`（命名照原版类名）；`remote_session.dart` 消化 Center/Radius 包、接入存储环与批次计算器。
- `packages/mc_session/lib/src/session_isolate.dart`：事件契约（新增窗口更新事件，若跨 isolate 传递）。
- `lib/game/game_screen.dart`：消费窗口更新事件；`_columns` 的无界增长改为消费存储环的卸载事件。
- 测试：`mc_session` 包内新增存储环/批次计算器黄金值测试（判据常量：2,000,000 ns 初值、7,000,000 ns/tick 预算、权重 49、钳制系数 3、`calculateStorageRange = max(2, viewRange)+3`）。
