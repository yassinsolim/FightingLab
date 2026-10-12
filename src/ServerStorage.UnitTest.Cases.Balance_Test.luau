--!strict
-- Balance / anti-cheese guards (contract 0.8): punishable launchers and power lows, honest block advantage, juggle cap,
-- safe wake-up, no sidestep invulnerability, and one-move spam or button mashing cannot beat Normal or Hard.
local Lab = game:GetService("ReplicatedStorage"):WaitForChild("FightingLab")
local Sim = require(Lab:WaitForChild("CombatSim"))
local Config = require(Lab:WaitForChild("CombatConfig"))
local Roster = require(Lab:WaitForChild("Roster"))

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

local function reach(def: Roster.MoveDef): number
	return def.range + def.advance
end

local function prefix(def: Roster.MoveDef): string?
	return string.match(def.input, "^(%a+)%+")
end

local function flat(m: Sim.Match): number
	local d = m.fighters[2].pos - m.fighters[1].pos
	return math.sqrt(d.X * d.X + d.Z * d.Z)
end

-- One-move spammer (walks into range, then presses the move whenever free). Slot 1.
local function spamBot(key: string): (Sim.Match) -> ()
	return function(m: Sim.Match)
		local f = m.fighters[1]
		local def = f.character.moves[key]
		f.input.block = false
		if f.health <= 0 or Sim.isLocked(f) or f.move ~= nil or f.throwInfo ~= nil then return end
		local p = prefix(def)
		local threat = if def.height == "Throw" then math.max(def.range, Config.Separation + 0.05) else reach(def)
		if flat(m) > threat - 0.15 then
			f.input.crouch = false
			if f.input.moveX ~= 1 then Sim.setMovement(m, 1, 1, 0) end
			return
		end
		if f.input.moveX ~= 0 then Sim.setMovement(m, 1, 0, 0) end
		f.input.crouch = p == "d" or p == "df" or p == "db"
		Sim.queueAttack(f, key)
	end
end

local function botMatch(bot: (Sim.Match) -> (), botChar: string, cpuChar: string, diff: string, seed: number): number
	local m = Sim.newMatch("Match", botChar, cpuChar)
	Sim.setDifficulty(m, diff)
	m.aiSeed = seed
	local guard = 0
	while m.phase ~= "MatchOver" and guard < 40000 do
		if m.phase == "Fight" and m.hitstop == 0 then bot(m) end
		Sim.trainerInput(m, 2)
		Sim.step(m)
		guard += 1
	end
	return m.winner
end

return function(t)
	local test, expect = t.test, t.expect

	test("launchers and power lows are punishable at their maximum range by every character", function()
		for _, aId in Roster.order do
			local c = Roster.get(aId)
			for _, key in c.moveOrder do
				local def = c.moves[key]
				local mustPunish = def.onHit == "LAUNCH" or (def.height == "Low" and def.onHit == "KND")
				if mustPunish then
					local blockedAt = def.range + (def.push or 0) * 0.35
					for _, dId in Roster.order do
						local dc = Roster.get(dId)
						local found = false
						for _, pKey in dc.moveOrder do
							local p = dc.moves[pKey]
							local pre = prefix(p)
							if p.chainFrom == nil and p.height ~= "Throw" and p.damage > 0 and pre ~= "dash" and pre ~= "ss"
								and p.startup + 1 <= -def.onBlock and reach(p) - 0.1 >= blockedAt then
								found = true
								break
							end
						end
						expect.truthy(found, aId .. "." .. key .. " is punishable by " .. dId)
					end
				end
			end
		end
	end)

	test("no attack is better than +1 on block and pressure always leaves a gap", function()
		expect.truthy(Config.LandingFrames >= 34 and Config.GetupFrames >= 26, "falls and getups take about a second (not rushed)")
		expect.truthy((Config.LandingFrames + Config.GetupFrames) / Config.FPS >= 0.95, "floor to standing ~1 s")
		local fastest = math.huge
		for _, id in Roster.order do
			local c = Roster.get(id)
			for _, key in c.moveOrder do
				local def = c.moves[key]
				if def.height ~= "Throw" and def.damage > 0 then
					fastest = math.min(fastest, def.startup + 1)
					expect.truthy(def.onBlock <= 1, id .. "." .. key .. " on block " .. def.onBlock)
				end
			end
		end
		expect.truthy(fastest - 1 >= 2, "a blocked +1 move leaves the defender free frames before the fastest follow-up")
		for _, id in Roster.order do
			for _, key in Roster.get(id).moveOrder do
				local def = Roster.getMove(id, key)
				if def.height == "Throw" then
					expect.truthy(def.recovery >= 30, id .. "." .. key .. " whiffed throw is punishable")
				end
			end
		end
	end)

	test("juggles stay below 45 percent of the smallest health bar", function()
		local minHealth = math.huge
		for _, id in Roster.order do minHealth = math.min(minHealth, Roster.get(id).stats.maxHealth) end
		local worst, worstName = 0, ""
		local rng = 12345
		local function rand(): number rng = (rng * 16807) % 2147483647; return rng / 2147483647 end
		for _, aId in Roster.order do
			local c = Roster.get(aId)
			local fast = {}
			for _, key in c.moveOrder do
				local def = c.moves[key]
				if def.chainFrom == nil and def.height ~= "Throw" and def.damage > 0 and def.startup + 1 <= 18 and prefix(def) ~= "dash" and prefix(def) ~= "ss" then table.insert(fast, key) end
			end
			for _, launcher in c.moveOrder do
				if c.moves[launcher].onHit == "LAUNCH" then
					for _ = 1, 40 do
						local m = Sim.newMatch("Training", aId, "Kael")
						m.fighters[2].dummy = "Stand"
						place(m, 3)
						Sim.queueAttack(m.fighters[1], launcher)
						local damage, airborne, frames = 0, false, 0
						local waitUntil = 0
						while frames < 260 do
							frames += 1
							local a, d = m.fighters[1], m.fighters[2]
							if airborne and a.move == nil and not Sim.isLocked(a) and frames >= waitUntil and d.state == "Airborne" then
								local key = fast[1 + math.floor(rand() * #fast)]
								local def = c.moves[key]
								local x = if flat(m) > reach(def) - 0.2 then 1 else 0
								if a.input.moveX ~= x then Sim.setMovement(m, 1, x, 0) end
								a.input.crouch = prefix(def) == "d" or prefix(def) == "df" or prefix(def) == "db"
								Sim.queueAttack(a, key)
								waitUntil = frames + math.floor(rand() * 6)
							end
							for _, e in Sim.step(m) do
								if e.attacker == 1 and (e.kind == "Hit" or e.kind == "KO") then
									damage += e.damage
									if e.launch then airborne = true end
								end
							end
							settle(m)
							if airborne and (d.state == "Landing" or d.state == "Getup" or d.state == "Idle") then break end
							if not airborne and frames > 40 then break end
						end
						if damage > worst then worst, worstName = damage, aId .. "." .. launcher end
					end
				end
			end
		end
		expect.truthy(worst > 0, "launchers connect")
		expect.truthy(worst <= 0.45 * minHealth, string.format("worst juggle %s %d damage of %d", worstName, worst, minHealth))
	end)

	test("getting up is safe: invulnerable getup and the first free frame guards", function()
		for _, aId in Roster.order do
			local c = Roster.get(aId)
			local mid, low = nil, nil
			for _, key in c.moveOrder do
				local def = c.moves[key]
				local pre = prefix(def)
				if def.chainFrom == nil and def.damage > 0 and pre ~= "dash" and pre ~= "ss" then
					if def.height == "Mid" and not def.smid and (mid == nil or def.startup < c.moves[mid].startup) then mid = key end
					if def.height == "Low" and (low == nil or def.startup < c.moves[low].startup) then low = key end
				end
			end
			for _, case in { { key = mid, crouch = false }, { key = low, crouch = true } } do
				local key = case.key :: string
				local def = c.moves[key]
				for _, getup in { "Stand", "BackRoll", "SideRoll" } do
					local firstDelay = Config.LandingFrames + Config.GetupFrames - 24
					local lastDelay = Config.LandingFrames + Config.GetupFrames + Config.RollFrames + 12
					local blocks = 0
					for delay = firstDelay, lastDelay, 2 do
						local m = Sim.newMatch("Training", aId, "Sierra")
						m.fighters[2].dummy = nil
						place(m, 2.8)
						local d = m.fighters[2]
						d.state = "Landing"; d.stun = Config.LandingFrames; d.knockdown = "FaceUp"
						d.input.crouch = case.crouch
						local hits = 0
						for frame = 1, 140 do
							if getup == "BackRoll" and d.state == "Landing" then d.input.moveX = -1
							elseif getup == "SideRoll" and d.state == "Landing" and Config.LandingFrames - d.stun == Config.GetupChoiceFrame - 1 then
								Sim.setMovement(m, 2, 0, 1); Sim.setMovement(m, 2, 0, 0)
							elseif d.state ~= "Landing" then d.input.moveX = 0 end
							if frame == delay + 1 then Sim.queueAttack(m.fighters[1], key) end
							local a = m.fighters[1]
							if a.move == nil and not Sim.isLocked(a) and frame > delay + 1 and a.input.attack == nil and flat(m) > reach(def) - 0.2 then
								Sim.setMovement(m, 1, 1, 0)
							elseif a.input.moveX ~= 0 then
								Sim.setMovement(m, 1, 0, 0)
							end
							for _, e in Sim.step(m) do
								if e.attacker == 1 and (e.kind == "Hit" or e.kind == "KO") then hits += 1 end
								if e.attacker == 1 and e.kind == "Block" then blocks += 1 end
							end
							settle(m)
						end
						expect.equal(hits, 0, string.format("%s.%s %d frames after the knockdown vs %s getup", aId, key, delay, getup))
					end
					if getup == "Stand" then
						expect.truthy(blocks > 0, string.format("%s.%s reaches the rising fighter, who guards it", aId, key))
					end
				end
			end
		end
	end)

	test("sidesteps have no invulnerability: a homing move connects on every sidestep frame", function()
		local def = Roster.getMove("Kael", "WeaveHook")
		expect.truthy(def.homing == true, "Kael's weave hook is the homing reference move")
		for frame = 1, Config.SidestepFrames + Config.SidestepRecovery do
			local m = Sim.newMatch("Training", "Kael", "Sierra")
			m.fighters[2].dummy = "Stand"
			place(m, 3.2)
			Sim.setMovement(m, 2, 0, 1); Sim.setMovement(m, 2, 0, 0)
			for _ = 1, frame do Sim.step(m) end
			local a = m.fighters[1]
			a.move = "WeaveHook"; a.moveName = def.name; a.moveFrame = def.startup; a.state = "Startup"; a.hasHit = false
			local hit = false
			for _ = 1, def.active + 1 do
				for _, e in Sim.step(m) do if e.attacker == 1 and e.kind == "Hit" then hit = true end end
				settle(m)
			end
			expect.truthy(hit, "homing hook catches sidestep frame " .. frame)
		end
	end)

	test("spamming one move does not beat Normal or Hard", function()
		-- Round-2 targets: at most 20 percent against Normal and 10 percent against Hard. The picks cover every
		-- fighter's jab, a launcher, a power low and the throw, plus the moves that used to be the worst spam starters.
		local played, wins = { Normal = 0, Hard = 0 }, { Normal = 0, Hard = 0 }
		local tail = { Goran = "RamSlam", Rhys = "SpinBackfist", Sierra = "Teep", Kael = "RisingUppercut" }
		for i, id in Roster.order do
			local c = Roster.get(id)
			local picks = { c.moveOrder[1] }
			for _, key in c.moveOrder do
				local def = c.moves[key]
				if def.chainFrom == nil and prefix(def) ~= "dash" and prefix(def) ~= "ss" then
					if def.onHit == "LAUNCH" and #picks < 2 then table.insert(picks, key) end
				end
			end
			for _, key in c.moveOrder do
				local def = c.moves[key]
				if def.height == "Low" and def.onHit == "KND" then table.insert(picks, key) break end
			end
			table.insert(picks, "Throw")
			if tail[id] and not table.find(picks, tail[id]) then table.insert(picks, tail[id]) end
			for _, key in picks do
				for _, diff in { "Normal", "Hard" } do
					local cpuChar = Roster.order[(i % #Roster.order) + 1]
					played[diff] += 1
					if botMatch(spamBot(key), id, cpuChar, diff, i) == 1 then wins[diff] += 1 end
				end
			end
		end
		expect.truthy(wins.Normal / played.Normal <= 0.2, string.format("spam bots won %d of %d vs Normal", wins.Normal, played.Normal))
		expect.truthy(wins.Hard / played.Hard <= 0.1, string.format("spam bots won %d of %d vs Hard", wins.Hard, played.Hard))
	end)
end
