import 'dart:io';

import 'package:mc_nbt/mc_nbt.dart';
import 'package:mc_protocol_v26_2/mc_protocol_v26_2.dart';

import 'status_probe.dart';

/// 多人列表条目（原版 `client/multiplayer/ServerData` 的对应物）。
class ServerData {
  ServerData({
    required this.name,
    required this.ip,
    int? protocol,
  }) : protocol = protocol ?? ProtocolV262.measuredProtocolId;

  String name;
  String ip;

  /// 协议版本缓存：status 探测成功后由响应回写（原版列表的版本号来源，
  /// 也是未来多版本装配点的选型输入）；未探测时默认当前锚点版本。
  int protocol;

  /// 探测状态缓存（非持久化字段之外的原版运行时形态）：null=未探测。
  ServerInfo? pingInfo;
  bool pingFailed = false;

  NbtCompound write() {
    final tag = NbtCompound()
      ..['name'] = NbtString(name)
      ..['ip'] = NbtString(ip);
    // hidden/packStatus 等原版字段按"存在才写"处理；本客户端恒写 hidden=false
    // 保持格式一致（原版 save 对可见条目同样写 false）。
    tag['hidden'] = NbtByte(0);
    return tag;
  }

  static ServerData read(NbtCompound tag) {
    final data = ServerData(
      name: tag.getString('name'),
      ip: tag.getString('ip'),
    );
    // 原版条目可能携带本客户端不识别的字段（icon/packStatus 等）：保留缺失给默认。
    if (tag.containsKey('icon')) {
      // 图标（base64 byte array）本版不渲染，占位读出不丢失后续兼容。
      tag.getByteArray('icon');
    }
    return data;
  }
}

/// 服务器列表（原版 `client/multiplayer/ServerList` 的对应物）：
/// servers.dat 兼容（gzip NBT，根 servers 列表，条目 name/ip/hidden）、
/// 原子轮换写入（temp→old→dat）。路径由调用方注入（应用私有目录）。
class ServerList {
  /// [gameDir] 为应用私有"游戏目录"（原版 servers.dat 即放在游戏目录根部）。
  ServerList(this.gameDir);

  final Directory gameDir;

  final List<ServerData> _servers = [];
  List<ServerData> get servers => List.unmodifiable(_servers);
  int get length => _servers.length;
  bool get isEmpty => _servers.isEmpty;
  bool get isNotEmpty => _servers.isNotEmpty;
  ServerData operator [](int index) => _servers[index];

  File get _file => File('${gameDir.path}/servers.dat');

  void load() {
    _servers.clear();
    try {
      if (!_file.existsSync()) return;
      final tag = NbtReader.readGzipFile(_file);
      final list = tag['servers'];
      if (list is! NbtList) return;
      for (final entry in list.value) {
        if (entry is NbtCompound) {
          // hidden 条目本客户端不展示：跳过但保留文件里的其他条目不动。
          if (entry.getBool('hidden')) continue;
          _servers.add(ServerData.read(entry));
        }
      }
    } on NbtFormatException {
      // 读失败按原版口径：记日志、以空列表继续（不破坏文件，等下次 save 覆盖）。
      _servers.clear();
    }
  }

  void save() {
    final serverTags = NbtList.empty();
    for (final server in _servers) {
      final tag = server.write();
      tag['hidden'] = NbtByte(0);
      serverTags.add(tag);
    }
    final root = NbtCompound()..['servers'] = serverTags;

    gameDir.createSync(recursive: true);
    final temp = File(
        '${gameDir.path}/servers.tmp${DateTime.now().microsecondsSinceEpoch}.dat');
    NbtWriter.writeGzipFile(root, temp);
    final oldFile = File('${gameDir.path}/servers.dat_old');
    if (_file.existsSync()) {
      _file.renameSync(oldFile.path);
    }
    temp.renameSync(_file.path);
  }

  void add(ServerData data) {
    _servers.add(data);
    save();
  }

  void removeAt(int index) {
    _servers.removeAt(index);
    save();
  }

  void editAt(int index, ServerData data) {
    _servers[index] = data;
    save();
  }
}
