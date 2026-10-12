--!strict
local TweenService = game:GetService("TweenService")
local M = {}
export type ComboState = { attacker: number, hits: number, damage: number, shown: boolean, expiresAt: number, counterUntil: number }
export type Rect = { x: number, y: number, w: number, h: number }
export type ViewportFramePlan = { pivot: CFrame, cameraCFrame: CFrame, fieldOfView: number, facingDot: number, verticalFit: number }

-- Only notable events get callouts; plain hits, blocks and whiffs would spam the screen every exchange.
local POPUPS = {
	ThrowBreak = "THROW ESCAPE",
	ThrowHit = "THROW",
	Parry = "PARRY",
	Armor = "ARMOR",
	Crush = "CRUSH",
}

function M.damageTrail(currentTrail: number, targetHealth: number, dt: number, maxHealth: number): number
	local target = math.clamp(targetHealth, 0, maxHealth)
	local trail = math.clamp(currentTrail, 0, maxHealth)
	if target >= trail then return target end
	local speed = math.max(maxHealth * 0.22, (trail - target) * 4.2)
	return math.max(target, trail - speed * math.max(dt, 0))
end

function M.healthRatio(health: number, maxHealth: number): number
	if maxHealth <= 0 then error("maxHealth must be positive") end
	return math.clamp(health / maxHealth, 0, 1)
end

function M.formatTimer(mode: string, frames: number, fps: number): string
	if mode == "Training" then return utf8.char(0x221E) end
	if fps <= 0 then error("fps must be positive") end
	return string.format("%02d", math.max(0, math.ceil(frames / fps)))
end

function M.roundPips(score: number, needed: number): { boolean }
	local result = {}
	for i = 1, needed do result[i] = i <= score end
	return result
end

function M.registerCombo(state: ComboState, event: any, now: number): ComboState
	local nextState: ComboState = table.clone(state)
	if event.kind == "Hit" and (event.combo or 0) >= 2 then
		nextState.attacker = event.attacker or state.attacker
		nextState.hits = event.combo
		nextState.damage += event.damage or 0
		nextState.shown = true
		nextState.expiresAt = now + 1.35
	elseif event.kind == "Hit" then
		nextState.attacker = event.attacker or state.attacker
		nextState.hits = 1
		nextState.damage = event.damage or 0
		nextState.shown = false
		nextState.expiresAt = now + 0.8
	end
	if event.counter == true then nextState.counterUntil = now + 0.85 end
	return nextState
end

function M.comboVisible(state: ComboState, now: number): boolean
	return state.shown and now <= state.expiresAt
end

function M.rectsOverlap(a: Rect, b: Rect, padding: number?): boolean
	local p = padding or 0
	return a.x < b.x + b.w + p and a.x + a.w + p > b.x and a.y < b.y + b.h + p and a.y + a.h + p > b.y
end

function M.anyOverlap(targets: { Rect }, hudRects: { Rect }, padding: number?): boolean
	for _, t in targets do
		for _, h in hudRects do
			if M.rectsOverlap(t, h, padding) then return true end
		end
	end
	return false
end

function M.viewportFramePlan(modelPivot: CFrame, minBound: Vector3, maxBound: Vector3, bust: boolean, yawDegrees: number): ViewportFramePlan
	if minBound.X > maxBound.X or minBound.Y > maxBound.Y or minBound.Z > maxBound.Z then
		error("viewportFramePlan requires valid model bounds")
	end
	local center = (minBound + maxBound) * 0.5
	local bodySize = maxBound - minBound
	local height = math.max(bodySize.Y, 3)
	local fieldOfView = if bust then 24 else 32
	-- Bounds cover body parts only, so busts keep headroom for hair and headwear above the head.
	local focusY = if bust then height * 0.31 else 0
	local verticalFit = if bust then height * 0.56 else height * 1.12
	local distance = (verticalFit * 0.5) / math.tan(math.rad(fieldOfView) * 0.5)
	local cameraPosition = Vector3.new(0, focusY, distance)
	local pivot = CFrame.new(-center) * modelPivot * CFrame.Angles(0, math.rad(180 + yawDegrees), 0)
	local flatLook = Vector3.new(pivot.LookVector.X, 0, pivot.LookVector.Z)
	local flatToCamera = Vector3.new(cameraPosition.X - pivot.Position.X, 0, cameraPosition.Z - pivot.Position.Z)
	local facingDot = if flatLook.Magnitude > 0.001 and flatToCamera.Magnitude > 0.001 then flatLook.Unit:Dot(flatToCamera.Unit) else 0
	return {
		pivot = pivot,
		cameraCFrame = CFrame.new(cameraPosition, Vector3.new(0, focusY, 0)),
		fieldOfView = fieldOfView,
		facingDot = facingDot,
		verticalFit = verticalFit,
	}
end

function M.popupForEvent(e: any): string?
	if e.kind == "Hit" and e.counter == true then return "COUNTER HIT" end
	if e.kind == "Hit" and e.launch == true then return "LAUNCH" end
	if e.kind == "Hit" and e.knockdown == true then return "KNOCKDOWN" end
	return POPUPS[e.kind]
end

function M.statBars(character: any): { health: number, speed: number, power: number }
	local stats = character.stats
	local total = 0
	local count = 0
	for _, key in character.moveOrder do
		local move = character.moves[key]
		if move and move.height ~= "Throw" then total += move.damage; count += 1 end
	end
	local avg = if count > 0 then total / count else 1
	return {
		health = math.clamp(stats.maxHealth / 120, 0, 1),
		speed = math.clamp((stats.walkSpeed + stats.sideSpeed + stats.dashSpeed / 2) / 36, 0, 1),
		power = math.clamp(avg / 18, 0, 1),
	}
end

--------------------------------------------------------------------------------------------------------------------
-- FightingLab UI kit (OV6 "Ember & Steel"): shared theme, Controls-driven key glyphs, move notation, buttons and
-- pure helpers for LobbyUI, FighterSelect, HudController, StationBoards and Leaderboard. Builders only touch the
-- parent they are given, so they are safe to call from server-side tests.
--------------------------------------------------------------------------------------------------------------------
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local LabFolder = script.Parent.Parent

local function fontFamily(name: string): string return "rbxasset://fonts/families/" .. name .. ".json" end

M.Theme = {
	-- Type: slanted black display for names and call-outs, a sturdy grotesque for labels, wide numerals for clocks.
	display = Font.new(fontFamily("Montserrat"), Enum.FontWeight.Heavy, Enum.FontStyle.Italic),
	title = Font.new(fontFamily("Montserrat"), Enum.FontWeight.ExtraBold, Enum.FontStyle.Italic),
	number = Font.new(fontFamily("BuilderExtended"), Enum.FontWeight.ExtraBold),
	heavy = Font.new(fontFamily("BuilderSans"), Enum.FontWeight.ExtraBold),
	bold = Font.new(fontFamily("BuilderSans"), Enum.FontWeight.Bold),
	medium = Font.new(fontFamily("BuilderSans"), Enum.FontWeight.Medium),
	-- Colour: ink-steel surfaces, one hot ember accent, gold for wins/selection, cyan for the far side.
	bg = Color3.fromRGB(7, 9, 14),
	panel = Color3.fromRGB(14, 17, 25),
	panel2 = Color3.fromRGB(22, 27, 38),
	line = Color3.fromRGB(255, 255, 255),
	text = Color3.fromRGB(243, 245, 249),
	muted = Color3.fromRGB(163, 172, 189),
	dim = Color3.fromRGB(98, 107, 125),
	ink = Color3.fromRGB(10, 12, 18),
	panelTop = Color3.fromRGB(24, 29, 41),
	panelBottom = Color3.fromRGB(10, 12, 18),
	slot = Color3.fromRGB(32, 38, 52),
	ember = Color3.fromRGB(255, 84, 51),
	gold = Color3.fromRGB(255, 200, 69),
	warm = Color3.fromRGB(255, 120, 56),
	cool = Color3.fromRGB(67, 198, 255),
	win = Color3.fromRGB(255, 205, 82),
	loss = Color3.fromRGB(255, 71, 87),
	live = Color3.fromRGB(255, 64, 86),
	ok = Color3.fromRGB(91, 228, 155),
	key = Color3.fromRGB(240, 242, 247),
	health = Color3.fromRGB(255, 226, 120),
	healthLow = Color3.fromRGB(255, 76, 64),
}
M.Difficulties = { "Easy", "Normal", "Hard" }
M.DifficultyInfo = {
	Easy = { color = Color3.fromRGB(91, 228, 155), text = "Slow reactions, blocks rarely, short combos" },
	Normal = { color = Color3.fromRGB(255, 200, 69), text = "Blocks and punishes sometimes, uses strings" },
	Hard = { color = Color3.fromRGB(255, 84, 51), text = "Reads you, punishes, mixes throws and lows" },
} :: { [string]: { color: Color3, text: string } }

function M.make(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst: any = Instance.new(className)
	local parent: any = nil
	if props then
		for key, value in props do
			if key == "Parent" then parent = value else inst[key] = value end
		end
	end
	if children then for _, child in children do child.Parent = inst end end
	if parent then inst.Parent = parent end
	return inst
end

-- radius in pixels; nil gives a fully rounded pill/circle.
function M.corner(parent: Instance, radius: number?): UICorner
	return M.make("UICorner", { CornerRadius = if radius then UDim.new(0, radius) else UDim.new(1, 0), Parent = parent })
end

function M.outline(parent: Instance, color: Color3, thickness: number?, transparency: number?): UIStroke
	return M.make("UIStroke", { Color = color, Thickness = thickness or 1, Transparency = transparency or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = parent })
end

-- Dark contextual outline that keeps text readable over bright 3D scenes.
function M.textStroke(parent: Instance, transparency: number?, thickness: number?): UIStroke
	return M.make("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = thickness or 1.5, Transparency = transparency or 0.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, Parent = parent })
end

function M.gradient(parent: Instance, top: Color3, bottom: Color3, rotation: number?, transparency: NumberSequence?): UIGradient
	return M.make("UIGradient", { Color = ColorSequence.new(top, bottom), Rotation = rotation or 90, Transparency = transparency or NumberSequence.new(0), Parent = parent })
end

-- Transparency ramp helper: NumberSequence from {t, value} pairs.
function M.ramp(points: { { number } }): NumberSequence
	local keys = {}
	for _, p in points do table.insert(keys, NumberSequenceKeypoint.new(p[1], p[2])) end
	return NumberSequence.new(keys)
end

function M.padding(parent: Instance, x: number, y: number?): UIPadding
	local py = y or x
	return M.make("UIPadding", { PaddingLeft = UDim.new(0, x), PaddingRight = UDim.new(0, x), PaddingTop = UDim.new(0, py), PaddingBottom = UDim.new(0, py), Parent = parent })
end

function M.list(parent: Instance, horizontal: boolean, gap: number, align: Enum.HorizontalAlignment?, valign: Enum.VerticalAlignment?): UIListLayout
	return M.make("UIListLayout", {
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		Padding = UDim.new(0, gap), SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left, VerticalAlignment = valign or Enum.VerticalAlignment.Top,
		Parent = parent,
	})
end

function M.text(parent: Instance, name: string, value: string, font: Font, size: number, color: Color3, props: { [string]: any }?): TextLabel
	local label: any = M.make("TextLabel", { Name = name, Text = value, FontFace = font, TextSize = size, TextColor3 = color, BackgroundTransparency = 1, BorderSizePixel = 0, TextXAlignment = Enum.TextXAlignment.Left, Parent = parent })
	if props then for key, v in props do label[key] = v end end
	return label
end

-- Dark glass panel: ink gradient, hairline edge, small radius (the kit's corners stay sharp-ish on purpose).
function M.panel(parent: Instance, name: string, props: { [string]: any }?): Frame
	local frame: any = M.make("Frame", { Name = name, BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.06, BorderSizePixel = 0, Parent = parent })
	M.gradient(frame, M.Theme.panelTop, M.Theme.panelBottom, 90)
	M.corner(frame, 6)
	M.outline(frame, Color3.new(1, 1, 1), 1, 0.88)
	if props then for key, v in props do frame[key] = v end end
	return frame
end

-- Thin accent bar on the left edge of a panel/card.
function M.accentBar(parent: Instance, color: Color3, width: number?, props: { [string]: any }?): Frame
	local bar: any = M.make("Frame", { Name = "AccentBar", BackgroundColor3 = color, BorderSizePixel = 0, Size = UDim2.new(0, width or 4, 1, 0), Parent = parent })
	if props then for key, v in props do bar[key] = v end end
	return bar
end

-- A panel that grows with its content and carries a left accent edge. The edge cannot live in the same frame as a
-- UIListLayout (the layout would stack it, and a full-height child makes an auto-sized list frame grow without
-- bound), so the content goes into an inner "Content" frame that owns the padding and the list.
function M.edgeCard(parent: Instance, name: string, props: { [string]: any }, edgeColor: Color3, edgeWidth: number?, padX: number?, padY: number?): (Frame, Frame, Frame)
	local outer = M.panel(parent, name, props)
	outer.AutomaticSize = Enum.AutomaticSize.Y
	local content: any = M.make("Frame", { Name = "Content", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = outer })
	M.padding(content, padX or 14, padY or 12)
	local edge = M.accentBar(outer, edgeColor, edgeWidth or 4)
	return outer, content, edge
end

function M.tween(inst: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local tween = TweenService:Create(inst, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal)
	tween:Play()
	return tween
end

-- UI scale for a 1280x740 design space: 1.0 around 1366x768, ~1.46 at 1920x1080, never tiny on phones.
function M.uiScale(size: Vector2, touchOnly: boolean?): number
	if size.X <= 1 or size.Y <= 1 then return 1 end
	local s = math.min(size.X / 1280, size.Y / 740)
	return math.clamp(s, if touchOnly then 0.66 else 0.58, 1.6)
end

-- Keeps `root` covering `container` in design-space units scaled by a UIScale. Returns a disconnect function.
function M.fitToScreen(container: GuiBase2d, root: GuiObject, touchOnly: boolean?): () -> ()
	local scale: UIScale = M.make("UIScale", { Name = "DesignScale", Parent = root })
	local function apply()
		local abs = container.AbsoluteSize
		local s = M.uiScale(abs, touchOnly)
		scale.Scale = s
		root.Size = UDim2.fromOffset(math.max(abs.X, 1) / s, math.max(abs.Y, 1) / s)
	end
	local conn = container:GetPropertyChangedSignal("AbsoluteSize"):Connect(apply)
	apply()
	return function() conn:Disconnect() end
end

-- Whole seconds left before a server-time deadline: nil without a deadline, 0 once it passed.
function M.countdownDigit(endsAt: any, now: number): number?
	if typeof(endsAt) ~= "number" or endsAt <= 0 then return nil end
	local remaining = endsAt - now
	if remaining <= 0 then return 0 end
	return math.min(9, math.ceil(remaining - 1e-6))
end

function M.formatSeconds(seconds: any): string
	if typeof(seconds) ~= "number" or seconds ~= seconds then return "--" end
	return string.format("%d", math.max(0, math.ceil(seconds - 1e-6)))
end

function M.difficultyIndex(name: any): number
	for i, d in M.Difficulties do if d == name then return i end end
	return 2
end

-- Roster lookups that never throw on bad attribute values.
function M.fighterDef(roster: any, id: any): any?
	if typeof(id) ~= "string" or id == "" then return nil end
	local ok, has = pcall(roster.has, id)
	if not ok or not has then return nil end
	return roster.get(id)
end

function M.titleCase(s: string): string
	return (string.gsub(string.lower(s), "(%a)([%w']*)", function(a: string, b: string) return string.upper(a) .. b end))
end

--------------------------------------------------------------------------------------------------------------------
-- Controls (ReplicatedStorage.FightingLab.Controls is the single source of truth for every key the UI shows).
-- The fallback below only exists so the UI still renders in a place without the module; it mirrors contract §2.
--------------------------------------------------------------------------------------------------------------------
local FALLBACK = {
	fight = {
		keyboard = { forward = "D", back = "A", sidestepIn = "W", sidestepOut = "S", crouch = "S", lp = "U", rp = "I", lk = "J", rk = "K", throw = "O", guide = "G" },
		gamepad = { forward = "DPadRight", back = "DPadLeft", sidestepIn = "DPadUp", sidestepOut = "DPadDown", crouch = "DPadDown", lp = "ButtonX", rp = "ButtonY", lk = "ButtonA", rk = "ButtonB", throw = "ButtonR1", guide = "ButtonSelect" },
	},
	practice = {
		keyboard = { reset = "R", switchMode = "T", easy = "One", normal = "Two", hard = "Three", dummy = "Y", pause = "P", leave = "Backspace" },
		gamepad = { pause = "ButtonStart" },
	},
	lobby = {
		keyboard = { interact = "E", menu = "Tab", jump = "Space", play = "F", fighters = "C", sprint = "LeftShift" },
		gamepad = { interact = "ButtonX", menu = "ButtonY", jump = "ButtonA", play = "ButtonR1", fighters = "ButtonL1", sprint = "ButtonL3" },
	},
	notation = { lp = "1", rp = "2", lk = "3", rk = "4" },
}
local KEY_TEXT: { [string]: string } = {
	One = "1", Two = "2", Three = "3", Four = "4", Five = "5", Backspace = "BACKSPACE", Space = "SPACE", Tab = "TAB", Return = "ENTER",
	LeftShift = "SHIFT", RightShift = "SHIFT", LeftControl = "CTRL", Escape = "ESC",
	ButtonX = "X", ButtonY = "Y", ButtonA = "A", ButtonB = "B", ButtonR1 = "RB", ButtonL1 = "LB", ButtonR2 = "RT", ButtonL2 = "LT",
	ButtonStart = "START", ButtonSelect = "SELECT", DPadLeft = "←", DPadRight = "→", DPadUp = "↑", DPadDown = "↓",
	Left = "←", Right = "→", Up = "↑", Down = "↓", Thumbstick1 = "LS", Thumbstick2 = "RS", ButtonL3 = "L3", ButtonR3 = "R3",
}
M.KEY_TEXT = KEY_TEXT

local controlsModule: any = nil
local controlsTried = 0
local controlsOverride: any = nil
-- The live Controls module (cached once found); falls back to the §2 table without caching the fallback.
function M.controls(): any
	if controlsOverride then return controlsOverride end
	if controlsModule then return controlsModule end
	if os.clock() - controlsTried > 2 or controlsTried == 0 then
		controlsTried = os.clock()
		local module = LabFolder:FindFirstChild("Controls")
		if module and module:IsA("ModuleScript") then
			local ok, result = pcall(require, module)
			if ok and typeof(result) == "table" then controlsModule = result; return result end
		end
	end
	return FALLBACK
end
function M.usingFallbackControls(): boolean return M.controls() == FALLBACK end
-- Tests only: render the UI against a Controls-shaped table (nil restores the real module).
function M._setControlsForTests(c: any?) controlsOverride = c end

-- Plain-language action names (Controls.actionText); the copy below is only used when the module is missing.
local FALLBACK_TEXT: { [string]: string } = {
	forward = "Walk forward", back = "Walk back / guard", dash = "Dash", backdash = "Backdash",
	sidestepIn = "Sidestep in", sidestepOut = "Sidestep out", crouch = "Crouch / low guard",
	lp = "Left punch (1)", rp = "Right punch (2)", lk = "Left kick (3)", rk = "Right kick (4)",
	throw = "Throw (1+3)", throw1 = "Throw (1+3)", throw2 = "Throw (2+4)", breakThrow = "Break a throw",
	guard = "Guard", guide = "Controls guide",
	reset = "Reset positions", switchMode = "Training / Versus CPU", easy = "CPU Easy", normal = "CPU Normal", hard = "CPU Hard",
	dummy = "Dummy: stand / guard / fight back", pause = "Pause", leave = "Leave practice",
	interact = "Interact", menu = "Menu", jump = "Jump",
	play = "Play: Quick Duel, Fight CPU, Practice, Arenas", fighters = "Change fighter", sprint = "Sprint",
}
local FALLBACK_LEGEND: { [string]: { string } } = {
	practice = { "reset", "switchMode", "easy", "normal", "hard", "dummy", "pause", "leave" },
	lobby = { "play", "fighters", "sprint", "interact", "menu", "jump" },
}
function M.actionText(action: string): string
	local c = M.controls()
	local t = typeof(c.actionText) == "table" and c.actionText[action] or nil
	if typeof(t) == "string" and t ~= "" then return t end
	return FALLBACK_TEXT[action] or action
end

export type LegendRow = { action: string, keys: string, text: string }
-- Ordered rows { action, keys, text } for a group (Controls.legend); rows without a binding on the device are left
-- out, exactly like Controls.legend.
function M.legend(group: string, device: string?): { LegendRow }
	local dev = if device == "gamepad" then "gamepad" else "keyboard"
	local c = M.controls()
	if typeof(c.legend) == "function" then
		local ok, rows = pcall(c.legend, group, dev)
		if ok and typeof(rows) == "table" then
			local out: { LegendRow } = {}
			for _, r in rows do
				if typeof(r) == "table" and typeof(r.action) == "string" then
					table.insert(out, { action = r.action, keys = tostring(r.keys or ""), text = if typeof(r.text) == "string" then r.text else M.actionText(r.action) })
				end
			end
			return out
		end
	end
	local out: { LegendRow } = {}
	for _, action in FALLBACK_LEGEND[group] or {} do
		local keys = M.keyLabel(group, action, dev)
		if keys ~= "" then table.insert(out, { action = action, keys = keys, text = M.actionText(action) }) end
	end
	return out
end

-- "Dummy: stand / guard / fight back" -> "Dummy", { "stand", "guard", "fight back" }; "Training / Versus CPU" ->
-- nil, { "Training", "Versus CPU" }; "Pause" -> nil, { "Pause" }.
function M.legendOptions(textValue: string): (string?, { string })
	local prefix, rest = string.match(textValue, "^%s*([^:]+):%s*(.+)$")
	local body = if rest then rest else textValue
	local options = {}
	for part in string.gmatch(body, "[^/]+") do
		local trimmed = string.match(part, "^%s*(.-)%s*$") :: string
		if trimmed ~= "" then table.insert(options, trimmed) end
	end
	return (if prefix then string.match(prefix, "^%s*(.-)%s*$") else nil), options
end

local function rawBinding(group: string, action: string, device: string?): string?
	local c = M.controls()
	local g = c[group]
	local d = typeof(g) == "table" and g[device or "keyboard"] or nil
	local v = typeof(d) == "table" and d[action] or nil
	if typeof(v) == "string" then return v end
	if typeof(v) == "EnumItem" then return v.Name end
	if typeof(v) == "table" and typeof(v[1]) == "string" then return v[1] end
	return nil
end

-- Display text for one action ("D", "1", "BACKSPACE", "X"); "" when the action has no binding on that device.
function M.keyLabel(group: string, action: string, device: string?): string
	local c = M.controls()
	if typeof(c.label) == "function" then
		local ok, value = pcall(c.label, group, action, device or "keyboard")
		if ok and typeof(value) == "string" then return value end
	end
	local raw = rawBinding(group, action, device)
	if not raw then return "" end
	return KEY_TEXT[raw] or string.upper(raw)
end

-- Every KeyCode bound to an action (Controls.keyCodes when present).
function M.keyCodes(group: string, action: string, device: string?): { Enum.KeyCode }
	local c = M.controls()
	if typeof(c.keyCodes) == "function" then
		local ok, value = pcall(c.keyCodes, group, action, device or "keyboard")
		if ok and typeof(value) == "table" then return value end
	end
	local raw = rawBinding(group, action, device)
	if not raw then return {} end
	local ok, code = pcall(function() return (Enum.KeyCode :: any)[raw] end)
	return if ok and code then { code } else {}
end

function M.keyMatches(key: Enum.KeyCode, group: string, action: string): boolean
	for _, device in { "keyboard", "gamepad" } do
		for _, code in M.keyCodes(group, action, device) do
			if code == key then return true end
		end
	end
	return false
end

-- Roster input ("LP, RP", "df+RP", or already numeric "1,2") -> numeric notation ("1,2", "df+2").
local BUTTON_TOKENS: { [string]: string } = { LP = "1", RP = "2", LK = "3", RK = "4", TH = "1+3" }
function M.notationOf(input: string): string
	local c = M.controls()
	local s = input
	if typeof(c.notationOf) == "function" then
		local ok, value = pcall(c.notationOf, input)
		if ok and typeof(value) == "string" and value ~= "" then s = value end
	end
	-- Button names Controls did not convert (older rosters' "TH") still map to numbers.
	local n = c.notation or FALLBACK.notation
	local map = { LP = n.lp or "1", RP = n.rp or "2", LK = n.lk or "3", RK = n.rk or "4" }
	local out = string.gsub(s, "%u%u", function(token: string) return map[token] or BUTTON_TOKENS[token] or token end)
	return (string.gsub(out, "%s+", ""))
end

--------------------------------------------------------------------------------------------------------------------
-- Move notation tokens: "df+2" -> { dir df, plus, btn 2 }; "1,2" -> { btn 1, then, btn 2 }; prefixes kept as tags.
--------------------------------------------------------------------------------------------------------------------
M.ARROWS = { f = "→", b = "←", u = "↑", d = "↓", df = "↘", db = "↙", uf = "↗", ub = "↖", n = "★" } :: { [string]: string }
local TAG_WORDS: { [string]: string } = {
	ss = "SIDESTEP", SS = "SIDESTEP", dash = "DASH", ws = "RISING", WS = "RISING", fc = "CROUCHING", FC = "CROUCHING",
	hold = "HOLD", h = "HOLD", ["~"] = "→", qcf = "↓↘→", qcb = "↓↙←", TH = "THROW",
}
export type NotationToken = { kind: string, value: string }

function M.notationTokens(input: string): { NotationToken }
	-- "f,f+2" (out of a forward dash) reads as one double-tap: two forward arrows, not a two-step string.
	local s = (string.gsub(M.notationOf(input), "f,f%+", "ff+"))
	local tokens: { NotationToken } = {}
	local i = 1
	local n = #s
	while i <= n do
		local ch = string.sub(s, i, i)
		if ch == "," then
			table.insert(tokens, { kind = "then", value = "," })
			i += 1
		elseif ch == "+" then
			table.insert(tokens, { kind = "plus", value = "+" })
			i += 1
		elseif string.match(ch, "%d") then
			table.insert(tokens, { kind = "btn", value = ch })
			i += 1
		elseif string.match(ch, "%a") then
			local word = string.match(s, "^%a+", i) :: string
			i += #word
			local lower = string.lower(word)
			if M.ARROWS[lower] and #lower <= 2 then
				table.insert(tokens, { kind = "dir", value = lower })
			elseif lower == "dash" or lower == "ff" then
				table.insert(tokens, { kind = "dir", value = "f" }); table.insert(tokens, { kind = "dir", value = "f" })
			elseif TAG_WORDS[word] or TAG_WORDS[lower] then
				table.insert(tokens, { kind = "tag", value = TAG_WORDS[word] or TAG_WORDS[lower] })
			else
				-- Unknown multi-letter words: split into direction letters when they all are ("dbf"), else a tag.
				table.insert(tokens, { kind = "tag", value = string.upper(word) })
			end
		else
			i += 1
		end
	end
	return tokens
end

-- Plain-text notation ("↘ + 2", "1 › 2") for compact labels and tests.
function M.notationText(input: string): string
	local parts = {}
	for _, tok in M.notationTokens(input) do
		if tok.kind == "dir" then table.insert(parts, M.ARROWS[tok.value] or tok.value)
		elseif tok.kind == "btn" then table.insert(parts, tok.value)
		elseif tok.kind == "plus" then table.insert(parts, "+")
		elseif tok.kind == "then" then table.insert(parts, "›")
		else table.insert(parts, tok.value) end
	end
	return table.concat(parts, " ")
end

-- Keys to press for a roster input on a device: keyboard "S+D+I", "U, I"; gamepad "↘+Y" (Controls.formatMoveInput
-- when the module has it; otherwise built from the binding labels).
local DIR_ACTIONS: { [string]: { string } } = {
	f = { "forward" }, b = { "back" }, d = { "crouch" }, u = { "sidestepIn" }, df = { "crouch", "forward" }, db = { "crouch", "back" },
	uf = { "sidestepIn", "forward" }, ub = { "sidestepIn", "back" },
}
local BTN_ACTIONS: { [string]: string } = { ["1"] = "lp", ["2"] = "rp", ["3"] = "lk", ["4"] = "rk" }
function M.formatMoveInput(input: string, device: string?): string
	local dev = if device == "gamepad" then "gamepad" else "keyboard"
	input = (string.gsub(input, "%f[%u]TH%f[^%u]", "LP+LK"))
	local c = M.controls()
	if typeof(c.formatMoveInput) == "function" then
		local ok, value = pcall(c.formatMoveInput, input, dev)
		if ok and typeof(value) == "string" and value ~= "" then return value end
	end
	local out = ""
	for _, tok in M.notationTokens(input) do
		if tok.kind == "dir" then
			local keys = {}
			for _, a in DIR_ACTIONS[tok.value] or {} do table.insert(keys, M.keyLabel("fight", a, dev)) end
			out ..= (if #keys > 0 then table.concat(keys, "+") else (M.ARROWS[tok.value] or tok.value))
		elseif tok.kind == "btn" then
			local l = BTN_ACTIONS[tok.value] and M.keyLabel("fight", BTN_ACTIONS[tok.value], dev) or ""
			out ..= (if l ~= "" then l else tok.value)
		elseif tok.kind == "plus" then
			out ..= "+"
		elseif tok.kind == "then" then
			out ..= ", "
		else
			out ..= tok.value .. " "
		end
	end
	return out
end

-- Short generated move description from frame data (the roster has no prose; this keeps every moveset readable).
function M.moveDescription(move: any): string
	local bits = {}
	local height = typeof(move.height) == "string" and move.height or ""
	local tier = typeof(move.tier) == "string" and move.tier or ""
	local startup = typeof(move.startup) == "number" and move.startup or 0
	local onBlock = typeof(move.onBlock) == "number" and move.onBlock or 0
	if height == "Throw" then
		table.insert(bits, "Grab: beats guarding opponents")
		local w = move.breakWindow
		table.insert(bits, "break with " .. (if move.breakWith then tostring(move.breakWith) else "1 or 2") .. (if typeof(w) == "number" then " (" .. w .. "f)" else ""))
		return table.concat(bits, " · ")
	end
	local launch = move.onHit == "LAUNCH" or tier == "Launch"
	local knd = move.onHit == "KND"
	if launch then table.insert(bits, string.lower(height) .. " launcher")
	elseif knd then table.insert(bits, string.lower(height) .. " knockdown")
	elseif startup > 0 and startup <= 10 then table.insert(bits, "fast " .. string.lower(height) .. " poke")
	elseif tier == "Heavy" then table.insert(bits, "heavy " .. string.lower(height))
	else table.insert(bits, string.lower(height) .. " " .. (if move.chainFrom then "string follow-up" else "strike")) end
	if typeof(move.chainFrom) == "string" and not launch and not string.find(bits[1], "string", 1, true) then table.insert(bits, "string") end
	local props = move.props or {}
	if props.highCrush then table.insert(bits, "ducks highs") end
	if props.lowCrush then table.insert(bits, "hops lows") end
	if props.armor then table.insert(bits, "armored") end
	if props.parry then table.insert(bits, "parries") end
	if onBlock >= 0 then table.insert(bits, "safe (+" .. onBlock .. ")")
	elseif onBlock >= -9 then table.insert(bits, "safe (" .. onBlock .. ")")
	else table.insert(bits, "punishable (" .. onBlock .. ")") end
	local first = bits[1]
	bits[1] = string.upper(string.sub(first, 1, 1)) .. string.sub(first, 2)
	return table.concat(bits, " · ")
end

-- Four readable 0..1 attributes for the fighter select bars. Raw numbers come from the roster (move damage, walk and
-- dash speed, fastest startup, reach, health and weight) and are ranked against the whole cast, so the bars always
-- separate the six fighters whatever units the roster uses. REACH is the designer spacing (stats.preferredRange)
-- when the roster has it, else the longest threat range (range + advance); a move's own range alone is not reach
-- (step-in moves start short and travel).
local function rawAttributes(def: any): { number }
	local stats = def.stats or {}
	local total, count, reach, best, fastest = 0, 0, 0, 0, math.huge
	for _, key in def.moveOrder or {} do
		local mv = def.moves[key]
		if mv and mv.height ~= "Throw" then
			total += mv.damage or 0; count += 1
			reach = math.max(reach, (mv.range or 0) + (if typeof(mv.advance) == "number" then mv.advance else 0))
			best = math.max(best, mv.damage or 0)
			if typeof(mv.startup) == "number" and typeof(mv.chainFrom) ~= "string" then fastest = math.min(fastest, mv.startup) end
		end
	end
	local avg = if count > 0 then total / count else 10
	local walk = stats.walkSpeed or 10
	local dash = if typeof(stats.dashDistance) == "number" and typeof(stats.dashFrames) == "number" and stats.dashFrames > 0
		then stats.dashDistance / stats.dashFrames * 60 else (stats.dashSpeed or 24) * 0.25
	local quick = if fastest < math.huge then 1 / fastest else 0.1
	local guards = 0
	for _, key in def.moveOrder or {} do
		local props = def.moves[key] and def.moves[key].props
		if typeof(props) == "table" and (props.armor or props.parry) then guards += 1 end
	end
	if typeof(stats.preferredRange) == "number" then reach = stats.preferredRange end
	return {
		avg * 0.7 + best * 0.3,
		walk + (stats.backSpeed or walk * 0.8) * 0.5 + dash * 0.25 + quick * 40,
		reach,
		(stats.maxHealth or 100) + guards * 3,
	}
end
M.ATTRIBUTE_NAMES = { "POWER", "SPEED", "REACH", "DEFENSE" }
function M.attributes(def: any, roster: any?): { { name: string, value: number } }
	local mine = rawAttributes(def)
	local lows, highs = table.clone(mine), table.clone(mine)
	local cast = roster
	if cast == nil then
		local module = LabFolder:FindFirstChild("Roster")
		if module and module:IsA("ModuleScript") then
			local ok, result = pcall(require, module)
			if ok then cast = result end
		end
	end
	if typeof(cast) == "table" and typeof(cast.order) == "table" and typeof(cast.get) == "function" then
		for _, id in cast.order do
			local ok, other = pcall(cast.get, id)
			if ok and typeof(other) == "table" then
				for i, v in rawAttributes(other) do
					lows[i] = math.min(lows[i], v)
					highs[i] = math.max(highs[i], v)
				end
			end
		end
	end
	local out = {}
	for i, name in M.ATTRIBUTE_NAMES do
		local span = highs[i] - lows[i]
		local value = if span > 1e-6 then 0.3 + 0.65 * (mine[i] - lows[i]) / span else 0.6
		table.insert(out, { name = name, value = math.clamp(value, 0.12, 1) })
	end
	return out
end

--------------------------------------------------------------------------------------------------------------------
-- Input device + key glyphs
--------------------------------------------------------------------------------------------------------------------
-- "keyboard" | "gamepad" | "touch" from the last input (keyboard on servers/tests).
function M.inputDevice(): string
	if not RunService:IsClient() then return "keyboard" end
	local last = UserInputService:GetLastInputType()
	if string.sub(last.Name, 1, 7) == "Gamepad" then return "gamepad" end
	if last == Enum.UserInputType.Touch then return "touch" end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then return "touch" end
	return "keyboard"
end

-- Roblox's player list sits top right over full-screen overlays (and Tab, the menu key, also toggles it): the lobby
-- menu and the fighter select hold it hidden while open. Holds nest; the last release restores the saved state, or
-- `restoreTo` when the caller knows better (FightSession turns the list off in fights and practice, on in the lobby).
local playerListHolds = 0
local playerListSaved: boolean? = nil
function M.holdPlayerList(on: boolean, restoreTo: boolean?)
	if not RunService:IsClient() then return end
	local StarterGui = game:GetService("StarterGui")
	if on then
		playerListHolds += 1
		if playerListHolds == 1 then
			pcall(function()
				playerListSaved = StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.PlayerList)
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
			end)
		end
	elseif playerListHolds > 0 then
		playerListHolds -= 1
		if playerListHolds == 0 then
			local saved = if restoreTo ~= nil then restoreTo else playerListSaved
			playerListSaved = nil
			if saved ~= nil then pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, saved) end) end
		end
	end
end
function M.playerListHeld(): boolean return playerListHolds > 0 end

local FACE_COLORS: { [string]: Color3 } = {
	A = Color3.fromRGB(96, 214, 108), B = Color3.fromRGB(255, 90, 82), X = Color3.fromRGB(78, 156, 255), Y = Color3.fromRGB(255, 206, 64),
}
local PAD_PILLS: { [string]: boolean } = { LB = true, RB = true, LT = true, RT = true, MENU = true, VIEW = true, LS = true, RS = true, START = true, SELECT = true, L3 = true, R3 = true }
local ARROW_GLYPHS: { [string]: boolean } = { ["←"] = true, ["→"] = true, ["↑"] = true, ["↓"] = true }

-- A key glyph: keyboard key cap, gamepad face button (coloured ring), shoulder/menu pill or D-pad arrow tile.
-- opts: device ("keyboard"/"gamepad"), height (px), order, zindex. Structure: Key_<label> > Face > Label.
function M.glyph(parent: Instance, label: string, opts: { [string]: any }?): Frame
	local o = opts or {}
	local h = o.height or 22
	local z = o.zindex or 1
	local device = o.device or "keyboard"
	local face = device == "gamepad" and FACE_COLORS[label] ~= nil
	local pill = device == "gamepad" and PAD_PILLS[label] == true
	local width = if face then h else math.max(h, math.floor(#label * h * 0.42 + h * 0.66))
	if ARROW_GLYPHS[label] then width = h end
	local cap: any = M.make("Frame", { Name = "Key_" .. label, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromOffset(width, h), LayoutOrder = o.order or 0, ZIndex = z, Parent = parent })
	local top: any = M.make("Frame", { Name = "Face", BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = z + 1, Parent = cap })
	local textColor = M.Theme.ink
	if face then
		M.corner(top)
		top.BackgroundColor3 = Color3.fromRGB(18, 22, 30)
		M.outline(top, FACE_COLORS[label], math.max(1.5, h * 0.09), 0)
		textColor = FACE_COLORS[label]
	elseif pill then
		M.corner(top, math.floor(h * 0.5))
		top.BackgroundColor3 = Color3.fromRGB(46, 52, 66)
		M.outline(top, Color3.new(1, 1, 1), 1, 0.7)
		textColor = M.Theme.text
	else
		local radius = math.max(3, math.floor(h * 0.2))
		top.Size = UDim2.new(1, 0, 1, -2)
		M.corner(top, radius)
		M.gradient(top, M.Theme.key, Color3.fromRGB(200, 206, 220), 90)
		-- Key depth: a darker lip peeking out under the cap.
		local lip = M.make("Frame", { Name = "Lip", BackgroundColor3 = Color3.fromRGB(110, 118, 136), BorderSizePixel = 0, Position = UDim2.fromOffset(0, 2), Size = UDim2.new(1, 0, 1, -2), ZIndex = z, Parent = cap })
		M.corner(lip, radius)
	end
	local size = if #label <= 1 then math.floor(h * 0.64) elseif #label <= 3 then math.floor(h * 0.48) else math.floor(h * 0.42)
	if ARROW_GLYPHS[label] then size = math.floor(h * 0.7) end
	M.text(top, "Label", label, if face then M.Theme.number else M.Theme.heavy, size, textColor, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = z + 2 })
	return cap
end

-- Legacy key cap (keyboard look) kept for callers that pass a raw label.
function M.keyCap(parent: Instance, key: string, height: number?, order: number?): Frame
	return M.glyph(parent, key, { height = height, order = order, device = "keyboard" })
end

-- Row of glyphs for one action ("A" or "A / D"); returns the row frame.
function M.glyphRow(parent: Instance, labels: { string }, opts: { [string]: any }?): Frame
	local o = opts or {}
	local h = o.height or 22
	local row: any = M.make("Frame", { Name = o.name or "Keys", BackgroundTransparency = 1, Size = UDim2.fromOffset(0, h), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = o.order or 0, Parent = parent })
	M.list(row, true, o.gap or 4, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	for i, l in labels do
		if l ~= "" then
			if i > 1 and o.separator then
				M.text(row, "Sep" .. i, o.separator, M.Theme.heavy, math.floor(h * 0.6), o.sepColor or M.Theme.muted, { Size = UDim2.fromOffset(0, h), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = i * 2 - 1 })
			end
			M.glyph(row, l, { height = h, device = o.device, order = i * 2, zindex = o.zindex })
		end
	end
	return row
end

-- [glyph] caption hint used in footers and prompts.
function M.hint(parent: Instance, labels: { string }, caption: string, opts: { [string]: any }?): Frame
	local o = opts or {}
	local h = o.height or 22
	local row: any = M.make("Frame", { Name = o.name or ("Hint_" .. caption), BackgroundTransparency = 1, Size = UDim2.fromOffset(0, h), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = o.order or 0, Parent = parent })
	M.list(row, true, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	M.glyphRow(row, labels, { height = h, device = o.device, order = 1, separator = o.separator })
	M.text(row, "Caption", caption, o.font or M.Theme.heavy, o.textSize or math.floor(h * 0.62), o.color or M.Theme.text, { Size = UDim2.fromOffset(0, h), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2 })
	return row
end

-- Move notation chips: arrows in dark tiles, attack buttons as numbered rings, "+" and "›" between steps.
local BUTTON_COLORS: { [string]: Color3 } = {
	["1"] = Color3.fromRGB(255, 160, 96), ["2"] = Color3.fromRGB(255, 108, 80), ["3"] = Color3.fromRGB(96, 196, 255), ["4"] = Color3.fromRGB(150, 140, 255),
}
M.BUTTON_COLORS = BUTTON_COLORS
function M.notationRow(parent: Instance, input: string, opts: { [string]: any }?): Frame
	local o = opts or {}
	local h = o.height or 24
	local row: any = M.make("Frame", { Name = o.name or "Notation", BackgroundTransparency = 1, Size = UDim2.fromOffset(0, h), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = o.order or 0, Parent = parent })
	M.list(row, true, 3, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	for i, tok in M.notationTokens(input) do
		if tok.kind == "dir" then
			local tile = M.make("Frame", { Name = "Dir_" .. tok.value, BackgroundColor3 = Color3.fromRGB(38, 44, 58), BorderSizePixel = 0, Size = UDim2.fromOffset(h, h), LayoutOrder = i, Parent = row })
			M.corner(tile, 4)
			M.text(tile, "Arrow", M.ARROWS[tok.value] or tok.value, M.Theme.heavy, math.floor(h * 0.74), M.Theme.text, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
		elseif tok.kind == "btn" then
			local color = BUTTON_COLORS[tok.value] or M.Theme.text
			local ring = M.make("Frame", { Name = "Btn_" .. tok.value, BackgroundColor3 = Color3.fromRGB(16, 19, 27), BorderSizePixel = 0, Size = UDim2.fromOffset(h, h), LayoutOrder = i, Parent = row })
			M.corner(ring)
			M.outline(ring, color, math.max(1.5, h * 0.09), 0)
			M.text(ring, "Digit", tok.value, M.Theme.number, math.floor(h * 0.56), color, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
		elseif tok.kind == "plus" then
			M.text(row, "Plus" .. i, "+", M.Theme.heavy, math.floor(h * 0.62), M.Theme.muted, { Size = UDim2.fromOffset(math.floor(h * 0.45), h), TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = i })
		elseif tok.kind == "then" then
			M.text(row, "Then" .. i, "›", M.Theme.heavy, math.floor(h * 0.8), M.Theme.dim, { Size = UDim2.fromOffset(math.floor(h * 0.42), h), TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = i })
		else
			local chip = M.make("Frame", { Name = "Tag" .. i, BackgroundColor3 = Color3.fromRGB(52, 46, 70), BorderSizePixel = 0, Size = UDim2.fromOffset(0, h), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = i, Parent = row })
			M.corner(chip, 4)
			M.make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), Parent = chip })
			M.text(chip, "Text", tok.value, M.Theme.heavy, math.floor(h * 0.46), Color3.fromRGB(214, 200, 255), { Size = UDim2.fromOffset(0, h), AutomaticSize = Enum.AutomaticSize.X })
		end
	end
	return row
end

--------------------------------------------------------------------------------------------------------------------
-- Buttons: one look for every menu / picker / panel button, with hover, press and keyboard/gamepad focus states.
--------------------------------------------------------------------------------------------------------------------
export type Button = {
	button: TextButton, label: TextLabel, row: Frame, bar: Frame, stroke: UIStroke, scale: UIScale,
	setFocused: (on: boolean) -> (), setSelected: (on: boolean) -> (), setEnabled: (on: boolean) -> (), setAccent: (c: Color3) -> (),
	focused: boolean, selected: boolean, enabled: boolean,
}
-- opts: text, size, order, accent, primary (filled accent), font, textSize, align ("left"/"center"), glyphs ({labels}), device
function M.button(parent: Instance, name: string, opts: { [string]: any }?): Button
	local o = opts or {}
	local accent: Color3 = o.accent or M.Theme.ember
	local primary = o.primary == true
	local b: TextButton = M.make("TextButton", {
		Name = name, Text = "", AutoButtonColor = false, BackgroundColor3 = if primary then accent else M.Theme.panel2,
		BackgroundTransparency = if primary then 0 else 0.15, BorderSizePixel = 0, Size = o.size or UDim2.fromOffset(200, 44),
		LayoutOrder = o.order or 0, ClipsDescendants = false, Selectable = true, Parent = parent,
	})
	M.corner(b, 5)
	local stroke = M.outline(b, Color3.new(1, 1, 1), 1, if primary then 0.6 else 0.86)
	local scale: UIScale = M.make("UIScale", { Parent = b })
	local bar: Frame = M.make("Frame", { Name = "Bar", BackgroundColor3 = accent, BorderSizePixel = 0, Size = UDim2.new(0, 4, 1, 0), BackgroundTransparency = 1, Parent = b })
	M.corner(bar, 2)
	local row: Frame = M.make("Frame", { Name = "Row", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = b })
	local align = if o.align == "left" then Enum.HorizontalAlignment.Left else Enum.HorizontalAlignment.Center
	M.list(row, true, 8, align, Enum.VerticalAlignment.Center)
	if o.align == "left" then M.make("UIPadding", { PaddingLeft = UDim.new(0, 16), Parent = row }) end
	if o.glyphs and #o.glyphs > 0 then M.glyphRow(row, o.glyphs, { height = o.glyphHeight or 22, device = o.device, order = 1, separator = "/" }) end
	local label = M.text(row, "Label", o.text or name, o.font or M.Theme.heavy, o.textSize or 17, if primary then M.Theme.ink else M.Theme.text, { Size = UDim2.fromOffset(0, (o.textSize or 17) + 6), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2 })
	local ctl: Button
	local hovered = false
	local function paint()
		local active = ctl.focused or hovered
		if primary then
			b.BackgroundColor3 = if ctl.enabled then (if active then accent:Lerp(Color3.new(1, 1, 1), 0.18) else accent) else M.Theme.slot
			label.TextColor3 = if ctl.enabled then M.Theme.ink else M.Theme.dim
			stroke.Color = Color3.new(1, 1, 1)
			stroke.Transparency = if ctl.focused then 0 else 0.6
			stroke.Thickness = if ctl.focused then 2 else 1
		else
			b.BackgroundColor3 = if ctl.selected then accent:Lerp(M.Theme.panel2, 0.72) elseif active then M.Theme.panel2:Lerp(Color3.new(1, 1, 1), 0.08) else M.Theme.panel2
			bar.BackgroundTransparency = if ctl.selected or ctl.focused then 0 else 1
			stroke.Color = if ctl.focused then accent elseif ctl.selected then accent else Color3.new(1, 1, 1)
			stroke.Transparency = if ctl.focused then 0 elseif ctl.selected then 0.35 elseif hovered then 0.7 else 0.86
			stroke.Thickness = if ctl.focused then 2 else 1
			label.TextColor3 = if not ctl.enabled then M.Theme.dim elseif ctl.selected or active then M.Theme.text else Color3.fromRGB(214, 220, 232)
		end
		scale.Scale = if ctl.focused then 1.03 else 1
		b:SetAttribute("Selected", ctl.selected)
		b:SetAttribute("Focused", ctl.focused)
		b:SetAttribute("Enabled", ctl.enabled)
	end
	ctl = {
		button = b, label = label, row = row, bar = bar, stroke = stroke, scale = scale, focused = false, selected = false, enabled = true,
		setFocused = function(on: boolean) if ctl.focused ~= on then ctl.focused = on; paint() end end,
		setSelected = function(on: boolean) if ctl.selected ~= on then ctl.selected = on; paint() end end,
		setEnabled = function(on: boolean) if ctl.enabled ~= on then ctl.enabled = on; paint() end end,
		setAccent = function(c: Color3) accent = c; bar.BackgroundColor3 = c; if primary then b.BackgroundColor3 = c end; paint() end,
	}
	b.MouseEnter:Connect(function() hovered = true; paint() end)
	b.MouseLeave:Connect(function() hovered = false; paint() end)
	b.MouseButton1Down:Connect(function() scale.Scale = 0.97 end)
	b.MouseButton1Up:Connect(function() paint() end)
	paint()
	return ctl
end

-- Segmented 0..1 bar (attributes, volume): `segments` blocks, filled ones in `color`. Returns a setter.
function M.segmentBar(parent: Instance, name: string, segments: number, color: Color3, props: { [string]: any }?): (Frame, (value: number, animate: boolean?) -> (), (c: Color3) -> ())
	local frame: any = M.make("Frame", { Name = name, BackgroundTransparency = 1, Size = UDim2.fromOffset(240, 10), Parent = parent })
	if props then for k, v in props do frame[k] = v end end
	M.list(frame, true, 3, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	local blocks: { Frame } = {}
	for i = 1, segments do
		local block = M.make("Frame", { Name = "S" .. i, BackgroundColor3 = color, BackgroundTransparency = 0.82, BorderSizePixel = 0, Size = UDim2.new(1 / segments, -3, 1, 0), LayoutOrder = i, Parent = frame })
		M.corner(block, 1)
		blocks[i] = block
	end
	local current = -1
	local function set(value: number, animate: boolean?)
		local filled = math.clamp(math.floor(value * segments + 0.5), 0, segments)
		if filled == current then return end
		current = filled
		for i, block in blocks do
			local on = i <= filled
			local goal = { BackgroundTransparency = if on then 0 else 0.82 }
			if animate then
				task.delay((i - 1) * 0.018, function() if block.Parent then M.tween(block, 0.12, goal) end end)
			else
				block.BackgroundTransparency = goal.BackgroundTransparency
			end
		end
	end
	local function recolor(c: Color3) for _, block in blocks do block.BackgroundColor3 = c end end
	frame:SetAttribute("Segments", segments)
	return frame, function(value: number, animate: boolean?) set(value, animate) end, recolor
end

-- Monogram badge (accent square with the fighter's initial) used where a live portrait is not worth the cost.
function M.monogram(parent: Instance, def: any, size: number, props: { [string]: any }?): Frame
	local f: any = M.make("Frame", { Name = "Monogram", BackgroundColor3 = def.accentColor, BorderSizePixel = 0, Size = UDim2.fromOffset(size, size), Parent = parent })
	M.corner(f, math.floor(size * 0.12))
	M.gradient(f, def.accentColor, def.accentColor:Lerp(Color3.new(0, 0, 0), 0.55), 120)
	M.text(f, "Letter", string.sub(def.displayName, 1, 1), M.Theme.display, math.floor(size * 0.62), Color3.new(1, 1, 1), { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
	if props then for k, v in props do f[k] = v end end
	return f
end

return M
