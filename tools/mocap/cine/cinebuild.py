"""Ultimate cinematics (round 6): spec modules -> FLThrow1 cinematic + activation FLClip1 modules, checks, review sheets.

  python tools/mocap/cine/cinebuild.py [--only Kael,Sierra] [--roster <roster.json>] [--out <src dir>]
                                       [--sheets <dir>] [--no-write] [--step 10] [--debug]

Each spec module ult_<fighter>.py exposes build(tl) -> spec dict; tl = the fighter's cinematic timeline
{duration, impacts: [frames], endKind, endDistance} (the roster's when --roster has `moves.Ultimate.cinematic`, else the
contract's default template). The cinematic is authored at 60 fps on the sim frames (clip time = frame / 60), so its
impacts land on the timeline exactly; Motion.Cinematic still maps any later roster change onto them.
Roster JSON: lune run tools/mocap/cine/roster_dump.luau src <out.json>.
Docs: docs/design/ultimates.md.
"""
from __future__ import annotations

import argparse
import importlib
import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import twobody as T  # noqa: E402
import cinecommon as C  # noqa: E402
import clipio  # noqa: E402

FOLDER = "Moves.Ultimates"
LICENSE = ("Original hand-keyed two-person animation (FightingLab motion, round 6); key poses sampled from the game's own "
           "move, reaction and fall clips (credited sources)")
SPECS = {"Kael": "ult_kael", "Sierra": "ult_sierra", "Goran": "ult_goran", "Lumi": "ult_lumi", "Rhys": "ult_rhys", "Nia": "ult_nia"}
DEFAULT = {"duration": 210, "impacts": [36, 74, 112, 150, 192], "shares": [0.12, 0.12, 0.16, 0.20, 0.40], "endKind": "FaceUp", "endDistance": 3.2}
DEBUG = [False]


def timeline_for(fighter: str, roster: dict | None) -> dict:
    tl = dict(DEFAULT)
    if roster:
        m = ((roster.get("fighters") or {}).get(fighter) or {}).get("moves", {}).get("Ultimate")
        cin = m.get("cinematic") if isinstance(m, dict) else None
        if isinstance(cin, dict) and cin.get("duration") and cin.get("impacts"):
            imps = cin["impacts"]
            imps = [imps[str(k)] for k in sorted(int(x) for x in imps)] if isinstance(imps, dict) else imps
            tl = {"duration": int(cin["duration"]), "impacts": [int(round(i["frame"])) for i in imps],
                  "shares": [float(i.get("share", 0)) for i in imps], "endKind": cin.get("endKind", "FaceUp"),
                  "endDistance": float(cin.get("endDistance", 3.2)), "source": "roster"}
            if isinstance(m, dict):
                tl["move"] = {k: m.get(k) for k in ("startup", "active", "recovery", "impact", "range", "advance", "name")}
    tl.setdefault("source", "default")
    return tl


def track_channels(P) -> np.ndarray:
    ch = np.stack([T.channels_from_pose(p) for p in P], axis=1)
    for q in (3, 7, 11, 21, 31, 41, 51):
        for i in range(1, ch.shape[1]):
            if float(np.dot(ch[q:q + 4, i], ch[q:q + 4, i - 1])) < 0:
                ch[q:q + 4, i] = -ch[q:q + 4, i]
    return ch


def meta(fps: float, n: int) -> dict:
    return {"fps": fps, "frames": n, "loop": False, "speed": 0.0, "travel": [0.0, 0.0, 0.0]}


def sources_for(spec) -> list[str]:
    ids = ["original:motion"]
    for name in spec.get("clipsUsed", []):
        try:
            for s in T.core_sources(name):
                if s not in ids:
                    ids.append(s)
        except FileNotFoundError:
            pass
    return ids


def clips_used(keys_lists) -> list[str]:
    """Every installed clip a spec samples ("Clip@s" and Displayed:<Fighter> stance clips), for the credits."""
    out = []
    for keys in keys_lists:
        for k in keys:
            ref = k.get("from")
            if isinstance(ref, str):
                if ref.startswith("Displayed:"):
                    import lineup
                    style = T.FIGHTER_STYLE.get(ref[10:].partition("@")[0], "boxer")
                    name = T.stance_clip_name(style)
                elif ref.startswith("style:"):
                    name = T.stance_clip_name(ref[6:])
                else:
                    name = ref.partition("@")[0]
                if name not in out:
                    out.append(name)
    return out


def check_pair(spec, frames, PA, PD, JA, JD) -> dict:
    allow = [tuple(x) for x in spec.get("allow", [])]
    rep = {"pen": [], "penWhere": [], "selfA": [], "selfD": [], "selfWhere": [], "floorA": [], "floorD": [], "twist": (0.0, "")}
    worst_twist = (0.0, "")
    for k, f in enumerate(frames):
        JDa = T.joints_to_other(JD[k])
        pen, where = T.penetration(JA[k], JDa, allow)
        rep["pen"].append(pen)
        rep["penWhere"].append(where)
        sa, swa = T.self_penetration(JA[k])
        sd, swd = T.self_penetration(JD[k])
        rep["selfA"].append(sa)
        rep["selfD"].append(sd)
        rep["selfWhere"].append(swa + "|" + swd)
        rep["floorA"].append(min(JA[k][j][1] for j in JA[k] if not j.startswith("_") and j != "pelvis"))
        rep["floorD"].append(min(JD[k][j][1] for j in JD[k] if not j.startswith("_") and j != "pelvis"))
        for who, J in (("A", JA[k]), ("D", JD[k])):
            for limb in T.LIMBS:
                tw = T.limb_twist(J, limb)
                lim = 105 if limb in T.HANDS else 65
                if tw is not None and abs(tw) > lim and abs(tw) - lim > worst_twist[0]:
                    worst_twist = (abs(tw) - lim, f"f{f} {who}.{limb} {tw:.0f}")
    rep["twist"] = worst_twist
    # planted-foot slide (sole XZ drift between frames while contact >= 0.5), metres
    slide, slide_where = 0.0, ""
    for who, P in (("A", PA), ("D", PD)):
        for i, limb in enumerate(T.FEET):
            for k in range(1, len(P)):
                if (P[k].contact[i] or 0) >= 0.5 and (P[k - 1].contact[i] or 0) >= 0.5:
                    a, b = P[k].limbs[limb]["at"], P[k - 1].limbs[limb]["at"]
                    d = float(math.hypot(a[0] - b[0], a[2] - b[2]))
                    if d > slide:
                        slide, slide_where = d, f"{who}.{limb}@f{frames[k]:g}"
    rep["slide"], rep["slideWhere"] = slide, slide_where
    return rep


JOINT_OF = {"LeftHand": "handL", "RightHand": "handR", "LeftFoot": "ankleL", "RightFoot": "ankleR", "LeftElbow": "elbowL",
            "RightElbow": "elbowR", "LeftKnee": "kneeL", "RightKnee": "kneeR", "Head": "head"}


def strike_gaps(spec, frames, JA, JD) -> list[dict]:
    """At every impact: the distance from the striking limb's tip to its target point on the defender (metres)."""
    out = []
    for g in spec.get("strikes", []):
        f = g["frame"]
        if f not in frames:
            continue
        k = frames.index(f)
        target = T.to_other(T.point(JD[k], g["target"][:3]))
        tip = JA[k][JOINT_OF.get(g["limb"], "handR")]
        out.append({"impact": g.get("impact"), "frame": f, "limb": g["limb"], "gapCm": round(float(np.linalg.norm(tip - target)) * 100, 1)})
    return out


def grip_entries(att: T.Track, dfd: T.Track) -> list[dict]:
    """Held grips (a hand/foot keyed on the SAME partner point with weight 1 across a key segment) -> runtime windows."""
    out = []
    for role, tr in (("Attacker", att), ("Defender", dfd)):
        for limb in T.LIMBS:
            run = None
            for i in range(len(tr.states) - 1):
                a, b = tr.states[i].limbs[limb], tr.states[i + 1].limbs[limb]
                ta = C.runtime_grip(a["grip"]) if a["w"] >= 0.99 else None
                tb = C.runtime_grip(b["grip"]) if b["w"] >= 0.99 else None
                f0, f1 = float(tr.keys[i]["f"]) / 60.0, float(tr.keys[i + 1]["f"]) / 60.0
                if ta is not None and ta == tb:
                    if run is not None and run["target"] == ta and abs(run["to"] - f0) < 1e-9:
                        run["to"] = f1
                    else:
                        if run is not None:
                            out.append(run)
                        run = {"target": ta, "from": f0, "to": f1, "role": role, "limb": limb}
                elif run is not None:
                    out.append(run)
                    run = None
            if run is not None:
                out.append(run)
    entries = []
    for r in out:
        e = {"role": r["role"], "limb": r["limb"], "from": round(r["from"], 4), "to": round(r["to"], 4), "fade": 0.05}
        e.update({k: (list(v) if isinstance(v, tuple) else v) for k, v in r["target"].items()})
        entries.append(e)
    return entries


def end_gap(PD_last, kind: str) -> float:
    ref = T.full_joints(C.end_pose(kind))
    J = T.full_joints(PD_last)
    return max(float(np.linalg.norm(J[k] - ref[k])) for k in ref if not k.startswith("_"))


def render(spec, frames, JA, JD, out: str, step: int = 10, views=("side", "threequarter"), size: int = 230, scale: float = 92):
    impacts = set(spec["impacts"])
    pick = sorted(set(list(range(0, len(frames), step)) + [frames.index(f) for f in impacts if f in frames] + [len(frames) - 1]))
    rows = []
    for view in views:
        panels = []
        for k in pick:
            f = frames[k]
            hl = (255, 60, 60) if f in impacts else None
            jd = T.joints_to_other(JD[k])
            # frame each panel on the pair (the action can leave the start spots, e.g. a throw behind the attacker)
            mid = 0.5 * (np.asarray(JA[k]["pelvis"]) + np.asarray(jd["pelvis"]))
            cx = np.array([mid[0] * 0.5, 0.85, min(max(mid[2], T.DIST[0] * 0.5 - 1.2), T.DIST[0] * 0.5 + 1.2)])
            panels.append(T.draw_bodies([(jd, T.COL_D), (JA[k], T.COL_A)], view, size, scale, cx, f"{view[:5]} f{f}", hl))
        per_row = 11
        for i in range(0, len(panels), per_row):
            rows.append(panels[i:i + per_row])
    T.sheet(rows, out, f"{spec['name']}  {spec['fighter']}.Ultimate  {spec['duration']} f, impacts {spec['impacts']} (red)  end {spec['endKind']}  "
                       f"dist {T.DIST[0]:.2f} m ({T.DIST[0] / T.LEG:.3f} L)  [attacker white/blue/red, defender green/teal/olive]")


def build_cine(spec, out_dir: str | None, sheets: str | None, step: int) -> dict:
    T.DIST[0] = spec["dist"]
    dur = spec["duration"]
    frames = list(range(0, dur + 1))
    att = T.Track(spec["attacker"], "A")
    dfd = T.Track(spec["defender"], "D")
    PA, PD, JA, JD = T.solve_pair(att, dfd, frames, spec.get("order", []))
    T.auto_contacts(PA, JA, att.explicit_contact, 1 / 60)
    T.auto_contacts(PD, JD, dfd.explicit_contact, 1 / 60)
    T.sanitize_contacts(PA, 1 / 60)
    T.sanitize_contacts(PD, 1 / 60)
    cha, chd = track_channels(PA), track_channels(PD)
    rep = check_pair(spec, frames, PA, PD, JA, JD)
    if DEBUG[0]:
        for k, f in enumerate(frames):
            if f % 2 == 0 or f in spec["impacts"]:
                print(f"  f{f:3d} pen {rep['pen'][k] * 100:5.1f} {rep['penWhere'][k]:24s} selfA {rep['selfA'][k] * 100:5.1f} selfD {rep['selfD'][k] * 100:5.1f} "
                      f"{rep['selfWhere'][k]:30s} floorA {rep['floorA'][k] * 100:5.1f} floorD {rep['floorD'][k] * 100:5.1f}")
    gaps = strike_gaps(spec, frames, JA, JD)
    spec["clipsUsed"] = sorted(C.USED)
    ids = sources_for(spec)
    name = spec["name"]
    result = {
        "name": name, "fighter": spec["fighter"], "duration": dur, "impacts": spec["impacts"], "endKind": spec["endKind"],
        "endGapCm": round(end_gap(PD[-1], spec["endKind"]) * 100, 2), "penMaxCm": round(max(rep["pen"]) * 100, 1),
        "penWhere": rep["penWhere"][int(np.argmax(rep["pen"]))], "penFrame": frames[int(np.argmax(rep["pen"]))],
        "selfMaxCm": round(max(max(rep["selfA"]), max(rep["selfD"])) * 100, 1),
        "selfWhere": rep["selfWhere"][int(np.argmax([max(a, b) for a, b in zip(rep["selfA"], rep["selfD"])]))],
        "floorMinCm": round(min(min(rep["floorA"]), min(rep["floorD"])) * 100, 1),
        "twist": rep["twist"], "slideCm": round(rep["slide"] * 100, 1), "slideWhere": rep["slideWhere"], "strikeGaps": gaps,
        "problems": [f"f{f} pen {rep['pen'][k] * 100:.0f} {rep['penWhere'][k]}" for k, f in enumerate(frames) if rep["pen"][k] > 0.04 and f % 2 == 0]
        + [f"f{f} self {max(rep['selfA'][k], rep['selfD'][k]) * 100:.0f} {rep['selfWhere'][k]}" for k, f in enumerate(frames) if max(rep["selfA"][k], rep["selfD"][k]) > 0.04 and f % 2 == 0],
        "sources": ids,
    }
    grips = list(spec.get("grips", [])) + grip_entries(att, dfd)
    m = {"fighter": spec["fighter"], "move": "Ultimate", "impact": spec["impacts"][0] / dur, "distance": spec["dist"] / T.LEG,
         "impacts": [f / dur for f in spec["impacts"]], "hits": spec.get("hits"), "endKind": spec["endKind"],
         "release": (spec["release"] / dur) if spec.get("release") is not None else None, "grips": grips,
         "camera": [dict(k, t=k["f"] / dur) for k in spec.get("camera", [])] or None}
    for k in m["camera"] or []:
        k.pop("f", None)
    result["grips"] = len(grips)
    if out_dir:
        text, clipped = clipio.throw_module(name, (cha, meta(60, cha.shape[1])), (chd, meta(60, chd.shape[1])), m,
                                            "hand-keyed (tools/mocap/cine/cinebuild.py)", LICENSE, spec.get("notes", ""), ids)
        text = text.replace("generated by OV6/tools/mocap/convert.py", "generated by tools/mocap/cine/cinebuild.py")
        path = os.path.join(out_dir, f"ReplicatedStorage.FightingLab.Client.Motion.Clips.{FOLDER}.{name}.luau")
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)
        result["bytes"] = len(text.encode("utf-8"))
        result["clipped"] = clipped
        result["path"] = path
    if sheets:
        os.makedirs(sheets, exist_ok=True)
        render(spec, frames, JA, JD, os.path.join(sheets, f"{name}.sheet.png"), step)
    return result


def build_start(spec, out_dir: str | None) -> dict | None:
    """The Ultimate move's own FLClip1 (startup with the activation, the catch strike on the first active frame, the
    whiff/block recovery), bound to <Fighter>/Ultimate like any attack clip."""
    st = spec.get("start")
    if not st:
        return None
    startup, active, recovery = st["timing"]
    total = startup + active + recovery
    tr = T.Track(st["keys"], "S")
    frames = list(range(0, total + 1, 2))
    P, J = T.solve_single(tr, frames)
    T.auto_contacts(P, J, tr.explicit_contact, 1 / 30)
    T.sanitize_contacts(P, 1 / 30)
    ch = track_channels(P)
    dur = (ch.shape[1] - 1) / 30
    name = spec["name"] + "Start"
    ids = sources_for(spec)
    m = meta(30, ch.shape[1])
    first = startup + 1
    m["contact"] = (first / 60) / dur
    m["recover"] = ((first + active) / 60) / dur
    m["tags"] = st.get("tags", {"aim": False})
    m["fighter"], m["move"] = spec["fighter"], "Ultimate"
    result = {"name": name, "contactFrame": first}
    if out_dir:
        text, _ = clipio.luau_module(name, ch, m, "hand-keyed (tools/mocap/cine/cinebuild.py)", LICENSE, st.get("notes", ""), ids)
        text = text.replace("generated by OV6/tools/mocap/convert.py", "generated by tools/mocap/cine/cinebuild.py")
        path = os.path.join(out_dir, f"ReplicatedStorage.FightingLab.Client.Motion.Clips.{FOLDER}.{name}.luau")
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)
        result["path"] = path
        result["bytes"] = len(text.encode("utf-8"))
    return result


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--roster", default=None, help="roster JSON (roster_dump.luau); default: the contract's template timeline")
    ap.add_argument("--out", default=os.path.join(T.REPO, "src"))
    ap.add_argument("--sheets", default=None)
    ap.add_argument("--no-write", action="store_true")
    ap.add_argument("--step", type=int, default=10)
    ap.add_argument("--debug", action="store_true")
    ap.add_argument("--report", default=None)
    args = ap.parse_args()
    DEBUG[0] = args.debug
    roster = json.load(open(args.roster, encoding="utf-8")) if args.roster else None
    only = [x for x in args.only.split(",") if x]
    results = []
    for fighter, mod in SPECS.items():
        if only and fighter not in only:
            continue
        try:
            spec_mod = importlib.import_module(mod)
        except ModuleNotFoundError:
            print(f"{fighter}: no spec ({mod}.py)")
            continue
        tl = timeline_for(fighter, roster)
        C.USED.clear()
        spec = spec_mod.build(tl)
        spec.setdefault("duration", tl["duration"])
        spec.setdefault("impacts", tl["impacts"])
        spec.setdefault("endKind", tl["endKind"])
        r = build_cine(spec, None if args.no_write else args.out, args.sheets, args.step)
        s = build_start(spec, None if args.no_write else args.out)
        r["timeline"] = tl.get("source")
        r["start"] = s
        results.append(r)
        print(json.dumps({k: v for k, v in r.items() if k not in ("sources",)}, default=str))
    if args.report:
        with open(args.report, "w", encoding="utf-8") as fh:
            json.dump(results, fh, indent=1, default=str)
    return 0


if __name__ == "__main__":
    sys.exit(main())
