# flutter_mc 执行规则

行为判据只有一份：`mc-sources/minecraft-26.2` 官方源码（只读参考，不入库）。翻译目标是
Java→Dart 级忠实：原版怎么从服务器数据算出结果，我们怎么算。唯三处自由设计：
flutter_scene 渲染、Flutter 输入、数据上行。新增模块先指名原版对应物（或标注"后端适配"），
才能落包；无对应物的只能落 app 壳。本文件是红线摘要，规则正文在 `openspec/`（能力
`project-structure` 等），冲突时以 openspec 为准并回改本文件。

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
  只是指针与摘要，不构成第二套规则正文。
