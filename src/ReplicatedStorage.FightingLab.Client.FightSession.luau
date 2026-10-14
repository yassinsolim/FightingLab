--!strict
-- Client fight session (contract v5 section 5). Owns the lobby <-> fight state machine on the client:
--   Lobby -> Countdown (duel pads) -> Fight (server duel) -> Results (MatchOver) -> Lobby (MatchEnd)
--   Lobby -> Practice (local runner at the dojo) -> Lobby
-- Server sessions send inputs with Command:FireServer and render 60 Hz snapshots through RenderBuffer with an adaptive
-- delay; practice runs a MatchRunner locally at 60 Hz (instant input). All sim positions are arena-space: the
-- presentation modules translate them by the session origin (world FightOrigin; fight axis = world X).
--
-- Screen sides: the local fighter is always drawn on the LEFT and moves forward with D/right. For slot 2 the camera
-- sits on the other side of the fight line (CameraDirector.beginFight(origin, 2)) and the HUD swaps its bars, so
-- FightSession.screenSide(slot, viewSlot) = slot for viewSlot 1 and 3 - slot for viewSlot 2.
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Lab = script.Parent.Parent
local Config = require(Lab:WaitForChild("CombatConfig"))
local Roster = require(Lab:WaitForChild("Roster"))
local RenderBuffer = require(Lab:WaitForChild("RenderBuffer"))
local MatchRunner = require(Lab:WaitForChild("MatchRunner"))
local NetProtocol = require(Lab:WaitForChild("NetProtocol"))

export type State = "Lobby" | "Countdown" | "Fight" | "Results" | "Practice"
export type Controls = { enable: () -> (), disable: () -> () }
export type Deps = {
	ctx: any,
	remotes: any?,
	localPlayer: any?,
	controls: Controls?,
	clock: (() -> number)?,
	serverClock: (() -> number)?,
	arenaModel: ((arenaId: string) -> Instance?)?,
	changed: BindableEvent?,
	rejected: BindableEvent?,
	teleport: BindableEvent?,
	coreGui: boolean?,
}

local FightSession = {}
local Session = {}
Session.__index = Session

FightSession.LeaveTimeout = 2.5
FightSession.PracticeRematchSeconds = 6
local FIGHT_COMMANDS = NetProtocol.FightCommands
local PRACTICE_COMMANDS = { Reset = true, Spar = true, Difficulty = true, Mode = true, SetMode = true, SwitchMode = true, Pause = true, Opponent = true, SelectCharacters = true, Dummy = true }

function FightSession.screenSide(slot: number, viewSlot: number?): number
	if viewSlot == 2 then return 3 - slot end
	return slot
end

local function validSide(raw: unknown, fallbackFighter: string): { userId: number, name: string, fighter: string }
	local t: any = if typeof(raw) == "table" then raw else {}
	return {
		userId = if typeof(t.userId) == "number" then t.userId else 0,
		name = if typeof(t.name) == "string" then t.name else "",
		fighter = if typeof(t.fighter) == "string" and Roster.has(t.fighter) then t.fighter else fallbackFighter,
	}
end

-- Validates a MatchStart payload from the server; returns a clean copy or nil.
function FightSession.parseMatchStart(payload: unknown): { [string]: any }?
	if typeof(payload) ~= "table" then return nil end
	local p: any = payload
	if typeof(p.matchId) ~= "string" or typeof(p.origin) ~= "Vector3" then return nil end
	local authority = if p.authority == "Local" then "Local" else "Server"
	local slot = if p.slot == 2 then 2 else 1
	return {
		matchId = p.matchId, arenaId = if typeof(p.arenaId) == "string" then p.arenaId else "",
		stageId = if typeof(p.stageId) == "string" then p.stageId else Config.DefaultStage,
		origin = p.origin, authority = authority, slot = slot,
		mode = if p.mode == "Training" then "Training" else "Match", cpu = p.cpu == true,
		difficulty = NetProtocol.validDifficulty(p.difficulty), practice = if typeof(p.practice) == "string" then p.practice else nil,
		p1 = validSide(p.p1, Config.DefaultP1), p2 = validSide(p.p2, Config.DefaultP2),
	}
end

function FightSession.new(deps: Deps)
	local self = setmetatable({}, Session)
	self.deps = deps
	self.ctx = deps.ctx
	self.remotes = deps.remotes
	self.clock = deps.clock or os.clock
	self.serverClock = deps.serverClock or function() return workspace:GetServerTimeNow() end
	self.changedEvent = deps.changed or Instance.new("BindableEvent")
	self.rejectedEvent = deps.rejected or Instance.new("BindableEvent")
	self.teleportEvent = deps.teleport or Instance.new("BindableEvent")
	self.Changed = self.changedEvent.Event
	self.Rejected = self.rejectedEvent.Event
	-- The server is about to move this player's character (PLAY panel / quick travel): {reason, arenaId, delay}.
	self.Teleport = self.teleportEvent.Event
	self.current = "Lobby" :: State
	self.info = nil :: { [string]: any }?
	self.countdown = nil :: { [string]: any }?
	self.lastResult = nil :: { [string]: any }?
	self.authority = nil :: string?
	self.slot = 1
	self.origin = Vector3.zero
	self.matchId = nil :: string?
	self.buffer = RenderBuffer.new({ period = 1 / Config.FPS, adaptive = true })
	self.eventQueue = RenderBuffer.newEventQueue()
	self.runner = nil :: any
	self.accumulator = 0
	self.previousLocal = nil :: RenderBuffer.Entry?
	self.currentLocal = nil :: RenderBuffer.Entry?
	self.latestEntry = nil :: RenderBuffer.Entry?
	self.previousPhase = nil :: string?
	self.previousKO = false
	self.commandId = 0
	self.pending = nil :: { id: number, sentAt: number, acknowledgedAt: number?, startFrame: number?, move: string? }?
	self.latency = { count = 0, total = 0, max = 0, last = 0 }
	self.leaveRequestedAt = nil :: number?
	self.matchOverAt = nil :: number?
	self.eventsReceived = 0
	self.snapshotsReceived = 0
	self.lastArrival = nil :: number?
	self.gapStats = { count = 0, total = 0, bursts = 0, max = 0 }
	self.dtAverage = 1 / 60
	return self
end

function Session:gui(): any
	local ctx = self.ctx
	return ctx and ctx.gui
end

function Session:setAttr(name: string, value: any)
	local gui = self:gui()
	if gui then gui:SetAttribute(name, value) end
end

function Session:module(name: string): any
	local ctx = self.ctx
	return ctx and ctx.modules and ctx.modules[name]
end

function Session:call(moduleName: string, fn: string, ...: any)
	local m = self:module(moduleName)
	local f = m and m[fn]
	if typeof(f) == "function" then
		local ok, err = pcall(f, ...)
		if not ok then warn(("FightingLab FightSession: %s.%s failed: %s"):format(moduleName, fn, tostring(err))) end
	end
end

function Session:setState(state: State, info: { [string]: any }?)
	self.current = state
	self:setAttr("SessionState", state)
	-- Short transition trace for debugging (last 8 states with match ids).
	self.trace = self.trace or {}
	table.insert(self.trace, string.format("%s:%s@%.1f", state, tostring(self.matchId), self.clock()))
	while #self.trace > 8 do table.remove(self.trace, 1) end
	self:setAttr("SessionTrace", table.concat(self.trace, " "))
	self.changedEvent:Fire(state, info)
end

function Session:isFightActive(): boolean
	return self.current == "Fight" or self.current == "Results" or self.current == "Practice"
end

-- Local Roblox chrome around a fight: default character controls, reset button, player list.
function Session:setLobbyChrome(lobby: boolean)
	local controls = self.deps.controls
	if controls then
		if lobby then controls.enable() else controls.disable() end
	end
	if self.deps.coreGui ~= false then
		task.spawn(function()
			for _ = 1, 10 do
				local ok = pcall(function()
					StarterGui:SetCore("ResetButtonCallback", lobby)
				end)
				if ok then break end
				task.wait(0.5)
			end
		end)
		pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, lobby) end)
	end
end

-- Remote messages --------------------------------------------------------------------------------------------------

function Session:handleDuel(kind: unknown, payload: unknown)
	self.duelTrace = self.duelTrace or {}
	local p0: any = if typeof(payload) == "table" then payload else {}
	table.insert(self.duelTrace, string.format("%s:%s@%.1f", tostring(kind), tostring(p0.matchId or p0.arenaId), self.clock()))
	while #self.duelTrace > 8 do table.remove(self.duelTrace, 1) end
	self:setAttr("DuelTrace", table.concat(self.duelTrace, " "))
	if kind == "Countdown" then
		if self.current ~= "Lobby" and self.current ~= "Countdown" then return end
		local p: any = if typeof(payload) == "table" then payload else {}
		self.countdown = { arenaId = p.arenaId, endsAt = if typeof(p.endsAt) == "number" then p.endsAt else self.serverClock() + 3, side = p.side }
		self:setState("Countdown", self.countdown)
	elseif kind == "CountdownCancelled" then
		if self.current == "Countdown" then
			self.countdown = nil
			self:setState("Lobby", nil)
		end
	elseif kind == "MatchStart" then
		local info = FightSession.parseMatchStart(payload)
		if not info then return end
		if self:isFightActive() then self:teardown() end
		self:begin(info)
	elseif kind == "MatchEnd" then
		local p: any = if typeof(payload) == "table" then payload else {}
		self:setAttr("LastMatchEnd", string.format("%s w=%s r=%s @%.1f", tostring(p.matchId), tostring(p.winnerSlot), tostring(p.reason), self.clock()))
		if self.matchId ~= nil and p.matchId == self.matchId and self.current ~= "Lobby" then
			self:finish(p)
		end
	elseif kind == "Rejected" then
		self.rejectedEvent:Fire(payload)
	elseif kind == "Teleport" then
		local p: any = if typeof(payload) == "table" then payload else {}
		self.teleportEvent:Fire({
			reason = if typeof(p.reason) == "string" then p.reason else "Travel",
			arenaId = if typeof(p.arenaId) == "string" then p.arenaId else "",
			delay = if typeof(p.delay) == "number" then math.clamp(p.delay, 0, 2) else NetProtocol.TeleportDelay,
		})
	end
end

function Session:handleSnapshot(raw: unknown)
	local id = NetProtocol.matchIdOf(raw)
	if self.authority ~= "Server" or id == nil or id ~= self.matchId then
		local spectator = self:module("Spectator")
		if spectator and spectator.onSnapshot then spectator.onSnapshot(raw) end
		return
	end
	local unpacked = NetProtocol.unpackEntry(raw)
	local entry = if unpacked then RenderBuffer.parse(unpacked) else nil
	if not entry then return end
	self.snapshotsReceived += 1
	local arrival = self.clock()
	local lastArrival = self.lastArrival
	self.lastArrival = arrival
	if lastArrival then
		local gap = (arrival - lastArrival) * 1000
		local gaps = self.gapStats
		gaps.count += 1
		gaps.total += gap
		if gap < 4 then gaps.bursts += 1 end
		gaps.max = math.max(gaps.max * 0.995, gap)
		if gaps.count % 30 == 0 then
			self:setAttr("SnapGapAvgMs", gaps.total / gaps.count)
			self:setAttr("SnapGapMaxMs", gaps.max)
			self:setAttr("SnapBurstPct", gaps.bursts / gaps.count * 100)
		end
	end
	local now = self.serverClock()
	if RenderBuffer.push(self.buffer, entry, now) then
		RenderBuffer.clearEvents(self.eventQueue)
		self.pending = nil
		self:setAttr("AttackStatus", "Cancelled")
	end
	self:handleEntry(entry, false)
end

-- Session lifecycle -------------------------------------------------------------------------------------------------

function Session:arenaModel(arenaId: string): Instance?
	local find = self.deps.arenaModel
	if find then return find(arenaId) end
	local world = workspace:FindFirstChild("FightingLabWorld")
	local arenas = world and world:FindFirstChild("Arenas")
	return arenas and arenas:FindFirstChild(arenaId)
end

function Session:begin(info: { [string]: any })
	self.info = info
	self.countdown = nil
	self.authority = info.authority
	self.slot = info.slot
	self.origin = info.origin
	self.matchId = info.matchId
	self.leaveRequestedAt = nil
	self.matchOverAt = nil
	self.latestEntry = nil
	self.previousPhase = nil
	self.previousKO = false
	self.pending = nil
	self.previousLocal = nil
	self.currentLocal = nil
	self.accumulator = 0
	RenderBuffer.flush(self.buffer)
	self.buffer.epoch = -1
	RenderBuffer.clearEvents(self.eventQueue)
	self.runner = nil
	if info.authority == "Local" then
		local runner = MatchRunner.new()
		runner:configure({
			mode = info.mode, p1Id = info.p1.fighter, p2Id = info.p2.fighter, stageId = info.stageId,
			difficulty = info.difficulty or "Normal", human1 = true, human2 = false, sparring = false,
		})
		self.runner = runner
	end
	self:setAttr("TwoPlayer", false)
	self:setAttr("P2Human", info.authority == "Server" and not info.cpu)
	self:setAttr("SessionSlot", info.slot)
	self:setAttr("SessionAuthority", info.authority)
	self:setAttr("SessionMatchId", info.matchId)
	self:present(info)
	self:setLobbyChrome(false)
	self:setState(if info.authority == "Local" then "Practice" else "Fight", info)
end

function Session:sideLabel(side: { [string]: any }, slot: number, info: { [string]: any }): (string, string)
	if side.userId == NetProtocol.CpuUserId then
		local tag = if info.practice == "Training" then "DUMMY" elseif info.difficulty then "CPU · " .. string.upper(info.difficulty) else "CPU"
		return tag, ""
	end
	local mine = slot == info.slot
	return if mine then "YOU" else "P" .. slot, side.name
end

function Session:present(info: { [string]: any })
	local origin = info.origin
	-- Spectated fights give their pooled rigs back before the fight takes two.
	self:call("Spectator", "clear")
	self:call("Characters", "setOrigin", origin)
	self:call("Characters", "setCharacters", info.p1.fighter, info.p2.fighter)
	self:call("Stage", "setArena", self:arenaModel(info.arenaId), origin)
	self:call("Effects", "setOrigin", origin)
	self:call("Audio", "setOrigin", origin)
	self:call("Camera", "beginFight", origin, info.slot)
	self:call("Hud", "setViewSlot", info.slot)
	for slot, side in { info.p1, info.p2 } do
		local def = Roster.get(side.fighter)
		local tag, playerName = self:sideLabel(side, slot, info)
		self:call("Hud", "setFighterInfo", slot, {
			displayName = def.displayName, color = def.accentColor, characterId = side.fighter, maxHealth = def.stats.maxHealth,
			playerName = playerName, tag = tag,
		})
	end
	self:call("Hud", "setVisible", true)
	self:call("FighterLighting", "setActive", true)
	local input = self:module("Input")
	if input then
		self:call("Input", "releaseAll")
		self:call("Input", "setGameplayEnabled", true)
	end
end

-- Puts every presentation module back into lobby mode (the default Roblox camera follows the avatar again).
function Session:teardown()
	self:call("Input", "setGameplayEnabled", false)
	self:call("Hud", "setVisible", false)
	self:call("Characters", "endFight")
	self:call("Stage", "clearArena")
	self:call("Effects", "clear")
	self:call("FighterLighting", "setActive", false)
	self:call("Audio", "endFight")
	self:call("Camera", "endFight")
	self:setLobbyChrome(true)
	self.runner = nil
	self.authority = nil
	RenderBuffer.flush(self.buffer)
	RenderBuffer.clearEvents(self.eventQueue)
end

function Session:finish(result: { [string]: any })
	self.lastResult = {
		matchId = result.matchId, winnerSlot = if typeof(result.winnerSlot) == "number" then result.winnerSlot else 0,
		reason = if typeof(result.reason) == "string" then result.reason else "", rounds = result.rounds,
		slot = self.slot, info = self.info,
	}
	if self.current == "Fight" then
		-- Ended without a MatchOver (forfeit, disconnect): still pass through Results so the lobby UI gets the outcome.
		local info = table.clone(self.info or {})
		info.winnerSlot = self.lastResult.winnerSlot
		info.rounds = result.rounds
		info.reason = self.lastResult.reason
		info.matchEnd = self.lastResult
		self:setState("Results", info)
	end
	self:teardown()
	self.info = nil
	self.matchId = nil
	self.leaveRequestedAt = nil
	self:setState("Lobby", nil)
end

-- Public API -------------------------------------------------------------------------------------------------------

function Session:fireLobby(kind: string, payload: { [string]: any })
	local remotes = self.remotes
	if remotes and remotes.lobby then remotes.lobby:FireServer(kind, payload) end
end

function Session:startPractice(opts: { [string]: any }?): boolean
	if self.current ~= "Lobby" then return false end
	local o: any = opts or {}
	local mode = if o.mode == "Cpu" then "Cpu" else "Training"
	self:fireLobby("StartPractice", {
		mode = mode, difficulty = NetProtocol.validDifficulty(o.difficulty), opponent = NetProtocol.validFighter(o.opponent),
	})
	return true
end

function Session:leave(): boolean
	if self.current == "Practice" then
		if self.leaveRequestedAt == nil then
			self.leaveRequestedAt = self.clock()
			self:fireLobby("EndPractice", {})
		end
		return true
	elseif self.current == "Fight" or self.current == "Results" or self.current == "Countdown" then
		self:fireLobby("LeaveFight", {})
		return true
	end
	-- Waiting on a duel pad also counts as "in a fight queue".
	self:fireLobby("LeaveFight", {})
	return false
end

-- PLAY (round 5 panel, round 7 flow): VS PLAYER / VS CPU / Practice through the server; only from the lobby. Duel and
-- Cpu take an optional `arena` (the map the player picked; none = any map).
function Session:quickPlay(opts: { [string]: any }?): boolean
	if self.current ~= "Lobby" then return false end
	local o: any = opts or {}
	local mode = o.mode
	if typeof(mode) ~= "string" or NetProtocol.QuickModes[mode] ~= true then return false end
	local payload: { [string]: any } = { mode = mode, difficulty = NetProtocol.validDifficulty(o.difficulty) }
	if mode == "Practice" then
		payload.practice = if o.practice == "Cpu" then "Cpu" else "Training"
		payload.opponent = NetProtocol.validFighter(o.opponent)
	else
		payload.arena = NetProtocol.validArenaId(o.arena)
	end
	self:fireLobby("QuickPlay", payload)
	return true
end

function Session:cancelQueue(): boolean
	self:fireLobby("CancelQueue", {})
	return true
end

-- Quick travel to an arena (its ArenaId) or back to the plaza ("Plaza").
function Session:travel(to: string): boolean
	if self.current ~= "Lobby" or typeof(to) ~= "string" or to == "" then return false end
	self:fireLobby("Travel", { to = to })
	return true
end

function Session:practiceCommand(kind: string, a: any?, b: any?): boolean
	local runner = self.runner
	if self.current ~= "Practice" or not runner or not PRACTICE_COMMANDS[kind] then return false end
	local info = self.info :: any
	if kind == "Opponent" or kind == "SelectCharacters" then
		local p2 = NetProtocol.validFighter(if kind == "Opponent" then a else b)
		if not p2 then return false end
		local p1 = info.p1.fighter
		runner:configure({ mode = runner.match.mode, p1Id = p1, p2Id = p2, human1 = true, human2 = false, sparring = runner.sparring })
		info.p2.fighter = p2
		self:call("Characters", "setCharacters", p1, p2)
		self:refreshOpponentInfo()
		self:resetLocalTimeline()
		return true
	elseif kind == "Difficulty" then
		local level = NetProtocol.validDifficulty(a)
		if not level then return false end
		info.difficulty = level
		runner:configure({ difficulty = level, sparring = runner.sparring })
		self:refreshOpponentInfo()
		self:resetLocalTimeline()
		return true
	elseif kind == "SetMode" or kind == "Mode" or kind == "SwitchMode" then
		-- "SwitchMode" (lobby UI) takes the target as "Cpu"/"Training" (or "Match"); without one it toggles like "Mode".
		local current = runner.match.mode
		local mode = a
		if kind == "Mode" or (kind == "SwitchMode" and a == nil) then
			mode = if current == "Match" then "Training" else "Match"
		elseif kind == "SwitchMode" and a == "Cpu" then
			mode = "Match"
		end
		if mode ~= "Match" and mode ~= "Training" then return false end
		local ok = runner:command("SetMode", mode, nil, 1)
		if ok then
			info.mode = mode
			info.cpu = mode == "Match"
			info.practice = if mode == "Match" then "Cpu" else "Training"
			self:refreshOpponentInfo()
			self:resetLocalTimeline()
		end
		return ok
	end
	local ok = runner:command(kind, a, b, 1)
	if ok and runner.match.mode ~= info.mode then
		-- "Spar" during a CPU practice drops the runner to Training (sparring): keep info/HUD in step.
		info.mode = runner.match.mode
		info.cpu = info.mode == "Match"
		info.practice = if info.cpu then "Cpu" else "Training"
		self:refreshOpponentInfo()
		self:resetLocalTimeline()
	elseif ok and kind == "Reset" then
		self:resetLocalTimeline()
	end
	return ok
end

-- Re-labels the practice opponent bar after a mode, difficulty or opponent change ("DUMMY" / "CPU · HARD").
function Session:refreshOpponentInfo()
	local info = self.info :: any
	if not info then return end
	local def = Roster.get(info.p2.fighter)
	local tag = self:sideLabel(info.p2, 2, info)
	self:call("Hud", "setFighterInfo", 2, {
		displayName = def.displayName, color = def.accentColor, characterId = info.p2.fighter, maxHealth = def.stats.maxHealth,
		playerName = "", tag = tag,
	})
end

function Session:resetLocalTimeline()
	self.previousLocal = nil
	self.currentLocal = nil
	self.matchOverAt = nil
	self.previousPhase = nil
	self.pending = nil
end

-- ctx.send: InputController and other modules send fight input here. Server sessions only forward fight inputs.
function Session:send(kind: string, a: any?, b: any?, slot: number?)
	local commandSlot = slot or 1
	if kind == "Attack" and commandSlot == 1 then
		self.commandId += 1
		self.pending = { id = self.commandId, sentAt = self.clock() }
		b = self.commandId
		self:setAttr("InputCommandId", self.commandId)
		self:setAttr("AttackStatus", "Pending")
	end
	if self.authority == "Local" then
		local runner = self.runner
		if not runner then return end
		if PRACTICE_COMMANDS[kind] then
			self:practiceCommand(kind, a, b)
		else
			runner:command(kind, a, b, commandSlot)
		end
	elseif self.authority == "Server" and (self.current == "Fight" or self.current == "Results") then
		if FIGHT_COMMANDS[kind] and commandSlot == 1 then
			local remotes = self.remotes
			if remotes and remotes.command then remotes.command:FireServer(kind, a, b) end
		end
	end
end

function Session:setHuman(slot: number, isHuman: boolean)
	local runner = self.runner
	if runner and self.authority == "Local" then runner:setHuman(slot, isHuman) end
end

-- Frame stepping ---------------------------------------------------------------------------------------------------

function Session:acknowledge(entry: RenderBuffer.Entry)
	local pending = self.pending
	if not pending or pending.acknowledgedAt then return end
	local f = entry.fighters[self.slot]
	local now = self.clock()
	if f and f.commandId == pending.id and f.move and f.moveStartFrame then
		pending.acknowledgedAt, pending.startFrame, pending.move = now, f.moveStartFrame, f.move
		self:setAttr("AckSnapshotMs", math.max(0, (now - pending.sentAt) * 1000))
		self:setAttr("AttackStatus", "Acknowledged")
	elseif now - pending.sentAt > 1 then
		self.pending = nil
		self:setAttr("AttackStatus", "Expired")
	end
end

function Session:handleEntry(entry: RenderBuffer.Entry, immediateEvents: boolean)
	self:setAttr("ServerMode", entry.mode)
	self:setAttr("ServerSparring", entry.sparring)
	local phase = entry.phase
	if (phase ~= self.previousPhase and (phase == "Ready" or phase == "RoundOver" or phase == "MatchOver")) or (self.previousKO and not entry.ko) then
		self:call("Input", "releaseAll")
	end
	if self.previousPhase and self.previousPhase ~= phase then
		self:call("Effects", "onPhase", self.previousPhase, phase)
		self:call("Audio", "onPhase", self.previousPhase, phase)
	end
	self.previousPhase = phase
	self.previousKO = entry.ko
	self.latestEntry = entry
	self:acknowledge(entry)
	for _, e in entry.events do
		self.eventsReceived += 1
		if immediateEvents then
			self:dispatchEvent(e)
		else
			RenderBuffer.enqueueEvent(self.eventQueue, e)
		end
	end
	self:call("Hud", "onSnapshot", entry)
	self:call("FrontEnd", "onSnapshot", entry)
	if phase == "MatchOver" then
		if self.current == "Fight" then
			local info = table.clone(self.info or {})
			info.winnerSlot = if entry.scores[1] > entry.scores[2] then 1 elseif entry.scores[2] > entry.scores[1] then 2 else 0
			info.rounds = { p1 = entry.scores[1], p2 = entry.scores[2] }
			self:setState("Results", info)
		elseif self.current == "Practice" and self.matchOverAt == nil then
			self.matchOverAt = self.clock()
		end
	end
end

function Session:dispatchEvent(e: RenderBuffer.SnapEvent)
	self:call("Hud", "onEvent", e)
	self:call("Effects", "onEvent", e)
	self:call("Audio", "onEvent", e)
end

local function cloneRendered(f: RenderBuffer.FighterState): RenderBuffer.Rendered
	local r: any = table.clone(f)
	r.extrapolated = 0
	return r :: RenderBuffer.Rendered
end

function Session:localFighters(alpha: number): { RenderBuffer.Rendered }
	local entry = self.currentLocal
	if not entry then return {} end
	local prev = self.previousLocal
	local fighters = {}
	for i = 1, 2 do
		local current = entry.fighters[i]
		local rendered = cloneRendered(current)
		if prev and prev.epoch == entry.epoch then
			local old = prev.fighters[i]
			if (current.pos - old.pos).Magnitude < RenderBuffer.TeleportDistance then
				rendered.pos = old.pos:Lerp(current.pos, alpha)
				local facing = old.facing:Lerp(current.facing, alpha)
				rendered.facing = if facing.Magnitude > 0.001 then facing.Unit else current.facing
				rendered.walkPhase = old.walkPhase + (current.walkPhase - old.walkPhase) * alpha
			end
		end
		fighters[i] = rendered
	end
	return fighters
end

function Session:measurePresented(fighters: { RenderBuffer.Rendered }, renderFrame: number)
	local pending = self.pending
	local r = fighters[self.slot]
	if not pending or not r or not r.move then return end
	local started = if self.authority == "Local" then pending.id ~= nil and r.commandId == pending.id else pending.startFrame ~= nil and pending.move == r.move
	if started and r.moveFrame >= 1 then
		local ms = math.max(0, (self.clock() - pending.sentAt) * 1000)
		local stats = self.latency
		stats.count += 1
		stats.total += ms
		stats.max = math.max(stats.max, ms)
		stats.last = ms
		self:setAttr("LatencySampleCount", stats.count)
		self:setAttr("LatencyAvgMs", stats.total / stats.count)
		self:setAttr("LatencyMaxMs", stats.max)
		self:setAttr("AckPresentedMs", ms)
		self:setAttr("PresentedCommandId", pending.id)
		self:setAttr("PresentedRenderFrame", renderFrame)
		self:setAttr("AttackStatus", "Presented")
		self.pending = nil
	end
end

function Session:resetLatency()
	self.latency = { count = 0, total = 0, max = 0, last = 0 }
	self.gapStats = { count = 0, total = 0, bursts = 0, max = 0 }
	self.buffer.starved = 0
	self.buffer.frames = 0
	self.buffer.lastGrowFrame = -math.huge
	self:setAttr("LatencySampleCount", 0)
end

-- Advances the session one render frame. Returns the RenderFrame for presentation modules, or nil in the lobby.
function Session:step(dt: number): { [string]: any }?
	self.dtAverage += (dt - self.dtAverage) * 0.1
	local state = self.current
	if state == "Practice" and self.leaveRequestedAt and self.clock() - self.leaveRequestedAt > FightSession.LeaveTimeout then
		-- The server never confirmed (lost message): leave locally; it restores the avatar on its own EndPractice.
		self:finish({ matchId = self.matchId, winnerSlot = 0, reason = "Practice" })
		return nil
	end
	if state ~= "Fight" and state ~= "Results" and state ~= "Practice" then return nil end
	local now = self.serverClock()
	local fighters = {}
	local renderT = 0
	if self.authority == "Local" then
		local runner = self.runner
		local step = 1 / Config.FPS
		self.accumulator = math.min(self.accumulator + dt, 0.25)
		while runner and self.accumulator >= step do
			self.accumulator -= step
			self.previousLocal = self.currentLocal
			local parsed = RenderBuffer.parse(runner:step())
			if parsed then
				self.currentLocal = parsed
				self:handleEntry(parsed, true)
			end
		end
		local entry = self.currentLocal
		local alpha = math.min(self.accumulator / step, 1)
		renderT = if entry then entry.time + alpha * step else 0
		fighters = self:localFighters(alpha)
		if self.matchOverAt and self.clock() - self.matchOverAt > FightSession.PracticeRematchSeconds and runner then
			self.matchOverAt = nil
			runner:command("Reset", nil, nil, 1)
			self:resetLocalTimeline()
		end
	else
		renderT = RenderBuffer.renderTime(self.buffer, now)
		for i = 1, 2 do
			local sample = RenderBuffer.sampleAt(self.buffer, i, renderT)
			if sample then fighters[i] = sample end
		end
		for _, e in RenderBuffer.drainEvents(self.eventQueue, renderT) do self:dispatchEvent(e) end
		self:setAttr("NetDelayMs", self.buffer.delay * 1000)
		self:setAttr("NetStarvedPct", if self.buffer.frames > 0 then self.buffer.starved / self.buffer.frames * 100 else 0)
		self:setAttr("SnapshotsReceived", self.snapshotsReceived)
	end
	local entry = self.latestEntry
	local info = self.info or {}
	local frame = {
		now = now, dt = dt, renderFrame = renderT * Config.FPS, config = Config, fighters = fighters, entry = entry,
		mode = if entry then entry.mode else "Training", phase = if entry then entry.phase else "Ready",
		timer = if entry then entry.timer else 0, scores = if entry then entry.scores else { 0, 0 }, round = if entry then entry.round else 1,
		winner = if entry and entry.winner then entry.winner else 0, reason = if entry then entry.reason else "",
		sparring = if entry then entry.sparring else false, ko = if entry then entry.ko else false,
		paused = if entry then entry.paused == true else false, hitstop = if entry then entry.hitstop else 0,
		origin = self.origin, viewSlot = self.slot, session = self.current, arenaId = info.arenaId, matchId = self.matchId,
		authority = self.authority,
	}
	self:setAttr("RenderFrame", frame.renderFrame)
	self:setAttr("PendingEvents", #self.eventQueue.pending)
	if entry then self:setAttr("RenderDelayMs", math.max(0, (entry.time - renderT) * 1000)) end
	self:setAttr("RenderDtMs", self.dtAverage * 1000)
	self:setAttr("EventsReceived", self.eventsReceived)
	self:measurePresented(fighters, frame.renderFrame)
	return frame
end

-- Module-level API (contract section 5) over the default session --------------------------------------------------

local defaultChanged = Instance.new("BindableEvent")
local defaultRejected = Instance.new("BindableEvent")
local defaultTeleport = Instance.new("BindableEvent")
local default: any = nil
FightSession.Changed = defaultChanged.Event
FightSession.Rejected = defaultRejected.Event
FightSession.Teleport = defaultTeleport.Event
FightSession.Session = Session

local function playerControls(player: Player): Controls?
	local ok, controls = pcall(function()
		local scripts = player:WaitForChild("PlayerScripts", 10)
		local playerModule = scripts and scripts:WaitForChild("PlayerModule", 10)
		if not playerModule then return nil end
		return (require(playerModule :: ModuleScript) :: any):GetControls()
	end)
	if not ok or not controls then return nil end
	return {
		enable = function() pcall(function() controls:Enable() end) end,
		disable = function() pcall(function() controls:Disable() end) end,
	}
end

local function restoreLobbyCamera(player: Player)
	local camera = workspace.CurrentCamera
	if not camera then return end
	camera.CameraType = Enum.CameraType.Custom
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then camera.CameraSubject = humanoid end
end

function FightSession.init(ctx: any)
	local player = Players.LocalPlayer
	local controlsRef: Controls? = nil
	local session = FightSession.new({
		ctx = ctx,
		localPlayer = player,
		changed = defaultChanged,
		rejected = defaultRejected,
		teleport = defaultTeleport,
		controls = {
			enable = function() if controlsRef then controlsRef.enable() end end,
			disable = function() if controlsRef then controlsRef.disable() end end,
		},
	})
	default = session
	if not player then return end
	task.spawn(function() controlsRef = playerControls(player) end)
	task.spawn(function()
		local remotes = NetProtocol.waitClient(Lab, 60)
		if not remotes then
			warn("FightingLab FightSession: lobby/duel remotes did not appear; fights are unavailable")
			return
		end
		session.remotes = remotes
		remotes.duel.OnClientEvent:Connect(function(kind: unknown, payload: unknown) session:handleDuel(kind, payload) end)
		remotes.snapshot.OnClientEvent:Connect(function(raw: unknown) session:handleSnapshot(raw) end)
	end)
	-- A respawned avatar during a fight must not steal the fight camera; in the lobby the default camera follows it.
	player.CharacterAdded:Connect(function()
		task.defer(function()
			if not session:isFightActive() then restoreLobbyCamera(player) end
		end)
	end)
	-- Fallback way out of practice when no lobby UI is running: Backspace leaves. The lobby UI (FightingLabLobby gui)
	-- owns Backspace itself (it also closes its menu with it), so this only acts without it.
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.KeyCode ~= Enum.KeyCode.Backspace or session.current ~= "Practice" then return end
		local playerGui = player:FindFirstChildOfClass("PlayerGui")
		if playerGui and playerGui:FindFirstChild("FightingLabLobby") then return end
		session:leave()
	end)
end

function FightSession.get(): any
	return default
end
function FightSession.state(): string
	return if default then default.current else "Lobby"
end
function FightSession.info(): { [string]: any }?
	if not default then return nil end
	if default.current == "Countdown" then return default.countdown end
	return default.info
end
function FightSession.lastResult(): { [string]: any }?
	return if default then default.lastResult else nil
end
function FightSession.startPractice(opts: { [string]: any }?): boolean
	return if default then default:startPractice(opts) else false
end
function FightSession.practiceCommand(kind: string, a: any?, b: any?): boolean
	return if default then default:practiceCommand(kind, a, b) else false
end
function FightSession.leave(): boolean
	return if default then default:leave() else false
end
function FightSession.quickPlay(opts: { [string]: any }?): boolean
	return if default then default:quickPlay(opts) else false
end
function FightSession.cancelQueue(): boolean
	return if default then default:cancelQueue() else false
end
function FightSession.travel(to: string): boolean
	return if default then default:travel(to) else false
end
function FightSession.isFightActive(): boolean
	return if default then default:isFightActive() else false
end
function FightSession.viewSlot(): number
	return if default then default.slot else 1
end
function FightSession.origin(): Vector3
	return if default then default.origin else Vector3.zero
end
function FightSession.send(kind: string, a: any?, b: any?, slot: number?)
	if default then default:send(kind, a, b, slot) end
end
function FightSession.setHuman(slot: number, isHuman: boolean)
	if default then default:setHuman(slot, isHuman) end
end
function FightSession.step(dt: number): { [string]: any }?
	return if default then default:step(dt) else nil
end
function FightSession.resetLatency()
	if default then default:resetLatency() end
end

return FightSession
