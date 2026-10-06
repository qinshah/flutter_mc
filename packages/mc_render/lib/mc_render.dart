/// mc_render —— 原版渲染数据半边的翻译落点（骨架）。
///
/// 目标：模型烘焙（ModelBakery / BlockModel / TextureAtlas）与区块编译
/// （SectionCompiler / VisGraph），产出"原版 BufferBuilder 形状"的顶点纯数据。
/// 本包纯 Dart，不 import Flutter / flutter_scene；GPU 上传由 app 壳的
/// flutter_scene 适配层完成。实现从区块编译切片开始（见 README）。
library;
