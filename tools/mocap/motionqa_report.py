"""MotionQA report: ranked defect tables (markdown + JSON) from the Studio harness output.

The Studio runner (tools/mocap/motionqa_report.luau) posts one JSON per fighter: <tag>-<Fighter>.json with the
collapsed defects (worst per fighter/case/metric/part), counts and per-case summaries. This script merges them,
ranks every defect by how far it exceeds its limit, and compares against a baseline tag.

    python tools/mocap/motionqa_report.py --reports <dir> --tag after [--baseline before] --out <report.md> [--json <out.json>]
"""
import argparse
import collections
import glob
import json
import os

CATEGORIES = [
    ("pop.rot", "rotation pop (deg/frame, > abs limit and > 4x local median)"),
    ("pop.speed", "limb-tip speed pop (studs/frame)"),
    ("transition.jump", "transition: joint turn in one frame (deg)"),
    ("flip", "elbow/knee bend-plane flip (deg/frame)"),
    ("limit", "joint limits (all limit.* metrics)"),
    ("self.handHead", "hand/glove inside own head (studs)"),
    ("self.handTorso", "hand/glove inside own torso (studs)"),
    ("self.armTorso", "arm centreline inside own torso (studs)"),
    ("self.legs", "thighs/shins through each other (studs)"),
    ("opp.strike", "striking hand/foot depth into the opponent at contact (studs)"),
    ("opp.through", "striking hand/foot through the opponent outside contact (studs)"),
    ("opp.body", "bodies overlapping outside throws (studs)"),
    ("jitter", "idle/walk zig-zag oscillation"),
    ("getup.spin", "knockdown -> getup -> idle: whole-body yaw/roll per frame (deg, round 5)"),
    ("getup.whip", "knockdown -> getup -> idle: limb turn relative to the pelvis per frame (deg, round 5)"),
]
FIGHTERS = ["Kael", "Sierra", "Goran", "Lumi", "Rhys", "Nia"]


def load(reports, tag):
    data = {}
    for path in sorted(glob.glob(os.path.join(reports, f"{tag}-*.json"))):
        with open(path, encoding="utf-8-sig") as fh:
            d = json.load(fh)
        data[d["fighter"]] = d
    return data


def category(metric):
    if metric.startswith("limit."):
        return "limit"
    return metric


def counts(data):
    table = collections.defaultdict(lambda: collections.Counter())
    for fighter, d in data.items():
        for x in d["defects"]:
            table[category(x["metric"])][fighter] += 1
    return table


def severity(x):
    lim = max(abs(x.get("limit") or 0), 1e-3)
    return x["value"] / lim


def fmt_defect(x):
    where = x.get("key") or x.get("state") or ""
    mf = x.get("mf") or 0
    move = f" mf{mf}" if x.get("move") else ""
    return (f"| {x['fighter']} | {x['case']} | {x['frame']} | {x['metric']} | {x['part']} | {x['value']:.3f} | "
            f"{x['limit']:.3f} | {where}{move} | {x.get('note') or ''} |")


def hand_head(data):
    rows = {}
    for fighter, d in data.items():
        worst = {"LeftHand": -9, "RightHand": -9}
        where = {"LeftHand": "", "RightHand": ""}
        for c in d["cases"]:
            hh = c.get("handHead") or []
            if hh and isinstance(hh, list) and hh[0]:
                for hand in ("LeftHand", "RightHand"):
                    v = hh[0].get(hand)
                    if v is not None and v > worst[hand]:
                        worst[hand], where[hand] = v, c["case"]
        rows[fighter] = (worst, where)
    return rows


def strike_table(data):
    rows = []
    for fighter, d in data.items():
        for c in d["cases"]:
            s = c.get("strike")
            if s and c["case"].endswith(":max") and s.get("contact") is not None:
                rows.append((fighter, c["case"], s["contact"], s.get("depth"), s.get("part")))
            elif s and c["case"].endswith(":close") and s.get("contact") is not None:
                rows.append((fighter, c["case"], s["contact"], s.get("depth"), s.get("part")))
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--reports", required=True)
    ap.add_argument("--tag", required=True)
    ap.add_argument("--baseline")
    ap.add_argument("--out", required=True)
    ap.add_argument("--json")
    ap.add_argument("--top", type=int, default=60)
    args = ap.parse_args()
    data = load(args.reports, args.tag)
    base = load(args.reports, args.baseline) if args.baseline else None
    lines = [f"# MotionQA report: {args.tag}" + (f" (baseline: {args.baseline})" if base else ""), ""]
    frames = sum(d["frames"] for d in data.values())
    ncases = sum(len(d["cases"]) for d in data.values())
    lines.append(f"{len(data)} fighters, {ncases} cases, {frames} frames at 60 fps on the real rigs. Counts are distinct "
                 "(fighter, case, metric, part) defects (the worst frame of each).")
    lines.append("")
    t = counts(data)
    tb = counts(base) if base else None
    lines.append("## Defects per category and fighter" + (" (baseline -> now)" if base else ""))
    lines.append("")
    lines.append("| category | " + " | ".join(FIGHTERS) + " | total |")
    lines.append("|---|" + "---|" * (len(FIGHTERS) + 1))
    for cat, desc in CATEGORIES:
        cells = []
        total, btotal = 0, 0
        for f in FIGHTERS:
            v = t[cat][f]
            total += v
            if tb is not None:
                b = tb[cat][f]
                btotal += b
                cells.append(f"{b} -> {v}")
            else:
                cells.append(str(v))
        tot = f"{btotal} -> {total}" if tb is not None else str(total)
        lines.append(f"| {cat} ({desc}) | " + " | ".join(cells) + f" | {tot} |")
    lines.append("")
    # Worst value per category and fighter.
    def worst_values(dd):
        w = collections.defaultdict(dict)
        for fighter, d in dd.items():
            for x in d["defects"]:
                c = category(x["metric"])
                if x["value"] > w[c].get(fighter, float("-inf")):
                    w[c][fighter] = x["value"]
        return w
    wv = worst_values(data)
    wb = worst_values(base) if base else None
    lines.append("## Worst value per category and fighter" + (" (baseline -> now; - = no defect)" if base else ""))
    lines.append("")
    lines.append("| category | " + " | ".join(FIGHTERS) + " |")
    lines.append("|---|" + "---|" * len(FIGHTERS))
    for cat, _ in CATEGORIES:
        cells = []
        for f in FIGHTERS:
            now = wv[cat].get(f)
            nows = f"{now:.2f}" if now is not None else "-"
            if wb is not None:
                b = wb[cat].get(f)
                cells.append(f"{(f'{b:.2f}' if b is not None else '-')} -> {nows}")
            else:
                cells.append(nows)
        lines.append(f"| {cat} | " + " | ".join(cells) + " |")
    lines.append("")
    # Hand/glove vs head per fighter.
    hh = hand_head(data)
    hb = hand_head(base) if base else None
    lines.append("## Hand/glove vs own head: deepest penetration (studs, negative = clearance)")
    lines.append("")
    lines.append("| fighter | left | worst case | right | worst case |" + (" baseline left / right |" if hb else ""))
    lines.append("|---|---|---|---|---|" + ("---|" if hb else ""))
    for f in FIGHTERS:
        if f not in hh:
            continue
        w, where = hh[f]
        extra = ""
        if hb and f in hb:
            bw, _ = hb[f]
            extra = f" {bw['LeftHand']:.3f} / {bw['RightHand']:.3f} |"
        lines.append(f"| {f} | {w['LeftHand']:.3f} | {where['LeftHand']} | {w['RightHand']:.3f} | {where['RightHand']} |{extra}")
    lines.append("")
    # Ranked defects.
    allx = [x for d in data.values() for x in d["defects"]]
    allx.sort(key=severity, reverse=True)
    lines.append(f"## Worst {args.top} defects (ranked by value / limit)")
    lines.append("")
    lines.append("| fighter | case | frame | metric | part | value | limit | key | note |")
    lines.append("|---|---|---|---|---|---|---|---|---|")
    for x in allx[: args.top]:
        lines.append(fmt_defect(x))
    lines.append("")
    # Strike depths at contact.
    st = strike_table(data)
    st.sort(key=lambda r: -r[2])
    lines.append("## Striking limb depth into the opponent's head/torso at contact (studs; worst 30)")
    lines.append("")
    lines.append("| fighter | move:range | contact depth | worst depth in move | where |")
    lines.append("|---|---|---|---|---|")
    for r in st[:30]:
        lines.append(f"| {r[0]} | {r[1]} | {r[2]:.3f} | {r[3]:.3f} | {r[4]} |")
    lines.append("")
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    if args.json:
        out = {"tag": args.tag, "baseline": args.baseline, "counts": {c: dict(t[c]) for c, _ in CATEGORIES},
               "baselineCounts": {c: dict(tb[c]) for c, _ in CATEGORIES} if tb else None,
               "defects": allx}
        with open(args.json, "w", encoding="utf-8") as fh:
            json.dump(out, fh, indent=1)
    print(f"wrote {args.out} ({len(allx)} defects)")


if __name__ == "__main__":
    main()
