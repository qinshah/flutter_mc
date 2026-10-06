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

- [ ] 4.1 Paper（创造）实测：鼠标转视角、双击空格起飞、空格升/Shift 降、落地双击取消飞行；dart MCP 截屏 + 运行日志见 PlayerInput/Abilities 上行；验证：截图 + 日志
- [x] 4.2 全仓回归：`dart analyze`零 issue + app 45 项 + mc_wire 51 / mc_protocol_v26_2 23 / mc_render 11 / mc_resource 35 / mc_session 23 全绿
