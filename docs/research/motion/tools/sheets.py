"""Stick-figure contact sheets for catalog entries (side + front view, 8 frames per clip).

    python sheets.py --label punch-jab              -> sheets/punch-jab.png (all entries with that label, best first)
    python sheets.py --all [--max 6]                -> one sheet per label
    python sheets.py --ids a,b,c --out name.png     -> custom sheet

Views are in the clip's TARGET frame (catalog targetDirXZ): side view = forward to the right, front view = looking at
the actor from the opponent (actor's left on the right). Blue = left limbs, red = right limbs. Star = contactFrame.
"""
import argparse
import json
import os
import sys

import numpy as np
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import warnings  # noqa: E402

warnings.filterwarnings("ignore", category=UserWarning)

sys.path.insert(0, os.path.dirname(__file__))
from mocap import load_motion, CANON, CANON_BONES  # noqa: E402

M = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CI = {n: i for i, n in enumerate(CANON)}
_cache = {}


def get_motion(entry):
    key = (entry["localFile"], entry["fps"])
    if key not in _cache:
        mo = load_motion(os.path.join(M, entry["localFile"]), fps=entry["fps"])
        _cache[key] = mo.canon()
    return _cache[key]


def target_frame(c, entry):
    t = entry.get("targetDirXZ") or [0.0, 1.0]
    fwd = np.array([t[0], 0.0, t[1]])
    fwd /= np.linalg.norm(fwd) + 1e-9
    left = np.cross([0.0, 1.0, 0.0], fwd)
    a = entry["start"]
    origin = c[a, CI["pelvis"]].copy()
    seg = c[entry["start"]: entry["end"] + 1]
    floor = float(np.percentile(np.minimum(seg[:, CI["ltoe"], 1], seg[:, CI["rtoe"], 1]), 1))
    rel = c - origin
    return np.stack([rel @ left, c[..., 1] - floor, rel @ fwd], -1)  # x=left, y=up, z=forward


def pick_frames(entry, n=8):
    a, b = entry["start"], entry["end"]
    fr = list(np.linspace(a, b, n).round().astype(int))
    cf = entry.get("contactFrame")
    if cf is not None and a <= cf <= b and cf not in fr:
        k = int(np.argmin([abs(f - cf) for f in fr[1:-1]])) + 1
        fr[k] = cf
    return sorted(set(fr))


def color(bone):
    a, b = bone
    if a.startswith("l") and a not in ("lclav",) or b.startswith("l"):
        return "#1f5fd6" if (a + b).count("l") and not (a.startswith("r") or b.startswith("r")) else "#c62828"
    if a.startswith("r") or b.startswith("r"):
        return "#c62828"
    return "#222222"


def bone_color(a, b):
    side = None
    for n in (a, b):
        if n[0] == "l" and n not in ("lclav",) or n in ("lclav",):
            side = "l"
        if n[0] == "r" and n not in ():
            side = "r"
    if b.startswith("l"):
        return "#1f5fd6"
    if b.startswith("r"):
        return "#c62828"
    return "#222222"


def draw(ax, P, view, eff=None):
    hi, vi = (2, 1) if view == "side" else (0, 1)
    for a, b in CANON_BONES:
        pa, pb = P[CI[a]], P[CI[b]]
        ax.plot([pa[hi], pb[hi]], [pa[vi], pb[vi]], color=bone_color(a, b), lw=1.6, solid_capstyle="round")
    head = P[CI["headtop"]]
    ax.plot([head[hi]], [head[vi]], "o", color="#222", ms=3)
    if eff is not None:
        e = P[CI[eff]]
        ax.plot([e[hi]], [e[vi]], "*", color="#ff9800", ms=11, mec="k", mew=0.5)


def effector_for(entry):
    lab = entry["label"]
    lead = entry.get("lead")
    if not lead:
        return None
    s = lead[0]
    if lab.startswith(("punch", "guard", "boxing")):
        return s + "hand"
    if lab.startswith("knee"):
        return s + "knee"
    if lab.startswith("kick") or lab.startswith("sweep"):
        return s + "ankle"
    return None


def render(entries, out, title):
    n = len(entries)
    cols = 8
    fig, axes = plt.subplots(2 * n, cols, figsize=(cols * 1.55, n * 2 * 1.75), squeeze=False)
    for i, e in enumerate(entries):
        c = get_motion(e)
        L = target_frame(c, e)
        frames = pick_frames(e, cols)
        seg = L[e["start"]: e["end"] + 1]
        zmin, zmax = seg[..., 2].min() - 0.15, seg[..., 2].max() + 0.15
        xmin, xmax = seg[..., 0].min() - 0.15, seg[..., 0].max() + 0.15
        ymax = max(1.9, seg[..., 1].max() + 0.1)
        eff = effector_for(e)
        for j in range(cols):
            for r, view in enumerate(("side", "front")):
                ax = axes[2 * i + r][j]
                ax.set_xticks([])
                ax.set_yticks([])
                if j >= len(frames):
                    ax.axis("off")
                    continue
                f = frames[j]
                is_c = e.get("contactFrame") == f
                draw(ax, L[f], view, eff if is_c else None)
                ax.axhline(0, color="#999", lw=0.8)
                if view == "side":
                    ax.set_xlim(zmin, zmax)
                    ax.axvline(0, color="#ddd", lw=0.6, zorder=0)
                else:
                    ax.set_xlim(xmin, xmax)
                ax.set_ylim(-0.05, ymax)
                ax.set_aspect("equal", adjustable="box")
                ax.set_title(f"{'C ' if is_c else ''}{f}", fontsize=7, color="#d84315" if is_c else "#333", pad=1)
                for s in ax.spines.values():
                    s.set_linewidth(1.6 if is_c else 0.4)
                    s.set_color("#d84315" if is_c else "#bbb")
        hdr = f"{e['id']}  [{e['label']}]  q{e['quality']}  lead={e.get('lead')}  stance={e.get('stance', '-')}  {e['fps']:.0f}fps  {e['start']}-{e['end']}"
        axes[2 * i][0].annotate(hdr, (0, 1.32), xycoords="axes fraction", fontsize=8, fontweight="bold", annotation_clip=False)
        axes[2 * i][0].set_ylabel("side (fwd>)", fontsize=6)
        axes[2 * i + 1][0].set_ylabel("front", fontsize=6)
    fig.suptitle(title + "   (blue=left, red=right, star=contact; side view: opponent to the right)", fontsize=10)
    fig.tight_layout(rect=[0, 0, 1, 0.985], h_pad=1.6)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    fig.savefig(out, dpi=80)
    plt.close(fig)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--label")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--ids")
    ap.add_argument("--out")
    ap.add_argument("--max", type=int, default=6)
    ap.add_argument("--catalog", default=os.path.join(M, "catalog.json"))
    a = ap.parse_args()
    cat = json.load(open(a.catalog))
    byid = {e["id"]: e for e in cat}
    jobs = []
    if a.ids:
        ids = a.ids.split(",")
        jobs.append((a.out or os.path.join(M, "sheets", "custom.png"), [byid[i] for i in ids], "custom"))
    labels = []
    if a.label:
        labels = a.label.split(",")
    elif a.all:
        labels = sorted({e["label"] for e in cat})
    for lab in labels:
        es = [e for e in cat if e["label"] == lab]
        es.sort(key=lambda e: (-e["quality"], e["id"]))
        es = es[: a.max]
        jobs.append((os.path.join(M, "sheets", f"{lab}.png"), es, lab))
    for out, es, title in jobs:
        if not es:
            continue
        render(es, out, title)
        print("wrote", os.path.relpath(out, M), len(es), "clips")


if __name__ == "__main__":
    main()

