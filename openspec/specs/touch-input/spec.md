# touch-input Specification

## Purpose
TBD - created by archiving change game-screens-touch-input. Update Purpose after archive.

## Requirements

### Requirement: 按输入类型显隐触控控件

应用 SHALL 记录最近的输入来源（触控指针 vs 键鼠），当且仅当最近来源为触控时 SHALL
显示触控控件 hub；来源切换即切换显隐。触控指针判定口径：`PointerDeviceKind.touch`
与 `PointerDeviceKind.stylus`。判定 SHALL 读取原始指针事件的设备类型，MUST NOT 依赖
平台静态判断（同一桌面平台可外接触屏）。（无 Java 对应物——输入采集自由设计；
参考 fscraft `game_page.dart:393-446` 口径。）

#### Scenario: 触屏点按即出 hub

- **WHEN** 桌面端键鼠操作中，手指点到画面
- **THEN** 触控 hub 立即显示；键鼠再次输入后 hub 隐藏

### Requirement: 触控按钮等价于键位按下

触控按钮的按下/抬起 SHALL 翻译为对应键位语义的按下/抬起，与物理键盘进入**同一条**
键位状态路径（MUST NOT 形成第二套输入状态）：方向键 → 前/后/左/右，跳 → 跳
（含双击窗口切飞行的既有语义），潜行 → 潜行，Esc → Esc（开/关暂停菜单），
E → 物品栏。输入标志上报、飞行切换等下游行为 MUST NOT 区分触控与键盘来源。

#### Scenario: 虚拟摇杆前进上报

- **WHEN** 手指按住 D-pad 前进并持续 1 秒
- **THEN** 输入标志"前"被上报（与按住 W 等价），抬起后不再上报

#### Scenario: 双击跳切飞行

- **WHEN** mayfly=true 时快速双击跳跃按钮
- **THEN** 切换飞行并上报 abilities（与双击空格完全一致）
