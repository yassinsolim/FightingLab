--!strict
-- PLAY flow (round 7). "It should be easy to play a game": one decision per screen, big clear cards, large type.
--   PLAY -> WHO DO YOU WANT TO FIGHT?  VS PLAYER / VS CPU / PRACTICE
--   VS CPU    -> PICK A MAP (CPU level toggle on top; behind the panel each map is shown on its own stage from its
--                PreviewCam, through StageController.previewArena)
--             -> READY? (FIGHT! or CHANGE FIGHTER) -> taken there, the fight starts
--   VS PLAYER -> PICK A MAP (ANY MAP first, recommended) -> taken there to wait (Any map = the matchmaking queue)
--   PRACTICE  -> FREE TRAINING / COMBO TRIALS / GUIDED LESSON / PRACTICE VS CPU (the dojo)
--   While searching or waiting on a circle, PLAY opens FINDING AN OPPONENT: FIGHT CPU INSTEAD (after 12 s) / CANCEL.
-- Back (Backspace / gamepad B / the BACK button) steps back one screen; the PLAY key (F / RB) closes it from anywhere.
-- The model (new / cards / act / rejected) is pure and tested on its own; mount(env) draws it, owns the preview camera
-- and hands requests to the lobby (env.send). Maps come from the Stations folder (State, Order, Reserved, P1/P2) and
-- the world's arena models (Contract D: Tagline, ThemeColor, PreviewCam; DisplayName / AccentColor / a computed shot
-- from FightOrigin when missing). No 3D fighter is drawn here (monogram tiles only), so no model can flash bare.
local GuiService = game:GetService("GuiService")

local Client = script.Parent
local Lab = Client.Parent
local UIHelpers = require(Client.UIHelpers)
local Roster = require(Lab:WaitForChild("Roster"))
local NetProtocol = require(Lab:WaitForChild("NetProtocol"))

local T = UIHelpers.Theme
local make, text = UIHelpers.make, UIHelpers.text
local WHITE = Color3.new(1, 1, 1)

local PlayFlow = {}
PlayFlow.CPU_OFFER_SECONDS = (NetProtocol :: any).QuickCpuOfferSeconds or 12
PlayFlow.DIP_IN = 0.09 -- the scene dips to dark this fast before the view changes to another map (or back)
PlayFlow.DIP_OUT = 0.2 -- and comes back this fast
PlayFlow.HANDOVER_SECONDS = 6 -- a fight from the flow takes the map's stage within this; else the lobby comes back
PlayFlow.PENDING_SECONDS = 3 -- FIGHT! waits this long for the server's Teleport / Rejected
PlayFlow.MODE_NAMES = { Duel = "VS PLAYER", Cpu = "VS CPU", Practice = "PRACTICE" } :: { [string]: string }
PlayFlow.LEVELS = { "Easy", "Normal", "Hard" }

export type Arena = {
	id: string, name: string, tagline: string, color: Color3, order: number, state: string, reserved: boolean,
	waiting: number, -- players waiting alone on its circles (0 or 1)
}
export type Facts = {
	arenas: { Arena }, -- duel maps in Order
	searching: boolean?, searchSeconds: number?, -- the Any map queue (Player attribute QuickQueue)
	waiting: boolean?, waitSeconds: number?, waitArena: string?, -- on a duel circle (DuelState Queued)
	fighter: string?,
}
export type Card = {
	id: string, title: string, sub: string, chip: string, color: Color3, enabled: boolean, mark: string?, kicker: string?,
	primary: boolean?, arena: Arena?,
}
export type Back = { screen: string, focus: number, mode: string? }
export type State = {
	screen: string, -- Who | Map | Ready | Practice | Search
	mode: string?, -- Duel | Cpu | Practice
	focus: number,
	zone: string, -- "cards" | "level" (the CPU level row on the map screen)
	difficulty: string,
	arena: string?, -- the map chosen for a CPU fight (Ready)
	back: { Back },
	notice: string?,
	pending: boolean, -- FIGHT! sent, waiting for the server
}
export type Request = { kind: string, payload: { [string]: any }?, lesson: boolean?, trials: boolean?, close: boolean?, arena: string? }

local function validLevel(v: any): string?
	return if v == "Easy" or v == "Normal" or v == "Hard" then v else nil
end

-- A CPU fight needs a map nobody uses; VS PLAYER can wait on an open map or join the player waiting on one.
local function freeForCpu(a: Arena): boolean return a.state == "Open" and not a.reserved end
local function freeForDuel(a: Arena): boolean
	return a.state == "Open" or (a.state == "Waiting" and a.waiting > 0)
end

local function arenaChip(a: Arena, mode: string?): string
	if a.state == "Fighting" or a.state == "Results" then return "LIVE FIGHT" end
	if a.state == "Countdown" then return "STARTING" end
	if mode == "Duel" then
		if a.state == "Waiting" and a.waiting > 0 then return "1 WAITING  ·  FIGHT NOW" end
		return "OPEN  ·  WAIT THERE"
	end
	if a.state == "Waiting" then return "PLAYER WAITING" end
	if a.reserved then return "BUSY" end
	return "OPEN"
end

function PlayFlow.new(opts: { [string]: any }?): State
	local o = opts or {}
	return {
		screen = if typeof(o.screen) == "string" then o.screen else "Who", mode = nil, focus = 1, zone = "cards",
		difficulty = validLevel(o.difficulty) or "Normal", arena = nil, back = {}, notice = nil, pending = false,
	}
end

local function arenaById(facts: Facts, id: string?): Arena?
	for _, a in facts.arenas do if a.id == id then return a end end
	return nil
end

-- The cards a screen shows for the current facts.
function PlayFlow.cards(s: State, facts: Facts): { Card }
	local out: { Card } = {}
	if s.screen == "Who" then
		local waiting = 0
		for _, a in facts.arenas do if a.state == "Waiting" then waiting += a.waiting end end
		table.insert(out, { id = "duel", title = "VS PLAYER", sub = "Fight another player. Any map, or pick one.", chip = if waiting > 0 then string.format("%d WAITING NOW", waiting) else "ONLINE", color = T.ember, enabled = true, mark = "VS", kicker = "01" })
		table.insert(out, { id = "cpu", title = "VS CPU", sub = "Fight the computer. Easy, Normal or Hard.", chip = "START IN SECONDS", color = T.gold, enabled = true, mark = "CPU", kicker = "02" })
		table.insert(out, { id = "practice", title = "PRACTICE", sub = "Free training, combo trials and a guided lesson.", chip = "LEARN COMBOS", color = T.cool, enabled = true, mark = "DOJO", kicker = "03" })
	elseif s.screen == "Map" then
		if s.mode == "Duel" then
			table.insert(out, { id = "any", title = "ANY MAP", sub = "Fastest: fight whoever is ready", chip = "RECOMMENDED", color = T.ember, enabled = true, mark = "★", primary = true })
		end
		for _, a in facts.arenas do
			local ok = if s.mode == "Duel" then freeForDuel(a) else freeForCpu(a)
			table.insert(out, { id = a.id, title = string.upper(a.name), sub = a.tagline, chip = arenaChip(a, s.mode), color = a.color, enabled = ok, arena = a })
		end
	elseif s.screen == "Ready" then
		local a = arenaById(facts, s.arena)
		local def = UIHelpers.fighterDef(Roster, facts.fighter) or Roster.get(Roster.order[1])
		local name = UIHelpers.titleCase(def.displayName)
		local where = if a then a.name else "the map"
		table.insert(out, { id = "fight", title = "FIGHT!", sub = string.format("%s vs CPU (%s) at %s", name, s.difficulty, where), chip = "VS CPU  ·  " .. string.upper(s.difficulty), color = T.ember, enabled = true, primary = true })
		table.insert(out, { id = "fighter", title = "CHANGE FIGHTER", sub = "Now: " .. name .. "  ·  " .. def.style, chip = "FIGHTER SELECT", color = def.accentColor, enabled = true })
	elseif s.screen == "Practice" then
		table.insert(out, { id = "training", title = "FREE TRAINING", sub = "A dummy, your rules: try anything.", chip = "DOJO", color = T.cool, enabled = true, kicker = "01" })
		table.insert(out, { id = "trials", title = "COMBO TRIALS", sub = "Learn your fighter's combos step by step.", chip = "SHOW ME + RETRY", color = T.gold, enabled = true, kicker = "02" })
		table.insert(out, { id = "lesson", title = "GUIDED LESSON", sub = "10 short steps: move, guard, strings, throws.", chip = "NEW PLAYERS", color = T.ok, enabled = true, kicker = "03" })
		table.insert(out, { id = "practiceCpu", title = "PRACTICE VS CPU", sub = "A practice match at the dojo. Nothing at stake.", chip = string.upper(s.difficulty) .. " CPU", color = T.warm, enabled = true, kicker = "04" })
	elseif s.screen == "Search" then
		local seconds = if facts.waiting then facts.waitSeconds or 0 else facts.searchSeconds or 0
		local ready = seconds >= PlayFlow.CPU_OFFER_SECONDS
		local left = math.max(1, math.ceil(PlayFlow.CPU_OFFER_SECONDS - seconds))
		table.insert(out, { id = "cpuInstead", title = "FIGHT CPU INSTEAD", sub = if ready then "A " .. s.difficulty .. " CPU, right now" else string.format("Available in %d s", left), chip = if ready then "READY" else "SOON", color = T.gold, enabled = ready, primary = ready })
		table.insert(out, { id = "cancel", title = "CANCEL", sub = if facts.waiting then "Leave the circle" else "Stop searching", chip = "BACK TO THE LOBBY", color = T.muted, enabled = true })
	end
	return out
end

-- The default focus on the map screen: Any map for VS PLAYER, the first free map for a CPU fight.
local function mapFocus(mode: string?, facts: Facts): number
	if mode == "Duel" then return 1 end
	for i, a in facts.arenas do if freeForCpu(a) then return i end end
	return 1
end

local function nextFree(cards: { Card }, from: number): number?
	local n = #cards
	for k = 1, n - 1 do
		local i = ((from - 1 + k) % n) + 1
		if cards[i].enabled and cards[i].arena then return i end
	end
	return nil
end

-- Pure reducer. Actions: Left | Right | Up | Down | Confirm | Back | Focus:<i> | Pick:<i> | Level:<Easy|Normal|Hard>.
-- Returns the next state and what the lobby must do (QuickPlay / CancelQueue / LeaveCircle / Fighters / Close).
function PlayFlow.act(state: State, facts: Facts, action: string): (State, Request?)
	local s: State = table.clone(state)
	s.back = table.clone(state.back)
	if action == "Back" then
		s.notice = nil
		if s.pending then return s, nil end
		if s.screen == "Map" and s.zone == "level" then s.zone = "cards"; return s, nil end
		local prev = table.remove(s.back)
		if not prev then return s, { kind = "Close" } end
		s.screen, s.focus, s.mode, s.zone = prev.screen, prev.focus, prev.mode, "cards"
		if s.screen ~= "Ready" then s.arena = nil end
		return s, nil
	end
	if s.pending then return s, nil end
	local level = string.match(action, "^Level:(%a+)$")
	if level then
		s.difficulty = validLevel(level) or s.difficulty
		return s, nil
	end
	local cards = PlayFlow.cards(s, facts)
	local n = math.max(1, #cards)
	local focusTo = tonumber(string.match(action, "^Focus:(%d+)$") or "")
	if focusTo then
		s.focus = math.clamp(focusTo, 1, n)
		s.zone = "cards"
		return s, nil
	end
	local pick = tonumber(string.match(action, "^Pick:(%d+)$") or "")
	if pick then
		s.focus = math.clamp(pick, 1, n)
		s.zone = "cards"
		action = "Confirm"
	end
	if s.screen == "Map" and s.mode == "Cpu" then
		if s.zone == "level" then
			local i = table.find(PlayFlow.LEVELS, s.difficulty) or 2
			if action == "Left" then s.difficulty = PlayFlow.LEVELS[math.max(1, i - 1)]
			elseif action == "Right" then s.difficulty = PlayFlow.LEVELS[math.min(#PlayFlow.LEVELS, i + 1)]
			elseif action == "Down" or action == "Confirm" then s.zone = "cards" end
			return s, nil
		elseif action == "Up" then
			s.zone = "level"
			return s, nil
		end
	end
	if action == "Left" or action == "Up" then
		s.focus = math.max(1, s.focus - 1)
		return s, nil
	elseif action == "Right" or action == "Down" then
		s.focus = math.min(n, s.focus + 1)
		return s, nil
	elseif action ~= "Confirm" then
		return s, nil
	end
	local card = cards[s.focus]
	if not card then return s, nil end
	local function push() table.insert(s.back, { screen = s.screen, focus = s.focus, mode = s.mode }) end
	if s.screen == "Who" then
		push()
		s.notice = nil
		if card.id == "practice" then
			s.screen, s.mode, s.focus = "Practice", "Practice", 1
		else
			s.mode = if card.id == "cpu" then "Cpu" else "Duel"
			s.screen, s.zone, s.focus = "Map", "cards", mapFocus(s.mode, facts)
		end
		return s, nil
	elseif s.screen == "Map" then
		if card.id == "any" then return s, { kind = "QuickPlay", payload = { mode = "Duel" }, close = true } end
		if card.enabled then
			s.notice = nil
			if s.mode == "Cpu" then
				push()
				s.screen, s.arena, s.focus = "Ready", card.id, 1
				return s, nil
			end
			return s, { kind = "QuickPlay", payload = { mode = "Duel", arena = card.id }, close = true, arena = card.id }
		end
		-- Busy: say so and offer the next free map (the focus moves there; one more press takes it).
		local nextIndex = nextFree(cards, s.focus)
		if nextIndex then
			s.notice = card.title .. " IS BUSY  ·  NEXT FREE: " .. cards[nextIndex].title
			s.focus = nextIndex
		else
			s.notice = if s.mode == "Cpu" then "EVERY MAP IS BUSY  ·  TRY PRACTICE VS CPU" else "EVERY MAP IS BUSY  ·  PICK ANY MAP TO QUEUE"
		end
		return s, nil
	elseif s.screen == "Ready" then
		if card.id == "fighter" then return s, { kind = "Fighters" } end
		s.pending = true
		s.notice = nil
		return s, { kind = "QuickPlay", payload = { mode = "Cpu", difficulty = s.difficulty, arena = s.arena }, arena = s.arena }
	elseif s.screen == "Practice" then
		local practice = if card.id == "practiceCpu" then "Cpu" else "Training"
		local payload: { [string]: any } = { mode = "Practice", practice = practice }
		if practice == "Cpu" then payload.difficulty = s.difficulty end
		return s, { kind = "QuickPlay", payload = payload, lesson = card.id == "lesson", trials = card.id == "trials", close = true }
	elseif s.screen == "Search" then
		if card.id == "cancel" then return s, { kind = if facts.waiting then "LeaveCircle" else "CancelQueue", close = true } end
		if not card.enabled then return s, nil end
		-- On a circle the CPU joins right there; from the queue it takes any free map.
		return s, { kind = "QuickPlay", payload = { mode = "Cpu", difficulty = s.difficulty, arena = if facts.waiting then facts.waitArena else nil }, close = true }
	end
	return s, nil
end

-- The server refused a QuickPlay (payload {request, reason, arena?, next?}): the state to show. A busy map on the READY
-- screen is swapped for the offered one in place (one press fights there); otherwise back to the map screen with the
-- notice and the focus on the offered map.
function PlayFlow.rejected(state: State, facts: Facts, payload: any): State
	local p = if typeof(payload) == "table" then payload else {}
	local s: State = table.clone(state)
	s.back = table.clone(state.back)
	s.pending = false
	local busyName = (function()
		local a = arenaById(facts, p.arena)
		return if a then string.upper(a.name) else "THAT MAP"
	end)()
	local nextArena = arenaById(facts, p.next)
	if p.reason == "ArenaBusy" then
		if s.screen == "Ready" and nextArena then
			s.arena = nextArena.id
			s.focus = 1
			s.notice = busyName .. " IS BUSY  ·  FIGHT AT " .. string.upper(nextArena.name) .. "?"
			return s
		end
		if s.screen ~= "Map" then
			if s.screen == "Ready" then table.remove(s.back) end
			s.screen, s.zone = "Map", "cards"
		end
		s.notice = busyName .. " IS BUSY" .. (if nextArena then "  ·  NEXT FREE: " .. string.upper(nextArena.name) else "  ·  EVERY MAP IS BUSY")
		local cards = PlayFlow.cards(s, facts)
		for i, c in cards do
			if nextArena and c.id == nextArena.id then s.focus = i end
		end
		return s
	elseif p.reason == "ArenasBusy" then
		s.notice = "EVERY MAP IS BUSY  ·  TRY PRACTICE VS CPU"
	elseif p.reason == "NoArena" then
		s.notice = "THAT MAP IS NOT OPEN"
	else
		s.notice = "NOT RIGHT NOW  ·  TRY AGAIN IN A MOMENT"
	end
	return s
end

--------------------------------------------------------------------------------------------------------------------
-- Facts and map looks (Stations folder + world arena models)
--------------------------------------------------------------------------------------------------------------------
-- The world's arena model of a map (workspace.FightingLabWorld.Arenas.<ArenaId>, or the model carrying that ArenaId).
function PlayFlow.arenaModel(world: Instance?, id: string): Instance?
	local arenas = world and world:FindFirstChild("Arenas")
	if not arenas then return nil end
	local direct = arenas:FindFirstChild(id)
	if direct then return direct end
	for _, m in arenas:GetChildren() do
		if m:GetAttribute("ArenaId") == id then return m end
	end
	return nil
end

-- Contract D looks with fallbacks: ThemeColor -> AccentColor -> ember; Tagline (40 chars max) -> "".
function PlayFlow.arenaLook(model: Instance?): (string?, string, Color3)
	local display = model and model:GetAttribute("DisplayName")
	local tagline = model and model:GetAttribute("Tagline")
	local color = model and (model:GetAttribute("ThemeColor") or model:GetAttribute("AccentColor"))
	return (if typeof(display) == "string" and display ~= "" then display else nil),
		(if typeof(tagline) == "string" then string.sub(tagline, 1, 48) else ""),
		(if typeof(color) == "Color3" then color else T.ember)
end

-- Duel maps from the Stations folder (Kind / State / Order / Reserved / P1UserId / P2UserId), with their looks.
function PlayFlow.collectArenas(stations: Instance?, world: Instance?): { Arena }
	local out: { Arena } = {}
	if not stations then return out end
	for _, st in stations:GetChildren() do
		if st:GetAttribute("Kind") ~= "Practice" then
			local idAttr = st:GetAttribute("ArenaId")
			local id = if typeof(idAttr) == "string" and idAttr ~= "" then idAttr else st.Name
			local display, tagline, color = PlayFlow.arenaLook(PlayFlow.arenaModel(world, id))
			local name = st:GetAttribute("DisplayName")
			local state = st:GetAttribute("State")
			local order = st:GetAttribute("Order")
			local p1, p2 = st:GetAttribute("P1UserId"), st:GetAttribute("P2UserId")
			local alone = (typeof(p1) == "number" and p1 ~= 0) ~= (typeof(p2) == "number" and p2 ~= 0)
			table.insert(out, {
				id = id, name = display or (if typeof(name) == "string" and name ~= "" then name else id), tagline = tagline, color = color,
				order = if typeof(order) == "number" then order else 99, state = if typeof(state) == "string" then state else "Open",
				reserved = st:GetAttribute("Reserved") == true, waiting = if state == "Waiting" and alone then 1 else 0,
			})
		end
	end
	table.sort(out, function(a, b)
		if a.order ~= b.order then return a.order < b.order end
		return a.id < b.id
	end)
	return out
end

-- The beauty shot of a map: its PreviewCam part (Contract D), else a shot from the plaza side, high enough to see the
-- ring and both circles (the circles stand 41 studs in front of FightOrigin, toward the plaza).
function PlayFlow.previewFrame(model: Instance?): CFrame?
	if not model then return nil end
	local cam = model:FindFirstChild("PreviewCam")
	if cam and cam:IsA("BasePart") then return cam.CFrame end
	local originPart = model:FindFirstChild("FightOrigin", true)
	if not (originPart and originPart:IsA("BasePart")) then return nil end
	local o = originPart.Position
	local arrival = model:FindFirstChild("Arrival", true)
	local out = if arrival and arrival:IsA("BasePart") then arrival.Position - o else -o
	out = Vector3.new(out.X, 0, out.Z)
	out = if out.Magnitude > 0.5 then out.Unit else Vector3.new(0, 0, 1)
	local right = Vector3.new(-out.Z, 0, out.X)
	local eye = o + out * 60 + right * 9 + Vector3.new(0, 24, 0)
	return CFrame.lookAt(eye, o + out * 12 + Vector3.new(0, 2, 0))
end

-- The field of view the PreviewCam shot is framed for (its FieldOfView attribute, Contract D), when sane.
function PlayFlow.previewFov(model: Instance?): number?
	local cam = if model then model:FindFirstChild("PreviewCam") else nil
	local fov = if cam then cam:GetAttribute("FieldOfView") else nil
	return if typeof(fov) == "number" and fov >= 20 and fov <= 100 then fov else nil
end

-- The camera type the preview hands back: the lobby camera follows the character, so a frozen (Scriptable) camera
-- seen when the preview started is never restored.
function PlayFlow.lobbyCameraType(saved: Enum.CameraType?): Enum.CameraType
	return if saved == nil or saved == Enum.CameraType.Scriptable then Enum.CameraType.Custom else saved
end

--------------------------------------------------------------------------------------------------------------------
-- View
--------------------------------------------------------------------------------------------------------------------
export type Env = {
	parent: Instance,
	player: Instance,
	live: boolean?,
	touchOnly: boolean?,
	device: () -> string, -- keyboard | gamepad | touch
	stations: () -> Instance?,
	world: () -> Instance?,
	serverNow: () -> number,
	clock: (() -> number)?,
	send: (req: Request) -> boolean,
	sound: ((name: string) -> ())?,
	camera: (() -> Camera?)?, -- the preview camera (live: workspace.CurrentCamera; nil = no preview)
	-- StageController (world, Contract D): previewArena(model?) shows a map as its fighters see it (its fight set and
	-- mood, the district hidden); previewing() tells which. nil / missing: the PreviewCam shot of the plain world.
	stage: (() -> any)?,
	onChanged: (() -> ())?, -- opened / closed: the lobby re-applies its HUD
	difficulty: (() -> string)?,
	setDifficulty: ((level: string) -> ())?,
}
export type Controller = {
	gui: ScreenGui,
	open: (screen: string?) -> boolean,
	close: () -> (),
	isOpen: () -> boolean,
	state: () -> State,
	screen: () -> string,
	cards: () -> { Card },
	facts: () -> Facts,
	action: (a: string) -> (),
	pick: (id: string) -> boolean,
	refresh: () -> (),
	tick: (dt: number) -> (),
	onTeleport: (payload: any) -> (),
	onRejected: (payload: any) -> boolean,
	suspend: () -> (),
	resume: () -> boolean,
	suspended: () -> boolean,
	previewArena: () -> string?,
	setSuppressed: (on: boolean) -> (),
	destroy: () -> (),
}

local SCREEN_TEXT: { [string]: { string } } = {
	Who = { "WHO DO YOU WANT TO FIGHT?", "Pick one. You can change your fighter at any time." },
	Map = { "PICK A MAP", "" },
	Ready = { "READY?", "" },
	Practice = { "PRACTICE", "Everything happens in the Training Bay dojo." },
	Search = { "", "" },
}
local CARD_SIZES: { [string]: Vector2 } = { Who = Vector2.new(330, 300), Practice = Vector2.new(262, 270), Search = Vector2.new(330, 230), Ready = Vector2.new(330, 220), Map = Vector2.new(228, 128) }

local function clockText(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

function PlayFlow.mount(env: Env): Controller
	local live = env.live == true
	local clock = env.clock or os.clock
	local player = env.player
	local destroyed = false
	local conns: { RBXScriptConnection } = {}
	local controller: Controller
	local S = {
		open = false, state = PlayFlow.new({ difficulty = if env.difficulty then env.difficulty() else nil }),
		signature = "", pendingSince = 0, suspendedState = nil :: State?, suppressed = false, previewId = nil :: string?,
		lastSecond = -1,
	}
	local refs: { [string]: any } = { cards = {} }
	local function sound(name: string) if env.sound then pcall(env.sound, name) end end
	local function attr(name: string): any return player:GetAttribute(name) end

	local function facts(): Facts
		local now = env.serverNow()
		local q = attr("QuickQueue")
		local duel = attr("DuelState")
		local queuedAt = attr("QueuedAt")
		local arena = attr("ArenaId")
		return {
			arenas = PlayFlow.collectArenas(env.stations(), env.world()),
			searching = typeof(q) == "number" and q > 0, searchSeconds = if typeof(q) == "number" and q > 0 then math.max(0, now - q) else 0,
			waiting = duel == "Queued", waitSeconds = if typeof(queuedAt) == "number" and queuedAt > 0 then math.max(0, now - queuedAt) else 0,
			waitArena = if typeof(arena) == "string" and arena ~= "" then arena else nil,
			fighter = attr("FighterId"),
		}
	end

	-- Root ---------------------------------------------------------------------------------------------------------
	local gui: ScreenGui = make("ScreenGui", { Name = "FightingLabPlay", ResetOnSpawn = false, DisplayOrder = 35, Enabled = false, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, ScreenInsets = Enum.ScreenInsets.None, Parent = env.parent })
	-- Dim for the choice screens; on the map screens only top and bottom shades, so the live preview reads.
	local dim: Frame = make("Frame", { Name = "Dim", BackgroundColor3 = T.bg, BackgroundTransparency = 0.3, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = gui })
	local shade: Frame = make("Frame", { Name = "Shade", BackgroundColor3 = T.bg, BackgroundTransparency = 0, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Visible = false, Parent = gui })
	make("UIGradient", { Rotation = 90, Transparency = UIHelpers.ramp({ { 0, 0.15 }, { 0.3, 0.85 }, { 0.55, 1 }, { 0.68, 0.7 }, { 1, 0.05 } }), Parent = shade })
	local holder: Frame = make("Frame", { Name = "Safe", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = gui })
	if live then
		-- The dim covers the whole screen; the content stays below Roblox's top bar.
		local ok, inset = pcall(function() return GuiService:GetGuiInset() end)
		if ok and typeof(inset) == "Vector2" and inset.Y > 0 then
			holder.Position = UDim2.fromOffset(0, inset.Y)
			holder.Size = UDim2.new(1, 0, 1, -inset.Y)
		end
	end
	local stage: Frame = make("Frame", { Name = "Stage", BackgroundTransparency = 1, Parent = holder })
	local unfit = UIHelpers.fitToScreen(holder, stage, env.touchOnly)
	local scale: UIScale = make("UIScale", { Name = "Pop", Parent = make("Frame", { Name = "Content", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = stage }) })
	local content: Frame = scale.Parent :: Frame

	-- Header: breadcrumb, big title, one line of help.
	local header = make("Frame", { Name = "Header", BackgroundTransparency = 1, Position = UDim2.fromOffset(64, 40), Size = UDim2.new(1, -460, 0, 150), Parent = content })
	refs.crumb = text(header, "Crumb", "PLAY", T.heavy, 16, T.ember, { Size = UDim2.new(1, 0, 0, 20) })
	refs.title = text(header, "Title", "", T.display, 52, T.text, { Position = UDim2.fromOffset(-2, 22), Size = UDim2.new(1, 0, 0, 62), TextTruncate = Enum.TextTruncate.AtEnd })
	UIHelpers.textStroke(refs.title, 0.55, 2)
	refs.sub = text(header, "Sub", "", T.medium, 20, T.muted, { Position = UDim2.fromOffset(0, 88), Size = UDim2.new(1, 0, 0, 26), TextTruncate = Enum.TextTruncate.AtEnd })
	UIHelpers.textStroke(refs.sub, 0.6, 1)

	-- CPU level toggle (map screen, VS CPU): one row of three chips under the header.
	-- A dark backing keeps the caption and the hint readable over the live preview.
	local levelRow = make("Frame", { Name = "Level", BackgroundColor3 = T.bg, BackgroundTransparency = 0.22, BorderSizePixel = 0, Position = UDim2.fromOffset(52, 156), Size = UDim2.fromOffset(0, 56), AutomaticSize = Enum.AutomaticSize.X, Visible = false, Parent = content })
	UIHelpers.corner(levelRow, 6)
	make("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 18), Parent = levelRow })
	UIHelpers.list(levelRow, true, 10, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	refs.levelCaption = text(levelRow, "Caption", "CPU LEVEL", T.heavy, 15, T.muted, { Size = UDim2.fromOffset(96, 46), LayoutOrder = 0 })
	refs.levels = {}
	for i, level in PlayFlow.LEVELS do
		local info = UIHelpers.DifficultyInfo[level]
		local b = UIHelpers.button(levelRow, "Level" .. level, { text = string.upper(level), size = UDim2.fromOffset(128, 42), order = i, textSize = 17, accent = info.color })
		b.button.Selectable = false
		refs.levels[level] = b
		table.insert(conns, b.button.Activated:Connect(function() controller.action("Level:" .. level) end))
	end
	refs.levelHint = text(levelRow, "Hint", "", T.medium, 16, T.muted, { Size = UDim2.fromOffset(0, 46), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 9 })
	make("UIPadding", { PaddingLeft = UDim.new(0, 6), Parent = refs.levelHint })

	-- Showcase (map / ready screens): the focused map's name, tagline and state, over the live preview.
	local showcase = make("Frame", { Name = "Showcase", BackgroundTransparency = 1, Position = UDim2.new(0, 64, 0.5, -120), Size = UDim2.fromOffset(760, 170), Visible = false, Parent = content })
	refs.showName = text(showcase, "Name", "", T.display, 66, T.text, { Size = UDim2.new(1, 0, 0, 78), TextScaled = true })
	make("UITextSizeConstraint", { MaxTextSize = 66, MinTextSize = 30, Parent = refs.showName })
	UIHelpers.textStroke(refs.showName, 0.35, 3)
	refs.showTag = text(showcase, "Tagline", "", T.bold, 22, T.text, { Position = UDim2.fromOffset(2, 78), Size = UDim2.new(1, 0, 0, 28), TextTruncate = Enum.TextTruncate.AtEnd })
	UIHelpers.textStroke(refs.showTag, 0.45, 2)
	refs.showChip = text(showcase, "Chip", "", T.heavy, 15, T.ink, { Position = UDim2.fromOffset(2, 116), Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 0, BackgroundColor3 = T.gold })
	UIHelpers.corner(refs.showChip, 3)
	make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), Parent = refs.showChip })

	-- Your fighter (map / ready screens): monogram, name, CHANGE.
	local fighterChip = UIHelpers.panel(content, "Fighter", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -40, 0, 40), Size = UDim2.fromOffset(330, 76), Visible = false })
	refs.fighterMono = make("Frame", { Name = "Mono", BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(56, 56), Parent = fighterChip })
	text(fighterChip, "Caption", "YOUR FIGHTER", T.heavy, 12, T.muted, { Position = UDim2.fromOffset(78, 10), Size = UDim2.fromOffset(150, 16) })
	refs.fighterName = text(fighterChip, "Name", "", T.display, 26, T.text, { Position = UDim2.fromOffset(78, 26), Size = UDim2.fromOffset(150, 34), TextTruncate = Enum.TextTruncate.AtEnd })
	refs.fighterChange = UIHelpers.button(fighterChip, "Change", { text = "CHANGE", size = UDim2.fromOffset(92, 36), textSize = 14, accent = T.gold })
	refs.fighterChange.button.AnchorPoint = Vector2.new(1, 0.5)
	refs.fighterChange.button.Position = UDim2.new(1, -10, 0.5, 0)
	refs.fighterChange.button.Selectable = false
	table.insert(conns, refs.fighterChange.button.Activated:Connect(function() controller.pick("fighter") end))

	-- Cards row and the notice above it.
	local cardsFrame = make("Frame", { Name = "Cards", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.56), Size = UDim2.new(1, -120, 0, 300), Parent = content })
	UIHelpers.list(cardsFrame, true, 22, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	local notice = text(content, "Notice", "", T.heavy, 18, T.ink, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0.56, -170), Size = UDim2.fromOffset(0, 40), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 0, BackgroundColor3 = T.warm, Visible = false, TextXAlignment = Enum.TextXAlignment.Center })
	UIHelpers.corner(notice, 4)
	make("UIPadding", { PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18), Parent = notice })
	refs.notice = notice

	-- Footer: BACK / CLOSE buttons and the key hints of the current device.
	local footer = make("Frame", { Name = "Footer", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 64, 1, -34), Size = UDim2.new(1, -128, 0, 48), Parent = content })
	UIHelpers.list(footer, true, 14, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	refs.backButton = UIHelpers.button(footer, "Back", { text = "‹  BACK", size = UDim2.fromOffset(150, 46), order = 1, textSize = 18 })
	refs.closeButton = UIHelpers.button(footer, "Close", { text = "CLOSE", size = UDim2.fromOffset(130, 46), order = 2, textSize = 16 })
	refs.backButton.button.Selectable = false
	refs.closeButton.button.Selectable = false
	table.insert(conns, refs.backButton.button.Activated:Connect(function() controller.action("Back") end))
	table.insert(conns, refs.closeButton.button.Activated:Connect(function() controller.close() end))
	local hints = make("Frame", { Name = "Hints", BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 46), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 3, Parent = footer })
	UIHelpers.list(hints, true, 18, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	refs.hints = hints
	refs.hintDevice = ""

	local function paintHints()
		local d = env.device()
		local key = d .. "|" .. S.state.screen .. "|" .. tostring(S.state.mode)
		if refs.hintDevice == key then return end
		refs.hintDevice = key
		for _, c in hints:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
		if d == "touch" then return end
		local gp = d == "gamepad"
		local gd = if gp then "gamepad" else "keyboard"
		local playKey = UIHelpers.keyLabel("lobby", "play", gd)
		UIHelpers.hint(hints, if gp then { "←", "→" } else { "←", "→" }, "Move", { height = 26, device = gd, order = 1, color = T.muted, textSize = 15 })
		UIHelpers.hint(hints, { if gp then "A" else "ENTER" }, "Select", { height = 26, device = gd, order = 2, color = T.muted, textSize = 15 })
		UIHelpers.hint(hints, { if gp then "B" else "BACKSPACE" }, "Back", { height = 26, device = gd, order = 3, color = T.muted, textSize = 15 })
		if playKey ~= "" then UIHelpers.hint(hints, { playKey }, "Close", { height = 26, device = gd, order = 4, color = T.muted, textSize = 15 }) end
		if S.state.screen == "Map" and S.state.mode == "Cpu" then UIHelpers.hint(hints, { "↑" }, "CPU level", { height = 26, device = gd, order = 5, color = T.muted, textSize = 15 }) end
	end

	-- Preview camera ---------------------------------------------------------------------------------------------------
	-- The map and ready screens show the focused map the way its fighters see it: StageController.previewArena puts up
	-- the arena's fight set and mood and hides the district (world, Contract D), and the camera sits on the arena's
	-- PreviewCam at its FieldOfView. Every map is its own stage, so the view cuts between maps under a short dip to dark
	-- (live) instead of gliding through the hidden city; leaving the map screens dips back to the lobby view. A CPU fight
	-- starting from the flow keeps the shot and the stage: the fight's StageController.setArena replaces the preview and
	-- the fight camera glides from the shot.
	local cam: { saved: any?, shown: string?, model: Instance?, dip: number, handover: number } = { saved = nil, shown = nil, model = nil, dip = 0, handover = 0 }
	local function camera(): Camera?
		return if env.camera then env.camera() else nil
	end
	local function stageModule(): any
		if not env.stage then return nil end
		local ok, m = pcall(env.stage)
		return if ok and typeof(m) == "table" and typeof(m.previewArena) == "function" then m else nil
	end
	local function stagePreview(model: Instance?): boolean
		local m = stageModule()
		if not m then return false end
		local ok, up = pcall(m.previewArena, model)
		return ok and up == true
	end
	-- The flow only opens in the lobby, where the camera follows the character: a Scriptable camera seen when the
	-- preview starts is someone's transient shot (e.g. the few frames a practice exit still holds the fight camera), so
	-- the preview hands back a following camera, never that frozen shot.
	local function handBack(c: Camera, saved: any)
		local t = PlayFlow.lobbyCameraType(saved.type)
		c.CameraType = t
		local subject = saved.subject
		if t ~= saved.type or not (subject and subject.Parent) then
			local character = if player:IsA("Player") then (player :: Player).Character else nil
			local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
			subject = humanoid or subject
		end
		c.CameraSubject = subject
	end
	-- Puts the view where the flow wants it now (S.previewId: a map, or nil for the lobby view).
	local function applyPreview()
		local want = S.previewId
		if want == cam.shown then return end
		cam.handover += 1
		local c = camera()
		if want and c then
			local model = PlayFlow.arenaModel(env.world(), want)
			local shot = PlayFlow.previewFrame(model)
			if shot then
				if not cam.saved then
					cam.saved = { type = c.CameraType, subject = c.CameraSubject, cframe = c.CFrame, fov = c.FieldOfView }
				end
				cam.model = if stagePreview(model) then model else nil
				c.CameraType = Enum.CameraType.Scriptable
				c.CFrame = shot
				c.FieldOfView = PlayFlow.previewFov(model) or cam.saved.fov
				cam.shown = want
				return
			end
		end
		-- The lobby view: the district back, the camera where it was, following the character.
		if cam.model then stagePreview(nil); cam.model = nil end
		local saved = cam.saved
		cam.saved = nil
		cam.shown = nil
		if c and saved then
			c.CFrame = saved.cframe
			handBack(c, saved)
			c.FieldOfView = saved.fov
		end
	end
	-- The scene dips to dark under the panel (the flow's cards stay up), changes, and comes back.
	local dipGui: ScreenGui? = if live then make("ScreenGui", { Name = "FightingLabPlayDip", ResetOnSpawn = false, DisplayOrder = 34, Enabled = false, IgnoreGuiInset = true, ScreenInsets = Enum.ScreenInsets.None, Parent = env.parent }) else nil
	local dipBlack: Frame? = if dipGui then make("Frame", { Name = "Black", BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = dipGui }) else nil
	local function dipToPreview()
		local g, black = dipGui, dipBlack
		if not (g and black) then applyPreview(); return end
		cam.dip += 1
		local token = cam.dip
		g.Enabled = true
		local darken = PlayFlow.DIP_IN * black.BackgroundTransparency
		UIHelpers.tween(black, darken, { BackgroundTransparency = 0 }, Enum.EasingStyle.Linear)
		task.delay(darken, function()
			if token ~= cam.dip or destroyed then return end
			applyPreview()
			UIHelpers.tween(black, PlayFlow.DIP_OUT, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			task.delay(PlayFlow.DIP_OUT + 0.03, function()
				if token == cam.dip and not destroyed then g.Enabled = false end
			end)
		end)
	end
	local function cancelDip()
		cam.dip += 1
		if dipBlack then dipBlack.BackgroundTransparency = 1 end
		if dipGui then dipGui.Enabled = false end
	end
	local function previewTo(arenaId: string?)
		if S.previewId == arenaId then return end
		S.previewId = arenaId
		if camera() then dipToPreview() end
	end
	-- Ends the preview now, without a dip: restore (the lobby view, e.g. under the travel fade or before the fighter
	-- select takes the camera) or hand over (a fight takes the stage and the camera from here).
	local function endPreview(restore: boolean)
		S.previewId = nil
		cancelDip()
		if restore then applyPreview(); return end
		local model, saved = cam.model, cam.saved
		cam.model, cam.saved, cam.shown = nil, nil, nil
		if not (live and model) then return end
		cam.handover += 1
		local token = cam.handover
		task.delay(PlayFlow.HANDOVER_SECONDS, function()
			if token ~= cam.handover or destroyed or S.open then return end
			local m = stageModule()
			local still = m and typeof(m.previewing) == "function" and m.previewing() == model
			if not still then return end
			-- No fight took the stage (refused after the move): the district and the lobby camera come back.
			stagePreview(nil)
			local c = camera()
			if c and saved and c.CameraType == Enum.CameraType.Scriptable then
				handBack(c, saved)
				c.FieldOfView = saved.fov
			end
		end)
	end
	-- The preview holds while the map screens are up: one that could not start (its arena or shot not there yet, e.g.
	-- right after joining) is retried, and a shot something else moved (a camera reset when the character respawns) is
	-- put back. Never during a dip, so the cut stays hidden.
	local function holdPreview()
		local want = S.previewId
		if not want or (dipGui and dipGui.Enabled) then return end
		local c = camera()
		if not c then return end
		if cam.shown ~= want then
			applyPreview()
		elseif c.CameraType ~= Enum.CameraType.Scriptable then
			local shot = PlayFlow.previewFrame(cam.model or PlayFlow.arenaModel(env.world(), want))
			if shot then
				c.CameraType = Enum.CameraType.Scriptable
				c.CFrame = shot
			end
		end
	end
	local function previewWanted(cards: { Card }): string?
		local s = S.state
		if not S.open then return nil end
		if s.screen == "Ready" then return s.arena end
		if s.screen == "Map" then
			local card = cards[s.focus]
			return if card and card.arena then card.id else nil
		end
		return nil
	end

	-- Cards --------------------------------------------------------------------------------------------------------------
	local function buildCard(index: number, c: Card, size: Vector2, small: boolean): any
		local b: TextButton = make("TextButton", { Name = "Card_" .. c.id, Text = "", AutoButtonColor = false, Selectable = false, BackgroundColor3 = T.panel, BackgroundTransparency = if small then 0.12 else 0.04, BorderSizePixel = 0, Size = UDim2.fromOffset(size.X, size.Y), LayoutOrder = index, ClipsDescendants = true, Parent = cardsFrame })
		UIHelpers.gradient(b, Color3.fromRGB(30, 36, 50), Color3.fromRGB(10, 12, 18), 90)
		UIHelpers.corner(b, 5)
		local stroke = UIHelpers.outline(b, WHITE, 1, 0.82)
		local pop: UIScale = make("UIScale", { Parent = b })
		local strip = make("Frame", { Name = "Strip", BackgroundColor3 = c.color, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, if small then 5 else 7), Parent = b })
		local fill = make("Frame", { Name = "Fill", BackgroundColor3 = c.color, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 0, Parent = b })
		local pad = if small then 14 else 22
		local mark: TextLabel? = nil
		if c.mark and not small then
			mark = text(b, "Mark", c.mark, T.display, 120, c.color, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 10, 0, 12), Size = UDim2.fromOffset(260, 120), TextXAlignment = Enum.TextXAlignment.Right, TextTransparency = 0.82 })
		end
		local kicker = text(b, "Kicker", c.kicker or "", T.number, 16, c.color, { Position = UDim2.fromOffset(pad, if small then 10 else 22), Size = UDim2.new(1, -2 * pad, 0, 18), Visible = c.kicker ~= nil and not small })
		local titleSize = if small then 23 else 44
		local titleY = if small then 14 else size.Y * 0.40
		-- Titles shrink to fit their card (one line), never cut.
		local title = text(b, "Title", c.title, T.display, titleSize, T.text, { Position = UDim2.fromOffset(pad - 2, titleY), Size = UDim2.new(1, -2 * pad + 4, 0, titleSize + 8), TextScaled = true })
		make("UITextSizeConstraint", { MaxTextSize = titleSize, MinTextSize = 14, Parent = title })
		local sub = text(b, "Sub", c.sub, T.medium, if small then 14 else 19, T.muted, { Position = UDim2.fromOffset(pad, titleY + titleSize + (if small then 6 else 10)), Size = UDim2.new(1, -2 * pad, 0, if small then 36 else 52), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
		local chip = text(b, "Chip", c.chip, T.heavy, if small then 12 else 14, c.color, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, pad, 1, if small then -10 else -18), Size = UDim2.fromOffset(0, if small then 22 else 28), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 0.82, BackgroundColor3 = c.color })
		UIHelpers.corner(chip, 3)
		make("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9), Parent = chip })
		local notch = UIHelpers.slantCap(b, "Notch", 26, 26, "TR", c.color, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), ZIndex = 3 })
		local r = { button = b, stroke = stroke, pop = pop, strip = strip, fill = fill, title = title, sub = sub, chip = chip, kicker = kicker, mark = mark, notch = notch, small = small }
		table.insert(conns, b.Activated:Connect(function()
			if not S.open then return end
			controller.action("Pick:" .. index)
		end))
		table.insert(conns, b.MouseEnter:Connect(function()
			if not S.open or env.device() == "touch" or S.state.focus == index then return end
			controller.action("Focus:" .. index)
		end))
		return r
	end
	local function paintCard(r: any, c: Card, focused: boolean)
		local primary = c.primary == true and c.enabled
		r.fill.BackgroundTransparency = if primary then (if focused then 0.05 else 0.18) elseif focused then 0.82 else 1
		r.title.Text = c.title
		r.title.TextColor3 = if primary then T.ink elseif c.enabled then T.text else T.dim
		r.sub.Text = c.sub
		r.sub.TextColor3 = if primary then T.ink elseif c.enabled then (if focused then T.text else T.muted) else T.dim
		r.chip.Text = c.chip
		r.chip.TextColor3 = if primary then T.ink elseif c.enabled then c.color else T.loss
		r.chip.BackgroundColor3 = if primary then WHITE elseif c.enabled then c.color else T.loss
		r.chip.BackgroundTransparency = if primary then 0.55 else 0.82
		r.kicker.TextColor3 = if primary then T.ink else c.color
		r.stroke.Color = if focused then (if primary then WHITE else c.color) else WHITE
		r.stroke.Thickness = if focused then 3 else 1
		r.stroke.Transparency = if focused then 0 else 0.82
		r.notch.Visible = focused
		r.notch.BackgroundColor3 = if primary then WHITE else c.color
		r.pop.Scale = if focused then 1.05 else 1
		r.button:SetAttribute("Focused", focused)
		r.button:SetAttribute("Available", c.enabled)
	end

	local function rebuildCards(cards: { Card })
		for _, c in cardsFrame:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
		table.clear(refs.cards)
		local s = S.state
		local size = CARD_SIZES[s.screen] or Vector2.new(300, 220)
		local small = s.screen == "Map"
		if s.screen == "Map" and #cards > 4 then size = Vector2.new(208, 128) end
		for i, c in cards do
			local sz = size
			if s.screen == "Ready" and c.id == "fight" then sz = Vector2.new(400, size.Y) end
			refs.cards[i] = buildCard(i, c, sz, small)
		end
		-- Map screens: the cards sit low so the preview owns the middle of the screen.
		cardsFrame.Position = if small then UDim2.new(0.5, 0, 1, -170) else UDim2.fromScale(0.5, 0.58)
		cardsFrame.Size = UDim2.new(1, -120, 0, size.Y + 20)
		notice.Position = if small then UDim2.new(0.5, 0, 1, -248) else UDim2.new(0.5, 0, 0.58, -(size.Y // 2) - 22)
	end

	local function render()
		if destroyed then return end
		local s = S.state
		gui.Enabled = S.open and not S.suppressed
		if not S.open then return end
		local f = facts()
		local cards = PlayFlow.cards(s, f)
		local ids = { s.screen, tostring(s.mode) }
		for _, c in cards do table.insert(ids, c.id) end
		local signature = table.concat(ids, "|")
		if signature ~= S.signature then
			S.signature = signature
			rebuildCards(cards)
		end
		local focusOnCards = not (s.screen == "Map" and s.zone == "level")
		for i, c in cards do
			local r = refs.cards[i]
			if r then paintCard(r, c, focusOnCards and env.device() ~= "touch" and s.focus == i) end
		end
		-- Header.
		local modeName = s.mode and PlayFlow.MODE_NAMES[s.mode] or nil
		local crumb = { "PLAY" }
		if modeName and s.screen ~= "Search" then table.insert(crumb, modeName) end
		local chosen = if s.arena then (function() for _, a in f.arenas do if a.id == s.arena then return a end end return nil end)() else nil
		if s.screen == "Ready" and chosen then table.insert(crumb, string.upper(chosen.name)) end
		refs.crumb.Text = table.concat(crumb, "  ›  ")
		local texts = SCREEN_TEXT[s.screen] or { "", "" }
		local title, sub = texts[1], texts[2]
		if s.screen == "Map" then
			sub = if s.mode == "Duel" then "Any map finds an opponent fastest. Pick a map to wait there." else "Watch each map behind this panel. Enter picks it."
		elseif s.screen == "Ready" then
			sub = "One more press and the fight starts."
		elseif s.screen == "Search" then
			local seconds = if f.waiting then f.waitSeconds or 0 else f.searchSeconds or 0
			local where = (function()
				for _, a in f.arenas do if a.id == f.waitArena then return string.upper(a.name) end end
				return "THE CIRCLE"
			end)()
			title = if f.waiting then "WAITING AT " .. where else "FINDING AN OPPONENT"
			sub = clockText(seconds) .. "  ·  " .. (if f.waiting then "Anyone who picks this map or Any map joins you." else "Walk around while you wait.")
		end
		refs.title.Text = title
		refs.sub.Text = sub
		-- Level row.
		local showLevel = s.screen == "Map" and s.mode == "Cpu"
		levelRow.Visible = showLevel
		if showLevel then
			for level, b in refs.levels do
				b.setSelected(level == s.difficulty)
				b.setFocused(s.zone == "level" and level == s.difficulty and env.device() ~= "touch")
			end
			refs.levelCaption.TextColor3 = if s.zone == "level" then T.text else T.muted
			refs.levelHint.Text = UIHelpers.DifficultyInfo[s.difficulty] and UIHelpers.DifficultyInfo[s.difficulty].text or ""
		end
		-- Showcase.
		local showArena: Arena? = nil
		if s.screen == "Map" then
			local card = cards[s.focus]
			showArena = card and card.arena or nil
			showcase.Visible = true
			if showArena then
				refs.showName.Text = string.upper(showArena.name)
				refs.showName.TextColor3 = showArena.color:Lerp(WHITE, 0.25)
				refs.showTag.Text = showArena.tagline
				refs.showChip.Text = arenaChip(showArena, s.mode)
				refs.showChip.BackgroundColor3 = if (s.mode == "Duel" and freeForDuel(showArena)) or (s.mode ~= "Duel" and freeForCpu(showArena)) then showArena.color else T.loss
			else
				refs.showName.Text = "ANY MAP"
				refs.showName.TextColor3 = T.text
				refs.showTag.Text = "You fight on the first free map, against the first player ready."
				refs.showChip.Text = "RECOMMENDED"
				refs.showChip.BackgroundColor3 = T.ember
			end
		elseif s.screen == "Ready" and chosen then
			showcase.Visible = true
			refs.showName.Text = string.upper(chosen.name)
			refs.showName.TextColor3 = chosen.color:Lerp(WHITE, 0.25)
			refs.showTag.Text = chosen.tagline
			refs.showChip.Text = "VS CPU  ·  " .. string.upper(s.difficulty)
			refs.showChip.BackgroundColor3 = (UIHelpers.DifficultyInfo[s.difficulty] or { color = T.gold }).color
		else
			showcase.Visible = false
		end
		showcase.Position = if s.screen == "Map" then UDim2.new(0, 64, 0.5, -100) else UDim2.new(0, 64, 0.5, -150)
		if s.screen == "Ready" then cardsFrame.Position = UDim2.new(0.5, 0, 1, -200) end
		-- Fighter chip (map / ready screens).
		local def = UIHelpers.fighterDef(Roster, f.fighter) or Roster.get(Roster.order[1])
		fighterChip.Visible = s.screen == "Map" or s.screen == "Ready"
		header.Size = if fighterChip.Visible then UDim2.new(1, -470, 0, 150) else UDim2.new(1, -128, 0, 150)
		if refs.fighterId ~= def.id then
			refs.fighterId = def.id
			for _, c in refs.fighterMono:GetChildren() do c:Destroy() end
			UIHelpers.monogram(refs.fighterMono, def, 56)
			refs.fighterName.Text = string.upper(def.displayName)
			refs.fighterName.TextColor3 = def.accentColor
		end
		-- Notice / pending.
		local noticeText = s.notice
		if s.pending then
			noticeText = "HEADING TO " .. (if chosen then string.upper(chosen.name) else "THE MAP") .. "..."
		end
		notice.Visible = noticeText ~= nil
		notice.Text = noticeText or ""
		notice.BackgroundColor3 = if s.pending then T.gold else T.warm
		-- Dim / shade.
		local scenic = s.screen == "Map" or s.screen == "Ready"
		dim.Visible = not scenic
		shade.Visible = scenic
		-- Footer.
		refs.backButton.button.Visible = #s.back > 0 or (s.screen == "Map" and s.zone == "level")
		paintHints()
		-- Camera.
		previewTo(previewWanted(cards))
	end

	local function hand(req: Request?)
		if not req then return end
		if req.kind == "Close" then controller.close(); return end
		local ok = env.send(req)
		if req.kind == "QuickPlay" and not req.close and ok then
			S.pendingSince = clock()
		end
		if req.close and ok then
			S.state.pending = false
			controller.close()
		end
		if not ok and S.state.pending then
			S.state.pending = false
			S.state.notice = "NOT RIGHT NOW  ·  TRY AGAIN IN A MOMENT"
		end
	end

	controller = {
		gui = gui,
		open = function(screen: string?): boolean
			if destroyed then return false end
			local f = facts()
			local start = screen or (if f.searching or f.waiting then "Search" else "Who")
			local wasOpen = S.open
			S.state = PlayFlow.new({ screen = start, difficulty = if env.difficulty then env.difficulty() else S.state.difficulty })
			if start == "Search" then
				-- CANCEL is focused until FIGHT CPU INSTEAD is offered.
				local first = PlayFlow.cards(S.state, f)[1]
				if first and not first.enabled then S.state.focus = 2 end
			end
			S.suspendedState = nil
			S.signature = ""
			S.open = true
			if live then
				-- Roblox's own GUI selection would take Enter / A from the flow (the old panel's lost first press).
				pcall(function() GuiService.SelectedObject = nil end)
				UIHelpers.holdPlayerList(true)
			end
			render()
			if not wasOpen then
				if live then
					scale.Scale = 0.94
					UIHelpers.tween(scale, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
				end
				sound("MenuSelect")
			end
			if env.onChanged and not wasOpen then env.onChanged() end
			return true
		end,
		close = function()
			if not S.open then return end
			S.open = false
			S.state.pending = false
			-- Back to the lobby view (under a dip) and the camera handed back.
			previewTo(nil)
			if live then UIHelpers.holdPlayerList(false) end
			render()
			sound("MenuBack")
			if env.onChanged then env.onChanged() end
		end,
		isOpen = function() return S.open end,
		state = function() return S.state end,
		screen = function() return S.state.screen end,
		cards = function() return PlayFlow.cards(S.state, facts()) end,
		facts = facts,
		action = function(a: string)
			if not S.open or destroyed then return end
			local before = S.state
			local f = facts()
			local nextState, req = PlayFlow.act(before, f, a)
			S.state = nextState
			if env.setDifficulty and nextState.difficulty ~= before.difficulty then pcall(env.setDifficulty, nextState.difficulty) end
			local moved = nextState.focus ~= before.focus or nextState.screen ~= before.screen or nextState.zone ~= before.zone or nextState.difficulty ~= before.difficulty
			if req then
				sound(if req.kind == "Close" then "MenuBack" else "MenuSelect")
			elseif nextState.screen ~= before.screen then
				sound(if a == "Back" then "MenuBack" else "MenuSelect")
			elseif moved then
				sound("MenuMove")
			end
			render()
			hand(req)
		end,
		pick = function(id: string): boolean
			if not S.open then return false end
			for i, c in PlayFlow.cards(S.state, facts()) do
				if c.id == id then controller.action("Pick:" .. i); return true end
			end
			return false
		end,
		refresh = function()
			if S.open then render() end
		end,
		tick = function(_dt: number)
			if not S.open or destroyed then return end
			holdPreview()
			if S.state.pending and clock() - S.pendingSince > PlayFlow.PENDING_SECONDS then
				S.state.pending = false
				S.state.notice = "NO ANSWER YET  ·  PRESS FIGHT! AGAIN"
				render()
			end
			-- The search clock and the CPU offer tick once a second.
			if S.state.screen == "Search" then
				local now = math.floor(env.serverNow())
				if now ~= S.lastSecond then S.lastSecond = now; render() end
			end
		end,
		onTeleport = function(payload: any)
			local p = if typeof(payload) == "table" then payload else {}
			-- A CPU fight or practice from the flow: the fight takes the map's stage and glides its camera from the
			-- preview shot (hand over before the flow closes, so closing does not bring the lobby view back). Anything
			-- else (wait on a circle, a match found, travel): the fade is black now, so the lobby view comes back.
			local fight = p.reason == "Cpu" or p.reason == "Practice"
			if fight and (cam.saved or cam.model) then endPreview(false) end
			if S.open then
				S.open = false
				S.state.pending = false
				if live then UIHelpers.holdPlayerList(false) end
				render()
				if env.onChanged then env.onChanged() end
			end
			if not fight and cam.saved then
				if live then
					-- Restore once the travel fade is black (it takes ~0.15 s), so the cut never shows.
					local saved = cam.saved
					task.delay(0.16, function() if cam.saved == saved and not S.open then endPreview(true) end end)
				else
					endPreview(true)
				end
			end
		end,
		onRejected = function(payload: any): boolean
			local p = if typeof(payload) == "table" then payload else {}
			if p.request ~= "QuickPlay" then return false end
			local s = S.state
			local fromFlow = S.open and s.pending
			-- VS PLAYER on a map closes the flow at once: a busy map reopens it on the map screen with the offer.
			local reopen = not S.open and p.reason == "ArenaBusy" and typeof(p.arena) == "string"
			if not fromFlow and not reopen then return false end
			if reopen then
				local back = { { screen = "Who", focus = 1, mode = nil } }
				S.state = PlayFlow.new({ screen = "Map", difficulty = s.difficulty })
				S.state.mode = "Duel"
				S.state.back = back
				S.signature = ""
				S.open = true
				if live then UIHelpers.holdPlayerList(true) end
				if env.onChanged then env.onChanged() end
			end
			S.state = PlayFlow.rejected(S.state, facts(), p)
			render()
			sound("MenuBack")
			return true
		end,
		-- The fighter select takes over the screen (Change fighter): the flow steps aside and comes back after.
		suspend = function()
			if not S.open then return end
			S.suspendedState = table.clone(S.state)
			S.open = false
			endPreview(true)
			if live then UIHelpers.holdPlayerList(false) end
			render()
		end,
		resume = function(): boolean
			local saved = S.suspendedState
			if not saved or destroyed then return false end
			S.suspendedState = nil
			S.state = saved
			S.state.pending = false
			S.signature = ""
			S.open = true
			if live then UIHelpers.holdPlayerList(true) end
			render()
			if env.onChanged then env.onChanged() end
			return true
		end,
		suspended = function() return S.suspendedState ~= nil end,
		previewArena = function() return S.previewId end,
		setSuppressed = function(on: boolean)
			S.suppressed = on
			gui.Enabled = S.open and not S.suppressed
		end,
		destroy = function()
			if destroyed then return end
			if S.open and live then UIHelpers.holdPlayerList(false) end
			endPreview(true)
			destroyed = true
			for _, c in conns do c:Disconnect() end
			table.clear(conns)
			unfit()
			gui:Destroy()
			if dipGui then dipGui:Destroy() end
		end,
	}
	return controller
end

return PlayFlow
