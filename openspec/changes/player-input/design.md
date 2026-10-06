# Design

## Decisions

- **D1 包 id**（注册序实证，与既有表同法标定）：serverbound playerAbilities=40、playerInput=43；clientbound playerAbilities=64（表中已有）。
- **D2 字节格式**（判据各类 STREAM_CODEC）：PlayerAbilities（clientbound）= 标志字节（invulnerable1/flying2/canFly4/instabuild8）+ float flyingSpeed + float walkingSpeed；其 serverbound 版= 仅 1 字节（bit2=flying）；PlayerInput = 1 字节 7 位（forward1/backward2/left4/right8/jump16/shift32/sprint64）。
- **D3 双击窗口落点**：PlayerController 固定步内（7 步 = jumpTriggerTime 7 刻），窗口状态（wasJumping/jumpTriggerTime）为控制器字段——纯逻辑可单测。切换时经回调 `onFlyingToggled` 通知 app 壳调 `session.sendAbilities(flying)`。
- **D4 abilities 状态**：会话解析 clientbound 包后写入 `session.abilities`（mayfly/flying/flyingSpeed/instabuild）；控制器经注入的 abilities 引用读取（app 壳每 tick 从会话同步）。物理：飞行时无重力、竖直=空格升/Shift 降（flyingSpeed×20 m/s，疾跑×2）、水平仍直接赋速（沿用步行简化的标注）、不施加"卡边"减速。
- **D5 视角**：game_screen 加 `Listener(onPointerMove)` 包 SceneView（沿用 fscraft 全屏口径；pointer-lock 留后），delta → `Player.applyLook` 改为原版公式（灵敏度常量默认 0.5；设置滑条留设置屏后续切片）。

## Risks / Trade-offs

- [双 float 的 abilities 字节序/端序与现网不符] → 沿用 mc_wire 既有 float 读写（已在 MovePlayer 等包验证过）
- [非创造服双击无反应被误报为 bug] → spec 已写明 mayfly 门控；调试按钮/日志带 abilities 状态
- [全屏 Listener 的指针无法锁定、到屏幕边缘失效] → fscraft 同款已知取舍；pointer-lock 另行切片

## 实测速度（判据 mc-sources/minecraft-26.2 逐刻递推离线核算 + 单测固化）

| 方向 | 公式（格/刻） | 终速 | 第1 秒末实测 |
|---|---|---|---|
| 水平 不疾跑 | `v=(v+0.05)*0.91` | 10.11 格/秒 | 8.4262 |
| 水平 疾跑 | `v=(v+0.10)*0.91` | 20.22 格/秒 | 16.8523（比值≈2） |
| 竖直 升/降 | `v=(v+0.15)*0.6` | 4.50 格/秒 | 4.4997 |

**修掉的偏差**（原实现 vs 原版）：
- 竖直误用 0.91 阻尼与 `×0.05×(疾跑?2:1)` 注入（原版是注入 `×3.0` **不含疾跑倍率**、
  再由 `Player.travel` 收尾 `×0.6`）⇒ 原实现竖直快 **2.25×**（10.11 vs 4.50）。
- 速度源硬编码 0.05，未读服务器下发的 `abilities.flyingSpeed`。
- 撞墙时清零速度（原版 `Entity.move` 只拦位置、不改 deltaMovement）。
- 起飞冲量写 `player.velocity` 会被下一步覆盖，应加在刻速度 `_flyVelocity.y`。

**"感觉飞行太慢"的口径澄清**：原版创造飞行水平终速就是 10.11 格/秒（疾跑 20.22），
本身不算快；真正的缺陷是上表竖直项——原实现竖直虽快但方向错，且水平因撞墙清零
在贴墙时像"撞停"。本切片以对齐原版为准，不额外放大速度。
若要主观加速（如 ×1.5），应在 `PlayerMotion` 加显式倍率并标注为"手感调整"，
不得混入原版公式。
