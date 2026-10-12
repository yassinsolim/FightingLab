--!strict
local Roster = require(script.Parent.Parent.Parent.Roster)
local Library = require(script.Parent.Parent.MotionLibrary)
local ClipPlayer = require(script.Parent.ClipPlayer)
export type Keyframe = Library.Keyframe

local States = {}
local tierScale = { Light = 0.75, Medium = 1.0, Heavy = 1.22, Launch = 1.45 }
local styleWalk = {
	boxer = { stride = 0.28, lift = 0.20, sway = 0.08 },
	kickboxer = { stride = 0.34, lift = 0.16, sway = 0.10 },
	grappler = { stride = 0.22, lift = 0.10, sway = 0.05 },
	flow = { stride = 0.42, lift = 0.24, sway = 0.16 },
	karate = { stride = 0.30, lift = 0.09, sway = 0.04 },
	kungfu = { stride = 0.36, lift = 0.13, sway = 0.12 },
}
-- Idle rhythm per stance (studs/radians at scale 1; freq in Hz): boxers bounce fast, grapplers sway heavy and slow,
-- karate stays still and breathes, kung fu circles the lead hand.
local styleIdle = {
	boxer = { freq = 1.7, bob = 0.065, sway = 0.02, shift = 0.02, twist = 0.03, breathe = 0.015, pump = 0.06, rear = 0.03, circle = 0 },
	kickboxer = { freq = 1.25, bob = 0.045, sway = 0.015, shift = 0.05, twist = 0.025, breathe = 0.015, pump = 0.04, rear = 0.025, circle = 0 },
	grappler = { freq = 0.55, bob = 0.03, sway = 0.07, shift = 0.02, twist = 0.05, breathe = 0.02, pump = 0.05, rear = 0.05, circle = 0.02 },
	flow = { freq = 0.9, bob = 0.05, sway = 0.09, shift = 0.02, twist = 0.04, breathe = 0.012, pump = 0.03, rear = 0.03, circle = 0.02 },
	karate = { freq = 0.3, bob = 0.012, sway = 0, shift = 0.01, twist = 0.01, breathe = 0.02, pump = 0.01, rear = 0, circle = 0 },
	kungfu = { freq = 0.6, bob = 0.025, sway = 0.04, shift = 0.015, twist = 0.03, breathe = 0.015, pump = 0, rear = 0.03, circle = 0.07 },
}

local function k(t: number, rootOffset: Vector3?, rootRotation: Vector3?, waist: Vector3?, neck: Vector3?, targets: { [string]: Library.Effector }?, plant: { [string]: number }?): Keyframe
	return Library.k(t, rootOffset, rootRotation, waist, neck, targets, plant)
end

local function style(characterId: string?): string
	if characterId and Roster.has(characterId) then return Roster.get(characterId).stanceStyle end
	return "boxer"
end

function States.neutral(characterId: string?, scale: number?): Keyframe
	return Library.stanceKey(style(characterId), "Idle", scale or 1)
end

function States.pose(characterId: string?, state: string, scale: number?, now: number?): Keyframe
	local stance = style(characterId)
	local s = scale or 1
	local key = Library.stanceKey(stance, state, s)
	local time = now or 0
	local bounce = 0.03 * s
	local data = Library.StanceStyles[stance]
	if data and type(data.bounce) == "number" then bounce *= data.bounce end
	if state == "Idle" or state == "Guard" then
		-- Per-style rhythm: bounce on the balls of the feet (knees flex because the feet stay planted), lateral sway,
		-- breathing in the torso, a lead hand that pumps or circles, and a neck that counters the torso to hold the gaze.
		local idle = styleIdle[stance] or styleIdle.boxer
		local amp = if state == "Guard" then 0.5 else 1
		local w = time * math.pi * 2 * idle.freq
		local beat = math.abs(math.sin(w))
		local breath = math.sin(time * 1.55)
		key.rootOffset = (key.rootOffset or Vector3.zero) + Vector3.new(math.sin(w) * idle.sway * s, -beat * idle.bob * s, math.sin(w * 0.5) * idle.shift * s) * amp
		key.waist = (key.waist or Vector3.zero) + Vector3.new(breath * idle.breathe, math.sin(w) * idle.twist, 0) * amp
		key.neck = (key.neck or Vector3.zero) + Vector3.new(-breath * idle.breathe * 0.6, -math.sin(w) * idle.twist * 0.7, 0) * amp
		local targets = key.targets
		if targets then
			local lead, rear = targets.LeftHand, targets.RightHand
			local pump = math.max(0, math.sin(w * 0.5)) ^ 2
			if lead then
				lead.pos += Vector3.new(math.cos(w) * idle.circle, math.sin(w) * idle.circle * 0.6 + beat * idle.bob * 0.35, pump * idle.pump) * s * amp
			end
			if rear then
				rear.pos += Vector3.new(0, math.sin(w + 1.2) * idle.rear + beat * idle.bob * 0.35, 0) * s * amp
			end
		end
	elseif state == "Walk" or state == "Backwalk" then
		local spec = styleWalk[stance] or styleWalk.boxer
		local phase = time * math.pi * 2
		local dir = if state == "Backwalk" then -1 else 1
		local sinp = math.sin(phase)
		local cosp = math.cos(phase)
		local leadLift = math.max(0, sinp) * spec.lift * s
		local rearLift = math.max(0, -sinp) * spec.lift * s
		key.rootOffset = (key.rootOffset or Vector3.zero) + Vector3.new(spec.sway * sinp * 0.22 * s, (leadLift + rearLift) * 0.10, dir * 0.08 * s)
		key.rootRotation = (key.rootRotation or Vector3.zero) + Vector3.new(math.rad(-3 * dir), math.rad(6 * sinp), math.rad(-3 * sinp))
		key.waist = (key.waist or Vector3.zero) + Vector3.new(0, math.rad(-7 * sinp), math.rad(2 * sinp))
		key.targets = key.targets or {}
		key.targets.LeftFoot = Library.e(Vector3.new(-0.30 * s, -3.10 * s + leadLift, (0.72 + dir * spec.stride * cosp) * s), Vector3.new(-0.25, 0.05, 1), nil, 1)
		key.targets.RightFoot = Library.e(Vector3.new(0.32 * s, -3.10 * s + rearLift, (-0.62 - dir * spec.stride * cosp) * s), Vector3.new(0.25, 0.05, 1), nil, 1)
		key.plant = { LeftFoot = if leadLift > 0.035 * s then 0.55 else 0, RightFoot = if rearLift > 0.035 * s then 0.55 else 0 }
	elseif state == "HighCrush" then
		key = Library.stanceKey(stance, "Crouch", s)
	elseif state == "LowCrush" then
		key.rootOffset = (key.rootOffset or Vector3.zero) + Vector3.new(0, 0.65 * s, 0.08 * s)
	end
	return key
end

function States.reaction(height: string, tier: string?, counter: boolean?, scale: number?, side: number?, frame: number?): Keyframe
	local s = scale or 1
	local amp = (tierScale[tier or "Medium"] or 1) * (if counter then 1.35 else 1)
	local hitSide = if (side or 0) < 0 then -1 else 1
	local decay = 1 - math.clamp((frame or 0) / 26, 0, 0.55)
	amp *= decay
	if height == "High" then
		return k(0, Vector3.new(0.06 * hitSide * s * amp, 0.04 * s, -0.22 * s * amp), Vector3.new(math.rad(-3 * amp), math.rad(-24 * hitSide * amp), math.rad(-9 * hitSide * amp)), Vector3.new(math.rad(8 * amp), math.rad(-30 * hitSide * amp), math.rad(-12 * hitSide * amp)), Vector3.new(math.rad(36 * amp), math.rad(-42 * hitSide), math.rad(-14 * hitSide)), nil, { LeftFoot = 0, RightFoot = 0 })
	elseif height == "Low" then
		return k(0, Vector3.new(0.12 * hitSide * s, -0.62 * s * amp, -0.14 * s), Vector3.new(math.rad(18 * amp), math.rad(9 * hitSide), math.rad(24 * hitSide * amp)), Vector3.new(math.rad(18), math.rad(10 * hitSide), math.rad(18 * hitSide * amp)), Vector3.new(math.rad(12), math.rad(-12 * hitSide), math.rad(-8 * hitSide)), nil, { LeftFoot = 0.25, RightFoot = 0 })
	end
	return k(0, Vector3.new(0.04 * hitSide * s, -0.16 * s, -0.28 * s * amp), Vector3.new(math.rad(22 * amp), math.rad(12 * hitSide), math.rad(4 * hitSide)), Vector3.new(math.rad(46 * amp), math.rad(8 * hitSide), math.rad(4 * hitSide)), Vector3.new(math.rad(-22), math.rad(-12 * hitSide), 0), nil, { LeftFoot = 0, RightFoot = 0 })
end

function States.blockstun(height: string, scale: number?, side: number?): Keyframe
	local s = scale or 1
	local hitSide = if (side or 0) < 0 then -1 else 1
	local key = Library.stanceKey("boxer", if height == "Low" then "CrouchGuard" else "Block", s)
	key.rootOffset = (key.rootOffset or Vector3.zero) + Vector3.new(0.04 * hitSide * s, 0, -0.18 * s)
	key.waist = (key.waist or Vector3.zero) + Vector3.new(math.rad(6), math.rad(-8 * hitSide), math.rad(-3 * hitSide))
	return key
end

function States.stagger(scale: number?, side: number?, counter: boolean?): Keyframe
	local s = scale or 1
	local dir = if (side or 0) < 0 then -1 else 1
	local amp = if counter then 1.35 else 1
	return k(0, Vector3.new(0.22 * dir * s, -0.12 * s, -0.44 * s), Vector3.new(math.rad(8), math.rad(-32 * dir * amp), math.rad(20 * dir * amp)), Vector3.new(math.rad(30), math.rad(-30 * dir * amp), math.rad(14 * dir)), Vector3.new(math.rad(-12), math.rad(24 * dir), 0), nil, { LeftFoot = 0, RightFoot = 0.35 })
end

function States.launch(scale: number?, velocityY: number?, airFrames: number?, airHits: number?, side: number?): Keyframe
	local s = scale or 1
	local dir = if (side or 0) < 0 then -1 else 1
	local frames = airFrames or 0
	local tumble = math.rad((frames * 18) % 360)
	local lift = math.clamp((velocityY or 0) * 0.035, -0.15, 0.45)
	local hitJolt = math.min(airHits or 0, 4) * 0.08
	return k(0, Vector3.new(0.08 * dir * s * hitJolt, (0.82 + lift + hitJolt) * s, -0.20 * s), Vector3.new(math.rad(26) + tumble * 0.22, math.rad(36 * dir) + tumble * 0.16, math.rad(-34 * dir)), Vector3.new(math.rad(18), math.rad(20 * dir), math.rad(-16 * dir)), Vector3.new(math.rad(-10), math.rad(-14 * dir), math.rad(8 * dir)), nil, { LeftFoot = 0.8, RightFoot = 0.8 })
end

function States.knockdown(frame: number?, scale: number?, knockdown: string?): Keyframe
	local s = scale or 1
	local f = frame or 0
	local faceDown = knockdown == "FaceDown"
	if f < 20 then
		local bounce = math.sin(math.clamp(f / 20, 0, 1) * math.pi) * 0.18
		return k(0, Vector3.new(0, (-0.48 + bounce) * s, -0.28 * s), Vector3.new(math.rad(if faceDown then -62 else 62), math.rad(12), math.rad(-20)), Vector3.new(math.rad(24), 0, math.rad(18)), Vector3.new(math.rad(-25), 0, math.rad(-15)), nil, { LeftFoot = 0.4, RightFoot = 0.4 })
	end
	return k(0, Vector3.new(0, -1.22 * s, -0.34 * s), Vector3.new(math.rad(if faceDown then -88 else 88), math.rad(4), math.rad(if faceDown then 18 else -18)), Vector3.new(math.rad(18), 0, math.rad(12)), Vector3.new(math.rad(-34), 0, math.rad(-12)), nil, { LeftFoot = 0, RightFoot = 0 })
end

function States.getup(frame: number?, scale: number?, knockdown: string?): Keyframe
	local s = scale or 1
	local alpha = math.clamp((frame or 0) / 32, 0, 1)
	local faceDown = knockdown == "FaceDown"
	local roll = if faceDown then math.rad(42 * (1 - alpha)) else math.rad(4)
	return k(0, Vector3.new(0, (-0.72 + 0.84 * alpha) * s, (-0.18 + 0.10 * alpha) * s), Vector3.new(math.rad((if faceDown then -48 else 42) * (1 - alpha)), math.rad(-8 + 20 * alpha), roll), Vector3.new(math.rad(35 - 30 * alpha), math.rad(-12 + 10 * alpha), 0), Vector3.new(math.rad(12 - 8 * alpha), math.rad(8), 0), nil, { LeftFoot = 0, RightFoot = 0 })
end

function States.ko(scale: number?, knockdown: string?): Keyframe
	return States.knockdown(48, scale, knockdown)
end

function States.ready(characterId: string, scale: number?): Keyframe
	local idx = table.find(Roster.order, characterId) or 1
	local key = States.neutral(characterId, scale)
	key.rootRotation = (key.rootRotation or Vector3.zero) + Vector3.new(0, math.rad((idx - 3) * 8), 0)
	key.rootOffset = (key.rootOffset or Vector3.zero) + Vector3.new(0, 0.04 * (scale or 1), -0.04 * idx * (scale or 1))
	return key
end

function States.victory(characterId: string, scale: number?): Keyframe
	local s = scale or 1
	local idx = table.find(Roster.order, characterId) or 1
	local poses = {
		k(0, Vector3.new(0, 0.08*s, 0), Vector3.new(math.rad(-4), math.rad(-14), 0), Vector3.new(math.rad(-12), math.rad(-16), 0), Vector3.new(math.rad(-8), math.rad(12), 0), { LeftHand = Library.e(Vector3.new(-0.22, 2.28, 0.42)*s, Vector3.new(-0.55,-0.4,0.05), nil, 1) }, { LeftFoot=0, RightFoot=0 }),
		k(0, Vector3.new(0.05*s, 0.02*s, 0), Vector3.new(0, math.rad(-28), 0), Vector3.new(0, math.rad(-34), 0), Vector3.zero, { RightHand = Library.e(Vector3.new(0.24, 2.10, 0.36)*s, Vector3.new(0.55,-0.4,0.05), nil, 1) }, { LeftFoot=0, RightFoot=0 }),
		k(0, Vector3.new(0, -0.16*s, 0), Vector3.new(math.rad(10), math.rad(-8), 0), Vector3.new(math.rad(18), math.rad(-10), 0), Vector3.zero, { LeftHand = Library.e(Vector3.new(-0.55, 1.28, 1.0)*s, Vector3.new(-0.7,-0.7,0.1), nil, 1), RightHand = Library.e(Vector3.new(0.55, 1.24, 1.0)*s, Vector3.new(0.7,-0.7,0.1), nil, 1) }, { LeftFoot=0, RightFoot=0 }),
		k(0, Vector3.new(0, 0.16*s, 0), Vector3.new(math.rad(-8), math.rad(-18), math.rad(-10)), Vector3.new(math.rad(-16), math.rad(-24), math.rad(-8)), Vector3.zero, { LeftFoot = Library.e(Vector3.new(-0.20, -1.2, 1.25)*s, Vector3.new(-0.25,0.05,1), nil, 1) }, { LeftFoot=0.6, RightFoot=0 }),
		k(0, Vector3.new(0, 0.02*s, 0), Vector3.new(0, math.rad(-34), 0), Vector3.new(0, math.rad(-42), 0), Vector3.zero, { LeftHand = Library.e(Vector3.new(-0.46, 1.52, 1.26)*s, Vector3.new(-0.7,-0.5,0.1), nil, 1), RightHand = Library.e(Vector3.new(0.46, 0.92, -0.12)*s, Vector3.new(0.7,-0.8,0.1), nil, 1) }, { LeftFoot=0, RightFoot=0 }),
		k(0, Vector3.new(0, -0.10*s, 0), Vector3.new(math.rad(5), math.rad(-22), 0), Vector3.new(math.rad(8), math.rad(-28), math.rad(6)), Vector3.zero, { LeftHand = Library.e(Vector3.new(-0.58, 1.50, 1.10)*s, Vector3.new(-0.7,-0.5,0.1), nil, 1), RightHand = Library.e(Vector3.new(0.34, 1.58, 0.36)*s, Vector3.new(0.7,-0.5,0.1), nil, 1) }, { LeftFoot=0, RightFoot=0 }),
	}
	return poses[idx]
end

function States.defeat(scale: number?): Keyframe
	local s = scale or 1
	return k(0, Vector3.new(0, -0.92*s, -0.10*s), Vector3.new(math.rad(18), 0, math.rad(10)), Vector3.new(math.rad(34), math.rad(-10), 0), Vector3.new(math.rad(18), math.rad(-16), 0), nil, { LeftFoot=0, RightFoot=0 })
end

-- Motion requests ---------------------------------------------------------------------------------------------------
-- MotionPlayer asks for one request per fighter per frame. A request names a mocap clip family (resolved per stance
-- style: "<clip>_<Style>" first, then "<clip>") and always carries a keyframe fallback. `key` identifies the motion:
-- a new key restarts one-shot clips and crossfades from the previous pose over `fade` seconds.
--   timeMode "loop" (default): slot clock * rate (+phase); "travel": distance walked / clip speed (feet stay planted);
--   "elapsed": seconds since the key started (or `seconds`), times `rate`; "progress": 0..1 of the clip (from the clip's
--   `tags[startTag]` seconds when given: e.g. a prone side roll starts the log roll at its half turn);
--   "contact": `progress` 0..1 of the way to the clip's contact (a body falling into a knockdown in the air);
--   "impact": `frames` sim frames elapsed, the clip's contact (a body reaching the floor) shown at `impactFrames`,
--   then real time (`fromContact` = start at the contact: a body that already fell in the air).
-- `adjust(pose, clip)` runs after sampling (style layer: guard arms, stance width/depth).
export type MotionRequest = {
	key: string, clip: string?, keyframe: Keyframe?, timeMode: string?, progress: number?, seconds: number?, rate: number?,
	phase: number?, mirror: boolean?, fade: number?, restart: boolean?, styled: boolean?, ground: number?,
	frames: number?, impactFrames: number?, fromContact: boolean?, startTag: string?,
	-- settle: a lying body relaxes onto the floor (pelvis, head and feet rest on it). true = from the clip's floor contact
	-- (knockdown/KO), "ground" = wherever the clip's own floor-support weight says the body lies (standing getups).
	settle: (boolean | string)?,
	adjust: ((any, any) -> ())?,
}
export type RequestContext = { clock: number, keyStarted: number, key: string?, settling: boolean, config: any, legLength: number? }

local STYLE_NAMES = { boxer = "Boxer", kickboxer = "Kickboxer", grappler = "Grappler", flow = "Flow", karate = "Karate", kungfu = "KungFu" }
States.STYLE_NAMES = STYLE_NAMES

-- Clip family names (motioncore Core clips) per core state. Style variants are "<name>_<Style>" (e.g. Stance_Boxer).
States.CLIPS = {
	Stance = "Stance", Crouch = "Crouch", CrouchDown = "CrouchDown",
	Walk = "WalkFwd", Backwalk = "WalkBack", Dash = "Dash", Backdash = "Backdash", SidestepLeft = "SidestepLeft", SidestepRight = "SidestepRight",
	Blockstun = "Blockstun", CrouchBlockstun = "CrouchBlockstun",
	Airborne = "Juggle", KnockdownFaceUp = "FallBack", KnockdownFaceDown = "FallFront", KnockdownFaceDownAir = "FallFrontAir", GetupFaceUp = "GetupBack", GetupFaceDown = "GetupFront",
	BackRoll = "BackRoll", SideRoll = "SideRoll", KOFaceUp = "KOBack", KOFaceDown = "KOFront", Intro = "Intro", Victory = "Victory", Defeat = "Defeat",
	Stagger = "Stagger", ThrowBreak = "ThrowBreak",
}

-- Knockdown timing (sim: Landing 34 f on the floor, then Getup 26 f, rolls +10): a grounded knockdown reaches the floor
-- after FALL_FRAMES frames of Landing (~1.2x the capture speed), lies still briefly, and a standing getup starts
-- GETUP_LEAD frames before the Getup state (the sit-up), so the rise plays over 36 frames.
States.FALL_FRAMES = 18
States.GETUP_LEAD = 10
-- Seconds after a grounded KO starts until the body hits the floor (KO fall clips: contact ~0.85 s).
States.KO_IMPACT_SECONDS = 0.85

-- Frames into Landing at which a grounded knockdown's body hits the floor (sound/dust sync), and the Landing length.
function States.fallFrames(config: any): (number, number)
	local total = if type(config) == "table" and type(config.LandingFrames) == "number" then config.LandingFrames else 34
	return math.min(States.FALL_FRAMES, total * 0.55), total
end

-- Floor-impact tracker for presentation (dust, thuds), one per fighter: floorImpact returns true on the frame the body
-- hits the floor (a grounded knockdown after its fall, a juggled body landing, a KO body landing).
function States.newImpactTracker(): any
	return { state = nil, fired = false, fromAir = false, since = 0 }
end
function States.floorImpact(tracker: any, view: any, config: any, now: number): boolean
	local state = view.state
	local y = if typeof(view.pos) == "Vector3" then view.pos.Y else 0
	if state ~= tracker.state then
		-- A thrown body already hit the floor at the throw impact (ThrowHit presents it): no second impact.
		local thrown = tracker.state == "Throw"
		tracker.fromAir = tracker.state == "Airborne" or y > 0.05
		tracker.state = state
		tracker.fired = thrown
		tracker.since = now
	end
	if tracker.fired then return false end
	if state == "Landing" then
		local fall, total = States.fallFrames(config)
		local elapsed = if type(view.stun) == "number" then total - view.stun else (now - tracker.since) * 60
		if tracker.fromAir or elapsed >= fall then
			tracker.fired = true
			return true
		end
	elseif state == "KO" then
		if y > 0.05 then
			tracker.fromAir = true
			return false
		end
		if tracker.fromAir or now - tracker.since >= States.KO_IMPACT_SECONDS then
			tracker.fired = true
			return true
		end
	end
	return false
end

-- Style layer (per Roster stanceStyle). Guard hands are shoulder->hand targets in the CHEST frame (Roblox axes: +X
-- right, +Y up, -Z forward; arm-length units) so they ride the torso's mocap weight shift; `w` blends them over the
-- clip's own arms. drop: extra knee bend (leg-length units); width/length scale the feet around the hips; rate: idle
-- tempo; sway: extra lateral weight shift amplitude (leg-length units) at `swayHz`.
type Arm = { rel: Vector3, pole: Vector3 }
type Style = { rate: number, drop: number, width: number, length: number, w: number, lead: Arm, rear: Arm, sway: number, swayHz: number, circle: number, yaw: number }
local function arm(x: number, y: number, z: number, px: number, py: number, pz: number): Arm
	return { rel = Vector3.new(x, y, z), pole = Vector3.new(px, py, pz).Unit }
end
States.STYLES = {
	-- Kael: upright, high tight guard, light bounce, narrow stance, chin tucked.
	boxer = { rate = 1.15, drop = 0.0, width = 0.85, length = 0.9, w = 0.9, lead = arm(0.22, 0.30, -0.40, -0.25, -1, 0.35), rear = arm(-0.20, 0.30, -0.28, 0.35, -1, 0.3), sway = 0.0, swayHz = 0, circle = 0, yaw = 30 },
	-- Sierra: bladed and tall, long high guard (lead hand reaching), slow rhythmic rocking, lead foot light.
	kickboxer = { rate = 0.8, drop = 0.0, width = 1.05, length = 1.1, w = 0.85, lead = arm(0.16, 0.30, -0.52, -0.3, -1, 0.3), rear = arm(-0.18, 0.30, -0.28, 0.35, -1, 0.3), sway = 0.0, swayHz = 0, circle = 0, yaw = 20 },
	-- Goran: wide planted base, torso up, knees moderately flexed, open hands forward at chest height, heavy slow sway.
	grappler = { rate = 0.6, drop = 0.06, width = 1.5, length = 1.0, w = 0.85, lead = arm(0.10, 0.02, -0.55, -0.6, -1, 0.1), rear = arm(-0.14, 0.0, -0.50, 0.6, -1, 0.1), sway = 0.02, swayHz = 0.45, circle = 0, yaw = 25 },
	-- Lumi: loose low stance, constant side-to-side sway, relaxed arms, springy knees.
	flow = { rate = 1.05, drop = 0.04, width = 1.2, length = 0.9, w = 0.6, lead = arm(0.12, 0.05, -0.45, -0.5, -1, 0.2), rear = arm(-0.10, 0.0, -0.32, 0.5, -1, 0.2), sway = 0.035, swayHz = 0.8, circle = 0, yaw = 30 },
	-- Rhys: long front stance, lead hand extended at chest height (kamae), rear fist guarding the chin, very still.
	karate = { rate = 0.45, drop = 0.03, width = 0.95, length = 1.25, w = 0.9, lead = arm(0.10, -0.02, -0.72, -0.5, -1, 0.1), rear = arm(-0.18, 0.18, -0.30, 0.35, -1, 0.3), sway = 0.0, swayHz = 0, circle = 0, yaw = 15 },
	-- Nia: low wide stance, lead open palm forward, rear palm guarding the chest, slow circular hand flow.
	kungfu = { rate = 0.55, drop = 0.07, width = 1.3, length = 1.05, w = 0.85, lead = arm(0.12, 0.08, -0.66, -0.55, -1, 0.1), rear = arm(-0.28, -0.05, -0.36, 0.5, -1, 0.2), sway = 0.015, swayHz = 0.3, circle = 0.06, yaw = 25 },
}
-- Stance width: feet move apart by WIDTH_SPREAD leg lengths per unit of `width` above 1 (plus the proportional scale),
-- so bladed captures (feet nearly in line) still widen.
States.WIDTH_SPREAD = 0.25
local LIMB_REF = { LeftHand = Vector3.new(-0.5, 1.1, 0), RightHand = Vector3.new(0.5, 1.1, 0), LeftFoot = Vector3.new(-0.3, -0.35, 0), RightFoot = Vector3.new(0.3, -0.35, 0) }

local function libv(v: Vector3): Vector3 return Vector3.new(v.X, v.Y, -v.Z) end

-- Turns a whole heading-space pose about the vertical axis through the fighter (positive = counter-clockwise seen
-- from above, Roblox convention): pelvis position/rotation, every limb target, pole and hand/foot rotation.
function States.rotateYaw(pose: any, radians: number, scale: number)
	if radians == 0 then return end
	local r = CFrame.Angles(0, radians, 0)
	pose.rootOffset = libv(r:VectorToWorldSpace(libv(pose.rootOffset)))
	local rootRot = r * (pose.rootRot or CFrame.Angles(pose.rootRotation.X, pose.rootRotation.Y, pose.rootRotation.Z))
	pose.rootRot = rootRot
	local x, y, z = rootRot:ToEulerAnglesXYZ()
	pose.rootRotation = Vector3.new(x, y, z)
	for limb, e in pose.targets do
		local ref = LIMB_REF[limb]
		if ref then
			local pivot = ref * scale
			e.pos = pivot + libv(r:VectorToWorldSpace(libv(e.pos - pivot)))
			if e.pole then e.pole = libv(r:VectorToWorldSpace(libv(e.pole))) end
			if e.rot then e.rot = r * e.rot end
		end
	end
end

-- Static foot placement of a travelling clip in pose space (loops: the mean over the cycle; one-shots: the first
-- frame), cached per clip and rig size. Used to turn a travelling pose by the style yaw without turning its stride.
local footRefCache: { [any]: { [number]: { [number]: { [string]: Vector3 } } } } = setmetatable({}, { __mode = "k" }) :: any
local function footReference(clip: any, legLength: number, scale: number): { [string]: Vector3 }?
	if type(clip) ~= "table" or type(clip.duration) ~= "number" then return nil end
	local perClip = footRefCache[clip]
	if not perClip then
		perClip = {}
		footRefCache[clip] = perClip
	end
	local perLeg = perClip[legLength]
	if not perLeg then
		perLeg = {}
		perClip[legLength] = perLeg
	end
	local ref = perLeg[scale]
	if ref then return ref end
	local sums = { LeftFoot = Vector3.zero, RightFoot = Vector3.zero }
	local n = if clip.loop then 24 else 1
	for i = 0, n - 1 do
		local p = ClipPlayer.sample(clip, clip.duration * i / n, { legLength = legLength, scale = scale })
		for limb in sums do
			local e = p.targets[limb]
			if e then sums[limb] += e.pos end
		end
	end
	ref = { LeftFoot = sums.LeftFoot / n, RightFoot = sums.RightFoot / n }
	perLeg[scale] = ref
	return ref
end

-- Blends the guard arms of `style` over a sampled heading-space pose (weight w), and applies stance width/depth.
-- travel = true for clips that move over the floor (walks, dashes, sidesteps): the style yaw turns the feet's static
-- placement but not their stride, so planted feet keep pace with the sim (a turned stride slides sideways).
local function styleAdjust(style: Style, scale: number, legLength: number, w: number, now: number, feet: string?, travel: boolean?): (any, any) -> ()
	return function(pose: any, clip: any)
		local ref = if travel and style.yaw ~= 0 then footReference(clip, legLength, scale) else nil
		local strideL, strideR
		if ref then
			local l, r = pose.targets.LeftFoot, pose.targets.RightFoot
			strideL = if l then l.pos - ref.LeftFoot else nil
			strideR = if r then r.pos - ref.RightFoot else nil
		end
		States.rotateYaw(pose, math.rad(style.yaw), scale)
		if ref then
			local turn = CFrame.Angles(0, math.rad(style.yaw), 0)
			local l, r = pose.targets.LeftFoot, pose.targets.RightFoot
			if l and strideL then
				local pivot = LIMB_REF.LeftFoot * scale
				l.pos = pivot + libv(turn:VectorToWorldSpace(libv(ref.LeftFoot - pivot))) + strideL
			end
			if r and strideR then
				local pivot = LIMB_REF.RightFoot * scale
				r.pos = pivot + libv(turn:VectorToWorldSpace(libv(ref.RightFoot - pivot))) + strideR
			end
		end
		local chest: CFrame = (pose.rootRot or CFrame.identity) * (pose.waistRot or CFrame.identity)
		for _, limb in { "LeftHand", "RightHand" } do
			local e = pose.targets[limb]
			if e then
				local a = if limb == "LeftHand" then style.lead else style.rear
				local rel = a.rel
				if limb == "LeftHand" and style.circle > 0 then
					local ph = now * math.pi * 2 * 0.35
					rel += Vector3.new(math.cos(ph) * style.circle, math.sin(ph) * style.circle * 0.7, 0)
				end
				local refPos = LIMB_REF[limb] * scale
				local current = (e.pos - refPos) / (1.95 * scale)
				local want = libv(chest:VectorToWorldSpace(rel))
				e.pos = refPos + current:Lerp(want, w) * (1.95 * scale)
				local pole = libv(chest:VectorToWorldSpace(a.pole))
				e.pole = (e.pole or pole):Lerp(pole, w)
			end
		end
		if feet then
			-- Work in studs around the fighter's base so planted feet stay put: feet keep their world position while
			-- the pelvis drops/sways, and stance width/length scale about the fighter, not about the swaying hips.
			-- feet: "stance" (width, length, drop, sway), "walk" (width, drop), "crouch" (width only).
			local k = legLength / (2.75 * scale)
			local root0: Vector3 = pose.rootOffset
			local stance = feet == "stance"
			-- Walks keep part of the style (a wide stance straddles otherwise); crouches keep only the width.
			local walk = feet == "walk"
			local drop = if feet == "crouch" then 0 elseif walk then style.drop * 0.4 else style.drop
			local width = if walk then 1 + (style.width - 1) * 0.5 else style.width
			local sway = if stance and style.sway > 0 then math.sin(now * math.pi * 2 * style.swayHz) * style.sway * legLength else 0
			local root1 = root0 + Vector3.new(sway, -drop * legLength, 0)
			for _, limb in { "LeftFoot", "RightFoot" } do
				local e = pose.targets[limb]
				if e then
					local refPos = LIMB_REF[limb] * scale
					local world = root0 + (e.pos - refPos) * k
					local side = if limb == "LeftFoot" then -1 else 1
					world = Vector3.new(world.X * width + side * (width - 1) * States.WIDTH_SPREAD * legLength, world.Y, world.Z * (if stance then style.length else 1))
					e.pos = refPos + (world - root1) / k
				end
			end
			pose.rootOffset = root1
		end
	end
end
States.styleAdjust = styleAdjust

local function styleOf(characterId: string?): Style
	return (States.STYLES :: any)[style(characterId)] or States.STYLES.boxer
end

local function hitClip(height: string, tier: string?, counter: boolean): string
	local heavy = counter or tier == "Heavy" or tier == "Launch"
	return "Hit" .. (if height == "High" or height == "Low" then height else "Mid") .. (if heavy then "Heavy" else "Light")
end
States.hitClip = hitClip

local function hitStamp(hit: any): string
	if type(hit) ~= "table" then return "?" end
	return tostring(hit.frame) .. ":" .. tostring(hit.move)
end

-- Request key of the reaction a view is in (nil outside hit/block/stagger reactions); MotionPlayer uses it to snap
-- to a new reaction's impact pose during hitstop.
function States.reactionKey(view: any): string?
	local state = view.state
	if state == "Hitstun" then return "Hit:" .. hitStamp(view.lastHit) end
	if state == "Blockstun" then return "Blockstun:" .. hitStamp(view.lastHit) end
	if state == "Stagger" then return "Stagger:" .. hitStamp(view.lastHit) end
	return nil
end

function States.request(view: any, frame: any?, slot: number, characterId: string, scale: number, ctx: RequestContext): MotionRequest
	local now = if frame and type(frame.now) == "number" then frame.now else ctx.clock
	local config = ctx.config or {}
	local legLength = ctx.legLength or 3 * scale * 0.93
	local st = styleOf(characterId)
	local guardArms = styleAdjust(st, scale, legLength, st.w, ctx.clock, "stance")
	local walkArms = styleAdjust(st, scale, legLength, st.w, ctx.clock, "walk", true)
	local moveArms = styleAdjust(st, scale, legLength, st.w * 0.75, ctx.clock, nil)
	local travelArms = styleAdjust(st, scale, legLength, st.w * 0.75, ctx.clock, nil, true)
	local crouchArms = styleAdjust(st, scale, legLength, st.w, ctx.clock, "crouch")
	-- Reactions keep the fighter's stance (yaw, width, depth) and only lean a little on the guard arms: the reaction's
	-- own hands (pushed back, dropped to the body, flung open) must read.
	local reactArms = styleAdjust(st, scale, legLength, st.w * 0.3, ctx.clock, "stance")
	local crouchReactArms = styleAdjust(st, scale, legLength, st.w * 0.3, ctx.clock, "crouch")
	if view.crush == "High" then return { key = "HighCrush", clip = States.CLIPS.Crouch, keyframe = States.pose(characterId, "HighCrush", scale, now), fade = 0.06, adjust = moveArms } end
	if view.crush == "Low" then return { key = "LowCrush", keyframe = States.pose(characterId, "LowCrush", scale, now), fade = 0.06 } end
	local state = view.state
	local hit = view.lastHit
	local hitKind = if type(hit) == "table" and type(hit.kind) == "string" then hit.kind else nil
	local hitHeight = if type(hit) == "table" and type(hit.height) == "string" then hit.height else "Mid"
	local hitTier = if type(hit) == "table" and type(hit.tier) == "string" then hit.tier else nil
	local hitCounter = (type(hit) == "table" and hit.counter == true) or view.counter == true or hitKind == "Counter"
	local hitSide = if type(hit) == "table" and type(hit.side) == "number" then hit.side else 1
	local stun = if type(view.stun) == "number" then view.stun else 0
	local knockdown = if view.knockdown == "FaceDown" then "FaceDown" else "FaceUp"
	local elapsedFrames = (ctx.clock - ctx.keyStarted) * 60
	local crouchGuard = view.guard == "Crouch" or view.crouched == true or state == "Crouch" or state == "CrouchBlock"
	if state == "Blockstun" then
		local low = view.guard == "Crouch" or view.crouched == true or hitHeight == "Low"
		return { key = "Blockstun:" .. hitStamp(hit), clip = if low then States.CLIPS.CrouchBlockstun else States.CLIPS.Blockstun, timeMode = "elapsed",
			keyframe = if low then States.pose(characterId, "CrouchGuard", scale, now) else States.blockstun(hitHeight, scale, hitSide), fade = 0.04, adjust = if low then crouchReactArms else reactArms }
	end
	if state == "Block" or state == "Guard" or state == "CrouchBlock" then
		-- OV5 sims (explicit block state); OV6 guards automatically while Idle/Backwalk/Crouch.
		if crouchGuard then return { key = "Crouch", clip = States.CLIPS.Crouch, keyframe = States.pose(characterId, "CrouchGuard", scale, now), fade = 0.1, adjust = crouchArms } end
		return { key = "Stance", clip = States.CLIPS.Stance, keyframe = States.pose(characterId, "Guard", scale, now), rate = st.rate, phase = (slot - 1) * 0.37, fade = 0.12, adjust = guardArms }
	end
	if state == "Dash" or state == "Backdash" then
		local back = state == "Backdash" or (state == "Dash" and view.dashFrame == nil and ((view.moveX or 0) < 0 or (view.dashDirection or 1) < 0))
		local total = if type(view.dashTotal) == "number" and view.dashTotal > 0 then view.dashTotal else (if back then 18 else 14)
		local progress = if type(view.dashFrame) == "number" then view.dashFrame / total else elapsedFrames / total
		return { key = if back then "Backdash" else "Dash", clip = if back then States.CLIPS.Backdash else States.CLIPS.Dash, timeMode = "progress", progress = progress,
			keyframe = States.pose(characterId, if back then "Backdash" else "Dash", scale, now), fade = 0.06, restart = true, adjust = travelArms }
	end
	if state == "Sidestep" or state == "Step" then
		-- stepDir +1 = the fighter's own LEFT (into the screen for the left-side player), -1 = its RIGHT.
		local dir = if type(view.stepDir) == "number" then view.stepDir elseif (view.moveZ or view.moveX or 0) < 0 then -1 else 1
		local left = dir > 0
		local progress = if type(view.stepFrame) == "number" then view.stepFrame / 22 else elapsedFrames / 22
		return { key = if left then "SidestepLeft" else "SidestepRight", clip = if left then States.CLIPS.SidestepLeft else States.CLIPS.SidestepRight,
			timeMode = "progress", progress = progress, keyframe = States.pose(characterId, if left then "SidestepIn" else "SidestepOut", scale, view.walkPhase),
			fade = 0.06, restart = true, adjust = travelArms }
	end
	if state == "Hitstun" then
		-- Reactions are authored for the orthodox stance; mirroring them would swap the feet mid-fight.
		return { key = "Hit:" .. hitStamp(hit), clip = hitClip(hitHeight, hitTier, hitCounter), timeMode = "elapsed",
			keyframe = States.reaction(hitHeight, hitTier, hitCounter, scale, hitSide, elapsedFrames), fade = 0.035, adjust = reactArms }
	end
	if state == "Stagger" then
		return { key = "Stagger:" .. hitStamp(hit), clip = States.CLIPS.Stagger, timeMode = "elapsed",
			keyframe = States.stagger(scale, hitSide, hitCounter), fade = 0.05, adjust = reactArms }
	end
	if state == "Airborne" or (state == "KO" and (view.pos and view.pos.Y or 0) > 0.05) then
		local vy = if type(view.velocityY) == "number" then view.velocityY else 0
		if view.knockdown == "FaceDown" then
			-- Falling out of a juggle into a face-down knockdown: the face-down fall clip reaches its floor contact
			-- exactly when the body lands (time to the floor from height, velocity and gravity), so Landing continues
			-- the same clip from its contact.
			local g = if type(config.Gravity) == "number" and config.Gravity > 0 then config.Gravity else 44
			local y = math.max(0, if typeof(view.pos) == "Vector3" then view.pos.Y else 0)
			local tLand = (vy + math.sqrt(math.max(vy * vy + 2 * g * y, 0))) / g
			local e = elapsedFrames / 60
			local u = if tLand + e > 1e-3 then e / (tLand + e) else 1
			return { key = "Airborne:Down:FaceDown", clip = States.CLIPS.KnockdownFaceDownAir, timeMode = "contact", progress = 0.55 + 0.45 * u,
				keyframe = States.launch(scale, view.velocityY, view.airFrames, view.airHits, hitSide), fade = 0.12, styled = false, ground = 0 }
		end
		local launchV = if type(config.LaunchVelocity) == "number" then config.LaunchVelocity else 16
		-- Rising half of the clip while going up, falling half on the way down.
		local progress = math.clamp(0.5 - 0.5 * vy / math.max(launchV, 1), 0, 1)
		return { key = "Airborne", clip = States.CLIPS.Airborne, timeMode = "progress", progress = progress,
			keyframe = States.launch(scale, view.velocityY, view.airFrames, view.airHits, hitSide), fade = 0.05, styled = false, ground = 0 }
	end
	-- A body that already fell (out of a juggle) or was thrown down continues the knockdown clip from its floor contact.
	local fromAirKey = type(ctx.key) == "string" and (string.sub(ctx.key, 1, 8) == "Airborne" or ctx.key == "Throw" or string.find(ctx.key, ":Air", 1, true) ~= nil)
	if state == "Landing" or state == "Knockdown" then
		local total = if type(config.LandingFrames) == "number" then config.LandingFrames else 34
		local elapsed = if type(view.stun) == "number" then math.clamp(total - stun, 0, total) else elapsedFrames
		local fallFrames = States.fallFrames(config)
		local lead = math.min(States.GETUP_LEAD, total * 0.3)
		local getupFrames = if type(config.GetupFrames) == "number" then config.GetupFrames else 26
		-- The last frames on the floor already start a standing getup (the fighter is invulnerable and cannot act), so
		-- the short Getup state shows a believable rise instead of a jump to the feet.
		local kind = view.getupKind
		if (kind == nil or kind == "Stand") and elapsed >= total - lead then
			return { key = "Getup:" .. knockdown .. ":Stand", clip = if knockdown == "FaceDown" then States.CLIPS.GetupFaceDown else States.CLIPS.GetupFaceUp,
				timeMode = "progress", progress = (elapsed - (total - lead)) / (lead + getupFrames),
				keyframe = States.getup(0, scale, knockdown), fade = 0.12, styled = false, settle = "ground" }
		end
		return { key = "Down:" .. knockdown .. (if fromAirKey then ":Air" else ""), clip = if knockdown == "FaceDown" then (if fromAirKey then States.CLIPS.KnockdownFaceDownAir else States.CLIPS.KnockdownFaceDown) else States.CLIPS.KnockdownFaceUp,
			timeMode = "impact", frames = elapsed, impactFrames = fallFrames, fromContact = fromAirKey,
			keyframe = States.knockdown(math.max(elapsed, 20), scale, knockdown), fade = if fromAirKey then 0.08 else 0.05, styled = false, ground = 1, settle = true }
	end
	if state == "Getup" then
		local kind = if view.getupKind == "BackRoll" or view.getupKind == "SideRoll" then view.getupKind else "Stand"
		local getupFrames = if type(config.GetupFrames) == "number" then config.GetupFrames else 26
		local landing = if type(config.LandingFrames) == "number" then config.LandingFrames else 34
		local lead = math.min(States.GETUP_LEAD, landing * 0.3)
		local total = getupFrames + (if kind ~= "Stand" then 10 else 0)
		local done = math.clamp(total - stun, 0, total)
		local progress = if kind == "Stand" then (lead + done) / (lead + getupFrames) else done / math.max(total, 1)
		local clip = if kind == "BackRoll" then States.CLIPS.BackRoll elseif kind == "SideRoll" then States.CLIPS.SideRoll elseif knockdown == "FaceDown" then States.CLIPS.GetupFaceDown else States.CLIPS.GetupFaceUp
		-- Side roll: a log roll whose chest turns toward the travel side first. Face up it is one full turn from the
		-- clip's first frame (the lying pose itself, so a short fade); face down (prone) it is the second half turn.
		local sideRoll = kind == "SideRoll"
		return { key = "Getup:" .. knockdown .. ":" .. kind, clip = clip, timeMode = "progress", progress = math.clamp(progress, 0, 1), mirror = sideRoll and (view.rollDir or 1) < 0,
			startTag = if sideRoll and knockdown == "FaceDown" then "proneStart" else nil,
			keyframe = States.getup(math.clamp(done / math.max(total, 1), 0, 1) * 32, scale, knockdown),
			fade = if sideRoll then (if knockdown == "FaceDown" then 0.06 else 0.03) else 0.08, styled = false,
			settle = if kind == "Stand" then "ground" else nil }
	end
	if state == "KO" then
		if fromAirKey then
			-- A body that fell out of a juggle lands like a knockdown and stays down.
			return { key = "KO:" .. knockdown .. ":Air", clip = if knockdown == "FaceDown" then States.CLIPS.KnockdownFaceDownAir else States.CLIPS.KnockdownFaceUp,
				timeMode = "impact", fromContact = true, keyframe = States.ko(scale, knockdown), fade = 0.08, styled = false, ground = 1, settle = true }
		end
		return { key = "KO:" .. knockdown, clip = if knockdown == "FaceDown" then States.CLIPS.KOFaceDown else States.CLIPS.KOFaceUp, timeMode = "elapsed",
			keyframe = States.ko(scale, knockdown), fade = 0.06, styled = false, ground = 1, settle = true }
	end
	if frame then
		if (frame.phase == "MatchOver" or frame.phase == "RoundOver") and ctx.settling then
			if frame.winner == slot then return { key = "Victory", clip = States.CLIPS.Victory, timeMode = "elapsed", keyframe = States.victory(characterId, scale), fade = 0.3 } end
			if frame.winner ~= 0 then return { key = "Defeat", clip = States.CLIPS.Defeat, timeMode = "elapsed", keyframe = States.defeat(scale), fade = 0.3, styled = false } end
		elseif frame.phase == "Ready" then
			return { key = "Intro", clip = States.CLIPS.Intro, timeMode = "elapsed", keyframe = States.ready(characterId, scale), fade = 0.2 }
		end
	end
	if state == "Crouch" or crouchGuard then
		local frames = if type(view.crouchFrames) == "number" then view.crouchFrames else elapsedFrames
		return { key = "Crouch", clip = States.CLIPS.Crouch, keyframe = States.pose(characterId, "Crouch", scale, now), fade = if frames < 2 then 0.1 else 0.12, adjust = crouchArms }
	end
	if state == "Walk" or state == "Backwalk" or math.abs(view.moveX or 0) > 0.05 then
		local back = state == "Backwalk" or (state ~= "Walk" and (view.moveX or 0) < 0)
		return { key = if back then "Backwalk" else "Walk", clip = if back then States.CLIPS.Backwalk else States.CLIPS.Walk, timeMode = "travel",
			keyframe = States.pose(characterId, if back then "Backwalk" else "Walk", scale, view.walkPhase), fade = 0.14, restart = true, adjust = walkArms }
	end
	return { key = "Stance", clip = States.CLIPS.Stance, keyframe = States.pose(characterId, "Idle", scale, now), rate = st.rate, phase = (slot - 1) * 0.37, fade = 0.15, adjust = guardArms }
end

-- Menu/preview poses ("Stance", "Guard", "Intro", "Victory", "Defeat") at time t (seconds).
function States.named(characterId: string, name: string, scale: number, t: number, legLength: number?): MotionRequest
	local st = styleOf(characterId)
	local adjust = styleAdjust(st, scale, legLength or 3 * scale * 0.93, st.w, t, "stance")
	if name == "Stance" or name == "Guard" then return { key = name, clip = States.CLIPS.Stance, keyframe = States.pose(characterId, if name == "Guard" then "Guard" else "Idle", scale, t), rate = st.rate, adjust = adjust } end
	if name == "Intro" then return { key = "Intro", clip = States.CLIPS.Intro, keyframe = States.ready(characterId, scale) } end
	if name == "Victory" then return { key = "Victory", clip = States.CLIPS.Victory, keyframe = States.victory(characterId, scale) } end
	if name == "Defeat" then return { key = "Defeat", clip = States.CLIPS.Defeat, keyframe = States.defeat(scale), styled = false } end
	error("States.named: unknown pose " .. tostring(name))
end

return States
