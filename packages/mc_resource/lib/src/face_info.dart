/// `net/minecraft/client/renderer/FaceInfo.java` 的 Dart 对应物（纯 Dart）。
///
/// 每个朝向的 4 个顶点在 AABB 上的取角规则（烘焙时顶点顺序即此顺序，
/// 判据 `FaceInfo.java:10-46` 的六个枚举项）。
library;

import 'direction.dart';

/// `FaceInfo.Extent`（判据 `FaceInfo.java:70-76`）。
enum Extent { minX, minY, minZ, maxX, maxY, maxZ }

/// `FaceInfo.VertexInfo`（判据 `FaceInfo.java:101-105`）。
class VertexInfo {
  const VertexInfo(this.xFace, this.yFace, this.zFace);

  final Extent xFace;
  final Extent yFace;
  final Extent zFace;

  /// `select(min, max)`。
  ({double x, double y, double z}) select(
      ({double x, double y, double z}) min,
      ({double x, double y, double z}) max) {
    return (
      x: xFace.select(min.x, max.x),
      y: yFace.select(min.y, max.y),
      z: zFace.select(min.z, max.z),
    );
  }
}

/// `FaceInfo`（判据 `FaceInfo.java:10-46`，逐顶点照抄）。
FaceInfoVertexInfo faceInfo(Direction direction) => switch (direction) {
      Direction.down => const [
        VertexInfo(Extent.minX, Extent.minY, Extent.maxZ),
        VertexInfo(Extent.minX, Extent.minY, Extent.minZ),
        VertexInfo(Extent.maxX, Extent.minY, Extent.minZ),
        VertexInfo(Extent.maxX, Extent.minY, Extent.maxZ),
      ],
      Direction.up => const [
        VertexInfo(Extent.minX, Extent.maxY, Extent.minZ),
        VertexInfo(Extent.minX, Extent.maxY, Extent.maxZ),
        VertexInfo(Extent.maxX, Extent.maxY, Extent.maxZ),
        VertexInfo(Extent.maxX, Extent.maxY, Extent.minZ),
      ],
      Direction.north => const [
        VertexInfo(Extent.maxX, Extent.maxY, Extent.minZ),
        VertexInfo(Extent.maxX, Extent.minY, Extent.minZ),
        VertexInfo(Extent.minX, Extent.minY, Extent.minZ),
        VertexInfo(Extent.minX, Extent.maxY, Extent.minZ),
      ],
      Direction.south => const [
        VertexInfo(Extent.minX, Extent.maxY, Extent.maxZ),
        VertexInfo(Extent.minX, Extent.minY, Extent.maxZ),
        VertexInfo(Extent.maxX, Extent.minY, Extent.maxZ),
        VertexInfo(Extent.maxX, Extent.maxY, Extent.maxZ),
      ],
      Direction.west => const [
        VertexInfo(Extent.minX, Extent.maxY, Extent.minZ),
        VertexInfo(Extent.minX, Extent.minY, Extent.minZ),
        VertexInfo(Extent.minX, Extent.minY, Extent.maxZ),
        VertexInfo(Extent.minX, Extent.maxY, Extent.maxZ),
      ],
      Direction.east => const [
        VertexInfo(Extent.maxX, Extent.maxY, Extent.maxZ),
        VertexInfo(Extent.maxX, Extent.minY, Extent.maxZ),
        VertexInfo(Extent.maxX, Extent.minY, Extent.minZ),
        VertexInfo(Extent.maxX, Extent.maxY, Extent.minZ),
      ],
    };

typedef FaceInfoVertexInfo = List<VertexInfo>;

extension ExtentSelect on Extent {
  double select(double min, double max) => switch (this) {
        Extent.minX || Extent.minY || Extent.minZ => min,
        Extent.maxX || Extent.maxY || Extent.maxZ => max,
      };
}
