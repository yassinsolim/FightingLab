"""Canonical skeleton extraction (source-independent) for retargeting.

Every source (CMU ASF/AMC, ACCAD/MotionBuilder BVH, ...) is reduced to a Canon: joint positions plus anatomical frames
per frame, in ROBLOX CHARACTER SPACE of the capture world (right-handed, +Y up; source +Z maps to Roblox -Z, so the
source's "toward the target" +Z becomes the Roblox LookVector), metres.

Anatomical frames are 3x3 matrices whose columns are a body part's (right, up, back) directions, i.e. the world rotation
of the matching R15 part (LowerTorso/UpperTorso/Head/Foot). They are built from joint POSITIONS (robust for any
skeleton convention); only the head's yaw/roll comes from the source rotation of the head joint.
"""
from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np

import motion as motionmod

# Source -> Roblox character space: a 180-degree turn about Y (X and Z negated).
M_SRC = np.diag([-1.0, 1.0, -1.0])

# Canonical joint -> source joint, or (jointA, jointB, t) = lerp between two joints.
PROFILES: dict[str, dict] = {
    "cmu": {
        "pos": {
            "pelvis": "root", "waist": "lowerback", "chest": "upperback", "neck": "thorax", "head": "upperneck", "headTop": "head",
            "hipL": "lhipjoint", "kneeL": "lfemur", "ankleL": "ltibia", "ballL": "lfoot", "toeL": "ltoes",
            "hipR": "rhipjoint", "kneeR": "rfemur", "ankleR": "rtibia", "ballR": "rfoot", "toeR": "rtoes",
            "shoulderL": "lclavicle", "elbowL": "lhumerus", "wristL": "lradius", "handL": "lwrist",
            "shoulderR": "rclavicle", "elbowR": "rhumerus", "wristR": "rradius", "handR": "rwrist",
        },
        "rot": {"pelvis": "root", "head": "head", "footL": "lfoot", "footR": "rfoot"},
    },
    # MotionBuilder naming (ACCAD Open Motion and many BVH exports).
    "mb": {
        "pos": {
            "pelvis": "Hips", "waist": "Spine", "chest": "Spine1", "neck": "Neck", "head": "Head", "headTop": "Head_End",
            "hipL": "LeftUpLeg", "kneeL": "LeftLeg", "ankleL": "LeftFoot", "ballL": "LeftToeBase", "toeL": "LeftToeBase_End",
            "hipR": "RightUpLeg", "kneeR": "RightLeg", "ankleR": "RightFoot", "ballR": "RightToeBase", "toeR": "RightToeBase_End",
            "shoulderL": "LeftArm", "elbowL": "LeftForeArm", "wristL": "LeftHand", "handL": ("LeftHand", "LeftHand_End", 0.45),
            "shoulderR": "RightArm", "elbowR": "RightForeArm", "wristR": "RightHand", "handR": ("RightHand", "RightHand_End", 0.45),
        },
        "rot": {"pelvis": "Hips", "head": "Head", "footL": "LeftFoot", "footR": "RightFoot"},
    },
    # Unreal-mannequin naming (Quaternius Universal Animation Library, Blender BVH exports).
    "ue": {
        "pos": {
            "pelvis": "pelvis", "waist": "spine_01", "chest": "spine_03", "neck": "neck_01", "head": "Head", "headTop": "Head_End",
            "hipL": "thigh_l", "kneeL": "calf_l", "ankleL": "foot_l", "ballL": "ball_l", "toeL": "ball_leaf_l",
            "hipR": "thigh_r", "kneeR": "calf_r", "ankleR": "foot_r", "ballR": "ball_r", "toeR": "ball_leaf_r",
            "shoulderL": "upperarm_l", "elbowL": "lowerarm_l", "wristL": "hand_l", "handL": ("hand_l", "middle_01_l", 0.6),
            "shoulderR": "upperarm_r", "elbowR": "lowerarm_r", "wristR": "hand_r", "handR": ("hand_r", "middle_01_r", 0.6),
        },
        "rot": {"pelvis": "pelvis", "head": "Head", "footL": "foot_l", "footR": "foot_r"},
    },
}


def detect_profile(m: motionmod.Motion) -> str:
    if m.kind == "cmu":
        return "cmu"
    names = set(m.pos)
    if {"Hips", "LeftUpLeg", "LeftForeArm", "Spine1"} <= names:
        return "mb"
    if {"pelvis", "thigh_l", "calf_l", "upperarm_l", "spine_03"} <= names:
        return "ue"
    raise ValueError("unknown skeleton naming: " + ", ".join(sorted(names)[:30]))


@dataclass
class Canon:
    fps: float
    p: dict[str, np.ndarray]           # joint -> (N,3) positions (Roblox space, metres)
    F: dict[str, np.ndarray]           # frame name -> (N,3,3) anatomical frames (columns right, up, back)
    lengths: dict[str, float]
    meta: dict = field(default_factory=dict)

    @property
    def n(self) -> int:
        return len(self.p["pelvis"])

    def slice(self, a: int, b: int, step: int = 1) -> "Canon":
        return Canon(self.fps / step, {k: v[a:b:step].copy() for k, v in self.p.items()},
                     {k: v[a:b:step].copy() for k, v in self.F.items()}, dict(self.lengths), dict(self.meta))


def unit(v: np.ndarray) -> np.ndarray:
    n = np.linalg.norm(v, axis=-1, keepdims=True)
    return v / np.maximum(n, 1e-9)


def frame_from(right: np.ndarray, up: np.ndarray) -> np.ndarray:
    """Columns (right, up, back) from approximate right/up vectors; up wins, right is orthogonalised."""
    u = unit(up)
    r = unit(right - u * np.sum(right * u, axis=-1, keepdims=True))
    b = np.cross(r, u)
    return np.stack([r, u, b], axis=-1)


def frame_from_forward_up(forward: np.ndarray, up: np.ndarray) -> np.ndarray:
    """Forward wins (feet point where the toes point), up is orthogonalised."""
    f = unit(forward)
    u = unit(up - f * np.sum(up * f, axis=-1, keepdims=True))
    b = -f
    r = np.cross(u, b)
    return np.stack([r, u, b], axis=-1)


def floor_estimate(P: dict[str, np.ndarray]) -> float:
    """Floor height: lowest foot point over the clip (balls/toes), robust to a few outliers."""
    lows = np.concatenate([P[k][:, 1] for k in ("toeL", "toeR", "ballL", "ballR")])
    return float(np.percentile(lows, 1)) - 0.012


def geometric_frames(P: dict[str, np.ndarray]) -> dict[str, np.ndarray]:
    """Frames from joint positions only (columns right, up, back), before calibration."""
    F: dict[str, np.ndarray] = {}
    F["pelvis"] = frame_from(P["hipR"] - P["hipL"], P["waist"] - P["pelvis"])
    F["chest"] = frame_from(P["shoulderR"] - P["shoulderL"], P["neck"] - P["waist"])
    F["head"] = F["chest"]
    for s in ("L", "R"):
        F["foot" + s] = frame_from_forward_up(P["ball" + s] - P["ankle" + s], P["knee" + s] - P["ankle" + s])
    return F


def neutral_like(F: np.ndarray) -> np.ndarray:
    """Same yaw as F, zero pitch and roll (an upright, level part)."""
    r = F[:, 0].copy()
    r[1] = 0
    if np.linalg.norm(r) < 1e-6:
        b = F[:, 2].copy(); b[1] = 0
        r = np.cross(np.array([0.0, 1.0, 0.0]), b)
    r = r / np.linalg.norm(r)
    u = np.array([0.0, 1.0, 0.0])
    b = np.cross(r, u)
    return np.stack([r, u, b], axis=-1)


ROT_PARTS = ("pelvis", "head", "footL", "footR")


def _positions(m: motionmod.Motion, prof: dict, units: float, rest: bool = False, frame: int | None = None) -> dict[str, np.ndarray]:
    P: dict[str, np.ndarray] = {}

    def get(name: str) -> np.ndarray:
        if rest:
            return m.rest[name][None]
        v = m.pos[name]
        return v[frame:frame + 1] if frame is not None else v

    for k, src in prof["pos"].items():
        if isinstance(src, tuple):
            a, b, t = src
            P[k] = get(a) * (1 - t) + get(b) * t
        else:
            P[k] = get(src)
    return {k: (v * units) @ M_SRC.T for k, v in P.items()}


def _rotations(m: motionmod.Motion, prof: dict, rest: bool = False, frame: int | None = None) -> dict[str, np.ndarray]:
    out = {}
    for part in ROT_PARTS:
        name = prof["rot"][part]
        if rest:
            R = np.eye(3)[None]
        else:
            R = m.rot[name] if frame is None else m.rot[name][frame:frame + 1]
        out[part] = M_SRC[None] @ R @ M_SRC.T[None]
    return out


def from_motion(m: motionmod.Motion, scale: float | None = None, calib: tuple[motionmod.Motion, int] | None = None) -> Canon:
    """Anatomical frames: the chest from geometry (shoulder line + waist->neck line); pelvis, head and feet from their
    source joint rotations. All are calibrated against a relaxed upright stand with flat feet (`calib` = (motion, frame)
    of the same actor; default: the CMU rest pose, or this motion's first frame for BVH without a calibration take),
    which absorbs skeleton conventions, the lumbar joint sitting behind the hips and the ankle->ball slope."""
    profile = detect_profile(m)
    prof = PROFILES[profile]
    units = scale if scale is not None else m.units
    P = _positions(m, prof, units)
    R = _rotations(m, prof)
    G = geometric_frames(P)
    if calib is not None:
        cm, cf = calib
        Pc, Rcal = _positions(cm, prof, units, frame=cf), _rotations(cm, prof, frame=cf)
    elif m.kind == "cmu":
        Pc, Rcal = _positions(m, prof, units, rest=True), _rotations(m, prof, rest=True)
    else:
        Pc, Rcal = _positions(m, prof, units, frame=0), _rotations(m, prof, frame=0)
    Gc = {k: v[0] for k, v in geometric_frames(Pc).items()}
    chest_cal = neutral_like(Gc["chest"])
    F: dict[str, np.ndarray] = {}
    F["chest"] = G["chest"] @ (Gc["chest"].T @ chest_cal)[None]
    targets = {"pelvis": neutral_like(Gc["pelvis"]), "head": chest_cal, "footL": neutral_like(Gc["footL"]), "footR": neutral_like(Gc["footR"])}
    for part in ROT_PARTS:
        Q = Rcal[part][0].T @ targets[part]
        F[part] = R[part] @ Q[None]
    floor = floor_estimate(P)
    ankle_h = float(np.percentile(np.minimum(P["ankleL"][:, 1], P["ankleR"][:, 1]) - floor, 3))

    def seg(a: str, b: str) -> float:
        return float(np.median(np.linalg.norm(P[a] - P[b], axis=1)))

    lengths = {
        "thigh": (seg("hipL", "kneeL") + seg("hipR", "kneeR")) / 2,
        "shin": (seg("kneeL", "ankleL") + seg("kneeR", "ankleR")) / 2,
        "upperArm": (seg("shoulderL", "elbowL") + seg("shoulderR", "elbowR")) / 2,
        "foreArm": (seg("elbowL", "wristL") + seg("elbowR", "wristR")) / 2,
        "hand": (seg("wristL", "handL") + seg("wristR", "handR")) / 2,
        "ankleHeight": float(np.clip(ankle_h, 0.04, 0.14)),
        "hipDrop": float(np.median(P["pelvis"][:, 1] - (P["hipL"][:, 1] + P["hipR"][:, 1]) / 2)),
        "floor": floor,
    }
    lengths["leg"] = lengths["thigh"] + lengths["shin"] + lengths["ankleHeight"]
    lengths["arm"] = lengths["upperArm"] + lengths["foreArm"] + lengths["hand"]
    return Canon(m.fps, P, F, lengths, {"profile": profile})


def load(path: str, fps: float | None = None, asf: str | None = None, calib: tuple[str, int] | None = None) -> Canon:
    cal = None
    if calib is not None:
        cpath = calib[0]
        cm = motionmod.load_cmu(asf or "", cpath, fps or 120.0) if cpath.lower().endswith(".amc") else motionmod.load_bvh(cpath)
        cal = (cm, int(calib[1]))
    if path.lower().endswith(".amc"):
        if not asf:
            raise ValueError("CMU AMC needs its ASF")
        return from_motion(motionmod.load_cmu(asf, path, fps or 120.0), calib=cal)
    return from_motion(motionmod.load_bvh(path), calib=cal)


def segments(c: Canon, i: int, xf=None, mirror: bool = False):
    """Stick-figure segments for frame i; xf maps a Roblox-space point to render (library) space. mirror=True draws the
    mirrored body (x negated, left/right colours swapped) to compare with mirrored clips."""
    from render import LEFT, RIGHT, CENTER
    if xf is None:
        xf = lambda v: np.array([v[0], v[1], -v[2]])
    if mirror:
        base_xf = xf
        xf = lambda v: base_xf(v) * np.array([-1.0, 1.0, 1.0])
    p = {k: xf(v[i]) for k, v in c.p.items()}
    cl, cr = (RIGHT, LEFT) if mirror else (LEFT, RIGHT)
    chain = [("pelvis", "waist", CENTER), ("waist", "chest", CENTER), ("chest", "neck", CENTER), ("neck", "head", CENTER), ("head", "headTop", CENTER)]
    for s, col in (("L", cl), ("R", cr)):
        chain += [("pelvis", "hip" + s, col), ("hip" + s, "knee" + s, col), ("knee" + s, "ankle" + s, col),
                  ("ankle" + s, "ball" + s, col), ("ball" + s, "toe" + s, col),
                  ("neck", "shoulder" + s, col), ("shoulder" + s, "elbow" + s, col), ("elbow" + s, "wrist" + s, col),
                  ("wrist" + s, "hand" + s, col)]
    return [(p[a], p[b], col) for a, b, col in chain]
