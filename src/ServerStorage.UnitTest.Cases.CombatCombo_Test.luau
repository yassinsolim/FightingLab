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
			for _, combo in c.combos do
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
					-- Combos deal 30-45% of a 100 HP bar and never more than 45% of the smallest one (90).
					expect.truthy(combo.damage >= 30 and combo.damage <= 40, id .. " " .. combo.name .. string.format(" damage %d in 30-40", combo.damage))
				end
			end
			expect.truthy(#c.combos >= 4, id .. " lists at least four combos")
			expect.truthy(kinds.launch, id .. " has a launch bread-and-butter")
			expect.truthy(kinds.counter or kinds.low, id .. " has a counter-hit or low route")
			expect.truthy(kinds.ultimate, id .. " has a combo ending in the Ultimate")
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
end
