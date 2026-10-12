"""Export every script Source from a Roblox .rbxlx place into <outDir>/<Full.Roblox.Path>.luau (UTF-8, no BOM).

Usage:
  python extract_sources.py --place in.rbxlx --out DIR [--prefix ReplicatedStorage.FightingLab --prefix ...]

Read-only on the place file. Script classes are recorded in <outDir>/_classes.json so new scripts can be recreated
with the right class. Only items that own a Source property are exported.
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from apply_sources_xml import decode_source, path_index, scan  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--place", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--prefix", action="append", default=[])
    a = ap.parse_args()

    with open(a.place, encoding="utf-8", newline="") as fh:
        text = fh.read()
    items = scan(text)
    paths = path_index(items)
    os.makedirs(a.out, exist_ok=True)
    classes, count = {}, 0
    for path, idxs in sorted(paths.items()):
        if a.prefix and not any(path == p or path.startswith(p + ".") for p in a.prefix):
            continue
        for i in idxs:
            it = items[i]
            if it["src"] is None:
                continue
            if len(idxs) > 1:
                raise SystemExit(f"ambiguous script path {path}")
            source = decode_source(text, it["src"])
            with open(os.path.join(a.out, path + ".luau"), "w", encoding="utf-8", newline="") as fh:
                fh.write(source)
            classes[path] = it["cls"]
            count += 1
    with open(os.path.join(a.out, "_classes.json"), "w", encoding="utf-8") as fh:
        json.dump(classes, fh, indent=1, sort_keys=True)
    print(f"exported {count} scripts to {a.out}")


if __name__ == "__main__":
    main()
