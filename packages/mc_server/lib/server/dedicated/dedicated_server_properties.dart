// 逐行翻译 net/minecraft/server/dedicated/DedicatedServerProperties.java 的**宿主所需键集**。
//
// 判据（行号即 `DedicatedServerProperties.java`，路径相对 mc-sources/minecraft-26.2/net/minecraft/）：
//   :53-55 —— 三个 TLS 键常量
//   :56    —— online-mode   = true
//   :58    —— server-ip     = ""
//   :72    —— server-port   = 25565
//   :73    —— management-server-enabled = false
//   :74    —— management-server-host    = "localhost"
//   :75    —— management-server-port    = 0
//   :76    —— management-server-secret  = SecurityConfig.generateSecretKey()
//   :77    —— management-server-tls-enabled = true
//   :78    —— management-server-tls-keystore = ""
//   :79    —— management-server-tls-keystore-password = ""
//   :80    —— management-server-allowed-origins = ""
//   :84    —— enable-rcon   = false
//   :85    —— rcon.port      = 25575
//   :86    —— rcon.password  = ""
//   :104   —— view-distance = 10
//   :133-135 —— 构造：交给 super(Properties) 后逐键读取
//
// 范围说明：本仓**不**翻译原版其余键（difficulty / gamemode / 资源包 / 数据包 / 权限等复杂
// 反序列化器）——那些键的解析由被托管服务端自己完成，宿主只需原样透传。未识别的键按规格
// 「逐键默认值与文本格式照原版」之外的「未知键原样保留」处理，保存在同一份 `Properties` 里。
import 'settings.dart';
import '../jsonrpc/security/security_config.dart';

class DedicatedServerProperties extends Settings {
  // :53-55
  static const String MANAGEMENT_SERVER_TLS_ENABLED_KEY =
      'management-server-tls-enabled';
  static const String MANAGEMENT_SERVER_TLS_KEYSTORE_KEY =
      'management-server-tls-keystore';
  static const String MANAGEMENT_SERVER_TLS_KEYSTORE_PASSWORD_KEY =
      'management-server-tls-keystore-password';

  // :56
  late final bool onlineMode;
  // :58
  late final String serverIp;
  // :72
  late final int serverPort;
  // :73-80（含 :77-79 的 TLS 键）
  late final bool managementServerEnabled;
  late final String managementServerHost;
  late final int managementServerPort;
  late final String managementServerSecret;
  late final bool managementServerTlsEnabled;
  late final String managementServerTlsKeystore;
  late final String managementServerTlsKeystorePassword;
  late final String managementServerAllowedOrigins;
  // :84-86
  late final bool enableRcon;
  late final int rconPort;
  late final String rconPassword;
  // :104
  late final int viewDistance;

  /// 照 :133-135 的构造口径：交给 super 后，按声明顺序逐键读取（并写回）。
  DedicatedServerProperties(super.properties) {
    onlineMode = getBool('online-mode', true);
    serverIp = getString('server-ip', '');
    serverPort = getInt('server-port', 25565);
    managementServerEnabled = getBool('management-server-enabled', false);
    managementServerHost = getString('management-server-host', 'localhost');
    managementServerPort = getInt('management-server-port', 0);
    managementServerSecret = getString(
        'management-server-secret', SecurityConfig.generateSecretKey());
    managementServerTlsEnabled =
        getBool(MANAGEMENT_SERVER_TLS_ENABLED_KEY, true);
    managementServerTlsKeystore =
        getString(MANAGEMENT_SERVER_TLS_KEYSTORE_KEY, '');
    managementServerTlsKeystorePassword =
        getString(MANAGEMENT_SERVER_TLS_KEYSTORE_PASSWORD_KEY, '');
    managementServerAllowedOrigins =
        getString('management-server-allowed-origins', '');
    enableRcon = getBool('enable-rcon', false);
    rconPort = getInt('rcon.port', 25575);
    rconPassword = getString('rcon.password', '');
    viewDistance = getInt('view-distance', 10);
  }
}
