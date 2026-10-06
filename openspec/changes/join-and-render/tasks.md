# Tasks

## 1. mc_session 装配点

- [x] 1.1 `SessionAssembly`：protocol→实现的注册表 + `connectFor`（未注册版本抛 UnsupportedProtocolError）；RemoteSession 接受装配产物；验证：单测（注册/未注册两分支），`dart test` 全绿
- [x] 1.2 mc_session.dart 导出装配点；验证：analyze 零 issue

## 2. mc_render 网格器

- [x] 2.1 读 fscraft `mesher.dart` 与 mc_session 区块/调色板数据结构，写移植笔记（数据源差异清单）
- [x] 2.2 移植网格器：区块→分区几何（顶点/UV/索引，面剔除），UV 由注入的方块面→图集矩形函数提供；纯 Dart、不碰引擎类型；简化点注释；验证：golden 单测（固定小区块→期望顶点数/UV 快照），`dart test` 全绿
- [x] 2.3 mc_render README 更新（原版对应物一节落到实现）；验证：analyze 零 issue

## 3. app 壳游戏屏

- [x] 3.1 读 flutter_scene-idioms skill + fscraft SceneView/相机用法，定 GameScreen 骨架（SceneView + 会话事件订阅 + 区块网格挂载）
- [ ] 3.2 移植 fscraft collision/player 物理（世界查询换 mc_session 区块）；输入 KeyboardListener（WASD/空格）→ 移动 → MovePlayer 上行；验证：物理单测（纯 Dart 部分）
- [x] 3.3 移植 sky_model（时间源 TimeUpdated）；贴图加载（rootBundle 图集 → ui.Image → flutter_scene 材质）；验证：analyze 零 issue
- [ ] 3.4 多人屏加入/直连接装配点：成功 push /game，失败 SnackBar 错误；验证：widget 测试（错误分支 + 路由）

## 4. 端到端验收

- [ ] 4.1 起 Paper（java -jar paper-26.2-129.jar nogui），dart MCP driver 入口真连 127.0.0.1：进世界、截屏见地形、走动、跳、昼夜推进；验证：截图 + get_runtime_errors 为零
- [ ] 4.2 全仓回归：8 项 analyze + 全部测试；红线 grep（flutter_scene 仅 lib/）；验证：全绿
