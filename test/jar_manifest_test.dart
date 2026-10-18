// `jar_manifest.dart` 的单测：MANIFEST 解析语义（java.util.jar.Manifest）+ 最小 ZIP 读取。
//
//   黄金值口径：期望值全部写死在测试里（照 AGENTS.md「测试断言黄金值，不断言实现输出」）。
//   ZIP 容器用 archive 包（dev 依赖）构造真文件再走被测代码读回。
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_mc/platform/server_host/jar_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('JarManifest.mainClassOf（java.util.jar.Manifest 语义）', () {
    test('paperclip 实测值：简单主清单', () {
      const text = 'Manifest-Version: 1.0\r\n'
          'Main-Class: io.papermc.paperclip.Main\r\n'
          'Enable-Native-Access: ALL-UNNAMED\r\n'
          '\r\n';
      expect(JarManifest.mainClassOf(text), 'io.papermc.paperclip.Main');
    });

    test('续行折叠：超长 Main-Class 以单个空格续行（72 字节上限的 JDK 口径）', () {
      const text = 'Manifest-Version: 1.0\r\n'
          'Main-Class: com.example.really.long.package.name.That.Exceeds.\r\n'
          ' Seventy.Two.Bytes.Limit.Main\r\n'
          '\r\n';
      expect(
        JarManifest.mainClassOf(text),
        'com.example.really.long.package.name.That.Exceeds.Seventy.Two.Bytes.Limit.Main',
      );
    });

    test('属性名大小写不敏感（Attributes.Name 的 Ascii 小写口径）', () {
      const text = 'Manifest-Version: 1.0\n'
          'main-class: org.example.Lower\n'
          '\n';
      expect(JarManifest.mainClassOf(text), 'org.example.Lower');
    });

    test('主属性节在第一个空行处结束：具名节里的 Main-Class 不是主属性', () {
      const text = 'Manifest-Version: 1.0\n'
          '\n'
          'Name: org/example/\n'
          'Main-Class: org.example.WrongSection\n';
      expect(JarManifest.mainClassOf(text), isNull);
    });

    test('无 Main-Class → null', () {
      const text = 'Manifest-Version: 1.0\n'
          'Implementation-Title: something\n'
          '\n';
      expect(JarManifest.mainClassOf(text), isNull);
    });
  });

  group('JarManifest.readMainClassSync（最小 ZIP 读取）', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('jar_manifest_test');
    });
    tearDown(() {
      tmp.deleteSync(recursive: true);
    });

    /// 用 archive 包（dev 依赖）构造真 zip 文件。
    File writeZip(String name, {required Map<String, List<int>> entries}) {
      final archive = Archive();
      entries.forEach((path, bytes) {
        archive.add(ArchiveFile.bytes(path, bytes));
      });
      final file = File('${tmp.path}/$name');
      file.writeAsBytesSync(ZipEncoder().encode(archive));
      return file;
    }

    test('deflate 压缩条目：读回 MANIFEST 的 Main-Class', () {
      const manifest = 'Manifest-Version: 1.0\r\n'
          'Main-Class: io.papermc.paperclip.Main\r\n'
          '\r\n';
      final jar = writeZip('paper.jar', entries: {
        'META-INF/MANIFEST.MF': manifest.codeUnits,
        'io/papermc/paperclip/Main.class': List<int>.filled(2048, 0xCA),
      });
      expect(
        JarManifest.readMainClassSync(jar),
        'io.papermc.paperclip.Main',
      );
    });

    test('无 MANIFEST 条目 → null（等价 java -jar 的 no main manifest attribute）', () {
      final jar = writeZip('bare.jar', entries: {
        'org/example/Main.class': <int>[0xCA, 0xFE],
      });
      expect(JarManifest.readMainClassSync(jar), isNull);
    });

    test('非 zip 文件 → FormatException（显式报错，不静默）', () {
      final file = File('${tmp.path}/not-a.jar');
      file.writeAsBytesSync(List<int>.filled(64, 0x00));
      expect(
        () => JarManifest.readMainClassSync(file),
        throwsFormatException,
      );
    });

    test('多文件 zip 的条目定位：局部头扩展区不干扰数据起点', () {
      // archive 包会给条目写扩展区（extra field），天然覆盖"局部头名字+扩展区跳过"路径。
      const manifest = 'Manifest-Version: 1.0\r\n'
          'Main-Class: net.minecraft.server.Main\r\n'
          '\r\n';
      final jar = writeZip('vanilla.jar', entries: {
        'a.class': List<int>.generate(1000, (i) => i % 256),
        'META-INF/MANIFEST.MF': manifest.codeUnits,
        'z.class': List<int>.generate(1000, (i) => (i * 7) % 256),
      });
      expect(JarManifest.readMainClassSync(jar), 'net.minecraft.server.Main');
    });
  });
}
