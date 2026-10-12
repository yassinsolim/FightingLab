--!strict
-- Move list (OV6). Numeric notation (1/2/3/4 = left punch / right punch / left kick / right kick, arrows for
-- directions, all taken through UIHelpers.notationOf, which defers to Controls.notationOf) and generated one-line
-- descriptions, so whatever moveset the Roster holds is rendered readably.
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
	if move.onHit == "LAUNCH" or move.tier == "Launch" then table.insert(props, "LAUNCH") end
	if move.onHit == "KND" then table.insert(props, "KND") end
	if move.height == "Throw" then table.insert(props, "THROW") end
	if typeof(move.chainFrom) == "string" then table.insert(props, "STRING") end
	if move.props then
		if move.props.armor then table.insert(props, "ARMOR") end
		if move.props.parry then table.insert(props, "PARRY") end
		if move.props.highCrush then table.insert(props, "HIGH CRUSH") end
		if move.props.lowCrush then table.insert(props, "LOW CRUSH") end
	end
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

-- Fills `scroll` (a ScrollingFrame) with one row per move of `def` (a Roster character). Clears previous rows first,
-- so switching fighters never accumulates instances. Returns the number of rows. `fonts` is kept for old callers.
function M.fillList(scroll: ScrollingFrame, def: any, _fonts: any?, opts: { [string]: any }?): number
	local o = opts or {}
	local T = UIHelpers.Theme
	local make, text = UIHelpers.make, UIHelpers.text
	for _, child in scroll:GetChildren() do
		if child:IsA("GuiObject") then child:Destroy() end
	end
	if not scroll:FindFirstChildOfClass("UIListLayout") then
		UIHelpers.list(scroll, false, 4)
	end
	local rowHeight = o.rowHeight or 54
	local count = 0
	for order, key in def.moveOrder do
		local mv = def.moves[key]
		if mv then
			count += 1
			local row = make("Frame", {
				Name = "Move_" .. key, LayoutOrder = order, Size = UDim2.new(1, -12, 0, rowHeight), BackgroundColor3 = T.panel2,
				BackgroundTransparency = if order % 2 == 1 then 0.25 else 0.55, BorderSizePixel = 0, Parent = scroll,
			})
			UIHelpers.corner(row, 4)
			local heightColor = M.HEIGHT_COLORS[mv.height] or T.muted
			make("Frame", { Name = "Edge", BackgroundColor3 = heightColor, BorderSizePixel = 0, Size = UDim2.new(0, 3, 1, -12), Position = UDim2.fromOffset(0, 6), Parent = row })
			local inputBox = make("Frame", { Name = "Input", BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 0), Size = UDim2.new(0, 196, 1, 0), Parent = row })
			UIHelpers.list(inputBox, true, 0, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
			UIHelpers.notationRow(inputBox, if typeof(mv.input) == "string" then mv.input else "", { height = 24, name = "Notation" })
			text(row, "Name", string.upper(mv.name or key), T.heavy, 17, T.text, { Position = UDim2.new(0, 222, 0, 7), Size = UDim2.new(0.74, -230, 0, 22), TextTruncate = Enum.TextTruncate.AtEnd })
			text(row, "Desc", UIHelpers.moveDescription(mv), T.medium, 14, T.muted, { Position = UDim2.new(0, 222, 0, 29), Size = UDim2.new(0.74, -230, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd })
			local tag = make("Frame", { Name = "Height", BackgroundColor3 = heightColor, BackgroundTransparency = 0.82, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.74, 0, 0.5, 0), Size = UDim2.fromOffset(62, 24), Parent = row })
			UIHelpers.corner(tag, 4)
			UIHelpers.outline(tag, heightColor, 1, 0.35)
			text(tag, "Text", M.HEIGHT_WORDS[mv.height] or string.upper(tostring(mv.height)), T.heavy, 13, heightColor, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
			local props = M.properties(mv)
			local propsBox = make("Frame", { Name = "Props", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.new(0.26, -80, 0, 24), Parent = row })
			UIHelpers.list(propsBox, true, 4, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
			for i, p in props do
				if p ~= "THROW" and i <= 2 then
					local chip = make("Frame", { Name = "Prop_" .. p, BackgroundColor3 = T.ember, BackgroundTransparency = if p == "LAUNCH" then 0.1 else 0.75, BorderSizePixel = 0, Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = i, Parent = propsBox })
					UIHelpers.corner(chip, 3)
					make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), Parent = chip })
					text(chip, "Text", p, T.heavy, 11, if p == "LAUNCH" then T.ink else T.text, { Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X })
				end
			end
		end
	end
	return count
end

-- Up to three "signature" moves for the fighter select: launcher, a knockdown/power move and a string.
function M.signature(def: any): { string }
	local picks: { string } = {}
	local function add(pred: (any) -> boolean)
		for _, key in def.moveOrder do
			local mv = def.moves[key]
			if mv and not table.find(picks, key) and pred(mv) then table.insert(picks, key); return end
		end
	end
	add(function(mv) return mv.onHit == "LAUNCH" or mv.tier == "Launch" end)
	add(function(mv) return mv.onHit == "KND" or (mv.tier == "Heavy" and mv.height ~= "Throw") end)
	add(function(mv) return typeof(mv.chainFrom) == "string" end)
	add(function(mv) return mv.height == "Throw" end)
	while #picks > 3 do table.remove(picks) end
	return picks
end

return M
