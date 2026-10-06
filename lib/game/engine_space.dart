import 'package:vector_math/vector_math.dart';

/// **世界坐标（右手系，Minecraft 约定）→ 引擎坐标（左手系）。**
///
/// 原版对应物：无（**后端适配**——这是 flutter_scene 的坐标系约定，不是原版概念）。
///
/// 判据：MC 世界是右手系（`right = forward × up`，看向 -Z 时右手边是 +X）；
/// flutter_scene 是左手系（`right = up × forward`，+Z 是引擎前向轴）。直接把右手系
/// 喂进去会同时坏两件事：
/// 1. **画面水平镜像**（按 D 往左走、鼠标右移视角左转）；
/// 2. **绕序反转**（正面被判成背面剔除，只能看到方块内壁——地形发黑、脚下地面消失）。
///
/// 做法是把 z 取反。注意分工：**顶点数据里的镜像在 `mc_render` 的网格器里做**
/// （那是网格器的输出契约）；场景图里的位置、方向与相机在这里做。两处必须一致，
/// 否则整段会跑到世界的另一侧。
Vector3 toEngineSpace(Vector3 world) => Vector3(world.x, world.y, -world.z);

/// 方向向量版（规则同 [toEngineSpace]；单列出来是为了让调用点读得懂）。
Vector3 directionToEngineSpace(Vector3 worldDirection) =>
    Vector3(worldDirection.x, worldDirection.y, -worldDirection.z);

/// 段原点的引擎空间位置（段节点用；段坐标 × 16，z 取反）。
Vector3 sectionOriginToEngineSpace(int sectionX, int sectionY, int sectionZ) =>
    Vector3(
      (sectionX * 16).toDouble(),
      (sectionY * 16).toDouble(),
      -(sectionZ * 16).toDouble(),
    );
