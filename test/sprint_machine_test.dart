import 'package:flutter_mc/game/collision.dart';
import 'package:flutter_mc/world/entity/player/input.dart';
import 'package:flutter_mc/world/entity/player/player.dart';
import 'package:flutter_mc/world/entity/player/abilities.dart';
import 'package:flutter_mc/client/player/local_player.dart';
import 'package:flutter_test/flutter_test.dart';

/// 加速状态机黄金测试（判据 mc-sources/minecraft-26.2
/// `LocalPlayer.aiStep:764-790` + `canStartSprinting:1095` +
/// `shouldStopRunSprinting:883` + `Options.java:623` sprintWindow=7）。
///
/// 断言的是**原版状态机的时序**，不是"我们的实现输出"；测试失败先怀疑实现。
class _EmptyWorld implements CollisionWorld {
  @override
  bool isCollidable(int bx, int by, int bz) => false;
  @override
  bool isColumnLoaded(int cx, int cz) => true;
  @override
  int get worldHeight => 384;
}

void main() {
  late LocalPlayer player;
  late Player p;
  late Abilities abilities;

  // 每次调用推进一个整刻（dt 略大于 1/20 防浮点边界少跑一步；
  // 累加器会保留余量，不影响逐刻语义）。
  void tickWith(Input input) => player.tick(1 / 20 + 1e-6, input);

  setUp(() {
    p = Player();
    abilities = Abilities()..mayfly = false;
    player = LocalPlayer(
      world: _EmptyWorld(),
      player: p,
      abilities: abilities,
    );
  });

  test('Ctrl 按住 ⇒ 立即加速；松开前进 ⇒ 停止（:777-779 + :883）', () {
    final input = Input()..move.y = 1;
    input.sprint = true; // Ctrl 按住
    tickWith(input);
    expect(player.isSprinting, isTrue, reason: 'keyPresses.sprint 按住即起跑');

    // 松开 W（无前进冲动）⇒ shouldStopRunSprinting ⇒ 停。
    final released = Input();
    tickWith(released);
    expect(player.isSprinting, isFalse,
        reason: 'shouldStopRunSprinting: !hasForwardImpulse ⇒ 停');
  });

  test('双击 W：首按置 7 刻窗口，窗口内再按 ⇒ 起跑（:769-775）', () {
    final down = Input()..move.y = 1;
    final up = Input();

    // 第一次按住 2 刻。
    tickWith(down);
    tickWith(down);
    expect(player.isSprinting, isFalse, reason: '未按 Ctrl 且窗口刚置入，单击不起跑');

    // 松开 1 刻（该刻末 prev=false）。
    tickWith(up);

    // 窗口内（<=7 刻）再按 ⇒ 起跑。
    tickWith(down);
    expect(player.isSprinting, isTrue, reason: '双击 W 在 sprintWindow(7) 内 ⇒ 起跑');
  });

  test('超出 sprintWindow（7 刻）再按 ⇒ 不起跑（窗口过期）', () {
    final down = Input()..move.y = 1;
    final up = Input();

    tickWith(down); // 首按：置 7 刻窗口
    // 松开并等 8 刻（窗口过期）。
    for (var i = 0; i < 8; i++) {
      tickWith(up);
    }
    tickWith(down);
    expect(player.isSprinting, isFalse, reason: '窗口已过期 ⇒ 重新等待双击');
  });

  test('潜行/后退取消双击窗口（:764-766）', () {
    final down = Input()..move.y = 1;
    tickWith(down); // 置窗口

    // 潜行中再按 W：窗口被清 ⇒ 不起跑。
    final sneakForward = Input()
      ..move.y = 1
      ..shift = true;
    tickWith(sneakForward);
    expect(player.isSprinting, isFalse, reason: 'shift 清窗口 ⇒ 双击失效');
    tickWith(Input()..move.y = 1);
    expect(player.isSprinting, isFalse, reason: '窗口已被 shift 清除');
  });

  test('加速态变化触发上行回调（sendIsSprintingIfNeeded，:304-309 变更才发）', () {
    var changes = <bool>[];
    p = Player();
    abilities = Abilities()..mayfly = false;
    player = LocalPlayer(
      world: _EmptyWorld(),
      player: p,
      abilities: abilities,
      onSprintingChanged: changes.add,
    );
    final input = Input()
      ..move.y = 1
      ..sprint = true;
    tickWith(input);
    tickWith(input); // 保持加速：不重复回调
    expect(changes, [true], reason: '只在变化时上行（wasSprinting 去重口径）');
  });
}
