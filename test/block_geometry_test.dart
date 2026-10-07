import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mc_render/mc_render.dart';
// 两侧各有几何类型（解析侧 `BlockGeometry` / 网格契约侧 `BlockGeometryMesh`），
// 用前缀区分解析侧。
import 'package:mc_resource/mc_resource.dart' as res;

/// 方块几何黄金值测试（判据 `CuboidModelElement` / `FaceBakery`）。
///
/// 断言两端都取自原版：
/// - **解析侧**：`mc_resource.ModelGeometryParser` 从jar 内模型 JSON 解析出的AABB
///   等于模型 `elements[].from/to` 除 16（`FaceBakery.java:131` 的 `div(16.0F)`）。
/// - **网格侧**：`meshSection` 按该 AABB 出面，而不是一律整方块。
///
/// 若资源包缺失（未跑 `tool/extract_assets.dart`）则跳过——资产不入库是红线，
/// 测试不应依赖构建产物存在。
class FakeSection implements SectionView {
  FakeSection([Map<int, int>? blocks]) : _blocks = blocks ?? {};
  final Map<int, int> _blocks;
  int _at(int x, int y, int z) => _blocks[(x << 8) | (y << 4) | z] ?? 0;
  void set(int x, int y, int z, int state) =>
      _blocks[(x << 8) | (y << 4) | z] = state;
  @override
  int stateAt(int lx, int ly, int lz) => _at(lx, ly, lz);
  @override
  bool get isEmpty => _blocks.isEmpty;
}

const String _assetRoot = 'assets/vanilla/26_2';

bool get _hasAssets => Directory('$_assetRoot/models/block').existsSync();

res.ModelGeometryParser? _parser() {
  if (!_hasAssets) return null;
  return res.ModelGeometryParser((modelPath) async {
    final f = File('$_assetRoot/models/$modelPath.json');
    return f.existsSync() ? f.readAsStringSync() : null;
  });
}

/// 解析侧 → 网格契约侧的转换（app 壳 `BlockTextures._toRenderGeometry` 的等价物）。
BlockGeometryMesh toMeshGeometry(res.BlockGeometry src) {
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
                  ),
              ],
            ))
        .toList(growable: false),
    hasUnsupportedRotation: src.unsupportedRotation,
  );
}

UvRect _uv(int stateId, BlockFace face) => const UvRect(0, 0, 1, 1);

/// 用给定几何网格化单个方块，返回非空层的数据。
ChunkMeshData meshOne(BlockGeometryMesh geometry, {int state = 1}) {
  final semantics = BlockSemanticsV262(geometryByState: {state: geometry});
  final section = FakeSection()..set(0, 0, 0, state);
  final mesh = meshSection(
    section,
    const SectionNeighbors(),
    semantics: MeshSemanticsCache(semantics),
    uvFor: _uv,
  );
  return mesh.opaque ?? mesh.cutout ?? mesh.translucent!;
}

BoxGeometry _box({
  required double x0,
  required double y0,
  required double z0,
  required double x1,
  required double y1,
  required double z1,
  List<String>? faces,
}) =>
    BoxGeometry(
      fromX: x0,
      fromY: y0,
      fromZ: z0,
      toX: x1,
      toY: y1,
      toZ: z1,
      faces: [
        for (final f in faces ??
            const ['down', 'up', 'north', 'south', 'west', 'east'])
          BoxFace(direction: f, u1: 0, v1: 0, u2: 1, v2: 1),
      ],
    );

void main() {
  group('几何解析（判据 CuboidModelElement / FaceBakery）', () {
    test('竹子：from[7,0,7] to[9,16,9] ⇒ 归一化 0.4375..0.5625 细柱', () async {
      final p = _parser()!;
      final g = await p.parse('block/bamboo1_age0');
      expect(g.boxes, hasLength(1));
      final b = g.boxes.single;
      // 7/16 = 0.4375、9/16 = 0.5625（FaceBakery.java:131 的 div(16.0F)）
      expect(b.from.x, closeTo(7 / 16, 1e-9));
      expect(b.from.z, closeTo(7 / 16, 1e-9));
      expect(b.to.x, closeTo(9 / 16, 1e-9));
      expect(b.to.z, closeTo(9 / 16, 1e-9));
      expect(b.to.y, 1.0);
      expect(b.faces,
          containsAll(<String>['down', 'up', 'north', 'south', 'west', 'east']));
      expect(g.unsupportedRotation, isFalse);
    }, skip: !_hasAssets);

    test('半砖：to.y = 8 ⇒ 归一化 0.5（只下半格）', () async {
      final p = _parser()!;
      final g = await p.parse('block/slab');
      expect(g.boxes, hasLength(1));
      final b = g.boxes.single;
      expect(b.from.y, 0.0);
      expect(b.to.y, closeTo(0.5, 1e-9));
      expect(b.from.x, 0.0);
      expect(b.to.x, 1.0);
    }, skip: !_hasAssets);

    test('楼梯：2 个 box（底层半高 + 上层半宽）', () async {
      final p = _parser()!;
      final g = await p.parse('block/stairs');
      expect(g.boxes, hasLength(2));
      expect(g.boxes[0].to.y, closeTo(0.5, 1e-9));
      expect(g.boxes[1].from.y, closeTo(0.5, 1e-9));
      expect(g.boxes[1].to.y, 1.0);
      expect(g.boxes[1].from.x, closeTo(0.5, 1e-9));
      // 上层 box 没有 down 面（原版不画被遮挡的面）
      expect(g.boxes[1].faces, isNot(contains('down')));
    }, skip: !_hasAssets);

    test('子模型沿 parent 链继承几何（oak_stairs → block/stairs）', () async {
      final p = _parser()!;
      // `models/block/oak_stairs.json` 只声明 parent 与 textures，
      // 几何必须从 `block/stairs` 模板继承。
      final g = await p.parse('block/oak_stairs');
      expect(g.boxes, hasLength(2));
      expect(g.boxes[0].to.y, closeTo(0.5, 1e-9));
    }, skip: !_hasAssets);

    test('rotation 被显式标记（cross 的 45° 斜面）', () async {
      final p = _parser()!;
      // `models/block/cross.json` 的 elements 带 rotation{angle:45}。
      // 本实现不支持旋转 ⇒ MUST 标记，而不是静默按未旋转渲染。
      final g = await p.parse('block/cross');
      expect(g.unsupportedRotation, isTrue);
    }, skip: !_hasAssets);

    test('普通整方块被识别为 singleFullBlock（走快速路径）', () async {
      final p = _parser()!;
      expect((await p.parse('block/stone')).isSingleFullBlock, isTrue);
    }, skip: !_hasAssets);
  });

  group('网格化：按真实 AABB 出面', () {
    test('竹子细柱：bounds 不再覆盖整格', () {
      final data = meshOne(BlockGeometryMesh(
        boxes: [
          _box(
              x0: 7 / 16,
              y0: 0,
              z0: 7 / 16,
              x1: 9 / 16,
              y1: 1,
              z1: 9 / 16),
        ],
        hasUnsupportedRotation: false,
      ));
      // 整方块时 bounds 是 [0,0,-1, 1,1,0]；细柱应只占格中央 2/16。
      expect(data.bounds[0], closeTo(7 / 16, 1e-6));
      expect(data.bounds[3], closeTo(9 / 16, 1e-6));
      expect(data.bounds[1], 0.0);
      expect(data.bounds[4], 1.0);
    });

    test('半砖：只覆盖下半格，6 面 24 顶点', () {
      final data = meshOne(BlockGeometryMesh(
        boxes: [_box(x0: 0, y0: 0, z0: 0, x1: 1, y1: 0.5, z1: 1)],
        hasUnsupportedRotation: false,
      ));
      expect(data.vertexCount, 24, reason: '6 面 × 4 角');
      expect(data.bounds[1], 0.0);
      expect(data.bounds[4], closeTo(0.5, 1e-6));
    });

    test('楼梯：2 个 box ⇒ 11 个面 44 顶点（底层 6 + 上层 5）', () {
      // 上层 box 未声明 down 面（判据：原版不画被遮挡的面）。
      final data = meshOne(BlockGeometryMesh(
        boxes: [
          _box(x0: 0, y0: 0, z0: 0, x1: 1, y1: 0.5, z1: 1),
          _box(
            x0: 0.5,
            y0: 0.5,
            z0: 0,
            x1: 1,
            y1: 1,
            z1: 1,
            faces: const ['up', 'north', 'south', 'east', 'west'],
          ),
        ],
        hasUnsupportedRotation: false,
      ));
      expect(data.vertexCount, (6 + 5) * 4);
      expect(data.bounds[4], 1.0);
    });

    test('藤蔓：只画 north/south 两面（零厚度薄板）', () {
      final data = meshOne(BlockGeometryMesh(
        boxes: [
          _box(
            x0: 0,
            y0: 0,
            z0: 0.05,
            x1: 1,
            y1: 1,
            z1: 0.05,
            faces: const ['north', 'south'],
          ),
        ],
        hasUnsupportedRotation: false,
      ));
      expect(data.vertexCount, 8, reason: '只 2 面 × 4 角');
      // 零厚度 ⇒ z 坐标恒定
      final zs = <double>{};
      for (var i = 0; i < data.vertexCount; i++) {
        zs.add(data.positions[i * 3 + 2]);
      }
      expect(zs.length, 1);
    });

    test('模型的局部 UV 被映射进 sprite 子矩形', () {
      // 面 UV 只占贴图左半（u:0..0.5）⇒ 顶点 u 应落在 sprite 的左半。
      // 用**非整格** box：单 box 覆盖整格时走旧的整方块路径（不含局部 UV）。
      final data = meshOne(BlockGeometryMesh(
        boxes: [
          BoxGeometry(
            fromX: 0.25,
            fromY: 0,
            fromZ: 0.25,
            toX: 0.75,
            toY: 1,
            toZ: 0.75,
            faces: const [
              BoxFace(direction: 'up', u1: 0, v1: 0, u2: 0.5, v2: 0.5),
            ],
          ),
        ],
        hasUnsupportedRotation: false,
      ));
      final us = <double>{};
      for (var i = 0; i < data.vertexCount; i++) {
        us.add(data.texCoords[i * 2]);
      }
      for (final u in us) {
        expect(u, inInclusiveRange(0.0, 0.5));
      }
    });

    test('带 rotation 的几何回退整方块（不静默按未旋转渲染）', () {
      final thin = BlockGeometryMesh(
        boxes: [
          _box(
              x0: 0.4375,
              y0: 0,
              z0: 0.4375,
              x1: 0.5625,
              y1: 1,
              z1: 0.5625),
        ],
        hasUnsupportedRotation: true,
      );
      final data = meshOne(thin);
      // 回退整方块 ⇒ bounds 覆盖整格（而不是细柱的 7/16..9/16）
      expect(data.bounds[0], 0.0);
      expect(data.bounds[3], 1.0);
    });

    test('单 box 覆盖整格时走旧整方块路径（行为等价）', () {
      final full = BlockGeometryMesh(
        boxes: [_box(x0: 0, y0: 0, z0: 0, x1: 1, y1: 1, z1: 1)],
        hasUnsupportedRotation: false,
      );
      final data = meshOne(full);
      expect(data.vertexCount, 24);
      expect(data.bounds, [0, 0, -1, 1, 1, 0]);
    });
  });
}