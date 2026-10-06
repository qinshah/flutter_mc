# Tasks

## 1. 引擎升级与 GPU 开关

- [x] 1.1 `pubspec.yaml` flutter_scene 0.23.0 → 0.24.0；验证：`flutter pub get` 成功解析且 `flutter analyze` 零 issue
- [x] 1.2 `macos/Runner/Info.plist` 与 `ios/Runner/Info.plist` 加 `FLTEnableFlutterGPU=true`，`android/app/src/main/AndroidManifest.xml` application 内加 `EnableFlutterGPU` meta-data；验证：`git grep FLTEnableFlutterGPU macos ios` 与 `git grep EnableFlutterGPU android` 各有命中
- [x] 1.3 README 运行命令补 `--enable-flutter-gpu`；验证：README 命令存在
  - 用户裁定跳过：平台文件已配置 GPU，运行无需该 flag（见 design D2）
