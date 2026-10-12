"""Convert JSON data files into a Luau ModuleScript source (a pure data table plus per-entry content hashes).

  python json_to_luau.py --out <Full.Roblox.Path>.luau --entry Kael=path/Kael.json --entry Sierra=path/Sierra.json ...

Output shape:
  return { order = { "Kael", ... }, hashes = { Kael = "<sha1>", ... }, specs = { Kael = { ... }, ... } }
The hash is computed from the canonical JSON (sorted keys) so a consumer can tell whether a saved instance built from
an entry is still current.
"""
import argparse
import hashlib
import json
import re

IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
KEYWORDS = {"and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in", "local", "nil",
            "not", "or", "repeat", "return", "then", "true", "until", "while", "continue", "type", "export"}


def lua_string(s):
    out = ['"']
    for ch in s:
        o = ord(ch)
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\r")
        elif ch == "\t":
            out.append("\\t")
        elif o < 32 or o == 127:
            out.append(f"\\{o:03d}")
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def lua_key(k):
    if IDENT.match(k) and k not in KEYWORDS:
        return k
    return "[" + lua_string(k) + "]"


def to_lua(v, indent):
    pad = "\t" * indent
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        return repr(v)
    if isinstance(v, str):
        return lua_string(v)
    if isinstance(v, list):
        if not v:
            return "{}"
        if all(isinstance(x, (int, float, bool, str)) or x is None for x in v) and len(v) <= 8:
            return "{ " + ", ".join(to_lua(x, 0) for x in v) + " }"
        inner = ",\n".join(pad + "\t" + to_lua(x, indent + 1) for x in v)
        return "{\n" + inner + ",\n" + pad + "}"
    if isinstance(v, dict):
        if not v:
            return "{}"
        inner = ",\n".join(f"{pad}\t{lua_key(k)} = {to_lua(x, indent + 1)}" for k, x in v.items())
        return "{\n" + inner + ",\n" + pad + "}"
    raise TypeError(f"unsupported JSON value {v!r}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--entry", action="append", required=True)
    ap.add_argument("--comment", default="Generated data module. Do not edit by hand; regenerate from the JSON sources.")
    a = ap.parse_args()

    order, hashes, specs = [], {}, {}
    for e in a.entry:
        name, path = e.split("=", 1)
        with open(path, encoding="utf-8-sig") as fh:
            data = json.load(fh)
        canonical = json.dumps(data, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        order.append(name)
        hashes[name] = hashlib.sha1(canonical.encode("utf-8")).hexdigest()
        specs[name] = data
    lines = ["--!strict", "-- " + a.comment, "return {",
             "\torder = " + to_lua(order, 1) + ",",
             "\thashes = " + to_lua(hashes, 1) + ",",
             "\tspecs = " + to_lua(specs, 1) + ",", "}", ""]
    with open(a.out, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines))
    print(f"wrote {a.out}: {', '.join(order)}")


if __name__ == "__main__":
    main()
