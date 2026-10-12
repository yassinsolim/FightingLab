--!strict
-- FightingLab fight HUD (OV6). Long slanted-feel health bars with a damage trail, live bust portraits, player and
-- fighter names, round pips, a centre clock, a combo counter on the attacker's side, call-outs (ROUND / FIGHT / K.O.,
-- COUNTER HIT, LAUNCH, THROW ESCAPE...) and the on-screen controls guide built from FightingLab.Controls (G toggles
-- it through InputController -> toggleGuide; it opens by itself in the first fight and first practice per session
-- when the ControlsGuide setting is "Auto"). The local fighter is always drawn on the left (setViewSlot).
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local UIHelpers = require(script.Parent.UIHelpers)
local AvatarGate = require(script.Parent:WaitForChild("AvatarGate"))
local NetProtocol = require(script.Parent.Parent:WaitForChild("NetProtocol"))
type Ctx = any; type RenderFrame = any; type CombatEvent = any
type PortraitEntry = { model: Model, pivot: CFrame, cameraCFrame: CFrame, fov: number, facingDot: number, ready: boolean }
type Bar = {
	group: Frame, back: Frame, trail: Frame, fill: Frame, fillGradient: UIGradient, low: Frame, portrait: ViewportFrame, portraitStroke: UIStroke,
	name: TextLabel, tag: TextLabel, player: TextLabel, pips: { Frame }, edge: Frame, color: Color3, right: boolean,
}
local T = UIHelpers.Theme
local make, text = UIHelpers.make, UIHelpers.text
local WHITE = Color3.new(1, 1, 1)

local M = {}
M.GUIDE_AUTO_SECONDS = 14 -- an auto-opened guide folds back to its hint chip after this long
local ctx: Ctx? = nil
local gui: ScreenGui? = nil
local root: Frame? = nil
local stage: Frame? = nil
local bars: { Bar } = {}
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
local trail = { 100, 100 }
local combo: UIHelpers.ComboState = { attacker = 1, hits = 0, damage = 0, shown = false, expiresAt = 0, counterUntil = 0 }
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
local guideShown = false
local guideAutoUntil = 0
local guidePending = false -- evaluate the auto guide on the next frame of a new fight
local guideSeen: { [string]: boolean } = {}
local guideDevice = ""
local calloutSerial = 0

local function sideOf(slot: number): number
	if viewSlot == 2 then return 3 - slot end
	return slot
end

local function escapeRich(s: string): string
	return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub("\"", "&quot;"):gsub("'", "&apos;"))
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
local BAR_TOP = 18
local BAR_H = 26
local TIMER_W = 104

local function makeBar(index: number, color: Color3): Bar
	local s = stage :: Frame
	local right = index == 2
	local group: Frame = make("Frame", { Name = "HudFighter" .. index, BackgroundTransparency = 1, AnchorPoint = Vector2.new(if right then 1 else 0, 0), Position = if right then UDim2.new(1, -16, 0, BAR_TOP) else UDim2.fromOffset(16, BAR_TOP), Size = UDim2.new(0.5, -(TIMER_W / 2 + 26), 0, 96), Parent = s })
	-- Portrait (outer end)
	local pframe = make("Frame", { Name = "PortraitFrame", BackgroundColor3 = T.panel, BorderSizePixel = 0, AnchorPoint = Vector2.new(if right then 1 else 0, 0), Position = if right then UDim2.fromScale(1, 0) else UDim2.fromScale(0, 0), Size = UDim2.fromOffset(62, 62), ClipsDescendants = true, Parent = group })
	UIHelpers.corner(pframe, 5)
	UIHelpers.gradient(pframe, color:Lerp(T.bg, 0.55), T.bg, 90)
	local pstroke = UIHelpers.outline(pframe, color, 2, 0)
	local vp: ViewportFrame = make("ViewportFrame", { Name = "Portrait", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Ambient = Color3.fromRGB(200, 204, 220), LightColor = Color3.fromRGB(255, 244, 220), LightDirection = Vector3.new(-0.35, -0.72, -0.58), ImageTransparency = 1, Parent = pframe })
	local cam = make("Camera", { CFrame = CFrame.new(Vector3.new(0, 1.8, 4.6), Vector3.new(0, 1.65, 0)), Parent = vp })
	vp.CurrentCamera = cam
	make("WorldModel", { Name = "World", Parent = vp })
	-- Bar (from the portrait toward the clock)
	local barX = 72
	local back: Frame = make("Frame", { Name = "Back", BackgroundColor3 = Color3.fromRGB(6, 7, 11), BackgroundTransparency = 0.1, BorderSizePixel = 0, ClipsDescendants = true, AnchorPoint = Vector2.new(if right then 1 else 0, 0), Position = if right then UDim2.new(1, -barX, 0, 6) else UDim2.fromOffset(barX, 6), Size = UDim2.new(1, -barX, 0, BAR_H), Parent = group })
	UIHelpers.outline(back, WHITE, 1, 0.78)
	local anchor = if right then Vector2.new(1, 0) else Vector2.zero
	local pos = if right then UDim2.fromScale(1, 0) else UDim2.fromScale(0, 0)
	local trailFrame: Frame = make("Frame", { Name = "Trail", BackgroundColor3 = Color3.fromRGB(255, 92, 70), BorderSizePixel = 0, AnchorPoint = anchor, Position = pos, Size = UDim2.fromScale(1, 1), Parent = back })
	UIHelpers.gradient(trailFrame, Color3.fromRGB(255, 250, 240), Color3.fromRGB(255, 120, 90), 90)
	local fill: Frame = make("Frame", { Name = "Fill", BackgroundColor3 = WHITE, BorderSizePixel = 0, AnchorPoint = anchor, Position = pos, Size = UDim2.fromScale(1, 1), Parent = back })
	local fillGradient = UIHelpers.gradient(fill, Color3.fromRGB(255, 240, 170), Color3.fromRGB(240, 170, 40), 90)
	-- Gloss line along the top of the fill.
	make("Frame", { Name = "Gloss", BackgroundColor3 = WHITE, BackgroundTransparency = 0.55, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 2), Parent = fill })
	local low: Frame = make("Frame", { Name = "LowPulse", BackgroundColor3 = T.healthLow, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = back })
	-- Accent edge under the bar in the fighter's colour.
	local edge: Frame = make("Frame", { Name = "Edge", BackgroundColor3 = color, BorderSizePixel = 0, AnchorPoint = anchor, Position = if right then UDim2.new(1, -barX, 0, 6 + BAR_H) else UDim2.fromOffset(barX, 6 + BAR_H), Size = UDim2.new(1, -barX, 0, 3), Parent = group })
	make("UIGradient", { Transparency = if right then UIHelpers.ramp({ { 0, 1 }, { 1, 0 } }) else UIHelpers.ramp({ { 0, 0 }, { 1, 1 } }), Parent = edge })
	-- Names: FIGHTER (accent) + tag chip (YOU / CPU · HARD) + player name.
	local nameRow = make("Frame", { Name = "NameRow", BackgroundTransparency = 1, AnchorPoint = anchor, Position = if right then UDim2.new(1, -barX, 0, 6 + BAR_H + 6) else UDim2.fromOffset(barX, 6 + BAR_H + 6), Size = UDim2.new(1, -barX - 60, 0, 26), Parent = group })
	UIHelpers.list(nameRow, true, 8, if right then Enum.HorizontalAlignment.Right else Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	local name = text(nameRow, "Name", "", T.display, 22, color, { Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = if right then 3 else 1, RichText = true })
	UIHelpers.textStroke(name, 0.45, 1.5)
	local tag = text(nameRow, "Slot", "", T.heavy, 11, T.ink, { Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 0, BackgroundColor3 = T.gold, LayoutOrder = 2, TextXAlignment = Enum.TextXAlignment.Center })
	UIHelpers.corner(tag, 3)
	make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), Parent = tag })
	local player = text(nameRow, "Player", "", T.bold, 14, Color3.fromRGB(214, 220, 232), { Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = if right then 1 else 3 })
	UIHelpers.textStroke(player, 0.5, 1)
	-- Round pips (diamonds) at the clock end, under the bar.
	local pipRow = make("Frame", { Name = "Pips", BackgroundTransparency = 1, AnchorPoint = Vector2.new(if right then 0 else 1, 0), Position = if right then UDim2.new(0, 0, 0, 6 + BAR_H + 10) else UDim2.new(1, 0, 0, 6 + BAR_H + 10), Size = UDim2.fromOffset(48, 16), Parent = group })
	UIHelpers.list(pipRow, true, 8, if right then Enum.HorizontalAlignment.Left else Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
	local pips: { Frame } = {}
	for i = 1, 2 do
		local holder = make("Frame", { Name = "Pip" .. i, BackgroundTransparency = 1, Size = UDim2.fromOffset(16, 16), LayoutOrder = if right then i else 3 - i, Parent = pipRow })
		local p = make("Frame", { Name = "Diamond", BackgroundColor3 = Color3.fromRGB(30, 34, 46), BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(11, 11), Rotation = 45, Parent = holder })
		UIHelpers.outline(p, T.gold, 1.5, 0.15)
		table.insert(pips, p)
	end
	return { group = group, back = back, trail = trailFrame, fill = fill, fillGradient = fillGradient, low = low, portrait = vp, portraitStroke = pstroke, name = name, tag = tag, player = player, pips = pips, edge = edge, color = color, right = right }
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
	row(8, {}, "<b>Stand still</b> = standing guard")
end

local function build(newCtx: Ctx)
	local g: ScreenGui = newCtx.gui
	local r: Frame = make("Frame", { Name = "FightHud", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = g })
	root = r
	local s: Frame = make("Frame", { Name = "Stage", BackgroundTransparency = 1, Parent = r })
	stage = s
	refs.unfit = UIHelpers.fitToScreen(r, s, touchOnly())
	-- Top shade so the bars read over bright stages.
	local shade = make("Frame", { Name = "Shade", BackgroundColor3 = T.bg, BorderSizePixel = 0, Position = UDim2.fromOffset(-60, -60), Size = UDim2.new(1, 120, 0, 190), Parent = s })
	make("UIGradient", { Rotation = 90, Transparency = UIHelpers.ramp({ { 0, 0.35 }, { 1, 1 } }), Parent = shade })
	bars = { makeBar(1, T.cool), makeBar(2, T.warm) }
	-- Clock
	local clock: Frame = make("Frame", { Name = "TimerPlate", BackgroundColor3 = T.panel, BackgroundTransparency = 0.08, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, BAR_TOP - 4), Size = UDim2.fromOffset(TIMER_W, 62), Parent = s })
	UIHelpers.gradient(clock, Color3.fromRGB(26, 30, 42), Color3.fromRGB(8, 9, 14), 90)
	UIHelpers.corner(clock, 5)
	UIHelpers.outline(clock, WHITE, 1, 0.8)
	make("Frame", { Name = "Underline", BackgroundColor3 = T.ember, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.new(0.6, 0, 0, 3), Parent = clock })
	refs.timer = text(clock, "Timer", "60", T.number, 34, T.text, { Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 2), TextXAlignment = Enum.TextXAlignment.Center })
	refs.timerScale = make("UIScale", { Parent = refs.timer })
	refs.round = text(clock, "Mode", "ROUND 1", T.heavy, 10, T.muted, { Position = UDim2.fromOffset(0, 42), Size = UDim2.new(1, 0, 0, 13), TextXAlignment = Enum.TextXAlignment.Center })
	-- Big centre banner (ROUND / FIGHT / K.O. / result): a dark band sweeps in under the word.
	local bannerHolder = make("Frame", { Name = "BannerHolder", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.4), Size = UDim2.new(1, 0, 0, 150), Visible = false, Parent = s })
	local band = make("Frame", { Name = "Band", BackgroundColor3 = T.bg, BackgroundTransparency = 0.25, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 0, 0, 104), Parent = bannerHolder })
	make("UIGradient", { Transparency = UIHelpers.ramp({ { 0, 1 }, { 0.2, 0.15 }, { 0.8, 0.15 }, { 1, 1 } }), Parent = band })
	local bandLine = make("Frame", { Name = "Line", BackgroundColor3 = T.ember, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.new(0.6, 0, 0, 3), Parent = band })
	make("UIGradient", { Transparency = UIHelpers.ramp({ { 0, 1 }, { 0.5, 0 }, { 1, 1 } }), Parent = bandLine })
	local banner = text(bannerHolder, "Banner", "", T.display, 96, T.text, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 0, 0, 120), TextXAlignment = Enum.TextXAlignment.Center })
	UIHelpers.textStroke(banner, 0.2, 3)
	local bannerSub = text(bannerHolder, "Sub", "", T.heavy, 18, T.muted, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Center })
	UIHelpers.textStroke(bannerSub, 0.4, 1.5)
	refs.bannerHolder, refs.band, refs.bandLine, refs.banner, refs.bannerSub = bannerHolder, band, bandLine, banner, bannerSub
	refs.bannerScale = make("UIScale", { Parent = banner })
	-- Combo counters (one per side, under the bars).
	refs.combo = {}
	for side = 1, 2 do
		local right = side == 2
		local holder = make("Frame", { Name = "Combo" .. side, BackgroundTransparency = 1, AnchorPoint = Vector2.new(if right then 1 else 0, 0), Position = if right then UDim2.new(1, -40, 0.25, 0) else UDim2.new(0, 40, 0.25, 0), Size = UDim2.fromOffset(300, 120), Visible = false, Parent = s })
		local count = text(holder, "Count", "", T.display, 72, WHITE, { Size = UDim2.fromOffset(300, 74), TextXAlignment = if right then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left })
		UIHelpers.textStroke(count, 0.25, 2.5)
		local hits = text(holder, "Hits", "HITS", T.title, 24, T.gold, { Position = UDim2.fromOffset(0, 66), Size = UDim2.fromOffset(300, 28), TextXAlignment = if right then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left })
		UIHelpers.textStroke(hits, 0.35, 1.5)
		local dmg = text(holder, "Damage", "", T.heavy, 15, T.text, { Position = UDim2.fromOffset(0, 94), Size = UDim2.fromOffset(300, 18), TextXAlignment = if right then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left })
		UIHelpers.textStroke(dmg, 0.4, 1.2)
		local scale = make("UIScale", { Parent = holder })
		refs.combo[side] = { holder = holder, count = count, hits = hits, damage = dmg, scale = scale }
	end
	-- Side call-outs (COUNTER HIT / LAUNCH / ...) under each combo counter.
	refs.callouts = {}
	for side = 1, 2 do
		local right = side == 2
		local stack = make("Frame", { Name = "Callouts" .. side, BackgroundTransparency = 1, AnchorPoint = Vector2.new(if right then 1 else 0, 0), Position = if right then UDim2.new(1, -40, 0.25, 122) else UDim2.new(0, 40, 0.25, 122), Size = UDim2.fromOffset(340, 120), Parent = s })
		UIHelpers.list(stack, false, 4, if right then Enum.HorizontalAlignment.Right else Enum.HorizontalAlignment.Left)
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
local bannerToken = 0
local function showBanner(word: string, color: Color3, sub: string?, hold: number?)
	local holder = refs.bannerHolder :: Frame
	if not holder then return end
	bannerToken += 1
	local myToken = bannerToken
	local banner = refs.banner :: TextLabel
	banner.Text = word
	banner.TextColor3 = color
	banner.TextTransparency = 0
	refs.bannerSub.Text = sub or ""
	refs.bannerSub.TextTransparency = 0
	refs.bandLine.BackgroundColor3 = if color == WHITE then T.ember else color
	holder.Visible = true
	local band = refs.band :: Frame
	band.Size = UDim2.new(0, 0, 0, 104)
	band.BackgroundTransparency = 0.25
	TweenService:Create(band, TweenInfo.new(0.22, Enum.EasingStyle.Quint), { Size = UDim2.new(1, 0, 0, 104) }):Play()
	local sc = refs.bannerScale :: UIScale
	sc.Scale = 1.35
	TweenService:Create(sc, TweenInfo.new(0.24, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	if hold and hold > 0 then
		task.delay(hold, function()
			if myToken ~= bannerToken then return end
			TweenService:Create(banner, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()
			TweenService:Create(refs.bannerSub, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()
			TweenService:Create(band, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
			task.delay(0.27, function() if myToken == bannerToken then holder.Visible = false end end)
		end)
	end
end

local CALLOUT_COLORS: { [string]: Color3 } = {
	["COUNTER HIT"] = T.ember, LAUNCH = T.gold, ["THROW ESCAPE"] = T.cool, THROW = Color3.fromRGB(196, 150, 255),
	PARRY = T.cool, ARMOR = Color3.fromRGB(255, 170, 90), CRUSH = Color3.fromRGB(150, 230, 120), EVADE = Color3.fromRGB(150, 230, 255),
	KNOCKDOWN = T.gold,
}
M.CALLOUT_COLORS = CALLOUT_COLORS
-- Small slanted call-out on one side (1 = left, 2 = right) or the centre (0).
local function callout(word: string, side: number)
	local stack = if side == 0 then refs.centerCallouts else refs.callouts[side]
	if not stack then return end
	calloutSerial += 1
	local color = CALLOUT_COLORS[word] or T.gold
	local chip = make("Frame", { Name = "Callout", BackgroundColor3 = color, BorderSizePixel = 0, Size = UDim2.fromOffset(0, 36), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = -calloutSerial, Parent = stack })
	make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 14), Parent = chip })
	local label = text(chip, "Text", word, T.display, 24, T.ink, { Size = UDim2.fromOffset(0, 36), AutomaticSize = Enum.AutomaticSize.X })
	local sc = make("UIScale", { Scale = 1.4, Parent = chip })
	TweenService:Create(sc, TweenInfo.new(0.16, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	task.delay(0.95, function()
		if not chip.Parent then return end
		TweenService:Create(chip, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(label, TweenInfo.new(0.2), { TextTransparency = 1 }):Play()
		task.delay(0.22, function() chip:Destroy() end)
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
	panel.Visible = guideShown and not touch
	local chip = refs.guideChip :: Frame
	if chip then
		if not guideShown and chip:GetAttribute("Device") ~= dev then chip:SetAttribute("Device", dev); fillChip(dev) end
		chip.Visible = not guideShown and not touch
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
function M._setTouchOverride(v: boolean?) touchOverride = v end
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
-- Public API
--------------------------------------------------------------------------------------------------------------------
function M.setVisible(b: boolean)
	hudVisible = b
	if root then root.Visible = b end
	if not b then guidePending = false end
end
-- Which slot the local player controls; its fighter is drawn on the left (bars swap for slot 2). Resets fight state.
function M.setViewSlot(slot: number)
	viewSlot = if slot == 2 then 2 else 1
	table.clear(tags)
	table.clear(playerNames)
	matchOverAt = nil
	resultShown = false
	if refs.bannerHolder then refs.bannerHolder.Visible = false end
	combo = { attacker = 1, hits = 0, damage = 0, shown = false, expiresAt = 0, counterUntil = 0 }
	lastComboHits = 0
	lastPhase = ""
	lastKO = false
	table.clear(inputHistory)
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
	b.name.TextColor3 = info.color:Lerp(WHITE, 0.12)
	local playerName = if info.playerName ~= nil then info.playerName else playerNames[side]
	if info.playerName ~= nil then playerNames[side] = info.playerName end
	b.player.Text = playerName or ""
	b.player.Visible = playerName ~= nil and playerName ~= ""
	tags[side] = info.tag
	if info.tag then b.tag.Text = info.tag end
	b.tag.BackgroundColor3 = if info.tag == "YOU" then T.gold elseif info.tag and string.sub(info.tag, 1, 3) == "CPU" then T.ember elseif info.tag == "DUMMY" then T.cool else T.muted
	b.color = info.color
	b.portraitStroke.Color = info.color
	b.edge.BackgroundColor3 = info.color
	if info.maxHealth then maxHealth[side] = info.maxHealth; health[side] = info.maxHealth; trail[side] = info.maxHealth end
	refreshPortrait(side, info.characterId)
end
function M.announce(kind: string, textValue: string?)
	local word = textValue or kind
	if kind == "Fight" then
		showBanner(word, T.ember, nil, 0.7)
	elseif kind == "KO" then
		showBanner(word, T.ember, nil, 1.3)
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
		local ok, roster = pcall(function() return require(ReplicatedStorage.FightingLab.Roster) end)
		name = if ok and id and roster.has(id) then roster.get(id).displayName else "P" .. winnerSlot
	end
	return string.upper(name :: string) .. " WINS"
end
function M.announceResult(winnerSlot: number)
	local word = M.resultText(winnerSlot)
	local mine = word == "YOU WIN"
	local loser = not mine and (tags[1] == "YOU" or tags[2] == "YOU") and word ~= "DRAW"
	showBanner(if loser then "DEFEAT" else word, if mine then T.gold elseif loser then T.loss else WHITE, if loser then word else nil, 0)
end
function M.popup(word: string, color: Color3?)
	if color then CALLOUT_COLORS[word] = CALLOUT_COLORS[word] or color end
	callout(word, 0)
end
-- The call-out (if any) for a combat event and the screen side it belongs to (0 = centre).
function M.calloutFor(e: CombatEvent): (string?, number)
	local attacker = if e.attacker == 1 or e.attacker == 2 then e.attacker else 1
	local side = sideOf(attacker)
	if e.kind == "Hit" and e.counter == true then return "COUNTER HIT", side end
	if e.kind == "Hit" and (e.launch == true or e.tier == "Launch") then return "LAUNCH", side end
	if e.kind == "ThrowBreak" then return "THROW ESCAPE", 0 end
	if e.kind == "ThrowHit" then return "THROW", side end
	if e.kind == "Parry" then return "PARRY", side end
	if e.kind == "Armor" then return "ARMOR", side end
	if e.kind == "Crush" then return "CRUSH", side end
	if e.kind == "Whiff" and e.evaded == true then
		local target = if e.target == 1 or e.target == 2 then e.target else 3 - attacker
		return "EVADE", sideOf(target)
	end
	return nil, 0
end
function M.onEvent(e: CombatEvent)
	combo = UIHelpers.registerCombo(combo, e, os.clock())
	if e.kind == "KO" then return end
	local word, side = M.calloutFor(e)
	if word then callout(word, side) end
end
function M.onSnapshot(entry: any)
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
				local ok, roster = pcall(function() return require(ReplicatedStorage.FightingLab.Roster) end)
				if ok and roster.has(f.characterId) then
					local def = roster.get(f.characterId)
					M.setFighterInfo(i, { displayName = def.displayName, color = def.accentColor, characterId = f.characterId, maxHealth = def.stats.maxHealth, tag = tags[side] })
				end
			end
			if f.maxHealth then maxHealth[side] = f.maxHealth end
			if f.health then health[side] = f.health end
		end
	end
end
function M.update(f: RenderFrame)
	if not root then return end
	local now = os.clock()
	local dt = if typeof(f.dt) == "number" then f.dt else 1 / 60
	for i, b in bars do
		local slotIndex = sideOf(i)
		trail[i] = UIHelpers.damageTrail(trail[i], health[i], dt, maxHealth[i])
		local ratio = UIHelpers.healthRatio(health[i], maxHealth[i]); local tr = UIHelpers.healthRatio(trail[i], maxHealth[i])
		b.fill.Size = UDim2.fromScale(ratio, 1); b.trail.Size = UDim2.fromScale(tr, 1)
		local lowHealth = ratio < 0.25
		b.fillGradient.Color = if lowHealth then ColorSequence.new(Color3.fromRGB(255, 150, 120), T.healthLow) else ColorSequence.new(Color3.fromRGB(255, 240, 170), Color3.fromRGB(240, 170, 40))
		b.low.BackgroundTransparency = if lowHealth and ratio > 0 then 0.8 + math.sin(now * 9) * 0.12 else 1
		for n, p in b.pips do
			local won = f.scores and f.scores[slotIndex] and n <= f.scores[slotIndex]
			p.BackgroundColor3 = if won then T.gold else Color3.fromRGB(30, 34, 46)
		end
	end
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
			if combo.hits ~= lastComboHits then
				lastComboHits = combo.hits
				cc.scale.Scale = 1.25
				TweenService:Create(cc.scale, TweenInfo.new(0.14, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			end
		end
	end
	if not visible then lastComboHits = 0 end
	-- Phase banners.
	if f.phase ~= lastPhase then
		if f.phase == "Ready" then
			local scores = f.scores or { 0, 0 }
			local final = (scores[1] or 0) == 1 and (scores[2] or 0) == 1
			if f.mode ~= "Training" then showBanner(if final then "FINAL ROUND" else "ROUND " .. tostring(f.round or 1), WHITE, nil, 1.0) end
		end
		if f.phase == "Fight" and lastPhase == "Ready" and f.mode ~= "Training" then M.announce("Fight", "FIGHT") end
		matchOverAt = if f.phase == "MatchOver" then now else nil
		resultShown = false
		lastPhase = f.phase
	end
	if f.ko and not lastKO then M.announce("KO", "K.O.") end
	lastKO = f.ko == true
	-- After the final K.O. beat, the winner stays announced until the session returns to the lobby.
	if matchOverAt and not resultShown and now - matchOverAt >= 1.5 then
		resultShown = true
		local scores = f.scores or { 0, 0 }
		local winnerSlot = if (scores[1] or 0) > (scores[2] or 0) then 1 elseif (scores[2] or 0) > (scores[1] or 0) then 2 else 0
		M.announceResult(winnerSlot)
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
end
return M
