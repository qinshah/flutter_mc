# Tasks

## 1. 提取工具转正

- [x] 1.1 根 dev_dependencies 加 `image`（纯 Dart 图像库）；`tool/extract_assets.dart` 增加 `extract` 能力：入参 jar 路径，提取 blockstates / models/block / textures/block 到 `assets/vanilla/26_2/`，保留 jar 内相对路径；`--list` 行为保留；验证：对本机 26.2 jar 运行，产物结构正确且 `dart analyze` 零 issue
- [x] 1.2 图集拼接：读 textures/block/*.png 拼为 2 的幂图集，写 `generated/block_atlas.png` + `generated/atlas.json`（贴图名→矩形+宽高）；验证：清单条目数=贴图数，矩形均在图集内
- [x] 1.3 `.gitignore` 加 `/assets/vanilla/*` 反白 `.gitkeep` 规则；各版本目录放 .gitkeep；验证：`git check-ignore assets/vanilla/26_2/generated/block_atlas.png` 通过且 `git status` 干净

## 2. mc_resource 读取侧

- [x] 2.1 `VanillaPack`：版本键构造、来源可插拔（目录/bundle 两个来源实现）、read/exists（缺失返回空结果不抛异常）；补单测（临时目录夹具）；验证：`cd packages/mc_resource && dart test` 全绿
- [x] 2.2 `BlockModels`：blockstate variants → 模型 parent 链合并 → `#` 引用插值 → 面向贴图路径；multipart 降级取首个模型（注释标注简化）；补单测（夹具 JSON）；验证：同上
- [x] 2.3 mc_resource 导出整理 + README 更新（原版对应物一节补充）；验证：`dart analyze` 零 issue

## 3. 应用接入与文档

- [x] 3.1 根 pubspec 声明 `assets/vanilla/26_2/` 目录资产；README 记录提取步骤（jar 来源示例、命令）；验证：`flutter pub get` 与 `flutter analyze` 通过
- [x] 3.2 对真实 jar 完整跑一次提取并冒烟读取（VanillaPack 读 atlas.json 与一个 blockstate）；验证：读取成功且产物不入库
  - 实施备注：26.2 的模型/贴图引用带 `minecraft:` 命名空间前缀（真实 jar 揪出），解析统一剥前缀；图集键去 `.png`；冒烟 1227 贴图、stone/oak_planks 全解析（grass_block 用 top 键，非缺陷）；冒烟脚本留作 tool/smoke_resource.dart
