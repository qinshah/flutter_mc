// 逐行翻译 java.util.Properties 的 load/store 文本格式——原版由 `Settings.java:36-43`（load）
// 与 `:59-65`（store）、`Eula.java:25-27`（load）与 `:42-44`（store）调用。
//
// 原版没有自己的 Properties 实现（用的是 JDK 的 java.util.Properties），所以本文件的判据是
// JDK Properties 的**文档化文本格式**，而不是 mc-sources 里的某个类；调用点与调用口径
// （UTF-8 优先、ISO-8859-1 回退；注释头文本；键值转义）逐项照 `Settings.java` / `Eula.java`。
//
// 与 JDK 的两点有意区分（均不改变可读回的语义）：
//   1. 遍历顺序：JDK 的 Properties 基于 Hashtable，`store` 的输出顺序未定义；本实现按插入
//      顺序（文件原始顺序 + 新追加项）输出，使写回确定性、未知键位置稳定。
//   2. `store` 的日期注释行：JDK 写 `#` + `Date.toString()`；本实现按同一形状本地生成，
//      内容仅供人读，不参与解析。
import 'dart:convert';
import 'dart:io';

/// JDK `java.util.Properties` 的文本格式实现（load / store）。
class Properties {
  /// 键 → 值（保持插入顺序，见文件头说明 1）。
  final Map<String, String> entries;

  Properties([Map<String, String>? entries]) : entries = entries ?? <String, String>{};

  /// 对应 `Properties.load(Reader)`：解析 Java properties 文本，保持键的出现顺序。
  static Map<String, String> parse(String text) {
    final result = <String, String>{};
    for (final logical in _logicalLines(text)) {
      final parsed = _parseLine(logical);
      if (parsed == null) continue; // 空行 / 注释行
      result[_loadConvert(parsed.key)] = _loadConvert(parsed.value);
    }
    return result;
  }

  /// 对应 `Properties.load(InputStream)`：JDK 先按 UTF-8 读（畸形即报错），失败回退
  /// ISO-8859-1；口径见 `Settings.java:36-51`。
  static Map<String, String> loadFromBytes(List<int> bytes) {
    String text;
    try {
      text = const Utf8Decoder(allowMalformed: false).convert(bytes);
    } on FormatException {
      text = latin1.decode(bytes);
    }
    return parse(text);
  }

  /// 对应 `Properties.load(InputStream)` 的便捷形式。
  static Map<String, String> loadFile(String path) =>
      loadFromBytes(File(path).readAsBytesSync());

  /// 对应 `Properties.store(Writer, comments)`：写注释头、日期行与全部键值。
  static void storeInto(StringBuffer out, Map<String, String> entries, String comments) {
    for (final line in comments.split('\n')) {
      out.write('#');
      out.write(line);
      out.write('\n');
    }
    out.write('#');
    out.write(_javaDate(DateTime.now()));
    out.write('\n');
    for (final e in entries.entries) {
      // saveConvert(key, escapeSpace=true) + "=" + saveConvert(value, escapeSpace=false)。
      out.write(_saveConvert(e.key, true));
      out.write('=');
      out.write(_saveConvert(e.value, false));
      out.write('\n');
    }
  }

  /// 对应 `Properties.store(Writer, comments)` 的落盘形式（UTF-8，见 `Settings.java:60`）。
  static void storeFile(String path, Map<String, String> entries, String comments) {
    final buffer = StringBuffer();
    storeInto(buffer, entries, comments);
    File(path).writeAsStringSync(buffer.toString(), encoding: utf8);
  }

  // --- JDK Properties 内部语义（逐项照抄 JDK 源码，勿"合理化"）---

  /// 把物理行合成逻辑行：以**奇数个**尾随 `\` 表示续行；续行的行首空白被丢弃。
  static List<String> _logicalLines(String text) {
    final result = <String>[];
    final buffer = StringBuffer();
    var continuing = false;
    for (var raw in const LineSplitter().convert(text)) {
      if (continuing) {
        var i = 0;
        while (i < raw.length && _isWhite(raw.codeUnitAt(i))) {
          i++;
        }
        raw = raw.substring(i);
      }
      if (_endsWithOddBackslashes(raw)) {
        buffer.write(raw.substring(0, raw.length - 1));
        continuing = true;
      } else {
        buffer.write(raw);
        result.add(buffer.toString());
        buffer.clear();
        continuing = false;
      }
    }
    if (buffer.isNotEmpty) result.add(buffer.toString());
    return result;
  }

  static bool _isWhite(int c) => c == 0x20 || c == 0x09 || c == 0x0c;

  static bool _endsWithOddBackslashes(String s) {
    var count = 0;
    for (var i = s.length - 1; i >= 0 && s.codeUnitAt(i) == 0x5c; i--) {
      count++;
    }
    return count % 2 == 1;
  }

  /// 解析单条逻辑行 → (key, value)；空行/注释行返回 null。照 JDK `load0` 的关键边界：
  /// 行首空白跳过；首非空白字符为 `#`/`!` 即注释；key 止于未转义的 `=`/`:`/空白；
  /// 值前导空白跳过，且未遇到分隔符时把 `=`/`:` 消费为分隔符。
  static _KeyValue? _parseLine(String line) {
    final n = line.length;
    var keyStart = 0;
    while (keyStart < n && _isWhite(line.codeUnitAt(keyStart))) {
      keyStart++;
    }
    if (keyStart == n) return null;
    final first = line.codeUnitAt(keyStart);
    if (first == 0x23 || first == 0x21) return null; // '#' / '!'

    var hasSep = false;
    var keyEnd = n;
    var valueStart = n;
    var precedingBackslash = false;
    var i = keyStart;
    for (; i < n; i++) {
      final c = line.codeUnitAt(i);
      if ((c == 0x3d || c == 0x3a) && !precedingBackslash) {
        hasSep = true;
        keyEnd = i;
        valueStart = i + 1;
        break;
      }
      if (_isWhite(c) && !precedingBackslash) {
        keyEnd = i;
        valueStart = i + 1;
        break;
      }
      precedingBackslash = c == 0x5c ? !precedingBackslash : false;
    }
    if (i >= n) {
      keyEnd = n;
      valueStart = n;
    }
    while (valueStart < n) {
      final c = line.codeUnitAt(valueStart);
      if (!_isWhite(c)) {
        if (!hasSep && (c == 0x3d || c == 0x3a)) {
          hasSep = true;
        } else {
          break;
        }
      }
      valueStart++;
    }
    return _KeyValue(line.substring(keyStart, keyEnd), line.substring(valueStart, n));
  }

  /// JDK `loadConvert`：还原 `\uXXXX`、`\t\n\r\f` 与 `\X`。
  static String _loadConvert(String s) {
    final out = StringBuffer();
    var i = 0;
    while (i < s.length) {
      final c = s.codeUnitAt(i++);
      if (c != 0x5c) {
        out.writeCharCode(c);
        continue;
      }
      if (i >= s.length) {
        // 尾随单个反斜杠：JDK 忽略之。
        break;
      }
      final next = s.codeUnitAt(i++);
      if (next == 0x75) {
        if (i + 4 > s.length) {
          out.write('u'); // 十六进制不足 4 位时 JDK 把 'u' 当普通字符写回
          continue;
        }
        out.writeCharCode(int.parse(s.substring(i, i + 4), radix: 16));
        i += 4;
      } else {
        switch (next) {
          case 0x74:
            out.write('\t');
          case 0x6e:
            out.write('\n');
          case 0x72:
            out.write('\r');
          case 0x66:
            out.write('\f');
          default:
            out.writeCharCode(next);
        }
      }
    }
    return out.toString();
  }

  /// JDK `saveConvert`（escUnicode 恒为 true）。
  static String _saveConvert(String s, bool escapeSpace) {
    final out = StringBuffer();
    for (var x = 0; x < s.length; x++) {
      final c = s.codeUnitAt(x);
      if (c == 0x5c) {
        out.write('\\\\');
        continue;
      }
      if (c == 0x20 && (x == 0 || escapeSpace)) out.write('\\');
      if (c == 0x3d || c == 0x3a || c == 0x23 || c == 0x21) out.write('\\');
      if (c == 0x09) {
        out.write('\\t');
        continue;
      }
      if (c == 0x0a) {
        out.write('\\n');
        continue;
      }
      if (c == 0x0d) {
        out.write('\\r');
        continue;
      }
      if (c == 0x0c) {
        out.write('\\f');
        continue;
      }
      if (c < 0x20 || c > 0x7e) {
        out.write('\\u');
        for (final shift in const [12, 8, 4, 0]) {
          out.write('0123456789abcdef'[(c >> shift) & 0xf]);
        }
      } else {
        out.writeCharCode(c);
      }
    }
    return out.toString();
  }

  /// JDK `store` 的日期注释行：`#` + Date.toString() 形状。
  static String _javaDate(DateTime d) {
    const weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final wd = weekdays[d.weekday % 7]; // DateTime.weekday: Mon=1 .. Sun=7
    final mon = months[d.month - 1];
    final day = d.day.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    final ss = d.second.toString().padLeft(2, '0');
    return '$wd $mon $day $hh:$mm:$ss ${d.timeZoneName} ${d.year}';
  }
}

class _KeyValue {
  final String key;
  final String value;
  _KeyValue(this.key, this.value);
}
