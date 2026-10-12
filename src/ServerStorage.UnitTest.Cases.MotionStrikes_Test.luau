--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Lab = ReplicatedStorage:WaitForChild("FightingLab")
local MotionLibrary = require(Lab.Client.MotionLibrary)
local Strikes = require(Lab.Client.Motion.Strikes)

type T = {
	test: (string, () -> ()) -> (),
	expect: {
		equal: (any, any, string?) -> (),
		truthy: (any, string?) -> (),
		near: (number, number, number?, string?) -> (),
	},
}

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

local ARCHETYPES = {
	"straight",
	"hook",
	"uppercut",
	"overhand",
	"body_hook",
	"weave_hook",
	"palm",
	"chop",
	"backfist",
	"spinning_backfist",
	"elbow",
	"hammer_fist",
	"superman_punch",
	"shoulder_tackle",
	"parry",
}
local SIDES = { "Lead", "Rear" }
local HEIGHTS = { "High", "Mid", "Low" }

local function params(side: string, height: string): any
	return {
		side = side,
		height = height,
		crouch = height == "Low",
		spin = 0,
		hop = 0,
		lunge = 0,
		scale = 1,
		neutral = MotionLibrary.StancePose,
		stance = "boxer",
	}
end

local function finite(n: number): boolean
	return n == n and math.abs(n) < math.huge
end

local function finiteVector(vec: Vector3?): boolean
	if not vec then
		return true
	end
	return finite(vec.X) and finite(vec.Y) and finite(vec.Z)
end

local function heightY(height: string): number
	if height == "High" then
		return 1.75
	elseif height == "Mid" then
		return 0.55
	end
	return -2.45
end

local function contactTarget(archetype: string, side: string): string
	if archetype == "shoulder_tackle" then
		return "Body"
	end
	return if side == "Lead" then "LeftHand" else "RightHand"
end

local function guardTarget(side: string): string
	return if side == "Lead" then "RightHand" else "LeftHand"
end

local function findContact(keys: { Keyframe }): Keyframe
	for _, key in keys do
		if math.abs(key.t - 1) < 1e-6 then
			return key
		end
	end
	error("missing t=1.0 keyframe")
end

local function sameNeutral(t: T, actual: Keyframe, neutral: Keyframe, label: string)
	t.expect.equal(actual.rootOffset, neutral.rootOffset, label .. " rootOffset")
	t.expect.equal(actual.rootRotation, neutral.rootRotation, label .. " rootRotation")
	t.expect.equal(actual.waist, neutral.waist, label .. " waist")
	t.expect.equal(actual.neck, neutral.neck, label .. " neck")
	t.expect.truthy(actual.targets ~= nil, label .. " targets")
	t.expect.truthy(neutral.targets ~= nil, label .. " neutral targets")
	for name, neutralTarget in neutral.targets :: { [string]: Effector } do
		local target = (actual.targets :: { [string]: Effector })[name]
		t.expect.truthy(target ~= nil, label .. " missing " .. name)
		t.expect.equal(target.pos, neutralTarget.pos, label .. " " .. name .. " pos")
		t.expect.equal(target.pole, neutralTarget.pole, label .. " " .. name .. " pole")
	end
end

local function assertFiniteKey(t: T, key: Keyframe, label: string)
	t.expect.truthy(finite(key.t), label .. " finite t")
	t.expect.truthy(finiteVector(key.rootOffset), label .. " finite rootOffset")
	t.expect.truthy(finiteVector(key.rootRotation), label .. " finite rootRotation")
	t.expect.truthy(finiteVector(key.waist), label .. " finite waist")
	t.expect.truthy(finiteVector(key.neck), label .. " finite neck")
	for name, target in key.targets or {} do
		t.expect.truthy(finiteVector(target.pos), label .. " finite " .. name .. " pos")
		t.expect.truthy(finiteVector(target.pole), label .. " finite " .. name .. " pole")
		t.expect.truthy(target.weight == nil or finite(target.weight), label .. " finite " .. name .. " weight")
	end
end

local function assertSortedAndFinite(t: T, keys: { Keyframe }, label: string)
	t.expect.truthy(#keys >= 5, label .. " readable beat count")
	local last = -math.huge
	for index, key in keys do
		t.expect.truthy(key.t > last, label .. " strictly increasing at " .. tostring(index))
		last = key.t
		assertFiniteKey(t, key, label .. " key " .. tostring(index))
	end
	t.expect.near(keys[1].t, 0, 1e-6, label .. " first key")
	t.expect.near(keys[#keys].t, 3, 1e-6, label .. " final key")
end

local function assertImpactCurve(t: T, archetype: string, side: string, keys: { Keyframe }, label: string)
	local targetName = contactTarget(archetype, side)
	local chamber = keys[2]
	local mid = keys[3]
	local contact = findContact(keys)
	local motionName = if targetName == "Body" then (if side == "Lead" then "LeftHand" else "RightHand") else targetName
	local chamberEffector = (chamber.targets or {})[motionName]
	local midEffector = (mid.targets or {})[motionName]
	local contactEffector = (contact.targets or {})[targetName]
	t.expect.truthy(chamberEffector ~= nil, label .. " chamber target " .. motionName)
	t.expect.truthy(midEffector ~= nil, label .. " mid target " .. motionName)
	t.expect.truthy(contactEffector ~= nil, label .. " contact target " .. targetName)
	t.expect.equal(chamber.ease, "out", label .. " chamber uses ease-out")
	t.expect.equal(contact.ease, "in", label .. " contact uses ease-in")
	local earlySpeed = ((midEffector :: Effector).pos - (chamberEffector :: Effector).pos).Magnitude / math.max(mid.t - chamber.t, 0.001)
	local contactSpeed = ((contactEffector :: Effector).pos - (midEffector :: Effector).pos).Magnitude / math.max(contact.t - mid.t, 0.001)
	t.expect.truthy(contactSpeed > earlySpeed * 0.65, label .. " keeps high impact speed into contact")
	t.expect.truthy((contactEffector :: Effector).pos.Z > (midEffector :: Effector).pos.Z + 0.25, label .. " extends through startup")
end

local function assertGuard(t: T, side: string, keys: { Keyframe }, label: string)
	local guardName = guardTarget(side)
	for _, key in keys do
		if key.t > 0 and key.t < 3 then
			local guard = (key.targets or {})[guardName]
			t.expect.truthy(guard ~= nil, label .. " guard hand present")
			t.expect.truthy(guard.pos.Z <= 0.75, label .. " guard hand stays close in Z")
			t.expect.truthy(guard.pos.Y > 0.85, label .. " guard hand stays by chin")
		end
	end
end

return function(t: T)
	t.test("exports every strike archetype", function()
		for _, archetype in ARCHETYPES do
			t.expect.truthy(type(Strikes[archetype]) == "function", "missing " .. archetype)
		end
	end)

	t.test("all sides and heights satisfy timing, contact, guard, and neutral invariants", function()
		for _, archetype in ARCHETYPES do
			for _, side in SIDES do
				for _, height in HEIGHTS do
					local label = archetype .. " " .. side .. " " .. height
					local keys = Strikes[archetype](params(side, height))
					assertSortedAndFinite(t, keys, label)
					t.expect.truthy(keys[2].t >= 0.28 and keys[2].t <= 0.60, label .. " chamber timing")
					sameNeutral(t, keys[1], MotionLibrary.StancePose, label .. " start")
					sameNeutral(t, keys[#keys], MotionLibrary.StancePose, label .. " end")
					local contact = findContact(keys)
					local target = (contact.targets or {})[contactTarget(archetype, side)]
					t.expect.truthy(target ~= nil, label .. " has contact target")
					t.expect.near(target.pos.Y, heightY(if archetype == "parry" then "High" elseif archetype == "shoulder_tackle" then "Mid" else height), 0.001, label .. " contact height")
					assertImpactCurve(t, archetype, side, keys, label)
					assertGuard(t, side, keys, label)
				end
			end
		end
	end)

	t.test("lead and rear variants mirror across the fighter centerline", function()
		for _, archetype in ARCHETYPES do
			for _, height in HEIGHTS do
				local lead = findContact(Strikes[archetype](params("Lead", height)))
				local rear = findContact(Strikes[archetype](params("Rear", height)))
				local leadTarget = (lead.targets or {})[contactTarget(archetype, "Lead")]
				local rearTarget = (rear.targets or {})[contactTarget(archetype, "Rear")]
				t.expect.truthy(leadTarget ~= nil, archetype .. " lead target")
				t.expect.truthy(rearTarget ~= nil, archetype .. " rear target")
				t.expect.near(leadTarget.pos.X, -rearTarget.pos.X, 0.001, archetype .. " mirrored X")
				t.expect.near(leadTarget.pos.Y, rearTarget.pos.Y, 0.001, archetype .. " mirrored Y")
				t.expect.near(leadTarget.pos.Z, rearTarget.pos.Z, 0.001, archetype .. " mirrored Z")
			end
		end
	end)

	t.test("crouch, spin, hop, and lunge hints change the intended channels", function()
		local crouched = findContact(Strikes.straight({
			side = "Lead",
			height = "Low",
			crouch = true,
			spin = 0,
			hop = 0,
			lunge = 0,
			scale = 1,
			neutral = MotionLibrary.StancePose,
			stance = "boxer",
		}))
		local spun = findContact(Strikes.spinning_backfist({
			side = "Rear",
			height = "High",
			crouch = false,
			spin = 1,
			hop = 0,
			lunge = 0,
			scale = 1,
			neutral = MotionLibrary.StancePose,
			stance = "flow",
		}))
		local hopped = findContact(Strikes.superman_punch({
			side = "Rear",
			height = "High",
			crouch = false,
			spin = 0,
			hop = 0.6,
			lunge = 1.0,
			scale = 1,
			neutral = MotionLibrary.StancePose,
			stance = "kickboxer",
		}))
		t.expect.truthy((crouched.rootOffset or Vector3.zero).Y < -0.45, "crouch lowers root")
		t.expect.truthy(math.abs((spun.rootRotation or Vector3.zero).Y) > math.pi * 1.5, "spin turns root")
		t.expect.truthy((hopped.rootOffset or Vector3.zero).Y > 0.45, "hop lifts root")
		t.expect.truthy((hopped.rootOffset or Vector3.zero).Z > 0.50, "lunge moves root forward")
	end)
end
