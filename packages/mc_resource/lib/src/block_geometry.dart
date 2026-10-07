/// 资源包模型的几何描述（判据：`net/minecraft.client.resources.model.cuboid.*`）。
///
/// ## 判据出处
///
/// - `CuboidModelElement.java:51-52` —— 模型 `elements[].from/to` 是 **0..16** 的整数坐标。
/// - `CuboidModelElement.java:143-148` —— 越界（<-16 或 >32）原版**抛异常**。
/// - `FaceBakery.java:131` —— 顶点输出时 `vertex.div(16.0F)`，即归一化到 0..1。
/// - `CuboidModelElement.java:114-118` —— `faces` 为空原版**抛异常**
///   （`Expected between 1 and 6 unique faces, got 0`）⇒ **只画模型声明的面**，
///   未声明的面原版不画（本实现 MUST NOT 自行补全）。
/// - `FaceBakery.java:44-47` —— 面的 `uv` 也在 0..16 空间，除 16 归一化到 0..1，
///   且先取 `min/max`（模型里允许 `uv` 起点大于终点，原版会规整）。
/// - `CuboidModelElement.java:22,28-29` —— `rotation` 可选；本实现见
///   [BlockGeometry.supportsRotation]。
///
/// 纯数据（无 flutter / flutter_scene 依赖），可在 worker isolate 使用。
library;

import 'dart:convert';

/// 一个模型元素（`elements[]` 的一项）的几何，坐标已归一化到 0..1。
///
/// [faces] 只含模型**显式声明**的面（判据见上）。[uvs] 与 [faces] 一一对应，
/// 顺序相同。
class ModelBox {
  ModelBox({
    required this.from,
    required this.to,
    required this.faces,
    required this.uvs,
    required this.textures,
    required this.cullFaces,
  });

  /// 左下角（0..1，相对方块）。
  final ({double x, double y, double z}) from;

  /// 右上角（0..1，相对方块）。
  final ({double x, double y, double z}) to;

  /// 该元素**显式声明**的面（顺序即发射顺序）：`'down'|'up'|'north'|'south'|'west'|'east'`。
  final List<String> faces;

  /// 每个面的 UV 矩形，已归一化到 0..1（`[u1, v1, u2, v2]`，min/max 规整过）。
  /// 与 [faces] 同序对应。
  final List<({double u1, double v1, double u2, double v2})> uvs;

  /// 每个面引用的**模型纹理键**（如 `'#all'`、`'#side'`、`'#top'`），
  /// 已去掉 `#` 前缀。与 [faces] 同序对应。
  ///
  /// 原版 `CuboidFace.texture` 存的是纹理**变量名**（`#all`），由
  /// `ModelBakery` 在烘焙时用 `textures` 映射解析成 `Sprite`。本实现把变量名
  /// 交给调用方的 `uvFor` 链路解析，语义一致。
  final List<String> textures;

  /// 该元素声明了 `cullface` 的面（判据：模型 JSON 里该面有 `"cullface"`）。
  /// 与 [faces] 同序对应；元素为 null 表示该面未声明 cullface。
  final List<String?> cullFaces;

  /// 该元素是否覆盖整格（`from=(0,0,0)`、`to=(1,1,1)`）。
  bool get isFullBlock =>
      from.x == 0.0 &&
      from.y == 0.0 &&
      from.z == 0.0 &&
      to.x == 1.0 &&
      to.y == 1.0 &&
      to.z == 1.0;
}

/// 一个方块模型的完整几何。
class BlockGeometry {
  const BlockGeometry({
    required this.boxes,
    required this.unsupportedRotation,
  });

  /// 空几何（方块没声明 `elements`，如 `block/block` 的纯立方体）。
  static const BlockGeometry empty =
      BlockGeometry(boxes: [], unsupportedRotation: false);

  /// 几何元素（0..1 归一化）。
  final List<ModelBox> boxes;

  /// 该模型链上是否存在 `elements[].rotation`。
  ///
  /// **本实现不支持 rotation**（判据见 [CuboidRotation] 与 `FaceBakery` 的旋转烘焙
  /// 路径，涉及 origin/axis/angle/rescale 与顶点绕原点重排，超出"逐 AABB 出面"范围）。
  /// 为 true 时调用方 MUST 显式处理（回退整方块或标记为债），
  /// **MUST NOT 静默按未旋转渲染**——那会产生与原版不同的错误几何。
  ///
  /// 26.2 的 343 个含 `elements` 的模型里有 95 个带 rotation（多为铁轨、
  /// 悬挂告示牌、作物、连节植物）。
  final bool unsupportedRotation;

  bool get isEmpty => boxes.isEmpty;

  /// 是否是"单个元素覆盖整格"——等价于整方块，可用旧的快速路径。
  bool get isSingleFullBlock =>
      boxes.length == 1 && boxes.first.isFullBlock;
}

/// 解析 `models/block/*.json` 的 `elements`（判据 `CuboidModelElement.java`）。
///
/// **为什么要有这一层**：原版把"方块→渲染层"与"方块→几何"都放在烘焙期的
/// `ModelBakery`/`FaceBakery` 里；本仓库的网格器（`mc_render`）不 import
/// `mc_resource`（包纯度要求：`mc_render` 只依赖 `mc_nbt`），因此几何数据必须
/// 由 app 壳在构建期解析好、经 `MeshSemantics` 注入网格器。
class ModelGeometryParser {
  ModelGeometryParser(this.readJson);

  /// 读取 `models/<path>.json` 的原文；缺失返回 null（契约同 `PackSource`）。
  final Future<String?> Function(String modelPath) readJson;

  /// 沿 parent 链解析几何。
  ///
  /// **parent 链语义**（判据 `ModelBakery` / `UnbakedCuboidGeometry`）：
  /// 模型的 `textures` 与 `elements` 都**沿 parent 链继承，子覆盖父**
  /// （`block/stairs` 提供 2 个 box，具体 `oak_stairs` 只改 `textures`）。
  /// 本实现取**首个声明 `elements` 的祖先**的 `elements`，并把链上所有 `textures`
  /// 合并（子优先）。
  ///
  /// `modelPath` 形如 `block/stairs`（已去命名空间）。
  Future<BlockGeometry> parse(String modelPath, {int depth = 0}) async {
    if (depth > 16) return BlockGeometry.empty; // 防御：异常 parent 环
    final text = await readJson(modelPath);
    if (text == null) return BlockGeometry.empty;

    final json = jsonDecode(text);
    if (json is! Map<String, dynamic>) return BlockGeometry.empty;

    final hasRotation =
        _elementsOf(json).any((e) => e is Map && e.containsKey('rotation'));

    final elements = _elementsOf(json);
    if (elements.isNotEmpty) {
      return BlockGeometry(
        boxes: elements
            .whereType<Map<String, dynamic>>()
            .map(_parseBox)
            .toList(growable: false),
        unsupportedRotation: hasRotation,
      );
    }
    // 本层无 elements ⇒ 沿 parent 链找（`oak_stairs` → `block/stairs`）。
    final parent = json['parent'];
    if (parent is! String || parent.isEmpty) return BlockGeometry.empty;
    return parse(_stripNamespace(parent), depth: depth + 1);
  }

  static List<dynamic> _elementsOf(Map<String, dynamic> json) {
    final els = json['elements'];
    return els is List ? els : const [];
  }

  ModelBox _parseBox(Map<String, dynamic> e) {
    final from = _triple(e['from']);
    final to = _triple(e['to']);
    final facesJson = e['faces'];
    final faces = <String>[];
    final uvs = <({double u1, double v1, double u2, double v2})>[];
    final textures = <String>[];
    final cullFaces = <String?>[];
    if (facesJson is Map<String, dynamic>) {
      for (final entry in facesJson.entries) {
        final name = entry.key.toLowerCase(); // 原版枚举名全小写
        if (!_allFaces.contains(name)) continue;
        final f = entry.value;
        if (f is! Map<String, dynamic>) continue;
        faces.add(name);
        uvs.add(_uvOf(f['uv']));
        final tex = f['texture'];
        final key = tex is String ? tex : '';
        // `#all` ⇒ `all`；`minecraft:block/x`（不经变量）原版也允许，原样保留。
        textures.add(key.startsWith('#') ? key.substring(1) : key);
        final cull = f['cullface'];
        cullFaces.add(cull is String ? cull.toLowerCase() : null);
      }
    }
    return ModelBox(
      from: from,
      to: to,
      faces: faces,
      uvs: uvs,
      textures: textures,
      cullFaces: cullFaces,
    );
  }

  /// 0..16 → 0..1（判据 `CuboidModelElement.java:143` 的边界 + `FaceBakery.java:131`
  /// 的 `div(16.0F)`）。
  static ({double x, double y, double z}) _triple(Object? raw) {
    if (raw is List && raw.length >= 3) {
      return (
        x: _norm(raw[0]),
        y: _norm(raw[1]),
        z: _norm(raw[2]),
      );
    }
    return (x: 0.0, y: 0.0, z: 0.0);
  }

  static double _norm(Object? v) {
    final d = v is num ? v.toDouble() : 0.0;
    return d / 16.0;
  }

  /// 面 UV → 0..1，且做 min/max 规整（判据 `FaceBakery.java:44-47` 用
  /// `Math.min/max(uvs.minU(), uvs.maxU())`）。
  static ({double u1, double v1, double u2, double v2}) _uvOf(Object? raw) {
    if (raw is List && raw.length >= 4) {
      final u1 = _norm(raw[0]);
      final v1 = _norm(raw[1]);
      final u2 = _norm(raw[2]);
      final v2 = _norm(raw[3]);
      return (
        u1: (u1 < u2 ? u1 : u2),
        v1: (v1 < v2 ? v1 : v2),
        u2: (u1 < u2 ? u2 : u1),
        v2: (v1 < v2 ? v2 : v1),
      );
    }
    return (u1: 0.0, v1: 0.0, u2: 1.0, v2: 1.0);
  }

  static const List<String> _allFaces = [
    'down',
    'up',
    'north',
    'south',
    'west',
    'east',
  ];

  static String _stripNamespace(String path) {
    final colon = path.indexOf(':');
    return colon >= 0 ? path.substring(colon + 1) : path;
  }
}