"""Hand-keyed poses -> FLClip1 / FLThrow1 clip modules.

For moves without licence-clean mocap (throws, overhands, low kicks, sweeps, elbows, palms) and for touching up
reactions. The output is the same clip format as convert.py, so it plays through the same runtime path (contact warp,
contact aim, foot locking, mirroring, two-role throws) and the same offline check (clipsheet.py).

Usage:
  python keyed.py --spec <keyed.json> --out <dir> [--only Name1,Name2] [--clips <dir with Core clip modules>]

Spec (JSON):
{
  "folder": "Moves.Throws",                     # Motion.Clips.<folder>
  "license": "Original hand-keyed animation (FightingLab); no third-party data",   # optional
  "clips": [
    { "name": "Goran_Elbow", "fighter": "Goran", "move": "Elbow", "sources": ["original:motionstrikes"],
      "fps": 30, "contact": 0.30, "recover": 0.50,  # seconds of clip time (contact lands on the first active frame)
      "mirror": false, "loop": false, "tags": { "limb": "RightHand" },
      "keys": [ { "t": 0.0, "from": "Stance" }, { "t": 0.3, "rootRot": [0, -25, 0], "RightHand": { "pos": [0.1, 0.0, 0.9] } } ] },
    { "format": "FLThrow1", "name": "Goran_Suplex", "fighter": "Goran", "move": "Suplex", "sources": ["original:motionthrows"],
      "impact": 1.10, "distance": 0.55,         # impact: seconds (lands on throw.impactFrame); distance: leg lengths
      "attacker": { "keys": [ ... ] }, "defender": { "keys": [ ... ] },
      "breakAttacker": { "keys": [ ... ] }, "breakDefender": { "keys": [ ... ] },   # optional: played when broken
      "grips": [ { "role": "Attacker", "limb": "LeftHand", "anchor": "Collar", "from": 0.20, "to": 0.90 } ] }
      # optional grips: at runtime the limb is held on the partner's REAL body point (any fighter sizes), see clipio
  ]
}

Key fields. Axes are LIBRARY axes: +X = the fighter's right, +Y = up, +Z = toward the opponent. Every field is
optional; a missing field carries over from the previous key (the first key starts from "from", default "Stance").
  t          seconds
  from       "Stance" | "<Core clip name>" | "<Core clip name>@<seconds>": take every channel from a frame of an
             installed clip module (e.g. "FallBack@1.2"); later fields of the same key override it.
             "Displayed:<Fighter>[@<seconds>]" (e.g. "Displayed:Goran") = that fighter's idle stance exactly as the
             runtime shows it (style stance clip + per-style yaw, guard arms, stance width/length/drop) - start and end
             attack clips on it so the blend in/out of the idle does not twist the body
  root       [x, y, z] pelvis offset in leg lengths; y = 0 is the straight-legged standing height (stance ~ -0.08,
             deep crouch ~ -0.45, lying ~ -0.95). Moving the pelvis keeps the feet planted where they stand (set
             "feetFollowRoot": true on the key to carry the feet along, e.g. for a hop)
  rootRot    [x, y, z] degrees, Euler XYZ in Roblox character space: x+ leans back, y+ turns left, z+ leans left
  waist      [x, y, z] degrees, chest relative to the pelvis (same convention)
  neck       [x, y, z] degrees, head relative to the chest
  LeftHand / RightHand   { "pos": [x, y, z] shoulder->hand in arm lengths (|pos| = 1 is a straight arm),
                           "pole": [x, y, z] direction the elbow points (normalised) }
  LeftFoot / RightFoot   { "pos": [x, y, z] hip->sole in leg lengths (y = -1 under a straight leg),
                           "pole": [x, y, z] direction the knee points, "rot": [x, y, z] foot rotation, degrees }
  contact    { "LeftFoot": 0..1, "RightFoot": 0..1 } planted feet (runtime foot lock). Default: automatic from the
             sole height (on the floor = planted)
  ground     0..1 body supported by the floor (lying). Default: automatic from the pelvis height
  ease       curve of the segment ENDING at this key: "smooth" (default), "linear", "in", "out", "snap" (fast in,
             for impacts), "hold" (keeps the previous key until this time, then jumps)
"""
from __future__ import annotations

import argparse
import glob
import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import clipio  # noqa: E402
import retarget as rt  # noqa: E402

OV6 = os.path.abspath(os.path.join(HERE, "..", ".."))
CLIP_DIRS = [os.path.join(OV6, "handoff", "motioncore-src"), os.path.join(OV6, "work", "motioncore", "src")]
LIMBS = ("LeftHand", "RightHand", "LeftFoot", "RightFoot")
LIMB_BASE = {"LeftHand": 15, "RightHand": 25, "LeftFoot": 35, "RightFoot": 45}  # 0-based channel index
DEFAULT_LICENSE = "Original hand-keyed animation (FightingLab); no third-party data"
EASES = ("smooth", "linear", "in", "out", "snap", "hold")


def euler_to_quat(deg) -> np.ndarray:
    x, y, z = (math.radians(float(v)) for v in deg)
    cx, sx, cy, sy, cz, sz = math.cos(x), math.sin(x), math.cos(y), math.sin(y), math.cos(z), math.sin(z)
    rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    return rt.mat_to_quat((rx @ ry @ rz)[None])[0]  # Roblox CFrame.Angles(x, y, z) = Rx * Ry * Rz


def lib_to_clip(v) -> np.ndarray:
    v = np.asarray(v, dtype=float)
    return np.array([v[0], v[1], -v[2]])


def ease(kind: str, u: float) -> float:
    u = min(max(u, 0.0), 1.0)
    if kind == "linear":
        return u
    if kind == "in":
        return u * u
    if kind == "out":
        return 1 - (1 - u) * (1 - u)
    if kind == "snap":
        return 1 - (1 - u) ** 3
    if kind == "hold":
        return 1.0 if u >= 1.0 else 0.0
    return u * u * (3 - 2 * u)


def slerp(a: np.ndarray, b: np.ndarray, t: float) -> np.ndarray:
    if float(np.dot(a, b)) < 0:
        b = -b
    return rt.quat_slerp(a, b, t)


_module_cache: dict = {}


def load_core_clip(name: str, clip_dirs: list[str]) -> tuple[np.ndarray, dict]:
    if name in _module_cache:
        return _module_cache[name]
    for d in clip_dirs:
        hits = glob.glob(os.path.join(d, f"ReplicatedStorage.FightingLab.Client.Motion.Clips.*.{name}.luau"))
        if hits:
            raw = clipio.parse_lua_table(open(hits[0], encoding="utf-8").read())
            ch = clipio.clip_channels(raw)
            _module_cache[name] = (ch, raw)
            return ch, raw
    raise FileNotFoundError(f"clip module {name} not found in {clip_dirs}")


FIGHTER_STYLE = {"kael": "boxer", "sierra": "kickboxer", "goran": "grappler", "lumi": "flow", "rhys": "karate", "nia": "kungfu"}


def displayed_frame(fighter: str, at: float, clip_dirs: list[str]) -> np.ndarray:
    """The fighter's idle stance exactly as the runtime shows it: the style's stance clip + Motion.States.styleAdjust
    (yaw, guard arms, stance width/length/drop), read from the installed Motion.States.luau."""
    import clipsheet
    import lineup
    style = FIGHTER_STYLE.get(fighter.lower())
    if style is None:
        raise ValueError(f"Displayed:{fighter}: unknown fighter (use one of {sorted(FIGHTER_STYLE)})")
    states = next((p for d in clip_dirs for p in [os.path.join(d, "ReplicatedStorage.FightingLab.Client.Motion.States.luau")]
                   if os.path.exists(p)), None)
    if states is None:
        raise FileNotFoundError(f"Motion.States.luau not found in {clip_dirs}")
    st = lineup.parse_styles(states)[style]
    try:
        ch, raw = load_core_clip(f"Stance_{lineup.STYLE_NAMES[style]}", clip_dirs)
    except FileNotFoundError:
        ch, raw = load_core_clip("Stance", clip_dirs)
    t = at * (st["rate"] if st["rate"] > 0 else 1.0)
    frame = clipsheet.sample_channels(ch, float(raw["fps"]), bool(raw.get("loop")), t)
    out = lineup.style_frame(frame, st, st["w"], at, "stance")
    for q in (3, 7, 11, 21, 31, 41, 51):
        out[q:q + 4] /= max(np.linalg.norm(out[q:q + 4]), 1e-9)
    return out


def frame_from(ref: str, clip_dirs: list[str]) -> np.ndarray:
    name, _, at = ref.partition("@")
    if name.startswith("Displayed:"):
        return displayed_frame(name[len("Displayed:"):], float(at or 0), clip_dirs)
    ch, raw = load_core_clip(name, clip_dirs)
    fps, n = float(raw["fps"]), ch.shape[1]
    f = min(max(float(at or 0) * fps, 0), n - 1)
    i0 = int(math.floor(f)); i1 = min(i0 + 1, n - 1); a = f - i0
    out = ch[:, i0] * (1 - a) + ch[:, i1] * a
    for q in (3, 7, 11, 21, 31, 41, 51):
        out[q:q + 4] /= max(np.linalg.norm(out[q:q + 4]), 1e-9)
    return out


def key_frame(prev: np.ndarray | None, key: dict, clip_dirs: list[str]) -> tuple[np.ndarray, dict]:
    """Full 58-channel frame for a key (carry-over from prev) and which auto channels were given explicitly."""
    if "from" in key or prev is None:
        v = frame_from(key.get("from", "Stance"), clip_dirs)
    else:
        v = prev.copy()
    explicit = {"contactL": "from" in key, "contactR": "from" in key, "ground": "from" in key}
    root_before = v[0:3].copy()
    if "root" in key:
        v[0:3] = lib_to_clip(key["root"])
    if "root+" in key:
        v[0:3] += lib_to_clip(key["root+"])
    if key.get("feetFollowRoot") is not True:
        # Moving the pelvis keeps the feet where they stand (foot targets are hip-relative): an animator lowers the
        # hips into a crouch or shifts the weight without the soles sliding or sinking. Explicit LeftFoot/RightFoot
        # fields below still move the feet.
        moved = v[0:3] - root_before
        v[35:38] -= moved
        v[45:48] -= moved
    for field, base in (("rootRot", 3), ("waist", 7), ("neck", 11)):
        if field in key:
            v[base:base + 4] = euler_to_quat(key[field])
        if field + "+" in key:
            # Relative turn, applied in the parent's frame on top of the carried rotation.
            v[base:base + 4] = rt.quat_mul(euler_to_quat(key[field + "+"]), v[base:base + 4])
            v[base:base + 4] /= max(np.linalg.norm(v[base:base + 4]), 1e-9)
    for limb in LIMBS:
        b = LIMB_BASE[limb]
        e = key.get(limb)
        if e:
            if "pos" in e:
                v[b:b + 3] = lib_to_clip(e["pos"])
            if "pole" in e:
                p = lib_to_clip(e["pole"])
                v[b + 3:b + 6] = p / max(np.linalg.norm(p), 1e-9)
            if "rot" in e:
                v[b + 6:b + 10] = euler_to_quat(e["rot"])
        d = key.get(limb + "+")
        if d:
            if "pos" in d:
                v[b:b + 3] += lib_to_clip(d["pos"])
            if "pole" in d:
                p = v[b + 3:b + 6] + lib_to_clip(d["pole"])
                v[b + 3:b + 6] = p / max(np.linalg.norm(p), 1e-9)
            if "rot" in d:
                v[b + 6:b + 10] = rt.quat_mul(euler_to_quat(d["rot"]), v[b + 6:b + 10])
    c = key.get("contact") or {}
    if "LeftFoot" in c:
        v[55] = float(c["LeftFoot"]); explicit["contactL"] = True
    if "RightFoot" in c:
        v[56] = float(c["RightFoot"]); explicit["contactR"] = True
    if "ground" in key:
        v[57] = float(key["ground"]); explicit["ground"] = True
    return v, explicit


def build_track(track: dict, clip_dirs: list[str], fps: float, duration: float | None = None, loop: bool = False) -> np.ndarray:
    keys = sorted(track["keys"], key=lambda k: float(k["t"]))
    if not keys:
        raise ValueError("track has no keys")
    frames, flags = [], []
    prev = None
    for k in keys:
        prev, ex = key_frame(prev, k, clip_dirs)
        frames.append(prev)
        flags.append(ex)
    times = [float(k["t"]) for k in keys]
    T = max(times[-1], duration or 0.0)
    n = max(int(round(T * fps)) + 1, 2)
    if loop:
        # A loop's last key is its first frame again: drop the duplicate (ClipPlayer wraps frames/fps).
        n = max(n - 1, 2)
    out = np.zeros((58, n))
    for i in range(n):
        t = i / fps
        j = 0
        while j + 1 < len(times) and times[j + 1] < t:
            j += 1
        if t <= times[0] or j + 1 >= len(times):
            out[:, i] = frames[0] if t <= times[0] else frames[-1]
            continue
        a, b = frames[j], frames[j + 1]
        u = ease(keys[j + 1].get("ease", "smooth"), (t - times[j]) / max(times[j + 1] - times[j], 1e-9))
        v = a * (1 - u) + b * u
        for q in (3, 7, 11, 21, 31, 41, 51):
            v[q:q + 4] = slerp(a[q:q + 4], b[q:q + 4], u)
        for limb in LIMBS:
            p = LIMB_BASE[limb] + 3
            v[p:p + 3] /= max(np.linalg.norm(v[p:p + 3]), 1e-9)
        out[:, i] = v
    # Automatic contacts / ground where no key set them: sole on the floor = planted; pelvis near the floor = lying.
    auto_l = not any(f["contactL"] for f in flags[1:]) and "contact" not in track
    auto_r = not any(f["contactR"] for f in flags[1:]) and "contact" not in track
    for side, base, ch, auto in (("L", 35, 55, auto_l), ("R", 45, 56, auto_r)):
        if auto:
            sole_h = 1.0 + out[1] + out[base + 1]
            out[ch] = np.clip((0.07 - sole_h) / 0.05, 0, 1)
    if not any(f["ground"] for f in flags[1:]):
        out[57] = np.clip((0.32 - (out[1] + 1.1)) / 0.12, 0, 1)
    return out


def track_meta(ch: np.ndarray, fps: float) -> dict:
    return {"fps": fps, "frames": ch.shape[1], "loop": False, "speed": 0.0, "travel": [0.0, 0.0, 0.0]}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--spec", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--only")
    ap.add_argument("--clips", help="directory with the Core clip modules (default: OV6 handoff/motioncore-src, then work src)")
    args = ap.parse_args()
    spec = json.load(open(args.spec, encoding="utf-8-sig"))
    folder = spec.get("folder", "Moves")
    clip_dirs = [args.clips] if args.clips else CLIP_DIRS
    only = set(args.only.split(",")) if args.only else None
    license_text = spec.get("license", DEFAULT_LICENSE)
    os.makedirs(args.out, exist_ok=True)
    total = 0
    for clip in spec["clips"]:
        name = clip["name"]
        if only and name not in only:
            continue
        ids = list(clip.get("sources") or [])
        if not ids:
            raise ValueError(f"{name}: 'sources' is required (use [\"original:<agent>\"] for hand-keyed work)")
        fps = float(clip.get("fps", 30))
        label = f"hand-keyed ({os.path.basename(args.spec)})"
        notes = clip.get("notes", "")
        if clip.get("format") == "FLThrow1":
            att_keys, def_keys = clip["attacker"], clip["defender"]
            T = max(max(float(k["t"]) for k in att_keys["keys"]), max(float(k["t"]) for k in def_keys["keys"]))
            cha = build_track(att_keys, clip_dirs, fps, T)
            chd = build_track(def_keys, clip_dirs, fps, T)
            breaks = []
            for key in ("breakAttacker", "breakDefender"):
                track = clip.get(key)
                breaks.append(build_track(track, clip_dirs, fps) if track else None)
            if clip.get("mirror"):
                cha, chd = rt.mirror_channels(cha), rt.mirror_channels(chd)
                breaks = [rt.mirror_channels(b) if b is not None else None for b in breaks]
            dur = (cha.shape[1] - 1) / fps
            meta = {"fighter": clip.get("fighter"), "move": clip["move"],
                    "impact": min(max(float(clip["impact"]) / max(dur, 1e-9), 0), 1), "distance": float(clip.get("distance", 0.6))}
            if clip.get("grips"):
                meta["grips"] = [clipio.mirror_grip(g) for g in clip["grips"]] if clip.get("mirror") else list(clip["grips"])
            text, clipped = clipio.throw_module(name, (cha, track_meta(cha, fps)), (chd, track_meta(chd, fps)), meta, label, license_text, notes, ids,
                                                *[(b, track_meta(b, fps)) if b is not None else None for b in breaks])
        else:
            loop = bool(clip.get("loop"))
            ch = build_track(clip, clip_dirs, fps, loop=loop)
            if clip.get("mirror"):
                ch = rt.mirror_channels(ch)
            meta = track_meta(ch, fps)
            meta["loop"] = loop
            dur = (ch.shape[1] - 1) / fps
            for key in ("contact", "recover"):
                if clip.get(key) is not None:
                    meta[key] = min(max(float(clip[key]) / max(dur, 1e-9), 0), 1)
            meta["tags"] = clip.get("tags", {})
            for key in ("fighter", "move", "stringIndex"):
                if clip.get(key) is not None:
                    meta[key] = clip[key]
            if clip.get("mirrorAtRuntime"):
                meta["mirrorAtRuntime"] = True
            text, clipped = clipio.luau_module(name, ch, meta, label, license_text, notes, ids)
        text = text.replace("generated by OV6/tools/mocap/convert.py", "generated by OV6/tools/mocap/keyed.py")
        path = os.path.join(args.out, f"ReplicatedStorage.FightingLab.Client.Motion.Clips.{folder}.{name}.luau")
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)
        total += len(text)
        print(f"{name:30s} {len(text) / 1024:6.1f} KB  clipped {clipped}")
    print(f"{total / 1024:.1f} KB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
