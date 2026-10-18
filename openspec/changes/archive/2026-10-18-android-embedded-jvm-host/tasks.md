# Tasks

## 1. Native 层骨架（CMake + JNI 构建面）

- [x] 1.1 新增 `android/app/src/main/cpp/`（`CMakeLists.txt` + JNI 源）并在 `android/app/build.gradle.kts` 接入 `externalNativeBuild`，abiFilters 首期取 `arm64-v8a`；已验证 `flutter build apk --debug` 产出 `lib/arm64-v8a/libmc_jvm_host.so` 与 `lib/arm64-v8a/libandroidnsbypass.so`，APK 装配成功
- [x] 1.2 打通 JNI 通道：Kotlin 侧 `external fun` 声明 + Dart 侧平台通道（MethodChannel），验证真机上一次空调用往返成功（方法名与返回码可观测）；已验证（2026-10-18 真机）：`JvmHost`/`JvmHostChannel` 的 `installJre` / `createJvm` / `runMain` / `stopKeepAlive` 全部往返成功，自检日志可见 `JVM 创建成功（JNI_CreateJavaVM 返回 JNI_OK）`

## 2. JRE 产物安装与进程内 JVM 装载

- [x] 2.1 实现 JRE 解包安装到应用私有目录（零存储权限，判据：spec「产物安装于应用私有目录」），验证无任何存储权限时安装与启动均可完成；已验证（2026-10-18 真机）：JRE 落在 `files/local_server/jre/25`，应用未声明任何存储权限，安装与起服均完成
- [x] 2.2 集成 namespace 绕行件（MIT 的 `androidnsbypass`；BSD-2-Clause 仅覆盖其 `liblinkernsbypass_compat` 头文件），**保留原始版权/许可头与来源说明**，验证应用私有目录下的 `.so` 可被 `dlopen`，失败时给出显式报错而非静默降级；已验证（2026-10-18 真机，MIUI/Android 13）：日志 `逃逸命名空间就绪`，`libjli.so` / `libjvm.so` / `libnet.so` 等 dlopen 成功，失败项逐条打印 `dlopen 失败：...`（无静默降级）
- [x] 2.3 实现 stdout/stderr 重定向到实例日志文件（语义照 FCL `FCLBridge.java:104` 的 `redirectStdio`），验证日志文件随 JVM 输出增长；已验证（2026-10-18 真机）：`stdio 已重定向到日志文件`，`logs/host-console.log` 随输出增长并被 Dart 侧增量 tail
- [x] 2.4 实现**停机结果回传**（原计划照 `jre_launcher.c:184-207` 返回 `JLI_Launch` 结果；改用 `JNI_CreateJavaVM` 后进程内无 OS 退出码可采，退化为原版停机行确认 + 回传 `0`，见 `openspec/progress.md` 16.3），验证上层可观测停机；已验证（2026-10-18 真机）：`停止后状态=ServerState.stopped 退出码=0`
- [x] 2.5 用本地 `fcl-sources/.../jreAssets/app_runtime/java/jre25` 的 `universal.tar.xz` + `bin-arm64.tar.xz` 落到产物位并解包（产物不入库，仅占位）；已验证产物被 APK 装配进 `assets/jre/25/`，且 `git check-ignore` 确认不入库

## 3. 真机跑通 Paper 26.2（承载验收）

- [x] 3.1 真机上以该承载起 JVM：不触发 `execve` 相关 abort、JVM 打印版本，即"无系统 java 也能启动"成立（spec「载体在应用进程内承载 JVM」）；已验证（2026-10-18 真机）：`JVM created; java.version=25.0.5-internal`，进程始终为宿主 pid（未发生 `execve` 顶替）
- [x] 3.2 用该承载起 Paper 26.2（`--nogui`，判据 `server/Main.java:72`），验证日志出现**原版就绪行**（判据 `server/dedicated/DedicatedServer.java:246`），且客户端可连 `127.0.0.1:<端口>`（端口行判据 `DedicatedServer.java:210`）——已达成（2026-10-18 真机：就绪行与端口行到位；MC 客户端连接经自检 client 模式用**生产 joinServer** 连入 127.0.0.1:25566，RCON `list` 回显 `There are 1 of a max of 20 players online: flutter_mc`，见 8.1）
- [x] 3.3 验证退出码经承载层可观测、前台服务保活下退后台不掉线、停服后无残留进程与端口占用——已验证（2026-10-18 真机）：退出码 0 可观测；soak 300s 期间退后台（Settings 盖住）60s 后宿主 pid 存活、25566/25576 仍 LISTEN、前台服务 isForeground=true；停服后保活服务 0 残留、端口 0 残留、宿主存活（exit 拦截生效）

## 4. 承载接口抽取（桌面等价回归）

- [x] 4.1 抽出承载接口 `DedicatedServerCarrier`（启动/停止/状态/日志/退出码），[dedicated_server_process.dart](file:///Users/qshh/Code/flutter_mc/lib/platform/server_host/dedicated_server_process.dart) 成为其桌面子进程实现；已验证既有单测全绿（148 项通过，语义未改）
- [x] 4.2 为接口补契约测试（`test/local_server_carrier_contract_test.dart`，含"超时处置随承载方式"分支：进程外强杀 / 进程内不强杀转失败），已验证 [specs/local-server-host/spec.md](file:///Users/qshh/Code/flutter_mc/openspec/changes/android-embedded-jvm-host/specs/local-server-host/spec.md) 新增场景有测试覆盖

## 5. Android 承载实现与平台分派

- [x] 5.1 新增 Android 进程内承载实现 [android_embedded_jvm_host.dart](file:///Users/qshh/Code/flutter_mc/lib/platform/server_host/android_embedded_jvm_host.dart)（与 4.1 接口同面），日志取自实例日志文件增量 tail，就绪判定仍只认原版就绪行（判据 `DedicatedServer.java:246`）；已验证就绪/绑定失败/端口回显三条判据在契约测试中成立
- [x] 5.2 在 app 装配点（`local_server_host.dart` 的 `_createCarrier`）按平台分派桌面/Android 实现（`packages/` 未动，业务代码不按版本号分支）；已验证桌面路径行为与改动前一致（回归单测全绿）
- [x] 5.3 落实"进程内不强杀"口径：停止超时转报告失败并保留日志与状态（spec「进程内承载的生命周期释放口径」）；已验证该分支有测试且实现中无 `kill` 调用
- [x] 5.4 落实"缺产物→入口置灰+报缺"：缺 arm64 JRE / 主版本不符时拒绝启动并同时报出主版本，验证 [artifact_resolver.dart](file:///Users/qshh/Code/flutter_mc/lib/platform/server_host/artifact_resolver.dart) 的报缺口径在 Android 上生效——已验证（2026-10-18 真机）：① 主版本不符（release 改 JAVA_VERSION=21）→ `可用 JRE 的 Java 主版本为 21，本服务器需要 Java 25 … MUST NOT 以低主版本启动`；② 缺资产（APK 去掉 assets/jre + 删私有目录）→ `缺少 arm64 的 Java 25 运行环境… 期望位置：…/jre/25，来源为构建期资产 jre/25/…`
- [x] 5.5 落实"与桌面共享同一契约面"：配置读写、EULA 门槛、管理服务器/RCON 控制面在 Android 上复用同一批实现（无平台分支改写语义）；已核对仅装配点按平台分派

## 6. 保活、manifest 与产物资产

- [x] 6.1 新增前台服务（`LocalServerKeepAliveService`）与被托管 JVM 生命周期同步（起服即起、停服即停），验证退后台不断线且停服后无空转服务（spec「长期运行以前台服务保活」）——已验证（2026-10-18 真机）：运行中 `dumpsys activity services` 可见 `LocalServerKeepAliveService isForeground=true`；退后台 60s 服务端两口仍 LISTEN；停服后服务 0 残留。实现照 FCL `GameService.kt` 对齐（specialUse 类型 + contentIntent + START_NOT_STICKY）
- [x] 6.2 `AndroidManifest.xml` 按当前 targetSdk 增补前台服务类型与所需权限，验证真机安装后服务可常驻不被回收——已验证（2026-10-18 真机，MIUI/Android 13，targetSdk 36）：`FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_SPECIAL_USE` + `POST_NOTIFICATIONS`，类型 `specialUse`（照 FCL；**不取 dataSync**——Android 15+ 对 dataSync 型前台服务有 6 小时强制超时，长期挂服会被掐停），服务常驻不被回收
- [x] 6.3 声明 arm64 JRE 产物资产并确认 Git 不追踪（仅占位）；已验证 `.gitignore` 规则生效（`git check-ignore`）且 `assets/jre/25/` 随 APK 装配

## 7. 第三方许可与来源登记（受限）

- [x] 7.1 落 MIT（`androidnsbypass`）与 BSD-2（`liblinkernsbypass_compat` 头文件）许可文本与来源说明（`android/app/src/main/cpp/third_party/NOTICE.md`）；已验证逐文件原始版权/许可头完整保留、来源可查（spec「复用宽松许可件须署名」）
- [x] 7.2 引入 GPLv2+CE 件（Oracle 派生的 `jre_launcher.c`）后，许可文本随目录保留并在 [openspec/progress.md](file:///Users/qshh/Code/flutter_mc/openspec/progress.md) 登记"本仓分发因此受 GPL-3.0 约束"的受限项（spec「引入 GPL-3.0 件须落许可并登记受限」）；**后续已解除**：改用 `JNI_CreateJavaVM` 后 `jre_launcher.c` 已删除，native 层现只含 MIT / BSD-2-Clause 件（见 `android/app/src/main/cpp/third_party/NOTICE.md` 第 2 节），受限登记已同步撤销
- [x] 7.3 已验证新增 native 源无无署名抄录（逐文件版权头齐全），且文档未对外声称本仓为宽松许可

## 8. 端到端集成验证（真机）

- [x] 8.1 真机起 Android 内建 Paper 26.2：启动 → 原版就绪行 → 客户端 `127.0.0.1` 连接 → RCON 下发 `stop` → 优雅退出 → 退出码可观测 → 无残留进程与端口（对照 [design.md](file:///Users/qshh/Code/flutter_mc/openspec/changes/android-embedded-jvm-host/design.md) 迁移计划第 5 步）——已验证（2026-10-18 真机，自检 client 模式全程）：`starting → ready(端口=25566) → RCON 鉴权 true → 生产 joinServer 连入（RCON list 见玩家 flutter_mc）→ soak 300s（跨前台/后台）→ RCON stop → stopped 退出码 0 → 保活服务 0 残留、端口 0 残留、宿主 pid 存活`；结果文件 `selftest-result.txt` verdict=`通过：启动→就绪(RCON 可用)→客户端连入→优雅停止(退出码 0)`
- [x] 8.2 验证上层契约零语义改动：配置读写、EULA 门槛、管理服务器/RCON 控制面、世界列表 UI 在 Android 上与桌面一致——已验证（2026-10-18）：① 真机自检走**同一套**上层契约（`InstanceDirectory` 实例布局/properties 写入、`EulaGate`、`DedicatedServerProperties` 读口令/端口、`RconClient` 控制面），输出与桌面同构；② 代码层仅装配点 `_createCarrier` 按平台分派（5.2/5.5 已核），`packages/` 未动；③ 契约测试 `local_server_carrier_contract_test.dart` 两块承载共面断言全绿（158 项通过）；④ 世界列表 UI（`SelectWorldScreen`）为纯 Flutter 层、无平台分支，消费同一 `LocalServerManager`

## Workflow follow-up

- 在 `openspec/progress.md` 登记本 change 的承载口径变化（第 16 项）；原"因引入 GPL-2.0+CE
  件而受限"的登记已随 `jre_launcher.c` 删除而撤销（16.1）。
- `openspec validate android-embedded-jvm-host` 通过后归档；归档前确认第 7 组的许可文本与受限登记已落地（已落地）。
- 真机取证入口：`--dart-define=MC_JVM_SELFTEST=1` → `/jvm-selftest`（与既有 `AUTOJOIN` 同性质的取证路径，非 spike；走生产承载路径）。

## 9. 真机实测后的新增待办（2026-10-18）

> 背景：承载路线已由 `JLI_Launch` 改为 `JNI_CreateJavaVM`（真机实测 `JLI_Launch` 必然
> `execve(<jre>/bin/java)` 顶替应用进程映像）。改后 Paper 26.2 **已在真机完整启动**：
> 管理服务器 `localhost:25586`、RCON `0.0.0.0:25576`、原版就绪行 `Done (18.840s)!` 全部到位。
> 下列为随之暴露的收尾项，登记见 `openspec/progress.md` 16.3。

- [x] 9.1 **生命周期建模修正**：paperclip 在**同一 JVM 内另起 `ServerMain` 线程**跑服务端，
      故 `Main.main` 返回 ≠ 服务端结束（真机实测：main 返回后才打出就绪行）。
      → 就绪/停止的判据必须改为"原版日志行"（就绪 `DedicatedServer.java:246`、
      停机 `MinecraftServer.java:650` 的 `Stopping server`、启动失败 `Main.java:227`）
      而不能用 main 返回值；**已验证**（2026-10-18 真机）：`runMain` 改 unawaited、
      状态只由日志行驱动；自检真机输出 `starting → ready → stopping → stopped`，
      RCON `list` 回显正常、退出码 0；契约测试新增一例锁定"main 返回不判停"。
      （另修一处自检竞态：RCON 监听与就绪行不同时出现，判据 `DedicatedServer.java:245` →
      `:255-258`，自检改为重试连接。）
- [x] 9.2 **拦下被托管 JVM 的 `exit()`**（用户裁决：走"自写 GOT patch"路线，
      **不引入**字节跳动 bytehook）：
      真机实测优雅停服后宿主应用被整个带死（`stopped`/退出码 0 之后打出 atexit 探针，
      随即 `Lost connection to device`）。根因已定位（javap 实证 `paper-26.2.jar` 的
      `DedicatedServer.onServerExit()`）：**服务端自己**显式 `System.exit(abnormalExit ? 70 : 0)`，
      经 HotSpot `vm_exit()` → libc `exit()` 退进程。故保留非守护线程拦不住它。
      处置：在 `mc_jvm_host.c` 里手写 GOT patch——解析 libjvm 的 `PT_DYNAMIC` →
      `DT_RELA`/`DT_JMPREL` → 按符号名 `exit` 命中重定位 → 覆盖槽位指向 `mc_guarded_exit`
      （拦到后永久挂起该线程，既不真退出也不返回 VM 关闭路径）；只改 libjvm 的重定位、
      **不碰 libc**，故宿主自身退出不受影响。
      离线已用等价 Python 解析真 `libjvm.so` 验证：`.rela.plt` 内确有 `exit`（r_offset
      `0x1265f20`）、`DT_PLTREL == DT_RELA`。
      验证：真机停服后宿主应用存活（不再 `Lost connection to device`）
      ——**已验证**（2026-10-18 真机）：日志 `已改写 exit 重定位槽位 0x6f74311f20
      （库内 vaddr 0x1265f20）` → `已拦下 libjvm 的 exit()（1 处重定位）`；停服走完
      `starting → ready → stopping → stopped`、退出码 0 后打出
      `拦下被托管 JVM 的 exit(0)：宿主应用必须存活，永久挂起本线程`；
      随后 `adb shell pidof com.qshh.flutter_mc` 仍返回同一宿主 pid（12237），应用存活。
      （修 GOT patch 期间另踩一坑：Android bionic 内存 `.dynamic` 的 `d_ptr` 未重定位为绝对
      地址，改为解析**磁盘 ELF 文件** + PT_LOAD 换算文件偏移后解决，见 `mc_jvm_host.c`。）
- [x] 9.3 **主类改为从 jar 的 `META-INF/MANIFEST.MF` 读 `Main-Class`**——已落地并验证：
      新增 `lib/platform/server_host/jar_manifest.dart`（最小 ZIP 读取：EOCD → 中央目录 →
      局部头 → 条目数据，只解压 MANIFEST 一个条目；语义照 `java.util.jar.Manifest`：主属性节、
      续行折叠、属性名大小写不敏感）；`AndroidEmbeddedJvmHost.start` 读不到 Main-Class 时
      显式失败（等价 `java -jar` 的 `no main manifest attribute`）。验证：
      ① 单测 9 项（含续行折叠、具名节不干扰、损坏 jar 显式报错）+ 全量 158 项通过；
      ② 真实 paper-26.2.jar（64.5MB）13ms 读出 `io.papermc.paperclip.Main`（与原硬编码一致）；
      ③ 契约测试桩 jar 故意用**另一个**主类 `org.bukkit.craftbukkit.Main`（模拟已打补丁的
      服务端 jar），断言 `runMain` 的 className 跟随清单而非硬编码；
      ④ 真机自检经清单读取后照常起服（就绪行到位）。
- [x] 9.4 在 `design.md` / spec 补记两条**故意偏离与限制**：`-DPaper.IgnoreJavaVersion=true`
      （判据：Paper `org/bukkit/craftbukkit/Main.class` 的官方开关）、一进程一台 VM
      （→ 同一进程内无法二次起服）；已落 [design.md](file:///Users/qshh/Code/flutter_mc/openspec/changes/android-embedded-jvm-host/design.md) 的 `D9`（另含日志行判据、退出码口径、exit 拦截）
- [x] 9.5 OSHI/JNA 在 Android 上加载失败（`libc.so.6` 找不到）为**非致命**（Paper 用
      `ignoreErrors` 包裹，仅硬件信息缺失）——已记入 [design.md](file:///Users/qshh/Code/flutter_mc/openspec/changes/android-embedded-jvm-host/design.md) `D9` 与 `openspec/progress.md` 16.3，不修

