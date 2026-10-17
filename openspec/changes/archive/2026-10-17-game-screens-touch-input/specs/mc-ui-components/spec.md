# Spec Delta

## ADDED Requirements

### Requirement: 触控按钮控件样式

mc_ui SHALL 提供触控按钮控件：半透明深色底 + 白色描边圆角矩形、白色单色图标/文字
（按用户新 UI 图口径）。控件 SHALL 同时支持图标与文字两种内容；按下 SHALL 有可见
反馈。控件 SHALL 基于 `Listener`（非手势竞技场）采集原始指针，支持多点触控下
多个按钮同时按住（判据 fscraft `touch_hud.dart` 的 `HitTestBehavior.opaque` 口径）。
（无 Java 对应物——输入采集自由设计。）

#### Scenario: 多点同时按住

- **WHEN** 手指按住前进按钮的同时另一手指按住跳跃按钮
- **THEN** 两个按钮均处于按下态，输入层同时收到"前"+"跳"

### Requirement: TouchHub 布局

mc_ui SHALL 提供 TouchHub 组件（自由设计，参考触控 UI 图）：左下方向区
（D-pad：▲▼◀▶ + 中央跳跃 ◆）、右下动作区、顶部系统键（Esc、E）。
组件 SHALL 只做"手势 → 键位语义"翻译，MUST NOT 含游戏逻辑；按钮语义由调用方注入。
hub 整体 MUST NOT 拦截其覆盖区域之外的指针（未命中按钮的指针穿透给场景层转视角）。

#### Scenario: 覆盖区外可转视角

- **WHEN** 手指在 hub 按钮之外的画面区域拖动
- **THEN** 该指针被场景层接收用于转视角，hub 无反应
