/// 协议阶段状态机 —— 骨架层面只管"合法迁移"，不认识任何具体包
/// （包类型登记由版本包提供，见 `PacketRegistry`）。
///
/// 迁移图（REF: mc-sources/minecraft-26.2 `network/protocol/` 各阶段的
/// `*Protocols.java` 与 `ServerHandshakePacketListenerImpl`）：
///
/// ```
/// handshake ──intent=STATUS──▶ status（应答后连接终结，本包骨架不管理其关闭）
///          ──intent=LOGIN───▶ login ──▶ configuration ──▶ play
/// ```
///
/// 26.x 没有"从 play 回 configuration"（重登录走新连接；TRANSFER intent 属范围外，
/// 见 change 的 proposal）。任何非法迁移抛 [IllegalPhaseTransitionException]。
enum ProtocolPhase { handshake, status, login, configuration, play }

class IllegalPhaseTransitionException implements Exception {
  const IllegalPhaseTransitionException(this.from, this.to);

  final ProtocolPhase from;
  final ProtocolPhase to;

  @override
  String toString() => '非法协议阶段迁移：$from → $to';
}

class ProtocolPhaseMachine {
  ProtocolPhase phase = ProtocolPhase.handshake;

  /// 握手落点：status（探测）或 login（登录）。
  void startFromHandshake(ClientIntent intent) {
    _expect(ProtocolPhase.handshake);
    switch (intent) {
      case ClientIntent.status:
        phase = ProtocolPhase.status;
      case ClientIntent.login:
        phase = ProtocolPhase.login;
      case ClientIntent.transfer:
        throw const IllegalPhaseTransitionException(
          ProtocolPhase.handshake,
          ProtocolPhase.play,
        );
    }
  }

  void loginFinished() {
    _expect(ProtocolPhase.login);
    phase = ProtocolPhase.configuration;
  }

  void configurationFinished() {
    _expect(ProtocolPhase.configuration);
    phase = ProtocolPhase.play;
  }

  void _expect(ProtocolPhase expected) {
    if (phase != expected) {
      throw IllegalPhaseTransitionException(phase, expected);
    }
  }
}

/// 握手 intent（REF: `network/protocol/handshake/ClientIntent.java`：
/// STATUS=1, LOGIN=2, TRANSFER=3）。
enum ClientIntent {
  status(1),
  login(2),
  transfer(3);

  const ClientIntent(this.id);

  final int id;
}
