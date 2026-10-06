import 'dart:typed_data';

import 'package:mc_render/mc_render.dart';
import 'package:test/test.dart';

/// 测试用段视图：Map 填充的 16³。
class FakeSection implements SectionView {
  FakeSection([Map<int, int>? blocks]) : _blocks = blocks ?? {};
  final Map<int, int> _blocks; // key = (x<<8) | (y<<4) | z
  int _at(int x, int y, int z) => _blocks[(x << 8) | (y << 4) | z] ?? 0;
  void set(int x, int y, int z, int state) => _blocks[(x << 8) | (y << 4) | z] = state;
  @override
  int stateAt(int lx, int ly, int lz) => _at(lx, ly, lz);
  @override
  bool get isEmpty => _blocks.isEmpty;
}

const _semantics = BlockSemanticsV262();

UvRect _uv(int stateId, BlockFace face) => const UvRect(0, 0, 1, 1);

void main() {
  test('单元块：24 顶点 36 索引，z 镜像与明暗正确', () {
    final section = FakeSection()..set(0, 0, 0, 1); // 1 = stone
    final mesh = meshSection(section, const SectionNeighbors(),
        semantics: _semantics, uvFor: _uv);

    final opaque = mesh.opaque!;
    expect(opaque.vertexCount, 24);
    expect(opaque.triangleCount, 12);
    // 东面（+X）第一角：世界 (1,0,1) → 引擎 z 镜像 → (1,0,-1)。
    expect(opaque.positions.sublist(0, 3), [1.0, 0.0, -1.0]);
    // 法线：+X 朝向（z 分量镜像对 +X 无影响）。
    expect(opaque.normals.sublist(0, 3), [1.0, 0.0, 0.0]);
    // 明暗：东面 0.6。
    expect(opaque.colors[0], closeTo(0.6, 1e-6));
    // 绕序：逆时针为正面（flutter_scene 0.24 约定），前三索引 0,1,2。
    expect(opaque.indices.sublist(0, 3), [0, 1, 2]);
    // bounds 覆盖整块（z 镜像：-1..0）。
    expect(opaque.bounds, [0, 0, -1, 1, 1, 0]);
  });

  test('相邻同面剔除：两块石头只出 10 个面', () {
    final section = FakeSection()
      ..set(0, 0, 0, 1)
      ..set(1, 0, 0, 1);
    final mesh = meshSection(section, const SectionNeighbors(),
        semantics: _semantics, uvFor: _uv);
    expect(mesh.opaque!.vertexCount, 40); // 10 面 × 4
  });

  test('邻居段：西侧列有石头则本段西面被剔', () {
    final section = FakeSection()..set(0, 0, 0, 1);
    final west = FakeSection()..set(15, 0, 0, 1);
    final withNeighbor = meshSection(
      section,
      const SectionNeighbors(),
      semantics: _semantics,
      uvFor: _uv,
    );
    final culled = meshSection(
      section,
      SectionNeighbors(negX: west),
      semantics: _semantics,
      uvFor: _uv,
    );
    expect(withNeighbor.opaque!.vertexCount, 24);
    expect(culled.opaque!.vertexCount, 20); // 西面被剔
  });

  test('水进 translucent 层且不遮挡邻居', () {
    // 从状态表找一个 water 状态。
    final waterState = kBlockStateIdentity262.entries
        .firstWhere((e) => e.value.startsWith('minecraft:water'))
        .key;
    final section = FakeSection()
      ..set(0, 0, 0, 1)
      ..set(1, 0, 0, waterState);
    final mesh = meshSection(section, const SectionNeighbors(),
        semantics: _semantics, uvFor: _uv);
    expect(mesh.opaque, isNotNull); // 石头仍在 opaque
    expect(mesh.translucent, isNotNull); // 水在 translucent
    // 水不遮挡邻居 → 石头 6 面全画；水与石头相邻面也画。
    expect(mesh.opaque!.vertexCount, 24);
    expect(mesh.translucent!.vertexCount, greaterThanOrEqualTo(4));
  });

  test('十字植物：2 片对角面片 8 顶点，cutout 层', () {
    final grassState = kBlockStateIdentity262.entries
        .firstWhere((e) => e.value.startsWith('minecraft:short_grass'))
        .key;
    final section = FakeSection()..set(0, 0, 0, grassState);
    final mesh = meshSection(section, const SectionNeighbors(),
        semantics: _semantics, uvFor: _uv);
    expect(mesh.opaque ?? ChunkMeshData.empty().isEmpty, true);
    final cutout = mesh.cutout!;
    expect(cutout.vertexCount, 8);
    expect(cutout.triangleCount, 4);
  });

  test('索引不越界（golden 守卫）', () {
    final section = FakeSection();
    final rnd = Uint32List(16 * 16 * 4);
    for (var i = 0; i < rnd.length; i++) {
      rnd[i] = (i * 2654435761) % 32366;
    }
    var n = 0;
    for (var y = 0; y < 4; y++) {
      for (var z = 0; z < 16; z++) {
        for (var x = 0; x < 16; x++) {
          final s = rnd[n++];
          if (s != 0) section.set(x, y, z, s);
        }
      }
    }
    final mesh = meshSection(section, const SectionNeighbors(),
        semantics: _semantics, uvFor: _uv);
    for (final data in [mesh.opaque, mesh.cutout, mesh.translucent]) {
      if (data == null) continue;
      for (final index in data.indices) {
        expect(index, lessThan(data.vertexCount));
      }
    }
  });

  test('UV 快照：UV 由注入的面→矩形函数决定，翻轴按面修正', () {
    // 各面给互不相同的矩形，锁住「取哪个面」与「矩形→顶点」两步映射。
    UvRect uvByFace(int stateId, BlockFace face) => switch (face) {
          BlockFace.east || BlockFace.west => const UvRect(0.5, 0.0, 0.75, 0.25),
          BlockFace.north || BlockFace.south => const UvRect(0.75, 0.0, 1.0, 0.25),
          BlockFace.up => const UvRect(0.0, 0.0, 0.25, 0.25),
          BlockFace.down => const UvRect(0.25, 0.0, 0.5, 0.25),
        };

    final mesh = meshSection(FakeSection()..set(0, 0, 0, 1),
        const SectionNeighbors(), semantics: _semantics, uvFor: uvByFace);
    final uv = mesh.opaque!.texCoords;

    // 发射顺序固定 east/west/north/south/up/down，每面 4 顶点 × (u,v)。
    // 东面 flip=u：角点 u 依次 1,0,0,1 → 翻成 0,1,1,0，映到矩形 0.5..0.75。
    expect(uv.sublist(0, 8), [0.5, 0.25, 0.75, 0.25, 0.75, 0.0, 0.5, 0.0]);
    // 顶面（第 5 面，顶点 16..19）flip=v：角点 v 依次 1,1,0,0 → 翻成 0,0,1,1。
    expect(uv.sublist(32, 40), [0.0, 0.0, 0.25, 0.0, 0.25, 0.25, 0.0, 0.25]);
  });

  test('UV 注入契约：网格器把 (stateId, 面) 原样转交，单块问六个面各一次', () {
    final asked = <(int, BlockFace)>[];
    meshSection(FakeSection()..set(0, 0, 0, 1), const SectionNeighbors(),
        semantics: _semantics, uvFor: (stateId, face) {
      asked.add((stateId, face));
      return const UvRect(0, 0, 1, 1);
    });

    expect(asked, hasLength(6));
    expect(asked.map((e) => e.$2).toSet(), BlockFace.values.toSet());
    expect(asked.every((e) => e.$1 == 1), isTrue);
  });

  test('竖直邻居用段内局部坐标：本段 y=15 顶面查 posY 段的 y=0', () {
    final section = FakeSection()..set(0, 15, 0, 1);
    final above = FakeSection()..set(0, 0, 0, 1);

    final culled = meshSection(section, SectionNeighbors(posY: above),
        semantics: _semantics, uvFor: _uv);
    expect(culled.opaque!.vertexCount, 20); // 顶面被剔
  });

  test('竖直邻居用段内局部坐标：本段 y=0 底面查 negY 段的 y=15', () {
    final section = FakeSection()..set(0, 0, 0, 1);
    final below = FakeSection()..set(0, 15, 0, 1);

    final culled = meshSection(section, SectionNeighbors(negY: below),
        semantics: _semantics, uvFor: _uv);
    expect(culled.opaque!.vertexCount, 20); // 底面被剔
  });

  test('流体同族剔除：相邻 water 的不同 level（state 不同）之间不出内表面', () {
    // 26.2 无 flowing_* 方块：水是单一 block + 16 个 level state，
    // 「同族」靠方块名相等判定（见 mesher 文件头简化点）。
    final water0 = kBlockStateIdentity262.entries
        .firstWhere((e) => e.value.startsWith('minecraft:water[level=0]'))
        .key;
    final water1 = kBlockStateIdentity262.entries
        .firstWhere((e) => e.value.startsWith('minecraft:water[level=1]'))
        .key;
    expect(water0, isNot(water1));

    final lone = meshSection(
        FakeSection()..set(0, 0, 0, water0),
        const SectionNeighbors(),
        semantics: _semantics,
        uvFor: _uv);
    final pair = meshSection(
        FakeSection()
          ..set(0, 0, 0, water0)
          ..set(1, 0, 0, water1),
        const SectionNeighbors(),
        semantics: _semantics,
        uvFor: _uv);

    expect(lone.translucent!.vertexCount, 24); // 单块 6 面
    expect(pair.translucent!.vertexCount, 40); // 两块 10 面（共享面被剔）
  });
}
