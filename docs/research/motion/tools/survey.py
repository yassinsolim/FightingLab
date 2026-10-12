"""Survey downloaded takes: duration, pelvis height profile, strike peaks. Writes work/survey.json + prints a table."""
import glob
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from mocap import load_motion, CANON  # noqa: E402
from events import CI, per_frame_facing, reach_curve, find_peaks, floor_y  # noqa: E402

M = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def survey(path):
    mo = load_motion(path)
    c = mo.canon()
    fps = mo.fps
    fl = floor_y(c)
    ph = c[:, CI["pelvis"], 1] - fl
    hd = c[:, CI["headtop"], 1] - fl
    fwd, _ = per_frame_facing(c, fps)
    out = {"file": os.path.relpath(path, M).replace("\\", "/"), "frames": mo.n_frames, "fps": fps,
           "dur": round(mo.n_frames / fps, 2), "pelvis_min": round(float(ph.min()), 2), "pelvis_max": round(float(ph.max()), 2),
           "head_min": round(float(hd.min()), 2), "head_max": round(float(hd.max()), 2),
           "travel": round(float(np.linalg.norm((c[-1, 0] - c[0, 0])[[0, 2]])), 2)}
    ev = {}
    for eff, thr in (("lhand", 0.45), ("rhand", 0.45), ("lankle", 0.45), ("rankle", 0.45)):
        r = reach_curve(c, fps, eff, "pelvis", fwd)
        pk = find_peaks(r, fps, thr, 0.3, 0.18)
        ev[eff] = [(int(p), round(float(r[p]), 2)) for p in pk]
    out["peaks"] = ev
    return out


if __name__ == "__main__":
    pats = sys.argv[1:] or [os.path.join(M, "raw", "cmu", "*", "*.amc"), os.path.join(M, "raw", "accad", "*", "*.bvh")]
    files = []
    for p in pats:
        files += sorted(glob.glob(p))
    res = []
    for f in files:
        try:
            s = survey(f)
        except Exception as e:  # noqa: BLE001
            print("FAIL", f, e)
            continue
        res.append(s)
        pk = " ".join(f"{k[0]}{k[1:2]}{k[-4:] if 'ankle' in k else ''}:" + ",".join(f"{p}" for p, _ in v) for k, v in s["peaks"].items() if v)
        print(f"{os.path.basename(f):38s} {s['frames']:5d}f {s['fps']:5.0f} {s['dur']:6.1f}s pel {s['pelvis_min']:.2f}-{s['pelvis_max']:.2f} trav {s['travel']:.1f} | {pk[:150]}")
    out = os.path.join(M, "work", "survey.json")
    old = json.load(open(out)) if os.path.exists(out) else []
    known = {r["file"]: r for r in old}
    for r in res:
        known[r["file"]] = r
    json.dump(list(known.values()), open(out, "w"), indent=0)
