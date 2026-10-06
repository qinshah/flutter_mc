# mc_ui

MC 风格 Flutter 组件库：用 Flutter widget 实现原版 `client/gui/components` 的控件（MCButton、MCEditBox 等），API 形状照原版。packages/ 下唯一允许依赖 Flutter 的包；禁依赖 flutter_scene。

## 原版对应物

判据 `mc-sources/minecraft-26.2`：

- `net.minecraft.client.gui.components.AbstractWidget` / `AbstractButton` / `Button` —— 控件基类与按钮
- `net.minecraft.client.gui.components.EditBox` —— 文本框
- `net.minecraft.client.gui.components.Checkbox` / `CycleButton` / `AbstractSliderButton` 等 —— 其余控件

## 边界与首个 change

- 外观贴图/字体由调用方经资源抽象注入，本包不捆绑任何官方资产
- screens（TitleScreen 等绑定游戏状态的页面）不进本包，留在 app 壳用本包组件拼装
- 首个预期 change：MCButton
