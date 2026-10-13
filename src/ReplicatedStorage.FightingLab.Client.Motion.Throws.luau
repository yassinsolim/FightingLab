--!strict
local Library = require(script.Parent.Parent.MotionLibrary)
export type Keyframe = Library.Keyframe
export type ThrowTrack = { attacker: { Keyframe }, defender: { Keyframe }, duration: number, impactFrame: number }

local Throws: { [string]: (duration: number?, impactFrame: number?) -> ThrowTrack } = {}
local function k(t: number, rootOffset: Vector3?, rootRotation: Vector3?, waist: Vector3?, neck: Vector3?, targets: { [string]: Library.Effector }?, plant: { [string]: number }?, ease: string?): Keyframe return Library.k(t, rootOffset, rootRotation, waist, neck, targets, plant, ease) end
local both = { LeftFoot = 0, RightFoot = 0 }
local air = { LeftFoot = 0.86, RightFoot = 0.86 }
local function v(x:number,y:number,z:number): Vector3 return Vector3.new(x,y,z) end
local function a(x:number,y:number,z:number): Vector3 return Vector3.new(math.rad(x),math.rad(y),math.rad(z)) end
local function hands(z:number, y:number?): { [string]: Library.Effector } return { LeftHand = Library.e(v(-0.42, y or 1.40, z), v(-0.7,-0.7,0.1), nil, 1), RightHand = Library.e(v(0.42, (y or 1.34)-0.06, z-0.04), v(0.7,-0.7,0.1), nil, 1) } end

type Spec = { lift: number, turn: number, side: number, slam: number, arc: number, pitch: number }
local specs: { [string]: Spec } = {
	clinch_strike = { lift = 0.45, turn = 35, side = 0.10, slam = 0.70, arc = 0.80, pitch = 40 },
	clinch_knees = { lift = 0.55, turn = 28, side = -0.08, slam = 0.72, arc = 0.72, pitch = 32 },
	bear_hug_toss = { lift = 1.25, turn = 55, side = 0.22, slam = 1.10, arc = 1.00, pitch = 78 },
	slam = { lift = 1.35, turn = 42, side = 0.05, slam = 1.26, arc = 0.92, pitch = 88 },
	flip_toss = { lift = 1.55, turn = 170, side = 0.46, slam = 1.16, arc = 1.35, pitch = 120 },
	hip_toss = { lift = 1.15, turn = 88, side = -0.34, slam = 1.04, arc = 1.06, pitch = 96 },
	arm_toss = { lift = 1.05, turn = 112, side = 0.55, slam = 0.98, arc = 1.18, pitch = 105 },
}

local function common(name: string, duration: number?, impactFrame: number?): ThrowTrack
	local d = duration or 48
	local impact = impactFrame or math.floor(d * 0.68)
	local s = specs[name] or specs.clinch_strike
	local hitT = math.clamp(impact / math.max(d, 1), 0.55, 0.86)
	local attacker = {
		k(0, v(0,0,0), a(0,0,0), a(0,0,0), a(0,0,0), nil, both),
		k(0.16, v(0,-0.10,0.34), a(8,-8,0), a(14,-12,0), a(-5,8,0), hands(1.18,1.26), both, "out"),
		k(0.30, v(0,-0.16,0.50), a(14,8,0), a(20,10,0), a(-8,-5,0), hands(0.88,1.24), both, "linear"),
		k(1/3, v(0,-0.12,0.44), a(10,16,0), a(16,18,0), a(-6,-8,0), hands(0.70,1.34), both, "linear"),
		k(0.48, v(0,0.08,0.26), a(-8,s.turn*0.35,0), a(-14,s.turn*0.42,0), a(2,-s.turn*0.20,0), hands(0.42,1.58), both, "in"),
		k(hitT, v(0,-0.04,0.10), a(20,s.turn,0), a(28,s.turn,0), a(-12,-s.turn*0.35,0), hands(0.68,1.20), both, "in"),
		k(0.92, v(0,0,0.04), a(4,s.turn*0.28,0), a(8,s.turn*0.20,0), a(0,0,0), nil, both, "out"),
		k(1, v(0,0,0), a(0,0,0), a(0,0,0), a(0,0,0), nil, both, "inout"),
	}
	local defender = {
		k(0, v(0,0,1.10), a(0,180,0), a(0,0,0), a(0,0,0), nil, both),
		k(0.16, v(0,0.04,0.72), a(4,180,4), a(10,0,0), a(-8,0,0), nil, both, "out"),
		k(0.30, v(s.side*0.35,0.34,0.42), a(16,180-s.turn*0.16,12), a(18,0,-8), a(-10,0,0), nil, both, "linear"),
		k(1/3, v(s.side*0.46,0.50,0.36), a(22,180-s.turn*0.24,18), a(18,0,-10), a(-8,0,0), nil, air, "linear"),
		k(0.48, v(s.side*0.70,s.lift,0.20), a(42,180-s.turn*0.50,36), a(18,0,-18), a(-6,0,0), nil, air, "in"),
		k(hitT, v(s.side*s.arc,-s.slam,1.38), a(s.pitch,180-s.turn,-22), a(28,0,14), a(-28,0,-8), nil, both, "in"),
		k(0.92, v(s.side*s.arc*1.05,-1.22,1.82), a(90,180-s.turn,-10), a(14,0,8), a(-34,0,-8), nil, both, "out"),
		k(1, v(s.side*s.arc*1.05,-1.24,1.96), a(90,180-s.turn,0), a(0,0,0), a(0,0,0), nil, both, "inout"),
	}
	return { attacker = attacker, defender = defender, duration = d, impactFrame = impact }
end
for _, name in { "clinch_strike", "clinch_knees", "bear_hug_toss", "slam", "flip_toss", "hip_toss", "arm_toss" } do Throws[name] = function(duration: number?, impactFrame: number?): ThrowTrack return common(name, duration, impactFrame) end end
-- The Ultimate (round 6) is posed by Motion.Cinematic; this keyframe pair only keeps any older caller of the throw
-- archetypes from failing on its "ultimate" snapshot archetype.
Throws.ultimate = function(duration: number?, impactFrame: number?): ThrowTrack return common("slam", duration, impactFrame) end
function Throws.whiff(): { Keyframe } return { k(0, Vector3.zero, Vector3.zero, Vector3.zero, Vector3.zero, nil, both), k(0.35, v(0,-0.05,0.34), a(8,0,0), a(20,0,0), nil, hands(1.22,1.28), both, "out"), k(3, Vector3.zero, Vector3.zero, Vector3.zero, Vector3.zero, nil, both, "out") } end
function Throws.throwBreak(role: string): { Keyframe } local dir = if role == "Attacker" then -1 else 1; return { k(0, Vector3.zero, Vector3.zero, Vector3.zero, Vector3.zero, nil, both), k(1, v(0,0,dir*-0.70), a(-8,0,0), a(-12,0,0), nil, nil, both, "out"), k(3, Vector3.zero, Vector3.zero, Vector3.zero, Vector3.zero, nil, both, "out") } end
return Throws
