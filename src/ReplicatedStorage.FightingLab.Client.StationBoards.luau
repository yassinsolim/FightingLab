--!strict
-- Arena status boards (OV5). Fills every arena's StatusBoard.StatusGui from the matching
-- ReplicatedStorage.FightingLab.Stations.<ArenaId> attributes and tags the pads with small BillboardGuis.
-- Each board's layout is built once; attribute changes only update properties (no per-frame rebuilds, no leaks).
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Client = script.Parent
local Lab = Client.Parent
local UIHelpers = require(Client.UIHelpers)
local Roster = require(Lab.Roster)

local T = UIHelpers.Theme
local make, text = UIHelpers.make, UIHelpers.text

local StationBoards = {}

export type SideView = {
	slot: number, occupied: boolean, cpu: boolean, name: string, fighter: string, fighterColor: Color3,
	health: number, rounds: number, winner: boolean, loser: boolean,
}
export type View = {
	kind: string, state: string, title: string, badge: string, badgeColor: Color3, headline: string, footer: string,
	center: string, centerSub: string, live: boolean, digit: number?, difficulty: string, p1: SideView, p2: SideView,
}

local SIDE_COLOR = { [1] = T.warm, [2] = T.cool }

local function str(v: any, default: string): string return if typeof(v) == "string" and v ~= "" then v else default end
local function num(v: any, default: number): number return if typeof(v) == "number" and v == v then v else default end

local function sideView(attrs: { [string]: any }, slot: number, state: string, winnerSlot: number): SideView
	local prefix = "P" .. slot
	local userId = num(attrs[prefix .. "UserId"], 0)
	local cpu = userId == -1
	local rawName = str(attrs[prefix .. "Name"], "")
	local occupied = userId ~= 0 or rawName ~= ""
	local def = UIHelpers.fighterDef(Roster, attrs[prefix .. "Fighter"])
	local name = if rawName ~= "" then rawName elseif cpu then "CPU" else "OPEN"
	return {
		slot = slot,
		occupied = occupied,
		cpu = cpu,
		name = if occupied then name else "OPEN",
		fighter = if def and occupied then def.displayName else "",
		fighterColor = if def then def.accentColor else T.muted,
		health = math.clamp(num(attrs[prefix .. "Health"], 1), 0, 1),
		rounds = math.clamp(math.floor(num(attrs[prefix .. "Rounds"], 0)), 0, 2),
		winner = state == "Results" and winnerSlot == slot,
		loser = state == "Results" and winnerSlot ~= 0 and winnerSlot ~= slot,
	}
end

-- Pure view model for one station (also used by tests and the pad tags).
function StationBoards.viewModel(attrs: { [string]: any }, now: number): View
	local kind = str(attrs.Kind, "Duel")
	local state = str(attrs.State, "Open")
	local title = string.upper(str(attrs.DisplayName, str(attrs.ArenaId, "Arena")))
	local winnerSlot = math.floor(num(attrs.WinnerSlot, 0))
	local p1 = sideView(attrs, 1, state, winnerSlot)
	local p2 = sideView(attrs, 2, state, winnerSlot)
	local view: View = {
		kind = kind, state = state, title = title, badge = "OPEN", badgeColor = T.ok, headline = "OPEN",
		footer = "Step on a glowing circle to duel", center = "VS", centerSub = "", live = false, digit = nil,
		difficulty = if attrs.Cpu == true or p1.cpu or p2.cpu then str(attrs.Difficulty, "") else "", p1 = p1, p2 = p2,
	}
	if kind == "Practice" then
		view.badge = "PRACTICE"; view.badgeColor = T.cool
		view.headline = "PRACTICE DOJO"
		view.center = "DOJO"; view.centerSub = ""
		local users = {}
		if p1.occupied then table.insert(users, p1.name) end
		if p2.occupied then table.insert(users, p2.name) end
		view.footer = if #users > 0 and state ~= "Open" then "In use by " .. table.concat(users, " & ") else "Step on a pad and press " .. (UIHelpers.keyLabel("lobby", "interact") ~= "" and UIHelpers.keyLabel("lobby", "interact") or "E") .. ": training, lessons or a CPU match"
		return view
	end
	if state == "Waiting" then
		view.badge = "WAITING"; view.badgeColor = T.gold
		view.headline = "WAITING FOR CHALLENGER"
		view.footer = "Step on the " .. (if p1.occupied and not p2.occupied then "P2" else "P1") .. " circle to accept the duel"
	elseif state == "Countdown" then
		view.badge = "STARTING"; view.badgeColor = T.gold
		local digit = UIHelpers.countdownDigit(attrs.CountdownEndsAt, now)
		view.digit = digit
		view.center = if digit and digit > 0 then tostring(digit) else "GO"
		view.centerSub = "GET READY"
		view.headline = "DUEL STARTING"
		view.footer = "Stepping off a circle cancels the countdown"
	elseif state == "Fighting" then
		view.badge = "LIVE"; view.badgeColor = T.live; view.live = true
		view.center = UIHelpers.formatSeconds(attrs.Timer)
		view.centerSub = "ROUND " .. tostring(math.max(1, math.floor(num(attrs.Round, 1))))
		view.headline = "LIVE DUEL"
		view.footer = if attrs.Cpu == true or p1.cpu or p2.cpu then "Best of 3  ·  CPU " .. string.upper(str(attrs.Difficulty, "Normal")) else "Best of 3 rounds"
	elseif state == "Results" then
		view.badge = "RESULT"; view.badgeColor = T.win
		local winner = if winnerSlot == 1 then p1 elseif winnerSlot == 2 then p2 else nil
		-- Short centre mark ("P1" over "WINS") so long names on both sides never crowd it.
		view.center = if winner then "P" .. winner.slot else "DRAW"
		view.centerSub = if winner then "WINS" else ""
		view.headline = if winner then string.upper(winner.name) .. " WINS" else "DRAW"
		view.footer = str(attrs.ResultText, if winner then winner.name .. " wins the duel" else "No winner this time")
	else
		view.state = "Open"
		view.headline = "OPEN"
		view.footer = "Open — step on a glowing circle to duel"
	end
	return view
end

--------------------------------------------------------------------------------------------------------------------
-- Board layout (built once per StatusGui)
--------------------------------------------------------------------------------------------------------------------
type SideRefs = { col: Frame, slot: TextLabel, name: TextLabel, fighter: TextLabel, bar: Frame, fill: Frame, pips: { Frame }, tag: TextLabel, tint: Frame }
export type Board = {
	root: Frame, title: TextLabel, badge: Frame, badgeText: TextLabel, badgeDot: Frame, center: TextLabel, centerSub: TextLabel,
	headline: TextLabel, footer: TextLabel, sides: { SideRefs }, dotTween: Tween?, lastState: string, lastHealth: { number },
}

local function scaledText(parent: Instance, name: string, font: Font, color: Color3, pos: UDim2, size: UDim2, align: Enum.TextXAlignment, maxSize: number?): TextLabel
	local label = text(parent, name, "", font, 24, color, { Position = pos, Size = size, TextScaled = true, TextXAlignment = align, TextYAlignment = Enum.TextYAlignment.Center })
	make("UITextSizeConstraint", { MaxTextSize = maxSize or 100, MinTextSize = 6, Parent = label })
	return label
end

local function buildSide(content: Frame, slot: number): SideRefs
	local right = slot == 2
	local color = SIDE_COLOR[slot]
	local align = if right then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left
	local x = if right then 0.6 else 0.04
	local tint = make("Frame", { Name = "Tint" .. slot, BackgroundColor3 = color, BackgroundTransparency = 0, BorderSizePixel = 0, Position = UDim2.fromScale(if right then 0.5 else 0, 0.215), Size = UDim2.fromScale(0.5, 0.56), ZIndex = 1, Parent = content })
	UIHelpers.gradient(tint, color, color, if right then 180 else 0, NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 1) }))
	local col = make("Frame", { Name = "P" .. slot, BackgroundTransparency = 1, Position = UDim2.fromScale(x, 0.22), Size = UDim2.fromScale(0.36, 0.56), ZIndex = 2, Parent = content })
	local slotLabel = scaledText(col, "Slot", T.heavy, color, UDim2.fromScale(0, 0.02), UDim2.fromScale(1, 0.13), align)
	slotLabel.Text = "P" .. slot .. (if right then "  ·  BLUE" else "  ·  ORANGE")
	local name = scaledText(col, "Name", T.display, T.text, UDim2.fromScale(0, 0.17), UDim2.fromScale(1, 0.3), align)
	local fighter = scaledText(col, "Fighter", T.heavy, T.muted, UDim2.fromScale(0, 0.48), UDim2.fromScale(1, 0.14), align)
	local bar = make("Frame", { Name = "Health", BackgroundColor3 = Color3.fromRGB(34, 40, 60), BorderSizePixel = 0, Position = UDim2.fromScale(0, 0.69), Size = UDim2.fromScale(1, 0.1), Parent = col })
	UIHelpers.corner(bar, 6)
	local fill = make("Frame", { Name = "Fill", BackgroundColor3 = color, BorderSizePixel = 0, AnchorPoint = Vector2.new(if right then 1 else 0, 0), Position = UDim2.fromScale(if right then 1 else 0, 0), Size = UDim2.fromScale(1, 1), Parent = bar })
	UIHelpers.corner(fill, 6)
	UIHelpers.gradient(fill, Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190), 90)
	local pipRow = make("Frame", { Name = "Pips", BackgroundTransparency = 1, Position = UDim2.fromScale(0, 0.84), Size = UDim2.fromScale(1, 0.09), Parent = col })
	local pips = {}
	for i = 1, 2 do
		local px = if right then 1 - i * 0.13 else (i - 1) * 0.13
		local pip = make("Frame", { Name = "Pip" .. i, BackgroundColor3 = Color3.fromRGB(46, 52, 74), BorderSizePixel = 0, Position = UDim2.fromScale(px, 0), Size = UDim2.fromScale(0.11, 1), Parent = pipRow })
		UIHelpers.corner(pip, 4)
		UIHelpers.outline(pip, T.gold, 1, 0.35)
		table.insert(pips, pip)
	end
	local tag = scaledText(col, "WinnerTag", T.heavy, T.ink, UDim2.fromScale(if right then 0.62 else 0, 0.69), UDim2.fromScale(0.38, 0.13), Enum.TextXAlignment.Center)
	tag.Text = "WINNER"; tag.BackgroundTransparency = 0; tag.BackgroundColor3 = T.win; tag.Visible = false
	UIHelpers.corner(tag, 6)
	return { col = col, slot = slotLabel, name = name, fighter = fighter, bar = bar, fill = fill, pips = pips, tag = tag, tint = tint }
end

-- Builds the board layout under a SurfaceGui (replacing an earlier FightingLab board there).
function StationBoards.build(surfaceGui: Instance): Board
	local old = surfaceGui:FindFirstChild("FightingLabBoard")
	if old then old:Destroy() end
	local root = make("Frame", { Name = "FightingLabBoard", BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) })
	UIHelpers.gradient(root, Color3.fromRGB(22, 26, 36), Color3.fromRGB(6, 7, 11), 90)
	local content = make("Frame", { Name = "Content", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), Parent = root })
	make("UIAspectRatioConstraint", { AspectRatio = 16 / 9, Parent = content })
	local header = make("Frame", { Name = "Header", BackgroundColor3 = Color3.fromRGB(4, 5, 8), BackgroundTransparency = 0.1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 0.19), Parent = content })
	local accent = make("Frame", { Name = "Accent", BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0.035, 0), Parent = header })
	make("UIGradient", { Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, T.warm), ColorSequenceKeypoint.new(0.5, T.ember), ColorSequenceKeypoint.new(1, T.cool) }), Parent = accent })
	local title = scaledText(header, "Title", T.display, T.text, UDim2.fromScale(0.035, 0.12), UDim2.fromScale(0.6, 0.72), Enum.TextXAlignment.Left)
	local badge = make("Frame", { Name = "Badge", BackgroundColor3 = T.ok, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(0.965, 0.47), Size = UDim2.fromScale(0.25, 0.56), Parent = header })
	UIHelpers.corner(badge, 6)
	local badgeDot = make("Frame", { Name = "Dot", BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0.08, 0.5), Size = UDim2.fromScale(0.09, 0.36), Parent = badge })
	make("UIAspectRatioConstraint", { AspectRatio = 1, Parent = badgeDot })
	UIHelpers.corner(badgeDot)
	local badgeText = scaledText(badge, "Text", T.heavy, T.ink, UDim2.fromScale(0.22, 0.14), UDim2.fromScale(0.72, 0.72), Enum.TextXAlignment.Center)
	local sides = { buildSide(content, 1), buildSide(content, 2) }
	local center = scaledText(content, "Center", T.display, T.gold, UDim2.fromScale(0.4, 0.27), UDim2.fromScale(0.2, 0.3), Enum.TextXAlignment.Center)
	center.ZIndex = 3
	local centerSub = scaledText(content, "CenterSub", T.heavy, T.muted, UDim2.fromScale(0.4, 0.58), UDim2.fromScale(0.2, 0.08), Enum.TextXAlignment.Center)
	centerSub.ZIndex = 3
	local footerBar = make("Frame", { Name = "FooterBar", BackgroundColor3 = Color3.fromRGB(4, 5, 8), BackgroundTransparency = 0.12, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0.18), Parent = content })
	local headline = scaledText(footerBar, "Headline", T.heavy, T.gold, UDim2.fromScale(0.035, 0.1), UDim2.fromScale(0.93, 0.42), Enum.TextXAlignment.Center)
	local footer = scaledText(footerBar, "Footer", T.medium, T.text, UDim2.fromScale(0.035, 0.52), UDim2.fromScale(0.93, 0.36), Enum.TextXAlignment.Center)
	root.Parent = surfaceGui
	return { root = root, title = title, badge = badge, badgeText = badgeText, badgeDot = badgeDot, center = center, centerSub = centerSub, headline = headline, footer = footer, sides = sides, dotTween = nil, lastState = "", lastHealth = { 1, 1 } }
end

-- Applies a view to a built board: property updates only.
function StationBoards.render(board: Board, view: View)
	board.title.Text = view.title
	board.badge.BackgroundColor3 = view.badgeColor
	board.badgeText.Text = view.badge
	board.center.Text = view.center
	board.centerSub.Text = view.centerSub
	board.headline.Text = view.headline
	board.footer.Text = view.footer
	board.center.TextColor3 = if view.state == "Results" then T.win elseif view.live then T.text else T.gold
	local practice = view.kind == "Practice"
	for slot, refs in board.sides do
		local side = if slot == 1 then view.p1 else view.p2
		local fighting = view.state == "Fighting" or view.state == "Results"
		if practice then
			refs.slot.Text = if slot == 1 then "PAD 1" else "PAD 2"
			refs.name.Text = if slot == 1 then "TRAINING" else "VERSUS CPU"
			refs.fighter.Text = if slot == 1 then "Dummy · guided lesson · resets" else "Easy · Normal · Hard"
			refs.fighter.TextColor3 = T.muted
		else
			-- Named after the circle colours players see (world: PadP1 orange, PadP2 cyan).
			local sideName = if slot == 2 then "BLUE" else "ORANGE"
			refs.slot.Text = "P" .. slot .. "  ·  " .. (if side.cpu and view.difficulty ~= "" then "CPU " .. string.upper(view.difficulty) else sideName)
			refs.name.Text = if side.occupied then string.upper(side.name) else "OPEN"
			refs.fighter.Text = if side.occupied and side.fighter ~= "" then side.fighter else (if side.occupied then "" else "STEP ON THE CIRCLE")
			refs.fighter.TextColor3 = if side.occupied and side.fighter ~= "" then side.fighterColor else T.dim
		end
		refs.name.TextColor3 = if side.winner then T.win elseif side.occupied or practice then T.text else T.dim
		local dim = side.loser
		refs.name.TextTransparency = if dim then 0.45 else 0
		refs.fighter.TextTransparency = if dim then 0.45 else 0
		-- Results replace the health bar with the WINNER tag; round pips stay.
		refs.bar.Visible = view.state == "Fighting" and not practice
		refs.tag.Visible = side.winner and not practice
		refs.tint.BackgroundTransparency = if side.occupied or practice then 0 else 0.6
		for i, pip in refs.pips do
			pip.Visible = fighting and not practice
			pip.BackgroundColor3 = if side.rounds >= i then T.gold else Color3.fromRGB(46, 52, 74)
		end
		if refs.bar.Visible then
			local target = UDim2.fromScale(side.health, 1)
			if board.lastHealth[slot] ~= side.health then
				board.lastHealth[slot] = side.health
				UIHelpers.tween(refs.fill, 0.2, { Size = target })
			end
		else
			board.lastHealth[slot] = 1
			refs.fill.Size = UDim2.fromScale(1, 1)
		end
	end
	if view.live ~= (board.dotTween ~= nil) then
		if view.live then
			board.badgeDot.BackgroundTransparency = 0
			local tween = TweenService:Create(board.badgeDot, TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { BackgroundTransparency = 0.75 })
			board.dotTween = tween
			tween:Play()
		else
			local tween = board.dotTween
			if tween then tween:Cancel() end
			board.dotTween = nil
			board.badgeDot.BackgroundTransparency = 0
		end
	end
	board.lastState = view.state
end

--------------------------------------------------------------------------------------------------------------------
-- Pad tags (BillboardGui above each pad)
--------------------------------------------------------------------------------------------------------------------
export type PadTag = { gui: BillboardGui, chip: Frame, chipText: TextLabel, name: TextLabel, sub: TextLabel, slot: number, mode: string? }

function StationBoards.buildPadTag(pad: BasePart, slot: number, parent: Instance, practiceMode: string?): PadTag
	local color = if practiceMode == "Cpu" then T.warm elseif practiceMode == "Training" then T.cool else SIDE_COLOR[slot] or T.gold
	local padColor = pad:GetAttribute("PadColor")
	if typeof(padColor) == "Color3" then color = padColor end
	local gui = make("BillboardGui", {
		Name = "PadTag_" .. pad.Name, Adornee = pad, Size = UDim2.fromScale(7.2, 2.05),
		-- StudsOffsetWorldSpace follows the adornee's rotation (pads are rotated cylinders): convert world up into it.
		-- 8.4 studs keeps the tag clear above the head of the fighter standing on the circle.
		StudsOffsetWorldSpace = pad.CFrame:VectorToObjectSpace(Vector3.new(0, 8.4, 0)),
		-- 100 studs: every pad reads from anywhere in the plaza (pads sit ~57 from its centre in the compact ring, the
		-- camera trails ~12 behind), while far stages drop out. During the local player's own fight every tag is hidden
		-- (StationBoards.start / setFocusArena), so none floats in the fight's background.
		LightInfluence = 0, MaxDistance = 100, AlwaysOnTop = false, ResetOnSpawn = false, ClipsDescendants = false,
	})
	local pill = make("Frame", { Name = "Pill", BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.06, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = gui })
	UIHelpers.gradient(pill, Color3.fromRGB(26, 30, 42), Color3.fromRGB(6, 7, 11), 90)
	UIHelpers.corner(pill, 8)
	UIHelpers.outline(pill, color, 2, 0.1)
	local chip = make("Frame", { Name = "Chip", BackgroundColor3 = color, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0.035, 0.5), Size = UDim2.fromScale(0.2, 0.7), Parent = pill })
	UIHelpers.corner(chip, 5)
	local chipText = scaledText(chip, "Text", T.display, T.ink, UDim2.fromScale(0.08, 0.1), UDim2.fromScale(0.84, 0.8), Enum.TextXAlignment.Center)
	local name = scaledText(pill, "Name", T.display, T.text, UDim2.fromScale(0.27, 0.08), UDim2.fromScale(0.7, 0.5), Enum.TextXAlignment.Left)
	local sub = scaledText(pill, "Sub", T.heavy, T.muted, UDim2.fromScale(0.27, 0.56), UDim2.fromScale(0.7, 0.32), Enum.TextXAlignment.Left)
	gui.Parent = parent
	return { gui = gui, chip = chip, chipText = chipText, name = name, sub = sub, slot = slot, mode = practiceMode }
end

function StationBoards.renderPadTag(tag: PadTag, view: View)
	if tag.mode then
		tag.chipText.Text = if tag.mode == "Cpu" then "CPU" else "DOJO"
		tag.name.Text = if tag.mode == "Cpu" then "VERSUS CPU" else "TRAINING"
		local key = UIHelpers.keyLabel("lobby", "interact")
		tag.sub.Text = "STEP IN · PRESS " .. (if key ~= "" then key else "E")
		return
	end
	local side = if tag.slot == 1 then view.p1 else view.p2
	tag.chipText.Text = "P" .. tag.slot
	if side.occupied then
		tag.name.Text = string.upper(side.name)
		tag.sub.Text = if view.state == "Fighting" then "FIGHTING NOW" elseif side.winner then "WINNER" elseif side.fighter ~= "" then side.fighter else "READY"
		tag.sub.TextColor3 = if side.winner then T.win elseif side.fighter ~= "" then side.fighterColor else T.muted
	else
		tag.name.Text = "OPEN"
		tag.sub.Text = if view.state == "Waiting" then "CHALLENGER WANTED" else "STEP IN TO DUEL"
		tag.sub.TextColor3 = if view.state == "Waiting" then T.gold else T.muted
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Live binding
--------------------------------------------------------------------------------------------------------------------
export type Binding = {
	board: Board, tags: { PadTag }, refresh: (now: number?) -> (), destroy: () -> (), arena: Instance, station: Instance?, dirty: boolean, view: View?,
	surface: SurfaceGui, hidden: boolean, tagsHidden: boolean, setHidden: (on: boolean) -> (), setTagsHidden: (on: boolean) -> (),
}

local function arenaAttributes(arena: Instance, station: Instance?): { [string]: any }
	local attrs: { [string]: any } = if station then station:GetAttributes() else {}
	if attrs.DisplayName == nil then attrs.DisplayName = arena:GetAttribute("DisplayName") end
	if attrs.Kind == nil then attrs.Kind = arena:GetAttribute("Kind") end
	if attrs.ArenaId == nil then attrs.ArenaId = arena.Name end
	return attrs
end

-- Binds one arena model (StatusBoard.StatusGui + pads) to its station. Returns nil when the arena has no StatusGui.
function StationBoards.bind(arena: Instance, station: Instance?, tagParent: Instance?, serverNow: (() -> number)?): Binding?
	local boardPart = arena:FindFirstChild("StatusBoard")
	local surface = boardPart and boardPart:FindFirstChild("StatusGui")
	if not surface or not surface:IsA("SurfaceGui") then return nil end
	local now = serverNow or function() return workspace:GetServerTimeNow() end
	local board = StationBoards.build(surface)
	local tags: { PadTag } = {}
	if tagParent then
		local kind = arena:GetAttribute("Kind")
		local padNames = if kind == "Practice" then { { "PadTraining", 1, "Training" }, { "PadCpu", 2, "Cpu" } } else { { "PadP1", 1, nil }, { "PadP2", 2, nil } }
		for _, spec in padNames do
			local pad = arena:FindFirstChild(spec[1] :: string)
			if pad and pad:IsA("BasePart") then
				local mode = pad:GetAttribute("PadMode")
				table.insert(tags, StationBoards.buildPadTag(pad, spec[2] :: number, tagParent, if typeof(mode) == "string" then mode else spec[3] :: string?))
			end
		end
	end
	local conns: { RBXScriptConnection } = {}
	local savedEnabled = surface.Enabled
	local binding: Binding
	local function paintTags()
		for _, tag in tags do tag.gui.Enabled = not (binding.hidden or binding.tagsHidden) end
	end
	binding = {
		board = board, tags = tags, arena = arena, station = station, dirty = true, view = nil, surface = surface, hidden = false, tagsHidden = false,
		-- Local-only: hides this arena's StatusGui and pad tags (the local player's own fight camera looks at them).
		setHidden = function(on: boolean)
			if on == binding.hidden then return end
			binding.hidden = on
			if on then
				savedEnabled = surface.Enabled
				surface.Enabled = false
			else
				surface.Enabled = savedEnabled
			end
			paintTags()
		end,
		-- Local-only: hides just the floating pad tags (every arena's, while the local player fights or practises).
		setTagsHidden = function(on: boolean)
			if on == binding.tagsHidden then return end
			binding.tagsHidden = on
			paintTags()
		end,
		refresh = function(at: number?)
			local view = StationBoards.viewModel(arenaAttributes(arena, station), at or now())
			binding.view = view
			binding.dirty = false
			StationBoards.render(board, view)
			for _, tag in tags do StationBoards.renderPadTag(tag, view) end
		end,
		destroy = function()
			if binding.hidden then binding.setHidden(false) end
			binding.tagsHidden = false
			for _, c in conns do c:Disconnect() end
			table.clear(conns)
			local tween = board.dotTween
			if tween then tween:Cancel() end
			board.root:Destroy()
			for _, tag in tags do tag.gui:Destroy() end
			table.clear(tags)
		end,
	}
	if station then table.insert(conns, station.AttributeChanged:Connect(function() binding.dirty = true end)) end
	table.insert(conns, arena.AttributeChanged:Connect(function() binding.dirty = true end))
	binding.refresh()
	return binding
end

export type Controller = { stop: () -> (), bindings: () -> { Binding }, refreshAll: () -> (), setFocusArena: (arenaId: string?) -> (), focusArena: () -> string? }
export type StartOptions = { world: () -> Instance?, stations: () -> Instance?, tagParent: Instance, serverNow: (() -> number)? }

-- Live wiring: binds every arena under <world>.Arenas, rebinding as arenas or stations appear. Dirty boards are
-- re-rendered at most 10 times a second; countdown boards tick on their own.
function StationBoards.start(options: StartOptions): Controller
	local bindings: { [Instance]: Binding } = {}
	local conns: { RBXScriptConnection } = {}
	local watched: { [Instance]: boolean } = {}
	local stopped = false
	local focusArena: string? = nil
	local serverNow = options.serverNow or function() return workspace:GetServerTimeNow() end

	local function stationFor(arena: Instance): Instance?
		local folder = options.stations()
		return folder and folder:FindFirstChild(arena.Name) or nil
	end
	local function ensure(arena: Instance)
		if stopped or not arena:IsA("Model") then return end
		local existing = bindings[arena]
		local station = stationFor(arena)
		if existing and existing.station == station then return end
		if existing then existing.destroy(); bindings[arena] = nil end
		local binding = StationBoards.bind(arena, station, options.tagParent, serverNow)
		if binding then
			bindings[arena] = binding
			binding.setHidden(arena.Name == focusArena)
			binding.setTagsHidden(focusArena ~= nil)
		end
	end
	local function drop(arena: Instance)
		local existing = bindings[arena]
		if existing then existing.destroy(); bindings[arena] = nil end
	end
	local function scan()
		local world = options.world()
		local arenas = world and world:FindFirstChild("Arenas")
		if arenas and not watched[arenas] then
			watched[arenas] = true
			table.insert(conns, arenas.ChildAdded:Connect(function(child) task.defer(ensure, child) end))
			table.insert(conns, arenas.ChildRemoved:Connect(drop))
		end
		local stations = options.stations()
		if stations and not watched[stations] then
			watched[stations] = true
			table.insert(conns, stations.ChildAdded:Connect(function(child)
				local folder = options.world()
				local arenaFolder = folder and folder:FindFirstChild("Arenas")
				local arena = arenaFolder and arenaFolder:FindFirstChild(child.Name)
				if arena then task.defer(ensure, arena) end
			end))
		end
		if arenas then for _, arena in arenas:GetChildren() do ensure(arena) end end
		for arena, binding in bindings do
			if not arena.Parent or not binding.board.root.Parent then drop(arena) end
		end
	end

	local accumulator, rescan = 0, 0
	table.insert(conns, RunService.Heartbeat:Connect(function(dt)
		accumulator += dt; rescan += dt
		if rescan >= 1 then rescan = 0; scan() end
		if accumulator < 0.1 then return end
		accumulator = 0
		local now = serverNow()
		for _, binding in bindings do
			local view = binding.view
			if binding.dirty or (view and view.state == "Countdown") then binding.refresh(now) end
		end
	end))
	scan()

	return {
		stop = function()
			stopped = true
			for _, c in conns do c:Disconnect() end
			table.clear(conns)
			for arena in bindings do drop(arena) end
		end,
		bindings = function()
			local list = {}
			for _, b in bindings do table.insert(list, b) end
			return list
		end,
		refreshAll = function() for _, b in bindings do b.refresh() end end,
		-- The arena the local player is fighting or practising in: its StatusGui and pad tags would sit behind the fight
		-- HUD in the fight camera, so they are hidden locally until the fight ends. The floating pad tags of every
		-- other arena hide too (the compact ring puts them in the fight's background); their physical boards stay live.
		setFocusArena = function(arenaId: string?)
			if focusArena == arenaId then return end
			focusArena = arenaId
			for arena, b in bindings do
				b.setHidden(arena.Name == arenaId)
				b.setTagsHidden(arenaId ~= nil)
			end
		end,
		focusArena = function() return focusArena end,
	}
end

return StationBoards
