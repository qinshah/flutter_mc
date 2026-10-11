import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart'
    show PointerDeviceKind, PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart';
import 'package:mc_render/mc_render.dart';
import 'package:mc_session/mc_session.dart';
import 'package:mc_ui/mc_ui.dart';
import 'package:pointer_lock/pointer_lock.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'block_icon.dart';
import 'block_textures.dart';
import 'column_section_view.dart';
import 'engine_space.dart';
import 'package:flutter_mc/world/entity/player/input.dart';
import 'key_map.dart';
import 'package:flutter_mc/world/entity/player/player.dart';
import 'package:flutter_mc/world/entity/player/abilities.dart';
import 'package:flutter_mc/client/gui/gui.dart';
import 'package:flutter_mc/client/multiplayer/level_load_tracker.dart';
import 'package:flutter_mc/client/gui/screens/inventory/creative_mode_inventory_screen.dart';
import 'package:flutter_mc/client/mouse_handler.dart';
import 'package:flutter_mc/client/player/local_player.dart';
import 'package:flutter_mc/client/player/position_sync.dart';
import 'session_collision_world.dart';
import 'sky_model.dart';
import '../screens/screen.dart' show mcGuiScale;

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
  const GameScreen({
    super.key,
    required this.session,
    required this.events,
  });

  /// 装配点建好的会话句柄（`SessionAssembly.connectFor` 的产物）。
  /// 本屏是它的消费方：`dispose` 时负责关掉。
  final SessionHandle session;

  /// **已缓冲**的会话事件流（由加入流程转发；会话自身的流是 broadcast、不缓存，
  /// 直接订阅会丢掉进屏前到达的事件，包括初始位姿）。
  final Stream<SessionEvent> events;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

/// 最近输入来源（touch-input 能力；由指针设备类型驱动 hub 显隐）。
enum InputSource { touch, keyboardMouse }

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  final Scene _scene = Scene();
  final Player _player = Player();

  /// 已加载的列，键为 `(chunkX, chunkZ)`（邻居查询用）。
  ///
  /// **增删完全跟随会话事件**（ChunkLoaded/ChunkUnloaded）：列的持有/顶替/
  /// 卸载决策在会话侧的存储环（`ClientChunkCache`，判据 `ClientChunkCache.java`），
  /// 渲染端 MUST NOT 自行推断卸载。
  final Map<(int, int), RemoteChunkColumn> _columns = {};

  /// 登录期就绪状态机（判据 `LevelLoadTracker.java`）：就绪前不跑玩家物理、
  /// 不上行位置（原版 loading screen 期间玩家不 tick 的对位），就绪后发
  /// `ServerboundPlayerLoadedPacket` 放行服务端。就绪判据 = 玩家列的段已
  /// 网格化（或 30s 超时 / y 超界豁免）。一次性——与已拆除的"永续脚下列
  /// 门禁"（自造偏差）不同。
  final LevelLoadTracker _levelLoadTracker = LevelLoadTracker(
    minY: SessionCollisionWorld.kMinY,
    maxY: SessionCollisionWorld.kMaxY,
  );
  bool _worldReady = false;

  /// 服务器窗口几何（`ViewGeometryChanged`；判据 `ClientPacketListener.java:2314-2330`）。
  /// radius 为服务器语义半径（未 +3 换算）。供网格化优先级按 center 排序（未来）。
  (int, int) _viewCenter = (0, 0);
  int _viewRadius = 10;

  /// 已挂载的段节点，键为 `"chunkX,sectionY,chunkZ"`。
  final Map<String, Node> _sectionNodes = {};

  /// 方块语义的**查询缓存**（mc_render 自带）。必须复用同一个实例：语义查询是
  /// 网格化最热的一环（每格每面都要问），而 `BlockSemanticsV262` 每次都做
  /// stateId → 身份串的字符串解析 + contains/startsWith 判定。缓存后每个 stateId
  /// 只算一次。**注意**：不缓存时视距内几百列的网格化会把主 isolate 卡死（实测）。
  late MeshSemanticsCache _semantics =
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

  /// 输入与物理（3.2）：按键状态 → `Input` → `LocalPlayer` → 上行。
  final Input _input = Input();

  /// 服务器权威 abilities 快照（AbilitiesUpdated 事件驱动；player-input 切片）。
  final _abilities = Abilities();
  final Set<LogicalKeyboardKey> _pressed = {};
  final FocusNode _focus = FocusNode();
  late final LocalPlayer _controller;

  /// 位置上行（判据 `LocalPlayer.sendPosition:265-302` 的状态机）。
  final PositionSync _positionSync = PositionSync();

  // —— 游戏内屏幕与指针捕获（game-screens-touch-input）——

  /// 指针捕获（`MouseHandler.java` 对应物；真捕获走 pointer_lock，
  /// 降级平台由下方近似路径补）。
  late final MouseHandler _mouseHandler;

  /// 游戏内屏幕持有（`Gui.java` 对应物：单槽位 screen 状态）。
  late final Gui _gui;

  /// 窗口是否活跃（`isWindowActive()` 对应，grabMouse 门控用）。
  bool _appActive = true;

  /// 热键栏内容（最小实现：stateId 槽位，null = 空；完整 Inventory 类见债 §8）。
  final List<int?> _hotbar = List<int?>.filled(9, null);

  // —— 触控采集（touch-input 能力；自由设计，参考 fscraft game_page 口径）——

  /// 最近输入来源（touch-input spec：hub 显隐由它驱动）。
  /// **初始为 touch（hub 初始显示）**；检测到鼠标输入才隐藏——桌面插触屏 /
  /// 移动端插鼠标都成立，MUST NOT 依赖平台静态判断。
  InputSource _inputSource = InputSource.touch;


  late final PerspectiveCamera _camera;

  StreamSubscription<SessionEvent>? _events;
  bool _ready = false;
  bool _exiting = false;

  /// 诊断探针开关（`--dart-define=TRACE=true` 才生效）。
  static const bool _trace = bool.fromEnvironment('TRACE');
  double _traceAccum = 0;

  // —— 冻结诊断（2026-10-07：无条件心跳 + 关键路径计数，复现时贴日志用）——

  /// 心跳累计（每 1s 打一行 [BEAT]；心跳停 = Ticker 死，心跳在但不动 = 输入/门禁问题）。
  double _beatAccum = 0;
  int _beatTick = 0;

  /// 本秒收到的指针移动事件数（心跳里输出：冻结时区分"没事件"vs"事件没生效"）。
  int _pointerMoves = 0;

  /// 本秒网格化的段数 + 本秒上行包计数（会话侧回填通道，见 beat）。
  int _meshedThisSecond = 0;
  int _physicsStepsThisSecond = 0;

  /// 上行节流累计。原版每**刻**（20 Hz）上报一次移动，逐帧上报会把服务器的移动
  /// 校验打乱（实测服务器刷 moved too quickly）；这里按 20 Hz 发。
  double _uplinkAccum = 0;
  static const double _uplinkInterval = 1 / 20;

  /// 探针用：上行计数（每 20 次打一行）。
  int _sendTraceCount = 0;

  /// 探针用：逐包上行序号（[MOVE] 与 [WIRE>] 对齐用，2026-10-11 怼墙抽搐取证）。
  int _moveSendSeq = 0;
  bool _movePrevSet = false;
  double _movePrevX = 0, _movePrevY = 0, _movePrevZ = 0;

  /// 合成输入（`--dart-define=AUTOWALK=true|walk`）：端到端取证用——驱动 tap
  /// 模拟不了键盘，所以由调试开关直接注入"一直向前走 + 每 2 秒跳一下"。默认关。
  //
  // 【坑】2026-10-11：此处曾是 `bool.fromEnvironment('AUTOWALK')`，而
  // `--dart-define=AUTOWALK=walk` 的值 "walk" 不是合法 bool ⇒ 解析成 false
  // ⇒ walk 探针从未激活过（实测日志 move=(0,0)、phys=0）。改为 "true" 或
  // "walk" 都算开（const 表达式里 String.isNotEmpty 不可求值，只能显式判等）。
  static const bool _autoWalk =
      bool.fromEnvironment('AUTOWALK') ||
          String.fromEnvironment('AUTOWALK') == 'walk';


  /// AUTOWALK=walk：纯行走变体（不进飞行），专测台阶拒绝循环。
  static const bool _autoWalkWalkOnly =
      String.fromEnvironment('AUTOWALK') == 'walk';
  double _autoWalkTime = 0;

  /// 渲染二分开关（`--dart-define=RENDER_DEBUG=opaque`）：只挂 opaque 层。
  /// 用于判定"部分方块面渲染成深红"是**某一层材质**的问题还是贴图采样本身。
  static const String _renderDebug = String.fromEnvironment('RENDER_DEBUG');


  @override
  void initState() {
    super.initState();
    // 失焦清键需要生命周期回调（macOS 失焦后不再收 KeyUp ⇒ 按键永久卡"按下"）。
    WidgetsBinding.instance.addObserver(this);
    _controller = LocalPlayer(
      world: SessionCollisionWorld(_columns),
      player: _player,
      abilities: _abilities,
      onFlyingToggled: (flying) => widget.session.sendAbilities(flying: flying),
      // 判据 `LocalPlayer.sendIsSprintingIfNeeded`（:304-309）：加速态变化即上行。
      onSprintingChanged: (sprinting) =>
          widget.session.sendSprinting(sprinting: sprinting),
    );
    // —— Gui / MouseHandler 装配（判据链见各类文档）——
    _mouseHandler = MouseHandler(
      isWindowActive: () => _appActive,
      onLookDelta: (dx, dy) => _input.lookDelta.add(vm.Vector2(dx, dy)),
    );
    _gui = Gui(
      mouseHandler: _mouseHandler,
      releaseAllKeys: _releaseAllKeys,
      restoreToggleStatesOnScreenClosed: _restoreToggleStatesOnScreenClosed,
      guiScaledSize: _guiScaledSize,
      disconnectFromWorld: () => _exit('玩家断开连接'),
      onChanged: () {
        if (!mounted) return;
        setState(() {}); // 屏幕切换 → 重渲染覆盖层
        // 屏幕关闭 ⇒ 把主焦点交还游戏（否则覆盖层的 TextField 卸载后焦点
        // 落回 scope 而非本节点 ⇒ 键盘事件无人接收 ⇒ "动不了"）。
        if (_gui.screen() == null && !_focus.hasFocus) {
          _focus.requestFocus();
        }
      },
    );
    _mouseHandler.gui = _gui;
    // pointer_lock 被系统意外释放（Cmd+Tab 等）→ 等价失焦：清按键 + 复位捕获态
    //（判据包文档 "Treat an unrequested CaptureState.released as a reason to
    // pause"；原版 GLFW 失焦自动 releaseMouse，`MouseHandler.java:406/422`）。
    PointerLock.instance.onStateChanged.listen((state) {
      if (state == CaptureState.released) {
        _mouseHandler.onCaptureLostExternally();
        _releaseAllKeys();
        if (_trace) debugPrint('[KEY] 捕获被系统释放 → 清按键');
      }
    });
    _camera = PerspectiveCamera(
      position: vm.Vector3(0, 0, 0),
      target: vm.Vector3(0, 0, 1),
      fovNear: 0.05,
      fovFar: 1024,
    );
    _boot();
  }

  /// GUI 缩放尺寸（`getWindow().getGuiScaledWidth/Height` 对应：
  /// 窗口尺寸 ÷ 缩放档位，判据 `lib/screens/screen.dart` `mcGuiScale`）。
  ({int width, int height}) _guiScaledSize() {
    final size = MediaQuery.maybeSizeOf(context) ?? const Size(1280, 720);
    final s = mcGuiScale(size);
    return (width: (size.width / s).round(), height: (size.height / s).round());
  }

  /// 引擎静态资源（shader bundle）就绪后才能建几何与材质——早建出来的会静默不渲染。
  Future<void> _boot() async {
    await Scene.initializeStaticResources();

    // 几何 / 材质 / 天空都只能在静态资源就绪后构造（早建出来的会静默不渲染）。
    final textures = await BlockTextures.load();
    _blockTextures = textures;
    // 贴图是**按需**解析的：解析出一个新方块后，已用兜底 UV 网格化的段要重做。
    textures?.onResolved = _markAllSectionsDirty;
    // 分类判据（block-geometry B）：构建期扫全量模型，按 parent 链得出十字面片
    // 方块集，注入 semantics——取代原 40 项手写名单（判据缺失说明见
    // `BlockSemanticsV262` 类文档）。
    if (textures != null) {
      final cross = await textures.buildCrossBlockSet();
      // 真实几何（block-geometry A）：按模型 `elements` 的 AABB 出面，
      // 竹子/半砖/楼梯/藤蔓/睡莲不再被拉成整方块。判据 `CuboidModelElement.java:22`
      // + `FaceBakery.java:131`；带 rotation 的模型不注入（本网格器不支持旋转，
      // 见 `BlockGeometryMesh.hasUnsupportedRotation`），那些方块显式回退整方块。
      final geometry = await textures.buildGeometryMap();
      _semantics = MeshSemanticsCache(BlockSemanticsV262(
        crossBlocks: cross,
        geometryByState: geometry,
      ));
      if (_trace) {
        debugPrint('[SEM] 判据驱动的 cross 方块 ${cross.length} 个');
        debugPrint('[SEM] 真实几何 state ${geometry.length} 个；'
            '因rotation 未注入 ${textures.geometryRotationSkipped} 个');
      }
    }
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
        // 采样判据（原版 `client.renderer.texture`）：
        // - `TextureAtlas.java:83` 图集采样器 = `getClampToEdge(FilterMode.NEAREST)`
        //   ⇒ min=mag 均为 NEAREST + CLAMP_TO_EDGE——16px 贴图放大时保持像素棱角，
        //   这是原版"方块锐利"观感的来源；flutter_scene 默认 linear（双线性放大）会糊。
        // - `SamplerCache.java:21` createSampler(..., 1, ...) ⇒ 各向异性固定 1
        //   （flutter_scene 在任一 filter 为 nearest 时同样自动丢弃 aniso）。
        // - mip 层数 4：原版"mipmap"视频选项默认 4；16px sprite 到 level4 恰好
        //   1px/sprite，封顶以免更高层把相邻 sprite 平均成一团（fscraft 同值，
        //   flutter_scene 文档明确"图集用 maxMipmapLevels 防跨 tile 合并"）。
        // - `TextureAtlas.java:150` 原版把 mip 存为纹理数组按 NEAREST 逐层采样，
        //   硬件采样近似 = mipFilter nearest（级别选择最近，层内最近）。
        atlasTexture = await loadTexture(
          BlockTextures.atlasAssetPath,
          sampling: const TextureSampling(
            maxMipmapLevels: 4,
            minFilter: gpu.MinMagFilter.nearest,
            magFilter: gpu.MinMagFilter.nearest,
            mipFilter: gpu.MipFilter.nearest,
            addressMode: gpu.SamplerAddressMode.clampToEdge,
          ),
        );
      } catch (e) {
        if (_trace) debugPrint('[TEX] 贴图加载失败，退化为顶点色：$e');
      }
    }
    _materials = _SectionMaterials(atlasTexture);

    final skySource = GradientSkySource();
    _skySource = skySource;
    // 只设**可见天空**。
    //
    // 实拍判定：同时设 `skyEnvironment`（它接管 scene.environment 并按策略重烘 IBL）时，
    // 可见天空会被渲染成深红——正午（dayFraction=0.247、sunElev=1.00，SkyModel 算出的
    // zenith 是 (0.25,0.45,0.85) 蓝）也是红的；去掉 IBL/方向光绑定后天空即刻恢复蓝。
    // 故本版只保留 skybox，昼夜 IBL 与方向光（含阴影）留作后续切片，届时需先查清
    // SkyEnvironment 与 ShaderSkySource 混用时的可见天空来源。
    _scene.skybox = Skybox(skySource);
    _applySky();

    if (!mounted) return;
    _events = widget.events.listen(
      _onEvent,
      onDone: () => _exit('会话终止'),
      onError: (Object e) => _exit('会话异常：$e'),
    );
    setState(() => _ready = true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _events?.cancel();
    _focus.dispose();
    _mouseHandler.dispose();
    widget.session.close();
    super.dispose();
  }

  // —— 输入（Flutter 输入是本项目三处自由设计之一；键位照原版 KeyMapping） ——

  // —— 指针捕获（降级平台的近似；真捕获走 [_mouseHandler] 的 pointer_lock）——
  //
  // `MouseHandler.usesNativeLock == false` 的平台（Windows 上游未支持、
  // ohos/Android 无指针）没有原生捕获可用，保留"越界断流"近似并登记翻译债
  // （`openspec/progress.md` §10）。真捕获平台上以下近似路径全部旁路。

  /// 降级近似下"忽略下一次移动"（原版 `ignoreFirstMove` 口径）。
  bool _ignoreApproxMove = false;

  /// 指针移动 → 视角增量。
  ///
  /// 触控指针：拖动即转视角（自由设计——触屏无指针捕获）；鼠标指针：真捕获
  /// 平台在 [MouseHandler.pollMovement] 消费（此处旁路），降级平台走越界补偿。
  void _handlePointerMove(PointerMoveEvent event) {
    _pointerMoves++; // 心跳诊断：冻结时区分"没事件"vs"事件没生效"
    final isTouch = event.kind == PointerDeviceKind.touch ||
        event.kind == PointerDeviceKind.stylus;
    if (isTouch) {
      _noteSource(InputSource.touch);
      _input.lookDelta.add(vm.Vector2(event.delta.dx, event.delta.dy));
      return;
    }
    _noteSource(InputSource.keyboardMouse); // 鼠标输入 → 隐藏 hub
    if (_mouseHandler.usesNativeLock) return; // 真捕获：pollMovement 已消费
    if (_mouseHandler.isMouseGrabbed()) {
      final size = context.size;
      final last = _lastPointerPos;
      if (_ignoreApproxMove) {
        // 原版 `ignoreFirstMove`（`MouseHandler.java:415`）：抓指针/回中那一下
        // 不算视角转动。同时把参考点挪到当前位置，作为后续越界补偿的基准。
        _ignoreApproxMove = false;
        _lastPointerPos = event.position;
        if (_trace) debugPrint('[KEY] 忽略回中那一次移动（ignoreFirstMove）');
        return;
      }
      // **越界补偿**：指针抵达窗口边缘（贴边）时，把越过的那段位移反向加回去，
      // 等价于原版真指针锁下"光标被钉在中心、视角继续转"的体验。
      if (size != null && last != null && size.width > 0 && size.height > 0) {
        final atEdgeX = event.position.dx <= 0 ||
            event.position.dx >= size.width - 1;
        final atEdgeY = event.position.dy <= 0 ||
            event.position.dy >= size.height - 1;
        if (atEdgeX || atEdgeY) {
          // 从边缘回拉的位移方向与本帧位移方向相反 ⇒ 减掉它，视角就不会"粘住"。
          _input.lookDelta.sub(vm.Vector2(event.delta.dx, event.delta.dy));
          return;
        }
      }
      _lastPointerPos = event.position;
      _input.lookDelta.add(vm.Vector2(event.delta.dx, event.delta.dy));
    }
  }

  /// 失焦即释放全部按键（判据 `KeyMapping.releaseAll()`，`KeyMapping.java:57`）。
  ///
  /// **为什么必需**：macOS 窗口失焦后不再投递 KeyUp，`_pressed` 里的键会永久卡在
  /// "按下"态——这既是"键盘突然失效"的原因，也是系统"无效按键"提示音的来源
  ///（有 keyDown 无 keyUp 配对）。
  ///
  /// 注意 `RESTORE_KEY_STATE_AFTER_MOUSE_GRAB = !ON_OSX`（`InputQuirks.java:11`）
  /// ⇒ **macOS 原版在抓鼠标时也不重置按键**，靠的是别的路径兜住这个缺口；
  /// 我们在这里显式清，两边最终状态一致（全部松开）。
  void _releaseAllKeys() {
    if (!KeyMap.releaseAll(_pressed)) return; // 本来就没有按住键
    // 重算移动意图 ⇒ `Input` 全部回到"松开"，并同步一次上行，
    // 否则服务器仍认为玩家在前进。加速态由状态机在下一刻自动停止
    //（shouldStopRunSprinting：无前进冲动 ⇒ setSprinting(false) ⇒ 上行 STOP）。
    KeyMap.apply(_pressed, _input);
    // 全松开地同步一次上行（服务器据此停止把玩家视为前进中）。
    widget.session.sendInputFlags(
      forward: false,
      backward: false,
      left: false,
      right: false,
      jump: false,
      shift: false,
      sprint: false,
    );
    if (_trace) debugPrint('[KEY] 失焦释放全部按键');
  }

  /// 判据 `KeyMapping.restoreToggleStatesOnScreenClosed()`（`KeyMapping.java:63-69`）：
  /// 屏幕关闭时恢复"切换式按键"的激活态。本仓加速已改按住式（无 ToggleKeyMapping）
  /// ⇒ 无可恢复项；原版该回调同样只处理切换式按键。
  void _restoreToggleStatesOnScreenClosed() {}

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `resumed → inactive` 即 macOS 窗口失焦；其余非活跃态同理。
    _appActive = state == AppLifecycleState.resumed;
    if (state != AppLifecycleState.resumed) {
      _releaseAllKeys();
    }
  }

  void _onKey(KeyEvent event) {
    // 注意：屏幕打开时键盘已在 Focus.onKeyEvent 里路由给 screen（KeyDown/Repeat
    // → keyPressed、KeyUp → keyReleased，判据 `KeyboardHandler.java:483-503`
    // 分流），此处只会收到无屏时的游戏键位。
    if (KeyMap.update(_pressed, event)) {
      KeyMap.apply(_pressed, _input);
      // `Esc` → pauseGame（判据 `KeyboardHandler.java:534-537`：
      // handlesGlobalInput && event.isEscape() → minecraft.pauseGame()；
      // 联机恒 PauseScreen(true)，setPauseScreen 只在无屏时生效）。
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        _gui.pauseGame();
        if (_trace) debugPrint('[KEY] Esc → pauseGame');
      }
      // `E` → 物品栏（判据 `Minecraft.java:1869+1983`：handleKeybinds 仅在
      // 无屏时执行；keyInventory.consumeClick → setScreen(InventoryScreen)）。
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.keyE) {
        _openInventory();
      }
      // 数字键 1-9 → 热键栏（判据 `Minecraft.java:1969-1976`：
      // keyHotbarSlots[i].consumeClick() → inventory.setSelectedSlot(i)）。
      if (event is KeyDownEvent) {
        final digit = _digitIndex(event.logicalKey);
        if (digit != null) {
          _selectSlot(digit);
          if (_trace) debugPrint('[HOTBAR] 数字键 → 槽位 $digit');
        }
      }
      if (_trace && event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.space) {
        debugPrint('[KEY] space down（onGround=${_input.jump}）');
      }
    }
  }

  /// `Minecraft.handleKeybinds` 的 keyInventory 分支（判据 `:1983-1990`）。
  ///
  /// 差异（登记债）：原版生存模式打开生存 InventoryScreen、
  /// `isServerControlledInventory` 走 sendOpenInventory——两者均未实现，故
  /// 仅在 `mayfly`（创造能力）时打开创造物品栏，生存下 E 无操作。
  void _openInventory() {
    if (!_abilities.mayfly) {
      if (_trace) debugPrint('[INV] mayfly=false → E 无操作（生存物品栏未实现，债）');
      return;
    }
    _gui.setScreen(CreativeModeInventoryScreen(
      textures: _blockTextures,
      onPickItem: _onPickCreativeItem,
    ));
  }

  /// 创造点选：替换当前选中槽位 + 上行（判据
  /// `MultiPlayerGameMode.java:491-495`：hasInfiniteMaterials 才发
  /// `ServerboundSetCreativeModeSlotPacket(slot, stack)`——门控在会话侧）。
  void _onPickCreativeItem(String blockName, int itemId, int stateId) {
    final slot = _player.inventory.getSelectedSlot();
    if (slot < 0 || slot >= _hotbar.length) return;
    _hotbar[slot] = stateId; // 本地：替换当前拿的东西
    widget.session.sendCreativeModeSlot(
      slot: slot,
      itemId: itemId,
      count: 1,
    );
    // **必须 setState**：_hotbar 是普通 List，不改 UI 不会重建 ⇒ 热键栏图标
    // 不出现（2026-10-07 实机：物品栏状态更新未完全修复的残留）。
    if (mounted) setState(() {});
    if (_trace) debugPrint('[INV] 点选 $blockName → 槽位 $slot（itemId=$itemId）');
  }

  /// 切换选中槽位（判据 `Inventory.setSelectedSlot`）并**即时刷新 HUD**——
  /// 数字键/滚轮/点选三条路都走这里，否则热键栏高亮不更新（2026-10-07 实机反馈）。
  void _selectSlot(int slot) {
    _player.inventory.setSelectedSlot(slot);
    if (mounted) setState(() {});
  }

  /// 数字键 1-9 → 槽位 0-8（判据 `Minecraft.java:1969-1976` keyHotbarSlots）。
  static int? _digitIndex(LogicalKeyboardKey key) {
    const digits = [
      LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3, LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5, LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7, LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
    ];
    final i = digits.indexOf(key);
    return i < 0 ? null : i;
  }

  /// 滚轮切槽（判据 `MouseHandler.onScroll:208-215` +
  /// `ScrollWheelHandler.getNextScrollWheelSelection:31-42`：
  /// step = signum(wheel)；current -= step；负数回绕 +9、超界回绕 -9。
  /// Flutter 的 scrollDelta.dy 正 = 向下滚 = 原版 wheel 负）。
  void _onScroll(double scrollDeltaDy) {
    if (_gui.screen() != null) return; // :207 屏幕打开 → 归屏幕
    final wheel = scrollDeltaDy > 0 ? -1.0 : 1.0; // 原版 yoffset 正 = 上滚
    final step = wheel.sign.toInt();
    var selected = _player.inventory.getSelectedSlot() - step; // :33
    selected = selected < -1 ? -1 : selected; // :34
    while (selected < 0) {
      selected += 9; // :36-38（Inventory.getSelectionSize = 9）
    }
    while (selected >= 9) {
      selected -= 9; // :39-41
    }
    _selectSlot(selected);
    if (_trace) debugPrint('[HOTBAR] 滚轮 → 槽位 $selected');
  }

  /// 触控 Esc（瞬时语义）：无屏开暂停 / 有屏关屏
  /// （判据 `KeyboardHandler.java:534` + `Screen.java:202` 同一条链）。
  void _onVirtualEscape() {
    final screen = _gui.screen();
    if (screen != null) {
      screen.onClose();
    } else {
      _gui.pauseGame();
    }
  }

  /// 触控 E（瞬时语义）：无屏开物品栏 / 有屏关屏
  /// （判据 `Minecraft.java:1983` + `AbstractContainerScreen.java:486-489`）。
  void _onVirtualInventory() {
    final screen = _gui.screen();
    if (screen != null) {
      screen.onClose();
    } else {
      _openInventory();
    }
  }

  /// 触控按钮 → 键位等价按下/抬起（touch-input spec：与键盘同一条
  /// KeyMapping 路径，MUST NOT 形成第二套输入状态）。
  void _setVirtualKey(LogicalKeyboardKey key, bool down) {
    final changed = down ? _pressed.add(key) : _pressed.remove(key);
    if (!changed) return;
    KeyMap.apply(_pressed, _input);
  }

  /// 上一次已知的指针位置（窗口坐标，Flutter 的 [Offset]），用于检测越界。
  Offset? _lastPointerPos;

  /// 会话事件 → 场景。
  //
  // 事件来自 worker isolate，但 `SessionHandle.events` 是主 isolate 上的流
  // （isolate 边界由 mc_session 收口），所以这里可以直接改场景。

  void _onEvent(SessionEvent event) {
    try {
      _onEventInner(event);
    } catch (e, st) {
      // **不静默**：完整堆栈。区块事件处理抛异常不该杀掉会话订阅。
      debugPrint('[EVENT] 事件处理异常（$event）：$e\n$st');
    }
  }

  void _onEventInner(SessionEvent event) {
    switch (event) {
      case JoinedGame():
        // 进服成功；启动登录期就绪状态机（判据 `LevelLoadTracker.java`
        // `startClientLoad`，:40-43——原版在玩家实体创建时调用）。
        _levelLoadTracker.startClientLoad();
        break;

      case LevelChunksLoadStart():
        // 服务器开始下发出生区块（判据 `ClientPacketListener.java:1551-1553`
        // → `loadingPacketsReceived()`）：状态机进入"等待玩家列"阶段。
        _levelLoadTracker.loadingPacketsReceived();
        break;

      case AbilitiesUpdated(
          :final mayfly,
          :final flying,
          :final flyingSpeed,
          :final walkingSpeed
        ):
        _abilities
          ..mayfly = mayfly
          ..flyingSpeed = flyingSpeed
          // 判据 `Player.java:639`：
          //   setBaseValue(abilities.getWalkingSpeed()) ⇒ MOVEMENT_SPEED
          // 而水平飞行速度 = `getSpeed() × 0.1`（`LivingEntity.java:2707`）
          // ⇒ **walkingSpeed 决定水平飞行快慢**，必须透传。
          ..walkingSpeed = walkingSpeed;
        debugPrint('[ABIL] mayfly=$mayfly flying=$flying '
            'flySpeed=$flyingSpeed walkSpeed=$walkingSpeed');
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
          // 【取证】服务器拒绝时，转储客户端本地 3×3×3 网格的身份串——
          // 与服务器几何比对，锁定分歧格。
          final px = _player.position.x.floor();
          final py = _player.position.y.floor();
          final pz = _player.position.z.floor();
          final buf = StringBuffer('[GRID] ($px,$py,$pz)');
          String short(String? id) {
            if (id == null) return '?';
            final noNs = id.substring(id.indexOf(':') + 1);
            final br = noNs.indexOf('[');
            return br < 0 ? noNs : noNs.substring(0, br);
          }

          for (var dy = 1; dy >= -1; dy--) {
            buf.write(' | y${py + dy}:');
            for (var dz = -1; dz <= 1; dz++) {
              for (var dx = -1; dx <= 1; dx++) {
                buf.write(short(_controller.world.blockIdentityAt(px + dx, py + dy, pz + dz)));
                buf.write(',');
              }
            }
          }
          debugPrint(buf.toString());
        }
        // 服务器权威位姿（相对标志已在会话侧解成绝对值）；直接采信并清速度。
        // 【2026-10-11】此前实测"抽搐"曾疑回拉，诊断确认根因 = 漏发
        // ClientTickEnd（服务器 knownMovement 状态机失配致位置漂移→拒绝循环），
        // sendMovePlayer 补发后恢复正常回拉响应（原版权威位姿语义）。
        _player.setPos(x, y, z);
        // 原版 setDeltaMovement(newValues.deltaMovement())：速度也以服务器下发为准。
        _player.velocity.setValues(dx, dy, dz);
        // 原版 yaw 0 = 朝 +Z（度）；本应用 yaw 0 = 朝 -Z（弧度）——逆变换。
        _player.yaw = (180.0 - yRot) * math.pi / 180.0;
        _player.pitch = xRot * math.pi / 180.0;

      case ChunkLoaded(:final chunk):
        // 无条件留痕（诊断"加载的不是最近的区域"）：列坐标 + 离玩家距离。
        debugPrint('[CHUNK] load (${chunk.x},${chunk.z}) '
            'dist=${(chunk.x - _player.position.x / 16).abs().toStringAsFixed(1)},'
            '${(chunk.z - _player.position.z / 16).abs().toStringAsFixed(1)} '
            'cols=${_columns.length + 1}');
        _mountColumn(chunk);

      case ChunkUnloaded(:final x, :final z):
        // 无条件留痕：卸载脚下列/眼前列是冻结头号嫌疑。
        final standing = (x, z) ==
            (_player.position.x.floor() >> 4, _player.position.z.floor() >> 4);
        debugPrint('[CHUNK] unload ($x,$z) '
            'dist=${(x - _player.position.x / 16).abs().toStringAsFixed(1)},'
            '${(z - _player.position.z / 16).abs().toStringAsFixed(1)} '
            '${standing ? '⚠️ 卸载的是脚下列！' : ''}cols=${_columns.length - 1}');
        _unmountColumn(x, z);

      case ViewGeometryChanged(
          :final centerX,
          :final centerZ,
          :final radius
        ):
        // 窗口几何（判据 `ClientPacketListener.java:2314-2330`）：存储环的
        // 收发边界由它决定（mc_session 侧已生效）；此处仅留痕 + 暂存字段，
        // 供网格化优先级未来按 center 排序。
        _viewCenter = (centerX, centerZ);
        _viewRadius = radius;
        debugPrint('[VIEW] center=($centerX,$centerZ) radius=$radius');

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

  /// 按帧预算消费脏队列——**最近优先**：每帧从待网格化集合里挑离玩家最近
  /// 的段（2026-10-07 实机：高速飞行时 FIFO 会让眼前的新段排在大量
  /// 邻居重网格化之后，表现为"眼前的区域半天不出来、远处的先加载"）。
  /// 一次调用是同步的，不会与事件交错。
  void _processDirty() {
    var budget = _meshBudgetPerFrame;
    while (budget > 0 && _dirtyQueue.isNotEmpty) {
      final px = _player.position.x;
      final pz = _player.position.z;
      (int, int, int)? best;
      var bestD = double.infinity;
      var bestIdx = -1;
      for (var i = _dirtyCursor; i < _dirtyQueue.length; i++) {
        final (x, y, z) = _dirtyQueue[i];
        // 段中心到玩家的水平距离²（粗排足够）。
        final dx = x * 16 + 8 - px;
        final dz = z * 16 + 8 - pz;
        final d = dx * dx + dz * dz;
        if (d < bestD) {
          bestD = d;
          best = _dirtyQueue[i];
          bestIdx = i;
        }
      }
      if (best == null) break;
      // swap-remove：把选中项换到游标位，游标前移（避免 O(n) 删除）。
      _dirtyQueue[bestIdx] = _dirtyQueue[_dirtyCursor];
      _dirtyQueue[_dirtyCursor] = best;
      _dirtyCursor++;
      _dirtySet.remove(best);
      _remeshSection(best.$1, best.$2, best.$3);
      _meshedThisSecond++;
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
    // 清掉该列自己的待网格化条目（列已卸载 ⇒ 条目只会空跑占预算；2026-10-07
    // 实机：高速飞行时脏队列被过期条目塞满，眼前的段被饿死）。
    final stale = _dirtyQueue
        .where(((int, int, int) e) => e.$1 == chunkX && e.$3 == chunkZ)
        .toList();
    for (final e in stale) {
      _dirtyQueue.remove(e);
      _dirtySet.remove(e);
    }
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
  ///
  /// 单段隔离：一段坏数据（异常 state/网格）抛异常曾打停 SceneView 的
  /// Ticker（2026-10-07 实机：移动与视角冻结而 E/Esc 仍响应）——这里接住、
  /// 完整打日志（含段坐标与堆栈）并跳过该段，根因仍要按日志修。
  void _remeshSection(int chunkX, int sectionY, int chunkZ) {
    try {
      _remeshSectionInner(chunkX, sectionY, chunkZ);
    } catch (e, st) {
      debugPrint('[MESH] 段 ($chunkX,$sectionY,$chunkZ) 网格化失败：$e\n$st');
    }
  }

  void _remeshSectionInner(int chunkX, int sectionY, int chunkZ) {
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
    if (_renderDebug == 'normals') {
      // v14 表面通道调试：把所有材质换成 worldNormal 输出，直读正面/背面。
      _scene.debug.view = const DebugView(channel: SurfaceDebugChannel.worldNormal);
    }
    if (_renderDebug != 'opaque') {
      addLayer(mesh.cutout, materials.cutout);
      addLayer(mesh.translucent, materials.translucent);
    }

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
    // **心跳放在 try 外**：inner 抛异常被接住后心跳仍要继续——复现冻结时看
    // [BEAT] 是否还在打：停了 = Ticker 本身死了（渲染期异常，看 [UNCAUGHT]）；
    // 还在打但不动 = 输入/门禁/物理路径问题，对照行内字段定位。
    _beatTick++;
    _beatAccum += dt;
    if (_beatAccum >= 1.0) {
      _beatAccum = 0;
      _beat();
    }
    try {
      _onTickInner(elapsed, dt);
    } catch (e, st) {
      // **不静默**：完整堆栈。SceneView 的 Ticker 回调直接调 onTick
      //（flutter_scene scene_view.dart:581），回调抛异常会打停 Ticker ⇒
      // 相机与移动同时冻结而 UI 仍活着（2026-10-07 实机复现）。
      // 这里接住保活循环，把错误完整打出来定位根因。
      debugPrint('[TICK] tick 异常（ticker 保活）：$e\n$st');
    }
  }

  /// 每秒一行的心跳（无条件，不依赖 _trace）。
  void _beat() {
    final look = _input.lookDelta;
    debugPrint('[BEAT] #$_beatTick '
        'pos=(${_player.position.x.toStringAsFixed(1)},'
        '${_player.position.y.toStringAsFixed(1)},'
        '${_player.position.z.toStringAsFixed(1)}) '
        'yaw=${_player.yaw.toStringAsFixed(2)} '
        'lookAccum=(${look.x.toStringAsFixed(1)},${look.y.toStringAsFixed(1)}) '
        'move=(${_input.move.x.toStringAsFixed(0)},${_input.move.y.toStringAsFixed(0)}) '
        'jump=${_input.jump} sprint=${_input.sprint} '
        'pressed=${_pressed.length} '
        'grabbed=${_mouseHandler.isMouseGrabbed()} '
        'nativeLock=${_mouseHandler.usesNativeLock} '
        'ptrMoves=$_pointerMoves '
        'cols=${_columns.length} '
        'view=($_viewCenter,$_viewRadius) '
        'dirty=${_dirtyQueue.length - _dirtyCursor} '
        'meshed=$_meshedThisSecond '
        'phys=$_physicsStepsThisSecond');
    _pointerMoves = 0;
    _meshedThisSecond = 0;
    _physicsStepsThisSecond = 0;
  }

  void _onTickInner(Duration elapsed, double dt) {
    // 0) 相对位移消费（判据 turnPlayer 路径；真捕获平台取 pointer_lock 增量，
    //    降级平台不动——近似路径在 onPointerMove 里直接加）。
    _mouseHandler.pollMovement();

    // 0) 摊还网格化（每帧限额，避免地形涌入时卡住输入与渲染）。
    _processDirty();

    // 0.0) 登录期就绪状态机（判据 `LevelLoadTracker.java`）：就绪前不跑物理、
    // 不上行——原版 loading screen 期间玩家不 tick 的对位。就绪即发
    // PlayerLoaded 放行服务端并开始物理。**一次性**——与已拆除的永续门禁
    // （自造偏差）判据不同。
    if (!_worldReady) {
      final cx = _player.position.x.floor() >> 4;
      final cz = _player.position.z.floor() >> 4;
      // 原版判据 = **相机所在段**已编译（LevelRenderer.java:272-275：
      // isSectionCompiledAndVisible(cameraPos) → playerSectionReady.set(true)，
      // AtomicBoolean 一次性——之后邻居到达的重网格化**不会撤销**）。
      // 本侧对应 = 该段的 mesh 节点已建出（_remeshSection 同步换新，
      // node 一旦存在即编译完成过）。
      // 【2026-10-12 坑】旧实现等"整列全部段且不在脏集合"——邻居列到达会
      // 不断把玩家段重新标脏 ⇒ 条件实际是"全窗口网格化完毕" ⇒ 每次都吃满
      // 30s 超时才就绪（原版几秒，实测差近 1 分钟）。
      var sectionReady = false;
      if (_columns.containsKey((cx, cz))) {
        final sectionY = _player.position.y.floor() >> 4;
        sectionReady = _sectionNodes.containsKey('$cx,$sectionY,$cz');
      }
      _levelLoadTracker.tick(
        playerSectionReady: sectionReady,
        playerY: _player.position.y.floor(),
        // 相机 y（判据 WaitingForPlayerChunk.isReady 用 cameraPos，
        // LevelLoadTracker.java:125；眼高 1.62 = AABB.EYE_HEIGHT）。
        cameraY: (_player.position.y + 1.62).floor(),
      );
      if (_levelLoadTracker.shouldNotifyPlayerLoaded()) {
        _worldReady = true;
        widget.session.sendPlayerLoaded();
        debugPrint('[LOAD] 世界就绪，PlayerLoaded 已上行（'
            'cols=${_columns.length}）');
      } else {
        _cameraSync();
        return;
      }
    }

    // 0.5) 合成输入（仅调试开关开启时）。
    if (_autoWalk) {
      _autoWalkTime += dt;
      // 恒向直走（2026-10-12 用户口径：一直朝一个方向、不跳即可触发传送抽搐；
      // 旧版"螺旋转向 + 每 2 秒跳 + 疾跑"引入了多余变量，取证序列更难复算）。
      _input
        ..move.y = 1 // 一直向前（yaw 恒定 = 出生朝向，不再每帧旋转）
        ..jump = false
        ..sprint = false;
      // 3 秒后进创造飞行（服务器已下发 mayfly），复现高速跑图场景。
      // AUTOWALK=walk 变体：**永不飞行**——纯行走，专测水平拒绝循环。
      if (_autoWalkWalkOnly) {
        _controller.flying = false;
      } else if (_autoWalkTime > 3 && !_controller.flying) {
        _controller.flying = true;
        widget.session.sendAbilities(flying: true);
      }
    }

    // 1) 本地预测：物理推进（固定步长；dt 是渲染帧间隔）。
    _controller.tick(dt, _input);
    _physicsStepsThisSecond++;

    // 1.1) 位置上行（判据 `LocalPlayer.tick:246` sendPosition——在 super.tick()
    // 之后每 tick 调用，变体判定即其逐行翻译）。无条件运行：服务器的"相信位置"
    // 是区块流窗口的圆心（ChunkMap.updateChunkTracking），缺它窗口就停在旧位置。
    _positionSync.tick(
      player: _player,
      yawDeg: 180.0 - _player.yaw * 180.0 / math.pi, // 原版 yRot 逆变换
      pitchDeg: _player.pitch * 180.0 / math.pi,
      horizontalCollision: _controller.horizontalCollision,
      send: (variant, x, y, z, yRot, xRot, onGround, hCol) {
        // 【取证】逐包上行记录（与 [WIRE<] 回拉逐条对齐，锁定 gate2 拒绝的
        // 上行目标值）。坐标用 Dart toString（最短往返表示，round-trip 无损）：
        // 6 位小数无法区分"精确贴面 -291.7"与"微穿透 -291.7000016"，这是
        // 2026-10-11 run4 取证的盲点；Δ 为与上一包的差，供对齐单刻速度上限。
        if (_trace) {
          final dxx = _movePrevSet ? x - _movePrevX : 0.0;
          final dyy = _movePrevSet ? y - _movePrevY : 0.0;
          final dzz = _movePrevSet ? z - _movePrevZ : 0.0;
          debugPrint('[MOVE] #${++_moveSendSeq} v=$variant '
              '($x,$y,$z) Δ($dxx,$dyy,$dzz) '
              'onGround=$onGround hCol=$hCol');
          _movePrevSet = true;
          _movePrevX = x; _movePrevY = y; _movePrevZ = z;
        }
        widget.session.sendMovePlayer(
          variant: variant.index,
          x: x,
          y: y,
          z: z,
          yRot: yRot,
          xRot: xRot,
          onGround: onGround,
          horizontalCollision: hCol,
        );
      },
    );

    // 1.2) 手持槽位 ensure 上行（判据 `MultiPlayerGameMode.tick:305-307` →
    // `ensureHasSentCarriedItem:317-323`：变化才发 SetCarriedItem）。
    widget.session.sendCarriedItem(
        slot: _player.inventory.getSelectedSlot());

    // 1.5) 输入标志上行（isolate 内 lastSentInput 去重；player-input 切片）。
    widget.session.sendInputFlags(
      forward: _input.move.y > 0,
      backward: _input.move.y < 0,
      left: _input.move.x < 0,
      right: _input.move.x > 0,
      jump: _input.jump,
      shift: _input.shift,
      sprint: _input.sprint,
    );

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
          'yaw=${_player.yaw.toStringAsFixed(2)} '
          '看=${_lookBlockName()} '

          'gameTime=${_sky.gameTime} day=${_sky.dayFraction.toStringAsFixed(3)} '
          'sunElev=${_sky.sunElevation.toStringAsFixed(2)}',
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
        // 【取证】第二条 20 Hz 上行路径的逐包记录（与 [MOVE] 同格式，
        // tag 区分；两条路径交错上行，须各自留痕才能对齐回拉）。
        debugPrint('[MOVE2] #${++_moveSendSeq} v=cmd '
            '(${_player.position.x.toStringAsFixed(6)},'
            '${_player.position.y.toStringAsFixed(6)},'
            '${_player.position.z.toStringAsFixed(6)}) '
            'onGround=${_player.onGround}');
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

  /// 调试射线：沿视线步进找第一个实体方块，返回「坐标 stateId 方块名」。
  ///
  /// 用于判定"画面里的红色是新结构的方块本色，还是贴图/材质缺陷"——直接看命中的
  /// 是哪种方块名即可（天然红色方块 vs 石头/泥土这类普通方块）。
  String _lookBlockName() {
    final world = SessionCollisionWorld(_columns);
    final eye = _player.eyePosition;
    final dir = _player.lookDirection;
    for (var t = 0.5; t < 24.0; t += 0.25) {
      final bx = (eye.x + dir.x * t).floor();
      final by = (eye.y + dir.y * t).floor();
      final bz = (eye.z + dir.z * t).floor();
      final state = world.stateAtBlock(bx, by, bz);
      if (state == null || state == 0) continue;
      if (!world.isCollidable(bx, by, bz)) continue;
      return '($bx,$by,$bz)#$state:${BlockSemanticsV262.blockNameOf(state)}';
    }
    return '无命中';
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
    // 拦截系统返回手势/返回键充当 Esc（判据 fscraft `game_page.dart:736-741`
    // PopScope 口径；Java 语义同 KeyboardHandler Esc 链——无屏开暂停、有屏关屏）。
    // 游戏内屏幕不走 Navigator 子路由 ⇒ 无滑动返回样式问题。
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _onVirtualEscape();
      },
      child: Scaffold(
      backgroundColor: const Color(0xFF87CEEB), // 3.3 接昼夜天空前的占位底色
      // **用 `Focus` 而不是 `KeyboardListener`**：后者在
      // `keyboard_listener.dart:77` 无条件 `return KeyEventResult.ignored`，
      // 文档明说 ignored 会 "propagated to other key event handlers,
      // **even non-Flutter ones**" ⇒ 每个按键都漏回 macOS ⇒ 系统 beep
      // （用户实机："按任何键都发无效键盘输入声"，2026-10-07）。
      // `Focus.onKeyEvent` 能返回 `handled` 阻断冒泡，语义等价于原版 GLFW 的
      // 独占消费（`KeyMapping.click/set` 走 GLFW 回调，不回灌系统）。
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: (node, event) {
          // 屏幕打开 ⇒ 键归屏幕（KeyDown/Repeat → keyPressed、KeyUp →
          // keyReleased）；屏幕不处理的键返回 **ignored**——覆盖层里的
          // 搜索框等文本输入需要这些事件（返回 handled 会吞掉输入）。
          final screen = _gui.screen();
          if (screen != null) {
            final handled = event is KeyUpEvent
                ? screen.keyReleased(event)
                : screen.keyPressed(event);
            return handled
                ? KeyEventResult.handled
                : KeyEventResult.ignored;
          }
          _onKey(event);
          // 让 macOS 的 Esc 仍能退出全屏：系统级组合键交回平台。
          final sysCombo = HardwareKeyboard.instance.isControlPressed ||
              HardwareKeyboard.instance.isMetaPressed;
          if (sysCombo && event.logicalKey == LogicalKeyboardKey.escape) {
            return KeyEventResult.ignored;
          }
          return KeyEventResult.handled;
        },
        child: Stack(
          children: [
            // —— ① 场景层：指针位移 → 视角 ——
            Listener(
              behavior: HitTestBehavior.opaque,
              onPointerMove: _handlePointerMove,
              onPointerSignal: (signal) {
                // 滚轮切槽（判据 `MouseHandler.onScroll`，fscraft 同款接线）。
                if (signal is PointerScrollEvent) {
                  _onScroll(signal.scrollDelta.dy);
                }
              },
              // 降级近似：指针越界断流判定（真捕获平台旁路）。
              onPointerHover: (event) {
                _noteSource(InputSource.keyboardMouse); // 鼠标输入 → 隐藏 hub
                if (_mouseHandler.usesNativeLock) return;
                if (!_mouseHandler.isMouseGrabbed()) return;
                final size = context.size;
                if (size == null || size.width <= 0 || size.height <= 0) return;
                final pos = event.position;
                final center = Offset(size.width / 2, size.height / 2);
                // 越界深度（>0 说明指针在边界外侧）。
                final overshoot = Offset(
                    (pos.dx - center.dx).abs(), (pos.dy - center.dy).abs());
                final atEdge = overshoot.dx >= size.width / 2 ||
                    overshoot.dy >= size.height / 2;
                if (!atEdge) {
                  _lastPointerPos = pos;
                  return;
                }
                // 指针重新进入 ⇒ 回中并忽略这一次移动（原版 `ignoreFirstMove`）。
                _lastPointerPos = center;
                _ignoreApproxMove = true;
                if (_trace) {
                  debugPrint('[KEY] 指针回中(${overshoot.dx.toStringAsFixed(0)},'
                      '${overshoot.dy.toStringAsFixed(0)}) → 忽略该次移动');
                }
              },
              // 点击游戏区：抢回焦点 + 重新捕获（判据 `MouseHandler.java:80-88`：
              // 无屏且未捕获时按下即 grabMouse；屏幕打开时归屏幕处理）。
              onPointerDown: (event) {
                _notePointerSource(event);
                if (!_focus.hasFocus) {
                  _focus.requestFocus();
                  if (_trace) debugPrint('[KEY] 点击游戏区 → 抢回焦点');
                }
                final grabbed = _mouseHandler.onButton(true);
                if (grabbed) {
                  // 近似路径的回中基准（真捕获路径无需）。
                  _ignoreApproxMove = true;
                  final size = context.size;
                  _lastPointerPos = size == null
                      ? null
                      : Offset(size.width / 2, size.height / 2);
                }
              },
              onPointerUp: (event) => _mouseHandler.onButton(false),
              child: SceneView(_scene, camera: _camera, onTick: _onTick),
            ),

            // —— ②b 热键栏 HUD（判据 `Hud` 底部居中 hotbar；数字键/滚轮/
            //    点选的判据见 _onKey/_onScroll；屏幕打开时被覆盖层遮住）——
            Positioned(
              left: 0,
              right: 0,
              bottom: 8,
              child: IgnorePointer(
                ignoring: _gui.screen() != null,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 槽位 = 组件宽度 1/14（钳制 28..56），随窗口自适应。
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final slot =
                            (constraints.maxWidth / 14).clamp(28.0, 56.0);
                        return MCHotbar(
                          icons: [
                            for (final stateId in _hotbar)
                              stateId == null
                                  ? null
                                  : BlockIcon(
                                      stateId: stateId,
                                      textures: _blockTextures,
                                      size: slot * 0.8,
                                    ),
                          ],
                          selectedIndex: _player.inventory.getSelectedSlot(),
                          onSelect: _selectSlot,
                          slotSize: slot,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            // —— ③ 十字准星（判据 `Hud.java:447` 居中 + `RenderPipelines.java:798`
            //    BlendFunction.INVERT 反色混合；屏幕打开时隐藏，同原版 HUD 门控）——
            if (_gui.screen() == null) const Crosshair(),

            // —— ③b 触控 hub（**置于暂停菜单覆盖层之下**，用户约定 2026-10-07；
            //    关闭菜单用键盘 Esc 或菜单内「回到游戏」按钮）——
            if (_inputSource == InputSource.touch)
              TouchHub(
                bindings: TouchHubBindings(
                  onForward: (d) => _setVirtualKey(LogicalKeyboardKey.keyW, d),
                  onBack: (d) => _setVirtualKey(LogicalKeyboardKey.keyS, d),
                  onLeft: (d) => _setVirtualKey(LogicalKeyboardKey.keyA, d),
                  onRight: (d) => _setVirtualKey(LogicalKeyboardKey.keyD, d),
                  onJump: (d) => _setVirtualKey(LogicalKeyboardKey.space, d),
                  onSneak: (d) =>
                      _setVirtualKey(LogicalKeyboardKey.shiftLeft, d),
                  onEscape: _onVirtualEscape,
                  onInventory: _onVirtualInventory,
                ),
              ),

            if (_gui.screen() != null)
              Positioned.fill(
                child: _gui.screen()!.buildWidget(context),
              ),

          ],
        ),
      ),
      ),
    );
  }

  /// 最近输入来源检测（touch-input spec：`PointerDeviceKind.touch/stylus` →
  /// touch，判据 fscraft `game_page.dart:441-446` 口径；MUST NOT 依赖平台静态
  /// 判断——同一桌面平台可外接触屏）。
  void _noteSource(InputSource source) {
    if (source != _inputSource && mounted) {
      setState(() => _inputSource = source);
    }
  }

  void _notePointerSource(PointerDownEvent event) {
    final isTouch = event.kind == PointerDeviceKind.touch ||
        event.kind == PointerDeviceKind.stylus;
    _noteSource(
        isTouch ? InputSource.touch : InputSource.keyboardMouse);
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
