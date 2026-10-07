#!/usr/bin/env python3
"""生成 26.2 物品注册序表（lib/world/item/items_26_2.dart）。

判据链（与 tool/gen_block_state_ids_26_2.py 同法）：
- `Items.java` 字段声明顺序 = 注册顺序（static init 顺序即注册顺序）；
- 注册名来自 `references/BlockItemIds.java` / `ItemIds.java`：
  - `BlockItemId.create("stone")` / 多参 `create("redstone_wire", "redstone")`
    （**末参** = 物品注册名）；
  - `ResourceKey<Item> SADDLE = create("saddle")`；
  - `createSpawnEgg(EntityTypeIds.CHICKEN)` → `chicken_spawn_egg`
    （实体注册名 + `_spawn_egg`，实体名取 `EntityTypeIds.create("...")`）；
  - `createMusicDisc(JukeboxSongs.THIRTEEN)` → `music_disc_13`
    （歌曲注册名 + `music_disc_` 前缀；`thirteen` 特例为 `13`）；
- **集合字段**（按集合类的注册遍历序展开）：
  - `ColorCollection`（`createSimpleColored(base)`）→ 16 项，`color + "_" + base`，
    按 `DyeColor` 枚举序（判据 `ColorCollection.prefixWithColor` + `NAMES`）；
  - `WeatheringCopperCollection`（`createSimpleCopper(base)`）→ 8 项，前缀序见
    `WeatheringCopperCollection.PREFIXES`；
    特殊命名表（如 COPPER_BLOCK 的 ByState 字面量）逐前缀拼接；
- 原版客户端的 item registry 就是这样内置的（item **不是**同步注册表，
  configuration 阶段服务器不下发）。

用法：python3 tool/gen_item_registry_26_2.py <mc-sources 根>
只读 mc-sources，产物入库。
"""
import re
import sys
from pathlib import Path

COPPER_PREFIXES = [
    "", "exposed_", "weathered_", "oxidized_",
    "waxed_", "waxed_exposed_", "waxed_weathered_", "waxed_oxidized_",
]


def parse_create_map(path: Path) -> dict:
    """CONSTANT -> (表达式, 字符串参数列表)。"""
    out = {}
    for m in re.finditer(
        r'public static final [\w<>]+ (\w+) = ([^;]+)',
        path.read_text(),
    ):
        out[m.group(1)] = (m.group(2), re.findall(r'"([^"]+)"', m.group(2)))
    return out


def parse_id_file(path: Path) -> dict:
    """CONSTANT -> 注册名（create 多参时取**末参**）。"""
    out = {}
    for const, (_, args) in parse_create_map(path).items():
        if args:
            out[const] = args[-1]
    return out


def parse_dye_colors(path: Path) -> list:
    """DyeColor 注册名按枚举序（判据 `DyeColor.getName` + `ColorCollection` record 序）。"""
    return [g[1] for g in re.findall(
        r'\b([A-Z_0-9]+)\(\d+, "([a-z_]+)"', path.read_text())]


def expand_collection(expr: str, dye_colors: list, special: dict) -> list | None:
    """把集合常量的表达式展开为按注册序排列的名字列表。"""
    mm = re.search(r'createSimpleColored\("([^"]+)"\)', expr)
    if mm is not None:
        return [c + "_" + mm.group(1) for c in dye_colors]
    mm = re.search(r'createSimpleCopper\("([^"]+)"\)', expr)
    if mm is not None:
        return [pfx + mm.group(1) for pfx in COPPER_PREFIXES]
    # 特殊命名表：prefixWithState(... same(X = new ByState<>(...)))
    mm = re.search(r'prefixWithState\(\s*WeatheringCopperCollection\.same\((\w+)\)', expr)
    if mm is not None:
        bases = special.get(mm.group(1))
        if bases is None:
            return None
        unwaxed = [pfx + b for pfx, b in zip(COPPER_PREFIXES[:4], bases)]
        waxed = [pfx + b for pfx, b in zip(COPPER_PREFIXES[4:], bases)]
        return unwaxed + waxed
    return None


def main(root: Path) -> None:
    refs = root / "net/minecraft/references"
    items_java = root / "net/minecraft/world/item/Items.java"
    dye_colors = parse_dye_colors(root / "net/minecraft/world/item/DyeColor.java")
    assert len(dye_colors) == 16, f"DyeColor 解析异常：{dye_colors}"

    # 引用表：常量 -> 单名（create）或集合展开（ColorCollection/WeatheringCopper）。
    # 特殊命名表（private ByState 字面量，如 COPPER_BLOCK_SPECIAL_NAMES）。
    special: dict[str, list] = {}
    for fname in ["BlockItemIds.java", "ItemIds.java"]:
        for m in re.finditer(
            r'private static final WeatheringCopperCollection\.ByState<String> (\w+)\s*=\s*new WeatheringCopperCollection\.ByState<[^>]*>\(([^)]*)\)',
            (refs / fname).read_text(),
        ):
            special[m.group(1)] = re.findall(r'"([^"]+)"', m.group(2))

    single: dict[str, str] = {}
    collections: dict[str, list] = {}
    entity_ids = parse_id_file(root / "net/minecraft/world/entity/EntityTypeIds.java")
    jukebox = parse_id_file(root / "net/minecraft/world/item/JukeboxSongs.java")
    for fname in ["BlockItemIds.java", "ItemIds.java"]:
        for const, (expr, args) in parse_create_map(refs / fname).items():
            names = expand_collection(expr, dye_colors, special)
            if names is not None:
                collections[const] = names
            elif args:
                single[const] = args[-1]
            else:
                # 工厂形态：createSpawnEgg / createMusicDisc（ItemIds 侧）。
                m = re.search(r'createSpawnEgg\(EntityTypeIds\.(\w+)\)', expr)
                if m is not None:
                    base = entity_ids.get(m.group(1), m.group(1).lower())
                    single[const] = f"{base}_spawn_egg"
                    continue
                m = re.search(r'createMusicDisc\(JukeboxSongs\.(\w+)\)', expr)
                if m is not None:
                    song = jukebox.get(m.group(1), [m.group(1).lower()])[-1]
                    song = "13" if song == "thirteen" else song
                    single[const] = f"music_disc_{song}"
                    continue
                m = re.search(r'createArmorTrimSmithingTemplate\((?:\w+\.)?(\w+)\)', expr)
                if m is not None:
                    # 判据 `createArmorTrimSmithingTemplate`：图案注册名 + 后缀。
                    single[const] = f"{m.group(1).lower()}_armor_trim_smithing_template"
                    continue
                m = re.search(r'createPotterySherd\((?:\w+\.)?(\w+)\)', expr)
                if m is not None:
                    single[const] = f"{m.group(1).lower()}_pottery_sherd"
                    continue

    text = items_java.read_text()
    # 按"字段声明"切开：任何 `public static final ` 开头都是一个字段
    #（Item 之外还有 ColorCollection<Item> 等泛型声明）；字段体取到第一个 `;`。
    chunks = text.split("public static final ")[1:]
    entries = []
    skipped = []
    for chunk in chunks:
        name_m = re.match(r'[\w<>\[\], .]+ (\w+) =', chunk)
        if name_m is None:
            continue
        const_name = name_m.group(1)
        body = chunk.split(";")[0]

        # ① 集合引用：按出现位置取第一个集合常量，整体展开。
        expanded = None
        for cm in re.finditer(r"(?:BlockItemIds|ItemIds)\.(\w+)", body):
            col = collections.get(cm.group(1))
            if col is not None:
                expanded = col
                break
        if expanded is not None:
            entries.extend(expanded)
            continue

        # ② 单名引用：body 中**位置最早**的引用优先。
        name = None
        refs = [(m.start(), m.group(1)) for m in
                re.finditer(r"(?:BlockItemIds|ItemIds)\.(\w+)", body)]
        for _, ref in sorted(refs):
            name = single.get(ref)
            if name is not None:
                break

        # ③ 字符串字面量直注册。
        if name is None:
            lit = re.search(r'registerItem\("([^"]+)"', body)
            name = lit.group(1) if lit else None

        if name is None:
            skipped.append(const_name)
            continue
        entries.append(name)

    out_path = Path(__file__).parent.parent / "lib/world/item/items_26_2.dart"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "// 由 tool/gen_item_registry_26_2.py 从官方 26.2 Items.java 生成。",
        "// **勿手改**：重新生成 = 重跑本工具。判据：",
        "// - `Items.java` 字段声明顺序 = 注册顺序（static init 即注册）；",
        "// - 注册名来自 `BlockItemIds.java` / `ItemIds.java` 的 create(...) 字面量；",
        "// - 集合字段按 ColorCollection(16 色序) / WeatheringCopperCollection(8 变体序) 展开；",
        "// - item 不是同步注册表（configuration 不下发），原版客户端同样内置此序",
        "//   （判据 `Item.java:104` holderRegistry(Registries.ITEM) 的注册序）。",
        "library;",
        "",
        "/// 26.2 物品注册序：`minecraft:<name>` → 注册序 id（SetCreativeModeSlot",
        "/// 的 itemId 来源）。共 %d 项；未解析跳过 %d 项（%s）。"
        % (len(entries), len(skipped), ", ".join(skipped[:6]) or "无"),
        "const Map<String, int> kItemRegistry262 = {",
    ]
    for idx, name in enumerate(entries):
        lines.append(f'  "minecraft:{name}": {idx},')
    lines.append("};")
    lines.append("")
    out_path.write_text("\n".join(lines))
    print(f"生成 {out_path}：{len(entries)} 项；跳过 {len(skipped)} 项")
    if skipped:
        print("跳过清单：", ", ".join(skipped))


if __name__ == "__main__":
    main(Path(sys.argv[1]))
