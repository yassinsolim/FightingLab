--!strict
-- Round 7 CPU (CombatAI): Hard's hit-confirmed strings are real combos. Round 6's Hard confirmed a string hit after its
-- reaction delay and pressed the follow-up after the last frame that still combos, so 95% of its follow-up hits were
-- gaps (Nia's d+3,4 launcher got blocked and launch-punished). Now a confirm that cannot be in time is decided before
-- that frame instead (combat-balance.md, Round 7). Deterministic seeds; a dummy that never guards.
local Lab = game:GetService("ReplicatedStorage"):WaitForChild("FightingLab")
local Sim = require(Lab:WaitForChild("CombatSim"))
local Roster = require(Lab:WaitForChild("Roster"))

-- Hard CPU (P1) against a standing dummy that never guards: string follow-up hits and how many of them combo.
-- Delayable follow-ups (Nia's whirl) are left out: delaying them is a deliberate mix-up, not a combo.
local function followUps(id: string, level: string, seed: number): (number, number)
	local m = Sim.newMatch("Match", id, if id == "Kael" then "Sierra" else "Kael")
	m.difficulty = level :: any
	m.aiSeed = seed
	local f, o = m.fighters[1], m.fighters[2]
	o.dummy = "Stand"
	local prev: string? = nil
	local pending: { [string]: boolean } = {}
	local hits, combos = 0, 0
	for _ = 1, 3600 do
		if m.phase == "MatchOver" then break end
		Sim.trainerInput(m, 1)
		for _, e in Sim.step(m) do
			if e.attacker == 1 and (e.kind == "Hit" or e.kind == "KO") and pending[e.move] then
				pending[e.move] = nil
				hits += 1
				if e.combo >= 2 then combos += 1 end
			end
		end
		if f.move ~= prev then
			local def = if f.move then f.character.moves[f.move] else nil
			if def and prev and def.chainFrom == prev and def.delay == nil then
				pending[f.move :: string] = true
			end
			prev = f.move
		end
		o.health = math.max(o.health, 30)
	end
	return hits, combos
end

return function(t)
	local test, expect = t.test, t.expect

	test("Hard's hit-confirmed string follow-ups land as combos", function()
		local allHits, allCombos = 0, 0
		for _, id in Roster.order do
			local hits, combos = 0, 0
			for seed = 71, 72 do
				local h, c = followUps(id, "Hard", seed)
				hits += h; combos += c
			end
			expect.truthy(hits >= 8, id .. " plays strings on hit (" .. hits .. " follow-up hits)")
			expect.truthy(combos >= hits * 0.9, string.format("%s follow-ups combo (%d of %d)", id, combos, hits))
			allHits += hits; allCombos += combos
		end
		expect.truthy(allCombos >= allHits * 0.95, string.format("Hard follow-ups combo overall (%d of %d)", allCombos, allHits))
	end)
end
