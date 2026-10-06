// 官方 client jar 资产提取器。
//
// 用法：
//   dart run tool/extract_assets.dart list    <client.jar>            # 枚举 assets/ 分类计数
//   dart run tool/extract_assets.dart extract <client.jar> [--out <dir>]  # 提取+拼图集
//
// extract 提取方块资产（blockstates / models/block / textures/block）到
// assets/vanilla/26_2/（版本标记目录，gitignore——官方资产不入库），并把
// 方块贴图预拼接为 generated/block_atlas.png + generated/atlas.json（fscraft
// 实证形态：网格化只查清单取 UV）。
//
// 只读 jar；真实"应用内按版本下载 jar"是后续来源扩展（能力 resource-pipeline）。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;

const defaultOut = 'assets/vanilla/26_2';
const extractPrefixes = [
  'assets/minecraft/blockstates/',
  'assets/minecraft/models/block/',
  'assets/minecraft/textures/block/',
];

void main(List<String> args) {
  if (args.isEmpty || args.contains('--help') || args.contains('-h')) {
    _usage(exitCode: args.isEmpty ? 64 : 0);
  }
  switch (args.first) {
    case 'list':
      _list(_requireJar(args.sublist(1)));
    case 'extract':
      _extract(_requireJar(args.sublist(1)), _outDir(args));
    default:
      // 兼容旧形态：<jar> 直接枚举。
      if (args.first.endsWith('.jar')) {
        _list(File(args.first));
      } else {
        _usage(exitCode: 64);
      }
  }
}

File _requireJar(List<String> rest) {
  if (rest.isEmpty) {
    stderr.writeln('错误: 缺少 client.jar 路径');
    exit(64);
  }
  final f = File(rest.first);
  if (!f.existsSync()) {
    stderr.writeln('错误: 文件不存在: ${rest.first}');
    exit(66);
  }
  return f;
}

String _outDir(List<String> args) {
  final i = args.indexOf('--out');
  return i >= 0 && i + 1 < args.length ? args[i + 1] : defaultOut;
}

void _usage({required int exitCode}) {
  stderr.writeln('用法:');
  stderr.writeln('  dart run tool/extract_assets.dart list <client.jar>');
  stderr.writeln('  dart run tool/extract_assets.dart extract <client.jar> [--out <目录>]');
  exit(exitCode);
}

Archive _openJar(File jar) {
  try {
    return ZipDecoder().decodeBytes(jar.readAsBytesSync());
  } catch (e) {
    stderr.writeln('错误: 无法按 zip 解析 ${jar.path}（$e）');
    exit(65);
  }
}

void _list(File jar) {
  final archive = _openJar(jar);
  var total = 0;
  final byCategory = <String, int>{};
  for (final entry in archive) {
    if (!entry.isFile || !entry.name.startsWith('assets/')) continue;
    total++;
    final segments = entry.name.substring('assets/'.length).split('/');
    final category =
        segments.length >= 2 ? '${segments[0]}/${segments[1]}' : segments[0];
    byCategory[category] = (byCategory[category] ?? 0) + 1;
  }
  stdout.writeln('assets/ 条目总数: $total');
  final sorted = byCategory.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final e in sorted) {
    stdout.writeln('  ${e.key}: ${e.value}');
  }
}

void _extract(File jar, String outDirPath) {
  final archive = _openJar(jar);
  final outDir = Directory(outDirPath);
  outDir.createSync(recursive: true);

  var extracted = 0;
  final textures = <String, Uint8List>{}; // 贴图名("block/stone") → png 字节
  for (final entry in archive) {
    if (!entry.isFile) continue;
    final matched =
        extractPrefixes.where(entry.name.startsWith).toList(growable: false);
    if (matched.isEmpty) continue;
    if (!entry.name.endsWith('.json') && !entry.name.endsWith('.png')) continue;
    final rel = entry.name.substring('assets/minecraft/'.length);
    final target = File('${outDir.path}/$rel');
    target.createSync(recursive: true);
    target.writeAsBytesSync(entry.content as List<int>);
    extracted++;
    if (entry.name.startsWith('assets/minecraft/textures/block/') &&
        entry.name.endsWith('.png')) {
      // 贴图键不带扩展名（与模型 JSON 的贴图引用形态一致）：block/stone
      textures[rel.substring('textures/'.length).replaceAll('.png', '')] =
          Uint8List.fromList(entry.content as List<int>);
    }
  }
  stdout.writeln('提取 $extracted 个文件到 ${outDir.path}');
  _stitchAtlas(outDir, textures);
}

/// 拼接方块贴图图集，写 generated/block_atlas.png + atlas.json。
/// 动画贴图（竖条）取首帧（简化，mcmeta 动画后续补）。
void _stitchAtlas(Directory outDir, Map<String, Uint8List> textures) {
  final frames = <String, img.Image>{};
  for (final e in textures.entries) {
    final image = img.decodePng(e.value);
    if (image == null) {
      stderr.writeln('警告: 贴图解码失败，跳过 ${e.key}');
      continue;
    }
    if (image.width != 16) {
      stderr.writeln('警告: 非 16 宽贴图，跳过 ${e.key} (${image.width}x${image.height})');
      continue;
    }
    frames[e.key] =
        image.height > 16 ? _firstFrame(image, 16) : image;
  }

  final names = frames.keys.toList()..sort();
  var atlasW = 256;
  var placed = <String, Rect>{};
  var rowsUsed = 0;
  while (true) {
    final result = _packRows(names, atlasW);
    if (result != null) {
      placed = result.$2;
      rowsUsed = result.$1;
      break;
    }
    if (atlasW >= 4096) {
      stderr.writeln('错误: 图集放不下（宽超 4096）');
      exit(74);
    }
    atlasW *= 2;
  }
  final atlasH = _pow2(rowsUsed * 16);

  final atlas = img.Image(width: atlasW, height: atlasH);
  final manifest = <String, dynamic>{
    'size': [atlasW, atlasH],
    'textures': <String, dynamic>{},
  };
  for (final name in names) {
    final r = placed[name]!;
    img.compositeImage(atlas, frames[name]!, dstX: r.x, dstY: r.y);
    manifest['textures'][name] = {'x': r.x, 'y': r.y, 'w': r.w, 'h': r.h};
  }

  final genDir = Directory('${outDir.path}/generated')..createSync(recursive: true);
  File('${genDir.path}/block_atlas.png').writeAsBytesSync(img.encodePng(atlas));
  File('${genDir.path}/atlas.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifest));
  stdout.writeln('图集: ${genDir.path}/block_atlas.png (${atlasW}x$atlasH, ${names.length} 贴图)');
}

/// 行式装箱：行高统一 16。返回 (已用行数, 布局)；放不下返回 null。
(int, Map<String, Rect>)? _packRows(List<String> names, int atlasW) {
  final placed = <String, Rect>{};
  var cursorX = 0;
  var row = 0;
  for (final name in names) {
    if (cursorX + 16 > atlasW) {
      cursorX = 0;
      row++;
    }
    placed[name] = Rect(cursorX, row * 16, 16, 16);
    cursorX += 16;
  }
  return (row + 1, placed);
}

img.Image _firstFrame(img.Image strip, int frameW) {
  final frame = img.Image(width: frameW, height: frameW);
  for (var y = 0; y < frameW; y++) {
    for (var x = 0; x < frameW; x++) {
      frame.setPixel(x, y, strip.getPixel(x, y));
    }
  }
  return frame;
}

int _pow2(int v) {
  var p = 1;
  while (p < v) {
    p *= 2;
  }
  return p;
}

class Rect {
  Rect(this.x, this.y, this.w, this.h);
  final int x;
  final int y;
  final int w;
  final int h;
}
