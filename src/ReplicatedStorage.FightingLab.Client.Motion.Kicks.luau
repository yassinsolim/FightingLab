--!strict
-- Original FightingLab kick archetypes: chamber -> accelerating impact -> re-chamber.
local Kicks = {}

export type Effector = { pos: Vector3, pole: Vector3?, orient: Vector3?, weight: number? }
export type Keyframe = { t: number, rootOffset: Vector3?, rootRotation: Vector3?, waist: Vector3?, neck: Vector3?, targets: { [string]: Effector }?, plant: { [string]: number }?, ease: string? }
export type AnimParams = { side: "Lead" | "Rear", height: "High" | "Mid" | "Low", crouch: boolean, spin: number, hop: number, lunge: number, scale: number, neutral: Keyframe, stance: string }

type Targets = { [string]: Effector }
type Plant = { [string]: number }
type Spec = { kind: string, reach: number, x: number, chamberY: number, chamberZ: number, yaw: number, waist: number, roll: number, pitch: number, recoil: number, spin: number?, hop: number?, low: boolean?, sweep: boolean?, handsLow: boolean?, pivot: number?, lungeMul: number?, airborne: boolean? }

local PI = math.pi
local TAU = PI * 2
local function v(x: number, y: number, z: number): Vector3 return Vector3.new(x, y, z) end
local function a(x: number, y: number, z: number): Vector3 return Vector3.new(math.rad(x), math.rad(y), math.rad(z)) end
local function e(pos: Vector3, pole: Vector3?, orient: Vector3?, weight: number?): Effector return { pos = pos, pole = pole, orient = orient, weight = weight } end
local function k(t: number, rootOffset: Vector3?, rootRotation: Vector3?, waist: Vector3?, neck: Vector3?, targets: Targets?, plant: Plant?, ease: string?): Keyframe return { t = t, rootOffset = rootOffset, rootRotation = rootRotation, waist = waist, neck = neck, targets = targets, plant = plant, ease = ease } end
local function scaleOf(p: AnimParams): number return if p.scale > 0 then p.scale else 1 end
local function side(p: AnimParams): number return if p.side == "Lead" then -1 else 1 end
local function foot(p: AnimParams): string return if p.side == "Lead" then "LeftFoot" else "RightFoot" end
local function support(p: AnimParams): string return if p.side == "Lead" then "RightFoot" else "LeftFoot" end
local function contactY(p: AnimParams): number local s=scaleOf(p); if p.height == "High" then return 1.82*s elseif p.height == "Low" then return -2.42*s end return 0.58*s end
local function copyNeutral(p: AnimParams, t: number): Keyframe return { t=t, rootOffset=p.neutral.rootOffset, rootRotation=p.neutral.rootRotation, waist=p.neutral.waist, neck=p.neutral.neck, targets=p.neutral.targets, plant=p.neutral.plant, ease="out" } end
local function pole(s: number, y: number?, z: number?): Vector3 return v(0.42*s, y or 0.04, z or 1) end
local function guard(p: AnimParams, low: boolean?): Targets
	local sc=scaleOf(p); local sg=side(p); local drop=if low then -0.55 else 0
	return {
		LeftHand=e(v((-0.34-0.08*sg)*sc,(1.34+drop)*sc,0.52*sc),v(-0.75,-0.8,0.08),nil,1),
		RightHand=e(v((0.34-0.08*sg)*sc,(1.18+drop)*sc,0.36*sc),v(0.75,-0.8,0.08),nil,1),
	}
end
local function add(base: Targets, name: string, pos: Vector3, orient: Vector3?, p: AnimParams): Targets local out: Targets={}; for n,t in base do out[n]=t end; out[name]=e(pos,pole(side(p), if pos.Y > 1 then -0.12 else 0.06, 1),orient,1); return out end
local function plantFor(p: AnimParams, airborne: boolean?): Plant
	if airborne then return { LeftFoot=0.84, RightFoot=0.84 } end
	local out={ LeftFoot=0.22, RightFoot=0.22 }; out[support(p)] = 0; return out
end
local function spinAmount(p: AnimParams, spec: Spec): number return ((p.spin > 0 and p.spin or (spec.spin or 0)) * TAU) end

local style = {
	boxer={lean=0.90, snap=0.92}, kickboxer={lean=1.05, snap=1.08}, grappler={lean=0.82, snap=0.88}, flow={lean=1.18, snap=1.14}, karate={lean=1.00, snap=1.16}, kungfu={lean=1.10, snap=1.08},
}

local function make(spec: Spec): (AnimParams) -> { Keyframe }
	return function(p: AnimParams): { Keyframe }
		local sc=scaleOf(p); local sg=side(p); local f=foot(p); local st=style[p.stance] or style.kickboxer
		local low = spec.low or p.height == "Low" or p.crouch
		local lunge = math.min((p.lunge or 0) * (spec.lungeMul or 0.34), 0.95)
		local hop = math.max(p.hop, spec.hop or 0)
		local spin = spinAmount(p, spec) * sg
		local chamberT = if spec.sweep then 0.50 else 0.42
		local midT = 0.90
		local yHit = contactY(p)
		local chamberY = (if low then math.min(spec.chamberY, -1.05) else spec.chamberY) * sc
		local chamber = v(0.34*sg*sc, chamberY, spec.chamberZ*sc)
		local mid = v((spec.x*0.62)*sg*sc, (chamberY + yHit)*0.50, (spec.reach*0.58 + lunge*0.55)*sc)
		local contact = v(spec.x*sg*sc, yHit, (spec.reach + lunge)*sc)
		local overshoot = v((spec.x+0.12)*sg*sc, yHit + (if p.height=="High" then 0.05*sc else -0.03*sc), (spec.reach + lunge + 0.18)*sc)
		local rechamber = v(0.40*sg*sc, chamberY + 0.10*sc, spec.recoil*sc)
		local gLow = low or spec.handsLow == true
		local g=guard(p,gLow)
		local plant=plantFor(p, spec.airborne or hop > 0.45)
		local suppPlant=plantFor(p,false)
		local pivot = (spec.pivot or 0) * sg
		local crouch = if low then -0.44 else 0
		local root0 = v(0,0,0)
		local rootA = v(-0.05*sg*sc, (0.08 + hop*0.22 + crouch)*sc, (0.02+lunge*0.10)*sc)
		local rootM = v(-0.08*sg*sc, (0.12 + hop*0.55 + crouch*0.45)*sc, (0.10+lunge*0.45)*sc)
		local rootC = v(-0.11*sg*sc, (0.15 + hop + crouch*0.35)*sc, (0.22+lunge)*sc)
		local rootO = v(-0.10*sg*sc, (0.10 + hop*0.55 + crouch*0.25)*sc, (0.16+lunge*0.65)*sc)
		local yaw = spec.yaw * sg * st.snap
		local waist = spec.waist * sg * st.snap
		local roll = spec.roll * sg
		local pitch = spec.pitch * st.lean
		return {
			copyNeutral(p,0),
			k(chamberT, rootA, a(pitch*0.30, yaw*0.22 + spin*0.10/math.pi*180, roll*0.40), a(pitch*0.35, waist*0.35, -roll*0.28), a(5,-yaw*0.16,0), add(g,f,chamber,nil,p), suppPlant, "out"),
			k(midT, rootM, a(pitch*0.55, yaw*0.55 + spin*0.48/math.pi*180, roll*0.70), a(pitch*0.58, waist*0.65, -roll*0.45), a(4,-yaw*0.26,0), add(g,f,mid,nil,p), plant, "linear"),
			k(1.00, rootC, a(pitch, yaw + spin/math.pi*180, roll), a(pitch*1.05, waist + pivot, -roll*0.65), a(4,-yaw*0.38,0), add(g,f,contact,a(0,0,if spec.kind=="side" or spec.kind=="round" then 84*sg else 10*sg),p), plant, "in"),
			k(1.18, rootO, a(pitch*0.84, yaw*1.06 + spin/math.pi*180, roll*0.78), a(pitch*0.86, waist*1.08 + pivot, -roll*0.50), nil, add(g,f,overshoot,a(0,0,if spec.kind=="side" or spec.kind=="round" then 92*sg else 12*sg),p), plant, "linear"),
			k(1.48, rootO*0.72, a(pitch*0.55, yaw*0.88 + spin/math.pi*180, roll*0.48), a(pitch*0.58, waist*0.86, -roll*0.34), nil, add(g,f,overshoot,nil,p), plant, "hold"),
			k(2.14, v(-0.03*sg*sc, (0.00+crouch*0.10)*sc, 0), a(pitch*0.18, yaw*0.18, roll*0.12), a(pitch*0.15, waist*0.18, -roll*0.08), nil, add(g,f,rechamber,nil,p), suppPlant, "out"),
			copyNeutral(p,3),
		}
	end
end

Kicks.front_kick = make({kind="front", reach=2.95, x=0.12, chamberY=-0.88, chamberZ=0.88, yaw=-16, waist=-34, roll=-6, pitch=-8, recoil=1.02, lungeMul=0.38})
Kicks.teep = make({kind="front", reach=3.20, x=0.08, chamberY=-0.82, chamberZ=1.00, yaw=-10, waist=-24, roll=-4, pitch=-10, recoil=1.12, lungeMul=0.44})
Kicks.roundhouse = make({kind="round", reach=2.92, x=0.96, chamberY=-0.78, chamberZ=0.78, yaw=92, waist=116, roll=-14, pitch=-10, recoil=1.40, pivot=34, lungeMul=0.32})
Kicks.low_kick = make({kind="round", reach=2.58, x=0.82, chamberY=-1.18, chamberZ=0.76, yaw=68, waist=88, roll=-10, pitch=8, recoil=1.18, pivot=28, low=true, lungeMul=0.28})
Kicks.sweep = make({kind="sweep", reach=3.02, x=-0.50, chamberY=-1.42, chamberZ=0.72, yaw=-110, waist=-136, roll=-20, pitch=28, recoil=1.72, spin=0.55, low=true, sweep=true, handsLow=true, lungeMul=0.42})
Kicks.knee = make({kind="knee", reach=1.64, x=0.08, chamberY=-1.08, chamberZ=0.60, yaw=-24, waist=-46, roll=5, pitch=-18, recoil=0.72, hop=0.10, lungeMul=0.55})
Kicks.spinning_back_kick = make({kind="back", reach=3.26, x=0.08, chamberY=-0.90, chamberZ=0.62, yaw=-120, waist=-150, roll=8, pitch=-8, recoil=1.10, spin=0.50, pivot=24, lungeMul=0.54})
Kicks.axe_kick = make({kind="axe", reach=2.70, x=0.14, chamberY=1.78, chamberZ=1.08, yaw=-20, waist=-42, roll=5, pitch=12, recoil=1.02, lungeMul=0.28})
Kicks.side_kick = make({kind="side", reach=3.18, x=0.74, chamberY=-0.86, chamberZ=0.64, yaw=82, waist=104, roll=-16, pitch=-8, recoil=1.12, pivot=30, lungeMul=0.46})
Kicks.crescent_kick = make({kind="round", reach=2.82, x=0.88, chamberY=0.80, chamberZ=0.92, yaw=66, waist=88, roll=10, pitch=-8, recoil=1.30, pivot=20, lungeMul=0.28})
Kicks.cartwheel_kick = make({kind="acrobatic", reach=2.80, x=0.82, chamberY=-0.30, chamberZ=0.76, yaw=-110, waist=-130, roll=110, pitch=18, recoil=1.15, hop=0.72, airborne=true, lungeMul=0.32})
Kicks.flip_kick = make({kind="acrobatic", reach=2.88, x=0.50, chamberY=-0.68, chamberZ=0.84, yaw=-52, waist=-78, roll=22, pitch=-72, recoil=1.08, hop=1.15, airborne=true, lungeMul=0.34})
Kicks.slide_kick = make({kind="slide", reach=3.28, x=0.28, chamberY=-1.76, chamberZ=1.00, yaw=-12, waist=-22, roll=-8, pitch=52, recoil=1.48, low=true, handsLow=true, lungeMul=0.70})
Kicks.jumping_kick = make({kind="jump", reach=3.00, x=0.48, chamberY=-0.72, chamberZ=0.84, yaw=-44, waist=-62, roll=18, pitch=-10, recoil=1.10, hop=0.82, airborne=true, lungeMul=0.58})
Kicks.tornado_kick = make({kind="round", reach=2.92, x=0.90, chamberY=-0.72, chamberZ=0.80, yaw=108, waist=132, roll=18, pitch=-8, recoil=1.28, spin=1.0, hop=0.45, airborne=true, pivot=26, lungeMul=0.36})
Kicks.butterfly_kick = make({kind="acrobatic", reach=2.80, x=0.84, chamberY=-0.58, chamberZ=0.72, yaw=96, waist=128, roll=80, pitch=-28, recoil=1.10, spin=1.0, hop=1.0, airborne=true, lungeMul=0.34})
Kicks.rising_kick = make({kind="rise", reach=2.42, x=0.18, chamberY=-1.34, chamberZ=0.74, yaw=-30, waist=-48, roll=8, pitch=-28, recoil=0.98, hop=0.20, lungeMul=0.30})
Kicks.stomp = make({kind="stomp", reach=2.06, x=0.18, chamberY=-0.70, chamberZ=1.02, yaw=-12, waist=-28, roll=2, pitch=18, recoil=0.86, low=true, lungeMul=0.22})
Kicks.spin_kick = function(p: AnimParams): { Keyframe } local pp = table.clone(p) :: AnimParams; pp.spin = if p.spin > 0 then p.spin else 1.0; return Kicks.roundhouse(pp) end

return Kicks
