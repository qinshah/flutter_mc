# server-list Specification

## Purpose

定义服务器列表的持久化与管理契约：servers.dat 兼容读写（NBT 结构、原子轮换照原版），条目的添加/编辑/删除/直连地址输入，以及列表探测状态展示；为 join-and-render 的连接提供数据面。

## Requirements

### Requirement: servers.dat 兼容持久化

ServerList SHALL 以与原版一致的 NBT 结构（根 `servers` 列表，条目含 name/ip/hidden/icon）读写 `servers.dat`（gzip 压缩 NBT），写入 SHALL 原子化（临时文件→old→dat 轮换，写失败不上报成功）；存储位置为应用私有目录，路径由调用方注入，MUST NOT 读写用户 MC 目录。

#### Scenario: 读写往返

- **WHEN** 添加条目后保存再加载
- **THEN** 名称/地址/顺序一致；文件轮换产物（servers.dat_old）语义正确

### Requirement: 条目携带协议版本与探测缓存

ServerData SHALL 携带名称、地址与协议版本（未探测时默认当前锚点版本），并缓存 status 探测结果（协议号/MOTD/玩家数或失败态）；hidden 字段 MUST 写出以保持格式一致。

#### Scenario: 新增条目默认协议

- **WHEN** 新建条目未做探测
- **THEN** 协议版本为当前锚点（26.2），写出文件含 hidden=false

### Requirement: 列表管理操作

多人游戏屏 SHALL 支持：添加服务器（名称+地址表单）、编辑选中条目、删除选中条目（需二次确认）、直接连接（仅地址输入）。每个操作 SHALL 即时持久化到 servers.dat。

#### Scenario: 添加→列表→删除

- **WHEN** 添加一条服务器后删除并二次确认
- **THEN** 列表即时更新且重新加载后仍一致

### Requirement: 列表探测状态展示

进入列表 SHALL 对各条目做 status 探测并展示：成功显示 MOTD 与协议号，失败显示红字"无法连接至服务器"；"刷新" SHALL 重新探测。探测 MUST NOT 阻塞列表展示。

#### Scenario: 探测与刷新

- **WHEN** 存在一个可用服务器条目时进入列表并按刷新
- **THEN** 该条目显示服务器 MOTD 与协议号；不可达条目呈红字失败态
