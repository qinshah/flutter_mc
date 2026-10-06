# flutter_mc 项目执行规则

本文件是项目级执行规则真身；AGENTS.md 只放红线摘要与指针，按内容种类在本文件分节维护。
与 openspec/ 固化内容冲突时以 openspec 为准并回改本文件。

## 包脚手架

- 新建 Dart/Flutter 包 MUST 用 CLI 生成，禁止逐个手写文件搭骨架：
  - 纯 Dart 包：`dart create --template=package-simple <名>`
  - Flutter 包：`flutter create --template=package <名>`
- 生成后定制三件事：
  1. 清理模板示例（example/、示例实现、示例测试）
  2. pubspec：中文 description、`publish_to: 'none'`、按依赖方向补 path 依赖
  3. README 写明「原版对应物」（判据 mc-sources/minecraft-26.2）与首个预期 change

## 提交信息

- 遵循 Conventional Commits：`<type>(<scope>): <subject>`
- type 取 feat / fix / docs / build / chore / refactor / test
- scope 用包名或区域（如 `mc_wire`、`tool`、`openspec`）；跨多包的搬入类提交可用 `packages`
- subject 用中文一行说清"做了什么"；正文按需补充动机与验证结果（测试计数、分析结果）
