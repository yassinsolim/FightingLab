"""LUMI (acrobat) Ultimate 'Skyline' (roster beats, movesets.md 5.4):
  f0     the hit: an armored running jump kick into the chest; the opponent rocks back and Lumi lands light in front
  imp 1  a spinning heel kick to the ribs; the defender bends sideways
  imp 2  a cartwheel kick over the top onto the defender's shoulder; it sinks to one knee
  imp 3  she runs up its thigh and chest like a rooftop wall and kicks off its chest (back-flip off the body); the
         defender is knocked upright, arms wide
  imp 4  at the top of the flip, a scissor kick to the head; its head whips sideways
  imp 5  she lands low and a fast drop sweep takes its legs; it floats up horizontally
  imp 6  she springs into a front flip and drives a falling heel down onto the floating defender, spiking it face-first
         into the floor (FaceDown, head away, on its spot); she lands crouched on one hand
"""
from __future__ import annotations

import numpy as np

import twobody as T
import cinecommon as C
from cinecommon import F, pk

FIGHTER = "Lumi"
STYLE = "flow"
ROOT_HEIGHT = 4.111

VAULT = "Kick_Lumi_VaultKick"
HEEL = "Kick_Lumi_PalmHeel"
WHEEL = "Kick_Lumi_CartwheelKick"
FLIP = "Kick_Lumi_FlipKick"
SCISSOR = "Kick_Lumi_ScissorKick"
LOW = "Kick_Lumi_QuickLow"
CRESCENT = "Kick_Lumi_CrescentKick"

ALLOW = [("foot", "spine", 0.06), ("foot", "hips", 0.06), ("foot", "head", 0.06), ("foot", "shoulders", 0.06), ("shin", "spine", 0.05),
         ("shin", "shoulders", 0.05), ("foot", "thigh", 0.06), ("shin", "thigh", 0.04), ("foot", "shin", 0.05), ("shin", "shin", 0.04),
         ("hand", "spine", 0.05), ("hand", "shoulders", 0.05), ("hand", "head", 0.05), ("foreArm", "spine", 0.04), ("thigh", "spine", 0.04)]


def home_m(end_distance: float) -> float:
    return end_distance / (ROOT_HEIGHT * 0.775) * T.LEG


def kneeling(z: float) -> T.Pose:
    """The defender sunk to one knee (the right knee down behind it), torso bent over."""
    p = C.pose_at("HitMidHeavy@0.3", z)
    p = C.lowered(p, 0.36)
    p.limbs["RightFoot"]["at"] = np.array([0.16, 0.02, z - 0.42])
    p.limbs["RightFoot"]["pole"] = T.unit([0.1, -0.3, 1.0])
    p.limbs["LeftFoot"]["at"] = np.array([-0.16, 0.0, z + 0.22])
    return p


def build(tl: dict) -> dict:
    D = tl["duration"]
    i1, i2, i3, i4, i5, i6 = tl["impacts"]
    home = home_m(tl.get("endDistance", 4.4))
    T.DIST[0] = home
    stance = C.stance_of(FIGHTER)
    H = C.Hits()

    # --- defender ---------------------------------------------------------------------------------------------------
    kick = C.tip_of(T.full_joints(C.pose_at(C.at(VAULT, "contact"))), "LeftFoot")
    ch_d = T.point(T.full_joints(C.pose_at("HitMidHeavy@0.0")), C.chest()[:3])
    z0 = home - ch_d[2] - kick[2] - 0.03
    zc = home - 1.05

    def r(f, ref, z, ease=None, **kw):
        return pk(f, C.pose_at(ref, z), ease, **kw)

    Dk = [
        # rocked back by the jump kick
        r(0, "HitMidHeavy@0.0", z0, rot_plus=[10, 0, 0], waist_plus=[8, 0, 0]),
        r(10, "HitMidHeavy@0.15", z0 - 0.04, rot_plus=[6, 0, 0], lift=(0.04, 0.04)),
        r(i1 - 6, "HitMidHeavy@0.5", zc),
        # the spinning heel on its left ribs: bends sideways
        r(i1, "HitMidHeavy@0.0", zc, "snap", rot_plus=[0, 8, 12], waist_plus=[-4, 6, 14]),
        r(i1 + 10, "HitMidHeavy@0.15", zc - 0.03, rot_plus=[-2, 6, 12], waist_plus=[-4, 6, 12]),
        r(i2 - 6, "HitMidHeavy@0.4", zc - 0.02),
        # the cartwheel kick on its right shoulder: it sinks to one knee
        r(i2, "HitHighHeavy@0.0", zc - 0.02, "snap", neck_plus=[-16, 0, -8], rot_plus=[-6, 0, -6]),
        pk(i2 + 10, kneeling(zc - 0.04), lift=(0.0, 0.05)),
        pk(i3 - 4, kneeling(zc - 0.04), rot_plus=[-4, 0, 0]),
        # the kick-off from its chest knocks it upright, arms wide
        r(i3, "HitHighHeavy@0.0", zc - 0.06, "snap", rot_plus=[10, 0, 0], neck_plus=[16, 0, 0],
          LeftHand={"local": [-0.56, 0.40, 0.02], "lw": 1.0}, RightHand={"local": [0.56, 0.40, 0.02], "lw": 1.0}),
        r(i3 + 12, "HitHighHeavy@0.2", zc - 0.10, rot_plus=[6, 0, 0], lift=(0.04, 0.04),
          LeftHand={"local": [-0.52, 0.30, 0.06], "lw": 1.0}, RightHand={"local": [0.52, 0.30, 0.06], "lw": 1.0}),
        r(i4 - 6, "HitHighHeavy@0.4", zc - 0.10),
        # the scissor kick whips its head sideways
        r(i4, "HitHighHeavy@0.0", zc - 0.10, "snap", neck_plus=[6, -32, -10], waist_plus=[0, -8, 0]),
        r(i4 + 10, "HitHighHeavy@0.15", zc - 0.12, neck_plus=[4, -20, -6]),
        r(i5 - 8, "Stagger@0.45", zc - 0.10),
        # the drop sweep takes its legs: it floats up horizontally
        r(i5, "HitLowHeavy@0.0", zc - 0.10, "snap"),
        C.floating(i5 + 8, 0.66, zc - 0.10, pitch=60, legs=0.05),
        C.floating(i5 + 20, 0.92, zc - 0.12, pitch=86, yaw=-40),
        C.floating(i6 - 4, 0.86, zc - 0.12, pitch=90, yaw=-50),
        # the falling heel spikes it: it turns face down and is driven into the floor, head away from her
        C.floating(i6, 0.78, zc - 0.12, pitch=94, yaw=-50, roll=-40, ease="snap"),
        F(i6 + 4, **{"pelvis": [0.0, 0.62, (zc - 0.12) * 0.6], "rot": [0, -180, 0], "rot+": [72, 0, 0], "waist": [-6, 0, 0], "neck": [14, 0, 0],
                     "LeftHand": {"local": [-0.32, 0.22, 0.42], "lw": 1.0}, "RightHand": {"local": [0.32, 0.22, 0.42], "lw": 1.0},
                     "LeftFoot": {"local": [-0.14, -0.84, -0.16], "lw": 1.0}, "RightFoot": {"local": [0.14, -0.82, -0.10], "lw": 1.0}}),
        F(i6 + 12, ease="in", **{"from": C.end_pose("FaceDown"), "ground": 1.0}),
        F(D, **{"from": C.end_pose("FaceDown"), "ground": 1.0}),
    ]
    dtrack = T.Track(Dk, "D")

    # --- attacker ---------------------------------------------------------------------------------------------------
    A = [pk(0, C.pose_at(C.at(VAULT, "contact"))), pk(7, C.pose_at(C.at(VAULT, "recover"))), pk(12, C.pose_at(C.at(VAULT, "end")))]
    # the spinning heel kick to its left ribs
    _, b1 = C.strike_beat(dtrack, i1, HEEL, "RightFoot", C.ribs(-1), stance, start_off=12, windup_off=6, recover_off=8, guard_after=6, arm_tol=-0.1)
    A += b1[1:]
    H.add(i1, "RightFoot", "Mid", C.ribs(-1))
    # the cartwheel kick over the top onto its right shoulder
    _, b2 = C.strike_beat(dtrack, i2, WHEEL, "LeftFoot", C.shoulder_top(+1), stance, start_off=14, windup_off=7, recover_off=9, guard_after=6,
                          clear=0.0, arm_tol=-0.1)
    A += b2
    H.add(i2, "LeftFoot", "High", C.shoulder_top(+1))
    # runs up its thigh and chest and kicks off: the feet on its body, the body rising, then the push-off
    dz3 = C.reach_dz(C.raised(stance, 0.55), "RightFoot", C.chest(), dtrack, i3, 0.02, clear=0.0, arm_tol=-0.3)
    run = C.pose_at(stance, dz3 - 0.25)
    A += [
        pk(i3 - 18, run, lift=(0.05, 0.05)),
        pk(i3 - 12, C.pose_at(stance, dz3 - 0.10), RightFoot={"grip": C.thigh(+1, frac=0.45), "w": 1.0, "pole": [0.2, 0.2, 1.0]},
           rot_plus=[-12, 0, 0], contact={"RightFoot": 0.0}),
        pk(i3 - 6, C.raised(C.pose_at(stance, dz3 - 0.05), 0.30), LeftFoot={"grip": C.belly(), "w": 1.0, "pole": [-0.2, 0.3, 1.0]},
           RightFoot={"grip": C.thigh(+1, frac=0.45), "w": 1.0}, rot_plus=[-6, 0, 0], contact={"LeftFoot": 0.0, "RightFoot": 0.0}),
        pk(i3, C.rotated(C.raised(C.pose_at(stance, dz3), 0.48), [22, 0, 0]), "snap", RightFoot={"grip": C.chest(), "w": 1.0, "pole": [0.2, 0.5, 1.0]},
           LeftFoot={"at": [-0.2, 0.55, dz3 + 0.30], "pole": [-0.2, 0.5, 1.0]}, contact={"LeftFoot": 0.0, "RightFoot": 0.0}),
        # the back-flip off the body (a full turn back in the air), coming out high for the scissor kick
        pk(i3 + 8, C.rotated(C.raised(C.pose_at(C.at(FLIP, "contact"), dz3 - 0.25), 0.60), [110, 0, 0]), contact={"LeftFoot": 0.0, "RightFoot": 0.0}),
        pk(i3 + 16, C.rotated(C.raised(C.pose_at(C.at(FLIP, "contact"), dz3 - 0.35), 0.62), [230, 0, 0])),
        pk(i3 + 24, C.rotated(C.raised(C.pose_at(C.at(FLIP, "recover"), dz3 - 0.30), 0.50), [330, 0, 0])),
    ]
    H.add(i3, "RightFoot", "Mid", C.chest())
    # the scissor kick at the top
    scissor = C.pose_at(C.at(SCISSOR, "contact"))
    dz4 = C.reach_dz(C.raised(scissor, 0.30), "RightFoot", C.temple(+1), dtrack, i4, 0.03, clear=0.0, arm_tol=-0.2)
    A += [
        pk(i4 - 6, C.raised(C.pose_at(C.at(SCISSOR, "windup"), dz4), 0.42)),
        pk(i4, C.raised(C.pose_at(scissor, dz4), 0.30), "snap", RightFoot={"grip": C.temple(+1), "w": 1.0}),
        pk(i4 + 8, C.raised(C.pose_at(C.at(SCISSOR, "recover"), dz4), 0.12)),
        pk(i4 + 14, C.lowered(C.pose_at(stance, dz4 * 0.8), 0.10), lift=(0.02, 0.02)),
    ]
    H.add(i4, "RightFoot", "High", C.temple(+1))
    # lands low and the drop sweep
    low = C.lowered(C.pose_at(C.at(LOW, "contact")), 0.12)
    dz5 = C.reach_dz(low, "LeftFoot", C.ankle(+1), dtrack, i5, 0.03, clear=0.0, arm_tol=-0.2)
    A += [
        pk(i5 - 10, C.lowered(C.pose_at(C.at(LOW, "start"), dz5), 0.14)),
        pk(i5 - 5, C.lowered(C.pose_at(C.at(LOW, "windup"), dz5), 0.14)),
        pk(i5, C.pose_at(low, dz5), "snap", LeftFoot={"grip": C.ankle(+1), "w": 1.0}),
        pk(i5 + 8, C.lowered(C.pose_at(C.at(LOW, "recover"), dz5), 0.10)),
    ]
    H.add(i5, "LeftFoot", "Low", C.ankle(+1))
    # springs into a front flip and the falling heel onto the floating body, lands crouched on one hand
    heel = C.pose_at(C.at(CRESCENT, "contact"))
    dz6 = C.reach_dz(C.raised(heel, 0.62), "RightFoot", C.belly(), dtrack, i6, 0.03, clear=0.0, arm_tol=-0.3)
    A += [
        pk(i6 - 24, C.lowered(C.pose_at(stance, dz6 - 0.1), 0.18), lift=(0.04, 0.04)),
        pk(i6 - 16, C.rotated(C.raised(C.pose_at(stance, dz6 - 0.05), 0.50), [-120, 0, 0]), contact={"LeftFoot": 0.0, "RightFoot": 0.0}),
        pk(i6 - 8, C.rotated(C.raised(C.pose_at(C.at(CRESCENT, "windup"), dz6), 0.62), [-250, 0, 0])),
        pk(i6, C.rotated(C.raised(C.pose_at(heel, dz6), 0.55), [-345, 0, 0]), "snap", RightFoot={"grip": C.belly(), "w": 1.0}),
        pk(i6 + 8, C.lowered(C.pose_at(stance, dz6 * 0.6), 0.34), LeftHand={"at": [-0.30, 0.04, dz6 * 0.6 + 0.35], "pole": [-0.6, 0.3, 0.6]}),
        pk(D - 4, C.lowered(stance, 0.12), lift=(0.05, 0.05)),
        pk(D, stance),
    ]
    H.add(i6, "RightFoot", "Mid", C.belly())
    A.sort(key=lambda kk: kk["f"])

    cam = [
        {"f": 0, "pos": [5.8, 3.2, -1.6], "look": [0.3, 3.2, 2.6], "fov": 38, "cut": True},
        {"f": i1 + 8, "pos": [5.0, 3.0, -0.4], "look": [0.2, 3.0, 2.6], "fov": 36},
        {"f": i1 + 12, "pos": [8.4, 2.4, 2.2], "look": [0.0, 3.0, 2.6], "fov": 36, "cut": True},
        {"f": i2 + 12, "pos": [7.8, 2.2, 2.6], "look": [0.0, 2.8, 2.8], "fov": 35},
        # low angle up the wall-run and the flip
        {"f": i2 + 16, "pos": [4.6, 1.2, 6.2], "look": [0.0, 4.6, 2.2], "fov": 40, "cut": True},
        {"f": i4 + 6, "pos": [5.4, 1.6, 6.6], "look": [0.0, 4.8, 2.2], "fov": 40},
        # wide for the sweep and the spike
        {"f": i4 + 10, "pos": [9.6, 3.0, 0.6], "look": [0.0, 2.2, 2.8], "fov": 36, "cut": True},
        {"f": i6 - 12, "pos": [8.8, 3.4, 1.2], "look": [0.0, 3.0, 2.8], "fov": 36},
        {"f": i6 - 11, "pos": [4.2, 6.8, 5.6], "look": [0.0, 2.0, 2.6], "fov": 38, "cut": True},
        {"f": i6 + 6, "pos": [4.8, 6.2, 6.0], "look": [0.0, 1.2, 3.0], "fov": 36},
        {"f": D, "pos": [10.2, 5.0, 0.8], "look": [0.0, 1.2, 3.4], "fov": 38, "ease": "out"},
    ]

    timing = tl.get("move") or {}
    startup = int(timing.get("startup") or 17)
    active = int(timing.get("active") or 3)
    recovery = int(timing.get("recovery") or 30)
    first = startup + 1
    start_keys = [
        pk(0, stance),
        # the activation: a quick crouch onto the toes, arms swept back, then the run-up and the jump kick
        pk(5, C.lowered(stance, 0.12), "out", rot_plus=[-10, 0, 0], LeftHand={"at": [-0.30, 0.95, -0.22], "pole": [-0.8, -0.2, -0.4]},
           RightHand={"at": [0.34, 0.95, -0.24], "pole": [0.8, -0.2, -0.4]}),
        pk(10, C.lowered(stance, 0.14), "smooth", rot_plus=[-12, 0, 0], LeftHand={"at": [-0.30, 0.92, -0.26], "pole": [-0.8, -0.2, -0.4]},
           RightHand={"at": [0.34, 0.92, -0.28], "pole": [0.8, -0.2, -0.4]}),
        pk(first - 5, C.pose_at(C.at(VAULT, "windup")), "in"),
        pk(first, C.pose_at(C.at(VAULT, "contact")), "snap"),
        pk(first + active + 5, C.pose_at(C.at(VAULT, "recover"))),
        pk(first + active + int(recovery * 0.6), C.pose_at(C.at(VAULT, "end"))),
        pk(first + active + recovery, stance),
    ]
    return {
        "name": "Lumi_Ultimate", "fighter": FIGHTER, "style": STYLE, "dist": home, "duration": D, "impacts": H.impacts,
        "endKind": "FaceDown", "attacker": A, "defender": Dk, "allow": ALLOW, "hits": H.hits, "strikes": H.strikes, "grips": H.grips,
        "camera": cam, "release": i6,
        "order": [("D", "LeftHand"), ("D", "RightHand"), ("D", "LeftFoot"), ("D", "RightFoot"), ("A", "LeftHand"), ("A", "RightHand")],
        "start": {"timing": (startup, active, recovery), "keys": start_keys, "tags": {"limb": "LeftFoot"},
                  "notes": "Skyline start: a crouch onto the toes with the arms swept back, then an armored running jump kick."},
        "notes": "Lumi Ultimate 'Skyline': jump kick, spinning heel, cartwheel kick, wall-run flip off the chest, scissor kick, drop sweep, falling heel.",
    }
