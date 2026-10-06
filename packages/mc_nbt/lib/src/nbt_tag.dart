import 'dart:collection';
import 'dart:typed_data';

/// NBT 标签号 —— 与 Java `NBTBase`（MCP 1.12.2 `net.minecraft.nbt.NBTBase`）的常量一一对应。
///
/// 名字里带位宽（`int32` / `float64`）而不是直接抄 Java 的 `TAG_INT` / `TAG_DOUBLE`，
/// 是为了让"这个标签到底是 32 位还是 64 位"在调用处一眼可见 —— 移植原版算法时
/// 位宽搞错是最难查的一类 bug（project_rules.md §4.10）。
abstract final class NbtTagType {
  /// 0：仅用于 compound 的结束标记与"空列表/无类型"占位，**不作为元素类型出现**。
  static const int end = 0;
  static const int byte = 1;
  static const int short = 2;
  static const int int32 = 3;
  static const int int64 = 4;
  static const int float32 = 5;
  static const int float64 = 6;
  static const int byteArray = 7;
  static const int string = 8;
  static const int list = 9;
  static const int compound = 10;
  static const int intArray = 11;
  static const int longArray = 12;

  /// 诊断用：把标签号翻译成名字（异常信息里用，避免"类型 13 越界"这种无法阅读的报错）。
  static String nameOf(int type) => switch (type) {
        end => 'END',
        byte => 'BYTE',
        short => 'SHORT',
        int32 => 'INT',
        int64 => 'LONG',
        float32 => 'FLOAT',
        float64 => 'DOUBLE',
        byteArray => 'BYTE_ARRAY',
        string => 'STRING',
        list => 'LIST',
        compound => 'COMPOUND',
        intArray => 'INT_ARRAY',
        longArray => 'LONG_ARRAY',
        _ => 'UNKNOWN($type)',
      };
}

/// NBT 数据不符合格式时抛出（截断、标签号越界、长度非法、压缩流损坏……）。
///
/// 明确用异常而不是 `assert`：这些分支全部来自**磁盘上的第三方文件**，
/// 必须在 release 下也能被上层捕获并降级（design.md §10 / E-22 / E-23）。
class NbtFormatException implements Exception {
  const NbtFormatException(this.message, {this.offset});

  final String message;

  /// 出错位置（字节偏移），读取时尽量填上，便于对着 hex dump 排查。
  final int? offset;

  @override
  String toString() =>
      'NbtFormatException: $message${offset == null ? '' : ' @$offset'}';
}

/// NBT 标签模型（design.md §4.5）。
///
/// 两条贯穿全局的纪律：
/// 1. **无损**：往返必须保留未知标签的类型与顺序（E-24）。因此
///    [NbtCompound] 用插入有序的 Map、[NbtList] 记住自己的元素类型（**含空列表**）。
/// 2. **不猜**：任何"看不懂"的输入一律抛 [NbtFormatException]，绝不悄悄改写成别的值。
sealed class NbtTag {
  const NbtTag();

  /// 标签号，见 [NbtTagType]。
  int get type;
}

/// 0：END。[NbtCompound] 用它作结束标记，[NbtList] 里**不允许**出现。
final class NbtEnd extends NbtTag {
  const NbtEnd();

  @override
  int get type => NbtTagType.end;

  @override
  bool operator ==(Object other) => other is NbtEnd;

  @override
  int get hashCode => NbtTagType.end;

  @override
  String toString() => 'END';
}

/// 1：有符号 8 位（Java `byte`，值域 -128..127）。
final class NbtByte extends NbtTag {
  const NbtByte(this.value);

  final int value;

  @override
  int get type => NbtTagType.byte;

  @override
  bool operator ==(Object other) => other is NbtByte && other.value == value;

  @override
  int get hashCode => Object.hash(NbtTagType.byte, value);

  @override
  String toString() => 'BYTE($value)';
}

/// 2：有符号 16 位（Java `short`）。
final class NbtShort extends NbtTag {
  const NbtShort(this.value);

  final int value;

  @override
  int get type => NbtTagType.short;

  @override
  bool operator ==(Object other) => other is NbtShort && other.value == value;

  @override
  int get hashCode => Object.hash(NbtTagType.short, value);

  @override
  String toString() => 'SHORT($value)';
}

/// 3：有符号 32 位（Java `int`）。
final class NbtInt extends NbtTag {
  const NbtInt(this.value);

  final int value;

  @override
  int get type => NbtTagType.int32;

  @override
  bool operator ==(Object other) => other is NbtInt && other.value == value;

  @override
  int get hashCode => Object.hash(NbtTagType.int32, value);

  @override
  String toString() => 'INT($value)';
}

/// 4：有符号 64 位（Java `long`）。Dart 原生 `int` 在 64 位平台上就是 64 位，直接存。
final class NbtLong extends NbtTag {
  const NbtLong(this.value);

  final int value;

  @override
  int get type => NbtTagType.int64;

  @override
  bool operator ==(Object other) => other is NbtLong && other.value == value;

  @override
  int get hashCode => Object.hash(NbtTagType.int64, value);

  @override
  String toString() => 'LONG($value)';
}

/// 5：IEEE-754 单精度（Java `float`）。
///
/// **值在构造时就截断到 f32**（`Java float` 只有 32 位）。不这么做就会出现
/// "两个标签在内存里不相等、写出的字节却一模一样"（或反过来）—— 而这条链路的两端
/// 是同一个文件，任何"内存语义与字节语义不一致"都是致命的。
/// 代价是一个反直觉的现象：`NbtFloat(0.1).value != 0.1`，它等于 f32 意义上的 0.1。
/// 用 `const` 就无法在构造时截断，所以这个类**没有 const 构造函数**。
final class NbtFloat extends NbtTag {
  NbtFloat(double value) : value = _toFloat32(value);

  final double value;

  @override
  int get type => NbtTagType.float32;

  @override
  bool operator ==(Object other) => other is NbtFloat && other.value == value;

  @override
  int get hashCode => Object.hash(NbtTagType.float32, value);

  @override
  String toString() => 'FLOAT($value)';
}

/// 共享的 4 字节暂存：`NbtFloat` 每次构造都要做一次 f32 舍入，
/// 不值得每次现分配一个 `ByteData`。
final ByteData _float32Scratch = ByteData(4);

/// 按 IEEE-754 就近舍入到单精度（与 Java `writeFloat`/`readFloat` 的转换一致）。
double _toFloat32(double value) {
  _float32Scratch.setFloat32(0, value);
  return _float32Scratch.getFloat32(0);
}

/// 6：IEEE-754 双精度（Java `double`）。
final class NbtDouble extends NbtTag {
  const NbtDouble(this.value);

  final double value;

  @override
  int get type => NbtTagType.float64;

  @override
  bool operator ==(Object other) => other is NbtDouble && other.value == value;

  @override
  int get hashCode => Object.hash(NbtTagType.float64, value);

  @override
  String toString() => 'DOUBLE($value)';
}

/// 7：字节数组。
///
/// `Add` / `Blocks` / `Biomes` 这些区块字段全是它，是 1.12.2 存档里体积最大的标签。
/// 相等性按**内容**比较（`Uint8List` 的默认 `==` 是同一性比较，直接用会漏掉内容差异）。
final class NbtByteArray extends NbtTag {
  const NbtByteArray(this.value);

  final Uint8List value;

  @override
  int get type => NbtTagType.byteArray;

  @override
  bool operator ==(Object other) =>
      other is NbtByteArray && _bytesEqual(other.value, value);

  @override
  int get hashCode => Object.hash(NbtTagType.byteArray, Object.hashAll(value));

  @override
  String toString() => 'BYTE_ARRAY(${value.length})';
}

/// 8：字符串，字节层是 Java modified UTF-8（见 `java_utf.dart`）。
final class NbtString extends NbtTag {
  const NbtString(this.value);

  final String value;

  @override
  int get type => NbtTagType.string;

  @override
  bool operator ==(Object other) => other is NbtString && other.value == value;

  @override
  int get hashCode => Object.hash(NbtTagType.string, value);

  @override
  String toString() => 'STRING("$value")';
}

/// 9：同质列表。
///
/// **元素类型（[elementType]）是数据的一部分**，必须跟着列表一起往返：
/// - 非空列表的类型由元素决定；
/// - **空列表的类型来自文件头**，原版 1.12.2 写空列表时会把类型字节写成 0
///   （已用 `test_fixtures/vanilla_save/` 实测：7815 个空列表**全部**是 0），
///   但 mod 写出的文件可能是别的值 —— 我们**原样保留、不做规范化**，
///   这样写回时既不丢信息、也不需要"猜"。
///
/// 类型是 `int` 而不是 `final int`：原版 `NBTTagList#appendTag` 会在列表为空时
/// 采纳第一个元素的类型，我们照做（[add]）。
final class NbtList extends NbtTag {
  NbtList(this.elementType, [Iterable<NbtTag> elements = const <NbtTag>[]])
      : _elements = List<NbtTag>.of(elements) {
    // 空列表允许携带任意元素类型（含 0）；非空列表则必须自洽。
    if (elementType == NbtTagType.end && _elements.isNotEmpty) {
      elementType = _elements.first.type;
    }
    for (final element in _elements) {
      if (element is NbtEnd) {
        throw ArgumentError('NbtList 不能包含 END 标签（原版 NBTTagList#appendTag 会直接丢弃它）');
      }
      if (element.type != elementType) {
        throw ArgumentError(
          'NbtList 元素类型不一致：列表声明 ${NbtTagType.nameOf(elementType)}，'
          '元素为 ${NbtTagType.nameOf(element.type)}',
        );
      }
    }
  }

  /// 空列表（可指定元素类型，默认 0）。
  NbtList.empty([int elementType = NbtTagType.end]) : this(elementType);

  /// 由元素推导元素类型（空集合 → 0），照原版 `NBTTagList` 的用法。
  factory NbtList.of(Iterable<NbtTag> elements) {
    final copy = List<NbtTag>.of(elements);
    return NbtList(copy.isEmpty ? NbtTagType.end : copy.first.type, copy);
  }

  int elementType;
  final List<NbtTag> _elements;

  /// 只读视图，防止绕过 [add] 的类型校验。
  ///
  /// 缓存成字段而不是每次返回新视图：解码一个区块会碰到上千个列表，
  /// 每次现包一个 `UnmodifiableListView` 是白白的分配。
  late final List<NbtTag> value = UnmodifiableListView(_elements);

  int get length => _elements.length;
  bool get isEmpty => _elements.isEmpty;
  bool get isNotEmpty => _elements.isNotEmpty;

  NbtTag operator [](int index) => _elements[index];

  /// 追加元素。列表原本为空（类型为 0）时采纳元素类型；类型不符直接抛错。
  void add(NbtTag tag) {
    if (tag is NbtEnd) {
      throw ArgumentError('NbtList 不能包含 END 标签');
    }
    if (_elements.isEmpty && elementType == NbtTagType.end) {
      elementType = tag.type;
    }
    if (tag.type != elementType) {
      throw ArgumentError(
        'NbtList 元素类型不一致：列表声明 ${NbtTagType.nameOf(elementType)}，'
        '元素为 ${NbtTagType.nameOf(tag.type)}',
      );
    }
    _elements.add(tag);
  }

  @override
  int get type => NbtTagType.list;

  @override
  bool operator ==(Object other) =>
      other is NbtList &&
      other.elementType == elementType &&
      _tagsEqual(other._elements, _elements);

  @override
  int get hashCode =>
      Object.hash(NbtTagType.list, elementType, Object.hashAll(_elements));

  @override
  String toString() =>
      'LIST<${NbtTagType.nameOf(elementType)}>(${_elements.length})';
}

/// 10：复合标签。**插入有序**（Dart 的 `Map` 是 `LinkedHashMap`，
/// 且对已存在的键赋值**不会**改变它的位置），因此往返后标签顺序与文件一致 ——
/// 这既是 E-24 的要求，也让 A-13 的字节比对容易通过。
final class NbtCompound extends NbtTag {
  NbtCompound([Map<String, NbtTag>? initial]) {
    if (initial != null) {
      for (final entry in initial.entries) {
        this[entry.key] = entry.value;
      }
    }
  }

  final Map<String, NbtTag> _tags = <String, NbtTag>{};

  /// 只读视图（保持插入序）。
  Map<String, NbtTag> get value => UnmodifiableMapView(_tags);

  Iterable<String> get keys => _tags.keys;
  int get length => _tags.length;
  bool get isEmpty => _tags.isEmpty;
  bool get isNotEmpty => _tags.isNotEmpty;

  bool containsKey(String key) => _tags.containsKey(key);

  NbtTag? operator [](String key) => _tags[key];

  void operator []=(String key, NbtTag tag) {
    if (tag is NbtEnd) {
      throw ArgumentError('NbtCompound 不能存放 END 标签（它是结束标记，不是数据）');
    }
    _tags[key] = tag;
  }

  NbtTag? remove(String key) => _tags.remove(key);

  /// 该键的标签号；不存在返回 [NbtTagType.end]（照原版 `NBTTagCompound#getTagId`）。
  int typeIdOf(String key) => _tags[key]?.type ?? NbtTagType.end;

  // —— 类型化访问器（照原版 `NBTTagCompound` 的宽松取值语义） ——

  /// 数值型标签统一取值；非数值返回 null。
  num? _number(String key) => switch (_tags[key]) {
        final NbtByte t => t.value,
        final NbtShort t => t.value,
        final NbtInt t => t.value,
        final NbtLong t => t.value,
        final NbtFloat t => t.value,
        final NbtDouble t => t.value,
        _ => null,
      };

  /// 32 位整数。原版在取 `byte`/`short`/`int`/`long` 时都会跨类型强转，这里同样宽松。
  int getInt(String key, [int orElse = 0]) => _number(key)?.toInt() ?? orElse;

  /// 64 位整数（Dart `int` 即 64 位）。
  int getLong(String key, [int orElse = 0]) => _number(key)?.toInt() ?? orElse;

  double getDouble(String key, [double orElse = 0]) =>
      _number(key)?.toDouble() ?? orElse;

  /// 原版 `NBTTagCompound#getBoolean` 就是 `getByte(key) != 0`。
  bool getBool(String key, [bool orElse = false]) {
    final n = _number(key);
    return n == null ? orElse : n != 0;
  }

  /// 只认 STRING 标签（原版对类型不符返回空串）。
  String getString(String key, [String orElse = '']) {
    final tag = _tags[key];
    return tag is NbtString ? tag.value : orElse;
  }

  Uint8List? getByteArray(String key) {
    final tag = _tags[key];
    return tag is NbtByteArray ? tag.value : null;
  }

  Int32List? getIntArray(String key) {
    final tag = _tags[key];
    return tag is NbtIntArray ? tag.value : null;
  }

  List<int>? getLongArray(String key) {
    final tag = _tags[key];
    return tag is NbtLongArray ? tag.value : null;
  }

  NbtCompound? getCompound(String key) {
    final tag = _tags[key];
    return tag is NbtCompound ? tag : null;
  }

  /// 取列表。`expectedType` 非空时要求元素类型匹配（照原版 `getTagList`：
  /// **空列表不受类型检查**，因为空列表的类型没有语义）。
  NbtList? getList(String key, [int? expectedType]) {
    final tag = _tags[key];
    if (tag is! NbtList) return null;
    if (expectedType != null && tag.isNotEmpty && tag.elementType != expectedType) {
      return null;
    }
    return tag;
  }

  @override
  int get type => NbtTagType.compound;

  @override
  bool operator ==(Object other) =>
      other is NbtCompound && _mapsEqual(other._tags, _tags);

  @override
  int get hashCode =>
      Object.hash(NbtTagType.compound, Object.hashAll(_tags.keys),
          Object.hashAll(_tags.values));

  @override
  String toString() => 'COMPOUND(${_tags.keys.join(', ')})';
}

/// 11：32 位整数数组。`HeightMap` 就是它。
final class NbtIntArray extends NbtTag {
  const NbtIntArray(this.value);

  final Int32List value;

  @override
  int get type => NbtTagType.intArray;

  @override
  bool operator ==(Object other) =>
      other is NbtIntArray && _intsEqual(other.value, value);

  @override
  int get hashCode => Object.hash(NbtTagType.intArray, Object.hashAll(value));

  @override
  String toString() => 'INT_ARRAY(${value.length})';
}

/// 12：64 位整数数组。Dart 侧用 `List<int>`（`Int64List` 的平台可用性不值得依赖）。
final class NbtLongArray extends NbtTag {
  const NbtLongArray(this.value);

  final List<int> value;

  @override
  int get type => NbtTagType.longArray;

  @override
  bool operator ==(Object other) =>
      other is NbtLongArray && _intsEqual(other.value, value);

  @override
  int get hashCode => Object.hash(NbtTagType.longArray, Object.hashAll(value));

  @override
  String toString() => 'LONG_ARRAY(${value.length})';
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _intsEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _tagsEqual(List<NbtTag> a, List<NbtTag> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _mapsEqual(Map<String, NbtTag> a, Map<String, NbtTag> b) {
  if (a.length != b.length) return false;
  // 顺序也是数据的一部分：先比 key 序列，再比每个值。
  final ka = a.keys.toList(growable: false);
  final kb = b.keys.toList(growable: false);
  for (var i = 0; i < ka.length; i++) {
    if (ka[i] != kb[i]) return false;
    if (a[ka[i]] != b[kb[i]]) return false;
  }
  return true;
}
