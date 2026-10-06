# Spec Delta

## MODIFIED Requirements

### Requirement: 菜单页面链路

应用 SHALL 提供路由：`/`（标题屏）、`/multiplayer`（多人游戏）、`/settings/video`（视频设置）、`/game`（游玩屏，join-and-render 接入）。标题屏 SHALL 可进入多人游戏与视频设置；多人游戏的"返回"与视频设置的"完成" SHALL 回到标题屏。加入服务器/直接连接的"加入" SHALL 以装配点建立会话并在成功后进入游玩屏，失败 SHALL 回多人游戏屏并显示可操作错误。路由唯一事实来源是 `lib/routes.dart`。

#### Scenario: 冷启动进标题屏

- **WHEN** 应用启动
- **THEN** 首屏为标题屏，出现 MINECRAFT 标题区与主按钮组

#### Scenario: 进入并返回

- **WHEN** 标题屏点"多人游戏"再点"返回"，或点"选项…"进视频设置后点"完成"
- **THEN** 均回到标题屏，无路由残留错误
