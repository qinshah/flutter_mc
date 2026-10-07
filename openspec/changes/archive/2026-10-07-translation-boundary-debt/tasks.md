# Tasks

## 1. 边界收敛

- [x] 1.1 核实原版是否有对应 Java：扫全仓"简化/占位/未实现/TODO"标记（30+ 处），
      逐条查 mc-sources 确认全部有对应 Java，**无一条真平台差异**
- [x] 1.2 核实数据上行有原版流程：`ClientCommonPacketListenerImpl:147/152/175/209/319`、
      `ClientPacketListener:2658 notifyPlayerLoaded` ⇒ 从自由设计清单移出
- [x] 1.3 自由设计清单由三类收敛为两类（3D 渲染后端 / 输入事件采集），并注明这两处的
      **语义**仍要照原版

## 2. 翻译债登记

- [x] 2.1 `docs/translation-debt.md`：9 类债项，逐条写原版文件:行号、当前实现、
      受影响观感、产品完整性维度
- [x] 2.2 核实 UI 债规模：原版 `gui/components` 65 个 vs 我们 6 个；
      `gui/screens` 39 个 vs 我们 9 个 ⇒ 控件层在还原，**屏幕主体是债**
- [x] 2.3 核实音频：`client/sounds/` 齐全而我们无实现（TODO）⇒ 登记为债
- [x] 2.4 清单**不承诺排期**，只登记事实

## 3. 命名与路径

- [x] 3.1 核实命名偏离现状：`LivingEntity`+`Player`→`player_controller.dart`（两个类合一
      + 改名）、`KeyMapping`→`key_map`、`LevelRenderer`→`mesher`、`BlockRenderLayer`→`block_semantics_v262`
- [x] 3.2 spec 新增「命名与文件路径照原版」需求（一 Java 类 = 一 Dart 文件）
- [x] 3.3 `AGENTS.md` 同步命名要求 + 偏离示例表

## 4. 审查机制（方案 1）

- [x] 4.1 spec 新增「审查机制以判据清单为门禁」：`design.md` 须列判据文件:行号，
      缺失不得进入实现
- [x] 4.2 审查重点标注**常量量纲**与**表达式顺序**（历史上反复出错的两个维度）

## 5. 流程

- [x] 5.1 delta 合并进主 spec，新建 `translation-debt` 能力
- [x] 5.2 `openspec validate --specs` 全过（8 项主 spec）
- [x] 5.3 归档本 change

**说明**：design.md 有意跳过——其条件是"跨服务改动 / 新依赖 / 迁移复杂度 / 歧义"，
本 change 只立文档与清单，四项均不满足。

## 遗留（非本次范围，需另开 change）

- 命名逐步改正（会牵动导入关系，建议在相关 change 中顺手改）
- 债项排期（按"观感影响 × 实施成本"另议）
