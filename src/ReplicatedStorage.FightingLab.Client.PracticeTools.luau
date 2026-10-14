--!strict
-- Practice tools (round 7): make combos learnable in the dojo.
--   * Input display: the last 10 inputs as notation icons, each with the frames since the one before it (HudController
--     records what InputController sends, keyboard, gamepad and touch alike).
--   * Frame advantage on hit / block (+3 / -12) from the sim's own event numbers, always from the player's side.
--   * Combo trials (Contract C, ReplicatedStorage.FightingLab.ComboTrial): pick one of your fighter's listed combos,
--     the steps light up as they land, a failure names the reason in plain words and resets, a success celebrates;
--     SHOW ME plays ComboTrial.demo through the practice runner with your fighter.
-- Mounted by LobbyUI (practice is its mode); everything degrades to nothing when ComboTrial is missing. Keys: the trial
-- list is browsed like every overlay (arrows / WASD / D-pad, Enter / A, Backspace / B); pausing during a trial opens it.
local Client = script.Parent
local Lab = Client.Parent
local UIHelpers = require(Client.UIHelpers)
local Roster = require(Lab:WaitForChild("Roster"))

local T = UIHelpers.Theme
local make, text = UIHelpers.make, UIHelpers.text
local WHITE = Color3.new(1, 1, 1)

local PracticeTools = {}
PracticeTools.INPUT_ROWS = 10
PracticeTools.FPS = 60
PracticeTools.FRAME_SECONDS = 3 -- the frame readout stays this long
PracticeTools.FAIL_SECONDS = 1.3 -- a failure reads this long, then the trial resets
PracticeTools.CLEAR_SECONDS = 2.4 -- a success celebrates this long, then the trial is ready again
PracticeTools.DEMO_TAIL = 100 -- runner steps a demo keeps watching after its last input
PracticeTools.LONG_GAP = 90 -- frames: a longer pause starts a new sequence ("—")

-- InputController's notes (HudController.recordInput) -> notation for the icon row.
local NOTE_INPUT: { [string]: { string } } = {
	f = { "f" }, b = { "b" }, d = { "d" }, ["SS in"] = { "u", "STEP" }, ["SS out"] = { "d", "STEP" },
}
PracticeTools.REASONS = {
	Early = { "TOO EARLY", "Let the dummy fall a little before the next hit." },
	Late = { "TOO LATE", "Press the next button sooner." },
	Wrong = { "WRONG MOVE", "That was a different move: check the step." },
	Blocked = { "BLOCKED", "The dummy blocked it: set the dummy to STAND." },
	Whiffed = { "MISSED", "Out of reach: start a little closer." },
	Dropped = { "TOO SLOW", "The combo ended before the next hit." },
} :: { [string]: { string } }

export type InputRow = { text: string, input: string, tag: string?, gap: number?, t: number }

-- Newest first, at most INPUT_ROWS; gap = frames since the previous (older) input, nil for the oldest or after a long
-- pause.
function PracticeTools.inputRows(log: { { text: string, t: number } }): { InputRow }
	local rows: { InputRow } = {}
	for i = 1, math.min(#log, PracticeTools.INPUT_ROWS) do
		local e = log[i]
		local older = log[i + 1]
		local map = NOTE_INPUT[e.text]
		local gap: number? = nil
		if older then
			local frames = math.floor((e.t - older.t) * PracticeTools.FPS + 0.5)
			if frames <= PracticeTools.LONG_GAP then gap = math.max(0, frames) end
		end
		table.insert(rows, { text = e.text, input = if map then map[1] else e.text, tag = if map then map[2] else nil, gap = gap, t = e.t })
	end
	return rows
end

export type Readout = { value: number?, word: string?, caption: string, move: string, plus: boolean }

-- The frame readout for one snapshot event, from the player's side (`slot`); nil for events it does not describe.
-- Hit / Block / Counter carry the sim's advantage (the attacker's frames free before the defender); launchers and
-- knockdowns read as words; the opponent's moves you blocked or took read as your advantage (its sign flipped).
function PracticeTools.readout(e: any, slot: number, entry: any?): Readout?
	if typeof(e) ~= "table" or (e.kind ~= "Hit" and e.kind ~= "Block") then return nil end
	local mine = e.attacker == slot
	if not mine and e.target ~= slot then return nil end
	local fighters = if typeof(entry) == "table" then entry.fighters else nil
	local attacker = if typeof(fighters) == "table" then fighters[e.attacker] else nil
	local moveName = ""
	if typeof(e.move) == "string" and typeof(attacker) == "table" and typeof(attacker.characterId) == "string" and Roster.has(attacker.characterId) then
		local def = Roster.get(attacker.characterId).moves[e.move]
		moveName = if def then def.name else e.move
	end
	local blocked = e.kind == "Block"
	if not blocked and e.air then return nil end -- juggle hits: no advantage to read
	local caption = (if mine then "" else "THEIRS ") .. (if blocked then "ON BLOCK" elseif e.counter then "ON COUNTER HIT" else "ON HIT")
	if not blocked and e.launch then return { value = nil, word = "LAUNCH", caption = caption, move = moveName, plus = mine } end
	if not blocked and e.knockdown then return { value = nil, word = "DOWN", caption = caption, move = moveName, plus = mine } end
	local adv = if typeof(e.advantage) == "number" then e.advantage else 0
	local value = if mine then adv else -adv
	return { value = value, word = nil, caption = caption, move = moveName, plus = value >= 0 }
end

function PracticeTools.formatValue(r: Readout): string
	if r.word then return r.word end
	local v = r.value or 0
	return if v > 0 then "+" .. v elseif v < 0 then "−" .. math.abs(v) else "±0"
end

-- The trial module (Contract C); nil when combat's module is missing.
local cachedTrial: any = nil
function PracticeTools.comboTrialModule(): any
	if cachedTrial ~= nil then return cachedTrial or nil end
	local module = Lab:FindFirstChild("ComboTrial")
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and typeof(result) == "table" and typeof(result.list) == "function" and typeof(result.new) == "function" then
			cachedTrial = result
			return result
		end
	end
	cachedTrial = false
	return nil
end

--------------------------------------------------------------------------------------------------------------------
-- View
--------------------------------------------------------------------------------------------------------------------
export type Env = {
	parent: Instance,
	live: boolean?,
	touchOnly: boolean?,
	device: () -> string,
	clock: (() -> number)?,
	sound: ((name: string) -> ())?,
	practice: () -> boolean, -- in the dojo (practice session)
	versus: () -> boolean, -- practice vs CPU (trials run in Training)
	fighter: () -> string,
	command: (kind: string, arg: any?) -> (), -- practice commands: Reset, Dummy, Pause, SwitchMode
	send: (kind: string, a: any?, b: any?) -> (), -- fight input for SHOW ME (slot 1)
	inputLog: () -> { { text: string, t: number } }?,
	comboTrial: any?, -- tests: a ComboTrial-shaped module
	onChanged: (() -> ())?, -- input blocked / modal changed: the lobby re-applies (gameplay input, its panel)
	onTrialStart: (() -> ())?, -- a trial began: the guided lesson steps aside
}

function PracticeTools.mount(env: Env): any
	local live = env.live == true
	local clock = env.clock or os.clock
	local destroyed = false
	local conns: { RBXScriptConnection } = {}
	local tools: any
	local S = {
		inputs = false, frames = false, suppressed = false,
		modal = false, focus = 1, action = "Try", list = {} :: { any }, listFighter = "",
		trial = nil :: any, index = 0, status = nil :: any, cleared = {} :: { [string]: boolean },
		bannerUntil = 0, banner = nil :: string?, resetAt = 0, lastEpoch = nil :: number?, paused = false,
		demo = nil :: { entries: { any }, cursor: number, step: number, last: number, held: { x: number, z: number, crouch: boolean } }?,
		readout = nil :: Readout?, readoutUntil = 0, lastInputT = -1, inputsAuto = false, demoResult = nil :: string?,
	}
	local function sound(name: string) if env.sound then pcall(env.sound, name) end end
	local function changed() if env.onChanged then pcall(env.onChanged) end end
	local function trialModule(): any
		if env.comboTrial == false then return nil end -- tests: a build without Contract C
		return env.comboTrial or PracticeTools.comboTrialModule()
	end

	local gui: ScreenGui = make("ScreenGui", { Name = "FightingLabPractice", ResetOnSpawn = false, DisplayOrder = 12, Enabled = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets, Parent = env.parent })
	local stage: Frame = make("Frame", { Name = "Stage", BackgroundTransparency = 1, Parent = gui })
	local unfit = UIHelpers.fitToScreen(gui, stage, env.touchOnly)

	-- Input display (left edge, under the combo counter) ------------------------------------------------------------
	local inputsPanel = make("Frame", { Name = "Inputs", BackgroundColor3 = T.bg, BackgroundTransparency = 0.35, BorderSizePixel = 0, Position = UDim2.fromOffset(16, 342), Size = UDim2.fromOffset(170, 0), AutomaticSize = Enum.AutomaticSize.Y, Visible = false, Parent = stage })
	UIHelpers.corner(inputsPanel, 5)
	UIHelpers.padding(inputsPanel, 8, 6)
	UIHelpers.list(inputsPanel, false, 3)
	local inputsHead = text(inputsPanel, "Head", "INPUTS", T.heavy, 12, T.muted, { Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 0 })
	text(inputsHead, "Unit", "FRAMES", T.heavy, 10, T.dim, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Right })
	local inputRowsFrame = make("Frame", { Name = "Rows", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Parent = inputsPanel })
	UIHelpers.list(inputRowsFrame, false, 2)

	local function renderInputs(force: boolean?)
		local show = S.inputs and env.practice() and not S.suppressed
		inputsPanel.Visible = show
		if not show then return end
		local log = env.inputLog() or {}
		local newest = if log[1] then log[1].t else -1
		if not force and newest == S.lastInputT then return end
		S.lastInputT = newest
		for _, c in inputRowsFrame:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
		for i, row in PracticeTools.inputRows(log) do
			local r = make("Frame", { Name = "Row" .. i, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = i, Parent = inputRowsFrame })
			local fade = math.clamp((i - 1) / PracticeTools.INPUT_ROWS, 0, 0.7)
			local tiles = UIHelpers.notationRow(r, row.input, { height = 22, name = "Notation" })
			tiles.Position = UDim2.fromOffset(0, 1)
			if row.tag then text(tiles, "Tag", row.tag, T.heavy, 10, T.muted, { Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 99 }) end
			for _, d in tiles:GetDescendants() do
				if d:IsA("TextLabel") then d.TextTransparency = fade end
				if d:IsA("Frame") then d.BackgroundTransparency = math.max(d.BackgroundTransparency, fade) end
			end
			local gapText = if row.gap == nil then "—" else "+" .. row.gap
			local chord = row.gap ~= nil and row.gap <= 2 and string.match(row.input, "^%d") ~= nil
			text(r, "Gap", gapText, T.number, 13, if chord then T.ok else T.text, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(44, 24), TextXAlignment = Enum.TextXAlignment.Right, TextTransparency = fade })
		end
	end

	-- Frame readout (top centre, under the round clock) --------------------------------------------------------------
	local readoutFrame = make("Frame", { Name = "Frames", BackgroundColor3 = T.bg, BackgroundTransparency = 0.25, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 104), Size = UDim2.fromOffset(250, 60), Visible = false, Parent = stage })
	UIHelpers.corner(readoutFrame, 5)
	local readoutValue = text(readoutFrame, "Value", "", T.display, 38, T.ok, { Position = UDim2.fromOffset(12, 6), Size = UDim2.fromOffset(110, 48), TextXAlignment = Enum.TextXAlignment.Center })
	local readoutCaption = text(readoutFrame, "Caption", "", T.heavy, 13, T.text, { Position = UDim2.fromOffset(128, 10), Size = UDim2.fromOffset(116, 18), TextTruncate = Enum.TextTruncate.AtEnd })
	local readoutMove = text(readoutFrame, "Move", "", T.medium, 13, T.muted, { Position = UDim2.fromOffset(128, 30), Size = UDim2.fromOffset(116, 18), TextTruncate = Enum.TextTruncate.AtEnd })
	local function renderReadout()
		local r = S.readout
		local show = S.frames and env.practice() and not S.suppressed and r ~= nil and clock() < S.readoutUntil
		readoutFrame.Visible = show
		if not show or not r then return end
		readoutValue.Text = PracticeTools.formatValue(r)
		local v = r.value
		readoutValue.TextColor3 = if r.word then T.gold elseif (v or 0) >= 0 then T.ok elseif (v or 0) > -10 then T.gold else T.loss
		readoutValue.TextScaled = r.word ~= nil
		readoutCaption.Text = r.caption .. (if v and v <= -10 then "  ·  PUNISHABLE" else "")
		readoutMove.Text = r.move
	end

	-- Trial card (right side, under the practice strip) ----------------------------------------------------------------
	local card: Frame, cardContent: Frame, cardEdge: Frame = UIHelpers.edgeCard(stage, "Trial", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 148), Size = UDim2.fromOffset(340, 0), Visible = false, BackgroundTransparency = 0.08 }, T.gold, 4, 14, 12)
	UIHelpers.list(cardContent, false, 6)
	local C: { [string]: any } = { steps = {} }
	C.top = make("Frame", { Name = "Top", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 1, Parent = cardContent })
	C.caption = text(C.top, "Caption", "COMBO TRIAL", T.heavy, 12, T.gold, { Size = UDim2.fromScale(0.6, 1) })
	C.count = text(C.top, "Count", "", T.number, 12, T.muted, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromScale(0.4, 1), TextXAlignment = Enum.TextXAlignment.Right })
	C.name = text(cardContent, "Name", "", T.display, 26, T.text, { Size = UDim2.new(1, 0, 0, 32), LayoutOrder = 2, TextTruncate = Enum.TextTruncate.AtEnd })
	C.meta = text(cardContent, "Meta", "", T.medium, 13, T.muted, { Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 3, RichText = true })
	C.stepsFrame = make("Frame", { Name = "Steps", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 4, Parent = cardContent })
	UIHelpers.list(C.stepsFrame, false, 4)
	C.status = text(cardContent, "Status", "", T.heavy, 15, T.text, { Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 5, TextWrapped = true })
	C.buttons = make("Frame", { Name = "Buttons", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 6, Parent = cardContent })
	UIHelpers.list(C.buttons, true, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	C.showMe = UIHelpers.button(C.buttons, "ShowMe", { text = "SHOW ME", size = UDim2.fromOffset(104, 32), order = 1, textSize = 13, accent = T.gold })
	C.next = UIHelpers.button(C.buttons, "Next", { text = "NEXT ›", size = UDim2.fromOffset(82, 32), order = 2, textSize = 13, accent = T.cool })
	C.all = UIHelpers.button(C.buttons, "All", { text = "ALL", size = UDim2.fromOffset(56, 32), order = 3, textSize = 13, accent = T.cool })
	C.stop = UIHelpers.button(C.buttons, "End", { text = "END", size = UDim2.fromOffset(60, 32), order = 4, textSize = 13, accent = T.muted })
	for _, b in { C.showMe, C.next, C.all, C.stop } do b.button.Selectable = false end
	C.hint = text(cardContent, "Hint", "", T.medium, 12, T.dim, { Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 7, RichText = true })
	C.scale = make("UIScale", { Parent = card })

	-- Centre banner: COMBO CLEAR! / the failure reason.
	local banner = make("Frame", { Name = "Banner", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.33), Size = UDim2.fromOffset(760, 120), Visible = false, Parent = stage })
	local bannerTitle = text(banner, "Title", "", T.display, 72, T.gold, { Size = UDim2.new(1, 0, 0, 84), TextXAlignment = Enum.TextXAlignment.Center })
	UIHelpers.textStroke(bannerTitle, 0.25, 3)
	local bannerSub = text(banner, "Sub", "", T.bold, 22, T.text, { Position = UDim2.fromOffset(0, 84), Size = UDim2.new(1, 0, 0, 28), TextXAlignment = Enum.TextXAlignment.Center })
	UIHelpers.textStroke(bannerSub, 0.4, 2)
	local bannerScale = make("UIScale", { Parent = banner })

	-- Trial list (modal) ---------------------------------------------------------------------------------------------
	local modal: Frame, modalContent: Frame = UIHelpers.edgeCard(stage, "Trials", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromOffset(700, 0), Visible = false, BackgroundTransparency = 0.03 }, T.gold, 4, 22, 16)
	UIHelpers.list(modalContent, false, 8)
	local M: { [string]: any } = { rows = {} }
	M.title = text(modalContent, "Title", "COMBO TRIALS", T.display, 34, T.text, { Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 1 })
	M.sub = text(modalContent, "Sub", "Pick a combo. TRY IT, or let SHOW ME play it first.", T.medium, 16, T.muted, { Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 2 })
	M.rowsFrame = make("Frame", { Name = "Rows", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3, Parent = modalContent })
	UIHelpers.list(M.rowsFrame, false, 8)
	M.footer = make("Frame", { Name = "Footer", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 4, Parent = modalContent })
	UIHelpers.list(M.footer, true, 14, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	M.close = UIHelpers.button(M.footer, "Close", { text = "BACK TO TRAINING", size = UDim2.fromOffset(190, 30), order = 1, textSize = 13 })
	M.close.button.Selectable = false
	M.hints = make("Frame", { Name = "Hints", BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2, Parent = M.footer })
	UIHelpers.list(M.hints, true, 14, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	M.empty = text(modalContent, "Empty", "", T.medium, 16, T.muted, { Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 5, Visible = false })

	-- Difficulty 1-5 as gold / dim stars (rich text).
	local function stars(n: number): string
		local filled = math.clamp(math.floor(n + 0.5), 0, 5)
		return string.format('<font color="#%s">%s</font><font color="#%s">%s</font>', T.gold:ToHex(), string.rep("★", filled), T.slot:ToHex(), string.rep("★", 5 - filled))
	end
	local function comboList(): { any }
		local mod = trialModule()
		local id = env.fighter()
		if not mod then return {} end
		if S.listFighter ~= id then
			S.listFighter = id
			local ok, list = pcall(mod.list, id)
			S.list = if ok and typeof(list) == "table" then list else {}
		end
		return S.list
	end

	local function paintModalHints()
		for _, c in M.hints:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
		local d = env.device()
		if d == "touch" then return end
		local gp = d == "gamepad"
		local gd = if gp then "gamepad" else "keyboard"
		UIHelpers.hint(M.hints, { "↑", "↓" }, "Combo", { height = 22, device = gd, order = 1, color = T.muted, textSize = 13 })
		UIHelpers.hint(M.hints, { "←", "→" }, "Try / Show me", { height = 22, device = gd, order = 2, color = T.muted, textSize = 13 })
		UIHelpers.hint(M.hints, { if gp then "A" else "ENTER" }, "Go", { height = 22, device = gd, order = 3, color = T.muted, textSize = 13 })
		UIHelpers.hint(M.hints, { if gp then "B" else "BACKSPACE" }, "Back", { height = 22, device = gd, order = 4, color = T.muted, textSize = 13 })
	end

	local function buildModalRows()
		for _, c in M.rowsFrame:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
		table.clear(M.rows)
		local list = comboList()
		M.empty.Visible = #list == 0
		M.empty.Text = if trialModule() then "This fighter has no listed combos yet." else "Combo trials are not installed in this build."
		local def = UIHelpers.fighterDef(Roster, env.fighter())
		M.title.Text = "COMBO TRIALS" .. (if def then "  ·  " .. def.displayName else "")
		for i, info in list do
			-- Three lines left of the buttons: name; difficulty, damage, tags and CLEARED; the notation.
			local row: TextButton = make("TextButton", { Name = "Combo" .. i, Text = "", AutoButtonColor = false, Selectable = false, BackgroundColor3 = T.panel2, BackgroundTransparency = 0.1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 86), LayoutOrder = i, Parent = M.rowsFrame })
			UIHelpers.corner(row, 4)
			local stroke = UIHelpers.outline(row, WHITE, 1, 0.85)
			text(row, "Index", string.format("%02d", i), T.number, 16, T.gold, { Position = UDim2.fromOffset(14, 8), Size = UDim2.fromOffset(30, 20) })
			text(row, "Name", info.name, T.title, 21, T.text, { Position = UDim2.fromOffset(50, 6), Size = UDim2.new(1, -270, 0, 26), TextTruncate = Enum.TextTruncate.AtEnd })
			local metaRow = make("Frame", { Name = "MetaRow", BackgroundTransparency = 1, Position = UDim2.fromOffset(50, 33), Size = UDim2.new(1, -270, 0, 16), Parent = row })
			UIHelpers.list(metaRow, true, 12, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
			text(metaRow, "Meta", stars(info.difficulty) .. "   " .. tostring(info.damage) .. " DMG", T.heavy, 12, T.muted, { Size = UDim2.fromOffset(0, 16), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 1, RichText = true })
			if info.counter then text(metaRow, "Counter", "COUNTER HIT", T.heavy, 12, T.gold, { Size = UDim2.fromOffset(0, 16), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2 }) end
			if info.surge then text(metaRow, "Surge", "SURGE", T.heavy, 12, T.ember, { Size = UDim2.fromOffset(0, 16), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 3 }) end
			local cleared = text(metaRow, "Cleared", "CLEARED", T.heavy, 12, T.ok, { Size = UDim2.fromOffset(0, 16), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 4, Visible = false })
			local notation = UIHelpers.notationRow(row, info.notation, { height = 24, name = "Notation" })
			notation.Position = UDim2.fromOffset(50, 54)
			local try = UIHelpers.button(row, "Try", { text = "TRY IT", size = UDim2.fromOffset(96, 30), textSize = 13, accent = T.gold, primary = true })
			try.button.AnchorPoint = Vector2.new(1, 0.5); try.button.Position = UDim2.new(1, -116, 0.5, 0); try.button.Selectable = false
			local show = UIHelpers.button(row, "Show", { text = "SHOW ME", size = UDim2.fromOffset(96, 30), textSize = 13, accent = T.cool })
			show.button.AnchorPoint = Vector2.new(1, 0.5); show.button.Position = UDim2.new(1, -12, 0.5, 0); show.button.Selectable = false
			table.insert(conns, try.button.Activated:Connect(function() tools.startTrial(i) end))
			table.insert(conns, show.button.Activated:Connect(function() tools.startTrial(i); tools.showMe() end))
			table.insert(conns, row.Activated:Connect(function() S.focus = i; tools.refresh() end))
			M.rows[i] = { row = row, stroke = stroke, try = try, show = show, cleared = cleared, info = info }
		end
		paintModalHints()
	end

	local function paintModal()
		modal.Visible = S.modal and not S.suppressed
		if not S.modal then return end
		local focusOn = env.device() ~= "touch"
		for i, r in M.rows do
			local f = focusOn and i == S.focus
			r.stroke.Color = if f then T.gold else WHITE
			r.stroke.Thickness = if f then 2 else 1
			r.stroke.Transparency = if f then 0 else 0.85
			r.try.setFocused(f and S.action == "Try")
			r.show.setFocused(f and S.action == "Show")
			r.show.setEnabled(trialModule() ~= nil and typeof(trialModule().demo) == "function")
			r.cleared.Visible = S.cleared[env.fighter() .. "#" .. i] == true
		end
	end

	local function buildSteps()
		for _, c in C.stepsFrame:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
		table.clear(C.steps)
		local info = S.trial and S.trial.info or (comboList()[S.index])
		if not info then return end
		for k, step in info.steps do
			local row = make("Frame", { Name = "Step" .. k, BackgroundColor3 = T.panel2, BackgroundTransparency = 0.25, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = k, Parent = C.stepsFrame })
			UIHelpers.corner(row, 4)
			local stroke = UIHelpers.outline(row, WHITE, 1, 0.88)
			local dot = make("Frame", { Name = "Dot", BackgroundColor3 = T.slot, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, 0), Size = UDim2.fromOffset(22, 22), Parent = row })
			UIHelpers.corner(dot)
			local num = text(dot, "Num", tostring(k), T.number, 12, T.muted, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
			local tiles = UIHelpers.notationRow(row, step.notation, { height = 24, name = "Notation" })
			tiles.Position = UDim2.fromOffset(38, 5)
			local label = text(row, "Label", step.label, T.bold, 14, T.text, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0), Size = UDim2.fromOffset(150, 34), TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd })
			C.steps[k] = { row = row, stroke = stroke, dot = dot, num = num, label = label }
		end
	end

	local function paintCard()
		local trial = S.trial
		local info = trial and trial.info
		card.Visible = trial ~= nil and info ~= nil and env.practice() and not S.suppressed and not S.modal
		if not card.Visible then return end
		local st = S.status or { state = "Ready", step = 0, total = #info.steps, damage = 0 }
		C.count.Text = string.format("%d / %d", S.index, #comboList())
		C.name.Text = info.name
		C.meta.Text = stars(info.difficulty) .. "   " .. tostring(info.damage) .. " DAMAGE" .. (if info.counter then '   <font color="#FFC845">COUNTER HIT</font>' else "")
		local demo = S.demo ~= nil
		for k, r in C.steps do
			local done = st.step >= k
			local nextStep = st.state == "Running" and k == st.step + 1 or (st.state == "Ready" and k == 1)
			r.row.BackgroundColor3 = if done then T.ok:Lerp(T.panel2, 0.55) else T.panel2
			r.stroke.Color = if done then T.ok elseif nextStep then T.gold else WHITE
			r.stroke.Transparency = if done or nextStep then 0 else 0.88
			r.stroke.Thickness = if nextStep then 2 else 1
			r.dot.BackgroundColor3 = if done then T.ok elseif nextStep then T.gold else T.slot
			r.num.Text = if done then "✓" else tostring(k)
			r.num.TextColor3 = if done or nextStep then T.ink else T.muted
		end
		local reason = st.reason and PracticeTools.REASONS[st.reason]
		if demo then
			C.status.Text = "WATCH: the combo plays itself"
			C.status.TextColor3 = T.cool
		elseif st.state == "Success" then
			C.status.Text = "COMBO CLEAR!  " .. tostring(st.damage) .. " DAMAGE"
			C.status.TextColor3 = T.gold
		elseif st.state == "Failed" and reason then
			C.status.Text = reason[1] .. "  ·  " .. reason[2]
			C.status.TextColor3 = T.loss
		elseif st.state == "Running" then
			C.status.Text = string.format("KEEP GOING  ·  %d / %d", st.step, st.total)
			C.status.TextColor3 = T.text
		else
			C.status.Text = if info.counter then "Land step 1 as a COUNTER HIT: hit the dummy while it attacks." elseif info.steps[1] and info.steps[1].stance then "Start with step 1: enter the stance." else "Land step 1 on the dummy to start."
			C.status.TextColor3 = T.muted
		end
		C.showMe.setEnabled(typeof(trialModule() and trialModule().demo) == "function" and not demo)
		C.next.setEnabled(#comboList() > 1 and not demo)
		local d = env.device()
		local resetKey = UIHelpers.keyLabel("practice", "reset", if d == "gamepad" then "gamepad" else "keyboard")
		local pauseKey = UIHelpers.keyLabel("practice", "pause", if d == "gamepad" then "gamepad" else "keyboard")
		local bits = {}
		if d ~= "touch" and resetKey ~= "" then table.insert(bits, "<b>" .. resetKey .. "</b> restart") end
		if d ~= "touch" and pauseKey ~= "" then table.insert(bits, "<b>" .. pauseKey .. "</b> trial list") end
		C.hint.Text = table.concat(bits, "   ·   ")
		C.hint.Visible = #bits > 0
	end

	local function showBanner(title: string, sub: string, color: Color3, seconds: number)
		S.banner = title
		S.bannerUntil = clock() + seconds
		bannerTitle.Text = title
		bannerTitle.TextColor3 = color
		bannerSub.Text = sub
		banner.Visible = not S.suppressed
		if live then
			bannerScale.Scale = 1.25
			UIHelpers.tween(bannerScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end

	local function render()
		if destroyed then return end
		gui.Enabled = env.practice() and not S.suppressed
		renderInputs(true)
		renderReadout()
		paintCard()
		paintModal()
		if S.banner and clock() >= S.bannerUntil then S.banner = nil end
		banner.Visible = S.banner ~= nil and env.practice() and not S.suppressed
	end

	-- Demo playback ("SHOW ME") ---------------------------------------------------------------------------------------
	local function applyDemo(frame: number)
		local demo = S.demo
		if not demo then return end
		while demo.cursor <= #demo.entries and demo.entries[demo.cursor].frame <= frame do
			local e = demo.entries[demo.cursor]
			if e.hold then
				local h = e.hold
				if h.moveX ~= demo.held.x or h.moveZ ~= demo.held.z then
					demo.held.x, demo.held.z = h.moveX, h.moveZ
					env.send("Move", h.moveX, h.moveZ)
				end
				if h.crouch ~= demo.held.crouch then
					demo.held.crouch = h.crouch
					env.send("Crouch", h.crouch)
				end
			end
			if e.press then env.send("Attack", e.press) end
			demo.cursor += 1
		end
	end
	local function stopDemo(resetAfter: boolean)
		local demo = S.demo
		if not demo then return end
		S.demo = nil
		env.send("Move", 0, 0)
		env.send("Crouch", false)
		if resetAfter then
			env.command("Reset", nil)
			if S.trial then S.trial:reset(); S.status = S.trial:status() end
			if S.demoResult == "Success" then
				local name = S.trial and S.trial.info and S.trial.info.name or "The combo"
				showBanner("YOUR TURN!", name .. ": now you try it", T.cool, 1.8)
			end
		end
		changed()
		render()
	end

	local function setDummyFor(info: any)
		env.command("Dummy", if info and info.counter then "Fight" else "Stand")
	end

	tools = {
		gui = gui,
		inputsOn = function() return S.inputs end,
		setInputs = function(on: boolean) S.inputs = on; S.inputsAuto = false; S.lastInputT = -1; render() end,
		framesOn = function() return S.frames end,
		setFrames = function(on: boolean) S.frames = on; render() end,
		available = function(): boolean return trialModule() ~= nil end,
		trialsOpen = function() return S.modal end,
		modalOpen = function() return S.modal end,
		-- Gameplay input is off while the list is open or a demo plays (LobbyUI.updateFreeze reads this).
		inputBlocked = function() return S.modal or S.demo ~= nil end,
		openTrials = function(): boolean
			if destroyed or not env.practice() then return false end
			if S.demo then stopDemo(true) end
			S.listFighter = ""
			buildModalRows()
			S.modal = true
			S.focus = math.clamp(if S.index > 0 then S.index else 1, 1, math.max(1, #comboList()))
			S.action = "Try"
			if S.paused then env.command("Pause", false) end
			if live then
				local sc = modal:FindFirstChildOfClass("UIScale") or make("UIScale", { Parent = modal })
				sc.Scale = 0.94
				UIHelpers.tween(sc, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
			end
			sound("MenuSelect")
			render()
			changed()
			return true
		end,
		closeTrials = function()
			if not S.modal then return end
			S.modal = false
			if S.paused then env.command("Pause", false) end
			sound("MenuBack")
			render()
			changed()
		end,
		startTrial = function(index: number): boolean
			local mod = trialModule()
			local list = comboList()
			if not mod or not list[index] or not env.practice() then return false end
			if S.demo then stopDemo(false) end
			if env.versus() then env.command("SwitchMode", nil) end
			local ok, trial = pcall(mod.new, env.fighter(), index)
			if not ok or not trial then return false end
			S.trial = trial
			S.index = index
			S.status = trial:status()
			S.modal = false
			if S.paused then env.command("Pause", false) end
			S.banner = nil
			S.resetAt = 0
			if not S.inputs then S.inputs = true; S.inputsAuto = true end
			setDummyFor(trial.info or list[index])
			env.command("Reset", nil)
			buildSteps()
			if env.onTrialStart then pcall(env.onTrialStart) end
			if live then
				C.scale.Scale = 0.9
				UIHelpers.tween(C.scale, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
			end
			sound("MenuSelect")
			render()
			changed()
			return true
		end,
		nextTrial = function(): boolean
			local n = #comboList()
			if n == 0 then return false end
			return tools.startTrial((S.index % n) + 1)
		end,
		endTrial = function()
			if S.demo then stopDemo(false) end
			if not S.trial and not S.modal then return end
			S.trial = nil
			S.status = nil
			S.index = 0
			S.modal = false
			S.banner = nil
			if S.inputsAuto then S.inputs = false; S.inputsAuto = false end
			render()
			changed()
		end,
		trial = function() return S.trial end,
		trialIndex = function() return S.index end,
		status = function() return S.status end,
		showMe = function(): boolean
			local mod = trialModule()
			if not mod or typeof(mod.demo) ~= "function" or not S.trial then return false end
			local ok, entries = pcall(mod.demo, env.fighter(), S.index)
			if not ok or typeof(entries) ~= "table" or #entries == 0 then return false end
			S.modal = false
			if S.paused then env.command("Pause", false) end
			env.command("Dummy", "Stand")
			env.command("Reset", nil)
			S.trial:reset()
			S.status = S.trial:status()
			S.banner = nil
			S.demo = { entries = entries, cursor = 1, step = 0, last = entries[#entries].frame, held = { x = 0, z = 0, crouch = false } }
			S.demoResult = nil
			changed() -- gameplay input off before the first scripted input
			applyDemo(0)
			sound("MenuSelect")
			render()
			return true
		end,
		demoPlaying = function() return S.demo ~= nil end,
		-- How the last SHOW ME ended: "Success" when the combo played out (nil while playing / never shown).
		demoResult = function() return S.demoResult end,
		cleared = function(index: number): boolean return S.cleared[env.fighter() .. "#" .. index] == true end,
		readout = function() return S.readout end,
		-- Keys while the trial list is open (navigation) -- returns true when consumed.
		handleNav = function(action: string): boolean
			if not S.modal then return false end
			local n = #comboList()
			if action == "Up" then
				S.focus = math.max(1, S.focus - 1); sound("MenuMove")
			elseif action == "Down" then
				S.focus = math.min(math.max(1, n), S.focus + 1); sound("MenuMove")
			elseif action == "Left" or action == "Right" then
				local can = trialModule() and typeof(trialModule().demo) == "function"
				S.action = if action == "Right" and can then "Show" else "Try"; sound("MenuMove")
			elseif action == "Confirm" then
				if n == 0 then tools.closeTrials(); return true end
				local i = S.focus
				if S.action == "Show" then tools.startTrial(i); tools.showMe() else tools.startTrial(i) end
				return true
			elseif action == "Back" then
				tools.closeTrials()
				return true
			end
			render()
			return true
		end,
		onSnapshot = function(entry: any)
			if destroyed or typeof(entry) ~= "table" or not env.practice() then return end
			-- Pause (the practice panel / P) during a trial opens the trial list.
			local paused = entry.paused == true
			if paused ~= S.paused then
				S.paused = paused
				if paused and S.trial and not S.modal and not S.demo then
					S.modal = true
					S.listFighter = ""
					buildModalRows()
					S.focus = math.max(1, S.index)
					S.action = "Try"
					render()
					changed()
				end
			end
			-- A practice reset (R, a mode / dummy change) restarts the attempt.
			if S.lastEpoch ~= nil and entry.epoch ~= S.lastEpoch and S.trial and not S.demo then
				S.trial:reset()
				S.status = S.trial:status()
				S.resetAt = 0
			end
			S.lastEpoch = entry.epoch
			-- Frame readout.
			if typeof(entry.events) == "table" then
				for _, e in entry.events do
					local r = PracticeTools.readout(e, 1, entry)
					if r then
						S.readout = r
						S.readoutUntil = clock() + PracticeTools.FRAME_SECONDS
					end
				end
			end
			-- Trial.
			local trial = S.trial
			if trial then
				local before = S.status
				local ok, st = pcall(trial.feed, trial, entry)
				if ok and typeof(st) == "table" then
					S.status = st
					local was = before and before.state or "Ready"
					local stepWas = before and before.step or 0
					if st.state == "Success" and was ~= "Success" then
						if S.demo then
							S.demoResult = "Success"
						else
							S.cleared[env.fighter() .. "#" .. S.index] = true
							showBanner("COMBO CLEAR!", tostring(st.damage) .. " DAMAGE  ·  " .. (trial.info and trial.info.name or ""), T.gold, PracticeTools.CLEAR_SECONDS)
							S.resetAt = clock() + PracticeTools.CLEAR_SECONDS
							sound("MenuSelect")
						end
					elseif st.state == "Failed" and was ~= "Failed" and not S.demo then
						local reason = PracticeTools.REASONS[st.reason or ""] or { "MISSED", "Try again." }
						showBanner(reason[1], reason[2], T.loss, PracticeTools.FAIL_SECONDS)
						S.resetAt = clock() + PracticeTools.FAIL_SECONDS
						sound("MenuBack")
					elseif st.step > stepWas and st.state == "Running" then
						sound("MenuMove")
					end
				end
			end
			-- Demo playback: entries for the next runner step.
			local demo = S.demo
			if demo then
				demo.step += 1
				applyDemo(demo.step)
				local st = S.status
				local finished = demo.step > demo.last + PracticeTools.DEMO_TAIL or (demo.step > demo.last and st and (st.state == "Success" or st.state == "Failed") and entry.fighters[1] and entry.fighters[1].state ~= "Ultimate")
				if finished then stopDemo(true) end
			end
			renderInputs(false)
			renderReadout()
			paintCard()
		end,
		sessionChanged = function(state: string)
			if state ~= "Practice" then
				if S.demo then S.demo = nil end
				S.trial = nil; S.status = nil; S.index = 0; S.modal = false; S.banner = nil; S.readout = nil
				S.lastEpoch = nil; S.paused = false
				if S.inputsAuto then S.inputs = false; S.inputsAuto = false end
				changed()
			end
			render()
		end,
		tick = function(_dt: number)
			if destroyed then return end
			gui.Enabled = env.practice() and not S.suppressed
			if S.resetAt > 0 and clock() >= S.resetAt then
				-- After the banner: back to the start for the next attempt.
				S.resetAt = 0
				if S.trial and not S.demo then
					env.command("Reset", nil)
					S.trial:reset()
					S.status = S.trial:status()
				end
			end
			if S.banner and clock() >= S.bannerUntil then S.banner = nil; banner.Visible = false end
			if readoutFrame.Visible and clock() >= S.readoutUntil then readoutFrame.Visible = false end
			renderInputs(false)
		end,
		refresh = function() render() end,
		setSuppressed = function(on: boolean) S.suppressed = on; render() end,
		destroy = function()
			if destroyed then return end
			destroyed = true
			for _, c in conns do c:Disconnect() end
			table.clear(conns)
			unfit()
			gui:Destroy()
		end,
	}
	table.insert(conns, C.showMe.button.Activated:Connect(function() tools.showMe() end))
	table.insert(conns, C.next.button.Activated:Connect(function() tools.nextTrial() end))
	table.insert(conns, C.all.button.Activated:Connect(function() tools.openTrials() end))
	table.insert(conns, C.stop.button.Activated:Connect(function() tools.endTrial() end))
	table.insert(conns, M.close.button.Activated:Connect(function() tools.closeTrials() end))
	return tools
end

return PracticeTools
