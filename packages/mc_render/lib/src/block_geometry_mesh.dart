/// 网格器用的方块几何（坐标已归一化到0..1，相对方块原点）。
///
/// ## 判据出处
///
/// 原版把这段放在 `net/minecraft.client.resources.model.cuboid`：
/// - `CuboidModelElement.java:22` —— `elements[]` 每项是 `from`/`to` 两个三维点
///   加一张 `faces` 表。
/// - `CuboidModelElement.java:51-52` —— `from`/`to` 是 **0..16** 整数坐标。
/// - `FaceBakery.java:131` —— 烘焙成顶点时 `vertexInfo.select(from, to).div(16.0F)`
///   ⇒ 归一化到 0..1。本类型即该归一化后的形状。
/// - `CuboidModelElement.java:114-118` —— `faces` 为空原版**抛异常**
///   （`Expected between 1 and 6 unique faces, got 0`）⇒ **只画模型声明的面**，
///   未声明的面不画。
/// - `FaceBakery.java:44-47` —— 面 `uv` 也在 0..16 空间，除 16 归一化并做 min/max 规整。
///
/// **为什么本类型在 mc_render 而不在 mc_resource**：包纯度要求 `mc_render` 只依赖
/// `mc_nbt`，不依赖 `mc_resource`。网格器是几何的**消费者**，故形状契约定义在
/// 此处；`mc_resource.BlockGeometryMesh`（解析侧）由 app 壳转换成本类型后注入。
library;

/// 一个 AABB 元素的面。
class BoxFace {
  const BoxFace({
    required this.direction,
    required this.u1,
    required this.v1,
    required this.u2,
    required this.v2,
    this.texture,
  });

  /// 面朝向。取值与 [BlockFace] 的名字一致（`'down'|'up'|'north'|'south'|'west'|'east'`），
  /// 用字符串是为了让 [mc_render] 不必在几何类型里依赖 mesher 的枚举定义顺序。
  final String direction;

  /// UV 矩形（0..1，纹理空间；已按 `FaceBakery.java:44-47` 做 min/max 规整）。
  final double u1, v1, u2, v2;

  /// 该面引用的**模型纹理变量**（模型 JSON 里 `faces[].texture` 去掉 `#`，
  /// 如 `all`/`side`/`top`）。
  ///
  /// 判据：`CuboidFace.texture` 是面的属性、烘焙时不随 blockstate 旋转改变
  /// （`CuboidFace.java:37`；`ModelBakery` 用模型的 `textures` 映射把变量解析
  /// 成 Sprite）。为 null 时（整方块快速路径等无变量来源处）由调用方退回
  /// 按朝向的键链解析。
  final String? texture;
}

/// 一个 AABB 元素（模型 `elements[]` 的一项）。
class BoxGeometry {
  const BoxGeometry({
    required this.fromX,
    required this.fromY,
    required this.fromZ,
    required this.toX,
    required this.toY,
    required this.toZ,
    required this.faces,
  });

  /// 左下角（0..1）。
  final double fromX, fromY, fromZ;

  /// 右上角（0..1）。
  final double toX, toY, toZ;

  /// 该元素**显式声明**的面（判据见类文档）。未声明的面不画。
  final List<BoxFace> faces;

  /// 是否覆盖整格（`from=(0,0,0)`、`to=(1,1,1)`）——等价整方块，可用快速路径。
  bool get isFullBlock =>
      fromX == 0.0 && fromY == 0.0 && fromZ == 0.0 &&
      toX == 1.0 && toY == 1.0 && toZ == 1.0;
}

/// 一个方块的完整几何。
class BlockGeometryMesh {
  const BlockGeometryMesh({required this.boxes, required this.hasUnsupportedRotation});

  /// 无几何（模型未声明 `elements`）⇒ 调用方回退整方块路径。
  static const BlockGeometryMesh none =
      BlockGeometryMesh(boxes: [], hasUnsupportedRotation: false);

  /// 几何元素（0..1 归一化）。
  final List<BoxGeometry> boxes;

  /// 模型链上存在 `elements[].rotation`（本网格器**不支持**）。
  ///
  /// 判据：`CuboidRotation` + `FaceBakery` 的旋转烘焙路径，涉及
  /// origin/axis/angle/rescale 与顶点绕原点重排，超出"逐 AABB 出面"范围。
  /// 26.2 的 343 个含 `elements` 的模型中 95 个带 rotation（铁轨、告示牌、作物等）。
  ///
  /// 为 true 时调用方 MUST 显式回退整方块并留下记录，
  /// **MUST NOT 静默按未旋转渲染**。
  final bool hasUnsupportedRotation;

  bool get isNone => boxes.isEmpty;

  /// 单元素且覆盖整格 ⇒ 与旧的整方块路径等价。
  bool get isSingleFullBlock => boxes.length == 1 && boxes.first.isFullBlock;
}