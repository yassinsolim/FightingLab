"""Event detection helpers for strikes in long or short mocap takes (FightingLab research)."""
from __future__ import annotations

import numpy as np
from mocap import CANON

CI = {n: i for i, n in enumerate(CANON)}


def smooth(x, k):
    if k <= 1:
        return x
    ker = np.ones(k) / k
    pad = k // 2
    xp = np.pad(x, [(pad, pad)] + [(0, 0)] * (x.ndim - 1), mode="edge")
    if x.ndim == 1:
        return np.convolve(xp, ker, mode="valid")[: len(x)]
    return np.stack([np.convolve(xp[:, i], ker, mode="valid")[: len(x)] for i in range(x.shape[1])], -1)


def per_frame_facing(c, fps):
    lat = (c[:, CI["lhip"]] - c[:, CI["rhip"]]) + (c[:, CI["lshoulder"]] - c[:, CI["rshoulder"]])
    lat[:, 1] = 0
    lat = smooth(lat, max(1, int(fps * 0.25)))
    lat /= np.linalg.norm(lat, axis=1, keepdims=True) + 1e-9
    fwd = np.cross(lat, np.array([0.0, 1.0, 0.0]))
    fwd /= np.linalg.norm(fwd, axis=1, keepdims=True) + 1e-9
    return fwd, lat


def floor_y(c):
    return float(np.percentile(np.minimum(c[:, CI["ltoe"], 1], c[:, CI["rtoe"], 1]), 2))


def elbow_angle(c, f, side):
    s, e, w = c[f, CI[side + "shoulder"]], c[f, CI[side + "elbow"]], c[f, CI[side + "wrist"]]
    a, b = s - e, w - e
    return float(np.degrees(np.arccos(np.clip(a @ b / (np.linalg.norm(a) * np.linalg.norm(b) + 1e-9), -1, 1))))


def knee_angle(c, f, side):
    h, k, a = c[f, CI[side + "hip"]], c[f, CI[side + "knee"]], c[f, CI[side + "ankle"]]
    u, v = h - k, a - k
    return float(np.degrees(np.arccos(np.clip(u @ v / (np.linalg.norm(u) * np.linalg.norm(v) + 1e-9), -1, 1))))


def reach_curve(c, fps, eff, ref="pelvis", fwd=None):
    if fwd is None:
        fwd, _ = per_frame_facing(c, fps)
    rel = c[:, CI[eff]] - c[:, CI[ref]]
    return np.einsum("ni,ni->n", rel, fwd)


def find_peaks(x, fps, min_val, min_sep_s=0.25, min_rise=0.15, rise_window_s=0.6):
    n = len(x)
    w = max(1, int(fps * min_sep_s / 2))
    rw = max(1, int(fps * rise_window_s))
    peaks = []
    for i in range(1, n - 1):
        if x[i] < min_val:
            continue
        a, b = max(0, i - w), min(n, i + w + 1)
        if x[i] < x[a:b].max():
            continue
        prev_min = x[max(0, i - rw): i + 1].min()
        next_min = x[i: min(n, i + rw)].min()
        if x[i] - prev_min < min_rise or x[i] - next_min < min_rise * 0.5:
            continue
        if peaks and i - peaks[-1] < 2 * w:
            if x[i] > x[peaks[-1]]:
                peaks[-1] = i
            continue
        peaks.append(i)
    return peaks


def stance_side(c, f, fwd_vec):
    """'left' if the left foot is forward (orthodox), else 'right'."""
    lz = (c[f, CI["lankle"]] - c[f, CI["pelvis"]]) @ fwd_vec
    rz = (c[f, CI["rankle"]] - c[f, CI["pelvis"]]) @ fwd_vec
    return "left" if lz > rz else "right"


def classify_punch(c, fps, f, side, fwd_vec):
    """Crude punch type from the pose at contact frame f. side: 'l'/'r'/'left'/'right'."""
    side = side[0]
    chest_y = c[f, CI["chest"], 1]
    hand = c[f, CI[side + "hand"]]
    ang = elbow_angle(c, f, side)
    back = max(0, f - int(0.15 * fps))
    rise = hand[1] - c[back, CI[side + "hand"], 1]
    lead_foot = stance_side(c, f, fwd_vec)
    if hand[1] < chest_y - 0.12:
        kind = "body"
    elif ang < 120 and rise > 0.12:
        kind = "uppercut"
    elif ang < 125:
        kind = "hook"
    else:
        kind = "jab" if side == lead_foot[0] else "cross"
    return kind, ang, rise, lead_foot


def strike_window(local, fps, eff_idx, contact, a=0, b=None):
    """Onset/recovery around a contact frame from effector displacement relative to its pre-strike rest."""
    if b is None:
        b = local.shape[0] - 1
    p = local[:, eff_idx]
    rest = p[max(a, contact - int(0.6 * fps)): max(a + 1, contact - int(0.35 * fps))]
    rest = rest.mean(0) if len(rest) else p[a]
    d = np.linalg.norm(p - rest, axis=1)
    dmax = d[contact]
    on = contact
    while on > a and d[on] > 0.12 * dmax:
        on -= 1
    rec = contact
    while rec < b and d[rec] > 0.2 * dmax:
        rec += 1
    return on, rec
