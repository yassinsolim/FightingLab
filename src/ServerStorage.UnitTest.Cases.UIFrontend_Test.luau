--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lab = ReplicatedStorage:WaitForChild("FightingLab")
local Client = Lab:WaitForChild("Client")
local UIHelpers = require(Client:WaitForChild("UIHelpers"))
local UIState = require(Client:WaitForChild("UIState"))
local MoveList = require(Client:WaitForChild("MoveList"))
local Roster = require(Lab:WaitForChild("Roster"))

return function(t)
	t.test("HUD utility math validates timer, pips and overlap", function()
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

	-- Round 6: the select bars follow each fighter's design. Only real attacks count (the 3+4 stance entries, Rhys's
	-- parries and Goran's catch start in 3-10 frames and used to read as the "fastest startup", so Goran outran Kael).
	t.test("select bars follow the design: utility moves are not attacks, Goran slow and strong, Sierra long, Rhys defensive", function()
		local kael, goran, rhys = Roster.get("Kael"), Roster.get("Goran"), Roster.get("Rhys")
		t.expect.truthy(UIHelpers.isAttack(kael.moves.Jab), "a jab is an attack")
		t.expect.truthy(UIHelpers.isAttack(kael.moves.PocketShovel), "a stance follow-up is an attack")
		t.expect.falsy(UIHelpers.isAttack(kael.moves.Pocket), "a stance entry is not an attack")
		t.expect.falsy(UIHelpers.isAttack(goran.moves.BearTrap), "the catch is not an attack")
		t.expect.falsy(UIHelpers.isAttack(rhys.moves.Deflect), "a parry is not an attack")
		t.expect.falsy(UIHelpers.isAttack(goran.moves.Throw), "throws are not strikes")
		t.expect.falsy(UIHelpers.isAttack(goran.moves.Ultimate), "the Ultimate is not part of the everyday kit")
		local bars: { [string]: { [string]: number } } = {}
		for _, id in Roster.order do
			local v = {}
			for _, a in UIHelpers.attributes(Roster.get(id), Roster) do v[a.name] = a.value end
			bars[id] = v
		end
		-- 1 = the highest bar of the cast
		local function rank(name: string, id: string): number
			local r = 1
			for _, other in Roster.order do if bars[other][name] > bars[id][name] + 1e-9 then r += 1 end end
			return r
		end
		local n = #Roster.order
		local function shown(id: string, name: string): number return math.clamp(math.floor(bars[id][name] * 10 + 0.5), 1, 10) end
		t.expect.equal(rank("POWER", "Goran"), 1, "Goran hits hardest")
		t.expect.truthy(rank("SPEED", "Goran") >= n - 1, "Goran is the slowest or second slowest (rank " .. rank("SPEED", "Goran") .. ")")
		t.expect.truthy(shown("Goran", "SPEED") < shown("Kael", "SPEED"), "Goran's SPEED reads below Kael's")
		t.expect.equal(rank("DEFENSE", "Goran"), 1, "armor, the catch and the most health")
		t.expect.equal(rank("REACH", "Sierra"), 1, "Sierra has the longest reach")
		t.expect.equal(rank("DEFENSE", "Rhys"), 2, "Rhys, the parrying counter-striker, is the next most defensive")
		t.expect.equal(rank("SPEED", "Lumi"), 1, "Lumi, the freerunner, is the fastest")
		for _, id in { "Lumi", "Nia", "Kael" } do
			t.expect.truthy(bars[id].SPEED > bars.Rhys.SPEED and bars[id].SPEED > bars.Goran.SPEED, id .. " is quicker than Rhys and Goran")
		end
		-- a zero-damage utility move (a 2-frame parry) never changes POWER or SPEED
		local fake = table.clone(kael) :: any
		fake.moves = table.clone(kael.moves)
		fake.moveOrder = table.clone(kael.moveOrder)
		fake.moves.TestParry = { key = "TestParry", height = "Mid", damage = 0, startup = 2, noHit = true, props = { parry = { window = { 1, 12 }, heights = { "High", "Mid" }, stagger = 20 } } }
		table.insert(fake.moveOrder, "TestParry")
		local before, after = UIHelpers.attributes(kael, Roster), UIHelpers.attributes(fake, Roster)
		t.expect.equal(after[1].value, before[1].value, "POWER unchanged by a utility move")
		t.expect.equal(after[2].value, before[2].value, "SPEED unchanged by a utility move")
		t.expect.truthy(after[4].value > before[4].value, "a parry is a defensive tool")
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

	t.test("HUD popup mapping covers the notable combat events", function()
		t.expect.equal(UIHelpers.popupForEvent({ kind = "Hit", counter = true }), "COUNTER HIT")
		t.expect.equal(UIHelpers.popupForEvent({ kind = "ThrowBreak" }), "THROW ESCAPE")
		t.expect.equal(UIHelpers.popupForEvent({ kind = "Parry" }), "PARRY")
		t.expect.equal(UIHelpers.popupForEvent({ kind = "Armor" }), "ARMOR")
		t.expect.equal(UIHelpers.popupForEvent({ kind = "Crush" }), "CRUSH")
	end)

	-- Round 5: the pre-lobby front end (title screen -> Arcade / Versus CPU / Practice state machine and the arcade
	-- ladder) is gone; the game starts in the lobby and only the lobby UI remains.
	t.test("the legacy title / arcade / versus menu code is deleted", function()
		t.expect.equal(Client:FindFirstChild("ArcadeMode"), nil, "ArcadeMode module removed")
		for _, name in { "initialMenuState", "menuReduce", "isValidPauseCommand", "characterIndexToId", "stageIndexToId", "makeProtocol" } do
			t.expect.equal((UIHelpers :: any)[name], nil, "UIHelpers." .. name .. " removed")
		end
		for _, name in { "initial", "reduce", "validPause" } do
			t.expect.equal((UIState :: any)[name], nil, "UIState." .. name .. " removed")
		end
		-- Everything the lobby still uses stays.
		for _, name in { "lobbyView", "prompts", "pickerNew", "pickerAction", "tutorialNew", "tutorialObserve" } do
			t.expect.equal(typeof((UIState :: any)[name]), "function", "UIState." .. name .. " kept")
		end
		t.expect.truthy(Client:FindFirstChild("SelectScene") ~= nil, "SelectScene (fighter select studio) kept")
	end)
end
