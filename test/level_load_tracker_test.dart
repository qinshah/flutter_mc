import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mc/client/multiplayer/level_load_tracker.dart';

/// 黄金值全部对照原版判据（`LevelLoadTracker.java`）手算：
/// - 超时 30s（:21 CLIENT_WAIT_TIMEOUT_MS）
/// - 就绪条件（:119-133）：玩家段就绪 / y 超界豁免 / 旁观豁免 / 超时兜底
/// - `isLevelReady` = readyAt + closeDelayMs（:46-48）
void main() {
  // 固定时钟：t 毫秒
  (LevelLoadTracker, List<int>) make() {
    final clock = <int>[0];
    final tracker = LevelLoadTracker(
      minY: -64,
      maxY: 320,
      nowMs: () => clock.first,
    );
    return (tracker, clock);
  }

  test('未 startClientLoad 前永不就绪', () {
    final (tracker, _) = make();
    tracker.loadingPacketsReceived();
    tracker.tick(playerSectionReady: true, playerY: 70, cameraY: 72);
    expect(tracker.isLevelReady, isFalse);
  });

  test('阶段 1（WaitingForServer）：未收到区块流前，段就绪也不放行', () {
    final (tracker, clock) = make();
    tracker.startClientLoad();
    tracker.tick(playerSectionReady: true, playerY: 70, cameraY: 72);
    expect(tracker.isLevelReady, isFalse); // 还在等 LEVEL_CHUNKS_LOAD_START

    clock[0] = 31_000; // 31s > 30s 超时
    tracker.tick(playerSectionReady: true, playerY: 70, cameraY: 72);
    expect(tracker.isLevelReady, isTrue); // 超时兜底（:124-126）
  });

  test('阶段 2（WaitingForPlayerChunk）：段就绪即就绪（:128-132）', () {
    final (tracker, clock) = make();
    tracker.startClientLoad();
    tracker.loadingPacketsReceived();

    tracker.tick(playerSectionReady: false, playerY: 70, cameraY: 72);
    expect(tracker.isLevelReady, isFalse);

    tracker.tick(playerSectionReady: true, playerY: 70, cameraY: 72);
    expect(tracker.isLevelReady, isTrue);
    expect(clock.first, lessThan(30_000)); // 非超时路径
  });

  test('y 超出建筑高度豁免：未就绪段也直接放行（:126-129）', () {
    final (tracker, _) = make();
    tracker.startClientLoad();
    tracker.loadingPacketsReceived();
    // 玩家 y=400 ≥ 320（世界顶）→ isOutsideBuildHeight → 就绪
    tracker.tick(playerSectionReady: false, playerY: 400, cameraY: 402);
    expect(tracker.isLevelReady, isTrue);
  });

  test('30s 超时强制放行（"letting the player into the world anyway"，:124-126）', () {
    final (tracker, clock) = make();
    tracker.startClientLoad();
    tracker.loadingPacketsReceived();
    tracker.tick(playerSectionReady: false, playerY: 70, cameraY: 72);
    expect(tracker.isLevelReady, isFalse);

    clock[0] = 30_001;
    tracker.tick(playerSectionReady: false, playerY: 70, cameraY: 72);
    expect(tracker.isLevelReady, isTrue);
  });

  test('shouldNotifyPlayerLoaded：closeDelay=0 时就绪即可发（ConnectScreen 口径）', () {
    final (tracker, _) = make();
    tracker.startClientLoad();
    tracker.loadingPacketsReceived();
    expect(tracker.shouldNotifyPlayerLoaded(), isFalse);

    tracker.tick(playerSectionReady: true, playerY: 70, cameraY: 72);
    expect(tracker.shouldNotifyPlayerLoaded(), isTrue);
    // closeDelay>0：就绪后未到延迟不放行
    expect(tracker.shouldNotifyPlayerLoaded(closeDelayMs: 500), isFalse);
  });
}
