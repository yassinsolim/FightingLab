--!strict
-- Round 6 signatures (docs/design/movesets.md): the 3+4 stances (Pocket, Southpaw, Aerial, Still Water, Coil) with
-- their follow-ups, exits, properties and stance cancels; Goran's Bear Trap catch; the tumble extender; delayable
-- whirl follow-ups; ground combo scaling.
local RS = game:GetService("ReplicatedStorage")
local Lab = RS:WaitForChild("FightingLab")
local Sim = require(Lab:WaitForChild("CombatSim"))
local Roster = require(Lab:WaitForChild("Roster"))
local Config = require(Lab:WaitForChild("CombatConfig"))

type Match = Sim.Match
type Event = Sim.Event

local function practice(p1: string, p2: string, distance: number?): Match
	local m = Sim.newMatch("Training", p1, p2)
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

local function first(events: { Event }, kind: string): Event?
	for _, e in events do if e.kind == kind then return e end end
	return nil
end

-- 3+4 as a player presses it (both kick buttons on the same frame).
local function signature(m: Match, i: number): string?
	Sim.press(m, i, "LeadKick")
	return Sim.press(m, i, "RearKick")
end

local function hold(m: Match, i: number, notation: string): string
	local act = Sim.parseNotation(notation)
	Sim.setMovement(m, i, act.x, 0)
	m.fighters[i].input.crouch = act.crouch
	return act.button
end

local function release(m: Match, i: number)
	Sim.setMovement(m, i, 0, 0)
	m.fighters[i].input.crouch = false
end

return function(t)
	local test, expect = t.test, t.expect

	test("3+4 starts every fighter's signature and stance follow-ups come out of the stance", function()
		for _, id in Roster.order do
			local c = Roster.get(id)
			local m = practice(id, "Kael", 6.0)
			local a = m.fighters[1]
			local key = signature(m, 1)
			assert(key, id .. " 3+4")
			expect.equal(c.moves[key].notation, "3+4", id)
			steps(m, 1)
			if c.signature.kind == "stance" then
				expect.equal(a.state, "Stance", id .. " enters its stance")
				expect.equal(a.stance, c.signature.key)
				expect.equal(a.stanceFrame, 1)
				expect.equal(Sim.stanceOf(a), c.stances[c.signature.key])
			else
				expect.equal(c.signature.kind, "catch")
				expect.equal(a.move, key, id .. " starts the catch")
			end
			for _, moveKey in c.moveOrder do
				local def = c.moves[moveKey]
				if def.stance and def.chainFrom == nil then
					local st = c.stances[def.stance]
					local m2 = practice(id, "Kael", 6.0)
					local f = m2.fighters[1]
					signature(m2, 1)
					steps(m2, 1)
					local button = hold(m2, 1, def.notation)
					expect.equal(Sim.press(m2, 1, button), moveKey, id .. " " .. def.notation .. " in the stance")
					local startedAt: number? = nil
					for frame = 1, st.cancelFrom + 4 do
						steps(m2, 1)
						if f.move == moveKey then startedAt = frame; break end
					end
					release(m2, 1)
					expect.truthy(startedAt ~= nil, id .. " " .. moveKey .. " starts from " .. st.key)
					expect.truthy((startedAt :: number) + 1 >= st.cancelFrom, id .. " " .. moveKey .. " waits for cancelFrom")
				end
			end
		end
	end)

	test("stances end by holding back, by 3+4 again and on their own", function()
		for _, id in Roster.order do
			local c = Roster.get(id)
			for _, st in c.stances do
				-- Times out.
				local m = practice(id, "Kael", 6.0)
				local a = m.fighters[1]
				signature(m, 1)
				steps(m, st.maxFrames + 2)
				expect.equal(a.stance, nil, id .. " " .. st.key .. " times out")
				expect.equal(a.state, "Idle")
				-- 3+4 again.
				m = practice(id, "Kael", 6.0)
				a = m.fighters[1]
				signature(m, 1)
				steps(m, st.cancelFrom + 1)
				expect.equal(a.state, "Stance")
				signature(m, 1)
				steps(m, 2)
				expect.equal(a.stance, nil, id .. " " .. st.key .. " 3+4 again leaves")
				expect.equal(a.move, nil, id .. " leaving starts no move")
				-- Back.
				if st.backExit then
					m = practice(id, "Kael", 6.0)
					a = m.fighters[1]
					signature(m, 1)
					steps(m, 1)
					Sim.setMovement(m, 1, -1, 0)
					steps(m, st.backExit + 1)
					expect.equal(a.stance, nil, id .. " " .. st.key .. " back exits")
					expect.equal(Sim.guardFor(a), "Stand", id .. " back exit guards")
				end
			end
		end
	end)

	test("stance properties: Pocket ducks highs, Southpaw guards, Aerial travels over lows, Still Water parries, Coil is open", function()
		-- Pocket: a high jab is crushed.
		local m = practice("Kael", "Sierra", 3.0)
		signature(m, 1)
		steps(m, 2)
		expect.equal(Sim.currentCrush(m.fighters[1]), "High")
		Sim.press(m, 2, "LeadPunch")
		expect.truthy(first(steps(m, 16), "Crush") ~= nil, "Pocket crushes a high")
		-- Southpaw: guards highs and mids.
		m = practice("Sierra", "Kael", 3.0)
		signature(m, 1)
		steps(m, 4)
		Sim.press(m, 2, "RearPunch")
		local events = steps(m, 18)
		local block = first(events, "Block")
		expect.truthy(block ~= nil and block.target == 1, "Southpaw guards")
		-- Aerial: travels forward and crushes lows.
		m = practice("Lumi", "Kael", 8.0)
		local lumi = m.fighters[1]
		signature(m, 1)
		local stance = Roster.stance("Lumi", "Aerial") :: Roster.StanceDef
		steps(m, 1)
		local x0 = lumi.pos.X
		steps(m, stance.travelFrames)
		expect.near(lumi.pos.X - x0, stance.travel, 0.25, "Aerial travels its distance")
		m = practice("Lumi", "Kael", 3.2)
		signature(m, 1)
		steps(m, 4)
		expect.equal(Sim.currentCrush(m.fighters[1]), "Low")
		-- Still Water: parries a mid and Rhys is free at once.
		m = practice("Rhys", "Kael", 3.0)
		local rhys = m.fighters[1]
		signature(m, 1)
		steps(m, 8)
		Sim.press(m, 2, "RearPunch")
		events = steps(m, 18)
		local parry = first(events, "Parry")
		assert(parry, "Still Water parries")
		expect.equal(parry.attacker, 1)
		expect.equal(m.fighters[2].state, "Stagger")
		expect.equal(rhys.state, "Idle", "the parrying fighter is free")
		expect.truthy(m.fighters[2].stun >= 10, "the stagger is the punish window")
		-- Coil: hits in the stance are counter hits.
		m = practice("Nia", "Kael", 3.0)
		signature(m, 1)
		steps(m, 2)
		Sim.press(m, 2, "LeadPunch")
		events = steps(m, 16)
		local hit = first(events, "Hit")
		assert(hit and hit.target == 1, "Coil is hit")
		expect.equal(hit.counter, true, "Coil is open to counter hits")
	end)

	test("stance cancels: 3+4 in the recovery of a cancelable move enters the stance", function()
		for _, id in Roster.order do
			local c = Roster.get(id)
			for _, key in c.moveOrder do
				local def = c.moves[key]
				if def.stanceCancel then
					local m = practice(id, "Kael", 9.0)
					local a = m.fighters[1]
					a.move = key; a.moveName = def.name; a.moveFrame = def.startup + def.active; a.state = "Active"; a.hasHit = true
					signature(m, 1)
					steps(m, 2)
					expect.equal(a.state, "Stance", id .. "." .. key .. " cancels")
					expect.equal(a.stance, def.stanceCancel, id .. "." .. key .. " into its stance")
				end
			end
		end
		-- Moves without the property do not cancel.
		local m = practice("Kael", "Sierra", 9.0)
		local a = m.fighters[1]
		local jab = Roster.getMove("Kael", "Jab")
		a.move = "Jab"; a.moveName = jab.name; a.moveFrame = jab.startup + jab.active; a.state = "Active"; a.hasHit = true
		signature(m, 1)
		steps(m, 2)
		expect.truthy(a.state ~= "Stance", "a jab does not cancel into Pocket")
	end)

	test("Goran's Bear Trap catches a high or mid into an unbreakable throw; lows beat it", function()
		local m = practice("Goran", "Kael", 3.0)
		local goran, kael = m.fighters[1], m.fighters[2]
		signature(m, 1)
		steps(m, 3)
		Sim.press(m, 2, "LeadPunch")
		local events: { Event } = {}
		for _ = 1, 120 do
			for _, e in Sim.step(m) do table.insert(events, e) end
			if kael.throwInfo then Sim.press(m, 2, "LeadPunch") end
		end
		local catch = first(events, "Catch")
		assert(catch, "the jab is caught")
		expect.equal(catch.attacker, 1)
		expect.truthy(first(events, "ThrowHit") ~= nil, "the catch throw lands")
		expect.equal(first(events, "ThrowBreak"), nil, "the catch throw cannot be broken")
		expect.equal(kael.health, kael.maxHealth - Roster.getMove("Goran", "ThrowB").damage)
		expect.equal(goran.health, goran.maxHealth)
		-- A low is not caught.
		m = practice("Goran", "Kael", 3.0)
		signature(m, 1)
		steps(m, 3)
		hold(m, 2, "d+4")
		Sim.press(m, 2, "RearKick")
		events = steps(m, 40)
		release(m, 2)
		expect.equal(first(events, "Catch"), nil, "lows are not caught")
		local low = first(events, "Hit")
		expect.truthy(low ~= nil and low.target == 1, "the low hits Goran")
	end)

	test("tumble: one extender per juggle spins the opponent and allows one more air hit", function()
		expect.equal(Config.TumbleVelocity > Config.JuggleVelocity, true)
		local c = Roster.get("Kael")
		local route = c.combos[1]
		local m = practice("Kael", "Sierra", 3.0)
		local d = m.fighters[2]
		local run = Sim.comboRun(m, 1, route.steps)
		local tumbleHits, sawTumbling = 0, false
		for _ = 1, 600 do
			if m.hitstop == 0 then Sim.comboTick(run) end
			for _, e in Sim.step(m) do
				if e.kind == "Hit" and e.tumble then tumbleHits += 1; expect.equal(e.move, "RibRoller") end
			end
			if d.tumbling then sawTumbling = true end
		end
		expect.equal(tumbleHits, 1, "one tumble hit")
		expect.truthy(sawTumbling, "the defender is shown tumbling")
		expect.falsy(d.tumbled or d.tumbling, "landing clears the tumble")
		-- A second tumble move in the same juggle does not tumble again.
		m = practice("Kael", "Sierra", 3.0)
		local a = m.fighters[1]
		d = m.fighters[2]
		d.state = "Airborne"; d.pos = Vector3.new(3, 1.5, 0); d.velocityY = 2; d.chain = 3; d.airHits = 2; d.tumbled = true
		local rib = Roster.getMove("Kael", "RibRoller")
		a.move = "RibRoller"; a.moveName = rib.name; a.moveFrame = rib.startup; a.state = "Startup"
		local events = steps(m, 3)
		local hit = first(events, "Hit")
		assert(hit, "the extender hits")
		expect.equal(hit.tumble, nil, "no second tumble in one juggle")
	end)

	test("delayable Coil whirl follow-ups and ground combo scaling", function()
		local whirl = Roster.getMove("Nia", "CoilWhirl")
		local second = Roster.getMove("Nia", "CoilWhirl2")
		expect.truthy((second.delay or 0) >= 10, "the second whirl can be delayed")
		local m = practice("Nia", "Kael", 9.0)
		local nia = m.fighters[1]
		nia.move = "CoilWhirl"; nia.moveName = whirl.name; nia.state = "Recovery"; nia.hasHit = true
		-- Past the normal string window (ChainLate after the active frames) but inside the delay window.
		nia.moveFrame = whirl.startup + whirl.active + Sim.ChainLate + 2
		expect.truthy(nia.moveFrame < Sim.totalFramesFor(nia, "CoilWhirl"), "still in the whirl's recovery")
		expect.falsy(Sim.chainWindowOpen(nia, whirl), "a plain follow-up would be too late here")
		expect.equal(Sim.press(m, 1, "RearKick"), "CoilWhirl2", "a delayed press still chains")
		steps(m, 2)
		expect.equal(nia.move, "CoilWhirl2")
		-- Ground scaling: the 4th consecutive hit of a ground combo deals less.
		m = practice("Kael", "Sierra", 3.0)
		local a, d = m.fighters[1], m.fighters[2]
		d.state = "Hitstun"; d.stun = 30; d.chain = 3
		local jab = Roster.getMove("Kael", "Jab")
		a.move = "Jab"; a.moveName = jab.name; a.moveFrame = jab.startup; a.state = "Startup"
		local hp = d.health
		local events = steps(m, 3)
		local hit = first(events, "Hit")
		assert(hit, "the 4th hit lands")
		expect.equal(hit.combo, 4)
		expect.equal(hp - d.health, math.floor(jab.damage * (Config.ComboScale[4] :: number) + 0.5), "4th hit scaled")
	end)
end
