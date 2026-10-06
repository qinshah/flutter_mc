import 'package:flutter_scene/build_hooks.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
// flutter_scene:init:start
    // Import .glb and .fscene sources under assets/, loadable by source path
    // with loadScene (and hot-reloadable). A no-op when there are no scenes.
    buildScenes(buildInput: input, buildOutput: output);
    // Compile .fmat materials under assets/, loadable by source path with
    // loadFmatMaterial (and hot-reloadable). A no-op when there are none.
    await buildMaterials(buildInput: input, buildOutput: output);
    // 把 assets/ 下的散图 cook 成 .fstex（loadTexture 按源路径加载）。
    // 本项目的方块图集在 assets/vanilla/26_2/generated/block_atlas.png。
    buildTextures(
      buildInput: input,
      buildOutput: output,
      // 本项目的方块图集（构建期由 tool/extract_assets.dart 拼好）。
      textures: ['assets/vanilla/26_2/generated/block_atlas.png'],
    );
// flutter_scene:init:end
  });
}
