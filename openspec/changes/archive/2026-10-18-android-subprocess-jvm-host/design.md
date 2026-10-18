# Design

## Context

归档 change `android-embedded-jvm-host` 已在真机跑通"宿主进程内 dlopen JRE →
`JNI_CreateJavaVM` → Paper 26.2 就绪 → RCON 停服"，但其承载单元是**宿主应用进程**：
JNI"一进程一台 VM"使二次起服静默夭折（真机 bug：实例日志第二次分界行后零输出，UI 永卡
「正在启动」），并连带三处退化/偏离——退出码回传 0、`exit()` GOT patch、不可强杀。
spike（`JvmSandboxService` + 自检 `subprocess` 模式）已在真机验证 `:jvm` 专用子进程承载
**两轮起停成立**（pid 4370/4725 均就绪、退净、宿主存活），且 spike 踩出的三个 Android
坑（System.out 不走 fd 1、`/proc/<pid>` 探活不可靠、日志轮询半行残段）已有解法。

约束（`openspec/config.yaml` / `AGENTS.md`）：`packages/` 纯 Dart；承载方式属第三类自由
设计（被托管物照旧是翻译债）；mc-sources 只读；Mojang/JRE 产物不入库。

## Goals / Non-Goals

**Goals:**

- 二次起服成立：每个会话全新 `:jvm` 子进程，上一会话终止后可反复再起（spec 新增场景）。
- 真实退出码回归：承载子进程的 OS 退出码回传上层（撤销"回传 0"）。
- 撤销 `exit()` GOT patch 与"进程内不强杀"：恢复与桌面同构的生命周期语义。
- 孤儿兜底：主进程异常死亡时子进程自杀（watchdog），宿主终止 ⇒ 服务端终止口径保持。
- 上层契约零语义改动：装配点换实现，`DedicatedServerCarrier` 面不变。

**Non-Goals:**

- 不做 AIDL/Binder 通道（启动参数走 Intent extras，控制面仍走 RCON——够用且零新依赖）。
- 不做多实例并行（一次一个 `:jvm` 子进程，与现状一致）。
- 不动 JRE 产物安装链（`AndroidJreInstaller` 原样复用）。
- 不翻译服务端本体（翻译债不变，progress.md 16.x 口径不变）。

## Decisions

### D1 承载单元：`:jvm` 专用子进程，一次会话一个

被托管服务端的 JVM 装进应用专用子进程（manifest `android:process=":jvm"`），会话结束子进程
SIGKILL 自杀（范式出处 FCL `GameMenu.onExit`，`GameMenu.java:967-973`）。每会话全新 VM，
"一进程一台 VM"不再约束第二轮。spike 已真机验证。

**备选否掉**：同 VM 复用（同一进程里再跑一次 main）——真机已证脏 VM 上第二次 main 零输出
（静态状态污染不可控），且原版从未支持；留在宿主进程内（现状）——无法二次起服。

### D2 通道四件套：extras / pidFile / 日志文件 / RCON

| 通道 | 方向 | 内容 | 为什么 |
|---|---|---|---|
| Intent extras | 宿主 → 子进程 | workDir / logPath / pidFile / JRE 路径 / LD_LIBRARY_PATH / vmOptions / mainClass | 启动参数一次性传递，零新依赖 |
| pidFile | 子进程 → 宿主 | pid 上报 + **判死信号**（child 自杀前删除） | spike 实测 `System.out` 被 ART 换成 logcat 流不走 fd 1，`/proc/<pid>` 探活对活进程误报不存在——pidFile 是唯一可靠判死依据 |
| 日志文件 | 子进程 → 宿主 | stdout/stderr 重定向（现有 `nativeRedirectStdio`）+ Dart 增量 tail（现有 `_drainLog`，含半行残段） | 与归档 change 同口径，判定文本不变 |
| RCON | 宿主 → 服务端 | 停止 / 控制面（现有 `RconClient`） | 控制面只走原版通道（spec 不变） |

### D3 判死与轮次隔离

child 哨兵线程只扫**本会话**日志段：命中原版停机行（判据 `MinecraftServer.java:650`
`Stopping server`）→ 留存盘窗口（实测全量存盘 ~2s，取 10s）→ **先删 pidFile 再 SIGKILL
自杀**。parent：等 pidFile 消失判死（+2s 给 SIGKILL 收尾）；开新会话前 MUST 等 pidFile
消失（否则 `startService` 会重入未死的旧 `:jvm` 进程——spike 实测踩到）。

### D4 watchdog：主进程异常死亡 → 子进程自杀

Android service 子进程的父进程是 zygote（`getppid` 探不到主进程死亡），force stop 由系统
全杀。唯一漏洞是主进程 crash → child 孤儿。兜底：主进程周期性心跳（写心跳文件，5s 间隔），
child 心跳超时（30s 无更新）自杀。覆盖 spec「宿主终止不留残余」的全部路径。

**备选否掉**：`Inotify` 监听主进程 death fd / binder 链接监听——复杂度不成比例，心跳文件
与现有通道同构。

### D5 真实退出码：结果文件回传

`runMain` 返回后 child 把 `{mainExitCode, stopConfirmed}` 写结果文件，parent 在 pidFile
消失后读取。优雅停止 = 原版停机行出现后 main 返回 0；异常退出（启动失败判据
`Main.java:227` / crash）取实际非 0 值。`DedicatedServerCarrier.exitCode` 语义恢复"真实值"。

### D6 强杀恢复：native `nativeKill`

Dart/Java 无法可靠对其他 pid 发 SIGKILL（`Process.killProcess` 只承诺自己）。`mc_jvm_host.c`
新增 `nativeKill(pid)`（`kill(pid, SIGKILL)`；同 uid 由内核放行）。停止超时路径：
RCON `stop` → 等 pidFile 消失 → 超时则 `nativeKill(childPid)`。

### D7 exit() GOT patch 撤销

`nativeCreateJvm` 的自动 patch 改为开关（sandbox 承载不装——child 死就死；桌面/其他路径
不受影响）。宿主进程从此不再改写 libjvm 重定位，progress.md 16.3 的"宿主存活机制"偏离
随之撤销。

### D8 装配点：`AndroidEmbeddedJvmHost` → `AndroidSubprocessJvmHost`

`DedicatedServerCarrier` 接口不动。Android 实现整体替换：
`start` = 产物解析（`AndroidJreInstaller` 原样）→ `computeSandboxParams` 转正 → startService
→ 状态由日志行驱动（就绪 `DedicatedServer.java:246` / 停机 `MinecraftServer.java:650` /
启动失败 `Main.java:227`，判据与桌面完全一致）；`stop` = RCON + D6；`reap` = 强杀 child。
`AndroidEmbeddedJvmHost` 的进程内承载路径删除（其 jar 清单主类解析 `jar_manifest.dart`、
日志 tail、判据正则全部复用）；契约测试改为两承载（桌面子进程 / Android :jvm 子进程）共面。

### D9 保活不变：宿主前台服务 + `:jvm` started service

`LocalServerKeepAliveService`（specialUse）语义不变（spec「长期运行以前台服务保活」措辞
不改）；承载子进程含 started service 组件，重要性由系统保障；真机验证退后台不断线时一并
复核子进程是否需要独立前台化（spike 未暴露问题，留观察项）。

## Risks / Trade-offs

- [MIUI 厂商管控] 后台 service 进程可能被激进回收 → 与桌面同级风险，前台服务 +
  START_NOT_STICKY（宿主被杀时 child 同死，重开反而留空转）；真机验证退后台场景。
- [watchdog 兜底时延] 主进程 crash 后 child 最迟 ~30s 自杀 → 孤儿窗口可接受（端口会被
  新会话前置检查拦截并提示）。
- [退出码经文件] child 崩溃于写文件前则无退出码 → 该路径本就是异常路径，parent 以
  "pidFile 消失且无结果文件" 判为异常退出（exitCode 取 -1），日志保留可观测。
- [两次进程创建开销] 每会话多一次 zygote fork + 链重放（实测 ~1.5s）→ 相对 40s 起服
  可忽略。
- [自检 harness 演进] 自检 `subprocess` 模式转正后与 `full`（进程内）并存会造成双承载
  分叉 → 随 D8 删除进程内路径，`full` 模式自动落在新承载上。

## Migration Plan

1. native：`nativeCreateJvm` 加 patch 开关 + 新增 `nativeKill`。
2. Kotlin：`JvmSandboxService` 转正（心跳 watchdog、结果文件、pidFile 生命周期、哨兵）。
3. Dart：`AndroidSubprocessJvmHost` 实现承载接口；装配点切换；删进程内路径；契约测试更新。
4. 真机：两轮起停（含客户端连入）→ 退后台 → 主进程 kill ⇒ child 自杀 → 退出码可区分。
5. 文档：progress.md 登记三处退化/偏离撤销；归档。

回滚：装配点单点切换，保留提交粒度可整体 revert。

## Open Questions

- `:jvm` 子进程在厂商 ROM 长时间后台的存活率——真机验证项，不在规格层定案。
