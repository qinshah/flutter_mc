# mc_nbt

Minecraft NBT 编解码。纯 Dart，无 Flutter 依赖，可在 worker isolate 运行。

## 原版对应物

判据 `mc-sources/minecraft-26.2`：

- `net.minecraft.nbt`（NbtIo / CompoundTag / 各 Tag 类）—— 磁盘与通用形态的 NBT 读写
- 网络形态 NBT（根无名字）由 `NbtReader.readNetworkRoot` 承接，对应原版
  `FriendlyByteBuf.readNbt` 的网络变体

## 用法

```dart
final tag = NbtReader.readRoot(bytes);            // 通用 NBT
final root = NbtReader.readNetworkRoot(bytes);    // 协议线上 NBT
```
