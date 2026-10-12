"""Re-time the fast segments of built clips so no frame jumps (MotionQA round 4).

Hand-keyed throws (and a few keyed moves) cover a body throw or a snap in two or three frames next to frames that
barely move, and some hold a duplicated frame in the middle of a fast arc (a one-frame stall then a jump): played at
60 fps that reads as a teleport. This tool re-times such a clip in place: inside each segment between fixed anchor
frames (start, contact/impact, recover, end — so contact and impact frames stay exact) every frame-to-frame step gets
an output duration proportional to how far the body travels in it (at most LIMIT studs per frame, stalls inside a fast
arc squeezed out), normalised so the segment keeps its frame count. Slow holds play a little faster, snaps a little
slower. The poses themselves are unchanged (resampled from the clip: positions linear, rotations normalised lerp).

FLThrow1: attacker and defender share one time warp (they stay in sync); grip windows are remapped through it; the
break tracks are left alone. FLClip1: one track, anchors at contact and recover.

    python tools/mocap/retime.py --src src --clips Goran_Throw,Kael_ThrowB            (report only)
    python tools/mocap/retime.py --src src --clips Goran_Throw --write                (rewrite the modules)
    python tools/mocap/retime.py --src src --all-throws --write

Only the layout/data strings of the warped tracks (and the grip from/to times) change in the module text.
"""
from __future__ import annotations

import argparse
import glob
import os
import re
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import clipio  # noqa: E402

LEG = 3.0       # studs per leg length (root motion scale, typical rig)
ARM = 2.0       # studs per arm reach
BODY_R = 1.2    # studs: tangential speed of the head/shoulders per radian of root rotation
LIMIT = 0.40    # studs per frame: target ceiling of the fastest body point
QUATS = (3, 7, 11, 21, 31, 41, 51)  # 0-based first channel of each quaternion
LIMB_BASES = (15, 25, 35, 45)       # 0-based first channel of each limb (pos, pole, rot)


def quat_angle(q0: np.ndarray, q1: np.ndarray) -> np.ndarray:
    d = np.abs(np.sum(q0 * q1, axis=0) / (np.linalg.norm(q0, axis=0) * np.linalg.norm(q1, axis=0) + 1e-9))
    return 2 * np.arccos(np.clip(d, 0, 1))


def activity(ch: np.ndarray) -> np.ndarray:
    """Studs travelled by the fastest body point per frame step (approximation from the channels), shape (N-1,)."""
    root = np.linalg.norm(np.diff(ch[0:3], axis=1), axis=0) * LEG
    rot = quat_angle(ch[3:7, :-1], ch[3:7, 1:]) * BODY_R
    waist = quat_angle(ch[7:11, :-1], ch[7:11, 1:]) * BODY_R * 0.6
    limbs = []
    for k, b in enumerate(LIMB_BASES):
        scale = ARM if k < 2 else LEG
        limbs.append(np.linalg.norm(np.diff(ch[b:b + 3], axis=1), axis=0) * scale * 0.7)
    return np.max(np.stack([root, rot, waist] + limbs), axis=0)


def warp_segment(a: np.ndarray, limit: float) -> np.ndarray:
    """Output durations (frames) of the steps of one segment; sums to len(a)."""
    n = len(a)
    if n == 0:
        return a.copy()
    w = np.maximum(1.0, a / limit)
    fast = a > limit
    # A stall (or near-stall) inside a fast arc is a duplicated key: squeeze it out.
    for i in range(n):
        left = fast[max(0, i - 2):i].any()
        right = fast[i + 1:i + 3].any()
        if left and right and a[i] < limit * 0.5:
            w[i] = max(a[i] / limit, 0.15)
    # Gentle ramps into and out of the slowed part.
    if n >= 3:
        k = np.array([0.25, 0.5, 0.25])
        padded = np.concatenate([[w[0]], w, [w[-1]]])
        blurred = np.convolve(padded, k, mode="valid")
        w = np.where(fast, w, np.maximum(blurred, np.minimum(w, 1.0)))
    return w * (n / w.sum())


def sample(ch: np.ndarray, s: np.ndarray) -> np.ndarray:
    n = ch.shape[1]
    s = np.clip(s, 0, n - 1)
    i0 = np.floor(s).astype(int)
    i1 = np.minimum(i0 + 1, n - 1)
    t = s - i0
    out = ch[:, i0] * (1 - t) + ch[:, i1] * t
    for q in QUATS:
        q0, q1 = ch[q:q + 4, i0], ch[q:q + 4, i1].copy()
        flip = np.sum(q0 * q1, axis=0) < 0
        q1[:, flip] = -q1[:, flip]
        v = q0 * (1 - t) + q1 * t
        out[q:q + 4] = v / (np.linalg.norm(v, axis=0) + 1e-12)
    return out


def build_warp(acts: list[np.ndarray], anchors: list[int], limit: float) -> np.ndarray:
    """Source frame position of every output frame (monotone; anchors map to themselves)."""
    a = np.max(np.stack(acts), axis=0)
    n = len(a) + 1
    out_time = np.zeros(n)
    for s0, s1 in zip(anchors[:-1], anchors[1:]):
        d = warp_segment(a[s0:s1], limit)
        out_time[s0 + 1:s1 + 1] = out_time[s0] + np.cumsum(d)
    # Invert: output frame j -> source position.
    return np.interp(np.arange(n), out_time, np.arange(n))


def remap_time(t_sec: float, src_pos: np.ndarray, fps: float) -> float:
    """Source time -> output time through the warp (src_pos[j] = source frame of output frame j)."""
    f = t_sec * fps
    j = np.interp(f, src_pos, np.arange(len(src_pos)))
    return float(j / fps)


def module_name(path: str) -> str:
    return os.path.basename(path).split(".")[-2]


def find_modules(src: str, names: list[str] | None, all_throws: bool) -> list[str]:
    files = glob.glob(os.path.join(src, "ReplicatedStorage.FightingLab.Client.Motion.Clips.*.luau"))
    out = []
    for f in sorted(files):
        n = module_name(f)
        if names and n in names:
            out.append(f)
        elif all_throws and ".Throws." in f and not n.endswith("_Grab"):
            out.append(f)
    return out


def replace_track(text: str, old: dict, new_ch: np.ndarray) -> str:
    layout, data, clipped = clipio.encode(new_ch)
    if clipped:
        raise ValueError("re-timed channels out of range")
    i = text.index(f'data = "{old["data"]}"')
    j = text.rindex('layout = "', 0, i)
    k = text.index('"', j + len('layout = "'))
    text = text[:j] + f'layout = "{layout}"' + text[k + 1:]
    i = text.index(f'data = "{old["data"]}"')
    return text[:i] + f'data = "{data}"' + text[i + len(f'data = "{old["data"]}"'):]


def process(path: str, limit: float, write: bool) -> str:
    text = open(path, encoding="utf-8").read()
    raw = clipio.parse_lua_table(text)
    name = module_name(path)
    if raw.get("format") == "FLThrow1":
        A, D = clipio.clip_channels(raw["attacker"]), clipio.clip_channels(raw["defender"])
        n = A.shape[1]
        fps = float(raw["attacker"]["fps"])
        impact = int(round(float(raw["impact"]) * (n - 1)))
        anchors = sorted({0, impact, n - 1})
        before = max(activity(A).max(), activity(D).max())
        src_pos = build_warp([activity(A), activity(D)], anchors, limit)
        A2, D2 = sample(A, src_pos), sample(D, src_pos)
        after = max(activity(A2).max(), activity(D2).max())
        new = replace_track(replace_track(text, raw["attacker"], A2), raw["defender"], D2)

        def grip(m: re.Match) -> str:
            f0, f1 = float(m.group(1)), float(m.group(2))
            return f"from = {remap_time(f0, src_pos, fps):.4f}, to = {remap_time(f1, src_pos, fps):.4f}"
        new = re.sub(r"from = ([0-9.]+), to = ([0-9.]+)", grip, new)
        tracks = ((raw["attacker"], A2), (raw["defender"], D2))
    else:
        C = clipio.clip_channels(raw)
        n = C.shape[1]
        contact = raw.get("contact")
        recover = raw.get("recover")
        anchors = {0, n - 1}
        for v in (contact, recover):
            if v is not None:
                anchors.add(int(round(float(v) * (n - 1))))
        anchors = sorted(anchors)
        before = activity(C).max()
        src_pos = build_warp([activity(C)], anchors, limit)
        C2 = sample(C, src_pos)
        after = activity(C2).max()
        new = replace_track(text, raw, C2)
        tracks = ((raw, C2),)
    # Anchors land exactly on source frames: their poses are unchanged.
    for _old, ch in tracks:
        assert ch.shape[1] == n
    moved = float(np.max(np.abs(src_pos - np.arange(len(src_pos)))))
    note = f"-- Re-timed by tools/mocap/retime.py (fastest step <= ~{limit:.2f} studs/frame; start, contact/impact, recover and end frames unchanged)."
    if moved > 1e-6 and note not in new:
        new = re.sub(r"-- Re-timed by tools/mocap/retime\.py[^\n]*\n", "", new)
        r = new.index("return {")
        new = new[:r] + note + "\n" + new[r:]
    if write and new != text:
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(new)
    return f"{name}: fastest step {before:.2f} -> {after:.2f} studs/frame (limit {limit:.2f}), max shift {moved:.2f} frames, anchors {anchors}"


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--src", default="src")
    ap.add_argument("--clips", default="")
    ap.add_argument("--all-throws", action="store_true")
    ap.add_argument("--limit", type=float, default=LIMIT)
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args()
    names = [c.strip() for c in args.clips.split(",") if c.strip()] or None
    files = find_modules(args.src, names, args.all_throws)
    if not files:
        sys.exit("no matching clip modules")
    for f in files:
        print(process(f, args.limit, args.write))


if __name__ == "__main__":
    main()
