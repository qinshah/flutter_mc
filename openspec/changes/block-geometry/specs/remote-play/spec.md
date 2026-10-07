# Spec Delta

## MODIFIED Requirements

### Requirement: 区块渲染为带贴图地形

进入世界后，收到的区块 SHALL 被网格化（方块状态→资源包模型→图集 UV）并渲染为 3D 地形；
网格化在纯 Dart 侧产出顶点/UV 数据，flutter_scene 仅在 app 壳消费。

网格化 SHALL 按**资源包模型的真实几何**出网格：模型声明 `elements` 时按其逐个 AABB 与
逐面 UV 生成，MUST NOT 一律按 1×1×1 整方块渲染。方块的**渲染层**（solid / cutout /
translucent）与**是否遮挡邻居**SHALL 由判据推导，MUST NOT 由手写方块名名单决定；
判据不可得时 MUST 在代码注明所替代的判据来源。

仍允许的简化：**光照**（无 AO / 平滑光照 / lightmap）、**天气**、**天空**。
这三项 SHALL 在代码标注为翻译债。

#### Scenario: 进服可见地形

- **WHEN** 加入在线服务器并等待区块批量下发
- **THEN** 游戏屏渲染出与服务器地形一致的方块世界（有贴图）

#### Scenario: 非整方块模型按真实几何渲染

- **WHEN** 区块含声明了 `elements` 的模型（如半砖、楼梯、竹子这类非1×1×1 几何）
- **THEN** 网格 SHALL 按其AABB 生成，MUST NOT 被拉成整方块

#### Scenario: 渲染层由判据推导而非手写名单

- **WHEN** 一个方块（如海带、海草）此前未出现在任何分类名单里
- **THEN** 其渲染层与遮挡行为 SHALL 由判据推导得到，MUST NOT 因"名单没收录"而
  落入实心层

## ADDED Requirements

### Requirement: 渲染判据缺失时须记录来源

当某项判据在 `mc-sources` 中不存在（如方块到渲染层的完整注册表已编译进客户端渲染库），
实现SHALL 改用可得的等价判据（如资源包模型数据），并在代码注释中写明：原判据为何不可得、
替代判据来自何处。MUST NOT 在无判据的情况下凭"看起来应该属于哪层"编写分类逻辑。

#### Scenario: 判据不可得时的替代

- **WHEN** 某分类所需的原版注册表在 mc-sources 中不存在
- **THEN** 代码注释写明该事实与替代判据来源，MUST NOT 留下未说明的经验性名单
