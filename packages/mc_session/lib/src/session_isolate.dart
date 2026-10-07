import 'dart:async';
import 'dart:isolate';

import 'package:mc_protocol_v26_2/mc_protocol_v26_2.dart';

import 'remote_session.dart';

/// isolate 边界消息协议（design D3：会话整体跑在 worker isolate，
/// 沿用 `chunk_worker_protocol` 的"命令进 / 事件出"模式）。
///
/// 消息全是纯数据（可跨 isolate 传递）；命令由主 isolate 发、事件由会话 isolate 回。
sealed class SessionCommand {
  const SessionCommand();
}

/// 每 tick 的玩家状态上报（本地预测；design D6）。
final class CmdUpdatePlayer extends SessionCommand {
  const CmdUpdatePlayer({
    required this.x,
    required this.y,
    required this.z,
    required this.yaw,
    required this.pitch,
    required this.onGround,
    required this.horizontalCollision,
  });

  final double x;
  final double y;
  final double z;
  final double yaw;
  final double pitch;
  final bool onGround;
  final bool horizontalCollision;
}

/// 挖掘时序（action：0=START 1=ABORT 2=STOP，design D7）。
final class CmdPlayerAction extends SessionCommand {
  const CmdPlayerAction(this.action, this.x, this.y, this.z, this.direction);

  final int action;
  final int x;
  final int y;
  final int z;
  final int direction;
}

/// 放置方块（use-item-on，cursor 为命中面内 0..1 相对坐标）。
final class CmdPlace extends SessionCommand {
  const CmdPlace(this.x, this.y, this.z, this.direction, this.cursor);

  final int x;
  final int y;
  final int z;
  final int direction;
  final double cursor;
}

/// 挥手。
final class CmdSwing extends SessionCommand {
  const CmdSwing(this.hand);

  final int hand;
}

/// 飞行切换上报（本地双击预测 → 服务器采信）。
final class CmdAbilities extends SessionCommand {
  const CmdAbilities({required this.flying});
  final bool flying;
}

/// 输入标志上报（isolate 内由 lastSentInput 去重）。
final class CmdInputFlags extends SessionCommand {
  const CmdInputFlags({
    required this.forward,
    required this.backward,
    required this.left,
    required this.right,
    required this.jump,
    required this.shift,
    required this.sprint,
  });

  final bool forward;
  final bool backward;
  final bool left;
  final bool right;
  final bool jump;
  final bool shift;
  final bool sprint;
}

/// 玩家命令（加速态上行；判据 `LocalPlayer.sendIsSprintingIfNeeded`，
/// `LocalPlayer.java:304-309` → `ServerboundPlayerCommandPacket`
/// START_SPRINTING=1 / STOP_SPRINTING=2）。
final class CmdPlayerCommand extends SessionCommand {
  const CmdPlayerCommand({required this.action});
  final int action;
}

/// 位置上行（判据 `LocalPlayer.sendPosition`，`LocalPlayer.java:265-302` →
/// `ServerboundMovePlayerPacket` 四变体；variant：0=pos、1=posRot、2=rot、
/// 3=statusOnly）。
final class CmdMovePlayer extends SessionCommand {
  const CmdMovePlayer({
    required this.variant,
    required this.x,
    required this.y,
    required this.z,
    required this.yRot,
    required this.xRot,
    required this.onGround,
    required this.horizontalCollision,
  });
  final int variant;
  final double x;
  final double y;
  final double z;
  final double yRot;
  final double xRot;
  final bool onGround;
  final bool horizontalCollision;
}

/// 手持槽位上行（判据 `MultiPlayerGameMode.ensureHasSentCarriedItem`，
/// `MultiPlayerGameMode.java:317-323` → `ServerboundSetCarriedItemPacket`）。
final class CmdCarriedItem extends SessionCommand {
  const CmdCarriedItem({required this.slot});
  final int slot;
}

/// 创造模式设置槽位（判据 `MultiPlayerGameMode.java:491-495` →
/// `ServerboundSetCreativeModeSlotPacket`）。
final class CmdCreativeModeSlot extends SessionCommand {
  const CmdCreativeModeSlot({
    required this.slot,
    required this.itemId,
    required this.count,
  });

  final int slot;
  final int itemId;
  final int count;
}

/// 关闭会话。
final class CmdClose extends SessionCommand {
  const CmdClose();
}

/// 会话 isolate 的持有物：命令入口 + 事件流。
///
/// 正常路径由 [spawnSession] 产出；构造器公开是为了让**宿主或测试**注入自己的
/// 会话（例如脚本化事件流），从而不必起真服务器也能覆盖上层接线。
final class SessionHandle {
  SessionHandle(this.commands, this.events);

  final SendPort commands;
  final Stream<SessionEvent> events;

  void close() {
    commands.send(const CmdClose());
  }

  /// 飞行切换上报。
  void sendAbilities({required bool flying}) =>
      commands.send(CmdAbilities(flying: flying));

  /// 加速态上行（entityId 由会话侧以登录包的 playerId 填，判据
  /// `ServerboundPlayerCommandPacket` 构造传 `entity`=本地玩家）。
  void sendSprinting({required bool sprinting}) =>
      commands.send(CmdPlayerCommand(action: sprinting ? 1 : 2));

  /// 手持槽位上行（会话侧按 carriedIndex 去重，等价原版 ensure 判据）。
  void sendCarriedItem({required int slot}) =>
      commands.send(CmdCarriedItem(slot: slot));

  /// 位置上行（vanilla 每 tick 由 LocalPlayer.sendPosition 判定变体后发送；
  /// 服务器的区块流窗口、反作弊全挂在它更新出的"相信位置"上——缺了它
  /// 区块永远发在旧位置周围，2026-10-07 实机日志证实）。
  void sendMovePlayer({
    required int variant,
    required double x,
    required double y,
    required double z,
    required double yRot,
    required double xRot,
    required bool onGround,
    required bool horizontalCollision,
  }) =>
      commands.send(CmdMovePlayer(
        variant: variant,
        x: x,
        y: y,
        z: z,
        yRot: yRot,
        xRot: xRot,
        onGround: onGround,
        horizontalCollision: horizontalCollision,
      ));

  /// 创造模式设置槽位（创造物品栏点选；会话侧按 hasInfiniteMaterials 门控）。
  void sendCreativeModeSlot({
    required int slot,
    required int itemId,
    required int count,
  }) =>
      commands.send(CmdCreativeModeSlot(slot: slot, itemId: itemId, count: count));

  /// 输入标志上报（isolate 内去重，可每 tick 调用）。
  void sendInputFlags({
    required bool forward,
    required bool backward,
    required bool left,
    required bool right,
    required bool jump,
    required bool shift,
    required bool sprint,
  }) =>
      commands.send(CmdInputFlags(
        forward: forward,
        backward: backward,
        left: left,
        right: right,
        jump: jump,
        shift: shift,
        sprint: sprint,
      ));
}

/// 在独立 isolate 里起一个 [RemoteSession]。
///
/// isolate 内部把所有会话异常折叠为 [SessionClosed] 事件——主 isolate 只面对
/// 事件流，不需要 try/catch 跨边界。
Future<SessionHandle> spawnSession({
  required String host,
  required int port,
  required String playerName,
  required int protocolId,
  int? viewDistance,
}) async {
  final ready = Completer<SendPort>();
  final events = StreamController<SessionEvent>.broadcast();
  final fromIsolate = ReceivePort();

  await Isolate.spawn(
    _entry,
    _IsolateConfig(
      host: host,
      port: port,
      playerName: playerName,
      protocolId: protocolId,
      viewDistance: viewDistance,
      reply: fromIsolate.sendPort,
    ),
    errorsAreFatal: false,
  );

  late StreamSubscription sub;
  sub = fromIsolate.listen((message) {
    if (message is SendPort) {
      ready.complete(message);
    } else if (message is SessionEvent) {
      events.add(message);
      if (message is SessionClosed && !events.isClosed) {
        events.close();
        sub.cancel();
      }
    }
  });

  final commands = await ready.future;
  return SessionHandle(commands, events.stream);
}

class _IsolateConfig {
  _IsolateConfig({
    required this.host,
    required this.port,
    required this.playerName,
    required this.protocolId,
    required this.reply,
    this.viewDistance,
  });

  final String host;
  final int port;
  final String playerName;
  final int protocolId;
  final SendPort reply;

  /// 端侧视距（原版客户端设置项；configuration 阶段经 ClientInformation
  /// 上报，服务器取 min(它, 自己的 view-distance) 决定推送半径）。
  final int? viewDistance;
}

Future<void> _entry(_IsolateConfig config) async {
  final toMain = ReceivePort();
  config.reply.send(toMain.sendPort);

  final session = RemoteSession(
    host: config.host,
    port: config.port,
    playerName: config.playerName,
    protocolId: config.protocolId,
    viewDistance: config.viewDistance,
  );

  toMain.listen((message) {
    switch (message) {
      case final CmdUpdatePlayer c:
        session.updatePlayer(c.x, c.y, c.z, c.yaw, c.pitch,
            onGround: c.onGround, horizontalCollision: c.horizontalCollision);
      case final CmdPlayerAction c:
        session.sendPlayerAction(c.action, McBlockPos(c.x, c.y, c.z), c.direction);
      case final CmdPlace c:
        session.sendPlace(McBlockPos(c.x, c.y, c.z), c.direction, cursor: c.cursor);
      case final CmdSwing c:
        session.sendSwing(hand: c.hand);
      case final CmdAbilities c:
        session.sendAbilities(flying: c.flying);
      case final CmdPlayerCommand c:
        session.sendPlayerCommand(action: c.action);
      case final CmdMovePlayer c:
        session.sendMovePlayer(
          variant: c.variant,
          x: c.x,
          y: c.y,
          z: c.z,
          yRot: c.yRot,
          xRot: c.xRot,
          onGround: c.onGround,
          horizontalCollision: c.horizontalCollision,
        );
      case final CmdCarriedItem c:
        session.sendCarriedItem(slot: c.slot);
      case final CmdCreativeModeSlot c:
        session.sendCreativeModeSlot(
            slot: c.slot, itemId: c.itemId, count: c.count);
      case final CmdInputFlags c:
        session.sendInputFlagsIfChanged(
          forward: c.forward,
          backward: c.backward,
          left: c.left,
          right: c.right,
          jump: c.jump,
          shift: c.shift,
          sprint: c.sprint,
        );
      case CmdClose():
        session.close();
    }
  });

  session.events.listen(
    config.reply.send,
    onError: (Object e) => config.reply.send(SessionClosed('会话异常：$e')),
    onDone: () => config.reply.send(SessionClosed('会话终止')),
  );

  // spawn 即连接（配置随 spawn 传入；连接结果经事件流回传）
  unawaited(session.connect().catchError((Object e) {
    config.reply.send(SessionClosed('连接失败：$e'));
  }));
}
