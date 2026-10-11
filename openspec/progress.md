# 总体进度与翻译债清单

> 凡原版（`mc-sources/minecraft-26.2`）**有 Java 实现**，而本仓标为"简化 / 占位 / 未实现 /
> TODO"之处，都登记在此。**这些不是"自由设计"** —— 自由设计仅限两类环境差异：
> 3D 渲染后端（flutter_scene）与输入事件采集（Flutter 组件）。
> 见能力 `translation-debt`（`openspec/specs/translation-debt/spec.md`）。
>
> **口径**：按大类分组，每债一条 checkbox —— **未勾选 = 未完成**；补齐后勾选保留作记录。
> 本清单只登记事实，**不承诺时间**；补齐顺序按"观感影响 × 实施成本"另议。

---

## 1. 渲染：几何形状（影响观感·大）

- [ ] 半砖/楼梯/薄皮/竹子/睡莲等按 1×1×1 整方块渲染
  - 原版：`net/minecraft/world/level/block/BlockShapes.java`、`BlockRenderLayer`、`RenderShape`
  - 我们：`packages/mc_render/lib/src/mesher.dart` 文件头「首版简化」
  - 后果：台阶像方块、竹子像柱子、海带像冰柱
  - 备注：`RenderShape` 枚举只有 MODEL/INVISIBLE 两值，不足以分类；须改读模型 `elements`

## 2. 渲染：光照（影响观感·大）

- [ ] 无 AO / 平滑光照 / lightmap，只有面朝向明暗（顶 1.0 / 底 0.5 / 南北 0.8 / 东西 0.6）
  - 原版：`client/renderer/Lightmap.java`、`LightmapRenderStateExtractor.java`、`LevelRenderer` 的光照传播
  - 我们：`packages/mc_render/lib/src/mesher.dart`「无 AO/平滑光照」
  - 后果：洞穴全黑、室内无明暗过渡

## 3. 渲染：天空与昼夜（影响观感·中）

- [ ] 天空色写死（`lib/game/game_screen.dart` `backgroundColor: Color(0xFF87CEEB)`），
      无昼夜循环、无星空/日月/云
  - 原版：`client/renderer/SkyRenderer.java`、`client/gui/screens/LevelLoadingScreen` 的天空绘制
  - 备注：昼夜**时间数据**已随会话下发（`remote-play` 能力），但未用于渲染

## 4. 天气（影响观感·中）

- [ ] 无天气系统（雨/雪）
  - 原版：`client/renderer/WeatherEffectRenderer.java` + `ClientLevel` 的雨雪强度
  - 备注：属「产品完整性」维度

## 5. 资源：模型与图集（影响正确性·中）

- [ ] 同键多变体"取首个"（`packages/mc_resource/lib/src/block_models.dart:30`）
      —— 随机权重方块（草/花变体）每次取同一个
- [ ] 图集 UV 不写 padding（`atlas_uv.dart:11`）—— 图集边缘可能串色
  - 原版：`client/resources/model/BlockModel.java`、`model/textures/SpriteLoader.java`

## 6. 方块分类（影响正确性·中）

- [ ] 渲染层判定靠名字启发式名单（`packages/mc_render/lib/src/block_semantics_v262.dart`
      的 `_crossNames` 40 项）；kelp / seagrass / vine / lily_pad / bamboo 未命中 →
      落 opaque 层按实心立方体渲染
  - 原版：`BlockRenderLayer` 注册表（**不在 mc-sources 源码树**，已编译进客户端渲染库）
  - 备注：判据源改为 jar 内 2657 个模型 JSON（构建期数据）

## 7. GUI 控件（影响产品完整性·大）

- [ ] 控件覆盖约 1/11：原版 `client/gui/components/` 共 65 个，本仓
      `packages/mc_ui/lib/src/` 有 Button/CycleButton/EditBox/FacePainter/IconButton/
      SliderButton（另加 SpriteIconButton、触控按钮样式——见 change
      `game-screens-touch-input`）

## 8. GUI 屏幕（影响产品完整性·大）

- [ ] 屏幕覆盖约 9/39：原版 `client/gui/screens/` 共 39 个，本仓 `lib/screens/` 多数
      标注"简化"；title_screen 的 splash、服务器图标为占位
- [ ] PauseScreen 的进度/统计/好友/举报玩家四类入口置灰（对应
      AdvancementsScreen / StatsScreen / SocialInteractionsScreen / FriendsOverlayScreen
      未实现）—— change `game-screens-touch-input` 引入
- [ ] `handleKeybinds` 中 togglePerspective / attack / use / drop / swapOffhand 等
      分支留空待补 —— change `game-screens-touch-input` 引入
- [ ] 物品栏为"点选替换选中槽位"的最小实现；原版完整 Inventory（36 格 +
      carried/drag 语义）未实现 —— change `game-screens-touch-input` 引入

## 9. 音频（影响产品完整性·大）

- [ ] 无音效、无环境声、无音乐
  - 原版：`client/sounds/`（`SoundEngine`、`AudioStream`、`SoundManager` 等）+ `SoundEvents`
  - 我们：无（`packages/mc_session/lib/src/mc_session_base.dart:1` 有 TODO 标记）

## 10. 指针捕获（影响正确性·小，平台依赖上游）

- [ ] Windows/ohos 等平台 pointer_lock `isSupported=false`，指针捕获退化为
      onPointerMove 断流近似 —— change `game-screens-touch-input` 引入
  - 原版：`MouseHandler.java:404-429` GLFW 212995/212993 真捕获
  - 备注：等 pointer_lock 上游支持 Windows（Raw Input + ClipCursor）后回访；
    macOS 已走真捕获。**移动端按用户决策（2026-10-07）完全不参与指针捕获**
    （MouseHandler._isDesktop 门控），视角走触控拖动。

## 11. 区块流：光照引擎与 onChunkLoaded 附带面（影响正确性·中）

- [ ] `ClientChunkCache.replaceWithPacketData` 的光照摄入面未建模——原版
      `ClientPacketListener.java:843-857` 收列后 `queueLightUpdate`（applyLightData
      + enableChunkLight + setSectionRangeDirty），我们无光照引擎（join-and-render
      起即简化），区块以服务器列数据直接网格化 —— change `chunk-streaming-align`
      接入存储环时保持现状
- [ ] `ClientLevel.onChunkLoaded`（:522-525）的 tint 缓存失效与实体 tick 启动
      面未建模（无对应物：tint 已在 mesher 内联，实体未实现）
- [ ] 存储环缩窗迁移对窗外列**补发卸载事件**——原版 `updateViewRadius`
      （ClientChunkCache.java:137-145）对未迁移列静默丢弃；我们 MUST 发事件
      （渲染端"卸载必达"契约，spec 缩窗场景）—— 有意偏差，勿"修"

## 12. 实体物理（影响正确性·中）

- [ ] 水物理分支缺失：vanilla `LivingEntity.travel` 三分支（air/water/lava，
      LivingEntity.java travel 系），我们只有 air 分支（`lib/world/entity/player/` 无
      `travelInWater` 对应物，`isInWater`/浮力/水中摩擦/水中速度属性均未建模）
  - 后果：浅水区移动速度/浮沉与原版不一致（2026-10-12 怼墙抽搐诊断中确认，
    非 root cause 但影响轨迹复算与对照实验，见 `docs/walk-jitter-diagnosis.md`）
- [x] ~~建盒半宽 double 化~~（2026-10-12 已还债：`Aabb` 按
      `EntityDimensions.makeBoundingBox`（EntityDimensions.java:19-22）的 float
      语义建盒——float32(0.6)/2 = 0.30000001192092896、头顶 y + float32(1.8)。
      曾经此差 1.19e-8 被 Paper `hasNewCollision` 判 CLIPPED_INTO_BLOCK 回拉抽搐）

---

## 命名 / 路径偏离（非"债"，是纪律偏离，需逐步改正）

- [x] ~~`LivingEntity` + `Player` → `player_controller.dart`~~（2026-10-07 已还债：拆为
      `lib/client/player/local_player.dart`（LocalPlayer）、`lib/world/entity/player/` 下的
      `player.dart` / `abilities.dart` / `input.dart`，路径从 `net/minecraft/` 对齐 `lib/`）
- [ ] `KeyMapping` → 现为 `lib/game/key_map.dart`，应改名 key_mapping.dart
- [ ] `LevelRenderer` → 现为 `packages/mc_render/lib/src/mesher.dart`，应对齐命名
- [ ] `BlockRenderLayer` → 现为 `block_semantics_v262.dart`，应对齐命名
- [ ] `ClientPacketListener` / `Connection` → 现为 `remote_session.dart`（两个 Java 类合一 + 改名）
- [ ] `MouseHandler` → 无对应文件（change `game-screens-touch-input` 落 `client/gui/` 时补齐）
- [ ] 旧屏幕路径偏离：title/confirm/菜单链屏幕在 `lib/screens/`，按规则应为
      `lib/client/gui/screens/`（change `game-screens-touch-input` 新增的
      pause_screen / creative_mode_inventory_screen 已落正位）

> 见能力 `project-structure` 的「命名与文件路径照原版」需求。逐步改正会牵动导入关系，
> 建议在相关 change 中顺手改，不单独做大规模重命名。
