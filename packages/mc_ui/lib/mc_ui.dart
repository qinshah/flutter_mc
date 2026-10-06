/// mc_ui —— MC 风格 Flutter 组件库。
///
/// 用 Flutter widget 实现原版 `client/gui/components` 的控件（MCButton、
/// MCEditBox 等），API 形状照原版；外观贴图/字体由调用方经资源抽象注入，
/// 本包不捆绑任何官方资产。screens（绑定游戏状态）留在 app 壳组合。
/// 本包是 packages/ 下唯一允许依赖 Flutter 的包，禁依赖 flutter_scene。
library;

export 'src/mc_button.dart';
export 'src/mc_cycle_button.dart';
export 'src/mc_edit_box.dart';
export 'src/mc_face_painter.dart';
export 'src/mc_icon_button.dart';
export 'src/mc_slider_button.dart';
