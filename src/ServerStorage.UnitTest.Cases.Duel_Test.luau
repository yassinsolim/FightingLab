--!strict
-- DuelService with stub players (plain tables) and a fake clock: pads, countdown, slot routing, forfeit,
-- results/leaderstats, CPU requests, practice validation and the world index.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Lab = ReplicatedStorage:WaitForChild("FightingLab")
local NetProtocol = require(Lab:WaitForChild("NetProtocol"))
local RenderBuffer = require(Lab:WaitForChild("RenderBuffer"))
local Duel = ServerStorage:WaitForChild("FightingLab"):WaitForChild("Duel")
local DuelService = require(Duel:WaitForChild("DuelService"))
local WorldIndex = require(Duel:WaitForChild("WorldIndex"))

local DUEL_ORIGIN = Vector3.new(100, 0, 0)
local DOJO_ORIGIN = Vector3.new(-100, 0, 0)

local function pad(position: Vector3, side: number, mode: string?): any
	return { position = position, radius = 3.5, side = side, mode = mode }
end

local function fakeWorld(): any
	return {
		arenas = {
			Arena_Test = {
				id = "Arena_Test", stageId = "HarborDusk", displayName = "Test Arena", kind = "Duel", order = 1, origin = DUEL_ORIGIN,
				pads = { [1] = pad(DUEL_ORIGIN + Vector3.new(-27, 0, 0), 1), [2] = pad(DUEL_ORIGIN + Vector3.new(27, 0, 0), 2) },
				practicePads = {}, exits = { P1 = CFrame.new(DUEL_ORIGIN + Vector3.new(-33, 0.5, 0)), P2 = CFrame.new(DUEL_ORIGIN + Vector3.new(33, 0.5, 0)) },
			},
			Arena_Dojo = {
				id = "Arena_Dojo", stageId = "TrainingBay", displayName = "Dojo", kind = "Practice", order = 5, origin = DOJO_ORIGIN, pads = {},
				practicePads = { Training = pad(DOJO_ORIGIN + Vector3.new(-27, 0, 0), 0, "Training"), Cpu = pad(DOJO_ORIGIN + Vector3.new(27, 0, 0), 0, "Cpu") },
				exits = { Training = CFrame.new(DOJO_ORIGIN + Vector3.new(-33, 0.5, 0)), Cpu = CFrame.new(DOJO_ORIGIN + Vector3.new(33, 0.5, 0)) },
			},
		},
		order = { "Arena_Test", "Arena_Dojo" },
		spawns = {},
	}
end

type Harness = { service: any, clock: { t: number }, sent: { any }, snapshots: { any }, avatarCalls: { any }, stations: Folder }

local function harness(): Harness
	local clock = { t = 1000 }
	local sent, snapshots, avatarCalls = {}, {}, {}
	local stations = Instance.new("Folder")
	local service = DuelService.new({
		world = fakeWorld(),
		now = function() return clock.t end,
		serverTime = function() return clock.t + 5000 end,
		send = function(player: any, kind: string, payload: any) table.insert(sent, { player = player, kind = kind, payload = payload }) end,
		sendSnapshot = function(player: any, packed: any) table.insert(snapshots, { player = player, packed = packed }) end,
		avatars = {
			freeze = function(_, p: any) table.insert(avatarCalls, { op = "freeze", player = p }) end,
			unfreeze = function(_, p: any, at: CFrame?) table.insert(avatarCalls, { op = "unfreeze", player = p, at = at }) end,
			reload = function(_, p: any) table.insert(avatarCalls, { op = "reload", player = p }) end,
		},
		stations = stations,
		random = Random.new(7),
	})
	return { service = service, clock = clock, sent = sent, snapshots = snapshots, avatarCalls = avatarCalls, stations = stations }
end

local function stub(id: number, position: Vector3?, fighter: string?): any
	return { UserId = id, Name = "Stub" .. id, DisplayName = "Stub" .. id, fighterId = fighter or "Kael", position = position or Vector3.new(0, 3, 0) }
end

local function lastSent(h: Harness, player: any, kind: string): any
	for i = #h.sent, 1, -1 do
		local m = h.sent[i]
		if m.player == player and m.kind == kind then return m.payload end
	end
	return nil
end

local function onPad(side: number): Vector3
	return DUEL_ORIGIN + Vector3.new(if side == 1 then -27 else 27, 3, 0)
end

local function startPvp(h: Harness): (any, any)
	local a, b = stub(1, onPad(1), "Kael"), stub(2, onPad(2), "Goran")
	h.service:addPlayer(a)
	h.service:addPlayer(b)
	h.service:pollPads()
	h.clock.t += 3.05
	h.service:update(0)
	return a, b
end

-- Round 5 PLAY panel harness: records teleports, has a plaza spawn and (optionally) an Arrival on the duel arena.
local PLAZA = CFrame.new(0, 0, 0)
local function quickHarness(arrival: CFrame?): Harness
	local clock = { t = 1000 }
	local sent, snapshots, avatarCalls = {}, {}, {}
	local stations = Instance.new("Folder")
	local loading: { [any]: boolean } = {}
	local world = fakeWorld()
	world.arenas.Arena_Test.arrival = arrival
	local service = DuelService.new({
		world = world,
		now = function() return clock.t end,
		serverTime = function() return clock.t + 5000 end,
		send = function(player: any, kind: string, payload: any) table.insert(sent, { player = player, kind = kind, payload = payload }) end,
		sendSnapshot = function(player: any, packed: any) table.insert(snapshots, { player = player, packed = packed }) end,
		avatars = {
			freeze = function(_, p: any) table.insert(avatarCalls, { op = "freeze", player = p }) end,
			unfreeze = function(_, p: any, at: CFrame?) table.insert(avatarCalls, { op = "unfreeze", player = p, at = at }) end,
			reload = function(_, p: any) table.insert(avatarCalls, { op = "reload", player = p }) end,
			isLoading = function(_, p: any): boolean return loading[p] == true end,
			teleport = function(_, p: any, at: CFrame)
				table.insert(avatarCalls, { op = "teleport", player = p, at = at })
				p.position = at.Position + Vector3.new(0, 3, 0)
			end,
		},
		stations = stations,
		random = Random.new(11),
		spawnFrame = function() return PLAZA end,
	})
	local h: any = { service = service, clock = clock, sent = sent, snapshots = snapshots, avatarCalls = avatarCalls, stations = stations }
	h.loading = loading
	return h
end

local function countSent(h: Harness, player: any, kind: string): number
	local n = 0
	for _, m in h.sent do if m.player == player and m.kind == kind then n += 1 end end
	return n
end

-- Lets the pending server moves run (TeleportDelay) and the pad poll / matchmaking tick.
local function settle(h: Harness)
	h.clock.t += NetProtocol.TeleportDelay + 0.01
	h.service:update(1 / NetProtocol.PadPollHz)
end

local function near(a: Vector3, b: Vector3): boolean
	return (a - b).Magnitude < 0.01
end

return function(t)
	t.test("world index reads arenas, pads, exits and spawns from the contract layout", function()
		local world = Instance.new("Folder")
		local lobby = Instance.new("Model")
		lobby.Name = "Lobby"
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "LobbySpawn"
		spawn.Parent = lobby
		lobby.Parent = world
		local arenas = Instance.new("Folder")
		arenas.Name = "Arenas"
		arenas.Parent = world
		local arena = Instance.new("Model")
		arena.Name = "Arena_Unit"
		arena:SetAttribute("ArenaId", "Arena_Unit")
		arena:SetAttribute("StageId", "JungleRuins")
		arena:SetAttribute("Kind", "Duel")
		arena:SetAttribute("Order", 3)
		local function part(name: string, position: Vector3): Part
			local p = Instance.new("Part")
			p.Name = name
			p.Position = position
			p.Parent = arena
			return p
		end
		part("FightOrigin", Vector3.new(10, 0, 50))
		part("PadP1", Vector3.new(-17, 0.1, 50)):SetAttribute("PadRadius", 4)
		part("PadP2", Vector3.new(37, 0.1, 50))
		part("ExitP1", Vector3.new(-23, 0.5, 50))
		part("ExitP2", Vector3.new(43, 0.5, 50))
		arena.Parent = arenas
		local index = WorldIndex.scan(world)
		local a = index.arenas.Arena_Unit
		t.expect.truthy(a ~= nil, "arena indexed")
		t.expect.equal(a.stageId, "JungleRuins")
		t.expect.equal(a.origin, Vector3.new(10, 0, 50))
		t.expect.equal(a.pads[1].radius, 4)
		t.expect.equal(a.pads[2].radius, WorldIndex.DefaultPadRadius)
		t.expect.truthy(a.exits.P1.LookVector:Dot(Vector3.xAxis) > 0.99, "exit faces the fight centre")
		t.expect.equal(#index.spawns, 1)
		t.expect.truthy(WorldIndex.onPad(a.pads[1], Vector3.new(-17, 3, 52)))
		t.expect.falsy(WorldIndex.onPad(a.pads[1], Vector3.new(-17, 3, 56)))
		world:Destroy()
	end)

	t.test("standing on a pad queues the player and publishes station state", function()
		local h = harness()
		local a = stub(1, onPad(1))
		h.service:addPlayer(a)
		h.service:pollPads()
		local rec = h.service:recordOf(a)
		t.expect.equal(rec.state, "Queued")
		t.expect.equal(rec.padSide, 1)
		t.expect.equal(rec.arenaId, "Arena_Test")
		local station = h.stations:FindFirstChild("Arena_Test")
		t.expect.truthy(station ~= nil and station:IsA("Configuration"), "station configuration exists")
		t.expect.equal(station:GetAttribute("State"), "Waiting")
		t.expect.equal(station:GetAttribute("P1UserId"), 1)
		t.expect.equal(station:GetAttribute("P1Fighter"), "Kael")
		t.expect.equal(station:GetAttribute("Kind"), "Duel")
		a.position = Vector3.new(0, 3, 0)
		h.service:pollPads()
		t.expect.equal(rec.state, "Lobby")
		t.expect.equal(station:GetAttribute("State"), "Open")
		t.expect.equal(station:GetAttribute("P1UserId"), 0)
		t.expect.equal(h.stations:FindFirstChild("Arena_Dojo"):GetAttribute("Kind"), "Practice")
	end)

	t.test("both pads start a 3 s countdown that stepping off cancels", function()
		local h = harness()
		local a, b = stub(1, onPad(1)), stub(2, onPad(2))
		h.service:addPlayer(a)
		h.service:addPlayer(b)
		h.service:pollPads()
		local ca, cb = lastSent(h, a, "Countdown"), lastSent(h, b, "Countdown")
		t.expect.truthy(ca ~= nil and cb ~= nil, "both told about the countdown")
		t.expect.equal(ca.arenaId, "Arena_Test")
		t.expect.equal(ca.side, 1)
		t.expect.equal(cb.side, 2)
		t.expect.equal(ca.endsAt, h.clock.t + 5000 + NetProtocol.CountdownSeconds)
		t.expect.equal(h.service:recordOf(a).state, "Countdown")
		t.expect.equal(h.stations.Arena_Test:GetAttribute("State"), "Countdown")
		h.clock.t += 1.5
		b.position = Vector3.new(0, 3, 0)
		h.service:pollPads()
		t.expect.truthy(lastSent(h, a, "CountdownCancelled") ~= nil)
		t.expect.truthy(lastSent(h, b, "CountdownCancelled") ~= nil)
		t.expect.equal(h.service:recordOf(a).state, "Queued")
		t.expect.equal(h.service:recordOf(b).state, "Lobby")
		t.expect.equal(h.stations.Arena_Test:GetAttribute("State"), "Waiting")
		h.clock.t += 5
		h.service:update(0)
		t.expect.equal(h.service:recordOf(a).state, "Queued", "a cancelled countdown never starts a match")
	end)

	t.test("countdown end starts a server match and routes inputs only to each player's slot", function()
		local h = harness()
		local a, b = startPvp(h)
		local sa, sb = lastSent(h, a, "MatchStart"), lastSent(h, b, "MatchStart")
		t.expect.truthy(sa ~= nil and sb ~= nil, "both get MatchStart")
		t.expect.equal(sa.authority, "Server")
		t.expect.equal(sa.slot, 1)
		t.expect.equal(sb.slot, 2)
		t.expect.equal(sa.matchId, sb.matchId)
		t.expect.equal(sa.origin, DUEL_ORIGIN)
		t.expect.equal(sa.p1.fighter, "Kael")
		t.expect.equal(sa.p2.fighter, "Goran")
		t.expect.equal(sa.p2.userId, 2)
		t.expect.equal(sa.cpu, false)
		t.expect.equal(h.service:recordOf(a).state, "Fighting")
		t.expect.equal(#h.avatarCalls, 2)
		t.expect.equal(h.avatarCalls[1].op, "freeze")
		local station = h.service:station("Arena_Test")
		local match = station.host.runner.match
		h.service:onCommand(a, "Move", 1, 0)
		h.service:onCommand(b, "Move", -1, 1)
		t.expect.equal(match.fighters[1].input.moveX, 1)
		t.expect.equal(match.fighters[2].input.moveX, -1)
		t.expect.equal(match.fighters[2].input.moveZ, 1)
		h.service:onCommand(b, "Block", true)
		t.expect.equal(match.fighters[2].input.block, true)
		t.expect.equal(match.fighters[1].input.block, false)
		local outsider = stub(9)
		h.service:addPlayer(outsider)
		h.service:onCommand(outsider, "Move", -1, 0)
		t.expect.equal(match.fighters[1].input.moveX, 1, "non-participants are ignored")
		local epoch = station.host.runner.epoch
		h.service:onCommand(a, "Reset")
		h.service:onCommand(a, "SetMode", "Training")
		t.expect.equal(station.host.runner.epoch, epoch, "only Move/Block/Crouch/Attack are accepted")
		t.expect.equal(match.mode, "Match")
	end)

	t.test("server matches stream every step to both participants with matchId", function()
		local h = harness()
		local a, b = startPvp(h)
		local before = #h.snapshots
		h.service:update(1 / 60)
		h.service:update(1 / 60)
		h.service:update(1 / 60)
		t.expect.truthy(#h.snapshots - before >= 4, "two players x at least two steps")
		local last = h.snapshots[#h.snapshots]
		local matchId = h.service:recordOf(a).matchId
		t.expect.equal(NetProtocol.matchIdOf(last.packed), matchId)
		local entry = RenderBuffer.parse(NetProtocol.unpackEntry(last.packed))
		t.expect.truthy(entry ~= nil, "packed snapshot parses")
		t.expect.equal((entry :: any).matchId, matchId)
		t.expect.equal((entry :: any).p2Id, "Goran")
		local station = h.stations.Arena_Test
		t.expect.equal(station:GetAttribute("State"), "Fighting")
		h.service:update(0.11)
		t.expect.equal(station:GetAttribute("Phase"), "Ready")
		t.expect.equal(station:GetAttribute("P2Fighter"), "Goran")
		t.expect.equal(station:GetAttribute("P1Health"), 1)
	end)

	t.test("command rate is limited per player", function()
		local h = harness()
		local a, b = startPvp(h)
		local runner = h.service:station("Arena_Test").host.runner
		local accepted = 0
		local original = runner.command
		runner.command = function(self: any, ...: any)
			accepted += 1
			return original(self, ...)
		end
		for _ = 1, 200 do h.service:onCommand(a, "Crouch", false) end
		t.expect.equal(accepted, NetProtocol.CommandBurst, "burst capped")
		h.service:onCommand(b, "Crouch", false)
		t.expect.equal(accepted, NetProtocol.CommandBurst + 1, "the other player is unaffected")
		h.clock.t += 1
		h.service:onCommand(a, "Crouch", false)
		t.expect.equal(accepted, NetProtocol.CommandBurst + 2, "tokens refill over time")
	end)

	t.test("forfeit awards the opponent, updates stats and returns both players", function()
		local h = harness()
		local a, b = startPvp(h)
		local matchId = h.service:recordOf(a).matchId
		h.service:onLobby(a, "LeaveFight", {})
		local ea, eb = lastSent(h, a, "MatchEnd"), lastSent(h, b, "MatchEnd")
		t.expect.truthy(ea ~= nil and eb ~= nil, "both get MatchEnd")
		t.expect.equal(ea.matchId, matchId)
		t.expect.equal(ea.winnerSlot, 2)
		t.expect.equal(ea.reason, "Forfeit")
		local ra, rb = h.service:recordOf(a), h.service:recordOf(b)
		t.expect.equal(rb.wins, 1)
		t.expect.equal(rb.streak, 1)
		t.expect.equal(ra.wins, 0)
		t.expect.equal(ra.streak, 0)
		t.expect.equal(ra.state, "Lobby")
		t.expect.equal(rb.state, "Lobby")
		local unfreezes = 0
		for _, call in h.avatarCalls do
			if call.op == "unfreeze" then
				unfreezes += 1
				local expected = if call.player == a then DUEL_ORIGIN + Vector3.new(-33, 0.5, 0) else DUEL_ORIGIN + Vector3.new(33, 0.5, 0)
				t.expect.equal((call.at :: CFrame).Position, expected)
			end
		end
		t.expect.equal(unfreezes, 2)
		t.expect.equal(h.stations.Arena_Test:GetAttribute("State"), "Open")
		h.service:pollPads()
		t.expect.equal(ra.state, "Lobby", "still standing on the pad after the match does not re-queue")
	end)

	t.test("MatchOver shows results for a few seconds, then MatchEnd with leaderstats", function()
		local h = harness()
		local a, b = startPvp(h)
		local station = h.service:station("Arena_Test")
		local match = station.host.runner.match
		match.scores = { 2, 1 }
		match.phase = "MatchOver"
		match.reason = "KO"
		h.service:update(1 / 60)
		t.expect.equal(station.state, "Results")
		t.expect.equal(h.service:recordOf(a).state, "Results")
		t.expect.equal(h.stations.Arena_Test:GetAttribute("WinnerSlot"), 1)
		t.expect.equal(h.stations.Arena_Test:GetAttribute("ResultText"), "Stub1 wins")
		t.expect.falsy(lastSent(h, a, "MatchEnd"), "no MatchEnd during results")
		h.clock.t += NetProtocol.ResultsSeconds + 0.1
		h.service:update(1 / 60)
		local ea = lastSent(h, a, "MatchEnd")
		t.expect.truthy(ea ~= nil)
		t.expect.equal(ea.winnerSlot, 1)
		t.expect.equal(ea.reason, "KO")
		t.expect.equal(ea.rounds.p1, 2)
		t.expect.equal(ea.rounds.p2, 1)
		t.expect.equal(h.service:recordOf(a).wins, 1)
		t.expect.equal(h.service:recordOf(a).streak, 1)
		t.expect.equal(h.service:recordOf(b).streak, 0)
		t.expect.equal(station.state, "Open")
	end)

	t.test("a disconnect during a fight forfeits to the remaining player", function()
		local h = harness()
		local a, b = startPvp(h)
		h.service:removePlayer(a)
		local eb = lastSent(h, b, "MatchEnd")
		t.expect.truthy(eb ~= nil)
		t.expect.equal(eb.winnerSlot, 2)
		t.expect.equal(eb.reason, "Disconnect")
		t.expect.falsy(lastSent(h, a, "MatchEnd"), "nothing is sent to the leaver")
		t.expect.equal(h.service:recordOf(b).wins, 1)
	end)

	t.test("CPU is offered only to a player waiting alone, after the offer delay", function()
		local h = harness()
		local a = stub(1, onPad(2), "Lumi")
		h.service:addPlayer(a)
		h.service:pollPads()
		h.service:onLobby(a, "RequestCpu", { difficulty = "Hard" })
		t.expect.equal(lastSent(h, a, "Rejected").reason, "TooSoon")
		h.clock.t += NetProtocol.CpuOfferSeconds
		h.service:onLobby(a, "RequestCpu", { difficulty = "Hard" })
		local start = lastSent(h, a, "MatchStart")
		t.expect.truthy(start ~= nil, "CPU match started")
		t.expect.equal(start.slot, 2)
		t.expect.equal(start.cpu, true)
		t.expect.equal(start.difficulty, "Hard")
		t.expect.equal(start.p1.userId, NetProtocol.CpuUserId)
		t.expect.equal(start.p2.fighter, "Lumi")
		local station = h.service:station("Arena_Test")
		t.expect.equal(station.host.runner.human[1], false)
		t.expect.equal(station.host.runner.human[2], true)
		t.expect.equal(station.host.runner.match.difficulty, "Hard")
		t.expect.equal(h.stations.Arena_Test:GetAttribute("Cpu"), true)
		t.expect.equal(h.stations.Arena_Test:GetAttribute("P1UserId"), NetProtocol.CpuUserId)
		local lonely = stub(3)
		h.service:addPlayer(lonely)
		h.service:onLobby(lonely, "RequestCpu", {})
		t.expect.equal(lastSent(h, lonely, "Rejected").reason, "NotWaiting")
		h.service:onCommand(a, "Move", 1, 0)
		t.expect.equal(station.host.runner.match.fighters[2].input.moveX, 1, "the human drives slot 2")
	end)

	t.test("practice needs the matching dojo pad and ends at the dojo exit", function()
		local h = harness()
		local a = stub(1, Vector3.new(0, 3, 0), "Rhys")
		h.service:addPlayer(a)
		h.service:onLobby(a, "StartPractice", { mode = "Training" })
		t.expect.equal(lastSent(h, a, "Rejected").reason, "NotOnPad")
		a.position = DOJO_ORIGIN + Vector3.new(27, 3, 0)
		h.service:onLobby(a, "StartPractice", { mode = "Training" })
		t.expect.equal(lastSent(h, a, "Rejected").reason, "NotOnPad", "the CPU pad does not start Training")
		h.service:onLobby(a, "StartPractice", { mode = "Cpu", difficulty = "Easy", opponent = "Nia" })
		local start = lastSent(h, a, "MatchStart")
		t.expect.truthy(start ~= nil)
		t.expect.equal(start.authority, "Local")
		t.expect.equal(start.mode, "Match")
		t.expect.equal(start.cpu, true)
		t.expect.equal(start.origin, DOJO_ORIGIN)
		t.expect.equal(start.p1.fighter, "Rhys")
		t.expect.equal(start.p2.fighter, "Nia")
		t.expect.equal(start.difficulty, "Easy")
		local rec = h.service:recordOf(a)
		t.expect.equal(rec.state, "Practice")
		t.expect.equal(h.avatarCalls[#h.avatarCalls].op, "freeze")
		h.service:onLobby(a, "SelectFighter", { id = "Goran" })
		t.expect.equal(lastSent(h, a, "Rejected").reason, "Busy")
		h.service:onLobby(a, "EndPractice", {})
		local ended = lastSent(h, a, "MatchEnd")
		t.expect.equal(ended.matchId, start.matchId)
		t.expect.equal(ended.reason, "Practice")
		t.expect.equal(rec.state, "Lobby")
		local last = h.avatarCalls[#h.avatarCalls]
		t.expect.equal(last.op, "unfreeze")
		t.expect.equal((last.at :: CFrame).Position, DOJO_ORIGIN + Vector3.new(33, 0.5, 0))
	end)

	t.test("fighter select reloads the avatar only in the lobby or queue", function()
		local h = harness()
		local a = stub(1)
		h.service:addPlayer(a)
		h.service:onLobby(a, "SelectFighter", { id = "Nia" })
		t.expect.equal(h.service:recordOf(a).fighterId, "Nia")
		t.expect.equal(h.avatarCalls[#h.avatarCalls].op, "reload")
		h.service:onLobby(a, "SelectFighter", { id = "NotAFighter" })
		t.expect.equal(lastSent(h, a, "Rejected").reason, "Invalid")
		t.expect.equal(h.service:recordOf(a).fighterId, "Nia")
	end)

	t.test("a queued player keeps the pad while the avatar reloads for a fighter change", function()
		local h = harness()
		local loading = {}
		h.service.deps.avatars.isLoading = function(_, p: any): boolean return loading[p] == true end
		local a = stub(1, onPad(1))
		h.service:addPlayer(a)
		h.service:pollPads()
		t.expect.equal(h.service:recordOf(a).state, "Queued")
		loading[a] = true
		a.position = Vector3.new(0, 3, 0)
		h.service:pollPads()
		t.expect.equal(h.service:recordOf(a).state, "Queued", "a reloading avatar (briefly at the lobby spawn) keeps the claim")
		loading[a] = nil
		h.service:pollPads()
		t.expect.equal(h.service:recordOf(a).state, "Lobby")
	end)

	t.test("lobby request floods are dropped", function()
		local h = harness()
		local a = stub(1)
		h.service:addPlayer(a)
		for _ = 1, 40 do h.service:onLobby(a, "RequestCpu", {}) end
		local rejected = 0
		for _, m in h.sent do if m.player == a and m.kind == "Rejected" then rejected += 1 end end
		t.expect.equal(rejected, NetProtocol.LobbyBurst)
	end)

	-- Round 5: PLAY panel (server matchmaking queue, Fight CPU, Practice, quick travel) ----------------------------------
	t.test("Quick Duel pairs two searchers: both are teleported onto PadP1 / PadP2 and the countdown starts", function()
		local h = quickHarness()
		local a, b = stub(1, Vector3.new(0, 3, 0), "Kael"), stub(2, Vector3.new(4, 3, 0), "Goran")
		h.service:addPlayer(a)
		h.service:addPlayer(b)
		h.service:onLobby(a, "QuickPlay", { mode = "Duel" })
		local ra, rb = h.service:recordOf(a), h.service:recordOf(b)
		t.expect.truthy(ra.quick ~= nil, "a is searching")
		t.expect.equal(ra.quickStatus, "Searching")
		t.expect.equal(ra.state, "Lobby", "searchers stay in the lobby (they can walk, change fighter)")
		t.expect.equal(h.stations:GetAttribute("QuickSearching"), 1)
		t.expect.equal(h.stations:GetAttribute("FreeArenas"), 1)
		h.service:onLobby(b, "QuickPlay", { mode = "Duel" })
		t.expect.equal(ra.quickStatus, "Matched")
		t.expect.equal(rb.quickStatus, "Matched")
		local ta = lastSent(h, a, "Teleport")
		t.expect.truthy(ta ~= nil and lastSent(h, b, "Teleport") ~= nil, "both are told before the move")
		t.expect.equal(ta.arenaId, "Arena_Test")
		t.expect.equal(ta.delay, NetProtocol.TeleportDelay)
		t.expect.truthy(h.service:station("Arena_Test").reserved, "the arena is held for them")
		-- Someone walking onto the circle meanwhile cannot take it.
		local walker = stub(3, onPad(1))
		h.service:addPlayer(walker)
		h.service:pollPads()
		t.expect.equal(h.service:recordOf(walker).state, "Lobby", "a reserved arena takes no walk-in claims")
		h.service:removePlayer(walker)
		settle(h)
		t.expect.truthy(near(a.position, onPad(1)), "a on PadP1")
		t.expect.truthy(near(b.position, onPad(2)), "b on PadP2")
		t.expect.equal(ra.state, "Countdown")
		t.expect.equal(rb.state, "Countdown")
		t.expect.equal(ra.padSide, 1)
		t.expect.equal(rb.padSide, 2)
		t.expect.equal(ra.quick, nil)
		t.expect.truthy(lastSent(h, a, "Countdown") ~= nil and lastSent(h, b, "Countdown") ~= nil)
		t.expect.falsy(h.service:station("Arena_Test").reserved)
		-- A client still reporting its old spot for a moment does not cancel the countdown.
		a.position = Vector3.new(0, 3, 0)
		h.service:pollPads()
		t.expect.equal(ra.state, "Countdown", "teleport grace keeps the claim")
		a.position = onPad(1)
		h.clock.t += NetProtocol.CountdownSeconds
		h.service:update(0)
		local sa, sb = lastSent(h, a, "MatchStart"), lastSent(h, b, "MatchStart")
		t.expect.truthy(sa ~= nil and sb ~= nil, "the duel starts")
		t.expect.equal(sa.cpu, false)
		t.expect.equal(sa.slot, 1)
		t.expect.equal(sb.slot, 2)
		t.expect.equal(sa.p2.fighter, "Goran")
	end)

	t.test("Quick Duel sends a searcher to a player already waiting alone on a duel circle", function()
		local h = quickHarness()
		local waiter = stub(1, onPad(1), "Nia")
		h.service:addPlayer(waiter)
		h.service:pollPads()
		t.expect.equal(h.service:recordOf(waiter).state, "Queued")
		local s = stub(2, Vector3.new(0, 3, 0), "Rhys")
		h.service:addPlayer(s)
		h.service:onLobby(s, "QuickPlay", { mode = "Duel" })
		t.expect.truthy(lastSent(h, s, "Teleport") ~= nil)
		settle(h)
		t.expect.truthy(near(s.position, onPad(2)))
		t.expect.equal(h.service:recordOf(s).state, "Countdown")
		t.expect.equal(h.service:recordOf(waiter).state, "Countdown")
		t.expect.equal(h.stations.Arena_Test:GetAttribute("State"), "Countdown")
	end)

	t.test("Fight CPU from PLAY: teleported onto a free arena's PadP1 and the CPU match starts at once", function()
		local h = quickHarness()
		local a = stub(1, Vector3.new(0, 3, 0), "Lumi")
		h.service:addPlayer(a)
		h.service:onLobby(a, "QuickPlay", { mode = "Cpu", difficulty = "Hard" })
		t.expect.truthy(lastSent(h, a, "Teleport") ~= nil)
		t.expect.equal(lastSent(h, a, "MatchStart"), nil, "the move comes first")
		settle(h)
		local start = lastSent(h, a, "MatchStart")
		t.expect.truthy(start ~= nil, "CPU match started")
		t.expect.equal(start.cpu, true)
		t.expect.equal(start.slot, 1)
		t.expect.equal(start.difficulty, "Hard")
		t.expect.equal(start.p1.fighter, "Lumi")
		t.expect.equal(start.p2.userId, NetProtocol.CpuUserId)
		t.expect.truthy(near(a.position, onPad(1)))
		local station = h.service:station("Arena_Test")
		t.expect.equal(station.state, "Fighting")
		t.expect.equal(station.host.runner.human[2], false)
		t.expect.equal(station.host.runner.match.difficulty, "Hard")
		t.expect.equal(h.service:recordOf(a).state, "Fighting")
		local teleports = 0
		for _, call in h.avatarCalls do if call.op == "teleport" then teleports += 1 end end
		t.expect.equal(teleports, 1)
		t.expect.equal(h.avatarCalls[#h.avatarCalls].op, "freeze", "frozen for the fight after the move")
	end)

	t.test("Practice from PLAY: teleported onto the dojo pad, practice (or the Versus CPU) starts", function()
		local h = quickHarness()
		local a = stub(1, Vector3.new(0, 3, 0), "Rhys")
		h.service:addPlayer(a)
		h.service:onLobby(a, "QuickPlay", { mode = "Practice", practice = "Cpu", difficulty = "Easy", opponent = "Nia" })
		settle(h)
		local start = lastSent(h, a, "MatchStart")
		t.expect.truthy(start ~= nil)
		t.expect.equal(start.authority, "Local")
		t.expect.equal(start.practice, "Cpu")
		t.expect.equal(start.difficulty, "Easy")
		t.expect.equal(start.p2.fighter, "Nia")
		t.expect.truthy(near(a.position, DOJO_ORIGIN + Vector3.new(27, 3, 0)), "on the Versus CPU pad")
		t.expect.equal(h.service:recordOf(a).state, "Practice")
		h.service:onLobby(a, "EndPractice", {})
		h.clock.t += 2
		h.service:onLobby(a, "QuickPlay", { mode = "Practice", practice = "Training" })
		settle(h)
		local again = lastSent(h, a, "MatchStart")
		t.expect.equal(again.practice, "Training")
		t.expect.truthy(near(a.position, DOJO_ORIGIN + Vector3.new(-27, 3, 0)), "on the Training pad")
	end)

	t.test("quick travel: an arena's Arrival part, else 6 studs behind PadP1 / PadTraining, and back to the plaza", function()
		local h = quickHarness()
		local a = stub(1, Vector3.new(0, 3, 0))
		h.service:addPlayer(a)
		h.service:onLobby(a, "Travel", { to = "Arena_Test" })
		t.expect.equal(lastSent(h, a, "Teleport").reason, "Travel")
		settle(h)
		t.expect.truthy(near(a.position, DUEL_ORIGIN + Vector3.new(-27 - WorldIndex.ArrivalFallbackDistance, 3, 0)), "fallback: behind PadP1, away from the ring")
		local arrivalAt = h.avatarCalls[#h.avatarCalls].at :: CFrame
		t.expect.truthy(arrivalAt.LookVector:Dot(Vector3.xAxis) > 0.99, "facing the ring")
		t.expect.equal(h.service:recordOf(a).state, "Lobby", "travel never claims a circle")
		h.service:onLobby(a, "Travel", { to = "Arena_Dojo" })
		t.expect.equal(lastSent(h, a, "Rejected").reason, "TooFast", "travel cooldown")
		h.clock.t += NetProtocol.TravelCooldown
		h.service:onLobby(a, "Travel", { to = "Arena_Dojo" })
		settle(h)
		t.expect.truthy(near(a.position, DOJO_ORIGIN + Vector3.new(-27 - WorldIndex.ArrivalFallbackDistance, 3, 0)), "dojo: behind PadTraining")
		h.clock.t += NetProtocol.TravelCooldown
		h.service:onLobby(a, "Travel", { to = "Plaza" })
		settle(h)
		t.expect.truthy(near(a.position, PLAZA.Position + Vector3.new(0, 3, 0)), "back on the plaza")
		h.clock.t += NetProtocol.TravelCooldown
		h.service:onLobby(a, "Travel", { to = "Arena_Nowhere" })
		t.expect.equal(lastSent(h, a, "Rejected").reason, "NoArena")
		h.service:onLobby(a, "Travel", { to = "../Plaza" })
		t.expect.equal(lastSent(h, a, "Rejected").reason, "Invalid")
		-- With the world's Arrival part.
		local h2 = quickHarness(CFrame.new(DUEL_ORIGIN + Vector3.new(0, 0.5, 40)))
		local b = stub(2, Vector3.new(0, 3, 0))
		h2.service:addPlayer(b)
		h2.service:onLobby(b, "Travel", { to = "Arena_Test" })
		settle(h2)
		t.expect.truthy(near(b.position, DUEL_ORIGIN + Vector3.new(0, 3.5, 40)), "Arrival part")
		local at = h2.avatarCalls[#h2.avatarCalls].at :: CFrame
		t.expect.truthy(at.LookVector:Dot(Vector3.new(0, 0, -1)) > 0.99, "facing the ring")
	end)

	t.test("edge cases: busy arenas queue searchers, a leaver frees the partner, fighter changes keep the place, spam is capped", function()
		local h = quickHarness()
		-- The only duel arena is busy: searchers queue as Busy and Fight CPU explains.
		local a, b = startPvp(h)
		local c, d, e = stub(3, Vector3.new(0, 3, 0), "Sierra"), stub(4, Vector3.new(2, 3, 0), "Nia"), stub(5, Vector3.new(-2, 3, 0))
		for _, p in { c, d, e } do h.service:addPlayer(p) end
		h.service:onLobby(c, "QuickPlay", { mode = "Duel" })
		h.service:onLobby(d, "QuickPlay", { mode = "Duel" })
		t.expect.equal(h.service:recordOf(c).quickStatus, "Busy")
		t.expect.equal(h.service:recordOf(d).quickStatus, "Busy")
		t.expect.equal(h.stations:GetAttribute("FreeArenas"), 0)
		h.service:onLobby(e, "QuickPlay", { mode = "Cpu" })
		t.expect.equal(lastSent(h, e, "Rejected").reason, "ArenasBusy")
		-- The match ends: the queue moves at once.
		h.service:finishMatch(h.service:station("Arena_Test"), "Debug", 1)
		a.position = DUEL_ORIGIN + Vector3.new(-33, 3, 0)
		b.position = DUEL_ORIGIN + Vector3.new(33, 3, 0)
		h.service:update(1 / NetProtocol.PadPollHz)
		t.expect.equal(h.service:recordOf(c).quickStatus, "Matched")
		-- d leaves before the move: c goes back to the front of the queue and the arena is free again.
		h.service:removePlayer(d)
		settle(h)
		local rc = h.service:recordOf(c)
		t.expect.equal(rc.state, "Lobby")
		t.expect.truthy(rc.quick ~= nil, "c is searching again")
		t.expect.falsy(h.service:station("Arena_Test").reserved)
		t.expect.equal(h.service:station("Arena_Test").state, "Open")
		-- A fighter change while searching keeps the place; the avatar reload is waited for.
		local f = stub(6, Vector3.new(0, 3, 0), "Kael")
		h.service:addPlayer(f)
		h.clock.t += 1
		h.service:onLobby(c, "SelectFighter", { id = "Goran" })
		h.loading[c] = true
		h.service:onLobby(f, "QuickPlay", { mode = "Duel" })
		h.service:update(1 / NetProtocol.PadPollHz)
		t.expect.truthy(rc.quick ~= nil and rc.quickStatus ~= "Matched", "not paired while the avatar reloads")
		t.expect.equal(h.service:recordOf(f).quickStatus, "Searching")
		t.expect.equal(rc.fighterId, "Goran")
		h.loading[c] = nil
		h.service:update(1 / NetProtocol.PadPollHz)
		t.expect.equal(rc.quickStatus, "Matched", "paired once loaded (still first in line)")
		settle(h)
		t.expect.equal(rc.state, "Countdown")
		t.expect.equal(h.service:recordOf(f).state, "Countdown")
		-- Spam: cooldown per player, then the lobby token bucket drops floods without replies.
		local g = stub(7, Vector3.new(0, 3, 0))
		h.service:addPlayer(g)
		h.service:onLobby(g, "QuickPlay", { mode = "Duel" })
		h.service:onLobby(g, "QuickPlay", { mode = "Duel" })
		t.expect.equal(lastSent(h, g, "Rejected").reason, "TooFast")
		h.service:onLobby(g, "CancelQueue", {})
		t.expect.equal(h.service:recordOf(g).quick, nil)
		t.expect.equal(h.service:recordOf(g).quickStatus, "")
		local before = countSent(h, g, "Rejected")
		for _ = 1, 40 do h.service:onLobby(g, "Travel", { to = "Arena_Test" }) end
		t.expect.truthy(countSent(h, g, "Rejected") - before <= NetProtocol.LobbyBurst, "a flood is mostly dropped")
		-- Players in a fight cannot use PLAY.
		h.service:onLobby(c, "QuickPlay", { mode = "Practice", practice = "Training" })
		t.expect.equal(lastSent(h, c, "Rejected").reason, "Busy")
	end)

	t.test("PLAY while waiting on a circle: Quick Duel says so, Fight CPU joins right there", function()
		local h = quickHarness()
		local a = stub(1, onPad(2), "Goran")
		h.service:addPlayer(a)
		h.service:pollPads()
		h.service:onLobby(a, "QuickPlay", { mode = "Duel" })
		t.expect.equal(lastSent(h, a, "Rejected").reason, "OnCircle")
		h.clock.t += 1
		h.service:onLobby(a, "QuickPlay", { mode = "Cpu", difficulty = "Easy" })
		local start = lastSent(h, a, "MatchStart")
		t.expect.truthy(start ~= nil, "no wait for the circle's CPU offer")
		t.expect.equal(start.slot, 2)
		t.expect.equal(start.cpu, true)
		t.expect.equal(start.difficulty, "Easy")
		t.expect.equal(lastSent(h, a, "Teleport"), nil, "no move needed")
	end)

	-- Round 7 PLAY flow: two duel arenas (A, B in Order) and the dojo.
	local B_ORIGIN = Vector3.new(0, 0, 200)
	local function arenaHarness(): any
		local h: any = quickHarness()
		local world = h.service.deps.world
		world.arenas.Arena_B = {
			id = "Arena_B", stageId = "JungleRuins", displayName = "Arena B", kind = "Duel", order = 2, origin = B_ORIGIN,
			pads = { [1] = pad(B_ORIGIN + Vector3.new(-27, 0, 0), 1), [2] = pad(B_ORIGIN + Vector3.new(27, 0, 0), 2) },
			practicePads = {}, exits = { P1 = CFrame.new(B_ORIGIN + Vector3.new(-33, 0.5, 0)), P2 = CFrame.new(B_ORIGIN + Vector3.new(33, 0.5, 0)) },
		}
		table.insert(world.order, 2, "Arena_B")
		h.service:addStation(world.arenas.Arena_B)
		table.remove(h.service.stationOrder)
		table.insert(h.service.stationOrder, 2, "Arena_B")
		return h
	end
	local function onPadOf(origin: Vector3, side: number): Vector3
		return origin + Vector3.new(if side == 1 then -27 else 27, 3, 0)
	end

	t.test("round 7: VS CPU on a chosen map fights there; a busy map is refused with the next free one", function()
		local h = arenaHarness()
		t.expect.equal(table.concat(h.service.stationOrder, ","), "Arena_Test,Arena_B,Arena_Dojo")
		local a, b, c = stub(1, Vector3.new(0, 3, 0), "Lumi"), stub(2, Vector3.new(3, 3, 0), "Kael"), stub(3, Vector3.new(-3, 3, 0), "Nia")
		for _, p in { a, b, c } do h.service:addPlayer(p) end
		h.service:onLobby(a, "QuickPlay", { mode = "Cpu", difficulty = "Hard", arena = "Arena_B" })
		local notice = lastSent(h, a, "Teleport")
		t.expect.truthy(notice ~= nil and notice.arenaId == "Arena_B" and notice.reason == "Cpu", "taken to the chosen map")
		t.expect.equal(h.stations.Arena_B:GetAttribute("Reserved"), true, "the map is held while the move is pending")
		-- Meanwhile the chosen map is not free for anybody else.
		h.service:onLobby(b, "QuickPlay", { mode = "Cpu", arena = "Arena_B" })
		local busy = lastSent(h, b, "Rejected")
		t.expect.equal(busy.reason, "ArenaBusy")
		t.expect.equal(busy.arena, "Arena_B")
		t.expect.equal(busy.next, "Arena_Test", "the next free map is offered")
		settle(h)
		local start = lastSent(h, a, "MatchStart")
		t.expect.truthy(start ~= nil and start.arenaId == "Arena_B", "the CPU fight starts on the chosen map")
		t.expect.equal(start.difficulty, "Hard")
		t.expect.truthy(near(a.position, onPadOf(B_ORIGIN, 1)), "on the chosen map's P1 circle")
		t.expect.equal(h.stations.Arena_B:GetAttribute("Reserved"), false)
		-- The offered map works.
		h.clock.t += 1
		h.service:onLobby(b, "QuickPlay", { mode = "Cpu", arena = busy.next })
		settle(h)
		t.expect.equal(lastSent(h, b, "MatchStart").arenaId, "Arena_Test")
		-- Every map busy: refused with no alternative; the dojo and unknown ids are not duel maps.
		h.service:onLobby(c, "QuickPlay", { mode = "Cpu", arena = "Arena_Test" })
		local none = lastSent(h, c, "Rejected")
		t.expect.equal(none.reason, "ArenaBusy")
		t.expect.equal(none.next, "", "nothing free to offer")
		h.clock.t += 1
		h.service:onLobby(c, "QuickPlay", { mode = "Cpu", arena = "Arena_Dojo" })
		t.expect.equal(lastSent(h, c, "Rejected").reason, "NoArena")
		h.clock.t += 1
		h.service:onLobby(c, "QuickPlay", { mode = "Cpu", arena = "Arena_Nowhere" })
		t.expect.equal(lastSent(h, c, "Rejected").reason, "NoArena")
		h.clock.t += 1
		h.service:onLobby(c, "QuickPlay", { mode = "Cpu", arena = "../Arena_B" })
		t.expect.equal(lastSent(h, c, "Rejected").reason, "Invalid", "malformed ids never reach the service")
		-- Without a map it is today's "any free arena" (none left now).
		h.clock.t += 1
		h.service:onLobby(c, "QuickPlay", { mode = "Cpu" })
		t.expect.equal(lastSent(h, c, "Rejected").reason, "ArenasBusy")
	end)

	t.test("round 7: VS PLAYER on a chosen map waits on its circle; a second player there or an Any map searcher starts the duel", function()
		local h = arenaHarness()
		local a, b = stub(1, Vector3.new(0, 3, 0), "Kael"), stub(2, Vector3.new(3, 3, 0), "Goran")
		h.service:addPlayer(a)
		h.service:addPlayer(b)
		h.service:onLobby(a, "QuickPlay", { mode = "Duel", arena = "Arena_B" })
		local notice = lastSent(h, a, "Teleport")
		t.expect.truthy(notice ~= nil and notice.reason == "Wait" and notice.arenaId == "Arena_B", "taken to the chosen map to wait")
		local ra = h.service:recordOf(a)
		t.expect.equal(ra.quick, nil, "a chosen map is not the Any map queue")
		t.expect.equal(h.stations.Arena_B:GetAttribute("Reserved"), true)
		-- A walk-in cannot take the circle the server is moving `a` onto.
		local walker = stub(9, onPadOf(B_ORIGIN, 1))
		h.service:addPlayer(walker)
		h.service:pollPads()
		t.expect.equal(h.service:recordOf(walker).state, "Lobby", "the incoming circle takes no walk-in")
		h.service:removePlayer(walker)
		settle(h)
		t.expect.truthy(near(a.position, onPadOf(B_ORIGIN, 1)))
		t.expect.equal(ra.state, "Queued", "waiting on the chosen map's circle")
		t.expect.equal(ra.arenaId, "Arena_B")
		t.expect.equal(h.stations.Arena_B:GetAttribute("State"), "Waiting")
		t.expect.equal(h.stations.Arena_B:GetAttribute("Reserved"), false)
		-- Picking the same map again says you are already there.
		h.clock.t += 1
		h.service:onLobby(a, "QuickPlay", { mode = "Duel", arena = "Arena_B" })
		t.expect.equal(lastSent(h, a, "Rejected").reason, "OnCircle")
		-- A second player picking that map is put on the other circle: countdown.
		h.service:onLobby(b, "QuickPlay", { mode = "Duel", arena = "Arena_B" })
		settle(h)
		t.expect.truthy(near(b.position, onPadOf(B_ORIGIN, 2)), "opposite the waiter")
		t.expect.equal(ra.state, "Countdown")
		t.expect.equal(h.service:recordOf(b).state, "Countdown")
		-- That map is now busy: the next map with a free circle is offered.
		local c = stub(3, Vector3.new(-3, 3, 0), "Nia")
		h.service:addPlayer(c)
		h.service:onLobby(c, "QuickPlay", { mode = "Duel", arena = "Arena_B" })
		local busy = lastSent(h, c, "Rejected")
		t.expect.equal(busy.reason, "ArenaBusy")
		t.expect.equal(busy.next, "Arena_Test")
		-- c waits on Arena_Test instead; an Any map searcher is sent to c (circle waiters first).
		h.clock.t += 1
		h.service:onLobby(c, "QuickPlay", { mode = "Duel", arena = busy.next })
		settle(h)
		t.expect.equal(h.service:recordOf(c).state, "Queued")
		local d = stub(4, Vector3.new(0, 3, 4), "Rhys")
		h.service:addPlayer(d)
		h.service:onLobby(d, "QuickPlay", { mode = "Duel" })
		t.expect.equal(h.service:recordOf(d).quickStatus, "Matched", "Any map joins the player waiting on a chosen map")
		settle(h)
		t.expect.equal(h.service:recordOf(c).state, "Countdown")
		t.expect.equal(h.service:recordOf(d).state, "Countdown")
		t.expect.truthy(near(d.position, onPad(2)))
	end)

	t.test("round 7: waiting on a chosen map: cancel, fight a CPU right there, switch maps, two players arriving at once", function()
		local h = arenaHarness()
		local a = stub(1, Vector3.new(0, 3, 0), "Sierra")
		h.service:addPlayer(a)
		h.service:onLobby(a, "QuickPlay", { mode = "Duel", arena = "Arena_Test" })
		settle(h)
		local ra = h.service:recordOf(a)
		t.expect.equal(ra.state, "Queued")
		-- Cancel = LeaveFight: back to the lobby, the circle is free again (no re-claim until stepping off).
		h.service:onLobby(a, "LeaveFight", {})
		t.expect.equal(ra.state, "Lobby")
		t.expect.equal(h.stations.Arena_Test:GetAttribute("State"), "Open")
		h.service:pollPads()
		t.expect.equal(ra.state, "Lobby", "standing on the circle does not re-queue at once")
		-- Wait again, then fight a CPU right there (no move).
		h.clock.t += 1
		h.service:onLobby(a, "QuickPlay", { mode = "Duel", arena = "Arena_B" })
		settle(h)
		t.expect.equal(ra.arenaId, "Arena_B", "switched maps")
		t.expect.equal(h.stations.Arena_Test:GetAttribute("State"), "Open")
		local teleports = countSent(h, a, "Teleport")
		h.clock.t += 1
		h.service:onLobby(a, "QuickPlay", { mode = "Cpu", difficulty = "Easy", arena = "Arena_B" })
		local start = lastSent(h, a, "MatchStart")
		t.expect.truthy(start ~= nil and start.cpu == true and start.arenaId == "Arena_B", "the CPU joins on the circle")
		t.expect.equal(start.difficulty, "Easy")
		t.expect.equal(countSent(h, a, "Teleport"), teleports, "no move")
		-- Two players picking the same open map at once: one circle each, then the countdown.
		local h2 = arenaHarness()
		local p, q, walker = stub(5, Vector3.new(0, 3, 0)), stub(6, Vector3.new(2, 3, 0)), stub(7, Vector3.new(-2, 3, 0))
		for _, s in { p, q, walker } do h2.service:addPlayer(s) end
		h2.service:onLobby(p, "QuickPlay", { mode = "Duel", arena = "Arena_B" })
		h2.service:onLobby(q, "QuickPlay", { mode = "Duel", arena = "Arena_B" })
		t.expect.equal(lastSent(h2, q, "Rejected"), nil, "the second arrival gets the other circle")
		settle(h2)
		t.expect.equal(h2.service:recordOf(p).state, "Countdown")
		t.expect.equal(h2.service:recordOf(q).state, "Countdown")
		-- A challenger already on the way to the other circle: the waiter's CPU request keeps the circle.
		h2.service:onLobby(walker, "QuickPlay", { mode = "Duel", arena = "Arena_Test" })
		local w = h2.service:recordOf(walker)
		local r = stub(8, Vector3.new(4, 3, 4))
		h2.service:addPlayer(r)
		settle(h2)
		t.expect.equal(w.state, "Queued")
		h2.service:onLobby(r, "QuickPlay", { mode = "Duel", arena = "Arena_Test" })
		h2.clock.t += 1
		h2.service:onLobby(walker, "QuickPlay", { mode = "Cpu" })
		t.expect.equal(lastSent(h2, walker, "Rejected").reason, "NotAlone", "a challenger is on the way")
		t.expect.equal(w.state, "Queued", "still waiting on the circle")
		settle(h2)
		t.expect.equal(w.state, "Countdown")
	end)
end
