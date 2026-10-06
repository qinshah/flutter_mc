# Proposal

## Why

快速连服游玩需要真实的服务器列表管理：手动添加/编辑/删除与直接连接（LAN 发现明确延后）。原版对应 `client/multiplayer` 的 ServerList/ServerData（servers.dat 持久化）与 `ManageServerScreen`/`DirectJoinServerScreen`。

## What Changes

- mc_session 新增 `ServerData`（名称/地址/协议版本缓存/探测结果）与 `ServerList`（servers.dat 兼容读写：NBT 结构照原版，含 hidden 字段与 new→old→dat 原子轮换；路径由调用方注入）
- mc_ui 新增 `MCEditBox`（原版 EditBox 形态：暗底细框、聚焦白框、文本编辑）
- app 壳：多人游戏屏接真实列表（替换硬编码条目）；新增 添加/编辑服务器屏、直接连接屏、删除二次确认；进入列表逐条 ping 显示状态，刷新可重探
- 加入服务器：选中条目即可用；连接行为占位（join-and-render 接入）

## Capabilities

### New Capabilities

- `server-list`：服务器列表的持久化（servers.dat 兼容）与列表管理行为

### Modified Capabilities

- `mc-ui-components`：ADDED MCEditBox 控件契约
- `client-screens`：MODIFIED 多人游戏屏内容（固定示例条目 → 真实列表与管理操作）

## Impact

- `packages/mc_session/`（新增两文件+测试）、`packages/mc_ui/`（MCEditBox+测试）、`lib/screens/multiplayer/`、`lib/routes.dart`
- 存储文件：应用私有目录 `servers.dat`（不改用户 MC 目录）
