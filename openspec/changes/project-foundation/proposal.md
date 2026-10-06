# Proposal

## Why

flutter_mc 是 fscraft 的重构重启：定位为**纯 Minecraft 客户端**（只连既有 MC 服务器，照官方源码做 Java→Dart 翻译），而 fscraft 的 lib/ 已叠了两代架构（单人玩法核心 + 后加的远程多人 + benchmark/dev/debug 混杂），不宜继续演化。新项目需要先把包结构、文档权威与项目红线立起来，后续所有 change 才有稳定落点。

## What Changes

- 从 fscraft 原样搬入四个纯 Dart 包（含测试），归入 `packages/`，按新架构做必要调整：
  - `mc_nbt`（NBT 编解码）、`mc_wire`（帧/VarInt/压缩/连接）、`mc_session`（客户端会话状态机）、`mc_protocol_v26_2`（26.2 协议包 ID 与编解码）
- 新建三个包骨架（本 change 只立结构与占位，实现在后续 change）：
  - `mc_render`：原版渲染数据半边的翻译落点（模型烘焙、区块编译，产顶点数据）
  - `mc_resource`：资源包读取抽象（`PackResources` 式、来源可插拔）
  - `mc_ui`：MC 风格 Flutter 组件库（MCButton 等，API 照原版 `gui/components`）
- 建立文档三件套（openspec/ 为唯一流程权威，不另建 docs/ 树）：
  - `openspec/config.yaml` 补 `context`（不可从代码推断的约束）
  - `README.md`（仓库地图 + 运行方式）
  - `AGENTS.md`（红线内联一页，不做指针链）
- 建 `tool/` 资源提取 CLI 骨架：能打开官方 client jar 并枚举资产；完整提取管线留给后续 change
- `pubspec.yaml` 补上 packages/ 的 path 依赖

## Capabilities

### New Capabilities

- `project-structure`：包布局与依赖方向（包映射原版源码树）、包纯度边界（packages/ 纯 Dart、app 壳是 flutter_scene 唯一使用点）、版本包接入模式（`mc_protocol_v<ver>` 命名、装配点选择、禁版本号 if 分支）、文档权威与红线（mc-sources 只读、提取资产不入库）

### Modified Capabilities

（无——项目首个 change，尚无既有能力）

## Impact

- 新增 `packages/`（7 包）、`tool/`、根级 `README.md`、`AGENTS.md`；`openspec/config.yaml` 补 context
- `pubspec.yaml` 新增 path 依赖（mc_nbt / mc_wire / mc_session / mc_protocol_v26_2 等）
- `lib/` 本 change 不动（app 壳接线是后续 change）；验证靠 `dart analyze` 全仓通过 + 搬入包的既有测试全绿
- `mc-sources/` 只读不改；提取资产目录入 `.gitignore`
