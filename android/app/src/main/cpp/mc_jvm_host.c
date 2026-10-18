/*
 * 宿主承载层桥（第三类自由设计「运行时宿主（JVM 托管）」的承载方式实现，本仓自写）。
 *
 * 本文件只做"承载方式"该做的事，全部无原版对应物（原版 `server/Main.java` 假定 JVM 已存在）：
 *   · setenv            —— 把 JVM 运行所需的进程环境写入（HOME / JAVA_HOME / PATH /
 *                          LD_LIBRARY_PATH / TMPDIR），口径照参考实现 FCLauncher.addCommonEnv
 *                          （`FCLauncher.java:203-250`）。
 *   · redirectStdio     —— 把 fd 1/2 重定向到实例日志文件，使被托管 JVM 的 stdout/stderr
 *                          落到日志（语义照参考实现 `FCLBridge.java:104` 的 redirectStdio，
 *                          但那是重定向到 pipe + Java 回调；本仓直接落文件，见 design D4）。
 *   · dlopen（带回退）  —— 先常规 dlopen；失败再走 androidnsbypass 的逃逸命名空间
 *                          （语义照参考实现 `utils.c:146-169`）。
 *   · setLdLibraryPath  —— 调 linker 的 private API 更新 LD_LIBRARY_PATH（照 `utils.c:129-144`），
 *                          否则 libjli/libjvm 之间的 NEEDED 解析不到 JRE 内部库。
 *   · chdir             —— 切到实例工作目录（原版服务端的工作目录即它的 "."）。
 *
 * 许可：无第三方代码，纯自写；运行时 dlopen 的 `libandroidnsbypass.so` 为 MIT + BSD-2-Clause
 * （见 third_party/NOTICE.md）。**不 execve**（Android targetSdk >= 29 禁 execve 应用可写目录）。
 */

#include <android/dlext.h>
#include <android/log.h>
#include <dlfcn.h>
#include <elf.h>
#include <errno.h>
#include <fcntl.h>
#include <jni.h>
#include <link.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <signal.h>
#include <unistd.h>

#define TAG "mc_jvm_host"
#define HOST_LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define HOST_LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

// ⚠ JNI 符号名规则：包名 `com.qshh.flutter_mc` 里的 `_` 在 JNI 中须转义为 `_1`，
// 故符号前缀是 `Java_com_qshh_flutter_1mc_`（不是 `..._flutter_mc_`）。写错会在运行期报
// "No implementation found for ..."（真机已踩过一次）。改包名 / 加方法时务必同步这里。

// ── 诊断探针：区分"exit() 干净退出"与"进程映像被 execve 顶替" ────────────────
// 被托管 JVM 启动后进程无输出地消失（无 crash tombstone、`JLI_Launch` 也不返回）时，
// 只有两种可能：JVM 内部调 `exit()`，或进程被 `execve` 换成了别的程序。后者**不会**触发
// `atexit`，故用一条 atexit 日志即可判别。
static void on_process_exit_probe(void) {
    HOST_LOGI("探针：进程经 exit() 退出（atexit 被触发）——非 execve 顶替");
}

__attribute__((constructor)) static void install_exit_probe(void) {
    atexit(on_process_exit_probe);
}

// ── androidnsbypass 的私有符号（懒装载，见下） ────────────────────────────────
// 不在构建期链接它：其 constructor 在解析失败时会 exit(121)，故只在**真正起服时**才 dlopen，
// 让这条失败路径不发生在应用启动阶段（design D3 的"显式报错而非静默降级"）。
struct android_namespace_t;

typedef struct android_namespace_t *(*get_escape_namespace_t)(void);
typedef void *(*linker_ns_dlopen_t)(const char *, int, struct android_namespace_t *);

static int g_ns_state = 0; // 0=未装载 1=可用 -1=不可用
static struct android_namespace_t *g_escape_ns = NULL;
static linker_ns_dlopen_t p_linker_ns_dlopen = NULL;

static bool ensure_escape_namespace(void) {
    if (g_ns_state == 1) return true;
    if (g_ns_state == -1) return false;
    g_ns_state = -1; // 先置失败态，成功后翻回

    void *handle = dlopen("libandroidnsbypass.so", RTLD_NOW | RTLD_GLOBAL);
    if (handle == NULL) {
        HOST_LOGE("装载 libandroidnsbypass.so 失败：%s", dlerror());
        return false;
    }
    get_escape_namespace_t p_get =
            (get_escape_namespace_t) dlsym(handle, "get_escape_namespace");
    p_linker_ns_dlopen = (linker_ns_dlopen_t) dlsym(handle, "linker_ns_dlopen");
    if (p_get == NULL || p_linker_ns_dlopen == NULL) {
        HOST_LOGE("libandroidnsbypass.so 缺少符号（get_escape_namespace / linker_ns_dlopen）");
        return false;
    }
    g_escape_ns = p_get();
    if (g_escape_ns == NULL) {
        HOST_LOGE("逃逸命名空间创建失败（该设备 linker 私有 API 不可用）");
        return false;
    }
    g_ns_state = 1;
    HOST_LOGI("逃逸命名空间就绪");
    return true;
}

/** 逃逸命名空间是否可用（供 Dart 侧在起服前判"缺产物/不可用"口径）。 */
JNIEXPORT jboolean JNICALL
Java_com_qshh_flutter_1mc_JvmHost_nativeEscapeNamespaceReady(JNIEnv *env, jclass clazz) {
    return ensure_escape_namespace() ? JNI_TRUE : JNI_FALSE;
}

/** 写进程环境（口径照参考实现 FCLauncher.addCommonEnv）。 */
JNIEXPORT void JNICALL
Java_com_qshh_flutter_1mc_JvmHost_nativeSetEnv(JNIEnv *env, jclass clazz, jstring jname,
                                              jstring jvalue) {
    const char *name = (*env)->GetStringUTFChars(env, jname, NULL);
    const char *value = (*env)->GetStringUTFChars(env, jvalue, NULL);
    if (setenv(name, value, 1) != 0) {
        HOST_LOGE("setenv(%s) 失败：%s", name, strerror(errno));
    } else {
        HOST_LOGI("Env: %s=%s", name, value);
    }
    (*env)->ReleaseStringUTFChars(env, jname, name);
    (*env)->ReleaseStringUTFChars(env, jvalue, value);
}

/**
 * 把 stdout/stderr 重定向到日志文件（追加写）。
 *
 * 语义照参考实现 `FCLBridge.java:104` 的 redirectStdio：行缓冲 stdout、无缓冲 stderr，
 * 再把 fd 1/2 换成目标。区别仅在于目标是**文件**而非 pipe（design D4）。
 * 返回 0 成功；非 0 为错误码。
 */
JNIEXPORT jint JNICALL
Java_com_qshh_flutter_1mc_JvmHost_nativeRedirectStdio(JNIEnv *env, jclass clazz, jstring jpath) {
    setvbuf(stdout, NULL, _IOLBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);

    const char *path = (*env)->GetStringUTFChars(env, jpath, NULL);
    // O_CREAT|O_WRONLY|O_APPEND：多次起服追加到同一日志，与桌面侧 host-console.log 同口径
    int fd = open(path, O_CREAT | O_WRONLY | O_APPEND, 0644);
    (*env)->ReleaseStringUTFChars(env, jpath, path);
    if (fd < 0) {
        HOST_LOGE("打开日志文件失败：%s", strerror(errno));
        return 1;
    }
    if (dup2(fd, STDOUT_FILENO) != STDOUT_FILENO ||
        dup2(fd, STDERR_FILENO) != STDERR_FILENO) {
        HOST_LOGE("重定向 stdio 失败：%s", strerror(errno));
        close(fd);
        return 2;
    }
    if (fd != STDOUT_FILENO && fd != STDERR_FILENO) close(fd);
    HOST_LOGI("stdio 已重定向到日志文件");
    return 0;
}

/**
 * dlopen（实现私有目录下的 JRE 库），失败回退到逃逸命名空间。
 * 语义照参考实现 `utils.c:146-169`。返回 handle（0 表示失败）。
 */
JNIEXPORT jlong JNICALL
Java_com_qshh_flutter_1mc_JvmHost_nativeDlopen(JNIEnv *env, jclass clazz, jstring jname) {
    const char *name = (*env)->GetStringUTFChars(env, jname, NULL);

    dlerror();
    void *handle = dlopen(name, RTLD_GLOBAL | RTLD_LAZY);
    if (handle == NULL) {
        const char *first_error = dlerror();
        if (ensure_escape_namespace()) {
            dlerror();
            handle = p_linker_ns_dlopen(name, RTLD_GLOBAL | RTLD_LAZY, g_escape_ns);
            if (handle != NULL) {
                HOST_LOGI("dlopen（逃逸命名空间）成功：%s", name);
            } else {
                HOST_LOGE("dlopen 失败：%s（常规：%s / 逃逸：%s）", name,
                          first_error == NULL ? "?" : first_error,
                          dlerror() == NULL ? "?" : dlerror());
            }
        } else {
            HOST_LOGE("dlopen 失败且逃逸命名空间不可用：%s（%s）", name,
                      first_error == NULL ? "?" : first_error);
        }
    } else {
        HOST_LOGI("dlopen 成功：%s", name);
    }

    (*env)->ReleaseStringUTFChars(env, jname, name);
    return (jlong) handle;
}

/**
 * 更新 linker 的 LD_LIBRARY_PATH（JRE 内部库之间的 NEEDED 靠它解析）。
 * 照参考实现 `utils.c:129-144`：优先 `android_update_LD_LIBRARY_PATH`，
 * 回退 `__loader_android_update_LD_LIBRARY_PATH`。
 */
JNIEXPORT void JNICALL
Java_com_qshh_flutter_1mc_JvmHost_nativeSetLdLibraryPath(JNIEnv *env, jclass clazz,
                                                        jstring jpath) {
    void *libdl = dlopen("libdl.so", RTLD_LAZY);
    void *fn = libdl == NULL ? NULL : dlsym(libdl, "android_update_LD_LIBRARY_PATH");
    if (fn == NULL && libdl != NULL) {
        fn = dlsym(libdl, "__loader_android_update_LD_LIBRARY_PATH");
    }
    if (fn == NULL) {
        HOST_LOGE("找不到 android_update_LD_LIBRARY_PATH，JRE 库解析可能失败");
        return;
    }
    const char *path = (*env)->GetStringUTFChars(env, jpath, NULL);
    ((void (*)(const char *)) fn)(path);
    HOST_LOGI("LD_LIBRARY_PATH 已更新：%s", path);
    (*env)->ReleaseStringUTFChars(env, jpath, path);
}

/** 切工作目录（原版服务端的工作目录即它的 "."）。返回 0 成功。 */
JNIEXPORT jint JNICALL
Java_com_qshh_flutter_1mc_JvmHost_nativeChdir(JNIEnv *env, jclass clazz, jstring jpath) {
    const char *path = (*env)->GetStringUTFChars(env, jpath, NULL);
    int result = chdir(path);
    if (result != 0) {
        HOST_LOGE("chdir(%s) 失败：%s", path, strerror(errno));
    } else {
        HOST_LOGI("工作目录已切换到 %s", path);
    }
    (*env)->ReleaseStringUTFChars(env, jpath, path);
    return (jint) result;
}

// ── 进程内 JVM：创建与主类调用（承载方式，替代 `JLI_Launch`） ─────────────────
//
// 为什么不用 `JLI_Launch`（真机实测结论，非推测）：只要经它，进程映像必被
// `execve(<jre>/bin/java)` 顶替——`atexit` 探针不触发（不是 exit()）、crash 缓冲区为空
// （不是崩溃）、events 里无 `am_kill`（系统没杀它）。这与"进程内承载"根本对立。
// 改用 JNI 的 `JNI_CreateJavaVM`：这是"在进程内嵌入 JVM"的标准做法，**不会 exec**。
//
// JNI 约束：一个进程只能创建一台 VM，且不可在 `DestroyJavaVM` 之后重建（故此处不去 destroy，
// 让 VM 随进程一起结束；代价是同一进程内无法二次起服，见 spec/design 的已知限制）。

typedef jint (*CreateJavaVM_t)(JavaVM **, void **, void *);

static JavaVM *g_jvm = NULL;

// exit() 拦截开关（design D7）：默认开启（宿主进程内承载的旧行为）；专用子进程承载
// 启动前显式关闭——子进程死了就死了，不改写 libjvm 重定位。
static bool g_exit_guard_enabled = true;

// ── 拦下被托管 JVM 的 `exit()`（承载方式，见 openspec/progress.md 16.3） ──────────────
//
// 为什么必须拦：被托管服务端**自己会显式退出整个进程**。判据（javap 实证，
// `paper-26.2.jar` 的 `net.minecraft.server.dedicated.DedicatedServer.onServerExit()`）：
//
//     this.hasFullyShutdown = true;
//     System.exit(this.abnormalExit ? 70 : 0);
//
// 它经 HotSpot 的 `vm_exit()` → libc `exit()` 退出；子进程承载下无所谓（服务端本就是那个
// 进程），但**进程内**承载下那等于把宿主应用一起杀掉（真机实测：`stopped` 后打出 atexit
// 探针，随即 `Lost connection to device`）。保留非守护线程**拦不住**它——因为那不是
// "非守护线程跑完了"而是显式调用。
//
// 做法：只把 **libjvm.so 里对 `exit` 的重定位**改指到本函数。手写 GOT patch
// （PT_DYNAMIC → DT_RELA / DT_JMPREL → 按符号名 `exit` 匹配 → 覆盖槽位），**不引入**
// 任何第三方 hook 库。拦到后**永久挂起调用线程**：既不真退出，也不返回进 VM 的关闭路径
// （返回会让 VM 在不变量已破坏的状态下继续跑）。
//
// 只动 libjvm 的重定位、**不碰 libc 的 `exit`**：宿主应用自身的正常退出（ART 侧、
// 系统强停）不受影响。
// ⚠ 仅 arm64（abiFilters 首期只 arm64-v8a）：重定位一律按 ELF64 解析。

static void mc_guarded_exit(int code);

struct mc_phdr_ctx {
    const char *name;
    uintptr_t base;   // 装载基址（dlpi_addr）
    char path[1024];  // 磁盘上的真实路径（用于读 ELF 文件）
};

static int mc_find_object_cb(struct dl_phdr_info *info, size_t size, void *data) {
    struct mc_phdr_ctx *ctx = (struct mc_phdr_ctx *) data;
    if (info->dlpi_name != NULL && strstr(info->dlpi_name, ctx->name) != NULL) {
        ctx->base = (uintptr_t) info->dlpi_addr;
        snprintf(ctx->path, sizeof(ctx->path), "%s", info->dlpi_name);
        return 1; // 找到即停
    }
    return 0;
}

/** 用 PT_LOAD 表把 vaddr 换算成**文件偏移**。 */
static uint64_t mc_vaddr_to_off(const uint8_t *img, const ElfW(Phdr) *ph, size_t phnum,
                                uint64_t vaddr) {
    for (size_t i = 0; i < phnum; i++) {
        if (ph[i].p_type != PT_LOAD) continue;
        if (vaddr >= ph[i].p_vaddr && vaddr < ph[i].p_vaddr + ph[i].p_filesz) {
            return ph[i].p_offset + (vaddr - ph[i].p_vaddr);
        }
    }
    return UINT64_MAX;
}

/** 在给定重定位表（文件内，由 vaddr 给出）里收集符号名 `exit` 的**槽位 vaddr**。 */
static int mc_collect_exit_slots(const uint8_t *img, const ElfW(Phdr) *ph, size_t phnum,
                                 uint64_t rela_vaddr, uint64_t rela_size,
                                 const ElfW(Sym) * symtab, const char *strtab,
                                 uint64_t *slots, int max_slots) {
    if (rela_vaddr == 0 || rela_size == 0 || symtab == NULL || strtab == NULL) return 0;
    const uint64_t off = mc_vaddr_to_off(img, ph, phnum, rela_vaddr);
    if (off == UINT64_MAX) return 0;
    const ElfW(Rela) *rela = (const ElfW(Rela) *) (img + off);
    const size_t count = (size_t) (rela_size / sizeof(ElfW(Rela)));
    int n = 0;
    for (size_t i = 0; i < count && n < max_slots; i++) {
        const unsigned long sym_index = (unsigned long) (rela[i].r_info >> 32); // ELF64
        const ElfW(Sym) *sym = &symtab[sym_index];
        if (sym->st_name == 0) continue;
        if (strcmp(strtab + sym->st_name, "exit") != 0) continue;
        slots[n++] = (uint64_t) rela[i].r_offset; // 槽位 vaddr；真地址 = 装载基址 + 它
    }
    return n;
}

/**
 * 把 `libname` 这个已装载共享库里对 `exit` 的重定位改指到 [mc_guarded_exit]，返回改写处数。
 *
 * ⚠ **解析磁盘上的 ELF 文件，不解析内存里的 `.dynamic`**：Android bionic 下 `.dynamic`
 * 的 `d_ptr`（DT_RELA / DT_SYMTAB / DT_STRTAB …）**不保证**已被重定位成绝对地址——真机实测
 * 仍是"节偏移/vaddr"（`DT_RELA = 0x55f8`），直接当指针用必 SIGSEGV（已踩一次）。
 * 读文件则语义明确：`d_ptr` 是 vaddr，用 PT_LOAD 换算文件偏移；`r_offset` 也是 vaddr，
 * 加装载基址即为内存里的 GOT 槽位。此口径已用等价 Python 在真 `libjvm.so` 上离线验证。
 */
static int mc_hook_exit_in(const char *libname) {
    struct mc_phdr_ctx ctx;
    memset(&ctx, 0, sizeof(ctx));
    ctx.name = libname;
    if (dl_iterate_phdr(mc_find_object_cb, &ctx) == 0) {
        HOST_LOGE("找不到已装载的 %s", libname);
        return 0;
    }

    // dlpi_name 可能只是 SONAME：不够用时回退到 /proc/self/maps 取真实路径。
    if (ctx.path[0] != '/') {
        FILE *maps = fopen("/proc/self/maps", "r");
        if (maps != NULL) {
            char line[1024];
            while (fgets(line, sizeof(line), maps) != NULL) {
                if (strstr(line, libname) == NULL) continue;
                char *nl = strchr(line, '\n');
                if (nl != NULL) *nl = '\0';
                char *sp = strrchr(line, ' ');
                if (sp != NULL && sp[1] == '/') {
                    snprintf(ctx.path, sizeof(ctx.path), "%s", sp + 1);
                    break;
                }
            }
            fclose(maps);
        }
    }
    if (ctx.path[0] != '/') {
        HOST_LOGE("拿不到 %s 的文件路径，无法解析其重定位", libname);
        return 0;
    }

    int fd = open(ctx.path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) {
        HOST_LOGE("打开 %s 失败：%s", ctx.path, strerror(errno));
        return 0;
    }
    struct stat st;
    if (fstat(fd, &st) != 0 || st.st_size <= 0) {
        HOST_LOGE("取 %s 大小失败", ctx.path);
        close(fd);
        return 0;
    }
    const size_t img_size = (size_t) st.st_size;
    const uint8_t *img = (const uint8_t *) mmap(NULL, img_size, PROT_READ, MAP_PRIVATE, fd, 0);
    close(fd);
    if (img == MAP_FAILED) {
        HOST_LOGE("映射 %s 失败：%s", ctx.path, strerror(errno));
        return 0;
    }

    int patched = 0;
    do {
        const ElfW(Ehdr) *eh = (const ElfW(Ehdr) *) img;
        if (img_size < sizeof(ElfW(Ehdr)) || eh->e_ident[EI_MAG0] != ELFMAG0 ||
            eh->e_ident[EI_CLASS] != ELFCLASS64 || eh->e_phnum == 0) {
            HOST_LOGE("%s 不是可解析的 ELF64", ctx.path);
            break;
        }
        const ElfW(Phdr) *ph = (const ElfW(Phdr) *) (img + eh->e_phoff);
        const size_t phnum = eh->e_phnum;

        const ElfW(Dyn) *dyn = NULL;
        for (size_t i = 0; i < phnum; i++) {
            if (ph[i].p_type == PT_DYNAMIC) {
                dyn = (const ElfW(Dyn) *) (img + ph[i].p_offset);
                break;
            }
        }
        if (dyn == NULL) {
            HOST_LOGE("%s 没有 PT_DYNAMIC", ctx.path);
            break;
        }

        uint64_t symtab_v = 0, strtab_v = 0, rela_v = 0, jmprel_v = 0;
        uint64_t rela_size = 0, jmprel_size = 0;
        long plt_rel = -1;
        for (const ElfW(Dyn) *d = dyn; d->d_tag != DT_NULL; ++d) {
            switch (d->d_tag) {
                case DT_SYMTAB: symtab_v = d->d_un.d_ptr; break;
                case DT_STRTAB: strtab_v = d->d_un.d_ptr; break;
                case DT_RELA: rela_v = d->d_un.d_ptr; break;
                case DT_RELASZ: rela_size = d->d_un.d_val; break;
                case DT_JMPREL: jmprel_v = d->d_un.d_ptr; break;
                case DT_PLTRELSZ: jmprel_size = d->d_un.d_val; break;
                case DT_PLTREL: plt_rel = (long) d->d_un.d_val; break;
                default: break;
            }
        }
        const uint64_t symtab_off = mc_vaddr_to_off(img, ph, phnum, symtab_v);
        const uint64_t strtab_off = mc_vaddr_to_off(img, ph, phnum, strtab_v);
        if (symtab_off == UINT64_MAX || strtab_off == UINT64_MAX) {
            HOST_LOGE("%s 的 DT_SYMTAB / DT_STRTAB 无法换算成文件偏移", ctx.path);
            break;
        }
        const ElfW(Sym) *symtab = (const ElfW(Sym) *) (img + symtab_off);
        const char *strtab = (const char *) (img + strtab_off);
        if (jmprel_v != 0 && plt_rel != DT_RELA) {
            HOST_LOGE("%s 的 PLT 用的是 REL（非 arm64 预期），跳过该表", ctx.path);
            jmprel_v = 0;
        }

        uint64_t slots[8];
        int n = mc_collect_exit_slots(img, ph, phnum, rela_v, rela_size, symtab, strtab,
                                     slots, 8);
        n += mc_collect_exit_slots(img, ph, phnum, jmprel_v, jmprel_size, symtab, strtab,
                                  slots + n, 8 - n);

        const uintptr_t page_mask = (uintptr_t) getpagesize() - 1;
        for (int i = 0; i < n; i++) {
            void **slot = (void **) (ctx.base + slots[i]);
            // GOT 常落在 RELRO 只读页：先放开写权限（改完不收回，保持可写）。
            void *page = (void *) ((uintptr_t) slot & ~page_mask);
            if (mprotect(page, getpagesize(), PROT_READ | PROT_WRITE) != 0) {
                HOST_LOGE("放开 GOT 页写权限失败（%p）：%s", page, strerror(errno));
                continue;
            }
            *slot = (void *) mc_guarded_exit;
            HOST_LOGI("已改写 exit 重定位槽位 %p（库内 vaddr 0x%llx）", (void *) slot,
                      (unsigned long long) slots[i]);
            patched++;
        }
    } while (0);

    munmap((void *) img, img_size);
    return patched;
}

/**
 * 拦下被托管 JVM 的进程退出请求：**不真正退出、也不返回**，只把本线程永久挂起。
 *
 * 挂起而不是返回，是因为调用点位于 HotSpot `vm_exit()` 的末尾——返回等于让 VM 带着
 * 已拆除的状态继续执行；而宿主应用（ART 侧线程）与该 JVM 互不相干，照样运行。
 */
static void mc_guarded_exit(int code);

// exit 结果回传（design D5）：拦截到 exit 后，把真实退出码写进结果文件（C 层写，
// 供 Dart 侧读取）。路径由 Kotlin 侧经 nativeSetExitResultPath 注入；Kotlin 侧在
// runMain 返回后已预写 mainExitCode/stopConfirmed 行，这里追加 exit 行。
static char g_exit_result_path[1024] = {0};
static char g_exit_pid_path_buf[1024] = {0};
static bool g_exit_result_ready = false;

static void mc_write_exit_result(int code) {
    if (!g_exit_result_ready || g_exit_result_path[0] == '\0') return;
    // 读 Kotlin 预写的基础行（.tmp，可能不存在），追加 exit 行后落为正式结果文件。
    char tmp_path[1040];
    snprintf(tmp_path, sizeof(tmp_path), "%s.tmp", g_exit_result_path);
    char prior[2048] = {0};
    FILE *in = fopen(tmp_path, "r");
    if (in != NULL) {
        size_t n = fread(prior, 1, sizeof(prior) - 1, in);
        fclose(in);
        prior[n] = '\0';
        unlink(tmp_path);
    }
    FILE *out = fopen(g_exit_result_path, "w");
    if (out == NULL) return;
    fputs(prior, out);
    fprintf(out, "exitStatus=%d\nvmExited=true\n", code);
    fclose(out);
}

static void mc_guarded_exit(int code) {
    HOST_LOGI("拦下被托管 JVM 的 exit(%d)：回传真实退出码后终止承载子进程", code);
    printf("[mc_jvm_host] 被托管服务端请求退出（exit(%d)）：回传退出码并收尾子进程\n", code);
    fflush(stdout);
    mc_write_exit_result(code);
    unlink(g_exit_pid_path_buf); // pidFile 由本层清理
    kill(getpid(), SIGKILL);   // 承载子进程随之终止（不再挂起线程、不再殃及宿主）
    for (;;) pause();          // 不可达兜底
}

/** Java `String[]` → VM 选项数组（optionString 归本函数所有，须在调用结束后释放）。 */
static JavaVMOption *create_vm_options(JNIEnv *env, jobjectArray strings, jsize *out_count) {
    jsize count = (*env)->GetArrayLength(env, strings);
    JavaVMOption *options = (JavaVMOption *) calloc((size_t) count, sizeof(JavaVMOption));
    for (jsize i = 0; i < count; i++) {
        jstring item = (jstring) (*env)->GetObjectArrayElement(env, strings, i);
        const char *utf = (*env)->GetStringUTFChars(env, item, NULL);
        options[i].optionString = strdup(utf);
        (*env)->ReleaseStringUTFChars(env, item, utf);
        (*env)->DeleteLocalRef(env, item);
    }
    *out_count = count;
    return options;
}

static void free_vm_options(JavaVMOption *options, jsize count) {
    for (jsize i = 0; i < count; i++) free((void *) options[i].optionString);
    free(options);
}

/** 取当前线程的 JNIEnv（必要时 AttachCurrentThread）。未创建 VM 时返回 NULL。 */
static JNIEnv *current_env(void) {
    if (g_jvm == NULL) return NULL;
    JNIEnv *env = NULL;
    // Android 的 `jni.h` 最高只到 `JNI_VERSION_1_6`（现代 VM 亦接受该版本号）。
    jint rc = (*g_jvm)->GetEnv(g_jvm, (void **) &env, JNI_VERSION_1_6);
    if (rc == JNI_EDETACHED) {
        if ((*g_jvm)->AttachCurrentThread(g_jvm, &env, NULL) != JNI_OK) return NULL;
    } else if (rc != JNI_OK) {
        return NULL;
    }
    return env;
}

/**
 * 创建进程内 JVM。入参为 VM 选项数组（`-Djava.class.path` / `-Djava.home` / `-Xms` …）。
 * 返回 JNI_OK(0) 成功，负值为失败（`JNI_ERR=-1` 等）。
 */
JNIEXPORT jint JNICALL
Java_com_qshh_flutter_1mc_JvmHost_nativeCreateJvm(JNIEnv *env, jclass clazz, jobjectArray options) {
    if (g_jvm != NULL) {
        HOST_LOGI("JVM 已创建过，跳过（一进程一台 VM 是 JNI 的约束）");
        return 0;
    }

    // libjvm 已由 nativeDlopen 预加载过；这里再取一次句柄并解析创建函数。
    void *libjvm = dlopen("libjvm.so", RTLD_NOW | RTLD_GLOBAL);
    if (libjvm == NULL) {
        HOST_LOGE("libjvm.so 装载失败（LD_LIBRARY_PATH 是否含 <jre>/lib/<arch>/server？）：%s",
                  dlerror());
        return -1;
    }

    // 拦下 libjvm 的 `exit()`（**必须在建 VM 之前**，覆盖初始化期的退出路径）。
    // 开关（design D7）：专用子进程承载下**不装**——子进程死了就死了，宿主进程从此
    // 不改写 libjvm 重定位（默认开启保持旧行为，子进程承载启动前显式关闭）。
    static bool exit_guard_done = false;
    if (g_exit_guard_enabled && !exit_guard_done) {
        exit_guard_done = true;
        const int patched = mc_hook_exit_in("libjvm.so");
        if (patched > 0) {
            HOST_LOGI("已拦下 libjvm 的 exit()（%d 处重定位）：停服不再带走宿主应用", patched);
        } else {
            HOST_LOGE("未能拦下 libjvm 的 exit()：停服可能连带终止宿主应用");
        }
    }

    CreateJavaVM_t create = (CreateJavaVM_t) dlsym(libjvm, "JNI_CreateJavaVM");
    if (create == NULL) {
        HOST_LOGE("libjvm.so 中找不到 JNI_CreateJavaVM：%s", dlerror());
        return -1;
    }

    jsize count = 0;
    JavaVMOption *vm_options = create_vm_options(env, options, &count);
    JavaVMInitArgs args;
    memset(&args, 0, sizeof(args));
    args.version = JNI_VERSION_1_6;
    args.nOptions = count;
    args.options = vm_options;
    args.ignoreUnrecognized = JNI_FALSE;

    HOST_LOGI("JNI_CreateJavaVM：共 %d 个选项", (int) count);
    for (jsize i = 0; i < count; i++) {
        HOST_LOGI("  VM 选项[%d] = %s", (int) i, vm_options[i].optionString);
    }

    JNIEnv *vm_env = NULL;
    jint rc = create(&g_jvm, (void **) &vm_env, &args);
    free_vm_options(vm_options, count);

    if (rc != JNI_OK) {
        HOST_LOGE("JNI_CreateJavaVM 失败，返回码 %d", (int) rc);
        g_jvm = NULL;
        return rc;
    }
    HOST_LOGI("JVM 创建成功（JNI_CreateJavaVM 返回 JNI_OK）");

    // 打印 java.version（stdout 已重定向到实例日志）——供"仅建 VM"的判别实验取证。
    jclass system_class = (*vm_env)->FindClass(vm_env, "java/lang/System");
    jmethodID get_property = system_class == NULL ? NULL
            : (*vm_env)->GetStaticMethodID(vm_env, system_class, "getProperty",
                                          "(Ljava/lang/String;)Ljava/lang/String;");
    if (get_property != NULL) {
        jstring key = (*vm_env)->NewStringUTF(vm_env, "java.version");
        jstring value = (jstring) (*vm_env)->CallStaticObjectMethod(vm_env, system_class,
                                                                   get_property, key);
        const char *version = value == NULL ? NULL : (*vm_env)->GetStringUTFChars(vm_env, value, NULL);
        printf("JVM created; java.version=%s\n", version == NULL ? "(unknown)" : version);
        fflush(stdout);
        HOST_LOGI("JVM created; java.version=%s", version == NULL ? "(unknown)" : version);
        if (version != NULL) (*vm_env)->ReleaseStringUTFChars(vm_env, value, version);
    }
    return 0;
}

/**
 * 调用被托管 jar 的主类 `main(String[])`（阻塞至 main 返回）。
 * 返回 0 正常返回；负值为失败；`-4` 表示 main 抛异常（已打到日志并清除）。
 */
JNIEXPORT jint JNICALL
Java_com_qshh_flutter_1mc_JvmHost_nativeRunMain(JNIEnv *caller_env, jclass clazz,
                                                jstring class_name, jobjectArray args) {
    JNIEnv *env = current_env();
    if (env == NULL) {
        HOST_LOGE("JVM 尚未创建或当前线程无法 attach，无法调用主类");
        return -1;
    }

    const char *name_utf = (*caller_env)->GetStringUTFChars(caller_env, class_name, NULL);
    char *name = strdup(name_utf);
    (*caller_env)->ReleaseStringUTFChars(caller_env, class_name, name_utf);
    HOST_LOGI("runMain 步骤 1：准备加载主类 %s（caller_env=%p, env=%p）", name,
              (void *) caller_env, (void *) env);

    // 经系统类加载器加载主类（attached 线程里 FindClass 的口径不保证能看见 -Djava.class.path，
    // 故显式走 ClassLoader.getSystemClassLoader().loadClass）。
    HOST_LOGI("runMain 步骤 2：FindClass(java/lang/ClassLoader)");
    jclass class_loader_class = (*env)->FindClass(env, "java/lang/ClassLoader");
    HOST_LOGI("runMain 步骤 2 完成：class_loader_class=%p", (void *) class_loader_class);
    jmethodID get_system_loader = class_loader_class == NULL ? NULL
            : (*env)->GetStaticMethodID(env, class_loader_class, "getSystemClassLoader",
                                        "()Ljava/lang/ClassLoader;");
    jmethodID load_class = class_loader_class == NULL ? NULL
            : (*env)->GetMethodID(env, class_loader_class, "loadClass",
                                  "(Ljava/lang/String;)Ljava/lang/Class;");
    HOST_LOGI("runMain 步骤 3：取系统类加载器（getStatic=%p, loadClass=%p）",
              (void *) get_system_loader, (void *) load_class);
    jobject system_loader = get_system_loader == NULL ? NULL
            : (*env)->CallStaticObjectMethod(env, class_loader_class, get_system_loader);
    HOST_LOGI("runMain 步骤 3 完成：system_loader=%p", (void *) system_loader);

    jstring jname = (*env)->NewStringUTF(env, name);
    jobject main_class = NULL;
    if (load_class != NULL && system_loader != NULL) {
        HOST_LOGI("runMain 步骤 4：loadClass(%s)", name);
        main_class = (*env)->CallObjectMethod(env, system_loader, load_class, jname);
    }
    HOST_LOGI("runMain 步骤 4 完成：main_class=%p", (void *) main_class);
    if ((*env)->ExceptionCheck(env) != JNI_FALSE || main_class == NULL) {
        HOST_LOGE("加载主类失败：%s", name);
        (*env)->ExceptionDescribe(env);
        (*env)->ExceptionClear(env);
        free(name);
        return -2;
    }
    free(name);

    HOST_LOGI("runMain 步骤 5：GetStaticMethodID(main)");
    jmethodID main_method = (*env)->GetStaticMethodID(env, (jclass) main_class, "main",
                                                      "([Ljava/lang/String;)V");
    HOST_LOGI("runMain 步骤 5 完成：main_method=%p", (void *) main_method);
    if (main_method == NULL) {
        HOST_LOGE("主类里找不到 main(String[])");
        (*env)->ExceptionDescribe(env);
        (*env)->ExceptionClear(env);
        return -3;
    }

    jclass string_class = (*env)->FindClass(env, "java/lang/String");
    jsize argc = (*caller_env)->GetArrayLength(caller_env, args);
    HOST_LOGI("runMain 步骤 6：构造参数数组（argc=%d, String.class=%p）", (int) argc,
              (void *) string_class);
    jobjectArray jargs = (*env)->NewObjectArray(env, argc, string_class, NULL);
    if (jargs == NULL) {
        HOST_LOGE("创建参数数组失败");
        (*env)->ExceptionDescribe(env);
        (*env)->ExceptionClear(env);
        return -5;
    }
    // ⚠ 跨 VM 边界只允许传 **C 层字符串**：
    //   本进程里同时存在两台 VM —— Android 的 ART（`caller_env` 属于它）与我们新建的 HotSpot
    //   （`env` 属于它）。JNI 的 local ref 只能在其所属 VM 里使用，把 ART 的 ref 塞进 HotSpot 的
    //   数组会被 HotSpot 当成 oop 解引用而 SIGSEGV（真机实测：fault addr 0x2c）。
    //   故：用 `caller_env` 取 C 字符串 → 用 `env` 新建 HotSpot 字符串 → 放进 HotSpot 数组。
    for (jsize i = 0; i < argc; i++) {
        jstring item = (jstring) (*caller_env)->GetObjectArrayElement(caller_env, args, i);
        const char *utf = (*caller_env)->GetStringUTFChars(caller_env, item, NULL);
        jstring hot_spot_item = (*env)->NewStringUTF(env, utf);
        (*env)->SetObjectArrayElement(env, jargs, i, hot_spot_item);
        (*caller_env)->ReleaseStringUTFChars(caller_env, item, utf);
        (*caller_env)->DeleteLocalRef(caller_env, item);
        (*env)->DeleteLocalRef(env, hot_spot_item);
    }

    HOST_LOGI("runMain 步骤 7：CallStaticVoidMethod(main)");
    (*env)->CallStaticVoidMethod(env, (jclass) main_class, main_method, jargs);
    if ((*env)->ExceptionCheck(env) != JNI_FALSE) {
        HOST_LOGE("主类执行时抛异常（详见日志）");
        (*env)->ExceptionDescribe(env); // 打到已被重定向的 stderr → 实例日志
        (*env)->ExceptionClear(env);
        return -4;
    }
    HOST_LOGI("主类 main 正常返回");
    return 0;
}

// exit() 拦截开关（design D7）：子进程承载在启动前关闭（宿主进程内承载旧行为保持默认开）。
JNIEXPORT jint JNICALL
Java_com_qshh_flutter_1mc_JvmHost_nativeSetExitGuardEnabled(JNIEnv *env, jclass clazz,
                                                            jboolean enabled) {
    g_exit_guard_enabled = enabled != JNI_FALSE;
    HOST_LOGI("exit() 拦截开关 = %s", g_exit_guard_enabled ? "开" : "关");
    return 0;
}

// 对指定 pid 下发 SIGKILL（design D6）：承载父进程对子进程的强制终止能力。
// 同 uid 进程间 kill 由内核放行；返回 0 成功、-1 失败（errno 见日志）。
JNIEXPORT jint JNICALL
Java_com_qshh_flutter_1mc_JvmHost_nativeKill(JNIEnv *env, jclass clazz, jint pid) {
    if (pid <= 0) return -1;
    if (kill((pid_t) pid, SIGKILL) != 0) {
        HOST_LOGE("kill(%d, SIGKILL) 失败：errno=%d", (int) pid, errno);
        return -1;
    }
    HOST_LOGI("已向 pid %d 下发 SIGKILL", (int) pid);
    return 0;
}

// 注入 exit 结果回传路径（design D5）：结果文件 + pidFile。专用子进程承载在启动时调用。
JNIEXPORT jint JNICALL
Java_com_qshh_flutter_1mc_JvmHost_nativeSetExitResultPaths(JNIEnv *env, jclass clazz,
                                                           jstring jresult, jstring jpid) {
    const char *result = (*env)->GetStringUTFChars(env, jresult, NULL);
    const char *pid = (*env)->GetStringUTFChars(env, jpid, NULL);
    snprintf(g_exit_result_path, sizeof(g_exit_result_path), "%s", result);
    snprintf(g_exit_pid_path_buf, sizeof(g_exit_pid_path_buf), "%s", pid);
    g_exit_result_ready = true;
    (*env)->ReleaseStringUTFChars(env, jresult, result);
    (*env)->ReleaseStringUTFChars(env, jpid, pid);
    HOST_LOGI("exit 结果回传就绪：result=%s pid=%s", g_exit_result_path,
              g_exit_pid_path_buf);
    return 0;
}
