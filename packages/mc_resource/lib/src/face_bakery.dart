/// `net/minecraft/client/resources/model/cuboid/FaceBakery.java` 的 Dart
/// 对应物（**blockstate 变体旋转的盒级烘焙**，纯 Dart）。
///
/// 原版在烘焙期对每个面的 4 个顶点做：
/// 1. 取角（`FaceInfo`，判据 `FaceBakery.java:130-131`）；
/// 2. 绕块中心 (0.5,0.5,0.5) 施加模型旋转（`FaceBakery.java:136-138`，
///    `BLOCK_MIDDLE` 在 :23）；
/// 3. UV：uvlock 时按 `inverseFaceTransformation(原面)` 绕 (0.5,0.5) 变换
///    （`FaceBakery.java:85,144-151`），否则原样（`ModelState.java:19-21`）；
/// 4. `calculateFacing` 取旋转后的面朝向（:96,171-194）——群旋转下法线仍
///    轴对齐，精确等于 [OctahedralGroup.rotate]；
/// 5. `recalculateWinding` 把顶点/UV 重排到新朝向的取角模板
///    （:96-99,196-251）。
///
/// 本实现以 AABB 面为粒度执行同一条管线（盒在群旋转下仍是轴对齐盒），
/// 最后把 4 个「最终顶点 → UV」还原成矩形 UV。纹理变量（`CuboidFace.texture`）
/// **不随旋转改变**（判据 `CuboidFace.java:37`：texture 是面的属性，
/// `FaceBakery` 只旋转位置与 UV）。
///
/// 已知限制（翻译债，见 `openspec/progress.md`）：少数（旋转群, 面）组合下
/// 最终 UV 场相对模板是**转置**的（u 随模板 cv 变、v 随模板 cu 变），轴对齐
/// 矩形无法表示字段方向，此时退化为包围矩形（方向丢失）。
library;

import 'block_geometry.dart';
import 'block_model_rotation.dart';
import 'direction.dart';
import 'face_info.dart';
import 'octahedral_group.dart';

/// 对解析好的模型几何施加 blockstate 变体旋转（`x`/`y`/`z` + `uvlock`）。
///
/// 判据 `SimpleModelWrapper.bake` → `FaceBakery.bakeQuad` 的旋转路径。
BlockGeometry bakeBlockstateRotation(
  BlockGeometry geometry,
  BlockModelRotation rotation,
) {
  final group = rotation.group;
  if (group.isIdentity && !rotation.uvLock) return geometry;

  final boxes = <ModelBox>[];
  for (final box in geometry.boxes) {
    final (from2, to2) = _rotateBox(box, group);
    final faces = <String>[];
    final uvs = <({double u1, double v1, double u2, double v2})>[];
    final textures = <String>[];
    final cullFaces = <String?>[];
    for (var i = 0; i < box.faces.length; i++) {
      final d0 = Direction.byName(box.faces[i]);
      if (d0 == null) continue; // 解析侧已过滤，兜底不画
      final d1 = group.rotate(d0);
      final rect = _bakeFaceUvs(box, d0, box.uvs[i], rotation);
      faces.add(d1.name);
      uvs.add(rect);
      textures.add(box.textures[i]);
      final cull = box.cullFaces[i];
      final cullDir = cull == null ? null : Direction.byName(cull);
      cullFaces.add(cullDir == null ? cull : group.rotate(cullDir).name);
    }
    boxes.add(ModelBox(
      from: from2,
      to: to2,
      faces: faces,
      uvs: uvs,
      textures: textures,
      cullFaces: cullFaces,
    ));
  }
  return BlockGeometry(
    boxes: boxes,
    unsupportedRotation: geometry.unsupportedRotation,
  );
}

({double x, double y, double z}) _uvOf(
        ({double u1, double v1, double u2, double v2}) r, int corner) =>
    switch (corner) {
      // `CuboidFace.UVs.getVertexU/getVertexV`（CuboidFace.java:77-83）：
      // v0=(minU,minV), v1=(minU,maxV), v2=(maxU,maxV), v3=(maxU,minV)。
      0 => (x: r.u1, y: r.v1, z: 0.0),
      1 => (x: r.u1, y: r.v2, z: 0.0),
      2 => (x: r.u2, y: r.v2, z: 0.0),
      _ => (x: r.u2, y: r.v1, z: 0.0),
    };

({double u1, double v1, double u2, double v2}) _bakeFaceUvs(
  ModelBox box,
  Direction d0,
  ({double u1, double v1, double u2, double v2}) rect,
  BlockModelRotation rotation,
) {
  final group = rotation.group;
  final info = faceInfo(d0);

  // 1. 每顶点原始 UV（CuboidFace.UVs 绑定）。
  final raw = [
    for (var i = 0; i < 4; i++) _uvOf(rect, i),
  ];

  // 2. uvlock：按 inverseFaceTransformation(原面) 绕 (0.5,0.5) 变换
  //    （FaceBakery.java:85,144-151）。原版 :144 对恒等变换**短路直通**
  //    （MatrixUtil.isIdentity ⇒ transformedU = rawU，不做 (u−0.5)+0.5 往返）。
  //    精度注记：原版此链是 JOML Vector3f（float32）；模型 UV 恒为 k/16 型
  //    二进小数（u−0.5、×±1、+0.5 全部落在 float32 精确域），float32 与
  //    double 位级一致，故本实现按 double 递推不损失保真度。
  final m = rotation.inverseFaceTransformation(d0);
  final transformed = (m == null || m.isIdentity)
      ? raw
      : [
          for (final uv in raw) _transformUv(m, uv),
        ];

  // 3. 顶点位置旋转（FaceBakery.java:136-138）。
  final rotated = [
    for (var i = 0; i < 4; i++)
      group.rotatePoint(info[i].select(box.from, box.to)),
  ];

  // 4-5. recalculateWinding（FaceBakery.java:196-251）：新朝向模板的每个
  //      取角位置，找到旋转后落在该位置的原始顶点，沿用其 UV。
  //      模板角绑定（CuboidFace.java:77-83）：k=0→(cuMin,cvMin)、
  //      k=1→(cuMin,cvMax)、k=2→(cuMax,cvMax)、k=3→(cuMax,cvMin)。
  final (from2, to2) = _rotateBox(box, group);
  final newInfo = faceInfo(group.rotate(d0));
  final wx = List<double>.filled(4, 0); // 最终 UV 的 u 通道（模板 cu/cv 槽位）
  final wy = List<double>.filled(4, 0); // 最终 UV 的 v 通道
  for (var k = 0; k < 4; k++) {
    final target = newInfo[k].select(from2, to2);
    var found = -1;
    for (var i = 0; i < 4; i++) {
      if (rotated[i] == target) {
        found = i;
        break;
      }
    }
    if (found < 0) {
      // 理论不可达（群旋转把 AABB 角映到 AABB 角）；兜底保持原矩形。
      return rect;
    }
    wx[k] = transformed[found].x;
    wy[k] = transformed[found].y;
  }
  // 轴对齐检查：u 只随 cu 变、v 只随 cv 变 → 直接还原矩形
  // （u1=W0、u2=W2、v1=W0、v2=W1）。
  if (wx[0] == wx[1] && wx[2] == wx[3] && wy[0] == wy[3] && wy[1] == wy[2]) {
    return (u1: wx[0], v1: wy[0], u2: wx[2], v2: wy[1]);
  }
  // 转置情形：u 随 cv 变、v 随 cu 变（实证：east 面 + x=90）。BoxFace 的
  // 轴对齐矩形 UV 表示无法保留字段方向，退化为取两通道的 min/max 包围矩形
  // （方向丢失）。**翻译债**：已登记 openspec/progress.md。
  if (wx[0] == wx[3] && wx[1] == wx[2] && wy[0] == wy[1] && wy[2] == wy[3]) {
    final u1 = wx[0] < wx[1] ? wx[0] : wx[1];
    final u2 = wx[0] < wx[1] ? wx[1] : wx[0];
    final v1 = wy[0] < wy[2] ? wy[0] : wy[2];
    final v2 = wy[0] < wy[2] ? wy[2] : wy[0];
    return (u1: u1, v1: v1, u2: u2, v2: v2);
  }
  // 理论不可达（模板角绑定下 4 个 UV 必呈上述两种模式之一）；兜底包围盒。
  var uMin = wx[0], uMax = wx[0], vMin = wy[0], vMax = wy[0];
  for (var k = 1; k < 4; k++) {
    if (wx[k] < uMin) uMin = wx[k];
    if (wx[k] > uMax) uMax = wx[k];
    if (wy[k] < vMin) vMin = wy[k];
    if (wy[k] > vMax) vMax = wy[k];
  }
  return (u1: uMin, v1: vMin, u2: uMax, v2: vMax);
}

/// UV 点经符号置换群变换（中心坐标语义，`FaceBakery.java:148-150`：
/// 输入 (u−0.5, v−0.5, 0)，取输出 x,y 后 +0.5）。
({double x, double y, double z}) _transformUv(
    OctahedralGroup m, ({double x, double y, double z}) uv) {
  final input = (
    x: uv.x - 0.5,
    y: uv.y - 0.5,
    z: uv.z, // 原版 z 不做 cornerToCenter（FaceBakery.java:148）
  );
  final p = m.permutation;
  final cx = _pick(input, p.permute(0)) * (m.invertX ? -1.0 : 1.0);
  final cy = _pick(input, p.permute(1)) * (m.invertY ? -1.0 : 1.0);
  final cz = _pick(input, p.permute(2)) * (m.invertZ ? -1.0 : 1.0);
  return (x: cx + 0.5, y: cy + 0.5, z: cz);
}

double _pick(({double x, double y, double z}) v, int axisIndex) =>
    switch (axisIndex) {
      0 => v.x,
      1 => v.y,
      _ => v.z,
    };

/// 盒旋转：两角分别过群变换，再逐轴 min/max（群旋转把轴对齐盒映为轴对齐盒）。
(({double x, double y, double z}), ({double x, double y, double z}))
    _rotateBox(ModelBox box, OctahedralGroup group) {
  final a = group.rotatePoint(box.from);
  final b = group.rotatePoint(box.to);
  return (
    (
      x: a.x < b.x ? a.x : b.x,
      y: a.y < b.y ? a.y : b.y,
      z: a.z < b.z ? a.z : b.z,
    ),
    (
      x: a.x < b.x ? b.x : a.x,
      y: a.y < b.y ? b.y : a.y,
      z: a.z < b.z ? b.z : a.z,
    ),
  );
}
