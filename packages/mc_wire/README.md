# mc_wire

MC 协议传输核心：VarInt、分帧、zlib 帧内压缩、协议阶段状态机骨架、包登记表接口。版本无关——本包不认识任何具体包类型与版本号；26.2 的包类型与编解码在 `mc_protocol_v26_2`。纯 Dart，无 Flutter 依赖。

## 原版对应物

判据 `mc-sources/minecraft-26.2`：

- `net.minecraft.network.FriendlyByteBuf` —— VarInt/VarLong 等线上基础类型
- `net.minecraft.network.Connection` / `ConnectionProtocol` —— 连接与协议阶段状态机
- `net.minecraft.network.CompressionEncoder` / `CompressionDecoder` —— 帧内 zlib 压缩

## 用法

会话层（`mc_session`）经 `Connection` 建立连接并按阶段取用登记表；应用一般不直接依赖本包。
