# mc_protocol_v26_2

MC 26.2 协议的包类型登记与编解码。判据 = `mc-sources/minecraft-26.2`；依赖 mc_wire 的传输核心与 mc_nbt。版本特定代码只落在此形态的版本包中，新协议版本以新增 `mc_protocol_v<主>_<次>` 包接入，业务代码禁止按版本号分支。

## 原版对应物

判据 `mc-sources/minecraft-26.2`：

- `net.minecraft.network.protocol.*` —— 各阶段（handshake/status/login/configuration/play）
  clientbound / serverbound 包类型与 `StreamCodec` 编解码
- 包 ID 与阶段登记对应 `ConnectionProtocol` 的包映射

## 用法

由 `mc_session` 经版本装配点选用；应用一般不直接依赖本包。
