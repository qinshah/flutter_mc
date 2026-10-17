// 判据：Eula.java:18-21/:23-33/:35-37/:39-49，CommonLinks.java:10。
import 'dart:io';

import 'package:mc_server/mc_server.dart';
import 'package:test/test.dart';

void main() {
  test('文件不存在：判为未同意并写默认（eula=false + 原版注释头）', () {
    final dir = Directory.systemTemp.createTempSync('mc_server_eula');
    final file = '${dir.path}/eula.txt';
    try {
      final eula = Eula(file);
      expect(eula.hasAgreedToEULA(), isFalse);
      expect(File(file).existsSync(), isTrue);

      final content = File(file).readAsStringSync();
      expect(content, contains('eula=false'));
      expect(content, contains(Eula.EULA_URL));
      expect(content.split('\n').first, '#${Eula.COMMENT}');
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('setAgreed(true) 后重新读取为已同意；撤回后再次为未同意', () {
    final dir = Directory.systemTemp.createTempSync('mc_server_eula');
    final file = '${dir.path}/eula.txt';
    try {
      Eula.setAgreed(file, true);
      expect(Eula(file).hasAgreedToEULA(), isTrue);
      expect(File(file).readAsStringSync(), contains('eula=true'));

      Eula.setAgreed(file, false);
      expect(Eula(file).hasAgreedToEULA(), isFalse);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('已有 eula=true 的文件被判为已同意', () {
    final dir = Directory.systemTemp.createTempSync('mc_server_eula');
    final file = '${dir.path}/eula.txt';
    try {
      File(file).writeAsStringSync('#x\neula=TRUE\n');
      expect(Eula(file).hasAgreedToEULA(), isTrue);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
