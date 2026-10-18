# native 层第三方来源与许可登记

本目录（`android/app/src/main/cpp/`）的第三方代码来源与许可，按 change
`android-embedded-jvm-host` 的规格「第三方 native 复用须带许可与来源，并登记本仓受限」登记如下。
**引入受 GPL 约束的件意味着本仓分发许可因此受限**（见 `openspec/progress.md`）。

## 1. `third_party/androidnsbypass/` —— MIT（+ BSD-2-Clause）

- **来源**：FoldCraftLauncher（FCL）仓库内 vendored 的 `androidnsbypass` 子模块
  （FCL 的 `CMakeLists.txt` 注明：vendor 自 Amethyst-Android 的 androidnsbypass 子模块 `616dc33`）。
- **许可**（逐文件核对后登记）：
  - **MIT**：`nsbypass.c`、`nsbypass_dlfcn.c`、`android_linker_ns.cpp`、`utils.h`、
    `elf_soname_patcher.c/.h` 等，逐文件头 `SPDX-License-Identifier: MIT` /
    `Copyright (c) 2026 alexytomi`（`nsbypass_dlfcn.c` 自带 2016 年 avs333 的 MIT 式授权文本）。
    MIT 全文见同目录 [`LICENSE`](third_party/androidnsbypass/LICENSE)。
  - **BSD-2-Clause**：`include/liblinkernsbypass_compat/android_linker_ns.h`
    （文件头 `SPDX-License-Identifier: BSD-2-Clause`、`Copyright © 2021 Billy Laws`）。
    全文见同目录
    [`LICENSE-BSD-2-Clause`](third_party/androidnsbypass/LICENSE-BSD-2-Clause)。
  - 注意：`utils.c` 无版权头（首行仅 `Created by tom on 9/1/26.`），
    按目录级 MIT 处理；若日后要收紧，需向上游确认其归属。
- **保留义务**：逐文件原始版权/许可头**原样保留**（本次 vendor 未做任何修改）；两份许可全文随目录保留。
- **用途**：绕过 Android linker namespace 限制，使应用私有目录下的 JRE `.so` 可被 `dlopen`。

## 2. `jre_launcher.c` —— **已移除**（原为 GPLv2 + Classpath exception）

- 历史：曾引入 Oracle 派生的 JVM 启动器源（走 `JLI_Launch`），许可为
  **GPLv2 + Classpath exception**，会使本仓分发受 GPL 约束。
- **现已删除**：真机实测确认 `JLI_Launch` 必然 `execve(<jre>/bin/java)` 把整个应用进程映像
  顶替（`atexit` 探针不触发、crash 缓冲区为空、events 里无 `am_kill`），与"进程内承载"对立。
  承载改为 **`JNI_CreateJavaVM`**（见 `../../cpp/mc_jvm_host.c`），属 JNI 标准 API，
  无第三方许可问题。
- 结论：本仓 native 层现**只含 MIT / BSD-2-Clause 的第三方件**，不再有 GPL 件；
  仓库级 `LICENSE` 仍待确定（见 `openspec/progress.md` 第 16 项）。

## 3. `mc_jvm_host.c` —— 本仓自写

- **来源**：本仓原创（无第三方代码；使用 JNI 标准 API，`jni.h` 随 NDK 提供）。
- **许可**：随本仓。
- **性质**：第三类自由设计「运行时宿主（JVM 托管）」的承载方式实现；语义参照
  FCL 的 `FCLauncher.java:203-250`（env 口径）、`utils.c:129-169`（dlopen / LD_LIBRARY_PATH 回退）、
  `RuntimeUtils.java:94-115`（JRE 解包），已在文件头逐条注明对应位置。
- 进程内 JVM 的创建与主类调用用 `JNI_CreateJavaVM` + `ClassLoader.getSystemClassLoader().loadClass`
  （**不再经 `JLI_Launch`**，原因见第 2 节）。
