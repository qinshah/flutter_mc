package com.qshh.flutter_mc

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.apache.commons.compress.archivers.tar.TarArchiveEntry
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream
import org.apache.commons.compress.compressors.xz.XZCompressorInputStream
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream
import java.util.concurrent.Executors

/**
 * 宿主承载层的 native 桥（第三类自由设计「运行时宿主（JVM 托管）」的承载方式）。
 *
 * 对应的 native 实现在 `android/app/src/main/cpp/`（见该目录 third_party/NOTICE.md 的许可登记）。
 * 这里只做"把 native 能力暴露给 Dart"，不含任何玩法/协议语义。
 * 方法名与 `mc_jvm_host.c` / `jre_launcher.c` 的 JNI 符号一一对应。
 */
object JvmHost {
    init {
        System.loadLibrary("mc_jvm_host")
    }

    /** 写进程环境（HOME / JAVA_HOME / PATH / LD_LIBRARY_PATH / TMPDIR …）。 */
    external fun nativeSetEnv(name: String, value: String)

    /**
     * 把 stdout/stderr 重定向到日志文件（被托管 JVM 的输出即落此处）。
     * 返回 0 成功。
     */
    external fun nativeRedirectStdio(path: String): Int

    /** dlopen（私有目录下的 JRE 库），失败回退逃逸命名空间；返回 handle（0 为失败）。 */
    external fun nativeDlopen(path: String): Long

    /** 更新 linker 的 LD_LIBRARY_PATH（JRE 内部 NEEDED 解析）。 */
    external fun nativeSetLdLibraryPath(path: String)

    /** 切工作目录（原版服务端的工作目录即它的 "."）。返回 0 成功。 */
    external fun nativeChdir(path: String): Int

    /** 逃逸命名空间是否可用（不可用即"载体不可用"，Dart 侧据此报错，不静默降级）。 */
    external fun nativeEscapeNamespaceReady(): Boolean

    /**
     * 创建进程内 JVM（`JNI_CreateJavaVM`，**不 exec**）。入参为 VM 选项
     * （`-Djava.class.path` / `-Djava.home` / `-Xms` …）。返回 `JNI_OK`(0) 成功。
     * 一进程只能创建一台 VM（JNI 约束）。
     */
    external fun nativeCreateJvm(options: Array<String>): Int

    /**
     * 调用被托管 jar 的主类 `main(String[])`（阻塞至 main 返回），返回退出码（0 正常）。
     * MUST 在后台线程调用（见 [JvmHostChannel]）。
     */
    external fun nativeRunMain(className: String, args: Array<String>): Int
}

/**
 * MethodChannel 桥：承载层的 native 能力 + JRE 解包，供 Dart 侧 `AndroidEmbeddedJvmHost` 调用。
 *
 * 通道名 `flutter_mc/jvm_host`。长耗时操作（解包、起 JVM）一律丢到单线程 executor，
 * 结果经主线程回给 Dart——避免阻塞平台线程（UI isolate 也就不会被卡住）。
 */
class JvmHostChannel(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "flutter_mc/jvm_host"
    }

    private val io = Executors.newSingleThreadExecutor { r ->
        Thread(r, "mc-jvm-host-io").apply { isDaemon = true }
    }
    private val main = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "escapeNamespaceReady" ->
                    result.success(JvmHost.nativeEscapeNamespaceReady())

                "setEnv" ->
                    JvmHost.nativeSetEnv(
                        call.argument<String>("name")!!,
                        call.argument<String>("value")!!,
                    ).also { result.success(null) }

                "redirectStdio" ->
                    result.success(JvmHost.nativeRedirectStdio(call.argument<String>("path")!!))

                "dlopen" ->
                    result.success(JvmHost.nativeDlopen(call.argument<String>("path")!!))

                "setLdLibraryPath" ->
                    JvmHost.nativeSetLdLibraryPath(call.argument<String>("path")!!)
                        .also { result.success(null) }

                "chdir" ->
                    result.success(JvmHost.nativeChdir(call.argument<String>("path")!!))

                // 应用 native 库目录（含 libc++_shared.so —— JRE 的部分库依赖它）。
                // 口径照参考实现 FCLauncher.appendCommonPaths 末尾追加 nativeLibraryDir。
                "nativeLibraryDir" ->
                    result.success(context.applicationInfo.nativeLibraryDir)

                // 建 VM（JNI_CreateJavaVM；不 exec）。
                "createJvm" -> {
                    val options = call.argument<List<String>>("options")!!.toTypedArray()
                    result.success(JvmHost.nativeCreateJvm(options))
                }

                // 调主类：阻塞操作，放后台线程；返回退出码回主线程。
                "runMain" -> {
                    val className = call.argument<String>("className")!!
                    val args = call.argument<List<String>>("args")!!.toTypedArray()
                    io.execute {
                        val code = try {
                            JvmHost.nativeRunMain(className, args)
                        } catch (t: Throwable) {
                            -1
                        }
                        main.post { result.success(code) }
                    }
                }

                // JRE 解包（阻塞、大 IO），放后台线程。
                "unpackJre" -> {
                    val assetDir = call.argument<String>("assetDir")!!
                    val targetDir = call.argument<String>("targetDir")!!
                    val archSuffix = call.argument<String>("archSuffix")!!
                    io.execute {
                        try {
                            unpackJre(assetDir, targetDir, archSuffix)
                            main.post { result.success(null) }
                        } catch (t: Throwable) {
                            main.post { result.error("unpackJre", t.message ?: t.toString(), null) }
                        }
                    }
                }

                // 长期保活（spec「长期运行以前台服务保活」）：起服即起、停服即停。
                "startKeepAlive" ->
                    LocalServerKeepAliveService.start(context).also { result.success(null) }

                "stopKeepAlive" ->
                    LocalServerKeepAliveService.stop(context).also { result.success(null) }

                else -> result.notImplemented()
            }
        } catch (t: Throwable) {
            result.error("jvm_host", t.message ?: t.toString(), null)
        }
    }

    /**
     * 安装 JRE：解 `universal.tar.xz` + `bin-<arch>.tar.xz` 到 targetDir，再写 `version`。
     *
     * 口径照参考实现 `RuntimeUtils.installJava`（`RuntimeUtils.java:94-115`）：
     * 先普通包再架构包、最后落 `version` 文件；目标目录为**应用私有目录**（零存储权限）。
     */
    @Throws(IOException::class)
    private fun unpackJre(assetDir: String, targetDir: String, archSuffix: String) {
        val dest = File(targetDir)
        dest.mkdirs()

        val assets = context.assets
        uncompressTarXz(assets.open("$assetDir/universal.tar.xz"), dest)
        uncompressTarXz(assets.open("$assetDir/bin-$archSuffix.tar.xz"), dest)

        // version 文件：从资产读，落到包内（用于判断已安装口径，照 RuntimeUtils.isLatest 的用法）
        assets.open("$assetDir/version").use { ins ->
            File(dest, "version").writeBytes(ins.readBytes())
        }
    }

    /**
     * 解 tar.xz（照参考实现 `RuntimeUtils.uncompressTarXZ` 的口径，**并按 tar 的 mode 位还原
     * 可执行权限**）。
     *
     * 还原 exec 位是**实测必需**：参考实现只跑游戏（JVM 在进程内、不起子进程 java），
     * 所以它不设置文件的 exec 位也没关系；而 Paper 的 paperclip 引导器会**再起一个子进程 java**
     * 去跑打补丁后的服务端，`bin/java` 无 exec 位就会 `Permission denied: trying to exec ...`
     * （真机已踩过）。
     *
     * 差异说明：参考实现用 `Os.symlink` 建符号链接（`RuntimeUtils.java:194-200`）；本仓对符号
     * 链接**记录并跳过**——JRE 内部对 lib 的引用走 linker 的 LD_LIBRARY_PATH，不依赖这些链接名
     * （真机实测：`libjli.so` / `libjvm.so` / `libnet.so` / `libnio.so` 等均从扁平 `lib/` 直接装载成功）。
     */
    @Throws(IOException::class)
    private fun uncompressTarXz(input: InputStream, dest: File) {
        input.use { ins ->
            TarArchiveInputStream(XZCompressorInputStream(ins)).use { tar ->
                var entry: TarArchiveEntry? = tar.nextEntry
                while (entry != null) {
                    val outFile = File(dest, entry.name)
                    when {
                        entry.isDirectory -> {
                            outFile.mkdirs()
                            outFile.setExecutable(true, false)
                        }
                        entry.isSymbolicLink -> {
                            // 跳过符号链接（见上文口径说明）
                        }
                        else -> {
                            outFile.parentFile?.mkdirs()
                            FileOutputStream(outFile).use { os ->
                                tar.copyTo(os, 8192)
                            }
                            // 还原 tar 里的可执行位（0o111），见方法注释。
                            val mode = entry.mode
                            if (mode != 0 && (mode and 0b001_001_001) != 0) {
                                outFile.setExecutable(true, false)
                            }
                        }
                    }
                    entry = tar.nextEntry
                }
            }
        }
    }
}
