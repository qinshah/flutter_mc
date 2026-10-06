# Design

## Decisions

- **D1 产物形态照 fscraft**：单张预拼接图集 + JSON 清单（他们实证对 flutter_scene 友好），网格化只查清单取 UV，不在运行时逐贴图建材质。
- **D2 拼接用纯 Dart**：`package:image` 在提取工具内完成（替代 fscraft 的 python venv 方案，少一套工具链）。图集尺寸取能容纳全部 16×16 贴图的 2 的幂。
- **D3 目录=版本标记**：`assets/vanilla/26_2/`（下划线形式），未来版本并列；读取接口 `VanillaPack(version)` 与之对应。pubspec 声明目录资产，目录内 `.gitkeep` 保底，缺提取产物时构建不炸（运行时资产缺失走降级）。
- **D4 blockstate 解析范围**：首版只支持 `variants`（覆盖绝大多数方块）；`multipart`（栅栏/连线类）降级取首个模型并标注简化，待 join-and-render 之后补。
- **D5 jar 来源**：本机官方启动器目录已确认存在 `~/Library/Application Support/minecraft/versions/26.2/26.2.jar`；工具入参传路径，不写死。

## Risks / Trade-offs

- [pubspec 目录资产在空目录下的构建行为] → .gitkeep 保底 + 实际构建一次验证；异常则改用清单文件声明资产
- [贴图尺寸非 16×16（动画贴图为竖条）] → 清单记录实际宽高，网格化按整块取用；动画（mcmeta）首版取首帧并标注简化
- [multipart 降级导致栅栏门类方块形状/贴图不对] → 记入已知简化，后续补全

## Open Questions

（无——实现细节在任务内闭环）
