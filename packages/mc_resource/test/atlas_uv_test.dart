import 'dart:io';

import 'package:mc_resource/mc_resource.dart';
import 'package:test/test.dart';

/// 内联小夹具（hermetic）：不依赖 `assets/vanilla/26_2/generated/atlas.json`
/// 这个被 gitignore 的真实产物。
const String _fixtureJson = '''
{
  "size": [32, 64],
  "textures": {
    "block/stone": {"x": 0, "y": 0, "w": 16, "h": 16},
    "block/dirt": {"x": 16, "y": 0, "w": 16, "h": 16},
    "block/oak_leaves": {"x": 0, "y": 16, "w": 32, "h": 48},
    "block/zero_width": {"x": 0, "y": 32, "w": 0, "h": 16},
    "block/missing_fields": {"x": 0},
    "block/out_of_bounds": {"x": 20, "y": 60, "w": 16, "h": 16},
    "block/not_object": 7
  }
}
''';

void main() {
  group('AtlasSprite：像素矩形 → [0,1] UV（左上原点，v 向下）', () {
    test('非零 x/y、非 16×16 的矩形精确换算', () {
      final s = AtlasSprite.fromPixels(
        x: 112,
        y: 304,
        width: 32,
        height: 48,
        atlasWidth: 256,
        atlasHeight: 2048,
      );
      // 精确值（二进制可表示，故等值断言而非 closeTo）。
      expect(s.minU, 112 / 256);
      expect(s.maxU, 144 / 256);
      expect(s.minV, 304 / 2048);
      expect(s.maxV, 352 / 2048);
      expect(s.minU, 0.4375);
      expect(s.maxU, 0.5625);
      expect(s.minV, 0.1484375);
      expect(s.maxV, 0.171875);
      // 像素矩形原样保留。
      expect([s.x, s.y, s.width, s.height], [112, 304, 32, 48]);
    });

    test('原点贴图 minU/minV 为 0；整幅贴图 UV 覆盖满区', () {
      final corner = AtlasSprite.fromPixels(
        x: 0,
        y: 0,
        width: 16,
        height: 16,
        atlasWidth: 256,
        atlasHeight: 2048,
      );
      expect(corner.minU, 0.0);
      expect(corner.minV, 0.0);
      expect(corner.maxU, 16 / 256);
      expect(corner.maxV, 16 / 2048);

      final whole = AtlasSprite.fromPixels(
        x: 0,
        y: 0,
        width: 32,
        height: 64,
        atlasWidth: 32,
        atlasHeight: 64,
      );
      expect([whole.minU, whole.minV, whole.maxU, whole.maxV], [0.0, 0.0, 1.0, 1.0]);
    });

    test('v 向下增长：y 越大 minV 越大（图集顶边为 v=0）', () {
      final top = AtlasSprite.fromPixels(
        x: 0, y: 0, width: 16, height: 16, atlasWidth: 32, atlasHeight: 64);
      final bottom = AtlasSprite.fromPixels(
        x: 0, y: 48, width: 16, height: 16, atlasWidth: 32, atlasHeight: 64);
      expect(top.minV, 0.0);
      expect(bottom.minV, 0.75);
      expect(bottom.minV, greaterThan(top.minV));
    });
  });

  group('BlockAtlas.parse', () {
    test('正常清单：图集尺寸与各矩形可查', () {
      final atlas = BlockAtlas.parse(_fixtureJson);
      expect(atlas, isNotNull);
      expect(atlas!.width, 32);
      expect(atlas.height, 64);

      final stone = atlas.sprite('block/stone')!;
      expect([stone.x, stone.y, stone.width, stone.height], [0, 0, 16, 16]);
      expect([stone.minU, stone.minV, stone.maxU, stone.maxV],
          [0.0, 0.0, 16 / 32, 16 / 64]);

      final dirt = atlas.sprite('block/dirt')!;
      expect(dirt.minU, 16 / 32);
      expect(dirt.maxU, 32 / 32);

      final leaves = atlas.sprite('block/oak_leaves')!;
      expect([leaves.width, leaves.height], [32, 48]);
      expect([leaves.minU, leaves.minV, leaves.maxU, leaves.maxV],
          [0.0, 16 / 64, 1.0, 64 / 64]);
    });

    test('未收录贴图返回 null', () {
      final atlas = BlockAtlas.parse(_fixtureJson)!;
      expect(atlas.sprite('block/netherite_block'), isNull);
      expect(atlas.sprite('item/diamond'), isNull);
      expect(atlas.sprite(''), isNull);
    });

    test('查询容忍命名空间前缀（与 BlockModels 输出取向一致）', () {
      final atlas = BlockAtlas.parse(_fixtureJson)!;
      final stone = atlas.sprite('minecraft:block/stone')!;
      expect([stone.x, stone.y], [0, 0]);
    });

    test('畸形条目被跳过，其余条目保留', () {
      final atlas = BlockAtlas.parse(_fixtureJson)!;
      // 夹具 7 条中 3 条有效，其余为畸形（零宽 / 缺字段 / 越界 / 非对象）。
      expect(atlas.spriteCount, 3);
      expect(atlas.texturePaths,
          containsAll(<String>['block/stone', 'block/dirt', 'block/oak_leaves']));
      expect(atlas.sprite('block/zero_width'), isNull);
      expect(atlas.sprite('block/missing_fields'), isNull);
      expect(atlas.sprite('block/out_of_bounds'), isNull);
      expect(atlas.sprite('block/not_object'), isNull);
    });

    test('条目缺 h 只跳过该条（清单仍可用）', () {
      final atlas = BlockAtlas.parse(
        '{"size": [32, 64], "textures": {'
        '"block/stone": {"x": 0, "y": 0, "w": 16, "h": 16},'
        '"block/no_height": {"x": 0, "y": 0, "w": 16}}}',
      );
      expect(atlas, isNotNull);
      expect(atlas!.spriteCount, 1);
      expect(atlas.sprite('block/stone'), isNotNull);
      expect(atlas.sprite('block/no_height'), isNull);
    });

    for (final bad in <String>[
      'not json at all',
      '[]',
      '[1, 2]',
      '"just a string"',
      'null',
      '{"textures": {}}',
      '{"size": [32, 64]}',
      '{"size": [32], "textures": {}}',
      '{"size": [32, 64, 3], "textures": {}}',
      '{"size": ["32", 64], "textures": {}}',
      '{"size": [0, 64], "textures": {}}',
      '{"size": [32, -64], "textures": {}}',
      '{"size": [32, 64], "textures": []}',
      '{"size": [32, 64], "textures": "nope"}',
      '{"size": [32, 64], "textures": null}',
    ]) {
      test('坏 JSON / 缺键返回 null：${bad.length > 40 ? '${bad.substring(0, 40)}…' : bad}', () {
        expect(BlockAtlas.parse(bad), isNull);
      });
    }

    test('坏条目全部畸形时仍返回空图集而非 null（尺寸有效）', () {
      final atlas = BlockAtlas.parse(
        '{"size": [32, 64], "textures": {"block/x": {"x": 0, "y": 0, "w": 40, "h": 16}}}',
      );
      expect(atlas, isNotNull);
      expect(atlas!.spriteCount, 0);
      expect(atlas.sprite('block/x'), isNull);
    });
  });

  group('BlockAtlas.load（PackSource 便捷入口）', () {
    late Directory tmp;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('mc_atlas_uv_test');
      final f = File('${tmp.path}/${BlockAtlas.defaultPath}')
        ..createSync(recursive: true);
      f.writeAsStringSync(_fixtureJson);
    });
    tearDown(() {
      tmp.deleteSync(recursive: true);
    });

    test('DirectoryPackSource 读 generated/atlas.json', () async {
      final source = DirectoryPackSource(tmp);
      final atlas = await BlockAtlas.load(source);
      expect(atlas, isNotNull);
      expect(atlas!.width, 32);
      expect(atlas.sprite('block/stone')!.maxU, 0.5);
      // 同一目录经 VanillaPack 读也一致（路径约定 = 资源包根相对）。
      final viaPack = await BlockAtlas.load(VanillaPack.fromDirectory(tmp.path).source);
      expect(viaPack!.spriteCount, 3);
    });

    test('文件缺失返回 null（不抛异常）', () async {
      final missing = Directory('${tmp.path}/nope');
      expect(await BlockAtlas.load(DirectoryPackSource(missing)), isNull);
    });

    test('文件内容坏 JSON 返回 null（不抛异常）', () async {
      File('${tmp.path}/${BlockAtlas.defaultPath}')
          .writeAsStringSync('{ broken');
      expect(await BlockAtlas.load(DirectoryPackSource(tmp)), isNull);
    });

    test('CallbackPackSource（app 壳注入）同样可用', () async {
      final seen = <String>[];
      final source = CallbackPackSource((path) async {
        seen.add(path);
        return path == BlockAtlas.defaultPath
            ? File('${tmp.path}/$path').readAsBytesSync()
            : null;
      });
      final atlas = await BlockAtlas.load(source);
      expect(seen, [BlockAtlas.defaultPath]);
      expect(atlas!.sprite('block/dirt')!.minU, 0.5);
    });
  });

  test('真实提取产物：存在时才校验（该目录 gitignore，CI 上不存在）', () {
    final candidates = <String>[
      '../../assets/vanilla/26_2/generated/atlas.json',
      'assets/vanilla/26_2/generated/atlas.json',
    ];
    File? real;
    for (final c in candidates) {
      final f = File(c);
      if (f.existsSync()) {
        real = f;
        break;
      }
    }
    if (real == null) return; // 产物不在本机，跳过。

    final atlas = BlockAtlas.parse(real.readAsStringSync());
    expect(atlas, isNotNull, reason: '真实清单必须可解析');
    expect(atlas!.width, 256);
    expect(atlas.height, 2048);
    expect(atlas.spriteCount, greaterThan(1000));
    // block/stone 的 x/y 取决于拼接顺序（按名排序，不以 stone 开头），只校验尺寸。
    final stone = atlas.sprite('block/stone')!;
    expect([stone.width, stone.height], [16, 16]);
    expect(stone.maxU - stone.minU, 16 / 256);
    expect(stone.maxV - stone.minV, 16 / 2048);
    for (final path in atlas.texturePaths) {
      final s = atlas.sprite(path)!;
      expect(s.x >= 0 && s.y >= 0 && s.x + s.width <= atlas.width &&
          s.y + s.height <= atlas.height, isTrue, reason: path);
    }
  });
}
