--!strict
-- Move list (OV6, round 6). Numeric notation (1/2/3/4 = left punch / right punch / left kick / right kick, arrows for
-- directions, stance tags such as PKT, all taken through UIHelpers.notationOf, which defers to Controls.notationOf)
-- and generated one-line descriptions, so whatever moveset the Roster holds is rendered readably.
-- Round 6: moves are grouped (signature, strings, launchers, lows, other strikes, throws, Ultimate) and the fighter's
-- listed combos (Roster CharacterDef.combos) follow in a COMBOS section; `fillCombos` renders that page on its own.
local UIHelpers = require(script.Parent.UIHelpers)
local M = {}

-- Plain-text input: keyboard shows the numeric notation with arrows ("↘ + 2"); gamepad maps 1-4 to its face buttons.
function M.formatInput(input: string, gamepad: boolean?): string
	if not gamepad then return UIHelpers.notationText(input) end
	local map = {
		["1"] = UIHelpers.keyLabel("fight", "lp", "gamepad"), ["2"] = UIHelpers.keyLabel("fight", "rp", "gamepad"),
		["3"] = UIHelpers.keyLabel("fight", "lk", "gamepad"), ["4"] = UIHelpers.keyLabel("fight", "rk", "gamepad"),
	}
	local parts = {}
	for _, tok in UIHelpers.notationTokens(input) do
		if tok.kind == "btn" then table.insert(parts, if map[tok.value] and map[tok.value] ~= "" then map[tok.value] else tok.value)
		elseif tok.kind == "dir" then table.insert(parts, UIHelpers.ARROWS[tok.value] or tok.value)
		elseif tok.kind == "plus" then table.insert(parts, "+")
		elseif tok.kind == "then" then table.insert(parts, "›")
		else table.insert(parts, tok.value) end
	end
	return table.concat(parts, " ")
end

function M.properties(move: any): { string }
	local props = {}
	if move.cinematic then table.insert(props, "ULTIMATE") end
	if move.onHit == "LAUNCH" or move.tier == "Launch" then table.insert(props, "LAUNCH") end
	if move.onCounter == "LAUNCH" then table.insert(props, "CH LAUNCH") end
	if move.tumble == true then table.insert(props, "TUMBLE") end
	if move.onHit == "KND" and not move.cinematic then table.insert(props, "KND") end
	if move.height == "Throw" then table.insert(props, "THROW") end
	if typeof(move.toStance) == "string" then table.insert(props, "STANCE") end
	if typeof(move.chainFrom) == "string" then table.insert(props, "STRING") end
	if typeof(move.delay) == "number" then table.insert(props, "DELAY") end
	if move.props then
		if move.props.catch then table.insert(props, "CATCH") end
		if move.props.armor and not move.cinematic then table.insert(props, "ARMOR") end
		if move.props.parry then table.insert(props, "PARRY") end
		if move.props.highCrush then table.insert(props, "HIGH CRUSH") end
		if move.props.lowCrush then table.insert(props, "LOW CRUSH") end
	end
	if typeof(move.stanceCancel) == "string" then table.insert(props, "CANCEL") end
	return props
end

function M.heightTag(height: string): string
	if height == "High" then return "H" elseif height == "Mid" then return "M" elseif height == "Low" then return "L" elseif height == "Throw" then return "T" end
	return string.sub(height, 1, 1)
end

M.HEIGHT_COLORS = {
	High = Color3.fromRGB(255, 200, 92), Mid = Color3.fromRGB(96, 214, 255), Low = Color3.fromRGB(255, 104, 112), Throw = Color3.fromRGB(196, 150, 255),
} :: { [string]: Color3 }
M.HEIGHT_WORDS = { High = "HIGH", Mid = "MID", Low = "LOW", Throw = "THROW" } :: { [string]: string }

local function stanceWords(st: any): string
	local bits = {}
	local p = st.props or {}
	if p.highCrush then table.insert(bits, "ducks highs") end
	if p.lowCrush then table.insert(bits, "airborne over lows") end
	if p.parry then table.insert(bits, "parries highs and mids") end
	if st.guard then table.insert(bits, "guards highs and mids") end
	if (st.travel or 0) > 0 then table.insert(bits, "travels forward") end
	if st.backExit then table.insert(bits, "back to leave") end
	return table.concat(bits, ", ")
end

-- One line for a move: the generated description plus what round 6 added (stances, tumble, catch, the Ultimate).
function M.describe(move: any, def: any?): string
	if move.cinematic then
		local frames = if typeof(move.startup) == "number" then " · i" .. (move.startup + 1) else ""
		return "Only in Surge (25% health or less), once per round · armored startup" .. frames .. " · " .. tostring(move.damage) .. " damage cinematic · punishable on block"
	end
	if typeof(move.toStance) == "string" then
		local st = def and def.stances and def.stances[move.toStance]
		return "Enter " .. (if st then st.name else move.toStance) .. (if st then " · " .. stanceWords(st) else "") .. " · follow-ups below"
	end
	if move.props and move.props.catch then
		return "Catch: a high or mid that touches him becomes an unbreakable throw · lows and throws beat it · punishable on whiff"
	end
	local text = UIHelpers.moveDescription(move)
	local extra = {}
	if move.tumble == true then table.insert(extra, "tumble: one more juggle hit") end
	if move.onCounter == "LAUNCH" then table.insert(extra, "launches on counter hit") end
	if typeof(move.delay) == "number" then table.insert(extra, "can be delayed") end
	if typeof(move.stanceCancel) == "string" then
		local st = def and def.stances and def.stances[move.stanceCancel]
		table.insert(extra, "3+4 cancels into " .. (if st then st.name else move.stanceCancel))
	end
	if #extra > 0 then text ..= " · " .. table.concat(extra, " · ") end
	return text
end

export type Group = { id: string, title: string, note: string, keys: { string } }

-- The fighter's moves in groups, each move once, in moveOrder inside a group.
function M.groups(def: any): { Group }
	local moves = def.moves
	local order: { string } = def.moveOrder
	local placed: { [string]: boolean } = {}
	local groups: { Group } = {}
	local function isSignature(key: string): boolean
		local mv = moves[key]
		local seen = 0
		while mv and seen < 8 do
			if typeof(mv.toStance) == "string" or typeof(mv.stance) == "string" or (mv.props and mv.props.catch) then return true end
			mv = if typeof(mv.chainFrom) == "string" then moves[mv.chainFrom] else nil
			seen += 1
		end
		return false
	end
	local function hasFollowers(key: string): boolean
		for _, k in order do if moves[k].chainFrom == key then return true end end
		return false
	end
	local sig = def.signature
	local spec: { { id: string, title: string, note: string, pick: (string, any) -> boolean } } = {
		{ id = "Signature", title = if sig then "SIGNATURE · " .. string.upper(sig.name) .. " (3+4)" else "SIGNATURE (3+4)", note = if sig then sig.summary else "",
			pick = function(key) return isSignature(key) end },
		{ id = "Ultimate", title = "ULTIMATE (1+2)", note = "Only in Surge (25% health or less), once per round. Keyboard L, or 1+2 together; gamepad RT.",
			pick = function(_key, mv) return mv.cinematic ~= nil end },
		{ id = "Throws", title = "THROWS", note = "Beat a guarding opponent. Break by pressing the button shown as the grab starts.",
			pick = function(_key, mv) return mv.height == "Throw" end },
		{ id = "Strings", title = "STRINGS", note = "Press the next button as the previous hit lands (› = next hit).",
			pick = function(key, mv) return typeof(mv.chainFrom) == "string" or hasFollowers(key) end },
		{ id = "Launchers", title = "LAUNCHERS", note = "Pop the opponent up, then juggle. A TUMBLE hit spins them for one more hit (once per juggle).",
			pick = function(_key, mv) return mv.onHit == "LAUNCH" or mv.onCounter == "LAUNCH" end },
		{ id = "Lows", title = "LOWS", note = "Must be blocked crouching.",
			pick = function(_key, mv) return mv.height == "Low" end },
		{ id = "Strikes", title = "POKES, MIDS AND POWER", note = "",
			pick = function() return true end },
	}
	local byId: { [string]: Group } = {}
	for _, g in spec do
		local group: Group = { id = g.id, title = g.title, note = g.note, keys = {} }
		byId[g.id] = group
		for _, key in order do
			local mv = moves[key]
			if mv and not placed[key] and g.pick(key, mv) then
				placed[key] = true
				table.insert(group.keys, key)
			end
		end
	end
	-- Display order: signature, strings, launchers, lows, other strikes, throws, Ultimate.
	for _, id in { "Signature", "Strings", "Launchers", "Lows", "Strikes", "Throws", "Ultimate" } do
		local g = byId[id]
		if g and #g.keys > 0 then table.insert(groups, g) end
	end
	return groups
end

local KIND_WORDS = { launch = "LAUNCH", stance = "STANCE", counter = "COUNTER HIT", low = "LOW START", max = "MAX DAMAGE", ultimate = "ULTIMATE" } :: { [string]: string }
M.COMBO_KIND_WORDS = KIND_WORDS

-- Round 7: combo difficulty in words. The Roster labels are measured (combat-balance.md, Round 7): 1 = lands even with
-- sloppy timing; each point more = a longer route, a stance entry, a counter-hit start or a tighter step.
local DIFFICULTY_WORDS = { "EASY", "MEDIUM", "TRICKY", "HARD", "EXPERT" }
M.DIFFICULTY_WORDS = DIFFICULTY_WORDS
function M.difficultyText(n: number?): string
	local d = math.clamp(math.floor(tonumber(n) or 1), 1, #DIFFICULTY_WORDS)
	return DIFFICULTY_WORDS[d] .. "  " .. d .. "/5"
end

local function clear(scroll: ScrollingFrame)
	for _, child in scroll:GetChildren() do
		if child:IsA("GuiObject") then child:Destroy() end
	end
	if not scroll:FindFirstChildOfClass("UIListLayout") then
		UIHelpers.list(scroll, false, 4)
	end
end

-- Section headers, the jump button and combo rows are not Frames: the lobby counts the Frame rows of the list as the
-- fighter's moves (LobbyUI_Test), so only move rows are Frames.
local function header(scroll: ScrollingFrame, name: string, title: string, note: string, order: number): TextLabel
	local T = UIHelpers.Theme
	local h = if note ~= "" then (if #note > 120 then 70 else 52) else 36
	local label: TextLabel = UIHelpers.make("TextLabel", {
		Name = name, LayoutOrder = order, Size = UDim2.new(1, -12, 0, h), BackgroundTransparency = 1, BorderSizePixel = 0,
		Text = "", Parent = scroll,
	})
	UIHelpers.make("Frame", { Name = "Rule", BackgroundColor3 = T.ember, BorderSizePixel = 0, Position = UDim2.new(0, 0, 0, 30), Size = UDim2.new(1, 0, 0, 1), BackgroundTransparency = 0.6, Parent = label })
	UIHelpers.text(label, "Title", title, T.title, 20, T.text, { Position = UDim2.fromOffset(2, 2), Size = UDim2.new(1, -4, 0, 26) })
	if note ~= "" then
		UIHelpers.text(label, "Note", note, T.medium, 14, T.muted, { Position = UDim2.fromOffset(2, 34), Size = UDim2.new(1, -4, 0, h - 34), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
	end
	return label
end

local function chip(parent: Instance, name: string, value: string, color: Color3, filled: boolean, order: number)
	local T = UIHelpers.Theme
	local c = UIHelpers.make("Frame", { Name = name, BackgroundColor3 = color, BackgroundTransparency = if filled then 0.1 else 0.75, BorderSizePixel = 0, Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = order, Parent = parent })
	UIHelpers.corner(c, 3)
	UIHelpers.make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), Parent = c })
	UIHelpers.text(c, "Text", value, T.heavy, 11, if filled then T.ink else T.text, { Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X })
end

local function moveRow(scroll: ScrollingFrame, def: any, key: string, order: number, stripe: number, rowHeight: number)
	local T = UIHelpers.Theme
	local make, text = UIHelpers.make, UIHelpers.text
	local mv = def.moves[key]
	local row = make("Frame", {
		Name = "Move_" .. key, LayoutOrder = order, Size = UDim2.new(1, -12, 0, rowHeight), BackgroundColor3 = T.panel2,
		BackgroundTransparency = if stripe % 2 == 1 then 0.25 else 0.55, BorderSizePixel = 0, Parent = scroll,
	})
	UIHelpers.corner(row, 4)
	local heightColor = M.HEIGHT_COLORS[mv.height] or T.muted
	make("Frame", { Name = "Edge", BackgroundColor3 = heightColor, BorderSizePixel = 0, Size = UDim2.new(0, 3, 1, -12), Position = UDim2.fromOffset(0, 6), Parent = row })
	local inputBox = make("Frame", { Name = "Input", BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 0), Size = UDim2.new(0, 196, 1, 0), Parent = row })
	UIHelpers.list(inputBox, true, 0, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	UIHelpers.notationRow(inputBox, if typeof(mv.input) == "string" then mv.input else "", { height = 24, name = "Notation" })
	local frames = if typeof(mv.startup) == "number" and mv.height ~= "Throw" and not mv.noHit then "  i" .. (mv.startup + 1) else ""
	text(row, "Name", string.upper(mv.name or key) .. frames, T.heavy, 17, T.text, { Position = UDim2.new(0, 222, 0, 7), Size = UDim2.new(0.74, -230, 0, 22), TextTruncate = Enum.TextTruncate.AtEnd })
	text(row, "Desc", M.describe(mv, def), T.medium, 14, T.muted, { Position = UDim2.new(0, 222, 0, 29), Size = UDim2.new(0.74, -230, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd })
	local tag = make("Frame", { Name = "Height", BackgroundColor3 = heightColor, BackgroundTransparency = 0.82, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.74, 0, 0.5, 0), Size = UDim2.fromOffset(62, 24), Parent = row })
	UIHelpers.corner(tag, 4)
	UIHelpers.outline(tag, heightColor, 1, 0.35)
	text(tag, "Text", M.HEIGHT_WORDS[mv.height] or string.upper(tostring(mv.height)), T.heavy, 13, heightColor, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
	local propsBox = make("Frame", { Name = "Props", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.new(0.26, -80, 0, 24), Parent = row })
	UIHelpers.list(propsBox, true, 4, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
	local shown = 0
	for i, p in M.properties(mv) do
		if p ~= "THROW" and p ~= "STRING" and p ~= "CANCEL" and shown < 2 then
			shown += 1
			local hot = p == "LAUNCH" or p == "ULTIMATE" or p == "TUMBLE"
			chip(propsBox, "Prop_" .. p, p, if p == "TUMBLE" then T.gold else T.ember, hot, i)
		end
	end
end

local function comboRow(scroll: ScrollingFrame, combo: any, order: number, stripe: number, first: boolean?)
	local T = UIHelpers.Theme
	local make, text = UIHelpers.make, UIHelpers.text
	local row = make("ImageLabel", {
		Name = "Combo_" .. string.gsub(combo.name, "%W", ""), LayoutOrder = order, Size = UDim2.new(1, -12, 0, 66), BackgroundColor3 = T.panel2,
		BackgroundTransparency = if stripe % 2 == 1 then 0.25 else 0.55, BorderSizePixel = 0, Image = "", Parent = scroll,
	})
	UIHelpers.corner(row, 4)
	local isUlt = combo.kind == "ultimate"
	make("Frame", { Name = "Edge", BackgroundColor3 = if isUlt then T.gold else T.ember, BorderSizePixel = 0, Size = UDim2.new(0, 3, 1, -12), Position = UDim2.fromOffset(0, 6), Parent = row })
	local titleBox = make("Frame", { Name = "Title", BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 6), Size = UDim2.new(0.7, -20, 0, 24), Parent = row })
	UIHelpers.list(titleBox, true, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	local name = text(titleBox, "Name", string.upper(combo.name), T.heavy, 17, T.text, { Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X })
	name.LayoutOrder = 1
	chip(titleBox, "Kind", KIND_WORDS[combo.kind] or string.upper(combo.kind), if isUlt then T.gold else T.ember, isUlt, 2)
	if combo.counter then chip(titleBox, "Counter", "COUNTER HIT START", T.cool, false, 3) end
	if combo.surge then chip(titleBox, "Surge", "IN SURGE", T.gold, false, 4) end
	-- The first listed route is each fighter's easy one (Roster combos, round 7).
	local difficulty = math.clamp(math.floor(tonumber(combo.difficulty) or 1), 1, 5)
	if first and difficulty <= 2 then chip(titleBox, "Start", "START HERE", T.cool, true, 5) end
	local notation = make("Frame", { Name = "Inputs", BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 34), Size = UDim2.new(0.78, -20, 0, 26), Parent = row })
	UIHelpers.list(notation, true, 0, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	-- The counter-hit opener has its own chip; "CH " would otherwise merge with the first direction ("CHF").
	UIHelpers.notationRow(notation, (string.gsub(combo.notation, "^CH%s+", "")), { height = 24, name = "Notation" })
	text(row, "Damage", tostring(combo.damage) .. " DMG", T.number, 22, if isUlt then T.gold else T.text, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 8), Size = UDim2.fromOffset(150, 26), TextXAlignment = Enum.TextXAlignment.Right })
	text(row, "Difficulty", M.difficultyText(difficulty), T.heavy, 12, if difficulty <= 2 then T.cool elseif difficulty >= 4 then T.ember else T.muted, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 38), Size = UDim2.fromOffset(150, 18), TextXAlignment = Enum.TextXAlignment.Right })
end

local COMBO_NOTE = "Start with the first route: short and forgiving. Difficulty is measured with sloppy timing (1 easy, 5 expert); every route works on all six fighters. Ultimate routes are played in Surge; counter-hit routes start on a counter hit."

-- Fills `scroll` with the fighter's listed combos only (a COMBOS page). Returns the number of combo rows.
function M.fillCombos(scroll: ScrollingFrame, def: any, opts: { [string]: any }?): number
	local _ = opts
	clear(scroll)
	header(scroll, "Group_Combos", "COMBOS", COMBO_NOTE, 1)
	local count = 0
	for i, combo in def.combos or {} do
		count += 1
		comboRow(scroll, combo, 1 + i, i, i == 1)
	end
	return count
end

-- Fills `scroll` (a ScrollingFrame) with the fighter's moves in groups, then its combos. Clears previous rows first,
-- so switching fighters never accumulates instances. Returns the number of move rows. `fonts` is kept for old callers;
-- opts.combos = false leaves the COMBOS section out.
function M.fillList(scroll: ScrollingFrame, def: any, _fonts: any?, opts: { [string]: any }?): number
	local o = opts or {}
	local T = UIHelpers.Theme
	clear(scroll)
	local rowHeight = o.rowHeight or 54
	local count = 0
	local order = 0
	local combos = if o.combos == false then {} else (def.combos or {})
	if #combos > 0 then
		-- A jump to the COMBOS section for mouse and touch (gamepad and keys scroll there).
		order += 1
		local button = UIHelpers.make("TextButton", { Name = "Jump", LayoutOrder = order, Text = "COMBOS ↓", FontFace = T.heavy, TextSize = 14, TextColor3 = T.ink, BackgroundColor3 = T.gold, BorderSizePixel = 0, AutoButtonColor = true, Size = UDim2.fromOffset(120, 26), Parent = scroll })
		UIHelpers.corner(button, 4)
		button.Activated:Connect(function()
			local target = scroll:FindFirstChild("Group_Combos")
			if target and target:IsA("GuiObject") then
				scroll.CanvasPosition = Vector2.new(0, math.max(0, target.AbsolutePosition.Y - scroll.AbsolutePosition.Y + scroll.CanvasPosition.Y))
			end
		end)
	end
	for _, group in M.groups(def) do
		order += 1
		header(scroll, "Group_" .. group.id, group.title, group.note, order)
		for stripe, key in group.keys do
			order += 1
			count += 1
			moveRow(scroll, def, key, order, stripe, rowHeight)
		end
	end
	if #combos > 0 then
		order += 1
		header(scroll, "Group_Combos", "COMBOS", COMBO_NOTE, order)
		for i, combo in combos do
			order += 1
			comboRow(scroll, combo, order, i, i == 1)
		end
	end
	return count
end

-- Up to three highlight moves for the fighter select: the 3+4 signature, a launcher and the Ultimate (older rosters
-- without them fall back to a knockdown, a string and a throw).
function M.signature(def: any): { string }
	local picks: { string } = {}
	local function add(pred: (any) -> boolean)
		for _, key in def.moveOrder do
			local mv = def.moves[key]
			if mv and not table.find(picks, key) and pred(mv) then table.insert(picks, key); return end
		end
	end
	add(function(mv) return typeof(mv.toStance) == "string" or (mv.props ~= nil and mv.props.catch ~= nil) end)
	add(function(mv) return (mv.onHit == "LAUNCH" or mv.tier == "Launch") and mv.stance == nil end)
	add(function(mv) return mv.cinematic ~= nil end)
	add(function(mv) return mv.onHit == "KND" or (mv.tier == "Heavy" and mv.height ~= "Throw") end)
	add(function(mv) return typeof(mv.chainFrom) == "string" end)
	add(function(mv) return mv.height == "Throw" end)
	while #picks > 3 do table.remove(picks) end
	return picks
end

return M
