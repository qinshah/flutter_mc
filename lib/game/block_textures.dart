import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:mc_render/mc_render.dart';
import 'package:mc_resource/mc_resource.dart';

/// 方块贴图查表：`stateId + 面 → 图集 UV 矩形`（网格器的 `uvFor` 注入点）。
///
/// 原版对应物：`client.renderer.block.BlockRenderDispatcher` 里"取该面精灵"那一步
/// —— `ModelBlockRenderer` 从烘焙好的模型按 `Direction` 取 `TextureAtlasSprite`。
///
/// **为什么要预解析成表**：网格器的 `uvFor` 是**同步**签名（一段网格化要问上千次），
/// 而 `BlockModels.resolve` 是**异步**的（要读 blockstates + model JSON）。所以启动期
/// 把「方块名 → 面键 → 贴图路径」解析一次，运行期只做同步查表 + 图集取矩形。
///
/// 已知代价（首版）：启动期对身份表里出现的**全部**方块名各解析一次（约千次），
/// 在桌面端是可接受的几秒；更好的做法是像 fscraft 那样在构建期把面→tile 表生成好
/// （见后续 change），届时这里退化成纯查表。
class BlockTextures {
  BlockTextures._(this._atlas, this._byBlock, this._fallback);

  /// 版本资产目录名（构建期提取产物 `assets/vanilla/<version>/` 的最后一级）。
  /// 这是**构建产物路径**，不是协议版本分支。
  static const String assetVersion = '26_2';

  /// 图集 PNG 的资产路径（材质用整图 + UV 采样，不做逐贴图材质）。
  static const String atlasAssetPath =
      'assets/vanilla/$assetVersion/generated/block_atlas.png';

  final BlockAtlas _atlas;

  /// 方块名（去命名空间/属性）→ 原版模型纹理键 → 贴图路径（相对 `textures/` 根）。
  final Map<String, Map<String, String>> _byBlock;

  /// 查不到时的兜底矩形。
  final UvRect _fallback;

  /// `stateId → 该方块的 面键→贴图路径`（未收录为 null）。
  ///
  /// 必须缓存：`BlockSemanticsV262.blockNameOf` 每次都做身份串的字符串解析，
  /// 而 `uvFor` 是**逐面**调用的热路径。
  final Map<int, Map<String, String>?> _byState = {};

  int get spriteCount => _atlas.spriteCount;
  int get blockCount => _byBlock.length;

  /// 从应用 bundle 读资源包并预解析。
  ///
  /// 资产缺失（没跑过 `tool/extract_assets.dart`）时返回 null——调用方退化为
  /// 纯顶点色渲染，与资源抽象"缺失即降级"的取向一致。
  static Future<BlockTextures?> load() async {
    final source = CallbackPackSource(_readAsset);
    final atlas = await BlockAtlas.load(source);
    if (atlas == null) return null;

    // BlockModels 要的是 VanillaPack（版本 + 来源），BlockAtlas 只要来源。
    final models = BlockModels(
      VanillaPack(version: assetVersion, source: source),
    );
    final byBlock = <String, Map<String, String>>{};
    final names = <String>{
      for (final id in kBlockStateIdentity262.keys)
        BlockSemanticsV262.blockNameOf(id),
    };
    for (final name in names) {
      final resolved = await models.resolve('minecraft:$name');
      if (resolved != null) byBlock[name] = resolved;
    }

    // 兜底取石头（原版"缺失贴图"是紫黑格；我们没有那张贴图，取石头最不刺眼）。
    final stone = atlas.sprite('block/stone');
    final fallback = stone == null
        ? const UvRect(0, 0, 1, 1)
        : UvRect(stone.minU, stone.minV, stone.maxU, stone.maxV);

    return BlockTextures._(atlas, byBlock, fallback);
  }

  /// Flutter 资产读取（`PackSource` 契约：缺失返回 null，不抛）。
  static Future<Uint8List?> _readAsset(String path) async {
    try {
      final data =
          await rootBundle.load(VanillaPack.bundlePath(assetVersion, path));
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (_) {
      return null;
    }
  }

  /// 网格器注入点。**永不返回 null**（网格器签名非空），未知方块/缺贴图时兜底。
  UvRect uvFor(int stateId, BlockFace face) {
    final byKey = _byState.putIfAbsent(
      stateId,
      () => _byBlock[BlockSemanticsV262.blockNameOf(stateId)],
    );
    if (byKey != null) {
      for (final key in _keysFor(face)) {
        final path = byKey[key];
        if (path == null) continue;
        final sprite = _atlas.sprite(path);
        if (sprite != null) {
          return UvRect(sprite.minU, sprite.minV, sprite.maxU, sprite.maxV);
        }
      }
    }
    return _fallback;
  }

  /// 面 → 原版模型纹理键的**优先级链**。
  ///
  /// 原版 `BlockModel` 的键空间：立方体全用 `all`；分面用 `top`/`bottom`/`side`；
  /// 柱状方块（石英、原木端面）用 `end`；十字植物（矮草、花）用 `cross`。
  /// 逐级回退，是为了让各类模型都能取到一张说得过去的贴图。
  static List<String> _keysFor(BlockFace face) => switch (face) {
        BlockFace.up => const ['top', 'up', 'end', 'all', 'side'],
        BlockFace.down => const ['bottom', 'down', 'end', 'all', 'side'],
        BlockFace.north ||
        BlockFace.south ||
        BlockFace.east ||
        BlockFace.west =>
          const ['side', 'cross', 'all', 'end', 'north', 'south', 'east', 'west'],
      };
}
