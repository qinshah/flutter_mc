// 从 jar（ZIP 容器）读 `META-INF/MANIFEST.MF` 主清单的 `Main-Class`。
//
//   承载层属第三类自由设计「运行时宿主（JVM 托管）」（AGENTS.md）。这一步复刻的是真
//   `java -jar` 的行为：JDK 启动器经 `JarFile.getManifest()` 读主清单属性并取
//   `Main-Class`（`sun.launcher.LauncherHelper.getMainClass`）。清单语义照
//   `java.util.jar.Manifest`：
//     · 节（section）以空行分隔，**第一节是主属性（main attributes）**；
//     · 属性名对大小写不敏感（`Attributes.Name` 的 hashCode/equals 走 Ascii 小写）；
//     · 行长上限 72 字节，超长续行以**单个空格**开头，解析时去掉该空格接回上一行。
//
//   为什么不用 `archive` 包：它在本仓是 dev 依赖（不进 `lib/`），且 paperclip jar
//   ~50MB，全量解码在真机上内存代价过大。这里只做**最小 ZIP 读取**——按 ZIP 规范
//   （APPNOTE 4.3.16/4.3.12/4.3.7）定位 EOCD → 中央目录 → 目标条目 → 局部头 → 数据，
//   只解压 MANIFEST 一个条目（deflate 用 SDK 的 `ZLibCodec(raw: true)`，stored 直读）。
//   限制：不支持 ZIP64（jar 单条目 > 4GB / 条目数 > 65535 才会用到，现实不会触碰）。
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

class JarManifest {
  JarManifest._();

  /// 读 jar 的主清单 `Main-Class`；无清单或无该属性返回 null（由调用方显式报错，
  /// 等价于真 `java -jar` 的 `no main manifest attribute`）。
  static String? readMainClassSync(File jar) {
    final bytes = _readEntrySync(jar, 'META-INF/MANIFEST.MF');
    if (bytes == null) return null;
    return mainClassOf(utf8.decode(bytes, allowMalformed: true));
  }

  /// 解析 MANIFEST 文本 → 主属性 `Main-Class`（`java.util.jar.Manifest` 语义，见文件头注释）。
  static String? mainClassOf(String text) {
    // 行折叠（续行以单个空格开头）。注意要先合并续行再判空行：续行本身可能是空格后空内容。
    final lines = <String>[];
    for (var raw in text.split('\n')) {
      if (raw.endsWith('\r')) raw = raw.substring(0, raw.length - 1);
      if (raw.startsWith(' ') && lines.isNotEmpty) {
        lines[lines.length - 1] = lines.last + raw.substring(1);
      } else if (raw.isNotEmpty) {
        lines.add(raw);
      } else if (lines.isNotEmpty) {
        break; // 第一个空行 = 主属性节结束（后续是逐 jar/逐包的具名节）
      }
    }
    for (final line in lines) {
      final i = line.indexOf(': ');
      if (i <= 0) continue;
      final name = line.substring(0, i);
      if (name.toLowerCase() == 'main-class') {
        return line.substring(i + 2).trim();
      }
    }
    return null;
  }

  // ── 最小 ZIP 读取（APPNOTE 规范偏移，注释逐字段对应） ──────────────────────────

  /// 从 ZIP 容器读出 [name] 条目的**未压缩**内容；条目不存在返回 null。
  static Uint8List? _readEntrySync(File jar, String name) {
    final raf = jar.openSync();
    try {
      final length = raf.lengthSync();

      // EOCD（End Of Central Directory，APPNOTE 4.3.16）：签名 0x06054b50，
      // 固定 22 字节 + 可选注释（≤ 65535），故从尾部最多回扫 22 + 65535 字节。
      final scanStart = math.max(0, length - (22 + 65535));
      raf.setPositionSync(scanStart);
      final tail = raf.readSync(length - scanStart);
      var eocd = -1;
      for (var i = tail.length - 22; i >= 0; i--) {
        if (_u32le(tail, i) == 0x06054b50) {
          eocd = i;
          break;
        }
      }
      if (eocd < 0) {
        throw FormatException('不是有效的 jar/zip（找不到 EOCD）：${jar.path}');
      }
      // EOCD 字段：+10 条目总数（本盘面），+12 中央目录大小，+16 中央目录偏移。
      final entryCount = _u16le(tail, eocd + 10);
      final cdSize = _u32le(tail, eocd + 12);
      final cdOffset = _u32le(tail, eocd + 16);

      // 中央目录（Central Directory，APPNOTE 4.3.12）：逐条扫到目标名字为止。
      raf.setPositionSync(cdOffset);
      final cd = raf.readSync(cdSize);
      var p = 0;
      for (var i = 0; i < entryCount; i++) {
        if (p + 46 > cd.length || _u32le(cd, p) != 0x02014b50) break;
        // 字段：+10 压缩方法，+20 压缩后大小，+28 名字长，+30 扩展区长，
        //       +32 注释长，+42 局部头偏移，+46 名字。
        final method = _u16le(cd, p + 10);
        final compSize = _u32le(cd, p + 20);
        final nameLen = _u16le(cd, p + 28);
        final extraLen = _u16le(cd, p + 30);
        final commentLen = _u16le(cd, p + 32);
        final localOffset = _u32le(cd, p + 42);
        final entryName =
            utf8.decode(cd.sublist(p + 46, p + 46 + nameLen), allowMalformed: true);
        if (entryName == name) {
          return _readEntryData(raf, localOffset, nameLen, method, compSize);
        }
        p += 46 + nameLen + extraLen + commentLen;
      }
      return null;
    } finally {
      raf.closeSync();
    }
  }

  /// 按局部头（Local File Header，APPNOTE 4.3.7）跳过名字/扩展区后取数据。
  ///
  /// 压缩后大小取自**中央目录**（局部头在 data descriptor 流式写法下可能为 0，
  /// 中央目录里恒有真值），故局部头只需用来定位数据起点。
  static Uint8List _readEntryData(
      RandomAccessFile raf, int localOffset, int nameLen, int method, int compSize) {
    raf.setPositionSync(localOffset);
    final header = raf.readSync(30);
    if (header.length < 30 || _u32le(header, 0) != 0x04034b50) {
      throw const FormatException('ZIP 局部头损坏（签名不符）');
    }
    final lhNameLen = _u16le(header, 26);
    final lhExtraLen = _u16le(header, 28);
    raf.setPositionSync(localOffset + 30 + lhNameLen + lhExtraLen);
    final data = raf.readSync(compSize);
    switch (method) {
      case 0: // stored
        return data;
      case 8: // deflate（raw，无 zlib 头——ZIP 的 deflate 不带 0x78 头）
        return Uint8List.fromList(ZLibCodec(raw: true).decode(data));
      default:
        throw FormatException('不支持的 ZIP 压缩方法 $method（条目读取仅 stored/deflate）');
    }
  }

  static int _u16le(Uint8List b, int i) => b[i] | (b[i + 1] << 8);
  static int _u32le(Uint8List b, int i) =>
      b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24);
}
