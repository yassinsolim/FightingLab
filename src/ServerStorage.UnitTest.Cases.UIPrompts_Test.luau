--!strict
-- World prompts and pickers (OV6): which E prompt is live in each lobby state, the prompts LobbyUI creates on a world's
-- kiosk / duel circles / dojo pads (restyling the world's own kiosk prompt), and the pure picker reducer.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lab = ReplicatedStorage:WaitForChild("FightingLab")
local Client = Lab:WaitForChild("Client")
local UIState = require(Client:WaitForChild("UIState"))
local UIHelpers = require(Client:WaitForChild("UIHelpers"))
local LobbyUI = require(Client:WaitForChild("LobbyUI"))
local Roster = require(Lab:WaitForChild("Roster"))
local Runner = require(game:GetService("ServerStorage").UnitTest.RunUnitTest)

local function fakeWorld(withServerKioskPrompt: boolean): Folder
	local world = Instance.new("Folder")
	world.Name = "FightingLabWorld"
	local lobby = Instance.new("Model"); lobby.Name = "Lobby"; lobby.Parent = world
	local kiosk = Instance.new("Model"); kiosk.Name = "FighterKiosk"; kiosk.Parent = lobby
	local promptPart = Instance.new("Part"); promptPart.Name = "PromptPart"; promptPart.Anchored = true; promptPart.Position = Vector3.new(30, 2, 20); promptPart.Parent = kiosk
	if withServerKioskPrompt then
		local p = Instance.new("ProximityPrompt"); p.Name = "ChooseFighter"; p.ActionText = "Choose Fighter"; p.Parent = promptPart
	end
	local arenas = Instance.new("Folder"); arenas.Name = "Arenas"; arenas.Parent = world
	local duel = Instance.new("Model"); duel.Name = "Arena_Test"; duel:SetAttribute("Kind", "Duel"); duel.Parent = arenas
	for side, name in { "PadP1", "PadP2" } do
		local pad = Instance.new("Part"); pad.Name = name; pad.Anchored = true; pad.Size = Vector3.new(0.4, 7, 7)
		pad.CFrame = CFrame.new(side * 20, 0.2, 0) * CFrame.Angles(0, 0, math.rad(90)); pad.Parent = duel
	end
	local dojo = Instance.new("Model"); dojo.Name = "Arena_Dojo"; dojo:SetAttribute("Kind", "Practice"); dojo.Parent = arenas
	for i, spec in { { "PadTraining", "Training" }, { "PadCpu", "Cpu" } } do
		local pad = Instance.new("Part"); pad.Name = spec[1]; pad.Anchored = true; pad.Size = Vector3.new(0.4, 7, 7)
		pad.CFrame = CFrame.new(-i * 20, 0.2, 40) * CFrame.Angles(0, 0, math.rad(90)); pad:SetAttribute("PadMode", spec[2]); pad.Parent = dojo
	end
	return world
end

local function promptsOn(pad: Instance): { ProximityPrompt }
	local list = {}
	for _, d in pad:GetDescendants() do if d:IsA("ProximityPrompt") then table.insert(list, d) end end
	return list
end

return function(t: Runner.T)
	t.test("prompt specs: exactly the prompt the state needs, never while an overlay is open", function()
		local lobby = UIState.lobbyView({ duelState = "Lobby" })
		local s = UIState.prompts({ view = lobby })
		t.expect.truthy(s.kiosk.enabled, "kiosk prompt in the lobby")
		t.expect.falsy(s.cpu.enabled); t.expect.falsy(s.training.enabled); t.expect.falsy(s.versus.enabled)
		t.expect.falsy(UIState.prompts({ view = lobby, overlay = true }).kiosk.enabled, "no prompts while a menu is open")
		t.expect.falsy(UIState.prompts({ view = lobby, templatesReady = false }).kiosk.enabled, "kiosk waits for the fighter templates")
		local waiting = UIState.lobbyView({ duelState = "Queued", queuedSeconds = 1 })
		t.expect.falsy(UIState.prompts({ view = waiting }).cpu.enabled, "no Fight CPU in the first seconds")
		local offer = UIState.lobbyView({ duelState = "Queued", queuedSeconds = UIState.CPU_OFFER_DELAY + 0.5 })
		local o = UIState.prompts({ view = offer, arenaId = "Arena_A", padSide = 2 })
		t.expect.truthy(o.cpu.enabled)
		t.expect.equal(o.cpu.action, "Fight CPU")
		t.expect.equal(o.cpu.arenaId, "Arena_A")
		t.expect.equal(o.cpu.side, 2)
		t.expect.falsy(UIState.prompts({ view = offer, cpuPending = true }).cpu.enabled, "no second request while one is pending")
		local training = UIState.prompts({ view = UIState.lobbyView({ practicePad = "Training" }) })
		t.expect.truthy(training.training.enabled); t.expect.falsy(training.versus.enabled)
		t.expect.equal(training.training.action, "Start Training")
		local versus = UIState.prompts({ view = UIState.lobbyView({ practicePad = "Cpu" }) })
		t.expect.truthy(versus.versus.enabled); t.expect.falsy(versus.training.enabled)
		t.expect.equal(versus.versus.action, "Versus CPU")
		for _, state in { "Countdown", "Fighting", "Practice", "Results" } do
			local v = UIState.lobbyView({ duelState = state })
			local p = UIState.prompts({ view = v })
			t.expect.falsy(p.kiosk.enabled or p.cpu.enabled or p.training.enabled or p.versus.enabled, "no lobby prompts during " .. state)
		end
	end)

	t.test("world prompts: local prompts on circles and dojo pads, kiosk restyled, E from Controls", function()
		for _, serverKiosk in { true, false } do
			local world = fakeWorld(serverKiosk)
			local wp = LobbyUI.worldPrompts(function() return world end)
			local ok, err = pcall(function()
				local lobby = UIState.lobbyView({ duelState = "Lobby" })
				wp.sync(UIState.prompts({ view = lobby }), nil, nil)
				local all = wp.all()
				local kiosk = all.kiosk
				t.expect.truthy(kiosk ~= nil, "kiosk prompt found or created")
				t.expect.equal(kiosk.Style, Enum.ProximityPromptStyle.Custom)
				t.expect.equal(kiosk.ActionText, "Choose Fighter")
				t.expect.truthy(kiosk.Enabled)
				t.expect.equal(kiosk.KeyboardKeyCode, UIHelpers.keyCodes("lobby", "interact", "keyboard")[1], "interact key from Controls")
				local count = 0
				for _ in all do count += 1 end
				t.expect.equal(count, 5, "kiosk + two circles + two dojo pads")
				local pads = (world :: any).Arenas.Arena_Test
				t.expect.equal(#promptsOn(pads.PadP1), 1)
				local cpuPrompt = promptsOn(pads.PadP2)[1]
				t.expect.equal(cpuPrompt:GetAttribute(LobbyUI.PROMPT_ATTRIBUTE), "cpu")
				t.expect.falsy(cpuPrompt.Enabled, "Fight CPU hidden in the lobby")
				-- Anchor sits above the pad centre in world space even though pads are rotated cylinders.
				local anchor = cpuPrompt.Parent :: Attachment
				t.expect.near(anchor.WorldPosition.Y, pads.PadP2.Position.Y + 3.2, 0.01)
				-- Waiting alone on P2 for long enough: only that circle's prompt lights up.
				local offer = UIState.lobbyView({ duelState = "Queued", queuedSeconds = 9, padSide = 2 })
				wp.sync(UIState.prompts({ view = offer, arenaId = "Arena_Test", padSide = 2 }), "Arena_Test", 2)
				t.expect.truthy(cpuPrompt.Enabled)
				t.expect.falsy(promptsOn(pads.PadP1)[1].Enabled)
				t.expect.falsy(kiosk.Enabled, "kiosk prompt off while queued away from it")
				local dojo = (world :: any).Arenas.Arena_Dojo
				local trainingPrompt = promptsOn(dojo.PadTraining)[1]
				t.expect.equal(trainingPrompt:GetAttribute(LobbyUI.PROMPT_ATTRIBUTE), "training")
				wp.sync(UIState.prompts({ view = UIState.lobbyView({ practicePad = "Training" }) }), nil, nil)
				t.expect.truthy(trainingPrompt.Enabled)
				t.expect.equal(trainingPrompt.ActionText, "Start Training")
				t.expect.falsy(promptsOn(dojo.PadCpu)[1].Enabled)
				-- Re-syncing never duplicates prompts.
				for _ = 1, 3 do wp.sync(UIState.prompts({ view = lobby }), nil, nil) end
				t.expect.equal(#promptsOn(dojo.PadTraining), 1)
			end)
			wp.destroy()
			local left = 0
			for _, d in world:GetDescendants() do if d:IsA("ProximityPrompt") then left += 1 end end
			t.expect.equal(left, if serverKiosk then 1 else 0, "destroy removes our prompts and keeps the world's")
			world:Destroy()
			if not ok then error(err, 0) end
		end
	end)

	t.test("picker reducer: cpu, training and versus rows, mouse and keys", function()
		local p = UIState.pickerNew("cpu", { difficulty = "Normal" })
		t.expect.equal(UIState.pickerValue(p, "difficulty"), "Normal")
		p = UIState.pickerAction(p, "Right")
		t.expect.equal(UIState.pickerValue(p, "difficulty"), "Hard")
		p = UIState.pickerAction(p, "Right")
		t.expect.equal(UIState.pickerValue(p, "difficulty"), "Hard", "difficulty does not wrap")
		p = UIState.pickerAction(p, "Up")
		t.expect.equal(UIState.pickerValue(p, "difficulty"), "Normal", "up/down also move along the cards")
		p = UIState.pickerAction(p, "Confirm")
		t.expect.truthy(p.done)
		t.expect.equal(p.result and p.result.request, "RequestCpu")
		t.expect.equal(p.result and p.result.difficulty, "Normal")
		local tr = UIState.pickerNew("training", { fighters = Roster.order, opponent = Roster.order[2] })
		t.expect.equal(tr.rows[tr.focus].id, "start", "dojo pickers start on the START button")
		tr = UIState.pickerAction(tr, "Up")
		tr = UIState.pickerAction(tr, "Right")
		t.expect.equal(UIState.pickerValue(tr, "lesson"), "Lesson")
		tr = UIState.pickerAction(tr, "Up")
		tr = UIState.pickerAction(tr, "Left")
		t.expect.equal(UIState.pickerValue(tr, "opponent"), Roster.order[1], "opponent cycles")
		tr = UIState.pickerAction(tr, "Left")
		t.expect.equal(UIState.pickerValue(tr, "opponent"), Roster.order[#Roster.order], "opponent wraps")
		local early = UIState.pickerAction(tr, "Confirm")
		t.expect.truthy(early.done, "Enter starts from any row (values are already picked with the arrows)")
		t.expect.equal(early.result and early.result.opponent, Roster.order[#Roster.order])
		tr = UIState.pickerAction(tr, "Go:start")
		t.expect.truthy(tr.done)
		t.expect.equal(tr.result and tr.result.mode, "Training")
		t.expect.equal(tr.result and tr.result.lesson, true)
		local vs = UIState.pickerNew("versus", { fighters = Roster.order, opponent = Roster.order[3], difficulty = "Easy" })
		vs = UIState.pickerAction(vs, "Set:difficulty:3")
		t.expect.equal(vs.rows[vs.focus].id, "difficulty", "mouse picks focus the row")
		vs = UIState.pickerAction(vs, "Back")
		t.expect.truthy(vs.cancelled)
		vs = UIState.pickerAction(vs, "Confirm")
		t.expect.falsy(vs.done, "a cancelled picker ignores input")
	end)
end
