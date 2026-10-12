"""Offline lint for clip modules (no Studio): decodes every module and checks the rules the runtime relies on.

  python cliplint.py <dir or module.luau> [...] [--states <OV6/handoff/combat-states.md>] [--budget-kb 2048]

Checks: line 1 is "-- sources: <ids>" and matches the `sources` field; format FLClip1/FLThrow1; data decodes to the
declared frame count; unit quaternions; attack clips declare `fighter` (a roster id or "*") and `move` (a key of that
fighter's moveset in combat-states.md) and a `contact`; throws have attacker/defender tracks, impact and distance;
duplicate (fighter, move, stringIndex) bindings; total source size against the clip budget.
"""
from __future__ import annotations

import argparse
import glob
import os
import re
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import clipio  # noqa: E402

OV6 = os.path.abspath(os.path.join(HERE, "..", ".."))
ROSTER = ("kael", "sierra", "goran", "lumi", "rhys", "nia")


def movesets(path: str) -> dict[str, set[str]]:
    out: dict[str, set[str]] = {}
    if not os.path.exists(path):
        return out
    fighter = None
    for line in open(path, encoding="utf-8", errors="replace"):
        m = re.match(r"^###\s+([A-Z]+)\b", line)
        if m:
            fighter = m.group(1).lower()
            out.setdefault(fighter, set())
            continue
        m = re.match(r"^\|\s*([A-Za-z0-9_]+)\s*\|", line)
        if fighter and m and m.group(1) not in ("key",):
            out[fighter].add(m.group(1))
    return out


def check_track(raw: dict, where: str, errors: list[str]) -> None:
    if raw.get("format") != "FLClip1":
        errors.append(f"{where}: format must be FLClip1")
        return
    try:
        ch = clipio.clip_channels(raw)
    except Exception as e:  # noqa: BLE001
        errors.append(f"{where}: data does not decode ({e})")
        return
    for q in (3, 7, 11, 21, 31, 41, 51):
        norms = np.linalg.norm(ch[q:q + 4], axis=0)
        if np.abs(norms - 1).max() > 0.02:
            errors.append(f"{where}: quaternion channels {q + 1}-{q + 4} are not unit length")
            break


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("paths", nargs="+")
    ap.add_argument("--states", default=os.path.join(OV6, "handoff", "combat-states.md"))
    ap.add_argument("--budget-kb", type=float, default=2048)
    args = ap.parse_args()
    files: list[str] = []
    for p in args.paths:
        files += sorted(glob.glob(os.path.join(p, "*.Motion.Clips.*.luau"))) if os.path.isdir(p) else [p]
    sets = movesets(args.states)
    errors: list[str] = []
    bindings: dict[tuple, str] = {}
    total = 0
    for f in files:
        name = os.path.basename(f)
        text = open(f, encoding="utf-8").read()
        total += len(text.encode("utf-8"))
        first = text.splitlines()[0] if text else ""
        if not first.startswith("-- sources: ") or len(first.strip()) <= len("-- sources:"):
            errors.append(f"{name}: line 1 must be '-- sources: <catalog ids>'")
        try:
            raw = clipio.parse_lua_table(text)
        except Exception as e:  # noqa: BLE001
            errors.append(f"{name}: cannot parse the returned table ({e})")
            continue
        for i, item in enumerate(raw if isinstance(raw, list) else [raw]):
            where = f"{name}[{i + 1}]" if isinstance(raw, list) else name
            ids = item.get("sources") or []
            header_ids = [s.strip() for s in first[len("-- sources: "):].split(",") if s.strip()]
            if not ids:
                errors.append(f"{where}: missing sources = {{...}}")
            elif sorted(set(ids)) != sorted(set(ids) & set(header_ids)):
                errors.append(f"{where}: sources field {ids} not all listed on line 1 {header_ids}")
            fmt = item.get("format")
            is_move = ".Clips.Moves." in name
            if fmt == "FLThrow1":
                for role in ("attacker", "defender"):
                    if not isinstance(item.get(role), dict):
                        errors.append(f"{where}: FLThrow1 needs an {role} track")
                    else:
                        check_track(item[role], f"{where}.{role}", errors)
                for role in ("breakAttacker", "breakDefender"):
                    if item.get(role) is not None:
                        if isinstance(item[role], dict):
                            check_track(item[role], f"{where}.{role}", errors)
                        else:
                            errors.append(f"{where}: {role} must be an FLClip1 track")
                for key in ("impact", "distance", "move"):
                    if item.get(key) is None:
                        errors.append(f"{where}: FLThrow1 needs {key}")
                grips = item.get("grips")
                if grips is not None:
                    if not isinstance(grips, list):
                        errors.append(f"{where}: grips must be a list of grip tables")
                    else:
                        att = item.get("attacker") or {}
                        try:
                            duration = (int(att["frames"]) - 1) / float(att["fps"])
                        except (KeyError, TypeError, ValueError):
                            duration = None
                        for gi, grip in enumerate(grips):
                            for problem in clipio.check_grip(grip if isinstance(grip, dict) else {}, duration):
                                errors.append(f"{where}.grips[{gi + 1}]: {problem}")
            elif fmt == "FLClip1":
                check_track(item, where, errors)
                if is_move and item.get("contact") is None and item.get("contactFrame") is None:
                    errors.append(f"{where}: attack clips need contact (0..1) or contactFrame")
            else:
                errors.append(f"{where}: unknown format {fmt!r}")
                continue
            if is_move:
                fighter = str(item.get("fighter") or "*").lower()
                move = item.get("move")
                if fighter not in ROSTER and fighter not in ("*", "any"):
                    errors.append(f"{where}: fighter {item.get('fighter')!r} is not a roster id")
                if not move:
                    errors.append(f"{where}: move key missing")
                elif sets and fighter in sets and move not in sets[fighter]:
                    errors.append(f"{where}: {move!r} is not in {fighter.upper()}'s moveset (combat-states.md)")
                elif sets and fighter in ("*", "any") and not any(move in s for s in sets.values()):
                    errors.append(f"{where}: {move!r} is not a move key of any fighter")
                key = (fmt, fighter, move, item.get("stringIndex"))
                if key in bindings:
                    errors.append(f"{where}: same binding {key} as {bindings[key]} (only one is used)")
                bindings[key] = where
    print(f"{len(files)} modules, {total / 1024:.1f} KB (budget {args.budget_kb:.0f} KB)")
    if total > args.budget_kb * 1024:
        errors.append(f"total {total / 1024:.0f} KB exceeds the budget")
    for e in errors:
        print("ERROR", e)
    print("OK" if not errors else f"{len(errors)} problem(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
