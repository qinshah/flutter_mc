// 逐行翻译 net/minecraft/server/jsonrpc/security/SecurityConfig.java。
//
// 判据：
//   SecurityConfig.java:6  —— SECRET_KEY_CHARS（大小写字母 + 数字，62 字符）
//   SecurityConfig.java:8-10 —— isValid：空串为 false；否则要求 `^[a-zA-Z0-9]{40}$`
//   SecurityConfig.java:12-24 —— generateSecretKey：SecureRandom 逐位从字符表取 40 个字符
//
// 该格式是**版本无关**的安全工具（40 位字母数字密钥），故落在本包而非版本包；
// 其调用点 `DedicatedServerProperties.java:76` 作为 management-server-secret 的默认值。
import 'dart:math';

class SecurityConfig {
  /// SecurityConfig.java:6
  static const String SECRET_KEY_CHARS =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

  /// SecurityConfig.java:8-10
  static final RegExp _secretKeyPattern = RegExp(r'^[a-zA-Z0-9]{40}$');

  static bool isValid(String secretKey) =>
      secretKey.isEmpty ? false : _secretKeyPattern.hasMatch(secretKey);

  /// SecurityConfig.java:12-24（SecureRandom → Dart `Random.secure()`）。
  static String generateSecretKey() {
    final random = Random.secure();
    final key = StringBuffer();
    for (var i = 0; i < 40; i++) {
      key.write(SECRET_KEY_CHARS[random.nextInt(SECRET_KEY_CHARS.length)]);
    }
    return key.toString();
  }
}
