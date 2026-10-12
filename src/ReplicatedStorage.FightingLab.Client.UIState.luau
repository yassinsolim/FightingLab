--!strict
local UIHelpers = require(script.Parent.UIHelpers)
local NetProtocol = require(script.Parent.Parent:WaitForChild("NetProtocol"))
local M = {}

--------------------------------------------------------------------------------------------------------------------
-- Lobby view model (OV6). Pure: maps session/player/pad facts to what the lobby HUD shows. Every lobby interaction is
-- an E ProximityPrompt now (kiosk, "Fight CPU" on a duel circle, dojo pads), so the HUD only explains and never
-- binds keys of its own. LobbyUI renders it and LobbyUI_Test checks the text for every state.
--------------------------------------------------------------------------------------------------------------------
export type LobbyInput = {
	sessionState: string?, -- FightSession.state(): Lobby | Countdown | Fight | Results | Practice
	duelState: string?, -- Player attribute DuelState: Lobby | Queued | Countdown | Fighting | Results | Practice
	arenaName: string?, -- display name of the arena the player waits in
	padSide: number?, -- 0 none, 1 = P1 circle, 2 = P2 circle
	practicePad: string?, -- "Training" | "Cpu" while standing on a dojo pad
	queuedSeconds: number?, -- time spent waiting alone on a duel circle
	countdownEndsAt: number?, -- workspace:GetServerTimeNow() deadline
	now: number?,
	keyboard: boolean?, -- false on touch-only devices: tap wording
	interactKey: string?, -- Controls lobby interact label ("E")
	searching: boolean?, -- in the Quick Duel queue (Player attribute QuickQueue > 0)
	searchSeconds: number?, -- time spent in the queue
	quickStatus: string?, -- Player attribute QuickStatus: Searching | Busy | Matched
}
export type LobbyView = {
	mode: string, -- Hidden | Results | Practice | Countdown | Waiting | CpuOffer | PracticeChoice | Searching | Lobby
	title: string,
	subtitle: string,
	offer: string,
	digit: number?,
	side: number,
	padMode: string?,
	canChooseFighter: boolean,
	menuAllowed: boolean,
	showIdentity: boolean,
	-- Searching: the queue offers "Fight CPU instead" (after QUICK_CPU_OFFER seconds).
	cpuInstead: boolean?,
}

-- The server accepts RequestCpu after CpuOfferSeconds - 1 (clock-skew allowance); offer it a little after that.
M.CPU_OFFER_DELAY = math.max(2.5, ((NetProtocol :: any).CpuOfferSeconds or 4) - 0.8)
-- Quick Duel: "Fight CPU instead" after this long alone in the queue.
M.QUICK_CPU_OFFER = (NetProtocol :: any).QuickCpuOfferSeconds or 12
M.LOBBY_MODES = { Lobby = true, Waiting = true, CpuOffer = true, PracticeChoice = true, Searching = true }

-- "0:07" style queue clock.
function M.clock(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

function M.lobbyView(input: LobbyInput): LobbyView
	local session = input.sessionState or "Lobby"
	local duel = input.duelState or "Lobby"
	local keyboard = input.keyboard ~= false
	local key = input.interactKey or "E"
	local press = if keyboard then "Press " .. key else "Tap"
	local side = input.padSide or 0
	local view: LobbyView = {
		mode = "Lobby", title = "", subtitle = "", offer = "", digit = nil, side = side, padMode = nil,
		canChooseFighter = false, menuAllowed = false, showIdentity = true,
	}
	if session == "Fight" or duel == "Fighting" then
		view.mode = "Hidden"; view.showIdentity = false
		return view
	end
	if session == "Results" or duel == "Results" then
		view.mode = "Results"; view.showIdentity = false
		return view
	end
	if session == "Practice" or duel == "Practice" then
		view.mode = "Practice"; view.showIdentity = false; view.menuAllowed = true
		view.title = "PRACTICE"
		view.subtitle = "Practice keys are listed on the panel"
		return view
	end
	if session == "Countdown" or duel == "Countdown" then
		view.mode = "Countdown"
		view.title = "DUEL STARTING"
		view.subtitle = "Step off the circle to cancel"
		view.digit = UIHelpers.countdownDigit(input.countdownEndsAt, input.now or 0)
		return view
	end
	view.menuAllowed = true
	view.canChooseFighter = duel == "Lobby" or duel == "Queued"
	local pad = input.practicePad
	if pad == "Training" or pad == "Cpu" then
		view.mode = "PracticeChoice"; view.padMode = pad
		if pad == "Training" then
			view.title = "TRAINING"
			view.subtitle = "Free training or a guided lesson against a dummy"
			view.offer = press .. " to start training"
		else
			view.title = "VERSUS CPU"
			view.subtitle = "A practice match: pick an opponent and a difficulty"
			view.offer = press .. " to set up the match"
		end
		return view
	end
	if duel == "Queued" then
		local arena = input.arenaName or "the arena"
		view.title = "WAITING FOR A CHALLENGER"
		view.subtitle = string.upper(arena) .. "  ·  " .. (if side == 2 then "P2" else "P1") .. " CIRCLE  ·  STEP OFF TO LEAVE"
		if (input.queuedSeconds or 0) >= M.CPU_OFFER_DELAY then
			view.mode = "CpuOffer"
			view.offer = "No challenger yet? " .. press .. " to fight a CPU"
		else
			view.mode = "Waiting"
		end
		return view
	end
	if input.searching then
		local seconds = input.searchSeconds or 0
		view.mode = "Searching"
		if input.quickStatus == "Matched" then
			view.title = "OPPONENT FOUND"
			view.subtitle = "Heading to the arena..."
			return view
		end
		view.title = "SEARCHING  " .. M.clock(seconds)
		view.subtitle = if input.quickStatus == "Busy" then "All arenas are busy  ·  you are next in line" else "Walk around while you wait  ·  PLAY to cancel"
		if seconds >= M.QUICK_CPU_OFFER then
			view.cpuInstead = true
			view.offer = "No opponent yet? Fight a CPU instead"
		end
		return view
	end
	view.mode = "Lobby"
	view.title = "PRESS PLAY TO FIGHT"
	view.subtitle = "Or walk into a glowing circle  ·  Fighter Kiosk: change fighter"
	return view
end

--------------------------------------------------------------------------------------------------------------------
-- World prompts (ProximityPrompts created by LobbyUI on the kiosk and the pads). Pure: which prompt is live, and its
-- texts. The kiosk prompt may be the world's own server prompt; LobbyUI restyles it either way.
--------------------------------------------------------------------------------------------------------------------
export type PromptInput = { view: LobbyView, overlay: boolean?, cpuPending: boolean?, arenaId: string?, padSide: number?, templatesReady: boolean? }
export type PromptSpec = { enabled: boolean, action: string, object: string, arenaId: string?, side: number? }
export type PromptSet = { kiosk: PromptSpec, cpu: PromptSpec, training: PromptSpec, versus: PromptSpec }

M.PROMPT_TEXT = {
	kiosk = { action = "Choose Fighter", object = "Fighter Kiosk" },
	cpu = { action = "Fight CPU", object = "No challenger yet" },
	training = { action = "Start Training", object = "Training Dummy" },
	versus = { action = "Versus CPU", object = "Practice Match" },
}

function M.prompts(input: PromptInput): PromptSet
	local v = input.view
	local free = input.overlay ~= true
	local function spec(id: string, enabled: boolean): PromptSpec
		local t = (M.PROMPT_TEXT :: any)[id]
		return { enabled = enabled, action = t.action, object = t.object }
	end
	-- The kiosk is a walk-up station: only offered while free in the lobby (queued players stand on a circle; Quick Duel
	-- searchers walk around freely).
	local walking = v.mode == "Lobby" or v.mode == "Searching"
	local kiosk = spec("kiosk", free and walking and v.canChooseFighter and input.templatesReady ~= false)
	if input.templatesReady == false and free and walking then kiosk.object = "Fighters loading..." end
	local cpu = spec("cpu", free and v.mode == "CpuOffer" and input.cpuPending ~= true)
	cpu.arenaId = input.arenaId
	cpu.side = input.padSide
	if input.cpuPending == true and v.mode == "CpuOffer" then cpu.object = "Calling a CPU..." end
	local training = spec("training", free and v.mode == "PracticeChoice" and v.padMode == "Training")
	local versus = spec("versus", free and v.mode == "PracticeChoice" and v.padMode == "Cpu")
	return { kiosk = kiosk, cpu = cpu, training = training, versus = versus }
end

--------------------------------------------------------------------------------------------------------------------
-- Pickers (CPU difficulty after "Fight CPU", dojo setup after "Start Training" / "Versus CPU"). Pure reducer over rows:
--   cycle  : left/right steps through options (opponent)
--   choice : left/right picks one of a few options (difficulty, lesson)
--   action : confirm triggers the picker's result
-- Actions: Up | Down | Left | Right | Confirm | Back | Set:<row>:<index> (mouse) | Go:<row> (mouse on an action row)
--------------------------------------------------------------------------------------------------------------------
export type PickerRow = { id: string, kind: string, options: { string }, index: number }
export type Picker = { kind: string, rows: { PickerRow }, focus: number, done: boolean, cancelled: boolean, result: { [string]: any }? }

local function rowIndex(p: Picker, id: string): number?
	for i, r in p.rows do if r.id == id then return i end end
	return nil
end
function M.pickerValue(p: Picker, id: string): string?
	local i = rowIndex(p, id)
	if not i then return nil end
	local r = p.rows[i]
	return r.options[r.index]
end

-- kind: "cpu" | "training" | "versus". opts: fighters (roster order), opponent (id), difficulty, lesson (bool)
function M.pickerNew(kind: string, opts: { [string]: any }?): Picker
	local o = opts or {}
	local fighters: { string } = o.fighters or {}
	local difficulty = UIHelpers.difficultyIndex(o.difficulty or "Normal")
	local opponent = math.max(1, table.find(fighters, o.opponent) or 1)
	local rows: { PickerRow } = {}
	if kind == "cpu" then
		table.insert(rows, { id = "difficulty", kind = "choice", options = table.clone(UIHelpers.Difficulties), index = difficulty })
	elseif kind == "training" then
		table.insert(rows, { id = "opponent", kind = "cycle", options = table.clone(fighters), index = opponent })
		table.insert(rows, { id = "lesson", kind = "choice", options = { "Free", "Lesson" }, index = if o.lesson then 2 else 1 })
		table.insert(rows, { id = "start", kind = "action", options = { "START" }, index = 1 })
	else
		table.insert(rows, { id = "opponent", kind = "cycle", options = table.clone(fighters), index = opponent })
		table.insert(rows, { id = "difficulty", kind = "choice", options = table.clone(UIHelpers.Difficulties), index = difficulty })
		table.insert(rows, { id = "start", kind = "action", options = { "START" }, index = 1 })
	end
	-- Start on the most likely edit: difficulty for the CPU offer, the start button for dojo setups.
	local focus = if kind == "cpu" then 1 else #rows
	return { kind = kind, rows = rows, focus = focus, done = false, cancelled = false, result = nil }
end

local function result(p: Picker): { [string]: any }
	if p.kind == "cpu" then
		return { request = "RequestCpu", difficulty = M.pickerValue(p, "difficulty") or "Normal" }
	elseif p.kind == "training" then
		return { request = "StartPractice", mode = "Training", opponent = M.pickerValue(p, "opponent"), lesson = M.pickerValue(p, "lesson") == "Lesson" }
	end
	return { request = "StartPractice", mode = "Cpu", opponent = M.pickerValue(p, "opponent"), difficulty = M.pickerValue(p, "difficulty") or "Normal" }
end

function M.pickerAction(state: Picker, action: string): Picker
	local p: Picker = table.clone(state)
	p.rows = table.clone(state.rows)
	for i, r in p.rows do p.rows[i] = table.clone(r) end
	if p.done or p.cancelled then return p end
	local row = p.rows[p.focus]
	local set, setRow, setIndex = string.match(action, "^(Set):([%w_]+):(%d+)$")
	if set then
		local i = rowIndex(p, setRow :: string)
		if i then
			local r = p.rows[i]
			r.index = math.clamp(tonumber(setIndex) or 1, 1, #r.options)
			p.focus = i
		end
		return p
	end
	local go = string.match(action, "^Go:([%w_]+)$")
	if go then
		local i = rowIndex(p, go)
		if i then p.focus = i; p.done = true; p.result = result(p) end
		return p
	end
	if p.kind == "cpu" and (action == "Up" or action == "Down") then
		-- One horizontal row of difficulty cards: every arrow key moves along it.
		action = if action == "Up" then "Left" else "Right"
	end
	if action == "Up" then
		p.focus = math.max(1, p.focus - 1)
	elseif action == "Down" then
		p.focus = math.min(#p.rows, p.focus + 1)
	elseif action == "Left" or action == "Right" then
		local delta = if action == "Left" then -1 else 1
		if row.kind == "cycle" then
			row.index = ((row.index - 1 + delta) % #row.options) + 1
		elseif row.kind == "choice" then
			row.index = math.clamp(row.index + delta, 1, #row.options)
		end
	elseif action == "Confirm" then
		-- Enter / A starts from any row: every value is already picked with the arrows, so there is no extra step.
		p.done = true
		p.result = result(p)
	elseif action == "Back" then
		p.cancelled = true
	end
	return p
end

--------------------------------------------------------------------------------------------------------------------
-- PLAY panel (round 5). Pure: the rows the bottom bar's PLAY panel shows for the current facts, keyboard / gamepad
-- focus over them and the request each item sends. Every action is two steps: open PLAY, pick an item.
--   duel     : QUICK DUEL (server matchmaking queue); while searching CANCEL, and FIGHT CPU INSTEAD after
--              QUICK_CPU_OFFER seconds
--   cpu      : Easy / Normal / Hard (server teleports you onto a free arena and the CPU match starts at once)
--   practice : Free training / Guided lesson / Versus CPU (teleport onto the dojo pad, practice starts)
--   travel   : every arena (its Arrival point, to watch or walk in) and back to the plaza
--------------------------------------------------------------------------------------------------------------------
export type PlayItem = { id: string, label: string, sub: string, enabled: boolean, accent: string }
export type PlayRow = { id: string, title: string, items: { PlayItem } }
export type PlayArena = { id: string, name: string, kind: string, state: string, order: number }
export type PlayInput = {
	searching: boolean?, searchSeconds: number?, quickStatus: string?,
	pending: boolean?, -- a PLAY request is in flight (debounce)
	onCircle: boolean?, -- waiting on a duel circle (Quick Duel already effectively running there)
	freeArenas: number?, -- duel arenas nobody uses (Stations attribute FreeArenas)
	arenas: { PlayArena }?,
}
export type PlayFocus = { row: number, col: number }
M.PLAY_ROW_IDS = { "duel", "cpu", "practice", "travel" } -- "travel" continues as "travel2", "travel3"... (3 per line)
M.PLAY_TRAVEL_PER_ROW = 3
local ARENA_STATE_TEXT: { [string]: string } = { Open = "OPEN", Waiting = "1 WAITING", Countdown = "STARTING", Fighting = "LIVE", Results = "LIVE" }
local CPU_TEXT: { [string]: string } = { Easy = "Learn the basics", Normal = "A fair fight", Hard = "Reads and punishes" }

function M.playRows(input: PlayInput): { PlayRow }
	local can = input.pending ~= true
	local busy = (input.freeArenas or 1) <= 0
	local rows: { PlayRow } = {}
	local duel: { PlayItem } = {}
	if input.searching then
		local secs = input.searchSeconds or 0
		local offer = secs >= M.QUICK_CPU_OFFER
		table.insert(duel, { id = "cpuInstead", label = "FIGHT CPU INSTEAD", sub = if offer then "Nobody yet: a Normal CPU, right now" else string.format("Offered after %d s", M.QUICK_CPU_OFFER), enabled = offer and can and not busy, accent = "warm" })
		table.insert(duel, { id = "cancel", label = "CANCEL SEARCH", sub = "Searching " .. M.clock(secs), enabled = true, accent = "muted" })
	else
		local sub = if input.onCircle then "You are already waiting on a circle" elseif busy then "All arenas busy: you will queue" else "Find an opponent"
		table.insert(duel, { id = "quick", label = "QUICK DUEL", sub = sub, enabled = can and input.onCircle ~= true, accent = "ember" })
	end
	table.insert(rows, { id = "duel", title = "VERSUS A PLAYER", items = duel })
	local cpu: { PlayItem } = {}
	for _, d in { "Easy", "Normal", "Hard" } do
		local ok = can and (input.onCircle == true or not busy)
		table.insert(cpu, { id = "cpu:" .. d, label = string.upper(d), sub = if ok or not can then CPU_TEXT[d] else "All arenas busy", enabled = ok, accent = d })
	end
	table.insert(rows, { id = "cpu", title = "FIGHT CPU", items = cpu })
	table.insert(rows, { id = "practice", title = "PRACTICE", items = {
		{ id = "practice:Training", label = "FREE TRAINING", sub = "A dummy, your rules", enabled = can, accent = "cool" },
		{ id = "practice:Lesson", label = "GUIDED LESSON", sub = "10 short steps", enabled = can, accent = "cool" },
		{ id = "practice:Cpu", label = "VERSUS CPU", sub = "Practice match", enabled = can, accent = "warm" },
	} })
	local travel: { PlayItem } = {}
	local arenas = table.clone(input.arenas or {})
	table.sort(arenas, function(a, b)
		if a.order ~= b.order then return a.order < b.order end
		return a.id < b.id
	end)
	for _, a in arenas do
		local state = if a.kind == "Practice" then "DOJO" else (ARENA_STATE_TEXT[a.state] or "OPEN")
		table.insert(travel, { id = "travel:" .. a.id, label = string.upper(a.name), sub = state, enabled = can, accent = if a.kind == "Practice" then "cool" else "gold" })
	end
	table.insert(travel, { id = "travel:Plaza", label = "PLAZA", sub = "Start area", enabled = can, accent = "muted" })
	-- Three per line so every arena name fits: rows "travel", "travel2", ... (arrow keys move between the lines).
	for i = 1, #travel, M.PLAY_TRAVEL_PER_ROW do
		local line = table.move(travel, i, math.min(#travel, i + M.PLAY_TRAVEL_PER_ROW - 1), 1, {})
		local n = (i - 1) // M.PLAY_TRAVEL_PER_ROW + 1
		table.insert(rows, { id = if n == 1 then "travel" else "travel" .. n, title = if n == 1 then "GO TO" else "", items = line })
	end
	return rows
end

-- Where the focus starts: the item most players want next.
function M.playDefaultFocus(rows: { PlayRow }): PlayFocus
	local duel = rows[1]
	if duel and duel.items[1] and duel.items[1].id == "cpuInstead" and not duel.items[1].enabled then return { row = 1, col = 2 } end
	return { row = 1, col = 1 }
end

-- Keyboard / gamepad / mouse focus: Up | Down | Left | Right | Confirm | Set:<row>:<col>. Returns the new focus and
-- the id of an item that was activated (Confirm on an enabled item).
function M.playNav(rows: { PlayRow }, focus: PlayFocus, action: string): (PlayFocus, string?)
	local row = math.clamp(focus.row, 1, math.max(1, #rows))
	local function clampCol(r: number, c: number): number
		local items = rows[r] and rows[r].items or {}
		return math.clamp(c, 1, math.max(1, #items))
	end
	local col = clampCol(row, focus.col)
	local setRow, setCol = string.match(action, "^Set:(%d+):(%d+)$")
	if setRow then
		local r = math.clamp(tonumber(setRow) or 1, 1, math.max(1, #rows))
		return { row = r, col = clampCol(r, tonumber(setCol) or 1) }, nil
	end
	if action == "Up" or action == "Down" then
		local nextRow = math.clamp(row + (if action == "Up" then -1 else 1), 1, math.max(1, #rows))
		return { row = nextRow, col = clampCol(nextRow, col) }, nil
	elseif action == "Left" or action == "Right" then
		return { row = row, col = clampCol(row, col + (if action == "Left" then -1 else 1)) }, nil
	elseif action == "Confirm" then
		local item = rows[row] and rows[row].items[col]
		if item and item.enabled then return { row = row, col = col }, item.id end
	end
	return { row = row, col = col }, nil
end

-- The request an item sends: { kind = Lobby kind, payload = {...}, lesson = guided lesson after practice starts }.
function M.playRequest(id: string, difficulty: string?): { kind: string, payload: { [string]: any }, lesson: boolean }?
	local level = if difficulty == "Easy" or difficulty == "Hard" then difficulty else "Normal"
	if id == "quick" then return { kind = "QuickPlay", payload = { mode = "Duel" }, lesson = false } end
	if id == "cancel" then return { kind = "CancelQueue", payload = {}, lesson = false } end
	if id == "cpuInstead" then return { kind = "QuickPlay", payload = { mode = "Cpu", difficulty = "Normal" }, lesson = false } end
	local cpuLevel = string.match(id, "^cpu:(%a+)$")
	if cpuLevel then return { kind = "QuickPlay", payload = { mode = "Cpu", difficulty = cpuLevel }, lesson = false } end
	if id == "practice:Training" then return { kind = "QuickPlay", payload = { mode = "Practice", practice = "Training" }, lesson = false } end
	if id == "practice:Lesson" then return { kind = "QuickPlay", payload = { mode = "Practice", practice = "Training" }, lesson = true } end
	if id == "practice:Cpu" then return { kind = "QuickPlay", payload = { mode = "Practice", practice = "Cpu", difficulty = level }, lesson = false } end
	local to = string.match(id, "^travel:([%w_]+)$")
	if to then return { kind = "Travel", payload = { to = to }, lesson = false } end
	return nil
end

--------------------------------------------------------------------------------------------------------------------
-- Practice lesson (dojo tutorial). Pure: steps observe snapshot entries (fighter state names and events published in
-- combat-states.md) and tick their goals; LobbyUI shows the card and sets the dummy behaviour each step asks for.
--------------------------------------------------------------------------------------------------------------------
export type Goal = { id: string, text: string, need: number, have: number }
export type TutorialStep = { id: string, title: string, text: string, dummy: string, reset: boolean?, goals: { Goal } }
export type Tutorial = {
	slot: number, fighter: string, index: number, steps: { TutorialStep }, done: boolean, completedAt: number?,
	stepDoneAt: number?, lastState: string, launchers: { [string]: boolean }, strings: { [string]: boolean },
	stringNotation: string, launcherNotation: string, frames: number, crouchFrames: number,
}

M.TUTORIAL_ADVANCE = 0.9 -- seconds a finished step stays ticked before the next one
local WALK_FRAMES = 18
local CROUCH_FRAMES = 40

-- Key placeholders in step texts: {fight.forward} -> the Controls label, {input:df+RP} -> the keys of a move input
-- ("S+D+I" on keyboard). Device-aware.
function M.fillKeys(text: string, device: string?): string
	local withMoves = string.gsub(text, "{input:([^}]*)}", function(input: string)
		return UIHelpers.formatMoveInput(input, device)
	end)
	return (string.gsub(withMoves, "{(%a+)%.(%a+)}", function(group: string, action: string)
		local l = UIHelpers.keyLabel(group, action, device)
		return if l ~= "" then l else action
	end))
end

local function notationOf(move: any): string
	return UIHelpers.notationOf(if typeof(move.input) == "string" then move.input else "")
end

-- "1,3" -> "{fight.lp} then {fight.lk}" (the buttons of a plain string, for the lesson text).
local BUTTON_ACTION: { [string]: string } = { ["1"] = "lp", ["2"] = "rp", ["3"] = "lk", ["4"] = "rk" }
local function stringKeysText(notation: string): string
	local parts = {}
	for _, tok in UIHelpers.notationTokens(notation) do
		if tok.kind == "btn" and BUTTON_ACTION[tok.value] then table.insert(parts, "{fight." .. BUTTON_ACTION[tok.value] .. "}") end
	end
	return table.concat(parts, " then ")
end

-- Picks the lesson's example string ("1,2" when the fighter has it, else its first plain button string) and
-- launcher for `def`. Returns strings, stringNotation, launchers, launcherNotation, launcherInput.
local function lessonMoves(def: any): ({ [string]: boolean }, string, { [string]: boolean }, string, string)
	local strings, launchers = {}, {}
	local stringNotation, launcherNotation, launcherInput = "", "", ""
	local fallbackString: string?, anyString: string? = nil, nil
	local launcherStandalone = false
	for _, key in def.moveOrder or {} do
		local mv = def.moves[key]
		if mv then
			local n = notationOf(mv)
			if n == "1,2" then strings[key] = true; stringNotation = n end
			if typeof(mv.chainFrom) == "string" then
				if anyString == nil then anyString = key end
				-- Plain button strings ("1,3", "4,4") read best in a lesson; "d+3,4" style strings are a last resort.
				if fallbackString == nil and string.match(n, "^[%d,]+$") then fallbackString = key end
			end
			if mv.onHit == "LAUNCH" or mv.tier == "Launch" then
				launchers[key] = true
				-- The lesson names a launcher that works on its own (not the end of a string) when there is one.
				local standalone = typeof(mv.chainFrom) ~= "string"
				if launcherNotation == "" or (standalone and not launcherStandalone) then
					launcherNotation = n
					launcherInput = if typeof(mv.input) == "string" then mv.input else n
					launcherStandalone = standalone
				end
			end
		end
	end
	local pick = fallbackString or anyString
	if next(strings) == nil and pick then
		strings[pick] = true
		stringNotation = notationOf(def.moves[pick])
	end
	return strings, (if stringNotation ~= "" then stringNotation else "1,2"), launchers, launcherNotation, launcherInput
end

function M.tutorialNew(slot: number, fighterId: string, roster: any): Tutorial
	local def = UIHelpers.fighterDef(roster, fighterId)
	local strings, stringNotation, launchers, launcherNotation, launcherInput = {}, "1,2", {}, "", ""
	if def then strings, stringNotation, launchers, launcherNotation, launcherInput = lessonMoves(def) end
	local stringKeys = stringKeysText(stringNotation)
	if stringKeys == "" then stringKeys = "{fight.lp} then {fight.rp}" end
	local function goal(id: string, text: string, need: number): Goal return { id = id, text = text, need = need, have = 0 } end
	local steps: { TutorialStep } = {
		{ id = "walk", title = "WALK", dummy = "Stand", text = "Hold {fight.forward} to walk in, hold {fight.back} to walk away.",
			goals = { goal("forward", "Walk forward", WALK_FRAMES), goal("back", "Walk back", WALK_FRAMES) } },
		{ id = "dash", title = "DASH", dummy = "Stand", text = "Double-tap {fight.forward} to dash in fast.",
			goals = { goal("dash", "Dash in", 1) } },
		{ id = "backdash", title = "BACKDASH", dummy = "Stand", text = "Double-tap {fight.back} to backdash out of range.",
			goals = { goal("backdash", "Backdash", 1) } },
		{ id = "sidestep", title = "SIDESTEP", dummy = "Stand", text = "Tap {fight.sidestepIn} to step into the screen, tap {fight.sidestepOut} to step toward the camera. One step per tap.",
			goals = { goal("in", "Step in", 1), goal("out", "Step out", 1) } },
		{ id = "standGuard", title = "STANDING GUARD", dummy = "Fight", text = "Stand still or hold {fight.back}: you block high and mid attacks. Block two hits.",
			goals = { goal("block", "Standing blocks", 2) } },
		{ id = "crouchGuard", title = "CROUCH GUARD", dummy = "Fight", text = "Hold {fight.crouch} to crouch: highs whiff over you and lows are blocked.",
			goals = { goal("crouch", "Crouch guard", 1) } },
		{ id = "string", title = "STRING", dummy = "Stand", text = if next(strings) ~= nil then "Press " .. stringKeys .. " in rhythm for the " .. stringNotation .. " string: the second hit flows out of the first." else "Press {fight.lp} then {fight.rp} quickly so both hits land: a two-hit combo.",
			goals = { goal("string", if next(strings) ~= nil then "Land the " .. stringNotation .. " string" else "Two hits in a row", 1) } },
		{ id = "launcher", title = "LAUNCHER", dummy = "Stand", text = if launcherNotation ~= "" then "Launch with {input:" .. launcherInput .. "}: hold the direction and press the button together. Launchers are unsafe if blocked." else "Find your launcher in the Move List and use it.",
			goals = { goal("launch", "Launcher", 1) } },
		{ id = "throw", title = "THROW", dummy = "Guard", text = "Get close and press {fight.throw}: throws beat a guarding opponent.",
			goals = { goal("throw", "Throw", 1) } },
		-- reset: the fighting dummy restarts from neutral spacing, where it walks in and grabs (after the throw step it
		-- can otherwise sit back in a crouch and never try one).
		{ id = "throwBreak", title = "BREAK A THROW", dummy = "Fight", reset = true, text = "The dummy comes in for a grab: the moment it grabs you, press {fight.lp} or {fight.rp} to break free.",
			goals = { goal("break", "Throw escape", 1) } },
	}
	return {
		slot = if slot == 2 then 2 else 1, fighter = fighterId, index = 1, steps = steps, done = false, completedAt = nil, stepDoneAt = nil,
		lastState = "", launchers = launchers, strings = strings, stringNotation = stringNotation, launcherNotation = launcherNotation, frames = 0, crouchFrames = 0,
	}
end

function M.tutorialStep(t: Tutorial): TutorialStep? return t.steps[t.index] end
function M.stepComplete(step: TutorialStep): boolean
	for _, g in step.goals do if g.have < g.need then return false end end
	return true
end

local function bump(step: TutorialStep, id: string, amount: number?)
	for _, g in step.goals do
		if g.id == id and g.have < g.need then g.have = math.min(g.need, g.have + (amount or 1)) end
	end
end

local WALK_STATES = { Walk = "forward", WalkForward = "forward", Backwalk = "back", WalkBack = "back", BackWalk = "back" }

-- Feeds one snapshot entry; returns true when progress changed. `now` (os.clock) times the auto-advance.
function M.tutorialObserve(t: Tutorial, entry: any, now: number): boolean
	if t.done or typeof(entry) ~= "table" then return false end
	local changed = false
	-- A finished step waits TUTORIAL_ADVANCE seconds (the tick is visible) before the next one starts.
	if t.stepDoneAt then
		if now - t.stepDoneAt >= M.TUTORIAL_ADVANCE then
			t.stepDoneAt = nil
			if t.index >= #t.steps then
				t.done = true
				t.completedAt = now
			else
				t.index += 1
			end
			return true
		end
		return false
	end
	local step = t.steps[t.index]
	if not step then return false end
	local fighters = entry.fighters
	local me = typeof(fighters) == "table" and fighters[t.slot] or nil
	local state = if typeof(me) == "table" and typeof(me.state) == "string" then me.state else ""
	local entered = state ~= t.lastState
	t.lastState = state
	t.frames += 1
	local before = 0
	for _, g in step.goals do before += g.have end
	if step.id == "walk" then
		local dir = WALK_STATES[state]
		if dir then bump(step, dir) end
	elseif step.id == "dash" then
		local dash = state == "Dash" and (typeof(me.dashDirection) ~= "number" or me.dashDirection >= 0)
		if dash and entered then bump(step, "dash") end
	elseif step.id == "backdash" then
		local back = state == "Backdash" or (state == "Dash" and typeof(me.dashDirection) == "number" and me.dashDirection < 0)
		if back and entered then bump(step, "backdash") end
	elseif step.id == "sidestep" then
		if (state == "Sidestep" or state == "Step") and entered then
			local dir = if typeof(me.stepDir) == "number" then me.stepDir else 0
			if dir > 0 then bump(step, "in")
			elseif dir < 0 then bump(step, "out")
			else
				-- No direction published: count steps in order (in first, then out).
				if step.goals[1].have < 1 then bump(step, "in") else bump(step, "out") end
			end
		end
	elseif step.id == "crouchGuard" then
		local crouching = me and (me.guard == "Crouch" or state == "Crouch" or me.crouched == true)
		if crouching then
			t.crouchFrames += 1
			if t.crouchFrames >= CROUCH_FRAMES then bump(step, "crouch") end
		end
	elseif step.id == "string" then
		if me and typeof(me.move) == "string" and t.strings[me.move] then bump(step, "string") end
	elseif step.id == "launcher" then
		if me and typeof(me.move) == "string" and t.launchers[me.move] and (state == "Active" or state == "Recovery") then bump(step, "launch") end
	end
	for _, e in (if typeof(entry.events) == "table" then entry.events else {}) do
		if typeof(e) == "table" then
			local kind = e.kind
			if step.id == "standGuard" and kind == "Block" and e.target == t.slot and e.height ~= "Low" then
				bump(step, "block")
			elseif step.id == "crouchGuard" and kind == "Block" and e.target == t.slot and e.height == "Low" then
				bump(step, "crouch")
			elseif step.id == "launcher" and kind == "Hit" and e.attacker == t.slot and e.launch == true then
				bump(step, "launch")
			elseif step.id == "string" and (kind == "Hit" or kind == "Block") and e.attacker == t.slot and typeof(e.move) == "string" and t.strings[e.move] then
				bump(step, "string")
			elseif step.id == "string" and next(t.strings) == nil and kind == "Hit" and e.attacker == t.slot and typeof(e.combo) == "number" and e.combo >= 2 then
				-- Fighters without a string learn to link two hits instead.
				bump(step, "string")
			elseif step.id == "throw" and (kind == "ThrowHit" or kind == "ThrowStart") and e.attacker == t.slot then
				bump(step, "throw")
			elseif step.id == "throwBreak" and kind == "ThrowBreak" and e.attacker ~= t.slot then
				bump(step, "break")
			end
		end
	end
	local after = 0
	for _, g in step.goals do after += g.have end
	changed = after ~= before
	if M.stepComplete(step) then
		t.stepDoneAt = now
		changed = true
	end
	return changed
end

-- Skips the current step (mouse "Skip" on the lesson card).
function M.tutorialSkip(t: Tutorial, now: number)
	local step = t.steps[t.index]
	if not step or t.done then return end
	for _, g in step.goals do g.have = g.need end
	t.stepDoneAt = now - M.TUTORIAL_ADVANCE
end

function M.tutorialProgress(t: Tutorial): (number, number)
	local done = 0
	for i, s in t.steps do if i < t.index or (i == t.index and (t.stepDoneAt ~= nil or t.done)) then done += 1 end end
	return done, #t.steps
end

return M
