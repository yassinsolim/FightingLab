--!strict
-- HudKit (round 6, look): the fight HUD's drawing pieces in the game's own "Ember & Steel" language: slanted
-- parallelogram shapes built from plain frames (a straight body plus two diagonal caps), the angled health bar with
-- its damage trail, Surge glow and sheen, slanted chips and round pips. Builders only touch the parent they are
-- given (server-side tests build them too); nothing is created on require.
--
-- A diagonal cap is a w x h frame whose UIGradient (rotation in pixels, through the frame centre) makes a hard
-- transparency step at 0.5, so exactly one corner triangle stays: "TL"/"BR" split on the "/" diagonal, "TR"/"BL" on
-- the "\" diagonal. Measured in Studio: UIGradient rotation is pixel-space and t = 0.5 is always the centre line.
local UIHelpers = require(script.Parent.UIHelpers)

local make = UIHelpers.make
local M = {}

local WHITE = Color3.new(1, 1, 1)
local STEP = 0.002

local function stepSequence(opaqueLow: boolean, baseTransparency: number?): NumberSequence
	local a = baseTransparency or 0
	local low, high = if opaqueLow then a else 1, if opaqueLow then 1 else a
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, low), NumberSequenceKeypoint.new(0.5 - STEP, low),
		NumberSequenceKeypoint.new(0.5, high), NumberSequenceKeypoint.new(1, high),
	})
end

-- Rotation and which half stays opaque for a corner triangle of a w x h cap.
function M.capGradient(w: number, h: number, keep: string): (number, boolean)
	local angle = math.deg(math.atan2(math.max(w, 0.01), math.max(h, 0.01)))
	if keep == "TL" then return angle, true end
	if keep == "BR" then return angle, false end
	if keep == "TR" then return -angle, false end
	return -angle, true -- "BL"
end

export type Cap = { frame: Frame, gradient: UIGradient, keep: string, alpha: number }

-- A diagonal corner-triangle cap (see the header). `alpha` is its background transparency.
function M.cap(parent: Instance, name: string, w: number, h: number, keep: string, color: Color3, alpha: number?, props: { [string]: any }?): Cap
	local f: Frame = make("Frame", { Name = name, BackgroundColor3 = color, BackgroundTransparency = 0, BorderSizePixel = 0, Size = UDim2.fromOffset(w, h), Parent = parent })
	local rotation, low = M.capGradient(w, h, keep)
	local g: UIGradient = make("UIGradient", { Rotation = rotation, Transparency = stepSequence(low, alpha), Parent = f })
	if props then for k, v in props do (f :: any)[k] = v end end
	return { frame = f, gradient = g, keep = keep, alpha = alpha or 0 }
end

function M.setCapAlpha(c: Cap, alpha: number)
	if math.abs(c.alpha - alpha) < 1e-3 then return end
	c.alpha = alpha
	local _, low = M.capGradient(c.frame.Size.X.Offset, c.frame.Size.Y.Offset, c.keep)
	c.gradient.Transparency = stepSequence(low, alpha)
end

export type Slab = { holder: Frame, body: Frame, left: Cap, right: Cap, color: Color3 }

-- A parallelogram (or trapezoid) w x h: body plus two caps. lean "/" or "\" (both ends parallel), or "A" (a
-- trapezoid wider at the bottom) / "V" (wider at the top). `slant` is the horizontal run of each cap.
function M.slab(parent: Instance, name: string, w: number, h: number, slant: number, lean: string, color: Color3, alpha: number?, props: { [string]: any }?): Slab
	local holder: Frame = make("Frame", { Name = name, BackgroundTransparency = 1, Size = UDim2.fromOffset(w, h), Parent = parent })
	local leftKeep, rightKeep = "BR", "TL"
	if lean == "\\" then leftKeep, rightKeep = "TR", "BL"
	elseif lean == "A" then leftKeep, rightKeep = "BR", "BL"
	elseif lean == "V" then leftKeep, rightKeep = "TR", "TL" end
	local body: Frame = make("Frame", { Name = "Body", BackgroundColor3 = color, BackgroundTransparency = alpha or 0, BorderSizePixel = 0, Position = UDim2.fromOffset(slant, 0), Size = UDim2.new(1, -2 * slant, 1, 0), Parent = holder })
	local left = M.cap(holder, "CapL", slant, h, leftKeep, color, alpha)
	local right = M.cap(holder, "CapR", slant, h, rightKeep, color, alpha, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0) })
	if props then for k, v in props do (holder :: any)[k] = v end end
	return { holder = holder, body = body, left = left, right = right, color = color }
end

function M.paintSlab(s: Slab, color: Color3, alpha: number?)
	s.color = color
	s.body.BackgroundColor3 = color
	s.left.frame.BackgroundColor3 = color
	s.right.frame.BackgroundColor3 = color
	if alpha then
		s.body.BackgroundTransparency = alpha
		M.setCapAlpha(s.left, alpha)
		M.setCapAlpha(s.right, alpha)
	end
end

-- A slanted text chip that grows with its text: label on a parallelogram (lean "/" by default).
export type Chip = { holder: Frame, label: TextLabel, slab: Slab, set: (text: string, color: Color3?, textColor: Color3?) -> () }
function M.chip(parent: Instance, name: string, text: string, height: number, font: Font, textSize: number, color: Color3, textColor: Color3, lean: string?, props: { [string]: any }?): Chip
	local slant = math.floor(height * 0.36 + 0.5)
	local holder: Frame = make("Frame", { Name = name, BackgroundTransparency = 1, Size = UDim2.fromOffset(60, height), Parent = parent })
	local slab = M.slab(holder, "Plate", 60, height, slant, lean or "/", color, 0, { Size = UDim2.fromScale(1, 1) })
	local label: TextLabel = UIHelpers.text(holder, "Text", text, font, textSize, textColor, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 2 })
	if props then for k, v in props do (holder :: any)[k] = v end end
	local function fit()
		local bounds = label.TextBounds.X
		holder.Size = UDim2.fromOffset(math.ceil(bounds + slant * 2 + height * 0.5), height)
	end
	local function set(t: string, c: Color3?, tc: Color3?)
		label.Text = t
		if c then M.paintSlab(slab, c) end
		if tc then label.TextColor3 = tc end
		fit()
	end
	label:GetPropertyChangedSignal("TextBounds"):Connect(fit)
	fit()
	return { holder = holder, label = label, slab = slab, set = set }
end

--------------------------------------------------------------------------------------------------------------------
-- Angled health bar
--------------------------------------------------------------------------------------------------------------------
export type Layer = { body: Frame, gradient: UIGradient?, outer: Cap, moving: Cap, color: Color3 }
export type HealthBar = {
	holder: Frame, back: Slab, halo: Slab, trail: Layer, fill: Layer, gloss: Frame, glowTop: Frame, glowBottom: Frame, sheen: Frame,
	sheenClip: Frame, ticks: Frame, low: Frame, right: boolean, width: number, height: number, slant: number,
	setRatios: (fill: number, trail: number) -> (), setFillColors: (outer: Color3, inner: Color3) -> (),
}

-- The bar runs from the outer end (portrait side) to the inner end (clock side). The left bar leans "/", the right
-- bar mirrors it ("\"). Health stays anchored at the outer end; damage removes it from the clock end.
function M.healthBar(parent: Instance, name: string, width: number, height: number, slant: number, right: boolean, props: { [string]: any }?): HealthBar
	local holder: Frame = make("Frame", { Name = name, BackgroundTransparency = 1, Size = UDim2.fromOffset(width, height), Parent = parent })
	local lean = if right then "\\" else "/"
	-- soft Surge aura above and below the bar (hidden until Surge)
	local glowTop: Frame = make("Frame", { Name = "GlowTop", BackgroundColor3 = Color3.fromRGB(255, 40, 70), BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromOffset(0, 2), Size = UDim2.new(1, 0, 0, 12), Visible = false, ZIndex = 0, Parent = holder })
	make("UIGradient", { Rotation = 90, Transparency = UIHelpers.ramp({ { 0, 1 }, { 1, 0.35 } }), Parent = glowTop })
	local glowBottom: Frame = make("Frame", { Name = "GlowBottom", BackgroundColor3 = Color3.fromRGB(255, 40, 70), BorderSizePixel = 0, Position = UDim2.new(0, 0, 1, -2), Size = UDim2.new(1, 0, 0, 12), Visible = false, ZIndex = 0, Parent = holder })
	make("UIGradient", { Rotation = 90, Transparency = UIHelpers.ramp({ { 0, 0.35 }, { 1, 1 } }), Parent = glowBottom })
	-- Surge halo: a slightly larger parallelogram behind the plate that pulses (hidden outside Surge)
	local haloSlant = slant * (height + 8) / height
	local halo = M.slab(holder, "Halo", width + 8, height + 8, haloSlant, lean, Color3.fromRGB(255, 46, 80), 1, { Position = UDim2.fromOffset(-4 - (haloSlant - slant) / 2, -4), ZIndex = 0 })
	for _, d in halo.holder:GetDescendants() do if d:IsA("GuiObject") then d.ZIndex = 0 end end
	local back = M.slab(holder, "Back", width, height, slant, lean, Color3.fromRGB(8, 10, 16), 0.12, { Size = UDim2.fromScale(1, 1), ZIndex = 1 })
	make("Frame", { Name = "Rim", BackgroundColor3 = WHITE, BackgroundTransparency = 0.8, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 1), ZIndex = 1, Parent = back.body })
	make("Frame", { Name = "Floor", BackgroundColor3 = WHITE, BackgroundTransparency = 0.9, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 1), ZIndex = 1, Parent = back.body })
	local inner = width - 2 * slant -- body length of a full bar
	local outerKeep = if right then "BL" else "BR"
	local movingKeep = if right then "TR" else "TL"
	local function layer(lname: string, color: Color3, z: number, gradient: boolean): Layer
		local body: Frame = make("Frame", { Name = lname, BackgroundColor3 = if gradient then WHITE else color, BorderSizePixel = 0, AnchorPoint = Vector2.new(if right then 1 else 0, 0), Position = if right then UDim2.new(1, -slant, 0, 0) else UDim2.fromOffset(slant, 0), Size = UDim2.fromOffset(inner, height), ZIndex = z, Parent = holder })
		local g: UIGradient? = if gradient then make("UIGradient", { Rotation = if right then 180 else 0, Color = ColorSequence.new(color), Parent = body }) else nil
		local outer = M.cap(holder, lname .. "Outer", slant, height, outerKeep, color, 0, { ZIndex = z, AnchorPoint = Vector2.new(if right then 1 else 0, 0), Position = if right then UDim2.fromScale(1, 0) else UDim2.fromScale(0, 0) })
		local moving = M.cap(holder, lname .. "Edge", slant, height, movingKeep, color, 0, { ZIndex = z })
		return { body = body, gradient = g, outer = outer, moving = moving, color = color }
	end
	local trail = layer("Trail", Color3.fromRGB(255, 120, 86), 2, false)
	local fill = layer("Fill", Color3.fromRGB(255, 214, 110), 3, true)
	-- thin gloss along the top of the fill, 10 % ticks, the low-health pulse and the Surge sheen (clipped to the body)
	local gloss: Frame = make("Frame", { Name = "Gloss", BackgroundColor3 = WHITE, BackgroundTransparency = 0.55, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 2), Position = UDim2.fromOffset(0, 2), ZIndex = 4, Parent = fill.body })
	local ticks: Frame = make("Frame", { Name = "Ticks", BackgroundTransparency = 1, Position = UDim2.fromOffset(slant, 0), Size = UDim2.new(1, -2 * slant, 1, 0), ZIndex = 5, Parent = holder })
	for i = 1, 9 do
		make("Frame", { Name = "Tick" .. i, BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.72, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(i / 10, 1), Size = UDim2.new(0, 2, if i == 5 then 0.6 else 0.35, 0), ZIndex = 5, Parent = ticks })
	end
	local low: Frame = make("Frame", { Name = "LowPulse", BackgroundColor3 = Color3.fromRGB(255, 76, 64), BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(slant, 0), Size = UDim2.new(1, -2 * slant, 1, 0), ZIndex = 4, Parent = holder })
	local sheenClip: Frame = make("Frame", { Name = "SheenClip", BackgroundTransparency = 1, ClipsDescendants = true, Size = UDim2.fromScale(1, 1), ZIndex = 6, Visible = false, Parent = fill.body })
	local sheen: Frame = make("Frame", { Name = "Sheen", BackgroundColor3 = WHITE, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.new(0, 46, 1, 0), ZIndex = 6, Parent = sheenClip })
	make("UIGradient", { Rotation = if right then -18 else 18, Transparency = UIHelpers.ramp({ { 0, 1 }, { 0.5, 0.45 }, { 1, 1 } }), Parent = sheen })
	if props then for k, v in props do (holder :: any)[k] = v end end

	local function place(l: Layer, ratio: number)
		local r = math.clamp(ratio, 0, 1)
		local len = inner * r
		l.body.Size = UDim2.fromOffset(len, height)
		local visible = r > 0.0005
		l.body.Visible = visible
		l.outer.frame.Visible = visible
		l.moving.frame.Visible = visible
		if right then
			l.moving.frame.Position = UDim2.new(1, -slant - len - slant, 0, 0)
		else
			l.moving.frame.Position = UDim2.fromOffset(slant + len, 0)
		end
	end
	local function setFillColors(outerColor: Color3, innerColor: Color3)
		fill.color = innerColor
		if fill.gradient then fill.gradient.Color = ColorSequence.new(outerColor, innerColor) end
		fill.outer.frame.BackgroundColor3 = outerColor
		fill.moving.frame.BackgroundColor3 = innerColor
	end
	local bar: HealthBar = {
		holder = holder, back = back, halo = halo, trail = trail, fill = fill, gloss = gloss, glowTop = glowTop, glowBottom = glowBottom,
		sheen = sheen, sheenClip = sheenClip, ticks = ticks, low = low, right = right, width = width, height = height, slant = slant,
		setRatios = function(f: number, t: number) place(fill, f); place(trail, math.max(t, f)) end,
		setFillColors = setFillColors,
	}
	bar.setRatios(1, 1)
	return bar
end

--------------------------------------------------------------------------------------------------------------------
-- Pure helpers (tests)
--------------------------------------------------------------------------------------------------------------------
-- The recent-damage trail: holds for `hold` seconds after the last hit, then drains toward the health.
export type TrailState = { value: number, holdUntil: number }
function M.stepTrail(state: TrailState, health: number, maxHealth: number, now: number, dt: number, hold: number?): TrailState
	local target = math.clamp(health, 0, maxHealth)
	if target >= state.value then return { value = target, holdUntil = state.holdUntil } end
	if now < state.holdUntil then return state end
	local speed = math.max(maxHealth * 0.3, (state.value - target) * 5)
	return { value = math.max(target, state.value - speed * math.max(dt, 0)), holdUntil = state.holdUntil }
end

-- Fill palette for a health ratio: calm gold, a hotter orange under 50 %, and the molten Surge colours.
function M.fillColors(ratio: number, surge: boolean): (Color3, Color3)
	if surge then return Color3.fromRGB(176, 16, 58), Color3.fromRGB(255, 92, 92) end
	if ratio < 0.25 then return Color3.fromRGB(214, 52, 40), Color3.fromRGB(255, 132, 92) end
	if ratio < 0.5 then return Color3.fromRGB(224, 112, 30), Color3.fromRGB(255, 196, 96) end
	return Color3.fromRGB(226, 150, 34), Color3.fromRGB(255, 236, 156)
end

return M
