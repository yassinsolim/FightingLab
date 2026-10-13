"""GORAN (heavyweight grappler) Ultimate 'Landslide' (roster beats, movesets.md 5.3):
  f0     the hit: an armored charging shoulder pins the opponent; Goran wraps both arms around its waist (body lock)
         and keeps driving a little
  imp 1  he crushes the body lock (it is lifted off its feet, back arched, arms over his shoulders) and shakes it
  imp 2  belly-to-belly suplex: he arches back and throws it over his head; it lands flat on its back behind him (head
         toward him) while he lands on his shoulders and rolls through to his left, onto his front, and stands
  ...    he drags the dazed defender up by the waist from behind, its legs buckling
  imp 3  he lifts it across his chest and drops it onto his raised right knee; it folds over the knee
  ...    he heaves it up onto his right shoulder (lengthwise, head out in front), turns round to his left and walks one
         heavy step forward
  imp 4  he falls forward with his whole weight and drives it flat onto its back on its spot (FaceUp, head away); he
         rises slowly over it
Defender poses in the middle of the clip are authored in Goran's frame (g(): +z = Goran's original front) and turned
into the defender's frame by to_def(); the first and last keys are in the defender's own frame.
"""
from __future__ import annotations

import twobody as T
import cinecommon as C
from cinecommon import pk

FIGHTER = "Goran"
STYLE = "grappler"
ROOT_HEIGHT = 4.095

TACKLE = "Strike_Goran_ShoulderTackle"

ALLOW = [("hand", "spine", 0.08), ("hand", "hips", 0.08), ("foreArm", "spine", 0.08), ("foreArm", "hips", 0.07), ("upperArm", "spine", 0.06),
         ("spine", "spine", 0.10), ("spine", "hips", 0.08), ("hips", "hips", 0.08), ("shoulders", "spine", 0.08), ("head", "spine", 0.06),
         ("head", "shoulders", 0.06), ("hand", "shoulders", 0.06), ("foreArm", "shoulders", 0.06), ("thigh", "spine", 0.08),
         ("thigh", "hips", 0.08), ("thigh", "thigh", 0.06), ("shoulders", "hips", 0.08), ("neck", "spine", 0.06), ("hand", "thigh", 0.06),
         ("foreArm", "thigh", 0.06), ("shoulders", "thigh", 0.08), ("upperArm", "thigh", 0.06), ("spine", "thigh", 0.08), ("hand", "hand", 0.04),
         ("foreArm", "foreArm", 0.04), ("upperArm", "upperArm", 0.04), ("hand", "head", 0.05), ("foreArm", "head", 0.05),
         ("shoulders", "shoulders", 0.06), ("upperArm", "spine", 0.06), ("upperArm", "hips", 0.06), ("neck", "hips", 0.06)]


def flank(side: int, dy: float = 0.0, out: float = 0.07):
    """Its side under the shoulder, a hand's thickness outside the ribs (side +1 = its right)."""
    return ("shoulderR" if side > 0 else "shoulderL", ((0.03 + out) * side, -0.13 + dy, -0.02), "chest",
            C._rt("UpperTorso", (1.0 + out / 0.19) * side, 0.2 + dy / 0.18, 0.0))


def hip_side(side: int, dy: float = 0.0, out: float = 0.06):
    """Its hip, a hand's thickness outside the side of the pelvis (side +1 = its right)."""
    return (("pelvis", "waist", 0.8), ((0.15 + out) * side, dy, 0.0), "pelvis", C._rt("LowerTorso", (1.1 + out / 0.17) * side, 0.6 + dy / 0.10, 0.0))


def home_m(end_distance: float) -> float:
    return end_distance / (ROOT_HEIGHT * 0.775) * T.LEG


def build(tl: dict) -> dict:
    D = tl["duration"]
    i1, i2, i3, i4 = tl["impacts"]
    home = home_m(tl.get("endDistance", 4.6))
    T.DIST[0] = home
    stance = C.stance_of(FIGHTER)
    H = C.Hits()

    def to_def(p_g: T.Pose) -> T.Pose:
        """A defender pose given in Goran's frame -> the defender's own frame (half turn about the midpoint)."""
        return C.rotated(p_g, [0, 180, 0], about=[0.0, 0.0, home * 0.5])

    def dk(f, p_g, ease=None, **kw):
        return pk(f, to_def(p_g), ease, **kw)

    def facing_back(ref, z, x=0.0):
        """A pose (or ref) turned to face -z (toward Goran when it stands in front of him; away from him when it stands
        behind him), placed at (x, z) in Goran's frame."""
        return C.pose_at(C.yawed(C.pose_at(ref), 180), z, x)

    flat_up = C.end_pose("FaceUp")                       # lying on its back, head toward -z (own frame)
    head_fwd = C.yawed(flat_up, 180)                     # ... head toward +z

    # --- key places (Goran's frame) ---------------------------------------------------------------------------------
    g_lock = 0.28                                        # Goran's root after driving through the body lock
    zl = g_lock + 0.66                                   # the defender's root in the lock
    d_land = (0.42, -1.15)                               # (x, z) of the defender's pelvis after the suplex
    g_knee = (0.30, -0.55)                               # Goran's root for the drag-up and the knee slam (facing -z)
    g_carry = (-0.20, 0.05)                              # ... after turning round with it on his shoulder (facing +z)
    g_fall = (-0.22, 0.48)                               # ... stepping into the fall
    KNEE_UP = 1.02                                       # the defender's lift onto the raised knee (its back on the knee)
    SHOULDER = 1.68                                      # ... onto his shoulder (lying pose raised)
    SIDE = 0.30                                          # its body beside his head: the right shoulder, off his centre line
    g_drop = (-0.42, 0.95)                               # Goran's root when the defender hits the floor (kneeling at its right hip)

    # --- defender ---------------------------------------------------------------------------------------------------
    hug = "HitMidHeavy@0.0"
    Dk = [
        dk(0, facing_back(hug, zl - 0.20)),
        dk(10, facing_back("HitMidHeavy@0.12", zl), rot_plus=[-6, 0, 0]),
        dk(i1 - 10, facing_back("HitMidHeavy@0.3", zl - 0.02)),
        # lifted off its feet in the crushing lock: the back arches, the arms flail over his shoulders
        dk(i1, C.raised(facing_back("HitHighHeavy@0.0", zl - 0.04), 0.28), "snap",
           LeftHand={"local": [-0.40, 0.60, -0.20], "lw": 1.0}, RightHand={"local": [0.40, 0.64, -0.18], "lw": 1.0},
           contact={"LeftFoot": 0.0, "RightFoot": 0.0}),
    ]
    for k, (f, yaw) in enumerate(((i1 + 8, 10), (i1 + 16, -10), (i1 + 24, 8), (i1 + 32, -6))):
        Dk.append(dk(f, C.rotated(C.raised(facing_back("HitHighHeavy@0.12", zl - 0.04), 0.30), [0, yaw, 0], about=[0.0, 0.0, g_lock]),
                     LeftHand={"local": [-0.42, 0.58 - k * 0.02, -0.18], "lw": 1.0}, RightHand={"local": [0.42, 0.62, -0.16], "lw": 1.0},
                     contact={"LeftFoot": 0.0, "RightFoot": 0.0}))
    # the suplex: up and over his head (x+ tips its head toward -z), landing flat on its back behind him
    over = C.raised(facing_back("HitHighHeavy@0.12", zl - 0.04), 0.32)
    piv = [0.0, 1.05, g_lock - 0.05]
    Dk += [
        dk(i2 - 12, over),
        dk(i2 - 8, C.rotated(over, [55, 0, 0], about=piv)),
        dk(i2 - 5, C.rotated(over, [120, 0, 0], about=piv)),
        dk(i2 - 2, C.rotated(C.pose_at(over, -0.25, d_land[0] * 0.6), [165, 0, 0], about=[d_land[0] * 0.6, 1.05, g_lock - 0.30])),
        dk(i2, C.pose_at(C.rotated(head_fwd, [-14, 0, 0]), d_land[1], d_land[0]), "snap", ground=1.0),
        dk(i2 + 10, C.pose_at(head_fwd, d_land[1], d_land[0]), ground=1.0),
        dk(i2 + 30, C.pose_at(head_fwd, d_land[1], d_land[0]), ground=1.0),
    ]
    # hauled up from behind by the armpits (he stands past its head, never over it): sits up, comes up to a crouch and
    # stands facing away from him, legs buckling. In frame order, on the floor until it stands (round 6 follow-up: the
    # keys had fallen out of order on the roster timeline - stand, sit, stand within ten frames - and the lying/standing
    # blend once sank the body under the floor).
    Dk += [
        dk(i2 + 36, C.pose_at(head_fwd, d_land[1], d_land[0]), waist_plus=[-12, 0, 0], ground=1.0),
        dk(i2 + 41, C.pose_at(head_fwd, d_land[1] + 0.03, d_land[0]), waist_plus=[-58, 0, 0], neck_plus=[-12, 0, 0], ground=1.0),
        # (a step out in front of him: the buckled stance leans its hips back toward him)
        dk(i2 + 46, facing_back(C.lowered(C.pose_at("HitMidHeavy@0.4"), 0.42), d_land[1] - 0.05, d_land[0] - 0.02)),
        dk(i3 - 8, facing_back(C.lowered(C.pose_at("HitMidHeavy@0.3"), 0.16), d_land[1] - 0.01, d_land[0] - 0.06)),
    ]
    # lifted across his chest (on its back, head to his left = +x) and dropped onto his raised right knee. Every lifted
    # key says ground=0: the lying source pose carries the floor-support weight 1, and the runtime's ground solver then
    # pulled the carried body down onto the floor at his feet (round 6 playtest: the carry never showed, his legs went
    # through it, and once it sank under the floor).
    across = C.yawed(flat_up, 90)                         # head toward +x
    kx, kz = g_knee[0] - 0.14, g_knee[1] - 0.44           # his raised right knee (his right = -x when facing -z)
    # its right side faces him across the knee: that arm reaches straight past its head instead of hanging into his chest
    arm_over = {"RightHand": {"local": [-0.04, 0.66, 0.10], "lw": 1.0}}
    Dk += [
        dk(i3 - 5, C.pose_at(C.raised(across, 1.12), kz, kx - 0.28), ground=0.0, **arm_over),
        # (its back rests on the knee, not inside the thigh)
        dk(i3, C.rotated(C.pose_at(C.raised(across, KNEE_UP), kz - 0.07, kx - 0.26), [0, 0, -10]), "snap", ground=0.0, **arm_over),
        dk(i3 + 9, C.rotated(C.pose_at(C.raised(across, KNEE_UP + 0.02), kz - 0.07, kx - 0.26), [0, 0, -16]), ground=0.0, **arm_over),
    ]
    # on the shoulder its right side lies against his head: that arm reaches past its head, away from his face
    arm_up = {"RightHand": {"local": [0.26, 0.62, 0.12], "lw": 1.0}}
    # heaved up onto his right shoulder: it swings lengthwise on the way up (head out in front of him), its body beside
    # his head, never across it; he turns round to his left (yaw +180) carrying it, then one heavy step forward.
    lengthwise = C.yawed(flat_up, 180)                    # head toward +z when he faces +z
    g_turn = g_knee[1] + 0.05
    shoulder = SHOULDER
    on_right = C.pose_at(C.raised(flat_up, shoulder), g_turn + 0.06, g_knee[0] - SIDE)   # he faces -z: his right is -x
    # (on the shoulder too its right side lies against his head: the same raised arm)
    mid = ((g_turn + g_carry[1]) * 0.5, (g_knee[0] + g_carry[0]) * 0.5)          # half way through the second quarter turn
    s45 = 0.7071
    Dk += [
        # (it swings lengthwise low, at his chest, out to his right - never across his face - then rises onto the shoulder)
        dk(i3 + 15, C.yawed(C.pose_at(C.raised(across, 0.95), kz + 0.04, kx - 0.32), -70), ground=0.0, **arm_up),
        dk(i3 + 19, C.pose_at(C.raised(flat_up, 1.40), g_turn - 0.45, g_knee[0] - SIDE - 0.02), ground=0.0, **arm_up),
        dk(i3 + 22, on_right, ground=0.0, **arm_up),
        # (quarter-turn keys every 45 degrees: the carried body follows the arc round his head, not the chord)
        dk(i3 + 28, C.rotated(C.raised(on_right, 0.06), [0, 45, 0], about=[g_knee[0], 0.0, g_turn]), ground=0.0, **arm_up),
        dk(i3 + 34, C.rotated(C.raised(on_right, 0.05), [0, 90, 0], about=[g_knee[0], 0.0, g_turn]), ground=0.0, **arm_up),
        dk(i4 - 24, C.pose_at(C.yawed(C.raised(lengthwise, shoulder + 0.02), -45), mid[0] - SIDE * s45 - 0.06 * s45, mid[1] + SIDE * s45 - 0.06 * s45),
           ground=0.0, **arm_up),
        dk(i4 - 18, C.pose_at(C.raised(lengthwise, shoulder + 0.03), g_carry[1] - 0.06, g_carry[0] + SIDE), ground=0.0, **arm_up),
        # slides off his shoulder forward and out to his right, head first, as he falls
        dk(i4 - 9, C.rotated(C.pose_at(C.raised(lengthwise, shoulder - 0.22), g_fall[1] + 0.22, g_fall[0] + SIDE + 0.06), [-30, 0, 0],
                             about=[g_fall[0] + SIDE + 0.06, shoulder - 0.1, g_fall[1] + 0.22]), ground=0.0, **arm_up),
    ]
    # driven flat onto its back on its spot (own frame: head away from him); the floor support takes over only in the
    # last frames of the fall, when the body is a hand's breadth above the floor (MotionUltimate_Test)
    Dk += [
        pk(i4 - 3, C.raised(flat_up, 0.22), "in", ground=0.0),
        pk(i4, flat_up, "in", ground=1.0),
        pk(D, flat_up, ground=1.0),
    ]

    # --- attacker ---------------------------------------------------------------------------------------------------
    # (the locked hands sit a hand's thickness off its lower back)
    lock = {"LeftHand": {"grip": C.lower_back(dx=0.12, dy=-0.06, dz=-0.05), "w": 1.0, "pole": [-0.8, -0.4, 0.2]},
            "RightHand": {"grip": C.lower_back(dx=-0.12, dy=-0.06, dz=-0.05), "w": 1.0, "pole": [0.8, -0.4, 0.2]}}
    # on the shoulder its right side lies against his head: his left hand holds its right flank, his right hand its hip
    # (both just outside the body: the grip points sit off the surface by about a hand's thickness)
    carry = {"LeftHand": {"grip": flank(+1), "w": 1.0}, "RightHand": {"grip": hip_side(+1), "w": 1.0}}
    A = [
        pk(0, C.pose_at(C.at(TACKLE, "contact"))),
        pk(12, C.pose_at(stance, g_lock * 0.6), lift=(0.06, 0.06), **lock),
        pk(i1 - 10, C.lowered(C.pose_at(stance, g_lock), 0.10), **lock),
        # the crush: he rises and leans back a little, lifting it
        pk(i1, C.pose_at(stance, g_lock - 0.04), "snap", rot_plus=[8, 0, 0], waist_plus=[6, 0, 0], **lock),
    ]
    for f, yaw in ((i1 + 8, 12), (i1 + 16, -12), (i1 + 24, 10), (i1 + 32, -8)):
        A.append(pk(f, C.rotated(C.pose_at(stance, g_lock - 0.04), [6, yaw, 0]), **lock))
    # the suplex: a dip, he arches back over his heels, lets go over his head and lands on his shoulders
    A += [
        pk(i2 - 12, C.lowered(C.pose_at(stance, g_lock - 0.02), 0.14), **lock),
        pk(i2 - 8, C.rotated(C.pose_at(stance, g_lock - 0.02), [32, 0, 0], about=[0.0, 0.1, g_lock - 0.1]), **lock),
        pk(i2 - 5, C.rotated(C.pose_at(stance, g_lock - 0.08), [72, 0, 0], about=[0.0, 0.2, g_lock - 0.2])),
        pk(i2, C.pose_at(flat_up, g_lock - 0.55, -0.18), "in", ground=1.0),
        # rolls through to his left (onto his front), pushes up and stands facing it
        pk(i2 + 10, C.raised(C.rotated(C.pose_at(flat_up, g_lock - 0.58, -0.30), [0, 0, 90]), 0.24), ground=1.0),
        pk(i2 + 18, C.pose_at(C.prone_away_contact(), g_lock - 0.60, -0.42), ground=1.0),
        pk(i2 + 26, facing_back(C.lowered(C.pose_at(stance), 0.46), 0.12, -0.30), ground=0.3),
        # stands past its head (never over the body), bends, hooks both armpits and hauls it up to its feet
        pk(i2 + 33, facing_back(C.lowered(C.pose_at(stance), 0.10), 0.06, d_land[0]), lift=(0.05, 0.05)),
        pk(i2 + 37, facing_back(C.lowered(C.pose_at(stance), 0.32), 0.0, d_land[0]), rot_plus=[-30, 0, 0],
           LeftHand={"grip": flank(-1), "w": 1.0}, RightHand={"grip": flank(+1), "w": 1.0}),
        pk(i2 + 42, facing_back(C.lowered(C.pose_at(stance), 0.20), -0.26, d_land[0] - 0.04), rot_plus=[-14, 0, 0], lift=(0.04, 0.04),
           LeftHand={"grip": flank(-1), "w": 1.0}, RightHand={"grip": flank(+1), "w": 1.0}),
        # (far enough back that his lead knee stays off its back while it stands)
        pk(i3 - 8, facing_back(C.lowered(C.pose_at(stance), 0.06), -0.50, d_land[0] - 0.06), rot_plus=[-8, 0, 0],
           LeftHand={"grip": hip_side(-1), "w": 1.0}, RightHand={"grip": hip_side(+1), "w": 1.0}),
        # lifts it across his chest, raises the right knee and drops it onto the thigh
        # (held across his chest by its near side on the way up: its right flank and right hip face him)
        pk(i3 - 5, facing_back(stance, g_knee[1], g_knee[0]),
           LeftHand={"grip": flank(+1), "w": 1.0}, RightHand={"grip": hip_side(+1), "w": 1.0}),
        pk(i3, facing_back(C.lowered(C.pose_at(stance), 0.04), g_knee[1], g_knee[0]), "snap",
           RightFoot={"at": [g_knee[0] - 0.14, 0.46, g_knee[1] - 0.30], "pole": [0, 0.3, -1.0]},
           LeftHand={"grip": C.chest(dz=0.10), "w": 1.0, "pole": [-0.5, 0.7, 0.2]}, RightHand={"grip": C.thigh(-1), "w": 1.0}, contact={"RightFoot": 0.0}),
        pk(i3 + 9, facing_back(C.lowered(C.pose_at(stance), 0.04), g_knee[1], g_knee[0]),
           RightFoot={"at": [g_knee[0] - 0.14, 0.46, g_knee[1] - 0.28], "pole": [0, 0.3, -1.0]},
           LeftHand={"grip": C.chest(dz=0.10), "w": 1.0, "pole": [-0.5, 0.7, 0.2]}, RightHand={"grip": C.thigh(-1), "w": 1.0}, contact={"RightFoot": 0.0}),
        # heaves it up onto his right shoulder (both hands on its near side: shoulder and hip), turns round to his
        # left, one heavy step
        pk(i3 + 15, facing_back(C.lowered(C.pose_at(stance), 0.14), g_knee[1], g_knee[0]),
           LeftHand={"grip": C.chest(dz=0.06), "w": 1.0}, RightHand={"grip": C.thigh(-1), "w": 1.0}),
        pk(i3 + 19, facing_back(C.lowered(C.pose_at(stance), 0.10), g_knee[1], g_knee[0]), **carry),
        pk(i3 + 22, facing_back(C.lowered(C.pose_at(stance), 0.06), g_turn, g_knee[0]), **carry),
        pk(i3 + 28, C.pose_at(C.yawed(C.pose_at(C.lowered(C.pose_at(stance), 0.04)), -135), g_turn, g_knee[0]), **carry),
        pk(i3 + 34, C.pose_at(C.yawed(C.pose_at(stance), -90), g_turn, g_knee[0]), lift=(0.06, 0.06), **carry),
        pk(i4 - 24, C.pose_at(C.yawed(C.pose_at(stance), -45), (g_turn + g_carry[1]) * 0.5, (g_knee[0] + g_carry[0]) * 0.5), **carry),
        pk(i4 - 18, C.pose_at(stance, g_carry[1], g_carry[0]), lift=(0.08, 0.08), **carry),
        pk(i4 - 9, C.pose_at(stance, g_fall[1], g_fall[0]), lift=(0.12, 0.04), rot_plus=[-18, 0, 0], **carry),
        # the drop: he falls forward with his whole weight, down onto his right knee at its right hip (his left shin
        # outside its legs), driving it into the floor
        pk(i4, C.lowered(C.pose_at(stance, g_drop[1], g_drop[0]), 0.50), "in", rot_plus=[-34, 0, 0],
           RightFoot={"at": [g_drop[0] - 0.08, 0.15, g_drop[1] - 0.50], "pole": [0, -0.2, 1.0]},
           LeftHand={"grip": C.chest(dx=0.10, dz=0.05), "w": 1.0}, RightHand={"grip": C.belly(dx=-0.06, dz=0.05), "w": 1.0}),
        pk(i4 + 8, C.lowered(C.pose_at(stance, g_drop[1] - 0.02, g_drop[0]), 0.52), rot_plus=[-30, 0, 0],
           RightFoot={"at": [g_drop[0] - 0.08, 0.15, g_drop[1] - 0.52], "pole": [0, -0.2, 1.0]},
           LeftHand={"grip": C.chest(dx=0.10, dz=0.05), "w": 0.7}, RightHand={"grip": C.belly(dx=-0.06, dz=0.05), "w": 0.7}),
        # rises slowly over it and steps back to his spot, round its feet (never across its legs)
        pk(i4 + 16, C.lowered(C.pose_at(stance, g_drop[1] - 0.12, g_drop[0]), 0.30), rot_plus=[-12, 0, 0]),
        pk(D - 12, C.pose_at(C.lowered(C.pose_at(stance), 0.10), 0.28, g_drop[0] - 0.04), lift=(0.06, 0.06)),
        pk(D - 6, C.pose_at(C.lowered(C.pose_at(stance), 0.06), -0.10, -0.16), lift=(0.06, 0.06)),
        pk(D, stance, lift=(0.04, 0.04)),
    ]
    A.sort(key=lambda kk: kk["f"])
    H.add(i1, "Body", "Mid", None)
    H.add(i2, "Body", "Mid", None)
    H.add(i3, "RightKnee", "Mid", None)
    H.add(i4, "Body", "Mid", None)

    cam = [
        {"f": 0, "pos": [6.0, 3.4, -1.4], "look": [0.3, 3.4, 2.0], "fov": 38, "cut": True},
        {"f": i1 + 30, "pos": [5.4, 3.2, 0.2], "look": [0.1, 3.8, 1.6], "fov": 36},
        # the suplex wide in profile
        {"f": i1 + 34, "pos": [10.4, 3.4, -0.6], "look": [0.0, 3.2, -0.8], "fov": 40, "cut": True},
        {"f": i2 + 24, "pos": [10.0, 3.0, -1.4], "look": [0.6, 2.0, -2.4], "fov": 40},
        # in front of Goran for the drag-up and the knee slam
        {"f": i2 + 28, "pos": [3.6, 3.6, -9.2], "look": [0.8, 2.8, -2.6], "fov": 36, "cut": True},
        {"f": i3 + 14, "pos": [3.0, 3.4, -8.8], "look": [0.8, 2.8, -2.6], "fov": 35},
        # the carry and the drop: low and wide on the drop
        {"f": i3 + 18, "pos": [9.0, 2.4, 2.4], "look": [0.4, 4.0, -0.6], "fov": 40, "cut": True},
        {"f": i4 - 4, "pos": [8.0, 1.9, 3.6], "look": [0.2, 2.8, 1.6], "fov": 37},
        {"f": i4 + 6, "pos": [8.2, 3.0, 3.4], "look": [0.0, 1.4, 3.2], "fov": 37},
        {"f": D, "pos": [10.8, 5.4, 0.6], "look": [0.0, 1.8, 3.2], "fov": 38, "ease": "out"},
    ]

    timing = tl.get("move") or {}
    startup = int(timing.get("startup") or 21)
    active = int(timing.get("active") or 4)
    recovery = int(timing.get("recovery") or 28)
    first = startup + 1
    start_keys = [
        pk(0, stance),
        # the activation: a deep breath, chest swells, arms spread wide (held under the flash), then the charge
        pk(5, stance, "out", pelvis_plus=[0.0, 0.02, -0.03], rot_plus=[6, 0, 0], waist_plus=[6, 0, 0],
           LeftHand={"at": [-0.70, 1.30, 0.10], "pole": [-0.6, -0.6, -0.4]}, RightHand={"at": [0.72, 1.30, 0.10], "pole": [0.6, -0.6, -0.4]}),
        pk(11, stance, "smooth", pelvis_plus=[0.0, 0.02, -0.04], rot_plus=[8, 0, 0], waist_plus=[8, 0, 0],
           LeftHand={"at": [-0.74, 1.34, 0.08], "pole": [-0.6, -0.6, -0.4]}, RightHand={"at": [0.76, 1.34, 0.08], "pole": [0.6, -0.6, -0.4]}),
        pk(first - 6, C.pose_at(C.at(TACKLE, "windup")), "in"),
        pk(first, C.pose_at(C.at(TACKLE, "contact")), "snap"),
        pk(first + active + 5, C.pose_at(C.at(TACKLE, "follow"))),
        pk(first + active + int(recovery * 0.6), C.pose_at(C.at(TACKLE, "recover"))),
        pk(first + active + recovery, stance),
    ]
    return {
        "name": "Goran_Ultimate", "fighter": FIGHTER, "style": STYLE, "dist": home, "duration": D, "impacts": H.impacts,
        "endKind": "FaceUp", "attacker": A, "defender": Dk, "allow": ALLOW, "hits": H.hits, "strikes": H.strikes, "grips": H.grips,
        "camera": cam, "release": i4 - 9,
        "order": [("D", "LeftHand"), ("D", "RightHand"), ("D", "LeftFoot"), ("D", "RightFoot"), ("A", "LeftHand"), ("A", "RightHand")],
        "start": {"timing": (startup, active, recovery), "keys": start_keys, "tags": {"aim": False},
                  "notes": "Landslide start: chest swells and arms spread wide, then an armored charging shoulder."},
        "notes": "Goran Ultimate 'Landslide': charging shoulder, body-lock crush, suplex, knee slam, shoulder carry and forward drop.",
    }
