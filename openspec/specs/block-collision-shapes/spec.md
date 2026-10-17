# block-collision-shapes Specification

## Purpose
TBD - created by archiving change block-collision-shapes. Update Purpose after archive.

## Requirements

### Requirement: 按方块状态的碰撞形状

方块碰撞查询 SHALL 返回**按方块状态解析的体素形状**（盒并集），而非整块布尔。形状来源 = 26.2 状态身份串的方块名与属性。形状族 SHALL 至少覆盖：整块、无碰撞（空气/常见植物/液体）、半砖（top/bottom）、楼梯（facing×half×shape）、栅栏与栅栏门与玻璃板与铁栏杆（连接属性驱动，碰撞高 1.5 / 1.0）、墙、雪片（层高 0.125×n）、地毯（0.0625）、耕地与土径（0.9375）、灵魂沙（0.875）。未覆盖族 SHALL 兜底为整块并登记翻译债。

#### Scenario: 栅栏碰撞高 1.5 格

- **WHEN** 查询一根任意连接状态的栅栏的碰撞形状
- **THEN** 形状最高点为 1.5 格（跳跃高度 1.25 不可及）

#### Scenario: 半砖碰撞为半高

- **WHEN** 查询 `type=bottom` 的半砖
- **THEN** 形状仅占 y 0..0.5

#### Scenario: 无碰撞方块返回空形状

- **WHEN** 查询空气、常见植物（草/花/火把/作物/导线/甘蔗）或液体
- **THEN** 返回空形状（不阻挡）

### Requirement: 栅栏与墙的连接驱动形状

栅栏、栅栏门、玻璃板、铁栏杆的碰撞形状 SHALL 由东/南/西/北连接属性驱动：中心柱恒在，连接侧含横臂（碰撞高全族一致：栅栏/墙 1.5、玻璃板/铁栏杆 1.0）。

#### Scenario: 栅栏横臂随连接出现

- **WHEN** 栅栏的 `north=true`
- **THEN** 形状含北侧横臂盒（y 0..1.5）
