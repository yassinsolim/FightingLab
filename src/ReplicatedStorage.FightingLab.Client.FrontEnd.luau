--!strict
-- Lobby front end (OV6). FrontEnd.start() starts the lobby UI (LobbyUI: HUD, world prompts, pickers, practice panel
-- and lesson, cinematic fighter select, lobby menu, arena boards, leaderboard). FrontEnd.onSnapshot receives every
-- snapshot entry (practice panel sync + lesson goals); FrontEnd.update stays callable for the client bootstrap.
--
-- Studio-only dev mock (off by default, never runs outside Studio): set FightingLabHUD attribute LobbyDevMock = true
-- to fabricate a mini world (four duel arenas + dojo boards, kiosk, leaderboard), Station / Player attributes,
-- leaderstats, a fake FightSession and a fake Lobby remote. Drive it with FightingLabHUD attributes:
--   LobbyDevScene = Idle | Waiting | CpuOffer | PickerCpu | Countdown | Countdown3 | Countdown2 | Countdown1 | Fight |
--                   Result | ResultLoss | PracticeTraining | PracticeCpu | PickerTraining | PickerVersus | Practice |
--                   PracticeVsCpu | Lesson | Lesson:<step> | Toasts | Rejected | Boards | Menu | MenuFighters |
--                   MenuHowTo | MenuControls | MenuMoves | MenuCredits | MenuSettings | Select | Select:<FighterId> |
--                   SelectConfirm | Board:<State> | Hud:<Fight|Combo|Counter|Launch|Escape|KO|Round|Win|Lose|Guide|Low|
--                   Surge|UltBanner|UltHits|Perfect|Time|DoubleKO|Punish|Intro|Final|Stance> | HudOff
--   LobbyDevHideHud = true hides the lobby HUD (board/leaderboard captures)
--   LobbyDevView  = "" (leave the camera alone) | Plaza | Leaderboard | Board:<ArenaId> | Pads:<ArenaId>
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LobbyUI = require(script.Parent.LobbyUI)
local LobbyCamera = require(script.Parent.LobbyCamera)
local UIHelpers = require(script.Parent.UIHelpers)
local Roster = require(script.Parent.Parent.Roster)

type Ctx = any
local M = {}
local ctx: Ctx? = nil
local started = false
local mock: any = nil
local returnCamera: LobbyCamera.Tracker? = nil -- frames the lobby camera after a fight, a practice or a quick travel

--------------------------------------------------------------------------------------------------------------------
-- Dev mock (Studio only)
--------------------------------------------------------------------------------------------------------------------
local DevMock = {}
DevMock.ORIGIN = Vector3.new(2400, 0, 2400)
DevMock.ARENAS = {
	{ id = "Arena_MidnightRooftop", stage = "MidnightRooftop", name = "Midnight Rooftop", kind = "Duel" },
	{ id = "Arena_HarborDusk", stage = "HarborDusk", name = "Harbor Dusk", kind = "Duel" },
	{ id = "Arena_JungleRuins", stage = "JungleRuins", name = "Jungle Ruins", kind = "Duel" },
	{ id = "Arena_SnowSummit", stage = "SnowSummit", name = "Summit Observatory", kind = "Duel" },
	{ id = "Arena_TrainingBay", stage = "TrainingBay", name = "Training Bay", kind = "Practice" },
}
local LADDER = {
	{ "NovaKick", 24, 5, "Sierra" }, { "IronPalm", 19, 0, "Goran" }, { "RooftopRex", 17, 3, "Kael" }, { "MiraDash", 15, 1, "Lumi" },
	{ "QuietStorm", 12, 0, "Rhys" }, { "SableFist", 11, 2, "Nia" }, { "Kestrel", 9, 0, "Sierra" }, { "JunoK", 6, 1, "Lumi" },
	{ "Orbit", 4, 0, "Goran" }, { "PixelPunch", 2, 0, "Kael" }, { "LateBloomer", 1, 1, "Nia" },
}

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, props: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Name = name; p.Anchored = true; p.Size = size; p.CFrame = cf; p.Color = color; p.Material = material; p.TopSurface = Enum.SurfaceType.Smooth
	if props then for k, v in props do (p :: any)[k] = v end end
	p.Parent = parent
	return p
end

local function surface(parent: BasePart, name: string, pixelsPerStud: number): SurfaceGui
	local g = Instance.new("SurfaceGui")
	g.Name = name; g.Face = Enum.NormalId.Front; g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud; g.PixelsPerStud = pixelsPerStud
	g.LightInfluence = 0; g.AlwaysOnTop = false; g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling; g.Parent = parent
	return g
end

-- Minimal stand-in for workspace.FightingLabWorld (contract section 3 names), far from the stage at the origin.
local function buildWorld(origin: Vector3): Folder
	local root = Instance.new("Folder")
	root.Name = "FightingLabWorld"
	root:SetAttribute("DevMock", true)
	local lobby = Instance.new("Model"); lobby.Name = "Lobby"; lobby.Parent = root
	part(lobby, "Plaza", Vector3.new(300, 1, 150), CFrame.new(origin + Vector3.new(0, -0.5, 10)), Color3.fromRGB(92, 98, 112), Enum.Material.Concrete)
	local board = part(lobby, "Leaderboard", Vector3.new(16, 12, 0.6), CFrame.lookAt(origin + Vector3.new(0, 8, 52), origin + Vector3.new(0, 8, 0)), Color3.fromRGB(30, 34, 46), Enum.Material.Metal)
	surface(board, "LeaderboardGui", 50)
	local kiosk = Instance.new("Model"); kiosk.Name = "FighterKiosk"; kiosk.Parent = lobby
	local promptPart = part(kiosk, "PromptPart", Vector3.new(3, 5, 3), CFrame.new(origin + Vector3.new(24, 2.5, 40)), Color3.fromRGB(255, 200, 76), Enum.Material.Neon)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ChooseFighter"; prompt.ActionText = "Choose Fighter"; prompt.ObjectText = "Fighters"; prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10; prompt.RequiresLineOfSight = false; prompt.Parent = promptPart
	local arenas = Instance.new("Folder"); arenas.Name = "Arenas"; arenas.Parent = root
	for i, spec in DevMock.ARENAS do
		local m = Instance.new("Model"); m.Name = spec.id
		m:SetAttribute("ArenaId", spec.id); m:SetAttribute("StageId", spec.stage); m:SetAttribute("DisplayName", spec.name)
		m:SetAttribute("Kind", spec.kind); m:SetAttribute("Order", i)
		local center = origin + Vector3.new((i - 3) * 58, 0, -20)
		part(m, "FightOrigin", Vector3.one, CFrame.new(center), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
		part(m, "Floor", Vector3.new(50, 1, 34), CFrame.new(center + Vector3.new(0, -0.45, 0)), Color3.fromRGB(58, 62, 76), Enum.Material.Slate)
		local boardPart = part(m, "StatusBoard", Vector3.new(16, 9, 0.6), CFrame.lookAt(center + Vector3.new(0, 10, -12), center + Vector3.new(0, 10, 30)), Color3.fromRGB(26, 30, 40), Enum.Material.Metal)
		surface(boardPart, "StatusGui", 50)
		local padNames = if spec.kind == "Practice" then { "PadTraining", "PadCpu" } else { "PadP1", "PadP2" }
		for side, padName in padNames do
			local color = if side == 1 then Color3.fromRGB(255, 124, 64) else Color3.fromRGB(64, 196, 255)
			if spec.kind == "Practice" then color = if side == 1 then Color3.fromRGB(64, 196, 255) else Color3.fromRGB(255, 124, 64) end
			local pad = part(m, padName, Vector3.new(0.4, 7, 7), CFrame.new(center + Vector3.new(if side == 1 then -14 else 14, 0.2, 6)) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.Material.Neon, { Shape = Enum.PartType.Cylinder, CanCollide = false })
			pad:SetAttribute("PadRadius", 3.5)
			if spec.kind == "Practice" then pad:SetAttribute("PadMode", if side == 1 then "Training" else "Cpu") else pad:SetAttribute("PadSide", side) end
		end
		m.Parent = arenas
	end
	root.Parent = workspace
	return root
end

local STATION_DEFAULTS: { [string]: any } = {
	State = "Open", P1UserId = 0, P2UserId = 0, P1Name = "", P2Name = "", P1Fighter = "", P2Fighter = "", CountdownEndsAt = 0,
	Phase = "", Round = 0, P1Rounds = 0, P2Rounds = 0, P1Health = 1, P2Health = 1, Timer = 0, WinnerSlot = 0, ResultText = "", Cpu = false, Difficulty = "",
}

function DevMock.start(cx: Ctx): any
	local player = Players.LocalPlayer
	local gui: ScreenGui = cx.gui
	local lab = ReplicatedStorage:WaitForChild("FightingLab")
	local created: { Instance } = {}
	local conns: { RBXScriptConnection } = {}
	local world = workspace:FindFirstChild("FightingLabWorld")
	local Lighting = game:GetService("Lighting")
	local savedClock = Lighting.ClockTime
	local disabledEffects: { PostEffect } = {}
	if not world then
		world = buildWorld(DevMock.ORIGIN)
		table.insert(created, world :: Instance)
		-- Readable daylight for dev captures without the real world (the base keeps the last stage's night grade
		-- and a fight-camera depth of field); restored on stop.
		Lighting.ClockTime = 16.6
		for _, e in Lighting:GetChildren() do
			if e:IsA("DepthOfFieldEffect") and e.Enabled then e.Enabled = false; table.insert(disabledEffects, e) end
		end
	end
	local stations = lab:FindFirstChild("Stations")
	if not stations then
		stations = Instance.new("Folder"); (stations :: Folder).Name = "Stations"; (stations :: Folder).Parent = lab
		table.insert(created, stations :: Instance)
	end
	local function station(id: string): Configuration
		local existing = (stations :: Instance):FindFirstChild(id)
		if existing and existing:IsA("Configuration") then return existing end
		local cfg = Instance.new("Configuration")
		cfg.Name = id
		for _, spec in DevMock.ARENAS do
			if spec.id == id then
				cfg:SetAttribute("ArenaId", id); cfg:SetAttribute("StageId", spec.stage); cfg:SetAttribute("DisplayName", spec.name); cfg:SetAttribute("Kind", spec.kind)
			end
		end
		for k, v in STATION_DEFAULTS do cfg:SetAttribute(k, v) end
		cfg.Parent = stations
		table.insert(created, cfg)
		return cfg
	end
	local function reset(id: string)
		local cfg = station(id)
		for k, v in STATION_DEFAULTS do cfg:SetAttribute(k, v) end
	end
	for _, spec in DevMock.ARENAS do station(spec.id) end

	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		stats = Instance.new("Folder"); (stats :: Folder).Name = "leaderstats"
		local wins = Instance.new("IntValue"); wins.Name = "Wins"; wins.Value = 7; wins.Parent = stats
		local streak = Instance.new("IntValue"); streak.Name = "Streak"; streak.Value = 2; streak.Parent = stats
		;(stats :: Folder).Parent = player
		table.insert(created, stats :: Instance)
	end
	local function bump(won: boolean)
		local w = (stats :: Instance):FindFirstChild("Wins") :: IntValue?
		local s = (stats :: Instance):FindFirstChild("Streak") :: IntValue?
		if w and won then w.Value += 1 end
		if s then s.Value = if won then s.Value + 1 else 0 end
	end
	if typeof(player:GetAttribute("FighterId")) ~= "string" then player:SetAttribute("FighterId", "Kael") end
	local function setPlayer(duel: string, arena: string, side: number)
		player:SetAttribute("DuelState", duel); player:SetAttribute("ArenaId", arena); player:SetAttribute("PadSide", side)
	end
	setPlayer("Lobby", "", 0)

	-- Fake FightSession (same surface as netcore's Client.FightSession).
	local changed = Instance.new("BindableEvent")
	local rejected = Instance.new("BindableEvent")
	local session: any = { _state = "Lobby", _info = nil, _last = nil, Changed = changed.Event, Rejected = rejected.Event, log = {} }
	local function setSession(state: string, info: any?)
		session._state = state; session._info = info
		-- Like FightSession: Roblox's player list only shows in the lobby (unless an overlay holds it hidden).
		if not UIHelpers.playerListHeld() then
			pcall(function() game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, state == "Lobby" or state == "Results") end)
		end
		changed:Fire(state, info)
	end
	function session.state(): string return session._state end
	function session.info(): any return session._info end
	function session.lastResult(): any return session._last end
	function session.isFightActive(): boolean return session._state == "Fight" or session._state == "Practice" end
	function session.startPractice(opts: any)
		table.insert(session.log, { "startPractice", opts })
		session._dummy = "Stand"
		session._paused = false
		gui:SetAttribute("LobbyDevPracticePad", nil)
		setPlayer("Practice", "Arena_TrainingBay", 0)
		local me = { userId = player.UserId, name = player.DisplayName, fighter = player:GetAttribute("FighterId") }
		setSession("Practice", { matchId = "practice", arenaId = "Arena_TrainingBay", stageId = "TrainingBay", authority = "Local", slot = 1,
			mode = if opts.mode == "Cpu" then "Match" else "Training", cpu = opts.mode == "Cpu", difficulty = opts.difficulty,
			p1 = me, p2 = { userId = -1, name = "CPU", fighter = opts.opponent or "Sierra" } })
	end
	-- Mirrors the combat agent's practice semantics (SetMode / Dummy Stand|Guard|Fight / Pause / Difficulty / Reset).
	function session.practiceCommand(kind: string, arg: any?): boolean
		table.insert(session.log, { kind, arg })
		print("[LobbyDevMock] practiceCommand", kind, arg)
		local info = session._info
		if session._state ~= "Practice" or typeof(info) ~= "table" then return false end
		if kind == "SetMode" and (arg == "Match" or arg == "Training") then
			info.mode = arg; info.cpu = arg == "Match"; session._dummy = "Stand"
		elseif kind == "Dummy" then
			local modes = { "Stand", "Guard", "Fight" }
			session._dummy = if typeof(arg) == "string" and table.find(modes, arg) then arg else modes[((table.find(modes, session._dummy) or 1) % 3) + 1]
		elseif kind == "Pause" then
			session._paused = if typeof(arg) == "boolean" then arg else not session._paused
		elseif kind == "Difficulty" then
			info.difficulty = arg
		end
		LobbyUI.onSnapshot({ mode = info.mode, dummy = if info.mode == "Training" then session._dummy else nil, paused = session._paused, fighters = {}, events = {} })
		return true
	end
	function session.leave()
		table.insert(session.log, { "leave" })
		if session._state == "Practice" then
			session._last = { matchId = "practice", winnerSlot = 0, reason = "Practice", rounds = { p1 = 0, p2 = 0 }, slot = 1, info = session._info }
		end
		setPlayer("Lobby", "", 0)
		setSession("Lobby", nil)
	end

	local me = { userId = player.UserId, name = player.DisplayName }
	local function startCountdown(seconds: number, cpu: boolean?, difficulty: string?)
		local cfg = station("Arena_MidnightRooftop")
		local endsAt = workspace:GetServerTimeNow() + seconds
		cfg:SetAttribute("State", "Countdown"); cfg:SetAttribute("P1UserId", me.userId); cfg:SetAttribute("P1Name", me.name)
		cfg:SetAttribute("P1Fighter", player:GetAttribute("FighterId"))
		cfg:SetAttribute("P2UserId", if cpu then -1 else 101); cfg:SetAttribute("P2Name", if cpu then "CPU" else "IronPalm"); cfg:SetAttribute("P2Fighter", "Goran")
		cfg:SetAttribute("Cpu", cpu == true); cfg:SetAttribute("Difficulty", difficulty or ""); cfg:SetAttribute("CountdownEndsAt", endsAt)
		setPlayer("Countdown", "Arena_MidnightRooftop", 1)
		setSession("Countdown", { arenaId = "Arena_MidnightRooftop", endsAt = endsAt, side = 1 })
	end

	local remote: any = { log = {} }
	local fight: (number?) -> () -- assigned below; RequestCpu starts a fake CPU duel after its countdown
	function remote:FireServer(kind: string, payload: any)
		table.insert(remote.log, { kind, payload })
		print("[LobbyDevMock] Lobby:FireServer", kind, if typeof(payload) == "table" then (payload.id or payload.difficulty or payload.mode) else payload)
		if kind == "SelectFighter" and typeof(payload) == "table" then
			player:SetAttribute("FighterId", payload.id)
		elseif kind == "RequestCpu" then
			startCountdown(3, true, if typeof(payload) == "table" then payload.difficulty else "Normal")
			task.delay(3.05, function() if session._state == "Countdown" then fight(nil) end end)
		elseif kind == "StartPractice" then
			session.startPractice(payload)
		end
	end

	local function practicePad(): string?
		local v = gui:GetAttribute("LobbyDevPracticePad")
		return if v == "Training" or v == "Cpu" then v else nil
	end
	local function ladder(): { any }
		local list = {}
		for i, row in LADDER do list[i] = { userId = 1000 + i, name = row[1], wins = row[2], streak = row[3], fighter = row[4] } end
		return list
	end
	local lobby = LobbyUI.start(cx, { session = session, remote = remote, practicePad = practicePad, leaderboardEntries = ladder })

	local holdDigit: number? = nil
	local cycling = false
	local boardsLive = false
	local matchCounter = 0
	fight = function(winnerSlot: number?)
		matchCounter += 1
		local matchId = "dev-" .. tostring(matchCounter)
		local cfg = station("Arena_MidnightRooftop")
		local fighter = player:GetAttribute("FighterId")
		for k, v in { P1UserId = me.userId, P1Name = me.name, P1Fighter = fighter, P2UserId = 101, P2Name = "IronPalm", P2Fighter = "Goran", Round = 2, P1Rounds = 1, P2Rounds = 0, P1Health = 0.62, P2Health = 0.35, Timer = 41, WinnerSlot = 0, ResultText = "", CountdownEndsAt = 0 } do cfg:SetAttribute(k, v) end
		cfg:SetAttribute("State", "Fighting")
		setPlayer("Fighting", "Arena_MidnightRooftop", 1)
		local startInfo = { matchId = matchId, arenaId = "Arena_MidnightRooftop", stageId = "MidnightRooftop", authority = "Server", slot = 1, mode = "Match", cpu = false,
			p1 = { userId = me.userId, name = me.name, fighter = fighter }, p2 = { userId = 101, name = "IronPalm", fighter = "Goran" } }
		setSession("Fight", startInfo)
		if winnerSlot then
			task.delay(0.4, function()
				cfg:SetAttribute("WinnerSlot", winnerSlot); cfg:SetAttribute("P1Rounds", if winnerSlot == 1 then 2 else 1)
				cfg:SetAttribute("P2Rounds", if winnerSlot == 2 then 2 else 1)
				local fighterName = string.upper(tostring(fighter))
				cfg:SetAttribute("ResultText", if winnerSlot == 1 then me.name .. " (" .. fighterName .. ") beat IronPalm (GORAN)" else "IronPalm (GORAN) beat " .. me.name .. " (" .. fighterName .. ")")
				cfg:SetAttribute("State", "Results")
				setPlayer("Results", "Arena_MidnightRooftop", 1)
				-- netcore: Results info = MatchStart info + winnerSlot; the MatchEnd (rounds) lands in lastResult().
				local resultsInfo = table.clone(startInfo)
				resultsInfo.winnerSlot = winnerSlot
				setSession("Results", resultsInfo)
				bump(winnerSlot == 1)
				task.delay(0.6, function()
					session._last = { matchId = matchId, winnerSlot = winnerSlot, reason = "KO", slot = 1, info = startInfo,
						rounds = { p1 = if winnerSlot == 1 then 2 else 1, p2 = if winnerSlot == 2 then 2 else 1 } }
					setPlayer("Lobby", "", 0)
					setSession("Lobby", nil)
					reset("Arena_MidnightRooftop")
				end)
			end)
		end
	end
	local function boards()
		boardsLive = true
		reset("Arena_MidnightRooftop"); reset("Arena_HarborDusk"); reset("Arena_JungleRuins"); reset("Arena_SnowSummit")
		local live = station("Arena_MidnightRooftop")
		for k, v in { State = "Fighting", P1UserId = 201, P1Name = "NovaKick", P1Fighter = "Sierra", P2UserId = 202, P2Name = "SableFist", P2Fighter = "Nia", Round = 2, P1Rounds = 1, P2Rounds = 0, P1Health = 0.72, P2Health = 0.31, Timer = 38 } do live:SetAttribute(k, v) end
		local waiting = station("Arena_HarborDusk")
		for k, v in { State = "Waiting", P1UserId = 203, P1Name = "IronPalm", P1Fighter = "Goran" } do waiting:SetAttribute(k, v) end
		local countdown = station("Arena_JungleRuins")
		for k, v in { State = "Countdown", P1UserId = 204, P1Name = "MiraDash", P1Fighter = "Lumi", P2UserId = -1, P2Name = "CPU", P2Fighter = "Rhys", Cpu = true, Difficulty = "Hard", CountdownEndsAt = workspace:GetServerTimeNow() + 2.6 } do countdown:SetAttribute(k, v) end
		local results = station("Arena_SnowSummit")
		for k, v in { State = "Results", P1UserId = 205, P1Name = "QuietStorm", P1Fighter = "Rhys", P2UserId = 206, P2Name = "Kestrel", P2Fighter = "Sierra", P1Rounds = 2, P2Rounds = 1, WinnerSlot = 1, ResultText = "QuietStorm (RHYS) beat Kestrel (SIERRA) 2-1" } do results:SetAttribute(k, v) end
	end
	-- Board:<State> puts the Midnight Rooftop board (unobstructed from the front) into one state for captures.
	local function boardState(state: string)
		boardsLive = true
		reset("Arena_MidnightRooftop")
		local cfg = station("Arena_MidnightRooftop")
		local sets: { [string]: { [string]: any } } = {
			Waiting = { P1UserId = 203, P1Name = "IronPalm", P1Fighter = "Goran" },
			Countdown = { P1UserId = 204, P1Name = "MiraDash", P1Fighter = "Lumi", P2UserId = -1, P2Name = "CPU", P2Fighter = "Rhys", Cpu = true, Difficulty = "Hard", CountdownEndsAt = workspace:GetServerTimeNow() + 2.6 },
			Fighting = { P1UserId = 201, P1Name = "NovaKick", P1Fighter = "Sierra", P2UserId = 202, P2Name = "SableFist", P2Fighter = "Nia", Round = 2, P1Rounds = 1, P2Rounds = 0, P1Health = 0.72, P2Health = 0.31, Timer = 38 },
			Results = { P1UserId = 205, P1Name = "QuietStorm", P1Fighter = "Rhys", P2UserId = 206, P2Name = "Kestrel", P2Fighter = "Sierra", P1Rounds = 2, P2Rounds = 1, WinnerSlot = 1, ResultText = "QuietStorm (RHYS) beat Kestrel (SIERRA) 2-1" },
		}
		for k, v in sets[state] or {} do cfg:SetAttribute(k, v) end
		cfg:SetAttribute("State", if sets[state] then state else "Open")
	end
	-- Stations are reset first and re-filled after the lobby feed's settle time, so each change reads as a new event.
	local function toasts()
		local a = station("Arena_SnowSummit")
		reset("Arena_SnowSummit")
		task.delay(0.7, function()
			for k, v in { P1UserId = 205, P1Name = "QuietStorm", P1Fighter = "Rhys", P2UserId = 206, P2Name = "Kestrel", P2Fighter = "Sierra", WinnerSlot = 1, P1Rounds = 2, P2Rounds = 0, ResultText = "QuietStorm (RHYS) beat Kestrel (SIERRA) 2-0" } do a:SetAttribute(k, v) end
			a:SetAttribute("State", "Results")
		end)
		local b = station("Arena_HarborDusk")
		reset("Arena_HarborDusk")
		task.delay(1.0, function()
			b:SetAttribute("P1UserId", 203); b:SetAttribute("P1Name", "IronPalm"); b:SetAttribute("P1Fighter", "Goran"); b:SetAttribute("State", "Waiting")
		end)
		local c = station("Arena_JungleRuins")
		reset("Arena_JungleRuins")
		task.delay(1.3, function()
			for k, v in { P1UserId = 204, P1Name = "MiraDash", P1Fighter = "Lumi", P2UserId = -1, P2Name = "CPU", P2Fighter = "Rhys", Cpu = true, WinnerSlot = 2, ResultText = "CPU (RHYS, HARD) beat MiraDash (LUMI)" } do c:SetAttribute(k, v) end
			c:SetAttribute("State", "Results")
		end)
	end

	-- Fight HUD demo (Studio captures): drives HudController with a fabricated frame so every call-out can be shot.
	-- Round 6 variants: Surge (molten bar + SURGE + ULTIMATE ready), UltBanner (UltStart title card + letterbox),
	-- UltHits (the cinematic's impacts on the combo counter), Perfect, Time, DoubleKO, Punish, Intro, Final, Stance.
	-- In the real world the camera frames the Midnight Rooftop ring like a fight camera so the HUD reads over a stage.
	local hudDemo: string? = nil
	local hudFrame: { [string]: any } = {}
	local hudCamera = false
	local function hudScene(variant: string)
		local Hud = cx.modules and cx.modules.Hud
		if not Hud then return end
		-- FightSession hides the player list in real fights; the demo does the same so the bars read cleanly.
		if not hudDemo then UIHelpers.holdPlayerList(true) end
		hudDemo = variant
		lobby.setSuppressed(true)
		Hud.setViewSlot(1)
		local mine = player:GetAttribute("FighterId")
		local myId = if typeof(mine) == "string" and Roster.has(mine) then mine else "Kael"
		local oppId = if myId == "Goran" then "Sierra" else "Goran"
		local d1, d2 = Roster.get(myId), Roster.get(oppId)
		Hud.setFighterInfo(1, { displayName = d1.displayName, color = d1.accentColor, characterId = myId, maxHealth = d1.stats.maxHealth, playerName = player.DisplayName, tag = "YOU" })
		Hud.setFighterInfo(2, { displayName = d2.displayName, color = d2.accentColor, characterId = oppId, maxHealth = d2.stats.maxHealth, playerName = "", tag = "CPU · HARD" })
		Hud.setVisible(true)
		local h1, h2 = 0.72, 0.46
		if variant == "Low" then h1, h2 = 0.18, 0.64
		elseif variant == "KO" or variant == "Perfect" then h1, h2 = if variant == "Perfect" then 1 else 0.41, 0
		elseif variant == "Surge" or variant == "UltBanner" or variant == "UltHits" then h1, h2 = 0.19, 0.58
		elseif variant == "Time" then h1, h2 = 0.55, 0.31
		elseif variant == "DoubleKO" then h1, h2 = 0, 0 end
		local m1, m2 = d1.stats.maxHealth, d2.stats.maxHealth
		local function snap(frame: number, s1: string?, s2: string?, extra1: { [string]: any }?, extra2: { [string]: any }?)
			local f1: { [string]: any } = { characterId = myId, health = m1 * h1, maxHealth = m1, state = s1 or "Idle" }
			local f2: { [string]: any } = { characterId = oppId, health = m2 * h2, maxHealth = m2, state = s2 or "Idle" }
			for k, v in extra1 or {} do f1[k] = v end
			for k, v in extra2 or {} do f2[k] = v end
			local entry = { p2Human = false, frame = frame, fighters = { f1, f2 } }
			Hud.onSnapshot(entry)
			return entry
		end
		local surgeFields = if variant == "Surge" or variant == "UltBanner" or variant == "UltHits" then { surge = variant == "Surge", ultUsed = variant ~= "Surge" } else nil
		local entry = snap(100, nil, nil, surgeFields, if surgeFields then { surge = false, ultUsed = false } else nil)
		hudFrame = { dt = 1 / 60, mode = "Match", timer = 47 * 60, config = cx.config, scores = { 1, 0 }, phase = "Fight", round = 2, ko = false, session = "Fight", authority = "Server", paused = false, renderFrame = 0, winner = 0, reason = "", entry = entry }
		if variant == "Combo" then
			for i = 1, 5 do task.delay(0.12 * i, function() Hud.onEvent({ kind = "Hit", attacker = 1, target = 2, combo = i, damage = 7 + i, frame = i }) end) end
		elseif variant == "Counter" then
			Hud.onEvent({ kind = "Hit", attacker = 1, target = 2, combo = 1, damage = 18, counter = true, frame = 1 })
		elseif variant == "Punish" then
			snap(101, nil, "Recovery")
			Hud.onEvent({ kind = "Hit", attacker = 1, target = 2, combo = 1, damage = 16, frame = 102 })
		elseif variant == "Launch" then
			Hud.onEvent({ kind = "Hit", attacker = 1, target = 2, combo = 1, damage = 14, launch = true, tier = "Launch", frame = 1 })
		elseif variant == "Escape" then
			Hud.onEvent({ kind = "ThrowBreak", attacker = 2, target = 1, combo = 0, damage = 0, frame = 1 })
		elseif variant == "Surge" then
			Hud.onEvent({ kind = "Surge", attacker = 1, target = 1, combo = 0, damage = 0, frame = 100 })
		elseif variant == "UltBanner" or variant == "UltHits" then
			local ult = { archetype = "ultimate", move = "Ultimate", frame = 1, duration = 210, impactFrame = 36 }
			Hud.onEvent({ kind = "UltStart", attacker = 1, target = 2, move = "Ultimate", combo = 0, damage = 0, frame = 101 })
			snap(102, "Ultimate", "Ultimate", { surge = false, ultUsed = true, throw = ult }, { surge = false, ultUsed = false, throw = ult })
			if variant == "UltHits" then
				for i, share in { 0.12, 0.12, 0.16, 0.2, 0.4 } do
					task.delay(0.25 * i, function() Hud.onEvent({ kind = "UltHit", attacker = 1, target = 2, move = "Ultimate", combo = i, damage = math.floor(33 * share + 0.5), knockdown = i == 5, frame = 102 + i }) end)
				end
			end
		elseif variant == "Stance" then
			snap(101, "Stance", nil, { stance = "Pocket", stanceFrame = 12 })
		elseif variant == "KO" then
			hudFrame.ko = true; hudFrame.phase = "RoundOver"; hudFrame.reason = "KO"; hudFrame.winner = 1
		elseif variant == "Perfect" then
			hudFrame.ko = true; hudFrame.phase = "RoundOver"; hudFrame.reason = "KO"; hudFrame.winner = 1
		elseif variant == "DoubleKO" then
			hudFrame.ko = true; hudFrame.phase = "RoundOver"; hudFrame.reason = "KO"; hudFrame.winner = 0
		elseif variant == "Time" then
			hudFrame.timer = 0; hudFrame.phase = "RoundOver"; hudFrame.reason = "TIME"; hudFrame.winner = 1
		elseif variant == "Round" or variant == "Intro" or variant == "Final" then
			hudFrame.phase = "Ready"
			if variant == "Intro" then hudFrame.round = 1; hudFrame.scores = { 0, 0 } end
			if variant == "Final" then hudFrame.round = 3; hudFrame.scores = { 1, 1 } end
			task.delay(1.3, function() if hudDemo == variant then hudFrame.phase = "Fight" end end)
		elseif variant == "Win" then
			hudFrame.phase = "MatchOver"; hudFrame.scores = { 2, 1 }; hudFrame.winner = 1; hudFrame.reason = "KO"
		elseif variant == "Lose" then
			hudFrame.phase = "MatchOver"; hudFrame.scores = { 0, 2 }; hudFrame.winner = 2; hudFrame.reason = "KO"
		end
		-- The guide shows for the first fight (and on demand); the call-out shots leave it closed.
		if Hud.setGuide then Hud.setGuide(variant == "Guide" or variant == "Fight") end
		-- A fight-camera view of the rooftop ring behind the HUD (real world only; held every frame in update).
		local w = workspace:FindFirstChild("FightingLabWorld")
		local arenas = w and w:FindFirstChild("Arenas")
		local arena = arenas and arenas:FindFirstChild("Arena_MidnightRooftop")
		hudCamera = arena ~= nil and arena:FindFirstChild("FightOrigin") ~= nil
	end
	local function hudOff()
		local Hud = cx.modules and cx.modules.Hud
		if hudDemo and Hud then Hud.setVisible(false); if Hud.setGuide then Hud.setGuide(false) end end
		if hudDemo then UIHelpers.holdPlayerList(false) end
		hudDemo = nil
		if hudCamera then
			hudCamera = false
			local cam = workspace.CurrentCamera
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if cam then cam.CameraType = Enum.CameraType.Custom; cam.FieldOfView = 70; if humanoid then cam.CameraSubject = humanoid end end
		end
		lobby.setSuppressed(gui:GetAttribute("LobbyDevHideHud") == true)
	end

	local function scene(name: string)
		holdDigit = nil; cycling = false
		gui:SetAttribute("LobbyDevPracticePad", nil)
		lobby.closeMenu()
		if lobby.picker() then lobby.pickerAction("Back") end
		if string.sub(name, 1, 4) ~= "Hud:" then hudOff() end
		local picker = lobby.fighterSelect()
		if string.sub(name, 1, 6) ~= "Select" and picker.isOpen() then picker.close() end
		if name ~= "Boards" and string.sub(name, 1, 6) ~= "Board:" and boardsLive then boardsLive = false; reset("Arena_MidnightRooftop") end
		local function waiting(seconds: number)
			setSession("Lobby", nil)
			reset("Arena_MidnightRooftop")
			local cfg = station("Arena_MidnightRooftop")
			cfg:SetAttribute("State", "Waiting"); cfg:SetAttribute("P1UserId", me.userId); cfg:SetAttribute("P1Name", me.name); cfg:SetAttribute("P1Fighter", player:GetAttribute("FighterId"))
			setPlayer("Queued", "Arena_MidnightRooftop", 1)
			player:SetAttribute("QueuedAt", workspace:GetServerTimeNow() - seconds)
		end
		local function pad(kind: string)
			if session._state ~= "Lobby" then setSession("Lobby", nil) end
			setPlayer("Lobby", "", 0)
			gui:SetAttribute("LobbyDevPracticePad", kind)
		end
		if name == "Idle" then
			if session._state ~= "Lobby" then setSession("Lobby", nil) end
			setPlayer("Lobby", "", 0); reset("Arena_MidnightRooftop")
		elseif name == "Waiting" then
			waiting(1)
		elseif name == "CpuOffer" then
			waiting(8)
		elseif name == "PickerCpu" then
			waiting(8)
			lobby.refresh()
			lobby.openPicker("cpu")
		elseif name == "Countdown" then
			cycling = true
			startCountdown(3)
		elseif string.match(name, "^Countdown%d$") then
			holdDigit = tonumber(string.sub(name, 10))
			startCountdown((holdDigit :: number) - 0.5)
		elseif name == "Fight" then
			fight(nil)
		elseif name == "Result" then
			fight(1)
		elseif name == "ResultLoss" then
			fight(2)
		elseif name == "PracticeTraining" or name == "PracticeCpu" then
			pad(if name == "PracticeTraining" then "Training" else "Cpu")
		elseif name == "PickerTraining" or name == "PickerVersus" then
			pad(if name == "PickerTraining" then "Training" else "Cpu")
			lobby.refresh()
			lobby.openPicker(if name == "PickerTraining" then "training" else "versus")
		elseif name == "Practice" then
			session.startPractice({ mode = "Training", opponent = "Sierra" })
		elseif name == "PracticeVsCpu" then
			session.startPractice({ mode = "Cpu", difficulty = "Hard", opponent = "Goran" })
		elseif name == "Lesson" or string.sub(name, 1, 7) == "Lesson:" then
			if session._state ~= "Practice" then session.startPractice({ mode = "Training", opponent = "Sierra" }) end
			lobby.startLesson()
			local stepNo = tonumber(string.sub(name, 8))
			local t = lobby.lesson()
			if t and stepNo then
				for _ = 1, math.clamp(stepNo, 1, #t.steps) - 1 do
					local UIState = require(script.Parent.UIState) :: any
					UIState.tutorialSkip(t, os.clock() - 5)
					UIState.tutorialObserve(t, { fighters = {}, events = {} }, os.clock())
				end
				if stepNo > 1 then
					-- Half-done goals so the card shows progress.
					local step = t.steps[t.index]
					if step and step.goals[1] then step.goals[1].have = math.max(0, step.goals[1].need - 1) end
				end
				lobby.onSnapshot({ mode = "Training", dummy = "Stand", fighters = {}, events = {} })
			end
		elseif name == "Toasts" then
			toasts()
		elseif name == "Rejected" then
			rejected:Fire({ request = "RequestCpu", reason = "TooSoon" })
		elseif name == "Boards" then
			boards()
		elseif string.sub(name, 1, 6) == "Board:" then
			boardState(string.sub(name, 7))
		elseif name == "Menu" or name == "MenuFighters" then
			lobby.openMenu("Fighters")
		elseif name == "MenuControls" or name == "MenuHowTo" then
			lobby.openMenu("HowToPlay")
		elseif name == "MenuMoves" then
			lobby.openMenu("Moves")
		elseif name == "MenuCredits" then
			lobby.openMenu("Credits")
		elseif name == "MenuSettings" then
			lobby.openMenu("Settings")
		elseif name == "Select" then
			lobby.openFighterSelect()
		elseif string.sub(name, 1, 7) == "Select:" then
			if not picker.isOpen() then lobby.openFighterSelect() end
			picker.select(string.sub(name, 8))
		elseif name == "SelectConfirm" then
			picker.confirm()
		elseif string.sub(name, 1, 4) == "Hud:" then
			hudScene(string.sub(name, 5))
		elseif name == "HudOff" then
			hudOff()
		end
	end
	table.insert(conns, gui:GetAttributeChangedSignal("LobbyDevHideHud"):Connect(function()
		lobby.setSuppressed(gui:GetAttribute("LobbyDevHideHud") == true)
	end))
	table.insert(conns, gui:GetAttributeChangedSignal("LobbyDevScene"):Connect(function()
		local name = gui:GetAttribute("LobbyDevScene")
		if typeof(name) == "string" and name ~= "" then scene(name) end
	end))

	-- With the real world present, the pre-lobby bootstrap still loads a stage and two idle fighters at the origin
	-- (inside the plaza); keep them out of dev captures. Studio dev mock only.
	local realWorld = not (world :: Instance):GetAttribute("DevMock")
	local tidyAcc = 1
	local function tidyLegacyStage(dt: number)
		tidyAcc += dt
		if not realWorld or tidyAcc < 1 then return end
		tidyAcc = 0
		local stage = workspace:FindFirstChild("FightingLabArena")
		if stage and stage:IsA("Model") and stage:GetPivot().Position.Y > -500 then stage:PivotTo(CFrame.new(0, -900, 0)) end
		local fighters = workspace:FindFirstChild("FightingLabLocalRender")
		if fighters then
			-- Only the legacy stage's two idle fighters; pooled preview rigs (fighter select) stay visible.
			for _, m in fighters:GetChildren() do
				if string.sub(m.Name, 1, 7) == "Fighter" then
					for _, d in m:GetDescendants() do if d:IsA("BasePart") then d.LocalTransparencyModifier = 1 end end
				end
			end
		end
	end

	local liveAcc = 0
	local function update(frame: any)
		local dt = if frame and typeof(frame.dt) == "number" then frame.dt else 1 / 60
		tidyLegacyStage(dt)
		if hudDemo then
			local Hud = cx.modules and cx.modules.Hud
			if Hud then hudFrame.dt = dt; pcall(Hud.update, hudFrame) end
			local w = workspace:FindFirstChild("FightingLabWorld")
			local arenas = w and w:FindFirstChild("Arenas")
			local arena = arenas and arenas:FindFirstChild("Arena_MidnightRooftop")
			local origin = arena and arena:FindFirstChild("FightOrigin")
			local cam = workspace.CurrentCamera
			if hudCamera and origin and origin:IsA("BasePart") and cam then
				cam.CameraType = Enum.CameraType.Scriptable
				cam.FieldOfView = 46
				cam.CFrame = CFrame.lookAt(origin.Position + Vector3.new(0, 4.2, 14), origin.Position + Vector3.new(0, 3, 0))
			end
		end
		local now = workspace:GetServerTimeNow()
		-- Countdown scenes: keep cycling 3-2-1 or hold one digit so captures can catch it.
		if session._state == "Countdown" and (cycling or holdDigit) then
			local info = session._info
			if typeof(info) == "table" and typeof(info.endsAt) == "number" then
				local remaining = info.endsAt - now
				-- Changed payloads are copied by the BindableEvent, so a moved deadline is re-announced.
				if holdDigit and remaining < holdDigit - 0.85 then
					info.endsAt = now + holdDigit - 0.5; station("Arena_MidnightRooftop"):SetAttribute("CountdownEndsAt", info.endsAt)
					setSession("Countdown", info)
				elseif cycling and remaining < 0.15 then
					info.endsAt = now + 3; station("Arena_MidnightRooftop"):SetAttribute("CountdownEndsAt", info.endsAt)
					setSession("Countdown", info)
				end
			end
		end
		if boardsLive then
			liveAcc += dt
			if liveAcc >= 0.2 then
				liveAcc = 0
				local t = os.clock()
				for _, cfg in (stations :: Instance):GetChildren() do
					local state = cfg:GetAttribute("State")
					if state == "Fighting" then
						cfg:SetAttribute("P1Health", 0.55 + math.sin(t * 0.7) * 0.2); cfg:SetAttribute("P2Health", 0.32 + math.cos(t * 0.9) * 0.12)
						cfg:SetAttribute("Timer", 60 - (math.floor(t) % 60))
					elseif state == "Countdown" then
						local endsAt = cfg:GetAttribute("CountdownEndsAt")
						if typeof(endsAt) == "number" and endsAt - now < 0.2 then cfg:SetAttribute("CountdownEndsAt", now + 3) end
					end
				end
			end
		end
		local viewName = gui:GetAttribute("LobbyDevView")
		local cam = workspace.CurrentCamera
		local w = workspace:FindFirstChild("FightingLabWorld")
		if typeof(viewName) ~= "string" or viewName == "" or not cam or not w then return end
		local target: BasePart? = nil
		local distance, height = 16, 0
		if viewName == "Leaderboard" then
			local l = w:FindFirstChild("Lobby")
			target = l and l:FindFirstChild("Leaderboard") :: any
			distance = 17
		elseif string.sub(viewName, 1, 6) == "Board:" or string.sub(viewName, 1, 5) == "Pads:" then
			local arenaId = string.match(viewName, ":(.+)$")
			local arenas = w:FindFirstChild("Arenas")
			local arena = arenas and arenaId and arenas:FindFirstChild(arenaId)
			if arena and string.sub(viewName, 1, 6) == "Board:" then
				target = arena:FindFirstChild("StatusBoard") :: any
				distance = 15
			elseif arena then
				local origin = arena:FindFirstChild("FightOrigin") :: BasePart?
				if origin then
					cam.CameraType = Enum.CameraType.Scriptable; cam.FieldOfView = 50
					cam.CFrame = CFrame.lookAt(origin.Position + Vector3.new(0, 12, 40), origin.Position + Vector3.new(0, 4, 0))
				end
				return
			end
		elseif viewName == "Plaza" then
			cam.CameraType = Enum.CameraType.Scriptable; cam.FieldOfView = 55
			local o = if realWorld then Vector3.zero else DevMock.ORIGIN
			cam.CFrame = if realWorld then CFrame.lookAt(Vector3.new(-6, 7, 44), Vector3.new(0, 7, -30)) else CFrame.lookAt(o + Vector3.new(0, 10, 34), o + Vector3.new(0, 6, -24))
			return
		end
		if target then
			-- Fit the board's face (with a margin) into a 40 degree view whatever its size.
			local vfov = math.rad(40)
			local aspect = cam.ViewportSize.X / math.max(1, cam.ViewportSize.Y)
			local fit = math.max(target.Size.Y / (2 * math.tan(vfov / 2)), target.Size.X / (2 * math.tan(vfov / 2) * aspect))
			distance = math.max(distance, fit * 1.12)
			cam.CameraType = Enum.CameraType.Scriptable; cam.FieldOfView = 40
			cam.CFrame = CFrame.lookAt(target.Position + target.CFrame.LookVector * distance + Vector3.new(0, height, 0), target.Position)
		end
	end

	return {
		lobby = lobby, session = session, remote = remote,
		update = update,
		stop = function()
			hudOff()
			for _, c in conns do c:Disconnect() end
			for i = #created, 1, -1 do created[i]:Destroy() end
			changed:Destroy()
			rejected:Destroy()
			setPlayer("Lobby", "", 0)
			gui:SetAttribute("LobbyDevPracticePad", nil)
			if #disabledEffects > 0 or Lighting.ClockTime == 16.6 then Lighting.ClockTime = savedClock end
			for _, e in disabledEffects do e.Enabled = true end
		end,
	}
end

--------------------------------------------------------------------------------------------------------------------
-- Front end
--------------------------------------------------------------------------------------------------------------------
local function c(): Ctx
	local v = ctx
	if not v then error("FrontEnd.init first") end
	return v
end

function M.start()
	if started then return end
	started = true
	local cx = c()
	LobbyUI.start(cx)
	local tracker = LobbyCamera.new()
	returnCamera = tracker
	local fightSession = cx.modules and cx.modules.FightSession
	local teleport = fightSession and fightSession.Teleport
	if typeof(teleport) == "RBXScriptSignal" then
		teleport:Connect(function(payload: any) tracker.onTeleport(payload, os.clock()) end)
	end
	if RunService:IsStudio() then
		local function sync()
			local want = cx.gui:GetAttribute("LobbyDevMock") == true
			if want and not mock then
				mock = DevMock.start(cx)
			elseif not want and mock then
				mock.stop()
				mock = nil
				LobbyUI.start(cx)
			end
		end
		cx.gui:GetAttributeChangedSignal("LobbyDevMock"):Connect(sync)
		sync()
	end
end

function M.onSnapshot(entry: any)
	-- The dev mock's fake session feeds the lobby itself; real snapshots then belong to another match.
	if mock then return end
	LobbyUI.onSnapshot(entry)
end

function M.update(frame: any)
	LobbyUI.update(frame)
	if mock then mock.update(frame) end
	local tracker = returnCamera
	if tracker and not mock and typeof(frame) == "table" and typeof(frame.session) == "string" then
		tracker.step(frame.session, os.clock())
	end
end

function M.init(newCtx: Ctx)
	ctx = newCtx
end

-- Roster ids the lobby UI can show (handy for tools and tests).
function M.fighters(): { string }
	return table.clone(Roster.order)
end

return M
