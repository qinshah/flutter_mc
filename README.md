# flutter_mc

Minecraft 官方客户端的 Flutter 复刻：连既有 MC 服务器，或在应用私有目录**托管本机服务端**（本地服务器），用服务器数据渲染 3D 世界，玩家输入上行。行为判据 = 本地参考源码 `mc-sources/minecraft-26.2`（只读、不入库），目标 Java→Dart 级忠实翻译；唯三处自由设计——3D 渲染（flutter_scene）、输入（Flutter）、运行时宿主（JVM 托管）；数据上行与自撰的控制面/配置读写不属自由设计，须逐行翻译。

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
cd packages/mc_wire && dart test       # 包内测试（多个包有测试）
dart analyze                           # 各纯 Dart 包内运行
dart run tool/extract_assets.dart extract "<官方 client.jar>"   # 提取资产+拼图集（构建期一次）
```

资产提取：从本机官方启动器 jar（如 `~/Library/Application Support/minecraft/versions/26.2/26.2.jar`）
提取方块资产到 `assets/vanilla/26_2/`（版本标记目录，gitignore 不入库），运行前执行一次。

## 本地服务器（本机托管）

在应用私有目录（`path_provider` 的 support 目录）托管一个原版系 Java 服务端（Paper 26.2），
作为服务器列表中的**一等公民条目**：可启停、可看状态与日志、可编辑配置；「单人世界」是它的
快捷入口（起服后自动连 `127.0.0.1:<端口>`）。控制面只走原版通道——状态/玩家等走 **26.2 管理
服务器**（JSON-RPC over WebSocket），任意指令走 **原版 RCON**（不自造协议、不解析日志推断。
**首版仅桌面**；Android 嵌入式 JVM 另开 change。

服务端 jar 属**构建期资产携带**：放入 `assets/server/26_2/`，**文件名不限**（目录下任意 `*.jar`
都会被枚举并落地，如 `paper-26.2.jar`、`paper-26.2-129.jar`；pubspec 逐目录声明，gitignore 不入库，
仅保留 `.gitkeep` 维持目录存在），**后续改为"使用时下载"**（FVM 式全局缓存 + 按实例 pin，切换时只换
产物解析实现）。也可在运行时把任意 `paper-26.2-*.jar` 放到实例私有根的 `artifacts/` 下（按 `mcVersion`
匹配），或直接在实例配置里填 `jarPath`（对照实测用）。
jar 缺失时构建仍通过，本地服务器入口置灰并提示放置位置与期望版本。桌面**不捆绑 JRE**，探测并
复用系统 JDK（Paper 26.2 需 **Java 25**）。首次启动前须同意服务端 EULA（未同意不写 `eula=true`
且不启动）。

## 流程与文档

- `openspec/` 是流程唯一权威：当前做什么、验收标准、变更是否完成
- `AGENTS.md` 是红线一页；文档与 openspec 冲突时以 openspec 为准
- 换 change 流程：`/openspec-propose`（立项）→ `/openspec-apply-change`（实施）→ `/openspec-archive-change`（归档）
