# mc_render

原版渲染数据半边的翻译落点：模型烘焙与区块编译，产出"原版 BufferBuilder 形状"的顶点纯数据。本包纯 Dart，不 import Flutter / flutter_scene；GPU 上传由 app 壳的 flutter_scene 适配层完成。

## 原版对应物

判据 `mc-sources/minecraft-26.2`：

- `net.minecraft.client.resources.model.ModelBakery` —— 模型烘焙
- `net.minecraft.client.renderer.block.model.BlockModel` —— 方块模型定义
- `net.minecraft.client.renderer.texture.TextureAtlas` —— 贴图集
- `net.minecraft.client.renderer.chunk.SectionCompiler` / `SectionRenderDispatcher` —— 区块编译为区块网格
- `net.minecraft.client.renderer.chunk.VisGraph` / `VisibilitySet` —— 遮剔

## 边界与首个 change

- 依赖 mc_nbt（读 NBT 形态资产）；不得依赖 mc_session / mc_wire / 任何 Flutter 或引擎类型
- 接缝：产出顶点/网格纯数据，app 壳负责转换为 flutter_scene 几何体（等价原版 GPU 上传步）
- 首个预期 change：区块编译切片（SectionCompiler 优先于 ModelBakery）
