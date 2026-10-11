
/// `client/multiplayer/LevelLoadTracker.java` 的 Dart 对应物（逐行翻译）。
///
/// 登录期就绪状态机：就绪前客户端不跑玩家物理、不上行位置（原版 loading
/// screen 期间玩家不 tick 的对位），就绪后发 `ServerboundPlayerLoadedPacket`
/// 放行服务端。**这是原版机制**（2026-10-11 修复 teleport 拒绝循环的根：
/// 旧实现登录即发 PlayerLoaded + 立即跑物理 ⇒ 出生列未到就飞 ⇒ 嵌入
/// 服务器侧实地 ⇒ collision-reject 弹跳；区别于已拆除的"永续脚下列门禁"
/// ——本状态机是一次性的、有 30s 超时、有就绪条件）。
///
/// 判据（`LevelLoadTracker.java`）：
/// - `CLIENT_WAIT_TIMEOUT_MS = 30s`（:21）——超时强制就绪（"letting the player
///   into the world anyway"，:124-126）
/// - 状态机 `WaitingForServer --loadingPacketsReceived()--> WaitingForPlayerChunk
///   --isReady()--> ClientLevelReady`（:87-90, :99-104, :117-135）
/// - `isReady()`（:119-133）：玩家/相机 y 超出建筑高度、旁观、死亡 ⇒ 直接就绪；
///   否则等 `playerSectionReady`（玩家所在段编译完成——本侧对应"玩家列的段
///   已网格化"）
/// - `isLevelReady()`（:46-48）= ClientLevelReady 且过 `closeDelayMs`
///   （ConnectScreen 传 0——我们走 JoinFlow 对应 ConnectScreen ⇒ 0）
class LevelLoadTracker {
  /// `CLIENT_WAIT_TIMEOUT_MS`（:21）。
  static const Duration clientWaitTimeout = Duration(seconds: 30);

  final int _minY;
  final int _maxY;

  /// 注入时钟（测试用；默认墙钟毫秒，对应 `Util.getMillis()`）。
  final int Function() _nowMs;

  int? _startMs;
  bool _loadingPacketsReceived = false;
  bool _ready = false;
  int? _readyAtMs;

  LevelLoadTracker({
    required int minY,
    required int maxY,
    int Function()? nowMs,
  })  : _minY = minY, // ignore: prefer_initializing_formals
        _maxY = maxY, // ignore: prefer_initializing_formals
        _nowMs = nowMs ?? _defaultNowMs;

  static int _defaultNowMs() => DateTime.now().millisecondsSinceEpoch;

  /// `startClientLoad(player, level)`（:40-43）。
  void startClientLoad() {
    _startMs = _nowMs();
  }

  /// `loadingPacketsReceived()`（:51-55）：收到出生区块流的第一包
  /// （`GameEvent(LEVEL_CHUNKS_LOAD_START)`，判据
  /// `ClientPacketListener.java:1551-1553`）后进入等待玩家列阶段。
  void loadingPacketsReceived() {
    if (_startMs == null) return;
    _loadingPacketsReceived = true;
  }

  /// `isLevelReady()`（:46-48）。
  bool get isLevelReady => _ready;

  /// 每 tick 推进（对应 `tickClientLoad()` + `WaitingForPlayerChunk.tick()`）。
  ///
  /// [playerSectionReady]：玩家所在列的段已网格化（原版 `playerSectionReady`
  /// 编译回调的同义物）；[playerY]/[cameraY]：玩家/相机世界 y（原版逐项判
  /// `isOutsideBuildHeight`，:126-127）；[spectator]/[alive]：旁观/存活豁免。
  void tick({
    required bool playerSectionReady,
    required int playerY,
    required int cameraY,
    bool spectator = false,
    bool alive = true,
  }) {
    if (_ready || _startMs == null) return;
    final now = _nowMs();
    final timeout = _startMs! + clientWaitTimeout.inMilliseconds;

    if (!_loadingPacketsReceived) {
      // WaitingForServer：30s 超时同样强制就绪（原版 WaitingForServer 持有
      // 同一个 timeoutAfter 字段，:42；超时路径经 WaitingForPlayerChunk 的
      // isReady 兜底——此处合并判定）。
      if (now > timeout) _markReady(now);
      return;
    }

    // WaitingForPlayerChunk.isReady()（:119-133）。
    if (now > timeout) {
      _markReady(now); // "letting the player into the world anyway"
      return;
    }
    final outside = _isOutsideBuildHeight(playerY) || _isOutsideBuildHeight(cameraY);
    if (outside || spectator || !alive) {
      _markReady(now); // :127-129 的豁免分支
      return;
    }
    if (playerSectionReady) _markReady(now);
  }

  void _markReady(int nowMs) {
    _ready = true;
    _readyAtMs = nowMs;
  }

  /// 就绪后过 [closeDelayMs] 才算"可以放行"（`isLevelReady()` 的
  /// `readyAt + closeDelayMs`，:46-48）。我们走 ConnectScreen 对应物 ⇒ 0。
  bool shouldNotifyPlayerLoaded({int closeDelayMs = 0}) {
    if (!_ready) return false;
    return _nowMs() >= _readyAtMs! + closeDelayMs;
  }

  /// `Level.isOutsideBuildHeight(y)`。
  bool _isOutsideBuildHeight(int y) => y < _minY || y >= _maxY;
}

