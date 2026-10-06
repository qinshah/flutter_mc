import 'dart:typed_data';

/// 一个 16³ 段的网格数据（移植自 fscraft mesher，输出形状与其一致）。
///
/// **纯数据、可跨 isolate**：只有 `TypedData`，没有任何 GPU 类型。
/// 顶点位置已是**引擎空间**（世界 z 已取反，见 mesher.dart 的手性说明）。
class ChunkMeshData {
  ChunkMeshData({
    required this.positions,
    required this.normals,
    required this.texCoords,
    required this.colors,
    required this.indices,
    required this.bounds,
  });

  final Float32List positions; // 3/顶点（段内局部坐标，引擎空间）
  final Float32List normals; // 3/顶点
  final Float32List texCoords; // 2/顶点
  final Float32List colors; // 4/顶点（面朝向明暗，RGBA）
  final Uint32List indices; // 三角形索引
  final List<double> bounds; // [minX,minY,minZ,maxX,maxY,maxZ]（引擎空间）

  int get vertexCount => positions.length ~/ 3;
  int get triangleCount => indices.length ~/ 3;
  bool get isEmpty => indices.isEmpty;

  static ChunkMeshData empty() => ChunkMeshData(
        positions: Float32List(0),
        normals: Float32List(0),
        texCoords: Float32List(0),
        colors: Float32List(0),
        indices: Uint32List(0),
        bounds: const [0, 0, 0, 0, 0, 0],
      );
}

/// 一个段的网格化结果：按渲染层分开（无面的层为 null）。
class ChunkMesh {
  const ChunkMesh({this.opaque, this.cutout, this.translucent});

  final ChunkMeshData? opaque;
  final ChunkMeshData? cutout;
  final ChunkMeshData? translucent;

  bool get isEmpty =>
      (opaque?.isEmpty ?? true) &&
      (cutout?.isEmpty ?? true) &&
      (translucent?.isEmpty ?? true);
}

/// 渲染层（序号口径与语义表一致：0 opaque / 1 cutout / 2 translucent）。
enum RenderLayer { opaque, cutout, translucent }
