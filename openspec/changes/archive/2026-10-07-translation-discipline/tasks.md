# Tasks

## 1. 立纪律（文档）

- [x] 1.1 `AGENTS.md`：把"Java→Dart 级忠实"从描述性表述升级为**最高纪律**——写代码前
  必须先指名原版对应物、指不出就停下、确实没有则写明属于三类自由设计或 Flutter API 差异
- [x] 1.2 `AGENTS.md`：附**踩坑表**（顺序错→跳高 0.9969/量纲错→飞行快 21 倍/
  擅自合理化→失重悬浮），让后来者一眼看到"看起来对"其实多危险
- [x] 1.3 `project-structure` spec delta：写入可判违规的 5 条需求（逐行翻译 / 写前指名 /
  判据可追溯 / 测试断言黄金值 / 原版奇怪处仍照抄）
- [x] 1.4 归档本 change，delta 合并进 `openspec/specs/project-structure/spec.md`
- [x] 1.5 `openspec validate --specs` 全过（7 项主 spec）

## 2. 让纪律可执行（自查动作）

- [ ] 2.1 后续每个 change 的 design.md SHALL 列出"本次涉及的判据文件:行号"，
  供apply 阶段逐条核对（下一个 change 起生效）
- [ ] 2.2 审已有代码中**常量口径**是否还有混用：重点查 `PlayerMotion` 各速度常量
  （`walkSpeed` 4.317 格/秒 vs `moveSpeedAttribute` 0.1 属性值）是否被跨口径代入
- [ ] 2.3 审已归档 change 的实现里是否残留"擅自合理化"的保护逻辑（多余 `Math.max` /
  边界钳制 / fallback 常量），逐条对照原版源码确认该有还是有

**说明**：design.md 有意跳过——其指引要求"仅在跨服务改动、新依赖、迁移复杂度或歧义时
创建"，本 change 纯纪律文档，四项条件均不满足。