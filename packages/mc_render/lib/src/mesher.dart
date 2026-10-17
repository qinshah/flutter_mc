import 'dart:typed_data';

import 'block_geometry_mesh.dart';
import 'chunk_mesh_data.dart';
import 'mesh_semantics.dart';
import 'uv_rect.dart';

/// 网格化器（移植自 fscraft `voxel/mesher.dart`，语义与 UV 改为注入式）。
///
/// 数据面与原版判据：MC 世界右手系 → flutter_scene 左手系（顶点 z 取反）、
/// 绕序反向发射（flutter_scene 0.23+ 顺时针为正面）、面朝向明暗（顶1.0/底0.5/
/// 南北0.8/东西0.6）、UV 按面翻回 z 镜像。
///
/// ## 几何：按模型 `elements` 出面（判据 `CuboidModelElement` / `FaceBakery`）
///
/// 方块若注入了真实几何（[MeshSemantics.geometryOf]），按其 AABB 逐面发射——
/// **只画模型 `faces` 声明的面**（判据 `CuboidModelElement.java:114-118`：
/// `faces` 为空原版抛异常，未声明的面不画）。竹子（2×16×2 细柱）、半砖
/// （下半格）、楼梯（2~3 个 box）、藤蔓（零厚度薄板）、睡莲（贴地薄片）
/// 因此不再被拉成整方块。
///
/// **仍未支持**（MUST NOT 静默按未旋转渲染，见 [BlockGeometryMesh.hasUnsupportedRotation]）：
/// 带 `rotation` 的 95 个模型（铁轨、告示牌、作物等）回退整方块。
///
/// ## 仍存在的简化
///
/// 无 AO / 平滑光照 / lightmap（见 `openspec/progress.md`）；
/// 流体族内部面剔除按"同名流体"近似。
///
/// 纯计算：不 import flutter_scene，可在 worker isolate 运行。

/// 网格化器读取方块用的段视图（段内局部坐标 0..15）。
abstract interface class SectionView {
  int stateAt(int lx, int ly, int lz);
  bool get isEmpty;
}

/// 面朝向。
enum BlockFace { east, west, north, south, up, down }

/// 相邻段（缺省=未加载，按空气处理：不画内表面）。
class SectionNeighbors {
  const SectionNeighbors({
    this.negX,
    this.posX,
    this.negY,
    this.posY,
    this.negZ,
    this.posZ,
  });

  final SectionView? negX, posX, negY, posY, negZ, posZ;
}

enum _UvFlip { none, u, v }

const Map<BlockFace, _UvFlip> _uvFlip = {
  BlockFace.up: _UvFlip.v,
  BlockFace.down: _UvFlip.v,
  BlockFace.east: _UvFlip.u,
  BlockFace.west: _UvFlip.u,
  BlockFace.north: _UvFlip.none,
  BlockFace.south: _UvFlip.none,
};

double _mirrorZ(num z) => z == 0 ? 0.0 : -z.toDouble();

double _shadeFor(BlockFace face) => switch (face) {
      BlockFace.up => 1.0,
      BlockFace.down => 0.5,
      BlockFace.north || BlockFace.south => 0.8,
      BlockFace.east || BlockFace.west => 0.6,
    };

/// 单面 4 角：[x, y, z, u, v]（世界右手系，法线朝外，逆时针）。
const Map<BlockFace, List<List<double>>> _corners = {
  BlockFace.east: [
    [1, 0, 1, 1, 1],
    [1, 0, 0, 0, 1],
    [1, 1, 0, 0, 0],
    [1, 1, 1, 1, 0],
  ],
  BlockFace.west: [
    [0, 0, 0, 0, 1],
    [0, 0, 1, 1, 1],
    [0, 1, 1, 1, 0],
    [0, 1, 0, 0, 0],
  ],
  BlockFace.up: [
    [0, 1, 1, 0, 1],
    [1, 1, 1, 1, 1],
    [1, 1, 0, 1, 0],
    [0, 1, 0, 0, 0],
  ],
  BlockFace.down: [
    [0, 0, 0, 0, 1],
    [1, 0, 0, 1, 1],
    [1, 0, 1, 1, 0],
    [0, 0, 1, 0, 0],
  ],
  BlockFace.south: [
    [0, 0, 1, 0, 1],
    [1, 0, 1, 1, 1],
    [1, 1, 1, 1, 0],
    [0, 1, 1, 0, 0],
  ],
  BlockFace.north: [
    [1, 0, 0, 1, 1],
    [0, 0, 0, 0, 1],
    [0, 1, 0, 0, 0],
    [1, 1, 0, 1, 0],
  ],
};

const Map<BlockFace, List<int>> _offsets = {
  BlockFace.east: [1, 0, 0],
  BlockFace.west: [-1, 0, 0],
  BlockFace.up: [0, 1, 0],
  BlockFace.down: [0, -1, 0],
  BlockFace.south: [0, 0, 1],
  BlockFace.north: [0, 0, -1],
};

const List<BlockFace> _allFaces = [
  BlockFace.east,
  BlockFace.west,
  BlockFace.north,
  BlockFace.south,
  BlockFace.up,
  BlockFace.down,
];

/// [uvFor]：stateId+面 → 图集 UV 矩形（十字植物用 side 面语义由调用方处理）。
ChunkMesh meshSection(
  SectionView section,
  SectionNeighbors neighbors, {
  required MeshSemantics semantics,
  required UvRect Function(int stateId, BlockFace face, String? textureKey) uvFor,
}) {
  if (section.isEmpty) return const ChunkMesh();

  final builders = <RenderLayer, _LayerBuilder>{};

  int neighborState(int lx, int ly, int lz, BlockFace face) {
    final o = _offsets[face]!;
    final nx = lx + o[0];
    final ny = ly + o[1];
    final nz = lz + o[2];
    if (nx >= 0 && nx < 16 && ny >= 0 && ny < 16 && nz >= 0 && nz < 16) {
      return section.stateAt(nx, ny, nz);
    }
    return _neighborStateOf(neighbors, lx, ly, lz, nx, ny, nz);
  }

  for (var ly = 0; ly < 16; ly++) {
    for (var lz = 0; lz < 16; lz++) {
      for (var lx = 0; lx < 16; lx++) {
        final state = section.stateAt(lx, ly, lz);
        if (state == 0) continue; // 内部 id 空间不变量：0 = 空
        final isCross = semantics.isCross(state);
        final layer = RenderLayer.values[semantics.layerIndexOf(state)];

        if (isCross) {
          _emitCross(builders, layer, semantics, state, lx, ly, lz, uvFor);
          continue;
        }

        // 真实几何路径（判据 `CuboidModelElement.java:22` + `FaceBakery.java:131`）。
        // 有几何且不是"单 box 覆盖整格"时按 AABB 出面；带 rotation 的模型回退整方块
        // （MUST NOT 静默按未旋转渲染，见 BlockGeometryMesh 文档）。
        final geometry = semantics.geometryOf(state);
        if (!geometry.isNone &&
            !geometry.isSingleFullBlock &&
            !geometry.hasUnsupportedRotation) {
          _emitBoxes(
            builders,
            layer,
            state,
            geometry,
            lx,
            ly,
            lz,
            uvFor,
          );
          continue;
        }

        for (final face in _allFaces) {
          final nState = neighborState(lx, ly, lz, face);
          if (nState == state) continue;
          if (semantics.hidesNeighbors(nState)) continue;
          // 流体族内部面剔除（同名流体近似，见文件头简化点）。
          if (layer == RenderLayer.translucent &&
              RenderLayer.values[semantics.layerIndexOf(nState)] ==
                  RenderLayer.translucent &&
              _fluidFamily(semantics.nameOf(state)) ==
                  _fluidFamily(semantics.nameOf(nState))) {
            continue;
          }
          _emitFace(builders, layer, semantics, state, face, lx, ly, lz, uvFor);
        }
      }
    }
  }

  ChunkMeshData? take(RenderLayer layer) => builders[layer]?.build();
  return ChunkMesh(
    opaque: take(RenderLayer.opaque),
    cutout: take(RenderLayer.cutout),
    translucent: take(RenderLayer.translucent),
  );
}

String _fluidFamily(String name) =>
    name.startsWith('flowing_') ? name.substring('flowing_'.length) : name;

int _neighborStateOf(SectionNeighbors neighbors, int lx, int ly, int lz,
    int nx, int ny, int nz) {
  SectionView? col;
  int sx = lx, sy = ly, sz = lz;
  if (ny < 0) {
    col = neighbors.negY;
    sy = -1;
  } else if (ny > 15) {
    col = neighbors.posY;
    sy = 16;
  } else if (nx < 0) {
    col = neighbors.negX;
    sx = -1;
  } else if (nx > 15) {
    col = neighbors.posX;
    sx = 16;
  } else if (nz < 0) {
    col = neighbors.negZ;
    sz = -1;
  } else if (nz > 15) {
    col = neighbors.posZ;
    sz = 16;
  }
  if (col == null) return 0;
  final cx = sx == -1 ? 15 : (sx == 16 ? 0 : sx.clamp(0, 15));
  final cy = sy == -1 ? 15 : (sy == 16 ? 0 : sy.clamp(0, 15));
  final cz = sz == -1 ? 15 : (sz == 16 ? 0 : sz.clamp(0, 15));
  return col.stateAt(cx, cy, cz);
}

class _LayerBuilder {
  static const int _initialVertices = 256;

  Float32List _positions = Float32List(_initialVertices * 3);
  Float32List _normals = Float32List(_initialVertices * 3);
  Float32List _texCoords = Float32List(_initialVertices * 2);
  Float32List _colors = Float32List(_initialVertices * 4);
  Uint32List _indices = Uint32List(_initialVertices * 6);

  int _vertexCount = 0;
  int _indexCount = 0;

  int get vertexCount => _vertexCount;

  var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity, maxZ = -double.infinity;

  void addVertex(double x, double y, double z, double nx, double ny, double nz,
      double u, double v, double shade) {
    if (_vertexCount * 3 >= _positions.length) _grow();
    final p = _vertexCount * 3;
    _positions[p] = x;
    _positions[p + 1] = y;
    _positions[p + 2] = z;
    _normals[p] = nx;
    _normals[p + 1] = ny;
    _normals[p + 2] = nz;
    final t = _vertexCount * 2;
    _texCoords[t] = u;
    _texCoords[t + 1] = v;
    final c = _vertexCount * 4;
    _colors[c] = shade;
    _colors[c + 1] = shade;
    _colors[c + 2] = shade;
    _colors[c + 3] = 1.0;
    if (x < minX) minX = x;
    if (y < minY) minY = y;
    if (z < minZ) minZ = z;
    if (x > maxX) maxX = x;
    if (y > maxY) maxY = y;
    if (z > maxZ) maxZ = z;
    _vertexCount++;
  }

  /// 绕序 2,1,0 / 3,2,0（相对顶点书写顺序即**顺时针**）。
  ///
  /// **别被下面注释里的"逆时针"误导**：引擎正面判定看的是**外法线方向**
  /// （`gl.frontFace(CCW)`，判据见下），而`_corners` 的顶点顺序 + `_mirrorZ`
  /// 镜像共同决定了实际绕序。已用纯几何实证：对 6 个面 × 4 种索引序算
  /// `cross(b-a, c-a) · 外法线`，本实现发射的`2,1,0`/`3,2,0` **六面 dot 全为
  /// +1（正面）**；若改成 `0,1,2`/`0,2,3` 则六面全为 −1（背面，会被剔除）。
  ///
  /// 判据：flutter_scene 0.24 `GeometryBuilder.addTriangle` 的文档——
  /// "Vertices must be specified in Counter-Clockwise (CCW) order around the
  /// outward-facing normal, matching the glTF and engine front-face convention"。
  ///
  /// 早先按 fscraft（flutter_scene **0.23**）的"顺时针为正面"额外反向发射成
  /// 2,1,0 / 3,2,0；但 z 镜像本身已经翻转过一次绕序，再反一次等于没反——
  /// 实拍表现就是方块面反向（near face 被剔除、看到的是背面/内壁）。
  void addQuadIndices(int base) {
    if (_indexCount + 6 > _indices.length) {
      _indices = _resizeU(_indices, _indices.length * 2);
    }
    final i = _indexCount;
    _indices[i] = base + 2;
    _indices[i + 1] = base + 1;
    _indices[i + 2] = base;
    _indices[i + 3] = base + 3;
    _indices[i + 4] = base + 2;
    _indices[i + 5] = base;
    _indexCount += 6;
  }

  void _grow() {
    final next = _positions.length ~/ 3 * 2;
    _positions = _resizeF(_positions, next * 3);
    _normals = _resizeF(_normals, next * 3);
    _texCoords = _resizeF(_texCoords, next * 2);
    _colors = _resizeF(_colors, next * 4);
    _indices = _resizeU(_indices, next * 6);
  }

  static Float32List _resizeF(Float32List src, int length) {
    final out = Float32List(length);
    out.setRange(0, src.length, src);
    return out;
  }

  static Uint32List _resizeU(Uint32List src, int length) {
    final out = Uint32List(length);
    out.setRange(0, src.length, src);
    return out;
  }

  ChunkMeshData? build() {
    if (_indexCount == 0) return null;
    return ChunkMeshData(
      positions: Float32List.sublistView(_positions, 0, _vertexCount * 3),
      normals: Float32List.sublistView(_normals, 0, _vertexCount * 3),
      texCoords: Float32List.sublistView(_texCoords, 0, _vertexCount * 2),
      colors: Float32List.sublistView(_colors, 0, _vertexCount * 4),
      indices: Uint32List.sublistView(_indices, 0, _indexCount),
      bounds: [minX, minY, minZ, maxX, maxY, maxZ],
    );
  }
}

/// 面贴图选择（原版 `BlockFaces` 口径：上/下取 top/bottom，侧面统一 side）
/// 由 `uvFor` 注入方负责——网格器只把 `(stateId, face)` 原样转交
/// （整方块路径无纹理变量来源，textureKey 传 null）。
void _emitFace(
  Map<RenderLayer, _LayerBuilder> builders,
  RenderLayer layer,
  MeshSemantics semantics,
  int state,
  BlockFace face,
  int lx,
  int ly,
  int lz,
  UvRect Function(int stateId, BlockFace face, String? textureKey) uvFor,
) {
  final builder = builders.putIfAbsent(layer, _LayerBuilder.new);
  final uv = uvFor(state, face, null);
  final shade = _shadeFor(face);
  final offset = _offsets[face]!;
  final corners = _corners[face]!;
  final flip = _uvFlip[face]!;

  final base = builder.vertexCount;
  for (final corner in corners) {
    final cu = flip == _UvFlip.u ? 1.0 - corner[3] : corner[3];
    final cv = flip == _UvFlip.v ? 1.0 - corner[4] : corner[4];
    final u = uv.minU + (uv.maxU - uv.minU) * cu;
    // 纹理 v 轴朝下（图集左上原点）：网格 y 增大 → v 减小
    final v = uv.minV + (uv.maxV - uv.minV) * cv;
    builder.addVertex(
      lx + corner[0],
      ly + corner[1],
      _mirrorZ(lz + corner[2]),
      offset[0].toDouble(),
      offset[1].toDouble(),
      _mirrorZ(offset[2]),
      u,
      v,
      shade,
    );
  }
  builder.addQuadIndices(base);
}

/// 按模型 `elements` 的 AABB 逐面发射（判据 `CuboidModelElement.java:22`
/// 的 `from`/`to` + `faces` 表；坐标已由解析侧除 16 归一化，同
/// `FaceBakery.java:131` 的 `div(16.0F)`）。
///
/// **只画 `faces` 声明的面**（判据 `CuboidModelElement.java:114-118`：`faces`
/// 为空原版抛异常；未声明的面原版不画）。藤蔓只声明 `north`/`south`、
/// 睡莲只声明 `down`/`up`，照此执行。
///
/// UV：模型的局部 UV（已归一化到 0..1 相对该面贴图）按
/// [uvFor] 给出的 sprite 矩形**取子矩形**——判据 `FaceBakery.java:40-49`
/// 同样是把 `CuboidFace.UVs`（0..16）÷16 后再按 sprite 尺寸映射。
void _emitBoxes(
  Map<RenderLayer, _LayerBuilder> builders,
  RenderLayer layer,
  int state,
  BlockGeometryMesh geometry,
  int lx,
  int ly,
  int lz,
  UvRect Function(int stateId, BlockFace face, String? textureKey) uvFor,
) {
  final builder = builders.putIfAbsent(layer, _LayerBuilder.new);
  for (final box in geometry.boxes) {
    for (final face in box.faces) {
      final dir = _faceByName(face.direction);
      // 模型未声明的面已在解析侧过滤；这里再兜一层，避免脏数据落到 _faceByName
      // 的 null 分支后静默画错面。
      if (dir == null) continue;
      // 纹理变量优先（判据 CuboidFace.java:37：texture 是面的属性，不随
      // blockstate 旋转改变）；null 时由 uvFor 退回按朝向的键链。
      final sprite = uvFor(state, dir, face.texture);
      final shade = _shadeFor(dir);

      // 该面在 box 上的 4 个角（世界右手系，法线朝外，逆时针），格式与
      // `_corners` 一致：`[x, y, z, u, v]`。u/v 是**面内归一化**坐标
      // （0..1），再按 face.uv 取 sprite 子矩形。
      final corners = _boxCorners(box, dir);
      final base = builder.vertexCount;
      for (final c in corners) {
        // 面的局部 UV 矩形（0..1，相对整张贴图）。
        final lu = face.u1 + (face.u2 - face.u1) * c[3];
        final lv = face.v1 + (face.v2 - face.v1) * c[4];
        // 映射进 sprite 的子矩形。纹理 v 轴朝下（图集左上原点）：局部 v 增大
        // 对应图集 v 增大，与 `_emitFace` 的 `cv` 语义一致（此处不做翻转，
        // 因为模型 UV 的 v 已是"从上往下"的原版口径）。
        builder.addVertex(
          lx + c[0],
          ly + c[1],
          _mirrorZ(lz + c[2]),
          _offsets[dir]![0].toDouble(),
          _offsets[dir]![1].toDouble(),
          _mirrorZ(_offsets[dir]![2]),
          sprite.minU + sprite.width * lu,
          sprite.minV + sprite.height * lv,
          shade,
        );
      }
      builder.addQuadIndices(base);
    }
  }
}

/// 名字 → [BlockFace]（几何侧用字符串，见 `BoxFace.direction` 的说明）。
BlockFace? _faceByName(String name) => switch (name) {
      'down' => BlockFace.down,
      'up' => BlockFace.up,
      'north' => BlockFace.north,
      'south' => BlockFace.south,
      'west' => BlockFace.west,
      'east' => BlockFace.east,
      _ => null,
    };

/// 一个 box 在某面上的 4 角：`[x, y, z, u, v]`，v 向下为 0（贴图原点在左上）。
///
/// 与 [_corners] 的差别：位置来自 box 的 `from`/`to` 而非整格 0/1；
/// u/v 的排布沿用整格的约定（与 `_emitFace` 的 `_uvFlip` 配合保持一致观感）。
List<List<double>> _boxCorners(BoxGeometry box, BlockFace dir) {
  final x0 = box.fromX, y0 = box.fromY, z0 = box.fromZ;
  final x1 = box.toX, y1 = box.toY, z1 = box.toZ;
  return switch (dir) {
    // 东面（+X）：由 z 从大到小、y 从小到大，右手系外法线 +X。
    BlockFace.east => [
        [x1, y0, z1, 1, 1],
        [x1, y0, z0, 0, 1],
        [x1, y1, z0, 0, 0],
        [x1, y1, z1, 1, 0],
      ],
    BlockFace.west => [
        [x0, y0, z0, 0, 1],
        [x0, y0, z1, 1, 1],
        [x0, y1, z1, 1, 0],
        [x0, y1, z0, 0, 0],
      ],
    BlockFace.up => [
        [x0, y1, z1, 0, 1],
        [x1, y1, z1, 1, 1],
        [x1, y1, z0, 1, 0],
        [x0, y1, z0, 0, 0],
      ],
    BlockFace.down => [
        [x0, y0, z0, 0, 1],
        [x1, y0, z0, 1, 1],
        [x1, y0, z1, 1, 0],
        [x0, y0, z1, 0, 0],
      ],
    BlockFace.south => [
        [x0, y0, z1, 0, 1],
        [x1, y0, z1, 1, 1],
        [x1, y1, z1, 1, 0],
        [x0, y1, z1, 0, 0],
      ],
    BlockFace.north => [
        [x1, y0, z0, 1, 1],
        [x0, y0, z0, 0, 1],
        [x0, y1, z0, 0, 0],
        [x1, y1, z0, 1, 0],
      ],
  };
}

void _emitCross(
  Map<RenderLayer, _LayerBuilder> builders,
  RenderLayer layer,
  MeshSemantics semantics,
  int state,
  int lx,
  int ly,
  int lz,
  UvRect Function(int stateId, BlockFace face, String? textureKey) uvFor,
) {
  final builder = builders.putIfAbsent(layer, _LayerBuilder.new);
  final uv = uvFor(state, BlockFace.north, null); // 十字植物取侧面语义
  const shade = 1.0;

  void quad(List<List<double>> corners, List<double> normal) {
    final base = builder.vertexCount;
    for (final c in corners) {
      final u = uv.minU + (uv.maxU - uv.minU) * (1.0 - c[3]);
      final v = uv.minV + (uv.maxV - uv.minV) * c[4];
      builder.addVertex(
        lx + c[0],
        ly + c[1],
        _mirrorZ(lz + c[2]),
        normal[0],
        normal[1],
        _mirrorZ(normal[2]),
        u,
        v,
        shade,
      );
    }
    builder.addQuadIndices(base);
  }

  quad(
    const [
      [0, 0, 0, 0, 1],
      [1, 0, 1, 1, 1],
      [1, 1, 1, 1, 0],
      [0, 1, 0, 0, 0],
    ],
    const [0.7071067811865476, 0, -0.7071067811865476],
  );
  quad(
    const [
      [1, 0, 0, 1, 1],
      [0, 0, 1, 0, 1],
      [0, 1, 1, 0, 0],
      [1, 1, 0, 1, 0],
    ],
    const [0.7071067811865476, 0, 0.7071067811865476],
  );
}
