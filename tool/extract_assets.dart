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
  // biome 着色用的索引调色板（判据`GrassColorReloadListener` /
  // `FoliageColorReloadListener` 读 textures/colormap/{grass,foliage}.png）。
  // 少了它，所有 L/P 模式的灰度索引贴图（草方块顶面、树叶等）会被解成灰色。
  'assets/minecraft/textures/colormap/',
];

/// 需要按 biome 默认色着色的 colormap 资产（文件名 → 判据里的类）。
const colormapFiles = <String, String>{
  'grass': 'GrassColor.getDefaultColor() = get(0.5, 1.0)',
  'foliage': 'FoliageColor.getDefaultColor()',
  // 干枯/ underwater 变体：暂不参与着色，先提取备用。
  'dry_foliage': 'DryFoliageColor',
};

void main(List<String> args) {
  if (args.isEmpty || args.contains('--help') || args.contains('-h')) {
    _usage(exitCode: args.isEmpty ? 64 : 0);
  }
  switch (args.first) {
    case 'list':
      _list(_requireJar(args.sublist(1)));
    case 'extract':
      _extract(_requireJar(args.sublist(1)), _outDir(args));
    case 'restitch':
      // 从**已提取的贴图目录**重跑图集拼接（不需 client jar）。
      // 用途：贴图打包策略（通道归一 / 尺寸 / 排序）改动后重拼，不必重解 jar。
      _restitch(Directory(_outDir(args)));
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
  // 灰度索引贴图（草方块顶面/树叶）必须按 biome colormap 着色，否则是灰色。
  final tints = _loadColormaps(outDir);
  _stitchAtlas(outDir, textures, tints: tints);
}

/// 从已提取目录重跑图集拼接（`restitch` 子命令）。
///
/// 与 [extract] 的差别只在**贴图来源**：这里读 `<outDir>/textures/block/*.png`，
/// 而 extract 从 jar 解压。因此可以在不持有 client jar 的机器上迭代打包策略
/// （通道归一、图集尺寸、排序）——本仓 `assets/vanilla/` 是 gitignore 产物，
/// 但提取出的 PNG 仍在，重拼比重新解 jar 快得多。
void _restitch(Directory outDir) {
  final blockDir = Directory('${outDir.path}/textures/block');
  if (!blockDir.existsSync()) {
    stderr.writeln('错误: 贴图目录不存在: ${blockDir.path}（先跑 extract）');
    exit(66);
  }
  final textures = <String, Uint8List>{};
  for (final f in blockDir.listSync()) {
    if (f is! File || !f.path.toLowerCase().endsWith('.png')) continue;
    textures['block/${f.uri.pathSegments.last.replaceAll('.png', '')}'] =
        f.readAsBytesSync();
  }
  if (textures.isEmpty) {
    stderr.writeln('错误: ${blockDir.path} 下没有 PNG');
    exit(66);
  }
  final tints = _loadColormaps(outDir);
  stdout.writeln('restitch: 读入 ${textures.length} 张已提取贴图'
      '${tints.isEmpty ? '（未找到 colormap，灰度贴图将保持灰色）' : '，colormap ${tints.keys.join("/")}'}');
  _stitchAtlas(outDir, textures, tints: tints);
}

/// colormap 名 → 该colormap 的256 级颜色带（索引 0..255）。
typedef TintRamp = List<int>;

// biome 着色只对特定材质生效（判据 `BlockColors` 的 tint 索引约定）。
// 草方块顶面/草类植物走 grass，树叶类走 foliage——按**贴图路径**判定，
// 因为这是离线构建期唯一拿得到的信息（原版是按 material 在运行时查表）。
final _grassTintPrefixes = <String>[
  'block/grass_block_top',
  'block/short_grass', 'block/tall_grass', 'block/fern', 'block/dead_bush',
  'block/grass', 'block/seagrass', 'block/tall_seagrass',
];
final _foliageTintPrefixes = <String>[
  'block/oak_leaves', 'block/birch_leaves', 'block/spruce_leaves',
  'block/jungle_leaves', 'block/acacia_leaves', 'block/dark_oak_leaves',
  'block/mangrove_leaves', 'block/azalea_leaves', 'block flowering_azalea_leaves',
  'block/cherry_leaves', 'block/pale_oak_leaves',
];

String? _tintKeyFor(String textureKey) {
  for (final p in _grassTintPrefixes) {
    if (textureKey == p || textureKey.startsWith('$p/')) return 'grass';
  }
  for (final p in _foliageTintPrefixes) {
    if (textureKey == p || textureKey.startsWith('$p/')) return 'foliage';
  }
  return null;
}

bool _isTinted(String textureKey, Map<String, TintRamp> tints) {
  final k = _tintKeyFor(textureKey);
  return k != null && tints.containsKey(k);
}

/// 内容是否为灰阶（三通道近似相等）。
///
/// 容差 12：索引图解码后可能有±1 的量化误差；彩色树叶贴图（如 oak_leaves
/// 的绿色调色板）通道差远超此值，不会被误判。
bool _isGrayscale(img.Image im) {
  var sampled = 0;
  for (var y = 0; y < im.height; y++) {
    for (var x = 0; x < im.width; x++) {
      final p = im.getPixel(x, y);
      if (p.a == 0) continue; // 全透明像素无意义
      final r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
      final m = r > g ? (r > b ? r : b) : (g > b ? g : b);
      final n = r < g ? (r < b ? r : b) : (g < b ? g : b);
      if (m - n > 12) return false;
      if (++sampled >= 64) return true; // 采样够 64 个不彩色像素即判灰阶
    }
  }
  return true; // 全透明/采样不足 → 视为灰阶（无色可染）
}

/// 按 colormap 给灰度索引图着色：**逐通道相乘**，保留原 alpha。
///
/// 判据（`ModelBlockRenderer` 第 215 行）：材质带 `tintIndex != -1` 时调用
/// `quadInstance.multiplyColor(tintColor)` —— 是**乘法**，不是查表替换。
/// 这解释了为什么 colormap 只有一半列有值：灰度索引普遍 >127（如
/// grass_block_top 索引 148/195），若按查表直取会拿到纯白 `(255,255,255)`
/// （colormap 的空白区），草方块顶面就变成白色；乘法则保留灰度明暗，
/// 只是整体染上 biome 色调。
///
/// 乘法按 `out = round(src * tint / 255)` 逐通道算；tint 取 colormap 的
/// 默认 biome 行（判据 `GrassColor.getDefaultColor()` = `get(0.5, 1.0)`
/// ⇒ x=127, y=127）。
img.Image _applyTint(img.Image src, TintRamp ramp) {
  final out = img.Image(width: src.width, height: src.height, numChannels: 4);
  // 只有一个色调常量（默认 biome），取一次即可。
  final tint = ramp[127 & 0xFF];
  final tr = (tint >> 16) & 0xFF;
  final tg = (tint >> 8) & 0xFF;
  final tb = tint & 0xFF;
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      final p = src.getPixel(x, y);
      if (p.a == 0) {
        out.setPixelRgba(x, y, 0, 0, 0, 0);
        continue;
      }
      // 灰度索引在解码后的 r 通道；三个通道此时都等于该灰度。
      final g = p.r.toInt();
      out.setPixelRgba(
        x, y,
        (g * tr + 127) ~/ 255,
        (g * tg + 127) ~/ 255,
        (g * tb + 127) ~/ 255,
        p.a.toInt(),
      );
    }
  }
  return out;
}

/// 读 `<outDir>/textures/colormap/*.png` 解析成 256 级颜色带。
Map<String, TintRamp> _loadColormaps(Directory outDir) {
  final dir = Directory('${outDir.path}/textures/colormap');
  if (!dir.existsSync()) return const {};
  final out = <String, TintRamp>{};
  for (final name in colormapFiles.keys) {
    final f = File('${dir.path}/$name.png');
    if (!f.existsSync()) continue;
    final cmap = img.decodePng(f.readAsBytesSync());
    if (cmap == null) continue;
    // colormap 是 256×256 的调色板条，判据 `ColorMapColorUtil.get`：
    //   x = (int)((1.0 - temp) * 255.0)   // 温度轴 = 列
    //   y = (int)((1.0 - rain * temp) * 255.0)  // 湿度轴 = 行
    //   index = y << 8 | x
    // 本切片不实现按 biome 变化，只取**默认 biome** 的那一行：
    //   `GrassColor.getDefaultColor()` = get(0.5, 1.0) ⇒ x = 127, y = 0
    //   （rain *= temp ⇒ 1.0*0.5 = 0.5 ⇒ y = (1-0.5)*255 = 127）
    // 即第 127 行；索引 i → 该行第 i 列。
    const defaultRow = 127;
    final row = defaultRow < cmap.height ? defaultRow : cmap.height ~/ 2;
    final ramp = List<int>.filled(256, 0x000000);
    for (var i = 0; i < 256 && i < cmap.width; i++) {
      final p = cmap.getPixel(i, row);
      ramp[i] = (p.r.toInt() << 16) | (p.g.toInt() << 8) | p.b.toInt();
    }
    out[name] = ramp;
    stdout.writeln('  colormap $name: ${cmap.width}x${cmap.height} '
        '取默认 biome 行 y=$row（get(0.5,1.0)）');
  }
  return out;
}

/// 拼接方块贴图图集，写 generated/block_atlas.png + atlas.json。
/// 动画贴图（竖条）取首帧（简化，mcmeta 动画后续补）。
void _stitchAtlas(
  Directory outDir,
  Map<String, Uint8List> textures, {
  Map<String, TintRamp> tints = const {},
}) {
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
    // **必须归一到 RGBA**：jar 里的方块贴图有 L（灰度索引）/ P（调色板）/ LA /
    // 1（位图）等模式，而 `compositeImage` / `setPixel` 是**逐通道**复制的。
    // 直接把 L 模式的灰度索引当 RGB 复制会让像素变成 (v,0,0) —— 实测
    // grass_block_top 整张变纯红 (148,0,0)、bedrock 变暗红，这就是"大片红色"的根因。
    // `convert(numChannels: 4)` 让 P 走调色板展开、L/LA 走灰度→灰度RGB、1 走位图→黑白。
    var rgba = image.convert(numChannels: 4);
    rgba = rgba.height > 16 ? _firstFrame(rgba, 16) : rgba;
    // L 模式是**索引图**，不是最终颜色：原版用 biome colormap 运行时着色
    // （`ModelBlockRenderer` → `multiplyColor`，色源 `GrassColor/FoliageColor`）。
    // 不着色就会得到灰色草方块顶面/灰色云杉叶（实测修复红 bug 后暴露出来）。
    //
    // 判据用**内容是否灰阶**而非通道数：`decodePng` 已把 L 模式展开成 RGB，
    // 通道数信息丢失。灰阶检测同时天然排除了自带彩色的 P 模式贴图
    // （oak_leaves/jungle_leaves 的调色板是彩色的，本就不该着色）。
    if (_isTinted(e.key, tints) && _isGrayscale(rgba)) {
      rgba = _applyTint(rgba, tints[_tintKeyFor(e.key)]!);
    }
    frames[e.key] = rgba;
  }

  final names = frames.keys.toList()..sort();
  // 宽度选择：在 2 的幂候选里取「宽 + 高」最小者，并列时取更接近正方形者。
  //
  // **不能"能装下就停"**：从 256 起第一个装得下的宽度会把高度撑得极大——
  // 1227 张 16px 贴图在 256 宽只需约 1232 行，而高度要取 2 的幂 → 2048，
  // 于是图集 65% 是空黑（4.1 实拍：mipmap 降级被黑区污染 + 纹理内存浪费）。
  // 本批数据下 512 宽 → 1024 高（宽+高 2304 → 1536，比例 1:8 → 1:2）。
  var placed = <String, Rect>{};
  var rowsUsed = 0;
  var atlasW = 0;
  var bestSum = 1 << 30;
  var bestDelta = 1 << 30;
  for (var candidate = 256; candidate <= 4096; candidate *= 2) {
    final result = _packRows(names, candidate);
    if (result == null) continue;
    final height = _pow2(result.$1 * 16);
    final sum = candidate + height;
    final delta = (candidate - height).abs();
    if (sum < bestSum || (sum == bestSum && delta < bestDelta)) {
      bestSum = sum;
      bestDelta = delta;
      atlasW = candidate;
      placed = result.$2;
      rowsUsed = result.$1;
    }
  }
  if (atlasW == 0) {
    stderr.writeln('错误: 图集放不下（宽超 4096）');
    exit(74);
  }
  final atlasH = _pow2(rowsUsed * 16);

  // 画布必须是 RGBA（4 通道）：默认的 uint8 只有 3 通道，写入时会丢掉 alpha，
  // 且与上面归一后的 RGBA 源图通道数不一致。
  final atlas = img.Image(width: atlasW, height: atlasH, numChannels: 4);
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
  final frame = img.Image(width: frameW, height: frameW, numChannels: 4);
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
