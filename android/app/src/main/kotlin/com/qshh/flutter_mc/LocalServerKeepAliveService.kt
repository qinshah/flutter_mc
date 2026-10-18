package com.qshh.flutter_mc

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * 承载保活服务（第三类自由设计「运行时宿主（JVM 托管）」的宿主机制）。
 *
 * 为什么需要它：Android 会回收"退到后台且没有任何前台组件"的应用进程。被托管服务端与宿主
 * **同进程**（进程内 JVM），所以只要宿主进程活着，服务端就活着——这正是 spec
 * 「长期运行以前台服务保活」要的语义：**退到后台不断线**。
 *
 * 生命周期口径（spec「长期运行以前台服务保活」的第二个场景）：**与 JVM 同步**——
 * 起服即 start、停服即 stop，MUST NOT 留下仅用于保活的空转服务。
 *
 * 前台服务类型（照参考实现 FCL `GameService.kt:41-47` 的口径，取 **specialUse**）：
 *   · 不用 `dataSync`：Android 15+ 对 dataSync 型前台服务有 **6 小时强制超时**，长期
 *     运行的被托管服务端会被系统掐停；specialUse 无此限制。
 *   · specialUse 仅 API 34+ 可识别，低版本传 0 走无类型前台服务（旧系统不校验）；
 *     subtype 注明用途（照 FCL："Keep game process alive while a Minecraft session is
 *     running" 的同类场景，见 AndroidManifest 的 PROPERTY_SPECIAL_USE_FGS_SUBTYPE）。
 */
class LocalServerKeepAliveService : Service() {

    companion object {
        private const val CHANNEL_ID = "flutter_mc_local_server"
        private const val NOTIFICATION_ID = 0x6D63 // "mc"
        const val ACTION_START = "com.qshh.flutter_mc.KEEPALIVE_START"
        const val ACTION_STOP = "com.qshh.flutter_mc.KEEPALIVE_STOP"

        /** 起保活（幂等）。须在应用处于前台时调用（Android 12+ 前台服务启动限制）——
         *  起服必然发生在用户操作 UI 时，满足该前提（照 FCL `GameService.kt:75`）。 */
        fun start(context: Context) {
            val intent = Intent(context, LocalServerKeepAliveService::class.java)
                .setAction(ACTION_START)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        /** 撤保活（停服时调用；服务自行 stopSelf）。 */
        fun stop(context: Context) {
            context.stopService(Intent(context, LocalServerKeepAliveService::class.java))
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopForegroundCompat()
            stopSelf()
            return START_NOT_STICKY
        }
        startForegroundCompat()
        // 不做 START_STICKY：服务端与宿主同进程，宿主被系统杀掉时服务端也一并终止，
        // 重启服务反而会留下"没有服务端在跑"的空转服务（违反上面的同步口径）。
        // （照 FCL `GameService.kt:28` 同为 START_NOT_STICKY。）
        return START_NOT_STICKY
    }

    private fun startForegroundCompat() {
        ensureChannel()
        // specialUse 仅 API 34+ 可识别；低版本传 0（照 FCL `GameService.kt:41-47`）。
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
        } else {
            0
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, buildNotification(), type)
        } else {
            @Suppress("DEPRECATION")
            startForeground(NOTIFICATION_ID, buildNotification())
        }
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "本地服务器",
                NotificationManager.IMPORTANCE_LOW, // 静默常驻：不该打扰用户
            )
        )
    }

    private fun buildNotification(): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("本地服务器运行中")
            .setContentText("正在托管本机服务端，退出应用会一并停止")
            // 点通知回应用（照 FCL `GameService.kt:50-58` 的 contentIntent 口径）。
            .setContentIntent(buildContentIntent())
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
    }

    private fun buildContentIntent(): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        return PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }
}
