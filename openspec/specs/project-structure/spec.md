# project-structure Specification

## Purpose

立起 flutter_mc 的仓库结构契约：Java→Dart 逐行翻译为默认行为、写代码前必须指名原版对应物、判据可追溯到源码行号、包布局映射原版源码树、包纯度边界、版本接入模式、参考源码与官方资产红线、文档单一权威，使后续所有 change 在稳定落点上按"逐行翻译"总纲演化。

## Requirements

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

### Requirement: Java→Dart 逐行翻译为默认行为

除下列三类自由设计外，仓库游戏代码 SHALL 按**Java 代码转成 Dart 代码那个级别的忠实**实现：
原版的**表达式顺序**、**常量**、**调用次序**、**分支条件**逐项对应；MUST NOT 做"功能等价"
或"效果类似"的改写，MUST NOT 把自己认为更合理的写法替换原版写法。允许的三类自由设计为：
3D 渲染后端（用 flutter_scene 替代 Java 渲染层，但深度测试/面剔除/混合/光照的**语义**
仍 SHALL 照原版）、玩家输入的事件来源（取自 Flutter 而非 GLFW）、数据上行（发服务器）。

#### Scenario: 表达式顺序不得改写

- **WHEN** 实现某段物理/编解码逻辑，其原版对应物中位移发生在扣重力**之前**
- **THEN** 我们的实现 MUST 保持该顺序；MUST NOT 以"数学上等价"为由调换顺序

#### Scenario: 常量按原版口径代入

- **WHEN** 原版表达式里的某个量来自属性系统（如 `getSpeed()` 返回属性值）而非常量字面量
- **THEN** MUST 沿用原版口径换算，MUST NOT 拿仓库内另一套量纲的同名概念代入

### Requirement: 写代码前必须先指名原版对应物

任何写代码的动作前，SHALL 先确认该代码的原版 Java 对应物（类/方法/字段）。若暂时指不出，
MUST 停止编写并去 `mc-sources/minecraft-26.2` 查找。若确认原版确实无对应物，MUST 在代码
注释或提交信息中写明属于三类自由设计之一、或指明 Flutter / flutter_scene 与Java 实现
的具体差异，方可继续。MUST NOT 以"看起来原版也差不多""我以为是这样"作为不翻译的理由。

#### Scenario: 指不出对应物时先停下

- **WHEN** 要写的逻辑在 mc-sources 中一时找不到对应物
- **THEN** 停止编写并继续查找或确认缺失，MUST NOT 先写一个"合理版本"再补注释

#### Scenario: 自由设计需写明理由

- **WHEN** 某段代码确定不翻译原版
- **THEN** 其注释或提交信息里指明属于 3D 渲染后端 / 输入来源 / 数据上行之一，
  或指明 Flutter、flutter_scene 与 Java 的具体 API 差异

### Requirement: 判据可追溯到源码位置

用于实现与测试的判据值（常量、公式、时序）SHALL 能指向 `mc-sources/minecraft-26.2` 的
具体文件与行号；指不出的 SHALL 视为猜测，MUST 先查证再使用。

#### Scenario: 判据指不到行号即视为猜测

- **WHEN** 一个数值/时序被用作实现依据但无法指到源码位置
- **THEN** 判为猜测，MUST 先在原版源码中定位对应表达式

### Requirement: 测试断言原版黄金值而非实现输出

测试 SHALL 断言**原版离线递推/核算得出的黄金值**，MUST NOT 以实现当前的输出作为期望值。
测试失败时 MUST 先怀疑实现并修改实现去对齐判据，MUST NOT 为让测试通过而修改期望值；
容差仅用于吸收纯浮点噪声，MUST NOT 用于掩盖判据层面的偏差。

#### Scenario: 实现偏了但期望值被改宽

- **WHEN** 实现与判据不符时，有人把测试期望值改成实现当前输出
- **THEN** 判为违规；处置是修正实现回判据，期望值保持原版黄金值

### Requirement: 原版"看起来奇怪"的行为仍是判据

原版实现中看起来不合常理的部分（如收尾系数直接乘速度、某些字段不参与某分支）SHALL 原样
照抄，MUST NOT 因其"不合理"而自行补充 `Math.max`、边界保护或"更稳健"的处理。

#### Scenario: 不给原版"补保护"

- **WHEN** 照抄原版逻辑时发现某处看起来会锁死/溢出/越界
- **THEN** 仍按原版实现，MUST NOT 额外加保护；确有原版之外的缺陷时另开 change 并附判据

### Requirement: 文档单一权威

`openspec/` SHALL 是流程唯一权威（当前做什么、验收标准、变更是否完成）；`README.md` 与 `AGENTS.md` SHALL 保持为短文档（README 是仓库地图与运行方式，AGENTS.md 是红线内联一页），MUST NOT 形成与 openspec 冲突的第二套规则正文。

#### Scenario: 文档冲突以 openspec 为准

- **WHEN** README / AGENTS.md 的内容与 openspec 固化内容冲突
- **THEN** 以 openspec 为准，并回改相应文档
