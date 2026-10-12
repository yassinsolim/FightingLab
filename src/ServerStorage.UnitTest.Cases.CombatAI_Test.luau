--!strict
-- CombatAI: perception delay, persistent decisions, adaptation to repeated moves, throw breaks and wake-up guard.
local Lab = game:GetService("ReplicatedStorage"):WaitForChild("FightingLab")
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

local function flat(f: Sim.Fighter, o: Sim.Fighter): number
	local d = o.pos - f.pos
	return math.sqrt(d.X * d.X + d.Z * d.Z)
end

local function settle(m: Sim.Match)
	while m.hitstop > 0 do Sim.step(m) end
end

-- P1 repeats `key` whenever it is free and in range (walks in otherwise); P2 is the CPU. Returns how many of the
-- repeats after the first four were blocked and how many hit.
local function spamLow(diff: string, char: string, key: string, attempts: number): (number, number)
	local m = Sim.newMatch("Match", char, "Kael")
	Sim.setDifficulty(m, diff)
	m.aiSeed = 3
	while m.phase ~= "Fight" do Sim.step(m) end
	local def = Roster.getMove(char, key)
	local f = m.fighters[1]
	local started, blocked, hit = 0, 0, 0
	local guard = 0
	while started < attempts and m.phase == "Fight" and guard < 30000 do
		guard += 1
		local o = m.fighters[2]
		if f.move == nil and not Sim.isLocked(f) and f.throwInfo == nil then
			if flat(f, o) > def.range + def.advance - 0.2 then
				f.input.crouch = false
				if f.input.moveX ~= 1 then Sim.setMovement(m, 1, 1, 0) end
			else
				if f.input.moveX ~= 0 then Sim.setMovement(m, 1, 0, 0) end
				Sim.queueAttack(f, key)
			end
		end
		Sim.trainerInput(m, 2)
		for _, e in Sim.step(m) do
			if e.attacker == 1 and e.move == key and started > 4 then
				if e.kind == "Block" then blocked += 1 elseif e.kind == "Hit" or e.kind == "KO" then hit += 1 end
			end
		end
		if f.move == key and f.moveFrame == 1 then started += 1 end
		settle(m)
		o.health = math.max(o.health, 40)
		f.health = math.max(f.health, 40)
	end
	return blocked, hit
end

return function(t)
	local test, expect = t.test, t.expect

	test("perception shows the opponent as it was a reaction delay ago", function()
		local m = Sim.newMatch("Training", "Kael", "Sierra")
		place(m, 3)
		for _ = 1, 30 do AI.observe(m); Sim.step(m) end
		Sim.queueAttack(m.fighters[1], "Jab")
		for _ = 1, 5 do AI.observe(m); Sim.step(m) end
		AI.observe(m)
		expect.equal(AI.perceive(m, 1, 0).move, "Jab", "no delay sees the jab")
		expect.equal(AI.perceive(m, 1, 20).move, nil, "20 frames ago there was no jab yet")
		expect.equal(AI.perceive(m, 1, 20).state, "Idle")
		local fresh = Sim.newMatch("Training")
		expect.equal(AI.perceive(fresh, 1, 22).state, "Idle", "no history falls back to a neutral view")
	end)

	test("decisions persist instead of changing every frame", function()
		for _, diff in { "Easy", "Normal", "Hard" } do
			local m = Sim.newMatch("Match", "Kael", "Goran")
			Sim.setDifficulty(m, diff)
			m.aiSeed = 5
			while m.phase ~= "Fight" do Sim.step(m) end
			local cpu = m.fighters[2]
			local changes, frames, lastIntent = 0, 0, nil
			for _ = 1, 900 do
				Sim.trainerInput(m, 2)
				Sim.step(m)
				settle(m)
				if m.phase ~= "Fight" then break end
				frames += 1
				local brain = (cpu :: any).ai
				if brain and brain.intent ~= lastIntent then changes += 1; lastIntent = brain.intent end
			end
			expect.truthy(changes / (frames / Config.FPS) <= 4, string.format("%s intent changes %.1f/s", diff, changes / (frames / Config.FPS)))
		end
	end)

	test("a repeated slow low gets crouch-blocked more by stronger levels", function()
		local easyBlocked, easyHit = spamLow("Easy", "Rhys", "LowSweep", 22)
		local hardBlocked, hardHit = spamLow("Hard", "Rhys", "LowSweep", 22)
		local easyRate = easyBlocked / math.max(1, easyBlocked + easyHit)
		local hardRate = hardBlocked / math.max(1, hardBlocked + hardHit)
		expect.truthy(hardBlocked >= 4 and hardRate >= 0.7, string.format("Hard blocks the repeated sweep %d, hit %d", hardBlocked, hardHit))
		expect.truthy(hardRate > easyRate, string.format("Hard adapts better than Easy %.2f vs %.2f", hardRate, easyRate))
	end)

	test("hard breaks throws far more often than easy", function()
		local function breaks(diff: string): number
			local n = 0
			for i = 1, 20 do
				local m = Sim.newMatch("Match", "Kael", "Sierra")
				Sim.setDifficulty(m, diff)
				m.aiSeed = i
				while m.phase ~= "Fight" do Sim.step(m) end
				place(m, 2.8)
				Sim.press(m, 1, if i % 2 == 0 then "Throw" else "Throw2")
				for _ = 1, 60 do
					-- The CPU only acts once it is grabbed, so every throw connects and only the break is measured.
					if m.fighters[2].throwInfo ~= nil then Sim.trainerInput(m, 2) end
					for _, e in Sim.step(m) do if e.kind == "ThrowBreak" then n += 1 end end
					settle(m)
				end
			end
			return n
		end
		local hard, easy = breaks("Hard"), breaks("Easy")
		expect.truthy(hard >= 9, "Hard breaks " .. hard .. "/20")
		expect.truthy(easy <= 6 and easy < hard, "Easy breaks " .. easy .. "/20")
	end)

	test("hard wakes up guarding low against a sweep habit", function()
		local m = Sim.newMatch("Match", "Rhys", "Kael")
		Sim.setDifficulty(m, "Hard")
		m.aiSeed = 9
		while m.phase ~= "Fight" do Sim.step(m) end
		local cpu = m.fighters[2]
		local brain: any = nil
		Sim.trainerInput(m, 2)
		brain = (cpu :: any).ai
		assert(brain, "brain created")
		for i = 1, 6 do
			table.insert(brain.recent, { key = "LowSweep", height = "Low", start = m.frame - i * 40, onBlock = -16, startup = 18 })
		end
		while #brain.recent > 6 do table.remove(brain.recent, 1) end
		cpu.state = "Getup"
		cpu.stun = 6
		cpu.lastHit = { kind = "Hit", height = "Low", tier = "Heavy", counter = false, frame = m.frame - 30, move = "LowSweep", limb = "RearLeg", side = 0 } :: any
		local crouched = 0
		for _ = 1, 20 do
			if cpu.state == "Getup" then Sim.trainerInput(m, 2) end
			if cpu.input.crouch then crouched += 1 end
			Sim.step(m)
		end
		expect.truthy(crouched > 0, "Hard holds down while getting up after being swept")
		expect.equal(cpu.guard, "Crouch", "and comes up in a crouching guard")
	end)

	test("the CPU never starts attacks while the opponent is out of reach", function()
		local m = Sim.newMatch("Match", "Nia", "Lumi")
		Sim.setDifficulty(m, "Normal")
		m.aiSeed = 2
		while m.phase ~= "Fight" do Sim.step(m) end
		local cpu = m.fighters[2]
		local starts, far = 0, 0
		local p1 = m.fighters[1]
		for frame = 1, 1500 do
			-- P1 keeps backing off every other second.
			if p1.move == nil and not Sim.isLocked(p1) then
				local x = if (frame // 60) % 2 == 0 then -1 else 0
				if p1.input.moveX ~= x then Sim.setMovement(m, 1, x, 0) end
			end
			Sim.trainerInput(m, 2)
			Sim.step(m)
			settle(m)
			if cpu.move and cpu.moveFrame == 1 and cpu.state == "Startup" then
				local def = Sim.moveDef(cpu, cpu.move)
				if def.chainFrom == nil then
					starts += 1
					if flat(cpu, p1) > AI.threatOf(def) + 0.6 then far += 1 end
				end
			end
			if m.phase ~= "Fight" then break end
		end
		expect.truthy(starts > 0, "CPU attacks")
		expect.truthy(far <= math.max(1, starts * 0.05), string.format("out-of-range starts %d of %d", far, starts))
	end)

	test("a planned block punish comes out instead of a quick poke", function()
		-- Hard Lumi crouch-blocks Goran's leg sweep (-17): the launcher punish is buffered during blockstun and must not
		-- be replaced by the turn-taking poke on the first free frame.
		local launched = 0
		for seed = 1, 12 do
			local m = Sim.newMatch("Match", "Goran", "Lumi")
			Sim.setDifficulty(m, "Hard")
			m.aiSeed = seed
			while m.phase ~= "Fight" do Sim.step(m) end
			place(m, 3.0)
			local cpu = m.fighters[2]
			cpu.input.crouch = true
			for _ = 1, 4 do Sim.step(m) end
			Sim.queueAttack(m.fighters[1], "LegHook")
			local blocked, first = false, nil
			for _ = 1, 90 do
				if blocked then Sim.trainerInput(m, 2) end
				for _, e in Sim.step(m) do if e.kind == "Block" and e.attacker == 1 then blocked = true end end
				settle(m)
				if blocked and cpu.move ~= nil and first == nil then first = cpu.move end
			end
			if first == "FlipKick" then launched += 1 end
		end
		expect.truthy(launched >= 8, "Hard launches the blocked sweep " .. launched .. "/12")
	end)

	test("Easy matchup adjustments touch only Easy", function()
		for _, a in Roster.order do
			for _, b in Roster.order do
				expect.equal(AI.paramsFor("Normal", a, b), AI.params("Normal"), "Normal " .. a .. " vs " .. b)
				expect.equal(AI.paramsFor("Hard", a, b), AI.params("Hard"), "Hard " .. a .. " vs " .. b)
				local easy = AI.paramsFor("Easy", a, b)
				local scale = math.min((AI.Matchups.Easy.vs[b] or 1) * (AI.Matchups.Easy.as[a] or 1), AI.Matchups.Easy.cap / AI.params("Easy").turnTake)
				expect.truthy(math.abs(easy.turnScale - scale) < 1e-9, "Easy " .. a .. " vs " .. b)
				-- even the sharpest Easy matchup counter-attacks less than Normal
				expect.truthy(easy.turnTake * easy.turnScale < AI.params("Normal").turnTake, "Easy stays below Normal " .. a .. " vs " .. b)
				expect.truthy(easy.blockPunish < AI.params("Normal").blockPunish and easy.whiffPunish < AI.params("Normal").whiffPunish, "Easy punishes less than Normal " .. a .. " vs " .. b)
				expect.truthy(easy.crowdJab >= 0 and easy.crowdJab <= 1, "crowdJab is a chance " .. a .. " vs " .. b)
				expect.equal(AI.paramsFor("Normal", a, b).crowdJab, 0, "only Easy mashes when crowded")
			end
		end
		expect.equal(AI.params("Easy").turnScale, 1, "the shared Easy table is not modified")
	end)

	-- Round 4 (ui report): after the player threw it, the CPU sat in a crouch for minutes. Every remembered read must
	-- fade once the player stops, and the CPU must stand up and act again.
	local MOVING = { Walk = true, Backwalk = true, Dash = true, Backdash = true, Sidestep = true }
	-- The player (P1) walks in and throws until `throws` throws land, then only waits (or walks back and forth). Returns
	-- the throws landed, the frames from the CPU's first free frame to its first attack or deliberate move, and its
	-- longest crouch (outside its own moves) during the next 8 s. `level` "Dummy" = the Training fighting dummy.
	local function throwThenIdle(level: string, cpuChar: string, seed: number, throws: number, walk: boolean): (number, number, number)
		local playerChar = if cpuChar == "Goran" then "Kael" else "Goran"
		local m: Sim.Match
		local stepOnce: () -> { Sim.Event }
		if level == "Dummy" then
			local MatchRunner = require(Lab:WaitForChild("MatchRunner")) :: any
			local runner = MatchRunner.new()
			runner:configure({ mode = "Training", p1Id = playerChar, p2Id = cpuChar, human1 = true, human2 = false })
			runner.match.aiSeed = seed
			runner:setDummy("Fight")
			m = runner.match
			stepOnce = function() return runner:step().events end
		else
			m = Sim.newMatch("Match", playerChar, cpuChar)
			m.difficulty = level :: any
			m.aiSeed = seed
			while m.phase ~= "Fight" do Sim.step(m) end
			stepOnce = function() Sim.trainerInput(m, 2); return Sim.step(m) end
		end
		local p, cpu = m.fighters[1], m.fighters[2]
		local landed, frames = 0, 0
		while landed < throws and frames < 3600 do
			frames += 1
			if Sim.isFree(p) and p.throwInfo == nil then
				if flat(p, cpu) > 2.9 then
					if p.input.moveX ~= 1 then Sim.setMovement(m, 1, 1, 0) end
				else
					if p.input.moveX ~= 0 then Sim.setMovement(m, 1, 0, 0) end
					if Sim.isFree(cpu) and not cpu.crouched then Sim.press(m, 1, "Throw") end
				end
			end
			for _, e in stepOnce() do if e.kind == "ThrowHit" and e.attacker == 1 then landed += 1 end end
			p.health = p.maxHealth
			cpu.health = math.max(cpu.health, cpu.maxHealth * 0.5)
		end
		Sim.setMovement(m, 1, 0, 0)
		local freeAt, actAt, run, longest = nil :: number?, nil :: number?, 0, 0
		for t = 1, 1200 do
			if walk and Sim.isFree(p) then
				local x = if (t // 40) % 2 == 0 then 1 else -1
				if p.input.moveX ~= x then Sim.setMovement(m, 1, 0, 0); Sim.setMovement(m, 1, x, 0) end
			end
			stepOnce()
			p.health = p.maxHealth
			cpu.health = math.max(cpu.health, cpu.maxHealth * 0.5)
			if freeAt == nil and Sim.isFree(cpu) then freeAt = t end
			if freeAt ~= nil then
				if t - freeAt > 480 then break end
				if actAt == nil and ((cpu.move ~= nil and cpu.moveFrame == 1) or MOVING[cpu.state]) then actAt = t end
				if cpu.crouched and cpu.move == nil then run += 1; longest = math.max(longest, run) else run = 0 end
			end
		end
		return landed, if freeAt and actAt then actAt - freeAt else math.huge, longest
	end

	test("after landing throws on it, the CPU stands up and acts again (every level and the fighting dummy)", function()
		for _, level in { "Easy", "Normal", "Hard", "Dummy" } do
			for i, id in Roster.order do
				for _, walk in { false, true } do
					local landed, act, crouch = throwThenIdle(level, id, 4242 + i, 2, walk)
					local what = string.format("%s %s after %d throws, player %s", level, id, landed, if walk then "walks" else "waits")
					expect.truthy(landed >= 2, what .. ": throws land")
					expect.truthy(act <= 3 * Config.FPS, string.format("%s: first attack or move after %.1f s", what, act / Config.FPS))
					expect.truthy(crouch <= 1.5 * Config.FPS, string.format("%s: crouched %.1f s in a row", what, crouch / Config.FPS))
				end
			end
		end
	end)

	test("old throw and low reads fade: a remembered streak no longer makes the CPU crouch", function()
		local m = Sim.newMatch("Match", "Goran", "Kael")
		m.difficulty = "Hard"
		m.aiSeed = 11
		while m.phase ~= "Fight" do Sim.step(m) end
		place(m, 3.2)
		Sim.trainerInput(m, 2)
		local cpu = m.fighters[2]
		local brain: any = (cpu :: any).ai
		assert(brain, "brain created")
		-- Six throws remembered, the last one long ago (6 s): no streak, no crouch habit, no pressure read.
		for i = 1, 6 do
			table.insert(brain.recent, { key = "Throw", height = "Throw", start = m.frame - 360 - i * 30, onBlock = 0, startup = 11, lead = 12 })
		end
		local crouched, longest, attacked = 0, 0, false
		for _ = 1, 300 do
			Sim.trainerInput(m, 2)
			Sim.step(m)
			settle(m)
			if cpu.crouched and cpu.move == nil then crouched += 1; longest = math.max(longest, crouched) else crouched = 0 end
			if cpu.move ~= nil then attacked = true end
			m.fighters[1].health = m.fighters[1].maxHealth
		end
		expect.truthy(longest <= 1.5 * Config.FPS, string.format("crouched %.1f s on an old read", longest / Config.FPS))
		expect.truthy(attacked, "the CPU attacks a player who does nothing")
	end)

	test("one blocked attack or one throw is remembered once", function()
		-- A hit jab (4 frames of hitstop) and a landed throw (the throw has its own clock) must each be remembered once.
		for _, key in { "Jab", "Throw" } do
			local checked = 0
			for seed = 1, 12 do
				local m = Sim.newMatch("Match", "Kael", "Sierra")
				m.difficulty = "Normal"
				m.aiSeed = seed
				while m.phase ~= "Fight" do Sim.step(m) end
				place(m, if key == "Throw" then 2.8 else 3.6)
				Sim.press(m, 1, if key == "Throw" then "Throw" else "LeadPunch")
				local landed = false
				for _ = 1, 200 do
					Sim.trainerInput(m, 2)
					for _, e in Sim.step(m) do
						if e.attacker == 1 and e.move == key and (e.kind == "Hit" or e.kind == "Block" or e.kind == "ThrowHit") then landed = true end
					end
					m.fighters[1].health = m.fighters[1].maxHealth
				end
				if landed then
					checked += 1
					local brain: any = (m.fighters[2] :: any).ai
					local n = 0
					for _, r in brain.recent do if r.key == key then n += 1 end end
					expect.equal(n, 1, string.format("%s (seed %d) logged once through hitstop / the throw clock", key, seed))
				end
			end
			expect.truthy(checked >= 3, key .. " landed in enough runs to check: " .. checked)
		end
	end)

	test("CPU vs CPU: nobody stays in range for long without attacking", function()
		for _, level in { "Easy", "Normal", "Hard" } do
			local worst = 0
			for i, pair in { { "Kael", "Lumi" }, { "Goran", "Sierra" }, { "Rhys", "Nia" }, { "Lumi", "Goran" } } do
				local m = Sim.newMatch("Match", pair[1], pair[2])
				m.difficulty = level :: any
				m.aiSeed = 40 + i
				local passive = { 0, 0 }
				local guard = 0
				while m.phase ~= "MatchOver" and guard < 20000 do
					guard += 1
					Sim.trainerInput(m, 1); Sim.trainerInput(m, 2)
					Sim.step(m)
					if m.phase ~= "Fight" then passive = { 0, 0 } end
					if m.phase == "Fight" and m.hitstop == 0 then
						for j, f in m.fighters do
							local o = m.fighters[3 - j]
							local engage = math.max(f.character.stats.preferredRange, AI.pokeRange(f.character) - 0.5) + 0.4
							if f.move ~= nil and f.moveFrame == 1 then passive[j] = 0
							elseif Sim.isFree(f) and flat(f, o) <= engage then passive[j] += 1; worst = math.max(worst, passive[j]) end
						end
					end
				end
			end
			expect.truthy(worst <= 6 * Config.FPS, string.format("%s: %.1f s in range without an attack", level, worst / Config.FPS))
		end
	end)
end
