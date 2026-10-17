# mc_server

原版系服务端的**控制面翻译件**（纯 Dart）。本包不实现任何服务端玩法逻辑——服务端本体由
外部托管的 Java 产物提供（见 `openspec/changes/local-server-host/`，被托管物登记在
`openspec/progress.md` 第 14 项）。

## 原版对应物（判据 `mc-sources/minecraft-26.2`）

| 本包文件 | 原版判据 |
| --- | --- |
| `lib/server/rcon/pkt_utils.dart` | `net/minecraft/server/rcon/PktUtils.java:6/:9/:20/:24/:28` |
| `lib/server/rcon/rcon_client.dart` | `net/minecraft/server/rcon/thread/RconClient.java:17-21/:48-67/:108-134` |
| `lib/server/dedicated/settings.dart` | `net/minecraft/server/dedicated/Settings.java:34-65/:103-108/:119-130` |
| `lib/server/dedicated/dedicated_server_properties.dart` | `net/minecraft/server/dedicated/DedicatedServerProperties.java:56`、`:58`、`:72-80`、`:84-86`、`:104` |
| `lib/server/eula.dart` | `net/minecraft/server/Eula.java:20/:27/:35-48`、`net/minecraft/util/CommonLinks.java:10` |

RCON 的原版只有**服务端**（`RconClient` 处理入站连接）；本包的同名客户端是同一线格式的
**对偶实现**（请求编码/响应解码沿用原版声明常量 `RconClient.java:17-21` 与 `PktUtils` 的字节序）。

## 首个预期 change

`local-server-host`（桌面托管本机服务端）。
