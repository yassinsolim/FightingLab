--!strict
-- HudBanners (round 6, look): the fight HUD's big moments, in the game's own style: the round intro (ROUND n /
-- FINAL ROUND, then FIGHT), round ends (K.O. / DOUBLE K.O. / TIME / DRAW, PERFECT when the winner lost no health),
-- the winner presentation at match end, and the Ultimate: cinematic letterbox bars while a cinematic plays and a
-- title card on UltStart naming the fighter and the Ultimate (Roster.get(id).moves.Ultimate.name, "ULTIMATE" when the
-- move or its name is missing). Pure text helpers are exported for tests; builders only touch the frames given.
local TweenService = game:GetService("TweenService")
local UIHelpers = require(script.Parent.UIHelpers)
local HudKit = require(script.Parent.HudKit)

local T = UIHelpers.Theme
local make, text = UIHelpers.make, UIHelpers.text
local WHITE = Color3.new(1, 1, 1)

local M = {}

M.ULTIMATE_FALLBACK = "ULTIMATE"
M.ULT_TITLE_SECONDS = 2.1
M.COLORS = {
	ko = Color3.fromRGB(255, 70, 52), time = Color3.fromRGB(255, 200, 69), perfect = Color3.fromRGB(255, 214, 92),
	fight = Color3.fromRGB(255, 84, 51), round = WHITE, ult = Color3.fromRGB(255, 205, 82), draw = Color3.fromRGB(200, 210, 230),
}

--------------------------------------------------------------------------------------------------------------------
-- Pure text helpers
--------------------------------------------------------------------------------------------------------------------
-- "ROUND 2", or "FINAL ROUND" when both fighters are one win from the match.
function M.roundIntroText(round: number?, scores: { number }?, winsNeeded: number?): string
	local need = winsNeeded or 2
	local s = scores or { 0, 0 }
	if need > 1 and (s[1] or 0) == need - 1 and (s[2] or 0) == need - 1 then return "FINAL ROUND" end
	return "ROUND " .. tostring(round or 1)
end

-- Headline and optional sub-line for a round that just ended.
function M.roundEndText(reason: string?, winner: number?, perfect: boolean?): (string, string?)
	local w = winner or 0
	if reason == "TIME" then
		if w == 0 then return "DRAW", "TIME" end
		return "TIME", if perfect then "PERFECT" else nil
	end
	if w == 0 then return "DOUBLE K.O.", nil end
	return "K.O.", if perfect then "PERFECT" else nil
end

-- A round is perfect when its winner still has every point of health.
function M.isPerfect(winner: number?, fighters: { any }?): boolean
	if winner ~= 1 and winner ~= 2 then return false end
	local f = fighters and fighters[winner :: number]
	if not f or typeof(f.health) ~= "number" or typeof(f.maxHealth) ~= "number" then return false end
	return f.health >= f.maxHealth and f.maxHealth > 0
end

-- The Ultimate's display name for a fighter (never errors; "ULTIMATE" when the roster has no name for it).
function M.ultimateName(roster: any, characterId: any): string
	if typeof(characterId) ~= "string" or roster == nil then return M.ULTIMATE_FALLBACK end
	local ok, name = pcall(function()
		if roster.has and not roster.has(characterId) then return nil end
		local def = roster.get(characterId)
		local ult = def and def.moves and def.moves.Ultimate
		return if ult and typeof(ult.name) == "string" and ult.name ~= "" then ult.name else nil
	end)
	return if ok and typeof(name) == "string" then string.upper(name) else M.ULTIMATE_FALLBACK
end

--------------------------------------------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------------------------------------------
export type Banners = {
	stage: Frame, root: Frame, centre: Frame, band: Frame, bandLine: Frame, word: TextLabel, wordScale: UIScale, sub: TextLabel,
	flash: Frame, letterTop: Frame, letterBottom: Frame, ult: Frame, ultFighter: TextLabel, ultName: TextLabel, ultBand: Frame,
	ultSweep: Frame, ultScale: UIScale, winner: Frame, winnerTitle: TextLabel, winnerName: TextLabel, winnerPlayer: TextLabel,
	winnerScore: TextLabel, winnerBar: Frame, token: number, ultToken: number, cinematic: boolean,
}

function M.build(stage: Frame, root: Frame): Banners
	-- full-screen pieces live on the unscaled root (they must cover the whole screen). The letterbox sits BEHIND the
	-- scaled stage (ZIndex 0 vs the stage's 1), so the bars stay readable on the black bands during a cinematic.
	local flash: Frame = make("Frame", { Name = "Flash", BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(0, -80), Size = UDim2.new(1, 0, 1, 160), ZIndex = 40, Parent = root })
	local letterTop: Frame = make("Frame", { Name = "LetterboxTop", BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromOffset(0, -80), Size = UDim2.new(1, 0, 0.13, 80), ZIndex = 0, Visible = false, Parent = root })
	local letterBottom: Frame = make("Frame", { Name = "LetterboxBottom", BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Position = UDim2.new(0, 0, 1, 80), Size = UDim2.new(1, 0, 0.11, 80), ZIndex = 0, Visible = false, Parent = root })
	-- centre banner: a slanted dark band sweeps in under the word
	local centre: Frame = make("Frame", { Name = "BannerHolder", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.new(1, 0, 0, 170), Visible = false, ZIndex = 20, Parent = stage })
	local band: Frame = make("Frame", { Name = "Band", BackgroundColor3 = T.bg, BackgroundTransparency = 0.18, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 0, 0, 112), ZIndex = 20, Parent = centre })
	make("UIGradient", { Transparency = UIHelpers.ramp({ { 0, 1 }, { 0.18, 0.1 }, { 0.82, 0.1 }, { 1, 1 } }), Parent = band })
	local bandLine: Frame = make("Frame", { Name = "Line", BackgroundColor3 = T.ember, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.new(0.66, 0, 0, 4), ZIndex = 21, Parent = band })
	make("UIGradient", { Transparency = UIHelpers.ramp({ { 0, 1 }, { 0.5, 0 }, { 1, 1 } }), Parent = bandLine })
	make("Frame", { Name = "LineTop", BackgroundColor3 = WHITE, BackgroundTransparency = 0.6, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0.5, 0, 0, 2), ZIndex = 21, Parent = band })
	local word = text(centre, "Banner", "", T.display, 104, WHITE, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.47), Size = UDim2.new(1, 0, 0, 124), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 22 })
	UIHelpers.textStroke(word, 0.15, 3.5)
	local wordScale: UIScale = make("UIScale", { Parent = word })
	local sub = text(centre, "Sub", "", T.title, 30, T.gold, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, -30), Size = UDim2.new(1, 0, 0, 34), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 22 })
	UIHelpers.textStroke(sub, 0.3, 2)
	-- Ultimate title card: a long slanted band with the fighter's name over the Ultimate's name
	local ult: Frame = make("Frame", { Name = "UltimateCard", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.74), Size = UDim2.fromOffset(820, 118), Visible = false, ZIndex = 32, Parent = stage })
	local ultBand: Frame = make("Frame", { Name = "Band", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 32, Parent = ult })
	local slab = HudKit.slab(ultBand, "Plate", 820, 92, 34, "/", Color3.fromRGB(10, 10, 16), 0.08, { Position = UDim2.fromOffset(0, 22), ZIndex = 32 })
	for _, d in slab.holder:GetDescendants() do if d:IsA("GuiObject") then d.ZIndex = 32 end end
	local accent = HudKit.slab(ultBand, "Accent", 820, 5, 2, "/", M.COLORS.ult, 0, { Position = UDim2.fromOffset(-6, 112), ZIndex = 33 })
	for _, d in accent.holder:GetDescendants() do if d:IsA("GuiObject") then d.ZIndex = 33 end end
	local ultFighter = text(ult, "Fighter", "", T.title, 26, T.ember, { Position = UDim2.fromOffset(64, 0), Size = UDim2.fromOffset(600, 30), ZIndex = 34 })
	UIHelpers.textStroke(ultFighter, 0.25, 2)
	local ultName = text(ult, "UltName", "", T.display, 60, M.COLORS.ult, { Position = UDim2.fromOffset(52, 30), Size = UDim2.fromOffset(740, 70), ZIndex = 34, TextScaled = true })
	make("UITextSizeConstraint", { MaxTextSize = 60, Parent = ultName })
	UIHelpers.textStroke(ultName, 0.2, 2.5)
	local ultSweepClip: Frame = make("Frame", { Name = "SweepClip", BackgroundTransparency = 1, ClipsDescendants = true, Position = UDim2.fromOffset(34, 22), Size = UDim2.fromOffset(752, 92), ZIndex = 35, Parent = ult })
	local ultSweep: Frame = make("Frame", { Name = "Sweep", BackgroundColor3 = WHITE, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(-0.2, 0), Size = UDim2.new(0, 120, 1, 0), ZIndex = 35, Parent = ultSweepClip })
	make("UIGradient", { Rotation = 20, Transparency = UIHelpers.ramp({ { 0, 1 }, { 0.5, 0.55 }, { 1, 1 } }), Parent = ultSweep })
	local ultScale: UIScale = make("UIScale", { Parent = ult })
	-- winner presentation: a wide card across the middle of the screen
	local winner: Frame = make("Frame", { Name = "WinnerCard", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 0, 0, 230), Visible = false, ZIndex = 24, Parent = stage })
	local wband: Frame = make("Frame", { Name = "Band", BackgroundColor3 = T.bg, BackgroundTransparency = 0.12, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 24, Parent = winner })
	make("UIGradient", { Transparency = UIHelpers.ramp({ { 0, 1 }, { 0.12, 0.08 }, { 0.88, 0.08 }, { 1, 1 } }), Parent = wband })
	local winnerBar: Frame = make("Frame", { Name = "Accent", BackgroundColor3 = T.gold, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0.7, 0, 0, 4), ZIndex = 25, Parent = winner })
	make("UIGradient", { Transparency = UIHelpers.ramp({ { 0, 1 }, { 0.5, 0 }, { 1, 1 } }), Parent = winnerBar })
	local winnerTitle = text(winner, "Title", "", T.display, 92, T.gold, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 16), Size = UDim2.new(1, 0, 0, 100), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 26 })
	UIHelpers.textStroke(winnerTitle, 0.2, 3)
	local winnerName = text(winner, "Fighter", "", T.title, 34, WHITE, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 118), Size = UDim2.new(1, 0, 0, 40), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 26 })
	UIHelpers.textStroke(winnerName, 0.3, 2)
	local winnerPlayer = text(winner, "Player", "", T.bold, 18, T.muted, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 158), Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 26 })
	local winnerScore = text(winner, "Score", "", T.number, 24, WHITE, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 184), Size = UDim2.new(1, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 26 })
	return {
		stage = stage, root = root, centre = centre, band = band, bandLine = bandLine, word = word, wordScale = wordScale, sub = sub,
		flash = flash, letterTop = letterTop, letterBottom = letterBottom, ult = ult, ultFighter = ultFighter, ultName = ultName,
		ultBand = ultBand, ultSweep = ultSweep, ultScale = ultScale, winner = winner, winnerTitle = winnerTitle,
		winnerName = winnerName, winnerPlayer = winnerPlayer, winnerScore = winnerScore, winnerBar = winnerBar, token = 0, ultToken = 0,
		cinematic = false,
	}
end

local function tween(inst: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	TweenService:Create(inst, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goal):Play()
end

function M.flash(b: Banners, strength: number?, seconds: number?)
	b.flash.BackgroundTransparency = 1 - math.clamp(strength or 0.5, 0, 1)
	tween(b.flash, seconds or 0.35, { BackgroundTransparency = 1 })
end

-- Big centre word with an optional sub-line; `hold` seconds then fades (0 = stays until replaced).
function M.show(b: Banners, word: string, color: Color3, sub: string?, hold: number?, punch: number?)
	b.token += 1
	local myToken = b.token
	b.word.Text = word
	b.word.TextColor3 = color
	b.word.TextTransparency = 0
	b.sub.Text = sub or ""
	b.sub.TextTransparency = 0
	b.bandLine.BackgroundColor3 = if color == WHITE then T.ember else color
	b.centre.Visible = true
	b.band.Size = UDim2.new(0, 0, 0, 112)
	b.band.BackgroundTransparency = 0.18
	tween(b.band, 0.2, { Size = UDim2.new(1, 0, 0, 112) }, Enum.EasingStyle.Quint)
	b.wordScale.Scale = punch or 1.45
	tween(b.wordScale, 0.26, { Scale = 1 }, Enum.EasingStyle.Back)
	if hold and hold > 0 then
		task.delay(hold, function()
			if myToken ~= b.token then return end
			tween(b.word, 0.25, { TextTransparency = 1 })
			tween(b.sub, 0.25, { TextTransparency = 1 })
			tween(b.band, 0.25, { BackgroundTransparency = 1 })
			task.delay(0.27, function() if myToken == b.token then b.centre.Visible = false end end)
		end)
	end
end

function M.hideCentre(b: Banners)
	b.token += 1
	b.centre.Visible = false
end

-- Letterbox bars for an Ultimate cinematic (slide in / out). The top band reaches under the top-bar inset.
function M.setCinematic(b: Banners, on: boolean)
	if b.cinematic == on then return end
	b.cinematic = on
	if on then
		b.letterTop.Visible = true
		b.letterBottom.Visible = true
	end
	tween(b.letterTop, if on then 0.22 else 0.35, { Position = if on then UDim2.new(0, 0, 0.13, 0) else UDim2.fromOffset(0, -80) }, Enum.EasingStyle.Quart)
	tween(b.letterBottom, if on then 0.22 else 0.35, { Position = if on then UDim2.new(0, 0, 0.89, 0) else UDim2.new(0, 0, 1, 80) }, Enum.EasingStyle.Quart)
	if not on then
		task.delay(0.36, function()
			if not b.cinematic then
				b.letterTop.Visible = false
				b.letterBottom.Visible = false
			end
		end)
	end
end

-- The Ultimate title card: fighter name (accent colour) over the Ultimate's name, swept by a light.
function M.showUltimate(b: Banners, fighterName: string, ultName: string, accent: Color3?, fromRight: boolean?)
	b.ultToken += 1
	local myToken = b.ultToken
	b.ultFighter.Text = string.upper(fighterName)
	b.ultFighter.TextColor3 = accent or T.ember
	b.ultName.Text = ultName
	b.ultName.TextTransparency = 0
	b.ultFighter.TextTransparency = 0
	b.ult.Visible = true
	local x = if fromRight then 1.25 else -0.25
	b.ult.Position = UDim2.fromScale(x, 0.74)
	tween(b.ult, 0.28, { Position = UDim2.fromScale(0.5, 0.74) }, Enum.EasingStyle.Quint)
	b.ultScale.Scale = 1.08
	tween(b.ultScale, 0.5, { Scale = 1 }, Enum.EasingStyle.Quad)
	b.ultSweep.Position = UDim2.fromScale(-0.2, 0)
	task.delay(0.25, function()
		if myToken == b.ultToken then tween(b.ultSweep, 0.7, { Position = UDim2.fromScale(1.2, 0) }, Enum.EasingStyle.Sine) end
	end)
	task.delay(M.ULT_TITLE_SECONDS, function()
		if myToken ~= b.ultToken then return end
		tween(b.ult, 0.3, { Position = UDim2.fromScale(if fromRight then -0.25 else 1.25, 0.74) }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		task.delay(0.32, function() if myToken == b.ultToken then b.ult.Visible = false end end)
	end)
end

function M.hideUltimate(b: Banners)
	b.ultToken += 1
	b.ult.Visible = false
end

-- Winner presentation (held until hidden): title (YOU WIN / DEFEAT / <NAME> WINS / DRAW), fighter, player, score.
function M.showWinner(b: Banners, title: string, color: Color3, fighter: string, player: string?, score: string?)
	b.winnerTitle.Text = title
	b.winnerTitle.TextColor3 = color
	b.winnerBar.BackgroundColor3 = color
	b.winnerName.Text = string.upper(fighter)
	b.winnerPlayer.Text = player or ""
	b.winnerScore.Text = score or ""
	b.winner.Visible = true
	b.winner.Size = UDim2.new(1, 0, 0, 0)
	tween(b.winner, 0.3, { Size = UDim2.new(1, 0, 0, 230) }, Enum.EasingStyle.Quint)
end

function M.hideAll(b: Banners)
	b.token += 1
	b.ultToken += 1
	b.centre.Visible = false
	b.ult.Visible = false
	b.winner.Visible = false
	b.flash.BackgroundTransparency = 1
	b.cinematic = false
	b.letterTop.Position = UDim2.fromOffset(0, -80)
	b.letterBottom.Position = UDim2.new(0, 0, 1, 80)
	b.letterTop.Visible = false
	b.letterBottom.Visible = false
end

return M
