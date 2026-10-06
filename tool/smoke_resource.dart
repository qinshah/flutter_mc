// ignore_for_file: avoid_print
// 冒烟：对真实提取产物读取图集清单与一个 blockstate（resource-pipeline 任务 3.2）。
import 'dart:convert';
import 'package:mc_resource/mc_resource.dart';

Future<void> main() async {
  final pack = VanillaPack.fromDirectory('assets/vanilla/26_2');
  final atlasText = await pack.readString('generated/atlas.json');
  final atlas = jsonDecode(atlasText!) as Map<String, dynamic>;
  final textures = atlas['textures'] as Map<String, dynamic>;
  print('atlas: ${atlas['size']} textures=${textures.length}');
  print('stone rect: ${textures['block/stone']}');

  final models = BlockModels(pack);
  for (final id in ['minecraft:stone', 'minecraft:oak_planks', 'minecraft:grass_block']) {
    final faces = await models.resolve(id);
    print('$id => ${faces == null ? '缺失' : faces['up']} (共 ${faces?.length} 键)');
  }
}
