/**
 * 判据：`net.minecraft.world.entity.player.Abilities`（mc-sources/minecraft-26.2）。
 * app 壳每帧从会话同步；纯数据便于 LocalPlayer 单测。
 */
/// abilities 快照（app 壳每帧从会话同步；纯数据便于控制器单测）。
class Abilities {
  Abilities({
    this.invulnerable = false,
    this.flying = false,
    this.mayfly = false,
    this.flyingSpeed = 0.05,
    this.walkingSpeed = 0.1,
  });

  /// `Abilities.invulnerable`（Abilities.java:15）。
  bool invulnerable;

  /// `Abilities.flying`（Abilities.java:16）——**服务器从 playerdata 恢复**，
  /// 重连时随 `ClientboundPlayerAbilitiesPacket` 下发；客户端照单全收
  /// （判据 `ClientPacketListener.java:2005`，无 mayfly 门禁——门禁在
  /// 服务器侧 `ServerGamePacketListenerImpl.java:2036`）。
  bool flying;

  bool mayfly;

  /// 竖直飞行注入源（判据 `Abilities.flyingSpeed`，`Abilities.java:21`）。
  double flyingSpeed;

  /// `Attributes.MOVEMENT_SPEED` 的**属性值**（判据 `Abilities.walkingSpeed`，
  /// `Abilities.java:21`；由 `Player.java:639` 的 `setBaseValue` 写入）。
  ///
  /// 只喂**地面行走**（`getFrictionInfluencedSpeed` 地面分支）；水平飞行走
  /// `abilities.flyingSpeed`（`Player.java:1952-1958`），与它无关。
  double walkingSpeed;
}
