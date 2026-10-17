// 逐行翻译 net/minecraft/server/dedicated/Settings.java。
//
// 判据：
//   Settings.java:26-32 —— 构造：持有一份 Properties（引用，不拷贝）。
//   Settings.java:34-57 —— loadFromFile：UTF-8 优先（畸形即 REPORT 报错），CharacterCodingException
//                          时回退 ISO-8859-1；任何 IOException（含文件不存在）返回**空** Properties。
//   Settings.java:59-65 —— store：注释头 "Minecraft server properties"（本文件字面量照抄）。
//   Settings.java:67-75 —— wrapNumberDeserializer：NumberFormatException → null。
//   Settings.java:103-108 —— get：文件值存在则反序列化，结果为空时取默认值；无论哪条路径，
//                            解析结果都被**写回** properties（写回的是序列化形态字符串）。
//   Settings.java:140-142 / :148-150 / :168-170 —— getString / getInt / getBool 三个重载口径。
//
// 未翻译的部分（本仓用不到，故不引入）：泛型自类型 `Settings<T>`、`getMutable`/`MutableValue`
// （在线改写配置，宿主改用整份写回）、枚举/资源包等复杂反序列化器、`getLegacy*`。
// 原版 `store` 会捕获 IOException 并记日志（:62-64）；本实现的 `store` 让异常上抛，交由宿主在
// 日志面板呈现——差别只在错误路径的呈现方式，不改变成功路径的字节。
import 'dart:io';

import '../java_properties.dart';

/// 对应 `Settings`：一份 server.properties 的键值视图 + 类型化读取。
abstract class Settings {
  /// 文件原始内容（插入顺序，见 `Properties` 文件头说明）。
  final Map<String, String> properties;

  Settings(this.properties);

  /// 对应 `Settings.loadFromFile`：UTF-8 优先、ISO-8859-1 回退；IO 失败返回空表（:53-56）。
  static Map<String, String> loadFromFile(String path) {
    List<int> bytes;
    try {
      bytes = File(path).readAsBytesSync();
    } on IOException {
      // :53-56：原版对 IOException 记日志并返回 new Properties()（空表）。
      return <String, String>{};
    }
    return Properties.loadFromBytes(bytes);
  }

  /// 对应 `Settings.get(String, Function, Function, T)`（:103-108）：解析 + 写回。
  ///
  /// 语义照 `MoreObjects.firstNonNull(deserializer.apply(raw), defaultValue)`：反序列化返回
  /// null（或键缺失）即取默认值；无论哪条路径，结果都以**序列化形态**写回 properties。
  V _get<V extends Object>(
    String key,
    V? Function(String) deserializer,
    String Function(V) serializer,
    V defaultValue,
  ) {
    final raw = properties[key];
    final result = (raw != null ? deserializer(raw) : null) ?? defaultValue;
    properties[key] = serializer(result);
    return result;
  }

  /// :140-142：identity 反序列化 + identity 序列化。
  String getString(String key, String defaultValue) =>
      _get(key, (s) => s, (s) => s, defaultValue);

  /// :148-150：wrapNumberDeserializer(Integer::parseInt) + Objects::toString。
  int getInt(String key, int defaultValue) =>
      _get(key, _parseInt, _intToString, defaultValue);

  /// :168-170：Boolean::valueOf（非 null，故 key 存在时永不落默认值）+ Objects::toString。
  bool getBool(String key, bool defaultValue) =>
      _get(key, _parseBool, _boolToString, defaultValue);

  /// java.lang.Integer.parseInt：不接受 `0x` 前缀（Dart 的 int.tryParse 会接受，故显式排除）；
  /// 解析失败（NumberFormatException）返回 null → 由调用方落到默认值（:67-75）。
  static int? _parseInt(String s) {
    if (s.startsWith('0x') || s.startsWith('0X')) return null;
    return int.tryParse(s);
  }

  /// java.lang.Boolean.valueOf：仅忽略大小写的 "true" 为真（永不返回 null）。
  static bool _parseBool(String s) => s.toLowerCase() == 'true';

  static String _intToString(int v) => v.toString();

  static String _boolToString(bool v) => v.toString();

  /// 对应 `Settings.store`（:59-65）：写回带注释头的 properties 文本。
  void store(String path, {String comments = 'Minecraft server properties'}) {
    Properties.storeFile(path, properties, comments);
  }
}
