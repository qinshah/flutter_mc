import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart';
import 'package:mc_render/mc_render.dart';
import 'package:mc_session/mc_session.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'block_textures.dart';
import 'column_section_view.dart';
import 'engine_space.dart';
import 'input_state.dart';
import 'key_map.dart';
import 'player.dart';
import 'player_controller.dart';
import 'session_collision_world.dart';
import 'sky_model.dart';

/// 游戏屏（join-and-render 3.1 骨架）。
///
/// 原版对应物：`client.gui.screens.LevelLoadingScreen` → `LevelRenderer` 的装配面
/// （世界渲染的持有与驱动）。本类是 app 壳的**装配层**，只做三件事：
/// 1. flutter_scene `Scene` + `SceneView` 的持有与逐帧驱动；
/// 2. 订阅会话事件流（worker isolate 回传的 `SessionEvent`），把服务器世界变成场景节点；
/// 3. 相机跟随玩家（位置由 `PositionCorrection` 的服务器权威值定）。
///
/// **分层**：本文件可以用 flutter_scene；方块语义/网格计算在 `mc_render`（纯 Dart），
/// 协议与会话在 `mc_session`（纯 Dart）。容器与光照首版从简（见 `_SectionMaterials`）。
///
/// 未接线（后续切片）：键盘输入与本地碰撞预测（3.2）、图集贴图与昼夜天空（3.3）、
/// 多人屏入口与路由（3.4）。
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.session});

  /// 装配点建好的会话句柄（`SessionAssembly.connectFor` 的产物）。
  /// 本屏是它的消费方：`dispose` 时负责关掉。
  final SessionHandle session;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final Scene _scene = Scene();
  final Player _player = Player();

  /// 已加载的列，键为 `(chunkX, chunkZ)`（邻居查询用）。
  final Map<(int, int), RemoteChunkColumn> _columns = {};

  /// 已挂载的段节点，键为 `"chunkX,sectionY,chunkZ"`。
  final Map<String, Node> _sectionNodes = {};

  /// 方块语义的**查询缓存**（mc_render 自带）。必须复用同一个实例：语义查询是
  /// 网格化最热的一环（每格每面都要问），而 `BlockSemanticsV262` 每次都做
  /// stateId → 身份串的字符串解析 + contains/startsWith 判定。缓存后每个 stateId
  /// 只算一次。**注意**：不缓存时视距内几百列的网格化会把主 isolate 卡死（实测）。
  final MeshSemanticsCache _semantics =
      MeshSemanticsCache(const BlockSemanticsV262());

  /// 待网格化的段（脏队列 + 去重集合）。
  ///
  /// 列到达时**只登记不网格化**，改由 [_onTick] 按帧摊还——否则一次收到一批列
  /// （每列 24 段 + 4 个邻居各 24 段）会在单帧里做上百次 16³ 扫描，界面直接卡死。
  final List<(int, int, int)> _dirtyQueue = [];
  final Set<(int, int, int)> _dirtySet = {};
  int _dirtyCursor = 0;

  /// 每帧最多网格化多少段（摊还预算）。宁可地形晚几帧补齐，也不能卡住输入与渲染。
  static const int _meshBudgetPerFrame = 6;

  /// 材质与贴图表都在引擎静态资源就绪后建（见 [_boot]）。
  _SectionMaterials? _materials;
  BlockTextures? _blockTextures;

  /// 天空模型：纯数学，时间源是服务器的 `TimeUpdated`。
  final SkyModel _sky = SkyModel();
  GradientSkySource? _skySource;

  /// 输入与物理（3.2）：按键状态 → `InputState` → `PlayerController` → 上行。
  final InputState _input = InputState();
  final Set<LogicalKeyboardKey> _pressed = {};
  final FocusNode _focus = FocusNode();
  late final PlayerController _controller;

  late final PerspectiveCamera _camera;

  StreamSubscription<SessionEvent>? _events;
  bool _ready = false;
  bool _exiting = false;

  /// 诊断探针开关（`--dart-define=TRACE=true` 才生效）。
  static const bool _trace = bool.fromEnvironment('TRACE');
  double _traceAccum = 0;

  /// 上行节流累计。原版每**刻**（20 Hz）上报一次移动，逐帧上报会把服务器的移动
  /// 校验打乱（实测服务器刷 moved too quickly）；这里按 20 Hz 发。
  double _uplinkAccum = 0;
  static const double _uplinkInterval = 1 / 20;

  /// 探针用：上行计数（每 20 次打一行）。
  int _sendTraceCount = 0;

  /// 合成输入（`--dart-define=AUTOWALK=true`）：端到端取证用——驱动 tap 模拟不了
  /// 键盘，所以由调试开关直接注入"一直向前走 + 每 2 秒跳一下"。默认关，不参与发行。
  static const bool _autoWalk = bool.fromEnvironment('AUTOWALK');
  double _autoWalkTime = 0;

  @override
  void initState() {
    super.initState();
    _controller = PlayerController(
      world: SessionCollisionWorld(_columns),
      player: _player,
    );
    _camera = PerspectiveCamera(
      position: vm.Vector3(0, 0, 0),
      target: vm.Vector3(0, 0, 1),
      fovNear: 0.05,
      fovFar: 1024,
    );
    _boot();
  }

  /// 引擎静态资源（shader bundle）就绪后才能建几何与材质——早建出来的会静默不渲染。
  Future<void> _boot() async {
    await Scene.initializeStaticResources();

    // 几何 / 材质 / 天空都只能在静态资源就绪后构造（早建出来的会静默不渲染）。
    final textures = await BlockTextures.load();
    _blockTextures = textures;
    // 贴图是**按需**解析的：解析出一个新方块后，已用兜底 UV 网格化的段要重做。
    textures?.onResolved = _markAllSectionsDirty;
    if (_trace) {
      // 贴图链路取证：null 表示资源包/图集没读到（会退化成纯顶点色）。
      debugPrint(textures == null
          ? '[TEX] 图集缺失：BlockTextures.load() 返回 null（退化为顶点色）'
          : '[TEX] 图集就绪 spriteCount=${textures.spriteCount} '
              'blocks=${textures.blockCount}');
    }
    // 贴图失败**不能**让整屏起不来：flutter_scene 的 loadTexture 要求构建钩子先把
    // 图片"cook"进 flutter_scene_generated/（本仓尚无该钩子，会抛 Bad state）。
    // 这里吞掉异常并退化为顶点色——贴图是观感增强，不是进世界的必要条件。
    TextureSource? atlasTexture;
    if (textures != null) {
      try {
        atlasTexture = await loadTexture(BlockTextures.atlasAssetPath);
      } catch (e) {
        if (_trace) debugPrint('[TEX] 贴图加载失败，退化为顶点色：$e');
      }
    }
    _materials = _SectionMaterials(atlasTexture);

    final skySource = GradientSkySource();
    _skySource = skySource;
    _scene
      ..skybox = Skybox(skySource)
      // 天空同时驱动 IBL 与方向光：昼夜不只是"天变黑"，世界亮度也跟着走。
      // 刷新走 interval（服务器时间约每秒一次，逐帧重烘没必要）。
      ..skyEnvironment = SkyEnvironment(
        skySource,
        refresh: SkyEnvironmentRefresh.interval,
        interval: const Duration(seconds: 2),
      )
      ..sunLight = SunLight(skySource);
    _applySky();

    if (!mounted) return;
    _events = widget.session.events.listen(
      _onEvent,
      onDone: () => _exit('会话终止'),
      onError: (Object e) => _exit('会话异常：$e'),
    );
    setState(() => _ready = true);
  }

  @override
  void dispose() {
    _events?.cancel();
    _focus.dispose();
    widget.session.close();
    super.dispose();
  }

  // —— 输入（Flutter 输入是本项目三处自由设计之一；键位照原版 KeyMapping） ——

  void _onKey(KeyEvent event) {
    if (KeyMap.update(_pressed, event)) KeyMap.apply(_pressed, _input);
  }

  // —— 会话事件 → 场景 ——
  //
  // 事件来自 worker isolate，但 `SessionHandle.events` 是主 isolate 上的流
  // （isolate 边界由 mc_session 收口），所以这里可以直接改场景。

  void _onEvent(SessionEvent event) {
    switch (event) {
      case JoinedGame():
        // 进服成功；玩家位姿等随后的 PositionCorrection（原版登录后必发一次）。
        break;

      case PositionCorrection(
          :final x,
          :final y,
          :final z,
          :final yRot,
          :final xRot,
          :final teleportId,
          :final isTeleport,
          :final dx,
          :final dy,
          :final dz
        ):
        if (_trace) {
          debugPrint('[CORR] ($x, $y, $z) teleportId=$teleportId '
              'isTeleport=$isTeleport');
        }
        // 服务器权威位姿（相对标志已在会话侧解成绝对值）；直接采信并清速度。
        _player.position.setValues(x, y, z);
        // 原版 setDeltaMovement(newValues.deltaMovement())：速度也以服务器下发为准。
        _player.velocity.setValues(dx, dy, dz);
        // 原版 yaw 0 = 朝 +Z（度）；本应用 yaw 0 = 朝 -Z（弧度）——逆变换。
        _player.yaw = (180.0 - yRot) * math.pi / 180.0;
        _player.pitch = xRot * math.pi / 180.0;

      case ChunkLoaded(:final chunk):
        _mountColumn(chunk);

      case ChunkUnloaded(:final x, :final z):
        _unmountColumn(x, z);

      case SessionClosed(:final reason):
        _exit(reason);

      case TimeUpdated(:final gameTime):
        // 服务器时间 → 天色 / 太阳角（原版约每秒一次 SetTime）。
        _sky.setGameTime(gameTime);
        _applySky();

      case BlockChanged():
      case SectionChanged():
        // 后续切片（方块交互的增量重网格化）用。
        break;
    }
  }

  void _exit(String reason) {
    if (_exiting) return;
    _exiting = true;
    if (!mounted) return;
    // 返回原因给调用方（多人屏据此提示），失败回到列表——design D6。
    Navigator.of(context).pop(reason);
  }

  // —— 区块 → 场景节点 ——

  void _mountColumn(RemoteChunkColumn column) {
    _columns[(column.x, column.z)] = column;
    for (var sy = 0; sy < column.sections.length; sy++) {
      _markDirty(column.x, sy, column.z);
    }
    // 新列就位后，贴边邻居段的边界面从"外表面"变成"内部面"，必须重建。
    for (final (dx, dz) in const [(-1, 0), (1, 0), (0, -1), (0, 1)]) {
      final neighbor = _columns[(column.x + dx, column.z + dz)];
      if (neighbor == null) continue;
      for (var sy = 0; sy < neighbor.sections.length; sy++) {
        _markDirty(neighbor.x, sy, neighbor.z);
      }
    }
  }

  /// 把所有已加载段标脏（贴图增量解析完成时调用）。
  ///
  /// 脏队列按"段"去重，所以连续解析出多个方块时不会把队列撑大；重做由每帧预算
  /// [_meshBudgetPerFrame] 摊还。代价是最早重做的那批段可能仍用着"当时已解析到"的
  /// 贴图——解析通常几秒内收敛，可接受。
  void _markAllSectionsDirty() {
    for (final column in _columns.values) {
      for (var sy = 0; sy < column.sections.length; sy++) {
        _markDirty(column.x, sy, column.z);
      }
    }
  }

  /// 登记一个待网格化的段（去重；真正干活在 [_processDirty]）。
  void _markDirty(int chunkX, int sectionY, int chunkZ) {
    if (_dirtySet.add((chunkX, sectionY, chunkZ))) {
      _dirtyQueue.add((chunkX, sectionY, chunkZ));
    }
  }

  /// 按帧预算消费脏队列（摊还网格化）。一次调用是同步的，不会与事件交错。
  void _processDirty() {
    var budget = _meshBudgetPerFrame;
    while (budget > 0 && _dirtyCursor < _dirtyQueue.length) {
      final (x, y, z) = _dirtyQueue[_dirtyCursor++];
      _dirtySet.remove((x, y, z));
      _remeshSection(x, y, z);
      budget--;
    }
    if (_dirtyCursor >= _dirtyQueue.length) {
      _dirtyQueue.clear();
      _dirtySet.clear();
      _dirtyCursor = 0;
    }
  }

  void _unmountColumn(int chunkX, int chunkZ) {
    _columns.remove((chunkX, chunkZ));
    final prefix = '$chunkX,';
    final suffix = ',$chunkZ';
    final doomed = _sectionNodes.keys
        .where((k) => k.startsWith(prefix) && k.endsWith(suffix))
        .toList();
    for (final key in doomed) {
      final node = _sectionNodes.remove(key);
      if (node != null) _scene.remove(node);
    }
    // 邻居的贴边面重新变成外表面，需要复建。
    for (final (dx, dz) in const [(-1, 0), (1, 0), (0, -1), (0, 1)]) {
      final neighbor = _columns[(chunkX + dx, chunkZ + dz)];
      if (neighbor == null) continue;
      for (var sy = 0; sy < neighbor.sections.length; sy++) {
        _markDirty(neighbor.x, sy, neighbor.z);
      }
    }
  }

  /// 重网格化一个段并替换它的场景节点（整段换节点，不做原地顶点更新）。
  void _remeshSection(int chunkX, int sectionY, int chunkZ) {
    final column = _columns[(chunkX, chunkZ)];
    if (column == null || sectionY < 0 || sectionY >= column.sections.length) {
      return;
    }
    // 静态资源/材质就绪前不该有事件进来（订阅在 _boot 里晚于建材质），防御一下。
    if (_materials == null) return;

    final key = '$chunkX,$sectionY,$chunkZ';
    final old = _sectionNodes.remove(key);
    if (old != null) _scene.remove(old);

    final mesh = meshSection(
      ColumnSectionView(column, sectionY),
      neighborsOf(column, sectionY, _columns),
      semantics: _semantics,
      // 贴图表由资源包在启动期预解析（资产缺失时退化为整图 + 顶点色）。
      uvFor: _blockTextures?.uvFor ?? _flatUv,
    );
    if (mesh.isEmpty) return;

    final node = _buildNode(chunkX, sectionY, chunkZ, mesh);
    _sectionNodes[key] = node;
    _scene.add(node);
  }

  Node _buildNode(int chunkX, int sectionY, int chunkZ, ChunkMesh mesh) {
    final primitives = <MeshPrimitive>[];

    void addLayer(ChunkMeshData? data, PhysicallyBasedMaterial material) {
      if (data == null || data.isEmpty) return;
      final b = data.bounds;
      primitives.add(
        MeshPrimitive(
          MeshGeometry.fromArrays(
            positions: data.positions,
            normals: data.normals,
            texCoords: data.texCoords,
            colors: data.colors,
            indices: data.indices,
            // 网格器边写顶点边更新的 AABB 直接交给引擎，省掉构造期一次全顶点扫描。
            bounds: vm.Aabb3.minMax(
              vm.Vector3(b[0], b[1], b[2]),
              vm.Vector3(b[3], b[4], b[5]),
            ),
            // 段网格不需要 CPU 副本：体素射线检测走我们自己的世界查询，不用几何体。
            retainCpuData: false,
          ),
          material,
        ),
      );
    }

    final materials = _materials!;
    addLayer(mesh.opaque, materials.opaque);
    addLayer(mesh.cutout, materials.cutout);
    addLayer(mesh.translucent, materials.translucent);

    return Node(
      name: 'section',
      mesh: Mesh.primitives(primitives: primitives),
      // 段原点也要走手性转换（z 取反），否则整段跑到世界的另一侧。
      localTransform: vm.Matrix4.translation(
        sectionOriginToEngineSpace(chunkX, sectionY, chunkZ),
      ),
    )..shadowStatic = true;
  }

  /// 把 [SkyModel] 算出的天色 / 太阳喂给引擎的天空源。
  ///
  /// 太阳方向要过手性转换（世界右手系 → 引擎左手系），否则太阳会挂在镜像的位置。
  void _applySky() {
    final source = _skySource;
    if (source == null) return;
    source
      ..zenithColor = _sky.zenithColor
      ..horizonColor = _sky.horizonColor
      ..groundColor = _sky.groundColor
      ..sunDirection = directionToEngineSpace(_sky.sunDirection())
      // HDR 太阳色按昼夜明暗缩放，夜里接近熄灭（否则"夜里的太阳也很亮"）。
      ..sunColor = _sky.sunColor * _sky.sunIntensityScale;
  }

  // —— 逐帧 ——

  void _onTick(Duration elapsed, double dt) {
    // 0) 摊还网格化（每帧限额，避免地形涌入时卡住输入与渲染）。
    _processDirty();

    // 脚下这一列的区块还没到就**不做物理也不上行**：原版客户端在收到区块前同样不动，
    // 否则本地重力会在空世界里自由落体、人掉出世界、相机跑到地形下方。
    //
    // 注意**不要**再要求"已收到服务器位姿"才动：修掉 EntityPositionSync 误用之后，
    // 那条路径不再产生位姿事件，而 Paper 并不保证登录后立刻发 PlayerPosition——
    // 于是玩家永远不动、也不上行（实测：门禁加上它就再无任何上行）。
    final spawnColumn = (_player.position.x.floor() >> 4, _player.position.z.floor() >> 4);
    if (!_columns.containsKey(spawnColumn)) {
      _cameraSync();
      return;
    }

    // 0.5) 合成输入（仅调试开关开启时）。
    if (_autoWalk) {
      _autoWalkTime += dt;
      // 边走边转（螺旋）：只朝一个方向走可能正对墙，位置不变会让人误判"物理没生效"。
      _player.yaw += 0.9 * dt;
      _input
        ..move.y = 1 // 一直向前
        ..jump = _autoWalkTime % 2.0 < 0.15; // 每 2 秒按一下空格
    }

    // 1) 本地预测：物理推进（固定步长；dt 是渲染帧间隔）。
    _controller.tick(dt, _input);

    if (_trace) {
      _traceAccum += dt;
      if (_traceAccum >= 1.0) {
        _traceAccum = 0;
        final world = _controller.world;
        final bx = _player.position.x.floor();
        final by = _player.position.y.floor();
        final bz = _player.position.z.floor();
        final col = _columns[(bx >> 4, bz >> 4)];
        debugPrint(
          '[TRACE] pos=(${_player.position.x.toStringAsFixed(1)},'
          '${_player.position.y.toStringAsFixed(1)},'
          '${_player.position.z.toStringAsFixed(1)}) '
          'vy=${_player.velocity.y.toStringAsFixed(1)} '
          'onGround=${_player.onGround} '
          'cols=${_columns.length} '
          'colLoaded=${col != null} '
          'state@feet=${col?.stateAt(bx & 15, by, bz & 15)} '
          'collidable=${world.isCollidable(bx, by, bz)} '
          'collidableBelow=${world.isCollidable(bx, by - 1, bz)} '
          'dirty=${_dirtyQueue.length - _dirtyCursor} '
          'yaw=${_player.yaw.toStringAsFixed(2)}',
        );
      }
    }

    // 2) 上行玩家状态（原版角度制：yaw 0 = 朝 +Z；本应用 0 = 朝 -Z）。
    //    节流到原版的每刻一次；逐帧发会打乱服务器侧的移动校验。
    _uplinkAccum += dt;
    if (_uplinkAccum >= _uplinkInterval) {
      _uplinkAccum = 0;
      if (_trace) {
        // 每 20 次（≈每秒一次）打一次上行值，便于与 [CORR] 对照。
        _sendTraceCount++;
        if (_sendTraceCount % 20 == 0) {
          debugPrint('[SEND] (${_player.position.x}, ${_player.position.y}, '
              '${_player.position.z}) onGround=${_player.onGround} '
              'vy=${_player.velocity.y}');
        }
      }
      widget.session.commands.send(
        CmdUpdatePlayer(
          x: _player.position.x,
          y: _player.position.y,
          z: _player.position.z,
          yaw: 180.0 - _player.yaw * 180.0 / math.pi,
          pitch: _player.pitch * 180.0 / math.pi,
          onGround: _player.onGround,
          horizontalCollision: false,
        ),
      );
    }

    // 3) 本帧的鼠标位移是消费型输入，用完即清（按住的键保留）。
    _input.endFrame();

    // 4) 相机跟随。
    _cameraSync();
  }

  /// 相机 = 玩家眼睛位置（含手性转换），朝向 = 玩家视线方向。
  void _cameraSync() {
    final eye = toEngineSpace(_player.eyePosition);
    _camera
      ..position = eye
      ..target = eye + directionToEngineSpace(_player.lookDirection);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      backgroundColor: const Color(0xFF87CEEB), // 3.3 接昼夜天空前的占位底色
      body: KeyboardListener(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: SceneView(_scene, camera: _camera, onTick: _onTick),
      ),
    );
  }
}

/// 无贴图时的占位 UV：整图（配合顶点色看不出错乱，只是"没有纹理"）。
UvRect _flatUv(int stateId, BlockFace face) => const UvRect(0, 0, 1, 1);

/// 一个段的三层共享材质。
///
/// 原版对应物：`client.renderer.RenderType` 的层语义（opaque / cutout / translucent）。
/// **全场景共享一份**：材质是"贴图 + alpha 处理 + 采样状态"的组合，逐段新建会让材质
/// 实例随加载区块线性增长，既浪费显存也打散合批。
///
/// 贴图来自预拼接图集（`generated/block_atlas.png`，整图 + 逐面 UV 采样）；资源包
/// 缺失时退化为顶点色（承载面朝向明暗），观感有体积感但没有纹理。
class _SectionMaterials {
  _SectionMaterials(TextureSource? atlas)
      : opaque = _build(AlphaMode.opaque, atlas),
        cutout = _build(AlphaMode.mask, atlas),
        translucent = _build(AlphaMode.blend, atlas);

  final PhysicallyBasedMaterial opaque;
  final PhysicallyBasedMaterial cutout;
  final PhysicallyBasedMaterial translucent;

  static PhysicallyBasedMaterial _build(AlphaMode mode, TextureSource? atlas) {
    final material = PhysicallyBasedMaterial()
      ..metallicFactor = 0.0
      ..roughnessFactor = 1.0
      // 有贴图时基色由贴图给（明暗交给光照），无贴图时退化为顶点色（面朝向明暗）。
      ..vertexColorWeight = atlas == null ? 1.0 : 0.0;
    if (atlas != null) material.baseColorTexture = atlas;

    switch (mode) {
      case AlphaMode.opaque:
        break;
      case AlphaMode.mask:
        // 叶与十字植物：alpha 测试出镂空轮廓；双面渲染，否则树冠内部只剩单层壳。
        material
          ..alphaMode = AlphaMode.mask
          ..alphaCutoff = 0.4
          ..doubleSided = true;
      case AlphaMode.blend:
        // 水：走深度排序的 blend pass；alpha 让水下可见（原版观感取向，同 fscraft）。
        material
          ..alphaMode = AlphaMode.blend
          ..baseColorFactor = vm.Vector4(1.0, 1.0, 1.0, 0.6)
          ..doubleSided = true;
    }
    return material;
  }
}
