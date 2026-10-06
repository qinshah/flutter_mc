# Design

## Decisions

- **D1 装配点**：mc_session 内 `SessionAssembly.connectFor(ServerData, …)`——按 protocol 查注册表取协议实现；26.2 已注册，其余版本抛 `UnsupportedProtocolError`。会话代码保持不按版本分支。
  - 注册表实际形态：`Map<int, RemoteSessionFactory>`（`RemoteSessionFactory` = 建会话的函数类型）；26.2 的工厂即 `RemoteSession.new`——编解码层的多态（工厂体换成各自会话实现）在第二个协议版本落地时上收，本版不过早抽象。
  - `connectFor` 取 `ServerData.ip`（`host[:port]`）与 `ServerData.protocol`（status 探测回写）；未注册版本在**发起网络连接之前**即拒绝。
  - 地址解析落 `ServerAddress`（原版对应物 `client.multiplayer.resolver.ServerAddress`，Guava `HostAndPort` 语义：缺省端口 25565、IPv6 方括号、失败回落 `server.invalid:25565`）；标注简化点：无 `IDN.toASCII` 转码。
  - `ServerAddress` 是 mc_session 的新公开类型（任务原文只提"注册表 + connectFor"，地址解析是其前置契约），同时供多人屏加入路径复用，消除 `lib/` 里已有的 host/port 重复解析。
- **D2 mc_render 网格器**：移植 fscraft `mesher`（630 行，原版语义：整块立方体 + 面剔除 + 逐面 UV），适配两处数据源：方块状态来自 mc_session 区块调色板，贴图 UV 来自 mc_resource（BlockModels→atlas 矩形）。产出纯数据（顶点/UV/索引），golden 测试锁形状。简化点标注：无 AO/平滑光照/非常规形状（半砖/楼梯按整块渲染）。
- **D3 渲染消费**：app 壳 `GameScreen` = flutter_scene `SceneView`；每个已网格化分区一个 Mesh（图集单材质）。相机 = 玩家眼睛位置；朝向由输入驱动。
- **D4 移动与碰撞**：移植 fscraft `collision`（AABB 扫掠）与 `player` 物理（重力/跳跃/地面检测），世界查询换为 mc_session 区块数据；位置每 tick 上行 `MovePlayer`（onGround 语义照原版）。输入映射照原版 KeyMapping：W/A/S/D、空格跳。
- **D5 昼夜**：移植 fscraft `sky_model`（时间→天色/太阳角），时间源 = `TimeUpdated`；无数据时用默认正午。
- **D6 入口**：多人屏加入/直连 → 装配点 connect → JoinedGame 后 push `/game`（携带会话句柄）；失败显示错误返回列表。

## Risks / Trade-offs

- [fscraft 代码数据源差异较大，移植非机械] → 逐文件读原实现再改，保语义换数据面；golden 测试兜底
- [flutter_scene 0.24 API 陌生] → 先读 flutter_scene-idioms skill 与 fscraft 的 SceneView 用法
- [Paper 有实体/其它玩家不渲染但会推位置包] → mc_session 未识别包已按"跳过+计数"处理，不阻塞
- [无光照首版观感偏平] → 接受，光照采样列为后续 change
