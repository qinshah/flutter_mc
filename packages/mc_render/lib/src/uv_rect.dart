/// 图集内一块矩形（UV 空间，左上原点）。（移植自 fscraft block_atlas_uv。）
class UvRect {
  final double minU, minV, maxU, maxV;

  const UvRect(this.minU, this.minV, this.maxU, this.maxV);

  double get width => maxU - minU;
  double get height => maxV - minV;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UvRect &&
          minU == other.minU &&
          minV == other.minV &&
          maxU == other.maxU &&
          maxV == other.maxV;

  @override
  int get hashCode => Object.hash(minU, minV, maxU, maxV);

  @override
  String toString() => 'UvRect($minU, $minV, $maxU, $maxV)';
}
