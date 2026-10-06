# Design

## Context

项目现有七个包（project-foundation 已归档入纲）：mc_ui 是唯一 Flutter 例外包，尚无任何控件；app 壳 lib/ 只有 hello-world main.dart。用户给定 26.2 原版三屏截图作为布局与文案的验收参照。要求：文件结构按源码来、组件由 mc_ui 负责、"简单实现"。

## Goals / Non-Goals

**Goals:**

- 三屏可达、可交互、布局与文案对照截图；mc_ui 立起四个可复用控件
- `lib/` 文件结构与原版 `gui/screens` 一一对应，为后续所有界面立先例

**Non-Goals:**

- 真实连接（多人屏仅骨架）、LAN 搜索、servers.dat 读写
- 设置持久化（Options 系统后续 change 立项）
- panorama 背景、原版位图字体、官方贴图（均依赖资源管线 change）
- 单人游戏 / Realms / 添加服务器 / 直接连接等次级页面（按钮禁用占位）

## Decisions

### D1 翻译边界：screens 在 app 壳，components 在 mc_ui

原版把可复用控件放 `gui/components`、把绑定 Minecraft 实例与导航的页面放 `gui/screens`。沿用此界：mc_ui 只出**无游戏状态依赖**的控件（四控件 + 纯 widget API）；`lib/` 按 vanilla 建目录与文件名：

```
lib/
  main.dart               ← Minecraft.java 的入口角色（本期仅装配 MaterialApp）
  routes.dart             ← 路由唯一事实
  screens/
    screen.dart           ← gui/screens/Screen.java（暗底 + 居中标题 + 头部渐变线）
    title_screen.dart     ← gui/screens/TitleScreen.java
    multiplayer/
      join_multiplayer_screen.dart   ← JoinMultiplayerScreen.java
      server_selection_list.dart     ← ServerSelectionList.java
    options/
      video_settings_screen.dart     ← options/VideoSettingsScreen.java
```

备选：MCScreen 基类放 mc_ui —— 放弃，Screen 属于 gui/screens 层次，且未来必然绑定导航/游戏状态（原版 Screen 持有 Minecraft 引用）。

### D2 外观程序化绘制（backend adaptation，非原版分歧）

资产管线未立，本期外观全部代码绘制：按钮用 CustomPaint 画灰底 + 黑框 + 上亮下暗棱线（对照截图取色，灰系 #6f6f6f 底、#000 边框、#a0a0a0/#565656 棱线），按下底面提亮；背景为纯暗色 + 标题栏底部渐变线，不做 panorama。字体用 Flutter 默认等宽风格样式。以上均标注 backend adaptation：资源 change 接入后替换为注入的贴图/字体，控件 API 不变。

### D3 缩放布局：模拟原版 scaled GUI

原版按整数 guiScale 把虚拟坐标缩放到屏幕。本期做一个简化版 `ScaledLayout`：取 `scale = (短边 / 240).floor().clamp(1, 4)`（原版 `Window.calculateScale` 的简化），控件在虚拟坐标布局——按钮高 20、主按钮宽 200、列间距 4、行距 24，与截图比例一致。备选：直接逻辑像素布局 —— 放弃，缩放层是原版 UI 的核心机制，越晚立越难对齐。

### D4 导航与退出

`MaterialApp(routes:)` 命名路由；"返回"/"完成"即 `Navigator.pop`。"退出游戏"桌面端走 `SystemNavigator.pop`，web 平台该按钮禁用。

### D5 状态边界

视频设置取值：Screen 内 StatefulWidget 内存态，进入即默认值（对应 spec"不持久化"）；控件值文案照截图（如"最大帧率: 无限制"、"垂直同步: 关"）。服务器列表：一条硬编码示例条目（localhost / 无法连接至服务器），由 `server_selection_list.dart` 承载（对应原版该类就是列表 widget 本体）。

## Risks / Trade-offs

- [默认字体与 MC 位图字体宽度差异导致文案溢出] → 标签超宽截断 + 省略号；宽度敏感文案（按钮）测试断言不溢出
- [无 panorama 观感与截图差距明显] → 接受，记为后续资源 change 的输入
- [缩放公式是简化版，与原版 calculateScale 不完全一致] → 标注简化点；资源/UI 精修 change 时对齐判据
- [WidgetTester 拖动/点按测试的 Flutter 版本差异] → 用稳定 API（drag、tap、find.text）

## Open Questions

- splash 文案：本期用截图占位 "Random splash!"，正式文案列表（splash.txt 等价物）随资源 change 定
