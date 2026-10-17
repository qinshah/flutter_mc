// 本地服务器实例配置（宿主侧自造物）。
//
//   ⚠ 原版**无对应物** —— 本文件属第三类自由设计「运行时宿主（JVM 托管）」（AGENTS.md）：
//   原版服务端自身只认 `server.properties`（判据 `server/dedicated/DedicatedServerProperties.java`，
//   本仓翻译件在 `packages/mc_server`），而"用哪个 jar、哪个 JVM、监听哪个端口、停止等多久"
//   由**启动命令行**表达（原版判据 `server/Main.java:72-73` 的选项解析与 `:205-208` 的
//   `server.setPort(options.valueOf(port))`）。宿主把这份"命令行口径"落成一份配置文件，
//   豁免的只是**承载方式**；被托管物（服务端本体）照旧是翻译债（见 openspec/progress.md 第 14 项）。
//
// 落盘位置与实例目录布局见 `local_server_host.dart`（根下沿用原版文件名，design.md D6）。
import 'dart:convert';
import 'dart:io';

/// 一个被托管服务端实例的宿主配置。
class LocalServerConfig {
  LocalServerConfig({
    required this.id,
    required this.name,
    this.mcVersion = '26.2',
    this.protocol = 776,
    this.javaMajor = 25,
    this.port = 25565,
    this.rconPort = 25575,
    this.managementServerPort = 25585,
    this.gamemode = 'survival',
    this.difficulty = 'easy',
    this.hardcore = false,
    this.levelSeed = '',
    this.jvmArgs = const <String>['-Xms4G', '-Xmx4G'],
    this.stopTimeoutSeconds = 30,
    this.jarPath,
  });

  /// 实例标识（也用作实例目录名）。
  String id;

  /// 展示名（服务器列表条目名）。
  String name;

  /// jar 产物的**命名口径**（宿主约定，非原版概念）：产物目录/资产目录按此版本号组织。
  /// 真正参与"版本锚点校验"的是 [protocol]（见 `local_server_host.dart` 的装配点校验）。
  String mcVersion;

  /// 被托管服务端的协议号。SHALL 与客户端会话锚点一致（spec「版本锚点与客户端同版」）。
  int protocol;

  /// 所需 Java 主版本（Paper 26.2 实测需 Java 25，经验证据 `/Users/qshh/Desktop/paperMC/logs/latest.log:1`）。
  int javaMajor;

  /// 服务端监听端口（原版默认 25565，`DedicatedServerProperties.java:72`）。
  int port;

  /// RCON 端口（原版默认 25575，`DedicatedServerProperties.java:85`）。
  int rconPort;

  /// 管理服务器端口（原版默认 0=内核分配；本宿主取定值以便客户端可寻址，故不照抄 0）。
  int managementServerPort;

  /// 默认游戏模式，落 `server.properties` 的 `gamemode`
  /// （判据 `DedicatedServerProperties.java:68-70`，默认 `GameType.SURVIVAL`；
  /// 取值序列化名照 `GameType.java:17-20` 的 `getName()`：
  /// survival / creative / adventure / spectator）。
  String gamemode;

  /// 默认难度，落 `server.properties` 的 `difficulty`
  /// （判据 `DedicatedServerProperties.java:65-67`，默认 `Difficulty.EASY`；
  /// 取值序列化名照 `Difficulty.java:13-16` 的 `getSerializedName()`：
  /// peaceful / easy / normal / hard）。
  String difficulty;

  /// 极限模式，落 `server.properties` 的 `hardcore`
  /// （判据 `DedicatedServerProperties.java:87`，默认 false）。
  bool hardcore;

  /// 世界种子，落 `server.properties` 的 `level-seed`
  /// （判据 `DedicatedServerProperties.java:135`，默认 `""`）。
  ///
  /// 空串 = 服务端自行随机（原版创建世界界面的种子输入框同样是"留空即随机"：
  /// `CreateWorldScreen.java:766-775` 的 `seedEdit`，空值时显示
  /// `selectWorld.seedInfo` 提示；`WorldCreationUiState.java:37`/`:161-168` 存该串）。
  /// 注意：**只在世界首次生成时生效**——世界已存在时改它不会重新生成地形（原版同此）。
  String levelSeed;

  /// JVM 参数（原版判据即启动命令行，经验证据 `/Users/qshh/Desktop/paperMC/command.md`）。
  List<String> jvmArgs;

  /// 停止时"下发 stop 后等待退出的上限"，超过才强杀（design.md D10）。
  int stopTimeoutSeconds;

  /// 可选：直接指向 jar 文件（用户放置/对照实测用）。为空则按 [mcVersion] 在产物目录解析。
  String? jarPath;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'mcVersion': mcVersion,
        'protocol': protocol,
        'javaMajor': javaMajor,
        'port': port,
        'rconPort': rconPort,
        'managementServerPort': managementServerPort,
        'gamemode': gamemode,
        'difficulty': difficulty,
        'hardcore': hardcore,
        'levelSeed': levelSeed,
        'jvmArgs': jvmArgs,
        'stopTimeoutSeconds': stopTimeoutSeconds,
        if (jarPath != null) 'jarPath': jarPath,
      };

  factory LocalServerConfig.fromJson(Map<String, Object?> json) => LocalServerConfig(
        id: json['id'] as String,
        name: json['name'] as String,
        mcVersion: json['mcVersion'] as String? ?? '26.2',
        protocol: json['protocol'] as int? ?? 776,
        javaMajor: json['javaMajor'] as int? ?? 25,
        port: json['port'] as int? ?? 25565,
        rconPort: json['rconPort'] as int? ?? 25575,
        managementServerPort: json['managementServerPort'] as int? ?? 25585,
        gamemode: json['gamemode'] as String? ?? 'survival',
        difficulty: json['difficulty'] as String? ?? 'easy',
        hardcore: json['hardcore'] as bool? ?? false,
        levelSeed: json['levelSeed'] as String? ?? '',
        jvmArgs: (json['jvmArgs'] as List<Object?>?)
                ?.map((e) => e.toString())
                .toList(growable: false) ??
            const <String>['-Xms4G', '-Xmx4G'],
        stopTimeoutSeconds: json['stopTimeoutSeconds'] as int? ?? 30,
        jarPath: json['jarPath'] as String?,
      );
}

/// 实例配置的持久化（JSON，落于应用私有根，**不写** `servers.dat`，见 spec「列表文件不被污染」）。
class LocalServerConfigStore {
  LocalServerConfigStore(this.file);

  final File file;

  List<LocalServerConfig> load() {
    if (!file.existsSync()) return <LocalServerConfig>[];
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! List) return <LocalServerConfig>[];
      return decoded
          .whereType<Map<Object?, Object?>>()
          .map((e) => LocalServerConfig.fromJson(e.cast<String, Object?>()))
          .toList();
    } catch (_) {
      // 读失败按"空表继续"（与 ServerList 的口径一致：不破坏文件、等下次 save 覆盖）。
      return <LocalServerConfig>[];
    }
  }

  void save(List<LocalServerConfig> configs) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ')
          .convert(configs.map((c) => c.toJson()).toList()),
    );
  }
}
