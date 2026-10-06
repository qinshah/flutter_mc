// 官方 client jar 资产枚举（骨架）。
//
// 当前能力：打开用户本机的官方 client jar，按 `assets/` 前缀分类计数——
// 用于在资源提取 change 立项前盘点 jar 内容。只读，不写任何文件。
// 真实提取 / 转换 / 随包打包是后续资源 change 的工作；届时产物约定目录
// `build/extracted_assets/`（已被 .gitignore 覆盖——官方资产不入库，见 AGENTS.md）。
//
// 用法：dart run tool/extract_assets.dart <client.jar 路径>
import 'dart:io';

import 'package:archive/archive.dart';

void main(List<String> args) {
  if (args.contains('--help') || args.contains('-h')) {
    _usage(exitCode: 0);
  }
  if (args.isEmpty) {
    _usage(exitCode: 64);
  }

  final path = args.first;
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('错误: 文件不存在: $path');
    exit(66);
  }

  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(file.readAsBytesSync());
  } catch (e) {
    stderr.writeln('错误: 无法按 zip 解析 $path（$e）');
    exit(65);
  }

  var total = 0;
  final byCategory = <String, int>{};
  for (final entry in archive) {
    if (!entry.isFile || !entry.name.startsWith('assets/')) continue;
    total++;
    final rest = entry.name.substring('assets/'.length);
    final segments = rest.split('/');
    final category =
        segments.length >= 2 ? '${segments[0]}/${segments[1]}' : segments[0];
    byCategory[category] = (byCategory[category] ?? 0) + 1;
  }

  stdout.writeln('assets/ 条目总数: $total');
  final sorted = byCategory.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final e in sorted) {
    stdout.writeln('  ${e.key}: ${e.value}');
  }
}

void _usage({required int exitCode}) {
  stderr.writeln('用法: dart run tool/extract_assets.dart <client.jar 路径>');
  stderr.writeln('功能: 枚举 jar 内 assets/ 资产并按类别计数（只读，不写任何文件）。');
  exit(exitCode);
}
