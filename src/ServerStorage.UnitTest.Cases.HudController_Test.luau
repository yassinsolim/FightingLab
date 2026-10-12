--!strict
-- Fight HUD (OV6): call-outs from combat events (COUNTER HIT / LAUNCH / THROW ESCAPE / EVADE...), the own fighter on
-- the left (setViewSlot), result text, and the controls guide auto-show rules (first fight / first practice).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lab = ReplicatedStorage:WaitForChild("FightingLab")
local Client = Lab:WaitForChild("Client")
local Hud = require(Client:WaitForChild("HudController"))
local Runner = require(game:GetService("ServerStorage").UnitTest.RunUnitTest)

local function frame(overrides: { [string]: any }?): any
	local f: { [string]: any } = { dt = 1 / 60, mode = "Match", timer = 45 * 60, config = { FPS = 60 }, scores = { 0, 0 }, phase = "Fight", round = 1, ko = false, session = "Fight", authority = "Server", paused = false }
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
	return gui, function() Hud.setVisible(false); Hud._setTouchOverride(nil); holder:Destroy() end
end

local function info(name: string, tag: string): any
	return { displayName = name, color = Color3.new(1, 0.5, 0.2), characterId = "", maxHealth = 100, playerName = if tag == "YOU" then "Tester" else "", tag = tag }
end

return function(t: Runner.T)
	t.test("combat events map to call-outs on the right side", function()
		local _, cleanup = hud()
		local ok, err = pcall(function()
			Hud.setViewSlot(1)
			local word, side = Hud.calloutFor({ kind = "Hit", attacker = 1, target = 2, counter = true })
			t.expect.equal(word, "COUNTER HIT"); t.expect.equal(side, 1)
			word, side = Hud.calloutFor({ kind = "Hit", attacker = 2, target = 1, launch = true })
			t.expect.equal(word, "LAUNCH"); t.expect.equal(side, 2)
			word, side = Hud.calloutFor({ kind = "ThrowBreak", attacker = 2, target = 1 })
			t.expect.equal(word, "THROW ESCAPE"); t.expect.equal(side, 0)
			word, side = Hud.calloutFor({ kind = "Whiff", attacker = 2, target = 1, evaded = true })
			t.expect.equal(word, "EVADE"); t.expect.equal(side, 1, "an evade is credited to the evader")
			t.expect.equal((Hud.calloutFor({ kind = "Hit", attacker = 1, target = 2 })), nil, "plain hits stay quiet")
			t.expect.equal((Hud.calloutFor({ kind = "Block", attacker = 1, target = 2 })), nil)
			-- The local player is slot 2: its events are drawn on the left.
			Hud.setViewSlot(2)
			word, side = Hud.calloutFor({ kind = "Hit", attacker = 2, target = 1, counter = true })
			t.expect.equal(side, 1, "own counter hit shows on the left for a slot-2 player")
		end)
		cleanup()
		if not ok then error(err, 0) end
	end)

	t.test("events create call-out chips and combos count on the attacker's side", function()
		local gui, cleanup = hud()
		local ok, err = pcall(function()
			Hud.setViewSlot(1)
			Hud.setFighterInfo(1, info("KAEL", "YOU"))
			Hud.setFighterInfo(2, info("GORAN", "CPU · HARD"))
			Hud.setVisible(true)
			local stage = (gui :: any).FightHud.Stage
			Hud.onEvent({ kind = "Hit", attacker = 1, target = 2, combo = 1, damage = 10, counter = true })
			local chip = stage.Callouts1:FindFirstChild("Callout")
			t.expect.truthy(chip ~= nil, "counter hit chip on the left")
			t.expect.equal(chip and chip.Text.Text, "COUNTER HIT")
			Hud.onEvent({ kind = "ThrowBreak", attacker = 2, target = 1, combo = 0, damage = 0 })
			t.expect.truthy(stage.CenterCallouts:FindFirstChild("Callout") ~= nil, "throw escape in the centre")
			for i = 2, 4 do Hud.onEvent({ kind = "Hit", attacker = 1, target = 2, combo = i, damage = 8 }) end
			Hud.update(frame())
			t.expect.truthy(stage.Combo1.Visible, "combo counter on the attacker's side")
			t.expect.falsy(stage.Combo2.Visible)
			t.expect.equal(stage.Combo1.Count.Text, "4")
			t.expect.equal(stage.HudFighter1.NameRow.Slot.Text, "YOU")
			t.expect.equal(stage.HudFighter2.NameRow.Slot.Text, "CPU · HARD")
		end)
		cleanup()
		if not ok then error(err, 0) end
	end)

	t.test("result text names the winner from the local player's point of view", function()
		local _, cleanup = hud()
		local ok, err = pcall(function()
			Hud.setViewSlot(2)
			Hud.setFighterInfo(1, info("GORAN", "P1"))
			Hud.setFighterInfo(2, info("NIA", "YOU"))
			t.expect.equal(Hud.resultText(2), "YOU WIN", "slot 2 is the local player")
			t.expect.equal(Hud.resultText(0), "DRAW")
			t.expect.equal(Hud.getViewSlot(), 2)
		end)
		cleanup()
		if not ok then error(err, 0) end
	end)

	t.test("controls guide opens by itself in the first fight and the first practice only (Auto)", function()
		local gui, cleanup = hud()
		local ok, err = pcall(function()
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
		cleanup()
		if not ok then error(err, 0) end
	end)

	t.test("timer, pips and low-health warning follow the frame", function()
		local gui, cleanup = hud()
		local ok, err = pcall(function()
			Hud.setViewSlot(1)
			Hud.setFighterInfo(1, info("KAEL", "YOU"))
			Hud.setFighterInfo(2, info("GORAN", "CPU"))
			Hud.setVisible(true)
			Hud.onSnapshot({ fighters = { { characterId = "", health = 20, maxHealth = 100 }, { characterId = "", health = 90, maxHealth = 100 } } })
			Hud.update(frame({ timer = 9 * 60, scores = { 1, 0 } }))
			local stage = (gui :: any).FightHud.Stage
			t.expect.equal(stage.TimerPlate.Timer.Text, "09")
			t.expect.equal(stage.HudFighter1.Pips.Pip1.Diamond.BackgroundColor3, (require(Client.UIHelpers) :: any).Theme.gold)
			t.expect.truthy(stage.HudFighter1.Back.LowPulse.BackgroundTransparency < 1, "low health pulses")
			t.expect.equal(stage.HudFighter2.Back.LowPulse.BackgroundTransparency, 1)
			Hud.update(frame({ mode = "Training" }))
			t.expect.equal(stage.TimerPlate.Mode.Text, "TRAINING")
		end)
		cleanup()
		if not ok then error(err, 0) end
	end)
end
