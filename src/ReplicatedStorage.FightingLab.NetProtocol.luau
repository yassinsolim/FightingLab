--!strict
-- Shared lobby/duel network protocol (contract v5 section 4): remote names, message kinds, payload validation,
-- player/station attribute defaults and the compact snapshot codec used on the 60 Hz server->client stream.
local Config = require(script.Parent.CombatConfig)
local Roster = require(script.Parent.Roster)
local Sim = require(script.Parent.CombatSim)

export type Remotes = {
	net: Folder,
	lobby: RemoteEvent,
	duel: RemoteEvent,
	stations: Folder,
	command: RemoteEvent,
	snapshot: RemoteEvent,
}
export type Packed = { matchId: string, p: { any } }

local NetProtocol = {}

NetProtocol.Version = 1
NetProtocol.CountdownSeconds = 3
NetProtocol.CpuOfferSeconds = 4
NetProtocol.ResultsSeconds = 3.5
NetProtocol.PadPollHz = 10
NetProtocol.StationHz = 10
NetProtocol.SpectatorEvery = 3
-- Lobby players within this distance of an arena's fight origin receive its snapshots (arenas sit 66-70 studs from
-- the plaza centre: the centre sees every arena, a player standing at one arena does not stream the far side).
NetProtocol.SpectatorRadius = 85
NetProtocol.CommandRate = 90
NetProtocol.CommandBurst = 45
NetProtocol.LobbyRate = 4
NetProtocol.LobbyBurst = 8
NetProtocol.CpuUserId = -1
NetProtocol.DefaultFighter = "Kael"
NetProtocol.Difficulties = { "Easy", "Normal", "Hard" }
NetProtocol.FightCommands = { Move = true, Block = true, Crouch = true, Attack = true }
NetProtocol.DuelStates = { Lobby = true, Queued = true, Countdown = true, Fighting = true, Results = true, Practice = true }
NetProtocol.StationStates = { Open = true, Waiting = true, Countdown = true, Fighting = true, Results = true }
NetProtocol.LobbyKinds = {
	SelectFighter = true, RequestCpu = true, StartPractice = true, EndPractice = true, LeaveFight = true,
	-- Round 5 PLAY panel: Quick Duel queue / Fight CPU / Practice (QuickPlay), leaving the queue, quick travel.
	QuickPlay = true, CancelQueue = true, Travel = true,
}
NetProtocol.DuelKinds = { Countdown = true, CountdownCancelled = true, MatchStart = true, MatchEnd = true, Rejected = true, Teleport = true }

-- PLAY panel (round 5). QuickPlay modes: "Duel" joins the matchmaking queue (paired players are teleported onto a free
-- duel arena's PadP1 / PadP2, or onto the free circle of a player already waiting there), "Cpu" teleports onto a free
-- arena's PadP1 and starts a CPU match at once, "Practice" teleports onto the dojo pad and starts practice.
NetProtocol.QuickModes = { Duel = true, Cpu = true, Practice = true }
-- After this long in the Quick Duel queue the PLAY panel offers "Fight CPU instead".
NetProtocol.QuickCpuOfferSeconds = 12
-- The server tells a client it is about to be moved (Teleport), then pivots its character this much later: the
-- client's fade-out covers the jump.
NetProtocol.TeleportDelay = 0.2
-- Pads keep the claim of a player the server just teleported onto them for this long (the client's physics may
-- still report the old position for a few frames).
NetProtocol.TravelGraceSeconds = 1.5
NetProtocol.TravelCooldown = 1
NetProtocol.QuickPlayCooldown = 0.6
NetProtocol.PlazaTravel = "Plaza"

NetProtocol.PlayerDefaults = { FighterId = "Kael", DuelState = "Lobby", ArenaId = "", PadSide = 0, MatchId = "", QuickQueue = 0, QuickStatus = "" }
NetProtocol.StationDefaults = {
	ArenaId = "", StageId = "", DisplayName = "", Kind = "Duel", State = "Open",
	P1UserId = 0, P2UserId = 0, P1Name = "", P2Name = "", P1Fighter = "", P2Fighter = "",
	CountdownEndsAt = 0, Phase = "", Round = 0, P1Rounds = 0, P2Rounds = 0, P1Health = 1, P2Health = 1, Timer = 0,
	WinnerSlot = 0, ResultText = "", Cpu = false, Difficulty = "", MatchId = "",
}

local function ensureChild(parent: Instance, className: string, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing then
		if not existing:IsA(className) then error(("FightingLab: %s.%s must be a %s"):format(parent:GetFullName(), name, className)) end
		return existing
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = parent
	return inst
end

-- Server: create (or adopt) every remote and folder of the protocol.
function NetProtocol.ensureServer(lab: Instance): Remotes
	local net = ensureChild(lab, "Folder", "Net") :: Folder
	return {
		net = net,
		lobby = ensureChild(net, "RemoteEvent", "Lobby") :: RemoteEvent,
		duel = ensureChild(net, "RemoteEvent", "Duel") :: RemoteEvent,
		stations = ensureChild(lab, "Folder", "Stations") :: Folder,
		command = ensureChild(lab, "RemoteEvent", "Command") :: RemoteEvent,
		snapshot = ensureChild(lab, "RemoteEvent", "Snapshot") :: RemoteEvent,
	}
end

-- Client: wait for the server-created remotes; returns nil when they do not appear in time.
function NetProtocol.waitClient(lab: Instance, timeout: number?): Remotes?
	local limit = timeout or 30
	local net = lab:WaitForChild("Net", limit)
	if not net then return nil end
	local lobby = net:WaitForChild("Lobby", limit)
	local duel = net:WaitForChild("Duel", limit)
	local stations = lab:WaitForChild("Stations", limit)
	local command = lab:WaitForChild("Command", limit)
	local snapshot = lab:WaitForChild("Snapshot", limit)
	if not (lobby and duel and stations and command and snapshot) then return nil end
	if not (lobby:IsA("RemoteEvent") and duel:IsA("RemoteEvent") and command:IsA("RemoteEvent") and snapshot:IsA("RemoteEvent")) then return nil end
	return { net = net :: Folder, lobby = lobby, duel = duel, stations = stations :: Folder, command = command, snapshot = snapshot }
end

function NetProtocol.validDifficulty(value: unknown): string?
	if value == "Easy" or value == "Normal" or value == "Hard" then return value :: string end
	return nil
end

function NetProtocol.validFighter(value: unknown): string?
	if typeof(value) == "string" and Roster.has(value) then return value end
	return nil
end

-- Validates a client->server Lobby message. Returns the kind and a clean payload, or nil when rejected.
function NetProtocol.parseLobby(kind: unknown, payload: unknown): (string?, { [string]: any }?)
	if typeof(kind) ~= "string" or NetProtocol.LobbyKinds[kind] ~= true then return nil, nil end
	local p: { [any]: any } = if typeof(payload) == "table" then payload :: any else {}
	if kind == "SelectFighter" then
		local id = NetProtocol.validFighter(p.id)
		if not id then return nil, nil end
		return kind, { id = id }
	elseif kind == "RequestCpu" then
		return kind, { difficulty = NetProtocol.validDifficulty(p.difficulty) or "Normal" }
	elseif kind == "StartPractice" then
		local mode = p.mode
		if mode ~= "Training" and mode ~= "Cpu" then return nil, nil end
		return kind, { mode = mode, difficulty = NetProtocol.validDifficulty(p.difficulty) or "Normal", opponent = NetProtocol.validFighter(p.opponent) }
	elseif kind == "QuickPlay" then
		local mode = p.mode
		if typeof(mode) ~= "string" or NetProtocol.QuickModes[mode] ~= true then return nil, nil end
		local clean: { [string]: any } = { mode = mode, difficulty = NetProtocol.validDifficulty(p.difficulty) or "Normal" }
		if mode == "Practice" then
			local practice = p.practice
			if practice ~= "Training" and practice ~= "Cpu" then return nil, nil end
			clean.practice = practice
			clean.opponent = NetProtocol.validFighter(p.opponent)
		end
		return kind, clean
	elseif kind == "Travel" then
		-- An arena id (letters, digits, underscores) or "Plaza"; the service checks that the arena exists.
		local to = p.to
		if typeof(to) ~= "string" or #to == 0 or #to > 48 or string.find(to, "[^%w_]") then return nil, nil end
		return kind, { to = to }
	end
	return kind, {}
end

-- Only fight inputs are ever accepted from clients on the server path.
function NetProtocol.validFightCommand(kind: unknown, a: unknown, b: unknown): boolean
	return typeof(kind) == "string" and NetProtocol.FightCommands[kind] == true and Sim.validCommand(kind, a, b)
end

local function opt(v: any): any
	if v == nil then return false end
	return v
end
local function unopt(v: any): any
	if v == false then return nil end
	return v
end
local function numberOr(v: any, fallback: number): number
	return if typeof(v) == "number" and v == v then v else fallback
end

local function packFighter(f: { [string]: any }): { any }
	local throw = f.throw
	local hit = f.lastHit
	return {
		f.pos, f.facing, f.health, f.state, opt(f.move), f.moveFrame, f.commandId or 0, f.moveStartFrame or 0,
		f.stun, f.stagger or 0, f.combo, f.crouched == true, f.walkPhase or 0, f.moveX or 0,
		if typeof(throw) == "table" then { throw.role, throw.archetype, throw.frame, throw.duration, throw.impactFrame, opt(throw.move), throw.breakWindow or 0, if throw.broken == true then (throw.breakFrame or 0) + 1 else 0 } else false,
		f.armorActive == true, opt(f.crush),
		if typeof(hit) == "table" then { hit.kind, hit.height, hit.tier, hit.counter == true, hit.frame, hit.move, hit.limb, hit.side } else false,
		f.velocityY or 0, f.airFrames or 0, f.airHits or 0, opt(f.knockdown), f.dashDirection or 0, f.characterId or "",
		opt(f.guard), f.stepDir or 0, f.stepFrame or 0, f.dashFrame or 0, f.dashTotal or 0, f.stringIndex or 0,
		f.crouchFrames or 0, opt(f.getupKind), f.rollDir or 0,
		f.surge == true, f.ultUsed == true, opt(f.stance), f.stanceFrame or 0, f.tumble == true,
	}
end

local function unpackFighter(t: unknown): { [string]: any }?
	if typeof(t) ~= "table" then return nil end
	local a = t :: { any }
	local throwRaw, hitRaw = a[15], a[18]
	local throw = if typeof(throwRaw) == "table" then { role = throwRaw[1], archetype = throwRaw[2], frame = throwRaw[3], duration = throwRaw[4], impactFrame = throwRaw[5], move = unopt(throwRaw[6]), breakWindow = throwRaw[7],
		broken = if numberOr(throwRaw[8], 0) > 0 then true else nil, breakFrame = if numberOr(throwRaw[8], 0) > 0 then numberOr(throwRaw[8], 1) - 1 else nil } else nil
	local hit = if typeof(hitRaw) == "table" then { kind = hitRaw[1], height = hitRaw[2], tier = hitRaw[3], counter = hitRaw[4] == true, frame = hitRaw[5], move = hitRaw[6], limb = hitRaw[7], side = hitRaw[8] } else nil
	local commandId, moveStart = numberOr(a[7], 0), numberOr(a[8], 0)
	return {
		pos = a[1], facing = a[2], health = a[3], state = a[4], move = unopt(a[5]), moveFrame = a[6],
		commandId = if commandId > 0 then commandId else nil, moveStartFrame = if moveStart > 0 then moveStart else nil,
		stun = a[9], stagger = a[10], combo = a[11], crouched = a[12] == true, walkPhase = a[13], moveX = a[14],
		throw = throw, armorActive = a[16] == true, crush = unopt(a[17]), lastHit = hit,
		velocityY = a[19], airFrames = a[20], airHits = a[21], knockdown = unopt(a[22]), dashDirection = a[23],
		characterId = if typeof(a[24]) == "string" and a[24] ~= "" then a[24] else nil,
		guard = unopt(a[25]), stepDir = numberOr(a[26], 0), stepFrame = numberOr(a[27], 0), dashFrame = numberOr(a[28], 0),
		dashTotal = numberOr(a[29], 0), stringIndex = numberOr(a[30], 0), crouchFrames = numberOr(a[31], 0),
		getupKind = unopt(a[32]), rollDir = numberOr(a[33], 0),
		surge = a[34] == true, ultUsed = a[35] == true, stance = unopt(a[36]), stanceFrame = numberOr(a[37], 0), tumble = a[38] == true,
	}
end

local function packEvent(e: { [string]: any }): { any }
	return {
		e.kind, e.attacker, e.target, opt(e.move), e.damage or 0, e.advantage or 0, e.frame, opt(e.point), e.combo or 0,
		e.air == true, e.counter == true, e.launch == true, e.knockdown == true, opt(e.tier), opt(e.archetype), opt(e.height), opt(e.limb),
		e.evaded == true, e.tumble == true, e.punish == true,
	}
end

local function unpackEvent(t: unknown): { [string]: any }?
	if typeof(t) ~= "table" then return nil end
	local a = t :: { any }
	return {
		kind = a[1], attacker = a[2], target = a[3], move = unopt(a[4]), damage = a[5], advantage = a[6], frame = a[7],
		point = unopt(a[8]), combo = a[9], air = a[10] == true, counter = if a[11] == true then true else nil,
		launch = if a[12] == true then true else nil, knockdown = if a[13] == true then true else nil,
		tier = unopt(a[14]), archetype = unopt(a[15]), height = unopt(a[16]), limb = unopt(a[17]),
		evaded = if a[18] == true then true else nil,
		tumble = if a[19] == true then true else nil,
		punish = if a[20] == true then true else nil,
	}
end

-- Packs a MatchRunner entry into dense arrays (no repeated key strings): roughly a third of the bytes of the
-- dictionary form, which matters at 60 Hz per participant. The outer table keeps `matchId` readable for routing.
function NetProtocol.packEntry(entry: { [string]: any }, matchId: string): Packed
	local events = {}
	for i, e in entry.events or {} do events[i] = packEvent(e) end
	local scores = entry.scores or { 0, 0 }
	return {
		matchId = matchId,
		p = {
			entry.frame, entry.epoch or 0, entry.phase, entry.phaseFrames or 0, entry.timer or 0, entry.round or 1,
			scores[1] or 0, scores[2] or 0, entry.winner or 0, entry.reason or "", entry.hitstop or 0,
			entry.ko == true, entry.paused == true, entry.sparring == true, entry.mode or "Match",
			packFighter(entry.fighters[1]), packFighter(entry.fighters[2]), events,
			entry.p1Id or "", entry.p2Id or "", entry.stageId or "", entry.p2Human == true, entry.difficulty or "Normal", entry.serverTime or 0,
			opt(entry.dummy),
		},
	}
end

-- Rebuilds the MatchRunner entry shape (the input of RenderBuffer.parse) from the binary form ({ matchId, b }), the
-- array form ({ matchId, p }) or a plain (legacy) entry.
function NetProtocol.unpackEntry(raw: unknown): { [string]: any }?
	if typeof(raw) ~= "table" then return nil end
	local packed = raw :: { [string]: any }
	if typeof(packed.b) == "buffer" then
		return NetProtocol.decodeBuffer(packed.b, if typeof(packed.matchId) == "string" then packed.matchId else nil)
	end
	local p = packed.p
	if typeof(p) ~= "table" then
		if typeof(packed.frame) == "number" then return packed end
		return nil
	end
	local a = p :: { any }
	local f1, f2 = unpackFighter(a[16]), unpackFighter(a[17])
	if not f1 or not f2 then return nil end
	local events = {}
	if typeof(a[18]) == "table" then
		for _, e in a[18] :: { any } do
			local parsed = unpackEvent(e)
			if parsed then table.insert(events, parsed) end
		end
	end
	local p1Id = if typeof(a[19]) == "string" and a[19] ~= "" then a[19] else f1.characterId
	local p2Id = if typeof(a[20]) == "string" and a[20] ~= "" then a[20] else f2.characterId
	return {
		matchId = if typeof(packed.matchId) == "string" then packed.matchId else nil,
		frame = a[1], epoch = a[2], phase = a[3], phaseFrames = a[4], timer = a[5], round = a[6],
		scores = { numberOr(a[7], 0), numberOr(a[8], 0) }, winner = a[9], reason = a[10], hitstop = a[11],
		ko = a[12] == true, paused = a[13] == true, sparring = a[14] == true, mode = a[15],
		fighters = { f1, f2 }, events = events,
		p1Id = p1Id, p2Id = p2Id, stageId = if typeof(a[21]) == "string" and a[21] ~= "" then a[21] else nil,
		p2Human = a[22] == true, difficulty = a[23], serverTime = a[24], dummy = unopt(a[25]),
	}
end

function NetProtocol.matchIdOf(raw: unknown): string?
	if typeof(raw) ~= "table" then return nil end
	local id = (raw :: any).matchId
	return if typeof(id) == "string" then id else nil
end

-- Binary snapshot codec ---------------------------------------------------------------------------------------------
-- The 60 Hz participant stream is the largest message in the game. Entries are written into a Luau `buffer` (sent
-- as { matchId, b = buffer }): floats as f32, counters as small integers, and strings through a shared table built
-- the same way on server and client from Roster/CombatConfig (unknown strings are written literally).

local CODEC_VERSION = 3
local STRINGS: { string } = {}
local STRING_INDEX: { [string]: number } = {}
local function addString(s: string?)
	if typeof(s) ~= "string" or s == "" or STRING_INDEX[s] then return end
	table.insert(STRINGS, s)
	STRING_INDEX[s] = #STRINGS
end
for _, s in {
	"Ready", "Fight", "RoundOver", "MatchOver", "Match", "Training", "KO", "TIME", "Easy", "Normal", "Hard",
	"Idle", "Walk", "Backwalk", "Crouch", "Block", "Startup", "Active", "Recovery", "Hitstun", "Blockstun", "Airborne",
	"Landing", "Getup", "Dash", "Backdash", "Throw", "Stagger", "Step", "Knockdown", "Guard", "CrouchBlock",
	"Hit", "Whiff", "Parry", "Armor", "Crush", "Counter", "ThrowStart", "ThrowHit", "ThrowBreak",
	"Light", "Medium", "Heavy", "Launch", "High", "Mid", "Low", "LeadArm", "RearArm", "LeadLeg", "RearLeg", "Body", "Head",
	"Torso", "Attacker", "Defender", "FaceUp", "FaceDown",
	"Sidestep", "Stand", "All", "BackRoll", "SideRoll", "Throw2", "LeadPunch", "RearPunch",
	-- codec v3 (round 6): stances, Surge / Ultimate events and states, the catch.
	"Stance", "Ultimate", "ultimate", "Surge", "UltStart", "UltHit", "Catch", "Kicks",
} do addString(s) end
for _, id in Roster.order do
	addString(id)
	local character = Roster.get(id)
	for _, key in character.moveOrder do
		addString(key)
		local def: any = character.moves[key]
		if def and typeof(def.anim) == "table" then addString(def.anim.archetype) end
		if def then addString(def.limb) end
	end
	local stances: any = (character :: any).stances
	if typeof(stances) == "table" then
		local keys = {}
		for key in stances do table.insert(keys, key) end
		table.sort(keys)
		for _, key in keys do addString(key) end
	end
end
for _, stage in Roster.stages do addString(stage.id) end
for _, key in Config.MoveOrder do addString(key) end
NetProtocol.StringTable = STRINGS

type Writer = { b: buffer, n: number }
local function ensure(w: Writer, bytes: number)
	local size = buffer.len(w.b)
	if w.n + bytes <= size then return end
	local grown = buffer.create(math.max(size * 2, w.n + bytes))
	buffer.copy(grown, 0, w.b, 0, w.n)
	w.b = grown
end
local function wu8(w: Writer, v: number) ensure(w, 1); buffer.writeu8(w.b, w.n, math.clamp(math.floor(v + 0.5), 0, 255)); w.n += 1 end
local function wi8(w: Writer, v: number) ensure(w, 1); buffer.writei8(w.b, w.n, math.clamp(math.floor(v + 0.5), -128, 127)); w.n += 1 end
local function wu16(w: Writer, v: number) ensure(w, 2); buffer.writeu16(w.b, w.n, math.clamp(math.floor(v + 0.5), 0, 65535)); w.n += 2 end
local function wi16(w: Writer, v: number) ensure(w, 2); buffer.writei16(w.b, w.n, math.clamp(math.floor(v + 0.5), -32768, 32767)); w.n += 2 end
local function wu32(w: Writer, v: number) ensure(w, 4); buffer.writeu32(w.b, w.n, math.clamp(math.floor(v + 0.5), 0, 4294967295)); w.n += 4 end
local function wf32(w: Writer, v: number) ensure(w, 4); buffer.writef32(w.b, w.n, if v == v then v else 0); w.n += 4 end
local function wf64(w: Writer, v: number) ensure(w, 8); buffer.writef64(w.b, w.n, v); w.n += 8 end
local function wvec(w: Writer, v: Vector3) wf32(w, v.X); wf32(w, v.Y); wf32(w, v.Z) end
-- 0 = nil, 1..250 = table index, 251 + u16 = larger index, 255 + u8 length + bytes = literal.
local function wstr(w: Writer, s: string?)
	if typeof(s) ~= "string" then wu8(w, 0) return end
	local index = STRING_INDEX[s]
	if index and index <= 250 then
		wu8(w, index)
	elseif index then
		wu8(w, 251); wu16(w, index)
	else
		local text = string.sub(s, 1, 255)
		wu8(w, 255); wu8(w, #text)
		ensure(w, #text)
		buffer.writestring(w.b, w.n, text)
		w.n += #text
	end
end

type Reader = { b: buffer, n: number }
local function ru8(r: Reader): number local v = buffer.readu8(r.b, r.n); r.n += 1; return v end
local function ri8(r: Reader): number local v = buffer.readi8(r.b, r.n); r.n += 1; return v end
local function ru16(r: Reader): number local v = buffer.readu16(r.b, r.n); r.n += 2; return v end
local function ri16(r: Reader): number local v = buffer.readi16(r.b, r.n); r.n += 2; return v end
local function ru32(r: Reader): number local v = buffer.readu32(r.b, r.n); r.n += 4; return v end
local function rf32(r: Reader): number local v = buffer.readf32(r.b, r.n); r.n += 4; return v end
local function rf64(r: Reader): number local v = buffer.readf64(r.b, r.n); r.n += 8; return v end
local function rvec(r: Reader): Vector3 return Vector3.new(rf32(r), rf32(r), rf32(r)) end
local function rstr(r: Reader): string?
	local code = ru8(r)
	if code == 0 then return nil end
	if code <= 250 then return STRINGS[code] end
	if code == 251 then return STRINGS[ru16(r)] end
	local len = ru8(r)
	local s = buffer.readstring(r.b, r.n, len)
	r.n += len
	return s
end

local function num(v: any, fallback: number): number
	return if typeof(v) == "number" and v == v and math.abs(v) < math.huge then v else fallback
end

local function writeFighter(w: Writer, f: { [string]: any })
	local throw, hit = f.throw, f.lastHit
	local flags = (if f.crouched == true then 1 else 0) + (if f.armorActive == true then 2 else 0)
		+ (if typeof(throw) == "table" then 4 else 0) + (if typeof(hit) == "table" then 8 else 0) + (if typeof(hit) == "table" and hit.counter == true then 16 else 0)
		+ (if f.surge == true then 32 else 0) + (if f.ultUsed == true then 64 else 0) + (if f.tumble == true then 128 else 0)
	wu8(w, flags)
	wvec(w, if typeof(f.pos) == "Vector3" then f.pos else Vector3.zero)
	local facing = if typeof(f.facing) == "Vector3" then f.facing else Vector3.xAxis
	wf32(w, facing.X); wf32(w, facing.Z)
	wf32(w, num(f.health, 0)); wstr(w, f.state); wstr(w, f.move); wu16(w, num(f.moveFrame, 0))
	wu32(w, num(f.commandId, 0)); wu32(w, num(f.moveStartFrame, 0)); wu16(w, num(f.stun, 0)); wu16(w, num(f.stagger, 0))
	wu8(w, num(f.combo, 0)); wf32(w, num(f.walkPhase, 0)); wf32(w, num(f.moveX, 0)); wstr(w, f.crush)
	wf32(w, num(f.velocityY, 0)); wu16(w, num(f.airFrames, 0)); wu8(w, num(f.airHits, 0)); wstr(w, f.knockdown)
	wi8(w, num(f.dashDirection, 0)); wstr(w, f.characterId); wf32(w, num(f.maxHealth, 0))
	-- OV6 additions (codec v2): guard, sidestep, dash frames, string index, crouch frames, getup.
	wstr(w, f.guard); wi8(w, num(f.stepDir, 0)); wu8(w, num(f.stepFrame, 0)); wu8(w, num(f.dashFrame, 0)); wu8(w, num(f.dashTotal, 0))
	wu8(w, num(f.stringIndex, 0)); wu16(w, num(f.crouchFrames, 0)); wstr(w, f.getupKind); wi8(w, num(f.rollDir, 0))
	-- codec v3 (round 6): signature stance (flags carry surge / ultUsed / tumble).
	wstr(w, f.stance); wu16(w, num(f.stanceFrame, 0))
	if typeof(throw) == "table" then
		wstr(w, throw.role); wstr(w, throw.archetype); wu16(w, num(throw.frame, 0)); wu16(w, num(throw.duration, 0)); wu16(w, num(throw.impactFrame, 0))
		wstr(w, throw.move); wu8(w, num(throw.breakWindow, 0)); wu8(w, if throw.broken == true then math.clamp(num(throw.breakFrame, 0) + 1, 1, 255) else 0)
	end
	if typeof(hit) == "table" then
		wstr(w, hit.kind); wstr(w, hit.height); wstr(w, hit.tier); wu32(w, num(hit.frame, 0)); wstr(w, hit.move); wstr(w, hit.limb); wi8(w, num(hit.side, 1))
	end
end

local function readFighter(r: Reader): { [string]: any }
	local flags = ru8(r)
	local f: { [string]: any } = {}
	f.pos = rvec(r)
	local fx, fz = rf32(r), rf32(r)
	f.facing = Vector3.new(fx, 0, fz)
	f.health = rf32(r); f.state = rstr(r) or "Idle"; f.move = rstr(r); f.moveFrame = ru16(r)
	local commandId, moveStart = ru32(r), ru32(r)
	f.commandId = if commandId > 0 then commandId else nil
	f.moveStartFrame = if moveStart > 0 then moveStart else nil
	f.stun = ru16(r); f.stagger = ru16(r); f.combo = ru8(r); f.walkPhase = rf32(r); f.moveX = rf32(r); f.crush = rstr(r)
	f.velocityY = rf32(r); f.airFrames = ru16(r); f.airHits = ru8(r); f.knockdown = rstr(r); f.dashDirection = ri8(r)
	f.characterId = rstr(r)
	local maxHealth = rf32(r)
	f.maxHealth = if maxHealth > 0 then maxHealth else nil
	f.guard = rstr(r); f.stepDir = ri8(r); f.stepFrame = ru8(r); f.dashFrame = ru8(r); f.dashTotal = ru8(r)
	f.stringIndex = ru8(r); f.crouchFrames = ru16(r); f.getupKind = rstr(r); f.rollDir = ri8(r)
	f.stance = rstr(r); f.stanceFrame = ru16(r)
	f.crouched = bit32.band(flags, 1) ~= 0
	f.armorActive = bit32.band(flags, 2) ~= 0
	f.surge = bit32.band(flags, 32) ~= 0
	f.ultUsed = bit32.band(flags, 64) ~= 0
	f.tumble = bit32.band(flags, 128) ~= 0
	if bit32.band(flags, 4) ~= 0 then
		f.throw = { role = rstr(r), archetype = rstr(r), frame = ru16(r), duration = ru16(r), impactFrame = ru16(r), move = rstr(r), breakWindow = ru8(r) }
		local broken = ru8(r)
		if broken > 0 then f.throw.broken = true; f.throw.breakFrame = broken - 1 end
	end
	if bit32.band(flags, 8) ~= 0 then
		f.lastHit = { kind = rstr(r), height = rstr(r), tier = rstr(r), frame = ru32(r), move = rstr(r), limb = rstr(r), side = ri8(r), counter = bit32.band(flags, 16) ~= 0 }
	end
	return f
end

local function writeEvent(w: Writer, e: { [string]: any })
	local flags = (if e.air == true then 1 else 0) + (if e.counter == true then 2 else 0) + (if e.launch == true then 4 else 0)
		+ (if e.knockdown == true then 8 else 0) + (if typeof(e.point) == "Vector3" then 16 else 0) + (if e.evaded == true then 32 else 0)
		+ (if e.tumble == true then 64 else 0) + (if e.punish == true then 128 else 0)
	wu8(w, flags)
	wstr(w, e.kind); wu8(w, num(e.attacker, 1)); wu8(w, num(e.target, 2)); wstr(w, e.move); wf32(w, num(e.damage, 0))
	wi16(w, num(e.advantage, 0)); wu32(w, num(e.frame, 0)); wu8(w, num(e.combo, 0))
	if typeof(e.point) == "Vector3" then wvec(w, e.point) end
	wstr(w, e.tier); wstr(w, e.archetype); wstr(w, e.height); wstr(w, e.limb)
end

local function readEvent(r: Reader): { [string]: any }
	local flags = ru8(r)
	local e: { [string]: any } = {}
	e.kind = rstr(r); e.attacker = ru8(r); e.target = ru8(r); e.move = rstr(r); e.damage = rf32(r)
	e.advantage = ri16(r); e.frame = ru32(r); e.combo = ru8(r)
	if bit32.band(flags, 16) ~= 0 then e.point = rvec(r) end
	e.tier = rstr(r); e.archetype = rstr(r); e.height = rstr(r); e.limb = rstr(r)
	e.air = bit32.band(flags, 1) ~= 0
	e.counter = if bit32.band(flags, 2) ~= 0 then true else nil
	e.launch = if bit32.band(flags, 4) ~= 0 then true else nil
	e.knockdown = if bit32.band(flags, 8) ~= 0 then true else nil
	e.evaded = if bit32.band(flags, 32) ~= 0 then true else nil
	e.tumble = if bit32.band(flags, 64) ~= 0 then true else nil
	e.punish = if bit32.band(flags, 128) ~= 0 then true else nil
	return e
end

function NetProtocol.encodeEntry(entry: { [string]: any }, matchId: string): { matchId: string, b: buffer }
	local w: Writer = { b = buffer.create(256), n = 0 }
	local scores = entry.scores or { 0, 0 }
	wu8(w, CODEC_VERSION)
	local flags = (if entry.ko == true then 1 else 0) + (if entry.paused == true then 2 else 0) + (if entry.sparring == true then 4 else 0) + (if entry.p2Human == true then 8 else 0)
	wu8(w, flags)
	wu32(w, num(entry.frame, 0)); wu16(w, num(entry.epoch, 0) % 65536); wstr(w, entry.phase); wu16(w, num(entry.phaseFrames, 0))
	wu16(w, num(entry.timer, 0)); wu8(w, num(entry.round, 1)); wu8(w, num(scores[1], 0)); wu8(w, num(scores[2], 0))
	wu8(w, num(entry.winner, 0)); wstr(w, entry.reason); wu8(w, num(entry.hitstop, 0)); wstr(w, entry.mode)
	wstr(w, entry.p1Id); wstr(w, entry.p2Id); wstr(w, entry.stageId); wstr(w, entry.difficulty); wf64(w, num(entry.serverTime, 0))
	wstr(w, entry.dummy)
	writeFighter(w, entry.fighters[1])
	writeFighter(w, entry.fighters[2])
	local events = entry.events or {}
	wu8(w, math.min(#events, 255))
	for i = 1, math.min(#events, 255) do writeEvent(w, events[i]) end
	local out = buffer.create(w.n)
	buffer.copy(out, 0, w.b, 0, w.n)
	return { matchId = matchId, b = out }
end

function NetProtocol.decodeBuffer(b: buffer, matchId: string?): { [string]: any }?
	local ok, result = pcall(function()
		local r: Reader = { b = b, n = 0 }
		if ru8(r) ~= CODEC_VERSION then return nil end
		local flags = ru8(r)
		local entry: { [string]: any } = { matchId = matchId }
		entry.frame = ru32(r); entry.epoch = ru16(r); entry.phase = rstr(r); entry.phaseFrames = ru16(r)
		entry.timer = ru16(r); entry.round = ru8(r); entry.scores = { ru8(r), ru8(r) }
		entry.winner = ru8(r); entry.reason = rstr(r) or ""; entry.hitstop = ru8(r); entry.mode = rstr(r)
		entry.p1Id = rstr(r); entry.p2Id = rstr(r); entry.stageId = rstr(r); entry.difficulty = rstr(r); entry.serverTime = rf64(r)
		entry.dummy = rstr(r)
		entry.ko = bit32.band(flags, 1) ~= 0
		entry.paused = bit32.band(flags, 2) ~= 0
		entry.sparring = bit32.band(flags, 4) ~= 0
		entry.p2Human = bit32.band(flags, 8) ~= 0
		entry.fighters = { readFighter(r), readFighter(r) }
		local events = {}
		for _ = 1, ru8(r) do table.insert(events, readEvent(r)) end
		entry.events = events
		if r.n ~= buffer.len(b) then return nil end
		return entry
	end)
	return if ok then result else nil
end

-- Whole seconds left on the round clock, as the HUD shows them.
function NetProtocol.timerSeconds(frames: number?): number
	return math.max(0, math.ceil((frames or 0) / Config.FPS))
end

-- Avatar appearance handshake (anti "naked flash"): after dressing a character the server publishes how many
-- accessories, layered-clothing wrap layers and rigid extras (the welded gloves, shoes, belts and fists CharacterFactory
-- marks FightingLabExtra) it has; clients keep the character hidden until theirs match.
NetProtocol.AccessoryCountAttribute = "AccessoryCount"
NetProtocol.WrapLayerCountAttribute = "WrapLayerCount"
NetProtocol.ExtraCountAttribute = "ExtraCount"
NetProtocol.ExtraAttribute = "FightingLabExtra"

function NetProtocol.appearanceCounts(model: Instance): (number, number, number)
	local accessories, wrapLayers, extras = 0, 0, 0
	for _, d in model:GetDescendants() do
		if d:IsA("Accoutrement") then
			accessories += 1
		elseif d:IsA("WrapLayer") then
			wrapLayers += 1
		elseif d:IsA("BasePart") and d:GetAttribute(NetProtocol.ExtraAttribute) == true then
			extras += 1
		end
	end
	return accessories, wrapLayers, extras
end

-- Expected counts published by the server, or nil while they are not known yet (extras: 0 when a server without the
-- attribute published).
function NetProtocol.expectedAppearance(model: Instance): (number?, number?, number?)
	local accessories = model:GetAttribute(NetProtocol.AccessoryCountAttribute)
	local wrapLayers = model:GetAttribute(NetProtocol.WrapLayerCountAttribute)
	local extras = model:GetAttribute(NetProtocol.ExtraCountAttribute)
	if typeof(accessories) ~= "number" then return nil, nil, nil end
	return accessories, if typeof(wrapLayers) == "number" then wrapLayers else 0, if typeof(extras) == "number" then extras else 0
end

return NetProtocol
