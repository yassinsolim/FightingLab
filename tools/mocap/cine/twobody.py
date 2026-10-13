"""Two-body hand-keyed authoring on motioncore's reference skeleton (Ultimate cinematics, round 6; started from the
motionthrows throw library).

Everything here mirrors tools/mocap (review.reconstruct = MotionPlayer.apply on the reference body) so a pose that is
right here is right in the clip. Authoring space is LIBRARY space in METRES: +X = the body's right, +Y = up (floor 0),
+Z = toward the opponent; each body has its own frame (root on the floor at the origin, facing +Z). The defender stands
`dist` metres in front of the attacker facing it: attacker-LS = (-x, y, dist - z) of defender-LS (and vice versa).

Paths: the mocap tools are this folder's parent; installed clips (Core and Moves, for "Clip@seconds" and
"Displayed:<Fighter>") and Motion.States come from the repo's src/ (or FIGHTINGLAB_CLIPS); the reference skeleton's
capture comes from the OV6 research folder (FIGHTINGLAB_OV6).

Keys (dicts, sorted by sim frame 'f'; clip time = f / 60 so the clip plays 1:1 with the sim frames):
  from      Pose | "Stance" | "Clip@seconds" | "Displayed:<Fighter>" | "style:<boxer|kickboxer|...>" (= the displayed
            idle of that style's fighter)   full base pose (later fields override)
  pelvis / pelvis+          [x,y,z] metres (absolute / delta)
  rot / rot+ / rot*         root rotation: Euler deg (Roblox XYZ: x+ leans back, y+ turns left, z+ leans left);
                            '+' = turn in the parent (heading) frame, '*' = turn in the body's own frame
  waist / waist+ ; neck / neck+   same, relative to the pelvis / chest
  LeftHand / RightHand / LeftFoot / RightFoot: { at, at+, pole, rot, rot+, lift, grip, w }
      at    [x,y,z] metres own-LS (hands: hand target, feet: sole point)
      pole  [x,y,z] own-LS direction the elbow/knee points
      rot   feet: Euler deg (Roblox, heading frame)
      lift  feet: arc height (m) of the step ending at this key
      grip  (point, [ox,oy,oz], frame) attach to a point of the OTHER body; w = attach weight 0..1
  contact   {LeftFoot: 0..1, RightFoot: 0..1} (else automatic from sole height + speed)
  ground    0..1 (else 0)
  ease      smooth | linear | in | out | snap | hold   (curve of the segment ending at this key)
"""
from __future__ import annotations

import copy
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
REPO = os.path.abspath(os.path.join(TOOLS, "..", ".."))
OV6 = os.environ.get("FIGHTINGLAB_OV6") or r"C:\Users\solim\.copilot\session-state\e3751321-5f48-4183-b62a-9577765df8cf\files\overhaul6"
sys.path.insert(0, TOOLS)

import clipio  # noqa: E402
import clipsheet  # noqa: E402
import keyed  # noqa: E402
import retarget as rt  # noqa: E402
import review  # noqa: E402

# The tools resolve the research captures relative to their own folder (OV6 layout); the repo keeps them outside.
clipsheet.OV6 = OV6
clipsheet.REF_BODY = os.path.join(OV6, "research", "motion", "raw", "accad", "Male2", "Male2_D1_StandToReady.bvh")
BODY = clipsheet.reference_body()
LEG, ARM, STAND = BODY.L, BODY.A, BODY.stand
CORE_DIR = os.environ.get("FIGHTINGLAB_CLIPS") or os.path.join(REPO, "src")
# Reference clips the specs sample but the game does not ship (e.g. a round-5 clip a round-6 clip re-times).
REF_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "refclips")
CLIP_DIRS = [CORE_DIR, REF_DIR]
LIMB_BASE = {"LeftHand": 15, "RightHand": 25, "LeftFoot": 35, "RightFoot": 45}
HANDS = ("LeftHand", "RightHand")
FEET = ("LeftFoot", "RightFoot")
LIMBS = HANDS + FEET
SIDE = {"LeftHand": "L", "RightHand": "R", "LeftFoot": "L", "RightFoot": "R"}
FPS = 60.0


# --------------------------------------------------------------------------------------------------------------------
# math helpers

def flip(v) -> np.ndarray:
    """Library space <-> clip (Roblox heading) space: negate z."""
    v = np.asarray(v, dtype=float)
    return np.array([v[0], v[1], -v[2]])


def eq(deg) -> np.ndarray:
    return keyed.euler_to_quat(deg)


def qm(q) -> np.ndarray:
    return rt.quat_to_mat(np.asarray(q, dtype=float)[None])[0]


def qmul(a, b) -> np.ndarray:
    return rt.quat_mul(np.asarray(a, float), np.asarray(b, float))


def qn(q) -> np.ndarray:
    q = np.asarray(q, dtype=float)
    return q / max(np.linalg.norm(q), 1e-12)


def slerp(a, b, t) -> np.ndarray:
    a, b = qn(a), qn(b)
    if float(np.dot(a, b)) < 0:
        b = -b
    return rt.quat_slerp(a, b, float(t))


def unit(v) -> np.ndarray:
    v = np.asarray(v, dtype=float)
    return v / max(np.linalg.norm(v), 1e-12)


def ease(kind: str, u: float) -> float:
    return keyed.ease(kind or "smooth", u)


def local_to_world(R_cs: np.ndarray, o_ls) -> np.ndarray:
    """Offset given in a body part's own library-style frame (+x right, +y up, +z front) -> own-LS world vector."""
    return flip(R_cs @ flip(o_ls))


def to_other(p) -> np.ndarray:
    """Point in one body's LS -> the other body's LS (bodies face each other `DIST` metres apart)."""
    p = np.asarray(p, dtype=float)
    return np.array([-p[0], p[1], DIST[0] - p[2]])


DIST = [0.93]   # set per throw (metres between the roots)


# --------------------------------------------------------------------------------------------------------------------
# poses

class Pose:
    __slots__ = ("pelvis", "q", "limbs", "contact", "ground")

    def __init__(self):
        self.pelvis = np.zeros(3)
        self.q = {"root": np.array([0, 0, 0, 1.0]), "waist": np.array([0, 0, 0, 1.0]), "neck": np.array([0, 0, 0, 1.0])}
        self.limbs = {l: {"at": np.zeros(3), "pole": np.array([0, 0, 1.0]), "rot": np.array([0, 0, 0, 1.0]), "grip": None, "w": 0.0, "lift": 0.0,
                          "knee": None, "kw": 0.0, "shin": np.array([0, -0.85, -0.45]),
                          "local": np.zeros(3), "lw": 0.0, "plocal": None} for l in LIMBS}
        self.contact = [None, None]
        self.ground = 0.0

    def copy(self) -> "Pose":
        return copy.deepcopy(self)


def frames_of(p: Pose):
    Rp = qm(p.q["root"])
    Rc = Rp @ qm(p.q["waist"])
    Rh = Rc @ qm(p.q["neck"])
    return Rp, Rc, Rh


def pose_from_channels(ch: np.ndarray) -> Pose:
    p = Pose()
    pelvis_cs = ch[0:3] * LEG + np.array([0, STAND, 0])
    p.pelvis = flip(pelvis_cs)
    p.q = {"root": qn(ch[3:7]), "waist": qn(ch[7:11]), "neck": qn(ch[11:15])}
    Rp, Rc, _ = frames_of(p)
    waist_cs = pelvis_cs + Rp @ BODY.waist
    for limb in LIMBS:
        b = LIMB_BASE[limb]
        s = SIDE[limb]
        rel, pole, rot = ch[b:b + 3], ch[b + 3:b + 6], ch[b + 6:b + 10]
        if limb in HANDS:
            at = waist_cs + Rc @ BODY.shoulder[s] + rel * ARM
        else:
            at = pelvis_cs + Rp @ BODY.hip[s] + rel * LEG
        p.limbs[limb] = {"at": flip(at), "pole": unit(flip(pole)), "rot": qn(rot), "grip": None, "w": 0.0, "lift": 0.0,
                         "knee": None, "kw": 0.0, "shin": np.array([0, -0.85, -0.45]),
                         "local": np.zeros(3), "lw": 0.0, "plocal": None}
    p.contact = [float(ch[55]), float(ch[56])]
    p.ground = float(ch[57])
    return p


def channels_from_pose(p: Pose) -> np.ndarray:
    ch = np.zeros(58)
    pelvis_cs = flip(p.pelvis)
    ch[0:3] = (pelvis_cs - np.array([0, STAND, 0])) / LEG
    ch[3:7], ch[7:11], ch[11:15] = qn(p.q["root"]), qn(p.q["waist"]), qn(p.q["neck"])
    Rp, Rc, _ = frames_of(p)
    waist_cs = pelvis_cs + Rp @ BODY.waist
    for limb in LIMBS:
        b = LIMB_BASE[limb]
        s = SIDE[limb]
        e = p.limbs[limb]
        if limb in HANDS:
            rel = (flip(e["at"]) - (waist_cs + Rc @ BODY.shoulder[s])) / ARM
        else:
            rel = (flip(e["at"]) - (pelvis_cs + Rp @ BODY.hip[s])) / LEG
        ch[b:b + 3] = rel
        ch[b + 3:b + 6] = unit(flip(e["pole"]))
        ch[b + 6:b + 10] = qn(e["rot"])
    ch[55] = 1.0 if p.contact[0] is None else p.contact[0]
    ch[56] = 1.0 if p.contact[1] is None else p.contact[1]
    ch[57] = p.ground
    return ch


def torso_joints(p: Pose) -> dict:
    """Pelvis/spine/head/shoulder/hip joints (own LS metres) + part frames."""
    Rp, Rc, Rh = frames_of(p)
    pel = flip(p.pelvis)
    J = {}
    J["pelvis"] = pel
    J["waist"] = pel + Rp @ BODY.waist
    J["neck"] = J["waist"] + Rc @ BODY.neck
    J["head"] = J["waist"] + Rc @ BODY.head
    J["headTop"] = J["head"] + Rh @ BODY.headTop
    for s in "LR":
        J["shoulder" + s] = J["waist"] + Rc @ BODY.shoulder[s]
        J["hip" + s] = pel + Rp @ BODY.hip[s]
    out = {k: flip(v) for k, v in J.items()}
    out["_R"] = {"pelvis": Rp, "chest": Rc, "head": Rh}
    return out


TWIST_CLAMP = {"on": True, "arm": 100.0, "leg": 60.0}   # solver keeps humerus/femur twist inside these (checks: 105/65)


def _rotate_about(v: np.ndarray, axis: np.ndarray, ang: float) -> np.ndarray:
    k = unit(axis)
    return v * math.cos(ang) + np.cross(k, v) * math.sin(ang) + k * float(k @ v) * (1 - math.cos(ang))


def solve_limb(p: Pose, J: dict, limb: str) -> None:
    """Two-bone IK exactly like review.reconstruct; adds the limb joints to J (own LS). When the authored pole would
    twist the upper bone past the natural limit (a broken-looking elbow/knee), the pole is turned about the
    root->target axis by the smallest angle that brings the twist back inside the limit; the corrected pole is
    written back to the pose, so the exported channel (and the runtime IK) use it too."""
    _solve_limb_raw(p, J, limb)
    if not TWIST_CLAMP["on"]:
        return
    lim = TWIST_CLAMP["arm" if limb in HANDS else "leg"]
    tw = limb_twist(J, limb)
    if tw is None or abs(tw) <= lim:
        return
    s = SIDE[limb]
    e = p.limbs[limb]
    root = J[("shoulder" if limb in HANDS else "hip") + s]
    tip = J[("hand" if limb in HANDS else "ankle") + s]
    axis = tip - root
    if np.linalg.norm(axis) < 1e-6:
        return
    pole0 = np.array(e["pole"], float)
    for step in range(1, 73):
        for sgn in (1.0, -1.0):
            e["pole"] = unit(_rotate_about(pole0, axis, sgn * math.radians(2.5 * step)))
            _solve_limb_raw(p, J, limb)
            tw2 = limb_twist(J, limb)
            if tw2 is None or abs(tw2) <= lim:
                return
    e["pole"] = pole0
    _solve_limb_raw(p, J, limb)


def _solve_limb_raw(p: Pose, J: dict, limb: str) -> None:
    s = SIDE[limb]
    e = p.limbs[limb]
    pole_cs = flip(e["pole"])
    if limb in HANDS:
        sh = flip(J["shoulder" + s])
        target = flip(e["at"])
        elbow, hand = review.two_bone(sh, target, BODY.upper, BODY.lower, pole_cs)
        J["elbow" + s], J["hand" + s] = flip(elbow), flip(hand)
        J["_reach" + limb] = float(np.linalg.norm(target - sh) - (BODY.upper + BODY.lower) * 0.999)
    else:
        hip = flip(J["hip" + s])
        sole = flip(e["at"])
        ankle = sole + np.array([0, BODY.ankleH, 0])
        knee, ankle2 = review.two_bone(hip, ankle, BODY.thigh, BODY.shin, pole_cs)
        Rf = qm(e["rot"])
        toe = ankle2 + Rf @ np.array([0, -BODY.ankleH * 0.8, -0.14])
        J["knee" + s], J["ankle" + s], J["toe" + s] = flip(knee), flip(ankle2), flip(toe)
        J["_reach" + limb] = float(np.linalg.norm(ankle - hip) - (BODY.thigh + BODY.shin) * 0.999)


def full_joints(p: Pose) -> dict:
    J = torso_joints(p)
    for limb in LIMBS:
        solve_limb(p, J, limb)
    return J


# --------------------------------------------------------------------------------------------------------------------
# base poses: Core clips, styled stances

def core_channels(name: str):
    return keyed.load_core_clip(name, CLIP_DIRS)


def core_frame(ref: str) -> np.ndarray:
    name, _, at = ref.partition("@")
    ch, raw = core_channels(name)
    return clipsheet.sample_channels(ch, float(raw["fps"]), bool(raw.get("loop")), float(at or 0))


def core_sources(name: str) -> list[str]:
    _, raw = core_channels(name.partition("@")[0])
    return list(raw.get("sources") or [])


# Motion.States.STYLES (motioncore) - guard arms in the CHEST frame (Roblox axes, arm lengths), yaw in degrees.
STYLES = {
    "boxer": dict(drop=0.0, width=0.85, length=0.9, w=0.9, lead=((0.22, 0.30, -0.40), (-0.25, -1, 0.35)), rear=((-0.20, 0.30, -0.28), (0.35, -1, 0.3)), yaw=30, clip="Stance"),
    "kickboxer": dict(drop=0.0, width=0.95, length=1.05, w=0.85, lead=((0.16, 0.22, -0.46), (-0.3, -1, 0.3)), rear=((-0.18, 0.26, -0.30), (0.35, -1, 0.3)), yaw=20, clip="Stance_Kickboxer"),
    "grappler": dict(drop=0.07, width=1.35, length=0.95, w=0.85, lead=((0.10, -0.05, -0.62), (-0.6, -1, 0.1)), rear=((-0.12, -0.08, -0.55), (0.6, -1, 0.1)), yaw=35, clip="Stance_Grappler"),
    "flow": dict(drop=0.04, width=1.2, length=0.9, w=0.6, lead=((0.12, 0.05, -0.45), (-0.5, -1, 0.2)), rear=((-0.10, 0.0, -0.32), (0.5, -1, 0.2)), yaw=30, clip="Stance"),
    "karate": dict(drop=0.03, width=0.95, length=1.25, w=0.9, lead=((0.10, -0.02, -0.72), (-0.5, -1, 0.1)), rear=((0.02, -0.38, 0.08), (0.6, -0.3, 0.75)), yaw=15, clip="Stance_Karate"),
    "kungfu": dict(drop=0.08, width=1.3, length=1.05, w=0.85, lead=((0.12, 0.08, -0.66), (-0.55, -1, 0.1)), rear=((-0.28, -0.05, -0.36), (0.5, -1, 0.2)), yaw=25, clip="Stance_KungFu"),
}
FIGHTER_STYLE = {"Kael": "boxer", "Sierra": "kickboxer", "Goran": "grappler", "Lumi": "flow", "Rhys": "karate", "Nia": "kungfu"}


def styled_stance_channels(style: str, t: float = 0.0) -> np.ndarray:
    """Offline copy of States.styleAdjust(..., 'stance') at now = 0 applied to the style's Stance clip frame: the pose the
    runtime shows when a fighter of this style idles (so a throw that ends here blends into Idle without a pop)."""
    st = STYLES[style]
    ch = core_frame(f"{st['clip']}@{t}").copy()
    # rotateYaw(+yaw): root offset, root rotation, limb rel vectors / poles / rots about the vertical axis (CS).
    yaw = math.radians(st["yaw"])
    Ry = np.array([[math.cos(yaw), 0, math.sin(yaw)], [0, 1, 0], [-math.sin(yaw), 0, math.cos(yaw)]])
    qy = eq([0, st["yaw"], 0])
    ch[0:3] = Ry @ ch[0:3]
    ch[3:7] = qmul(qy, ch[3:7])
    for limb in LIMBS:
        b = LIMB_BASE[limb]
        ch[b:b + 3] = Ry @ ch[b:b + 3]
        ch[b + 3:b + 6] = Ry @ ch[b + 3:b + 6]
        ch[b + 6:b + 10] = qmul(qy, ch[b + 6:b + 10])
    # Guard arms (chest frame) blended with weight w.
    Rc = qm(ch[3:7]) @ qm(ch[7:11])
    for limb, key in (("LeftHand", "lead"), ("RightHand", "rear")):
        b = LIMB_BASE[limb]
        rel, pole = np.array(st[key][0], float), unit(st[key][1])
        want = Rc @ rel
        ch[b:b + 3] = ch[b:b + 3] + (want - ch[b:b + 3]) * st["w"]
        pw = Rc @ pole
        ch[b + 3:b + 6] = unit(ch[b + 3:b + 6] + (pw - ch[b + 3:b + 6]) * st["w"])
    # Feet: width/length about the fighter's base, pelvis drop (leg-length units; sway = 0 at now = 0).
    root0 = flip(ch[0:3])
    root1 = root0 + np.array([0, -st["drop"], 0])
    for limb, side in (("LeftFoot", -1), ("RightFoot", 1)):
        b = LIMB_BASE[limb]
        world = root0 + flip(ch[b:b + 3])
        world = np.array([world[0] * st["width"] + side * (st["width"] - 1) * 0.05, world[1], world[2] * st["length"]])
        ch[b:b + 3] = flip(world - root1)
    ch[0:3] = flip(root1)
    return ch


STYLE_FIGHTER = {v: k for k, v in FIGHTER_STYLE.items()}


def displayed_channels(fighter: str, t: float = 0.0) -> np.ndarray:
    """The fighter's idle exactly as the runtime displays it (motioncore STANCES FINAL: style stance clip +
    Motion.States.styleAdjust read from the installed States.luau) - via keyed.py's "Displayed:<Fighter>"."""
    return keyed.displayed_frame(fighter, t, [CORE_DIR])


def stance_clip_name(style: str) -> str:
    """Core clip the style's displayed idle is sampled from (for credits)."""
    import lineup
    name = "Stance_" + lineup.STYLE_NAMES[style]
    try:
        keyed.load_core_clip(name, CLIP_DIRS)
        return name
    except FileNotFoundError:
        return "Stance"


def base_pose(ref) -> Pose:
    if isinstance(ref, Pose):
        return ref.copy()
    if isinstance(ref, str) and ref.startswith("style:"):
        return pose_from_channels(displayed_channels(STYLE_FIGHTER[ref[6:]]))
    if isinstance(ref, str) and ref.startswith("Displayed:"):
        name, _, at = ref.partition("@")
        return pose_from_channels(displayed_channels(name[len("Displayed:"):], float(at or 0)))
    return pose_from_channels(core_frame(ref))


# --------------------------------------------------------------------------------------------------------------------
# grip points

RADII = {"spineLow": 0.12, "spineHigh": 0.13, "shoulders": 0.06, "hips": 0.085, "neck": 0.055, "head": 0.105,
         "upperArm": 0.048, "foreArm": 0.04, "hand": 0.045, "thigh": 0.075, "shin": 0.052, "foot": 0.04}


def point(J: dict, spec) -> np.ndarray:
    """spec = (anchor, offset, frame). anchor: joint name | (j1, j2, frac); frame: pelvis|chest|head|world."""
    anchor, off, frame = spec[0], spec[1] if len(spec) > 1 else (0, 0, 0), spec[2] if len(spec) > 2 else "world"
    if isinstance(anchor, (tuple, list)):
        a = J[anchor[0]] + (J[anchor[1]] - J[anchor[0]]) * float(anchor[2])
    else:
        a = J[anchor]
    off = np.asarray(off, dtype=float)
    if frame == "world":
        return a + off
    return a + local_to_world(J["_R"][frame], off)


# --------------------------------------------------------------------------------------------------------------------
# tracks

class Track:
    """Hand-keyed body track. Keys are resolved with carry-over, then sampled per sim frame."""

    def __init__(self, keys: list[dict], name: str = ""):
        self.name = name
        self.keys = sorted(keys, key=lambda k: float(k["f"]))
        self.states: list[Pose] = []
        self.eases: list[str] = []
        self.explicit_contact = [False, False]
        self.explicit_ground = False
        self.carry: list[tuple] = []   # per key: (spec | None, weight); spec = {"part": "chest"|"pelvis", "ref": frame}
        prev = None
        cprev = (None, 0.0)
        for k in self.keys:
            if "carry" in k or "cw" in k:
                spec = k.get("carry", cprev[0])
                cprev = (spec, float(k.get("cw", 1.0 if "carry" in k else cprev[1])))
            self.carry.append(cprev)
        for k in self.keys:
            p = base_pose(k["from"]) if "from" in k or prev is None else prev.copy()
            if "from" not in k and prev is not None:
                for limb in LIMBS:
                    p.limbs[limb]["lift"] = 0.0
            if "from" in k:
                p.contact = [None, None]
            self._apply(p, k)
            self.states.append(p)
            self.eases.append(k.get("ease", "smooth"))
            prev = p
        # Explicit contacts carry forward over keys that do not set them (a "from" key resets them to automatic).
        for i in range(2):
            if self.explicit_contact[i]:
                last = 1.0
                for p in self.states:
                    if p.contact[i] is None:
                        p.contact[i] = last
                    last = p.contact[i]

    def _apply(self, p: Pose, k: dict) -> None:
        if "pelvis" in k:
            p.pelvis = np.asarray(k["pelvis"], float)
        if "root" in k:
            r = np.asarray(k["root"], float)
            p.pelvis = np.array([r[0] * LEG, r[1] * LEG + STAND, r[2] * LEG])
        if "pelvis+" in k:
            p.pelvis = p.pelvis + np.asarray(k["pelvis+"], float)
        for field, slot in (("rot", "root"), ("waist", "waist"), ("neck", "neck")):
            if field in k:
                p.q[slot] = eq(k[field])
            if field + "+" in k:
                p.q[slot] = qn(qmul(eq(k[field + "+"]), p.q[slot]))
            if field + "*" in k:
                p.q[slot] = qn(qmul(p.q[slot], eq(k[field + "*"])))
        for limb in LIMBS:
            e = k.get(limb)
            if not e:
                continue
            L = p.limbs[limb]
            if "at" in e:
                L["at"] = np.asarray(e["at"], float)
            if "at+" in e:
                L["at"] = L["at"] + np.asarray(e["at+"], float)
            if "pole" in e:
                L["pole"] = unit(e["pole"])
            if "rot" in e:
                L["rot"] = eq(e["rot"])
            if "rot+" in e:
                L["rot"] = qn(qmul(eq(e["rot+"]), L["rot"]))
            if "lift" in e:
                L["lift"] = float(e["lift"])
            if "grip" in e:
                L["grip"] = e["grip"]
                L["w"] = float(e.get("w", 1.0))
            elif "w" in e:
                L["w"] = float(e["w"])
            if "knee" in e:
                L["knee"] = e["knee"]
                L["kw"] = float(e.get("kw", 1.0))
            elif "kw" in e:
                L["kw"] = float(e["kw"])
            if "shin" in e:
                L["shin"] = unit(e["shin"])
            if "local" in e:
                L["local"] = np.asarray(e["local"], float)
                L["lw"] = float(e.get("lw", 1.0))
            elif "lw" in e:
                L["lw"] = float(e["lw"])
            if "plocal" in e:
                L["plocal"] = None if e["plocal"] is None else unit(e["plocal"])
        c = k.get("contact")
        if c:
            for i, limb in enumerate(FEET):
                if limb in c:
                    p.contact[i] = float(c[limb])
                    self.explicit_contact[i] = True
        if "ground" in k:
            p.ground = float(k["ground"])
            self.explicit_ground = True

    def carry_at(self, f: float):
        """(spec, weight) of the carry attachment at sim frame f (weight interpolated between keys)."""
        fs = [float(k["f"]) for k in self.keys]
        if f <= fs[0]:
            return self.carry[0]
        if f >= fs[-1]:
            return self.carry[-1]
        j = 0
        while j + 1 < len(fs) and fs[j + 1] < f:
            j += 1
        (sa, wa), (sb, wb) = self.carry[j], self.carry[j + 1]
        u = ease(self.eases[j + 1], (f - fs[j]) / max(fs[j + 1] - fs[j], 1e-9))
        spec = sb if wb > 0 else sa
        return spec, wa + (wb - wa) * u

    def sample(self, f: float) -> tuple[Pose, dict]:
        """Base pose at sim frame f (grips unresolved) + per-limb grip blend info."""
        p, info = self._sample(f)
        apply_local(p)
        return p, info

    def _sample(self, f: float) -> tuple[Pose, dict]:
        fs = [float(k["f"]) for k in self.keys]
        if f <= fs[0]:
            p = self.states[0].copy()
            return p, {l: (self.states[0].limbs[l]["grip"], None, 0.0, self.states[0].limbs[l]["w"],
                           self.states[0].limbs[l]["knee"], None, self.states[0].limbs[l]["kw"]) for l in LIMBS}
        if f >= fs[-1]:
            p = self.states[-1].copy()
            return p, {l: (self.states[-1].limbs[l]["grip"], None, 0.0, self.states[-1].limbs[l]["w"],
                           self.states[-1].limbs[l]["knee"], None, self.states[-1].limbs[l]["kw"]) for l in LIMBS}
        j = 0
        while j + 1 < len(fs) and fs[j + 1] < f:
            j += 1
        a, b = self.states[j], self.states[j + 1]
        raw = (f - fs[j]) / max(fs[j + 1] - fs[j], 1e-9)
        kind = self.eases[j + 1]
        u = ease(kind, raw)
        p = Pose()
        p.pelvis = a.pelvis + (b.pelvis - a.pelvis) * u
        arc = self.keys[j + 1].get("arc")
        if arc:
            p.pelvis = p.pelvis + np.array([0, float(arc) * 4 * raw * (1 - raw), 0])
        for slot in ("root", "waist", "neck"):
            p.q[slot] = slerp(a.q[slot], b.q[slot], u)
        info = {}
        for limb in LIMBS:
            ea, eb = a.limbs[limb], b.limbs[limb]
            e = p.limbs[limb]
            e["at"] = ea["at"] + (eb["at"] - ea["at"]) * u
            if limb in FEET and eb["lift"] > 0:
                e["at"] = e["at"] + np.array([0, eb["lift"] * math.sin(math.pi * raw), 0])
            e["pole"] = unit(ea["pole"] + (eb["pole"] - ea["pole"]) * u)
            e["rot"] = slerp(ea["rot"], eb["rot"], u)
            w = ea["w"] + (eb["w"] - ea["w"]) * u
            kw = ea["kw"] + (eb["kw"] - ea["kw"]) * u
            e["shin"] = unit(ea["shin"] + (eb["shin"] - ea["shin"]) * u)
            e["local"] = ea["local"] + (eb["local"] - ea["local"]) * u
            e["lw"] = ea["lw"] + (eb["lw"] - ea["lw"]) * u
            pa_, pb_ = ea["plocal"], eb["plocal"]
            e["plocal"] = None if pa_ is None and pb_ is None else unit((pa_ if pa_ is not None else pb_) * (1 - u) + (pb_ if pb_ is not None else pa_) * u)
            info[limb] = (ea["grip"] if ea["w"] > 0 else eb["grip"], eb["grip"] if eb["w"] > 0 else ea["grip"], u, w,
                          ea["knee"] if ea["kw"] > 0 else eb["knee"], eb["knee"] if eb["kw"] > 0 else ea["knee"], kw)
        for i in range(2):
            ca = a.contact[i] if a.contact[i] is not None else 1.0
            cb = b.contact[i] if b.contact[i] is not None else 1.0
            p.contact[i] = ca + (cb - ca) * (u if kind != "hold" else (1.0 if raw >= 1 else 0.0))
        p.ground = a.ground + (b.ground - a.ground) * u
        return p, info


def apply_local(p: Pose) -> None:
    """Limbs authored in the body frame ('local': feet in the pelvis frame, hands in the chest frame; 'plocal': pole in
    that frame) follow the body through flips and lifts."""
    Rp, Rc, _ = frames_of(p)
    pel = flip(p.pelvis)
    waist = pel + Rp @ BODY.waist
    for limb in LIMBS:
        e = p.limbs[limb]
        R, origin = (Rc, waist) if limb in HANDS else (Rp, pel)
        if e["lw"] > 1e-6:
            world = flip(origin + R @ flip(e["local"]))
            e["at"] = e["at"] + (world - e["at"]) * min(e["lw"], 1.0)
        if e["plocal"] is not None:
            e["pole"] = unit(flip(R @ flip(e["plocal"])))


def resolve_grip(own_at: np.ndarray, info, other_J: dict) -> np.ndarray:
    g0, g1, u, w = info[0], info[1], info[2], info[3]
    if w <= 1e-6 or (g0 is None and g1 is None):
        return own_at
    p0 = to_other(point(other_J, g0)) if g0 is not None else None
    p1 = to_other(point(other_J, g1)) if g1 is not None else None
    if p0 is None:
        gp = p1
    elif p1 is None:
        gp = p0
    else:
        gp = p0 + (p1 - p0) * u
    return own_at + (gp - own_at) * min(max(w, 0.0), 1.0)


def resolve_knee(p: "Pose", J: dict, limb: str, info, other_J: dict) -> None:
    """Knee strike: place the knee on a point of the other body (thigh length from the hip toward it), shin along the
    limb's 'shin' direction; blends the foot target and knee pole by the key weight kw."""
    k0, k1, u, kw = info[4], info[5], info[2], info[6]
    if kw <= 1e-6 or (k0 is None and k1 is None):
        return
    q0 = to_other(point(other_J, k0)) if k0 is not None else None
    q1 = to_other(point(other_J, k1)) if k1 is not None else None
    target = q1 if q0 is None else (q0 if q1 is None else q0 + (q1 - q0) * u)
    hip = J["hip" + SIDE[limb]]
    d = target - hip
    knee = hip + unit(d) * min(np.linalg.norm(d), BODY.thigh * 0.999)
    e = p.limbs[limb]
    ankle = knee + e["shin"] * BODY.shin * 0.999
    sole = ankle - np.array([0, BODY.ankleH, 0])
    mid = (hip + ankle) * 0.5
    kpole = unit(knee - mid) if np.linalg.norm(knee - mid) > 1e-4 else e["pole"]
    a = min(max(kw, 0.0), 1.0)
    e["at"] = e["at"] + (sole - e["at"]) * a
    e["pole"] = unit(e["pole"] + (kpole - e["pole"]) * a)
    J["_kneeTarget" + limb] = target


M_OTHER = np.diag([-1.0, 1.0, -1.0])


def part_frame_cs(J: dict, part: str) -> tuple[np.ndarray, np.ndarray]:
    """(R, x) of a body part in its owner's clip space; chest origin = waist joint, pelvis origin = pelvis."""
    R = J["_R"][part]
    x = flip(J["pelvis"] if part == "pelvis" else J["waist"])
    return R, x


def to_other_cs(R: np.ndarray, x: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    t = np.array([0.0, 0.0, -DIST[0]])
    return M_OTHER @ R, M_OTHER @ x + t


def apply_rigid(p: Pose, Rg: np.ndarray, xg: np.ndarray, w: float) -> None:
    """Moves a whole pose by the rigid transform (Rg, xg) given in its own clip space, blended by w."""
    w = min(max(w, 0.0), 1.0)
    if w <= 1e-6:
        return

    def tp(v_ls):
        v = flip(v_ls)
        return flip(Rg @ v + xg)

    qg = rt.mat_to_quat(Rg[None])[0]
    new_pel = tp(p.pelvis)
    p.pelvis = p.pelvis + (new_pel - p.pelvis) * w
    p.q["root"] = slerp(p.q["root"], qmul(qg, p.q["root"]), w)
    for limb in LIMBS:
        e = p.limbs[limb]
        e["at"] = e["at"] + (tp(e["at"]) - e["at"]) * w
        e["pole"] = unit(e["pole"] + (flip(Rg @ flip(e["pole"])) - e["pole"]) * w)
        e["rot"] = slerp(e["rot"], qmul(qg, e["rot"]), w)
        e["shin"] = unit(e["shin"] + (flip(Rg @ flip(e["shin"])) - e["shin"]) * w)


def carry_body(carried: Pose, carried_track: "Track", f: float, carrier_track: "Track", carrier_J: dict) -> None:
    """Rigidly attaches `carried` to a part of the other body: the carried body follows the carrier part's motion since
    the spec's reference frame (on top of its own authored motion)."""
    spec, w = carried_track.carry_at(f)
    if not spec or w <= 1e-6:
        return
    part = spec.get("part", "chest")
    ref_pose, _ = carrier_track.sample(float(spec["ref"]))
    Rr, xr = to_other_cs(*part_frame_cs(torso_joints(ref_pose), part))
    Rf, xf = to_other_cs(*part_frame_cs(carrier_J, part))
    if spec.get("rot", True):
        Rg = Rf @ Rr.T
        xg = xf - Rg @ xr
    else:
        # translation only: the carried body rides along with the part's origin, its rotation stays authored
        Rg = np.eye(3)
        xg = xf - xr
    apply_rigid(carried, Rg, xg, w)


def solve_pair(att: Track, dfd: Track, frames, order) -> tuple[list[Pose], list[Pose], list[dict], list[dict]]:
    """Samples both tracks at the given sim frames and resolves carries and grips. order: list of ("A"|"D", limb) - the
    limbs listed are solved in that order (a grip may only use the other body's torso or limbs solved earlier)."""
    PA, PD, JA, JD = [], [], [], []
    full = list(order) + [(w, l) for w in "AD" for l in LIMBS if (w, l) not in order]
    for f in frames:
        pa, ia = att.sample(f)
        pd, idf = dfd.sample(f)
        # carries: the carrier's torso first, then the carried body follows it
        if dfd.carry_at(f)[1] > 1e-6:
            carry_body(pd, dfd, f, att, torso_joints(pa))
        elif att.carry_at(f)[1] > 1e-6:
            carry_body(pa, att, f, dfd, torso_joints(pd))
        ja, jd = torso_joints(pa), torso_joints(pd)
        for who, limb in full:
            p, info, J, other = (pa, ia, ja, jd) if who == "A" else (pd, idf, jd, ja)
            p.limbs[limb]["at"] = resolve_grip(p.limbs[limb]["at"], info[limb], other)
            gi = info[limb]
            J["_gw" + limb] = float(gi[3]) if (gi[0] is not None or gi[1] is not None) else 0.0
            if limb in FEET:
                resolve_knee(p, J, limb, info[limb], other)
            solve_limb(p, J, limb)
        PA.append(pa); PD.append(pd); JA.append(ja); JD.append(jd)
    return PA, PD, JA, JD


def solve_single(tr: Track, frames) -> tuple[list[Pose], list[dict]]:
    P, J = [], []
    for f in frames:
        p, _ = tr.sample(f)
        j = torso_joints(p)
        for limb in LIMBS:
            solve_limb(p, j, limb)
        P.append(p); J.append(j)
    return P, J


def sanitize_contacts(P: list, dt: float) -> None:
    """Runtime locks planted feet in world space, so a foot may only be 'planted' while its sole is on the floor and
    it is not moving: clear contact where the foot is airborne or travelling (explicit keys included), and fade it in
    over two frames so the lock never grabs a foot mid-step."""
    n = len(P)
    for i, limb in enumerate(FEET):
        h = np.array([P[k].limbs[limb]["at"][1] for k in range(n)])
        xz = np.array([[P[k].limbs[limb]["at"][0], P[k].limbs[limb]["at"][2]] for k in range(n)])
        v = np.zeros(n)
        if n > 1:
            v[1:] = np.linalg.norm(np.diff(xz, axis=0), axis=1) / dt
            v[0] = v[1]
            v[:-1] = np.maximum(v[:-1], v[1:])     # moving into the next frame counts as moving
        ok = (h < 0.045) & (v < 0.35)
        c = np.array([float(P[k].contact[i] or 0.0) for k in range(n)])
        c = np.where(ok, c, 0.0)
        out = c.copy()
        for k in range(1, n):
            if c[k] > 0 and out[k - 1] < c[k]:
                out[k] = min(c[k], out[k - 1] + 0.5)
        for k in range(n):
            P[k].contact[i] = float(out[k])


def auto_contacts(P: list[Pose], J: list[dict], explicit, dt: float) -> None:
    """Planted = sole on the floor and not moving (unless the keys set contacts explicitly)."""
    n = len(P)
    for i, limb in enumerate(FEET):
        if explicit[i]:
            continue
        h = np.array([P[k].limbs[limb]["at"][1] for k in range(n)])
        xz = np.array([[P[k].limbs[limb]["at"][0], P[k].limbs[limb]["at"][2]] for k in range(n)])
        v = np.zeros(n)
        v[1:] = np.linalg.norm(np.diff(xz, axis=0), axis=1) / dt
        v[0] = v[1] if n > 1 else 0
        c = np.clip((0.035 - h) / 0.02, 0, 1) * np.clip((0.5 - v) / 0.3, 0, 1)
        for k in range(n):
            P[k].contact[i] = float(c[k])


# --------------------------------------------------------------------------------------------------------------------
# checks

def capsules(J: dict) -> list[tuple[str, np.ndarray, np.ndarray, float]]:
    c = []
    c.append(("spineLow", J["pelvis"], J["waist"], RADII["spineLow"]))
    c.append(("spineHigh", J["waist"], (J["neck"] * 0.8 + J["waist"] * 0.2), RADII["spineHigh"]))
    c.append(("shoulders", J["shoulderL"], J["shoulderR"], RADII["shoulders"]))
    c.append(("hips", J["hipL"], J["hipR"], RADII["hips"]))
    c.append(("neck", J["neck"], J["head"], RADII["neck"]))
    hc = (J["head"] + J["headTop"]) * 0.5
    c.append(("head", hc, hc, RADII["head"]))
    for s in "LR":
        if "elbow" + s in J:
            c.append(("upperArm" + s, J["shoulder" + s], J["elbow" + s], RADII["upperArm"]))
            c.append(("foreArm" + s, J["elbow" + s], J["hand" + s], RADII["foreArm"]))
            c.append(("hand" + s, J["hand" + s], J["hand" + s], RADII["hand"]))
        if "knee" + s in J:
            c.append(("thigh" + s, J["hip" + s], J["knee" + s], RADII["thigh"]))
            c.append(("shin" + s, J["knee" + s], J["ankle" + s], RADII["shin"]))
            c.append(("foot" + s, J["ankle" + s], J["toe" + s], RADII["foot"]))
    return c


def seg_dist(p1, q1, p2, q2) -> float:
    d1, d2, r = q1 - p1, q2 - p2, p1 - p2
    a, e, f = float(d1 @ d1), float(d2 @ d2), float(d2 @ r)
    if a <= 1e-12 and e <= 1e-12:
        return float(np.linalg.norm(r))
    if a <= 1e-12:
        s, t = 0.0, min(max(f / e, 0), 1)
    else:
        c = float(d1 @ r)
        if e <= 1e-12:
            t, s = 0.0, min(max(-c / a, 0), 1)
        else:
            b = float(d1 @ d2)
            den = a * e - b * b
            s = min(max((b * f - c * e) / den, 0), 1) if den > 1e-12 else 0.0
            t = (b * s + f) / e
            if t < 0:
                t, s = 0.0, min(max(-c / a, 0), 1)
            elif t > 1:
                t, s = 1.0, min(max((b - c) / a, 0), 1)
    return float(np.linalg.norm((p1 + d1 * s) - (p2 + d2 * t)))


def penetration(JA: dict, JD_in_A: dict, allow) -> tuple[float, str]:
    """Worst capsule overlap (m, positive = interpenetration) between the two bodies. `allow` = [(a_prefix, d_prefix[,
    tolerance_m])]: intended contacts (gripping hands, forearms on the neck, knee strikes) are reported only beyond
    their tolerance (default 3 cm; a hand wrapped around a limb has its centre on the limb axis: use ~0.09)."""
    rules = []
    for x in allow:
        rules.append((x[0], x[1], float(x[2]) if len(x) > 2 else 0.03))
    worst, where = -1.0, ""
    for na, a0, a1, ra in capsules(JA):
        for nd, d0, d1, rd in capsules(JD_in_A):
            ov = ra + rd - seg_dist(a0, a1, d0, d1)
            tol = max([t for x, y, t in rules if na.startswith(x) and nd.startswith(y)], default=0.0)
            ov -= tol
            if ov > worst:
                worst, where = ov, f"{na}/{nd}"
    return worst, where


SELF_PAIRS = [("foreArmL", "spine"), ("foreArmR", "spine"), ("handL", "spine"), ("handR", "spine"),
              ("foreArmL", "head"), ("foreArmR", "head"), ("thighL", "thighR"), ("shinL", "shinR"), ("footL", "footR"),
              ("shinL", "thighR"), ("shinR", "thighL"), ("handL", "thigh"), ("handR", "thigh")]


def self_penetration(J: dict) -> tuple[float, str]:
    caps = capsules(J)
    worst, where = -1.0, ""
    for x, y in SELF_PAIRS:
        for n1, a0, a1, r1 in caps:
            if not n1.startswith(x):
                continue
            for n2, b0, b1, r2 in caps:
                if not n2.startswith(y) or n1 == n2:
                    continue
                ov = (r1 + r2) * 0.85 - seg_dist(a0, a1, b0, b1)
                if ov > worst:
                    worst, where = ov, f"{n1}/{n2}"
    return worst, where


def lowest(J: dict) -> float:
    return min(min(a[1], b[1]) - r for _, a, b, r in capsules(J))


def torso_bottom(J: dict) -> float:
    return min(min(a[1], b[1]) - r for n, a, b, r in capsules(J) if n.startswith(("spine", "shoulders", "hips", "head")))


def limb_twist(J: dict, limb: str) -> float | None:
    """Humerus/femur twist (deg) relative to the natural hinge orientation: swing the rest limb (hanging down, elbow
    folding forward / knee folding backward) onto the actual upper bone, compare the carried fold direction with the
    actual fold direction. |twist| > ~100 (arm) / ~60 (leg) reads as a broken joint. None when nearly straight or
    pointing straight up (undefined)."""
    s = SIDE[limb]
    arm = limb in HANDS
    R = J["_R"]["chest" if arm else "pelvis"]
    a = J[("shoulder" if arm else "hip") + s]
    m = J[("elbow" if arm else "knee") + s]
    t = J[("hand" if arm else "ankle") + s]
    u = unit(m - a)
    f = unit(t - m)
    fold = f - u * float(f @ u)
    if np.linalg.norm(fold) < 0.12:          # nearly straight: hinge direction meaningless
        return None
    fold = unit(fold)
    down = local_to_world(R, [0, -1, 0])
    rest_fold = local_to_world(R, [0, 0, 1] if arm else [0, 0, -1])
    if float(u @ down) < -0.9:
        return None
    # rotation taking `down` onto u (shortest arc), applied to rest_fold
    axis = np.cross(down, u)
    sa = np.linalg.norm(axis)
    ca = float(down @ u)
    if sa < 1e-9:
        carried = rest_fold
    else:
        k = axis / sa
        ang = math.atan2(sa, ca)
        carried = rest_fold * math.cos(ang) + np.cross(k, rest_fold) * math.sin(ang) + k * float(k @ rest_fold) * (1 - math.cos(ang))
    carried = unit(carried - u * float(carried @ u))
    return math.degrees(math.atan2(float(np.cross(carried, fold) @ u), float(carried @ fold)))


# --------------------------------------------------------------------------------------------------------------------
# rendering (dense review sheets with body volumes)

COL_A = {"C": (235, 235, 235), "L": (90, 170, 255), "R": (255, 120, 90)}
COL_D = {"C": (170, 230, 150), "L": (60, 150, 120), "R": (200, 170, 60)}


def project(view: str):
    if view == "side":
        R = np.array([[0, 0, 1.0], [0, 1.0, 0]])
    elif view == "front":
        R = np.array([[-1.0, 0, 0], [0, 1.0, 0]])
    elif view == "top":
        R = np.array([[0, 0, 1.0], [-1.0, 0, 0]])
    else:
        a = math.radians(40)
        R = np.array([[math.sin(a), 0, math.cos(a)], [0, 1.0, 0]])
    return R


def draw_bodies(bodies, view: str, size: int, scale: float, center, label: str, highlight=None, marks=()):
    img = Image.new("RGB", (size, size), (24, 26, 32))
    d = ImageDraw.Draw(img)
    P = project(view)

    def pr(p):
        q = P @ (np.asarray(p) - center)
        return (size / 2 + q[0] * scale, size * 0.55 - q[1] * scale)

    if view != "top":
        fy = pr(np.array([center[0], 0, center[2]]))[1]
        d.line([(0, fy), (size, fy)], fill=(80, 85, 95), width=1)
    for J, cols in bodies:
        caps = capsules(J)
        # draw far limbs first (rough depth: library x for the side view)
        order = sorted(caps, key=lambda c: (c[1][0] + c[2][0]) * (1 if view == "side" else 0))
        for n, a, b, r in order:
            side = "L" if n.endswith("L") else "R" if n.endswith("R") else "C"
            col = cols[side]
            w = max(2, int(2 * r * scale))
            pa, pb = pr(a), pr(b)
            d.line([pa, pb], fill=tuple(int(c * 0.55) for c in col), width=w + 2)
            d.line([pa, pb], fill=col, width=max(1, w - 2))
            if np.linalg.norm(np.asarray(a) - np.asarray(b)) < 1e-6:
                rr = r * scale
                d.ellipse([pa[0] - rr, pa[1] - rr, pa[0] + rr, pa[1] + rr], outline=col, width=2)
    for p, col in marks:
        q = pr(p)
        d.ellipse([q[0] - 3, q[1] - 3, q[0] + 3, q[1] + 3], outline=col, width=2)
    d.text((4, 3), label, fill=(255, 230, 120))
    if highlight:
        d.rectangle([1, 1, size - 2, size - 2], outline=highlight, width=3)
    return img


def sheet(rows, out: str, title: str) -> None:
    w = rows[0][0].width
    h = rows[0][0].height
    cols = max(len(r) for r in rows)
    img = Image.new("RGB", (w * cols, h * len(rows) + 18), (10, 10, 12))
    d = ImageDraw.Draw(img)
    d.text((4, 3), title, fill=(255, 255, 255))
    for r, row in enumerate(rows):
        for c, pnl in enumerate(row):
            img.paste(pnl, (c * w, 18 + r * h))
    img.save(out)


def joints_to_other(J: dict) -> dict:
    out = {}
    for k, v in J.items():
        if k.startswith("_"):
            if k == "_R":
                # body frames re-expressed for the other body's LS: x -> -x, z -> dist - z == rotate 180 deg about Y
                Ryp = np.diag([-1.0, 1.0, -1.0])
                out[k] = {n: Ryp @ R for n, R in v.items()}
            else:
                out[k] = v
            continue
        out[k] = to_other(v)
    return out
