# flutter_mc

Minecraft 官方客户端的 Flutter 复刻（纯客户端）：只连既有 MC 服务器，用服务器数据渲染 3D 世界，玩家输入上行。行为判据 = 本地参考源码 `mc-sources/minecraft-26.2`（只读、不入库），目标 Java→Dart 级忠实翻译；唯三处自由设计——3D 渲染（flutter_scene）、输入（Flutter）、数据上行。

## 仓库地图

包映射原版源码树，每个包的「原版对应物」见各包 README：

| 包 | 原版对应 | 状态 |
| --- | --- | --- |
| app 壳 `lib/` | `client` 根 + renderer 的 GPU 半边（平台绑定层） | 待实现 |
| `packages/mc_session` | `client.multiplayer` 会话编排与状态摄入 | 自 fscraft 搬入，26.2 连服已验证 |
| `packages/mc_protocol_v26_2` | `network.protocol.*` 26.2 包类型与编解码 | 自 fscraft 搬入 |
| `packages/mc_wire` | `network` 传输核心（VarInt/分帧/压缩/阶段） | 自 fscraft 搬入 |
| `packages/mc_nbt` | `nbt` + 网络形态 NBT | 自 fscraft 搬入 |
| `packages/mc_render` | 渲染数据半边（ModelBakery / SectionCompiler） | 骨架 |
| `packages/mc_resource` | 资源包抽象（`server.packs.resources` 等） | 骨架 |
| `packages/mc_ui` | `client.gui.components` MC 风格控件 | 骨架 |

依赖方向：app 壳 → mc_render / mc_resource / mc_session；mc_session → mc_protocol_v26_2 → mc_wire → mc_nbt；mc_ui 只依赖 Flutter。`packages/` 全纯 Dart（mc_ui 是唯一例外，且只到 Flutter 为止）；flutter_scene 只允许 app 壳使用。

## 常用命令

```bash
flutter pub get                        # 根依赖（含 packages/ 全部 path 依赖）
flutter analyze                        # app 壳静态检查
cd packages/mc_wire && dart test       # 包内测试（mc_wire / mc_session / mc_protocol_v26_2 有测试）
dart analyze                           # 各纯 Dart 包内运行
dart run tool/extract_assets.dart <client.jar>   # 盘点官方 jar 内 assets/ 资产（只读）
```

## 流程与文档

- `openspec/` 是流程唯一权威：当前做什么、验收标准、变更是否完成
- `AGENTS.md` 是红线一页；文档与 openspec 冲突时以 openspec 为准
- 换 change 流程：`/openspec-propose`（立项）→ `/openspec-apply-change`（实施）→ `/openspec-archive-change`（归档）
