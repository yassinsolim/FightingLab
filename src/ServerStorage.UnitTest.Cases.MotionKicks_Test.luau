--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lab = ReplicatedStorage.FightingLab
local MotionLibrary = require(Lab.Client.MotionLibrary)
local Kicks = require(Lab.Client.Motion.Kicks)

type Effector = { pos: Vector3, pole: Vector3?, orient: Vector3?, weight: number? }
type Keyframe = {
	t: number,
	rootOffset: Vector3?,
	rootRotation: Vector3?,
	waist: Vector3?,
	neck: Vector3?,
	targets: { [string]: Effector }?,
	plant: { [string]: number }?,
	ease: string?,
}
type AnimParams = {
	side: "Lead" | "Rear",
	height: "High" | "Mid" | "Low",
	crouch: boolean,
	spin: number,
	hop: number,
	lunge: number,
	scale: number,
	neutral: Keyframe,
	stance: string,
}

local ARCHETYPES = {
	"front_kick",
	"teep",
	"roundhouse",
	"low_kick",
	"sweep",
	"knee",
	"spinning_back_kick",
	"axe_kick",
	"side_kick",
	"crescent_kick",
	"cartwheel_kick",
	"flip_kick",
	"slide_kick",
	"jumping_kick",
	"tornado_kick",
	"butterfly_kick",
	"rising_kick",
	"stomp",
	"spin_kick",
}

local AIRBORNE: { [string]: boolean } = {
	cartwheel_kick = true,
	flip_kick = true,
	jumping_kick = true,
	tornado_kick = true,
	butterfly_kick = true,
}

local function finite(n: number): boolean
	return n == n and math.abs(n) < math.huge
end

local function finiteVector(vec: Vector3?): boolean
	if not vec then return true end
	return finite(vec.X) and finite(vec.Y) and finite(vec.Z)
end

local function finiteKey(key: Keyframe): boolean
	if not finite(key.t) or not finiteVector(key.rootOffset) or not finiteVector(key.rootRotation) or not finiteVector(key.waist) or not finiteVector(key.neck) then
		return false
	end
	for _, target in key.targets or {} do
		if not finiteVector(target.pos) or not finiteVector(target.pole) or not finiteVector(target.orient) then
			return false
		end
		if target.weight and not finite(target.weight) then
			return false
		end
	end
	for _, amount in key.plant or {} do
		if not finite(amount) then
			return false
		end
	end
	return true
end

local function nearVector(a: Vector3?, b: Vector3?, eps: number): boolean
	if a == nil or b == nil then return a == b end
	return (a - b).Magnitude <= eps
end

local function targetAt(keys: { Keyframe }, t: number): Keyframe
	for _, key in keys do
		if math.abs(key.t - t) < 1e-5 then
			return key
		end
	end
	error("missing keyframe at t=" .. tostring(t))
end

local function activeFoot(params: AnimParams): string
	return if params.side == "Lead" then "LeftFoot" else "RightFoot"
end

local function supportFoot(params: AnimParams): string
	return if params.side == "Lead" then "RightFoot" else "LeftFoot"
end

local function contactHeight(height: string): number
	if height == "High" then return 1.75 end
	if height == "Low" then return -2.45 end
	return 0.55
end

local function params(side: "Lead" | "Rear", height: "High" | "Mid" | "Low", archetype: string): AnimParams
	return {
		side = side,
		height = height,
		crouch = height == "Low" or archetype == "slide_kick" or archetype == "sweep",
		spin = if archetype == "spin_kick" or archetype == "tornado_kick" or archetype == "butterfly_kick" then 1 elseif archetype == "spinning_back_kick" then 0.5 else 0,
		hop = if archetype == "flip_kick" then 1.2 elseif archetype == "jumping_kick" then 0.9 elseif archetype == "butterfly_kick" then 1.0 else 0,
		lunge = if archetype == "slide_kick" then 1.6 elseif archetype == "knee" then 0.6 elseif archetype == "jumping_kick" then 1.0 else 0,
		scale = 1,
		neutral = MotionLibrary.StancePose,
		stance = "kickboxer",
	}
end

local function assertNeutral(t: any, key: Keyframe, neutral: Keyframe, expectedT: number, label: string)
	t.expect.near(key.t, expectedT, 1e-5, label .. " time")
	t.expect.truthy(nearVector(key.rootOffset, neutral.rootOffset, 1e-5), label .. " rootOffset neutral")
	t.expect.truthy(nearVector(key.rootRotation, neutral.rootRotation, 1e-5), label .. " rootRotation neutral")
	t.expect.truthy(nearVector(key.waist, neutral.waist, 1e-5), label .. " waist neutral")
	t.expect.truthy(nearVector(key.neck, neutral.neck, 1e-5), label .. " neck neutral")
	for name, effector in neutral.targets or {} do
		local actual = key.targets and key.targets[name]
		t.expect.truthy(actual ~= nil, label .. " neutral target " .. name .. " exists")
		t.expect.truthy(nearVector((actual :: Effector).pos, effector.pos, 1e-5), label .. " neutral target " .. name)
	end
end

return function(t)
	t.test("all required kick archetypes are exported", function()
		for _, archetype in ARCHETYPES do
			t.expect.equal(type(Kicks[archetype]), "function", archetype .. " export")
		end
	end)

	t.test("kick keyframes satisfy timing, contact and plant contracts", function()
		for _, archetype in ARCHETYPES do
			for _, side in { "Lead" :: "Lead", "Rear" :: "Rear" } do
				for _, height in { "High" :: "High", "Mid" :: "Mid", "Low" :: "Low" } do
					local p = params(side, height, archetype)
					local keys = Kicks[archetype](p)
					t.expect.truthy(#keys >= 5, archetype .. " has enough keys")
					t.expect.truthy(keys[2].t >= 0.28 and keys[2].t <= 0.60, archetype .. " chamber timing")
					local previous = -math.huge
					for i, key in keys do
						t.expect.truthy(key.t > previous, archetype .. " strictly increasing key " .. tostring(i))
						previous = key.t
						t.expect.truthy(finiteKey(key), archetype .. " finite key " .. tostring(i))
					end
					assertNeutral(t, keys[1], p.neutral, 0, archetype .. " start")
					assertNeutral(t, keys[#keys], p.neutral, 3, archetype .. " end")
					local active = targetAt(keys, 1.0)
					local foot = active.targets and active.targets[activeFoot(p)]
					t.expect.truthy(foot ~= nil, archetype .. " active striking foot")
					local pos = (foot :: Effector).pos
					t.expect.near(pos.Y, contactHeight(height), 0.16, archetype .. " " .. side .. " " .. height .. " contact height")
					t.expect.equal(active.ease, "in", archetype .. " accelerates into contact")
					local chamber = keys[2]
					local mid = keys[3]
					local chamberFoot = chamber.targets and chamber.targets[activeFoot(p)]
					local midFoot = mid.targets and mid.targets[activeFoot(p)]
					t.expect.truthy(chamberFoot ~= nil and midFoot ~= nil, archetype .. " has chamber and mid-travel foot")
					local earlySpeed = ((midFoot :: Effector).pos - (chamberFoot :: Effector).pos).Magnitude / math.max(mid.t - chamber.t, 0.001)
					local contactSpeed = (pos - (midFoot :: Effector).pos).Magnitude / math.max(active.t - mid.t, 0.001)
					t.expect.truthy(contactSpeed > earlySpeed * 0.65, archetype .. " contact keeps high startup speed")
					local activePlant = active.plant or {}
					if AIRBORNE[archetype] then
						t.expect.truthy((activePlant.LeftFoot or 0) > 0.25 and (activePlant.RightFoot or 0) > 0.25, archetype .. " airborne contact unplants both feet")
						t.expect.near((keys[#keys].plant and keys[#keys].plant.LeftFoot) or 0, (p.neutral.plant and p.neutral.plant.LeftFoot) or 0, 1e-5, archetype .. " left foot lands")
						t.expect.near((keys[#keys].plant and keys[#keys].plant.RightFoot) or 0, (p.neutral.plant and p.neutral.plant.RightFoot) or 0, 1e-5, archetype .. " right foot lands")
					else
						t.expect.near(activePlant[supportFoot(p)] or 0, 0, 1e-5, archetype .. " support foot planted")
					end
				end
			end
		end
	end)

	t.test("lead and rear kick contacts mirror symmetrically", function()
		for _, archetype in ARCHETYPES do
			for _, height in { "High" :: "High", "Mid" :: "Mid", "Low" :: "Low" } do
				local leadParams = params("Lead", height, archetype)
				local rearParams = params("Rear", height, archetype)
				local lead = targetAt(Kicks[archetype](leadParams), 1.0)
				local rear = targetAt(Kicks[archetype](rearParams), 1.0)
				local leadFoot = (lead.targets :: { [string]: Effector }).LeftFoot.pos
				local rearFoot = (rear.targets :: { [string]: Effector }).RightFoot.pos
				t.expect.near(leadFoot.X, -rearFoot.X, 0.06, archetype .. " " .. height .. " mirrored X")
				t.expect.near(leadFoot.Y, rearFoot.Y, 0.06, archetype .. " " .. height .. " mirrored Y")
				t.expect.near(leadFoot.Z, rearFoot.Z, 0.06, archetype .. " " .. height .. " mirrored Z")
				local leadRoot = lead.rootRotation or Vector3.zero
				local rearRoot = rear.rootRotation or Vector3.zero
				t.expect.near(leadRoot.Y, -rearRoot.Y, 0.08, archetype .. " " .. height .. " mirrored yaw")
			end
		end
	end)
end
