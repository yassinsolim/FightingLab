"""Remove stale post effects / atmosphere saved under Lighting in a .rbxlx (text-level, no Lune round-trip).

Stage presets are applied at runtime by the client; effects saved into the place's Lighting replicate to every
client and stack with the runtime stage grade. Items whose Name starts with a --keep prefix are preserved.

  python remove_lighting_effects.py --place in.rbxlx --out out.rbxlx [--keep FightingLabCharacter]
"""
import argparse
import re
import sys
import xml.etree.ElementTree as ET

EFFECT_CLASSES = {"BloomEffect", "BlurEffect", "ColorCorrectionEffect", "DepthOfFieldEffect", "SunRaysEffect", "Atmosphere"}
TAG = re.compile(r'<Item class="([^"]+)" referent="[^"]+">|</Item>')
NAME = re.compile(r'<string name="Name">([^<]*)</string>')


def find_lighting_children(s: str):
    start = s.find('<Item class="Lighting"')
    if start < 0:
        raise SystemExit("no Lighting item")
    body = s.find(">", start) + 1
    level = 1
    children = []
    stack = []
    for m in TAG.finditer(s, body):
        if m.group(0) == "</Item>":
            level -= 1
            if level == 0:
                break
            if level == 1 and stack:
                cls, child_start = stack.pop()
                children.append((cls, child_start, m.end()))
        else:
            if level == 1:
                stack.append((m.group(1), m.start()))
            level += 1
    return children


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--place", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--keep", action="append", default=["FightingLabCharacter"])
    a = ap.parse_args()
    s = open(a.place, encoding="utf-8", newline="").read()
    removed = []
    for cls, begin, end in reversed(find_lighting_children(s)):
        if cls not in EFFECT_CLASSES:
            continue
        name_match = NAME.search(s, begin, end)
        name = name_match.group(1) if name_match else "?"
        if any(name.startswith(k) for k in a.keep):
            continue
        # Drop the item plus the whitespace that indented it.
        line_start = s.rfind("\n", 0, begin) + 1
        cut_start = line_start if s[line_start:begin].strip() == "" else begin
        s = s[:cut_start] + s[end:]
        removed.append(f"{cls}:{name}")
    ET.fromstring(s.encode("utf-8"))  # must still be well-formed XML
    with open(a.out, "w", encoding="utf-8", newline="") as f:
        f.write(s)
    print("removed", len(removed), ", ".join(reversed(removed)))
    print("wrote", a.out)


if __name__ == "__main__":
    sys.exit(main())
