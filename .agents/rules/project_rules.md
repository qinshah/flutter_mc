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

## Flutter 规则

- **调试用 dart MCP**：遇到运行期报错/界面异常，先取真实证据再改码，禁止凭猜测盲改。实战流程：
  1. 后台起 driver 入口：`flutter run -t tool/driver_main.dart -d macos`（启用 driver 扩展；
     发行入口 main.dart 不掺调试代码）
  2. `dtd listDtdUris` → `dtd connect`：选 Workspace Root 为本项目的那个实例
     （flutter run 自建；IDE 启动的 app 挂 IDE 的 DTD）
  3. `get_runtime_errors` 看真实报错；`flutter_driver_command` 的 `tap` / `screenshot` /
     `scroll` / `get_diagnostics_tree` 复现与取证（screenshot 直接回图，看界面最直接）
  4. `hot_reload`（结构性改动用 `hot_restart`）后同法复验；`widget_inspector` 的
     `get_widget_tree` 可查树
  另有 `analyze_files`、`lsp`、`pub`、`vm_service` 可用。
- **状态管理用 provider**；**持久化用 hive_ce + hive_ce_flutter**。
  持久化边界：hive 只存 flutter_mc 专属数据（如界面设置、应用配置）；
  原版数据的持久化语义归 Java MC 侧（如 servers.dat、存档格式），不自创格式、不混存。

## 提交信息

- 遵循 Conventional Commits：`<type>(<scope>): <subject>`
- type 取 feat / fix / docs / build / chore / refactor / test
- scope 用包名或区域（如 `mc_wire`、`tool`、`openspec`）；跨多包的搬入类提交可用 `packages`
- subject 用中文一行说清"做了什么"；正文按需补充动机与验证结果（测试计数、分析结果）
