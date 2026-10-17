// 判据：Settings.java:103-108/:140-142/:148-150/:168-170，DedicatedServerProperties.java:53-86/:104/:133-135。
import 'dart:io';

import 'package:mc_server/mc_server.dart';
import 'package:test/test.dart';

void main() {
  test('默认值逐键与 DedicatedServerProperties.java 判据行一致', () {
    final properties = <String, String>{};
    final p = DedicatedServerProperties(properties);

    expect(p.onlineMode, isTrue, reason: 'online-mode :56');
    expect(p.serverIp, '', reason: 'server-ip :58');
    expect(p.serverPort, 25565, reason: 'server-port :72');
    expect(p.managementServerEnabled, isFalse, reason: 'management-server-enabled :73');
    expect(p.managementServerHost, 'localhost', reason: 'management-server-host :74');
    expect(p.managementServerPort, 0, reason: 'management-server-port :75');
    expect(SecurityConfig.isValid(p.managementServerSecret), isTrue,
        reason: 'management-server-secret :76（generateSecretKey）');
    expect(p.managementServerTlsEnabled, isTrue, reason: 'management-server-tls-enabled :77');
    expect(p.managementServerTlsKeystore, '', reason: 'management-server-tls-keystore :78');
    expect(p.managementServerTlsKeystorePassword, '',
        reason: 'management-server-tls-keystore-password :79');
    expect(p.managementServerAllowedOrigins, '',
        reason: 'management-server-allowed-origins :80');
    expect(p.enableRcon, isFalse, reason: 'enable-rcon :84');
    expect(p.rconPort, 25575, reason: 'rcon.port :85');
    expect(p.rconPassword, '', reason: 'rcon.password :86');
    expect(p.viewDistance, 10, reason: 'view-distance :104');
  });

  test('构造即把解析结果写回（Settings.java:106）', () {
    final properties = <String, String>{};
    DedicatedServerProperties(properties);
    expect(properties['online-mode'], 'true');
    expect(properties['server-port'], '25565');
    expect(properties['management-server-tls-enabled'], 'true');
    expect(properties['enable-rcon'], 'false');
    expect(properties['rcon.port'], '25575');
    expect(properties['view-distance'], '10');
  });

  test('已知键被解析，未知键原样保留并可写回（往返）', () {
    final dir = Directory.systemTemp.createTempSync('mc_server_props');
    final file = '${dir.path}/server.properties';
    try {
      final original = <String, String>{
        'server-port': '12345',
        'enable-rcon': 'true',
        'custom-unknown-key': 'keep-me',
      };
      final p = DedicatedServerProperties(original);
      expect(p.serverPort, 12345);
      expect(p.enableRcon, isTrue);

      p.store(file);
      final written = Properties.loadFile(file);
      expect(written['custom-unknown-key'], 'keep-me');
      expect(written['server-port'], '12345');
      expect(written['enable-rcon'], 'true');

      // 注释头照 Settings.java:61。
      expect(File(file).readAsLinesSync().first, '#Minecraft server properties');
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  group('Settings 类型化读取口径', () {
    test('int 解析失败落默认值（wrapNumberDeserializer）', () {
      final s = _TestSettings({'a': 'not-a-number'});
      expect(s.getInt('a', 42), 42);
      expect(s.properties['a'], '42'); // 写回默认值
    });

    test('int 拒绝 0x 前缀（Java Integer.parseInt 口径）', () {
      final s = _TestSettings({'a': '0x10'});
      expect(s.getInt('a', 7), 7);
    });

    test('bool 仅忽略大小写的 "true" 为真', () {
      expect(_TestSettings({'a': 'TRUE'}).getBool('a', false), isTrue);
      expect(_TestSettings({'a': 'yes'}).getBool('a', false), isFalse);
      // key 不存在时落默认值
      expect(_TestSettings({}).getBool('a', true), isTrue);
    });

    test('string 缺失落默认值', () {
      expect(_TestSettings({}).getString('a', 'd'), 'd');
    });
  });
}

/// 用于直接测试 Settings 的类型化读取（不涉及 DedicatedServerProperties 的键集）。
class _TestSettings extends Settings {
  _TestSettings(super.properties);
}
