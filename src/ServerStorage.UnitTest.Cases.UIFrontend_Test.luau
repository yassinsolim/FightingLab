--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lab = ReplicatedStorage:WaitForChild("FightingLab")
local Client = Lab:WaitForChild("Client")
local UIHelpers = require(Client:WaitForChild("UIHelpers"))
local UIState = require(Client:WaitForChild("UIState"))
local MoveList = require(Client:WaitForChild("MoveList"))
local ArcadeMode = require(Client:WaitForChild("ArcadeMode"))
local Roster = require(Lab:WaitForChild("Roster"))

return function(t)
	t.test("HUD utility math validates timer pips overlap and pause payloads", function()
		t.expect.equal(UIHelpers.damageTrail(80, 95, 0.016, 100), 95)
		local trailed = UIHelpers.damageTrail(100, 60, 0.1, 100)
		t.expect.truthy(trailed < 100 and trailed > 60)
		t.expect.equal(UIHelpers.formatTimer("Training", 1234, 60), utf8.char(0x221E))
		t.expect.equal(UIHelpers.formatTimer("Match", 599, 60), "10")
		local pips = UIHelpers.roundPips(1, 2)
		t.expect.truthy(pips[1])
		t.expect.falsy(pips[2])
		t.expect.falsy(UIHelpers.anyOverlap({ { x = 500, y = 180, w = 90, h = 220 } }, { { x = 20, y = 12, w = 460, h = 34 } }, 0))
		t.expect.truthy(UIHelpers.anyOverlap({ { x = 500, y = 180, w = 90, h = 220 } }, { { x = 520, y = 150, w = 200, h = 100 } }, 0))
		t.expect.truthy(UIState.validPause("Pause", true))
		t.expect.falsy(UIState.validPause("Pause", "true"))
	end)

	t.test("combo tracker shows attacker side damage and expiry", function()
		local state = { attacker = 1, hits = 0, damage = 0, shown = false, expiresAt = 0, counterUntil = 0 }
		state = UIHelpers.registerCombo(state, { kind = "Hit", attacker = 2, combo = 1, damage = 12 }, 10)
		t.expect.falsy(UIHelpers.comboVisible(state, 10.1))
		state = UIHelpers.registerCombo(state, { kind = "Hit", attacker = 2, combo = 2, damage = 18, counter = true }, 10.2)
		t.expect.equal(state.attacker, 2)
		t.expect.equal(state.hits, 2)
		t.expect.equal(state.damage, 30)
		t.expect.truthy(UIHelpers.comboVisible(state, 10.3))
		t.expect.falsy(UIHelpers.comboVisible(state, 12))
		t.expect.truthy(state.counterUntil > 10.2)
	end)

	t.test("menu state machine covers arcade ladder continue and practice dummy", function()
		local counts = { characters = #Roster.order, stages = #Roster.stages }
		local s = UIState.initial()
		s = UIState.reduce(s, "Confirm", counts)
		t.expect.equal(s.screen, "Main")
		s = UIState.reduce(s, "Confirm", counts)
		t.expect.equal(s.mode, "Arcade")
		t.expect.equal(s.screen, "Character")
		s = UIState.reduce(s, "Confirm", counts)
		t.expect.equal(s.screen, "Stage")
		s = UIState.reduce(s, "Confirm", counts)
		t.expect.equal(s.screen, "ArcadeProgress")
		s.screen = "Continue"; s.selected = 1
		s = UIState.reduce(s, "Confirm", counts)
		t.expect.equal(s.screen, "ArcadeProgress")
		s = UIState.initial(); s.screen = "Main"; s.selected = 4
		s = UIState.reduce(s, "Confirm", counts)
		t.expect.equal(s.mode, "Practice")
		s = UIState.reduce(s, "Confirm", counts)
		t.expect.equal(s.screen, "Dummy")
	end)

	t.test("two-player versus routes P1 then P2 character select before stage", function()
		local counts = { characters = #Roster.order, stages = #Roster.stages }
		local s = UIState.initial()
		s.screen = "Main"; s.selected = 3
		s = UIState.reduce(s, "Confirm", counts)
		t.expect.equal(s.mode, "TwoPlayer")
		t.expect.equal(s.screen, "Character")
		s.selected = 1
		s = UIState.reduce(s, "Confirm", counts)
		t.expect.equal(s.screen, "CharacterP2")
		t.expect.equal(s.p1, 1)
		s.selected = 2
		s = UIState.reduce(s, "Confirm", counts)
		t.expect.equal(s.p2, 2)
		t.expect.equal(s.screen, "Stage")
	end)

	t.test("credits main-menu route returns to credits selection", function()
		local counts = { characters = #Roster.order, stages = #Roster.stages }
		local s = UIState.initial()
		s.screen = "Main"; s.selected = 7
		s = UIState.reduce(s, "Confirm", counts)
		t.expect.equal(s.screen, "Credits")
		s = UIState.reduce(s, "Back", counts)
		t.expect.equal(s.screen, "Main")
		t.expect.equal(s.selected, 7)
	end)

	t.test("move-list notation formats every roster move for keyboard and gamepad", function()
		for _, id in Roster.order do
			local def = Roster.get(id)
			for _, key in def.moveOrder do
				local move = def.moves[key]
				t.expect.truthy(#MoveList.formatInput(move.input, false) > 0, id .. " " .. key .. " keyboard notation")
				t.expect.truthy(#MoveList.formatInput(move.input, true) > 0, id .. " " .. key .. " gamepad notation")
				t.expect.truthy(#MoveList.heightTag(move.height) == 1)
				local props = MoveList.properties(move)
				if move.height == "Throw" then t.expect.truthy(table.find(props, "THROW") ~= nil) end
			end
		end
	end)

	t.test("stat bars derive health speed and power from roster data", function()
		for _, id in Roster.order do
			local bars = UIHelpers.statBars(Roster.get(id))
			t.expect.truthy(bars.health > 0 and bars.health <= 1)
			t.expect.truthy(bars.speed > 0 and bars.speed <= 1)
			t.expect.truthy(bars.power > 0 and bars.power <= 1)
		end
	end)

	-- Viewport framing faces avatars toward the UI camera and gives full-body previews enough vertical room.
	t.test("viewport framing faces the camera and fits full-body previews", function()
		local minBound = Vector3.new(-1, 0, -0.5)
		local maxBound = Vector3.new(1, 6, 0.5)
		local plan = UIHelpers.viewportFramePlan(CFrame.new(), minBound, maxBound, false, 14)
		t.expect.truthy(plan.facingDot > 0.7, "full preview should face the camera")
		t.expect.truthy(plan.verticalFit >= (maxBound - minBound).Y, "full preview should fit model height")
		local bustPlan = UIHelpers.viewportFramePlan(CFrame.new(), minBound, maxBound, true, -16)
		t.expect.truthy(bustPlan.facingDot > 0.7, "bust preview should face the camera")
		t.expect.truthy(bustPlan.cameraCFrame.Position.Z > 0)
	end)

	t.test("protocol message construction and HUD popup mapping cover v2 fields", function()
		local selectChars = UIHelpers.makeProtocol("SelectCharacters", "Kael", "Sierra")
		t.expect.equal(selectChars.kind, "SelectCharacters")
		t.expect.equal(selectChars.a, "Kael")
		t.expect.equal(selectChars.b, "Sierra")
		t.expect.equal(UIHelpers.makeProtocol("SelectStage", Roster.stages[1].id).a, Roster.stages[1].id)
		t.expect.equal(UIHelpers.makeProtocol("SetMode", "Match").a, "Match")
		t.expect.throws(function() UIHelpers.makeProtocol("SetMode", "Arcade") end)
		t.expect.equal(UIHelpers.makeProtocol("Attack", "Throw").a, "Throw")
		t.expect.throws(function() UIHelpers.makeProtocol("Attack", "RearThrow") end)
		t.expect.equal(UIHelpers.popupForEvent({ kind = "Hit", counter = true }), "COUNTER HIT")
		t.expect.equal(UIHelpers.popupForEvent({ kind = "ThrowBreak" }), "THROW ESCAPE")
		t.expect.equal(UIHelpers.popupForEvent({ kind = "Parry" }), "PARRY")
		t.expect.equal(UIHelpers.popupForEvent({ kind = "Armor" }), "ARMOR")
		t.expect.equal(UIHelpers.popupForEvent({ kind = "Crush" }), "CRUSH")
	end)

	t.test("arcade ladder chooses four different opponents when possible", function()
		local ladder = ArcadeMode.buildLadder(Roster.order, "Kael", 4, 2)
		t.expect.equal(#ladder, 4)
		for _, id in ladder do t.expect.truthy(id ~= "Kael") end
		t.expect.equal(ArcadeMode.afterResult(4, true), "Champion")
		t.expect.equal(select(1, ArcadeMode.afterResult(2, false)), "Continue")
	end)

	-- Results confirmation routes each option to its promised destination.
	t.test("results menu confirm supports rematch select and main menu", function()
		local counts = { characters = #Roster.order, stages = #Roster.stages }
		local s = UIState.initial()
		s.screen = "Results"; s.mode = "Versus"; s.selected = 1
		t.expect.equal(UIState.reduce(s, "Confirm", counts).screen, "VS")
		s.selected = 2
		local selectState = UIState.reduce(s, "Confirm", counts)
		t.expect.equal(selectState.screen, "Character")
		t.expect.equal(selectState.selected, s.p1)
		s.selected = 3
		t.expect.equal(UIState.reduce(s, "Confirm", counts).screen, "Main")
		s.selected = 1; s.mode = "Arcade"
		t.expect.equal(UIState.reduce(s, "Confirm", counts).screen, "ArcadeProgress")
		t.expect.equal(UIState.reduce(s, "Back", counts).screen, "Main")
	end)
end
