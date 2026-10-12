"""FightingLab mocap loader (research reference implementation).

Parses CMU ASF/AMC and BVH (ACCAD MotionBuilder skeleton, Blender BVH exports, 100STYLE)
into per-frame WORLD joint positions (meters, Y-up, right-handed) plus a canonical
24-joint set shared by all sources.

    from mocap import load_motion
    mo = load_motion(r"raw\\cmu\\14\\14_01.amc")          # ASF found next to it (<subject>.asf)
    mo = load_motion(r"raw\\accad\\Male2\\Male2_E1_JabLeft.bvh")
    mo.fps, mo.n_frames, mo.names, mo.parents, mo.positions   # (N, J, 3) meters, all joints
    mo.canon(), mo.canon_names                                   # (N, 24, 3) canonical joints

Conventions
- Units: meters. CMU ASF "length 0.45" => 1 ASF unit = (1/0.45) inch = 0.0564444 m. BVH: cm by default
  (ACCAD/100STYLE), override with load_motion(..., unit_scale=...). Blender BVH exports are in meters.
- Axes: all sources are Y-up already; nothing is flipped. Facing differs per file - use facing_frame().
- Frames: native file frames, 0-based (AMC frame "1" == index 0).
"""
from __future__ import annotations

import os
import re
import numpy as np

CANON = [
    "pelvis", "spine", "chest", "neck", "head", "headtop",
    "lclav", "lshoulder", "lelbow", "lwrist", "lhand",
    "rclav", "rshoulder", "relbow", "rwrist", "rhand",
    "lhip", "lknee", "lankle", "ltoe",
    "rhip", "rknee", "rankle", "rtoe",
]
CANON_BONES = [
    ("pelvis", "spine"), ("spine", "chest"), ("chest", "neck"), ("neck", "head"), ("head", "headtop"),
    ("chest", "lclav"), ("lclav", "lshoulder"), ("lshoulder", "lelbow"), ("lelbow", "lwrist"), ("lwrist", "lhand"),
    ("chest", "rclav"), ("rclav", "rshoulder"), ("rshoulder", "relbow"), ("relbow", "rwrist"), ("rwrist", "rhand"),
    ("pelvis", "lhip"), ("lhip", "lknee"), ("lknee", "lankle"), ("lankle", "ltoe"),
    ("pelvis", "rhip"), ("rhip", "rknee"), ("rknee", "rankle"), ("rankle", "rtoe"),
]

# canonical joint -> candidate source joint names (first match wins).
# CMU names are BONE END points ("lfemur" end = knee); BVH names are joint origins.
CANON_MAP = {
    "pelvis": ["Hips", "hips", "pelvis", "Pelvis", "Hip", "root"],
    "spine": ["lowerback", "Spine", "spine", "spine_01", "Spine1", "Chest", "abdomen"],
    "chest": ["thorax", "Spine1", "spine_03", "Spine2", "Chest4", "Chest3", "Chest", "chest", "Chest2", "spine.003", "spine.002"],
    "neck": ["lowerneck", "Neck", "neck", "neck_01"],
    "head": ["upperneck", "Head", "head"],
    "headtop": ["Head_End", "HeadTop_End", "Head_end", "head_End", "head"],
    "lclav": ["lclavicle", "LeftCollar", "LeftShoulder", "shoulder.L", "clavicle_l", "upperarm_l_parent"],
    "lshoulder": ["lclavicle", "LeftArm", "LeftUpArm", "upper_arm.L", "upperarm_l", "LeftShoulder"],
    "lelbow": ["lhumerus", "LeftForeArm", "LeftLowArm", "forearm.L", "lowerarm_l", "LeftElbow"],
    "lwrist": ["lradius", "LeftHand", "hand.L", "hand_l", "LeftWrist"],
    "lhand": ["lhand", "LeftHand_End", "LeftHandIndex1", "LeftFinger", "hand.L_End", "hand_l_End", "middle_01_l", "LeftWrist_End"],
    "rclav": ["rclavicle", "RightCollar", "RightShoulder", "shoulder.R", "clavicle_r"],
    "rshoulder": ["rclavicle", "RightArm", "RightUpArm", "upper_arm.R", "upperarm_r", "RightShoulder"],
    "relbow": ["rhumerus", "RightForeArm", "RightLowArm", "forearm.R", "lowerarm_r", "RightElbow"],
    "rwrist": ["rradius", "RightHand", "hand.R", "hand_r", "RightWrist"],
    "rhand": ["rhand", "RightHand_End", "RightHandIndex1", "RightFinger", "hand.R_End", "hand_r_End", "middle_01_r", "RightWrist_End"],
    "lhip": ["lhipjoint", "LeftUpLeg", "LeftHip", "thigh.L", "thigh_l"],
    "lknee": ["lfemur", "LeftLeg", "LeftKnee", "LeftLowLeg", "shin.L", "calf_l"],
    "lankle": ["ltibia", "LeftFoot", "LeftAnkle", "foot.L", "foot_l"],
    "ltoe": ["lfoot", "LeftToeBase", "LeftToe", "toe.L", "ball_l", "LeftFoot_End"],
    "rhip": ["rhipjoint", "RightUpLeg", "RightHip", "thigh.R", "thigh_r"],
    "rknee": ["rfemur", "RightLeg", "RightKnee", "RightLowLeg", "shin.R", "calf_r"],
    "rankle": ["rtibia", "RightFoot", "RightAnkle", "foot.R", "foot_r"],
    "rtoe": ["rfoot", "RightToeBase", "RightToe", "toe.R", "ball_r", "RightFoot_End"],
}
# CMU: the shoulder joint is the END of the clavicle bone, the clavicle START is the thorax end.
CMU_OVERRIDES = {"lclav": "thorax", "rclav": "thorax"}


# ---------------------------------------------------------------- rotations (vectorised over frames)
def _rx(a):
    c, s = np.cos(a), np.sin(a)
    o, z = np.ones_like(a), np.zeros_like(a)
    return np.stack([np.stack([o, z, z], -1), np.stack([z, c, -s], -1), np.stack([z, s, c], -1)], -2)


def _ry(a):
    c, s = np.cos(a), np.sin(a)
    o, z = np.ones_like(a), np.zeros_like(a)
    return np.stack([np.stack([c, z, s], -1), np.stack([z, o, z], -1), np.stack([-s, z, c], -1)], -2)


def _rz(a):
    c, s = np.cos(a), np.sin(a)
    o, z = np.ones_like(a), np.zeros_like(a)
    return np.stack([np.stack([c, -s, z], -1), np.stack([s, c, z], -1), np.stack([z, z, o], -1)], -2)


_ROT = {"x": _rx, "y": _ry, "z": _rz}


class Motion:
    def __init__(self, names, parents, positions, fps, fmt, skeleton, path, rotations=None):
        self.names = list(names)
        self.parents = list(parents)
        self.positions = positions  # (N, J, 3) meters, world
        self.rotations = rotations  # (N, J, 3, 3) world rotation matrices (optional)
        self.fps = float(fps)
        self.format = fmt
        self.skeleton = skeleton
        self.path = path
        self._canon = None

    @property
    def n_frames(self):
        return self.positions.shape[0]

    def index(self, name):
        return self.names.index(name)

    def canon_indices(self):
        idx = []
        lower = {n.lower(): i for i, n in enumerate(self.names)}
        for c in CANON:
            if self.format == "asf/amc" and c in CMU_OVERRIDES:
                idx.append(self.names.index(CMU_OVERRIDES[c]))
                continue
            found = None
            for cand in CANON_MAP[c]:
                if cand in self.names:
                    found = self.names.index(cand)
                    break
                if cand.lower() in lower:
                    found = lower[cand.lower()]
                    break
            if found is None:
                raise KeyError(f"{os.path.basename(self.path)}: no joint for canonical '{c}'")
            idx.append(found)
        return idx

    @property
    def canon_names(self):
        return list(CANON)

    def canon(self):
        if self._canon is None:
            self._canon = self.positions[:, self.canon_indices(), :]
        return self._canon


# ---------------------------------------------------------------- BVH
def parse_bvh(path):
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        text = f.read()
    head, _, motion = text.partition("MOTION")
    names, parents, offsets, channels = [], [], [], []
    stack, pending = [], None
    for raw in head.splitlines():
        parts = raw.strip().split()
        if not parts:
            continue
        key = parts[0]
        if key in ("ROOT", "JOINT"):
            names.append(parts[1] if len(parts) > 1 else f"joint{len(names)}")
            parents.append(stack[-1] if stack else -1)
            offsets.append([0.0, 0.0, 0.0])
            channels.append([])
            pending = len(names) - 1
        elif key == "End":
            par = stack[-1]
            names.append(names[par] + "_End")
            parents.append(par)
            offsets.append([0.0, 0.0, 0.0])
            channels.append([])
            pending = len(names) - 1
        elif key == "{":
            stack.append(pending)
        elif key == "}":
            stack.pop()
        elif key == "OFFSET":
            offsets[pending] = [float(v) for v in parts[1:4]]
        elif key == "CHANNELS":
            n = int(parts[1])
            channels[pending] = parts[2:2 + n]
    mlines = motion.strip().splitlines()
    n_frames = int(re.search(r"Frames:\s*(\d+)", mlines[0]).group(1))
    frame_time = float(re.search(r"Frame Time:\s*([0-9.eE+-]+)", mlines[1]).group(1))
    rows = [l for l in mlines[2:] if l.strip()]
    data = np.array([[float(v) for v in l.split()] for l in rows[:n_frames]], dtype=np.float64)
    return names, parents, np.array(offsets), channels, data, frame_time


def fk_bvh(names, parents, offsets, channels, data):
    n = data.shape[0]
    J = len(names)
    gp = np.zeros((n, J, 3))
    gr = np.zeros((n, J, 3, 3))
    col = 0
    eye = np.broadcast_to(np.eye(3), (n, 3, 3))
    for j in range(J):
        local_p = np.broadcast_to(offsets[j], (n, 3)).copy()
        R = eye.copy()
        has_pos = False
        for ch in channels[j]:
            v = data[:, col]
            col += 1
            axis = ch[0].lower()
            if ch.lower().endswith("position"):
                if not has_pos:
                    local_p = np.zeros((n, 3))
                    has_pos = True
                local_p[:, "xyz".index(axis)] = v
            else:
                R = R @ _ROT[axis](np.deg2rad(v))
        p = parents[j]
        if p < 0:
            gp[:, j] = local_p
            gr[:, j] = R
        else:
            gp[:, j] = gp[:, p] + np.einsum("nij,nj->ni", gr[:, p], local_p)
            gr[:, j] = gr[:, p] @ R
    return gp, gr


def load_bvh(path, unit_scale=None, up="auto"):
    names, parents, offsets, channels, data, frame_time = parse_bvh(path)
    gp, gr = fk_bvh(names, parents, offsets, channels, data)
    if up == "auto":
        up = rest_up_axis(names, parents, offsets)
    if up == "z":  # Blender BVH exports are Z-up: (x, y, z) -> (x, z, -y)
        gp = np.stack([gp[..., 0], gp[..., 2], -gp[..., 1]], -1)
        Rz2y = np.array([[1.0, 0, 0], [0, 0, 1.0], [0, -1.0, 0]])
        gr = np.einsum("ij,nkjl->nkil", Rz2y, gr)
    if unit_scale is None:
        # guess: leg length (hip->ankle) ~0.8-1.0 m in meters; ~80-100 in cm; ~32-40 in inches
        unit_scale = guess_unit_scale(names, gp)
    skel = "bvh:" + ",".join(n for n in names if not n.endswith("_End"))
    mo = Motion(names, parents, gp * unit_scale, round(1.0 / frame_time, 3), "bvh", skel, path, gr)
    mo.up_axis = up
    return mo


def rest_up_axis(names, parents, offsets):
    """Up axis from the REST skeleton (accumulated OFFSETs root->head). 'z' only when Z clearly dominates
    (Blender BVH exports); MotionBuilder/other rests that are not upright default to 'y'."""
    head = None
    for i, n in enumerate(names):
        if n.lower() == "head":
            head = i
    if head is None:
        return "y"
    v = np.zeros(3)
    j = head
    while j >= 0 and parents[j] >= 0:  # exclude the root OFFSET (it is just a start position)
        v += offsets[j]
        j = parents[j]
    a = np.abs(v)
    if a[2] > 2.0 * max(a[0], a[1]):
        return "z"
    return "y"


def guess_unit_scale(names, gp):
    ys = gp[0, :, 1]
    height = ys.max() - ys.min()
    if height < 3.0:
        return 1.0  # meters
    if height < 120.0 and height > 40.0 and any(n.startswith("Left") for n in names):
        return 0.0254 if height < 80 else 0.01
    return 0.01


# ---------------------------------------------------------------- ASF/AMC
def parse_asf(path):
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        lines = [l.split("#")[0].rstrip() for l in f]
    bones = {}
    root = {"order": ["TX", "TY", "TZ", "RX", "RY", "RZ"], "axis": "XYZ", "position": [0, 0, 0], "orientation": [0, 0, 0]}
    hierarchy = {}
    length_unit = 1.0
    section = None
    cur = None
    for l in lines:
        s = l.strip()
        if not s:
            continue
        if s.startswith(":"):
            section = s.split()[0][1:]
            continue
        parts = s.split()
        if section == "units":
            if parts[0] == "length":
                length_unit = float(parts[1])
        elif section == "root":
            if parts[0] == "order":
                root["order"] = [p.upper() for p in parts[1:]]
            elif parts[0] == "axis":
                root["axis"] = parts[1].upper()
            elif parts[0] == "position":
                root["position"] = [float(v) for v in parts[1:4]]
            elif parts[0] == "orientation":
                root["orientation"] = [float(v) for v in parts[1:4]]
        elif section == "bonedata":
            if parts[0] == "begin":
                cur = {"dof": [], "axis": [0, 0, 0], "axis_order": "XYZ", "direction": [0, 0, 0], "length": 0.0}
            elif parts[0] == "end":
                bones[cur["name"]] = cur
                cur = None
            elif cur is not None:
                if parts[0] == "name":
                    cur["name"] = parts[1]
                elif parts[0] == "direction":
                    cur["direction"] = [float(v) for v in parts[1:4]]
                elif parts[0] == "length":
                    cur["length"] = float(parts[1])
                elif parts[0] == "axis":
                    cur["axis"] = [float(v) for v in parts[1:4]]
                    cur["axis_order"] = parts[4].upper() if len(parts) > 4 else "XYZ"
                elif parts[0] == "dof":
                    cur["dof"] = [p.lower() for p in parts[1:]]
        elif section == "hierarchy":
            if parts[0] in ("begin", "end"):
                continue
            hierarchy[parts[0]] = parts[1:]
    return root, bones, hierarchy, length_unit


def parse_amc(path, bones):
    frames = []
    cur = None
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for l in f:
            s = l.strip()
            if not s or s.startswith("#") or s.startswith(":"):
                continue
            parts = s.split()
            if len(parts) == 1 and parts[0].isdigit():
                cur = {}
                frames.append(cur)
                continue
            if cur is not None:
                cur[parts[0]] = [float(v) for v in parts[1:]]
    return frames


def _euler_xyz(ax, ay, az):
    # static-axes XYZ (transforms3d 'sxyz'): R = Rz(az) @ Ry(ay) @ Rx(ax)
    return _rz(az) @ _ry(ay) @ _rx(ax)


def load_asfamc(amc_path, asf_path=None):
    if asf_path is None:
        d = os.path.dirname(amc_path)
        subj = os.path.basename(amc_path).split("_")[0]
        asf_path = os.path.join(d, subj + ".asf")
    root, bones, hierarchy, length_unit = parse_asf(asf_path)
    frames = parse_amc(amc_path, bones)
    n = len(frames)
    scale = (1.0 / length_unit) * 0.0254  # ASF units -> inches -> meters
    order = ["root"]
    parents = [-1]
    queue = ["root"]
    while queue:
        b = queue.pop(0)
        for c in hierarchy.get(b, []):
            order.append(c)
            parents.append(order.index(b))
            queue.append(c)
    J = len(order)
    gp = np.zeros((n, J, 3))
    gr = np.zeros((n, J, 3, 3))
    # root
    rvals = np.array([fr.get("root", [0] * 6) for fr in frames])
    rd = {k: rvals[:, i] for i, k in enumerate(root["order"])}
    z = np.zeros(n)
    Lr = _euler_xyz(np.deg2rad(rd.get("RX", z)), np.deg2rad(rd.get("RY", z)), np.deg2rad(rd.get("RZ", z)))
    o = np.deg2rad(np.array(root["orientation"]))
    Cr = _euler_xyz(o[0:1], o[1:2], o[2:3])[0]
    gr[:, 0] = Cr @ Lr @ np.linalg.inv(Cr)
    gp[:, 0] = np.stack([rd.get("TX", z), rd.get("TY", z), rd.get("TZ", z)], -1) + np.array(root["position"])
    for j in range(1, J):
        b = bones[order[j]]
        p = parents[j]
        a = np.deg2rad(np.array(b["axis"]))
        C = _euler_xyz(a[0:1], a[1:2], a[2:3])[0]
        Cinv = np.linalg.inv(C)
        vals = {"rx": z, "ry": z, "rz": z}
        if b["dof"]:
            arr = np.array([fr.get(order[j], [0] * len(b["dof"])) for fr in frames])
            for k, dname in enumerate(b["dof"]):
                if dname in vals and k < arr.shape[1]:
                    vals[dname] = np.deg2rad(arr[:, k])
        L = _euler_xyz(vals["rx"], vals["ry"], vals["rz"])
        gr[:, j] = gr[:, p] @ C @ L @ Cinv
        d = np.array(b["direction"]) * b["length"]
        gp[:, j] = gp[:, p] + np.einsum("nij,j->ni", gr[:, j], d)
    skel = "cmu-asf(" + os.path.basename(asf_path) + ")"
    return Motion(order, parents, gp * scale, 120.0, "asf/amc", skel, amc_path, gr)


def load_motion(path, fps=None, unit_scale=None):
    ext = os.path.splitext(path)[1].lower()
    if ext == ".amc":
        mo = load_asfamc(path)
    elif ext == ".bvh":
        mo = load_bvh(path, unit_scale)
    else:
        raise ValueError(f"unsupported format: {path}")
    if fps:
        mo.fps = float(fps)
    return mo


# ---------------------------------------------------------------- analysis helpers
def facing_frame(canon, frame=0, window=5):
    """Return (forward, left) unit vectors in the XZ plane at a frame (averaged over a small window)."""
    a, b = max(0, frame - window), min(canon.shape[0], frame + window + 1)
    ci = {n: i for i, n in enumerate(CANON)}
    lat = (canon[a:b, ci["lhip"]] - canon[a:b, ci["rhip"]]) + (canon[a:b, ci["lshoulder"]] - canon[a:b, ci["rshoulder"]])
    lat = lat.mean(0)
    lat[1] = 0.0
    lat /= np.linalg.norm(lat) + 1e-9
    up = np.array([0.0, 1.0, 0.0])
    fwd = np.cross(lat, up)
    fwd /= np.linalg.norm(fwd) + 1e-9
    return fwd, lat


def to_local(canon, frame=0):
    """Express positions in the actor frame at `frame`: x = actor-left, y = up, z = forward, origin = pelvis XZ, floor y=0."""
    fwd, lat = facing_frame(canon, frame)
    ci = {n: i for i, n in enumerate(CANON)}
    origin = canon[frame, ci["pelvis"]].copy()
    floor = np.percentile(np.minimum(canon[:, ci["ltoe"], 1], canon[:, ci["rtoe"], 1]), 2)
    rel = canon - origin
    out = np.stack([rel @ lat, canon[..., 1] - floor, rel @ fwd], -1)
    return out


def detect_contact(local, a, b, effector):
    """Frame in [a,b] where `effector` (canonical name) reaches furthest forward (z) - strike contact/max extension."""
    ci = {n: i for i, n in enumerate(CANON)}
    z = local[a:b + 1, ci[effector], 2]
    return a + int(np.argmax(z)), float(z.max())


if __name__ == "__main__":
    import sys
    for p in sys.argv[1:]:
        mo = load_motion(p)
        c = mo.canon()
        h = c[0, CANON.index("headtop"), 1] - min(c[0, CANON.index("ltoe"), 1], c[0, CANON.index("rtoe"), 1])
        print(f"{os.path.basename(p)}: {mo.n_frames} frames @ {mo.fps} fps, {len(mo.names)} joints, height~{h:.2f} m, {mo.skeleton[:80]}")
