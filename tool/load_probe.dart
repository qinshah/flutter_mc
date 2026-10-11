// 时序探针：实证登录期各事件时间轴（不动、不挖、不飞），60s 后退出。
// 用法：dart run tool/load_probe.dart [host] [port] [playerName]
import 'dart:async';
import 'dart:io';

import 'package:mc_session/mc_session.dart';

Future<void> main(List<String> args) async {
  final host = args.isNotEmpty ? args[0] : '127.0.0.1';
  final port = args.length > 1 ? int.parse(args[1]) : 25565;
  final name = args.length > 2 ? args[2] : 'LoadProbe';

  final t0 = Stopwatch()..start();
  String ts() => '${(t0.elapsedMilliseconds / 1000).toStringAsFixed(2)}s';

  final info = await pingServer(host, port);
  stdout.writeln('[${ts()}] ping ok proto=${info.protocolId}');

  final handle = await spawnSession(
    host: host,
    port: port,
    playerName: name,
    protocolId: info.protocolId,
  );

  var chunks = 0;
  int? playerCx, playerCz;
  var posSeen = false;
  var abilSeen = false;
  var pcCount = 0;

  final sub = handle.events.listen((event) {
    switch (event) {
      case JoinedGame():
        stdout.writeln('[${ts()}] JoinedGame id=${event.login.playerId}');
      case LevelChunksLoadStart():
        stdout.writeln('[${ts()}] LevelChunksLoadStart');
      case ChunkLoaded():
        chunks++;
        if (chunks == 1) stdout.writeln('[${ts()}] 首个 ChunkLoaded');
        if (chunks % 50 == 0) stdout.writeln('[${ts()}] chunks=$chunks');
      case PositionCorrection():
        pcCount++;
        if (!posSeen) {
          posSeen = true;
          playerCx = event.x.floor() >> 4;
          playerCz = event.z.floor() >> 4;
          stdout.writeln('[${ts()}] 首个 PositionCorrection '
              '(${event.x},${event.y},${event.z}) 玩家列=($playerCx,$playerCz)');
        }
      case AbilitiesUpdated():
        if (!abilSeen) {
          abilSeen = true;
          stdout.writeln('[${ts()}] 首个 AbilitiesUpdated '
              'mayfly=${event.mayfly} flying=${event.flying} '
              'flySpeed=${event.flyingSpeed}');
        }
      case ViewGeometryChanged():
        stdout.writeln('[${ts()}] ViewGeometryChanged radius=${event.radius}');
      case SessionClosed():
        stdout.writeln('[${ts()}] SessionClosed');
      default:
        break;
    }
  });

  await Future<void>.delayed(const Duration(seconds: 45));
  stdout.writeln('[${ts()}] 45s 结束：chunks=$chunks posCorr=$pcCount '
      '玩家列=($playerCx,$playerCz)');
  await sub.cancel();
  handle.close();
  exit(0);
}
