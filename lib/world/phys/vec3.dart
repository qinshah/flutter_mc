/// `net/minecraft/world/phys/Vec3.java` 的 Dart 对应物（逐行翻译）。
///
/// **不可变 + double**：原版字段是 `public final double x/y/z`（:41-43），
/// 实体换位置走整体替换（`Entity.setPos`），不做原地 set。这一点是
/// 2026-10-11 贴墙卡死修复的根：此前 `Player.position` 用 vector_math 的
/// `Vector3`（**float32** 存储），|x| > 64 后 ulp ≥ 4e-6 ≫ 碰撞容差 1e-7，
/// 贴面静止的盒会被舍入到墙内（微穿透），触发旧求解器的"穿透锁死"分支
/// 把沿墙平移轴一并锁死（实机：贴墙动不了、只有背向墙才能走）。
///
/// 原版 `Vec3(Vector3fc)` 构造（:71）正对应"渲染边界才转 float32"——本仓
/// 渲染插值输出仍是 `Vector3`，物理/同步全部走本类（double）。
class Vec3 {
  const Vec3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  static const Vec3 zero = Vec3(0.0, 0.0, 0.0);

  @override
  String toString() => 'Vec3($x, $y, $z)';
}
