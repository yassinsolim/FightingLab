--!strict
-- Controls-driven labels (OV6): every key the UI shows comes from ReplicatedStorage.FightingLab.Controls — prompts,
-- the practice panel, the How to Play page, the fight HUD guide, lesson texts — and move notation is numeric (1-4).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lab = ReplicatedStorage:WaitForChild("FightingLab")
local Client = Lab:WaitForChild("Client")
local UIState = require(Client:WaitForChild("UIState"))
local UIHelpers = require(Client:WaitForChild("UIHelpers"))
local LobbyUI = require(Client:WaitForChild("LobbyUI"))
local MoveList = require(Client:WaitForChild("MoveList"))
local Hud = require(Client:WaitForChild("HudController"))
local Roster = require(Lab:WaitForChild("Roster"))
local Runner = require(game:GetService("ServerStorage").UnitTest.RunUnitTest)

local FIGHT = { "forward", "back", "sidestepIn", "sidestepOut", "crouch", "lp", "rp", "lk", "rk", "throw", "guide" }
local PRACTICE = { "reset", "switchMode", "easy", "normal", "hard", "dummy", "pause", "leave" }
local LOBBY = { "interact", "menu", "jump", "play", "fighters", "sprint" }

local function hasGlyph(root: Instance, label: string): boolean
	for _, d in root:GetDescendants() do
		if d.Name == "Key_" .. label then return true end
	end
	return false
end

return function(t: Runner.T)
	t.test("every label the UI shows matches FightingLab.Controls", function()
		local module = Lab:FindFirstChild("Controls")
		t.expect.truthy(module ~= nil, "ReplicatedStorage.FightingLab.Controls exists")
		local Controls = require(module :: ModuleScript) :: any
		t.expect.falsy(UIHelpers.usingFallbackControls(), "the UI reads the live Controls module")
		for group, actions in { fight = FIGHT, practice = PRACTICE, lobby = LOBBY } do
			for _, action in actions do
				local label = UIHelpers.keyLabel(group, action, "keyboard")
				t.expect.truthy(label ~= "", group .. "." .. action .. " has a keyboard label")
				if typeof(Controls.label) == "function" then
					t.expect.equal(label, Controls.label(group, action, "keyboard"), group .. "." .. action)
				end
				t.expect.truthy(#UIHelpers.keyCodes(group, action, "keyboard") >= 1, group .. "." .. action .. " has a KeyCode")
			end
		end
		-- §2 defaults, so a regression in either module is caught.
		t.expect.equal(UIHelpers.keyLabel("lobby", "interact"), "E")
		t.expect.equal(UIHelpers.keyLabel("fight", "lp"), "U")
		t.expect.equal(UIHelpers.keyLabel("practice", "leave"), "BACKSPACE")
	end)

	t.test("prompt, lobby hint and lesson texts use the Controls labels", function()
		local interact = UIHelpers.keyLabel("lobby", "interact", "keyboard")
		local v = UIState.lobbyView({ duelState = "Queued", queuedSeconds = 99, interactKey = interact })
		t.expect.truthy(string.find(v.offer, "Press " .. interact, 1, true) ~= nil)
		t.expect.equal(UIState.fillKeys("{fight.forward}/{fight.back}"), UIHelpers.keyLabel("fight", "forward") .. "/" .. UIHelpers.keyLabel("fight", "back"))
		t.expect.truthy(string.find(LobbyUI.richKeys("Press {fight.throw}"), UIHelpers.keyLabel("fight", "throw"), 1, true) ~= nil)
		-- The custom prompt billboard shows the interact glyph.
		local part = Instance.new("Part")
		local prompt = Instance.new("ProximityPrompt"); prompt.ActionText = "Fight CPU"; prompt.ObjectText = "No challenger yet"
		prompt:SetAttribute(LobbyUI.PROMPT_ATTRIBUTE, "cpu"); prompt.Parent = part
		local holder = Instance.new("Folder")
		local cleanup = LobbyUI.PromptStyle.build(prompt, holder, "keyboard")
		local gui = holder:FindFirstChild("FightingLabPrompt")
		t.expect.truthy(gui ~= nil)
		t.expect.truthy(gui and hasGlyph(gui, interact), "prompt glyph is the interact key")
		t.expect.equal(gui and (gui :: any).Pill.Action.Text, "FIGHT CPU")
		cleanup()
		t.expect.equal(#holder:GetChildren(), 0)
		local padGui = LobbyUI.PromptStyle.build(prompt, holder, "gamepad")
		t.expect.truthy(hasGlyph(holder, UIHelpers.keyLabel("lobby", "interact", "gamepad")), "gamepad glyph")
		padGui()
		holder:Destroy(); part:Destroy()
	end)

	t.test("practice panel and How to Play page draw their key caps from Controls", function()
		local holder = Instance.new("Folder")
		local player = Instance.new("Folder"); player:SetAttribute("DuelState", "Lobby"); player:SetAttribute("FighterId", "Kael")
		local session: any = { _state = "Lobby" }
		function session.state() return session._state end
		function session.info() return nil end
		function session.practiceCommand() end
		local ctl = LobbyUI.mount({ player = player, parent = holder, session = session, stations = function() return nil end, world = function() return nil end, serverNow = function() return 0 end, previews = false, live = false, keyboard = true })
		local ok, err = pcall(function()
			ctl.sessionChanged("Practice", { mode = "Training", authority = "Local", slot = 1 })
			local panel = (ctl.gui:FindFirstChild("Stage") :: any).PracticePanel
			for _, action in { "reset", "switchMode", "easy", "normal", "hard", "dummy", "pause", "leave" } do
				t.expect.truthy(hasGlyph(panel, UIHelpers.keyLabel("practice", action)), "practice panel shows " .. action)
			end
			t.expect.truthy(hasGlyph(panel, UIHelpers.keyLabel("fight", "guide")), "practice panel shows the guide key")
			ctl.sessionChanged("Lobby", nil)
			ctl.openMenu("HowToPlay")
			local page = (holder :: any).FightingLabLobbyMenu.Stage.Body.Panel.Content.Page_HowToPlay
			for _, action in FIGHT do
				t.expect.truthy(hasGlyph(page, UIHelpers.keyLabel("fight", action)), "How to Play shows fight." .. action)
			end
			for _, action in { "interact", "jump", "play", "fighters", "sprint" } do
				t.expect.truthy(hasGlyph(page, UIHelpers.keyLabel("lobby", action)), "How to Play shows lobby." .. action)
			end
		end)
		ctl.destroy(); holder:Destroy(); player:Destroy()
		if not ok then error(err, 0) end
	end)

	-- Nothing about the practice keys is written in the UI: rebinding or renaming an action in Controls changes the
	-- practice panel, its key handling and the How to Play card, and no stale label (like an old "K sparring") remains.
	t.test("practice panel and How to Play follow Controls.legend: a rebound, renamed scheme leaves no stale label", function()
		local KEY_TEXT: { [string]: string } = { Seven = "7", Eight = "8", Nine = "9", Delete = "DEL" }
		local fake: any = {
			fight = { keyboard = { forward = "D", back = "A", sidestepIn = "W", sidestepOut = "S", crouch = "S", lp = "U", rp = "I", lk = "J", rk = "K", throw = "O", guide = "G" }, gamepad = {} },
			practice = { keyboard = { reset = "F", switchMode = "M", easy = "Seven", normal = "Eight", hard = "Nine", dummy = "Q", pause = "L", leave = "Delete" }, gamepad = {} },
			lobby = { keyboard = { interact = "E", menu = "Tab", jump = "Space" }, gamepad = {} },
			notation = { lp = "1", rp = "2", lk = "3", rk = "4" },
			actionText = {
				reset = "Restart the round", switchMode = "Drill / Match", easy = "AI Easy", normal = "AI Normal", hard = "AI Hard",
				dummy = "Partner: idle / block / attack", pause = "Freeze", leave = "Exit the dojo", guide = "Key guide",
			},
		}
		local ORDER = { practice = { "reset", "switchMode", "easy", "normal", "hard", "dummy", "pause", "leave" }, lobby = { "interact", "menu", "jump" } }
		function fake.label(group: string, action: string, device: string?): string
			local d = fake[group] and fake[group][device or "keyboard"]
			local v = d and d[action]
			return if v then (KEY_TEXT[v] or string.upper(v)) else ""
		end
		function fake.keyCodes(group: string, action: string, device: string?): { Enum.KeyCode }
			local d = fake[group] and fake[group][device or "keyboard"]
			local v = d and d[action]
			return if v then { (Enum.KeyCode :: any)[v] } else {}
		end
		function fake.legend(group: string, device: string?): { any }
			local rows = {}
			for _, action in ORDER[group] or {} do
				local keys = fake.label(group, action, device)
				if keys ~= "" then table.insert(rows, { action = action, keys = keys, text = fake.actionText[action] or action }) end
			end
			return rows
		end
		local function texts(root: Instance): string
			local out = {}
			for _, d in root:GetDescendants() do if d:IsA("TextLabel") or d:IsA("TextButton") then table.insert(out, (d :: any).Text) end end
			return table.concat(out, " | ")
		end
		UIHelpers._setControlsForTests(fake)
		local holder = Instance.new("Folder")
		local player = Instance.new("Folder"); player:SetAttribute("DuelState", "Lobby"); player:SetAttribute("FighterId", "Kael")
		local calls: { { any } } = {}
		local inPractice = false
		local session: any = { _state = "Lobby" }
		function session.state() return session._state end
		function session.info() return if inPractice then { mode = "Training", cpu = false, authority = "Local", slot = 1 } else nil end
		function session.practiceCommand(kind: string, arg: any) table.insert(calls, { kind, arg }); return true end
		function session.leave() table.insert(calls, { "leave" }) end
		local ok, err = pcall(function()
			local ctl = LobbyUI.mount({ player = player, parent = holder, session = session, stations = function() return nil end, world = function() return nil end, serverNow = function() return 0 end, previews = false, live = false, keyboard = true })
			inPractice = true
			ctl.sessionChanged("Practice", { mode = "Training", cpu = false, authority = "Local", slot = 1 })
			local panel = (ctl.gui:FindFirstChild("Stage") :: any).PracticePanel
			for _, key in { "F", "M", "7", "8", "9", "Q", "L", "DEL" } do t.expect.truthy(hasGlyph(panel, key), "panel shows the rebound key " .. key) end
			for _, stale in { "R", "T", "1", "2", "3", "Y", "P", "BACKSPACE" } do t.expect.falsy(hasGlyph(panel, stale), "no stale key " .. stale) end
			local all = texts(panel)
			for _, caption in { "RESTART THE ROUND", "DRILL", "MATCH", "AI", "EASY", "NORMAL", "HARD", "PARTNER", "IDLE", "BLOCK", "ATTACK", "FREEZE", "EXIT THE DOJO", "KEY GUIDE" } do
				t.expect.truthy(string.find(all, caption, 1, true) ~= nil, "panel caption from Controls: " .. caption)
			end
			for _, stale in { "SPAR", "RESET POSITIONS", "LEAVE PRACTICE", "FIGHT BACK" } do
				t.expect.falsy(string.find(all, stale, 1, true), "no hard-coded label: " .. stale)
			end
			t.expect.equal(panel.Header.Mode.Text, "DRILL", "the mode chip uses the legend's mode names")
			t.expect.equal(panel.Switch.ModeTraining.Row.Label.Text, "DRILL")
			-- The folded strip is legend-driven too: a (rebound) fight key folds the panel, the strip shows the renamed
			-- mode and dummy texts and the rebound pause key with its renamed action.
			t.expect.falsy(ctl.handleKey(Enum.KeyCode.D), "fight keys are not consumed")
			t.expect.falsy(ctl.panelOpen(), "a fight key folds the panel")
			local strip = (ctl.gui:FindFirstChild("Stage") :: any).PracticeStrip
			t.expect.truthy(strip.Visible)
			local stripText = texts(strip)
			for _, caption in { "DRILL", "PARTNER", "IDLE", "FREEZE" } do
				t.expect.truthy(string.find(stripText, caption, 1, true) ~= nil, "strip caption from Controls: " .. caption)
			end
			t.expect.truthy(hasGlyph(strip, "L"), "strip shows the rebound pause key")
			t.expect.falsy(hasGlyph(strip, "P") or string.find(stripText, "PAUSE", 1, true) ~= nil, "no stale pause key or text")
			-- Key handling follows the rebinding too (LobbyUI owns switch / difficulty / leave).
			t.expect.falsy(ctl.handleKey(Enum.KeyCode.T), "T no longer switches")
			t.expect.truthy(ctl.handleKey(Enum.KeyCode.M), "M switches")
			t.expect.truthy(ctl.handleKey(Enum.KeyCode.Nine), "9 picks Hard")
			local sawMode, sawHard = false, false
			for _, c in calls do
				if c[1] == "SetMode" then sawMode = true end
				if c[1] == "Difficulty" and c[2] == "Hard" then sawHard = true end
			end
			t.expect.truthy(sawMode and sawHard, "rebound keys drive the session")
			inPractice = false
			ctl.sessionChanged("Lobby", nil)
			ctl.openMenu("HowToPlay")
			local page = (holder :: any).FightingLabLobbyMenu.Stage.Body.Panel.Content.Page_HowToPlay
			local practiceCard = page:FindFirstChild("Practice", true)
			t.expect.truthy(practiceCard ~= nil)
			local cardText = texts(practiceCard :: Instance)
			for _, caption in { "Restart the round", "Drill / Match", "AI Easy / Normal / Hard", "Partner: idle / block / attack", "Freeze", "Exit the dojo" } do
				t.expect.truthy(string.find(cardText, caption, 1, true) ~= nil, "How to Play line from Controls: " .. caption)
			end
			for _, key in { "F", "M", "7", "8", "9", "Q", "L", "DEL" } do t.expect.truthy(hasGlyph(practiceCard :: Instance, key), "How to Play shows " .. key) end
			t.expect.falsy(string.find(string.upper(cardText), "SPAR", 1, true), "no sparring text")
			ctl.destroy()
		end)
		UIHelpers._setControlsForTests(nil)
		holder:Destroy(); player:Destroy()
		if not ok then error(err, 0) end
	end)

	t.test("fight HUD controls guide is built from Controls", function()
		local gui = Instance.new("ScreenGui")
		local holder = Instance.new("Folder"); gui.Parent = holder
		Hud.init({ gui = gui, modules = {} })
		Hud._resetForTests()
		Hud.setGuide(true)
		local guide = (gui :: any).FightHud.Stage.ControlsGuide
		for _, action in FIGHT do
			t.expect.truthy(hasGlyph(guide, UIHelpers.keyLabel("fight", action)), "guide shows fight." .. action)
		end
		Hud.setGuide(false)
		holder:Destroy()
	end)

	-- Every row of Controls.legend (the combat agent's list of the whole scheme) has its keys on screen: the fight rows
	-- in the in-fight guide, the practice rows on the practice panel, the lobby rows on the How to Play page.
	t.test("every Controls.legend key is shown: fight guide, practice panel, How to Play", function()
		local module = Lab:FindFirstChild("Controls")
		local Controls = if module then require(module :: ModuleScript) :: any else nil
		if not Controls or typeof(Controls.legend) ~= "function" then
			t.expect.truthy(UIHelpers.usingFallbackControls(), "without Controls.legend the UI must be on its fallback table")
			return
		end
		local function tokens(keys: string): { string }
			local out = {}
			local cleaned = string.gsub(string.gsub(keys, "%(%a+%)", ""), "[%+/]", " ")
			for token in string.gmatch(cleaned, "%S+") do table.insert(out, token) end
			return out
		end
		local gui = Instance.new("ScreenGui")
		local hudHolder = Instance.new("Folder"); gui.Parent = hudHolder
		Hud.init({ gui = gui, modules = {} })
		Hud._resetForTests()
		Hud.setGuide(true)
		local guide = (gui :: any).FightHud.Stage.ControlsGuide
		for _, row in Controls.legend("fight", "keyboard") do
			for _, key in tokens(row.keys) do t.expect.truthy(hasGlyph(guide, key), "guide shows " .. row.action .. " key " .. key) end
		end
		Hud.setGuide(false)
		hudHolder:Destroy()
		local holder = Instance.new("Folder")
		local player = Instance.new("Folder"); player:SetAttribute("DuelState", "Lobby"); player:SetAttribute("FighterId", "Kael")
		local session: any = { _state = "Lobby" }
		function session.state() return session._state end
		function session.info() return nil end
		function session.practiceCommand() end
		local ctl = LobbyUI.mount({ player = player, parent = holder, session = session, stations = function() return nil end, world = function() return nil end, serverNow = function() return 0 end, previews = false, live = false, keyboard = true })
		local ok, err = pcall(function()
			ctl.sessionChanged("Practice", { mode = "Training", authority = "Local", slot = 1 })
			local panel = (ctl.gui:FindFirstChild("Stage") :: any).PracticePanel
			for _, row in Controls.legend("practice", "keyboard") do
				for _, key in tokens(row.keys) do t.expect.truthy(hasGlyph(panel, key), "practice panel shows " .. row.action .. " key " .. key) end
			end
			ctl.sessionChanged("Lobby", nil)
			ctl.openMenu("HowToPlay")
			local page = (holder :: any).FightingLabLobbyMenu.Stage.Body.Panel.Content.Page_HowToPlay
			for _, group in { "fight", "lobby" } do
				for _, row in Controls.legend(group, "keyboard") do
					for _, key in tokens(row.keys) do t.expect.truthy(hasGlyph(page, key), "How to Play shows " .. group .. "." .. row.action .. " key " .. key) end
				end
			end
		end)
		ctl.destroy(); holder:Destroy(); player:Destroy()
		if not ok then error(err, 0) end
	end)

	-- A full-height child (Size.Y.Scale > 0) inside an auto-height frame that also has a list layout makes the frame
	-- grow without bound (seen once as a 1000 px empty lesson card). Every UI surface is scanned for the pattern.
	t.test("no auto-height list frame has a scale-height child (unbounded growth)", function()
		local function offenders(root: Instance): { string }
			local out = {}
			for _, f in root:GetDescendants() do
				if f:IsA("GuiObject") and (f.AutomaticSize == Enum.AutomaticSize.Y or f.AutomaticSize == Enum.AutomaticSize.XY)
					and (f:FindFirstChildOfClass("UIListLayout") or f:FindFirstChildOfClass("UIGridLayout")) then
					for _, c in f:GetChildren() do
						if c:IsA("GuiObject") and c.Size.Y.Scale ~= 0 then table.insert(out, f.Name .. " > " .. c.Name) end
					end
				end
			end
			return out
		end
		local holder = Instance.new("Folder")
		local player = Instance.new("Folder"); player:SetAttribute("DuelState", "Lobby"); player:SetAttribute("FighterId", "Kael")
		local session: any = { _state = "Lobby" }
		function session.state() return session._state end
		function session.info() return { mode = "Training", cpu = false, authority = "Local", slot = 1 } end
		function session.practiceCommand() end
		local ctl = LobbyUI.mount({ player = player, parent = holder, session = session, stations = function() return nil end, world = function() return nil end, serverNow = function() return 0 end, previews = false, live = false, keyboard = true })
		local gui = Instance.new("ScreenGui"); gui.Parent = holder
		local ok, err = pcall(function()
			for _, page in { "Fighters", "HowToPlay", "Moves", "Settings", "Credits" } do ctl.openMenu(page) end
			ctl.closeMenu()
			t.expect.truthy(ctl.openFighterSelect("Kael"), "the fighter select builds too")
			local sel = ctl.fighterSelect()
			if sel then sel.close() end
			ctl.sessionChanged("Practice", { mode = "Training", cpu = false, authority = "Local", slot = 1 })
			t.expect.truthy(ctl.startLesson())
			t.expect.truthy(ctl.openPicker("training") or ctl.picker() == nil)
			Hud.init({ gui = gui, modules = {} })
			Hud._resetForTests()
			Hud.setGuide(true)
			local bad = offenders(holder)
			t.expect.equal(#bad, 0, "unbounded layouts: " .. table.concat(bad, ", "))
			-- Only one UIScale per object takes effect: a second one (e.g. a fit scale next to the design scale) is ignored.
			local doubled = {}
			for _, d in holder:GetDescendants() do
				if d:IsA("GuiObject") then
					local n = 0
					for _, c in d:GetChildren() do if c:IsA("UIScale") then n += 1 end end
					if n > 1 then table.insert(doubled, d.Name) end
				end
			end
			t.expect.equal(#doubled, 0, "objects with two UIScales: " .. table.concat(doubled, ", "))
			Hud.setGuide(false)
		end)
		ctl.destroy(); holder:Destroy(); player:Destroy()
		if not ok then error(err, 0) end
	end)

	t.test("fighter select attribute bars separate the cast whatever units the roster uses", function()
		local spread: { [string]: { number } } = {}
		for _, id in Roster.order do
			for _, a in UIHelpers.attributes(Roster.get(id), Roster) do
				t.expect.truthy(a.value >= 0.12 and a.value <= 1, id .. " " .. a.name .. " in range")
				local s = spread[a.name] or { math.huge, -math.huge }
				spread[a.name] = { math.min(s[1], a.value), math.max(s[2], a.value) }
			end
		end
		for _, name in UIHelpers.ATTRIBUTE_NAMES do
			local s = spread[name]
			t.expect.truthy(s ~= nil and s[2] - s[1] >= 0.3, name .. " bars differ between fighters")
		end
		-- The roster's heaviest fighter has the best DEFENSE bar.
		local tank, most = "", -1
		for _, id in Roster.order do
			local hp = Roster.get(id).stats.maxHealth or 0
			if hp > most then tank, most = id, hp end
		end
		local best, bestId = -1, ""
		for _, id in Roster.order do
			local v = UIHelpers.attributes(Roster.get(id), Roster)[4].value
			if v > best then best, bestId = v, id end
		end
		t.expect.equal(bestId, tank)
		-- REACH follows the designer spacing (stats.preferredRange) when the roster has it: the kickboxer outreaches the
		-- grappler, whatever the per-move ranges say after a step-in retune.
		local longest, shortest, hi, lo = "", "", -math.huge, math.huge
		for _, id in Roster.order do
			local pr = Roster.get(id).stats.preferredRange
			if typeof(pr) == "number" then
				if pr > hi then longest, hi = id, pr end
				if pr < lo then shortest, lo = id, pr end
			end
		end
		if longest ~= "" and hi > lo then
			local function reachOf(id: string): number return UIHelpers.attributes(Roster.get(id), Roster)[3].value end
			for _, id in Roster.order do
				t.expect.truthy(reachOf(id) <= reachOf(longest) + 1e-9, id .. " reach <= " .. longest)
				t.expect.truthy(reachOf(id) >= reachOf(shortest) - 1e-9, id .. " reach >= " .. shortest)
			end
		end
	end)

	t.test("move notation is numeric 1-4 with direction arrows for every roster move", function()
		for _, id in Roster.order do
			local def = Roster.get(id)
			for _, key in def.moveOrder do
				local mv = def.moves[key]
				local n = UIHelpers.notationOf(mv.input)
				t.expect.falsy(string.find(n, "LP", 1, true) or string.find(n, "RP", 1, true) or string.find(n, "LK", 1, true) or string.find(n, "RK", 1, true), id .. " " .. key .. " notation is numeric: " .. n)
				local tokens = UIHelpers.notationTokens(mv.input)
				local buttons = 0
				for _, tok in tokens do if tok.kind == "btn" then buttons += 1 end end
				t.expect.truthy(buttons >= 1, id .. " " .. key .. " names at least one button")
				t.expect.truthy(#MoveList.formatInput(mv.input, false) > 0)
				t.expect.truthy(#UIHelpers.moveDescription(mv) > 0, id .. " " .. key .. " has a description")
			end
		end
		local tokens = UIHelpers.notationTokens("df+2")
		t.expect.equal(tokens[1].kind, "dir"); t.expect.equal(tokens[1].value, "df")
		t.expect.equal(tokens[2].kind, "plus"); t.expect.equal(tokens[3].kind, "btn"); t.expect.equal(tokens[3].value, "2")
		t.expect.equal(UIHelpers.notationText("1,2"), "1 › 2")
		t.expect.equal(UIHelpers.notationText("d+3"), "↓ + 3")
		-- Out of a forward dash: one double-tap, not a two-step string (roster "dash+RP", Controls notation "f,f+2").
		for _, input in { "dash+RP", "f,f+2" } do
			local kinds = {}
			for _, tok in UIHelpers.notationTokens(input) do table.insert(kinds, tok.kind .. ":" .. tok.value) end
			t.expect.equal(table.concat(kinds, " "), "dir:f dir:f plus:+ btn:2", input)
		end
		t.expect.equal(UIHelpers.notationText("ss+3"), "SIDESTEP + 3")
		-- Keys to press for a move, per device.
		local kb = UIHelpers.formatMoveInput("df+RP", "keyboard")
		t.expect.truthy(string.find(kb, UIHelpers.keyLabel("fight", "rp", "keyboard"), 1, true) ~= nil, "keyboard keys: " .. kb)
		t.expect.truthy(string.find(kb, UIHelpers.keyLabel("fight", "forward", "keyboard"), 1, true) ~= nil, "keyboard keys: " .. kb)
		local pad = UIHelpers.formatMoveInput("LP, RP", "gamepad")
		t.expect.truthy(string.find(pad, UIHelpers.keyLabel("fight", "lp", "gamepad"), 1, true) ~= nil and string.find(pad, UIHelpers.keyLabel("fight", "rp", "gamepad"), 1, true) ~= nil, "gamepad keys: " .. pad)
	end)
end
