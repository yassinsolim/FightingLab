"""Export catalogued segments as per-frame canonical joint positions (for retargeting / clip conversion).

    python export_clip.py <id> [<id> ...] [--fps 60] [--out-dir ../export]
    python export_clip.py --label punch-jab --min-quality 4

Output JSON per clip (meters):
  { id, label, source, credit, srcFps, fps, frames, joints: [24 canonical names], contactFrame (re-based to the
    segment, resampled), lead, frame: "x=actor-left, y=up, z=toward opponent (catalog targetDirXZ); origin = pelvis
    XZ at segment start, y=0 on the floor", positions: [frames][24][3], rootYawDeg: [frames] }
Resampling is linear (positions). Contact frame index is mapped to the output fps.
"""
import argparse
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from mocap import load_motion, CANON  # noqa: E402

M = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CI = {n: i for i, n in enumerate(CANON)}


def export(e, fps_out):
    mo = load_motion(os.path.join(M, e["localFile"]), fps=e["fps"])
    c = mo.canon()
    a, b = e["start"], e["end"]
    t = e.get("targetDirXZ") or [0.0, 1.0]
    fwd = np.array([t[0], 0.0, t[1]])
    fwd /= np.linalg.norm(fwd)
    left = np.cross([0.0, 1.0, 0.0], fwd)
    seg = c[a: b + 1]
    floor = float(np.percentile(np.minimum(seg[:, CI["ltoe"], 1], seg[:, CI["rtoe"], 1]), 1))
    o = seg[0, CI["pelvis"]].copy()
    rel = seg - o
    loc = np.stack([rel @ left, seg[..., 1] - floor, rel @ fwd], -1)
    n_in = len(loc)
    dur = (n_in - 1) / mo.fps
    fps = fps_out or mo.fps
    n_out = max(1, int(round(dur * fps)) + 1)
    ts = np.linspace(0, n_in - 1, n_out)
    i0 = np.floor(ts).astype(int)
    i1 = np.minimum(i0 + 1, n_in - 1)
    w = (ts - i0)[:, None, None]
    out = loc[i0] * (1 - w) + loc[i1] * w
    lat = (out[:, CI["lhip"]] - out[:, CI["rhip"]]) + (out[:, CI["lshoulder"]] - out[:, CI["rshoulder"]])
    yaw = np.degrees(np.arctan2(-lat[:, 2], lat[:, 0]))  # 0 = hips square to the opponent
    cf = e.get("contactFrame")
    cf_out = None if cf is None else int(round((cf - a) / mo.fps * fps))
    return {
        "id": e["id"], "label": e["label"], "source": e["source"], "credit": e["credit"], "license": e["license"],
        "srcFile": e["localFile"], "srcFps": mo.fps, "srcStart": a, "srcEnd": b, "fps": fps, "frames": n_out,
        "joints": CANON, "contactFrame": cf_out, "lead": e.get("lead"), "stance": e.get("stance"),
        "frame": "x=actor-left, y=up, z=toward opponent; origin=pelvis XZ at segment start; y=0 floor",
        "positions": np.round(out, 4).tolist(), "rootYawDeg": np.round(yaw, 2).tolist(),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ids", nargs="*")
    ap.add_argument("--label")
    ap.add_argument("--min-quality", type=int, default=1)
    ap.add_argument("--fps", type=float, default=60.0)
    ap.add_argument("--out-dir", default=os.path.join(M, "export"))
    a = ap.parse_args()
    cat = json.load(open(os.path.join(M, "catalog.json")))
    byid = {e["id"]: e for e in cat}
    sel = [byid[i] for i in a.ids]
    if a.label:
        sel += [e for e in cat if e["label"] in a.label.split(",") and e["quality"] >= a.min_quality]
    os.makedirs(a.out_dir, exist_ok=True)
    for e in sel:
        d = export(e, a.fps)
        p = os.path.join(a.out_dir, e["id"] + ".json")
        json.dump(d, open(p, "w"))
        print("wrote", os.path.relpath(p, M), d["frames"], "frames @", d["fps"], "contact", d["contactFrame"])


if __name__ == "__main__":
    main()
