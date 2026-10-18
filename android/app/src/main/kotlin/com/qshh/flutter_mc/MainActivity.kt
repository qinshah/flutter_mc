package com.qshh.flutter_mc

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    /**
     * 注册宿主承载层通道（`flutter_mc/jvm_host`，见 [JvmHostChannel]）。
     *
     * 这是"运行时宿主"的装配点：Dart 侧走同一通道，不受版本 / 玩法语义影响。
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, JvmHostChannel.CHANNEL)
            .setMethodCallHandler(JvmHostChannel(this))
    }
}
