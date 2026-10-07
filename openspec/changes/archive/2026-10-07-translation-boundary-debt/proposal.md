# Proposal

## Why

上一 change 把「Java→Dart 逐行翻译」立为最高纪律，但**"自由设计"的边界仍然太宽**，成了可以往里塞东西的口袋。用户指出：目标本应是 100% 翻译，3D 与输入的差异只是"用 flutter_scene / Flutter 组件所以代码不一样"，**不是不翻译的理由**；而数据上行原版本就有完整 Java 流程，不该豁免。

核实结论（扫全仓"简化"标记 + 查 mc-sources）：
- 全仓标着"简化/占位"的地方，**原版全部有 Java 对应物**，一条真平台差异都没有。
- 数据上行有完整原版流程（`ClientCommonPacketListenerImpl:147/152/175/209/319`、
  `ClientPacketListener:2658`），我们已在做同构实现，本就该逐行翻译发送条件与时序。
- 命名与文件路径偏离原版更远：一个 Dart 文件塞两个 Java 类（`LivingEntity` + `Player`
  → `player_controller.dart`）、`KeyMapping`→`key_map`、`LevelRenderer`→`mesher`、
  `BlockRenderLayer`→`block_semantics_v262`。

## What Changes

- **自由设计收敛为两类**（原版无 Dart 可抄的环境差异）：3D 渲染后端、输入事件采集。
  连这两处的**语义**仍须照原版。**数据上行不再豁免**。
- **新增「翻译债」能力**：全仓"简化"逐条登记，写明原版文件:行号、影响的观感、
  缺失的产品完整性维度；MUST NOT 再把"简化"称作"自由设计"。
- **新增命名与路径对齐要求**：类名、方法名、字段名、文件路径 SHALL 照原版
  （一个 Java 类对应一个 Dart 文件），仅在语言惯例必须时记录偏离理由。
- **审查机制（方案 1）**：每个新 change 的 `design.md` SHALL 列出本次用到的
  判据 `文件:行号`，缺失即校验不通过。
- `AGENTS.md` 同步（自由设计两类、命名对齐、design.md 判据清单要求）。

## Capabilities

### New Capabilities

- `translation-debt`: 翻译债的登记、边界判定与审查机制。

### Modified Capabilities

- `project-structure`: 「Java→Dart 逐行翻译」需求的自由设计清单由三类收敛为两类
  （数据上行移出），并新增命名/路径对齐要求。

## Impact

- `openspec/specs/project-structure/spec.md`（改一条需求 + 新增命名要求）
- `openspec/specs/translation-debt/spec.md`（新建）
- `docs/translation-debt.md`（债清单，含原版文件:行号）
- `AGENTS.md`（摘要同步）
- 不改运行时代码。