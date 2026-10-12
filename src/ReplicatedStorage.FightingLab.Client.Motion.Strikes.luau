--!strict
-- Original FightingLab strike archetypes: fast impact curves with per-key easing.

export type Effector = { pos: Vector3, pole: Vector3?, orient: Vector3?, weight: number? }
export type Keyframe = { t: number, rootOffset: Vector3?, rootRotation: Vector3?, waist: Vector3?, neck: Vector3?, targets: { [string]: Effector }?, plant: { [string]: number }?, ease: string? }
export type AnimParams = { side: "Lead" | "Rear", height: "High" | "Mid" | "Low", crouch: boolean, spin: number, hop: number, lunge: number, scale: number, neutral: Keyframe, stance: string }

type Plant = { [string]: number }
type Targets = { [string]: Effector }
type Spec = { reach: number, x: number, arc: number, chamberY: number, chamberZ: number, guardY: number, guardZ: number, twist: number, roll: number, pitch: number, recoil: number, highArc: number?, lowDrop: number?, rearHeel: boolean?, shoulder: boolean?, parry: boolean?, hop: number?, lungeMul: number?, circular: number? }

local Strikes: { [string]: (AnimParams) -> { Keyframe } } = {}
local BOTH: Plant = { LeftFoot = 0, RightFoot = 0 }
local LEAD_PLANT: Plant = { LeftFoot = 0, RightFoot = 0.12 }
local REAR_PLANT: Plant = { LeftFoot = 0.08, RightFoot = 0 }
local HOP_PLANT: Plant = { LeftFoot = 0.55, RightFoot = 0.55 }

local styleBias = {
	boxer = { tight = 0.86, bounce = 0.10, blade = 0.0, circle = 0.80 },
	kickboxer = { tight = 1.05, bounce = 0.06, blade = 0.05, circle = 0.92 },
	grappler = { tight = 0.78, bounce = -0.08, blade = -0.02, circle = 0.70 },
	flow = { tight = 1.08, bounce = 0.16, blade = 0.08, circle = 1.20 },
	karate = { tight = 1.12, bounce = -0.02, blade = 0.14, circle = 0.62 },
	kungfu = { tight = 1.00, bounce = 0.08, blade = 0.10, circle = 1.35 },
}

local function v(x: number, y: number, z: number): Vector3 return Vector3.new(x, y, z) end
local function a(x: number, y: number, z: number): Vector3 return Vector3.new(math.rad(x), math.rad(y), math.rad(z)) end
local function e(pos: Vector3, pole: Vector3?, orient: Vector3?, weight: number?): Effector return { pos = pos, pole = pole, orient = orient, weight = weight } end
local function k(t: number, rootOffset: Vector3?, rootRotation: Vector3?, waist: Vector3?, neck: Vector3?, targets: Targets?, plant: Plant?, ease: string?): Keyframe return { t = t, rootOffset = rootOffset, rootRotation = rootRotation, waist = waist, neck = neck, targets = targets, plant = plant or BOTH, ease = ease } end
local function contactY(height: string, scale: number): number if height == "High" then return 1.75 * scale elseif height == "Low" then return -2.45 * scale end return 0.55 * scale end
local function sideInfo(side: string): (number, string, string) if side == "Lead" then return -1, "LeftHand", "RightHand" end return 1, "RightHand", "LeftHand" end
local function pole(side: number, lift: number?, zed: number?): Vector3 return v(0.78 * side, -0.78 + (lift or 0), zed or 0.16) end
local function scalePos(pos: Vector3, scale: number): Vector3 return v(pos.X * scale, pos.Y * scale, pos.Z * scale) end
local function copyNeutral(neutral: Keyframe, t: number): Keyframe
	return { t = t, rootOffset = neutral.rootOffset, rootRotation = neutral.rootRotation, waist = neutral.waist, neck = neutral.neck, targets = neutral.targets, plant = neutral.plant, ease = "out" }
end
local function guard(side: number, scale: number, y: number, zed: number): Effector return e(v(-0.24 * side * scale, y * scale, zed * scale), pole(-side, 0.04, 0.08), nil, 1) end
local function feet(scale: number, side: number, rearHeel: boolean?, step: number?): Targets
	local stepZ = step or 0
	return {
		LeftFoot = e(v(-0.30 * scale, -3.10 * scale, (0.70 + stepZ) * scale), v(-0.25, 0.05, 1), nil, 1),
		RightFoot = e(v(0.32 * scale, (if rearHeel then -2.86 else -3.10) * scale, (-0.62 - stepZ * 0.35 + (if rearHeel then 0.12 else 0)) * scale), v(0.25, 0.05, 1), nil, 1),
	}
end
local function merge(base: Targets, extra: Targets): Targets local out: Targets = {}; for n,t in base do out[n] = t end; for n,t in extra do out[n] = t end; return out end

local function make(spec: Spec): (AnimParams) -> { Keyframe }
	return function(p: AnimParams): { Keyframe }
		local scale = if p.scale > 0 then p.scale else 1
		local bias = styleBias[p.stance] or styleBias.boxer
		local side, hitHand, guardHand = sideInfo(p.side)
		local y = contactY(p.height, scale)
		local crouch = if p.crouch or p.height == "Low" then (spec.lowDrop or 0.70) else 0
		local lunge = math.min((p.lunge or 0) * (spec.lungeMul or 0.36), 0.86)
		local hop = (p.hop or 0) + (spec.hop or 0) + bias.bounce
		local chamberT = if spec.parry then 0.28 else 0.42
		local midT = 0.90
		local twist = spec.twist * side * bias.tight
		local circle = (spec.circular or 0) * bias.circle
		local step = math.max(0, lunge) * 0.45
		local hitZ = (spec.reach + lunge) * scale
		local chamber = e(v(spec.x * side * 0.45 * scale, (spec.chamberY * scale) + y * 0.10, spec.chamberZ * scale), pole(side, 0.18, 0.18), nil, 1)
		local mid = e(v(spec.x * side * 0.72 * scale, y - 0.04 * scale, (spec.reach * 0.62 + lunge * 0.65) * scale), pole(side, 0.10, 0.18), nil, 1)
		local contact = e(v(spec.x * side * scale, y, hitZ), pole(side, 0.02, 0.22), a(0, 0, spec.roll * side), 1)
		local over = e(v((spec.x + spec.arc) * side * scale, y + (spec.highArc or 0) * scale, (spec.reach + lunge + 0.20) * scale), pole(side, -0.04, 0.28), a(0, 0, spec.roll * 1.1 * side), 1)
		local recoil = e(v((spec.x - spec.arc * 0.25) * side * scale, y + 0.10 * scale, (spec.reach - spec.recoil) * scale), pole(side, 0.14, 0.16), nil, 1)
		local guardNear = guard(side, scale, spec.guardY, spec.guardZ)
		local guardFar = guard(side, scale, spec.guardY + 0.05, spec.guardZ - 0.08)
		local f0 = feet(scale, side, false, 0)
		local fStep = feet(scale, side, spec.rearHeel == true and p.side == "Rear", step)
		local plant = if (p.hop or 0) > 0.3 then HOP_PLANT elseif p.side == "Rear" then REAR_PLANT else LEAD_PLANT
		if spec.shoulder then
			contact = guard(side, scale, 1.18, 0.74)
			over = guard(side, scale, 1.12, 0.94)
		end
		if spec.parry then
			contact = e(v(0.62 * side * scale, contactY("High", scale), 1.24 * scale), pole(side, 0.12, 0.18), a(0, 0, -28 * side), 1)
			over = e(v(0.70 * side * scale, contactY("High", scale) - 0.03 * scale, 1.34 * scale), pole(side, 0.08, 0.22), a(0, 0, -32 * side), 1)
		end
		local antRoot = v(0.04 * side * scale, (-0.03 - crouch * 1.05 + hop * 0.18) * scale, (-0.10 + lunge * 0.10) * scale)
		local midRoot = v(-0.02 * side * scale, (-0.01 - crouch * 0.85 + hop * 0.35) * scale, (0.10 + lunge * 0.45) * scale)
		local hitRoot = v(-0.06 * side * scale, (0.04 - crouch * 0.95 + hop * 0.70) * scale, (0.22 + lunge) * scale)
		local overRoot = v(-0.09 * side * scale, (0.02 - crouch * 0.55 + hop * 0.35) * scale, (0.18 + lunge * 0.70) * scale)
		local recRoot = v(0.02 * side * scale, (-0.02 - crouch * 0.10) * scale, -0.02 * scale)
		local contactTargets: Targets = { [hitHand] = contact, [guardHand] = guardFar }
		if spec.shoulder then contactTargets.Body = e(v(0.44 * side * scale, 0.55 * scale, (1.55 + lunge) * scale), Vector3.yAxis, nil, 1) end
		return {
			copyNeutral(p.neutral, 0),
			k(chamberT, antRoot, a(spec.pitch * 0.35, -twist * 0.45 + circle, -spec.roll * 0.20 * side), a(spec.pitch * 0.42, -twist * 0.58 + circle, -spec.roll * 0.28 * side), a(4, twist * 0.24, 0), merge(f0, { [hitHand] = chamber, [guardHand] = guardNear }), BOTH, "out"),
			k(midT, midRoot, a(spec.pitch * 0.55, twist * 0.35 + circle, -spec.roll * 0.35 * side), a(spec.pitch * 0.60, twist * 0.55 + circle, -spec.roll * 0.42 * side), a(3, -twist * 0.20, 0), merge(fStep, { [hitHand] = mid, [guardHand] = guardFar }), plant, "linear"),
			k(1.00, hitRoot, a(spec.pitch, twist + circle, -spec.roll * side), a(spec.pitch * 1.15, twist * 1.18 + circle, -spec.roll * 0.90 * side), a(4, -twist * 0.36, 0), merge(fStep, contactTargets), plant, "in"),
			k(1.18, overRoot, a(spec.pitch * 0.85, twist * 1.16 + circle, -spec.roll * 0.82 * side), a(spec.pitch, twist * 1.24 + circle, -spec.roll * 0.72 * side), nil, merge(fStep, { [hitHand] = over, [guardHand] = guardFar }), plant, "linear"),
			k(1.48, overRoot * 0.72, a(spec.pitch * 0.55, twist * 0.94 + circle, -spec.roll * 0.50 * side), a(spec.pitch * 0.62, twist, -spec.roll * 0.42 * side), nil, merge(fStep, { [hitHand] = over, [guardHand] = guardFar }), plant, "hold"),
			k(2.16, recRoot, a(spec.pitch * 0.16, twist * 0.22, -spec.roll * 0.10 * side), a(spec.pitch * 0.18, twist * 0.20, -spec.roll * 0.08 * side), nil, merge(f0, { [hitHand] = recoil, [guardHand] = guardNear }), BOTH, "out"),
			copyNeutral(p.neutral, 3),
		}
	end
end

Strikes.straight = make({ reach=2.80, x=0.10, arc=0.05, chamberY=1.02, chamberZ=0.24, guardY=1.34, guardZ=0.36, twist=42, roll=6, pitch=-8, recoil=0.62, rearHeel=true, lungeMul=0.58 })
Strikes.hook = make({ reach=2.26, x=0.78, arc=0.34, chamberY=1.02, chamberZ=0.18, guardY=1.36, guardZ=0.38, twist=64, roll=72, pitch=-7, recoil=0.46, highArc=0.02, rearHeel=true, lungeMul=0.38, circular=8 })
Strikes.uppercut = make({ reach=2.18, x=0.14, arc=0.04, chamberY=0.24, chamberZ=0.34, guardY=1.26, guardZ=0.36, twist=38, roll=10, pitch=-26, recoil=0.54, highArc=0.48, lowDrop=0.82, rearHeel=true, lungeMul=0.30 })
Strikes.overhand = make({ reach=2.52, x=0.24, arc=0.12, chamberY=1.92, chamberZ=0.02, guardY=1.30, guardZ=0.36, twist=70, roll=22, pitch=20, recoil=0.58, highArc=-0.38, rearHeel=true, lungeMul=0.44, circular=5 })
Strikes.body_hook = make({ reach=2.04, x=0.68, arc=0.25, chamberY=0.42, chamberZ=0.20, guardY=1.24, guardZ=0.36, twist=66, roll=78, pitch=18, recoil=0.42, lowDrop=0.70, rearHeel=true, lungeMul=0.30, circular=8 })
Strikes.weave_hook = make({ reach=2.28, x=0.86, arc=0.40, chamberY=0.44, chamberZ=0.14, guardY=1.35, guardZ=0.34, twist=78, roll=74, pitch=-4, recoil=0.42, lowDrop=0.60, rearHeel=true, lungeMul=0.34, circular=12 })
Strikes.palm = make({ reach=2.58, x=0.18, arc=0.08, chamberY=1.08, chamberZ=0.26, guardY=1.30, guardZ=0.40, twist=34, roll=-64, pitch=-5, recoil=0.56, rearHeel=true, lungeMul=0.42 })
Strikes.chop = make({ reach=2.40, x=0.24, arc=0.12, chamberY=1.86, chamberZ=0.20, guardY=1.34, guardZ=0.36, twist=48, roll=54, pitch=16, recoil=0.48, highArc=-0.30, lungeMul=0.34 })
Strikes.backfist = make({ reach=2.48, x=0.54, arc=0.30, chamberY=1.04, chamberZ=0.14, guardY=1.36, guardZ=0.34, twist=-60, roll=-92, pitch=-4, recoil=0.52, lungeMul=0.36, circular=12 })
Strikes.spinning_backfist = make({ reach=2.64, x=0.58, arc=0.36, chamberY=1.00, chamberZ=0.16, guardY=1.32, guardZ=0.34, twist=360, roll=-96, pitch=-7, recoil=0.56, lungeMul=0.42, circular=30 })
Strikes.elbow = make({ reach=1.86, x=0.48, arc=0.18, chamberY=1.26, chamberZ=0.14, guardY=1.34, guardZ=0.38, twist=62, roll=96, pitch=-8, recoil=0.34, rearHeel=true, lungeMul=0.52 })
Strikes.hammer_fist = make({ reach=2.34, x=0.26, arc=0.08, chamberY=1.88, chamberZ=-0.02, guardY=1.28, guardZ=0.36, twist=60, roll=24, pitch=24, recoil=0.52, highArc=-0.44, rearHeel=true, lungeMul=0.42 })
Strikes.superman_punch = make({ reach=2.92, x=0.14, arc=0.08, chamberY=1.00, chamberZ=0.12, guardY=1.30, guardZ=0.34, twist=48, roll=8, pitch=-12, recoil=0.72, rearHeel=false, hop=0.36, lungeMul=0.78 })
Strikes.shoulder_tackle = make({ reach=1.86, x=0.30, arc=0.10, chamberY=1.06, chamberZ=0.30, guardY=1.25, guardZ=0.40, twist=48, roll=16, pitch=20, recoil=0.32, rearHeel=true, shoulder=true, lungeMul=0.82 })
Strikes.parry = make({ reach=1.20, x=0.58, arc=0.02, chamberY=1.32, chamberZ=0.42, guardY=1.34, guardZ=0.36, twist=16, roll=26, pitch=-2, recoil=0.18, parry=true, lungeMul=0.10 })

return Strikes
