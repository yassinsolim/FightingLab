--!strict
-- Practice tools (round 7): the input display rows, the frame advantage readout, combo trials against a Contract C
-- stub (list / steps lighting / failure reasons / success / SHOW ME timing / a missing module), and SHOW ME through a
-- real practice MatchRunner with the real ComboTrial: the demo, played by the tools, clears the trial.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lab = ReplicatedStorage:WaitForChild("FightingLab")
local Client = Lab:WaitForChild("Client")
local PracticeTools = require(Client:WaitForChild("PracticeTools"))
local MatchRunner = require(Lab:WaitForChild("MatchRunner"))
local RenderBuffer = require(Lab:WaitForChild("RenderBuffer"))

-- A ComboTrial-shaped stub (Contract C API): feed() follows a scripted list of statuses.
local function stubTrialModule(): any
	local mod: any = { fed = 0, script = {} :: { any }, demos = 0 }
	local combos = {
		{ index = 1, name = "Jab Bread", notation = "1, 2", difficulty = 1, damage = 12, kind = "launch", counter = false, surge = false,
			steps = { { label = "Jab", notation = "1", move = "Jab" }, { label = "Cross", notation = "2", move = "Cross" } } },
		{ index = 2, name = "Uppercut Launch", notation = "df+2, 1, 2", difficulty = 3, damage = 30, kind = "launch", counter = false, surge = false,
			steps = { { label = "Uppercut", notation = "df+2", move = "Upper" }, { label = "Jab", notation = "1", move = "Jab" }, { label = "Cross", notation = "2", move = "Cross" } } },
	}
	function mod.list(_id: string) return combos end
	function mod.new(id: string, index: number)
		local trial: any = { characterId = id, index = index, info = combos[index], state = "Ready", step = 0, reason = nil, damage = 0 }
		function trial:status() return { state = self.state, step = self.step, total = #self.info.steps, reason = self.reason, damage = self.damage } end
		function trial:reset() self.state = "Ready"; self.step = 0; self.reason = nil; self.damage = 0 end
		function trial:feed(_entry: any)
			mod.fed += 1
			local nextStatus = table.remove(mod.script, 1)
			if nextStatus then
				self.state, self.step, self.reason, self.damage = nextStatus.state, nextStatus.step, nextStatus.reason, nextStatus.damage or self.damage
			end
			return self:status()
		end
		return trial
	end
	function mod.demo(_id: string, _index: number)
		mod.demos += 1
		return {
			{ frame = 0, hold = { moveX = 1, moveZ = 0, crouch = false } },
			{ frame = 12, hold = { moveX = 0, moveZ = 0, crouch = false } },
			{ frame = 30, hold = { moveX = 1, moveZ = 0, crouch = true } },
			{ frame = 30, press = "RearPunch", step = 1, notation = "df+2" },
			{ frame = 31, hold = { moveX = 0, moveZ = 0, crouch = false } },
			{ frame = 60, press = "LeadPunch", step = 2, notation = "1" },
		}
	end
	return mod
end

local function entry(frame: number, extra: { [string]: any }?): any
	local e: any = {
		frame = frame, epoch = 1, paused = false, hitstop = 0, events = {},
		fighters = { { characterId = "Kael", state = "Idle" }, { characterId = "Sierra", state = "Idle" } },
	}
	for k, v in extra or {} do e[k] = v end
	return e
end

type Mounted = { tools: any, holder: Folder, commands: { any }, sends: { any }, now: { t: number }, log: { any }, destroy: () -> () }
local function mountTools(mod: any?, practice: boolean?): Mounted
	local holder = Instance.new("Folder")
	local commands, sends, log = {}, {}, {}
	local now = { t = 100 }
	local inPractice = if practice == nil then true else practice
	local tools = PracticeTools.mount({
		parent = holder, live = false, device = function() return "keyboard" end, clock = function() return now.t end,
		practice = function() return inPractice end, versus = function() return false end, fighter = function() return "Kael" end,
		command = function(kind: string, arg: any?) table.insert(commands, { kind, arg }) end,
		send = function(kind: string, a: any?, b: any?) table.insert(sends, { kind, a, b }) end,
		inputLog = function() return log end,
		comboTrial = mod,
	})
	return { tools = tools, holder = holder, commands = commands, sends = sends, now = now, log = log, destroy = function() tools.destroy(); holder:Destroy() end }
end
local function lastCommand(m: Mounted, kind: string): any
	for i = #m.commands, 1, -1 do if m.commands[i][1] == kind then return m.commands[i] end end
	return nil
end

return function(t)
	t.test("input display: newest first, notation icons and the frames since the previous input", function()
		local log = {
			{ text = "4", t = 10 + 3 / 60 }, { text = "3", t = 10 + 2 / 60 }, { text = "SS in", t = 10 },
			{ text = "f", t = 10 - 30 / 60 }, { text = "1", t = 10 - 300 / 60 },
		}
		local rows = PracticeTools.inputRows(log)
		t.expect.equal(#rows, 5)
		t.expect.equal(rows[1].input, "4")
		t.expect.equal(rows[1].gap, 1, "3 then 4 one frame apart: a chord")
		t.expect.equal(rows[2].gap, 2)
		t.expect.equal(rows[3].input, "u", "a sidestep in is an up arrow")
		t.expect.equal(rows[3].tag, "STEP")
		t.expect.equal(rows[3].gap, 30)
		t.expect.equal(rows[4].gap, nil, "a long pause starts a new sequence")
		t.expect.equal(rows[5].gap, nil, "the oldest has nothing before it")
		local many = {}
		for i = 1, 15 do table.insert(many, { text = "1", t = 100 - i / 60 }) end
		t.expect.equal(#PracticeTools.inputRows(many), PracticeTools.INPUT_ROWS, "the last 10 only")
	end)

	t.test("frame advantage: the sim's numbers from the player's side; launchers and knockdowns are words", function()
		local e = entry(1)
		local hit = PracticeTools.readout({ kind = "Hit", attacker = 1, target = 2, move = "Jab", advantage = 8 }, 1, e) :: any
		t.expect.equal(hit.value, 8)
		t.expect.equal(PracticeTools.formatValue(hit), "+8")
		t.expect.equal(hit.caption, "ON HIT")
		local block = PracticeTools.readout({ kind = "Block", attacker = 1, target = 2, move = "Jab", advantage = -12 }, 1, e) :: any
		t.expect.equal(block.value, -12)
		t.expect.equal(block.caption, "ON BLOCK")
		t.expect.falsy(block.plus)
		local theirs = PracticeTools.readout({ kind = "Block", attacker = 2, target = 1, move = "Jab", advantage = -14 }, 1, e) :: any
		t.expect.equal(theirs.value, 14, "you blocked their -14: you are +14")
		t.expect.truthy(string.find(theirs.caption, "THEIRS", 1, true) ~= nil)
		local launch = PracticeTools.readout({ kind = "Hit", attacker = 1, target = 2, launch = true, advantage = 0 }, 1, e) :: any
		t.expect.equal(PracticeTools.formatValue(launch), "LAUNCH")
		local down = PracticeTools.readout({ kind = "Hit", attacker = 1, target = 2, knockdown = true, advantage = 0 }, 1, e) :: any
		t.expect.equal(PracticeTools.formatValue(down), "DOWN")
		t.expect.equal(PracticeTools.readout({ kind = "Hit", attacker = 1, target = 2, air = true }, 1, e), nil, "juggle hits")
		t.expect.equal(PracticeTools.readout({ kind = "Whiff", attacker = 1, target = 2 }, 1, e), nil)
		t.expect.equal(PracticeTools.formatValue({ value = 0, caption = "", move = "", plus = true }), "±0")
		-- Mounted: shown only when switched on, then fades.
		local m = mountTools(stubTrialModule())
		local ok, err = pcall(function()
			local frames = m.holder:FindFirstChild("Frames", true) :: Frame
			m.tools.onSnapshot(entry(2, { events = { { kind = "Block", attacker = 1, target = 2, move = "Jab", advantage = -12 } } }))
			t.expect.falsy(frames.Visible, "off by default")
			m.tools.setFrames(true)
			m.tools.onSnapshot(entry(3, { events = { { kind = "Block", attacker = 1, target = 2, move = "Jab", advantage = -12 } } }))
			t.expect.truthy(frames.Visible)
			t.expect.equal((frames :: any).Value.Text, "−12")
			t.expect.truthy(string.find((frames :: any).Caption.Text, "PUNISHABLE", 1, true) ~= nil)
			m.now.t += PracticeTools.FRAME_SECONDS + 0.1
			m.tools.tick(0.1)
			t.expect.falsy(frames.Visible, "fades after a few seconds")
		end)
		m.destroy()
		if not ok then error(err, 0) end
	end)

	t.test("combo trials (Contract C stub): pick, steps light up, failure names the reason and resets, success celebrates", function()
		local mod = stubTrialModule()
		local m = mountTools(mod)
		local ok, err = pcall(function()
			local tools = m.tools
			t.expect.truthy(tools.available())
			t.expect.truthy(tools.openTrials())
			t.expect.truthy(tools.modalOpen())
			t.expect.truthy(tools.inputBlocked(), "gameplay input is off while choosing")
			local trials = m.holder:FindFirstChild("Trials", true) :: Frame
			t.expect.truthy(trials.Visible)
			t.expect.truthy(trials:FindFirstChild("Combo2", true) ~= nil, "every listed combo is a row")
			t.expect.truthy(tools.handleNav("Down"))
			t.expect.truthy(tools.handleNav("Confirm"))
			t.expect.falsy(tools.modalOpen())
			t.expect.equal(tools.trialIndex(), 2)
			t.expect.equal(lastCommand(m, "Dummy")[2], "Stand", "a standing dummy")
			t.expect.truthy(lastCommand(m, "Reset") ~= nil, "from the start distance")
			t.expect.truthy(tools.inputsOn(), "the input display comes on for trials")
			local card = m.holder:FindFirstChild("Trial", true) :: Frame
			t.expect.truthy(card.Visible)
			local steps = card:FindFirstChild("Steps", true) :: Frame
			t.expect.truthy(steps:FindFirstChild("Step3") ~= nil, "the steps in a vertical list")
			-- Step 1 lands, then 2: they light up.
			mod.script = { { state = "Running", step = 1, damage = 14 }, { state = "Running", step = 2, damage = 20 } }
			tools.onSnapshot(entry(10))
			tools.onSnapshot(entry(11))
			t.expect.equal(tools.status().step, 2)
			local step1 = steps:FindFirstChild("Step1", true) :: any
			t.expect.equal(step1.Dot.Num.Text, "✓")
			t.expect.equal((steps:FindFirstChild("Step3", true) :: any).Dot.Num.Text, "3")
			-- Too late: the reason in plain words, then a reset for the next attempt.
			mod.script = { { state = "Failed", step = 2, reason = "Late", damage = 20 } }
			local resets = 0
			for _, c in m.commands do if c[1] == "Reset" then resets += 1 end end
			tools.onSnapshot(entry(12))
			local banner = m.holder:FindFirstChild("Banner", true) :: any
			t.expect.truthy(banner.Visible)
			t.expect.equal(banner.Title.Text, "TOO LATE")
			t.expect.truthy(string.find((card:FindFirstChild("Status", true) :: TextLabel).Text, "TOO LATE", 1, true) ~= nil)
			m.now.t += PracticeTools.FAIL_SECONDS + 0.05
			tools.tick(0.05)
			local after = 0
			for _, c in m.commands do if c[1] == "Reset" then after += 1 end end
			t.expect.equal(after, resets + 1, "positions reset after the failure")
			t.expect.equal(tools.status().state, "Ready", "and the trial is ready again")
			for reason, words in PracticeTools.REASONS do
				t.expect.truthy(words[1] ~= "" and words[2] ~= "", reason .. " has plain words")
			end
			t.expect.equal(PracticeTools.REASONS.Whiffed[1], "MISSED")
			t.expect.equal(PracticeTools.REASONS.Early[1], "TOO EARLY")
			t.expect.equal(PracticeTools.REASONS.Wrong[1], "WRONG MOVE")
			t.expect.equal(PracticeTools.REASONS.Blocked[1], "BLOCKED")
			-- Success: COMBO CLEAR! and the combo is marked cleared.
			mod.script = { { state = "Running", step = 1 }, { state = "Running", step = 2 }, { state = "Success", step = 3, damage = 31 } }
			tools.onSnapshot(entry(20)); tools.onSnapshot(entry(21)); tools.onSnapshot(entry(22))
			t.expect.equal(banner.Title.Text, "COMBO CLEAR!")
			t.expect.truthy(string.find(banner.Sub.Text, "31", 1, true) ~= nil, "with the damage")
			tools.openTrials()
			t.expect.truthy((trials:FindFirstChild("Combo2", true) :: any).Cleared.Visible, "cleared this session")
			t.expect.truthy(tools.handleNav("Back"))
			t.expect.falsy(tools.modalOpen())
			-- Pausing during a trial opens the list (keyboard / gamepad way in).
			tools.onSnapshot(entry(30, { paused = true }))
			t.expect.truthy(tools.modalOpen())
			tools.handleNav("Back")
			t.expect.equal(lastCommand(m, "Pause")[2], false, "closing the list resumes")
			tools.endTrial()
			t.expect.falsy(card.Visible)
			t.expect.falsy(tools.inputsOn(), "the input display goes back off")
		end)
		m.destroy()
		if not ok then error(err, 0) end
	end)

	t.test("SHOW ME plays the demo script frame by frame (hold first, then press), with player input off", function()
		local mod = stubTrialModule()
		local m = mountTools(mod)
		local ok, err = pcall(function()
			local tools = m.tools
			tools.startTrial(2)
			table.clear(m.sends)
			t.expect.truthy(tools.showMe())
			t.expect.truthy(tools.demoPlaying())
			t.expect.truthy(tools.inputBlocked(), "the player's input is off during the demo")
			t.expect.equal(lastCommand(m, "Dummy")[2], "Stand")
			t.expect.equal(m.sends[1][1], "Move", "frame 0 is applied right after the reset")
			t.expect.equal(m.sends[1][2], 1)
			local at: { [number]: { any } } = {}
			for frame = 1, 70 do
				local before = #m.sends
				tools.onSnapshot(entry(frame, { epoch = 2 }))
				at[frame] = table.move(m.sends, before + 1, #m.sends, 1, {})
			end
			t.expect.equal(at[12][1][1], "Move", "frame 12: let go")
			t.expect.equal(at[12][1][2], 0)
			local f30 = at[30]
			t.expect.equal(f30[1][1], "Move", "hold before press")
			t.expect.equal(f30[2][1], "Crouch")
			t.expect.equal(f30[2][2], true)
			t.expect.equal(f30[3][1], "Attack")
			t.expect.equal(f30[3][2], "RearPunch")
			t.expect.equal(at[60][1][2], "LeadPunch")
			for frame = 71, 70 + PracticeTools.DEMO_TAIL + 2 do tools.onSnapshot(entry(frame, { epoch = 2 })) end
			t.expect.falsy(tools.demoPlaying(), "ends after its tail")
			t.expect.falsy(tools.inputBlocked())
			-- Without the module nothing breaks: trials are simply not offered.
			local bare = mountTools(false)
			local ok2, err2 = pcall(function()
				t.expect.falsy(bare.tools.available())
				t.expect.truthy(bare.tools.openTrials(), "the list still opens")
				local empty = bare.holder:FindFirstChild("Empty", true) :: TextLabel
				t.expect.truthy(empty.Visible and string.find(empty.Text, "not installed", 1, true) ~= nil, "and says why")
				t.expect.falsy(bare.tools.startTrial(1))
				t.expect.falsy(bare.tools.showMe())
				bare.tools.onSnapshot(entry(1, { events = { { kind = "Hit", attacker = 1, target = 2, advantage = 3 } } }))
			end)
			bare.destroy()
			if not ok2 then error(err2, 0) end
		end)
		m.destroy()
		if not ok then error(err, 0) end
	end)

	t.test("with the real ComboTrial: SHOW ME through a practice MatchRunner clears every standing combo of all six fighters", function()
		local mod = PracticeTools.comboTrialModule()
		if not mod then
			-- Contract C not merged in this build: the tools must still mount and offer nothing.
			local m = mountTools(false)
			t.expect.falsy(m.tools.available())
			m.destroy()
			return
		end
		local Roster = require(Lab:WaitForChild("Roster"))
		local checked = 0
		for _, id in Roster.order do
			for index, info in mod.list(id) do
				-- Counter routes need the dummy attacking under the opener: their demo only shows the inputs.
				if not info.counter then
					local runner = MatchRunner.new()
					runner:configure({ mode = "Training", p1Id = id, p2Id = "Sierra", stageId = "TrainingBay", human1 = true, human2 = false })
					local holder = Instance.new("Folder")
					local tools = PracticeTools.mount({
						parent = holder, live = false, device = function() return "keyboard" end,
						practice = function() return true end, versus = function() return false end, fighter = function() return id end,
						command = function(kind: string, arg: any?)
							if kind == "Reset" then runner:command("Reset", nil, nil, 1)
							elseif kind == "Dummy" then runner:command("Dummy", arg, nil, 1)
							elseif kind == "Pause" then runner:command("Pause", arg == true, nil, 1) end
						end,
						send = function(kind: string, a: any?, b: any?) runner:command(kind, a, b, 1) end,
						inputLog = function() return {} end,
					})
					local ok, err = pcall(function()
						t.expect.truthy(tools.startTrial(index))
						t.expect.truthy(tools.showMe())
						for _ = 1, 1500 do
							tools.onSnapshot(RenderBuffer.parse(runner:step()))
							if not tools.demoPlaying() then break end
						end
						t.expect.falsy(tools.demoPlaying(), id .. " " .. info.name .. ": the demo ends")
						t.expect.equal(tools.demoResult(), "Success", id .. " " .. info.name .. ": the demo played by the tools completes the trial")
						t.expect.falsy(tools.cleared(index), "a demo never counts as the player's clear")
						t.expect.equal(tools.status().state, "Ready", "then the trial is ready for the player")
					end)
					tools.destroy(); holder:Destroy()
					if not ok then error(err, 0) end
					checked += 1
				end
			end
		end
		t.expect.truthy(checked >= 12, "every fighter has standing combos to show: " .. checked)
	end, { timeout = 20 })
end
