import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
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
/// **按需增量解析**（不是启动期全量）：启动只读图集；`uvFor` 遇到没解析过的方块名时
/// 立刻返回兜底 UV，并在后台解析它的模型，解析完成后经 [onResolved] 通知调用方把
/// 已网格化的段标脏重做。
///
/// 为什么不能启动期全量：身份表里有上千个方块名，每个要读 1–4 个资产（约 3000 次
/// rootBundle 读取，且在主 isolate）——实测 >2 分钟仍未完成，把进游戏屏整个阻塞住。
/// 按需解析只需覆盖当前视野里真正出现的几十到几百种方块。
///
/// 更好的终局是像 fscraft 那样在构建期生成「方块 → 面 → 图集 tile」表（见后续
/// change），届时这里退化成纯查表，还能省掉打包 blockstates/models。
class BlockTextures {
  BlockTextures._(this._atlas, this._byBlock, this._fallback);

  /// 版本资产目录名（构建期提取产物 `assets/vanilla/<version>/` 的最后一级）。
  /// 这是**构建产物路径**，不是协议版本分支。
  static const String assetVersion = '26_2';

  /// 图集 PNG 的资产路径（材质用整图 + UV 采样，不做逐贴图材质）。
  static const String atlasAssetPath =
      'assets/vanilla/$assetVersion/generated/block_atlas.png';

  /// 按需解析用（来自资源包的模型读取器）。
  late final BlockModels _models;

  /// 正在后台解析的方块名（去重）。
  final Set<String> _pending = {};

  /// 有新的方块纹理解析完成时的回调：调用方据此把已网格化的段标脏重做 UV。
  void Function()? onResolved;

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

    // 兜底取石头（原版"缺失贴图"是紫黑格；我们没有那张贴图，取石头最不刺眼）。
    final stone = atlas.sprite('block/stone');
    final fallback = stone == null
        ? const UvRect(0, 0, 1, 1)
        : UvRect(stone.minU, stone.minV, stone.maxU, stone.maxV);

    final textures = BlockTextures._(
      atlas,
      <String, Map<String, String>>{},
      fallback,
    );
    // BlockModels 要的是 VanillaPack（版本 + 来源），BlockAtlas 只要来源。
    textures._models = BlockModels(
      VanillaPack(version: assetVersion, source: source),
    );
    return textures;
  }

  /// 构建期扫描全部方块，得出**十字面片方块名集合**（判据驱动，供
  /// `BlockSemanticsV262` 注入，取代手写名单）。
  ///
  /// 判据：模型 parent 链命中 `BlockModels.crossTemplateParents`
  /// （`block/cross` / `block/tinted_cross` / `block/template_seagrass`）。
  /// 这三个模板的共同形态是"零厚度薄面片"，语义即十字面片。
  ///
  /// 判据来源说明：原版的"方块 → 渲染层"完整注册表在 `BlockRenderLayer`，
  /// 该类已编译进客户端渲染库、`mc-sources` 中不存在（全树 grep 零命中），
  /// 故改用模型 parent 链这一可得判据——比手写名单完备（新方块自动覆盖）。
  Future<Set<String>> buildCrossBlockSet() async {
    final result = <String>{};
    for (final name in _allBlockNames) {
      if (await _models.isCrossModel('minecraft:$name')) result.add(name);
    }
    return result;
  }

  /// 构建期扫描全部方块，得出**stateId → 真实几何**表（判据驱动，供
  /// `BlockSemanticsV262.geometryByState` 注入，让网格器按模型 `elements` 出面）。
  ///
  /// 判据（`net/minecraft.client.resources.model.cuboid`）：
  /// - `CuboidModelElement.java:22/51-52` —— `elements[].from/to`（0..16 坐标）
  /// - `CuboidModelElement.java:114-118` —— `faces` 为空原版抛异常 ⇒ **只画声明的面**
  /// - `FaceBakery.java:131` —— 顶点 `div(16.0F)` 归一化到 0..1
  ///
  /// **按 state 变体解析**：半砖 `type=bottom`/`type=top`、楼梯 `shape=*`/
  /// `facing=*` 走**不同模型**（几何也不同），故按 `variantKey` 取模型路径，
  /// 不能只取首个变体。
  ///
  /// **blockstate 变体旋转**（判据 `Variant.java:73-76` 的 `asModelState`）：
  /// 变体的 `x`/`y`/`z` + `uvlock` 经 `BlockModelRotation` 复合成
  /// [OctahedralGroup]，再按 `FaceBakery` 的烘焙路径旋转几何与 UV
  /// （`bakeBlockstateRotation`）——楼梯 `half=top`（x=180）与 `facing`（y）
  /// 由此生效。
  ///
  /// 带 `rotation` 的模型**不注入**几何（本网格器不支持元素级旋转，见
  /// `BlockGeometry.hasUnsupportedRotation`）——那些方块会退回整方块路径，
  /// **不会**静默按未旋转渲染。
  Future<Map<int, BlockGeometryMesh>> buildGeometryMap() async {
    final result = <int, BlockGeometryMesh>{};
    var rotationSkipped = 0;
    // **按「模型+变体旋转」去重**：模型只有两千余个，而 state 有 32366 个——
    // 同一模型被几百个 state 复用（所有石砖变体都指向 `block/stone_bricks`）。
    // 不缓存会重复读同一 JSON 六万余次、耗时 6.4 秒（实测），足以卡住启动。
    final byVariant = <String, BlockGeometryMesh>{};
    final pending = <String, Future<BlockGeometryMesh?>>{};

    Future<BlockGeometryMesh?> geometryOf(String cacheKey, BlockstateVariant v) {
      return pending.putIfAbsent(cacheKey, () async {
        final parser = ModelGeometryParser((p) => _models.modelJson(p));
        final geo = await parser.parse(v.model.split(':').last);
        if (geo.isEmpty || geo.unsupportedRotation) return null;
        final rotation = BlockModelRotation.tryFromAngles(v.x, v.y, v.z,
            uvLock: v.uvlock);
        if (rotation == null) return null;
        return _toRenderGeometry(bakeBlockstateRotation(geo, rotation));
      });
    }

    for (final entry in kBlockStateIdentity262.entries) {
      final identity = entry.value;
      final variantKey = _variantKeyOfIdentity(identity);
      final name = BlockSemanticsV262.blockNameOfStateIdentity(identity);
      if (name.isEmpty || name == 'unknown') continue;
      final variant = await _models.variantFor(
        'minecraft:$name',
        variantKey,
      );
      if (variant == null) continue;
      final key = '${variant.model.split(':').last}'
          '|${variant.x}|${variant.y}|${variant.z}|${variant.uvlock}';
      final cached = byVariant[key];
      if (cached != null) {
        if (cached == BlockGeometryMesh.none) {
          rotationSkipped++;
        } else {
          result[entry.key] = cached;
        }
        continue;
      }
      final mesh = await geometryOf(key, variant);
      if (mesh == null) {
        // 无几何、或带 rotation（本网格器不支持旋转 ⇒ 显式回退整方块，
        // **MUST NOT 静默按未旋转渲染**，见 BlockGeometryMesh 文档）。
        byVariant[key] = BlockGeometryMesh.none;
        rotationSkipped++;
        continue;
      }
      byVariant[key] = mesh;
      result[entry.key] = mesh;
    }
    _geometryRotationSkipped = rotationSkipped;
    return result;
  }

  /// 因模型带 rotation 而未注入几何的方块数（`--dart-define=TRACE=true` 时打印，
  /// 让"这些方块仍是整方块"成为**可见事实**而非静默回退）。
  int _geometryRotationSkipped = 0;
  int get geometryRotationSkipped => _geometryRotationSkipped;

  /// `mc_resource` 的解析结果 → `mc_render` 的网格器契约（[BlockGeometryMesh]）。
  ///
  /// 两侧各有自己的类型（包纯度：`mc_render` 只依赖 `mc_nbt`，不依赖
  /// `mc_resource`），故在此转换。解析侧叫 `BlockGeometry`，网格器契约侧叫
  /// `BlockGeometryMesh`——刻意不同名，避免 app 壳同时 import 两个包时符号冲突。
  static BlockGeometryMesh _toRenderGeometry(BlockGeometry src) {
    if (src.isEmpty) return BlockGeometryMesh.none;
    return BlockGeometryMesh(
      boxes: src.boxes
          .map((b) => BoxGeometry(
                fromX: b.from.x,
                fromY: b.from.y,
                fromZ: b.from.z,
                toX: b.to.x,
                toY: b.to.y,
                toZ: b.to.z,
                faces: [
                  for (var i = 0; i < b.faces.length; i++)
                    BoxFace(
                      direction: b.faces[i],
                      u1: b.uvs[i].u1,
                      v1: b.uvs[i].v1,
                      u2: b.uvs[i].u2,
                      v2: b.uvs[i].v2,
                      // 模型纹理变量（`CuboidFace.texture`）：烘焙旋转时保持
                      // 不变（判据 CuboidFace.java:37），供 uvFor 直查。
                      texture: b.textures[i].isEmpty ? null : b.textures[i],
                    ),
                ],
              ))
          .toList(growable: false),
      hasUnsupportedRotation: src.unsupportedRotation,
    );
  }

  /// `minecraft:oak_slab[type=top]` → `type=top`（blockstate `variants` 的键）。
  ///
  /// 身份串的属性顺序按官方 data generator 的输出稳定，直接以原样作键查表；
  /// 查不到时 [BlockModels.variantFor] 会退回首变体。
  static String? _variantKeyOfIdentity(String identity) {
    final lb = identity.indexOf('[');
    final rb = identity.lastIndexOf(']');
    if (lb < 0 || rb <= lb) return null;
    return identity.substring(lb + 1, rb);
  }

  /// 资源包里全部方块名（来自 blockstates 目录清单）。
  ///
  /// [VanillaPack] 未暴露"列目录"，故用**已知方块清单**兜底：取自区块调色板
  /// 的 state身份串（`kBlockStateIdentity262`，官方 data generator 产物）。
  static Set<String> get _allBlockNames {
    final seen = <String>{};
    for (final identity in kBlockStateIdentity262.values) {
      final n = BlockSemanticsV262.blockNameOfStateIdentity(identity);
      if (n.isNotEmpty && n != 'unknown') seen.add(n);
    }
    return seen;
  }

  /// 后台解析一个方块名的模型（去重；完成后通知调用方重做 UV）。
  void _requestResolve(String name) {
    if (!_pending.add(name)) return;
    unawaited(_models.resolve('minecraft:$name').then((resolved) {
      _pending.remove(name);
      if (resolved == null) return;
      _byBlock[name] = resolved;
      _byState.clear(); // 让 stateId → 面键表 重查
      onResolved?.call();
    }).catchError((Object _) {
      _pending.remove(name);
    }));
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

  /// 贴图解析映射探针（`--dart-define=TRACE=true` 时生效）：去重打印前 40 条
  /// "方块名+面 → 贴图路径"，并统计兜底命中次数——用于定位"某些面渲染成错色"。
  static const bool _trace = bool.fromEnvironment('TRACE');
  final Set<String> _logged = {};
  int _fallbackHits = 0;

  /// 网格器注入点。**永不返回 null**（网格器签名非空），未知方块/缺贴图时兜底。
  ///
  /// [textureKey] 是该面的**模型纹理变量**（`CuboidFace.texture`，如 `all`/
  /// `side`/`top`）；非 null 时**直查**模型 `textures` 映射（判据 `ModelBakery`
  /// 的变量解析——纹理绑定跟随面而非朝向，blockstate 旋转后面方向变了、
  /// 变量不变），查不到再退按朝向的键链。
  UvRect uvFor(int stateId, BlockFace face, String? textureKey) {
    final name = BlockSemanticsV262.blockNameOf(stateId);
    final byKey = _byState.putIfAbsent(stateId, () {
      final known = _byBlock[name];
      // 没解析过：立刻返回兜底，并把它排进后台解析（完成后 onResolved 通知重做）。
      if (known == null) _requestResolve(name);
      return known;
    });
    if (byKey != null) {
      if (textureKey != null) {
        final direct = byKey[textureKey];
        if (direct != null) {
          final sprite = _atlas.sprite(direct);
          if (sprite != null) {
            return UvRect(sprite.minU, sprite.minV, sprite.maxU, sprite.maxV);
          }
        }
      }
      for (final key in _keysFor(face)) {
        final path = byKey[key];
        if (path == null) continue;
        final sprite = _atlas.sprite(path);
        if (sprite != null) {
          if (_trace && _logged.length < 40) {
            final key = '$name/${face.name}→$path';
            if (_logged.add(key)) {
              debugPrint('[TEXMAP] $key rect=(${sprite.x},${sprite.y},'
                  '${sprite.width}x${sprite.height}) '
                  'uv=(${sprite.minU.toStringAsFixed(4)},'
                  '${sprite.minV.toStringAsFixed(4)},'
                  '${sprite.maxU.toStringAsFixed(4)},'
                  '${sprite.maxV.toStringAsFixed(4)})');
            }
          }
          return UvRect(sprite.minU, sprite.minV, sprite.maxU, sprite.maxV);
        }
      }
    }
    _fallbackHits++;
    if (_trace && _fallbackHits <= 20) {
      debugPrint('[TEXMAP-MISS] ${BlockSemanticsV262.blockNameOf(stateId)}'
          '/${face.name} → 兜底（未收录或贴图不在图集）');
    }
    return _fallback;
  }

  /// 面 → 原版模型纹理键的**优先级链**。
  ///
  /// 原版 `BlockModel` 的键空间：立方体全用 `all`；分面用 `top`/`bottom`/`side`；
  /// 柱状方块（石英、原木端面）用 `end`；十字植物（矮草、花）用 `cross`。
  /// 逐级回退，是为了让各类模型都能取到一张说得过去的贴图。
  ///
  /// **`texture` 必须在链里**：`template_seagrass` / `template_kelp` 这类水草模型
  /// 只声明 `"textures": {"texture": "block/seagrass"}` 一个键（无 all/side/cross），
  /// 漏掉它会让整片水草回退到兜底矩形（石头）⇒ 渲染成青蓝灰的"冰柱"。
  /// 查证`models/block/seagrass.json`：parent=template_seagrass、textures.texture。
  static List<String> _keysFor(BlockFace face) => switch (face) {
        BlockFace.up => const ['top', 'up', 'end', 'all', 'side', 'texture'],
        BlockFace.down => const ['bottom', 'down', 'end', 'all', 'side', 'texture'],
        BlockFace.north ||
        BlockFace.south ||
        BlockFace.east ||
        BlockFace.west =>
          const [
            'side',
            'cross',
            'all',
            'end',
            'north',
            'south',
            'east',
            'west',
            'texture', // 水草/海带/藤蔓类模板的单键
          ],
      };
}
