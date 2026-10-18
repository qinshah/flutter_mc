# local-server-host Specification

## Purpose

定义"本机托管原版系 Java 服务端"的端到端外部契约：产物解析与版本锚点、EULA 同意门槛、
私有目录布局、进程生命周期与就绪判定、控制面（原版管理服务器 + RCON）、以及它在 UI 中
作为"本地服务器条目 + 单人快捷入口"的形态。

## Requirements

### Requirement: 运行根为应用私有目录

服务端运行所需的全部文件（世界数据、日志、配置、库缓存）SHALL 位于应用私有目录下，其根
路径由调用方注入；MUST NOT 读写用户的 MC 目录或任意外部路径。首次运行 SHALL 以最小配置
初始化该目录，MUST NOT 依赖预先存在的外部存档。

#### Scenario: 首次运行从零初始化

- **WHEN** 私有目录下不存在任何服务端文件
- **THEN** 在用户同意 EULA 后，以原版默认口径生成配置与空白世界，不读取任何外部存档

#### Scenario: 不触碰用户 MC 目录

- **WHEN** 无论何种路径触发服务端启动
- **THEN** 所读写路径全部落在注入的私有根之下；出现越界路径视为错误

### Requirement: EULA 同意为启动硬门槛

首次启动前，SHALL 向用户展示服务端 EULA 并获得**明确同意**。未获同意时 MUST NOT 写入
`eula=true`、MUST NOT 启动服务端；同意状态 SHALL 持久化且可撤回（撤回后再次启动需重新同意）。

#### Scenario: 未同意不启动

- **WHEN** 用户未同意 EULA 或已撤回同意
- **THEN** 启动被拒绝并说明原因，`eula.txt` 保持 `false`（或不存在）

#### Scenario: 同意后才写盘

- **WHEN** 用户明确同意
- **THEN** 写入 `eula=true` 并继续启动流程

### Requirement: 产物解析与缺失降级

服务端 jar 与 JVM 的实现 SHALL 经"产物解析"决定，依据是**被托管的 MC 版本**与**所需 Java
主版本**。产物缺失时 SHALL 明确报告缺失项与期望位置，UI 入口 SHALL 置灰并给出补齐途径；
MUST NOT 静默替换为其他版本。jar 与 JVM 产物 MUST NOT 入库（版本控制不追踪）；当前以
构建期资产携带时，SHALL 在配置与文档中写明，且缺产物不得导致构建或其余功能失败。

#### Scenario: 缺产物时明确报缺

- **WHEN** 私有目录与构建资产中均找不到匹配版本的 jar
- **THEN** 报告"缺少 <版本> 的产物"与期望位置，本地服务器入口不可用，其余功能不受影响

#### Scenario: 桌面复用系统 JVM

- **WHEN** 平台为桌面且系统已装有满足主版本要求的 JDK
- **THEN** 直接复用该系统 JVM，不要求下载或捆绑 JRE

### Requirement: 版本锚点与客户端同版

被托管服务端的 MC 版本（含协议号）SHALL 与客户端会话锚点版本一致。不一致时 SHALL 拒绝
启动，并同时指出服务端版本与客户端锚点版本。

#### Scenario: 版本不匹配即拒绝

- **WHEN** 产物对应的协议号与客户端装配点选择的协议版本不同
- **THEN** 拒绝启动并报出两侧版本，MUST NOT 尝试连接或降级到其他版本

### Requirement: 进程生命周期可控可观测

SHALL 提供启动、停止、状态查询与日志读取能力。停止 SHALL 走优雅路径（下发停止请求并等待
退出）；超出等待上限仍未退出时 SHALL 回落到强制终止（对承载单元下发终止信号；Android
专用子进程承载下即对子进程强制终止）。异常退出 SHALL 被检出并暴露退出码，日志 SHALL 保留。
MUST NOT 残留孤儿进程：应用退出或宿主重启时，已启动的服务端 SHALL 被回收。

#### Scenario: 优雅停止

- **WHEN** 用户请求停止正在运行的服务端
- **THEN** 先下发停止请求并等待退出；超出等待上限仍未退出才进入超时处置

#### Scenario: 崩溃可观测

- **WHEN** 服务端进程异常退出
- **THEN** 状态转为失败并暴露退出码，最近日志仍可读取

#### Scenario: 超时处置随承载方式

- **WHEN** 优雅停止超出等待上限
- **THEN** 承载层对承载单元（桌面子进程 / Android 承载子进程）强制终止，进程与端口不再残留
  （原"进程内承载不强杀"分支随子进程承载消失，所有承载均可回落强制终止）

### Requirement: 就绪判定以原版输出为准

"可以连接"的判定 SHALL 取自服务端输出的**原版就绪行**（`Done (<耗时>)! For help, type
"help"`），MUST NOT 以"进程已启动"、端口可连或任意自定义信号替代。

#### Scenario: 未就绪不可连

- **WHEN** 进程已起但尚未输出就绪行
- **THEN** 状态为"启动中"，连接入口不作为可连状态呈现

### Requirement: 网络与端口默认

默认端口 SHALL 为 25565，端口被占用时 SHALL 允许选择其他可用端口并把最终端口回显给用户。
监听 SHALL 覆盖局域网（`server-ip` 为空，绑定全部接口）。`online-mode` 默认 SHALL 为
`false`（兼容离线客户端）。启动完成后 SHALL 以 `127.0.0.1:<最终端口>` 作为可连接地址。

#### Scenario: 端口冲突可改

- **WHEN** 25565 已被占用
- **THEN** 提示冲突并允许改到其他可用端口，并在启动后回显实际监听端口

#### Scenario: 局域网默认可连

- **WHEN** 服务端以默认配置启动于普通局域网
- **THEN** 同网段设备可用同一端口连接（离线模式下无需正版验证）

### Requirement: 控制面只走原版通道

服务器状态、玩家列表、白名单/封禁、难度与游戏规则等 SHALL 经**原版管理服务器**通道
（JSON-RPC over WebSocket，带密钥鉴权与可开关的 TLS）读取与修改；任意指令 SHALL 经
**原版 RCON** 通道下发。MUST NOT 自造控制协议，MUST NOT 以解析日志文本替代上述通道实现
同一能力。相应通道未启用或不可用时 SHALL 显式提示，MUST NOT 静默降级为不可用界面。

#### Scenario: 状态来自管理服务器

- **WHEN** 用户查看本地服务器状态与在线玩家
- **THEN** 数据来自原版管理服务器的对应方法返回，而非日志文本推断

#### Scenario: 指令走 RCON

- **WHEN** 用户在日志面板下发一条指令
- **THEN** 该指令经原版 RCON 通道发送，输出回显自原版响应

### Requirement: 配置读写照原版口径

配置文件的读写 SHALL 沿用原版的键名、默认值与文本格式（含注释头、键值转义与排序口径）；
文件中出现的未知键 SHALL 原样保留，MUST NOT 因写入而丢弃。

#### Scenario: 未知键不被丢弃

- **WHEN** 配置文件中含本实现未识别的键（如后续版本新增项）
- **THEN** 写回后该键仍存在且值不变

### Requirement: UI 形态为"一等公民条目 + 快捷入口"

本地服务器 SHALL 在服务器列表中作为条目呈现（**管理形态**：启停、状态、日志与配置）。
"单人世界"SHALL 呈现为**世界列表**（照原版 `client/gui/screens/worldselection/SelectWorldScreen.java`：
进入世界 / 创建新的世界 / 编辑 / 删除 / 返回，未选中条目时前述四键禁用）。本地服务器的
状态与配置 MUST NOT 混入原版 `servers.dat` 的条目持久化，以保持该文件格式不变。

#### Scenario: 单人入口是世界列表，且不提前起服

- **WHEN** 用户从"单人游戏"入口进入
- **THEN** 呈现本地世界列表，**不启动服务器、不创建实例目录**（MUST NOT 无进入动作就占用端口）

#### Scenario: 选中世界并按"进入世界"才启动服务器

- **WHEN** 用户在世界列表选中一个世界并按"进入世界"
- **THEN** 才启动该世界的本地服务器，就绪后连到 `127.0.0.1:<实际端口>`

#### Scenario: 退出游戏即停服（仅单人世界路径）

- **WHEN** 用户从单人世界退出游戏（或取消/未就绪而返回）
- **THEN** 该世界的本地服务器被停止、端口释放（管理形态的本地服务器仍由用户手动启停）

#### Scenario: 列表文件不被污染

- **WHEN** 创建或修改本地服务器条目
- **THEN** `servers.dat` 内容与结构保持原版口径，本地服务器的可变量存于应用私有目录

### Requirement: 世界选项照原版键与 MC 控件

本地服务器 SHALL 暴露世界/玩法项（至少 `gamemode`、`difficulty`、`hardcore`、`level-seed`），
键名、默认值与取值序列化名 SHALL 照原版 `server.properties`。这些项在界面上 SHALL 用原版的
同类控件呈现，MUST NOT 让用户以手打枚举值的方式修改。

`force-gamemode` 由**宿主持恒 `true`**、MUST NOT 作为用户可选项暴露——本地服务器就是单机形态，
玩家的游戏模式以世界设定为准。

#### Scenario: 新建世界即可选玩法与种子

- **WHEN** 用户创建本地世界（单人入口或"新建本地世界"）
- **THEN** 界面以 CycleButton 提供游戏模式、难度、极限模式等选项
  （原版 `gui/components/CycleButton`，`CreateWorldScreen.java:651-671` 即此法；本仓取 mc_ui 的
  `MCCycleButton`），文本项用 `MCEditBox`（原版 `EditBox`）
- **AND** 提供种子输入（原版 `CreateWorldScreen.java:738-775` 的 `seedEdit`：留空即随机，
  空值时显示提示），确认后落到 `server.properties` 对应键（`DedicatedServerProperties.java:63` /
  `:65-67` / `:68-70` / `:87` / `:135`；取值名照 `GameType.java:17-20`、`Difficulty.java:13-16`）

#### Scenario: 确认才创建

- **WHEN** 用户在创建世界界面上按"取消"
- **THEN** MUST NOT 创建任何世界实例（不入库、不写 `instances.json`、不建实例目录）

#### Scenario: 极限模式锁难度

- **WHEN** 极限模式开启
- **THEN** 难度固定为 `hard` 且选项不可改（`WorldCreationUiState.java:139`、
  `CreateWorldScreen.java:670` 的 `difficultyButton.active = !isHardcore`）
