# Design

## Decisions

- **D1 归属**：ServerData/ServerList 落 mc_session（对应原版 `client/multiplayer`），纯 Dart；存储路径由调用方注入（app 壳用 path_provider 的应用文档目录），包不碰平台。
- **D2 持久化细节照原版**：gzip 压缩 NBT（NbtIo.write 语义）；条目 write 含 name/ip/icon(可空,本期不存图标)/hidden；原子轮换 temp→old→dat；读失败按原版口径记日志并以空列表继续。
- **D3 探测**：`pingServer`（mc_session 现有）对列表逐条并发调用；ServerInfo.protocolId 回写条目协议字段（对应原版列表按 ping 缓存协议版本的多版本口径）。
- **D4 屏幕结构**：ManageServerScreen（名称/地址 + 完成/取消，新增与编辑共用，编辑传条目下标）；DirectJoinServerScreen（地址 + 加入/取消，加入=占位提示）；删除确认屏照原版 ConfirmScreen 语义（正文 + 确认/取消）。三条路由挂 /multiplayer 下。
- **D5 连接占位**：加入服务器/直连的"加入"在 join-and-render 前显示占位提示（SnackBar 风格的临时条）——导航点已通，数据面就绪。

## Risks / Trade-offs

- [列表条目多时并发 ping 压力] → 实际个人列表条目个位数，直接全并发
- [servers.dat 与官方版字段差异（icon/packStatus）] → 读写均以"存在才写、缺失给默认"兼容，不会破坏官方格式的互读
