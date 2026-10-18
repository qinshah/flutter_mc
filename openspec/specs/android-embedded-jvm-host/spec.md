# android-embedded-jvm-host Specification

## Purpose
定义 Android 上"在当前应用进程内承载外部 JVM 与被托管 Java 产物"的载体契约：JRE 产物与私有目录
安装、进程内 JVM 的装载与保活、输出与退出码回传、生命周期释放口径，以及它与桌面承载层共享的
同一条契约面。

## Requirements

### Requirement: 载体在应用进程内承载 JVM

Android 上被托管服务端的 JVM SHALL 在宿主应用进程内装载（native 动态加载 JRE 库并由 native
创建 VM），MUST NOT 依赖系统 `java` 可执行文件，也 MUST NOT 依赖 `execve` 应用可写目录中的文件。

#### Scenario: 无系统 java 也能启动

- **WHEN** Android 设备上不存在任何系统 JVM 或 `java` 命令
- **THEN** 被托管服务端仍能启动；启动路径不含对系统 `java` 的任何查找或调用

#### Scenario: 不依赖 execve

- **WHEN** 承载层装载 JRE
- **THEN** 以动态加载方式取入 JRE 库并由 native 创建 VM；实现中出现"需 `execve` 应用可写目录
  中的可执行文件"的步骤即判违规

#### Scenario: 定位不到 JVM 库时明确报缺

- **WHEN** 目标 ABI 的 JRE 库在私有目录中不存在
- **THEN** 状态为"缺少产物"并给出期望位置，MUST NOT 尝试其他装载路径掩盖缺失

### Requirement: JRE 产物按客户端锚点主版本提供

JRE 产物 SHALL 与客户端锚点版本所需的 Java 主版本一致，SHALL 提供目标 ABI（`arm64-v8a`）的
产物；缺失或主版本不符时 SHALL 拒绝启动并报出所需主版本，MUST NOT 静默替换为其他主版本。

#### Scenario: 主版本不符即拒绝

- **WHEN** 可用 JRE 的主版本低于被托管服务端所需主版本
- **THEN** 拒绝启动并同时报出双方主版本，MUST NOT 以低主版本尝试启动

#### Scenario: 缺 arm64 产物时入口置灰

- **WHEN** 仅有其他 ABI 的 JRE 产物
- **THEN** 本地服务器入口不可用并给出补齐途径，其余功能不受影响

### Requirement: 产物安装于应用私有目录

JRE 与被托管 jar SHALL 安装或解包到应用私有目录；公开这一能力 MUST NOT 要求任何存储权限，
所读写路径 MUST NOT 越出私有根。

#### Scenario: 零存储权限可用

- **WHEN** 应用未被授予任何存储权限（含任意文件访问）
- **THEN** 服务端仍能完成产物安装与启动，全部读写落在注入的私有根之下

#### Scenario: JRE 与 jar 不入库

- **WHEN** 检查版本控制追踪内容
- **THEN** JRE 与 jar 产物 MUST NOT 出现在追踪列表中，仅保留占位文件

### Requirement: 输出与退出码经承载层回传

被托管 JVM 的 stdout/stderr SHALL 由承载层重定向写入实例目录下的日志文件，日志 SHALL 支持
增量读取；JVM 结束时 SHALL 回传退出码。

#### Scenario: 输出落到实例日志

- **WHEN** 被托管 JVM 向 stdout 或 stderr 写入内容
- **THEN** 该内容出现在实例目录的日志文件中，并可被日志面板增量读取

#### Scenario: 退出码可观测

- **WHEN** 被托管 JVM 结束
- **THEN** 退出码经承载层回传并被记录，状态随之更新

### Requirement: 长期运行以前台服务保活

Android 上承载长时间运行的被托管服务端时，SHALL 以前台服务维持宿主进程存活；该服务的启动与
停止 SHALL 与被托管 JVM 的生命周期同步。

#### Scenario: 退到后台不断线

- **WHEN** 用户切离本应用而服务端仍在运行
- **THEN** 前台服务保持宿主进程存活，服务端不被系统回收，已连接的玩家不掉线

#### Scenario: 停服即撤保活

- **WHEN** 服务端被停止
- **THEN** 前台服务随之停止，MUST NOT 留下仅用于保活的空转服务

### Requirement: 进程内承载的生命周期释放口径

进程内承载下，宿主应用进程终止 SHALL 一并终止被托管服务端；承载层 MUST NOT 声称可对被托管
JVM 单独下发强制终止信号。

#### Scenario: 宿主终止不留残余

- **WHEN** 宿主应用进程被用户或系统终止
- **THEN** 服务端随之终止，MUST NOT 残留独立的服务端进程或占用端口

#### Scenario: 不提供进程内强杀

- **WHEN** 承载方式为进程内 JVM 且优雅停止超时
- **THEN** 不强杀（无从单独终止该 JVM），转为报告失败并保留日志与状态

### Requirement: 与桌面承载层共享同一契约面

Android 承载层 SHALL 复用与桌面相同的上层契约（私有运行根、实例目录、配置读写、EULA 门槛、
原版管理服务器与 RCON 控制面、就绪文本判定），MUST NOT 因平台差异改写这些语义。

#### Scenario: 控制面不分平台

- **WHEN** 在 Android 上查看状态、玩家列表或下发指令
- **THEN** 仍经原版管理服务器与 RCON 通道，与桌面行为一致

#### Scenario: 配置口径不分平台

- **WHEN** 在 Android 上读写服务端配置
- **THEN** 键名、默认值、文本格式与未知键保留口径均与桌面一致

### Requirement: 第三方 native 复用须带许可与来源，并登记本仓受限

承载层 MAY 复用第三方 native 代码（含 MIT / BSD 等宽松许可件与 GPL-3.0 件）。复用 MUST 保留
原始版权与许可头、记明出处与许可证名，并 SHALL 随仓库落对应许可文件。引入 GPL-3.0 件时，
本仓的**分发许可 SHALL 因此登记为受限**——MUST NOT 声称本仓为宽松许可，SHALL 在
`openspec/progress.md` 记明"本仓分发因此受 GPL-3.0 约束"。MUST NOT 无署名地复制第三方代码。

#### Scenario: 复用宽松许可件须署名

- **WHEN** 复用 MIT 的 namespace 绕行件
- **THEN** 保留其版权与许可头，并在来源说明中记明出处与许可证名

#### Scenario: 引入 GPL-3.0 件须落许可并登记受限

- **WHEN** 承载层引入 GPL-3.0 许可的第三方代码
- **THEN** 随仓库落该许可文本，并在来源说明与 `openspec/progress.md` 记明"本仓分发因此受
  GPL-3.0 约束"的受限项；MUST NOT 对外声称本仓为宽松许可
</content>
</invoke>
