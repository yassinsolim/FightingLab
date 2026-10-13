--!strict
-- Pure client presentation buffer for authoritative FightingLab snapshots.
local Config = require(script.Parent.CombatConfig)
local Roster = require(script.Parent.Roster)

export type ThrowState = { role: string, archetype: string, frame: number, duration: number, impactFrame: number, move: string?, breakWindow: number?, broken: boolean?, breakFrame: number? }
export type LastHitState = { kind: string, height: string, tier: string, counter: boolean, frame: number, move: string, limb: string, side: number }
export type FighterState = {
	pos: Vector3, facing: Vector3, health: number, maxHealth: number, state: string, move: string?, moveName: string?,
	moveFrame: number, stun: number, stagger: number, combo: number, crouched: boolean, walkPhase: number, moveX: number,
	characterId: string, throw: ThrowState?, armorActive: boolean, crush: string?, commandId: number?, moveStartFrame: number?,
	lastHit: LastHitState?, velocityY: number, airFrames: number, airHits: number, knockdown: string?, dashDirection: number,
	guard: string?, stepDir: number, stepFrame: number, dashFrame: number, dashTotal: number, stringIndex: number,
	crouchFrames: number, getupKind: string?, rollDir: number,
	surge: boolean, ultUsed: boolean, tumble: boolean, stance: string?, stanceFrame: number,
}
export type SnapEvent = {
	kind: string, attacker: number, target: number, move: string?, damage: number,
	advantage: number, combo: number, air: boolean, point: Vector3?, frame: number,
	counter: boolean?, launch: boolean?, knockdown: boolean?, tier: string?, archetype: string?,
	height: string?, limb: string?, evaded: boolean?, tumble: boolean?, punish: boolean?,
}
export type Entry = {
	frame: number, epoch: number, serverTime: number, phase: string, mode: string, sparring: boolean,
	ko: boolean, paused: boolean, timer: number, scores: { number }, round: number, winner: number?, reason: string,
	hitstop: number, fighters: { FighterState }, events: { SnapEvent }, time: number,
	stageId: string, p1Id: string, p2Id: string, p2Human: boolean, matchId: string?, dummy: string?,
}
export type Rendered = FighterState & { extrapolated: number }
export type Buffer = {
	entries: { Entry }, epoch: number, offset: number?, period: number, delay: number, capacity: number, flushes: number, cursor: number?,
	adaptive: boolean, minDelay: number, maxDelay: number, grow: number, decay: number, cooldown: number,
	frames: number, starved: number, lastGrowFrame: number,
}
export type Options = { period: number?, delay: number?, capacity: number?, adaptive: boolean?, minDelay: number?, maxDelay: number?, grow: number?, decay: number? }
export type EventQueue = { pending: { { time: number, event: SnapEvent } }, seen: { [string]: boolean }, order: { string } }

local RenderBuffer = {}
local LOCKED: { [string]: boolean } = { Startup = true, Active = true, Recovery = true, Hitstun = true, Blockstun = true, Airborne = true, Landing = true, Getup = true, Dash = true, Backdash = true, Sidestep = true, KO = true, Throw = true, Stagger = true, Stance = true, Ultimate = true }
RenderBuffer.TeleportDistance = 6

-- Default: the legacy every-third-frame stream with a fixed delay. Server duels stream every 60 Hz step and pass
-- { period = 1/60, adaptive = true }: the delay is then driven by starvation (render time past the newest entry):
-- each starved frame grows it at once (with a short cooldown), every fed frame shrinks it a little. The equilibrium
-- is about one starved frame in a hundred, i.e. the smallest delay the connection sustains.
function RenderBuffer.new(opts: Options?): Buffer
	local o = opts or {}
	local period = o.period or Config.SnapshotEvery / Config.FPS
	return {
		entries = {}, epoch = -1, offset = nil, period = period, delay = o.delay or period + 0.012, capacity = o.capacity or 12, flushes = 0, cursor = nil,
		adaptive = o.adaptive == true, minDelay = o.minDelay or 0.004, maxDelay = o.maxDelay or 0.15, grow = o.grow or 0.003, decay = o.decay or 0.00003,
		cooldown = 6, frames = 0, starved = 0, lastGrowFrame = -math.huge,
	}
end
local function num(v: unknown): number? return if typeof(v) == "number" and v == v and math.abs(v) < math.huge then v else nil end
local function validCharacter(raw: unknown, fallback: string): string
	return if typeof(raw) == "string" and Roster.has(raw) then raw else fallback
end
local function moveExists(id: string, move: unknown): string?
	if typeof(move) ~= "string" then return nil end
	local ok = Roster.get(id).moves[move] ~= nil
	return if ok then move else nil
end
local function parseThrow(raw: unknown): ThrowState?
	if raw == nil then return nil end
	if typeof(raw) ~= "table" then return nil end
	local role, archetype = raw.role, raw.archetype
	local frame, duration, impactFrame = num(raw.frame), num(raw.duration), num(raw.impactFrame)
	if (role ~= "Attacker" and role ~= "Defender") or typeof(archetype) ~= "string" or not frame or not duration or not impactFrame then return nil end
	local move = raw.move
	local broken = raw.broken == true
	return { role = role, archetype = archetype, frame = frame, duration = duration, impactFrame = impactFrame, move = if typeof(move) == "string" then move else nil, breakWindow = num(raw.breakWindow),
		broken = if broken then true else nil, breakFrame = if broken then num(raw.breakFrame) else nil }
end
local function parseLastHit(raw: unknown): LastHitState?
	if raw == nil then return nil end
	if typeof(raw) ~= "table" then return nil end
	local kind, height, tier, move, limb = raw.kind, raw.height, raw.tier, raw.move, raw.limb
	local frame, side = num(raw.frame), num(raw.side)
	if typeof(kind) ~= "string" or typeof(height) ~= "string" or typeof(tier) ~= "string" or typeof(move) ~= "string" or typeof(limb) ~= "string" or not frame or not side then return nil end
	return { kind = kind, height = height, tier = tier, counter = raw.counter == true, frame = frame, move = move, limb = limb, side = side }
end
local function parseFighter(raw: unknown, fallbackId: string): FighterState?
	if typeof(raw) ~= "table" then return nil end
	local characterId = validCharacter(raw.characterId, fallbackId)
	local pos, facing = raw.pos, raw.facing
	local health, moveFrame, stun, combo = num(raw.health), num(raw.moveFrame), num(raw.stun), num(raw.combo)
	local walkPhase, moveX = num(raw.walkPhase) or 0, num(raw.moveX) or 0
	local state, move, crouched = raw.state, raw.move, raw.crouched
	if typeof(pos) ~= "Vector3" or typeof(facing) ~= "Vector3" or typeof(state) ~= "string" or typeof(crouched) ~= "boolean" then return nil end
	if not (health and moveFrame and stun and combo) then return nil end
	local moveName = raw.moveName
	local crush = raw.crush
	return {
		pos = pos, facing = facing, health = health, maxHealth = num(raw.maxHealth) or Roster.get(characterId).stats.maxHealth,
		state = state, move = moveExists(characterId, move), moveName = if typeof(moveName) == "string" then moveName else nil,
		moveFrame = moveFrame, stun = stun, stagger = num(raw.stagger) or 0, combo = combo, crouched = crouched,
		walkPhase = walkPhase, moveX = moveX, characterId = characterId, throw = parseThrow(raw.throw),
		armorActive = raw.armorActive == true, crush = if crush == "High" or crush == "Low" then crush else nil,
		commandId = num(raw.commandId), moveStartFrame = num(raw.moveStartFrame),
		lastHit = parseLastHit(raw.lastHit), velocityY = num(raw.velocityY) or 0, airFrames = num(raw.airFrames) or 0,
		airHits = num(raw.airHits) or 0, knockdown = if raw.knockdown == "FaceUp" or raw.knockdown == "FaceDown" then raw.knockdown else nil,
		dashDirection = num(raw.dashDirection) or 0,
		guard = if raw.guard == "Stand" or raw.guard == "Crouch" or raw.guard == "All" then raw.guard else nil,
		stepDir = num(raw.stepDir) or 0, stepFrame = num(raw.stepFrame) or 0, dashFrame = num(raw.dashFrame) or 0, dashTotal = num(raw.dashTotal) or 0,
		stringIndex = num(raw.stringIndex) or 0, crouchFrames = num(raw.crouchFrames) or 0,
		getupKind = if raw.getupKind == "Stand" or raw.getupKind == "BackRoll" or raw.getupKind == "SideRoll" then raw.getupKind else nil,
		rollDir = num(raw.rollDir) or 0,
		-- Round 6: Surge / Ultimate (contract A), signature stance, tumble.
		surge = raw.surge == true, ultUsed = raw.ultUsed == true, tumble = raw.tumble == true,
		stance = if typeof(raw.stance) == "string" and Roster.stance(characterId, raw.stance) ~= nil then raw.stance else nil,
		stanceFrame = num(raw.stanceFrame) or 0,
	}
end
local function parseEvent(raw: unknown): SnapEvent?
	if typeof(raw) ~= "table" then return nil end
	local kind, attacker, target, move = raw.kind, num(raw.attacker), num(raw.target), raw.move
	local frame = num(raw.frame)
	if typeof(kind) ~= "string" or not frame or not attacker or not target then return nil end
	if (attacker ~= 1 and attacker ~= 2) or (target ~= 1 and target ~= 2) then return nil end
	local point = raw.point
	local tier = raw.tier
	local archetype = raw.archetype
	return {
		kind = kind, attacker = attacker, target = target, move = if typeof(move) == "string" then move else nil,
		damage = num(raw.damage) or 0, advantage = num(raw.advantage) or 0, combo = num(raw.combo) or 0,
		air = raw.air == true, point = if typeof(point) == "Vector3" then point else nil, frame = frame,
		counter = if raw.counter == true then true else nil, launch = if raw.launch == true then true else nil,
		knockdown = if raw.knockdown == true then true else nil, tier = if typeof(tier) == "string" then tier else nil,
		archetype = if typeof(archetype) == "string" then archetype else nil,
		height = if typeof(raw.height) == "string" then raw.height else nil,
		limb = if typeof(raw.limb) == "string" then raw.limb else nil,
		evaded = if raw.evaded == true then true else nil,
		tumble = if raw.tumble == true then true else nil,
		punish = if raw.punish == true then true else nil,
	}
end
function RenderBuffer.parse(raw: unknown): Entry?
	if typeof(raw) ~= "table" then return nil end
	local frame, epoch = num(raw.frame), num(raw.epoch) or 0
	local phase, mode, fighters, events, scores = raw.phase, raw.mode, raw.fighters, raw.events, raw.scores
	if not frame or typeof(phase) ~= "string" or typeof(mode) ~= "string" or typeof(fighters) ~= "table" then return nil end
	local p1Id, p2Id = validCharacter(raw.p1Id, Config.DefaultP1), validCharacter(raw.p2Id, Config.DefaultP2)
	local a, b = parseFighter(fighters[1], p1Id), parseFighter(fighters[2], p2Id)
	if not a or not b then return nil end
	local list: { SnapEvent } = {}
	if typeof(events) == "table" then for _, e in events do local parsed = parseEvent(e); if parsed then table.insert(list, parsed) end end end
	local scoreList = { 0, 0 }
	if typeof(scores) == "table" then scoreList = { num(scores[1]) or 0, num(scores[2]) or 0 } end
	local reason = raw.reason
	local stageId = raw.stageId
	return {
		frame = frame, epoch = epoch, serverTime = num(raw.serverTime) or 0, phase = phase, mode = mode,
		sparring = raw.sparring == true, ko = raw.ko == true, paused = raw.paused == true, timer = num(raw.timer) or 0,
		scores = scoreList, round = num(raw.round) or 1, winner = num(raw.winner), reason = if typeof(reason) == "string" then reason else "",
		hitstop = math.max(0, num(raw.hitstop) or 0), fighters = { a, b }, events = list, time = frame / Config.FPS,
		stageId = if typeof(stageId) == "string" then stageId else Config.DefaultStage, p1Id = p1Id, p2Id = p2Id,
		p2Human = raw.p2Human == true, matchId = if typeof(raw.matchId) == "string" then raw.matchId else nil,
		dummy = if raw.dummy == "Stand" or raw.dummy == "Guard" or raw.dummy == "Fight" then raw.dummy else nil,
	}
end
function RenderBuffer.flush(buffer: Buffer) table.clear(buffer.entries); buffer.offset=nil; buffer.cursor=nil; buffer.flushes += 1 end
function RenderBuffer.push(buffer: Buffer, entry: Entry, receivedAt: number): boolean
	local entries=buffer.entries; local last=entries[#entries]; local flushed=false
	if last and entry.epoch == buffer.epoch and entry.frame == last.frame then return false end
	if entry.epoch ~= buffer.epoch or (last and entry.frame < last.frame) or (last and last.phase ~= "Ready" and entry.phase == "Ready") then RenderBuffer.flush(buffer); buffer.epoch=entry.epoch; flushed=true end
	table.insert(entries, entry); while #entries > buffer.capacity do table.remove(entries, 1) end
	local sample=receivedAt-entry.time
	if buffer.offset == nil or sample < buffer.offset then buffer.offset=sample else buffer.offset += (sample-buffer.offset)*0.02 end
	return flushed
end
function RenderBuffer.renderTime(buffer: Buffer, now: number): number
	local t=now-(buffer.offset or 0)-buffer.delay; local cursor=math.max(buffer.cursor or t,t); buffer.cursor=cursor
	if buffer.adaptive then
		local last = buffer.entries[#buffer.entries]
		if last then
			buffer.frames += 1
			if cursor > last.time + 1e-4 then
				buffer.starved += 1
				if buffer.frames - buffer.lastGrowFrame >= buffer.cooldown then
					buffer.lastGrowFrame = buffer.frames
					buffer.delay = math.min(buffer.maxDelay, buffer.delay + buffer.grow)
				end
			else
				buffer.delay = math.max(buffer.minDelay, buffer.delay - buffer.decay)
			end
		end
	end
	return cursor
end
function RenderBuffer.eventKey(event: SnapEvent): string return string.format("%d:%d:%s:%s", event.attacker, event.frame, event.move or "", event.kind) end
function RenderBuffer.eventTime(event: SnapEvent): number return event.frame / Config.FPS end
function RenderBuffer.newEventQueue(): EventQueue return { pending = {}, seen = {}, order = {} } end
function RenderBuffer.clearEvents(queue: EventQueue) table.clear(queue.pending); table.clear(queue.seen); table.clear(queue.order) end
function RenderBuffer.enqueueEvent(queue: EventQueue, event: SnapEvent): boolean
	local key=RenderBuffer.eventKey(event); if queue.seen[key] then return false end
	queue.seen[key]=true; table.insert(queue.order,key); if #queue.order>256 then queue.seen[table.remove(queue.order,1)]=nil end
	table.insert(queue.pending,{time=RenderBuffer.eventTime(event),event=event}); return true
end
function RenderBuffer.drainEvents(queue: EventQueue, renderT: number): { SnapEvent }
	local due: { SnapEvent }={}; local i=1
	while i<=#queue.pending do local q=queue.pending[i]; if q.time<=renderT then table.insert(due,q.event); table.remove(queue.pending,i) else i+=1 end end
	return due
end
local function flatFacing(a: Vector3,b: Vector3,alpha: number): Vector3 if a:Dot(b)<-0.5 then return if alpha<0.5 then a else b end; local f=a:Lerp(b,alpha); return if f.Magnitude>1e-3 then f.Unit else b end
local function from(f: FighterState,pos: Vector3,facing: Vector3,moveFrame: number,walkPhase: number,extrapolated: number): Rendered
	local rendered: any = table.clone(f)
	rendered.pos = pos
	rendered.facing = facing
	rendered.moveFrame = moveFrame
	rendered.walkPhase = walkPhase
	rendered.extrapolated = extrapolated
	return rendered :: Rendered
end
function RenderBuffer.canExtrapolate(entry: Entry, f: FighterState): boolean return entry.phase=="Fight" and not entry.ko and f.health>0 and not LOCKED[f.state] end
function RenderBuffer.sampleAt(buffer: Buffer, index: number, t: number): Rendered?
	local entries=buffer.entries; local n=#entries; if n==0 then return nil end
	local first=entries[1]
	if t<=first.time or n==1 then local f=first.fighters[index]; if n==1 or t<=first.time then return from(f,f.pos,f.facing,f.moveFrame,f.walkPhase,0) end end
	local last=entries[n]
	if t>=last.time then
		local f=last.fighters[index]; local prev=entries[n-1].fighters[index]; local dt=math.min(t-last.time,buffer.period); local span=last.time-entries[n-1].time
		if dt>0 and span>0 and RenderBuffer.canExtrapolate(last,f) and (f.pos-prev.pos).Magnitude<RenderBuffer.TeleportDistance then local velocity=(f.pos-prev.pos)/span; return from(f,f.pos+velocity*dt,f.facing,f.moveFrame,f.walkPhase+(f.walkPhase-prev.walkPhase)/span*dt,dt) end
		return from(f,f.pos,f.facing,f.moveFrame,f.walkPhase,0)
	end
	for i=n-1,1,-1 do
		local a=entries[i]
		if a.time<=t then
			local b=entries[i+1]; local alpha=(t-a.time)/(b.time-a.time); local fa,fb=a.fighters[index],b.fighters[index]
			if (fb.pos-fa.pos).Magnitude>=RenderBuffer.TeleportDistance then local f=if alpha<0.5 then fa else fb; return from(f,f.pos,f.facing,f.moveFrame,f.walkPhase,0) end
			local pos=fa.pos:Lerp(fb.pos,alpha); local facing=flatFacing(fa.facing,fb.facing,alpha); local base=fa; local moveFrame=base.moveFrame; local frames=b.frame-a.frame
			if fa.move~=nil and fa.move==fb.move and fb.moveFrame>=fa.moveFrame then base=if alpha<0.5 then fa else fb; moveFrame=fa.moveFrame+(fb.moveFrame-fa.moveFrame)*alpha
			elseif fb.move~=nil and fb.move~=fa.move then
				local intoMove=frames*alpha-(frames-fb.moveFrame+1)
				if intoMove>=0 then base=fb; moveFrame=intoMove+1 elseif fa.move~=nil then base=fa; moveFrame=fa.moveFrame+frames*alpha else base=fa end
				if base.move then local def=Roster.getMove(base.characterId, base.move); base=table.clone(base); base.state=if moveFrame<=def.startup then "Startup" elseif moveFrame<=def.startup+def.active then "Active" else "Recovery" end
			elseif fa.move~=nil and fb.move==nil and not LOCKED[fb.state] then
				local totalFrame=fa.moveFrame+frames*alpha; local def=Roster.getMove(fa.characterId, fa.move)
				if totalFrame<=def.startup+def.active+def.recovery then base=fa; moveFrame=totalFrame end
			end
			local walkPhase=if fb.walkPhase>=fa.walkPhase then fa.walkPhase+(fb.walkPhase-fa.walkPhase)*alpha else base.walkPhase
			return from(base,pos,facing,moveFrame,walkPhase,0)
		end
	end
	local f=first.fighters[index]; return from(f,f.pos,f.facing,f.moveFrame,f.walkPhase,0)
end
function RenderBuffer.sample(buffer: Buffer, index: number, now: number): Rendered? return RenderBuffer.sampleAt(buffer,index,RenderBuffer.renderTime(buffer,now)) end
function RenderBuffer.latest(buffer: Buffer): Entry? return buffer.entries[#buffer.entries] end
return RenderBuffer
