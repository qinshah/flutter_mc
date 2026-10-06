# Tasks

## 1. 协议三包（mc_protocol_v26_2）

- [x] 1.1 `protocol_ids.dart`：PlayServerbound 加 playerAbilities=40、playerInput=43（注册序标定注释）；验证：analyze 零 issue
- [x] 1.2 `packets.dart`：PlayerInputFlags（7 位打包/解出）、PlayerAbilitiesIn（clientbound：4 标志位+双 float）、PlayerAbilitiesOut（serverbound：1 字节 flying 位）三编解码；验证：roundtrip 单测全绿
- [x] 1.3 `registry.dart` 登记三条（inb abilities=64 → PlayerAbilitiesIn；outb 43/40）；mc_session 消费路径接上；验证：mc_session `dart test` 全绿

## 2. mc_session 状态与上行

- [x] 2.1 会话持有 abilities（mayfly/flying/flyingSpeed，收到下发即更新）；`sendAbilities({required bool flying})`；`sendInputFlagsIfChanged(7 bools)`（lastSent 比对）；导出；验证：单测（变更才发、abilities 更新）

## 3. app 壳

- [x] 3.1 `Player.applyLook` 换原版公式（灵敏度默认 0.5）；game_screen 加 `Listener(onPointerMove)` 全屏视角；验证：单测（灵敏度 0.5 下 10px=1.5°）
- [x] 3.2 控制器飞行分支：双击窗口（7 步）、mayfly 门控、onFlyingToggled 回调→session.sendAbilities；飞行物理（无重力、空格升/Shift 降=flyingSpeed×20×(疾跑?2:1)、不卡边）；验证：控制器单测（双击时序矩阵、飞行运动学）
- [x] 3.3 game_screen 接线：abilities 每帧同步进控制器、每 tick sendInputFlagsIfChanged；验证：analyze 零 issue、既有测试全绿

## 4. 真机验收

- [x] 4.1 Paper（创造）实测：本机 Paper 26.2（127.0.0.1:25565）+ dart MCP 端到端取证。
  -进服与渲染：`[ABIL] mayfly=true flying=true speed=0.05`、`[TEX] spriteCount=1227`，
    截图见带贴图地形/水面/雾天，区块持续加载（cols 63→530）。
  - **双击切飞行时序**（合成探针走生产物理路径，0.1s 打点）：
    t=0.12 `win=0.342 flying=false`（第一按开窗）→ t=0.21 `win=0.175` 第二按 →
    t=0.31 **`flying=true`**（0.35s 窗口内切换，符合 `jumpTriggerTime=7`）。
  - **竖直终速对齐原版**：t=1.21 起稳定 `vy=4.500` 格/秒（=原版 4.50），位移每 1 秒
    精确 +4.50格（y 112.40→116.90→121.40→…），证明逐刻递推与原版 `LivingEntity.travel`
    竖直分支一致。
  - abilities 上行：`[ABIL]` 回读确认服务器接受flying=true。
  - 运行时异常：`get_runtime_errors` 与日志均0 条。
  - 遗留观察：高空俯瞰时大片深红为 `leaf_litter` 本色（与 commit 2ab988e 判定一致），非缺陷。
  - 键盘双击/鼠标视角的手感项需人工实机确认（本探针只验物理与上行链路）。
- [x] 4.2 全仓回归：`dart analyze`零 issue + app 45 项 + mc_wire 51 / mc_protocol_v26_2 23 / mc_render 11 / mc_resource 35 / mc_session 23 全绿
