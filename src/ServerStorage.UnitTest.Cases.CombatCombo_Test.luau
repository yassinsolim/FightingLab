--!strict
-- Round 6 (docs/design/movesets.md): every combo listed in a CharacterDef is played through CombatSim with its
-- frame-timed inputs (Sim.comboRun) against all six fighters (different heights, weights and health) and must connect
-- in full for its listed damage; the combo budget and the moveset sameness metric are pinned here too.
local RS = game:GetService("ReplicatedStorage")
local Lab = RS:WaitForChild("FightingLab")
local Sim = require(Lab:WaitForChild("CombatSim"))
local Roster = require(Lab:WaitForChild("Roster"))

type Result = { pressed: { string }, connected: { boolean }, damage: number, blocked: number, maxCombo: number, ultHits: number }

-- Plays `combo` for fighter 1 (attackerId) on a standing dummy (defenderId). Counter routes: the dummy starts its
-- jab so the opener lands during the jab's startup. Surge routes: the attacker starts at 20% health (in Surge).
local function playCombo(attackerId: string, defenderId: string, combo: Roster.ComboDef): Result
	local m = Sim.newMatch("Match", attackerId, defenderId)
	m.phase = "Fight"
	local a, d = m.fighters[1], m.fighters[2]
	a.pos = Vector3.zero
	d.pos = Vector3.new(combo.distance or 3.0, 0, 0)
	a.facing = Vector3.new(1, 0, 0)
	d.facing = Vector3.new(-1, 0, 0)
	d.dummy = "Stand"
	if combo.surge then a.health = math.floor(a.maxHealth * 0.2) end
	local run = Sim.comboRun(m, 1, combo.steps)
	local hp0 = d.health
	local comboAt: { [number]: number } = {}
	local stanceSeen: { [number]: boolean } = {}
	local blocked, maxCombo, ultHits = 0, 0, 0
	local counterAt: number? = nil
	local lastPress = 0
	for frame = 1, 1500 do
		local before = #run.pressed
		if m.hitstop == 0 then Sim.comboTick(run) end
		if #run.pressed > before then
			lastPress = frame
			local key = run.pressed[#run.pressed]
			if combo.counter and #run.pressed == 1 and key ~= "" then
				counterAt = frame + Roster.getMove(attackerId, key).startup - 7
			end
		end
		if counterAt == frame then Sim.queueAttack(d, d.character.moveOrder[1]) end
		for _, e in Sim.step(m) do
			if e.attacker == 1 then
				if e.kind == "Block" then blocked += 1 end
				if e.kind == "Hit" or e.kind == "UltHit" then
					if e.kind == "UltHit" then ultHits += 1 else maxCombo = math.max(maxCombo, e.combo) end
					for k, key in run.pressed do
						if key == e.move and comboAt[k] == nil then
							comboAt[k] = if e.kind == "UltHit" then 99 else e.combo
							break
						end
					end
				end
			end
		end
		if a.state == "Stance" and #run.pressed > 0 then stanceSeen[#run.pressed] = true end
		local settled = d.state == "Landing" or d.state == "Getup" or d.state == "Idle" or d.state == "KO"
		if run.step > #combo.steps and frame - lastPress > 60 and a.throwInfo == nil and settled then break end
	end
	-- A step connected when its move hit; after the opener every hit must keep the combo going (combo index > 1).
	local connected: { boolean } = {}
	local first = true
	for k, key in run.pressed do
		local def = if key ~= "" then a.character.moves[key] else nil
		if def == nil then connected[k] = false
		elseif def.toStance then connected[k] = stanceSeen[k] == true
		elseif comboAt[k] == nil then connected[k] = false
		else
			connected[k] = first or comboAt[k] > 1
			first = false
		end
	end
	return { pressed = run.pressed, connected = connected, damage = hp0 - d.health, blocked = blocked, maxCombo = maxCombo, ultHits = ultHits }
end

-- Sameness: for every input two fighters share (throws, the Ultimate and the 3+4 signature entry are universal by the
-- control scheme and excluded), the pair is "the same kind of move" when animation archetype, height, hit result,
-- counter-hit result and special properties (crush, armor, parry, catch, tumble, homing, stance cancel) all match.
local function resultKind(r: (number | string)?): string
	if r == "LAUNCH" or r == "KND" then return r :: string end
	return "-"
end
local function signatureOf(m: Roster.MoveDef): string
	local props = {}
	if m.props.highCrush then table.insert(props, "highCrush") end
	if m.props.lowCrush then table.insert(props, "lowCrush") end
	if m.props.armor then table.insert(props, "armor") end
	if m.props.parry then table.insert(props, "parry") end
	if m.props.catch then table.insert(props, "catch") end
	if m.tumble then table.insert(props, "tumble") end
	if m.homing then table.insert(props, "homing") end
	if m.stanceCancel then table.insert(props, "cancel:" .. m.stanceCancel) end
	return table.concat({ m.anim.archetype, m.height, resultKind(m.onHit), resultKind(m.onCounter), table.concat(props, ",") }, "|")
end
local function universal(m: Roster.MoveDef): boolean
	return m.height == "Throw" or m.cinematic ~= nil or m.toStance ~= nil
end
local function sameness(): (number, number, { string })
	local shared, same, list = 0, 0, {}
	local order = Roster.order
	for i = 1, #order do
		for j = i + 1, #order do
			local a, b = Roster.get(order[i]), Roster.get(order[j])
			local byInput: { [string]: Roster.MoveDef } = {}
			for _, k in a.moveOrder do
				local m = a.moves[k]
				if not universal(m) then byInput[m.input] = m end
			end
			for _, k in b.moveOrder do
				local mb = b.moves[k]
				local ma = byInput[mb.input]
				if ma and not universal(mb) then
					shared += 1
					if signatureOf(ma) == signatureOf(mb) then
						same += 1
						table.insert(list, order[i] .. "." .. ma.key .. " = " .. order[j] .. "." .. mb.key)
					end
				end
			end
		end
	end
	return same, shared, list
end

return function(t)
	local test, expect = t.test, t.expect

	for _, id in Roster.order do
		test(id .. " combos connect in full against every fighter for their listed damage", function()
			local c = Roster.get(id)
			for _, combo in c.combos do
				for _, foe in Roster.order do
					local r = playCombo(id, foe, combo)
					local label = string.format("%s combo '%s' (%s) vs %s", id, combo.name, combo.notation, foe)
					expect.equal(#r.pressed, #combo.steps, label .. " presses")
					for k, ok in r.connected do
						expect.truthy(ok, string.format("%s: step %d (%s -> %s) connects", label, k, combo.steps[k].input, r.pressed[k]))
					end
					expect.equal(r.blocked, 0, label .. " is never blocked")
					expect.truthy(math.abs(r.damage - combo.damage) <= 1, string.format("%s deals %d (listed %d)", label, r.damage, combo.damage))
					expect.truthy(r.maxCombo <= 7, label .. " juggle ends within 7 hits")
					if combo.kind == "ultimate" then
						expect.equal(r.ultHits, #c.moves.Ultimate.cinematic.impacts, label .. " plays every Ultimate impact")
					end
				end
			end
		end)
	end

	test("every fighter lists its combo routes inside the damage budget", function()
		for _, id in Roster.order do
			local c = Roster.get(id)
			local kinds: { [string]: boolean } = {}
			for i, combo in c.combos do
				kinds[combo.kind] = true
				if combo.counter then kinds.counter = true end
				expect.truthy(combo.difficulty >= 1 and combo.difficulty <= 5, id .. " " .. combo.name .. " difficulty 1-5")
				expect.truthy(#combo.notation > 0 and #combo.name > 0, id .. " " .. combo.name .. " is named and notated")
				for _, step in combo.steps do Sim.parseNotation(step.input) end
				if combo.kind == "ultimate" then
					-- Ultimate enders stay under 55% of the smallest health bar (Lumi, 90).
					expect.truthy(combo.surge == true, id .. " " .. combo.name .. " is played in Surge")
					expect.truthy(combo.damage <= 49, id .. " " .. combo.name .. " ultimate combo <= 55%")
				else
					-- Combos deal 30-45% of a 100 HP bar and never more than 45% of the smallest one (90). Round 7: the first
					-- route is the easy one (a launcher and one string), which trades a little damage for consistency: 25-40.
					local low = if i == 1 then 25 else 30
					expect.truthy(combo.damage >= low and combo.damage <= 40, id .. " " .. combo.name .. string.format(" damage %d in %d-40", combo.damage, low))
				end
			end
			expect.truthy(#c.combos >= 4, id .. " lists at least four combos")
			expect.truthy(kinds.launch, id .. " has a launch bread-and-butter")
			expect.truthy(kinds.counter or kinds.low, id .. " has a counter-hit or low route")
			expect.truthy(kinds.ultimate, id .. " has a combo ending in the Ultimate")
		end
	end)

	test("round 7: the first listed route is easy and no listed route types two buttons that merge into a chord", function()
		for _, id in Roster.order do
			local c = Roster.get(id)
			local first = c.combos[1]
			expect.equal(first.kind, "launch", id .. " lists its easy launch route first")
			expect.truthy(first.difficulty <= 2, id .. " first route difficulty 1-2")
			expect.truthy(#first.steps <= 5 and not first.counter and not first.surge, id .. " first route: at most 5 presses, no counter hit, no Surge")
			for _, step in first.steps do
				expect.falsy(string.find(step.input, "3+4", 1, true), id .. " first route uses no 3+4")
			end
			-- Two single buttons typed in a row must stay far enough apart that a person pressing them a little early or
			-- late never makes the 1+3 / 2+4 throw, the 1+2 Ultimate (always ready in practice) or the 3+4 signature.
			for _, combo in c.combos do
				for k = 2, #combo.steps do
					local a = string.match(combo.steps[k - 1].input, "(%d)$")
					local b = string.match(combo.steps[k].input, "(%d)$")
					local prevChord = string.find(combo.steps[k - 1].input, "%d%+%d$") ~= nil
					local thisChord = string.find(combo.steps[k].input, "%d%+%d$") ~= nil
					if a and b and not prevChord and not thisChord then
						local pair = a .. b
						local need = if pair == "34" or pair == "43" or pair == "13" or pair == "31" or pair == "24" or pair == "42" then 12 elseif pair == "12" or pair == "21" then 8 else 1
						expect.truthy(combo.steps[k].wait >= need, string.format("%s %s step %d (%s after %s) waits %d >= %d", id, combo.name, k, combo.steps[k].input, combo.steps[k - 1].input, combo.steps[k].wait, need))
					end
				end
			end
		end
	end)

	test("fighters do not share the same kind of move on the same input", function()
		-- Before round 6 (one template for six fighters): 33 of 113 shared inputs were the same kind of move (29%).
		local same, shared, list = sameness()
		print(string.format("[SAMENESS] %d of %d shared inputs are the same kind of move (%.1f%%): %s", same, shared,
			if shared > 0 then same / shared * 100 else 0, table.concat(list, ", ")))
		expect.truthy(shared >= 60, "fighters still share the basic input grid")
		expect.truthy(same / shared <= 0.08, "at most 8% of shared inputs are the same kind of move")
		for _, line in list do
			-- Only plain i10 jabs may stay identical across fighters.
			expect.truthy(string.find(line, "Jab", 1, true) ~= nil, "only jabs may match: " .. line)
		end
	end)

	test("round 7: every string is a natural combo on hit from every range its first hit reaches", function()
		-- Each follow-up pressed as early as possible; after the first hit the dummy guards whenever it is free, so a gap
		-- would be blocked and pushback that carried it out of reach would whiff. (Round 6: 13 of 22 strings.)
		local BUTTON = { LP = "LeadPunch", RP = "RearPunch", LK = "LeadKick", RK = "RearKick" }
		local natural, total = 0, 0
		for _, id in Roster.order do
			local c = Roster.get(id)
			local followers: { [string]: { string } } = {}
			for _, key in c.moveOrder do
				local from = c.moves[key].chainFrom
				if from then followers[from] = followers[from] or {}; table.insert(followers[from], key) end
			end
			local paths: { { string } } = {}
			local function walk(path: { string })
				local nexts = followers[path[#path]]
				if not nexts then if #path > 1 then table.insert(paths, table.clone(path)) end return end
				for _, k in nexts do local p = table.clone(path); table.insert(p, k); walk(p) end
			end
			for _, key in c.moveOrder do if c.moves[key].chainFrom == nil and followers[key] then walk({ key }) end end
			for _, path in paths do
				total += 1
				local root = c.moves[path[1]]
				local ok, reached = true, 0
				local d10 = 26
				while d10 <= math.floor((root.range + root.advance) * 10) + 3 do
					local m = Sim.newMatch("Training", id, "Goran")
					local a, t = m.fighters[1], m.fighters[2]
					a.pos = Vector3.zero; t.pos = Vector3.new(d10 / 10, 0, 0)
					if root.stance then Sim.enterStance(a, root.stance); a.stanceFrame = c.stances[root.stance].cancelFrom end
					Sim.queueAttack(a, path[1])
					local k, hits, result = 2, 0, nil
					for _ = 1, 400 do
						if k <= #path and a.move == path[k - 1] and a.moveFrame >= 2 and m.hitstop == 0 then
							Sim.press(m, 1, BUTTON[string.match(c.moves[path[k]].input, "([%a]+)%s*$")])
							k += 1
						end
						for _, e in Sim.step(m) do
							if e.attacker == 1 then
								if e.kind == "Hit" or e.kind == "KO" then
									hits += 1
									if hits == 1 then Sim.setDummy(m, "Guard") end
									if hits > 1 and e.combo < 2 then result = "gap" end
								elseif e.kind == "Block" or e.kind == "Whiff" then
									result = if hits == 0 then "nohit" else string.lower(e.kind)
								end
							end
						end
						if result or hits == #path then break end
					end
					if result ~= "nohit" then
						reached += 1
						if hits ~= #path then
							ok = false
							expect.truthy(false, string.format("%s %s from %.1f: hit %d %s", id, table.concat(path, ","), d10 / 10, hits + 1, tostring(result)))
						end
					end
					d10 += 3
				end
				expect.truthy(reached > 0, id .. " " .. path[1] .. " reaches")
				if ok then natural += 1 end
			end
		end
		print(string.format("[STRINGS] %d of %d strings are natural combos on hit", natural, total))
	end)

	-- Round 7 (motion request): natural strings must not come from reach the animation cannot show. A follow-up on hit
	-- steps in during its startup (real travel) and may connect at most Config.StringReach (0.3 studs) past its range;
	-- the distance is measured from where the attacker actually is when the hit connects (root advance and step-in
	-- included). Round-7 head before this fix: 51 strikes in 72 CPU matches and the string sweeps connected more than
	-- 0.3 studs past their range, up to 1.05.
	test("round 7: no strike connects more than 0.3 studs past its range; strings on hit step in instead", function()
		local Config = require(Lab:WaitForChild("CombatConfig"))
		local BUTTON = { LP = "LeadPunch", RP = "RearPunch", LK = "LeadKick", RK = "RearKick" }
		local lastAlong: { [any]: { move: string, along: number } } = {}
		local original = Sim.reach
		local worst, worstWhat, checked, stepped = -math.huge, "", 0, 0
		local function check(m: Sim.Match, e: Sim.Event, label: string, blockedRun: boolean)
			if e.kind ~= "Hit" and e.kind ~= "KO" and e.kind ~= "Block" then return end
			local a = m.fighters[e.attacker]
			local rec = lastAlong[a]
			local def = a.character.moves[e.move]
			if rec == nil or rec.move ~= e.move or def == nil or def.height == "Throw" or def.cinematic ~= nil then return end
			checked += 1
			local excess = rec.along - def.range
			if excess > worst then worst, worstWhat = excess, string.format("%s %s %s", label, a.characterId, e.move) end
			local step = (a :: any).stringStep or 0
			if step > 0 then stepped += 1 end
			expect.truthy(step <= ((Config :: any).StringStepIn or math.huge) + 1e-6, "step-in within its cap: " .. label .. " " .. e.move)
			if blockedRun then expect.equal(step, 0, "a follow-up on block never steps in: " .. label .. " " .. e.move) end
		end
		local ok, err = pcall(function()
			Sim.reach = function(a: any, t: any, name: string)
				local inReach, along, side = original(a, t, name)
				lastAlong[a] = { move = name, along = along }
				return inReach, along, side
			end
			-- Every string, from several distances its first hit reaches; once on hit (the dummy guards after hit 1) and
			-- once guarded from the start.
			for _, id in Roster.order do
				local c = Roster.get(id)
				for _, key in c.moveOrder do
					local def = c.moves[key]
					if def.chainFrom == nil or def.stance ~= nil then continue end
					local path = { key }
					while c.moves[path[1]].chainFrom do table.insert(path, 1, c.moves[path[1]].chainFrom :: string) end
					local root = c.moves[path[1]]
					if root.stance ~= nil or root.toStance ~= nil then continue end
					for _, blockedRun in { false, true } do
						local d10 = 26
						while d10 <= math.floor((root.range + root.advance) * 10) do
							local m = Sim.newMatch("Training", id, "Goran")
							local a, t = m.fighters[1], m.fighters[2]
							a.pos = Vector3.zero; t.pos = Vector3.new(d10 / 10, 0, 0)
							if blockedRun then Sim.setDummy(m, "Guard") end
							Sim.queueAttack(a, path[1])
							local k, hits = 2, 0
							for _ = 1, 300 do
								if k <= #path and a.move == path[k - 1] and a.moveFrame >= 2 and m.hitstop == 0 then
									Sim.press(m, 1, BUTTON[string.match(c.moves[path[k]].input, "([%a]+)%s*$")])
									k += 1
								end
								for _, e in Sim.step(m) do
									check(m, e, string.format("%s from %.1f%s", table.concat(path, ","), d10 / 10, if blockedRun then " guarded" else ""), blockedRun)
									if e.attacker == 1 and (e.kind == "Hit" or e.kind == "KO") then
										hits += 1
										if hits == 1 then Sim.setDummy(m, "Guard") end
									end
								end
								if k > #path and a.move == nil then break end
							end
							d10 += 4
						end
					end
				end
			end
			-- CPU vs CPU at Hard (strings, juggles, punishes).
			for i, id in Roster.order do
				local m = Sim.newMatch("Match", id, Roster.order[i % #Roster.order + 1])
				m.difficulty = "Hard"
				m.aiSeed = 70 + i
				local guard = 0
				while m.phase ~= "MatchOver" and guard < 30000 do
					guard += 1
					Sim.trainerInput(m, 1); Sim.trainerInput(m, 2)
					for _, e in Sim.step(m) do check(m, e, "Hard CPU", false) end
				end
			end
		end)
		Sim.reach = original
		if not ok then error(err) end
		print(string.format("[REACH] %d strikes, %d stepped in; the furthest connected %.2f studs past its range (%s)", checked, stepped, worst, worstWhat))
		expect.truthy(checked > 500, "strikes checked " .. checked)
		expect.truthy(stepped > 0, "strings on hit step in")
		expect.truthy(Config.StringReach <= 0.3, "the extra reach is at most 0.3 studs")
		expect.truthy(worst <= 0.3 + 1e-6, string.format("no strike connects more than 0.3 studs past its range (%.2f: %s)", worst, worstWhat))
	end)
end
