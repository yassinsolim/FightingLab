--!strict
-- FightingLab lobby UI (OV6). Lobby HUD (identity card, objective hint, toasts, duel countdown, result card), world
-- prompts (every lobby interaction is an E ProximityPrompt: Fighter Kiosk "Choose Fighter", duel circle "Fight CPU"
-- once waiting alone, dojo pads "Start Training" / "Versus CPU", all drawn with one custom prompt style), pickers
-- (CPU difficulty, dojo setup), the practice panel and the guided practice lesson, and the [Tab] lobby menu
-- (Fighters, How to Play, Move List, Settings, Credits). Every key it shows comes from FightingLab.Controls.
-- It only reads server state (Player attributes, Stations, FightSession) and only talks to the server through the
-- Lobby remote / FightSession. mount(env) takes an injectable environment so LobbyUI_Test can drive every state on
-- the server without a client.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local SoundService = game:GetService("SoundService")
local StarterGui = game:GetService("StarterGui")
local GuiService = game:GetService("GuiService")

local Client = script.Parent
local Lab = Client.Parent
local UIHelpers = require(Client.UIHelpers)
local UIState = require(Client.UIState)
local MoveList = require(Client.MoveList)
local CreditsScreen = require(Client.CreditsScreen)
local FighterSelect = require(Client.FighterSelect)
local StationBoards = require(Client.StationBoards)
local Leaderboard = require(Client.Leaderboard)
local Roster = require(Lab.Roster)

local T = UIHelpers.Theme
local make, text = UIHelpers.make, UIHelpers.text
local WHITE = Color3.new(1, 1, 1)

local LobbyUI = {}
LobbyUI.RESULT_SECONDS = 7
LobbyUI.TOAST_SECONDS = 5.5
LobbyUI.MAX_TOASTS = 3
LobbyUI.FEED_SETTLE = 0.3
LobbyUI.MENU_PAGES = { "Fighters", "HowToPlay", "Moves", "Settings", "Credits" }
LobbyUI.PAGE_ALIASES = { Fighter = "Fighters", Controls = "HowToPlay", Help = "HowToPlay" } :: { [string]: string }
LobbyUI.PROMPT_ATTRIBUTE = "FightingLabPrompt"
-- Practice panel: it folds into a one-line strip while the player fights. Opened by the pause key (or a click / tap
-- on the strip) it is a pause menu; opened on entering practice it folds after this long without use, or at once on
-- any fight input.
LobbyUI.PANEL_IDLE_SECONDS = 4
LobbyUI.PANEL_START_SECONDS = 6

export type Env = {
	player: Instance, -- Players.LocalPlayer (a Folder with attributes in tests)
	parent: Instance, -- PlayerGui (a test container in tests)
	hud: Instance?, -- FightingLabHUD: CameraShakeDisabled / ControlsGuide attributes (settings)
	modules: { [string]: any }?, -- ctx.modules (FightSession, Characters, Audio, Input)
	session: any?, -- FightSession override (dev mock, tests)
	remote: any?, -- Lobby RemoteEvent or a double with FireServer
	stations: (() -> Instance?)?,
	world: (() -> Instance?)?,
	serverNow: (() -> number)?,
	characterRoot: (() -> BasePart?)?,
	practicePad: (() -> string?)?, -- override of the dojo pad detection (dev mock, tests)
	previews: boolean?, -- 3D portraits (off in tests)
	keyboard: boolean?, -- key hints (default: keyboard present)
	live: boolean?, -- Heartbeat, keyboard, prompt and station wiring (off in tests)
	controls: any?, -- PlayerModule controls override
	userId: number?,
	onLocalArena: ((arenaId: string?) -> ())?, -- arena of the local player's fight/practice (nil in the lobby)
	device: (() -> string)?, -- input device override ("keyboard" | "gamepad" | "touch")
	clock: (() -> number)?, -- time source of the practice panel timers (tests); os.clock by default
}

export type Controller = {
	gui: ScreenGui,
	view: () -> UIState.LobbyView,
	refresh: () -> (),
	tick: (dt: number) -> (),
	handleKey: (key: Enum.KeyCode) -> boolean,
	openMenu: (page: string?) -> (),
	closeMenu: () -> (),
	isMenuOpen: () -> boolean,
	menuPage: () -> string,
	openFighterSelect: (id: string?) -> boolean,
	fighterSelect: () -> any,
	requestCpu: (difficulty: string?) -> boolean,
	startPractice: (opts: { [string]: any }?) -> boolean,
	practiceCommand: (kind: string, arg: any?) -> (),
	leavePractice: () -> (),
	showResult: (result: any) -> (),
	resultVisible: () -> boolean,
	pushToast: (title: string, body: string, color: Color3?) -> (),
	toastCount: () -> number,
	promptText: () -> (string, string, string),
	promptSpecs: () -> UIState.PromptSet,
	triggerPrompt: (id: string) -> boolean,
	worldPrompts: () -> { [string]: ProximityPrompt },
	openPicker: (kind: string) -> boolean,
	picker: () -> UIState.Picker?,
	pickerAction: (action: string) -> (),
	startLesson: () -> boolean,
	stopLesson: () -> (),
	lesson: () -> UIState.Tutorial?,
	onSnapshot: (entry: any) -> (),
	sessionChanged: (state: string, info: any?) -> (),
	syncPractice: (mode: any, dummy: any, paused: any?) -> (), -- practice snapshot fields from FightSession
	practiceState: () -> { cpu: boolean, dummy: string, paused: boolean, difficulty: string },
	panelOpen: () -> boolean, -- the full practice panel is shown (else its strip)
	setPanelOpen: (open: boolean) -> (), -- show / fold the panel without pausing
	togglePanel: () -> (), -- the strip / fold button: open as a pause menu, or fold (and resume)
	localArena: () -> string?, -- arena whose board/pad tags the local fight camera must not see
	settings: () -> { [string]: any },
	setSetting: (name: string, value: any) -> (),
	setSuppressed: (on: boolean) -> (), -- hide the HUD regardless of state (cutscenes, captures)
	destroy: () -> (),
}

type Result = { outcome: string, opponent: string, opponentFighter: string?, arena: string, rounds: string?, cpu: boolean, difficulty: string?, key: string }

-- FightSession.Rejected payloads ({request, reason}) shown as a toast.
local REJECT_TITLES: { [string]: string } = {
	RequestCpu = "NO CPU YET", SelectFighter = "FIGHTER NOT CHANGED", StartPractice = "PRACTICE UNAVAILABLE",
}
local REJECT_TEXT: { [string]: string } = {
	Busy = "Finish your current match first.", TooFast = "One moment - you just switched.",
	NotWaiting = "Stand on a duel circle first.", NotAlone = "A challenger is already here!",
	TooSoon = "Keep waiting a few seconds for a challenger.", NotOnPad = "Stand on a practice circle first.",
	Invalid = "That request was not recognised.",
}
LobbyUI.REJECT_TITLES = REJECT_TITLES
LobbyUI.REJECT_TEXT = REJECT_TEXT

local DUMMY_MODES = { "Stand", "Guard", "Fight" }
local DUMMY_TEXT: { [string]: string } = { Stand = "STAND", Guard = "GUARD", Fight = "FIGHT BACK" }
LobbyUI.DUMMY_MODES = DUMMY_MODES
-- Fight actions (Controls "fight" group) whose keys mean the player is fighting: the practice panel folds away.
local FIGHT_ACTIONS = { "forward", "back", "sidestepIn", "sidestepOut", "crouch", "lp", "rp", "lk", "rk", "throw" }
-- Snapshot states the local fighter only reaches through its own input (covers the touch buttons too).
local INPUT_STATES: { [string]: boolean } = {
	Walk = true, Backwalk = true, Crouch = true, Dash = true, Backdash = true, Sidestep = true, Startup = true, Active = true, Recovery = true,
}

local NAV_KEYS: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.Up] = "Up", [Enum.KeyCode.W] = "Up", [Enum.KeyCode.DPadUp] = "Up",
	[Enum.KeyCode.Down] = "Down", [Enum.KeyCode.S] = "Down", [Enum.KeyCode.DPadDown] = "Down",
	[Enum.KeyCode.Left] = "Left", [Enum.KeyCode.A] = "Left", [Enum.KeyCode.DPadLeft] = "Left",
	[Enum.KeyCode.Right] = "Right", [Enum.KeyCode.D] = "Right", [Enum.KeyCode.DPadRight] = "Right",
	[Enum.KeyCode.Return] = "Confirm", [Enum.KeyCode.KeypadEnter] = "Confirm", [Enum.KeyCode.ButtonA] = "Confirm",
	[Enum.KeyCode.Backspace] = "Back", [Enum.KeyCode.ButtonB] = "Back",
}
LobbyUI.NAV_KEYS = NAV_KEYS
-- Keys some Roblox feature also binds (camera arrows, jump, player list); overlays still take them while open.
local OVERLAY_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.Left] = true, [Enum.KeyCode.Right] = true, [Enum.KeyCode.Up] = true, [Enum.KeyCode.Down] = true,
	[Enum.KeyCode.DPadLeft] = true, [Enum.KeyCode.DPadRight] = true, [Enum.KeyCode.DPadUp] = true, [Enum.KeyCode.DPadDown] = true,
	[Enum.KeyCode.ButtonA] = true, [Enum.KeyCode.ButtonB] = true, [Enum.KeyCode.Return] = true, [Enum.KeyCode.Space] = true,
	[Enum.KeyCode.W] = true, [Enum.KeyCode.A] = true, [Enum.KeyCode.S] = true, [Enum.KeyCode.D] = true,
	[Enum.KeyCode.ButtonL1] = true, [Enum.KeyCode.ButtonR1] = true,
}

local function str(v: any, default: string): string return if typeof(v) == "string" and v ~= "" then v else default end
local function hex(c: Color3): string return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)) end
LobbyUI.hex = hex

-- "Hold {fight.forward}" / "{input:df+RP}" -> rich text with the keys in gold.
local function richKeys(textValue: string, device: string?): string
	local function gold(l: string): string return '<font color="' .. hex(T.gold) .. '"><b>' .. l .. "</b></font>" end
	local withMoves = string.gsub(textValue, "{input:([^}]*)}", function(input: string)
		return gold(UIHelpers.formatMoveInput(input, device))
	end)
	return (string.gsub(withMoves, "{(%a+)%.(%a+)}", function(group: string, action: string)
		local l = UIHelpers.keyLabel(group, action, device)
		if l == "" then l = action end
		return gold(l)
	end))
end
LobbyUI.richKeys = richKeys

local function autoText(parent: Instance, name: string, value: string, font: Font, size: number, color: Color3, order: number, height: number?): TextLabel
	return text(parent, name, value, font, size, color, { Size = UDim2.fromOffset(0, height or size + 6), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = order })
end

-- Gamepad glyph of the lobby menu key (Controls.lobby.gamepad.menu; View/Select also opens the menu in the lobby).
local function menuPadLabel(): string
	local l = UIHelpers.keyLabel("lobby", "menu", "gamepad")
	return if l ~= "" then l else (UIHelpers.KEY_TEXT.ButtonSelect or "SELECT")
end

local function chip(parent: Instance, name: string, caption: string, color: Color3, order: number): TextLabel
	local f = make("Frame", { Name = name, BackgroundColor3 = color, BackgroundTransparency = 0.84, BorderSizePixel = 0, Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = order, Parent = parent })
	UIHelpers.corner(f, 3)
	make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = f })
	UIHelpers.list(f, true, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	autoText(f, "Label", caption, T.heavy, 11, color, 1, 22)
	return autoText(f, "Value", "0", T.number, 13, T.text, 2, 22)
end

--------------------------------------------------------------------------------------------------------------------
-- Prompt style: every FightingLab ProximityPrompt (Style = Custom) is drawn as an ember-edged glass pill with the
-- interact key glyph from Controls; on touch the pill itself is the button.
--------------------------------------------------------------------------------------------------------------------
local PromptStyle = {}
LobbyUI.PromptStyle = PromptStyle

function PromptStyle.isOurs(prompt: ProximityPrompt): boolean
	return prompt:GetAttribute(LobbyUI.PROMPT_ATTRIBUTE) ~= nil or prompt.Name == "ChooseFighter"
end

-- Builds the billboard for one shown prompt; returns a cleanup function.
function PromptStyle.build(prompt: ProximityPrompt, parent: Instance, device: string): () -> ()
	local adornee = prompt.Parent
	if not adornee then return function() end end
	local accent = T.ember
	local kind = prompt:GetAttribute(LobbyUI.PROMPT_ATTRIBUTE)
	if kind == "training" then accent = T.cool elseif kind == "versus" then accent = T.warm elseif kind == "kiosk" or prompt.Name == "ChooseFighter" then accent = T.gold end
	local gui: BillboardGui = make("BillboardGui", {
		Name = "FightingLabPrompt", Adornee = adornee, Size = UDim2.fromOffset(320, 72), AlwaysOnTop = true, LightInfluence = 0,
		ResetOnSpawn = false, Active = true, ClipsDescendants = false, MaxDistance = 60,
	})
	-- Pad prompts sit beside the fighter standing on the pad (not over the body); the kiosk prompt stays centred.
	if kind == "cpu" or kind == "training" or kind == "versus" then gui.SizeOffset = Vector2.new(0.62, 0.15) end
	local pill: TextButton = make("TextButton", { Name = "Pill", Text = "", AutoButtonColor = false, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(300, 60), BackgroundColor3 = T.panel, BackgroundTransparency = 0.08, BorderSizePixel = 0, Parent = gui })
	UIHelpers.corner(pill, 6)
	UIHelpers.outline(pill, WHITE, 1, 0.82)
	UIHelpers.gradient(pill, Color3.fromRGB(30, 35, 48), Color3.fromRGB(10, 12, 18), 90)
	make("Frame", { Name = "Edge", BackgroundColor3 = accent, BorderSizePixel = 0, Size = UDim2.new(0, 4, 1, 0), Parent = pill })
	local scale: UIScale = make("UIScale", { Scale = 0.8, Parent = pill })
	local glyphBox = make("Frame", { Name = "Key", BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 0), Size = UDim2.fromOffset(46, 60), Parent = pill })
	UIHelpers.list(glyphBox, true, 0, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	if device == "touch" then
		local tap = make("Frame", { Name = "Tap", BackgroundColor3 = accent, BorderSizePixel = 0, Size = UDim2.fromOffset(40, 40), Parent = glyphBox })
		UIHelpers.corner(tap)
		text(tap, "Label", "TAP", T.heavy, 13, T.ink, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
	else
		local labelText = UIHelpers.keyLabel("lobby", "interact", device)
		if labelText == "" then labelText = UIHelpers.KEY_TEXT[prompt.KeyboardKeyCode.Name] or prompt.KeyboardKeyCode.Name end
		UIHelpers.glyph(glyphBox, labelText, { height = 38, device = device })
	end
	text(pill, "Action", string.upper(prompt.ActionText), T.title, 22, T.text, { Position = UDim2.fromOffset(72, 8), Size = UDim2.new(1, -84, 0, 28), TextTruncate = Enum.TextTruncate.AtEnd })
	text(pill, "Object", prompt.ObjectText, T.medium, 14, accent:Lerp(WHITE, 0.35), { Position = UDim2.fromOffset(73, 35), Size = UDim2.new(1, -84, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd })
	gui.Parent = parent
	UIHelpers.tween(scale, 0.18, { Scale = 1.08 }, Enum.EasingStyle.Back)
	local conns: { RBXScriptConnection } = {}
	table.insert(conns, pill.Activated:Connect(function()
		prompt:InputHoldBegin()
		task.defer(function() prompt:InputHoldEnd() end)
	end))
	table.insert(conns, prompt.Triggered:Connect(function()
		scale.Scale = 0.96
		UIHelpers.tween(scale, 0.16, { Scale = 1.08 }, Enum.EasingStyle.Back)
	end))
	table.insert(conns, prompt:GetPropertyChangedSignal("ActionText"):Connect(function()
		local a = pill:FindFirstChild("Action") :: TextLabel?
		if a then a.Text = string.upper(prompt.ActionText) end
	end))
	table.insert(conns, prompt:GetPropertyChangedSignal("ObjectText"):Connect(function()
		local o = pill:FindFirstChild("Object") :: TextLabel?
		if o then o.Text = prompt.ObjectText end
	end))
	return function()
		for _, c in conns do c:Disconnect() end
		gui:Destroy()
	end
end

-- Live: draws our prompts while shown. Returns a stop function.
function PromptStyle.start(parent: Instance, device: () -> string): () -> ()
	local shown: { [ProximityPrompt]: () -> () } = {}
	local c1 = ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
		if not PromptStyle.isOurs(prompt) then return end
		local old = shown[prompt]
		if old then old() end
		shown[prompt] = PromptStyle.build(prompt, parent, device())
	end)
	local c2 = ProximityPromptService.PromptHidden:Connect(function(prompt: ProximityPrompt)
		local cleanup = shown[prompt]
		shown[prompt] = nil
		if cleanup then cleanup() end
	end)
	return function()
		c1:Disconnect(); c2:Disconnect()
		for _, cleanup in shown do cleanup() end
		table.clear(shown)
	end
end

--------------------------------------------------------------------------------------------------------------------
-- World prompts: one local ProximityPrompt per duel circle ("Fight CPU"), one per dojo pad, and the kiosk prompt (the
-- world's own server prompt when present, restyled locally; else a local one). Enabled per UIState.prompts.
--------------------------------------------------------------------------------------------------------------------
type WorldPrompts = { sync: (specs: UIState.PromptSet, arenaId: string?, padSide: number?) -> (), all: () -> { [string]: ProximityPrompt }, destroy: () -> () }

local function newPrompt(parent: Instance, name: string, kind: string, distance: number): ProximityPrompt
	local p: ProximityPrompt = make("ProximityPrompt", {
		Name = name, HoldDuration = 0, MaxActivationDistance = distance, RequiresLineOfSight = false, Enabled = false,
		Style = Enum.ProximityPromptStyle.Custom, Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton,
	})
	p:SetAttribute(LobbyUI.PROMPT_ATTRIBUTE, kind)
	p.Parent = parent
	return p
end

local function anchorOn(part: BasePart, height: number): Attachment
	local existing = part:FindFirstChild("FightingLabPromptAnchor")
	if existing and existing:IsA("Attachment") then return existing end
	local a: Attachment = make("Attachment", { Name = "FightingLabPromptAnchor" })
	-- Pads are rotated cylinders: place the anchor in world space above the pad centre.
	a.Position = part.CFrame:PointToObjectSpace(part.Position + Vector3.new(0, height, 0))
	a.Parent = part
	return a
end

local function applyKeys(p: ProximityPrompt)
	local kb = UIHelpers.keyCodes("lobby", "interact", "keyboard")[1]
	local gp = UIHelpers.keyCodes("lobby", "interact", "gamepad")[1]
	if kb then p.KeyboardKeyCode = kb end
	if gp then p.GamepadKeyCode = gp end
end

function LobbyUI.worldPrompts(world: () -> Instance?): WorldPrompts
	local created: { Instance } = {}
	local kiosk: ProximityPrompt? = nil
	local kioskOwned = false
	local pads: { [string]: ProximityPrompt } = {} -- "<ArenaId>:<side>" -> Fight CPU prompt
	local dojo: { [string]: { ProximityPrompt } } = { training = {}, versus = {} }
	local dojoPads: { [Instance]: ProximityPrompt } = {}
	local lastScan = -math.huge
	local scannedWorld: Instance? = nil
	local function scan()
		local w = world()
		if not w then return end
		if w == scannedWorld and os.clock() - lastScan < 3 then return end
		lastScan = os.clock()
		scannedWorld = w
		local lobby = w:FindFirstChild("Lobby")
		local kioskModel = lobby and lobby:FindFirstChild("FighterKiosk")
		local promptPart = kioskModel and kioskModel:FindFirstChild("PromptPart")
		if promptPart and promptPart:IsA("BasePart") and (not kiosk or not kiosk.Parent) then
			local existing = promptPart:FindFirstChild("ChooseFighter")
			if existing and existing:IsA("ProximityPrompt") then
				kiosk = existing
				kioskOwned = false
			else
				kiosk = newPrompt(promptPart, "ChooseFighter", "kiosk", 10)
				kioskOwned = true
				table.insert(created, kiosk :: Instance)
			end
			local k = kiosk :: ProximityPrompt
			k.Style = Enum.ProximityPromptStyle.Custom
			k.ActionText = UIState.PROMPT_TEXT.kiosk.action
			k.ObjectText = UIState.PROMPT_TEXT.kiosk.object
			applyKeys(k)
		end
		local arenas = w:FindFirstChild("Arenas")
		if not arenas then return end
		for _, arena in arenas:GetChildren() do
			local kind = arena:GetAttribute("Kind")
			if kind == "Practice" then
				for _, spec in { { "PadTraining", "training" }, { "PadCpu", "versus" } } do
					local pad = arena:FindFirstChild(spec[1])
					if pad and pad:IsA("BasePart") and not dojoPads[pad] then
						local mode = pad:GetAttribute("PadMode")
						local id = if mode == "Cpu" then "versus" elseif mode == "Training" then "training" else spec[2]
						local anchor = anchorOn(pad, 3.2)
						local p = newPrompt(anchor, "FightingLab_" .. id, id, 9)
						applyKeys(p)
						table.insert(created, anchor)
						table.insert(dojo[id], p)
						dojoPads[pad] = p
					end
				end
			else
				for side, padName in { "PadP1", "PadP2" } do
					local key = arena.Name .. ":" .. side
					local pad = arena:FindFirstChild(padName)
					if pad and pad:IsA("BasePart") and (not pads[key] or not pads[key].Parent) then
						local anchor = anchorOn(pad, 3.2)
						local p = newPrompt(anchor, "FightingLab_FightCpu", "cpu", 9)
						applyKeys(p)
						table.insert(created, anchor)
						pads[key] = p
					end
				end
			end
		end
	end
	local function set(p: ProximityPrompt, spec: UIState.PromptSpec, enabled: boolean)
		if p.Enabled ~= enabled then p.Enabled = enabled end
		if p.ActionText ~= spec.action then p.ActionText = spec.action end
		if p.ObjectText ~= spec.object then p.ObjectText = spec.object end
	end
	return {
		sync = function(specs: UIState.PromptSet, arenaId: string?, padSide: number?)
			scan()
			if kiosk and kiosk.Parent then set(kiosk, specs.kiosk, specs.kiosk.enabled) end
			for key, p in pads do
				local mine = arenaId ~= nil and key == arenaId .. ":" .. tostring(padSide)
				set(p, specs.cpu, specs.cpu.enabled and mine)
			end
			for _, p in dojo.training do set(p, specs.training, specs.training.enabled) end
			for _, p in dojo.versus do set(p, specs.versus, specs.versus.enabled) end
		end,
		all = function()
			local out: { [string]: ProximityPrompt } = {}
			if kiosk then out.kiosk = kiosk end
			for key, p in pads do out["cpu:" .. key] = p end
			for i, p in dojo.training do out["training:" .. i] = p end
			for i, p in dojo.versus do out["versus:" .. i] = p end
			return out
		end,
		destroy = function()
			if kiosk and not kioskOwned then kiosk.Style = Enum.ProximityPromptStyle.Default; kiosk.Enabled = true end
			for i = #created, 1, -1 do created[i]:Destroy() end
			table.clear(created); table.clear(pads); table.clear(dojoPads)
			table.clear(dojo.training); table.clear(dojo.versus)
			kiosk = nil
		end,
	}
end

--------------------------------------------------------------------------------------------------------------------
-- Mount
--------------------------------------------------------------------------------------------------------------------
function LobbyUI.mount(env: Env): Controller
	local player = env.player
	local live = env.live == true
	local previewsOn = env.previews ~= false
	local keyboard = if env.keyboard ~= nil then env.keyboard else (UserInputService.KeyboardEnabled or not UserInputService.TouchEnabled)
	local touchOnly = not keyboard
	local serverNow = env.serverNow or function() return workspace:GetServerTimeNow() end
	local clock: () -> number = env.clock or os.clock
	local conns: { RBXScriptConnection } = {}
	local statConns: { RBXScriptConnection } = {}
	local stationConns: { [Instance]: RBXScriptConnection } = {}
	local destroyed = false
	local controller: Controller

	-- Mutable state shared by the builders below (one table keeps the main function's locals in check).
	local S = {
		sessionState = "Lobby", sessionHooked = nil :: any, sessionConn = nil :: RBXScriptConnection?, rejectConn = nil :: RBXScriptConnection?,
		countdownInfo = nil :: any, matchInfo = nil :: any, pendingEnd = nil :: any, queuedSince = nil :: number?,
		practicePad = nil :: string?, cpuPendingUntil = 0, lastCpuRequest = -math.huge, lastDigit = nil :: number?,
		menuOpen = false, menuPage = "Fighters", frozen = false, owedEnable = false, gameplayPaused = false,
		resultUntil = 0, resultShownKey = "", suppressed = false, dots = 3,
		practiceCpu = false, dummy = "Stand", paused = false, practiceDifficulty = "Normal", pendingLesson = false,
		panelOpen = false, panelUntil = 0, panelPausedSeen = false, stripFlash = nil :: string?, stripFlashUntil = 0,
		lesson = nil :: UIState.Tutorial?, lessonDummy = "", picker = nil :: UIState.Picker?, pickerRefresh = nil :: (() -> ())?,
		identityId = nil :: string?, portraitToken = 0, portraitRelease = nil :: (() -> ())?, device = "keyboard",
		notifiedArena = "?" :: string?, stationSnapshot = nil :: { [string]: any }?,
		lastDuel = player:GetAttribute("DuelState"), lastArena = player:GetAttribute("ArenaId"),
	}
	local view: UIState.LobbyView = UIState.lobbyView({})
	local settings = { cameraShake = true, music = 1, sfx = 1, guide = "Auto", duelFeed = true }
	local toasts: { { frame: Frame, expires: number } } = {}
	local stationSeen: { [Instance]: { state: string, resultKey: string, waitingAt: number, pending: boolean } } = {}
	local deviceListeners: { (string) -> () } = {}

	local function attr(name: string): any return player:GetAttribute(name) end
	local function myUserId(): number
		if env.userId then return env.userId end
		if player:IsA("Player") then return player.UserId end
		local v = player:GetAttribute("UserId")
		return if typeof(v) == "number" then v else 0
	end
	local function modules(): { [string]: any } return env.modules or {} end
	local function session(): any
		if env.session then return env.session end
		return modules().FightSession
	end
	local function sound(name: string)
		local audio = modules().Audio
		if audio and audio.play then pcall(audio.play, name) end
	end
	local function device(): string
		if env.device then return env.device() end
		if touchOnly then return "touch" end
		if not live then return "keyboard" end
		return UIHelpers.inputDevice()
	end
	-- Glyph device: touch shows no keys; gamepad shows pad glyphs.
	local function glyphDevice(): string
		local d = S.device
		return if d == "gamepad" then "gamepad" else "keyboard"
	end
	local function onDevice(fn: (string) -> ()) table.insert(deviceListeners, fn) end
	local function stationsFolder(): Instance? return if env.stations then env.stations() else nil end
	local function worldFolder(): Instance? return if env.world then env.world() else nil end
	local function stationFor(arenaId: any): Instance?
		if typeof(arenaId) ~= "string" or arenaId == "" then return nil end
		local folder = stationsFolder()
		return folder and folder:FindFirstChild(arenaId) or nil
	end
	local function arenaName(arenaId: any): string
		local station = stationFor(arenaId)
		local name = station and station:GetAttribute("DisplayName")
		if typeof(name) == "string" and name ~= "" then return name end
		local world = worldFolder()
		local arenas = world and world:FindFirstChild("Arenas")
		local arena = arenas and typeof(arenaId) == "string" and arenas:FindFirstChild(arenaId)
		local display = arena and arena:GetAttribute("DisplayName")
		if typeof(display) == "string" and display ~= "" then return display end
		if typeof(arenaId) == "string" and arenaId ~= "" then return (string.gsub(string.gsub(arenaId, "^Arena_", ""), "(%l)(%u)", "%1 %2")) end
		return "the arena"
	end
	local function fighterId(): string
		local id = attr("FighterId")
		if UIHelpers.fighterDef(Roster, id) then return id end
		return Roster.order[1]
	end
	local function playerName(): string
		if player:IsA("Player") then return player.DisplayName end
		return str(player:GetAttribute("DisplayName"), player.Name)
	end
	local function fire(kind: string, payload: any): boolean
		local remote = env.remote
		if not remote then warn("FightingLab lobby: Lobby remote is not available yet (" .. kind .. ")"); return false end
		local ok, err = pcall(function() remote:FireServer(kind, payload) end)
		if not ok then warn("FightingLab lobby: " .. kind .. " failed: " .. tostring(err)) end
		return ok
	end
	S.device = device()

	-- Root -----------------------------------------------------------------------------------------------------------
	local gui: ScreenGui = make("ScreenGui", {
		Name = "FightingLabLobby", ResetOnSpawn = false, DisplayOrder = 10, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets, Parent = env.parent,
	})
	local stage: Frame = make("Frame", { Name = "Stage", BackgroundTransparency = 1, Parent = gui })
	local unfit = UIHelpers.fitToScreen(gui, stage, touchOnly)

	-- Identity card (top-left) ------------------------------------------------------------------------------------
	local H: { [string]: any } = {}
	do
		local identity: Frame = make("Frame", { Name = "Identity", BackgroundColor3 = T.panel, BackgroundTransparency = 0.04, BorderSizePixel = 0, Position = UDim2.fromOffset(20, 18), Size = UDim2.fromOffset(332, 104), Parent = stage })
		UIHelpers.gradient(identity, Color3.fromRGB(28, 33, 46), Color3.fromRGB(10, 12, 18), 90)
		UIHelpers.corner(identity, 6)
		UIHelpers.outline(identity, WHITE, 1, 0.86)
		H.identity = identity
		H.accentBar = UIHelpers.accentBar(identity, T.gold, 4)
		local portrait: Frame = make("Frame", { Name = "Portrait", BackgroundColor3 = WHITE, BorderSizePixel = 0, ClipsDescendants = true, Position = UDim2.fromOffset(14, 13), Size = UDim2.fromOffset(78, 78), Parent = identity })
		UIHelpers.corner(portrait, 5)
		H.portraitGradient = UIHelpers.gradient(portrait, Color3.fromRGB(60, 44, 30), Color3.fromRGB(12, 14, 22), 90)
		H.portraitStroke = UIHelpers.outline(portrait, T.gold, 2, 0)
		local pvp, pcam, pworld = FighterSelect.newViewport(portrait, "Bust")
		pvp.ZIndex = 2
		H.pvp, H.pcam, H.pworld = pvp, pcam, pworld
		local pcover: Frame = make("Frame", { Name = "Cover", BackgroundColor3 = WHITE, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = portrait })
		H.pcover = pcover
		H.pcoverGradient = UIHelpers.gradient(pcover, Color3.fromRGB(90, 60, 30), Color3.fromRGB(14, 16, 26), 90)
		H.pmono = text(pcover, "Monogram", "", T.display, 46, T.gold, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })
		H.playerLabel = text(identity, "Player", "", T.heavy, 12, T.muted, { Position = UDim2.fromOffset(106, 10), Size = UDim2.fromOffset(216, 16), TextTruncate = Enum.TextTruncate.AtEnd })
		H.fighterLabel = text(identity, "Fighter", "", T.display, 32, T.text, { Position = UDim2.fromOffset(104, 23), Size = UDim2.fromOffset(250, 38) })
		H.styleLabel = text(identity, "Style", "", T.medium, 13, T.muted, { Position = UDim2.fromOffset(106, 60), Size = UDim2.fromOffset(216, 16), TextTruncate = Enum.TextTruncate.AtEnd })
		local statsRow = make("Frame", { Name = "Stats", BackgroundTransparency = 1, Position = UDim2.fromOffset(106, 78), Size = UDim2.fromOffset(246, 22), Parent = identity })
		UIHelpers.list(statsRow, true, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
		H.winsValue = chip(statsRow, "WINS", "WINS", T.gold, 1)
		H.streakValue = chip(statsRow, "STREAK", "STREAK", T.ember, 2)
	end

	-- Menu button (under the identity card) -------------------------------------------------------------------------
	local menuButtonHolder: Frame = make("Frame", { Name = "MenuButtonHolder", BackgroundTransparency = 1, Position = UDim2.fromOffset(20, 130), Size = UDim2.fromOffset(170, 40), Parent = stage })
	local menuButton: UIHelpers.Button? = nil
	local function buildMenuButton()
		if menuButton then menuButton.button:Destroy() end
		local d = S.device
		local glyphs = if d == "touch" then {} else { UIHelpers.keyLabel("lobby", "menu", "keyboard") }
		if d == "gamepad" then glyphs = { menuPadLabel() } end
		local b = UIHelpers.button(menuButtonHolder, "MenuButton", { text = "MENU", size = UDim2.fromOffset(if d == "touch" then 120 else 150, 40), glyphs = glyphs, device = glyphDevice(), textSize = 16, glyphHeight = 22 })
		menuButton = b
		table.insert(conns, b.button.Activated:Connect(function()
			if S.menuOpen then controller.closeMenu() else controller.openMenu(nil) end
		end))
	end
	buildMenuButton()
	onDevice(function() buildMenuButton() end)

	-- Toast feed (top centre) ----------------------------------------------------------------------------------------
	local toastStack: Frame = make("Frame", { Name = "Toasts", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 18), Size = UDim2.fromOffset(420, 220), Parent = stage })
	UIHelpers.list(toastStack, false, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)

	-- Objective hint (bottom centre) ---------------------------------------------------------------------------------
	local prompt: Frame = make("Frame", { Name = "Prompt", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, if touchOnly then -112 else -22), Size = UDim2.fromOffset(640, 70), Parent = stage })
	do
		local pill: Frame = make("Frame", { Name = "Pill", BackgroundColor3 = T.panel, BackgroundTransparency = 0.1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = prompt })
		UIHelpers.gradient(pill, Color3.fromRGB(26, 31, 44), Color3.fromRGB(9, 11, 17), 90)
		UIHelpers.corner(pill, 6)
		UIHelpers.outline(pill, WHITE, 1, 0.86)
		H.pill = pill
		H.pillEdge = UIHelpers.accentBar(pill, T.gold, 4)
		local ring: Frame = make("Frame", { Name = "Ring", BackgroundColor3 = T.gold, BackgroundTransparency = 0.86, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 20, 0.5, 0), Size = UDim2.fromOffset(38, 38), Parent = pill })
		UIHelpers.corner(ring)
		H.ring = ring
		H.ringStroke = UIHelpers.outline(ring, T.gold, 3, 0)
		H.ringDot = make("Frame", { Name = "Dot", BackgroundColor3 = T.gold, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(12, 12), Parent = ring })
		UIHelpers.corner(H.ringDot)
		H.ringScale = make("UIScale", { Parent = ring })
		H.promptTitle = text(pill, "Title", "", T.title, 21, T.text, { Position = UDim2.fromOffset(74, 10), Size = UDim2.new(1, -90, 0, 28), TextTruncate = Enum.TextTruncate.AtEnd })
		H.promptSub = text(pill, "Subtitle", "", T.medium, 14, T.muted, { Position = UDim2.fromOffset(75, 40), Size = UDim2.new(1, -90, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd })
		-- Action line (CPU offer / dojo pad): interact glyph + what it does; replaces the subtitle while shown.
		local offer: Frame = make("Frame", { Name = "Offer", BackgroundTransparency = 1, Position = UDim2.fromOffset(75, 37), Size = UDim2.new(1, -90, 0, 24), Visible = false, Parent = pill })
		UIHelpers.list(offer, true, 7, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
		H.offer = offer
		H.offerGlyph = make("Frame", { Name = "Glyph", BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 1, Parent = offer })
		H.offerText = autoText(offer, "Text", "", T.heavy, 15, T.gold, 2, 24)
		local progressBack: Frame = make("Frame", { Name = "Progress", BackgroundColor3 = T.slot, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 74, 1, -6), Size = UDim2.new(1, -94, 0, 3), Visible = false, Parent = pill })
		H.progressBack = progressBack
		H.progressFill = make("Frame", { Name = "Fill", BackgroundColor3 = T.gold, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), Parent = progressBack })
	end
	local function paintOfferGlyph()
		for _, c in H.offerGlyph:GetChildren() do c:Destroy() end
		if S.device ~= "touch" then
			UIHelpers.glyph(H.offerGlyph, UIHelpers.keyLabel("lobby", "interact", glyphDevice()), { height = 24, device = glyphDevice() })
		end
	end
	paintOfferGlyph()
	onDevice(function() paintOfferGlyph() end)

	-- Countdown (centre) ---------------------------------------------------------------------------------------------
	local countdown: Frame = make("Frame", { Name = "Countdown", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(560, 380), Visible = false, Parent = stage })
	do
		H.cdTitle = text(countdown, "Title", "DUEL STARTING", T.title, 26, T.gold, { Size = UDim2.fromOffset(560, 34), TextXAlignment = Enum.TextXAlignment.Center })
		UIHelpers.textStroke(H.cdTitle, 0.35, 2)
		H.cdVersus = text(countdown, "Versus", "", T.heavy, 20, T.text, { Position = UDim2.fromOffset(0, 38), Size = UDim2.fromOffset(560, 26), TextXAlignment = Enum.TextXAlignment.Center })
		UIHelpers.textStroke(H.cdVersus, 0.4, 2)
		local ring: Frame = make("Frame", { Name = "Ring", BackgroundColor3 = T.bg, BackgroundTransparency = 0.12, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 78), Size = UDim2.fromOffset(196, 196), Parent = countdown })
		UIHelpers.corner(ring)
		local ringStroke = UIHelpers.outline(ring, WHITE, 6, 0)
		H.cdRingGradient = make("UIGradient", { Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, T.ember), ColorSequenceKeypoint.new(0.5, T.gold), ColorSequenceKeypoint.new(1, T.ember) }), Parent = ringStroke })
		H.cdDigit = text(ring, "Digit", "3", T.display, 138, T.text, { Size = UDim2.fromScale(1, 1), Position = UDim2.fromOffset(-4, -4), TextXAlignment = Enum.TextXAlignment.Center })
		UIHelpers.textStroke(H.cdDigit, 0.3, 3)
		H.cdScale = make("UIScale", { Parent = ring })
		local seq = make("Frame", { Name = "Sequence", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 286), Size = UDim2.fromOffset(560, 40), Parent = countdown })
		UIHelpers.list(seq, true, 18, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
		H.cdSteps = {}
		for i, n in { 3, 0, 2, 0, 1 } do
			local l = autoText(seq, if n == 0 then "Dot" .. i else "Step" .. n, if n == 0 then "\u{00B7}" else tostring(n), T.display, 30, T.dim, i, 38)
			UIHelpers.textStroke(l, 0.5, 2)
			if n > 0 then H.cdSteps[n] = l end
		end
		H.cdHint = text(countdown, "Hint", "Step off the circle to cancel", T.bold, 17, T.muted, { Position = UDim2.fromOffset(0, 334), Size = UDim2.fromOffset(560, 22), TextXAlignment = Enum.TextXAlignment.Center })
		UIHelpers.textStroke(H.cdHint, 0.4, 2)
	end

	-- Result card (after a duel) ------------------------------------------------------------------------------------
	local resultCard: TextButton = make("TextButton", { Name = "Result", Text = "", AutoButtonColor = false, BackgroundColor3 = T.panel, BackgroundTransparency = 0.04, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 92), Size = UDim2.fromOffset(560, 258), Visible = false, ClipsDescendants = true, Parent = stage })
	do
		UIHelpers.gradient(resultCard, Color3.fromRGB(24, 28, 40), Color3.fromRGB(8, 10, 16), 90)
		UIHelpers.corner(resultCard, 8)
		H.resultStroke = UIHelpers.outline(resultCard, T.win, 2, 0.2)
		H.resultScale = make("UIScale", { Parent = resultCard })
		H.band = make("Frame", { Name = "Band", BackgroundColor3 = T.win, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 112), Parent = resultCard })
		make("UIGradient", { Rotation = 90, Transparency = UIHelpers.ramp({ { 0, 0.45 }, { 1, 1 } }), Parent = H.band })
		H.bandStripe = make("Frame", { Name = "Stripe", BackgroundColor3 = T.win, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 4), Parent = resultCard })
		H.outcomeLabel = text(resultCard, "Outcome", "VICTORY", T.display, 80, T.win, { Position = UDim2.fromOffset(0, 10), Size = UDim2.new(1, 0, 0, 92), TextXAlignment = Enum.TextXAlignment.Center })
		UIHelpers.textStroke(H.outcomeLabel, 0.3, 3)
		H.resultVs = text(resultCard, "Versus", "", T.heavy, 21, T.text, { Position = UDim2.fromOffset(20, 110), Size = UDim2.new(1, -40, 0, 28), TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd })
		H.resultWhere = text(resultCard, "Where", "", T.heavy, 14, T.muted, { Position = UDim2.fromOffset(20, 140), Size = UDim2.new(1, -40, 0, 20), TextXAlignment = Enum.TextXAlignment.Center })
		local resultChips = make("Frame", { Name = "Chips", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 174), Size = UDim2.new(1, 0, 0, 26), Parent = resultCard })
		UIHelpers.list(resultChips, true, 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
		H.resultStreak = chip(resultChips, "STREAK", "STREAK", T.ember, 1)
		H.resultWins = chip(resultChips, "TOTAL WINS", "TOTAL WINS", T.gold, 2)
		text(resultCard, "Hint", if touchOnly then "Tap to close" else "Click to close", T.medium, 12, T.dim, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -12), Size = UDim2.fromOffset(120, 14), TextXAlignment = Enum.TextXAlignment.Right })
		H.resultTimer = make("Frame", { Name = "Timer", BackgroundColor3 = T.win, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 20, 1, -32), Size = UDim2.new(1, -40, 0, 3), Parent = resultCard })
	end

	-- Practice panel (top right, under the fight HUD) ----------------------------------------------------------------
	-- The keyed rows are generated from Controls.legend("practice"): their order, their key glyphs (Controls.label) and
	-- their captions (the legend text, i.e. Controls.actionText). A rebinding or a renamed action therefore shows up
	-- here with no UI change, and no key can be listed for an action it no longer does. Legend texts shaped
	-- "Prefix: a / b / c" or "a / b" become chip rows (dummy behaviour, Training / Versus CPU); the easy / normal /
	-- hard rows ("CPU Easy"...) share one CPU row. Rows without a known panel action are shown as key hints only.
	-- While the player fights, the panel is folded into a one-line strip (see setPanelOpen below).
	local PANEL_TOP = 100 -- under the fight HUD's name rows (both GUIs share UIHelpers.fitToScreen design units)
	local practicePanel: Frame = UIHelpers.panel(stage, "PracticePanel", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, PANEL_TOP), Size = UDim2.fromOffset(292, 0), AutomaticSize = Enum.AutomaticSize.Y, Visible = false, BackgroundTransparency = 0.14 })
	UIHelpers.padding(practicePanel, 12, 12)
	UIHelpers.list(practicePanel, false, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)
	local P: { [string]: any } = { chips = {}, dummyChips = {}, modeChips = {}, modeNames = {}, legend = {}, dummyLabels = {}, levelLabels = {}, dummyPrefix = "", levelCaption = "" }
	local DIFFICULTY_ACTIONS: { [string]: string } = { easy = "Easy", normal = "Normal", hard = "Hard" }
	local PANEL_W = 268
	local function chipWidth(label: string, glyphs: number): number
		return math.max(48, math.ceil(#label * 6.4 + 18)) + glyphs * 22
	end
	-- Any use of the open panel keeps it open a little longer.
	local function panelTouch() S.panelUntil = math.max(S.panelUntil, clock() + LobbyUI.PANEL_IDLE_SECONDS) end
	local function rich(s: string): string
		return (string.gsub(string.gsub(string.gsub(s, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
	end

	-- Folded strip: training / versus, the dummy mode (or a short CPU-level flash) and the pause key that opens the
	-- full panel. A click / tap opens it as a pause menu too.
	local strip: TextButton = make("TextButton", { Name = "PracticeStrip", Text = "", AutoButtonColor = false, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, PANEL_TOP), Size = UDim2.fromOffset(0, 38), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = T.panel, BackgroundTransparency = 0.14, BorderSizePixel = 0, Visible = false, Parent = stage })
	UIHelpers.corner(strip, 5)
	UIHelpers.outline(strip, WHITE, 1, 0.82)
	local stripScale: UIScale = make("UIScale", { Parent = strip })
	local stripEdge: Frame = make("Frame", { Name = "Edge", BackgroundColor3 = T.cool, BorderSizePixel = 0, Size = UDim2.new(0, 3, 1, 0), Parent = strip })
	UIHelpers.corner(stripEdge, 2)
	local stripRow: Frame = make("Frame", { Name = "Row", BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 0), Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, Parent = strip })
	UIHelpers.list(stripRow, true, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	local SP: { [string]: any } = {}
	table.insert(conns, strip.Activated:Connect(function() controller.togglePanel() end))
	local function buildStrip(gd: string, showKeys: boolean)
		for _, c in stripRow:GetChildren() do
			if c:IsA("GuiObject") then c:Destroy() end
		end
		local mode: TextLabel = text(stripRow, "Mode", "", T.heavy, 11, T.ink, { Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 0, BackgroundColor3 = T.cool, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 1 })
		UIHelpers.corner(mode, 3)
		make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = mode })
		SP.mode = mode
		SP.info = text(stripRow, "Info", "", T.heavy, 12, T.text, { Size = UDim2.fromOffset(0, 38), AutomaticSize = Enum.AutomaticSize.X, RichText = true, LayoutOrder = 2 })
		make("Frame", { Name = "Sep", BackgroundColor3 = WHITE, BackgroundTransparency = 0.78, BorderSizePixel = 0, Size = UDim2.fromOffset(1, 18), LayoutOrder = 3, Parent = stripRow })
		local key = if showKeys then UIHelpers.keyLabel("practice", "pause", gd) else ""
		if key ~= "" then UIHelpers.glyph(stripRow, key, { height = 20, device = gd, order = 4 }) end
		SP.hint = text(stripRow, "Hint", string.upper(UIHelpers.actionText("pause")), T.heavy, 11, T.muted, { Size = UDim2.fromOffset(0, 38), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 5 })
		text(stripRow, "Chevron", "▼", T.heavy, 9, T.muted, { Size = UDim2.fromOffset(10, 38), TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 6 })
		make("Frame", { Name = "End", BackgroundTransparency = 1, Size = UDim2.fromOffset(4, 2), LayoutOrder = 7, Parent = stripRow })
	end

	local function buildPracticePanel()
		for _, c in practicePanel:GetChildren() do
			if c:IsA("GuiObject") then c:Destroy() end
		end
		table.clear(P.chips); table.clear(P.dummyChips); table.clear(P.modeChips); table.clear(P.modeNames)
		table.clear(P.dummyLabels); table.clear(P.levelLabels)
		P.dummyPrefix, P.levelCaption = "", ""
		P.reset, P.switch, P.pause, P.leave, P.dummyRow, P.level = nil, nil, nil, nil, nil, nil
		local gd = glyphDevice()
		local showKeys = S.device ~= "touch"
		buildStrip(gd, showKeys)
		local function keysFor(group: string, action: string): { string }
			if not showKeys then return {} end
			local l = UIHelpers.keyLabel(group, action, gd)
			return if l ~= "" then { l } else {}
		end
		local header = make("Frame", { Name = "Header", BackgroundTransparency = 1, Size = UDim2.fromOffset(PANEL_W, 32), LayoutOrder = 1, Parent = practicePanel })
		text(header, "Title", "PRACTICE", T.display, 24, T.text, { Size = UDim2.fromOffset(150, 32) })
		local mode: TextLabel = text(header, "Mode", "", T.heavy, 11, T.ink, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -34, 0.5, 0), Size = UDim2.fromOffset(98, 22), BackgroundTransparency = 0, BackgroundColor3 = T.cool, TextXAlignment = Enum.TextXAlignment.Center })
		UIHelpers.corner(mode, 3)
		P.mode = mode
		-- Fold back into the strip (and resume, when the panel is open as a pause menu).
		local fold: TextButton = make("TextButton", { Name = "Fold", Text = "", AutoButtonColor = false, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(28, 26), BackgroundColor3 = T.panel2, BackgroundTransparency = 0.1, BorderSizePixel = 0, Parent = header })
		UIHelpers.corner(fold, 4)
		UIHelpers.outline(fold, WHITE, 1, 0.8)
		text(fold, "Chevron", "▲", T.heavy, 10, T.text, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
		table.insert(conns, fold.Activated:Connect(function() controller.togglePanel() end))
		local order = 1
		local function nextOrder(): number order += 1; return order end
		local function row(name: string, keys: { string }, caption: string, onClick: (() -> ())?, at: number?): UIHelpers.Button
			local b = UIHelpers.button(practicePanel, name, { text = caption, size = UDim2.fromOffset(PANEL_W, 34), order = at or nextOrder(), align = "left", glyphs = keys, device = gd, textSize = 14, glyphHeight = 20 })
			if onClick then
				local fn = onClick :: () -> ()
				table.insert(conns, b.button.Activated:Connect(function() panelTouch(); fn() end))
			else
				b.setEnabled(false)
			end
			return b
		end
		-- A row of chips after an optional key glyph and caption; chips grow to fill the panel width.
		local function chipRow(name: string, keys: { string }, caption: string, chips: { { id: string, name: string, text: string, glyphs: { string }, onClick: () -> () } }, accent: Color3?): (Frame, { [string]: UIHelpers.Button })
			local holder = make("Frame", { Name = name, BackgroundTransparency = 1, Size = UDim2.fromOffset(PANEL_W, 30), LayoutOrder = nextOrder(), Parent = practicePanel })
			UIHelpers.list(holder, true, 4, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
			local used = 0
			if #keys > 0 then UIHelpers.glyphRow(holder, keys, { height = 20, device = gd, order = 0 }); used += 24 * #keys end
			if caption ~= "" then autoText(holder, "Caption", caption, T.heavy, 11, T.muted, 1, 30); used += math.ceil(#caption * 7.2) + 4 end
			local widths, total = {}, 0
			for i, c in chips do widths[i] = chipWidth(c.text, #c.glyphs); total += widths[i] end
			local free = PANEL_W - used - total - 4 * #chips
			local grow = if free > 0 and #chips > 0 then math.floor(free / #chips) else 0
			local out: { [string]: UIHelpers.Button } = {}
			for i, c in chips do
				local b = UIHelpers.button(holder, c.name, { text = c.text, size = UDim2.fromOffset(widths[i] + grow, 28), order = i + 1, textSize = 11, accent = accent or T.cool, glyphs = c.glyphs, device = gd, glyphHeight = 16 })
				local fn = c.onClick
				table.insert(conns, b.button.Activated:Connect(function() panelTouch(); fn() end))
				out[c.id] = b
			end
			return holder, out
		end
		local rows = UIHelpers.legend("practice", "keyboard")
		P.legend = rows
		local leaveRow: UIHelpers.LegendRow? = nil
		local difficultyDone = false
		for _, r in rows do
			local action = r.action
			local upper = string.upper(r.text)
			if DIFFICULTY_ACTIONS[action] then
				if not difficultyDone then
					difficultyDone = true
					-- "CPU Easy" / "CPU Normal" / "CPU Hard": the shared first word is the caption, the rest the chips.
					local group: { UIHelpers.LegendRow } = {}
					for _, other in rows do if DIFFICULTY_ACTIONS[other.action] then table.insert(group, other) end end
					local caption = string.match(group[1].text, "^(%S+)%s") or ""
					for _, g in group do if string.match(g.text, "^(%S+)%s") ~= caption then caption = "" end end
					local chips = {}
					for _, g in group do
						local d = DIFFICULTY_ACTIONS[g.action]
						local chipText = if caption ~= "" then string.sub(g.text, #caption + 2) else g.text
						P.levelLabels[d] = string.upper(chipText)
						table.insert(chips, { id = d, name = "Level" .. d, text = string.upper(chipText), glyphs = keysFor("practice", g.action), onClick = function() controller.practiceCommand("Difficulty", d) end })
					end
					P.levelCaption = string.upper(caption)
					local level, buttons = chipRow("Level", {}, string.upper(caption), chips, T.ember)
					P.level = level
					for d, b in buttons do
						b.setAccent(UIHelpers.DifficultyInfo[d].color)
						P.chips[d] = b
					end
				end
			elseif action == "dummy" then
				local prefix, options = UIHelpers.legendOptions(r.text)
				local chips = {}
				for i, m in DUMMY_MODES do
					local label = if #options == #DUMMY_MODES then string.upper(options[i]) else DUMMY_TEXT[m]
					P.dummyLabels[m] = label
					table.insert(chips, { id = m, name = "Dummy" .. m, text = label, glyphs = {}, onClick = function() controller.practiceCommand("Dummy", m) end })
				end
				P.dummyPrefix = string.upper(prefix or "")
				local holder, buttons = chipRow("Dummy", keysFor("practice", action), string.upper(prefix or ""), chips, T.cool)
				P.dummyRow = holder
				for m, b in buttons do P.dummyChips[m] = b end
			elseif action == "switchMode" then
				local prefix, options = UIHelpers.legendOptions(r.text)
				if #options == 2 then
					-- "Training / Versus CPU": both modes as chips, the current one lit; a click switches when needed.
					P.modeNames = { training = string.upper(options[1]), versus = string.upper(options[2]) }
					local chips = {
						{ id = "training", name = "ModeTraining", text = P.modeNames.training, glyphs = {}, onClick = function() if S.practiceCpu then controller.practiceCommand("SwitchMode") end end },
						{ id = "versus", name = "ModeVersus", text = P.modeNames.versus, glyphs = {}, onClick = function() if not S.practiceCpu then controller.practiceCommand("SwitchMode") end end },
					}
					local holder, buttons = chipRow("Switch", keysFor("practice", action), string.upper(prefix or ""), chips, T.warm)
					P.switch = holder
					buttons.training.setAccent(T.cool)
					buttons.versus.setAccent(T.warm)
					for id, b in buttons do P.modeChips[id] = b end
				else
					P.switch = row("Switch", keysFor("practice", action), upper, function() controller.practiceCommand("SwitchMode") end).button
				end
			elseif action == "reset" then
				P.reset = row("Reset", keysFor("practice", action), upper, function() controller.practiceCommand("Reset") end)
			elseif action == "pause" then
				P.pause = row("Pause", keysFor("practice", action), upper, function() controller.practiceCommand("Pause") end)
			elseif action == "leave" then
				leaveRow = r
			else
				-- An action this panel has no button for: still list its key so the panel never hides a binding.
				row("Hint_" .. action, keysFor("practice", action), upper, nil)
			end
		end
		-- Panel tools (not practice key bindings): fight guide key, the lesson, the menu.
		P.guide = row("Guide", keysFor("fight", "guide"), string.upper(UIHelpers.actionText("guide")), function()
			local hud = modules().Hud
			if hud and typeof(hud.toggleGuide) == "function" then pcall(hud.toggleGuide) end
		end)
		P.lesson = row("Lesson", {}, "GUIDED LESSON", function()
			if S.lesson then controller.stopLesson() else controller.startLesson() end
		end)
		P.menu = row("Menu", if gd == "keyboard" then keysFor("lobby", "menu") else {}, "MOVE LIST & MENU", function() controller.openMenu("Moves") end)
		if leaveRow then
			local lr = leaveRow :: UIHelpers.LegendRow
			P.leave = row("Leave", keysFor("practice", lr.action), string.upper(lr.text), function() controller.leavePractice() end)
		else
			P.leave = row("Leave", {}, "LEAVE PRACTICE", function() controller.leavePractice() end)
		end
	end
	buildPracticePanel()
	onDevice(function() buildPracticePanel(); if controller then controller.refresh() end end)

	-- Strip contents: mode chip from the switchMode legend, "DUMMY  GUARD" from the dummy legend (or a short
	-- "CPU  HARD" flash after a level key), the pause key from Controls.
	local function stripInfo(prefix: string, value: string): string
		if value == "" then return "" end
		if prefix == "" then return rich(value) end
		return string.format('<font color="#%s">%s</font>  %s', T.muted:ToHex(), rich(prefix), rich(value))
	end
	local function paintStrip()
		local cpu = S.practiceCpu == true
		local accent = if cpu then T.warm else T.cool
		stripEdge.BackgroundColor3 = accent
		if SP.mode then
			SP.mode.Text = if cpu then (P.modeNames.versus or "VERSUS CPU") else (P.modeNames.training or "TRAINING")
			SP.mode.BackgroundColor3 = accent
		end
		if SP.info then
			local line = ""
			if S.stripFlash and clock() < S.stripFlashUntil then
				line = S.stripFlash :: string
			elseif not cpu then
				line = stripInfo(P.dummyPrefix, P.dummyLabels[S.dummy] or DUMMY_TEXT[S.dummy] or "")
			end
			SP.info.Text = line
			SP.info.Visible = line ~= ""
		end
	end
	local function pulseStrip()
		if not live or not strip.Visible then return end
		stripScale.Scale = 1.07
		UIHelpers.tween(stripScale, 0.22, { Scale = 1 }, Enum.EasingStyle.Quint)
	end
	-- Feedback for a practice setting the strip does not show (the CPU level), without opening the panel.
	local function flashStrip(prefix: string, value: string)
		S.stripFlash = stripInfo(prefix, value)
		S.stripFlashUntil = clock() + 1.6
		paintStrip()
		pulseStrip()
	end
	-- Full panel or folded strip. Pausing opens it (a pause menu) and resuming folds it (apply() follows S.paused);
	-- open and unpaused, it folds after PANEL_IDLE_SECONDS without use or on any fight input (tick / handleKey /
	-- onSnapshot). Entering practice opens it for PANEL_START_SECONDS, except on touch screens where it would sit
	-- over the fight buttons.
	local function setPanelOpen(open: boolean)
		if S.panelOpen == open then return end
		S.panelOpen = open
		if open then S.panelUntil = clock() + LobbyUI.PANEL_IDLE_SECONDS end
		local shown = view.mode == "Practice"
		practicePanel.Visible = open and shown
		strip.Visible = shown and not open
		paintStrip()
		if not live or not shown then return end
		if open then
			practicePanel.Position = UDim2.new(1, -16, 0, PANEL_TOP - 12)
			UIHelpers.tween(practicePanel, 0.16, { Position = UDim2.new(1, -16, 0, PANEL_TOP) }, Enum.EasingStyle.Quint)
		else
			stripScale.Scale = 0.9
			UIHelpers.tween(stripScale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end
	-- Fight input (keys, or the local fighter acting in a snapshot): an open panel that is not a pause menu folds.
	local function foldForFight()
		if S.panelOpen and not S.paused then setPanelOpen(false) end
	end
	local function isFightKey(key: Enum.KeyCode): boolean
		for _, action in FIGHT_ACTIONS do
			if UIHelpers.keyMatches(key, "fight", action) then return true end
		end
		return false
	end
	-- The mouse rests on the open panel: it is being read, keep it open.
	local function pointerOnPanel(): boolean
		if not live or S.device == "touch" or not practicePanel.Visible then return false end
		local m = UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
		local p, s = practicePanel.AbsolutePosition, practicePanel.AbsoluteSize
		return m.X >= p.X and m.X <= p.X + s.X and m.Y >= p.Y and m.Y <= p.Y + s.Y
	end

	-- Lesson card (left side, below the fight HUD's bars) ------------------------------------------------------------
	local lessonCard: Frame, lessonContent: Frame = UIHelpers.edgeCard(stage, "Lesson", { Position = UDim2.new(0, 18, 0.24, 0), Size = UDim2.fromOffset(372, 0), Visible = false, BackgroundTransparency = 0.1 }, T.ember, 4, 14, 12)
	local L: { [string]: any } = {}
	do
		UIHelpers.list(lessonContent, false, 6)
		local top = make("Frame", { Name = "Top", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 1, Parent = lessonContent })
		text(top, "Caption", "GUIDED LESSON", T.heavy, 12, T.ember, { Size = UDim2.fromScale(0.6, 1) })
		L.count = text(top, "Count", "1 / 10", T.number, 12, T.muted, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromScale(0.4, 1), TextXAlignment = Enum.TextXAlignment.Right })
		local dots = make("Frame", { Name = "Dots", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 5), LayoutOrder = 2, Parent = lessonContent })
		UIHelpers.list(dots, true, 3)
		L.dots = {}
		for i = 1, 10 do
			L.dots[i] = make("Frame", { Name = "D" .. i, BackgroundColor3 = T.slot, BorderSizePixel = 0, Size = UDim2.new(0.1, -3, 1, 0), LayoutOrder = i, Parent = dots })
		end
		L.title = text(lessonContent, "Title", "", T.display, 30, T.text, { Size = UDim2.new(1, 0, 0, 38), LayoutOrder = 3 })
		L.body = text(lessonContent, "Body", "", T.medium, 15, Color3.fromRGB(220, 225, 235), { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, RichText = true, LayoutOrder = 4 })
		L.goals = make("Frame", { Name = "Goals", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 5, Parent = lessonContent })
		UIHelpers.list(L.goals, false, 4)
		L.goalRows = {}
		for i = 1, 2 do
			local r = make("Frame", { Name = "Goal" .. i, BackgroundColor3 = T.panel2, BackgroundTransparency = 0.3, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = i, Visible = false, Parent = L.goals })
			UIHelpers.corner(r, 4)
			local box = make("Frame", { Name = "Box", BackgroundColor3 = T.slot, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, 0), Size = UDim2.fromOffset(18, 18), Parent = r })
			UIHelpers.corner(box, 3)
			local tick = text(box, "Tick", "✓", T.heavy, 15, T.ink, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, Visible = false })
			local label = text(r, "Text", "", T.bold, 14, T.text, { Position = UDim2.fromOffset(34, 0), Size = UDim2.new(1, -90, 1, 0) })
			local count = text(r, "Count", "", T.number, 12, T.muted, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0), Size = UDim2.fromOffset(50, 28), TextXAlignment = Enum.TextXAlignment.Right })
			L.goalRows[i] = { frame = r, box = box, tick = tick, label = label, count = count }
		end
		local buttons = make("Frame", { Name = "Buttons", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 6, Parent = lessonContent })
		UIHelpers.list(buttons, true, 6, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
		L.skip = UIHelpers.button(buttons, "Skip", { text = "SKIP STEP", size = UDim2.fromOffset(104, 28), textSize = 12, order = 1 })
		L.stop = UIHelpers.button(buttons, "End", { text = "END LESSON", size = UDim2.fromOffset(110, 28), textSize = 12, order = 2 })
		table.insert(conns, L.skip.button.Activated:Connect(function()
			local t = S.lesson
			if t then UIState.tutorialSkip(t, os.clock()); sound("MenuMove") end
		end))
		table.insert(conns, L.stop.button.Activated:Connect(function() controller.stopLesson() end))
		L.scale = make("UIScale", { Parent = lessonCard })
	end
	local lastLessonKey = ""
	local function renderLesson()
		local t = S.lesson
		lessonCard.Visible = t ~= nil and view.mode == "Practice" and not S.suppressed
		if not t then lastLessonKey = ""; return end
		local done, total = UIState.tutorialProgress(t)
		L.count.Text = if t.done then "COMPLETE" else string.format("%d / %d", math.min(t.index, total), total)
		for i, dot in L.dots do
			dot.Visible = i <= total
			dot.BackgroundColor3 = if i <= done then T.ok elseif i == t.index and not t.done then T.ember else T.slot
		end
		if t.done then
			L.title.Text = "LESSON COMPLETE"
			L.title.TextColor3 = T.ok
			L.body.Text = richKeys("You have the basics. Press {practice.switchMode} for a CPU match, or {practice.leave} to leave.", glyphDevice())
			for _, r in L.goalRows do r.frame.Visible = false end
			L.skip.button.Visible = false
			L.stop.label.Text = "CLOSE"
		else
			local step = UIState.tutorialStep(t)
			if not step then return end
			L.title.Text = step.title
			L.title.TextColor3 = if t.stepDoneAt then T.ok else T.text
			L.body.Text = richKeys(step.text, glyphDevice())
			for i, r in L.goalRows do
				local g = step.goals[i]
				r.frame.Visible = g ~= nil
				if g then
					local complete = g.have >= g.need
					r.label.Text = g.text
					r.count.Text = if g.need > 1 and g.id ~= "forward" and g.id ~= "back" then string.format("%d/%d", g.have, g.need) elseif complete then "DONE" else ""
					r.box.BackgroundColor3 = if complete then T.ok else T.slot
					r.tick.Visible = complete
					r.label.TextColor3 = if complete then T.ok else T.text
				end
			end
			L.skip.button.Visible = true
			L.stop.label.Text = "END LESSON"
		end
		local key = tostring(t.index) .. (if t.done then "done" else "")
		if key ~= lastLessonKey then
			lastLessonKey = key
			L.scale.Scale = 0.94
			UIHelpers.tween(L.scale, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end

	-- Pickers (CPU difficulty / dojo setup), own ScreenGui above the HUD --------------------------------------------
	local pickerGui: ScreenGui = make("ScreenGui", { Name = "FightingLabPicker", ResetOnSpawn = false, DisplayOrder = 30, Enabled = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets, Parent = env.parent })
	local pickerStage: Frame = make("Frame", { Name = "Stage", BackgroundTransparency = 1, Parent = pickerGui })
	local unfitPicker = UIHelpers.fitToScreen(pickerGui, pickerStage, touchOnly)
	local K: { [string]: any } = { rows = {} }
	do
		local card: Frame, content: Frame, edge: Frame = UIHelpers.edgeCard(pickerStage, "Card", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, if touchOnly then -96 else -28), Size = UDim2.fromOffset(640, 0), BackgroundTransparency = 0.04 }, T.ember, 4, 22, 18)
		UIHelpers.list(content, false, 12, Enum.HorizontalAlignment.Center)
		K.card = card
		K.edge = edge
		local head = make("Frame", { Name = "Head", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 52), LayoutOrder = 1, Parent = content })
		K.title = text(head, "Title", "", T.display, 34, T.text, { Size = UDim2.new(1, 0, 0, 38) })
		K.sub = text(head, "Sub", "", T.medium, 15, T.muted, { Position = UDim2.fromOffset(2, 36), Size = UDim2.new(1, 0, 0, 18) })
		K.body = make("Frame", { Name = "Body", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, Parent = content })
		UIHelpers.list(K.body, false, 10, Enum.HorizontalAlignment.Center)
		K.footer = make("Frame", { Name = "Footer", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 3, Parent = content })
		UIHelpers.list(K.footer, true, 16, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
		K.scale = make("UIScale", { Parent = card })
	end
	local function pickerFooter()
		for _, c in K.footer:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
		local d = S.device
		if d ~= "touch" then
			local gp = d == "gamepad"
			local gd = if gp then "gamepad" else "keyboard"
			local kind = S.picker and S.picker.kind or "cpu"
			UIHelpers.hint(K.footer, if gp then { "←", "→" } else { "←", "→" }, if kind == "cpu" then "Difficulty" else "Change", { height = 22, device = gd, order = 1, color = T.muted, textSize = 13 })
			if kind ~= "cpu" then UIHelpers.hint(K.footer, { "↑", "↓" }, "Row", { height = 22, device = gd, order = 2, color = T.muted, textSize = 13 }) end
			UIHelpers.hint(K.footer, { if gp then "A" else "ENTER" }, if kind == "cpu" then "Fight" else "Confirm", { height = 22, device = gd, order = 3, color = T.muted, textSize = 13 })
			UIHelpers.hint(K.footer, { if gp then "B" else "BACKSPACE" }, "Cancel", { height = 22, device = gd, order = 4, color = T.muted, textSize = 13 })
		end
		local cancel = UIHelpers.button(K.footer, "Cancel", { text = "CANCEL", size = UDim2.fromOffset(96, 26), textSize = 12, order = 9 })
		table.insert(conns, cancel.button.Activated:Connect(function() controller.pickerAction("Back") end))
	end
	-- Builds the rows for the current picker kind (once per open); renderPicker() repaints them from S.picker.
	local function buildPickerRows()
		for _, c in K.body:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
		table.clear(K.rows)
		local p = S.picker
		if not p then return end
		for ri, row in p.rows do
			local refs: { [string]: any } = { id = row.id, options = {} }
			if row.id == "difficulty" and p.kind == "cpu" then
				local holder = make("Frame", { Name = "Row_difficulty", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 136), LayoutOrder = ri, Parent = K.body })
				UIHelpers.list(holder, true, 12, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
				for i, d in row.options do
					local info = UIHelpers.DifficultyInfo[d]
					local cardB: TextButton = make("TextButton", { Name = "Option_" .. d, Text = "", AutoButtonColor = false, BackgroundColor3 = T.panel2, BorderSizePixel = 0, Size = UDim2.fromOffset(186, 132), LayoutOrder = i, Parent = holder })
					UIHelpers.corner(cardB, 6)
					local stroke = UIHelpers.outline(cardB, info.color, 2, 0.75)
					make("Frame", { Name = "Strip", BackgroundColor3 = info.color, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 4), Parent = cardB })
					text(cardB, "Name", string.upper(d), T.display, 30, info.color, { Position = UDim2.fromOffset(14, 14), Size = UDim2.new(1, -28, 0, 36) })
					text(cardB, "Desc", info.text, T.medium, 13, T.muted, { Position = UDim2.fromOffset(14, 54), Size = UDim2.new(1, -28, 0, 54), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
					local sc = make("UIScale", { Parent = cardB })
					refs.options[i] = { button = cardB, stroke = stroke, scale = sc }
					table.insert(conns, cardB.Activated:Connect(function()
						controller.pickerAction("Set:difficulty:" .. i)
						controller.pickerAction("Confirm")
					end))
				end
			elseif row.kind == "cycle" then
				local holder: Frame = make("Frame", { Name = "Row_" .. row.id, BackgroundColor3 = T.panel2, BackgroundTransparency = 0.2, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 64), LayoutOrder = ri, Parent = K.body })
				UIHelpers.corner(holder, 6)
				refs.stroke = UIHelpers.outline(holder, T.ember, 2, 1)
				text(holder, "Caption", if p.kind == "training" then "DUMMY FIGHTER" else "OPPONENT", T.heavy, 12, T.muted, { Position = UDim2.fromOffset(16, 8), Size = UDim2.fromOffset(200, 14) })
				refs.mono = make("Frame", { Name = "Mono", BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 24), Size = UDim2.fromOffset(32, 32), Parent = holder })
				refs.value = text(holder, "Value", "", T.display, 28, T.text, { Position = UDim2.fromOffset(58, 22), Size = UDim2.new(1, -200, 0, 36) })
				refs.style = text(holder, "Style", "", T.medium, 13, T.muted, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -96, 0, 32), Size = UDim2.fromOffset(200, 18), TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd })
				local prev = UIHelpers.button(holder, "Prev", { text = "‹", size = UDim2.fromOffset(36, 40), textSize = 26 })
				prev.button.AnchorPoint = Vector2.new(1, 0.5); prev.button.Position = UDim2.new(1, -52, 0.5, 0)
				local nextB = UIHelpers.button(holder, "Next", { text = "›", size = UDim2.fromOffset(36, 40), textSize = 26 })
				nextB.button.AnchorPoint = Vector2.new(1, 0.5); nextB.button.Position = UDim2.new(1, -10, 0.5, 0)
				table.insert(conns, prev.button.Activated:Connect(function()
					local cur = S.picker
					if cur then local r = cur.rows[ri]; controller.pickerAction("Set:" .. row.id .. ":" .. tostring(((r.index - 2) % #r.options) + 1)) end
				end))
				table.insert(conns, nextB.button.Activated:Connect(function()
					local cur = S.picker
					if cur then local r = cur.rows[ri]; controller.pickerAction("Set:" .. row.id .. ":" .. tostring((r.index % #r.options) + 1)) end
				end))
				refs.holder = holder
			elseif row.kind == "choice" then
				local holder: Frame = make("Frame", { Name = "Row_" .. row.id, BackgroundColor3 = T.panel2, BackgroundTransparency = 0.2, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 64), LayoutOrder = ri, Parent = K.body })
				UIHelpers.corner(holder, 6)
				refs.stroke = UIHelpers.outline(holder, T.ember, 2, 1)
				text(holder, "Caption", if row.id == "lesson" then "SESSION" else "DIFFICULTY", T.heavy, 12, T.muted, { Position = UDim2.fromOffset(16, 8), Size = UDim2.fromOffset(200, 14) })
				refs.desc = text(holder, "Desc", "", T.medium, 12, T.muted, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 8), Size = UDim2.fromOffset(330, 14), TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd })
				local opts = make("Frame", { Name = "Options", BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 26), Size = UDim2.new(1, -32, 0, 30), Parent = holder })
				UIHelpers.list(opts, true, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
				for i, option in row.options do
					local caption = if option == "Free" then "FREE TRAINING" elseif option == "Lesson" then "GUIDED LESSON" else string.upper(option)
					local accent = if UIHelpers.DifficultyInfo[option] then UIHelpers.DifficultyInfo[option].color else T.ember
					local b = UIHelpers.button(opts, "Option_" .. option, { text = caption, size = UDim2.new(1 / #row.options, -6, 0, 30), order = i, textSize = 13, accent = accent })
					refs.options[i] = b
					table.insert(conns, b.button.Activated:Connect(function() controller.pickerAction("Set:" .. row.id .. ":" .. i) end))
				end
				refs.holder = holder
			else
				local b = UIHelpers.button(K.body, "Row_" .. row.id, { text = row.options[1], size = UDim2.new(1, 0, 0, 48), order = ri, primary = true, textSize = 20, font = T.title })
				refs.action = b
				table.insert(conns, b.button.Activated:Connect(function() controller.pickerAction("Go:" .. row.id) end))
			end
			K.rows[ri] = refs
		end
		pickerFooter()
	end
	local function renderPicker()
		local p = S.picker
		pickerGui.Enabled = p ~= nil and not S.suppressed
		if not p then return end
		local titles = { cpu = { "FIGHT A CPU", "No challenger yet. Pick how hard the CPU fights." }, training = { "TRAINING", "Free practice or a step-by-step lesson against a dummy." }, versus = { "VERSUS CPU", "A practice match on this dojo. Fight back with everything." } }
		local t = (titles :: any)[p.kind] or titles.cpu
		K.title.Text = t[1]
		K.sub.Text = t[2]
		K.edge.BackgroundColor3 = if p.kind == "training" then T.cool elseif p.kind == "versus" then T.warm else T.ember
		for ri, refs in K.rows do
			local row = p.rows[ri]
			local focused = ri == p.focus
			if refs.stroke then refs.stroke.Transparency = if focused then 0 else 1 end
			if row.id == "difficulty" and p.kind == "cpu" then
				for i, o in refs.options do
					local sel = i == row.index
					o.stroke.Transparency = if sel then 0 else 0.75
					o.stroke.Thickness = if sel then 3 else 2
					o.button.BackgroundColor3 = if sel then T.panel2:Lerp(UIHelpers.DifficultyInfo[row.options[i]].color, 0.16) else T.panel2
					o.scale.Scale = if sel then 1.04 else 1
				end
			elseif row.kind == "cycle" then
				local id = row.options[row.index]
				local def = UIHelpers.fighterDef(Roster, id)
				if def then
					refs.value.Text = def.displayName
					refs.value.TextColor3 = def.accentColor
					refs.style.Text = def.style
					for _, c in refs.mono:GetChildren() do c:Destroy() end
					UIHelpers.monogram(refs.mono, def, 32)
				end
			elseif row.kind == "choice" then
				for i, b in refs.options do b.setSelected(i == row.index); b.setFocused(focused and i == row.index) end
				local option = row.options[row.index]
				refs.desc.Text = if option == "Free" then "Reset anytime and choose what the dummy does" elseif option == "Lesson" then "10 short steps: movement, guard, strings, throws" elseif UIHelpers.DifficultyInfo[option] then UIHelpers.DifficultyInfo[option].text else ""
			elseif refs.action then
				refs.action.setFocused(focused)
			end
		end
	end
	S.pickerRefresh = renderPicker

	-- Lobby menu ([Tab]) — built on first open ----------------------------------------------------------------------
	local NAV: { [string]: { string } } = {
		Fighters = { "FIGHTERS", "Six original fighters" },
		HowToPlay = { "HOW TO PLAY", "Every control, keyboard or gamepad" },
		Moves = { "MOVE LIST", "Commands for every fighter" },
		Settings = { "SETTINGS", "Camera, audio, controls guide" },
		Credits = { "CREDITS", "Outfit creators, motion capture, sound" },
	}
	local Mn: any = nil -- menu refs once built
	local menuFocus = "nav"
	local pageBuilders: { [string]: (Frame) -> any } = {}

	local function sectionTitle(parent: Instance, name: string, value: string, order: number): TextLabel
		local l = text(parent, name, value, T.title, 18, T.text, { Size = UDim2.new(1, 0, 0, 26), LayoutOrder = order })
		local rule = make("Frame", { Name = "Rule", BackgroundColor3 = T.ember, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromOffset(28, 2), Parent = l })
		rule.ZIndex = 2
		return l
	end
	local function scrollFrame(parent: Instance, name: string, props: { [string]: any }?): ScrollingFrame
		local sf: ScrollingFrame = make("ScrollingFrame", {
			Name = name, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 4,
			ScrollBarImageColor3 = T.ember, Parent = parent,
		})
		if props then for k, v in props do (sf :: any)[k] = v end end
		return sf
	end
	local function scrollBy(sf: ScrollingFrame, delta: number)
		local maxY = math.max(0, sf.AbsoluteCanvasSize.Y - sf.AbsoluteWindowSize.Y)
		local y = math.clamp(sf.CanvasPosition.Y + delta, 0, maxY)
		UIHelpers.tween(sf, 0.15, { CanvasPosition = Vector2.new(0, y) })
	end

	-- Fighters ---------------------------------------------------------------------------------------------------------
	pageBuilders.Fighters = function(parent: Frame): any
		local page: Frame = make("Frame", { Name = "Page_Fighters", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = parent })
		local list = make("Frame", { Name = "List", BackgroundTransparency = 1, Size = UDim2.new(0, 252, 1, 0), Parent = page })
		UIHelpers.list(list, false, 6)
		local detail = make("Frame", { Name = "Detail", BackgroundTransparency = 1, Position = UDim2.fromOffset(276, 0), Size = UDim2.new(1, -276, 1, 0), Parent = page })
		local rows: { [string]: UIHelpers.Button } = {}
		local selected = 1
		for i, id in Roster.order do
			local def = Roster.get(id)
			local b = UIHelpers.button(list, "Fighter_" .. id, { text = "", size = UDim2.new(1, 0, 0, 56), order = i, align = "left", accent = def.accentColor })
			b.label.Visible = false
			UIHelpers.monogram(b.button, def, 38, { Position = UDim2.fromOffset(12, 9) })
			text(b.button, "Name", def.displayName, T.title, 20, T.text, { Position = UDim2.fromOffset(60, 7), Size = UDim2.new(1, -70, 0, 24) })
			text(b.button, "Style", def.style, T.medium, 12, T.muted, { Position = UDim2.fromOffset(60, 31), Size = UDim2.new(1, -70, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd })
			local tag = text(b.button, "InUse", "IN USE", T.heavy, 10, T.ink, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 6), Size = UDim2.fromOffset(46, 15), BackgroundTransparency = 0, BackgroundColor3 = T.gold, TextXAlignment = Enum.TextXAlignment.Center, Visible = false })
			UIHelpers.corner(tag, 3)
			rows[id] = b
			table.insert(conns, b.button.Activated:Connect(function() selected = i; menuFocus = "page"; sound("MenuMove"); (Mn.pages.Fighters :: any).refresh() end))
		end
		local name = text(detail, "Name", "", T.display, 64, T.text, { Size = UDim2.new(1, 0, 0, 72) })
		local style = text(detail, "Style", "", T.heavy, 15, T.gold, { Position = UDim2.fromOffset(2, 72), Size = UDim2.new(1, 0, 0, 20) })
		local tagline = text(detail, "Tagline", "", T.medium, 17, T.text, { Position = UDim2.fromOffset(2, 98), Size = UDim2.new(1, -10, 0, 44), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
		local quote = text(detail, "Quote", "", T.medium, 14, T.muted, { Position = UDim2.fromOffset(2, 144), Size = UDim2.new(1, -10, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd })
		local bars = make("Frame", { Name = "Attributes", BackgroundTransparency = 1, Position = UDim2.fromOffset(2, 176), Size = UDim2.new(1, -10, 0, 104), Parent = detail })
		UIHelpers.list(bars, false, 8)
		local setters: { (number, boolean?) -> () } = {}
		local recolors: { (Color3) -> () } = {}
		local barLabels: { TextLabel } = {}
		for i = 1, 4 do
			local r = make("Frame", { Name = "Attr" .. i, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = i, Parent = bars })
			barLabels[i] = text(r, "Label", "", T.heavy, 12, T.muted, { Size = UDim2.fromOffset(84, 20) })
			local _, set, recolor = UIHelpers.segmentBar(r, "Bar", 10, T.gold, { Position = UDim2.fromOffset(90, 5), Size = UDim2.new(1, -96, 0, 10) })
			setters[i] = set; recolors[i] = recolor
		end
		sectionTitle(detail, "SignatureTitle", "SIGNATURE MOVES", 0).Position = UDim2.fromOffset(2, 290)
		local sig = make("Frame", { Name = "Signature", BackgroundTransparency = 1, Position = UDim2.fromOffset(2, 324), Size = UDim2.new(1, -10, 0, 96), Parent = detail })
		UIHelpers.list(sig, false, 6)
		local change = UIHelpers.button(detail, "Change", { text = "CHANGE FIGHTER", size = UDim2.fromOffset(250, 48), primary = true, font = T.title, textSize = 19 })
		change.button.AnchorPoint = Vector2.new(0, 1)
		change.button.Position = UDim2.new(0, 2, 1, -4)
		local reason = text(detail, "Reason", "", T.medium, 13, T.muted, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 266, 1, -18), Size = UDim2.new(1, -270, 0, 18) })
		local shownId = ""
		local function refresh()
			local id = Roster.order[selected]
			local def = Roster.get(id)
			local current = fighterId()
			for rid, b in rows do
				b.setSelected(rid == id)
				b.setFocused(rid == id and menuFocus == "page")
				local tag = b.button:FindFirstChild("InUse") :: TextLabel?
				if tag then tag.Visible = rid == current end
			end
			change.setEnabled(view.canChooseFighter)
			change.setFocused(menuFocus == "page")
			change.label.Text = if id == current then "OPEN FIGHTER SELECT" else "CHANGE TO " .. def.displayName
			reason.Text = if view.canChooseFighter then (if S.device == "touch" then "" else "Or walk to the Fighter Kiosk") else "Available in the lobby"
			if shownId == id then return end
			shownId = id
			name.Text = def.displayName
			name.TextColor3 = def.accentColor
			style.Text = string.upper(def.style)
			style.TextColor3 = def.accentColor:Lerp(WHITE, 0.25)
			tagline.Text = def.tagline
			quote.Text = if typeof(def.intro) == "string" and def.intro ~= "" then "\u{201C}" .. def.intro .. "\u{201D}" else ""
			for i, a in UIHelpers.attributes(def) do
				barLabels[i].Text = a.name
				recolors[i](def.accentColor)
				setters[i](a.value, live)
			end
			for _, c in sig:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
			for i, key in MoveList.signature(def) do
				local mv = def.moves[key]
				local r = make("Frame", { Name = "Sig" .. i, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = i, Parent = sig })
				UIHelpers.list(r, true, 10, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
				local n = make("Frame", { Name = "In", BackgroundTransparency = 1, Size = UDim2.fromOffset(100, 26), LayoutOrder = 1, Parent = r })
				UIHelpers.list(n, true, 0, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
				UIHelpers.notationRow(n, mv.input, { height = 22 })
				autoText(r, "Name", string.upper(mv.name), T.heavy, 14, T.text, 2, 26)
			end
		end
		table.insert(conns, change.button.Activated:Connect(function()
			if view.canChooseFighter then controller.openFighterSelect(Roster.order[selected]) end
		end))
		return {
			frame = page, refresh = refresh,
			show = function() selected = table.find(Roster.order, fighterId()) or 1; shownId = ""; refresh() end,
			handle = function(action: string): boolean
				if action == "Up" or action == "Down" then
					selected = math.clamp(selected + (if action == "Up" then -1 else 1), 1, #Roster.order)
					sound("MenuMove"); refresh(); return true
				elseif action == "Confirm" then
					if view.canChooseFighter then controller.openFighterSelect(Roster.order[selected]) end
					return true
				end
				return action == "Left" or action == "Right"
			end,
		}
	end

	-- How to play ------------------------------------------------------------------------------------------------------
	pageBuilders.HowToPlay = function(parent: Frame): any
		local page: Frame = make("Frame", { Name = "Page_HowToPlay", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = parent })
		local tabs = make("Frame", { Name = "Tabs", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), Parent = page })
		UIHelpers.list(tabs, true, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
		local tabButtons: { [string]: UIHelpers.Button } = {}
		local deviceShown = if S.device == "gamepad" then "gamepad" else "keyboard"
		local body = scrollFrame(page, "Body", { Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 1, -46) })
		local function keysFor(group: string, actions: { string }, dev: string): { string }
			local out = {}
			for _, a in actions do
				local l = UIHelpers.keyLabel(group, a, dev)
				if l ~= "" and not table.find(out, l) then table.insert(out, l) end
			end
			return out
		end
		local function card(parentFrame: Instance, name: string, title: string, order: number): Frame
			local c = make("Frame", { Name = name, BackgroundColor3 = T.panel2, BackgroundTransparency = 0.35, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order, Parent = parentFrame })
			UIHelpers.corner(c, 6)
			UIHelpers.padding(c, 14, 12)
			UIHelpers.list(c, false, 7)
			sectionTitle(c, "Title", title, 0)
			return c
		end
		local function line(parentFrame: Instance, keys: { string }, caption: string, dev: string, order: number, sep: string?)
			local r = make("Frame", { Name = "Line" .. order, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = order, Parent = parentFrame })
			UIHelpers.list(r, true, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
			-- The key column is 112 wide and grows for a long key row; the caption then shrinks instead of being overlapped.
			local k = make("Frame", { Name = "Keys", BackgroundTransparency = 1, Size = UDim2.new(0, 112, 1, 0), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 1, Parent = r })
			UIHelpers.list(k, true, 4, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
			UIHelpers.glyphRow(k, keys, { height = 24, device = dev, separator = if sep == "" then nil else (sep or "/") })
			local caption_ = text(r, "Text", caption, T.bold, 15, T.text, { Size = UDim2.new(1, -120, 1, 0), LayoutOrder = 2, TextWrapped = true, RichText = true })
			make("UIFlexItem", { FlexMode = Enum.UIFlexMode.Shrink, Parent = caption_ })
		end
		local function build(dev: string)
			for _, c in body:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
			local cols = make("Frame", { Name = "Columns", BackgroundTransparency = 1, Size = UDim2.new(1, -10, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = body })
			local left = make("Frame", { Name = "Left", BackgroundTransparency = 1, Size = UDim2.new(0.5, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = cols })
			UIHelpers.list(left, false, 10)
			local right = make("Frame", { Name = "Right", BackgroundTransparency = 1, Position = UDim2.new(0.5, 6, 0, 0), Size = UDim2.new(0.5, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = cols })
			UIHelpers.list(right, false, 10)
			local move = card(left, "Move", "MOVE", 1)
			line(move, keysFor("fight", { "forward" }, dev), "Walk forward  ·  <b>double-tap</b>: dash", dev, 1)
			line(move, keysFor("fight", { "back" }, dev), "Walk back + guard  ·  <b>double-tap</b>: backdash", dev, 2)
			line(move, keysFor("fight", { "sidestepIn" }, dev), "<b>Tap</b>: sidestep into the screen", dev, 3)
			line(move, keysFor("fight", { "sidestepOut" }, dev), "<b>Tap</b>: sidestep toward the camera", dev, 4)
			line(move, keysFor("fight", { "crouch" }, dev), "<b>Hold</b>: crouch (crouch guard)", dev, 5)
			local note = text(move, "Note", "Your fighter is always on the left, so forward is always toward the opponent.", T.medium, 13, T.muted, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, LayoutOrder = 6 })
			note.TextYAlignment = Enum.TextYAlignment.Top
			local defend = card(left, "Defend", "DEFEND", 2)
			line(defend, {}, "<b>Standing guard</b>: stand still (or hold back). Blocks highs and mids.", dev, 1)
			line(defend, keysFor("fight", { "crouch" }, dev), "<b>Crouch guard</b>: blocks lows, ducks highs, takes mids.", dev, 2)
			local throwKeys = keysFor("fight", { "throw" }, dev)
			line(defend, throwKeys, "<b>Throw</b> up close" .. (if dev == "keyboard" then " (or " .. UIHelpers.keyLabel("fight", "lp", dev) .. "+" .. UIHelpers.keyLabel("fight", "lk", dev) .. " / " .. UIHelpers.keyLabel("fight", "rp", dev) .. "+" .. UIHelpers.keyLabel("fight", "rk", dev) .. ")" else "") .. ": beats guard.", dev, 3)
			line(defend, keysFor("fight", { "lp", "rp" }, dev), "<b>Throw escape</b>: press the moment you are grabbed.", dev, 4)
			local lobby = card(left, "Lobby", "LOBBY", 3)
			local ldev = if dev == "gamepad" then "gamepad" else "keyboard"
			line(lobby, if dev == "gamepad" then { "LS" } else { "W", "A", "S", "D" }, "Walk", ldev, 1, "")
			line(lobby, keysFor("lobby", { "jump" }, ldev), "Jump", ldev, 2)
			line(lobby, keysFor("lobby", { "interact" }, ldev), "Interact: Fighter Kiosk, duel circles, dojo pads", ldev, 3)
			line(lobby, if dev == "gamepad" then { menuPadLabel() } else keysFor("lobby", { "menu" }, ldev), "This menu", ldev, 4)
			line(lobby, {}, "<b>Duel</b>: walk into a glowing circle. Nobody coming? A <b>Fight CPU</b> prompt appears after a few seconds.", dev, 5)
			-- Attack pad diagram (1 2 / 3 4)
			local attack = card(right, "Attack", "ATTACK", 1)
			local pad = make("Frame", { Name = "Pad", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 132), LayoutOrder = 1, Parent = attack })
			local limbs = { { "lp", "1", "LEFT PUNCH", 0, 0 }, { "rp", "2", "RIGHT PUNCH", 1, 0 }, { "lk", "3", "LEFT KICK", 0, 1 }, { "rk", "4", "RIGHT KICK", 1, 1 } }
			for _, l in limbs do
				local cell = make("Frame", { Name = "Btn" .. l[2], BackgroundColor3 = T.bg, BackgroundTransparency = 0.25, BorderSizePixel = 0, Position = UDim2.new((l[4] :: number) * 0.5, (l[4] :: number) * 4, 0, (l[5] :: number) * 66), Size = UDim2.new(0.5, -4, 0, 60), Parent = pad })
				UIHelpers.corner(cell, 6)
				local color = UIHelpers.BUTTON_COLORS[l[2] :: string]
				UIHelpers.outline(cell, color, 1, 0.5)
				local ring = make("Frame", { Name = "Ring", BackgroundColor3 = Color3.fromRGB(16, 19, 27), BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Size = UDim2.fromOffset(38, 38), Parent = cell })
				UIHelpers.corner(ring)
				UIHelpers.outline(ring, color, 3, 0)
				text(ring, "Digit", l[2] :: string, T.number, 20, color, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
				text(cell, "Limb", l[3] :: string, T.heavy, 13, T.text, { Position = UDim2.fromOffset(58, 9), Size = UDim2.new(1, -60, 0, 18) })
				local k = make("Frame", { Name = "Key", BackgroundTransparency = 1, Position = UDim2.fromOffset(58, 29), Size = UDim2.fromOffset(60, 24), Parent = cell })
				UIHelpers.list(k, true, 4, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
				UIHelpers.glyph(k, UIHelpers.keyLabel("fight", l[1] :: string, dev), { height = 22, device = dev })
			end
			local how = text(attack, "How", "Move notation uses these numbers: <b>1,2</b> = press 1 then 2 (a string); <b>" .. UIHelpers.ARROWS.df .. "+2</b> = hold down-forward and press 2.", T.medium, 14, T.muted, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, RichText = true, LayoutOrder = 2 })
			how.TextYAlignment = Enum.TextYAlignment.Top
			line(attack, keysFor("fight", { "guide" }, dev), "Show / hide the on-screen controls guide in fights", dev, 3)
			-- Practice keys straight from Controls.legend("practice"): keys and texts, in the legend's order. Rows that
			-- share a first word ("CPU Easy", "CPU Normal", "CPU Hard") collapse into one line.
			local practice = card(right, "Practice", "PRACTICE DOJO", 2)
			local pdev = if dev == "gamepad" then "gamepad" else "keyboard"
			local prow = UIHelpers.legend("practice", pdev)
			local n, i = 0, 1
			while i <= #prow do
				local r = prow[i]
				local first = string.match(r.text, "^(%S+)%s")
				local j = i
				while first and prow[j + 1] and string.match(prow[j + 1].text, "^(%S+)%s") == first do j += 1 end
				local keys, words = {}, {}
				for k = i, j do
					local l = UIHelpers.keyLabel("practice", prow[k].action, pdev)
					if l ~= "" then table.insert(keys, l) end
					table.insert(words, if k == i then prow[k].text else string.sub(prow[k].text, #(first :: string) + 2))
				end
				n += 1
				local caption = string.gsub(string.gsub(string.gsub(table.concat(words, " / "), "&", "&amp;"), "<", "&lt;"), ">", "&gt;")
				line(practice, keys, caption, pdev, n, if j > i then " " else nil)
				i = j + 1
			end
			if pdev == "gamepad" and #prow < #UIHelpers.legend("practice", "keyboard") then
				n += 1
				line(practice, {}, "The other practice options are buttons on the practice panel.", dev, n)
			end
			-- The panel folds into a strip while you fight; the pause key (or a click / tap on the strip) opens it.
			local pauseName = string.gsub(string.gsub(UIHelpers.actionText("pause"), "&", "&amp;"), "<", "&lt;")
			n += 1
			line(practice, {}, "<b>" .. pauseName .. "</b> opens the practice panel; it folds into a strip while you fight.", dev, n)
			line(practice, {}, "Start <b>Guided Lesson</b> on the Training pad to learn step by step.", dev, n + 1)
		end
		local function select(dev: string)
			deviceShown = dev
			for id, b in tabButtons do b.setSelected(id == dev); b.setFocused(id == dev and menuFocus == "page") end
			build(dev)
		end
		for i, id in { "keyboard", "gamepad" } do
			local b = UIHelpers.button(tabs, "Tab_" .. id, { text = if id == "keyboard" then "KEYBOARD" else "GAMEPAD", size = UDim2.fromOffset(130, 32), order = i, textSize = 13 })
			tabButtons[id] = b
			table.insert(conns, b.button.Activated:Connect(function() menuFocus = "page"; sound("MenuMove"); select(id) end))
		end
		local tip = autoText(tabs, "Tip", "Touch: on-screen buttons in fights; tap prompts and menus.", T.medium, 13, T.muted, 3, 32)
		tip.Visible = S.device == "touch"
		select(deviceShown)
		return {
			frame = page,
			refresh = function() for id, b in tabButtons do b.setFocused(id == deviceShown and menuFocus == "page") end end,
			show = function() end,
			handle = function(action: string): boolean
				if action == "Left" or action == "Right" then
					select(if deviceShown == "keyboard" then "gamepad" else "keyboard"); sound("MenuMove"); return true
				elseif action == "Up" or action == "Down" then
					scrollBy(body, if action == "Up" then -120 else 120); return true
				end
				return action == "Confirm"
			end,
		}
	end

	-- Move list ----------------------------------------------------------------------------------------------------------
	pageBuilders.Moves = function(parent: Frame): any
		local page: Frame = make("Frame", { Name = "Page_Moves", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = parent })
		local tabs = make("Frame", { Name = "Tabs", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), Parent = page })
		UIHelpers.list(tabs, true, 6)
		local head = make("Frame", { Name = "Head", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 0, 44), Parent = page })
		local heading = text(head, "Heading", "", T.display, 32, T.text, { Size = UDim2.new(0.4, 0, 0, 40) })
		local style = text(head, "Style", "", T.heavy, 13, T.muted, { Position = UDim2.new(0, 2, 0, 36), Size = UDim2.new(0.6, 0, 0, 16) })
		local legend = make("Frame", { Name = "Legend", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 6), Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, Parent = head })
		UIHelpers.list(legend, true, 10, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
		for i, l in { { "1", "LP" }, { "2", "RP" }, { "3", "LK" }, { "4", "RK" } } do
			local cell = make("Frame", { Name = "L" .. i, BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = i, Parent = legend })
			UIHelpers.list(cell, true, 4, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
			UIHelpers.notationRow(cell, l[1], { height = 22, order = 1 })
			autoText(cell, "Text", l[2] == "LP" and "L.PUNCH" or l[2] == "RP" and "R.PUNCH" or l[2] == "LK" and "L.KICK" or "R.KICK", T.heavy, 11, T.muted, 2, 26)
		end
		local scroll = scrollFrame(page, "List", { Position = UDim2.fromOffset(0, 104), Size = UDim2.new(1, 0, 1, -104) })
		local tabButtons: { [string]: UIHelpers.Button } = {}
		local shownId = ""
		local index = 1
		local function show(id: string)
			local def = UIHelpers.fighterDef(Roster, id) or Roster.get(Roster.order[1])
			index = table.find(Roster.order, def.id) or 1
			for tid, tab in tabButtons do tab.setSelected(tid == def.id); tab.setFocused(tid == def.id and menuFocus == "page") end
			if def.id == shownId then return end
			shownId = def.id
			heading.Text = def.displayName
			heading.TextColor3 = def.accentColor
			style.Text = string.upper(def.style) .. "  ·  " .. #def.moveOrder .. " MOVES"
			MoveList.fillList(scroll, def, nil, { rowHeight = 54 })
			scroll.CanvasPosition = Vector2.zero
		end
		for i, id in Roster.order do
			local def = Roster.get(id)
			local b = UIHelpers.button(tabs, "Tab_" .. id, { text = def.displayName, size = UDim2.fromOffset(100, 34), order = i, textSize = 14, accent = def.accentColor })
			tabButtons[id] = b
			table.insert(conns, b.button.Activated:Connect(function() menuFocus = "page"; sound("MenuMove"); show(id) end))
		end
		return {
			frame = page, show = function() show(fighterId()) end,
			refresh = function() for tid, tab in tabButtons do tab.setFocused(tid == shownId and menuFocus == "page") end end,
			showFighter = show,
			handle = function(action: string): boolean
				if action == "Left" or action == "Right" then
					index = ((index - 1 + (if action == "Left" then -1 else 1)) % #Roster.order) + 1
					sound("MenuMove"); show(Roster.order[index]); return true
				elseif action == "Up" or action == "Down" then
					scrollBy(scroll, if action == "Up" then -116 else 116); return true
				end
				return action == "Confirm"
			end,
		}
	end

	-- Settings ------------------------------------------------------------------------------------------------------------
	local function applyVolume(groupName: string, key: string, level: number)
		(settings :: any)[key] = math.clamp(level, 0, 1)
		local audio = modules().Audio
		local setter = audio and (if key == "music" then audio.setMusicVolume else audio.setSfxVolume)
		if typeof(setter) == "function" then pcall(setter, (settings :: any)[key]); return end
		local group = SoundService:FindFirstChild(groupName)
		if group and group:IsA("SoundGroup") then
			local base = group:GetAttribute("FightingLabBaseVolume")
			if typeof(base) ~= "number" then base = group.Volume; group:SetAttribute("FightingLabBaseVolume", base) end
			group.Volume = (base :: number) * (settings :: any)[key]
		end
	end
	local function setSetting(name: string, value: any)
		if name == "cameraShake" then
			settings.cameraShake = value == true
			if env.hud then env.hud:SetAttribute("CameraShakeDisabled", not settings.cameraShake) end
		elseif name == "music" then
			applyVolume("FightingLabMusic", "music", tonumber(value) or 1)
		elseif name == "sfx" then
			applyVolume("FightingLabSFX", "sfx", tonumber(value) or 1)
		elseif name == "guide" then
			settings.guide = if value == "On" or value == "Off" then value else "Auto"
			if env.hud then env.hud:SetAttribute("ControlsGuide", settings.guide) end
		elseif name == "duelFeed" then
			settings.duelFeed = value == true
		end
	end

	pageBuilders.Settings = function(parent: Frame): any
		local page: Frame = make("Frame", { Name = "Page_Settings", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = parent })
		UIHelpers.list(page, false, 8)
		local rows: { { frame: Frame, stroke: UIStroke, adjust: (number) -> (), activate: () -> (), paint: () -> () } } = {}
		local focus = 1
		local function row(name: string, title: string, desc: string, order: number): (Frame, UIStroke)
			local r: Frame = make("Frame", { Name = name, BackgroundColor3 = T.panel2, BackgroundTransparency = 0.3, BorderSizePixel = 0, Size = UDim2.new(1, -8, 0, 66), LayoutOrder = order, Parent = page })
			UIHelpers.corner(r, 6)
			local stroke = UIHelpers.outline(r, T.ember, 2, 1)
			text(r, "Title", title, T.title, 18, T.text, { Position = UDim2.fromOffset(18, 11), Size = UDim2.new(1, -340, 0, 24) })
			text(r, "Desc", desc, T.medium, 13, T.muted, { Position = UDim2.fromOffset(18, 36), Size = UDim2.new(1, -340, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd })
			table.insert(conns, r.InputBegan:Connect(function(input: InputObject)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					focus = order; menuFocus = "page"
					for _, x in rows do x.paint() end
				end
			end))
			return r, stroke
		end
		local function segmented(r: Frame, options: { string }, get: () -> string, set: (string) -> ()): ({ UIHelpers.Button }, () -> ())
			local holder = make("Frame", { Name = "Options", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), Size = UDim2.fromOffset(300, 36), Parent = r })
			UIHelpers.list(holder, true, 6, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
			local buttons = {}
			local function paint() for i, b in buttons do b.setSelected(options[i] == get()) end end
			for i, option in options do
				local b = UIHelpers.button(holder, "Opt_" .. option, { text = string.upper(option), size = UDim2.fromOffset(88, 34), order = i, textSize = 13 })
				buttons[i] = b
				table.insert(conns, b.button.Activated:Connect(function() set(option); sound("MenuMove"); paint() end))
			end
			paint()
			return buttons, paint
		end
		local function slider(r: Frame, key: string, groupName: string): () -> ()
			local holder = make("Frame", { Name = "Volume", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), Size = UDim2.fromOffset(310, 36), Parent = r })
			UIHelpers.list(holder, true, 8, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
			local minus = UIHelpers.button(holder, "Down", { text = "\u{2212}", size = UDim2.fromOffset(36, 34), order = 1, textSize = 20 })
			local barHolder = make("Frame", { Name = "Bar", BackgroundTransparency = 1, Size = UDim2.fromOffset(150, 34), LayoutOrder = 2, Active = true, Parent = holder })
			local _, set = UIHelpers.segmentBar(barHolder, "Segments", 20, T.ember, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, 12) })
			local plus = UIHelpers.button(holder, "Up", { text = "+", size = UDim2.fromOffset(36, 34), order = 3, textSize = 20 })
			local percent = text(holder, "Percent", "", T.number, 14, T.text, { Size = UDim2.fromOffset(52, 34), LayoutOrder = 4, TextXAlignment = Enum.TextXAlignment.Right })
			local function paint()
				local v = (settings :: any)[key]
				set(v, false)
				percent.Text = tostring(math.floor(v * 100 + 0.5)) .. "%"
			end
			table.insert(conns, minus.button.Activated:Connect(function() applyVolume(groupName, key, (settings :: any)[key] - 0.1); sound("MenuMove"); paint() end))
			table.insert(conns, plus.button.Activated:Connect(function() applyVolume(groupName, key, (settings :: any)[key] + 0.1); sound("MenuMove"); paint() end))
			table.insert(conns, barHolder.InputBegan:Connect(function(input: InputObject)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					local x = (input.Position.X - barHolder.AbsolutePosition.X) / math.max(1, barHolder.AbsoluteSize.X)
					applyVolume(groupName, key, math.floor(math.clamp(x, 0, 1) * 20 + 0.5) / 20)
					paint()
				end
			end))
			paint()
			return paint
		end
		local function onOff(v: boolean): string return if v then "On" else "Off" end
		local shake, shakeStroke = row("CameraShake", "CAMERA SHAKE", "Screen shake on heavy hits during fights", 1)
		local _, paintShake = segmented(shake, { "On", "Off" }, function() return onOff(settings.cameraShake) end, function(v) setSetting("cameraShake", v == "On") end)
		local music, musicStroke = row("Music", "MUSIC VOLUME", "Lobby and fight music", 2)
		local paintMusic = slider(music, "music", "FightingLabMusic")
		local sfx, sfxStroke = row("Sfx", "SOUND EFFECTS", "Hits, blocks, menus", 3)
		local paintSfx = slider(sfx, "sfx", "FightingLabSFX")
		local guide, guideStroke = row("Guide", "CONTROLS GUIDE", "Auto shows it in your first fight and first practice", 4)
		local _, paintGuide = segmented(guide, { "Auto", "On", "Off" }, function() return settings.guide end, function(v) setSetting("guide", v) end)
		local feed, feedStroke = row("DuelFeed", "DUEL FEED", "Toasts for results and challengers at other arenas", 5)
		local _, paintFeed = segmented(feed, { "On", "Off" }, function() return onOff(settings.duelFeed) end, function(v) setSetting("duelFeed", v == "On") end)
		local function cycle(options: { string }, current: string, delta: number): string
			local i = table.find(options, current) or 1
			return options[math.clamp(i + delta, 1, #options)]
		end
		local defs = {
			{ shake, shakeStroke, function(d: number) setSetting("cameraShake", cycle({ "On", "Off" }, onOff(settings.cameraShake), d) == "On") end, function() setSetting("cameraShake", not settings.cameraShake) end, paintShake },
			{ music, musicStroke, function(d: number) applyVolume("FightingLabMusic", "music", settings.music + d * 0.1) end, function() end, paintMusic },
			{ sfx, sfxStroke, function(d: number) applyVolume("FightingLabSFX", "sfx", settings.sfx + d * 0.1) end, function() end, paintSfx },
			{ guide, guideStroke, function(d: number) setSetting("guide", cycle({ "Auto", "On", "Off" }, settings.guide, d)) end, function() setSetting("guide", cycle({ "Auto", "On", "Off" }, settings.guide, 1)) end, paintGuide },
			{ feed, feedStroke, function(d: number) setSetting("duelFeed", cycle({ "On", "Off" }, onOff(settings.duelFeed), d) == "On") end, function() setSetting("duelFeed", not settings.duelFeed) end, paintFeed },
		}
		for i, d in defs do
			local stroke = d[2] :: UIStroke
			local paintValue = d[5] :: () -> ()
			rows[i] = {
				frame = d[1] :: Frame, stroke = stroke, adjust = d[3] :: (number) -> (), activate = d[4] :: () -> (),
				paint = function() stroke.Transparency = if focus == i and menuFocus == "page" then 0 else 1; paintValue() end,
			}
		end
		local function paintAll() for _, r in rows do r.paint() end end
		paintAll()
		return {
			frame = page, show = paintAll, refresh = paintAll,
			handle = function(action: string): boolean
				if action == "Up" or action == "Down" then
					focus = math.clamp(focus + (if action == "Up" then -1 else 1), 1, #rows); sound("MenuMove")
				elseif action == "Left" or action == "Right" then
					rows[focus].adjust(if action == "Left" then -1 else 1); sound("MenuMove")
				elseif action == "Confirm" then
					rows[focus].activate(); sound("MenuMove")
				else
					return false
				end
				paintAll()
				return true
			end,
		}
	end

	-- Credits ----------------------------------------------------------------------------------------------------------
	pageBuilders.Credits = function(parent: Frame): any
		local page: Frame = make("Frame", { Name = "Page_Credits", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = parent })
		local root = CreditsScreen.render(page, { compact = true, fontFace = T.heavy, bodyFace = T.medium, gold = T.gold, text = T.text, muted = T.muted, hint = "Scroll with the mouse wheel, drag, or use the arrow keys" })
		return {
			frame = page, show = function() end, refresh = function() end,
			handle = function(action: string): boolean
				if action == "Up" or action == "Down" then CreditsScreen.scroll(root, if action == "Up" then -1 else 1); return true end
				return action == "Left" or action == "Right" or action == "Confirm"
			end,
		}
	end

	-- Menu shell ---------------------------------------------------------------------------------------------------------
	local function menuFooter()
		local m = Mn
		if not m then return end
		for _, c in m.footer:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
		local d = S.device
		if d ~= "touch" then
			local gp = d == "gamepad"
			local gd = if gp then "gamepad" else "keyboard"
			UIHelpers.hint(m.footer, { "↑", "↓" }, "Section", { height = 24, device = gd, order = 1, color = T.muted, textSize = 13 })
			UIHelpers.hint(m.footer, { "←", "→" }, "Browse", { height = 24, device = gd, order = 2, color = T.muted, textSize = 13 })
			UIHelpers.hint(m.footer, { if gp then "A" else "ENTER" }, "Select", { height = 24, device = gd, order = 3, color = T.muted, textSize = 13 })
			UIHelpers.hint(m.footer, { if gp then "B" else "BACKSPACE" }, "Back", { height = 24, device = gd, order = 4, color = T.muted, textSize = 13 })
			UIHelpers.hint(m.footer, { if gp then menuPadLabel() else UIHelpers.keyLabel("lobby", "menu", "keyboard") }, "Close", { height = 24, device = gd, order = 5, color = T.muted, textSize = 13 })
		end
	end
	local function buildMenu(): any
		if Mn then return Mn end
		local mgui: ScreenGui = make("ScreenGui", { Name = "FightingLabLobbyMenu", ResetOnSpawn = false, ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets, DisplayOrder = 40, Enabled = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = env.parent })
		-- The dim reaches past the safe area (top bar, notches) so the whole screen darkens.
		local dim: TextButton = make("TextButton", { Name = "Dim", Text = "", AutoButtonColor = false, Modal = true, BackgroundColor3 = T.bg, BackgroundTransparency = 0.1, BorderSizePixel = 0, Position = UDim2.fromOffset(-200, -200), Size = UDim2.new(1, 400, 1, 400), Parent = mgui })
		make("UIGradient", { Rotation = 0, Transparency = UIHelpers.ramp({ { 0, 0.06 }, { 0.32, 0.18 }, { 1, 0.42 } }), Parent = dim })
		local mstage: Frame = make("Frame", { Name = "Stage", BackgroundTransparency = 1, Parent = mgui })
		local munfit = UIHelpers.fitToScreen(mgui, mstage, touchOnly)
		local body: Frame = make("Frame", { Name = "Body", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = mstage })
		-- The stage already carries the design-space UIScale (one UIScale per object), so the short-screen fit scales the body.
		local fit: UIScale = make("UIScale", { Name = "Fit", Parent = body })
		-- Brand + nav (left column)
		local brand = make("Frame", { Name = "Brand", BackgroundTransparency = 1, Position = UDim2.fromOffset(48, 40), Size = UDim2.fromOffset(320, 64), Parent = body })
		local word = text(brand, "Word", '<font color="' .. hex(T.text) .. '">FIGHTING</font><font color="' .. hex(T.ember) .. '">LAB</font>', T.display, 40, T.text, { Size = UDim2.fromOffset(320, 46), RichText = true })
		UIHelpers.textStroke(word, 0.6, 1)
		text(brand, "Tag", "DUEL LOBBY  \u{00B7}  MENU", T.heavy, 12, T.muted, { Position = UDim2.fromOffset(3, 46), Size = UDim2.fromOffset(300, 16) })
		local nav = make("Frame", { Name = "Nav", BackgroundTransparency = 1, Position = UDim2.fromOffset(40, 132), Size = UDim2.fromOffset(318, 360), Parent = body })
		UIHelpers.list(nav, false, 4)
		local navItems: { [string]: any } = {}
		for i, id in LobbyUI.MENU_PAGES do
			local b: TextButton = make("TextButton", { Name = "Nav_" .. id, Text = "", AutoButtonColor = false, BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 62), LayoutOrder = i, Parent = nav })
			local fill = make("Frame", { Name = "Fill", BackgroundColor3 = T.ember, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = b })
			make("UIGradient", { Transparency = UIHelpers.ramp({ { 0, 0.55 }, { 1, 1 } }), Parent = fill })
			local bar = make("Frame", { Name = "Bar", BackgroundColor3 = T.ember, BorderSizePixel = 0, Size = UDim2.new(0, 4, 1, -14), Position = UDim2.fromOffset(0, 7), Visible = false, Parent = b })
			local num = text(b, "Index", string.format("%02d", i), T.number, 12, T.dim, { Position = UDim2.fromOffset(16, 8), Size = UDim2.fromOffset(30, 16) })
			local label = text(b, "Label", NAV[id][1], T.display, 28, T.muted, { Position = UDim2.fromOffset(46, 2), Size = UDim2.new(1, -50, 0, 36) })
			local sub = text(b, "Sub", NAV[id][2], T.medium, 13, T.dim, { Position = UDim2.fromOffset(48, 38), Size = UDim2.new(1, -52, 0, 16) })
			navItems[id] = { button = b, fill = fill, bar = bar, label = label, sub = sub, num = num }
			table.insert(conns, b.Activated:Connect(function() menuFocus = "nav"; controller.openMenu(id) end))
		end
		-- Player chip (bottom-left)
		local who = make("Frame", { Name = "Who", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 48, 1, -84), Size = UDim2.fromOffset(300, 44), Parent = body })
		local whoName = text(who, "Player", "", T.heavy, 13, T.muted, { Size = UDim2.fromOffset(300, 16) })
		local whoFighter = text(who, "Fighter", "", T.title, 22, T.text, { Position = UDim2.fromOffset(0, 16), Size = UDim2.fromOffset(300, 28) })
		-- Content panel (right)
		local panel: Frame = UIHelpers.panel(body, "Panel", { Active = true, Position = UDim2.fromOffset(392, 40), Size = UDim2.new(1, -440, 1, -124), BackgroundTransparency = 0.08 })
		make("TextButton", { Name = "Catcher", Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = panel })
		local pageTitle = text(panel, "Title", "", T.display, 34, T.text, { Position = UDim2.fromOffset(28, 14), Size = UDim2.new(1, -200, 0, 42) })
		local pageSub = text(panel, "Sub", "", T.medium, 14, T.muted, { Position = UDim2.fromOffset(30, 54), Size = UDim2.new(1, -200, 0, 18) })
		make("Frame", { Name = "Divider", BackgroundColor3 = WHITE, BackgroundTransparency = 0.9, BorderSizePixel = 0, Position = UDim2.fromOffset(28, 82), Size = UDim2.new(1, -56, 0, 1), Parent = panel })
		local close = UIHelpers.button(panel, "Close", { text = "CLOSE", size = UDim2.fromOffset(110, 34), textSize = 13 })
		close.button.AnchorPoint = Vector2.new(1, 0)
		close.button.Position = UDim2.new(1, -22, 0, 22)
		local content: Frame = make("Frame", { Name = "Content", BackgroundTransparency = 1, ClipsDescendants = true, Position = UDim2.fromOffset(28, 96), Size = UDim2.new(1, -56, 1, -112), Parent = panel })
		local footer = make("Frame", { Name = "Footer", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 392, 1, -36), Size = UDim2.new(1, -440, 0, 26), Parent = body })
		UIHelpers.list(footer, true, 18, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
		local function fitMenu()
			-- Short screens (phones): shrink the whole menu so the 600-unit-tall layout fits.
			local h = mstage.Size.Y.Offset
			local w = mstage.Size.X.Offset
			local s = math.clamp(math.min(h / 640, w / 1180), 0.5, 1)
			fit.Scale = s
			body.Size = UDim2.fromOffset(w / s, h / s)
		end
		table.insert(conns, mstage:GetPropertyChangedSignal("Size"):Connect(fitMenu))
		fitMenu()
		table.insert(conns, dim.Activated:Connect(function() sound("MenuBack"); controller.closeMenu() end))
		table.insert(conns, close.button.Activated:Connect(function() sound("MenuBack"); controller.closeMenu() end))
		Mn = { gui = mgui, body = body, panel = panel, content = content, nav = navItems, pages = {}, unfit = munfit, footer = footer, title = pageTitle, sub = pageSub, whoName = whoName, whoFighter = whoFighter, blur = nil :: BlurEffect? }
		menuFooter()
		return Mn
	end
	onDevice(function() menuFooter() end)

	local function paintNav()
		local m = Mn
		if not m then return end
		for pid, nb in m.nav do
			local sel = pid == S.menuPage
			nb.fill.BackgroundTransparency = if sel then (if menuFocus == "nav" then 0 else 0.5) else 1
			nb.bar.Visible = sel
			nb.label.TextColor3 = if sel then T.text else T.muted
			nb.num.TextColor3 = if sel then T.ember else T.dim
			nb.sub.TextColor3 = if sel then T.muted else T.dim
		end
		local fighterNav = m.nav.Fighters
		if fighterNav then fighterNav.sub.Text = if view.canChooseFighter then NAV.Fighters[2] else "Fighter changes: lobby only" end
	end

	local function showPage(id: string)
		local m = buildMenu()
		local previous = S.menuPage
		S.menuPage = id
		m.title.Text = NAV[id][1]
		m.sub.Text = NAV[id][2]
		local def = Roster.get(fighterId())
		m.whoName.Text = string.upper(playerName())
		m.whoFighter.Text = def.displayName
		m.whoFighter.TextColor3 = def.accentColor
		if not m.pages[id] and pageBuilders[id] then m.pages[id] = pageBuilders[id](m.content) end
		for pid, page in m.pages do page.frame.Visible = pid == id end
		local page = m.pages[id]
		if page and previous ~= id then
			page.show()
			if live then
				page.frame.Position = UDim2.fromOffset(18, 0)
				UIHelpers.tween(page.frame, 0.18, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Quart)
			end
		elseif page then
			page.refresh()
		end
		paintNav()
	end
	local function menuAction(action: string): boolean
		local m = Mn
		if not m then return false end
		local page = m.pages[S.menuPage]
		if menuFocus == "page" and page then
			if action == "Back" then menuFocus = "nav"; sound("MenuBack"); page.refresh(); paintNav(); return true end
			if page.handle(action) then return true end
			return false
		end
		if action == "Up" or action == "Down" then
			local index = table.find(LobbyUI.MENU_PAGES, S.menuPage) or 1
			local nextIndex = ((index - 1 + (if action == "Up" then -1 else 1)) % #LobbyUI.MENU_PAGES) + 1
			controller.openMenu(LobbyUI.MENU_PAGES[nextIndex])
			return true
		elseif action == "Right" or action == "Confirm" then
			menuFocus = "page"; sound("MenuMove")
			if page then page.refresh() end
			paintNav()
			return true
		elseif action == "Back" then
			sound("MenuBack"); controller.closeMenu(); return true
		end
		return false
	end

	-- Fighter select (cinematic, FighterSelect + SelectScene) ---------------------------------------------------------
	local picker = FighterSelect.mount({
		parent = env.parent,
		presenter = modules().Characters,
		previews = previewsOn,
		touchOnly = touchOnly,
		live = live,
		world = env.world,
		device = function() return S.device end,
		canSelect = function(): (boolean, string?)
			if not view.canChooseFighter then return false, "Fighter changes are locked during duels and practice." end
			return true, nil
		end,
		currentFighter = function(): string? return fighterId() end,
		onConfirm = function(id: string) fire("SelectFighter", { id = id }) end,
		onClose = function() task.defer(function() if not destroyed then controller.refresh() end end) end,
		sound = sound,
		blur = live,
	})

	-- Lobby avatar freeze while an overlay is open (lobby modes only) ------------------------------------------------
	local controls: any = nil
	local function getControls(): any
		if controls ~= nil then return controls end
		controls = false
		if env.controls then controls = env.controls; return controls end
		if not live then return controls end
		pcall(function()
			local scripts = player:FindFirstChild("PlayerScripts")
			local moduleScript = scripts and scripts:FindFirstChild("PlayerModule")
			if moduleScript and moduleScript:IsA("ModuleScript") then controls = (require(moduleScript) :: any):GetControls() end
		end)
		return controls
	end
	local function setControls(enabled: boolean)
		if enabled then
			-- FightSession owns the character controls during fights and practice: never hand them back mid-fight
			-- (a picker that starts practice closes after the session already took the controls).
			local s = session()
			local active = false
			if s then
				pcall(function()
					local st = if typeof(s.state) == "function" then s.state() else nil
					active = st == "Fight" or st == "Practice" or (typeof(s.isFightActive) == "function" and s.isFightActive() == true)
				end)
			end
			if active then return end
		end
		local c = getControls()
		if c then pcall(function() if enabled then c:Enable() else c:Disable() end end) end
	end
	local function overlayOpen(): boolean return S.menuOpen or picker.isOpen() or S.picker ~= nil end
	local function updateFreeze()
		local overlay = overlayOpen()
		local lobbyMode = UIState.LOBBY_MODES[view.mode] == true
		local wantFrozen = overlay and lobbyMode
		if wantFrozen ~= S.frozen then
			S.frozen = wantFrozen
			if wantFrozen then
				setControls(false)
				S.owedEnable = true
			elseif lobbyMode then
				setControls(true)
				S.owedEnable = false
			end
		elseif S.owedEnable and not overlay and lobbyMode then
			setControls(true)
			S.owedEnable = false
		end
		-- Practice runs fight input; the menu pauses it so menu keys never move the fighter.
		local wantPause = S.menuOpen and view.mode == "Practice"
		if wantPause ~= S.gameplayPaused then
			S.gameplayPaused = wantPause
			local input = modules().Input
			if input and typeof(input.setGameplayEnabled) == "function" and (wantPause or view.mode == "Practice") then
				pcall(input.setGameplayEnabled, not wantPause)
			end
		end
		-- Camera blur behind the menu (local, on the current camera; removed on close).
		if live and Mn then
			local cam = workspace.CurrentCamera
			if S.menuOpen and cam and not Mn.blur then
				Mn.blur = make("BlurEffect", { Name = "FightingLabMenuBlur", Size = 14, Parent = cam })
			elseif not S.menuOpen and Mn.blur then
				Mn.blur:Destroy(); Mn.blur = nil
			end
		end
	end

	-- Identity -------------------------------------------------------------------------------------------------------
	local function setPortrait(id: string)
		if S.identityId == id then return end
		S.identityId = id
		local def = Roster.get(id)
		local dark = def.accentColor:Lerp(Color3.fromRGB(10, 12, 18), 0.5)
		H.fighterLabel.Text = def.displayName
		H.fighterLabel.TextColor3 = def.accentColor
		H.styleLabel.Text = def.style
		H.accentBar.BackgroundColor3 = def.accentColor
		H.portraitStroke.Color = def.accentColor
		H.portraitGradient.Color = ColorSequence.new(dark, Color3.fromRGB(10, 12, 18))
		H.pcoverGradient.Color = ColorSequence.new(dark, Color3.fromRGB(10, 12, 18))
		H.pmono.Text = string.sub(def.displayName, 1, 1)
		H.pmono.TextColor3 = def.accentColor
		H.pcover.Visible = true
		H.pcover.BackgroundTransparency = 0
		H.pmono.TextTransparency = 0
		S.portraitToken += 1
		local token = S.portraitToken
		local release = S.portraitRelease
		S.portraitRelease = nil
		if release then release() end
		if not previewsOn then return end
		task.spawn(function()
			if not FighterSelect.awaitTemplates(function() return token == S.portraitToken and not destroyed end) then return end
			local presenter = modules().Characters
			local model, warm, releaseFn = FighterSelect.acquireModel(presenter, id)
			if not model then return end
			if token ~= S.portraitToken or destroyed then releaseFn(); return end
			S.portraitRelease = releaseFn
			model.Parent = H.pworld
			if presenter and typeof(presenter.posePreview) == "function" then pcall(presenter.posePreview, model, id, "Stance", 0) end
			FighterSelect.frame(H.pvp, H.pcam, model, "Bust", 12)
			task.wait(warm)
			if token ~= S.portraitToken or destroyed then return end
			UIHelpers.tween(H.pcover, 0.3, { BackgroundTransparency = 1 })
			UIHelpers.tween(H.pmono, 0.2, { TextTransparency = 1 })
		end)
	end

	local function statValue(name: string): number
		local stats = player:FindFirstChild("leaderstats")
		local v = stats and stats:FindFirstChild(name)
		if v and v:IsA("ValueBase") then return tonumber((v :: any).Value) or 0 end
		return 0
	end
	local function updateStats()
		local wins, streak = statValue("Wins"), statValue("Streak")
		H.winsValue.Text = tostring(wins)
		H.streakValue.Text = tostring(streak)
		H.resultWins.Text = tostring(wins)
		H.resultStreak.Text = tostring(streak)
	end
	local function hookStats()
		for _, c in statConns do c:Disconnect() end
		table.clear(statConns)
		local stats = player:FindFirstChild("leaderstats")
		if stats then
			table.insert(statConns, stats.ChildAdded:Connect(function() task.defer(hookStats) end))
			for _, v in stats:GetChildren() do
				if v:IsA("ValueBase") then table.insert(statConns, (v :: any).Changed:Connect(updateStats)) end
			end
		end
		updateStats()
	end

	-- Practice pads: server hint (ArenaId of a Practice station + PadSide) or the character standing on a dojo pad.
	local practiceArenas: { Instance } = {}
	local lastArenaScan = -math.huge
	local function detectPracticePad(): string?
		if env.practicePad then return env.practicePad() end
		local arenaId = attr("ArenaId")
		local station = stationFor(arenaId)
		if station and station:GetAttribute("Kind") == "Practice" then
			local side = attr("PadSide")
			if side == 1 then return "Training" elseif side == 2 then return "Cpu" end
		end
		local getRoot = env.characterRoot
		local rootPart = if getRoot then getRoot() else nil
		if not rootPart then return nil end
		if os.clock() - lastArenaScan > 3 then
			lastArenaScan = os.clock()
			table.clear(practiceArenas)
			local world = worldFolder()
			local arenas = world and world:FindFirstChild("Arenas")
			if arenas then
				for _, arena in arenas:GetChildren() do
					if arena:GetAttribute("Kind") == "Practice" then table.insert(practiceArenas, arena) end
				end
			end
		end
		for _, arena in practiceArenas do
			for _, padName in { "PadTraining", "PadCpu" } do
				local pad = arena:FindFirstChild(padName)
				if pad and pad:IsA("BasePart") then
					local r = pad:GetAttribute("PadRadius")
					local radius = if typeof(r) == "number" then r else math.max(pad.Size.X, pad.Size.Z) * 0.5
					local offset = rootPart.Position - pad.Position
					if Vector2.new(offset.X, offset.Z).Magnitude <= radius + 0.6 and offset.Y > -1 and offset.Y < 8 then
						local mode = pad:GetAttribute("PadMode")
						return if mode == "Cpu" or (mode == nil and padName == "PadCpu") then "Cpu" else "Training"
					end
				end
			end
		end
		return nil
	end

	-- View -----------------------------------------------------------------------------------------------------------
	local function countdownEndsAt(): number?
		local info = S.countdownInfo
		if typeof(info) == "table" and typeof(info.endsAt) == "number" then return info.endsAt end
		local station = stationFor(attr("ArenaId"))
		local v = station and station:GetAttribute("CountdownEndsAt")
		return if typeof(v) == "number" and v > 0 then v else nil
	end
	-- Time waited alone on a duel circle: the server's QueuedAt (server time) when present, else local tracking.
	local function waitedSeconds(): number
		local queuedAt = attr("QueuedAt")
		if typeof(queuedAt) == "number" and queuedAt > 0 then return math.max(0, serverNow() - queuedAt) end
		local since = S.queuedSince
		return if since then os.clock() - since else 0
	end
	local function computeView(): UIState.LobbyView
		local duel = attr("DuelState")
		if duel == "Queued" then S.queuedSince = S.queuedSince or os.clock() else S.queuedSince = nil end
		local side = attr("PadSide")
		return UIState.lobbyView({
			sessionState = S.sessionState,
			duelState = if typeof(duel) == "string" then duel else nil,
			arenaName = arenaName(attr("ArenaId")),
			padSide = if typeof(side) == "number" then side else 0,
			practicePad = S.practicePad,
			queuedSeconds = waitedSeconds(),
			countdownEndsAt = countdownEndsAt(),
			now = serverNow(),
			keyboard = S.device ~= "touch",
			interactKey = UIHelpers.keyLabel("lobby", "interact", glyphDevice()),
		})
	end
	local function opponentLine(): string
		local info = S.countdownInfo
		local arenaId = attr("ArenaId")
		if (typeof(arenaId) ~= "string" or arenaId == "") and typeof(info) == "table" then arenaId = info.arenaId end
		local station = stationFor(arenaId)
		if not station then return "" end
		local mySide = if typeof(info) == "table" and typeof(info.side) == "number" then info.side else attr("PadSide")
		local other = if mySide == 2 then 1 else 2
		local name = station:GetAttribute("P" .. other .. "Name")
		if typeof(name) ~= "string" or name == "" then return "" end
		local def = UIHelpers.fighterDef(Roster, station:GetAttribute("P" .. other .. "Fighter"))
		return "VS  " .. string.upper(name) .. (if def then "  \u{00B7}  " .. def.displayName else "")
	end
	-- The arena of the local player's own fight or practice: FightSession.info().arenaId while the session is in
	-- Fight/Results/Practice, else the server's ArenaId attribute while DuelState says so (before MatchStart lands).
	local function localFightArena(): string?
		if S.sessionState == "Fight" or S.sessionState == "Results" or S.sessionState == "Practice" then
			local s = session()
			local get = s and s.info
			if typeof(get) == "function" then
				local ok, inf = pcall(get)
				if ok and typeof(inf) == "table" and typeof(inf.arenaId) == "string" and inf.arenaId ~= "" then return inf.arenaId end
			end
			local m = S.matchInfo
			if typeof(m) == "table" and typeof(m.arenaId) == "string" and m.arenaId ~= "" then return m.arenaId end
		end
		local duel = attr("DuelState")
		if duel == "Fighting" or duel == "Results" or duel == "Practice" then
			local a = attr("ArenaId")
			if typeof(a) == "string" and a ~= "" then return a end
		end
		return nil
	end
	-- FightSession.info() is the truth for the practice mode/difficulty (netcore keeps it in step on every route).
	local function readPracticeInfo(): boolean
		local s = session()
		local get = s and s.info
		if typeof(get) ~= "function" then return false end
		local ok, inf = pcall(get)
		if not ok or typeof(inf) ~= "table" then return false end
		if inf.mode == "Match" or inf.mode == "Training" then
			S.practiceCpu = inf.mode == "Match"
		elseif inf.practice == "Cpu" or inf.practice == "Training" then
			S.practiceCpu = inf.practice == "Cpu"
		elseif typeof(inf.cpu) == "boolean" then
			S.practiceCpu = inf.cpu
		end
		if typeof(inf.difficulty) == "string" and table.find(UIHelpers.Difficulties, inf.difficulty) then S.practiceDifficulty = inf.difficulty end
		return true
	end
	local function titleText(): string
		if view.mode == "Waiting" or view.mode == "CpuOffer" then
			return view.title .. string.rep(".", S.dots)
		end
		return view.title
	end

	-- World prompts (live) ---------------------------------------------------------------------------------------------
	local world = if live then LobbyUI.worldPrompts(function() return worldFolder() end) else nil
	local stopPromptStyle = if live then PromptStyle.start(env.parent, function() return S.device end) else nil
	local function promptSpecs(): UIState.PromptSet
		local side = attr("PadSide")
		local arena = attr("ArenaId")
		return UIState.prompts({
			view = view, overlay = overlayOpen(), cpuPending = os.clock() < S.cpuPendingUntil,
			arenaId = if typeof(arena) == "string" and arena ~= "" then arena else nil, padSide = if typeof(side) == "number" then side else nil,
			templatesReady = if previewsOn then FighterSelect.templatesReady() else true,
		})
	end

	local function apply()
		local v = view
		local mode = v.mode
		local lobbyish = UIState.LOBBY_MODES[mode] == true
		-- The fighter select is a full-screen scene: the HUD would only show through it.
		gui.Enabled = not S.suppressed and not picker.isOpen() and not S.menuOpen and mode ~= "Hidden" and mode ~= "Results"
		H.identity.Visible = v.showIdentity
		menuButtonHolder.Visible = v.menuAllowed and mode ~= "Practice"
		toastStack.Visible = lobbyish
		prompt.Visible = lobbyish and S.picker == nil
		if lobbyish then
			local offerShown = (mode == "CpuOffer" or mode == "PracticeChoice") and v.offer ~= ""
			H.offer.Visible = offerShown
			H.promptSub.Visible = not offerShown
			H.promptSub.Text = v.subtitle
			H.offerText.Text = if offerShown then v.offer else ""
			if os.clock() < S.cpuPendingUntil and mode == "CpuOffer" then H.offerText.Text = "Calling a CPU..." end
			local sideColor = if v.side == 2 then T.cool elseif v.side == 1 then T.warm else T.gold
			local ringColor = if mode == "Lobby" then T.gold elseif mode == "PracticeChoice" then (if v.padMode == "Cpu" then T.warm else T.cool) else sideColor
			H.ringStroke.Color = ringColor
			H.ringDot.BackgroundColor3 = ringColor
			H.ring.BackgroundColor3 = ringColor
			H.progressFill.BackgroundColor3 = ringColor
			H.pillEdge.BackgroundColor3 = ringColor
			H.promptTitle.Text = titleText()
		end
		H.progressBack.Visible = mode == "Waiting"
		countdown.Visible = mode == "Countdown"
		if mode == "Countdown" then
			H.cdVersus.Text = opponentLine()
			local digit = v.digit
			H.cdDigit.Text = if digit and digit > 0 then tostring(digit) else "GO"
			if digit ~= S.lastDigit then
				S.lastDigit = digit
				H.cdScale.Scale = 1.3
				UIHelpers.tween(H.cdScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
				for n, l in H.cdSteps do
					l.TextColor3 = if n == digit then T.gold elseif digit and n > digit then T.text else T.dim
					l.TextSize = if n == digit then 42 else 30
				end
				sound("MenuMove")
			end
		else
			S.lastDigit = nil
		end
		local inPractice = mode == "Practice"
		if inPractice and S.paused ~= S.panelPausedSeen then
			-- The pause key doubles as the practice menu: pausing opens the full panel, resuming folds it.
			S.panelPausedSeen = S.paused
			setPanelOpen(S.paused)
		end
		practicePanel.Visible = inPractice and S.panelOpen
		strip.Visible = inPractice and not S.panelOpen
		if mode == "Practice" then
			readPracticeInfo()
			-- Mode names come from the switchMode legend text ("Training / Versus CPU").
			P.mode.Text = if S.practiceCpu then (P.modeNames.versus or "VERSUS CPU") else (P.modeNames.training or "TRAINING")
			P.mode.BackgroundColor3 = if S.practiceCpu then T.warm else T.cool
			for id, b in P.modeChips do b.setSelected((id == "versus") == (S.practiceCpu == true)) end
			for d, b in P.chips do b.setSelected(d == S.practiceDifficulty) end
			if P.dummyRow then P.dummyRow.Visible = not S.practiceCpu end
			for m, b in P.dummyChips do b.setSelected(m == S.dummy) end
			if P.pause then P.pause.setSelected(S.paused == true) end
			P.lesson.label.Text = if S.lesson then "END LESSON" else "GUIDED LESSON"
			P.lesson.setSelected(S.lesson ~= nil)
			paintStrip()
		end
		renderLesson()
		if resultCard.Visible and not lobbyish then resultCard.Visible = false end
		if not v.menuAllowed and S.menuOpen then controller.closeMenu() end
		if picker.isOpen() then
			if not lobbyish then picker.close() else picker.refresh() end
		end
		-- A picker only lives while its prompt's condition holds (left the pad, challenger arrived, countdown...).
		local open = S.picker
		if open then
			local valid = (open.kind == "cpu" and mode == "CpuOffer") or (open.kind == "training" and mode == "PracticeChoice" and v.padMode == "Training") or (open.kind == "versus" and mode == "PracticeChoice" and v.padMode == "Cpu")
			if not valid then S.picker = nil; renderPicker() end
		end
		if S.menuOpen then paintNav() end
		updateFreeze()
		if world then
			local a, sd = attr("ArenaId"), attr("PadSide")
			world.sync(promptSpecs(), if typeof(a) == "string" and a ~= "" then a else nil, if typeof(sd) == "number" then sd else nil)
		end
		local arenaNow = localFightArena()
		if arenaNow ~= S.notifiedArena then
			S.notifiedArena = arenaNow
			local onLocalArena = env.onLocalArena
			if onLocalArena then
				local ok, err = pcall(onLocalArena, arenaNow)
				if not ok then warn("FightingLab lobby: onLocalArena failed: " .. tostring(err)) end
			end
		end
	end

	-- Results --------------------------------------------------------------------------------------------------------
	local function buildResult(start: any, finish: any): Result?
		if typeof(finish) ~= "table" or typeof(finish.winnerSlot) ~= "number" then return nil end
		local info = if typeof(start) == "table" then start else {}
		local slot = if info.slot == 2 then 2 else 1
		local opp = if slot == 1 then info.p2 else info.p1
		local oppTable = if typeof(opp) == "table" then opp else {}
		local isCpu = info.cpu == true or oppTable.userId == -1
		local oppName = if isCpu then "CPU" else str(oppTable.name, "Challenger")
		local oppDef = UIHelpers.fighterDef(Roster, oppTable.fighter)
		local roundsText: string? = nil
		local rounds = finish.rounds
		if typeof(rounds) == "table" and typeof(rounds.p1) == "number" and typeof(rounds.p2) == "number" then
			local mine = if slot == 1 then rounds.p1 else rounds.p2
			local theirs = if slot == 1 then rounds.p2 else rounds.p1
			roundsText = string.format("%d\u{2013}%d", mine, theirs)
		end
		local winner = finish.winnerSlot
		return {
			outcome = if winner == 0 then "DRAW" elseif winner == slot then "WIN" else "LOSS",
			opponent = oppName,
			opponentFighter = if oppDef then oppDef.displayName else nil,
			arena = arenaName(info.arenaId or attr("ArenaId")),
			rounds = roundsText,
			cpu = isCpu,
			difficulty = if typeof(info.difficulty) == "string" then info.difficulty else nil,
			key = tostring(finish.matchId or info.matchId or os.clock()),
		}
	end

	local function showResultCard(r: Result)
		if r.key ~= "" and r.key == S.resultShownKey then return end
		S.resultShownKey = r.key
		local color = if r.outcome == "WIN" then T.win elseif r.outcome == "LOSS" then T.loss else T.muted
		H.outcomeLabel.Text = if r.outcome == "WIN" then "VICTORY" elseif r.outcome == "LOSS" then "DEFEAT" else "DRAW"
		H.outcomeLabel.TextColor3 = color
		H.band.BackgroundColor3 = color
		H.bandStripe.BackgroundColor3 = color
		H.resultStroke.Color = color
		H.resultTimer.BackgroundColor3 = color
		H.resultVs.Text = "vs " .. r.opponent .. (if r.opponentFighter then "  \u{00B7}  " .. r.opponentFighter else "") .. (if r.cpu and r.difficulty then "  \u{00B7}  " .. string.upper(r.difficulty) else "")
		H.resultWhere.Text = string.upper(r.arena) .. (if r.rounds then "  \u{00B7}  ROUNDS " .. r.rounds else "")
		updateStats()
		resultCard.Visible = true
		H.resultScale.Scale = 0.78
		UIHelpers.tween(H.resultScale, 0.34, { Scale = 1 }, Enum.EasingStyle.Back)
		H.outcomeLabel.Position = UDim2.fromOffset(-40, 10)
		UIHelpers.tween(H.outcomeLabel, 0.4, { Position = UDim2.fromOffset(0, 10) }, Enum.EasingStyle.Quint)
		H.resultTimer.Size = UDim2.new(1, -40, 0, 3)
		UIHelpers.tween(H.resultTimer, LobbyUI.RESULT_SECONDS, { Size = UDim2.new(0, 0, 0, 3) }, Enum.EasingStyle.Linear)
		S.resultUntil = os.clock() + LobbyUI.RESULT_SECONDS
		sound(if r.outcome == "WIN" then "MenuSelect" else "MenuBack")
	end

	-- Toasts ---------------------------------------------------------------------------------------------------------
	local toastOrder = 0
	local function removeToast(index: number, fade: boolean)
		local item = table.remove(toasts, index)
		if not item then return end
		local frame = item.frame
		if fade then
			UIHelpers.tween(frame, 0.25, { BackgroundTransparency = 1 })
			for _, d in frame:GetDescendants() do
				if d:IsA("TextLabel") then UIHelpers.tween(d, 0.2, { TextTransparency = 1 }) end
				if d:IsA("UIStroke") then UIHelpers.tween(d, 0.2, { Transparency = 1 }) end
				if d:IsA("Frame") then UIHelpers.tween(d, 0.2, { BackgroundTransparency = 1 }) end
			end
			task.delay(0.26, function() frame:Destroy() end)
		else
			frame:Destroy()
		end
	end
	local function pushToast(title: string, body: string, color: Color3?)
		local c = color or T.gold
		toastOrder += 1
		local frame = UIHelpers.panel(toastStack, "Toast", { Size = UDim2.fromOffset(420, 58), LayoutOrder = -toastOrder, BackgroundTransparency = 0.08 })
		UIHelpers.accentBar(frame, c, 4)
		text(frame, "Title", title, T.heavy, 12, c, { Position = UDim2.fromOffset(18, 9), Size = UDim2.new(1, -30, 0, 15), TextTruncate = Enum.TextTruncate.AtEnd })
		text(frame, "Body", body, T.bold, 16, T.text, { Position = UDim2.fromOffset(18, 27), Size = UDim2.new(1, -30, 0, 22), TextTruncate = Enum.TextTruncate.AtEnd })
		local s = make("UIScale", { Scale = 0.88, Parent = frame })
		UIHelpers.tween(s, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
		table.insert(toasts, { frame = frame, expires = os.clock() + LobbyUI.TOAST_SECONDS })
		while #toasts > LobbyUI.MAX_TOASTS do removeToast(1, false) end
	end

	-- Stations (feed of other arenas) --------------------------------------------------------------------------------
	-- Servers update several attributes per transition (State, WinnerSlot, ResultText...) in any order, so each
	-- station is evaluated once, shortly after its last change: one toast per result, one per new challenger.
	local function isMine(station: Instance): boolean
		local me = myUserId()
		if me ~= 0 and (station:GetAttribute("P1UserId") == me or station:GetAttribute("P2UserId") == me) then return true end
		local duel = attr("DuelState")
		return attr("ArenaId") == station.Name and (duel == "Fighting" or duel == "Results" or duel == "Countdown" or duel == "Queued")
	end
	local function evaluateStation(station: Instance)
		local seen = stationSeen[station]
		if not seen or destroyed then return end
		seen.pending = false
		local state = str(station:GetAttribute("State"), "Open")
		local previous = seen.state
		seen.state = state
		if station:GetAttribute("Kind") == "Practice" then return end
		local display = str(station:GetAttribute("DisplayName"), station.Name)
		if state == "Results" then
			if seen.resultKey == "" then
				seen.resultKey = table.concat({ tostring(station:GetAttribute("WinnerSlot")), tostring(station:GetAttribute("ResultText")) }, "|")
				if not isMine(station) and settings.duelFeed then
					local v = StationBoards.viewModel(station:GetAttributes(), serverNow())
					pushToast(string.upper(display) .. "  \u{00B7}  RESULT", v.footer, T.win)
				end
			end
		else
			seen.resultKey = ""
			if state == "Waiting" and previous ~= "Waiting" and not isMine(station) and settings.duelFeed and os.clock() - seen.waitingAt > 25 then
				seen.waitingAt = os.clock()
				local who = str(station:GetAttribute("P1Name"), str(station:GetAttribute("P2Name"), "A fighter"))
				pushToast(string.upper(display), who .. " is waiting for a challenger", T.gold)
			end
		end
	end
	local function onStationAttr(station: Instance, name: string)
		if name ~= "State" and name ~= "WinnerSlot" and name ~= "ResultText" and name ~= "P1Name" and name ~= "P2Name" then return end
		local seen = stationSeen[station]
		if not seen or seen.pending then return end
		seen.pending = true
		task.delay(LobbyUI.FEED_SETTLE, evaluateStation, station)
	end
	local function scanStations()
		local folder = stationsFolder()
		for station, c in stationConns do
			if not folder or station.Parent ~= folder then c:Disconnect(); stationConns[station] = nil; stationSeen[station] = nil end
		end
		if not folder then return end
		for _, station in folder:GetChildren() do
			if not stationConns[station] then
				local state = str(station:GetAttribute("State"), "Open")
				stationSeen[station] = { state = state, resultKey = if state == "Results" then "seen" else "", waitingAt = -math.huge, pending = false }
				stationConns[station] = station.AttributeChanged:Connect(function(name: string) onStationAttr(station, name) end)
			end
		end
	end

	-- Session --------------------------------------------------------------------------------------------------------
	local function sessionLastResult(): { [string]: any }?
		local s = session()
		local lr = s and s.lastResult
		if typeof(lr) == "function" then
			local ok, v = pcall(lr)
			return if ok and typeof(v) == "table" then v else nil
		end
		return if typeof(lr) == "table" then lr else nil
	end
	local function onSession(state: any, info: any)
		if typeof(state) ~= "string" then return end
		local previous = S.sessionState
		S.sessionState = state
		if state == "Countdown" then
			S.countdownInfo = info
		elseif state == "Lobby" then
			S.countdownInfo = nil
		end
		if state == "Fight" or state == "Practice" then
			if typeof(info) == "table" then S.matchInfo = info end
			S.pendingEnd = nil
		end
		if state == "Practice" and previous ~= "Practice" then
			local m = if typeof(S.matchInfo) == "table" then S.matchInfo else {}
			S.practiceCpu = m.mode == "Match" or (m.cpu == true and m.mode ~= "Training")
			if typeof(m.difficulty) == "string" then S.practiceDifficulty = m.difficulty end
			S.dummy = "Stand"
			S.paused = false
			S.panelPausedSeen = false
			S.stripFlash = nil
			-- First look at the whole panel (it folds on the first fight input); touch screens start folded because
			-- the open panel would cover the touch fight buttons.
			S.panelOpen = S.device ~= "touch"
			S.panelUntil = clock() + LobbyUI.PANEL_START_SECONDS
			if S.pendingLesson then
				S.pendingLesson = false
				task.defer(function() if not destroyed and S.sessionState == "Practice" then controller.startLesson() end end)
			end
		end
		if state ~= "Practice" and previous == "Practice" then S.lesson = nil; S.panelOpen = false end
		if state == "Results" and typeof(info) == "table" then
			if info.result or info.matchEnd or info.winnerSlot ~= nil then
				S.pendingEnd = info.result or info.matchEnd or info
			end
			if info.p1 and info.p2 then S.matchInfo = info end
		end
		if state == "Lobby" then
			-- A countdown that ends in the lobby (not in a fight) was cancelled; only worth a toast while still on a circle.
			if previous == "Countdown" and (attr("DuelState") == "Queued" or attr("DuelState") == "Countdown" or not live) then
				pushToast("COUNTDOWN CANCELLED", "A fighter stepped off the circle.", T.muted)
			end
			if previous == "Results" or previous == "Fight" or previous == "Practice" then
				-- FightSession.lastResult() carries the MatchEnd (rounds included); the Results info is the fallback.
				local last = sessionLastResult()
				local r: Result? = nil
				if last then
					local start = if typeof(last.info) == "table" then last.info else S.matchInfo
					local local_ = typeof(start) == "table" and start.authority == "Local"
					if last.reason ~= "Practice" and not local_ then r = buildResult(start, last) end
				elseif S.pendingEnd and previous ~= "Practice" then
					local isPractice = typeof(S.matchInfo) == "table" and S.matchInfo.authority == "Local"
					r = if isPractice then nil else buildResult(S.matchInfo, S.pendingEnd)
				end
				if r then showResultCard(r) end
			end
			S.pendingEnd = nil
		end
		controller.refresh()
	end

	local function onRejected(payload: any)
		local p = if typeof(payload) == "table" then payload else {}
		local request = str(p.request, "")
		local reason = str(p.reason, "")
		if request == "RequestCpu" then S.cpuPendingUntil = 0 end
		local title = REJECT_TITLES[request] or "NOT RIGHT NOW"
		pushToast(title, REJECT_TEXT[reason] or "Please try again in a moment.", T.warm)
		controller.refresh()
	end

	local function hookSession()
		local s = session()
		if not s or S.sessionHooked == s then return end
		S.sessionHooked = s
		if S.sessionConn then S.sessionConn:Disconnect(); S.sessionConn = nil end
		if S.rejectConn then S.rejectConn:Disconnect(); S.rejectConn = nil end
		local changed = s.Changed
		if typeof(changed) == "RBXScriptSignal" then
			S.sessionConn = changed:Connect(function(state: any, info: any) onSession(state, info) end)
		end
		local rejected = s.Rejected
		if typeof(rejected) == "RBXScriptSignal" then
			S.rejectConn = rejected:Connect(onRejected)
		end
		if typeof(s.state) == "function" then
			local ok, st = pcall(s.state)
			if ok and typeof(st) == "string" then S.sessionState = st end
		end
		if typeof(s.info) == "function" then
			local ok, inf = pcall(s.info)
			if ok and typeof(inf) == "table" then
				if S.sessionState == "Countdown" then S.countdownInfo = inf else S.matchInfo = inf end
			end
		end
	end

	-- Without FightSession results come from the arena's station, snapshotted when DuelState turns to Results.
	local function onDuelChanged()
		local duel = attr("DuelState")
		local arena = attr("ArenaId")
		if typeof(arena) == "string" and arena ~= "" then S.lastArena = arena end
		if duel == "Results" then
			local station = stationFor(S.lastArena)
			S.stationSnapshot = if station then station:GetAttributes() else nil
		end
		if session() == nil and (S.lastDuel == "Results" or S.lastDuel == "Fighting") and (duel == "Lobby" or duel == "Queued") then
			local st = S.stationSnapshot or (function() local x = stationFor(S.lastArena); return if x then x:GetAttributes() else nil end)()
			if st then
				local me = myUserId()
				local slot = if st.P2UserId == me and me ~= 0 then 2 else 1
				local start = {
					slot = slot, arenaId = S.lastArena, cpu = st.Cpu == true, difficulty = st.Difficulty, matchId = attr("MatchId"),
					p1 = { name = st.P1Name, fighter = st.P1Fighter, userId = st.P1UserId }, p2 = { name = st.P2Name, fighter = st.P2Fighter, userId = st.P2UserId },
				}
				local finish = { winnerSlot = if typeof(st.WinnerSlot) == "number" then st.WinnerSlot else 0, rounds = { p1 = st.P1Rounds, p2 = st.P2Rounds }, matchId = attr("MatchId") }
				local r = buildResult(start, finish)
				if r then showResultCard(r) end
			end
			S.stationSnapshot = nil
		end
		S.lastDuel = duel
		controller.refresh()
	end

	-- Practice commands: T / 1-3 / Backspace are ours (Controls.practice); R, Y and P belong to InputController, but the
	-- panel's buttons route the same commands through Input.practice (or FightSession) so clicks and keys agree.
	local function sessionCommand(kind: string, arg: any?)
		local s = session()
		if s and typeof(s.practiceCommand) == "function" then
			local ok, err = pcall(s.practiceCommand, kind, arg)
			if not ok then warn("FightingLab lobby: practiceCommand " .. kind .. " failed: " .. tostring(err)) end
		end
	end
	local function inputCommand(kind: string, arg: any?)
		local input = modules().Input
		if input and typeof(input.practice) == "function" then
			local ok, err = pcall(input.practice, kind, arg)
			if ok then return end
			warn("FightingLab lobby: Input.practice " .. kind .. " failed: " .. tostring(err))
		end
		sessionCommand(kind, arg)
	end
	local lessonResetStep = 0 -- the step whose "reset" (neutral spacing) was already sent
	local function lessonApplyDummy()
		local t = S.lesson
		local step = t and not t.done and UIState.tutorialStep(t)
		if step and step.dummy ~= S.lessonDummy and not S.practiceCpu then
			S.lessonDummy = step.dummy
			inputCommand("Dummy", step.dummy)
			S.dummy = step.dummy
		end
		if t and step and step.reset and lessonResetStep ~= t.index and not S.practiceCpu then
			lessonResetStep = t.index
			inputCommand("Reset", nil)
		end
	end

	local function practiceKey(key: Enum.KeyCode): string?
		for _, spec in { { "switchMode", "Switch" }, { "easy", "Easy" }, { "normal", "Normal" }, { "hard", "Hard" }, { "leave", "Leave" } } do
			if UIHelpers.keyMatches(key, "practice", spec[1]) then return spec[2] end
		end
		return nil
	end

	-- Controller -----------------------------------------------------------------------------------------------------
	local acc, scanAcc, dotsAcc, deviceAcc = 0, 0, 0, 0
	local function closePicker(cancelled: boolean)
		if not S.picker then return end
		S.picker = nil
		if cancelled then sound("MenuBack") end
		renderPicker()
		apply()
	end
	controller = {
		gui = gui,
		view = function() return view end,
		refresh = function()
			if destroyed then return end
			view = computeView()
			setPortrait(fighterId())
			H.playerLabel.Text = string.upper(playerName())
			apply()
		end,
		tick = function(dt: number)
			if destroyed then return end
			if S.sessionHooked == nil or S.sessionHooked ~= session() then hookSession() end
			acc += dt
			scanAcc += dt
			dotsAcc += dt
			deviceAcc += dt
			if deviceAcc >= 0.25 then
				deviceAcc = 0
				local d = device()
				if d ~= S.device then
					S.device = d
					for _, fn in deviceListeners do pcall(fn, d) end
					if S.picker then buildPickerRows(); renderPicker() end
				end
			end
			if scanAcc >= 2 then scanAcc = 0; scanStations() end
			if acc >= 0.1 then
				acc = 0
				S.practicePad = detectPracticePad()
				controller.refresh()
			end
			local mode = view.mode
			if mode == "Waiting" or mode == "CpuOffer" then
				if dotsAcc >= 0.42 then dotsAcc = 0; S.dots = (S.dots % 3) + 1; H.promptTitle.Text = titleText() end
				H.progressFill.Size = UDim2.fromScale(math.clamp(waitedSeconds() / math.max(0.01, UIState.CPU_OFFER_DELAY), 0, 1), 1)
				H.ringScale.Scale = 1 + math.sin(os.clock() * 4.2) * 0.08
			else
				H.ringScale.Scale = 1
			end
			if mode == "Countdown" then H.cdRingGradient.Rotation = (H.cdRingGradient.Rotation + dt * 160) % 360 end
			if mode == "Practice" then
				-- An open panel (not a pause menu) folds after a few seconds without use; resting the mouse on it keeps it.
				if S.panelOpen and not S.paused then
					if pointerOnPanel() then
						S.panelUntil = math.max(S.panelUntil, clock() + 1)
					elseif clock() >= S.panelUntil then
						setPanelOpen(false)
					end
				end
				if S.stripFlash and clock() >= S.stripFlashUntil then S.stripFlash = nil; paintStrip() end
			end
			if resultCard.Visible and os.clock() > S.resultUntil then resultCard.Visible = false end
			for i = #toasts, 1, -1 do
				if os.clock() > toasts[i].expires then removeToast(i, true) end
			end
		end,
		handleKey = function(key: Enum.KeyCode): boolean
			if destroyed then return false end
			if picker.isOpen() then return picker.handleKey(key) end
			local nav = NAV_KEYS[key]
			if S.picker then
				if nav then controller.pickerAction(nav); return true end
				return key == Enum.KeyCode.Tab
			end
			-- In practice the gamepad face buttons and Select belong to the fight (attacks / controls guide): only Tab opens
			-- the menu there (the practice panel also has a Menu button).
			local inPractice = view.mode == "Practice"
			local padKey = string.sub(key.Name, 1, 6) == "Button" or string.sub(key.Name, 1, 4) == "DPad"
			local menuKey = key == Enum.KeyCode.Tab or (UIHelpers.keyMatches(key, "lobby", "menu") and not (inPractice and padKey)) or (key == Enum.KeyCode.ButtonSelect and not inPractice)
			if S.menuOpen then
				if menuKey then sound("MenuBack"); controller.closeMenu(); return true end
				if nav then return menuAction(nav) end
				return false
			end
			local mode = view.mode
			if menuKey and view.menuAllowed then controller.openMenu(nil); return true end
			if mode == "Practice" then
				local action = practiceKey(key)
				if action then panelTouch() end
				if action == "Switch" then controller.practiceCommand("SwitchMode"); return true end
				if action == "Easy" or action == "Normal" or action == "Hard" then controller.practiceCommand("Difficulty", action); return true end
				if action == "Leave" then controller.leavePractice(); return true end
				-- Fight keys stay with the fight (never consumed); they only fold the open panel away.
				if isFightKey(key) then foldForFight() end
			end
			return false
		end,
		openMenu = function(page: string?)
			if destroyed or not view.menuAllowed then return end
			local id = page and (LobbyUI.PAGE_ALIASES[page] or page) or S.menuPage
			if not NAV[id] then id = "Fighters" end
			if picker.isOpen() then picker.close() end
			if S.picker then closePicker(false) end
			local m = buildMenu()
			local wasOpen = S.menuOpen
			S.menuOpen = true
			m.gui.Enabled = true
			if live and not wasOpen then UIHelpers.holdPlayerList(true) end
			if not wasOpen then menuFocus = "nav" end
			apply()
			showPage(id)
			if not wasOpen then
				if live then
					m.body.Position = UDim2.fromOffset(-30, 0)
					UIHelpers.tween(m.body, 0.24, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Quint)
				end
				sound("MenuSelect")
			else
				sound("MenuMove")
			end
			updateFreeze()
		end,
		closeMenu = function()
			if not S.menuOpen then return end
			S.menuOpen = false
			if live then UIHelpers.holdPlayerList(false, view.mode ~= "Practice") end
			if Mn then Mn.gui.Enabled = false end
			apply()
		end,
		isMenuOpen = function() return S.menuOpen end,
		menuPage = function() return S.menuPage end,
		openFighterSelect = function(id: string?): boolean
			if destroyed or not UIState.LOBBY_MODES[view.mode] or not view.canChooseFighter then return false end
			if S.menuOpen then controller.closeMenu() end
			if S.picker then closePicker(false) end
			picker.open(if id and UIHelpers.fighterDef(Roster, id) then id else fighterId())
			apply()
			return true
		end,
		fighterSelect = function() return picker end,
		requestCpu = function(difficulty: string?): boolean
			if view.mode ~= "CpuOffer" then return false end
			local d = difficulty or S.practiceDifficulty
			if os.clock() - S.lastCpuRequest < 1.2 then return false end
			S.lastCpuRequest = os.clock()
			S.cpuPendingUntil = os.clock() + 3
			sound("MenuSelect")
			fire("RequestCpu", { difficulty = d })
			apply()
			return true
		end,
		startPractice = function(opts: { [string]: any }?): boolean
			if view.mode ~= "PracticeChoice" then return false end
			local o = opts or {}
			local mine = table.find(Roster.order, fighterId()) or 1
			local opponent = if typeof(o.opponent) == "string" and UIHelpers.fighterDef(Roster, o.opponent) then o.opponent else Roster.order[(mine % #Roster.order) + 1]
			local mode = if o.mode == "Cpu" or o.mode == "Training" then o.mode elseif view.padMode == "Cpu" then "Cpu" else "Training"
			local payload: { [string]: any } = { mode = mode, opponent = opponent }
			if mode == "Cpu" then
				payload.difficulty = if typeof(o.difficulty) == "string" then o.difficulty else S.practiceDifficulty
				S.practiceDifficulty = payload.difficulty
			end
			S.pendingLesson = mode == "Training" and o.lesson == true
			sound("MenuSelect")
			local s = session()
			if s and typeof(s.startPractice) == "function" then
				local ok, err = pcall(s.startPractice, payload)
				if not ok then warn("FightingLab lobby: startPractice failed: " .. tostring(err)) end
				return ok
			end
			return fire("StartPractice", payload)
		end,
		practiceCommand = function(kind: string, arg: any?)
			readPracticeInfo()
			panelTouch()
			local folded = not S.panelOpen
			if kind == "SwitchMode" then
				-- An explicit target taken from the true current mode, so the switch can never invert a stale panel.
				local target = if S.practiceCpu then "Training" else "Match"
				sessionCommand("SetMode", target)
				S.practiceCpu = target == "Match"
				if S.practiceCpu and S.lesson then S.lesson = nil; pushToast("LESSON ENDED", "Versus CPU started. Restart the lesson from the panel.", T.muted) end
				if folded then pulseStrip() end
			elseif kind == "Difficulty" then
				if typeof(arg) == "string" then S.practiceDifficulty = arg end
				sessionCommand("Difficulty", arg)
				if folded and typeof(arg) == "string" then flashStrip(P.levelCaption, P.levelLabels[arg] or string.upper(arg)) end
			elseif kind == "Dummy" then
				local m = if typeof(arg) == "string" and table.find(DUMMY_MODES, arg) then arg else DUMMY_MODES[((table.find(DUMMY_MODES, S.dummy) or 1) % #DUMMY_MODES) + 1]
				inputCommand("Dummy", m)
				S.dummy = m
				S.lessonDummy = m
			elseif kind == "Pause" then
				local want = if typeof(arg) == "boolean" then arg else not S.paused
				sessionCommand("Pause", want)
				S.paused = want
			elseif kind == "Reset" then
				inputCommand("Reset", nil)
			else
				sessionCommand(kind, arg)
			end
			sound("MenuMove")
			apply()
		end,
		leavePractice = function()
			sound("MenuBack")
			S.lesson = nil
			local s = session()
			if s and typeof(s.leave) == "function" then
				local ok, err = pcall(s.leave)
				if not ok then warn("FightingLab lobby: leave failed: " .. tostring(err)) end
			else
				fire("EndPractice", {})
			end
		end,
		showResult = function(result: any)
			local r = if typeof(result) == "table" and result.outcome then result else buildResult(result.start, result.finish)
			if r then showResultCard(r) end
		end,
		resultVisible = function() return resultCard.Visible end,
		pushToast = pushToast,
		toastCount = function() return #toasts end,
		promptText = function() return titleText(), (if H.offer.Visible then H.offerText.Text else H.promptSub.Text), view.offer end,
		promptSpecs = function() return promptSpecs() end,
		triggerPrompt = function(id: string): boolean
			local specs = promptSpecs()
			if id == "kiosk" then
				if not specs.kiosk.enabled then return false end
				return controller.openFighterSelect(nil)
			end
			local spec = (specs :: any)[id]
			if not spec or not spec.enabled then return false end
			return controller.openPicker(id)
		end,
		worldPrompts = function() return if world then world.all() else {} end,
		openPicker = function(kind: string): boolean
			if destroyed then return false end
			local mode = view.mode
			local ok = (kind == "cpu" and mode == "CpuOffer") or (kind == "training" and mode == "PracticeChoice" and view.padMode == "Training") or (kind == "versus" and mode == "PracticeChoice" and view.padMode == "Cpu")
			if not ok then return false end
			if S.menuOpen then controller.closeMenu() end
			local mine = table.find(Roster.order, fighterId()) or 1
			S.picker = UIState.pickerNew(kind, { fighters = Roster.order, opponent = Roster.order[(mine % #Roster.order) + 1], difficulty = S.practiceDifficulty })
			buildPickerRows()
			renderPicker()
			if live then
				K.scale.Scale = 0.92
				UIHelpers.tween(K.scale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
			end
			sound("MenuSelect")
			apply()
			return true
		end,
		picker = function() return S.picker end,
		pickerAction = function(action: string)
			local p = S.picker
			if not p then return end
			local nextP = UIState.pickerAction(p, action)
			if nextP.cancelled then closePicker(true); return end
			if nextP.done then
				local r = nextP.result or {}
				S.picker = nil
				renderPicker()
				if r.request == "RequestCpu" then
					S.practiceDifficulty = r.difficulty or S.practiceDifficulty
					controller.requestCpu(r.difficulty)
				else
					controller.startPractice(r)
				end
				apply()
				return
			end
			if nextP.focus ~= p.focus or action ~= "Confirm" then sound("MenuMove") end
			S.picker = nextP
			renderPicker()
		end,
		startLesson = function(): boolean
			if view.mode ~= "Practice" and S.sessionState ~= "Practice" then return false end
			if S.practiceCpu then controller.practiceCommand("SwitchMode") end
			local s = session()
			local slot = 1
			if s and typeof(s.info) == "function" then
				local ok, inf = pcall(s.info)
				if ok and typeof(inf) == "table" and inf.slot == 2 then slot = 2 end
			end
			S.lesson = UIState.tutorialNew(slot, fighterId(), Roster)
			S.lessonDummy = ""
			lessonResetStep = 0
			lessonApplyDummy()
			inputCommand("Reset", nil)
			if S.menuOpen then controller.closeMenu() end
			sound("MenuSelect")
			apply()
			return true
		end,
		stopLesson = function()
			if not S.lesson then return end
			S.lesson = nil
			sound("MenuBack")
			apply()
		end,
		lesson = function() return S.lesson end,
		onSnapshot = function(entry: any)
			if destroyed or typeof(entry) ~= "table" then return end
			controller.syncPractice(entry.mode, entry.dummy, entry.paused)
			-- The local fighter acting on its own input (keys or touch buttons) folds the open panel away.
			if S.panelOpen and not S.paused and S.sessionState == "Practice" and typeof(entry.fighters) == "table" then
				local info = S.matchInfo
				local mine = entry.fighters[if typeof(info) == "table" and info.slot == 2 then 2 else 1]
				if typeof(mine) == "table" and (mine.move ~= nil or INPUT_STATES[mine.state] == true) then foldForFight() end
			end
			local t = S.lesson
			if t and S.sessionState == "Practice" then
				local index = t.index
				local changed = UIState.tutorialObserve(t, entry, os.clock())
				if t.index ~= index then lessonApplyDummy(); sound("MenuSelect") end
				if changed then renderLesson() end
			end
		end,
		sessionChanged = onSession,
		localArena = function() return localFightArena() end,
		syncPractice = function(mode: any, dummy: any, paused: any?)
			if S.sessionState ~= "Practice" then return end
			local cpu = if mode == "Match" then true elseif mode == "Training" then false else S.practiceCpu
			local d = if typeof(dummy) == "string" and table.find(DUMMY_MODES, dummy) then dummy else S.dummy
			local p = if typeof(paused) == "boolean" then paused else S.paused
			if cpu ~= S.practiceCpu or d ~= S.dummy or p ~= S.paused then
				local changedSetting = cpu ~= S.practiceCpu or d ~= S.dummy
				S.practiceCpu, S.dummy, S.paused = cpu, d, p
				apply() -- re-reads FightSession.info(), which wins over the snapshot for the mode
				-- Y / T through InputController: an open panel stays open a little longer, a folded strip pulses.
				if changedSetting then
					if S.panelOpen then panelTouch() else pulseStrip() end
				end
			end
		end,
		practiceState = function() return { cpu = S.practiceCpu, dummy = S.dummy, paused = S.paused, difficulty = S.practiceDifficulty } end,
		panelOpen = function() return S.panelOpen end,
		setPanelOpen = function(open: boolean)
			if destroyed or view.mode ~= "Practice" then return end
			setPanelOpen(open)
			if open then panelTouch() end
			apply()
		end,
		togglePanel = function()
			if destroyed or view.mode ~= "Practice" then return end
			if S.panelOpen then
				-- Fold; a pause menu also resumes the fight.
				if S.paused then controller.practiceCommand("Pause", false) end
				setPanelOpen(false)
				sound("MenuBack")
			else
				-- The strip opens the panel as a pause menu, like the pause key.
				controller.practiceCommand("Pause", true)
				setPanelOpen(true)
				sound("MenuSelect")
			end
			apply()
		end,
		settings = function() return table.clone(settings) end,
		setSetting = function(name: string, value: any) setSetting(name, value); if Mn and Mn.pages.Settings then Mn.pages.Settings.refresh() end end,
		setSuppressed = function(on: boolean)
			S.suppressed = on
			if on then controller.closeMenu() end
			renderPicker()
			apply()
		end,
		destroy = function()
			if destroyed then return end
			controller.closeMenu()
			picker.destroy()
			destroyed = true
			if S.frozen or S.owedEnable then setControls(true) end
			local release = S.portraitRelease
			S.portraitRelease = nil
			if release then release() end
			for _, c in conns do c:Disconnect() end
			for _, c in statConns do c:Disconnect() end
			for _, c in stationConns do c:Disconnect() end
			table.clear(conns); table.clear(statConns); table.clear(stationConns)
			if S.sessionConn then S.sessionConn:Disconnect() end
			if S.rejectConn then S.rejectConn:Disconnect() end
			if world then world.destroy() end
			if stopPromptStyle then stopPromptStyle() end
			unfit()
			unfitPicker()
			if Mn then
				if Mn.blur then Mn.blur:Destroy() end
				Mn.unfit(); Mn.gui:Destroy()
			end
			pickerGui:Destroy()
			gui:Destroy()
		end,
	}

	-- Wiring ---------------------------------------------------------------------------------------------------------
	table.insert(conns, player.AttributeChanged:Connect(function(name: string)
		if name == "DuelState" then onDuelChanged()
		elseif name == "FighterId" or name == "ArenaId" or name == "PadSide" or name == "QueuedAt" then controller.refresh() end
	end))
	table.insert(conns, player.ChildAdded:Connect(function(child) if child.Name == "leaderstats" then task.defer(hookStats) end end))
	table.insert(conns, resultCard.Activated:Connect(function() S.resultUntil = 0; resultCard.Visible = false end))
	-- Keys that Roblox features also bind arrive as "processed": Tab (player list), 1-3 (Backpack hotbar, disabled by
	-- LobbyUI.start but may still be bound), arrows/WASD/Space (default camera and character). In the states that use
	-- them they still belong to the lobby UI; typing in a TextBox and the Roblox menu always win.
	local function acceptProcessed(key: Enum.KeyCode): boolean
		if UserInputService:GetFocusedTextBox() or GuiService.MenuIsOpen then return false end
		if key == Enum.KeyCode.Tab then return true end
		local overlay = S.menuOpen or picker.isOpen() or S.picker ~= nil
		if overlay then return OVERLAY_KEYS[key] == true or NAV_KEYS[key] ~= nil end
		if view.mode == "Practice" then return practiceKey(key) ~= nil or isFightKey(key) end
		return false
	end
	if live then
		table.insert(conns, RunService.Heartbeat:Connect(function(dt: number) controller.tick(dt) end))
		table.insert(conns, UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			local kind = input.UserInputType
			if kind ~= Enum.UserInputType.Keyboard and string.sub(kind.Name, 1, 7) ~= "Gamepad" then return end
			if processed and not acceptProcessed(input.KeyCode) then return end
			controller.handleKey(input.KeyCode)
		end))
		table.insert(conns, ProximityPromptService.PromptTriggered:Connect(function(p: ProximityPrompt, who: Player?)
			if who ~= nil and who ~= player then return end
			local kind = p:GetAttribute(LobbyUI.PROMPT_ATTRIBUTE)
			if p.Name == "ChooseFighter" or kind == "kiosk" then controller.triggerPrompt("kiosk")
			elseif kind == "cpu" or kind == "training" or kind == "versus" then controller.triggerPrompt(kind :: string) end
		end))
	end
	hookStats()
	hookSession()
	scanStations()
	if env.hud then
		local shakeOff = env.hud:GetAttribute("CameraShakeDisabled")
		settings.cameraShake = shakeOff ~= true
		local guideMode = env.hud:GetAttribute("ControlsGuide")
		if guideMode == "On" or guideMode == "Off" or guideMode == "Auto" then settings.guide = guideMode end
	end
	local audio = modules().Audio
	if audio and typeof(audio.getMusicVolume) == "function" then
		local ok, v = pcall(audio.getMusicVolume)
		if ok and typeof(v) == "number" then settings.music = math.clamp(v, 0, 1) end
	end
	controller.refresh()
	return controller
end

--------------------------------------------------------------------------------------------------------------------
-- Live start (client): one lobby UI, arena boards and the leaderboard. FrontEnd.start() calls this.
--------------------------------------------------------------------------------------------------------------------
local active: Controller? = nil
local boards: any = nil
local ladder: any = nil

export type StartOverrides = { session: any?, remote: any?, practicePad: (() -> string?)?, leaderboardEntries: (() -> { any })?, previews: boolean? }

function LobbyUI.stop()
	if active then active.destroy(); active = nil end
	if boards then boards.stop(); boards = nil end
	if ladder then ladder.stop(); ladder = nil end
end

-- Keys 1-3 pick practice difficulties, but Roblox's Backpack hotbar binds them too (this game has no tools), so the
-- hotbar is turned off. SetCoreGuiEnabled can fail while the CoreGui is still loading: retried until it sticks.
function LobbyUI.disableBackpack()
	task.spawn(function()
		for _ = 1, 240 do
			local ok = pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false) end)
			local okRead, enabled = pcall(function() return StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Backpack) end)
			if ok and okRead and enabled == false then return end
			task.wait(0.25)
		end
		warn("FightingLab lobby: the Backpack hotbar could not be disabled; keys 1-3 may reach it")
	end)
end

function LobbyUI.start(ctx: any, overrides: StartOverrides?): Controller
	LobbyUI.stop()
	LobbyUI.disableBackpack()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local lab = ReplicatedStorage:WaitForChild("FightingLab")
	local o: StartOverrides = overrides or {}
	local env: Env = {
		player = player,
		parent = playerGui,
		hud = ctx.gui,
		modules = ctx.modules,
		session = o.session,
		remote = o.remote,
		stations = function() return lab:FindFirstChild("Stations") end,
		world = function() return workspace:FindFirstChild("FightingLabWorld") end,
		serverNow = function() return workspace:GetServerTimeNow() end,
		characterRoot = function(): BasePart?
			local character = player.Character
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			return if rootPart and rootPart:IsA("BasePart") then rootPart else nil
		end,
		practicePad = o.practicePad,
		previews = o.previews ~= false,
		live = true,
		onLocalArena = function(arenaId: string?)
			local b = boards
			if b then b.setFocusArena(arenaId) end
		end,
	}
	if env.remote == nil then
		task.spawn(function()
			local net = lab:WaitForChild("Net", math.huge)
			local remote = net and net:WaitForChild("Lobby", math.huge)
			if remote and remote:IsA("RemoteEvent") and env.remote == nil then env.remote = remote end
		end)
	end
	local controller = LobbyUI.mount(env)
	active = controller
	boards = StationBoards.start({ world = env.world :: any, stations = env.stations :: any, tagParent = playerGui, serverNow = env.serverNow })
	boards.setFocusArena(controller.localArena())
	ladder = Leaderboard.start({
		gui = function(): Instance?
			local world = workspace:FindFirstChild("FightingLabWorld")
			local lobby = world and world:FindFirstChild("Lobby")
			local part = lobby and lobby:FindFirstChild("Leaderboard")
			local surface = part and part:FindFirstChild("LeaderboardGui")
			return if surface and surface:IsA("SurfaceGui") then surface else nil
		end,
		provider = o.leaderboardEntries,
	})
	return controller
end

function LobbyUI.active(): Controller? return active end
function LobbyUI.boards(): any return boards end
function LobbyUI.leaderboard(): any return ladder end

-- Kept for the FrontEnd contract; the lobby UI runs on its own Heartbeat.
function LobbyUI.update(_frame: any) end
-- Practice snapshots keep the practice panel honest (mode / dummy / pause changed by keys the panel did not see) and
-- drive the guided lesson's goals.
function LobbyUI.onSnapshot(entry: any)
	local c = active
	if c and typeof(entry) == "table" then c.onSnapshot(entry) end
end

return LobbyUI
