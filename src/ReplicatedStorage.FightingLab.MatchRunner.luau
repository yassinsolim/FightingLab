--!strict
local Config = require(script.Parent.CombatConfig)
local Sim = require(script.Parent.CombatSim)
local SnapshotTiming = require(script.Parent.SnapshotTiming)

export type Options = { publishFolder: Folder? }
export type AttackCommand = { id: number, move: string }
export type Setup = { mode: string?, p1Id: string?, p2Id: string?, stageId: string?, difficulty: string?, human1: boolean?, human2: boolean?, sparring: boolean? }
export type Runner = {
	match: Sim.Match,
	command: (Runner, string, any?, any?, number?) -> boolean,
	setHuman: (Runner, number, boolean) -> (),
	configure: (Runner, Setup) -> (),
	step: (Runner) -> any,
}

local MatchRunner = {}
MatchRunner.__index = MatchRunner

local function num(v: any, fallback: number): number
	return if typeof(v) == "number" and v == v and math.abs(v) < math.huge then v else fallback
end

local function serializeThrow(f: Sim.Fighter)
	local info = f.throwInfo
	if not info then return nil end
	return { role = info.role, archetype = info.archetype, frame = info.frame, duration = info.duration, impactFrame = info.impactFrame, move = info.move, breakWindow = info.breakWindow,
		broken = if info.broken then true else nil, breakFrame = if info.broken then info.breakFrame else nil }
end

local function cloneEvent(e: Sim.Event): { [string]: any }
	local raw: any = e
	return {
		kind = e.kind, attacker = e.attacker, target = e.target, move = e.move, damage = e.damage,
		advantage = e.advantage, frame = e.frame, point = e.point, combo = e.combo, air = e.air,
		counter = e.counter, launch = e.launch, knockdown = e.knockdown, tier = e.tier, archetype = e.archetype,
		height = if typeof(raw.height) == "string" then raw.height else nil,
		limb = if typeof(raw.limb) == "string" then raw.limb else nil,
		evaded = if raw.evaded == true then true else nil,
		tumble = if raw.tumble == true then true else nil,
		punish = if raw.punish == true then true else nil,
	}
end

local function serialize(match: Sim.Match, f: Sim.Fighter, index: number, acceptedIds: { [number]: number? })
	local raw: any = f
	return {
		name = f.name, characterId = f.characterId, maxHealth = f.maxHealth,
		pos = f.pos, facing = f.facing, health = f.health, state = f.state,
		move = f.move, moveName = f.moveName, moveFrame = f.moveFrame,
		commandId = acceptedIds[index],
		moveStartFrame = if f.move then match.frame - f.moveFrame + 1 else nil,
		stun = f.stun, stagger = f.stagger, combo = f.combo, crouched = f.crouched,
		walkPhase = f.walkPhase, moveX = f.input.moveX,
		throw = serializeThrow(f), armorActive = Sim.armorActive(f), crush = Sim.currentCrush(f),
		lastHit = if typeof(raw.lastHit) == "table" then raw.lastHit else nil,
		velocityY = num(raw.velocityY, 0), airFrames = num(raw.airFrames, 0), airHits = num(raw.airHits, 0),
		knockdown = if typeof(raw.knockdown) == "string" then raw.knockdown else nil,
		dashDirection = num(raw.dashDirection, 0),
		guard = if typeof(raw.guard) == "string" then raw.guard else nil,
		stepDir = num(raw.stepDir, 0), stepFrame = num(raw.stepFrame, 0),
		dashFrame = num(raw.dashFrame, 0), dashTotal = num(raw.dashTotal, 0),
		stringIndex = num(raw.stringIndex, 0), crouchFrames = num(raw.crouchFrames, 0),
		getupKind = if typeof(raw.getupKind) == "string" then raw.getupKind else nil, rollDir = num(raw.rollDir, 0),
		-- Round 6: Surge / Ultimate, signature stance, tumble.
		surge = raw.surge == true, ultUsed = raw.ultUsed == true, tumble = raw.tumbling == true,
		stance = if typeof(raw.stance) == "string" then raw.stance else nil, stanceFrame = num(raw.stanceFrame, 0),
	}
end

function MatchRunner.new(opts: Options?): Runner
	local self = setmetatable({}, MatchRunner)
	self.match = Sim.newMatch("Match")
	-- CPU randomness differs per runner (tests that need a fixed seed set match.aiSeed explicitly).
	self.match.aiSeed = math.floor(os.clock() * 1000) % 100000
	self.restDummy = "Stand"
	self.publishFolder = opts and opts.publishFolder or nil
	self.human = { true, false }
	self.sparring = false
	self.paused = false
	-- One budget per slot: in a duel both players send through the same runner.
	self.budget = { { window = 0, count = 0 }, { window = 0, count = 0 } }
	self.queued = {}
	self.accepted = {}
	self.rejected = 0
	self.epoch = 0
	self.lastPhase = self.match.phase
	self.publishedEdge = SnapshotTiming.capture(self.match, self.epoch)
	self.snapshotCounter = 0
	self:publishDebugAttributes()
	return (self :: any) :: Runner
end

function MatchRunner:bumpEpoch()
	self.epoch += 1
	local folder: Folder? = self.publishFolder
	if folder then folder:SetAttribute("Epoch", self.epoch) end
end

function MatchRunner:reject(reason: string): boolean
	self.rejected += 1
	local folder: Folder? = self.publishFolder
	if folder then
		folder:SetAttribute("RejectedCommands", self.rejected)
		folder:SetAttribute("LastRejection", reason)
	end
	return false
end

function MatchRunner:resetMatch()
	Sim.reset(self.match)
	self:bumpEpoch()
	self.paused = false
	table.clear(self.queued)
	table.clear(self.accepted)
end

function MatchRunner:setHuman(slot: number, isHuman: boolean)
	if slot ~= 1 and slot ~= 2 then error("slot must be 1 or 2") end
	self.human[slot] = isHuman
	if not isHuman then
		self.match.fighters[slot].input = Sim.newInput()
		self.queued[slot] = nil
		self.accepted[slot] = nil
	end
	self:bumpEpoch()
	self:publishDebugAttributes()
end

-- Sets up a fresh match (duel host or practice) without spending command budget.
function MatchRunner:configure(setup: Setup)
	local match: Sim.Match = self.match
	if setup.mode and setup.mode ~= match.mode then Sim.setMode(match, setup.mode) end
	if setup.p1Id or setup.p2Id then
		-- Character swaps are only legal outside a running match round; a practice opponent change restarts it.
		if match.phase == "Fight" and match.mode ~= "Training" then Sim.reset(match) end
		local ok = Sim.selectCharacters(match, setup.p1Id or match.fighters[1].characterId, setup.p2Id or match.fighters[2].characterId)
		if not ok then error("MatchRunner.configure: invalid character selection") end
	end
	if setup.stageId and not Sim.selectStage(match, setup.stageId) then error("MatchRunner.configure: invalid stage " .. setup.stageId) end
	if setup.difficulty then
		if match.phase == "Fight" and match.mode == "Match" then Sim.reset(match) end
		Sim.setDifficulty(match, setup.difficulty)
	end
	if setup.human1 ~= nil then self:setHuman(1, setup.human1) end
	if setup.human2 ~= nil then self:setHuman(2, setup.human2) end
	self.sparring = setup.sparring == true
	Sim.setDummy(match, if self.sparring then "Fight" else self.restDummy)
	self.paused = false
	table.clear(self.queued)
	table.clear(self.accepted)
	self.lastPhase = match.phase
	self:bumpEpoch()
	self:publishDebugAttributes()
end

local function allowedWhilePaused(kind: string): boolean
	return kind == "Pause" or kind == "Reset" or kind == "Mode" or kind == "SetMode" or kind == "Spar" or kind == "Difficulty" or kind == "SelectCharacters" or kind == "SelectStage" or kind == "Dummy"
end

local DUMMY_CYCLE = { Stand = "Guard", Guard = "Fight", Fight = "Stand" }

-- Practice dummy behaviour: "Stand" (never guards on its own), "Guard" (blocks everything) or "Fight" (CPU = sparring).
function MatchRunner:setDummy(mode: string)
	local match: Sim.Match = self.match
	Sim.setDummy(match, mode)
	self.sparring = mode == "Fight"
	if mode ~= "Fight" then self.restDummy = mode end
	if self.human[2] ~= true then match.fighters[2].input = Sim.newInput() end
end

function MatchRunner:command(kind: string, a: any?, b: any?, slot: number?): boolean
	local targetSlot = slot or 1
	if targetSlot ~= 1 and targetSlot ~= 2 then return self:reject("InvalidSlot") end
	if targetSlot == 2 and self.human[2] ~= true then return self:reject("P2NotHuman") end
	if kind == "Pause" then
		if typeof(a) ~= "boolean" or b ~= nil then return self:reject("InvalidPausePayload") end
	elseif not Sim.validCommand(kind, a, b) then
		return self:reject("InvalidPayload")
	end
	local now = os.clock()
	local budget = self.budget[targetSlot]
	if now - budget.window >= 1 then budget.window = now; budget.count = 0 end
	budget.count += 1
	if budget.count > Config.CommandBudget then return self:reject("RateLimit") end
	if self.paused and not allowedWhilePaused(kind) then return self:reject("Paused") end
	local match: Sim.Match = self.match
	local f = match.fighters[targetSlot]
	local input = f.input
	if kind == "Pause" then
		self.paused = a == true
		match.fighters[1].input = Sim.newInput()
		match.fighters[2].input = Sim.newInput()
		table.clear(self.queued)
		table.clear(self.accepted)
		self:bumpEpoch()
	elseif kind == "Move" then
		Sim.setMovement(match, targetSlot, a :: number, b :: number)
	elseif kind == "Block" then
		input.block = a == true
	elseif kind == "Crouch" then
		input.crouch = a == true
	elseif kind == "Attack" then
		if match.phase == "Fight" then
			local move = Sim.press(match, targetSlot, a :: string)
			self.queued[targetSlot] = if typeof(b) == "number" and move then { id = b, move = move } else nil
		end
	elseif kind == "Dummy" then
		if match.mode ~= "Training" then return self:reject("DummyNeedsTraining") end
		local current = match.dummy or "Stand"
		self:setDummy(if typeof(a) == "string" then a else DUMMY_CYCLE[current] or "Stand")
		self:bumpEpoch()
	elseif kind == "Reset" then
		self:resetMatch()
	elseif kind == "Difficulty" then
		Sim.setDifficulty(match, a :: string)
	elseif kind == "SelectCharacters" then
		if Sim.selectCharacters(match, a :: string, b :: string) then
			table.clear(self.queued); table.clear(self.accepted); self:bumpEpoch()
		else
			return self:reject("InvalidCharacterSelection")
		end
	elseif kind == "SelectStage" then
		if Sim.selectStage(match, a :: string) then self:bumpEpoch() else return self:reject("InvalidStage") end
	elseif kind == "Mode" then
		Sim.setMode(match, if match.mode == "Match" then "Training" else "Match")
		self.sparring = false; Sim.setDummy(match, self.restDummy); table.clear(self.queued); table.clear(self.accepted); self:bumpEpoch()
	elseif kind == "SetMode" then
		if match.mode ~= a then Sim.setMode(match, a :: string) else Sim.reset(match) end
		self.sparring = false; Sim.setDummy(match, self.restDummy); table.clear(self.queued); table.clear(self.accepted); self:bumpEpoch()
	elseif kind == "Spar" then
		if match.mode == "Match" then
			Sim.setMode(match, "Training")
			self:setDummy("Fight")
			table.clear(self.queued); table.clear(self.accepted); self:bumpEpoch()
		else
			self:setDummy(if self.sparring then self.restDummy else "Fight")
		end
		if self.human[2] ~= true then match.fighters[2].input = Sim.newInput() end
	end
	self:publishDebugAttributes()
	return true
end

function MatchRunner:publishDebugAttributes()
	local folder: Folder? = self.publishFolder
	if not folder then return end
	local match: Sim.Match = self.match
	folder:SetAttribute("Frame", match.frame); folder:SetAttribute("Sparring", self.sparring); folder:SetAttribute("Paused", self.paused)
	folder:SetAttribute("Mode", match.mode); folder:SetAttribute("Difficulty", match.difficulty); folder:SetAttribute("Phase", match.phase)
	folder:SetAttribute("Timer", match.timer); folder:SetAttribute("Hitstop", match.hitstop); folder:SetAttribute("Round", match.round)
	folder:SetAttribute("LearnerScore", match.scores[1]); folder:SetAttribute("TrainerScore", match.scores[2])
	folder:SetAttribute("StageId", match.stageId); folder:SetAttribute("P1Id", match.fighters[1].characterId); folder:SetAttribute("P2Id", match.fighters[2].characterId)
	folder:SetAttribute("P2Human", self.human[2] == true)
	for i, f in match.fighters do
		local prefix = if i == 1 then "Learner" else "Trainer"
		folder:SetAttribute(prefix .. "Health", f.health); folder:SetAttribute(prefix .. "MaxHealth", f.maxHealth)
		folder:SetAttribute(prefix .. "CharacterId", f.characterId); folder:SetAttribute(prefix .. "State", f.state); folder:SetAttribute(prefix .. "Pos", f.pos)
		folder:SetAttribute(prefix .. "Move", f.move or ""); folder:SetAttribute(prefix .. "Combo", f.combo); folder:SetAttribute(prefix .. "Crouched", f.crouched); folder:SetAttribute(prefix .. "MoveFrame", f.moveFrame)
		local raw: any = f
		folder:SetAttribute(prefix .. "Surge", raw.surge == true); folder:SetAttribute(prefix .. "UltUsed", raw.ultUsed == true); folder:SetAttribute(prefix .. "Stance", raw.stance or "")
	end
	folder:SetAttribute("Dummy", if match.mode == "Training" then match.dummy else nil)
	folder:SetAttribute("AcceptedCommandId", self.accepted[1]); folder:SetAttribute("AcceptedMoveStartFrame", if match.fighters[1].move then match.frame - match.fighters[1].moveFrame + 1 else nil)
end

function MatchRunner:buildEntry(events: { Sim.Event })
	local match: Sim.Match = self.match
	local outgoing = {}
	for _, e in events do table.insert(outgoing, cloneEvent(e)) end
	return {
		frame = match.frame, epoch = self.epoch, serverTime = workspace:GetServerTimeNow(), stageId = match.stageId,
		p1Id = match.fighters[1].characterId, p2Id = match.fighters[2].characterId, p2Human = self.human[2] == true,
		sparring = self.sparring, ko = match.koFrame ~= nil, mode = match.mode, phase = match.phase, phaseFrames = match.phaseFrames,
		difficulty = match.difficulty, timer = match.timer, scores = { match.scores[1], match.scores[2] }, round = match.round,
		winner = match.winner, reason = match.reason, hitstop = match.hitstop, paused = self.paused,
		dummy = if match.mode == "Training" and self.human[2] ~= true then (if self.sparring then "Fight" else match.dummy) else nil,
		fighters = { serialize(match, match.fighters[1], 1, self.accepted), serialize(match, match.fighters[2], 2, self.accepted) },
		events = outgoing,
	}
end

function MatchRunner:step()
	local events: { Sim.Event } = {}
	if not self.paused then
		if self.human[2] == true then self.match.fighters[2].dummy = nil end
		for i = 1, 2 do
			if self.human[i] ~= true and (self.sparring or self.match.mode == "Match") then
				Sim.trainerInput(self.match, i)
			end
		end
		events = Sim.step(self.match)
	end
	for i, f in self.match.fighters do
		local queued: AttackCommand? = self.queued[i]
		if queued and f.move ~= nil and f.move == queued.move and f.moveFrame <= Config.ChordFrames + 2 then
			-- Started (a 1+3 / 2+4 chord upgrades the first button's move in place, so allow a few frames).
			self.accepted[i] = queued.id
			self.queued[i] = nil
		elseif f.move ~= nil and f.moveFrame == 1 then
			self.accepted[i] = nil
			self.queued[i] = nil
		elseif f.input.attack == nil and f.chainMove == nil then
			self.queued[i] = nil
		end
	end
	if self.match.mode == "Training" and self.match.koFrame and self.match.frame - self.match.koFrame >= Config.KOResetFrames then
		self:resetMatch()
	end
	if self.match.phase ~= self.lastPhase then
		if self.match.phase == "Ready" then self:bumpEpoch() end
		self.lastPhase = self.match.phase
	end
	self.snapshotCounter += 1
	self.publishedEdge = SnapshotTiming.capture(self.match, self.epoch)
	self:publishDebugAttributes()
	local folder: Folder? = self.publishFolder
	if folder then folder:SetAttribute("LastPublishedFrame", self.match.frame) end
	return self:buildEntry(events)
end

return MatchRunner
