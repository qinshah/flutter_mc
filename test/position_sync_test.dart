import 'package:flutter_mc/client/player/position_sync.dart';
import 'package:flutter_mc/world/entity/player/player.dart';
import 'package:flutter_test/flutter_test.dart';

/// `LocalPlayer.sendPosition`（`LocalPlayer.java:265-302`）翻译的黄金测试：
/// 断言原版判据（变体选择、2.0E-4 阈值、reminder>=20 保底）。
void main() {
  final calls = <(MoveVariant, double, double, double, double, double, bool, bool)>[];
  PositionSync sync = PositionSync();
  Player player = Player();

  void reset() {
    calls.clear();
    sync = PositionSync();
    player = Player();
    // 立基准（原版字段初值 0 由首帧显式替代）。
    sync.tick(
      player: player,
      yawDeg: 180,
      pitchDeg: 0,
      horizontalCollision: false,
      send: (v, x, y, z, yr, xr, og, hc) => calls.add((v, x, y, z, yr, xr, og, hc)),
    );
  }

  test('静止 1 帧不上报，reminder 满 20 帧发一次 Pos（保底）', () {
    reset();
    for (var i = 0; i < 19; i++) {
      sync.tick(
        player: player,
        yawDeg: 180,
        pitchDeg: 0,
        horizontalCollision: false,
        send: (v, x, y, z, yr, xr, og, hc) =>
            calls.add((v, x, y, z, yr, xr, og, hc)),
      );
    }
    expect(calls, isEmpty, reason: ':274 reminder 未满、无移动 ⇒ 不发');
    sync.tick(
      player: player,
      yawDeg: 180,
      pitchDeg: 0,
      horizontalCollision: false,
      send: (v, x, y, z, yr, xr, og, hc) =>
          calls.add((v, x, y, z, yr, xr, og, hc)),
    );
    expect(calls.single.$1, MoveVariant.pos, reason: ':274 reminder>=20 ⇒ move');
  });

  test('微小位移（≤2.0E-4）不算 move，纯旋转发 Rot', () {
    reset();
    player.setPos(1.0e-4, 0, 0); // 判据 :274 阈值内
    sync.tick(
      player: player,
      yawDeg: 179, // 转 1° ⇒ rot
      pitchDeg: 0,
      horizontalCollision: false,
      send: (v, x, y, z, yr, xr, og, hc) =>
          calls.add((v, x, y, z, yr, xr, og, hc)),
    );
    expect(calls.single.$1, MoveVariant.rot, reason: ':280 move=false, rot=true');
  });

  test('位移+旋转同时变化发 PosRot', () {
    reset();
    player.setPos(1, 0, 0);
    sync.tick(
      player: player,
      yawDeg: 90,
      pitchDeg: 0,
      horizontalCollision: false,
      send: (v, x, y, z, yr, xr, og, hc) =>
          calls.add((v, x, y, z, yr, xr, og, hc)),
    );
    final call = calls.single;
    expect(call.$1, MoveVariant.posRot, reason: ':276 move&&rot');
    // 判据 `:277`：上报的是当前位姿，yRot=90。
    expect(call.$2, 1.0);
    expect(call.$5, 90.0);
  });

  test('仅 onGround 翻转发 StatusOnly', () {
    reset();
    player.onGround = true;
    sync.tick(
      player: player,
      yawDeg: 180,
      pitchDeg: 0,
      horizontalCollision: false,
      send: (v, x, y, z, yr, xr, og, hc) =>
          calls.add((v, x, y, z, yr, xr, og, hc)),
    );
    expect(calls.single.$1, MoveVariant.statusOnly, reason: ':282');
  });

  test('move 后基准重置（:286-291）——同一位移不重复上报', () {
    reset();
    player.setPos(1, 0, 0);
    sync.tick(
      player: player,
      yawDeg: 180,
      pitchDeg: 0,
      horizontalCollision: false,
      send: (v, x, y, z, yr, xr, og, hc) =>
          calls.add((v, x, y, z, yr, xr, og, hc)),
    );
    expect(calls.single.$1, MoveVariant.pos);
    calls.clear();
    sync.tick(
      player: player,
      yawDeg: 180,
      pitchDeg: 0,
      horizontalCollision: false,
      send: (v, x, y, z, yr, xr, og, hc) =>
          calls.add((v, x, y, z, yr, xr, og, hc)),
    );
    expect(calls, isEmpty, reason: '位置没再变 ⇒ 无移动无上报');
  });
}
