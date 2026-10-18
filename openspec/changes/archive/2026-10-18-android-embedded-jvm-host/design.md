# Design

## Context

本机托管服务端（`local-server-host`）的**上层契约**已经成熟且平台无关：实例目录 / 配置读写 /
EULA / 就绪判定 / 管理服务器与 RCON 控制面都在 [lib/platform/server_host/](file:///Users/qshh/Code/flutter_mc/lib/platform/server_host)
下，只有两个文件与平台绑定——

- [artifact_resolver.dart](file:///Users/qshh/Code/flutter_mc/lib/platform/server_host/artifact_resolver.dart)
  ：`JAVA_HOME` / `which java` / `java -version`。
- [dedicated_server_process.dart](file:///Users/qshh/Code/flutter_mc/lib/platform/server_host/dedicated_server_process.dart)
  ：`Process.start(...)` + stdout 管道 + `kill`。

这两个文件的"java 可执行文件 + 子进程"假设在 Android 上不成立：Android 无系统 JVM，且
targetSdk ≥ 29 的进程不能 `execve` 应用可写目录中的文件（W^X）。因此本 change 只换**承载
方式**（第三类自由设计），不碰上层契约。动机与范围见 [proposal.md](file:///Users/qshh/Code/flutter_mc/openspec/changes/android-embedded-jvm-host/proposal.md)——
Why / What Changes。

约束（来自 `openspec/config.yaml` 与 `AGENTS.md`）：`packages/` 全纯 Dart；版本特定代码只在
`mc_protocol_v<主>_<次>` 包；`mc-sources/` 只读不入库、代码不得引用；Mojang 官方资产不入库。

## Goals / Non-Goals

**Goals:**

- 在 Android 上以**进程内 JVM**承载被托管服务端，跑通"启动 → 原版就绪行 → 连接 → 优雅停止 →
  退出码可观测"整条链路，且上层契约零语义改动。
- 承载层以**接口**形式与桌面并列，装配点按平台选实现——不改 `packages/`。
- 引入的第三方 native 代码**有据可依**（保留版权/许可头 + 来源说明），引入受限许可件时
  **登记本仓分发受限**。

**Non-Goals:**

- 不在 Android 上支持"多个被托管服务端同时运行"（进程内一个 VM 为一个实例服务；多实例留作后续）。
- 不翻译服务端本体（仍是翻译债，登记在 `openspec/progress.md`）。
- 不做 Android 端的 AWT / 图形栈（服务端为 headless：`--nogui`，不涉 FCL 的 SDL/EGL 渲染面）。
- 不在本 change 内定案许可文件（列为受限待做）。

## Decisions

### D1 承载路线：进程内 `dlopen` 整个 JRE，而非 `execve`

`execve` 应用可写目录中的文件在 targetSdk ≥ 29 被禁，`Process.start` 无路可走；改用动态加载
装载 JRE 的 `.so`，再由 native 进入 JVM 启动入口，全程不 `execve`。这是一手证据支撑的路线
（只读参考副本 `fcl-sources/`）：

| 环节 | 参考实现证据（承载方式，非原版判据） |
|---|---|
| Java 侧入口声明 | `FCL/src/main/java/com/oracle/dalvik/VMLauncher.java:6`（`native int launchJVM(String[])`） |
| native 装载 JRE 并入 JVM | `FCL/src/main/jni/jre_launcher.c:123-176`（`dlopen("libjli.so")` → `dlsym` → `JLI_Launch`） |
| JNI 入口与退出码 | `FCL/src/main/jni/jre_launcher.c:184-207`（返回 `JLI_Launch` 的 `jint` 即退出码） |
| stdout/stderr 重定向 | `FCL/src/main/java/com/tungsten/fclauncher/bridge/FCLBridge.java:104`（`native int redirectStdio(String)`，用于 `:155-158`） |
| 退出码回调到上层 | `FCL/src/main/java/com/tungsten/fclauncher/bridge/FCLBridge.java:243-246`（`onExit(int code)`） |

**实施修正（2026-10-18 真机实测）**：上表第 2/3 行的 `JLI_Launch` 路线**已废弃**——真机实测
`JLI_Launch` 内部必然 `execve(<jre>/bin/java)` 顶替整个应用进程映像（`atexit` 探针不触发、
crash 缓冲区为空、events 无 `am_kill`），与"进程内承载"直接对立。现路线为：
`dlopen(libjli.so)` 取 `JNI_CreateJavaVM` → 建 VM → `ClassLoader.getSystemClassLoader()
.loadClass(<Main-Class>)` → `CallStaticVoidMethod(main)`。承载语义（environment 口径、
`LD_LIBRARY_PATH`、stdio 重定向）仍照参考实现；退出码语义的变化见 D9。

**备选否掉**：① 走 `Runtime.exec`/`ProcessBuilder` 跑 `java`——同一 W^X 限制，且 Android 无
java 可执行文件；② 把 JRE 装到"可执行白名单"路径（如 `/data/local/tmp`）——非本应用私有目录、
需 root/壳外步骤，违反"运行根为应用私有目录"规格。

### D2 产物策略：复用桌面既有"缺产物→置灰+补齐途径"口径

arm64 的 Java 25 JRE 产物确实存在（`fcl-sources/.../jreAssets/app_runtime/java/jre25/bin-arm64.tar.xz`，
一手证据），但体积可观（FCL 的 `jreAssets` 合计 ≈154M）。**决策**：沿用桌面 jar 的同一口径
——产物按"应用私有目录 artifacts + 构建期资产携带、Git 不追踪、缺失时入口置灰并给出补齐途径"
处理（桌面侧已落地于 [artifact_resolver.dart](file:///Users/qshh/Code/flutter_mc/lib/platform/server_host/artifact_resolver.dart#L112-L175)）。
首期把 arm64 JRE 作为**构建期资产**（`.tar.xz` 解包），APK 体积代价在风险节说明；"首次运行下载"
作为可选补齐途径，不进首期硬路径。

**备选否掉**：默认捆绑所有 ABI（arm/x86/x86_64）——APK 体积倍增，且绝大多数真机为 arm64。

### D3 linker namespace：复用宽松许可的实现件（MIT + BSD-2）

Android 从 API 24 起对应用 `dlopen` 私有目录 `/data/data/.../` 下的 `.so` 有命名空间限制
（"library is not accessible for the namespace"）。参考实现的这一层**并非 GPL-3.0**：
`FCL/src/main/jni/androidnsbypass/` 为 **MIT**（`nsbypass.c:1` 的 `SPDX-License-Identifier: MIT`、
同目录 `LICENSE`），其中 **BSD-2-Clause 只覆盖**
`include/liblinkernsbypass_compat/android_linker_ns.h`（`Copyright © 2021 Billy Laws`）。
**决策**：直接复用，保留原始版权/许可头与来源说明（见 D8），使最高风险项由"自研 1700 行"
降为"集成 + 适配"。
注意其注释已点名 **MIUI 存在 `--X` 映射**的设备差异（`nsbypass.c:118-120`、`:132`），故首期在
MIUI/Android 13 真机上直接验证，失败即显式报错而非静默降级。

### D4 日志与就绪判定的**来源**改变，**判据文本**不变

桌面：`Process.stdout/stderr` 管道 → 由 Dart 逐行解析就绪行。Android 进程内：无独立子进程
stdout，改为 native 侧 `dup2` 把 fd 1/2 重定向到实例日志文件（参考实现 `FCLBridge.java:104`），
Dart 侧改为**增量 tail 实例日志文件**。就绪判定仍是**原版就绪行**：

- 就绪行判据 `server/dedicated/DedicatedServer.java:246`（`Done ({})! For help, type "help"`）
- 监听端口判据 `server/dedicated/DedicatedServer.java:210`
- 绑定失败判据 `server/dedicated/DedicatedServer.java:215`
- `--nogui` 选项判据 `server/Main.java:72`；EULA 判据 `server/Eula.java:27`、`:43-44`、
  `server/Main.java:113-121`

因此「就绪判定以原版输出为准」这条规格**不必修改**（措辞与前三条判据均不变），只需改日志**来源**。

### D5 上层契约以**接口**并列两套承载，装配点选实现

不合并、不 if 分支散落业务代码：抽出承载接口（启动 / 停止 / 状态 / 日志 / 退出码），
[dedicated_server_process.dart](file:///Users/qshh/Code/flutter_mc/lib/platform/server_host/dedicated_server_process.dart)
为桌面子进程实现，Android 进程内实现为同目录新文件；由 app 装配点按平台选择。`packages/` 不动。
（同类先例：`artifact_resolver` 已用**可注入探针**隔离平台差异，见 `:39-51`。）

### D6 保活：前台服务与被托管 JVM 生命周期同步

Android 长时间运行需前台服务维持宿主进程存活（参考实现 `FCL/src/main/AndroidManifest.xml:137-156`
的多个前台服务声明；`GameService.kt` 为游戏进程保活的服务本体）。**决策**：起服即起前台服务、
停服即停服务，避免仅用于保活的空转服务（spec「长期运行以前台服务保活」）。

**前台服务类型（2026-10-18 定案，照 FCL `GameService.kt:41-47`）**：取 **`specialUse`**
（manifest 附 `PROPERTY_SPECIAL_USE_FGS_SUBTYPE` 注明用途），**不取 `dataSync`**——
Android 15+ 对 dataSync 型前台服务有 **6 小时强制超时**，长期运行的被托管服务端会被系统
掐停；specialUse 无此限制，且与 FCL"保游戏进程活"是同类场景。API < 34 不识别该类型，
`startForeground` 按版本传 `FOREGROUND_SERVICE_TYPE_SPECIAL_USE` / `0`（旧系统不校验）。
权限：`FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_SPECIAL_USE`（+ 可选 `POST_NOTIFICATIONS`）。
另与 FCL 一致的两点：通知带 `contentIntent`（点通知回应用）、`START_NOT_STICKY`（宿主被杀
时服务端一并终止，重启服务只会留下空转服务）。**有意偏离**：FCL 的 `ProcessService` 跑在
`:jvm` 独立进程——那是因为它的游戏进程与启动器分离；我们的被托管 JVM 与宿主同进程，
为满足「宿主进程终止 ⇒ 服务端一并终止」MUST NOT 另开进程。

（实现差异说明：FCL 经 `ServiceCompat.startForeground` 传类型；本仓不引 androidx.core，
按 API 版本直接调 `startForeground` 三参/两参重载，语义等价。）

### D7 生命周期与"强杀"：进程内承载不声称可单独强杀

进程内 JVM 与宿主同进程，无法只对它发信号。停止超时不再回落强杀，转为报告失败并保留日志
（spec「进程内承载的生命周期释放口径」）；「MUST NOT 残留孤儿进程」在进程内承载下**自然
成立**（宿主进程终止即终止服务端）。这是对 `local-server-host` 中「进程生命周期可控可观测」
的**平台重述**（见 delta 规格）。

### D8 许可口径：允许引入受限许可件，并登记本仓分发受限

本仓无 LICENSE 文件。参考实现的分层许可已核实：`androidnsbypass` **MIT**、
`elf_soname_patcher` **BSD-2-Clause**、Oracle 的 JVM 启动器源 **GPLv2 + Classpath exception**
（`FCL/src/main/jni/jre_launcher.c:1-24` 的头即是许可文本本身）。**决策（用户定口径）**：
**允许引入 GPL-3.0 / GPLv2+CE 件**，代价是本仓**分发许可因此受限**——MUST 保留原始版权/许可头、
记明出处与许可证名、随仓库落对应许可文本，并在 `openspec/progress.md` 登记"本仓分发因此受
GPL-3.0 约束"；MUST NOT 声称本仓为宽松许可。此为**受限项**，见 tasks 第 7 组。

**事后更正（2026-10-18）**：改用 `JNI_CreateJavaVM` 后 `jre_launcher.c` **已删除**，该 GPL 件
从未随本仓分发；native 层现只含 MIT / BSD-2-Clause 件（`third_party/NOTICE.md` 第 2 节），
"本仓分发许可受限"的登记随之撤销。仓库级 `LICENSE` 仍待确定（见 `openspec/progress.md` 16.1）。

### D9 宿主侧故意偏离与已知限制（2026-10-18 真机实测后补记）

- **故意偏离：`-DPaper.IgnoreJavaVersion=true`**——被托管服务端的 `org/bukkit/craftbukkit/Main.class`
  读取 `java.version` 并要求 GA 版本；Android 上不存在 GA 版 OpenJDK（arm64 JRE 自建，VM 自报
  `25.0.5-internal`）。处置用**被托管物自己提供的官方开关**（同一判据文件内即有该属性与
  "the check was skipped. Proceed with caution!" 文案）；不走伪造路线（实测 `-Djava.version=`
  被 HotSpot 忽略，该属性是 VM 内建只读属性）。后果：Paper 的该门禁被跳过。
- **已知限制：一进程一台 VM**（JNI 约束，`DestroyJavaVM` 后不可重建）→ 同一应用进程内
  **无法二次起服**，停服后须重启应用才能再起。
- **生命周期判据全部取自原版日志行**：原版 `Main.main` 经 `MinecraftServer.spin` 另起
  "Server thread" 后即刻返回（`Main.java:201-217` / `MinecraftServer.java:307`），故就绪/停机/
  启动失败分别认 `DedicatedServer.java:246` / `MinecraftServer.java:650`（`Stopping server`）/
  `Main.java:227`（`Failed to start the minecraft server`），**不用** `main` 返回值。
- **进程内拿不到真实退出码** ⇒ 优雅停机以原版停机行确认、`exitCode` 回传 `0`（等价值）；
  JVM 随宿主进程存亡，不会单独退出，无 OS 退出码可采。
- **宿主存活机制：拦下被托管 JVM 的 `exit()`**——被托管服务端自己显式
  `System.exit(abnormalExit ? 70 : 0)`（javap 实证 `paper-26.2.jar` 的
  `DedicatedServer.onServerExit()`），经 HotSpot `vm_exit()` → libc `exit()` 退掉整个进程；
  子进程承载下无妨，进程内承载下等于杀死宿主。处置：在 **libjvm.so 的 GOT** 上按符号名命中
  `exit` 重定位、覆盖为 `mc_guarded_exit`（拦到后永久挂起该线程）；只改 libjvm、不碰 libc，
  也不引入第三方 hook 库。代价：停服后 JVM 存活但空闲，配合"一进程一台 VM"仍无法二次起服。
- **已知非致命：OSHI/JNA 加载失败**（Android 上找不到 `libc.so.6`）——Paper 用 `ignoreErrors`
  包裹，仅"硬件信息"缺失（TPS/CPU/内存上报），不影响起服。登记即可，**不修**。
- **主类取自 jar 清单（2026-10-18 已落地，原"待办"撤销）**：`AndroidEmbeddedJvmHost` 从
  被托管 jar 的 `META-INF/MANIFEST.MF` 读 `Main-Class`（真 `java -jar` 同口径；实现见
  `jar_manifest.dart`），读不到时显式失败（等价 `no main manifest attribute`）。换任何
  主类相符的 jar（含已打补丁的服务端 jar）均无需改宿主代码。

## Risks / Trade-offs

- [APK 体积] 内置 arm64 Java 25 JRE → 体积上升 → 首期只带 arm64；改"首次下载"作为后续优化，
  与"缺产物→置灰+补齐途径"口径一致。
- [linker namespace 绕行脆弱] 不同 Android 版本/厂商对私有目录 `dlopen` 的口径有差异（源码已
  点名 MIUI）→ 先在手头一台真机跑通 `dlopen` + 就绪行为准，再铺上层；绕行失败做成显式报错
  而非静默降级。
- [设备 ABI 覆盖] 仅 arm64 → 非 arm64 设备入口置灰并给出补齐途径（spec 已要求）。
- [前台服务类型] Android 14+ 对前台服务类型有额外要求（参考实现 `libs.versions.toml` 目标 SDK
  偏低）→ manifest 按当前 SDK 声明合适类型，真机验证常驻不被回收。
- [JVM 线程与 Dart isolate] 进程内 VM 与 Flutter 主线程/isolate 的交互 → 启动与退出回调经
  native 侧线程切换到平台通道，避免阻塞 UI isolate。

## Migration Plan

1. Native 层骨架（CMake/JNI + `externalNativeBuild`），先打通 JNI 通道。
2. JRE 解包安装 + namespace 绕行集成（复用 MIT/BSD 件）+ stdio 重定向 + 退出码回传。
3. 真机跑通：起 JVM → 起 Paper 26.2 → 原版就绪行 → 客户端连接 → 停服无残留。
4. 抽承载接口 → 桌面实现保持等价（回归既有 138 项单测）→ Android 承载实现接入；装配点分派。
5. manifest / 前台服务 / 产物资产声明；许可文本与来源登记。
6. 端到端复核上层契约零语义改动。

回滚：承载接口并存，Android 实现未就绪时该平台入口置灰（不破坏桌面路径）。

## Open Questions

- ~~首期产物形态（构建期 `.tar.xz` 资产 vs 首次运行下载）~~——已按构建期资产落地（真机验证
  安装/报缺两条路径）；"首次下载"留作后续优化。
- ~~前台服务类型的具体取值~~——已定案 `specialUse`（照 FCL，见 D6；Android 15+ 的 dataSync
  6 小时超时排除了 dataSync），真机常驻验证通过。
