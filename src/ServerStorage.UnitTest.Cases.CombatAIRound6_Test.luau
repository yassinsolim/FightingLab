--!strict
-- Round 6 CPU (CombatAI): every fighter's CPU uses its 3+4 signature, Hard plays the listed combo routes and spends
-- the Ultimate well, Easy almost never uses it, parry staggers get punished. CPU vs CPU samples are deterministic
-- (fixed seeds); the bars are well below the measured rates (docs/design/combat-balance.md, round 6 CPU).
local RS = game:GetService("ReplicatedStorage")
local Lab = RS:WaitForChild("FightingLab")
local Sim = require(Lab:WaitForChild("CombatSim"))
local AI = require(Lab:WaitForChild("CombatAI"))
local Roster = require(Lab:WaitForChild("Roster"))

type Match = Sim.Match

-- One CPU vs CPU match (both sides at `level`); returns the event counts and the per-fighter stance entries.
local function cpuMatch(level: string, p1: string, p2: string, seed: number): { [string]: number }
	local m = Sim.newMatch("Match", p1, p2)
	m.difficulty = level :: any
	m.aiSeed = seed
	local counts: { [string]: number } = { stance1 = 0, stance2 = 0, catch1 = 0, catch2 = 0, ultStart = 0, ultLand = 0, ultBlocked = 0, rounds = 0 }
	local last = { "", "" }
	local round = 0
	local guard = 0
	while m.phase ~= "MatchOver" and guard < 40000 do
		guard += 1
		Sim.trainerInput(m, 1); Sim.trainerInput(m, 2)
		for _, e in Sim.step(m) do
			if e.kind == "UltStart" then counts.ultStart += 1
			elseif e.kind == "UltHit" and e.combo == 1 then counts.ultLand += 1
			elseif e.kind == "Block" and e.move == "Ultimate" then counts.ultBlocked += 1
			elseif e.kind == "Catch" then counts["catch" .. e.attacker] += 1 end
		end
		if m.round ~= round then round = m.round; counts.rounds += 1 end
		for i, f in m.fighters do
			if f.state == "Stance" and last[i] ~= "Stance" then counts["stance" .. i] += 1 end
			if f.move == "BearTrap" and f.moveFrame == 1 then counts["catch" .. i] += 0.001 end
			last[i] = f.state
		end
	end
	counts.finished = if m.phase == "MatchOver" then 1 else 0
	return counts
end

return function(t)
	local test, expect = t.test, t.expect

	test("the CPU knows every listed combo route", function()
		for _, id in Roster.order do
			local c = Roster.get(id)
			local routes = AI.routesOf(c)
			expect.equal(#routes, #c.combos, id .. " resolves every combo")
			for _, r in routes do
				expect.truthy(r.launchIndex >= 1 and r.launchIndex <= 2, id .. " " .. r.combo.name .. " launches on its first or second press")
				expect.equal(#r.keys, #r.combo.steps, id .. " " .. r.combo.name .. " keys")
			end
		end
	end)

	test("every fighter's CPU uses its 3+4 signature at Normal and Hard", function()
		for n, id in Roster.order do
			local foe = Roster.order[(n % #Roster.order) + 1]
			local uses = 0
			for _, level in { "Normal", "Hard" } do
				local c = cpuMatch(level, id, foe, 600 + n)
				expect.equal(c.finished, 1, id .. " " .. level .. " match finishes")
				uses += c.stance1 + c.catch1
			end
			expect.truthy(uses >= 1, id .. " uses its signature (" .. uses .. ")")
		end
	end)

	test("Ultimate use is ordered: Easy almost never, Normal sometimes, Hard often and well", function()
		local totals: { [string]: { [string]: number } } = {}
		for _, level in { "Easy", "Normal", "Hard" } do
			local sum: { [string]: number } = { ultStart = 0, ultLand = 0, ultBlocked = 0, rounds = 0 }
			for i = 1, 6 do
				local a = Roster.order[i]
				local b = Roster.order[(i + 1) % #Roster.order + 1]
				local c = cpuMatch(level, a, b, 900 + i)
				for k in sum do sum[k] += c[k] end
			end
			totals[level] = sum
		end
		print(string.format("[ULTIMATE] Easy %d/%d rounds, Normal %d started %d landed, Hard %d started %d landed (%d rounds)",
			totals.Easy.ultStart, totals.Easy.rounds, totals.Normal.ultStart, totals.Normal.ultLand, totals.Hard.ultStart, totals.Hard.ultLand, totals.Hard.rounds))
		expect.truthy(totals.Easy.ultStart <= 1, "Easy almost never uses the Ultimate")
		expect.truthy(totals.Normal.ultStart >= 1, "Normal uses the Ultimate")
		expect.truthy(totals.Hard.ultStart >= 2, "Hard uses the Ultimate")
		expect.truthy(totals.Hard.ultLand >= totals.Hard.ultStart * 0.6, "Hard lands most of its Ultimates")
	end)

	test("Hard ends a juggle with its Ultimate when it is ready and finishes listed routes", function()
		AI.resetStats()
		local enders = 0
		for seed = 1, 6 do
			local m = Sim.newMatch("Match", "Kael", "Sierra")
			m.phase = "Fight"
			m.difficulty = "Hard"
			m.aiSeed = seed
			local a, d = m.fighters[1], m.fighters[2]
			a.pos = Vector3.zero; d.pos = Vector3.new(3, 0, 0); a.facing = Vector3.xAxis; d.facing = -Vector3.xAxis
			a.health = 20
			d.health = 30
			d.dummy = "Stand"
			-- Kael's uppercut has launched the dummy: the CPU takes over from here.
			Sim.queueAttack(a, "RisingUppercut")
			local landed = false
			for _ = 1, 400 do
				Sim.trainerInput(m, 1)
				for _, e in Sim.step(m) do if e.kind == "UltHit" and e.attacker == 1 then landed = true end end
				if landed then break end
			end
			if landed then enders += 1 end
		end
		expect.truthy(enders >= 4, "Hard finished " .. enders .. "/6 launches with the Ultimate")
		AI.resetStats()
		local m = Sim.newMatch("Match", "Kael", "Nia")
		m.difficulty = "Hard"
		m.aiSeed = 77
		local guard = 0
		while m.phase ~= "MatchOver" and guard < 40000 do
			guard += 1
			Sim.trainerInput(m, 1); Sim.trainerInput(m, 2); Sim.step(m)
		end
		expect.truthy(AI.stats.routesStarted >= 1 and AI.stats.routesDone >= 1, string.format("Hard plays listed routes (%d started, %d done)", AI.stats.routesStarted, AI.stats.routesDone))
	end)

	test("the CPU punishes a parry stagger", function()
		local punished = 0
		for seed = 1, 6 do
			local m = Sim.newMatch("Match", "Rhys", "Kael")
			m.phase = "Fight"
			m.difficulty = "Hard"
			m.aiSeed = seed
			local a, d = m.fighters[1], m.fighters[2]
			a.pos = Vector3.zero; d.pos = Vector3.new(3, 0, 0); a.facing = Vector3.xAxis; d.facing = -Vector3.xAxis
			d.state = "Stagger"; d.stun = 26; d.stagger = 26
			for _ = 1, 40 do
				Sim.trainerInput(m, 1)
				local hit = false
				for _, e in Sim.step(m) do if e.kind == "Hit" and e.attacker == 1 then hit = true end end
				if hit then punished += 1 break end
			end
		end
		expect.truthy(punished >= 4, "Hard punished " .. punished .. "/6 staggers")
	end)
end
