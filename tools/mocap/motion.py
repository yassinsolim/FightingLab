"""Generic skeletal motion: joints, FK, rest pose. Sources: BVH files and CMU ASF/AMC (via asfamc).

Motion.pos[j]   (N,3) world position of joint j (source units, source axes)
Motion.rot[j]   (N,3,3) world rotation of joint j: orients the segment from j to its children
Motion.rest[j]  (3,) joint position in the zero-rotation rest pose
Motion.restRot[j] (3,3) world rotation of joint j in the rest pose (identity for BVH and CMU)
Motion.parent[j] parent joint name (None for the root)
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field

import numpy as np

import asfamc


def _axis_rot(axis: str, ang: np.ndarray) -> np.ndarray:
    c, s = np.cos(ang), np.sin(ang)
    n = len(ang)
    R = np.zeros((n, 3, 3))
    if axis == "X":
        R[:, 0, 0] = 1; R[:, 1, 1] = c; R[:, 1, 2] = -s; R[:, 2, 1] = s; R[:, 2, 2] = c
    elif axis == "Y":
        R[:, 1, 1] = 1; R[:, 0, 0] = c; R[:, 0, 2] = s; R[:, 2, 0] = -s; R[:, 2, 2] = c
    else:
        R[:, 2, 2] = 1; R[:, 0, 0] = c; R[:, 0, 1] = -s; R[:, 1, 0] = s; R[:, 1, 1] = c
    return R


@dataclass
class Motion:
    fps: float
    pos: dict[str, np.ndarray]
    rot: dict[str, np.ndarray]
    rest: dict[str, np.ndarray]
    parent: dict[str, str | None]
    children: dict[str, list[str]] = field(default_factory=dict)
    kind: str = "bvh"
    units: float = 1.0  # metres per source unit (informational)

    @property
    def n(self) -> int:
        return len(next(iter(self.pos.values())))


# BVH ------------------------------------------------------------------------------------------------------------

def load_bvh(path: str, start: int = 0, end: int | None = None) -> Motion:
    tokens = open(path, "r", encoding="latin-1").read().split()
    i = 0
    joints: list[dict] = []
    stack: list[int] = []
    end_count = 0

    def expect(tok):
        nonlocal i
        if tokens[i] != tok:
            raise ValueError(f"BVH parse: expected {tok} got {tokens[i]} at {i}")
        i += 1

    expect("HIERARCHY")
    while tokens[i] != "MOTION":
        t = tokens[i]
        if t in ("ROOT", "JOINT"):
            name = tokens[i + 1]
            i += 2
            joints.append({"name": name, "parent": stack[-1] if stack else None, "offset": None, "channels": [], "end": False})
            stack.append(len(joints) - 1)
        elif t == "End":
            # End Site: a leaf with an offset and no channels.
            parent = stack[-1]
            end_count += 1
            joints.append({"name": joints[parent]["name"] + "_End", "parent": parent, "offset": None, "channels": [], "end": True})
            stack.append(len(joints) - 1)
            i += 2
        elif t == "{":
            i += 1
        elif t == "}":
            stack.pop()
            i += 1
        elif t == "OFFSET":
            joints[stack[-1]]["offset"] = np.array([float(tokens[i + 1]), float(tokens[i + 2]), float(tokens[i + 3])])
            i += 4
        elif t == "CHANNELS":
            n = int(tokens[i + 1])
            joints[stack[-1]]["channels"] = tokens[i + 2:i + 2 + n]
            i += 2 + n
        else:
            raise ValueError(f"BVH parse: unexpected token {t}")
    expect("MOTION")
    expect("Frames:")
    nframes = int(tokens[i]); i += 1
    expect("Frame")
    expect("Time:")
    frame_time = float(tokens[i]); i += 1
    nch = sum(len(j["channels"]) for j in joints)
    data = np.array(tokens[i:i + nframes * nch], dtype=float).reshape(nframes, nch)
    data = data[start:end]
    n = len(data)
    pos: dict[str, np.ndarray] = {}
    rot: dict[str, np.ndarray] = {}
    rest: dict[str, np.ndarray] = {}
    parent: dict[str, str | None] = {}
    children: dict[str, list[str]] = {j["name"]: [] for j in joints}
    col = 0
    deg = np.pi / 180
    for j in joints:
        name = j["name"]
        pj = joints[j["parent"]]["name"] if j["parent"] is not None else None
        parent[name] = pj
        if pj:
            children[pj].append(name)
        R_local = np.repeat(np.eye(3)[None], n, axis=0)
        trans = None
        for ch in j["channels"]:
            v = data[:, col]
            col += 1
            if ch.endswith("position"):
                if trans is None:
                    trans = np.zeros((n, 3))
                trans[:, "XYZ".index(ch[0])] = v
            else:
                R_local = R_local @ _axis_rot(ch[0], v * deg)
        off = j["offset"] if j["offset"] is not None else np.zeros(3)
        # A joint with position channels uses them instead of its OFFSET (Blender exports animate every joint's
        # translation, e.g. the Quaternius pelvis carries the body's height).
        local = trans if trans is not None else np.repeat(off[None], n, axis=0)
        if pj is None:
            p = local
            pos[name] = p
            rot[name] = R_local
            rest[name] = off.copy()
        else:
            Rp = rot[pj]
            pos[name] = pos[pj] + np.einsum("nij,nj->ni", Rp, local)
            rot[name] = Rp @ R_local
            rest[name] = rest[pj] + off
    units = 0.01
    up = _rest_up_axis(joints)
    if up == "z":
        # Blender BVH exports (Quaternius) are Z-up and in metres: (x, y, z) -> (x, z, -y).
        C = np.array([[1.0, 0, 0], [0, 0, 1.0], [0, -1.0, 0]])
        pos = {k: v @ C.T for k, v in pos.items()}
        rot = {k: C[None] @ v for k, v in rot.items()}
        rest = {k: C @ v for k, v in rest.items()}
    heights = np.array([v[1] for v in rest.values()])
    if heights.max() - heights.min() < 3.0:
        units = 1.0
    return Motion(1.0 / frame_time, pos, rot, rest, parent, children, "bvh", units)


def _rest_up_axis(joints: list[dict]) -> str:
    """'z' when the rest skeleton's root->head chain clearly points along Z (Blender exports), else 'y'."""
    head = next((i for i, j in enumerate(joints) if j["name"].lower() == "head"), None)
    if head is None:
        return "y"
    v = np.zeros(3)
    i = head
    while i is not None and joints[i]["parent"] is not None:
        if joints[i]["offset"] is not None:
            v += joints[i]["offset"]
        i = joints[i]["parent"]
    a = np.abs(v)
    return "z" if a[2] > 2.0 * max(a[0], a[1]) else "y"


# CMU ----------------------------------------------------------------------------------------------------------------

def load_cmu(asf: str, amc: str, fps: float, start: int = 0, end: int | None = None) -> Motion:
    """CMU: joints are bone END points; rot[b] is the bone's own rotation (it rigidly carries the bone's end and the
    start of its children)."""
    skel = asfamc.parse_asf(asf)
    frames = asfamc.parse_amc(amc)
    m = asfamc.fk(skel, frames, fps, start, end)
    zero = [{name: [0.0] * len(b.dof) for name, b in skel.bones.items() if name != "root"}]
    zero[0]["root"] = [0.0] * 6
    r = asfamc.fk(skel, zero, fps)
    rest = {k: v[0] for k, v in r.pos_end.items()}
    parent = {name: b.parent for name, b in skel.bones.items()}
    children = {name: list(b.children) for name, b in skel.bones.items()}
    return Motion(fps, dict(m.pos_end), dict(m.rot), rest, parent, children, "cmu", 1.0)
