# Spec Delta

## MODIFIED Requirements

### Requirement: Java→Dart 逐行翻译为默认行为

除下列**三类**自由设计外，仓库游戏代码 SHALL 按**Java 代码转成 Dart 代码那个级别的忠实**
实现：原版的**表达式顺序**、**常量**、**调用次序**、**分支条件**逐项对应；MUST NOT 做
"功能等价"或"效果类似"的改写，MUST NOT 把自己认为更合理的写法替换原版写法。

允许的自由设计**仅限环境确实无 Java 可抄的三处**：

1. **3D 渲染后端** —— 用 flutter_scene 替代 Java 渲染层；但深度测试、面剔除、混合、
   光照的**语义**仍 SHALL 照原版。
2. **输入事件采集** —— 取自 Flutter 组件（含触屏、手柄）而非 GLFW 回调；但视角换算、
   键位映射等**语义**仍 SHALL 照原版。
3. **运行时宿主（JVM 托管）** —— 指"如何在平台上承载外部 JVM 与被托管的 Java 产物"
   这类**环境机制**（桌面复用系统 JVM、Android 无系统 Java 运行时的承载方式、进程与
   日志管道的接法）；但**语义**仍 SHALL 照原版（启动参数语义、服务端配置口径、
   就绪判定、控制通道的协议与鉴权）。本类**仅**豁免"承载方式"，MUST NOT 借它豁免任何
   原版有 Java 对应物的功能逻辑——被托管物自身的差异一律按翻译债处理（见能力
   `translation-debt`）。

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

#### Scenario: 宿主机制可豁免，语义不可豁免

- **WHEN** 实现平台承载方式（如以进程或嵌入式 JVM 运行被托管产物）
- **THEN** 该承载方式 MAY 标注为第三类"运行时宿主"并写明平台 API 差异；但启动参数语义、
  配置口径、就绪判定、控制通道协议 MUST 照原版，且被托管物本身的未翻译差异 MUST 登记为
  翻译债

### Requirement: 写代码前必须先指名原版对应物

任何写代码的动作前，SHALL 先确认该代码的原版 Java 对应物（类/方法/字段）。若暂时指不出，
MUST 停止编写并去 `mc-sources/minecraft-26.2` 查找。若确认原版确实无对应物，MUST 在代码
注释或提交信息中写明属于三类自由设计之一（3D 渲染后端 / 输入事件采集 / 运行时宿主），
或指明 Flutter / flutter_scene 与 Java 实现的具体差异，方可继续。MUST NOT 以"看起来原版也
差不多""我以为是这样"作为不翻译的理由。

#### Scenario: 指不出对应物时先停下

- **WHEN** 要写的逻辑在 mc-sources 中一时找不到对应物
- **THEN** 停止编写并继续查找或确认缺失，MUST NOT 先写一个"合理版本"再补注释

#### Scenario: 自由设计需写明理由

- **WHEN** 某段代码确定不翻译原版
- **THEN** 其注释或提交信息里指明属于 3D 渲染后端 / 输入事件采集 / 运行时宿主之一，
  或指明 Flutter、flutter_scene 与 Java 的具体 API 差异
