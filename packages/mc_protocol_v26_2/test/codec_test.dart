import 'dart:typed_data';

import 'package:mc_protocol_v26_2/mc_protocol_v26_2.dart';
import 'package:mc_protocol_v26_2/src/protocol_ids.dart' as ids;
import 'package:mc_wire/mc_wire.dart';
import 'package:test/test.dart';

void main() {
  late PacketRegistry reg;

  setUp(() => reg = buildRegistry26_2());

  /// 通过登记表对 inbound 包做一次 decode（模拟 WireConnection 的路径）。
  InboundPacket<Object?> decode(ProtocolPhase phase, int id, List<int> body) =>
      reg.decodeInbound(phase, id, Uint8List.fromList(body));

  /// 通过登记表对 outbound 包做一次 encode（id 前缀 + body）。
  Uint8List encode(ProtocolPhase phase, Object type, Object packet) =>
      reg.encodeOutbound(phase, type, packet);

  group('handshake', () {
    test('ClientIntention 字节精确（tasks 1.1 探针验证过的布局）', () {
      final pkt = ClientIntention(protocolVersion: 776, hostName: '127.0.0.1', port: 25565, intent: 2);
      final bytes = encode(ProtocolPhase.handshake, ClientIntention, pkt);
      // varint id(0x00) + varint 776 + varint len 9 + "127.0.0.1" + ushort 25565 + varint 2
      expect(bytes.sublist(0, 1), [0x00]);
      // 776 = 0b1100001000 → varint = 88 06
      expect(bytes[1], 0x88);
      expect(bytes[2], 0x06);
      expect(bytes.last, 2);
    });

    test('protocol id 常量 = 实测 776', () {
      expect(ProtocolV262.measuredProtocolId, 776);
    });
  });

  group('status', () {
    test('StatusResponse 解码', () {
      final body = ByteWriter()..writeUtf('{"version":{"protocol":776,"name":"Paper 26.2"}}');
      final pkt = decode(ProtocolPhase.status, 0, body.takeBytes());
      expect((pkt.value as StatusResponse).json, contains('776'));
    });
  });

  group('login', () {
    test('LoginCompression 解码', () {
      final pkt = decode(ProtocolPhase.login, ids.LoginClientbound.loginCompression, [0x40]);
      expect((pkt.value as LoginCompression).threshold, 64);
    });

    test('HelloEncryption 识别字段（online-mode 判定用）', () {
      final w = ByteWriter()
        ..writeUtf('')
        ..writeByteArray([1, 2, 3])
        ..writeByteArray([4, 5])
        ..writeBool(true);
      final pkt = decode(ProtocolPhase.login, ids.LoginClientbound.hello, w.takeBytes());
      final v = pkt.value as LoginHelloEncryption;
      expect(v.serverId, '');
      expect(v.publicKey, [1, 2, 3]);
      expect(v.challenge, [4, 5]);
      expect(v.shouldAuthenticate, isTrue);
    });

    test('ServerboundHello 编码（utf16 + 16 字节 uuid）', () {
      final uuid = List<int>.generate(16, (i) => i);
      final bytes = encode(ProtocolPhase.login, ServerboundHello, ServerboundHello('Steve', uuid));
      final r = ByteReader(bytes);
      expect(r.readVarInt(), ids.LoginServerbound.hello);
      expect(r.readUtf(16), 'Steve');
      expect(r.readBytes(16), uuid);
    });

    test('CustomQueryAnswer 编码（varint id + bool false）', () {
      final bytes = encode(ProtocolPhase.login, CustomQueryAnswer, CustomQueryAnswer(7));
      expect(bytes, [ids.LoginServerbound.customQueryAnswer, 7, 0]);
    });
  });

  group('common', () {
    test('KeepAlive（long）往返', () {
      final w = ByteWriter()..writeLong(1727437739123);
      final pkt = decode(ProtocolPhase.play, ids.PlayClientbound.keepAlive, w.takeBytes());
      final v = pkt.value as KeepAlive;
      expect(v.id, 1727437739123);
      // SB 回应按登记表编码，id 前缀正确
      final sb = encode(ProtocolPhase.play, KeepAlive, KeepAlive(v.id));
      final r = ByteReader(sb);
      expect(r.readVarInt(), ids.PlayServerbound.keepAlive);
      expect(r.readLong(), 1727437739123);
    });

    test('Ping(long) → Pong(int) 按参考源码位宽', () {
      final w = ByteWriter()..writeLong(0x1122334455667788);
      final pkt = decode(ProtocolPhase.configuration, ids.ConfigurationClientbound.ping, w.takeBytes());
      expect((pkt.value as Ping).id, 0x1122334455667788);
      final sb = encode(ProtocolPhase.configuration, Ping, Ping(12345));
      final r = ByteReader(sb);
      expect(r.readVarInt(), ids.ConfigurationServerbound.pong);
      expect(r.readInt(), 12345);
    });
  });

  group('play', () {
    test('BlockUpdate 解码（BlockPos long + varint 状态号）', () {
      final pos = McBlockPos(1000, 64, -1000).packLong();
      final w = ByteWriter()
        ..writeLong(pos)
        ..writeVarInt(1234);
      final pkt = decode(ProtocolPhase.play, ids.PlayClientbound.blockUpdate, w.takeBytes());
      final v = pkt.value as BlockUpdate;
      expect(v.pos.x, 1000);
      expect(v.pos.y, 64);
      expect(v.pos.z, -1000);
      expect(v.stateId, 1234);
    });

    test('BlockPos 打包往返（含负坐标与边界）', () {
      for (final p in [McBlockPos(0, 0, 0), McBlockPos(-33554432, -2048, -33554432),
                       McBlockPos(33554431, 2047, 33554431), McBlockPos(-1, -1, -1)]) {
        final u = McBlockPos.unpackLong(p.packLong());
        expect(u.x, p.x, reason: '$p');
        expect(u.y, p.y, reason: '$p');
        expect(u.z, p.z, reason: '$p');
      }
    });

    test('BlockPos 打包黄金向量（对齐原版 BlockPos.asLong 位布局，真机联调实测教训）', () {
      // 曾把 y/z 段位置颠倒（y@26、z@0），服务器解出垃圾坐标静默拒绝挖掘。
      // 期望值按原版 getX/getY/getZ 语义计算：y bit0..11、z bit12..37、x bit38..63。
      final golden = <McBlockPos, int>{
        const McBlockPos(1, 2, 3): 274877919234,
        const McBlockPos(-1, 64, -1): -4032,
        const McBlockPos(-30, 62, 45): -8246337023938,
        const McBlockPos(29999999, -60, -29999998): 8246337085440012228,
      };
      golden.forEach((p, l) {
        expect(p.packLong(), l, reason: 'pack $p');
        final u = McBlockPos.unpackLong(l);
        expect(u.x, p.x, reason: 'unpack x $p');
        expect(u.y, p.y, reason: 'unpack y $p');
        expect(u.z, p.z, reason: 'unpack z $p');
      });
    });

    test('ChunkPos 打包往返', () {
      final pos = McChunkPos(-12345, 67890);
      final u = McChunkPos.unpackLong(pos.packLong());
      expect(u.x, pos.x);
      expect(u.z, pos.z);
    });

    test('SectionBlocksUpdate 解码（sectionPos long + varlong 打包）', () {
      // sectionPos: x=1,y=5,z=-2 → pack 手工构造
      final sx = 1 & 0x3FFFFF, sy = 5 & 0xFFFFF, sz = -2 & 0x3FFFFF;
      final sectionLong = (sx << 42) | (sz << 20) | sy;
      final w = ByteWriter()
        ..writeLong(sectionLong)
        ..writeVarInt(1)
        ..writeVarLong((1234 << 12) | 0x2A5); // 状态号 1234 + 段内局部坐标 0x2A5
      final pkt = decode(ProtocolPhase.play, ids.PlayClientbound.sectionBlocksUpdate, w.takeBytes());
      final v = pkt.value as SectionBlocksUpdate;
      expect(v.sectionX, 1);
      expect(v.sectionY, 5);
      expect(v.sectionZ, -2);
      expect(v.packedChanges.length, 1);
      expect(v.packedChanges[0] >>> 12, 1234);
      expect(v.packedChanges[0] & 0xFFF, 0x2A5);
    });

    test('PlayerLoaded / ClientTickEnd 空包体编码', () {
      expect(encode(ProtocolPhase.play, PlayerLoaded, const PlayerLoaded()),
          [ids.PlayServerbound.playerLoaded]);
      expect(encode(ProtocolPhase.play, ClientTickEnd, const ClientTickEnd()),
          [ids.PlayServerbound.clientTickEnd]);
    });

    test('MovePlayer.posRot 编码（3 double + 2 float + flags）', () {
      final pkt = MovePlayer.posRot(1.5, 64.0, -3.5, 90.0, -10.0,
          onGround: true, horizontalCollision: false);
      final bytes = encode(ProtocolPhase.play, pkt.runtimeType, pkt);
      final r = ByteReader(bytes);
      expect(r.readVarInt(), ids.PlayServerbound.movePlayerPosRot);
      expect(r.readDouble(), 1.5);
      expect(r.readDouble(), 64.0);
      expect(r.readDouble(), -3.5);
      expect(r.readFloat(), closeTo(90.0, 1e-5));
      expect(r.readFloat(), closeTo(-10.0, 1e-5));
      expect(r.readUnsignedByte(), 1); // onGround
    });

    test('ChunkBatchReceived 编码（float）', () {
      final bytes = encode(ProtocolPhase.play, ChunkBatchReceived, ChunkBatchReceived(15.0));
      final r = ByteReader(bytes);
      expect(r.readVarInt(), ids.PlayServerbound.chunkBatchReceived);
      expect(r.readFloat(), 15.0);
    });

    test('PlayerAction 编码', () {
      final bytes = encode(
        ProtocolPhase.play,
        PlayerAction,
        PlayerAction(0, McBlockPos(10, 20, 30), 1, 42),
      );
      final r = ByteReader(bytes);
      expect(r.readVarInt(), ids.PlayServerbound.playerAction);
      expect(r.readVarInt(), 0);
      final pos = McBlockPos.unpackLong(r.readLong());
      expect(pos.x, 10);
      expect(pos.y, 20);
      expect(pos.z, 30);
      expect(r.readUnsignedByte(), 1);
      expect(r.readVarInt(), 42);
    });

    test('UseItemOn 编码', () {
      final bytes = encode(
        ProtocolPhase.play,
        UseItemOn,
        UseItemOn(
          hand: 0,
          pos: McBlockPos(1, 2, 3),
          direction: 1,
          cursorX: 0.5,
          cursorY: 0.5,
          cursorZ: 0.5,
          insideBlock: false,
          worldBorderHit: false,
          sequence: 9,
        ),
      );
      final r = ByteReader(bytes);
      expect(r.readVarInt(), ids.PlayServerbound.useItemOn);
      expect(r.readVarInt(), 0);
      final pos = McBlockPos.unpackLong(r.readLong());
      expect(pos.x, 1);
      expect(r.readVarInt(), 1);
      expect(r.readFloat(), 0.5);
      expect(r.readFloat(), 0.5);
      expect(r.readFloat(), 0.5);
      expect(r.readBool(), isFalse);
      expect(r.readBool(), isFalse);
      expect(r.readVarInt(), 9);
    });
  });

  group('LevelChunkWithLight', () {
    test('合成 chunk 解码（heightmaps + sections buffer + block entities + light）', () {
      final w = ByteWriter();
      w.writeInt(3); // x
      w.writeInt(-4); // z
      // heightmaps：1 个类型（id 1），2 个 long
      w.writeVarInt(1);
      w.writeVarInt(1);
      w.writeVarInt(2);
      w.writeLong(0xAAAA);
      w.writeLong(0xBBBB);
      // sections buffer
      w.writeVarInt(4);
      w.writeBytes([9, 9, 9, 9]);
      // block entities：1 个（packedXZ=0x12, y=-1, type=3, tag = 0x00 即 null，
      // 判据：readAnyTag 首字节 0 = null，无 presence bool）
      w.writeVarInt(1);
      w.writeUnsignedByte(0x12);
      w.writeShort(-1);
      w.writeVarInt(3);
      w.writeUnsignedByte(0x00);
      // light：4 bitset（各 0 long）+ 空 sky/block 列表
      for (var i = 0; i < 4; i++) {
        w.writeVarInt(0);
      }
      w.writeVarInt(0);
      w.writeVarInt(0);

      final pkt = decode(ProtocolPhase.play, ids.PlayClientbound.levelChunkWithLight, w.takeBytes());
      final v = pkt.value as LevelChunkWithLight;
      expect(v.x, 3);
      expect(v.z, -4);
      expect(v.heightmapTypes, [1]);
      expect(v.heightmapData[0].length, 16);
      expect(v.sectionsBuffer, [9, 9, 9, 9]);
      expect(v.blockEntities.single.y, -1);
      expect(v.skyYMask, isEmpty);
    });

    test('真实 Paper 刷怪笼 NBT 黄金回归（chunk #73 错位 bug：非空 tag 后必须零偏差）', () {
      // 取自 2026-10-01 真机 dump：spawner tag（SpawnData.entity.id=minecraft:spider），
      // 170B。曾有 bug：optional NBT 误先读 presence bool，非空 tag 整体错位 1 字节。
      const spawnerNbt = [
        0x0a, 0x0a, 0x00, 0x09, 0x53, 0x70, 0x61, 0x77, 0x6e, 0x44, 0x61, 0x74, 0x61, 0x0a, 0x00, 0x06,
        0x65, 0x6e, 0x74, 0x69, 0x74, 0x79, 0x08, 0x00, 0x02, 0x69, 0x64, 0x00, 0x10, 0x6d, 0x69, 0x6e,
        0x65, 0x63, 0x72, 0x61, 0x66, 0x74, 0x3a, 0x73, 0x70, 0x69, 0x64, 0x65, 0x72, 0x00, 0x00, 0x02,
        0x00, 0x11, 0x4d, 0x61, 0x78, 0x4e, 0x65, 0x61, 0x72, 0x62, 0x79, 0x45, 0x6e, 0x74, 0x69, 0x74,
        0x69, 0x65, 0x73, 0x00, 0x06, 0x02, 0x00, 0x0d, 0x4d, 0x69, 0x6e, 0x53, 0x70, 0x61, 0x77, 0x6e,
        0x44, 0x65, 0x6c, 0x61, 0x79, 0x00, 0xc8, 0x02, 0x00, 0x0a, 0x53, 0x70, 0x61, 0x77, 0x6e, 0x52,
        0x61, 0x6e, 0x67, 0x65, 0x00, 0x04, 0x02, 0x00, 0x0d, 0x4d, 0x61, 0x78, 0x53, 0x70, 0x61, 0x77,
        0x6e, 0x44, 0x65, 0x6c, 0x61, 0x79, 0x03, 0x20, 0x02, 0x00, 0x13, 0x52, 0x65, 0x71, 0x75, 0x69,
        0x72, 0x65, 0x64, 0x50, 0x6c, 0x61, 0x79, 0x65, 0x72, 0x52, 0x61, 0x6e, 0x67, 0x65, 0x00, 0x10,
        0x02, 0x00, 0x0a, 0x53, 0x70, 0x61, 0x77, 0x6e, 0x43, 0x6f, 0x75, 0x6e, 0x74, 0x00, 0x04, 0x02,
        0x00, 0x05, 0x44, 0x65, 0x6c, 0x61, 0x79, 0x00, 0x14, 0x00,
      ];
      final w = ByteWriter();
      w.writeInt(0); // x
      w.writeInt(5); // z
      w.writeVarInt(0); // 无 heightmaps
      w.writeVarInt(0); // 空 sections buffer
      // block entities：刷怪笼（非空 NBT）+ 基岩（null tag）
      w.writeVarInt(2);
      w.writeUnsignedByte(0x09);
      w.writeShort(-40);
      w.writeVarInt(9);
      w.writeBytes(spawnerNbt);
      w.writeUnsignedByte(0x06);
      w.writeShort(-40);
      w.writeVarInt(1);
      w.writeUnsignedByte(0x00); // null tag
      // light：错位时这里立刻爆——skyYMask 用特征值断言
      w.writeVarInt(1);
      w.writeLong(0x1122334455667788);
      for (var i = 0; i < 3; i++) {
        w.writeVarInt(0);
      }
      w.writeVarInt(0); // sky 空
      w.writeVarInt(0); // block 空

      final pkt = decode(ProtocolPhase.play, ids.PlayClientbound.levelChunkWithLight, w.takeBytes());
      final v = pkt.value as LevelChunkWithLight;
      expect(v.blockEntities, hasLength(2));
      expect(v.blockEntities[0].tagNbt, spawnerNbt); // 原样保留
      expect(v.blockEntities[1].tagNbt, isNull);
      expect(v.skyYMask, [0x1122334455667788]); // 偏差 1 字节时必炸
    });
  });

  group('未知包', () {
    test('play 阶段未登记 id 跳过 + 计数（实体等范围外包）', () {
      final pkt = decode(ProtocolPhase.play, ids.PlayClientbound.addEntity, [1, 2, 3]);
      expect(pkt.value, isNull);
      expect(pkt.body, [1, 2, 3]);
      expect(reg.unknownStats.snapshot(), contains('play/0x1'));
    });

    test('bundle delimiter id = 0（clientbound play）', () {
      expect(ids.PlayClientbound.bundleDelimiter, 0);
    });
  });
}
