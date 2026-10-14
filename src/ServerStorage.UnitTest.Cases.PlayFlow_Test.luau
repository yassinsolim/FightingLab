--!strict
-- PLAY flow (round 7): the pure step model (who -> map -> ready, practice, searching), busy maps and the server's
-- refusals, Contract D map looks with their fallbacks and the preview shot.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lab = ReplicatedStorage:WaitForChild("FightingLab")
local Client = Lab:WaitForChild("Client")
local PlayFlow = require(Client:WaitForChild("PlayFlow"))

local function arena(id: string, order: number, state: string?, extra: { [string]: any }?): any
	local a: any = { id = id, name = string.gsub(id, "^Arena_", ""), tagline = "Tagline of " .. id, color = Color3.new(1, 0, 0), order = order, state = state or "Open", reserved = false, waiting = if state == "Waiting" then 1 else 0 }
	for k, v in extra or {} do a[k] = v end
	return a
end
local function facts(list: { any }?, extra: { [string]: any }?): any
	local f: any = { arenas = list or { arena("Arena_A", 1), arena("Arena_B", 2), arena("Arena_C", 3), arena("Arena_D", 4) }, fighter = "Kael" }
	for k, v in extra or {} do f[k] = v end
	return f
end
local function ids(cards: { any }): string
	local out = {}
	for _, c in cards do table.insert(out, c.id) end
	return table.concat(out, ",")
end
local function run(state: any, f: any, actions: { string }): (any, any)
	local req = nil
	for _, a in actions do
		local r
		state, r = PlayFlow.act(state, f, a)
		req = r or req
	end
	return state, req
end

return function(t)
	t.test("who -> VS CPU -> map (+CPU level) -> READY -> FIGHT!: four presses, the map and level ride along", function()
		local f = facts()
		local s = PlayFlow.new()
		t.expect.equal(s.screen, "Who")
		t.expect.equal(ids(PlayFlow.cards(s, f)), "duel,cpu,practice", "three big choices, nothing else")
		local req
		s, req = PlayFlow.act(s, f, "Right")
		t.expect.equal(req, nil)
		s, req = PlayFlow.act(s, f, "Confirm")
		t.expect.equal(req, nil, "a choice screen never talks to the server")
		t.expect.equal(s.screen, "Map")
		t.expect.equal(s.mode, "Cpu")
		t.expect.equal(ids(PlayFlow.cards(s, f)), "Arena_A,Arena_B,Arena_C,Arena_D", "one card per duel map")
		t.expect.equal(s.difficulty, "Normal", "Normal by default")
		-- The CPU level is a toggle above the maps: Up, Right, Down.
		s = run(s, f, { "Up", "Right", "Down" })
		t.expect.equal(s.difficulty, "Hard")
		t.expect.equal(s.zone, "cards")
		s = run(s, f, { "Right" })
		t.expect.equal(PlayFlow.cards(s, f)[s.focus].id, "Arena_B")
		s, req = PlayFlow.act(s, f, "Confirm")
		t.expect.equal(s.screen, "Ready")
		t.expect.equal(s.arena, "Arena_B")
		t.expect.equal(ids(PlayFlow.cards(s, f)), "fight,fighter", "FIGHT! and CHANGE FIGHTER")
		t.expect.truthy(string.find(PlayFlow.cards(s, f)[1].sub, "Kael", 1, true) ~= nil, "your fighter is shown")
		t.expect.equal(s.focus, 1, "FIGHT! is focused")
		s, req = PlayFlow.act(s, f, "Confirm")
		t.expect.truthy(req ~= nil and req.kind == "QuickPlay", "FIGHT! sends the request")
		t.expect.equal(req.payload.mode, "Cpu")
		t.expect.equal(req.payload.arena, "Arena_B")
		t.expect.equal(req.payload.difficulty, "Hard")
		t.expect.truthy(s.pending, "waits for the server (no double send)")
		local again
		s, again = PlayFlow.act(s, f, "Confirm")
		t.expect.equal(again, nil, "a second press while pending does nothing")
		-- CHANGE FIGHTER asks the lobby for the fighter select.
		local r = PlayFlow.new()
		r = run(r, f, { "Pick:2", "Confirm" })
		local _, fighters = PlayFlow.act(r, f, "Pick:2")
		t.expect.equal(fighters.kind, "Fighters")
	end)

	t.test("Back steps back one screen at a time; Back on the first screen closes", function()
		local f = facts()
		local s = run(PlayFlow.new(), f, { "Pick:2", "Confirm" })
		t.expect.equal(s.screen, "Ready")
		s = run(s, f, { "Back" })
		t.expect.equal(s.screen, "Map")
		t.expect.equal(s.arena, nil)
		s = run(s, f, { "Up" })
		t.expect.equal(s.zone, "level")
		s = run(s, f, { "Back" })
		t.expect.equal(s.zone, "cards", "Back first leaves the level row")
		t.expect.equal(s.screen, "Map")
		s = run(s, f, { "Back" })
		t.expect.equal(s.screen, "Who")
		t.expect.equal(s.focus, 2, "the focus comes back to VS CPU")
		local _, req = PlayFlow.act(s, f, "Back")
		t.expect.equal(req.kind, "Close")
	end)

	t.test("a busy map says so and offers the next free one; the server's refusal swaps the map on READY", function()
		local f = facts({ arena("Arena_A", 1, "Fighting"), arena("Arena_B", 2), arena("Arena_C", 3, "Waiting"), arena("Arena_D", 4) })
		local s = run(PlayFlow.new(), f, { "Pick:2" })
		t.expect.equal(PlayFlow.cards(s, f)[s.focus].id, "Arena_B", "the first free map is focused")
		t.expect.equal(PlayFlow.cards(s, f)[1].chip, "LIVE FIGHT")
		t.expect.falsy(PlayFlow.cards(s, f)[3].enabled, "someone waiting there: no CPU fight")
		s = run(s, f, { "Left", "Confirm" })
		t.expect.equal(s.screen, "Map", "a busy map is not taken")
		t.expect.truthy(s.notice ~= nil and string.find(s.notice, "IS BUSY", 1, true) ~= nil)
		t.expect.truthy(string.find(s.notice, "NEXT FREE: B", 1, true) ~= nil, "the next free map is named")
		t.expect.equal(PlayFlow.cards(s, f)[s.focus].id, "Arena_B", "and focused: one press takes it")
		s = run(s, f, { "Confirm" })
		t.expect.equal(s.screen, "Ready")
		local sent
		s, sent = PlayFlow.act(s, f, "Confirm")
		t.expect.equal(sent.payload.arena, "Arena_B")
		-- B got busy in the meantime: READY now offers D in place.
		s = PlayFlow.rejected(s, f, { request = "QuickPlay", reason = "ArenaBusy", arena = "Arena_B", next = "Arena_D" })
		t.expect.falsy(s.pending)
		t.expect.equal(s.screen, "Ready")
		t.expect.equal(s.arena, "Arena_D")
		t.expect.truthy(string.find(s.notice, "FIGHT AT D", 1, true) ~= nil)
		s, sent = PlayFlow.act(s, f, "Confirm")
		t.expect.equal(sent.payload.arena, "Arena_D", "one press fights on the offered map")
		-- Nothing free: back to the map screen with the reason.
		s = PlayFlow.rejected(s, f, { request = "QuickPlay", reason = "ArenaBusy", arena = "Arena_D", next = "" })
		t.expect.equal(s.screen, "Map")
		t.expect.truthy(string.find(s.notice, "EVERY MAP IS BUSY", 1, true) ~= nil)
		-- Every map busy on the map screen itself.
		local busy = facts({ arena("Arena_A", 1, "Fighting"), arena("Arena_B", 2, "Countdown") })
		local b = run(PlayFlow.new(), busy, { "Pick:2", "Confirm" })
		t.expect.equal(b.screen, "Map")
		t.expect.truthy(string.find(b.notice, "EVERY MAP IS BUSY", 1, true) ~= nil)
	end)

	t.test("VS PLAYER: ANY MAP first and recommended; a map with someone waiting means fight now", function()
		local f = facts({ arena("Arena_A", 1), arena("Arena_B", 2, "Waiting"), arena("Arena_C", 3, "Fighting") })
		local s = run(PlayFlow.new(), f, { "Confirm" })
		t.expect.equal(s.screen, "Map")
		t.expect.equal(s.mode, "Duel")
		local cards = PlayFlow.cards(s, f)
		t.expect.equal(ids(cards), "any,Arena_A,Arena_B,Arena_C")
		t.expect.equal(cards[1].chip, "RECOMMENDED")
		t.expect.equal(s.focus, 1, "Any map is focused")
		t.expect.truthy(string.find(cards[3].chip, "1 WAITING", 1, true) ~= nil)
		local _, any = PlayFlow.act(s, f, "Confirm")
		t.expect.equal(any.kind, "QuickPlay")
		t.expect.equal(any.payload.mode, "Duel")
		t.expect.equal(any.payload.arena, nil, "Any map = the matchmaking queue")
		t.expect.truthy(any.close)
		local _, there = PlayFlow.act(s, f, "Pick:3")
		t.expect.equal(there.payload.arena, "Arena_B", "go and fight the player waiting there")
		local busy = run(s, f, { "Pick:4" })
		t.expect.truthy(string.find(busy.notice, "IS BUSY", 1, true) ~= nil)
		t.expect.equal(PlayFlow.cards(busy, f)[busy.focus].id, "Arena_A", "the next map with a free circle")
		-- A refused VS PLAYER map (the flow had closed) comes back on the map screen with the offer.
		local back = PlayFlow.new({ screen = "Map" })
		back.mode = "Duel"
		back = PlayFlow.rejected(back, f, { request = "QuickPlay", reason = "ArenaBusy", arena = "Arena_C", next = "Arena_B" })
		t.expect.equal(PlayFlow.cards(back, f)[back.focus].id, "Arena_B")
	end)

	t.test("PRACTICE: free training, combo trials, guided lesson and practice vs CPU each start practice", function()
		local f = facts()
		local s = run(PlayFlow.new({ difficulty = "Easy" }), f, { "Pick:3" })
		t.expect.equal(s.screen, "Practice")
		t.expect.equal(ids(PlayFlow.cards(s, f)), "training,trials,lesson,practiceCpu")
		local _, training = PlayFlow.act(s, f, "Pick:1")
		t.expect.equal(training.payload.practice, "Training")
		t.expect.falsy(training.trials)
		t.expect.falsy(training.lesson)
		local _, trials = PlayFlow.act(s, f, "Pick:2")
		t.expect.equal(trials.payload.practice, "Training")
		t.expect.truthy(trials.trials, "combo trials open once practice starts")
		local _, lesson = PlayFlow.act(s, f, "Pick:3")
		t.expect.truthy(lesson.lesson)
		local _, cpu = PlayFlow.act(s, f, "Pick:4")
		t.expect.equal(cpu.payload.practice, "Cpu")
		t.expect.equal(cpu.payload.difficulty, "Easy")
		for _, r in { training, trials, lesson, cpu } do t.expect.truthy(r.close and r.kind == "QuickPlay") end
	end)

	t.test("searching / waiting: FIGHT CPU INSTEAD after about 12 s, CANCEL leaves the queue or the circle", function()
		local early = facts(nil, { searching = true, searchSeconds = 5 })
		local s = PlayFlow.new({ screen = "Search" })
		local cards = PlayFlow.cards(s, early)
		t.expect.equal(ids(cards), "cpuInstead,cancel")
		t.expect.falsy(cards[1].enabled)
		t.expect.truthy(string.find(cards[1].sub, "7 s", 1, true) ~= nil, "counts down to the offer")
		local _, none = PlayFlow.act(s, early, "Pick:1")
		t.expect.equal(none, nil, "not offered yet")
		local _, cancel = PlayFlow.act(s, early, "Pick:2")
		t.expect.equal(cancel.kind, "CancelQueue")
		local late = facts(nil, { searching = true, searchSeconds = PlayFlow.CPU_OFFER_SECONDS + 0.5 })
		local _, cpu = PlayFlow.act(s, late, "Pick:1")
		t.expect.equal(cpu.payload.mode, "Cpu")
		t.expect.equal(cpu.payload.arena, nil, "from the queue: any free map")
		local waiting = facts(nil, { waiting = true, waitSeconds = 13, waitArena = "Arena_C" })
		local _, here = PlayFlow.act(s, waiting, "Pick:1")
		t.expect.equal(here.payload.arena, "Arena_C", "on a circle the CPU joins right there")
		local _, leave = PlayFlow.act(s, waiting, "Pick:2")
		t.expect.equal(leave.kind, "LeaveCircle")
		t.expect.truthy(PlayFlow.CPU_OFFER_SECONDS >= 10 and PlayFlow.CPU_OFFER_SECONDS <= 15)
	end)

	t.test("map facts: Stations state + Contract D looks (Tagline, ThemeColor, PreviewCam) with fallbacks", function()
		local stations = Instance.new("Folder")
		local world = Instance.new("Folder")
		local arenas = Instance.new("Folder"); arenas.Name = "Arenas"; arenas.Parent = world
		local function station(id: string, order: number, state: string, kind: string?, p1: number?)
			local st = Instance.new("Configuration"); st.Name = id
			st:SetAttribute("ArenaId", id); st:SetAttribute("DisplayName", id .. " Station"); st:SetAttribute("Kind", kind or "Duel")
			st:SetAttribute("State", state); st:SetAttribute("Order", order); st:SetAttribute("P1UserId", p1 or 0); st:SetAttribute("P2UserId", 0)
			st.Parent = stations
			return st
		end
		local function model(id: string, attrs: { [string]: any }, origin: Vector3, previewCam: CFrame?)
			local m = Instance.new("Model"); m.Name = id
			for k, v in attrs do m:SetAttribute(k, v) end
			local o = Instance.new("Part"); o.Name = "FightOrigin"; o.Anchored = true; o.Position = origin; o.Parent = m
			if previewCam then
				local c = Instance.new("Part"); c.Name = "PreviewCam"; c.Anchored = true; c.CFrame = previewCam; c.Parent = m
			end
			m.Parent = arenas
			return m
		end
		station("Arena_B", 2, "Waiting", nil, 42)
		station("Arena_A", 1, "Open")
		station("Arena_Dojo", 5, "Open", "Practice")
		local shot = CFrame.lookAt(Vector3.new(0, 30, 100), Vector3.new(0, 0, 60))
		model("Arena_A", { DisplayName = "Harbor Dusk", Tagline = "Timber dock ring over the evening tide", ThemeColor = Color3.fromRGB(255, 150, 50) }, Vector3.new(0, 1, 66), shot)
		model("Arena_B", { DisplayName = "Jungle Ruins", AccentColor = Color3.fromRGB(120, 220, 90) }, Vector3.new(66, 2, 0), nil)
		local list = PlayFlow.collectArenas(stations, world)
		t.expect.equal(#list, 2, "duel maps only (no dojo)")
		t.expect.equal(list[1].id, "Arena_A", "in Order")
		t.expect.equal(list[1].name, "Harbor Dusk", "the world's DisplayName")
		t.expect.equal(list[1].tagline, "Timber dock ring over the evening tide")
		t.expect.equal(list[1].color, Color3.fromRGB(255, 150, 50), "ThemeColor")
		t.expect.equal(list[2].color, Color3.fromRGB(120, 220, 90), "AccentColor when ThemeColor is missing")
		t.expect.equal(list[2].tagline, "", "no tagline yet: none shown")
		t.expect.equal(list[2].waiting, 1, "one player waiting alone")
		local camShot = PlayFlow.previewFrame(PlayFlow.arenaModel(world, "Arena_A")) :: CFrame
		t.expect.truthy((camShot.Position - shot.Position).Magnitude < 1e-3 and camShot.LookVector:Dot(shot.LookVector) > 0.9999, "PreviewCam wins")
		local computed = PlayFlow.previewFrame(PlayFlow.arenaModel(world, "Arena_B")) :: CFrame
		t.expect.truthy(computed ~= nil, "a shot is computed from FightOrigin")
		local toRing = (Vector3.new(66, 2, 0) - computed.Position).Unit
		t.expect.truthy(computed.LookVector:Dot(toRing) > 0.85, "looking at the ring")
		t.expect.truthy(computed.Position.Y > 10, "from above, both circles in view")
		t.expect.truthy((Vector3.new(computed.Position.X, 0, computed.Position.Z)).Magnitude < 66, "from the plaza side")
		t.expect.equal(PlayFlow.arenaModel(world, "Arena_Missing"), nil)
		t.expect.equal(PlayFlow.previewFrame(nil), nil)
		-- The shot's field of view: the PreviewCam's FieldOfView attribute when sane, else none (keep the current one).
		local previewPart = (PlayFlow.arenaModel(world, "Arena_A") :: Instance):FindFirstChild("PreviewCam") :: BasePart
		t.expect.equal(PlayFlow.previewFov(PlayFlow.arenaModel(world, "Arena_A")), nil, "no attribute: none")
		previewPart:SetAttribute("FieldOfView", 64)
		t.expect.equal(PlayFlow.previewFov(PlayFlow.arenaModel(world, "Arena_A")), 64, "the attribute")
		previewPart:SetAttribute("FieldOfView", 500)
		t.expect.equal(PlayFlow.previewFov(PlayFlow.arenaModel(world, "Arena_A")), nil, "nonsense is ignored")
		t.expect.equal(PlayFlow.previewFov(PlayFlow.arenaModel(world, "Arena_B")), nil, "no PreviewCam: none")
		t.expect.equal(PlayFlow.previewFov(nil), nil)
		-- Without the world: Stations names, ember.
		local bare = PlayFlow.collectArenas(stations, nil)
		t.expect.equal(bare[1].name, "Arena_A Station")
		stations:Destroy(); world:Destroy()
	end)
end
