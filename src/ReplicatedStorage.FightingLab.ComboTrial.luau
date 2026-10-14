--!strict
-- Combo trials (round 7, Contract C; owner combat, play renders). One listed combo route of a fighter
-- (Roster CharacterDef.combos) as a practice challenge. Pure: no Instances, no services.
--
--   ComboTrial.list(id) -> { { index, name, notation, difficulty, damage, kind, counter, surge,
--                              steps = { { label, notation, move } } } }
--       steps[k].move = the move KEY step k performs (a string follow-up resolves to its string key, "3+4" to the
--       stance entry / catch key, "1+2" to "Ultimate"); label = its display name; notation = the step's input.
--   ComboTrial.new(id, index) -> Trial
--   trial:feed(entry) -> Status     (entry = a practice MatchRunner entry, raw or RenderBuffer.parse'd:
--                                    `fighters`, `events`, `frame`, `hitstop`; the player is slot 1, the dummy slot 2)
--   trial:reset(); trial:status() -> Status
--       Status = { state = "Ready" | "Running" | "Success" | "Failed", step = last completed step 0..n, total = n,
--                  reason = nil | "Early" | "Late" | "Wrong" | "Blocked" | "Whiffed" | "Dropped", damage = so far }
--   ComboTrial.demo(id, index) -> { { frame, press?, hold?, step?, notation? } }
--
-- Trial rules. Ready until step 1 lands (a hit by its move; a counter route needs a COUNTER hit; a "3+4" stance entry
-- as step 1 counts when the fighter is in that stance). Running: each next step must be performed by its move and
-- keep the combo going (the dummy still in hitstun / juggled). It fails as soon as the combo is broken:
--   Wrong    a different move started (or hit / whiffed / threw)
--   Late     the right button after the combo was over (the string window closed and the plain move came out, the
--            dummy had already recovered or landed, or the hit no longer combos)
--   Early    the right move came out while the juggled dummy was still too high to hit
--   Whiffed  the right move came out in time but missed (out of reach)
--   Blocked  the dummy blocked (Guard dummy), parried, crushed, caught or armored it
--   Dropped  nothing came out in time (no press, or a press so early it was not kept)
-- Success when the last step lands; the damage keeps adding up while an Ultimate ender's cinematic plays. From
-- Success or Failed a new step-1 hit (or stance entry) starts the next attempt by itself; call reset() when the
-- practice resets (positions / dummy).
--
-- Demo: an input script that performs the route from the practice start (Config.StartDistance, a standing dummy):
-- it walks in to the route's distance, settles, then presses every step with the route timing. `frame` counts runner
-- steps from the start of the playback (hitstop frames included). For each entry apply `hold` first (send
-- Move(moveX, moveZ) and Crouch(crouch)), then `press` (send Attack(press); press is a sim button name: "LeadPunch",
-- "RearPunch", "LeadKick", "RearKick", "Kicks" = 3+4, "Ultimate" = 1+2), then step the runner. Counter routes need
-- the dummy to be attacking when the opener lands: their script is timed for a counter-hit opener (the dummy's jab
-- starting on frame <opener press> + <opener startup> - 7); on a standing dummy it only shows the inputs.
local Roster = require(script.Parent.Roster)

local ComboTrial = {}
ComboTrial.__index = ComboTrial

export type Step = { label: string, notation: string, move: string, stance: string? }
export type Info = {
	index: number, name: string, notation: string, difficulty: number, damage: number, kind: string,
	counter: boolean, surge: boolean, steps: { Step },
}
export type Status = { state: string, step: number, total: number, reason: string?, damage: number }
export type DemoEntry = { frame: number, press: string?, hold: { moveX: number, moveZ: number, crouch: boolean }?, step: number?, notation: string? }

-- A juggled body above this height cannot be hit (CombatConfig.AirHitCeiling); a whiff up there is an early press.
local AIR_CEILING = 4.5
-- Frames the trial waits after the dummy leaves the combo before it names the reason (a move that is already on its
-- way can still be blocked or whiff).
local GRACE = 6
-- A running trial with no progress for this long is over.
local IDLE_LIMIT = 300
-- Frames of the string window after the source move's active frames (CombatSim.ChainLate).
local CHAIN_LATE = 14

local HIT_KINDS: { [string]: boolean } = { Hit = true, KO = true }
local BUTTON_OF: { [string]: string } = { ["1"] = "LeadPunch", ["2"] = "RearPunch", ["3"] = "LeadKick", ["4"] = "RearKick",
	["1+2"] = "Ultimate", ["3+4"] = "Kicks", ["1+3"] = "Throw", ["2+4"] = "Throw2" }
local DIR_OF: { [string]: { number } } = { f = { 1, 0 }, b = { -1, 0 }, d = { 0, 1 }, df = { 1, 1 }, db = { -1, 1 } }

-- One step's input in display notation ("df+2", "PKT+2", "3+4", "1+2") -> held x, crouch, sim button.
local function parse(notation: string): (number, boolean, string?)
	local s = string.gsub(notation, "%s+", "")
	local tag, rest = string.match(s, "^(%u%u+)%+(.+)$")
	if tag and rest then s = rest end
	local x, crouch = 0, false
	local dir, buttons = string.match(s, "^(%l+)%+(.+)$")
	if dir and DIR_OF[dir] then
		x = DIR_OF[dir][1]; crouch = DIR_OF[dir][2] == 1
		s = buttons :: string
	end
	return x, crouch, BUTTON_OF[s]
end
ComboTrial.parse = parse

-- The move a player gets for a notation from neutral or from the stance it names ("df+2", "PKT+2", "3+4", "1+2").
local function byNotation(c: Roster.CharacterDef, notation: string): string?
	if notation == "1+2" then return if c.moves.Ultimate then "Ultimate" else nil end
	for _, key in c.moveOrder do
		local def = c.moves[key]
		if def.chainFrom == nil and def.notation == notation then return key end
	end
	return nil
end

-- Move key of every step: a plain button right after a move is its string follow-up when the step's wait falls inside
-- the string window (the same rule CombatSim.selectMove applies), otherwise the move its notation names.
local function stepKeys(c: Roster.CharacterDef, combo: Roster.ComboDef): { string }
	local keys: { string } = {}
	local prev: string? = nil
	for k, step in combo.steps do
		local key: string? = nil
		if prev and not string.find(step.input, "+", 1, true) then
			local pdef = c.moves[prev]
			for _, fk in c.moveOrder do
				local fdef = c.moves[fk]
				if fdef.chainFrom == prev and string.match(fdef.notation, "([^,]+)$") == step.input then
					local late = pdef.startup + pdef.active + CHAIN_LATE + (fdef.delay or 0)
					if step.wait - 1 <= math.min(late, pdef.startup + pdef.active + pdef.recovery - 1) then key = fk end
				end
			end
		end
		key = key or byNotation(c, step.input)
		assert(key ~= nil, "ComboTrial: " .. c.id .. " combo '" .. combo.name .. "' step " .. k .. " (" .. step.input .. ") names no move")
		keys[k] = key :: string
		prev = key
	end
	return keys
end
ComboTrial.stepKeys = stepKeys

local listCache: { [string]: { Info } } = {}

-- Every listed combo of a fighter with the move each step performs.
function ComboTrial.list(characterId: string): { Info }
	local cached = listCache[characterId]
	if cached then return cached end
	local out: { Info } = {}
	if not Roster.has(characterId) then return out end
	local c = Roster.get(characterId)
	for i, combo in c.combos do
		local keys = stepKeys(c, combo)
		local steps: { Step } = {}
		for k, step in combo.steps do
			local def = c.moves[keys[k]]
			local stance = def.toStance
			local label = def.name
			if stance and c.stances[stance] then label = c.stances[stance].name end
			steps[k] = { label = label, notation = step.input, move = keys[k], stance = stance }
		end
		table.insert(out, {
			index = i, name = combo.name, notation = combo.notation, difficulty = combo.difficulty, damage = combo.damage,
			kind = combo.kind, counter = combo.counter == true, surge = combo.surge == true, steps = steps,
		})
	end
	listCache[characterId] = out
	return out
end

-- Trials -----------------------------------------------------------------------------------------------------------

export type Trial = typeof(setmetatable({} :: {
	characterId: string, index: number, info: Info?, total: number, state: string, step: number, reason: string?,
	damage: number, idle: number, pending: number?, hit: boolean, prevMove: string?, prevMoveFrame: number,
	prevStance: string?, plainMoves: { [number]: string? },
}, ComboTrial))

function ComboTrial.new(characterId: string, index: number): Trial
	local info = ComboTrial.list(characterId)[index]
	local self = setmetatable({
		characterId = characterId, index = index, info = info, total = if info then #info.steps else 0,
		state = "Ready", step = 0, reason = nil, damage = 0, idle = 0, pending = nil, hit = false,
		prevMove = nil, prevMoveFrame = 0, prevStance = nil, plainMoves = {},
	}, ComboTrial)
	-- For each string follow-up step: the plain move the same button gives once the string window is closed (a late
	-- press of a string follow-up starts this move instead).
	if info and Roster.has(characterId) then
		local c = Roster.get(characterId)
		for k, step in info.steps do
			local def = c.moves[step.move]
			if def and def.chainFrom ~= nil then self.plainMoves[k] = byNotation(c, step.notation) end
		end
	end
	return self
end

function ComboTrial.status(self: Trial): Status
	return { state = self.state, step = self.step, total = self.total, reason = self.reason, damage = self.damage }
end

function ComboTrial.reset(self: Trial)
	self.state = "Ready"; self.step = 0; self.reason = nil; self.damage = 0; self.idle = 0; self.pending = nil; self.hit = false
end

local function begin(self: Trial, damage: number, hit: boolean)
	self.state = "Running"; self.step = 1; self.reason = nil; self.damage = damage; self.idle = 0; self.pending = nil
	self.hit = hit
	if self.step >= self.total then self.state = "Success" end
end

local function fail(self: Trial, reason: string)
	self.state = "Failed"; self.reason = reason; self.pending = nil
end

local function advanceStep(self: Trial, damage: number, hit: boolean)
	self.step += 1
	self.damage += damage
	self.idle = 0
	self.pending = nil
	if hit then self.hit = true end
	if self.step >= self.total then self.state = "Success" end
end

-- The dummy is still inside the combo: in hitstun, juggled (not yet falling into its knockdown) or in a cinematic.
local function inCombo(d: { [string]: any }): boolean
	local state = d.state
	if state == "Hitstun" or state == "Stagger" or state == "Ultimate" then return true end
	if state == "Airborne" then return d.knockdown == nil end
	return false
end

local function whiffReason(dummy: { [string]: any }, broken: boolean): string
	if broken then return "Late" end
	local pos = dummy.pos
	if dummy.state == "Airborne" and typeof(pos) == "Vector3" and pos.Y > AIR_CEILING - 0.2 then return "Early" end
	return "Whiffed"
end

function ComboTrial.feed(self: Trial, entry: any): Status
	local info = self.info
	if info == nil or typeof(entry) ~= "table" or typeof(entry.fighters) ~= "table" then return self:status() end
	local me, dummy = entry.fighters[1], entry.fighters[2]
	if typeof(me) ~= "table" or typeof(dummy) ~= "table" then return self:status() end
	if me.characterId ~= nil and me.characterId ~= self.characterId then return self:status() end
	local steps = info.steps
	local counterOpener = info.counter
	local events = if typeof(entry.events) == "table" then entry.events else {}
	local hitstop = typeof(entry.hitstop) == "number" and entry.hitstop > 0

	-- A move that started on this frame (string follow-ups change the key; a repeated move restarts its frame count).
	local started: string? = nil
	local moveFrame = if typeof(me.moveFrame) == "number" then me.moveFrame else 0
	if me.move ~= nil and (me.move ~= self.prevMove or moveFrame < self.prevMoveFrame) then started = me.move end
	self.prevMove = me.move
	self.prevMoveFrame = moveFrame
	local stanceNow = if me.state == "Stance" then me.stance else nil
	local enteredStance = stanceNow ~= nil and stanceNow ~= self.prevStance
	self.prevStance = stanceNow

	local function opener(e: any): boolean
		return e.attacker == 1 and e.target == 2 and HIT_KINDS[e.kind] == true and e.move == steps[1].move and (not counterOpener or e.counter == true)
	end

	for _, e in events do
		if typeof(e) ~= "table" then continue end
		if self.state == "Running" then
			local expected = steps[self.step + 1]
			local broken = self.pending ~= nil
			if e.attacker == 1 and e.target == 2 then
				if HIT_KINDS[e.kind] then
					if e.move == expected.move then
						-- The first hit of a route that opened with a stance entry starts the combo; later hits must keep it.
						if not self.hit or (e.combo or 0) > 1 or e.air == true then advanceStep(self, e.damage or 0, true) else fail(self, "Late") end
					else
						fail(self, "Wrong")
					end
				elseif e.kind == "UltHit" then
					if expected.move == "Ultimate" then advanceStep(self, e.damage or 0, true) else fail(self, "Wrong") end
				elseif e.kind == "Block" or e.kind == "Armor" then
					fail(self, "Blocked")
				elseif e.kind == "Whiff" then
					if e.move == expected.move then fail(self, whiffReason(dummy, broken)) else fail(self, "Wrong") end
				elseif e.kind == "ThrowStart" or e.kind == "ThrowHit" then
					fail(self, "Wrong")
				end
			elseif e.attacker == 2 and e.target == 1 and (e.kind == "Parry" or e.kind == "Crush" or e.kind == "Catch") then
				fail(self, "Blocked")
			end
		elseif self.state == "Success" then
			if e.attacker == 1 and e.target == 2 and e.kind == "UltHit" then
				self.damage += e.damage or 0
			elseif opener(e) then
				begin(self, e.damage or 0, true)
			end
		elseif opener(e) then
			-- Ready, or a new attempt after Failed.
			begin(self, e.damage or 0, true)
		end
	end

	-- A "3+4" stance entry as the first step starts the trial once the fighter is in that stance.
	if self.state ~= "Running" and enteredStance and steps[1].stance ~= nil and stanceNow == steps[1].stance then
		begin(self, 0, false)
		return self:status()
	end

	if self.state == "Running" then
		local k = self.step + 1
		local expected = steps[k]
		if expected.stance ~= nil and stanceNow == expected.stance and enteredStance then
			advanceStep(self, 0, false)
		elseif started ~= nil and started ~= expected.move then
			if self.plainMoves[k] ~= nil and started == self.plainMoves[k] then fail(self, "Late") else fail(self, "Wrong") end
		end
	end

	if self.state == "Running" and not hitstop then
		self.idle += 1
		local expected = steps[self.step + 1]
		-- Before the first hit (a route opened by a stance entry) the trial lasts while the stance does; after it,
		-- while the dummy stays in the combo.
		local alive = if self.hit then inCombo(dummy) else (stanceNow ~= nil or me.move ~= nil)
		if alive then
			self.pending = nil
		else
			self.pending = (self.pending or 0) + 1
			if (self.pending :: number) > GRACE then
				if me.move ~= nil and me.move == expected.move then
					-- The right move is on its way: its whiff / block / late hit names the reason; once it is over: late.
					if me.state == "Recovery" then fail(self, "Late") end
				elseif me.move ~= nil then
					fail(self, "Wrong")
				else
					fail(self, "Dropped")
				end
			end
		end
		if self.state == "Running" and self.idle > IDLE_LIMIT then fail(self, "Dropped") end
	end
	return self:status()
end

-- Demo -------------------------------------------------------------------------------------------------------------

-- Frames the demo stands still after walking in (well past the double-tap window, so the next forward press never
-- turns into a dash).
local SETTLE = 20

function ComboTrial.demo(characterId: string, index: number): { DemoEntry }
	local out: { DemoEntry } = {}
	if not Roster.has(characterId) then return out end
	local c = Roster.get(characterId)
	local combo = c.combos[index]
	if not combo then return out end
	local Sim = require(script.Parent.CombatSim) :: any
	local m = Sim.newMatch("Training", characterId, characterId)
	local a, d = m.fighters[1], m.fighters[2]
	local function distance(): number
		local v = d.pos - a.pos
		return math.sqrt(v.X * v.X + v.Z * v.Z)
	end
	local frame = 0
	local target = combo.distance or 3.0
	local held = { x = 0, crouch = false }
	-- Entries are kept in order (several can share a frame: apply them in order).
	local function hold(x: number, crouch: boolean)
		if x == held.x and crouch == held.crouch then return end
		local changedX = x ~= held.x
		held.x, held.crouch = x, crouch
		table.insert(out, { frame = frame, hold = { moveX = x, moveZ = 0, crouch = crouch } })
		if changedX then Sim.setMovement(m, 1, x, 0) end
		a.input.crouch = crouch
	end
	if distance() > target + 0.05 then
		hold(1, false)
		while distance() > target + 0.05 and frame < 600 do Sim.step(m); frame += 1 end
		hold(0, false)
	end
	for _ = 1, SETTLE do Sim.step(m); frame += 1 end
	-- The route with its own timing, exactly as Sim.comboTick plays it: a step is pressed `wait` frames without
	-- hitstop after the previous press, holding its direction on that frame; the direction is let go on the next one.
	-- Counter routes are timed on a counter-hit opener (the dummy's jab is started under it, as CombatCombo_Test does):
	-- the counter hit's longer hitstop shifts every later press.
	local pos = 1
	local wait = combo.steps[1].wait
	local release = false
	local guard = 0
	local counterAt: number? = nil
	while guard < 3000 do
		guard += 1
		if counterAt == frame then Sim.queueAttack(d, d.character.moveOrder[1]) end
		if m.hitstop == 0 then
			if release then
				release = false
				hold(0, false)
			end
			local step = combo.steps[pos]
			if step == nil then break end
			if wait > 0 then
				wait -= 1
			else
				local x, crouch, button = parse(step.input)
				hold(x, crouch)
				table.insert(out, { frame = frame, press = button, step = pos, notation = step.input })
				local key = Sim.press(m, 1, button)
				if pos == 1 and combo.counter and key then counterAt = frame + c.moves[key].startup - 7 end
				release = true
				pos += 1
				local nextStep = combo.steps[pos]
				wait = if nextStep then math.max(0, nextStep.wait - 1) else 0
			end
		end
		Sim.step(m)
		frame += 1
	end
	return out
end

return ComboTrial
