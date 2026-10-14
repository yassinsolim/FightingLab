--!strict
-- Round 7 (combat-balance.md, Round 7): input leniency without sloppiness. The next hit of a combo pressed early (during the
-- previous hit's hitstop or recovery) is kept until the fighter can act; presses made in stun or during a move's
-- startup still expire after Config.AttackBuffer frames. J+K up to 4 frames apart is the 3+4 signature (the first
-- kick is upgraded in place before its active frames) while a typed 3,4 string (5+ frames) stays a string. A press that
-- continues the pending move (its string follow-up, its stance cancel, or a stance follow-up behind a pending stance
-- entry) waits behind it instead of replacing it.
local RS = game:GetService("ReplicatedStorage")
local Lab = RS:WaitForChild("FightingLab")
local Sim = require(Lab:WaitForChild("CombatSim"))
local Roster = require(Lab:WaitForChild("Roster"))
local Config = require(Lab:WaitForChild("CombatConfig"))

type Match = Sim.Match

local function practice(p1: string, p2: string, distance: number?): Match
	local m = Sim.newMatch("Training", p1, p2)
	local a, b = m.fighters[1], m.fighters[2]
	a.pos = Vector3.zero
	b.pos = Vector3.new(distance or 3.0, 0, 0)
	a.facing = Vector3.xAxis
	b.facing = -Vector3.xAxis
	return m
end

local function steps(m: Match, n: number): { Sim.Event }
	local all = {}
	for _ = 1, n do for _, e in Sim.step(m) do table.insert(all, e) end end
	return all
end

-- Steps until fighter 1 starts `key` (or `limit` frames pass); returns the frame count or nil.
local function untilMove(m: Match, key: string, limit: number): number?
	for n = 1, limit do
		Sim.step(m)
		if m.fighters[1].move == key then return n end
	end
	return nil
end

local function hits(events: { Sim.Event }, move: string): number
	local n = 0
	for _, e in events do if e.attacker == 1 and e.kind == "Hit" and e.move == move then n += 1 end end
	return n
end

return function(t)
	local test, expect = t.test, t.expect

	test("a juggle hit pressed early in the launcher's recovery is kept and comes out on the first free frame", function()
		local m = practice("Kael", "Goran")
		local a = m.fighters[1]
		local up = Roster.getMove("Kael", "RisingUppercut")
		m.fighters[1].input.crouch = true
		Sim.setMovement(m, 1, 1, 0)
		expect.equal(Sim.press(m, 1, "RearPunch"), "RisingUppercut")
		Sim.setMovement(m, 1, 0, 0)
		a.input.crouch = false
		-- run to the hit, through the hitstop and a few recovery frames
		local events = steps(m, up.startup + 1)
		expect.truthy(m.fighters[2].state == "Airborne", "launched")
		while m.hitstop > 0 do Sim.step(m) end
		steps(m, 3)
		expect.equal(a.state, "Recovery")
		local left = up.startup + up.active + up.recovery - a.moveFrame
		expect.truthy(left > Config.AttackBuffer, "pressed more than AttackBuffer frames before the end (" .. left .. ")")
		Sim.press(m, 1, "LeadPunch")
		local n = untilMove(m, "Jab", 60)
		assert(n, "the early press is kept")
		expect.equal(n, left + 1, "the jab starts on the first free frame")
		events = steps(m, 20)
		expect.equal(hits(events, "Jab"), 1, "and juggles")
	end)

	test("presses made in stun or during a move's startup still expire (no stale moves)", function()
		-- In hitstun: the jab pressed at the start of a long hitstun is dropped.
		local m = practice("Kael", "Goran")
		Sim.queueAttack(m.fighters[1], "Jab")
		steps(m, Roster.getMove("Kael", "Jab").startup + 1)
		local d = m.fighters[2]
		expect.equal(d.state, "Hitstun")
		Sim.press(m, 2, "LeadPunch")
		steps(m, d.stun + 2)
		expect.equal(d.move, nil, "a press older than the buffer when the stun ends is dropped")
		-- During startup: a button mashed right after a slow move's start does not come out after its recovery.
		m = practice("Kael", "Goran", 8.0)
		local a = m.fighters[1]
		Sim.queueAttack(a, "LegKick")
		Sim.step(m)
		Sim.press(m, 1, "LeadPunch")
		local leg = Roster.getMove("Kael", "LegKick")
		local events = steps(m, leg.startup + leg.active + leg.recovery + 4)
		local started = false
		for _ = 1, 4 do Sim.step(m); if a.move == "Jab" then started = true end end
		expect.falsy(started, "a press during the startup ages like any other")
		expect.truthy(#events >= 0)
		-- Hitstop never ages a press: the buffer limit is counted in frames without hitstop.
		expect.equal(Sim.bufferLimit({ attackKeep = true } :: any), Config.RecoveryBuffer)
		expect.equal(Sim.bufferLimit({ attackKeep = false } :: any), Config.AttackBuffer)
	end)

	test("J and K up to 4 frames apart are the 3+4 signature; the first kick is upgraded before it can hit", function()
		expect.equal(Config.ChordWindow.Kicks, 4)
		for _, id in Roster.order do
			local c = Roster.get(id)
			local sig = c.signature.key
			for gap = 0, Config.ChordWindow.Kicks do
				for _, order in { { "LeadKick", "RearKick" }, { "RearKick", "LeadKick" } } do
					local m = practice(id, "Goran", 2.8)
					local a = m.fighters[1]
					Sim.press(m, 1, order[1])
					local events = steps(m, gap)
					Sim.press(m, 1, order[2])
					for _, e in steps(m, 2) do table.insert(events, e) end
					local isSig = (c.signature.kind == "stance" and a.state == "Stance" and a.stance == sig) or a.move == sig
					expect.truthy(isSig, string.format("%s %s then %s %d frames apart is the signature", id, order[1], order[2], gap))
					for _, e in events do
						expect.falsy(e.attacker == 1 and (e.kind == "Hit" or e.kind == "Block" or e.kind == "Whiff"), id .. " the first kick never reached its active frames")
					end
				end
			end
		end
	end)

	test("a typed 3,4 string (5+ frames apart) stays a string, and 1,2 typed 2+ frames apart is not the Ultimate", function()
		for _, case in { { "Sierra", "Teep", "TeepKick" }, { "Lumi", "SnapKick", "SnapCrescent" } } do
			for gap = Config.ChordWindow.Kicks + 1, 12 do
				local m = practice(case[1], "Goran", 3.0)
				local a = m.fighters[1]
				Sim.press(m, 1, "LeadKick")
				steps(m, gap)
				expect.equal(Sim.press(m, 1, "RearKick"), case[3], string.format("%s 3,4 typed %d frames apart", case[1], gap))
				expect.truthy(a.state ~= "Stance", case[1] .. " no accidental stance")
				expect.equal(untilMove(m, case[3], 40) ~= nil, true, case[1] .. " the string follow-up comes out")
			end
		end
		-- Free Training keeps the player in Surge: 1 then 2 two frames apart is still the One-Two.
		local m = practice("Kael", "Goran", 3.0)
		steps(m, 1)
		expect.truthy(Sim.ultimateReady(m.fighters[1]))
		Sim.press(m, 1, "LeadPunch")
		steps(m, 2)
		expect.equal(Sim.press(m, 1, "RearPunch"), "OneTwo")
	end)

	test("a string typed while its first hit is still buffered comes out whole (follow-up queue)", function()
		-- Kael: in the launcher's recovery press 2 then 1 then 2 (2,1,2) before the Cross has started.
		local m = practice("Kael", "Goran")
		local a = m.fighters[1]
		Sim.queueAttack(a, "RisingUppercut")
		steps(m, 20)
		while m.hitstop > 0 do Sim.step(m) end
		steps(m, 4)
		expect.equal(a.state, "Recovery")
		expect.equal(Sim.press(m, 1, "RearPunch"), "Cross")
		steps(m, 3)
		expect.equal(Sim.press(m, 1, "LeadPunch"), "CrossHook", "1 continues the buffered 2")
		steps(m, 3)
		expect.equal(Sim.press(m, 1, "RearPunch"), "HookOverhand", "2 continues the queued 2,1")
		expect.equal(a.input.attack, "Cross", "the buffered Cross was not replaced")
		local events = steps(m, 120)
		expect.equal(hits(events, "Cross"), 1)
		expect.equal(hits(events, "CrossHook"), 1)
		expect.equal(hits(events, "HookOverhand"), 1)
		-- An unrelated press still replaces the buffered move (as before) and clears the queue.
		m = practice("Kael", "Goran", 8.0)
		a = m.fighters[1]
		Sim.queueAttack(a, "LegKick")
		steps(m, Roster.getMove("Kael", "LegKick").startup + 3)
		Sim.press(m, 1, "RearPunch")
		Sim.press(m, 1, "LeadKick")
		expect.equal(a.input.attack, "FrontKick", "a press that does not continue the buffered move replaces it")
		expect.equal((a.input :: any).queue, nil)
	end)

	test("3+4 and stance follow-ups pressed before their move has started wait behind it", function()
		-- Sierra: 3 (Teep, cancelable) buffered in a recovery, then 3+4 and SPW+3 before the Teep starts.
		local m = practice("Sierra", "Goran", 3.0)
		local a = m.fighters[1]
		Sim.queueAttack(a, "SwitchKick")
		steps(m, 20)
		while m.hitstop > 0 do Sim.step(m) end
		expect.equal(Sim.press(m, 1, "LeadKick"), "Teep")
		steps(m, 2)
		Sim.press(m, 1, "LeadKick")
		local key = Sim.press(m, 1, "RearKick")
		expect.equal(key, "Southpaw", "3+4 behind the buffered Teep is its stance cancel")
		expect.equal(a.input.attack, "Teep", "the Teep stays buffered")
		steps(m, 2)
		expect.equal(Sim.press(m, 1, "LeadKick"), "SouthpawBodyKick", "3 behind the pending Southpaw is SPW+3")
		local sawTeep, sawStance, sawKick = false, false, false
		for _ = 1, 120 do
			Sim.step(m)
			if a.move == "Teep" then sawTeep = true end
			if a.state == "Stance" and a.stance == "Southpaw" then sawStance = true end
			if a.move == "SouthpawBodyKick" then sawKick = true end
		end
		expect.truthy(sawTeep and sawStance and sawKick, "Teep, then Southpaw, then the body kick")
		-- The queue is dropped when the fighter is hit.
		m = practice("Kael", "Goran", 3.0)
		a = m.fighters[1]
		Sim.queueAttack(a, "OneTwo")
		a.move = "Jab"; a.moveFrame = 20; a.state = "Recovery"
		a.input.attack = "Cross"; a.input.attackAge = 0
		Sim.press(m, 1, "LeadPunch")
		expect.truthy((a.input :: any).queue ~= nil, "queued behind the buffered Cross")
		a.input.attack = nil; a.chainMove = nil; a.move = nil; a.state = "Hitstun"; a.stun = 10
		Sim.step(m)
		expect.equal((a.input :: any).queue, nil, "a hit leaves nothing to follow")
	end)

	test("juggle follow-ups turn toward the body in the air", function()
		local m = practice("Kael", "Goran", 3.0)
		local a, d = m.fighters[1], m.fighters[2]
		-- The juggled body drifted well off line (45 degrees). A string follow-up starts from the chain, without the
		-- re-facing a move from neutral gets; the narrow One-Two (track 1.5 per frame) only reaches it because a
		-- follow-up against a body in the air faces it.
		d.state = "Airborne"; d.pos = Vector3.new(2.0, 1.6, 2.0); d.velocityY = 4; d.chain = 2; d.airHits = 1
		a.facing = Vector3.xAxis
		local jab = Roster.getMove("Kael", "Jab")
		a.move = "Jab"; a.moveName = jab.name; a.moveFrame = jab.startup + jab.active; a.state = "Active"; a.hasHit = true
		a.chainMove = "OneTwo"
		local events = steps(m, Roster.getMove("Kael", "OneTwo").startup + 3)
		expect.equal(hits(events, "OneTwo"), 1, "the string follow-up tracks the juggled body")
	end)
end
