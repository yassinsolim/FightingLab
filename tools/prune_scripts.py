"""Remove scripts from a Roblox .rbxlx place that no longer exist in src/ (XML text level, nothing else re-serialised).

  python prune_scripts.py --place in.rbxlx --out out.rbxlx --src DIR --prefix ReplicatedStorage.FightingLab ... [--max N]

Only script items (ModuleScript / Script / LocalScript) under the given path prefixes are considered. An item is removed
when no "<path>.luau" (or .server/.client) file exists for it in DIR. A script that still has descendants present in DIR
is never removed. At most --max scripts are removed unless the limit is raised (safety against a partial src folder).
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from apply_sources_xml import load_sources, path_index, scan  # noqa: E402

SCRIPT_CLASSES = {"ModuleScript", "Script", "LocalScript"}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--place", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--src", required=True)
    ap.add_argument("--prefix", action="append", required=True)
    ap.add_argument("--max", type=int, default=10)
    a = ap.parse_args()

    with open(a.place, encoding="utf-8", newline="") as fh:
        text = fh.read()
    items = scan(text)
    paths = path_index(items)
    path_of = {i: p for p, idxs in paths.items() for i in idxs}
    wanted = set(load_sources([a.src]))

    def under_prefix(path):
        return any(path == p or path.startswith(p + ".") for p in a.prefix)

    doomed = []
    for i, it in enumerate(items):
        path = path_of[i]
        if it["cls"] not in SCRIPT_CLASSES or not under_prefix(path) or path in wanted:
            continue
        # A removed item takes its whole subtree with it: never drop a script that still has live descendants.
        live = [p for p in wanted if p.startswith(path + ".")]
        if live:
            raise SystemExit(f"refusing to remove {path}: it still contains {live[0]}")
        doomed.append(i)
    # Drop nested duplicates (a doomed item inside another doomed item is removed with its ancestor).
    doomed_set = set(doomed)

    def has_doomed_ancestor(i):
        j = items[i]["parent"]
        while j is not None:
            if j in doomed_set:
                return True
            j = items[j]["parent"]
        return False

    roots = [i for i in doomed if not has_doomed_ancestor(i)]
    if len(roots) > a.max:
        raise SystemExit(f"{len(roots)} scripts would be removed (limit {a.max}); is the src folder complete?")
    spans = []
    for i in roots:
        it = items[i]
        start = it["start"]
        while start > 0 and text[start - 1] in " \t\r\n":
            start -= 1
        end = it["close_start"] + len("</Item>")
        spans.append((start, end))
        print(f"removed   {path_of[i]} ({it['cls']})")
    for start, end in sorted(spans, reverse=True):
        text = text[:start] + text[end:]
    with open(a.out, "w", encoding="utf-8", newline="") as fh:
        fh.write(text)
    # Verify: the output parses and none of the removed paths remain.
    check = path_index(scan(text))
    for i in roots:
        if path_of[i] in check:
            raise SystemExit(f"VERIFY FAILED: {path_of[i]} still present")
    print(f"pruned {len(roots)} scripts; items {len(items)} -> {sum(len(v) for v in check.values())}")


if __name__ == "__main__":
    main()
