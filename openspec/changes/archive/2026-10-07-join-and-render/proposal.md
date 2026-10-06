# Proposal

## Why

打通"连服游玩"最后一公里：从服务器列表加入真实服务器（本机 Paper 26.2），收到区块后以 flutter_scene 渲染出带贴图的世界，玩家可行走/跳跃（客户端本地碰撞预测，原版语义），昼夜天空随服务器时间流转。

## What Changes

- **版本装配点实体化**（多版本口径）：按 `ServerData.protocol` 选择协议实现接入会话；本版仅注册 26.2，不支持版本明确报错
- **mc_render 落地**：移植 fscraft `mesher`（630 行，照原版语义所写）适配服务器区块数据（mc_session 调色板）+ 资源包模型/图集（mc_resource），产出顶点/UV 纯数据；首版简化（整块立方体+面剔除、无 AO/平滑光照）并标注
- **游戏屏（app 壳）**：flutter_scene `SceneView` + 相机；键盘输入（WASD/空格，原版 KeyMapping 语义）→ `MovePlayer` 上行；碰撞预测移植 fscraft `collision`（408 行）；天空/昼夜移植 fscraft `sky_model`，时间源 = 会话 `TimeUpdated`
- 多人游戏屏"加入服务器/直接连接"接真：connect → JoinedGame → 进游戏屏
- 实体不做；方块交互（挖/放）不做（数据面已就绪，下一切片）

## Capabilities

### New Capabilities

- `remote-play`：加入服务器→世界渲染→输入上行的端到端契约

### Modified Capabilities

- `client-screens`：加入服务器/直接连接从占位改为真实连接入口

## Impact

- `packages/mc_session/`（装配点）、`packages/mc_render/`（网格器）、`lib/`（游戏屏+输入）、`lib/routes.dart`
- flutter_scene 仅 app 壳使用（红线不变）；验证需本机 Paper 服务器
