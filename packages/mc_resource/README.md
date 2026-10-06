# mc_resource

资源包读取抽象：来源可插拔（本机目录 / zip / 未来应用内下载 jar），把资产解析为纯数据。构建期提取官方 client jar 的管线与产物由 app 壳侧接入，本包只认"资源包"抽象。纯 Dart。

## 原版对应物

判据 `mc-sources/minecraft-26.2`：

- `net.minecraft.server.packs.AbstractPackResources` / `FilePackResources` —— 资源包来源抽象
- `net.minecraft.server.packs.resources.ResourceManager` 等同类 —— 资源加载与重载管线
- `net.minecraft.client.resources` —— 客户端资源装配（语言/元数据/皮肤等）

## 边界与首个 change

- 依赖 mc_nbt（读 NBT 形态资产）；不得依赖任何 Flutter 或引擎类型
- 首个预期 change：PackResources 式资源抽象 + 构建期提取管线（`tool/extract_assets.dart` 从骨架转正）
