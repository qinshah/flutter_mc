// 逐行翻译 net/minecraft/server/Eula.java。
//
// 判据：
//   Eula.java:18-21 —— 构造：`agreed = IS_RUNNING_IN_IDE || readFile()`
//   Eula.java:23-33 —— readFile：读 properties 的 `eula`（缺省 "false"，Boolean.parseBoolean）；
//                      读失败即 saveDefaults() 并返回 false
//   Eula.java:35-37 —— hasAgreedToEULA
//   Eula.java:39-49 —— saveDefaults：写 `eula=false`，注释头为
//                      "By changing the setting below to TRUE you are indicating your agreement to our EULA (<CommonLinks.EULA>)."
//   CommonLinks.java:10 —— EULA = https://aka.ms/MinecraftEULA
//
// `IS_RUNNING_IN_IDE`（SharedConstants.java:27）：原版在 IDE 中跳过 EULA 门槛。本仓**恒为 false**
// ——我们始终要求用户明确同意（规格 `local-server-host` 的「EULA 同意为启动硬门槛」），
// 故此处不引入该旁路。
import 'java_properties.dart';

class Eula {
  /// CommonLinks.java:10
  static const String EULA_URL = 'https://aka.ms/MinecraftEULA';

  /// Eula.java:44 的注释头文本（逐字照抄，含末尾句点）。
  static const String COMMENT =
      'By changing the setting below to TRUE you are indicating your agreement to our EULA ($EULA_URL).';

  final String file;
  final bool agreed;

  Eula(this.file) : agreed = _readFile(file);

  /// Eula.java:23-33
  static bool _readFile(String file) {
    bool agreed;
    try {
      final properties = Properties.loadFile(file);
      agreed = _parseBoolean(properties['eula'] ?? 'false'); // java.lang.Boolean.parseBoolean
    } catch (_) {
      // 读失败：写回默认（eula=false）并视为未同意。
      saveDefaults(file);
      return false;
    }
    return agreed;
  }

  /// Eula.java:35-37
  bool hasAgreedToEULA() => agreed;

  /// Eula.java:39-49：写默认值（`eula=false` + 注释头）。
  static void saveDefaults(String file) => _store(file, false);

  /// 宿主侧写"同意"——原版要求用户手动把文件里的 false 改成 true（Eula.java:44 的注释正文），
  /// 本方法只是把该动作换成 UI 写入，**格式与注释头仍旧照原版**（同一 Properties.store）。
  static void setAgreed(String file, bool value) => _store(file, value);

  static void _store(String file, bool agreed) {
    Properties.storeFile(
      file,
      <String, String>{'eula': agreed.toString()},
      COMMENT,
    );
  }

  /// 对应 `java.lang.Boolean.parseBoolean`：仅忽略大小写的 "true" 为真。
  static bool _parseBoolean(String s) => s.toLowerCase() == 'true';
}
