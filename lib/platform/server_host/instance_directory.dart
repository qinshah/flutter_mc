// 实例目录初始化：在应用私有根下按**原版文件名**生成服务端目录与首启配置。
//
//   ⚠ 属第三类自由设计「运行时宿主（JVM 托管）」：原版由 `server/Main.java:110-121`
//   在**进程工作目录**里就地读写 `server.properties` / `eula.txt`（判据 `:110`、
//   `DedicatedServerProperties.java:56/:58/:72`），宿主把"工作目录"换成应用私有目录下的
//   实例目录——**目录与文件名沿用原版**（design.md D6），不另造命名。
//
// 键名与默认值口径照 `DedicatedServerProperties.java`（本仓翻译件 `packages/mc_server`）；
// 相对原版的**故意差异**逐项写在下方 `_initialProperties` 的注释里（design.md D7 + Open Question）。
import 'dart:io';

import 'package:mc_server/mc_server.dart';

import 'local_server_config.dart';

/// 一个实例目录的路径集合（全部落在注入的私有根之下，spec「不触碰用户 MC 目录」）。
class InstanceDirectory {
  /// [sharedDir]（宿主根的 `shared/`）用于**跨实例共享** paperclip 的引导产物
  /// （`libraries/`、`versions/`、`cache/`）——见 [pullSharedCache] / [pushSharedCache]。
  /// 为 null 时不共享（单测/无宿主的场景）。
  InstanceDirectory(this.dir, {this.sharedDir});

  /// 实例根（= 服务端进程工作目录，原版 `Main.java` 里就是 `new File(".")`）。
  final Directory dir;

  /// 宿主根下的共享缓存目录。
  ///
  /// 为什么需要它：paperclip 把引导产物（原版 jar / 依赖库 / 打补丁后的服务端 jar）下在
  /// **进程工作目录**下，而我们是"一个世界一个实例目录" ⇒ 每建一个新世界就要重下一遍
  /// （实测各 79M libraries + 28M versions + 58M cache）。原版单机不会如此（jar/libs 是
  /// 游戏自带的、全局一份）。
  ///
  /// 为什么用**复制**而不是符号链接（用户确认的口径）：符号链接在 Android/Windows 上未必可建
  /// （沙箱/权限），复制是跨平台做法；代价是每个世界仍各占一份磁盘，但不再花流量。
  final Directory? sharedDir;

  /// 参与共享的三项（paperclip 的引导产物）。
  static const List<String> _sharedNames = <String>['libraries', 'versions', 'cache'];

  File get serverProperties => File('${dir.path}/server.properties');
  File get eulaFile => File('${dir.path}/eula.txt');

  /// 该实例是否**已生成过世界**（`world/level.dat` 存在）。
  ///
  /// 用途：世界生成类设置（`level-seed`、`hardcore`）是**创建时固化**的——世界已生成时改了
  /// 也不生效（原版把这些写进 `level.dat`，编辑已有世界只能改名：`EditWorldScreen.java:41/57/71`）。
  /// 故已生成时界面上须置为只读并说明。
  bool get worldExists => File('${dir.path}/world/level.dat').existsSync();

  /// 该实例是否已具备 paperclip 的运行依赖（`libraries/` 或 `versions/` 里已有内容）。
  ///
  /// 用途：**只有真缺依赖时**才提示"首次启动需下载"（paperclip 首启才会下
  /// `cache/mojang_<ver>.jar` + 打补丁 + 拉 `libraries/`，之后复用缓存不再下载）。
  /// 注意 [createLayout] 会先建出**空**的 `libraries/`/`versions/` 目录，所以判据必须是
  /// "目录里有内容"，不能只看目录是否存在。
  bool get hasCachedDependencies =>
      _hasEntries(Directory('${dir.path}/libraries')) ||
      _hasEntries(Directory('${dir.path}/versions'));

  bool _hasEntries(Directory directory) =>
      directory.existsSync() && directory.listSync().isNotEmpty;

  /// 按原版文件名生成目录（design.md D6）。已存在则不动。
  void createLayout() {
    dir.createSync(recursive: true);
    for (final name in const <String>[
      'world', // 原版 level-name 默认 "world"（DedicatedServerProperties.java:71）
      'logs', // 原版服务端日志目录
      'plugins', // Paper 系
      'config', // Paper 系
      'cache', // Paper 系（paperclip 的原版 jar 缓存）
      'libraries', // paperclip 依赖缓存
      '.paper', // Paper 系
    ]) {
      Directory('${dir.path}/$name').createSync(recursive: true);
    }
  }

  /// 共享缓存 → 本实例：共享目录已有内容而本实例还没有时复制进来，
  /// 这样**新世界首启不必再下载**。返回复制的文件数。
  Future<int> pullSharedCache() async {
    final shared = sharedDir;
    if (shared == null) return 0;
    var copied = 0;
    for (final name in _sharedNames) {
      final from = Directory('${shared.path}/$name');
      final to = Directory('${dir.path}/$name');
      if (!_hasEntries(from)) continue;
      if (_hasEntries(to)) continue; // 本实例已有自己那份，不动
      copied += await _copyTree(from, to);
    }
    return copied;
  }

  /// 本实例 → 共享缓存：本实例下完一遍后回写，给全局缓存"播种"，后续世界即可复用。
  /// 只在共享目录还空着时做（不覆盖已有共享内容）。返回复制的文件数。
  Future<int> pushSharedCache() async {
    final shared = sharedDir;
    if (shared == null) return 0;
    var copied = 0;
    for (final name in _sharedNames) {
      final from = Directory('${dir.path}/$name');
      final to = Directory('${shared.path}/$name');
      if (!_hasEntries(from)) continue;
      if (_hasEntries(to)) continue;
      copied += await _copyTree(from, to);
    }
    return copied;
  }

  /// 递归复制文件树（目录按需建；**不照搬符号链接**——跨盘/跨平台可能失效，
  /// 这里按内容复制）。返回复制的文件数。
  static Future<int> _copyTree(Directory from, Directory to) async {
    var copied = 0;
    to.createSync(recursive: true);
    await for (final entity in from.list(recursive: true, followLinks: false)) {
      final relative = entity.path.substring(from.path.length + 1);
      final target = '${to.path}/$relative';
      if (entity is Directory) {
        Directory(target).createSync(recursive: true);
      } else if (entity is File) {
        File(target).parent.createSync(recursive: true);
        await entity.copy(target);
        copied++;
      }
    }
    return copied;
  }

  /// 首启写入 `server.properties`（仅宿主所需键集；其余键由被托管服务端自己补齐，
  /// 原版 `Settings` 的 get 会把每个键写回，判据 `Settings.java:103-108`）。
  ///
  /// 只在文件不存在时写：已存在则**原样保留**（含未知键，spec「未知键不被丢弃」）。
  void writeInitialPropertiesIfAbsent(LocalServerConfig config) {
    if (serverProperties.existsSync()) return;
    final entries = initialProperties(config);
    Properties.storeFile(
      serverProperties.path,
      entries,
      'Minecraft server properties', // 注释头照 Settings.java:63
    );
  }

  /// 同步**宿主管理的键**为实例配置的当前值（端口冲突改端口后必须落到文件，
  /// 否则服务端仍绑旧端口）。未知键与用户改过的其他键原样保留（spec「未知键不被丢弃」）。
  ///
  /// 密钥类（`rcon.password` / `management-server-secret`）**不在此同步**——它们首启生成后
  /// 固定，随文件持久化，避免每次启动换口令导致客户端旧凭据失效。
  void ensureProperties(LocalServerConfig config) {
    if (!serverProperties.existsSync()) {
      writeInitialPropertiesIfAbsent(config);
      return;
    }
    final entries = Settings.loadFromFile(serverProperties.path);
    final desired = initialProperties(config);
    for (final key in const <String>[
      'online-mode',
      'server-ip',
      'server-port',
      'gamemode',
      'difficulty',
      'hardcore',
      'level-seed',
      'force-gamemode',
      'enable-rcon',
      'rcon.port',
      'management-server-enabled',
      'management-server-host',
      'management-server-port',
      'management-server-tls-enabled',
      'management-server-allowed-origins',
    ]) {
      entries[key] = desired[key]!;
    }
    // 密钥缺失或为空时补齐（例如旧文件、用户误删，或原版风格文件里 `rcon.password=` 为空——
    // 原版空口令会**拒绝启动 RCON**，判据 RconThread.java:64-66），保证控制面可鉴权。
    if ((entries['rcon.password'] ?? '').isEmpty) {
      entries['rcon.password'] = desired['rcon.password']!;
    }
    if ((entries['management-server-secret'] ?? '').isEmpty) {
      entries['management-server-secret'] = desired['management-server-secret']!;
    }
    Properties.storeFile(
      serverProperties.path,
      entries,
      'Minecraft server properties',
    );
  }

  /// 生成首启配置。**顺序**取插入顺序（`Properties` 的确定性写回口径，见其文件头说明 1）；
  /// JDK 的 `Properties.store` 顺序本身未定义，故此处不追求与原版文件逐字节同序。
  static Map<String, String> initialProperties(LocalServerConfig config) {
    return <String, String>{
      // —— 相对原版默认值的**故意差异**（design.md D7）——
      // 差异 1：online-mode 原版默认 true（DedicatedServerProperties.java:56）；本仓客户端为
      // 离线登录口径，若保持 true 则本机连不上自己，故写 false。
      'online-mode': 'false',
      // 差异 2：server-ip 原版默认 ""（:58）。**保持一致**：空即绑全部接口，顺带满足局域网。
      'server-ip': '',
      // 差异 3：server-port 原版默认 25565（:72）。默认取原版同值，冲突时按用户配置改
      // （spec「端口冲突可改」）；此处写入实例配置的实际端口。
      'server-port': '${config.port}',

      // —— 世界/玩法项（原版默认值，逐项给判据；创建世界界面即这些键的 CycleButton）——
      // gamemode：原版默认 GameType.SURVIVAL（:68-70），序列化名照 GameType.java:17-20。
      // 单机创建世界界面同样把它做成 CycleButton（CreateWorldScreen.java:651-654）。
      'gamemode': config.gamemode,
      // difficulty：原版默认 Difficulty.EASY（:65-67），序列化名照 Difficulty.java:13-16。
      'difficulty': config.difficulty,
      // hardcore：原版默认 false（:87）。
      'hardcore': '${config.hardcore}',
      // level-seed：原版默认 ""（:135）＝服务端随机。世界已存在时改它不重生成地形。
      'level-seed': config.levelSeed,
      // force-gamemode：原版默认 false（:63），本仓**恒 true**——本地服务器就是单机形态，
      // 玩家的游戏模式以世界设定为准（判据 `DedicatedServer.java:759-761`
      // `forceGameMode() ? worldData.getGameType() : null`，配合
      // `ServerPlayer.java:2017-2024` 的"存档模式优先"）。不暴露给用户改。
      'force-gamemode': 'true',

      // —— 首启写入的控制面开启项（原版两通道默认皆关闭，design.md D3/D7）——
      // RCON：原版默认 enable-rcon=false（:84）。宿主显式开启。
      'enable-rcon': 'true',
      'rcon.port': '${config.rconPort}',
      // 原版默认 rcon.password=""（:86），但 RconThread 要求非空口令，空则**拒绝启动 RCON**
      // （判据 `server/rcon/thread/RconThread.java:64-66` 的 "No rcon password set ... rcon disabled"）。
      // 故首启生成一把随机口令（借用 SecurityConfig.java:6-20 的 40 字符字母数字口径；
      // 原版对 RCON 口令无格式要求，仅要求非空）。
      'rcon.password': SecurityConfig.generateSecretKey(),

      // 管理服务器：原版默认 management-server-enabled=false（:73）。宿主显式开启。
      'management-server-enabled': 'true',
      'management-server-host': 'localhost', // :74 默认值原样
      // 差异 4：原版默认 management-server-port=0（:75，内核分配临时端口）。宿主取定值，
      // 以便客户端可稳定寻址（原版在 `JsonRpc.java:26-27` 只把 host/port 交给 Netty bind）。
      'management-server-port': '${config.managementServerPort}',
      'management-server-secret': SecurityConfig.generateSecretKey(), // :76 的默认生成口径
      // 差异 5：原版默认 management-server-tls-enabled=true（:77），但 keystore 默认空（:78）——
      // 开启会走 `JsonRpc.create` 的 TLS 分支（`:41-45`），keystore 为空即抛
      // IllegalStateException（`JsonRpcSslContextProvider.createFrom` 失败）导致服务端起不来。
      // 本机自托管无证书，故显式关闭 TLS，走 `JsonRpc.java:23` 的 startWithoutTls（明文 ws）。
      // 明文仅绑环回（management-server-host=localhost），密钥鉴权照旧（AuthenticationHandler）。
      'management-server-tls-enabled': 'false',
      'management-server-allowed-origins': '', // :80 默认值原样
    };
  }
}
