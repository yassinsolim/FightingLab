--!strict
-- Fight HUD (OV6, round 6 restyle): call-outs from combat events (COUNTER HIT / PUNISH / LAUNCH / THROW ESCAPE /
-- EVADE / SURGE...), the own fighter on the left (setViewSlot), result text, the controls guide auto-show rules, the
-- angled bars (trail, pips, low pulse), Contract A (Surge glow + SURGE tag, the ULTIMATE indicator with its key, the
-- UltStart title card and the cinematic letterbox; nothing without the fields), the round intro / K.O. / TIME /
-- PERFECT texts, the stance chip and the phone layout.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lab = ReplicatedStorage:WaitForChild("FightingLab")
local Client = Lab:WaitForChild("Client")
local Hud = require(Client:WaitForChild("HudController"))
local HudKit = require(Client:WaitForChild("HudKit"))
local HudBanners = require(Client:WaitForChild("HudBanners"))
local UIHelpers = require(Client:WaitForChild("UIHelpers"))
local Runner = require(game:GetService("ServerStorage").UnitTest.RunUnitTest)

local function frame(overrides: { [string]: any }?): any
	local f: { [string]: any } = { dt = 1 / 60, mode = "Match", timer = 45 * 60, config = { FPS = 60, WinsNeeded = 2 }, scores = { 0, 0 }, phase = "Fight", round = 1, ko = false, session = "Fight", authority = "Server", paused = false, winner = 0, reason = "" }
	if overrides then for k, v in overrides do f[k] = v end end
	return f
end

-- A fresh HUD in a throwaway ScreenGui; returns it and a cleanup. Keyboard behaviour is forced so the guide rules
-- hold even when the Studio device simulator emulates a phone.
local function hud(): (ScreenGui, () -> ())
	local holder = Instance.new("Folder")
	local gui = Instance.new("ScreenGui"); gui.Parent = holder
	Hud.init({ gui = gui, modules = {} })
	Hud._resetForTests()
	Hud._setTouchOverride(false)
	return gui, function() Hud.setVisible(false); Hud._setTouchOverride(nil); UIHelpers._setControlsForTests(nil); holder:Destroy() end
end

local function info(name: string, tag: string): any
	return { displayName = name, color = Color3.new(1, 0.5, 0.2), characterId = "", maxHealth = 100, playerName = if tag == "YOU" then "Tester" else "", tag = tag }
end

local function run(t: Runner.T, body: (ScreenGui) -> ())
	local gui, cleanup = hud()
	local ok, err = pcall(body, gui)
	cleanup()
	if not ok then error(err, 0) end
end

local function snap(frameNo: number, f1: { [string]: any }, f2: { [string]: any }): any
	local a: { [string]: any } = { characterId = "", health = 100, maxHealth = 100, state = "Idle" }
	local b: { [string]: any } = { characterId = "", health = 100, maxHealth = 100, state = "Idle" }
	for k, v in f1 do a[k] = v end
	for k, v in f2 do b[k] = v end
	return { frame = frameNo, p2Human = false, fighters = { a, b } }
end

return function(t: Runner.T)
	t.test("combat events map to call-outs on the right side", function()
		run(t, function()
			Hud.setViewSlot(1)
			local word, side = Hud.calloutFor({ kind = "Hit", attacker = 1, target = 2, counter = true })
			t.expect.equal(word, "COUNTER HIT"); t.expect.equal(side, 1)
			word, side = Hud.calloutFor({ kind = "Hit", attacker = 2, target = 1, launch = true })
			t.expect.equal(word, "LAUNCH"); t.expect.equal(side, 2)
			word, side = Hud.calloutFor({ kind = "ThrowBreak", attacker = 2, target = 1 })
			t.expect.equal(word, "THROW ESCAPE"); t.expect.equal(side, 0)
			word, side = Hud.calloutFor({ kind = "Whiff", attacker = 2, target = 1, evaded = true })
			t.expect.equal(word, "EVADE"); t.expect.equal(side, 1, "an evade is credited to the evader")
			word, side = Hud.calloutFor({ kind = "Surge", attacker = 2, target = 2 })
			t.expect.equal(word, "SURGE"); t.expect.equal(side, 2, "Surge shows on the surging fighter's side")
			t.expect.equal((Hud.calloutFor({ kind = "Hit", attacker = 1, target = 2 })), nil, "plain hits stay quiet")
			t.expect.equal((Hud.calloutFor({ kind = "Block", attacker = 1, target = 2 })), nil)
			t.expect.equal((Hud.calloutFor({ kind = "UltStart", attacker = 1, target = 2 })), nil, "the Ultimate gets its card, not a chip")
			-- The local player is slot 2: its events are drawn on the left.
			Hud.setViewSlot(2)
			word, side = Hud.calloutFor({ kind = "Hit", attacker = 2, target = 1, counter = true })
			t.expect.equal(side, 1, "own counter hit shows on the left for a slot-2 player")
		end)
	end)

	t.test("a first hit on a fighter in recovery reads as a PUNISH (also when the event drains late)", function()
		run(t, function()
			Hud.setViewSlot(1)
			Hud.onSnapshot(snap(200, {}, { state = "Recovery" }))
			Hud.onSnapshot(snap(201, {}, { state = "Hitstun" }))
			Hud.onSnapshot(snap(202, {}, { state = "Hitstun" }))
			local word, side = Hud.calloutFor({ kind = "Hit", attacker = 1, target = 2, combo = 1, frame = 201 })
			t.expect.equal(word, "PUNISH", "the target was recovering on the frame before the hit")
			t.expect.equal(side, 1)
			t.expect.equal((Hud.calloutFor({ kind = "Hit", attacker = 1, target = 2, combo = 2, frame = 201 })), nil, "combo follow-ups are not punishes")
			Hud.onSnapshot(snap(300, {}, { state = "Walk" }))
			t.expect.equal((Hud.calloutFor({ kind = "Hit", attacker = 1, target = 2, combo = 1, frame = 301 })), nil, "a hit on a walking fighter is not a punish")
			t.expect.equal((Hud.calloutFor({ kind = "Hit", attacker = 1, target = 2, combo = 1, frame = 301, punish = true })), "PUNISH", "an explicit punish flag wins")
		end)
	end)

	t.test("events create slanted call-out chips and combos count with damage on the attacker's side", function()
		run(t, function(gui)
			Hud.setViewSlot(1)
			Hud.setFighterInfo(1, info("KAEL", "YOU"))
			Hud.setFighterInfo(2, info("GORAN", "CPU · HARD"))
			Hud.setVisible(true)
			local stage = (gui :: any).FightHud.Stage
			Hud.onEvent({ kind = "Hit", attacker = 1, target = 2, combo = 1, damage = 10, counter = true })
			local chip = stage.Callouts1:FindFirstChild("Callout")
			t.expect.truthy(chip ~= nil, "counter hit chip on the left")
			t.expect.equal(chip and chip.Text.Text, "COUNTER HIT")
			t.expect.truthy(chip and chip:FindFirstChild("Plate") and chip.Plate:FindFirstChild("CapL"), "the chip is a slanted plate")
			Hud.onEvent({ kind = "ThrowBreak", attacker = 2, target = 1, combo = 0, damage = 0 })
			t.expect.truthy(stage.CenterCallouts:FindFirstChild("Callout") ~= nil, "throw escape in the centre")
			for i = 2, 4 do Hud.onEvent({ kind = "Hit", attacker = 1, target = 2, combo = i, damage = 8 }) end
			Hud.update(frame())
			t.expect.truthy(stage.Combo1.Visible, "combo counter on the attacker's side")
			t.expect.falsy(stage.Combo2.Visible)
			t.expect.equal(stage.Combo1.Count.Text, "4")
			t.expect.equal(stage.Combo1.Damage.Text, "34 DAMAGE", "10 + 3 x 8")
			t.expect.equal(stage.Combo1.Kind.Text, "COUNTER", "the hit type rides with the count")
			t.expect.equal(stage.HudFighter1.NameRow.TagPlate.Slot.Text, "YOU")
			t.expect.equal(stage.HudFighter2.NameRow.TagPlate.Slot.Text, "CPU · HARD")
		end)
	end)

	t.test("result text names the winner from the local player's point of view", function()
		run(t, function()
			Hud.setViewSlot(2)
			Hud.setFighterInfo(1, info("GORAN", "P1"))
			Hud.setFighterInfo(2, info("NIA", "YOU"))
			t.expect.equal(Hud.resultText(2), "YOU WIN", "slot 2 is the local player")
			t.expect.equal(Hud.resultText(0), "DRAW")
			t.expect.equal(Hud.getViewSlot(), 2)
		end)
	end)

	t.test("controls guide opens by itself in the first fight and the first practice only (Auto)", function()
		run(t, function(gui)
			gui:SetAttribute("ControlsGuide", nil)
			t.expect.equal(Hud.guideMode(), "Auto")
			Hud.setViewSlot(1); Hud.setVisible(true); Hud.update(frame())
			t.expect.truthy(Hud.guideVisible(), "first fight shows the guide")
			Hud.toggleGuide()
			t.expect.falsy(Hud.guideVisible(), "G hides it")
			Hud.setViewSlot(1); Hud.update(frame())
			t.expect.falsy(Hud.guideVisible(), "second fight does not reopen it")
			Hud.setViewSlot(1); Hud.update(frame({ session = "Practice", authority = "Local", mode = "Training" }))
			t.expect.truthy(Hud.guideVisible(), "first practice shows it")
			Hud.toggleGuide()
			gui:SetAttribute("ControlsGuide", "Off")
			Hud._resetForTests()
			Hud.setViewSlot(1); Hud.update(frame())
			t.expect.falsy(Hud.guideVisible(), "Off never opens it")
			gui:SetAttribute("ControlsGuide", "On")
			Hud.setViewSlot(1); Hud.update(frame())
			t.expect.truthy(Hud.guideVisible(), "On opens it every fight")
			Hud.toggleGuide()
			Hud.setViewSlot(1); Hud.update(frame())
			t.expect.truthy(Hud.guideVisible(), "On opens it again next fight")
			local stage = (gui :: any).FightHud.Stage
			t.expect.truthy(stage.ControlsGuide.Visible)
			Hud.toggleGuide()
			Hud.update(frame())
			t.expect.falsy(stage.ControlsGuide.Visible)
			t.expect.truthy(stage.GuideChip.Visible, "a small chip reminds the guide key")
		end)
	end)

	t.test("timer, round pips, angled bars and the low-health warning follow the frame", function()
		run(t, function(gui)
			Hud.setViewSlot(1)
			Hud.setFighterInfo(1, info("KAEL", "YOU"))
			Hud.setFighterInfo(2, info("GORAN", "CPU"))
			Hud.setVisible(true)
			Hud.onSnapshot({ fighters = { { characterId = "", health = 20, maxHealth = 100 }, { characterId = "", health = 90, maxHealth = 100 } } })
			Hud.update(frame({ timer = 9 * 60, scores = { 1, 0 } }))
			local stage = (gui :: any).FightHud.Stage
			t.expect.equal(stage.TimerPlate.Timer.Text, "09")
			t.expect.equal(stage.TimerPlate.Pips1.Pip1:GetAttribute("Won"), true, "P1's first round is won")
			t.expect.equal(stage.TimerPlate.Pips2.Pip1:GetAttribute("Won"), false)
			local bar = stage.HudFighter1.Bar
			t.expect.truthy(bar.LowPulse.BackgroundTransparency < 1, "low health pulses (no Surge field)")
			t.expect.equal(stage.HudFighter2.Bar.LowPulse.BackgroundTransparency, 1)
			t.expect.near(bar.Fill.Size.X.Offset / (HudKit.healthBar ~= nil and (Hud.LAYOUT.barWidth - 26) or 1), 0.2, 0.02, "fill at 20 %")
			t.expect.truthy(bar.FillEdge.Visible and bar.FillOuter.Visible, "both slanted ends drawn")
			t.expect.truthy(bar.Trail.Size.X.Offset >= bar.Fill.Size.X.Offset, "the damage trail never trails behind the health")
			Hud.update(frame({ mode = "Training" }))
			t.expect.equal(stage.TimerPlate.Mode.Text, "TRAINING")
			Hud.onSnapshot({ fighters = { { characterId = "", health = 0, maxHealth = 100 }, { characterId = "", health = 90, maxHealth = 100 } } })
			Hud.update(frame())
			t.expect.falsy(bar.FillEdge.Visible, "an empty bar draws no fill ends")
		end)
	end)

	t.test("the recent-damage trail holds after a hit, then drains to the health", function()
		local s: HudKit.TrailState = { value = 100, holdUntil = 10 }
		s = HudKit.stepTrail(s, 60, 100, 9.8, 0.1)
		t.expect.equal(s.value, 100, "held during the hold time")
		s = HudKit.stepTrail(s, 60, 100, 10.1, 0.1)
		t.expect.truthy(s.value < 100 and s.value >= 60, "drains after it")
		for _ = 1, 60 do s = HudKit.stepTrail(s, 60, 100, 11, 1 / 60) end
		t.expect.equal(s.value, 60, "settles on the health")
		s = HudKit.stepTrail(s, 80, 100, 12, 1 / 60)
		t.expect.equal(s.value, 80, "a heal (new round) snaps the trail up")
		local outer, inner = HudKit.fillColors(0.2, true)
		local calmOuter = HudKit.fillColors(0.9, false)
		t.expect.truthy(outer ~= calmOuter and inner ~= outer, "Surge has its own molten palette")
	end)

	t.test("Contract A: Surge and the ULTIMATE indicator follow the snapshot fields, and nothing shows without them", function()
		run(t, function(gui)
			UIHelpers._setControlsForTests({
				fight = { keyboard = { ultimate = "L", guide = "G" }, gamepad = { ultimate = "ButtonR2" } },
				notation = { lp = "1", rp = "2", lk = "3", rk = "4", ultimate = "1+2" },
				label = function(_g: string, action: string, device: string?): string
					if action == "ultimate" then return if device == "gamepad" then "RT" else "L" end
					return ""
				end,
			})
			Hud.setViewSlot(1)
			Hud.setFighterInfo(1, info("KAEL", "YOU"))
			Hud.setFighterInfo(2, info("GORAN", "CPU"))
			Hud.setVisible(true)
			local stage = (gui :: any).FightHud.Stage
			local s1, s2 = stage.HudFighter1.Status, stage.HudFighter2.Status
			-- a build without the Ultimate: no fields at all
			Hud.onSnapshot(snap(1, { health = 20 }, {}))
			Hud.update(frame())
			t.expect.falsy(s1.Surge.Visible, "no SURGE without the field")
			t.expect.falsy(s1.Ultimate.Visible, "no ULTIMATE without the field")
			t.expect.falsy(stage.HudFighter1.Bar.GlowTop.Visible)
			-- Surge, Ultimate not used yet
			Hud.onSnapshot(snap(2, { health = 20, surge = true, ultUsed = false }, { surge = false, ultUsed = false }))
			Hud.update(frame())
			t.expect.truthy(s1.Surge.Visible, "SURGE tag")
			t.expect.truthy(s1.Ultimate.Visible, "ULTIMATE ready")
			t.expect.truthy(stage.HudFighter1.Bar.GlowTop.Visible, "the bar glows")
			t.expect.truthy(stage.HudFighter1.Bar.Halo.Body.BackgroundTransparency < 1, "the halo pulses round the bar")
			t.expect.falsy(s2.Surge.Visible); t.expect.falsy(s2.Ultimate.Visible)
			t.expect.equal(s1.Ultimate.Text.Text, "ULTIMATE")
			local keyLabel = s1.Ultimate.Key:FindFirstChildWhichIsA("Frame", true)
			t.expect.truthy(keyLabel ~= nil, "the key glyph is drawn")
			t.expect.equal(Hud.ultimateKey("keyboard"), "L", "keyboard key from Controls")
			t.expect.equal(Hud.ultimateKey("gamepad"), "RT", "gamepad key from Controls")
			t.expect.equal(Hud.ultimateKey("touch"), "", "no key on touch")
			-- the Ultimate was used: Surge has ended, nothing remains
			Hud.onSnapshot(snap(3, { health = 20, surge = false, ultUsed = true }, {}))
			Hud.update(frame())
			t.expect.falsy(s1.Surge.Visible); t.expect.falsy(s1.Ultimate.Visible, "used this round")
			-- Controls without an ultimate binding: the notation stands in
			UIHelpers._setControlsForTests({ fight = { keyboard = {}, gamepad = {} }, notation = { ultimate = "1+2" }, label = function() return "" end })
			t.expect.equal(Hud.ultimateKey("keyboard"), "1+2")
			t.expect.equal(Hud.statusFor(nil, nil), false)
			local inSurge, ready = Hud.statusFor(true, nil)
			t.expect.truthy(inSurge and ready, "ultUsed absent counts as not used")
		end)
	end)

	t.test("only the local player's side shows the Ultimate key; a dummy or CPU in Surge gets a plain ULTIMATE tag", function()
		run(t, function(gui)
			UIHelpers._setControlsForTests({
				fight = { keyboard = { ultimate = "L", guide = "G" }, gamepad = { ultimate = "ButtonR2" } },
				notation = { lp = "1", rp = "2", lk = "3", rk = "4", ultimate = "1+2" },
				label = function(_g: string, action: string, device: string?): string
					if action == "ultimate" then return if device == "gamepad" then "RT" else "L" end
					return ""
				end,
			})
			-- Free Training after a few Ultimates: the dummy drops into Surge too; as P1 and as P2 (own fighter on the left)
			for _, view in { 1, 2 } do
				Hud.setViewSlot(view)
				Hud.setFighterInfo(view, info("KAEL", "YOU"))
				Hud.setFighterInfo(3 - view, info("SIERRA", "DUMMY"))
				Hud.setVisible(true)
				local stage = (gui :: any).FightHud.Stage
				local own, other = stage.HudFighter1.Status.Ultimate, stage.HudFighter2.Status.Ultimate
				Hud.onSnapshot(snap(10 + view, { health = 20, surge = true, ultUsed = false }, { health = 20, surge = true, ultUsed = false }))
				Hud.update(frame({ mode = "Training", session = "Practice", authority = "Local" }))
				t.expect.truthy(own.Visible and other.Visible, "both sides show a ready Ultimate (view " .. view .. ")")
				t.expect.truthy(own.Key.Visible and own.Key:FindFirstChildWhichIsA("Frame", true) ~= nil, "own side: the key to press")
				t.expect.equal(own:GetAttribute("KeyShown"), true)
				t.expect.falsy(other.Key.Visible, "the opponent's side shows no key (view " .. view .. ")")
				t.expect.equal(other.Key:FindFirstChildWhichIsA("GuiObject", true), nil, "no glyph on the opponent's side")
				t.expect.equal(other:GetAttribute("KeyShown"), false)
				t.expect.equal(other.Text.Text, "ULTIMATE")
			end
		end)
	end)

	t.test("status chips stay compact and never lower than the name row (tall fighters' heads stay clear)", function()
		run(t, function(gui)
			Hud.setViewSlot(1)
			Hud.setVisible(true)
			local stage = (gui :: any).FightHud.Stage
			local L = Hud.LAYOUT
			for i = 1, 2 do
				local group = stage["HudFighter" .. i]
				local status, nameRow = group.Status, group.NameRow
				local statusTop = status.Position.Y.Offset
				local statusBottom = statusTop + status.Size.Y.Offset
				local nameBottom = nameRow.Position.Y.Offset + nameRow.Size.Y.Offset
				t.expect.truthy(statusTop >= 14 + L.barHeight, "chips sit under the bar, not on it")
				t.expect.truthy(statusBottom <= nameBottom - 10, string.format("chips end above the name row's bottom (%d vs %d)", statusBottom, nameBottom))
				t.expect.truthy(status.Size.Y.Offset <= 18, "a compact status row")
				for _, name in { "Surge", "Ultimate", "Stance" } do
					local chip = status:FindFirstChild(name) :: Frame
					t.expect.truthy(chip ~= nil and chip.Size.Y.Offset <= 18, name .. " chip is compact")
				end
			end
		end)
	end)

	t.test("Contract A: UltStart shows the Ultimate card with the roster name, letterbox while in state Ultimate", function()
		run(t, function(gui)
			Hud.setViewSlot(1)
			Hud.setFighterInfo(1, info("KAEL", "YOU"))
			Hud.setFighterInfo(2, info("GORAN", "CPU"))
			Hud.setVisible(true)
			local root = (gui :: any).FightHud
			local card = root.Stage.UltimateCard
			t.expect.falsy(card.Visible)
			t.expect.falsy(root.LetterboxTop.Visible, "no letterbox outside a cinematic")
			Hud.onEvent({ kind = "UltStart", attacker = 1, target = 2, move = "Ultimate", combo = 0, damage = 0 })
			t.expect.truthy(card.Visible, "the card shows on UltStart")
			t.expect.equal(card.UltName.Text, "ULTIMATE", "fallback name without a roster entry")
			local ult = { archetype = "ultimate", move = "Ultimate", frame = 10, duration = 210, impactFrame = 36 }
			Hud.onSnapshot(snap(5, { state = "Ultimate", throw = ult }, { state = "Ultimate", throw = ult }))
			Hud.setGuide(true)
			Hud.update(frame())
			t.expect.truthy(root.LetterboxTop.Visible and root.LetterboxBottom.Visible, "letterbox during the cinematic")
			local guide = root.Stage:FindFirstChild("ControlsGuide", true) :: Frame?
			t.expect.truthy(guide ~= nil and not guide.Visible, "the controls guide steps aside during the cinematic")
			t.expect.truthy((card :: any).Tag.Visible == false, "no ULTIMATE tag next to the fallback name")
			for i = 1, 5 do Hud.onEvent({ kind = "UltHit", attacker = 1, target = 2, move = "Ultimate", combo = i, damage = 6 }) end
			Hud.update(frame())
			t.expect.truthy(root.Stage.Combo1.Visible, "impacts count on the attacker's side")
			t.expect.equal(root.Stage.Combo1.Count.Text, "5")
			t.expect.equal(root.Stage.Combo1.Kind.Text, "ULTIMATE")
			Hud.onSnapshot(snap(6, { state = "Idle" }, { state = "Knockdown" }))
			Hud.update(frame())
			task.wait(0.45)
			t.expect.falsy(root.LetterboxTop.Visible, "letterbox retracts after the cinematic")
			t.expect.truthy(guide and guide.Visible, "the guide comes back after the cinematic")
			Hud.setGuide(false)
			-- names: the roster's Ultimate name, upper case; anything missing falls back
			local fake = { has = function(id: string) return id == "A" or id == "B" end, get = function(id: string): any
				if id == "A" then return { displayName = "Ace", moves = { Ultimate = { name = "Final Bell" } } } end
				return { displayName = "Bee", moves = {} }
			end }
			t.expect.equal(HudBanners.ultimateName(fake, "A"), "FINAL BELL")
			t.expect.equal(HudBanners.ultimateName(fake, "B"), "ULTIMATE", "no Ultimate move")
			t.expect.equal(HudBanners.ultimateName(fake, "Z"), "ULTIMATE", "unknown fighter")
			t.expect.equal(HudBanners.ultimateName(nil, "A"), "ULTIMATE", "no roster")
		end)
	end)

	t.test("the Ultimate title card leaves at the cinematic's first impact, after its minimum time, so it never covers the action", function()
		run(t, function(gui)
			Hud.setViewSlot(1)
			Hud.setFighterInfo(1, info("GORAN", "YOU"))
			Hud.setFighterInfo(2, info("NIA", "DUMMY"))
			Hud.setVisible(true)
			local card = (gui :: any).FightHud.Stage.UltimateCard
			Hud.onEvent({ kind = "UltStart", attacker = 1, target = 2, move = "Ultimate", combo = 0, damage = 0 })
			t.expect.truthy(card.Visible, "the card shows on UltStart")
			Hud.onEvent({ kind = "UltHit", attacker = 1, target = 2, move = "Ultimate", combo = 1, damage = 6 })
			t.expect.truthy(card.Visible, "the card stays up for its minimum time so the name reads")
			t.expect.truthy(HudBanners.ULT_TITLE_MIN_SECONDS < HudBanners.ULT_TITLE_SECONDS, "the minimum is shorter than the full hold")
			task.wait(HudBanners.ULT_TITLE_MIN_SECONDS + 0.6)
			t.expect.falsy(card.Visible, "the card is gone soon after the first impact, long before its full hold")
		end)
	end)

	t.test("round intro and round-end texts: ROUND n, FINAL ROUND, K.O., DOUBLE K.O., TIME, DRAW, PERFECT", function()
		t.expect.equal(HudBanners.roundIntroText(1, { 0, 0 }, 2), "ROUND 1")
		t.expect.equal(HudBanners.roundIntroText(3, { 1, 1 }, 2), "FINAL ROUND")
		t.expect.equal(HudBanners.roundIntroText(2, { 1, 0 }, 2), "ROUND 2")
		local h, s = HudBanners.roundEndText("KO", 1, false); t.expect.equal(h, "K.O."); t.expect.equal(s, nil)
		h, s = HudBanners.roundEndText("KO", 2, true); t.expect.equal(h, "K.O."); t.expect.equal(s, "PERFECT")
		h, s = HudBanners.roundEndText("KO", 0, false); t.expect.equal(h, "DOUBLE K.O.")
		h, s = HudBanners.roundEndText("TIME", 1, false); t.expect.equal(h, "TIME"); t.expect.equal(s, nil)
		h, s = HudBanners.roundEndText("TIME", 0, false); t.expect.equal(h, "DRAW"); t.expect.equal(s, "TIME")
		t.expect.truthy(HudBanners.isPerfect(1, { { health = 120, maxHealth = 120 }, { health = 0, maxHealth = 100 } }))
		t.expect.falsy(HudBanners.isPerfect(1, { { health = 119, maxHealth = 120 }, { health = 0, maxHealth = 100 } }))
		t.expect.falsy(HudBanners.isPerfect(0, nil))
	end)

	t.test("the HUD shows the round intro, K.O. with PERFECT, TIME and the winner card from the frames", function()
		run(t, function(gui)
			Hud.setViewSlot(1)
			Hud.setFighterInfo(1, info("KAEL", "YOU"))
			Hud.setFighterInfo(2, info("GORAN", "CPU"))
			Hud.setVisible(true)
			local stage = (gui :: any).FightHud.Stage
			Hud.update(frame({ phase = "Ready", round = 1 }))
			t.expect.truthy(stage.BannerHolder.Visible); t.expect.equal(stage.BannerHolder.Banner.Text, "ROUND 1")
			task.wait(1.3)
			Hud.update(frame({ phase = "Ready", round = 1 }))
			t.expect.truthy(stage.BannerHolder.Visible and stage.BannerHolder.Banner.TextTransparency < 0.5, "ROUND 1 holds through the Ready phase")
			-- the HUD hidden and shown again during Ready (fight set-up): the intro comes back
			Hud.setVisible(false)
			Hud.setVisible(true)
			Hud.update(frame({ phase = "Ready", round = 1 }))
			t.expect.truthy(stage.BannerHolder.Visible, "ROUND 1 is back after the HUD was hidden during Ready")
			t.expect.equal(stage.BannerHolder.Banner.Text, "ROUND 1")
			Hud.update(frame({ phase = "Fight" }))
			t.expect.equal(stage.BannerHolder.Banner.Text, "FIGHT")
			local entry = { fighters = { { health = 100, maxHealth = 100 }, { health = 0, maxHealth = 100 } } }
			Hud.update(frame({ phase = "RoundOver", ko = true, reason = "KO", winner = 1, entry = entry }))
			t.expect.equal(stage.BannerHolder.Banner.Text, "K.O.")
			task.wait(1.15)
			t.expect.equal(stage.BannerHolder.Banner.Text, "PERFECT", "a winner with full health gets PERFECT after the K.O.")
			Hud.setViewSlot(1)
			Hud.update(frame({ phase = "Fight", round = 2 }))
			Hud.update(frame({ phase = "RoundOver", reason = "TIME", winner = 2, timer = 0 }))
			t.expect.equal(stage.BannerHolder.Banner.Text, "TIME")
			Hud.setViewSlot(1)
			Hud.setFighterInfo(1, info("KAEL", "YOU"))
			Hud.update(frame({ phase = "MatchOver", scores = { 2, 1 }, winner = 1, reason = "KO", ko = true }))
			task.wait(1.6)
			Hud.update(frame({ phase = "MatchOver", scores = { 2, 1 }, winner = 1, reason = "KO", ko = true }))
			t.expect.truthy(stage.WinnerCard.Visible, "winner card after the K.O. beat")
			t.expect.equal(stage.WinnerCard.Title.Text, "VICTORY")
			t.expect.equal(stage.WinnerCard.Score.Text, "2  —  1")
			-- practice Versus CPU rematches at once: the new round must not keep the old result card
			Hud.update(frame({ phase = "Ready", round = 1, scores = { 0, 0 } }))
			t.expect.falsy(stage.WinnerCard.Visible, "the result card goes away when a rematch starts")
			t.expect.equal(stage.BannerHolder.Banner.Text, "ROUND 1", "the rematch shows its round intro")
		end)
	end)

	t.test("the stance chip names the stance a fighter holds", function()
		t.expect.equal(Hud.stanceName("StillWater"), "STILL WATER")
		t.expect.equal(Hud.stanceName("Pocket"), "POCKET")
		run(t, function(gui)
			Hud.setViewSlot(1)
			Hud.setVisible(true)
			local status = (gui :: any).FightHud.Stage.HudFighter1.Status
			Hud.onSnapshot(snap(1, { state = "Stance", stance = "Southpaw", stanceFrame = 4 }, {}))
			Hud.update(frame())
			t.expect.truthy(status.Stance.Visible)
			t.expect.equal(status.Stance.Text.Text, "SOUTHPAW")
			Hud.onSnapshot(snap(2, { state = "Idle" }, {}))
			Hud.update(frame())
			t.expect.falsy(status.Stance.Visible)
		end)
	end)

	t.test("phone layout: the bars, clock and status rows fit a landscape phone without overlapping", function()
		local holder = Instance.new("Folder")
		local ok, err = pcall(function()
			-- the design space a 844 x 390 touch screen gets (fitToScreen with touchOnly)
			local scale = UIHelpers.uiScale(Vector2.new(844, 390), true)
			local w = 844 / scale
			local half = w / 2
			local L = Hud.LAYOUT
			local groupW = L.barWidth + L.card - 16
			local outerEdge = half - (L.timerWidth / 2 + 12) - groupW
			t.expect.truthy(outerEdge >= 0, string.format("the bars stay on screen (outer edge %.1f, design width %.0f)", outerEdge, w))
			t.expect.truthy(scale >= 0.6, "readable scale on a phone: " .. scale)
			t.expect.truthy(L.top + L.barHeight + 60 < 390 / scale * 0.3, "the HUD keeps to the top third")
		end)
		holder:Destroy()
		if not ok then error(err, 0) end
	end)
end
