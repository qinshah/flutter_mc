# Tasks

## 1. mc_ui 四控件

- [x] 1.1 建 `MCButton`：CustomPaint 三态（可用/按下/禁用）程序化外观，参数 onPress/label/enabled/width；补 widget 测试（点击回调恰一次、禁用不响应、标签居中、零资产渲染）；验证：`cd packages/mc_ui && flutter test` 全绿、`flutter analyze` 无问题
- [x] 1.2 建 `MCSliderButton`：value 0.0–1.0、onChanged 实时回调、标签"名称: 值"由调用方格式化；补测试（拖动从左到右 value 单调至 1.0、标签更新）；验证：同上
- [x] 1.3 建 `MCCycleButton`：values + index + onChanged，末尾回绕；补测试（连续点按回绕到首值、标签更新）；验证：同上
- [x] 1.4 建 `MCIconButton`：方形、child 由调用方注入、与 MCButton 同禁用语义；补测试；四控件从 `lib/mc_ui.dart` 导出；验证：同上

## 2. app 壳骨架

- [x] 2.1 建 `lib/routes.dart`（三条命名路由）与 `lib/screens/screen.dart` 基类（暗底、居中标题、头部渐变线，按 D3 缩放布局），`lib/main.dart` 替换为路由入口，标题屏先以占位接入；根目录补 widget 冒烟测试（pump 后见标题屏骨架）；验证：根目录 `flutter analyze` 无问题、`flutter test` 冒烟通过

## 3. 三屏实现

- [x] 3.1 实现 `lib/screens/title_screen.dart`：标题区文字版 MINECRAFT/JAVA EDITION、五主按钮（宽度 200、间距对照截图）+ 三图标钮、右上倾斜黄色 splash 占位、左下版本/右下版权 overlay；按 spec 断言按钮可用性与导航（多人游戏/选项… 可进、退出游戏桌面端结束）；验证：根 `flutter test` 对应用例全绿
- [x] 3.2 实现 `lib/screens/multiplayer/join_multiplayer_screen.dart` + `server_selection_list.dart`：标题+渐变线、localhost 示例条目（红色"无法连接至服务器"、叉钮占位、图标占位区）、LAN 提示区、底部七按钮（仅返回可用）；验证：根 `flutter test` 对应用例全绿
- [x] 3.3 实现 `lib/screens/options/video_settings_screen.dart`：分组"显示"/"品质与性能"、截图控件清单（滑条/循环按钮混排）、"完成"返回；状态内存态（重进回默认值）；验证：根 `flutter test` 对应用例全绿

## 4. 集成验收

- [x] 4.1 全链路测试：标题→多人→返回、标题→视频设置→完成 两路径 pump 往返；结构对照检查（lib/screens 文件清单与 design D1 一致、mc_ui 无 flutter_scene 引用）；验证：测试全绿、两条 grep/清单命令符合预期
- [x] 4.2 全仓回归：根 + 七包 analyze 零 issue，四个搬入包 `dart test` 全绿；验证：命令输出符合预期
