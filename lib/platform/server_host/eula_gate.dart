// EULA 同意门槛（宿主侧的判定与写盘）。
//
//   ⚠ 属第三类自由设计「运行时宿主（JVM 托管）」：原版在**控制台**要求同意后才运行
//   （判据 `server/Main.java:113-121` + `server/Eula.java:35/:44`），本仓把"控制台提问"
//   换成"UI 对话框"，判定与写盘语义照旧（design.md D9）：
//     - 未同意：MUST NOT 写 `eula=true`、MUST NOT 启动；
//     - 同意状态持久化于实例 `eula.txt`，撤回即写回 `eula=false`，再次启动重新要求同意。
//
// 判定/写盘逻辑全部复用 `packages/mc_server` 的逐行翻译件 `Eula`（Eula.java:23-49），
// 本文件只做"宿主语义"的薄包装。
import 'package:mc_server/mc_server.dart';

import 'instance_directory.dart';

class EulaGate {
  /// 构造即保证实例目录存在：原版 `Eula` 读不到文件会 `saveDefaults()` 写回 `eula=false`
  /// （`Eula.java:36-38`），而 `Properties.storeFile` 逐行照抄 JDK `Properties.store`，
  /// **不建父目录**——目录缺失时无论"读"还是"写"都会抛 `FileSystemException`。
  ///   —— 真机缺陷：首次启动时实例目录尚不存在，`gate.agreed` 直接就抛，起服失败。
  EulaGate(this.instanceDirectory) {
    instanceDirectory.dir.createSync(recursive: true);
  }

  final InstanceDirectory instanceDirectory;

  /// 原版 EULA 链接（判据 `CommonLinks.java:10`，`Eula.java:44` 注释头引用之）。
  static const String url = Eula.EULA_URL;

  /// 当前是否已同意（读实例 `eula.txt`；文件缺失/读失败按原版口径写回 `eula=false`）。
  bool get agreed =>
      Eula(instanceDirectory.eulaFile.path).hasAgreedToEULA();

  /// 用户明确同意后写盘（`eula=true`，注释头照 `Eula.java:44`）。
  void agree() {
    instanceDirectory.dir.createSync(recursive: true);
    Eula.setAgreed(instanceDirectory.eulaFile.path, true);
  }

  /// 撤回同意（`eula=false`）；再次启动须重新同意。
  void revoke() {
    instanceDirectory.dir.createSync(recursive: true);
    Eula.setAgreed(instanceDirectory.eulaFile.path, false);
  }
}
