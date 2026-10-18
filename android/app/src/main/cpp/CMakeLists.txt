# 宿主承载层 native 构建（第三类自由设计「运行时宿主（JVM 托管）」的承载方式实现）。
#
# 目标：
#   · androidnsbypass —— 第三方件（MIT + BSD-2-Clause，逐文件版权头保留，见
#     third_party/androidnsbypass/LICENSE 与同目录 LICENSE-BSD-2-Clause），
#     用于绕过 Android linker namespace 以 dlopen 应用私有目录下的 JRE 库。
#     来源：Amethyst-Android / FoldCraftLauncher 的 androidnsbypass 子模块。
#   · mc_jvm_host —— 本仓自写桥：env / stdio 重定向 / dlopen 回退 / LD_LIBRARY_PATH / chdir
#     + 进程内 JVM 的创建与主类调用（`JNI_CreateJavaVM`，不用 `JLI_Launch`）。
#     —— 为什么不用 `JLI_Launch`：真机实测它必然 `execve(<jre>/bin/java)` 把整个应用进程映像
#        顶替（无 atexit、无 tombstone、系统未 kill），与"进程内承载"对立；也正因弃用它，
#        本仓不再引入 Oracle 的 GPLv2+CE 启动器源，许可面收窄到 MIT/BSD 的 namespace 绕行件。
#
# 注意：mc_jvm_host **不** 链接 androidnsbypass——改为在需要时 dlopen 它，
# 使其 constructor（会 exit(121) 的失败路径）只在真正起服时运行，而非应用启动时。
cmake_minimum_required(VERSION 3.22.1)

project("mc_jvm_host")

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)

# ── 第三方：androidnsbypass（MIT + BSD-2-Clause） ──────────────────────────────
add_library(
        androidnsbypass
        SHARED
        third_party/androidnsbypass/android_linker_ns.cpp
        third_party/androidnsbypass/elf_soname_patcher.c
        third_party/androidnsbypass/nsbypass.c
        third_party/androidnsbypass/nsbypass_dlfcn.c
        third_party/androidnsbypass/utils.c
)

set_target_properties(
        androidnsbypass
        PROPERTIES
        CXX_STANDARD 17
        CXX_STANDARD_REQUIRED ON
)

target_include_directories(
        androidnsbypass
        PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/third_party/androidnsbypass/include
)

target_link_libraries(
        androidnsbypass
        PRIVATE
        log
        dl
        android
)

# ── 本仓：mc_jvm_host ────────────────────────────────────────────────────────
add_library(
        mc_jvm_host
        SHARED
        mc_jvm_host.c
)

target_link_libraries(
        mc_jvm_host
        PRIVATE
        log
        dl
        android
)
