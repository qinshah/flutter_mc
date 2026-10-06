// 联机验收探针（tasks 7.2 的协议栈部分）：直连真实 Paper 服务器走完整进服流程。
// 用法：dart run bin/join_probe.dart <host> <port> [玩家名]
import 'dart:async';
import 'dart:io';

import 'package:mc_protocol_v26_2/mc_protocol_v26_2.dart';
import 'package:mc_session/mc_session.dart';

Future<void> main(List<String> args) async {
  final host = args.isNotEmpty ? args[0] : '127.0.0.1';
  final port = args.length > 1 ? int.parse(args[1]) : 25565;
  final name = args.length > 2 ? args[2] : 'FscraftProbe';

  final info = await pingServer(host, port);
  stdout.writeln('[probe] ping ok: ${info.versionName} protocol=${info.protocolId} '
      'players=${info.playersOnline}/${info.playersMax} motd=${info.motd}');
  RemoteSession.validateProtocol(info.protocolId, ProtocolV262.measuredProtocolId);

  final handle = await spawnSession(
    host: host,
    port: port,
    playerName: name,
    protocolId: info.protocolId,
  );

  var chunks = 0;
  var blocks = 0;
  var digsSent = 0;
  final digTargets = <String>{};
  // 上报位置（初始值仅触发首次同步；之后跟随服务器回拉）
  var reportX = 8.0, reportY = 80.0, reportZ = 8.0;
  double? px, py, pz;
  final done = Completer<void>();
  final sub = handle.events.listen((event) {
    switch (event) {
      case JoinedGame():
        stdout.writeln('[probe] joined! playerId=${event.login.playerId} '
            'dim=${event.login.dimension} spawnY-ish=seaLevel ${event.login.seaLevel}');
      case ChunkLoaded():
        chunks++;
        if (chunks % 25 == 0) stdout.writeln('[probe] chunks=$chunks');
        if (chunks == 1) {
          // 收到第一个 chunk 后开始上报移动；位置跟随服务器回拉（Paper 对
          // 与服务器认知差太远的移动会拒并回拉，硬报固定坐标会持续打架）。
          // 【走动加载断言】叠加向东疾跑（50ms/tick × 0.35 = 7 m/s）：服务器
          // 应随移动推新列，60s 窗口的 chunks 应远超出生区基线（约 441 列）。
          var ticks = 0;
          Timer.periodic(const Duration(milliseconds: 50), (t) {
            ticks++;
            reportX += 0.35;
            handle.commands.send(CmdUpdatePlayer(
              x: reportX, y: reportY, z: reportZ, yaw: 0, pitch: 0,
              onGround: false, horizontalCollision: false,
            ));
            if (ticks % 100 == 0) {
              stdout.writeln('[probe] walk x=${reportX.toStringAsFixed(1)} '
                  'ticks=$ticks chunks=$chunks');
            }
            if (ticks > 1200) t.cancel();
          });
        }
      case BlockChanged():
        blocks++;
        if (digsSent > 0 &&
            digTargets.contains('${event.pos.x},${event.pos.y},${event.pos.z}')) {
          stdout.writeln('[probe] ✅ 挖掘回显命中: (${event.pos.x}, ${event.pos.y}, '
              '${event.pos.z}) state=${event.stateId}');
        }
      case PositionCorrection():
        stdout.writeln('[probe] 位置回拉: (${event.x}, ${event.y}, ${event.z}) teleport=${event.isTeleport}');
        // 只有 teleport=true 的 PlayerPosition 是服务器权威玩家位置；
        // EntityPositionSync 是实体同步（可能非玩家/插值位置），不能当挖掘锚点
        if (event.isTeleport) {
          px = event.x;
          py = event.y;
          pz = event.z;
          reportX = event.x;
          reportY = event.y;
          reportZ = event.z;
        }
        // 首次拿到服务器权威位置后，向下逐层试挖验证回显（tasks 7.2；
        // creative 即时破坏，空气块服务器静默忽略，实体块必有 BlockChanged）
        // 位置已回拉稳定（连续 20 次回拉后）→ 挖脚下方块（creative 即时破坏；
        // 判据 ServerPlayerGameMode.handleBlockBreakAction：instabuild 走
        // destroyAndAck，必回 BlockChanged 或同位置原状态）
        if (digsSent == 0 && chunks >= 1) {
          digsSent++;
          final bx = px!.floor();
          final by = py!.floor() - 1;
          final bz = pz!.floor();
          stdout.writeln('[probe] 挖脚下方块 -> ($bx, $by, $bz)');
          digTargets.add('$bx,$by,$bz');
          // 立即发送：玩家在持续下落，任何延迟都会让服务器侧位置漂出交互距离
          handle.commands.send(CmdPlayerAction(0, bx, by, bz, 1)); // START
        }
      case ChunkUnloaded():
        break;
      case TimeUpdated():
        break; // 服务器时间同步（约每秒一次），探针不消费
      case SectionChanged():
        break; // 段批量更新（水面/流体 tick），探针不消费
      case AbilitiesUpdated():
        break;
      case SessionClosed():
        stdout.writeln('[probe] closed: ${event.reason} (chunks=$chunks blocks=$blocks)');
        done.complete();
    }
  });

  // 60 秒无终结则主动退出（验收窗口）
  await done.future.timeout(const Duration(seconds: 60), onTimeout: () {
    stdout.writeln('[probe] 60s 验收窗口结束: chunks=$chunks blocks=$blocks');
  });
  await sub.cancel();
  handle.close();
  exit(0);
}
