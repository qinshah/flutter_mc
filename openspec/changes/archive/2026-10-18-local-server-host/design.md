# Design

## Context

见 `proposal.md` 的 Why/What。这里只记录影响做法的现状与约束：

- 客户端数据面已完备：本地服务器对会话层而言只是 `127.0.0.1:<port>` 这个普通条目，走既有
  `remote-play` 通路，本 change 不碰会话与渲染代码。
- 本仓的"平台差异"惯例是集中在一处 app 壳层（参见 `lib/platform/` 现有文件与
  `android/app/src/main/kotlin/.../MainActivity.kt`），本 change 沿用这一形态。
- 实证参考（**不在 mc-sources 内，仅作经验证据**）：`/Users/qshh/Desktop/paperMC` 是一份
  正在运行的真实实例——`paper-26.2-129.jar`（64,522,678 B）、启动命令
  `java -Xms4G -Xmx4G -jar paper-26.2-129.jar --nogui`（见该目录 `command.md`）、
  日志首行即 `Running Java 25 (OpenJDK 64-Bit Server VM 25.0.2+10-69)`，就绪行为
  `Done (4.619s)! For help, type "help"`，其 `server.properties` 已是
  `online-mode=false`、`server-ip=`（空）、`server-port=25565`。
- 约束：产物（jar/JVM）不入库；版本特定代码只在 `mc_protocol_v<主>_<次>` 形态的包；新增模块
  须先指名原版对应物或标注自由设计类别（本 change 走第三类"运行时宿主"，见 specs）。

## Goals / Non-Goals

**Goals:**

- 把"托管一个原版系服务端"做成可独立启停、可观测、可配置的**一等公民功能**（桌面）。
- 控制面与配置口径**逐行对齐原版**，判据可指行号（见文末判据清单）。
- 纪律侧不留模糊：宿主机制与"被托管物"分别落位（第三类自由设计 / 翻译债）。

**Non-Goals:**

- Android 的嵌入式 JVM（`dlopen` 承载、独立进程 Service）——另开 change，先 spike。
- 插件/资源包/代理（Velocity 之类）管理、世界编辑器、备份体系。
- 在 Dart 侧翻译 `DedicatedServer` 或世界生成；不实现任何服务端玩法逻辑。
- 离线首次安装体验（paperclip 首启需联网拉 vanilla jar 与 libraries，本 change 不解决它）。

## Decisions

### D1 托管外部产物，不在 Dart 侧翻译服务端

理由：章程禁止 Dart 侧 world gen/存档写入；翻译服务端等于重写整个游戏服务端，与本 change 的
目标无关。备选（自研 Dart 服务端）已否决，但**被托管物**照旧登记为翻译债，不因"已托管"消失。

### D2 进程外托管，而非把 JVM 嵌进 Flutter 进程

桌面用 `Process.start(<java>, [...args, '-jar', <jar>, '--nogui'])`，stdout/stderr 入管道。

- 理由：崩溃隔离（JVM 段错误不带走 UI）、日志管道天然（就绪判定与面板直接消费 stdout）、
  堆参数可控（`-Xms/-Xmx` 由用户配置）、生命周期可 kill。
- 备选：JNI 嵌入式 JVM（同进程）——对服务器无收益，还会引入信号处理器抢占与 GC 卡顿；
  它在 Android 上才是必需品（无系统 JVM），留待下一个 change。

### D3 控制面 = 原版管理服务器（JSON-RPC/WebSocket）+ 原版 RCON

- **状态/玩家/白名单/封禁/难度/游戏规则** → 管理服务器：方法集与 schema 的原版判据在
  `server/jsonrpc/methods/**` 与 `internalapi/**`，接入握手/鉴权在
  `SecurityConfig`、`AuthenticationHandler`，可用 `discover` 方法自描述
  （`DiscoveryService.discover`，API 版本随 `SharedConstants` 的
  `RPC_MANAGEMENT_SERVER_API_VERSION`）。
- **任意指令** → RCON：报文类型与握手/指令帧判据在 `RconClient.java:17-21/:48-67`。
- 否决项：解析 stdout 文本推断状态（脆弱且被 spec 明令禁止）、自造本地 socket 桥（属自造协议，
  与原版控制通道并存只会成为第二个真相源）。
- 两个通道原版**默认都是关闭的**（`enable-rcon=false`、`management-server-enabled=false`），
  因此宿主在首启写配置时 SHALL 显式开启并生成密钥（照 `SecurityConfig` 的 40 字符字母数字口径）。

### D4 就绪判定取自原版就绪行

判据 `DedicatedServer.java:246`（`Done ({})! For help, type "help"`）。不用"进程存活"或端口
探测替代——那会在世界仍在加载时误报可连。

### D5 产物解析：二级 pin + 桌面复用系统 JVM

```
  本地服务器实例配置
    ├─ mcVersion  -> 协议锚点（SharedConstants.java:20 = 776）+ jar 产物
    └─ javaMajor  -> JVM 产物（Paper 26.2 实测需 Java 25）
```

- 桌面**不捆绑 JRE**：探测系统 JDK 主版本，满足即用；不满足则按"缺产物"报出并给指引。
- jar 现阶段由构建期资产携带（git 不追踪 + 文档说明），缺失时入口置灰并提示放置位置；
  后续改为"使用时下载"（FVM 式全局缓存 + 按实例 pin），目录与接口按同一抽象设计，
  切换时只换解析实现。
- 版本锚点硬绑 `mc-sources/minecraft-26.2` 与协议 776；`mc-sources/minecraft-common-26.3-sources`
  是并列的更高版本，MUST NOT 用作本锚点判据。

### D6 私有根目录沿用原版文件名

根 = `path_provider` 的应用私有目录（`getApplicationSupportDirectory()`）下的实例目录；根下
沿用原版命名，不自造：`world/`、`logs/`、`server.properties`、`eula.txt`、`libraries/`、
`versions/<mc>/`、`bukkit.yml`、`spigot.yml`、`config/`、`plugins/`、`cache/`、`.paper/`
（后几者为 Paper 系产物，原版 dedicated 也有同类配置文件，键名照样）。

### D7 配置口径照原版，仅覆盖三项默认值

键名、默认值、注释头、转义全部照 `DedicatedServerProperties.java`（判据见文末），未知键原样
保留。相对原版的**故意差异**只有三项，均须在代码注释写明理由：

| 键 | 原版默认 | 我们的默认 | 理由 |
|---|---|---|---|
| `online-mode` | `true`（`:56`） | `false` | 本仓客户端为离线登录口径，否则本机连不上自己 |
| `server-ip` | `""`（`:58`） | `""` | 保持一致：空即绑全部接口，顺带满足局域网 |
| `server-port` | `25565`（`:72`） | `25565`（冲突时可改） | 与客户端默认条目地址一致 |

另需在首启写入开启项：`enable-rcon`/`rcon.port`/`rcon.password`、`management-server-enabled`
/`-host`/`-port`/`-secret`（`-tls-enabled` 的取值见 Open Questions）。

### D8 包划分：能翻译的落包，承载方式落 app 壳

- **纯 Dart 包**：RCON 客户端（协议与 MC 版本无关，原版判据 `server/rcon/**`）、
  `server.properties` 读写（原版判据 `DedicatedServerProperties.java`）。
- **版本特定部分**归 `mc_protocol_v26_2`：管理服务器的 JSON-RPC 方法集与 schema 是 26.2 特定，
  按"版本特定代码只在 `mc_protocol_v<主>_<次>` 形态的包"这一硬约束放置（不新造版本包名）。
- **app 壳**：进程承载、stdout 管道、就绪判定、生命周期与孤儿回收、EULA 对话框、产物解析的
  平台分支——即第三类"运行时宿主"的全部内容。
- 备选（把宿主也放进包）已否决：包纯度红线禁止包内出现平台/`dart:io` 进程承载语义之外的
  Flutter 依赖，且宿主天然是平台差异。

### D9 EULA 门槛照原版语义、换承载形式

原版在控制台要求同意后才能运行（`Main.java:113-121` + `Eula.java:35/:44`）。我们只把"控制台
提问"换成"UI 对话框"，判定与写盘语义照旧：未同意不写 `eula=true`、不启动。

### D10 停止与孤儿回收

优雅停止 = 经 RCON 下发 `stop` → 等待进程退出（超时上限由配置给定）→ 超时仍未退出才强杀。
应用退出/宿主重载时，已启动实例 SHALL 被回收（避免孤儿进程占端口）。

### D11 端口冲突处理

默认 25565；被占用时按配置允许改到用户指定端口，启动后回显**实际**监听端口，并以
`127.0.0.1:<实际端口>` 生成可连接条目。

## Risks / Trade-offs

- **[桌面无 Java 25 ⇒ 无法启动]** → 产物解析显式报缺失 + 安装指引；后续切"下载 JRE"口径。
- **[jar 靠 assets 携带且不入库 ⇒ 他人 clone 后功能不可用]** → 入口置灰 + 文档说明 + 缺失时
  不影响其余功能；尽早切下载口径。
- **[内置 jar 随包分发 ⇒ 触发 Paper GPLv3 与 Mojang EULA 义务]** → 产物不入库、不分发；
  下载路径在 UI 上呈现许可提示；EULA 同意作为硬门槛（D9）。
- **[paperclip 首启需联网拉 vanilla jar 与 libraries]** → 启动进度与日志面板如实展示，首次启动
  较慢属预期；不承诺离线首装。
- **[Paper native transport（libdeflate/cipher）在部分平台无原生库]** → 原版会回退到纯 Java
  实现；macOS ARM64 实测走原生，其他平台待实测。
- **[版本漂移（26.2 vs 26.3 源码并列）]** → 锚点硬绑协议 776 与 26.2 源码树；产物解析按
  协议号校验，不匹配拒绝启动。
- **[两套控制通道各自默认关闭]** → 首启写入开启项并生成密钥；通道不可用时显式提示（spec 要求），
  不静默降级。

## 判据清单（门禁：实现与测试的取值一律指向下列位置，路径均相对 `mc-sources/minecraft-26.2/net/minecraft/`）

| 用途 | 判据 `文件:行号` |
|---|---|
| 版本/协议锚点（world 4903、协议 776、快照协议 322） | `SharedConstants.java:16`、`:20`、`:22` |
| 就绪行（可连接判定的唯一依据） | `server/dedicated/DedicatedServer.java:246` |
| RCON 启停条件 | `server/dedicated/DedicatedServer.java:256-258`、`:403-404` |
| 配置键与默认值 | `server/dedicated/DedicatedServerProperties.java:56`、`:58`、`:72-80`、`:84-86`、`:104` |
| 启动选项与 EULA 门槛 | `server/Main.java:72`、`:73`、`:113-121`、`:211` |
| EULA 判定与文件头文本 | `server/Eula.java:35`、`:44` |
| RCON 报文类型/握手与指令帧 | `server/rcon/thread/RconClient.java:17-21`、`:48-67` |
| RCON 端口与口令来源 | `server/rcon/thread/RconThread.java:41`、`:64-66` |
| RCON 字节编解码（长度上限、int/string 互转） | `server/rcon/PktUtils.java:6`、`:9`、`:20`、`:24`、`:28` |
| 管理服务器起停与 WebSocket 管线 | `server/jsonrpc/ManagementServer.java:86-91`、`:116-119`、`:132` |
| 管理服务器的 TLS/非 TLS 创建分支 | `server/jsonrpc/JsonRpc.java:19` |
| 管理服务器密钥格式与生成 | `server/jsonrpc/security/SecurityConfig.java:6-20` |
| 管理服务器鉴权（Bearer / `minecraft-v1` 子协议） | `server/jsonrpc/security/AuthenticationHandler.java:29-31`、`:108-113` |
| 管理服务器方法集与自描述 | `server/jsonrpc/methods/DiscoveryService.java:16`、`:34-35`，方法实现见 `server/jsonrpc/internalapi/*ServiceImpl.java` |

**非源码的经验证据**（仅用于确认启动参数、配置默认值与产物版本，不作为翻译判据）：
`/Users/qshh/Desktop/paperMC/command.md`（启动命令）、`.../server.properties`（真实默认值）、
`.../logs/latest.log:1`（Java 25）、`:49`（就绪行）。

## Migration Plan

无破坏性变更、无数据迁移：`servers.dat` 结构不变（本地服务器可变量存于私有目录）；新功能可
独立启停。回滚 = 关闭/删除本地服务器条目并清理私有目录中的实例目录。

## Open Questions

- `management-server-tls-enabled` 在本机自托管场景取何值最合适（原版默认 `true`，但 keystore
  为空；需要确认在本机回环 + 自签场景下的实际行为）。不影响 specs 与任务拆分，实现时以
  `JsonRpc.java:19` 的创建分支为准并实测。
- 局域网分享的对外呈现（二维码/地址复制）形式——UI 细节，留实现期定。
