"""Review renders: source skeleton (heading space) next to the pose reconstructed from FLClip1 channels.

The reconstruction mirrors MotionPlayer.apply on the actor's proportions: pelvis from the root channel, chest/head
from the root*waist*neck rotations, hands/feet by two-bone IK toward their effector targets with the encoded poles.
If a clip reads right here, retargeting is right; remaining differences in Studio come from rig proportions.
"""
from __future__ import annotations

import math

import numpy as np

import canon as canonmod
import render
import retarget as rt


def two_bone(root: np.ndarray, target: np.ndarray, l1: float, l2: float, pole: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    d = target - root
    dist = np.linalg.norm(d)
    dn = d / max(dist, 1e-9)
    dist = min(max(dist, abs(l1 - l2) + 1e-3), (l1 + l2) * 0.999)
    a = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
    h = math.sqrt(max(l1 * l1 - a * a, 0))
    p = pole - dn * np.dot(pole, dn)
    p = p / max(np.linalg.norm(p), 1e-9)
    return root + dn * a + p * h, root + dn * dist


class Body:
    """Actor proportions in local part frames, measured from the canonical source."""

    def __init__(self, c: canonmod.Canon):
        def local(frame: str, origin: str, point: str) -> np.ndarray:
            F = c.F[frame]
            v = c.p[point] - c.p[origin]
            return np.median(np.einsum("nji,nj->ni", F, v), axis=0)

        self.hip = {s: local("pelvis", "pelvis", "hip" + s) for s in "LR"}
        self.waist = local("pelvis", "pelvis", "waist")
        self.neck = local("chest", "waist", "neck")
        self.shoulder = {s: local("chest", "waist", "shoulder" + s) for s in "LR"}
        self.head = local("chest", "waist", "head")
        self.headTop = local("head", "head", "headTop")
        L = c.lengths
        self.L, self.A = L["leg"], L["arm"]
        self.thigh, self.shin, self.ankleH = L["thigh"], L["shin"], L["ankleHeight"]
        self.upper, self.lower = L["upperArm"], L["foreArm"] + L["hand"]
        self.stand = L["hipDrop"] + L["leg"]


def reconstruct(body: Body, ch: np.ndarray, i: int) -> dict[str, np.ndarray]:
    """Joint positions (heading space, Roblox axes, floor at y=0) from channel frame i."""
    q = lambda s: rt.quat_to_mat(ch[s:s + 4, i][None])[0]
    Rp = q(3)
    Rc = Rp @ q(7)
    Rh = Rc @ q(11)
    pelvis = ch[0:3, i] * body.L + np.array([0, body.stand, 0])
    J = {"pelvis": pelvis}
    J["waist"] = pelvis + Rp @ body.waist
    J["neck"] = J["waist"] + Rc @ body.neck
    J["head"] = J["waist"] + Rc @ body.head
    J["headTop"] = J["head"] + Rh @ body.headTop
    for li, limb in enumerate(rt.LIMBS):
        base = 15 + li * 10
        s = "L" if limb.startswith("Left") else "R"
        rel = ch[base:base + 3, i]
        pole = ch[base + 3:base + 6, i]
        if limb.endswith("Hand"):
            sh = J["waist"] + Rc @ body.shoulder[s]
            target = sh + rel * body.A
            elbow, hand = two_bone(sh, target, body.upper, body.lower, pole)
            J["shoulder" + s], J["elbow" + s], J["hand" + s] = sh, elbow, hand
        else:
            hip = pelvis + Rp @ body.hip[s]
            sole = hip + rel * body.L
            ankle = sole + np.array([0, body.ankleH, 0])
            knee, ankle2 = two_bone(hip, ankle, body.thigh, body.shin, pole)
            Rf = q(base + 6)
            toe = ankle2 + Rf @ np.array([0, -body.ankleH * 0.8, -0.14])
            J["hip" + s], J["knee" + s], J["ankle" + s], J["toe" + s] = hip, knee, ankle2, toe
    return J


def recon_segments(J: dict[str, np.ndarray], tint: float = 1.0):
    lib = lambda v: np.array([v[0], v[1], -v[2]])
    col = lambda c: tuple(int(x * tint) for x in c)
    segs = [(lib(J["pelvis"]), lib(J["waist"]), col(render.CENTER)), (lib(J["waist"]), lib(J["neck"]), col(render.CENTER)),
            (lib(J["neck"]), lib(J["head"]), col(render.CENTER)), (lib(J["head"]), lib(J["headTop"]), col(render.CENTER))]
    for s, c in (("L", render.LEFT), ("R", render.RIGHT)):
        segs += [(lib(J["pelvis"]), lib(J["hip" + s]), col(c)), (lib(J["hip" + s]), lib(J["knee" + s]), col(c)),
                 (lib(J["knee" + s]), lib(J["ankle" + s]), col(c)), (lib(J["ankle" + s]), lib(J["toe" + s]), col(c)),
                 (lib(J["neck"]), lib(J["shoulder" + s]), col(c)), (lib(J["shoulder" + s]), lib(J["elbow" + s]), col(c)),
                 (lib(J["elbow" + s]), lib(J["hand" + s]), col(c))]
    return segs


def review_sheet(c: canonmod.Canon, spec: dict, result: dict, out: str, cols: int = 8, size: int = 210) -> None:
    """Rows: source side, reconstruction side, source 3/4, reconstruction 3/4 (heading space, travel kept for source)."""
    ch = result["channels"]
    n = ch.shape[1]
    body = Body(c)
    a, b = int(spec["range"][0]), int(spec["range"][1])
    idx = np.linspace(0, n - 1, cols).round().astype(int)
    meta = result["meta"]
    yaw = math.radians(meta["yawDeg"])
    H = rt.ry(yaw)
    floor = float(spec.get("floor", c.lengths["floor"]))
    rows = []
    src_frames = [a + (b - a) * k / max(n - 1, 1) for k in idx]
    first = c.p["pelvis"][a].copy()
    for view in ("side", "threequarter"):
        r_src, r_rec = [], []
        for k, sf in zip(idx, src_frames):
            si = int(round(sf))
            anchor = first.copy(); anchor[1] = floor

            def xf(v, anchor=anchor):
                q = (v - anchor) @ H
                return np.array([q[0], q[1], -q[2]])

            segs = canonmod.segments(c, si, xf, mirror=bool(spec.get("mirror")))
            r_src.append(render.draw_panel(segs, view, size, size * 0.42, np.array([0, 0.95, 0]), f"src {si}"))
            J = reconstruct(body, ch, int(k))
            r_rec.append(render.draw_panel(recon_segments(J), view, size, size * 0.42, np.array([0, 0.95, 0]),
                                           f"clip {k} c{ch[55, k]:.1f}/{ch[56, k]:.1f} g{ch[57, k]:.1f}"))
        rows += [r_src, r_rec]
    render.sheet(rows, out, f"{spec['name']}  frames={n} fps={meta['fps']:g} loop={meta['loop']} yaw={meta['yawDeg']:.0f} speed={meta['speed']:.2f}L/s")
