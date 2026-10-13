"""RHYS (karate counter-striker) Ultimate 'Last Kata' (roster beats, movesets.md 5.5):
  f0     the hit: an armored gliding reverse punch to the sternum; the opponent stops dead
  imp 1  a lead knife-hand chop down onto the collarbone; the defender's shoulder drops
  imp 2  a front snap kick into the stomach; the defender doubles over
  imp 3  a rising elbow under the chin; the head snaps up and it sways, dazed
  ...    Rhys steps back into a deep, still stance and exhales; nothing moves but the swaying defender (the camera holds
         on him)
  imp 4  one perfect stepping reverse punch to the sternum; the defender is blown off its feet and lands on its back
         (FaceUp, on its spot). Rhys holds the finished punch, then returns the fist to his hip
"""
from __future__ import annotations

import numpy as np

import twobody as T
import cinecommon as C
from cinecommon import F, pk

FIGHTER = "Rhys"
STYLE = "karate"
ROOT_HEIGHT = 4.100

LUNGE = "Strike_Rhys_LungePunch"
JAB = "Strike_Rhys_Jab"
STRAIGHT = "Strike_Rhys_StraightPunch"
SNAP = "Kick_Rhys_FrontSnap"

ALLOW = [("hand", "head", 0.05), ("hand", "spine", 0.05), ("hand", "neck", 0.05), ("foreArm", "head", 0.04),
         ("hand", "shoulders", 0.05), ("foreArm", "shoulders", 0.04), ("hand", "hips", 0.05), ("hand", "hand", 0.03),
         ("hand", "foreArm", 0.03), ("foreArm", "hand", 0.03), ("foreArm", "foreArm", 0.03), ("foreArm", "spine", 0.03),
         ("foot", "spine", 0.05), ("foot", "hips", 0.05), ("shin", "hips", 0.03), ("foreArm", "neck", 0.05), ("upperArm", "head", 0.03)]


def home_m(end_distance: float) -> float:
    return end_distance / (ROOT_HEIGHT * 0.775) * T.LEG


def edited(pose: T.Pose, **limbs) -> T.Pose:
    """A copy of a pose with limb targets / poles replaced (absolute own-LS metres)."""
    p = C.resolved(pose)
    for limb, e in limbs.items():
        if "at" in e:
            p.limbs[limb]["at"] = np.asarray(e["at"], float)
        if "pole" in e:
            p.limbs[limb]["pole"] = T.unit(e["pole"])
    return p


def build(tl: dict) -> dict:
    D = tl["duration"]
    i1, i2, i3, i4 = tl["impacts"]
    home = home_m(tl.get("endDistance", 4.6))
    T.DIST[0] = home
    stance = C.stance_of(FIGHTER)
    H = C.Hits()

    # --- defender ---------------------------------------------------------------------------------------------------
    fist = C.tip_of(T.full_joints(C.pose_at(C.at(LUNGE, "contact"))), "RightHand")
    st_d = T.point(T.full_joints(C.pose_at("HitMidHeavy@0.0")), C.sternum()[:3])
    z0 = home - st_d[2] - fist[2] - 0.02
    zc = home - 1.0

    def r(f, ref, z, ease=None, **kw):
        return pk(f, C.pose_at(ref, z), ease, **kw)

    Dk = [
        # stops dead on the reverse punch
        r(0, "HitMidHeavy@0.0", z0, rot_plus=[4, 0, 0]),
        r(10, "HitMidHeavy@0.1", (z0 + zc) * 0.5),
        r(i1 - 6, "HitMidHeavy@0.4", zc),
        # the knife-hand drops its right shoulder
        r(i1, "HitMidHeavy@0.0", zc, "snap", rot_plus=[-4, -6, -12], waist_plus=[-4, 0, -10], neck_plus=[0, 0, -6]),
        r(i1 + 10, "HitMidHeavy@0.15", zc - 0.02, rot_plus=[-6, -4, -10], waist_plus=[-4, 0, -8]),
        r(i2 - 6, "HitMidHeavy@0.5", zc - 0.01, rot_plus=[3, 0, -2]),
        # the front kick doubles it over
        r(i2, "HitMidHeavy@0.0", zc - 0.01, "snap", rot_plus=[2, 0, 0], waist_plus=[-2, 0, 0]),
        r(i2 + 4, "HitMidHeavy@0.05", zc - 0.10, rot_plus=[-4, 0, 0], waist_plus=[-4, 0, 0]),
        r(i2 + 10, "HitMidHeavy@0.15", zc - 0.12, rot_plus=[-18, 0, 0], waist_plus=[-12, 0, 0]),
        r(i3 - 6, "HitMidHeavy@0.4", zc - 0.03, rot_plus=[-4, 0, 0], waist_plus=[-4, 0, 0], neck_plus=[-6, 0, 0]),
        # the rising elbow: head snaps up, it sways dazed
        r(i3, "HitHighHeavy@0.0", zc - 0.03, "snap", neck_plus=[34, 0, 0], waist_plus=[10, 0, 0]),
        r(i3 + 8, "HitHighHeavy@0.12", zc - 0.07, neck_plus=[22, 0, 0], waist_plus=[8, 0, 0]),
        r(i3 + 22, "Stagger@0.3", zc - 0.08, rot_plus=[0, 0, 5], neck_plus=[6, 0, 6]),
        r(i3 + 40, "Stagger@0.45", zc - 0.07, rot_plus=[-2, 0, -5], neck_plus=[2, 0, -6]),
        r(i3 + 58, "Stagger@0.55", zc - 0.06, rot_plus=[1, 0, 4], neck_plus=[4, 0, 5]),
        r(i4 - 6, "Stagger@0.6", zc - 0.05, rot_plus=[0, 0, -2]),
        # the last kata: blown off its feet onto its back
        r(i4, "HitMidHeavy@0.0", zc - 0.05, "snap", rot_plus=[8, 0, 0]),
    ]
    Dk += C.flight(i4 + 1, i4 + 15, zc - 0.05, "FaceUp", apex=0.82)
    Dk.append(F(D, **{"from": C.end_pose("FaceUp"), "ground": 1.0}))
    dtrack = T.Track(Dk, "D")

    # --- attacker ---------------------------------------------------------------------------------------------------
    A = [pk(0, C.pose_at(C.at(LUNGE, "contact"))), pk(8, C.pose_at(C.at(LUNGE, "follow")))]
    # the knife-hand: the open lead hand rises high, then chops down onto the right collarbone
    _, b1 = C.strike_beat(dtrack, i1, JAB, "LeftHand", C.collar(+1), stance, start_off=12, windup_off=6, recover_off=8, guard_after=8,
                          arm_tol=-0.14, clear=0.0, extra={"windup": {"LeftHand": {"at": [-0.08, 1.92, 0.22], "pole": [-0.6, 0.2, -0.6]}},
                                                "limb": {"pole": [-0.75, -0.45, 0.1]}})
    A += b1
    H.add(i1, "LeftHand", "High", C.collar(+1))
    # the front snap kick
    _, b2 = C.strike_beat(dtrack, i2, SNAP, "LeftFoot", C.belly(), stance, start_off=12, windup_off=6, recover_off=8, guard_after=8)
    A += b2
    H.add(i2, "LeftFoot", "Mid", C.belly())
    # the rising elbow: the right forearm folds up by the ear and the point of the elbow rises under the chin
    elbow_contact = edited(C.pose_at(C.at(STRAIGHT, "contact")), RightHand={"at": [0.28, 1.80, 0.24], "pole": [0.15, -0.5, 1.0]})
    elbow_windup = edited(C.pose_at(C.at(STRAIGHT, "windup")), RightHand={"at": [0.24, 1.10, 0.06], "pole": [0.3, -0.6, 0.8]})
    dz3 = C.reach_dz(elbow_contact, "RightHand", C.chin(), dtrack, i3, 0.03, clear=-0.01, arm_tol=-0.3, dx=-0.12, joint="elbowR")
    elbow_contact, elbow_windup = C.pose_at(elbow_contact, 0.0, -0.12), C.pose_at(elbow_windup, 0.0, -0.12)
    A += [
        pk(i3 - 16, C.pose_at(stance, dz3), lift=(0.05, 0.05)),
        pk(i3 - 7, C.pose_at(elbow_windup, dz3), pelvis_plus=[0.0, -0.06, 0.0]),
        pk(i3, C.pose_at(elbow_contact, dz3), "snap", pelvis_plus=[0.0, 0.04, 0.0], rot_plus=[4, 6, 0]),
        pk(i3 + 8, C.pose_at(elbow_contact, dz3), pelvis_plus=[0.0, 0.02, 0.0]),
    ]
    H.add(i3, "RightElbow", "High", C.chin(), grip=False)
    # a long, still breath in a deep stance (steps back from the dazed defender)
    deep = C.lowered(stance, 0.06)
    A += [
        pk(i3 + 16, C.pose_at(stance, dz3 * 0.5), lift=(0.05, 0.05)),
        pk(i3 + 24, C.pose_at(deep, -0.04), lift=(0.04, 0.05)),
        pk(i3 + 44, C.pose_at(deep, -0.04), rot_plus=[3, 0, 0], waist_plus=[3, 0, 0]),
        pk(i4 - 22, C.pose_at(deep, -0.04), rot_plus=[-1, 0, 0]),
    ]
    # one perfect stepping reverse punch, held, then the fist back to the hip
    _, b4 = C.strike_beat(dtrack, i4, LUNGE, "RightHand", C.sternum(), stance, start_off=12, windup_off=6, recover_off=12, guard_after=0, clear=0.01)
    A += b4[1:]
    H.add(i4, "RightHand", "Mid", C.sternum())
    A += [pk(D - 3, stance, lift=(0.04, 0.04)), pk(D, stance)]
    A.sort(key=lambda kk: kk["f"])

    cam = [
        {"f": 0, "pos": [5.2, 3.4, -1.4], "look": [0.3, 3.4, 2.6], "fov": 38, "cut": True},
        {"f": i1 - 14, "pos": [4.6, 3.2, -0.6], "look": [0.2, 3.6, 2.6], "fov": 36},
        {"f": i1 - 13, "pos": [6.8, 3.0, 3.6], "look": [0.0, 3.8, 2.2], "fov": 35, "cut": True},
        {"f": i2 + 10, "pos": [7.4, 2.6, 2.6], "look": [0.0, 3.0, 2.2], "fov": 34},
        # low side angle for the rising elbow (both in profile: from behind the defender he hid the attacker)
        {"f": i3 - 14, "pos": [6.2, 1.3, 2.2], "look": [0.0, 4.0, 1.9], "fov": 38, "cut": True},
        {"f": i3 + 10, "pos": [6.6, 1.5, 2.6], "look": [0.0, 3.9, 2.0], "fov": 38},
        # holds on him through the breath
        {"f": i3 + 14, "pos": [2.8, 4.2, 3.0], "look": [0.1, 4.4, 0.2], "fov": 30, "cut": True},
        {"f": i4 - 14, "pos": [2.5, 4.1, 2.6], "look": [0.1, 4.3, 0.3], "fov": 28},
        # the punch in profile, then out over the fall
        {"f": i4 - 13, "pos": [8.6, 2.8, 1.2], "look": [0.0, 3.2, 2.6], "fov": 34, "cut": True},
        {"f": i4 + 2, "pos": [8.2, 2.7, 1.6], "look": [0.0, 3.2, 2.8], "fov": 32},
        {"f": D, "pos": [10.6, 5.0, 0.6], "look": [0.0, 1.6, 3.6], "fov": 38, "ease": "out"},
    ]

    timing = tl.get("move") or {}
    startup = int(timing.get("startup") or 19)
    active = int(timing.get("active") or 3)
    recovery = int(timing.get("recovery") or 28)
    first = startup + 1
    start_keys = [
        pk(0, stance),
        # the activation: a slow, deliberate breath in (fists drawn to the hips), held under the flash
        pk(5, stance, "out", pelvis_plus=[0.0, -0.04, -0.03], rot_plus=[4, 0, 0], neck_plus=[6, 0, 0],
           LeftHand={"at": [-0.26, 1.02, 0.10], "pole": [-0.8, -0.3, -0.5]}, RightHand={"at": [0.32, 1.02, 0.02], "pole": [0.8, -0.3, -0.5]}),
        pk(10, stance, "smooth", pelvis_plus=[0.0, -0.05, -0.04], rot_plus=[5, 0, 0], neck_plus=[8, 0, 0],
           LeftHand={"at": [-0.26, 1.02, 0.10], "pole": [-0.8, -0.3, -0.5]}, RightHand={"at": [0.32, 1.02, 0.02], "pole": [0.8, -0.3, -0.5]}),
        pk(first - 6, C.pose_at(C.at(LUNGE, "windup")), "in"),
        pk(first, C.pose_at(C.at(LUNGE, "contact")), "snap"),
        pk(first + active + 4, C.pose_at(C.at(LUNGE, "follow"))),
        pk(first + active + int(recovery * 0.6), C.pose_at(C.at(LUNGE, "recover"))),
        pk(first + active + recovery, stance),
    ]
    return {
        "name": "Rhys_Ultimate", "fighter": FIGHTER, "style": STYLE, "dist": home, "duration": D, "impacts": H.impacts,
        "endKind": "FaceUp", "attacker": A, "defender": Dk, "allow": ALLOW, "hits": H.hits, "strikes": H.strikes, "grips": H.grips,
        "camera": cam, "release": i4,
        "order": [("D", "LeftHand"), ("D", "RightHand"), ("D", "LeftFoot"), ("D", "RightFoot"), ("A", "LeftHand"), ("A", "RightHand")],
        "start": {"timing": (startup, active, recovery), "keys": start_keys, "tags": {"limb": "RightHand"},
                  "notes": "Last Kata start: a deliberate breath with the fists drawn to the hips, then an armored gliding reverse punch."},
        "notes": "Rhys Ultimate 'Last Kata': gliding reverse punch, knife-hand, front snap kick, rising elbow, a still breath, the last reverse punch.",
    }
