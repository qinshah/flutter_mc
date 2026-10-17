# Proposal

## Why

目前本应用**只能连别人的服务器**：想自己玩，必须先有一台机器把服务端起起来。而本仓章程
明确"Dart 侧不做 world gen / 存档写入"，所以"用 Dart 自研服务端"这条路与章程直接冲突。

把**原版系服务端以 Java 进程形式托管在本机**，恰好把世界生成整体留在 Java 侧：Dart 侧
一行世界逻辑都不用写，客户端数据面也一行不用改（本地服务器只是 `127.0.0.1:<port>` 这个
普通条目）。版本对齐也已经具备条件——本机实测运行的 Paper 26.2 与客户端协议锚点同版
（协议 776 / `mc-sources/minecraft-26.2`）。

## What Changes

- **新增能力** `local-server-host`：在 app 私有目录托管一个 Paper 服务端，作为**一等公民**
  的"本地服务器"（独立启停、配置项、日志面板、端口、存档目录）；"单人世界"是它的
  快捷入口（创建 → 起服 → 自动连 `127.0.0.1`）。**首版仅桌面**。
- **控制面逐行翻译原版**，不自造协议：状态/玩家/白名单/难度等走 **26.2 原版管理服务器**
  （JSON-RPC over WebSocket，判据 `server/jsonrpc/**`）；发任意指令走 **原版 RCON**
  （判据 `server/rcon/**`）。
- **产物口径**：jar 类产物暂放 `assets/`（git 不追踪 + 文档说明），后续改为"使用时下载"；
  桌面**不捆绑 JRE**，检测并复用系统 JDK（Paper 26.2 需 **Java 25**）。
- **纪律新增第三类自由设计**「运行时宿主（JVM 托管）」，并把**服务端本体**（`DedicatedServer`
  / `Main` / 世界生成等）登记为翻译债——即"宿主机制"可豁免，"被托管物"不可豁免。
- **不做**：Android 的嵌入式 JVM（另开 change，含 spike）；不碰 `servers.dat` 结构；不做
  资源包/插件市场；不改客户端会话与渲染代码。

## Capabilities

### New Capabilities

- `local-server-host`: 本机托管原版系 Java 服务端的端到端契约——产物解析与 JRE 校验、进程
  生命周期（起/停/崩溃回收）、EULA 同意门槛、私有目录布局（`world/`、`logs/`、
  `server.properties`）、控制面（原版管理服务器 + RCON）、就绪判定与日志、以及它在 UI 中
  作为"本地服务器条目 + 单人快捷入口"的形态。

### Modified Capabilities

- `project-structure`: 「Java→Dart 逐行翻译为默认行为」的自由设计类别由**两类**扩为**三类**
  （新增"运行时宿主（JVM 托管）"）；「写代码前必须先指名原版对应物」的场景同步扩为三类。
- `translation-debt`: 新增"宿主机制与被托管物可分离"的登记口径——宿主机制可标注为运行时
  宿主（第三类自由设计），被托管物（原版有 Java 而未翻译的部分）SHALL 照旧登记为翻译债，
  MUST NOT 借第三类类别豁免。

## Impact

- **app 壳**：新增平台宿主层（进程启动、就绪判定、日志管道、生命周期），仅桌面实现；
  macOS 沿用现有 entitlements（复用系统 JDK，无需 JIT 相关调整）。
- **包（纯 Dart）**：新增原版服务端控制面的翻译件——管理服务器客户端、RCON 客户端、
  `server.properties` 读写；版本特定部分按"版本包形态"归置（细节见 design.md）。
- **规格与规则文件**：`AGENTS.md`（第三类自由设计）、`openspec/config.yaml`（context 措辞，
  并修掉"数据上行属自由设计"这句与 `AGENTS.md`/`project-structure` 口径不一致的旧文）、
  `openspec/progress.md`（服务端本体债项）。
- **资产**：`assets/` 下新增不入库的 jar 类产物目录 + `pubspec.yaml` 资产声明 + 缺失时的
  优雅降级（无产物则入口置灰并提示）。
- **依赖**：无新第三方运行时依赖（`dart:io` 的 `Process` / `WebSocket` / `Socket` 足够）。
- **客户端**：数据面零改动；本地服务器在 `server-list` 语义上仍是普通条目。
