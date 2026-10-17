import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:mc_render/mc_render.dart';

import 'block_textures.dart';

/// 方块图标：图集 sprite 采样（stateId 顶面 UV）。
///
/// 供热键栏/创造物品栏等 HUD 复用（图集资产与 [BlockTextures.atlasAssetPath]
/// 同源；未解析方块显示兜底 UV——`uvFor` 会触发后台解析，解析完成重绘即正确）。
class BlockIcon extends StatefulWidget {
  const BlockIcon({
    super.key,
    required this.stateId,
    required this.textures,
    this.size = 16,
  });

  final int stateId;
  final BlockTextures? textures;
  final double size;

  @override
  State<BlockIcon> createState() => _BlockIconState();
}

class _BlockIconState extends State<BlockIcon> {
  static ui.Image? _cachedAtlas;

  @override
  void initState() {
    super.initState();
    _loadAtlas();
  }

  Future<void> _loadAtlas() async {
    if (_cachedAtlas != null) return;
    final provider = AssetImage(BlockTextures.atlasAssetPath);
    final stream = provider.resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      _cachedAtlas = info.image;
      if (mounted) setState(() {});
      stream.removeListener(listener);
    });
    stream.addListener(listener);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: CustomPaint(
        painter: _SpritePainter(
          atlas: _cachedAtlas,
          uv: widget.textures?.uvFor(widget.stateId, BlockFace.up, null),
        ),
      ),
    );
  }
}

/// 图集采样绘制（NEAREST 采样，像素风放大不糊）。
class _SpritePainter extends CustomPainter {
  _SpritePainter({required this.atlas, required this.uv});

  final ui.Image? atlas;
  final UvRect? uv;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()..filterQuality = FilterQuality.none;
    final image = atlas;
    if (image == null || uv == null) {
      canvas.drawRect(rect, paint..color = const Color(0xFF44444E));
      return;
    }
    final src = Rect.fromLTWH(
      uv!.minU * image.width,
      uv!.minV * image.height,
      uv!.width * image.width,
      uv!.height * image.height,
    );
    canvas.drawImageRect(image, src, rect, paint);
  }

  @override
  bool shouldRepaint(covariant _SpritePainter old) =>
      old.atlas != atlas || old.uv != uv;
}
