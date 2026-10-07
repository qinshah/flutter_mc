# Proposal

## Why

实机多次反馈：海带/海草/藤蔓渲染成青蓝"冰柱"，竹子被拉成整方块，半砖/楼梯/薄皮形态全错。
根因是两条独立的简化（`mesher.dart` 文件头自述「首版简化：整块立方体 + 面剔除；
无 AO/平滑光照/非常规形状」）：

1. **分类靠手写名单** —— `BlockSemanticsV262` 的 `_crossNames`（40 项）/
   `_isCutoutName`（只认 leaves/glass）/`_isFlatGroundCover`（8 项）都按名字启发式，
   `kelp`/`seagrass`/`vine`/`lily_pad`/`bamboo` 一个都没命中⇒ 落opaque 层 ⇒ 按实心立方体画。
2. **几何只支持整方块** —— mesher 不读模型 `elements`，故 2×16×2 的竹子、
   半砖、楼梯、薄皮全被拉成1×1×1。

## 判据可得性（本轮复核结论）

- **`BlockRenderLayer` 确认不在 mc-sources**（全树 grep 零命中，已编译进客户端渲染库）⇒
  抄不到"方块→层"的完整注册表。
- **但判层入口可抄**：`ChunkSectionLayer.java`（`net/minecraft/client/renderer/chunk/`）——
  `SOLID / CUTOUT / TRANSLUCENT` 三层 + `byTransparency(Transparency)`：
  `t.hasTranslucent ? TRANSLUCENT : t.hasTransparent ? CUTOUT : SOLID`。
- **几何判据在 jar 内**：`models/block/*.json` 的 `parent` 与 `elements[].from/to`
  （构建期数据，非 mc-sources，不触"源码只读"红线）。

## What Changes

- **B分类改判据驱动**：删掉手写名单，改由模型 `parent`（`block/cross` ⇒ 十字面片，
  76 个模型）与贴图 alpha 特征推导渲染层与是否遮挡邻居。
- **A mesher 读 `elements`**：按真实 AABB + 逐面 UV 出几何（343 个模型含 elements），
  取代"一律整方块"。
- **C 面剔除随之精确**：半砖/薄皮不再遮整格邻居；判据是 AABB 而非整格占位。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `remote-play`: 「区块渲染为带贴图地形」的简化条款（"整块立方体+面剔除"）改为
  按模型几何渲染。

## Impact

- `packages/mc_resource`：`BlockModels` 解析 `parent` 链与 `elements`
- `packages/mc_render`：`block_semantics_v262.dart`（分类）、`mesher.dart`（几何）
- 不改协议。判据不可得处（`BlockRenderLayer`）以 jar 内模型数据替代并在代码注明。
