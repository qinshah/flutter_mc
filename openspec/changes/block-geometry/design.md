# Design

## Context

见proposal.md - Why。此处只记录**复核过的判据可得性**与由此决定的方案边界。

### 判据清单（审查门禁必需）

| 判据 | 位置 | 状态 |
|---|---|---|
| 三层枚举 `SOLID / CUTOUT / TRANSLUCENT` | `net/minecraft/client/renderer/chunk/ChunkSectionLayer.java` | ✅ 可抄 |
| 判层入口 `byTransparency(t)` | 同上（`t.hasTranslucent ? TRANSLUCENT : t.hasTransparent ? CUTOUT : SOLID`） | ✅ 可抄 |
| `Transparency` 四态（NONE/TRANSPARENT/TRANSLUCENT/两者） | `com/mojang/blaze3d/platform/Transparency.java` | ✅ 可抄 |
| 方块→层的完整注册表 | `BlockRenderLayer` | ❌ **不在 mc-sources**（全树 grep 零命中） |
| 模型几何 `elements[].from/to` + 逐面 `faces` | jar 内 `models/block/*.json` | ✅ 可得（构建期数据） |
| 模型 parent（如 `block/cross`） | jar 内 `models/block/*.json` | ✅ 可得；`block/cross` 共 76 个模型 |

**当前代码**（`packages/mc_render/lib/src/`）：
- `block_semantics_v262.dart`：`_crossNames`（40 项手写）、`_isCutoutName`（只认
  leaves/glass）、`_isFlatGroundCover`（8 项）；`layerIndexOf` 依次问这三个。
- `mesher.dart`：不读 `elements`，一律按整方块 6 面生成。

## Goals / Non-Goals

- 目标：海带/海草/藤蔓/睡莲不再被当实心立方体（分类由判据推导）。
- 目标：mesher 按模型 `elements` 出真实几何（竹子 2×16×2、半砖、楼梯）。
- 目标：面剔除改用真实 AABB。
- 非目标：**光照**（AO/平滑/lightmap）、**天气**、**天空**——这三项是独立翻译债，
  本 change 不碰。

## Decisions

- **D1 分类改为"模型 parent 优先、alpha 兜底"**。判据链：
  `parent == block/cross` ⇒ 十字面片（cutout 层，不遮邻居）；
  贴图含半透明像素 ⇒ translucent（可透但不遮）；否则 solid。
  *备选*：继续扩充手写名单。**否决**——`kelp`/`seagrass` 这类正是名单漏的，
  扩充只是延后同一问题（且违反新立的spec「渲染层由判据推导」）。
- **D2 几何从模型 `elements` 来**。`BlockModels` 增加 `elements` 解析（沿 parent 链
  继承，子覆盖父），mesher 按 AABB 出面。*备选*：只对已知非整方块硬编码。
  **否决**——343 个模型含 elements，硬编码必然漏。
- **D3 十字面片走既有 `_emitCross`**。海带/海草的 parent 就是 `block/cross`，
  判层为 cutout + `isCross=true`，可直接复用已实现的十字面片路径，
  **无需 mesher 改动**——这是 B 能独立先做的关键。
- **D4 `BlockRenderLayer` 缺失写成注释**（新 spec 要求）。在
  `block_semantics_v262.dart` 顶部注明：该注册表已编译进客户端渲染库、
  mc-sources 不可得，替代判据为模型 parent + 贴图 alpha。

## Risks / Trade-offs

- [模型 parent 链很深，解析成本] → 构建期预解析成贴图+几何的合并产物，
  运行期只查表。
- [AABB 面剔除可能暴露既有"整格占位"假设（碰撞仍按整格）] → 本 change 只改渲染，
  碰撞的细粒度 AABB 另开债；但须保证视觉与碰撞不一致时不产生"卡墙"观感，
  实机验收时确认。
- [343个模型的几何形态各异（多元素、旋转 22.5°）] → 先覆盖无旋转的 AABB，
  带 rotation 的（如楼梯斜面）单独标注为后续债，MUST NOT 静默按未旋转渲染。

## Migration Plan

纯渲染层改动，无数据迁移。回滚 = 恢复 `mesher.dart` 与 `block_semantics_v262.dart`。

## Open Questions

无。判据可得性已复核（见上表），方案边界由可得性决定。
