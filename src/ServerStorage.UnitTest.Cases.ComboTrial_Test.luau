--!strict
-- Round 7, Contract C: ComboTrial. Every listed combo completes its trial when its demo inputs are played through a
-- practice MatchRunner (counter routes: the dummy is attacking when the opener lands); late, dropped, wrong-move and
-- blocked attempts fail with the right reason; the step moves are the moves the sim really performs.
local RS = game:GetService("ReplicatedStorage")
local Lab = RS:WaitForChild("FightingLab")
local Sim = require(Lab:WaitForChild("CombatSim"))
local Roster = require(Lab:WaitForChild("Roster"))
local MatchRunner = require(Lab:WaitForChild("MatchRunner"))
local ComboTrial = require(Lab:WaitForChild("ComboTrial"))

type Script = { { frame: number, press: string?, hold: { moveX: number, moveZ: number, crouch: boolean }?, step: number?, notation: string? } }

-- Plays an input script in a practice runner (slot 1 = player, slot 2 = standing dummy) and feeds every entry to a
-- trial. `edit(script)` may change the script first; `onFrame(runner, frame)` runs before each step.
local function play(id: string, index: number, foe: string, demo: Script, onFrame: ((any, number) -> ())?, human2: boolean?): (any, { any })
	local runner = MatchRunner.new()
	runner:configure({ mode = "Training", p1Id = id, p2Id = foe, stageId = "TrainingBay", human1 = true, human2 = human2 == true })
	local trial = ComboTrial.new(id, index)
	local statuses = {}
	local cursor = 1
	local last = if #demo > 0 then demo[#demo].frame else 0
	local status = trial:status()
	for frame = 0, last + 420 do
		while demo[cursor] and demo[cursor].frame == frame do
			local e = demo[cursor]
			if e.hold then
				runner:command("Move", e.hold.moveX, e.hold.moveZ, 1)
				runner:command("Crouch", e.hold.crouch, nil, 1)
			end
			if e.press then runner:command("Attack", e.press, nil, 1) end
			cursor += 1
		end
		if onFrame then onFrame(runner, frame) end
		status = trial:feed(runner:step())
		table.insert(statuses, status)
		if frame > last and (status.state == "Success" or status.state == "Failed") and runner.match.fighters[1].state ~= "Ultimate" then break end
	end
	return status, statuses
end

-- Counter routes: the dummy (a second human slot) starts its jab so that the opener lands during the jab's startup
-- (the opener is pressed on frame P and starts at once; the jab, pressed on P + startup - 7, is on its 8th of 9
-- startup frames when the opener's first active frame arrives).
local function counterHook(id: string, index: number, demo: Script): (any, number) -> ()
	local openerFrame = 0
	for _, e in demo do if e.press and e.step == 1 then openerFrame = e.frame break end end
	local def = Roster.getMove(id, ComboTrial.list(id)[index].steps[1].move)
	local counterAt = openerFrame + def.startup - 7
	return function(runner, frame)
		if frame == counterAt then runner:command("Attack", "LeadPunch", nil, 2) end
	end
end

local function cloneScript(demo: Script): Script
	local out = {}
	for _, e in demo do
		local c = table.clone(e)
		if e.hold then c.hold = table.clone(e.hold) end
		table.insert(out, c)
	end
	return out
end

-- Shifts every entry of step `k` and after by `delta` frames (a press `delta` frames late).
local function delayFrom(demo: Script, k: number, delta: number): Script
	local out = cloneScript(demo)
	local from: number? = nil
	for _, e in out do if e.step == k then from = e.frame break end end
	assert(from, "step " .. k)
	for _, e in out do if e.frame >= (from :: number) then e.frame += delta end end
	return out
end

local function synthetic(dummyState: string, events: { any }, dummyY: number?): any
	return {
		frame = 0, hitstop = 0, events = events,
		fighters = {
			{ characterId = "Kael", state = "Startup", move = "Jab", moveFrame = 5 },
			{ characterId = "Sierra", state = dummyState, pos = Vector3.new(3, dummyY or 0, 0), knockdown = nil },
		},
	}
end

return function(t)
	local test, expect = t.test, t.expect

	test("list() carries every listed combo with the moves the sim really performs", function()
		for _, id in Roster.order do
			local c = Roster.get(id)
			local list = ComboTrial.list(id)
			expect.equal(#list, #c.combos, id .. " combos")
			for i, info in list do
				local combo = c.combos[i]
				expect.equal(info.index, i)
				expect.equal(info.name, combo.name)
				expect.equal(info.notation, combo.notation)
				expect.equal(info.difficulty, combo.difficulty)
				expect.equal(info.damage, combo.damage)
				expect.equal(#info.steps, #combo.steps, id .. " " .. combo.name .. " steps")
				-- The listed timing played by Sim.comboRun presses exactly these moves.
				local m = Sim.newMatch("Training", id, "Goran")
				m.fighters[1].pos = Vector3.zero
				m.fighters[2].pos = Vector3.new(combo.distance or 3.0, 0, 0)
				local run = Sim.comboRun(m, 1, combo.steps)
				for _ = 1, 900 do
					if m.hitstop == 0 then Sim.comboTick(run) end
					Sim.step(m)
					if run.step > #combo.steps and not run.release then break end
				end
				for k, step in info.steps do
					expect.equal(step.notation, combo.steps[k].input)
					expect.truthy(#step.label > 0, id .. " step label")
					expect.equal(step.move, run.pressed[k], string.format("%s %s step %d (%s)", id, combo.name, k, step.notation))
				end
			end
		end
		expect.equal(#ComboTrial.list("Nobody"), 0, "unknown fighter: no trials")
	end)

	test("every listed combo of all six fighters completes its trial from its demo inputs", function()
		for n, id in Roster.order do
			local foe = Roster.order[(n % #Roster.order) + 1]
			for i, info in ComboTrial.list(id) do
				local demo = ComboTrial.demo(id, i)
				expect.truthy(#demo > 0, id .. " demo")
				local presses = 0
				for k, e in demo do
					if k > 1 then expect.truthy(e.frame >= demo[k - 1].frame, "demo frames are ordered") end
					if e.press then presses += 1; expect.truthy(Sim.validCommand("Attack", e.press, nil), "demo press is a sim button") end
				end
				expect.equal(presses, #info.steps, id .. " " .. info.name .. " demo presses every step")
				local hook = if info.counter then counterHook(id, i, demo) else nil
				local status = play(id, i, foe, demo, hook, info.counter)
				local label = string.format("%s '%s' vs %s", id, info.name, foe)
				expect.equal(status.state, "Success", label .. " (" .. tostring(status.reason) .. " at step " .. status.step .. ")")
				expect.equal(status.step, #info.steps, label .. " steps")
				expect.equal(status.total, #info.steps)
				expect.equal(status.reason, nil)
				-- Free Training has no Surge damage bonus, so an Ultimate ender reads a little lower than listed.
				local low = if info.surge then info.damage - 5 else info.damage - 1
				expect.truthy(status.damage >= low and status.damage <= info.damage + 1, string.format("%s damage %d (listed %d)", label, status.damage, info.damage))
			end
		end
	end)

	test("a trial waits for its opener: whiffs and other moves leave it Ready", function()
		local trial = ComboTrial.new("Kael", 1)
		local s = trial:status()
		expect.equal(s.state, "Ready"); expect.equal(s.step, 0); expect.equal(s.total, #ComboTrial.list("Kael")[1].steps)
		s = trial:feed(synthetic("Idle", { { kind = "Hit", attacker = 1, target = 2, move = "Cross", damage = 9, combo = 1 } }))
		expect.equal(s.state, "Ready", "another move does not start it")
		s = trial:feed(synthetic("Idle", { { kind = "Whiff", attacker = 1, target = 2, move = "RisingUppercut", damage = 0, combo = 0 } }))
		expect.equal(s.state, "Ready", "a whiffed opener does not start it")
		s = trial:feed({ fighters = {} })
		expect.equal(s.state, "Ready", "malformed entries are ignored")
		-- A counter route needs a counter-hit opener.
		local counterIndex: number? = nil
		for i, info in ComboTrial.list("Kael") do if info.counter then counterIndex = i end end
		if counterIndex then
			local ch = ComboTrial.new("Kael", counterIndex)
			local opener = ComboTrial.list("Kael")[counterIndex].steps[1].move
			expect.equal(ch:feed(synthetic("Airborne", { { kind = "Hit", attacker = 1, target = 2, move = opener, damage = 14, combo = 1, air = true } })).state, "Ready", "normal hit is not a counter opener")
			expect.equal(ch:feed(synthetic("Airborne", { { kind = "Hit", attacker = 1, target = 2, move = opener, damage = 18, combo = 1, air = true, counter = true } })).state, "Running")
		end
	end)

	test("late, dropped, wrong-move and blocked attempts fail with the right reason", function()
		-- Kael's first route: opener, juggle hits, then a 2,1 string.
		local info = ComboTrial.list("Kael")[1]
		local demo = ComboTrial.demo("Kael", 1)
		local lastStep = #info.steps
		-- Late: the last press of a string follow-up after the string window (the plain move comes out instead).
		local plain = (ComboTrial.new("Kael", 1) :: any).plainMoves[lastStep]
		if plain then
			local late: any = nil
			for delta = 8, 80, 2 do
				local status = play("Kael", 1, "Goran", delayFrom(demo, lastStep, delta))
				if status.state == "Failed" then late = status; break end
			end
			assert(late, "a late string press fails")
			expect.equal(late.reason, "Late", "late string press")
			expect.equal(late.step, lastStep - 1)
		end
		-- Late: a juggle hit pressed so late that it comes out on the falling body after it landed.
		do
			local late: any = nil
			for delta = 6, 40, 2 do
				local status = play("Kael", 1, "Goran", delayFrom(demo, 2, delta))
				if status.state == "Failed" and status.step == 1 then late = status; break end
			end
			assert(late, "a late juggle press fails")
			expect.truthy(late.reason == "Late" or late.reason == "Dropped", "late juggle press: " .. tostring(late.reason))
		end
		-- Dropped: step 2 never pressed.
		do
			local skipped = cloneScript(demo)
			for k = #skipped, 1, -1 do if skipped[k].step == 2 then table.remove(skipped, k) end end
			for _, e in skipped do if e.step and e.step > 2 then e.press = nil end end
			local status = play("Kael", 1, "Goran", skipped)
			expect.equal(status.state, "Failed", "skipped step")
			expect.equal(status.reason, "Dropped")
			expect.equal(status.step, 1)
		end
		-- Wrong: a different button for step 2.
		do
			local wrong = cloneScript(demo)
			for _, e in wrong do if e.step == 2 then e.press = if e.press == "RearKick" then "LeadKick" else "RearKick" end end
			local status = play("Kael", 1, "Goran", wrong)
			expect.equal(status.state, "Failed", "wrong button")
			expect.equal(status.reason, "Wrong")
			expect.equal(status.step, 1)
		end
		-- Blocked: a route that opens with the 3+4 stance against a guarding dummy (its first hit is blocked).
		for i, route in ComboTrial.list("Kael") do
			if route.steps[1].stance then
				local status = play("Kael", i, "Goran", ComboTrial.demo("Kael", i), function(runner, frame)
					if frame == 0 then runner:setDummy("Guard") end
				end)
				expect.equal(status.state, "Failed", "stance route into a guarding dummy")
				expect.equal(status.reason, "Blocked")
				expect.equal(status.step, 1)
				break
			end
		end
		-- After a failure a new opener hit starts the next attempt by itself; reset() goes back to Ready.
		local trial = ComboTrial.new("Kael", 1)
		local opener = info.steps[1].move
		trial:feed(synthetic("Airborne", { { kind = "Hit", attacker = 1, target = 2, move = opener, damage = 14, combo = 1, air = true } }))
		local s = trial:feed(synthetic("Airborne", { { kind = "Hit", attacker = 1, target = 2, move = "LegKick", damage = 10, combo = 2, air = true } }))
		expect.equal(s.state, "Failed"); expect.equal(s.reason, "Wrong")
		s = trial:feed(synthetic("Airborne", { { kind = "Hit", attacker = 1, target = 2, move = opener, damage = 14, combo = 1, air = true } }))
		expect.equal(s.state, "Running", "a new opener restarts"); expect.equal(s.step, 1); expect.equal(s.damage, 14)
		trial:reset()
		s = trial:status()
		expect.equal(s.state, "Ready"); expect.equal(s.step, 0); expect.equal(s.damage, 0); expect.equal(s.reason, nil)
	end)

	test("early and whiffed juggle hits are named (synthetic entries)", function()
		local info = ComboTrial.list("Kael")[1]
		local opener, second = info.steps[1].move, info.steps[2].move
		local function running(): any
			local trial = ComboTrial.new("Kael", 1)
			trial:feed(synthetic("Airborne", { { kind = "Hit", attacker = 1, target = 2, move = opener, damage = 14, combo = 1, air = true } }))
			return trial
		end
		local s = running():feed(synthetic("Airborne", { { kind = "Whiff", attacker = 1, target = 2, move = second, damage = 0, combo = 0 } }, 4.6))
		expect.equal(s.reason, "Early", "whiff under a body still too high")
		s = running():feed(synthetic("Airborne", { { kind = "Whiff", attacker = 1, target = 2, move = second, damage = 0, combo = 0 } }, 1.5))
		expect.equal(s.reason, "Whiffed", "whiff in reach of the ceiling: out of reach")
		s = running():feed(synthetic("Airborne", { { kind = "Block", attacker = 1, target = 2, move = second, damage = 0, combo = 0 } }, 1.5))
		expect.equal(s.reason, "Blocked")
		s = running():feed(synthetic("Hitstun", { { kind = "Hit", attacker = 1, target = 2, move = second, damage = 4, combo = 1 } }))
		expect.equal(s.reason, "Late", "a hit that no longer combos")
	end)
end
