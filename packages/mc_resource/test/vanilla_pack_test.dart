import 'dart:io';
import 'dart:typed_data';

import 'package:mc_resource/mc_resource.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mc_resource_test');
  });
  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  test('read 存在路径返回字节，缺失路径返回 null 不抛异常', () async {
    final f = File('${tmp.path}/blockstates/stone.json');
    f.createSync(recursive: true);
    f.writeAsStringSync('{}');
    final pack = VanillaPack.fromDirectory(tmp.path);

    expect(pack.version, tmp.path.split('/').last);
    final bytes = await pack.read('blockstates/stone.json');
    expect(bytes, isNotNull);
    expect(String.fromCharCodes(bytes!), '{}');
    expect(await pack.read('blockstates/missing.json'), isNull);
    expect(await pack.readString('blockstates/missing.json'), isNull);
  });

  test('bundlePath 拼版本标记路径', () {
    expect(VanillaPack.bundlePath('26_2', 'blockstates/stone.json'),
        'assets/vanilla/26_2/blockstates/stone.json');
  });

  test('CallbackPackSource 来源可插拔', () async {
    final pack = VanillaPack(
      version: '26_2',
      source: CallbackPackSource(
        (path) async => path == 'a.txt' ? Uint8List.fromList([1, 2]) : null,
      ),
    );
    expect(await pack.read('a.txt'), [1, 2]);
    expect(await pack.read('b.txt'), isNull);
  });
}
