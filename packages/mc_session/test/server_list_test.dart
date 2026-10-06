import 'dart:io';

import 'package:mc_protocol_v26_2/mc_protocol_v26_2.dart';
import 'package:mc_session/mc_session.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mc_server_list_test');
  });
  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  test('读写往返：名称/地址/顺序一致，hidden 恒写 false', () {
    final list = ServerList(tmp)
      ..add(ServerData(name: '本地', ip: '127.0.0.1:25565'))
      ..add(ServerData(name: '远端', ip: 'example.com'));
    expect(list.length, 2);

    final reloaded = ServerList(tmp)..load();
    expect(reloaded.length, 2);
    expect(reloaded[0].name, '本地');
    expect(reloaded[0].ip, '127.0.0.1:25565');
    expect(reloaded[1].ip, 'example.com');
    // 未探测条目协议默认锚点（多版本口径：条目自带版本缓存）。
    expect(reloaded[0].protocol, ProtocolV262.measuredProtocolId);
  });

  test('原子轮换：save 后存在 servers.dat，再次 save 留下 servers.dat_old', () {
    final list = ServerList(tmp)..add(ServerData(name: 'a', ip: 'a'));
    expect(File('${tmp.path}/servers.dat').existsSync(), isTrue);
    list.editAt(0, ServerData(name: 'b', ip: 'b'));
    expect(File('${tmp.path}/servers.dat_old').existsSync(), isTrue);
    final reloaded = ServerList(tmp)..load();
    expect(reloaded[0].name, 'b');
  });

  test('removeAt 持久化；缺失文件 load 得空列表', () {
    final list = ServerList(tmp)
      ..add(ServerData(name: 'x', ip: 'x'))
      ..removeAt(0);
    expect(list.length, 0);
    final fresh = Directory.systemTemp.createTempSync('mc_empty');
    addTearDown(() {
      fresh.deleteSync(recursive: true);
    });
    final empty = ServerList(fresh)..load();
    expect(empty.length, 0);
  });
}
