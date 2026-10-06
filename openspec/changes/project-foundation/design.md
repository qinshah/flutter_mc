# Design

## Context

flutter_mc 目前是 Flutter 空壳（lib/ 仅 main.dart），OpenSpec 已初始化但无 specs。参考资产已就位：fscraft 有四个已验证的纯 Dart 协议包可搬；`mc-sources/` 有 minecraft-26.2 完整客户端源码作翻译判据。项目定位与总纲见 proposal.md「Why」。

## Goals / Non-Goals

**Goals:**

- 一次性立起 `packages/` 七包格局与依赖方向，后续 change 只在既有落点上填充
- 文档三件套（config.yaml context / README / AGENTS.md）承载不可推断的约束与红线
- 搬入包在本仓可解析、可分析、测试全绿

**Non-Goals:**

- 不写任何游戏逻辑：mc_render / mc_resource / mc_ui 只立骨架，app 壳不接线
- 不实现资源提取管线（本 change 只有能枚举 jar 资产的 CLI 骨架）
- 不实现运行时版本选择（单版本 26.2，装配点形态留给远程连接 change）
- 不引入 melos/workspace 工具链

## Decisions

### D1 总纲的工程表达：忠实翻译 + 三处自由区

原版 26.2 源码是行为唯一判据，翻译目标是"原版怎么从服务器数据算出结果，我们怎么算"。仅三处自由设计：3D 渲染交 flutter_scene、玩家输入取自 Flutter、数据上行给服务器。工程上的接缝选在**原版自身的分层处**：凡原版产出的中间数据形状（如 `ClientChunkCache` 的区块状态、`CompiledSectionMesh`/BufferBuilder 的顶点数据）照原样翻译成 Dart 类型，自由区只消费这些类型。这让"翻译是否忠实"可以被 golden 测试验证（对拍中间数据形状）。

备选：按 flutter 的习惯自由设计数据流 —— 放弃，因为用户明确要求 java→dart 级别的照搬，且对拍测试需要形状一致。

### D2 包映射表（已对照 mc-sources/minecraft-26.2 验证）

| 原版 26.2 | flutter_mc 包 | 本 change 动作 |
| --- | --- | --- |
| `net.minecraft.network` 编解码、NBT | mc_wire / mc_nbt / mc_protocol_v26_2 | 从 fscraft 搬入 |
| `client.multiplayer`（ClientPacketListener / ClientLevel / ClientChunkCache） | mc_session | 从 fscraft 搬入 |
| `client.resources`（资源包读取、模型 JSON 解析） | mc_resource | 新建骨架 |
| `client.resources.model` + `client.renderer` 数据半边（ModelBakery / BlockModel / TextureAtlas / SectionCompiler / VisGraph） | mc_render | 新建骨架 |
| `client.gui.components`（AbstractButton / Button / EditBox / …） | mc_ui | 新建骨架 |
| `client` 根 + renderer GPU 半边（Minecraft / MouseHandler / GameRenderer 等价物） | app 壳 lib/ | 后续 change |

### D3 依赖方向与包纯度

```
                     app 壳 lib/  ←—— flutter_scene 唯一使用点
                    /     |      \
          mc_render   mc_resource   mc_session → mc_protocol_v26_2
              (纯Dart)   (纯Dart)          → mc_wire → mc_nbt
                     \      |
                      mc_ui（唯一允许依赖 Flutter 的包）
```

- packages/ 全部纯 Dart，mc_ui 例外只到 Flutter 为止
- 包间只传纯数据类型；渲染、网络连接的生命周期归 app 壳
- mc_render / mc_resource 依赖 mc_nbt（读 NBT 资产）但不依赖 mc_session；mc_ui 不依赖任何 mc 包（外观资源经参数注入）

### D4 搬包：原样搬，按需最小调整

四包逐目录复制（含 7 个测试文件），然后做三类允许的调整：a) 根 pubspec 加 path 依赖并全仓 `dart analyze`；b) 清理指向 fscraft app 层的残留引用（若有）；c) 各包 README 补"原版对应物"一节。版本锚点、公开 API、文件组织不动——fscraft 已用它们打通 26.2 连服链路（归档 change `remote-multiplayer-26-2`），原样性本身就是资产。

备选：顺手重构改名 —— 放弃，避免"搬入"与"重构"混在一个 change 里互相牵制；后续 change 要改时再说。

### D5 新包骨架形态

每个新包 = pubspec（纯 Dart 或 Flutter，按 D3）+ `lib/<包名>.dart` 导出入口 + README 一节，README 必须写明：原版对应层次、职责边界（承接 D2 表）、首个预期 change。骨架不含占位实现代码，避免僵尸代码。

### D6 文档三件套内容要点

- **config.yaml `context`**：纯客户端定位、忠实翻译总纲与三处自由区、包纯度边界、版本包命名与禁版本号分支、mc-sources 只读、官方资产不入库。只写无法从代码推断的约束，10 行以内。
- **README**：一句话定位 → 仓库地图（D3 包图）→ 运行/分析命令 → 指向 openspec。
- **AGENTS.md**：红线内联一页，直接写正文不做指针链（fscraft 的三级指针跳转在小项目是负担）：mc-sources 只读、官方资产不入库、包纯度、版本包模式、禁改测试期望值、禁 --force 等。注意 fscraft 的"零网络"红线**不搬**——连 MC 服务器是本项目立身之本；网络方向约束（仅用户指定服务器、无遥测）以一句概括。

### D7 资源提取工具骨架

`tool/extract_assets.dart`：纯 Dart CLI，入参为用户本机官方 client jar 路径，能力仅限打开 zip 并按清单枚举 `assets/**`（分类计数输出）。真实提取、转换、随包打包留给专门的资源 change。产物目录约定 `build/extracted_assets/`（已被 Flutter 默认 gitignore 覆盖），gitignore 显式再补一条以防漂移。

## Risks / Trade-offs

- [搬入包携带 fscraft 隐性耦合] → 搬后逐包 analyze + 跑测试，残留引用当作发现记录在 tasks 勾选项，不静默清理
- [三个骨架包长期空置成僵尸] → 每个骨架 README 强制写"首个预期 change"，apply 验收时检查
- [单版本下装配点无真实分派压力，设计可能过/欠] → 装配点本 change 不实现，只把"版本实现从装配点取"写进 spec；首个真实分派在远程连接 change 落地时校准
- [AGENTS.md 与未来 spec 漂移] → spec 已有"文档冲突以 openspec 为准并回改"条款兜底

## Open Questions

- 第一批提取哪些资产类别（方块贴图/模型 JSON/字体/音效的取舍）—— 资源 change 立项时定
- mc_render 的第一个落地切片（建议区块编译 SectionCompiler 先于模型烘焙 ModelBakery）—— 该 change 立项时定
