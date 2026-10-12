--!strict
-- Practice lesson (OV6): every step completes from fake snapshot entries using the state names and events published
-- by combat (combat-states.md): Walk/Backwalk, Dash/Backdash, Sidestep (stepDir), Block events, guard = "Crouch",
-- the fighter's string move, a launcher hit, ThrowHit/ThrowStart and ThrowBreak. LobbyUI sets the dummy each step.
-- The last tests play the whole lesson for every fighter against the real MatchRunner/CombatSim and CPU dummy.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lab = ReplicatedStorage:WaitForChild("FightingLab")
local Client = Lab:WaitForChild("Client")
local UIState = require(Client:WaitForChild("UIState"))
local LobbyUI = require(Client:WaitForChild("LobbyUI"))
local Roster = require(Lab:WaitForChild("Roster"))
local Runner = require(game:GetService("ServerStorage").UnitTest.RunUnitTest)

local function entry(fighter: { [string]: any }?, events: { any }?, slot: number?): any
	local fighters = { {}, {} }
	if fighter then fighters[slot or 1] = fighter end
	return { mode = "Training", dummy = "Stand", fighters = fighters, events = events or {} }
end

-- Feeds `count` identical entries; returns the clock after them.
local function feed(t: UIState.Tutorial, e: any, count: number, now: number): number
	for _ = 1, count do
		now += 1 / 60
		UIState.tutorialObserve(t, e, now)
	end
	return now
end

local function finishStep(t: UIState.Tutorial, now: number): number
	return feed(t, entry({ state = "Idle" }), 2, now + UIState.TUTORIAL_ADVANCE)
end

local function firstMove(def: any, pred: (any) -> boolean): string?
	for _, key in def.moveOrder do
		local mv = def.moves[key]
		if mv and pred(mv) then return key end
	end
	return nil
end

-- Plays the whole lesson against the real combat sim (MatchRunner + CombatSim + the CPU dummy): the player's inputs
-- go straight into the sim, the lesson sets the dummy behaviour per step like LobbyUI does, and every entry the
-- runner builds is fed to the lesson. Returns the ids of the steps that completed.
local BUTTONS = { LP = "LeadPunch", RP = "RearPunch", LK = "LeadKick", RK = "RearKick" }
local function playLessonInSim(fighterId: string): { string }
	local Sim = require(Lab:WaitForChild("CombatSim")) :: any
	local MatchRunner = require(Lab:WaitForChild("MatchRunner")) :: any
	local runner = MatchRunner.new()
	local opponent = if fighterId == "Sierra" then "Kael" else "Sierra"
	runner:configure({ mode = "Training", p1Id = fighterId, p2Id = opponent, human1 = true, human2 = false })
	runner.match.aiSeed = 4242
	local match = runner.match
	local lesson = UIState.tutorialNew(1, fighterId, Roster)
	local def = Roster.get(fighterId)
	local now, lastDummy = 0, nil
	local lastReset = 0
	local e: any = runner:step()
	local done: { string } = {}
	local function frame()
		local step = UIState.tutorialStep(lesson)
		if step and step.dummy ~= lastDummy then lastDummy = step.dummy; runner:setDummy(step.dummy) end
		-- Like LobbyUI: a step marked "reset" starts from neutral spacing (once per step).
		if step and step.reset and lastReset ~= lesson.index then lastReset = lesson.index; runner:command("Reset", nil, nil, 1) end
		e = runner:step()
		now += 1 / 60
		local index = lesson.index
		UIState.tutorialObserve(lesson, e, now)
		if lesson.stepDoneAt and lesson.steps[index] and done[#done] ~= lesson.steps[index].id then table.insert(done, lesson.steps[index].id) end
	end
	local function run(n: number) for _ = 1, n do frame() end end
	local function move(x: number, z: number) Sim.setMovement(match, 1, x, z) end
	local function crouch(on: boolean) match.fighters[1].input.crouch = on end
	local function finished(i: number): boolean return lesson.done or lesson.index > i or (lesson.index == i and lesson.stepDoneAt ~= nil) end
	local function nextStep(i: number) local n = 0; while lesson.index == i and not lesson.done and n < 300 do frame(); n += 1 end end
	local function dist(): number
		local a, b = e.fighters[1].pos, e.fighters[2].pos
		return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
	end
	local function approach(target: number)
		local n = 0
		move(1, 0)
		while dist() > target and n < 300 do frame(); n += 1 end
		move(0, 0)
		run(20) -- outside the double-tap window, so the next forward press is not a dash
	end
	-- "df+RP" / "LP, RP": held direction, then the buttons a few frames apart (a string).
	local function perform(input: string)
		local dir, rest = string.match(input, "^(%a+)%+(.+)$")
		if not dir or not string.match(rest :: string, "^[LR][PK]") then dir, rest = nil, input end
		if dir == "d" or dir == "df" or dir == "db" then crouch(true); run(3) end
		if dir == "f" or dir == "df" then move(1, 0) elseif dir == "b" or dir == "db" then move(-1, 0) end
		if dir then run(2) end
		for part in string.gmatch(rest :: string, "[^,]+") do
			Sim.press(match, 1, BUTTONS[(string.gsub(part, "%s", ""))] or "LeadPunch")
			run(7)
		end
		move(0, 0); crouch(false)
		run(45)
	end
	-- 1-4: walk, dash, backdash, sidestep in + out
	move(1, 0); run(25); move(-1, 0); run(25); move(0, 0); run(2); nextStep(1)
	move(1, 0); run(1); move(0, 0); run(2); move(1, 0); run(2); move(0, 0); run(24); nextStep(2)
	move(-1, 0); run(1); move(0, 0); run(2); move(-1, 0); run(2); move(0, 0); run(26); nextStep(3)
	move(0, 1); run(1); move(0, 0); run(30); move(0, -1); run(1); move(0, 0); run(30); nextStep(4)
	-- 5 standing guard: stand still while the fighting dummy attacks
	local n = 0
	while not finished(5) and n < 3000 do frame(); n += 1 end
	nextStep(5)
	-- 6 crouch guard
	crouch(true); n = 0
	while not finished(6) and n < 600 do frame(); n += 1 end
	crouch(false); nextStep(6)
	-- 7 the lesson's string, 8 its launcher, 9 a throw against the guarding dummy
	local stringKey = next(lesson.strings)
	if stringKey then approach(3.3); perform(def.moves[stringKey].input) end
	nextStep(7)
	local launcherKey: string? = nil
	for key in lesson.launchers do if def.moves[key].chainFrom == nil then launcherKey = key end end
	if launcherKey then approach(3.2); perform(def.moves[launcherKey].input) end
	nextStep(8)
	approach(2.0); Sim.press(match, 1, "Throw"); run(80); nextStep(9)
	-- 10 break the fighting dummy's throw with the button its throw names
	n = 0
	while not finished(10) and n < 7200 do
		frame(); n += 1
		for _, ev in e.events do
			if ev.kind == "ThrowStart" and ev.attacker == 2 then
				local mv = Roster.get(opponent).moves[ev.move]
				local button = if mv and typeof(mv.input) == "string" and string.find(mv.input, "RP", 1, true) then "RearPunch" else "LeadPunch"
				run(4)
				Sim.press(match, 1, button)
			end
		end
	end
	nextStep(10)
	return done
end

return function(t: Runner.T)
	t.test("lesson has ten steps for every fighter, with a string and a launcher to teach", function()
		for _, id in Roster.order do
			local lesson = UIState.tutorialNew(1, id, Roster)
			t.expect.equal(#lesson.steps, 10, id)
			local ids = {}
			for _, s in lesson.steps do table.insert(ids, s.id) end
			t.expect.equal(table.concat(ids, ","), "walk,dash,backdash,sidestep,standGuard,crouchGuard,string,launcher,throw,throwBreak")
			t.expect.truthy(next(lesson.strings) ~= nil or string.find(lesson.steps[7].goals[1].text, "Two hits", 1, true) ~= nil, id .. " has a string (or the two-hit fallback) to teach")
			t.expect.truthy(next(lesson.launchers) ~= nil, id .. " has a launcher to teach")
			for _, s in lesson.steps do
				t.expect.falsy(string.find(UIState.fillKeys(s.text), "{", 1, true), id .. " " .. s.id .. " text has no unresolved key")
			end
		end
	end)

	t.test("every step completes from fake snapshot states and events, in order", function()
		local id = Roster.order[1]
		local def = Roster.get(id)
		local lesson = UIState.tutorialNew(1, id, Roster)
		local now = 100
		-- 1 walk: forward and back frames
		now = feed(lesson, entry({ state = "Walk" }), 10, now)
		t.expect.equal(lesson.index, 1)
		t.expect.equal(lesson.stepDoneAt, nil, "half a walk is not enough")
		now = feed(lesson, entry({ state = "Walk" }), 10, now)
		now = feed(lesson, entry({ state = "Backwalk" }), 20, now)
		t.expect.truthy(lesson.stepDoneAt ~= nil, "walk done")
		now = feed(lesson, entry({ state = "Idle" }), 3, now)
		t.expect.equal(lesson.index, 1, "a finished step stays ticked for a moment")
		now = finishStep(lesson, now)
		t.expect.equal(lesson.index, 2)
		-- 2 dash
		now = feed(lesson, entry({ state = "Dash", dashDirection = 1 }), 1, now)
		t.expect.truthy(lesson.stepDoneAt ~= nil, "dash done")
		now = finishStep(lesson, now)
		-- 3 backdash
		now = feed(lesson, entry({ state = "Dash", dashDirection = 1 }), 1, now)
		t.expect.equal(lesson.stepDoneAt, nil, "a forward dash is not a backdash")
		now = feed(lesson, entry({ state = "Idle" }), 1, now)
		now = feed(lesson, entry({ state = "Backdash" }), 1, now)
		t.expect.truthy(lesson.stepDoneAt ~= nil, "backdash done")
		now = finishStep(lesson, now)
		-- 4 sidestep: one step in, one step out (one per entry into the state)
		now = feed(lesson, entry({ state = "Sidestep", stepDir = 1 }), 12, now)
		t.expect.equal(lesson.steps[4].goals[1].have, 1)
		t.expect.equal(lesson.stepDoneAt, nil)
		now = feed(lesson, entry({ state = "Idle" }), 1, now)
		now = feed(lesson, entry({ state = "Sidestep", stepDir = -1 }), 1, now)
		t.expect.truthy(lesson.stepDoneAt ~= nil, "sidestep in and out done")
		now = finishStep(lesson, now)
		-- 5 standing guard: two blocks of high/mid attacks aimed at us; a low block does not count
		now = feed(lesson, entry({ state = "Blockstun", guard = "Stand" }, { { kind = "Block", attacker = 2, target = 1, height = "Low", frame = 1 } }), 1, now)
		t.expect.equal(lesson.steps[5].goals[1].have, 0)
		now = feed(lesson, entry({ state = "Blockstun", guard = "Stand" }, { { kind = "Block", attacker = 2, target = 1, height = "Mid", frame = 2 } }), 1, now)
		now = feed(lesson, entry({ state = "Blockstun" }, { { kind = "Block", attacker = 1, target = 2, height = "High", frame = 3 } }), 1, now)
		t.expect.equal(lesson.steps[5].goals[1].have, 1, "only blocks by the player count")
		now = feed(lesson, entry({ state = "Blockstun", guard = "Stand" }, { { kind = "Block", attacker = 2, target = 1, height = "High", frame = 4 } }), 1, now)
		t.expect.truthy(lesson.stepDoneAt ~= nil, "standing guard done")
		now = finishStep(lesson, now)
		-- 6 crouch guard: holding crouch guard long enough
		now = feed(lesson, entry({ state = "Crouch", guard = "Crouch", crouched = true }), 45, now)
		t.expect.truthy(lesson.stepDoneAt ~= nil, "crouch guard done")
		now = finishStep(lesson, now)
		-- 7 string: the fighter's 1,2 (or first string) move
		local stringKey = next(lesson.strings) :: string
		now = feed(lesson, entry({ state = "Active", move = firstMove(def, function(mv) return mv.height ~= "Throw" and mv.chainFrom == nil end) }), 2, now)
		t.expect.equal(lesson.stepDoneAt, nil, "a single poke is not the string")
		now = feed(lesson, entry({ state = "Startup", move = stringKey }), 1, now)
		t.expect.truthy(lesson.stepDoneAt ~= nil, "string done")
		now = finishStep(lesson, now)
		-- 8 launcher: landing it (Hit with launch from us)
		now = feed(lesson, entry({ state = "Recovery" }, { { kind = "Hit", attacker = 2, target = 1, launch = true, frame = 9 } }), 1, now)
		t.expect.equal(lesson.stepDoneAt, nil, "the dummy's launcher does not count")
		now = feed(lesson, entry({ state = "Active" }, { { kind = "Hit", attacker = 1, target = 2, launch = true, frame = 10 } }), 1, now)
		t.expect.truthy(lesson.stepDoneAt ~= nil, "launcher done")
		now = finishStep(lesson, now)
		-- 9 throw
		now = feed(lesson, entry({ state = "Throw" }, { { kind = "ThrowHit", attacker = 1, target = 2, frame = 11 } }), 1, now)
		t.expect.truthy(lesson.stepDoneAt ~= nil, "throw done")
		now = finishStep(lesson, now)
		-- 10 break the dummy's throw
		now = feed(lesson, entry({ state = "Throw" }, { { kind = "ThrowBreak", attacker = 1, target = 2, frame = 12 } }), 1, now)
		t.expect.equal(lesson.stepDoneAt, nil, "the dummy escaping our throw is not our escape")
		now = feed(lesson, entry({ state = "Throw" }, { { kind = "ThrowBreak", attacker = 2, target = 1, frame = 13 } }), 1, now)
		t.expect.truthy(lesson.stepDoneAt ~= nil, "throw escape done")
		now = finishStep(lesson, now)
		t.expect.truthy(lesson.done, "lesson complete")
		local done, total = UIState.tutorialProgress(lesson)
		t.expect.equal(done, total)
	end)

	t.test("launcher also counts when performed, and a slot-2 player is tracked on slot 2", function()
		local id = Roster.order[1]
		local lesson = UIState.tutorialNew(2, id, Roster)
		lesson.index = 8
		local launcherKey = next(lesson.launchers) :: string
		UIState.tutorialObserve(lesson, entry({ state = "Active", move = launcherKey }, nil, 1), 1)
		t.expect.equal(lesson.stepDoneAt, nil, "slot 1 is the dummy here")
		UIState.tutorialObserve(lesson, entry({ state = "Active", move = launcherKey }, nil, 2), 2)
		t.expect.truthy(lesson.stepDoneAt ~= nil)
	end)

	t.test("without a 1,2 the lesson teaches the fighter's first plain button string, with its own keys", function()
		local def = { id = "Kicker", displayName = "KICKER", moveOrder = { "Jab", "LowSpin", "SpinRise", "Teep", "JabKick", "Lift" }, moves = {
			Jab = { key = "Jab", input = "LP", height = "High", tier = "Light" },
			LowSpin = { key = "LowSpin", input = "d+LK", height = "Low", tier = "Medium" },
			SpinRise = { key = "SpinRise", input = "d+LK, RK", chainFrom = "LowSpin", height = "Mid", tier = "Launch", onHit = "LAUNCH" },
			Teep = { key = "Teep", input = "LK", height = "Mid", tier = "Medium" },
			JabKick = { key = "JabKick", input = "LP, LK", chainFrom = "Jab", height = "Mid", tier = "Medium" },
			Lift = { key = "Lift", input = "df+LK", height = "Mid", tier = "Launch", onHit = "LAUNCH" },
		} }
		local fakeRoster = { has = function(x: string) return x == "Kicker" end, get = function(_x: string) return def end }
		local lesson = UIState.tutorialNew(1, "Kicker", fakeRoster)
		t.expect.truthy(lesson.strings.JabKick, "the plain 1,3 string is picked over the directional d+3,4")
		t.expect.equal(lesson.stringNotation, "1,3")
		local UIHelpers = require(Client:WaitForChild("UIHelpers"))
		local text = UIState.fillKeys(lesson.steps[7].text, "keyboard")
		t.expect.truthy(string.find(text, UIHelpers.keyLabel("fight", "lp", "keyboard") .. " then " .. UIHelpers.keyLabel("fight", "lk", "keyboard"), 1, true) ~= nil, "string text names the string's own keys: " .. text)
		local launch = UIState.fillKeys(lesson.steps[8].text, "keyboard")
		t.expect.truthy(lesson.launchers.SpinRise and lesson.launchers.Lift, "every launcher counts")
		t.expect.equal(lesson.launcherNotation, "df+3", "the lesson names the stand-alone launcher, not a string ender")
		t.expect.truthy(string.find(launch, UIHelpers.formatMoveInput("df+LK", "keyboard"), 1, true) ~= nil, "launcher text shows the keys to press: " .. launch)
		t.expect.falsy(string.find(launch, "{", 1, true))
		-- Rich text for the lesson card resolves the same placeholders.
		t.expect.falsy(string.find(LobbyUI.richKeys(lesson.steps[8].text, "keyboard"), "{input:", 1, true))
	end)

	t.test("a fighter without strings learns a two-hit combo instead", function()
		local def = { id = "Plain", displayName = "PLAIN", moveOrder = { "Jab", "Upper" }, moves = {
			Jab = { key = "Jab", input = "LP", height = "High", tier = "Light" },
			Upper = { key = "Upper", input = "df+RP", height = "Mid", tier = "Launch", onHit = "LAUNCH" },
		} }
		local fakeRoster = { has = function(x: string) return x == "Plain" end, get = function(_x: string) return def end }
		local lesson = UIState.tutorialNew(1, "Plain", fakeRoster)
		t.expect.equal(next(lesson.strings), nil)
		lesson.index = 7
		UIState.tutorialObserve(lesson, entry({ state = "Active" }, { { kind = "Hit", attacker = 1, target = 2, combo = 1, frame = 1 } }), 1)
		t.expect.equal(lesson.stepDoneAt, nil, "one hit is not a combo")
		UIState.tutorialObserve(lesson, entry({ state = "Active" }, { { kind = "Hit", attacker = 1, target = 2, combo = 2, frame = 2 } }), 2)
		t.expect.truthy(lesson.stepDoneAt ~= nil, "two linked hits complete the step")
	end)

	t.test("LobbyUI runs the lesson: dummy behaviour per step, skip, completion card", function()
		local holder = Instance.new("Folder")
		local player = Instance.new("Folder"); player:SetAttribute("DuelState", "Lobby"); player:SetAttribute("FighterId", Roster.order[1])
		local calls: { { any } } = {}
		local session: any = { _state = "Lobby" }
		function session.state() return session._state end
		function session.info() return { mode = "Training", cpu = false, authority = "Local", slot = 1 } end
		function session.practiceCommand(kind: string, arg: any) table.insert(calls, { kind, arg }) end
		local ctl = LobbyUI.mount({ player = player, parent = holder, session = session, stations = function() return nil end, world = function() return nil end, serverNow = function() return 0 end, previews = false, live = false, keyboard = true })
		local ok, err = pcall(function()
			t.expect.falsy(ctl.startLesson(), "no lesson outside practice")
			ctl.sessionChanged("Practice", { mode = "Training", cpu = false, authority = "Local", slot = 1 })
			t.expect.truthy(ctl.startLesson())
			local function dummies(): { string }
				local list = {}
				for _, c in calls do if c[1] == "Dummy" then table.insert(list, c[2]) end end
				return list
			end
			t.expect.equal(dummies()[1], "Stand", "movement steps use a standing dummy")
			local resetSeen = false
			for _, c in calls do if c[1] == "Reset" then resetSeen = true end end
			t.expect.truthy(resetSeen, "the lesson starts from reset positions")
			local card = (ctl.gui:FindFirstChild("Stage") :: any).Lesson
			t.expect.truthy(card.Visible)
			t.expect.equal(card.Content.Title.Text, "WALK")
			-- Skip to the standing-guard step: the dummy is told to fight back.
			local lesson = ctl.lesson()
			for _ = 1, 4 do
				UIState.tutorialSkip(lesson, os.clock() - 5)
				ctl.onSnapshot(entry({ state = "Idle" }))
			end
			t.expect.equal(lesson.index, 5)
			t.expect.equal(card.Content.Title.Text, "STANDING GUARD")
			local d = dummies()
			t.expect.equal(d[#d], "Fight", "guard steps need an attacking dummy")
			for _ = 1, 4 do
				UIState.tutorialSkip(lesson, os.clock() - 5)
				ctl.onSnapshot(entry({ state = "Idle" }))
			end
			t.expect.equal(lesson.index, 9)
			d = dummies()
			t.expect.equal(d[#d], "Guard", "the throw step uses a guarding dummy (throws beat guard)")
			local function resets(): number
				local count = 0
				for _, c in calls do if c[1] == "Reset" then count += 1 end end
				return count
			end
			local before = resets()
			UIState.tutorialSkip(lesson, os.clock() - 5)
			ctl.onSnapshot(entry({ state = "Idle" }))
			t.expect.equal(lesson.index, 10)
			t.expect.equal(resets(), before + 1, "the throw-break step restarts from neutral spacing (the dummy walks in to grab)")
			ctl.onSnapshot(entry({ state = "Idle" }))
			t.expect.equal(resets(), before + 1, "...once")
			for _ = 1, 1 do
				UIState.tutorialSkip(lesson, os.clock() - 5)
				ctl.onSnapshot(entry({ state = "Idle" }))
			end
			t.expect.truthy(lesson.done)
			t.expect.equal(card.Content.Title.Text, "LESSON COMPLETE")
			ctl.stopLesson()
			t.expect.equal(ctl.lesson(), nil)
			t.expect.falsy(card.Visible)
		end)
		ctl.destroy(); holder:Destroy(); player:Destroy()
		if not ok then error(err, 0) end
	end)

	-- The same lesson played against the real sim and CPU dummy: every step is reachable with the real controls.
	for _, fighterId in Roster.order do
		t.test("lesson completes against the real combat sim: " .. fighterId, function()
			local MatchRunner = require(Lab:WaitForChild("MatchRunner")) :: any
			t.expect.truthy(typeof(MatchRunner.setDummy) == "function", "OV6 MatchRunner (practice dummy) is present")
			local started = os.clock()
			local done = playLessonInSim(fighterId)
			t.expect.equal(table.concat(done, ","), "walk,dash,backdash,sidestep,standGuard,crouchGuard,string,launcher,throw,throwBreak", fighterId .. " steps completed")
			t.expect.truthy(os.clock() - started < 4, "the simulated lesson stays fast")
		end)
	end
end
