"""SIERRA (kickboxer) Ultimate 'Eight Limbs' (roster beats, movesets.md 5.2):
  f0     the hit: an armored long teep into the stomach folds the opponent; Sierra steps in behind it
  imp 1  lead (left) body kick into the liver; the defender bends sideways toward the kick
  imp 2  she clinches (both hands behind its head) and drives a rising knee into its chest; the head is pulled onto it
  imp 3  the second knee, to the chin; the head snaps back up
  imp 4  she releases the clinch with a slashing horizontal elbow across the brow; it staggers back, turning away
  ...    two quick steps back to kicking range, a hop-switch of the feet (Southpaw) and a breath
  imp 5  a full-power switch head kick (the left leg, from Southpaw); the defender is spun off its feet and lands on its
         back (FaceUp, on its spot). Sierra finishes in her bladed guard
"""
from __future__ import annotations

import numpy as np

import twobody as T
import cinecommon as C
from cinecommon import F, pk

FIGHTER = "Sierra"
STYLE = "kickboxer"
ROOT_HEIGHT = 4.059

TEEP = "Kick_Sierra_Teep"
BODYKICK = "Kick_Sierra_AngleKick"
KNEE = "Kick_Sierra_KneeStrike"
CROSS = "Strike_Sierra_Cross"
HEADKICK = "Kick_Sierra_HighRoundhouse"

ALLOW = [("hand", "head", 0.05), ("hand", "neck", 0.06), ("foreArm", "head", 0.05), ("foreArm", "neck", 0.06), ("hand", "shoulders", 0.05),
         ("foreArm", "shoulders", 0.05), ("upperArm", "shoulders", 0.03), ("hand", "spine", 0.05), ("foreArm", "spine", 0.04),
         ("thigh", "spine", 0.06), ("shin", "spine", 0.05), ("thigh", "hips", 0.05), ("foot", "spine", 0.05), ("foot", "hips", 0.05),
         ("foot", "head", 0.05), ("shin", "head", 0.04), ("head", "head", 0.03), ("hand", "hand", 0.03), ("foreArm", "foreArm", 0.03),
         ("upperArm", "upperArm", 0.03), ("thigh", "thigh", 0.03)]


def home_m(end_distance: float) -> float:
    return end_distance / (ROOT_HEIGHT * 0.775) * T.LEG


def build(tl: dict) -> dict:
    D = tl["duration"]
    i1, i2, i3, i4, i5 = tl["impacts"]
    home = home_m(tl.get("endDistance", 4.6))
    T.DIST[0] = home
    stance = C.stance_of(FIGHTER)
    south = C.mirrored(stance)
    H = C.Hits()

    # --- defender ---------------------------------------------------------------------------------------------------
    foot = C.tip_of(T.full_joints(C.pose_at(C.at(TEEP, "contact"))), "LeftFoot")
    belly_d = T.point(T.full_joints(C.pose_at("HitMidHeavy@0.0")), C.belly()[:3])
    z0 = home - belly_d[2] - foot[2] - 0.03
    zc = home - 1.05            # body-kick range
    zk = home - 0.78            # the clinch: pulled in close

    def r(f, ref, z, ease=None, **kw):
        return pk(f, C.pose_at(ref, z), ease, **kw)

    Dk = [
        # the teep folds it
        r(0, "HitMidHeavy@0.0", z0),
        r(10, "HitMidHeavy@0.15", z0 - 0.03, rot_plus=[-6, 0, 0]),
        r(i1 - 8, "HitMidHeavy@0.45", zc, rot_plus=[2, 0, 0]),
        # the body kick on its right side: it bends toward the kick
        r(i1, "HitMidHeavy@0.0", zc, "snap", rot_plus=[0, -8, -12], waist_plus=[-4, -6, -14]),
        r(i1 + 10, "HitMidHeavy@0.15", zc - 0.03, rot_plus=[-4, -6, -14], waist_plus=[-6, -6, -14]),
        # pulled into the clinch, head drawn down
        r(i2 - 14, "HitMidHeavy@0.3", (zc + zk) * 0.5, rot_plus=[-10, 0, -4], neck_plus=[-10, 0, 0]),
        r(i2 - 4, "HitMidHeavy@0.3", zk, rot_plus=[-28, 0, 0], waist_plus=[-14, 0, 0], neck_plus=[-14, 0, 0]),
        # knee 1 into the chest
        r(i2, "HitMidHeavy@0.0", zk, "snap", rot_plus=[-24, 0, 0], waist_plus=[-10, 0, 0], neck_plus=[-12, 0, 0]),
        r(i2 + 10, "HitMidHeavy@0.12", zk - 0.02, rot_plus=[-34, 0, 0], waist_plus=[-16, 0, 0], neck_plus=[-14, 0, 0]),
        r(i3 - 6, "HitMidHeavy@0.25", zk - 0.01, rot_plus=[-44, 0, 0], waist_plus=[-20, 0, 0], neck_plus=[-12, 0, 0]),
        # knee 2 to the chin: the head snaps back up
        r(i3, "HitHighHeavy@0.0", zk - 0.01, "snap", rot_plus=[-30, 0, 0], neck_plus=[30, 0, 0], waist_plus=[-6, 0, 0]),
        r(i3 + 10, "HitHighHeavy@0.12", zk - 0.04, neck_plus=[18, 0, 0]),
        r(i4 - 6, "HitHighHeavy@0.45", zk - 0.03),
        # the elbow across the brow: it staggers back, turning away
        r(i4, "HitHighHeavy@0.0", zk - 0.03, "snap", neck_plus=[8, 26, 6], waist_plus=[0, 10, 0]),
        pk(i4 + 10, C.yawed(C.pose_at("HitHighHeavy@0.15", zk - 0.12), 18), lift=(0.04, 0.04)),
        pk(i4 + 26, C.yawed(C.pose_at("Stagger@0.35", zc - 0.08), 26), lift=(0.04, 0.03)),
        pk(i5 - 16, C.yawed(C.pose_at("Stagger@0.55", zc - 0.06), 14)),
        pk(i5 - 4, C.yawed(C.pose_at("Stagger@0.65", zc - 0.05), 6)),
        # the head kick on its right temple spins it off its feet
        r(i5, "HitHighHeavy@0.0", zc - 0.05, "snap", neck_plus=[6, 34, 10], rot_plus=[0, 10, 6]),
    ]
    Dk += C.flight(i5 + 1, i5 + 18, zc - 0.05, "FaceUp", yaw_from=10, yaw_end=360, apex=0.95)
    Dk.append(F(D, **{"from": C.end_pose("FaceUp"), "ground": 1.0}))
    dtrack = T.Track(Dk, "D")

    # --- attacker ---------------------------------------------------------------------------------------------------
    A = [pk(0, C.pose_at(C.at(TEEP, "contact"))), pk(8, C.pose_at(C.at(TEEP, "follow"))), pk(16, C.pose_at(C.at(TEEP, "end")))]
    # lead body kick into the liver
    _, b1 = C.strike_beat(dtrack, i1, BODYKICK, "LeftFoot", C.liver(+1), stance, start_off=12, windup_off=6, recover_off=9, guard_after=8, arm_tol=-0.06)
    A += b1[1:]
    H.add(i1, "LeftFoot", "Mid", C.liver(+1))
    # the clinch: both hands behind the head, then two knees
    nape_l, nape_r = C.nape(dx=0.05, dy=0.02), C.nape(dx=-0.05, dy=0.02)
    clinch_hands = {"LeftHand": {"grip": nape_l, "w": 1.0, "pole": [-0.6, -0.7, 0.2]}, "RightHand": {"grip": nape_r, "w": 1.0, "pole": [0.6, -0.7, 0.2]}}
    knee_pose = C.pose_at(C.at(KNEE, "contact"))
    # the hip ends ~0.32 m behind the target; the knee itself is put on the target (twobody knee target)
    dzk = C.reach_dz(knee_pose, "LeftFoot", C.sternum(dy=-0.06), dtrack, i2, 0.32, clear=-0.1, arm_tol=-0.4, joint="hipL")
    dzk2 = C.reach_dz(knee_pose, "LeftFoot", C.chin(), dtrack, i3, 0.30, clear=-0.1, arm_tol=-0.4, joint="hipL")
    knee1 = {"LeftFoot": {"knee": C.sternum(dy=-0.06), "kw": 1.0, "shin": [0.05, -0.75, -0.66]}}
    knee2 = {"LeftFoot": {"knee": C.chin(), "kw": 1.0, "shin": [0.05, -0.85, -0.52]}}
    A += [
        pk(i2 - 18, C.pose_at(stance, dzk - 0.05), lift=(0.05, 0.05)),
        pk(i2 - 12, C.pose_at(stance, dzk), lift=(0.04, 0.0), **clinch_hands),
        pk(i2 - 6, C.pose_at(C.at(KNEE, "windup"), dzk), **clinch_hands),
        pk(i2, C.pose_at(knee_pose, dzk), "snap", **clinch_hands, **knee1),
        pk(i2 + 9, C.pose_at(C.at(KNEE, "recover"), dzk), **clinch_hands),
        pk(i3 - 14, C.pose_at(stance, dzk2), lift=(0.03, 0.0), **clinch_hands),
        pk(i3 - 6, C.pose_at(C.at(KNEE, "windup"), dzk2), **clinch_hands),
        pk(i3, C.pose_at(knee_pose, dzk2), "snap", **clinch_hands, **knee2),
        pk(i3 + 9, C.pose_at(C.at(KNEE, "recover"), dzk2), **clinch_hands),
    ]
    H.add(i2, "LeftKnee", "Mid", C.sternum(dy=-0.06), grip=False)
    H.add(i3, "LeftKnee", "High", C.chin(), grip=False)
    # the slashing elbow across the brow (the right arm folded, the point of the elbow slicing left-to-right)
    elbow_c = C.resolved(C.pose_at(C.at(CROSS, "windup")))
    elbow_c.limbs["RightHand"]["at"] = np.array([-0.30, 1.58, 0.30])
    elbow_c.limbs["RightHand"]["pole"] = T.unit([0.6, 0.1, 0.8])
    elbow_c.q["root"] = T.qn(T.qmul(T.eq([0, 34, 0]), elbow_c.q["root"]))
    elbow_w = C.resolved(C.pose_at(C.at(CROSS, "windup")))
    elbow_w.limbs["RightHand"]["at"] = np.array([0.34, 1.58, 0.10])
    elbow_w.limbs["RightHand"]["pole"] = T.unit([0.9, 0.1, -0.2])
    dze = C.reach_dz(elbow_c, "RightHand", C.face(dy=0.05), dtrack, i4, 0.03, clear=-0.04, arm_tol=-0.3, joint="elbowR")
    A += [
        pk(i4 - 12, C.pose_at(stance, dze), lift=(0.03, 0.03)),
        pk(i4 - 6, C.pose_at(elbow_w, dze), rot_plus=[0, -14, 0]),
        pk(i4, C.pose_at(elbow_c, dze), "snap"),
        pk(i4 + 8, C.pose_at(elbow_c, dze), rot_plus=[0, 8, 0]),
    ]
    H.add(i4, "RightElbow", "High", C.face(dy=0.05), grip=False)
    # two quick steps back to kicking range, the hop-switch into Southpaw and a breath
    head_contact = C.mirrored(C.pose_at(C.at(HEADKICK, "contact")))
    dzh = C.reach_dz(head_contact, "RightFoot", C.temple(+1), dtrack, i5, 0.03, clear=0.02, arm_tol=-0.1)
    A += [
        pk(i4 + 18, C.pose_at(stance, dze - 0.18), lift=(0.06, 0.06)),
        pk(i4 + 30, C.pose_at(stance, dzh - 0.12), lift=(0.06, 0.06)),
        pk(i4 + 40, C.pose_at(stance, dzh - 0.10), pelvis_plus=[0.0, 0.03, 0.0], lift=(0.05, 0.05)),
        pk(i4 + 46, C.pose_at(south, dzh - 0.06), lift=(0.06, 0.06)),
        pk(i5 - 20, C.pose_at(south, dzh - 0.04), rot_plus=[2, 0, 0]),
        pk(i5 - 12, C.pose_at(C.mirrored(C.pose_at(C.at(HEADKICK, "start"))), dzh)),
        pk(i5 - 6, C.pose_at(C.mirrored(C.pose_at(C.at(HEADKICK, "windup"))), dzh)),
        pk(i5, C.pose_at(head_contact, dzh), "snap", RightFoot={"grip": C.temple(+1), "w": 1.0}),
        pk(i5 + 8, C.pose_at(C.mirrored(C.pose_at(C.at(HEADKICK, "recover"))), dzh)),
        pk(i5 + 18, C.pose_at(south, dzh * 0.5), lift=(0.05, 0.05)),
        # back into her own (orthodox) bladed guard on her spot
        pk(D - 4, stance, lift=(0.06, 0.06)),
        pk(D, stance),
    ]
    H.add(i5, "RightFoot", "High", C.temple(+1))
    A.sort(key=lambda kk: kk["f"])

    cam = [
        {"f": 0, "pos": [6.0, 3.0, -1.8], "look": [0.4, 3.0, 2.8], "fov": 38, "cut": True},
        {"f": i1 + 8, "pos": [5.2, 2.8, -0.6], "look": [0.2, 3.0, 2.8], "fov": 36},
        # the clinch from the side, low
        {"f": i1 + 12, "pos": [5.6, 2.4, 2.6], "look": [0.0, 3.6, 2.0], "fov": 34, "cut": True},
        {"f": i3 + 4, "pos": [5.0, 2.2, 2.8], "look": [0.0, 3.8, 2.0], "fov": 33},
        # reverse angle for the elbow: her face over its shoulder
        {"f": i3 + 12, "pos": [-2.4, 4.8, 7.0], "look": [0.2, 4.4, 1.0], "fov": 34, "cut": True},
        {"f": i4 + 8, "pos": [-3.0, 4.6, 6.6], "look": [0.2, 4.2, 1.2], "fov": 34},
        # wide while she resets and switches
        {"f": i4 + 12, "pos": [9.6, 3.6, 0.2], "look": [0.0, 3.0, 2.6], "fov": 36, "cut": True},
        {"f": i5 - 14, "pos": [8.6, 3.2, 0.8], "look": [0.0, 3.4, 2.4], "fov": 34},
        # the head kick, low three-quarter, then the spin and the landing
        {"f": i5 - 13, "pos": [5.0, 1.8, 6.0], "look": [0.0, 4.2, 2.2], "fov": 36, "cut": True},
        {"f": i5 + 4, "pos": [5.4, 2.2, 6.4], "look": [0.0, 3.8, 2.6], "fov": 34},
        {"f": D, "pos": [10.8, 5.2, 0.4], "look": [0.0, 1.6, 3.6], "fov": 38, "ease": "out"},
    ]

    timing = tl.get("move") or {}
    startup = int(timing.get("startup") or 19)
    active = int(timing.get("active") or 3)
    recovery = int(timing.get("recovery") or 28)
    first = startup + 1
    start_keys = [
        pk(0, stance),
        # the activation: a sharp exhale, gloves tapped together in front of the face, chin down
        pk(5, stance, "out", pelvis_plus=[0.0, -0.03, -0.03], neck_plus=[-8, 0, 0],
           LeftHand={"at": [-0.04, 1.42, 0.30], "pole": [-0.8, -0.5, 0.1]}, RightHand={"at": [0.08, 1.42, 0.30], "pole": [0.8, -0.5, 0.1]}),
        pk(10, stance, "smooth", pelvis_plus=[0.0, -0.04, -0.03], neck_plus=[-10, 0, 0],
           LeftHand={"at": [-0.04, 1.44, 0.30], "pole": [-0.8, -0.5, 0.1]}, RightHand={"at": [0.08, 1.44, 0.30], "pole": [0.8, -0.5, 0.1]}),
        pk(first - 7, C.pose_at(C.at(TEEP, "windup")), "in"),
        pk(first, C.pose_at(C.at(TEEP, "contact")), "snap"),
        pk(first + active + 5, C.pose_at(C.at(TEEP, "follow"))),
        pk(first + active + int(recovery * 0.6), C.pose_at(C.at(TEEP, "recover"))),
        pk(first + active + recovery, stance),
    ]
    return {
        "name": "Sierra_Ultimate", "fighter": FIGHTER, "style": STYLE, "dist": home, "duration": D, "impacts": H.impacts,
        "endKind": "FaceUp", "attacker": A, "defender": Dk, "allow": ALLOW, "hits": H.hits, "strikes": H.strikes, "grips": H.grips,
        "camera": cam, "release": i5,
        "order": [("D", "LeftHand"), ("D", "RightHand"), ("D", "LeftFoot"), ("D", "RightFoot"), ("A", "LeftHand"), ("A", "RightHand")],
        "start": {"timing": (startup, active, recovery), "keys": start_keys, "tags": {"limb": "LeftFoot"},
                  "notes": "Eight Limbs start: gloves tapped together with a sharp exhale, then an armored long teep."},
        "notes": "Sierra Ultimate 'Eight Limbs': teep, body kick, clinch knees, slashing elbow, Southpaw switch head kick.",
    }
