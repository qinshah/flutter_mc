# Spec Delta

## MODIFIED Requirements

### Requirement: 翻译债清单完整可核查

`openspec/progress.md` SHALL 登记全仓所有"原版有 Java 实现、本仓标为简化/占位/未实现"
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

- **WHEN** 某 untracked 债项在 change 中被补齐
- **THEN** `openspec/progress.md` 对应 checkbox 被勾选，条目保留作记录
