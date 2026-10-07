import 'dart:io' show Platform;

import 'package:permission_handler/permission_handler.dart';

/// 申请"按任意路径读写文件"所需的运行时授权。
///
/// 只做平台能做到的那部分，各平台的真实边界见对应的配置文件：
/// * android/app/src/main/AndroidManifest.xml
/// * macos/Runner/DebugProfile.entitlements、Release.entitlements
/// * macos/Runner/Info.plist、ios/Runner/Info.plist
///
/// Android 11（API 30）起，MANAGE_EXTERNAL_STORAGE 是唯一能按**任意路径**读写的
/// 权限（READ/WRITE_EXTERNAL_STORAGE 在 API 33 已彻底失效）。它属于"特殊权限"：
/// 系统不会弹运行时对话框授予，只能把用户送到设置页手动打开开关，所以这里是
/// "引导"而不是"静默拿到"——拿不到时返回 false，由调用方决定怎么办。
///
/// macOS 关掉 App Sandbox 后不需要运行时授权；桌面/文稿/下载仍受 TCC 单独看管，
/// 首次触碰由系统弹窗，文案来自 Info.plist 的 NS*FolderUsageDescription。
/// permission_handler 目前没有 macOS 实现（permission_handler_apple 只 implements
/// ios），所以 macOS 分支不能碰插件。
///
/// iOS 没有"任意路径"这回事，只能在沙盒内读写，或经 UIDocumentPicker 由用户挑选。
Future<bool> ensureArbitraryPathFileAccess() async {
  if (!Platform.isAndroid) {
    return true;
  }

  // 开过就不再打断用户：request() 在已授权时直接返回 granted，不会跳设置页。
  final manage = await Permission.manageExternalStorage.request();
  if (manage.isGranted) {
    return true;
  }

  // Android 10 及以下没有 MANAGE_EXTERNAL_STORAGE（插件返回 restricted），
  // 回落到传统的 READ/WRITE_EXTERNAL_STORAGE 运行时权限。
  return await Permission.storage.request().isGranted;
}
