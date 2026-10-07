# 翻译债清单

>凡原版（`mc-sources/minecraft-26.2`）**有 Java 实现**，而本仓标为"简化 / 占位 / 未实现 /
> TODO"之处，都登记在此。**这些不是"自由设计"** —— 自由设计仅限两类环境差异：
> 3D 渲染后端（flutter_scene）与输入事件采集（Flutter 组件）。
> 见 `openspec/specs/translation-debt/spec.md`。

**排期**：本清单只登记事实，**不承诺时间**。补齐顺序按"观感影响 × 实施成本"另议。

**规模**：9 类，其中 3 类影响产品完整性（音频、GUI 主体、天气）。

---

## 1. 渲染：几何形状（影响观感·大）

| 项 | 内容 |
|---|---|
| 原版 | `net/minecraft/world/level/block/BlockShapes.java`、`BlockRenderLayer`、`RenderShape` |
| 我们 | `packages/mc_render/lib/src/mesher.dart` 文件头「首版简化」 |
| 现状 | 一律按 1×1×1 整方块；半砖/楼梯/薄皮/竹子/睡莲等全被拉成整块 |
| 后果 | 台阶像方块、竹子像柱子、海带像冰柱（用户已多次反馈） |
| 备注 | `RenderShape` 枚举本身只有 MODEL/INVISIBLE 两值，**不足以分类**；须改读模型 `elements` |

## 2. 渲染：光照（影响观感·大）

| 项 | 内容 |
|---|---|
| 原版 | `client/renderer/Lightmap.java`、`LightmapRenderStateExtractor.java`、`LevelRenderer` 的光照传播 |
| 我们 | `mesher.dart`「无 AO/平滑光照」 |
| 现状 | 只有面朝向明暗（顶 1.0 / 底 0.5 / 南北 0.8 / 东西 0.6），无 AO、无平滑光照、无 lightmap |
| 后果 | 洞穴全黑、室内无明暗过渡 |

## 3. 渲染：天空与昼夜（影响观感·中）

| 项 | 内容 |
|---|---|
| 原版 | `client/renderer/SkyRenderer.java`、`client/gui/screens/LevelLoadingScreen` 的天空绘制 |
| 我们 | `lib/game/game_screen.dart:614` `backgroundColor: const Color(0xFF87CEEB)` ← 注释自写"占位" |
| 现状 | 天空色写死，无昼夜循环、无星空/日月/云 |
| 备注 | 昼夜**时间数据**已随会话下发（`remote-play` 能力），但未用于渲染 |

## 4. 天气（影响观感·中）

| 项 | 内容 |
|---|---|
| 原版 | `client/renderer/WeatherEffectRenderer.java` + `ClientLevel` 的雨雪强度 |
| 我们 | 无 |
| 备注 | 属于「产品完整性」维度：无天气系统即无环境沉浸 |

## 5. 资源：模型与图集（影响正确性·中）

| 项 | 内容 |
|---|---|
| 原版 | `client/resources/model/BlockModel.java`、`model/textures/SpriteLoader.java` |
| 我们 | `packages/mc_resource/lib/src/block_models.dart:30`（同键多变体"取首个"）、`atlas_uv.dart:11`（不写 padding） |
| 后果 | 随机权重方块（如草/花变体）每次取同一个；图集边缘可能串色 |

## 6. 方块分类（影响正确性·中）

| 项 | 内容 |
|---|---|
| 原版 | `BlockRenderLayer` 注册表（**不在 mc-sources 源码树**，已编译进客户端渲染库） |
| 我们 | `packages/mc_render/lib/src/block_semantics_v262.dart` 的名字启发式名单（`_crossNames` 40 项） |
| 后果 | kelp / seagrass / vine / lily_pad / bamboo 未命中 → 落opaque 层 → 按实心立方体渲染 |
| 备注 | 原版注册表抄不到（源码树无该类）；判据源改为**jar 内 2657 个模型 JSON**（构建期数据） |

## 7. GUI 控件（影响产品完整性·大）

| 项 | 内容 |
|---|---|
| 原版 | `client/gui/components/` —— **65 个** |
| 我们 | `packages/mc_ui/lib/src/` —— **6 个**（Button/CycleButton/EditBox/FacePainter/IconButton/SliderButton） |
| 现状 | 控件层在还原（对应 `gui/components`），但覆盖面约 1/11 |

## 8. GUI 屏幕（影响产品完整性·大）

| 项 | 内容 |
|---|---|
| 原版 | `client/gui/screens/` —— **39 个** |
| 我们 | `lib/screens/` —— **9 个**（title/confirm/screen/join_multiplayer/join_flow/manage_server/direct_join_server/server_selection_list/options.video_settings） |
| 现状 | 多数屏幕标注"简化"；`title_screen` 的splash、服务器图标为占位 |
| 后果 | 多人流程外的内容（世界选择、选项全量、聊天、暂停菜单、Realms…）不可达 |

## 9. 音频（影响产品完整性·大）

| 项 | 内容 |
|---|---|
| 原版 | `client/sounds/`（`SoundEngine`、`AudioStream`、`SoundManager` 等）+ `SoundEvents` |
| 我们 | 无（`packages/mc_session/lib/src/mc_session_base.dart:1` 有 TODO 标记） |
| 后果 | 无音效、无环境声、无音乐 |

---

## 命名 / 路径偏离（非"债"，是纪律偏离，需逐步改正）

| 原版 | 我们 | 问题 |
|---|---|---|
~~`LivingEntity` + `Player` → `player_controller.dart`~~（2026-10-07 已还债：拆为
`lib/client/player/local_player.dart`（LocalPlayer）、`lib/world/entity/player/` 下的
`player.dart` / `abilities.dart` / `input.dart`，路径从 `net/minecraft/` 对齐 `lib/`）
| `KeyMapping` | `key_map.dart` | 改名 |
| `LevelRenderer` | `mesher.dart` | 改名 |
| `BlockRenderLayer` | `block_semantics_v262.dart` | 改名 |
| `ClientPacketListener` / `Connection` | `remote_session.dart` | 两个 Java 类合一 + 改名 |
| `MouseHandler` | （无对应文件） | — |

> 见能力 `project-structure` 的「命名与文件路径照原版」需求。逐步改正会牵动导入关系，
> 建议在相关 change 中顺手改，不单独做大规模重命名。