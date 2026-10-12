"""Apply exported script sources to a Roblox .rbxlx place at the XML text level (nothing else is re-serialised).

Usage:
  python apply_sources_xml.py --place in.rbxlx --out out.rbxlx --src DIR [--src DIR ...] [--dry-run]

Each file in a DIR is named "<Full.Roblox.Path>.luau" (e.g. ReplicatedStorage.FightingLab.Client.FrontEnd.luau).
Existing scripts get their <ProtectedString name="Source"> replaced. Missing scripts are created under their parent
path as ModuleScript, or Script / LocalScript when the file name ends in ".server.luau" / ".client.luau".
Later --src directories win when two directories contain the same path. The output is re-scanned and every applied
Source is verified byte-for-byte.
"""
import argparse
import html
import os
import re
import sys
import uuid

TOKEN = re.compile(
    r'<Item class="([^"]+)" referent="([^"]+)">|</Item>|<string name="Name">([^<]*)</string>'
    r'|<ProtectedString name="Source">|<!\[CDATA\['
)
SOURCE_OPEN = '<ProtectedString name="Source">'
SOURCE_CLOSE = "</ProtectedString>"


def scan(text):
    """Return the list of items: dict(cls, name, parent, close_start, src=(start, end) of the Source body)."""
    items, stack, pos = [], [], 0
    while True:
        m = TOKEN.search(text, pos)
        if not m:
            break
        tok = m.group(0)
        if tok.startswith("<Item"):
            items.append({"cls": m.group(1), "name": None, "parent": stack[-1] if stack else None,
                          "close_start": None, "src": None, "start": m.start()})
            stack.append(len(items) - 1)
            pos = m.end()
        elif tok == "</Item>":
            items[stack.pop()]["close_start"] = m.start()
            pos = m.end()
        elif tok.startswith('<string name="Name">'):
            top = items[stack[-1]]
            if top["name"] is None:
                top["name"] = html.unescape(m.group(3))
            pos = m.end()
        elif tok == SOURCE_OPEN:
            p = m.end()
            while text.startswith("<![CDATA[", p):
                p = text.index("]]>", p + 9) + 3
            if not text.startswith(SOURCE_CLOSE, p):
                raise ValueError(f"unexpected Source encoding at offset {m.start()}")
            top = items[stack[-1]]
            if top["src"] is None:
                top["src"] = (m.end(), p)
            pos = p + len(SOURCE_CLOSE)
        else:  # CDATA in some other property: skip it whole
            pos = text.index("]]>", m.end()) + 3
    if stack:
        raise ValueError("unbalanced <Item> tags")
    return items


def path_index(items):
    paths = {}
    for i, it in enumerate(items):
        parts, j = [], i
        while j is not None:
            parts.append(items[j]["name"] or "")
            j = items[j]["parent"]
        key = ".".join(reversed(parts))
        paths.setdefault(key, []).append(i)
    return paths


def decode_source(text, span):
    body = text[span[0]:span[1]]
    out, p = [], 0
    while p < len(body):
        if not body.startswith("<![CDATA[", p):
            raise ValueError("Source body is not pure CDATA")
        q = body.index("]]>", p + 9)
        out.append(body[p + 9:q])
        p = q + 3
    return "".join(out)


def encode_source(source):
    return "<![CDATA[" + source.replace("]]>", "]]]]><![CDATA[>") + "]]>"


def item_xml(cls, name, source, depth, children=()):
    """Serialize one new Item (a script with Source, or a Folder when source is None) with nested child items."""
    ind = "\t" * depth
    if cls == "Folder":
        props = [
            '<BinaryString name="AttributesSerialize"></BinaryString>',
            f'<string name="Name">{html.escape(name, quote=False)}</string>',
            '<BinaryString name="Tags"></BinaryString>',
        ]
    else:
        props = [
            '<Content name="LinkedSource"><null></null></Content>',
            f'<ProtectedString name="Source">{encode_source(source)}</ProtectedString>',
            f'<string name="ScriptGuid">{{{str(uuid.uuid4()).upper()}}}</string>',
            '<BinaryString name="AttributesSerialize"></BinaryString>',
            '<SecurityCapabilities name="Capabilities">0</SecurityCapabilities>',
            '<bool name="DefinesCapabilities">false</bool>',
            f'<string name="Name">{html.escape(name, quote=False)}</string>',
            '<BinaryString name="Tags"></BinaryString>',
        ]
        if cls in ("Script", "LocalScript"):
            props.insert(1, '<bool name="Disabled">false</bool>')
    ref = "RBX" + uuid.uuid4().hex.upper()
    body = "".join(f"\n{ind}\t\t{p}" for p in props)
    kids = "".join(f"\n{ind}\t{child}" for child in children)
    return f'<Item class="{cls}" referent="{ref}">\n{ind}\t<Properties>{body}\n{ind}\t</Properties>{kids}\n{ind}</Item>'


def new_item(cls, name, source, depth):
    return item_xml(cls, name, source, depth) + "\n" + "\t" * (depth - 1)


def load_sources(dirs):
    wanted = {}
    for d in dirs:
        for fn in sorted(os.listdir(d)):
            if not fn.endswith(".luau"):
                continue
            base, cls = fn[:-5], "ModuleScript"
            if base.endswith(".server"):
                base, cls = base[:-7], "Script"
            elif base.endswith(".client"):
                base, cls = base[:-7], "LocalScript"
            with open(os.path.join(d, fn), "rb") as fh:
                raw = fh.read()
            if raw.startswith(b"\xef\xbb\xbf"):
                raise SystemExit(f"BOM in {os.path.join(d, fn)}")
            wanted[base] = (cls, raw.decode("utf-8"), os.path.join(d, fn))
    return wanted


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--place", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--src", action="append", required=True)
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    with open(a.place, encoding="utf-8", newline="") as fh:
        text = fh.read()
    items = scan(text)
    paths = path_index(items)
    wanted = load_sources(a.src)

    edits, report = [], []
    # New items are grouped under their nearest existing ancestor and inserted there as one nested subtree, so new
    # modules may live under new modules, and missing intermediate path segments become Folders.
    subtrees = {}
    for path, (cls, source, origin) in wanted.items():
        hits = paths.get(path, [])
        if len(hits) > 1:
            raise SystemExit(f"ambiguous path {path} ({len(hits)} items)")
        if hits:
            it = items[hits[0]]
            if it["src"] is None:
                raise SystemExit(f"{path} is a {it['cls']} without Source")
            if decode_source(text, it["src"]) == source:
                report.append(f"unchanged {path}")
                continue
            edits.append((it["src"][0], it["src"][1], encode_source(source)))
            report.append(f"updated   {path}")
            continue
        segments = path.split(".")
        k = len(segments) - 1
        while k > 0 and ".".join(segments[:k]) not in paths:
            k -= 1
        if k == 0:
            raise SystemExit(f"cannot create {path}: no existing ancestor")
        anchor = ".".join(segments[:k])
        if len(paths[anchor]) != 1:
            raise SystemExit(f"cannot create {path}: ancestor {anchor} matches {len(paths[anchor])} items")
        node = subtrees.setdefault(anchor, {})
        for seg in segments[k:]:
            node = node.setdefault(seg, {"cls": "Folder", "source": None, "children": {}})
            last = node
            node = node["children"]
        last["cls"], last["source"] = cls, source
        report.append(f"created   {path} ({cls})")

    def serialize(children, depth, prefix):
        out = []
        for name, child in children.items():
            if child["source"] is None:
                report.append(f"created   {prefix}.{name} (Folder)")
            out.append(item_xml(child["cls"], name, child["source"], depth,
                                serialize(child["children"], depth + 1, f"{prefix}.{name}")))
        return out

    for anchor, children in subtrees.items():
        index = paths[anchor][0]
        depth, j = 1, index
        while items[j]["parent"] is not None:
            depth, j = depth + 1, items[j]["parent"]
        pos = items[index]["close_start"]
        xml = "".join(x + "\n" + "\t" * depth for x in serialize(children, depth + 1, anchor))
        edits.append((pos, pos, xml))

    print("\n".join(sorted(report)))
    if a.dry_run:
        return
    for start, end, repl in sorted(edits, key=lambda e: e[0], reverse=True):
        text = text[:start] + repl + text[end:]
    with open(a.out, "w", encoding="utf-8", newline="") as fh:
        fh.write(text)

    check_items = scan(text)
    check_paths = path_index(check_items)
    for path, (cls, source, origin) in wanted.items():
        hits = check_paths.get(path, [])
        if len(hits) != 1 or decode_source(text, check_items[hits[0]]["src"]) != source:
            raise SystemExit(f"VERIFY FAILED for {path}")
    print(f"verified {len(wanted)} sources; items {len(items)} -> {len(check_items)}; wrote {a.out}")


if __name__ == "__main__":
    sys.exit(main())
