"""Round-5 lying clips: built in BODY frames so limbs follow the body through rolls (FLClip1 modules).

  python tools/mocap/lying.py --src <src dir with the Core clips> --out <dir> [--only ProneTurnOver,SideRoll] [--sheet <dir>]

Hand-keyed rolls authored with heading-space limb keys (keyed.py) leave the arms and legs where the clip put them while the
pelvis turns under them: a log roll then twisted the limbs 30 degrees a frame relative to the body and pushed the gloves
through the chest. Here every key is a body pose: the pelvis rotation, the spine, the hands as shoulder->hand vectors in
the CHEST frame and the feet as hip->sole vectors in the PELVIS frame (arm / leg lengths), poles and foot rotations in the
same frames. Frames between keys interpolate in those frames (directions slerp, lengths lerp) and are written back to the
clip channels (heading space), so a tucked arm stays tucked however the body turns. The pelvis follows an explicit
rotation path (a roll about the spine at a constant rate, a sit-up, a turn), never a 180-degree slerp.

Clips (game frames are 60 Hz; the runtime plays them by progress, see Motion.States):
  ProneTurnOver  face down with the head away from the opponent (FallFrontAir's lying pose: a juggle that ends face
                 down) -> a log roll at <= 12 deg/frame onto the back -> FallBack's lying pose (head away, face up), from
                 which every getup rises. 18 frames.
  SideRoll       face up (FallBack's lying pose) -> roll a quarter turn onto the travel-side hip while the knees draw up
                 -> push up into a crouch turning toward the opponent -> the stance. 36 frames (the sim's roll getup);
                 the sim slides the body 2.2 studs over the first 10. Rolls left; the runtime mirrors it for right.
"""
from __future__ import annotations

import argparse
import glob
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import clipio  # noqa: E402
import retarget as rt  # noqa: E402

HANDS = {"LeftHand": 15, "RightHand": 25}
FEET = {"LeftFoot": 35, "RightFoot": 45}
LICENSE = "Original hand-keyed animation (FightingLab motioncore), built on mocap lying frames (Quaternius CC0 / CMU)"


def load(src: str, name: str) -> tuple[np.ndarray, dict]:
    hits = glob.glob(os.path.join(src, f"ReplicatedStorage.FightingLab.Client.Motion.Clips.*.{name}.luau"))
    if not hits:
        raise FileNotFoundError(name)
    raw = clipio.parse_lua_table(open(hits[0], encoding="utf-8").read())
    return clipio.clip_channels(raw), raw


def mat(q) -> np.ndarray:
    return rt.quat_to_mat(np.asarray(q, dtype=float)[None])[0]


def quat(m: np.ndarray) -> np.ndarray:
    q = rt.mat_to_quat(np.asarray(m, dtype=float)[None])[0]
    return q / np.linalg.norm(q)


def axis_angle(axis, ang: float) -> np.ndarray:
    a = np.asarray(axis, dtype=float)
    a = a / np.linalg.norm(a)
    x, y, z = a
    c, s = math.cos(ang), math.sin(ang)
    C = 1 - c
    return np.array([[c + x * x * C, x * y * C - z * s, x * z * C + y * s],
                     [y * x * C + z * s, c + y * y * C, y * z * C - x * s],
                     [z * x * C - y * s, z * y * C + x * s, c + z * z * C]])


def rot_slerp(A: np.ndarray, B: np.ndarray, t: float) -> np.ndarray:
    qa, qb = quat(A), quat(B)
    if float(np.dot(qa, qb)) < 0:
        qb = -qb
    return mat(rt.quat_slerp(qa, qb, t))


def unit(v) -> np.ndarray:
    v = np.asarray(v, dtype=float)
    n = np.linalg.norm(v)
    return v / n if n > 1e-9 else v


def slerp_vec(a, b, t: float) -> np.ndarray:
    a, b = unit(a), unit(b)
    d = float(np.clip(np.dot(a, b), -1, 1))
    ang = math.acos(d)
    if ang < 1e-6:
        return a
    if abs(ang - math.pi) < 1e-3:
        # Opposite: turn through any perpendicular.
        p = unit(np.cross(a, [0, 1, 0] if abs(a[1]) < 0.9 else [1, 0, 0]))
        return unit(a * math.cos(ang * t) + p * math.sin(ang * t))
    return unit((math.sin((1 - t) * ang) * a + math.sin(t * ang) * b) / math.sin(ang))


def smooth(u: float) -> float:
    u = min(max(u, 0.0), 1.0)
    return u * u * (3 - 2 * u)


def trapezoid(u: float, ramp: float) -> float:
    """Progress 0..1 with a constant middle speed and linear speed ramps of `ramp` (share of the time) at both ends."""
    u = min(max(u, 0.0), 1.0)
    r = min(max(ramp, 1e-6), 0.5)
    vmax = 1.0 / (1.0 - r)
    if u < r:
        return 0.5 * vmax * u * u / r
    if u > 1 - r:
        w = 1 - u
        return 1.0 - 0.5 * vmax * w * w / r
    return 0.5 * vmax * r + vmax * (u - r)


class Body:
    """A pose in body frames (see the module docstring)."""

    def __init__(self, root, R, W, N, limbs, contact=(0.0, 0.0), ground=1.0):
        self.root = np.asarray(root, dtype=float)
        self.R, self.W, self.N = R, W, N
        self.limbs = limbs  # name -> dict(dir, len, pole, rot)
        self.contact = contact
        self.ground = ground

    @staticmethod
    def of(f: np.ndarray) -> "Body":
        R, W, N = mat(f[3:7]), mat(f[7:11]), mat(f[11:15])
        C = R @ W
        limbs = {}
        for name, b in list(HANDS.items()) + list(FEET.items()):
            frame = C if name in HANDS else R
            v = frame.T @ f[b:b + 3]
            limbs[name] = {"dir": unit(v), "len": float(np.linalg.norm(v)), "pole": unit(frame.T @ f[b + 3:b + 6]),
                           "rot": frame.T @ mat(f[b + 6:b + 10])}
        return Body(f[0:3].copy(), R, W, N, limbs, (float(f[55]), float(f[56])), float(f[57]))

    def frame(self) -> np.ndarray:
        f = np.zeros(58)
        f[0:3] = self.root
        f[3:7], f[7:11], f[11:15] = quat(self.R), quat(self.W), quat(self.N)
        C = self.R @ self.W
        for name, b in list(HANDS.items()) + list(FEET.items()):
            L = self.limbs[name]
            frame = C if name in HANDS else self.R
            f[b:b + 3] = frame @ (L["dir"] * L["len"])
            f[b + 3:b + 6] = unit(frame @ L["pole"])
            f[b + 6:b + 10] = quat(frame @ L["rot"])
        f[55], f[56], f[57] = self.contact[0], self.contact[1], self.ground
        return f


def limb(dirv, length, pole, rot=None) -> dict:
    return {"dir": unit(dirv), "len": float(length), "pole": unit(pole), "rot": np.eye(3) if rot is None else rot}


def blend_limb(a: dict, b: dict, t: float) -> dict:
    return {"dir": slerp_vec(a["dir"], b["dir"], t), "len": a["len"] + (b["len"] - a["len"]) * t,
            "pole": slerp_vec(a["pole"], b["pole"], t), "rot": rot_slerp(a["rot"], b["rot"], t)}


def limb_track(keys: list[tuple[float, dict]], u: float) -> dict:
    """Piecewise smooth interpolation of limb keys (u = 0..1)."""
    if u <= keys[0][0]:
        return keys[0][1]
    for (ua, la), (ub, lb) in zip(keys, keys[1:]):
        if u <= ub:
            return blend_limb(la, lb, smooth((u - ua) / max(ub - ua, 1e-9)))
    return keys[-1][1]


def rot_track(keys: list[tuple[float, np.ndarray]], u: float) -> np.ndarray:
    if u <= keys[0][0]:
        return keys[0][1]
    for (ua, ra), (ub, rb) in zip(keys, keys[1:]):
        if u <= ub:
            return rot_slerp(ra, rb, smooth((u - ua) / max(ub - ua, 1e-9)))
    return keys[-1][1]


def mirror_limb_dir(v) -> np.ndarray:
    return np.array([-v[0], v[1], v[2]])


def leg_frame(L: dict) -> np.ndarray:
    """A limb's own frame (same as MotionPlayer's limbFrame): up along the limb toward its root, forward toward the pole."""
    up = -unit(L["dir"])
    pole = np.asarray(L["pole"], dtype=float)
    fwd = pole - up * float(np.dot(pole, up))
    fwd = unit(fwd) if np.linalg.norm(fwd) > 1e-6 else unit(np.cross(up, [1.0, 0.0, 0.0]))
    back = -fwd
    return np.stack([unit(np.cross(up, back)), up, back], axis=1)


def foot_on_leg(L: dict, rel: np.ndarray) -> np.ndarray:
    """The foot rotation (pelvis frame) that keeps `rel` (the foot in its leg's frame) on this leg."""
    return leg_frame(L) @ rel


# --- ProneTurnOver ---------------------------------------------------------------------------------------------------


def prone_turn_over(src: str, frames: int = 18) -> np.ndarray:
    fa, _ = load(src, "FallFrontAir")
    fb, _ = load(src, "FallBack")
    A, B = Body.of(fa[:, -1]), Body.of(fb[:, -1])
    axis = unit(A.R[:, 1])  # the pelvis long axis (head away from the opponent: ~+Z in clip space)
    # +180 deg about the spine turns the front through +X (the fighter's right): the face turns toward the camera side.
    Bp = axis_angle(axis, math.pi) @ A.R
    residual = B.R @ Bp.T
    # The roll goes over the right side (front through +X): the right (bottom) arm reaches overhead along the floor so
    # the body rolls past it instead of pinning it under the chest; the left (top) arm guards in front of the face.
    reachR = limb([0.62, 0.76, -0.15], 0.95, [0.0, 0.0, 1.0])
    # On the back again the arm comes down along the floor beside the body (straight from overhead it swept past the face).
    sideR = limb([0.95, 0.2, -0.2], 0.95, [0.0, -0.3, 1.0])
    guardL = limb([0.25, 0.4, -0.88], 0.6, [-0.4, -0.85, 0.3])
    legL = limb([-0.1, -0.93, -0.18], 0.9, [0, 0.1, -1])
    legR = limb([0.1, -0.93, -0.18], 0.9, [0, 0.1, -1])
    out = []
    for i in range(frames + 1):
        u = i / frames
        s = trapezoid(u, 0.15)
        R = rot_slerp(np.eye(3), residual, s) @ axis_angle(axis, math.pi * s) @ A.R
        W = rot_slerp(A.W, B.W, s)
        N = rot_slerp(A.N, B.N, s)
        limbs = {
            "LeftHand": limb_track([(0.0, A.limbs["LeftHand"]), (0.35, guardL), (0.7, guardL), (1.0, B.limbs["LeftHand"])], u),
            "RightHand": limb_track([(0.0, A.limbs["RightHand"]), (0.25, reachR), (0.62, reachR), (0.82, sideR), (1.0, B.limbs["RightHand"])], u),
            "LeftFoot": limb_track([(0.0, A.limbs["LeftFoot"]), (0.35, legL), (0.65, legL), (1.0, B.limbs["LeftFoot"])], u),
            "RightFoot": limb_track([(0.0, A.limbs["RightFoot"]), (0.35, legR), (0.65, legR), (1.0, B.limbs["RightFoot"])], u),
        }
        root = A.root + (B.root - A.root) * s + np.array([0, 0.06 * math.sin(math.pi * s), 0])
        out.append(Body(root, R, W, N, limbs, (0.0, 0.0), 1.0).frame())
    return np.stack(out, axis=1)


# --- SideRoll ---------------------------------------------------------------------------------------------------------


def side_roll(src: str, frames: int = 36) -> np.ndarray:
    fb, _ = load(src, "FallBack")
    st, _ = load(src, "Stance")
    A = Body.of(fb[:, -1])
    E = Body.of(st[:, 0])
    E.contact, E.ground = (1.0, 1.0), 0.0
    spine = unit(A.R[:, 1])
    # Quarter turn onto the left hip: +90 deg about the spine turns the front (up) toward -X, the travel side.
    R1 = axis_angle(spine, math.pi / 2) @ A.R
    # Crouch: the spine upright, the front still toward the travel side, then turning toward the opponent while rising.
    front_left = np.array([-1.0, 0.0, 0.0])
    up = np.array([0.0, 1.0, 0.0])
    back = -front_left
    right = np.cross(up, back)
    R2 = np.stack([right, up, back], axis=1)  # columns: right, up, back (front = -back = -X)
    # Half way through the rise the body faces the opponent (front -Z, slightly bladed), then the stance.
    R3 = axis_angle(up, -math.pi / 2 + math.radians(25)) @ R2
    rot_keys = [(0.0, A.R), (0.27, R1), (0.6, R2), (0.8, R3), (1.0, E.R)]
    # Limbs (chest frame for hands, pelvis frame for feet; Roblox axes: +X right, +Y up, -Z front). Nothing passes under
    # or across the body: the lower (left) arm reaches forward along the floor and braces in front of the chest, the
    # upper (right) hand comes from a guard in front of the face down to the floor in front of the chest (round 5: the
    # first version tucked both forearms on the belly and braced the lower one under the chest, 0.4-0.5 studs inside it).
    reachL = limb([-0.35, 0.15, -0.92], 0.8, [-0.8, -0.4, 0.4])
    guardR0 = limb([-0.3, 0.3, -0.9], 0.6, [0.35, -1, 0.3])
    plantR = limb([-0.65, -0.25, -0.72], 0.9, [0.45, 0.85, 0.25])    # the upper (right) hand plants in front of the chest
    braceL = limb([-0.55, -0.2, -0.8], 0.8, [-0.8, -0.2, 0.55])      # the lower (left) hand braces in front of the chest
    kneesL = limb([-0.12, -0.62, -0.62], 0.8, [0, 0.2, -1])
    kneesR = limb([0.15, -0.6, -0.62], 0.78, [0, 0.2, -1])
    crouchL = limb([-0.22, -0.85, -0.25], 0.62, [0, 0.15, -1])
    crouchR = limb([0.22, -0.8, 0.3], 0.62, [0, 0.15, -1])
    guardL = limb([0.3, 0.35, -0.85], 0.62, [-0.3, -1, 0.3])
    guardR = limb([-0.3, 0.3, -0.85], 0.6, [0.35, -1, 0.3])
    hands = {
        "LeftHand": [(0.0, A.limbs["LeftHand"]), (0.2, reachL), (0.42, braceL), (0.62, braceL), (0.82, guardL), (1.0, E.limbs["LeftHand"])],
        "RightHand": [(0.0, A.limbs["RightHand"]), (0.2, guardR0), (0.4, plantR), (0.6, plantR), (0.8, guardR), (1.0, E.limbs["RightHand"])],
        "LeftFoot": [(0.0, A.limbs["LeftFoot"]), (0.25, kneesL), (0.6, crouchL), (1.0, E.limbs["LeftFoot"])],
        "RightFoot": [(0.0, A.limbs["RightFoot"]), (0.25, kneesR), (0.6, crouchR), (1.0, E.limbs["RightFoot"])],
    }
    W_keys = [(0.0, A.W), (0.3, np.eye(3)), (0.6, axis_angle([1, 0, 0], math.radians(25))), (1.0, E.W)]
    # Each foot keeps its lying pose's set on the leg (ankle angle) through the roll, then plants flat.
    foot_rel = {f: leg_frame(A.limbs[f]).T @ A.limbs[f]["rot"] for f in ("LeftFoot", "RightFoot")}
    N_keys = [(0.0, A.N), (0.3, axis_angle([1, 0, 0], math.radians(15))), (0.7, np.eye(3)), (1.0, E.N)]
    out = []
    for i in range(frames + 1):
        u = i / frames
        R = rot_track(rot_keys, u)
        W = rot_track(W_keys, u)
        N = rot_track(N_keys, u)
        limbs = {name: limb_track(keys, u) for name, keys in hands.items()}
        # Feet: set on the leg as in the lying pose while rolling (the ankle angle does not change), then flat on the floor
        # under the pelvis's heading as they plant (the round-5 first version kept them in the pelvis frame: ankles at 90-116
        # degrees while the knees were drawn up).
        fwd = R @ np.array([0.0, 0.0, -1.0])
        fwd[1] = 0.0
        if np.linalg.norm(fwd) > 1e-3:
            fwd = unit(fwd)
            yaw = np.stack([np.cross([0.0, 1.0, 0.0], -fwd), [0.0, 1.0, 0.0], -fwd], axis=1)
            flat = R.T @ yaw
            for foot in ("LeftFoot", "RightFoot"):
                L = dict(limbs[foot])
                track = L["rot"]  # FallBack's foot at the start, the stance's at the end
                rot = foot_on_leg(L, foot_rel[foot])
                # The kneeling (right) leg stays on its toes until it steps under the body; the other foot plants flat.
                plant_at = 0.56 if foot == "LeftFoot" else 0.78
                rot = rot_slerp(rot, flat, smooth((u - plant_at) / 0.12))
                L["rot"] = rot_slerp(rot, track, smooth((u - 0.82) / 0.18))
                limbs[foot] = L
        # Pelvis height: lying, a little higher on the hip, a crouch, the stance.
        y = float(np.interp(u, [0.0, 0.27, 0.62, 0.82, 1.0], [A.root[1], A.root[1] + 0.08, -0.5, -0.2, E.root[1]]))
        xz = A.root[[0, 2]] * (1 - smooth(u)) + E.root[[0, 2]] * smooth(u)
        root = np.array([xz[0], y, xz[1]])
        # The feet plant once the body is up over them (planted feet are flattened to the floor by the runtime).
        contact = (float(np.interp(u, [0, 0.56, 0.68, 1], [0, 0, 1, E.contact[0]])), float(np.interp(u, [0, 0.78, 0.9, 1], [0, 0, 1, E.contact[1]])))
        ground = float(np.interp(u, [0, 0.45, 0.66, 1], [1, 1, 0.15, 0]))
        out.append(Body(root, R, W, N, limbs, contact, ground).frame())
    return np.stack(out, axis=1)


CLIPS = {
    "ProneTurnOver": (prone_turn_over, ["original:motioncore", "cmu-90_16", "quat-ual2-hit-knockback"],
                      "Juggle face-down landing (head away from the opponent) rolled over onto the back at <= 12 deg/frame, "
                      "the lower arm reaching overhead along the floor, the upper arm guarding the face, legs together, ending in "
                      "FallBack's lying pose (round 5)."),
    "SideRoll": (side_roll, ["original:motioncore", "quat-ual2-hit-knockback", "cmu-140_08"],
                 "Side roll getup (round 5): a quarter turn onto the travel-side hip with the knees drawn up, push up into a "
                 "crouch turning toward the opponent, the stance; rolls left, mirrored at runtime for right."),
}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--only")
    args = ap.parse_args()
    only = set(args.only.split(",")) if args.only else None
    for name, (fn, sources, notes) in CLIPS.items():
        if only and name not in only:
            continue
        ch = fn(args.src)
        meta = {"fps": 60, "loop": False}
        text, clipped = clipio.luau_module(name, ch, meta, "hand-keyed (tools/mocap/lying.py)", LICENSE, notes, sources)
        text = text.replace("generated by OV6/tools/mocap/convert.py", "generated by tools/mocap/lying.py")
        path = os.path.join(args.out, f"ReplicatedStorage.FightingLab.Client.Motion.Clips.Core.{name}.luau")
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)
        print(f"{name}: {ch.shape[1]} frames -> {path} (clipped {clipped})")


if __name__ == "__main__":
    main()
