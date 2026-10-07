# Spec Delta

## MODIFIED Requirements

### Requirement: Java→Dart 逐行翻译为默认行为

除下列**两类**自由设计外，仓库游戏代码 SHALL 按**Java 代码转成 Dart 代码那个级别的忠实**
实现：原版的**表达式顺序**、**常量**、**调用次序**、**分支条件**逐项对应；MUST NOT 做
"功能等价"或"效果类似"的改写，MUST NOT 把自己认为更合理的写法替换原版写法。

允许的自由设计**仅限环境确实无Java 可抄的两处**：

1. **3D 渲染后端** —— 用 flutter_scene 替代 Java 渲染层；但深度测试、面剔除、混合、
   光照的**语义**仍 SHALL 照原版。
2. **输入事件采集** —— 取自 Flutter 组件（含触屏、手柄）而非 GLFW 回调；但视角换算、
   键位映射等**语义**仍 SHALL 照原版。

**数据上行不再属于自由设计**：原版有完整客户端上行流程
（`ClientCommonPacketListenerImpl` 的 keepAlive/cookie/resource-pack/`sendDeferredPackets`、
`ClientPacketListener.notifyPlayerLoaded`），本仓 SHALL 逐行翻译其发送条件与时序。

凡原版有 Java 实现而本仓标为简化/占位/未实现之处，SHALL 登记为**翻译债**（见能力
`translation-debt`），MUST NOT 再称作自由设计。

#### Scenario: 表达式顺序不得改写

- **WHEN** 实现某段物理/编解码逻辑，其原版对应物中位移发生在扣重力**之前**
- **THEN** 我们的实现 MUST 保持该顺序；MUST NOT 以"数学上等价"为由调换顺序

#### Scenario: 常量按原版口径代入

- **WHEN** 原版表达式里的某个量来自属性系统（如 `getSpeed()` 返回属性值）而非常量字面量
- **THEN** MUST 沿用原版口径换算，MUST NOT 拿仓库内另一套量纲的同名概念代入

#### Scenario: 上行走原版流程

- **WHEN** 实现登录、keepAlive、移动、加载完成通知等任一上行
- **THEN** MUST 翻译原版的发送条件与节流/时序，MUST NOT 援引自由设计豁免

## ADDED Requirements

### Requirement: 命名与文件路径照原版

翻译代码时 SHALL 沿用原版的类名、方法名、字段名与包结构到可映射的程度：一个 Java 类
SHALL 对应一个 Dart 文件，MUST NOT 把多个 Java 类合并进同一文件；命名 SHALL 保留原版的
词与结构（例：`LivingEntity`/`Player`/`KeyMapping`/`LevelRenderer`），MUST NOT 另造
"更达意"的名字（例：`player_controller`、`key_map`、`mesher`）。仅在语言惯例必须时
（如 Java 首字母大写的类型→Dart 小写文件）才做语法必需的调整，MUST NOT 做语义改名。

#### Scenario: 一个 Java 类对应一个 Dart 文件

- **WHEN** 需要实现原版的 `LivingEntity` 与 `Player`
- **THEN** 分别落在独立 Dart 文件中，MUST NOT 合并成一个 `player_controller.dart`

#### Scenario: 不另造名字

- **WHEN** 为原版某个类/方法/字段命名 Dart 对应物
- **THEN** 沿用原版命名；MUST NOT 因为"更清楚"而改成自定义名，改名需记录偏离理由
