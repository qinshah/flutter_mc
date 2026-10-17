import 'dart:convert';
import 'dart:io';

import 'package:mc_resource/mc_resource.dart';
import 'package:test/test.dart';

/// blockstate 变体旋转烘焙的黄金值测试（判据 `FaceBakery.java` +
/// `BlockMath.java` + `Quadrant/OctahedralGroup`）。
///
/// 黄金值全部由原版变换**手算递推**得出（非"本实现的输出"）：
/// - uvlock 的 UV 变换 `m = getFaceTransformation(G, face).inverse()`
///   （`FaceBakery.java:85`）；
/// - 位置旋转 = 群作用绕块中心（`FaceBakery.java:136-138`）；
/// - 最终矩形按模板角绑定提取（`CuboidFace.java:77-83`）。
void main() {
  group('FaceBakery 烘焙黄金值', () {
    // 全格盒，只声明被测面（其余面不画，判据：只画模型声明的面）。
    // UV 取 k/16 二进小数（与原版模型一致：JSON uv 为 0..16 整数除 16），
    // 避免 double/float32 表示差干扰黄金值。
    ModelBox boxOf(String face) => ModelBox(
          from: (x: 0.0, y: 0.0, z: 0.0),
          to: (x: 1.0, y: 1.0, z: 1.0),
          faces: [face],
          uvs: const [
            (u1: 0.125, v1: 0.25, u2: 0.375, v2: 0.5),
          ],
          textures: ['side'],
          cullFaces: [null],
        );

    BlockGeometry bake(int x, int y, int z, String face, {bool uvlock = true}) {
      final rotation =
          BlockModelRotation.tryFromAngles(x, y, z, uvLock: uvlock)!;
      return bakeBlockstateRotation(
        BlockGeometry(boxes: [boxOf(face)], unsupportedRotation: false),
        rotation,
      );
    }

    test('y90 + south 面（uvlock）：面 → west，矩形不变（m=identity 短路）', () {
      final out = bake(0, 90, 0, 'south');
      expect(out.boxes.single.faces, ['west']);
      expect(out.boxes.single.uvs.single,
          const (u1: 0.125, v1: 0.25, u2: 0.375, v2: 0.5));
    });

    test('y90 + up 面（uvlock）：面不变，矩形 (0.5,0.125,0.75,0.375)'
        '（m=(1−v,u)）', () {
      final out = bake(0, 90, 0, 'up');
      expect(out.boxes.single.faces, ['up']);
      expect(out.boxes.single.uvs.single,
          const (u1: 0.5, v1: 0.125, u2: 0.75, v2: 0.375));
    });

    test('x180 + north 面（uvlock）：面 → south，矩形 (0.625,0.5,0.875,0.75)'
        '（m=(1−u,1−v)）', () {
      final out = bake(180, 0, 0, 'north');
      expect(out.boxes.single.faces, ['south']);
      expect(out.boxes.single.uvs.single,
          const (u1: 0.625, v1: 0.5, u2: 0.875, v2: 0.75));
    });

    test('y90 非 uvlock：UV 原样（NO_TRANSFORM，判据 ModelState.java:19-21）', () {
      final out = bake(0, 90, 0, 'south', uvlock: false);
      expect(out.boxes.single.faces, ['west']);
      expect(out.boxes.single.uvs.single,
          const (u1: 0.125, v1: 0.25, u2: 0.375, v2: 0.5));
    });

    test('转置情形：x90 + east 面（uvlock）—— u 随模板 cv 变，退化为包围矩形 '
        '(0.5,0.125,0.75,0.375)（翻译债：字段方向丢失）', () {
      final out = bake(90, 0, 0, 'east');
      expect(out.boxes.single.faces, ['east']);
      expect(out.boxes.single.uvs.single,
          const (u1: 0.5, v1: 0.125, u2: 0.75, v2: 0.375));
    });

    test('盒旋转：x180 把下半盒 (0,0,0)-(1,0.5,1) 翻成上半 (0,0.5,0)-(1,1,1)', () {
      final rotation = BlockModelRotation.tryFromAngles(180, 0, 0, uvLock: true)!;
      final out = bakeBlockstateRotation(
        BlockGeometry(
          boxes: [
            ModelBox(
              from: (x: 0.0, y: 0.0, z: 0.0),
              to: (x: 1.0, y: 0.5, z: 1.0),
              faces: ['up'],
              uvs: const [
                (u1: 0.0, v1: 0.0, u2: 1.0, v2: 1.0),
              ],
              textures: ['side'],
              cullFaces: [null],
            ),
          ],
          unsupportedRotation: false,
        ),
        rotation,
      );
      expect(out.boxes.single.from, (x: 0.0, y: 0.5, z: 0.0));
      expect(out.boxes.single.to, (x: 1.0, y: 1.0, z: 1.0));
    });
  });

  group('楼梯变体端到端（对照 blockstates/oak_stairs.json 旋转表）', () {
    late Directory tmp;
    late BlockModels models;
    late ModelGeometryParser parser;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('mc_face_bakery_test');
      void write(String rel, Object json) {
        final f = File('${tmp.path}/$rel')..createSync(recursive: true);
        f.writeAsStringSync(jsonEncode(json));
      }

      // 与原版 oak_stairs.json 同构（节选 straight 的四个朝向 + half=top）。
      write('blockstates/oak_stairs.json', {
        'variants': {
          'facing=east,half=bottom,shape=straight': {
            'model': 'block/oak_stairs'
          },
          'facing=south,half=bottom,shape=straight': {
            'model': 'block/oak_stairs',
            'y': 90,
            'uvlock': true,
          },
          'facing=north,half=bottom,shape=straight': {
            'model': 'block/oak_stairs',
            'y': 270,
            'uvlock': true,
          },
          'facing=east,half=top,shape=straight': {
            'model': 'block/oak_stairs',
            'x': 180,
            'uvlock': true,
          },
        },
      });
      // block/stairs 基准模型：底板整宽半高 + 踏步在东半（判据：基准朝向为东）。
      write('models/block/stairs.json', {
        'elements': [
          {
            'from': [0, 0, 0],
            'to': [16, 8, 16],
            'faces': {
              'north': {'texture': '#side', 'uv': [0, 8, 16, 16]},
            },
          },
          {
            'from': [8, 8, 0],
            'to': [16, 16, 16],
            'faces': {
              'up': {'texture': '#side', 'uv': [8, 0, 16, 16]},
            },
          },
        ],
      });
      write('models/block/oak_stairs.json', {
        'parent': 'block/stairs',
        'textures': {'side': 'block/oak_planks'},
      });
      models = BlockModels(VanillaPack.fromDirectory(tmp.path));
      parser = ModelGeometryParser(models.modelJson);
    });

    tearDown(() => tmp.deleteSync(recursive: true));

    Future<BlockGeometry> bakedStairs(String variantKey) async {
      final v = await models.variantFor('minecraft:oak_stairs', variantKey);
      final geo = await parser.parse(v!.model);
      return bakeBlockstateRotation(
        geo,
        BlockModelRotation.tryFromAngles(v.x, v.y, v.z, uvLock: v.uvlock)!,
      );
    }

    test('facing=south（y=90）：踏步落南半顶部', () async {
      final out = await bakedStairs('facing=south,half=bottom,shape=straight');
      final slab = out.boxes[0];
      final step = out.boxes[1];
      // 底板绕 y 轴旋转后不变（关于 y 轴对称）。
      expect(slab.from, (x: 0.0, y: 0.0, z: 0.0));
      expect(slab.to, (x: 1.0, y: 0.5, z: 1.0));
      // 踏步：东半 → 南半（y90 俯视顺时针 east→south），仍在上半。
      expect(step.from, (x: 0.0, y: 0.5, z: 0.5));
      expect(step.to, (x: 1.0, y: 1.0, z: 1.0));
      // 声明的面随群旋转：north → east（(0,0,−1)→(1,0,0)），up → up。
      expect(slab.faces, ['east']);
      expect(step.faces, ['up']);
    });

    test('half=top（x=180）：底板翻到上半，踏步翻到下半东侧', () async {
      final out = await bakedStairs('facing=east,half=top,shape=straight');
      final slab = out.boxes[0];
      final step = out.boxes[1];
      expect(slab.from, (x: 0.0, y: 0.5, z: 0.0));
      expect(slab.to, (x: 1.0, y: 1.0, z: 1.0));
      expect(step.from, (x: 0.5, y: 0.0, z: 0.0));
      expect(step.to, (x: 1.0, y: 0.5, z: 1.0));
      // north 面 → south（x180），up 面 → down。
      expect(slab.faces, ['south']);
      expect(step.faces, ['down']);
    });

    test('facing=east（无旋转）：uvlock 不改变几何与 UV', () async {
      final out = await bakedStairs('facing=east,half=bottom,shape=straight');
      // 踏步仍在东半顶部。
      expect(out.boxes[1].from, (x: 0.5, y: 0.5, z: 0.0));
      expect(out.boxes[1].to, (x: 1.0, y: 1.0, z: 1.0));
      expect(out.boxes[0].faces, ['north']);
    });
  });
}
