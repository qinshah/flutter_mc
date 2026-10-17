# flutter_mc 执行规则

## 最高纪律：Java → Dart **逐行翻译**

行为判据只有一份：`mc-sources/minecraft-26.2` 官方源码（只读参考，不入库）。
**翻译目标是 Java 代码转成 Dart 代码那个级别的忠实**——不是"功能等价"、不是"效果类似"，
而是原版每一步计算，我们就是对应的一步计算；原版的常量、表达式、调用顺序、分支条件，
逐项对应。

**自由设计只有三类**（环境确实无 Java 可抄，且仅此三类）：

1. **3D 渲染后端**：用 flutter_scene 替代 Java 渲染层。语义（深度测试、面剔除、混合、
   光照）仍要照原版。
2. **输入事件采集**：取自 Flutter 组件（含触屏、手柄）而非 GLFW 回调。语义（视角换算
   公式、键位映射）仍要照原版。
3. **运行时宿主（JVM 托管）**：指"如何在平台上承载外部 JVM 与被托管的 Java 产物"这类
   **环境机制**（桌面复用系统 JVM、Android 无系统 Java 运行时的承载方式、进程与日志管道
   的接法）。语义（启动参数语义、服务端配置口径、就绪判定、控制通道的协议与鉴权）仍要
   照原版。本类**仅**豁免"承载方式"——被托管物自身的差异一律是翻译债，见
   `openspec/progress.md`。

**数据上行不是自由设计** —— 原版有完整流程（`ClientCommonPacketListenerImpl` 的
keepAlive/cookie/resource-pack/`sendDeferredPackets`、`ClientPacketListener.notifyPlayerLoaded`），
必须逐行翻译其发送条件与时序。

### 数值精度零误差：类型宽度（float/double）本身是判据

Java 的 `float` 字段**不是**"一个近似的小数"，它是一台正在运行的舍入机器：
`float32(0.6) = 0.6000000238418579`、`float32(1.8) = 1.7999999523162842`、
`float32(0.6)/2 = 0.30000001192092896`。这些值与十进制字面量的差可达 1e-8 量级，
而 Minecraft 的判定体系（`AABB.intersects` 严格不等式、VoxelShape 1e-7 epsilon、
服务器 knownMovement 门禁）就运行在这个量级上——**1 ulp 之差即可改变行为**
（实证：建盒半宽 double 0.3 vs float 0.30000001192092896，差 1.19e-8，
被服务器判 `CLIPPED_INTO_BLOCK` 回拉抽搐，判据 EntityDimensions.java:19-22）。

因此数据精度按**零误差**口径执行：

- 原版声明为 `float` 的字段/表达式（尺寸、眼高、速度、偏移……）参与运算时，
  MUST 保持 float32 舍入语义，MUST NOT 按 double"数学等价值"代入；
  Dart 用 `Float32List` 写入读出精确模拟（`(double)(float)v`），见
  `lib/game/collision.dart` 的 `_asF32`。
- 原版是 double 的地方 MUST NOT 混入 float32 存储（`Vec3` 是 double，实体位置
  不用 `vector_math` 的 `Vector3`——float32 存储在 |x|>64 后 ulp ≥ 4e-6，贴面
  静止即微穿透，判据 Vec3.java:41-43）。
- 单测黄金值与实机递推值 MUST 位级一致（`==` 或 `expect(..., same 值)`），
  `closeTo` 容差只允许用于确实跨浮点不可复现边界的地方，并在注释里写明理由。

### 写代码前必须问自己

> 这段代码的原版 Java 对应物在哪里？它真的不需要翻译吗？

- **答不上来 ⇒ 停下来去 mc-sources 找**，找到后照抄对应 Java 的逻辑与常量（可改语法、
  改语言特性，但不得改数值、改顺序、改语义）。
- **确实没有对应物** ⇒ 必须**在代码注释或提交信息里写明**属于上述三类之一（或指明
  Flutter / flutter_scene 的具体 API 差异）。
- **原版有 Java 但我们简化了 / 改成外部托管了** ⇒ 那是**翻译债**，登记进
  `openspec/progress.md`，**MUST NOT** 叫它"自由设计"（"运行时宿主"只豁免承载方式，
  不豁免被托管物）。
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
| float 语义丢失 | 怼墙直走被服务器判 `CLIPPED_INTO_BLOCK` 回拉原地抽搐（vanilla 同服务器不抽搐） | 原版 **`float` 字段的舍入差是判据的一部分**：`EntityDimensions.width` 是 float，半宽 = float32(0.6)/2 = `0.30000001192092896` 而非 double 的 0.3（EntityDimensions.java:19-22），差 1.19e-8 恰好卡在服务器 `AABB.intersects` 严格不等式的判定边上。Dart 无 float 类型不是借口——用 `Float32List` 写入读出精确模拟（见 `lib/game/collision.dart` 的 `Aabb`）。凡原版声明为 `float` 的尺寸/速度/偏移参与运算，先问：这里要不要保持 float32 舍入？ |

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
