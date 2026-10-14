--!strict
-- FightingLab server entry (contract v5): creates the lobby/duel remotes, waits for the world (Studio-only dev stub
-- when none appears), spawns lobby avatars as each player's fighter and runs the DuelService: duel pads, countdowns,
-- 60 Hz server-hosted matches (PvP and CPU), results, leaderstats and practice bookkeeping.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

Players.CharacterAutoLoads = false

local Lab = ReplicatedStorage:WaitForChild("FightingLab")
local NetProtocol = require(Lab:WaitForChild("NetProtocol"))
local remotes = NetProtocol.ensureServer(Lab)

local ServerLab = ServerStorage:WaitForChild("FightingLab")
local DuelFolder = ServerLab:WaitForChild("Duel")
local WorldIndex = require(DuelFolder:WaitForChild("WorldIndex"))
local DuelService = require(DuelFolder:WaitForChild("DuelService"))
local AvatarService = require(DuelFolder:WaitForChild("AvatarService"))
local Factory = require(ServerLab:WaitForChild("CharacterFactory"))
local Specs = require(ServerLab:WaitForChild("CharacterSpecs"))

-- Spectators near an arena receive 20 Hz snapshots for Client.SpectatorPresenter.
local SPECTATORS = true

local function waitForWorld(): Instance
	local started = os.clock()
	local warned = false
	while true do
		local ready = Lab:FindFirstChild("WorldReady")
		local world = workspace:FindFirstChild("FightingLabWorld")
		if world and ready and ready:IsA("BoolValue") and ready.Value then return world end
		local elapsed = os.clock() - started
		-- The dev stub never replaces a real world: it needs Studio, no world folder and no world boot script.
		if elapsed > 8 and RunService:IsStudio() and not world and not ServerScriptService:FindFirstChild("FightingLabWorldBoot") then
			warn("FightingLab: no FightingLabWorld after 8 s; building the Studio dev stub world")
			return require(DuelFolder:WaitForChild("DevWorld")).build()
		end
		if elapsed > 20 and not warned then
			warned = true
			warn("FightingLab: still waiting for workspace.FightingLabWorld / FightingLab.WorldReady")
		end
		task.wait(0.1)
	end
end

local world = waitForWorld()
local index = WorldIndex.scan(world)
if #index.order == 0 then warn("FightingLab: the world has no arenas") end
local random = Random.new()

local function spawnFrame(): CFrame?
	local spawns = index.spawns
	if #spawns == 0 then return nil end
	local spawn = spawns[random:NextInteger(1, #spawns)]
	local halfX = math.max(0, spawn.Size.X * 0.5 - 1.5)
	local halfZ = math.max(0, spawn.Size.Z * 0.5 - 1.5)
	local offset = Vector3.new(random:NextNumber(-halfX, halfX), spawn.Size.Y * 0.5, random:NextNumber(-halfZ, halfZ))
	return spawn.CFrame * CFrame.new(offset)
end

local service: any = nil
local avatars = AvatarService.new({
	factory = Factory,
	specs = Specs,
	defaultFighter = NetProtocol.DefaultFighter,
	spawnFrame = spawnFrame,
	canRespawn = function(player: Player): boolean
		return service == nil or service:canRespawn(player)
	end,
})

-- Stub participants (tests, Studio harness) are plain tables: only real Players reach remotes and avatars.
local function isPlayer(p: any): boolean
	return typeof(p) == "Instance" and p:IsA("Player")
end

local function spectatorsFor(origin: Vector3, exclude: { [any]: boolean }): { Player }
	local list = {}
	for _, player in Players:GetPlayers() do
		if not exclude[player] then
			local state = player:GetAttribute("DuelState")
			if state == "Lobby" or state == "Queued" or state == "Countdown" then
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") and (root.Position - origin).Magnitude <= NetProtocol.SpectatorRadius then
					table.insert(list, player)
				end
			end
		end
	end
	return list
end

service = DuelService.new({
	world = index,
	send = function(player: any, kind: string, payload: { [string]: any })
		if isPlayer(player) then remotes.duel:FireClient(player, kind, payload) end
	end,
	sendSnapshot = function(player: any, packed: any)
		if isPlayer(player) then remotes.snapshot:FireClient(player, packed) end
	end,
	spectatorsFor = if SPECTATORS then spectatorsFor else nil,
	avatars = {
		freeze = function(_, p: any) if isPlayer(p) then avatars:freeze(p) end end,
		unfreeze = function(_, p: any, at: CFrame?) if isPlayer(p) then avatars:unfreeze(p, at) end end,
		reload = function(_, p: any) if isPlayer(p) then avatars:reload(p) end end,
		rescue = function(_, p: any) if isPlayer(p) then avatars:rescue(p) end end,
		isLoading = function(_, p: any): boolean return isPlayer(p) and avatars:isLoading(p) end,
		-- Quick play / quick travel: real players are pivoted by AvatarService, stub players just move.
		teleport = function(_, p: any, at: CFrame)
			if isPlayer(p) then
				avatars:teleport(p, at)
			elseif typeof(p) == "table" then
				p.position = at.Position + Vector3.new(0, 3, 0)
			end
		end,
	},
	stations = remotes.stations,
	random = random,
	spawnFrame = spawnFrame,
})

local function onPlayerAdded(player: Player)
	if NetProtocol.validFighter(player:GetAttribute("FighterId")) == nil then player:SetAttribute("FighterId", NetProtocol.DefaultFighter) end
	-- Left Shift sprints in the lobby (Client.LobbySprint); Roblox's shift-lock toggle would share the key.
	pcall(function() player.DevEnableMouseLock = false end)
	service:addPlayer(player)
	avatars:attach(player)
	avatars:spawn(player, nil)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do task.spawn(onPlayerAdded, player) end
Players.PlayerRemoving:Connect(function(player)
	service:removePlayer(player)
	avatars:detach(player)
end)

remotes.lobby.OnServerEvent:Connect(function(player: Player, kind: unknown, payload: unknown)
	service:onLobby(player, kind, payload)
end)
remotes.command.OnServerEvent:Connect(function(player: Player, kind: unknown, a: unknown, b: unknown)
	service:onCommand(player, kind, a, b)
end)

local statsClock = 0
RunService.Heartbeat:Connect(function(dt: number)
	service:update(dt)
	statsClock += dt
	if statsClock >= 1 then
		statsClock = 0
		local stats = service.stats
		remotes.net:SetAttribute("ServerStepMs", math.floor(stats.stepMs * 1000 + 0.5) / 1000)
		remotes.net:SetAttribute("ServerStepMaxMs", math.floor(stats.maxStepMs * 1000 + 0.5) / 1000)
		remotes.net:SetAttribute("ActiveMatches", stats.activeMatches)
	end
end)

-- Studio-only harness for solo testing: stub opponents on pads, AI-driven stub slots, CPU-vs-CPU load matches.
if RunService:IsStudio() then
	local debugHook = Instance.new("BindableFunction")
	debugHook.Name = "FightingLabDuelDebug"
	debugHook.OnInvoke = function(command: string, ...: any): any
		local args = { ... }
		if command == "stats" then
			return table.clone(service.stats)
		elseif command == "addStub" then
			-- addStub(arenaId, side, fighterId?, name?): a stub player standing on a duel pad.
			local arena = index.arenas[args[1]]
			local pad = arena and arena.pads[args[2]]
			if not pad then return "no such pad" end
			local name = args[4] or ("Stub" .. tostring(args[2]))
			local stub = { UserId = -100 - args[2], Name = name, DisplayName = name, fighterId = args[3] or "Sierra", position = pad.position + Vector3.new(0, 3, 0) }
			service:addPlayer(stub)
			return name
		elseif command == "removeStubs" then
			for player in service.records do
				if not isPlayer(player) then service:removePlayer(player) end
			end
			return true
		elseif command == "quickStub" then
			-- quickStub(mode?, fighterId?, name?, arenaId?): a stub player in the plaza sends QuickPlay (default "Duel": joins
			-- the Quick Duel queue, so one real player can test pairing alone; with an arena it waits on that arena's circle).
			-- Returns the stub's name.
			local name = args[3] or ("Quick" .. tostring(#Players:GetPlayers() + math.random(10, 99)))
			local at = spawnFrame()
			local stub = { UserId = -200 - math.random(1, 99), Name = name, DisplayName = name, fighterId = args[2] or "Goran", position = if at then at.Position + Vector3.new(0, 3, 0) else Vector3.new(0, 3, 0) }
			service:addPlayer(stub)
			service:onLobby(stub, "QuickPlay", { mode = args[1] or "Duel", difficulty = "Normal", arena = args[4] })
			return name
		elseif command == "quickState" then
			-- quickState(): queue / reservation summary of the PLAY panel matchmaking.
			local out = {}
			for player, rec in service.records do
				table.insert(out, string.format("%s state=%s quick=%s status=%s pending=%s arena=%s side=%d", tostring(rec.displayName), rec.state, tostring(rec.quick ~= nil), rec.quickStatus, tostring(rec.pending ~= nil), rec.arenaId, rec.padSide))
			end
			for _, id in service.stationOrder do
				local st = service.stations[id]
				table.insert(out, string.format("%s %s reserved=%s incoming=%s", id, st.state, tostring(st.reserved), tostring(next(st.incoming) ~= nil)))
			end
			return table.concat(out, "\n")
		elseif command == "stubAi" then
			-- stubAi(arenaId): stub slots of the running match become CPU-driven (the network path stays PvP).
			local station = service:station(args[1])
			local host = station and station.host
			if not host then return "no match" end
			for slot = 1, 2 do
				local rec = station.participants[slot]
				if rec and not isPlayer(rec.player) then
					host.runner:setHuman(slot, false)
					host.cpuSlot = slot
				end
			end
			return true
		elseif command == "startCpu" then
			-- startCpu(arenaId, cpuSlot, difficulty): CPU-vs-CPU server match without participants (load tests).
			local station = service:station(args[1])
			if not station or station.host then return "busy" end
			local cpuSlot = args[2] or 2
			service:startMatch(station, { slot = cpuSlot, difficulty = args[3] or "Normal" })
			if station.host then station.host.runner:setHuman(3 - cpuSlot, false) end
			return station.matchId
		elseif command == "finish" then
			local station = service:station(args[1])
			if station and station.host then service:finishMatch(station, "Debug", args[2]) end
			return true
		elseif command == "setHealth" then
			-- setHealth(arenaId, slot, health): set up a KO for results/return-to-lobby checks.
			local station = service:station(args[1])
			local host = station and station.host
			if not host then return "no match" end
			host.runner.match.fighters[args[2]].health = args[3]
			return true
		elseif command == "delayLobby" then
			-- delayLobby(seconds, kind, payload): a Lobby request from the first real player after a delay
			-- (lines fight starts up with burst captures in Studio tests).
			local player = Players:GetPlayers()[1]
			if not player then return "no player" end
			task.delay(args[1] or 1, function() service:onLobby(player, args[2], args[3] or {}) end)
			return true
		elseif command == "avatarSettle" then
			-- avatarSettle(seconds): server reveal delay after dressing; 0 leaves the client AvatarGate as the only
			-- guard (cold-cache simulation for burst captures). Returns the previous value.
			local previous = AvatarService.SettleSeconds
			if typeof(args[1]) == "number" then AvatarService.SettleSeconds = math.max(0, args[1]) end
			return previous
		elseif command == "forceKo" then
			-- forceKo(arenaId, loserSlot): the loser drops now; the sim ends the round on its next step.
			local station = service:station(args[1])
			local host = station and station.host
			if not host then return "no match" end
			local match = host.runner.match
			if match.phase ~= "Fight" then return "not fighting (" .. match.phase .. ")" end
			local loser = match.fighters[args[2]]
			loser.health = 0
			loser.state = "KO"
			loser.knockdown = "FaceUp"
			match.koFrame = match.frame
			return true
		end
		return "unknown command"
	end
	debugHook.Parent = ServerStorage
end
