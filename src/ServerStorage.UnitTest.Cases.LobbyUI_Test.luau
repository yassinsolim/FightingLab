--!strict
-- Lobby UI (OV6): prompt text per state, E-prompt flows (Fight CPU picker -> RequestCpu, dojo pickers -> practice),
-- no lobby hotkeys, practice keys from Controls (T / 1-3 / Backspace), the practice panel (dummy, pause), the menu
-- sections, station boards without instance leaks, leaderboard ordering, the result card and the duel feed.
-- Everything is mounted on the server with injected doubles (fake player Folder, fake remote, fake FightSession).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lab = ReplicatedStorage:WaitForChild("FightingLab")
local Client = Lab:WaitForChild("Client")
local UIState = require(Client:WaitForChild("UIState"))
local UIHelpers = require(Client:WaitForChild("UIHelpers"))
local LobbyUI = require(Client:WaitForChild("LobbyUI"))
local FighterSelect = require(Client:WaitForChild("FighterSelect"))
local StationBoards = require(Client:WaitForChild("StationBoards"))
local Leaderboard = require(Client:WaitForChild("Leaderboard"))
local Roster = require(Lab:WaitForChild("Roster"))
local LobbySprintModule = require(Client:WaitForChild("LobbySprint"))
local Runner = require(game:GetService("ServerStorage").UnitTest.RunUnitTest)

local function fakePlayer(attrs: { [string]: any }): Folder
	local p = Instance.new("Folder")
	p.Name = "TestDuelist"
	p:SetAttribute("DisplayName", "Tester")
	p:SetAttribute("UserId", 77)
	for k, v in attrs do p:SetAttribute(k, v) end
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local wins = Instance.new("IntValue"); wins.Name = "Wins"; wins.Value = 3; wins.Parent = stats
	local streak = Instance.new("IntValue"); streak.Name = "Streak"; streak.Value = 1; streak.Parent = stats
	stats.Parent = p
	return p
end

type Mounted = { ctl: any, player: Folder, holder: Folder, stations: Folder, remote: any, session: any, rejected: BindableEvent, arenas: { string }, setPad: (string?) -> (), destroy: () -> () }

local function mount(attrs: { [string]: any }, keyboard: boolean?, extra: { [string]: any }?): Mounted
	local holder = Instance.new("Folder")
	local player = fakePlayer(attrs)
	local stations = Instance.new("Folder")
	local remote: any = { calls = {} }
	function remote:FireServer(kind: string, payload: any) table.insert(self.calls, { kind = kind, payload = payload }) end
	-- Same surface as Client.FightSession (state/info/lastResult/Rejected/startPractice/practiceCommand/leave).
	local rejected = Instance.new("BindableEvent")
	local session: any = { calls = {}, _state = "Lobby", _last = nil, Rejected = rejected.Event }
	function session.state() return session._state end
	function session.info() return nil end
	function session.lastResult() return session._last end
	function session.startPractice(opts: any) table.insert(session.calls, { "startPractice", opts }) end
	function session.practiceCommand(kind: string, arg: any) table.insert(session.calls, { kind, arg }) end
	function session.leave() table.insert(session.calls, { "leave" }) end
	function session.isFightActive() return false end
	local pad: string? = nil
	local arenas: { string } = {}
	local env: any = {
		player = player, parent = holder, session = session, remote = remote, onLocalArena = function(id: string?) table.insert(arenas, id or "") end,
		stations = function() return stations end, world = function() return nil end, serverNow = function() return 1000 end,
		practicePad = function() return pad end, previews = false, live = false, keyboard = if keyboard == nil then true else keyboard,
	}
	for k, v in extra or {} do env[k] = v end
	local ctl = LobbyUI.mount(env)
	return {
		ctl = ctl, player = player, holder = holder, stations = stations, remote = remote, session = session, rejected = rejected, arenas = arenas,
		setPad = function(v: string?) pad = v end,
		destroy = function() ctl.destroy(); holder:Destroy(); player:Destroy(); stations:Destroy(); rejected:Destroy() end,
	}
end

-- Runs `body` with a mounted lobby UI and always tears it down (and restores the CPU offer delay).
local function withLobby(attrs: { [string]: any }, body: (Mounted) -> (), keyboard: boolean?, extra: { [string]: any }?)
	local m = mount(attrs, keyboard, extra)
	local saved = UIState.CPU_OFFER_DELAY
	local ok, err = pcall(body, m)
	UIState.CPU_OFFER_DELAY = saved
	m.destroy()
	if not ok then error(err, 0) end
end

local function setDuel(m: Mounted, duel: string, arena: string?, side: number?)
	m.player:SetAttribute("DuelState", duel)
	m.player:SetAttribute("ArenaId", arena or "")
	m.player:SetAttribute("PadSide", side or 0)
	m.ctl.refresh()
end

local function key(group: string, action: string): Enum.KeyCode
	return UIHelpers.keyCodes(group, action, "keyboard")[1]
end

return function(t: Runner.T)
	t.test("lobby prompt text follows the duel state", function()
		local v = UIState.lobbyView({ duelState = "Lobby" })
		t.expect.equal(v.mode, "Lobby")
		t.expect.equal(v.title, "PRESS PLAY TO FIGHT")
		v = UIState.lobbyView({ duelState = "Queued", arenaName = "Harbor Dusk", padSide = 2, queuedSeconds = 1 })
		t.expect.equal(v.mode, "Waiting")
		t.expect.equal(v.title, "WAITING FOR A CHALLENGER")
		t.expect.truthy(string.find(v.subtitle, "HARBOR DUSK", 1, true) ~= nil, "waiting names the arena")
		t.expect.truthy(string.find(v.subtitle, "P2", 1, true) ~= nil, "waiting names the circle side")
		v = UIState.lobbyView({ duelState = "Queued", queuedSeconds = UIState.CPU_OFFER_DELAY + 0.1, interactKey = "E" })
		t.expect.equal(v.mode, "CpuOffer")
		t.expect.equal(v.offer, "No challenger yet? Press E to fight a CPU")
		t.expect.falsy(string.find(UIState.lobbyView({ duelState = "Queued", queuedSeconds = 9, keyboard = false }).offer, "Press", 1, true), "tap wording on touch")
		t.expect.truthy(UIState.CPU_OFFER_DELAY >= 2.5 and UIState.CPU_OFFER_DELAY <= 3.5, "the CPU is offered after about three seconds")
		v = UIState.lobbyView({ sessionState = "Countdown", countdownEndsAt = 102.5, now = 100 })
		t.expect.equal(v.mode, "Countdown")
		t.expect.equal(v.digit, 3)
		t.expect.equal(v.subtitle, "Step off the circle to cancel")
		t.expect.equal(UIState.lobbyView({ duelState = "Countdown", countdownEndsAt = 100.4, now = 100 }).digit, 1)
		t.expect.equal(UIState.lobbyView({ sessionState = "Fight" }).mode, "Hidden")
		t.expect.equal(UIState.lobbyView({ duelState = "Fighting" }).mode, "Hidden")
		t.expect.equal(UIState.lobbyView({ sessionState = "Results" }).mode, "Results")
		t.expect.equal(UIState.lobbyView({ sessionState = "Practice" }).mode, "Practice")
		local p = UIState.lobbyView({ duelState = "Lobby", practicePad = "Cpu" })
		t.expect.equal(p.mode, "PracticeChoice")
		t.expect.equal(p.title, "VERSUS CPU")
		t.expect.equal(UIState.lobbyView({ practicePad = "Training" }).title, "TRAINING")
		t.expect.truthy(UIState.lobbyView({ duelState = "Queued" }).canChooseFighter)
		t.expect.falsy(UIState.lobbyView({ duelState = "Countdown" }).canChooseFighter)
		t.expect.falsy(UIState.lobbyView({ sessionState = "Fight" }).menuAllowed)
	end)

	t.test("ui helpers scale for 1080p, 768p and phones and count down whole seconds", function()
		t.expect.near(UIHelpers.uiScale(Vector2.new(1920, 1080), false), 1080 / 740, 0.01)
		t.expect.near(UIHelpers.uiScale(Vector2.new(1366, 768), false), 768 / 740, 0.01)
		t.expect.near(UIHelpers.uiScale(Vector2.new(667, 375), true), 0.66, 0.001)
		t.expect.equal(UIHelpers.countdownDigit(nil, 5), nil)
		t.expect.equal(UIHelpers.countdownDigit(10, 7.2), 3)
		t.expect.equal(UIHelpers.countdownDigit(10, 9.95), 1)
		t.expect.equal(UIHelpers.countdownDigit(10, 10.5), 0)
		t.expect.equal(UIHelpers.formatSeconds(37.2), "38")
		t.expect.equal(UIHelpers.formatSeconds("x"), "--")
	end)

	t.test("mounted lobby HUD shows identity and prompts and hides during fights", function()
		withLobby({ DuelState = "Lobby", FighterId = "Sierra" }, function(m)
			local title = m.ctl.promptText()
			t.expect.equal(title, "PRESS PLAY TO FIGHT")
			local stage = m.ctl.gui:FindFirstChild("Stage") :: any
			t.expect.equal(stage.Identity.Fighter.Text, "SIERRA")
			t.expect.equal(stage.Identity.Stats.WINS.Value.Text, "3")
			t.expect.equal(stage.Identity.Stats.STREAK.Value.Text, "1")
			setDuel(m, "Queued", "Arena_HarborDusk", 1)
			t.expect.truthy(string.find((m.ctl.promptText()), "WAITING FOR A CHALLENGER", 1, true) == 1)
			t.expect.truthy(stage.Prompt.Visible)
			setDuel(m, "Fighting", "Arena_HarborDusk", 1)
			t.expect.falsy(m.ctl.gui.Enabled, "lobby UI hidden during a fight")
			t.expect.equal(m.arenas[#m.arenas], "Arena_HarborDusk", "the fight's arena is reported so its board and pad tags hide locally")
			setDuel(m, "Lobby")
			t.expect.truthy(m.ctl.gui.Enabled)
			t.expect.equal(m.arenas[#m.arenas], "", "back in the lobby every board is live again")
			m.ctl.sessionChanged("Countdown", { arenaId = "Arena_HarborDusk", endsAt = 1001.6, side = 1 })
			t.expect.truthy(stage.Countdown.Visible)
			t.expect.equal(stage.Countdown.Ring.Digit.Text, "2")
			t.expect.falsy(stage.Prompt.Visible)
			m.ctl.sessionChanged("Lobby", nil)
			t.expect.equal(m.ctl.toastCount(), 1, "cancelled countdown leaves a toast")
		end)
	end)

	t.test("lobby hotkeys are only the action bar's Controls keys: PLAY and FIGHTERS; 1-3, E and Q do nothing", function()
		withLobby({ DuelState = "Lobby", FighterId = "Kael" }, function(m)
			for _, k in { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.E, Enum.KeyCode.Q, Enum.KeyCode.R, Enum.KeyCode.T } do
				t.expect.falsy(m.ctl.handleKey(k), k.Name .. " is not a lobby hotkey")
			end
			t.expect.equal(#m.remote.calls, 0)
			t.expect.truthy(m.ctl.handleKey(key("lobby", "play")), "the PLAY key opens the PLAY panel")
			t.expect.truthy(m.ctl.isPlayOpen())
			t.expect.truthy(m.ctl.handleKey(key("lobby", "play")), "and closes it again")
			t.expect.falsy(m.ctl.isPlayOpen())
			t.expect.truthy(m.ctl.handleKey(key("lobby", "fighters")), "the FIGHTERS key opens the fighter select")
			t.expect.truthy(m.ctl.fighterSelect().isOpen())
			m.ctl.fighterSelect().close()
			UIState.CPU_OFFER_DELAY = 0
			setDuel(m, "Queued", "Arena_MidnightRooftop", 1)
			t.expect.equal(m.ctl.view().mode, "CpuOffer")
			for _, k in { Enum.KeyCode.One, Enum.KeyCode.Three } do
				t.expect.falsy(m.ctl.handleKey(k), k.Name .. " never calls a CPU")
			end
			t.expect.equal(#m.remote.calls, 0)
			-- Never in fights or practice.
			setDuel(m, "Fighting", "Arena_MidnightRooftop", 1)
			t.expect.falsy(m.ctl.handleKey(key("lobby", "play")), "no PLAY panel in a fight")
			t.expect.falsy(m.ctl.handleKey(key("lobby", "fighters")), "no fighter select in a fight")
			t.expect.falsy(m.ctl.isPlayOpen())
		end)
	end)

	t.test("Fight CPU: E prompt after waiting alone, difficulty picker, then RequestCpu", function()
		withLobby({ DuelState = "Lobby" }, function(m)
			setDuel(m, "Queued", "Arena_MidnightRooftop", 1)
			t.expect.equal(m.ctl.view().mode, "Waiting")
			t.expect.falsy(m.ctl.promptSpecs().cpu.enabled, "no Fight CPU prompt while waiting the first seconds")
			t.expect.falsy(m.ctl.triggerPrompt("cpu"))
			t.expect.falsy(m.ctl.requestCpu("Hard"), "no CPU before the offer appears")
			UIState.CPU_OFFER_DELAY = 0
			m.ctl.refresh()
			t.expect.equal(m.ctl.view().mode, "CpuOffer")
			local spec = m.ctl.promptSpecs().cpu
			t.expect.truthy(spec.enabled)
			t.expect.equal(spec.action, "Fight CPU")
			t.expect.equal(spec.arenaId, "Arena_MidnightRooftop")
			t.expect.equal(spec.side, 1)
			t.expect.truthy(m.ctl.triggerPrompt("cpu"), "E opens the difficulty picker")
			local picker = m.ctl.picker()
			t.expect.equal(picker and picker.kind, "cpu")
			t.expect.falsy(m.ctl.promptSpecs().cpu.enabled, "prompts hide while the picker is open")
			local pickerGui = m.holder:FindFirstChild("FightingLabPicker") :: ScreenGui
			t.expect.truthy(pickerGui and pickerGui.Enabled)
			t.expect.truthy(m.ctl.handleKey(Enum.KeyCode.Right), "arrow keys move along the difficulties")
			t.expect.truthy(m.ctl.handleKey(Enum.KeyCode.Return), "Enter fights")
			t.expect.equal(#m.remote.calls, 1)
			t.expect.equal(m.remote.calls[1].kind, "RequestCpu")
			t.expect.equal(m.remote.calls[1].payload.difficulty, "Hard")
			t.expect.equal(m.ctl.picker(), nil)
			t.expect.falsy(pickerGui.Enabled)
			t.expect.truthy(string.find(select(2, m.ctl.promptText()), "Calling", 1, true) ~= nil, "the hint shows the CPU is coming")
			-- Backspace cancels, and repeat requests are debounced.
			m.ctl.triggerPrompt("cpu")
			t.expect.equal(m.ctl.picker(), nil, "no second picker while the CPU request is pending")
		end)
	end)

	t.test("difficulty picker cancels with Backspace and closes when a challenger arrives", function()
		withLobby({ DuelState = "Lobby" }, function(m)
			UIState.CPU_OFFER_DELAY = 0
			setDuel(m, "Queued", "Arena_HarborDusk", 2)
			t.expect.truthy(m.ctl.openPicker("cpu"))
			t.expect.truthy(m.ctl.handleKey(Enum.KeyCode.Backspace))
			t.expect.equal(m.ctl.picker(), nil)
			t.expect.equal(#m.remote.calls, 0)
			t.expect.truthy(m.ctl.openPicker("cpu"))
			setDuel(m, "Countdown", "Arena_HarborDusk", 2)
			t.expect.equal(m.ctl.picker(), nil, "the picker closes when its prompt no longer applies")
		end)
	end)

	t.test("dojo pads: E opens the setup picker; Versus CPU starts with opponent and difficulty", function()
		withLobby({ DuelState = "Lobby", FighterId = "Kael" }, function(m)
			m.setPad("Cpu")
			m.ctl.tick(0.2)
			t.expect.equal(m.ctl.view().mode, "PracticeChoice")
			local specs = m.ctl.promptSpecs()
			t.expect.truthy(specs.versus.enabled)
			t.expect.equal(specs.versus.action, "Versus CPU")
			t.expect.falsy(specs.training.enabled)
			t.expect.truthy(m.ctl.triggerPrompt("versus"))
			t.expect.truthy(m.ctl.handleKey(Enum.KeyCode.Up), "up: difficulty row")
			t.expect.truthy(m.ctl.handleKey(Enum.KeyCode.Right), "right: Hard")
			t.expect.truthy(m.ctl.handleKey(Enum.KeyCode.Up), "up: opponent row")
			t.expect.truthy(m.ctl.handleKey(Enum.KeyCode.Right), "right: next opponent")
			m.ctl.pickerAction("Go:start")
			local call = m.session.calls[1]
			t.expect.equal(call[1], "startPractice")
			t.expect.equal(call[2].mode, "Cpu")
			t.expect.equal(call[2].difficulty, "Hard")
			t.expect.truthy(Roster.has(call[2].opponent))
			t.expect.truthy(call[2].opponent ~= "Kael" or #Roster.order == 1)
		end)
	end)

	t.test("training pad: guided lesson choice starts the lesson when practice begins", function()
		withLobby({ DuelState = "Lobby", FighterId = "Kael" }, function(m)
			m.setPad("Training")
			m.ctl.tick(0.2)
			t.expect.truthy(m.ctl.promptSpecs().training.enabled)
			t.expect.equal(m.ctl.promptSpecs().training.action, "Start Training")
			t.expect.truthy(m.ctl.triggerPrompt("training"))
			t.expect.truthy(m.ctl.handleKey(Enum.KeyCode.Up), "up: lesson row")
			t.expect.truthy(m.ctl.handleKey(Enum.KeyCode.Right), "right: Guided lesson")
			t.expect.truthy(m.ctl.handleKey(Enum.KeyCode.Down))
			t.expect.truthy(m.ctl.handleKey(Enum.KeyCode.Return))
			local call = m.session.calls[1]
			t.expect.equal(call[2].mode, "Training")
			t.expect.equal(call[2].difficulty, nil)
			m.setPad(nil)
			m.ctl.sessionChanged("Practice", { mode = "Training", cpu = false, authority = "Local", slot = 1 })
			task.wait()
			t.expect.truthy(m.ctl.lesson() ~= nil, "the lesson starts with the practice session")
			local lessonCard = (m.ctl.gui:FindFirstChild("Stage") :: any).Lesson
			t.expect.truthy(lessonCard.Visible)
			t.expect.equal(lessonCard.Content.Title.Text, "WALK")
		end)
	end)

	t.test("practice keys come from Controls: T switches, 1-3 set the level, Backspace leaves", function()
		withLobby({ DuelState = "Lobby", FighterId = "Kael" }, function(m)
			m.ctl.sessionChanged("Practice", { mode = "Match", cpu = true, difficulty = "Hard", authority = "Local", slot = 1 })
			t.expect.equal(m.ctl.view().mode, "Practice")
			t.expect.falsy(m.ctl.handleKey(Enum.KeyCode.F), "F is not a practice key")
			t.expect.falsy(m.ctl.handleKey(key("practice", "reset")), "Reset belongs to InputController")
			t.expect.falsy(m.ctl.handleKey(key("practice", "dummy")), "Dummy belongs to InputController")
			t.expect.falsy(m.ctl.handleKey(key("practice", "pause")), "Pause belongs to InputController")
			t.expect.truthy(m.ctl.handleKey(key("practice", "easy")))
			t.expect.truthy(m.ctl.handleKey(key("practice", "switchMode")))
			t.expect.truthy(m.ctl.handleKey(key("practice", "leave")))
			t.expect.equal(m.session.calls[1][1], "Difficulty")
			t.expect.equal(m.session.calls[1][2], "Easy")
			t.expect.equal(m.session.calls[2][1], "SetMode", "T switches with FightSession's SetMode")
			t.expect.equal(m.session.calls[2][2], "Training")
			t.expect.equal(m.session.calls[3][1], "leave")
			t.expect.falsy(m.ctl.handleKey(Enum.KeyCode.ButtonY), "gamepad Y is right punch in practice, never the menu")
		end)
	end)

	t.test("practice panel: dummy and pause buttons, and snapshots keep it honest", function()
		withLobby({ DuelState = "Lobby", FighterId = "Kael" }, function(m)
			local info: any = { matchId = "p1", mode = "Training", cpu = false, practice = "Training", difficulty = "Normal", authority = "Local", slot = 1 }
			m.session.info = function() return info end
			m.session.practiceCommand = function(kind: string, arg: any)
				table.insert(m.session.calls, { kind, arg })
				if kind == "SetMode" and (arg == "Match" or arg == "Training") then info.mode = arg; info.cpu = arg == "Match"
				elseif kind == "Difficulty" then info.difficulty = arg end
				return true
			end
			m.ctl.sessionChanged("Practice", info)
			local panel = (m.ctl.gui:FindFirstChild("Stage") :: any).PracticePanel
			t.expect.truthy(panel.Visible)
			t.expect.equal(panel.Header.Mode.Text, "TRAINING")
			t.expect.truthy(panel.Dummy.Visible, "dummy behaviour row in training")
			m.ctl.practiceCommand("Dummy", "Guard")
			t.expect.equal(m.ctl.practiceState().dummy, "Guard")
			local dummyCall = m.session.calls[#m.session.calls]
			t.expect.equal(dummyCall[1], "Dummy")
			t.expect.equal(dummyCall[2], "Guard")
			m.ctl.practiceCommand("Dummy")
			t.expect.equal(m.ctl.practiceState().dummy, "Fight", "no argument cycles Stand > Guard > Fight")
			m.ctl.practiceCommand("Pause")
			t.expect.equal(m.session.calls[#m.session.calls][1], "Pause")
			t.expect.equal(m.session.calls[#m.session.calls][2], true)
			t.expect.equal(panel.Pause.Row.Label.Text, string.upper(UIHelpers.actionText("pause")), "the pause caption is the Controls legend text")
			t.expect.equal(panel.Pause:GetAttribute("Selected"), true, "the pause button lights while paused")
			-- Snapshot fields win (Y / P pressed through InputController).
			m.ctl.onSnapshot({ mode = "Training", dummy = "Stand", paused = false, fighters = {}, events = {} })
			t.expect.equal(m.ctl.practiceState().dummy, "Stand")
			t.expect.equal(panel.Pause:GetAttribute("Selected"), false, "snapshot paused = false clears it")
			-- T targets the opposite of the TRUE mode (FightSession.info()).
			info.mode = "Match"; info.cpu = true; info.practice = "Cpu"
			m.ctl.refresh()
			t.expect.equal(panel.Header.Mode.Text, "VERSUS CPU", "panel follows FightSession.info().mode")
			t.expect.equal(panel.Switch.ModeVersus:GetAttribute("Selected"), true, "the Versus CPU chip is lit")
			t.expect.equal(panel.Switch.ModeTraining:GetAttribute("Selected"), false)
			t.expect.falsy(panel.Dummy.Visible, "no dummy row in a CPU match")
			t.expect.truthy(m.ctl.handleKey(key("practice", "switchMode")))
			local last = m.session.calls[#m.session.calls]
			t.expect.equal(last[1], "SetMode")
			t.expect.equal(last[2], "Training")
			t.expect.truthy(m.ctl.handleKey(key("practice", "hard")))
			t.expect.equal(info.difficulty, "Hard")
			m.ctl.syncPractice("Match", nil, nil)
			t.expect.equal(panel.Header.Mode.Text, "TRAINING", "FightSession.info() wins over a stale snapshot")
		end)
	end)

	t.test("practice panel folds into a strip while fighting; pause (or the strip) opens it as a pause menu", function()
		local function hasKey(root: Instance, label: string): boolean
			for _, d in root:GetDescendants() do if d.Name == "Key_" .. label then return true end end
			return false
		end
		local function fightKey(action: string): Enum.KeyCode
			return UIHelpers.keyCodes("fight", action, "keyboard")[1]
		end
		local function run(touch: boolean)
			local now = 500
			local holder = Instance.new("Folder")
			local player = fakePlayer({ DuelState = "Lobby", FighterId = "Kael" })
			local info: any = { mode = "Training", cpu = false, practice = "Training", difficulty = "Normal", authority = "Local", slot = 1 }
			local calls: { { any } } = {}
			local session: any = { _state = "Lobby" }
			function session.state() return session._state end
			function session.info() return info end
			function session.practiceCommand(kind: string, arg: any) table.insert(calls, { kind, arg }); return true end
			function session.leave() end
			local ctl = LobbyUI.mount({
				player = player, parent = holder, session = session, stations = function() return nil end, world = function() return nil end,
				serverNow = function() return 1000 end, previews = false, live = false, keyboard = not touch, clock = function() return now end,
			})
			local ok, err = pcall(function()
				ctl.sessionChanged("Practice", info)
				local stage = ctl.gui:FindFirstChild("Stage") :: any
				local panel, strip = stage.PracticePanel, stage.PracticeStrip
				if touch then
					-- Touch: starts folded (an open panel would cover the touch fight buttons), no key glyphs; a tap on the
					-- strip opens it as a pause menu.
					t.expect.falsy(ctl.panelOpen(), "touch starts folded")
					t.expect.truthy(strip.Visible and not panel.Visible)
					t.expect.falsy(hasKey(strip, UIHelpers.keyLabel("practice", "pause")), "no key glyph on touch")
					ctl.togglePanel()
					t.expect.truthy(ctl.panelOpen() and panel.Visible and not strip.Visible, "a tap opens the panel")
					t.expect.equal(calls[#calls][1], "Pause"); t.expect.equal(calls[#calls][2], true)
					ctl.togglePanel()
					t.expect.falsy(ctl.panelOpen(), "a second tap folds it")
					t.expect.equal(calls[#calls][2], false, "...and resumes")
					return
				end
				-- Entering practice shows the whole panel for a first look.
				t.expect.truthy(ctl.panelOpen() and panel.Visible and not strip.Visible, "open on entering practice")
				now += LobbyUI.PANEL_START_SECONDS - 1; ctl.tick(0.05)
				t.expect.truthy(ctl.panelOpen(), "still open within the first-look time")
				now += 2; ctl.tick(0.05)
				t.expect.falsy(ctl.panelOpen(), "folds after a few seconds without use")
				t.expect.truthy(strip.Visible and not panel.Visible, "the strip replaces it")
				-- The strip: training / versus, the dummy mode, and the pause key that opens the panel (all from Controls).
				local stripText = strip.Row.Mode.Text .. " " .. strip.Row.Info.Text .. " " .. strip.Row.Hint.Text
				t.expect.truthy(string.find(stripText, "TRAINING", 1, true) ~= nil, "strip shows the mode: " .. stripText)
				t.expect.truthy(string.find(stripText, "STAND", 1, true) ~= nil, "strip shows the dummy mode")
				t.expect.truthy(string.find(stripText, string.upper(UIHelpers.actionText("pause")), 1, true) ~= nil, "strip names the pause action")
				t.expect.truthy(hasKey(strip, UIHelpers.keyLabel("practice", "pause")), "strip shows the pause key")
				-- Y through InputController: the dummy mode reaches the strip.
				ctl.onSnapshot({ mode = "Training", dummy = "Guard", paused = false, fighters = {}, events = {} })
				t.expect.truthy(string.find(strip.Row.Info.Text, "GUARD", 1, true) ~= nil, "strip follows entry.dummy")
				-- Pause (P / Start through InputController) opens the panel as a pause menu; it stays while paused.
				ctl.onSnapshot({ mode = "Training", dummy = "Guard", paused = true, fighters = {}, events = {} })
				t.expect.truthy(ctl.panelOpen() and panel.Visible, "pausing opens the panel")
				t.expect.falsy(ctl.handleKey(fightKey("lp")), "fight keys are never consumed")
				now += 60; ctl.tick(0.05)
				t.expect.truthy(ctl.panelOpen(), "a pause menu neither folds on fight keys nor times out")
				ctl.onSnapshot({ mode = "Training", dummy = "Guard", paused = false, fighters = {}, events = {} })
				t.expect.falsy(ctl.panelOpen(), "resuming folds it")
				-- The strip / fold button: open as a pause menu, fold and resume.
				ctl.togglePanel()
				t.expect.truthy(ctl.panelOpen(), "the strip opens the panel")
				t.expect.equal(calls[#calls][1], "Pause"); t.expect.equal(calls[#calls][2], true)
				ctl.togglePanel()
				t.expect.falsy(ctl.panelOpen(), "the fold button folds it")
				t.expect.equal(calls[#calls][1], "Pause"); t.expect.equal(calls[#calls][2], false)
				-- An open (unpaused) panel: use keeps it open, any fight key folds it at once.
				ctl.setPanelOpen(true)
				now += LobbyUI.PANEL_IDLE_SECONDS - 1; ctl.tick(0.05)
				ctl.practiceCommand("Dummy", "Stand")
				now += LobbyUI.PANEL_IDLE_SECONDS - 1; ctl.tick(0.05)
				t.expect.truthy(ctl.panelOpen(), "using the panel keeps it open")
				t.expect.falsy(ctl.handleKey(fightKey("forward")))
				t.expect.falsy(ctl.panelOpen(), "a fight key folds it")
				-- Touch fight buttons do not go through keys: the local fighter acting in a snapshot folds it too.
				ctl.setPanelOpen(true)
				ctl.onSnapshot({ mode = "Training", dummy = "Stand", paused = false, fighters = { { state = "Idle" }, { state = "Walk" } }, events = {} })
				t.expect.truthy(ctl.panelOpen(), "the dummy moving does not fold it")
				ctl.onSnapshot({ mode = "Training", dummy = "Stand", paused = false, fighters = { { state = "Startup", move = "Jab" }, { state = "Idle" } }, events = {} })
				t.expect.falsy(ctl.panelOpen(), "the local fighter attacking folds it")
				-- Versus CPU: the strip shows the mode; a level key flashes the level without opening the panel.
				info.mode = "Match"; info.cpu = true; info.practice = "Cpu"
				ctl.refresh()
				t.expect.equal(strip.Row.Mode.Text, "VERSUS CPU")
				t.expect.truthy(ctl.handleKey(UIHelpers.keyCodes("practice", "hard", "keyboard")[1]))
				t.expect.falsy(ctl.panelOpen(), "level keys do not open the panel")
				t.expect.truthy(string.find(strip.Row.Info.Text, "HARD", 1, true) ~= nil, "the strip flashes the new level")
				now += 2; ctl.tick(0.05)
				t.expect.falsy(strip.Row.Info.Visible, "the flash fades (the HUD tag already shows the CPU level)")
				-- Leaving practice hides both.
				ctl.sessionChanged("Lobby", nil)
				t.expect.falsy(panel.Visible or strip.Visible, "nothing left in the lobby")
			end)
			ctl.destroy(); holder:Destroy(); player:Destroy()
			if not ok then error(err, 0) end
		end
		run(false)
		run(true)
	end)

	t.test("fighter select confirm fires SelectFighter and locks outside the lobby", function()
		withLobby({ DuelState = "Lobby", FighterId = "Kael" }, function(m)
			t.expect.truthy(m.ctl.openFighterSelect())
			local picker = m.ctl.fighterSelect()
			t.expect.truthy(picker.isOpen())
			-- The overlays must survive respawns and stack above the HUD.
			local overlay = m.holder:FindFirstChild("FightingLabFighterSelect") :: ScreenGui?
			t.expect.truthy(overlay ~= nil and overlay.Enabled, "fighter select overlay exists and is shown")
			t.expect.falsy(overlay and overlay.ResetOnSpawn, "overlay survives respawn")
			t.expect.truthy(overlay and overlay.DisplayOrder > m.ctl.gui.DisplayOrder, "overlay sits above the lobby HUD")
			t.expect.falsy(m.ctl.gui.Enabled, "the lobby HUD hides behind the select")
			t.expect.equal(picker.selected(), "Kael")
			t.expect.truthy(picker.handleKey(Enum.KeyCode.Right))
			t.expect.equal(picker.selected(), Roster.order[2])
			t.expect.truthy(picker.handleKey(Enum.KeyCode.Left))
			picker.select("Nia")
			local info = (overlay :: any).Stage.Body.Info
			t.expect.equal((info:FindFirstChild("Name") :: TextLabel).Text, Roster.get("Nia").displayName)
			t.expect.truthy(picker.confirm())
			t.expect.equal(#m.remote.calls, 1)
			t.expect.equal(m.remote.calls[1].kind, "SelectFighter")
			t.expect.equal(m.remote.calls[1].payload.id, "Nia")
			t.expect.truthy(m.ctl.openFighterSelect("Kael"))
			t.expect.falsy(picker.confirm(), "the current fighter is not re-sent (the select just closes)")
			t.expect.falsy(picker.isOpen())
			t.expect.truthy(m.ctl.openFighterSelect())
			setDuel(m, "Countdown", "Arena_HarborDusk", 1)
			t.expect.falsy(picker.isOpen(), "select closes when a countdown starts")
			t.expect.falsy(m.ctl.openFighterSelect())
			t.expect.equal(#m.remote.calls, 1)
		end)
	end)

	t.test("fighter previews use their own covered clones, never the in-world rig pool", function()
		local borrowed = 0
		local presenter = {
			acquirePreview = function(_id: string) borrowed += 1; return Instance.new("Model") end,
			releasePreview = function(_model: Instance) borrowed += 1 end,
			prewarm = function(_ids: any) borrowed += 1 end,
		}
		local model, warm, release = FighterSelect.acquireModel(presenter, "Kael")
		t.expect.equal(borrowed, 0, "portrait clones must not borrow in-world pooled rigs")
		if model then
			t.expect.equal(warm, FighterSelect.WARMUP, "fresh clones stay covered while layered clothing refits")
			t.expect.equal(model.Parent, nil)
			release()
			t.expect.equal(model.Parent, nil)
		end
		local missing = FighterSelect.acquireModel(presenter, "NoSuchFighter")
		t.expect.equal(missing, nil)
		t.expect.equal(borrowed, 0)
	end)

	t.test("lobby menu opens on Tab with five sections, keyboard navigation, and closes", function()
		withLobby({ DuelState = "Lobby", FighterId = "Goran" }, function(m)
			t.expect.truthy(m.ctl.handleKey(Enum.KeyCode.Tab))
			t.expect.truthy(m.ctl.isMenuOpen())
			t.expect.equal(m.ctl.menuPage(), "Fighters")
			local menuGui = m.holder:FindFirstChild("FightingLabLobbyMenu") :: any
			t.expect.truthy(menuGui and menuGui.Enabled)
			local nav = menuGui.Stage.Body.Nav
			for _, id in LobbyUI.MENU_PAGES do t.expect.truthy(nav:FindFirstChild("Nav_" .. id) ~= nil, "nav item " .. id) end
			t.expect.truthy(m.ctl.handleKey(Enum.KeyCode.Down))
			t.expect.equal(m.ctl.menuPage(), "HowToPlay")
			t.expect.truthy(m.ctl.handleKey(Enum.KeyCode.Down))
			t.expect.equal(m.ctl.menuPage(), "Moves")
			local content = menuGui.Stage.Body.Panel.Content
			local rows = 0
			-- move rows only (round 6: MoveList adds group headers and a COMBOS section around them)
			for _, row in content.Page_Moves.List:GetChildren() do if row:IsA("Frame") and string.sub(row.Name, 1, 5) == "Move_" then rows += 1 end end
			t.expect.equal(rows, #Roster.get("Goran").moveOrder, "move list shows the current fighter")
			t.expect.truthy(m.ctl.handleKey(Enum.KeyCode.Return), "enter moves focus into the page")
			t.expect.truthy(m.ctl.handleKey(Enum.KeyCode.Right), "right switches the fighter tab")
			local heading = content.Page_Moves.Head.Heading.Text
			t.expect.truthy(heading ~= Roster.get("Goran").displayName, "move list shows the next fighter")
			t.expect.truthy(m.ctl.handleKey(Enum.KeyCode.Backspace), "backspace returns focus to the sections")
			m.ctl.openMenu("Settings")
			m.ctl.openMenu("Credits")
			m.ctl.openMenu("Controls")
			t.expect.equal(m.ctl.menuPage(), "HowToPlay", "old page ids map onto the new sections")
			t.expect.truthy(content.Page_HowToPlay.Visible)
			t.expect.falsy(content.Page_Settings.Visible)
			t.expect.falsy(m.ctl.handleKey(Enum.KeyCode.Escape), "Escape is never bound")
			t.expect.truthy(m.ctl.handleKey(Enum.KeyCode.Tab))
			t.expect.falsy(m.ctl.isMenuOpen())
			t.expect.falsy(menuGui.Enabled)
			setDuel(m, "Fighting", "Arena_HarborDusk", 1)
			t.expect.falsy(m.ctl.handleKey(Enum.KeyCode.Tab), "no lobby menu during a fight")
			t.expect.falsy(m.ctl.isMenuOpen())
		end)
	end)

	t.test("settings page: camera shake, volumes and controls guide mode are adjustable by keys", function()
		local hud = Instance.new("ScreenGui")
		local holder = Instance.new("Folder")
		local player = fakePlayer({ DuelState = "Lobby" })
		local ctl = LobbyUI.mount({ player = player, parent = holder, hud = hud, stations = function() return nil end, world = function() return nil end, serverNow = function() return 1000 end, previews = false, live = false, keyboard = true })
		local ok, err = pcall(function()
			ctl.openMenu("Settings")
			ctl.handleKey(Enum.KeyCode.Return) -- focus the page (row 1: camera shake)
			ctl.handleKey(Enum.KeyCode.Right) -- Off
			t.expect.equal(hud:GetAttribute("CameraShakeDisabled"), true)
			ctl.handleKey(Enum.KeyCode.Down); ctl.handleKey(Enum.KeyCode.Left) -- music -10%
			t.expect.near(ctl.settings().music, 0.9, 1e-6)
			ctl.handleKey(Enum.KeyCode.Down); ctl.handleKey(Enum.KeyCode.Left); ctl.handleKey(Enum.KeyCode.Left) -- sfx -20%
			t.expect.near(ctl.settings().sfx, 0.8, 1e-6)
			ctl.handleKey(Enum.KeyCode.Down); ctl.handleKey(Enum.KeyCode.Right) -- guide Auto -> On
			t.expect.equal(hud:GetAttribute("ControlsGuide"), "On")
			ctl.handleKey(Enum.KeyCode.Right)
			t.expect.equal(ctl.settings().guide, "Off")
		end)
		ctl.destroy(); holder:Destroy(); player:Destroy(); hud:Destroy()
		if not ok then error(err, 0) end
	end)

	t.test("station boards render every state without leaking instances", function()
		local surface = Instance.new("SurfaceGui")
		local board = StationBoards.build(surface)
		local function render(attrs: { [string]: any }) StationBoards.render(board, StationBoards.viewModel(attrs, 1000)) end
		render({ DisplayName = "Harbor Dusk", Kind = "Duel", State = "Open" })
		local count = #surface:GetDescendants()
		t.expect.equal(board.title.Text, "HARBOR DUSK")
		t.expect.equal(board.badgeText.Text, "OPEN")
		render({ DisplayName = "Harbor Dusk", State = "Waiting", P1UserId = 5, P1Name = "Ana", P1Fighter = "Nia" })
		t.expect.equal(board.badgeText.Text, "WAITING")
		t.expect.equal(board.sides[1].name.Text, "ANA")
		t.expect.equal(board.sides[1].fighter.Text, "NIA")
		t.expect.equal(board.sides[2].name.Text, "OPEN")
		render({ State = "Countdown", CountdownEndsAt = 1002.2, P1UserId = 5, P2UserId = -1, P1Name = "Ana" })
		t.expect.equal(board.center.Text, "3")
		t.expect.equal(board.sides[2].name.Text, "CPU")
		render({ State = "Fighting", P1UserId = 5, P2UserId = 6, P1Name = "Ana", P2Name = "Bo", P1Fighter = "Nia", P2Fighter = "Goran", P1Health = 0.4, P2Health = 0.9, Timer = 37.2, Round = 2, P1Rounds = 1 })
		t.expect.equal(board.badgeText.Text, "LIVE")
		t.expect.equal(board.center.Text, "38")
		t.expect.equal(board.centerSub.Text, "ROUND 2")
		t.expect.truthy(board.sides[1].bar.Visible)
		t.expect.equal(board.sides[1].pips[1].BackgroundColor3, UIHelpers.Theme.gold)
		render({ State = "Results", P1UserId = 5, P2UserId = 6, P1Name = "Ana", P2Name = "Bo", WinnerSlot = 2, ResultText = "Bo (GORAN) beat Ana (NIA)" })
		t.expect.equal(board.headline.Text, "BO WINS")
		t.expect.truthy(board.sides[2].tag.Visible)
		t.expect.equal(board.footer.Text, "Bo (GORAN) beat Ana (NIA)")
		render({ DisplayName = "Training Bay", Kind = "Practice", State = "Open" })
		t.expect.equal(board.badgeText.Text, "PRACTICE")
		t.expect.truthy(string.find(board.footer.Text, UIHelpers.keyLabel("lobby", "interact"), 1, true) ~= nil, "dojo board names the interact key")
		render({ DisplayName = "Harbor Dusk", Kind = "Duel", State = "Open" })
		t.expect.equal(#surface:GetDescendants(), count, "re-rendering never adds instances")
		surface:Destroy()
	end)

	t.test("station binding follows attribute changes and cleans up its board and pad tags", function()
		local arena = Instance.new("Model")
		arena.Name = "Arena_Test"
		arena:SetAttribute("DisplayName", "Test Arena")
		local boardPart = Instance.new("Part"); boardPart.Name = "StatusBoard"; boardPart.Parent = arena
		local gui = Instance.new("SurfaceGui"); gui.Name = "StatusGui"; gui.Parent = boardPart
		for _, name in { "PadP1", "PadP2" } do local pad = Instance.new("Part"); pad.Name = name; pad.Parent = arena end
		local station = Instance.new("Configuration")
		station.Name = "Arena_Test"
		station:SetAttribute("State", "Waiting"); station:SetAttribute("P1UserId", 5); station:SetAttribute("P1Name", "Ana")
		local tags = Instance.new("Folder")
		local binding = StationBoards.bind(arena, station, tags, function() return 1000 end)
		t.expect.truthy(binding ~= nil)
		if binding then
			t.expect.equal(#tags:GetChildren(), 2)
			t.expect.equal(binding.tags[1].name.Text, "ANA")
			t.expect.equal(binding.tags[2].name.Text, "OPEN")
			t.expect.equal(binding.board.title.Text, "TEST ARENA")
			local before = #gui:GetDescendants()
			station:SetAttribute("State", "Fighting"); station:SetAttribute("P2UserId", 6); station:SetAttribute("P2Name", "Bo")
			binding.refresh(1000)
			t.expect.equal(binding.board.badgeText.Text, "LIVE")
			t.expect.equal(binding.tags[2].name.Text, "BO")
			t.expect.equal(#gui:GetDescendants(), before)
			binding.destroy()
			t.expect.equal(#gui:GetChildren(), 0)
			t.expect.equal(#tags:GetChildren(), 0)
		end
		arena:Destroy(); station:Destroy(); tags:Destroy()
	end)

	t.test("live station boards: the local fight hides its arena board and every pad tag, then restores them", function()
		local world = Instance.new("Folder")
		local arenas = Instance.new("Folder"); arenas.Name = "Arenas"; arenas.Parent = world
		local stations = Instance.new("Folder")
		local tags = Instance.new("Folder")
		for _, id in { "Arena_A", "Arena_B" } do
			local arena = Instance.new("Model"); arena.Name = id
			local boardPart = Instance.new("Part"); boardPart.Name = "StatusBoard"; boardPart.Parent = arena
			local gui = Instance.new("SurfaceGui"); gui.Name = "StatusGui"; gui.Parent = boardPart
			for _, name in { "PadP1", "PadP2" } do local pad = Instance.new("Part"); pad.Name = name; pad.Parent = arena end
			arena.Parent = arenas
			local station = Instance.new("Configuration"); station.Name = id; station:SetAttribute("State", "Open"); station.Parent = stations
		end
		local live = StationBoards.start({ world = function() return world end, stations = function() return stations end, tagParent = tags, serverNow = function() return 1000 end })
		local function statusGui(id: string): SurfaceGui return (arenas :: any)[id].StatusBoard.StatusGui end
		local function tagsOf(id: string): { BillboardGui }
			local list = {}
			for _, b in live.bindings() do if b.arena.Name == id then for _, tag in b.tags do table.insert(list, tag.gui) end end end
			return list
		end
		local ok, err = pcall(function()
			t.expect.equal(#live.bindings(), 2)
			t.expect.equal(#tags:GetChildren(), 4)
			live.setFocusArena("Arena_A")
			t.expect.falsy(statusGui("Arena_A").Enabled, "the local fight's StatusGui is hidden")
			for _, tag in tagsOf("Arena_A") do t.expect.falsy(tag.Enabled, "the local fight's pad tags are hidden") end
			t.expect.truthy(statusGui("Arena_B").Enabled, "other arenas' physical boards stay live")
			for _, tag in tagsOf("Arena_B") do t.expect.falsy(tag.Enabled, "other arenas' floating pad tags hide during the local fight") end
			live.setFocusArena(nil)
			t.expect.truthy(statusGui("Arena_A").Enabled, "restored after the fight")
			for _, id in { "Arena_A", "Arena_B" } do
				for _, tag in tagsOf(id) do t.expect.truthy(tag.Enabled, id .. " pad tags are back in the lobby") end
			end
			-- An arena that appears mid-fight is bound with its tags already hidden.
			live.setFocusArena("Arena_B")
			local late = Instance.new("Model"); late.Name = "Arena_C"
			local lateBoard = Instance.new("Part"); lateBoard.Name = "StatusBoard"; lateBoard.Parent = late
			local lateGui = Instance.new("SurfaceGui"); lateGui.Name = "StatusGui"; lateGui.Parent = lateBoard
			for _, name in { "PadP1", "PadP2" } do local pad = Instance.new("Part"); pad.Name = name; pad.Parent = late end
			late.Parent = arenas
			live.refreshAll()
			task.wait()
			local lateTags = tagsOf("Arena_C")
			t.expect.equal(#lateTags, 2)
			for _, tag in lateTags do t.expect.falsy(tag.Enabled, "late arena's tags start hidden") end
		end)
		live.stop()
		t.expect.equal(#tags:GetChildren(), 0, "stop removes every pad tag")
		t.expect.truthy(statusGui("Arena_B").Enabled, "stop restores a hidden StatusGui")
		world:Destroy(); stations:Destroy(); tags:Destroy()
		if not ok then error(err, 0) end
	end)

	t.test("leaderboard orders by wins then streak and keeps ten fixed rows", function()
		local entries = {}
		for i = 1, 12 do table.insert(entries, { userId = i, name = "P" .. i, wins = i % 5, streak = i % 3, fighter = Roster.order[(i % #Roster.order) + 1] }) end
		local sorted = Leaderboard.sortEntries(entries)
		t.expect.equal(#sorted, 10)
		for i = 2, #sorted do
			local a, b = sorted[i - 1], sorted[i]
			t.expect.truthy(a.wins > b.wins or (a.wins == b.wins and a.streak >= b.streak))
		end
		local tie = Leaderboard.sortEntries({ { userId = 1, name = "zed", wins = 3, streak = 1 }, { userId = 2, name = "Amy", wins = 3, streak = 1 }, { userId = 3, name = "Bo", wins = 3, streak = 4 } })
		t.expect.equal(tie[1].name, "Bo")
		t.expect.equal(tie[2].name, "Amy")
		local surface = Instance.new("SurfaceGui")
		local board = Leaderboard.build(surface)
		Leaderboard.render(board, entries)
		t.expect.equal(board.rows[1].name.Text, sorted[1].name)
		t.expect.equal(board.rows[1].wins.Text, tostring(sorted[1].wins))
		local count = #surface:GetDescendants()
		Leaderboard.render(board, { entries[4] })
		t.expect.truthy(board.rows[1].frame.Visible)
		t.expect.falsy(board.rows[2].frame.Visible)
		t.expect.equal(#surface:GetDescendants(), count, "rows are reused")
		local p = fakePlayer({ FighterId = "Lumi" })
		local e = Leaderboard.entryFor(p)
		t.expect.equal(e.wins, 3)
		t.expect.equal(e.streak, 1)
		t.expect.equal(e.fighter, "Lumi")
		t.expect.equal(e.name, "Tester")
		p:Destroy(); surface:Destroy()
	end)

	t.test("result card reports victory or defeat with opponent, arena and rounds", function()
		withLobby({ DuelState = "Lobby" }, function(m)
			local start = { matchId = "m1", arenaId = "Arena_HarborDusk", slot = 2, cpu = false, authority = "Server",
				p1 = { userId = 9, name = "Rival", fighter = "Goran" }, p2 = { userId = 77, name = "Tester", fighter = "Nia" } }
			m.ctl.sessionChanged("Fight", start)
			t.expect.falsy(m.ctl.gui.Enabled, "hidden during the fight")
			m.ctl.sessionChanged("Results", { matchId = "m1", winnerSlot = 2, reason = "KO", rounds = { p1 = 1, p2 = 2 } })
			m.ctl.sessionChanged("Lobby", nil)
			t.expect.truthy(m.ctl.resultVisible())
			local card = (m.ctl.gui:FindFirstChild("Stage") :: any).Result
			t.expect.equal(card.Outcome.Text, "VICTORY")
			t.expect.truthy(string.find(card.Versus.Text, "Rival", 1, true) ~= nil)
			t.expect.truthy(string.find(card.Versus.Text, "GORAN", 1, true) ~= nil)
			t.expect.truthy(string.find(card.Where.Text, "HARBOR DUSK", 1, true) ~= nil)
			t.expect.truthy(string.find(card.Where.Text, "2\u{2013}1", 1, true) ~= nil)
			start.matchId = "m2"; start.slot = 1
			m.ctl.sessionChanged("Fight", start)
			m.ctl.sessionChanged("Results", { matchId = "m2", winnerSlot = 2, rounds = { p1 = 0, p2 = 2 } })
			m.ctl.sessionChanged("Lobby", nil)
			t.expect.equal(card.Outcome.Text, "DEFEAT")
			card.Visible = false
			m.ctl.sessionChanged("Practice", { matchId = "p1", authority = "Local", mode = "Training", slot = 1 })
			m.ctl.sessionChanged("Lobby", nil)
			t.expect.falsy(m.ctl.resultVisible(), "practice never shows a duel result")
		end)
	end)

	t.test("netcore protocol: result card from lastResult() once per match, rejections become toasts", function()
		withLobby({ DuelState = "Lobby" }, function(m)
			local start = { matchId = "n1", arenaId = "Arena_SnowSummit", slot = 1, cpu = true, difficulty = "Hard", authority = "Server",
				p1 = { userId = 77, name = "Tester", fighter = "Kael" }, p2 = { userId = -1, name = "", fighter = "Rhys" } }
			m.ctl.sessionChanged("Fight", start)
			local resultsInfo = table.clone(start)
			resultsInfo.winnerSlot = 1
			m.ctl.sessionChanged("Results", resultsInfo)
			m.session._last = { matchId = "n1", winnerSlot = 1, reason = "KO", rounds = { p1 = 2, p2 = 1 }, slot = 1, info = start }
			m.ctl.sessionChanged("Lobby", nil)
			t.expect.truthy(m.ctl.resultVisible())
			local card = (m.ctl.gui:FindFirstChild("Stage") :: any).Result
			t.expect.equal(card.Outcome.Text, "VICTORY")
			t.expect.truthy(string.find(card.Versus.Text, "CPU", 1, true) ~= nil, "CPU opponent named")
			t.expect.truthy(string.find(card.Versus.Text, "RHYS", 1, true) ~= nil)
			t.expect.truthy(string.find(card.Versus.Text, "HARD", 1, true) ~= nil)
			t.expect.truthy(string.find(card.Where.Text, "2\u{2013}1", 1, true) ~= nil, "rounds come from lastResult")
			card.Visible = false
			m.ctl.sessionChanged("Results", resultsInfo)
			m.ctl.sessionChanged("Lobby", nil)
			t.expect.falsy(m.ctl.resultVisible(), "the same match is never reported twice")
			m.ctl.sessionChanged("Practice", { matchId = "p9", authority = "Local", mode = "Training", slot = 1 })
			m.session._last = { matchId = "p9", winnerSlot = 0, reason = "Practice", rounds = { p1 = 0, p2 = 0 }, slot = 1, info = { authority = "Local" } }
			m.ctl.sessionChanged("Lobby", nil)
			t.expect.falsy(m.ctl.resultVisible(), "leaving practice shows no result")
			local before = m.ctl.toastCount()
			m.rejected:Fire({ request = "RequestCpu", reason = "TooSoon" })
			task.wait()
			t.expect.equal(m.ctl.toastCount(), before + 1)
			local newest: any = nil
			for _, toast in (m.ctl.gui:FindFirstChild("Stage") :: any).Toasts:GetChildren() do
				if toast.Name == "Toast" and (newest == nil or toast.LayoutOrder < newest.LayoutOrder) then newest = toast end
			end
			t.expect.equal(newest and newest.Title.Text, LobbyUI.REJECT_TITLES.RequestCpu)
			t.expect.equal(newest and newest.Body.Text, LobbyUI.REJECT_TEXT.TooSoon)
		end)
	end)

	t.test("other arenas' results arrive as toasts but your own duel does not", function()
		withLobby({ DuelState = "Lobby" }, function(m)
			local other = Instance.new("Configuration")
			other.Name = "Arena_SnowSummit"
			other:SetAttribute("DisplayName", "Summit Observatory"); other:SetAttribute("Kind", "Duel"); other:SetAttribute("State", "Fighting")
			other.Parent = m.stations
			local mine = Instance.new("Configuration")
			mine.Name = "Arena_HarborDusk"
			mine:SetAttribute("DisplayName", "Harbor Dusk"); mine:SetAttribute("State", "Fighting"); mine:SetAttribute("P1UserId", 77)
			mine.Parent = m.stations
			m.ctl.tick(2.1)
			other:SetAttribute("P1Name", "Ana"); other:SetAttribute("P2Name", "Bo"); other:SetAttribute("WinnerSlot", 1)
			other:SetAttribute("ResultText", "Ana (NIA) beat Bo (GORAN)"); other:SetAttribute("State", "Results")
			mine:SetAttribute("WinnerSlot", 1); mine:SetAttribute("State", "Results")
			task.wait(LobbyUI.FEED_SETTLE + 0.15)
			t.expect.equal(m.ctl.toastCount(), 1)
			local toasts = (m.ctl.gui:FindFirstChild("Stage") :: any).Toasts
			local toast = toasts:FindFirstChild("Toast")
			t.expect.truthy(toast ~= nil and string.find(toast.Body.Text, "Ana (NIA)", 1, true) ~= nil)
		end)
	end)

	t.test("lobby modules require without side effects", function()
		local before = #workspace:GetChildren()
		for _, name in { "LobbyUI", "LobbyPrompts", "PlayFlow", "FighterSelect", "SelectScene", "StationBoards", "Leaderboard", "FrontEnd", "UIState", "UIHelpers", "HudController", "LobbySprint", "FlashDetector" } do
			local module = Client:FindFirstChild(name)
			t.expect.truthy(module ~= nil and module:IsA("ModuleScript"), name .. " exists")
			require(module :: ModuleScript)
		end
		t.expect.equal(#workspace:GetChildren(), before)
		local frontEnd = require(Client:WaitForChild("FrontEnd")) :: any
		for _, fn in { "init", "start", "onSnapshot", "update" } do t.expect.equal(typeof(frontEnd[fn]), "function", "FrontEnd." .. fn) end
	end)

	-- Round 5 / 7 ---------------------------------------------------------------------------------------------------------
	local function station(m: Mounted, id: string, kind: string, order: number, state: string?): Configuration
		local c = Instance.new("Configuration")
		c.Name = id
		c:SetAttribute("ArenaId", id)
		c:SetAttribute("DisplayName", (string.gsub(id, "_", " ")))
		c:SetAttribute("Kind", kind)
		c:SetAttribute("Order", order)
		c:SetAttribute("State", state or "Open")
		c:SetAttribute("P1UserId", 0)
		c:SetAttribute("P2UserId", 0)
		c.Parent = m.stations
		return c
	end
	local function lastCall(m: Mounted): any
		return m.remote.calls[#m.remote.calls]
	end
	local function cardIds(m: Mounted): string
		local out = {}
		for _, c in m.ctl.playFlow().cards() do table.insert(out, c.id) end
		return table.concat(out, ",")
	end
	-- The flow's own parts: Header (Title, Sub, Crumb), Level, Showcase, Fighter, Cards, Notice, Footer.
	local function flowPart(m: Mounted, name: string): any
		return (m.holder:FindFirstChild("FightingLabPlay") :: any).Safe.Stage.Content:FindFirstChild(name)
	end
	local function press(m: Mounted, ...: Enum.KeyCode)
		for _, k in { ... } do t.expect.truthy(m.ctl.handleKey(k), k.Name .. " is taken by the PLAY flow") end
	end

	t.test("action bar: one big PLAY with smaller FIGHTERS and MENU, their Controls keys; hidden in fights, countdowns and practice", function()
		withLobby({ DuelState = "Lobby", FighterId = "Kael" }, function(m)
			local stage = m.ctl.gui:FindFirstChild("Stage") :: any
			local barFrame = stage.ActionBar
			t.expect.truthy(m.ctl.barVisible(), "bar shown in the lobby")
			for name, action in { Play = "play", Fighters = "fighters", Menu = "menu" } do
				local b = barFrame:FindFirstChild(name)
				t.expect.truthy(b ~= nil, name .. " button")
				t.expect.truthy(b:FindFirstChild("Key_" .. UIHelpers.keyLabel("lobby", action), true) ~= nil, name .. " shows its Controls key")
			end
			local play, fighters, menu = barFrame.Play :: TextButton, barFrame.Fighters :: TextButton, barFrame.Menu :: TextButton
			t.expect.truthy(play.Size.X.Offset >= 1.8 * fighters.Size.X.Offset and play.Size.X.Offset >= 1.8 * menu.Size.X.Offset, "PLAY is the big one")
			t.expect.truthy(play.Size.Y.Offset > fighters.Size.Y.Offset + 20, "and taller")
			t.expect.equal(stage:FindFirstChild("MenuButtonHolder"), nil, "the old top-left MENU button is gone (the bar has it)")
			t.expect.truthy(m.ctl.firstHintVisible(), "first-time hint points at PLAY")
			t.expect.truthy(string.find(stage.FirstHint.Text.Text, "PLAY", 1, true) ~= nil)
			t.expect.falsy(stage.Prompt.Visible, "the first-time hint stands in for the objective pill (no overlap)")
			t.expect.truthy(stage.Prompt.Position.Y.Offset < -stage.ActionBar.Size.Y.Offset, "hint above the bar")
			m.ctl.openPlay(nil)
			t.expect.falsy(m.ctl.barVisible(), "bar hidden behind the PLAY flow")
			t.expect.falsy(m.ctl.gui.Enabled, "the lobby HUD steps aside: much less on screen")
			m.ctl.closePlay()
			t.expect.truthy(m.ctl.gui.Enabled)
			t.expect.falsy(m.ctl.firstHintVisible(), "the first-time hint is gone once PLAY was opened")
			t.expect.truthy(stage.Prompt.Visible, "then the objective pill is back")
			t.expect.truthy(m.ctl.barVisible())
			m.ctl.openMenu(nil)
			t.expect.falsy(m.ctl.barVisible(), "hidden behind the menu")
			m.ctl.closeMenu()
			m.ctl.sessionChanged("Countdown", { arenaId = "Arena_A", endsAt = 1002, side = 1 })
			t.expect.falsy(m.ctl.barVisible(), "hidden in a countdown")
			m.ctl.sessionChanged("Lobby", nil)
			setDuel(m, "Fighting", "Arena_A", 1)
			t.expect.falsy(m.ctl.barVisible(), "hidden in a fight")
			setDuel(m, "Lobby")
			m.ctl.sessionChanged("Practice", { mode = "Training", authority = "Local", slot = 1 })
			t.expect.falsy(m.ctl.barVisible(), "hidden in practice")
			t.expect.falsy(m.ctl.openPlay(nil), "no PLAY in practice")
			m.ctl.sessionChanged("Lobby", nil)
			t.expect.truthy(m.ctl.barVisible(), "back in the lobby")
			t.expect.truthy(m.ctl.openFighterSelect(nil) and m.ctl.fighterSelect().isOpen(), "FIGHTERS opens the showcase select anywhere")
			t.expect.falsy(m.ctl.barVisible(), "hidden behind the select")
			m.ctl.fighterSelect().close()
		end)
	end)

	t.test("PLAY flow: a CPU fight is PLAY, VS CPU, a map, FIGHT!, with the first press never dropped", function()
		withLobby({ DuelState = "Lobby", FighterId = "Kael" }, function(m)
			station(m, "Arena_A", "Duel", 1)
			station(m, "Arena_B", "Duel", 2, "Fighting")
			station(m, "Arena_C", "Duel", 3)
			station(m, "Arena_Dojo", "Practice", 5)
			press(m, key("lobby", "play"))
			local flow = m.ctl.playFlow()
			t.expect.truthy(m.ctl.isPlayOpen())
			local gui = m.holder:FindFirstChild("FightingLabPlay") :: ScreenGui
			t.expect.truthy(gui and gui.Enabled, "the flow is on screen")
			t.expect.equal(flow.screen(), "Who")
			t.expect.equal(cardIds(m), "duel,cpu,practice", "three big cards: who do you want to fight?")
			t.expect.truthy(gui:FindFirstChild("Card_cpu", true) ~= nil)
			t.expect.equal(gui:FindFirstChild("Card_travel:Plaza", true), nil, "no GO TO grid")
			press(m, Enum.KeyCode.Right)
			press(m, Enum.KeyCode.Return)
			t.expect.equal(flow.screen(), "Map", "the very first Enter is taken")
			t.expect.equal(cardIds(m), "Arena_A,Arena_B,Arena_C", "one card per duel map (no dojo)")
			t.expect.equal(flow.state().focus, 1, "the first free map")
			t.expect.equal(flow.previewArena(), "Arena_A", "its preview is behind the panel")
			press(m, Enum.KeyCode.D)
			t.expect.equal(flow.previewArena(), "Arena_B", "the preview follows the focus")
			press(m, Enum.KeyCode.Left)
			press(m, Enum.KeyCode.Return)
			t.expect.equal(flow.screen(), "Ready")
			t.expect.truthy(gui:FindFirstChild("Card_fight", true) ~= nil and gui:FindFirstChild("Card_fighter", true) ~= nil, "FIGHT! and CHANGE FIGHTER")
			t.expect.truthy(flowPart(m, "Fighter").Visible, "your fighter is shown")
			local before = #m.remote.calls
			press(m, Enum.KeyCode.Return)
			t.expect.equal(#m.remote.calls, before + 1, "FIGHT! sends one request")
			local call = lastCall(m)
			t.expect.equal(call.kind, "QuickPlay")
			t.expect.equal(call.payload.mode, "Cpu")
			t.expect.equal(call.payload.arena, "Arena_A")
			t.expect.equal(call.payload.difficulty, "Normal")
			press(m, Enum.KeyCode.Return)
			t.expect.equal(#m.remote.calls, before + 1, "no double send while the server answers")
			t.expect.truthy(string.find(flowPart(m, "Notice").Text, "HEADING TO", 1, true) ~= nil)
			-- The server moves the player: the flow closes (the fight camera takes the preview shot from here).
			m.ctl.onTeleport({ reason = "Cpu", arenaId = "Arena_A", delay = 0.2 })
			t.expect.falsy(m.ctl.isPlayOpen())
			t.expect.falsy(gui.Enabled)
			-- The CPU level rides along: Up on the map screen, Left / Right, Down.
			m.ctl.openPlay(nil)
			press(m, Enum.KeyCode.Right, Enum.KeyCode.Return, Enum.KeyCode.Up, Enum.KeyCode.Right, Enum.KeyCode.Down, Enum.KeyCode.Right, Enum.KeyCode.Right)
			t.expect.equal(flow.state().difficulty, "Hard")
			t.expect.equal(flow.cards()[flow.state().focus].id, "Arena_C", "B is busy: the focus may still rest on it, C is free")
			press(m, Enum.KeyCode.Return, Enum.KeyCode.Return)
			t.expect.equal(lastCall(m).payload.difficulty, "Hard")
			t.expect.equal(lastCall(m).payload.arena, "Arena_C")
			m.ctl.closePlay()
			-- Mouse / touch: every card is a button (one click each).
			m.ctl.openPlay(nil)
			t.expect.truthy(m.ctl.playSelect("cpu"))
			t.expect.truthy(m.ctl.playSelect("Arena_C"))
			t.expect.equal(flow.screen(), "Ready")
			m.ctl.closePlay()
		end)
	end)

	t.test("PLAY flow: Back steps back, PLAY closes from any screen, Tab opens the menu, CHANGE FIGHTER comes back", function()
		withLobby({ DuelState = "Lobby", FighterId = "Kael" }, function(m)
			station(m, "Arena_A", "Duel", 1)
			local flow = m.ctl.playFlow()
			press(m, key("lobby", "play"), Enum.KeyCode.Return)
			t.expect.equal(flow.screen(), "Map")
			t.expect.equal(flow.state().mode, "Duel")
			press(m, Enum.KeyCode.Backspace)
			t.expect.equal(flow.screen(), "Who", "Backspace: one screen back")
			press(m, Enum.KeyCode.ButtonB)
			t.expect.falsy(m.ctl.isPlayOpen(), "B on the first screen closes")
			press(m, key("lobby", "play"), Enum.KeyCode.Return)
			press(m, key("lobby", "play"))
			t.expect.falsy(m.ctl.isPlayOpen(), "the PLAY key closes it from any screen")
			press(m, key("lobby", "play"), Enum.KeyCode.Right, Enum.KeyCode.Return, Enum.KeyCode.Return)
			t.expect.equal(flow.screen(), "Ready")
			-- CHANGE FIGHTER: the select takes over, then the flow comes back on READY.
			t.expect.truthy(m.ctl.playSelect("fighter"))
			t.expect.truthy(m.ctl.fighterSelect().isOpen())
			t.expect.falsy(m.ctl.isPlayOpen())
			m.ctl.fighterSelect().close()
			task.wait()
			t.expect.truthy(m.ctl.isPlayOpen(), "back in the flow")
			t.expect.equal(flow.screen(), "Ready", "on the same screen")
			-- The fighters key does the same.
			press(m, key("lobby", "fighters"))
			t.expect.truthy(m.ctl.fighterSelect().isOpen())
			m.ctl.fighterSelect().close()
			task.wait()
			t.expect.equal(flow.screen(), "Ready")
			press(m, Enum.KeyCode.Tab)
			t.expect.truthy(m.ctl.isMenuOpen(), "Tab: the menu")
			t.expect.falsy(m.ctl.isPlayOpen())
			m.ctl.closeMenu()
			t.expect.equal(#m.remote.calls, 0, "browsing sends nothing")
		end)
	end)

	t.test("PLAY flow: VS PLAYER: Any map queues, a map sends you there; searching / waiting show CANCEL and FIGHT CPU after 12 s", function()
		withLobby({ DuelState = "Lobby", FighterId = "Kael" }, function(m)
			station(m, "Arena_A", "Duel", 1)
			station(m, "Arena_B", "Duel", 2, "Waiting"):SetAttribute("P1UserId", 5)
			local flow = m.ctl.playFlow()
			press(m, key("lobby", "play"), Enum.KeyCode.Return)
			t.expect.equal(cardIds(m), "any,Arena_A,Arena_B", "Any map first")
			t.expect.equal(flow.cards()[1].chip, "RECOMMENDED")
			t.expect.equal(flow.previewArena(), nil, "Any map: the lobby view")
			press(m, Enum.KeyCode.Return)
			t.expect.equal(lastCall(m).kind, "QuickPlay")
			t.expect.equal(lastCall(m).payload.mode, "Duel")
			t.expect.equal(lastCall(m).payload.arena, nil)
			t.expect.falsy(m.ctl.isPlayOpen(), "the flow closes: walk around while you wait")
			-- Searching: the hint has CANCEL; PLAY opens the searching screen with CANCEL focused.
			m.player:SetAttribute("QuickQueue", 1000 - 3)
			m.player:SetAttribute("QuickStatus", "Searching")
			m.ctl.refresh()
			local v = m.ctl.view()
			t.expect.equal(v.mode, "Searching")
			t.expect.truthy(string.find(v.title, "0:03", 1, true) ~= nil, "queue clock")
			local stage = m.ctl.gui:FindFirstChild("Stage") :: any
			t.expect.truthy(stage.Prompt.Pill.Actions.Visible, "CANCEL on the hint")
			t.expect.falsy(stage.Prompt.Pill.Actions.FightCpu.Visible)
			m.ctl.tick(0.11)
			t.expect.equal(stage.ActionBar.Play.Row.Label.Text, "SEARCHING 0:03", "the PLAY button shows the queue clock")
			press(m, key("lobby", "play"))
			t.expect.equal(flow.screen(), "Search")
			t.expect.equal(cardIds(m), "cpuInstead,cancel")
			t.expect.equal(flow.state().focus, 2, "CANCEL focused until the CPU is offered")
			press(m, Enum.KeyCode.Return)
			t.expect.equal(lastCall(m).kind, "CancelQueue")
			m.player:SetAttribute("QuickQueue", 1000 - UIState.QUICK_CPU_OFFER - 1)
			m.ctl.refresh()
			t.expect.truthy(m.ctl.view().cpuInstead)
			t.expect.truthy(stage.Prompt.Pill.Actions.FightCpu.Visible, "FIGHT CPU on the hint")
			press(m, key("lobby", "play"))
			t.expect.equal(flow.state().focus, 1)
			press(m, Enum.KeyCode.Return)
			t.expect.equal(lastCall(m).payload.mode, "Cpu")
			t.expect.equal(lastCall(m).payload.arena, nil, "any free map")
			m.player:SetAttribute("QuickStatus", "Busy")
			m.player:SetAttribute("QuickQueue", 1000 - 2)
			m.ctl.refresh()
			t.expect.truthy(string.find(m.ctl.view().subtitle, "All maps are busy", 1, true) ~= nil)
			m.player:SetAttribute("QuickStatus", "Matched")
			m.ctl.refresh()
			t.expect.equal(m.ctl.view().title, "OPPONENT FOUND")
			m.player:SetAttribute("QuickQueue", 0)
			m.player:SetAttribute("QuickStatus", "")
			m.ctl.refresh()
			-- A chosen map: sent there to wait; the CPU is offered after the Quick Duel delay, not the walk-in one.
			press(m, key("lobby", "play"), Enum.KeyCode.Return, Enum.KeyCode.Right, Enum.KeyCode.Return)
			t.expect.equal(lastCall(m).payload.arena, "Arena_A")
			t.expect.falsy(m.ctl.isPlayOpen())
			m.player:SetAttribute("QueuedAt", 1000 - 5)
			setDuel(m, "Queued", "Arena_A", 1)
			t.expect.equal(m.ctl.view().mode, "Waiting", "5 s: still waiting for a player")
			t.expect.truthy(stage.Prompt.Pill.Actions.Visible, "CANCEL on the hint")
			m.ctl.tick(0.11)
			t.expect.equal(stage.ActionBar.Play.Row.Label.Text, "WAITING 0:05")
			m.player:SetAttribute("QueuedAt", 1000 - UIState.QUICK_CPU_OFFER - 1)
			m.ctl.refresh()
			t.expect.equal(m.ctl.view().mode, "CpuOffer")
			t.expect.truthy(stage.Prompt.Pill.Actions.FightCpu.Visible)
			press(m, key("lobby", "play"))
			t.expect.equal(flow.screen(), "Search")
			t.expect.truthy(string.find(flowPart(m, "Header").Title.Text, "WAITING AT", 1, true) ~= nil)
			press(m, Enum.KeyCode.Return)
			t.expect.equal(lastCall(m).payload.mode, "Cpu")
			t.expect.equal(lastCall(m).payload.arena, "Arena_A", "the CPU joins right on the circle")
			t.expect.truthy(m.ctl.playSelect("pill:cancel"))
			t.expect.equal(m.session.calls[#m.session.calls][1], "leave", "CANCEL leaves the circle")
			setDuel(m, "Lobby")
			-- Somebody walking onto a circle (not through the flow) keeps the short walk-in offer.
			UIState.CPU_OFFER_DELAY = 0
			setDuel(m, "Queued", "Arena_B", 2)
			t.expect.equal(m.ctl.view().mode, "CpuOffer")
		end)
	end)

	t.test("PLAY flow: a busy map is refused with the next free one offered, in place (READY) or by reopening the flow", function()
		withLobby({ DuelState = "Lobby", FighterId = "Kael" }, function(m)
			station(m, "Arena_A", "Duel", 1, "Fighting")
			station(m, "Arena_C", "Duel", 3)
			station(m, "Arena_D", "Duel", 4)
			local flow = m.ctl.playFlow()
			press(m, key("lobby", "play"), Enum.KeyCode.Right, Enum.KeyCode.Return)
			t.expect.equal(flow.cards()[flow.state().focus].id, "Arena_C", "the first free map is focused")
			press(m, Enum.KeyCode.Left, Enum.KeyCode.Return)
			local notice = flowPart(m, "Notice") :: TextLabel
			t.expect.truthy(notice.Visible and string.find(notice.Text, "IS BUSY", 1, true) ~= nil, "says so")
			t.expect.equal(flow.cards()[flow.state().focus].id, "Arena_C", "and offers the next free one")
			press(m, Enum.KeyCode.Return, Enum.KeyCode.Return)
			t.expect.equal(lastCall(m).payload.arena, "Arena_C")
			local toasts = m.ctl.toastCount()
			m.rejected:Fire({ request = "QuickPlay", reason = "ArenaBusy", arena = "Arena_C", next = "Arena_D" })
			task.wait()
			t.expect.equal(flow.screen(), "Ready")
			t.expect.equal(flow.state().arena, "Arena_D", "READY now offers D")
			t.expect.truthy(string.find(notice.Text, "FIGHT AT", 1, true) ~= nil)
			t.expect.equal(m.ctl.toastCount(), toasts, "the flow shows it, no toast")
			press(m, Enum.KeyCode.Return)
			t.expect.equal(lastCall(m).payload.arena, "Arena_D", "one press fights there")
			m.ctl.onTeleport({ reason = "Cpu", arenaId = "Arena_D" })
			-- VS PLAYER on a map that turned busy: the flow comes back on the map screen with the offer.
			press(m, key("lobby", "play"), Enum.KeyCode.Return)
			t.expect.truthy(m.ctl.playSelect("Arena_C"))
			t.expect.falsy(m.ctl.isPlayOpen())
			m.rejected:Fire({ request = "QuickPlay", reason = "ArenaBusy", arena = "Arena_C", next = "Arena_D" })
			task.wait()
			t.expect.truthy(m.ctl.isPlayOpen(), "reopened")
			t.expect.equal(flow.screen(), "Map")
			t.expect.equal(flow.cards()[flow.state().focus].id, "Arena_D")
			m.ctl.closePlay()
			-- Other refusals stay toasts.
			m.rejected:Fire({ request = "QuickPlay", reason = "TooFast" })
			task.wait()
			t.expect.equal(m.ctl.toastCount(), toasts + 1)
		end)
	end)

	t.test("sprint: lobby only, 16 -> 28 studs/s with a smooth ramp and a small FOV ease; never in fights, practice or overlays", function()
		local model = Instance.new("Model")
		local humanoid = Instance.new("Humanoid")
		humanoid.WalkSpeed = 16
		humanoid.Parent = model
		local camera = Instance.new("Camera")
		camera.FieldOfView = 70
		camera.CameraType = Enum.CameraType.Custom
		local moving = true
		local ok, err = pcall(function()
			withLobby({ DuelState = "Lobby", FighterId = "Kael" }, function(m)
				local sprint = m.ctl.sprint()
				t.expect.truthy(m.ctl.sprintAllowed())
				sprint.setHeld(true)
				local speeds = {}
				for _ = 1, 6 do
					m.ctl.tick(0.07)
					table.insert(speeds, humanoid.WalkSpeed)
				end
				for i = 2, #speeds do t.expect.truthy(speeds[i] >= speeds[i - 1], "speed ramps up smoothly") end
				t.expect.truthy(speeds[1] > 16 and speeds[1] < 22, "first step is a ramp, not a jump: " .. speeds[1])
				t.expect.near(humanoid.WalkSpeed, 28, 0.01)
				t.expect.near(camera.FieldOfView, 70 + LobbySprintModule.FOV_BOOST, 0.01)
				-- Standing still does not sprint.
				moving = false
				for _ = 1, 6 do m.ctl.tick(0.07) end
				t.expect.near(humanoid.WalkSpeed, 16, 0.01)
				t.expect.near(camera.FieldOfView, 70, 0.01)
				moving = true
				for _ = 1, 6 do m.ctl.tick(0.07) end
				t.expect.near(humanoid.WalkSpeed, 28, 0.01)
				-- An overlay stops it at once (the fighter select must never capture the boosted FOV).
				m.ctl.openPlay()
				m.ctl.tick(0.016)
				t.expect.near(humanoid.WalkSpeed, 16, 0.01)
				t.expect.near(camera.FieldOfView, 70, 0.01)
				m.ctl.closePlay()
				for _ = 1, 6 do m.ctl.tick(0.07) end
				t.expect.near(humanoid.WalkSpeed, 28, 0.01)
				m.ctl.openFighterSelect(nil)
				t.expect.near(humanoid.WalkSpeed, 16, 0.01, "cancelled before the select saves the camera")
				t.expect.near(camera.FieldOfView, 70, 0.01)
				m.ctl.fighterSelect().close()
				-- Never in practice or fights.
				m.ctl.sessionChanged("Practice", { mode = "Training", authority = "Local", slot = 1 })
				for _ = 1, 6 do m.ctl.tick(0.07) end
				t.expect.near(humanoid.WalkSpeed, 16, 0.01, "no sprint in practice")
				t.expect.falsy(m.ctl.sprintAllowed())
				m.ctl.sessionChanged("Lobby", nil)
				setDuel(m, "Fighting", "Arena_A", 1)
				for _ = 1, 6 do m.ctl.tick(0.07) end
				t.expect.near(humanoid.WalkSpeed, 16, 0.01, "no sprint in a fight")
				setDuel(m, "Lobby")
				sprint.setHeld(false)
				for _ = 1, 6 do m.ctl.tick(0.07) end
				t.expect.near(humanoid.WalkSpeed, 16, 0.01)
				-- Gamepad / touch toggle: armed while you reach for the stick, then on until you stop moving.
				moving = false
				sprint.setToggle(true)
				for _ = 1, 20 do m.ctl.tick(0.07) end
				t.expect.truthy(sprint.toggled(), "a tap on SPRINT waits for the first step (1.4 s still)")
				moving = true
				for _ = 1, 6 do m.ctl.tick(0.07) end
				t.expect.near(humanoid.WalkSpeed, 28, 0.01)
				moving = false
				for _ = 1, 12 do m.ctl.tick(0.07) end
				t.expect.falsy(sprint.toggled(), "the toggle switches off after standing still")
				t.expect.near(humanoid.WalkSpeed, 16, 0.01)
				sprint.setToggle(true)
				for _ = 1, math.ceil(LobbySprintModule.ARM_SECONDS / 0.07) + 1 do m.ctl.tick(0.07) end
				t.expect.falsy(sprint.toggled(), "never moving after the tap: off after ARM_SECONDS")
			end, true, { humanoid = function() return humanoid end, camera = function() return camera end, moving = function() return moving end })
		end)
		model:Destroy(); camera:Destroy()
		if not ok then error(err, 0) end
	end)
end
