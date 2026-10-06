# Proposal

## Why

project-foundation 立起了包结构与"照官方源码翻译"总纲，本项目还没有任何用户可见界面。照原版 `client/gui/screens` 实现游戏菜单链路（用户提供了 26.2 原版三屏截图：主菜单、多人游戏、视频设置），既产出第一个可见成果，也首次验证 mc_ui 组件库与"文件结构按源码"的工作方式。

## What Changes

- mc_ui 新增四个控件（纯 Flutter 实现，外观程序化绘制，不捆任何资产）：
  - `MCButton`（原版 `Button`：灰底斜面、居中标签、禁用态、按下反馈）
  - `MCSliderButton`（原版 `AbstractSliderButton`：可拖滑块、"名称: 值"标签）
  - `MCCycleButton`（原版 `CycleButton`：点按循环"名称: 值"）
  - `MCIconButton`（原版 `ImageButton` 形态的方形小按钮）
- app 壳 `lib/` 文件结构按原版 `gui/screens` 组织：
  - `lib/routes.dart` —— 路由唯一事实来源
  - `lib/screens/screen.dart` —— 界面基类（暗底、居中标题、头部渐变线，对应原版 `Screen`）
  - `lib/screens/title_screen.dart`（原版 `TitleScreen`）
  - `lib/screens/multiplayer/join_multiplayer_screen.dart` + `server_selection_list.dart`（原版 `multiplayer/JoinMultiplayerScreen` + `ServerSelectionList`）
  - `lib/screens/options/video_settings_screen.dart`（原版 `options/VideoSettingsScreen`）
- `lib/main.dart` 替换为路由入口
- 三屏为**视觉与导航骨架**：控件可交互、界面间可达、布局对齐截图；不含真实连接、LAN 搜索、设置持久化

## Capabilities

### New Capabilities

- `mc-ui-components`：MC 风格控件的交互与外观契约（按钮/滑条/循环按钮/图标按钮，纯 widget、资源注入原则的落实）
- `client-screens`：客户端界面链路与各屏内容（标题/多人/视频设置的可达性、内容要素、布局对齐原版）

### Modified Capabilities

（无）

## Impact

- `packages/mc_ui/`（新增四个控件 + 测试）、`lib/`（screens 结构 + routes + main 替换）
- 无新增依赖（纯 Flutter 与既有包）
- 不触碰 packages/ 其余五包、tool/、mc-sources/
