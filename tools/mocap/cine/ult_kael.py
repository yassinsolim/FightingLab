"""KAEL (street boxer) Ultimate 'Final Bell' (roster beats, movesets.md 5.1):
  f0     the hit: an armored, lunging right straight to the sternum; the opponent folds forward and Kael steps in
         chest to chest, dipping into the Pocket
  imp 1  lead shovel hook to the liver; the defender doubles over to its right side, elbows drop
  imp 2  rear hook to the other side of the body; its knees buckle and its hands fall from its face
  imp 3  lead uppercut through the guard; the chin snaps up, the torso straightens, it staggers half a step back
  imp 4  right straight to the jaw; the head turns and it spins a quarter turn away, arms limp
  ...    Kael plants and loads the overhand right high behind his ear (the camera holds on him)
  imp 5  the overhand comes over the top onto the temple and drives the defender face-first into the floor (FaceDown,
         head away, on its spot); Kael ends standing over it, gloves up, breathing
Key poses: Kael's own strike clips (contact poses) and the core reaction / fall clips, moved whole; each strike's
step-in is solved so the fist meets its target on the defender (the runtime strike grip then fits any pair of rigs).
"""
from __future__ import annotations

import twobody as T
import cinecommon as C
from cinecommon import F, pk

FIGHTER = "Kael"
STYLE = "boxer"
ROOT_HEIGHT = 4.113    # Kael's rig (CharacterFactory): leg = RootHeight x 0.775 studs

STRAIGHT = "Strike_Kael_ChargingCross"
LIVER = "Strike_Kael_LiverHook"
SHOVEL = "Strike_Kael_BodyBlow"
UPPER = "Strike_Kael_RisingUppercut"
CROSS = "Strike_Kael_Cross"
JAB = "Strike_Kael_Jab"
OVER = "Strike_Kael_Overhand"

ALLOW = [("hand", "head", 0.05), ("hand", "spine", 0.05), ("hand", "neck", 0.04), ("foreArm", "head", 0.03),
         ("hand", "shoulders", 0.04), ("foreArm", "shoulders", 0.03), ("hand", "hips", 0.05), ("hand", "hand", 0.03),
         ("hand", "foreArm", 0.03), ("foreArm", "hand", 0.03), ("foreArm", "foreArm", 0.03), ("foreArm", "spine", 0.03),
         ("foreArm", "hips", 0.03), ("head", "head", 0.02), ("hand", "upperArm", 0.03), ("upperArm", "hand", 0.03)]


def home_m(end_distance: float) -> float:
    """The defender's sim spot in authoring metres: endDistance studs / Kael's leg (studs) x the reference leg (m)."""
    return end_distance / (ROOT_HEIGHT * 0.775) * T.LEG


def pocket(base: T.Pose, sway: float = 0.0) -> dict:
    """Edits that drop a boxer's guard pose into the Pocket: knees bend, head forward-down under the line, chin behind
    the lead shoulder, gloves at the cheeks; `sway` (deg) rolls the head side to side (the bob-and-roll)."""
    out = {"pelvis_plus": [0.0, -0.11, 0.02], "rot_plus": [-14, 6, sway], "waist_plus": [-10, 4, sway * 0.6], "neck_plus": [-6, 0, 0]}
    out.update(C.guard_local(base, dy=0.02, dz=0.02))
    return out


def build(tl: dict) -> dict:
    D = tl["duration"]
    I = list(tl["impacts"])
    assert len(I) == 5, "Final Bell has five impacts"
    i1, i2, i3, i4, i5 = I
    home = home_m(tl.get("endDistance", 4.4))
    T.DIST[0] = home
    stance = C.stance_of(FIGHTER)
    H = C.Hits()

    # --- defender (its own LS: +z toward Kael), built first: the strikes are aimed at it --------------------------------
    catch_fist = C.tip_of(T.full_joints(C.pose_at(C.at(STRAIGHT, "contact"))), "RightHand")
    sternum_d = T.point(T.full_joints(C.pose_at("HitMidHeavy@0.0")), C.sternum()[:3])
    z0 = home - sternum_d[2] - catch_fist[2] - 0.02
    zc = home - 0.98            # where it stands while the combination lands (~1 m from Kael's spot)
    limp = {"LeftHand": {"local": [-0.24, -0.52, 0.06], "lw": 1.0, "plocal": [0, 0, 1]},
            "RightHand": {"local": [0.24, -0.52, 0.06], "lw": 1.0, "plocal": [0, 0, 1]}}

    def r(f, ref, z, ease=None, **kw):
        return pk(f, C.pose_at(ref, z), ease, **kw)

    def turned(f, ref, z, yaw, ease=None, **kw):
        """A reaction pose turned `yaw` deg about the vertical (feet re-planted around the pelvis)."""
        p = C.pose_at(ref, z)
        return pk(f, C.yawed(p, yaw), ease, **kw)

    Dk = [
        # the catch: the straight folds it forward
        r(0, "HitMidHeavy@0.0", z0),
        r(8, "HitMidHeavy@0.12", z0 - 0.01, rot_plus=[-4, 0, 0]),
        r(20, "HitMidHeavy@0.3", (z0 + zc) * 0.5, rot_plus=[-6, 0, 0]),
        # imp 1: the shovel hook to the liver doubles it over to its right side, elbows drop
        r(i1 - 4, "HitMidHeavy@0.45", zc, rot_plus=[2, 0, 0]),
        r(i1, "HitMidHeavy@0.0", zc, "snap", rot_plus=[2, -6, -14], waist_plus=[-2, -6, -12]),
        r(i1 + 8, "HitMidHeavy@0.15", zc - 0.03, rot_plus=[-12, -8, -16], waist_plus=[-8, -8, -14], LeftHand={"at+": [0.04, -0.12, 0.0]}, RightHand={"at+": [-0.02, -0.14, 0.0]}),
        r(i2 - 10, "HitMidHeavy@0.35", zc - 0.03, rot_plus=[-10, -4, -10], waist_plus=[-6, -4, -8]),
        # imp 2: the rear hook to its left side: the knees buckle, the hands fall from the face
        r(i2, "HitMidHeavy@0.0", zc - 0.02, "snap", rot_plus=[-6, 8, 12], waist_plus=[-4, 8, 12], pelvis_plus=[0.0, -0.05, 0.0],
          LeftHand={"at+": [-0.02, -0.22, -0.04]}, RightHand={"at+": [0.02, -0.24, -0.04]}),
        r(i2 + 8, "HitMidHeavy@0.15", zc - 0.04, rot_plus=[-8, 6, 10], waist_plus=[-6, 6, 10], pelvis_plus=[0.0, -0.09, 0.0],
          LeftHand={"at+": [-0.02, -0.3, -0.04]}, RightHand={"at+": [0.02, -0.32, -0.04]}),
        r(i3 - 8, "HitMidHeavy@0.3", zc - 0.03, rot_plus=[-10, 2, 4], pelvis_plus=[0.0, -0.08, 0.0],
          LeftHand={"at+": [-0.02, -0.26, -0.04]}, RightHand={"at+": [0.02, -0.28, -0.04]}),
        # imp 3: the lead uppercut: chin snaps up, torso straightens, half a step back
        r(i3, "HitHighHeavy@0.0", zc - 0.02, "snap", neck_plus=[32, 0, 0], waist_plus=[10, 0, 0]),
        r(i3 + 8, "HitHighHeavy@0.12", zc - 0.08, neck_plus=[20, 0, 0], waist_plus=[6, 0, 0], lift=(0.04, 0.0)),
        r(i3 + 20, "HitHighHeavy@0.45", zc - 0.12, lift=(0.0, 0.03)),
        r(i4 - 6, "HitHighHeavy@0.6", zc - 0.10),
        # imp 4: the straight to the jaw: the head turns, it spins a quarter turn away, arms limp
        r(i4, "HitHighHeavy@0.0", zc - 0.10, "snap", neck_plus=[6, -34, -6], waist_plus=[0, -12, 0]),
        turned(i4 + 8, "HitHighHeavy@0.15", zc - 0.12, -45, neck_plus=[4, -20, -4], **limp),
        turned(i4 + 18, "Stagger@0.3", zc - 0.12, -90, **limp),
        turned(i5 - 16, "Stagger@0.5", zc - 0.10, -92, rot_plus=[0, 0, 4], **limp),
        turned(i5 - 6, "Stagger@0.6", zc - 0.09, -88, rot_plus=[0, 0, -3], **limp),
        # imp 5: the overhand on the (left) temple turns it the rest of the way and drives it face-first to the floor
        turned(i5, "HitHighHeavy@0.0", zc - 0.08, -96, "snap", neck_plus=[-18, -24, 0], rot_plus=[0, 0, 0], **limp),
    ]
    Dk += C.flight(i5 + 1, i5 + 15, zc - 0.10, "FaceDown", yaw_from=-96, yaw_end=-180, apex=0.72)
    Dk.append(F(D, **{"from": C.end_pose("FaceDown"), "ground": 1.0}))
    dtrack = T.Track(Dk, "D")

    # --- attacker ------------------------------------------------------------------------------------------------
    pk_edit = pocket(stance)
    A = [
        pk(0, C.pose_at(C.at(STRAIGHT, "contact"))),
        pk(6, C.pose_at(C.at(STRAIGHT, "follow"))),
    ]
    # steps in chest to chest and dips into the Pocket (bobbing), then the shovel hook to the liver
    dz1, b1 = C.strike_beat(dtrack, i1, LIVER, "LeftHand", C.liver(+1), stance, start_off=9, windup_off=5, recover_off=7, guard_after=8,
                            dx=-0.20, extra={"guard": pk_edit, "start": {"pelvis_plus": [0.0, -0.06, 0.0]}})
    A += [pk(14, C.pose_at(stance, dz1 * 0.6), lift=(0.05, 0.05), **pocket(stance, 5))]
    A += b1[1:]
    H.add(i1, "LeftHand", "Mid", C.liver(+1))
    # the rear hook to the other side (a rear shovel ripping in from the right)
    dz2, b2 = C.strike_beat(dtrack, i2, SHOVEL, "RightHand", C.ribs(-1), stance, start_off=10, windup_off=6, recover_off=7, guard_after=8,
                            dx=0.10, extra={"guard": pocket(stance, -5)})
    A += b2
    H.add(i2, "RightHand", "Mid", C.ribs(-1))
    # the lead uppercut through the guard (the left fist rising from the dipped hook position)
    # (a compact stance under it: the jab's feet, the lead fist rising from the dip with the elbow under it)
    dz3, b3 = C.strike_beat(dtrack, i3, JAB, "LeftHand", C.chin(), stance, start_off=11, windup_off=6, recover_off=8, guard_after=8,
                            arm_tol=-0.06, extra={"guard": pocket(stance, 4), "windup": {"pelvis_plus": [0.0, -0.10, 0.0], "rot_plus": [-8, 8, 0],
                                                                                          "LeftHand": {"at+": [0.04, -0.30, -0.12], "pole": [-0.2, -1.0, 0.1]}},
                                                  "limb": {"pole": [-0.2, -1.0, 0.25]}, "contact": {"pelvis_plus": [0.0, 0.04, 0.0], "rot_plus": [4, -12, 0], "waist_plus": [6, -10, 0]}})
    A += b3
    H.add(i3, "LeftHand", "High", C.chin())
    # the right straight to the jaw
    dz4, b4 = C.strike_beat(dtrack, i4, CROSS, "RightHand", C.jaw(-1), stance, start_off=11, windup_off=6, recover_off=8, guard_after=9, clear=0.01, arm_tol=-0.07)
    A += b4
    H.add(i4, "RightHand", "High", C.jaw(-1))
    # plants and loads the overhand high behind his ear (held while the camera stays on him), then the finish
    dz5 = C.reach_dz(C.at(OVER, "contact"), "RightHand", C.temple(-1), dtrack, i5, 0.02, clear=0.0, arm_tol=-0.09)
    A += [
        pk(i4 + 30, C.pose_at(stance, dz5), lift=(0.04, 0.05)),
        pk(i4 + 36, C.pose_at(C.at(OVER, "start"), dz5)),
        pk(i5 - 14, C.pose_at(C.at(OVER, "windup"), dz5), rot_plus=[0, 10, 0], waist_plus=[4, 10, 0]),
        pk(i5 - 5, C.pose_at(C.at(OVER, "windup"), dz5), rot_plus=[0, 14, 0], waist_plus=[6, 14, 0], RightHand={"at+": [0.04, 0.06, -0.06]}),
        pk(i5, C.pose_at(C.at(OVER, "contact"), dz5), "snap", RightHand={"grip": C.temple(-1), "w": 1.0}),
        pk(i5 + 5, C.pose_at(C.at(OVER, "follow"), dz5)),
        # steps back off the falling body
        pk(i5 + 11, C.pose_at(C.at(OVER, "recover"), dz5 - 0.12), lift=(0.05, 0.04)),
        # stands over it, gloves up, breathing (back on his spot for the idle)
        pk(D - 4, stance, lift=(0.03, 0.03), rot_plus=[3, 0, 0]),
        pk(D, stance),
    ]
    H.add(i5, "RightHand", "High", C.temple(-1))
    A.sort(key=lambda kk: kk["f"])

    # --- camera (studs, Kael's frame: +x his right, +z toward the defender) ----------------------------------------
    cam = [
        {"f": 0, "pos": [5.4, 3.6, -1.6], "look": [0.3, 3.4, 2.4], "fov": 38, "cut": True},
        {"f": 18, "pos": [4.0, 3.0, 0.6], "look": [0.2, 3.0, 2.3], "fov": 35},
        {"f": i1 + 8, "pos": [3.7, 2.9, 0.9], "look": [0.2, 3.0, 2.3], "fov": 34},
        # reverse low angle past the defender: Kael's face working the body
        {"f": i1 + 12, "pos": [2.8, 2.3, 7.4], "look": [0.0, 3.3, 1.4], "fov": 35, "cut": True},
        {"f": i2 + 10, "pos": [2.2, 2.2, 7.0], "look": [0.0, 3.3, 1.5], "fov": 34},
        # profile for the uppercut
        {"f": i3 - 16, "pos": [8.4, 2.4, 1.8], "look": [0.0, 4.0, 2.2], "fov": 34, "cut": True},
        {"f": i3 + 10, "pos": [7.8, 2.2, 2.2], "look": [0.0, 4.2, 2.3], "fov": 33},
        # over Kael's left shoulder: the straight and the spin
        {"f": i4 - 14, "pos": [-2.8, 5.2, -2.8], "look": [0.4, 4.2, 3.8], "fov": 36, "cut": True},
        {"f": i4 + 14, "pos": [-3.4, 5.0, -2.4], "look": [0.5, 4.0, 3.8], "fov": 35},
        # holds on him while he loads the overhand
        {"f": i4 + 20, "pos": [3.4, 3.9, 3.0], "look": [0.1, 4.8, 0.6], "fov": 31, "cut": True},
        {"f": i5 - 4, "pos": [2.9, 3.8, 2.6], "look": [0.1, 4.7, 0.7], "fov": 29},
        # the bell: wide low side angle, then up and out over the body on the floor
        {"f": i5 - 3, "pos": [7.4, 1.8, 2.6], "look": [0.0, 3.2, 3.0], "fov": 36, "cut": True},
        {"f": i5 + 12, "pos": [8.6, 4.6, 1.8], "look": [0.0, 1.4, 3.8], "fov": 38},
        {"f": D, "pos": [10.4, 5.8, 0.4], "look": [0.0, 1.6, 3.4], "fov": 40, "ease": "out"},
    ]

    # --- the Ultimate move's own clip: the activation and the lunging straight -------------------------------------
    timing = tl.get("move") or {}
    startup = int(timing.get("startup") or 17)
    active = int(timing.get("active") or 3)
    recovery = int(timing.get("recovery") or 30)
    first = startup + 1
    roar = {"pelvis_plus": [0.0, -0.05, -0.04], "rot_plus": [8, 10, 0], "waist_plus": [8, 6, 0], "neck_plus": [12, 0, 0],
            "LeftHand": {"at": [-0.30, 1.05, 0.08], "pole": [-0.9, -0.3, -0.2]}, "RightHand": {"at": [0.48, 1.02, -0.02], "pole": [0.9, -0.3, -0.2]}}
    start_keys = [
        pk(0, stance),
        # the activation: gloves drop and pull back, chest open, a roar (held while the screen flashes)
        pk(4, stance, "out", **roar),
        pk(9, stance, "smooth", **dict(roar, neck_plus=[14, 0, 0])),
        pk(first - 5, C.pose_at(C.at(STRAIGHT, "windup")), "in"),
        pk(first, C.pose_at(C.at(STRAIGHT, "contact")), "snap"),
        pk(first + active + 4, C.pose_at(C.at(STRAIGHT, "follow"))),
        pk(first + active + int(recovery * 0.6), C.pose_at(C.at(STRAIGHT, "recover"))),
        pk(first + active + recovery, stance),
    ]
    return {
        "name": "Kael_Ultimate", "fighter": FIGHTER, "style": STYLE, "dist": home, "duration": D, "impacts": H.impacts,
        "endKind": "FaceDown", "attacker": A, "defender": Dk, "allow": ALLOW, "hits": H.hits, "strikes": H.strikes, "grips": H.grips,
        "camera": cam, "release": i5,
        "order": [("D", "LeftHand"), ("D", "RightHand"), ("D", "LeftFoot"), ("D", "RightFoot"), ("A", "LeftHand"), ("A", "RightHand")],
        "start": {"timing": (startup, active, recovery), "keys": start_keys, "tags": {"limb": "RightHand"},
                  "notes": "Final Bell start: drops the gloves with a roar, then an armored lunging right straight to the sternum."},
        "notes": "Kael Ultimate 'Final Bell': lunging straight, shovel hook, rear body hook, lead uppercut, straight to the jaw, overhand face-first finish.",
    }
