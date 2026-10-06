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
