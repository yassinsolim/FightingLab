"""Mocap -> FLClip1 / FLThrow1 Luau clip modules.

Usage:
  python convert.py --spec specs/core.json --out <dir> [--review <dir>] [--only Name1,Name2] [--catalog <catalog.json>]

Spec (JSON):
  {
    "folder": "Core" | "Moves.Strikes" | "Moves.Kicks" | "Moves.Throws",   # Motion.Clips.<folder> (dots = subfolders)
    "sources": { "<id>": { "root": "<dir, relative to OV6 or absolute>", "calib": ["<file>", <frame>],
                           "asf": "<CMU asf (relative to root)>", "license": "...", "credit": "..." } },
    "clips": [ {
        "name": "Kael_Jab",                             # module name (unique within the folder)
        "catalog": "accad-male2-e1-jableft",            # file/range/fps/target/contact taken from catalog.json
        "source": "<id>", "file": "<path relative to the source root>", "fps": 120,  # when not using "catalog"
        "range": [start, end],                          # source frames, inclusive (0-based, as in the catalog)
        "target": [x, z] | "pelvis" | "chest" | "head" | "travel" | "-travel",   # source XZ toward the opponent
        "yawOffset": 0, "loop": false, "travel": "remove" | "linear" | "center" | "none",
        "mirror": false,                                # bake a left/right mirror (right-lead capture -> left lead)
        "contact": <source frame>, "recover": <source frame>,   # attacks: contact lands on the first active frame
        "fighter": "Kael" | "*", "move": "<Roster move key>", "stringIndex": 2, "mirrorAtRuntime": false,
        "smooth": 1.0, "floor": <metres>, "ground": "auto" | 0..1, "outFps": 30, "tags": {...},
        "sources": ["<catalog id>", ...],               # credits; defaults to [catalog]
        "leadIn": { "from": "Displayed:Rhys", "seconds": 0.6 }   # optional stepped transition from that pose into frame 0
    },
    { "format": "FLThrow1", "name": "Goran_BearHug", "fighter": "Goran", "move": "BearHug",
      "attacker": { <clip fields> }, "defender": { <clip fields, defender's own heading> },
      "impact": <attacker source frame>, "distance": <attacker leg lengths, default: measured from the two captures> } ]
  }
Writes ReplicatedStorage.FightingLab.Client.Motion.Clips.<folder>.<name>.luau per clip (UTF-8, LF; line 1 =
"-- sources: <ids>"), a review sheet per clip with --review, and manifest-<folder>.json.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import canon as canonmod  # noqa: E402
import clipio  # noqa: E402
import retarget as rt  # noqa: E402
import review  # noqa: E402

OV6 = os.path.abspath(os.path.join(HERE, "..", ".."))
DEFAULT_CATALOG = os.path.join(OV6, "research", "motion", "catalog.json")


def resolve(path: str, base: str) -> str:
    return path if os.path.isabs(path) else os.path.join(base, path)


def merged_spec(clip: dict, catalog: dict) -> dict:
    spec = dict(clip)
    cid = clip.get("catalog")
    if cid:
        entry = catalog.get(cid)
        if not entry:
            raise KeyError(f"catalog id {cid} not found")
        spec.setdefault("file", os.path.join(OV6, "research", "motion", entry["localFile"]))
        spec.setdefault("fps", entry.get("fps"))
        spec.setdefault("range", [entry["start"], entry["end"]])
        if entry.get("targetDirXZ") is not None:
            spec.setdefault("target", entry["targetDirXZ"])
        if entry.get("contactFrame") is not None and "contact" not in spec and spec.get("useCatalogContact", True):
            spec["contact"] = entry["contactFrame"]
        spec.setdefault("license", entry.get("license"))
        spec.setdefault("credit", entry.get("credit"))
    return spec


_canon_cache: dict = {}


def load_canon(spec: dict, sources: dict) -> canonmod.Canon:
    src = sources.get(spec.get("source", ""), {})
    root = resolve(src.get("root", ""), OV6) if src else OV6
    path = resolve(spec["file"], root)
    calib = None
    if src.get("calib"):
        calib = (resolve(src["calib"][0], root), int(src["calib"][1]))
    if spec.get("calib"):
        calib = (resolve(spec["calib"][0], root), int(spec["calib"][1]))
    asf = None
    if path.lower().endswith(".amc"):
        asf = spec.get("asf") or src.get("asf")
        if asf:
            asf = resolve(asf, root)
        else:
            subj = os.path.basename(path).split("_")[0]
            asf = os.path.join(os.path.dirname(path), subj + ".asf")
    key = (path, calib, asf, spec.get("fps"))
    if key not in _canon_cache:
        _canon_cache[key] = canonmod.load(path, fps=spec.get("fps"), asf=asf, calib=calib)
    return _canon_cache[key]


def convert_track(clip: dict, sources: dict, catalog: dict) -> dict:
    """Retargets one track. Returns spec, canon, channels, meta, label, ids, license, credit."""
    spec = merged_spec(clip, catalog)
    src = sources.get(spec.get("source", ""), {})
    c = load_canon(spec, sources)
    rspec = dict(spec)
    rspec["fps"] = spec.get("outFps", 30)
    result = rt.retarget(c, rspec)
    if spec.get("reverse"):
        # Play the capture backwards (e.g. a forward roll -> a backward roll); travel was already removed.
        result["channels"] = np.ascontiguousarray(result["channels"][:, ::-1])
    if spec.get("overlay"):
        result["channels"] = apply_overlay(result["channels"], spec["overlay"])
    meta = result["meta"]
    meta["tags"] = spec.get("tags", {})
    for key in ("fighter", "move", "stringIndex", "mirrorAtRuntime"):
        if spec.get(key) is not None:
            meta[key] = spec[key]
    used = meta.get("range", spec["range"])
    base_label = spec.get("catalog") or os.path.basename(spec["file"])
    ids = list(spec.get("sources") or ([spec["catalog"]] if spec.get("catalog") else []))
    if not ids:
        raise ValueError(f"clip {spec.get('name')}: give a catalog id ('catalog') or 'sources' for the credits header")
    return {
        "spec": dict(spec, range=used), "canon": c, "channels": result["channels"], "meta": meta, "result": result,
        "label": f"{base_label} [{used[0]}:{used[1]}]", "ids": ids,
        "license": spec.get("license") or src.get("license", ""), "credit": spec.get("credit") or src.get("credit", ""),
    }


def _curve(points: list, n: int) -> np.ndarray:
    """(n, 3) piecewise-linear curve over normalised clip time from [[u, [x, y, z]], ...], lightly smoothed."""
    u = np.linspace(0, 1, n)
    us = np.array([float(p[0]) for p in points])
    vals = np.array([p[1] for p in points], dtype=float)
    out = np.stack([np.interp(u, us, vals[:, k]) for k in range(3)], axis=1)
    if n > 4:
        from scipy.ndimage import gaussian_filter1d
        out = gaussian_filter1d(out, 1.0, axis=0, mode="nearest")
    return out


def apply_overlay(ch: np.ndarray, overlay: dict) -> np.ndarray:
    """Hand-authored layer on top of a mocap clip (library axes: +X right, +Y up, +Z toward the opponent; degrees for
    rotations, leg lengths for positions; each curve is [[u 0..1, [x, y, z]], ...] over the clip):
      root       pelvis offset, feet stay planted (weight shifts, dips, leans away from the fight line)
      rootFeet   pelvis AND feet together (a hop)
      rootRot / waist / neck   extra rotation (x+ leans back, y+ turns left, z+ leans left), applied in the parent frame
    """
    import keyed
    out = ch.copy()
    n = ch.shape[1]
    for key, feet in (("root", False), ("rootFeet", True)):
        if key in overlay:
            d = _curve(overlay[key], n).T.copy()
            d[2] *= -1
            out[0:3] += d
            if not feet:
                out[35:38] -= d
                out[45:48] -= d
    for key, base in (("rootRot", 3), ("waist", 7), ("neck", 11)):
        if key in overlay:
            e = _curve(overlay[key], n)
            for i in range(n):
                q = rt.quat_mul(keyed.euler_to_quat(e[i]), out[base:base + 4, i])
                out[base:base + 4, i] = q / max(np.linalg.norm(q), 1e-9)
    return out


def apply_lead_in(ch: np.ndarray, lead: dict, fps: float, clip_dirs: list[str]) -> np.ndarray:
    """Prepends a stepped transition INTO the clip: from a start pose ("from": "Displayed:<Fighter>" = that fighter's
    idle exactly as the game shows it, or "<Clip>@<s>") to the clip's first frame over `seconds`. Body channels ease
    (quaternions slerp); each foot that has to move more than `stepMin` leg lengths takes a lifted step (the longer step
    first, overlapping), with its contact released while it is in the air; other feet stay planted. Use it for clips
    that start far from the fighting stance (victories, bows, defeats), so the runtime fade has nothing left to skate."""
    import keyed
    start = keyed.frame_from(lead["from"], clip_dirs)
    n = max(int(round(float(lead.get("seconds", 0.5)) * fps)), 2)
    end = ch[:, 0].copy()
    moves = {}
    for base in (35, 45):
        a = start[0:3] + start[base:base + 3]
        b = end[0:3] + end[base:base + 3]
        moves[base] = (a, b, float(np.linalg.norm((b - a)[[0, 2]])))
    step_min = float(lead.get("stepMin", 0.04))
    order = sorted((b for b in (35, 45) if moves[b][2] > step_min), key=lambda b: -moves[b][2])
    windows = {}
    if len(order) == 2:
        windows = {order[0]: (0.05, 0.55), order[1]: (0.42, 0.95)}
    elif len(order) == 1:
        windows = {order[0]: (0.15, 0.85)}
    out = np.zeros((ch.shape[0], n))
    for i in range(n):
        u = i / n  # never 1: the clip's own frame 0 follows
        w = u * u * (3 - 2 * u)
        v = start * (1 - w) + end * w
        for q in (3, 7, 11, 21, 31, 41, 51):
            v[q:q + 4] = keyed.slerp(start[q:q + 4], end[q:q + 4], w)
        for p in (18, 28, 38, 48):
            v[p:p + 3] /= max(np.linalg.norm(v[p:p + 3]), 1e-9)
        root = v[0:3]
        for base, ci in ((35, 55), (45, 56)):
            a, b, d = moves[base]
            if base in windows:
                s0, s1 = windows[base]
                k = float(np.clip((u - s0) / (s1 - s0), 0, 1))
                ks = k * k * (3 - 2 * k)
                pos = a * (1 - ks) + b * ks
                pos[1] += math.sin(math.pi * k) * (0.05 + 0.12 * d)
                v[ci] = 0.0 if 0 < k < 1 else max(start[ci], end[ci], 1.0)
            else:
                pos = a * (1 - w) + b * w
                v[ci] = 1.0
            v[base:base + 3] = pos - root
        out[:, i] = v
    return np.concatenate([out, ch], axis=1)


def roundtrip_error(text: str, channels: np.ndarray) -> float:
    """Max quantisation error of the first clip table in a module (decode(encode(x)) vs x)."""
    chunk = text.split('layout = "', 1)[1]
    layout = chunk.split('"', 1)[0]
    data = chunk.split('data = "', 1)[1].split('"', 1)[0]
    back = clipio.decode(layout, data, channels.shape[1])
    return float(np.max(np.abs(back - np.clip(channels, -2, 2))))

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--spec", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--review")
    ap.add_argument("--only")
    ap.add_argument("--catalog", default=DEFAULT_CATALOG)
    ap.add_argument("--clips", help="directory with the Core clip modules + Motion.States for leadIn 'from' poses (default: work src, then handoff)")
    args = ap.parse_args()
    clip_dirs = [args.clips] if args.clips else [os.path.join(OV6, "work", "motioncore", "src"), os.path.join(OV6, "handoff", "motioncore-src")]
    spec_doc = json.load(open(args.spec, encoding="utf-8-sig"))
    catalog = {}
    if os.path.exists(args.catalog):
        catalog = {e["id"]: e for e in json.load(open(args.catalog, encoding="utf-8-sig"))}
    folder = spec_doc.get("folder", "Core").replace("/", ".")
    sources = spec_doc.get("sources", {})
    only = set(args.only.split(",")) if args.only else None
    os.makedirs(args.out, exist_ok=True)
    if args.review:
        os.makedirs(args.review, exist_ok=True)
    manifest = []
    total = 0
    for clip in spec_doc["clips"]:
        if only and clip["name"] not in only:
            continue
        name = clip["name"]
        path = os.path.join(args.out, f"ReplicatedStorage.FightingLab.Client.Motion.Clips.{folder}.{name}.luau")
        if clip.get("format") == "FLThrow1":
            att = convert_track(dict(clip["attacker"], name=name + ".attacker"), sources, catalog)
            dfd = convert_track(dict(clip["defender"], name=name + ".defender"), sources, catalog)
            impact = clip.get("impact")
            a0, a1 = att["spec"]["range"]
            impact_n = float(np.clip((float(impact) - a0) / max(a1 - a0, 1), 0, 1)) if impact is not None else 0.6
            distance = clip.get("distance")
            if distance is None:
                pa = att["canon"].p["pelvis"][a0]
                pd = dfd["canon"].p["pelvis"][dfd["spec"]["range"][0]]
                distance = float(np.linalg.norm((pa - pd)[[0, 2]]) / att["canon"].lengths["leg"])
            ids = sorted(set(att["ids"]) | set(dfd["ids"]) | set(clip.get("sources") or []))
            meta = {"fighter": clip.get("fighter"), "move": clip["move"], "impact": impact_n, "distance": distance}
            text, clipped = clipio.throw_module(name, (att["channels"], att["meta"]), (dfd["channels"], dfd["meta"]), meta,
                                               att["label"] + " + " + dfd["label"], att["license"], att["credit"], ids)
            frames = att["meta"]["frames"]
            err = roundtrip_error(text, att["channels"])
            entry = {"name": name, "format": "FLThrow1", "folder": folder, "fighter": clip.get("fighter"), "move": clip["move"],
                     "impact": impact_n, "distance": round(distance, 3), "sources": ids, "frames": frames}
            if args.review:
                review.review_sheet(att["canon"], att["spec"], att["result"], os.path.join(args.review, name + ".attacker.png"))
                review.review_sheet(dfd["canon"], dfd["spec"], dfd["result"], os.path.join(args.review, name + ".defender.png"))
        else:
            tr = convert_track(clip, sources, catalog)
            meta = tr["meta"]
            if clip.get("leadIn"):
                n0 = tr["channels"].shape[1]
                tr["channels"] = apply_lead_in(tr["channels"], clip["leadIn"], float(meta["fps"]), clip_dirs)
                added = tr["channels"].shape[1] - n0
                meta["frames"] = tr["channels"].shape[1]
                for key in ("contact", "recover"):
                    if meta.get(key) is not None:
                        meta[key] = (meta[key] * (n0 - 1) + added) / max(n0 - 1 + added, 1)
            text, clipped = clipio.luau_module(name, tr["channels"], meta, tr["label"], tr["license"], tr["credit"], tr["ids"])
            frames = meta["frames"]
            err = roundtrip_error(text, tr["channels"])
            entry = {"name": name, "format": "FLClip1", "folder": folder, "frames": frames, "fps": meta["fps"], "loop": meta["loop"],
                     "speed": round(meta["speed"], 4), "yawDeg": round(meta["yawDeg"], 1), "sources": tr["ids"], "source": tr["label"],
                     "license": tr["license"], "contact": meta.get("contact"), "recover": meta.get("recover"),
                     "fighter": meta.get("fighter"), "move": meta.get("move")}
            if args.review:
                review.review_sheet(tr["canon"], tr["spec"], tr["result"], os.path.join(args.review, name + ".png"))
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)
        size = len(text.encode("utf-8"))
        total += size
        entry.update({"bytes": size, "clipped": clipped, "maxQuantError": round(err, 5)})
        manifest.append(entry)
        print(f"{name:28s} {frames:4d} f  {size / 1024:6.1f} KB  clipped {clipped}  q {err:.4f}")
    with open(os.path.join(args.review or args.out, f"manifest-{folder}.json"), "w", encoding="utf-8", newline="\n") as fh:
        json.dump(manifest, fh, indent=1)
    print(f"{len(manifest)} clips, {total / 1024:.1f} KB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
