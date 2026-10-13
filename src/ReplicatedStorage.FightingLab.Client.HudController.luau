--!strict
-- FightingLab fight HUD (OV6, round 6 restyle). The game's own "Ember & Steel" layout: angled health bars (a
-- parallelogram per side, leaning toward the clock) with a recent-damage trail that holds then drains, 10 % ticks and a
-- gloss line; live bust portraits on slanted cards; nameplates (fighter, player, YOU / CPU tag) under the bars; a
-- trapezoid clock plate with the round under it and slanted round pips; a combo counter with total damage on the
-- attacker's side; call-outs (COUNTER HIT, PUNISH, LAUNCH, THROW ESCAPE, SURGE...); the round intro, K.O. / TIME /
-- PERFECT and the winner presentation (HudBanners); and the on-screen controls guide built from FightingLab.Controls
-- (G toggles it through InputController -> toggleGuide; it opens by itself in the first fight and first practice per
-- session when the ControlsGuide setting is "Auto"). The local fighter is always drawn on the left (setViewSlot).
--
-- Contract A (Surge / Ultimate): a fighter with `surge = true` in the snapshot gets a molten bar with a pulsing aura and
-- a SURGE tag; `surge and not ultUsed` shows the ULTIMATE indicator with its key from Controls (fight "ultimate"; the
-- notation "1+2" when the key is unknown; no key on touch); an UltStart event shows the Ultimate title card (fighter
-- name + Roster.get(id).moves.Ultimate.name, "ULTIMATE" when missing) and letterbox bars stay while a fighter is in
-- state "Ultimate". Without those fields (a build without the Ultimate) nothing of it shows and nothing errors.
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local UIHelpers = require(script.Parent.UIHelpers)
local HudKit = require(script.Parent.HudKit)
local HudBanners = require(script.Parent.HudBanners)
local AvatarGate = require(script.Parent:WaitForChild("AvatarGate"))
local NetProtocol = require(script.Parent.Parent:WaitForChild("NetProtocol"))
type Ctx = any; type RenderFrame = any; type CombatEvent = any
type PortraitEntry = { model: Model, pivot: CFrame, cameraCFrame: CFrame, fov: number, facingDot: number, ready: boolean }
type Bar = {
	group: Frame, bar: HudKit.HealthBar, portrait: ViewportFrame, portraitStroke: UIStroke, card: Frame, name: TextLabel, tag: TextLabel,
	tagPlate: Frame, player: TextLabel, pips: { Frame }, edge: Frame, color: Color3, right: boolean, surgeChip: HudKit.Chip,
	ultChip: Frame, ultKey: Frame, ultText: TextLabel, status: Frame,
}
local T = UIHelpers.Theme
local make, text = UIHelpers.make, UIHelpers.text
local WHITE = Color3.new(1, 1, 1)
local SURGE_RED = Color3.fromRGB(255, 52, 84)
local ULT_GOLD = Color3.fromRGB(255, 205, 82)

local M = {}
M.GUIDE_AUTO_SECONDS = 14 -- an auto-opened guide folds back to its hint chip after this long
M.TRAIL_HOLD = 0.45 -- the recent-damage trail holds this long after a hit, then drains
local ctx: Ctx? = nil
local gui: ScreenGui? = nil
local root: Frame? = nil
local stage: Frame? = nil
local bars: { Bar } = {}
local banners: HudBanners.Banners? = nil
-- Per screen side: portrait clones by fighter id, kept parented in that side's WorldModel for the whole session.
local portraitCache: { { [string]: PortraitEntry } } = { {}, {} }
local PORTRAIT_PARKED = CFrame.new(0, -500, 0)
local PORTRAIT_SETTLE = 0.2
local refs: { [string]: any } = {}
local inputHistory: { string } = {}
local portraitIds: { [number]: string } = {}
local hudVisible = false
local debugShown = false
local health = { 100, 100 }
local maxHealth = { 100, 100 }
local trails: { HudKit.TrailState } = { { value = 100, holdUntil = 0 }, { value = 100, holdUntil = 0 } }
-- Contract A per screen side (nil = the snapshot carries no such field).
local surge: { [number]: boolean? } = {}
local ultUsed: { [number]: boolean? } = {}
local inUltimate: { [number]: boolean } = {}
local stances: { [number]: string? } = {}
local combo: UIHelpers.ComboState = { attacker = 1, hits = 0, damage = 0, shown = false, expiresAt = 0, counterUntil = 0 }
local comboTag: { side: number, word: string, untilTime: number } = { side = 0, word = "", untilTime = 0 }
local lastComboHits = 0
local lastPhase = ""
local lastKO = false
-- Bars are indexed by screen side (1 = left, 2 = right). The local fighter is always on the left: when the local
-- player is slot 2 (viewSlot 2), slot data is mapped to the opposite side.
local viewSlot = 1
local tags: { [number]: string? } = {}
local playerNames: { [number]: string? } = {}
local matchOverAt: number? = nil
local resultShown = false
local roundEndShown = false
local guideShown = false
local guideAutoUntil = 0
local guidePending = false -- evaluate the auto guide on the next frame of a new fight
local guideSeen: { [string]: boolean } = {}
local guideDevice = ""
local calloutSerial = 0
local ultDevice = ""
-- Fight states by snapshot frame (slot-indexed), so a hit landing on a fighter in Recovery reads as a PUNISH even when
-- the event is drained after later snapshots (server sessions).
local stateHistory: { { frame: number, states: { string } } } = {}

local function sideOf(slot: number): number
	if viewSlot == 2 then return 3 - slot end
	return slot
end

local function escapeRich(s: string): string
	return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub("\"", "&quot;"):gsub("'", "&apos;"))
end

local function roster(): any
	local ok, r = pcall(function() return require(ReplicatedStorage.FightingLab.Roster) end)
	return if ok then r else nil
end

local touchOverride: boolean? = nil -- tests force a device; nil = ask UserInputService
local function touchOnly(): boolean
	if touchOverride ~= nil then return touchOverride end
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and not UserInputService.MouseEnabled
end

local BODY_BOUND_PARTS = { Head = true, UpperTorso = true, LowerTorso = true, LeftUpperArm = true, LeftLowerArm = true, LeftHand = true, RightUpperArm = true, RightLowerArm = true, RightHand = true, LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true, RightUpperLeg = true, RightLowerLeg = true, RightFoot = true }
local function modelBounds(model: Model): (Vector3, Vector3)
	local minBound = Vector3.new(math.huge, math.huge, math.huge)
	local maxBound = Vector3.new(-math.huge, -math.huge, -math.huge)
	local found = false
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and BODY_BOUND_PARTS[d.Name] == true then
			local cf, size = d.CFrame, d.Size
			for _, sx in { -0.5, 0.5 } do for _, sy in { -0.5, 0.5 } do for _, sz in { -0.5, 0.5 } do
				local p = cf * Vector3.new(size.X * sx, size.Y * sy, size.Z * sz)
				minBound = minBound:Min(p)
				maxBound = maxBound:Max(p)
				found = true
			end end end
		end
	end
	if not found then
		local cf, size = model:GetBoundingBox()
		return cf.Position - size * 0.5, cf.Position + size * 0.5
	end
	return minBound, maxBound
end
local function actualFacingDot(model: Model, cam: Camera): number
	local rootPart = model:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then return 0 end
	local toCamera = Vector3.new(cam.CFrame.Position.X - rootPart.Position.X, 0, cam.CFrame.Position.Z - rootPart.Position.Z)
	local look = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z)
	if toCamera.Magnitude < 0.001 or look.Magnitude < 0.001 then return 0 end
	return look.Unit:Dot(toCamera.Unit)
end

--------------------------------------------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------------------------------------------
local TOP = 18
local BAR_H = 30
local BAR_W = 500
local SLANT = 13
local CARD = 70 -- portrait card size
local TIMER_W = 116
local GAP = 12 -- between a bar's inner end and the clock plate
M.LAYOUT = { top = TOP, barHeight = BAR_H, barWidth = BAR_W, card = CARD, timerWidth = TIMER_W }

local function makeBar(index: number, color: Color3): Bar
	local s = stage :: Frame
	local right = index == 2
	local groupW = BAR_W + CARD - 16
	-- Each side hangs off the screen centre, so wide screens keep the bars close to the clock.
	local group: Frame = make("Frame", { Name = "HudFighter" .. index, BackgroundTransparency = 1, AnchorPoint = Vector2.new(if right then 0 else 1, 0), Position = UDim2.new(0.5, if right then TIMER_W / 2 + GAP else -(TIMER_W / 2 + GAP), 0, TOP), Size = UDim2.fromOffset(groupW, 120), Parent = s })
	local outerX = if right then groupW - CARD else 0
	-- Health bar (from the card toward the clock)
	local bar = HudKit.healthBar(group, "Bar", BAR_W, BAR_H, SLANT, right, { AnchorPoint = Vector2.new(if right then 0 else 1, 0), Position = if right then UDim2.fromOffset(0, 14) else UDim2.new(1, 0, 0, 14) })
	-- Accent edge under the bar in the fighter's colour
	local edge: Frame = make("Frame", { Name = "Edge", BackgroundColor3 = color, BorderSizePixel = 0, AnchorPoint = Vector2.new(if right then 0 else 1, 0), Position = if right then UDim2.fromOffset(0, 14 + BAR_H + 3) else UDim2.new(1, -SLANT, 0, 14 + BAR_H + 3), Size = UDim2.fromOffset(BAR_W - SLANT - CARD + 30, 3), Parent = group })
	make("UIGradient", { Rotation = if right then 180 else 0, Transparency = UIHelpers.ramp({ { 0, 0.85 }, { 1, 0 } }), Parent = edge })
	-- Portrait card (outer end), drawn over the bar's outer cap
	local card: Frame = make("Frame", { Name = "PortraitFrame", BackgroundColor3 = T.panel, BorderSizePixel = 0, Position = UDim2.fromOffset(outerX, 0), Size = UDim2.fromOffset(CARD, CARD), ClipsDescendants = true, ZIndex = 8, Parent = group })
	UIHelpers.corner(card, 4)
	UIHelpers.gradient(card, color:Lerp(T.bg, 0.45), T.bg, 90)
	local pstroke = UIHelpers.outline(card, color, 2, 0)
	local vp: ViewportFrame = make("ViewportFrame", { Name = "Portrait", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Ambient = Color3.fromRGB(200, 204, 220), LightColor = Color3.fromRGB(255, 244, 220), LightDirection = Vector3.new(-0.35, -0.72, -0.58), ImageTransparency = 1, ZIndex = 8, Parent = card })
	local cam = make("Camera", { CFrame = CFrame.new(Vector3.new(0, 1.8, 4.6), Vector3.new(0, 1.65, 0)), Parent = vp })
	vp.CurrentCamera = cam
	make("WorldModel", { Name = "World", Parent = vp })
	-- a slanted accent sash across the card's lower corner
	local sash = HudKit.cap(card, "Sash", 26, 26, if right then "BL" else "BR", color, 0.1, { AnchorPoint = Vector2.new(if right then 0 else 1, 1), Position = if right then UDim2.fromScale(0, 1) else UDim2.fromScale(1, 1), ZIndex = 9 })
	refs["sash" .. index] = sash
	-- Name row under the bar: FIGHTER  player  [TAG]
	local nameRow = make("Frame", { Name = "NameRow", BackgroundTransparency = 1, AnchorPoint = Vector2.new(if right then 1 else 0, 0), Position = if right then UDim2.new(1, -(CARD + 8), 0, 14 + BAR_H + 9) else UDim2.fromOffset(CARD + 8, 14 + BAR_H + 9), Size = UDim2.fromOffset(BAR_W - 150, 30), Parent = group })
	UIHelpers.list(nameRow, true, 9, if right then Enum.HorizontalAlignment.Right else Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	local name = text(nameRow, "Name", "", T.display, 27, WHITE, { Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2, RichText = true })
	UIHelpers.textStroke(name, 0.35, 2)
	local tagPlate: Frame = make("Frame", { Name = "TagPlate", BackgroundColor3 = T.gold, BorderSizePixel = 0, Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = if right then 1 else 3, Parent = nameRow })
	UIHelpers.corner(tagPlate, 2)
	make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), Parent = tagPlate })
	local tag = text(tagPlate, "Slot", "", T.heavy, 11, T.ink, { Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, TextXAlignment = Enum.TextXAlignment.Center })
	local player = text(nameRow, "Player", "", T.bold, 14, Color3.fromRGB(214, 220, 232), { Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = if right then 0 else 4 })
	UIHelpers.textStroke(player, 0.5, 1)
	-- Status row at the bar's inner end: SURGE and the ULTIMATE indicator (Contract A)
	local status = make("Frame", { Name = "Status", BackgroundTransparency = 1, AnchorPoint = Vector2.new(if right then 0 else 1, 0), Position = if right then UDim2.fromOffset(4, 14 + BAR_H + 10) else UDim2.new(1, -4, 0, 14 + BAR_H + 10), Size = UDim2.fromOffset(300, 26), Parent = group })
	UIHelpers.list(status, true, 6, if right then Enum.HorizontalAlignment.Left else Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
	local surgeChip = HudKit.chip(status, "Surge", "SURGE", 22, T.display, 16, SURGE_RED, WHITE, if right then "\\" else "/", { LayoutOrder = if right then 1 else 2, Visible = false })
	local ultChip: Frame = make("Frame", { Name = "Ultimate", BackgroundColor3 = Color3.fromRGB(16, 14, 10), BackgroundTransparency = 0.08, BorderSizePixel = 0, Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = if right then 2 else 1, Visible = false, Parent = status })
	UIHelpers.corner(ultChip, 3)
	local ultStroke = UIHelpers.outline(ultChip, ULT_GOLD, 1.5, 0)
	refs["ultStroke" .. index] = ultStroke
	make("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 8), Parent = ultChip })
	UIHelpers.list(ultChip, true, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	local ultKey = make("Frame", { Name = "Key", BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 1, Parent = ultChip })
	UIHelpers.list(ultKey, true, 2, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	local ultText = text(ultChip, "Text", "ULTIMATE", T.display, 15, ULT_GOLD, { Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2 })
	-- the current stance (round 6 signatures: Pocket, Southpaw, ...) while the fighter holds one
	local stanceChip = HudKit.chip(status, "Stance", "", 20, T.heavy, 12, Color3.fromRGB(28, 32, 44), WHITE, if right then "\\" else "/", { LayoutOrder = if right then 3 else 0, Visible = false })
	refs["stance" .. index] = stanceChip
	return {
		group = group, bar = bar, portrait = vp, portraitStroke = pstroke, card = card, name = name, tag = tag, tagPlate = tagPlate, player = player,
		pips = {}, edge = edge, color = color, right = right, surgeChip = surgeChip, ultChip = ultChip, ultKey = ultKey, ultText = ultText, status = status,
	}
end

local function buildGuide(): Frame
	local s = stage :: Frame
	local panel: Frame, content: Frame = UIHelpers.edgeCard(s, "ControlsGuide", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -16), Size = UDim2.fromOffset(330, 0), BackgroundTransparency = 0.16, Visible = false }, T.ember, 3, 12, 10)
	UIHelpers.list(content, false, 6)
	refs.guideContent = content
	return panel
end

-- Rebuilds the guide's rows for a device (keys straight from Controls).
local function fillGuide(device: string)
	local panel = refs.guideContent :: Frame
	if not panel then return end
	for _, c in panel:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
	guideDevice = device
	local head = make("Frame", { Name = "Head", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 0, Parent = panel })
	text(head, "Title", "CONTROLS", T.heavy, 12, T.ember, { Size = UDim2.fromScale(0.5, 1) })
	local hide = UIHelpers.keyLabel("fight", "guide", device)
	local hideRow = make("Frame", { Name = "Hide", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(120, 18), Parent = head })
	UIHelpers.list(hideRow, true, 4, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
	if hide ~= "" then UIHelpers.glyph(hideRow, hide, { height = 16, device = device, order = 1 }) end
	text(hideRow, "Text", "HIDE", T.heavy, 10, T.muted, { Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2 })
	local function row(order: number, keys: { string }, caption: string)
		local r = make("Frame", { Name = "Row" .. order, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = order, Parent = panel })
		local k = make("Frame", { Name = "Keys", BackgroundTransparency = 1, Size = UDim2.fromOffset(112, 22), Parent = r })
		UIHelpers.list(k, true, 3, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
		UIHelpers.glyphRow(k, keys, { height = 20, device = device, separator = "/" })
		text(r, "Text", caption, T.bold, 13, T.text, { Position = UDim2.fromOffset(116, 0), Size = UDim2.new(1, -116, 1, 0), RichText = true })
	end
	local function l(action: string): string return UIHelpers.keyLabel("fight", action, device) end
	row(1, { l("forward") }, "Forward  ·  <b>x2</b> dash")
	row(2, { l("back") }, "Back + guard  ·  <b>x2</b> backdash")
	row(3, { l("sidestepIn"), l("sidestepOut") }, "<b>Tap</b>: sidestep in / out")
	row(4, { l("crouch") }, "<b>Hold</b>: crouch guard")
	-- Attack buttons with their notation numbers.
	local atk = make("Frame", { Name = "Attacks", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 5, Parent = panel })
	UIHelpers.list(atk, true, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	for i, a in { { "lp", "1" }, { "rp", "2" }, { "lk", "3" }, { "rk", "4" } } do
		local cell = make("Frame", { Name = "A" .. a[2], BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = i, Parent = atk })
		UIHelpers.list(cell, true, 3, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
		UIHelpers.glyph(cell, l(a[1]), { height = 20, device = device, order = 1 })
		UIHelpers.notationRow(cell, a[2], { height = 20, order = 2 })
	end
	text(panel, "Limbs", "1 L.punch  ·  2 R.punch  ·  3 L.kick  ·  4 R.kick", T.medium, 12, T.muted, { Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 6 })
	row(7, { l("throw") }, "Throw  ·  break: " .. l("lp") .. " or " .. l("rp"))
	local ultKey = l("ultimate")
	if ultKey ~= "" then row(8, { ultKey }, "<b>Ultimate</b> (1+2) in Surge, once a round") end
	row(9, {}, "<b>Stand still</b> = standing guard")
end

local function makeTimer(s: Frame)
	local plate: Frame = make("Frame", { Name = "TimerPlate", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, TOP - 4), Size = UDim2.fromOffset(TIMER_W, 66), Parent = s })
	local slab = HudKit.slab(plate, "Plate", TIMER_W, 66, 12, "V", Color3.fromRGB(10, 12, 18), 0.06, { Size = UDim2.fromScale(1, 1) })
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(30, 34, 48), Color3.fromRGB(8, 9, 14)), Parent = slab.body })
	make("Frame", { Name = "Underline", BackgroundColor3 = T.ember, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.new(0, TIMER_W - 34, 0, 3), ZIndex = 2, Parent = plate })
	refs.timer = text(plate, "Timer", "60", T.number, 38, T.text, { Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 2), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 2 })
	refs.timerScale = make("UIScale", { Parent = refs.timer })
	refs.round = text(plate, "Mode", "ROUND 1", T.heavy, 11, T.muted, { Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 0, 14), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 2 })
	-- round pips under the clock: two per side, slanted like the bars
	for side = 1, 2 do
		local right = side == 2
		local row = make("Frame", { Name = "Pips" .. side, BackgroundTransparency = 1, AnchorPoint = Vector2.new(if right then 0 else 1, 0), Position = UDim2.new(0.5, if right then 4 else -4, 1, 6), Size = UDim2.fromOffset(52, 12), Parent = plate })
		UIHelpers.list(row, true, 4, if right then Enum.HorizontalAlignment.Left else Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
		local pips: { Frame } = {}
		for i = 1, 2 do
			local holder = make("Frame", { Name = "Pip" .. i, BackgroundTransparency = 1, Size = UDim2.fromOffset(24, 11), LayoutOrder = if right then i else 3 - i, Parent = row })
			local mark = HudKit.slab(holder, "Mark", 24, 11, 4, if right then "\\" else "/", Color3.fromRGB(34, 38, 52), 0.05, { Size = UDim2.fromScale(1, 1) })
			holder:SetAttribute("Won", false)
			refs["pip" .. side .. "_" .. i] = mark
			table.insert(pips, holder)
		end
		refs["pips" .. side] = pips
	end
end

local function build(newCtx: Ctx)
	local g: ScreenGui = newCtx.gui
	local r: Frame = make("Frame", { Name = "FightHud", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = g })
	root = r
	local s: Frame = make("Frame", { Name = "Stage", BackgroundTransparency = 1, Parent = r })
	stage = s
	refs.unfit = UIHelpers.fitToScreen(r, s, touchOnly())
	-- Top shade so the bars read over bright stages.
	local shade = make("Frame", { Name = "Shade", BackgroundColor3 = T.bg, BorderSizePixel = 0, Position = UDim2.fromOffset(-60, -60), Size = UDim2.new(1, 120, 0, 200), Parent = s })
	make("UIGradient", { Rotation = 90, Transparency = UIHelpers.ramp({ { 0, 0.3 }, { 1, 1 } }), Parent = shade })
	bars = { makeBar(1, T.cool), makeBar(2, T.warm) }
	makeTimer(s)
	bars[1].pips = refs.pips1
	bars[2].pips = refs.pips2
	banners = HudBanners.build(s, r)
	local b = banners :: HudBanners.Banners
	refs.bannerHolder, refs.banner, refs.bannerSub = b.centre, b.word, b.sub
	-- Combo counters (one per side): count, HITS, total damage and the hit-type tag.
	refs.combo = {}
	for side = 1, 2 do
		local right = side == 2
		local holder = make("Frame", { Name = "Combo" .. side, BackgroundTransparency = 1, AnchorPoint = Vector2.new(if right then 1 else 0, 0), Position = if right then UDim2.new(1, -36, 0.26, 0) else UDim2.new(0, 36, 0.26, 0), Size = UDim2.fromOffset(300, 140), Visible = false, Parent = s })
		local align = if right then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left
		local slashBand = HudKit.slab(holder, "Band", 220, 82, 26, if right then "\\" else "/", T.bg, 0.45, { AnchorPoint = Vector2.new(if right then 1 else 0, 0), Position = if right then UDim2.new(1, 12, 0, 6) else UDim2.fromOffset(-12, 6) })
		local _ = slashBand
		local count = text(holder, "Count", "", T.display, 84, WHITE, { Size = UDim2.fromOffset(300, 86), TextXAlignment = align, ZIndex = 2 })
		UIHelpers.textStroke(count, 0.2, 3)
		local hits = text(holder, "Hits", "HITS", T.title, 24, T.gold, { Position = UDim2.fromOffset(0, 78), Size = UDim2.fromOffset(300, 28), TextXAlignment = align, ZIndex = 2 })
		UIHelpers.textStroke(hits, 0.35, 1.5)
		local dmg = text(holder, "Damage", "", T.heavy, 16, T.text, { Position = UDim2.fromOffset(0, 106), Size = UDim2.fromOffset(300, 20), TextXAlignment = align, ZIndex = 2 })
		UIHelpers.textStroke(dmg, 0.4, 1.2)
		local kind = text(holder, "Kind", "", T.heavy, 13, T.ember, { Position = UDim2.fromOffset(0, 124), Size = UDim2.fromOffset(300, 16), TextXAlignment = align, ZIndex = 2 })
		UIHelpers.textStroke(kind, 0.4, 1.2)
		local scale = make("UIScale", { Parent = holder })
		refs.combo[side] = { holder = holder, count = count, hits = hits, damage = dmg, kind = kind, scale = scale }
	end
	-- Side call-outs (COUNTER HIT / PUNISH / LAUNCH / SURGE ...) under each combo counter.
	refs.callouts = {}
	for side = 1, 2 do
		local right = side == 2
		local stack = make("Frame", { Name = "Callouts" .. side, BackgroundTransparency = 1, AnchorPoint = Vector2.new(if right then 1 else 0, 0), Position = if right then UDim2.new(1, -36, 0.26, 148) else UDim2.new(0, 36, 0.26, 148), Size = UDim2.fromOffset(360, 130), Parent = s })
		UIHelpers.list(stack, false, 5, if right then Enum.HorizontalAlignment.Right else Enum.HorizontalAlignment.Left)
		refs.callouts[side] = stack
	end
	refs.centerCallouts = make("Frame", { Name = "CenterCallouts", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.2), Size = UDim2.fromOffset(500, 100), Parent = s })
	UIHelpers.list(refs.centerCallouts, false, 4, Enum.HorizontalAlignment.Center)
	-- Paused (practice)
	refs.paused = text(s, "Paused", "PAUSED", T.display, 64, T.text, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(600, 80), TextXAlignment = Enum.TextXAlignment.Center, Visible = false })
	UIHelpers.textStroke(refs.paused, 0.2, 3)
	-- Controls guide + its hint chip.
	refs.guide = buildGuide()
	local chip = make("Frame", { Name = "GuideChip", BackgroundColor3 = T.panel, BackgroundTransparency = 0.2, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -16), Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, Visible = false, Parent = s })
	UIHelpers.corner(chip, 4)
	make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 10), Parent = chip })
	UIHelpers.list(chip, true, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	refs.guideChip = chip
end

local function fillChip(device: string)
	local chip = refs.guideChip :: Frame
	for _, c in chip:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
	local key = UIHelpers.keyLabel("fight", "guide", device)
	if key ~= "" then UIHelpers.glyph(chip, key, { height = 20, device = device, order = 1 }) end
	text(chip, "Text", "CONTROLS", T.heavy, 12, T.text, { Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2 })
end

--------------------------------------------------------------------------------------------------------------------
-- Portraits
--------------------------------------------------------------------------------------------------------------------
local function refreshPortrait(index: number, characterId: string?)
	local c = ctx; local b = bars[index]; if not c or not b then return end
	local world = b.portrait:FindFirstChild("World"); if not world then error("FightingLab HUD portrait WorldModel missing") end
	local id = characterId or ""
	local cache = portraitCache[index]
	-- Portrait clones stay parented in their WorldModel for the session and are swapped by moving them: re-parenting
	-- or re-cloning would replay the layered-clothing refit (a bare body) inside the portrait.
	for otherId, entry in cache do
		if otherId ~= id and entry.model.Parent then entry.model:PivotTo(PORTRAIT_PARKED) end
	end
	local entry = cache[id]
	if entry and entry.model.Parent == world then
		entry.model:PivotTo(entry.pivot)
		local cam = b.portrait.CurrentCamera
		if cam then cam.FieldOfView = entry.fov; cam.CFrame = entry.cameraCFrame end
		b.portrait:SetAttribute("CharacterId", id); b.portrait:SetAttribute("FacingDot", entry.facingDot)
		b.portrait.ImageTransparency = if entry.ready then 0 else 1
		return
	end
	local model: Model? = nil
	if characterId then
		local lab = ReplicatedStorage:FindFirstChild("FightingLab")
		local templates = lab and lab:FindFirstChild("Characters")
		local template = templates and templates:FindFirstChild(characterId)
		if template and template:IsA("Model") then model = template end
	end
	if not model then return end
	b.portrait.ImageTransparency = 1
	model.Archivable = true
	local clone = model:Clone()
	for _, d in clone:GetDescendants() do if d:IsA("BasePart") then d.Anchored = (d.Name == "HumanoidRootPart"); d.CanCollide = false; d.LocalTransparencyModifier = 0 end end
	clone.Parent = world
	local presenter = c.modules and c.modules.Characters
	if presenter and presenter.posePreview then pcall(presenter.posePreview, clone, characterId or clone.Name, "Stance", os.clock()) end
	local minBound, maxBound = modelBounds(clone)
	local cam = b.portrait.CurrentCamera
	local newEntry: PortraitEntry = { model = clone, pivot = clone:GetPivot(), cameraCFrame = if cam then cam.CFrame else CFrame.new(), fov = if cam then cam.FieldOfView else 70, facingDot = 1, ready = false }
	if cam then
		local plan = UIHelpers.viewportFramePlan(clone:GetPivot(), minBound, maxBound, true, if index == 1 then -16 else 16)
		clone:PivotTo(plan.pivot); cam.FieldOfView = plan.fieldOfView; cam.CFrame = plan.cameraCFrame
		local facingDot = actualFacingDot(clone, cam)
		if facingDot < 0.7 then clone:PivotTo(clone:GetPivot() * CFrame.Angles(0, math.pi, 0)); facingDot = actualFacingDot(clone, cam) end
		newEntry.pivot = clone:GetPivot(); newEntry.cameraCFrame = cam.CFrame; newEntry.fov = cam.FieldOfView; newEntry.facingDot = facingDot
		b.portrait:SetAttribute("CharacterId", id); b.portrait:SetAttribute("FacingDot", facingDot)
	end
	cache[id] = newEntry
	local wantAccessories, wantWrapLayers, wantExtras = NetProtocol.appearanceCounts(model)
	local portrait = b.portrait
	AvatarGate.track(clone, {
		label = "Portrait " .. id,
		expected = function() return wantAccessories, wantWrapLayers, wantExtras end,
		settleSeconds = PORTRAIT_SETTLE,
		hide = function() if portraitIds[index] == id then portrait.ImageTransparency = 1 end end,
		show = function()
			newEntry.ready = true
			if portraitIds[index] == id then portrait.ImageTransparency = 0 end
			portrait:SetAttribute("PortraitShownAt", os.clock())
		end,
	})
end

--------------------------------------------------------------------------------------------------------------------
-- Banners and call-outs
--------------------------------------------------------------------------------------------------------------------
local function showBanner(word: string, color: Color3, sub: string?, hold: number?)
	local b = banners
	if not b then return end
	HudBanners.show(b, word, color, sub, hold)
end

local CALLOUT_COLORS: { [string]: Color3 } = {
	["COUNTER HIT"] = T.ember, PUNISH = Color3.fromRGB(255, 120, 60), LAUNCH = T.gold, ["THROW ESCAPE"] = T.cool, THROW = Color3.fromRGB(196, 150, 255),
	PARRY = T.cool, ARMOR = Color3.fromRGB(255, 170, 90), CRUSH = Color3.fromRGB(150, 230, 120), EVADE = Color3.fromRGB(150, 230, 255),
	KNOCKDOWN = T.gold, SURGE = SURGE_RED, ULTIMATE = ULT_GOLD,
}
M.CALLOUT_COLORS = CALLOUT_COLORS
-- Slanted call-out chip on one side (1 = left, 2 = right) or the centre (0).
local function callout(word: string, side: number)
	local stack = if side == 0 then refs.centerCallouts else refs.callouts[side]
	if not stack then return end
	calloutSerial += 1
	local color = CALLOUT_COLORS[word] or T.gold
	local textColor = if word == "SURGE" then WHITE else T.ink
	local chip = HudKit.chip(stack, "Callout", word, 36, T.display, 24, color, textColor, if side == 2 then "\\" else "/", { LayoutOrder = -calloutSerial })
	local holder = chip.holder
	local sc = make("UIScale", { Scale = 1.4, Parent = holder })
	TweenService:Create(sc, TweenInfo.new(0.16, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	task.delay(0.95, function()
		if not holder.Parent then return end
		for _, d in holder:GetDescendants() do
			if d:IsA("Frame") then TweenService:Create(d, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play() end
			if d:IsA("TextLabel") then TweenService:Create(d, TweenInfo.new(0.2), { TextTransparency = 1 }):Play() end
		end
		task.delay(0.22, function() holder:Destroy() end)
	end)
	local items = stack:GetChildren()
	local count = 0
	for _, c in items do if c.Name == "Callout" then count += 1 end end
	if count > 3 then
		local oldest: Instance? = nil
		for _, c in items do if c.Name == "Callout" and (oldest == nil or (c :: any).LayoutOrder > (oldest :: any).LayoutOrder) then oldest = c end end
		if oldest then oldest:Destroy() end
	end
end
M.callout = callout

--------------------------------------------------------------------------------------------------------------------
-- Controls guide
--------------------------------------------------------------------------------------------------------------------
local function currentDevice(): string
	local d = UIHelpers.inputDevice()
	return if d == "gamepad" then "gamepad" else "keyboard"
end
local function paintGuide()
	local panel = refs.guide :: Frame
	if not panel then return end
	local dev = currentDevice()
	local touch = touchOnly()
	if guideShown and dev ~= guideDevice then fillGuide(dev) end
	-- an Ultimate cinematic owns the screen: the guide and its chip step aside until it ends
	local cinematic = banners ~= nil and (banners :: HudBanners.Banners).cinematic
	panel.Visible = guideShown and not touch and not cinematic
	local chip = refs.guideChip :: Frame
	if chip then
		if not guideShown and chip:GetAttribute("Device") ~= dev then chip:SetAttribute("Device", dev); fillChip(dev) end
		chip.Visible = not guideShown and not touch and not cinematic
	end
end
function M.guideVisible(): boolean return guideShown end
function M.setGuide(on: boolean)
	guideShown = on
	guideAutoUntil = 0
	if on then fillGuide(currentDevice()) end
	paintGuide()
end
function M.toggleGuide() M.setGuide(not guideShown) end
function M.toggleDebug() debugShown = not debugShown end
function M.recordInput(textValue: string) table.insert(inputHistory, 1, textValue); while #inputHistory > 10 do table.remove(inputHistory) end end
function M.inputHistory(): { string } return table.clone(inputHistory) end
-- Clears the per-session guide memory (tests and tools).
function M._resetForTests() table.clear(guideSeen); guideShown = false; guideAutoUntil = 0; guidePending = false end
-- Forces touch-only (true) or keyboard/gamepad (false) behaviour; nil restores the real device (tests only; the
-- Studio device simulator can make the test DataModel look like a phone).
function M._setTouchOverride(v: boolean?) touchOverride = v; ultDevice = "" end
-- "Auto" opens the guide in the first fight and the first practice per session; "On" in every fight; "Off" never.
function M.guideMode(): string
	local c = ctx
	local v = c and c.gui and c.gui:GetAttribute("ControlsGuide")
	return if v == "On" or v == "Off" then v else "Auto"
end
local function evaluateAutoGuide(kind: string)
	local mode = M.guideMode()
	local want = mode == "On" or (mode == "Auto" and not guideSeen[kind])
	guideSeen[kind] = true
	if want and not touchOnly() then
		M.setGuide(true)
		if mode == "Auto" then guideAutoUntil = os.clock() + M.GUIDE_AUTO_SECONDS end
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Surge / Ultimate (Contract A)
--------------------------------------------------------------------------------------------------------------------
-- Key label shown on the ULTIMATE indicator for a device: the Controls key ("L", "RT"), the notation ("1+2") when
-- Controls has no ultimate binding yet, and nothing on touch.
function M.ultimateKey(device: string): string
	if device == "touch" then return "" end
	local key = UIHelpers.keyLabel("fight", "ultimate", device)
	if key ~= "" then return key end
	local c = UIHelpers.controls()
	local notation = typeof(c.notation) == "table" and c.notation.ultimate or nil
	return if typeof(notation) == "string" and notation ~= "" then notation else "1+2"
end

-- What the status row shows for one side: (surgeVisible, ultimateVisible). Both false without the fields.
function M.statusFor(surgeValue: boolean?, ultUsedValue: boolean?): (boolean, boolean)
	local inSurge = surgeValue == true
	return inSurge, inSurge and ultUsedValue ~= true
end

-- Display name of a stance key: "StillWater" -> "STILL WATER", "Pocket" -> "POCKET".
function M.stanceName(key: string): string
	local spaced = string.gsub(key, "(%l)(%u)", "%1 %2")
	return string.upper(spaced)
end

local function paintUltKey(b: Bar, device: string)
	for _, c in b.ultKey:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
	local key = M.ultimateKey(device)
	b.ultKey.Visible = key ~= ""
	if key ~= "" then
		if string.find(key, "%d") and not string.find(key, "%a") then
			UIHelpers.notationRow(b.ultKey, key, { height = 18, order = 1 })
		else
			UIHelpers.glyph(b.ultKey, key, { height = 18, device = if device == "gamepad" then "gamepad" else "keyboard", order = 1 })
		end
	end
	b.ultText.Text = if key == "" then "ULTIMATE READY" else "ULTIMATE"
end

--------------------------------------------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------------------------------------------
function M.setVisible(b: boolean)
	hudVisible = b
	if root then root.Visible = b end
	if not b then
		guidePending = false
		if banners then HudBanners.hideAll(banners) end
	end
end
-- Which slot the local player controls; its fighter is drawn on the left (bars swap for slot 2). Resets fight state.
function M.setViewSlot(slot: number)
	viewSlot = if slot == 2 then 2 else 1
	table.clear(tags)
	table.clear(playerNames)
	matchOverAt = nil
	resultShown = false
	roundEndShown = false
	if banners then HudBanners.hideAll(banners) end
	combo = { attacker = 1, hits = 0, damage = 0, shown = false, expiresAt = 0, counterUntil = 0 }
	comboTag = { side = 0, word = "", untilTime = 0 }
	lastComboHits = 0
	lastPhase = ""
	lastKO = false
	table.clear(surge)
	table.clear(ultUsed)
	table.clear(inUltimate)
	table.clear(stances)
	table.clear(stateHistory)
	table.clear(inputHistory)
	trails = { { value = maxHealth[1], holdUntil = 0 }, { value = maxHealth[2], holdUntil = 0 } }
	guidePending = true
end
function M.getViewSlot(): number return viewSlot end
-- `index` is the fight slot. Optional `playerName` (shown next to the fighter name) and `tag` ("YOU", "P2", "CPU · HARD").
function M.setFighterInfo(index: number, info: { displayName: string, color: Color3, characterId: string, maxHealth: number?, playerName: string?, tag: string? })
	local side = sideOf(index)
	local b = bars[side]
	if not b then return end
	portraitIds[side] = info.characterId
	b.name.Text = escapeRich(string.upper(info.displayName))
	b.name.TextColor3 = info.color:Lerp(WHITE, 0.35)
	local playerName = if info.playerName ~= nil then info.playerName else playerNames[side]
	if info.playerName ~= nil then playerNames[side] = info.playerName end
	b.player.Text = playerName or ""
	b.player.Visible = playerName ~= nil and playerName ~= ""
	tags[side] = info.tag
	if info.tag then b.tag.Text = info.tag end
	b.tagPlate.BackgroundColor3 = if info.tag == "YOU" then T.gold elseif info.tag and string.sub(info.tag, 1, 3) == "CPU" then T.ember elseif info.tag == "DUMMY" then T.cool else T.muted
	b.color = info.color
	b.portraitStroke.Color = info.color
	b.edge.BackgroundColor3 = info.color
	local sash = refs["sash" .. side]
	if sash then sash.frame.BackgroundColor3 = info.color end
	if info.maxHealth then
		maxHealth[side] = info.maxHealth; health[side] = info.maxHealth
		trails[side] = { value = info.maxHealth, holdUntil = 0 }
	end
	refreshPortrait(side, info.characterId)
end
function M.announce(kind: string, textValue: string?)
	local word = textValue or kind
	if kind == "Fight" then
		showBanner(word, HudBanners.COLORS.fight, nil, 0.75)
		if banners then HudBanners.flash(banners, 0.28, 0.3) end
	elseif kind == "KO" then
		showBanner(word, HudBanners.COLORS.ko, nil, 1.3)
		if banners then HudBanners.flash(banners, 0.55, 0.45) end
	elseif kind == "Round" then
		showBanner(word, WHITE, nil, 1.0)
	else
		showBanner(word, WHITE, nil, 1.1)
	end
end
-- Held winner banner for the results beat: "YOU WIN" for the local fighter, otherwise the winner's name.
function M.resultText(winnerSlot: number): string
	if winnerSlot ~= 1 and winnerSlot ~= 2 then return "DRAW" end
	local side = sideOf(winnerSlot)
	if tags[side] == "YOU" then return "YOU WIN" end
	local name = playerNames[side]
	if not name or name == "" then
		local id = portraitIds[side]
		local r = roster()
		name = if r and id and r.has(id) then r.get(id).displayName else "P" .. winnerSlot
	end
	return string.upper(name :: string) .. " WINS"
end
-- The winner presentation: YOU WIN / DEFEAT / <NAME> WINS / DRAW over the winning fighter, player and the score.
function M.announceResult(winnerSlot: number, scores: { number }?)
	local b = banners
	if not b then return end
	local word = M.resultText(winnerSlot)
	local mine = word == "YOU WIN"
	local loser = not mine and (tags[1] == "YOU" or tags[2] == "YOU") and word ~= "DRAW"
	HudBanners.hideCentre(b)
	local side = if winnerSlot == 1 or winnerSlot == 2 then sideOf(winnerSlot) else 0
	local fighterName = ""
	local player = ""
	if side > 0 then
		local r = roster()
		local id = portraitIds[side]
		fighterName = if r and id and r.has(id) then r.get(id).displayName else ""
		player = playerNames[side] or ""
	end
	local s = scores or { 0, 0 }
	local score = string.format("%d  —  %d", s[1] or 0, s[2] or 0)
	local title = if mine then "VICTORY" elseif loser then "DEFEAT" else word
	local color = if mine then T.gold elseif loser then T.loss else WHITE
	HudBanners.showWinner(b, title, color, if side > 0 then fighterName .. " WINS" else "", player, score)
	if refs.bannerSub then refs.bannerSub.Text = if loser then word else "" end
end
function M.popup(word: string, color: Color3?)
	if color then CALLOUT_COLORS[word] = CALLOUT_COLORS[word] or color end
	callout(word, 0)
end

local function stateAt(slot: number, frame: number?): string?
	if typeof(frame) ~= "number" then return nil end
	local best: { frame: number, states: { string } }? = nil
	for _, h in stateHistory do
		if h.frame < frame and (best == nil or h.frame > best.frame) then best = h end
	end
	return if best then best.states[slot] else nil
end

-- The call-out (if any) for a combat event and the screen side it belongs to (0 = centre).
function M.calloutFor(e: CombatEvent): (string?, number)
	local attacker = if e.attacker == 1 or e.attacker == 2 then e.attacker else 1
	local side = sideOf(attacker)
	local target = if e.target == 1 or e.target == 2 then e.target else 3 - attacker
	if e.kind == "Hit" and e.counter == true then return "COUNTER HIT", side end
	if e.kind == "Hit" and (e.launch == true or e.tier == "Launch") then return "LAUNCH", side end
	if e.kind == "Hit" and (e.punish == true or ((e.combo or 0) <= 1 and stateAt(target, e.frame) == "Recovery")) then return "PUNISH", side end
	if e.kind == "ThrowBreak" then return "THROW ESCAPE", 0 end
	if e.kind == "ThrowHit" then return "THROW", side end
	if e.kind == "Parry" then return "PARRY", side end
	if e.kind == "Armor" then return "ARMOR", side end
	if e.kind == "Crush" then return "CRUSH", side end
	if e.kind == "Surge" then return "SURGE", side end
	if e.kind == "Whiff" and e.evaded == true then
		return "EVADE", sideOf(target)
	end
	return nil, 0
end

function M.onEvent(e: CombatEvent)
	local now = os.clock()
	if e.kind == "UltHit" then
		-- the cinematic's impacts count like a combo on the attacker's side, from the first impact
		local attacker = if e.attacker == 1 or e.attacker == 2 then e.attacker else 1
		local index = math.max(1, math.floor(tonumber(e.combo) or 1))
		local previous = if index > 1 and combo.attacker == attacker then combo.damage else 0
		combo = { attacker = attacker, hits = index, damage = previous + (tonumber(e.damage) or 0), shown = true, expiresAt = now + 1.8, counterUntil = combo.counterUntil }
		comboTag = { side = sideOf(attacker), word = "ULTIMATE", untilTime = now + 2.5 }
		return
	end
	if e.kind == "UltStart" then
		local attacker = if e.attacker == 1 or e.attacker == 2 then e.attacker else 1
		local side = sideOf(attacker)
		local id = portraitIds[side]
		local r = roster()
		local def = if r and id and r.has(id) then r.get(id) else nil
		local b = banners
		if b then
			HudBanners.showUltimate(b, if def then def.displayName else "", HudBanners.ultimateName(r, id), if def then def.accentColor else nil, side == 2)
			HudBanners.flash(b, 0.35, 0.4)
			HudBanners.setCinematic(b, true)
		end
		ultUsed[side] = true
		return
	end
	combo = UIHelpers.registerCombo(combo, e, now)
	if e.kind == "KO" then return end
	local word, side = M.calloutFor(e)
	if word then
		callout(word, side)
		if (word == "COUNTER HIT" or word == "PUNISH") and side > 0 then comboTag = { side = side, word = if word == "COUNTER HIT" then "COUNTER" else word, untilTime = now + 1.4 } end
	end
end

function M.onSnapshot(entry: any)
	local states: { string } = {}
	for i = 1, 2 do
		local side = sideOf(i)
		local b = bars[side]
		if b and not tags[side] then
			b.tag.Text = if i == viewSlot then "YOU" elseif i == 2 and entry.p2Human ~= true then "CPU" else "P" .. i
		end
		local f = entry.fighters and entry.fighters[i]
		if f then
			if f.characterId and ctx and f.characterId ~= portraitIds[side] then
				-- Rebuild name/colour/portrait only when the slot's fighter changes; rebuilding every snapshot re-cloned
				-- whole avatars at 60 Hz and reset the bars to full health.
				local r = roster()
				if r and r.has(f.characterId) then
					local def = r.get(f.characterId)
					M.setFighterInfo(i, { displayName = def.displayName, color = def.accentColor, characterId = f.characterId, maxHealth = def.stats.maxHealth, tag = tags[side] })
				end
			end
			if f.maxHealth then maxHealth[side] = f.maxHealth end
			if f.health then
				if f.health < health[side] then trails[side].holdUntil = os.clock() + M.TRAIL_HOLD end
				health[side] = f.health
			end
			-- Contract A fields (absent = nothing shown)
			if typeof(f.surge) == "boolean" then surge[side] = f.surge else surge[side] = nil end
			if typeof(f.ultUsed) == "boolean" then ultUsed[side] = f.ultUsed else ultUsed[side] = nil end
			local throw = f.throw
			inUltimate[side] = f.state == "Ultimate" or (typeof(throw) == "table" and throw.archetype == "ultimate")
			stances[side] = if f.state == "Stance" and typeof(f.stance) == "string" then f.stance else nil
			states[i] = if typeof(f.state) == "string" then f.state else ""
		end
	end
	if typeof(entry.frame) == "number" then
		table.insert(stateHistory, { frame = entry.frame, states = states })
		while #stateHistory > 40 do table.remove(stateHistory, 1) end
	end
end

local function updateStatus(now: number)
	local device = if touchOnly() then "touch" else currentDevice()
	if device ~= ultDevice then
		ultDevice = device
		for _, b in bars do paintUltKey(b, device) end
	end
	for side, b in bars do
		local showSurge, showUlt = M.statusFor(surge[side], ultUsed[side])
		b.surgeChip.holder.Visible = showSurge
		b.ultChip.Visible = showUlt
		local pulse = (math.sin(now * 6) + 1) * 0.5
		if showSurge then
			b.surgeChip.label.TextTransparency = 0.05 * pulse
			b.bar.glowTop.Visible = true; b.bar.glowBottom.Visible = true
			local glow = 0.15 + 0.35 * pulse
			b.bar.glowTop.BackgroundTransparency = glow; b.bar.glowBottom.BackgroundTransparency = glow
			HudKit.paintSlab(b.bar.halo, SURGE_RED, 0.25 + 0.45 * (1 - pulse))
			b.portraitStroke.Color = b.color:Lerp(SURGE_RED, 0.5 + 0.5 * pulse)
			b.bar.sheenClip.Visible = true
			local cycle = (now * 0.7) % 1.4
			b.bar.sheen.Position = UDim2.fromScale(if b.right then 1.2 - cycle else cycle - 0.2, 0)
		else
			b.bar.glowTop.Visible = false; b.bar.glowBottom.Visible = false
			HudKit.paintSlab(b.bar.halo, SURGE_RED, 1)
			b.bar.sheenClip.Visible = false
			b.portraitStroke.Color = b.color
		end
		local stroke = refs["ultStroke" .. side] :: UIStroke?
		if showUlt and stroke then stroke.Transparency = 0.45 * (1 - pulse) end
		local stanceChip = refs["stance" .. side] :: HudKit.Chip?
		if stanceChip then
			local key = stances[side]
			stanceChip.holder.Visible = key ~= nil
			if key and stanceChip.label.Text ~= M.stanceName(key) then stanceChip.set(M.stanceName(key), b.color:Lerp(Color3.fromRGB(20, 22, 30), 0.55)) end
		end
	end
end

function M.update(f: RenderFrame)
	if not root then return end
	local now = os.clock()
	local dt = if typeof(f.dt) == "number" then f.dt else 1 / 60
	for i, b in bars do
		local slotIndex = sideOf(i)
		trails[i] = HudKit.stepTrail(trails[i], health[i], maxHealth[i], now, dt)
		local ratio = UIHelpers.healthRatio(health[i], maxHealth[i]); local tr = UIHelpers.healthRatio(trails[i].value, maxHealth[i])
		b.bar.setRatios(ratio, tr)
		local inSurge = surge[i] == true
		local outerColor, innerColor = HudKit.fillColors(ratio, inSurge)
		b.bar.setFillColors(outerColor, innerColor)
		local lowHealth = ratio < 0.25 and surge[i] == nil
		b.bar.low.BackgroundTransparency = if lowHealth and ratio > 0 then 0.8 + math.sin(now * 9) * 0.12 else 1
		for n, p in b.pips do
			local won = f.scores and f.scores[slotIndex] and n <= f.scores[slotIndex]
			p:SetAttribute("Won", won == true)
			local mark = refs["pip" .. i .. "_" .. n]
			if mark then HudKit.paintSlab(mark, if won then T.gold else Color3.fromRGB(34, 38, 52)) end
		end
	end
	updateStatus(now)
	local fps = if f.config and f.config.FPS then f.config.FPS else 60
	refs.timer.Text = UIHelpers.formatTimer(f.mode, f.timer or 0, fps)
	local seconds = if f.mode == "Training" then 99 else math.ceil((f.timer or 0) / fps)
	local urgent = seconds <= 10 and f.mode ~= "Training"
	refs.timer.TextColor3 = if urgent then T.healthLow else T.text
	refs.timerScale.Scale = if urgent then 1 + math.sin(now * 11) * 0.05 else 1
	refs.round.Text = if f.mode == "Training" then "TRAINING" elseif f.session == "Practice" then "VS CPU · R" .. tostring(f.round or 1) else "ROUND " .. tostring(f.round or 1)
	-- Combo counter on the attacker's side.
	local visible = UIHelpers.comboVisible(combo, now)
	for side = 1, 2 do
		local cc = refs.combo[side]
		local mine = visible and sideOf(combo.attacker) == side
		cc.holder.Visible = mine
		if mine then
			cc.count.Text = tostring(combo.hits)
			cc.damage.Text = tostring(math.floor(combo.damage + 0.5)) .. " DAMAGE"
			cc.kind.Text = if comboTag.side == side and now < comboTag.untilTime then comboTag.word else ""
			cc.kind.TextColor3 = if comboTag.word == "ULTIMATE" then ULT_GOLD else T.ember
			if combo.hits ~= lastComboHits then
				lastComboHits = combo.hits
				cc.scale.Scale = 1.25
				TweenService:Create(cc.scale, TweenInfo.new(0.14, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			end
		end
	end
	if not visible then lastComboHits = 0 end
	-- Ultimate cinematic letterbox: on while a fighter is in state "Ultimate".
	local b = banners
	if b then
		HudBanners.setCinematic(b, inUltimate[1] == true or inUltimate[2] == true)
	end
	-- Phase banners: round intro, FIGHT, round end (K.O. / TIME / PERFECT), winner.
	if f.phase ~= lastPhase then
		if f.phase == "Ready" and f.mode ~= "Training" then
			roundEndShown = false
			local winsNeeded = if f.config and f.config.WinsNeeded then f.config.WinsNeeded else 2
			showBanner(HudBanners.roundIntroText(f.round, f.scores, winsNeeded), WHITE, nil, 1.0)
		end
		if f.phase == "Fight" and lastPhase == "Ready" and f.mode ~= "Training" then M.announce("Fight", "FIGHT") end
		if (f.phase == "RoundOver" or f.phase == "MatchOver") and not roundEndShown and f.mode ~= "Training" then
			roundEndShown = true
			local entry = f.entry
			local fighters = if entry and entry.fighters then entry.fighters else f.fighters
			local winner = if typeof(f.winner) == "number" then f.winner else 0
			local headline, sub = HudBanners.roundEndText(f.reason, winner, HudBanners.isPerfect(winner, fighters))
			if headline == "K.O." or headline == "DOUBLE K.O." then
				if not lastKO then M.announce("KO", headline) end
				if sub then task.delay(1.0, function() if b and roundEndShown then HudBanners.show(b, sub, HudBanners.COLORS.perfect, nil, 1.0, 1.2) end end) end
			elseif f.reason == "TIME" then
				showBanner(headline, if headline == "DRAW" then HudBanners.COLORS.draw else HudBanners.COLORS.time, sub, 1.3)
			end
		end
		matchOverAt = if f.phase == "MatchOver" then now else nil
		resultShown = false
		lastPhase = f.phase
	end
	if f.ko and not lastKO and not roundEndShown then M.announce("KO", "K.O.") end
	if f.ko and not lastKO then roundEndShown = roundEndShown or f.mode ~= "Training" end
	lastKO = f.ko == true
	-- After the final K.O. beat, the winner stays announced until the session returns to the lobby.
	if matchOverAt and not resultShown and now - matchOverAt >= 1.5 then
		resultShown = true
		local scores = f.scores or { 0, 0 }
		local winnerSlot = if (scores[1] or 0) > (scores[2] or 0) then 1 elseif (scores[2] or 0) > (scores[1] or 0) then 2 else 0
		M.announceResult(winnerSlot, scores)
	end
	refs.paused.Visible = f.paused == true
	-- Auto guide: first fight / first practice of the session (per the ControlsGuide setting).
	if guidePending then
		guidePending = false
		evaluateAutoGuide(if f.session == "Practice" or f.authority == "Local" then "practice" else "fight")
	end
	if guideAutoUntil > 0 and now > guideAutoUntil then guideAutoUntil = 0; guideShown = false end
	paintGuide()
	root.Visible = hudVisible
end
function M.init(newCtx: Ctx)
	ctx = newCtx; gui = newCtx.gui
	portraitCache = { {}, {} }
	table.clear(portraitIds)
	build(newCtx)
	fillChip(currentDevice())
	ultDevice = ""
end
return M
