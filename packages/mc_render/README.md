# mc_render

原版渲染数据半边的翻译落点：区块编译（SectionCompiler 切片），产出"原版 BufferBuilder 形状"的顶点纯数据。本包纯 Dart，不 import Flutter / flutter_scene；GPU 上传由 app 壳的 flutter_scene 适配层完成。

## 原版对应物

判据 `mc-sources/minecraft-26.2`（✅ 已落地 / ⬜ 未实现）：

- ✅ `net.minecraft.client.renderer.chunk.SectionCompiler` / `SectionRenderDispatcher` —— 区块编译为区块网格（`src/mesher.dart`：16³ 段 → 顶点/UV/索引）
- ✅ `net.minecraft.client.renderer.block.BlockRenderDispatcher` 的**层归属面** —— 渲染层（opaque/cutout/translucent）与遮挡语义（`src/mesh_semantics.dart` + 26.2 实现 `src/block_semantics_v262.dart`）
- ⬜ `net.minecraft.client.renderer.chunk.VisGraph` / `VisibilitySet` —— 段内遮挡图（遮剔），首版用直接邻居查询替代
- ⬜ 平滑光照 / AO（`AmbientOcclusionCalculator` 一路）

模型与图集侧（`ModelBakery` / `BlockModel` / `TextureAtlas`）不在本包：方块状态→模型→面贴图路径的读取落在 **mc_resource**
（`BlockModels`，见 resource-pipeline change），本包只经注入的 `uvFor(stateId, face)` 消费其结果。

## 边界

- 依赖 mc_nbt（读 NBT 形态资产）；**不得**依赖 mc_session / mc_wire / 任何 Flutter 或引擎类型
- 区块数据由调用方适配成 `SectionView` 传入（不 import mc_session，只认接口）
- 接缝：产出顶点/网格纯数据，app 壳负责转换为 flutter_scene 几何体（等价原版 GPU 上传步）

## 已实现（join-and-render 2.x）

- `src/mesher.dart` —— 分区网格器：16³ 段 → 按渲染层分的顶点/法线/UV/颜色/索引 + 包围盒；
  面剔除（同 state 相邻、`hidesNeighbors`、流体同族）、十字植物两片对角面片。
  数据源全部注入：`SectionView`（段视图）、`SectionNeighbors`（相邻段，段内局部坐标）、
  `MeshSemantics`（方块语义）、`uvFor`（stateId + 面 → 图集 UV 矩形）
- `src/mesh_semantics.dart` —— 语义接口 + 查询缓存视图
- `src/block_semantics_v262.dart` —— 26.2 语义实现（state 身份表 + 名字启发式分类）
- `src/state_identity_26_2.dart` —— 26.2 stateId → 身份串（32366 项，官方 data generator 产物）
- `src/chunk_mesh_data.dart` / `src/uv_rect.dart` —— 纯数据载体

移植依据、fscraft 数据源差异清单、后续端口指引：见 [PORTING_NOTES.md](PORTING_NOTES.md)。

**首版简化**（design D2，代码注释已标注）：整块立方体 + 面剔除，无 AO / 平滑光照；
半砖/楼梯等非常规形状按整块渲染；语义分类是名字启发式，未识别 state 按 opaque。

## 验证

```bash
cd packages/mc_render && dart analyze && dart test
```

`test/mesher_test.dart` 用固定小区块作 golden：锁顶点数/索引/UV 快照/邻居剔除/分层。
