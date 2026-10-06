# Proposal

## Why

渲染侧开发（join-and-render）在即，引擎升级趁 app 壳尚无 flutter_scene 代码时做最省事；Flutter GPU 需平台文件显式开启，fscraft 已有同款配置可照搬。

## What Changes

- flutter_scene 0.23.0 → 0.24.0（app 壳尚无场景代码，无迁移面）
- 三平台启用 Flutter GPU（照 fscraft 与官方口径）：macOS/iOS `Info.plist` 加 `FLTEnableFlutterGPU`，Android manifest 加 `EnableFlutterGPU` meta-data
- README 运行命令补 `--enable-flutter-gpu`

## Capabilities

（无——依赖升级与平台构建配置，纯 tooling，`skip_specs: true`）

## Impact

- `pubspec.yaml`、`macos/Runner/Info.plist`、`ios/Runner/Info.plist`、`android/app/src/main/AndroidManifest.xml`、`README.md`
