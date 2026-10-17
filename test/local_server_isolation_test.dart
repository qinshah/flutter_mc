// `servers.dat` 隔离测试（tasks 4.3 / spec「列表文件不被污染」）。
//
// 本地服务器的状态与配置 MUST 存于应用私有目录，MUST NOT 混入原版 `servers.dat`。
import 'dart:io';

import 'package:flutter_mc/platform/server_host/local_server_host.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mc_session/mc_session.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('local_server_isolation'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('创建/修改/删除本地服务器条目后 servers.dat 字节不变', () {
    // 一份既有的原版服务器列表（模拟用户已有的远端条目）。
    final gameDir = Directory('${tmp.path}/game');
    final list = ServerList(gameDir)..load();
    list.add(ServerData(name: '远端服务器', ip: 'example.com:25565'));

    final dat = File('${gameDir.path}/servers.dat');
    expect(dat.existsSync(), isTrue);
    final before = dat.readAsBytesSync();

    // 宿主侧：创建 → 改配置 → 再建 → 删除。
    final manager = LocalServerManager(Directory('${tmp.path}/local_server'));
    final first = manager.addConfig(name: '新的世界');
    first.port = 25566;
    first.mcVersion = '26.2';
    manager.saveConfigs();

    final second = manager.addConfig(name: '另一个世界');
    manager.removeConfig(second);

    final after = dat.readAsBytesSync();
    expect(after, equals(before),
        reason: '本地服务器操作 MUST NOT 改动 servers.dat');

    // 本地条目落在应用私有目录（独立于 servers.dat）。
    final hostConfig = File('${tmp.path}/local_server/instances.json');
    expect(hostConfig.existsSync(), isTrue);
    expect(hostConfig.readAsStringSync(), contains('新的世界'));
    expect(hostConfig.readAsStringSync(), isNot(contains('另一个世界')));

    // 远端条目仍可读且未被本地条目影响。
    final reloaded = ServerList(gameDir)..load();
    expect(reloaded.servers.length, 1);
    expect(reloaded.servers.single.name, '远端服务器');
    expect(reloaded.servers.single.ip, 'example.com:25565');
  });
}
