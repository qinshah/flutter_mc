import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

/// 天空/太阳的纯数学模型：时间 → 太阳方向 + 天空配色 + 光强。
///
/// 原版对应物（判据 `mc-sources/minecraft-26.2`）：
/// - `client.renderer.SkyRenderer` —— 用太阳角度旋转天体、按天色渲染天空
/// - `world.timeline.Timelines.OVERWORLD_DAY` —— 日周期的权威定义：
///   `setPeriodTicks(24000)`，`SUN_ANGLE` 轨道在正午（tick 6000）取值、一整天转 360°；
///   时刻标记 DAY=1000 / NOON=6000 / NIGHT=13000 / MIDNIGHT=18000
///
/// **时间源是服务器**（会话的 `TimeUpdated`，约每秒一次 SetTime），不是本地累加：
/// 原版的日周期同样由服务器 `levelTime` 驱动，客户端只做插值。`gameTime` 即原版
/// 世界时间（tick），故 [dayFraction] = `(gameTime % 24000) / 24000` ——
/// 0 = 日出（06:00，太阳在东）、0.25 = 正午、0.5 = 日落、0.75 = 午夜。
///
/// **本文件不 import flutter_scene**：只把数学算清楚，交给 app 壳喂给引擎
/// （`GradientSkySource`），也便于无 GPU 单测。
///
/// 简化点（标注）：太阳角度按 [dayFraction] **线性**推进，原版对 `SUN_ANGLE` 轨道
/// 施加了 `EasingType.symmetricCubicBezier(0.362, 0.241)` 缓动（太阳在正午/午夜附近
/// 走得慢）；配色是移植自 fscraft 的手调色板，未照搬原版 `SKY_COLOR` /
/// `SUNRISE_SUNSET_COLOR` 的关键帧轨道。
class SkyModel {
  SkyModel({this.gameTime = kDefaultGameTime});

  /// 一天的 tick 数（原版 `Timelines.OVERWORLD_DAY` 的 period）。
  static const int kTicksPerDay = 24000;

  /// 尚无服务器时间时的缺省时刻：正午（原版 `ClockTimeMarkers.NOON` = 6000）。
  static const int kDefaultGameTime = 6000;

  /// 服务器世界时间（tick，可跨天累加）。**原样保存**，取模在 [dayFraction] 里做。
  int gameTime;

  /// 服务器时间同步（`TimeUpdated.gameTime`）。原版语义：时间可回退（`/time set`
  /// 或切换维度），所以这里直接覆盖而不是取最大值。
  void setGameTime(int gameTime) => this.gameTime = gameTime;

  /// 当前时刻 ∈ [0,1)。取模必须对负数也正确（原版时间不会为负，但防御一下）。
  double get dayFraction {
    final t = gameTime % kTicksPerDay;
    return (t < 0 ? t + kTicksPerDay : t) / kTicksPerDay;
  }

  /// 太阳高度角的正弦：0 = 地平线，1 = 天顶，-1 = 正下方。**明暗的唯一依据。**
  double get sunElevation => math.sin(2 * math.pi * dayFraction);

  /// 是否为夜间（太阳在地平线下）。
  bool get isNight => sunElevation < 0;

  /// 朝向太阳的单位方向（**世界坐标**：+X 东、+Y 上、+Z 南；引擎空间转换由
  /// app 壳的 `directionToEngineSpace` 负责）。
  ///
  /// 太阳沿一条倾斜的大圆走（z 分量固定），避免正午正好穿过天顶导致竖直面全黑、
  /// 也避免日出日落方位抖动。
  Vector3 sunDirection() {
    final angle = 2 * math.pi * dayFraction;
    return Vector3(math.cos(angle), math.sin(angle), 0.25).normalized();
  }

  /// 环境光强度（0.16..1.0）。夜里留一个地板值，否则地形全黑没法玩。
  double get ambientIntensity {
    final t = _smoothstep(-0.12, 0.18, sunElevation);
    return 0.16 + 0.84 * t;
  }

  /// 天空配色（天顶 / 地平线 / 地面），线性空间。
  Vector3 get zenithColor => _mix(_nightZenith, _dayZenith, _dayBlend);

  Vector3 get horizonColor {
    final base = _mix(_nightHorizon, _dayHorizon, _dayBlend);
    // 日出/日落：地平线染暖色（只在高度的窄区间里生效，正午与深夜都不染）。
    final glow = _sunsetGlow;
    return _mix(base, _sunsetHorizon, glow);
  }

  Vector3 get groundColor => _mix(_nightGround, _dayGround, _dayBlend);

  /// 太阳色（HDR；夜里接近熄灭，避免"夜里的太阳也很亮"）。
  Vector3 get sunColor => _mix(_nightSun, _daySun, _dayBlend);

  /// 0 = 全夜，1 = 全昼（用于平滑过渡）。
  double get _dayBlend => _smoothstep(-0.18, 0.22, sunElevation);

  /// 日出/日落暖光强度（0..0.75）：只在太阳贴近地平线时出现。
  ///
  /// 截止必须与钟形的零点**完全重合**（都是 |e| = 0.3）：早先写成 [-0.25, 0.35]
  /// 的区间，日落时暖光会在 e=-0.25 处从 0.125 直接掉到 0——天空"啪"地变一次色
  /// （连续性测试当场抓到）。
  double get _sunsetGlow {
    final e = sunElevation;
    const range = 0.3;
    if (e.abs() >= range) return 0;
    return 0.75 * (1.0 - e.abs() / range);
  }

  static final Vector3 _dayZenith = Vector3(0.25, 0.45, 0.85);
  static final Vector3 _dayHorizon = Vector3(0.62, 0.78, 0.96);
  static final Vector3 _dayGround = Vector3(0.28, 0.30, 0.32);
  static final Vector3 _nightZenith = Vector3(0.015, 0.025, 0.07);
  static final Vector3 _nightHorizon = Vector3(0.04, 0.055, 0.12);
  static final Vector3 _nightGround = Vector3(0.015, 0.018, 0.025);
  static final Vector3 _sunsetHorizon = Vector3(0.95, 0.47, 0.20);
  static final Vector3 _daySun = Vector3(3.0, 2.7, 2.2);
  static final Vector3 _nightSun = Vector3(0.10, 0.13, 0.26);

  /// 方向光的强度倍率（0.06..1.0）：夜里太阳几乎不照，靠环境光。
  double get sunIntensityScale => 0.06 + 0.94 * _dayBlend;

  static Vector3 _mix(Vector3 a, Vector3 b, double t) => Vector3(
        a.x + (b.x - a.x) * t,
        a.y + (b.y - a.y) * t,
        a.z + (b.z - a.z) * t,
      );

  /// GLSL 同款 smoothstep（edge0 == edge1 时返回阶跃）。
  static double _smoothstep(double edge0, double edge1, double x) {
    if (edge0 == edge1) return x < edge0 ? 0.0 : 1.0;
    final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
  }
}
