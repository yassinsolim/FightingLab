--!strict
-- Server duel system (contract v5 sections 0, 3, 4): pad occupancy -> countdown -> server-hosted match (PvP or CPU)
-- -> results -> return to the lobby, plus practice bookkeeping. Everything that touches Roblox (remotes, avatars,
-- attributes, positions, clocks) comes in through `deps`, so tests can drive it with stub players.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lab = ReplicatedStorage:WaitForChild("FightingLab")
local Roster = require(Lab:WaitForChild("Roster"))
local Config = require(Lab:WaitForChild("CombatConfig"))
local NetProtocol = require(Lab:WaitForChild("NetProtocol"))
local WorldIndex = require(script.Parent.WorldIndex)
local MatchHost = require(script.Parent.MatchHost)

export type Avatars = {
	freeze: (self: any, player: any) -> (),
	unfreeze: (self: any, player: any, at: CFrame?) -> (),
	reload: (self: any, player: any) -> (),
	rescue: ((self: any, player: any) -> ())?,
	isLoading: ((self: any, player: any) -> boolean)?,
}
export type Deps = {
	world: WorldIndex.Index,
	now: (() -> number)?,
	serverTime: (() -> number)?,
	positionOf: ((player: any) -> Vector3?)?,
	send: ((player: any, kind: string, payload: { [string]: any }) -> ())?,
	sendSnapshot: ((player: any, packed: any) -> ())?,
	spectatorsFor: ((origin: Vector3, exclude: { [any]: boolean }) -> { any })?,
	avatars: Avatars?,
	stations: Instance?,
	random: Random?,
}
export type Record = {
	player: any, userId: number, displayName: string, fighterId: string, state: string, arenaId: string, padSide: number,
	matchId: string, slot: number, queuedAt: number, mustStepOff: boolean, tokens: number, tokenTime: number,
	wins: number, streak: number, practiceMode: string?, lastSelect: number, lobbyTokens: number, lobbyTime: number,
}
type Station = {
	id: string, arena: WorldIndex.Arena, kind: string, folder: Instance?, published: { [string]: any },
	pads: { [number]: Record? }, participants: { [number]: Record? }, state: string,
	countdownDeadline: number, countdownEndsAt: number, host: any?, cpuSlot: number?, difficulty: string,
	fighters: { string }, resultsUntil: number?, winnerSlot: number, resultText: string, matchId: string, practiceCount: number,
}

local DuelService = {}
DuelService.__index = DuelService

local function defaultPosition(player: any): Vector3?
	if typeof(player) == "Instance" then
		local character = (player :: Player).Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then return root.Position end
		return nil
	end
	local pos = player.position
	return if typeof(pos) == "Vector3" then pos else nil
end

function DuelService.new(deps: Deps)
	local self = setmetatable({}, DuelService)
	self.deps = deps
	self.now = deps.now or os.clock
	self.serverTime = deps.serverTime or function() return workspace:GetServerTimeNow() end
	self.positionOf = deps.positionOf or defaultPosition
	self.random = deps.random or Random.new()
	self.records = {} :: { [any]: Record }
	self.stations = {} :: { [string]: Station }
	self.stationOrder = {} :: { string }
	self.matchCounter = 0
	self.padAccumulator = 0
	self.stepAccumulator = 0
	self.stationAccumulator = 0
	self.stats = { stepMs = 0, maxStepMs = 0, steps = 0, activeMatches = 0, snapshotsSent = 0, sendDrops = 0, lastSent = "" }
	for _, id in deps.world.order do self:addStation(deps.world.arenas[id]) end
	return self
end

-- Stations -----------------------------------------------------------------------------------------------------------

function DuelService:addStation(arena: WorldIndex.Arena)
	local folder: Instance? = nil
	if self.deps.stations then
		local existing = self.deps.stations:FindFirstChild(arena.id)
		folder = existing or Instance.new("Configuration")
		;(folder :: Instance).Name = arena.id
		;(folder :: Instance).Parent = self.deps.stations
	end
	local station: Station = {
		id = arena.id, arena = arena, kind = arena.kind, folder = folder, published = {},
		pads = {}, participants = {}, state = "Open", countdownDeadline = 0, countdownEndsAt = 0, host = nil,
		cpuSlot = nil, difficulty = "", fighters = {}, resultsUntil = nil, winnerSlot = 0, resultText = "", matchId = "", practiceCount = 0,
	}
	self.stations[arena.id] = station
	table.insert(self.stationOrder, arena.id)
	self:publishStation(station)
end

function DuelService:station(id: string): Station?
	return self.stations[id]
end

local function sideAttributes(station: Station, side: number): (number, string, string)
	local rec = station.participants[side] or station.pads[side]
	if rec then return rec.userId, rec.displayName, station.fighters[side] or rec.fighterId end
	if station.host and station.cpuSlot == side then return NetProtocol.CpuUserId, "CPU", station.fighters[side] or "" end
	return 0, "", ""
end

function DuelService:stationAttributes(station: Station): { [string]: any }
	local arena = station.arena
	local p1Id, p1Name, p1Fighter = sideAttributes(station, 1)
	local p2Id, p2Name, p2Fighter = sideAttributes(station, 2)
	local attrs: { [string]: any } = {
		ArenaId = arena.id, StageId = arena.stageId, DisplayName = arena.displayName, Kind = arena.kind, State = station.state,
		P1UserId = p1Id, P2UserId = p2Id, P1Name = p1Name, P2Name = p2Name, P1Fighter = p1Fighter, P2Fighter = p2Fighter,
		CountdownEndsAt = if station.state == "Countdown" then station.countdownEndsAt else 0,
		Phase = "", Round = 0, P1Rounds = 0, P2Rounds = 0, P1Health = 1, P2Health = 1, Timer = 0,
		WinnerSlot = station.winnerSlot, ResultText = station.resultText, Cpu = station.host ~= nil and station.cpuSlot ~= nil,
		Difficulty = if station.host and station.cpuSlot then station.difficulty else "", MatchId = station.matchId,
		PracticeCount = station.practiceCount,
	}
	local host = station.host
	if host then
		local s = host:summary()
		attrs.Phase = s.phase
		attrs.Round = s.round
		attrs.P1Rounds = s.scores[1]
		attrs.P2Rounds = s.scores[2]
		attrs.P1Health = math.floor(s.health[1] * 1000 + 0.5) / 1000
		attrs.P2Health = math.floor(s.health[2] * 1000 + 0.5) / 1000
		attrs.Timer = s.timer
	end
	return attrs
end

function DuelService:publishStation(station: Station)
	local folder = station.folder
	if not folder then return end
	for key, value in self:stationAttributes(station) do
		if station.published[key] ~= value then
			station.published[key] = value
			folder:SetAttribute(key, value)
		end
	end
end

-- Players ------------------------------------------------------------------------------------------------------------

local function isInstance(player: any): boolean
	return typeof(player) == "Instance"
end

function DuelService:publishRecord(rec: Record)
	local player = rec.player
	if not isInstance(player) then return end
	player:SetAttribute("FighterId", rec.fighterId)
	player:SetAttribute("DuelState", rec.state)
	player:SetAttribute("ArenaId", rec.arenaId)
	player:SetAttribute("PadSide", rec.padSide)
	player:SetAttribute("MatchId", rec.matchId)
	player:SetAttribute("QueuedAt", if rec.state == "Queued" then rec.queuedAt + (self.serverTime() - self.now()) else 0)
end

function DuelService:publishStats(rec: Record)
	local player = rec.player
	if not isInstance(player) then return end
	local stats = player:FindFirstChild("leaderstats")
	local fresh = stats == nil
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "leaderstats"
	end
	-- PlayerList column order: Wins first (primary, ranks the list), then Streak.
	for index, name in { "Wins", "Streak" } do
		local value = if name == "Wins" then rec.wins else rec.streak
		local v = stats:FindFirstChild(name)
		if not v then
			v = Instance.new("IntValue")
			v.Name = name
			local priority = Instance.new("NumberValue")
			priority.Name = "Priority"
			priority.Value = 3 - index
			priority.Parent = v
			if index == 1 then
				local primary = Instance.new("BoolValue")
				primary.Name = "IsPrimary"
				primary.Value = true
				primary.Parent = v
			end
			v.Parent = stats
		end
		(v :: IntValue).Value = value
	end
	if fresh then stats.Parent = player end
end

function DuelService:addPlayer(player: any): Record
	local existing = self.records[player]
	if existing then return existing end
	local fighter = NetProtocol.validFighter(if isInstance(player) then player:GetAttribute("FighterId") else player.fighterId) or NetProtocol.DefaultFighter
	local rec: Record = {
		player = player, userId = player.UserId or 0, displayName = player.DisplayName or player.Name or "Player",
		fighterId = fighter, state = "Lobby", arenaId = "", padSide = 0, matchId = "", slot = 0, queuedAt = 0,
		mustStepOff = false, tokens = NetProtocol.CommandBurst, tokenTime = self.now(), wins = 0, streak = 0, practiceMode = nil, lastSelect = -math.huge,
		lobbyTokens = NetProtocol.LobbyBurst, lobbyTime = self.now(),
	}
	self.records[player] = rec
	self:publishRecord(rec)
	self:publishStats(rec)
	return rec
end

function DuelService:recordOf(player: any): Record?
	return self.records[player]
end

function DuelService:canRespawn(player: any): boolean
	local rec = self.records[player]
	return rec == nil or rec.state == "Lobby" or rec.state == "Queued" or rec.state == "Countdown"
end

function DuelService:removePlayer(player: any)
	local rec = self.records[player]
	if not rec then return end
	self.records[player] = nil
	local station = self.stations[rec.arenaId]
	if station then
		if rec.state == "Queued" or rec.state == "Countdown" then
			self:leavePad(station, rec.padSide)
		elseif (rec.state == "Fighting" or rec.state == "Results") and station.host then
			self:finishMatch(station, "Disconnect", if rec.state == "Fighting" then 3 - rec.slot else nil)
		elseif rec.state == "Practice" then
			station.practiceCount = math.max(0, station.practiceCount - 1)
			self:publishStation(station)
		end
	end
end

function DuelService:sendDuel(rec: Record, kind: string, payload: { [string]: any })
	if self.records[rec.player] ~= rec then
		self.stats.sendDrops += 1
		return
	end
	local send = self.deps.send
	if send then send(rec.player, kind, payload) end
	self.stats.lastSent = kind .. " " .. tostring(payload.matchId or payload.arenaId or "")
	self.stats.lastSentAt = os.clock()
end

function DuelService:reject(rec: Record, request: string, reason: string)
	self:sendDuel(rec, "Rejected", { request = request, reason = reason })
end

local function takeToken(rec: Record, now: number): boolean
	rec.tokens = math.min(NetProtocol.CommandBurst, rec.tokens + (now - rec.tokenTime) * NetProtocol.CommandRate)
	rec.tokenTime = now
	if rec.tokens < 1 then return false end
	rec.tokens -= 1
	return true
end

-- Pads ---------------------------------------------------------------------------------------------------------------

function DuelService:onAnyPad(position: Vector3?): boolean
	if not position then return false end
	for _, station in self.stations do
		for _, pad in station.arena.pads do if WorldIndex.onPad(pad, position, 1) then return true end end
		for _, pad in station.arena.practicePads do if WorldIndex.onPad(pad, position, 1) then return true end end
	end
	return false
end

function DuelService:claimPad(station: Station, side: number, rec: Record)
	station.pads[side] = rec
	rec.state = "Queued"
	rec.arenaId = station.id
	rec.padSide = side
	rec.queuedAt = self.now()
	station.winnerSlot = 0
	station.resultText = ""
	self:publishRecord(rec)
	if station.pads[1] and station.pads[2] then
		self:startCountdown(station)
	else
		station.state = "Waiting"
		self:publishStation(station)
	end
end

function DuelService:leavePad(station: Station, side: number)
	local rec = station.pads[side]
	if not rec then return end
	station.pads[side] = nil
	local wasCountdown = station.state == "Countdown"
	rec.state = "Lobby"
	rec.arenaId = ""
	rec.padSide = 0
	self:publishRecord(rec)
	if wasCountdown then
		self:sendDuel(rec, "CountdownCancelled", { arenaId = station.id })
		local other = station.pads[3 - side]
		if other then
			other.state = "Queued"
			other.queuedAt = self.now()
			self:publishRecord(other)
			self:sendDuel(other, "CountdownCancelled", { arenaId = station.id })
		end
	end
	station.state = if station.pads[1] or station.pads[2] then "Waiting" else "Open"
	station.countdownEndsAt = 0
	self:publishStation(station)
end

function DuelService:startCountdown(station: Station)
	station.state = "Countdown"
	station.countdownDeadline = self.now() + NetProtocol.CountdownSeconds
	station.countdownEndsAt = self.serverTime() + NetProtocol.CountdownSeconds
	for side = 1, 2 do
		local rec = station.pads[side]
		if rec then
			rec.state = "Countdown"
			self:publishRecord(rec)
			self:sendDuel(rec, "Countdown", { arenaId = station.id, endsAt = station.countdownEndsAt, side = side })
		end
	end
	self:publishStation(station)
end

function DuelService:pollPads()
	for _, id in self.stationOrder do
		local station = self.stations[id]
		if station.kind == "Duel" and (station.state == "Waiting" or station.state == "Countdown") then
			for side = 1, 2 do
				local rec = station.pads[side]
				local pad = station.arena.pads[side]
				if rec then
					-- No position, or an avatar being reloaded for a fighter change, keeps the claim.
					local avatars = self.deps.avatars
					local loading = avatars ~= nil and avatars.isLoading ~= nil and avatars:isLoading(rec.player)
					local position = if loading then nil else self.positionOf(rec.player)
					if not pad or (position and not WorldIndex.onPad(pad, position, 0.75)) then self:leavePad(station, side) end
				end
			end
		end
	end
	for _, rec in self.records do
		local position = self.positionOf(rec.player)
		if rec.mustStepOff then
			if not self:onAnyPad(position) then rec.mustStepOff = false end
		elseif rec.state == "Lobby" and position then
			for _, id in self.stationOrder do
				local station = self.stations[id]
				if station.kind == "Duel" and (station.state == "Open" or station.state == "Waiting") then
					for side = 1, 2 do
						local pad = station.arena.pads[side]
						if pad and station.pads[side] == nil and WorldIndex.onPad(pad, position) then
							self:claimPad(station, side, rec)
							break
						end
					end
				end
				if rec.state ~= "Lobby" then break end
			end
		end
		if self.deps.avatars and self.deps.avatars.rescue and (rec.state == "Lobby" or rec.state == "Queued") then
			self.deps.avatars:rescue(rec.player)
		end
	end
end

-- Matches ------------------------------------------------------------------------------------------------------------

function DuelService:nextMatchId(prefix: string): string
	self.matchCounter += 1
	return ("%s#%d"):format(prefix, self.matchCounter)
end

function DuelService:pickOpponent(avoid: string?): string
	local pool = {}
	for _, id in Roster.order do if id ~= avoid then table.insert(pool, id) end end
	if #pool == 0 then return Roster.order[1] end
	return pool[self.random:NextInteger(1, #pool)]
end

local function sideInfo(rec: Record?, fighter: string, cpuName: string): { [string]: any }
	if rec then return { userId = rec.userId, name = rec.displayName, fighter = fighter } end
	return { userId = NetProtocol.CpuUserId, name = cpuName, fighter = fighter }
end

function DuelService:startMatch(station: Station, cpu: { slot: number, difficulty: string }?)
	local participants: { [number]: Record? } = { station.pads[1], station.pads[2] }
	local cpuSlot = if cpu then cpu.slot else nil
	local fighters = {}
	for slot = 1, 2 do
		local rec = participants[slot]
		fighters[slot] = if rec then rec.fighterId else self:pickOpponent(if participants[3 - slot] then (participants[3 - slot] :: Record).fighterId else nil)
	end
	local matchId = self:nextMatchId(station.id)
	local difficulty = if cpu then cpu.difficulty else ""
	station.host = MatchHost.new({
		matchId = matchId, arenaId = station.id, stageId = station.arena.stageId, p1Id = fighters[1], p2Id = fighters[2],
		cpuSlot = cpuSlot, difficulty = if cpu then cpu.difficulty else "Normal",
	})
	station.participants = participants
	station.cpuSlot = cpuSlot
	station.difficulty = difficulty
	station.fighters = fighters
	station.state = "Fighting"
	station.matchId = matchId
	station.winnerSlot = 0
	station.resultText = ""
	station.resultsUntil = nil
	station.countdownEndsAt = 0
	local p1 = sideInfo(participants[1], fighters[1], "CPU")
	local p2 = sideInfo(participants[2], fighters[2], "CPU")
	for slot = 1, 2 do
		local rec = participants[slot]
		if rec then
			rec.state = "Fighting"
			rec.matchId = matchId
			rec.slot = slot
			rec.padSide = slot
			self:publishRecord(rec)
			if self.deps.avatars then self.deps.avatars:freeze(rec.player) end
			self:sendDuel(rec, "MatchStart", {
				matchId = matchId, arenaId = station.id, stageId = station.arena.stageId, origin = station.arena.origin,
				authority = "Server", slot = slot, mode = "Match", cpu = cpuSlot ~= nil,
				difficulty = if cpuSlot then difficulty else nil, p1 = p1, p2 = p2,
			})
		end
	end
	self:publishStation(station)
end

function DuelService:resultText(station: Station, winner: number): string
	if winner ~= 1 and winner ~= 2 then return "Draw" end
	local _, name = sideAttributes(station, winner)
	return (if name ~= "" then name else "P" .. winner) .. " wins"
end

function DuelService:enterResults(station: Station)
	local host = station.host
	if not host then return end
	station.state = "Results"
	station.winnerSlot = host:winnerSlot()
	station.resultText = self:resultText(station, station.winnerSlot)
	station.resultsUntil = self.now() + NetProtocol.ResultsSeconds
	for slot = 1, 2 do
		local rec = station.participants[slot]
		if rec and rec.state == "Fighting" then
			rec.state = "Results"
			self:publishRecord(rec)
		end
	end
	self:publishStation(station)
end

-- Ends the match: leaderstats, avatars back at the exits, MatchEnd to both participants, station reopened.
function DuelService:finishMatch(station: Station, reason: string?, winnerOverride: number?)
	local host = station.host
	if not host then return end
	local winner = winnerOverride or (if station.state == "Results" then station.winnerSlot else host:winnerSlot())
	local summary = host:summary()
	local entry = host.lastEntry
	local endReason = reason or (if entry and entry.reason ~= "" then entry.reason else "KO")
	local rounds = { p1 = summary.scores[1], p2 = summary.scores[2] }
	station.host = nil
	for slot = 1, 2 do
		local rec = station.participants[slot]
		if rec then
			if winner == slot then
				rec.wins += 1
				rec.streak += 1
			elseif winner == 1 or winner == 2 then
				rec.streak = 0
			end
			local connected = self.records[rec.player] == rec
			rec.state = "Lobby"
			rec.arenaId = ""
			rec.padSide = 0
			rec.matchId = ""
			rec.slot = 0
			rec.mustStepOff = true
			if connected then
				self:publishStats(rec)
				self:publishRecord(rec)
				if self.deps.avatars then self.deps.avatars:unfreeze(rec.player, station.arena.exits["P" .. slot]) end
				self:sendDuel(rec, "MatchEnd", { matchId = host.matchId, winnerSlot = winner, reason = endReason, rounds = rounds })
			end
		end
	end
	station.participants = {}
	station.pads = {}
	station.cpuSlot = nil
	station.fighters = {}
	station.state = "Open"
	station.resultsUntil = nil
	station.winnerSlot = 0
	station.resultText = ""
	station.matchId = ""
	self:publishStation(station)
end

function DuelService:stepMatches()
	local started = os.clock()
	local active = 0
	for _, id in self.stationOrder do
		local station = self.stations[id]
		local host = station.host
		if host then
			active += 1
			local entry = host:step()
			local packed = NetProtocol.encodeEntry(entry, host.matchId)
			local sendSnapshot = self.deps.sendSnapshot
			if sendSnapshot then
				local exclude = {}
				for slot = 1, 2 do
					local rec = station.participants[slot]
					if rec and self.records[rec.player] == rec then
						exclude[rec.player] = true
						sendSnapshot(rec.player, packed)
						self.stats.snapshotsSent += 1
					end
				end
				local spectators = self.deps.spectatorsFor
				if spectators and host.steps % NetProtocol.SpectatorEvery == 0 then
					for _, player in spectators(station.arena.origin, exclude) do sendSnapshot(player, packed) end
				end
			end
			if station.state == "Fighting" and host:isOver() then self:enterResults(station) end
		end
	end
	local ms = (os.clock() - started) * 1000
	self.stats.steps += 1
	self.stats.activeMatches = active
	self.stats.stepMs += (ms - self.stats.stepMs) * 0.05
	self.stats.maxStepMs = math.max(self.stats.maxStepMs * 0.999, ms)
end

function DuelService:update(dt: number)
	local now = self.now()
	self.padAccumulator += dt
	if self.padAccumulator >= 1 / NetProtocol.PadPollHz then
		self.padAccumulator = 0
		self:pollPads()
	end
	for _, id in self.stationOrder do
		local station = self.stations[id]
		if station.state == "Countdown" and now >= station.countdownDeadline then self:startMatch(station, nil) end
	end
	self.stepAccumulator = math.min(self.stepAccumulator + dt, 0.25)
	local step = 1 / Config.FPS
	while self.stepAccumulator >= step do
		self.stepAccumulator -= step
		self:stepMatches()
	end
	for _, id in self.stationOrder do
		local station = self.stations[id]
		if station.state == "Results" and station.resultsUntil and now >= station.resultsUntil then self:finishMatch(station, nil, nil) end
	end
	self.stationAccumulator += dt
	if self.stationAccumulator >= 1 / NetProtocol.StationHz then
		self.stationAccumulator = 0
		for _, id in self.stationOrder do
			local station = self.stations[id]
			if station.host then self:publishStation(station) end
		end
	end
end

-- Client requests ----------------------------------------------------------------------------------------------------

function DuelService:onCommand(player: any, kind: unknown, a: unknown, b: unknown)
	local rec = self.records[player]
	if not rec or rec.state ~= "Fighting" then return end
	local station = self.stations[rec.arenaId]
	local host = station and station.host
	if not host or host.matchId ~= rec.matchId then return end
	if not NetProtocol.validFightCommand(kind, a, b) then return end
	if not takeToken(rec, self.now()) then return end
	host:command(rec.slot, kind :: string, a, b)
end

function DuelService:onLobby(player: any, rawKind: unknown, rawPayload: unknown)
	local rec = self.records[player]
	if not rec then return end
	-- Lobby requests are rare UI actions; a flood is dropped without replies.
	local now = self.now()
	rec.lobbyTokens = math.min(NetProtocol.LobbyBurst, rec.lobbyTokens + (now - rec.lobbyTime) * NetProtocol.LobbyRate)
	rec.lobbyTime = now
	if rec.lobbyTokens < 1 then return end
	rec.lobbyTokens -= 1
	local kind, payload = NetProtocol.parseLobby(rawKind, rawPayload)
	if not kind or not payload then
		self:reject(rec, tostring(rawKind), "Invalid")
		return
	end
	if kind == "SelectFighter" then
		self:selectFighter(rec, payload.id)
	elseif kind == "RequestCpu" then
		self:requestCpu(rec, payload.difficulty)
	elseif kind == "StartPractice" then
		self:startPractice(rec, payload)
	elseif kind == "EndPractice" then
		self:endPractice(rec)
	elseif kind == "LeaveFight" then
		self:leaveFight(rec)
	end
end

function DuelService:selectFighter(rec: Record, id: string)
	if rec.state ~= "Lobby" and rec.state ~= "Queued" then
		self:reject(rec, "SelectFighter", "Busy")
		return
	end
	local now = self.now()
	if now - rec.lastSelect < 0.25 then
		self:reject(rec, "SelectFighter", "TooFast")
		return
	end
	rec.lastSelect = now
	if id == rec.fighterId then return end
	rec.fighterId = id
	self:publishRecord(rec)
	if self.deps.avatars then self.deps.avatars:reload(rec.player) end
	local station = self.stations[rec.arenaId]
	if station then self:publishStation(station) end
end

function DuelService:requestCpu(rec: Record, difficulty: string)
	local station = self.stations[rec.arenaId]
	if rec.state ~= "Queued" or not station or station.kind ~= "Duel" then
		self:reject(rec, "RequestCpu", "NotWaiting")
		return
	end
	if station.state ~= "Waiting" or station.pads[3 - rec.padSide] ~= nil then
		self:reject(rec, "RequestCpu", "NotAlone")
		return
	end
	-- The UI offers the CPU after CpuOfferSeconds; allow a second of clock skew.
	if self.now() - rec.queuedAt < NetProtocol.CpuOfferSeconds - 1 then
		self:reject(rec, "RequestCpu", "TooSoon")
		return
	end
	self:startMatch(station, { slot = 3 - rec.padSide, difficulty = NetProtocol.validDifficulty(difficulty) or "Normal" })
end

function DuelService:practicePadAt(position: Vector3?, mode: string): Station?
	for _, id in self.stationOrder do
		local station = self.stations[id]
		local pad = if station.kind == "Practice" then station.arena.practicePads[mode] else nil
		if pad and WorldIndex.onPad(pad, position, 1.5) then return station end
	end
	return nil
end

function DuelService:startPractice(rec: Record, payload: { [string]: any })
	if rec.state ~= "Lobby" then
		self:reject(rec, "StartPractice", "Busy")
		return
	end
	local mode = payload.mode :: string
	local station = self:practicePadAt(self.positionOf(rec.player), mode)
	if not station then
		self:reject(rec, "StartPractice", "NotOnPad")
		return
	end
	local matchId = self:nextMatchId(station.id .. "/Practice")
	local opponent = payload.opponent or self:pickOpponent(rec.fighterId)
	rec.state = "Practice"
	rec.arenaId = station.id
	rec.padSide = 0
	rec.matchId = matchId
	rec.practiceMode = mode
	station.practiceCount += 1
	self:publishRecord(rec)
	if self.deps.avatars then self.deps.avatars:freeze(rec.player) end
	self:sendDuel(rec, "MatchStart", {
		matchId = matchId, arenaId = station.id, stageId = station.arena.stageId, origin = station.arena.origin,
		authority = "Local", slot = 1, mode = if mode == "Cpu" then "Match" else "Training", cpu = mode == "Cpu",
		difficulty = payload.difficulty, practice = mode,
		p1 = { userId = rec.userId, name = rec.displayName, fighter = rec.fighterId },
		p2 = { userId = NetProtocol.CpuUserId, name = if mode == "Cpu" then "CPU" else "Training Dummy", fighter = opponent },
	})
	self:publishStation(station)
end

function DuelService:endPractice(rec: Record)
	if rec.state ~= "Practice" then return end
	local station = self.stations[rec.arenaId]
	local matchId = rec.matchId
	local exit = if station then station.arena.exits[rec.practiceMode or "Training"] else nil
	rec.state = "Lobby"
	rec.arenaId = ""
	rec.matchId = ""
	rec.practiceMode = nil
	rec.mustStepOff = true
	self:publishRecord(rec)
	if self.deps.avatars then self.deps.avatars:unfreeze(rec.player, exit) end
	self:sendDuel(rec, "MatchEnd", { matchId = matchId, winnerSlot = 0, reason = "Practice", rounds = { p1 = 0, p2 = 0 } })
	if station then
		station.practiceCount = math.max(0, station.practiceCount - 1)
		self:publishStation(station)
	end
end

function DuelService:leaveFight(rec: Record)
	local station = self.stations[rec.arenaId]
	if rec.state == "Queued" or rec.state == "Countdown" then
		if station then self:leavePad(station, rec.padSide) end
		rec.mustStepOff = true
	elseif rec.state == "Fighting" and station then
		self:finishMatch(station, "Forfeit", 3 - rec.slot)
	elseif rec.state == "Results" and station then
		self:finishMatch(station, nil, nil)
	elseif rec.state == "Practice" then
		self:endPractice(rec)
	end
end

return DuelService
