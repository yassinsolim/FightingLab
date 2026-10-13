--!strict
-- Motion.Cinematic (round 6): the Ultimate's two-role cinematic (docs/design/ultimates.md).
--
-- Sim (Contract A): when an Ultimate hits, both fighters are in state "Ultimate" for cinematic.duration frames and both
-- views carry `throw` = { archetype = "ultimate", move = "Ultimate", role = "Attacker" | "Defender", frame (1..duration),
-- duration, impactFrame (first impact) }; positions stay locked (the defender endDistance in front of the attacker).
-- The attacker's roster move `Ultimate` carries `cinematic = { duration, impacts = { { frame, share } }, endKind,
-- endDistance }`; without it (or with malformed data) the contract's default template is used.
--
-- Clips: an FLThrow1 bound to <Fighter>/"Ultimate" (ClipLibrary.forThrow; fighter "*" = any) with `impacts` (normalised
-- clip times). Impact k of the clip is shown exactly on the roster's impact frame k (piecewise-linear time map), both
-- roles sample the same clip time and the defender plays the ATTACKER's clip. The defender track is authored with the
-- roots `distance` attacker leg lengths apart: the runtime slides the defender so that spacing holds whatever the sim
-- spacing is, and from `release` (default: the last impact) glides it onto its sim spot by the last frame, where the
-- knockdown (Landing / KO, Motion.States) continues from the same lying pose.
--
-- Presentation slow motion (displayFrame): the final impact plays in slow motion. The display runs a little ahead of the
-- sim before it and catches up after it, so every impact still shows on its own sim frame (the UltHit events, the HUD
-- and the sound stay in sync) and the cinematic ends on the sim's last frame. Sim timing never changes.
local Roster = require(script.Parent.Parent.Parent.Roster)
local ClipLibrary = require(script.Parent.ClipLibrary)
local ClipPlayer = require(script.Parent.ClipPlayer)

local Cinematic = {}
Cinematic.MOVE = "Ultimate"
Cinematic.ARCHETYPE = "ultimate"
Cinematic.STATE = "Ultimate"
-- Contract A default template (used until a fighter's roster move carries its own timeline).
Cinematic.DEFAULT = {
	duration = 210,
	impacts = { { frame = 36, share = 0.12 }, { frame = 74, share = 0.12 }, { frame = 112, share = 0.16 }, { frame = 150, share = 0.20 }, { frame = 192, share = 0.40 } },
	endKind = "FaceUp",
	endDistance = 3.2,
}
-- Final-impact slow motion: display speed in the slow window, the most sim frames of it before / after the impact.
Cinematic.SlowFactor = 0.3
Cinematic.SlowBefore = 14
Cinematic.SlowAfter = 8
-- The defender glides into the authored spacing over the first AlignFrames cinematic frames.
Cinematic.AlignFrames = 4

export type Timeline = {
	duration: number, frames: { number }, shares: { number }, endKind: string, endDistance: number, source: string,
	slow: { l0: number, a: number, i: number, b: number, d: number, h1: number, h2: number }?,
}

local function smoothstep(x: number): number local t = math.clamp(x, 0, 1); return t * t * (3 - 2 * t) end
local function ease(kind: string?, x: number): number
	local t = math.clamp(x, 0, 1)
	if kind == "linear" then return t end
	if kind == "hold" then return if t >= 1 then 1 else 0 end
	if kind == "in" then return t * t end
	if kind == "out" then return 1 - (1 - t) * (1 - t) end
	return t * t * (3 - 2 * t)
end
Cinematic.ease = ease

-- Is this `throw` table the Ultimate's cinematic (Contract A)?
function Cinematic.isUltimate(throw: any): boolean
	return type(throw) == "table" and throw.archetype == Cinematic.ARCHETYPE
end

-- Slow-motion window of a timeline (nil = too little room around the final impact).
local function slowWindow(duration: number, frames: { number }): any
	local n = #frames
	if n == 0 then return nil end
	local s = Cinematic.SlowFactor
	local i = frames[n]
	local p = if n >= 2 then frames[n - 1] else 0
	local h2 = math.min(Cinematic.SlowAfter, (duration - i) / 3)
	local h1 = math.min(Cinematic.SlowBefore, (i - p) / 4)
	if h1 < 2 or h2 < 1 or s >= 1 then return nil end
	local a = math.min(2.5 * h1, i - p - h1 - 2)
	if a < h1 then return nil end
	return { l0 = i - h1 - a, a = i - h1, i = i, b = i + h2, d = duration, h1 = h1, h2 = h2 }
end

local function build(raw: any, source: string): Timeline?
	if type(raw) ~= "table" or type(raw.duration) ~= "number" or raw.duration < 2 or type(raw.impacts) ~= "table" or #raw.impacts == 0 then return nil end
	local frames, shares = {}, {}
	local last = 0
	for k, imp in raw.impacts do
		local f = if type(imp) == "table" then imp.frame elseif type(imp) == "number" then imp else nil
		if type(f) ~= "number" or f <= last or f > raw.duration then return nil end
		frames[k] = f
		shares[k] = if type(imp) == "table" and type(imp.share) == "number" then imp.share else 1 / #raw.impacts
		last = f
	end
	local tl: Timeline = {
		duration = raw.duration, frames = frames, shares = shares,
		endKind = if raw.endKind == "FaceDown" then "FaceDown" else "FaceUp",
		endDistance = if type(raw.endDistance) == "number" and raw.endDistance > 0 then raw.endDistance else Cinematic.DEFAULT.endDistance,
		source = source,
	}
	tl.slow = slowWindow(tl.duration, frames)
	return tl
end

local cache: { [string]: Timeline } = {}

-- The attacker's cinematic timeline: its roster `moves.Ultimate.cinematic`, else the default template. The sim's own
-- `throw.duration` wins when it differs (the impact frames scale with it).
function Cinematic.timeline(attackerId: string?, throw: any?): Timeline
	local key = if type(attackerId) == "string" then attackerId else "?"
	local tl = cache[key]
	if not tl then
		local raw = nil
		if type(attackerId) == "string" then
			local ok, def = pcall(function() return if Roster.has(attackerId) then Roster.get(attackerId) else nil end)
			if ok and type(def) == "table" and type(def.moves) == "table" then
				local m = def.moves[Cinematic.MOVE]
				if type(m) == "table" then raw = m.cinematic end
			end
		end
		tl = build(raw, "roster") or (build(Cinematic.DEFAULT, "default") :: Timeline)
		cache[key] = tl
	end
	local t = tl :: Timeline
	if type(throw) == "table" and type(throw.duration) == "number" and throw.duration >= 2 and math.abs(throw.duration - t.duration) > 0.5 then
		local k = throw.duration / t.duration
		local frames = {}
		for i, f in t.frames do frames[i] = math.clamp(f * k, 1, throw.duration) end
		local scaled = table.clone(t)
		scaled.duration, scaled.frames, scaled.source = throw.duration, frames, t.source .. "+scaled"
		scaled.slow = slowWindow(scaled.duration, frames)
		return scaled
	end
	return t
end

function Cinematic.clearCache()
	table.clear(cache)
end

-- The Ultimate clip of an attacker (fighter-specific beats the generic "*" one), or nil.
function Cinematic.clip(attackerId: string?): ClipLibrary.ThrowClip?
	if type(attackerId) ~= "string" then return nil end
	return ClipLibrary.forThrow(attackerId, Cinematic.MOVE)
end

local function hermite(x0: number, y0: number, m0: number, x1: number, y1: number, m1: number, x: number): number
	local h = x1 - x0
	if h <= 1e-6 then return y1 end
	local t = (x - x0) / h
	local t2, t3 = t * t, t * t * t
	return (2 * t3 - 3 * t2 + 1) * y0 + (t3 - 2 * t2 + t) * h * m0 + (-2 * t3 + 3 * t2) * y1 + (t3 - t2) * h * m1
end

-- Presentation frame for sim cinematic frame f: the identity, except around the final impact (slow motion: shown at
-- SlowFactor speed from h1 frames before to h2 frames after it, a speed-up before and a catch-up after). Every impact
-- frame maps onto itself, and so do the first and the last frame.
function Cinematic.displayFrame(tl: Timeline, f: number): number
	local w = tl.slow
	if not w or f <= w.l0 or f >= w.d then return f end
	local s = Cinematic.SlowFactor
	if f < w.a then return hermite(w.l0, w.l0, 1, w.a, w.i - s * w.h1, s, f) end
	if f <= w.b then return w.i + (f - w.i) * s end
	return hermite(w.b, w.i + s * w.h2, s, w.d, w.d, 1, f)
end

-- Is the presentation in the final slow-motion window at sim frame f (camera and effects)?
function Cinematic.slowMotion(tl: Timeline, f: number): boolean
	local w = tl.slow
	return w ~= nil and f >= w.a and f <= w.b
end

-- Matched (sim frame, normalised clip time) control points of the time map: the clip's impacts on the timeline's. With
-- different counts the first ones pair in order and the last impact (the finisher) always pairs with the last.
local function controlPoints(tc: any, tl: Timeline): ({ number }, { number })
	local us = tc.impacts
	local fs = tl.frames
	local xs, ys = { 0 }, { 0 }
	if type(us) == "table" and #us > 0 then
		local m = math.min(#us, #fs)
		for k = 1, m - 1 do table.insert(xs, fs[k]); table.insert(ys, us[k]) end
		table.insert(xs, fs[#fs]); table.insert(ys, us[#us])
	else
		table.insert(xs, fs[1]); table.insert(ys, math.clamp(if type(tc.impact) == "number" then tc.impact else 0.6, 0, 1))
	end
	table.insert(xs, tl.duration); table.insert(ys, 1)
	return xs, ys
end

-- Normalised clip time (0..1) at cinematic frame f (fractional allowed).
function Cinematic.clipU(tc: any, tl: Timeline, f: number): number
	local xs, ys = controlPoints(tc, tl)
	local x = math.clamp(f, 0, tl.duration)
	for k = 2, #xs do
		if x <= xs[k] then
			local x0, x1 = xs[k - 1], xs[k]
			local y0, y1 = ys[k - 1], math.max(ys[k], ys[k - 1])
			if x1 - x0 <= 1e-6 then return y1 end
			return y0 + (y1 - y0) * (x - x0) / (x1 - x0)
		end
	end
	return 1
end

-- Seconds of `track` at cinematic frame f.
function Cinematic.clipTime(tc: any, tl: Timeline, f: number, track: any): number
	return Cinematic.clipU(tc, tl, f) * track.duration
end

-- Weight of the defender's spacing correction at sim frame f (clip time u): eases in over AlignFrames, holds, and from
-- `release` (default: the last impact) eases out to 0 by the end, so the last frame lies on the sim spot.
function Cinematic.alignWeight(tc: any, f: number, u: number): number
	local release = if type(tc.release) == "number" then tc.release
		elseif type(tc.impacts) == "table" and #tc.impacts > 0 then tc.impacts[#tc.impacts] else 0.85
	release = math.clamp(release, 0, 0.98)
	local wIn = smoothstep(f / math.max(Cinematic.AlignFrames, 1))
	local wOut = if u <= release then 1 else 1 - smoothstep((u - release) / math.max(1 - release, 1e-3))
	return wIn * wOut
end

-- Heading-space pose of this view's role from the attacker's Ultimate clip (nil = no clip installed; the caller falls
-- back to keyframes). ctx: attackerId, actual (sim distance between the two along the facing), attackerLeg (studs).
function Cinematic.samplePose(view: any, ctx: { attackerId: string?, actual: number?, attackerLeg: number? }, scale: number, legLength: number): (any?, Timeline)
	local throw = view.throw
	local defender = throw.role == "Defender"
	local tl = Cinematic.timeline(ctx.attackerId, throw)
	local tc = Cinematic.clip(ctx.attackerId)
	if not tc then return nil, tl end
	local f = if type(throw.frame) == "number" then throw.frame else 0
	local u = Cinematic.clipU(tc, tl, Cinematic.displayFrame(tl, f))
	local track = if defender then tc.defender else tc.attacker
	local pose = ClipPlayer.sample(track, u * track.duration, { mirror = track.mirror, legLength = legLength, scale = scale })
	if defender and type(ctx.actual) == "number" then
		local leg = if type(ctx.attackerLeg) == "number" then ctx.attackerLeg else legLength
		local shift = ctx.actual - tc.distance * leg
		local w = Cinematic.alignWeight(tc, f, u)
		if math.abs(shift) > 1e-4 and w > 0 then pose.rootOffset += Vector3.new(0, 0, shift * w) end
	end
	return pose, tl
end

-- Keyframe fallback (no clip installed anywhere): the defender takes a reaction per impact and falls after the last one
-- (Motion.States keyframes); the attacker holds its guard and lunges into each impact. `States` is passed in (it is
-- required by MotionPlayer; this module stays free of it).
function Cinematic.fallbackKeyframe(view: any, ctx: { attackerId: string? }, characterId: string, scale: number, States: any, now: number): any
	local throw = view.throw
	local tl = Cinematic.timeline(ctx.attackerId, throw)
	local f = Cinematic.displayFrame(tl, if type(throw.frame) == "number" then throw.frame else 0)
	local fs = tl.frames
	local last = fs[#fs]
	if throw.role == "Defender" then
		if f >= last then return States.knockdown(math.min(f - last + 2, 34), scale, tl.endKind) end
		local since, k = f, 0
		for i, x in fs do if f >= x then since, k = f - x, i end end
		return States.reaction(if k % 2 == 1 then "High" else "Mid", "Heavy", false, scale, if k % 2 == 1 then -1 else 1, since)
	end
	local key = States.pose(characterId, "Guard", scale, now)
	local nearest = math.huge
	for _, x in fs do nearest = math.min(nearest, math.abs(f - x)) end
	local lunge = math.max(0, 1 - nearest / 10)
	local out = table.clone(key)
	out.rootOffset = (key.rootOffset or Vector3.zero) + Vector3.new(0, -0.08 * lunge * scale, 0.35 * lunge * scale)
	out.waist = (key.waist or Vector3.zero) + Vector3.new(math.rad(10) * lunge, 0, 0)
	return out
end

-- The defender track's floor-support weight (0 standing .. 1 lying) at sim cinematic frame f: Effects/Audio present the
-- body's landing inside the cinematic when it crosses 0.5.
function Cinematic.defenderGround(tc: any, tl: Timeline, f: number): number
	local track = tc.defender
	local u = Cinematic.clipU(tc, tl, Cinematic.displayFrame(tl, f))
	local p = ClipPlayer.sample(track, u * track.duration, { legLength = 1, scale = 1 })
	return if type(p.ground) == "number" then p.ground else 0
end

-- Per-impact presentation data from the attacker's clip (`hits[k]`: the striking limb and height), or nil.
function Cinematic.hitInfo(attackerId: string?, combo: number?): { limb: string?, height: string? }?
	local tc = Cinematic.clip(attackerId)
	if not tc or type(tc.hits) ~= "table" or type(combo) ~= "number" then return nil end
	return tc.hits[combo]
end

-- Camera keys used when an Ultimate clip has none (studs, attacker frame: +X its right, +Y up, +Z toward the defender,
-- which stands ~3.2 studs ahead): a three-quarter two-shot pushing in, a reverse angle over the defender's shoulder, a
-- low profile shot for the finish and a wide end frame.
Cinematic.DEFAULT_CAMERA = {
	{ t = 0.00, pos = Vector3.new(6.2, 3.6, -2.4), look = Vector3.new(0.4, 3.0, 1.8), fov = 40, cut = true, ease = "smooth", roll = 0 },
	{ t = 0.30, pos = Vector3.new(5.0, 3.1, -0.8), look = Vector3.new(0.2, 3.0, 1.7), fov = 36, cut = false, ease = "smooth", roll = 0 },
	{ t = 0.31, pos = Vector3.new(-2.6, 3.8, 7.6), look = Vector3.new(0.0, 3.1, 0.9), fov = 36, cut = true, ease = "smooth", roll = 0 },
	{ t = 0.62, pos = Vector3.new(-3.6, 3.2, 6.6), look = Vector3.new(0.0, 3.0, 1.2), fov = 34, cut = false, ease = "smooth", roll = 0 },
	{ t = 0.63, pos = Vector3.new(6.6, 1.6, 1.4), look = Vector3.new(0.0, 2.6, 1.8), fov = 34, cut = true, ease = "smooth", roll = 0 },
	{ t = 0.88, pos = Vector3.new(7.4, 2.0, 1.2), look = Vector3.new(0.0, 2.2, 2.4), fov = 32, cut = false, ease = "smooth", roll = 0 },
	{ t = 1.00, pos = Vector3.new(9.2, 4.2, -0.6), look = Vector3.new(0.0, 1.6, 2.6), fov = 38, cut = false, ease = "out", roll = 0 },
} :: { ClipLibrary.CameraKey }

-- The cinematic camera at sim cinematic frame f: world position and look point, fov, roll (radians), the shot index (it
-- changes on a cut) and the clip time. base = the attacker's sim floor point (world), forward = its facing; mirror =
-- author x mirrored (the attacker stands on the viewer's right, so the camera stays on the viewer's side of the fight).
export type Shot = { pos: Vector3, look: Vector3, fov: number, roll: number, shot: number, u: number }
function Cinematic.cameraShot(tc: any?, tl: Timeline, f: number, base: Vector3, forward: Vector3, mirror: boolean): Shot
	local keys: { ClipLibrary.CameraKey } = if tc and type(tc.camera) == "table" and #tc.camera > 0 then tc.camera else Cinematic.DEFAULT_CAMERA
	local fd = Cinematic.displayFrame(tl, f)
	local u = if tc then Cinematic.clipU(tc, tl, fd) else math.clamp(fd / math.max(tl.duration, 1), 0, 1)
	local i = 1
	for k = 1, #keys do if keys[k].t <= u then i = k end end
	local a, b = keys[i], keys[i + 1]
	local pos, look, fov, roll = a.pos, a.look, a.fov, a.roll
	if b and not b.cut and b.t > a.t then
		local x = ease(b.ease, (u - a.t) / (b.t - a.t))
		pos, look = a.pos:Lerp(b.pos, x), a.look:Lerp(b.look, x)
		fov, roll = a.fov + (b.fov - a.fov) * x, a.roll + (b.roll - a.roll) * x
	end
	local shot = 1
	for k = 1, i do if keys[k].cut then shot = k end end
	if mirror then
		pos, look, roll = Vector3.new(-pos.X, pos.Y, pos.Z), Vector3.new(-look.X, look.Y, look.Z), -roll
	end
	local flat = Vector3.new(forward.X, 0, forward.Z)
	local fwd = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.xAxis
	local right = fwd:Cross(Vector3.yAxis)
	local function world(v: Vector3): Vector3 return base + right * v.X + Vector3.yAxis * v.Y + fwd * v.Z end
	return { pos = world(pos), look = world(look), fov = fov, roll = math.rad(roll), shot = shot, u = u }
end

-- The cinematic in a render frame: the attacker's slot, its id and the shared cinematic frame, or nil.
function Cinematic.active(frame: any): (number?, string?, number?, any?)
	if type(frame) ~= "table" or type(frame.fighters) ~= "table" then return nil end
	for i = 1, 2 do
		local v = frame.fighters[i]
		if type(v) == "table" and Cinematic.isUltimate(v.throw) and v.throw.role ~= "Defender" then
			return i, (if type(v.characterId) == "string" then v.characterId else nil), (if type(v.throw.frame) == "number" then v.throw.frame else 0), v
		end
	end
	return nil
end

return Cinematic
