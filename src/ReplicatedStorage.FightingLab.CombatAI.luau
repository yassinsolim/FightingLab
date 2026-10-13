--!strict
-- FightingLab CPU opponent (OV6). Plays like a person instead of a reflex machine:
--   * sees the opponent through a reaction delay (Easy ~36-42 f, Normal ~22-26 f, Hard ~14-16 f),
--   * keeps a movement intent for a while (walk in, hold/guard, back off) instead of re-deciding every frame,
--   * guards by standing still, crouch-blocks lows only when it reacts to a slow low or reads a low habit,
--   * punishes blocked unsafe moves and whiffs with the right tool sometimes (per difficulty),
--   * pokes, uses strings (Hard hit-confirms), throws, a rare sidestep and an occasional backdash,
--   * converts launchers into short juggles (combo length per difficulty) and plays a simple wake-up game.
-- Deterministic: all randomness comes from a per-fighter Park-Miller generator seeded by round and slot.
local Config = require(script.Parent.CombatConfig)
local Roster = require(script.Parent.Roster)
local Sim = require(script.Parent.CombatSim)

local AI = {}

export type Params = {
	reactionDelay: number, reactionJitter: number, decisionMin: number, decisionMax: number,
	guardDiscipline: number, lowReact: number, lowRead: number, duckHighs: number, duckThrows: number,
	blockPunish: number, whiffPunish: number, punishLauncher: boolean, juggleHits: number,
	throwBreak: number, throwRead: number, stringContinue: number, hitConfirm: boolean, noise: number,
	attackCadence: number, attackCadenceJitter: number, aggression: number, stepGap: number, stepChance: number,
	backdashChance: number, dashIn: number, meaty: number, meatyError: number, getupRoll: number, turnTake: number, pressure: number, readSkill: number, holdGuard: number,
	-- Multiplier on the chance to counter-attack after blocking (per-fighter matchup adjustments, see MATCHUP).
	turnScale: number,
	-- Easy only: chance per decision to mash the fastest poke when crowded inside grab range under pressure.
	crowdJab: number,
	-- Patience: neutral frames without an attack or a deliberate movement before the CPU acts whatever its reads say
	-- (no read may keep it passive); in range it attacks after `patience * 1.6` frames without attacking.
	patience: number,
	-- Legacy names (tests/tools): blockChance = guardDiscipline, lowBlockChance = lowReact, punishChance = blockPunish,
	-- throwBreakChance = throwBreak, stringChance = stringContinue, sidestepChance = stepChance.
	blockChance: number, lowBlockChance: number, punishChance: number, throwBreakChance: number, stringChance: number,
	sidestepChance: number, approachDistance: number, throwChance: number, lowChance: number, launcherChance: number,
}

local function params(t: { [string]: any }): Params
	t.blockChance = t.guardDiscipline
	t.lowBlockChance = t.lowReact
	t.punishChance = t.blockPunish
	t.throwBreakChance = t.throwBreak
	t.stringChance = t.stringContinue
	t.sidestepChance = t.stepChance
	t.approachDistance = 4.0
	t.throwChance = t.throwChance or 0.08
	t.lowChance = t.lowChance or 0.1
	t.launcherChance = t.launcherChance or 0.02
	t.turnScale = t.turnScale or 1
	t.crowdJab = t.crowdJab or 0
	t.patience = t.patience or 120
	return (t :: any) :: Params
end

local PARAMS: { [string]: Params } = {
	Easy = params({ reactionDelay = 36, reactionJitter = 6, decisionMin = 24, decisionMax = 46,
		guardDiscipline = 0.25, lowReact = 0.2, lowRead = 0.05, duckHighs = 0, duckThrows = 0,
		blockPunish = 0.1, whiffPunish = 0.08, punishLauncher = false, juggleHits = 1,
		throwBreak = 0.5, throwRead = 0.58, stringContinue = 0.45, hitConfirm = false, noise = 0.45,
		attackCadence = 90, attackCadenceJitter = 50, aggression = 0.4, stepGap = 900, stepChance = 0.03,
		backdashChance = 0.03, dashIn = 0.1, meaty = 0.05, meatyError = 8, getupRoll = 0.05, turnTake = 0.3, pressure = 0.3, readSkill = 0.15, holdGuard = 0.25,
		throwChance = 0.05, lowChance = 0.08, launcherChance = 0.01, crowdJab = 1, patience = 150 }),
	Normal = params({ reactionDelay = 22, reactionJitter = 4, decisionMin = 16, decisionMax = 34,
		guardDiscipline = 0.7, lowReact = 0.55, lowRead = 0.12, duckHighs = 0.1, duckThrows = 0.05,
		blockPunish = 0.5, whiffPunish = 0.4, punishLauncher = true, juggleHits = 2,
		throwBreak = 0.55, throwRead = 0.6, stringContinue = 0.6, hitConfirm = false, noise = 0.15,
		attackCadence = 42, attackCadenceJitter = 34, aggression = 0.6, stepGap = 420, stepChance = 0.06,
		backdashChance = 0.06, dashIn = 0.25, meaty = 0.3, meatyError = 4, getupRoll = 0.2, turnTake = 0.4, pressure = 0.45, readSkill = 0.55, holdGuard = 0.9,
		throwChance = 0.08, lowChance = 0.1, launcherChance = 0.02, patience = 110 }),
	Hard = params({ reactionDelay = 14, reactionJitter = 2, decisionMin = 12, decisionMax = 26,
		guardDiscipline = 0.9, lowReact = 0.85, lowRead = 0.22, duckHighs = 0.3, duckThrows = 0.2,
		blockPunish = 0.85, whiffPunish = 0.7, punishLauncher = true, juggleHits = 3,
		throwBreak = 0.75, throwRead = 0.8, stringContinue = 0.55, hitConfirm = true, noise = 0.06,
		attackCadence = 28, attackCadenceJitter = 26, aggression = 0.7, stepGap = 270, stepChance = 0.08,
		backdashChance = 0.08, dashIn = 0.35, meaty = 0.5, meatyError = 2, getupRoll = 0.35, turnTake = 0.55, pressure = 0.55, readSkill = 0.85, holdGuard = 1,
		throwChance = 0.1, lowChance = 0.12, launcherChance = 0.03, patience = 90 }),
}

function AI.params(level: string?): Params
	return PARAMS[level or "Normal"] or PARAMS.Normal
end
AI.Levels = PARAMS

-- Per-fighter adjustments of a level (Easy only). A button-mashing beginner should win about half the time with every
-- fighter and against every fighter, but the kits differ for a masher (Goran's 120 HP, armored charges and d+4 sweep,
-- Lumi's 90 HP), so Easy counter-attacks after blocking (turnScale) more or less often depending on who the opponent
-- plays (`vs`) and on the fighter it plays itself (`as`); `cap` keeps the result below Normal's turnTake. `crowdVs`
-- scales the close-range jab mashing (`crowdJab`) per opponent (armored charges walk through it) and `punishVs`
-- scales block/whiff punishes per opponent (kept below Normal's). Tuned with harness/beginner.luau.
local MATCHUP: { [string]: { vs: { [string]: number }, as: { [string]: number }, crowdVs: { [string]: number }, punishVs: { [string]: number }, cap: number } } = {
	Easy = {
		vs = { Kael = 1.25, Sierra = 0.95, Goran = 1.4, Lumi = 1.0, Rhys = 1.25, Nia = 1.2 },
		as = { Kael = 0.85, Sierra = 1.3, Goran = 0.6, Lumi = 1.2, Rhys = 1.15, Nia = 1.4 },
		crowdVs = { Goran = 0 },
		punishVs = { Goran = 4 },
		cap = 0.38,
	},
}
AI.Matchups = MATCHUP

-- The parameters a CPU playing `meId` uses against `foeId` at `level`.
function AI.paramsFor(level: string?, meId: string, foeId: string): Params
	local base = AI.params(level)
	local adj = MATCHUP[level or "Normal"]
	if adj == nil then return base end
	local scale = math.min((adj.vs[foeId] or 1) * (adj.as[meId] or 1), adj.cap / base.turnTake)
	local crowd = adj.crowdVs[foeId] or 1
	local punish = adj.punishVs[foeId] or 1
	if scale == 1 and crowd == 1 and punish == 1 then return base end
	local t = table.clone(base :: any)
	t.turnScale *= scale
	t.crowdJab = math.min(1, t.crowdJab * crowd)
	local normal = AI.params("Normal")
	t.blockPunish = math.min(normal.blockPunish * 0.9, t.blockPunish * punish)
	t.whiffPunish = math.min(normal.whiffPunish * 0.9, t.whiffPunish * punish)
	t.punishChance = t.blockPunish
	return t :: Params
end

-- Random numbers --------------------------------------------------------------------------------------------------

type Brain = { [string]: any }

local function rand(s: Brain): number
	s.rng = (s.rng * 16807) % 2147483647
	return (s.rng - 1) / 2147483646
end
local function chance(s: Brain, p: number): boolean return rand(s) < p end
local function rint(s: Brain, a: number, b: number): number return a + math.floor(rand(s) * (b - a + 1)) end

local function hashString(text: string): number
	local h = 7
	for i = 1, #text do h = (h * 31 + string.byte(text, i)) % 1000003 end
	return h
end

-- Scrambles a seed (xorshift rounds) so neighbouring seeds do not give correlated Park-Miller sequences.
local function scramble(x: number): number
	x = bit32.band(math.floor(x), 0x7FFFFFFF)
	for _ = 1, 4 do
		x = bit32.bxor(x, bit32.lshift(x, 13))
		x = bit32.bxor(x, bit32.rshift(x, 17))
		x = bit32.bxor(x, bit32.lshift(x, 5))
	end
	return x % 2147483646 + 1
end

-- Perception ------------------------------------------------------------------------------------------------------

local HISTORY = 120

-- Frame on which a fighter's current move started. `frame - moveFrame + 1` drifts whenever the move's frame counter
-- stops while the match clock runs (hitstop, and the whole throw, which has its own clock), so one attack would be
-- remembered several times (every blocked jab twice, a throw once per frame). The start is kept while the same move
-- keeps running; called once per frame from `AI.observe`.
local function moveStartOf(m: Sim.Match, index: number, f: Sim.Fighter): number
	if not f.move then return -1 end
	local raw = m :: any
	local starts = raw.aiStarts
	if starts == nil then starts = {}; raw.aiStarts = starts end
	local prev = starts[index]
	if prev and prev.move == f.move and f.moveFrame >= prev.moveFrame and m.frame - prev.frame <= 40 then
		prev.moveFrame = f.moveFrame
		prev.frame = m.frame
		return prev.start
	end
	local start = m.frame - f.moveFrame + 1
	starts[index] = { move = f.move, moveFrame = f.moveFrame, frame = m.frame, start = start }
	return start
end

local function snapshotOf(m: Sim.Match, index: number, f: Sim.Fighter, frame: number): { [string]: any }
	return {
		state = f.state, move = f.move, moveFrame = f.moveFrame, moveStart = moveStartOf(m, index, f),
		pos = f.pos, health = f.health, crouched = f.crouched, hasHit = f.hasHit, lastDefendedMove = f.lastDefendedMove,
		stepFrame = f.stepFrame, guard = f.guard, velocityY = f.velocityY, stun = f.stun, frame = frame,
	}
end

function AI.observe(m: Sim.Match)
	if m.aiHistoryFrame == m.frame then return end
	m.aiHistoryFrame = m.frame
	m.aiHistory[m.frame] = { snapshotOf(m, 1, m.fighters[1], m.frame), snapshotOf(m, 2, m.fighters[2], m.frame) } :: any
	m.aiHistory[m.frame - HISTORY] = nil
end

-- What fighter `index` looked like `delay` frames ago (hitstop gaps fall back to the latest older sample).
function AI.perceive(m: Sim.Match, index: number, delay: number): { [string]: any }
	for back = delay, delay + 24 do
		local row = m.aiHistory[m.frame - back]
		if row then return (row :: any)[index] end
	end
	local f = m.fighters[index]
	return { state = "Idle", move = nil, moveFrame = 0, moveStart = -1, pos = f.pos, health = f.health, crouched = false, hasHit = false, stepFrame = 0, guard = "Stand", velocityY = 0, stun = 0, frame = m.frame }
end

-- Move knowledge -------------------------------------------------------------------------------------------------

-- Move definition by key, including the legacy alias keys (Config.Moves) that tools and old tests still queue.
local function defOf(f: Sim.Fighter, key: string?): Roster.MoveDef?
	if key == nil then return nil end
	return f.character.moves[key] or (Config.Moves[key] :: any)
end

local function impactOf(def: Roster.MoveDef): number return def.startup + 1 end
local function totalOf(def: Roster.MoveDef): number return def.startup + def.active + def.recovery end
local function threatOf(def: Roster.MoveDef): number
	if def.height == "Throw" then return math.max(def.range, Config.Separation + 0.05) end
	return def.range + def.advance
end
local function prefixOf(def: Roster.MoveDef): string?
	return string.match(def.input, "^(%a+)%+")
end
AI.impactOf = impactOf
AI.threatOf = threatOf

local followerCache: { [any]: { [string]: { string } } } = {}
local function followersOf(character: Roster.CharacterDef, key: string): { string }
	local map = followerCache[character]
	if not map then
		map = {}
		for _, k in character.moveOrder do
			local from = character.moves[k].chainFrom
			if from then
				map[from] = map[from] or {}
				table.insert(map[from], k)
			end
		end
		followerCache[character] = map
	end
	return map[key] or {}
end

local function flatDistance(a: Sim.Fighter, b: Sim.Fighter): number
	local d = b.pos - a.pos
	return Vector3.new(d.X, 0, d.Z).Magnitude
end

-- Brain ------------------------------------------------------------------------------------------------------------

local function brain(m: Sim.Match, me: Sim.Fighter, index: number, p: Params): Brain
	local s: Brain? = me.ai
	if s == nil or s.level ~= m.difficulty then
		local foe = m.fighters[3 - index]
		local seed = scramble((1 + index * 7919 + m.round * 104729 + hashString(me.characterId) * 13 + hashString(foe.characterId) * 7 + #me.name + ((m :: any).aiSeed or 0) * 7727) % 2147483646 + 1)
		local fresh: Brain = {
			level = m.difficulty, rng = seed, delay = p.reactionDelay,
			params = AI.paramsFor(m.difficulty, me.characterId, foe.characterId),
			intent = "hold", intentStart = -100, intentUntil = 0, x = 0, crouch = false,
			nextDecision = 0, nextAttack = m.frame + 20, lastStep = -100000, lastDash = -100000, lastBackdash = -100000,
			plan = nil, stringPlan = nil, reactedTo = -1, whiffFor = -1, punishFor = -1, okiFor = -1, breakFor = -1, getupFor = -1,
			punishKey = nil, juggleFor = -1, lastSeenState = "Idle", lastAttackFrame = -100,
			habits = { lows = 0, throws = 0, highs = 0, mids = 0, attacks = 0, steps = 0, blocks = 0, crouchTime = 0 },
			lastHabitMove = -1, recent = {}, started = {}, followed = {}, wake = { ups = 0, attacks = 0, lows = 0 },
		}
		for _ = 1, 3 do rand(fresh) end
		me.ai = fresh
		return fresh
	end
	return s :: Brain
end

local function rerollDelay(s: Brain, p: Params)
	s.delay = p.reactionDelay + rint(s, 0, p.reactionJitter)
end

-- States in which the (perceived) opponent is free to act.
local FOE_FREE: { [string]: boolean } = { Idle = true, Walk = true, Backwalk = true, Crouch = true, Dash = true, Backdash = true, Sidestep = true }

local function learn(m: Sim.Match, s: Brain, seen: { [string]: any }, foe: Sim.Fighter)
	local h = s.habits
	-- The opponent's free-time clock: frames it could act (no move, not stunned, down or thrown). Reads age on this
	-- clock, so a pattern fades while the opponent does something else, not while it lies on the floor after our punish.
	if seen.move == nil and FOE_FREE[seen.state] then s.foeClock = (s.foeClock or 0) + 1 end
	if seen.move and seen.moveStart ~= s.lastHabitMove and seen.moveStart > 0 then
		s.lastHabitMove = seen.moveStart
		local def = defOf(foe, seen.move)
		if def and def.chainFrom == nil then
			for k, v in h do h[k] = v * 0.9 end
			h.attacks += 1
			if def.height == "Low" then h.lows += 1 elseif def.height == "Throw" then h.throws += 1 elseif def.height == "High" then h.highs += 1 else h.mids += 1 end
			-- Recent attack log (what a player remembers: "they keep doing that").
			local recent = s.recent
			local prefix = prefixOf(def)
			table.insert(recent, { key = seen.move, height = def.height, smid = def.smid, start = seen.moveStart, clock = s.foeClock or 0, onBlock = def.onBlock, startup = def.startup,
				ducks = def.crouching == true or def.props.highCrush ~= nil,
				-- frames from their first input to the hit (sidestep and dash attacks include the step / dash)
				lead = impactOf(def) + (if prefix == "ss" then Config.SidestepAttackFrame elseif prefix == "dash" then Config.DashAttackFrame else 0) })
			if #recent > 6 then table.remove(recent, 1) end
			s.started[seen.move] = (s.started[seen.move] or 0) + 1
			s.foeMoved = 0
		elseif def and def.chainFrom then
			s.followed[def.chainFrom] = (s.followed[def.chainFrom] or 0) + 1
		end
	end
	-- An attack that connects (blocked, landed or a grab) is felt as pressure twice as much as a whiff: mark it once.
	if seen.move and seen.hasHit and seen.moveStart == s.lastHabitMove then
		local last = s.recent[#s.recent]
		if last and last.start == seen.moveStart and not last.connected then last.connected = true end
	end
	if seen.state == "Sidestep" and s.lastSeenState ~= "Sidestep" then h.steps += 1 end
	-- Frames the opponent spent moving away or around (walking back, backdash, sidestep) since its last attack: a player
	-- who resets the distance has moved on from the pattern a streak read was built on (walking in to repeat it has not).
	if seen.state == "Backwalk" or seen.state == "Backdash" or seen.state == "Sidestep" then
		s.foeMoved = (s.foeMoved or 0) + 1
	end
	-- Wake-up habits: do they attack (and with what) right as they stand up? Counted per wake-up, fading slowly.
	local wake = s.wake
	if s.lastSeenState == "Getup" and seen.state ~= "Getup" then
		s.foeWokeAt = seen.frame
		wake.ups = wake.ups * 0.85 + 1
		wake.attacks *= 0.85
		wake.lows *= 0.85
	end
	if seen.move and seen.moveStart ~= s.lastWakeMove and s.foeWokeAt and seen.moveStart >= s.foeWokeAt and seen.moveStart - s.foeWokeAt <= 8 then
		s.lastWakeMove = seen.moveStart
		local wdef = defOf(foe, seen.move)
		wake.attacks += 1
		if wdef and (wdef.height == "Low" or wdef.crouching) then wake.lows += 1 end
	end
	if seen.state == "Blockstun" and s.lastSeenState ~= "Blockstun" then
		h.blocks += 1
		if seen.crouched then h.crouchBlocks = (h.crouchBlocks or 0) + 1 else h.standBlocks = (h.standBlocks or 0) + 1 end
	end
	h.crouchTime = h.crouchTime * 0.995 + (if seen.crouched then 1 else 0)
	h.retreat = (h.retreat or 0) * 0.99 + (if seen.state == "Backdash" then 1 else 0)
	-- Old impressions fade even when the opponent never attacks (half-life about 10 s): a habit the opponent stopped
	-- showing (lows, grabs, highs, sidesteps, blocks) cannot keep shaping the reads.
	h.standBlocks = (h.standBlocks or 0) * 0.9988
	h.crouchBlocks = (h.crouchBlocks or 0) * 0.9988
	h.lows *= 0.9988; h.throws *= 0.9988; h.highs *= 0.9988; h.mids *= 0.9988
	h.attacks *= 0.9988; h.steps *= 0.9988; h.blocks *= 0.9988
	h.passive = (h.passive or 0) * 0.9988 + (if seen.move == nil then 1 / 60 else 0)
	s.lastSeenState = seen.state
end

-- A string starter the opponent keeps using on its own (rarely continued) is answered like a single move.
local function treatAsStandalone(s: Brain, character: Roster.CharacterDef, key: string): boolean
	if #followersOf(character, key) == 0 then return true end
	local started = s.started[key] or 0
	local followed = s.followed[key] or 0
	return started >= 2 and followed <= started * 0.3
end

-- Read of the opponent's recent attacks: rate (attacks in the last 2.5 s, one that connected counts twice), the move
-- they repeat, and which guard stance handles their habits best ("crouch" ducks highs and throws and blocks lows and
-- special mids, "stand" for mids).
-- `ducks`: most of their attacks go under highs (crouching moves, rising launchers), so a high poke gets crushed.
-- `impact`: how soon their recent attacks hit after they start them (frames, step/dash included).
-- Reads age on the opponent's free-time clock (`foeClock`, see `learn`): only attacks from its last READ_WINDOW free
-- frames shape a read, and a low/throw streak also needs its last attack to be fresh (STREAK_FRESH free frames) with
-- the opponent not having backed off or stepped since. A pattern the opponent stopped is forgotten within a few
-- seconds of it doing something else. `lastAge`: real frames since their latest attack started (huge when none).
local READ_WINDOW = 240
local STREAK_FRESH = 120
local STREAK_MOVED = 45
local function readAge(m: Sim.Match, s: Brain, r: { [string]: any }): number
	if r.clock ~= nil then return (s.foeClock or 0) - r.clock end
	return m.frame - r.start
end
local function readOpponent(m: Sim.Match, s: Brain): { rate: number, spamKey: string?, stance: string, highs: number, mids: number, lows: number, lowStreak: boolean, throwStreak: boolean, ducks: boolean, impact: number, lastAge: number }
	local recent = {}
	for _, r in s.recent do
		if readAge(m, s, r) <= READ_WINDOW then table.insert(recent, r) end
	end
	local rate, highs, mids, lows, throws, ducking, impacts = 0, 0, 0, 0, 0, 0, 0
	for _, r in recent do
		if m.frame - r.start <= 150 then rate += if r.connected then 2 else 1 end
		if r.height == "High" then highs += 1
		elseif r.height == "Low" then lows += 1
		elseif r.height == "Throw" then throws += 1
		elseif not r.smid then mids += 1 end
		if r.ducks then ducking += 1 end
		impacts += r.lead or ((r.startup or 15) + 1)
	end
	local spamKey = nil
	local n = #recent
	local lastAge = if n > 0 then m.frame - recent[n].start else math.huge
	local fresh = n > 0 and readAge(m, s, recent[n]) <= STREAK_FRESH and (s.foeMoved or 0) < STREAK_MOVED
	if n >= 3 and recent[n].key == recent[n - 1].key and recent[n].key == recent[n - 2].key then spamKey = recent[n].key end
	local lowStreak = fresh and n >= 3 and recent[n].height == "Low" and recent[n - 1].height == "Low" and recent[n - 2].height == "Low"
	local throwStreak = fresh and n >= 2 and recent[n].height == "Throw" and recent[n - 1].height == "Throw"
	-- Crouching blocks lows and ducks highs and throws but eats every mid: only worth it when mids are rare.
	local crouchScore = lows + (highs + throws) * 0.6
	local stance = if n >= 3 and crouchScore >= 2 and crouchScore >= mids * 2.5 then "crouch" else "stand"
	local ducks = n >= 3 and ducking * 2 >= n
	local impact = if n > 0 then impacts / n else 16
	return { rate = rate, spamKey = spamKey, stance = stance, highs = highs, mids = mids, lows = lows, lowStreak = lowStreak, throwStreak = throwStreak, ducks = ducks, impact = impact, lastAge = lastAge }
end

-- Inputs -----------------------------------------------------------------------------------------------------------

local function setIntent(m: Sim.Match, s: Brain, name: string, frames: number, x: number, crouch: boolean?)
	-- Never flip straight from walking in to walking out (or back): a short neutral pause comes first.
	if x ~= 0 and s.x ~= 0 and x ~= s.x and m.frame - s.intentStart < 14 then
		name, x, frames, crouch = "hold", 0, math.min(frames, 10), false
	end
	s.intent = name
	s.intentStart = m.frame
	s.intentUntil = m.frame + math.max(1, frames)
	s.x = x
	s.crouch = crouch == true
end

local function applyIntent(m: Sim.Match, me: Sim.Fighter, index: number, s: Brain)
	local x = s.x
	-- Re-pressing a direction inside the double-tap window would dash by accident: wait it out.
	if x ~= 0 and me.input.moveX == 0 and me.lastDirection == x and m.frame - me.lastTap <= Config.DashTapWindow then x = 0 end
	if me.input.moveX ~= x or me.input.moveZ ~= 0 then Sim.setMovement(m, index, x, 0) end
	me.input.crouch = s.crouch
	me.input.block = false
end

local function releaseAll(m: Sim.Match, me: Sim.Fighter, index: number)
	if me.input.moveX ~= 0 or me.input.moveZ ~= 0 then Sim.setMovement(m, index, 0, 0) end
	me.input.crouch = false
	me.input.block = false
end

local function doDash(m: Sim.Match, me: Sim.Fighter, index: number, s: Brain, dir: number)
	Sim.setMovement(m, index, 0, 0)
	Sim.setMovement(m, index, dir, 0)
	Sim.setMovement(m, index, 0, 0)
	Sim.setMovement(m, index, dir, 0)
	me.input.crouch = false
	if dir > 0 then s.lastDash = m.frame else s.lastBackdash = m.frame end
	s.idle = 0
	setIntent(m, s, if dir > 0 then "dash" else "backdash", if dir > 0 then 16 else 20, 0, false)
end

local function doSidestep(m: Sim.Match, me: Sim.Fighter, index: number, s: Brain, dir: number)
	Sim.setMovement(m, index, 0, dir)
	Sim.setMovement(m, index, 0, 0)
	me.input.crouch = false
	s.lastStep = m.frame
	s.idle = 0
	setIntent(m, s, "sidestep", Config.SidestepFrames + Config.SidestepRecovery, 0, false)
end

local function pressMove(m: Sim.Match, me: Sim.Fighter, index: number, s: Brain, key: string)
	local def = me.character.moves[key]
	local prefix = prefixOf(def)
	me.input.crouch = prefix == "d" or prefix == "df" or prefix == "db"
	s.crouch = me.input.crouch
	Sim.queueAttack(me, key)
	s.lastAttackFrame = m.frame
	s.idle = 0
	s.rangeIdle = 0
	if AI.trace then s.why = if AI.trace == "full" then debug.traceback() else debug.info(2, "l") end -- tools: which decision pressed the move
end

-- Choosing attacks -------------------------------------------------------------------------------------------------

-- Throws connect from body contact up to about this centre distance (Roster throw range).
local THROW_REACH = 3.2
-- Longest crouch (frames) the CPU holds on its own reads once the opponent stops attacking (a little longer while a
-- low/throw streak is fresh), and the intents that are such reads (reactions to an attack that is coming, and the
-- wake-up guard, end with that attack).
local CROUCH_CAP = 72
local CROUCH_CAP_STREAK = 84
local READ_CROUCH: { [string]: boolean } = { ["pressure-guard"] = true, ["crouch-read"] = true, ["respect"] = true, ["wake-crouch"] = true, ["approach-crouch"] = true }

local ROLE_BASE: { [string]: number } = { poke = 26, string = 20, mid = 16, low = 9, throw = 10, walkThrow = 5, power = 6, launcher = 2, homing = 3, powerLow = 3, parry = 0, dashAttack = 3, stepAttack = 2, duck = 0 }
local BIAS: { [string]: { [string]: number } } = {
	Kael = { string = 10, poke = 6 },
	Sierra = { mid = 8, homing = 2 },
	Goran = { throw = 10, walkThrow = 8, power = 6, string = -8 },
	Lumi = { homing = 3, power = 3, dashAttack = 3, stepAttack = 2 },
	Rhys = { mid = 8, parry = 2 },
	Nia = { string = 12 },
}

local function candidates(me: Sim.Fighter, role: string, dist: number, foeCrouched: boolean): { string }
	local list = {}
	for _, key in me.character.moveOrder do
		local def = me.character.moves[key]
		-- Stance follow-ups, stance entries and the Ultimate are chosen by their own decisions, never as neutral picks.
		if def.chainFrom == nil and def.stance == nil and def.toStance == nil and def.cinematic == nil then
			local prefix = prefixOf(def)
			local fits = false
			if role == "dashAttack" then fits = prefix == "dash"
			elseif role == "stepAttack" then fits = prefix == "ss"
			elseif prefix == "dash" or prefix == "ss" then fits = false
			elseif role == "throw" or role == "walkThrow" then fits = def.height == "Throw"
			elseif def.height == "Throw" then fits = false
			elseif role == "parry" then fits = def.props.parry ~= nil
			elseif def.damage <= 0 then fits = false
			elseif role == "poke" then fits = def.startup <= 11 and def.height ~= "Low"
			elseif role == "string" then fits = #followersOf(me.character, key) > 0
			elseif role == "mid" then fits = def.height == "Mid" and def.onHit ~= "LAUNCH" and def.onBlock >= -9
			elseif role == "low" then fits = def.height == "Low" and def.onHit ~= "KND"
			elseif role == "powerLow" then fits = def.height == "Low" and def.onHit == "KND"
			elseif role == "power" then fits = def.height ~= "Low" and def.onHit ~= "LAUNCH" and (def.onHit == "KND" or def.damage >= 15 or def.props.armor ~= nil)
			elseif role == "launcher" then fits = def.onHit == "LAUNCH"
			elseif role == "homing" then fits = def.homing or def.track >= 3
			elseif role == "duck" then fits = def.crouching or def.props.highCrush ~= nil
			end
			if fits and foeCrouched and (def.height == "High" or def.height == "Throw") then fits = false end
			if fits and role ~= "walkThrow" then
				local reach = threatOf(def)
				if role == "dashAttack" then reach += me.character.stats.dashDistance * 0.7 end
				if dist > reach - (if def.height == "Throw" then -0.02 else 0.15) then fits = false end
			end
			if fits then table.insert(list, key) end
		end
	end
	return list
end

local function pickRole(s: Brain, me: Sim.Fighter, dist: number, stepOk: boolean, read: { [string]: any }?, turtle: boolean?): string
	local w = table.clone(ROLE_BASE)
	local bias = BIAS[me.characterId]
	if bias then for k, v in bias do w[k] = math.max(0, (w[k] or 0) + v) end end
	local h = s.habits
	if h.crouchTime > 30 then
		-- A croucher blocks lows and ducks highs and throws: go for mids.
		w.mid += 14; w.poke = math.max(0, w.poke - 10); w.launcher += 3
		w.low = math.max(0, w.low - 6); w.powerLow = 0; w.throw = 0; w.walkThrow = 0
	end
	if h.blocks > 1.5 then w.low += 8; w.throw += 6; w.powerLow += 2; w.walkThrow += 4 end
	if turtle then
		-- They stand and block everything: open them up with lows and throws instead of more highs and mids.
		w.low += 22; w.throw += 12; w.walkThrow += 10; w.powerLow += 5
		w.poke = math.max(0, w.poke - 14); w.string = math.max(0, w.string - 8); w.mid = math.max(0, w.mid - 6)
	end
	if h.steps > 1.2 then w.homing += 10 end
	if h.attacks > 3.5 then w.poke += 4; if me.characterId == "Rhys" then w.parry += 8 end end
	if read and read.rate >= 2 and read.highs >= 2 then w.duck = (w.duck or 0) + 30; w.poke = math.max(0, w.poke - 10) end
	if dist > THROW_REACH - 0.05 then w.throw = 0 end
	if dist <= THROW_REACH - 0.05 or dist > 4.8 then w.walkThrow = 0 end
	if dist < 4.2 or dist > 6.4 then w.dashAttack = 0 end
	if not stepOk then w.stepAttack = 0 end
	local totalWeight = 0
	for _, v in w do totalWeight += v end
	local r = rand(s) * totalWeight
	local order = { "poke", "string", "mid", "low", "throw", "walkThrow", "power", "launcher", "homing", "powerLow", "parry", "dashAttack", "stepAttack", "duck" }
	for _, role in order do
		r -= w[role] or 0
		if r <= 0 then return role end
	end
	return "poke"
end

local function planString(s: Brain, p: Params, me: Sim.Fighter, key: string, full: boolean?)
	local chain = {}
	local cur = key
	while true do
		local nexts = followersOf(me.character, cur)
		if #nexts == 0 then break end
		local pick = nexts[rint(s, 1, #nexts)]
		table.insert(chain, pick)
		cur = pick
	end
	if #chain == 0 then s.stringPlan = nil return end
	local depth = 0
	if p.hitConfirm or full then depth = #chain
	else for i = 1, #chain do if chance(s, p.stringContinue) then depth = i else break end end end
	s.stringPlan = { chain = chain, done = 0, depth = depth, pressAt = -1, confirm = p.hitConfirm and not full }
end

local function chooseAttack(m: Sim.Match, me: Sim.Fighter, foe: Sim.Fighter, index: number, s: Brain, p: Params, dist: number, seen: { [string]: any }): boolean
	local foeCrouched = (seen.crouched == true and seen.move == nil) or s.habits.crouchTime > 40
	local key: string? = nil
	local role = "poke"
	if chance(s, p.noise) then
		local all = {}
		for _, r in { "poke", "mid", "low", "power", "launcher", "homing", "string", "powerLow" } do
			for _, k in candidates(me, r, dist, false) do table.insert(all, k) end
		end
		if #all > 0 then key = all[rint(s, 1, #all)]; role = "noise" end
	end
	if not key then
		local stepOk = m.frame - s.lastStep > p.stepGap
		local read = readOpponent(m, s)
		-- They keep going under highs (crouching moves, rising launchers): a high poke would get crushed.
		local foeLow = foeCrouched or (read.ducks and chance(s, p.readSkill))
		-- Against a button-happy opponent slow moves get interrupted: a player who notices sticks to quick ones.
		local busy = read.rate >= 2 and chance(s, p.readSkill)
		local turtle = (s.habits.standBlocks or 0) >= 2.5 and read.rate <= 1 and chance(s, 0.35 + p.readSkill * 0.65)
		for _ = 1, 4 do
			role = pickRole(s, me, dist, stepOk, if chance(s, p.readSkill) then read else nil, turtle)
			local list = candidates(me, role, dist, foeLow)
			if busy and role ~= "walkThrow" then
				-- quicker than what they keep throwing out (never stricter than i12)
				local limit = math.min(16, math.max(12, read.impact - 2))
				local quick = {}
				for _, k in list do
					local d = me.character.moves[k]
					if impactOf(d) <= limit or d.props.armor ~= nil or d.props.highCrush ~= nil or d.props.lowCrush ~= nil then table.insert(quick, k) end
				end
				list = quick
			end
			if #list > 0 then key = list[rint(s, 1, #list)] break end
		end
	end
	if not key then return false end
	s.nextAttack = m.frame + p.attackCadence + rint(s, 0, p.attackCadenceJitter)
	if role == "walkThrow" then
		-- Walk in and grab (the throw is pressed once close enough; the plan is dropped if anything happens).
		s.plan = { kind = "walkThrow", key = key, untilFrame = m.frame + 36 }
		setIntent(m, s, "walk-throw", 36, 1, false)
		applyIntent(m, me, index, s)
	elseif role == "dashAttack" then
		doDash(m, me, index, s, 1)
		s.plan = { kind = "dashAttack", key = key, at = m.frame + Config.DashAttackFrame + rint(s, 0, 3) }
	elseif role == "stepAttack" then
		doSidestep(m, me, index, s, if chance(s, 0.5) then 1 else -1)
		s.plan = { kind = "stepAttack", key = key, at = m.frame + Config.SidestepAttackFrame + rint(s, 0, 4) }
	else
		pressMove(m, me, index, s, key)
		planString(s, p, me, key)
	end
	return true
end

-- Best punisher that lands within `frames` (the opponent's disadvantage) at distance `dist`.
local function bestPunisher(me: Sim.Fighter, frames: number, dist: number, p: Params, foeCrouched: boolean?): string?
	local best, bestScore = nil, -math.huge
	for _, key in me.character.moveOrder do
		local def = me.character.moves[key]
		local prefix = prefixOf(def)
		if def.chainFrom == nil and def.stance == nil and def.toStance == nil and def.cinematic == nil and def.damage > 0 and def.height ~= "Throw" and prefix ~= "dash" and prefix ~= "ss" and impactOf(def) <= frames and dist <= threatOf(def) - 0.1
			and not (foeCrouched and def.height == "High") then
			local score = def.damage
			if def.onHit == "LAUNCH" then score += if p.punishLauncher then 20 else -100 end
			if def.onHit == "KND" then score += 6 end
			if #followersOf(me.character, key) > 0 then score += 7 end
			if score > bestScore then best, bestScore = key, score end
		end
	end
	return best
end

-- Behaviours -------------------------------------------------------------------------------------------------------

local function defendThrow(m: Sim.Match, me: Sim.Fighter, index: number, s: Brain, p: Params)
	local info = me.throwInfo :: Sim.ThrowInfo
	local id = m.frame - info.frame
	if s.breakFor ~= id then
		s.breakFor = id
		s.breakAttempt = chance(s, p.throwBreak)
		-- Hard reacts to the grab animation; lower levels guess early.
		s.breakAt = if p.hitConfirm then rint(s, 9, 17) else rint(s, 3, 18)
		local correct = chance(s, p.throwRead)
		s.breakButton = if correct then info.breakButton elseif info.breakButton == "LeadPunch" then "RearPunch" else "LeadPunch"
	end
	if s.breakAttempt and info.frame >= s.breakAt and not info.breakTried then
		Sim.press(m, index, s.breakButton)
	end
end

local function chooseGetup(m: Sim.Match, me: Sim.Fighter, index: number, s: Brain, p: Params)
	local id = if me.lastHit then me.lastHit.frame else 0
	if s.getupFor ~= id then
		s.getupFor = id
		s.getupMode = "Stand"
		s.rollPressed = false
		if chance(s, p.getupRoll) then s.getupMode = if chance(s, 0.6) then "BackRoll" else "SideRoll" end
	end
	local elapsed = Config.LandingFrames - me.stun
	if s.getupMode == "BackRoll" then
		if me.input.moveX ~= -1 then Sim.setMovement(m, index, -1, 0) end
	elseif s.getupMode == "SideRoll" then
		if not s.rollPressed and elapsed >= Config.GetupChoiceFrame - 1 then
			s.rollPressed = true
			Sim.setMovement(m, index, 0, if chance(s, 0.5) then 1 else -1)
			Sim.setMovement(m, index, 0, 0)
		end
	else
		releaseAll(m, me, index)
	end
	me.input.crouch = false
end

-- Getting up: guess the wake-up guard like a player holding down-back when the opponent keeps sweeping.
local function wakeGuard(m: Sim.Match, me: Sim.Fighter, index: number, s: Brain, p: Params)
	local id = if me.lastHit then me.lastHit.frame else 0
	if s.wakeFor ~= id then
		s.wakeFor = id
		local h = s.habits
		local recentLows, recentAll = 0, 0
		for _, r in s.recent do
			-- crouching blocks their lows and ducks their grabs (only what they did lately counts)
			if readAge(m, s, r) <= READ_WINDOW then
				recentAll += 1
				if r.height == "Low" or r.height == "Throw" then recentLows += 1 end
			end
		end
		local share = if recentAll > 0 then recentLows / recentAll else (if h.attacks > 0.5 then (h.lows + h.throws) / h.attacks else 0)
		local prob = p.readSkill * math.min(1, share * 1.5)
		if me.lastHit and (me.lastHit.height == "Low" or me.lastHit.height == "Throw") then prob = math.min(1, prob + p.readSkill * 0.35) end
		s.wakeCrouch = chance(s, prob)
	end
	if me.input.moveX ~= 0 or me.input.moveZ ~= 0 then Sim.setMovement(m, index, 0, 0) end
	me.input.block = false
	me.input.crouch = s.wakeCrouch == true
	if s.wakeCrouch and me.stun <= 1 then
		setIntent(m, s, "wake-crouch", rint(s, 14, 26), 0, true)
		s.defensive = true
	end
end

local function blockstun(m: Sim.Match, me: Sim.Fighter, foe: Sim.Fighter, index: number, s: Brain, p: Params)
	local hit = me.lastHit
	-- Punishes are decided during blockstun (players recognise the move while blocking it) and buffered for the
	-- first free frame; the recognition time is a fraction of the reaction delay.
	local recognise = math.max(1, math.floor(p.reactionDelay * 0.25))
	if hit and hit.kind == "Block" and s.punishFor ~= hit.frame and m.frame - hit.frame >= recognise then
		s.punishFor = hit.frame
		s.punishKey = nil
		rerollDelay(s, p)
		local blockedDef = defOf(foe, hit.move)
		if blockedDef and treatAsStandalone(s, foe.character, hit.move) then
			local frames = -blockedDef.onBlock
			if frames >= 10 and chance(s, p.blockPunish) then
				s.punishKey = bestPunisher(me, frames, flatDistance(me, foe), p, foe.crouched or blockedDef.crouching)
			end
		end
	end
	if s.punishKey and me.stun <= 3 then
		local key = s.punishKey :: string
		s.punishKey = nil
		pressMove(m, me, index, s, key)
		planString(s, p, me, key, true)
		s.nextAttack = m.frame + 24
		-- The punish is buffered for the first free frame: nothing after blockstun may replace it.
		s.punishedFor = s.punishFor
	end
end

local function continueString(m: Sim.Match, me: Sim.Fighter, foe: Sim.Fighter, index: number, s: Brain, p: Params)
	local plan = s.stringPlan
	if not plan or plan.done >= plan.depth or me.chainMove ~= nil then return end
	local nextKey = plan.chain[plan.done + 1]
	local nextDef = me.character.moves[nextKey]
	if not nextDef or nextDef.chainFrom ~= me.move then return end
	local src = Sim.moveDef(me, me.move :: string)
	local windowEnd = src.startup + src.active + Sim.ChainLate
	if me.moveFrame > windowEnd then plan.depth = plan.done return end
	if plan.pressAt < 0 then plan.pressAt = math.max(2, src.startup + rint(s, -3, 4)) end
	if plan.confirm then
		local knowAt = src.startup + 1 + s.delay
		if me.moveFrame < math.min(knowAt, windowEnd) then return end
		local landed = me.hasHit and (foe.state == "Hitstun" or foe.state == "Airborne" or foe.state == "Landing" or foe.state == "KO")
		if not landed then
			-- Blocked or whiffed: stop, except a safe follow-up now and then.
			if not (me.hasHit and nextDef.onBlock > -10 and chance(s, 0.4)) then plan.depth = plan.done return end
		end
	elseif me.moveFrame < plan.pressAt then
		return
	end
	-- A high follow-up whiffs over an opponent who keeps ducking under highs (crouching moves): stop the string.
	if nextDef.height == "High" and readOpponent(m, s).ducks and chance(s, p.readSkill) then plan.depth = plan.done return end
	Sim.queueAttack(me, nextKey)
	if me.chainMove == nextKey then plan.done += 1; plan.pressAt = -1 end
end

local function predictY(f: Sim.Fighter, frames: number): number
	local y, v = f.pos.Y, f.velocityY
	for _ = 1, frames do
		v -= Config.Gravity / Config.FPS
		y += v / Config.FPS
	end
	return y
end

local function juggle(m: Sim.Match, me: Sim.Fighter, foe: Sim.Fighter, index: number, s: Brain, p: Params, dist: number)
	if foe.airHits >= p.juggleHits or foe.airLocked then
		setIntent(m, s, "wait", 4, 0, false)
		applyIntent(m, me, index, s)
		return
	end
	local best, bestScore = nil, -math.huge
	for _, key in me.character.moveOrder do
		local def = me.character.moves[key]
		local prefix = prefixOf(def)
		if def.chainFrom == nil and def.stance == nil and def.toStance == nil and def.cinematic == nil and def.height ~= "Low" and def.height ~= "Throw" and def.damage > 0 and prefix ~= "dash" and prefix ~= "ss" and impactOf(def) <= 18 then
			local y = predictY(foe, impactOf(def))
			if y > 0.35 and y < Config.AirHitCeiling - 0.2 and dist <= threatOf(def) - 0.1 then
				local finisher = foe.airHits + 1 >= p.juggleHits
				local score = def.damage - impactOf(def) * 0.3 + (if finisher and def.onHit == "KND" then 6 else 0)
				if score > bestScore then best, bestScore = key, score end
			end
		end
	end
	if best then
		-- People drop combos sometimes.
		if chance(s, 1 - p.noise * 0.6) then
			pressMove(m, me, index, s, best)
			s.stringPlan = nil
		else
			s.juggleFor = foe.airFrames
		end
		return
	end
	setIntent(m, s, "juggle-walk", 4, if dist > 3.0 then 1 else 0, false)
	applyIntent(m, me, index, s)
end

-- Frame on which the knocked-down opponent becomes actionable (it guards from that frame).
local function wakeFrame(m: Sim.Match, foe: Sim.Fighter): number
	local rolling = foe.getupKind == "BackRoll" or foe.getupKind == "SideRoll"
	if foe.state == "Landing" then return m.frame + foe.stun + Config.GetupFrames + (if rolling then Config.RollFrames else 0) end
	return m.frame + foe.stun
end

local function okizeme(m: Sim.Match, me: Sim.Fighter, foe: Sim.Fighter, index: number, s: Brain, p: Params, dist: number)
	local downId = if foe.lastHit then foe.lastHit.frame else 0
	if s.okiFor ~= downId then
		s.okiFor = downId
		s.plan = nil
		local wake = s.wake
		if wake.ups >= 1.5 and wake.attacks >= wake.ups * 0.5 and chance(s, p.readSkill) then
			-- They like to attack as they stand up: wait for it in guard (low guard if those are lows) and punish.
			s.plan = { kind = "wakeGuard", low = wake.lows >= wake.attacks * 0.5 }
		elseif chance(s, p.meaty) then
			local r = rand(s)
			s.plan = { kind = "meaty", role = if r < 0.45 then "mid" elseif r < 0.75 then "low" else "throw", err = rint(s, 0, p.meatyError) }
		end
	end
	local pref = me.character.stats.preferredRange
	local plan = s.plan
	if plan and plan.kind == "wakeGuard" then
		local wakeAt = wakeFrame(m, foe)
		local untilFrame = wakeAt + rint(s, 18, 28)
		-- Close the distance only while they are still on the floor; as they rise, hold the guard where we are
		-- (walking in standing would walk into the wake-up low we are waiting for).
		local walk = dist > pref + 0.6 and wakeAt - m.frame > 20
		setIntent(m, s, "wake-guard", math.max(4, untilFrame - m.frame), if walk then 1 else 0, plan.low and not walk)
		s.defensive = true
		applyIntent(m, me, index, s)
		return
	end
	if plan and plan.kind == "meaty" then
		local list = candidates(me, plan.role, dist, false)
		if #list == 0 and plan.role ~= "mid" then list = candidates(me, "mid", dist, false) end
		if #list > 0 then
			local key = plan.key or list[rint(s, 1, #list)]
			plan.key = key
			local def = me.character.moves[key]
			if m.frame + def.startup >= wakeFrame(m, foe) + plan.err then
				s.plan = nil
				pressMove(m, me, index, s, key)
				planString(s, p, me, key)
				s.nextAttack = m.frame + p.attackCadence
				return
			end
		end
	end
	setIntent(m, s, "oki", 4, if dist > pref - 0.4 then 1 else 0, false)
	applyIntent(m, me, index, s)
end

-- The attack cannot reach us (or we duck under the grab): get ready to punish its recovery, like a player who sees
-- the whiff coming instead of waiting to notice the recovery.
local function expectWhiff(m: Sim.Match, s: Brain, p: Params, def: Roster.MoveDef, seen: { [string]: any }, framesLeft: number)
	if def.recovery < 12 or not chance(s, p.whiffPunish) then return end
	local settle = if p.hitConfirm then rint(s, 1, 4) elseif p.reactionDelay <= 26 then rint(s, 4, 9) else rint(s, 10, 18)
	local at = m.frame + math.max(0, framesLeft) + (if framesLeft >= 0 then def.active else 0) + settle
	s.plan = { kind = "whiffPunish", key = seen.move, at = at }
end

-- Reaction to an opponent attack seen through the perception delay. Returns true when it set a defensive intent.
local function react(m: Sim.Match, me: Sim.Fighter, foe: Sim.Fighter, index: number, s: Brain, p: Params, seen: { [string]: any }, dist: number): boolean
	if not seen.move or seen.state ~= "Startup" or seen.moveStart == s.reactedTo then return false end
	s.reactedTo = seen.moveStart
	local def = defOf(foe, seen.move)
	if not def then return false end
	rerollDelay(s, p)
	local nowFrame = seen.moveFrame + (m.frame - seen.frame)
	local framesLeft = impactOf(def) - nowFrame
	local endsIn = totalOf(def) - nowFrame
	if dist > threatOf(def) + 0.3 and not def.homing and foe.move == seen.move then
		if s.x <= 0 then expectWhiff(m, s, p, def, seen, framesLeft) end
		if dist > threatOf(def) + 0.8 then return false end
	end
	if def.height == "Throw" then
		if (framesLeft >= 2 and chance(s, p.duckThrows)) or s.crouch then
			setIntent(m, s, "duck-throw", endsIn + 4, 0, true)
			s.defensive = true
			if foe.move == seen.move then expectWhiff(m, s, p, def, seen, framesLeft) end
			return true
		end
		return false
	end
	if s.crouch and def.height == "High" then
		-- Reading highs from a crouch: the high whiffs over us; answer with a crouching move when we read it well.
		if chance(s, p.readSkill) then
			local list = candidates(me, "duck", dist, false)
			if #list > 0 then
				local key = list[rint(s, 1, #list)]
				pressMove(m, me, index, s, key)
				me.input.crouch = true
				s.crouch = true
				s.stringPlan = nil
				s.nextAttack = m.frame + p.attackCadence
				return true
			end
		end
		setIntent(m, s, "duck", framesLeft + def.active + 4, 0, true)
		s.defensive = true
		return true
	end
	if s.crouch and def.height == "Low" then
		setIntent(m, s, "crouch-guard", framesLeft + def.active + 6, 0, true)
		s.defensive = true
		return true
	end
	if s.crouch and def.height == "Mid" and not def.smid and framesLeft >= 4 and chance(s, p.guardDiscipline * 0.6) then
		setIntent(m, s, "guard", math.max(8, endsIn + 2), 0, false)
		s.defensive = true
		return true
	end
	if def.height == "Low" and framesLeft >= 1 and chance(s, p.lowReact) then
		setIntent(m, s, "crouch-guard", framesLeft + def.active + 6, 0, true)
		s.defensive = true
		return true
	end
	if def.height == "High" and framesLeft >= 3 and chance(s, p.duckHighs) then
		setIntent(m, s, "duck", framesLeft + def.active + 4, 0, true)
		s.defensive = true
		return true
	end
	if not def.homing and def.track < 2.5 and framesLeft >= 12 and m.frame - s.lastStep > p.stepGap * 0.5 and chance(s, p.stepChance * 2.5) then
		doSidestep(m, me, index, s, if chance(s, 0.5) then 1 else -1)
		return true
	end
	if s.x > 0 or s.crouch then
		if chance(s, p.guardDiscipline) then
			setIntent(m, s, "guard", math.max(8, endsIn + 2), 0, false)
			s.defensive = true
			return true
		end
		return false
	end
	if s.intent ~= "back-off" and s.intent ~= "step-out" then
		setIntent(m, s, "guard", math.max(8, endsIn + 2), 0, false)
		s.defensive = true
	end
	return true
end

local function whiffPunish(m: Sim.Match, me: Sim.Fighter, foe: Sim.Fighter, index: number, s: Brain, p: Params, seen: { [string]: any }, dist: number): boolean
	if not seen.move or seen.state ~= "Recovery" or seen.hasHit or s.whiffFor == seen.moveStart then return false end
	s.whiffFor = seen.moveStart
	local def = defOf(foe, seen.move)
	if not def or not treatAsStandalone(s, foe.character, seen.move) then return false end
	local remaining = totalOf(def) - (seen.moveFrame + (m.frame - seen.frame))
	if remaining < 6 or not chance(s, p.whiffPunish) then return false end
	local key = bestPunisher(me, remaining, dist, p, foe.crouched)
	if not key then return false end
	pressMove(m, me, index, s, key)
	planString(s, p, me, key, true)
	s.nextAttack = m.frame + 24
	return true
end

-- Longest reach of a fighter's quick pokes (impact <= 13): the distance from which it can start trading.
local pokeCache: { [any]: number } = {}
local function pokeRange(character: Roster.CharacterDef): number
	local cached = pokeCache[character]
	if cached then return cached end
	local best = 3.5
	for _, key in character.moveOrder do
		local def = character.moves[key]
		local prefix = prefixOf(def)
		if def.chainFrom == nil and def.damage > 0 and def.height ~= "Throw" and prefix ~= "dash" and prefix ~= "ss" and impactOf(def) <= 13 then
			best = math.max(best, threatOf(def))
		end
	end
	pokeCache[character] = best
	return best
end
AI.pokeRange = pokeRange

-- Turn-taking after an exchange: plus frames = my turn (poke again), minus frames = respect (guard for a moment).
local function afterExchange(m: Sim.Match, me: Sim.Fighter, foe: Sim.Fighter, index: number, s: Brain, p: Params, dist: number, prevState: string, prevMove: string?): boolean
	if prevState == "Blockstun" then
		local hit = me.lastHit
		-- A punish is already buffered for this block: let it come out.
		if hit and s.punishedFor == hit.frame then return true end
		local def = if hit then defOf(foe, hit.move) else nil
		local read = readOpponent(m, s)
		local takeChance = if read.spamKey ~= nil or read.rate >= 3 then math.max(p.turnTake, p.readSkill) else p.turnTake
		takeChance *= p.turnScale
		if def and def.onBlock < 0 and treatAsStandalone(s, foe.character, hit.move) and chance(s, takeChance) then
			-- Against crouching moves or a crouching player a high would whiff: answer with the fastest non-high.
			local foeLow = def.crouching or s.habits.crouchTime > 30 or (read.ducks and chance(s, p.readSkill))
			local list = candidates(me, "poke", dist, foeLow)
			for _, k in candidates(me, "mid", dist, true) do table.insert(list, k) end
			if #list == 0 then
				-- Nothing reaches from here: step in and take the turn when we have the time, i.e. a big minus, or we
				-- can walk into range and land a quick hit (about 18 frames with the step) before their usual next
				-- attack lands.
				local reach = 0
				for _, k in candidates(me, "poke", 0, foeLow) do reach = math.max(reach, threatOf(me.character.moves[k])) end
				for _, k in candidates(me, "mid", 0, true) do reach = math.max(reach, threatOf(me.character.moves[k])) end
				local walkFrames = math.max(0, dist - (reach - 0.15)) / (me.character.stats.walkSpeed / Config.FPS)
				if -def.onBlock >= 8 or -def.onBlock + read.impact > walkFrames + 18 then
					s.plan = { kind = "turn", untilFrame = m.frame + 16 }
					return false
				end
			end
			if #list > 0 then
				-- the fastest poke we have: we are only a few frames ahead
				local best, bestStartup = list[1], math.huge
				for _, k in list do local d = me.character.moves[k]; if d.startup < bestStartup then best, bestStartup = k, d.startup end end
				local key = if chance(s, p.readSkill) then best else list[rint(s, 1, #list)]
				pressMove(m, me, index, s, key)
				planString(s, p, me, key)
				s.nextAttack = m.frame + p.attackCadence
				return true
			end
		end
		setIntent(m, s, "respect", rint(s, 8, 20), 0, read.stance == "crouch" and chance(s, p.readSkill))
		s.defensive = true
		return false
	end
	if prevMove and (prevState == "Recovery" or prevState == "Active") then
		local def = me.character.moves[prevMove]
		local foeHit = foe.lastHit
		if def and foeHit and foeHit.move == prevMove and m.frame - foeHit.frame < 60 and foe.state ~= "Landing" and foe.state ~= "Airborne" then
			local adv = if foeHit.kind == "Block" then def.onBlock elseif typeof(def.onHit) == "number" then def.onHit :: number else 0
			if adv >= 1 and m.frame >= s.nextAttack - 20 and chance(s, p.pressure) then
				return chooseAttack(m, me, foe, index, s, p, dist, AI.perceive(m, 3 - index, 0))
			elseif adv <= -3 then
				setIntent(m, s, "respect", rint(s, 14, 30), 0, false)
				s.defensive = true
			end
		elseif def and not me.hasHit then
			-- Whiffed: back to guard for a moment.
			setIntent(m, s, "respect", rint(s, 10, 22), 0, false)
			s.defensive = true
		end
	end
	return false
end

local function neutral(m: Sim.Match, me: Sim.Fighter, foe: Sim.Fighter, index: number, s: Brain, p: Params, seen: { [string]: any }, dist: number)
	local plan = s.plan
	if plan and plan.kind == "turn" then
		-- Our turn after blocking a long-range minus move: close in and attack with the fastest thing that reaches.
		if m.frame > plan.untilFrame then
			s.plan = nil
		else
			local best, bestStartup = nil, math.huge
			for _, role in { "poke", "mid" } do
				for _, k in candidates(me, role, dist, s.habits.crouchTime > 30) do local d = me.character.moves[k]; if d.startup < bestStartup then best, bestStartup = k, d.startup end end
			end
			if best then
				s.plan = nil
				pressMove(m, me, index, s, best)
				planString(s, p, me, best)
				s.nextAttack = m.frame + p.attackCadence
				return
			end
			setIntent(m, s, "take-turn", 4, 1, false)
			applyIntent(m, me, index, s)
			return
		end
	end
	if plan and plan.kind == "walkThrow" then
		if m.frame > plan.untilFrame or (seen.crouched and seen.move == nil) then
			s.plan = nil
		elseif dist <= THROW_REACH - 0.25 then
			s.plan = nil
			pressMove(m, me, index, s, plan.key)
			s.stringPlan = nil
			return
		else
			setIntent(m, s, "walk-throw", 4, 1, false)
			applyIntent(m, me, index, s)
			return
		end
	end
	local pref = me.character.stats.preferredRange
	local engage = math.max(pref, pokeRange(me.character) - 0.5)
	local close = math.max(Config.Separation + 0.25, pref - 0.9)
	local read = readOpponent(m, s)
	local pressured = (read.rate >= 2 or read.throwStreak) and dist <= pokeRange(foe.character) + 0.5
	-- Patience: no read (a remembered streak, a crouch guess, a defensive intent) may keep the CPU passive while the
	-- opponent does nothing. A crouch held on a read ends after CROUCH_CAP frames without an attack from them (a bit
	-- longer while a low/throw streak is fresh) and is not re-armed for a moment, and a streak stays fresh for at most
	-- STREAK_FRESH frames of the opponent's free time; after `patience` neutral frames without an attack or a
	-- deliberate move, or 1.6x that in range without an attack, the CPU acts whatever its reads say.
	local foeQuiet = seen.move == nil and read.lastAge >= 40
	if s.x == 0 then s.idle = (s.idle or 0) + 1 else s.idle = 0 end
	if dist <= engage + 0.4 then s.rangeIdle = (s.rangeIdle or 0) + 1 end
	if foeQuiet then
		-- crouched frames since their last attack (a crouch they keep feeding with lows or grabs is not "unfed")
		local unfed = math.min(s.crouchRun or 0, read.lastAge)
		local cap = if read.lowStreak or read.throwStreak then CROUCH_CAP_STREAK else CROUCH_CAP
		if s.crouch and READ_CROUCH[s.intent] and unfed >= cap then
			s.crouch = false
			s.noCrouchUntil = m.frame + 45
			s.intentUntil = m.frame
		end
		if s.idle >= p.patience or (s.rangeIdle or 0) >= p.patience * 1.6 then
			s.idle = 0
			s.defensive = false
			if dist <= engage + 0.4 and chooseAttack(m, me, foe, index, s, p, dist, seen) then return end
			setIntent(m, s, "step-in", rint(s, 8, 14), 1, false)
			applyIntent(m, me, index, s)
			return
		end
	end
	local crouchOk = m.frame >= (s.noCrouchUntil or 0)
	if m.frame < s.intentUntil then
		if not s.defensive and not pressured and m.frame >= s.nextAttack and m.frame >= s.nextDecision and dist <= engage + 0.4 then
			s.nextDecision = m.frame + rint(s, p.decisionMin, p.decisionMax)
			if chance(s, p.aggression * 0.5) and chooseAttack(m, me, foe, index, s, p, dist, seen) then return end
		end
		applyIntent(m, me, index, s)
		return
	end
	s.defensive = false
	rerollDelay(s, p)
	s.nextDecision = m.frame + rint(s, p.decisionMin, p.decisionMax)
	if pressured then
		-- They keep pressing buttons in range: guard with the stance that beats their habits and never walk in.
		local readChance = if s.habits.crouchTime > 40 then math.min(1, p.readSkill + 0.25) else p.readSkill
		-- The same low (or grab) over and over: even a mid-level player starts ducking it.
		if read.lowStreak or read.throwStreak then readChance = readChance + (1 - readChance) * 0.5 end
		local crouchRead = (read.stance == "crouch" or read.throwStreak) and crouchOk and chance(s, readChance)
		-- Crouching most of the time but not attacking from there (a crouch turtle): open them up with mids.
		-- (Against high spam we stay down instead: the highs whiff over us and `react` answers from the crouch.)
		local foeTurtles = s.habits.crouchTime > 30 and not read.ducks
		if foeTurtles and m.frame >= s.nextAttack and chance(s, p.aggression * 0.6) then
			if chooseAttack(m, me, foe, index, s, p, dist, seen) then return end
		end
		-- They walk back into range between attacks: stick out the fastest poke that reaches (interrupt).
		if seen.state == "Walk" and seen.move == nil and chance(s, p.readSkill * 0.5) then
			local best, bestStartup = nil, math.huge
			for _, k in candidates(me, "poke", dist, false) do local d = me.character.moves[k]; if d.startup < bestStartup then best, bestStartup = k, d.startup end end
			for _, k in candidates(me, "mid", dist, false) do local d = me.character.moves[k]; if d.startup < bestStartup then best, bestStartup = k, d.startup end end
			if best then pressMove(m, me, index, s, best); planString(s, p, me, best); s.nextAttack = m.frame + p.attackCadence; return end
		end
		-- Behind with little time left: waiting out their pokes loses the round, so go in instead of guarding.
		local behind = me.health / me.maxHealth < foe.health / foe.maxHealth
		if behind and m.timer <= Config.FPS * 15 and dist > pokeRange(me.character) - 0.2 then
			if m.frame - s.lastDash > 30 then doDash(m, me, index, s, 1) return end
			setIntent(m, s, "close-in", rint(s, 8, 14), 1, false)
			applyIntent(m, me, index, s)
			return
		end
		-- Crowded inside grab range by a button-masher: a beginner-level player mashes its fastest poke (which also
		-- beats a grab) instead of only holding guard (`crowdJab`, Easy; stronger levels break and duck grabs).
		if p.crowdJab > 0 and read.rate >= 4 and dist <= THROW_REACH + 0.2 and m.frame - s.lastAttackFrame > 30 and chance(s, p.crowdJab) then
			local best, bestStartup = nil, math.huge
			for _, k in candidates(me, "poke", dist, false) do local d = me.character.moves[k]; if d.startup < bestStartup then best, bestStartup = k, d.startup end end
			if best then pressMove(m, me, index, s, best); planString(s, p, me, best); return end
		end
		-- Backing off is a standing guard: not while reading their lows or grabs (crouchRead holds the crouch).
		if dist < close and not crouchRead and chance(s, 0.3) then setIntent(m, s, "back-off", rint(s, 10, 18), -1, false)
		else setIntent(m, s, "pressure-guard", rint(s, 12, 26), 0, crouchRead) end
		s.defensive = not crouchRead
		applyIntent(m, me, index, s)
		return
	end
	if dist <= engage + 0.4 and m.frame >= s.nextAttack and chance(s, p.aggression) then
		if chooseAttack(m, me, foe, index, s, p, dist, seen) then return end
	end
	local r = rand(s)
	if dist > engage + 0.9 then
		-- Chase a runner with dashes; otherwise walk in (an occasional dash from far away).
		local running = (s.habits.retreat or 0) > 8
		if running and m.frame - s.lastDash > 24 and chance(s, 0.4 + p.dashIn) then doDash(m, me, index, s, 1) return end
		if dist > 6.8 and m.frame - s.lastDash > 100 and chance(s, p.dashIn) then doDash(m, me, index, s, 1) return end
		if read.rate >= 2 and dist <= pokeRange(foe.character) + 1.6 and s.intent == "approach" and chance(s, 0.35 + p.readSkill * 0.4) then
			-- They keep swinging: close in a step at a time, guarding (low if that is their habit) in between.
			local low = read.stance == "crouch" and crouchOk and chance(s, p.readSkill)
			setIntent(m, s, if low then "approach-crouch" else "guard", rint(s, 10, 18), 0, low)
		else
			setIntent(m, s, "approach", rint(s, if read.rate >= 2 then 8 else 14, if read.rate >= 2 then 14 else 30), 1, false)
		end
	elseif dist > engage then
		-- At the edge of range: inch in, wait, or give ground.
		if r < 0.5 then setIntent(m, s, "step-in", rint(s, 8, 14), 1, false)
		elseif r < 0.85 then setIntent(m, s, "hold", rint(s, 14, 30), 0, false)
		else setIntent(m, s, "step-out", rint(s, 10, 16), -1, false) end
	elseif dist >= close then
		-- In range: mostly stand guard and look for an opening.
		if m.frame - s.lastStep > p.stepGap and chance(s, p.stepChance) then
			doSidestep(m, me, index, s, if chance(s, 0.5) then 1 else -1)
			return
		end
		local lowRead = math.min(1, s.habits.lows / 3) * p.lowRead
		if s.habits.mids > s.habits.lows then lowRead *= 0.3 end
		if crouchOk and chance(s, lowRead) then setIntent(m, s, "crouch-read", rint(s, 14, 28), 0, true); s.defensive = true
		elseif r < 0.62 then
			-- Beginners fidget forward instead of standing in guard.
			if chance(s, p.holdGuard) then setIntent(m, s, "hold", rint(s, 14, 36), 0, false) else setIntent(m, s, "step-in", rint(s, 10, 20), 1, false) end
		elseif r < 0.9 then
			-- Right after stepping in, settle instead of walking straight back out (no back-and-forth shuffling).
			if s.intent == "step-in" then setIntent(m, s, "hold", rint(s, 14, 30), 0, false) else setIntent(m, s, "step-out", rint(s, 10, 18), -1, false) end
		else setIntent(m, s, "step-in", rint(s, 6, 10), 1, false) end
	else
		if m.frame - s.lastBackdash > 150 and chance(s, p.backdashChance * 2) then doDash(m, me, index, s, -1) return end
		-- Too close: players who care about spacing give ground; beginners mostly stay put.
		if r < 0.45 * p.holdGuard and s.intent ~= "step-in" and s.intent ~= "approach" then setIntent(m, s, "back-off", rint(s, 12, 24), -1, false)
		else setIntent(m, s, "hold", rint(s, 10, 22), 0, false) end
	end
	applyIntent(m, me, index, s)
end

-- Main entry: drive fighter `index` for the current frame (call before Sim.step).
function AI.step(m: Sim.Match, index: number)
	if m.phase ~= "Fight" or m.hitstop > 0 then return end
	AI.observe(m)
	local me, foe = m.fighters[index], m.fighters[3 - index]
	me.dummy = nil
	local s = brain(m, me, index, AI.params(m.difficulty))
	local p: Params = s.params or AI.params(m.difficulty)
	local prevState: string, prevMove: string? = s.prevState or "Idle", s.prevMove
	s.prevState = me.state
	s.prevMove = me.move
	-- Activity bookkeeping for the patience rule (see `neutral`): crouch run and attacks started by any path.
	if me.crouched and me.move == nil then s.crouchRun = (s.crouchRun or 0) + 1 else s.crouchRun = 0 end
	if me.move and me.moveFrame <= 1 then s.idle = 0; s.rangeIdle = 0 end
	if me.health <= 0 then releaseAll(m, me, index) return end
	if me.throwInfo then
		if me.throwInfo.role == "Defender" then defendThrow(m, me, index, s, p) end
		return
	end
	local seen = AI.perceive(m, 3 - index, s.delay)
	learn(m, s, seen, foe)
	if foe.health <= 0 then releaseAll(m, me, index) return end
	local state = me.state
	if state == "Landing" then chooseGetup(m, me, index, s, p) return end
	if state == "Getup" then
		if s.getupMode ~= "BackRoll" then wakeGuard(m, me, index, s, p) end
		return
	end
	if state == "Airborne" or state == "Hitstun" or state == "Stagger" or state == "KO" then
		releaseAll(m, me, index)
		s.stringPlan = nil
		s.punishKey = nil
		return
	end
	if state == "Blockstun" then blockstun(m, me, foe, index, s, p) return end
	if me.move then continueString(m, me, foe, index, s, p) return end
	if state == "Dash" or state == "Backdash" or state == "Sidestep" then
		local plan = s.plan
		if plan and (plan.kind == "dashAttack" or plan.kind == "stepAttack") and m.frame >= plan.at then
			s.plan = nil
			Sim.queueAttack(me, plan.key)
			planString(s, p, me, plan.key)
		end
		return
	end
	local plan = s.plan
	if plan and (plan.kind == "dashAttack" or plan.kind == "stepAttack") and m.frame > plan.at + 24 then s.plan = nil end
	local dist = flatDistance(me, foe)
	if plan and plan.kind == "whiffPunish" then
		if m.frame >= plan.at then
			-- We saw it coming up short (or ducked the grab): now it whiffs, punish the recovery.
			s.plan = nil
			local fdef = defOf(foe, foe.move)
			if foe.move == plan.key and fdef and not foe.hasHit and (foe.state == "Recovery" or foe.state == "Active") then
				local key = bestPunisher(me, totalOf(fdef) - foe.moveFrame, dist, p, foe.crouched)
				if key then
					pressMove(m, me, index, s, key)
					planString(s, p, me, key, true)
					s.nextAttack = m.frame + 24
					return
				end
			end
		elseif foe.move ~= plan.key then
			s.plan = nil
		end
	end
	if foe.state == "Airborne" then juggle(m, me, foe, index, s, p, dist) return end
	if foe.state == "Landing" or foe.state == "Getup" then okizeme(m, me, foe, index, s, p, dist) return end
	if s.plan and (s.plan.kind == "meaty" or s.plan.kind == "wakeGuard") then s.plan = nil end
	if (prevState == "Blockstun" or ((prevState == "Recovery" or prevState == "Active") and prevMove ~= nil)) and afterExchange(m, me, foe, index, s, p, dist, prevState, prevMove) then return end
	if react(m, me, foe, index, s, p, seen, dist) then
		if s.plan and s.plan.kind == "walkThrow" then s.plan = nil end
		if me.state == "Sidestep" or s.intent == "sidestep" then return end
		applyIntent(m, me, index, s)
		return
	end
	if whiffPunish(m, me, foe, index, s, p, seen, dist) then return end
	neutral(m, me, foe, index, s, p, seen, dist)
end

return AI
