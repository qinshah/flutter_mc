# Spec Delta

## ADDED Requirements

### Requirement: MCEditBox 文本输入框

MCEditBox SHALL 呈原版 EditBox 形态：暗底矩形，边框失焦灰色、聚焦白色；SHALL 支持文本输入（经 TextEditingController）、标签外置占位与光标移动；输入内容变化 SHALL 实时同步 controller。

#### Scenario: 输入与聚焦反馈

- **WHEN** 点击输入框并键入文本
- **THEN** 文本实时显示且 controller 同步；聚焦时边框变白，失焦恢复灰色

#### Scenario: 禁用态

- **WHEN** 控件禁用
- **THEN** 不接受输入且外观呈禁用态
