--!strict
-- Combo readability (round 7): juggle hits build up instead of fading out, a tumble and a body falling out of a juggle
-- read heavier than a plain knockdown, and the sound follows the same ladder.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Lab = ReplicatedStorage.FightingLab
local EffectsController = require(Lab.Client.EffectsController)
local AudioController = require(Lab.Client.AudioController)
local States = require(Lab.Client.Motion.States)

return function(t)
	local test, expect = t.test, t.expect

	test("juggle hits grow heavier with every further hit, the first stays lighter than a grounded hit", function()
		local grounded = EffectsController._specForEvent({ kind = "Hit", tier = "Heavy", combo = 1 } :: any)
		local previous = nil
		for combo = 1, 9 do
			local spec = EffectsController._specForEvent({ kind = "Hit", tier = "Heavy", air = true, combo = combo } :: any)
			if previous then
				expect.truthy(spec.sparks >= previous.sparks and spec.shake >= previous.shake - 1e-9,
					string.format("juggle hit %d sparks %d shake %.3f after %d / %.3f", combo, spec.sparks, spec.shake, previous.sparks, previous.shake))
			end
			previous = spec
		end
		local first = EffectsController._specForEvent({ kind = "Hit", tier = "Heavy", air = true, combo = 2 } :: any)
		local long = EffectsController._specForEvent({ kind = "Hit", tier = "Heavy", air = true, combo = 7 } :: any)
		expect.truthy(first.sparks < grounded.sparks, "the first juggle hit stays lighter than a grounded hit")
		expect.truthy(long.sparks > first.sparks + 4 and long.shake > first.shake, "a long juggle's hits read heavier than its first")
		expect.truthy(long.sparks >= grounded.sparks and long.sparks <= grounded.sparks * 1.2, "the build-up is capped near a grounded hit")
		local tumble = EffectsController._specForEvent({ kind = "Hit", tier = "Heavy", air = true, combo = 2, tumble = true } :: any)
		expect.truthy(tumble.sparks >= grounded.sparks and tumble.shake >= grounded.shake - 1e-9, "a tumbling hit reads as heavy as a grounded one")
	end)

	test("juggle sound climbs a capped ladder, grounded hits and launchers keep their pitch", function()
		expect.equal(AudioController._juggleLift({ kind = "Hit", tier = "Heavy", combo = 5 } :: any), 0)
		expect.equal(AudioController._juggleLift({ kind = "Hit", tier = "Launch", air = true, launch = true, combo = 3 } :: any), 0)
		expect.equal(AudioController._juggleLift({ kind = "Block", air = true, combo = 4 } :: any), 0)
		local last = -1
		for combo = 2, 12 do
			local lift = AudioController._juggleLift({ kind = "Hit", tier = "Medium", air = true, combo = combo } :: any)
			expect.truthy(lift >= last and lift >= 0 and lift <= AudioController.JuggleMax + 1e-9, string.format("combo %d lift %.3f", combo, lift))
			last = lift
		end
		expect.truthy(last > 0.05, "a long juggle is audibly higher")
		expect.truthy(AudioController.Layers.AirLand ~= nil and #AudioController.Layers.AirLand >= 2, "a body landing from the air has a layered thud")
		expect.truthy(AudioController.TumbleLift < 0, "the tumble whoosh is pitched down")
	end)

	test("a body falling out of the air lands at once and is marked as an air landing", function()
		local config = { LandingFrames = 34 }
		local air = States.newImpactTracker()
		expect.equal(States.floorImpact(air, { state = "Airborne", pos = Vector3.new(0, 2.5, 0) }, config, 0), false)
		expect.equal(States.floorImpact(air, { state = "Landing", pos = Vector3.new(0, 0, 0), stun = 34 }, config, 0.5), true)
		expect.equal(air.fromAir, true)
		expect.equal(States.floorImpact(air, { state = "Landing", pos = Vector3.new(0, 0, 0), stun = 33 }, config, 0.52), false, "one impact per landing")
		local ground = States.newImpactTracker()
		expect.equal(States.floorImpact(ground, { state = "Hitstun", pos = Vector3.new(0, 0, 0) }, config, 0), false)
		expect.equal(States.floorImpact(ground, { state = "Landing", pos = Vector3.new(0, 0, 0), stun = 34 }, config, 0.1), false, "a standing knockdown falls first")
		local fall = States.fallFrames(config)
		expect.equal(States.floorImpact(ground, { state = "Landing", pos = Vector3.new(0, 0, 0), stun = 34 - math.ceil(fall) }, config, 0.5), true)
		expect.equal(ground.fromAir, false)
		expect.truthy(EffectsController.AirLandDust > 26 and EffectsController.AirLandShake > 0.035, "air landings read heavier than standing knockdowns")
	end)
end
