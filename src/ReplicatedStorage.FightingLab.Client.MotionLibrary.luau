--!strict
local Library = {}

-- rot: optional hand/foot rotation relative to the fighter's heading frame (mocap clips); nil keeps the legacy
-- behaviour (hand aligned with the forearm, foot flattened when planted).
-- aimWorldY/aimWeight: contact aim toward a measured world height above the floor (set by MotionPlayer for attack clips
-- when the opponent's standing heights are known; MotionPlayer.apply corrects the IK goal with them).
-- gripWorld/gripWeight: throw grip, the hand centre / ankle goes to this world point (MotionPlayer.applyGrips).
export type Effector = { pos: Vector3, pole: Vector3?, orient: Vector3?, weight: number?, rot: CFrame?, aimWorldY: number?, aimWeight: number?, gripWorld: Vector3?, gripWeight: number?, sole: number? }
export type Keyframe = {
	t: number,
	rootOffset: Vector3?,
	rootRotation: Vector3?,
	waist: Vector3?,
	neck: Vector3?,
	targets: { [string]: Effector }?,
	plant: { [string]: number }?,
	ease: string?,
}
export type AnimParams = { side: string, height: string, crouch: boolean, spin: number, hop: number, lunge: number, scale: number, neutral: Keyframe, stance: string }

local function v(x: number, y: number, z: number): Vector3 return Vector3.new(x, y, z) end
local function a(x: number, y: number, z: number): Vector3 return Vector3.new(math.rad(x), math.rad(y), math.rad(z)) end
local function e(pos: Vector3, pole: Vector3?, orient: Vector3?, weight: number?): Effector return { pos = pos, pole = pole, orient = orient, weight = weight } end
local function k(t: number, rootOffset: Vector3?, rootRotation: Vector3?, waist: Vector3?, neck: Vector3?, targets: { [string]: Effector }?, plant: { [string]: number }?, ease: string?): Keyframe
	return { t = t, rootOffset = rootOffset, rootRotation = rootRotation, waist = waist, neck = neck, targets = targets, plant = plant, ease = ease }
end

Library.v = v
Library.a = a
Library.e = e
Library.k = k
Library.Joints = { "Root", "Waist", "Neck", "LeftShoulder", "LeftElbow", "LeftWrist", "RightShoulder", "RightElbow", "RightWrist", "LeftHip", "LeftKnee", "LeftAnkle", "RightHip", "RightKnee", "RightAnkle" }
Library.DefaultTargets = {
	LeftHand = e(v(-0.42, 1.34, 0.82), v(-0.75, -0.85, 0.08), nil, 1),
	RightHand = e(v(0.36, 1.12, 0.42), v(0.75, -0.85, 0.04), nil, 1),
	LeftFoot = e(v(-0.28, -3.10, 0.68), v(-0.25, 0.05, 1.0), nil, 1),
	RightFoot = e(v(0.30, -3.10, -0.58), v(0.25, 0.05, 1.0), nil, 1),
}
local both = { LeftFoot = 0, RightFoot = 0 }
local airborne = { LeftFoot = 0.8, RightFoot = 0.8 }

-- Fighting guards: fists in front of the chin with elbows tucked (lp/rp poles point down), a bladed torso, staggered
-- feet and bent knees. `drop` lowers the root so the planted legs flex instead of standing at full extension.
local styleData = {
	boxer = { root = a(-3, -16, 0), waist = a(-7, -20, -2), neck = a(6, 28, 0), lh = v(-0.02, 1.28, 0.92), rh = v(0.10, 1.32, 0.58), lp = v(-0.25, -1, 0.2), rp = v(0.3, -1, 0.1), lf = v(-0.26, -3.1, 0.62), rf = v(0.30, -3.1, -0.52), drop = 0.26, bounce = 1.0 },
	kickboxer = { root = a(-2, -24, 0), waist = a(-4, -22, -2), neck = a(4, 34, 0), lh = v(-0.06, 1.26, 0.96), rh = v(0.12, 1.30, 0.58), lp = v(-0.25, -1, 0.2), rp = v(0.3, -1, 0.1), lf = v(-0.22, -3.1, 0.78), rf = v(0.34, -3.1, -0.70), drop = 0.22, bounce = 0.75 },
	grappler = { root = a(-8, -8, 0), waist = a(-10, -8, 0), neck = a(14, 12, 0), lh = v(-0.34, 1.00, 1.04), rh = v(0.32, 0.94, 0.92), lp = v(-0.6, -1, 0), rp = v(0.6, -1, 0), lf = v(-0.48, -3.1, 0.52), rf = v(0.52, -3.1, -0.52), drop = 0.28, bounce = 0.25 },
	-- Open-hand guards sit at chest height (open palms at the chin read as covering the mouth). Targets are shoulder-relative
	-- and the bladed torso pulls the rear shoulder back, so rear-hand targets reach further forward and across than they land.
	flow = { root = a(-2, -18, -3), waist = a(-3, -20, -4), neck = a(4, 28, 4), lh = v(-0.30, 0.98, 1.00), rh = v(-0.36, 0.78, 1.04), lp = v(-0.6, -1, 0.1), rp = v(0.6, -1, 0), lf = v(-0.34, -3.1, 0.72), rf = v(0.30, -3.1, -0.60), drop = 0.28, bounce = 1.25 },
	karate = { root = a(-1, -30, 0), waist = a(-2, -26, 0), neck = a(2, 44, 0), lh = v(-0.10, 1.16, 1.14), rh = v(0.40, 0.30, -0.06), lp = v(-0.3, -1, 0.15), rp = v(0.6, -0.6, -0.6), lf = v(-0.24, -3.1, 0.95), rf = v(0.30, -3.1, -0.85), drop = 0.30, bounce = 0.1 },
	-- Kung fu: lead palm extended high, rear palm low in front of the stomach (a clear high/low split, never palms together).
	kungfu = { root = a(-4, -20, 0), waist = a(-4, -18, 2), neck = a(6, 30, -2), lh = v(-0.39, 1.24, 1.12), rh = v(-0.27, 0.60, 0.99), lp = v(-0.6, -1, 0), rp = v(0.6, -1, 0), lf = v(-0.40, -3.1, 0.60), rf = v(0.40, -3.1, -0.56), drop = 0.34, bounce = 0.45 },
}

local function scaledTargets(data: any, scale: number): { [string]: Effector }
	return {
		LeftHand = e(data.lh * scale, data.lp or v(-0.75, -0.85, 0.08), nil, 1),
		RightHand = e(data.rh * scale, data.rp or v(0.75, -0.85, 0.04), nil, 1),
		LeftFoot = e(data.lf * scale, v(-0.25, 0.05, 1), nil, 1),
		RightFoot = e(data.rf * scale, v(0.25, 0.05, 1), nil, 1),
	}
end

function Library.stanceKey(stance: string?, state: string?, scale: number?): Keyframe
	local s = scale or 1
	local data = styleData[stance or "boxer"] or styleData.boxer
	local st = state or "Idle"
	local drop = (data.drop or 0.06) * s
	local rootOffset = v(0, -drop, 0)
	local rootRotation = data.root
	local waist = data.waist
	local neck = data.neck
	local targets = scaledTargets(data, s)
	local plant = both
	if st == "Guard" or st == "Block" or st == "Blockstun" then
		-- Covering guard: fists raised to the temples with forearms in front of the face.
		targets.LeftHand = e(v(-0.12, 1.50, 0.62) * s, v(-0.2, -1, 0.3), nil, 1)
		targets.RightHand = e(v(0.14, 1.52, 0.50) * s, v(0.2, -1, 0.3), nil, 1)
	elseif st == "Crouch" or st == "CrouchGuard" then
		rootOffset = v(0, -0.82 * s, -0.06 * s)
		rootRotation = a(12, -7, 0)
		waist = a(26, -12, 0)
		neck = a(-6, 14, 0)
		targets.LeftHand = e(v(-0.20, 1.02, 0.50) * s, v(-0.65, -0.75, 0.05), nil, 1)
		targets.RightHand = e(v(0.22, 0.92, 0.36) * s, v(0.65, -0.75, 0.05), nil, 1)
	elseif st == "Dash" then
		rootOffset = v(0, 0.02 * s - drop, 0.22 * s)
		rootRotation += a(-7, 0, 0)
	elseif st == "Backdash" then
		rootOffset = v(0, 0.04 * s - drop, -0.22 * s)
		rootRotation += a(6, 18, 0)
	elseif st == "SidestepIn" then
		rootOffset = v(-0.24 * s, -drop, 0)
		rootRotation += a(0, -16, -7)
	elseif st == "SidestepOut" then
		rootOffset = v(0.24 * s, -drop, 0)
		rootRotation += a(0, 16, 7)
	end
	return k(0, rootOffset, rootRotation, waist, neck, targets, plant)
end

Library.StanceStyles = styleData
Library.StancePose = Library.stanceKey("boxer", "Idle", 1)
Library.StatePoses = {
	Idle = Library.StancePose,
	Guard = Library.stanceKey("boxer", "Guard", 1),
	BlockHigh = Library.stanceKey("boxer", "Block", 1),
	Crouch = Library.stanceKey("boxer", "Crouch", 1),
	CrouchGuard = Library.stanceKey("boxer", "CrouchGuard", 1),
	Dash = Library.stanceKey("boxer", "Dash", 1),
	Backdash = Library.stanceKey("boxer", "Backdash", 1),
	SidestepIn = Library.stanceKey("boxer", "SidestepIn", 1),
	SidestepOut = Library.stanceKey("boxer", "SidestepOut", 1),
	HitHigh = k(0, v(0, 0.04, -0.18), a(0, -18, -4), a(8, -24, -8), a(30, -36, -10), nil, both),
	HitMid = k(0, v(0, -0.10, -0.22), a(14, 7, 0), a(38, 6, 0), a(-18, -10, 0), nil, both),
	HitLow = k(0, v(0.05, -0.50, -0.12), a(15, 5, 16), a(14, 8, 12), a(10, -10, -6), nil, both),
	Airborne = k(0, v(0, 0.55, -0.20), a(28, 38, -34), a(18, 20, -16), a(-10, -14, 8), nil, airborne),
	Landing = k(0, v(0, -0.86, -0.12), a(58, 8, -12), a(30, 4, 10), a(-24, -6, -8), nil, both),
	Getup = k(0, v(0, -0.48, -0.08), a(25, -8, 4), a(30, -12, 0), a(12, 8, 0), nil, both),
	KO = k(0, v(0, -1.20, -0.28), a(86, 8, -22), a(24, 0, 18), a(-34, 0, -18), nil, both),
	Ready = k(0, v(0, 0.04, 0), a(0, -12, 0), a(-12, -18, -2), a(-4, 16, 0), nil, both),
	Victory = k(0, v(0, 0.08, 0), a(-4, -14, 0), a(-12, -16, 0), a(-8, 12, 0), { LeftHand = e(v(-0.22, 2.28, 0.42), v(-0.55, -0.4, 0.05), nil, 1), RightHand = e(v(0.34, 1.04, 0.42), v(0.65, -0.8, 0.05), nil, 1) }, both),
	Defeat = k(0, v(0, -0.92, -0.10), a(18, 0, 10), a(34, -10, 0), a(18, -16, 0), nil, both),
}
Library.HitReactions = { High = Library.StatePoses.HitHigh, Mid = Library.StatePoses.HitMid, Low = Library.StatePoses.HitLow }
Library.MoveKeyframes = {}

function Library.copyKey(key: Keyframe): Keyframe
	local targets: { [string]: Effector }? = nil
	if key.targets then
		targets = {}
		for name, target in key.targets do targets[name] = { pos = target.pos, pole = target.pole, orient = target.orient, weight = target.weight, rot = target.rot } end
	end
	return { t = key.t, rootOffset = key.rootOffset, rootRotation = key.rootRotation, waist = key.waist, neck = key.neck, targets = targets, plant = key.plant, ease = key.ease }
end

function Library.contactY(height: string, scale: number): number
	if height == "High" then return 1.75 * scale end
	if height == "Low" then return -2.45 * scale end
	return 0.55 * scale
end

return Library
