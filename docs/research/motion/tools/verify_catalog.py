"""Verify catalog.json: every catalogued file parses, canonical joints resolve, ranges are valid.

    python verify_catalog.py            -> prints summary, writes ../verify-report.txt (exit 1 on any error)
"""
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from mocap import load_motion, CANON  # noqa: E402

M = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REQ = ["id", "source", "license", "credit", "url", "localFile", "format", "fps", "skeleton", "start", "end", "label",
       "contactFrame", "lead", "quality", "notes"]


def main():
    cat = json.load(open(os.path.join(M, "catalog.json")))
    errors, lines = [], []
    files = {}
    ids = set()
    for e in cat:
        for k in REQ:
            if k not in e:
                errors.append(f"{e.get('id')}: missing field {k}")
        if e["id"] in ids:
            errors.append(f"{e['id']}: duplicate id")
        ids.add(e["id"])
        files.setdefault((e["localFile"], e["fps"]), []).append(e)
    hi = CANON.index("headtop")
    lt, rt = CANON.index("ltoe"), CANON.index("rtoe")
    for (lf, fps), es in sorted(files.items()):
        path = os.path.join(M, lf)
        if not os.path.exists(path):
            errors.append(f"{lf}: file missing")
            continue
        try:
            mo = load_motion(path, fps=fps)
            c = mo.canon()
        except Exception as ex:  # noqa: BLE001
            errors.append(f"{lf}: parse failed: {ex}")
            continue
        n = mo.n_frames
        if not np.isfinite(c).all():
            errors.append(f"{lf}: non-finite positions")
        floor = np.percentile(np.minimum(c[:, lt, 1], c[:, rt, 1]), 2)
        height = float(np.percentile(c[:, hi, 1] - floor, 95))
        warn = "" if 1.2 < height < 2.2 else "  WARN height"
        lines.append(f"OK {lf}: {n} frames @ {mo.fps:g} fps, {len(mo.names)} joints, standing height {height:.2f} m, "
                     f"{len(es)} entries{warn}")
        for e in es:
            a, b, cf = e["start"], e["end"], e["contactFrame"]
            if not (0 <= a <= b < n):
                errors.append(f"{e['id']}: bad range {a}-{b} (n={n})")
            if cf is not None and not (a <= cf <= b):
                errors.append(f"{e['id']}: contactFrame {cf} outside {a}-{b}")
            if e["lead"] not in (None, "left", "right"):
                errors.append(f"{e['id']}: bad lead {e['lead']}")
            if not (1 <= int(e["quality"]) <= 5):
                errors.append(f"{e['id']}: bad quality")
    summary = f"[VERIFY] {len(cat)} entries, {len(files)} files parsed, {len(errors)} errors"
    out = [summary] + [f"ERROR {x}" for x in errors] + lines
    open(os.path.join(M, "verify-report.txt"), "w", encoding="utf-8").write("\n".join(out) + "\n")
    print(summary)
    for x in errors[:30]:
        print("ERROR", x)
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
