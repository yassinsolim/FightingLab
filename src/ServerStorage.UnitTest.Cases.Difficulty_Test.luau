--!strict
-- CPU difficulty: reaction delays per level, guarding/punishing/juggling scale with level, calm movement (no jitter,
-- rare sidesteps, no attacks from out of range, no launcher spam) and win ordering between levels.
local RS = game:GetService("ReplicatedStorage")
local Lab = RS:WaitForChild("FightingLab")
local Sim = require(Lab:WaitForChild("CombatSim"))
local Config = require(Lab:WaitForChild("CombatConfig"))
local Roster = require(Lab:WaitForChild("Roster"))
local AI = require(Lab:WaitForChild("CombatAI"))

local function place(m: Sim.Match, d: number)
	local a, b = m.fighters[1], m.fighters[2]
	a.pos = Vector3.zero
	b.pos = Vector3.new(d, 0, 0)
	a.facing = Vector3.xAxis
	b.facing = -Vector3.xAxis
end

local function settle(m: Sim.Match)
	while m.hitstop > 0 do Sim.step(m) end
end

-- CPU (level a, slot 1) vs CPU (level b, slot 2); returns the winner slot.
local function cpuMatch(a: string, b: string, charA: string, charB: string, seed: number): number
	local m = Sim.newMatch("Match", charA, charB)
	m.aiSeed = seed
	local guard = 0
	while m.phase ~= "MatchOver" and guard < 40000 do
		m.difficulty = a; Sim.trainerInput(m, 1)
		m.difficulty = b; Sim.trainerInput(m, 2)
		Sim.step(m)
		guard += 1
	end
	return m.winner
end

return function(t)
	local test, expect = t.test, t.expect

	test("difficulty command validates enum values", function()
		expect.truthy(Sim.validCommand("Difficulty", "Easy", nil))
		expect.truthy(Sim.validCommand("Difficulty", "Normal", nil))
		expect.truthy(Sim.validCommand("Difficulty", "Hard", nil))
		expect.falsy(Sim.validCommand("Difficulty", "Nightmare", nil))
		expect.falsy(Sim.validCommand("Difficulty", "Easy", true))
	end)

	test("difficulty parameters are ordered and reaction delays match the contract", function()
		local e, n, h = Sim.difficultyParams("Easy"), Sim.difficultyParams("Normal"), Sim.difficultyParams("Hard")
		expect.truthy(e.reactionDelay >= 35, "Easy reacts in 35+ frames")
		expect.truthy(n.reactionDelay >= 22 and n.reactionDelay + n.reactionJitter <= 26, "Normal reacts in 22-26 frames")
		expect.truthy(h.reactionDelay >= 14 and h.reactionDelay + h.reactionJitter <= 16, "Hard reacts in 14-16 frames")
		for _, k in { "guardDiscipline", "lowReact", "blockPunish", "whiffPunish", "throwBreak", "readSkill", "holdGuard" } do
			expect.truthy((e :: any)[k] < (n :: any)[k] and (n :: any)[k] < (h :: any)[k], k .. " increases with level")
		end
		expect.truthy(e.attackCadence > n.attackCadence and n.attackCadence > h.attackCadence, "harder levels attack more often")
		expect.truthy(e.juggleHits < n.juggleHits and n.juggleHits < h.juggleHits, "juggle length grows with level")
		expect.truthy(e.noise > n.noise and n.noise > h.noise and h.noise <= 0.1, "decision noise shrinks with level")
		expect.falsy(e.hitConfirm, "Easy does not hit-confirm")
		expect.truthy(h.hitConfirm, "Hard hit-confirms strings")
		expect.equal(AI.params("Bogus"), AI.params("Normal"), "unknown levels fall back to Normal")
	end)

	test("every level starts attacking a standing opponent", function()
		for _, diff in { "Easy", "Normal", "Hard" } do
			local m = Sim.newMatch("Match")
			Sim.setDifficulty(m, diff)
			while m.phase ~= "Fight" do Sim.step(m) end
			local events = 0
			for _ = 1, 1200 do
				Sim.trainerInput(m, 2)
				for _, e in Sim.step(m) do if e.attacker == 2 then events += 1 end end
				if events > 0 then break end
			end
			expect.truthy(events > 0, diff .. " should attack")
		end
	end)

	test("hard crouch-blocks a reactable slow low and easy rarely does", function()
		local def = Roster.getMove("Sierra", "LowSweep")
		local function trial(diff: string, seed: number): boolean
			local m = Sim.newMatch("Training", "Sierra", "Kael")
			Sim.setDifficulty(m, diff)
			m.aiSeed = seed
			m.frame = seed * 17
			place(m, 3.4)
			Sim.queueAttack(m.fighters[1], "LowSweep")
			local blocked = false
			for _ = 1, def.startup + 2 do
				Sim.trainerInput(m, 2)
				for _, e in Sim.step(m) do if e.kind == "Block" then blocked = true end end
				settle(m)
			end
			return blocked
		end
		local hard, easy = 0, 0
		for i = 1, 25 do
			if trial("Hard", i) then hard += 1 end
			if trial("Easy", i) then easy += 1 end
		end
		expect.truthy(hard >= 18, "Hard low block rate " .. hard .. "/25")
		expect.truthy(easy <= 8 and easy < hard, "Easy low block rate " .. easy .. "/25")
	end)

	test("block punishes scale with difficulty", function()
		local launcher = Roster.getMove("Kael", "RisingUppercut")
		local function trial(diff: string, seed: number): boolean
			local m = Sim.newMatch("Training", "Kael", "Rhys")
			Sim.setDifficulty(m, diff)
			m.aiSeed = seed
			m.frame = seed * 23
			place(m, 3)
			local dummy, cpu = m.fighters[1], m.fighters[2]
			Sim.queueAttack(dummy, "RisingUppercut")
			local blocked = false
			for _ = 1, launcher.startup + 1 do
				cpu.input.block = true
				for _, e in Sim.step(m) do if e.kind == "Block" then blocked = true end end
				settle(m)
			end
			cpu.input.block = false
			local punished = false
			for _ = 1, 50 do
				Sim.trainerInput(m, 2)
				local busy = dummy.move ~= nil
				for _, e in Sim.step(m) do
					if e.attacker == 2 and (e.kind == "Hit" or e.kind == "KO") and busy then punished = true end
				end
				settle(m)
			end
			return blocked and punished
		end
		local counts = {}
		for _, diff in { "Easy", "Normal", "Hard" } do
			counts[diff] = 0
			for i = 1, 30 do if trial(diff, i) then counts[diff] += 1 end end
		end
		expect.truthy(counts.Hard >= 18, "Hard punishes " .. counts.Hard .. "/30")
		expect.truthy(counts.Easy <= 12, string.format("Easy punishes %d/30 (Normal %d, Hard %d)", counts.Easy, counts.Normal, counts.Hard))
		expect.truthy(counts.Hard > counts.Normal and counts.Normal > counts.Easy, string.format("punish order %d/%d/%d", counts.Easy, counts.Normal, counts.Hard))
	end)

	-- Round 7 retune: a conversion used to be "3+ hits within 4 s and a knockdown". Sierra's Hard CPU juggles this launch
	-- with one air hit (Spinning Back Kick, knockdown) in round 6 and round 7 alike, so the third hit was whatever it
	-- pressed after the knockdown, which moved with the round-7 per-fighter skill offsets (11/16 for 12 needed). A
	-- conversion is now what the name says: the launcher plus at least one air hit, ending in a knockdown.
	test("hard converts a launcher into a short juggle and easy barely follows up", function()
		local function conversions(diff: string): (number, number)
			local success, totalHits = 0, 0
			for i = 1, 16 do
				local m = Sim.newMatch("Training", "Kael", "Sierra")
				Sim.setDifficulty(m, diff)
				m.aiSeed = i
				m.frame = i * 31
				place(m, 3)
				m.fighters[1].dummy = "Stand"
				Sim.queueAttack(m.fighters[2], "SwitchKick")
				local hits, airHits, knockdown = 0, 0, false
				for _ = 1, 240 do
					Sim.trainerInput(m, 2)
					for _, e in Sim.step(m) do
						if e.attacker == 2 and (e.kind == "Hit" or e.kind == "KO") then
							hits += 1
							if e.air then airHits += 1 end
						end
						if e.attacker == 2 and e.knockdown == true then knockdown = true end
					end
					settle(m)
				end
				totalHits += hits
				if airHits >= 2 and knockdown then success += 1 end
			end
			return success, totalHits
		end
		local hard, hardHits = conversions("Hard")
		local _, easyHits = conversions("Easy")
		expect.truthy(hard >= 12, "Hard juggle conversions " .. hard .. "/16")
		expect.truthy(easyHits < hardHits, "Easy lands fewer juggle hits " .. easyHits .. " vs " .. hardHits)
	end)

	-- Round 7 retune: each fighter's CPU now has its own skill offset per level (CombatAI.FighterSkill), so its perception
	-- delay can differ from the level's shared table by a frame or two; the bound is the CPU's own delay (paramsFor).
	test("trainer does not read live input before its perception delay", function()
		for _, diff in { "Normal", "Hard" } do
			local m = Sim.newMatch("Training", "Sierra", "Kael")
			Sim.setDifficulty(m, diff)
			place(m, 3)
			local cpu = m.fighters[2]
			Sim.queueAttack(m.fighters[1], "LowSweep")
			Sim.trainerInput(m, 2)
			expect.falsy(cpu.input.crouch, "no pre-startup input-buffer read")
			for _ = 1, AI.paramsFor(diff, "Kael", "Sierra").reactionDelay - 1 do
				Sim.step(m)
				Sim.trainerInput(m, 2)
				expect.falsy(cpu.input.crouch, diff .. " has no zero-reaction low guard")
			end
		end
	end)

	test("hard opens up a standing guard with lows and throws", function()
		local totalSeconds, lowsAndThrows, attacks = 0, 0, 0
		for seed = 1, 4 do
			local m = Sim.newMatch("Match", "Kael", Roster.order[seed + 1])
			Sim.setDifficulty(m, "Hard")
			m.aiSeed = seed
			while m.phase ~= "Fight" do Sim.step(m) end
			local start = m.frame
			while m.phase == "Fight" and m.frame - start < Config.RoundFrames do
				Sim.trainerInput(m, 2)
				for _, e in Sim.step(m) do
					if e.attacker == 2 and (e.kind == "Hit" or e.kind == "Block" or e.kind == "Whiff" or e.kind == "ThrowStart" or e.kind == "KO") then
						attacks += 1
						if e.height == "Low" or e.height == "Throw" then lowsAndThrows += 1 end
					end
				end
				settle(m)
			end
			totalSeconds += (m.frame - start) / Config.FPS
		end
		expect.truthy(totalSeconds / 4 <= 35, string.format("Hard beats a standing guard in %.1f s on average", totalSeconds / 4))
		expect.truthy(lowsAndThrows / math.max(1, attacks) >= 0.3, string.format("lows and throws share %.2f", lowsAndThrows / math.max(1, attacks)))
	end)

	test("CPU movement is calm and its attacks are in range", function()
		local seconds, flips, steps, dashes, attacks, outOfRange, launchers = 0, 0, 0, 0, 0, 0, 0
		for seed = 1, 2 do
			local m = Sim.newMatch("Match", Roster.order[seed * 2], Roster.order[seed * 2 + 1])
			m.aiSeed = seed
			local lastX = { 0, 0 }
			local lastState = { "Idle", "Idle" }
			local guard = 0
			while m.phase ~= "MatchOver" and guard < 40000 do
				m.difficulty = "Normal"; Sim.trainerInput(m, 1)
				m.difficulty = "Hard"; Sim.trainerInput(m, 2)
				Sim.step(m)
				guard += 1
				if m.phase == "Fight" and m.hitstop == 0 then
					seconds += 1 / Config.FPS
					for i, f in m.fighters do
						local x = f.input.moveX
						if x ~= 0 then
							if lastX[i] ~= 0 and x ~= lastX[i] then flips += 1 end
							lastX[i] = x
						end
						if f.state == "Sidestep" and lastState[i] ~= "Sidestep" then steps += 1 end
						if (f.state == "Dash" or f.state == "Backdash") and lastState[i] ~= f.state then dashes += 1 end
						if f.move and f.moveFrame == 1 and f.state == "Startup" then
							local def = Sim.moveDef(f, f.move)
							if def.chainFrom == nil then
								attacks += 1
								local o = m.fighters[3 - i]
								local d = (Vector3.new(o.pos.X, 0, o.pos.Z) - Vector3.new(f.pos.X, 0, f.pos.Z)).Magnitude
								if d > AI.threatOf(def) + 0.6 then outOfRange += 1 end
								if def.onHit == "LAUNCH" then launchers += 1 end
							end
						end
						lastState[i] = f.state
					end
				end
			end
		end
		local fighterSeconds = seconds * 2
		expect.truthy(flips / fighterSeconds <= 0.5, string.format("walk direction flips %.2f/s", flips / fighterSeconds))
		expect.truthy(steps / fighterSeconds * 60 <= 4, string.format("sidesteps %.1f/min", steps / fighterSeconds * 60))
		expect.truthy(dashes / fighterSeconds * 60 <= 8, string.format("dashes %.1f/min", dashes / fighterSeconds * 60))
		expect.truthy(attacks > 20, "both CPUs attack")
		expect.truthy(outOfRange / attacks <= 0.06, string.format("attacks from out of range %.2f", outOfRange / attacks))
		expect.truthy(launchers / attacks <= 0.12, string.format("launcher share %.2f", launchers / attacks))
	end)

	test("difficulty levels are ordered in CPU vs CPU matches", function()
		-- 24 matches per pairing (sides alternate, characters cycle): 12 were too few for a stable ordering check.
		local hardWins, normalWins = 0, 0
		for i = 1, 24 do
			local a = Roster.order[(i - 1) % #Roster.order + 1]
			local b = Roster.order[(i + 2) % #Roster.order + 1]
			if i % 2 == 0 then
				if cpuMatch("Hard", "Normal", a, b, i) == 1 then hardWins += 1 end
				if cpuMatch("Normal", "Easy", a, b, i) == 1 then normalWins += 1 end
			else
				if cpuMatch("Normal", "Hard", a, b, i) == 2 then hardWins += 1 end
				if cpuMatch("Easy", "Normal", a, b, i) == 2 then normalWins += 1 end
			end
		end
		expect.truthy(hardWins >= 16, "Hard beats Normal " .. hardWins .. "/24")
		expect.truthy(normalWins >= 18, "Normal beats Easy " .. normalWins .. "/24")
	end)

	test("a beginner who walks in and presses buttons can beat Easy but not Hard", function()
		local buttons = { "LeadPunch", "RearPunch", "LeadKick", "RearKick", "Throw" }
		local function beginnerMatch(diff: string, char: string, cpuChar: string, seed: number): number
			local m = Sim.newMatch("Match", char, cpuChar)
			Sim.setDifficulty(m, diff)
			m.aiSeed = seed
			local rng = seed * 7919 + 13
			local function rand(): number rng = (rng * 16807) % 2147483647; return rng / 2147483647 end
			local nextAt = 0
			local guard = 0
			while m.phase ~= "MatchOver" and guard < 40000 do
				local f, o = m.fighters[1], m.fighters[2]
				if m.phase == "Fight" and m.hitstop == 0 and m.frame >= nextAt then
					local d = (Vector3.new(o.pos.X, 0, o.pos.Z) - Vector3.new(f.pos.X, 0, f.pos.Z)).Magnitude
					if d > 4.3 then
						if f.input.moveX ~= 1 then Sim.setMovement(m, 1, 1, 0) end
						f.input.crouch = false
						nextAt = m.frame + 6
					else
						nextAt = m.frame + 8 + math.floor(rand() * 13)
						local r = rand()
						local x = if r < 0.25 then 1 elseif r < 0.35 then -1 else 0
						if f.input.moveX ~= x then Sim.setMovement(m, 1, x, 0) end
						f.input.crouch = rand() < 0.15
						if rand() < 0.8 then Sim.press(m, 1, buttons[1 + math.floor(rand() * #buttons)]) end
					end
				end
				Sim.trainerInput(m, 2)
				Sim.step(m)
				guard += 1
			end
			return m.winner
		end
		local easyWins, hardWins = 0, 0
		for i = 1, 6 do
			local char = Roster.order[i]
			local cpuChar = Roster.order[(i + 1) % #Roster.order + 1]
			if beginnerMatch("Easy", char, cpuChar, i) == 1 then easyWins += 1 end
			if beginnerMatch("Hard", char, cpuChar, i) == 1 then hardWins += 1 end
		end
		expect.truthy(easyWins >= 1, "beginner beats Easy in " .. easyWins .. "/6")
		expect.truthy(hardWins == 0, "beginner beats Hard in " .. hardWins .. "/6")
	end)
end
