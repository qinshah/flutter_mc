# Tasks

## 1. 搬入 fscraft 四包

- [x] 1.1 复制 fscraft `packages/mc_nbt` 到本仓 `packages/mc_nbt`（含源码与空测试目录），补各包间 path 依赖所需的相对路径检查；验证：`cd packages/mc_nbt && dart pub get && dart analyze` 无 error
- [x] 1.2 复制 `mc_wire` 并同样接入；验证：`cd packages/mc_wire && dart pub get && dart analyze && dart test` 4 个测试全绿
- [x] 1.3 复制 `mc_session` 并同样接入；验证：`cd packages/mc_session && dart pub get && dart analyze && dart test` 2 个测试全绿
- [x] 1.4 复制 `mc_protocol_v26_2` 并同样接入；验证：`cd packages/mc_protocol_v26_2 && dart pub get && dart analyze && dart test` 1 个测试全绿
- [x] 1.5 根 `pubspec.yaml` 加四个包的 path 依赖；验证：根目录 `flutter pub get` 成功解析整图
- [x] 1.6 逐包 grep 指向 fscraft app 层/路径的残留引用，按设计 D4b 最小清理并在此注明改了什么；验证：`grep -rn "fscraft" packages/` 无结果（README 中"fscraft"出处说明除外）
  - 清理记录：测试数据改名（mock_login_server brand 字段与 5 处 playerName 'fscraft'→'flutter_mc'）；出处性注释/描述重写去掉旧项目名与旧 change 名（mc_nbt.dart、nbt_reader.dart、mc_wire.dart、mc_session.dart、两个 pubspec description）；出处由 git 历史与本 change 记录承载
- [x] 1.7 四包各补 README「原版对应物」一节（mc_nbt/mc_wire/mc_protocol_v26_2 → 网络编解码与 NBT；mc_session → `client.multiplayer`）；验证：对照 `mc-sources/minecraft-26.2/net/minecraft/` 层次名无误

## 2. 新建三包骨架

- [x] 2.1 建 `packages/mc_render`：纯 Dart pubspec（依赖 mc_nbt）+ 空 `lib/mc_render.dart` 导出口 + README 写明原版对应（`client.resources.model` + `client.renderer` 数据半边：ModelBakery/SectionCompiler 等）与首个预期 change（区块编译切片）；验证：`dart pub get && dart analyze` 无 error
- [x] 2.2 建 `packages/mc_resource`：纯 Dart pubspec（依赖 mc_nbt）+ 空导出口 + README 写明原版对应（`client.resources`）与首个预期 change（PackResources 式资源抽象 + 提取管线）；验证：同上
- [x] 2.3 建 `packages/mc_ui`：**Flutter** 包 pubspec（依赖 flutter，禁 flutter_scene）+ 空导出口 + README 写明原版对应（`client.gui.components`：Button/EditBox 等）与首个预期 change（MCButton）、外观资源经参数注入不捆官方资产；验证：`flutter pub get && flutter analyze` 无 error
  - 按用户要求，三包均用 CLI 生成（`dart create --template=package-simple` ×2、`flutter create --template=package` ×1）后清理模板示例
- [x] 2.4 根 `pubspec.yaml` 加三个骨架包的 path 依赖；验证：根目录 `flutter pub get` 成功

## 3. 文档三件套

- [x] 3.1 `openspec/config.yaml` 填 `context`（按设计 D6 要点：纯客户端定位、忠实翻译总纲与三处自由区、包纯度、版本包模式、mc-sources 只读、官方资产不入库，10 行内）；验证：`openspec context --json` 正常返回无解析错误
- [x] 3.2 重写根 `README.md`：一句话定位 → D3 包图 → 常用命令 → 指向 openspec/；验证：文中每条命令实际可运行
- [x] 3.3 写 `AGENTS.md` 红线一页（按设计 D6：mc-sources 只读、官方资产不入库、包纯度、版本包模式、禁改测试期望值、禁 --force 等；网络约束为"仅连用户指定的 MC 服务器、无遥测"，**不搬** fscraft 零网络红线）；验证：逐条对照 spec `project-structure` 无冲突
- [x] 3.4 `.gitignore` 增补提取产物目录显式条目，确认 `mc-sources/` 与 `packages/*/` 不被忽略的既有规则不受影响；验证：`git check-ignore mc-sources` 通过且 `git status --porcelain` 中 packages/ 新文件正常可见
  - 观察：gitignore 沿用自 fscraft，尚有 dashcraft/、vanilla 资产导入等旧条目（规则无害），留给后续 hygiene change 清理

## 4. 资源提取工具骨架

- [x] 4.1 写 `tool/extract_assets.dart`：纯 Dart CLI，入参为本机官方 client jar 路径，打开 zip 按 `assets/` 前缀分类计数输出，不写任何文件；`--help` 可用、缺参明确报错；注释注明真实提取留给后续资源 change（产物约定目录 `build/extracted_assets/`）；验证：用任意小 zip 冒烟运行输出分类计数，目标 jar 未被修改
  - 实现依赖根 dev_dependencies 新增 archive ^4.0.0（解析为 4.3.0）；冒烟用假 zip（assets/minecraft/textures ×2、models ×1）验证计数、md5 前后一致、缺参 exit 64
- [x] 4.2 README 常用命令一节收入该工具用法；验证：按 README 命令运行成功

## 5. 集成验收

- [x] 5.1 全仓静态检查：根目录 `flutter analyze` 加七包各自 `dart analyze`（mc_ui 用 flutter analyze）均 0 issue；验证：输出无 error/warning
- [x] 5.2 搬入包测试汇总重跑：四个包 `dart test` 全绿；验证：合计 7 个测试通过
  - 实际计数：mc_wire 51 + mc_session 6 + mc_protocol_v26_2 23 = 80 个用例全绿（"7"是搬入的测试文件数）；mc_nbt 在 fscraft 即无测试目录，维持现状
- [x] 5.3 结构红线抽查：`grep -rn "package:flutter_scene" packages/` 无结果、`grep -rn "package:flutter/" packages/*/lib` 仅 mc_ui 命中；`git status` 显示 mc-sources/ 无改动；验证：三条命令输出符合预期
  - flutter 引用当前为零命中——骨架尚无 import，比预期更干净；mc_ui 落地 MCButton 时按 spec 场景只允许它命中
