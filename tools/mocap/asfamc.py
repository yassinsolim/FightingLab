"""CMU ASF/AMC parser and forward kinematics.

Coordinate system of the result: CMU world (Y up). In the CMU rest pose the actor faces +Z and +X is the
actor's LEFT. Lengths are converted to metres (CMU "length 0.45" => 1 unit = 1/0.45 inch).

Rotation convention (standard CMU, as used by the reference amc_parser implementations):
    C   = euler(axis angles)                      (bone local axis, from the ASF "axis" field)
    M   = euler(dof angles from the AMC frame)    (missing dofs are 0)
    L   = C * M * C^-1                            (local rotation)
    R_b = R_parent * L                            (global rotation; the root uses L only)
    end_b = end_parent + length * R_b * direction (bone end position)
with euler(x, y, z) = Rz(z) * Ry(y) * Rx(x) ("static xyz").
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field

import numpy as np

INCH = 0.0254


def rx(a: float) -> np.ndarray:
    c, s = np.cos(a), np.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def ry(a: float) -> np.ndarray:
    c, s = np.cos(a), np.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def rz(a: float) -> np.ndarray:
    c, s = np.cos(a), np.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def euler_sxyz(x: float, y: float, z: float) -> np.ndarray:
    return rz(z) @ ry(y) @ rx(x)


def euler_batch(ax: np.ndarray, ay: np.ndarray, az: np.ndarray) -> np.ndarray:
    """Vectorised euler_sxyz for arrays of angles (radians); returns (N,3,3)."""
    n = len(ax)
    cx, sx = np.cos(ax), np.sin(ax)
    cy, sy = np.cos(ay), np.sin(ay)
    cz, sz = np.cos(az), np.sin(az)
    R = np.empty((n, 3, 3))
    # Rz * Ry * Rx
    R[:, 0, 0] = cz * cy
    R[:, 0, 1] = cz * sy * sx - sz * cx
    R[:, 0, 2] = cz * sy * cx + sz * sx
    R[:, 1, 0] = sz * cy
    R[:, 1, 1] = sz * sy * sx + cz * cx
    R[:, 1, 2] = sz * sy * cx - cz * sx
    R[:, 2, 0] = -sy
    R[:, 2, 1] = cy * sx
    R[:, 2, 2] = cy * cx
    return R


@dataclass
class Bone:
    name: str
    direction: np.ndarray
    length: float
    axis: np.ndarray  # degrees
    dof: list[str] = field(default_factory=list)
    parent: str | None = None
    children: list[str] = field(default_factory=list)


@dataclass
class Skeleton:
    bones: dict[str, Bone]
    order: list[str]  # topological order, root first
    root_order: list[str]
    scale: float  # metres per ASF length unit


def parse_asf(path: str) -> Skeleton:
    text = open(path, "r", encoding="latin-1").read()
    lines = [ln.strip() for ln in text.splitlines()]
    length_unit = 1.0
    for ln in lines:
        m = re.match(r"length\s+([0-9.eE+-]+)", ln)
        if m:
            length_unit = float(m.group(1))
            break
    scale = INCH / length_unit
    bones: dict[str, Bone] = {}
    root_order = ["TX", "TY", "TZ", "RX", "RY", "RZ"]
    i = 0
    section = None
    while i < len(lines):
        ln = lines[i]
        if ln.startswith(":"):
            section = ln.split()[0]
            i += 1
            continue
        if section == ":root" and ln.startswith("order"):
            root_order = ln.split()[1:]
        if section == ":bonedata" and ln == "begin":
            b = {"dof": []}
            i += 1
            while lines[i] != "end":
                parts = lines[i].split()
                if parts:
                    key = parts[0]
                    if key == "name":
                        b["name"] = parts[1]
                    elif key == "direction":
                        b["direction"] = np.array([float(v) for v in parts[1:4]])
                    elif key == "length":
                        b["length"] = float(parts[1])
                    elif key == "axis":
                        b["axis"] = np.array([float(v) for v in parts[1:4]])
                        if len(parts) > 4 and parts[4].upper() != "XYZ":
                            raise ValueError(f"unsupported axis order {parts[4]} in {path}")
                    elif key == "dof":
                        b["dof"] = parts[1:]
                i += 1
            bones[b["name"]] = Bone(b["name"], b["direction"], b["length"] * scale, b["axis"], b["dof"])
        if section == ":hierarchy" and ln not in ("begin", "end") and ln:
            parts = ln.split()
            parent = parts[0]
            for child in parts[1:]:
                bones[child].parent = parent
                if parent in bones:
                    bones[parent].children.append(child)
        i += 1
    bones["root"] = Bone("root", np.zeros(3), 0.0, np.zeros(3), [], None,
                         [n for n, b in bones.items() if b.parent == "root"])
    order: list[str] = []
    stack = ["root"]
    while stack:
        n = stack.pop(0)
        order.append(n)
        stack.extend(bones[n].children)
    return Skeleton(bones, order, root_order, scale)


def parse_amc(path: str) -> list[dict[str, list[float]]]:
    frames: list[dict[str, list[float]]] = []
    cur: dict[str, list[float]] | None = None
    with open(path, "r", encoding="latin-1") as fh:
        for ln in fh:
            ln = ln.strip()
            if not ln or ln.startswith("#") or ln.startswith(":"):
                continue
            if ln.isdigit():
                cur = {}
                frames.append(cur)
                continue
            parts = ln.split()
            if cur is not None:
                cur[parts[0]] = [float(v) for v in parts[1:]]
    return frames


@dataclass
class Motion:
    """FK result in CMU world metres. names: bone names; pos_end[name] (N,3); rot[name] (N,3,3)."""
    fps: float
    pos_end: dict[str, np.ndarray]
    rot: dict[str, np.ndarray]
    skeleton: Skeleton

    @property
    def n(self) -> int:
        return len(self.pos_end["root"])


def fk(skel: Skeleton, frames: list[dict[str, list[float]]], fps: float = 120.0,
       start: int = 0, end: int | None = None) -> Motion:
    frames = frames[start:end]
    n = len(frames)
    rot: dict[str, np.ndarray] = {}
    pos: dict[str, np.ndarray] = {}
    deg = np.pi / 180.0
    for name in skel.order:
        bone = skel.bones[name]
        if name == "root":
            vals = np.array([f["root"] for f in frames])
            idx = {k: j for j, k in enumerate(skel.root_order)}
            t = np.stack([vals[:, idx["TX"]], vals[:, idx["TY"]], vals[:, idx["TZ"]]], axis=1) * skel.scale
            R = euler_batch(vals[:, idx["RX"]] * deg, vals[:, idx["RY"]] * deg, vals[:, idx["RZ"]] * deg)
            rot[name] = R
            pos[name] = t
            continue
        C = euler_sxyz(*(bone.axis * deg))
        Ci = C.T
        ang = np.zeros((n, 3))
        if bone.dof:
            vals = np.array([f.get(name, [0.0] * len(bone.dof)) for f in frames])
            for j, d in enumerate(bone.dof):
                ang[:, "xyz".index(d[1])] = vals[:, j] * deg
        M = euler_batch(ang[:, 0], ang[:, 1], ang[:, 2])
        L = C[None] @ M @ Ci[None]
        R = rot[bone.parent] @ L
        rot[name] = R
        pos[name] = pos[bone.parent] + bone.length * (R @ bone.direction)
    return Motion(fps, pos, rot, skel)


def load(asf: str, amc: str, fps: float = 120.0, start: int = 0, end: int | None = None) -> Motion:
    skel = parse_asf(asf)
    return fk(skel, parse_amc(amc), fps, start, end)


if __name__ == "__main__":
    import sys
    m = load(sys.argv[1], sys.argv[2])
    print("frames", m.n, "bones", len(m.pos_end))
    for k in ["root", "lfemur", "ltibia", "lfoot", "ltoes", "thorax", "head", "lhumerus", "lradius", "lwrist"]:
        p = m.pos_end[k]
        print(f"{k:10s} first {np.round(p[0], 3)}  min y {p[:, 1].min():.3f}")
