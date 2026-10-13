--!strict
-- Contract A (CONTRACTS-v6.md, Surge and the Ultimate): Surge entry, the once-per-round Ultimate, its cinematic lock,
-- impacts, KO at the end, block / whiff / armor / throw outcomes, combo scaling and the Free Training rule.
local RS = game:GetService("ReplicatedStorage")
local Lab = RS:WaitForChild("FightingLab")
local Sim = require(Lab:WaitForChild("CombatSim"))
local Roster = require(Lab:WaitForChild("Roster"))
local Config = require(Lab:WaitForChild("CombatConfig"))

type Match = Sim.Match
type Event = Sim.Event

local function fight(p1: string, p2: string, distance: number?, mode: string?): Match
	local m = Sim.newMatch(mode or "Match", p1, p2)
	m.phase = "Fight"
	local a, b = m.fighters[1], m.fighters[2]
	a.pos = Vector3.zero
	b.pos = Vector3.new(distance or 3.0, 0, 0)
	a.facing = Vector3.xAxis
	b.facing = -Vector3.xAxis
	return m
end

local function steps(m: Match, n: number): { Event }
	local all: { Event } = {}
	for _ = 1, n do
		for _, e in Sim.step(m) do table.insert(all, e) end
	end
	return all
end

local function count(events: { Event }, kind: string): number
	local n = 0
	for _, e in events do if e.kind == kind then n += 1 end end
	return n
end

local function first(events: { Event }, kind: string): Event?
	for _, e in events do if e.kind == kind then return e end end
	return nil
end

-- Steps until fighter 1's Ultimate lands (state "Ultimate"); returns the events so far and whether it landed.
local function untilCinematic(m: Match, limit: number): ({ Event }, boolean)
	local all: { Event } = {}
	for _ = 1, limit do
		for _, e in Sim.step(m) do table.insert(all, e) end
		if m.fighters[1].state == "Ultimate" then return all, true end
	end
	return all, false
end

return function(t)
	local test, expect = t.test, t.expect

	test("Surge starts on the first frame at or below 25% health, once, and adds 10% damage", function()
		expect.equal(Config.SurgeThreshold, 0.25)
		expect.near(Config.SurgeDamageMultiplier, 1.1, 1e-6)
		local m = fight("Kael", "Sierra")
		local a, b = m.fighters[1], m.fighters[2]
		b.dummy = "Stand"
		a.health = 26
		expect.equal(count(steps(m, 1), "Surge"), 0)
		expect.falsy(a.surge, "26% is not Surge")
		a.health = 25
		local events = steps(m, 1)
		local surge = first(events, "Surge")
		assert(surge, "Surge event")
		expect.equal(surge.attacker, 1)
		expect.equal(surge.target, 1)
		expect.truthy(a.surge and Sim.ultimateReady(a), "in Surge with the Ultimate ready")
		expect.equal(count(steps(m, 30), "Surge"), 0, "the Surge event fires once")
		local hp = b.health
		Sim.press(m, 1, "LeadPunch")
		steps(m, 20)
		expect.equal(hp - b.health, math.floor(Roster.getMove("Kael", "Jab").damage * Config.SurgeDamageMultiplier + 0.5), "Surge damage bonus")
		expect.falsy(b.surge, "the defender is not in Surge")
	end)

	test("the Ultimate needs Surge, 1+2 must be pressed together, and it is used once per round", function()
		local m = fight("Kael", "Sierra")
		local a = m.fighters[1]
		expect.falsy(Sim.ultimateReady(a))
		expect.equal(Sim.press(m, 1, "Ultimate"), nil, "not ready outside Surge")
		Sim.press(m, 1, "LeadPunch")
		expect.truthy(Sim.press(m, 1, "RearPunch") ~= "Ultimate", "outside Surge 1+2 is not the Ultimate")
		steps(m, 60)
		Sim.press(m, 1, "LeadPunch")
		steps(m, 2)
		expect.equal(Sim.press(m, 1, "RearPunch"), "OneTwo", "a typed 1,2 is the string")
		-- In Surge: 1 then 2 two frames apart is still the string; on the same frame it is the Ultimate.
		m = fight("Kael", "Sierra", 9.0)
		a = m.fighters[1]
		a.health = 20
		steps(m, 1)
		Sim.press(m, 1, "LeadPunch")
		steps(m, 2)
		expect.equal(Sim.press(m, 1, "RearPunch"), "OneTwo", "a typed 1,2 string is not the Ultimate")
		steps(m, 60)
		expect.truthy(Sim.ultimateReady(a), "still ready")
		Sim.press(m, 1, "LeadPunch")
		expect.equal(Sim.press(m, 1, "RearPunch"), "Ultimate", "1+2 together")
		steps(m, 1)
		expect.equal(a.move, "Ultimate")
		expect.falsy(a.surge, "Surge ends when the Ultimate starts")
		expect.truthy(a.ultUsed)
		local events = steps(m, 90)
		local whiff = first(events, "Whiff")
		assert(whiff, "out of range: whiff")
		expect.equal(whiff.move, "Ultimate")
		expect.falsy(Sim.ultimateReady(a), "used for the round")
		expect.equal(Sim.press(m, 1, "Ultimate"), nil)
		a.health = 10
		steps(m, 3)
		expect.falsy(a.surge, "no second Surge in the round")
		-- The next round starts fresh.
		m.fighters[2].health = 0
		m.fighters[2].state = "KO"
		m.koFrame = m.frame
		for _ = 1, Config.RoundBreakFrames + Config.ReadyFrames + 400 do
			Sim.step(m)
			if m.round == 2 and m.phase == "Fight" then break end
		end
		expect.equal(m.round, 2)
		expect.falsy(m.fighters[1].ultUsed, "a new round gives the Ultimate back")
		expect.falsy(m.fighters[1].surge)
	end)

	test("on hit every Ultimate locks both fighters for its cinematic, plays each impact and knocks down", function()
		for _, id in Roster.order do
			local def = Roster.getMove(id, "Ultimate")
			local cin = def.cinematic :: Roster.Cinematic
			local m = fight(id, "Goran")
			local a, b = m.fighters[1], m.fighters[2]
			b.dummy = "Stand"
			a.health = 20
			steps(m, 1)
			expect.equal(Sim.press(m, 1, "Ultimate"), "Ultimate", id)
			local startEvent: Event? = nil
			local events: { Event } = {}
			local landed = false
			for _ = 1, 60 do
				for _, e in Sim.step(m) do
					table.insert(events, e)
					if e.kind == "UltStart" then
						startEvent = e
						expect.equal(a.moveFrame, 1, id .. " UltStart on the Ultimate's first frame")
					end
				end
				if a.state == "Ultimate" then landed = true; break end
			end
			assert(startEvent, id .. " UltStart")
			expect.equal(startEvent.attacker, 1); expect.equal(startEvent.target, 2); expect.equal(startEvent.move, "Ultimate")
			expect.truthy(landed, id .. " lands on a standing opponent")
			expect.equal(b.state, "Ultimate", id .. " defender state")
			local startFrame = m.frame
			local timer = m.timer
			local hp0 = b.health
			local apos, bpos = a.pos, b.pos
			expect.near((b.pos - a.pos).Magnitude, cin.endDistance, 1e-3, id .. " defender at endDistance")
			local frames = 1
			local hits: { Event } = {}
			while a.state == "Ultimate" and frames < 400 do
				for _, e in Sim.step(m) do
					if e.kind == "UltHit" then
						table.insert(hits, e)
						expect.equal(m.frame - startFrame, cin.impacts[#hits].frame, id .. " impact " .. #hits .. " frame")
					end
				end
				if a.state == "Ultimate" then
					frames += 1
					expect.equal(b.state, "Ultimate")
					expect.truthy((a.pos - apos).Magnitude < 1e-6 and (b.pos - bpos).Magnitude < 1e-6, id .. " positions locked")
					local info = (a :: any).throwInfo
					expect.equal(info.archetype, "ultimate"); expect.equal(info.duration, cin.duration)
					expect.equal(info.impactFrame, cin.impacts[1].frame)
				end
			end
			expect.equal(frames, cin.duration, id .. " cinematic lasts its duration")
			expect.equal(#hits, #cin.impacts, id .. " one UltHit per impact")
			local sum = 0
			for k, e in hits do
				sum += e.damage
				expect.equal(e.combo, k, id .. " impact index")
				expect.equal(e.move, "Ultimate")
				expect.equal(e.knockdown == true, k == #hits, id .. " knockdown flag on the last impact only")
			end
			expect.equal(sum, def.damage, id .. " impacts add up to the Ultimate's damage")
			expect.equal(hp0 - b.health, def.damage)
			expect.truthy(timer - m.timer <= 1, id .. " the round clock waits for the cinematic")
			expect.equal(b.state, "Landing", id .. " defender lies down")
			expect.equal(b.knockdown, cin.endKind, id .. " endKind")
			expect.equal(a.state, "Idle", id .. " attacker recovers")
			expect.falsy(a.surge); expect.truthy(a.ultUsed)
		end
	end)

	test("a KO inside the cinematic is declared at its end", function()
		local m = fight("Nia", "Lumi")
		local a, b = m.fighters[1], m.fighters[2]
		b.dummy = "Stand"
		a.health = 20
		b.health = 4
		steps(m, 1)
		Sim.press(m, 1, "Ultimate")
		local _, landed = untilCinematic(m, 60)
		expect.truthy(landed)
		local events: { Event } = {}
		local zeroDuring = false
		while a.state == "Ultimate" do
			for _, e in Sim.step(m) do table.insert(events, e) end
			if a.state == "Ultimate" then
				if b.health == 0 then zeroDuring = true end
				expect.equal(m.koFrame, nil, "no KO during the cinematic")
				expect.equal(m.phase, "Fight")
			end
		end
		expect.truthy(zeroDuring, "health reached 0 before the end")
		local ko = first(events, "KO")
		assert(ko, "KO event at the end")
		expect.equal(ko.attacker, 1); expect.equal(ko.move, "Ultimate")
		expect.equal(b.state, "KO")
		for _ = 1, 30 do Sim.step(m) end
		expect.equal(m.phase, "RoundOver")
		expect.equal(m.scores[1], 1)
	end)

	test("blocked or armored: the Ultimate is launch punishable, absorbs strikes and loses to throws", function()
		local def = Roster.getMove("Kael", "Ultimate")
		-- Blocked by a standing guard.
		local m = fight("Kael", "Sierra")
		local a = m.fighters[1]
		a.health = 20
		steps(m, 1)
		Sim.press(m, 1, "Ultimate")
		local events = steps(m, 40)
		local block = first(events, "Block")
		assert(block, "blocked")
		expect.equal(block.move, "Ultimate")
		expect.equal(block.advantage, def.onBlock, "onBlock")
		expect.truthy(def.onBlock <= -15, "launch punishable")
		expect.falsy(a.surge); expect.truthy(a.ultUsed, "a blocked Ultimate is used")
		-- A jab into the startup is absorbed by the armor; the Ultimate still lands.
		m = fight("Kael", "Sierra")
		a = m.fighters[1]
		a.health = 20
		steps(m, 1)
		Sim.press(m, 1, "Ultimate")
		steps(m, 2)
		Sim.press(m, 2, "LeadPunch")
		local armorEvents, landed = untilCinematic(m, 40)
		expect.truthy(first(armorEvents, "Armor") ~= nil, "armor absorbs the jab")
		expect.truthy(landed, "the Ultimate lands after absorbing it")
		-- A throw beats it.
		m = fight("Kael", "Sierra", 2.9)
		a = m.fighters[1]
		a.health = 20
		steps(m, 1)
		Sim.press(m, 1, "Ultimate")
		steps(m, 2)
		Sim.press(m, 2, "LeadPunch"); Sim.press(m, 2, "LeadKick")
		local throwEvents, thrownLanded = untilCinematic(m, 40)
		expect.truthy(first(throwEvents, "ThrowStart") ~= nil, "the throw connects during startup")
		expect.falsy(thrownLanded, "the Ultimate is interrupted")
		expect.truthy(a.ultUsed and not a.surge, "still used for the round")
	end)

	test("parries and the catch never stop the Ultimate; ending a juggle scales it", function()
		-- Rhys's Still Water parry stance does not parry it.
		local m = fight("Kael", "Rhys")
		local a, b = m.fighters[1], m.fighters[2]
		a.health = 20
		steps(m, 1)
		Sim.press(m, 1, "Ultimate")
		local stance = Roster.stance("Rhys", "StillWater")
		assert(stance and stance.props.parry, "Still Water parries")
		local parryEvents: { Event } = {}
		local landed = false
		for _ = 1, 40 do
			if a.move == "Ultimate" and a.moveFrame == Roster.getMove("Kael", "Ultimate").startup then
				b.state = "Stance"; b.stance = "StillWater"; b.stanceFrame = stance.props.parry.window[1]; b.move = nil
			end
			for _, e in Sim.step(m) do table.insert(parryEvents, e) end
			if a.state == "Ultimate" then landed = true; break end
		end
		expect.equal(count(parryEvents, "Parry"), 0, "no parry")
		expect.truthy(landed, "the Ultimate lands through the parry stance")
		-- Goran's Bear Trap does not catch it.
		m = fight("Kael", "Goran")
		a, b = m.fighters[1], m.fighters[2]
		a.health = 20
		steps(m, 1)
		Sim.press(m, 1, "Ultimate")
		local trap = Roster.getMove("Goran", "BearTrap")
		assert(trap.props.catch, "Bear Trap catches")
		local catchEvents: { Event } = {}
		landed = false
		for _ = 1, 40 do
			if a.move == "Ultimate" and a.moveFrame == Roster.getMove("Kael", "Ultimate").startup then
				b.move = "BearTrap"; b.moveName = trap.name; b.moveFrame = trap.props.catch.window[1]; b.state = "Startup"
			end
			for _, e in Sim.step(m) do table.insert(catchEvents, e) end
			if a.state == "Ultimate" then landed = true; break end
		end
		expect.equal(count(catchEvents, "Catch"), 0, "no catch")
		expect.truthy(landed, "the Ultimate lands through the Bear Trap")
		-- As a juggle ender the cinematic deals UltComboScale of its damage.
		expect.near(Config.UltComboScale, 0.7, 1e-6)
		local c = Roster.get("Kael")
		local route: Roster.ComboDef? = nil
		for _, combo in c.combos do if combo.kind == "ultimate" then route = combo end end
		assert(route, "Kael has an Ultimate combo")
		m = fight("Kael", "Sierra")
		a, b = m.fighters[1], m.fighters[2]
		b.dummy = "Stand"
		a.health = 20
		local run = Sim.comboRun(m, 1, route.steps)
		local ult = 0
		for _ = 1, 600 do
			if m.hitstop == 0 then Sim.comboTick(run) end
			for _, e in Sim.step(m) do if e.kind == "UltHit" then ult += e.damage end end
		end
		local full = Roster.getMove("Kael", "Ultimate").damage
		expect.equal(ult, math.floor(full * Config.UltComboScale + 0.5), "scaled cinematic damage")
	end)

	test("Free Training keeps the player in Surge and refills the Ultimate; Versus CPU practice uses the match rule", function()
		local m = fight("Nia", "Kael", 3.0, "Training")
		local a, b = m.fighters[1], m.fighters[2]
		expect.truthy(Sim.isFreeTraining(m))
		local events = steps(m, 2)
		expect.truthy(a.surge and Sim.ultimateReady(a), "always in Surge")
		expect.equal(count(events, "Surge"), 0, "no Surge burst for the practice Surge")
		local hp = b.health
		Sim.press(m, 1, "LeadPunch")
		steps(m, 20)
		expect.equal(hp - b.health, Roster.getMove("Nia", "Chop").damage, "practice Surge adds no damage")
		steps(m, 30)
		expect.equal(Sim.press(m, 1, "Ultimate"), "Ultimate")
		local _, landed = untilCinematic(m, 60)
		expect.truthy(landed)
		for _ = 1, 400 do
			Sim.step(m)
			if a.state ~= "Ultimate" and a.move == nil then break end
		end
		steps(m, 1)
		expect.truthy(a.surge and not a.ultUsed and Sim.ultimateReady(a), "the Ultimate refills after it ends")
		-- Versus CPU practice (the dummy fights back): the normal rule.
		m = fight("Nia", "Kael", 3.0, "Training")
		Sim.setDummy(m, "Fight")
		expect.falsy(Sim.isFreeTraining(m))
		steps(m, 2)
		expect.falsy(m.fighters[1].surge, "no Surge at full health against the CPU")
		m.fighters[1].health = 20
		expect.equal(count(steps(m, 1), "Surge"), 1)
	end)
end
