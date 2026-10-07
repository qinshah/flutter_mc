# Tasks

## 0. 判据复核（已完成）

- [x] 0.1 复核 `BlockRenderLayer` 是否在 mc-sources：**全树 grep 零命中**（已编译进
      客户端渲染库）⇒ 抄不到，替代判据为 jar 内模型数据
- [x] 0.2 找到可抄的判层入口：`ChunkSectionLayer.java`（三层枚举 +
      `byTransparency`）+ `Transparency.java`（四态）
- [x] 0.3 统计模型数据：含 `elements` 的 343 个（占 13%）、`parent=block/cross` 的 76 个

## 1. B — 分类改判据驱动（先做，可独立验收）

- [ ] 1.1 `mc_resource`：`BlockModels` 增加 `resolveParent`（沿 parent 链解析，
      子覆盖父）与"是否十字面片"查询；验证：`seagrass`/`kelp_plant` 判为十字
- [ ] 1.2 `mc_render/block_semantics_v262.dart`：删手写名单，改按模型 parent +
      贴图 alpha 推导 `layerIndexOf` / `isCross` / `hidesNeighbors`；顶部注明
      `BlockRenderLayer` 缺失与替代来源（design D4）
- [ ] 1.3 单测：海带/海草/藤蔓/睡莲 ⇒ cutout+十字；石头/泥土 ⇒ solid+遮邻居；
      水 ⇒ translucent；验证：断言判据来源而非实现输出
- [ ] 1.4 真机：海带/海草不再显示为青蓝冰柱

## 2. A — mesher 读 elements

- [ ] 2.1 `mc_resource`：解析 `elements[].from/to` 与 `faces[].uv/texture`，
      构建期预解析成合并产物（运行期只查表）
- [ ] 2.2 `mesher.dart`：按 AABB 出面（顶/底/四侧），逐面 UV 取模型给定值
- [ ] 2.3 带 `rotation` 的元素（楼梯斜面）：**显式标注为未支持**，MUST NOT
      静默按未旋转渲染
- [ ] 2.4 单测：竹子 `from[7,0,7] to[9,16,9]` ⇒ 顶面 UV 只覆盖格中央 2/16；
      半砖 ⇒ 只生成下半 2 个面
- [ ] 2.5 真机：竹子呈细柱、半砖/楼梯形态正确

## 3. C — 面剔除随之精确

- [ ] 3.1 `hidesNeighbors` 与面剔除改用真实 AABB：半砖/薄皮不遮整格邻居
- [ ] 3.2 实机确认视觉与碰撞（仍按整格）不产生"卡墙"观感

## 4. 验收

- [ ] 4.1 `dart analyze` 零 issue；各包测试 + app 测试全绿
- [ ] 4.2 真机（Paper 26.2 + dart MCP 截图）：海带/海草/竹子/半砖/楼梯形态正确，
      无青蓝冰柱、无红色、无穿插破面

**遗留（不在本 change）**：光照（AO/平滑/lightmap）、天气、天空 —— 见
`docs/translation-debt.md`；模型带 rotation 的几何；碰撞的细粒度 AABB。
