# Proposal

## Why

本机托管服务端（`local-server-host`）已在桌面落地并验证成熟，但 Android 是空白。Android 没有
系统 JVM，且 targetSdk ≥ 29 的进程**不能 `execve` 应用可写目录中的文件**——现有"起子进程跑
`java -jar`"的承载方式在 Android 上不存在，连"系统 java"这个前提都没有。

参考 FoldCraftLauncher（FCL）的一手实现（只读副本 `fcl-sources/`）确认了可行的承载路线：
**在应用进程内 `dlopen` 整个 JRE 的 `.so`，再由 native 调 `launchJVM` 拉起 OpenJDK**（不走
`execve`，因此不受该限制），且 **arm64 的 Java 25 产物确实存在**。要在 Android 上继续沿用
"托管原版 Paper 26.2 服务端"这一套既有契约，需要把承载层由"子进程"换成"进程内 JVM"。

## What Changes

- 新增 **Android 进程内 JVM 承载层**：JRE 产物解析与私有目录安装、`dlopen` 装载、native
  `launchJVM` 启动、退出码与输出回传、前台服务保活；Dart 侧沿用桌面已有的实例目录 / 配置
  读写 / EULA / RCON / 就绪判定契约，不改其语义。
- 新增 **Android native 层**（CMake + JNI，本仓 `android/` 目前没有任何 native 代码）：
  JRE 解包安装、`dlopen` 链与 linker namespace 绕行、stdout/stderr 重定向到实例日志文件、
  退出码回调。
- 新增 **前台服务保活**：长时间运行的托管服务端不能被系统回收。
- **产物**：arm64 的 Java 25 JRE 按既有"缺产物→入口置灰、给出补齐途径"口径引入（内置或
  首次下载，取舍见 design）。
- **BREAKING（规格口径）**：`local-server-host` 中「停止可**回落到强制终止**」与「MUST NOT
  残留孤儿进程」两条，在 Android 进程内承载下不成立，需按平台重述；日志与就绪判定的**来源**
  由"子进程 stdout 管道"改为"承载层重定向输出 + 实例日志文件"，判定文本本身不变。
- **许可（受限，已定口径）**：本仓当前**没有任何 LICENSE 文件**。经逐文件核对，参考实现里的
  namespace 绕行件为 **MIT**（`androidnsbypass`，BSD-2-Clause 只覆盖其
  `liblinkernsbypass_compat` 头文件），Oracle 的 JVM 启动器源为 **GPLv2 + Classpath exception**
  ——均可复用，但都**须保留原始版权/许可头并注明来源**。**本 change 允许引入 GPL-3.0 件**；
  代价是本仓**分发许可因此受限**：必须随仓库落对应许可文本，并在 `openspec/progress.md`
  记明"本仓分发因此受 GPL-3.0 约束"。MUST NOT 无署名地复制第三方代码，也 MUST NOT
  声称本仓为宽松许可。

## Capabilities

### New Capabilities

- `android-embedded-jvm-host`: Android 上"在当前应用进程内承载外部 JVM 与被托管 Java 产物"
  的载体契约——JRE 产物与私有目录安装、进程内 JVM 启动与就绪、输出与退出码回传、前后台
  保活、生命周期与释放（含"无孤儿进程"这一在进程内承载下的自然结果）、以及它与桌面承载层
  共享的同一条契约面。

### Modified Capabilities

- `local-server-host`: 「进程生命周期可控可观测」按平台重述——超时处置随承载方式而定（进程内
  MUST NOT 声称可单独强杀），「孤儿进程回收」在该承载下自然成立。日志与就绪判定的**来源**由
  "子进程 stdout 管道"改为"承载层重定向输出 + 实例日志文件"，判定文本与既有要求措辞不变，
  故「就绪判定以原版输出为准」不改。

## Impact

- **app 壳 lib/**：[artifact_resolver.dart](file:///Users/qshh/Code/flutter_mc/lib/platform/server_host/artifact_resolver.dart)
  与 [dedicated_server_process.dart](file:///Users/qshh/Code/flutter_mc/lib/platform/server_host/dedicated_server_process.dart)
  增加平台分派；新增 Android 载体实现（同目录）。
- **android/**：新增 CMake/JNI native 源与 `externalNativeBuild` 构建面；manifest 增补服务与
  权限（前台服务类型、存储）、保活 Service。
- **产物与体积**：arm64 JRE（Java 25）引入策略变化；APK 体积相应变化。
- **规则文档**：`openspec/progress.md` 登记 Android 载体相关的翻译债与**受限制项**（许可口径）。
- **不动**：`packages/` 全部不变（仍为纯 Dart、无 Flutter 依赖）；RCON / 管理服务器 / 配置 /
  EULA / 世界列表 UI / `servers.dat` 口径均不改。
</content>
</invoke>
