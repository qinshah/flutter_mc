# mc-ui-components Specification

## Purpose

定义 MC 风格控件库（mc_ui 包）的交互与外观契约：按钮、滑条按钮、循环按钮、图标按钮以纯 Flutter widget 实现，API 形状与视觉行为对照原版 `client/gui/components`，外观全部程序化绘制、不依赖包内资产。

## Requirements

### Requirement: MCButton 的三态与回调

MCButton SHALL 以程序化绘制呈现 MC 风格外观（灰色底面、黑色外框、上亮下暗斜面棱线、居中标签），SHALL 支持 可用 / 禁用 两态：禁用态标签变灰且 MUST NOT 触发回调；可用态 SHALL 在按下时给出可见反馈（底面变亮）。点击（含键盘激活以外的指针点击）SHALL 触发一次回调。

#### Scenario: 点击触发一次回调

- **WHEN** 控件可用且被点击
- **THEN** onPress 恰好触发一次，且按下期间外观有可见变化

#### Scenario: 禁用态不响应

- **WHEN** 控件处于禁用态且被点击
- **THEN** 回调不触发，标签呈灰色

### Requirement: MCSliderButton 的拖动与值标签

MCSliderButton SHALL 提供归一化取值（0.0–1.0）的水平滑块：拖动滑块实时更新取值并触发 onChanged；标签 SHALL 以"名称: 值"格式实时显示调用方格式化的当前值。

#### Scenario: 拖动更新取值

- **WHEN** 用户把滑块从最左拖到最右
- **THEN** value 单调升至 1.0，onChanged 收到中间值序列，标签随格式化值更新

### Requirement: MCCycleButton 的循环切换

MCCycleButton SHALL 持有一组有序值并在每次点按时前进一格，到末尾回绕到首值；标签 SHALL 以"名称: 当前值"格式显示。

#### Scenario: 循环回绕

- **WHEN** 当前处于最后一个值时再次点按
- **THEN** 回到第一个值，标签更新，onChanged 触发

### Requirement: MCIconButton 的方形小按钮形态

MCIconButton SHALL 呈方形（边长约等于主按钮高度），内容为调用方注入的 widget；SHALL 与 MCButton 同样的可用/禁用语义。

#### Scenario: 禁用图标按钮不响应

- **WHEN** MCIconButton 处于禁用态且被点击
- **THEN** 回调不触发且外观呈禁用态

### Requirement: 控件外观不依赖包内资产

mc_ui 全部控件 SHALL 程序化绘制（CustomPaint/装饰）或由调用方参数注入外观；控件在任何资源注入缺席时 MUST 仍可渲染（有默认观感），MUST NOT 读取包内资产文件。

#### Scenario: 零资产可渲染

- **WHEN** 在不含任何资产声明的测试环境中 pump 各控件
- **THEN** 全部正常渲染并通过交互测试

### Requirement: MCEditBox 文本输入框

MCEditBox SHALL 呈原版 EditBox 形态：暗底矩形，边框失焦灰色、聚焦白色；SHALL 支持文本输入（经 TextEditingController）、标签外置占位与光标移动；输入内容变化 SHALL 实时同步 controller。

#### Scenario: 输入与聚焦反馈

- **WHEN** 点击输入框并键入文本
- **THEN** 文本实时显示且 controller 同步；聚焦时边框变白，失焦恢复灰色

#### Scenario: 禁用态

- **WHEN** 控件禁用
- **THEN** 不接受输入且外观呈禁用态
