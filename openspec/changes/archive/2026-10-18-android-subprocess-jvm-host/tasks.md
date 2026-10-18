# Tasks

## 1. Native 层（mc_jvm_host.c）

- [x] 1.1 `nativeCreateJvm` 的 exit() GOT patch 加开关（入参控制，子进程承载**不装**——
      child 死就死，撤销对宿主进程 libjvm 重定位的改写；design D7）；既有调用点显式传参，
      行为默认不变
- [x] 1.2 新增 `nativeKill(pid)`（`kill(pid, SIGKILL)`，同 uid 由内核放行）并经
      `JvmHost` 暴露——承载父进程对子进程的强制终止能力（design D6）

## 2. Kotlin 承载 Service（`:jvm` 子进程）

- [x] 2.1 `JvmSandboxService`（spike 代码）转正：参数校验与失败显式报错、pidFile 生命周期
      （启动写 pid、自杀前删）、停机哨兵（本会话日志段内认停机行 `MinecraftServer.java:650`，
      留存盘窗口后 SIGKILL 自杀）；`AndroidManifest.xml` 服务声明保留 `:jvm` 进程
- [x] 2.2 心跳 watchdog：主进程周期性写心跳文件，child 超时（~30s 无更新）自杀——
      覆盖"主进程异常死亡 ⇒ 服务端终止"（design D4）
- [x] 2.3 结果文件回传：child 在 `runMain` 返回 / 哨兵触发时写
      `{mainExitCode, stopConfirmed}`，供父进程取真实退出码（design D5）

## 3. Dart 承载实现与装配点（app 壳 lib/）

- [x] 3.1 `AndroidEmbeddedJvmHost.computeSandboxParams` 转正（脱离 spike 命名），含
      `jar_manifest.dart` 主类解析复用；新增 `AndroidSubprocessJvmHost implements
      DedicatedServerCarrier`：`start` = 产物解析（`AndroidJreInstaller` 原样）→ startService
      → 日志行驱动状态（就绪 `DedicatedServer.java:246` / 启动失败 `Main.java:227` /
      停机 `MinecraftServer.java:650`）；`stop` = RCON `stop` → 等 pidFile 消失 → 超时
      `nativeKill` 强杀；`exitCode` 取结果文件真实值（design D8）
- [x] 3.2 装配点（`local_server_host.dart` `_createCarrier`）Android 分支换
      `AndroidSubprocessJvmHost`；删除进程内承载路径（`AndroidEmbeddedJvmHost.start` 的
      宿主进程内 dlopen/建 VM/调主类链）；`AndroidJreInstaller`、日志 tail、判据正则原样复用
- [x] 3.3 心跳文件写入方：主进程在承载运行期间周期性 touch 心跳文件（起服即起、停服即停，
      与前台服务同步；design D4）
- [x] 3.4 契约测试更新：两承载（桌面子进程 / Android `:jvm` 子进程）共面断言；
      "超时回落强制终止"分支覆盖 Android 路径（`nativeKill` 可注入）；进程内"不强杀"
      旧分支删除；全量测试回归

## 4. 真机验证（端到端）

- [x] 4.1 **二次起服**（spec 新增场景）：起服 → 就绪 → RCON stop → 子进程退净 → **再起 →
      新子进程（pid 不同）→ 再次就绪**；实例日志每会话分界清晰
- [x] 4.2 **真实退出码**：优雅停止 exitCode=0；人为制造启动失败（如 EULA 撤回/坏参数），
      状态转 failed 且退出码非 0 可观测（与"回传 0"退化划清界限）
- [x] 4.3 **宿主终止 ⇒ 服务端终止**：force stop 杀全部进程（`:jvm` 同死、无端口残留）；
      主进程异常终止（`adb shell am kill` 或 crash 注入）→ child 心跳超时自杀（watchdog 兜底）
- [x] 4.4 **退后台不断线**：承载运行中退后台 60s+，服务端口仍 LISTEN、已连接玩家不掉线、
      前台服务常驻（`specialUse`）不被回收；停服后前台服务与子进程均无空转残留
- [x] 4.5 **端到端 + 客户端连入**：起服 → 原版就绪行 → 生产 `joinServer` 连入
      `127.0.0.1`（RCON `list` 见玩家）→ RCON stop → 优雅退出 → 退出码可观测 → 无残留

## 5. 文档与登记

- [x] 5.1 `openspec/progress.md` 登记承载口径二次演进（16.4）：进程内 → 专用子进程；
      三处退化/偏离（退出码回传 0、exit GOT patch、不强杀）整体撤销；"一进程一台 VM"
      限制的口径更新
- [x] 5.2 spike 代码收编清点：`JvmSandboxService.kt`、自检 `subprocess` 模式、
      `computeSandboxParams` 转正或删除，工作区不留 spike 残留；`openspec validate` 通过后归档

### 真机证据补记（2026-10-18，MIUI/Android 13）

- 4.1：twice 模式同会话两轮——子进程 pid 32472/32682，均"就绪 → RCON stop → stopped /
  退出码 0"，宿主存活、:jvm 无残留、端口无残留。
- 4.2：① 契约测试 exitStatus=70 → failed/70（无停机行 ⇒ 非优雅）；② 真机注入
  createJvm 失败（删 libjvm.so）→ 560ms 内 failed、退出码 -1、结果文件 fatal 可读、
  UI 不卡 starting（对照旧 bug 的"永远正在启动"）。
- 4.3：force-stop 全杀（宿主/child/端口全清）+ 主进程 am crash 后无孤儿（child 经
  watchdog 兜底消亡）；残留检查在 child 存活期间正确拒绝重入（spec「上一会话残留
  可检出」设备实证）。watchdog 的 30s 精确时序未逐秒取证，以"宿主死后无孤儿"为结论。
- 4.4：承载运行中退后台（Settings 覆盖）60s——宿主与 :jvm child 均存活、25566/25576
  仍 LISTEN、前台服务 isForeground=true。⚠ 中途实测：:jvm 进程**非前台化**时会被
  MIUI 按 MiuiMemoryService(started-services) 杀（adj 800）→ 承载 Service 已照 FCL
  ProcessService 前台化（specialUse）修复并复测通过。
- 4.5：client 模式——生产 joinServer 连入 127.0.0.1:25566，RCON `list` 见玩家
  flutter_mc，优雅停止，退出码可观测。
