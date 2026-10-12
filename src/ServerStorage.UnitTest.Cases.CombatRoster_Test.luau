--!strict
local RS = game:GetService("ReplicatedStorage")
local Lab = RS:WaitForChild("FightingLab")
local Sim = require(Lab:WaitForChild("CombatSim"))
local Roster = require(Lab:WaitForChild("Roster"))
local Config = require(Lab:WaitForChild("CombatConfig"))

type Match = Sim.Match
type Event = Sim.Event

local function place(match: Match, a: Vector3?, b: Vector3?)
	local p1 = a or Vector3.zero
	local p2 = b or Vector3.new(3, 0, 0)
	local l, t = match.fighters[1], match.fighters[2]
	l.pos, t.pos = p1, p2
	l.facing = (p2 - p1).Unit
	t.facing = (p1 - p2).Unit
end

local function run(match: Match, frames: number): { Event }
	local all: { Event } = {}
	for _ = 1, frames do
		for _, e in Sim.step(match) do table.insert(all, e) end
		while match.hitstop > 0 do Sim.step(match) end
	end
	return all
end

local function first(events: { Event }, kind: string): Event?
	for _, e in events do if e.kind == kind then return e end end
	return nil
end

local function count(events: { Event }, kind: string): number
	local n = 0
	for _, e in events do if e.kind == kind then n += 1 end end
	return n
end

local function forceActive(f: Sim.Fighter, moveKey: string, frame: number)
	local def = Roster.getMove(f.characterId, moveKey)
	f.move = moveKey
	f.moveName = def.name
	f.state = "Active"
	f.moveFrame = frame
	f.hasHit = false
	f.crouched = def.crouching
end

return function(t)
	local test, expect = t.test, t.expect

	test("defaults and roster stats are carried by fighters", function()
		local m = Sim.newMatch("Training")
		expect.equal(m.fighters[1].characterId, "Kael")
		expect.equal(m.fighters[2].characterId, "Sierra")
		for _, id in Roster.order do
			local s = Roster.get(id).stats
			local f = Sim.newFighter(id, Vector3.zero, Vector3.xAxis, id)
			expect.equal(f.maxHealth, s.maxHealth, id)
			expect.equal(f.health, s.maxHealth, id)
			f.input.moveX = 1; run({ fighters = { f, Sim.newFighter("dummy", Vector3.new(8,0,0), -Vector3.xAxis, "Kael") }, frame = 0, koFrame = nil, mode = "Training", phase = "Fight", phaseFrames = 0, timer = Config.RoundFrames, scores = {0,0}, round = 1, winner = 0, reason = "", hitstop = 0, difficulty = "Normal", stageId = Config.DefaultStage } :: any, 1)
			expect.truthy(f.pos.X > 0, id .. " walks")
		end
	end)

	test("command direction priority resolves dash ss backdash diagonals and neutral", function()
		local f = Sim.newFighter("Kael", Vector3.zero, Vector3.xAxis, "Kael")
		f.state = "Dash"; f.input.moveX = 1; f.input.crouch = true; expect.equal(Sim.selectMove(f, "RearPunch"), "ChargingCross", "dash + 2")
		f.state = "Idle"; f.dashRequest = 1; expect.equal(Sim.selectMove(f, "RearPunch"), "ChargingCross", "button pressed with the second tap")
		f.dashRequest = 0; f.input.crouch = true; f.input.moveX = 1; expect.equal(Sim.selectMove(f, "RearPunch"), "RisingUppercut", "df+2")
		f.input.moveX = -1; expect.equal(Sim.selectMove(f, "RearPunch"), "BodyBlow", "db+2 falls back to d+2")
		f.input.crouch = false; f.input.moveX = 1; expect.equal(Sim.selectMove(f, "RearPunch"), "Overhand", "f+2")
		f.input.moveX = -1; expect.equal(Sim.selectMove(f, "RearPunch"), "WeaveHook", "b+2")
		f.input.moveX = 0; expect.equal(Sim.selectMove(f, "RearPunch"), "Cross", "2")
		f.state = "Backdash"; expect.equal(Sim.selectMove(f, "RearPunch"), "WeaveHook", "back context while backdashing")
		local s = Sim.newFighter("Sierra", Vector3.zero, Vector3.xAxis, "Sierra")
		s.state = "Sidestep"; expect.equal(Sim.selectMove(s, "LeadKick"), "AngleKick", "ss+3 during a sidestep")
		s.state = "Idle"; s.stepRequest = -1; expect.equal(Sim.selectMove(s, "LeadKick"), "AngleKick", "ss+3 pressed with the step tap")
		s.stepRequest = 0; expect.equal(Sim.selectMove(s, "RearPunch"), "Cross", "no ss move falls back to neutral")
		s.state = "Sidestep"; expect.equal(Sim.selectMove(s, "RearPunch"), "Cross")
	end)

	test("every roster move reports its target frame data", function()
		for _, id in Roster.order do
			local char = Roster.get(id)
			for _, key in char.moveOrder do
				local def = char.moves[key]
				if def.height ~= "Throw" then
					local m = Sim.newMatch("Training", id, "Kael")
					place(m, Vector3.zero, Vector3.new(math.min(3, def.range - 0.2), 0, 0))
					m.fighters[2].input.block = true
					m.fighters[2].input.crouch = def.height == "Low"
					Sim.queueAttack(m.fighters[1], key)
					local block = first(run(m, def.startup + 1), "Block")
					expect.truthy(block ~= nil, id .. "." .. key .. " blocks")
					if block then expect.equal(block.advantage, def.onBlock, id .. "." .. key .. " onBlock") end
					m = Sim.newMatch("Training", id, "Kael")
					place(m, Vector3.zero, Vector3.new(math.min(3, def.range - 0.2), 0, 0))
					Sim.queueAttack(m.fighters[1], key)
					local hit = first(run(m, def.startup + 1), "Hit") or first(run(m, 1), "Hit")
					expect.truthy(hit ~= nil, id .. "." .. key .. " hits")
					if hit then
						if typeof(def.onHit) == "number" then expect.equal(hit.advantage, def.onHit, id .. "." .. key .. " onHit") end
						if def.onHit == "LAUNCH" then expect.truthy(hit.launch == true, key) end
						if def.onHit == "KND" then expect.truthy(hit.knockdown == true, key) end
					end
				end
			end
		end
	end)

	test("strings chain during active and early recovery on hit block or whiff", function()
		for _, id in Roster.order do
			local char = Roster.get(id)
			for _, key in char.moveOrder do
				local def = char.moves[key]
				if def.chainFrom then
					for _, outcome in { "hit", "block", "whiff" } do
						local m = Sim.newMatch("Training", id, "Kael")
						local source = char.moves[def.chainFrom]
						place(m, Vector3.zero, if outcome == "whiff" then Vector3.new(10,0,0) else Vector3.new(3,0,0))
						if outcome == "block" then m.fighters[2].input.block = true end
						Sim.queueAttack(m.fighters[1], def.chainFrom)
						run(m, source.startup + 1)
						Sim.queueAttack(m.fighters[1], key)
						run(m, source.active + 1)
						expect.equal(m.fighters[1].move, key, id .. "." .. key .. " chains on " .. outcome)
					end
				end
			end
		end
	end)

	test("throws start break hit knock down and command throw whiffs crouch", function()
		local def = Roster.getMove("Goran", "RamSlam")
		local m = Sim.newMatch("Training", "Goran", "Kael")
		place(m, Vector3.zero, Vector3.new(2.8,0,0))
		Sim.queueAttack(m.fighters[1], "RamSlam")
		local events = run(m, def.startup + 1)
		expect.truthy(first(events, "ThrowStart") ~= nil, "command throw starts")
		Sim.press(m, 2, def.breakButton or "LeadPunch")
		events = run(m, 1)
		expect.truthy(first(events, "ThrowBreak") ~= nil, "the matching punch breaks")
		expect.equal(m.fighters[1].state, "Throw", "both stay locked while the break plays")
		expect.truthy(m.fighters[2].throwInfo ~= nil and m.fighters[2].throwInfo.broken == true, "the snapshot can show the break")
		events = run(m, Config.ThrowBreakFrames + 1)
		expect.equal(count(events, "ThrowHit"), 0, "a broken throw never lands")
		expect.equal(m.fighters[1].state, "Idle")
		expect.equal(m.fighters[2].state, "Idle", "both return to neutral together")
		m = Sim.newMatch("Training", "Goran", "Kael")
		place(m, Vector3.zero, Vector3.new(2.8,0,0))
		Sim.queueAttack(m.fighters[1], "RamSlam")
		run(m, def.startup + 1)
		Sim.press(m, 2, if def.breakButton == "LeadPunch" then "RearPunch" else "LeadPunch")
		events = run(m, def.impactFrame)
		expect.equal(count(events, "ThrowBreak"), 0, "the wrong punch commits the break attempt")
		local hit = first(events, "ThrowHit")
		expect.truthy(hit ~= nil)
		if hit then expect.equal(hit.damage, def.damage) end
		expect.truthy(hit ~= nil and hit.knockdown == true)
		m = Sim.newMatch("Training", "Goran", "Kael")
		place(m, Vector3.zero, Vector3.new(2.8,0,0)); m.fighters[2].input.crouch = true
		Sim.queueAttack(m.fighters[1], "RamSlam")
		events = run(m, Sim.totalFramesFor(m.fighters[1], "RamSlam") + 2)
		expect.equal(count(events, "ThrowStart"), 0)
		expect.equal(count(events, "Whiff"), 1)
		m = Sim.newMatch("Training", "Goran", "Kael")
		place(m, Vector3.zero, Vector3.new(3.6,0,0))
		Sim.queueAttack(m.fighters[1], "Throw")
		events = run(m, Sim.totalFramesFor(m.fighters[1], "Throw") + 2)
		expect.equal(count(events, "ThrowStart"), 0, "throws only connect at close range")
	end)

	test("each moveset has the required tools with honest frame data", function()
		for _, id in Roster.order do
			local char = Roster.get(id)
			local n = #char.moveOrder
			expect.truthy(n >= 12 and n <= 18, id .. " has 12-18 moves (" .. n .. ")")
			local jab = char.moves[char.moveOrder[1]]
			expect.equal(jab.startup + 1, 10, id .. " first move is a 10 frame jab")
			expect.equal(jab.onBlock, 1, id .. " jab is +1 on block")
			local strings, lows, launchers, powerLows, homing, throws12, throws24, directional = 0, 0, 0, 0, 0, false, false, {}
			for _, key in char.moveOrder do
				local def = char.moves[key]
				expect.truthy(type(def.intent) == "string" and #def.intent > 20, id .. "." .. key .. " has an animation intent")
				expect.truthy(type(def.notation) == "string" and #def.notation > 0, id .. "." .. key .. " has notation")
				expect.falsy(string.find(string.lower(def.name .. " " .. def.intent), "crane", 1, true), id .. "." .. key .. " avoids iconic film wording")
				if def.chainFrom then strings += 1 end
				if def.height == "Low" then lows += 1 end
				if def.onHit == "LAUNCH" then
					launchers += 1
					expect.truthy(def.onBlock <= -13, id .. "." .. key .. " launcher is punishable")
				end
				if def.height == "Low" and def.onHit == "KND" then
					powerLows += 1
					expect.truthy(def.onBlock <= -15, id .. "." .. key .. " power low is punishable")
				end
				if def.homing or def.track >= 3 then homing += 1 end
				if def.notation == "1+3" then throws12 = true end
				if def.notation == "2+4" then throws24 = true end
				local prefix = string.match(def.input, "^(%a+)%+")
				if prefix then directional[prefix] = true end
				if def.height ~= "Throw" then expect.truthy(def.onBlock <= 1, id .. "." .. key .. " is at most +1 on block") end
			end
			expect.truthy(strings >= 2, id .. " has strings")
			expect.truthy(lows >= 2, id .. " has a low poke and a power low")
			expect.truthy(launchers >= 1, id .. " has a launcher")
			expect.truthy(powerLows >= 1, id .. " has a power low")
			expect.truthy(homing >= 1, id .. " has a tracking move")
			expect.truthy(throws12 and throws24, id .. " has 1+3 and 2+4 throws")
			for _, prefix in { "f", "d", "b" } do expect.truthy(directional[prefix], id .. " uses " .. prefix .. " + button") end
		end
	end)

	test("renamed and removed move keys are documented", function()
		for id, map in Roster.renamedKeys do
			local char = Roster.get(id)
			for old, new in map do
				expect.truthy(char.moves[new] ~= nil, id .. " renamed key " .. new .. " exists")
				expect.truthy(char.moves[old] == nil, id .. " old key " .. old .. " is gone")
			end
		end
		for id, list in Roster.removedKeys do
			local char = Roster.get(id)
			for _, old in list do expect.truthy(char.moves[old] == nil, id .. " removed key " .. old .. " is gone") end
		end
		expect.equal(Roster.renamedKeys.Nia.CraneKick, "RisingFrontKick")
		expect.equal(Roster.get("Nia").moves.PalmKick.name, "Palm Into Rising Snap Kick")
	end)

	test("crush armor and parry windows produce contract events", function()
		local m = Sim.newMatch("Training", "Kael", "Lumi")
		place(m)
		forceActive(m.fighters[1], "Jab", Roster.getMove("Kael", "Jab").startup + 1)
		forceActive(m.fighters[2], "CartwheelKick", 8)
		local events = run(m, 1)
		expect.truthy(first(events, "Crush") ~= nil)
		m = Sim.newMatch("Training", "Kael", "Goran")
		place(m)
		forceActive(m.fighters[1], "Jab", Roster.getMove("Kael", "Jab").startup + 1)
		forceActive(m.fighters[2], "ShoulderTackle", 8)
		events = run(m, 1)
		expect.truthy(first(events, "Armor") ~= nil)
		expect.equal(m.fighters[2].state, "Startup")
		m = Sim.newMatch("Training", "Kael", "Rhys")
		place(m)
		forceActive(m.fighters[1], "Jab", Roster.getMove("Kael", "Jab").startup + 1)
		forceActive(m.fighters[2], "Deflect", 6)
		events = run(m, 1)
		expect.truthy(first(events, "Parry") ~= nil)
		expect.equal(m.fighters[1].state, "Stagger")
		expect.equal(m.fighters[1].stagger, Roster.getMove("Rhys", "Deflect").props.parry.stagger)
	end)

	test("protocol validates roster character stage and button payloads", function()
		expect.truthy(Sim.validCommand("SelectCharacters", "Kael", "Nia"))
		expect.falsy(Sim.validCommand("SelectCharacters", "Unknown", "Nia"))
		expect.truthy(Sim.validCommand("SelectStage", "HarborDusk", nil))
		expect.falsy(Sim.validCommand("SelectStage", "InvalidDojo", nil))
		expect.truthy(Sim.validCommand("Attack", "Throw", 9))
		expect.falsy(Sim.validCommand("Attack", "LeftSlash", nil))
	end)

	test("AI can complete all roster pairings and difficulty remains ordered", function()
		for _, p1 in Roster.order do
			for _, p2 in Roster.order do
				local m = Sim.newMatch("Match", p1, p2)
				Sim.setDifficulty(m, "Hard")
				if p1 == p2 then m.fighters[2].health -= 1 end
				local guard = 0
				while m.phase ~= "MatchOver" and guard < 60000 do
					if p1 == p2 and m.phase == "Fight" then m.fighters[2].health = math.max(1, m.fighters[1].health - 1); m.timer = math.min(m.timer, 120) end
					Sim.trainerInput(m, 1); Sim.trainerInput(m, 2); Sim.step(m); guard += 1
				end
				expect.equal(m.phase, "MatchOver", p1 .. " vs " .. p2)
			end
		end
		local easy = Sim.difficultyParams("Easy")
		local hard = Sim.difficultyParams("Hard")
		expect.truthy(easy.reactionDelay > hard.reactionDelay)
		expect.truthy(easy.attackCadence > hard.attackCadence)
	end)

	test("step-in moves connect at body contact and keep their threat range", function()
		-- REQUEST 7: moves that visibly connected short got a real step-in (range down, advance up by the same amount).
		-- Every attack must still connect when the bodies touch, and these spot checks pin the threat ranges.
		for _, id in Roster.order do
			local c = Roster.get(id)
			for _, key in c.moveOrder do
				local def = c.moves[key]
				if def.height ~= "Throw" and def.damage > 0 then
					expect.truthy(def.range >= Config.Separation + 0.15, id .. "." .. key .. " reaches body contact")
					expect.truthy(def.advance >= 0 and def.advance <= 3.0, id .. "." .. key .. " advance")
				end
			end
		end
		local pinned = { { "Sierra", "Teep", 3.8, 5.2 }, { "Kael", "Cross", 3.6, 4.6 }, { "Goran", "Bulldozer", 2.8, 5.8 },
			{ "Rhys", "RisingKnee", 2.8, 3.9 }, { "Nia", "Chop", 3.55, 4.2 }, { "Lumi", "ScissorKick", 3.5, 5.2 } }
		for _, row in pinned do
			local def = Roster.getMove(row[1], row[2])
			expect.near(def.range, row[3], 1e-6, row[1] .. "." .. row[2] .. " range")
			expect.near(def.range + def.advance, row[4], 1e-6, row[1] .. "." .. row[2] .. " threat range unchanged")
		end
	end)
end
