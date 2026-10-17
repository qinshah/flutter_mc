/// `net/minecraft/core/Direction.java` 的 Dart 对应物（本实现用到的子集）。
///
/// 六个水平/垂直朝向 + 轴/轴正负。枚举顺序照原版
/// （`Direction.java` 的 DOWN, UP, NORTH, SOUTH, WEST, EAST）。
///
/// 只翻译方块模型烘焙用到的成员：`getAxis` / `getAxisDirection` /
/// `fromAxisAndDirection` / `opposite` / `byName`；法向量、计划刻度等
/// 渲染后端无关成员未引入（自由设计注记：子集裁剪，语义逐项对应）。
library;

/// `Direction.Axis`（判据 `Direction.java` 的 Axis 枚举）。
enum Axis {
  x,
  y,
  z;

  /// `Axis.VALUES[axis.ordinal()]`（`permuteAxis` 的查表，见
  /// `SymmetricGroup3.permuteAxis`）。
  static Axis byOrdinal(int ordinal) => values[ordinal];
}

/// `Direction.AxisDirection`（POSITIVE / NEGATIVE）。
enum AxisDirection {
  positive,
  negative;

  /// `AxisDirection.opposite()`。
  AxisDirection get opposite =>
      this == positive ? negative : positive;
}

/// `Direction`（判据 `Direction.java`）。
enum Direction {
  down(Axis.y, AxisDirection.negative, 'down'),
  up(Axis.y, AxisDirection.positive, 'up'),
  north(Axis.z, AxisDirection.negative, 'north'),
  south(Axis.z, AxisDirection.positive, 'south'),
  west(Axis.x, AxisDirection.negative, 'west'),
  east(Axis.x, AxisDirection.positive, 'east');

  const Direction(this.axis, this.axisDirection, this.name);

  final Axis axis;
  final AxisDirection axisDirection;
  final String name;

  /// `Direction.fromAxisAndDirection`。
  static Direction fromAxisAndDirection(Axis axis, AxisDirection direction) =>
      values.firstWhere((d) => d.axis == axis && d.axisDirection == direction);

  /// `Direction.byName`（模型 JSON 的面键全小写；未知返回 null）。
  static Direction? byName(String name) {
    for (final d in values) {
      if (d.name == name) return d;
    }
    return null;
  }

  /// `Direction.getOpposite()`。
  Direction get opposite => fromAxisAndDirection(axis, axisDirection.opposite);
}
