# resource-pipeline Specification

## Purpose

定义官方资产的构建期提取与读取契约：从用户本机官方 client jar 提取方块资产到版本标记目录（不入库），mc_resource 以版本键、可插拔来源读取，并提供方块模型到贴图路径的解析；为未来"应用内按版本下载 jar"预留来源扩展位。

## Requirements

### Requirement: 构建期提取到版本标记目录

提取工具 SHALL 从用户指定的官方 client jar 读取并提取方块资产（blockstates、models/block、textures/block）到 `assets/vanilla/<协议版本>/` 目录，保持 jar 内相对路径；提取 SHALL 只读 jar、产物写入该版本目录。产物 MUST NOT 入库（gitignore 覆盖）。

#### Scenario: 提取产物落位

- **WHEN** 以 26.2 jar 运行提取
- **THEN** `assets/vanilla/26_2/` 下出现 blockstates / models / textures 结构与 `generated/` 图集，`git status` 不显示这些产物

### Requirement: 方块图集预拼接

提取时 SHALL 把方块贴图拼接为单张图集（`generated/block_atlas.png`），并写出 JSON 清单（`generated/atlas.json`）记录每个贴图名到图集矩形的映射，供网格化取 UV。

#### Scenario: 清单与图集一致

- **WHEN** 提取完成
- **THEN** atlas.json 中每个条目指向的矩形都在图集尺寸内，且贴图名与提取的贴图文件一一对应

### Requirement: VanillaPack 版本键读取

mc_resource SHALL 提供按版本键构造的资源包读取（`VanillaPack`），来源可插拔（应用 bundle 或文件目录），SHALL 支持按相对路径读取字节与存在性判断；包内容缺失时读取 SHALL 返回明确结果而非抛出异常路径。

#### Scenario: 按路径读取与缺失

- **WHEN** 读取存在与不存在的资产路径
- **THEN** 存在路径返回字节，缺失路径返回空结果，不抛异常

### Requirement: 方块模型解析

mc_resource SHALL 解析方块状态 JSON（variants 形态）到模型文件，沿 parent 链合并贴图映射，并把 `#` 引用插值为最终贴图路径；multipart 形态首版 MAY 降级为取首个可用模型（标注简化）。

#### Scenario: parent 链与插值

- **WHEN** 解析一个经由父模型继承贴图变量的方块状态
- **THEN** 得到各面向的最终贴图路径，`#xxx` 引用被替换为实际路径
