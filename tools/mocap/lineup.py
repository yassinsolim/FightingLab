"""Offline fighter lineup (no Studio): every fighter's stance/walk/backwalk/crouch as the runtime would pose it.

  python lineup.py [--clips <dir with Core clip modules>] [--states <Motion.States.luau>] [--out <dir>] [--t 0.4]

Emulates ClipPlayer.sample + Motion.States.styleAdjust (per-style yaw, guard arms in the chest frame, stance width /
length / drop / sway) on the clip channels, then reconstructs the body on the reference skeleton (like clipsheet.py).
Style numbers are read from Motion.States.luau (States.STYLES), so this always matches the runtime source.
"""
from __future__ import annotations

import argparse
import glob
import math
import os
import re
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import clipio  # noqa: E402
import clipsheet  # noqa: E402
import render  # noqa: E402
import retarget as rt  # noqa: E402

OV6 = os.path.abspath(os.path.join(HERE, "..", ".."))
WORK_SRC = os.path.join(OV6, "work", "motioncore", "src")
FIGHTERS = [("Kael", "boxer"), ("Sierra", "kickboxer"), ("Goran", "grappler"), ("Lumi", "flow"), ("Rhys", "karate"), ("Nia", "kungfu")]
STYLE_NAMES = {"boxer": "Boxer", "kickboxer": "Kickboxer", "grappler": "Grappler", "flow": "Flow", "karate": "Karate", "kungfu": "KungFu"}
NUM = r"(-?\d+(?:\.\d+)?)"


def parse_styles(path: str) -> dict:
    text = open(path, encoding="utf-8").read()
    block = text[text.index("States.STYLES = {"):]
    block = block[:block.index("\n}\n")]
    styles = {}
    for m in re.finditer(r"^\s*(\w+) = \{(.*)\},?\s*$", block, re.M):
        name, body = m.group(1), m.group(2)
        st = {}
        for key in ("rate", "drop", "width", "length", "w", "sway", "swayHz", "circle", "yaw", "pitch"):
            mm = re.search(r"\b" + key + r" = " + NUM, body)
            st[key] = float(mm.group(1)) if mm else 0.0
        for key in ("lead", "rear"):
            mm = re.search(r"\b" + key + r" = arm\(" + ",\\s*".join([NUM] * 6) + r"\)", body)
            vals = [float(mm.group(i)) for i in range(1, 7)]
            pole = np.array(vals[3:6]); pole /= max(np.linalg.norm(pole), 1e-9)
            st[key] = (np.array(vals[0:3]), pole)
        styles[name] = st
    m = re.search(r"States.WIDTH_SPREAD = " + NUM, text)
    for st in styles.values():
        st["spread"] = float(m.group(1)) if m else 0.05
    return styles


def load_clip(name: str, clip_dir: str):
    hits = glob.glob(os.path.join(clip_dir, f"ReplicatedStorage.FightingLab.Client.Motion.Clips.Core.{name}.luau"))
    if not hits:
        return None
    raw = clipio.parse_lua_table(open(hits[0], encoding="utf-8").read())
    return clipio.clip_channels(raw), raw


def find_clip(base: str, style: str | None, clip_dir: str):
    if style:
        c = load_clip(f"{base}_{STYLE_NAMES[style]}", clip_dir)
        if c:
            return c, f"{base}_{STYLE_NAMES[style]}"
    return load_clip(base, clip_dir), base


def ry(a: float) -> np.ndarray:
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def rx(a: float) -> np.ndarray:
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def qmat(q: np.ndarray) -> np.ndarray:
    return rt.quat_to_mat(q[None])[0]


def mq(R: np.ndarray) -> np.ndarray:
    return rt.mat_to_quat(R[None])[0]


def style_frame(v: np.ndarray, st: dict, w: float, now: float, feet: str | None, ref: np.ndarray | None = None) -> np.ndarray:
    """Exact port of Motion.States.styleAdjust on one channel frame (clip/Roblox axes, limb-length units).
    ref: the clip's static channel frame (loop mean / first frame) for travelling clips (walks, dashes, sidesteps):
    the yaw then turns the feet's static placement only, never their stride (runtime `travel = true`)."""
    v = v.copy()
    # rotateYaw (CFrame.Angles(0, yaw, 0)) of the whole pose about the vertical axis through the fighter.
    r = ry(math.radians(st["yaw"]))
    v[0:3] = r @ v[0:3]
    v[3:7] = mq(r @ qmat(v[3:7]))
    for base in (15, 25, 35, 45):
        if ref is not None and base in (35, 45) and st["yaw"] != 0:
            v[base:base + 3] = r @ ref[base:base + 3] + (v[base:base + 3] - ref[base:base + 3])
        else:
            v[base:base + 3] = r @ v[base:base + 3]
        v[base + 3:base + 6] = r @ v[base + 3:base + 6]
        v[base + 6:base + 10] = mq(r @ qmat(v[base + 6:base + 10]))
    if st.get("pitch"):
        # Optional torso pitch correction (positive = lean back), applied to the pelvis about its own centre.
        v[3:7] = mq(qmat(v[3:7]) @ rx(math.radians(st["pitch"])))
    chest = qmat(v[3:7]) @ qmat(v[7:11])
    for base, key in ((15, "lead"), (25, "rear")):
        rel, pole = st[key]
        rel = rel.copy()
        if key == "lead" and st["circle"] > 0:
            ph = now * math.pi * 2 * 0.35
            rel += np.array([math.cos(ph) * st["circle"], math.sin(ph) * st["circle"] * 0.7, 0])
        want = chest @ rel
        v[base:base + 3] = v[base:base + 3] * (1 - w) + want * w
        v[base + 3:base + 6] = v[base + 3:base + 6] * (1 - w) + (chest @ pole) * w
    if feet:
        stance = feet == "stance"
        walk = feet == "walk"
        root0 = v[0:3].copy()
        sway = math.sin(now * math.pi * 2 * st["swayHz"]) * st["sway"] if stance and st["sway"] > 0 else 0.0
        drop = 0.0 if feet == "crouch" else st["drop"] * (0.4 if walk else 1.0)
        width = 1 + (st["width"] - 1) * 0.5 if walk else st["width"]
        root1 = root0 + np.array([sway, -drop, 0])
        for base, side in ((35, -1), (45, 1)):
            world = root0 + v[base:base + 3]
            world = np.array([world[0] * width + side * (width - 1) * st.get("spread", 0.05), world[1],
                              world[2] * (st["length"] if stance else 1.0)])
            v[base:base + 3] = world - root1
        v[0:3] = root1
    return v


def render_row(body, frames: list[np.ndarray], labels: list[str], view: str, size: int) -> list[Image.Image]:
    return [clipsheet.panel(body, [(f, 0.0)], view, lab, False, size) for f, lab in zip(frames, labels)]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--clips", default=WORK_SRC)
    ap.add_argument("--states", default=os.path.join(WORK_SRC, "ReplicatedStorage.FightingLab.Client.Motion.States.luau"))
    ap.add_argument("--out", default=os.path.join(OV6, "work", "motioncore", "lineup"))
    ap.add_argument("--t", type=float, default=0.4)
    ap.add_argument("--size", type=int, default=230)
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    styles = parse_styles(args.states)
    body = clipsheet.reference_body()
    plan = [("stance", "Stance", "stance", True), ("walk", "WalkFwd", "walk", False), ("backwalk", "WalkBack", "walk", False),
            ("crouch", "Crouch", "crouch", True)]
    for label, base, feet, styled in plan:
        rows = []
        for view in ("side", "threequarter"):
            frames, labels = [], []
            for fighter, style in FIGHTERS:
                st = styles[style]
                (clip, name) = find_clip(base, style if styled else None, args.clips)
                if clip is None:
                    continue
                ch, raw = clip
                fps, loop = float(raw["fps"]), bool(raw.get("loop"))
                t = args.t * (st["rate"] if label == "stance" and st["rate"] > 0 else 1.0)
                frame = clipsheet.sample_channels(ch, fps, loop, t)
                ref = (ch.mean(axis=1) if loop else ch[:, 0]) if feet == "walk" else None
                frames.append(style_frame(frame, st, st["w"], args.t, feet, ref))
                labels.append(f"{fighter} ({name})")
            rows.append(render_row(body, frames, labels, view, args.size))
        out = os.path.join(args.out, f"lineup-{label}.png")
        render.sheet(rows, out, f"{label}: six fighters as posed by the runtime style layer (t={args.t:.2f}s)")
        print(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
