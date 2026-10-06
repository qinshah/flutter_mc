import 'dart:typed_data';

import 'package:mc_wire/mc_wire.dart';
import 'package:test/test.dart';

class _FakeCodec implements PacketCodec<Object?> {
  @override
  Object? decode(ByteReader r) => r.readVarInt();

  @override
  void encode(ByteWriter w, Object? packet) => w.writeVarInt(packet as int);
}

void main() {
  group('协议阶段状态机', () {
    test('status 分支', () {
      final m = ProtocolPhaseMachine();
      m.startFromHandshake(ClientIntent.status);
      expect(m.phase, ProtocolPhase.status);
    });

    test('login → configuration → play 合法链', () {
      final m = ProtocolPhaseMachine();
      m.startFromHandshake(ClientIntent.login);
      m.loginFinished();
      m.configurationFinished();
      expect(m.phase, ProtocolPhase.play);
    });

    test('transfer 拒绝', () {
      final m = ProtocolPhaseMachine();
      expect(() => m.startFromHandshake(ClientIntent.transfer),
          throwsA(isA<IllegalPhaseTransitionException>()));
    });

    test('跳阶段拒绝', () {
      final m = ProtocolPhaseMachine();
      expect(() => m.configurationFinished(),
          throwsA(isA<IllegalPhaseTransitionException>()));
      m.startFromHandshake(ClientIntent.login);
      expect(() => m.configurationFinished(),
          throwsA(isA<IllegalPhaseTransitionException>()));
    });

    test('intent id 与参考源码一致（STATUS=1/LOGIN=2/TRANSFER=3）', () {
      expect(ClientIntent.status.id, 1);
      expect(ClientIntent.login.id, 2);
      expect(ClientIntent.transfer.id, 3);
    });
  });

  group('包登记表', () {
    test('已登记 inbound 走 codec 解码', () {
      final reg = PacketRegistry();
      reg.registerInbound(ProtocolPhase.play, 0x2C, _FakeCodec());
      final pkt = reg.decodeInbound(ProtocolPhase.play, 0x2C, Uint8List.fromList([7]));
      expect(pkt.value, 7);
      expect(pkt.packetId, 0x2C);
    });

    test('未登记 inbound 跳过 + 计数，不抛异常', () {
      final reg = PacketRegistry();
      final pkt = reg.decodeInbound(ProtocolPhase.play, 0x99, Uint8List.fromList([1, 2]));
      expect(pkt.value, isNull);
      expect(pkt.body, [1, 2]);
      expect(reg.unknownStats.snapshot(), {'play/0x99': 1});
      reg.decodeInbound(ProtocolPhase.play, 0x99, Uint8List.fromList([1, 2]));
      expect(reg.unknownStats.snapshot(), {'play/0x99': 2});
    });

    test('outbound 未登记抛错；登记后 id 前缀正确', () {
      final reg = PacketRegistry();
      expect(
        () => reg.encodeOutbound(ProtocolPhase.login, 'hello', 1),
        throwsStateError,
      );
      reg.registerOutbound(ProtocolPhase.login, 0x02, 'hello', _FakeCodec());
      final bytes = reg.encodeOutbound(ProtocolPhase.login, 'hello', 5);
      expect(bytes, [0x02, 0x05]); // varint 包 id + body
    });

    test('同一包 id 在不同阶段互不串扰', () {
      final reg = PacketRegistry();
      reg.registerInbound(ProtocolPhase.play, 0x01, _FakeCodec());
      final pkt = reg.decodeInbound(ProtocolPhase.login, 0x01, Uint8List.fromList([7]));
      expect(pkt.value, isNull);
    });
  });
}
