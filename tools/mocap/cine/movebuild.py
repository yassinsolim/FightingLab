"""Round-6 move, stance and reaction clips -> FLClip1 modules (hand-keyed on the game's own clip poses).

Every new or changed roster move of round 6 (movesets.md) gets a clip: string enders start on the previous hit's pose
(its clip at the recover mark, where the sim starts the follow-up), the contact lands on startup + 1 and the clip ends
with the move on the fighter's displayed stance. Stances get their entry (bound to the 3+4 entry key), loop and exit
clips (Motion.Clips.Moves.Stances), the tumble extender its airborne reaction (Motion.Clips.Core.AirTumble).

Usage:
  python tools/mocap/cine/movebuild.py --roster <roster.json> [--only Kael,Sierra] [--keys A,B] [--no-write]
                                       [--sheets <dir>] [--report <json>]
Specs: movespecs.py (one builder per clip). Poses come from installed clips ("Clip@seconds", cinecommon.at phases),
so the credits are those clips' sources plus the motion catalog id of the folder.
"""
from __future__ import annotations

import argparse
import json
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.dirname(HERE))

import twobody as T  # noqa: E402
import cinecommon as C  # noqa: E402
import clipio  # noqa: E402

LICENSE = ("Original hand-keyed animation (FightingLab motion, round 6); key poses sampled from the game's own move, "
           "stance and reaction clips (credited sources)")
CATALOG = {"Kicks": "original:motionkicks", "Strikes": "original:motionstrikes", "Stances": "original:motioncore",
           "Core": "original:motioncore"}
# Moves.Strikes accepts accad- ids and original:motionstrikes only; Moves.Kicks accad-, cmu-, quat- and
# original:motionkicks (MotionMoves*Coverage_Test).
ACCEPT = {"Strikes": ("accad-",), "Kicks": ("accad-", "cmu-", "quat-")}

REGISTRY: list = []


class Ctx:
    """What a builder needs: the roster move (timing, limb), the fighter's displayed stance, frame marks."""

    def __init__(self, fighter: str, key: str | None, move: dict | None, roster: dict):
        self.fighter, self.key, self.m, self.roster = fighter, key, move or {}, roster
        self.startup = int(self.m.get("startup", 0))
        self.active = int(self.m.get("active", 0))
        self.recovery = int(self.m.get("recovery", 0))
        self.total = self.startup + self.active + self.recovery
        self.first = self.startup + 1                       # contact: the first active frame
        self.rec = self.startup + self.active + 1           # recover mark: a follow-up starts here
        self.stance = C.stance_of(fighter) if fighter in T.FIGHTER_STYLE else T.base_pose("Stance")

    def stance_def(self, key: str) -> dict:
        return ((self.roster["fighters"][self.fighter].get("stances") or {}).get(key)) or {}


def clip(fighter: str, key: str | None, folder: str, name: str | None = None, loop: int | None = None, tags=None,
         notes: str = "", fps: int = 60):
    """Registers a builder: fn(ctx) -> keys (sim frames at 60 fps). `key` binds the clip to that roster move (the
    clip then spans the move's frames); loop = loop length in sim frames for unbound loop clips; else the builder
    returns (keys, length)."""
    def deco(fn):
        REGISTRY.append({"fighter": fighter, "key": key, "folder": folder, "name": name, "loop": loop, "tags": tags,
                         "notes": notes or (fn.__doc__ or "").strip().split("\n")[0], "fn": fn, "fps": fps})
        return fn
    return deco


# ---- pose helpers -------------------------------------------------------------------------------------------------

def tsec(name: str, phase) -> float:
    _, _, dur, c, r = C.clip_info(name)
    C.USED.add(name)
    if isinstance(phase, tuple):
        return float(phase[1])
    if isinstance(phase, str):
        return {"start": 0.0, "windup": c * 0.5, "load": c * 0.8, "contact": c, "follow": c + (r - c) / 3, "recover": r,
                "end": dur}[phase]
    return float(phase) * dur


def P(name: str, phase) -> T.Pose:
    """Pose of an installed clip at a phase (see cinecommon.at) or a fraction of the clip."""
    return C.pose_at(f"{name}@{tsec(name, phase):.4f}")


def seg(name: str, a, b, f0: float, f1: float, every: float = 2.0, edit=None, ease=None) -> list:
    """Keys f0..f1 (sim frames, both ends) sampling the clip from phase a to phase b (retimed): spins, flips and
    whips keep the source's own path. edit(pose, u, f) -> pose may change each sampled pose (u = 0..1 along the
    segment)."""
    ta, tb = tsec(name, a), tsec(name, b)
    n = max(1, int(round((f1 - f0) / every)))
    out = []
    for i in range(n + 1):
        u = i / n
        f = f0 + (f1 - f0) * u
        p = C.pose_at(f"{name}@{ta + (tb - ta) * u:.4f}")
        if edit:
            p = edit(p, u, f)
        out.append(C.pk(f, p, ease if (ease and i == n) else None))
    return out


def bell(f: float, peak: float, width: float) -> float:
    """1 at peak, 0 beyond +-width (smooth)."""
    x = abs(f - peak) / max(width, 1e-6)
    return 0.0 if x >= 1 else 0.5 + 0.5 * np.cos(np.pi * x)


def nudge(limb: str, d, peak: float, width: float):
    """Edit: moves a limb target by d (metres, pose space) around frame `peak`."""
    d = np.asarray(d, float)

    def ed(p, u, f):
        p = C.resolved(p)
        p.limbs[limb]["at"] = p.limbs[limb]["at"] + d * bell(f, peak, width)
        return p
    return ed


def body(d, peak: float | None = None, width: float = 0.0):
    """Edit: the body (pelvis and hands; a vertical part keeps the feet down = crouch) moved by d metres, all along or
    as a bell around frame `peak`."""
    d = np.asarray(d, float)

    def ed(p, u, f):
        w = 1.0 if peak is None else bell(f, peak, width)
        return C.shifted(p, d * w)
    return ed


def air(dy: float, peak: float | None = None, width: float = 0.0):
    """Edit: the whole body including the feet raised by dy (airborne), all along or as a bell around `peak`."""
    def ed(p, u, f):
        w = 1.0 if peak is None else bell(f, peak, width)
        return C.raised(p, dy * w)
    return ed


def chain(*eds):
    def ed(p, u, f):
        for e in eds:
            if e:
                p = e(p, u, f)
        return p
    return ed


def mirror_ed(p, u, f):
    return C.mirrored(p)


def standard(ctx: Ctx, src: str, start=None, lead: float = 0.0, a="start", b="end", tail: int = 6, every: float = 2.0,
             edit=None, end=None, c="contact", r="recover") -> list:
    """start pose (a Pose or a ref; default the displayed stance) on frame 0 -> the src clip retimed: [a .. contact]
    onto [lead .. first] (contact snap), [contact .. recover] onto [first .. rec], [recover .. b] onto
    [rec .. total - tail], then `end` (default the displayed stance) on the move's last frame."""
    p0 = ctx.stance if start is None else (start if isinstance(start, T.Pose) else C.pose_at(start))
    keys = [C.pk(0, p0)]
    s1 = seg(src, a, c, lead, ctx.first, every, edit)
    keys += s1 if lead > 0 else s1[1:]
    keys[-1]["ease"] = "snap"
    keys += seg(src, c, r, ctx.first, ctx.rec, every, edit)[1:]
    fin = ctx.total - tail
    if fin > ctx.rec + 1:
        keys += seg(src, r, b, ctx.rec, fin, max(every, 3.0), edit)[1:]
    keys.append(C.pk(ctx.total, ctx.stance if end is None else end))
    return keys

# ---- build --------------------------------------------------------------------------------------------------------

def track_channels(Ps) -> np.ndarray:
    ch = np.stack([T.channels_from_pose(p) for p in Ps], axis=1)
    for q in (3, 7, 11, 21, 31, 41, 51):
        for i in range(1, ch.shape[1]):
            if float(np.dot(ch[q:q + 4, i], ch[q:q + 4, i - 1])) < 0:
                ch[q:q + 4, i] = -ch[q:q + 4, i]
    return ch


def sources(folder: str) -> list[str]:
    ids = []
    acc = ACCEPT.get(folder)
    for name in sorted(C.USED):
        try:
            for s in T.core_sources(name):
                if s.startswith("original:"):
                    continue
                if acc and not s.startswith(acc):
                    continue
                if s not in ids:
                    ids.append(s)
        except FileNotFoundError:
            pass
    ids.append(CATALOG.get(folder, "original:motioncore"))
    return ids


def build(entry: dict, roster: dict, out_dir: str | None) -> dict:
    fighter, key = entry["fighter"], entry["key"]
    F = roster["fighters"][fighter] if fighter in roster["fighters"] else None
    move = F["moves"].get(key) if (F and key) else None
    C.USED.clear()
    ctx = Ctx(fighter, key, move, roster)
    res = entry["fn"](ctx)
    keys, length = (res if isinstance(res, tuple) else (res, None))
    loop = entry["loop"]
    fps = entry["fps"]
    if move is not None:
        n_sim = ctx.total
    elif loop:
        n_sim = loop
    else:
        n_sim = int(length)
    step = 60 // fps
    frames = list(range(0, n_sim + (0 if loop else 1), step))
    tr = T.Track(keys, "M")
    Ps, Js = T.solve_single(tr, frames)
    T.auto_contacts(Ps, Js, tr.explicit_contact, step / 60)
    T.sanitize_contacts(Ps, step / 60)
    if move is not None and not any((Ps[k].contact[i] or 0.0) > 0 for k in range(len(Ps)) for i in range(2)):
        # A move that never stands still (spins, cartwheels) still starts or ends on the floor: plant the feet that are
        # down on its first and last frames (the runtime foot lock holds them while the move takes over).
        for k in (0, len(Ps) - 1):
            for i, limb in enumerate(T.FEET):
                if Ps[k].limbs[limb]["at"][1] < 0.045:
                    Ps[k].contact[i] = 1.0
    ch = track_channels(Ps)
    folder = entry["folder"]
    name = entry["name"] or (("Kick_" if folder == "Kicks" else "Strike_") + fighter + "_" + key)
    m = {"fps": fps, "frames": ch.shape[1], "loop": bool(loop), "speed": 0.0, "travel": [0.0, 0.0, 0.0]}
    if move is not None:
        m["contact"] = round(ctx.first / ctx.total, 6)
        m["recover"] = round(ctx.rec / ctx.total, 6)
        m["fighter"], m["move"] = fighter, key
    m["tags"] = entry["tags"] or ({"aimWeight": 0.5} if move is not None else {"aim": False})
    ids = sources(folder)
    res = {"name": name, "folder": folder, "frames": ch.shape[1], "sources": ids, "Ps": Ps, "Js": Js, "frameList": frames, "ctx": ctx}
    floor = min(min(J[j][1] for j in J if not j.startswith("_") and j != "pelvis") for J in Js)
    sp = [T.self_penetration(J) for J in Js]
    worst = max(range(len(sp)), key=lambda i: sp[i][0])
    res["floorMinCm"] = round(floor * 100, 1)
    res["selfMaxCm"] = round(sp[worst][0] * 100, 1)
    res["selfWhere"] = f"{sp[worst][1]}@f{frames[worst]}"
    if out_dir:
        sub = {"Kicks": "Moves.Kicks", "Strikes": "Moves.Strikes", "Stances": "Moves.Stances", "Core": "Core"}[folder]
        text, _ = clipio.luau_module(name, ch, m, "hand-keyed (tools/mocap/cine/movebuild.py)", LICENSE, entry["notes"], ids)
        text = text.replace("generated by OV6/tools/mocap/convert.py", "generated by tools/mocap/cine/movebuild.py")
        path = os.path.join(out_dir, f"ReplicatedStorage.FightingLab.Client.Motion.Clips.{sub}.{name}.luau")
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)
        res["path"] = path
        res["bytes"] = len(text.encode("utf-8"))
    return res


def sheet(results: list, out: str, title: str, size: int = 190, scale: float = 78) -> None:
    rows = []
    for r in results:
        ctx, frames, Js = r["ctx"], r["frameList"], r["Js"]
        if ctx.m:
            marks = [0, ctx.first // 2, max(ctx.first - 4, 0), ctx.first, ctx.first + 3, ctx.rec, (ctx.rec + ctx.total) // 2, ctx.total]
        else:
            n = frames[-1]
            marks = [int(round(n * u)) for u in (0, 0.14, 0.28, 0.42, 0.56, 0.7, 0.84, 1.0)]
        row = []
        for view in ("side", "threequarter"):
            for f in marks:
                k = min(range(len(frames)), key=lambda i: abs(frames[i] - f))
                J = Js[k]
                cx = np.array([J["pelvis"][0] * 0.5, 0.85, J["pelvis"][2] * 0.5])
                hl = (255, 60, 60) if (ctx.m and frames[k] == ctx.first) else None
                row.append(T.draw_bodies([(J, T.COL_A)], view, size, scale, cx, f"{r['name'][:22]} f{frames[k]}", hl))
        rows.append(row)
    if rows:
        T.sheet(rows, out, title)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--roster", required=True)
    ap.add_argument("--only", default="")
    ap.add_argument("--keys", default="")
    ap.add_argument("--out", default=os.path.join(T.REPO, "src"))
    ap.add_argument("--no-write", action="store_true")
    ap.add_argument("--sheets", default=None)
    ap.add_argument("--report", default=None)
    args = ap.parse_args()
    roster = json.load(open(args.roster, encoding="utf-8"))
    import movespecs  # noqa: F401  (registers the builders on the imported movebuild module)
    import movebuild as MB
    only = [x for x in args.only.split(",") if x]
    keys = [x for x in args.keys.split(",") if x]
    by_fighter: dict = {}
    report = []
    for e in MB.REGISTRY:
        if only and e["fighter"] not in only:
            continue
        label = e["key"] or e["name"]
        if keys and label not in keys:
            continue
        r = build(e, roster, None if args.no_write else args.out)
        by_fighter.setdefault(e["fighter"], []).append(r)
        line = {k: r[k] for k in ("name", "folder", "frames", "floorMinCm", "selfMaxCm", "selfWhere", "bytes") if k in r}
        line["sources"] = r["sources"]
        report.append(line)
        print(json.dumps(line))
    if args.sheets:
        os.makedirs(args.sheets, exist_ok=True)
        for fighter, rs in by_fighter.items():
            sheet(rs, os.path.join(args.sheets, f"moves_{fighter if fighter != '*' else 'Reactions'}.sheet.png"), f"{fighter}: round-6 move, stance and reaction clips (contact frame red)")
    if args.report:
        with open(args.report, "w", encoding="utf-8") as fh:
            json.dump(report, fh, indent=1)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
