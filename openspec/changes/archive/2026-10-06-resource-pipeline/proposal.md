# Proposal

## Why

渲染需要方块贴图。用户裁定：现阶段从本机官方 client jar **构建期提取**资产随应用打包，未来再做应用内按版本下载。fscraft 的产物形态（预拼接方块图集 + 清单）已实证对 flutter_scene 友好，照搬。

## What Changes

- `tool/extract_assets.dart` 转正为提取器：从官方 jar 提取方块相关资产（blockstates / models/block / textures/block）到 **版本标记目录** `assets/vanilla/26_2/`（gitignore，不入库），并把方块贴图**预拼接**为图集（`generated/block_atlas.png` + `generated/atlas.json` 清单）
- 新增能力 `resource-pipeline` 的读取侧：mc_resource 提供 `VanillaPack`（版本键、来源可插拔：bundle / 目录）与 `BlockModels`（blockstate → 模型 parent 链 → 贴图路径解析，含 `#` 变量插值）
- 根 pubspec 声明资产目录；`.gitignore` 覆盖提取产物
- 偏离说明：project-foundation design D7 的产物目录由 `build/extracted_assets/` 改为 `assets/vanilla/<版本>/`——Flutter 资产打包要求目录在包内

## Capabilities

### New Capabilities

- `resource-pipeline`：官方资产构建期提取、版本标记存储与读取抽象（含方块模型解析）

### Modified Capabilities

（无）

## Impact

- `tool/extract_assets.dart`、`packages/mc_resource/`、根 `pubspec.yaml`、`.gitignore`、`README.md`
- 新增 dev 依赖 `package:image`（图集拼接，tool 用）
- 提取产物不入库（红线）；缺失时应用仍可构建（资产目录以 .gitkeep 保底）
