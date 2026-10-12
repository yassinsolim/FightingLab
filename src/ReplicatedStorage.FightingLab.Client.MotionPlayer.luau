--!strict
-- MotionPlayer: turns a fighter view (sim state) into a body pose and applies it to an R15 render rig.
--
-- Poses carry quaternion rotations (rootRot/waistRot/neckRot, mirrored as Euler rootRotation/waist/neck for older
-- callers) and limb effectors. Poses returned by sample() are in HEADING SPACE: limb targets are relative to the
-- reference shoulder/hip and expressed in the fighter's facing frame (the HumanoidRootPart frame), not the pelvis
-- frame. Legacy keyframe poses (Motion.Strikes/Kicks/Throws keys) are converted on the way in; apply() still accepts
-- legacy poses from other callers.
--
-- Mocap clips (Motion.ClipLibrary / Motion.ClipPlayer) drive the core states when a clip is installed and fall back
-- to keyframes otherwise. apply() runs FK for the pelvis/chest/head, a ground solver (lying bodies rest on the floor,
-- nothing sinks into it), then two-bone IK per limb with floor-aware hand/foot goals.
local Library = require(script.Parent.MotionLibrary)
local Roster = require(script.Parent.Parent.Roster)
local MotionFolder = script.Parent:FindFirstChild("Motion")
if not MotionFolder then error("MotionPlayer requires ReplicatedStorage.FightingLab.Client.Motion") end
local States = require(MotionFolder.States)
local Throws = require(MotionFolder.Throws)
local Strikes = require(MotionFolder.Strikes)
local Kicks = require(MotionFolder.Kicks)
local MoveAnimOverrides = require(MotionFolder.MoveAnimOverrides)
local ClipLibrary = require(MotionFolder.ClipLibrary)
local ClipPlayer = require(MotionFolder.ClipPlayer)

export type FighterView = {
	pos: Vector3, facing: Vector3, state: string, move: string?, moveFrame: number, walkPhase: number,
	stun: number, crouched: boolean, moveX: number, extrapolated: number?, y: number?, height: number?, velocity: Vector3?,
	characterId: string?, throw: any?, armorActive: boolean?, crush: string?, rootHeight: number?, legLength: number?, counter: boolean?,
	lastHit: { kind: string?, height: string?, tier: string?, counter: boolean?, frame: number?, move: string?, limb: string?, side: number? }?,
	velocityY: number?, airFrames: number?, airHits: number?, knockdown: string?, dashDirection: number?,
}
export type Effector = Library.Effector
export type Keyframe = Library.Keyframe
export type Pose = {
	rootOffset: Vector3, rootRotation: Vector3, waist: Vector3, neck: Vector3,
	targets: { [string]: Effector }, joints: { [string]: CFrame }, plantedFeet: { [string]: number },
	rootRot: CFrame?, waistRot: CFrame?, neckRot: CFrame?,
	space: string?, ground: number?, contact: { [string]: number }?, footLock: boolean?, settle: number?, relaxFeet: number?,
	-- clock: the slot clock (seconds) the pose was sampled at (paces the foot-lock release fade); stepScale: applied ÷
	-- designed sim advance of a step-in so far (MotionPlayer.sample; < 1 when keepApart capped it).
	clock: number?, stepScale: number?,
}
export type RigInfo = {
	motors: { [string]: Motor6D }, parts: { [string]: BasePart }, rootHeight: number, legLength: number, armLength: number,
	chains: { [string]: any }, sizes: { [string]: Vector3 }, footLock: { [string]: any }, stats: { [string]: number },
	tips: { [string]: CFrame }, partMotor: { [string]: Motor6D },
	-- Intended clearance (studs) of each foot's lowest point above the floor in the latest apply: the clip's own height
	-- for a foot in the air, 0 for a planted one (tests and tools compare the shown foot with it).
	footClear: { [string]: number }?,
	-- Per foot: how far a floor foot's ankle had to stay above its intended height because the pelvis rides higher than
	-- the straight leg reaches (MotionPlayer.apply lowers the body by it).
	footHang: { [string]: number }?,
	-- Clock of the pose being applied (MotionPlayer.apply; nil for poses without one: no lock release fade).
	lockClock: number?,
}
export type ResolvedMove = { keyframes: { Keyframe }, move: any, params: Library.AnimParams, timing: { startup: number, active: number, recovery: number }, source: string, clip: ClipLibrary.Clip? }

local MotionPlayer = {}
MotionPlayer.GroundClearance = 0.03

type SlotState = {
	pose: Pose?, key: string?, clock: number, lastNow: number?, keyStarted: number,
	fadeFrom: Pose?, fadeStart: number, fadeDur: number,
	travel: number, lastPos: Vector3?, roundOverSince: number?,
	-- Step-in tracking of the current attack (sim advance designed vs applied since its first frame).
	stepMove: string?, stepFrame: number?, stepPos: Vector3?, stepApplied: number?, stepDesigned: number?,
}
local slots: { [number]: SlotState } = {}
local FINAL_HIT_HOLD = 1.1
-- A sim position jump larger than this in one frame is a round reset (fighters back on their marks), never movement
-- (dashes travel ~0.2 studs per frame, throw pushes 0.6): the pose cuts instead of crossfading.
MotionPlayer.TeleportDistance = 3
local resolvedCache: { [string]: ResolvedMove } = {}
local LEGACY_TO_ROSTER: { [string]: string } = { Jab = "Jab", Heavy = "Cross", Kick = "Roundhouse", LeadKick = "FrontKick", DuckJab = "DuckJab", BodyPunch = "BodyBlow", ShinTap = "ShinKick", Sweep = "LowSweep", Rise = "RisingUppercut" }
local DEFAULT_IDS = { "Kael", "Sierra" }
-- Leg length (hip to sole) relative to RootHeight on the generated fighter templates (measured 0.755-0.80).
local LEG_PER_ROOT = 0.775
MotionPlayer.LEG_PER_ROOT = LEG_PER_ROOT

local function finite(n: number): boolean return n == n and math.abs(n) < math.huge end
local function finiteVector(v: Vector3): boolean return finite(v.X) and finite(v.Y) and finite(v.Z) end
local function copyEffector(effector: Effector): Effector return { pos = effector.pos, pole = effector.pole, orient = effector.orient, weight = effector.weight, rot = effector.rot, aimWorldY = effector.aimWorldY, aimWeight = effector.aimWeight, sole = effector.sole } end
local function scaleFromRoot(rootHeight: number?): number return math.max(0.75, math.min(1.35, (rootHeight or 3) / 3)) end
local function characterRootHeight(characterId: string): number return (Roster.get(characterId).stats.height or 6) * 0.5 end
local function libVector(v: Vector3): Vector3 return Vector3.new(v.X, v.Y, -v.Z) end
local function eulerOf(cf: CFrame): Vector3 local x, y, z = cf:ToEulerAnglesXYZ(); return Vector3.new(x, y, z) end
local function anglesOf(v: Vector3): CFrame return CFrame.Angles(v.X, v.Y, v.Z) end
local function smoothstep(x: number): number local t = math.clamp(x, 0, 1); return t * t * (3 - 2 * t) end
MotionPlayer.scaleFromRoot = scaleFromRoot

local function newSlot(clock: number): SlotState
	return { pose = nil, key = nil, clock = clock, lastNow = nil, keyStarted = 0, fadeFrom = nil, fadeStart = 0, fadeDur = 0, travel = 0, lastPos = nil, roundOverSince = nil }
end

local function slotState(slot: number): SlotState
	local st = slots[slot]
	if not st then
		st = newSlot(0)
		slots[slot] = st
	end
	return st
end

local function mergedAnimHint(characterId: string, moveKey: string, move: any): any
	local base = table.clone(move.anim)
	local characterOverrides = MoveAnimOverrides[characterId]
	local sharedOverrides = MoveAnimOverrides["*"]
	local override = (type(characterOverrides) == "table" and characterOverrides[moveKey]) or (type(sharedOverrides) == "table" and sharedOverrides[moveKey])
	if type(override) == "table" then
		for key, value in override do base[key] = value end
	end
	return base
end

-- Legacy keyframes -------------------------------------------------------------------------------------------------

local function poseFromKey(key: Keyframe): Pose
	local targets: { [string]: Effector } = {}
	for name, effector in Library.DefaultTargets do targets[name] = copyEffector(effector) end
	if key.targets then for name, effector in key.targets do targets[name] = copyEffector(effector) end end
	return { rootOffset = key.rootOffset or Vector3.zero, rootRotation = key.rootRotation or Vector3.zero, waist = key.waist or Vector3.zero, neck = key.neck or Vector3.zero, targets = targets, joints = {}, plantedFeet = { LeftFoot = (key.plant and key.plant.LeftFoot) or 0, RightFoot = (key.plant and key.plant.RightFoot) or 0 } }
end
MotionPlayer.poseFromKey = poseFromKey

local function blendEffectorLegacy(a: Effector?, b: Effector?, alpha: number): Effector?
	if a and b then
		return { pos = a.pos:Lerp(b.pos, alpha), pole = (a.pole or Vector3.yAxis):Lerp(b.pole or a.pole or Vector3.yAxis, alpha), orient = (a.orient or Vector3.zero):Lerp(b.orient or a.orient or Vector3.zero, alpha), weight = (a.weight or 1) + ((b.weight or 1) - (a.weight or 1)) * alpha }
	elseif b then return copyEffector(b) elseif a then return copyEffector(a) end
	return nil
end

local function blendLegacy(a: Pose, b: Pose, alpha: number): Pose
	local targets: { [string]: Effector } = {}
	for name, effector in a.targets do local mixed = blendEffectorLegacy(effector, b.targets[name], alpha); if mixed then targets[name] = mixed end end
	for name, effector in b.targets do if not targets[name] then targets[name] = copyEffector(effector) end end
	return { rootOffset = a.rootOffset:Lerp(b.rootOffset, alpha), rootRotation = a.rootRotation:Lerp(b.rootRotation, alpha), waist = a.waist:Lerp(b.waist, alpha), neck = a.neck:Lerp(b.neck, alpha), targets = targets, joints = {}, plantedFeet = { LeftFoot = a.plantedFeet.LeftFoot + (b.plantedFeet.LeftFoot - a.plantedFeet.LeftFoot) * alpha, RightFoot = a.plantedFeet.RightFoot + (b.plantedFeet.RightFoot - a.plantedFeet.RightFoot) * alpha } }
end

local function easeValue(kind: string?, t: number): number
	local x = math.clamp(t, 0, 1)
	if kind == "linear" then return x end
	if kind == "hold" then return if x >= 1 then 1 else 0 end
	if kind == "in" then return x * x end
	if kind == "out" then return 1 - (1 - x) * (1 - x) end
	return x * x * (3 - 2 * x)
end
local function findSpan(keys: { Keyframe }, t: number): (Keyframe, Keyframe, number)
	local prev = keys[1]
	for i = 2, #keys do
		local nextKey = keys[i]
		if t <= nextKey.t then
			return prev, nextKey, easeValue(nextKey.ease, (t - prev.t) / math.max(nextKey.t - prev.t, 0.001))
		end
		prev = nextKey
	end
	return prev, prev, 0
end

local function moveTime(timing: { startup: number, active: number, recovery: number }, frame: number): number
	local firstActive = timing.startup + 1
	if frame <= firstActive then return math.clamp(frame / math.max(firstActive, 1), 0, 1) end
	if frame <= timing.startup + timing.active then return 1 + math.clamp((frame - firstActive) / math.max(timing.active - 1, 1), 0, 1) * 0.48 end
	return 1.48 + math.clamp((frame - timing.startup - timing.active) / math.max(timing.recovery, 1), 0, 1) * 1.52
end

local function sampleKeys(keys: { Keyframe }, normalized: number): Pose
	local aKey, bKey, alpha = findSpan(keys, normalized)
	return blendLegacy(poseFromKey(aKey), poseFromKey(bKey), alpha)
end

-- Heading space -----------------------------------------------------------------------------------------------------

local function legacyLying(rotation: Vector3): number
	return math.clamp((math.max(math.abs(rotation.X), math.abs(rotation.Z)) - 0.35) / 0.5, 0, 1)
end

local function refPivot(name: string, scale: number): Vector3
	local side = if name == "LeftHand" or name == "LeftFoot" then -1 else 1
	if name == "LeftFoot" or name == "RightFoot" then return Vector3.new(side * 0.3, -0.35, 0) * scale end
	return Vector3.new(side * 0.5, 1.1, 0) * scale
end

local function defaultPole(name: string): Vector3
	if name == "LeftFoot" or name == "RightFoot" then return Vector3.new(0, 0, 1) end
	return Vector3.new(if name == "LeftHand" then -0.7 else 0.7, -0.7, 0)
end

-- Converts a legacy pose (arm targets in the pelvis frame, leg targets in the yaw frame unless lying) to heading space.
local function toHeading(pose: Pose, scale: number): Pose
	if pose.space == "heading" then return pose end
	local rr = pose.rootRotation
	local rootRot = pose.rootRot or anglesOf(rr)
	local lying = legacyLying(rr)
	local legRot = CFrame.Angles(rr.X * lying, rr.Y, rr.Z * lying)
	local targets: { [string]: Effector } = {}
	for name, e in pose.targets do
		local isLeg = name == "LeftFoot" or name == "RightFoot"
		local frame = if isLeg then legRot else rootRot
		local pivot = refPivot(name, scale)
		local rel = frame:VectorToWorldSpace(libVector(e.pos - pivot))
		local pole = frame:VectorToWorldSpace(libVector(e.pole or defaultPole(name)))
		targets[name] = { pos = pivot + libVector(rel), pole = libVector(pole), orient = e.orient, weight = e.weight, rot = nil }
	end
	return {
		rootOffset = pose.rootOffset, rootRotation = rr, waist = pose.waist, neck = pose.neck,
		rootRot = rootRot, waistRot = pose.waistRot or anglesOf(pose.waist), neckRot = pose.neckRot or anglesOf(pose.neck),
		targets = targets, joints = {}, plantedFeet = pose.plantedFeet,
		contact = { LeftFoot = 1 - math.clamp(pose.plantedFeet.LeftFoot, 0, 1), RightFoot = 1 - math.clamp(pose.plantedFeet.RightFoot, 0, 1) },
		ground = lying, space = "heading",
	}
end
MotionPlayer.toHeading = toHeading

local function blendEffector(a: Effector, b: Effector, alpha: number): Effector
	local rot: CFrame? = nil
	local ra, rb = a.rot, b.rot
	if ra and rb then rot = ra:Lerp(rb, alpha) elseif alpha >= 0.5 then rot = rb else rot = ra end
	return {
		pos = a.pos:Lerp(b.pos, alpha),
		pole = (a.pole or Vector3.yAxis):Lerp(b.pole or a.pole or Vector3.yAxis, alpha),
		orient = a.orient, weight = (a.weight or 1) + ((b.weight or 1) - (a.weight or 1)) * alpha, rot = rot,
		aimWorldY = b.aimWorldY or a.aimWorldY,
		aimWeight = if a.aimWeight or b.aimWeight then (a.aimWeight or 0) + ((b.aimWeight or 0) - (a.aimWeight or 0)) * alpha else nil,
		sole = if a.sole and b.sole then a.sole + (b.sole - a.sole) * alpha else nil,
	}
end

-- Blends two heading-space poses (rotations slerp).
local function blendPose(a: Pose, b: Pose, alpha: number): Pose
	if alpha <= 0 then return a end
	if alpha >= 1 then return b end
	local targets: { [string]: Effector } = {}
	for name, ea in a.targets do
		local eb = b.targets[name]
		targets[name] = if eb then blendEffector(ea, eb, alpha) else copyEffector(ea)
	end
	for name, eb in b.targets do if not targets[name] then targets[name] = copyEffector(eb) end end
	local rootRot = (a.rootRot or anglesOf(a.rootRotation)):Lerp(b.rootRot or anglesOf(b.rootRotation), alpha)
	local waistRot = (a.waistRot or anglesOf(a.waist)):Lerp(b.waistRot or anglesOf(b.waist), alpha)
	local neckRot = (a.neckRot or anglesOf(a.neck)):Lerp(b.neckRot or anglesOf(b.neck), alpha)
	local ca = a.contact or { LeftFoot = 1, RightFoot = 1 }
	local cb = b.contact or { LeftFoot = 1, RightFoot = 1 }
	return {
		rootOffset = a.rootOffset:Lerp(b.rootOffset, alpha),
		rootRotation = eulerOf(rootRot), waist = eulerOf(waistRot), neck = eulerOf(neckRot),
		rootRot = rootRot, waistRot = waistRot, neckRot = neckRot,
		targets = targets, joints = {},
		plantedFeet = { LeftFoot = a.plantedFeet.LeftFoot + (b.plantedFeet.LeftFoot - a.plantedFeet.LeftFoot) * alpha, RightFoot = a.plantedFeet.RightFoot + (b.plantedFeet.RightFoot - a.plantedFeet.RightFoot) * alpha },
		contact = { LeftFoot = ca.LeftFoot + (cb.LeftFoot - ca.LeftFoot) * alpha, RightFoot = ca.RightFoot + (cb.RightFoot - ca.RightFoot) * alpha },
		ground = (a.ground or 0) + ((b.ground or 0) - (a.ground or 0)) * alpha,
		settle = if a.settle or b.settle then (a.settle or 0) + ((b.settle or 0) - (a.settle or 0)) * alpha else nil,
		relaxFeet = if a.relaxFeet or b.relaxFeet then (a.relaxFeet or 0) + ((b.relaxFeet or 0) - (a.relaxFeet or 0)) * alpha else nil,
		stepScale = if a.stepScale or b.stepScale then (a.stepScale or 1) + ((b.stepScale or 1) - (a.stepScale or 1)) * alpha else nil,
		space = "heading",
	}
end
MotionPlayer.blendPose = blendPose

-- Moves -------------------------------------------------------------------------------------------------------------

local function archetypeProvider(archetype: string, move: any?): ((Library.AnimParams) -> { Keyframe }, string)
	local strike = Strikes[archetype]
	if strike then return strike, "Strikes" end
	local kick = Kicks[archetype]
	if kick then return kick, "Kicks" end
	local throwFn = Throws[archetype]
	if throwFn then
		return function(_params: Library.AnimParams): { Keyframe }
			local track = throwFn(move and move.duration, move and move.impactFrame)
			local keys = table.clone(track.attacker)
			for _, key in keys do key.t *= 3 end
			return keys
		end, "Throws"
	end
	error("MotionPlayer: missing motion archetype " .. archetype)
end

function MotionPlayer.clearCache()
	table.clear(resolvedCache)
	ClipLibrary.clearCache()
end

-- Requires and indexes every clip module (decoding stays lazy); returns the number of clips and any problems.
function MotionPlayer.warmClips(): (number, { string })
	local count = 0
	for _ in ClipLibrary.index() do count += 1 end
	return count, ClipLibrary.problems()
end

function MotionPlayer.resolveMove(characterId: string, moveKey: string, rootHeight: number?): ResolvedMove
	local cacheKey = characterId .. ":" .. moveKey .. ":" .. tostring(rootHeight or 0)
	local cached = resolvedCache[cacheKey]
	if cached then return cached end
	local character = Roster.get(characterId)
	local move = Roster.getMove(characterId, moveKey)
	local hint = mergedAnimHint(characterId, moveKey, move)
	if not hint or type(hint.archetype) ~= "string" then error("MotionPlayer: roster move " .. characterId .. "." .. moveKey .. " has no anim archetype") end
	local scale = scaleFromRoot(rootHeight or characterRootHeight(characterId))
	local neutral = States.neutral(characterId, scale)
	local params: Library.AnimParams = { side = hint.side or "Lead", height = hint.height or move.height, crouch = hint.crouch == true or move.crouching == true, spin = hint.spin or 0, hop = hint.hop or 0, lunge = hint.lunge or 0, scale = scale, neutral = neutral, stance = character.stanceStyle }
	local fn, source = archetypeProvider(hint.archetype, move)
	local keyframes = fn(params)
	if #keyframes < 2 then error("MotionPlayer: archetype " .. hint.archetype .. " returned too few keyframes") end
	local clip = ClipLibrary.forMove(characterId, moveKey)
	local resolved: ResolvedMove = { keyframes = keyframes, move = move, params = params, timing = { startup = move.startup, active = move.active, recovery = move.recovery }, source = if clip then "Clip" else source, clip = clip }
	resolvedCache[cacheKey] = resolved
	return resolved
end

local function characterForSlot(view: FighterView, frame: any?, slot: number): string
	if view.characterId and Roster.has(view.characterId) then return view.characterId end
	if frame then
		local ids = { frame.p1Id, frame.p2Id }
		if typeof(ids[slot]) == "string" and Roster.has(ids[slot]) then return ids[slot] end
		local entry = frame.entry
		local fighter = entry and entry.fighters and entry.fighters[slot]
		if fighter and typeof(fighter.characterId) == "string" and Roster.has(fighter.characterId) then return fighter.characterId end
	end
	return DEFAULT_IDS[slot] or "Kael"
end

local function rosterMoveKey(characterId: string, moveName: string): string
	local mapped = LEGACY_TO_ROSTER[moveName] or moveName
	Roster.getMove(characterId, mapped)
	return mapped
end

local function opponentDistance(view: FighterView, frame: any?, slot: number): number?
	if not frame or type(frame.fighters) ~= "table" then return nil end
	local other = frame.fighters[if slot == 1 then 2 else 1]
	if type(other) ~= "table" or typeof(other.pos) ~= "Vector3" then return nil end
	local facing = if view.facing.Magnitude > 0.001 then view.facing.Unit else Vector3.xAxis
	local distance = (other.pos - view.pos):Dot(facing)
	if distance <= 0 then return nil end
	return distance
end

local function throwPose(view: FighterView, scale: number): Pose?
	local throw = view.throw
	if type(throw) ~= "table" then return nil end
	local archetype = throw.archetype
	if type(archetype) ~= "string" then error("MotionPlayer: throw snapshot missing archetype") end
	local fn = Throws[archetype]
	if not fn then error("MotionPlayer: missing throw archetype " .. archetype) end
	local track = fn(throw.duration, throw.impactFrame)
	local frame = if type(throw.frame) == "number" then throw.frame else 0
	local alpha = math.clamp(frame / math.max(track.duration, 1), 0, 1)
	local keys = if throw.role == "Defender" then track.defender else track.attacker
	return toHeading(sampleKeys(keys, alpha), scale)
end

-- Character id of the other fighter in this frame (throw defenders play the attacker's throw clip).
local function opponentId(frame: any?, slot: number): string?
	if not frame or type(frame.fighters) ~= "table" then return nil end
	local other = frame.fighters[if slot == 1 then 2 else 1]
	if type(other) == "table" and type(other.characterId) == "string" then return other.characterId end
	return nil
end

-- Standing root height of the other fighter (the presenter's rig value, else the roster estimate), for contact aim.
local function opponentRootHeight(frame: any?, slot: number): number?
	if not frame or type(frame.fighters) ~= "table" then return nil end
	local other = frame.fighters[if slot == 1 then 2 else 1]
	if type(other) ~= "table" then return nil end
	if type(other.rootHeight) == "number" then return other.rootHeight end
	if type(other.characterId) == "string" and Roster.has(other.characterId) then return characterRootHeight(other.characterId) end
	return nil
end

-- The other fighter's measured standing heights (High/Mid/Low world heights above the floor; CharacterPresenter puts
-- MotionPlayer.standingHeights on the views), or nil.
local function opponentAimHeights(frame: any?, slot: number): { [string]: number }?
	if not frame or type(frame.fighters) ~= "table" then return nil end
	local other = frame.fighters[if slot == 1 then 2 else 1]
	if type(other) == "table" and type(other.aimHeights) == "table" then return other.aimHeights end
	return nil
end

-- Normalised clip time of a throw at sim frame f: [0, impactFrame] plays [0, impact], the rest plays [impact, 1].
function MotionPlayer.throwTime(impact: number, f: number, impactFrame: number, duration: number): number
	local d = math.max(duration, 1)
	local hit = math.clamp(impactFrame, 1, d)
	local x = math.clamp(f, 0, d)
	if x <= hit then return impact * x / hit end
	return impact + (1 - impact) * (x - hit) / math.max(d - hit, 1)
end

-- FLThrow1 clip pose for this fighter's role, or nil (keyframe throw archetypes are the fallback).
MotionPlayer.ThrowAlignFrames = 4
local function throwClipPose(view: FighterView, frame: any?, slot: number, characterId: string, scale: number, legLength: number): Pose?
	local throw = view.throw
	if type(throw) ~= "table" or type(throw.move) ~= "string" then return nil end
	local defender = throw.role == "Defender"
	local attackerId = if defender then (opponentId(frame, slot) or characterId) else characterId
	local tc = ClipLibrary.forThrow(attackerId, throw.move)
	if not tc then return nil end
	local track = if defender then tc.defender else tc.attacker
	local duration = if type(throw.duration) == "number" then throw.duration else 48
	local impactFrame = if type(throw.impactFrame) == "number" then throw.impactFrame else duration * 0.6
	local u = MotionPlayer.throwTime(tc.impact, if type(throw.frame) == "number" then throw.frame else 0, impactFrame, duration)
	local pose = ClipPlayer.sample(track, u * track.duration, { mirror = track.mirror, legLength = legLength, scale = scale })
	if defender then
		-- The defender track was authored with the roots `distance` attacker leg lengths apart: slide the defender's
		-- body along its facing so the two bodies meet whatever the real spacing is. The correction ramps in over the
		-- first ThrowAlignFrames throw frames (the body glides into the clinch instead of jumping).
		local actual = opponentDistance(view, frame, slot)
		if actual then
			local other = frame and frame.fighters and frame.fighters[if slot == 1 then 2 else 1]
			local attackerLeg = if type(other) == "table" and type(other.legLength) == "number" then other.legLength else legLength
			local f = if type(throw.frame) == "number" then throw.frame else 0
			local w = smoothstep(f / math.max(MotionPlayer.ThrowAlignFrames, 1))
			pose.rootOffset += Vector3.new(0, 0, (actual - tc.distance * attackerLeg) * w)
		end
	end
	return pose
end

-- A broken throw (combat: `throw.broken`, `throw.breakFrame`; both fighters stay in Throw for ThrowBreakFrames, then
-- return to Idle pushed apart): each fighter plays its role's break track of the FLThrow1 clip, or the generic
-- Core.ThrowBreak shove, over the break frames. Never the rest of the throw.
local function throwBreakPose(view: FighterView, frame: any?, slot: number, characterId: string, scale: number, legLength: number, config: any): (Pose, string)
	local throw = view.throw
	local defender = throw.role == "Defender"
	local total = if type(config) == "table" and type(config.ThrowBreakFrames) == "number" then config.ThrowBreakFrames else 16
	local since = (if type(throw.frame) == "number" then throw.frame else 0) - (if type(throw.breakFrame) == "number" then throw.breakFrame else 0)
	local progress = math.clamp(since / math.max(total, 1), 0, 1)
	local attackerId = if defender then (opponentId(frame, slot) or characterId) else characterId
	local tc = if type(throw.move) == "string" then ClipLibrary.forThrow(attackerId, throw.move) else nil
	local track = if tc then (if defender then tc.breakDefender else tc.breakAttacker) else nil
	local source = if track then "clip" else "generic"
	if not track then track = ClipLibrary.find(States.CLIPS.ThrowBreak, nil) end
	if track then
		return ClipPlayer.sample(track, progress * track.duration, { mirror = track.mirror, legLength = legLength, scale = scale }), source
	end
	return toHeading(poseFromKey(States.pose(characterId, "Guard", scale, progress)), scale), "keyframe"
end

local function lungePhase(t: number): number
	if t < 0.35 then return 0 end
	if t <= 1 then return easeValue("in", (t - 0.35) / 0.65) end
	if t <= 1.48 then return 1 end
	return 1 - easeValue("out", (t - 1.48) / 1.52)
end

local function applyCosmeticLunge(pose: Pose, resolved: ResolvedMove, view: FighterView, frame: any?, slot: number, normalized: number)
	local move = resolved.move
	-- Moves with real root motion (`advance`, combat OV6) already travel in the sim; a cosmetic lunge would double it.
	if type(move.advance) == "number" then return end
	local distance = opponentDistance(view, frame, slot)
	if not distance then return end
	local surface = distance - 0.55
	if surface > ((move.range or 4) + 0.05) then return end
	local authoredMax = (move.range or 4) - 2.1 + (resolved.params.lunge or 0)
	local desired = math.clamp(authoredMax, 0, 2.4) * lungePhase(normalized)
	pose.rootOffset += Vector3.new(0, 0, desired)
end

-- Core states ---------------------------------------------------------------------------------------------------

local LIMB_EFFECTOR: { [string]: string } = { LeadArm = "LeftHand", RearArm = "RightHand", LeadLeg = "LeftFoot", RearLeg = "RightFoot" }
-- Reference shoulder/hip pivots (same as the IK's chain.refPivot) and the waist joint, in heading axes x scale.
local AIM_PIVOT: { [string]: Vector3 } = { LeftHand = Vector3.new(-0.5, 1.1, 0), RightHand = Vector3.new(0.5, 1.1, 0), LeftFoot = Vector3.new(-0.3, -0.35, 0), RightFoot = Vector3.new(0.3, -0.35, 0) }
local AIM_WAIST = Vector3.new(0, 0.3, 0)

-- Contact aim for attack clips: around the impact the striking hand/foot is pulled to the move's contact height
-- (High = head, Mid = body, Low = legs; Library.contactY) so mocap strikes land where the sim hits. The height is the
-- OPPONENT's (its standing root height when known), re-expressed above our own root, so strikes reach a taller head
-- and drop to a shorter one. Weight ramps in over the second half of startup, holds through the active frames and
-- releases over 40% of recovery. Clip tags: limb = "LeftHand"|... overrides the roster limb, aim = false disables,
-- aimWeight scales it.
local function aimContact(pose: Pose, clip: ClipLibrary.Clip, resolved: ResolvedMove, frame: number, scale: number, rootHeight: number, targetRootHeight: number?, targetHeights: { [string]: number }?)
	local tags = clip.tags
	if tags.aim == false then return end
	local move = resolved.move
	local height = move.height
	if height ~= "High" and height ~= "Mid" and height ~= "Low" then return end
	local limb = if type(tags.limb) == "string" then tags.limb else LIMB_EFFECTOR[move.limb or ""]
	local e = limb and pose.targets[limb]
	if not e then return end
	local timing = resolved.timing
	local first = timing.startup + 1
	local w
	if frame <= first then
		w = smoothstep((frame - first * 0.5) / math.max(first * 0.5, 1))
	elseif frame <= timing.startup + timing.active then
		w = 1
	else
		w = 1 - smoothstep((frame - timing.startup - timing.active) / math.max(timing.recovery * 0.4, 1))
	end
	w *= if type(tags.aimWeight) == "number" then tags.aimWeight else 1
	if w <= 0 then return end
	local targetY = Library.contactY(height, scale) - pose.rootOffset.Y
	if targetRootHeight then
		targetY = Library.contactY(height, scaleFromRoot(targetRootHeight)) + (targetRootHeight - rootHeight) - pose.rootOffset.Y
	end
	-- The IK hangs the hand (foot) off the POSED shoulder (hip): a leaning, pitched or twisted torso lowers that pivot
	-- below the reference one the targets are expressed against, so add the pivot's drop back.
	local pivot = AIM_PIVOT[limb]
	if pivot then
		local ref = pivot * scale
		local rootRot: CFrame = (pose :: any).rootRot or CFrame.Angles(pose.rootRotation.X, pose.rootRotation.Y, pose.rootRotation.Z)
		local posed: Vector3
		if limb == "LeftHand" or limb == "RightHand" then
			local waist = AIM_WAIST * scale
			local waistRot: CFrame = (pose :: any).waistRot or CFrame.Angles(pose.waist.X, pose.waist.Y, pose.waist.Z)
			posed = rootRot:VectorToWorldSpace(waist + waistRot:VectorToWorldSpace(ref - waist))
		else
			posed = rootRot:VectorToWorldSpace(ref)
		end
		targetY += ref.Y - posed.Y
	end
	e.pos = Vector3.new(e.pos.X, e.pos.Y + (targetY - e.pos.Y) * w, e.pos.Z)
	-- The aim weight marks the striking limb either way (the reach net leaves an aimed foot to the IK clamp toward its
	-- target). Exact layer: with the opponent's measured standing heights, MotionPlayer.apply moves the IK goal to that
	-- world height through the real posed shoulder/hip of this rig (the reference estimate above is only a first guess).
	e.aimWeight = w
	local worldY = targetHeights and targetHeights[height]
	if type(worldY) == "number" then
		e.aimWorldY = worldY
	end
end

type Request = States.MotionRequest

local function clipTime(clip: ClipLibrary.Clip, req: Request, st: SlotState, legLength: number): number
	local mode = req.timeMode
	if mode == "progress" then
		local tags = clip.tags
		local start = if req.startTag and tags and type(tags[req.startTag]) == "number" then math.clamp(tags[req.startTag], 0, clip.duration) else 0
		return start + (clip.duration - start) * math.clamp(req.progress or 0, 0, 1)
	end
	if mode == "contact" then return math.clamp(clip.contact or 1, 0, 1) * clip.duration * math.clamp(req.progress or 0, 0, 1) end
	if mode == "elapsed" then return (req.seconds or (st.clock - st.keyStarted)) * (req.rate or 1) end
	if mode == "impact" then
		local c = math.clamp(clip.contact or 0.5, 0, 1) * clip.duration
		local e = req.frames or (st.clock - st.keyStarted) * 60
		if req.fromContact then return c + e / 60 end
		local f = math.max(req.impactFrames or 14, 1)
		if e <= f then return c * e / f end
		return c + (e - f) / 60
	end
	if mode == "travel" and math.abs(clip.speed) > 0.001 and legLength > 0 and math.abs(st.travel) > 1e-4 then
		return math.abs(st.travel) / (math.abs(clip.speed) * legLength) + (req.phase or 0)
	end
	return (st.clock + (req.phase or 0)) * (req.rate or 1)
end

local function resolveRequest(req: Request, st: SlotState, style: string, scale: number, legLength: number): Pose
	if req.clip then
		local clip = ClipLibrary.find(req.clip, if req.styled == false then nil else States.STYLE_NAMES[style])
		if clip then
			local t = clipTime(clip, req, st, legLength)
			local pose = ClipPlayer.sample(clip, t, { mirror = req.mirror, legLength = legLength, scale = scale })
			local adjust = req.adjust
			if adjust then adjust(pose, clip) end
			if req.ground == 0 then
				-- An airborne body (KO still falling) must not be pulled onto the floor by the clip's ground channel.
				pose.ground = 0
			elseif req.ground and clip.contact then
				-- Lying states: from the clip's contact (the body reaching the floor) on, the body rests on the floor.
				local c = clip.contact * clip.duration
				if t >= c then pose.ground = math.max(pose.ground or 0, req.ground * math.clamp((t - c) / 0.05 + 0.5, 0, 1)) end
				-- ...and relaxes onto it right away (pelvis, head and feet settle with the impact; see MotionPlayer.apply).
				if req.settle == true then
					pose.settle = math.clamp((t - c) / 0.08, 0, 1)
					pose.relaxFeet = pose.settle
				end
			end
			-- Getups: the lying frames of the rise settle too, following the clip's own floor-support weight.
			if req.settle == "ground" then pose.settle = pose.ground end
			return pose
		end
	end
	local key = req.keyframe
	if not key then error("MotionPlayer: state request " .. req.key .. " has neither clip nor keyframe") end
	local pose = toHeading(poseFromKey(key), scale)
	if req.ground ~= nil then pose.ground = req.ground end
	return pose
end

local function addArmor(pose: Pose, view: FighterView)
	if view.armorActive == true then
		pose.rootOffset += Vector3.new(0, 0.015, 0)
		local waistRot = (pose.waistRot or anglesOf(pose.waist)) * CFrame.Angles(math.rad(-3), 0, 0)
		pose.waistRot = waistRot
		pose.waist = eulerOf(waistRot)
	end
end

local function validatePose(pose: Pose)
	if not finiteVector(pose.rootOffset) or not finiteVector(pose.rootRotation) or not finiteVector(pose.waist) or not finiteVector(pose.neck) then error("MotionPlayer produced a non-finite body pose") end
	for name, target in pose.targets do if not finiteVector(target.pos) or (target.pole and not finiteVector(target.pole)) then error("MotionPlayer produced non-finite target " .. name) end end
end

local function advanceClock(st: SlotState, frame: any?, view: FighterView)
	local now = if frame and type(frame.now) == "number" then frame.now else nil
	local dt = 0
	if frame and type(frame.dt) == "number" then
		dt = frame.dt
	elseif now and st.lastNow then
		dt = now - st.lastNow
	end
	if now then st.lastNow = now end
	st.clock += math.clamp(dt, 0, 0.1)
	-- Distance travelled along the facing (or sideways, whichever dominates) drives locomotion clips so planted
	-- feet stay planted whatever the walk speed.
	local pos = view.pos
	if typeof(pos) == "Vector3" then
		local last = st.lastPos
		if last then
			local delta = pos - last
			if delta.Magnitude < 4 then
				local facing = if view.facing.Magnitude > 0.001 then view.facing.Unit else Vector3.xAxis
				local lateral = Vector3.yAxis:Cross(facing)
				local flat = Vector3.new(delta.X, 0, delta.Z)
				local forward = flat:Dot(facing)
				local side = flat:Dot(lateral)
				st.travel += if math.abs(forward) >= math.abs(side) then forward else side
			end
		end
		st.lastPos = pos
	end
end

-- Step-ins (moves with `advance`): the share of the sim's designed root travel really applied since the attack's first
-- frame — keepApart caps it against an opponent standing at Separation. 1 = all of it (or not a step-in).
local function stepInScale(st: SlotState, view: FighterView, moveKey: string, resolved: ResolvedMove, scale: number): number
	local advance = resolved.move and resolved.move.advance
	local pos = view.pos
	if type(advance) ~= "number" or advance <= 0 or typeof(pos) ~= "Vector3" then
		st.stepMove = nil
		return 1
	end
	local mf = view.moveFrame or 0
	local startup = math.max(resolved.timing.startup, 1)
	local last = st.stepFrame
	if st.stepMove ~= moveKey or last == nil or mf < last or st.stepPos == nil then
		st.stepMove, st.stepFrame, st.stepPos, st.stepApplied, st.stepDesigned = moveKey, mf, pos, 0, 0
	elseif mf > last then
		-- The sim carries the root advance / startup studs per frame up to and including the first active frame.
		local counted = math.max(0, math.min(mf, startup + 1) - math.min(last, startup + 1))
		st.stepDesigned = (st.stepDesigned or 0) + advance / startup * counted
		local facing = if view.facing.Magnitude > 0.001 then view.facing.Unit else Vector3.xAxis
		local d = pos - (st.stepPos :: Vector3)
		st.stepApplied = (st.stepApplied or 0) + Vector3.new(d.X, 0, d.Z):Dot(facing)
		st.stepFrame, st.stepPos = mf, pos
	end
	local designed = st.stepDesigned or 0
	if designed <= 0.05 * scale then return 1 end
	return math.clamp((st.stepApplied or 0) / designed, 0, 1)
end

function MotionPlayer.sample(config: any, view: FighterView, frame: any?, slot: number?): Pose
	local s = slot or 1
	local st = slotState(s)
	local previous = st.pose
	local hitstop = frame ~= nil and (frame.hitstop or 0) > 0
	-- Hitstop freezes the pose, except on the frame a new reaction starts: the defender snaps to the impact pose
	-- (shown frozen for the whole hitstop) instead of freezing in its pre-hit stance.
	local reactionStart = hitstop and previous ~= nil and States.reactionKey(view) ~= nil and States.reactionKey(view) ~= st.key
	if hitstop and previous and not reactionStart then return previous end
	local prevPos = st.lastPos
	local clockBefore = st.clock
	advanceClock(st, frame, view)
	local characterId = characterForSlot(view, frame, s)
	local rootHeight = view.rootHeight or characterRootHeight(characterId)
	local scale = scaleFromRoot(rootHeight)
	local legLength = view.legLength or rootHeight * LEG_PER_ROOT
	-- The sim freezes the last move when a round ends; hold the final hit briefly, then settle into victory/defeat poses.
	local roundOver = frame ~= nil and (frame.phase == "MatchOver" or frame.phase == "RoundOver") and (frame.winner == 1 or frame.winner == 2)
	if roundOver then st.roundOverSince = st.roundOverSince or os.clock() else st.roundOverSince = nil end
	local settling = roundOver and os.clock() - (st.roundOverSince or 0) >= FINAL_HIT_HOLD
	local activeMove = if settling then nil else view.move
	local key: string
	local fade: number
	local pose: Pose? = nil
	if not settling and type(view.throw) == "table" then
		if view.throw.broken == true then
			local breakPose = throwBreakPose(view, frame, s, characterId, scale, legLength, config)
			pose = breakPose
			key, fade = "ThrowBreak", 0.05
		else
			pose = throwClipPose(view, frame, s, characterId, scale, legLength) or throwPose(view, scale)
			key, fade = "Throw", 0.06
		end
	end
	if pose then
		-- key/fade set above
	elseif activeMove then
		local moveKey = rosterMoveKey(characterId, activeMove)
		local resolved = MotionPlayer.resolveMove(characterId, moveKey, rootHeight)
		local clip = ClipLibrary.forMove(characterId, moveKey, view.stringIndex)
		if clip then
			pose = ClipPlayer.sample(clip, ClipPlayer.moveTime(clip, resolved.timing, view.moveFrame or 0), { mirror = clip.mirror, legLength = legLength, scale = scale })
			aimContact(pose :: Pose, clip, resolved, view.moveFrame or 0, scale, rootHeight, opponentRootHeight(frame, s), opponentAimHeights(frame, s))
		else
			local normalized = moveTime(resolved.timing, view.moveFrame or 0)
			local legacy = sampleKeys(resolved.keyframes, normalized)
			applyCosmeticLunge(legacy, resolved, view, frame, s, normalized)
			pose = toHeading(legacy, scale)
		end
		key, fade = "Move:" .. moveKey, 0.05
		local step = stepInScale(st, view, moveKey, resolved, scale)
		if step < 1 then (pose :: Pose).stepScale = step end
	else
		local style = if Roster.has(characterId) then Roster.get(characterId).stanceStyle else "boxer"
		local req = States.request(view, frame, s, characterId, scale, { clock = st.clock, keyStarted = st.keyStarted, key = st.key, settling = settling, config = config, legLength = legLength })
		if req.key ~= st.key then
			st.keyStarted = st.clock
			if req.restart then st.travel = 0 end
		end
		pose = resolveRequest(req, st, style, scale, legLength)
		key, fade = req.key, req.fade or 0.12
	end
	local result: Pose = pose :: Pose
	addArmor(result, view)
	-- The sim pushes both fighters apart on the frame a throw (or a broken throw) ends. The crossfade out of the throw
	-- starts from the last throw pose held where it was in the world (compensated by the sim jump), so the body slides
	-- over the push during the fade instead of popping. A track that already ends at the pushed spot shows no slide.
	local leavingThrow = st.key ~= nil and string.sub(st.key, 1, 5) == "Throw" and string.sub(key, 1, 5) ~= "Throw"
	-- A new round (the sim puts both fighters back on their marks; the KO'd loser is standing again) is a clean cut:
	-- crossfading from the lying/celebrating pose at the new spot would show a body morphing upright.
	local roundReset = (prevPos ~= nil and typeof(view.pos) == "Vector3" and (view.pos - prevPos).Magnitude > MotionPlayer.TeleportDistance)
		or (key == "Intro" and st.key ~= nil and (string.sub(st.key, 1, 3) == "KO:" or st.key == "Victory" or st.key == "Defeat"))
	if st.key ~= key then
		if previous and fade > 0 and not reactionStart and not roundReset then
			local from = previous
			if leavingThrow and prevPos and typeof(view.pos) == "Vector3" then
				local d = view.pos - prevPos
				d = Vector3.new(d.X, 0, d.Z)
				if d.Magnitude > 0.05 and d.Magnitude < 2.5 then
					local facing = if view.facing.Magnitude > 0.001 then view.facing.Unit else Vector3.xAxis
					local right = facing:Cross(Vector3.yAxis)
					local held = table.clone(previous)
					held.rootOffset = previous.rootOffset - Vector3.new(d:Dot(right), 0, d:Dot(facing))
					from = held
					fade = math.max(fade, 0.12)
				end
			end
			st.fadeFrom = from
			st.fadeStart = clockBefore
			st.fadeDur = fade
		else
			st.fadeFrom = nil
		end
		st.key = key
	end
	local from = st.fadeFrom
	if from then
		local alpha = smoothstep((st.clock - st.fadeStart) / math.max(st.fadeDur, 1e-3))
		if alpha >= 1 then st.fadeFrom = nil else result = blendPose(from, result, alpha) end
	end
	validatePose(result)
	result.clock = st.clock
	st.pose = result
	return result
end

-- Menu/preview pose without a fight view: "Stance", "Guard", "Intro", "Victory", "Defeat" at time t (seconds).
function MotionPlayer.namedPose(characterId: string, name: string, t: number, rootHeight: number, legLength: number?): Pose
	local scale = scaleFromRoot(rootHeight)
	local leg = legLength or rootHeight * LEG_PER_ROOT
	local req = States.named(characterId, name, scale, t, leg)
	local st = newSlot(t)
	local pose = resolveRequest(req, st, Roster.get(characterId).stanceStyle, scale, leg)
	-- Previews jump between unrelated poses on the same rig: never pin their feet to a previous pose.
	pose.footLock = false
	return pose
end

-- Rig -----------------------------------------------------------------------------------------------------------------

local function safeUnit(v: Vector3, fallback: Vector3): Vector3 if v.Magnitude > 1e-5 then return v.Unit end; return fallback.Unit end
local function projectPole(pole: Vector3, dir: Vector3, fallback: Vector3): Vector3
	local p = pole - dir * pole:Dot(dir)
	if p.Magnitude < 1e-5 then p = fallback - dir * fallback:Dot(dir) end
	if p.Magnitude < 1e-5 then p = Vector3.yAxis - dir * Vector3.yAxis:Dot(dir) end
	return safeUnit(p, Vector3.yAxis)
end
function MotionPlayer.solveTwoBone(startPos: Vector3, targetPos: Vector3, upperLen: number, lowerLen: number, poleHint: Vector3): (Vector3, Vector3, boolean)
	if upperLen <= 0 or lowerLen <= 0 then error("LimbIK lengths must be positive") end
	local raw = targetPos - startPos
	local dir = safeUnit(raw, Vector3.zAxis)
	local maxReach = (upperLen + lowerLen) * 0.999
	local minReach = math.max(math.abs(upperLen - lowerLen) + 0.001, 0.001)
	local dist = math.clamp(raw.Magnitude, minReach, maxReach)
	local target = startPos + dir * dist
	local a = (upperLen * upperLen - lowerLen * lowerLen + dist * dist) / (2 * dist)
	local h2 = math.max(upperLen * upperLen - a * a, 0)
	local pole = projectPole(poleHint, dir, Vector3.yAxis)
	local mid = startPos + dir * a + pole * math.sqrt(h2)
	return mid, target, raw.Magnitude > maxReach
end

local function restChain(motors: { [string]: Motor6D }, joint: string, mid: string, tip: string, target: string, isLeg: boolean): any
	local j, m, t = motors[joint], motors[mid], motors[tip]
	local upperBone = m.C0.Position - j.C1.Position
	local lowerBone = t.C0.Position - m.C1.Position
	local endPart = t.Part1
	local ankleHeight = if isLeg and endPart then math.max(0, t.C1.Position.Y + endPart.Size.Y * 0.5) else 0
	local side = if string.sub(joint, 1, 4) == "Left" then -1 else 1
	-- Arms reach to the hand center, legs to the ankle pivot. Fighters with fist meshes reach to the fist instead,
	-- because their long open-hand mesh is hidden and the fist sits just past the wrist.
	local handReach = if isLeg then 0 else t.C1.Position.Magnitude
	local fist = if not isLeg and endPart then endPart:FindFirstChild(if side < 0 then "LeftFist" else "RightFist") else nil
	if fist and fist:IsA("BasePart") and endPart then
		handReach = (t.C1.Position - endPart.CFrame:PointToObjectSpace(fist.Position)).Magnitude
	end
	local reach = lowerBone.Magnitude + handReach
	local l1, l2 = math.max(upperBone.Magnitude, 0.05), math.max(reach, 0.05)
	-- Library targets were authored for a reference rig (scale 1): shoulders at (+-0.5, 1.1, 0) with ~1.95 reach, hips at (+-0.3, -0.35, 0) with ~2.75 hip-to-sole reach.
	local refPivotV = if isLeg then Vector3.new(side * 0.3, -0.35, 0) else Vector3.new(side * 0.5, 1.1, 0)
	local refReach = if isLeg then 2.75 else 1.95
	local fullReach = l1 + l2 + (if isLeg then ankleHeight else 0)
	local upperPart, lowerPart = j.Part1, m.Part1
	local tipSize = if endPart then endPart.Size else Vector3.one * 0.3
	return {
		joint = joint, mid = mid, tip = tip, target = target, isLeg = isLeg, upperBone = upperBone, l1 = l1, l2 = l2,
		ankleHeight = ankleHeight, refPivot = refPivotV, refReach = refReach, fullReach = fullReach, side = side,
		upperSize = if upperPart then upperPart.Size else Vector3.one * 0.4, lowerSize = if lowerPart then lowerPart.Size else Vector3.one * 0.4,
		tipSize = tipSize, tipOffset = t.C1.Position,
		handRadius = math.min(tipSize.X, tipSize.Z) * 0.5 + 0.02,
		midRadius = math.max(if upperPart then math.min(upperPart.Size.X, upperPart.Size.Z) else 0.4, if lowerPart then math.min(lowerPart.Size.X, lowerPart.Size.Z) else 0.4) * 0.5 + 0.02,
	}
end

function MotionPlayer.collectRig(model: Model): RigInfo
	local motors: { [string]: Motor6D } = {}
	local parts: { [string]: BasePart } = {}
	for _, d in model:GetDescendants() do if d:IsA("BasePart") then parts[d.Name] = d elseif d:IsA("Motor6D") then motors[d.Name] = d end end
	local rootHeight = model:GetAttribute("RootHeight")
	if typeof(rootHeight) ~= "number" or rootHeight <= 0 then error("R15 template " .. model.Name .. " needs numeric RootHeight") end
	for _, joint in Library.Joints do if not motors[joint] then error("R15 template " .. model.Name .. " is missing Motor6D " .. joint) end end
	local chains = {
		LeftArm = restChain(motors, "LeftShoulder", "LeftElbow", "LeftWrist", "LeftHand", false),
		RightArm = restChain(motors, "RightShoulder", "RightElbow", "RightWrist", "RightHand", false),
		LeftLeg = restChain(motors, "LeftHip", "LeftKnee", "LeftAnkle", "LeftFoot", true),
		RightLeg = restChain(motors, "RightHip", "RightKnee", "RightAnkle", "RightFoot", true),
	}
	local function size(name: string): Vector3
		local part = parts[name]
		return if part then part.Size else Vector3.one
	end
	-- Each body part's driving joint (Part1 = the part), to compute posed part frames through the joint chain.
	local partMotor: { [string]: Motor6D } = {}
	for _, motor in motors do
		local p1 = motor.Part1
		if p1 then partMotor[p1.Name] = motor end
	end
	return {
		motors = motors, parts = parts, rootHeight = rootHeight,
		legLength = (chains.LeftLeg.fullReach + chains.RightLeg.fullReach) * 0.5,
		armLength = (chains.LeftArm.fullReach + chains.RightArm.fullReach) * 0.5,
		chains = chains,
		sizes = { LowerTorso = size("LowerTorso"), UpperTorso = size("UpperTorso"), Head = size("Head") },
		footLock = {}, stats = { groundShift = 0, lowest = 0 }, tips = {}, footClear = {}, footHang = {}, partMotor = partMotor,
	}
end

-- World frame of a body part as posed by the latest MotionPlayer.apply (through the joint chain: the engine updates
-- part CFrames from Motor6D transforms only on its next step).
local function partWorld(rig: RigInfo, name: string): CFrame?
	local part = rig.parts[name]
	if not part then return nil end
	local motor = rig.partMotor[name]
	if not motor or not motor.Part0 then return part.CFrame end
	local parent = partWorld(rig, (motor.Part0 :: BasePart).Name)
	if not parent then return nil end
	return parent * motor.C0 * motor.Transform * motor.C1:Inverse()
end
MotionPlayer.partWorld = partWorld

-- Depth of a body part below its centre: halfway between its oriented box and its inscribed ellipsoid (R15 meshes are
-- rounded boxes: box corners overestimate tilted parts, ellipsoids underestimate them).
local function extentY(cf: CFrame, size: Vector3): number
	local r, u, l = cf.RightVector.Y, cf.UpVector.Y, cf.LookVector.Y
	local box = math.abs(r) * size.X + math.abs(u) * size.Y + math.abs(l) * size.Z
	local ellipsoid = math.sqrt((r * size.X) ^ 2 + (u * size.Y) ^ 2 + (l * size.Z) ^ 2)
	return (box + ellipsoid) * 0.25
end
MotionPlayer.extentY = extentY

local function flatYaw(rot: CFrame): CFrame
	local look = rot.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		local up = rot.UpVector
		flat = Vector3.new(-up.X, 0, -up.Z)
		if flat.Magnitude < 1e-3 then return CFrame.identity end
	end
	return CFrame.lookAt(Vector3.zero, flat.Unit)
end

-- Lowest pole on the IK circle that keeps the mid joint (knee/elbow) at least `minY` high: rotates the pole hint
-- toward "up" within the plane perpendicular to the limb until the joint clears the floor.
local function liftPole(startPos: Vector3, targetPos: Vector3, upperLen: number, lowerLen: number, pole: Vector3, minY: number): Vector3
	local mid = MotionPlayer.solveTwoBone(startPos, targetPos, upperLen, lowerLen, pole)
	if mid.Y >= minY then return pole end
	local dir = safeUnit(targetPos - startPos, Vector3.zAxis)
	local up = Vector3.yAxis - dir * dir.Y
	if up.Magnitude < 1e-3 then return pole end
	up = up.Unit
	local base = projectPole(pole, dir, up)
	local lo, hi = 0, 1
	for _ = 1, 7 do
		local t = (lo + hi) * 0.5
		local candidate = base:Lerp(up, t)
		local m = MotionPlayer.solveTwoBone(startPos, targetPos, upperLen, lowerLen, candidate)
		if m.Y >= minY then hi = t else lo = t end
	end
	return base:Lerp(up, hi)
end

-- Solves one limb, sets its three Motor6D transforms and returns the lowest world Y of its parts.
-- Runtime foot locking: a planted foot (clip contact) keeps its world X/Z while the contact lasts, so feet never skate
-- when the body moves differently from the source (style scaling, rig proportions, sim speed vs clip speed). The
-- anchor is leashed: pushback or turning drags it along instead of stretching the leg, and a teleport resets it.
-- Releasing is paced: the lock weight follows the contact up at once but lets go no faster than FootLockRelease
-- seconds (pose clock), so a foot held back on its anchor — a step-in's rear foot while keepApart capped the root —
-- leaves it smoothly instead of snapping to the clip's spot when its contact drops. Grip passes release at once.
MotionPlayer.FootLockLeash = 0.3
MotionPlayer.FootLockRelease = 4 / 60
local function lockFoot(rig: RigInfo, name: string, goal: Vector3, contact: number, scale: number, hardRelease: boolean?): Vector3
	local st = rig.footLock[name]
	if not st then
		st = { x = 0, z = 0, active = false, w = 0, t = nil, releasing = false }
		rig.footLock[name] = st
	end
	local target = if contact < 0.5 then 0 else math.clamp((contact - 0.5) / 0.3, 0, 1)
	local clock = rig.lockClock
	if hardRelease then
		st.active, st.w, st.t, st.releasing = false, 0, clock, false
		return goal
	end
	if not st.active then
		st.w, st.t, st.releasing = target, clock, false
		if contact < 0.5 then return goal end
		st.active, st.x, st.z = true, goal.X, goal.Z
		return goal
	end
	local lastW, lastT = st.w or 0, st.t
	local paced = clock ~= nil and lastT ~= nil and clock >= lastT
	local faded = if paced then math.max(0, lastW - (clock - lastT) / MotionPlayer.FootLockRelease) else 0
	if contact >= 0.5 and st.releasing then
		-- Lands again while still letting go: it locks where it is shown now, never back on the old anchor.
		st.x, st.z = goal.X + (st.x - goal.X) * faded, goal.Z + (st.z - goal.Z) * faded
		st.releasing, st.w, st.t = false, 1, clock
		return Vector3.new(st.x, goal.Y, st.z)
	end
	local w = if paced and target < lastW then math.max(target, faded) else target
	st.w, st.t = w, clock
	if contact < 0.5 then
		if w <= 1e-3 then
			st.active, st.releasing = false, false
			return goal
		end
		st.releasing = true
	end
	local leash = MotionPlayer.FootLockLeash * scale
	local dx, dz = st.x - goal.X, st.z - goal.Z
	local d = math.sqrt(dx * dx + dz * dz)
	if d > leash * 4 then
		st.x, st.z = goal.X, goal.Z
		return goal
	end
	if d > leash then
		local k = leash / d
		dx, dz = dx * k, dz * k
		st.x, st.z = goal.X + dx, goal.Z + dz
	end
	return Vector3.new(goal.X + dx * w, goal.Y, goal.Z + dz * w)
end

-- A foot whose toes point into the floor while the body lies (captures tuck the toes under) relaxes like a knocked-out
-- body's: the toes lay out along the floor, `pitch` radians down (15 degrees by default), instep on the floor, sole up
-- (big toe stays medial: a 180-degree roll about the toe line). w: 0..1. Feet with the toes up or level (face up, soles
-- planted) are kept.
local RELAX_PITCH = math.rad(15)
local RELAX_PITCH_MAX = math.rad(60)
-- Steepest a planted foot rises onto its ball (toes below the floor plane) when its straight leg cannot reach the floor.
local TIPTOE_MAX = math.rad(60)
-- Reach net. A foot target beyond the leg's reach from the posed hip — step-ins (the sim carries the root forward by
-- `advance` while the rear foot stays behind), hand-keyed lunges, a pelvis riding high for a rig's legs — used to be
-- lifted off the floor by the IK clamp. A foot the clip holds on or near the floor (its own sole within NET_NEAR leg
-- lengths, fading out by NET_AIR) now keeps its height: it rises onto its ball (at most NET_TIPTOE), then slides along
-- the floor toward the hip until the straight leg reaches it, and a world-space planted lock is re-anchored there.
-- Reachable targets are never touched. false = the round-4 behaviour (diagnostics, A/B captures).
MotionPlayer.FootReachNet = true
local NET_NEAR, NET_AIR = 0.12, 0.25
local NET_TIPTOE = math.rad(40)
local function relaxLyingFoot(r: CFrame, w: number, pitch: number?): CFrame
	local look = r.LookVector
	local k = math.clamp((-look.Y - 0.15) / 0.35, 0, 1) * w
	if k <= 0 then return r end
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.2 then
		local up = r.UpVector
		flat = Vector3.new(-up.X, 0, -up.Z)
	end
	if flat.Magnitude < 1e-3 then return r end
	local p = pitch or RELAX_PITCH
	local dir = flat.Unit * math.cos(p) - Vector3.yAxis * math.sin(p)
	return r:Lerp(CFrame.lookAt(Vector3.zero, dir, -Vector3.yAxis), k)
end

-- Height of the ankle above the lowest point of a foot in orientation r (the ankle lift that rests that foot on the floor).
local function footLift(chain: any, r: CFrame): number
	return r:VectorToWorldSpace(chain.tipOffset).Y + extentY(r, chain.tipSize)
end

-- The foot rises onto its ball — toes pitched down about the ankle, at most `limit` below the floor plane — just enough
-- for its ankle (ankleAt: ankle height of the foot shown in a rotation, its lowest point keeping its clearance above the
-- floor) to reach `needY`; the full `limit` when that is not enough.
local function riseOnBall(base: CFrame, needY: number, limit: number, ankleAt: (CFrame?) -> number): CFrame
	local room = math.max(0, limit - math.asin(math.clamp(-base.LookVector.Y, -1, 1)))
	local function tiptoe(a: number): CFrame return base * CFrame.Angles(-a, 0, 0) end
	local tlo, thi = 0, room
	if ankleAt(tiptoe(thi)) >= needY then
		for _ = 1, 7 do
			local mid = (tlo + thi) * 0.5
			if ankleAt(tiptoe(mid)) >= needY then thi = mid else tlo = mid end
		end
	end
	return tiptoe(thi)
end

-- Reach net: slides an ankle goal at height y along the floor toward the hip until the straight leg (reach) gets there —
-- right under the hip when even a leg hanging straight down cannot reach that height — blended in by w; a world-space
-- planted lock is re-anchored where the foot now stands. Returns the new goal and the reachable ankle height.
local function slideIntoReach(rig: RigInfo, target: string, goal: Vector3, pivotPos: Vector3, reach: number, y: number, w: number, locked: boolean): (Vector3, number)
	local ty = math.max(y, pivotPos.Y - reach)
	local room = math.sqrt(math.max(reach * reach - (pivotPos.Y - ty) ^ 2, 0))
	local dx, dz = goal.X - pivotPos.X, goal.Z - pivotPos.Z
	local d = math.sqrt(dx * dx + dz * dz)
	if d > room then
		local s = if d > 1e-6 then room / d else 0
		goal = Vector3.new(goal.X + (pivotPos.X + dx * s - goal.X) * w, goal.Y, goal.Z + (pivotPos.Z + dz * s - goal.Z) * w)
		local lock = if locked then rig.footLock[target] else nil
		if lock and lock.active then lock.x, lock.z = goal.X, goal.Z end
	end
	return goal, ty
end

local function solveChain(rig: RigInfo, chain: any, parentFrame: CFrame, heading: CFrame, legacyFrame: CFrame, effector: Effector, floorY: number, footFlat: CFrame, scale: number, headingSpace: boolean, contact: number, settle: number?, lying: number?, relax: number?, stepScale: number?): number
	local motors = rig.motors
	local jm, mm, tm = motors[chain.joint], motors[chain.mid], motors[chain.tip]
	local pivot = parentFrame * jm.C0
	local targetFrame = if headingSpace then heading else legacyFrame
	-- Re-express the authored target relative to the reference shoulder/hip, scaled to this rig's limb reach.
	local rel = (effector.pos - chain.refPivot * scale) * (chain.fullReach / (chain.refReach * scale))
	local goal = pivot.Position + targetFrame:VectorToWorldSpace(libVector(rel))
	local aimY, aimW = effector.aimWorldY, effector.aimWeight
	if aimY and aimW and aimW > 0 then
		-- Contact aim at a measured world height (the opponent's head/chest/knee), through this rig's posed pivot.
		goal = Vector3.new(goal.X, goal.Y + (floorY + aimY - goal.Y) * math.min(aimW, 1), goal.Z)
	end
	local planted = 0
	local footRot: CFrame? = nil
	if chain.isLeg then
		if headingSpace then goal = lockFoot(rig, chain.target, goal, contact, scale, effector.gripWorld ~= nil) end
		-- The foot effector is the sole point under the ankle (sole = ankle - ankle height, so the clip's ankle height is
		-- reproduced). Near the floor the foot is SHOWN flattened sole-down (planted), and the ankle height is derived from
		-- that shown orientation: the foot's lowest point keeps the clip foot's clearance above the floor (a foot the
		-- clip plants, or one settling on the floor, rests on it), so flattening pivots the foot onto the floor instead of
		-- leaving it hovering at the tilted foot's ankle height. Never below the floor.
		local lyingW = math.clamp(lying or 0, 0, 1)
		local r: CFrame? = nil
		if headingSpace and effector.rot then
			r = heading.Rotation * (effector.rot :: CFrame)
			if relax and relax > 0 then
				local r0 = r :: CFrame
				local relaxed = relaxLyingFoot(r0, relax)
				-- The shin lying on the floor holds the ankle up by its radius: the relaxed foot drapes over the ankle
				-- until its toes touch the floor (thick boots/shins need a steeper drop).
				local need = chain.midRadius * lyingW
				if need > 0 and footLift(chain, relaxed) < need then
					local lo, hi = RELAX_PITCH, RELAX_PITCH_MAX
					for _ = 1, 6 do
						local mid = (lo + hi) * 0.5
						if footLift(chain, relaxLyingFoot(r0, relax, mid)) < need then lo = mid else hi = mid end
					end
					relaxed = relaxLyingFoot(r0, relax, hi)
				end
				r = relaxed
			end
		end
		local clipLift = if r then footLift(chain, r) else chain.ankleHeight
		local clear = math.max(goal.Y + chain.ankleHeight - floorY - clipLift, 0)
		-- Near-floor weight: 1 for a foot the clip holds on or near the floor (its own sole within NET_NEAR leg lengths),
		-- fading out by NET_AIR (a foot clearly in the air: steps, chambers, kicks); never on a lying body or a striking
		-- foot the contact aim pulls to the opponent. It weights the reach net (MotionPlayer.FootReachNet) and the
		-- capped step-in: when keepApart held the root back (stepScale < 1), a released near-floor foot lifts only as
		-- much of its clip clearance as the body really travelled, instead of stepping in place.
		local soleLegs = effector.sole or clear / chain.fullReach
		local nearW = math.clamp((NET_AIR - soleLegs) / (NET_AIR - NET_NEAR), 0, 1) * (1 - lyingW) * (1 - math.clamp(effector.aimWeight or 0, 0, 1))
		local netW = if MotionPlayer.FootReachNet then nearW else 0
		if stepScale and stepScale < 1 then clear *= 1 - nearW * (1 - math.max(stepScale, 0)) end
		-- Clip feet carry their own contact channel (keyframe fallbacks do not): a planted foot rests on the floor, and a
		-- body relaxing on the floor (settle) lets its feet rest on it.
		local hold = math.clamp(settle or 0, 0, 1)
		if r then hold = math.max(hold, math.clamp((contact - 0.5) / 0.3, 0, 1)) end
		clear *= 1 - hold
		-- Feet near the floor are flattened sole-down (planted), except on a lying body: there the foot keeps the clip's
		-- (relaxed) orientation.
		planted = math.clamp(1 - clear / 0.35, 0, 1) * (1 - lyingW)
		local function ankleY(rot: CFrame?): number
			local y = floorY + clear + math.max(if rot then footLift(chain, rot) else chain.ankleHeight, 0.05)
			-- A lying leg rests its shin on the floor: the ankle sits at least the shin's radius above it.
			if lyingW > 0 then y = math.max(y, floorY + chain.midRadius * lyingW) end
			return y
		end
		local reach = (chain.l1 + chain.l2) * 0.995
		local pivotPos = pivot.Position
		local flatD = Vector3.new(goal.X - pivotPos.X, 0, goal.Z - pivotPos.Z).Magnitude
		-- Lowest ankle height the leg reaches above this spot (the foot keeps its place on the floor).
		local lowestY = if flatD < reach then pivotPos.Y - math.sqrt(reach * reach - flatD * flatD) else -math.huge
		if r then
			local clipRot = r :: CFrame
			local flat = footFlat * flatYaw(heading.Rotation:Inverse() * clipRot)
			local k = planted
			local shown = if k > 0 then clipRot:Lerp(flat, k) else clipRot
			local y = ankleY(shown)
			if k > 0 and y < lowestY then
				-- A (nearly) straight leg cannot lower its ankle to a flat foot: the heel stays up just enough and the
				-- foot rests on its ball instead, still on the floor.
				local lo, hi = 0, k
				for _ = 1, 7 do
					local mid = (lo + hi) * 0.5
					if ankleY(clipRot:Lerp(flat, mid)) >= lowestY then lo = mid else hi = mid end
				end
				k = lo
				shown = if k > 0 then clipRot:Lerp(flat, k) else clipRot
				y = ankleY(shown)
				if y < lowestY and hold >= 0.5 then
					-- Even the clip's own foot cannot reach (a straight support or pivot leg on a rig whose pelvis rides
					-- high for its legs): the planted foot rises further onto its ball until its toes reach the floor.
					shown = riseOnBall(shown, lowestY, TIPTOE_MAX, ankleY)
					y = ankleY(shown)
				end
			end
			if y < lowestY or flatD >= reach then
				-- Still out of reach. Without the net, a planted foot's ankle goes as low as the leg reaches above the same
				-- spot, and any other foot is left to the IK clamp toward the hip — both lift the foot off the floor. The
				-- net keeps it at its height: on its ball (at most NET_TIPTOE) and slid toward the hip along the floor.
				local lifted = if planted > 0 then math.max(y, lowestY) else y
				if netW > 0 then
					local ball = riseOnBall(shown, if flatD < reach then lowestY else math.huge, NET_TIPTOE, ankleY)
					local ty
					goal, ty = slideIntoReach(rig, chain.target, goal, pivotPos, reach, ankleY(ball), netW, headingSpace)
					-- A pelvis riding higher than even a straight leg hanging under it reaches (a hop, a rising knee): the
					-- shortfall is reported so MotionPlayer.apply lowers the body onto that foot.
					local hang = rig.footHang
					if hang then hang[chain.target] = math.max(0, ty - ankleY(ball)) * netW end
					shown = shown:Lerp(ball, netW)
					y = lifted + (ty - lifted) * netW
				else
					y = lifted
				end
			end
			footRot = shown
			goal = Vector3.new(goal.X, y, goal.Z)
			local intent = rig.footClear
			if intent then intent[chain.target] = ankleY(shown) - footLift(chain, shown) - floorY end
		else
			local y = ankleY(nil)
			local intent = rig.footClear
			if intent then intent[chain.target] = y - chain.ankleHeight - floorY end
			if netW > 0 and (y < lowestY or flatD >= reach) then
				local ty
				goal, ty = slideIntoReach(rig, chain.target, goal, pivotPos, reach, y, netW, headingSpace)
				local hang = rig.footHang
				if hang then hang[chain.target] = math.max(0, ty - y) * netW end
				y += (ty - y) * netW
			end
			goal = Vector3.new(goal.X, y, goal.Z)
		end
	else
		goal = Vector3.new(goal.X, math.max(goal.Y, floorY + chain.handRadius), goal.Z)
	end
	local gripPoint, gripW = effector.gripWorld, effector.gripWeight
	if gripPoint and gripW and gripW > 0 then
		-- Throw grip: the hand centre / ankle goes to the partner's real body point (MotionPlayer.applyGrips).
		local minY = floorY + (if chain.isLeg then chain.ankleHeight else chain.handRadius)
		goal = goal:Lerp(Vector3.new(gripPoint.X, math.max(gripPoint.Y, minY), gripPoint.Z), math.min(gripW, 1))
	end
	local pole = targetFrame:VectorToWorldSpace(libVector(effector.pole or defaultPole(chain.target)))
	local bone = safeUnit(chain.upperBone, -Vector3.yAxis)
	local foldRest = if chain.isLeg then Vector3.zAxis else -Vector3.zAxis
	foldRest = safeUnit(foldRest - bone * foldRest:Dot(bone), foldRest)
	local restFrame = CFrame.fromMatrix(Vector3.zero, bone, foldRest):Inverse()
	local upperWorld, lowerWorld, tipWorld = pivot, pivot, pivot
	local midClearance = chain.midRadius
	for attempt = 1, 3 do
		-- Knees and elbows never bend through the floor.
		local bendPole = liftPole(pivot.Position, goal, chain.l1, chain.l2, pole, floorY + midClearance)
		local aim = goal
		for iteration = 1, 3 do
			local joint, tip = MotionPlayer.solveTwoBone(pivot.Position, aim, chain.l1, chain.l2, bendPole)
			local u = safeUnit(joint - pivot.Position, -pivot.UpVector)
			local f = safeUnit(tip - joint, u)
			-- The lower segment folds toward the inside of the bend; a straight limb folds away from its pole.
			local inward = f - u * f:Dot(u)
			if inward.Magnitude < 1e-3 then inward = -(bendPole - u * bendPole:Dot(u)) end
			inward = safeUnit(inward, -pivot.LookVector)
			local upperRot = CFrame.fromMatrix(Vector3.zero, u, inward) * restFrame
			jm.Transform = pivot.Rotation:Inverse() * upperRot * jm.C1.Rotation
			-- Elbows flex forward (+X), knees flex backward (-X).
			local bend = math.acos(math.clamp(u:Dot(f), -1, 1))
			mm.Transform = CFrame.Angles(if chain.isLeg then -bend else bend, 0, 0)
			upperWorld = pivot * jm.Transform * jm.C1:Inverse()
			lowerWorld = upperWorld * mm.C0 * mm.Transform * mm.C1:Inverse()
			-- R15 rest bones are not perfectly collinear (and hands sit off the forearm axis): measure where the tip
			-- really lands and re-aim (accumulating the correction) so ankles/hands hit their goals on every proportion.
			local actual = if chain.isLeg then (lowerWorld * tm.C0).Position else (lowerWorld * tm.C0 * tm.C1:Inverse()).Position
			local miss = goal - actual
			if iteration < 3 and miss.Magnitude > 0.004 then aim += miss else break end
		end
		local tipTransform = CFrame.identity
		if chain.isLeg then
			-- footRot is the foot exactly as shown (clip rotation, flattened when planted) — the ankle height above was
			-- derived from it. Keyframe fallbacks without a foot rotation flatten their planted feet here.
			local wanted: CFrame? = footRot
			if not wanted and planted > 0 then wanted = footFlat end
			if wanted then
				local flat = (lowerWorld * tm.C0).Rotation:Inverse() * wanted * tm.C1.Rotation
				tipTransform = if footRot then flat else CFrame.identity:Lerp(flat, planted)
			end
		end
		tm.Transform = tipTransform
		tipWorld = lowerWorld * tm.C0 * tipTransform * tm.C1:Inverse()
		-- A tilted foot (toe or heel down) or a hand dipping below the floor raises its goal by the overlap; a thigh,
		-- shin or forearm dipping below it (segments overhang their joints) lifts the knee/elbow further.
		local tipBottom = tipWorld.Position.Y - extentY(tipWorld, chain.tipSize)
		local segmentBottom = math.min(upperWorld.Position.Y - extentY(upperWorld, chain.upperSize), lowerWorld.Position.Y - extentY(lowerWorld, chain.lowerSize))
		local retry = false
		if tipBottom < floorY - 0.005 then
			goal += Vector3.new(0, floorY - tipBottom + 0.01, 0)
			retry = true
		end
		if segmentBottom < floorY - 0.005 then
			midClearance += floorY - segmentBottom + 0.01
			retry = true
		end
		if attempt == 3 or not retry then break end
	end
	rig.tips[chain.target] = tipWorld
	return math.min(upperWorld.Position.Y - extentY(upperWorld, chain.upperSize), lowerWorld.Position.Y - extentY(lowerWorld, chain.lowerSize), tipWorld.Position.Y - extentY(tipWorld, chain.tipSize))
end

-- Applies a pose to a rig whose HumanoidRootPart has already been placed (fighter position + rootOffset).
-- floorY: world floor height (defaults to HRP height - RootHeight).
function MotionPlayer.apply(rig: RigInfo, pose: Pose, floorY: number?)
	local motors = rig.motors
	local rootPart = motors.Root.Part0
	if not rootPart then return end
	local headingSpace = pose.space == "heading"
	local rootRot = pose.rootRot or anglesOf(pose.rootRotation)
	local waistRot = pose.waistRot or anglesOf(pose.waist)
	local neckRot = pose.neckRot or anglesOf(pose.neck)
	local hrp = rootPart.CFrame
	local floor = if floorY ~= nil then floorY else hrp.Position.Y - rig.rootHeight
	local rootC0 = hrp * motors.Root.C0
	local lowerTorso = rootC0 * rootRot * motors.Root.C1:Inverse()
	local upperTorso = lowerTorso * motors.Waist.C0 * waistRot * motors.Waist.C1:Inverse()
	local head = upperTorso * motors.Neck.C0 * neckRot * motors.Neck.C1:Inverse()
	local sizes = rig.sizes
	local coreLowest = math.min(
		lowerTorso.Position.Y - extentY(lowerTorso, sizes.LowerTorso),
		upperTorso.Position.Y - extentY(upperTorso, sizes.UpperTorso),
		head.Position.Y - extentY(head, sizes.Head)
	)
	-- Ground solver: lying/kneeling poses (ground weight) rest their lowest body part on the floor, and no pose sinks
	-- into it. The correction moves the pelvis through the Root joint, so callers' root placement stays untouched.
	local ground = pose.ground
	if ground == nil then ground = legacyLying(pose.rootRotation) end
	local clearance = MotionPlayer.GroundClearance
	local dy = 0
	if ground > 0 then dy = (floor + clearance - coreLowest) * math.clamp(ground, 0, 1) end
	if coreLowest + dy < floor + clearance * 0.5 then dy = floor + clearance * 0.5 - coreLowest end
	local pitch, roll = pose.rootRotation.X, pose.rootRotation.Z
	local lying = legacyLying(pose.rootRotation)
	local armFrame = hrp * rootRot
	local legFrame = hrp * CFrame.Angles(pitch * lying, pose.rootRotation.Y, roll * lying)
	local heading = hrp.Rotation
	local footFlat = if headingSpace then heading else hrp.Rotation * CFrame.Angles(0, pose.rootRotation.Y, 0)
	local scale = scaleFromRoot(rig.rootHeight)
	local contacts = if pose.footLock == false then nil else pose.contact
	rig.lockClock = pose.clock
	local stepScale = pose.stepScale
	-- Lying body (heading-space clips with a floor-support weight): no sole-down foot flattening, shins rest on the
	-- floor, and after a knockdown/KO the feet relax (relaxFeet, see relaxLyingFoot).
	local lyingLegs = if headingSpace and ground > 0.5 then math.clamp((ground - 0.5) * 2, 0, 1) else 0
	local relaxFeet = lyingLegs * math.clamp(pose.relaxFeet or 0, 0, 1)
	local limbLowest = math.huge
	local armLowest, legLowest = math.huge, math.huge
	local hang = rig.footHang
	for pass = 1, 3 do
		local shift = Vector3.new(0, dy, 0)
		motors.Root.Transform = CFrame.new(rootC0.Rotation:Inverse() * shift) * rootRot
		motors.Waist.Transform = waistRot
		motors.Neck.Transform = neckRot
		local lower = lowerTorso + shift
		local upper = upperTorso + shift
		limbLowest = math.huge
		armLowest, legLowest = math.huge, math.huge
		if hang then table.clear(hang) end
		for _, chain in rig.chains do
			local effector = pose.targets[chain.target]
			if effector then
				local lowest = solveChain(rig, chain, if chain.isLeg then lower else upper, heading, if chain.isLeg then legFrame else armFrame, effector, floor, footFlat, scale, headingSpace, if contacts then contacts[chain.target] or 0 else 0,
					nil, if chain.isLeg then lyingLegs else 0, if chain.isLeg then relaxFeet else 0, stepScale)
				limbLowest = math.min(limbLowest, lowest)
				if chain.isLeg then legLowest = math.min(legLowest, lowest) else armLowest = math.min(armLowest, lowest) end
			else
				motors[chain.joint].Transform = CFrame.identity
				motors[chain.mid].Transform = CFrame.identity
				motors[chain.tip].Transform = CFrame.identity
			end
		end
		-- A lying body whose limbs would sink (an arm under the shoulder, a knee on the floor) rises onto them.
		local deficit = floor - limbLowest
		if ground > 0.3 and deficit > 0.005 then
			if pass < 3 and deficit > 0.02 then
				dy += deficit
			else
				-- Last pass: lift the solved body rigidly (re-solving would reach the limbs back down to their targets).
				dy += deficit
				motors.Root.Transform = CFrame.new(rootC0.Rotation:Inverse() * Vector3.new(0, dy, 0)) * rootRot
				limbLowest += deficit
				armLowest += deficit
				legLowest += deficit
				local up = Vector3.new(0, deficit, 0)
				for name, tip in rig.tips do rig.tips[name] = tip + up end
				break
			end
		else
			-- A standing body whose floor foot cannot reach the floor even on a straight leg hanging under the hip (the
			-- reach net's shortfall: a clip pelvis riding high for this rig's legs) comes down onto that foot — never
			-- below the core's floor clearance.
			local down = if hang and ground <= 0.3 then math.max(hang.LeftFoot or 0, hang.RightFoot or 0) else 0
			local lowered = math.max(dy - down, floor + clearance * 0.5 - coreLowest)
			if pass < 3 and down > 0.005 and lowered < dy - 0.001 then
				dy = lowered
			else
				break
			end
		end
	end
	local coreAbs = coreLowest + dy
	-- Lying settle (knockdown/KO after the floor contact): the body rests on its thickest part (a deep chest holds the
	-- hips, head and legs up). Like a real body relaxing, the spine bends: the pelvis turns about the waist and the head
	-- about the neck until each rests on the floor, and the feet come down onto it. The upper torso stays where it lies.
	local settle = pose.settle
	if settle and settle > 0 and ground > 0.5 then
		local s = math.min(settle, 1) * math.clamp((ground - 0.5) * 2, 0, 1)
		local lowerNow = rootC0 * motors.Root.Transform * motors.Root.C1:Inverse()
		local upperNow = lowerNow * motors.Waist.C0 * motors.Waist.Transform * motors.Waist.C1:Inverse()
		local headNow = upperNow * motors.Neck.C0 * motors.Neck.Transform * motors.Neck.C1:Inverse()
		local long = upperNow.Position - lowerNow.Position
		local flat = Vector3.new(long.X, 0, long.Z)
		-- Only a torso lying along the floor settles (a sit-up or a kneeling crumple keeps its raised head and hips).
		if s > 0 and flat.Magnitude > 0.2 and flat.Magnitude > 0.9 * long.Magnitude then
			local axis = flat.Unit:Cross(Vector3.yAxis)
			local rest = floor + clearance
			local function bottom(cf: CFrame, size: Vector3): number return cf.Position.Y - extentY(cf, size) end
			local function settled(cf: CFrame, size: Vector3, p: Vector3, maxAngle: number, restY: number): CFrame
				local excess = bottom(cf, size) - restY
				if excess < 0.02 then return cf end
				local function turn(a: number): CFrame return CFrame.new(p) * CFrame.fromAxisAngle(axis, a) * CFrame.new(-p) * cf end
				local a = 0
				for _ = 1, 2 do
					local here = turn(a)
					local slope = (bottom(turn(a + 0.05), size) - bottom(here, size)) / 0.05
					if math.abs(slope) < 1e-3 then break end
					a = math.clamp(a - (bottom(here, size) - restY) / slope, -maxAngle, maxAngle)
				end
				return turn(a * s)
			end
			local waistPivot = (lowerNow * motors.Waist.C0).Position
			local function settleLegs(lowerFrame: CFrame): number
				motors.Root.Transform = rootC0:Inverse() * lowerFrame * motors.Root.C1
				motors.Waist.Transform = (lowerFrame * motors.Waist.C0):Inverse() * upperNow * motors.Waist.C1
				local low = math.huge
				for _, chain in rig.chains do
					local effector = pose.targets[chain.target]
					if chain.isLeg and effector then
						low = math.min(low, solveChain(rig, chain, lowerFrame, heading, legFrame, effector, floor, footFlat, scale, headingSpace, if contacts then contacts[chain.target] or 0 else 0, s, lyingLegs, relaxFeet))
					end
				end
				return low
			end
			local newLower = settled(lowerNow, sizes.LowerTorso, waistPivot, 0.6, rest)
			local newHead = settled(headNow, sizes.Head, (upperNow * motors.Neck.C0).Position, 0.8, rest)
			motors.Neck.Transform = (upperNow * motors.Neck.C0):Inverse() * newHead * motors.Neck.C1
			legLowest = settleLegs(newLower)
			local sink = floor - legLowest
			if sink > 0.005 then
				-- Thick thighs hold the pelvis up: it turns only until they rest on the floor.
				newLower = settled(lowerNow, sizes.LowerTorso, waistPivot, 0.6, rest + sink)
				legLowest = settleLegs(newLower)
				sink = floor - legLowest
				if sink > 0.005 then
					-- Whatever remains is lifted rigidly (nothing ever ends below the floor).
					local up = Vector3.new(0, sink, 0)
					newLower += up
					upperNow += up
					newHead += up
					motors.Root.Transform = rootC0:Inverse() * newLower * motors.Root.C1
					for name, tip in rig.tips do rig.tips[name] = tip + up end
					legLowest += sink
					armLowest += sink
					dy += sink
				end
			end
			limbLowest = math.min(armLowest, legLowest)
			coreAbs = math.min(bottom(newLower, sizes.LowerTorso), bottom(upperNow, sizes.UpperTorso), bottom(newHead, sizes.Head))
		end
	end
	rig.stats.groundShift = dy
	rig.stats.lowest = math.min(coreAbs, limbLowest) - floor
end

-- Throw grips (FLThrow1 `grips`): call after BOTH fighters were applied this frame. Each active grip of this fighter's
-- role re-solves that limb so the hand centre / ankle reaches the partner's real body point (sizes differ from the
-- authored pair). Process the attacker before the defender: a defender's grip on the attacker then follows the
-- re-solved arm. Returns the number of limbs moved.
local function gripWeight(g: ClipLibrary.Grip, t: number): number
	local fade = math.max(g.fade, 1e-3)
	if t < g.from - fade or t > g.to + fade then return 0 end
	local w = 1
	if t < g.from then w = smoothstep((t - (g.from - fade)) / fade) elseif t > g.to then w = 1 - smoothstep((t - g.to) / fade) end
	return w * g.weight
end
local function swapSide(name: string): string
	if string.sub(name, 1, 4) == "Left" then return "Right" .. string.sub(name, 5) end
	if string.sub(name, 1, 5) == "Right" then return "Left" .. string.sub(name, 6) end
	return name
end
function MotionPlayer.applyGrips(rig: RigInfo, pose: Pose, view: FighterView, frame: any?, slot: number, partner: RigInfo, floorY: number): number
	local throw = view.throw
	if type(throw) ~= "table" or throw.broken == true or type(throw.move) ~= "string" or pose.space ~= "heading" then return 0 end
	local defender = throw.role == "Defender"
	local characterId = if type(view.characterId) == "string" then view.characterId else ""
	local attackerId = if defender then (opponentId(frame, slot) or characterId) else characterId
	local tc = ClipLibrary.forThrow(attackerId, throw.move)
	if not tc or not tc.grips then return 0 end
	local track = if defender then tc.defender else tc.attacker
	local duration = if type(throw.duration) == "number" then throw.duration else 48
	local impactFrame = if type(throw.impactFrame) == "number" then throw.impactFrame else duration * 0.6
	local t = MotionPlayer.throwTime(tc.impact, if type(throw.frame) == "number" then throw.frame else 0, impactFrame, duration) * track.duration
	local role = if defender then "Defender" else "Attacker"
	local rootPart = rig.motors.Root.Part0
	if not rootPart then return 0 end
	local moved = 0
	for _, g in tc.grips do
		if g.role == role then
			local w = gripWeight(g, t)
			if w > 0 then
				local limb, partName, at = g.limb, g.part, g.at
				if track.mirror then limb, partName, at = swapSide(limb), swapSide(partName), Vector3.new(-at.X, at.Y, at.Z) end
				local chain = rig.chains[if limb == "LeftHand" then "LeftArm" elseif limb == "RightHand" then "RightArm" elseif limb == "LeftFoot" then "LeftLeg" else "RightLeg"]
				local effector = pose.targets[limb]
				local partCF = partWorld(partner, partName)
				local part = partner.parts[partName]
				if chain and effector and partCF and part then
					local point = partCF * Vector3.new(at.X * part.Size.X * 0.5, at.Y * part.Size.Y * 0.5, at.Z * part.Size.Z * 0.5)
					local motors = rig.motors
					local hrp = (rootPart :: BasePart).CFrame
					local lower = hrp * motors.Root.C0 * motors.Root.Transform * motors.Root.C1:Inverse()
					local parent = if chain.isLeg then lower else lower * motors.Waist.C0 * motors.Waist.Transform * motors.Waist.C1:Inverse()
					local grip = table.clone(effector)
					grip.gripWorld, grip.gripWeight = point, w
					local heading = hrp.Rotation
					solveChain(rig, chain, parent, heading, heading, grip, floorY, heading, scaleFromRoot(rig.rootHeight), true, 0, nil)
					moved += 1
				end
			end
		end
	end
	return moved
end

-- Standing heights above the floor of this fighter's head centre (High), chest (Mid) and knees (Low) in its displayed
-- stance: where an opponent's contact aim lands on it. Poses the rig once (the caller re-poses it on its next update);
-- measured through the joint chain, so it is exact the same frame. Cache the result per rig.
function MotionPlayer.standingHeights(rig: RigInfo, characterId: string): { [string]: number }
	local motors = rig.motors
	local rootPart = motors.Root.Part0 :: BasePart
	local pose = MotionPlayer.namedPose(characterId, "Stance", 0, rig.rootHeight, rig.legLength)
	MotionPlayer.apply(rig, pose, rootPart.CFrame.Position.Y - rig.rootHeight - pose.rootOffset.Y)
	local function through(frame: CFrame, motor: Motor6D): CFrame return frame * motor.C0 * motor.Transform * motor.C1:Inverse() end
	local hrp = rootPart.CFrame
	local lower = through(hrp, motors.Root)
	local upper = through(lower, motors.Waist)
	local head = through(upper, motors.Neck)
	local kneeL = (through(lower, motors.LeftHip) * motors.LeftKnee.C0).Position
	local kneeR = (through(lower, motors.RightHip) * motors.RightKnee.C0).Position
	local base = hrp.Position.Y - rig.rootHeight - pose.rootOffset.Y
	-- Centre of the head mesh, centre of the chest (UpperTorso), knee joints for low hits.
	return {
		High = head.Position.Y - base,
		Mid = upper.Position.Y - base,
		Low = (kneeL.Y + kneeR.Y) * 0.5 - base,
	}
end

function MotionPlayer.reset(slot: number?)
	if slot then slots[slot] = nil else table.clear(slots) end
end

function MotionPlayer._debugSampleKeys(keys: { Keyframe }, normalized: number): Pose
	return sampleKeys(keys, normalized)
end

function MotionPlayer._slotState(slot: number): any
	return slots[slot]
end

function MotionPlayer.measureTargetError(_rig: RigInfo, pose: Pose, _rootFrame: CFrame): { [string]: number }
	local errors: { [string]: number } = {}
	for name in pose.targets do errors[name] = 0 end
	return errors
end

return MotionPlayer
