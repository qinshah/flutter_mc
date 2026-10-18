# Spec Delta

## Purpose

把 Android 承载单元由「宿主应用进程内 JVM」演进为「应用专用子进程（`:jvm`）内 JVM」：
一次会话一个子进程、会话结束即终止——绕开 JNI"一进程一台 VM"对二次起服的限制，取回真实
退出码与强制终止能力。宿主终止 ⇒ 服务端终止的口径以"force stop 全杀 + 子进程心跳 watchdog"
重述。

## RENAMED Requirements

- FROM: ### Requirement: 载体在应用进程内承载 JVM
  TO: ### Requirement: 载体在应用专用子进程内承载 JVM

## MODIFIED Requirements

### Requirement: 载体在应用专用子进程内承载 JVM

Android 上被托管服务端的 JVM SHALL 在宿主应用的**专用子进程**内装载（子进程由系统派生，
native 动态加载 JRE 库并创建 VM），一次会话对应一个子进程；MUST NOT 依赖系统 `java` 可执行
文件，也 MUST NOT 依赖 `execve` 应用可写目录中的文件。

#### Scenario: 无系统 java 也能启动

- **WHEN** Android 设备上不存在任何系统 JVM 或 `java` 命令
- **THEN** 被托管服务端仍能启动；启动路径不含对系统 `java` 的任何查找或调用

#### Scenario: 不依赖 execve

- **WHEN** 承载层装载 JRE
- **THEN** 子进程以动态加载方式取入 JRE 库并由 native 创建 VM（子进程由系统派生，非
  `execve` 应用可写目录中的可执行文件）；实现中出现"需 `execve` 应用可写目录中的可执行
  文件"的步骤即判违规

#### Scenario: 定位不到 JVM 库时明确报缺

- **WHEN** 目标 ABI 的 JRE 库在私有目录中不存在
- **THEN** 状态为"缺少产物"并给出期望位置，MUST NOT 尝试其他装载路径掩盖缺失

#### Scenario: 会话结束子进程随之终止

- **WHEN** 被托管服务端停止（优雅停止或崩溃）
- **THEN** 承载子进程随之终止，MUST NOT 残留空转的承载进程或端口占用

#### Scenario: 二次起服

- **WHEN** 上一会话的子进程已终止后，用户再次启动被托管服务端
- **THEN** 承载层以**全新子进程**承载（全新 VM），服务端能再次走完"启动 → 原版就绪行"，
  MUST NOT 复用上一会话的进程或 VM

### Requirement: 输出与退出码经承载层回传

被托管 JVM 的 stdout/stderr SHALL 由承载层重定向写入实例目录下的日志文件，日志 SHALL 支持
增量读取；被托管 JVM 结束时 SHALL 回传其承载子进程的**真实退出码**。

#### Scenario: 输出落到实例日志

- **WHEN** 被托管 JVM 向 stdout 或 stderr 写入内容
- **THEN** 该内容出现在实例目录的日志文件中，并可被日志面板增量读取

#### Scenario: 退出码可观测

- **WHEN** 被托管 JVM 结束（优雅停止或异常退出）
- **THEN** 其承载子进程的真实退出码经承载层回传并被记录，状态随之更新（优雅停止与异常
  退出的退出码 MUST 可区分）

## REMOVED Requirements

### Requirement: 进程内承载的生命周期释放口径

进程内承载下，宿主应用进程终止 SHALL 一并终止被托管服务端；承载层 MUST NOT 声称可对被托管
JVM 单独下发强制终止信号。

#### Scenario: 宿主终止不留残余

- **WHEN** 宿主应用进程被用户或系统终止
- **THEN** 服务端随之终止，MUST NOT 残留独立的服务端进程或占用端口

#### Scenario: 不提供进程内强杀

- **WHEN** 承载方式为进程内 JVM 且优雅停止超时
- **THEN** 不强杀（无从单独终止该 JVM），转为报告失败并保留日志与状态

（整条移除：承载单元演进为专用子进程后，"进程内 MUST NOT 强杀"的例外不复存在；
替代口径见下方 ADDED 的「专用子进程承载的生命周期释放口径」。）

## ADDED Requirements

### Requirement: 专用子进程承载的生命周期释放口径

专用子进程承载下，宿主应用的终止 SHALL 一并终止承载子进程；承载层 SHALL 提供对承载子进程
的强制终止能力；两者之外的孤儿风险 SHALL 由子进程侧的兜底机制消除。

#### Scenario: 宿主终止不留残余

- **WHEN** 宿主应用被用户或系统终止（含 force stop 与主进程异常死亡）
- **THEN** 承载子进程随之终止（force stop 由系统全杀；主进程异常死亡由子进程侧
  watchdog 兜底自杀），MUST NOT 残留独立的服务端进程或占用端口

#### Scenario: 提供强制终止

- **WHEN** 优雅停止超出等待上限
- **THEN** 承载层 MAY（且 SHALL 有能力）对承载子进程下发强制终止，子进程随之消亡，
  端口与进程不再残留

#### Scenario: 上一会话残留可检出

- **WHEN** 承载层准备开启新会话
- **THEN** 上一会话的承载子进程存活状态 MUST 可可靠判定（不依赖易误报的进程表探活），
  未退净时 MUST NOT 在旧进程上重入承载逻辑
