--!strict
-- Samples decoded FLClip1 clips (see ClipLibrary) into heading-space poses for MotionPlayer, and maps attack frame
-- data onto clip time so the clip's contact frame lands exactly on the move's first active frame.
local ClipLibrary = require(script.Parent.ClipLibrary)

export type Clip = ClipLibrary.Clip
export type SampleOptions = { mirror: boolean?, legLength: number, scale: number }

local ClipPlayer = {}

-- Reference-rig constants shared with MotionPlayer.apply (library space, scale 1): shoulders at (+-0.5, 1.1, 0) with
-- 1.95 reach, hips at (+-0.3, -0.35, 0) with 2.75 hip-to-sole reach.
ClipPlayer.REF_SHOULDER = 0.5
ClipPlayer.REF_SHOULDER_Y = 1.1
ClipPlayer.REF_ARM = 1.95
ClipPlayer.REF_HIP = 0.3
ClipPlayer.REF_HIP_Y = -0.35
ClipPlayer.REF_LEG = 2.75

local LIMB_BASE = ClipLibrary.LIMB_BASE
local MIRROR_LIMB = { LeftHand = "RightHand", RightHand = "LeftHand", LeftFoot = "RightFoot", RightFoot = "LeftFoot" }

local function frameIndex(clip: Clip, t: number): (number, number, number)
	local n = clip.frames
	if n <= 1 then return 1, 1, 0 end
	local f = t * clip.fps
	if clip.loop then
		f = f % n
		local i0 = math.floor(f)
		local i1 = (i0 + 1) % n
		return i0 + 1, i1 + 1, f - i0
	end
	f = math.clamp(f, 0, n - 1)
	local i0 = math.floor(f)
	local i1 = math.min(i0 + 1, n - 1)
	return i0 + 1, i1 + 1, f - i0
end

local function ch(clip: Clip, c: number, i0: number, i1: number, a: number): number
	local v = clip.channels[c]
	if type(v) == "number" then return v end
	local x0 = v[i0]
	return x0 + (v[i1] - x0) * a
end

-- A foot contact channel at clip time t, median of three neighbouring clip frames: mocap contact detection wobbles for
-- a frame at touchdown (0.55, 0.76, 0.70, 0.91), which made the planted foot flatten, lift and flatten again. Steps
-- keep their exact timing (the median of three preserves a monotone edge).
local function contactAt(clip: Clip, c: number, t: number): number
	local v = clip.channels[c]
	if type(v) == "number" then return v end
	local fps = clip.fps or 30
	local i0, i1, a = frameIndex(clip, t)
	local m = ch(clip, c, i0, i1, a)
	local j0, j1, b = frameIndex(clip, t - 1 / fps)
	local p = ch(clip, c, j0, j1, b)
	local k0, k1, d = frameIndex(clip, t + 1 / fps)
	local n = ch(clip, c, k0, k1, d)
	return math.max(math.min(p, m), math.min(math.max(p, m), n))
end

local function vec(clip: Clip, c: number, i0: number, i1: number, a: number, mirror: boolean): Vector3
	local x = ch(clip, c, i0, i1, a)
	if mirror then x = -x end
	return Vector3.new(x, ch(clip, c + 1, i0, i1, a), ch(clip, c + 2, i0, i1, a))
end

local function quat(clip: Clip, c: number, i0: number, i1: number, a: number, mirror: boolean): CFrame
	local channels = clip.channels
	local function comp(k: number): (number, number)
		local v = channels[c + k]
		if type(v) == "number" then return v, v end
		return v[i0], v[i1]
	end
	local x0, x1 = comp(0)
	local y0, y1 = comp(1)
	local z0, z1 = comp(2)
	local w0, w1 = comp(3)
	if x0 * x1 + y0 * y1 + z0 * z1 + w0 * w1 < 0 then x1, y1, z1, w1 = -x1, -y1, -z1, -w1 end
	local x, y, z, w = x0 + (x1 - x0) * a, y0 + (y1 - y0) * a, z0 + (z1 - z0) * a, w0 + (w1 - w0) * a
	local len = math.sqrt(x * x + y * y + z * z + w * w)
	if len < 1e-6 then return CFrame.identity end
	if mirror then y, z = -y, -z end
	return CFrame.new(0, 0, 0, x / len, y / len, z / len, w / len)
end

-- Library space (+Z toward the opponent) from clip space (Roblox heading space, -Z toward the opponent).
local function lib(v: Vector3): Vector3 return Vector3.new(v.X, v.Y, -v.Z) end

local function euler(cf: CFrame): Vector3
	local x, y, z = cf:ToEulerAnglesXYZ()
	return Vector3.new(x, y, z)
end

-- Pose (heading space) at clip time `t` seconds. legLength: the rig's hip-to-sole length in studs (root motion
-- scale); scale: MotionPlayer's reference scale (RootHeight / 3) used by effector positions.
function ClipPlayer.sample(clip: Clip, t: number, opts: SampleOptions): any
	local mirror = opts.mirror == true
	local s = opts.scale
	local i0, i1, a = frameIndex(clip, t)
	local rootPos = vec(clip, ClipLibrary.ROOT_POS, i0, i1, a, mirror)
	local rootRot = quat(clip, ClipLibrary.ROOT_ROT, i0, i1, a, mirror)
	local waistRot = quat(clip, ClipLibrary.WAIST, i0, i1, a, mirror)
	local neckRot = quat(clip, ClipLibrary.NECK, i0, i1, a, mirror)
	local targets = {}
	for _, limb in ClipLibrary.LIMBS do
		local source = if mirror then MIRROR_LIMB[limb] else limb
		local base = LIMB_BASE[source]
		local rel = vec(clip, base, i0, i1, a, mirror)
		local pole = vec(clip, base + 3, i0, i1, a, mirror)
		local rot = quat(clip, base + 6, i0, i1, a, mirror)
		local isLeg = limb == "LeftFoot" or limb == "RightFoot"
		local side = if limb == "LeftHand" or limb == "LeftFoot" then -1 else 1
		local pivot = if isLeg then Vector3.new(side * ClipPlayer.REF_HIP, ClipPlayer.REF_HIP_Y, 0) else Vector3.new(side * ClipPlayer.REF_SHOULDER, ClipPlayer.REF_SHOULDER_Y, 0)
		local reach = if isLeg then ClipPlayer.REF_LEG else ClipPlayer.REF_ARM
		-- Feet also carry the clip's own sole height above the floor (leg lengths: 1 + pelvis height + hip->sole), so the
		-- runtime can tell a foot the clip holds on the floor from one it lifts, whatever the rig's proportions.
		targets[limb] = { pos = (pivot + lib(rel) * reach) * s, pole = lib(pole), rot = rot, weight = 1, sole = if isLeg then 1 + rootPos.Y + rel.Y else nil }
	end
	local contactL = contactAt(clip, if mirror then ClipLibrary.CONTACT_RIGHT else ClipLibrary.CONTACT_LEFT, t)
	local contactR = contactAt(clip, if mirror then ClipLibrary.CONTACT_LEFT else ClipLibrary.CONTACT_RIGHT, t)
	local ground = ch(clip, ClipLibrary.GROUND, i0, i1, a)
	return {
		rootOffset = lib(rootPos) * opts.legLength,
		rootRotation = euler(rootRot), waist = euler(waistRot), neck = euler(neckRot),
		rootRot = rootRot, waistRot = waistRot, neckRot = neckRot,
		targets = targets, joints = {},
		plantedFeet = { LeftFoot = 1 - contactL, RightFoot = 1 - contactR },
		contact = { LeftFoot = contactL, RightFoot = contactR },
		ground = ground,
		space = "heading",
	}
end

-- Clip time (seconds) for an attack at sim move frame `frame` (1-based; first active frame = startup + 1).
-- Startup frames play clip [0, contact]; the first active frame shows the contact frame exactly; the active window
-- plays [contact, recover] and recovery plays [recover, end]. `recover` defaults to a third of the way to the end.
function ClipPlayer.moveTime(clip: Clip, timing: { startup: number, active: number, recovery: number }, frame: number): number
	local d = clip.duration
	local c = math.clamp(clip.contact or 0.5, 0, 1) * d
	local r = math.clamp(clip.recover or ((clip.contact or 0.5) + (1 - (clip.contact or 0.5)) / 3), clip.contact or 0.5, 1) * d
	local firstActive = timing.startup + 1
	local activeEnd = timing.startup + timing.active
	local total = activeEnd + timing.recovery
	if frame <= firstActive then return c * math.clamp(frame / math.max(firstActive, 1), 0, 1) end
	if frame <= activeEnd + 1 then return c + (r - c) * math.clamp((frame - firstActive) / math.max(activeEnd + 1 - firstActive, 1), 0, 1) end
	return r + (d - r) * math.clamp((frame - activeEnd - 1) / math.max(total - activeEnd - 1, 1), 0, 1)
end

-- Normalised [0,1] clip progress for a one-shot state that lasts `frames` sim frames.
function ClipPlayer.progressTime(clip: Clip, elapsedFrames: number, frames: number): number
	return clip.duration * math.clamp(elapsedFrames / math.max(frames, 1), 0, 1)
end

return ClipPlayer
