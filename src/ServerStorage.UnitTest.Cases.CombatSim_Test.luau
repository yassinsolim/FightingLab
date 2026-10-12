--!strict
-- OV6 combat rules: grounded footwork, discrete sidesteps, automatic guard, chords/throw breaks, knockdowns, rounds.
local RS = game:GetService("ReplicatedStorage")
local Sim = require(RS.FightingLab.CombatSim)
local Config = require(RS.FightingLab.CombatConfig)
local Roster = require(RS.FightingLab.Roster)

type Match = Sim.Match
type Event = Sim.Event

local function place(match: Match, a: Vector3, b: Vector3)
	local l, t = match.fighters[1], match.fighters[2]
	l.pos, t.pos = a, b
	l.facing = (b - a).Unit
	t.facing = (a - b).Unit
end

local function run(match: Match, frames: number): { Event }
	local all: { Event } = {}
	for _ = 1, frames do
		for _, e in Sim.step(match) do table.insert(all, e) end
		-- Most tests assert combat outcomes, not presentation freeze frames; drain authoritative hitstop here.
		while match.hitstop > 0 do Sim.step(match) end
	end
	return all
end

local function count(events: { Event }, kind: string): number
	local n = 0
	for _, e in events do if e.kind == kind then n += 1 end end
	return n
end

local function first(events: { Event }, kind: string): Event?
	for _, e in events do if e.kind == kind then return e end end
	return nil
end

local function forceActive(f: Sim.Fighter, moveKey: string, frame: number)
	local def = f.character.moves[moveKey] or Config.Moves[moveKey]
	f.move = moveKey
	f.moveName = def.name
	f.state = "Active"
	f.moveFrame = frame
	f.hasHit = false
	f.crouched = def.crouching
end

local function flatDist(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Training match where both fighters follow the normal guard rules (no practice-dummy behaviour).
local function duel(p1: string?, p2: string?): Match
	local m = Sim.newMatch("Training", p1, p2)
	m.fighters[2].dummy = nil
	return m
end

return function(t)
	local test, expect = t.test, t.expect

	test("lethal hit resolves training KO and the KO'd fighter cannot act", function()
		local m = Sim.newMatch(); place(m, Vector3.zero, Vector3.new(3, 0, 0))
		local target = m.fighters[2]; target.health = 1
		Sim.queueAttack(m.fighters[1], "Jab")
		local events = run(m, Config.Moves.Jab.startup + 1)
		expect.equal(target.health, 0); expect.equal(target.state, "KO")
		expect.equal(count(events, "KO"), 1); expect.equal(m.koFrame, Config.Moves.Jab.startup + 1)
		run(m, 30); Sim.queueAttack(target, "Jab")
		Sim.setMovement(m, 2, 1, 0); Sim.setMovement(m, 2, 0, 0); Sim.setMovement(m, 2, 1, 0)
		expect.equal(count(run(m, 30), "Hit"), 0); expect.equal(m.fighters[1].health, m.fighters[1].maxHealth)
		expect.equal(target.state, "KO"); expect.equal(target.health, 0); expect.equal(target.dash, 0)
	end)

	test("blocked hits deal no chip damage and never KO", function()
		local m = Sim.newMatch(); place(m, Vector3.zero, Vector3.new(3, 0, 0))
		local target = m.fighters[2]; target.health = 1; target.input.block = true
		Sim.queueAttack(m.fighters[1], "Heavy")
		local events = run(m, Config.Moves.Heavy.startup + 1)
		expect.equal(count(events, "Block"), 1)
		expect.equal(first(events, "Block") and (first(events, "Block") :: Event).damage, 0)
		expect.equal(target.health, 1); expect.equal(target.state, "Blockstun")
		expect.equal(target.stun, Config.Moves.Heavy.blockStun)
	end)

	test("KO awards the round and the deciding win", function()
		local m = Sim.newMatch("Match")
		for round = 1, 2 do
			run(m, Config.ReadyFrames); place(m, Vector3.zero, Vector3.new(3, 0, 0))
			m.fighters[2].health = 1; m.fighters[2].dummy = "Stand"
			Sim.queueAttack(m.fighters[1], "Jab"); local events = run(m, Config.Moves.Jab.startup + 1)
			expect.equal(count(events, "KO"), 1); expect.equal(m.winner, 1); expect.equal(m.reason, "KO")
			expect.equal(m.scores[1], round); expect.equal(m.scores[2], 0)
			expect.equal(m.phase, if round == 1 then "RoundOver" else "MatchOver")
			Sim.queueAttack(m.fighters[2], "Jab"); expect.equal(#run(m, 30), 0)
			expect.equal(m.fighters[1].health, m.fighters[1].maxHealth); expect.equal(m.scores[1], round)
			if round == 1 then run(m, Config.RoundBreakFrames - 30) end
		end
	end)

	test("zero health cannot attack or dash after recovery", function()
		local m = Sim.newMatch(); place(m, Vector3.zero, Vector3.new(3, 0, 0))
		local f = m.fighters[2]; f.health = 0
		expect.truthy(Sim.isLocked(f)); Sim.queueAttack(f, "Jab")
		Sim.setMovement(m, 2, 1, 0); Sim.setMovement(m, 2, 0, 0); Sim.setMovement(m, 2, 1, 0)
		expect.equal(f.dash, 0); expect.equal(#run(m, 30), 0)
		expect.equal(f.state, "KO"); expect.equal(m.fighters[1].health, m.fighters[1].maxHealth)
	end)

	test("blocked move advantage matches roster-derived frame data", function()
		for _, name in Config.MoveOrder do
			local m = Sim.newMatch(); local v = Config.Moves[name]
			if v.height ~= "Throw" then
				place(m, Vector3.zero, Vector3.new(3, 0, 0))
				m.fighters[2].input.block = true; m.fighters[2].input.crouch = v.height == "Low"
				Sim.queueAttack(m.fighters[1], name); local events = run(m, v.startup + 1)
				expect.equal(count(events, "Block"), 1, name)
				expect.equal(events[1].advantage, v.onBlock, name)
				expect.equal(v.blockStun, v.onBlock + v.active + v.recovery - 1, name)
			end
		end
	end)

	test("buttons and directions select Kael roster moves", function()
		local f = Sim.newMatch().fighters[1]
		local standing = { LeadPunch = "Jab", RearPunch = "Cross", LeadKick = "FrontKick", RearKick = "Roundhouse", Throw = "Throw", Throw2 = "ThrowB" }
		for _, button in Config.Buttons do expect.equal(Sim.selectMove(f, button), standing[button], button) end
		f.input.crouch = true
		local crouching = { LeadPunch = "Jab", RearPunch = "BodyBlow", LeadKick = "ShinKick", RearKick = "LegKick", Throw = "Throw", Throw2 = "ThrowB" }
		for _, button in Config.Buttons do expect.equal(Sim.selectMove(f, button), crouching[button], "d+" .. button) end
		f.input.moveX = 1
		expect.equal(Sim.selectMove(f, "RearPunch"), "RisingUppercut")
		f.input.crouch = false
		expect.equal(Sim.selectMove(f, "RearPunch"), "Overhand")
		f.input.moveX = -1
		expect.equal(Sim.selectMove(f, "RearPunch"), "WeaveHook")
	end)

	test("high avoidance and mid versus crouch", function()
		for _, name in { "Jab", "LeadKick" } do
			local m = Sim.newMatch(); place(m, Vector3.zero, Vector3.new(3, 0, 0)); m.fighters[2].input.crouch = true
			Sim.queueAttack(m.fighters[1], name); local events = run(m, Sim.totalFrames(name))
			expect.equal(count(events, "Hit"), if name == "Jab" then 0 else 1, name)
			expect.equal(count(events, "Whiff"), if name == "Jab" then 1 else 0, name)
		end
	end)

	-- Stand guard blocks high/mid but not low; crouch guard blocks low but not mid.
	test("height guard matrix", function()
		for _, crouch in { false, true } do for _, name in { "Jab", "LeadKick", "ShinTap" } do
			local m = Sim.newMatch(); place(m, Vector3.zero, Vector3.new(3, 0, 0)); local target = m.fighters[2]
			target.input.block = true; target.input.crouch = crouch; Sim.queueAttack(m.fighters[1], name)
			local events = run(m, Config.Moves[name].startup + 1)
			local height = Config.Moves[name].height
			local block = (crouch and height == "Low") or (not crouch and height ~= "Low")
			local hit = (crouch and height == "Mid") or (not crouch and height == "Low")
			expect.equal(count(events, "Block"), if block then 1 else 0)
			expect.equal(count(events, "Hit"), if hit then 1 else 0)
		end end
	end)

	test("standing still or holding back guards automatically, walking forward does not", function()
		local function trial(setup: (Match) -> (), move: string): (number, number)
			local m = duel("Kael", "Sierra"); place(m, Vector3.zero, Vector3.new(3, 0, 0))
			setup(m)
			Sim.queueAttack(m.fighters[1], move)
			local events = run(m, Config.Moves[move].startup + 1)
			return count(events, "Block"), count(events, "Hit")
		end
		local b, h = trial(function(_) end, "Jab"); expect.equal(b, 1, "idle blocks high"); expect.equal(h, 0)
		b, h = trial(function(_) end, "LeadKick"); expect.equal(b, 1, "idle blocks mid")
		b, h = trial(function(m) Sim.setMovement(m, 2, -1, 0) end, "LeadKick"); expect.equal(b, 1, "back blocks mid")
		b, h = trial(function(m) Sim.setMovement(m, 2, 1, 0); run(m, 1) end, "Jab"); expect.equal(h, 1, "walking forward is hit")
		b, h = trial(function(_) end, "ShinTap"); expect.equal(h, 1, "standing guard loses to lows")
		b, h = trial(function(m) m.fighters[2].input.crouch = true end, "ShinTap"); expect.equal(b, 1, "holding down blocks lows")
		b, h = trial(function(m) m.fighters[2].input.crouch = true end, "LeadKick"); expect.equal(h, 1, "crouching loses to mids")
		local m = duel(); local f = m.fighters[2]
		run(m, 1); expect.equal(f.guard, "Stand")
		Sim.setMovement(m, 2, 1, 0); run(m, 1); expect.equal(f.guard, nil); expect.equal(f.state, "Walk")
		Sim.setMovement(m, 2, 0, 0); f.input.crouch = true; run(m, 1); expect.equal(f.guard, "Crouch"); expect.equal(f.state, "Crouch")
	end)

	test("attacking, dashing and sidestepping fighters do not guard", function()
		-- dashing forward into a kick
		local m = duel("Kael", "Kael"); place(m, Vector3.zero, Vector3.new(5.5, 0, 0))
		Sim.queueAttack(m.fighters[1], "FrontKick")
		run(m, 4)
		Sim.setMovement(m, 2, 1, 0); Sim.setMovement(m, 2, 0, 0); Sim.setMovement(m, 2, 1, 0); Sim.setMovement(m, 2, 0, 0)
		local sawDash = false
		local events = {}
		for _ = 1, Config.Moves.LeadKick.startup do
			for _, e in run(m, 1) do table.insert(events, e) end
			if m.fighters[2].state == "Dash" then sawDash = true; expect.equal(m.fighters[2].guard, nil) end
		end
		expect.truthy(sawDash, "defender dashed")
		expect.equal(count(events, "Block"), 0, "a dashing fighter cannot block")
		expect.equal(count(events, "Hit"), 1)
		-- starting an attack (counter hit)
		m = duel("Kael", "Kael"); place(m, Vector3.zero, Vector3.new(3, 0, 0))
		Sim.queueAttack(m.fighters[2], "RisingUppercut"); run(m, 2)
		Sim.queueAttack(m.fighters[1], "Jab")
		local hit = first(run(m, Config.Moves.Jab.startup + 1), "Hit")
		expect.truthy(hit ~= nil and hit.counter == true, "attack startup is counter-hit")
		-- sidestepping (a homing hook catches it)
		m = duel("Kael", "Sierra"); place(m, Vector3.zero, Vector3.new(3.2, 0, 0))
		Sim.setMovement(m, 2, 0, 1); Sim.setMovement(m, 2, 0, 0); run(m, 2)
		expect.equal(m.fighters[2].state, "Sidestep"); expect.equal(m.fighters[2].guard, nil)
		Sim.queueAttack(m.fighters[1], "WeaveHook")
		events = run(m, Roster.getMove("Kael", "WeaveHook").startup + 2)
		expect.equal(count(events, "Hit"), 1, "homing hook hits a sidestep")
	end)

	test("special mids are blocked standing and crouching", function()
		for _, crouch in { false, true } do
			local m = Sim.newMatch("Training", "Sierra", "Kael"); place(m, Vector3.zero, Vector3.new(3, 0, 0))
			m.fighters[2].input.block = true; m.fighters[2].input.crouch = crouch
			Sim.queueAttack(m.fighters[1], "DuckJab")
			expect.equal(count(run(m, Roster.getMove("Sierra", "DuckJab").startup + 1), "Block"), 1)
		end
		local m = Sim.newMatch("Training", "Sierra", "Kael"); place(m, Vector3.zero, Vector3.new(3, 0, 0))
		Sim.queueAttack(m.fighters[1], "DuckJab")
		expect.equal(count(run(m, Roster.getMove("Sierra", "DuckJab").startup + 1), "Hit"), 1, "no guard = hit")
	end)

	test("dash and backdash are committed eased movements of the roster distance", function()
		for _, id in Roster.order do
			local s = Roster.get(id).stats
			for _, direction in { 1, -1 } do
				local m = Sim.newMatch("Training", id, "Kael"); place(m, Vector3.new(-6, 0, 0), Vector3.new(12, 0, 0))
				local f = m.fighters[1]; local p = f.pos
				Sim.setMovement(m, 1, direction, 0); Sim.setMovement(m, 1, 0, 0); run(m, 2); Sim.setMovement(m, 1, direction, 0); Sim.setMovement(m, 1, 0, 0)
				run(m, 1)
				expect.equal(f.state, if direction < 0 then "Backdash" else "Dash", id)
				expect.equal(f.guard, nil, "no guard while dashing")
				local frames = 1
				while (f.state == "Dash" or f.state == "Backdash") and frames < 60 do run(m, 1); frames += 1 end
				expect.equal(frames, if direction < 0 then s.backdashFrames else s.dashFrames, id .. " frames")
				expect.near(flatDist(f.pos, p), if direction < 0 then s.backdashDistance else s.dashDistance, 0.01, id .. " distance")
				expect.near(f.pos.Z, 0, 0.001)
			end
		end
	end)

	test("backdashes chain while a forward dash cannot be cancelled into guard", function()
		local m = Sim.newMatch("Training", "Kael", "Sierra"); place(m, Vector3.zero, Vector3.new(10, 0, 0))
		local f = m.fighters[1]
		local function tapBack() Sim.setMovement(m, 1, -1, 0); Sim.setMovement(m, 1, 0, 0); Sim.setMovement(m, 1, -1, 0); Sim.setMovement(m, 1, 0, 0) end
		tapBack(); run(m, Config.BackdashChainFrame)
		expect.equal(f.state, "Backdash")
		local before = f.dashFrame
		tapBack(); run(m, 1)
		expect.equal(f.state, "Backdash"); expect.truthy(f.dashFrame < before, "a new backdash started")
		-- 4 chained backdashes travel far but slower than chained forward dashes (a runner can be caught)
		local p = f.pos
		for _ = 1, 4 do tapBack(); run(m, Config.BackdashChainFrame) end
		local speed = flatDist(f.pos, p) / (4 * Config.BackdashChainFrame) * Config.FPS
		local s = f.character.stats
		local forwardChain = s.dashDistance * (1 - (1 - Config.DashChainFrame / s.dashFrames) ^ 2) / Config.DashChainFrame * Config.FPS
		expect.truthy(speed < 12.5, "chained backdash speed " .. speed)
		expect.truthy(forwardChain > speed, "chained forward dashes are faster: " .. forwardChain)
	end)

	test("dash tap window inclusive boundary", function()
		local m = Sim.newMatch(); place(m, Vector3.zero, Vector3.new(10, 0, 0))
		Sim.setMovement(m, 1, -1, 0); Sim.setMovement(m, 1, 0, 0)
		run(m, Config.DashTapWindow); Sim.setMovement(m, 1, -1, 0); run(m, 1)
		expect.equal(m.fighters[1].state, "Backdash")
		m = Sim.newMatch(); place(m, Vector3.zero, Vector3.new(10, 0, 0))
		Sim.setMovement(m, 1, -1, 0); Sim.setMovement(m, 1, 0, 0)
		run(m, Config.DashTapWindow + 1); Sim.setMovement(m, 1, -1, 0); run(m, 1)
		expect.equal(m.fighters[1].state, "Backwalk", "late second tap is walking")
	end)

	test("dash respects crouch and move recovery", function()
		local m = Sim.newMatch(); m.fighters[1].input.crouch = true
		Sim.setMovement(m, 1, -1, 0); Sim.setMovement(m, 1, 0, 0); Sim.setMovement(m, 1, -1, 0); run(m, 1)
		expect.equal(m.fighters[1].dash, 0); expect.equal(m.fighters[1].state, "Crouch")
		m = Sim.newMatch(); Sim.queueAttack(m.fighters[1], "Heavy"); run(m, 2)
		Sim.setMovement(m, 1, -1, 0); Sim.setMovement(m, 1, 0, 0); Sim.setMovement(m, 1, -1, 0)
		run(m, 2); expect.equal(m.fighters[1].move, "Heavy")
		run(m, Sim.totalFrames("Heavy")); expect.truthy(m.fighters[1].state ~= "Backdash", "stale dash request expired")
	end)

	test("holding W makes exactly one sidestep and never orbits", function()
		local m = duel("Kael", "Sierra")
		local f, o = m.fighters[1], m.fighters[2]
		local start = f.pos
		local r0 = flatDist(f.pos, o.pos)
		Sim.setMovement(m, 1, 0, 1)
		local steps, last, travelled = 0, "Idle", 0
		local prev = f.pos
		for _ = 1, 120 do
			run(m, 1)
			if f.state == "Sidestep" and last ~= "Sidestep" then steps += 1 end
			last = f.state
			travelled += flatDist(f.pos, prev); prev = f.pos
		end
		expect.equal(steps, 1, "one sidestep per tap")
		expect.near(travelled, f.character.stats.sidestepArc, 0.03, "arc length")
		expect.near(flatDist(f.pos, o.pos), r0, 0.03, "distance kept")
		expect.equal(f.state, "Idle")
		expect.truthy(f.pos.Z < start.Z - 1, "stepped into the screen (toward -Z for the left fighter)")
		-- S-side step goes the other way
		Sim.setMovement(m, 1, 0, 0); Sim.setMovement(m, 1, 0, -1); Sim.setMovement(m, 1, 0, 0)
		local z = f.pos.Z
		run(m, Config.SidestepFrames + Config.SidestepRecovery)
		expect.truthy(f.pos.Z > z + 1, "stepped toward the camera")
	end)

	test("sidestep is a 16 frame arc plus a short recovery facing the opponent", function()
		local m = duel("Kael", "Sierra")
		local f, o = m.fighters[1], m.fighters[2]
		Sim.setMovement(m, 1, 0, -1); Sim.setMovement(m, 1, 0, 0)
		local r0 = flatDist(f.pos, o.pos)
		for frame = 1, Config.SidestepFrames + Config.SidestepRecovery do
			run(m, 1)
			if frame < Config.SidestepFrames + Config.SidestepRecovery then
				expect.equal(f.state, "Sidestep"); expect.equal(f.stepFrame, frame); expect.equal(f.stepDir, -1)
			end
			expect.near(flatDist(f.pos, o.pos), r0, 0.02, "constant distance")
			local toward = (o.pos - f.pos); toward = Vector3.new(toward.X, 0, toward.Z).Unit
			expect.truthy(f.facing:Dot(toward) > 0.999, "faces the opponent")
		end
		expect.equal(f.state, "Idle")
	end)

	test("a sidestep makes a slow linear move whiff while a homing move connects", function()
		local m = duel("Sierra", "Kael"); place(m, Vector3.zero, Vector3.new(3.2, 0, 0))
		Sim.queueAttack(m.fighters[1], "SpinningBackKick")
		Sim.setMovement(m, 2, 0, 1); Sim.setMovement(m, 2, 0, 0)
		local events = run(m, Sim.totalFramesFor(m.fighters[1], "SpinningBackKick"))
		expect.equal(count(events, "Hit") + count(events, "Block"), 0, "linear kick misses the step")
		local whiff = first(events, "Whiff")
		expect.truthy(whiff ~= nil and whiff.evaded == true, "whiff flagged as evaded")
		m = duel("Kael", "Sierra"); place(m, Vector3.zero, Vector3.new(3.2, 0, 0))
		Sim.queueAttack(m.fighters[1], "WeaveHook")
		Sim.setMovement(m, 2, 0, 1); Sim.setMovement(m, 2, 0, 0)
		events = run(m, Sim.totalFramesFor(m.fighters[1], "WeaveHook"))
		expect.equal(count(events, "Hit"), 1, "homing hook catches the step")
		-- a fast jab started at the same time is not sidestepped
		m = duel("Kael", "Sierra"); place(m, Vector3.zero, Vector3.new(3.2, 0, 0))
		Sim.queueAttack(m.fighters[1], "Jab")
		Sim.setMovement(m, 2, 0, 1); Sim.setMovement(m, 2, 0, 0)
		expect.equal(count(run(m, 20), "Hit"), 1, "jab is too fast to step on reaction")
	end)

	test("walk speeds match roster stats and crouch is stationary", function()
		for _, id in Roster.order do
			local s = Roster.get(id).stats
			local m = Sim.newMatch("Training", id, "Kael"); place(m, Vector3.new(-8, 0, 0), Vector3.new(12, 0, 0))
			local f = m.fighters[1]; local p = f.pos
			Sim.setMovement(m, 1, 1, 0); run(m, 60)
			expect.near(flatDist(f.pos, p), s.walkSpeed, 0.02, id .. " forward")
			p = f.pos
			Sim.setMovement(m, 1, 0, 0); run(m, 20); Sim.setMovement(m, 1, -1, 0); run(m, 60)
			expect.near(flatDist(f.pos, p), s.backSpeed, 0.02, id .. " back")
			expect.truthy(s.walkSpeed >= 4.25 and s.walkSpeed <= 5.75 and s.backSpeed >= 3.4 and s.backSpeed <= 4.6, id .. " within contract")
			p = f.pos
			Sim.setMovement(m, 1, 1, 0); f.input.crouch = true; run(m, 30)
			expect.near(flatDist(f.pos, p), 0, 0.001, id .. " crouch is stationary"); expect.equal(f.state, "Crouch")
		end
	end)

	test("launcher creates airborne state, lands on the floor and gets up", function()
		local m = Sim.newMatch(); place(m, Vector3.zero, Vector3.new(3, 0, 0)); Sim.queueAttack(m.fighters[1], "Rise")
		local events = run(m, Config.Moves.Rise.startup + 1)
		expect.equal(count(events, "Hit"), 1)
		local t2 = m.fighters[2]
		expect.equal(t2.state, "Airborne"); expect.equal(t2.airHits, 0)
		local guard = 0
		while t2.state == "Airborne" and guard < 200 do run(m, 1); guard += 1 end
		expect.equal(t2.state, "Landing"); expect.equal(t2.pos.Y, 0)
		run(m, Config.LandingFrames); expect.equal(t2.state, "Getup"); expect.equal(t2.getupKind, "Stand")
		run(m, Config.GetupFrames); expect.equal(t2.state, "Idle")
		expect.equal(m.fighters[1].combo, 0); expect.equal(t2.knockdown, nil)
	end)

	test("juggle hits scale damage and force knockdown cap", function()
		local m = Sim.newMatch(); place(m, Vector3.zero, Vector3.new(3, 0, 0)); local target = m.fighters[2]
		target.state = "Airborne"; target.pos = Vector3.new(3, 2.4, 0); target.velocityY = 0; target.chain = 1
		local health = target.health
		local damages: { number } = {}
		for i = 1, Config.MaxAirHits do
			forceActive(m.fighters[1], "Jab", Config.Moves.Jab.startup + 1); local events = run(m, 1)
			if events[1] then table.insert(damages, events[1].damage) end
			if i < Config.MaxAirHits then target.state = "Airborne"; target.pos = Vector3.new(3, 2.4, 0); target.velocityY = 0 end
		end
		expect.truthy(#damages >= 3)
		expect.truthy(damages[1] >= damages[#damages])
		expect.truthy(target.health > health - Config.Moves.Jab.damage * Config.MaxAirHits)
		expect.truthy(target.knockdown ~= nil, "the last air hit knocks down")
		expect.equal(target.state, "Airborne", "a body hit high in the air falls into the knockdown instead of snapping down")
		expect.truthy(target.airLocked, "no more hits connect while it falls")
		local lastY = target.pos.Y
		for _ = 1, 40 do
			run(m, 1)
			expect.truthy(lastY - target.pos.Y <= 1.0, "no snap to the floor")
			lastY = target.pos.Y
			if target.state ~= "Airborne" then break end
		end
		expect.equal(target.state, "Landing")
		expect.equal(target.pos.Y, 0)
	end)

	test("air time is capped and landing and getup cannot be hit", function()
		local m = Sim.newMatch(); place(m, Vector3.zero, Vector3.new(3, 0, 0)); local t2 = m.fighters[2]
		t2.state = "Airborne"; t2.pos = Vector3.new(3, 1, 0); t2.velocityY = 0; t2.airFrames = Config.MaxAirFrames - 1; t2.chain = 3
		run(m, 1); expect.truthy(t2.airLocked, "air time is up: no more juggle hits"); expect.truthy(t2.velocityY < 0)
		Sim.queueAttack(m.fighters[1], "Jab"); run(m, Config.Moves.Jab.startup + 1); expect.equal(t2.health, t2.maxHealth, "a falling body cannot be hit")
		expect.equal(t2.state, "Landing"); expect.equal(t2.chain, 0); expect.equal(t2.pos.Y, 0)
		Sim.queueAttack(m.fighters[1], "Jab"); run(m, Config.Moves.Jab.startup + 1)
		expect.equal(t2.state, "Landing"); expect.equal(t2.health, t2.maxHealth, "landing is invulnerable")
		local guard = 0
		while t2.state ~= "Getup" and guard < 40 do run(m, 1); guard += 1 end
		expect.equal(t2.state, "Getup")
		Sim.queueAttack(m.fighters[1], "ShinTap"); run(m, Config.Moves.ShinTap.startup + 1); expect.equal(t2.health, t2.maxHealth, "getup is invulnerable")
		run(m, Config.GetupFrames); expect.equal(t2.state, "Idle")
	end)

	test("exhausted juggle cannot relaunch", function()
		local m = Sim.newMatch(); place(m, Vector3.zero, Vector3.new(3, 0, 0)); local target = m.fighters[2]
		target.state = "Airborne"; target.pos = Vector3.new(3, 3.5, 0); target.velocityY = -1; target.chain = 3; target.extensions = Config.MaxJuggleExtensions
		Sim.queueAttack(m.fighters[1], "Jab"); local events = run(m, Config.Moves.Jab.startup + 1)
		expect.equal(count(events, "Hit"), 1); expect.equal(target.extensions, Config.MaxJuggleExtensions); expect.truthy(target.velocityY < 0)
	end)

	test("a KO in the air falls to the floor even after the round ends", function()
		local m = Sim.newMatch("Match"); run(m, Config.ReadyFrames); place(m, Vector3.zero, Vector3.new(3, 0, 0))
		local target = m.fighters[2]
		target.state = "Airborne"; target.pos = Vector3.new(3, 3, 0); target.velocityY = 4; target.health = 1; target.chain = 1
		forceActive(m.fighters[1], "Jab", Config.Moves.Jab.startup + 1)
		run(m, 1)
		expect.equal(target.state, "KO"); expect.truthy(target.pos.Y > 0, "still in the air at the KO")
		expect.equal(m.phase, "RoundOver")
		local lowest = target.pos.Y
		for _ = 1, 90 do run(m, 1); lowest = math.min(lowest, target.pos.Y); expect.truthy(target.pos.Y >= 0) end
		expect.equal(target.pos.Y, 0, "body rests on the floor"); expect.equal(target.velocityY, 0)
	end)

	test("getup options roll back or sideways and stay invulnerable", function()
		local function knockDown(): Match
			local m = Sim.newMatch("Training", "Kael", "Sierra"); place(m, Vector3.zero, Vector3.new(3, 0, 0))
			Sim.queueAttack(m.fighters[1], "LegKick")
			run(m, Roster.getMove("Kael", "LegKick").startup + 1)
			expect.equal(m.fighters[2].state, "Landing")
			return m
		end
		local m = knockDown(); local d = m.fighters[2]
		Sim.setMovement(m, 2, -1, 0)
		local start = d.pos
		run(m, Config.LandingFrames)
		expect.equal(d.state, "Getup"); expect.equal(d.getupKind, "BackRoll")
		run(m, Config.RollFrames)
		expect.near(flatDist(d.pos, start), Config.RollDistance, 0.05, "back roll distance")
		run(m, Config.GetupFrames); expect.equal(d.state, "Idle"); expect.equal(d.guard, "Stand", "first free frame guards")
		m = knockDown(); d = m.fighters[2]
		run(m, Config.GetupChoiceFrame)
		Sim.setMovement(m, 2, 0, 1); Sim.setMovement(m, 2, 0, 0)
		run(m, Config.LandingFrames - Config.GetupChoiceFrame)
		expect.equal(d.getupKind, "SideRoll"); expect.equal(d.rollDir, 1)
		local hp = d.health
		Sim.queueAttack(m.fighters[1], "WeaveHook"); run(m, 25)
		expect.equal(d.health, hp, "rolling getup is invulnerable")
	end)

	test("1+3 and 2+4 chords throw and only the matching punch breaks", function()
		local function setup(): Match
			local m = Sim.newMatch("Training", "Kael", "Sierra"); place(m, Vector3.zero, Vector3.new(2.6, 0, 0))
			return m
		end
		local m = setup()
		Sim.press(m, 1, "LeadPunch"); run(m, 1); expect.equal(m.fighters[1].move, "Jab")
		Sim.press(m, 1, "LeadKick")
		expect.equal(m.fighters[1].move, "Throw", "the jab is upgraded into the throw")
		local events = run(m, 12)
		expect.equal(count(events, "ThrowStart"), 1)
		Sim.press(m, 2, "RearPunch")
		events = run(m, 60)
		expect.equal(count(events, "ThrowBreak"), 0, "wrong button does not break 1+3")
		expect.equal(count(events, "ThrowHit"), 1)
		m = setup()
		Sim.press(m, 1, "RearPunch"); Sim.press(m, 1, "RearKick")
		run(m, 12)
		Sim.press(m, 2, "RearPunch")
		expect.equal(count(run(m, 2), "ThrowBreak"), 1, "2 breaks 2+4")
		m = setup()
		expect.equal(Sim.press(m, 1, "Throw"), "Throw", "throw button = 1+3")
		m.fighters[2].input.crouch = true
		events = run(m, Sim.totalFramesFor(m.fighters[1], "Throw") + 2)
		expect.equal(count(events, "ThrowStart"), 0, "crouching ducks throws"); expect.equal(count(events, "Whiff"), 1)
	end)

	test("string follow-ups chain inside the window only", function()
		local m = Sim.newMatch("Training", "Kael", "Sierra"); place(m, Vector3.zero, Vector3.new(3, 0, 0))
		local f = m.fighters[1]
		Sim.press(m, 1, "LeadPunch"); run(m, 2)
		Sim.press(m, 1, "RearPunch")
		expect.equal(f.chainMove, "OneTwo", "early press buffers the follow-up")
		run(m, 30)
		m = Sim.newMatch("Training", "Kael", "Sierra"); place(m, Vector3.zero, Vector3.new(3, 0, 0)); f = m.fighters[1]
		Sim.press(m, 1, "LeadPunch")
		local jab = Roster.getMove("Kael", "Jab")
		run(m, jab.startup + jab.active + Sim.ChainLate + 1)
		expect.equal(Sim.selectMove(f, "RearPunch"), "Cross", "after the window the button is a fresh move")
	end)

	test("lunging moves move the attacker forward without pushing the opponent", function()
		local m = Sim.newMatch("Training", "Goran", "Kael"); place(m, Vector3.zero, Vector3.new(7, 0, 0))
		local a, d = m.fighters[1], m.fighters[2]
		local def = Roster.getMove("Goran", "Bulldozer")
		Sim.queueAttack(a, "Bulldozer")
		run(m, def.startup + 1)
		expect.near(a.pos.X, def.advance, 0.05, "advanced by the first active frame")
		expect.near(d.pos.X, 7, 0.001, "opponent not pushed by the lunge")
		m = Sim.newMatch("Training", "Goran", "Kael"); place(m, Vector3.zero, Vector3.new(2.8, 0, 0)); a, d = m.fighters[1], m.fighters[2]
		Sim.queueAttack(a, "Bulldozer"); run(m, def.startup)
		expect.truthy(flatDist(a.pos, d.pos) >= Config.Separation - 1e-3, "stops at the separation distance")
		expect.near(d.pos.X, 2.8, 0.001)
	end)

	test("combo counter clears when defender becomes actionable", function()
		local m = Sim.newMatch(); place(m, Vector3.zero, Vector3.new(3, 0, 0)); Sim.queueAttack(m.fighters[1], "Jab")
		run(m, Config.Moves.Jab.startup + 1); expect.equal(m.fighters[1].combo, 1)
		run(m, Config.Moves.Jab.stun); expect.equal(m.fighters[1].combo, 0)
		Sim.queueAttack(m.fighters[1], "Jab"); local events = run(m, 12); expect.equal(events[1].combo, 1)
	end)

	test("ready held movement survives fight transition", function()
		local m = Sim.newMatch("Match"); m.fighters[1].input.moveX = 1
		run(m, Config.ReadyFrames); local before = m.fighters[1].pos
		run(m, 1); expect.truthy(m.fighters[1].pos.X > before.X)
	end)

	test("round timer health decision and round reset", function()
		local m = Sim.newMatch("Match"); run(m, Config.ReadyFrames); expect.equal(m.phase, "Fight"); expect.equal(m.timer, Config.RoundFrames)
		m.fighters[1].health = 80; m.fighters[2].health = 70
		run(m, Config.RoundFrames - 1); expect.equal(m.phase, "Fight"); expect.equal(m.timer, 1)
		run(m, 1); expect.equal(m.phase, "RoundOver"); expect.equal(m.winner, 1); expect.equal(m.scores[1], 1); expect.equal(m.reason, "TIME")
		run(m, Config.RoundBreakFrames); expect.equal(m.round, 2); expect.equal(m.phase, "Ready"); expect.equal(m.fighters[1].health, m.fighters[1].maxHealth); expect.equal(m.scores[1], 1)
	end)

	test("best of three match ends and rematch resets scores", function()
		local m = Sim.newMatch("Match")
		for round = 1, 2 do
			run(m, Config.ReadyFrames); place(m, Vector3.zero, Vector3.new(3, 0, 0)); m.fighters[2].health = 1; m.fighters[2].dummy = "Stand"
			Sim.queueAttack(m.fighters[1], "Jab"); run(m, Config.Moves.Jab.startup + 2)
			expect.equal(m.scores[1], round)
			if round == 1 then expect.equal(m.phase, "RoundOver"); run(m, Config.RoundBreakFrames) end
		end
		expect.equal(m.phase, "MatchOver"); local timer = m.timer; run(m, 100); expect.equal(m.timer, timer)
		Sim.reset(m); expect.equal(m.phase, "Ready"); expect.equal(m.scores[1], 0); expect.equal(m.scores[2], 0)
	end)

	test("one all goes to deciding third round", function()
		local m = Sim.newMatch("Match")
		for round, winner in { 1, 2, 1 } do
			run(m, Config.ReadyFrames); m.timer = 1
			m.fighters[1].health = if winner == 1 then 90 else 80
			m.fighters[2].health = if winner == 2 then 90 else 80
			run(m, 1)
			if round < 3 then expect.equal(m.phase, "RoundOver"); run(m, Config.RoundBreakFrames)
			else expect.equal(m.phase, "MatchOver"); expect.equal(m.scores[1], 2); expect.equal(m.scores[2], 1); expect.equal(m.winner, 1) end
		end
	end)

	test("draw replay and unlimited training", function()
		local m = Sim.newMatch("Match"); run(m, Config.ReadyFrames); m.fighters[1].health = 80; m.fighters[2].health = 80; m.timer = 1; run(m, 1)
		expect.equal(m.winner, 0); expect.equal(m.scores[1], 0); expect.equal(m.scores[2], 0)
		Sim.setMode(m, "Training"); run(m, Config.RoundFrames + 100); expect.equal(m.phase, "Fight"); expect.equal(m.timer, Config.RoundFrames)
		Sim.setMode(m, "Match"); expect.equal(m.phase, "Ready"); expect.equal(m.round, 1)
	end)

	test("match trainer approaches and attacks without input reading", function()
		local m = Sim.newMatch("Match"); local approached = false; local produced = false
		for _ = 1, 9000 do Sim.trainerInput(m, 2); local events = Sim.step(m)
			if m.fighters[2].pos.X < 2.9 then approached = true end
			if #events > 0 then produced = true end
			if m.phase == "MatchOver" then break end
		end
		expect.truthy(approached); expect.truthy(produced)
	end)

	test("strict remote input validation", function()
		for _, args in { { "Move", 2, 0 }, { "Move", 0 / 0, 0 }, { "Move", math.huge, 0 }, { "Move", 0.5, 0 }, { "Move", "1", 0 }, { "Attack", "Rise" }, { "Attack", {} }, { "Block", 1 }, { "Crouch", "true" }, { "Reset", true }, { "SetMode", "Arcade" }, { "SetMode", "Match", true }, { "Teleport" }, { "Dummy", "Sleep" }, { "Dummy", "Stand", 1 } } do
			expect.falsy(Sim.validCommand(args[1], args[2], args[3]))
		end
		expect.truthy(Sim.validCommand("Move", -1, 1)); expect.truthy(Sim.validCommand("Crouch", true, nil))
		expect.truthy(Sim.validCommand("SetMode", "Match", nil)); expect.truthy(Sim.validCommand("SetMode", "Training", nil))
		expect.truthy(Sim.validCommand("Dummy", "Guard", nil)); expect.truthy(Sim.validCommand("Dummy", nil, nil))
		for _, button in Config.Buttons do expect.truthy(Sim.validCommand("Attack", button, nil)) end
	end)

	test("each move hits exactly once in range", function()
		for _, name in Config.MoveOrder do
			local m = Sim.newMatch()
			place(m, Vector3.zero, Vector3.new(3, 0, 0))
			Sim.queueAttack(m.fighters[1], name)
			local events = run(m, Sim.totalFrames(name) + 2)
			expect.equal(count(events, "Hit"), 1, name .. " hit count")
			expect.equal(count(events, "Whiff"), 0, name .. " whiffs")
			expect.equal(m.fighters[2].health, m.fighters[2].maxHealth - Config.Moves[name].damage, name .. " damage")
		end
	end)

	test("hit lands on the first active frame", function()
		local m = Sim.newMatch()
		place(m, Vector3.zero, Vector3.new(3, 0, 0))
		Sim.queueAttack(m.fighters[1], "Jab")
		local startup = Config.Moves.Jab.startup
		expect.equal(count(run(m, startup), "Hit"), 0, "no hit during startup")
		expect.equal(count(run(m, 1), "Hit"), 1, "hit on first active frame")
	end)

	test("out of range attack whiffs once and deals no damage", function()
		local m = Sim.newMatch()
		Sim.queueAttack(m.fighters[1], "Jab")
		local events = run(m, Sim.totalFrames("Jab") + 2)
		expect.equal(count(events, "Hit"), 0)
		expect.equal(count(events, "Whiff"), 1)
		expect.equal(m.fighters[2].health, m.fighters[2].maxHealth)
		expect.equal(m.fighters[1].state, "Idle", "returns to idle after recovery")
	end)

	test("narrow lane misses an off-line target while the wide kick reaches it", function()
		local m = Sim.newMatch()
		place(m, Vector3.zero, Vector3.new(3, 0, 0))
		m.fighters[2].pos = Vector3.new(3, 0, 2)
		local jabOk = Sim.reach(m.fighters[1], m.fighters[2], "Jab")
		local kickOk = Sim.reach(m.fighters[1], m.fighters[2], "Kick")
		expect.falsy(jabOk, "jab lane")
		expect.truthy(kickOk, "kick lane")
	end)

	test("hitstun and recovery ignore movement input", function()
		local m = Sim.newMatch()
		place(m, Vector3.zero, Vector3.new(3, 0, 0))
		Sim.queueAttack(m.fighters[1], "Jab")
		run(m, Config.Moves.Jab.startup + 1)
		local target = m.fighters[2]
		expect.equal(target.state, "Hitstun")
		Sim.setMovement(m, 2, 0, 1)
		local before = target.pos
		run(m, 3)
		expect.equal(target.pos, before, "hitstun lock")
		expect.equal(m.fighters[1].state, "Recovery")
		local attacker = m.fighters[1]
		attacker.input.moveX = -1
		local attackerBefore = attacker.pos
		run(m, 2)
		expect.equal(attacker.pos, attackerBefore, "recovery lock")
	end)

	test("stale buffered attacks expire", function()
		local m = Sim.newMatch()
		place(m, Vector3.zero, Vector3.new(3, 0, 0))
		Sim.queueAttack(m.fighters[1], "Jab")
		run(m, Config.Moves.Jab.startup + 1)
		Sim.queueAttack(m.fighters[2], "Jab")
		run(m, Config.Moves.Jab.stun + 2)
		expect.equal(m.fighters[2].move, nil, "input older than the buffer is dropped")
		expect.equal(m.fighters[2].input.attack, nil)
	end)

	test("lethal hit causes KO and reset restores the match", function()
		local m = Sim.newMatch()
		place(m, Vector3.zero, Vector3.new(3, 0, 0))
		m.fighters[2].health = 5
		Sim.queueAttack(m.fighters[1], "Jab")
		local events = run(m, Sim.totalFrames("Jab"))
		expect.equal(count(events, "KO"), 1)
		expect.equal(m.fighters[2].health, 0)
		expect.equal(m.fighters[2].state, "KO")
		expect.truthy(m.koFrame ~= nil)
		m.fighters[2].input.moveX = 1
		local koPos = m.fighters[2].pos
		run(m, 5)
		expect.equal(m.fighters[2].pos, koPos, "KO fighter stays down")
		Sim.reset(m)
		expect.equal(m.koFrame, nil)
		for _, f in m.fighters do
			expect.equal(f.health, f.maxHealth)
			expect.equal(f.state, "Idle")
		end
		expect.near((m.fighters[2].pos - m.fighters[1].pos).Magnitude, Config.StartDistance)
	end)

	test("fighters never overlap and stay inside the ring", function()
		local m = Sim.newMatch()
		place(m, Vector3.zero, Vector3.new(0.5, 0, 0.2))
		m.fighters[1].input.moveX = 1
		m.fighters[2].input.moveX = 1
		for _ = 1, 30 do
			Sim.step(m)
			local d = (m.fighters[2].pos - m.fighters[1].pos).Magnitude
			expect.truthy(d >= Config.Separation - 1e-3, "separation " .. d)
		end
		local far = Sim.newMatch()
		place(far, Vector3.new(20, 0, 0), Vector3.new(-5, 0, 0))
		far.fighters[1].input.moveX = -1
		run(far, 120)
		expect.truthy(far.fighters[1].pos.Magnitude <= Config.ArenaRadius + 1e-3, "clamped to ring")
	end)

	test("unknown moves are rejected", function()
		local m = Sim.newMatch()
		expect.throws(function() Sim.queueAttack(m.fighters[1], "Teleport") end)
	end)

	test("trainer spar runs deterministically with bounded health", function()
		local function simulate(): (number, number)
			local m = Sim.newMatch()
			local n = 0
			for _ = 1, 900 do
				Sim.trainerInput(m, 2)
				n += #Sim.step(m)
			end
			for _, f in m.fighters do
				expect.truthy(f.health >= 0 and f.health <= f.maxHealth)
			end
			return n, m.fighters[2].pos.X
		end
		local n1, x1 = simulate()
		local n2, x2 = simulate()
		expect.truthy(n1 > 0, "trainer produced combat events")
		expect.equal(n1, n2)
		expect.equal(x1, x2)
	end)

	test("launcher and sweep poses retract with recovery", function()
		local rig = require(RS.FightingLab.FighterRig)
		local rise = rig.targetPose("Recovery", "Rise", Sim.totalFrames("Rise"), 0, 0, false)
		expect.near(rise.rShoulder, math.rad(55)); expect.near(rise.rElbow, math.rad(105))
		local sweep = rig.targetPose("Recovery", "Sweep", Sim.totalFrames("Sweep"), 0, 0, true)
		expect.near(sweep.rHip, math.rad(18)); expect.near(sweep.rHipRoll, math.rad(6)); expect.near(sweep.crouch, 1)
		expect.equal(rig.targetPose("Landing", nil, 0, 0, 10, false).fall, 1)
		expect.truthy(rig.targetPose("Getup", nil, 0, 0, 8, false).fall < 1)
	end)
end
