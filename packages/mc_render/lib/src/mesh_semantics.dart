/// 网格化所需的方块语义（按 stateId 查询；版本实现由装配处注入）。
///
/// [MeshSemantics.nameOf] 返回去掉命名空间与属性串的方块名
/// （如 "grass_block"），供贴图解析与分类启发式使用。
abstract interface class MeshSemantics {
  /// 渲染层：0 opaque / 1 cutout / 2 translucent。
  int layerIndexOf(int stateId);

  /// 是否为十字植物（两片对角面片，不参与面剔除）。
  bool isCross(int stateId);

  /// 是否完全不透光（遮挡邻居面）。
  bool hidesNeighbors(int stateId);

  /// 方块名（去命名空间/属性），未知 state 返回 "unknown"。
  String nameOf(int stateId);
}

/// 语义查询结果的缓存视图（一段网格化会反复取同一批 state）。
class MeshSemanticsCache implements MeshSemantics {
  MeshSemanticsCache(this._inner);

  final MeshSemantics _inner;
  final _layer = <int, int>{};
  final _cross = <int, bool>{};
  final _hides = <int, bool>{};
  final _name = <int, String>{};

  @override
  int layerIndexOf(int stateId) =>
      _layer.putIfAbsent(stateId, () => _inner.layerIndexOf(stateId));

  @override
  bool isCross(int stateId) =>
      _cross.putIfAbsent(stateId, () => _inner.isCross(stateId));

  @override
  bool hidesNeighbors(int stateId) =>
      _hides.putIfAbsent(stateId, () => _inner.hidesNeighbors(stateId));

  @override
  String nameOf(int stateId) =>
      _name.putIfAbsent(stateId, () => _inner.nameOf(stateId));
}
