"""Retarget a canonical source clip into FightingLab effector space (FLClip1 channels, see ClipLibrary.luau).

Per output frame (heading space = Roblox character space rotated so -Z points at the opponent):
  root position: pelvis, leg-length units, Y relative to the straight-legged standing pelvis height
  root/waist/neck: quaternions (pelvis frame, pelvis->chest, chest->head)
  hands: shoulder->hand in arm-length units, elbow pole, (identity) hand rotation
  feet: hip->sole point (sole = ankle minus ankle height) in leg-length units, knee pole, foot rotation
  contacts: left/right foot planted, ground (torso supported by the floor)
"""
from __future__ import annotations

import math

import numpy as np
from scipy.ndimage import gaussian_filter1d

import canon as canonmod

LIMBS = ("LeftHand", "RightHand", "LeftFoot", "RightFoot")
N_CHANNELS = 58


def ry(a: float) -> np.ndarray:
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def heading_yaw(direction_rbx_xz: np.ndarray) -> float:
    """Yaw about +Y so that Ry(yaw) @ (0,0,-1) points along the given Roblox-space XZ direction."""
    d = direction_rbx_xz
    return math.atan2(-d[0], -d[1])


def mat_to_quat(R: np.ndarray) -> np.ndarray:
    """(N,3,3) rotation matrices -> (N,4) quaternions (x,y,z,w), sign-continuous."""
    n = len(R)
    q = np.zeros((n, 4))
    for i in range(n):
        m = R[i]
        t = m[0, 0] + m[1, 1] + m[2, 2]
        if t > 0:
            s = math.sqrt(t + 1.0) * 2
            w = 0.25 * s
            x = (m[2, 1] - m[1, 2]) / s
            y = (m[0, 2] - m[2, 0]) / s
            z = (m[1, 0] - m[0, 1]) / s
        elif m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
            s = math.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2]) * 2
            w = (m[2, 1] - m[1, 2]) / s
            x = 0.25 * s
            y = (m[0, 1] + m[1, 0]) / s
            z = (m[0, 2] + m[2, 0]) / s
        elif m[1, 1] > m[2, 2]:
            s = math.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2]) * 2
            w = (m[0, 2] - m[2, 0]) / s
            x = (m[0, 1] + m[1, 0]) / s
            y = 0.25 * s
            z = (m[1, 2] + m[2, 1]) / s
        else:
            s = math.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1]) * 2
            w = (m[1, 0] - m[0, 1]) / s
            x = (m[0, 2] + m[2, 0]) / s
            y = (m[1, 2] + m[2, 1]) / s
            z = 0.25 * s
        q[i] = (x, y, z, w)
    q /= np.linalg.norm(q, axis=1, keepdims=True)
    for i in range(1, n):
        if np.dot(q[i], q[i - 1]) < 0:
            q[i] = -q[i]
    if q[0, 3] < 0:
        q = -q
        for i in range(1, n):
            if np.dot(q[i], q[i - 1]) < 0:
                q[i] = -q[i]
    return q


def quat_to_mat(q: np.ndarray) -> np.ndarray:
    x, y, z, w = q[:, 0], q[:, 1], q[:, 2], q[:, 3]
    R = np.empty((len(q), 3, 3))
    R[:, 0, 0] = 1 - 2 * (y * y + z * z); R[:, 0, 1] = 2 * (x * y - z * w); R[:, 0, 2] = 2 * (x * z + y * w)
    R[:, 1, 0] = 2 * (x * y + z * w); R[:, 1, 1] = 1 - 2 * (x * x + z * z); R[:, 1, 2] = 2 * (y * z - x * w)
    R[:, 2, 0] = 2 * (x * z - y * w); R[:, 2, 1] = 2 * (y * z + x * w); R[:, 2, 2] = 1 - 2 * (x * x + y * y)
    return R


def orthonormalize(R: np.ndarray) -> np.ndarray:
    u, _, vt = np.linalg.svd(R)
    out = u @ vt
    det = np.linalg.det(out)
    u[det < 0, :, -1] *= -1
    return u @ vt


def resample(c: canonmod.Canon, a: int, b: int, out_fps: float) -> tuple[dict, dict, float]:
    """Positions and frames of source frames [a, b] (inclusive) resampled to out_fps (linear / nlerp+orthonormalise)."""
    src_t = (np.arange(a, b + 1) - a) / c.fps
    duration = src_t[-1]
    n_out = max(2, int(round(duration * out_fps)) + 1)
    t = np.linspace(0, duration, n_out)
    f = t * c.fps + a
    i0 = np.clip(np.floor(f).astype(int), a, b)
    i1 = np.clip(i0 + 1, a, b)
    al = (f - i0)[:, None]
    P = {k: v[i0] * (1 - al) + v[i1] * al for k, v in c.p.items()}
    F = {k: orthonormalize(v[i0] * (1 - al[..., None]) + v[i1] * al[..., None]) for k, v in c.F.items()}
    return P, F, float(t[1] - t[0]) if n_out > 1 else 1.0 / out_fps


def smooth_positions(P: dict, sigma: float) -> dict:
    if sigma <= 0:
        return P
    return {k: gaussian_filter1d(v, sigma, axis=0, mode="nearest") for k, v in P.items()}


def smooth_frames(F: dict, sigma: float) -> dict:
    if sigma <= 0:
        return F
    return {k: orthonormalize(gaussian_filter1d(v, sigma, axis=0, mode="nearest")) for k, v in F.items()}


def bend_pole(root: np.ndarray, mid: np.ndarray, tip: np.ndarray, fallback: np.ndarray) -> np.ndarray:
    """Unit vector from the root->tip line toward the mid joint; falls back (smoothly) for straight limbs."""
    d = tip - root
    dn = d / np.maximum(np.linalg.norm(d, axis=1, keepdims=True), 1e-9)
    off = (mid - root) - dn * np.sum((mid - root) * dn, axis=1, keepdims=True)
    mag = np.linalg.norm(off, axis=1, keepdims=True)
    pole = off / np.maximum(mag, 1e-9)
    # Nearly straight limbs: blend toward the previous reliable pole so the bend direction never flips.
    seg = np.linalg.norm(mid - root, axis=1, keepdims=True)
    reliability = np.clip(mag[:, 0] / np.maximum(seg[:, 0], 1e-9) / 0.12, 0, 1)
    out = np.zeros_like(pole)
    last = fallback.copy()
    for i in range(len(pole)):
        w = float(reliability[i])
        v = pole[i] * w + last * (1 - w)
        v = v / max(np.linalg.norm(v), 1e-9)
        out[i] = v
        if w > 0.5:
            last = v
    return out


def foot_contacts(sole_h: np.ndarray, sole_xz: np.ndarray, dt: float, L: float) -> np.ndarray:
    """0..1 planted weight from sole height above the floor and horizontal speed (both scaled by leg length)."""
    vel = np.zeros(len(sole_xz))
    vel[1:] = np.linalg.norm(np.diff(sole_xz, axis=0), axis=1) / dt
    vel[0] = vel[1] if len(vel) > 1 else 0
    vel = gaussian_filter1d(vel, 1.0, mode="nearest")
    h_w = np.clip((0.09 * L - sole_h) / (0.05 * L), 0, 1)
    v_w = np.clip((0.28 * L - vel) / (0.2 * L), 0, 1)
    return np.clip(h_w * v_w, 0, 1)


def lock_feet(sole: np.ndarray, contact: np.ndarray, floor_y: float = 0.0, threshold: float = 0.6, blend: int = 3) -> np.ndarray:
    """Foot locking: while a foot is planted its sole holds one world position (the segment's weighted mean), on the
    floor; the lock eases in/out over `blend` frames at the segment edges so the lift-off/touch-down stays smooth."""
    out = sole.copy()
    n = len(sole)
    planted = contact >= threshold
    i = 0
    while i < n:
        if not planted[i]:
            i += 1
            continue
        j = i
        while j + 1 < n and planted[j + 1]:
            j += 1
        w = contact[i:j + 1][:, None]
        anchor = (sole[i:j + 1] * w).sum(axis=0) / max(w.sum(), 1e-9)
        for k in range(i, j + 1):
            # Ease toward the anchor inside the segment edges (frames touching a lift-off/touch-down). Only X/Z are
            # locked: heel raises (a bounce on the balls of the feet) keep their height.
            edge = min(k - i, j - k)
            a = 1.0 if (edge >= blend or (i == 0 and k - i < blend) or (j == n - 1 and j - k < blend)) else (edge + 1) / (blend + 1)
            out[k, 0] = sole[k, 0] * (1 - a) + anchor[0] * a
            out[k, 2] = sole[k, 2] * (1 - a) + anchor[2] * a
        i = j + 1
    return out


def remove_travel(root: np.ndarray, mode: str) -> tuple[np.ndarray, np.ndarray, float]:
    """Removes XZ root travel. Returns (root, removed travel per frame (N,3), forward speed in units/s)."""
    n = len(root)
    removed = np.zeros_like(root)
    if mode == "none" or n < 2:
        return root, removed, 0.0
    if mode == "remove":
        removed[:, [0, 2]] = root[:, [0, 2]] - root[0, [0, 2]]
    elif mode == "linear":
        span = root[-1, [0, 2]] - root[0, [0, 2]]
        removed[:, [0, 2]] = np.outer(np.linspace(0, 1, n), span)
    elif mode == "center":
        # Keep the oscillation (weight shift), only re-centre the pelvis over the anchor.
        removed[:, [0, 2]] = root[:, [0, 2]].mean(axis=0)
        return root - removed, np.zeros_like(root), 0.0
    return root - removed, removed, 0.0


def loop_close(ch: np.ndarray, quat_slots: list[int]) -> np.ndarray:
    """Makes a clip loop: distributes the end->start mismatch linearly over the clip; drops the duplicate last frame.
    ch: (C, N+1) channels where frame N should equal frame 0."""
    C, n1 = ch.shape
    n = n1 - 1
    out = ch.copy()
    ramp = np.arange(n1) / n
    qset = set()
    for s in quat_slots:
        qset.update(range(s, s + 4))
    for c in range(C):
        if c in qset or c >= 55:
            continue
        out[c] = ch[c] - (ch[c, -1] - ch[c, 0]) * ramp
    for s in quat_slots:
        q = ch[s:s + 4].T.copy()
        q_end, q_start = q[-1], q[0]
        if np.dot(q_end, q_start) < 0:
            q_end = -q_end
        # correction rotation c = q_start * conj(q_end), applied progressively: q'_i = slerp(1, c, i/n) * q_i
        corr = quat_mul(q_start, quat_conj(q_end))
        for i in range(n1):
            q[i] = quat_mul(quat_slerp(np.array([0, 0, 0, 1.0]), corr, ramp[i]), q[i])
        out[s:s + 4] = q.T
    return out[:, :n]


def quat_mul(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return np.array([aw * bx + ax * bw + ay * bz - az * by, aw * by - ax * bz + ay * bw + az * bx,
                     aw * bz + ax * by - ay * bx + az * bw, aw * bw - ax * bx - ay * by - az * bz])


def quat_conj(q: np.ndarray) -> np.ndarray:
    return np.array([-q[0], -q[1], -q[2], q[3]])


def quat_slerp(a: np.ndarray, b: np.ndarray, t: float) -> np.ndarray:
    d = float(np.dot(a, b))
    if d < 0:
        b, d = -b, -d
    if d > 0.9995:
        r = a + (b - a) * t
        return r / np.linalg.norm(r)
    th = math.acos(min(1.0, d))
    s = math.sin(th)
    return a * (math.sin((1 - t) * th) / s) + b * (math.sin(t * th) / s)


def best_loop_end(c: canonmod.Canon, a: int, b: int, window_s: float = 0.3) -> int:
    """Source frame near b whose pose and velocity best match frame a (so the loop seam is invisible)."""
    keys = ["handL", "handR", "ankleL", "ankleR", "kneeL", "kneeR", "elbowL", "elbowR", "head", "chest"]

    def feat(i: int) -> np.ndarray:
        i = min(max(i, 0), c.n - 2)
        base = c.p["pelvis"][i]
        pos = np.concatenate([c.p[k][i] - base for k in keys] + [[base[1]]])
        vel = np.concatenate([(c.p[k][i + 1] - c.p[k][i]) * c.fps for k in keys])
        return np.concatenate([pos, vel * 0.08])

    w = int(round(window_s * c.fps))
    fa = feat(a)
    best, best_d = b, float("inf")
    for e in range(max(a + int(0.4 * c.fps), b - w), min(c.n - 2, b + w) + 1):
        d = float(np.linalg.norm(feat(e) - fa))
        if d < best_d:
            best, best_d = e, d
    return best


def mirror_channels(ch: np.ndarray) -> np.ndarray:
    """Mirror across the character's sagittal plane: x -> -x, quaternions (x,-y,-z,w), left/right limbs swapped."""
    out = ch.copy()

    def mpos(dst: int, src: int):
        out[dst] = -ch[src]; out[dst + 1] = ch[src + 1]; out[dst + 2] = ch[src + 2]

    def mquat(dst: int, src: int):
        out[dst] = ch[src]; out[dst + 1] = -ch[src + 1]; out[dst + 2] = -ch[src + 2]; out[dst + 3] = ch[src + 3]

    mpos(0, 0)
    for s in (3, 7, 11):
        mquat(s, s)
    for a_idx, b_idx in ((0, 1), (2, 3)):
        for dst_li, src_li in ((a_idx, b_idx), (b_idx, a_idx)):
            d, s = 15 + dst_li * 10, 15 + src_li * 10
            mpos(d, s)
            mpos(d + 3, s + 3)
            mquat(d + 6, s + 6)
    out[55], out[56] = ch[56], ch[55]
    return out


def retarget(c: canonmod.Canon, spec: dict) -> dict:
    a, b = int(spec["range"][0]), int(spec["range"][1])
    b = min(b, c.n - 1)
    if spec.get("loop") and spec.get("autoLoop", True):
        b = best_loop_end(c, a, b)
    fps = float(spec.get("fps", 30))
    sigma_src = float(spec.get("smooth", 1.0))
    # Filter at the source rate (anti-aliasing), then resample.
    cs = canonmod.Canon(c.fps, smooth_positions(c.p, sigma_src * c.fps / 60.0), smooth_frames(c.F, sigma_src * c.fps / 90.0), c.lengths, c.meta)
    P, F, dt = resample(cs, a, b, fps)
    n = len(P["pelvis"])
    L = c.lengths["leg"]
    A = c.lengths["arm"]
    ankle_h = c.lengths["ankleHeight"]
    floor = float(spec.get("floor", c.lengths["floor"]))
    # Heading: direction toward the opponent in SOURCE XZ (catalog targetDirXZ) -> Roblox XZ = (-x, -z).
    target = spec.get("target", [0.0, 1.0])
    if isinstance(target, str):
        if target == "pelvis":
            fwd = -F["pelvis"][:, :, 2].mean(axis=0)
        elif target == "chest":
            fwd = -F["chest"][:, :, 2].mean(axis=0)
        elif target == "head":
            fwd = -F["head"][:, :, 2].mean(axis=0)
        elif target in ("travel", "-travel"):
            d = P["pelvis"][-1] - P["pelvis"][0]
            fwd = d if target == "travel" else -d
        else:
            raise ValueError(target)
        d_rbx = np.array([fwd[0], fwd[2]])
    else:
        d_rbx = np.array([-float(target[0]), -float(target[1])])
    d_rbx = d_rbx / max(np.linalg.norm(d_rbx), 1e-9)
    yaw = heading_yaw(d_rbx) + math.radians(float(spec.get("yawOffset", 0.0)))
    H = ry(yaw)
    anchor = P["pelvis"][0].copy() if not spec.get("loop") else P["pelvis"].mean(axis=0)
    anchor[1] = floor

    def loc(v: np.ndarray) -> np.ndarray:
        return (v - anchor) @ H  # == (H^T (v - anchor)^T)^T

    Lp = {k: loc(v) for k, v in P.items()}
    stand = c.lengths["hipDrop"] + L
    root = Lp["pelvis"].copy()
    root[:, 1] -= stand
    root, removed, _ = remove_travel(root, spec.get("travel", "remove"))
    travel = removed[-1] / L
    duration = (n - 1) * dt
    speed = float(-(removed[-1, 2] - removed[0, 2]) / L / duration) if duration > 0 else 0.0
    root /= L
    HT = H.T[None]
    Fp = HT @ F["pelvis"]
    Fc = HT @ F["chest"]
    Fh = HT @ F["head"]
    q_root = mat_to_quat(Fp)
    q_waist = mat_to_quat(np.transpose(Fp, (0, 2, 1)) @ Fc)
    q_neck = mat_to_quat(np.transpose(Fc, (0, 2, 1)) @ Fh)
    channels = np.zeros((N_CHANNELS, n))
    channels[0:3] = root.T
    channels[3:7] = q_root.T
    channels[7:11] = q_waist.T
    channels[11:15] = q_neck.T
    ident = np.zeros((4, n)); ident[3] = 1
    contacts = {}
    for li, limb in enumerate(LIMBS):
        base = 15 + li * 10
        s = "L" if limb.startswith("Left") else "R"
        if limb.endswith("Hand"):
            rel = (Lp["hand" + s] - Lp["shoulder" + s]) / A
            fallback = np.array([0.6 if s == "R" else -0.6, -0.6, 0.5])
            pole = bend_pole(Lp["shoulder" + s], Lp["elbow" + s], Lp["hand" + s], fallback / np.linalg.norm(fallback))
            rot = ident
        else:
            sole = Lp["ankle" + s].copy()
            sole[:, 1] -= ankle_h
            pole = bend_pole(Lp["hip" + s], Lp["knee" + s], Lp["ankle" + s], np.array([0.0, 0.0, -1.0]))
            rot = mat_to_quat(HT @ F["foot" + s]).T
            # A foot is planted while its ball (or its sole) is on the floor: heels lifting in a bounce stay planted.
            ball_h = Lp["ball" + s][:, 1] - 0.025
            contacts[s] = foot_contacts(np.minimum(sole[:, 1], ball_h), Lp["ball" + s][:, [0, 2]], dt, L)
            if spec.get("footLock", True):
                sole = lock_feet(sole, contacts[s])
            rel = (sole - Lp["hip" + s]) / L
        channels[base:base + 3] = rel.T
        channels[base + 3:base + 6] = pole.T
        channels[base + 6:base + 10] = rot
    channels[55] = contacts["L"]
    channels[56] = contacts["R"]
    core_h = np.minimum.reduce([Lp["pelvis"][:, 1], Lp["chest"][:, 1], Lp["head"][:, 1]]) / L
    ground = np.clip((0.32 - core_h) / 0.12, 0, 1)
    if "ground" in spec and spec["ground"] != "auto":
        ground = np.full(n, float(spec["ground"]))
    channels[57] = ground
    loop = bool(spec.get("loop", False))
    if loop:
        channels = loop_close(channels, [3, 7, 11, 21, 31, 41, 51])
    if spec.get("mirror"):
        channels = mirror_channels(channels)
        travel = np.array([-travel[0], travel[1], travel[2]])
    total_frames = channels.shape[1]
    meta = {
        "fps": fps, "frames": total_frames, "loop": loop, "speed": speed,
        "travel": [float(travel[0]), float(travel[1]), float(-travel[2])],
        "yawDeg": math.degrees(yaw), "legMeters": L, "armMeters": A, "range": [a, b],
    }
    span = max(b - a, 1)
    for key in ("contact", "recover"):
        if spec.get(key) is not None:
            meta[key] = float(np.clip((float(spec[key]) - a) / span, 0, 1))
    return {"channels": channels, "meta": meta}
