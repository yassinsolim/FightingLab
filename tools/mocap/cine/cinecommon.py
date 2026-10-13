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


def sternum(dy=0.0, dz=0.0, dx=0.0):
    return chest(dx, dy, dz)


def solar(dz=0.0):
    return chest(0.0, -0.09, dz)


def ribs(side: int, dy=0.0):
    """Side of the rib cage (a body hook); side +1 = the owner's right."""
    return (("waist", "neck", 0.28), (0.15 * side, dy, 0.10), "chest", _rt("UpperTorso", 0.8 * side, -0.5 + dy / 0.18, -1.1))


def liver(side: int = 1):
    """Low on the side, above the hip (a lead hook to the body lands on the defender's right: side +1)."""
    return (("pelvis", "waist", 0.92), (0.12 * side, 0.04, 0.125), "pelvis", _rt("LowerTorso", 0.75 * side, 0.85, -1.2))


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


def reach_dz(ref, limb: str, target, d_track, frame: float, margin: float = 0.02, clear: float = 0.04, arm_tol: float = -0.03, dx: float = 0.0, joint: str | None = None) -> float:
    """How far (m, along the attacker's +z) to move the attacker pose `ref` so that its striking `limb` reaches the
    target point (a grip spec on the defender) at sim `frame`, stopping `margin` short (the runtime strike grip then
    lands it on the real body). Set twobody.DIST first."""
    base = T.base_pose(ref) if not isinstance(ref, T.Pose) else ref
    if dx:
        base = shifted(base, [dx, 0.0, 0.0])
    J = T.full_joints(base)
    pd, _ = d_track.sample(frame)
    JD = T.full_joints(pd)
    tgt = T.to_other(T.point(JD, target[:3]))
    dz = float(tgt[2] - (J[joint] if joint else tip_of(J, limb))[2] - margin)
    # Never closer than the bodies allow: back the step-in off until the torsos and heads clear by `clear`.
    JDa = T.joints_to_other(JD)
    for _ in range(80):
        JA = T.full_joints(shifted(base, [0, 0, dz]))
        if body_gap(JA, JDa) >= clear and arm_gap(JA, JDa, limb) >= arm_tol:
            break
        dz -= 0.01
    return dz


def arm_gap(JA: dict, JD_in_A: dict, limb: str) -> float:
    """Smallest distance (m) between the striking limb's upper segment (upper arm / thigh) and forearm / shin and the
    other body's core; the striking hand / foot itself is excluded (it lands on the target)."""
    s = T.SIDE[limb]
    names = ("upperArm" + s, "foreArm" + s) if limb in T.HANDS else ("thigh" + s, "shin" + s)
    best = 9.0
    for na, a0, a1, ra in T.capsules(JA):
        if na not in names:
            continue
        if na.startswith(("foreArm", "shin")):
            a1 = a0 + (a1 - a0) * 0.5   # the half next to the fist / foot may touch the target
        for nd, d0, d1, rd in T.capsules(JD_in_A):
            if nd.startswith(CORE_CAPS):
                best = min(best, T.seg_dist(a0, a1, d0, d1) - ra - rd)
    return best


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

# ---- spec building blocks (all six Ultimate specs) ----------------------------------------------------------------

def pk(f, pose, ease=None, lift=None, **kw):
    """Key at sim frame f from a whole pose (a Pose or a ref); kw: relative edits (rot_plus -> 'rot+', waist_plus,
    neck_plus, pelvis_plus), limb dicts, contact / ground; lift = (lead foot, rear foot) step arcs (m)."""
    d = {"from": pose if isinstance(pose, T.Pose) else pose_at(pose)}
    if ease:
        d["ease"] = ease
    for k, v in kw.items():
        d[k.replace("_plus", "+")] = v
    if lift:
        for limb, h in (("LeftFoot", lift[0]), ("RightFoot", lift[1])):
            if h:
                d.setdefault(limb, {})["lift"] = h
    return F(f, **d)


def strike_beat(dtrack, f_imp: int, clip: str, limb: str, target, stance: T.Pose, start_off: int = 14,
                windup_off: int = 7, recover_off: int = 8, guard_after: int = 10, extra: dict | None = None,
                margin: float = 0.02, clear: float = 0.04, dz_bias: float = 0.0, step: float = 0.04,
                contact_ref: str | None = None, dx: float = 0.0, arm_tol: float = -0.03, joint: str | None = None):
    """One strike of a cinematic from an installed attack clip: a guard key at the beat's spot (lifted steps), the
    clip's start, wind-up, contact (snap, the striking limb gripped onto the target) and recover poses, and a guard
    after it. The whole beat is moved along +z so the limb meets the target (reach_dz). Returns (dz, keys)."""
    e = extra or {}
    cref = contact_ref or at(clip, "contact")
    dz = reach_dz(cref, limb, target, dtrack, f_imp, margin, clear, arm_tol, dx, joint) + dz_bias
    keys = [
        pk(f_imp - start_off - 4, pose_at(stance, dz, dx), lift=(step, step), **e.get("guard", {})),
        pk(f_imp - start_off, pose_at(at(clip, "start"), dz, dx), **e.get("start", {})),
        pk(f_imp - windup_off, pose_at(at(clip, "windup"), dz, dx), **e.get("windup", {})),
        pk(f_imp, pose_at(cref, dz, dx), "snap", **({limb: dict({"grip": target, "w": 1.0}, **e.get("limb", {}))} if not joint else {}), **e.get("contact", {})),
        pk(f_imp + recover_off, pose_at(at(clip, "recover"), dz, dx), **e.get("recover", {})),
    ]
    if guard_after:
        keys.append(pk(f_imp + recover_off + guard_after, pose_at(at(clip, "end"), dz, dx), **e.get("after", {})))
    return dz, keys


class Hits:
    """Collects the per-impact data of a spec: impact frames, hits (VFX limb/height), strike checks and runtime grips."""

    def __init__(self):
        self.impacts, self.hits, self.strikes, self.grips = [], [], [], []

    def add(self, f_imp: int, limb: str, height: str, target, grip: bool = True, before: float = 3, after: float = 2):
        self.impacts.append(f_imp)
        self.hits.append({"limb": limb, "height": height})
        if target is not None:
            self.strikes.append({"impact": len(self.hits), "frame": f_imp, "limb": limb, "target": target})
            if grip and limb in T.LIMBS:
                self.grips.append(hit_grip(limb, target, f_imp, before, after))


def yawed(pose: T.Pose, deg: float) -> T.Pose:
    """The whole pose turned `deg` about the vertical through its pelvis (Roblox convention: + = turns left): root
    rotation, limb targets (feet re-planted around the pelvis), poles and foot rotations."""
    p = resolved(pose)
    q = T.eq([0, deg, 0])
    R = T.qm(q)
    piv = T.flip(p.pelvis)

    def rot_pt(v):
        return T.flip(R @ (T.flip(v) - piv) + piv)

    def rot_dir(v):
        return T.flip(R @ T.flip(v))

    p.q["root"] = T.qn(T.qmul(q, p.q["root"]))
    for limb in T.LIMBS:
        e = p.limbs[limb]
        e["at"] = rot_pt(e["at"])
        e["pole"] = T.unit(rot_dir(e["pole"]))
        e["rot"] = T.qn(T.qmul(q, e["rot"]))
        e["shin"] = T.unit(rot_dir(e["shin"]))
    return p


def flight(f0: int, f_land: int, z_from: float, kind: str = "FaceUp", yaw_from: float = 0.0, yaw_end: float | None = None,
           apex: float = 0.9, lift: float = 0.0):
    """Defender keys from a big blow to lying on its spot (z = 0) in the endKind pose, landing exactly on the end pose
    at f_land. FaceUp: rocked off its feet backwards in an arc; FaceDown: turned away from the attacker (yaw_end,
    default 180 deg past yaw_from's side) and pitched face-first away from it. The pitch is applied in the heading frame
    (the head always goes away from the attacker, whatever the spin). Pelvis `apex` m high at the top. Limbs are keyed
    in the body's own frames (hands: chest, feet: pelvis), so they follow every turn."""
    end = end_pose(kind)
    span = max(f_land - f0, 6)

    def limbs(hl, hr, fl, fr):
        return {"LeftHand": {"local": hl, "lw": 1.0}, "RightHand": {"local": hr, "lw": 1.0},
                "LeftFoot": {"local": fl, "lw": 1.0}, "RightFoot": {"local": fr, "lw": 1.0}}

    if kind == "FaceDown":
        y_end = yaw_end if yaw_end is not None else (-180.0 if yaw_from <= 0 else 180.0)
        y1, y2 = yaw_from + (y_end - yaw_from) * 0.45, yaw_from + (y_end - yaw_from) * 0.85
        z1, z2 = z_from * 0.7, z_from * 0.28
        k1 = F(f0 + span * 0.3, **{"pelvis": [0.0, apex + lift, z1], "rot": [0, y1, 0], "rot+": [30, 0, 0], "waist": [-6, 0, 0], "neck": [8, 0, 0],
                                    **limbs([-0.30, 0.28, 0.30], [0.30, 0.30, 0.28], [-0.13, -0.84, -0.12], [0.13, -0.80, -0.06]),
                                    "contact": {"LeftFoot": 0.0, "RightFoot": 0.0}, "ground": 0.0})
        k2 = F(f0 + span * 0.7, ease="in", **{"pelvis": [0.0, 0.5 + lift * 0.5, z2], "rot": [0, y2, 0], "rot+": [68, 0, 0], "waist": [-4, 0, 0], "neck": [16, 0, 0],
                                              **limbs([-0.32, 0.22, 0.44], [0.32, 0.22, 0.44], [-0.14, -0.86, -0.18], [0.14, -0.84, -0.12])})
    else:
        y_end = yaw_end if yaw_end is not None else 0.0
        z1, z2 = z_from * 0.7, z_from * 0.15
        k1 = F(f0 + span * 0.3, **{"pelvis": [0.0, apex + lift, z1], "rot": [0, yaw_from + (y_end - yaw_from) * 0.4, 0], "rot+": [45, 0, 0], "waist": [6, 0, 0], "neck": [-10, 0, 0],
                                    **limbs([-0.56, 0.30, 0.10], [0.58, 0.34, 0.06], [-0.14, -0.74, 0.34], [0.14, -0.70, 0.42]),
                                    "contact": {"LeftFoot": 0.0, "RightFoot": 0.0}, "ground": 0.0})
        k2 = F(f0 + span * 0.7, ease="in", **{"pelvis": [0.0, 0.46 + lift * 0.5, z2], "rot": [0, yaw_from + (y_end - yaw_from) * 0.85, 0], "rot+": [76, 0, 0], "neck": [-22, 0, 0],
                                              **limbs([-0.58, 0.24, -0.04], [0.58, 0.26, -0.06], [-0.16, -0.80, 0.24], [0.16, -0.76, 0.30])})
    k3 = F(f_land, ease="in", **{"from": end, "ground": 1.0})
    return [k1, k2, k3]

def chest_local(pose: T.Pose, limb: str) -> list:
    """A hand's current target expressed in the pose's chest frame (twobody 'local': library axes, from the waist
    joint), so it rides along when the torso bends or turns."""
    J = T.torso_joints(pose)
    Rc = J["_R"]["chest"]
    rel = T.flip(pose.limbs[limb]["at"]) - T.flip(J["waist"])
    return [float(x) for x in T.flip(Rc.T @ rel)]


def guard_local(pose: T.Pose, dy: float = 0.0, dz: float = 0.0) -> dict:
    """Both hands held where they are in the pose's chest frame (a guard that follows the torso)."""
    out = {}
    for limb in T.HANDS:
        loc = chest_local(pose, limb)
        out[limb] = {"local": [loc[0], loc[1] + dy, loc[2] + dz], "lw": 1.0}
    return out

def _mq(q) -> np.ndarray:
    q = np.asarray(q, dtype=float)
    return T.qn(np.array([q[0], -q[1], -q[2], q[3]]))


def mirrored(pose: T.Pose) -> T.Pose:
    """The pose mirrored left <-> right (a southpaw version of an orthodox pose): x negated, limbs swapped, rotations
    reflected across the body's sagittal plane."""
    p = resolved(pose)
    out = p.copy()
    out.pelvis = np.array([-p.pelvis[0], p.pelvis[1], p.pelvis[2]])
    for slot in ("root", "waist", "neck"):
        out.q[slot] = _mq(p.q[slot])
    swap = {"LeftHand": "RightHand", "RightHand": "LeftHand", "LeftFoot": "RightFoot", "RightFoot": "LeftFoot"}
    for limb, other in swap.items():
        e = p.limbs[other]
        n = out.limbs[limb]
        n["at"] = np.array([-e["at"][0], e["at"][1], e["at"][2]])
        n["pole"] = T.unit(np.array([-e["pole"][0], e["pole"][1], e["pole"][2]]))
        n["rot"] = _mq(e["rot"])
        n["shin"] = T.unit(np.array([-e["shin"][0], e["shin"][1], e["shin"][2]]))
        n["grip"], n["w"], n["knee"], n["kw"] = None, 0.0, None, 0.0
        n["local"], n["lw"], n["plocal"] = np.zeros(3), 0.0, None
    out.contact = [p.contact[1], p.contact[0]]
    return out


def lowered(pose: T.Pose, dy: float) -> T.Pose:
    """The pose with the body (not the feet) lowered by dy metres (knees bend)."""
    return shifted(pose, [0.0, -abs(dy), 0.0])

def raised(pose: T.Pose, dy: float, dz: float = 0.0) -> T.Pose:
    """The whole pose (pelvis, hands and feet) moved up by dy (and forward by dz) metres: airborne."""
    p = resolved(pose)
    d = np.array([0.0, dy, dz])
    p.pelvis = p.pelvis + d
    for limb in T.LIMBS:
        p.limbs[limb]["at"] = p.limbs[limb]["at"] + d
    return p


def ankle(side: int, off=(0, 0, 0)):
    """The outside of an ankle (sweeps); side +1 = the owner's right."""
    s = "R" if side > 0 else "L"
    return (("knee" + s, "ankle" + s, 0.85), (0.04 * side + off[0], off[1], off[2]), "pelvis", _rt(_side(side) + "LowerLeg", 0.9 * side, -0.8, 0.0))


def floating(f, h: float, z: float, pitch: float = 80.0, yaw: float = 0.0, roll: float = 0.0, ease=None, legs: float = 0.0):
    """A defender key floating in the air on its back (pitched `pitch` deg back in the heading frame: head away from the
    attacker), pelvis `h` m high at `z`; arms loose, legs a little bent (`legs` bends them more)."""
    # pitched first, then turned about the vertical (heading frame): `yaw` turns the horizontal body across the line
    d = {"pelvis": [0.0, h, z], "rot": [pitch, 0, roll], "rot+": [0, yaw, 0], "waist": [6, 0, 0], "neck": [-14, 0, 0],
         "LeftHand": {"local": [-0.46, 0.28, 0.12], "lw": 1.0}, "RightHand": {"local": [0.48, 0.30, 0.10], "lw": 1.0},
         "LeftFoot": {"local": [-0.14, -0.78 + legs, 0.22 + legs * 0.6], "lw": 1.0}, "RightFoot": {"local": [0.15, -0.74 + legs, 0.30 + legs * 0.6], "lw": 1.0},
         "contact": {"LeftFoot": 0.0, "RightFoot": 0.0}, "ground": 0.0}
    if ease:
        d["ease"] = ease
    return F(f, **d)

def rotated(pose: T.Pose, deg, about=None) -> T.Pose:
    """The whole pose turned by the Euler rotation `deg` [x, y, z] (degrees, heading frame; x+ = tips back, y+ = turns
    left, z+ = tips left) about its pelvis (or the point `about`, own-LS metres): root rotation, limb targets, poles,
    foot rotations. Flips, cartwheels and spins keep the limbs with the body."""
    p = resolved(pose)
    q = T.eq(list(deg))
    R = T.qm(q)
    piv = T.flip(p.pelvis if about is None else np.asarray(about, float))

    def rot_pt(v):
        return T.flip(R @ (T.flip(v) - piv) + piv)

    def rot_dir(v):
        return T.flip(R @ T.flip(v))

    p.pelvis = rot_pt(p.pelvis)
    p.q["root"] = T.qn(T.qmul(q, p.q["root"]))
    for limb in T.LIMBS:
        e = p.limbs[limb]
        e["at"] = rot_pt(e["at"])
        e["pole"] = T.unit(rot_dir(e["pole"]))
        e["rot"] = T.qn(T.qmul(q, e["rot"]))
        e["shin"] = T.unit(rot_dir(e["shin"]))
    return p