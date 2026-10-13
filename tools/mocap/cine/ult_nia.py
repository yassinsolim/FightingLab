"""NIA (kung-fu whirlwind) Ultimate 'Monsoon' (roster beats, movesets.md 5.6):
  f0     the hit: an armored spinning palm strike to the chest; the opponent is rocked back and Nia flows in close
  imp 1  a double palm strike to the chest (both palms together); its torso is pushed back
  imp 2  she turns and a spinning back-hand chop lands on the side of the neck; its head jerks sideways
  imp 3  she drops into a low spinning sweep; its legs are taken and it floats up, horizontal
  imp 4  she corkscrews up with a rising spiral kick under the floating body, lifting it higher
  imp 5  in the air at the top, a whirlwind kick (both legs whipping in one turn) across the floating body
  imp 6  she lands, sinks low and blasts a focused two-palm push into the falling defender; it slides across the floor
         onto its back (FaceUp, on its spot). Nia finishes in a low stance, palms forward, breathing out
"""
from __future__ import annotations

import numpy as np

import twobody as T
import cinecommon as C
from cinecommon import F, pk

FIGHTER = "Nia"
STYLE = "kungfu"
ROOT_HEIGHT = 3.933

PALM = "Strike_Nia_PalmThrust"
BACKFIST = "Strike_Nia_Backfist"
SWEEP = "Kick_Nia_LowSweep"
RISING = "Kick_Nia_RisingTornado"
WHIRL = "Kick_Nia_ButterflyKick"

ALLOW = [("hand", "spine", 0.05), ("hand", "head", 0.05), ("hand", "neck", 0.06), ("foreArm", "neck", 0.05), ("foreArm", "head", 0.04),
         ("hand", "shoulders", 0.05), ("foreArm", "shoulders", 0.04), ("foreArm", "spine", 0.04), ("foot", "spine", 0.06),
         ("foot", "hips", 0.06), ("shin", "spine", 0.05), ("shin", "hips", 0.05), ("foot", "thigh", 0.05), ("foot", "shin", 0.05),
         ("shin", "shin", 0.04), ("foot", "foot", 0.04), ("hand", "hand", 0.03), ("foreArm", "foreArm", 0.03), ("hand", "hips", 0.05)]


def home_m(end_distance: float) -> float:
    return end_distance / (ROOT_HEIGHT * 0.775) * T.LEG


def build(tl: dict) -> dict:
    D = tl["duration"]
    i1, i2, i3, i4, i5, i6 = tl["impacts"]
    home = home_m(tl.get("endDistance", 4.6))
    T.DIST[0] = home
    stance = C.stance_of(FIGHTER)
    H = C.Hits()

    # --- defender ---------------------------------------------------------------------------------------------------
    palm = C.tip_of(T.full_joints(C.pose_at(C.at(PALM, "contact"))), "RightHand")
    st_d = T.point(T.full_joints(C.pose_at("HitMidHeavy@0.0")), C.sternum()[:3])
    z0 = home - st_d[2] - palm[2] - 0.02
    zc = home - 1.0

    def r(f, ref, z, ease=None, **kw):
        return pk(f, C.pose_at(ref, z), ease, **kw)

    zf = zc - 0.28      # where it floats (a little further out: the swept legs fly up toward her)
    yf = -62.0          # it floats on a diagonal across the fight line
    Dk = [
        r(0, "HitMidHeavy@0.0", z0, rot_plus=[6, 0, 0]),
        r(10, "HitMidHeavy@0.15", (z0 + zc) * 0.5),
        r(i1 - 6, "HitMidHeavy@0.45", zc + 0.02),
        # the double palm pushes the torso back
        r(i1, "HitMidHeavy@0.0", zc + 0.02, "snap", rot_plus=[10, 0, 0], waist_plus=[8, 0, 0]),
        r(i1 + 10, "HitMidHeavy@0.15", zc - 0.04, rot_plus=[6, 0, 0], waist_plus=[6, 0, 0], lift=(0.04, 0.0)),
        r(i2 - 8, "HitMidHeavy@0.5", zc - 0.03),
        # the spinning chop on the left side of the neck: the head jerks to its right
        r(i2, "HitHighHeavy@0.0", zc - 0.03, "snap", neck_plus=[4, -30, -14], waist_plus=[0, -8, -6]),
        r(i2 + 10, "HitHighHeavy@0.15", zc - 0.05, neck_plus=[2, -20, -10], waist_plus=[0, -6, -4]),
        r(i3 - 8, "Stagger@0.4", zc - 0.04),
        # the sweep takes its legs: it floats up on its back
        r(i3, "HitLowHeavy@0.0", zc - 0.04, "snap"),
        C.floating(i3 + 8, 0.62, zf + 0.12, pitch=55, yaw=yf * 0.6, legs=0.05),
        C.floating(i3 + 18, 0.82, zf, pitch=82, yaw=yf),
        C.floating(i4 - 6, 0.74, zf, pitch=88, yaw=yf, ease="in"),
        # the rising spiral kick under its back lifts it higher
        C.floating(i4, 0.76, zf, pitch=86, yaw=yf, ease="snap"),
        C.floating(i4 + 14, 1.20, zf - 0.02, pitch=96, yaw=yf - 12, legs=0.08),
        C.floating(i5 - 10, 1.52, zf - 0.03, pitch=100, yaw=yf - 22),
        # the whirlwind kick across it at the top
        C.floating(i5, 1.55, zf - 0.03, pitch=96, yaw=yf - 26, roll=12, ease="snap"),
        C.floating(i5 + 16, 1.25, zf, pitch=90, yaw=yf * 0.6, roll=4),
        C.floating(i6 - 18, 0.62, zf + 0.04, pitch=86, yaw=yf * 0.15, ease="in"),
        # lands on its back as the two palms hit, slides onto its spot
        pk(i6 - 4, C.pose_at(C.end_pose("FaceUp"), zf + 0.10), "in", ground=1.0),
        pk(i6, C.pose_at(C.end_pose("FaceUp"), zf + 0.08), "snap", ground=1.0),
        pk(i6 + 12, C.end_pose("FaceUp"), "out", ground=1.0),
        pk(D, C.end_pose("FaceUp"), ground=1.0),
    ]
    dtrack = T.Track(Dk, "D")

    # --- attacker ---------------------------------------------------------------------------------------------------
    A = [pk(0, C.pose_at(C.at(PALM, "contact"))), pk(8, C.pose_at(C.at(PALM, "follow")))]
    # the double palm: both heels of the hands together on the chest
    _, b1 = C.strike_beat(dtrack, i1, PALM, "RightHand", C.sternum(dx=-0.06), stance, start_off=11, windup_off=6, recover_off=8, guard_after=6,
                          extra={"contact": {"LeftHand": {"grip": C.sternum(dx=0.07, dy=0.02), "w": 1.0, "pole": [-0.6, -0.8, 0.0]}},
                                 "windup": {"LeftHand": {"at": [-0.16, 1.18, 0.20], "pole": [-0.7, -0.7, 0.0]}}})
    A += b1
    H.add(i1, "RightHand", "Mid", C.sternum(dx=-0.06))
    # she turns (a full spin on the spot) into the back-hand chop
    dz2 = C.reach_dz(C.at(BACKFIST, "contact"), "RightHand", C.neck_side(-1), dtrack, i2, 0.03, clear=0.02, arm_tol=-0.08)
    A += [
        pk(i2 - 22, C.pose_at(stance, dz2), lift=(0.04, 0.04)),
        pk(i2 - 16, C.yawed(C.pose_at(stance, dz2), -120), lift=(0.05, 0.05)),
        pk(i2 - 10, C.yawed(C.pose_at(C.at(BACKFIST, "start"), dz2), -240), lift=(0.05, 0.05)),
        pk(i2 - 5, C.pose_at(C.at(BACKFIST, "windup"), dz2)),
        pk(i2, C.pose_at(C.at(BACKFIST, "contact"), dz2), "snap", RightHand={"grip": C.neck_side(-1), "w": 1.0}),
        pk(i2 + 8, C.pose_at(C.at(BACKFIST, "recover"), dz2)),
    ]
    H.add(i2, "RightHand", "High", C.neck_side(-1))
    # the low spinning sweep
    _, b3 = C.strike_beat(dtrack, i3, SWEEP, "RightFoot", C.ankle(-1), stance, start_off=14, windup_off=7, recover_off=8, guard_after=0,
                          clear=0.0, arm_tol=-0.2)
    A += b3
    H.add(i3, "RightFoot", "Low", C.ankle(-1))
    # corkscrews up with the rising spiral kick under its back
    dz4 = C.reach_dz(C.at(RISING, "contact"), "RightFoot", C.lower_back(), dtrack, i4, 0.04, clear=0.0, arm_tol=-0.3)
    A += [
        pk(i3 + 14, C.pose_at(C.at(SWEEP, "end"), dz4), lift=(0.03, 0.03)),
        pk(i4 - 12, C.pose_at(C.at(RISING, "start"), dz4)),
        pk(i4 - 6, C.pose_at(C.at(RISING, "windup"), dz4)),
        pk(i4, C.pose_at(C.at(RISING, "contact"), dz4), "snap", RightFoot={"grip": C.lower_back(), "w": 1.0}),
        pk(i4 + 10, C.pose_at(C.at(RISING, "recover"), dz4)),
    ]
    H.add(i4, "RightFoot", "Mid", C.lower_back())
    # up into the air for the whirlwind kick across the floating body, then down
    whirl = C.pose_at(C.at(WHIRL, "contact"))
    lift = 0.42
    dz5 = C.reach_dz(C.raised(whirl, lift), "RightFoot", C.chest(), dtrack, i5, 0.04, clear=0.0, arm_tol=-0.3)
    A += [
        pk(i5 - 26, C.pose_at(stance, dz5), lift=(0.03, 0.03)),
        pk(i5 - 16, C.lowered(C.pose_at(C.at(WHIRL, "start"), dz5), 0.10)),
        pk(i5 - 8, C.raised(C.pose_at(C.at(WHIRL, "windup"), dz5), lift * 0.8), contact={"LeftFoot": 0.0, "RightFoot": 0.0}),
        pk(i5, C.raised(C.pose_at(whirl, dz5), lift), "snap", RightFoot={"grip": C.chest(), "w": 1.0}),
        pk(i5 + 10, C.raised(C.pose_at(C.at(WHIRL, "recover"), dz5), lift * 0.4)),
        pk(i5 + 18, C.lowered(C.pose_at(stance, dz5 * 0.6), 0.12), lift=(0.02, 0.02)),
    ]
    H.add(i5, "RightFoot", "High", C.chest())
    # lands, sinks low, the two-palm push into the falling body
    low = C.lowered(stance, 0.30)
    dz6 = C.reach_dz(C.lowered(C.pose_at(C.at(PALM, "contact")), 0.46), "RightHand", C.belly(), dtrack, i6, 0.03, clear=0.0, arm_tol=-0.2)
    A += [
        pk(i6 - 14, C.pose_at(low, dz6), lift=(0.04, 0.04)),
        pk(i6 - 6, C.lowered(C.pose_at(C.at(PALM, "windup"), dz6), 0.40), rot_plus=[-12, 0, 0]),
        pk(i6, C.lowered(C.pose_at(C.at(PALM, "contact"), dz6), 0.46), "snap", rot_plus=[-24, 0, 0],
           RightHand={"grip": C.belly(dx=-0.06), "w": 1.0}, LeftHand={"grip": C.belly(dx=0.06), "w": 1.0}),
        pk(i6 + 8, C.lowered(C.pose_at(C.at(PALM, "contact"), dz6), 0.40), rot_plus=[-18, 0, 0]),
        # low stance, palms forward, breathing out (back onto her spot)
        pk(D - 4, C.lowered(stance, 0.08), lift=(0.04, 0.04), rot_plus=[3, 0, 0]),
        pk(D, stance),
    ]
    H.add(i6, "RightHand", "Mid", C.belly(dx=-0.06))
    A.sort(key=lambda kk: kk["f"])

    cam = [
        {"f": 0, "pos": [5.6, 3.2, -1.6], "look": [0.3, 3.3, 2.6], "fov": 38, "cut": True},
        {"f": i1 + 10, "pos": [4.8, 3.0, -0.4], "look": [0.2, 3.3, 2.6], "fov": 36},
        # her face as she spins into the chop
        {"f": i1 + 14, "pos": [-2.6, 4.4, 7.2], "look": [0.2, 4.0, 1.0], "fov": 35, "cut": True},
        {"f": i2 + 10, "pos": [-3.2, 4.2, 6.8], "look": [0.2, 3.9, 1.2], "fov": 35},
        # low wide for the sweep and the float
        {"f": i2 + 14, "pos": [8.6, 1.4, 1.6], "look": [0.0, 2.2, 2.8], "fov": 36, "cut": True},
        {"f": i4 + 6, "pos": [8.0, 1.6, 2.2], "look": [0.0, 3.2, 3.0], "fov": 36},
        # up with them for the whirlwind
        {"f": i4 + 10, "pos": [6.4, 6.6, 0.8], "look": [0.0, 4.4, 3.0], "fov": 36, "cut": True},
        {"f": i5 + 8, "pos": [6.8, 6.2, 1.6], "look": [0.0, 4.0, 3.2], "fov": 35},
        # the push and the slide, low three-quarter, then out
        {"f": i5 + 12, "pos": [5.6, 1.6, 6.4], "look": [0.0, 1.8, 2.8], "fov": 36, "cut": True},
        {"f": i6 + 4, "pos": [6.0, 2.2, 6.8], "look": [0.0, 1.6, 3.2], "fov": 34},
        {"f": D, "pos": [10.6, 5.0, 0.6], "look": [0.0, 1.6, 3.6], "fov": 38, "ease": "out"},
    ]

    timing = tl.get("move") or {}
    startup = int(timing.get("startup") or 18)
    active = int(timing.get("active") or 3)
    recovery = int(timing.get("recovery") or 29)
    first = startup + 1
    start_keys = [
        pk(0, stance),
        # the activation: palms circle in and press together in front of the chest, a slow breath (held under the flash)
        pk(5, stance, "out", pelvis_plus=[0.0, -0.04, -0.02], rot_plus=[3, 0, 0],
           LeftHand={"at": [-0.04, 1.22, 0.24], "pole": [-0.8, -0.6, 0.0]}, RightHand={"at": [0.06, 1.22, 0.24], "pole": [0.8, -0.6, 0.0]}),
        pk(10, stance, "smooth", pelvis_plus=[0.0, -0.06, -0.02], rot_plus=[4, 0, 0],
           LeftHand={"at": [-0.04, 1.24, 0.24], "pole": [-0.8, -0.6, 0.0]}, RightHand={"at": [0.06, 1.24, 0.24], "pole": [0.8, -0.6, 0.0]}),
        pk(first - 8, C.yawed(C.pose_at(C.at(PALM, "start")), -180), lift=(0.04, 0.04)),
        pk(first - 4, C.pose_at(C.at(PALM, "windup"))),
        pk(first, C.pose_at(C.at(PALM, "contact")), "snap"),
        pk(first + active + 4, C.pose_at(C.at(PALM, "follow"))),
        pk(first + active + int(recovery * 0.6), C.pose_at(C.at(PALM, "recover"))),
        pk(first + active + recovery, stance),
    ]
    return {
        "name": "Nia_Ultimate", "fighter": FIGHTER, "style": STYLE, "dist": home, "duration": D, "impacts": H.impacts,
        "endKind": "FaceUp", "attacker": A, "defender": Dk, "allow": ALLOW, "hits": H.hits, "strikes": H.strikes, "grips": H.grips,
        "camera": cam, "release": i6,
        "order": [("D", "LeftHand"), ("D", "RightHand"), ("D", "LeftFoot"), ("D", "RightFoot"), ("A", "LeftHand"), ("A", "RightHand")],
        "start": {"timing": (startup, active, recovery), "keys": start_keys, "tags": {"limb": "RightHand"},
                  "notes": "Monsoon start: palms pressed together with a slow breath, then an armored spinning palm strike."},
        "notes": "Nia Ultimate 'Monsoon': spinning palm, double palm, spinning chop, low sweep, rising spiral kick, whirlwind kick, two-palm push.",
    }
