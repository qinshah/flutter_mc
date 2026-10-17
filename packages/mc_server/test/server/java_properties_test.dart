// 判据：Settings.java:34-57（load，含 UTF-8/ISO-8859-1 回退）、:59-65（store），
// 以及 JDK java.util.Properties 的文本格式。
import 'dart:convert';

import 'package:mc_server/mc_server.dart';
import 'package:test/test.dart';

void main() {
  group('Properties.parse（Java properties 文本 → Map）', () {
    test('注释行（# / !）与空行被跳过', () {
      final map = Properties.parse('#comment\n!comment2\n\nkey=value\n');
      expect(map, {'key': 'value'});
    });

    test('`=` 与 `:` 皆为分隔符；值前后空白被修剪', () {
      final map = Properties.parse('a=1\nb : 2\n');
      expect(map, {'a': '1', 'b': '2'});
    });

    test('转义：`\\:` `\\=` `\\ ` 与 `\\uXXXX`', () {
      // 分隔符之后的空白被 JDK 修剪；值前的首空白须转义（`\ `）才保留。
      final map = Properties.parse('key\\:x=has\\=eq\n'
          'sp=\\ leading\n'
          'uni=\\u4e2d\n');
      expect(map, {'key:x': 'has=eq', 'sp': ' leading', 'uni': '中'});
    });

    test('以奇数个反斜杠续行，续行首空白丢弃', () {
      final map = Properties.parse('multi=line1\\\n    line2\n');
      expect(map, {'multi': 'line1line2'});
    });

    test('保持键的出现顺序', () {
      final map = Properties.parse('b=1\na=2\nc=3\n');
      expect(map.keys.toList(), ['b', 'a', 'c']);
    });
  });

  group('Properties.store 往返', () {
    test('特殊字符经转义后能原样读回', () {
      final original = <String, String>{
        'a b': 'v1',
        'colon:key': 'has=equals',
        'back\\slash': 'tab\there',
        'unicode': '中文',
        'lead': ' leading',
      };
      final buffer = StringBuffer();
      Properties.storeInto(buffer, original, 'Minecraft server properties');
      expect(Properties.parse(buffer.toString()), original);
    });

    test('注释头为 "#" + comments，其后为日期行', () {
      final buffer = StringBuffer();
      Properties.storeInto(buffer, {'k': 'v'}, 'Minecraft server properties');
      final lines = buffer.toString().split('\n');
      expect(lines[0], '#Minecraft server properties');
      expect(lines[1].startsWith('#'), isTrue);
    });
  });

  group('Properties.loadFromBytes（Settings.java:36-51）', () {
    test('合法 UTF-8 直接解码', () {
      expect(Properties.loadFromBytes(utf8.encode('k=值\n')), {'k': '值'});
    });

    test('畸形 UTF-8 回退 ISO-8859-1', () {
      // 0xE4 是拉丁 1 的 'ä'，作为单独字节不是合法 UTF-8；回退后应解为 'ä'。
      expect(Properties.loadFromBytes([0x6B, 0x3D, 0xE4, 0x0A]), {'k': 'ä'});
    });
  });
}
