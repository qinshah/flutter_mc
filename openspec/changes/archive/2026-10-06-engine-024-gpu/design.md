# Design

## Decisions

- **D1 升级时机**：app 壳尚无任何 flutter_scene 调用，0.23→0.24 无迁移成本；越晚越贵。
- **D2 GPU 开关照官方三平台口径**（用户提供 + fscraft 实证）：macOS/ iOS `Info.plist` 加 `<key>FLTEnableFlutterGPU</key><true/>`；Android manifest `<application>` 内加 meta-data `io.flutter.embedding.android.EnableFlutterGPU=true`。平台文件配置后运行**无需** `--enable-flutter-gpu`（用户裁定，2026-10-06）。
- **D3 验收**：`flutter pub get` 解析 0.24.0、全仓 analyze 零 issue、三平台配置文件含开关；实际 GPU 渲染验收归 join-and-render。
