"""Shared authoring helpers for the Ultimate cinematic specs (library space, metres, see twobody; started from the
motionthrows throw helpers)."""
from __future__ import annotations

import numpy as np

import twobody as T

LEG = T.LEG


def F(f: float, **kw) -> dict:
    """Key at sim frame f (keyword names that are not identifiers use kw dicts: F(3, **{'rot+': [..]}))."""
    kw["f"] = f
    return kw


def K(f: float, d: dict) -> dict:
    d = dict(d)
    d["f"] = f
    return d


def stance(style: str) -> T.Pose:
    return T.base_pose("style:" + style)


DEFENDER_STYLE = "kickboxer"   # generic defender stance (orthodox, bladed 20 deg, mid-high guard)


def defender_stance() -> T.Pose:
    return T.base_pose("style:" + DEFENDER_STYLE)


def fallback_contact() -> T.Pose:
    return T.base_pose("FallBack@0.3667")


# ---- grip points on the OTHER body (owner's local frame: +x = owner's right, +z = owner's front) -----------------
# Each helper returns (anchor, offset, frame, runtime) where `runtime` is the matching FLThrow1 grip target on the
# owner's real R15 body (motioncore grips: part + point in the part box, -1..1 of the half size, x right, y up,
# z BACK; left/right are the owner's own). Half sizes used for the conversion (reference body, metres):
# Head 0.10/0.12/0.11, UpperTorso 0.19/0.18/0.11, LowerTorso 0.17/0.10/0.11, UpperLeg depth 0.08.

def _cl(v: float) -> float:
    return float(max(-3.0, min(3.0, v)))


def _rt(part: str, x: float, y: float, z: float) -> dict:
    return {"part": part, "at": (round(_cl(x), 3), round(_cl(y), 3), round(_cl(z), 3))}


def _side(side: int) -> str:
    return "Right" if side > 0 else "Left"


def nape(dx=0.0, dy=0.0, dz=0.0):
    return (("neck", "head", 0.35), (dx, dy, -0.075 + dz), "chest", _rt("Head", dx / 0.10, -0.75 + dy / 0.12, 1.0 - dz / 0.11))


def neck_side(side: int, dy=0.0, dz=0.0):
    """side +1 = owner's right."""
    return (("neck", "head", 0.3), (0.085 * side, dy, dz), "chest", _rt("Head", 0.95 * side, -0.9 + dy / 0.12, -dz / 0.11))


def collar(side: int, dy=0.0, dz=0.0, frac=0.5):
    """Top of the trapezius / collarbone between neck and shoulder; side +1 = owner's right."""
    return (("neck", "shoulderR" if side > 0 else "shoulderL", frac), (0, 0.06 + dy, 0.03 + dz), "chest",
            _rt("UpperTorso", 0.9 * frac * side, 0.95 + dy / 0.18, -0.4 - dz / 0.11))


def shoulder_top(side: int, dy=0.0, dz=0.0, dx=0.0):
    return ("shoulderR" if side > 0 else "shoulderL", (dx, 0.07 + dy, dz), "chest", {"anchor": _side(side) + "Shoulder"})


def chest(dx=0.0, dy=0.0, dz=0.0):
    return (("waist", "neck", 0.62), (dx, dy, 0.13 + dz), "chest", _rt("UpperTorso", dx / 0.19, 0.1 + dy / 0.18, -1.2 - dz / 0.11))


def belly(dx=0.0, dy=0.0, dz=0.0):
    return (("pelvis", "waist", 0.9), (dx, dy, 0.135 + dz), "pelvis", _rt("LowerTorso", dx / 0.17, 0.5 + dy / 0.10, -1.2 - dz / 0.11))


def back(dx=0.0, dy=0.0, dz=0.0, frac=0.55):
    """Middle/upper back surface."""
    return (("waist", "neck", frac), (dx, dy, -0.13 + dz), "chest", _rt("UpperTorso", dx / 0.19, 2 * frac - 1 + dy / 0.18, 1.2 - dz / 0.11))


def lower_back(dx=0.0, dy=0.0, dz=0.0):
    return (("pelvis", "waist", 0.8), (dx, dy, -0.125 + dz), "pelvis", _rt("LowerTorso", dx / 0.17, 0.5 + dy / 0.10, 1.2 - dz / 0.11))


def waist_side(side: int, dy=0.0, dz=0.0):
    return (("pelvis", "waist", 0.8), (0.15 * side, dy, dz), "pelvis", _rt("LowerTorso", 1.1 * side, 0.6 + dy / 0.10, -dz / 0.11))


def belt(dx=0.0, dy=0.0, dz=0.0):
    return ("pelvis", (dx, 0.08 + dy, 0.13 + dz), "pelvis", _rt("LowerTorso", dx / 0.17, 0.3 + dy / 0.10, -1.2 - dz / 0.11))


def armpit(side: int, dy=0.0, dz=0.0):
    return ("shoulderR" if side > 0 else "shoulderL", (0.03 * side, -0.11 + dy, -0.02 + dz), "chest",
            _rt("UpperTorso", 1.0 * side, 0.3 + dy / 0.18, -dz / 0.11))


def upper_arm(side: int, frac=0.5, off=(0, 0, 0)):
    s = "R" if side > 0 else "L"
    return (("shoulder" + s, "elbow" + s, frac), off, "world", _rt(_side(side) + "UpperArm", 0.0, 1 - 2 * frac, 0.0))


def wrist(side: int, frac=0.82, off=(0, 0, 0)):
    s = "R" if side > 0 else "L"
    return (("elbow" + s, "hand" + s, frac), off, "world", _rt(_side(side) + "LowerArm", 0.0, 1 - 2 * frac, 0.0))


def thigh(side: int, frac=0.5, off=(0, 0, 0.08)):
    s = "R" if side > 0 else "L"
    return (("hip" + s, "knee" + s, frac), off, "pelvis",
            _rt(_side(side) + "UpperLeg", off[0] / 0.08, 1 - 2 * frac, -1.1 - (off[2] - 0.08) / 0.08))


def knee_back(side: int, off=(0, 0, -0.06)):
    s = "R" if side > 0 else "L"
    return ("knee" + s, off, "pelvis", _rt(_side(side) + "LowerLeg", 0.0, 0.9, 1.0))


def head_point(off=(0, 0, 0)):
    return (("head", "headTop", 0.4), off, "head", _rt("Head", 0.0, 0.0, 0.0))


# Runtime targets of raw grip specs that name a joint of the other body directly (e.g. a hand held in a hand).
RAW_GRIP_TARGETS = {"handL": _rt("LeftHand", 0, 0, 0), "handR": _rt("RightHand", 0, 0, 0)}


def runtime_grip(spec) -> dict | None:
    """FLThrow1 grip target for a grip spec (None = not representable: the authored limb path is kept)."""
    if spec is None:
        return None
    if len(spec) > 3 and isinstance(spec[3], dict):
        return spec[3]
    if isinstance(spec[0], str):
        return RAW_GRIP_TARGETS.get(spec[0])
    return None


# ---- measurement helpers (used while authoring) -------------------------------------------------------------------

def sample_joints(track: T.Track, f: float) -> dict:
    p, _ = track.sample(f)
    return T.full_joints(p)


def other_point(track: T.Track, f: float, spec) -> np.ndarray:
    """A point of `track`'s body (spec as for grips) expressed in the OTHER body's LS."""
    return T.to_other(T.point(sample_joints(track, f), spec))


# ---- whole-pose helpers ------------------------------------------------------------------------------------------

END_BACK = [-0.1446]   # attacker's final root offset (m): bakes CombatSim.endThrow's 0.45-stud push (-0.155 L, motioncore OK'd)
D_END_BACK = -0.1446   # defender: FallBack@contact shifted 0.45 studs back (away from the attacker) for the same reason
BREAK_BACK = -0.193    # broken throws: each fighter is pushed 0.6 studs apart after the 16 break frames (-0.207 L)


def fallback_end() -> T.Pose:
    """The defender's last throw frame: FallBack@contact (Landing continues from it) at the post-throw root."""
    return shifted(fallback_contact(), [0, 0, D_END_BACK])


def shifted(pose: T.Pose, d) -> T.Pose:
    """The pose moved by d (m). A vertical component lowers/raises the body only: the feet keep their height (a
    crouch, not feet sunk into the floor)."""
    p = pose.copy()
    d = np.asarray(d, dtype=float)
    p.pelvis = p.pelvis + d
    for limb in T.LIMBS:
        p.limbs[limb]["at"] = p.limbs[limb]["at"] + (d * np.array([1.0, 0.0, 1.0]) if limb in T.FEET else d)
        p.limbs[limb]["grip"] = None
        p.limbs[limb]["w"] = 0.0
        p.limbs[limb]["knee"] = None
        p.limbs[limb]["kw"] = 0.0
    return p


def end_stance(style: str) -> T.Pose:
    return shifted(stance(style), [0, 0, END_BACK[0]])


# Lead (left) foot offset (m, attacker library axes) on the attacker's last throw frame: the long karate and kickboxing
# stances would put the lead shin into the lying defender's raised FallBack foot, so that foot ends stepped clear
# (outward and back). The other stances already clear it. Idle's crossfade takes the foot back to the stance spot.
END_CLEAR = {"karate": (-0.14, -0.12), "kickboxer": (-0.06, -0.09)}


def end_lead(style: str, extra=(0.0, 0.0)) -> list:
    dx, dz = END_CLEAR.get(style, (0.0, 0.0))
    return [dx + extra[0], 0.0, dz + extra[1]]


def resolved(pose: T.Pose) -> T.Pose:
    """A solved pose as a plain key base (grips/knees already baked into the limb targets)."""
    return shifted(pose, [0, 0, 0])


def make_grab(PA0: T.Pose, style: str, lean=(-3, 6, 0), whiff=None, startup: int = 11, recovery: int = 34,
              notes: str = "") -> dict:
    """Grab attempt FLClip1 keys (sim frames): stance -> anticipation -> the throw's first attacker pose exactly on the
    first active frame -> whiff (hands close on air, weight tips forward) -> back to the fighter's stance.
    startup = the SIM startup (Roster: data "startup" is the genre impact frame, sim startup = impact - 1), so the
    contact key lands on the roster's first active frame startup + 1."""
    first = startup + 1
    total = startup + 2 + recovery
    contact = resolved(PA0)
    w = whiff or {}
    keys = [
        {"f": 0, "from": "style:" + style},
        {"f": round(first * 0.45), "pelvis+": [0.0, -0.02, 0.03], "rot+": list(lean),
         "LeftHand": {"at+": [0.0, -0.04, 0.05]}, "RightHand": {"at+": [0.0, -0.04, 0.05]}},
        {"f": first, "from": contact, "ease": "snap"},
        {"f": first + 6, "pelvis+": w.get("pelvis+", [0.0, -0.015, 0.03]), "rot+": w.get("rot+", [-4, 0, 0]),
         "LeftHand": {"at+": w.get("L", [0.05, -0.04, 0.03])}, "RightHand": {"at+": w.get("R", [-0.05, -0.04, 0.03])}},
        {"f": first + int(recovery * 0.55), "from": shifted(stance(style), [0, 0, 0.06])},
        {"f": total, "from": "style:" + style},
    ]
    return {"timing": (startup, 2, recovery), "duration": total / 60.0, "contact": first, "recover": first + 2, "keys": keys,
            "notes": notes}


def generic_break(PA0: T.Pose, PD0: T.Pose, style: str, a_hands=((-0.14, 0.14, -0.12), (0.14, 0.14, -0.12)),
                  d_push=((0.02, 0.20, 0.10), (-0.02, 0.20, 0.10))) -> tuple[list, list]:
    """Throw break (16 sim frames): the defender drives both hands up between the attacker's arms and shoves, the
    grip is knocked loose, both rock back and settle into their stances."""
    a0, d0 = resolved(PA0), resolved(PD0)
    A = [
        {"f": 0, "from": a0},
        {"f": 4, "ease": "snap", "rot+": [7, 0, 0], "waist+": [4, 0, 0],
         "LeftHand": {"at+": list(a_hands[0]), "pole": [-0.6, -0.8, 0.0]}, "RightHand": {"at+": list(a_hands[1]), "pole": [0.6, -0.8, 0.0]}},
        {"f": 9, "pelvis+": [0.0, 0.0, -0.05], "rot+": [3, 0, 0]},
        {"f": 16, "from": shifted(stance(style), [0, 0, BREAK_BACK])},
    ]
    D = [
        {"f": 0, "from": d0},
        {"f": 4, "ease": "snap", "rot+": [8, 0, 0], "waist+": [5, 0, 0],
         "LeftHand": {"at+": list(d_push[0]), "pole": [-0.6, -0.8, 0.0]}, "RightHand": {"at+": list(d_push[1]), "pole": [0.6, -0.8, 0.0]}},
        {"f": 9, "pelvis+": [0.0, 0.0, -0.05], "rot+": [2, 0, 0]},
        {"f": 16, "from": shifted(defender_stance(), [0, 0, BREAK_BACK])},
    ]
    return A, D


# ---- Ultimate cinematics (round 6) -------------------------------------------------------------------------------

import keyed  # noqa: E402

_CLIP_CACHE: dict = {}
# Installed clips a spec sampled (credits: the builder lists their sources).
USED: set = set()


def note(ref) -> None:
    if isinstance(ref, str):
        if ref.startswith("Displayed:"):
            USED.add(T.stance_clip_name(T.FIGHTER_STYLE.get(ref[10:].partition("@")[0], "boxer")))
        elif ref.startswith("style:"):
            USED.add(T.stance_clip_name(ref[6:]))
        else:
            USED.add(ref.partition("@")[0])


def clip_info(name: str):
    """(channels, raw, duration s, contact s, recover s) of an installed clip module (Core or Moves, any folder)."""
    hit = _CLIP_CACHE.get(name)
    if hit:
        return hit
    ch, raw = keyed.load_core_clip(name, [T.CORE_DIR])
    fps = float(raw["fps"])
    n = ch.shape[1]
    dur = n / fps if raw.get("loop") else (n - 1) / fps
    c = raw.get("contact")
    if c is None and raw.get("contactFrame") is not None:
        c = float(raw["contactFrame"]) / max(n - 1, 1)
    r = raw.get("recover")
    if c is not None and r is None:
        r = c + (1 - c) / 3
    out = (ch, raw, dur, (c if c is not None else 0.5) * dur, (r if r is not None else 0.66) * dur)
    _CLIP_CACHE[name] = out
    return out


def at(name: str, phase) -> str:
    """'Clip@seconds' at a named phase of an installed clip: 'start', 'windup' (half way to the contact), 'load' (80 %
    of the way), 'contact', 'follow' (a third of the way to the recover pose), 'recover', 'end'; or a fraction (float)
    of the clip, or ('s', seconds)."""
    _, _, dur, c, r = clip_info(name)
    USED.add(name)
    if isinstance(phase, tuple):
        t = float(phase[1])
    elif isinstance(phase, str):
        t = {"start": 0.0, "windup": c * 0.5, "load": c * 0.8, "contact": c, "follow": c + (r - c) / 3, "recover": r, "end": dur}[phase]
    else:
        t = float(phase) * dur
    return f"{name}@{t:.4f}"


def prone_away_contact() -> T.Pose:
    """FallFrontAir at its floor contact: face down, head AWAY from the attacker (Landing continues it, then the
    ProneTurnOver and the face-up getups; motioncore 14)."""
    _, _, dur, c, _ = clip_info("FallFrontAir")
    USED.add("FallFrontAir")
    return T.base_pose(f"FallFrontAir@{c:.4f}")


def end_pose(kind: str) -> T.Pose:
    """The defender's last cinematic frame for the roster's endKind: the knockdown continues from it on the sim spot."""
    if kind != "FaceDown":
        USED.add("FallBack")
    return prone_away_contact() if kind == "FaceDown" else fallback_contact()


def stance_of(fighter: str) -> T.Pose:
    note("Displayed:" + fighter)
    return T.base_pose("Displayed:" + fighter)


# Strike targets on the OTHER body (grip specs as above: authoring anchor + the runtime R15 part point). Head half
# sizes 0.10/0.12/0.11, UpperTorso 0.19/0.18/0.11, LowerTorso 0.17/0.10/0.11 (reference body, metres).

def face(dy=0.0, dz=0.0):
    """Front of the face (nose line), just outside the surface."""
    return (("head", "headTop", 0.4), (0.0, dy, 0.115 + dz), "head", _rt("Head", 0.0, dy / 0.12, -1.15 - dz / 0.11))


def chin(dz=0.0):
    return (("head", "headTop", 0.4), (0.0, -0.075, 0.095 + dz), "head", _rt("Head", 0.0, -0.7, -0.95 - dz / 0.11))


def jaw(side: int, dz=0.0):
    """Side of the jaw; side +1 = the owner's right."""
    return (("head", "headTop", 0.4), (0.085 * side, -0.05, 0.05 + dz), "head", _rt("Head", 1.0 * side, -0.55, -0.55 - dz / 0.11))


def temple(side: int, dy=0.0):
    return (("head", "headTop", 0.4), (0.108 * side, 0.02 + dy, 0.0), "head", _rt("Head", 1.12 * side, 0.15 + dy / 0.12, -0.1))


def sternum(dy=0.0, dz=0.0):
    return chest(0.0, dy, dz)


def solar(dz=0.0):
    return chest(0.0, -0.09, dz)


def ribs(side: int, dy=0.0):
    """Side of the rib cage (a body hook); side +1 = the owner's right."""
    return (("waist", "neck", 0.3), (0.21 * side, dy, 0.03), "chest", _rt("UpperTorso", 1.1 * side, -0.45 + dy / 0.18, -0.3))


def liver(side: int = 1):
    """Low on the side, above the hip (a lead hook to the body lands on the defender's right: side +1)."""
    return (("pelvis", "waist", 0.95), (0.20 * side, 0.02, 0.03), "pelvis", _rt("LowerTorso", 1.15 * side, 0.75, -0.3))


def hit_grip(limb: str, target, f_impact: float, before: float = 3, after: float = 2) -> dict:
    """A runtime strike-contact window (FLThrow1 grip, Attacker role) around an impact: the striking hand/foot lands on
    the defender's real body point whatever the two fighters' sizes (seconds of track time = sim frames / 60)."""
    rt_target = target[3]
    g = {"role": "Attacker", "limb": limb, "from": round(max(0.0, (f_impact - before) / 60.0), 4), "to": round((f_impact + after) / 60.0, 4), "fade": 0.04}
    g.update({k: (list(v) if isinstance(v, tuple) else v) for k, v in rt_target.items()})
    return g

def pose_at(ref, dz: float = 0.0, dx: float = 0.0) -> T.Pose:
    """An installed clip's pose (or a Pose) moved whole (pelvis, hands, feet) by dz forward / dx right (metres)."""
    note(ref)
    base = ref if isinstance(ref, T.Pose) else T.base_pose(ref)
    return shifted(base, [dx, 0.0, dz]) if (dz or dx) else resolved(base)


def tip_of(J: dict, limb: str) -> np.ndarray:
    s = T.SIDE[limb]
    return J["hand" + s] if limb in T.HANDS else J["ankle" + s]


def reach_dz(ref, limb: str, target, d_track, frame: float, margin: float = 0.02, clear: float = 0.04) -> float:
    """How far (m, along the attacker's +z) to move the attacker pose `ref` so that its striking `limb` reaches the
    target point (a grip spec on the defender) at sim `frame`, stopping `margin` short (the runtime strike grip then
    lands it on the real body). Set twobody.DIST first."""
    base = T.base_pose(ref) if not isinstance(ref, T.Pose) else ref
    J = T.full_joints(base)
    pd, _ = d_track.sample(frame)
    JD = T.full_joints(pd)
    tgt = T.to_other(T.point(JD, target[:3]))
    dz = float(tgt[2] - tip_of(J, limb)[2] - margin)
    # Never closer than the bodies allow: back the step-in off until the torsos and heads clear by `clear`.
    JDa = T.joints_to_other(JD)
    for _ in range(80):
        if body_gap(T.full_joints(shifted(base, [0, 0, dz])), JDa) >= clear:
            break
        dz -= 0.01
    return dz


CORE_CAPS = ("spineLow", "spineHigh", "shoulders", "hips", "head", "neck")


def body_gap(JA: dict, JD_in_A: dict) -> float:
    """Smallest surface distance (m) between the two bodies' cores (torso, hips, shoulders, neck, head); negative =
    overlapping."""
    best = 9.0
    for na, a0, a1, ra in T.capsules(JA):
        if not na.startswith(CORE_CAPS):
            continue
        for nd, d0, d1, rd in T.capsules(JD_in_A):
            if not nd.startswith(CORE_CAPS):
                continue
            best = min(best, T.seg_dist(a0, a1, d0, d1) - ra - rd)
    return best