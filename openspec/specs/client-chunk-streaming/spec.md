# client-chunk-streaming Specification

## Purpose
TBD - created by archiving change chunk-streaming-align. Update Purpose after archive.

## Requirements

### Requirement: 固定容量存储环持有区块

客户端 SHALL 以固定容量存储环（容量 = `(2×存储半径+1)²`，存储半径 = `max(2, 视距半径)+3`）持有已加载区块；落到环内索引的写入 SHALL 顶替同索引旧列并触发其卸载事件。环内不存在的区块查询 SHALL 按"空气"语义处理（不阻挡移动）。

#### Scenario: 顶替旧列即卸载

- **WHEN** 一个新区块写入存储环且其索引上已有旧列
- **THEN** 旧列被卸载（产生卸载事件），新列占据该索引

#### Scenario: 未加载列按空气处理

- **WHEN** 碰撞查询命中一个不在存储环中的列
- **THEN** 该列不产生阻挡（玩家按物理照常移动，由服务器权威校正兜底）

### Requirement: 窗口几何由服务器包驱动

客户端 SHALL 消化 `SetChunkCacheCenter` 与 `SetChunkCacheRadius` 包更新窗口几何（center 直接更新；radius 经 `max(2, r)+3` 换算为存储半径，半径变化时按新几何重建存储环并迁移仍在新窗口内的列）。落在窗口几何之外的下发区块 SHALL 被拒收（不进入存储环）。

#### Scenario: 中心更新后越界写入被拒

- **WHEN** 窗口中心已更新为新坐标，服务器下发一个在新窗口之外（切比雪夫距离 > 存储半径）的区块
- **THEN** 该区块被拒收，不产生加载事件，并留下警告级诊断

#### Scenario: 半径缩小迁移存活列

- **WHEN** 视距半径缩小导致存储半径变小
- **THEN** 仍在新窗口内的列迁移进新存储环，窗口外的列被卸载

### Requirement: 忘记列与顶替列统一产生卸载

服务器 `ForgetLevelChunk`、存储环顶替、窗口半径缩小三条路径 SHALL 统一产生同一卸载事件，渲染端据此移除对应网格与待网格化条目。

#### Scenario: 服务器忘记列

- **WHEN** 服务器下发 `ForgetLevelChunk(x,z)` 且该列在存储环中
- **THEN** 该列被卸载并产生卸载事件

### Requirement: 批次应答速率按客户端计时计算

客户端 SHALL 按原版口径计算批次期望速率：批次开始记时，批次结束时以"批次耗时 ÷ 批次大小"采样，经钳制（采样钳制在累计均值的 1/3..3 倍之间）后并入加权滑动平均（权重自 1 起累加、上限 49），期望速率 = 7,000,000 纳秒预算 ÷ 累计均值（初值 2,000,000 纳秒/列）；应答包 SHALL 携带该期望速率。MUST NOT 把服务器的批次大小直接当期望速率回传。

#### Scenario: 批次应答携带计时得出的期望速率

- **WHEN** 一个区块批次完成（批次大小 > 0）
- **THEN** 客户端按上述公式更新累计均值并应答期望速率（初批约为 3.5 列/刻量级，随实测吞吐收敛）
