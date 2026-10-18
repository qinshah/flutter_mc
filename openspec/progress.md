# 总体进度与翻译债清单

> 凡原版（`mc-sources/minecraft-26.2`）**有 Java 实现**，而本仓标为"简化 / 占位 / 未实现 /
> TODO"之处，都登记在此。**这些不是"自由设计"** —— 自由设计仅限三类环境差异：
> 3D 渲染后端（flutter_scene）、输入事件采集（Flutter 组件）、运行时宿主（JVM 托管）。
> 其中"运行时宿主"**只豁免"承载方式"**，被托管物自身的差异仍按翻译债登记（见第 14 项）。
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
- [ ] blockstate 变体旋转 uvlock 的**转置情形**矩形 UV 丢字段方向（2026-10-17 登记）
  - 原版：`FaceBakery.java:144-151` 逐顶点烘焙 UV——少数（群, 面）组合下最终
    UV 场相对模板是转置的（u 随模板 cv 变、v 随模板 cu 变；实证 east 面 + x=90），
    四顶点 UV 不构成轴对齐矩形沿模板轴的绑定
  - 我们：`packages/mc_resource/lib/src/face_bakery.dart` `_bakeFaceUvs` 检测到
    转置时退化为两通道 min/max 包围矩形（`BoxFace` 只有 (u1,v1,u2,v2) 表示）
  - 后果：该类面的纹理方向（90° 旋转）与原版不同；位置与朝向仍正确
- [ ] mesher 面模板角绑定与原版在 east/north 面不一致（2026-10-17 登记）
  - 原版：`FaceInfo.java:10-46` 各面取角 + `CuboidFace.java:77-83` 统一
    v0=(minU,minV)…v3=(maxU,minV) 绑定
  - 我们：`packages/mc_render/lib/src/mesher.dart` `_boxCorners` 用自配的
    flip 修正（east 面 u 翻转、north 面 180°）近似达成同效果，但模板与原版
    不逐项对应；整块路径的历史近似
  - 后果：整块六面的 UV 角对应与原版存在未逐项核对的面；楼梯等烘焙面
    （矩形已按原版绑定提取）经该路径重映射后方向可能再偏——单一木板纹理
    场景不可见，混贴图方块需回访

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

## 13. 方块碰撞形状近似（影响正确性·小，2026-10-17 登记）

- [ ] 未覆盖族兜底整块（原版是每方块白名单 `BlockStateDefinition` 逐类建模）
  - 我们：`packages/mc_render/lib/src/block_collision_shapes.dart` `_build` 末尾
    `VoxelShape.full()` 兜底
- [ ] 墙（wall）碰撞臂用栅栏参数近似
  - 原版：`WallBlock.makeShapes`（WallBlock.java:66-74）碰撞 = post
    `column(8, 0, 24)`（UP 时）+ 臂 `boxZ(6, 0, 24, 0, 11)`——臂厚 6/16、
    post 宽 8/16，且 low/tall 在**碰撞层同形**（:67 wallTop=postHeight=24）；
    我们：`_crossCollision(props, 1.5)`（post 4/16 宽、臂厚 4/16 深 8/16）
- [ ] 脚手架碰撞整块化
  - 原版：`ScaffoldingBlock` 碰撞随 bottom/support 变化（顶部可站立边缘）
  - 我们：`_scaffolding` 返回整块（首切片）
- [x] ~~栅栏门开启态碰撞为两端柱~~（2026-10-17 已还债：`getCollisionShape`
  开启 → 空（FenceGateBlock.java:105-108），`in_wall` 只改视觉 shape）
- [x] ~~楼梯旋转语义直写~~（2026-10-17 已还债：改用 `Shapes.rotate`
  （BLOCK_ROT_Y_90/180/270 + INVERT_Y，Shapes.java:301-330/:390-403，
  OctahedralGroup.java:34-42/:65-73）从 NORTH 基准旋出四向 map，
  StairBlock.java:40-48 逐行对应；`Shapes.or` 补极大盒合并对齐原版
  离散体素集的吞并语义）

---

## 14. 服务端本体：未翻译，改为外部托管（影响范围·大，2026-10-17 登记）

> 本项为 change `local-server-host` 登记。**"运行时宿主"（JVM 托管）只豁免"承载方式"**，
> 不豁免被托管物：下面这些原版有 Java、本仓不翻译而改为外部运行的部分，仍是翻译债。

- [ ] 服务端本体未翻译，改为托管外部原版系服务端产物（Paper 26.2）
  - 原版：`net/minecraft/server/MinecraftServer.java`、`net/minecraft/server/dedicated/DedicatedServer.java`、
    `net/minecraft/server/Main.java`、`net/minecraft/server/Eula.java`，以及服务端侧的
    世界生成 / 光照 / tick / 实体 AI / 区块 IO / 服务端协议方向（`server/**`、`world/**`
    的服务端取值路径）
  - 我们：不翻译，改为在应用私有目录托管外部 Java 服务端（见能力 `local-server-host`）；
    承载方式属第三类自由设计"运行时宿主"，判据见 `AGENTS.md`
  - 后果：服务器行为由所托管的产物决定；版本必须与客户端锚点同版，产物缺失即该功能不可用
  - 备注：本项**不是**"补齐计划"，而是"确认不做翻译"的登记——如日后改为 Dart 侧翻译，
    本项转为待还债

---

## 15. 单机 ESC 暂停/继续 与 世界列表屏的两处省略（影响正确性/完整性·小，2026-10-18 登记）

> 本项为 change `local-server-host` 登记。用户明确"单机 ESC 同步暂停/继续"本期可遗留。

- [ ] 单机 ESC 暂停未翻译（原版暂停的是**内嵌服务端**的 tick，不只是客户端）
  - 原版：`IntegratedServer.java:147-160` —— `paused = Minecraft.isPaused() || 玩家列表为空`，
    暂停时走 `tickPaused()`（`:188`，只推进必要系统）；客户端侧 `Minecraft.pauseGame`
    （`Minecraft.java:1670`）/`isPaused`（`:2697`）。
  - 我们：本地服务端是**外部托管进程**（见第 14 项），ESC 目前只影响客户端渲染，
    服务端照常 tick（世界仍在跑）。
  - 建议还债路径：经 RCON/管理服务器下发 `tick freeze` / `tick unfreeze`
    （判据 `TickCommand.java:52-53`、`:109-128` 的 `setFreeze` →
    `ServerTickRateManager.setFrozen`），在 `/game` 的 ESC 菜单开关时同步下发。
- [ ] `SelectWorldScreen` / `EditWorldScreen` 的若干省略（本期未做）
  - 原版 `SelectWorldScreen.java:55`（搜索框 `selectWorld.search`）、`:98-101`
    （「重新创建」`selectWorld.recreate`）。
  - 原版 `EditWorldScreen.java:42/77`（重置图标）、`:43/81`（打开文件夹）、
    `:44/84`（备份）、`:45/88`（备份文件夹）、`:46/102`（优化世界）。
  - 我们：`lib/screens/worldselection/select_world_screen.dart` 与
    `edit_world_screen.dart` 未实现上述项（列表条目少；"重新创建"对托管实例是破坏性操作，
    且改名已覆盖原版该屏的主体语义——世界生成参数本就不能在编辑屏改）。

---

## 16. Android 进程内 JVM 承载：许可受限登记 + 承载口径变化（影响范围·中，2026-10-18 登记）

> 本项为 change `android-embedded-jvm-host` 登记，分两节：**受限项（许可）**与**承载口径变化**。

### 16.1 受限项：GPL 件已移除 ⇒ 受限登记撤销（仓库级 LICENSE 仍待确定）

- [x] ~~**本仓分发许可受限**~~（**已解除**：GPL 件从未随本仓分发）
  - 曾引入又已删除的 GPL 件：
    - `android/app/src/main/cpp/jre_launcher.c` —— **GPLv2 + Classpath exception**
      （Oracle OpenJDK 派生；承载方式参照 FCL 的 `FCL/src/main/jni/jre_launcher.c`）。
      **2026-10-18 已删除**：真机实测 `JLI_Launch` 必然 `execve` 顶替应用进程映像，
      承载改用 `JNI_CreateJavaVM`（JNI 标准 API），不再需要该派生源。
  - 现存的第三方 native 件（来源与许可全文见
    `android/app/src/main/cpp/third_party/NOTICE.md`）：
    - `third_party/androidnsbypass/` —— **MIT**
      （`nsbypass.c:1` 的 `SPDX-License-Identifier: MIT`、`Copyright (c) 2026 alexytomi`；
      逐文件核对：MIT 覆盖多数文件，**BSD-2-Clause 只覆盖**
      `include/liblinkernsbypass_compat/android_linker_ns.h`，`Copyright © 2021 Billy Laws`）；
      来源：FoldCraftLauncher 仓库 vendored 的 androidnsbypass 子模块
      （FCL 的 `CMakeLists.txt` 注明 vendor 自 Amethyst-Android `616dc33`）。
    - Android 侧 Gradle 依赖：`org.apache.commons:commons-compress`（Apache-2.0）、
      `org.tukaani:xz`（Public Domain）——仅解 `.tar.xz`，非 native 代码。
  - 结论：native 层现只含 MIT / BSD-2-Clause 件，**本仓分发不再因 GPL 受限**；
    但**仓库目前仍无 LICENSE 文件**，对外 MUST NOT 声称本仓为宽松许可，许可证口径待定。
  - 判据：`android/app/src/main/cpp/third_party/NOTICE.md` 第 1–3 节、
    `.../androidnsbypass/LICENSE`、`.../LICENSE-BSD-2-Clause`。

### 16.2 承载方式：Android 改走**进程内 JVM**（第三类自由设计，非债）

- [x] Android 上被托管服务端的承载方式为**进程内 JVM**（native `dlopen` JRE →
      `JNI_CreateJavaVM`，**不经** `JLI_Launch`——后者必然 `execve` 顶替进程映像，见 16.3），
      **不再**走子进程（Android 无系统 JVM；targetSdk ≥ 29 的进程不能 `execve` 应用可写目录）。
  - 这**不是债**——"运行时宿主"只豁免承载方式。登记目的是记明由此产生的**口径变化**：
    - 停止超时**不再回落强杀**（进程内无从单独终止该 JVM）→ 转报告失败并保留日志与状态。
      已按平台重述 `local-server-host` 的「进程生命周期可控可观测」（见该 change 的 delta 规格）。
    - 「MUST NOT 残留孤儿进程」在进程内承载下**自然成立**（宿主进程终止即服务端终止）。
    - 日志**来源**由"子进程 stdout 管道"改为"承载层重定向输出 + 实例日志文件"；
      就绪判定文本与判据不变（仍只认 `DedicatedServer.java:246` 的就绪行）。
    - 状态机**判据全部改用原版日志行**（见 16.3 末条）：就绪 `DedicatedServer.java:246`、
      停机 `MinecraftServer.java:650`、启动失败 `Main.java:227`——**不用**主类 `main` 的返回值
      （原版 `Main.java:201-217` 另起 Server thread 后 main 即返回）。
  - 被托管物（服务端本体）仍是翻译债：见第 14 项。

### 16.3 宿主侧故意偏离与已知限制（2026-10-18 真机实测后登记）

- [x] **承载改用 `JNI_CreateJavaVM`（不用 `JLI_Launch`）**——真机实测 `JLI_Launch` 必然
      `execve(<jre>/bin/java)` 把整个应用进程映像顶替（`atexit` 探针不触发、crash 缓冲区为空、
      events 里无 `am_kill`），与"进程内承载"对立；改用 JNI 标准 API 直接建 VM 后进程存活。
      —— 这属承载方式（非债），但它带来下面几条**必须登记**的后果：
  - [x] **故意偏离：`-DPaper.IgnoreJavaVersion=true`**（已随 change `design.md` D9 交接）
        - 判据：被托管服务端 `org/bukkit/craftbukkit/Main.class` 读取 `java.version` 并要求
          "GA 版本"，非 GA 即拒绝启动（文案 "Unsupported Java detected (...)"）。
        - 现实：Android 上不存在 GA 版 OpenJDK，arm64 JRE 皆自建、VM 自报 `25.0.5-internal`。
        - 处置：用**被托管物自己提供的官方开关**（同一判据文件内即有 `Paper.IgnoreJavaVersion`
          与配套文案 "but the check was skipped. Proceed with caution!"）。
          **不走伪造路线**：实测 `-Djava.version=` 被 HotSpot 忽略（该属性是 VM 内建只读属性）。
        - 后果：Paper 的该门禁被跳过——属"宿主为了让被托管物在 Android 上可运行"的**故意偏离**，
          须随 change 归档一并交接。
  - [x] **已知限制：一进程一台 VM**（JNI 约束，`DestroyJavaVM` 后不可重建；已随 `design.md` D9 交接）
        → 同一应用进程内**无法二次起服**（停服后须重启应用才能再起）。launcher 路线同样受此约束。
  - [x] **已做：exit hook**——**不走** FCL 的 bytehook 形态（用户裁决：不引入第三方 hook 库），
        改用自写 GOT patch，见本节末「宿主存活机制」条。
  - [x] **已补：主类改为从 jar 的 `MANIFEST.MF` 读 `Main-Class`**（2026-10-18 落地，
        任务 9.3）
        - 实现：`lib/platform/server_host/jar_manifest.dart`（最小 ZIP 读取，只解压
          MANIFEST 一个条目；语义照 `java.util.jar.Manifest`）；
          读不到时显式失败（等价 `java -jar` 的 `no main manifest attribute`）。
        - 验证：单测 9 项 + 真实 paper-26.2.jar（64.5MB）读出 `io.papermc.paperclip.Main`
          与原硬编码一致；契约测试桩 jar 故意用另一主类（模拟已打补丁服务端 jar），
          断言 `runMain` 的 className 跟随清单；真机照常起服。
  - [ ] **跨 VM 边界只许传 C 层值**（实测坑）：进程内有**两台 VM**（ART + 新建 HotSpot），
        `JNIEnv` 各属其一；把 ART 的 local ref 塞进 HotSpot 数组会被当 oop 解引用而 SIGSEGV
        （fault addr `0x2c`）。故参数只能"取 C 字符串 → 在新 VM 里重建"。
  - [ ] **生命周期判据全部取自原版日志行（不用 `main` 返回值）**（任务 9.1，2026-10-18 已落地）
        - 判据：原版 `Main.main` 经 `MinecraftServer.spin` **另起 "Server thread"** 跑
          `runServer()` 后即刻返回（`Main.java:201-217` / `MinecraftServer.java:307`）——
          `main` 返回 ≠ 服务端结束。真机实测：`main 正常返回` 之后原版就绪行才打出来。
        - 处置：Android 承载的就绪/停机/启动失败三条判据分别为
          `DedicatedServer.java:246` / `MinecraftServer.java:650`（`Stopping server`）/
          `Main.java:227`（`Failed to start the minecraft server`）；
          `runMain` 改为 **unawaited**（只记返回值，不驱动状态）。契约测试已覆盖。
        - 起服等待口径不变：`start()` 返回 ≠ 就绪，就绪仍由日志行异步驱动（与桌面承载一致）。
  - [ ] **进程内拿不到真实退出码** ⇒ 优雅停机回传 `0`（等价值）
        - spec「输出与退出码经承载层回传」在进程内**退化为**：以原版停机行作为停机确认，
          `exitCode` 回传 0；JVM 随宿主进程存亡，不会单独退出，故无 OS 退出码可采。
  - [x] **宿主存活机制：拦下被托管 JVM 的 `exit()`**（承载方式，非债；2026-10-18 真机已验证）
        - 根因（javap 实证 `paper-26.2.jar` 的
          `net.minecraft.server.dedicated.DedicatedServer.onServerExit()`）：
          **被托管服务端自己**显式 `System.exit(this.abnormalExit ? 70 : 0)`，经 HotSpot
          `vm_exit()` → libc `exit()` 退出整个进程。子进程承载下无所谓（服务端本就是那个
          进程）；**进程内**承载下那等于把宿主应用一起杀掉（真机实测：`stopped`/退出码 0
          之后打出 atexit 探针，随即 `Lost connection to device`）。
        - 处置：在 libjvm.so 上**手写 GOT patch**——解析 `PT_DYNAMIC` → `DT_RELA` /
          `DT_JMPREL` → 命中符号名 `exit` 的重定位 → 覆盖槽位指向 `mc_guarded_exit`
          （拦到后**永久挂起该线程**：既不真退出，也不返回进 VM 的关闭路径）。
          只改 libjvm 的重定位、**不碰 libc**，故宿主自身退出（ART 侧 / 系统强停）不受影响；
          也**不引入**第三方 hook 库（用户裁决：不走 bytehook 路线）。
        - 另有一条**不充分**的尝试已回退不必留：单纯在 VM 内保留非守护线程（`java.util.Timer`）
          拦不住——因为这不是"非守护线程跑完了"的自然退出，而是**显式调用**。
        - 代价：停服后 JVM 存活但空闲（`exit` 被拦在 VM 关闭尾部），配合"一进程一台 VM"
          仍无法二次起服（见上条）。
        - 真机证据（2026-10-18，MIUI/Android 13）：`已改写 exit 重定位槽位 0x6f74311f20
          （库内 vaddr 0x1265f20）` → `已拦下 libjvm 的 exit()（1 处重定位）`；停服走完
          `starting → ready → stopping → stopped`（退出码 0）后打出 `拦下被托管 JVM 的
          exit(0)：宿主应用必须存活，永久挂起本线程`，此后 `adb shell pidof
          com.qshh.flutter_mc` 仍返回同一宿主 pid（12237）——应用存活，不再 `Lost connection`。
        - 实现坑：Android bionic 的内存 `.dynamic` 中 `d_ptr` 不保证已重定位为绝对地址
          （实测 `DT_RELA = 0x55f8`），按指针直接用必 SIGSEGV；改为解析**磁盘 ELF 文件**
          + PT_LOAD 换算 vaddr→file offset 后解决。
  - [x] **已知非致命：OSHI/JNA 在 Android 上加载失败**（`libc.so.6` 找不到）
        —— Paper 用 `ignoreErrors` 包裹，仅"硬件信息"缺失（TPS/CPU/内存上报），不影响起服。
        登记即可，**不修**。

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

### 16.4 承载二次演进：宿主进程内 → 专用 `:jvm` 子进程（2026-10-18，change `android-subprocess-jvm-host`）

- **动因**：16.3 的"一进程一台 VM"在宿主进程内承载下使二次起服静默夭折（真机 bug：
  退出世界后再进卡「正在启动本地服务器」，实例日志分界行后零输出）+ 三处退化
  （退出码回传 0 / exit() GOT patch / 不可强杀）。FCL 实证"会话即进程、退即自杀"
  （`GameMenu.onExit` → killProcess，GameMenu.java:967-973）。
- **新口径**：被托管 JVM 装进应用专用 `:jvm` 子进程（`JvmHostService`，一次会话一个、
  会话结束自杀）；真实退出码经 native exit 拦截层回传（`exitStatus`）；强杀能力恢复；
  宿主终止 ⇒ 服务端终止 = force stop 全杀 + 子进程心跳 watchdog 兜底。
  **撤销**：16.3 的"退出码回传 0""宿主存活机制（GOT patch 拦 exit）"两条——GOT patch
  的 mc_guarded_exit 保留但语义改为"回传退出码 + 终止承载子进程"（宿主进程不再被
  改写 libjvm 重定位的路径保护，承载子进程死即净）。
- **实测坑（全部真机踩出，防复发）**：
  1. `Runtime.addShutdownHook` 注册在 **ART**，被托管 JVM（HotSpot）的 `System.exit`
     不会调它——结果文件必须在 native exit 拦截层写（libc exit 必经）；
  2. MIUI 按 `MiuiMemoryService(started-services)` 杀"仅有非前台 service"的后台进程
     （adj 800）→ `:jvm` 承载 Service 必须前台化（specialUse，照 FCL ProcessService）；
  3. 子进程 stdout 有用户态缓冲、exit 时才 flush——**跨会话共用日志文件会串扰**
     （上一会话停机行落在本会话分界之后）→ 每会话独立日志文件（原版按次滚动同型）；
  4. `System.out`（ART 与 HotSpot 均然）在 Android 上进 logcat 不走 fd 1——跨进程
     上报一律走文件；`/proc/<pid>` 探活对活进程误报不存在——判死用 pidFile/心跳文件；
  5. child 在写 pidFile 前死亡不可观测 → pidFile 必须在 runService 最开头写。
- **自检 harness**：`/jvm-selftest` 模式 `full`/`client`/`soak`/`twice`
  （twice = 同会话两轮起停，直接回归"退出世界后再进"）。
