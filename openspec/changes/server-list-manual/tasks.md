# Tasks

## 1. mc_session 数据面

- [x] 1.1 `ServerData`：name/ip/protocol（默认 26.2）/探测缓存字段 + NBT write/read（name/ip/hidden/icon 兼容、缺失给默认）；验证：roundtrip 单测全绿
- [x] 1.2 `ServerList`：load（gzip NBT，读失败回空列表）/save（临时文件→old→dat 轮换）/add/remove/editAt；路径注入；补 roundtrip+轮换单测；mc_session.dart 导出；验证：`cd packages/mc_session && dart test` 全绿
- [x] 1.3 多版本口径：ServerData.protocol 由 ping 结果回写的字段与测试（pingServer 返回 protocolId 即协议缓存）；验证：单测覆盖

## 2. mc_ui MCEditBox

- [x] 2.1 `MCEditBox`：暗底+边框（失焦灰/聚焦白）、TextEditingController 注入、光标与选区用 Flutter 原生编辑设施、禁用态；导出；补 widget 测试（输入同步 controller、聚焦边框变白、禁用不输入）；验证：`cd packages/mc_ui && flutter test` 全绿

## 3. app 壳界面

- [x] 3.1 多人游戏屏改 StatefulWidget：载入 ServerList（路径注入，默认应用文档目录）、真实列表渲染（两行条目+选中态）、并发 ping 与状态行、刷新重探；按钮可用性按 spec；验证：widget 测试（注入临时目录）：空列表→添加→选中→删除确认→持久化
- [x] 3.2 ManageServerScreen（添加/编辑共用）、DirectJoinServerScreen、删除确认屏 + 三条路由；加入占位提示；验证：widget 测试覆盖添加表单保存与直接连接入口
- [x] 3.3 mc_ui 导出与 routes 更新；验证：根 `flutter analyze` 零 issue

## 4. 集成验收

- [x] 4.1 全链路 widget 测试：列表管理主流程往返；既有测试回归（root 4 + mc_ui + mc_session + mc_resource + 三包）；验证：全绿
- [x] 4.2 红线抽查：mc_session/mc_ui 无新违规 import；servers.dat 只写应用私有目录（代码评审）；验证：analyze 全绿 + grep 无平台路径硬编码
