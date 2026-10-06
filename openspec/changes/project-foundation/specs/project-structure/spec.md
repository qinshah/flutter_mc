# Spec Delta

## Purpose

立起 flutter_mc 的仓库结构契约：包布局映射原版源码树、包纯度边界、版本接入模式、参考源码与官方资产红线、文档单一权威，使后续所有 change 在稳定落点上按"忠实翻译"总纲演化。

## ADDED Requirements

### Requirement: 包布局映射原版源码树

仓库的游戏代码 SHALL 按"一个包对应原版一个源码层次"组织：mc_nbt / mc_wire / mc_protocol_v26_2 对应原版网络编解码与 NBT，mc_session 对应 `client/multiplayer`，mc_resource 对应 `client/resources`，mc_render 对应原版渲染数据半边（模型烘焙与区块编译），mc_ui 对应 `client/gui/components`，app 壳 lib/ 对应原版客户端平台绑定层。后续新增游戏代码 MUST 先指明其原版对应物（或显式标注为"后端适配"），MUST NOT 在既有层次之外随意新增顶层目录。

#### Scenario: 新代码先找原版对应物

- **WHEN** 开发者要新增一个游戏逻辑模块
- **THEN** 必须能指名它翻译自哪个原版层次/类，才能落进对应包；无原版对应物的模块只能落在 app 壳并标注"后端适配"

### Requirement: 包纯度边界

`packages/` 下的包 SHALL 保持纯 Dart（不 import flutter 与 flutter_scene）；唯一例外 mc_ui 允许依赖 Flutter 但 MUST NOT 依赖 flutter_scene。flutter_scene SHALL 只被 app 壳 lib/ 直接使用。包与应用之间 MUST 只传纯数据（区块、调色板、实体状态、顶点数据）。

#### Scenario: 引入 flutter_scene 越界

- **WHEN** packages/ 下任意代码 import flutter_scene
- **THEN** 判为违规，处置是该依赖移入 app 壳，包间只留数据类型

#### Scenario: mc_ui 允许依赖 Flutter

- **WHEN** mc_ui 的代码 import package:flutter
- **THEN** 合规（唯一例外），但 import flutter_scene 仍判违规

### Requirement: 版本包接入模式

版本特定代码 SHALL 只存在于名为 `mc_protocol_v<主>_<次>` 形态的版本包中；会话层 SHALL 通过唯一装配点按服务器握手得到的协议版本选择版本实现，MUST NOT 在业务代码中按版本号做 if/switch 分支。新增协议版本 SHALL 以新增版本包接入。

#### Scenario: 服务器版本决定实现

- **WHEN** 客户端完成 status 握手得知服务器协议版本
- **THEN** 会话层从装配点取得该版本对应的协议实现并用它编解码；不支持的版本明确报错

#### Scenario: 版本号分支被拒

- **WHEN** 业务代码出现按版本号 if/switch 选择行为的分支
- **THEN** 审查判为违规，处置是拆进版本包并在装配点收口

### Requirement: mc-sources 只读

`mc-sources/` SHALL 保持只读参考：不得修改其中文件、不得提交入库（gitignore 覆盖）、代码 MUST NOT 以任何形式依赖或导入其内容（它是人工对照的参考，不是编译依赖）。

#### Scenario: 参考源码不被引用

- **WHEN** 仓库任何 Dart 代码 import 或在运行期读取 mc-sources/
- **THEN** 判为违规；mc-sources 仅供开发期人工/工具对照

### Requirement: 官方资产不入库

Mojang 官方资源（client jar 与从中提取的资产）SHALL 不提交进版本库：提取工具从用户本机提供的 jar 读取，产物写入 gitignore 覆盖的目录；任何包（含 mc_ui）MUST NOT 捆绑官方资产文件。

#### Scenario: 提取产物入库被拒

- **WHEN** 提取工具的产物目录内容出现在 git 追踪中
- **THEN** 判为违规；该目录必须被 .gitignore 覆盖

#### Scenario: mc_ui 不带官方贴图

- **WHEN** mc_ui 需要按钮/字体等外观资源
- **THEN** 由调用方经资源抽象注入，包内不含官方资产文件

### Requirement: 文档单一权威

`openspec/` SHALL 是流程唯一权威（当前做什么、验收标准、变更是否完成）；`README.md` 与 `AGENTS.md` SHALL 保持为短文档（README 是仓库地图与运行方式，AGENTS.md 是红线内联一页），MUST NOT 形成与 openspec 冲突的第二套规则正文。

#### Scenario: 文档冲突以 openspec 为准

- **WHEN** README / AGENTS.md 的内容与 openspec 固化内容冲突
- **THEN** 以 openspec 为准，并回改相应文档
