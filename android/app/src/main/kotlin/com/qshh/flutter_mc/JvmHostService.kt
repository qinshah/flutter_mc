package com.qshh.flutter_mc

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Bundle
import android.os.IBinder
import android.os.Process
import java.io.File

/**
 * 被托管服务端的**承载 Service**（第三类自由设计「运行时宿主（JVM 托管）」），
 * 跑在应用专用 `:jvm` 子进程（manifest `android:process=":jvm"`）。
 *
 * 承载范式：**一次会话一个子进程、会话结束即终止**（FCL `GameMenu.onExit`
 * （`GameMenu.java:967-973`）的 killProcess 范式；每会话全新 VM，绕开 JNI
 * "一进程一台 VM"对二次起服的限制——change `android-subprocess-jvm-host`）。
 *
 * 生命周期（design D2-D5）：
 *   · 启动：Intent extras 收参数 → env/stdio/命名空间/dlopen 链（照 Dart 侧旧进程内承载
 *     的同口径）→ 建 VM（**关 exit() 拦截**：子进程死了就死了）→ 调主类；
 *   · 收尾：停机哨兵只扫**本会话**日志段，命中原版停机行（判据 `MinecraftServer.java:650`）
 *     → 留存盘窗口 → 删 pidFile（父进程判死依据）→ 写结果文件 → SIGKILL 自杀；
 *   · 孤儿兜底：心跳 watchdog——主进程周期性写心跳文件，超时（主进程异常死亡）自杀
 *     （子进程父进程是 zygote，`getppid` 探不到主进程死亡，故用心跳文件）。
 */
class JvmHostService : Service() {

    companion object {
        const val EXTRA_SERVICE_PARAMS = "params"
        private const val CHANNEL_ID = "flutter_mc_jvm_host"
        private const val NOTIFICATION_ID = 0x6D64 // "md"
        private const val STOP_MARKER = "Stopping server" // 判据 MinecraftServer.java:650
        private const val HEARTBEAT_TIMEOUT_MS = 30_000L
    }

    /** 主类退出码（runMain 线程产出，收尾时落结果文件）。 */
    @Volatile
    private var mainExitCode: Int = -1

    /** 停机哨兵是否已见原版停机行（判据 `MinecraftServer.java:650`）。 */
    @Volatile
    private var stopConfirmed: Boolean = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val params = intent?.getBundleExtra(EXTRA_SERVICE_PARAMS)
        if (params == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        // 前台化**立即**执行（实测 MIUI 会按 MiuiMemoryService(started-services) 杀掉
        // "仅有非前台 service" 的后台进程，adj 800；照 FCL ProcessService 的 ":jvm + FGS"
        // 形态，specialUse 无 Android 15+ 的 dataSync 6 小时超时）。
        startForegroundCompat()
        Thread({ runService(params) }, "jvm-host-service").start()
        // 不做 START_STICKY：服务端与子进程同进程，系统重建只会留下没有服务端语境的空壳。
        return START_NOT_STICKY
    }

    private fun startForegroundCompat() {
        ensureChannel()
        val type = if (android.os.Build.VERSION.SDK_INT >=
            android.os.Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
        } else {
            0
        }
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, buildNotification(), type)
        } else {
            @Suppress("DEPRECATION")
            startForeground(NOTIFICATION_ID, buildNotification())
        }
    }

    private fun ensureChannel() {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "本地服务器（承载进程）",
                NotificationManager.IMPORTANCE_LOW,
            )
        )
    }

    private fun buildNotification(): Notification {
        val builder = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        val contentIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return builder
            .setContentTitle("本地服务器运行中")
            .setContentText("承载进程正在托管服务端")
            .setContentIntent(contentIntent)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
    }

    private fun runService(p: Bundle) {
        val workDir = p.getString("workDir")!!
        val logPath = p.getString("logPath")!!
        val pidFile = File(p.getString("pidFile")!!)
        val resultFile = File(p.getString("resultPath")!!)
        // pidFile **尽早**写：父进程的死亡监视以"pidFile 出现过 → 消失"为判死依据，
        // 若等建好 VM 才写，启动早期（dlopen/建 VM 失败）的死亡将不可观测（实测踩过）。
        try {
            pidFile.writeText(Process.myPid().toString())
        } catch (_: Throwable) {}
        try {
            // 1) env（照 Dart 侧旧进程内承载的推导口径，参数由父进程算好传入）。
            JvmHost.nativeSetEnv("HOME", workDir)
            JvmHost.nativeSetEnv("JAVA_HOME", p.getString("jrePath")!!)
            JvmHost.nativeSetEnv("PATH", p.getString("pathEnv")!!)
            JvmHost.nativeSetEnv("LD_LIBRARY_PATH", p.getString("ldLibraryPath")!!)
            JvmHost.nativeSetEnv("TMPDIR", p.getString("tmpDir")!!)
            JvmHost.nativeSetEnv("TMP", p.getString("tmpDir")!!)

            // 2) stdout/stderr 重定向到实例日志（此后 println 进日志文件——但注意
            //    Android 的 System.out 被 ART 换成 logcat 流，**可靠上报走文件**）。
            val rcStdio = JvmHost.nativeRedirectStdio(logPath)
            if (rcStdio != 0) throw IllegalStateException("redirectStdio=$rcStdio")

            // 3) namespace 逃逸（子进程有自己独立的 linker namespace，须重做）。
            if (!JvmHost.nativeEscapeNamespaceReady()) {
                throw IllegalStateException("命名空间绕行不可用")
            }

            // 4) dlopen 链（照 FCLauncher.setUpJavaRuntime / locateLibs 口径）。
            val jreDir = File(p.getString("jrePath")!!)
            JvmHost.nativeDlopen(p.getString("jliLib")!!)
            JvmHost.nativeDlopen(p.getString("jvmLib")!!)
            jreDir.walkTopDown().filter { it.isFile && it.name.endsWith(".so") }
                .forEach { JvmHost.nativeDlopen(it.path) }
            JvmHost.nativeSetLdLibraryPath(p.getString("ldLibraryPath")!!)
            val rcChdir = JvmHost.nativeChdir(workDir)
            if (rcChdir != 0) throw IllegalStateException("chdir=$rcChdir")

            // 5) exit() 拦截**保持开启**（native 默认），并注入结果回传路径：
            //    被托管服务端收尾会自己调 System.exit(status)（javap 实证
            //    DedicatedServer.onServerExit → exit(abnormal?70:0)），拦截层拿到真实
            //    status 写结果文件并终止承载子进程。
            //    ⚠ 结果**不能**靠 Runtime.addShutdownHook：那个 hook 注册在 ART 上，而
            //    System.exit 走 HotSpot 的 Shutdown（实测 hook 从不执行）——必须在
            //    native 拦截层写（C 层，libc exit 必经）。
            JvmHost.nativeSetExitResultPaths(resultFile.path, pidFile.path)

            // 6) 心跳 + watchdog + 停机哨兵（都在建 VM 前挂上）：
            //    · childHeartbeat：子进程自写（父进程判"child 是否活着"——残留检查与判死）；
            //    · heartbeat：主进程写，本进程 watchdog 监视（主进程死亡 ⇒ 自杀兜底）。
            //    （结果文件由 native exit 拦截层写，见步骤 5；此处不再注册 ART hook——
            //    它注册在 ART 的 Runtime 上，HotSpot 的 System.exit 不会调它。）
            val heartbeatPath = p.getString("heartbeatPath")!!
            val childHeartbeat = File(p.getString("childHeartbeatPath")!!)
            val logOffset = if (File(logPath).exists()) File(logPath).length() else 0L
            Thread({
                while (true) {
                    try {
                        childHeartbeat.writeText(
                            java.text.SimpleDateFormat("HH:mm:ss.SSS",
                                java.util.Locale.US).format(java.util.Date())
                        )
                    } catch (_: Throwable) {}
                    Thread.sleep(5_000)
                }
            }, "jvm-child-heartbeat").start()
            Thread({ watchHeartbeat(heartbeatPath, resultFile, pidFile) }, "jvm-heartbeat").start()
            Thread({ watchStopAndDie(logPath, logOffset, pidFile, resultFile) },
                "jvm-stop-watch").start()

            // 7) 建 VM（子进程自己的 native static：g_jvm 从 NULL 起步，真建）。
            val options = p.getStringArrayList("vmOptions")!!.toTypedArray()
            val rc = JvmHost.nativeCreateJvm(options)
            if (rc != 0) throw IllegalStateException("createJvm=$rc")

            // 8) pidFile 已在开头写（见上）；这里只留 logcat 取证行。
            println("[jvm-host] 承载子进程 pid=${Process.myPid()}，VM 建成")

            // 9) 主类（阻塞至 main 返回；服务端跑在 Server thread / paperclip 子进程里）。
            mainExitCode = JvmHost.nativeRunMain(p.getString("mainClass")!!,
                p.getStringArrayList("mainArgs")!!.toTypedArray())
            println("[jvm-host] 子进程 main 返回（退出码 $mainExitCode），等待 exit 拦截层收尾")
            // 预写结果基础行（mainExitCode / stopConfirmed）到 **.tmp**：exit 拦截层读到它
            // 后追加 exitStatus + vmExited 并落为正式结果文件——正式文件的出现即"退净"
            // 信号（⚠ 基础行 MUST NOT 写正式文件：main 返回 ≠ 服务端结束，父进程会把
            // 它误判为退净，实测踩过——心跳 Timer 被误停 → child watchdog 自杀）。
            writeResult(File(resultFile.path + ".tmp"), stopConfirmed = stopConfirmed,
                fatal = null, vmExited = null)
            Thread.sleep(Long.MAX_VALUE) // 收尾交给 exit 拦截层（SIGKILL 不挑线程状态）
        } catch (t: Throwable) {
            android.util.Log.e("JvmHostService", "承载子进程失败", t)
            writeResult(resultFile, stopConfirmed = false,
                fatal = t.message ?: t.toString(), vmExited = false)
            try {
                println("[jvm-host] 承载子进程异常退出：$t")
                pidFile.delete()
            } catch (_: Throwable) {}
            Process.killProcess(Process.myPid())
        }
    }

    /** 心跳 watchdog：心跳文件超时（主进程异常死亡）→ 删 pidFile → 写结果 → 自杀。 */
    private fun watchHeartbeat(heartbeatPath: String, resultFile: File, pidFile: File) {
        val heartbeat = File(heartbeatPath)
        while (true) {
            Thread.sleep(5_000)
            val last = if (heartbeat.exists()) heartbeat.lastModified() else 0L
            if (System.currentTimeMillis() - last > HEARTBEAT_TIMEOUT_MS) {
                // 主进程已死（force stop 时本进程也会被系统一并杀掉，走不到这里；
                // 这里兜的是主进程单独 crash 的孤儿窗口）。
                writeResult(resultFile, stopConfirmed = false,
                    fatal = "心跳超时：宿主主进程已死亡", vmExited = false)
                pidFile.delete()
                println("[jvm-host] 心跳超时，承载子进程自杀（pid=${Process.myPid()}）")
                Process.killProcess(Process.myPid())
                return
            }
        }
    }

    /** 只扫 [logOffset] 之后追加的日志；命中停机行 → 留存盘窗口 → 删 pidFile → 自杀。 */
    private fun watchStopAndDie(logPath: String, logOffset: Long, pidFile: File,
                                resultFile: File) {
        val deadline = System.currentTimeMillis() + 15 * 60_000L
        val f = File(logPath)
        var offset = logOffset
        var stopped = false
        while (System.currentTimeMillis() < deadline && !stopped) {
            try {
                if (f.exists() && f.length() > offset) {
                    val raf = f.inputStream()
                    raf.skip(offset)
                    val tail = raf.readBytes().toString(Charsets.UTF_8)
                    raf.close()
                    offset += tail.toByteArray().size
                    if (tail.contains(STOP_MARKER)) {
                        stopped = true
                        stopConfirmed = true // 停机行确认（父进程据此把 exitCode=0 判为优雅停止）
                    }
                }
            } catch (_: Throwable) {}
            if (!stopped) Thread.sleep(500)
        }
        if (stopped) {
            // 给 chunk 存盘留窗口（实测全量存盘 ~2s）。正常路径下被托管服务端收尾时会
            // 自行 System.exit（hook 写结果、进程自然退出），这里只是兜底。
            Thread.sleep(10_000)
        }
        if (!stopped) {
            writeResult(resultFile, stopConfirmed = false, fatal = null, vmExited = false)
        }
        // 删 pidFile 兜底（正常 exit 路径走不到这里；父进程判死另有 result/心跳依据）。
        pidFile.delete()
        println("[jvm-host] 承载子进程自杀（pid=${Process.myPid()} stopped=$stopped）")
        Process.killProcess(Process.myPid())
    }

    /** 结果文件：父进程判死（pidFile 消失 / child 心跳陈旧 / 本文件出现 exitStatus）后读取。
     *  `vmExited=true` 行由 native exit 拦截层追加（携带真实 exitStatus，design D5）；
     *  非正常路径（异常/心跳超时）由 ART 侧直接写 vmExited=false。 */
    private fun writeResult(resultFile: File, stopConfirmed: Boolean,
                            fatal: String?, vmExited: Boolean?) {
        try {
            resultFile.writeText(
                "mainExitCode=$mainExitCode\nstopConfirmed=$stopConfirmed\n"
                        + (vmExited?.let { "vmExited=$it\n" } ?: "")
                        + (fatal?.let { "fatal=$it\n" } ?: ""))
        } catch (_: Throwable) {}
    }
}
