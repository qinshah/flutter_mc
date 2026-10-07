import 'dart:convert';

import 'vanilla_pack.dart';

/// 方块状态 → 模型 → 面贴图路径的解析（原版
/// `client.resources.model` 的 blockstate 加载面对应物，纯 Dart）。
///
/// 首版范围（design D4）：支持 `variants` 形态；`multipart`（栅栏/连线类）
/// 降级取首个模型——已知简化，后续补全。
class BlockModels {
  BlockModels(this._pack);

  final VanillaPack _pack;

  /// 解析方块 id（形如 "minecraft:stone"）为 面键 → 贴图路径
  /// （键含 all/side/end 等原版键；值形如 "block/stone"，相对 textures/ 根）。
  /// 方块缺失或无可用模型返回 null。
  Future<Map<String, String>?> resolve(String blockId) async {
    final name = blockId.split(':').last;
    final stateText = await _pack.readString('blockstates/$name.json');
    if (stateText == null) return null;
    final state = jsonDecode(stateText) as Map<String, dynamic>;

    String? modelPath;
    final variants = state['variants'];
    if (variants is Map<String, dynamic>) {
      dynamic entry =
          variants.containsKey('') ? variants[''] : variants.values.first;
      if (entry is List) {
        // 同键多变体（随机权重等）：取首个（简化）。
        entry = entry.first;
      }
      modelPath = (entry as Map<String, dynamic>)['model'] as String?;
    } else if (state['multipart'] is List) {
      // 简化：multipart 取首个 apply 的模型（不按条件求值）。
      final parts = state['multipart'] as List;
      if (parts.isEmpty) return null;
      modelPath = (parts.first as Map<String, dynamic>)['apply']?['model'] as String?;
    }
    if (modelPath == null) return null;

    final textures = <String, String>{};
    await _collectModelTextures(modelPath, textures);
    return {
      for (final e in textures.entries)
        e.key: _stripNs(_interpolate(e.value, textures, 0)),
    };
  }

  /// 26.2 的模型/贴图引用带命名空间前缀（"minecraft:block/stone"）；
  /// 统一剥成包内相对路径（"block/stone"）。
  String _stripNs(String path) {
    final i = path.indexOf(':');
    return i >= 0 ? path.substring(i + 1) : path;
  }

  /// 26.2 的**十字面片模板**（jar 内共 88 个模型以此为 parent）。
  ///
  /// 判据来源：逐个读 `models/block/*.json` 的 `parent` 字段统计得出——
  ///   - `block/cross`（如 `kelp`/`kelp_plant`）
  ///   - `block/tinted_cross`（生物群系着色的十字，如 `short_grass`/`sugar_cane`）
  ///   - `block/template_seagrass`（海草，两片正交薄板）
  ///
  /// 三者的共同形态都是"两张（或四张）**零厚度薄面片**"，语义即十字面片，
  /// 与原版渲染层 `CUTOUT` 的处理一致。
  static const Set<String> crossTemplateParents = {
    'block/cross',
    'block/tinted_cross',
    'block/template_seagrass',
  };

  /// 读模型 JSON 原文（形如 `block/oak_slab_top`；缺失返回 null）。
  ///
  /// 给[ModelGeometryParser] 当数据源——解析器只认"按模型路径读 JSON"这一件事，
  /// 不需要知道资源包来源。
  Future<String?> modelJson(String modelPath) =>
      _pack.readString('models/${_stripNs(modelPath)}.json');

  /// 按 **state 变体**解析模型路径（形如 `block/oak_slab_top`）。
  ///
  /// [variantKey] 是 blockstate `variants` 的键（如 `type=top`）；传 null 时取
  /// 首个变体。半砖/楼梯这类**同一方块不同变体走不同模型**（几何也不同），
  /// 故几何解析必须按变体来，不能只取首个。
  ///
  /// 判据：`blockstates/*.json` 的 `variants` 结构（值可以是单模型或模型数组）。
  Future<String?> modelPathForVariant(String blockId, String? variantKey) async {
    final name = blockId.split(':').last;
    final stateText = await _pack.readString('blockstates/$name.json');
    if (stateText == null) return null;
    final state = jsonDecode(stateText) as Map<String, dynamic>;

    final variants = state['variants'];
    if (variants is Map<String, dynamic> && variants.isNotEmpty) {
      Object? entry;
      if (variantKey != null && variants.containsKey(variantKey)) {
        entry = variants[variantKey];
      } else {
        entry = variants.values.first;
      }
      return _modelOfVariantEntry(entry);
    }
    final multipart = state['multipart'];
    if (multipart is List && multipart.isNotEmpty) {
      final first = multipart.first;
      if (first is Map<String, dynamic>) return _modelOfVariantEntry(first);
    }
    return null;
  }

  /// `variants` 的值 → 模型路径（值可能是单模型对象或模型对象数组，取首个）。
  static String? _modelOfVariantEntry(Object? entry) {
    if (entry is Map<String, dynamic>) {
      final m = entry['model'];
      if (m is String) return m;
      if (m is List) {
        final first = m.whereType<Map<String, dynamic>>().toList();
        if (first.isNotEmpty) return first.first['model'] as String?;
      }
      final apply = entry['apply'];
      if (apply is Map<String, dynamic>) return _modelOfVariantEntry(apply);
    }
    return null;
  }

  /// 该方块的模型是否**十字面片**（cross）。
  ///
  /// **为什么用它替代手写名单**：原版把"方块 → 渲染层"的完整注册表放在
  /// `BlockRenderLayer`，该类已编译进客户端渲染库、`mc-sources` 中不存在
  /// （全树 grep 零命中）；而模型的 parent 链是可得的等价判据，且比手写名单
  /// 完备（新版本方块自动被覆盖）。
  Future<bool> isCrossModel(String blockId) async {
    final modelPath = await _resolveModelPath(blockId);
    if (modelPath == null) return false;
    return _hasCrossAncestor(modelPath, 0);
  }

  /// 沿 parent 链查是否命中 [crossTemplateParents]（子覆盖父）。
  Future<bool> _hasCrossAncestor(String modelPath, int depth) async {
    if (depth > 16) return false; // 防御：异常 parent 环
    final path = _stripNs(modelPath);
    if (crossTemplateParents.contains(path)) return true;
    final text = await _pack.readString('models/$path.json');
    if (text == null) return false;
    final parent = (jsonDecode(text) as Map<String, dynamic>)['parent'];
    if (parent is! String) return false;
    return _hasCrossAncestor(parent, depth + 1);
  }

  /// 从 blockstate 解析出模型路径（variants/multipart 两种形态取首个）。
  Future<String?> _resolveModelPath(String blockId) async {
    // 与 [resolve] 同口径：**剥掉命名空间**再拼 blockstates 路径
    // （`minecraft:short_grass` → `blockstates/short_grass.json`）。
    final name = blockId.split(':').last;
    final stateText = await _pack.readString('blockstates/$name.json');
    if (stateText == null) return null;
    final state = jsonDecode(stateText) as Map<String, dynamic>;
    final variants = state['variants'];
    if (variants is Map<String, dynamic> && variants.isNotEmpty) {
      final entry = variants.values.first;
      if (entry is Map<String, dynamic>) return entry['model'] as String?;
      final parts = (entry as List?)?.whereType<Map<String, dynamic>>().toList();
      if (parts != null && parts.isNotEmpty) {
        return parts.first['model'] as String?;
      }
    }
    final multipart = state['multipart'];
    if (multipart is List && multipart.isNotEmpty) {
      final first = multipart.first;
      if (first is Map<String, dynamic>) {
        final apply = first['apply'];
        if (apply is Map<String, dynamic>) {
          final one = apply['model'];
          if (one is String) return one;
          final many = (apply['model'] as List?)?.whereType<String>().toList();
          if (many != null && many.isNotEmpty) return many.first;
        }
      }
    }
    return null;
  }

  /// 沿 parent 链收集贴图映射（子覆盖父）。
  Future<void> _collectModelTextures(
    String modelPath,
    Map<String, String> out,
  ) async {
    final path = _stripNs(modelPath);
    if (path.startsWith('builtin/')) return;
    final text = await _pack.readString('models/$path.json');
    if (text == null) return;
    final model = jsonDecode(text) as Map<String, dynamic>;
    final parent = model['parent'];
    if (parent is String) {
      await _collectModelTextures(parent, out);
    }
    final textures = model['textures'];
    if (textures is Map<String, dynamic>) {
      textures.forEach((key, value) {
        if (value is String) out[key] = value;
      });
    }
  }

  String _interpolate(String value, Map<String, String> textures, int depth) {
    if (depth > 8 || !value.startsWith('#')) return value;
    final ref = textures[value.substring(1)];
    if (ref == null) return value;
    return _interpolate(ref, textures, depth + 1);
  }
}
