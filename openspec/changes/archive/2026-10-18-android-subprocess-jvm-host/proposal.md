# Proposal

## Why

已归档的 `android-embedded-jvm-host` 把被托管 JVM 装在**宿主应用进程**内，受 JNI"一进程一台
VM（且 `DestroyJavaVM` 后不可重建）"约束，退出世界后无法二次起服（真机 bug：第二次启动
静默夭折、UI 永远卡在「正在启动本地服务器」，实例日志分界行后一片空白）。同型参考实现
FCL 的答案已实证：`GameMenu.onExit`（`GameMenu.java:967-973`）每次会话结束
`killProcess(myPid())`——**一次会话一个进程、退即弃**；其 `:jvm` 专用进程先例
（`ProcessService`）证明同应用多进程承载是 Android 上的成熟工程范式。本仓 spike 已在真机
验证 `:jvm` 子进程承载两轮起停成立（pid 4370/4725 均就绪、退净、宿主存活）。

## What Changes

- **承载单元从「宿主应用进程」改为「应用专用 `:jvm` 子进程」**：一次会话一个子进程、
  会话结束即终止——每会话拿到全新 VM，二次起服不再受 JNI 约束。
- **真实退出码回归**：子进程的 OS 退出码经承载层回传，撤销归档 change 的"优雅停机回传 0"
  退化（progress.md 16.3）。
- **撤销 `exit()` GOT patch**：子进程死了就死了，无需拦截 libjvm 的 `exit()`；
  `nativeCreateJvm` 的自动 patch 加开关（本 change 后 native 层回归纯净）。
- **强制终止能力回归**：停止超时回落 SIGKILL 子进程，撤销"进程内承载不强杀"口径。
- **宿主终止 ⇒ 服务端终止的兜底**：force stop 杀全部进程天然成立；主进程异常死亡由
  子进程侧心跳 watchdog 兜底（心跳超时自杀，防孤儿）。
- **前台服务保活语义不变**：仍与被托管 JVM 生命周期同步（起服即起、停服即停），实现随
  承载切换调整。
- **BREAKING（规格口径）**：`android-embedded-jvm-host` 中「载体在应用进程内承载 JVM」
  「进程内承载的生命周期释放口径」两条按子进程承载重述；`local-server-host` 的
  「超时处置随承载方式」删除"进程内承载不强杀"分支。
- 承载上层契约（实例目录 / 配置 / EULA / RCON / 就绪判定）零语义改动，仅装配点换实现。

## Capabilities

### New Capabilities

（无——本 change 修改既有能力，不引入新能力。）

### Modified Capabilities

- `android-embedded-jvm-host`: 「载体在应用进程内承载 JVM」重述为「载体在应用专用子进程内
  承载 JVM」（新增"会话结束子进程随之终止""二次起服"场景）；「输出与退出码经承载层回传」
  的退出码改为真实 OS 退出码；「进程内承载的生命周期释放口径」重述为「专用子进程承载的
  生命周期释放口径」（恢复强杀、心跳 watchdog 兜底孤儿）。
- `local-server-host`: 「进程生命周期可控可观测」的"超时处置随承载方式"删除"进程内承载
  MUST NOT 强杀"分支——所有承载（桌面子进程 / Android 专用子进程）均可回落强制终止。

## Impact

- **app 壳 lib/**：新增 `AndroidSubprocessJvmHost`（`DedicatedServerCarrier` 的 Android 实现，
  装配点换它）；删除 `AndroidEmbeddedJvmHost` 进程内承载路径（jar 清单主类解析、日志 tail、
  判据行等资产全部复用）；契约测试同步。
- **android/**：`JvmSandboxService`（spike 代码）转正为正式承载 Service（`:jvm` 进程），
  补心跳 watchdog、结果文件、退出码采集；`mc_jvm_host.c` 的 exit patch 加开关 +
  新增 `nativeKill`（父进程对子进程 SIGKILL）；manifest 声明不变。
- **规格**：两个能力的 delta（见上）；`openspec/progress.md` 登记承载口径二次演进与
  三处退化/偏离的撤销。
- **不动**：`packages/`、RCON / 配置 / EULA / 世界列表 UI、JRE 产物安装链
  （`AndroidJreInstaller` 原样复用）。
