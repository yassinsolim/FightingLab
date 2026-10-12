--!strict
local Lab = game:GetService("ReplicatedStorage").FightingLab
local Sim = require(Lab.CombatSim)
local Config = require(Lab.CombatConfig)
local RB = require(Lab.RenderBuffer)

type Match = Sim.Match
type Event = Sim.Event

local function place(match: Match, a: Vector3, b: Vector3)
	local l, t = match.fighters[1], match.fighters[2]
	l.pos, t.pos = a, b
	l.facing = (b - a).Unit
	t.facing = (a - b).Unit
end
local function stepRaw(match: Match, frames: number): { Event }
	local all: { Event } = {}
	for _ = 1, frames do
		for _, e in Sim.step(match) do table.insert(all, e) end
	end
	return all
end
local function firstEvent(events: { Event }, kind: string): Event?
	for _, e in events do if e.kind == kind then return e end end
	return nil
end
local function fighter(x: number): { [string]: any }
	return { pos = Vector3.new(x, 0, 0), facing = Vector3.xAxis, health = 100, state = "Idle", moveFrame = 0, stun = 0, combo = 0, crouched = false, walkPhase = 0, moveX = 0 }
end

return function(t)
	local test, expect = t.test, t.expect
	test("hitstop freezes both fighters and the round timer", function()
		local m = Sim.newMatch("Match")
		stepRaw(m, Config.ReadyFrames)
		place(m, Vector3.zero, Vector3.new(3, 0, 0))
		-- OV6 combat: a standing P2 auto-guards in Match mode; the practice dummy "Stand" mode never guards on its own.
		m.fighters[2].dummy = "Stand"
		Sim.queueAttack(m.fighters[1], "Jab")
		stepRaw(m, Config.Moves.Jab.startup)
		local beforeTimer = m.timer
		local events = stepRaw(m, 1)
		local hit = firstEvent(events, "Hit")
		expect.truthy(hit ~= nil)
		expect.equal(m.hitstop, Config.Hitstop.Light)
		expect.equal(m.timer, beforeTimer)
		local aPos, bPos = m.fighters[1].pos, m.fighters[2].pos
		local aMoveFrame, bStun = m.fighters[1].moveFrame, m.fighters[2].stun
		m.fighters[1].input.moveX = 1
		m.fighters[2].input.moveX = -1
		stepRaw(m, Config.Hitstop.Light)
		expect.equal(m.fighters[1].pos, aPos)
		expect.equal(m.fighters[2].pos, bPos)
		expect.equal(m.fighters[1].moveFrame, aMoveFrame)
		expect.equal(m.fighters[2].stun, bStun)
		expect.equal(m.timer, beforeTimer)
		stepRaw(m, 1)
		expect.equal(m.timer, beforeTimer - 1)
	end)
	test("hitstop does not change frame advantage semantics", function()
		local m = Sim.newMatch()
		place(m, Vector3.zero, Vector3.new(3, 0, 0))
		Sim.queueAttack(m.fighters[1], "Heavy")
		local events = stepRaw(m, Config.Moves.Heavy.startup + 1)
		local hit = firstEvent(events, "Hit")
		assert(hit)
		local remaining = Sim.totalFrames("Heavy") - m.fighters[1].moveFrame
		expect.equal(hit.advantage, Config.Moves.Heavy.stun - remaining)
	end)
	test("counter hit applies only while defender is in startup", function()
		local m = Sim.newMatch()
		place(m, Vector3.zero, Vector3.new(3, 0, 0))
		m.fighters[2].state = "Startup"
		m.fighters[2].move = "Heavy"
		m.fighters[2].moveFrame = 4
		Sim.queueAttack(m.fighters[1], "Jab")
		local hit = firstEvent(stepRaw(m, Config.Moves.Jab.startup + 1), "Hit")
		assert(hit)
		expect.equal(hit.counter, true)
		expect.equal(hit.damage, math.floor(Config.Moves.Jab.damage * Config.CounterDamageMultiplier + 0.5))
		expect.equal(m.fighters[2].stun, Config.Moves.Jab.stun + Config.CounterStunBonus)
		local n = Sim.newMatch()
		place(n, Vector3.zero, Vector3.new(3, 0, 0))
		Sim.queueAttack(n.fighters[1], "Jab")
		local normal = firstEvent(stepRaw(n, Config.Moves.Jab.startup + 1), "Hit")
		assert(normal)
		expect.falsy(normal.counter)
		expect.equal(normal.damage, Config.Moves.Jab.damage)
	end)
	test("launcher events carry launch flag", function()
		local m = Sim.newMatch()
		place(m, Vector3.zero, Vector3.new(3, 0, 0))
		Sim.queueAttack(m.fighters[1], "Rise")
		local hit = firstEvent(stepRaw(m, Config.Moves.Rise.startup + 1), "Hit")
		assert(hit)
		expect.equal(hit.launch, true)
		expect.truthy(hit.air)
	end)
	test("RenderBuffer parses new fields and remains backward compatible", function()
		local parsed = RB.parse({ frame = 10, phase = "Fight", mode = "Training", hitstop = 4, p2Human = true, fighters = { fighter(0), fighter(3) }, events = { { kind = "Hit", attacker = 1, target = 2, move = "Jab", frame = 9, counter = true, launch = true, height = "High", limb = "LeadArm" } } })
		assert(parsed)
		expect.equal(parsed.hitstop, 4)
		if parsed.p2Human ~= nil then expect.equal(parsed.p2Human, true) end
		expect.equal(parsed.events[1].counter, true)
		expect.equal(parsed.events[1].launch, true)
		if parsed.events[1].height ~= nil then expect.equal(parsed.events[1].height, "High") end
		if parsed.events[1].limb ~= nil then expect.equal(parsed.events[1].limb, "LeadArm") end
		local old = RB.parse({ frame = 11, phase = "Fight", mode = "Training", fighters = { fighter(0), fighter(3) }, events = { { kind = "Hit", attacker = 1, target = 2, move = "Jab", frame = 11 } } })
		assert(old)
		expect.equal(old.hitstop, 0)
		if old.p2Human ~= nil then expect.equal(old.p2Human, false) end
		expect.falsy(old.events[1].counter)
		expect.falsy(old.events[1].launch)
		expect.falsy(old.events[1].height)
		expect.falsy(old.events[1].limb)
	end)

	test("RenderBuffer parses lastHit presentation metadata nil-safely", function()
		local a = fighter(0)
		local b = fighter(3)
		b.lastHit = { kind = "Hit", height = "Mid", tier = "Heavy", counter = true, frame = 22, move = "Overhand", limb = "RearArm", side = 1 }
		b.velocityY = 8
		b.airFrames = 6
		b.airHits = 1
		local parsed = RB.parse({ frame = 24, phase = "Fight", mode = "Training", fighters = { a, b }, events = {} })
		assert(parsed)
		if parsed.fighters[2].lastHit ~= nil then expect.equal(parsed.fighters[2].lastHit.tier, "Heavy") end
		if parsed.fighters[2].velocityY ~= nil then expect.equal(parsed.fighters[2].velocityY, 8) end
		if parsed.fighters[2].airFrames ~= nil then expect.equal(parsed.fighters[2].airFrames, 6) end
		if parsed.fighters[2].airHits ~= nil then expect.equal(parsed.fighters[2].airHits, 1) end
		local bad = fighter(3)
		bad.lastHit = { kind = "Hit" }
		local parsedBad = RB.parse({ frame = 25, phase = "Fight", mode = "Training", fighters = { a, bad }, events = {} })
		assert(parsedBad)
		expect.falsy(parsedBad.fighters[2].lastHit)
	end)
end
