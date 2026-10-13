"""Builders for the round-6 move, stance and reaction clips (registered with movebuild.clip; see movebuild.py).

Conventions: sim frames at 60 fps; the contact lands on ctx.first (startup + 1), ctx.rec = startup + active + 1 (a
string follow-up starts there), the clip ends on ctx.total on the displayed stance. Poses are sampled from the game's
own installed clips (credits follow them); library axes: +x the fighter's right, +y up, +z toward the opponent.
"""
from __future__ import annotations

import numpy as np

import twobody as T
import cinecommon as C
import movebuild as MB
from movebuild import clip, standard, seg, P, nudge, body, air, chain, mirror_ed, bell


def built_pose(ctx, key: str | None, frame: float, name: str | None = None) -> T.Pose:
    """The solved pose of another registered clip of this fighter at a sim frame (a string follow-up of a NEW move
    starts on that move's recover-mark pose; frame None = that move's recover mark)."""
    for e in MB.REGISTRY:
        if e["fighter"] == ctx.fighter and ((key and e["key"] == key) or (name and e["name"] == name)):
            move = ctx.roster["fighters"][ctx.fighter]["moves"].get(e["key"]) if e["key"] else None
            sub = MB.Ctx(ctx.fighter, e["key"], move, ctx.roster)
            res = e["fn"](sub)
            keys = res[0] if isinstance(res, tuple) else res
            f = sub.rec if frame is None else (sub.startup + sub.active if frame == "active_end" else frame)
            Ps, _ = T.solve_single(T.Track(keys, "prev"), [f])
            return C.resolved(Ps[0])
    raise KeyError(f"{ctx.fighter}: no registered clip {key or name}")


def posed(p: T.Pose, **kw) -> T.Pose:
    """A pose with relative key edits applied (rot_plus, waist_plus, neck_plus, limb dicts), as a plain pose."""
    tr = T.Track([C.pk(0, p, **kw)], "tmp")
    q, _ = tr.sample(0)
    return C.resolved(q)


def kick_chain(ctx, prev_clip: str, prev_key: str) -> str:
    """A kick string follow-up's first pose: the previous move's clip at its last active frame (moveTime of
    startup + active: between the contact and the recover marks)."""
    pm = ctx.roster["fighters"][ctx.fighter]["moves"][prev_key]
    _, _, dur, c, r = C.clip_info(prev_clip)
    a = max(int(pm["active"]), 1)
    return f"{prev_clip}@{c + (r - c) * (a - 1) / a:.4f}"


def held(f0: float, f1: float, p: T.Pose, **kw) -> list:
    return [C.pk(f0, p, **kw), C.pk(f1, p, **kw)]


# =====================================================================================================================
# KAEL (boxer)
# =====================================================================================================================

def planted(p: T.Pose, ref: T.Pose) -> T.Pose:
    """p with the feet put back where they stand in ref (whole-body rotations keep the feet on the floor)."""
    q = C.resolved(p)
    for limb in T.FEET:
        for k in ("at", "rot", "pole"):
            q.limbs[limb][k] = np.array(ref.limbs[limb][k], float).copy()
    return q


def tilted(p: T.Pose, deg) -> T.Pose:
    """The upper body (pelvis, chest, arms) turned about the pelvis by deg [x, y, z]; the feet stay planted."""
    return planted(C.rotated(p, deg), p)


def kael_pocket(ctx, x: float = 0.0, drop: float = 0.22, roll: float = 0.0) -> T.Pose:
    """The Pocket: a low coiled crouch, head forward-down behind the lead shoulder, gloves at the cheeks."""
    p = C.shifted(ctx.stance, [x, -drop, 0.03])
    return posed(tilted(p, [-11, 4, roll]), waist_plus=[-5, 0, 0], neck_plus=[3, 0, 0])


@clip("Kael", "OneTwoShin", "Kicks")
def kael_onetwoshin(ctx):
    """1,2,3: as the right straight returns, a lead-leg toe kick snaps into the shin, gloves high."""
    return standard(ctx, "Kick_Kael_ShinKick", start=kick_chain(ctx, "Strike_Kael_OneTwo", "OneTwo"), lead=4, a="windup")


@clip("Kael", "HookOverhand", "Strikes", tags={"aimWeight": 0.25})
def kael_hookoverhand(ctx):
    """2,1,2: out of the body hook he rises and loops the right hand over the top onto the temple."""
    return standard(ctx, "Strike_Kael_Overhand", start=C.at("Strike_Kael_CrossHook", "recover"), lead=4, a="windup")


@clip("Kael", "RibRoller", "Strikes")
def kael_ribroller(ctx):
    """b+1: a short stepping lead hook to the floating ribs that rolls up and through (tumble on an airborne body)."""
    roll_up = nudge("LeftHand", [0.0, 0.14, 0.02], ctx.first + 4, 6)
    return standard(ctx, "Strike_Kael_LiverHook", lead=3, a="windup", edit=chain(body([0, -0.05, 0]), roll_up))


@clip("Kael", "Pocket", "Kicks", tags={"aim": False})
def kael_pocket_entry(ctx):
    """3+4: knees bend fast and the head drops under the line of a high punch into the Pocket (stance entry)."""
    return [C.pk(0, ctx.stance), C.pk(ctx.first, kael_pocket(ctx, 0.0, 0.24), "out"), C.pk(ctx.total, kael_pocket(ctx, -0.02, 0.23, 2))]


@clip("Kael", None, "Core", name="Kael_Pocket", loop=40, fps=30)
def kael_pocket_loop(ctx):
    """The Pocket loop: a low bob-and-roll (U shape) side to side, creeping forward."""
    return [C.pk(0, kael_pocket(ctx, -0.08, 0.17, 6)), C.pk(10, kael_pocket(ctx, 0.0, 0.27, 0)),
            C.pk(20, kael_pocket(ctx, 0.08, 0.17, -6)), C.pk(30, kael_pocket(ctx, 0.0, 0.27, 0)),
            C.pk(40, kael_pocket(ctx, -0.08, 0.17, 6))]


@clip("Kael", None, "Core", name="Kael_PocketExit")
def kael_pocket_exit(ctx):
    """Rises out of the Pocket back into the upright boxing guard."""
    return [C.pk(0, kael_pocket(ctx, 0.0, 0.24)), C.pk(10, ctx.stance)], 10


@clip("Kael", "PocketShovel", "Strikes")
def kael_pocketshovel(ctx):
    """PKT+1: from the Pocket a lead shovel hook (half hook, half uppercut) into the liver, staying low."""
    up = nudge("LeftHand", [0.04, 0.08, 0.04], ctx.first, 4)
    return standard(ctx, "Strike_Kael_LiverHook", start=kael_pocket(ctx, 0.0, 0.24), lead=3, a="windup",
                    edit=chain(body([0, -0.14, 0.02]), up))


@clip("Kael", "PocketUppercut", "Strikes")
def kael_pocketuppercut(ctx):
    """PKT+2: from the bottom of the bob the rear uppercut springs straight up, legs extending onto the toes."""
    dip = body([0, -0.16, 0], peak=3, width=7)
    return standard(ctx, "Strike_Kael_RisingUppercut", start=kael_pocket(ctx, 0.0, 0.28), lead=3, a="windup", edit=dip)


# =====================================================================================================================
# SIERRA (kickboxer)
# =====================================================================================================================

def south(ctx) -> T.Pose:
    """Southpaw: her displayed kickboxing stance mirrored (right foot and right glove forward)."""
    return C.mirrored(ctx.stance)


def sierra_elbow_poses(ctx):
    c = C.resolved(P("Strike_Sierra_Cross", "windup"))
    c.limbs["RightHand"]["at"] = np.array([-0.30, 1.72, 0.32])
    c.limbs["RightHand"]["pole"] = T.unit([0.6, 0.1, 0.8])
    c.q["root"] = T.qn(T.qmul(T.eq([0, 34, 0]), c.q["root"]))
    w = C.resolved(P("Strike_Sierra_Cross", "windup"))
    w.limbs["RightHand"]["at"] = np.array([0.36, 1.70, 0.12])
    w.limbs["RightHand"]["pole"] = T.unit([0.9, 0.1, -0.2])
    return w, c


def switch_keys(f0: float, f1: float, a: T.Pose, b: T.Pose, hop: float = 0.06) -> list:
    """A hop-switch of the feet from pose a to pose b between f0 and f1 (both feet leave the floor half way)."""
    mid = C.raised(b, hop)
    return [C.pk(f0, a), C.pk((f0 + f1) * 0.5, mid, contact={"LeftFoot": 0.0, "RightFoot": 0.0}), C.pk(f1, b, "in")]


@clip("Sierra", "JabTeepHigh", "Kicks")
def sierra_jabteephigh(ctx):
    """1,3,4: the teep foot lands forward and the rear leg whips a full roundhouse to the head."""
    return standard(ctx, "Kick_Sierra_HighRoundhouse", start=kick_chain(ctx, "Kick_Sierra_JabKick", "JabKick"), lead=4, a="windup")


@clip("Sierra", "JabTeepLow", "Kicks")
def sierra_jabteeplow(ctx):
    """1,3,3: the teep leg re-chambers and chops an inside low kick into the lead calf, hands high."""
    return standard(ctx, "Kick_Kael_ShinKick", start=kick_chain(ctx, "Kick_Sierra_JabKick", "JabKick"), lead=3, a="windup")


@clip("Sierra", "SlashElbow", "Strikes", tags={"aimWeight": 0.25})
def sierra_slashelbow(ctx):
    """2: a short step in, the rear elbow lifts and slices down and across the brow."""
    w, c = sierra_elbow_poses(ctx)
    return [C.pk(0, ctx.stance), C.pk(ctx.first - 6, C.pose_at(w, 0.04), rot_plus=[0, -14, 0]),
            C.pk(ctx.first, C.pose_at(c, 0.12), "snap"), C.pk(ctx.rec, C.pose_at(c, 0.12), rot_plus=[0, 8, 0]),
            C.pk(ctx.rec + 6, C.pose_at(P("Strike_Sierra_Cross", "recover"), 0.06)), C.pk(ctx.total, ctx.stance)]


@clip("Sierra", "TeepSpinKick", "Kicks")
def sierra_teepspinkick(ctx):
    """3,4,4: the head kick carries her round into a spinning back kick, heel first into the stomach."""
    return standard(ctx, "Kick_Sierra_SpinningBackKick", start=kick_chain(ctx, "Kick_Sierra_TeepKick", "TeepKick"), lead=6, a=0.08)


@clip("Sierra", "Southpaw", "Kicks", tags={"aim": False})
def sierra_southpaw_entry(ctx):
    """3+4: a small hop-switch of the feet into Southpaw (right leg and right glove forward)."""
    return [C.pk(0, ctx.stance)] + switch_keys(1, ctx.first, ctx.stance, south(ctx), 0.05) + [C.pk(ctx.total, south(ctx))]


@clip("Sierra", None, "Core", name="Sierra_Southpaw", loop=138, fps=30)
def sierra_southpaw_loop(ctx):
    """Southpaw loop: the mirrored, bouncing kickboxing stance."""
    _, _, dur, _, _ = C.clip_info("Stance_Kickboxer")
    keys = []
    for i in range(0, 7):
        t = dur * i / 6.0
        keys.append(C.pk(138 * i / 6.0, C.mirrored(T.base_pose(f"Displayed:Sierra@{t % dur:.4f}"))))
    return keys


@clip("Sierra", None, "Core", name="Sierra_SouthpawExit")
def sierra_southpaw_exit(ctx):
    """Hop-switch back to the orthodox stance."""
    return switch_keys(0, 8, south(ctx), ctx.stance) + [C.pk(10, ctx.stance)], 10


def southpaw_move(ctx, src: str, a="start", edit=None, lead: float = 2.0) -> list:
    """A Southpaw follow-up: the src clip mirrored (orthodox lead/rear swap sides), out of the southpaw stance and
    back to the orthodox stance with a hop-switch in the recovery (the sim leaves the stance with the move)."""
    keys = standard(ctx, src, start=south(ctx), lead=lead, a=a, edit=chain(mirror_ed, edit) if edit else mirror_ed, tail=10)
    end = keys.pop()
    hop = C.pk(ctx.total - 5, C.raised(ctx.stance, 0.05), contact={"LeftFoot": 0.0, "RightFoot": 0.0})
    return keys + [C.pk(ctx.total - 9, south(ctx)), hop, end]


@clip("Sierra", "SouthpawHeadKick", "Kicks")
def sierra_southpawheadkick(ctx):
    """SPW+4: a fast lead (right) round kick to the head with almost no chamber."""
    return southpaw_move(ctx, "Kick_Sierra_AngleKick", a="windup", edit=nudge("RightFoot", [0.0, 0.34, 0.02], ctx.first, 6))


@clip("Sierra", "SouthpawBodyKick", "Kicks")
def sierra_southpawbodykick(ctx):
    """SPW+3: the left (rear) leg's full roundhouse into the liver, shin flat on the ribs."""
    return southpaw_move(ctx, "Kick_Sierra_HighRoundhouse", a="windup", edit=nudge("LeftFoot", [0.0, -0.30, -0.04], ctx.first, 6))


@clip("Sierra", "SouthpawLowKick", "Kicks")
def sierra_southpawlowkick(ctx):
    """SPW+d+4: the right (lead) leg chops a short low kick into the inside of the lead knee."""
    return southpaw_move(ctx, "Kick_Kael_ShinKick", a="windup")


# =====================================================================================================================
# GORAN (grappler)
# =====================================================================================================================

def forearm_poses(ctx, lead: bool):
    """Cocked and landed poses of the clubbing forearm smash (lead = the left arm)."""
    hand, s = ("LeftHand", -1.0) if lead else ("RightHand", 1.0)
    w = C.resolved(P("Strike_Goran_Jab", "windup"))
    w.limbs[hand]["at"] = np.array([0.62 * s, 1.46, -0.02])
    w.limbs[hand]["pole"] = T.unit([0.6 * s, 0.3, -0.7])
    c = C.resolved(P("Strike_Goran_Jab", "contact"))
    c.limbs[hand]["at"] = np.array([-0.10 * s, 1.50, 0.36 if not lead else 0.52])
    c.limbs[hand]["pole"] = T.unit([0.8 * s, 0.25, 0.55])
    return w, c


@clip("Goran", "JabHammerForearm", "Strikes", tags={"aimWeight": 0.25})
def goran_jabhammerforearm(ctx):
    """1,2,1: he steps through and clubs the lead forearm horizontally into the side of the head."""
    w, c = forearm_poses(ctx, True)
    return [C.pk(0, C.pose_at(C.at("Strike_Goran_JabHammer", "recover"))), C.pk(ctx.first - 7, w, rot_plus=[0, 22, 0]),
            C.pk(ctx.first, C.pose_at(c, 0.14), "snap", rot_plus=[0, -30, 0], lift=(0.06, 0.0)),
            C.pk(ctx.rec, C.pose_at(c, 0.14), rot_plus=[0, -40, 0]), C.pk(ctx.rec + 9, C.pose_at(ctx.stance, 0.08), rot_plus=[0, -12, 0]),
            C.pk(ctx.total, ctx.stance, lift=(0.04, 0.04))]


@clip("Goran", "JabHammerStomp", "Kicks")
def goran_jabhammerstomp(ctx):
    """1,2,3: the lead knee lifts high and the boot heel stamps down onto the lead foot and shin."""
    return standard(ctx, "Kick_Goran_Stomp", start=kick_chain(ctx, "Strike_Goran_JabHammer", "JabHammer"), lead=4, a="windup")


@clip("Goran", "BootForearm", "Strikes", tags={"aimWeight": 0.25})
def goran_bootforearm(ctx):
    """3,2: the push-kick foot lands and the rear forearm swings across into the side of the head."""
    w, c = forearm_poses(ctx, False)
    return [C.pk(0, C.pose_at(C.at("Kick_Goran_PushKick", "recover"))), C.pk(ctx.first - 7, w, rot_plus=[0, -22, 0]),
            C.pk(ctx.first, C.pose_at(c, 0.10), "snap", rot_plus=[0, 30, 0]),
            C.pk(ctx.rec, C.pose_at(c, 0.10), rot_plus=[0, 40, 0]), C.pk(ctx.rec + 8, C.pose_at(ctx.stance, 0.06), rot_plus=[0, 12, 0]),
            C.pk(ctx.total, ctx.stance, lift=(0.04, 0.04))]


@clip("Goran", "BootForearmHammer", "Strikes", tags={"aimWeight": 0.25})
def goran_bootforearmhammer(ctx):
    """3,2,2: both fists rise high above his head (armored), then the double club crashes onto the collarbone."""
    return standard(ctx, "Strike_Goran_DoubleHammer", start=built_pose(ctx, "BootForearm", None), lead=5, a="windup")


def bear_trap(ctx, breath: float = 0.0) -> T.Pose:
    p = C.shifted(ctx.stance, [0.0, -0.14 - breath, 0.02])
    p = posed(p, neck_plus=[-10, 0, 0], rot_plus=[-4, 0, 0],
              LeftHand={"at": [-0.64, 1.24 + breath, 0.26], "pole": [-0.5, -0.8, -0.2]},
              RightHand={"at": [0.66, 1.22 + breath, 0.24], "pole": [0.5, -0.8, -0.2]})
    return p


@clip("Goran", "BearTrap", "Kicks", tags={"aim": False})
def goran_beartrap(ctx):
    """3+4: he sinks his hips and opens both arms wide at chest height, palms forward, inviting the hit."""
    return [C.pk(0, ctx.stance), C.pk(ctx.first, bear_trap(ctx), "out"), C.pk(14, bear_trap(ctx, 0.015)),
            C.pk(ctx.rec - 1, bear_trap(ctx)), C.pk(ctx.rec + 12, C.shifted(ctx.stance, [0, -0.06, 0])), C.pk(ctx.total, ctx.stance)]


# =====================================================================================================================
# LUMI (acrobat)
# =====================================================================================================================

AERIAL = 26
# Kick_Lumi_PalmHeel's spinning heel is fully out ~0.06 s after the clip's own contact mark (the chamber).
HEEL_C, HEEL_R = ("s", 0.315), ("s", 0.365)


@clip("Lumi", None, "Core", name="Lumi_Aerial")
def lumi_aerial(ctx):
    """Aerial: a no-hands cartwheel toward the opponent, horizontal at the top, landing on the lead foot (26 frames)."""
    keys = seg("Kick_Lumi_CartwheelKick", "start", 0.6, 0, AERIAL - 6, 2.0, air(0.30, 10.5, 8.5))
    keys.append(C.pk(AERIAL, ctx.stance))
    return keys, AERIAL


@clip("Lumi", "Aerial", "Kicks", tags={"aim": False})
def lumi_aerial_entry(ctx):
    """3+4: the first frames of the Aerial (the stance plays Lumi_Aerial whole)."""
    keys = [C.pk(f * ctx.total / 11.0, built_pose(ctx, None, f, "Lumi_Aerial")) for f in range(0, 12)]
    return keys


@clip("Lumi", "PalmHeelHook", "Kicks")
def lumi_palmheelhook(ctx):
    """1,4,4: the spin keeps going into a second turn; the rear heel hooks round at head height."""
    return standard(ctx, "Kick_Lumi_PalmHeel", start=kick_chain(ctx, "Kick_Lumi_PalmHeel", "PalmHeel"), lead=2, a=0.15, c=HEEL_C, r=HEEL_R,
                    edit=nudge("RightFoot", [0.0, 0.50, 0.0], ctx.first, 7))


@clip("Lumi", "PalmHeelSweep", "Kicks")
def lumi_palmheelsweep(ctx):
    """1,4,3: out of the spinning heel she drops onto one hand and the lead leg sweeps along the floor."""
    return standard(ctx, "Kick_Nia_LowSpin", start=kick_chain(ctx, "Kick_Lumi_PalmHeel", "PalmHeel"), lead=6, a="start")


@clip("Lumi", "CrescentFlyingKick", "Kicks")
def lumi_crescentflyingkick(ctx):
    """3,4,4: she jumps off the crescent leg and shoots the rear leg out flat into the chest in mid-air."""
    return standard(ctx, "Kick_Lumi_ScissorKick", start=kick_chain(ctx, "Kick_Lumi_SnapCrescent", "SnapCrescent"), lead=3, a="start",
                    edit=nudge("RightFoot", [0.0, -0.12, 0.0], ctx.first, 6))


@clip("Lumi", "AerialSplit", "Kicks")
def lumi_aerialsplit(ctx):
    """AER+3: still in the air out of the cartwheel, a split and the lead foot snaps into the chest."""
    return standard(ctx, "Kick_Lumi_VaultKick", start=built_pose(ctx, None, 14, "Lumi_Aerial"), lead=3, a="windup",
                    edit=air(0.10, ctx.first, 8))


@clip("Lumi", "AerialHeel", "Kicks")
def lumi_aerialheel(ctx):
    """AER+4: she lands on the lead foot and the rear heel swings straight up under the chin (launcher)."""
    return standard(ctx, "Kick_Nia_RisingTornado", start=built_pose(ctx, None, 16, "Lumi_Aerial"), lead=3, a="windup")


@clip("Lumi", "AerialSweep", "Kicks")
def lumi_aerialsweep(ctx):
    """AER+d+3: she lands low on hands and knee and the lead leg sweeps a fast arc along the floor."""
    return standard(ctx, "Kick_Nia_LowSpin", start=built_pose(ctx, None, 16, "Lumi_Aerial"), lead=3, a="start")


# =====================================================================================================================
# RHYS (karate)
# =====================================================================================================================

def still_water(ctx, breath: float = 0.0) -> T.Pose:
    p = C.shifted(ctx.stance, [0.0, -0.07 + breath, -0.07])
    p.limbs["LeftFoot"]["at"] = p.limbs["LeftFoot"]["at"] + np.array([0.02, 0.0, -0.10])
    return posed(p, waist_plus=[-2.0 * breath / 0.01, 0, 0],
                 LeftHand={"at": [-0.02, 1.22 + breath, 0.50], "pole": [-0.7, -0.4, 0.2]},
                 RightHand={"at": [0.24, 0.98, -0.04], "pole": [0.6, -0.3, -0.6]})


@clip("Rhys", "ReverseHighKick", "Kicks")
def rhys_reversehighkick(ctx):
    """1,2,4: as the reverse punch returns, the rear instep snaps to the temple."""
    return standard(ctx, "Kick_Rhys_PunchKick", start=kick_chain(ctx, "Strike_Rhys_ReversePunch", "ReversePunch"), lead=4, a="windup")


@clip("Rhys", "ReverseLowKick", "Kicks")
def rhys_reverselowkick(ctx):
    """1,2,3: the lead sole thrusts down into the opponent's lead knee (a low stopping kick)."""
    return standard(ctx, "Kick_Rhys_FrontSnap", start=kick_chain(ctx, "Strike_Rhys_ReversePunch", "ReversePunch"), lead=5, a="windup",
                    edit=chain(nudge("LeftFoot", [0.0, -0.62, -0.06], ctx.first, 6), body([0.0, -0.05, 0.0], ctx.first, 8)))


@clip("Rhys", "PunchKickAxe", "Kicks")
def rhys_punchkickaxe(ctx):
    """2,4,4: the head-kick leg rises again and the heel chops down (axe kick)."""
    return standard(ctx, "Kick_Rhys_AxeKick", start=kick_chain(ctx, "Kick_Rhys_PunchKick", "PunchKick"), lead=4, a="windup")


@clip("Rhys", "LowParry", "Strikes", tags={"aim": False})
def rhys_lowparry(ctx):
    """db+1: he sinks into a low front stance and the lead forearm sweeps down and out across the shin line."""
    low = C.shifted(ctx.stance, [0.0, -0.20, 0.02])
    a = posed(low, LeftHand={"at": [-0.02, 0.66, 0.44], "pole": [-0.8, 0.1, 0.3]})
    b = posed(low, rot_plus=[0, -8, 0], LeftHand={"at": [-0.44, 0.52, 0.30], "pole": [-0.7, 0.4, 0.2]})
    return [C.pk(0, ctx.stance), C.pk(ctx.first, a, "out"), C.pk(ctx.first + 6, b), C.pk(ctx.rec - 1, b),
            C.pk(ctx.rec + 10, C.shifted(ctx.stance, [0.0, -0.08, 0.0])), C.pk(ctx.total, ctx.stance)]


@clip("Rhys", "StillWater", "Kicks", tags={"aim": False})
def rhys_stillwater_entry(ctx):
    """3+4: the lead foot slides back into a short back-weighted stance, the lead open hand extends."""
    return [C.pk(0, ctx.stance), C.pk(ctx.first, still_water(ctx), "out"), C.pk(ctx.total, still_water(ctx))]


@clip("Rhys", None, "Core", name="Rhys_StillWater", loop=60, fps=30)
def rhys_stillwater_loop(ctx):
    """Still Water: perfectly still except a slow breath."""
    return [C.pk(0, still_water(ctx)), C.pk(30, still_water(ctx, 0.012)), C.pk(60, still_water(ctx))]


@clip("Rhys", None, "Core", name="Rhys_StillWaterExit")
def rhys_stillwater_exit(ctx):
    """Brings the lead foot back and returns to the long front stance."""
    return [C.pk(0, still_water(ctx)), C.pk(10, ctx.stance)], 10


@clip("Rhys", "StillStrike", "Strikes")
def rhys_stillstrike(ctx):
    """STW+1: the open lead hand closes and shoots straight to the solar plexus with a small slide."""
    return standard(ctx, "Strike_Rhys_Jab", start=still_water(ctx), lead=2, a="windup",
                    edit=chain(nudge("LeftHand", [0.0, -0.20, 0.0], ctx.first, 8), body([0, 0, 0.08], ctx.first, 9)))


@clip("Rhys", "StillReverse", "Strikes")
def rhys_stillreverse(ctx):
    """STW+2: hips snap square and the rear fist drives up under the chin, legs extending (launcher)."""
    return standard(ctx, "Strike_Rhys_ReversePunch", start=still_water(ctx), lead=3, a="windup",
                    edit=nudge("RightHand", [0.0, 0.16, -0.02], ctx.first + 2, 8))


# =====================================================================================================================
# NIA (kung fu)
# =====================================================================================================================

def coil(ctx, k: float = 0.0) -> T.Pose:
    """The Coil: low, shoulders turned away, weight on the lead foot, palms drawn back at the hip (k = palm circle
    phase, 0..1)."""
    p = C.shifted(ctx.stance, [0.0, -0.10, 0.04])
    p = tilted(p, [0, -36, 0])
    cx, cy = 0.035 * np.cos(2 * np.pi * k), 0.035 * np.sin(2 * np.pi * k)
    return posed(p, neck_plus=[0, 30, 0],
                 LeftHand={"at": [0.16 + cx, 1.00 + cy, 0.18], "pole": [-0.5, -0.8, -0.2]},
                 RightHand={"at": [0.30 - cx, 0.98 - cy, -0.10], "pole": [0.5, -0.7, -0.5]})


@clip("Nia", "DoubleChopLow", "Kicks")
def nia_doublechoplow(ctx):
    """1,1,3: after the two chops she sinks low and the lead foot snaps a short kick into the shin."""
    return standard(ctx, "Kick_Kael_ShinKick", start=kick_chain(ctx, "Strike_Nia_DoubleChop", "DoubleChop"), lead=3, a="windup",
                    edit=body([0.0, -0.08, 0.0], ctx.first, 12))


@clip("Nia", "PalmKickHigh", "Kicks")
def nia_palmkickhigh(ctx):
    """2,3,4: the snap-kick foot lands and the rear leg swings a straight-legged outside crescent across the face."""
    return standard(ctx, "Kick_Lumi_CrescentKick", start=kick_chain(ctx, "Kick_Nia_PalmKick", "PalmKick"), lead=4, a="windup")


@clip("Nia", "Coil", "Kicks", tags={"aim": False})
def nia_coil_entry(ctx):
    """3+4: she winds her whole body like a spring into the Coil."""
    return [C.pk(0, ctx.stance), C.pk(ctx.first, coil(ctx), "out"), C.pk(ctx.total, coil(ctx, 0.05))]


@clip("Nia", None, "Core", name="Nia_Coil", loop=48, fps=30)
def nia_coil_loop(ctx):
    """The Coil loop: wound up, palms slowly circling at the hip."""
    return [C.pk(48 * i / 4.0, coil(ctx, i / 4.0)) for i in range(5)]


@clip("Nia", None, "Core", name="Nia_CoilExit")
def nia_coil_exit(ctx):
    """Unwinds back to the open kung fu stance, palms forward."""
    return [C.pk(0, coil(ctx)), C.pk(10, ctx.stance)], 10


@clip("Nia", "CoilWhirl", "Kicks")
def nia_coilwhirl(ctx):
    """COIL+4: the coil releases into a full turn; the rear heel whips round into the ribs."""
    return standard(ctx, "Kick_Lumi_PalmHeel", start=coil(ctx), lead=2, a=0.15, c=HEEL_C, r=HEEL_R)


@clip("Nia", "CoilWhirl2", "Kicks")
def nia_coilwhirl2(ctx):
    """COIL+4,4: the spin keeps going; off the lead foot the same leg whips a flat circle at head height."""
    return standard(ctx, "Kick_Nia_TornadoKick", start=built_pose(ctx, "CoilWhirl", "active_end"), lead=3, a="windup")


@clip("Nia", "CoilWhirl3", "Kicks")
def nia_coilwhirl3(ctx):
    """COIL+4,4,4: a last, lower, heavier spinning heel into the stomach; she finishes crouched, one palm forward."""
    low = body([0.0, -0.10, 0.0], ctx.first + 6, 14)
    return standard(ctx, "Kick_Lumi_PalmHeel", start=built_pose(ctx, "CoilWhirl2", "active_end"), lead=2, a=0.15, c=HEEL_C, r=HEEL_R,
                    edit=chain(low, nudge("RightFoot", [0.0, -0.10, 0.0], ctx.first, 6)))


# =====================================================================================================================
# Reactions
# =====================================================================================================================

@clip("*", None, "Core", name="AirTumble", fps=30)
def air_tumble(ctx):
    """Tumble extender: the juggled body rolls over in the air (a full turn about its long axis)."""
    base = C.resolved(P("Juggle", 0.45))
    J = T.full_joints(base)
    axis = np.asarray(J["head"]) - np.asarray(J["pelvis"])
    return [C.pk(f, C.rotated_axis(base, axis, -90.0 * i)) for i, f in enumerate((0, 6, 12, 18, 24))] + [C.pk(30, P("Juggle", 0.6))], 30

@clip("Lumi", "SnapKick", "Kicks")
def lumi_snapkick(ctx):
    """3 (round 6): Lumi's own fast lead front snap kick (the round-5 clip, refclips/Kick_Lumi_SnapKickR5) thrown off a
    small hop: both feet off the floor over frames 3-9 (low crush), landing on the support foot by the contact; the
    same timing marks, so its last active frame is still the crescent follow-up's first pose."""
    return standard(ctx, "Kick_Lumi_SnapKickR5", lead=0, a="start", edit=air(0.08, 6, 7))