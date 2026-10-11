import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'platform/file_permission.dart';
import 'routes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 全局异常钩子（**不静默**）：SceneView 的 Ticker 回调里若在渲染期抛异常
  //（网格化上传的坏数据等），我们 _onTick 的 try/catch 包不到那里，Ticker
  // 会被打停 ⇒ 画面/移动/视角整体冻结（2026-10-07 实机复现）。这里把
  // framework 与 isolate 的未捕获异常都打上 [UNCAUGHT] 前缀完整输出。
  FlutterError.onError = (details) {
    debugPrint('[UNCAUGHT-FRAMEWORK] ${details.exception}\n'
        '${details.stack ?? StackTrace.current}');
  };
  PlatformDispatcher.instance.onError = (e, st) {
    debugPrint('[UNCAUGHT-ISOLATE] $e\n$st');
    return false; // 交给默认处理（debug 构建仍会打印，release 不吞）
  };
  // 任意路径文件读写（安卓以外平台是 no-op）。安卓上第一次跑会把用户送到系统
  // 设置页开"所有文件的访问权限"，开过之后不再打断；若想改成"用到时再申请"，
  // 把这一行挪到真正访问外部文件的时机即可。
  await ensureArbitraryPathFileAccess();
  // 移动端横屏 + 沉浸全屏（参考 fscraft main.dart；桌面端 no-op）。
  // 判据：Minecraft 手机形态恒横屏；沉浸式隐藏状态栏/导航条（immersiveSticky
  // 允许下拉临时呼出，收起后自动隐藏）。
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const FlutterMcApp());
}

class FlutterMcApp extends StatelessWidget {
  const FlutterMcApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_mc',
      debugShowCheckedModeBanner: false,
      // AUTOJOIN 取证：启动直达自动进服屏（routes.dart 的 _AutoJoinScreen）。
      initialRoute: const String.fromEnvironment('AUTOJOIN').isNotEmpty
          ? '/autojoin'
          : '/',
      routes: mcRoutes,
      onGenerateRoute: mcOnGenerateRoute,
    );
  }
}
