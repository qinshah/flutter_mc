/// 方块图集清单（`generated/atlas.json`）的加载与查询（原版
/// `net.minecraft.client.renderer.texture.TextureAtlas` 的 sprite 索引面对应物，
/// 纯 Dart）。
///
/// 原版对应物：`net.minecraft.client.renderer.texture.TextureAtlas` —— 它持有图集内
/// 每张 `TextureAtlasSprite` 的像素矩形（`getX()`/`getY()`），而像素矩形到 UV 的换算
/// 在 `TextureAtlasSprite` 构造时完成：
/// `u0 = x / atlasWidth`、`u1 = (x + contents.width()) / atlasWidth`、
/// `v0 = y / atlasHeight`、`v1 = (y + contents.height()) / atlasHeight`
/// （判据 `mc-sources/minecraft-26.2/net/minecraft/client/renderer/texture/TextureAtlasSprite.java:34-37`；
/// 原式还含 `padding`，本管线构建期拼接不写 padding，故按 padding=0 简化）。
/// 差别只在时机：原版在运行期用 Stitcher 拼图并建立 sprite 索引，本项目改为构建期
/// （`tool/extract_assets.dart`）预拼并把该索引静态化为 `generated/atlas.json`，本文件
/// 只负责把它读回成纯数据；不持有贴图内容，不碰 GPU/引擎类型。
///
/// 清单形态（顶层仅 `size` 与 `textures` 两个键）：
/// ```json
/// { "size": [256, 2048],
///   "textures": { "block/stone": {"x": 0, "y": 0, "w": 16, "h": 16} } }
/// ```
/// `textures` 的键是资源包内相对路径（相对 `textures/` 根，与 `BlockModels` 的输出
/// 同一坐标系，如 `block/stone`）。
library;

import 'dart:convert';

import 'vanilla_pack.dart';

/// 图集内一张贴图的矩形，同时给出像素矩形与规范化 UV 矩形。
///
/// 坐标系约定：
/// - 像素矩形以图集**左上角**为原点，x 向右、y 向下；[x]/[y] 是贴图左上角像素，
///   [width]/[height] 是贴图尺寸（当前管线恒为 16×16，本类型不假设这一点）。
/// - UV 矩形归一化到 [0,1]：`minU = x / 图集宽`、`maxU = (x + width) / 图集宽`、
///   `minV = y / 图集高`、`maxV = (y + height) / 图集高`；**v 向下增长**（v=0 在图集
///   顶边），与原版 `TextureAtlasSprite` 一致。
class AtlasSprite {
  const AtlasSprite({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.minU,
    required this.minV,
    required this.maxU,
    required this.maxV,
  });

  /// 由左上原点像素矩形与图集尺寸换算 UV（原版 `TextureAtlasSprite` 构造式的 Dart 版）。
  factory AtlasSprite.fromPixels({
    required int x,
    required int y,
    required int width,
    required int height,
    required int atlasWidth,
    required int atlasHeight,
  }) {
    return AtlasSprite(
      x: x,
      y: y,
      width: width,
      height: height,
      minU: x / atlasWidth,
      minV: y / atlasHeight,
      maxU: (x + width) / atlasWidth,
      maxV: (y + height) / atlasHeight,
    );
  }

  /// 贴图左上角在图集内的像素坐标（原点为图集左上角，y 向下）。
  final int x;
  final int y;

  /// 贴图像素尺寸。
  final int width;
  final int height;

  /// 归一化 UV 矩形（v 向下增长）。
  final double minU;
  final double minV;
  final double maxU;
  final double maxV;

  @override
  String toString() =>
      'AtlasSprite(pixel: $x,$y ${width}x$height, uv: '
      '${minU.toStringAsFixed(6)},${minV.toStringAsFixed(6)} -> '
      '${maxU.toStringAsFixed(6)},${maxV.toStringAsFixed(6)})';
}

/// 图集清单（贴图相对路径 → 图集矩形）+ 图集像素尺寸。
///
/// 构造取向与包内既有 `BlockModels` 一致：不抛异常，读不到/坏数据一律 null，
/// 无法解释的条目跳过（跳过等价于"未收录"，查询得 null）。
class BlockAtlas {
  BlockAtlas({
    required this.width,
    required this.height,
    required Map<String, AtlasSprite> sprites,
  }) : _sprites = Map.unmodifiable(sprites);

  /// 清单相对资源包根的路径（[VanillaPack.read] / [PackSource.read] 的参数）。
  static const String defaultPath = 'generated/atlas.json';

  /// 图集像素尺寸。
  final int width;
  final int height;

  final Map<String, AtlasSprite> _sprites;

  /// 已收录的贴图数。
  int get spriteCount => _sprites.length;

  /// 已收录的贴图相对路径（顺序即清单顺序）。
  Iterable<String> get texturePaths => _sprites.keys;

  /// 解析清单 JSON 文本；坏 JSON 或缺少 `size`/`textures` 返回 null。
  ///
  /// 单个条目畸形（缺字段 / 非正尺寸 / 超出图集范围）只跳过该条，不影响其余条目。
  static BlockAtlas? parse(String jsonText) {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;

    final size = decoded['size'];
    if (size is! List || size.length != 2) return null;
    final width = size[0];
    final height = size[1];
    if (width is! int || height is! int) return null;
    if (width <= 0 || height <= 0) return null;

    final textures = decoded['textures'];
    if (textures is! Map<String, dynamic>) return null;

    final sprites = <String, AtlasSprite>{};
    textures.forEach((key, value) {
      if (value is! Map<String, dynamic>) return;
      final x = value['x'];
      final y = value['y'];
      final w = value['w'];
      final h = value['h'];
      if (x is! int || y is! int || w is! int || h is! int) return;
      if (w <= 0 || h <= 0) return;
      // 与 resource-pipeline spec「矩形都在图集尺寸内」一致：越界条目视为无效。
      if (x < 0 || y < 0 || x + w > width || y + h > height) return;
      sprites[key] = AtlasSprite.fromPixels(
        x: x,
        y: y,
        width: w,
        height: h,
        atlasWidth: width,
        atlasHeight: height,
      );
    });
    return BlockAtlas(width: width, height: height, sprites: sprites);
  }

  /// 从资源包来源读清单（默认 [defaultPath]）；文件缺失或内容不可解析返回 null。
  static Future<BlockAtlas?> load(
    PackSource source, {
    String path = defaultPath,
  }) async {
    final bytes = await source.read(path);
    if (bytes == null) return null;
    // 坏字节按替换字符处理，交由 JSON 解析判定失败，而不是在此抛异常。
    return parse(utf8.decode(bytes, allowMalformed: true));
  }

  /// 贴图相对路径 → 矩形；未收录返回 null。
  ///
  /// 入参容忍命名空间前缀（`minecraft:block/stone`），统一剥离后再查，与
  /// `BlockModels.resolve` 的输出取向一致。
  AtlasSprite? sprite(String texturePath) {
    final i = texturePath.indexOf(':');
    final key = i >= 0 ? texturePath.substring(i + 1) : texturePath;
    return _sprites[key];
  }
}
