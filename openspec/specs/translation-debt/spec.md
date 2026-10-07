# translation-debt Specification

## Purpose

定义"翻译债"的登记与审查机制：凡原版有 Java 实现而本仓简化/未实现之处，都必须成为可
见、可追踪的债项，而不是被称作"自由设计"；并规定 review 时如何验证"逐行翻译"这一纪律
被真正执行。

## Requirements

### Requirement: 翻译债清单完整可核查

`openspec/progress.md` SHALL 登记全仓所有"原版有Java 实现、本仓标为简化/占位/未实现"
之处，按大类分组，每条以 checkbox 呈现：未勾选 = 未完成，每条含：原版 `文件:行号`、
当前实现位置与做法、受影响观感。新增或修复简化点时 SHALL 同步更新该清单；完成债项
时 SHALL 勾选对应项。清单 SHALL NOT 承诺交付时间。本仓库 MUST NOT 在 `docs/` 下
维护第二份债清单（历史上为 `docs/translation-debt.md`，已迁出并删除）。

#### Scenario: 简化点未登记视为违规

- **WHEN** 代码中出现"简化/占位/暂不实现"的注释，而对应原版有 Java 实现
- **THEN** 判为违规；处置是登记进 `openspec/progress.md`（未勾选项），或按原版补齐实现

#### Scenario: 债项不得被称为自由设计

- **WHEN** 某处差异被归因为"自由设计"
- **THEN** 处置是核对原版是否存在对应 Java；存在则 MUST 改称翻译债

#### Scenario: 债项完成即勾选

- **WHEN** 某未勾选债项在 change 中被补齐
- **THEN** `openspec/progress.md` 对应 checkbox 被勾选，条目保留作记录

### Requirement: 审查机制以判据清单为门禁

进入实现阶段的 change SHALL 在其 `design.md` 中列出本次用到的判据
`文件:行号`；缺失该清单者不得进入实现。审查 SHALL 抽样核对代码常量与表达式是否与所列
判据一致，重点核对**常量量纲**与**表达式顺序**这两类历史上反复出错的维度。

#### Scenario: 缺判据清单不得实现

- **WHEN** 一个 change 已有 tasks 准备进入实现，但其 design.md 未列出判据文件:行号
- **THEN** 不得开始实现，先补齐判据清单

#### Scenario: 审查盯住量纲与顺序

- **WHEN** 审查某段物理/编解码实现
- **THEN** 核对常量是否按原版口径代入（尤其属性值 vs 换算值）、表达式顺序是否与原版一致
