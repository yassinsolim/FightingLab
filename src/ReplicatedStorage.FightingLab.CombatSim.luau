--!strict
-- FightingLab combat rules (OV6): deterministic, server-authoritative 60 Hz simulation.
-- Footwork: walk (D/A), committed dash and chainable backdash (double tap), discrete sidestep arcs (one per tap of
-- W/S), stationary crouch. Guard is automatic: standing still or holding back = standing guard, holding down =
-- crouch guard; walking forward, attacking, dashing, sidestepping and recovering never guard. Moves are linear
-- unless they track/home, so a sidestep makes them whiff. Throws beat guard, are ducked by crouching and are broken
-- by the matching punch (1+3 -> 1, 2+4 -> 2). Knockdowns and getups are invulnerable.
local Config = require(script.Parent.CombatConfig)
local Roster = require(script.Parent.Roster)

export type Input = { moveX: number, moveZ: number, block: boolean, crouch: boolean, attack: string?, attackAge: number }
export type ThrowInfo = {
	role: string, move: string, archetype: string, frame: number, duration: number, impactFrame: number, breakWindow: number,
	breakButton: string, impactDone: boolean, breakTried: boolean, breakPress: string?,
	-- Set when the defender broke the grab: both stay locked for Config.ThrowBreakFrames after `breakFrame`.
	broken: boolean?, breakFrame: number?,
}
export type LastHit = { kind: "Hit"|"Counter"|"Block"|"Crush"|"Armor"|"Parry"|"Throw", height: "High"|"Mid"|"Low"|"Throw", tier: "Light"|"Medium"|"Heavy"|"Launch", counter: boolean, frame: number, move: string, limb: string, side: number }
export type Press = { button: string, frame: number, move: string? }
export type Fighter = {
	name: string, characterId: string, character: Roster.CharacterDef, pos: Vector3, facing: Vector3, health: number, maxHealth: number, state: string,
	move: string?, moveName: string?, moveFrame: number, hasHit: boolean, stun: number, stagger: number, combo: number,
	chain: number, walkPhase: number, input: Input, crouched: boolean,
	velocityY: number, airFrames: number, airHits: number, extensions: number, knockdown: "FaceUp"|"FaceDown"?, lastHit: LastHit?,
	-- Airborne and already knocked down (juggle ended or air time ran out): falls to the floor, no more hits connect.
	airLocked: boolean,
	dash: number, dashDirection: number, dashCooldown: number, lastTap: number, lastDirection: number,
	dashFrame: number, dashTotal: number, dashDistance: number, dashRequest: number, dashRequestFrame: number,
	stepDir: number, stepFrame: number, stepRequest: number, stepRequestFrame: number,
	guard: string?, dummy: string?, getupKind: string?, rollDir: number, stringIndex: number, crouchFrames: number,
	lastPress: Press?, evaded: boolean, wasSidestepping: boolean,
	aiNextAttack: number, aiPressureUntil: number, aiLastLauncherFrame: number, chainMove: string?, armorUsed: boolean, throwInfo: ThrowInfo?, lastDefendedMove: string?,
	aiIntent: string?, aiIntentUntil: number, aiIntentX: number, aiIntentZ: number, aiIntentBlock: boolean, aiIntentCrouch: boolean,
	ai: any,
}
export type Event = { kind: string, attacker: number, target: number, move: string, damage: number, advantage: number, frame: number, point: Vector3, combo: number, air: boolean, counter: boolean?, launch: boolean?, knockdown: boolean?, tier: string?, archetype: string?, height: string?, limb: string?, evaded: boolean? }
export type TrainerDifficulty = "Easy" | "Normal" | "Hard"
export type AISnapshot = { state: string, move: string?, moveFrame: number, pos: Vector3, health: number, crouched: boolean, hasHit: boolean, lastDefendedMove: string?, stepFrame: number, guard: string?, velocityY: number }
export type Match = {
	fighters: { Fighter }, frame: number, koFrame: number?, mode: string, phase: string,
	phaseFrames: number, timer: number, scores: { number }, round: number, winner: number, reason: string, hitstop: number,
	difficulty: TrainerDifficulty, stageId: string, aiHistory: { [number]: { AISnapshot } }, aiHistoryFrame: number, dummy: string, aiSeed: number,
}

local Sim = {}
-- A string follow-up can be input from the first frame of the previous hit until this many frames after its last
-- active frame (it then starts right after those active frames, cancelling the recovery).
Sim.ChainLate = 14
-- States in which a fighter cannot start an action on its own.
local LOCKED = { Startup=true, Active=true, Recovery=true, Hitstun=true, Blockstun=true, Airborne=true, Landing=true, Getup=true, Dash=true, Backdash=true, Sidestep=true, KO=true, Throw=true, Stagger=true }
local FREE = { Idle=true, Walk=true, Backwalk=true, Crouch=true }
Sim.LockedStates = LOCKED
Sim.FreeStates = FREE

local function flat(v: Vector3): Vector3 return Vector3.new(v.X, 0, v.Z) end
function Sim.lateral(f: Vector3): Vector3 return Vector3.new(f.Z, 0, -f.X) end
function Sim.newInput(): Input return { moveX=0, moveZ=0, block=false, crouch=false, attack=nil, attackAge=0 } end
local function easeOut(t: number): number local u = 1 - math.clamp(t, 0, 1); return 1 - u * u end
local function easeInOut(t: number): number return (1 - math.cos(math.pi * math.clamp(t, 0, 1))) / 2 end
Sim.easeOut = easeOut
Sim.easeInOut = easeInOut

local function isStage(id: string): boolean
	for _, stage in Roster.stages do
		if stage.id == id then return true end
	end
	return false
end

local function moveDef(f: Fighter, move: string): Roster.MoveDef
	local rosterMove = f.character.moves[move]
	if rosterMove then return rosterMove end
	local legacy = Config.Moves[move]
	assert(legacy ~= nil, "unknown move " .. move .. " for " .. f.characterId)
	return (legacy :: any) :: Roster.MoveDef
end
Sim.moveDef = moveDef

local function total(def: Roster.MoveDef): number
	return def.startup + def.active + def.recovery
end

local function hitStun(def: Roster.MoveDef): number
	if typeof(def.onHit) == "number" then
		return math.max(1, (def.onHit :: number) + def.active + def.recovery - 1)
	end
	return Config.LandingFrames + Config.GetupFrames
end

local function blockStun(def: Roster.MoveDef): number
	return math.max(1, def.onBlock + def.active + def.recovery - 1)
end

function Sim.derivedHitStun(move: Roster.MoveDef): number return hitStun(move) end
function Sim.derivedBlockStun(move: Roster.MoveDef): number return blockStun(move) end

function Sim.newFighter(name: string, pos: Vector3, facing: Vector3, characterId: string?): Fighter
	local id = characterId or if name == "TRAINER" or name == "Trainer" then Config.DefaultP2 else Config.DefaultP1
	local character = Roster.get(id)
	return {
		name=name, characterId=id, character=character, pos=flat(pos), facing=flat(facing).Unit, health=character.stats.maxHealth, maxHealth=character.stats.maxHealth,
		state="Idle", move=nil, moveName=nil, moveFrame=0, hasHit=false, stun=0, stagger=0, combo=0, chain=0, walkPhase=0,
		input=Sim.newInput(), crouched=false, velocityY=0, airFrames=0, airHits=0, extensions=0, knockdown=nil, lastHit=nil, airLocked=false,
		dash=0, dashDirection=0, dashCooldown=0, lastTap=-100, lastDirection=0,
		dashFrame=0, dashTotal=0, dashDistance=0, dashRequest=0, dashRequestFrame=-100,
		stepDir=0, stepFrame=0, stepRequest=0, stepRequestFrame=-100,
		guard="Stand", dummy=nil, getupKind=nil, rollDir=0, stringIndex=0, crouchFrames=0,
		lastPress=nil, evaded=false, wasSidestepping=false,
		aiNextAttack=0, aiPressureUntil=0, aiLastLauncherFrame=-1000, chainMove=nil, armorUsed=false, throwInfo=nil, lastDefendedMove=nil,
		aiIntent=nil, aiIntentUntil=0, aiIntentX=0, aiIntentZ=0, aiIntentBlock=false, aiIntentCrouch=false, ai=nil,
	}
end

local function freshFighters(p1Id: string?, p2Id: string?): { Fighter }
	local h = Config.StartDistance / 2
	return { Sim.newFighter("LEARNER", Vector3.new(-h,0,0), Vector3.xAxis, p1Id), Sim.newFighter("TRAINER", Vector3.new(h,0,0), -Vector3.xAxis, p2Id) }
end

-- Training dummy behaviour for slot 2 ("Stand" never guards on its own, "Guard" guards everything, "Fight" = CPU).
local function applyDummy(m: Match)
	local f = m.fighters[2]
	if m.mode == "Training" and m.dummy ~= "Fight" then f.dummy = m.dummy else f.dummy = nil end
	m.fighters[1].dummy = nil
end

function Sim.newMatch(mode: string?, p1Id: string?, p2Id: string?, stageId: string?): Match
	local isMatch = mode == "Match"
	local stage = stageId or Config.DefaultStage
	assert(isStage(stage), "invalid stage")
	local m: Match = { fighters=freshFighters(p1Id, p2Id), frame=0, koFrame=nil, mode=if isMatch then "Match" else "Training", phase=if isMatch then "Ready" else "Fight", phaseFrames=if isMatch then Config.ReadyFrames else 0, timer=Config.RoundFrames, scores={0,0}, round=1, winner=0, reason="", hitstop=0, difficulty="Normal", stageId=stage, aiHistory={}, aiHistoryFrame=-1, dummy="Stand", aiSeed=0 }
	applyDummy(m)
	return m
end

function Sim.reset(m: Match)
	local p1, p2 = m.fighters[1].characterId, m.fighters[2].characterId
	local fresh = Sim.newMatch(m.mode, p1, p2, m.stageId)
	m.fighters=fresh.fighters; m.koFrame=nil; m.phase=fresh.phase; m.phaseFrames=fresh.phaseFrames
	m.timer=fresh.timer; m.scores={0,0}; m.round=1; m.winner=0; m.reason=""; m.hitstop=0
	m.aiHistory={}; m.aiHistoryFrame=-1
	applyDummy(m)
end

function Sim.selectCharacters(m: Match, p1Id: string, p2Id: string): boolean
	if not Roster.has(p1Id) or not Roster.has(p2Id) then return false end
	if m.phase == "Fight" and m.mode ~= "Training" then return false end
	local fresh = Sim.newMatch(m.mode, p1Id, p2Id, m.stageId)
	m.fighters=fresh.fighters; m.koFrame=nil; m.phase=fresh.phase; m.phaseFrames=fresh.phaseFrames; m.timer=fresh.timer
	m.scores={0,0}; m.round=1; m.winner=0; m.reason=""; m.hitstop=0
	m.aiHistory={}; m.aiHistoryFrame=-1
	applyDummy(m)
	return true
end

function Sim.selectStage(m: Match, stageId: string): boolean
	if not isStage(stageId) then return false end
	m.stageId = stageId
	return true
end

function Sim.setMode(m: Match, mode: string)
	assert(mode=="Match" or mode=="Training", "invalid mode")
	m.mode=mode; Sim.reset(m)
end

-- Practice dummy behaviour (Training only): "Stand" | "Guard" | "Fight". Returns false for an invalid mode.
function Sim.setDummy(m: Match, mode: string): boolean
	if mode ~= "Stand" and mode ~= "Guard" and mode ~= "Fight" then return false end
	-- A dummy that starts fighting gets a fresh CPU brain: it did not watch what happened while it stood or guarded.
	if mode == "Fight" and m.dummy ~= "Fight" then m.fighters[2].ai = nil end
	m.dummy = mode
	applyDummy(m)
	return true
end
Sim.applyDummy = applyDummy

function Sim.difficultyParams(level: string?): any
	local AI = require(script.Parent.CombatAI) :: any
	return AI.params(level)
end
function Sim.setDifficulty(m: Match, level: string)
	assert(level == "Easy" or level == "Normal" or level == "Hard", "invalid difficulty")
	if m.phase == "Fight" and m.mode == "Match" then return end
	m.difficulty = (level :: any) :: TrainerDifficulty
	for _, f in m.fighters do f.aiNextAttack = 0; f.ai = nil end
end
function Sim.isLocked(f: Fighter): boolean return f.health<=0 or LOCKED[f.state]==true end
function Sim.isFree(f: Fighter): boolean return f.health>0 and FREE[f.state]==true and f.move==nil end
function Sim.totalFramesFor(f: Fighter, name: string): number return total(moveDef(f, name)) end
function Sim.totalFrames(name: string): number
	local character = Roster.get(Config.DefaultP1)
	local def = character.moves[name] or Config.Moves[name]
	assert(def ~= nil, "unknown move " .. name)
	return total((def :: any) :: Roster.MoveDef)
end

-- Lane test: the target must be in front within reach and inside the lane half-width.
function Sim.reach(a: Fighter, t: Fighter, name: string): (boolean, number, number)
	local v = moveDef(a, name); local d = flat(t.pos-a.pos); local along = d:Dot(a.facing)
	local side = (d-a.facing*along).Magnitude
	local effectiveRange = if v.height == "Throw" then math.max(v.range, Config.Separation + 0.05) else v.range
	return along > 0 and along <= effectiveRange and side <= v.width, along, side
end

-- Input --------------------------------------------------------------------------------------------------------------

local function lastToken(input: string): string
	local token = input:match("[^,]+$") or input
	token = token:gsub("^%s+", ""):gsub("%s+$", "")
	return token
end
Sim.lastToken = lastToken

-- Direction contexts tried in order when a button is pressed (most specific first, "n" = neutral).
local function directionContexts(f: Fighter): { string }
	local x = f.input.moveX
	if f.state == "Dash" or (f.dashRequest > 0 and f.move == nil) then return { "dash", "f", "n" } end
	if f.state == "Sidestep" or (f.stepRequest ~= 0 and f.move == nil) then return { "ss", "n" } end
	if f.state == "Backdash" then return { "b", "n" } end
	if f.input.crouch then
		if x > 0 then return { "df", "d", "n" } end
		if x < 0 then return { "db", "d", "n" } end
		return { "d", "n" }
	end
	if x > 0 then return { "f", "n" } end
	if x < 0 then return { "b", "n" } end
	return { "n" }
end
Sim.directionContexts = directionContexts

local inputIndexCache: { [any]: { [string]: string } } = {}
local function inputIndex(character: Roster.CharacterDef): { [string]: string }
	local index = inputIndexCache[character]
	if index then return index end
	index = {}
	for _, key in character.moveOrder do
		local def = character.moves[key]
		if def.chainFrom == nil and index[def.input] == nil then index[def.input] = key end
	end
	inputIndexCache[character] = index
	return index
end

local function chainWindowOpen(f: Fighter, source: Roster.MoveDef): boolean
	return f.moveFrame >= 1 and f.moveFrame <= source.startup + source.active + Sim.ChainLate
end
Sim.chainWindowOpen = chainWindowOpen

-- Resolves a button press (Config.Buttons) to a move key for the fighter's current context.
function Sim.selectMove(f: Fighter, button: string): string
	local notation = Config.ButtonNotation[button]
	assert(notation ~= nil, "unknown button " .. tostring(button))
	local current = f.move
	if current and chainWindowOpen(f, moveDef(f, current)) then
		for _, key in f.character.moveOrder do
			local def = f.character.moves[key]
			if def.chainFrom == current and lastToken(def.input) == notation then return key end
		end
	end
	local index = inputIndex(f.character)
	for _, dir in directionContexts(f) do
		local key = index[if dir == "n" then notation else dir .. "+" .. notation]
		if key then return key end
	end
	error("no move for " .. f.characterId .. " " .. tostring(button) .. " (" .. notation .. ")")
end

-- Queues a move by key: a string follow-up chains when the source move is inside its input window, anything else is
-- buffered and starts as soon as the fighter can act (within Config.AttackBuffer frames).
function Sim.queueAttack(f: Fighter, name: string)
	assert(f.character.moves[name] ~= nil or Config.Moves[name] ~= nil, "unknown move " .. name .. " for " .. f.characterId)
	if f.move ~= nil then
		local source = moveDef(f, f.move)
		local queuedDef = (f.character.moves[name] or Config.Moves[name]) :: any
		if queuedDef.chainFrom == f.move and chainWindowOpen(f, source) then
			f.chainMove = name
			return
		end
	end
	f.input.attack=name; f.input.attackAge=0
end

-- Button press from a player or the CPU. Handles throw breaks, 1+3 / 2+4 chords (upgrading a move started by the
-- first button of the chord in place), strings and buffering. Returns the move key it queued (nil if none).
function Sim.press(m: Match, index: number, button: string): string?
	local f = m.fighters[index]
	if Config.ButtonNotation[button] == nil then return nil end
	if m.phase ~= "Fight" or f.health <= 0 then return nil end
	local info = f.throwInfo
	if info then
		if info.role == "Defender" and not info.breakTried then
			info.breakTried = true
			info.breakPress = button
		end
		return nil
	end
	local last = f.lastPress
	local chord = if last and m.frame - last.frame <= Config.ChordFrames then Config.Chords[last.button .. "+" .. button] else nil
	if chord and last then
		f.lastPress = nil
		if last.move ~= nil and f.input.attack == last.move then f.input.attack = nil end
		if last.move ~= nil and f.chainMove == last.move then f.chainMove = nil end
		local upgrade = last.move ~= nil and f.move == last.move and f.moveFrame <= Config.ChordFrames + 1 and f.state == "Startup"
		if upgrade then
			-- The first button already started its move: replace it, keeping the elapsed frames.
			local elapsed = f.moveFrame
			local prev = f.move
			f.move = nil
			local key = Sim.selectMove(f, chord)
			f.move = prev
			Sim.startMoveNow(f, key)
			f.moveFrame = elapsed
			return key
		end
		local key = Sim.selectMove(f, chord)
		Sim.queueAttack(f, key)
		return key
	end
	local key = Sim.selectMove(f, button)
	Sim.queueAttack(f, key)
	f.lastPress = { button = button, frame = m.frame, move = key }
	return key
end

-- Held directions. x: -1 back / 1 forward; z: 1 sidestep in (into the screen) / -1 sidestep out (toward camera).
-- A second forward/back tap within Config.DashTapWindow requests a dash/backdash; a z press (edge) requests ONE
-- sidestep. Holding z does nothing more (no orbiting).
function Sim.setMovement(m: Match, index: number, x: number, z: number)
	local f=m.fighters[index]
	local input = f.input
	if x~=0 and x~=input.moveX then
		if f.lastDirection==x and m.frame-f.lastTap<=Config.DashTapWindow and m.phase=="Fight" and f.health>0 then
			f.dashRequest=x; f.dashRequestFrame=m.frame; f.lastTap=-100
		else f.lastTap=m.frame; f.lastDirection=x end
	end
	if z~=0 and z~=input.moveZ and m.phase=="Fight" and f.health>0 then
		f.stepRequest=z; f.stepRequestFrame=m.frame
	end
	input.moveX=x; input.moveZ=z
end

function Sim.validCommand(kind: unknown, a: unknown, b: unknown): boolean
	if typeof(kind)~="string" then return false end
	if kind=="Move" then
		return typeof(a)=="number" and typeof(b)=="number" and (a==-1 or a==0 or a==1) and (b==-1 or b==0 or b==1)
	elseif kind=="Block" or kind=="Crouch" then return typeof(a)=="boolean" and b==nil
	elseif kind=="Attack" then
		return typeof(a)=="string" and Config.ButtonNotation[a]~=nil and (b==nil or (typeof(b)=="number" and b>0 and b<math.huge and b%1==0))
	elseif kind=="SelectCharacters" then
		return typeof(a)=="string" and typeof(b)=="string" and Roster.has(a) and Roster.has(b)
	elseif kind=="SelectStage" then
		return typeof(a)=="string" and isStage(a) and b==nil
	elseif kind=="SetMode" then
		return (a=="Match" or a=="Training") and b==nil
	elseif kind=="Dummy" then
		return (a==nil or a=="Stand" or a=="Guard" or a=="Fight") and b==nil
	elseif kind=="Reset" or kind=="Spar" or kind=="Mode" then return a==nil and b==nil
	elseif kind=="Difficulty" then return (a=="Easy" or a=="Normal" or a=="Hard") and b==nil end
	return false
end

-- Geometry ----------------------------------------------------------------------------------------------------------

local function face(f: Fighter, o: Fighter)
	local d=flat(o.pos-f.pos); if d.Magnitude>0.0001 then f.facing=d.Unit end
end
local function turnToward(f: Fighter, o: Fighter, degrees: number)
	if degrees <= 0 then return end
	local d = flat(o.pos - f.pos)
	if d.Magnitude < 0.0001 then return end
	local want = d.Unit
	local cur = f.facing
	local angle = math.acos(math.clamp(cur:Dot(want), -1, 1))
	local limit = math.rad(degrees)
	if angle <= limit then f.facing = want return end
	local cross = cur.X * want.Z - cur.Z * want.X
	local turn = if cross >= 0 then limit else -limit
	local c, s = math.cos(turn), math.sin(turn)
	f.facing = Vector3.new(cur.X * c - cur.Z * s, 0, cur.X * s + cur.Z * c).Unit
end
local function clamp(f: Fighter)
	local p=flat(f.pos); if p.Magnitude>Config.ArenaRadius then p=p.Unit*Config.ArenaRadius end
	f.pos=Vector3.new(p.X, f.pos.Y, p.Z)
end
-- Moves `f` (only) back out of the opponent so walking/dashing/lunging never pushes the other fighter.
local function keepApart(f: Fighter, o: Fighter)
	local d = flat(f.pos - o.pos)
	local n = d.Magnitude
	if n >= Config.Separation then return end
	local dir = if n > 0.0001 then d / n else -f.facing
	f.pos = Vector3.new(o.pos.X, f.pos.Y, o.pos.Z) + dir * Config.Separation
end
function Sim.separate(a: Fighter, b: Fighter)
	for _=1,3 do
		local d=flat(b.pos-a.pos); local n=d.Magnitude
		if n>=Config.Separation-0.000001 then return end
		local direction=if n>0.0001 then d/n else a.facing
		a.pos-=direction*(Config.Separation-n)/2; b.pos+=direction*(Config.Separation-n)/2
		clamp(a); clamp(b)
	end
end

-- State machine -----------------------------------------------------------------------------------------------------

-- Guard of a fighter that can act: "Stand" (blocks highs and mids), "Crouch" (blocks lows, ducks highs),
-- "All" (training dummy) or nil (walking forward / dummy that does not guard).
local function guardFor(f: Fighter): string?
	if f.dummy == "Guard" then return "All" end
	local input = f.input
	if input.crouch then return "Crouch" end
	if input.moveX > 0 then return nil end
	if input.moveX < 0 or input.block then return "Stand" end
	if f.dummy == "Stand" then return nil end
	return "Stand"
end
local function blockstunGuard(f: Fighter): string
	if f.dummy == "Guard" then return "All" end
	return if f.input.crouch then "Crouch" else "Stand"
end
Sim.guardFor = guardFor

local function clearMovement(f: Fighter)
	f.dash = 0; f.dashFrame = 0; f.dashTotal = 0; f.dashRequest = 0
	f.stepFrame = 0; f.stepDir = 0; f.stepRequest = 0
end

local function toIdle(f: Fighter)
	f.state = "Idle"; f.dash = 0; f.dashFrame = 0; f.dashTotal = 0; f.stepFrame = 0; f.stepDir = 0
end

local function startMove(f: Fighter, key: string)
	local def = moveDef(f, key)
	local prev = f.move
	f.stringIndex = if def.chainFrom ~= nil and prev == def.chainFrom then f.stringIndex + 1 else 1
	f.move=key; f.moveName=def.name; f.moveFrame=1; f.hasHit=false; f.state="Startup"; f.crouched=def.crouching
	f.chainMove=nil; f.armorUsed=false; f.guard=nil; f.evaded=false; f.crouchFrames=0
	f.dash=0; f.dashFrame=0; f.dashTotal=0; f.stepFrame=0; f.stepDir=0
end
Sim.startMoveNow = startMove

local function startDash(f: Fighter, direction: number)
	local s = f.character.stats
	f.state = if direction < 0 then "Backdash" else "Dash"
	f.dashDirection = direction
	f.dashFrame = 0
	f.dashTotal = if direction < 0 then s.backdashFrames else s.dashFrames
	f.dashDistance = if direction < 0 then s.backdashDistance else s.dashDistance
	f.dash = f.dashTotal
	f.dashRequest = 0
	f.guard = nil
	f.crouched = false
	f.crouchFrames = 0
end

local function dashTick(f: Fighter, o: Fighter)
	f.dashFrame += 1
	local back = f.state == "Backdash"
	local moveFrames = if back then math.min(Config.BackdashMoveFrames, f.dashTotal) else f.dashTotal
	face(f, o)
	if f.dashFrame <= moveFrames then
		local stepLen = f.dashDistance * (easeOut(f.dashFrame / moveFrames) - easeOut((f.dashFrame - 1) / moveFrames))
		f.pos += f.facing * (if back then -stepLen else stepLen)
		if not back then keepApart(f, o) end
		f.walkPhase = (f.walkPhase + 12 / Config.FPS) % (math.pi * 2)
	end
	f.dash = math.max(0, f.dashTotal - f.dashFrame)
end

local function startSidestep(f: Fighter, dir: number)
	f.state = "Sidestep"; f.stepDir = dir; f.stepFrame = 0; f.stepRequest = 0
	f.guard = nil; f.crouched = false; f.crouchFrames = 0
end

-- One frame of the discrete sidestep: an eased arc around the opponent at constant distance.
local function sidestepTick(f: Fighter, o: Fighter)
	f.stepFrame += 1
	if f.stepFrame <= Config.SidestepFrames then
		local rel = flat(f.pos - o.pos)
		local r = math.max(rel.Magnitude, 1)
		local radial = rel / r
		local tangent = Sim.lateral(-radial) * f.stepDir
		local dp = easeInOut(f.stepFrame / Config.SidestepFrames) - easeInOut((f.stepFrame - 1) / Config.SidestepFrames)
		local theta = f.character.stats.sidestepArc * dp / r
		local newRel = radial * (r * math.cos(theta)) + tangent * (r * math.sin(theta))
		f.pos = Vector3.new(o.pos.X + newRel.X, f.pos.Y, o.pos.Z + newRel.Z)
		f.walkPhase = (f.walkPhase + 9 / Config.FPS) % (math.pi * 2)
	end
	face(f, o)
end

local function becomeFree(f: Fighter, o: Fighter)
	f.state="Idle"; f.chain=0; f.stagger=0; f.knockdown=nil; f.airFrames=0; f.airHits=0; f.extensions=0; f.airLocked=false
	f.getupKind=nil; f.rollDir=0
	face(f, o)
	f.crouched = f.input.crouch
	f.guard = guardFor(f)
end

local function koFall(f: Fighter)
	if f.pos.Y > 0 or f.velocityY > 0 then
		f.velocityY -= Config.Gravity / Config.FPS
		f.pos += Vector3.new(0, f.velocityY / Config.FPS, 0)
		if f.pos.Y <= 0 then f.pos = flat(f.pos); f.velocityY = 0 end
	end
end

local function whiffEvent(events: { Event }, index: number, f: Fighter, moveName: string, v: Roster.MoveDef, frame: number)
	table.insert(events, { kind="Whiff", attacker=index, target=3-index, move=moveName, damage=0, advantage=0, frame=frame, point=f.pos, combo=0, air=false, tier=v.tier, archetype=v.anim.archetype, height=v.height, limb=v.limb, evaded=if f.evaded then true else nil })
end

local function advance(m: Match, f: Fighter, o: Fighter, events: { Event }, index: number)
	local frame = m.frame
	local input=f.input
	if input.attack then input.attackAge+=1 end
	if f.stepRequest ~= 0 and frame - f.stepRequestFrame > Config.StepBuffer then f.stepRequest = 0 end
	if f.dashRequest ~= 0 and frame - f.dashRequestFrame > 4 then f.dashRequest = 0 end
	f.dashCooldown=math.max(0,f.dashCooldown-1)
	if f.health<=0 then
		f.health=0; f.state="KO"; f.move=nil; f.moveFrame=0; input.attack=nil; f.throwInfo=nil; f.guard=nil; f.chainMove=nil
		clearMovement(f)
		if f.knockdown == nil then f.knockdown = "FaceUp" end
		koFall(f)
		return
	end
	if f.throwInfo then f.state="Throw"; f.guard=nil; return end
	if f.state=="KO" then return end
	if f.state=="Airborne" then
		f.guard=nil
		f.airFrames+=1; f.velocityY-=Config.Gravity / Config.FPS
		f.pos+=Vector3.new(0,f.velocityY/Config.FPS,0)
		if f.pos.Y<=0 then
			f.pos=flat(f.pos); f.velocityY=0; f.state="Landing"; f.stun=Config.LandingFrames; f.chain=0; f.knockdown=f.knockdown or "FaceUp"; f.getupKind=nil; f.airLocked=false
		elseif f.airFrames>=Config.MaxAirFrames and not f.airLocked then
			-- Air time is up: no more juggle hits, the body drops to the floor (never snapped down).
			f.airLocked=true; f.knockdown=f.knockdown or "FaceUp"; f.velocityY=math.min(f.velocityY, -6)
		end
		return
	end
	if f.state=="Landing" then
		-- On the floor. Hold back to roll back, tap W/S to roll sideways, otherwise stand up in place.
		f.guard=nil
		f.stun-=1
		local elapsed = Config.LandingFrames - f.stun
		if f.getupKind == nil and elapsed >= Config.GetupChoiceFrame then
			if input.moveX < 0 then f.getupKind = "BackRoll"
			elseif f.stepRequest ~= 0 then f.getupKind = "SideRoll"; f.rollDir = f.stepRequest; f.stepRequest = 0 end
		end
		if f.stun <= 0 then
			f.getupKind = f.getupKind or "Stand"
			f.state = "Getup"
			f.stun = Config.GetupFrames + (if f.getupKind ~= "Stand" then Config.RollFrames else 0)
		end
		return
	end
	if f.state=="Getup" then
		f.guard=nil
		local rolling = f.getupKind == "BackRoll" or f.getupKind == "SideRoll"
		local totalGetup = Config.GetupFrames + (if rolling then Config.RollFrames else 0)
		local elapsed = totalGetup - f.stun + 1
		if rolling and elapsed <= Config.RollFrames then
			local stepLen = Config.RollDistance * (easeOut(elapsed / Config.RollFrames) - easeOut((elapsed - 1) / Config.RollFrames))
			if f.getupKind == "BackRoll" then
				f.pos -= f.facing * stepLen
			else
				f.pos += Sim.lateral(f.facing) * f.rollDir * stepLen
				face(f, o)
			end
		end
		f.stun-=1
		if f.stun<=0 then becomeFree(f, o) end
		return
	end
	if f.stun>0 then
		f.stun-=1; f.stagger = if f.state == "Stagger" then f.stun else 0
		if f.state == "Blockstun" then f.crouched = input.crouch; f.guard = blockstunGuard(f) else f.guard = nil end
		if f.stun==0 then becomeFree(f, o) end
		return
	end
	if f.state == "Dash" or f.state == "Backdash" then
		local back = f.state == "Backdash"
		if f.dashRequest ~= 0 then
			if back and f.dashRequest < 0 and f.dashFrame >= Config.BackdashChainFrame then startDash(f, -1)
			elseif (not back) and f.dashRequest > 0 and f.dashFrame >= Config.DashChainFrame then startDash(f, 1) end
		end
		local attackFrame = if back then Config.BackdashAttackFrame else Config.DashAttackFrame
		if input.attack and f.dashFrame >= attackFrame then
			local queued = input.attack :: string
			input.attack = nil
			if input.attackAge <= Config.AttackBuffer then toIdle(f); face(f, o); startMove(f, queued); return end
		end
		dashTick(f, o)
		f.guard = nil
		if f.dashFrame >= f.dashTotal then toIdle(f); f.guard = guardFor(f) end
		return
	end
	if f.state == "Sidestep" then
		if input.attack and f.stepFrame >= Config.SidestepAttackFrame then
			local queued = input.attack :: string
			input.attack = nil
			if input.attackAge <= Config.AttackBuffer then toIdle(f); face(f, o); startMove(f, queued); return end
		end
		if f.stepFrame >= Config.SidestepGuardFrame and input.moveX < 0 then
			toIdle(f)
		else
			sidestepTick(f, o)
			f.guard = nil
			if f.stepFrame >= Config.SidestepFrames + Config.SidestepRecovery then toIdle(f); f.guard = guardFor(f) end
			return
		end
	end
	local moveName=f.move
	if moveName then
		local v=moveDef(f, moveName); f.moveFrame+=1
		local activeEnd = v.startup + v.active
		if f.chainMove and f.moveFrame > activeEnd then
			if f.state=="Active" and not f.hasHit then whiffEvent(events, index, f, moveName, v, frame) end
			startMove(f, f.chainMove :: string)
			return
		end
		if f.moveFrame <= v.startup or (v.homing and f.moveFrame <= activeEnd) then turnToward(f, o, v.track) end
		if v.advance > 0 and f.moveFrame <= v.startup + 1 then
			-- Root motion: `advance` studs spread over the frames up to and including the first active frame.
			f.pos += f.facing * (v.advance / math.max(1, v.startup))
			keepApart(f, o)
		end
		if f.moveFrame<=v.startup then f.state="Startup"
		elseif f.moveFrame<=activeEnd then f.state="Active"
		else
			if f.state=="Active" and not f.hasHit then whiffEvent(events, index, f, moveName, v, frame) end
			f.state="Recovery"
		end
		f.guard=nil
		if f.moveFrame>=total(v) then f.move=nil; f.moveName=nil; f.moveFrame=0; f.state="Idle"; f.crouched=false; f.chainMove=nil; f.stringIndex=0 end
		return
	end
	face(f,o)
	if f.dashRequest ~= 0 and not input.crouch and not input.block then
		startDash(f, f.dashRequest)
		if input.attack then input.attackAge = 0 end
		dashTick(f, o)
		return
	end
	if f.stepRequest ~= 0 then
		-- A button pressed together with the step tap becomes an ss move at Config.SidestepAttackFrame.
		startSidestep(f, f.stepRequest)
		if input.attack then input.attackAge = 0 end
		sidestepTick(f, o)
		return
	end
	local queued=input.attack
	if queued then
		input.attack=nil
		if input.attackAge<=Config.AttackBuffer then startMove(f, queued); return end
	end
	local stats=f.character.stats
	f.crouched=input.crouch
	local speed=if f.crouched then Config.CrouchSpeed elseif input.moveX>0 then stats.walkSpeed elseif input.moveX<0 then stats.backSpeed else 0
	if speed > 0 and input.moveX ~= 0 then
		f.pos+=f.facing*input.moveX*speed/Config.FPS
		if input.moveX > 0 then keepApart(f, o) end
		f.walkPhase=(f.walkPhase+9/Config.FPS)%(math.pi*2)
	end
	if f.crouched then
		f.state = "Crouch"; f.crouchFrames += 1
	else
		f.crouchFrames = 0
		f.state = if input.moveX > 0 then "Walk" elseif input.moveX < 0 then "Backwalk" else "Idle"
	end
	f.guard = guardFor(f)
end

-- Hits and throws ---------------------------------------------------------------------------------------------------

local function hitstopFor(kind: string, def: Roster.MoveDef, counter: boolean): number
	local frames = if kind == "KO" then Config.Hitstop.KO elseif kind == "Block" then Config.Hitstop.Block else Config.Hitstop[def.tier] or Config.Hitstop.Medium
	if counter and kind ~= "Block" then frames += Config.CounterHitstopBonus end
	return frames
end

local function inWindow(window: { number }?, frame: number): boolean
	return window ~= nil and frame >= window[1] and frame <= window[2]
end

local function limbSide(def: Roster.MoveDef): number
	if string.find(def.limb, "Lead", 1, true) or def.anim.side == "Lead" then return -1 end
	if string.find(def.limb, "Rear", 1, true) or def.anim.side == "Rear" then return 1 end
	return 0
end

local function rememberHit(target: Fighter, kind: string, def: Roster.MoveDef, moveName: string, frame: number, counter: boolean?)
	target.lastHit = {
		kind = (kind :: any),
		height = (def.height :: any),
		tier = (def.tier :: any),
		counter = counter == true,
		frame = frame,
		move = moveName,
		limb = def.limb,
		side = limbSide(def),
	}
end

local function crushState(f: Fighter): string?
	if not f.move then return nil end
	local def = moveDef(f, f.move)
	if inWindow(def.props.highCrush, f.moveFrame) then return "High" end
	if inWindow(def.props.lowCrush, f.moveFrame) then return "Low" end
	return nil
end
function Sim.currentCrush(f: Fighter): string? return crushState(f) end
function Sim.armorActive(f: Fighter): boolean
	return f.move ~= nil and inWindow(moveDef(f, f.move :: string).props.armor, f.moveFrame) and not f.armorUsed
end

local function canGuard(t: Fighter, def: Roster.MoveDef): boolean
	if def.height == "Throw" then return false end
	local g = t.guard
	if g == nil or t.move ~= nil then return false end
	if not (FREE[t.state] or t.state == "Blockstun") then return false end
	if g == "All" then return true end
	if def.smid then return g == "Stand" or g == "Crouch" end
	if g == "Crouch" then return def.height == "Low" end
	return def.height == "High" or def.height == "Mid"
end
Sim.canGuard = canGuard

local function throwEvent(kind: string, attackerIndex: number, targetIndex: number, move: string, def: Roster.MoveDef, frame: number, point: Vector3, damage: number?): Event
	return { kind=kind, attacker=attackerIndex, target=targetIndex, move=move, damage=damage or 0, advantage=0, frame=frame, point=point, combo=0, air=false, tier=def.tier, archetype=def.anim.archetype, knockdown=if kind=="ThrowHit" then true else nil, height=def.height, limb=def.limb }
end

local function startThrow(m: Match, i: number, moveName: string, def: Roster.MoveDef, events: { Event })
	local a=m.fighters[i]; local t=m.fighters[3-i]
	a.hasHit=true
	local function info(role: string): ThrowInfo
		return { role=role, move=moveName, archetype=def.anim.archetype, frame=0, duration=def.duration or 46, impactFrame=def.impactFrame or 30, breakWindow=def.breakWindow or 20, breakButton=def.breakButton or "LeadPunch", impactDone=false, breakTried=false, breakPress=nil }
	end
	a.throwInfo=info("Attacker")
	t.throwInfo=info("Defender")
	a.state="Throw"; t.state="Throw"; t.move=nil; t.moveFrame=0; t.input.attack=nil; t.chainMove=nil; t.guard=nil; a.guard=nil
	clearMovement(t)
	table.insert(events, throwEvent("ThrowStart", i, 3-i, moveName, def, m.frame, (a.pos+t.pos)/2+Vector3.new(0,2.5,0), 0))
	m.hitstop=math.max(m.hitstop, Config.Hitstop.Throw)
end

local function endThrow(attacker: Fighter, defender: Fighter, broken: boolean)
	attacker.throwInfo=nil; defender.throwInfo=nil; attacker.move=nil; attacker.moveFrame=0; attacker.hasHit=false; attacker.chainMove=nil
	attacker.state="Idle"; attacker.stun=0; attacker.stagger=0
	if broken then
		defender.state="Idle"; defender.stun=0; defender.stagger=0
	else
		defender.state="Landing"; defender.stun=Config.LandingFrames; defender.stagger=0; defender.getupKind=nil
	end
	defender.move=nil; defender.moveFrame=0; defender.input.attack=nil; attacker.input.attack=nil
	local dir = attacker.facing
	attacker.pos -= dir * (if broken then 0.6 else 0.45); defender.pos += dir * (if broken then 0.6 else 0.45); clamp(attacker); clamp(defender)
end

local function throwBreakMatches(press: string?, breakButton: string): boolean
	if press == nil then return false end
	if press == breakButton then return true end
	if press == "Throw" then return breakButton == "LeadPunch" end
	if press == "Throw2" then return breakButton == "RearPunch" end
	return false
end
Sim.throwBreakMatches = throwBreakMatches

local function processThrows(m: Match, events: { Event })
	for i, f in m.fighters do
		local info = f.throwInfo
		if info and info.role == "Attacker" then
			local targetIndex = 3 - i
			local target = m.fighters[targetIndex]
			local def = moveDef(f, info.move)
			info.frame += 1
			local tInfo = target.throwInfo
			if tInfo then tInfo.frame = info.frame end
			if info.broken then
				-- Broken grab: both fighters stay locked while they shove apart, then return to neutral together.
				if info.frame >= (info.breakFrame or info.frame) + Config.ThrowBreakFrames then endThrow(f, target, true) end
			elseif tInfo and tInfo.breakTried and info.frame <= info.breakWindow and throwBreakMatches(tInfo.breakPress, info.breakButton) then
				table.insert(events, throwEvent("ThrowBreak", i, targetIndex, info.move, def, m.frame, (f.pos + target.pos) / 2 + Vector3.new(0, 2.6, 0), 0))
				info.broken = true; info.breakFrame = info.frame
				tInfo.broken = true; tInfo.breakFrame = info.frame
				m.hitstop = math.max(m.hitstop, Config.Hitstop.Throw)
			elseif not info.impactDone and info.frame >= info.impactFrame then
				info.impactDone = true
				local damage = def.damage
				target.health = math.clamp(target.health - damage, 0, target.maxHealth)
				target.lastHit = { kind="Throw", height="Throw", tier=(def.tier :: any), counter=false, frame=m.frame, move=info.move, limb=def.limb, side=0 }
				target.knockdown = "FaceUp"
				target.lastDefendedMove = info.move
				table.insert(events, throwEvent("ThrowHit", i, targetIndex, info.move, def, m.frame, (f.pos + target.pos) / 2 + Vector3.new(0, 1.2, 0), damage))
				m.hitstop = math.max(m.hitstop, Config.Hitstop.Throw)
				if target.health == 0 then target.state="KO"; m.koFrame=m.frame end
			elseif info.frame >= info.duration then
				endThrow(f, target, false)
			end
		end
	end
end

local function applyKnockdown(t: Fighter, faceDown: boolean?)
	t.state="Landing"; t.stun=Config.LandingFrames; t.velocityY=0; t.pos=flat(t.pos); t.knockdown=if faceDown then "FaceDown" else "FaceUp"; t.getupKind=nil
end

local function hits(m: Match, events: { Event })
	local active: { { index: number, name: string } }={}
	for i,f in m.fighters do if f.health>0 and f.state=="Active" and not f.hasHit and f.move then table.insert(active,{index=i,name=f.move}) end end
	for _,entry in active do
		local i=entry.index; local a=m.fighters[i]; local t=m.fighters[3-i]; local def=moveDef(a, entry.name)
		local air=t.state=="Airborne"
		local eligible=t.state~="KO" and t.state~="Landing" and t.state~="Getup" and t.state~="Throw" and not (t.state=="Airborne" and t.airLocked)
		if def.height=="Throw" then
			if eligible and not air and not t.crouched and t.state~="Hitstun" and t.state~="Blockstun" and Sim.reach(a,t,entry.name) then startThrow(m, i, entry.name, def, events) end
			continue
		end
		if def.height=="High" and t.crouched and not air then eligible=false end
		if air and (def.height=="Low" or t.pos.Y>Config.AirHitCeiling) then eligible=false end
		if not eligible then continue end
		local inReach, along, side = Sim.reach(a,t,entry.name)
		if not inReach then
			if t.state == "Sidestep" and along > 0 and along <= def.range + 0.6 and side > def.width then a.evaded = true end
			continue
		end
		local tDef = if t.move then moveDef(t, t.move) else nil
		local parry = if tDef then tDef.props.parry else nil
		if parry and inWindow(parry.window, t.moveFrame) and (def.height == "High" or def.height == "Mid") then
			local ok=false; for _, h in parry.heights do if h == def.height then ok=true end end
			if ok then
				a.hasHit=true; a.move=nil; a.moveFrame=0; a.chainMove=nil; a.state="Stagger"; a.stun=parry.stagger; a.stagger=parry.stagger
				rememberHit(t, "Parry", def, entry.name, m.frame, false)
				table.insert(events,{kind="Parry",attacker=3-i,target=i,move=t.move or "",damage=0,advantage=parry.stagger,frame=m.frame,point=(a.pos+t.pos)/2+Vector3.new(0,3,0),combo=0,air=false,tier=def.tier,height=def.height,limb=def.limb})
				m.hitstop=math.max(m.hitstop, Config.Hitstop.Parry)
				continue
			end
		end
		local crush = crushState(t)
		if (crush == "High" and def.height == "High") or (crush == "Low" and def.height == "Low") then
			a.hasHit=true
			rememberHit(t, "Crush", def, entry.name, m.frame, false)
			table.insert(events,{kind="Crush",attacker=3-i,target=i,move=t.move or "",damage=0,advantage=0,frame=m.frame,point=(a.pos+t.pos)/2+Vector3.new(0,2.5,0),combo=0,air=false,tier=def.tier,height=def.height,limb=def.limb})
			m.hitstop=math.max(m.hitstop, Config.Hitstop.Crush)
			continue
		end
		a.hasHit=true
		local blocked=canGuard(t, def)
		local armored = (not blocked) and Sim.armorActive(t)
		local counter=not blocked and not armored and t.state=="Startup"
		local airScale = Config.AirDamageScale * ((Config.AirDamageDecay or 0.84) ^ math.max(0, t.airHits))
		local damage=if blocked then math.floor(def.damage*Config.BlockMultiplier+0.5) elseif air then math.max(1,math.floor(def.damage*airScale+0.5)) else def.damage
		if counter then damage=math.max(1,math.floor(damage*Config.CounterDamageMultiplier+0.5)) end
		local remaining=total(def)-a.moveFrame
		local continuing=(t.state=="Hitstun" or air) and t.chain>0
		t.health=math.clamp(t.health-damage,0,t.maxHealth); t.lastDefendedMove=entry.name
		local onHit: number | string = if counter and def.onCounter ~= nil then def.onCounter :: any else def.onHit
		local kind="Hit"; local advantage=0; local launched=false; local knockdown=false
		if blocked then
			t.move=nil; t.moveFrame=0; t.input.attack=nil; t.chainMove=nil; clearMovement(t); t.state="Blockstun"; t.stun=blockStun(def); t.chain=0; kind="Block"; advantage=t.stun-remaining
			t.guard = blockstunGuard(t)
			rememberHit(t, "Block", def, entry.name, m.frame, false)
		elseif armored then
			t.armorUsed=true; kind="Armor"; advantage=0; rememberHit(t, "Armor", def, entry.name, m.frame, false)
		else
			t.move=nil; t.moveFrame=0; t.input.attack=nil; t.chainMove=nil; clearMovement(t); t.chain=if continuing then t.chain+1 else 1; a.combo=t.chain; t.crouched=false; t.guard=nil
			if air then
				t.airHits += 1
				if onHit == "KND" or t.airHits >= (Config.MaxAirHits or 5) then
					knockdown=true
					if t.pos.Y > 0.05 then
						-- The juggle ends: fall the rest of the way into the knockdown instead of snapping to the floor.
						t.state="Airborne"; t.stun=0; t.airLocked=true; t.knockdown=if limbSide(def) > 0 then "FaceDown" else "FaceUp"
						t.velocityY=math.min(t.velocityY, 2)
					else
						applyKnockdown(t, limbSide(def) > 0)
					end
				else
					if t.extensions<Config.MaxJuggleExtensions then
						t.extensions+=1
						local liftScale = math.max(0.35, 1 - t.airHits * 0.14)
						t.velocityY=math.max(t.velocityY,Config.JuggleVelocity * liftScale)
					end
					t.state="Airborne"; t.stun=0
				end
			elseif onHit == "LAUNCH" then
				launched=true; t.state="Airborne"; t.stun=0; t.velocityY=Config.LaunchVelocity; t.airFrames=0; t.airHits=0; t.extensions=0; t.knockdown=nil; t.airLocked=false; t.pos+=Vector3.new(0,0.05,0); a.aiLastLauncherFrame=m.frame
			elseif onHit == "KND" then
				knockdown=true; applyKnockdown(t, limbSide(def) > 0)
			else
				local stun = if counter and typeof(def.onCounter) == "number" then (def.onCounter :: number) + def.active + def.recovery - 1
					else hitStun(def) + (if counter then Config.CounterStunBonus else 0)
				t.state="Hitstun"; t.stun=math.max(1, stun); advantage=t.stun-remaining
			end
			rememberHit(t, if counter then "Counter" else "Hit", def, entry.name, m.frame, counter)
		end
		if t.health==0 then
			t.state="KO"; t.stun=0; t.knockdown=if t.knockdown then t.knockdown else "FaceUp"; m.koFrame=m.frame; kind="KO"; advantage=0
			-- A KO in the air keeps its momentum and falls to the floor (koFall); on the ground the body stays down.
			if not (air or launched) then t.pos=flat(t.pos); t.velocityY=0 end
		end
		local airHit=not blocked and (air or launched)
		if not armored then t.pos+=a.facing*(if blocked then def.push*0.35 elseif air then def.push*0.45 else def.push*0.75); clamp(t) end
		m.hitstop=math.max(m.hitstop,hitstopFor(kind,def,counter))
		table.insert(events,{kind=kind,attacker=i,target=3-i,move=entry.name,damage=damage,advantage=if airHit or knockdown then 0 else advantage,frame=m.frame,point=(a.pos+t.pos)/2+Vector3.new(0,if def.height=="Low" then 1.2 else 3.5,0),combo=if blocked or armored then 0 else t.chain,air=airHit,counter=if counter then true else nil,launch=if launched then true else nil,knockdown=if knockdown then true else nil,tier=def.tier,archetype=def.anim.archetype,height=def.height,limb=def.limb})
	end
end

-- Rounds ------------------------------------------------------------------------------------------------------------

local function finishRound(m: Match)
	local a,b=m.fighters[1],m.fighters[2]
	m.winner=if a.health>b.health then 1 elseif b.health>a.health then 2 else 0
	m.reason=if m.koFrame then "KO" else "TIME"
	if m.winner~=0 then m.scores[m.winner]+=1 end
	for _,f in m.fighters do f.input=Sim.newInput() end
	if m.scores[1]>=Config.WinsNeeded or m.scores[2]>=Config.WinsNeeded then m.phase="MatchOver"
	else m.phase="RoundOver"; m.phaseFrames=Config.RoundBreakFrames end
end

-- Bodies keep falling to the floor after the round ends (a KO in the air never leaves anyone floating).
local function settleBodies(m: Match)
	for _, f in m.fighters do koFall(f) end
end

function Sim.step(m: Match): { Event }
	if m.hitstop>0 then
		m.frame+=1; m.hitstop-=1
		if m.phase=="Fight" then return {} end
	else m.frame+=1 end
	if m.mode=="Match" and m.phase~="Fight" then
		settleBodies(m)
		if m.phase=="Ready" then
			m.phaseFrames-=1; if m.phaseFrames<=0 then m.phase="Fight"; for _,f in m.fighters do f.input.attack=nil end end
		elseif m.phase=="RoundOver" then
			m.phaseFrames-=1
			if m.phaseFrames<=0 then local p1,p2=m.fighters[1].characterId,m.fighters[2].characterId; m.fighters=freshFighters(p1,p2); applyDummy(m); m.koFrame=nil; m.timer=Config.RoundFrames; m.round+=1; m.phase="Ready"; m.phaseFrames=Config.ReadyFrames; m.winner=0; m.reason=""; m.aiHistory={}; m.aiHistoryFrame=-1 end
		end
		return {}
	end
	local events: { Event }={}; local a,b=m.fighters[1],m.fighters[2]
	processThrows(m, events)
	advance(m,a,b,events,1); advance(m,b,a,events,2); clamp(a); clamp(b); Sim.separate(a,b); hits(m,events)
	for i,f in m.fighters do if m.fighters[3-i].chain==0 then f.combo=0 end end
	if m.mode=="Match" then
		if m.koFrame then finishRound(m)
		elseif m.hitstop==0 then m.timer=math.max(0,m.timer-1); if m.timer==0 then finishRound(m) end end
	end
	return events
end

-- CPU ---------------------------------------------------------------------------------------------------------------

-- Drives fighter `index` with the CPU (CombatAI) for this frame. Call before Sim.step.
function Sim.trainerInput(m: Match, index: number)
	local AI = require(script.Parent.CombatAI) :: any
	AI.step(m, index)
end

return Sim
