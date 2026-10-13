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
local BodyShape = require(MotionFolder.BodyShape)
local Cinematic = require(MotionFolder.Cinematic)

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
	-- real: the slot's real-time clock (advances in hitstop too; paces transitions that must not freeze).
	real: number?,
	-- selfClear: the arms may be pushed out of the own body (standing guard, movement, block and hit reactions; not
	-- attacks, throws, falls or round-end poses — see MotionPlayer.clearArms).
	selfClear: boolean?,
	-- cut: the pose starts a new round (no continuity with the previous frame: IK bend directions start over).
	cut: boolean?,
	-- pushBack: how far (studs) the attack's body is held back so its strike rests on the opponent (ContactPushBack).
	pushBack: number?,
	-- lyingFrames: the knockdown smoother is on for this pose (frames since the last shown one); apply limits every
	-- part's turn relative to the pelvis (MotionPlayer.LyingJointDeg).
	lyingFrames: number?,
	-- defenderClear: a thrown defender (the self clearance keeps its gloves out of its own body).
	defenderClear: boolean?,
	-- ankleRange: a getup clip's pose (unplanted feet keep inside the ankle's range, MotionPlayer.GetupAnkleRange).
	ankleRange: boolean?,
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
	-- Clock of the shown frame (real time; MotionPlayer.apply), paces the IK pole continuity.
	frameClock: number?,
	-- Contact aim residual (studs) per striking limb on the last startup/active frame, added in the recovery.
	aimResidual: { [string]: { r: number, clock: number? } }?,
	-- Strike contact retraction (fraction of the reach) per limb on the latest frame (MotionPlayer.applyContact).
	contactHold: { [string]: { s: number, clock: number? } }?,
	-- Deepest striking limb still inside the partner after the latest contact pass (studs beyond ContactAllowance).
	contactResidual: number?,
	-- Every part's rotation relative to the pelvis in the latest apply and its clock (MotionPlayer.LyingJointDeg).
	lyingRel: { [string]: any }?,
	-- Leg treatment of a lying body (0 standing .. 1 lying) on the latest frame and its real time (ramped).
	lyingLegs: { v: number, t: number }?,
	-- Relaxed-feet weight of a lying body on the latest frame and its real time (ramped, MotionPlayer.RelaxFeetRamp).
	relaxFeet: { v: number, t: number }?,
	-- Self-clearance push of each hand (heading space) on the latest frame (MotionPlayer.clearArms; `t` = its time).
	selfPush: { [string]: any }?,
	-- The same for the forced pass after a contact retraction, and the arms that retraction drew back this frame.
	selfPushForced: { [string]: any }?,
	-- The throw grips' clearance pass (a defender's gripping hands, MotionPlayer.presentFrame) and the hands the latest
	-- grip pass re-solved.
	selfPushGrip: { [string]: any }?,
	gripMoved: { [string]: boolean }?,
	contactMoved: { [string]: boolean }?,
	-- Body shapes for contact checks (Motion.BodyShape.of caches them here).
	bodyShape: any?,
	-- Optional per-frame solver diagnostics (tools: set to a table).
	debug: { [string]: any }?,
}
export type ResolvedMove = { keyframes: { Keyframe }, move: any, params: Library.AnimParams, timing: { startup: number, active: number, recovery: number }, source: string, clip: ClipLibrary.Clip? }

local MotionPlayer = {}
MotionPlayer.GroundClearance = 0.03
-- Fighter states whose arms the self clearance may push out of the own body (MotionPlayer.clearArms).
local SELF_CLEAR_STATES = {
	Idle = true, Guard = true, Walk = true, Backwalk = true, Crouch = true, CrouchBlock = true, Block = true,
	Blockstun = true, Dash = true, Backdash = true, Sidestep = true, Step = true, Hitstun = true, Stagger = true,
}
-- Per-fighter guard trims (studs, heading space: +X right, +Y up, +Z toward the opponent) added to the hand targets of
-- the states that hold the guard. Kael: the rear (right) glove, between the player's own fight camera and his profile
-- (the camera sees the local fighter's right side), sits lower, its top at the cheekbone instead of the brow, so his
-- profile eye reads.
MotionPlayer.GuardTrim = { Kael = { RightHand = Vector3.new(0, -0.1, 0) } } :: { [string]: { [string]: Vector3 } }
local GUARD_STATES = {
	Idle = true, Guard = true, Walk = true, Backwalk = true, Crouch = true, CrouchBlock = true, Block = true,
	Blockstun = true, Dash = true, Backdash = true, Sidestep = true, Step = true,
}

type SlotState = {
	pose: Pose?, key: string?, clock: number, lastNow: number?, keyStarted: number,
	fadeFrom: Pose?, fadeStart: number, fadeDur: number,
	travel: number, lastPos: Vector3?, roundOverSince: number?,
	-- Step-in tracking of the current attack (sim advance designed vs applied since its first frame).
	stepMove: string?, stepFrame: number?, stepPos: Vector3?, stepApplied: number?, stepDesigned: number?,
	-- real: wall time (runs during hitstop, unlike clock); fadeReal: the current crossfade runs on real time (an impact
	-- that starts during the hitstop freeze); hitStamp/hitSeen: the last hit seen; glide: world offset (studs, XZ) that
	-- holds the body where it was when the sim pushed it on a hit, released over glideDur of animation time.
	real: number, fadeReal: boolean?, fadeLinear: boolean?, hitStamp: string?, hitSeen: boolean?, glide: Vector3?, glideStart: number?, glideDur: number?,
	absorbUntil: number?, timeKey: string?, resetSnapUntil: number?, entryPos: Vector3?, entryFrame: number?,
	-- Point-blank spacing (MotionPlayer.LungeSpacing): the attack's lunge scale and the clock it was last set at.
	lungeK: number?, lungeAt: number?,
	-- Contact push-back of the current attack (studs) and the clock it was last set at (MotionPlayer.ContactPushBack).
	pushBack: number?, pushAt: number?, pushGrow: number?,
	-- Knockdown smoothing (MotionPlayer.LyingSmooth): the last shown pose in body frames, its real time, and until when
	-- the stance after a getup stays smoothed.
	lyingPrev: any?, lyingAt: number?, lyingTail: number?,
}
local slots: { [number]: SlotState } = {}
local FINAL_HIT_HOLD = 1.1
-- A sim position jump larger than this in one frame is a round reset (fighters back on their marks), never movement
-- (dashes travel ~0.2 studs per frame, throw pushes 0.6): the pose cuts instead of crossfading.
MotionPlayer.TeleportDistance = 3
-- Real-time window after a hit or a throw exit in which the sim's push is absorbed into the glide (see sample).
MotionPlayer.PushAbsorbWindow = 2.5 / 60
-- Animation seconds of the defender's glide onto its cinematic spot when the Ultimate lands (the sim puts it endDistance
-- in front of the attacker on the hit frame). The catch is authored against that spot: held at its pre-hit spot for a
-- normal push glide (up to 0.2 s), the attacker's catch strike went through its chest and it folded over his arm
-- (round 6 follow-up). Long enough not to read as a pop.
MotionPlayer.UltimateEntryGlide = 0.1
-- Real-time window after a round reset in which the body is shown at the newest entry's position (see sample).
MotionPlayer.ResetSnapWindow = 0.5
-- Impact entries (a reaction, knockdown, launch, KO or throw that starts on a hit): the crossfade from whatever the
-- fighter was doing runs on real time, so it plays during the hitstop freeze; its length follows how far the pose has to
-- travel (ImpactDegPerFrame of joint turn per frame), between ImpactFadeMin and ImpactFadeMax seconds.
MotionPlayer.ImpactFadeMin = 4 / 60
MotionPlayer.ImpactFadeMax = 12 / 60
MotionPlayer.ImpactDegPerFrame = 8
-- Other crossfades stretch the same way (never shorter than the state asks for, at most CrossfadeMax).
MotionPlayer.CrossfadeDegPerFrame = 9
MotionPlayer.CrossfadeMax = 0.3
MotionPlayer.GetupCrossfadeMax = 0.1
-- An attack's fade-in stretches at most MoveFadeMax (and always ends before its first active frame): a longer blend from
-- the guard into a wind-up dragged the hand target through the chest and right past the shoulder, where the folded arm
-- spun 170+ degrees in one frame (Lumi PalmHeel); 8 frames still spread the guard-to-chamber turn.
MotionPlayer.MoveFadeMax = 8 / 60
local resolvedCache: { [string]: ResolvedMove } = {}
local LEGACY_TO_ROSTER: { [string]: string } = { Jab = "Jab", Heavy = "Cross", Kick = "Roundhouse", LeadKick = "FrontKick", DuckJab = "DuckJab", BodyPunch = "BodyBlow", ShinTap = "ShinKick", Sweep = "LowSweep", Rise = "RisingUppercut" }
local DEFAULT_IDS = { "Kael", "Sierra" }
-- Leg length (hip to sole) relative to RootHeight on the generated fighter templates (measured 0.755-0.80).
local LEG_PER_ROOT = 0.775
MotionPlayer.LEG_PER_ROOT = LEG_PER_ROOT

local function finite(n: number): boolean return n == n and math.abs(n) < math.huge end
local function finiteVector(v: Vector3): boolean return finite(v.X) and finite(v.Y) and finite(v.Z) end
local function copyEffector(effector: Effector): Effector return { pos = effector.pos, pole = effector.pole, orient = effector.orient, weight = effector.weight, rot = effector.rot, aimWorldY = effector.aimWorldY, aimWeight = effector.aimWeight, aimPhase = effector.aimPhase, sole = effector.sole } end
local function scaleFromRoot(rootHeight: number?): number return math.max(0.75, math.min(1.35, (rootHeight or 3) / 3)) end
local function characterRootHeight(characterId: string): number return (Roster.get(characterId).stats.height or 6) * 0.5 end
local function libVector(v: Vector3): Vector3 return Vector3.new(v.X, v.Y, -v.Z) end
local function eulerOf(cf: CFrame): Vector3 local x, y, z = cf:ToEulerAnglesXYZ(); return Vector3.new(x, y, z) end
local function anglesOf(v: Vector3): CFrame return CFrame.Angles(v.X, v.Y, v.Z) end
local function smoothstep(x: number): number local t = math.clamp(x, 0, 1); return t * t * (3 - 2 * t) end
MotionPlayer.scaleFromRoot = scaleFromRoot

local function newSlot(clock: number): SlotState
	return { pose = nil, key = nil, clock = clock, lastNow = nil, keyStarted = 0, fadeFrom = nil, fadeStart = 0, fadeDur = 0, travel = 0, lastPos = nil, roundOverSince = nil, real = clock }
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

-- Arm targets blend around the shoulder (direction slerp, reach lerp): a straight-line blend between a hand behind the
-- body and one in front swept the hand past the shoulder and whipped the arm 140 degrees in one frame. Legs keep the
-- straight-line blend (a foot path on an arc around the hip would dip into the floor).
local SHOULDER_PIVOT = { LeftHand = Vector3.new(-0.5, 1.1, 0), RightHand = Vector3.new(0.5, 1.1, 0) }
local function blendHandPos(name: string, a: Vector3, b: Vector3, alpha: number): Vector3
	local pivot = SHOULDER_PIVOT[name]
	if not pivot then return a:Lerp(b, alpha) end
	local pa, pb = a - pivot, b - pivot
	local la, lb = pa.Magnitude, pb.Magnitude
	if la < 1e-3 or lb < 1e-3 then return a:Lerp(b, alpha) end
	local ua, ub = pa / la, pb / lb
	local axis = ua:Cross(ub)
	local ang = math.acos(math.clamp(ua:Dot(ub), -1, 1))
	if ang < 1e-3 or axis.Magnitude < 1e-4 then return a:Lerp(b, alpha) end
	return pivot + CFrame.fromAxisAngle(axis.Unit, ang * alpha):VectorToWorldSpace(ua) * (la + (lb - la) * alpha)
end

local function blendEffector(a: Effector, b: Effector, alpha: number, name: string?, chests: { CFrame }?): Effector
	local rot: CFrame? = nil
	local ra, rb = a.rot, b.rot
	if chests and name and SHOULDER_PIVOT[name] then
		-- Chest-frame blend (MotionPlayer.ChestBlend): the hand's reach from the shoulder, its pole and its rotation are
		-- blended in each pose's chest frame and carried by the blended chest.
		local ca, cb, cm = chests[1], chests[2], chests[3]
		local pivot = SHOULDER_PIVOT[name]
		local va = ca:VectorToObjectSpace(libVector(a.pos - pivot))
		local vb = cb:VectorToObjectSpace(libVector(b.pos - pivot))
		local pos = pivot + libVector(cm:VectorToWorldSpace(blendHandPos(name, pivot + va, pivot + vb, alpha) - pivot))
		local pa = ca:VectorToObjectSpace(libVector(a.pole or Vector3.yAxis))
		local pb = cb:VectorToObjectSpace(libVector(b.pole or a.pole or Vector3.yAxis))
		local pole = libVector(cm:VectorToWorldSpace(pa:Lerp(pb, alpha)))
		if ra and rb then rot = cm * (ca:Inverse() * ra):Lerp(cb:Inverse() * rb, alpha) elseif alpha >= 0.5 then rot = rb else rot = ra end
		return {
			pos = pos, pole = pole,
			orient = a.orient, weight = (a.weight or 1) + ((b.weight or 1) - (a.weight or 1)) * alpha, rot = rot,
			aimWorldY = b.aimWorldY or a.aimWorldY,
			aimWeight = if a.aimWeight or b.aimWeight then (a.aimWeight or 0) + ((b.aimWeight or 0) - (a.aimWeight or 0)) * alpha else nil,
			aimPhase = b.aimPhase or a.aimPhase,
			sole = if a.sole and b.sole then a.sole + (b.sole - a.sole) * alpha else nil,
		}
	end
	if ra and rb then rot = ra:Lerp(rb, alpha) elseif alpha >= 0.5 then rot = rb else rot = ra end
	return {
		pos = if name then blendHandPos(name, a.pos, b.pos, alpha) else a.pos:Lerp(b.pos, alpha),
		pole = (a.pole or Vector3.yAxis):Lerp(b.pole or a.pole or Vector3.yAxis, alpha),
		orient = a.orient, weight = (a.weight or 1) + ((b.weight or 1) - (a.weight or 1)) * alpha, rot = rot,
		aimWorldY = b.aimWorldY or a.aimWorldY,
		aimWeight = if a.aimWeight or b.aimWeight then (a.aimWeight or 0) + ((b.aimWeight or 0) - (a.aimWeight or 0)) * alpha else nil,
		aimPhase = b.aimPhase or a.aimPhase,
		sole = if a.sole and b.sole then a.sole + (b.sole - a.sole) * alpha else nil,
	}
end

-- Blends two heading-space poses (rotations slerp). Round 5 (ChestBlend): hands blend in the chest frames of the two
-- poses — a crossfade that turns the body (a thrown defender squaring up from a bladed stance, a getup rising) carried
-- the heading-space hand targets straight through the turning chest (up to 0.3 studs inside it).
MotionPlayer.ChestBlend = true
local function blendPose(a: Pose, b: Pose, alpha: number): Pose
	if alpha <= 0 then return a end
	if alpha >= 1 then return b end
	local rootRot = (a.rootRot or anglesOf(a.rootRotation)):Lerp(b.rootRot or anglesOf(b.rootRotation), alpha)
	local waistRot = (a.waistRot or anglesOf(a.waist)):Lerp(b.waistRot or anglesOf(b.waist), alpha)
	local chests: { CFrame }? = nil
	if MotionPlayer.ChestBlend then
		chests = {
			(a.rootRot or anglesOf(a.rootRotation)) * (a.waistRot or anglesOf(a.waist)),
			(b.rootRot or anglesOf(b.rootRotation)) * (b.waistRot or anglesOf(b.waist)),
			rootRot * waistRot,
		}
	end
	local targets: { [string]: Effector } = {}
	for name, ea in a.targets do
		local eb = b.targets[name]
		targets[name] = if eb then blendEffector(ea, eb, alpha, name, chests) else copyEffector(ea)
	end
	for name, eb in b.targets do if not targets[name] then targets[name] = copyEffector(eb) end end
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
		-- A step-in's cap applies through its fade-in (blending in from an uncapped 1 lifted the stepping foot in place)
		-- and lets go over a fade-out.
		stepScale = if a.stepScale and b.stepScale then a.stepScale + (b.stepScale - a.stepScale) * alpha
			elseif b.stepScale then b.stepScale
			elseif a.stepScale then a.stepScale + (1 - a.stepScale) * alpha
			else nil,
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

-- Ultimate cinematic (round 6, Motion.Cinematic): this role's track of the attacker's Ultimate clip, else keyframes.
local function ultimatePose(view: FighterView, frame: any?, slot: number, characterId: string, scale: number, legLength: number): Pose
	local defender = view.throw.role == "Defender"
	local attackerId = if defender then (opponentId(frame, slot) or characterId) else characterId
	local other = if frame and type(frame.fighters) == "table" then frame.fighters[if slot == 1 then 2 else 1] else nil
	local attackerLeg = if defender and type(other) == "table" and type(other.legLength) == "number" then other.legLength else legLength
	local pose = Cinematic.samplePose(view, { attackerId = attackerId, actual = opponentDistance(view, frame, slot), attackerLeg = attackerLeg }, scale, legLength)
	if pose then return pose end
	local now = if frame and type(frame.now) == "number" then frame.now else 0
	return toHeading(poseFromKey(Cinematic.fallbackKeyframe(view, { attackerId = attackerId }, characterId, scale, States, now)), scale)
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
-- Round 6 (R4 motion QA): through the startup and the active frames the limb is pulled to the target height as
-- before; in the recovery the correction measured on the last active frame is ADDED to the clip's own motion while it
-- releases, instead of pinning the limb toward the target height (a high kick whose clip drops the foot to the floor
-- in four frames used to hang at head height and then land 3 studs in one frame).
local function aimTargetY(pose: Pose, limb: string, height: string, scale: number, rootHeight: number, targetRootHeight: number?): number
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
	return targetY
end

-- The clip sampled on the move's last active frame (per clip, rig size and target), for the recovery correction.
local aimEndCache: { [any]: { [string]: number } } = setmetatable({}, { __mode = "k" }) :: any
local function recoveryCorrection(clip: ClipLibrary.Clip, resolved: ResolvedMove, limb: string, height: string, scale: number, legLength: number, rootHeight: number, targetRootHeight: number?): number
	local per = aimEndCache[clip]
	if not per then
		per = {}
		aimEndCache[clip] = per
	end
	local key = string.format("%s:%s:%.4f:%.4f:%.4f:%.4f", limb, height, scale, legLength, rootHeight, targetRootHeight or -1)
	local cached = per[key]
	if cached then return cached end
	local timing = resolved.timing
	local t = ClipPlayer.moveTime(clip, timing, timing.startup + timing.active)
	local endPose = ClipPlayer.sample(clip, t, { mirror = clip.mirror, legLength = legLength, scale = scale })
	local e = endPose.targets[limb]
	local c = if e then aimTargetY(endPose, limb, height, scale, rootHeight, targetRootHeight) - e.pos.Y else 0
	per[key] = c
	return c
end

local function aimContact(pose: Pose, clip: ClipLibrary.Clip, resolved: ResolvedMove, frame: number, scale: number, rootHeight: number, targetRootHeight: number?, targetHeights: { [string]: number }?, legLength: number?)
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
	local phase
	if frame <= first then
		w, phase = smoothstep((frame - first * 0.5) / math.max(first * 0.5, 1)), if frame < first then 1 else 2
	elseif frame <= timing.startup + timing.active then
		w, phase = 1, 2
	else
		w, phase = 1 - smoothstep((frame - timing.startup - timing.active) / math.max(timing.recovery * 0.4, 1)), 3
	end
	w *= if type(tags.aimWeight) == "number" then tags.aimWeight else 1
	if w <= 0 then return end
	if phase == 3 and MotionPlayer.AimAdditiveRecovery then
		-- The correction measured at the end of the active window, released with the same weight.
		local c = recoveryCorrection(clip, resolved, limb :: string, height, scale, legLength or rootHeight * LEG_PER_ROOT, rootHeight, targetRootHeight)
		e.pos = Vector3.new(e.pos.X, e.pos.Y + c * w, e.pos.Z)
	else
		local targetY = aimTargetY(pose, limb :: string, height, scale, rootHeight, targetRootHeight)
		e.pos = Vector3.new(e.pos.X, e.pos.Y + (targetY - e.pos.Y) * w, e.pos.Z)
	end
	-- The aim weight marks the striking limb either way (the reach net leaves an aimed foot to the IK clamp toward its
	-- target). Exact layer: with the opponent's measured standing heights, MotionPlayer.apply moves the IK goal to that
	-- world height through the real posed shoulder/hip of this rig (the reference estimate above is only a first guess).
	e.aimWeight = w
	e.aimPhase = phase
	local worldY = targetHeights and targetHeights[height]
	if type(worldY) == "number" then
		e.aimWorldY = worldY
	end
end
MotionPlayer.AimAdditiveRecovery = true

type Request = States.MotionRequest
-- Seconds over which a falling body's floor weight and its settle (pelvis, head, feet relaxing) ramp in from the clip's
-- floor contact.
local GROUND_RAMP = 0.12
local SETTLE_RAMP = 0.08

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
				-- Lying states: from the clip's contact (the body reaching the floor) on, the body rests on the floor. The floor
				-- weight ramps in over GROUND_RAMP (a jump to half weight at the contact frame used to flip the lying feet
				-- and elbows in one frame).
				local c = clip.contact * clip.duration
				if t >= c then pose.ground = math.max(pose.ground or 0, req.ground * smoothstep((t - c) / GROUND_RAMP)) end
				-- ...and relaxes onto it (pelvis, head and feet settle with the impact; see MotionPlayer.apply).
				if req.settle == true then
					pose.settle = smoothstep((t - c) / SETTLE_RAMP)
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

-- Knockdown smoothing (round 5). From the frame a fighter reaches the floor (Landing, KO; a getup) to LyingTail seconds
-- into the stance after a getup, the shown pose changes by at most a few degrees per frame: the pelvis yaws (about the
-- vertical) and rolls (about its own spine) at most LyingYawRoll and pitches (sit-ups, back rolls, falls) at most
-- LyingPitch; each hand and foot keeps its place relative to the chest / pelvis and moves at most LyingLimb (direction)
-- and LyingReach (extension, share of the reference limb) per frame, its elbow/knee pole LyingPole, the waist and neck
-- LyingSpine, the feet LyingFoot. Limbs follow the body: a clamped pelvis carries them along instead of leaving them
-- where the clip put them in heading space. Getup clips and the crossfades between them (a fall into a getup, a roll's
-- first frame, the getup into the guard) used to whip arms and legs up to 180 degrees in a frame. Real time (hitstop
-- impact fades keep moving); a round reset cuts.
MotionPlayer.LyingSmooth = true
MotionPlayer.LyingYawRoll = 12
MotionPlayer.LyingPitch = 28
MotionPlayer.LyingLimb = 18
MotionPlayer.LyingReach = 0.08
MotionPlayer.LyingPole = 22
MotionPlayer.LyingSpine = 14
MotionPlayer.LyingFoot = 22
MotionPlayer.LyingTail = 0.6
local LYING_SMOOTH_STATES = { Landing = true, Getup = true, KO = true, Knockdown = true }
local LYING_TAIL_STATES = { Idle = true, Guard = true, Walk = true, Backwalk = true, Crouch = true }
local ARM_PIVOTS = { LeftHand = Vector3.new(-0.5, 1.1, 0), RightHand = Vector3.new(0.5, 1.1, 0) }
local LEG_PIVOTS = { LeftFoot = Vector3.new(-0.3, -0.35, 0), RightFoot = Vector3.new(0.3, -0.35, 0) }
type BodyLimb = { dir: Vector3, len: number, pole: Vector3?, rot: CFrame? }
type BodyFrame = { root: CFrame, waist: CFrame, neck: CFrame, limbs: { [string]: BodyLimb } }
local function rotOf(rot: CFrame?, euler: Vector3?): CFrame
	if rot then return rot.Rotation end
	return anglesOf(euler or Vector3.zero)
end
-- A pose's limbs in its own body frames (hands in the chest frame, feet in the pelvis frame; Roblox axes).
local function bodyFrame(pose: Pose, scale: number): BodyFrame
	local root = rotOf(pose.rootRot, pose.rootRotation)
	local waist = rotOf(pose.waistRot, pose.waist)
	local neck = rotOf(pose.neckRot, pose.neck)
	local chest = root * waist
	local limbs = {}
	for limb, e in pose.targets do
		local pivot = ARM_PIVOTS[limb] or LEG_PIVOTS[limb]
		if pivot then
			local frame = if ARM_PIVOTS[limb] then chest else root
			local v = frame:VectorToObjectSpace(libVector(e.pos - pivot * scale))
			local len = v.Magnitude
			if len > 1e-4 then
				limbs[limb] = {
					dir = v / len, len = len,
					pole = if e.pole and e.pole.Magnitude > 1e-4 then frame:VectorToObjectSpace(libVector(e.pole)).Unit else nil,
					rot = if LEG_PIVOTS[limb] and e.rot then root:Inverse() * (e.rot :: CFrame).Rotation else nil,
				}
			end
		end
	end
	return { root = root, waist = waist, neck = neck, limbs = limbs }
end
local function clampRotation(prev: CFrame, new: CFrame, maxDeg: number): CFrame
	local axis, ang = (new * prev:Inverse()):ToAxisAngle()
	local maxA = math.rad(maxDeg)
	if ang <= maxA or ang ~= ang then return new end
	return CFrame.fromAxisAngle(axis, maxA) * prev
end
local function clampDirection(prev: Vector3, new: Vector3, maxDeg: number): Vector3
	local ang = math.acos(math.clamp(prev:Dot(new), -1, 1))
	local maxA = math.rad(maxDeg)
	if ang <= maxA then return new end
	local axis = prev:Cross(new)
	if axis.Magnitude < 1e-6 then
		axis = prev:Cross(Vector3.xAxis)
		if axis.Magnitude < 1e-6 then axis = prev:Cross(Vector3.yAxis) end
	end
	return CFrame.fromAxisAngle(axis.Unit, maxA):VectorToWorldSpace(prev)
end
-- The pelvis step split into its yaw/roll part (the plane of the vertical and the spine) and its pitch part.
local function clampPelvis(prev: CFrame, new: CFrame, yawRollDeg: number, pitchDeg: number): CFrame
	local axis, ang = (new * prev:Inverse()):ToAxisAngle()
	if ang < 1e-6 or ang ~= ang then return new end
	local w = axis * ang
	local spine = prev.UpVector
	local ys = Vector3.yAxis * w.Y
	local s2 = spine - Vector3.yAxis * spine.Y
	if s2.Magnitude > 0.05 then
		local e2 = s2.Unit
		ys += e2 * w:Dot(e2)
	end
	local pp = w - ys
	local maxYS, maxP = math.rad(yawRollDeg), math.rad(pitchDeg)
	if ys.Magnitude <= maxYS and pp.Magnitude <= maxP then return new end
	if ys.Magnitude > maxYS then ys *= maxYS / ys.Magnitude end
	if pp.Magnitude > maxP then pp *= maxP / pp.Magnitude end
	local w2 = ys + pp
	if w2.Magnitude < 1e-6 then return prev end
	return CFrame.fromAxisAngle(w2.Unit, w2.Magnitude) * prev
end
-- How a shown pose lies (Motion.States RequestContext.shownLie): nil standing; else face up/down and the head toward or away
-- from the opponent (heading space: -Z toward it).
local function lieOf(pose: Pose?): string?
	if not pose then return nil end
	local r = rotOf(pose.rootRot, pose.rootRotation)
	local up = r.UpVector
	if math.abs(up.Y) > 0.6 then return nil end
	return (if r.LookVector.Y > 0 then "Supine" else "Prone") .. (if up.Z > 0 then "Away" else "Toward")
end
-- A limb's own frame from its direction and pole (up along the limb toward its root, forward toward the pole).
local function limbFrame(dir: Vector3, pole: Vector3?): CFrame?
	if not pole then return nil end
	local up = -dir
	local fwd = pole - up * pole:Dot(up)
	if fwd.Magnitude < 1e-3 then return nil end
	local back = -fwd.Unit
	return CFrame.fromMatrix(Vector3.zero, up:Cross(back), up, back)
end
local function lyingSmooth(pose: Pose, prev: BodyFrame, frames: number, scale: number): Pose
	local new = bodyFrame(pose, scale)
	local root = clampPelvis(prev.root, new.root, MotionPlayer.LyingYawRoll * frames, MotionPlayer.LyingPitch * frames)
	local waist = clampRotation(prev.waist, new.waist, MotionPlayer.LyingSpine * frames)
	local neck = clampRotation(prev.neck, new.neck, MotionPlayer.LyingSpine * frames)
	local chest = root * waist
	local out = table.clone(pose)
	out.rootRot, out.waistRot, out.neckRot = root, waist, neck
	out.rootRotation, out.waist, out.neck = eulerOf(root), eulerOf(waist), eulerOf(neck)
	local targets = table.clone(pose.targets)
	for limb, info in new.limbs do
		local before = prev.limbs[limb]
		local e = targets[limb]
		if before and e then
			local isArm = ARM_PIVOTS[limb] ~= nil
			local reach = (if isArm then 1.95 else 2.75) * scale
			local dir = clampDirection(before.dir, info.dir, MotionPlayer.LyingLimb * frames)
			local step = MotionPlayer.LyingReach * reach * frames
			local len = math.clamp(info.len, before.len - step, before.len + step)
			local frame = if isArm then chest else root
			local pivot = (ARM_PIVOTS[limb] or LEG_PIVOTS[limb]) :: Vector3
			local copy = table.clone(e)
			copy.pos = pivot * scale + libVector(frame:VectorToWorldSpace(dir * len))
			local poleC: Vector3? = nil
			if info.pole and before.pole then
				poleC = clampDirection(before.pole, info.pole, MotionPlayer.LyingPole * frames)
			elseif info.pole then
				poleC = info.pole
			end
			if poleC then copy.pole = libVector(frame:VectorToWorldSpace(poleC)) end
			if info.rot and before.rot then
				-- The foot turns relative to its leg (a frame from the leg's direction and pole), so a clamped leg carries the
				-- foot along: clamped separately, a back roll's legs swinging overhead left the foot 180 degrees off the shin.
				local fPrev, fNew, fNow = limbFrame(before.dir, before.pole), limbFrame(info.dir, info.pole), limbFrame(dir, poleC)
				if fPrev and fNew and fNow then
					local rel = clampRotation(fPrev:Inverse() * before.rot, fNew:Inverse() * info.rot, MotionPlayer.LyingFoot * frames)
					copy.rot = root * (fNow * rel)
				else
					copy.rot = root * clampRotation(before.rot, info.rot, MotionPlayer.LyingFoot * frames)
				end
			elseif info.rot then
				copy.rot = root * info.rot
			end
			targets[limb] = copy
		end
	end
	out.targets = targets
	return out
end

local function validatePose(pose: Pose)
	if not finiteVector(pose.rootOffset) or not finiteVector(pose.rootRotation) or not finiteVector(pose.waist) or not finiteVector(pose.neck) then error("MotionPlayer produced a non-finite body pose") end
	for name, target in pose.targets do if not finiteVector(target.pos) or (target.pole and not finiteVector(target.pole)) then error("MotionPlayer produced non-finite target " .. name) end end
end

local function advanceClock(st: SlotState, frame: any?, view: FighterView, frozen: boolean?)
	local now = if frame and type(frame.now) == "number" then frame.now else nil
	local dt = 0
	if frame and type(frame.dt) == "number" then
		dt = frame.dt
	elseif now and st.lastNow then
		dt = now - st.lastNow
	end
	if now then st.lastNow = now end
	dt = math.clamp(dt, 0, 0.1)
	-- Real time always runs (impact fades play during the hitstop freeze); animation time stops in hitstop.
	st.real += dt
	if not frozen then st.clock += dt end
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

-- Point-blank spacing (round 5). Attack clips carry their own body lunge (the pelvis travels toward the contact on top
-- of the sim's `advance`), authored for the move's designed range. Against an opponent standing closer (keepApart holds
-- the bodies at Separation; mid range), that lunge carried the whole body into the opponent and no limb retraction
-- could clear it (Rhys Jab 0.57 studs deep, a teep's hip inside the opponent's belly). The clip's forward pelvis travel
-- from its first frame is scaled down by the distance missing at the predicted contact (the sim distance minus the
-- advance still to come, never below Separation; the move's designed contact distance is its `range`), so the body
-- stops where the strike can land; the contact pass (applyContact) then bends the limb onto the surface. The contact
-- frame and the clip's timing are unchanged. The scale changes at most LungeRate per frame.
MotionPlayer.LungeSpacing = true
MotionPlayer.LungeRate = 0.15
local function lungeSpacing(pose: Pose, clip: ClipLibrary.Clip, resolved: ResolvedMove, view: FighterView, frame: any?, slot: number, st: SlotState, legLength: number, config: any)
	if not MotionPlayer.LungeSpacing then return end
	local move = resolved.move
	if type(move) ~= "table" or move.height == "Throw" then return end
	local holder = clip :: any
	local cache = holder._lunge
	if cache == nil then
		-- The clip's largest forward pelvis offset from the sim root (a lunge can peak after the contact and carry the body
		-- on into the recovery; string follow-ups start where the previous hit left the body).
		local zMax = 0
		for i = 0, 24 do
			zMax = math.max(zMax, ClipPlayer.sample(clip, clip.duration * i / 24, { legLength = 1, scale = 1 }).rootOffset.Z)
		end
		cache = { zMax = zMax }
		holder._lunge = cache
	end
	local lunge = cache.zMax * legLength
	local target = 1
	local dist = opponentDistance(view, frame, slot)
	if lunge > 0.02 and dist and type(move.range) == "number" then
		local startup = math.max(resolved.timing.startup, 1)
		local mf = view.moveFrame or 0
		local remaining = (move.advance or 0) * math.max(0, startup - math.max(mf - 1, 0)) / startup
		local sep = if type(config) == "table" and type(config.Separation) == "number" then config.Separation else 2.6
		local predicted = math.max(sep, dist - remaining)
		target = 1 - math.clamp((move.range - predicted) / lunge, 0, 1)
	end
	-- The scale carries over between consecutive attack frames (string hits included) and moves at most LungeRate a frame.
	local k = target
	local clock = st.clock
	if st.lungeK and st.lungeAt and clock - (st.lungeAt :: number) <= 2.5 / 60 and clock >= (st.lungeAt :: number) then
		k = math.clamp(target, (st.lungeK :: number) - MotionPlayer.LungeRate, (st.lungeK :: number) + MotionPlayer.LungeRate)
	end
	st.lungeK, st.lungeAt = k, clock
	if k >= 0.999 then return end
	local ro = pose.rootOffset
	if ro.Z > 0 then pose.rootOffset = Vector3.new(ro.X, ro.Y, ro.Z * k) end
end

-- Identity of the last hit a fighter took (CombatSim's lastHit: frame + move + kind), nil before any.
local function hitStampOf(view: FighterView): string?
	local h = view.lastHit
	if type(h) ~= "table" then return nil end
	return tostring(h.frame) .. ":" .. tostring(h.move) .. ":" .. tostring(h.kind)
end

-- Hitstop at the RENDERED moment. frame.hitstop belongs to the newest snapshot, but server duels render the fighters a
-- buffer delay behind it (frozen several frames before the hit was even shown, the attacker caught short of contact).
-- When the frame carries renderFrame (sim frames at render time) and the newest entry, the freeze window [hit frame,
-- hit frame + hitstop) is tracked from the entries and compared with the rendered frame (practice renders the newest
-- entry, so both agree there). Frames without them (tests, previews): frame.hitstop.
local hitWindow: { start: number?, stop: number? } = { start = nil, stop = nil }
function MotionPlayer.hitstopActive(frame: any?): boolean
	if frame == nil then return false end
	local entry, rf = frame.entry, frame.renderFrame
	if type(entry) == "table" and type(entry.frame) == "number" and type(rf) == "number" then
		local hs = if type(entry.hitstop) == "number" then entry.hitstop else 0
		if hs > 0 then
			local stop = entry.frame + hs
			if hitWindow.stop == nil or entry.frame >= (hitWindow.stop :: number) or entry.frame < (hitWindow.start :: number) then
				hitWindow.start = entry.frame
			end
			hitWindow.stop = stop
		end
		local start, stop = hitWindow.start, hitWindow.stop
		return start ~= nil and stop ~= nil and rf >= start - 1e-6 and rf < stop
	end
	return (frame.hitstop or 0) > 0
end

-- How far (degrees) a crossfade between two heading-space poses turns the body's joints: pelvis, waist and neck
-- rotations; per limb, the swing of the shoulder/hip->effector direction, the change of the elbow/knee bend (from the
-- effector distance, two equal segments) and the turn of the bend plane (poles about the limb axis). Sets crossfade
-- lengths (a guard's elbows swinging out on a block barely move the fist, but turn the arm 70 degrees).
local LIMB_REACH: { [string]: number } = { LeftHand = 1.95, RightHand = 1.95, LeftFoot = 2.75, RightFoot = 2.75 }
local LIMB_PIVOT: { [string]: Vector3 } = { LeftHand = Vector3.new(-0.5, 1.1, 0), RightHand = Vector3.new(0.5, 1.1, 0), LeftFoot = Vector3.new(-0.3, -0.35, 0), RightFoot = Vector3.new(0.3, -0.35, 0) }
local function poseDistanceDeg(a: Pose, b: Pose, scale: number): number
	local function rotDeg(x: CFrame?, y: CFrame?): number
		if not x or not y then return 0 end
		local _, ang = (x:Inverse() * y):ToAxisAngle()
		return math.deg(math.abs(ang))
	end
	local function angle(u: Vector3, v: Vector3): number
		if u.Magnitude < 1e-6 or v.Magnitude < 1e-6 then return 0 end
		return math.deg(math.acos(math.clamp(u.Unit:Dot(v.Unit), -1, 1)))
	end
	local worst = math.max(rotDeg(a.rootRot, b.rootRot), rotDeg(a.waistRot, b.waistRot), rotDeg(a.neckRot, b.neckRot))
	for name, ea in a.targets do
		local eb = b.targets[name]
		local reach = LIMB_REACH[name]
		if eb and reach then
			local pivot = LIMB_PIVOT[name] * scale
			local va, vb = ea.pos - pivot, eb.pos - pivot
			local full = reach * scale
			local function flex(v: Vector3): number return math.deg(2 * math.acos(math.clamp(v.Magnitude / full, 0, 1))) end
			local swing = angle(va, vb)
			local bendChange = math.abs(flex(va) - flex(vb))
			local twist = 0
			local pa, pb = ea.pole, eb.pole
			local axis = va + vb
			if pa and pb and axis.Magnitude > 1e-4 then
				axis = axis.Unit
				-- A straight limb's bend plane barely shows.
				twist = angle(pa - axis * pa:Dot(axis), pb - axis * pb:Dot(axis)) * math.clamp(math.max(flex(va), flex(vb)) / 60, 0, 1)
			end
			worst = math.max(worst, swing + bendChange + twist)
		end
	end
	return worst
end
MotionPlayer.poseDistanceDeg = poseDistanceDeg

function MotionPlayer.sample(config: any, view: FighterView, frame: any?, slot: number?): Pose
	local s = slot or 1
	local st = slotState(s)
	local previous = st.pose
	-- Hitstop freezes animation TIME, not the view: the frozen sim data is re-sampled, so the attacker shows (and holds)
	-- its hit frame itself, and a fighter entering a reaction eases into its impact pose on real time during the freeze.
	local hitstop = MotionPlayer.hitstopActive(frame)
	local prevPos = st.lastPos
	local clockBefore = st.clock
	local realBefore = st.real
	advanceClock(st, frame, view, hitstop)
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
	local moveStartup: number? = nil
	local pose: Pose? = nil
	if not settling and type(view.throw) == "table" then
		if Cinematic.isUltimate(view.throw) then
			pose = ultimatePose(view, frame, s, characterId, scale, legLength)
			key, fade = "Ultimate", 0.06
		elseif view.throw.broken == true then
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
			lungeSpacing(pose :: Pose, clip, resolved, view, frame, s, st, legLength, config)
			aimContact(pose :: Pose, clip, resolved, view.moveFrame or 0, scale, rootHeight, opponentRootHeight(frame, s), opponentAimHeights(frame, s), legLength)
		else
			local normalized = moveTime(resolved.timing, view.moveFrame or 0)
			local legacy = sampleKeys(resolved.keyframes, normalized)
			applyCosmeticLunge(legacy, resolved, view, frame, s, normalized)
			pose = toHeading(legacy, scale)
		end
		key, fade = "Move:" .. moveKey, 0.05
		moveStartup = resolved.timing.startup
		local step = stepInScale(st, view, moveKey, resolved, scale)
		if step < 1 then (pose :: Pose).stepScale = step end
		-- The contact push-back of the previous frames carries on, released on the animation clock.
		st.pushGrow = 0
		if MotionPlayer.ContactPushBack and st.pushBack and st.pushAt and st.clock >= (st.pushAt :: number) and st.clock - (st.pushAt :: number) < 0.25 then
			local carried = math.max(0, (st.pushBack :: number) - (st.clock - (st.pushAt :: number)) * 60 * MotionPlayer.ContactPushRelease)
			st.pushBack, st.pushAt = carried, st.clock
			if carried > 1e-3 then
				local p = pose :: Pose
				p.rootOffset -= Vector3.new(0, 0, carried)
				p.pushBack = carried
			end
		else
			st.pushBack, st.pushAt = nil, nil
		end
	else
		local style = if Roster.has(characterId) then Roster.get(characterId).stanceStyle else "boxer"
		local req = States.request(view, frame, s, characterId, scale, { clock = st.clock, keyStarted = st.keyStarted, key = st.key, settling = settling, config = config, legLength = legLength, shownLie = lieOf(previous) })
		if req.key ~= st.key then
			if req.timeKey == nil or req.timeKey ~= st.timeKey then st.keyStarted = st.clock end
			if req.restart then st.travel = 0 end
		end
		st.timeKey = req.timeKey
		pose = resolveRequest(req, st, style, scale, legLength)
		key, fade = req.key, req.fade or 0.12
		local trim = MotionPlayer.GuardTrim[characterId]
		if trim and GUARD_STATES[view.state] and not settling then
			for limb, offset in trim do
				local e = (pose :: Pose).targets[limb]
				if e then e.pos += offset end
			end
		end
	end
	local result: Pose = pose :: Pose
	addArmor(result, view)
	-- The sim pushes both fighters apart on the frame a throw (or a broken throw) ends. The crossfade out of the throw
	-- starts from the last throw pose held where it was in the world (compensated by the sim jump), so the body slides
	-- over the push during the fade instead of popping. A track that already ends at the pushed spot shows no slide.
	local leavingThrow = st.key ~= nil and (string.sub(st.key, 1, 5) == "Throw" or st.key == "Ultimate") and string.sub(key, 1, 5) ~= "Throw" and key ~= "Ultimate"
	-- Entering the Ultimate cinematic: the sim locks the defender endDistance in front of the attacker on the hit frame;
	-- that jump glides like a hit push.
	local enteringUltimate = key == "Ultimate" and st.key ~= nil and st.key ~= "Ultimate"
	-- A new round (the sim puts both fighters back on their marks; the KO'd loser is standing again) is a clean cut:
	-- crossfading from the lying/celebrating pose at the new spot would show a body morphing upright.
	-- The renderers interpolate the position between two sim frames (or snapshots), so the reset can arrive as an
	-- in-between position below TeleportDistance with the new round's key one frame before the jump: the newest
	-- entry's own position jump counts too (faster than anything the sim moves: a long snapshot gap is not a reset).
	local entry = if type(frame) == "table" and type(frame.entry) == "table" then frame.entry else nil
	local entryFighter = if entry and type(entry.fighters) == "table" then entry.fighters[s] else nil
	local entryPos: Vector3? = if type(entryFighter) == "table" and typeof(entryFighter.pos) == "Vector3" then entryFighter.pos else nil
	local entryFrame: number? = if entry and type(entry.frame) == "number" then entry.frame else nil
	local entryJump = false
	if entryPos and st.entryPos then
		local dist = ((entryPos :: Vector3) - (st.entryPos :: Vector3)).Magnitude
		local frames = if entryFrame and st.entryFrame then math.max((entryFrame :: number) - (st.entryFrame :: number), 1) else 1
		entryJump = dist > MotionPlayer.TeleportDistance and dist / frames > 1.5
	end
	st.entryPos, st.entryFrame = entryPos, entryFrame
	local roundReset = (prevPos ~= nil and typeof(view.pos) == "Vector3" and (view.pos - prevPos).Magnitude > MotionPlayer.TeleportDistance)
		or entryJump
		or (key == "Intro" and st.key ~= nil and (string.sub(st.key, 1, 3) == "KO:" or st.key == "Victory" or st.key == "Defeat"))
	-- A new hit on this fighter (hit, block, counter): CombatSim pushes the defender back by up to ~1.8 studs on the hit
	-- frame. The body is held where it stood and released over a few frames of animation time (it stays put through the
	-- hitstop freeze, then slides back), instead of jumping back in one frame.
	local stamp = hitStampOf(view)
	local newHit = st.hitSeen == true and stamp ~= nil and stamp ~= st.hitStamp
	st.hitStamp, st.hitSeen = stamp, true
	-- Practice renders between two sim frames and server duels between two snapshots: a push the sim applies in one
	-- frame reaches the screen over the next render frames too, so displacement within PushAbsorbWindow (real time)
	-- after the hit, or after leaving a throw, is absorbed into the same glide (it used to show as a 0.3-stud jump on
	-- the frame after the hit).
	local absorbing = st.absorbUntil ~= nil and st.real <= (st.absorbUntil :: number)
	if roundReset then
		st.glide = nil
		st.absorbUntil = nil
	elseif (newHit or absorbing or enteringUltimate) and prevPos and typeof(view.pos) == "Vector3" then
		local d = view.pos - prevPos
		d = Vector3.new(d.X, 0, d.Z)
		if d.Magnitude > 0.05 and d.Magnitude < 2.5 then
			local remaining = if st.glide and st.glideStart and st.glideDur then (st.glide :: Vector3) * (1 - smoothstep((st.clock - st.glideStart) / st.glideDur)) else Vector3.zero
			st.glide = remaining - d
			st.glideStart = st.clock
			st.glideDur = if key == "Ultimate" then MotionPlayer.UltimateEntryGlide else math.clamp(0.08 + (remaining - d).Magnitude * 0.06, 0.08, 0.2)
		end
	end
	if not roundReset and (newHit or leavingThrow or enteringUltimate) then st.absorbUntil = st.real + MotionPlayer.PushAbsorbWindow end
	if st.key ~= key then
		-- An impact entry (a new key on a hit or during the hitstop freeze): the crossfade runs on real time so the
		-- impact pose arrives during the freeze, long enough that no joint turns more than ImpactDegPerFrame per frame.
		local impact = hitstop or newHit
		if previous and fade > 0 and not roundReset then
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
			local travel = poseDistanceDeg(from, result, scale)
			if impact then
				st.fadeReal = true
				st.fadeStart = realBefore
				st.fadeDur = math.clamp(travel / MotionPlayer.ImpactDegPerFrame / 60, MotionPlayer.ImpactFadeMin, MotionPlayer.ImpactFadeMax)
			else
				st.fadeReal = false
				st.fadeStart = clockBefore
				-- A getup starts from the lying pose the landing ends in and must keep the sim's roll timing: its stretch is
				-- capped shorter.
				local maxFade = if string.sub(key, 1, 6) == "Getup:" then MotionPlayer.GetupCrossfadeMax else MotionPlayer.CrossfadeMax
				local dur = math.max(fade, math.min(travel / MotionPlayer.CrossfadeDegPerFrame / 60, maxFade))
				-- An attack's fade-in always completes before its first active frame (the contact pose is never blended).
				-- When that cap shortens it, the fade runs linearly: the same turn every frame (an eased fade's middle
				-- frames turned 1.5x faster and showed as a jump into quick strikes).
				st.fadeLinear = false
				if moveStartup then
					local cap = math.max(fade, math.min((moveStartup - 2) / 60, MotionPlayer.MoveFadeMax))
					if dur > cap then dur, st.fadeLinear = cap, true end
				end
				st.fadeDur = dur
			end
			st.fadeFrom = from
		else
			st.fadeFrom = nil
		end
		st.key = key
	end
	local from = st.fadeFrom
	if from then
		-- Impact fades run linearly (an even turn per frame from the hit on); others ease in and out.
		local t = if st.fadeReal then st.real else st.clock
		local x = math.clamp((t - st.fadeStart) / math.max(st.fadeDur, 1e-3), 0, 1)
		local alpha = if st.fadeReal or st.fadeLinear then x else smoothstep(x)
		if alpha >= 1 then st.fadeFrom = nil else result = blendPose(from, result, alpha) end
	end
	local glide = st.glide
	if glide and st.glideStart and st.glideDur then
		local w = 1 - smoothstep((st.clock - st.glideStart) / st.glideDur)
		if w <= 0 then
			st.glide = nil
		else
			local facing = if view.facing.Magnitude > 0.001 then view.facing.Unit else Vector3.xAxis
			local right = facing:Cross(Vector3.yAxis)
			local g = glide * w
			result = table.clone(result)
			result.rootOffset += Vector3.new(g:Dot(right), 0, g:Dot(facing))
		end
	end
	-- A round reset the renderer interpolates (practice lerps between two sim frames, server duels between two snapshots;
	-- both only skip that beyond RenderBuffer.TeleportDistance) showed the body at an in-between spot on the cut frame and
	-- jumped up to 3 studs on the next one. For ResetSnapWindow (real time) the new round's intro pose is shown at the
	-- newest entry's position (the new mark; nobody moves during Ready): an offset that vanishes as the interpolation
	-- arrives there. A body still shown in the old round (a server duel renders behind the newest snapshot) is left alone.
	if roundReset then st.resetSnapUntil = st.real + MotionPlayer.ResetSnapWindow end
	if st.resetSnapUntil and st.real <= (st.resetSnapUntil :: number) then
		if key == "Intro" and entryPos and typeof(view.pos) == "Vector3" then
			local d = (entryPos :: Vector3) - view.pos
			d = Vector3.new(d.X, 0, d.Z)
			if d.Magnitude > 1e-3 and d.Magnitude < 8 then
				local facing = if view.facing.Magnitude > 0.001 then view.facing.Unit else Vector3.xAxis
				local right = facing:Cross(Vector3.yAxis)
				result = table.clone(result)
				result.rootOffset += Vector3.new(d:Dot(right), 0, d:Dot(facing))
			end
		end
	else
		st.resetSnapUntil = nil
	end
	-- Knockdowns: the lying smoother (see lyingSmooth).
	if LYING_SMOOTH_STATES[view.state] then st.lyingTail = st.real + MotionPlayer.LyingTail end
	local smoothing = MotionPlayer.LyingSmooth and not roundReset and not settling and type(view.move) ~= "string" and type(view.throw) ~= "table"
		and (LYING_SMOOTH_STATES[view.state] or (st.lyingTail ~= nil and st.real <= (st.lyingTail :: number) and LYING_TAIL_STATES[view.state] ~= nil))
	if smoothing and st.lyingPrev and st.lyingAt then
		local frames = math.clamp((st.real - (st.lyingAt :: number)) * 60, 0.25, 3)
		result = lyingSmooth(result, st.lyingPrev, frames, scale)
		result.lyingFrames = frames
		-- Getup clips only (the stand-up lead in Landing's last frames and the Getup state): their feet swing with the shins
		-- (MotionPlayer.GetupAnkleRange); lying and KO feet keep their relaxed pose.
		if MotionPlayer.GetupAnkleRange and string.sub(key, 1, 6) == "Getup:" then result.ankleRange = true end
	end
	st.lyingPrev, st.lyingAt = bodyFrame(result, scale), st.real
	validatePose(result)
	result.clock = st.clock
	result.real = st.real
	result.selfClear = SELF_CLEAR_STATES[view.state] == true and type(view.move) ~= "string" and type(view.throw) ~= "table"
		and (type(frame) ~= "table" or frame.phase == nil or frame.phase == "Fight")
	-- A thrown defender keeps its gloves out of its own body too (clearArms; grips re-solve their limbs afterwards), and
	-- so does a defender breaking the throw (MotionPlayer.DefenderClearBreak).
	result.defenderClear = type(view.throw) == "table" and view.throw.role == "Defender" and (view.throw.broken ~= true or MotionPlayer.DefenderClearBreak == true)
	if roundReset then result.cut = true end
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
	-- A visible foot in a shoe longer or wider than the bare foot publishes the shoe's ground box (foot space; same
	-- height and bottom as the foot box): feet then rest on the shoe, not on the bare foot inside it.
	local tipCenter = Vector3.zero
	-- The shoe worn on the foot (its part box, foot space): a foot the runtime re-orients after the solver rested it (the
	-- getup ankle range, the knockdown whip limit) keeps its shoe no lower than the solve had it (a high-top's collar
	-- reaches below the foot box once the foot turns).
	local shoeBox: CFrame?, shoeSize: Vector3? = nil, nil
	if isLeg and endPart then
		local shoeSize0, shoeCenter = endPart:GetAttribute("FightingLabShoeGroundSize"), endPart:GetAttribute("FightingLabShoeGroundCenter")
		if typeof(shoeSize0) == "Vector3" and typeof(shoeCenter) == "Vector3" then
			tipSize, tipCenter = shoeSize0, shoeCenter
		end
		for _, d in endPart:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("FightingLabRole") == "shoe" then
				local weld = d:FindFirstChildOfClass("Weld")
				if weld then shoeBox, shoeSize = weld.C0, d.Size end
				break
			end
		end
	end
	return {
		joint = joint, mid = mid, tip = tip, target = target, isLeg = isLeg, upperBone = upperBone, l1 = l1, l2 = l2,
		ankleHeight = ankleHeight, refPivot = refPivotV, refReach = refReach, fullReach = fullReach, side = side,
		upperSize = if upperPart then upperPart.Size else Vector3.one * 0.4, lowerSize = if lowerPart then lowerPart.Size else Vector3.one * 0.4,
		tipSize = tipSize, tipOffset = t.C1.Position - tipCenter, tipBox = CFrame.new(tipCenter), shoeBox = shoeBox, shoeSize = shoeSize,
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
-- Lowest point of an oriented box (its exact extent: a little below extentY's rounded estimate). Used where the runtime
-- turns a foot after the solver rested it (the getup ankle range, the knockdown whip limit): a shoe mesh fills its box.
local function boxBottom(cf: CFrame, size: Vector3): number
	return cf.Position.Y - (math.abs(cf.RightVector.Y) * size.X + math.abs(cf.UpVector.Y) * size.Y + math.abs(cf.LookVector.Y) * size.Z) * 0.5
end
-- Lowest point of a foot given its part frame: its (ground) box, and its shoe's box when it wears one.
local function footBottom(chain: any, footCF: CFrame): number
	local b = boxBottom(footCF * chain.tipBox, chain.tipSize)
	if chain.shoeBox then b = math.min(b, boxBottom(footCF * chain.shoeBox, chain.shoeSize)) end
	return b
end

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

-- Getup ankle range (round 5). On the knockdown smoother's poses (lying, rolling, getting up) a foot that is not planted
-- keeps the clip's orientation in the world while its shin swings under it: the side roll's kneeling foot read 100-146
-- deg of dorsiflexion and 60-95 deg of roll against its shin. Such a foot's turn against the shin is kept inside the
-- ankle's range (toes toward the knee, sideways, about the foot's long axis — as MotionQA measures it; pointed toes are
-- left alone: a lying foot lays its toes out along the floor), fading out as the foot plants (planted feet are flattened
-- onto the floor as before).
MotionPlayer.GetupAnkleRange = true
MotionPlayer.AnkleRange = { dorsi = 40, plantar = 180, roll = 35, yaw = 40 }
local function clampAnkle(shin: CFrame, foot: CFrame, w: number): CFrame
	local a = shin.Rotation:Inverse() * foot.Rotation
	local toe = a.LookVector
	local pitch = math.deg(math.atan2(toe.Y, -toe.Z))
	local yaw = math.deg(math.asin(math.clamp(toe.X, -1, 1)))
	local ax, ang = a:ToAxisAngle()
	local along = ax.Z * math.sin(ang * 0.5)
	local qw = math.cos(ang * 0.5)
	local len = math.sqrt(along * along + qw * qw)
	local roll = if len > 1e-9 then math.deg(2 * math.atan2(along / len, qw / len)) else 0
	while roll > 180 do roll -= 360 end
	while roll < -180 do roll += 360 end
	local R = MotionPlayer.AnkleRange
	local p2 = math.clamp(pitch, -R.plantar, R.dorsi)
	local y2 = math.clamp(yaw, -R.yaw, R.yaw)
	local r2 = math.clamp(roll, -R.roll, R.roll)
	if p2 == pitch and y2 == yaw and r2 == roll then return foot end
	local cy = math.cos(math.rad(y2))
	local toe2 = Vector3.new(math.sin(math.rad(y2)), cy * math.sin(math.rad(p2)), -cy * math.cos(math.rad(p2)))
	local from = -Vector3.zAxis
	local axis = from:Cross(toe2)
	local swing = if axis.Magnitude > 1e-6 then CFrame.fromAxisAngle(axis.Unit, math.acos(math.clamp(from:Dot(toe2), -1, 1))) else CFrame.identity
	local clamped = shin.Rotation * swing * CFrame.fromAxisAngle(Vector3.zAxis, math.rad(r2))
	return foot.Rotation:Lerp(clamped, math.clamp(w, 0, 1))
end

-- The foot rises onto its ball — toes pitched down about the ankle, at most `limit` below the floor plane — just enough
-- for its ankle (ankleAt: ankle height of the foot shown in a rotation, its lowest point keeping its clearance above the
-- floor) to reach `needY`. When no rise within the limit gets there, the rise that lifts the ankle most (none when
-- rising does not help: a short bare foot whose ankle sits over its toes lifts LESS when pitched; the old full-limit
-- answer stood such a foot on its toes for nothing and flipped it 60 degrees between frames).
local function riseOnBall(base: CFrame, needY: number, limit: number, ankleAt: (CFrame?) -> number): CFrame
	local room = math.max(0, limit - math.asin(math.clamp(-base.LookVector.Y, -1, 1)))
	local function tiptoe(a: number): CFrame return base * CFrame.Angles(-a, 0, 0) end
	local bestA, bestY = 0, ankleAt(base)
	if bestY >= needY or room <= 1e-4 then return base end
	local STEPS = 6
	local prevA = 0
	for i = 1, STEPS do
		local a = room * i / STEPS
		local yA = ankleAt(tiptoe(a))
		if yA >= needY then
			local lo, hi = prevA, a
			for _ = 1, 6 do
				local mid = (lo + hi) * 0.5
				if ankleAt(tiptoe(mid)) >= needY then hi = mid else lo = mid end
			end
			return tiptoe(hi)
		end
		if yA > bestY + 1e-4 then bestA, bestY = a, yA end
		prevA = a
	end
	return tiptoe(bestA)
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

-- IK pole continuity. The bend plane of a two-bone limb comes from the clip's pole hint projected off the limb axis.
-- When the hint lies nearly along the limb (a leg kicking straight out along its knee pole, an arm reaching along its
-- elbow pole, a crossfade between poses whose poles point apart and cancel), the projection is undefined and the
-- elbow/knee — and the twist of the upper limb with it — flips up to 180 degrees in one frame. The previous frame's
-- bend direction (kept in the parent part's frame: whole-body turns and spins do not count) takes over as the hint
-- weakens, and the bend direction turns at most PoleMaxStep per frame (pose clock), so a flip becomes a short roll.
-- false = the round-5 behaviour (A/B checks).
MotionPlayer.PoleContinuity = true
-- The continuity reference advances with the shown frames (real time), not the animation clock: during a hitstop freeze
-- the clock stops while the impact fade keeps moving the pose, and a stale reference let the bend plane jump once the
-- freeze ended (Kael's KO arm spun 153 degrees in one frame).
MotionPlayer.ContinuityRealTime = true
MotionPlayer.PoleMaxStep = math.rad(30)
local POLE_WEAK = 0.4
-- Per-frame bookkeeping: on the first solve of a new frame the previous frame's final bend becomes the reference
-- (re-solves within the frame — ground passes, the lying settle, throw grips — keep the same reference). A clock jump
-- (new round, reused rig) starts over. Returns whether continuity applies to this solve.
local function beginContinuity(rig: RigInfo, chain: any): boolean
	local clock = rig.frameClock or rig.lockClock
	if not MotionPlayer.PoleContinuity or clock == nil then return false end
	if chain.bendClock ~= clock then
		local last = chain.bendClock
		local fresh = last ~= nil and clock > last and clock - last < 0.25
		chain.bendRef = if fresh then chain.bendPrev else nil
		chain.bendClock = clock
	end
	return true
end

-- The bend direction (unit, perpendicular to the start->aim axis) a solve uses: the hint projected off the axis, with
-- the previous frame's bend blended in as the hint weakens and the change limited to PoleMaxStep. Projected exactly
-- as solveTwoBone projects, so a healthy hint gives the same answer as before.
local function continuousBend(chain: any, parentFrame: CFrame, start: Vector3, aim: Vector3, hint: Vector3, free: boolean): Vector3
	local dir = safeUnit(aim - start, Vector3.zAxis)
	local p = projectPole(hint, dir, Vector3.yAxis)
	local refLocal = chain.bendRef
	if not refLocal then return p end
	local ref = parentFrame:VectorToWorldSpace(refLocal)
	ref -= dir * ref:Dot(dir)
	if ref.Magnitude < 1e-4 then return p end
	ref = ref.Unit
	local raw = hint - dir * hint:Dot(dir)
	local k = if hint.Magnitude > 1e-6 then smoothstep(raw.Magnitude / hint.Magnitude / POLE_WEAK) else 0
	local want = p * k + ref * (1 - k)
	if want.Magnitude < 1e-4 then want = ref else want = want.Unit end
	-- A pole the floor lift turned (knees/elbows kept above the floor) may turn faster, but never flip in one frame.
	local step = if free then MotionPlayer.PoleMaxStep * 1.5 else MotionPlayer.PoleMaxStep
	if want:Dot(ref) < math.cos(step) then
		local axis = ref:Cross(want)
		axis = if axis.Magnitude > 1e-6 then axis.Unit else dir
		want = CFrame.fromAxisAngle(axis, step):VectorToWorldSpace(ref)
		want -= dir * want:Dot(dir)
		want = safeUnit(want, ref)
	end
	return want
end

-- Forgets a rig's per-frame continuity state (foot locks, bend directions): a rig reused for another fighter or case.
function MotionPlayer.resetRig(rig: RigInfo)
	table.clear(rig.footLock)
	rig.aimResidual = nil
	rig.lyingRel = nil
	rig.contactHold = nil
	rig.lyingLegs = nil
	rig.relaxFeet = nil
	rig.selfPush = nil
	rig.selfPushForced = nil
	rig.selfPushGrip = nil
	rig.gripMoved = nil
	(rig :: any).clampJoints = nil
	rig.contactMoved = nil
	for _, chain in rig.chains do
		chain.bendPrev, chain.bendRef, chain.bendClock = nil, nil, nil
		chain.flatPrev, chain.flatRef, chain.flatClock = nil, nil, nil
	end
end

-- Heel-drop continuity: the flatten fraction of a planted foot on the previous frame (nil on a new round, a reused rig
-- or a clock jump). Same per-frame bookkeeping as the bend continuity.
MotionPlayer.FlattenRate = 0.15
MotionPlayer.LyingLegsRamp = 0.1
-- Relaxed feet (toes laid out along the floor, sole up: up to a 180-degree roll about the toe line) come and go over at
-- least this much real time: a roll getup tucking the toes again within its 5-frame crossfade snapped the ankle 66 deg.
MotionPlayer.RelaxFeetRamp = 0.25
-- Soft limits of the foot solve (studs): a foot settling onto the floor eases in over SoftFloor; a leg nearing its
-- reach starts onto the ball within SoftReach of the limit.
MotionPlayer.SoftFloor = 0.06
MotionPlayer.SoftReach = 0.06
-- 0 below 0, x above w, an eased blend between (C1: a coming-down foot stops without a jolt).
local function softPositive(x: number, w: number): number
	if x <= 0 then return 0 end
	if w <= 0 or x >= w then return x end
	return x * smoothstep(x / w)
end
-- Polynomial smooth maximum (>= max(a, b), equal once they differ by more than w).
local function softMax(a: number, b: number, w: number): number
	if w <= 0 then return math.max(a, b) end
	local h = math.clamp(0.5 + 0.5 * (a - b) / w, 0, 1)
	return b + (a - b) * h + w * h * (1 - h)
end
local function flattenRef(rig: RigInfo, chain: any): number?
	local clock = rig.lockClock
	if clock == nil then return nil end
	if chain.flatClock ~= clock then
		local last = chain.flatClock
		local fresh = last ~= nil and clock > last and clock - last < 0.25
		chain.flatRef = if fresh then chain.flatPrev else nil
		chain.flatDt = if fresh then clock - last else 0
		chain.flatClock = clock
	end
	return chain.flatRef
end

local function solveChain(rig: RigInfo, chain: any, parentFrame: CFrame, heading: CFrame, legacyFrame: CFrame, effector: Effector, floorY: number, footFlat: CFrame, scale: number, headingSpace: boolean, contact: number, settle: number?, lying: number?, relax: number?, stepScale: number?, ankleRange: number?): number
	local motors = rig.motors
	local jm, mm, tm = motors[chain.joint], motors[chain.mid], motors[chain.tip]
	local pivot = parentFrame * jm.C0
	local targetFrame = if headingSpace then heading else legacyFrame
	-- Re-express the authored target relative to the reference shoulder/hip, scaled to this rig's limb reach.
	local rel = (effector.pos - chain.refPivot * scale) * (chain.fullReach / (chain.refReach * scale))
	local goal = pivot.Position + targetFrame:VectorToWorldSpace(libVector(rel))
	local aimY, aimW = effector.aimWorldY, effector.aimWeight
	if aimY and aimW and aimW > 0 then
		-- Contact aim at a measured world height (the opponent's head/chest/knee), through this rig's posed pivot. In the
		-- recovery the residual of the last active frame is added while it releases (the clip's own motion continues).
		local residuals = rig.aimResidual
		if not residuals then
			residuals = {}
			rig.aimResidual = residuals
		end
		local r = floorY + aimY - goal.Y
		local stored = residuals[chain.target]
		local clock = rig.lockClock
		if effector.aimPhase == 3 and MotionPlayer.AimAdditiveRecovery and stored and clock and stored.clock and clock - stored.clock >= 0 and clock - stored.clock < 1 then
			r = stored.r
		elseif effector.aimPhase ~= 3 then
			residuals[chain.target] = { r = r, clock = clock }
		end
		goal = Vector3.new(goal.X, goal.Y + r * math.min(aimW, 1), goal.Z)
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
		-- A foot coming down decelerates over the last SoftFloor studs instead of stopping dead on the floor (a clip foot
		-- aimed a little below this rig's floor used to stop in one frame and kick the shin).
		local clear = softPositive(goal.Y + chain.ankleHeight - floorY - clipLift, MotionPlayer.SoftFloor)
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
			-- The heel comes down at most FlattenRate per frame (a reach limit relaxing — the pelvis lowering over a
			-- foot on its ball — used to slap the heel down 30 degrees in one frame and kick the thigh with it).
			local kRef = flattenRef(rig, chain)
			if kRef and k > kRef then k = math.min(k, kRef + MotionPlayer.FlattenRate * math.max(chain.flatDt * 60, 1)) end
			local shown = if k > 0 then clipRot:Lerp(flat, k) else clipRot
			local y = ankleY(shown)
			-- Smooth max: near the reach limit the foot already starts onto its ball (no kink where the limit takes over).
			local need = softMax(y, lowestY, MotionPlayer.SoftReach)
			if k > 0 and y < need then
				-- A (nearly) straight leg cannot lower its ankle to a flat foot: the heel stays up just enough and the
				-- foot rests on its ball instead, still on the floor.
				local lo, hi = 0, k
				for _ = 1, 7 do
					local mid = (lo + hi) * 0.5
					if ankleY(clipRot:Lerp(flat, mid)) >= need then lo = mid else hi = mid end
				end
				k = lo
				shown = if k > 0 then clipRot:Lerp(flat, k) else clipRot
				y = ankleY(shown)
				if y < lowestY and hold > 0.35 then
					-- Even the clip's own foot cannot reach (a straight support or pivot leg on a rig whose pelvis rides
					-- high for its legs): the planted foot rises further onto its ball until its toes reach the floor.
					-- Faded in with the contact (a hard switch at contact 0.65 used to snap the foot 60 degrees).
					local riseW = smoothstep((hold - 0.35) / 0.3)
					shown = shown:Lerp(riseOnBall(shown, lowestY, TIPTOE_MAX, ankleY), riseW)
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
			chain.flatPrev = k
			local dbg = rig.debug
			if dbg then dbg[chain.target] = { planted = planted, k = k, hold = hold, clear = clear, netW = netW, lying = lyingW, relax = relax or 0, y = y, lowestY = lowestY, flatD = flatD, reach = reach, clip = clipRot, shown = shown, contact = contact, pivotY = pivotPos.Y - floorY, goalY = goal.Y - floorY } end
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
	local continuity = beginContinuity(rig, chain)
	local bone = safeUnit(chain.upperBone, -Vector3.yAxis)
	local foldRest = if chain.isLeg then Vector3.zAxis else -Vector3.zAxis
	foldRest = safeUnit(foldRest - bone * foldRest:Dot(bone), foldRest)
	local restFrame = CFrame.fromMatrix(Vector3.zero, bone, foldRest):Inverse()
	local upperWorld, lowerWorld, tipWorld = pivot, pivot, pivot
	local midClearance = chain.midRadius
	local usedBend: Vector3? = nil
	for attempt = 1, 3 do
		-- Knees and elbows never bend through the floor (a floor-lifted pole is taken as is: no continuity limit).
		local bendPole = liftPole(pivot.Position, goal, chain.l1, chain.l2, pole, floorY + midClearance)
		local lifted = bendPole ~= pole
		local aim = goal
		for iteration = 1, 3 do
			local bendDir = if continuity then continuousBend(chain, parentFrame, pivot.Position, aim, bendPole, lifted) else bendPole
			usedBend = bendDir
			local joint, tip = MotionPlayer.solveTwoBone(pivot.Position, aim, chain.l1, chain.l2, bendDir)
			local u = safeUnit(joint - pivot.Position, -pivot.UpVector)
			local f = safeUnit(tip - joint, u)
			-- The lower segment folds toward the inside of the bend; a straight limb folds away from its pole.
			local inward = f - u * f:Dot(u)
			if inward.Magnitude < 1e-3 then inward = -(bendDir - u * bendDir:Dot(u)) end
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
			-- On getup poses an unplanted foot stays inside the ankle's range against this solve's shin (GetupAnkleRange),
			-- as far as that does not take the foot or its shoe lower than the solve rested it (or below the floor).
			if wanted and footRot and ankleRange and ankleRange > 0 and planted < 1 then
				local w0 = ankleRange * (1 - planted)
				local turned = clampAnkle(lowerWorld, wanted :: CFrame, w0)
				if turned ~= wanted then
					local base = lowerWorld * tm.C0
					local c1 = tm.C1
					local function bottomOf(rot: CFrame): number
						return footBottom(chain, base * (base.Rotation:Inverse() * rot * c1.Rotation) * c1:Inverse())
					end
					local need = math.min(floorY, bottomOf(wanted :: CFrame))
					if bottomOf(turned) < need then
						local lo, hi = 0, w0
						for _ = 1, 6 do
							local mid = (lo + hi) * 0.5
							if bottomOf(clampAnkle(lowerWorld, wanted :: CFrame, mid)) >= need then lo = mid else hi = mid end
						end
						turned = clampAnkle(lowerWorld, wanted :: CFrame, lo)
					end
					wanted = turned
				end
			end
			if wanted then
				local flat = (lowerWorld * tm.C0).Rotation:Inverse() * wanted * tm.C1.Rotation
				tipTransform = if footRot then flat else CFrame.identity:Lerp(flat, planted)
			end
		end
		tm.Transform = tipTransform
		tipWorld = lowerWorld * tm.C0 * tipTransform * tm.C1:Inverse()
		-- A tilted foot (toe or heel down) or a hand dipping below the floor raises its goal by the overlap; a thigh,
		-- shin or forearm dipping below it (segments overhang their joints) lifts the knee/elbow further.
		local tipBottom = (tipWorld * chain.tipBox).Position.Y - extentY(tipWorld, chain.tipSize)
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
	-- The bend direction this frame ended with (parent space) is the next frame's continuity reference.
	if continuity and usedBend then chain.bendPrev = parentFrame:VectorToObjectSpace(usedBend) end
	-- The goal this solve aimed at (the tip lands up to ~0.1 studs off it: three re-aim passes on a bent arm whose hand sits
	-- off the forearm axis). Re-solves of the same limb (self clearance) offset this goal, not the landed tip, so a zero
	-- offset reproduces the pose exactly (offsetting the tip re-landed the arm elsewhere: a 14-degree upper-arm jump).
	chain.lastGoal = goal
	rig.tips[chain.target] = tipWorld
	return math.min(upperWorld.Position.Y - extentY(upperWorld, chain.upperSize), lowerWorld.Position.Y - extentY(lowerWorld, chain.lowerSize), (tipWorld * chain.tipBox).Position.Y - extentY(tipWorld, chain.tipSize))
end

-- Applies a pose to a rig whose HumanoidRootPart has already been placed (fighter position + rootOffset).
-- floorY: world floor height (defaults to HRP height - RootHeight).
-- Knockdown whip limit (round 5), the last step of apply for the poses the knockdown smoother marks (lyingFrames): every
-- body part's rotation relative to the pelvis turns at most LyingJointDeg per frame (real time) from the previous shown
-- frame, parts processed from the pelvis outward (a clamped elbow carries its hand along), so neither a clip's fast
-- getup or roll nor the floor rules (hands caught on the floor, the settle of a lying spine, knee lifts) whip a limb.
-- Every apply records the parts' rotations, so a knockdown starting next frame has its reference.
MotionPlayer.LyingJointDeg = 26
-- Most a clamped leg is lifted about the hip in a frame to keep it out of the floor (degrees).
MotionPlayer.LyingLiftMaxDeg = 3.5
local CLAMP_CHAIN = {
	{ "Waist", "UpperTorso" }, { "Neck", "Head" },
	{ "LeftShoulder", "LeftUpperArm" }, { "LeftElbow", "LeftLowerArm" }, { "LeftWrist", "LeftHand" },
	{ "RightShoulder", "RightUpperArm" }, { "RightElbow", "RightLowerArm" }, { "RightWrist", "RightHand" },
	{ "LeftHip", "LeftUpperLeg" }, { "LeftKnee", "LeftLowerLeg" }, { "LeftAnkle", "LeftFoot" },
	{ "RightHip", "RightUpperLeg" }, { "RightKnee", "RightLowerLeg" }, { "RightAnkle", "RightFoot" },
}
-- Per rig: the clamp chain's motors with their fixed offsets and part names (only Transform is read per frame); leg
-- joints are grouped per side (`leg`).
local function clampJoints(rig: RigInfo): { any }
	local cached = (rig :: any).clampJoints
	if cached then return cached end
	local list = {}
	for _, j in CLAMP_CHAIN do
		local m = rig.motors[j[1]]
		if m and m.Part0 and m.Part1 then
			local side = string.match(j[1], "^(%a-)Hip$") or string.match(j[1], "^(%a-)Knee$") or string.match(j[1], "^(%a-)Ankle$")
			table.insert(list, { motor = m, part = j[2], parent = (m.Part0 :: BasePart).Name, child = (m.Part1 :: BasePart).Name, c0 = m.C0, c1i = m.C1:Inverse(), c1r = m.C1.Rotation, leg = side })
		end
	end
	(rig :: any).clampJoints = list
	return list
end
-- Lowest point of a leg (thigh, shin, foot box and shoe) in the world frames `world`: the oriented boxes' exact extent, so
-- a clamped leg is never shown lower than the solve rested it.
local function legLowest(rig: RigInfo, side: string, world: { [string]: CFrame }): number
	local chain = rig.chains[side .. "Leg"]
	local up, low, foot = world[side .. "UpperLeg"], world[side .. "LowerLeg"], world[side .. "Foot"]
	if not (chain and up and low and foot) then return math.huge end
	return math.min(boxBottom(up, chain.upperSize), boxBottom(low, chain.lowerSize), footBottom(chain, foot))
end
local function jointClamp(rig: RigInfo, pose: Pose, floorY: number?)
	local motors = rig.motors
	local rootPart = motors.Root.Part0
	if not rootPart then return end
	local root = motors.Root
	local pelvis = rootPart.CFrame * root.C0 * root.Transform * root.C1:Inverse()
	local pelvisRot = pelvis.Rotation
	local pelvisInv = pelvisRot:Inverse()
	local world: { [string]: CFrame } = { [(rig :: any).pelvisName or (root.Part1 :: BasePart).Name] = pelvis }
	if not (rig :: any).pelvisName then (rig :: any).pelvisName = (root.Part1 :: BasePart).Name end
	local rel: { [string]: any } = {}
	local prev = rig.lyingRel
	local clock = pose.real or pose.clock
	local frames = pose.lyingFrames
	local fresh = frames ~= nil and prev ~= nil and clock ~= nil and prev.t ~= nil and clock > prev.t and clock - prev.t < 0.1 and not pose.cut
	local limit = MotionPlayer.LyingJointDeg * (frames or 1)
	-- One joint from its solved transform tr0 with the turn limit lim (degrees); returns whether it was clamped.
	local function step(j: any, tr0: CFrame, lim: number): boolean
		local parent = world[j.parent]
		if not parent then return false end
		local m = j.motor
		local tr = tr0
		local child = parent * j.c0 * tr * j.c1i
		local r = pelvisInv * child.Rotation
		local before = if fresh then (prev :: any)[j.part] else nil
		local did = false
		if before then
			local limited = clampRotation(before, r, lim)
			if limited ~= r then
				local t = (parent * j.c0).Rotation:Inverse() * (pelvisRot * limited) * j.c1r
				tr = CFrame.new(tr.Position) * t
				child = parent * j.c0 * tr * j.c1i
				r = limited
				did = true
			end
		end
		m.Transform = tr
		world[j.child] = child
		rel[j.part] = r
		return did
	end
	local clamped = false
	local legs: { [string]: { any } } = {}
	for _, j in clampJoints(rig) do
		if j.leg then
			local list = legs[j.leg] or {}
			legs[j.leg] = list
			table.insert(list, j)
		elseif step(j, j.motor.Transform, limit) then
			clamped = true
		end
	end
	-- Legs: a clamped leg that would end up lower than the solve rested it (or below the floor) — a foot held at last frame's
	-- turn while the solver laid it down sank shoes 0.03-0.08 studs into the floor — is lifted rigidly about the hip by the
	-- least angle that clears it (at most LyingLiftMaxDeg: clamp and lift stay within the whip limit). Relaxing the clamp
	-- instead brought back the solver's foot flips (up to 146 deg in a frame).
	for side, list in legs do
		local orig = {}
		for i, j in list do orig[i] = j.motor.Transform end
		local any = false
		for i, j in list do
			if step(j, orig[i], limit) then any = true end
		end
		if any and floorY then
			local low = legLowest(rig, side, world)
			if low < (floorY :: number) + 0.02 then
				local clampedTr = {}
				for i, j in list do clampedTr[i] = j.motor.Transform end
				for i, j in list do step(j, orig[i], 181) end
				local need = math.min(floorY :: number, legLowest(rig, side, world))
				for i, j in list do step(j, clampedTr[i], 181) end
				local hipJ = list[1]
				local parent = world[hipJ.parent]
				local foot = world[side .. "Foot"]
				if low < need and parent and foot and string.find(hipJ.motor.Name, "Hip", 1, true) then
					local pivotCF = parent * hipJ.c0
					local pivot = pivotCF.Position
					local d = foot.Position - pivot
					local dh = Vector3.new(d.X, 0, d.Z)
					if dh.Magnitude > 0.05 then
						local axis = dh:Cross(Vector3.yAxis).Unit
						local upper0 = world[hipJ.child]
						local c1 = hipJ.motor.C1
						local function lift(theta: number): number
							local upperNew = CFrame.new(pivot) * CFrame.fromAxisAngle(axis, theta) * CFrame.new(-pivot) * upper0
							step(hipJ, pivotCF:Inverse() * upperNew * c1, 181)
							for i = 2, #list do step(list[i], clampedTr[i], 181) end
							return legLowest(rig, side, world)
						end
						local hi = math.rad(MotionPlayer.LyingLiftMaxDeg)
						if lift(hi) >= need then
							local lo = 0
							for _ = 1, 6 do
								local mid = (lo + hi) * 0.5
								if lift(mid) >= need then hi = mid else lo = mid end
							end
							lift(hi)
						end
					end
				end
			end
		end
		if any then clamped = true end
	end
	rel.t = clock
	rig.lyingRel = rel
	if clamped then
		for name in rig.tips do
			local w = world[name]
			if w then rig.tips[name] = w end
		end
	end
end

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
	-- Shown-frame clock (real time: it runs through the hitstop freeze, when impact fades still move the pose).
	rig.frameClock = if MotionPlayer.ContinuityRealTime then (pose.real or pose.clock) else pose.clock
	if pose.cut then
		for _, chain in rig.chains do
			chain.bendPrev, chain.bendRef, chain.bendClock = nil, nil, nil
			chain.flatPrev, chain.flatRef, chain.flatClock = nil, nil, nil
		end
	end
	local stepScale = pose.stepScale
	-- Lying body (heading-space clips with a floor-support weight): no sole-down foot flattening, shins rest on the
	-- floor, and after a knockdown/KO the feet relax (relaxFeet, see relaxLyingFoot).
	local lyingLegs = if headingSpace and ground > 0.5 then math.clamp((ground - 0.5) * 2, 0, 1) else 0
	-- The leg treatment switches over LyingLegsRamp seconds of real time (a throw clip's floor channel steps 0 -> 1
	-- at the impact frame: the feet turned 97 degrees in one frame).
	local tReal = pose.real or pose.clock
	local prevLying = rig.lyingLegs
	if tReal and prevLying and not pose.cut and tReal > prevLying.t and tReal - prevLying.t < 0.25 then
		local step = (tReal - prevLying.t) / MotionPlayer.LyingLegsRamp
		lyingLegs = prevLying.v + math.clamp(lyingLegs - prevLying.v, -step, step)
	end
	if tReal then rig.lyingLegs = { v = lyingLegs, t = tReal } end
	local relaxFeet = lyingLegs * math.clamp(pose.relaxFeet or 0, 0, 1)
	local prevRelax = rig.relaxFeet
	if tReal and prevRelax and not pose.cut and tReal > prevRelax.t and tReal - prevRelax.t < 0.25 then
		local step = (tReal - prevRelax.t) / MotionPlayer.RelaxFeetRamp
		relaxFeet = prevRelax.v + math.clamp(relaxFeet - prevRelax.v, -step, step)
	end
	if tReal then rig.relaxFeet = { v = relaxFeet, t = tReal } end
	-- Getup ankle range (clampAnkle): the getup clips' poses only (Pose.ankleRange).
	local ankleRange = if headingSpace and pose.ankleRange == true then 1 else 0
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
					nil, if chain.isLeg then lyingLegs else 0, if chain.isLeg then relaxFeet else 0, stepScale, if chain.isLeg then ankleRange else 0)
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
						low = math.min(low, solveChain(rig, chain, lowerFrame, heading, legFrame, effector, floor, footFlat, scale, headingSpace, if contacts then contacts[chain.target] or 0 else 0, s, lyingLegs, relaxFeet, nil, ankleRange))
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
	-- The knockdown whip limit runs last: it also bounds what the self clearance's pushes and elbow swivels turn (a swivel
	-- re-planes a nearly straight arm, twisting the upper arm and forearm far more than the pole moved).
	if MotionPlayer.SelfClearance and headingSpace then MotionPlayer.clearArms(rig, pose, floor) end
	jointClamp(rig, pose, floor)
end

-- Throw grips (FLThrow1 `grips`): call after BOTH fighters were applied this frame. Each active grip of this fighter's
-- role re-solves that limb so the hand centre / ankle reaches the partner's real body point (sizes differ from the
-- authored pair). Process the attacker before the defender: a defender's grip on the attacker then follows the
-- re-solved arm. Returns the number of limbs moved.
-- Grips take hold over at least GripFadeInMin and let go over at least GripReleaseMin seconds of clip time: a hand
-- let go over the authored 3 frames swung up to 160 degrees per frame from the partner's body back to its clip place.
MotionPlayer.GripFadeInMin = 0.05
MotionPlayer.GripReleaseMin = 0.15
local function gripWeight(g: ClipLibrary.Grip, t: number): number
	local fadeIn = math.max(g.fade, MotionPlayer.GripFadeInMin, 1e-3)
	local fadeOut = math.max(g.fade, MotionPlayer.GripReleaseMin, 1e-3)
	if t < g.from - fadeIn or t > g.to + fadeOut then return 0 end
	local w = 1
	if t < g.from then w = smoothstep((t - (g.from - fadeIn)) / fadeIn) elseif t > g.to then w = 1 - smoothstep((t - g.to) / fadeOut) end
	return w * g.weight
end
local function swapSide(name: string): string
	if string.sub(name, 1, 4) == "Left" then return "Right" .. string.sub(name, 5) end
	if string.sub(name, 1, 5) == "Right" then return "Left" .. string.sub(name, 6) end
	return name
end
-- An Ultimate strike's grip point is where a bare fist meets the partner's head or body; a boxing glove (and the
-- forearm behind it) is bigger. After the arm reaches the point, whatever of the glove/hand capsule or the lower arm is
-- still inside the partner's core (Motion.BodyShape) draws the point back toward the striker by that depth and the arm
-- solves again, as long as that helps (round 6 follow-up: Kael's overhand sank his glove into a smaller opponent's
-- head). Studs of residual allowed:
MotionPlayer.StrikeGripClearance = 0.02
local STRIKE_GRIP_PARTS = { Head = true, UpperTorso = true, LowerTorso = true }
local function modelOf(rig: RigInfo): Instance?
	local root = rig.motors.Root.Part0
	return root and root.Parent or nil
end
local function strikeGripDepth(rig: RigInfo, limb: string, partner: RigInfo, frames: { [string]: CFrame }): number
	local shape = BodyShape.of(rig, rig.parts, modelOf(rig))
	local pshape = BodyShape.of(partner, partner.parts, modelOf(partner))
	local tip = rig.tips[limb]
	local h = shape.hand[limb]
	if not tip or not h then return 0 end
	local a, b, r = BodyShape.handCapsule(h, tip)
	local worst = -math.huge
	for k = 0, 4 do worst = math.max(worst, r - (BodyShape.coreDistance(pshape, frames, a:Lerp(b, k / 4), false))) end
	local midName = if limb == "LeftHand" then "LeftLowerArm" else "RightLowerArm"
	local mid = rig.parts[midName]
	local midCF = partWorld(rig, midName)
	if mid and midCF then
		local mr = math.min(mid.Size.X, mid.Size.Z) * 0.4
		local half = midCF.UpVector * math.max(mid.Size.Y * 0.5 - mr, 0)
		for k = 0, 4 do worst = math.max(worst, mr - (BodyShape.coreDistance(pshape, frames, (midCF.Position + half):Lerp(midCF.Position - half, k / 4), false))) end
	end
	return worst
end
function MotionPlayer.applyGrips(rig: RigInfo, pose: Pose, view: FighterView, frame: any?, slot: number, partner: RigInfo, floorY: number): number
	local throw = view.throw
	local ultimate = Cinematic.isUltimate(throw)
	if type(throw) ~= "table" or throw.broken == true or (type(throw.move) ~= "string" and not ultimate) or pose.space ~= "heading" then return 0 end
	local defender = throw.role == "Defender"
	local characterId = if type(view.characterId) == "string" then view.characterId else ""
	local attackerId = if defender then (opponentId(frame, slot) or characterId) else characterId
	local tc = ClipLibrary.forThrow(attackerId, if ultimate then Cinematic.MOVE else throw.move)
	if not tc or not tc.grips then return 0 end
	local track = if defender then tc.defender else tc.attacker
	local t
	if ultimate then
		local tl = Cinematic.timeline(attackerId, throw)
		t = Cinematic.clipU(tc, tl, Cinematic.displayFrame(tl, if type(throw.frame) == "number" then throw.frame else 0)) * track.duration
	else
		local duration = if type(throw.duration) == "number" then throw.duration else 48
		local impactFrame = if type(throw.impactFrame) == "number" then throw.impactFrame else duration * 0.6
		t = MotionPlayer.throwTime(tc.impact, if type(throw.frame) == "number" then throw.frame else 0, impactFrame, duration) * track.duration
	end
	local role = if defender then "Defender" else "Attacker"
	local rootPart = rig.motors.Root.Part0
	if not rootPart then return 0 end
	local moved = 0
	local movedHands: { [string]: boolean } = {}
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
					if ultimate and not defender and not chain.isLeg and STRIKE_GRIP_PARTS[partName] then
						local frames: { [string]: CFrame } = {}
						for _, n in BodyShape.CORE do frames[n] = partWorld(partner, n) :: CFrame end
						local back = -hrp.LookVector
						local depth = strikeGripDepth(rig, limb, partner, frames)
						for _ = 1, 3 do
							if depth <= MotionPlayer.StrikeGripClearance then break end
							local before = point
							point += back * (depth * w + 0.01)
							grip.gripWorld = point
							solveChain(rig, chain, parent, heading, heading, grip, floorY, heading, scaleFromRoot(rig.rootHeight), true, 0, nil)
							local after = strikeGripDepth(rig, limb, partner, frames)
							if after >= depth - 0.005 then
								-- (no better: back to the last point)
								point = before
								grip.gripWorld = point
								solveChain(rig, chain, parent, heading, heading, grip, floorY, heading, scaleFromRoot(rig.rootHeight), true, 0, nil)
								break
							end
							depth = after
						end
					end
					moved += 1
					if not chain.isLeg then movedHands[limb] = true end
				end
			end
		end
	end
	rig.gripMoved = if next(movedHands) then movedHands else nil
	return moved
end

-- HumanoidRootPart frame of a fighter at sim position `pos` (arena space, Y = height above the floor) facing `facing`,
-- moved by the pose's root offset (heading space: +X right, +Y up, +Z forward), in a fight centred on `base`.
function MotionPlayer.rootCFrame(pos: Vector3, facing: Vector3, rootHeight: number, offset: Vector3, base: Vector3): CFrame
	if facing.Magnitude < 0.01 then error("MotionPlayer.rootCFrame received a zero facing vector") end
	local floorPos = Vector3.new(base.X + pos.X, base.Y, base.Z + pos.Z)
	local airborne = math.max(0, pos.Y)
	local forward = facing.Unit
	-- Library +X is the fighter's right (forward x up), the same axis MotionPlayer.apply uses for limb targets.
	local right = forward:Cross(Vector3.yAxis)
	if right.Magnitude < 0.01 then right = Vector3.xAxis else right = right.Unit end
	local center = floorPos + Vector3.new(0, rootHeight + airborne, 0) + right * offset.X + Vector3.yAxis * offset.Y + forward * offset.Z
	return CFrame.lookAt(center, center + forward)
end

-- Contact push-back (round 5). After the contact pass bent the striking limb as far as it can, whatever still sinks into
-- the partner (an elbow or knee strike's own joint, a hammer fist on a folded arm, a clip lunge that carries the body
-- past the target) is cleared by holding the attacker's body back along its facing by the residual depth (at most
-- ContactPushMax): the root moves back, the pose is applied again (planted feet stay locked in the world; the legs
-- re-solve under the shifted pelvis) and the contact pass runs once more. The hold grows as needed in the same frame —
-- the strike stops on the surface the frame it arrives — and lets go at ContactPushRelease per frame of animation time.
MotionPlayer.ContactPushBack = true
MotionPlayer.ContactPushMax = 0.8
MotionPlayer.ContactPushRelease = 0.04
-- Most the hold may grow in one frame (studs): a strike that would need more stays a little inside for a frame.
MotionPlayer.ContactPushRate = 0.15
local function pushBack(e: PresentEntry, pose: Pose, origin: Vector3, partner: RigInfo): boolean
	local residual = e.rig.contactResidual
	if not residual or residual <= 0.005 or type(e.view.move) ~= "string" or type(e.view.throw) == "table" then return false end
	local carried = pose.pushBack or 0
	local st = slotState(e.slot)
	-- The hold grows at most ContactPushRate per shown frame (sample resets pushGrow) during the startup; from the first
	-- active frame on the strike rests on the surface whatever it takes.
	local grown = st.pushGrow or 0
	local rateCap = math.huge
	local mv = e.view.moveFrame
	local def = if type(e.view.characterId) == "string" then Roster.getMove(e.view.characterId, rosterMoveKey(e.view.characterId, e.view.move :: string)) else nil
	if type(mv) == "number" and type(def) == "table" and type(def.startup) == "number" and mv <= def.startup then rateCap = MotionPlayer.ContactPushRate - grown end
	local extra = math.min(residual + 0.02, MotionPlayer.ContactPushMax - carried, rateCap)
	if extra <= 0.005 then return false end
	local total = carried + extra
	pose.rootOffset -= Vector3.new(0, 0, extra)
	pose.pushBack = total
	st.pushBack, st.pushAt, st.pushGrow = total, st.clock, grown + extra
	e.root.CFrame = MotionPlayer.rootCFrame(e.view.pos, e.view.facing, e.rig.rootHeight, pose.rootOffset, origin)
	MotionPlayer.apply(e.rig, pose, origin.Y)
	MotionPlayer.applyContact(e.rig, pose, e.view, partner, origin.Y)
	return true
end

-- Poses the two fighters of one render frame (CharacterPresenter, MotionQA): sample each view (slot = its index in
-- frame.fighters), place its root, apply the pose; once both bodies are posed, the throw grips (attacker first) and the
-- strike contact (a hand or foot never sinks into the opponent's head or torso).
export type PresentEntry = { rig: RigInfo, root: BasePart, view: FighterView, slot: number }
function MotionPlayer.presentFrame(entries: { PresentEntry? }, frame: any, origin: Vector3, config: any): { [number]: Pose? }
	local poses: { [number]: Pose? } = {}
	for i = 1, 2 do
		local e = entries[i]
		if e and e.view then
			local pose = MotionPlayer.sample(config, e.view, frame, e.slot)
			e.root.CFrame = MotionPlayer.rootCFrame(e.view.pos, e.view.facing, e.rig.rootHeight, pose.rootOffset, origin)
			MotionPlayer.apply(e.rig, pose, origin.Y)
			poses[i] = pose
		end
	end
	local a, b = entries[1], entries[2]
	if a and b and poses[1] and poses[2] then
		for pass = 1, 2 do
			for i = 1, 2 do
				local e = entries[i] :: PresentEntry
				local throw = e.view.throw
				if type(throw) == "table" and (throw.role ~= "Defender") == (pass == 1) then
					MotionPlayer.applyGrips(e.rig, poses[i] :: Pose, e.view, frame, e.slot, (entries[3 - i] :: PresentEntry).rig, origin.Y)
				end
			end
		end
		-- Round 5: a thrown defender's grip (a hand on the attacker's arm or shoulder, the bodies pressed together) re-solves
		-- the arm after the self clearance and drove the glove or forearm up to 0.35 studs into the defender's own chest:
		-- the gripping hands get their own clearance pass (its own push record), the grip giving way by the overlap.
		if MotionPlayer.SelfClearance and MotionPlayer.LyingSelfClear then
			for i = 1, 2 do
				local e = entries[i] :: PresentEntry
				local pose = poses[i] :: Pose
				if pose.defenderClear and (e.rig.gripMoved ~= nil or e.rig.selfPushGrip ~= nil) then
					MotionPlayer.clearArms(e.rig, pose, origin.Y, true, e.rig.gripMoved or {}, "selfPushGrip")
				end
			end
		end
		if MotionPlayer.StrikeContact then
			for i = 1, 2 do
				local e = entries[i] :: PresentEntry
				local partner = (entries[3 - i] :: PresentEntry).rig
				local moved = MotionPlayer.applyContact(e.rig, poses[i] :: Pose, e.view, partner, origin.Y)
				-- A strike its limb cannot bend clear (the elbow or knee itself, a folded hammer arm, a lunge that reaches past
				-- the target) holds the body back instead: the pose is applied again with the root moved back.
				if MotionPlayer.ContactPushBack and pushBack(e, poses[i] :: Pose, origin, partner) then
					moved = math.max(moved, 1)
				end
				-- A strike drawn back toward its shoulder must not end inside its own head or chest.
				-- Only the arms the contact pass drew back (the other arm is the clip's).
				if MotionPlayer.SelfClearance and (moved > 0 or e.rig.selfPushForced ~= nil) then MotionPlayer.clearArms(e.rig, poses[i] :: Pose, origin.Y, true, e.rig.contactMoved or {}) end
			end
		end
	end
	return poses
end

-- Strike contact. Attack clips do not know how close the opponent stands: at point-blank range (keepApart holds the
-- bodies 2.6 studs apart; a jab is built to land at 4.2) a fully extended fist went 0.5-1.5 studs into the opponent's
-- head. After both bodies are posed, every hand (glove) and foot of a fighter in an attack that sinks into the
-- partner's head, chest or pelvis deeper than ContactAllowance is drawn back along its reach — the limb re-solved
-- toward its shoulder/hip — until it rests on the surface: the elbow or knee bends instead. Throws are excluded (their
-- grips hold the partner). Returns the number of limbs moved.
MotionPlayer.StrikeContact = true
MotionPlayer.ContactAllowance = 0.05
MotionPlayer.ContactMaxRetract = 0.85
MotionPlayer.ContactMaxFlex = 135
-- Fraction of the reach a retraction may release per frame (a strike leaving the contact eases back to its clip).
MotionPlayer.ContactRelease = 0.1
local CONTACT_LIMBS = { LeftHand = "LeftArm", RightHand = "RightArm", LeftFoot = "LeftLeg", RightFoot = "RightLeg" }
local CONTACT_MID = { LeftHand = "LeftLowerArm", RightHand = "RightLowerArm", LeftFoot = "LeftLowerLeg", RightFoot = "RightLowerLeg" }
local function rigModel(rig: RigInfo): Instance?
	local root = rig.motors.Root.Part0
	return root and root.Parent or nil
end
-- Deepest point of a limb's striking end — the hand (glove) or foot and the forearm or shin behind it (a fist that
-- passed through a head leaves its forearm inside it) — inside the partner's core.
local function limbDepth(rig: RigInfo, shape: any, limb: string, pshape: any, frames: { [string]: CFrame }): number
	local tip = rig.tips[limb]
	if not tip then return -math.huge end
	local a, b, r
	if limb == "LeftHand" or limb == "RightHand" then
		local h = shape.hand[limb]
		if not h then return -math.huge end
		a, b, r = BodyShape.handCapsule(h, tip)
	else
		local chain = rig.chains[CONTACT_LIMBS[limb]]
		local size = chain.tipSize :: Vector3
		r = math.min(size.X, size.Y) * 0.45
		local len = math.max(size.Z * 0.5 - r, 0.01)
		local c = (tip * chain.tipBox).Position
		a, b = c + tip.LookVector * len, c - tip.LookVector * len
	end
	local worst = -math.huge
	for k = 0, 4 do
		local d = BodyShape.coreDistance(pshape, frames, a:Lerp(b, k / 4), false)
		worst = math.max(worst, r - d)
	end
	local midName = CONTACT_MID[limb]
	local mid = rig.parts[midName]
	local midCF = partWorld(rig, midName)
	if mid and midCF then
		local size = mid.Size
		local mr = math.min(size.X, size.Z) * 0.4
		local half = midCF.UpVector * math.max(size.Y * 0.5 - mr, 0)
		for k = 0, 4 do
			local d = BodyShape.coreDistance(pshape, frames, (midCF.Position + half):Lerp(midCF.Position - half, k / 4), false)
			worst = math.max(worst, mr - d)
		end
	end
	return worst
end
function MotionPlayer.applyContact(rig: RigInfo, pose: Pose, view: FighterView, partner: RigInfo, floorY: number): number
	local held = rig.contactHold
	local clock = rig.lockClock
	local striking = type(view.move) == "string"
	if striking and type(view.characterId) == "string" then
		-- A throw's grab reaches into the partner's clothes (the throw clip and its grips take over): no contact clamp.
		local ok, def = pcall(Roster.getMove, view.characterId, view.move)
		if ok and type(def) == "table" and def.height == "Throw" then striking = false end
	end
	if pose.space ~= "heading" or type(view.throw) == "table" or not (striking or held) then
		rig.contactHold = nil
		rig.contactMoved = nil
		rig.contactResidual = nil
		return 0
	end
	local shape = BodyShape.of(rig, rig.parts, rigModel(rig))
	local pshape = BodyShape.of(partner, partner.parts, rigModel(partner))
	local frames: { [string]: CFrame } = {}
	for _, name in BodyShape.CORE do
		local cf = partWorld(partner, name)
		if cf then frames[name] = cf end
	end
	local allow = MotionPlayer.ContactAllowance
	local maxRetract = MotionPlayer.ContactMaxRetract
	local nextHold = {}
	local moved = 0
	local movedLimbs: { [string]: boolean } = {}
	-- Deepest striking limb left inside the partner after the retraction (studs beyond the allowance; <= 0: clear).
	local residual = -math.huge
	local dbg = rig.debug
	for limb, chainName in CONTACT_LIMBS do
		local effector = pose.targets[limb]
		local chain = rig.chains[chainName]
		local depth = if effector and chain and striking then limbDepth(rig, shape, limb, pshape, frames) else -math.huge
		-- The previous frame's retraction, released by ContactRelease per frame of animation time (held in hitstop).
		local prev = held and held[limb]
		local floorS = 0
		if prev and clock and prev.clock and clock >= prev.clock and clock - prev.clock < 0.25 then
			floorS = math.max(0, prev.s - (clock - prev.clock) * 60 * MotionPlayer.ContactRelease)
		end
		if dbg then dbg["contact" .. limb] = { depth = depth, floor = floorS } end
		if effector and chain and (depth > allow or floorS > 0) then
			local motors = rig.motors
			local hrp = (motors.Root.Part0 :: BasePart).CFrame
			local lower = hrp * motors.Root.C0 * motors.Root.Transform * motors.Root.C1:Inverse()
			local parent = if chain.isLeg then lower else lower * motors.Waist.C0 * motors.Waist.Transform * motors.Waist.C1:Inverse()
			local pivot = (parent * motors[chain.joint].C0).Position
			local tipNow = rig.tips[limb] :: CFrame
			local reachPoint = if chain.isLeg then (tipNow * motors[chain.tip].C1).Position else tipNow.Position
			local heading = hrp.Rotation
			local steps = if dbg then {} else nil
			local function solveAt(s: number): number
				local grip = table.clone(effector)
				grip.gripWorld, grip.gripWeight = reachPoint:Lerp(pivot, s), 1
				solveChain(rig, chain, parent, heading, heading, grip, floorY, heading, scaleFromRoot(rig.rootHeight), true, 0, nil)
				local d = if striking then limbDepth(rig, shape, limb, pshape, frames) else -math.huge
				if steps then table.insert(steps, string.format("%.2f:%.2f", s, d)) end
				return d
			end
			local s = floorS
			-- The retraction never folds the elbow/knee past ContactMaxFlex (a crumpled arm reads worse than a fist
			-- resting slightly inside a point-blank target).
			local l1, l2 = chain.l1 :: number, chain.l2 :: number
			local dmin = math.sqrt(math.max(l1 * l1 + l2 * l2 + 2 * l1 * l2 * math.cos(math.rad(MotionPlayer.ContactMaxFlex)), 0))
			local dist = (reachPoint - pivot).Magnitude
			local maxS = math.clamp(if dist > 1e-3 then 1 - dmin / dist else 0, 0, maxRetract)
			s = math.min(s, maxS)
			if depth > allow and solveAt(s) > allow and maxS > s then
				-- Smallest retraction that clears the body (the limb drawn straight back usually leaves it the way it
				-- came); when none does within reach, the least deep one.
				local lo, hi = s, maxS
				if solveAt(hi) <= allow then
					for _ = 1, 6 do
						local m = (lo + hi) * 0.5
						if solveAt(m) <= allow then hi = m else lo = m end
					end
					s = hi
				else
					local best, bestD = s, math.huge
					for k = 0, 7 do
						local t = s + (maxS - s) * k / 7
						local d = solveAt(t)
						if d < bestD - 1e-3 then best, bestD = t, d end
					end
					s = best
				end
			end
			local finalDepth = solveAt(s)
			residual = math.max(residual, finalDepth - allow)
			if s > 0 then nextHold[limb] = { s = s, clock = clock } end
			if dbg then dbg["contact" .. limb].s = s; dbg["contact" .. limb].steps = table.concat(steps :: { string }, " ") end
			moved += 1
			movedLimbs[limb] = true
		elseif effector and chain and striking then
			residual = math.max(residual, depth - allow)
		end
	end
	rig.contactHold = if next(nextHold) then nextHold else nil
	rig.contactMoved = movedLimbs
	rig.contactResidual = if striking then residual else nil
	return moved
end

-- Self clearance of the arms. Clips authored on other proportions (or a guard retargeted onto boxing gloves) leave a
-- glove inside the own head or chest, or an elbow tucked into the ribs. After the pose is applied, an arm whose glove
-- or hand sinks into the own head (beyond SelfHeadAllowance) or torso, or whose forearm / lower upper arm centreline
-- runs inside the body (beyond SelfBodyAllowance), is re-solved with the hand moved out along the surface normal, up to
-- three passes (every push is proportional to the overlap, so it changes continuously from frame to frame). Returns
-- the arms moved.
MotionPlayer.SelfClearance = true
MotionPlayer.SelfHeadAllowance = 0.015
MotionPlayer.SelfBodyAllowance = 0.03
local ARM_LIMBS = { LeftHand = "LeftArm", RightHand = "RightArm" }
type SelfHit = { e: number, p: Vector3?, fn: ((Vector3) -> number)? }
-- Deepest excess penetration (studs beyond the allowance) of an arm's hand/glove and of its arm centreline into its
-- own body, with the point and the distance function to take the surface normal from.
local function armSelfDepth(rig: RigInfo, shape: any, frames: { [string]: CFrame }, limb: string): (SelfHit, SelfHit)
	local side = if limb == "LeftHand" then "Left" else "Right"
	local hand: SelfHit = { e = -math.huge }
	local arm: SelfHit = { e = -math.huge }
	local function headD(p: Vector3): number return BodyShape.partDistance(shape, "Head", frames.Head, p) end
	local function bodyD(p: Vector3): number return (BodyShape.coreDistance(shape, frames, p, true)) end
	local function allD(p: Vector3): number return (BodyShape.coreDistance(shape, frames, p, false)) end
	local tip = rig.tips[limb]
	local h = shape.hand[limb]
	if tip and h then
		local a, b = BodyShape.handCapsule(h, tip)
		for k = 0, 4 do
			local p = a:Lerp(b, k / 4)
			if frames.Head then
				local e = h.r - headD(p) - MotionPlayer.SelfHeadAllowance
				if e > hand.e then hand = { e = e, p = p, fn = headD } end
			end
			local e2 = h.r - bodyD(p) - MotionPlayer.SelfBodyAllowance
			if e2 > hand.e then hand = { e = e2, p = p, fn = bodyD } end
		end
	end
	for _, partName in { side .. "LowerArm", side .. "UpperArm" } do
		local part = rig.parts[partName]
		local cf = partWorld(rig, partName)
		if part and cf then
			local half = cf.UpVector * (part.Size.Y * 0.5)
			local top, bottom = cf.Position + half, cf.Position - half
			-- The shoulder half of the upper arm always sits under the deltoid.
			local from = if partName == side .. "UpperArm" then 0.5 else 0
			for k = 0, 4 do
				local p = top:Lerp(bottom, from + (1 - from) * k / 4)
				local e = -allD(p) - MotionPlayer.SelfBodyAllowance
				if e > arm.e then arm = { e = e, p = p, fn = allD } end
			end
		end
	end
	return hand, arm
end
local function sdfNormal(fn: (Vector3) -> number, p: Vector3): Vector3
	local h = 0.03
	local g = Vector3.new(
		fn(p + Vector3.xAxis * h) - fn(p - Vector3.xAxis * h),
		fn(p + Vector3.yAxis * h) - fn(p - Vector3.yAxis * h),
		fn(p + Vector3.zAxis * h) - fn(p - Vector3.zAxis * h))
	return safeUnit(g, Vector3.yAxis)
end
MotionPlayer.SelfPushRate = 0.05
-- Self clearance on the floor (knockdowns, getups, rolls, KO, thrown defenders) and its faster push rate (studs/frame).
MotionPlayer.LyingSelfClear = true
MotionPlayer.LyingPushRate = 0.3
MotionPlayer.LyingPushRamp = 6
MotionPlayer.DefenderSwivelRamp = 3
-- A defender breaking a throw gets the same clearance as a thrown one (its break pose pulls a glove into its chest).
MotionPlayer.DefenderClearBreak = true
-- Profile clearance (round 5). The player's own fight camera watches the local fighter's right side (that fighter always
-- stands on the left of the screen) from slightly in front and below; a guard's rear glove held at the cheek sat between
-- that camera and the face and hid Kael's nose and mouth (0-46% of his eye, nose and mouth landmarks visible in guard,
-- walk, backwalk and blockstun). In the states the self clearance runs in, the right glove (or hand) is moved off the
-- sight lines from the camera-side eye, nose and mouth (Motion.BodyShape.faceLandmarks) down along the jaw (a little
-- forward: back would drive it into the shoulder), by the least distance that clears them (ProfileMargin): the glove
-- stays at the chin, the profile reads. The push goes through the self clearance's rate-limited push.
MotionPlayer.ProfileClearance = true
MotionPlayer.ProfileHand = "RightHand"
MotionPlayer.ProfileMargin = 0.03
-- Share of the newly wanted profile shift taken each frame (the rest is the previous frame's shift).
MotionPlayer.ProfileSmooth = 0.5
-- How fast the shift lets go once the guard ends (studs per frame).
MotionPlayer.ProfileRelease = 0.04
-- Heading space (Roblox axes: +X right, +Y up, -Z toward the opponent): from the face toward the camera (the shot of a
-- close and of a mid-range spacing: the camera stands at the middle of the pair), and the push.
MotionPlayer.ProfileViews = { Vector3.new(0.995, -0.06, -0.07).Unit, Vector3.new(0.975, -0.06, -0.21).Unit }
MotionPlayer.ProfileDir = Vector3.new(0, -1, -0.25).Unit
local function pointSegDistance2(p: Vector2, a: Vector2, b: Vector2): number
	local ab = b - a
	local l2 = ab:Dot(ab)
	local t = if l2 > 1e-9 then math.clamp((p - a):Dot(ab) / l2, 0, 1) else 0
	return (p - (a + ab * t)).Magnitude
end
local function profileWant(rig: RigInfo, shape: any, frames: { [string]: CFrame }, limb: string, heading: CFrame): Vector3
	local head = rig.parts.Head
	local headCF = frames.Head
	local h = shape.hand[limb]
	local tip = rig.tips[limb]
	if not (head and headCF and h and tip) then return Vector3.zero end
	local a, b, r = BodyShape.handCapsule(h, tip)
	local need = r + MotionPlayer.ProfileMargin
	local best: Vector3 = Vector3.zero
	for _, view in MotionPlayer.ProfileViews do
		local d = heading:VectorToWorldSpace(view)
		local up = (Vector3.yAxis - d * d.Y).Unit
		local across = d:Cross(up)
		local function flat(p: Vector3): Vector2 return Vector2.new(p:Dot(across), p:Dot(up)) end
		local side = if headCF:VectorToObjectSpace(d).X >= 0 then 1 else -1
		local gloveDepth = math.max(a:Dot(d), b:Dot(d)) + r
		-- Landmarks the glove can hide (it is nearer the camera than they are).
		local pts = {}
		for _, lp in BodyShape.faceLandmarks(head, side) do
			local w = headCF:PointToWorldSpace(lp)
			if w:Dot(d) < gloveDepth then table.insert(pts, flat(w)) end
		end
		if #pts > 0 then
			local dir = heading:VectorToWorldSpace(MotionPlayer.ProfileDir)
			dir = (dir - d * dir:Dot(d)).Unit
			local dir2 = flat(dir)
			local a2, b2 = flat(a), flat(b)
			local function blocked(t: number): boolean
				local pa, pb = a2 + dir2 * t, b2 + dir2 * t
				for _, q in pts do
					if pointSegDistance2(q, pa, pb) < need then return true end
				end
				return false
			end
			local t = 0
			while t < 0.8 and blocked(t) do t += 0.02 end
			-- Refined (the shift follows the glove continuously instead of in 0.02 steps).
			if t > 0 and t < 0.8 then
				local lo, hi = t - 0.02, t
				for _ = 1, 4 do
					local mid = (lo + hi) * 0.5
					if blocked(mid) then lo = mid else hi = mid end
				end
				t = hi
			end
			if t > 0 and t > best.Magnitude then best = dir * t end
		end
	end
	return best
end
MotionPlayer._profileWant = profileWant
-- Push passes per arm and frame (each re-solves the arm once and re-measures the overlap).
MotionPlayer.SelfClearPasses = 3
-- Elbow swivel before the hand push (round 5): passes and how far each turns the pole along the body's outward normal.
MotionPlayer.ElbowSwivel = true
MotionPlayer.ElbowSwivelPasses = 4
MotionPlayer.ElbowSwivelGain = 0.6
-- The swivel starts before the arm touches the body (centreline this close to the surface, studs): the elbow is already
-- turning out when a throw's entry or a KO's impact fade carries it toward the chest.
MotionPlayer.ElbowSwivelMargin = 0.25
-- Most the swivel angle may change per frame (degrees): it builds up and lets go over a few frames.
MotionPlayer.ElbowSwivelRate = 10
-- An arm this deep inside the body (studs) doubles that rate (proportionally).
MotionPlayer.ElbowSwivelDeep = 0.08
-- Frames over which a push's base eases between the solve's goal and the landed hand (see clearArms).
MotionPlayer.SelfBaseFrames = 6
-- Most the elbow swivel may twist the upper arm about its own axis relative to the chest (degrees; the QA limit is 120).
MotionPlayer.SwivelTwistMax = 112
-- Twist of the upper arm about its long axis relative to the chest (degrees, 0-180: swing-twist, as MotionQA measures it).
local function upperArmTwist(rig: RigInfo, limb: string): number
	local side = if limb == "LeftHand" then "Left" else "Right"
	local ut, ua = partWorld(rig, "UpperTorso"), partWorld(rig, side .. "UpperArm")
	if not ut or not ua then return 0 end
	local ax, ang = (ut.Rotation:Inverse() * ua.Rotation):ToAxisAngle()
	local along = ax.Y * math.sin(ang * 0.5)
	local qw = math.cos(ang * 0.5)
	local len = math.sqrt(along * along + qw * qw)
	if len < 1e-9 then return 0 end
	local d = math.deg(2 * math.atan2(along / len, qw / len))
	while d > 180 do d -= 360 end
	while d < -180 do d += 360 end
	return math.abs(d)
end
function MotionPlayer.clearArms(rig: RigInfo, pose: Pose, floorY: number, force: boolean?, onlyLimbs: { [string]: boolean }?, record: string?): number
	local rootPart = rig.motors.Root.Part0
	if not rootPart then return 0 end
	-- Lying and getting up the hands push on the floor beside the body, attacks fold the arm on purpose: left to the clip
	-- (an existing push lets go gradually). `force`: a strike the contact pass drew back toward its own head.
	local ground = pose.ground or 0
	-- Round 5: on the floor too — knockdowns, getups, rolls and the KO (the knockdown smoother's poses, LyingSelfClear) and
	-- a thrown defender — the gloves and forearms are kept out of the own body (rolls drove them 0.4-0.7 studs into it); the
	-- push only moves a hand out along the body's surface, and the IK floor rules keep it above the floor.
	local lyingPush = MotionPlayer.LyingSelfClear and (pose.lyingFrames ~= nil or pose.defenderClear == true)
	local allowPush = force == true or (pose.selfClear == true and ground <= 0.5) or lyingPush
	-- The forced pass after a contact retraction (onlyLimbs: the arms the contact drew back) runs on top of the frame's
	-- first pass, so it keeps its own push: rate-limited from zero when it starts (it used to apply in full in one
	-- frame), and let go gradually once the contact releases (arms no longer listed).
	local forcedPass = onlyLimbs ~= nil
	-- Push record (continuity and rate limit): the frame's first pass, the contact's forced pass, a grip's pass.
	local recordKey = record or (if forcedPass then "selfPushForced" else "selfPush")
	local prevPush = (rig :: any)[recordKey]
	local clock = pose.real or pose.clock
	local fresh = prevPush ~= nil and clock ~= nil and prevPush.t ~= nil and not pose.cut and clock > prevPush.t and clock - prevPush.t < 0.25
	local shape = BodyShape.of(rig, rig.parts, rigModel(rig))
	local frames: { [string]: CFrame } = {}
	for _, name in BodyShape.CORE do
		local cf = partWorld(rig, name)
		if cf then frames[name] = cf end
	end
	local motors = rig.motors
	local hrp = (rootPart :: BasePart).CFrame
	local heading = hrp.Rotation
	local nextPush: { [string]: any } = { t = clock }
	-- Frames the floor / thrown-defender clearance has been on: its push rate and the elbow swivel's depth boost ramp in
	-- over LyingPushRamp frames (switching on at full rate turned a shoulder ~30 degrees on the first lying frame).
	local lyingN = if lyingPush then ((if fresh then (prevPush :: any).lyingN else nil) or 0) + 1 else nil
	nextPush.lyingN = lyingN
	-- (A thrown defender's clearance starts at full rate: the grab carries its arms across its chest within a few frames;
	-- a ramp left a slam's glove in the chest. Only its elbow swivel eases in over the throw's first DefenderSwivelRamp
	-- frames: at full rate on the first frame it turned a guard's tucked elbow out 20-30 deg in that frame.)
	local ramp = if lyingN and pose.lyingFrames == nil then 1 elseif lyingN then math.clamp((lyingN - 1) / math.max(MotionPlayer.LyingPushRamp, 1), 0, 1) else 0
	local swivelRamp = if lyingN and pose.lyingFrames == nil then math.clamp((lyingN :: number) / math.max(MotionPlayer.DefenderSwivelRamp, 1), 0, 1) else ramp
	local lyingRate = MotionPlayer.SelfPushRate + (MotionPlayer.LyingPushRate - MotionPlayer.SelfPushRate) * ramp
	local moved = 0
	for limb, chainName in ARM_LIMBS do
		local chain = rig.chains[chainName]
		local effector = pose.targets[limb]
		local limbPush = allowPush and (not forcedPass or (onlyLimbs :: any)[limb] == true)
		local kKey = limb .. "Base"
		if forcedPass and not limbPush and not (fresh and ((prevPush :: any)[limb] or (prevPush :: any)[kKey] or (prevPush :: any)[limb .. "Swivel"])) then
			-- The forced pass leaves an arm it never pushed alone.
			continue
		elseif chain and effector then
			-- Push base: the solve's own goal blended toward the hand where it landed (the solve misses its goal by up to
			-- ~0.1 studs). Re-solving from the landed hand gives the push a little extra outward travel that keeps elbows off
			-- the ribs, but switching to it in one frame re-landed the arm elsewhere (a 14-degree upper-arm jump when a push
			-- started): the base eases between the two over SelfBaseFrames as a push starts and ends.
			local tipPos = (rig.tips[limb] :: CFrame).Position
			local goalPos = chain.lastGoal or tipPos
			local frameStep = if fresh then math.max((clock - (prevPush :: any).t) * 60, 1) else 1
			local prevK = if fresh then ((prevPush :: any)[kKey] or 0) else 0
			local kStep = frameStep / math.max(MotionPlayer.SelfBaseFrames, 1)
			local kUp = math.min(1, prevK + kStep)
			local start = goalPos:Lerp(tipPos, kUp)
			local want = Vector3.zero
			local lower = hrp * motors.Root.C0 * motors.Root.Transform * motors.Root.C1:Inverse()
			local parent = lower * motors.Waist.C0 * motors.Waist.Transform * motors.Waist.C1:Inverse()
			local grip = table.clone(effector)
			local solvedAt: Vector3? = nil
			local function solveAt(offset: Vector3, base: Vector3?)
				local at = (base or start) + offset
				grip.gripWorld, grip.gripWeight = at, 1
				solveChain(rig, chain, parent, heading, heading, grip, floorY, heading, scaleFromRoot(rig.rootHeight), true, 0, nil)
				solvedAt = at
			end
			-- Profile clearance first (the self passes below keep the moved glove out of the own body).
			local profileOn = limbPush and MotionPlayer.ProfileClearance and limb == MotionPlayer.ProfileHand and pose.selfClear == true
			if profileOn then
				local pw = profileWant(rig, shape, frames, limb, heading)
				-- Smoothed: the wanted shift follows the glove's sway across the sight lines; taking it frame by frame
				-- zig-zagged Sierra's backwalk glove (3 reversals in 6 frames).
				local prevPw = if fresh then (prevPush :: any).profile else nil
				if prevPw then pw = heading:VectorToWorldSpace(prevPw):Lerp(pw, MotionPlayer.ProfileSmooth) end
				if pw.Magnitude > 1e-4 then
					nextPush.profile = heading:VectorToObjectSpace(pw)
					want += pw
					solveAt(want)
				end
			elseif limb == MotionPlayer.ProfileHand and fresh and (prevPush :: any).profile then
				-- Out of the guard (an attack, a throw) the shift lets go at ProfileRelease per frame: dropped at the self
				-- push's rate it added to the attack's first frame (Kael's hooks turned the shoulder 16 deg in that frame).
				local was = heading:VectorToWorldSpace((prevPush :: any).profile)
				local left = was.Magnitude - MotionPlayer.ProfileRelease * frameStep
				if left > 1e-3 then
					local pw = was.Unit * left
					nextPush.profile = heading:VectorToObjectSpace(pw)
					want += pw
					solveAt(want)
				end
			end
			-- Round 5 (on the floor and for a thrown defender; the standing guard keeps its tucked elbows): an elbow or upper
			-- arm inside the body (or within ElbowSwivelMargin of it) swivels out first — the pole (the elbow's bend
			-- direction) turns along the body's outward normal so the elbow comes out around the shoulder-hand line while the
			-- hand stays where the clip put it (pushing the hand instead swung a thrown defender's glove behind her back).
			-- The swivel angle (from the clip's pole) is kept per arm and changes at most ElbowSwivelRate per frame, also
			-- while it lets go after the body stood up.
			local swivelKey = limb .. "Swivel"
			local prevSwivel = if fresh then ((prevPush :: any)[swivelKey] or 0) else 0
			local swivelOn = MotionPlayer.ElbowSwivel and limbPush and lyingPush
			local hand: SelfHit?, arm: SelfHit? = nil, nil
			if swivelOn or (MotionPlayer.ElbowSwivel and prevSwivel > 0) then
				local h0, a0 = armSelfDepth(rig, shape, frames, limb)
				hand, arm = h0, a0
				local clipPole = heading:VectorToWorldSpace(libVector(grip.pole or defaultPole(limb)))
				local margin = -MotionPlayer.ElbowSwivelMargin
				local depth0 = if swivelOn then math.max(a0.e, 0) else 0
				local poleW = clipPole
				-- Warm start: last frame's swivel, a step relaxed (most frames then need no pass at all; the swivel lets go by
				-- itself once the arm stays clear).
				local lastAxis = if fresh and prevSwivel > 0 then (prevPush :: any)[swivelKey .. "Axis"] else nil
				if swivelOn and lastAxis then
					local relaxed = math.max(prevSwivel - math.rad(MotionPlayer.ElbowSwivelRate) * math.max(frameStep, 1), 0)
					if relaxed > 1e-4 then
						poleW = CFrame.fromAxisAngle(heading:VectorToWorldSpace(lastAxis), relaxed):VectorToWorldSpace(clipPole)
						grip.pole = libVector(heading:VectorToObjectSpace(poleW))
						solveAt(want)
						hand, arm = armSelfDepth(rig, shape, frames, limb)
					end
				end
				if swivelOn then
					for _ = 1, MotionPlayer.ElbowSwivelPasses do
						local a = arm :: SelfHit
						if a.e <= margin or not a.p or not a.fn then break end
						local n = sdfNormal(a.fn, a.p)
						poleW = safeUnit(poleW + n * MotionPlayer.ElbowSwivelGain, poleW)
						grip.pole = libVector(heading:VectorToObjectSpace(poleW))
						solveAt(want)
						hand, arm = armSelfDepth(rig, shape, frames, limb)
					end
				end
				local wantAngle = math.acos(math.clamp(clipPole:Dot(poleW), -1, 1))
				-- Faster while an arm is deep in the body (a slam swinging the arm through the chest in a frame or two).
				-- (It also ramps in with the floor clearance: a full-rate swivel on the first lying frame read as a shoulder jump.)
				local step = math.rad(MotionPlayer.ElbowSwivelRate * (0.3 + 0.7 * swivelRamp)) * math.max(frameStep, 1) * (1 + swivelRamp * depth0 / MotionPlayer.ElbowSwivelDeep)
				local angle = math.clamp(wantAngle, prevSwivel - step, prevSwivel + step)
				if math.abs(angle - wantAngle) > 1e-3 then
					-- Rate-limited: turn the clip's pole toward the wanted swivel by the allowed angle (a released swivel keeps
					-- its last axis: it relaxes back toward the clip's pole).
					local axis = clipPole:Cross(poleW)
					if axis.Magnitude < 1e-4 then
						local last = if fresh then (prevPush :: any)[swivelKey .. "Axis"] else nil
						axis = if last then heading:VectorToWorldSpace(last) else Vector3.zero
					end
					if axis.Magnitude > 1e-4 and angle > 1e-4 then
						poleW = CFrame.fromAxisAngle(axis.Unit, angle):VectorToWorldSpace(clipPole)
					else
						poleW, angle = clipPole, 0
					end
					grip.pole = libVector(heading:VectorToObjectSpace(poleW))
					solveAt(want)
					hand, arm = armSelfDepth(rig, shape, frames, limb)
				end
				-- The swivel never twists the upper arm about its own axis (relative to the chest) past SwivelTwistMax when the
				-- clip's own pole stays within it: turning the elbow out around an arm reaching overhead or behind the back
				-- twisted the shoulder 140-170 deg. (A clip pose already past the limit is left alone; so is a guarded swivel
				-- that would leave the arm deeper in the body — the self clearance comes first.)
				if angle > 1e-4 and MotionPlayer.SwivelTwistMax then
					local limit = MotionPlayer.SwivelTwistMax :: number
					local axis = clipPole:Cross(poleW)
					if upperArmTwist(rig, limb) > limit and axis.Magnitude > 1e-4 then
						axis = axis.Unit
						local fullAngle, fullPole = angle, poleW
						local fullDepth = math.max((hand :: SelfHit).e, (arm :: SelfHit).e)
						local function poleAt(a: number): Vector3 return CFrame.fromAxisAngle(axis, a):VectorToWorldSpace(clipPole) end
						grip.pole = libVector(heading:VectorToObjectSpace(clipPole))
						solveAt(want)
						local guarded = false
						if upperArmTwist(rig, limb) <= limit then
							local lo, hi = 0, angle
							for _ = 1, 5 do
								local mid = (lo + hi) * 0.5
								grip.pole = libVector(heading:VectorToObjectSpace(poleAt(mid)))
								solveAt(want)
								if upperArmTwist(rig, limb) <= limit then lo = mid else hi = mid end
							end
							grip.pole = libVector(heading:VectorToObjectSpace(poleAt(lo)))
							solveAt(want)
							local h2, a2 = armSelfDepth(rig, shape, frames, limb)
							if math.max(h2.e, a2.e) <= math.max(fullDepth, 0) + 0.01 then
								angle, poleW, hand, arm = lo, poleAt(lo), h2, a2
								guarded = true
							end
						end
						if not guarded then
							angle, poleW = fullAngle, fullPole
							grip.pole = libVector(heading:VectorToObjectSpace(poleW))
							solveAt(want)
						end
					end
				end
				if angle > 1e-4 then
					nextPush[swivelKey] = angle
					local axis = clipPole:Cross(poleW)
					if axis.Magnitude > 1e-4 then nextPush[swivelKey .. "Axis"] = heading:VectorToObjectSpace(axis.Unit) end
				end
			end
			if limbPush then
				if not hand or not arm then hand, arm = armSelfDepth(rig, shape, frames, limb) end
				local h, a = hand :: SelfHit, arm :: SelfHit
				for _ = 1, MotionPlayer.SelfClearPasses do
					if h.e <= 0 and a.e <= 0 then break end
					-- Every push is proportional to its overlap: the hand moves out along the surface normal; an arm inside
					-- the body moves the hand out further (it carries the elbow along only partly).
					if h.e > 0 and h.p and h.fn then want += sdfNormal(h.fn, h.p) * (h.e + 0.005) end
					if a.e > 0 and a.p and a.fn then want += sdfNormal(a.fn, a.p) * (a.e * 2.5 + 0.005) end
					solveAt(want)
					h, a = armSelfDepth(rig, shape, frames, limb)
				end
			end
			-- The push follows at most SelfPushRate studs per frame (heading space, so it turns with the body): a hand
			-- crossing the chest fast is not shoved aside in one frame, and a push lets go gradually.
			local shown = want
			local prev = if fresh then (prevPush :: any)[limb] else nil
			if prev then
				local was = heading:VectorToWorldSpace(prev)
				local rate = if lyingPush then lyingRate else MotionPlayer.SelfPushRate
				local maxStep = rate * math.max((clock - (prevPush :: any).t) * 60, 1)
				local d = want - was
				shown = if d.Magnitude > maxStep then was + d.Unit * maxStep else want
			elseif want.Magnitude > 0 and (fresh or (forcedPass and not pose.cut)) then
				local rate = if lyingPush then lyingRate else MotionPlayer.SelfPushRate
				shown = if want.Magnitude > rate then want.Unit * rate else want
			end
			local pushing = shown.Magnitude > 1e-4
			local k = if pushing then kUp else math.max(0, prevK - kStep)
			if pushing then
				if shown ~= want or solvedAt == nil then solveAt(shown) end
				nextPush[limb] = heading:VectorToObjectSpace(shown)
				moved += 1
			elseif k > 0 then
				-- The push is gone; the base eases back to the solve's goal.
				solveAt(Vector3.zero, goalPos:Lerp(tipPos, k))
				moved += 1
			elseif solvedAt ~= nil then
				solveAt(Vector3.zero, goalPos)
			end
			if k > 0 then nextPush[kKey] = k end
		end
	end
	if forcedPass then
		(rig :: any)[recordKey] = if nextPush.LeftHand or nextPush.RightHand or nextPush.LeftHandBase or nextPush.RightHandBase or nextPush.LeftHandSwivel or nextPush.RightHandSwivel then nextPush else nil
	else
		(rig :: any)[recordKey] = nextPush
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
	if slot then
		slots[slot] = nil
	else
		table.clear(slots)
		hitWindow.start, hitWindow.stop = nil, nil
	end
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
