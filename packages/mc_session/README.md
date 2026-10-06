# mc_session

传输无关的联机会话编排与世界状态摄入：ping/status 探测、登录→配置→游玩阶段推进、区块与实体状态摄入、会话整体跑在 worker isolate。纯 Dart；依赖 mc_wire（传输核心）与 mc_protocol_v26_2（26.2 编解码）。

## 原版对应物

判据 `mc-sources/minecraft-26.2`：

- `net.minecraft.client.multiplayer.ClientPacketListener` —— 服务器包驱动的会话编排
- `net.minecraft.client.multiplayer.ClientChunkCache` / `ClientLevel` —— 区块与世界状态摄入
- `net.minecraft.client.multiplayer.MultiPlayerGameMode` —— 玩家操作上行

## 用法

```dart
final session = RemoteSession(host: '127.0.0.1', port: 25565, playerName: 'flutter_mc');
await session.connect();
session.events.listen((e) { ... });
```
