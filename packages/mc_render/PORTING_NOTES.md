# mc_render 移植笔记：fscraft 网格器 → 本仓

本文件记录 T2.1（join-and-render）的移植依据：把 fscraft `lib/voxel/mesher.dart`
（630 行）搬到本仓 `lib/src/mesher.dart`（409 行）时，**数据源侧的差异清单**，
以及哪些是逐字平移、哪些被简化。

原实现：`~/Desktop/Code/fscraft/lib/voxel/mesher.dart`（fscraft 另有
`dashcraft/lib/voxel/mesher.dart` 539 行，非本次判据）。

## 1. 逐字平移、语义零改动

以下部分按原实现照搬，仅去掉 `fscraft` 前缀与调试注释：

| 部分 | 说明 |
| --- | --- |
| 手性处理 `_mirrorZ` | 世界右手系 → 引擎左手系：顶点/法线/包围盒的 z 取反；`0` 保持 `+0.0` |
| 绕序 `addQuadIndices` | `2,1,0 / 3,2,0`（z 镜像翻转绕序 + flutter_scene 顺时针为正面） |
| 面朝向明暗 `_shadeFor` | 顶 1.0 / 底 0.5 / 南北 0.8 / 东西 0.6 |
| UV 翻轴 `_uvFlip` | `up/down` 翻 V、`east/west` 翻 U、`north/south` 不动（补偿 z 镜像） |
| 面角点表 `_corners` / 面向量 `_offsets` / 面序 `_allFaces` | 数值表原样 |
| `_LayerBuilder` | 分层顶点缓冲、倍增扩容、`bounds` 扫描、`Float32List`/`Uint32List` 纯数据输出 |
| 面剔除主循环 | 遍历 `ly/lz/lx` 三段循环，逐面查邻居 |
| 十字植物两片对角面片 `_emitCross` | 角点与法线（±0.7071）原样 |

## 2. 数据源差异清单（真正要改的地方）

| # | fscraft 原实现 | 本仓移植 | 为什么必须改 |
| --- | --- | --- | --- |
| D1 | 方块语义：`StateRenderInfo render.infoOf(state)`（`StateRenderKeying` 注入，1.12.2 默认 `(blockId<<4)\|meta` 打包约定） | 注入 `MeshSemantics`（`mesh_semantics.dart`），26.2 实现 `BlockSemanticsV262` | 26.2 的 stateId 由服务器 registry 下发（mc_session 调色板），不是本地打包；语义改为按 stateId 查 32366 项身份表 + 名字启发式 |
| D2 | `StateRenderInfo` 自带 `topTile/bottomTile/sideTile`（tile 序号） | **拆出去**：`MeshSemantics` 只留 `layerIndexOf/isCross/hidesNeighbors/nameOf`，UV 由调用方注入 `uvFor(stateId, face)` | UV 的权威来源是资源包模型 + 图集（mc_resource，见 resource-pipeline），不该由网格器或语义层持有 |
| D3 | 邻居是整列：`SectionNeighbors{negX..posZ: NeighborColumn?}`，列上 `stateAt(lx, 全局Y, lz)`，故 `_neighborStateOf(neighbors, section, …)` 需要 `section` 来算 `_globalY`；「列 + sectionY → 段视图」由 `ColumnSectionView` 承担 | 邻居是 16³ 段：`SectionNeighbors{negX..posZ: SectionView?}`，段上 `stateAt(段内局部X, 段内局部Y, 段内局部Z)`，`_neighborStateOf` **不再需要 `section`** | mc_render 不得 import mc_session（红线），故「列 → 段视图」的适配器**不随网格器搬**，落在 app 壳适配层。**数据源本体两边同构**：mc_session `RemoteChunkColumn`（`List<Uint16List> sections` + `stateAt(localX, worldY, localZ)`，26 段）与 fscraft `ChunkColumn`/`NeighborColumn` 形状一致，只是分属两个包 |
| D4 | `meshSection(..., includeOpaque/includeCutout/includeTranslucent, keying)` 六个参数 | 去掉三个层开关与 `keying`，只剩 `semantics` + `uvFor` | 分层开关调用方没用（永远三层全出）；`keying` 是 1.12.2 打包约定的入口，26.2 无对应物 |
| D5 | `ChunkMesh.empty` 静态工厂 | `const ChunkMesh()` | 纯风格：本仓 `ChunkMeshData.empty()` 仍保留（测试在用） |
| D6 | 流体同族：按 blockId 配对（静水 8 / 流水 9、熔岩 10 / 流动熔岩 11） | 按**方块名**判族：`flowing_` 前缀剥掉后相等即同族 | 26.2 已无 `flowing_*` 方块（水是单一 block + 16 个 `level` state，已核 `state_identity_26_2.dart`：`flowing_` 命中数 0）。实际生效路径是"同名不同 state 互剔"，即 `water[level=0]` 与 `water[level=1]` 之间不出内表面 |
| D7 | 十字植物贴图：`type.sideTile` 直接取 | `uvFor(state, BlockFace.north)`（约定：十字植物用侧面语义，由注入方处理） | D2 的连带结果——tile 不再由语义层提供 |

## 3. 首版简化点（design D2，已在代码注释标注）

- 整块立方体 + 面剔除；**无 AO、无平滑光照**
- 非常规形状（半砖/楼梯/栅栏/门）按整块渲染
- 渲染层/十字/遮挡分类是**名字启发式**（液体→translucent、叶/玻璃→cutout、
  植物名单→cross、其余→opaque），未识别 state 按 opaque；后续对齐原版
  `BlockRenderLayer` / `BlockShapes` 注册表
- 流体同族按名字相等近似（见 D6）

## 4. 后续端口指引

fscraft 网格器依赖的另外几个文件**没有**搬进 `mc_render`，它们在本仓各有归属：

| fscraft | 本仓归属 | 状态 |
| --- | --- | --- |
| `world/render_keying.dart`（`StateRenderKeying`/`StateRenderInfo`） | 语义拆成 `MeshSemantics`（本包）+ 身份表 `state_identity_26_2.dart` | 已落地（启发式版） |
| `voxel/block_atlas_uv.dart`（静态图集布局 + tile→UV） | `mc_resource` 的图集/模型查询（`uvFor` 注入方） | 见 resource-pipeline change |
| `world/chunk_column.dart` / `world/world.dart`（整列与邻居列） | mc_session `RemoteChunkColumn`（列本体已在）+ **app 壳的「列+sectionY → `SectionView`」适配器** | 列本体已落地；适配器待写（join-and-render T3.1/T3.2） |
| `voxel/packed_state_render_keying.dart`（1.12.2 打包约定） | 无对应物（26.2 用服务器 registry 的 stateId） | 不移植 |

适配器要点（照 `ColumnSectionView`）：`stateAt(lx, ly, lz) => column.stateAt(lx, sectionY * 16 + ly, lz)`；
`isEmpty` 在 mc_session 侧没有 `isSectionEmpty` 对应物，需由适配层自行判定（如全 0 扫描或
用段头部 `nonEmptyBlockCount`——后者目前 `ChunkIngestor` 读后丢弃）。

## 5. 验证

`packages/mc_render/test/mesher_test.dart`：11 项 golden 单测锁住
顶点数/索引/UV 快照/邻居剔除/分层。跑法：

```bash
cd packages/mc_render && dart test
```
