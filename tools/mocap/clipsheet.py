"""Offline clip check (no Studio): renders a generated clip module to a contact sheet.

  python clipsheet.py <module.luau> [--out sheet.png] [--startup S --active A --recovery R] [--cols 10]

Without timing: evenly spaced clip frames. With timing (the move's frame data from combat-states.md): the frames the
GAME will show at sim frames 1..total after the contact warp (MotionPlayer/ClipPlayer.moveTime), the first active frame
(startup + 1) outlined in red. FLThrow1 modules draw the attacker (left) and the defender (right, facing it) at the
authored distance, warped so `impact` lands on --impact-frame of --duration.
The body is reconstructed by IK on a reference martial-artist skeleton, like MotionPlayer.apply does on the rigs.
"""
from __future__ import annotations

import argparse
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import canon as canonmod  # noqa: E402
import clipio  # noqa: E402
import render  # noqa: E402
import review  # noqa: E402

OV6 = os.path.abspath(os.path.join(HERE, "..", ".."))
REF_BODY = os.path.join(OV6, "research", "motion", "raw", "accad", "Male2", "Male2_D1_StandToReady.bvh")


def reference_body() -> review.Body:
    c = canonmod.load(REF_BODY, calib=(REF_BODY, 0))
    return review.Body(c.slice(0, 20))


def move_time(contact: float, recover: float | None, duration: float, startup: int, active: int, recovery: int, f: int) -> float:
    """Exact copy of ClipPlayer.moveTime (seconds of clip time at sim move frame f)."""
    d = duration
    c = min(max(contact, 0), 1) * d
    rn = recover if recover is not None else contact + (1 - contact) / 3
    r = min(max(rn, contact), 1) * d
    first, active_end = startup + 1, startup + active
    total = active_end + recovery
    if f <= first:
        return c * min(max(f / max(first, 1), 0), 1)
    if f <= active_end + 1:
        return c + (r - c) * min(max((f - first) / max(active_end + 1 - first, 1), 0), 1)
    return r + (d - r) * min(max((f - active_end - 1) / max(total - active_end - 1, 1), 0), 1)


def sample_channels(ch: np.ndarray, fps: float, loop: bool, t: float) -> np.ndarray:
    n = ch.shape[1]
    f = t * fps
    if loop:
        f %= n
        i0 = int(math.floor(f)); i1 = (i0 + 1) % n
    else:
        f = min(max(f, 0), n - 1)
        i0 = int(math.floor(f)); i1 = min(i0 + 1, n - 1)
    a = f - i0
    out = ch[:, i0] * (1 - a) + ch[:, i1] * a
    for s in (3, 7, 11, 21, 31, 41, 51):
        q0, q1 = ch[s:s + 4, i0], ch[s:s + 4, i1]
        if np.dot(q0, q1) < 0:
            q1 = -q1
        q = q0 * (1 - a) + q1 * a
        out[s:s + 4] = q / max(np.linalg.norm(q), 1e-9)
    return out


def mirrored(ch: np.ndarray) -> np.ndarray:
    import retarget as rt
    return rt.mirror_channels(ch)


def panel(body: review.Body, tracks: list[tuple[np.ndarray, float]], view: str, label: str, highlight: bool, size: int) -> Image.Image:
    segs = []
    for col, (frame, offset) in enumerate(tracks):
        J = review.reconstruct(body, frame[:, None], 0)
        if offset != 0.0:
            # Defender: faces the attacker, `offset` metres away along the attacker's forward (-Z).
            J = {k: np.array([-v[0], v[1], -v[2]]) + np.array([0, 0, -offset]) for k, v in J.items()}
        segs += review.recon_segments(J, 1.0 if col == 0 else 0.75)
    center = np.array([0, 0.95, -tracks[-1][1] * 0.5 if len(tracks) > 1 else 0])
    img = render.draw_panel(segs, view, size, size * (0.42 if len(tracks) == 1 else 0.3), center, label)
    if highlight:
        d = ImageDraw.Draw(img)
        d.rectangle([1, 1, size - 2, size - 2], outline=(255, 60, 60), width=3)
    return img


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("module")
    ap.add_argument("--out")
    ap.add_argument("--startup", type=int)
    ap.add_argument("--active", type=int)
    ap.add_argument("--recovery", type=int)
    ap.add_argument("--duration", type=int, help="throws: throw.duration (sim frames)")
    ap.add_argument("--impact-frame", type=int, help="throws: throw.impactFrame")
    ap.add_argument("--break-frames", type=int, default=16, help="throws: CombatConfig.ThrowBreakFrames (break track rows)")
    ap.add_argument("--cols", type=int, default=10)
    ap.add_argument("--size", type=int, default=200)
    args = ap.parse_args()
    text = open(args.module, encoding="utf-8").read()
    first = text.splitlines()[0]
    if not first.startswith("-- sources: ") or len(first) <= 12:
        print("WARNING: line 1 must be '-- sources: <catalog ids>' (credits)")
    raw = clipio.parse_lua_table(text)
    raws = raw if isinstance(raw, list) else [raw]
    body = reference_body()
    out = args.out or os.path.splitext(args.module)[0] + ".sheet.png"
    rows = []
    title = os.path.basename(args.module)
    for item in raws:
        if item.get("format") == "FLThrow1":
            att, dfd = item["attacker"], item["defender"]
            cha, chd = clipio.clip_channels(att), clipio.clip_channels(dfd)
            dist = float(item.get("distance", 1.2)) * body.L
            impact = float(item.get("impact", 0.6))
            duration = args.duration or 48
            hit = args.impact_frame or int(round(duration * 0.6))
            sim_frames = np.linspace(1, duration, args.cols).round().astype(int)
            for view in ("side", "threequarter"):
                row = []
                for f in sim_frames:
                    u = impact * f / hit if f <= hit else impact + (1 - impact) * (f - hit) / max(duration - hit, 1)
                    fa = sample_channels(cha, att["fps"], False, u * (att["frames"] - 1) / att["fps"])
                    fd = sample_channels(chd, dfd["fps"], False, u * (dfd["frames"] - 1) / dfd["fps"])
                    row.append(panel(body, [(fa, 0.0), (fd, dist)], view, f"f{f}", f == hit, args.size))
                rows.append(row)
            # Break tracks (throw.broken): both roles over ThrowBreakFrames (16 sim frames) from the break.
            ba, bd = item.get("breakAttacker"), item.get("breakDefender")
            if isinstance(ba, dict) or isinstance(bd, dict):
                total = args.break_frames
                chba = clipio.clip_channels(ba) if isinstance(ba, dict) else None
                chbd = clipio.clip_channels(bd) if isinstance(bd, dict) else None
                row = []
                for f in np.linspace(0, total, args.cols).round().astype(int):
                    u = f / max(total, 1)
                    tracks = []
                    if chba is not None:
                        tracks.append((sample_channels(chba, ba["fps"], False, u * (ba["frames"] - 1) / ba["fps"]), 0.0))
                    if chbd is not None:
                        tracks.append((sample_channels(chbd, bd["fps"], False, u * (bd["frames"] - 1) / bd["fps"]), dist))
                    row.append(panel(body, tracks, "side", f"break+{f}", False, args.size))
                rows.append(row)
            title += f"  FLThrow1 {item.get('fighter')}.{item.get('move')} impact={impact:.2f} distance={item.get('distance')}"
            continue
        ch = clipio.clip_channels(item)
        if item.get("mirror"):
            ch = mirrored(ch)
        fps, frames, loop = float(item["fps"]), int(item["frames"]), bool(item.get("loop"))
        duration = frames / fps if loop else max(frames - 1, 1) / fps
        contact = item.get("contact")
        if args.startup is not None and contact is not None:
            total = args.startup + (args.active or 1) + (args.recovery or 1)
            sim = np.unique(np.linspace(1, total, args.cols).round().astype(int).tolist() + [args.startup + 1])
            times = [(f"f{f}", move_time(float(contact), item.get("recover"), duration, args.startup, args.active or 1, args.recovery or 1, int(f)), f == args.startup + 1) for f in sim]
            title += f"  {item.get('fighter')}.{item.get('move')}  i{args.startup + 1}/{args.active}/{args.recovery}  contact={contact:.3f}"
        else:
            n = args.cols
            times = [(f"t{t:.2f}s", t, contact is not None and abs(t - float(contact) * duration) < duration / (2 * n)) for t in np.linspace(0, duration if not loop else duration * (n - 1) / n, n)]
            title += f"  {item.get('name')}  {frames}f@{fps:g} loop={loop} contact={contact}"
        for view in ("side", "threequarter"):
            rows.append([panel(body, [(sample_channels(ch, fps, loop, t), 0.0)], view, lab, hl, args.size) for lab, t, hl in times])
    render.sheet(rows, out, title)
    print(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
