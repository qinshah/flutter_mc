# Design

## Decisions

- **D1 装配点**：mc_session 内 `SessionAssembly.connectFor(ServerData, …)`——按 protocol 查注册表取协议实现；26.2 已注册，其余版本抛 `UnsupportedProtocolError`。会话代码保持不按版本分支。
  - 注册表形态：`Map<int, SessionProtocol>`。`SessionProtocol`（**装配点适配，无原版对应物**）持该版本的实测 protocolId，并提供两个入口：`createSession`（同 isolate、不连接；纯 Dart 宿主与单测）与 `spawn`（worker isolate、spawn 即连接；app 壳）。
  - **会话进程口径**：app 壳走 `connectFor(ServerData, …) → Future<SessionHandle>`，即 worker isolate 会话（沿既有 D3 与 `session_isolate.dart`）——协议解析与网格化不占主线程。句柄只暴露"命令 SendPort + 事件流"，业务代码看不见协议号。
  - `connectFor` 取 `ServerData.ip`（`host[:port]`）与 `ServerData.protocol`（status 探测回写）。未注册版本**同步**抛 `UnsupportedProtocolError`（在 spawn isolate / 发起网络连接之前；同步而非失败 Future，免得配置错误被未 await 的 Future 吞掉）。
  - `connectFor` **不等"进服成功"**：返回句柄后由调用方订阅事件流——`JoinedGame` 即推进，`SessionClosed` 即报错（D6 据此接线）。
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
- [4.1 实拍的"大片红色"已定论：**不是渲染缺陷**。视线射线探针 172/172 次命中
  `leaf_litter`（落叶层，本色即红褐），而网格器有已标注的简化"所有方块按整块渲染"，
  于是成片的落叶层被画成整块红方块。排查过程留下两个可复用探针：[TEXMAP]（贴图解析
  映射，已证全部正确）与视线射线（[TRACE] 的 `看=` 字段）。教训：早期把"天空的红"
  与"方块的红"混为一谈，去掉 IBL 绑定后才分开——**先分离现象再解释**。]
- [图集打包浪费 65%：`tool/extract_assets.dart` 的宽度选择是"能装下就停"，1227 张 16px 贴图停在 256 宽 → 256×2048，实际只用到约 1232 行、下半 816 行全黑] → 4.1 实拍发现：上色后大片表面呈深红/异常，且 mipmap 一旦降级就被黑区污染。修法：改为选**接近正方形、浪费最小**的宽度（例如 512×512），并重跑提取器验证；若红面仍在，则打印每个面实际使用的 UV rect 与贴图路径定位。
