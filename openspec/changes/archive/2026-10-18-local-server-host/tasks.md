# Tasks

## 1. 纪律与规格落位

- [x] 1.1 `AGENTS.md` 新增第三类自由设计「运行时宿主（JVM 托管）」：写明它仅豁免"承载方式"，语义仍照原版，被托管物一律按翻译债处理。验证：通读该段落与 `openspec/specs/project-structure/spec.md` 的三处枚举逐字一致。
- [x] 1.2 修订 `openspec/config.yaml` 的 `context`：自由设计改为三类（3D 渲染后端 / 输入事件采集 / 运行时宿主），删去"数据上行属自由设计"的旧文（与 `AGENTS.md`、`project-structure` 口径不一致），并把"只连既有 MC 服务器"扩为"或在应用私有目录托管本机服务器"，保留"不做 world gen / 存档格式翻译"。验证：`openspec validate --all` 通过，且与 `project-structure` 规格无矛盾表述。
- [x] 1.3 `openspec/progress.md` 登记被托管物债项（服务端本体：`DedicatedServer`/`Main`/世界生成/玩法逻辑；判据 `server/dedicated/DedicatedServer.java`、`server/Main.java`），标注做法为"外部托管"，并注明宿主机制已在代码注释中标注第三类。验证：条目存在且含原版 `文件:行号`。
- [x] 1.4 资产携带口径落地：`assets/` 下新增 jar 产物目录、`.gitignore` 增补忽略规则、`pubspec.yaml` 逐目录声明、并在文档中写明"当前以构建期资产携带、不入库、后续改为使用时下载"。验证：`git status` 不出现 jar；缺该目录时 `flutter build macos` 仍成功。

## 2. 纯 Dart 控制面翻译件（逐行对照原版）

- [x] 2.1 `server.properties` 读写（键名/默认值/注释头/转义照 `DedicatedServerProperties.java`，判据见 `design.md` 判据清单）。验证：单测覆盖——原版默认值逐键相等、含未知键的文件写回后未知键原样保留、注释头文本与 `Main.java:113-121`/`Eula.java:44` 口径一致。
- [x] 2.2 RCON 客户端（判据 `server/rcon/thread/RconClient.java:17-21`、`:48-67`，`PktUtils.java:6`、`:9`、`:20`、`:24`、`:28`）。验证：单测用原版报文结构的**黄金字节序列**断言编码结果，鉴权成功/失败（`-1`）分支各有用例。
- [x] 2.3 管理服务器客户端（JSON-RPC over WebSocket，含 `Bearer` 与 `minecraft-v1` 子协议，判据 `SecurityConfig.java:6-20`、`AuthenticationHandler.java:29-31`、`:108-113`、`DiscoveryService.java:16`、`:34-35`）。方法集按 26.2 特定内容归 `mc_protocol_v26_2`。验证：对本地 mock WebSocket 服务端跑通 `discover` 与至少一个状态查询方法的单测（请求 JSON 与方法名逐字对齐原版 `methods/**`）。
- [x] 2.4 密钥生成（40 字符字母数字，判据 `SecurityConfig.java:6-20`）。验证：单测断言长度与字符集，且与原版 `isValid` 的 `^[a-zA-Z0-9]{40}$` 口径一致。

## 3. app 壳宿主层（桌面）

- [x] 3.1 产物解析：按实例配置的 `mcVersion`/`javaMajor` 解析 jar 与 JVM；桌面探测系统 JDK 主版本（Paper 26.2 需 Java 25），不满足即报"缺产物 + 期望位置"且入口置灰。验证：`test/local_server_host_test.dart`（缺 jar / 版本不符不静默替换 / JVM 主版本不足 / 找不到 JVM 四例）+ `test/local_server_screen_test.dart`（界面报缺 + 启动钮置灰）；并用伪造 `JAVA_HOME`（`java -version` 报 21）跑生产解析路径，得到"系统 Java 主版本为 21 … 需要 Java 25"。
- [x] 3.2 实例目录初始化：在应用私有根下按原版文件名生成目录与配置；写入项含 `online-mode=false`、`server-ip=` 空、`server-port=25565` 三项故意差异（代码注释写明理由）与开启 RCON/管理服务器所需键。验证：`test/local_server_host_test.dart` 断言生成的配置逐键与原版默认值口径一致、三项差异与理由在注释、原版目录名齐备、未知键不被丢弃、改端口落盘而密钥不变。
- [x] 3.3 EULA 同意流程：UI 对话框取得明确同意后才写 `eula=true` 并继续；同意状态可持久化与撤回。验证：`test/local_server_host_test.dart`（未同意时 `eula=false` 且不写 true、同意后持久化、撤回后回到未同意）；`_start` 在未同意时提前返回（不启动）。
- [x] 3.4 启动/停止/状态/日志：`Process.start(<java>, [...args, '-jar', <jar>, '--nogui'])`，stdout/stderr 入管道并同时落日志；就绪判定只认原版就绪行（`DedicatedServer.java:246`）。验证：`test/local_server_e2e_test.dart`（真实对照产物起服 → 状态转"可连接"）与就绪/监听/绑定失败判据单测；stdout 落 `logs/host-console.log`。
- [x] 3.5 停止与孤儿回收：优雅停止经控制通道下发 `stop` 并等待退出，超时上限后才强杀；应用退出/宿主重载时回收已启动实例。验证：e2e 实测经 RCON `stop` 后状态转"已停止"且端口释放；`main.dart` 经 `AppLifecycleListener.onExitRequested` 调 `reapAll()`。
- [x] 3.6 端口处理：25565 被占用时提示冲突并允许改端口，启动后回显实际监听端口。验证：端口可用性单测 + e2e 实测回显实际端口（`DedicatedServer.java:210` 的监听行）+ 界面冲突对话框（`_askPort` 给备选端口）。

## 4. UI 形态

- [x] 4.1 本地服务器条目：在服务器列表中呈现本地服务器（可启动/停止、查看状态与日志面板、编辑 `design.md` D7 所列配置项）。验证：`test/local_server_screen_test.dart`（列表呈现本地条目 + "新建本地世界"入口）与 `test/local_server_isolation_test.dart`（条目不进 `servers.dat`）；条目屏提供启停、状态、日志面板、RCON 指令框与配置对话框。
- [x] 4.2 单人世界快捷入口：创建或选中本地世界 → 走同一启动流程 → 自动连到 `127.0.0.1:<实际端口>`。验证：标题屏"单人游戏"入口（多世界时出选择框）→ `LocalServerArgs(autoJoin: true)` → 同 `_start(join: true)` 流程 → `_joinWorld()` 复用既有 `joinServer`；`test/local_server_screen_test.dart` 断言 autoJoin 路径安全降级不崩。**未复核项**：进世界后的区块/小地图渲染未在本 change 重新手工复核（该通路属既有 `remote-play`，其回归测试保持全绿）。
- [x] 4.3 `servers.dat` 隔离：本地服务器的状态与配置不写入 `servers.dat`。验证：`test/local_server_isolation_test.dart`——创建/修改/删除本地服务器条目后 `servers.dat` 字节不变，本地可变量落 `instances.json`（应用私有目录）。


## 5. 端到端验证

- [x] 5.1 端到端实测（用 `/Users/qshh/Desktop/paperMC` 的成熟产物做对照）：起服 → 就绪 → 用本应用连入 → 经 RCON 下发一条指令并看到原版回显 → 优雅停止。验证：`test/local_server_e2e_test.dart`（`MC_LOCAL_SERVER_E2E=1`，两例均 exit 0）——① 复制对照 `libraries/versions/cache/config/plugins`、独立端口起服 → 原版就绪行（`DedicatedServer.java:246`）转 ready → 回显实际监听端口（`:210`）→ `SessionAssembly.connectFor` 连入收到 `JoinedGame` 与 `ChunkLoaded` → RCON `list` 回显 `There are 1 of a max of` → 经 RCON `stop` 优雅停止 → 端口释放 → stdout 落 `logs/host-console.log`；② **真机运行路径**：不设 `jarPath`、不预置依赖，走生产资产解析（`AssetManifest` 枚举 `assets/server/26_2/*.jar`）起服，paperclip 自引导下载依赖后达就绪（37s）。跑后 `pgrep` 无孤儿进程。
     * 补记（实测暴露的缺陷 1）：首版把资产键写死为 `assets/server/26_2/server.jar`，用户放的是 `paper-26.2.jar` ⇒ 真机报"缺少 26.2 的服务端产物"（而上面①因设了 `jarPath` 绕过该分支仍为绿，属验证盲区）。已改为**枚举资产目录下任意 `.jar`**；`LocalServerManager` 增加资产来源注入口以让单测与"仓库里是否放了 jar"解耦；新增回归用例 `test/local_server_host_test.dart`「真实资产清单」，用生产 `rootBundle`+`AssetManifest` 证明落地成功。
     * 补记（实测暴露的缺陷 2）：首次启动时实例目录尚不存在，而 `Properties.storeFile` 逐行照抄 JDK `Properties.store`、**不建父目录**（实测 Dart：缺父目录写盘抛 `PathNotFoundException`）⇒ `gate.agreed` 走"读失败 → `saveDefaults()` 写回 `eula=false`"即抛异常，起服失败（真机证据：`artifacts/server-26.2.jar` 已落地而 `servers/<id>/` 从未被创建）。已修：`EulaGate` 构造即保证实例目录存在；`LocalServerScreen._start` 把 `createLayout()` 提到 EULA 门槛**之前**（e2e 一直是此顺序，故未暴露）。回归用例：`test/local_server_host_test.dart`「实例目录尚未创建时读/写 EULA 都不抛」。
- [x] 5.2 版本不匹配拒绝启动：实例配置的版本锚点字段（`LocalServerConfig.protocol`；`mcVersion` 仅决定产物目录命名）与客户端锚点（协议 776）不一致。验证：`test/local_server_host_test.dart`「协议与客户端锚点不同：拒绝并报出两侧版本」——`protocol: 775` 时 `resolveArtifacts` 抛 `VersionAnchorMismatchException`，异常携带 `serverVersion=775` 与 `clientVersions`（含装配点已注册的 776）；校验发生在 `start` 之前（`SessionAssembly.isSupported` 装配点判定，不按版本号 if 分支）。
- [x] 5.3 回归：`dart test`（全部包）+ `flutter analyze` 全绿；既有 107 项回归测试无新增失败。验证：包内 `dart test` 全绿（mc_protocol_v26_2 28、mc_render 20、mc_resource 44、mc_server 38、mc_session 37、mc_wire 51；mc_ui 无测试）；根 `flutter test` = **+132 通过 ~2 跳过 0 失败**（两条 e2e 默认跳过）；`flutter analyze lib/ test/` = No issues found。

## 6. 世界选项与 MC 控件配置界面（实测反馈追加）

- [x] 6.1 `LocalServerConfig` 增 `gamemode` / `difficulty` / `hardcore` / `forceGamemode`（后者后于 §8.2 删除，改为宿主恒 true）；`InstanceDirectory.initialProperties` 写入对应 `server.properties` 键（默认值照 `DedicatedServerProperties.java:63` / `:65-67` / `:68-70` / `:87`，取值序列化名照 `GameType.java:17-20`、`Difficulty.java:13-16`），并纳入 `ensureProperties` 的同步键集。验证：`test/local_server_host_test.dart`（首启逐键默认值 + 改游戏模式/难度落盘）。
- [x] 6.2 配置界面改用 mc_ui 控件：枚举/布尔用 `MCCycleButton`（原版 `gui/components/CycleButton`，`CreateWorldScreen.java:651-671` 即此法），文本用 `MCEditBox`（原版 `EditBox`），不再用裸 `TextField`；抽成公共 `LocalServerConfigDialog`（`lib/screens/multiplayer/local_server_config_dialog.dart`）供两处复用。验证：`test/local_server_screen_test.dart`「配置对话框：玩法项用 mc_ui 组件（CycleButton/EditBox），保存写回配置」。
- [x] 6.3 创建世界即可选玩法（原版在创建世界时就选游戏模式）：标题屏单人入口在**新建世界**时、多人屏「新建本地世界」时，先弹同一配置对话框。验证：`title_screen.dart` / `join_multiplayer_screen.dart` 的入口改动 + 6.2 的单测。

## 7. 单人流程与玩法修正（实测反馈追加，2026-10-18）

- [x] 7.1 单人入口改为**世界列表**（原版 `client/gui/screens/worldselection/SelectWorldScreen.java`）：列表 + 进入世界 / 创建新的世界 / 编辑 / 删除 / 返回；未选中条目时前述四键禁用（判据 `SelectWorldScreen.java:41`、`:80-104`、`:147-160`）。验证：`test/select_world_screen_test.dart`（标题与条目、无选中时禁用、选中后启用）。
- [x] 7.2 不许进屏即起服：列表屏**不**建实例目录、**不**启动进程；只有按「进入世界」（或创建后确认）才起服（用户要求："没有进入按钮的同时还自己占端口"）。验证：`test/select_world_screen_test.dart`「进世界列表不建实例目录、不起服占端口」。
- [x] 7.3 退出游戏即停服（**仅单人进世界路径**）：`LocalServerScreen(playMode: true)` 的极简形态（无日志/RCON）→ 起服 → 等就绪 → `joinServer`（内部 `await` 了 `'/game'` 的 push）→ 返回即 `stop()` 并回到世界列表；起不来 / 用户取消也收掉进程。多人 → 本地服务器那条管理路径仍由用户手动启停。验证：`test/local_server_screen_test.dart`「进世界形态（playMode）：缺产物时安全降级、不崩、不露日志面板」。
- [x] 7.4 **飞行修复**：本地服务器恒写 `force-gamemode=true`（判据 `ServerPlayer.java:2017-2024` + `DedicatedServer.java:759-761`；§8.2 起连字段一并去掉，不再给用户选）。实测根因：玩家存档 `playerGameType=0 (SURVIVAL)` 优先于服务器默认模式，而 `force-gamemode=false` 时 `getForcedGameType()` 返回 null ⇒ 服务端 abilities `mayFly=false` ⇒ 客户端双击空格切飞行被 `mayfly` 门禁挡住（`lib/client/player/local_player.dart:271-292`）。验证：读 `world/players/data/<uuid>.dat` 得 `playerGameType=0`，服务器日志 `Default game type: CREATIVE`（两处并存即证）。
- [x] 7.5 债登记：单机 ESC 同步暂停/继续、`SelectWorldScreen` 的搜索框与「重新创建」→ `openspec/progress.md` 第 15 项（含判据 `IntegratedServer.java:147-160`/`:188`、`TickCommand.java:52-53`/`:109-128`、`SelectWorldScreen.java:55`/`:98-101`）。

## 8. 配置优化（实测反馈追加，2026-10-18 第二批）

- [x] 8.1 **种子**：`LocalServerConfig` 增 `levelSeed`（默认 `''`＝随机），写 `server.properties` 的 `level-seed`（判据 `DedicatedServerProperties.java:135` 默认 `""`）并纳入同步键集；配置对话框增"种子"行（`MCEditBox`，提示"留空 = 随机"，判据原版 `CreateWorldScreen.java:738-775` 的 `SEED_LABEL`/`SEED_EMPTY_HINT`/`seedEdit`）。验证：`test/local_server_host_test.dart`（首启 `level-seed` 为空 + 改种子落盘）与 `test/local_server_screen_test.dart`（界面有"种子"行）。
- [x] 8.2 **单机不再暴露 `force-gamemode`**：从 `LocalServerConfig` 删除该字段，`initialProperties` 恒写 `force-gamemode=true`（单机形态即强制；判据 `DedicatedServer.java:759-761` + `ServerPlayer.java:2017-2024`），配置对话框移除该开关。验证：`test/local_server_screen_test.dart` 断言界面无"强制游戏模式"，`test/local_server_host_test.dart` 断言该键恒 `true`。
- [x] 8.3 **确认才创建**（回归：点"创建新的世界"先 `addConfig` 落盘、再弹表，取消也留了个世界）：改为 `LocalServerManager.newConfigDraft()`（不入库）→ 编辑草稿 → 用户确认才 `insertConfig()`；`select_world_screen.dart` 与 `join_multiplayer_screen.dart` 两处入口同步改。验证：`test/select_world_screen_test.dart`「点"创建新的世界"后取消＝什么都没建」。
- [x] 8.4 **端口冲突可就地停服**：冲突对话框检测占用端口的**本宿主实例**（`processFor().isRunning && (listeningPort ?? port) == port`），命中则多一个**红色**「停止该服务器」按钮（停掉占用者后仍用原端口）；端口输入框亦换成 `MCEditBox`（原版 `EditBox`）。
- [x] 8.5 **退游戏静默停服**：`playMode` 路径先退回世界列表再 `stop()`，不再停留"正在停止…"画面（用户要求"静默"，也避免上一局占着端口导致下一局冲突）。

## 9. 端口处理重做（实测反馈追加，2026-10-18 第三批）

> 背景（实测）：反复出现"服务端未在 300 秒内就绪"，实为**启动即崩**——
> `servers/<id>/logs/host-console.log` 里 **7 次** `java.net.BindException: Address already in use`，
> 失败点在 `JsonRpc.create`（管理服务器端口），且该实例 `world/level.dat` 从未生成。
> 根因：Paper 在**生成世界之前**就绑管理服务器端口，而本仓各实例默认同端口（25565/25575/25585），
> 旧实现只预检了游戏端口。

- [x] 9.1 起服前**三个端口**全部预检（游戏 / RCON / 管理服务器）；任一被占即弹「端口设置」。验证：`test/local_server_ports_dialog_test.dart`。
- [x] 9.2 新增 `LocalServerPortsDialog`：三行各自 **实时校验**，状态分「可用 / 被占用（含占用者名）/ 与另一个端口重复 / 须是 1–65535 的整数」；**三个都可用才允许按「确定」**（旧实现在冲突时确定照样可点）。占用者是**本宿主实例**时该行给**红色**「停止该服务器（名称）」按钮，停掉后自动重新校验。验证：同上（含"确定禁用"与"改端口后解禁"两例）。
- [x] 9.3 `LocalServerManager.localHolderOf(port)`：按进程**实际**监听端口反查本宿主占用者（判据 `DedicatedServer.java:210` 的端口回显）。
- [x] 9.4 失败原因如实上报：`_failureReason()` 从捕获输出里挑真实原因（`Address already in use` / `FAILED TO BIND TO PORT!` / 首条 `ERROR]`），不再一律说"未在 300 秒内就绪"。

## 10. 残留孤儿与"已生成世界"语义（实测反馈追加，2026-10-18 第四批）

> 背景（实测）：应用重启后端口仍被占——查到 `pid 31798` 的 java 进程（起于 01:54，PPID=1），
> 是**上次会话的孤儿**：Dart 子进程不随父进程退出而死，应用被强杀/开发期热重启都会丢掉
> Dart 侧句柄而 OS 进程照活；旧实现只查本次会话的进程表 ⇒ 端口面板"只知道被占、停不掉"。

- [x] 10.1 `LocalServerManager.findPortHolder(port)`：内存查不到时用 `lsof` 反查监听该端口的 PID，再以其 **cwd 落在宿主根下**确证属我方（防 PID 复用/他人 java 进程误杀）；命中即给可停的 [LocalPortHolder]（本会话实例走 RCON 优雅停，孤儿走 SIGTERM→SIGKILL）。
- [x] 10.2 `LocalServerManager.reapLeftovers()`：`initLocalServerHost()` 每次启动清掉上次会话残留的服务端进程（同样以 cwd 判据），实测那条孤儿即由此路径清理。
- [x] 10.3 端口面板的红色「停止该服务器（名称）」现在对**孤儿**也出现，点掉后自动重新校验并解禁「确定」。验证：`test/local_server_ports_dialog_test.dart`「被本宿主名下的服务器占用：给**红色**停止按钮，停掉后自动解禁确定」（注入假 holder，含颜色断言）。
- [x] 10.4 **已生成的世界只读**：`InstanceDirectory.worldExists`（`world/level.dat` 存在）；配置对话框在该状态下把 `level-seed` 与 `hardcore` 置灰并给说明（世界生成参数创建时固化，判据 `EditWorldScreen.java:41/57/71`），`gamemode`/`difficulty` 仍可改。验证：`test/local_server_screen_test.dart`「已生成的世界：种子与极限模式在配置里只读」。
- [x] 10.5 世界列表「编辑」改为**照原版 `EditWorldScreen`**：只改名（名字为空禁用保存，判据 `:74/:76`），不弹完整配置表。验证：`test/edit_world_screen_test.dart`（只有名称一个 `MCEditBox`、空名禁用保存、保存写回）。

## 11. 引导缓存跨实例共享（实测反馈追加，2026-10-18 第五批）

> 背景（实测）：**每新建一个世界都会重下一遍** paperclip 引导产物——`servers/1792261254081432` 与
> `servers/1792262684760811` 各有一份 `libraries 79M + versions 28M + cache ~58M`，各自
> `host-console.log` 里各 1 次 `Downloading mojang_26.2.jar`。根因：paperclip 把引导产物下在
> **进程工作目录**下，而我们"一个世界一个实例目录" ⇒ 每个新世界都是冷缓存。原版单机不会如此
> （jar/libs 是游戏自带的、全局一份）。

- [x] 11.1 宿主根下新增**共享缓存** `shared/{libraries,versions,cache}`：实例启动前若自己还没有而共享已有 → 复制进来（[pullSharedCache]）；实例下齐后（进程到原版就绪行）→ 回写共享播种（[pushSharedCache]）。**不用符号链接**——Android/Windows 上未必可建（沙箱/权限），复制是跨平台做法（用户确认的口径）。验证：`test/local_server_host_test.dart`「共享缓存：新实例从 shared 复制进来（不再走网络），已有实例回写播种」（含幂等）。
- [x] 11.2 接线：`LocalServerManager.instanceDirectoryFor` 注入 `sharedDir: <root>/shared`；`LocalServerScreen._start` 在建目录后 `await _dir.pullSharedCache()`；状态监听在首次 `ready` 时 `unawaited(_dir.pushSharedCache())`。
- [x] 11.3 真机对照（实测证据，2026-10-18）：同一台机器两个世界——"1"（`1792261254081432`）的 `host-console.log` 以 `Downloading mojang_26.2.jar` / `Applying patches` 开头（1 次下载，其后 5 次到就绪行），"2"（`1792263829514923`）以 `Starting org.bukkit.craftbukkit.Main` 开头、**0 次下载**且成功到就绪行；`shared/{libraries 79M, versions 28M, cache 58M}` 已播种。⇒ 新建世界不再走网络。

## Workflow follow-up

- 归档前复核 `AGENTS.md` / `openspec/config.yaml` / `openspec/progress.md` 三处改动已随本 change 一同提交。
- 下一个 change（Android 嵌入式 JVM）起草时，把本 change 的宿主管道抽象（产物解析、就绪判定、生命周期接口）作为接入点，避免重复实现。
