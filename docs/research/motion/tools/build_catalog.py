"""Build catalog.json for FightingLab mocap research.

Curated specs (source file + label + kind) -> automatic segment bounds, contact frame, acting side,
stance, target direction. Run:  python build_catalog.py   (writes ../catalog.json)
Frame numbers are 0-based indices into the file's frames (AMC frame label = index + 1).
"""
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from mocap import load_motion, CANON  # noqa: E402
from events import CI, floor_y, find_peaks, classify_punch, elbow_angle, smooth  # noqa: E402

M = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CMU_INDEX = json.load(open(os.path.join(M, "work", "cmu_index.json")))
CMU_FPS = {f'{t["subject"]:02d}_{t["trial"]:02d}': float(t["fps"]) for t in CMU_INDEX["trials"]}
CMU_DESC = {f'{t["subject"]:02d}_{t["trial"]:02d}': t["desc"] for t in CMU_INDEX["trials"]}

LIC_CMU = "CMU Graphics Lab Motion Capture Database terms: free for all uses; may be copied, modified, redistributed; may be included in commercially-sold products; may not be resold directly (even converted)."
CREDIT_CMU = "The data used in this project was obtained from mocap.cs.cmu.edu. The database was created with funding from NSF EIA-0196217."
LIC_ACCAD = "CC BY 3.0 (https://creativecommons.org/licenses/by/3.0/)"
CREDIT_ACCAD = "Motion capture data from the Open Motion Project by ACCAD/The Ohio State University (https://accad.osu.edu/research/motion-lab/mocap-system-and-data), licensed under CC BY 3.0."
ACCAD_ZIP = "https://accad.osu.edu/sites/accad.osu.edu/files/{}_bvh.zip"
LIC_QUAT = "CC0 1.0 Universal (public domain dedication) - License.txt in the pack; itch.io page: 'Free to use in personal, educational and commercial projects. (CC0 License)'"
CREDIT_QUAT = "Animations: Universal Animation Library by Quaternius (CC0) - credit optional."
QUAT_URL = {"UAL1": "https://quaternius.itch.io/universal-animation-library", "UAL2": "https://quaternius.itch.io/universal-animation-library-2"}
LIC_STY = "CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/) - 100STYLE page: 'This work is licensed under a Creative Commons Attribution 4.0 International License.'"
STUD_M = 0.28  # Roblox: 1 stud ~ 0.28 m at default avatar scale
CREDIT_STY = "The 100STYLE Dataset - Ian Mason (CC BY 4.0), https://www.ianxmason.com/100style/"
STY_HTML = os.path.join(M, "work", "100style.html")
# 100STYLE was evaluated (sheets) but adds little for a fighter (curved walk paths, T-pose segments, style walks).
# Nothing is catalogued by default; add stems here to include them again.
STY_INCLUDE = set()
# (file stem, label, quality, notes, window seconds or None=whole)
STY = [
    ("Crouched_ID", "crouch-idle", 3, "crouched idle (style 'Crouched')", 6.0),
    ("Crouched_FW", "crouch-walk", 3, "crouched walk forward", 4.0),
    ("Crouched_BW", "crouch-walk-back", 3, "crouched walk backward", 4.0),
    ("Crouched_SW", "crouch-sidestep", 3, "crouched sideways walk", 4.0),
    ("ShieldedLeft_ID", "stance-guard", 2, "idle with left arm shielding the face", 6.0),
    ("ShieldedLeft_FW", "walk-forward-guard", 2, "walk forward with arm shield", 4.0),
    ("Punch_ID", "style-punch", 2, "idle while throwing punches (style 'Punch')", 6.0),
    ("Punch_FW", "style-punch", 2, "walking forward while punching", 4.0),
    ("Punch_BW", "style-punch", 2, "walking backward while punching", 4.0),
    ("Punch_SW", "style-punch", 2, "sideways walk while punching", 4.0),
    ("Kick_ID", "style-kick", 2, "idle while kicking (style 'Kick')", 6.0),
    ("Kick_FW", "style-kick", 2, "walking forward while kicking", 4.0),
    ("KarateChop_ID", "style-chop", 2, "idle with karate chops", 6.0),
    ("Sweep_ID", "style-sweep", 2, "idle with sweeping motion (style 'Sweep') - check content", 6.0),
    ("Elated_ID", "victory", 2, "elated idle", 6.0),
    ("Proud_ID", "victory", 2, "proud idle (chest out)", 6.0),
    ("Depressed_ID", "defeat", 3, "depressed idle (slumped)", 6.0),
    ("Neutral_ID", "idle-stand", 2, "neutral idle (reference)", 6.0),
]

# Quaternius (hand-keyed, stylised; converted GLB(_RM, root motion) -> BVH with Blender 5.0, 30 fps, meters, Z-up file)
QUAT = [
    ("UAL1", "Hit_Head", "hit-head", "hit", 3, "short head-hit flinch (14 f); hand-keyed"),
    ("UAL1", "Hit_Chest", "hit-body", "hit", 3, "short body/chest hit flinch (11 f); hand-keyed"),
    ("UAL2", "Hit_Knockback", "hit-knockback", "hit", 3, "heavy hit knocked back (26 f, root motion); hand-keyed"),
    ("UAL2", "Idle_Shield_Break", "stagger", "hit", 2, "guard-break stagger (shield pose, arms differ)"),
    ("UAL1", "Death01", "ko-fall", "none", 3, "death / KO collapse to the floor"),
    ("UAL2", "LayToIdle", "getup-face-up", "none", 3, "lying -> stand (quick getup)"),
    ("UAL1", "Roll", "roll", "none", 2, "forward combat roll (root motion)"),
    ("UAL1", "Punch_Jab", "punch-jab", "hand", 2, "stylised jab (hand-keyed)"),
    ("UAL1", "Punch_Cross", "punch-cross", "hand", 2, "stylised cross (hand-keyed)"),
    ("UAL2", "Melee_Hook", "punch-hook", "hand", 2, "stylised hook (hand-keyed); recovery = Melee_Hook_Rec"),
    ("UAL1", "Crouch_Idle_Loop", "crouch-idle", "none", 2, "crouch idle loop"),
    ("UAL1", "Jump_Land", "land", "none", 2, "landing from a jump"),
    ("UAL2", "NinjaJump_Land", "land", "none", 2, "landing from a high jump (crouched)"),
    ("UAL2", "Yes", "victory", "none", 2, "'yes' fist-pump style gesture"),
    ("UAL2", "Idle_No_Loop", "defeat", "none", 2, "head-shake 'no' idle"),
    ("UAL2", "Idle_FoldArms_Loop", "taunt", "none", 2, "folded-arms idle"),
]

# locomotion takes that are cut into single steps: (entry id, axis)
STEP_TAKES = {
    "accad-male2-e3-advance": "fwd", "accad-male2-e4-quickadvance": "fwd", "accad-male2-e7-superfastadvance": "fwd",
    "accad-male2-e5-retreat": "fwd", "accad-male2-e6-quickretreat": "fwd",
    "accad-male2-e9-sidestepleft": "side", "accad-male2-e10-sidestepright": "side",
    "accad-male1-c24-quicksidestepleft": "side", "accad-male1-c25-quicksidestepright": "side",
    "cmu-76_11": "fwd", "cmu-102_27": "side", "cmu-102_28": "side", "cmu-83_66": "side", "cmu-83_19": "side",
}

# ------------------------------------------------------------------------------------------- specs
# ACCAD Male2 (martial artist). kind: hand | foot | block | evade | none
A2 = [
    ("D1_StandToReady", "stance-ready-in", "none", 4, "relaxed stand -> fighting stance"),
    ("D2_WalkToReady", "stance-ready-in", "none", 3, "walk in -> fighting stance"),
    ("D3_RunToReady", "stance-ready-in", "none", 3, "run in -> fighting stance"),
    ("D4_ReadyToRelax", "stance-ready-out", "none", 3, "fighting stance -> relaxed stand"),
    ("D7_WalkToBow", "bow", "none", 3, "walk in and bow (intro gesture)"),
    ("D8_BowToReady", "bow", "none", 4, "bow -> fighting stance (intro)"),
    ("D9_Victory1", "victory", "none", 4, "victory celebration"),
    ("D10_Victory2", "victory", "none", 4, "victory celebration 2"),
    ("D9_WarmUpToReadyToWarmUp", "warmup", "none", 3, "warm-up bounce/shake -> ready -> warm-up"),
    ("D11_ReadyToTaunt1ToReady", "taunt", "none", 3, "taunt from stance"),
    ("D12_ReadyToTaunt1ToReady", "taunt", "none", 3, "taunt from stance (take 2)"),
    ("D13_CrouchToReady", "crouch-up", "none", 4, "crouch -> fighting stance"),
    ("D14_ReadyToCrouch", "crouch-down", "none", 4, "fighting stance -> crouch"),
    ("D15_SwitchStance", "stance-switch", "none", 3, "switch lead foot"),
    ("D16_SwitchStanceMore", "stance-switch", "none", 3, "switch lead foot several times"),
    ("E1_TurnAroundRight", "stance-turn", "none", 2, "turning in stance (long)"),
    ("E2_TurnAroundLeft", "stance-turn", "none", 2, "turning in stance (long)"),
    ("E3_Advance", "walk-forward-stance", "none", 4, "step forward in fighting stance"),
    ("E4_QuickAdvance", "dash-forward", "none", 4, "quick forward step/dash in stance"),
    ("E5_Retreat", "walk-back-stance", "none", 4, "step back in fighting stance"),
    ("E6_QuickRetreat", "backdash", "none", 4, "quick backward step in stance"),
    ("E7_SuperFastAdvance", "dash-forward", "none", 3, "very fast advance (lunge)"),
    ("E8_Bounce", "stance-bounce", "none", 4, "boxing-style bounce in stance"),
    ("E9_SideStepLeft", "sidestep-left", "none", 4, "sidestep to the actor's left in stance"),
    ("E10_SideStepRight", "sidestep-right", "none", 4, "sidestep to the actor's right in stance"),
    ("E1_JabLeft", "punch-jab", "hand", 4, ""),
    ("E2_JabRight", "punch-jab", "hand", 4, ""),
    ("E3_CrossLeft", "punch-cross", "hand", 4, ""),
    ("E4_CrossRight", "punch-cross", "hand", 4, ""),
    ("E5_HookLeft", "punch-hook", "hand", 4, ""),
    ("E6_HookRight", "punch-hook", "hand", 4, ""),
    ("E7_UppercutLeft", "punch-uppercut", "hand", 4, ""),
    ("E8_UppercutRight", "punch-uppercut", "hand", 4, ""),
    ("E9_BodyHookLeft", "punch-body-hook", "hand", 4, ""),
    ("E10_BodyHookRight", "punch-body-hook", "hand", 4, ""),
    ("E11_BackfistLeft", "punch-backfist", "hand", 3, ""),
    ("E12_BackfistRight", "punch-backfist", "hand", 3, ""),
    ("E13_BodyCrossLeft", "punch-body-cross", "hand", 4, ""),
    ("E14_BodyCrossRight", "punch-body-cross", "hand", 4, ""),
    ("E15_BodyJabRight", "punch-body-jab", "hand", 3, ""),
    ("E16_BodyJabLeft", "punch-body-jab", "hand", 3, ""),
    ("E11_BlockLeftHigh", "guard-high", "block", 4, "high block / parry"),
    ("E13_BlockRightHigh", "guard-high", "block", 4, "high block / parry"),
    ("E17_BlockMiddleHigh", "guard-high", "block", 3, "two-arm high cover"),
    ("E15_BlockLeftMiddle", "guard-mid", "block", 4, "mid block"),
    ("E16_BlockRightMiddle", "guard-mid", "block", 4, "mid block"),
    ("E12_BlockLeftLow", "guard-low", "block", 4, "low block"),
    ("E14_BlockRightLow", "guard-low", "block", 4, "low block"),
    ("E18_BlockMiddleLow", "guard-low", "block", 3, "two-arm low block"),
    ("E19_DodgeLeft", "dodge", "evade", 4, "upper-body slip/dodge"),
    ("E20_DodgeRight", "dodge", "evade", 4, "upper-body slip/dodge"),
    ("E21_DuckLeft", "duck", "evade", 4, "duck under a high attack"),
    ("E22_DuckRight", "duck", "evade", 4, "duck under a high attack"),
    ("G1_SidekickLeadingLeft", "kick-side", "foot", 4, "lead-leg side kick"),
    ("G3_SidekickLeadingRight", "kick-side", "foot", 4, "lead-leg side kick"),
    ("G2_FrontKick", "kick-front", "foot", 4, ""),
    ("G17_PushKickLeft", "kick-push", "foot", 4, "push/teep kick"),
    ("G18_PushKickRight", "kick-push", "foot", 4, "push/teep kick"),
    ("G8_RoundhouseLeft", "kick-roundhouse", "foot", 4, "rear-leg roundhouse"),
    ("G9_RoundhouseRight", "kick-roundhouse", "foot", 3, "rear-leg roundhouse (short take)"),
    ("G9_RoundhouseRightT2", "kick-roundhouse", "foot", 4, "rear-leg roundhouse take 2"),
    ("G10_RoundhouseLeadingLeft", "kick-roundhouse", "foot", 4, "lead-leg roundhouse"),
    ("G11_RoundhouseLeadingRight", "kick-roundhouse", "foot", 4, "lead-leg roundhouse"),
    ("G14_RoundhouseBodyLeft", "kick-roundhouse-mid", "foot", 4, "roundhouse to the body"),
    ("G15_RoundhouseBodyRight", "kick-roundhouse-mid", "foot", 4, "roundhouse to the body"),
    ("G4_SpinningBackKick", "kick-spinning-back", "foot", 4, ""),
    ("G5_BackKick", "kick-back", "foot", 3, ""),
    ("G6_AxeKick", "kick-axe", "foot", 3, ""),
    ("G7_Capoeira", "kick-capoeira", "foot", 2, "capoeira kick (stylised)"),
    ("G12_CrescentLeft", "kick-crescent", "foot", 3, ""),
    ("G13_CrescentRight", "kick-crescent", "foot", 3, ""),
    ("G16_DoubleKick", "kick-double", "foot", 3, "two kicks same leg"),
    ("G19_ReverseSpinCrescentLeft", "kick-spin-crescent", "foot", 3, ""),
    ("G20_ReverseSpinCrescentRight", "kick-spin-crescent", "foot", 3, ""),
    ("Extended_1", "combo-sequence", "none", 3, "free-form martial arts sequence (mix of strikes/kicks); mine for strings"),
    ("Extended_2", "combo-sequence", "none", 3, "rapid punching sequence (many strikes)"),
    ("Extended_3", "combo-sequence", "none", 3, "long free-form sequence incl. low positions (53 s)"),
    ("Form_1", "kata-form", "none", 3, "martial arts form"),
    ("A7_Crouch", "crouch-idle", "none", 3, "stand -> crouch -> stand (not a fighting crouch)"),
    ("A8_CrouchToLie", "lie-down-controlled", "none", 2, "controlled lie-down (not a fall)"),
    # A9_Lie / A10_LieToCrouch (and Female1 A09/A10) removed: marker glitches (limbs below floor, head at 2.6 m)
]
A_OTHER = [
    ("Male1", "A9_LieDown", "lie-ground", "none", 3, "lying still"),
    ("Male1", "A10_LieToCrouch", "getup-generic", "none", 3, "lying -> crouch"),
    ("Male1", "A8_CrouchToLie", "lie-down-controlled", "none", 2, ""),
    ("Male1", "C24_QuickSideStepLeft", "sidestep-left", "none", 2, "generic quick sidestep (not in fighting stance)"),
    ("Male1", "C25_QuickSideStepRight", "sidestep-right", "none", 2, "generic quick sidestep"),
]

# CMU: (trial, label, kind, quality, notes, seg) ; seg None = auto / whole
# kind: strikes:'hand'|'foot' (auto-detect events, keep best k) ; 'getup' ; 'fall' ; 'none'
CMU = [
    # karate (subject 135, "Martial Arts Walks", Shotokan-style techniques)
    ("135_04", "kick-front", "foot-multi", 4, "karate mae-geri while stepping forward", 4),
    ("135_07", "kick-roundhouse", "foot-multi", 3, "karate mawashi-geri while stepping", 4),
    ("135_11", "kick-side", "foot-multi", 3, "karate yoko-geri", 4),
    ("135_09", "punch-lunge", "hand-multi", 3, "karate oi-zuki (stepping straight punch)", 4),
    ("135_05", "guard-low", "hand-multi", 2, "karate gedan-barai (low sweeping block)", 2),
    ("135_10", "guard-mid", "hand-multi", 2, "karate shuto-uke (knife-hand block)", 2),
    ("135_01", "kata-form", "none", 3, "karate kata Bassai (51 s)", None),
    ("135_06", "kata-form", "none", 3, "karate kata Heian Shodan", None),
    ("135_02", "kata-form", "none", 3, "karate kata Empi (has a jump)", None),
    # front kicks / punches drills (subject 144, female)
    ("144_05", "kick-front", "foot-multi", 3, "right front kick drill (12 reps)", 3),
    ("144_09", "kick-front", "foot-multi", 3, "left front kick drill (12 reps)", 3),
    ("144_20", "punch-straight", "hand-multi", 3, "right punch drill (30 reps)", 3),
    ("144_13", "punch-straight", "hand-multi", 3, "left punch drill (22 reps)", 3),
    ("144_07", "guard-mid", "hand-multi", 2, "left blocks drill", 2),
    ("144_26", "guard-mid", "hand-multi", 2, "right blocks drill", 2),
    ("143_23", "punch-straight", "hand-multi", 2, "untrained punching", 2),
    ("141_14", "punch-kick-mix", "hand-multi", 2, "untrained punch and kick", 2),
    ("86_06", "knee", "knee-multi", 2, "walking, kicking, punching, knee kicking (long)", 3),
    # boxing (shadow boxing)
    ("14_01", "boxing-shadow", "box", 3, "shadow boxing, bouncing stance; auto-classified punches", 6),
    ("14_02", "boxing-shadow", "box", 3, "shadow boxing", 4),
    ("14_03", "boxing-shadow", "box", 3, "shadow boxing", 4),
    ("13_17", "boxing-shadow", "box", 3, "shadow boxing", 4),
    ("13_18", "boxing-shadow", "box", 3, "shadow boxing", 3),
    ("15_13", "boxing-shadow", "box", 3, "shadow boxing (78 s)", 4),
    ("17_10", "boxing-shadow", "box", 3, "shadow boxing", 3),
    ("80_10", "boxing-shadow", "box", 2, "boxing (60 fps)", 3),
    ("02_05", "punch-straight", "hand-multi", 2, "repeated right punch/strike", 2),
    # getups / lying
    ("140_01", "getup-face-down", "getup", 4, "get up from lying face down", None),
    ("140_02", "getup-face-down", "getup", 4, "get up from lying face down", None),
    ("140_03", "getup-side", "getup", 3, "get up from lying on side", None),
    ("140_04", "getup-side", "getup", 3, "get up from lying on side", None),
    ("140_08", "getup-face-up", "getup", 4, "get up from lying on back", None),
    ("140_09", "getup-face-up", "getup", 4, "get up from lying on back", None),
    ("139_16", "getup-face-down", "getup", 3, "lie down + get up (same capture as 77_16)", None),
    ("139_18", "getup-face-up", "getup", 3, "get up from lying on back (same capture as 77_18)", None),
    # falls / stumbles / reactions
    ("90_16", "fall-forward", "fall", 3, "fall on face", None),
    ("90_17", "fall-backward", "fall", 3, "banana-peel slip, fall backward", None),
    ("90_18", "fall-backward", "fall", 3, "rug-pull fall (feet swept, backward)", None),
    ("85_15", "fall-spin", "fall", 2, "90-degree twists then fall (breakdance)", None),
    ("23_12", "stagger", "none", 3, "subject B is stumbled into by A (push reaction)", None),
    ("91_59", "stagger", "none", 2, "360 small stumble", None),
    # footwork / evasion / stance
    ("76_04", "stance-guard", "none", 3, "defensive guard pose", None),
    ("77_03", "stance-guard", "none", 3, "ready stance (60 fps)", None),
    ("76_03", "dodge", "none", 3, "avoid attacker (evasive moves)", None),
    ("76_11", "backdash", "none", 3, "quick large steps backwards", None),
    ("76_09", "walk-back-stance", "none", 2, "walking backwards (avoidance)", None),
    ("76_01", "walk-back-stance", "none", 3, "walk backwards then attack with a punch", None),
    ("102_27", "footwork-shuffle", "none", 3, "defensive side-to-side shuffle (basketball)", None),
    ("102_28", "footwork-shuffle", "none", 3, "defensive side-to-side shuffle (basketball)", None),
    ("83_66", "sidestep-right", "none", 2, "short sidestep right (generic)", None),
    ("83_19", "sidestep-left", "none", 2, "medium sidestep left (generic)", None),
    ("139_09", "duck", "none", 3, "ducking (same capture as 77_09)", None),
    ("136_09", "crouch-walk", "none", 2, "walk crouched", None),
    ("140_07", "idle-stand", "none", 2, "neutral standing idle (not a fight stance)", None),
    # emotes (60 fps actor clips)
    ("79_69", "victory", "none", 3, "very happy (60 fps)", None),
    ("80_43", "victory", "none", 3, "happy (60 fps)", None),
    ("79_94", "victory", "none", 3, "flexing (60 fps)", None),
    ("79_74", "defeat", "none", 3, "upset (60 fps)", None),
    ("79_71", "defeat", "none", 3, "sad (60 fps)", None),
    # jump kicks (priority B, flashy)
    ("90_05", "kick-jump", "foot-multi", 2, "jump kick", 1),
    ("88_06", "kick-jump-spin", "foot-multi", 2, "jump and spin kick (60 fps)", 1),
]


def rel(p):
    return os.path.relpath(p, M).replace("\\", "/")


def horiz_angle(v):
    return float(np.degrees(np.arctan2(v[0], v[2])))


def unit_xz(v):
    v = np.array([v[0], 0.0, v[2]])
    return v / (np.linalg.norm(v) + 1e-9)


def hips_forward(c, f):
    a, b = max(0, f - 3), min(len(c), f + 4)
    lat = (c[a:b, CI["lhip"]] - c[a:b, CI["rhip"]]) + (c[a:b, CI["lshoulder"]] - c[a:b, CI["rshoulder"]])
    lat = unit_xz(lat.mean(0))
    return unit_xz(np.cross(lat, [0, 1, 0]))


def stance_at(c, f, t):
    lz = (c[f, CI["lankle"]] - c[f, CI["pelvis"]]) @ t
    rz = (c[f, CI["rankle"]] - c[f, CI["pelvis"]]) @ t
    if abs(lz - rz) < 0.08:
        return "square"
    return "left-forward" if lz > rz else "right-forward"


def displacement(c, j, f0, f1):
    rest = c[f0:f1, j].mean(0)
    return np.linalg.norm(c[:, j] - rest, axis=1)


def single_action(c, fps, kind, t):
    """Contact + acting side + window for a short single-action clip."""
    n = len(c)
    rest_n = max(2, int(0.2 * fps))
    if kind in ("hand", "block"):
        effs = ["lhand", "rhand"]
    elif kind == "foot":
        effs = ["lankle", "rankle"]
    else:
        effs = ["headtop"]
    disp = {e: displacement(c, CI[e], 0, rest_n) for e in effs}
    eff = max(effs, key=lambda e: disp[e].max())
    side = "left" if eff.startswith("l") else ("right" if eff.startswith("r") else None)
    if kind in ("hand", "foot"):
        p0 = c[0, CI["pelvis"]]
        reach = (c[:, CI[eff]] - p0) @ t
        # only consider frames where the effector is clearly moving away from rest
        valid = disp[eff] > 0.35 * disp[eff].max()
        r = np.where(valid, reach, -1e9)
        contact = int(np.argmax(r))
    else:
        contact = int(np.argmax(disp[eff]))
    d = disp[eff]
    dmax = d[contact] if d[contact] > 0 else d.max()
    on = contact
    while on > 0 and d[on] > 0.1 * dmax:
        on -= 1
    rec = contact
    while rec < n - 1 and d[rec] > 0.15 * dmax:
        rec += 1
    start = max(0, on - int(0.25 * fps))
    end = min(n - 1, rec + int(0.35 * fps))
    sdir = unit_xz(c[contact, CI[eff]] - c[contact, CI["pelvis"]])
    return contact, side, start, end, eff, sdir


def multi_events(c, fps, kind, t, k):
    """Detect repeated strikes along fixed target direction t; return best k events."""
    if kind == "hand-multi":
        effs = ["lhand", "rhand"]
        thr = 0.40
    elif kind == "knee-multi":
        effs = ["lknee", "rknee"]
        thr = 0.30
    else:
        effs = ["lankle", "rankle"]
        thr = 0.45
    events = []
    for e in effs:
        if kind == "knee-multi":
            x = c[:, CI[e], 1] - c[:, CI["pelvis"], 1]  # knee rises toward/above hip height
            pk = find_peaks(x, fps, -0.05, 0.4, 0.25)
            vals = x
        else:
            x = smooth((c[:, CI[e]] - c[:, CI["pelvis"]]) @ t, max(1, int(fps * 0.03)))
            pk = find_peaks(x, fps, thr, 0.3, 0.2)
            vals = x
        for p in pk:
            events.append((float(vals[p]), p, e))
    events.sort(reverse=True)
    chosen = []
    for v, p, e in events:
        if all(abs(p - q) > int(0.5 * fps) for _, q, _ in chosen):
            chosen.append((v, p, e))
        if len(chosen) >= k:
            break
    return sorted(chosen, key=lambda x: x[1])


def boxing_events(c, fps, k):
    fwd_dirs = []
    out = []
    n = len(c)
    for e in ("lhand", "rhand"):
        # local forward from smoothed hips facing (boxer turns slowly)
        lat = (c[:, CI["lhip"]] - c[:, CI["rhip"]]) + (c[:, CI["lshoulder"]] - c[:, CI["rshoulder"]])
        lat[:, 1] = 0
        lat = smooth(lat, int(fps * 1.0))
        lat /= np.linalg.norm(lat, axis=1, keepdims=True) + 1e-9
        fwd = np.cross(lat, [0, 1, 0])
        x = np.einsum("ni,ni->n", c[:, CI[e]] - c[:, CI["chest"]], fwd)
        dist = np.linalg.norm(c[:, CI[e]] - c[:, CI["chest"]], axis=1)
        pk = find_peaks(dist, fps, 0.5, 0.25, 0.18)
        for p in pk:
            out.append((float(dist[p]), p, e, fwd[p]))
    out.sort(key=lambda z: -z[0])
    chosen = []
    for item in out:
        if all(abs(item[1] - q[1]) > int(0.4 * fps) for q in chosen):
            chosen.append(item)
    return sorted(chosen, key=lambda z: z[1]), len(out)


def getup_window(c, fps):
    fl = floor_y(c)
    ph = smooth(c[:, CI["pelvis"], 1] - fl, max(1, int(fps * 0.1)))
    hi = np.percentile(ph, 95)
    n = len(ph)
    # last frame of the lowest plateau before final standing
    stand_idx = np.where(ph > 0.9 * hi)[0]
    end_stand = stand_idx[-1] if len(stand_idx) else n - 1
    low_idx = np.where(ph < 0.25)[0]
    if not len(low_idx):
        return 0, n - 1, None, ph
    # rising phase: last low frame before the final standing frame
    lows_before = low_idx[low_idx < end_stand]
    last_low = lows_before[-1] if len(lows_before) else low_idx[-1]
    up = last_low
    while up < n - 1 and ph[up] < 0.9 * hi:
        up += 1
    start = max(0, last_low - int(0.5 * fps))
    end = min(n - 1, up + int(0.6 * fps))
    return start, end, int(last_low), ph


def fall_window(c, fps):
    fl = floor_y(c)
    ph = smooth(c[:, CI["pelvis"], 1] - fl, max(1, int(fps * 0.05)))
    n = len(ph)
    hi = np.percentile(ph, 90)
    low = np.where(ph < 0.3)[0]
    if not len(low):
        return 0, n - 1, None, ph
    impact = int(low[0])
    st = impact
    while st > 0 and ph[st] < 0.9 * hi:
        st -= 1
    start = max(0, st - int(0.6 * fps))
    end = min(n - 1, impact + int(1.2 * fps))
    return start, end, impact, ph


SKEL = {
    "cmu": "CMU ASF (31 bones, Y-up, 1 unit=0.05644 m)",
    "accad": "ACCAD MotionBuilder BVH (22 joints Hips..ToeBase, Y-up, cm)",
    "quaternius": "Quaternius UE-mannequin-style BVH from Blender (root,pelvis,spine_01-03,neck_01,Head,clavicle/upperarm/lowerarm/hand_l|r + fingers, thigh/calf/foot/ball_l|r; Z-up file, meters)",
    "100style": "100STYLE BVH (Hips, Chest..Chest4, Neck, Head, L/R Collar-Shoulder-Elbow-Wrist, Hip-Knee-Ankle-Toe; Y-up, cm, 60 fps)",
}
LIC = {"cmu": LIC_CMU, "accad": LIC_ACCAD, "quaternius": LIC_QUAT, "100style": LIC_STY}
CREDIT = {"cmu": CREDIT_CMU, "accad": CREDIT_ACCAD, "quaternius": CREDIT_QUAT, "100style": CREDIT_STY}


def standing_height(c):
    fl = floor_y(c)
    return float(np.percentile(c[:, CI["headtop"], 1] - fl, 95))


def contact_metrics(c, contact, eff):
    if contact is None or eff is None:
        return {}
    fl = floor_y(c)
    h = float(c[contact, CI[eff], 1] - fl)
    H = max(1.0, standing_height(c))
    r = h / H
    cls = "high" if r > 0.78 else ("mid" if r > 0.45 else "low")
    return {"contactHeightM": round(h, 2), "contactHeightRatio": round(r, 2), "heightClass": cls}


def step_segments(c, fps, t, axis, max_steps=6):
    """Cut a locomotion take into single steps: one pelvis-speed peak per step, boundaries at speed minima."""
    up = np.array([0.0, 1.0, 0.0])
    d = t if axis == "fwd" else np.cross(up, t)
    p = c[:, CI["pelvis"]]
    x = smooth((p - p[0]) @ d, max(1, int(fps * 0.08)))
    v = np.gradient(x) * fps
    sp = smooth(np.abs(v), max(1, int(fps * 0.1)))
    n = len(x)
    thr = max(0.2, 0.35 * sp.max())
    w = max(1, int(0.15 * fps))
    peaks = []
    for i in range(n):
        if sp[i] >= thr and sp[i] >= sp[max(0, i - w): i + w + 1].max():
            if peaks and i - peaks[-1] <= w:
                continue
            peaks.append(i)
    if not peaks:
        return []
    # merge peaks without a real slowdown between them
    groups = [[peaks[0]]]
    for pk in peaks[1:]:
        prev = groups[-1][-1]
        m = prev + int(np.argmin(sp[prev:pk + 1]))
        if sp[m] > 0.75 * min(sp[prev], sp[pk]):
            groups[-1].append(pk)
        else:
            groups.append([pk])
    bounds = []
    for g0, g1 in zip(groups[:-1], groups[1:]):
        a, b = g0[-1], g1[0]
        bounds.append(a + int(np.argmin(sp[a:b + 1])))
    first = groups[0][0]
    s0 = first
    while s0 > 0 and sp[s0 - 1] <= sp[s0] and sp[s0] > 0.08 * sp[first]:
        s0 -= 1
    last = groups[-1][-1]
    e1 = last
    while e1 < n - 1 and sp[e1 + 1] <= sp[e1] and sp[e1] > 0.08 * sp[last]:
        e1 += 1
    edges = [s0] + bounds + [e1]
    segs = []
    for a, b in zip(edges[:-1], edges[1:]):
        segs.append([a, b])
    # fold tiny segments into their neighbour
    out = []
    for a, b in segs:
        if out and abs(x[b] - x[a]) < 0.15 and np.sign(x[b] - x[a]) == np.sign(x[out[-1][1]] - x[out[-1][0]]):
            out[-1][1] = b
        else:
            out.append([a, b])
    res = []
    for a, b in out:
        if abs(x[b] - x[a]) > 1.2:
            res.extend(split_by_feet(c, fps, d, x, sp, a, b))
        else:
            res.append((a, b, float(x[b] - x[a]), (b - a) / fps, float(sp[a:b + 1].max())))
    return res[:max_steps]


def split_by_feet(c, fps, d, x, sp, a, b):
    """Continuous shuffles: one cycle = each foot moves once; cut where both feet are planted."""
    fv = {}
    for f in ("lankle", "rankle"):
        fx = smooth(c[:, CI[f]] @ d, max(1, int(fps * 0.05)))
        fv[f] = np.abs(np.gradient(fx) * fps)
    tot = fv["lankle"] + fv["rankle"]
    w = max(1, int(0.1 * fps))
    ev = []
    for f, s in fv.items():
        for i in range(a, b + 1):
            if s[i] > 1.5 and s[i] >= s[max(a, i - w): min(b, i + w) + 1].max():
                if not ev or not (ev[-1][1] == f and i - ev[-1][0] <= w):
                    ev.append((i, f))
    ev.sort()
    cycles = [ev[i:i + 2] for i in range(0, len(ev), 2)]
    if len(cycles) < 2:
        return [(a, b, float(x[b] - x[a]), (b - a) / fps, float(sp[a:b + 1].max()))]
    edges = [a]
    for c0, c1 in zip(cycles[:-1], cycles[1:]):
        lo, hi = c0[-1][0], c1[0][0]
        edges.append(lo + int(np.argmin(tot[lo:hi + 1])))
    edges.append(b)
    return [(s, e, float(x[e] - x[s]), (e - s) / fps, float(sp[s:e + 1].max())) for s, e in zip(edges[:-1], edges[1:])]


def entry(eid, source, path, mo, label, start, end, contact, lead, quality, notes, t=None, stance=None, url=None, extra=None):
    e = {
        "id": eid,
        "source": source,
        "license": LIC[source],
        "credit": CREDIT[source],
        "url": url,
        "localFile": rel(path),
        "format": mo.format,
        "fps": mo.fps,
        "skeleton": SKEL[source],
        "frameIndexBase": 0,
        "start": int(start),
        "end": int(end),
        "label": label,
        "contactFrame": None if contact is None else int(contact),
        "lead": lead,
        "quality": quality,
        "notes": notes,
    }
    if t is not None:
        e["targetDirXZ"] = [round(float(t[0]), 3), round(float(t[2]), 3)]
    if stance:
        e["stance"] = stance
    if extra:
        e.update(extra)
    return e


def build():
    cat = []
    # ---------------- ACCAD
    for actor, items in (("Male2", [("Male2",) + x for x in A2]), ("other", A_OTHER)):
        for spec in items:
            who, stem, label, kind, q, notes = spec
            path = os.path.join(M, "raw", "accad", who, f"{who}_{stem}.bvh")
            if not os.path.exists(path):
                print("missing", path)
                continue
            mo = load_motion(path)
            c = mo.canon()
            n = mo.n_frames
            martial = who == "Male2" and stem[0] in "DEG" or stem.startswith(("Extended", "Form"))
            t = np.array([0.0, 0.0, 1.0]) if martial else hips_forward(c, 0)
            contact, lead, start, end = None, None, 0, n - 1
            extra = {}
            if kind in ("hand", "foot", "block", "evade"):
                contact, lead, start, end, eff, sdir = single_action(c, mo.fps, kind, t)
                ang = horiz_angle(sdir)
                if kind in ("hand", "foot"):
                    extra["strikeDirDeg"] = round(ang, 1)
                    extra.update(contact_metrics(c, contact, eff))
                    if abs(ang) > 35:
                        notes = (notes + "; " if notes else "") + f"effector at contact is {ang:.0f} deg off +Z target line (hook/side/spin path)"
                name_side = "left" if "Left" in stem else ("right" if "Right" in stem else None)
                if name_side and lead and name_side != lead and kind in ("hand", "foot"):
                    notes = (notes + "; " if notes else "") + f"NOTE file name says {name_side}, detected moving limb {lead}"
                if kind == "evade":
                    lead = name_side
                    if label == "duck":
                        fl = floor_y(c)
                        contact = int(np.argmin(c[:, CI["headtop"], 1]))
                        notes = (notes + "; " if notes else "") + "contactFrame = lowest head position"
                    else:
                        notes = (notes + "; " if notes else "") + "contactFrame = max head displacement"
            stance = stance_at(c, start, t)
            if not notes:
                notes = f"ACCAD {who} '{stem}': single technique from a fighting stance"
            eid = f"accad-{who.lower()}-{stem.lower().replace('_', '-')}"
            cat.append(entry(eid, "accad", path, mo, label, start, end, contact, lead, q, notes, t, stance,
                             ACCAD_ZIP.format(who) + f" ({who}_{stem}.bvh)", extra))
    # ---------------- CMU
    for trial, label, kind, q, notes, k in CMU:
        s = trial.split("_")[0]
        path = os.path.join(M, "raw", "cmu", s, f"{trial}.amc")
        if not os.path.exists(path):
            print("missing", path)
            continue
        fps = CMU_FPS.get(trial, 120.0)
        mo = load_motion(path, fps=fps)
        c = mo.canon()
        n = mo.n_frames
        url = f"http://mocap.cs.cmu.edu/subjects/{s}/{trial}.amc (skeleton http://mocap.cs.cmu.edu/subjects/{s}/{s}.asf)"
        desc = CMU_DESC.get(trial, "")
        base_notes = f'CMU "{desc}". ' + notes
        t0 = hips_forward(c, 0)
        if kind in ("foot-multi", "hand-multi", "knee-multi"):
            # target line: travel direction if the actor moves > 1 m, else initial facing
            travel = c[-1, CI["pelvis"]] - c[0, CI["pelvis"]]
            t = unit_xz(travel) if np.linalg.norm(travel[[0, 2]]) > 1.0 else t0
            evs = multi_events(c, fps, kind, t, k)
            if not evs:
                cat.append(entry(f"cmu-{trial}", "cmu", path, mo, label, 0, n - 1, None, None, max(1, q - 1),
                                 base_notes + " (no clean events auto-detected; whole take)", t, None, url))
                continue
            for i, (v, p, e) in enumerate(evs):
                a = max(0, p - int(0.55 * fps))
                b = min(n - 1, p + int(0.6 * fps))
                side = "left" if e.startswith("l") else "right"
                lab = label
                extra = {"reachM": round(v, 2)}
                extra.update(contact_metrics(c, p, e))
                if kind == "hand-multi" and label in ("punch-straight", "punch-kick-mix"):
                    kind_p, ang, rise, lf = classify_punch(c, fps, p, side, t)
                    lab = "punch-" + kind_p if label == "punch-straight" else label
                    extra.update({"autoType": kind_p, "elbowDeg": round(ang)})
                cat.append(entry(f"cmu-{trial}-e{i + 1}", "cmu", path, mo, lab, a, b, p, side, q,
                                 base_notes + " Auto-detected event; verify on sheet.", t, stance_at(c, a, t), url, extra))
        elif kind == "box":
            evs, total = boxing_events(c, fps, k)
            counts = {}
            listing = []
            for v, p, e, fwd in evs:
                side = "left" if e.startswith("l") else "right"
                kp, ang, rise, lf = classify_punch(c, fps, p, side, unit_xz(fwd))
                counts[kp] = counts.get(kp, 0) + 1
                listing.append(f"{p}:{side[0].upper()}-{kp}")
            cat.append(entry(f"cmu-{trial}", "cmu", path, mo, "boxing-shadow", 0, n - 1, None, None, q,
                             base_notes + f" Whole take. {len(evs)} punches auto-detected (frame:hand-type): " + " ".join(listing),
                             t0, stance_at(c, 0, t0), url, {"punchCounts": counts}))
            # also emit the k cleanest straight/hook/uppercut punches as separate segments
            best = sorted(evs, key=lambda z: -z[0])[:k]
            for i, (v, p, e, fwd) in enumerate(sorted(best, key=lambda z: z[1])):
                side = "left" if e.startswith("l") else "right"
                kp, ang, rise, lf = classify_punch(c, fps, p, side, unit_xz(fwd))
                a = max(0, p - int(0.4 * fps))
                b = min(n - 1, p + int(0.45 * fps))
                cat.append(entry(f"cmu-{trial}-p{i + 1}", "cmu", path, mo, "punch-" + kp, a, b, p, side, max(1, q - 1),
                                 base_notes + f" Auto-classified '{kp}' (elbow {ang:.0f} deg); boxer's stance {lf}-foot forward. Verify on sheet.",
                                 unit_xz(fwd), stance_at(c, a, unit_xz(fwd)), url,
                                 dict({"autoType": kp}, **contact_metrics(c, p, side[0] + "hand"))))
        elif kind == "getup":
            a, b, last_low, ph = getup_window(c, fps)
            lie_end = last_low
            notes2 = base_notes + f" Getup segment auto-cut (pelvis rises from floor at ~{last_low})."
            cat.append(entry(f"cmu-{trial}", "cmu", path, mo, label, a, b, last_low, None, q, notes2, t0, None, url,
                             {"fullTakeFrames": n}))
        elif kind == "fall":
            a, b, impact, ph = fall_window(c, fps)
            cat.append(entry(f"cmu-{trial}", "cmu", path, mo, label, a, b, impact, None, q,
                             base_notes + " contactFrame = pelvis reaches floor (impact).", t0, None, url, {"fullTakeFrames": n}))
        else:
            cat.append(entry(f"cmu-{trial}", "cmu", path, mo, label, 0, n - 1, None, None, q, base_notes + " Whole take.", t0,
                             stance_at(c, 0, t0), url))
    # ---------------- Quaternius (CC0, hand-keyed)
    for tag, anim, label, kind, q, notes in QUAT:
        path = os.path.join(M, "raw", "quaternius", tag, "bvh", anim + ".bvh")
        if not os.path.exists(path):
            print("missing", path)
            continue
        mo = load_motion(path)
        c = mo.canon()
        n = mo.n_frames
        t = hips_forward(c, 0)
        contact, lead, extra = None, None, {}
        if kind == "hand":
            contact, lead, _, _, eff, sdir = single_action(c, mo.fps, "hand", t)
            extra.update(contact_metrics(c, contact, eff))
        elif kind == "hit":
            d = displacement(c, CI["headtop"], 0, 1)
            extra["peakFrame"] = int(np.argmax(d))
            extra["peakHeadDisplacementM"] = round(float(d.max()), 2)
            contact = 0
            notes += "; contactFrame 0 = impact (reaction starts on the hit)"
        cat.append(entry(f"quat-{tag.lower()}-{anim.lower().replace('_', '-')}", "quaternius", path, mo, label, 0, n - 1,
                         contact, lead, q, notes + f" [Quaternius {tag} '{anim}', from _RM glb]", t, stance_at(c, 0, t),
                         QUAT_URL[tag], extra))
    # ---------------- 100STYLE (CC BY 4.0) locomotion styles
    import re as _re
    sty_links = {}
    if os.path.exists(STY_HTML):
        html = open(STY_HTML, encoding="utf-8").read()
        sty_links = dict((nm[:-4], u.replace("&amp;", "&")) for u, nm in _re.findall(
            r'href="([^"]+)"[^>]*>\s*([A-Za-z]+_(?:BR|BW|FR|FW|ID|SR|SW|TR1|TR2|TR3)\.bvh)\s*<', html))
    for stem, label, q, notes, win in [s for s in STY if s[0] in STY_INCLUDE]:
        path = os.path.join(M, "raw", "100style", stem + ".bvh")
        if not os.path.exists(path):
            print("missing", path)
            continue
        mo = load_motion(path)
        c = mo.canon()
        n = mo.n_frames
        a = 0 if stem.endswith("_ID") else n // 3
        b = min(n - 1, a + int(win * mo.fps)) if win else n - 1
        t = hips_forward(c, a)
        cat.append(entry(f"sty-{stem.lower().replace('_', '-')}", "100style", path, mo, label, a, b, None, None, q,
                         notes + f" (window of a {n / mo.fps:.0f} s take; whole take usable)", t, stance_at(c, a, t),
                         sty_links.get(stem, "https://www.ianxmason.com/100style/") + f" ({stem}.bvh)", {"fullTakeFrames": n}))
    # ---------------- single steps cut from locomotion takes
    byid = {e["id"]: e for e in cat}
    for sid, axis in STEP_TAKES.items():
        parent = byid.get(sid)
        if not parent:
            continue
        mo = load_motion(os.path.join(M, parent["localFile"]), fps=parent["fps"])
        c = mo.canon()
        tx, tz = parent["targetDirXZ"]
        t = unit_xz(np.array([tx, 0.0, tz]))
        steps = step_segments(c, mo.fps, t, axis)
        plab = parent["label"]
        for i, (a, b, travel, dur, vmax) in enumerate(steps):
            if abs(travel) < 0.12:
                continue
            if axis == "side":
                lab = "sidestep-left" if travel > 0 else "sidestep-right"
            elif travel > 0:
                lab = plab if plab in ("walk-forward-stance", "dash-forward") else ("dash-forward" if plab == "backdash" else "walk-forward-stance")
            else:
                lab = plab if plab in ("walk-back-stance", "backdash") else ("backdash" if plab == "dash-forward" else "walk-back-stance")
            frames60 = round(dur * 60)
            note = (f"single step cut from {sid}: travel {travel:+.2f} m ({travel / STUD_M:+.1f} studs) in {dur:.2f} s "
                    f"(~{frames60} frames @60), peak pelvis speed {vmax:.1f} m/s")
            cat.append(entry(f"{sid}-s{i + 1}", parent["source"], os.path.join(M, parent["localFile"]), mo, lab, a, b, None,
                             None, parent["quality"], note, t, stance_at(c, a, t), parent["url"],
                             {"travelM": round(travel, 2), "durationS": round(dur, 2), "travelStuds": round(travel / STUD_M, 1)}))
    return cat


if __name__ == "__main__":
    cat = build()
    out = os.path.join(M, "catalog.json")
    # keep manual overrides (quality/notes/start/end/contact) from catalog_overrides.json
    ov_path = os.path.join(M, "tools", "catalog_overrides.json")
    if os.path.exists(ov_path):
        ov = json.load(open(ov_path))
        for e in cat:
            if e["id"] in ov:
                e.update(ov[e["id"]])
        cat = [e for e in cat if not e.get("drop")]
    json.dump(cat, open(out, "w"), indent=1)
    labels = {}
    for e in cat:
        labels[e["label"]] = labels.get(e["label"], 0) + 1
    print(len(cat), "entries ->", out)
    print(" ".join(f"{k}:{v}" for k, v in sorted(labels.items())))

