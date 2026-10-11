import 'dart:typed_data';

import 'package:mc_protocol_v26_2/mc_protocol_v26_2.dart';
import 'package:mc_session/mc_session.dart';
import 'package:test/test.dart';

/// 段索引 ↔ **世界坐标 y** 的偏移（4.1 端到端实测挖出的坑）。
///
/// 26.x 的 overworld 世界底是 y = −64（高 384 = −64..320），而段号是世界坐标
/// 的函数。早先按 0 基算（`worldY >> 4`）会让段索引整体偏 64 格：客户端据此
/// 判定"脚下有实体方块"而服务器认为玩家在自由落体，于是服务器反复下传权威位置
/// （日志狂刷 `moved too quickly`）。
void main() {
  RemoteChunkColumn column({int? minSectionY}) => RemoteChunkColumn(
        x: 0,
        z: 0,
        sections: List.generate(24, (_) => Uint16List(4096)),
        skyLight: const {},
        blockLight: const {},
        heightmapTypes: const [],
        heightmapData: const [],
        minSectionY: minSectionY ?? RemoteChunkColumn.kOverworldMinSectionY,
      );

  test('SectionBlocksUpdate 段内坐标位序：X=bit8-11、Z=bit4-7、Y=bit0-3（判据 SectionPos.java:100-110）', () {
    // 2026-10-11 实机"怼墙抽搐"根因回归：此前 Y/Z 位序弄反 ⇒ 玩家放置的
    // 整面墙（多方块更新）落到 y↔z 互换的格子，客户端碰撞缺墙格。
    final c = column();
    // 玩家在段 y=5（世界 y=80..95）放 3 个方块：
    //   A(x=3, y=2, z=7)：vanilla packed pos = x<<8 | z<<4 | y = 0x372
    //   B(x=15, y=15, z=0)：= 0xFF0
    //   C(x=0, y=0, z=15)：= 0x00F
    // stateId 全取 9（grass_block）。packed long = stateId << 12 | pos。
    final packedA = (9 << 12) | (3 << 8) | (7 << 4) | 2;
    final packedB = (9 << 12) | (15 << 8) | (0 << 4) | 15;
    final packedC = (9 << 12) | (0 << 8) | (15 << 4) | 0;
    expect(c.applySectionChanges(0, 5, 0, [packedA, packedB, packedC]), isTrue);

    // 世界 y = (5<<4) | 局部y。
    expect(c.stateAt(3, (5 << 4) | 2, 7), 9, reason: 'A：x=3,y=2,z=7');
    expect(c.stateAt(15, (5 << 4) | 15, 0), 9, reason: 'B：x=15,y=15,z=0');
    expect(c.stateAt(0, (5 << 4) | 0, 15), 9, reason: 'C：x=0,y=0,z=15');

    // 旧错序（Y/Z 互换）会落到的格子必须仍是空气。
    expect(c.stateAt(3, (5 << 4) | 7, 2), 0, reason: '旧 bug 落点 (x=3,y=7,z=2)');
    expect(c.stateAt(15, (5 << 4) | 0, 15), 0, reason: 'B 的旧 bug 落点 (x=15,y=0,z=15)');
    expect(c.stateAt(0, (5 << 4) | 15, 0), 0, reason: 'C 的旧 bug 落点 (x=0,y=15,z=0)');
  });

  test('overworld：世界 y=143 落在第 12 段（143>>4=8，再减 minSectionY −4）', () {
    final c = column();
    expect(c.minY, -64);

    expect(c.applyBlockUpdate(McBlockPos(3, 143, 5), 42), isTrue);
    expect(c.stateAt(3, 143, 5), 42);
    // 段内局部 y = 143 & 15 = 15；index = (15<<8)|(5<<4)|3
    expect(c.sections[12][(15 << 8) | (5 << 4) | 3], 42);
  });

  test('世界底 y=-64 落在第 0 段（按 0 基算会读到第 -4 段→越界成空气）', () {
    final c = column();
    expect(c.applyBlockUpdate(McBlockPos(0, -64, 0), 7), isTrue);
    expect(c.stateAt(0, -64, 0), 7);
    expect(c.sections[0][0], 7);
    expect(c.stateAt(0, -65, 0), 0, reason: '世界底之下仍是空气');
  });

  test('顶部 y=319 落在最后一段；y=320 越界为空气', () {
    final c = column();
    expect(c.applyBlockUpdate(McBlockPos(0, 319, 0), 9), isTrue);
    expect(c.stateAt(0, 319, 0), 9);
    expect(c.sections[23][15 << 8], 9);
    expect(c.stateAt(0, 320, 0), 0);
  });

  test('minSectionY=0 的维度（下界/末地）按 0 基解释', () {
    final c = column(minSectionY: 0);
    expect(c.minY, 0);

    expect(c.applyBlockUpdate(McBlockPos(1, 64, 1), 5), isTrue);
    expect(c.stateAt(1, 64, 1), 5);
    expect(c.sections[4][(1 << 4) | 1], 5);
  });
}
