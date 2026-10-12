"""Set top-level service properties in a Roblox .rbxlx at the XML text level (nothing else is re-serialised).

  python set_place_props.py --place in.rbxlx --out out.rbxlx --set MaterialService.Use2022MaterialsXml=true
                            [--set Terrain.Decoration=true] [--set Lighting.Technology=4]

Each --set names a class that must occur exactly once in the place and a property that must already be serialised
on it (bool, token, int, float or string). The value is written verbatim. The output is re-read and verified.
"""
import argparse
import re
import sys


def find_props_block(text, cls):
    starts = [m.start() for m in re.finditer(r'<Item class="%s" referent="[^"]+">' % re.escape(cls), text)]
    if len(starts) != 1:
        raise SystemExit(f"class {cls} occurs {len(starts)} times (need exactly 1)")
    start = text.index("<Properties>", starts[0])
    end = text.index("</Properties>", start)
    return start, end


def set_prop(text, cls, prop, value):
    start, end = find_props_block(text, cls)
    block = text[start:end]
    pattern = re.compile(r'<(bool|token|int|float|string) name="%s">([^<]*)</\1>' % re.escape(prop))
    hits = list(pattern.finditer(block))
    if len(hits) != 1:
        raise SystemExit(f"{cls}.{prop} occurs {len(hits)} times in its Properties block (need exactly 1)")
    m = hits[0]
    old = m.group(2)
    new_tag = f'<{m.group(1)} name="{prop}">{value}</{m.group(1)}>'
    block = block[:m.start()] + new_tag + block[m.end():]
    return text[:start] + block + text[end:], old


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--place", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--set", action="append", required=True)
    a = ap.parse_args()
    with open(a.place, encoding="utf-8", newline="") as fh:
        text = fh.read()
    wanted = []
    for item in a.set:
        key, value = item.split("=", 1)
        cls, prop = key.split(".", 1)
        text, old = set_prop(text, cls, prop, value)
        wanted.append((cls, prop, value))
        print(f"{cls}.{prop}: {old} -> {value}")
    with open(a.out, "w", encoding="utf-8", newline="") as fh:
        fh.write(text)
    with open(a.out, encoding="utf-8", newline="") as fh:
        check = fh.read()
    for cls, prop, value in wanted:
        start, end = find_props_block(check, cls)
        if f'name="{prop}">{value}<' not in check[start:end]:
            raise SystemExit(f"VERIFY FAILED for {cls}.{prop}")
    print(f"verified {len(wanted)} properties; wrote {a.out}")


if __name__ == "__main__":
    sys.exit(main())
