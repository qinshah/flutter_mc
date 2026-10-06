import 'dart:convert';
import 'dart:io';

import 'package:mc_resource/mc_resource.dart';
import 'package:test/test.dart';

void _writeFixture(Directory tmp, String rel, Object json) {
  final f = File('${tmp.path}/$rel')..createSync(recursive: true);
  f.writeAsStringSync(jsonEncode(json));
}

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mc_block_models_test');
    // 贴图变量经 parent 链两跳插值的最小夹具。
    _writeFixture(tmp, 'models/block/cube.json', {
      'textures': {
        'particle': '#all',
        'north': '#all',
        'south': '#all',
        'east': '#all',
        'west': '#all',
        'up': '#all',
        'down': '#all',
      },
    });
    _writeFixture(tmp, 'models/block/cube_all.json', {
      'parent': 'block/cube',
      'textures': {'all': '#all'},
    });
    _writeFixture(tmp, 'models/block/stone.json', {
      // 26.2 实测形态：引用带命名空间前缀。
      'parent': 'minecraft:block/cube_all',
      'textures': {'all': 'minecraft:block/stone'},
    });
    _writeFixture(tmp, 'blockstates/stone.json', {
      'variants': {
        '': [
          {'model': 'minecraft:block/stone'},
          {'model': 'minecraft:block/stone_mirrored'},
        ],
      },
    });
    // multipart 形态：降级取首个 apply 模型（design D4 已知简化）。
    _writeFixture(tmp, 'blockstates/oak_fence.json', {
      'multipart': [
        {'apply': {'model': 'block/stone'}},
      ],
    });
  });
  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  test('parent 链收集 + # 引用插值出最终贴图路径', () async {
    final models = BlockModels(VanillaPack.fromDirectory(tmp.path));
    final faces = await models.resolve('minecraft:stone');
    expect(faces, isNotNull);
    for (final face in ['north', 'south', 'east', 'west', 'up', 'down']) {
      expect(faces![face], 'block/stone', reason: face);
    }
    expect(faces!['particle'], 'block/stone');
  });

  test('子贴图覆盖父链', () async {
    _writeFixture(tmp, 'blockstates/oak_planks.json', {
      'variants': {
        '': {'model': 'block/oak_planks'},
      },
    });
    _writeFixture(tmp, 'models/block/oak_planks.json', {
      'parent': 'block/cube_all',
      'textures': {'all': 'block/oak_planks'},
    });
    final models = BlockModels(VanillaPack.fromDirectory(tmp.path));
    expect((await models.resolve('minecraft:oak_planks'))!['all'],
        'block/oak_planks');
  });

  test('multipart 降级取首个模型；缺失方块返回 null', () async {
    final models = BlockModels(VanillaPack.fromDirectory(tmp.path));
    expect((await models.resolve('minecraft:oak_fence'))!['all'],
        'block/stone');
    expect(await models.resolve('minecraft:missing_block'), isNull);
  });
}
