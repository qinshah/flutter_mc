# flutter_mc 执行规则

## 最高纪律：Java → Dart **逐行翻译**

行为判据只有一份：`mc-sources/minecraft-26.2` 官方源码（只读参考，不入库）。
**翻译目标是 Java 代码转成 Dart 代码那个级别的忠实**——不是"功能等价"、不是"效果类似"，
而是原版每一步计算，我们就是对应的一步计算；原版的常量、表达式、调用顺序、分支条件，
逐项对应。

**自由设计只有两类**（环境确实无 Java 可抄，且仅此两类）：

1. **3D 渲染后端**：用 flutter_scene 替代 Java 渲染层。语义（深度测试、面剔除、混合、
   光照）仍要照原版。
2. **输入事件采集**：取自 Flutter 组件（含触屏、手柄）而非 GLFW 回调。语义（视角换算
   公式、键位映射）仍要照原版。

**数据上行不是自由设计** —— 原版有完整流程（`ClientCommonPacketListenerImpl` 的
keepAlive/cookie/resource-pack/`sendDeferredPackets`、`ClientPacketListener.notifyPlayerLoaded`），
必须逐行翻译其发送条件与时序。

### 写代码前必须问自己

> 这段代码的原版 Java 对应物在哪里？它真的不需要翻译吗？

- **答不上来 ⇒ 停下来去 mc-sources 找**，找到后照抄对应 Java 的逻辑与常量（可改语法、
  改语言特性，但不得改数值、改顺序、改语义）。
- **确实没有对应物** ⇒ 必须**在代码注释或提交信息里写明**属于上述两类之一（或指明
  Flutter / flutter_scene 的具体 API 差异）。
- **原版有 Java 但我们简化了** ⇒ 那是**翻译债**，登记进 `docs/translation-debt.md`，
  **MUST NOT** 叫它"自由设计"。
- "看起来原版也差不多""我以为是这样"**都不算理由**。理由必须能指向源码行号。

### 命名与路径也照原版

类名、方法名、字段名、文件路径 SHALL 沿用原版：**一个 Java 类对应一个 Dart 文件**。
MUST NOT 合并多个 Java 类到一个文件，也 MUST NOT 另造"更达意"的名字
（`LivingEntity`+`Player` 不该叫 `player_controller.dart`、`KeyMapping` 不该叫 `key_map.dart`、
`LevelRenderer` 不该叫 `mesher.dart`）。仅语言惯例必须时（如类型名大小写）才做语法调整。

**路径映射口径：相对根对齐**——Java 文件相对 mc-sources 源码根，Dart 文件相对
`lib/`，即从 `net/minecraft/` 起逐级对应：
`net/minecraft/world/entity/player/Player.java` → `lib/world/entity/player/player.dart`；
`net/minecraft/client/player/LocalPlayer.java` → `lib/client/player/local_player.dart`。

### 已踩过的坑（都是没做到"逐行"造成的）

| 坑 | 表现 | 教训 |
|---|---|---|
| 顺序错 | 跳跃高度 0.9969 vs 1.2522 格，够不到 1 格方块 | 照抄 `LivingEntity.travelInAir` 的**表达式顺序**（先位移后扣重力），不得"等价改写" |
| 量纲错 | 飞行快21倍 | 判据给的是**属性值**（`getSpeed()` = 0.1），不得拿我们自己的换算常量代入 |
| 擅自"合理化" | 飞行松手后速度锁死成失重悬浮 | 原版 `setDeltaMovement(y = originalMovementY × 0.6)` 就是 `× 0.6`，**不得**解读成 `max(injected, afterGravity)` —— 原版看着奇怪的地方也是判据 |

**判据值必须能指到源码行号**（如 `Player.java:209`）。指不到 ⇒ 说明是猜的，先去查。
测试断言原版离线递推出的黄金值，**不断言"我的实现输出"**；测试失败时先怀疑实现、
改实现去对齐判据，**绝不**为了让测试变绿而改期望值。

**审查门禁**：进入实现阶段的 change，其 `design.md` SHALL 列出本次用到的判据
`文件:行号`；缺失者不得开始实现。

## 红线

- **包纯度**：`packages/` 全纯 Dart，不 import flutter / flutter_scene；`mc_ui` 是唯一
  Flutter 例外（也禁 flutter_scene）；flutter_scene 只允许 app 壳 `lib/` 使用；包与应用之间只传纯数据。
- **版本包模式**：版本特定代码只存在于 `mc_protocol_v<主>_<次>` 形态的包中；业务代码禁止按
  版本号 if/switch 分支；新协议版本 = 新增版本包 + 装配点注册。
- **mc-sources/ 只读**：不修改、不提交、代码不得 import 或在运行期读取（它是翻译判据，不是依赖）。
- **官方资产不入库**：client jar 与提取产物（`build/extracted_assets/` 等）一律 gitignore；
  任何包（含 mc_ui）不捆绑 Mojang 资产，外观资源经资源抽象注入。
- **网络方向**：仅连用户指定的 MC 服务器；无遥测、无账号体系外联。
- **测试纪律**：禁止为让测试通过而修改期望值；禁止 `--force`、跳 hook、amend 已推送提交。
- **协作规则**：包脚手架方式、提交信息规范等执行侧细则的真身在
  `.agents/rules/project_rules.md`，本文件不复述。
- **流程**：`openspec/` 是唯一流程权威（当前做什么、验收标准、变更是否完成）；本文件与 README
  只是指针与摘要，不构成第二套规则正文。新增模块先指名原版对应物（或按上文标注自由设计类别），
  才能落包；无对应物的只能落 app 壳。
