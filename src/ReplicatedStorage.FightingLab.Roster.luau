--!strict
-- FightingLab roster (OV6): ORIGINAL characters and move sets. Shared by server (CombatSim, CombatAI) and client
-- (motion, UI). Pure data plus accessors; no side effects.
--
-- Move fields (frames at 60 Hz):
--   input      internal command notation: LP/RP/LK/RK = buttons 1/2/3/4, "LP+LK" = 1+3 chord, prefixes f/b/d/df/db/ss/dash,
--              strings as "LP, RP" (the last token is the button pressed for that hit).
--   notation   display notation with button numbers ("1,2", "df+2", "1+3").
--   startup    frames before the first active frame (first active frame = startup + 1).
--   range      reach from the attacker's body centre along its facing; advance = studs the attacker travels forward
--              during startup (root motion), so the threat range from the starting position is range + advance.
--   width      half-width of the hit lane (studs); track = degrees per frame the attacker turns toward the opponent
--              during startup (0 = linear, sidestep beats it); homing = keeps turning through the active frames.
--   smid       special mid: blocked by standing AND crouching guard.
--   onBlock/onHit/onCounter: frame advantage (number) or "KND" (knockdown) / "LAUNCH" (juggle state).
--   intent     animation intent for the motion agents (limb, stance, height, motion).
-- Round 6 (docs/design/movesets.md):
--   stance       this move is a follow-up performed from that stance (input prefix = the stance tag, e.g. "PKT+LP").
--   toStance     pressing this input puts the fighter into that stance (the 3+4 signature entries; no hitbox).
--   stanceCancel this move's recovery can be cancelled into that stance by pressing the stance entry (3+4).
--   tumble       a hit on an airborne opponent spins them (tumble) so one more juggle hit connects; once per combo.
--   noHit        the move never strikes (parries, the catch, stance entries).
--   delay        string follow-up: extra frames it can be input late (a delayed hit starts on the press).
--   cinematic    the Ultimate's timeline (CONTRACTS-v6.md, Surge and Ultimate).
export type AnimHint = { archetype: string, side: string?, height: string?, crouch: boolean?, spin: number?, hop: number?, lunge: number?, stance: boolean? }
export type Parry = { window: { number }, heights: { string }, stagger: number }
export type Catch = { window: { number }, heights: { string }, throw: string }
export type Props = { highCrush: { number }?, lowCrush: { number }?, armor: { number }?, armorMulti: boolean?, parry: Parry?, catch: Catch? }
export type Impact = { frame: number, share: number }
export type Cinematic = { duration: number, impacts: { Impact }, endKind: string, endDistance: number, beats: { string }? }
export type MoveDef = {
	key: string, name: string, input: string, notation: string, chainFrom: string?, startup: number, impact: number, active: number, recovery: number,
	damage: number, height: string, range: number, width: number, push: number, advance: number, track: number, homing: boolean,
	smid: boolean, crouching: boolean, onBlock: number, onHit: number | string, onCounter: (number | string)?, tier: string, limb: string,
	props: Props, anim: AnimHint, intent: string, tags: { [string]: boolean },
	breakWindow: number?, duration: number?, impactFrame: number?, breakButton: string?,
	stance: string?, toStance: string?, stanceCancel: string?, tumble: boolean, noHit: boolean, delay: number?, cinematic: Cinematic?,
}
-- A signature stance (state "Stance" in the sim and the snapshot, with `stance` = key and `stanceFrame` 1..maxFrames).
--   tag         input prefix of its follow-ups ("PKT+LP" = 1 while in Pocket); notation shows it ("PKT+1").
--   cancelFrom  first stanceFrame a follow-up (or any button) can start; earlier presses are buffered.
--   backExit    holding back from this stanceFrame ends the stance into a standing guard (nil = cannot).
--   maxFrames   the stance ends on its own after this many frames (into Idle, guarding).
--   travel      studs it moves forward over the first `travelFrames` frames (ease-out); drift = studs per frame after.
--   guard       "Stand" = guards highs and mids while held; nil = no guard (hits in it are counter hits if counterHit).
--   props       highCrush / lowCrush / parry windows in stanceFrame.
export type StanceDef = {
	key: string, name: string, tag: string, entryFrames: number, cancelFrom: number, backExit: number?, maxFrames: number,
	travel: number, travelFrames: number, drift: number, guard: string?, counterHit: boolean, props: Props, intent: string,
	entryIntent: string, exitIntent: string,
}
export type Signature = { kind: string, key: string, name: string, summary: string }
-- A combo route (data for the move list, the CPU and CombatCombo_Test). steps[i].wait = frames since the previous
-- press while the sim is not in hitstop (the first wait is 0); input uses display notation with the stance tags
-- ("df+2", "PKT+2", "3+4", "1+2"). damage = expected total vs a standing 100 HP dummy (Surge multiplier included
-- when surge = true: the attacker is in Surge, as an Ultimate ender needs); counter = the opener is a counter hit.
-- kind: "launch" (bread and butter), "stance" (signature route), "counter", "low", "max" (max damage), "ultimate".
export type ComboStep = { wait: number, input: string }
export type ComboDef = {
	name: string, notation: string, kind: string, damage: number, difficulty: number, surge: boolean?, counter: boolean?,
	steps: { ComboStep }, distance: number?,
}
export type Stats = {
	maxHealth: number, walkSpeed: number, backSpeed: number, sideSpeed: number, dashSpeed: number, dashDistance: number,
	dashFrames: number, backdashDistance: number, backdashFrames: number, sidestepArc: number, weight: number, height: number,
	preferredRange: number,
}
export type CharacterDef = {
	id: string, displayName: string, style: string, stanceStyle: string, tagline: string, intro: string, victory: { string }, stats: Stats, look: string,
	primaryColor: Color3, accentColor: Color3, moves: { [string]: MoveDef }, moveOrder: { string },
	identity: string, signature: Signature, stances: { [string]: StanceDef }, combos: { ComboDef },
}
export type StageDef = { id: string, displayName: string }

local Roster = {}
Roster.FPS = 60

local function move(m: { [string]: any }): MoveDef
	-- Data below is written with genre impact frames ("i10" = the 10th frame is the first active frame); the sim
	-- counts `startup` frames BEFORE the first active frame, so startup = impact - 1.
	m.impact = m.startup
	m.startup = m.startup - 1
	m.width = m.width or 1.3
	m.push = m.push or 0.5
	m.advance = m.advance or 0
	m.track = m.track or 0
	m.homing = m.homing == true
	m.smid = m.smid == true
	m.crouching = m.crouching == true
	m.tumble = m.tumble == true
	m.noHit = m.noHit == true
	m.props = m.props or {}
	m.intent = m.intent or ""
	m.notation = m.notation or m.input
	if m.homing and m.track < 8 then m.track = 10 end
	local tags: { [string]: boolean } = {}
	if m.height == "Throw" then tags.throw = true
	else
		if m.chainFrom then tags.followup = true end
		if m.onHit == "LAUNCH" then tags.launcher = true end
		if m.onCounter == "LAUNCH" then tags.counterLauncher = true end
		if m.height == "Low" then tags.low = true end
		if m.height == "Mid" then tags.mid = true end
		if m.height == "High" then tags.high = true end
		if m.homing or m.track >= 2.5 then tags.tracking = true end
		if m.homing then tags.homing = true end
		if m.props.parry then tags.parry = true end
		if m.props.catch then tags.catch = true end
		if m.tumble then tags.tumble = true end
		if m.stance then tags.stanceMove = true end
		if m.toStance then tags.stanceEntry = true end
		if m.cinematic then tags.ultimate = true end
		if m.startup <= 11 and not m.chainFrom and not m.noHit then tags.poke = true end
		if m.onHit == "KND" or m.damage >= 15 or m.props.armor then tags.power = true end
	end
	if m.toStance or m.props.catch or m.props.parry or m.cinematic then tags.signature = true end
	m.tags = tags
	return (m :: any) :: MoveDef
end

local function stats(s: { [string]: number }): Stats
	s.sideSpeed = s.sidestepArc / 16 * 60
	s.dashSpeed = s.dashDistance / s.dashFrames * 60
	return (s :: any) :: Stats
end

local function stanceDef(s: { [string]: any }): StanceDef
	s.backExit = s.backExit
	s.travel = s.travel or 0
	s.travelFrames = s.travelFrames or 1
	s.drift = s.drift or 0
	s.counterHit = s.counterHit ~= false
	s.props = s.props or {}
	s.entryIntent = s.entryIntent or ""
	s.exitIntent = s.exitIntent or ""
	assert(s.cancelFrom >= 1 and s.cancelFrom <= s.maxFrames, "stance " .. s.key .. " cancel frame")
	assert(not string.find(s.tag, "[LR][PK]"), "stance tag must not contain a button name")
	return (s :: any) :: StanceDef
end

-- The Ultimate (CONTRACTS-v6.md, Surge and Ultimate): input 1+2, armor through startup (absorbs every strike; throws
-- beat it), launch-punishable on block, total damage spread over the cinematic impacts.
local function ultimate(m: { [string]: any }): { [string]: any }
	m.key = "Ultimate"
	m.input = "LP+RP"
	m.notation = "1+2"
	m.height = "Mid"
	m.tier = "Heavy"
	m.onHit = "KND"
	m.width = m.width or 1.6
	m.push = 0
	m.props = { armor = { 1, m.startup - 1 }, armorMulti = true }
	local total = 0
	local last = 0
	for _, impact in m.cinematic.impacts do
		assert(impact.frame > last and impact.frame < m.cinematic.duration, "Ultimate impacts are ordered inside the cinematic")
		last = impact.frame
		total += impact.share
	end
	assert(math.abs(total - 1) < 1e-6, "Ultimate impact shares sum to 1")
	assert(#m.cinematic.impacts >= 4 and #m.cinematic.impacts <= 6, "Ultimate has 4-6 impacts")
	return m
end

local characters: { [string]: CharacterDef } = {}
local function define(c: { [string]: any }, list: { { [string]: any } }, extra: { [string]: any }?)
	local moves: { [string]: MoveDef } = {}
	local order: { string } = {}
	for _, m in list do
		local def = move(m)
		assert(moves[def.key] == nil, "duplicate move " .. def.key)
		moves[def.key] = def
		table.insert(order, def.key)
	end
	local x = extra or {}
	local stances: { [string]: StanceDef } = {}
	for _, s in x.stances or {} do stances[s.key] = stanceDef(s) end
	for _, key in order do
		local def = moves[key]
		if def.stance then assert(stances[def.stance] ~= nil, c.id .. "." .. key .. " stance") end
		if def.toStance then assert(stances[def.toStance] ~= nil, c.id .. "." .. key .. " toStance") end
		if def.stanceCancel then assert(stances[def.stanceCancel] ~= nil, c.id .. "." .. key .. " stanceCancel") end
		if def.chainFrom then assert(moves[def.chainFrom] ~= nil, c.id .. "." .. key .. " chainFrom") end
		if def.props.catch then assert(moves[def.props.catch.throw] ~= nil and moves[def.props.catch.throw].height == "Throw", c.id .. "." .. key .. " catch throw") end
	end
	assert(moves.Ultimate ~= nil and order[#order] == "Ultimate", c.id .. " ends its move order with the Ultimate")
	c.moves = moves
	c.moveOrder = order
	c.stances = stances
	c.combos = x.combos or {}
	for _, combo in c.combos do
		assert(#combo.steps >= 2 and combo.steps[1].wait == 0, c.id .. " combo " .. combo.name .. " steps")
		assert(combo.kind ~= "ultimate" or combo.steps[#combo.steps].input == "1+2", c.id .. " combo " .. combo.name .. " ends in the Ultimate")
	end
	c.signature = x.signature
	characters[c.id] = (c :: any) :: CharacterDef
end

-- KAEL: street boxer. Fast hands, punch strings, pressure; few but honest kicks. Signature: POCKET (3+4), a low
-- bob-and-roll crouch that slips under high punches and fires body shovels and an uppercut launcher.
define({
	id = "Kael", displayName = "KAEL", style = "Street boxing / pressure", stanceStyle = "boxer",
	identity = "Relentless boxer: fast hands, body hooks and +1 pressure from the Pocket, where high punches sail over him.",
	tagline = "Pressure-forged striker with calm, heavy hands", intro = "Keep your guard up. It won't help.",
	victory = { "That's how the street keeps score.", "Stay down. You earned the rest." },
	stats = stats({ maxHealth = 100, walkSpeed = 5.0, backSpeed = 4.0, dashDistance = 3.0, dashFrames = 14, backdashDistance = 3.0, backdashFrames = 18, sidestepArc = 1.8, weight = 1.0, height = 5.95, preferredRange = 3.6 }),
	look = "Adult man, athletic boxer build, medium-olive skin, tight black cornrows down to the nape; slate heather sleeveless training hoodie with white trim, red satin boxing trunks, burnt-orange leather boxing gloves, sleek black leather high-top boxing boots.",
	primaryColor = Color3.fromRGB(32, 36, 44), accentColor = Color3.fromRGB(238, 105, 48),
}, {
	{ key = "Jab", name = "Jab", input = "LP", notation = "1", startup = 10, active = 2, recovery = 12, damage = 6, height = "High", range = 4.2, width = 1.2, track = 1.5, push = 0.4, onBlock = 1, onHit = 8, tier = "Light", limb = "LeadArm", anim = { archetype = "straight", side = "Lead", height = "High" },
		intent = "Lead-hand jab from a tight high boxing guard: small step of the lead foot, lead shoulder rolls over the chin, fist snaps straight to head height and back to the cheek; rear hand stays glued to the jaw." },
	{ key = "OneTwo", name = "One-Two", input = "LP, RP", notation = "1,2", chainFrom = "Jab", stanceCancel = "Pocket", startup = 10, active = 2, recovery = 14, damage = 8, height = "High", range = 3.95, width = 1.2, track = 1.5, advance = 0.65, push = 0.5, onBlock = -2, onHit = 6, tier = "Light", limb = "RearArm", anim = { archetype = "straight", side = "Rear", height = "High" },
		intent = "Rear straight right thrown as the jab returns: rear heel pivots out, hips and shoulders rotate fully, fist extends to head height, weight finishes over the lead knee." },
	{ key = "LiverHook", name = "Lead Liver Hook", input = "LP, RP, LP", notation = "1,2,1", chainFrom = "OneTwo", startup = 14, active = 3, recovery = 20, damage = 12, height = "Mid", range = 3.9, width = 1.8, track = 3, advance = 0.3, push = 0.9, onBlock = -9, onHit = 3, tier = "Medium", limb = "LeadArm", anim = { archetype = "body_hook", side = "Lead", height = "Mid" },
		intent = "Short lead hook to the opponent's right side (liver): level change by bending both knees, lead elbow bent ninety degrees, torso whips from the hips, fist lands at rib height." },
	{ key = "OneTwoShin", name = "One-Two Shin Kick", input = "LP, RP, LK", notation = "1,2,3", chainFrom = "OneTwo", startup = 15, active = 2, recovery = 21, damage = 9, height = "Low", range = 3.95, width = 1.3, track = 1, advance = 0.3, push = 0.3, onBlock = -13, onHit = 1, tier = "Medium", limb = "LeadLeg", anim = { archetype = "low_kick", side = "Lead", height = "Low" },
		intent = "Low ender of the one-two: as the right straight returns, the boxer drops his weight a little and snaps a lead-leg toe kick into the shin, foot skimming the floor, both gloves stay high at the chin; the kick returns straight to stance (same base as 1,2,1: mid hook or low kick)." },
	{ key = "Cross", name = "Straight Right", input = "RP", notation = "2", stanceCancel = "Pocket", startup = 11, active = 2, recovery = 14, damage = 9, height = "High", range = 3.6, width = 1.2, track = 1.5, advance = 1.0, push = 0.5, onBlock = -3, onHit = 5, tier = "Light", limb = "RearArm", anim = { archetype = "straight", side = "Rear", height = "High" },
		intent = "Rear straight right from the guard without the jab: rear foot pivots, hip and shoulder drive through, fist extends at chin height, lead hand covers the face." },
	{ key = "CrossHook", name = "Right Into Body Hook", input = "RP, LP", notation = "2,1", chainFrom = "Cross", startup = 13, active = 3, recovery = 18, damage = 11, height = "Mid", range = 3.9, width = 1.8, track = 3, advance = 0.2, push = 0.8, onBlock = -8, onHit = 3, tier = "Medium", limb = "LeadArm", anim = { archetype = "body_hook", side = "Lead", height = "Mid" },
		intent = "After the straight right, the boxer dips slightly and rips a lead hook to the body: weight shifts onto the lead leg, lead hip turns in, forearm horizontal at stomach height." },
	{ key = "HookOverhand", name = "Body Hook Into Overhand", input = "RP, LP, RP", notation = "2,1,2", chainFrom = "CrossHook", startup = 16, active = 3, recovery = 22, damage = 14, height = "High", range = 3.7, width = 1.6, track = 2, advance = 0.5, push = 1.0, onBlock = -11, onHit = "KND", tier = "Heavy", limb = "RearArm", anim = { archetype = "overhand", side = "Rear", height = "High" },
		intent = "High ender of 2,1: out of the body hook the boxer rises and loops the right hand over the top onto the temple, rear heel lifts, shoulders roll through and the punch drives down and across; the opponent spins to the floor (knockdown). Body-then-head: the hook lowers the guard, the overhand finishes high." },
	{ key = "Overhand", name = "Overhand Right", input = "f+RP", notation = "f+2", startup = 16, active = 3, recovery = 18, damage = 15, height = "High", range = 3.6, width = 1.6, track = 2, advance = 1.4, push = 1.0, onBlock = -5, onHit = 6, onCounter = "KND", tier = "Heavy", limb = "RearArm", anim = { archetype = "overhand", side = "Rear", height = "High" },
		intent = "Looping overhand right: step in with the lead foot, rear arm arcs up and over the shoulder and comes down onto the head, upper body rolls forward and down to the left, rear heel lifts." },
	{ key = "BodyBlow", name = "Crouching Body Shot", input = "d+RP", notation = "d+2", stanceCancel = "Pocket", startup = 14, active = 3, recovery = 17, damage = 12, height = "Mid", range = 3.8, width = 1.4, track = 1.5, advance = 0.3, push = 0.8, crouching = true, onBlock = -6, onHit = 4, tier = "Medium", limb = "RearArm", anim = { archetype = "body_hook", side = "Rear", height = "Mid", crouch = true },
		intent = "From a deep crouch, rear shovel punch to the stomach: knees stay bent, rear shoulder dips, fist travels forward and slightly upward into the body, chin tucked behind the lead glove." },
	{ key = "RisingUppercut", name = "Rising Uppercut", input = "df+RP", notation = "df+2", startup = 15, active = 3, recovery = 22, damage = 14, height = "Mid", range = 3.9, width = 1.2, advance = 0.3, push = 0.6, props = { highCrush = { 1, 7 } }, onBlock = -14, onHit = "LAUNCH", tier = "Launch", limb = "RearArm", anim = { archetype = "uppercut", side = "Rear", height = "Mid", crouch = true },
		intent = "Rear uppercut rising from a crouch: legs explode upward, hips drive up and forward, rear fist travels vertically from waist to above the head, body ends fully extended on the toes." },
	{ key = "WeaveHook", name = "Weaving Hook", input = "b+RP", notation = "b+2", startup = 17, active = 3, recovery = 19, damage = 15, height = "High", range = 3.7, width = 2.4, homing = true, advance = 0.7, push = 0.9, props = { highCrush = { 4, 14 } }, onBlock = -9, onHit = 4, tier = "Heavy", limb = "LeadArm", anim = { archetype = "weave_hook", side = "Lead", height = "High" },
		intent = "Upper body weaves down and under (U-shaped bob) then comes up with a wide lead hook to the head; the hook sweeps horizontally and turns with the opponent (homing), head stays low until the punch fires." },
	{ key = "RibRoller", name = "Rib Roller", input = "b+LP", notation = "b+1", startup = 13, active = 3, recovery = 18, damage = 11, height = "Mid", range = 3.6, width = 1.8, track = 3, advance = 0.5, push = 0.6, tumble = true, onBlock = -6, onHit = 3, tier = "Medium", limb = "LeadArm", anim = { archetype = "body_hook", side = "Lead", height = "Mid" },
		intent = "Short stepping lead hook to the floating ribs: a half step back-and-in with the lead foot, knees bend, the lead elbow tucks to ninety degrees and the hook rolls UP and through the ribs, torso turning hard from the hips. TUMBLE: on an airborne opponent the upward roll of the hook spins the body over in the air (one more juggle hit connects)." },
	{ key = "ShinKick", name = "Shin Kick", input = "d+LK", notation = "d+3", startup = 12, active = 2, recovery = 20, damage = 7, height = "Low", range = 4.0, width = 1.3, track = 1, crouching = true, push = 0.3, onBlock = -12, onHit = 1, tier = "Light", limb = "LeadLeg", anim = { archetype = "low_kick", side = "Lead", height = "Low", crouch = true },
		intent = "Quick lead-leg toe kick to the shin from a half crouch: knee lifts slightly, foot snaps out low along the floor and returns, hands stay in the guard." },
	{ key = "LegKick", name = "Low Roundhouse", input = "d+RK", notation = "d+4", startup = 19, active = 3, recovery = 24, damage = 14, height = "Low", range = 3.8, width = 1.8, track = 2, advance = 0.6, push = 0.3, onBlock = -17, onHit = "KND", tier = "Heavy", limb = "RearLeg", anim = { archetype = "low_kick", side = "Rear", height = "Low" },
		intent = "Heavy rear-leg roundhouse to the thigh/calf: step out with the lead foot, hips turn over, shin swings down through the opponent's leg at knee height, arms swing for balance." },
	{ key = "FrontKick", name = "Push Kick", input = "LK", notation = "3", startup = 13, active = 3, recovery = 17, damage = 10, height = "Mid", range = 3.9, width = 1.3, advance = 1.1, push = 0.9, onBlock = -6, onHit = 3, tier = "Medium", limb = "LeadLeg", anim = { archetype = "front_kick", side = "Lead", height = "Mid" },
		intent = "Lead-leg push kick to the stomach: knee chambers to the chest, hips push forward, sole of the foot extends straight out, torso leans back slightly, foot returns to stance." },
	{ key = "Roundhouse", name = "Street Roundhouse", input = "RK", notation = "4", startup = 15, active = 3, recovery = 20, damage = 13, height = "High", range = 4.4, width = 2.2, track = 3, advance = 0.8, push = 0.8, onBlock = -8, onHit = 5, tier = "Medium", limb = "RearLeg", anim = { archetype = "roundhouse", side = "Rear", height = "High" },
		intent = "Rear-leg roundhouse to the head: lead foot pivots, hips rotate fully, shin whips around horizontally at head height, rear arm swings down for counterbalance." },
	{ key = "ChargingCross", name = "Charging Straight", input = "dash+RP", notation = "f,f+2", startup = 16, active = 3, recovery = 22, damage = 17, height = "Mid", range = 3.6, width = 1.3, advance = 2.2, push = 1.6, onBlock = -10, onHit = "KND", tier = "Heavy", limb = "RearArm", anim = { archetype = "straight", side = "Rear", height = "Mid", lunge = 1.2 },
		intent = "Out of a forward dash, a lunging rear straight to the chest: big step forward, whole body travels behind the punch, rear leg drags, the boxer ends stretched forward." },
	{ key = "Pocket", name = "Pocket", input = "LK+RK", notation = "3+4", toStance = "Pocket", noHit = true, startup = 6, active = 1, recovery = 1, damage = 0, height = "Mid", range = 2.6, width = 1.2, push = 0, onBlock = 0, onHit = 0, tier = "Light", limb = "Body", anim = { archetype = "parry", side = "Lead", height = "Mid", crouch = true, stance = true },
		intent = "SIGNATURE stance entry (no strike): the boxer bends both knees and drops his head below an imaginary high punch, chin tucked behind the lead shoulder, gloves glued to the cheeks, elbows covering the ribs; he settles into the Pocket (see the stance: a low bob-and-roll crouch)." },
	{ key = "PocketShovel", name = "Pocket Shovel", input = "PKT+LP", notation = "PKT+1", stance = "Pocket", startup = 12, active = 3, recovery = 15, damage = 11, height = "Mid", range = 3.5, width = 1.6, track = 3, advance = 0.6, push = 0.7, onBlock = 1, onHit = 7, tier = "Medium", limb = "LeadArm", anim = { archetype = "body_hook", side = "Lead", height = "Mid", crouch = true },
		intent = "From the Pocket crouch, a lead shovel hook (half hook, half uppercut) into the liver: the lead knee drives, the elbow stays tucked under the fist, the fist travels forward and slightly up into the side of the stomach while he stays low; he rises back into his guard. Plus on block: the pressure tool." },
	{ key = "PocketUppercut", name = "Pocket Uppercut", input = "PKT+RP", notation = "PKT+2", stance = "Pocket", startup = 14, active = 3, recovery = 24, damage = 13, height = "Mid", range = 3.6, width = 1.2, advance = 0.5, push = 0.6, onBlock = -14, onHit = "LAUNCH", tier = "Launch", limb = "RearArm", anim = { archetype = "uppercut", side = "Rear", height = "Mid", crouch = true },
		intent = "Out of the lowest point of the Pocket bob, the rear uppercut springs straight up: both legs extend explosively, the rear fist travels vertically from knee height through the chin to above the head, the body finishes tall on the toes; lifts the opponent into a juggle (launcher, very unsafe on block)." },
	{ key = "Throw", name = "Clinch Headbutt", input = "LP+LK", notation = "1+3", startup = 12, active = 2, recovery = 34, damage = 18, height = "Throw", range = 3.2, width = 1.4, breakWindow = 20, breakButton = "LeadPunch", duration = 46, impactFrame = 30, tier = "Heavy", limb = "Body", anim = { archetype = "clinch_strike" },
		intent = "Both hands grab the back of the opponent's neck (collar tie), pull the head down, two short knees to the body, then shove them away so they fall on their back." },
	{ key = "ThrowB", name = "Over-Under Toss", input = "RP+RK", notation = "2+4", startup = 12, active = 2, recovery = 34, damage = 19, height = "Throw", range = 3.2, width = 1.4, breakWindow = 20, breakButton = "RearPunch", duration = 48, impactFrame = 32, tier = "Heavy", limb = "Body", anim = { archetype = "hip_toss" },
		intent = "Over-under body lock: rear arm under the opponent's armpit, lead arm over the shoulder, then a hip lift and dump in front onto their back." },
	ultimate({ name = "Final Bell", startup = 18, active = 3, recovery = 30, damage = 32, range = 3.6, advance = 1.2, onBlock = -15, limb = "RearArm", anim = { archetype = "straight", side = "Rear", height = "Mid", lunge = 1.0 },
		cinematic = { duration = 200, impacts = { { frame = 30, share = 0.10 }, { frame = 62, share = 0.14 }, { frame = 94, share = 0.16 }, { frame = 128, share = 0.20 }, { frame = 176, share = 0.40 } }, endKind = "FaceDown", endDistance = 4.4,
			beats = {
				"f0 (the hit): an armored, lunging right straight to the sternum; the opponent folds forward and Kael steps in chest to chest, dipping into the Pocket.",
				"f30 impact 1: lead shovel hook to the liver; the defender doubles over to its right side, elbows drop.",
				"f62 impact 2: rear hook to the other side of the body; the defender's knees buckle and its hands fall from its face.",
				"f94 impact 3: lead uppercut through the guard; the defender's chin snaps up, torso straightens and it staggers half a step back.",
				"f128 impact 4: right straight to the jaw; the defender's head turns and it spins a quarter turn away, arms limp.",
				"f150-175: Kael plants, loads the overhand right high behind his ear (the camera holds on him).",
				"f176 impact 5 (the final bell): the overhand right comes over the top onto the temple and drives the defender face-first into the floor (FaceDown, 4.4 studs in front); Kael ends standing over it, gloves up, breathing.",
			} },
		intent = "ULTIMATE (Surge only, once per round) 'Final Bell': an armored lunging right straight opens it; on hit the cinematic plays the beats listed in movesets.md (shovel, body hook, uppercut, straight, then the overhand that drops the opponent face-down)." }),
}, {
	combos = {
		{ name = "Uppercut Bread", kind = "launch", notation = "df+2, 1, b+1, 2,1", damage = 32, difficulty = 2, steps = { { wait = 0, input = "df+2" }, { wait = 32, input = "1" }, { wait = 23, input = "b+1" }, { wait = 33, input = "2" }, { wait = 8, input = "1" } } },
		{ name = "Pocket Launch", kind = "stance", notation = "3+4, PKT+2, 1, b+1, 2,1", damage = 31, difficulty = 3, steps = { { wait = 0, input = "3+4" }, { wait = 1, input = "PKT+2" }, { wait = 38, input = "1" }, { wait = 23, input = "b+1" }, { wait = 33, input = "2" }, { wait = 8, input = "1" } } },
		{ name = "Counter Uppercut", kind = "max", notation = "CH df+2, 1, b+1, 2,1", damage = 36, difficulty = 3, counter = true, steps = { { wait = 0, input = "df+2" }, { wait = 32, input = "1" }, { wait = 23, input = "b+1" }, { wait = 33, input = "2" }, { wait = 8, input = "1" } } },
		{ name = "Final Bell Finish", kind = "ultimate", notation = "df+2, 1+2", damage = 37, difficulty = 2, surge = true, steps = { { wait = 0, input = "df+2" }, { wait = 32, input = "1+2" } } },
	},
	signature = { kind = "stance", key = "Pocket", name = "Pocket", summary = "3+4: a low bob-and-roll crouch. Highs sail over him the whole time; PKT+1 is a +1 body shovel, PKT+2 an uppercut launcher. Cancel 1,2 / 2 / d+2 into it; hold back to leave." },
	stances = {
		{ key = "Pocket", name = "Pocket", tag = "PKT", entryFrames = 6, cancelFrom = 6, backExit = 8, maxFrames = 40, drift = 0.025, counterHit = true, props = { highCrush = { 1, 40 } },
			entryIntent = "Knees bend fast and the head drops forward-down under the line of a high punch (6 frames).",
			intent = "Pocket loop: a low, coiled boxer's crouch with the head moving in a small side-to-side bob-and-roll (U-shape), chin behind the lead shoulder, gloves at the cheeks, elbows on the ribs; he creeps forward a little (0.025 studs/frame). Crushes highs the whole time; no guard (hits are counter hits).",
			exitIntent = "Rises back into the upright boxing guard (back to Idle).", },
	},
})

-- SIERRA: kickboxer. Range control with long kicks, teeps and clean angles. Signature: SOUTHPAW (3+4), a guarded
-- switch stance (lead leg swapped) with its own long kicks.
define({
	id = "Sierra", displayName = "SIERRA", style = "Kickboxing / range control", stanceStyle = "kickboxer",
	identity = "Range kickboxer: teeps and long kicks keep you out, elbows punish you inside, and Southpaw switches every angle.",
	tagline = "Precision kickboxer with clean angles and fast exits", intro = "Find your range. I already found mine.",
	victory = { "Angles beat anger every time.", "Clean work. Next." },
	stats = stats({ maxHealth = 95, walkSpeed = 5.4, backSpeed = 4.4, dashDistance = 3.3, dashFrames = 14, backdashDistance = 3.2, backdashFrames = 18, sidestepArc = 1.9, weight = 1.05, height = 5.85, preferredRange = 4.4 }),
	look = "Adult woman, lean kickboxer build, fair skin, platinum high ponytail with swept fringe; teal striped training tank over a black sports bra, deep-teal satin kickboxing trunks with black waistband, brown leather boxing gloves, barefoot.",
	primaryColor = Color3.fromRGB(34, 48, 58), accentColor = Color3.fromRGB(77, 219, 205),
}, {
	{ key = "Jab", name = "Range Jab", input = "LP", notation = "1", startup = 10, active = 2, recovery = 12, damage = 5, height = "High", range = 3.95, width = 1.2, track = 1.5, advance = 0.25, push = 0.4, onBlock = 1, onHit = 8, tier = "Light", limb = "LeadArm", anim = { archetype = "straight", side = "Lead", height = "High" },
		intent = "Long lead jab from a bladed kickboxing stance: lead foot slides forward, arm fully extends at head height, rear glove at the cheek, quick return." },
	{ key = "JabKick", name = "Jab Into Teep", input = "LP, LK", notation = "1,3", chainFrom = "Jab", stanceCancel = "Southpaw", startup = 14, active = 3, recovery = 18, damage = 11, height = "Mid", range = 3.75, width = 1.3, advance = 1.35, push = 1.0, onBlock = -7, onHit = 3, tier = "Medium", limb = "LeadLeg", anim = { archetype = "teep", side = "Lead", height = "Mid" },
		intent = "As the jab retracts, the lead knee lifts and the ball of the foot pushes straight into the stomach (teep); hips thrust forward, upper body leans back, arms stay high." },
	{ key = "JabTeepHigh", name = "Jab Teep Head Kick", input = "LP, LK, RK", notation = "1,3,4", chainFrom = "JabKick", startup = 16, active = 3, recovery = 21, damage = 13, height = "High", range = 4.6, width = 2.2, track = 3, advance = 0.4, push = 0.8, onBlock = -9, onHit = 5, tier = "Medium", limb = "RearLeg", anim = { archetype = "roundhouse", side = "Rear", height = "High" },
		intent = "High ender of 1,3: the teep foot lands forward and the rear leg whips a full roundhouse to the side of the head, hips turning over, rear arm swinging down for balance; she lands back in the bladed stance." },
	{ key = "JabTeepLow", name = "Jab Teep Calf Kick", input = "LP, LK, LK", notation = "1,3,3", chainFrom = "JabKick", startup = 15, active = 2, recovery = 20, damage = 9, height = "Low", range = 4.0, width = 1.4, track = 1.5, push = 0.3, onBlock = -12, onHit = 2, tier = "Medium", limb = "LeadLeg", anim = { archetype = "low_kick", side = "Lead", height = "Low" },
		intent = "Low ender of 1,3: the teep leg never touches down; it re-chambers and chops an inside low kick into the opponent's lead calf, shin turned over, hands high (same base as the head kick: high or low)." },
	{ key = "SlashElbow", name = "Slashing Elbow", input = "RP", notation = "2", startup = 12, active = 2, recovery = 15, damage = 11, height = "High", range = 3.2, width = 1.6, track = 2, advance = 0.6, push = 0.6, onBlock = -3, onHit = 5, tier = "Medium", limb = "RearArm", anim = { archetype = "elbow", side = "Rear", height = "High" },
		intent = "Muay Thai slashing elbow: a short step in, the rear elbow lifts to shoulder height and slices diagonally down and across the opponent's brow, forearm horizontal, lead glove covering the chin; the body turns behind it and she resets the guard." },
	{ key = "Cross", name = "Counter Cross", input = "b+RP", notation = "b+2", startup = 11, active = 2, recovery = 14, damage = 9, height = "High", range = 3.8, width = 1.2, track = 1.5, advance = 0.8, push = 0.5, onBlock = -3, onHit = 5, tier = "Light", limb = "RearArm", anim = { archetype = "straight", side = "Rear", height = "High" },
		intent = "Counter cross (the weight rocks back first, then the punch): rear heel turns out, hips rotate, arm extends straight to the head, lead hand drops to cover the chin, snaps back to the bladed guard." },
	{ key = "Teep", name = "Long Teep", input = "LK", notation = "3", stanceCancel = "Southpaw", startup = 13, active = 3, recovery = 17, damage = 11, height = "Mid", range = 3.8, width = 1.3, advance = 1.4, push = 1.4, onBlock = -5, onHit = 3, tier = "Medium", limb = "LeadLeg", anim = { archetype = "teep", side = "Lead", height = "Mid" },
		intent = "Lead-leg push kick at full length: knee chambers high, hips drive the sole of the foot into the belly, supporting foot rises onto the ball, arms hold a high guard." },
	{ key = "TeepKick", name = "Teep Into High Kick", input = "LK, RK", notation = "3,4", chainFrom = "Teep", startup = 16, active = 3, recovery = 20, damage = 12, height = "High", range = 5.2, width = 2.2, track = 3, advance = 0.3, push = 0.8, onBlock = -9, onHit = 4, tier = "Medium", limb = "RearLeg", anim = { archetype = "roundhouse", side = "Rear", height = "High" },
		intent = "The teep foot lands forward and the rear leg immediately whips a roundhouse to the head; full hip rotation, rear arm swings down, kick turns over at head height." },
	{ key = "TeepSpinKick", name = "Teep Kick Spin", input = "LK, RK, RK", notation = "3,4,4", chainFrom = "TeepKick", startup = 18, active = 3, recovery = 24, damage = 15, height = "Mid", range = 4.2, width = 1.4, advance = 0.8, push = 2.0, onBlock = -13, onHit = "KND", tier = "Heavy", limb = "RearLeg", anim = { archetype = "spinning_back_kick", side = "Rear", height = "Mid", spin = 0.5 },
		intent = "Mid ender of 3,4: the head kick's momentum carries her around; she lets the rear leg land, keeps turning her back to the opponent (head looking over the shoulder) and drives a spinning back kick heel-first into the stomach (knockdown)." },
	{ key = "HighRoundhouse", name = "Head Roundhouse", input = "RK", notation = "4", startup = 14, active = 3, recovery = 20, damage = 13, height = "High", range = 4.5, width = 2.2, track = 3, advance = 0.9, push = 0.8, onBlock = -8, onHit = 5, onCounter = "KND", tier = "Medium", limb = "RearLeg", anim = { archetype = "roundhouse", side = "Rear", height = "High" },
		intent = "Rear-leg roundhouse to the head (Muay Thai style): lead foot pivots on the ball, hips turn over completely, shin swings in a flat arc at head height, rear arm swings back." },
	{ key = "DoubleRoundhouse", name = "Double Roundhouse", input = "RK, RK", notation = "4,4", chainFrom = "HighRoundhouse", startup = 16, active = 3, recovery = 24, damage = 12, height = "Mid", range = 4.35, width = 2.2, track = 3, advance = 0.85, push = 1.2, onBlock = -12, onHit = "KND", tier = "Heavy", limb = "RearLeg", anim = { archetype = "roundhouse", side = "Rear", height = "Mid" },
		intent = "Without planting, the same rear leg chambers again and fires a second roundhouse to the ribs; supporting leg hops slightly to re-balance, arms counter-swing." },
	{ key = "SpinningBackKick", name = "Spinning Back Kick", input = "b+RK", notation = "b+4", startup = 17, active = 3, recovery = 22, damage = 17, height = "Mid", range = 4.25, width = 1.3, advance = 1.15, push = 2.2, onBlock = -8, onHit = "KND", tier = "Heavy", limb = "RearLeg", anim = { archetype = "spinning_back_kick", side = "Rear", height = "Mid", spin = 0.5 },
		intent = "Turn the back to the opponent (head looks over the shoulder), rear leg chambers and thrusts straight back heel-first into the stomach, then the body completes the turn back to stance." },
	{ key = "KneeStrike", name = "Driving Knee", input = "f+LK", notation = "f+3", startup = 14, active = 3, recovery = 17, damage = 13, height = "Mid", range = 2.8, width = 1.3, track = 1.5, advance = 1.6, push = 1.0, onBlock = -5, onHit = 5, onCounter = "LAUNCH", tier = "Medium", limb = "LeadLeg", anim = { archetype = "knee", side = "Lead", height = "Mid", lunge = 0.6 },
		intent = "Step in and drive the lead knee up into the body: hands reach forward as if pulling the opponent in, hips push forward, supporting heel lifts." },
	{ key = "SwitchKick", name = "Switch Lift Kick", input = "df+LK", notation = "df+3", startup = 15, active = 3, recovery = 22, damage = 13, height = "Mid", range = 2.8, width = 1.2, advance = 1.4, push = 0.6, onBlock = -13, onHit = "LAUNCH", tier = "Launch", limb = "LeadLeg", anim = { archetype = "rising_kick", side = "Lead", height = "Mid" },
		intent = "Quick stance switch (feet swap with a small hop), then the lead leg kicks straight up under the chin like a vertical front kick, toes pointing up, body leans back." },
	{ key = "LegKick", name = "Calf Kick", input = "d+RK", notation = "d+4", startup = 13, active = 2, recovery = 21, damage = 8, height = "Low", range = 4.0, width = 1.5, track = 1.5, push = 0.3, onBlock = -13, onHit = 1, tier = "Medium", limb = "RearLeg", anim = { archetype = "low_kick", side = "Rear", height = "Low" },
		intent = "Fast rear-leg calf kick: small hip turn, shin chops down onto the opponent's lead calf just below the knee, foot returns quickly, guard stays high." },
	{ key = "LowSweep", name = "Ground Sweep", input = "db+RK", notation = "db+4", startup = 20, active = 4, recovery = 26, damage = 15, height = "Low", range = 4.0, width = 2.4, track = 2, advance = 0.6, crouching = true, push = 0.3, onBlock = -18, onHit = "KND", tier = "Heavy", limb = "RearLeg", anim = { archetype = "sweep", side = "Rear", height = "Low", crouch = true, spin = 0.5 },
		intent = "Drop low onto the lead knee and hands, rear leg sweeps in a wide arc along the floor at ankle height, body spins with it and rises back to stance." },
	{ key = "DuckJab", name = "Crouch Jab", input = "d+LP", notation = "d+1", startup = 11, active = 2, recovery = 14, damage = 5, height = "Mid", smid = true, range = 3.8, width = 1.2, crouching = true, push = 0.4, onBlock = -4, onHit = 4, tier = "Light", limb = "LeadArm", anim = { archetype = "straight", side = "Lead", height = "Low", crouch = true },
		intent = "Short lead jab from a crouch, aimed at the stomach: knees stay bent, lead arm extends level, rear glove covers the face, stays crouched after." },
	{ key = "HopCross", name = "Hop Cross", input = "f+RP", notation = "f+2", startup = 17, active = 3, recovery = 18, damage = 15, height = "High", range = 3.7, width = 1.3, advance = 2.1, push = 1.0, props = { lowCrush = { 6, 15 } }, onBlock = -6, onHit = 6, tier = "Heavy", limb = "RearArm", anim = { archetype = "superman_punch", side = "Rear", height = "High", hop = 0.6, lunge = 1.0 },
		intent = "Fake a rear knee, push off it and hop forward, throwing the rear cross in mid-air while the leg kicks back for balance; lands on the lead foot (feet leave the floor = low crush)." },
	{ key = "AngleKick", name = "Angle Kick", input = "ss+LK", notation = "ss+3", startup = 15, active = 3, recovery = 18, damage = 12, height = "Mid", range = 3.25, width = 2.4, homing = true, advance = 1.75, push = 0.8, onBlock = -8, onHit = 4, tier = "Medium", limb = "LeadLeg", anim = { archetype = "roundhouse", side = "Lead", height = "Mid" },
		intent = "From a sidestep, a lead-leg roundhouse to the ribs that turns with the opponent; pivot on the rear foot, kick arcs horizontally at waist height." },
	{ key = "Southpaw", name = "Southpaw", input = "LK+RK", notation = "3+4", toStance = "Southpaw", noHit = true, startup = 5, active = 1, recovery = 1, damage = 0, height = "Mid", range = 2.6, width = 1.2, push = 0, onBlock = 0, onHit = 0, tier = "Light", limb = "Body", anim = { archetype = "parry", side = "Lead", height = "High", stance = true },
		intent = "SIGNATURE stance entry (no strike): a small hop-switch of the feet (the right leg becomes the lead leg, the left the rear), the guard mirrors (right glove forward), she lands light on the balls of the feet in a mirrored, bladed kickboxing stance (see the stance)." },
	{ key = "SouthpawHeadKick", name = "Southpaw Head Kick", input = "SPW+RK", notation = "SPW+4", stance = "Southpaw", startup = 13, active = 3, recovery = 19, damage = 13, height = "High", range = 4.6, width = 2.2, track = 3, advance = 0.5, push = 0.8, onBlock = -7, onHit = 6, tier = "Medium", limb = "RearLeg", anim = { archetype = "roundhouse", side = "Rear", height = "High" },
		intent = "From Southpaw the RIGHT leg is the lead: a fast lead-leg round kick to the head with almost no chamber, the hip flicks over, the foot snaps to the temple and back; long reach, quick return to the southpaw guard." },
	{ key = "SouthpawBodyKick", name = "Southpaw Body Kick", input = "SPW+LK", notation = "SPW+3", stance = "Southpaw", startup = 13, active = 3, recovery = 20, damage = 13, height = "Mid", range = 4.0, width = 2.2, track = 3, advance = 0.6, push = 1.0, tumble = true, onBlock = -8, onHit = 4, tier = "Medium", limb = "LeadLeg", anim = { archetype = "roundhouse", side = "Lead", height = "Mid" },
		intent = "From Southpaw the LEFT leg is the rear (power) leg: a full rear roundhouse into the liver, the right foot pivots, hips turn over completely and the shin lands flat on the ribs, left arm swings down. TUMBLE: on an airborne opponent the shin rolls the body over in the air." },
	{ key = "SouthpawLowKick", name = "Southpaw Low Kick", input = "SPW+d+RK", notation = "SPW+d+4", stance = "Southpaw", startup = 14, active = 2, recovery = 20, damage = 9, height = "Low", range = 4.0, width = 1.5, track = 1.5, push = 0.3, onBlock = -12, onHit = 2, tier = "Medium", limb = "RearLeg", anim = { archetype = "low_kick", side = "Rear", height = "Low" },
		intent = "From Southpaw (holding down), the right (now lead) leg chops a short low kick into the inside of the opponent's lead knee; hands stay high, she stays upright and bladed." },
	{ key = "Throw", name = "Clinch Knees", input = "LP+LK", notation = "1+3", startup = 12, active = 2, recovery = 34, damage = 17, height = "Throw", range = 3.2, width = 1.4, breakWindow = 20, breakButton = "LeadPunch", duration = 48, impactFrame = 34, tier = "Heavy", limb = "Body", anim = { archetype = "clinch_knees" },
		intent = "Double collar tie (both hands behind the head), pull down, two alternating knees to the chest, then twist and dump the opponent to the floor." },
	{ key = "ThrowB", name = "Clinch Trip", input = "RP+RK", notation = "2+4", startup = 12, active = 2, recovery = 34, damage = 18, height = "Throw", range = 3.2, width = 1.4, breakWindow = 20, breakButton = "RearPunch", duration = 46, impactFrame = 30, tier = "Heavy", limb = "Body", anim = { archetype = "arm_toss" },
		intent = "Underhook the arm, step across and sweep the opponent's lead leg with the rear leg while turning the shoulders; the opponent spins and lands on their back." },
	ultimate({ name = "Eight Limbs", startup = 20, active = 3, recovery = 28, damage = 33, range = 4.0, advance = 1.0, onBlock = -15, limb = "LeadLeg", anim = { archetype = "teep", side = "Lead", height = "Mid", lunge = 0.6 },
		cinematic = { duration = 230, impacts = { { frame = 34, share = 0.10 }, { frame = 70, share = 0.12 }, { frame = 104, share = 0.14 }, { frame = 140, share = 0.16 }, { frame = 196, share = 0.48 } }, endKind = "FaceUp", endDistance = 4.6,
			beats = {
				"f0 (the hit): an armored long teep into the stomach folds the opponent; Sierra steps in behind it.",
				"f34 impact 1: lead (left) body kick into the liver; the defender bends sideways toward the kick.",
				"f70 impact 2: she clinches (both hands behind the defender's head) and drives a rising knee into its chest; the defender's head is pulled down onto the knee.",
				"f104 impact 3: the second knee, to the chin; the defender's head snaps back up.",
				"f140 impact 4: she releases the clinch with a slashing horizontal elbow across the brow; the defender staggers back, turning away.",
				"f150-195: two quick steps back to kicking range, a hop-switch of the feet (Southpaw) and a breath.",
				"f196 impact 5: a full-power switch head kick; the defender is spun off its feet and lands on its back (FaceUp, 4.6 studs away). Sierra finishes in her bladed guard.",
			} },
		intent = "ULTIMATE (Surge only, once per round) 'Eight Limbs': an armored long teep opens it; on hit the cinematic plays the beats in movesets.md (body kick, clinch knees, elbow, switch head kick)." }),
}, {
	combos = {
		{ name = "Switch Teep", kind = "launch", notation = "df+3, 3, 3+4, SPW+3, 1,3", damage = 34, difficulty = 4, steps = { { wait = 0, input = "df+3" }, { wait = 32, input = "3" }, { wait = 15, input = "3+4" }, { wait = 8, input = "SPW+3" }, { wait = 32, input = "1" }, { wait = 8, input = "3" } } },
		{ name = "Counter Knee", kind = "counter", notation = "CH f+3, 1,3,4", damage = 32, difficulty = 2, counter = true, steps = { { wait = 0, input = "f+3" }, { wait = 26, input = "1" }, { wait = 8, input = "3" }, { wait = 11, input = "4" } } },
		{ name = "Knee To Southpaw", kind = "max", notation = "CH f+3, 1,3, 3+4, SPW+3, 2", damage = 36, difficulty = 4, counter = true, steps = { { wait = 0, input = "f+3" }, { wait = 26, input = "1" }, { wait = 8, input = "3" }, { wait = 19, input = "3+4" }, { wait = 8, input = "SPW+3" }, { wait = 32, input = "2" } } },
		{ name = "Eight Limbs Finish", kind = "ultimate", notation = "df+3, 1+2", damage = 37, difficulty = 2, surge = true, steps = { { wait = 0, input = "df+3" }, { wait = 32, input = "1+2" } } },
	},
	signature = { kind = "stance", key = "Southpaw", name = "Southpaw", summary = "3+4: switch the lead leg. Southpaw guards highs and mids while held; SPW+4 fast long head kick, SPW+3 power body kick (tumbles in juggles), SPW+d+4 low kick. Cancel 3 / 1,3 into it; 3+4 again or back to switch back." },
	stances = {
		{ key = "Southpaw", name = "Southpaw", tag = "SPW", entryFrames = 5, cancelFrom = 5, backExit = 8, maxFrames = 90, guard = "Stand", counterHit = false,
			entryIntent = "Quick hop-switch of the feet (5 frames): right leg forward, guard mirrored.",
			intent = "Southpaw loop: the mirrored kickboxing stance, right foot and right glove forward, light rhythmic bounce, standing guard up (blocks highs and mids). Stationary (no walking in it).",
			exitIntent = "Hop-switch back to the orthodox stance (left leg forward).", },
	},
})

-- GORAN: heavyweight grappler. Armored charges, big throws, slow but heavy strikes. Signature: BEAR TRAP (3+4), a
-- catch: a high or mid strike that touches him during the window is caught and answered with a belly suplex.
define({
	id = "Goran", displayName = "GORAN", style = "Heavyweight grappling / armored pressure", stanceStyle = "grappler",
	identity = "Armored heavyweight: walks through punches, catches strikes in the Bear Trap and turns every touch into a slam.",
	tagline = "Iron-grip powerhouse who walks through punches", intro = "Hit me. Then it's my turn.",
	victory = { "Mountains don't move.", "You were brave. That's all." },
	stats = stats({ maxHealth = 120, walkSpeed = 4.3, backSpeed = 3.5, dashDistance = 2.6, dashFrames = 15, backdashDistance = 2.6, backdashFrames = 19, sidestepArc = 1.5, weight = 0.85, height = 6.75, preferredRange = 3.2 }),
	look = "Adult man, very broad heavyweight build, tan skin, shaved head, trimmed light-brown full beard; deep-red ribbed muscle tank, grey camo fight shorts over black compression tights, black leather lifting belt, red wrist sweatbands, light-brown suede combat boots, open grappler hands.",
	primaryColor = Color3.fromRGB(40, 38, 36), accentColor = Color3.fromRGB(190, 40, 48),
}, {
	{ key = "Jab", name = "Heavy Jab", input = "LP", notation = "1", startup = 10, active = 2, recovery = 13, damage = 7, height = "High", range = 4.4, width = 1.3, track = 1.5, push = 0.5, onBlock = 1, onHit = 7, tier = "Light", limb = "LeadArm", anim = { archetype = "straight", side = "Lead", height = "High" },
		intent = "Heavy, short lead jab from a wide grappling stance with open-ish fist: shoulder pushes the punch, little footwork, the big torso leans in." },
	{ key = "JabHammer", name = "Jab Into Hammer", input = "LP, RP", notation = "1,2", chainFrom = "Jab", startup = 15, active = 3, recovery = 19, damage = 12, height = "Mid", range = 4.0, width = 1.4, track = 1.5, advance = 0.2, push = 0.9, onBlock = -9, onHit = 3, tier = "Medium", limb = "RearArm", anim = { archetype = "hammer_fist", side = "Rear", height = "Mid" },
		intent = "After the jab, the rear fist rises above the head and clubs straight down onto the collarbone (hammer fist); knees bend as the blow lands." },
	{ key = "JabHammerForearm", name = "Jab Hammer Forearm", input = "LP, RP, LP", notation = "1,2,1", chainFrom = "JabHammer", startup = 16, active = 3, recovery = 22, damage = 13, height = "High", range = 3.6, width = 2.0, track = 2.5, advance = 0.5, push = 1.2, onBlock = -10, onHit = "KND", tier = "Heavy", limb = "LeadArm", anim = { archetype = "elbow", side = "Lead", height = "High" },
		intent = "High ender of 1,2: from the hammer fist he steps through with the lead foot and swings the lead forearm horizontally into the side of the head (clubbing forearm smash, elbow bent ninety degrees, the whole torso turning behind it); the opponent is knocked down." },
	{ key = "JabHammerStomp", name = "Jab Hammer Stomp", input = "LP, RP, LK", notation = "1,2,3", chainFrom = "JabHammer", startup = 16, active = 3, recovery = 22, damage = 11, height = "Low", range = 3.8, width = 1.4, track = 1, advance = 0.4, push = 0.3, onBlock = -13, onHit = 1, tier = "Medium", limb = "LeadLeg", anim = { archetype = "stomp", side = "Lead", height = "Low" },
		intent = "Low ender of 1,2: after the hammer fist he lifts the lead knee high and stamps the boot heel down onto the opponent's lead foot and shin, arms still forward, whole body weight dropping onto it (same base as the forearm: high or low)." },
	{ key = "Hammer", name = "Hammer Fist", input = "RP", notation = "2", startup = 14, active = 3, recovery = 18, damage = 13, height = "Mid", range = 4.0, width = 1.4, track = 1.5, advance = 0.2, push = 0.9, onBlock = -5, onHit = 4, tier = "Medium", limb = "RearArm", anim = { archetype = "hammer_fist", side = "Rear", height = "Mid" },
		intent = "Rear arm swings up and over like an axe and the bottom of the fist smashes down onto the shoulder/chest; whole body drops with the strike." },
	{ key = "DoubleHammer", name = "Double Hammer", input = "RP, RP", notation = "2,2", chainFrom = "Hammer", startup = 17, active = 3, recovery = 24, damage = 14, height = "Mid", range = 4.0, width = 1.5, track = 1.5, advance = 0.3, push = 1.6, onBlock = -13, onHit = "KND", tier = "Heavy", limb = "LeadArm", anim = { archetype = "hammer_fist", side = "Lead", height = "Mid" },
		intent = "The lead arm follows with a second overhead hammer fist, both shoulders driving down, a step forward into it that flattens the opponent." },
	{ key = "ShoulderTackle", name = "Shoulder Charge", input = "f+RP", notation = "f+2", startup = 18, active = 4, recovery = 20, damage = 18, height = "Mid", range = 2.8, width = 1.5, track = 1, advance = 2.2, push = 2.0, props = { armor = { 6, 17 } }, onBlock = -10, onHit = "KND", tier = "Heavy", limb = "Body", anim = { archetype = "shoulder_tackle", side = "Lead", height = "Mid", lunge = 1.4 },
		intent = "Lowers the lead shoulder, tucks the chin and charges two steps forward, ramming the shoulder into the chest; absorbs one hit while charging (armor)." },
	{ key = "Uppercut", name = "Lifting Uppercut", input = "d+RP", notation = "d+2", startup = 16, active = 3, recovery = 24, damage = 15, height = "Mid", range = 3.9, width = 1.2, advance = 0.2, push = 0.6, props = { highCrush = { 1, 8 } }, onBlock = -15, onHit = "LAUNCH", tier = "Launch", limb = "RearArm", anim = { archetype = "uppercut", side = "Rear", height = "Mid", crouch = true },
		intent = "Squat down, then a huge rear uppercut lifts from the floor to above the head, legs and hips extending, lifting the opponent off their feet." },
	{ key = "KneeLift", name = "Knee Lift", input = "f+LK", notation = "f+3", startup = 14, active = 3, recovery = 18, damage = 13, height = "Mid", range = 2.8, width = 1.3, track = 1.5, advance = 1.2, push = 1.0, tumble = true, onBlock = -5, onHit = 5, tier = "Medium", limb = "LeadLeg", anim = { archetype = "knee", side = "Lead", height = "Mid" },
		intent = "Both hands reach out to grab, then the lead knee drives up into the stomach as the hands pull down; heavy forward step. TUMBLE: on an airborne opponent the knee drives up under the body and flips it over in the air." },
	{ key = "PushKick", name = "Boot Push", input = "LK", notation = "3", startup = 14, active = 3, recovery = 18, damage = 12, height = "Mid", range = 3.8, width = 1.3, advance = 1.2, push = 1.6, props = { armor = { 4, 13 } }, onBlock = -6, onHit = 3, tier = "Medium", limb = "LeadLeg", anim = { archetype = "teep", side = "Lead", height = "Mid" },
		intent = "Big flat-footed lead push kick with the boot sole into the belly, upper body leaning back, arms out wide for balance. Armored chamber: the raised knee absorbs one strike." },
	{ key = "BootForearm", name = "Boot Push Forearm", input = "LK, RP", notation = "3,2", chainFrom = "PushKick", startup = 15, active = 3, recovery = 18, damage = 12, height = "High", range = 3.6, width = 1.8, track = 2, advance = 0.6, push = 0.8, onBlock = -7, onHit = 4, tier = "Medium", limb = "RearArm", anim = { archetype = "elbow", side = "Rear", height = "High" },
		intent = "The push-kick foot lands forward and he swings the rear forearm across into the side of the head (forearm smash, elbow high and bent), shoulders turning heavily behind it." },
	{ key = "BootForearmHammer", name = "Boot Forearm Hammer", input = "LK, RP, RP", notation = "3,2,2", chainFrom = "BootForearm", startup = 20, active = 3, recovery = 24, damage = 17, height = "Mid", range = 3.8, width = 1.6, track = 1.5, advance = 0.4, push = 1.4, props = { armor = { 4, 19 } }, onBlock = -14, onHit = "KND", tier = "Heavy", limb = "RearArm", anim = { archetype = "hammer_fist", side = "Rear", height = "Mid" },
		intent = "Mid ender of 3,2: both fists lock together and rise high above his head (armored windup, he absorbs a hit while raising them), then the double-fisted club crashes down onto the collarbone and drives the opponent to the floor (knockdown)." },
	{ key = "ClubKick", name = "Club Kick", input = "RK", notation = "4", startup = 16, active = 3, recovery = 20, damage = 14, height = "Mid", range = 4.8, width = 2.2, track = 3, advance = 0.2, push = 1.0, onBlock = -8, onHit = 3, tier = "Medium", limb = "RearLeg", anim = { archetype = "roundhouse", side = "Rear", height = "Mid" },
		intent = "Heavy rear-leg body kick thrown like a club: less snap, more weight, hips turn over slowly and the shin lands on the ribs." },
	{ key = "Stomp", name = "Knee Stomp", input = "d+LK", notation = "d+3", startup = 14, active = 3, recovery = 20, damage = 9, height = "Low", range = 3.8, width = 1.3, track = 1, advance = 0.3, push = 0.3, onBlock = -12, onHit = 1, tier = "Medium", limb = "LeadLeg", anim = { archetype = "stomp", side = "Lead", height = "Low" },
		intent = "Lifts the lead knee and stamps the boot down and forward onto the opponent's lead knee/shin; arms stay forward." },
	{ key = "CrouchJab", name = "Low Poke", input = "db+LP", notation = "db+1", startup = 12, active = 2, recovery = 15, damage = 6, height = "Mid", smid = true, range = 3.6, width = 1.2, crouching = true, push = 0.5, onBlock = -5, onHit = 3, tier = "Light", limb = "LeadArm", anim = { archetype = "straight", side = "Lead", height = "Low", crouch = true },
		intent = "From a squat, a short stiff lead punch to the stomach; stays crouched, other hand forward." },
	{ key = "LegHook", name = "Leg Hook Sweep", input = "d+RK", notation = "d+4", startup = 21, active = 4, recovery = 24, damage = 16, height = "Low", range = 3.8, width = 2.2, track = 2, advance = 0.5, crouching = true, push = 0.3, onBlock = -17, onHit = "KND", tier = "Heavy", limb = "RearLeg", anim = { archetype = "sweep", side = "Rear", height = "Low", crouch = true },
		intent = "Drops onto the lead knee and hooks the rear leg around the opponent's ankles, reaping them off their feet; heavy body rotation." },
	{ key = "Haymaker", name = "Wide Haymaker", input = "b+RP", notation = "b+2", startup = 18, active = 3, recovery = 19, damage = 17, height = "High", range = 3.95, width = 2.6, homing = true, advance = 0.55, push = 1.0, onBlock = -9, onHit = 5, onCounter = "LAUNCH", tier = "Heavy", limb = "RearArm", anim = { archetype = "hook", side = "Rear", height = "High" },
		intent = "Huge looping rear hook to the head, wound up from behind the hip; the arc sweeps wide and follows a sidestepping opponent (homing). On a counter hit it lifts the opponent off its feet (counter-hit launcher)." },
	{ key = "Bulldozer", name = "Bulldozer", input = "dash+RP", notation = "f,f+2", startup = 20, active = 4, recovery = 22, damage = 22, height = "Mid", range = 2.8, width = 1.5, track = 1, advance = 3.0, push = 2.4, props = { armor = { 4, 19 } }, onBlock = -12, onHit = "KND", tier = "Heavy", limb = "Body", anim = { archetype = "shoulder_tackle", side = "Lead", height = "Mid", lunge = 2.0 },
		intent = "Out of a dash, a running double-handed shove/shoulder ram: three heavy running steps, arms forward, absorbs a hit (armor), and bowls the opponent over." },
	{ key = "BearTrap", name = "Bear Trap", input = "LK+RK", notation = "3+4", noHit = true, startup = 4, active = 21, recovery = 26, damage = 0, height = "Mid", range = 2.6, width = 1.6, push = 0, props = { catch = { window = { 4, 24 }, heights = { "High", "Mid" }, throw = "ThrowB" } }, onBlock = 0, onHit = 0, tier = "Heavy", limb = "Body", anim = { archetype = "parry", side = "Lead", height = "High" },
		intent = "SIGNATURE catch (no strike): he sinks his hips and opens both arms wide at chest height, palms forward, chin down, inviting the hit (frames 4-24). A high or mid strike that touches him is caught: his arms clamp around the striking arm or leg and the body, and he goes straight into the Belly Suplex (ThrowB, unbreakable). Lows and throws beat it; a whiffed trap leaves him open for a long time." },
	{ key = "Throw", name = "Bear Hug Toss", input = "LP+LK", notation = "1+3", startup = 12, active = 2, recovery = 34, damage = 18, height = "Throw", range = 3.2, width = 1.4, breakWindow = 20, breakButton = "LeadPunch", duration = 50, impactFrame = 36, tier = "Heavy", limb = "Body", anim = { archetype = "bear_hug_toss" },
		intent = "Wraps both arms around the opponent's waist, lifts them off the floor with a hip thrust, turns and tosses them face-up in front of him." },
	{ key = "ThrowB", name = "Belly Suplex", input = "RP+RK", notation = "2+4", startup = 12, active = 2, recovery = 34, damage = 20, height = "Throw", range = 3.2, width = 1.4, breakWindow = 20, breakButton = "RearPunch", duration = 52, impactFrame = 38, tier = "Heavy", limb = "Body", anim = { archetype = "slam" },
		intent = "Front body lock, steps in deep, lifts belly to belly, slams forward onto the back." },
	{ key = "RamSlam", name = "Ram Slam", input = "f+LP+LK", notation = "f+1+3", startup = 15, active = 2, recovery = 36, damage = 26, height = "Throw", range = 3.2, width = 1.4, breakWindow = 14, breakButton = "LeadPunch", duration = 58, impactFrame = 42, tier = "Heavy", limb = "Body", anim = { archetype = "slam" },
		intent = "Command grab: lunges forward, scoops the opponent onto his shoulder and drops forward, slamming them flat into the floor (shorter break window)." },
	ultimate({ name = "Landslide", startup = 22, active = 4, recovery = 28, damage = 36, range = 3.0, advance = 1.4, onBlock = -15, limb = "Body", anim = { archetype = "shoulder_tackle", side = "Lead", height = "Mid", lunge = 1.0 },
		cinematic = { duration = 240, impacts = { { frame = 40, share = 0.12 }, { frame = 92, share = 0.18 }, { frame = 150, share = 0.25 }, { frame = 214, share = 0.45 } }, endKind = "FaceUp", endDistance = 4.6,
			beats = {
				"f0 (the hit): an armored charging shoulder pins the opponent; Goran wraps both arms around its waist (body lock).",
				"f40 impact 1: he crushes the body lock and shakes the defender; its back arches, arms flail over his shoulders, feet leave the floor.",
				"f92 impact 2: belly-to-belly suplex: he arches back and throws the defender over his head; it lands on its upper back behind him while he rolls through and stands.",
				"f120-149: he drags the dazed defender up by the waist, its legs buckling.",
				"f150 impact 3: he lifts it across his chest and drops it onto his raised knee (body slam onto the thigh); the defender folds over the knee.",
				"f170-213: he heaves it onto his shoulder (carry), walks one heavy step forward.",
				"f214 impact 4: he falls forward with his whole weight and drives the defender flat onto its back (FaceUp, 4.6 studs in front); Goran rises slowly over it.",
			} },
		intent = "ULTIMATE (Surge only, once per round) 'Landslide': an armored charging shoulder opens it; on hit the cinematic plays the beats in movesets.md (body-lock crush, suplex, knee slam, carry and forward drop)." }),
}, {
	combos = {
		{ name = "Lift And Hammer", kind = "launch", notation = "d+2, f+3, 1,2", damage = 34, difficulty = 2, steps = { { wait = 0, input = "d+2" }, { wait = 35, input = "f+3" }, { wait = 34, input = "1" }, { wait = 8, input = "2" } } },
		{ name = "Counter Haymaker", kind = "counter", notation = "CH b+2, f+3, 1,2", damage = 40, difficulty = 3, counter = true, steps = { { wait = 0, input = "b+2" }, { wait = 32, input = "f+3" }, { wait = 34, input = "1" }, { wait = 8, input = "2" } } },
		{ name = "Forearm Finish", kind = "max", notation = "d+2, f+3, 1,2,1", damage = 39, difficulty = 3, steps = { { wait = 0, input = "d+2" }, { wait = 35, input = "f+3" }, { wait = 34, input = "1" }, { wait = 8, input = "2" }, { wait = 11, input = "1" } } },
		{ name = "Landslide Finish", kind = "ultimate", notation = "d+2, 1+2", damage = 42, difficulty = 2, surge = true, steps = { { wait = 0, input = "d+2" }, { wait = 35, input = "1+2" } } },
	},
	signature = { kind = "catch", key = "BearTrap", name = "Bear Trap", summary = "3+4: open arms for frames 4-24. A high or mid strike that touches him is caught into an unbreakable Belly Suplex. Lows and throws beat it; very punishable on whiff. Plus armored power moves (3, f+2, f,f+2, 3,2,2) and the f+1+3 command grab." },
})

-- LUMI: acrobatic freerunner. Mobility, crush moves and tricky angles; light health. Signature: AERIAL (3+4), a
-- no-hands cartwheel that carries her forward over lows, with kicks out of it.
define({
	id = "Lumi", displayName = "LUMI", style = "Acrobatic freerunning", stanceStyle = "flow",
	identity = "Rooftop acrobat: hops over lows, flips through the air with the Aerial and comes down kicking from angles nobody guards.",
	tagline = "Rooftop freerunner who fights from impossible angles", intro = "Try to keep up. Seriously, try.",
	victory = { "Too slow for the rooftops.", "Gravity's optional. You didn't get the memo." },
	stats = stats({ maxHealth = 90, walkSpeed = 5.7, backSpeed = 4.6, dashDistance = 3.5, dashFrames = 13, backdashDistance = 3.4, backdashFrames = 17, sidestepArc = 2.1, weight = 1.15, height = 5.9, preferredRange = 4.2 }),
	look = "Adult woman, light long-limbed build, deep brown skin, brown eyes, black curly taper with a sports band; olive crop tank, black ribbed techwear arm sleeves, mint slim-fit track pants tucked into black suede split-toe tabi boots, open hands.",
	primaryColor = Color3.fromRGB(35, 40, 48), accentColor = Color3.fromRGB(86, 214, 160),
}, {
	{ key = "Palm", name = "Quick Palm", input = "LP", notation = "1", startup = 10, active = 2, recovery = 12, damage = 5, height = "High", range = 3.95, width = 1.2, track = 1.5, advance = 0.25, push = 0.4, onBlock = 1, onHit = 8, tier = "Light", limb = "LeadArm", anim = { archetype = "palm", side = "Lead", height = "High" },
		intent = "Loose lead palm strike to the face from a bouncy low stance: wrist bent back, heel of the palm snaps forward and back, knees springy." },
	{ key = "PalmHeel", name = "Palm To Spin Heel", input = "LP, RK", notation = "1,4", chainFrom = "Palm", startup = 15, active = 3, recovery = 22, damage = 12, height = "Mid", range = 3.5, width = 1.8, track = 2.5, advance = 1.4, push = 1.0, tumble = true, onBlock = -10, onHit = 3, tier = "Medium", limb = "RearLeg", anim = { archetype = "spin_kick", side = "Rear", height = "Mid", spin = 1.0 },
		intent = "After the palm, she spins a full turn on the lead foot and the rear heel swings around into the ribs (spinning heel kick), arms flung out for momentum. TUMBLE: on an airborne opponent the spinning heel flips the body over in the air (one more juggle hit connects)." },
	{ key = "PalmHeelHook", name = "Palm Heel Hook Kick", input = "LP, RK, RK", notation = "1,4,4", chainFrom = "PalmHeel", startup = 16, active = 3, recovery = 22, damage = 13, height = "High", range = 3.8, width = 2.2, track = 3, advance = 0.6, push = 1.2, onBlock = -12, onHit = "KND", tier = "Heavy", limb = "RearLeg", anim = { archetype = "spin_kick", side = "Rear", height = "High", spin = 1.0 },
		intent = "High ender of 1,4: the spinning heel lands and she keeps the spin going, hopping on the lead foot into a second full turn; the rear heel hooks around at head height (spinning hook kick) and knocks the opponent down." },
	{ key = "PalmHeelSweep", name = "Palm Heel Sweep", input = "LP, RK, LK", notation = "1,4,3", chainFrom = "PalmHeel", startup = 16, active = 3, recovery = 22, damage = 10, height = "Low", range = 3.9, width = 2.2, track = 2, advance = 0.4, push = 0.3, crouching = true, onBlock = -13, onHit = 1, tier = "Medium", limb = "LeadLeg", anim = { archetype = "sweep", side = "Lead", height = "Low", crouch = true, spin = 0.5 },
		intent = "Low ender of 1,4: out of the spinning heel she drops onto one hand and the lead leg sweeps a fast half circle along the floor at ankle height, then she springs back up (same base as the hook kick: high or low)." },
	{ key = "SpinBackfist", name = "Spin Backfist", input = "RP", notation = "2", startup = 12, active = 3, recovery = 16, damage = 10, height = "High", range = 3.75, width = 2.0, track = 3, advance = 0.85, push = 0.6, onBlock = -5, onHit = 5, tier = "Medium", limb = "RearArm", anim = { archetype = "spinning_backfist", side = "Rear", height = "High", spin = 1.0 },
		intent = "Quick spin on the lead foot, back turned for a moment, rear arm whips around and the back of the fist hits the side of the head at the end of the turn." },
	{ key = "SnapKick", name = "Snap Kick", input = "LK", notation = "3", startup = 12, active = 3, recovery = 15, damage = 9, height = "Mid", range = 3.8, width = 1.3, advance = 1.0, push = 0.6, props = { lowCrush = { 3, 9 } }, onBlock = -4, onHit = 4, tier = "Light", limb = "LeadLeg", anim = { archetype = "front_kick", side = "Lead", height = "Mid", hop = 0.3 },
		intent = "Fast lead front snap kick to the stomach thrown off a small hop: both feet leave the floor for a moment (hops over lows), the knee comes up, the shin snaps out and back like a whip, she lands bouncing on the supporting foot." },
	{ key = "SnapCrescent", name = "Snap Into Crescent", input = "LK, RK", notation = "3,4", chainFrom = "SnapKick", startup = 15, active = 3, recovery = 20, damage = 11, height = "High", range = 3.75, width = 2.2, track = 3, advance = 1.45, push = 0.8, onBlock = -9, onHit = 4, tier = "Medium", limb = "RearLeg", anim = { archetype = "crescent_kick", side = "Rear", height = "High" },
		intent = "The snap kick lands and the rear leg swings a straight-legged outside-to-inside crescent across the head, sweeping arc, arms counter-balance." },
	{ key = "CrescentFlyingKick", name = "Crescent Flying Kick", input = "LK, RK, RK", notation = "3,4,4", chainFrom = "SnapCrescent", startup = 18, active = 3, recovery = 24, damage = 14, height = "Mid", range = 3.9, width = 1.6, track = 1.5, advance = 0.8, push = 1.6, props = { lowCrush = { 6, 17 } }, onBlock = -13, onHit = "KND", tier = "Heavy", limb = "RearLeg", anim = { archetype = "jumping_kick", side = "Rear", height = "Mid", hop = 0.9 },
		intent = "Mid ender of 3,4: the crescent leg lands and she jumps off it straight away, tucking the lead knee and shooting the rear leg out flat into the chest in mid-air (flying side kick, low crush while airborne), landing in a crouch; knockdown." },
	{ key = "CrescentKick", name = "Crescent Kick", input = "RK", notation = "4", startup = 14, active = 3, recovery = 19, damage = 12, height = "High", range = 3.6, width = 2.4, track = 3, advance = 1.6, push = 0.8, onBlock = -7, onHit = 4, tier = "Medium", limb = "RearLeg", anim = { archetype = "crescent_kick", side = "Rear", height = "High" },
		intent = "Rear-leg crescent kick: straight leg lifts and swings across the face in a wide arc, hips open then close, foot lands back in stance." },
	{ key = "CartwheelKick", name = "Cartwheel Kick", input = "b+LK", notation = "b+3", startup = 18, active = 4, recovery = 20, damage = 15, height = "Mid", range = 3.7, width = 1.6, track = 1.5, advance = 1.5, push = 1.2, props = { highCrush = { 4, 16 } }, onBlock = -9, onHit = "KND", onCounter = "LAUNCH", tier = "Heavy", limb = "LeadLeg", anim = { archetype = "cartwheel_kick", side = "Lead", height = "Mid" },
		intent = "Hands go to the floor in a sideways cartwheel (head drops low = high crush) and the lead leg comes over the top into the chest; lands back on her feet. On a counter hit the heel scoops up under the chin and pops the opponent into the air (launch)." },
	{ key = "FlipKick", name = "Backflip Kick", input = "df+RK", notation = "df+4", startup = 16, active = 3, recovery = 26, damage = 13, height = "Mid", range = 3.1, width = 1.2, advance = 0.9, push = 0.6, props = { lowCrush = { 6, 15 } }, onBlock = -15, onHit = "LAUNCH", tier = "Launch", limb = "RearLeg", anim = { archetype = "flip_kick", side = "Rear", height = "Mid", hop = 1.2 },
		intent = "Standing backflip: the rear foot kicks up under the chin as she flips backwards, feet leave the floor (low crush), lands crouched slightly behind her start." },
	{ key = "SlideKick", name = "Slide Kick", input = "d+RK", notation = "d+4", startup = 18, active = 4, recovery = 24, damage = 13, height = "Low", range = 3.4, width = 1.6, track = 1, advance = 1.8, crouching = true, push = 0.3, props = { highCrush = { 5, 20 } }, onBlock = -16, onHit = "KND", tier = "Heavy", limb = "RearLeg", anim = { archetype = "slide_kick", side = "Rear", height = "Low", crouch = true, lunge = 1.6 },
		intent = "Baseball slide: drops onto the hip and slides feet-first along the floor into the opponent's ankles, rear leg extended, then pops back up." },
	{ key = "QuickLow", name = "Flick Low", input = "d+LK", notation = "d+3", stanceCancel = "Aerial", startup = 12, active = 2, recovery = 18, damage = 7, height = "Low", range = 4.0, width = 1.3, track = 1, crouching = true, push = 0.3, onBlock = -11, onHit = 2, tier = "Light", limb = "LeadLeg", anim = { archetype = "low_kick", side = "Lead", height = "Low", crouch = true },
		intent = "From a squat, the lead foot flicks out along the floor into the shin and snaps back; hands near the floor for balance." },
	{ key = "ScissorKick", name = "Scissor Hop Kick", input = "f+RK", notation = "f+4", startup = 16, active = 3, recovery = 20, damage = 14, height = "High", range = 3.5, width = 1.4, track = 1.5, advance = 1.7, push = 1.2, props = { lowCrush = { 5, 14 } }, onBlock = -9, onHit = "KND", tier = "Heavy", limb = "RearLeg", anim = { archetype = "jumping_kick", side = "Rear", height = "High", hop = 0.9 },
		intent = "Jumps off both feet, legs scissor in the air and the rear foot kicks forward at head height; lands on the kicking foot." },
	{ key = "VaultKick", name = "Vault Kick", input = "dash+LK", notation = "f,f+3", startup = 14, active = 3, recovery = 18, damage = 14, height = "Mid", range = 4.1, width = 1.4, track = 1.5, advance = 1.5, push = 1.0, props = { lowCrush = { 3, 12 } }, onBlock = -6, onHit = 4, tier = "Medium", limb = "LeadLeg", anim = { archetype = "jumping_kick", side = "Lead", height = "Mid", hop = 0.7, lunge = 1.0 },
		intent = "Out of a run, she vaults off the rear foot into a flying lead front kick to the chest, body almost horizontal, lands in stance." },
	{ key = "TwirlKick", name = "Twirl Kick", input = "ss+RK", notation = "ss+4", startup = 15, active = 3, recovery = 20, damage = 13, height = "High", range = 3.35, width = 2.6, homing = true, advance = 1.65, push = 0.8, onBlock = -9, onHit = 4, tier = "Medium", limb = "RearLeg", anim = { archetype = "tornado_kick", side = "Rear", height = "High", spin = 1.0 },
		intent = "From a sidestep, a 360-degree turning kick: she spins on the lead foot and the rear leg sweeps a flat circle at head height that tracks the opponent." },
	{ key = "KneeRush", name = "Running Knee", input = "f+LK", notation = "f+3", startup = 13, active = 3, recovery = 17, damage = 12, height = "Mid", range = 2.8, width = 1.3, track = 1.5, advance = 1.6, push = 1.0, props = { lowCrush = { 5, 13 } }, onBlock = -4, onHit = 6, tier = "Medium", limb = "LeadLeg", anim = { archetype = "knee", side = "Lead", height = "Mid", lunge = 0.8 },
		intent = "Two quick running steps and a jumping lead knee to the body (both feet off the floor: hops over lows), arms pumping back, lands on the knee leg." },
	{ key = "Aerial", name = "Aerial", input = "LK+RK", notation = "3+4", toStance = "Aerial", noHit = true, startup = 10, active = 1, recovery = 1, damage = 0, height = "Mid", range = 2.6, width = 1.2, push = 0, onBlock = 0, onHit = 0, tier = "Light", limb = "Body", anim = { archetype = "parry", side = "Lead", height = "Mid", stance = true },
		intent = "SIGNATURE (no strike): a forward no-hands cartwheel (gymnastics aerial). She steps in, throws both arms down and swings the legs over in a wide arc, body sideways and horizontal at the top, traveling about 2.2 studs toward the opponent and landing on the lead foot (see the stance: she is airborne, over lows, from frame 3 to 18)." },
	{ key = "AerialSplit", name = "Aerial Split Kick", input = "AER+LK", notation = "AER+3", stance = "Aerial", startup = 12, active = 3, recovery = 18, damage = 12, height = "Mid", range = 3.6, width = 1.8, track = 2, advance = 0.4, push = 0.8, props = { lowCrush = { 1, 10 } }, onBlock = -8, onHit = 4, tier = "Medium", limb = "LeadLeg", anim = { archetype = "jumping_kick", side = "Lead", height = "Mid", hop = 0.8 },
		intent = "Out of the cartwheel, still in the air, she opens the legs into a split and snaps the lead foot into the chest (low crush while airborne), landing on the rear foot." },
	{ key = "AerialHeel", name = "Aerial Rising Heel", input = "AER+RK", notation = "AER+4", stance = "Aerial", startup = 13, active = 3, recovery = 24, damage = 12, height = "Mid", range = 3.4, width = 1.2, advance = 0.4, push = 0.6, props = { lowCrush = { 1, 8 } }, onBlock = -14, onHit = "LAUNCH", tier = "Launch", limb = "RearLeg", anim = { archetype = "rising_kick", side = "Rear", height = "Mid", hop = 0.4 },
		intent = "She lands out of the cartwheel on the lead foot and the rear heel keeps the wheel's momentum, swinging straight up under the opponent's chin (rising heel kick) and lifting it into a juggle (launcher, very unsafe on block)." },
	{ key = "AerialSweep", name = "Aerial Drop Sweep", input = "AER+d+LK", notation = "AER+d+3", stance = "Aerial", startup = 12, active = 3, recovery = 26, damage = 13, height = "Low", range = 3.9, width = 2.4, track = 2, push = 0.3, crouching = true, onBlock = -16, onHit = "KND", tier = "Heavy", limb = "LeadLeg", anim = { archetype = "sweep", side = "Lead", height = "Low", crouch = true, spin = 0.5 },
		intent = "Holding down out of the cartwheel, she lands low on both hands and one knee and the lead leg sweeps a fast arc along the floor at ankle height (knockdown), then she springs back up." },
	{ key = "Throw", name = "Flip Toss", input = "LP+LK", notation = "1+3", startup = 12, active = 2, recovery = 34, damage = 16, height = "Throw", range = 3.2, width = 1.4, breakWindow = 20, breakButton = "LeadPunch", duration = 46, impactFrame = 32, tier = "Heavy", limb = "Body", anim = { archetype = "flip_toss" },
		intent = "Grabs the opponent's shoulders, springs up and backflips off the opponent's belly, the kick-off drives them onto their back." },
	{ key = "ThrowB", name = "Vault Takedown", input = "RP+RK", notation = "2+4", startup = 12, active = 2, recovery = 34, damage = 17, height = "Throw", range = 3.2, width = 1.4, breakWindow = 20, breakButton = "RearPunch", duration = 46, impactFrame = 30, tier = "Heavy", limb = "Body", anim = { archetype = "arm_toss" },
		intent = "Hooks the neck from the side, springs up and stamps the lead knee; her weight folds them backwards." },
	ultimate({ name = "Skyline", startup = 18, active = 3, recovery = 30, damage = 30, range = 3.9, advance = 1.2, onBlock = -15, limb = "RearLeg", anim = { archetype = "jumping_kick", side = "Rear", height = "Mid", hop = 0.6 },
		cinematic = { duration = 210, impacts = { { frame = 28, share = 0.10 }, { frame = 56, share = 0.10 }, { frame = 86, share = 0.12 }, { frame = 118, share = 0.14 }, { frame = 150, share = 0.18 }, { frame = 192, share = 0.36 } }, endKind = "FaceDown", endDistance = 4.4,
			beats = {
				"f0 (the hit): an armored running jump kick into the chest; the opponent rocks back and Lumi lands light in front of it.",
				"f28 impact 1: a spinning heel kick to the ribs; the defender bends sideways.",
				"f56 impact 2: a cartwheel kick over the top onto the defender's shoulder; it sinks to one knee.",
				"f86 impact 3: she runs up the defender's thigh and chest like a rooftop wall and kicks off its chest (back-flip off the body); the defender is knocked upright, arms wide.",
				"f118 impact 4: at the top of the flip, a scissor kick to the head; the defender's head whips sideways.",
				"f150 impact 5: she lands low and a fast drop sweep takes its legs; the defender floats up horizontally.",
				"f192 impact 6: she springs into a front flip and drives a falling heel down onto the floating defender, spiking it face-first into the floor (FaceDown, 4.4 studs in front); she lands crouched on one hand.",
			} },
		intent = "ULTIMATE (Surge only, once per round) 'Skyline': an armored running jump kick opens it; on hit the cinematic plays the beats in movesets.md (heel kick, cartwheel kick, wall-run flip off the chest, scissor kick, drop sweep, falling heel)." }),
}, {
	combos = {
		{ name = "Flip And Spin", kind = "launch", notation = "df+4, 2, 1,4, 4", damage = 34, difficulty = 3, steps = { { wait = 0, input = "df+4" }, { wait = 37, input = "2" }, { wait = 30, input = "1" }, { wait = 8, input = "4" }, { wait = 11, input = "4" } } },
		{ name = "Aerial Launch", kind = "stance", notation = "3+4, AER+4, 2, 1,4, 4", damage = 33, difficulty = 4, steps = { { wait = 0, input = "3+4" }, { wait = 1, input = "AER+4" }, { wait = 41, input = "2" }, { wait = 30, input = "1" }, { wait = 8, input = "4" }, { wait = 11, input = "4" } } },
		{ name = "Cartwheel Counter", kind = "counter", notation = "CH b+3, 2, 1,4, 4", damage = 40, difficulty = 3, counter = true, steps = { { wait = 0, input = "b+3" }, { wait = 34, input = "2" }, { wait = 30, input = "1" }, { wait = 8, input = "4" }, { wait = 11, input = "4" } } },
		{ name = "Crescent Flight", kind = "max", notation = "df+4, 2, 3,4,4", damage = 35, difficulty = 3, steps = { { wait = 0, input = "df+4" }, { wait = 37, input = "2" }, { wait = 30, input = "3" }, { wait = 8, input = "4" }, { wait = 14, input = "4" } } },
		{ name = "Skyline Finish", kind = "ultimate", notation = "df+4, 1+2", damage = 35, difficulty = 2, surge = true, steps = { { wait = 0, input = "df+4" }, { wait = 37, input = "1+2" } } },
	},
	signature = { kind = "stance", key = "Aerial", name = "Aerial", summary = "3+4: a forward no-hands cartwheel, airborne over lows from frame 3 to 18, traveling 2.2 studs. AER+3 split kick (tumbles in juggles), AER+4 rising heel launcher, AER+d+3 drop sweep; lands on its own at frame 26. Cancel d+3 into it." },
	stances = {
		{ key = "Aerial", name = "Aerial", tag = "AER", entryFrames = 4, cancelFrom = 10, maxFrames = 26, travel = 2.2, travelFrames = 18, counterHit = true, props = { lowCrush = { 3, 18 } },
			entryIntent = "Step and dip into the cartwheel: arms swing down, the rear leg kicks up (frames 1-4).",
			intent = "Aerial: a no-hands cartwheel, the body sideways and horizontal at the top of a wide arc, legs split in a V, arms out; the root travels 2.2 studs forward over frames 1-18 (ease-out) and she is airborne (low crush) on frames 3-18. Follow-ups come out of the second half (from frame 10).",
			exitIntent = "Lands on the lead foot, then the rear, and settles into her bouncy stance (frames 19-26).", },
	},
})

-- RHYS: karate counter-striker. Straight mids, parries, punishes mistakes. Signature: STILL WATER (3+4), a still
-- counter stance that parries every high or mid strike while he holds it.
define({
	id = "Rhys", displayName = "RHYS", style = "Karate-based counter striking", stanceStyle = "karate",
	identity = "Patient karateka: parries high, mid and low, waits in Still Water and answers every mistake with a straight line.",
	tagline = "Patient counter-striker who punishes every mistake", intro = "Show me your best opening.",
	victory = { "Discipline wins the long fight.", "Every mistake has a price." },
	stats = stats({ maxHealth = 100, walkSpeed = 4.8, backSpeed = 4.2, dashDistance = 3.0, dashFrames = 14, backdashDistance = 3.1, backdashFrames = 18, sidestepArc = 1.9, weight = 1.0, height = 5.9, preferredRange = 4.0 }),
	look = "Adult man, lean athletic build, light skin, dark brown hair tied back in a bun, clean-shaven; deep-indigo karate gi over a grey training tee, black belt, white cloth hand wraps, barefoot. Do NOT use a white gi, a torn sleeveless gi or any headband.",
	primaryColor = Color3.fromRGB(32, 48, 92), accentColor = Color3.fromRGB(170, 178, 190),
}, {
	{ key = "Jab", name = "Lead Strike", input = "LP", notation = "1", startup = 10, active = 2, recovery = 12, damage = 6, height = "High", range = 4.2, width = 1.2, track = 1.5, push = 0.4, onBlock = 1, onHit = 8, tier = "Light", limb = "LeadArm", anim = { archetype = "straight", side = "Lead", height = "High" },
		intent = "Karate lead punch (kizami-style) from a long front stance: the lead foot slides in, the fist twists palm-down at impact, the rear fist stays chambered at the ribs." },
	{ key = "ReversePunch", name = "Lead Into Reverse", input = "LP, RP", notation = "1,2", chainFrom = "Jab", startup = 12, active = 3, recovery = 17, damage = 11, height = "Mid", range = 4.4, width = 1.3, track = 1.5, advance = 0.2, push = 0.8, onBlock = -6, onHit = 4, tier = "Medium", limb = "RearArm", anim = { archetype = "straight", side = "Rear", height = "Mid" },
		intent = "The lead hand pulls back to the hip while the rear reverse punch drives to the solar plexus: hips snap square, rear heel planted, fist twists at full extension." },
	{ key = "ReverseHighKick", name = "Reverse Punch Head Kick", input = "LP, RP, RK", notation = "1,2,4", chainFrom = "ReversePunch", startup = 16, active = 3, recovery = 21, damage = 13, height = "High", range = 4.6, width = 2.2, track = 3, advance = 0.5, push = 0.8, onBlock = -9, onHit = 5, tier = "Medium", limb = "RearLeg", anim = { archetype = "roundhouse", side = "Rear", height = "High" },
		intent = "High ender of 1,2: as the reverse punch retracts to the hip, the rear knee chambers sideways and the instep snaps to the temple (head roundhouse, mawashi-geri style), then snaps back into the front stance." },
	{ key = "ReverseLowKick", name = "Reverse Punch Low Kick", input = "LP, RP, LK", notation = "1,2,3", chainFrom = "ReversePunch", startup = 15, active = 2, recovery = 20, damage = 9, height = "Low", range = 3.9, width = 1.3, track = 1, advance = 0.3, push = 0.3, onBlock = -12, onHit = 2, tier = "Medium", limb = "LeadLeg", anim = { archetype = "front_kick", side = "Lead", height = "Low" },
		intent = "Low ender of 1,2: the lead knee lifts low and the sole of the foot thrusts down into the opponent's lead knee/shin (a low stopping kick), body upright, fists chambered; the foot returns to the front stance (same base as the head kick: high or low)." },
	{ key = "StraightPunch", name = "Center Punch", input = "RP", notation = "2", startup = 12, active = 3, recovery = 16, damage = 11, height = "Mid", range = 3.8, width = 1.3, track = 1.5, advance = 0.8, push = 0.8, onBlock = -4, onHit = 5, tier = "Medium", limb = "RearArm", anim = { archetype = "straight", side = "Rear", height = "Mid" },
		intent = "Rear reverse punch to the chest from stance (gyaku-zuki): hip rotation first, lead hand chambers back, very straight line, short sharp exhale posture." },
	{ key = "PunchKick", name = "Punch Into High Kick", input = "RP, RK", notation = "2,4", chainFrom = "StraightPunch", startup = 16, active = 3, recovery = 21, damage = 13, height = "High", range = 4.65, width = 2.2, track = 3, advance = 0.55, push = 0.8, onBlock = -9, onHit = 5, tier = "Medium", limb = "RearLeg", anim = { archetype = "roundhouse", side = "Rear", height = "High" },
		intent = "After the center punch, the rear leg fires a snapping roundhouse to the head (mawashi-geri): knee chambers sideways, the instep snaps to the temple, snaps back." },
	{ key = "PunchKickAxe", name = "Punch Kick Axe", input = "RP, RK, RK", notation = "2,4,4", chainFrom = "PunchKick", startup = 19, active = 3, recovery = 22, damage = 15, height = "Mid", range = 3.6, width = 1.4, track = 1.5, advance = 0.6, push = 1.2, onBlock = -12, onHit = "KND", tier = "Heavy", limb = "RearLeg", anim = { archetype = "axe_kick", side = "Rear", height = "Mid" },
		intent = "Mid ender of 2,4: the head-kick leg does not land; it rises straight up above head height and the heel chops down onto the collarbone (falling axe kick), body upright, arms open; knockdown." },
	{ key = "FrontSnap", name = "Front Snap Kick", input = "LK", notation = "3", startup = 12, active = 3, recovery = 16, damage = 10, height = "Mid", range = 3.8, width = 1.3, advance = 1.0, push = 0.6, onBlock = -3, onHit = 4, onCounter = "KND", tier = "Light", limb = "LeadLeg", anim = { archetype = "front_kick", side = "Lead", height = "Mid" },
		intent = "Lead front snap kick (mae-geri) with the ball of the foot to the stomach: knee lifts high first, shin snaps out, recoils before landing." },
	{ key = "AxeKick", name = "Falling Axe Kick", input = "RK", notation = "4", startup = 19, active = 3, recovery = 18, damage = 16, height = "Mid", range = 3.25, width = 1.4, track = 1.5, advance = 1.65, push = 1.2, onBlock = -2, onHit = "KND", tier = "Heavy", limb = "RearLeg", anim = { archetype = "axe_kick", side = "Rear", height = "Mid" },
		intent = "Rear leg swings straight up above head height and the heel chops down onto the collarbone; body stays upright, arms open for balance." },
	{ key = "Deflect", name = "Deflect", input = "b+LP", notation = "b+1", noHit = true, startup = 3, active = 10, recovery = 22, damage = 0, height = "Mid", range = 2.6, width = 1.6, push = 0, props = { parry = { window = { 4, 13 }, heights = { "High", "Mid" }, stagger = 24 } }, onBlock = 0, onHit = 0, tier = "Light", limb = "LeadArm", anim = { archetype = "parry", side = "Lead", height = "High" },
		intent = "Inside-to-outside sweeping block (uke) with the lead forearm while stepping slightly back; on contact the attacker's arm/leg is knocked aside and they stagger." },
	{ key = "LowParry", name = "Low Deflect", input = "db+LP", notation = "db+1", noHit = true, startup = 3, active = 10, recovery = 20, damage = 0, height = "Mid", range = 2.6, width = 1.6, push = 0, crouching = true, props = { parry = { window = { 3, 12 }, heights = { "Low" }, stagger = 26 } }, onBlock = 0, onHit = 0, tier = "Light", limb = "LeadArm", anim = { archetype = "parry", side = "Lead", height = "Low", crouch = true },
		intent = "Downward sweeping block: he sinks into a low front stance and the lead forearm sweeps down and out across the shin line (palm down), knocking the low kick aside; the attacker staggers. Parries lows only." },
	{ key = "RisingKnee", name = "Rising Knee", input = "df+LK", notation = "df+3", startup = 15, active = 3, recovery = 22, damage = 13, height = "Mid", range = 2.8, width = 1.2, advance = 1.1, push = 0.6, onBlock = -13, onHit = "LAUNCH", tier = "Launch", limb = "LeadLeg", anim = { archetype = "knee", side = "Lead", height = "Mid", crouch = true, hop = 0.4 },
		intent = "From a slight crouch the lead knee drives straight up under the chin with a small jump, both hands pulling down, lifting the opponent." },
	{ key = "LowSweep", name = "Low Reaping Sweep", input = "b+RK", notation = "b+4", startup = 19, active = 4, recovery = 24, damage = 14, height = "Low", range = 3.9, width = 2.4, track = 2, advance = 0.5, crouching = true, push = 0.3, onBlock = -16, onHit = "KND", tier = "Heavy", limb = "RearLeg", anim = { archetype = "sweep", side = "Rear", height = "Low", crouch = true, spin = 0.5 },
		intent = "Drops low on the lead leg, rear leg reaps along the floor in a wide arc at the ankles (ashi-barai style), comes back up in stance." },
	{ key = "LowKick", name = "Low Kick", input = "d+RK", notation = "d+4", stanceCancel = "StillWater", startup = 13, active = 2, recovery = 20, damage = 8, height = "Low", range = 4.0, width = 1.4, track = 1, push = 0.3, onBlock = -13, onHit = 1, tier = "Light", limb = "RearLeg", anim = { archetype = "low_kick", side = "Rear", height = "Low" },
		intent = "Short rear-leg low kick to the inside of the knee: quick hip turn, shin chops down, returns to stance immediately." },
	{ key = "LowPunch", name = "Kneeling Punch", input = "d+LP", notation = "d+1", stanceCancel = "StillWater", startup = 11, active = 2, recovery = 14, damage = 5, height = "Mid", smid = true, range = 3.8, width = 1.2, crouching = true, push = 0.4, onBlock = -4, onHit = 4, tier = "Light", limb = "LeadArm", anim = { archetype = "straight", side = "Lead", height = "Low", crouch = true },
		intent = "Drops into a low stance and throws a short straight lead punch to the stomach; stays low afterward." },
	{ key = "SpinBackfist", name = "Turning Backfist", input = "b+RP", notation = "b+2", startup = 15, active = 3, recovery = 18, damage = 13, height = "High", range = 4.15, width = 2.6, homing = true, advance = 0.45, push = 0.8, tumble = true, onBlock = -8, onHit = 4, tier = "Medium", limb = "RearArm", anim = { archetype = "spinning_backfist", side = "Rear", height = "High", spin = 1.0 },
		intent = "Steps across and turns his back, the rear backfist whips around in a flat circle to the side of the head, turning with a sidestepping opponent (homing). TUMBLE: on an airborne opponent the turning backfist spins the body over in the air." },
	{ key = "LungePunch", name = "Lunging Punch", input = "f+RP", notation = "f+2", startup = 16, active = 3, recovery = 20, damage = 16, height = "Mid", range = 3.65, width = 1.3, advance = 1.95, push = 1.2, onBlock = -8, onHit = 5, tier = "Heavy", limb = "RearArm", anim = { archetype = "straight", side = "Rear", height = "Mid", lunge = 1.2 },
		intent = "Long gliding step forward (oi-zuki) covering distance, rear-hand punch to the chest at the end of the slide, body low and straight." },
	{ key = "SideKick", name = "Side Thrust Kick", input = "f+LK", notation = "f+3", startup = 14, active = 3, recovery = 18, damage = 14, height = "Mid", range = 3.85, width = 1.3, advance = 1.45, push = 1.6, onBlock = -6, onHit = 3, tier = "Medium", limb = "LeadLeg", anim = { archetype = "side_kick", side = "Lead", height = "Mid" },
		intent = "Turns sideways, lead knee chambers across the body and the heel thrusts out sideways into the ribs (yoko-geri), body leaning away." },
	{ key = "CrescentStep", name = "Stepping Crescent", input = "ss+RK", notation = "ss+4", startup = 15, active = 3, recovery = 19, damage = 13, height = "Mid", range = 4.25, width = 2.4, track = 4, advance = 0.55, push = 0.8, onBlock = -7, onHit = 4, tier = "Medium", limb = "RearLeg", anim = { archetype = "crescent_kick", side = "Rear", height = "Mid" },
		intent = "From a sidestep, a stepping crescent kick to the ribs: rear leg swings in a wide inward arc at waist height, catching an opponent moving to the side." },
	{ key = "StillWater", name = "Still Water", input = "LK+RK", notation = "3+4", toStance = "StillWater", noHit = true, startup = 8, active = 1, recovery = 1, damage = 0, height = "Mid", range = 2.6, width = 1.2, push = 0, onBlock = 0, onHit = 0, tier = "Light", limb = "Body", anim = { archetype = "parry", side = "Lead", height = "Mid", stance = true },
		intent = "SIGNATURE stance entry (no strike): he slides the lead foot back half a step into a short, low back-weighted stance, the lead open hand extends forward at chest height, the rear fist settles at the hip, eyes on the opponent; a long exhale (see the stance)." },
	{ key = "StillStrike", name = "Sudden Strike", input = "STW+LP", notation = "STW+1", stance = "StillWater", startup = 10, active = 2, recovery = 15, damage = 8, height = "Mid", range = 3.9, width = 1.3, track = 1.5, advance = 0.4, push = 0.5, onBlock = -3, onHit = 5, tier = "Light", limb = "LeadArm", anim = { archetype = "straight", side = "Lead", height = "Mid" },
		intent = "From Still Water, the extended lead hand closes into a fist and shoots straight to the solar plexus with a small forward slide of the front foot, no wind-up; the fist twists palm-down at impact and returns." },
	{ key = "StillReverse", name = "Rising Reverse Punch", input = "STW+RP", notation = "STW+2", stance = "StillWater", startup = 14, active = 3, recovery = 24, damage = 14, height = "Mid", range = 3.7, width = 1.2, advance = 0.6, push = 0.6, onBlock = -14, onHit = "LAUNCH", tier = "Launch", limb = "RearArm", anim = { archetype = "uppercut", side = "Rear", height = "Mid", crouch = true },
		intent = "From Still Water, the hips snap square and the rear fist drives from the hip up under the chin on a rising line (a reverse punch angled upward), the legs extending; the opponent is lifted into a juggle (launcher, very unsafe on block)." },
	{ key = "Throw", name = "Hip Throw", input = "LP+LK", notation = "1+3", startup = 12, active = 2, recovery = 34, damage = 18, height = "Throw", range = 3.2, width = 1.4, breakWindow = 20, breakButton = "LeadPunch", duration = 46, impactFrame = 32, tier = "Heavy", limb = "Body", anim = { archetype = "hip_toss" },
		intent = "Grips the sleeve and collar, steps in and takes them down with an outer reap of the lead leg." },
	{ key = "ThrowB", name = "Shoulder Throw", input = "RP+RK", notation = "2+4", startup = 12, active = 2, recovery = 34, damage = 19, height = "Throw", range = 3.2, width = 1.4, breakWindow = 20, breakButton = "RearPunch", duration = 48, impactFrame = 32, tier = "Heavy", limb = "Body", anim = { archetype = "arm_toss" },
		intent = "Arm trap and leg-block takedown, kneeling at the end." },
	ultimate({ name = "Last Kata", startup = 20, active = 3, recovery = 28, damage = 34, range = 3.9, advance = 1.0, onBlock = -15, limb = "RearArm", anim = { archetype = "straight", side = "Rear", height = "Mid", lunge = 0.8 },
		cinematic = { duration = 190, impacts = { { frame = 32, share = 0.12 }, { frame = 64, share = 0.14 }, { frame = 98, share = 0.16 }, { frame = 170, share = 0.58 } }, endKind = "FaceUp", endDistance = 4.6,
			beats = {
				"f0 (the hit): an armored gliding reverse punch to the sternum; the opponent stops dead.",
				"f32 impact 1: a lead knife-hand chop down onto the collarbone; the defender's shoulder drops.",
				"f64 impact 2: a front snap kick into the stomach; the defender doubles over.",
				"f98 impact 3: a rising elbow under the chin; the defender's head snaps up and it sways, dazed.",
				"f110-169: Rhys steps back into a deep, still stance and exhales; nothing moves but the defender swaying (the camera holds on him).",
				"f170 impact 4 (the last kata): one perfect stepping reverse punch to the sternum; the defender is blown off its feet and lands on its back (FaceUp, 4.6 studs away). Rhys holds the finished punch, then returns the fist to his hip.",
			} },
		intent = "ULTIMATE (Surge only, once per round) 'Last Kata': an armored gliding reverse punch opens it; on hit the cinematic plays the beats in movesets.md (knife-hand, front kick, rising elbow, a long still breath, one decisive reverse punch)." }),
}, {
	combos = {
		{ name = "Knee And Backfist", kind = "launch", notation = "df+3, 2, b+2, 1", damage = 31, difficulty = 2, steps = { { wait = 0, input = "df+3" }, { wait = 32, input = "2" }, { wait = 30, input = "b+2" }, { wait = 35, input = "1" } } },
		{ name = "Still Water Answer", kind = "stance", notation = "3+4, STW+2, 2, b+2, 1", damage = 32, difficulty = 3, steps = { { wait = 0, input = "3+4" }, { wait = 1, input = "STW+2" }, { wait = 40, input = "2" }, { wait = 30, input = "b+2" }, { wait = 35, input = "1" } } },
		{ name = "Counter Knee", kind = "max", notation = "CH df+3, 2, b+2, 1", damage = 34, difficulty = 3, counter = true, steps = { { wait = 0, input = "df+3" }, { wait = 32, input = "2" }, { wait = 30, input = "b+2" }, { wait = 35, input = "1" } } },
		{ name = "Last Kata Finish", kind = "ultimate", notation = "df+3, 1+2", damage = 38, difficulty = 2, surge = true, steps = { { wait = 0, input = "df+3" }, { wait = 32, input = "1+2" } } },
	},
	signature = { kind = "stance", key = "StillWater", name = "Still Water", summary = "3+4: a still counter stance. From frame 8 every high or mid strike that touches him is parried (26-frame stagger, he is free at once). Lows and throws beat it. STW+1 fast mid punch, STW+2 rising reverse punch launcher. Cancel d+1 / d+4 into it; hold back to leave. Plus parries on b+1 (high/mid) and db+1 (low)." },
	stances = {
		{ key = "StillWater", name = "Still Water", tag = "STW", entryFrames = 8, cancelFrom = 8, backExit = 10, maxFrames = 60, counterHit = true, props = { parry = { window = { 8, 60 }, heights = { "High", "Mid" }, stagger = 26 } },
			entryIntent = "Lead foot slides back into a short back-weighted stance, lead open hand extends (8 frames).",
			intent = "Still Water loop: a low, back-weighted karate stance (most weight on the rear leg, front foot light), lead open hand forward at chest height, rear fist at the hip, perfectly still except slow breathing. Any high or mid strike that touches him is parried (play the Deflect contact on the parry event). Lows hit him (counter hits).",
			exitIntent = "Brings the lead foot back under him and returns to the long front stance.", },
	},
})

-- NIA: kung-fu-inspired flow fighter. Flowing hand strings and spinning kicks. Signature: COIL (3+4), a winding
-- stance whose spinning kicks chain into a three-hit whirl with delayable timing.
define({
	id = "Nia", displayName = "NIA", style = "Kung-fu-inspired whirlwind", stanceStyle = "kungfu",
	identity = "Flowing whirlwind: never-ending hand strings, spins out of the Coil and delayable kicks that keep you guessing when the next one lands.",
	tagline = "Relentless flow fighter who never stops moving", intro = "Breathe in. You won't get another chance.",
	victory = { "Flow beats force.", "You blinked. That was enough." },
	stats = stats({ maxHealth = 95, walkSpeed = 5.2, backSpeed = 4.3, dashDistance = 3.2, dashFrames = 14, backdashDistance = 3.2, backdashFrames = 18, sidestepArc = 2.0, weight = 1.05, height = 5.5, preferredRange = 3.8 }),
	look = "Adult woman, compact athletic build, fair skin, black chin-length bob; black cropped mandarin-collar top with gold embroidery and laced gold bracers, deep-purple draped waist wrap, purple tapered training pants, soft dark slip-on shoes, open hands. Do NOT use a qipao/cheongsam, buns with ribbons, or pigtails.",
	primaryColor = Color3.fromRGB(36, 30, 44), accentColor = Color3.fromRGB(226, 180, 70),
}, {
	{ key = "Chop", name = "Knife Hand", input = "LP", notation = "1", startup = 10, active = 2, recovery = 12, damage = 5, height = "High", range = 3.55, width = 1.2, track = 1.5, advance = 0.65, push = 0.4, onBlock = 1, onHit = 8, tier = "Light", limb = "LeadArm", anim = { archetype = "chop", side = "Lead", height = "High" },
		intent = "Lead knife-hand strike to the neck: open hand, fingers together, wrist turns as the hand cuts forward and slightly down, rear palm guards the chest." },
	{ key = "DoubleChop", name = "Twin Knife Hand", input = "LP, LP", notation = "1,1", chainFrom = "Chop", startup = 10, active = 2, recovery = 13, damage = 6, height = "High", range = 3.75, width = 1.2, track = 1.5, advance = 0.55, push = 0.5, onBlock = 0, onHit = 7, tier = "Light", limb = "RearArm", anim = { archetype = "chop", side = "Rear", height = "High" },
		intent = "The rear hand follows with a second knife-hand from the other side as the lead hand circles back, flowing figure-eight arm motion." },
	{ key = "FlurryKick", name = "Flurry Finisher", input = "LP, LP, RK", notation = "1,1,4", chainFrom = "DoubleChop", startup = 15, active = 3, recovery = 22, damage = 12, height = "Mid", range = 4.2, width = 1.8, track = 2.5, advance = 0.9, push = 1.4, onBlock = -12, onHit = "KND", tier = "Medium", limb = "RearLeg", anim = { archetype = "roundhouse", side = "Rear", height = "Mid" },
		intent = "The hand flurry flows into a turning rear roundhouse to the body; she pivots on the lead foot, arms circle outward as the kick lands." },
	{ key = "DoubleChopLow", name = "Flurry Low Kick", input = "LP, LP, LK", notation = "1,1,3", chainFrom = "DoubleChop", startup = 15, active = 2, recovery = 20, damage = 9, height = "Low", range = 4.0, width = 1.4, track = 1, advance = 0.3, push = 0.3, onBlock = -12, onHit = 2, tier = "Medium", limb = "LeadLeg", anim = { archetype = "low_kick", side = "Lead", height = "Low", crouch = true },
		intent = "Low ender of 1,1: after the two chops she sinks into a low stance and the lead foot snaps a short kick into the shin along the floor, both palms circling in front of her (same base as the flurry finisher: mid or low)." },
	{ key = "PalmThrust", name = "Palm Thrust", input = "RP", notation = "2", startup = 12, active = 3, recovery = 16, damage = 11, height = "Mid", range = 3.4, width = 1.3, track = 1.5, advance = 1.0, push = 1.2, onBlock = -4, onHit = 5, tier = "Medium", limb = "RearArm", anim = { archetype = "palm", side = "Rear", height = "Mid" },
		intent = "Rear palm thrust to the chest from a low horse-like stance: the hips sink and turn, the heel of the palm pushes forward, the lead hand withdraws to the waist." },
	{ key = "PalmKick", name = "Palm Into Rising Snap Kick", input = "RP, LK", notation = "2,3", chainFrom = "PalmThrust", stanceCancel = "Coil", startup = 14, active = 3, recovery = 19, damage = 11, height = "Mid", range = 3.8, width = 1.3, track = 1.5, advance = 1.0, push = 1.0, onBlock = -8, onHit = 3, tier = "Medium", limb = "LeadLeg", anim = { archetype = "front_kick", side = "Lead", height = "Mid" },
		intent = "The palm withdraws, weight shifts onto the rear leg and the lead foot snaps a front kick into the stomach, then the hands return to a guard as the foot lands back in the low stance." },
	{ key = "PalmKickHigh", name = "Palm Kick Crescent", input = "RP, LK, RK", notation = "2,3,4", chainFrom = "PalmKick", delay = 20, startup = 16, active = 3, recovery = 22, damage = 13, height = "High", range = 4.4, width = 2.4, track = 3, advance = 0.6, push = 0.9, onBlock = -9, onHit = 5, tier = "Medium", limb = "RearLeg", anim = { archetype = "crescent_kick", side = "Rear", height = "High" },
		intent = "High ender of 2,3 (delayable: she can hold it for a beat): the snap-kick foot lands and the rear leg swings a straight-legged outside crescent across the face in a wide arc, arms circling the other way." },
	{ key = "RisingFrontKick", name = "Rising Front Kick", input = "LK", notation = "3", startup = 12, active = 3, recovery = 15, damage = 9, height = "Mid", range = 3.6, width = 1.3, advance = 1.2, push = 0.6, tumble = true, onBlock = -3, onHit = 4, tier = "Light", limb = "LeadLeg", anim = { archetype = "front_kick", side = "Lead", height = "Mid" },
		intent = "Lead front kick rising from the low stance: knee up, toes pointed, snaps to the stomach and back, rear palm forward. TUMBLE: on an airborne opponent the rising kick flips the body over in the air." },
	{ key = "HighKick", name = "Whip Kick", input = "RK", notation = "4", stanceCancel = "Coil", startup = 13, active = 3, recovery = 18, damage = 12, height = "High", range = 4.55, width = 2.2, track = 3, advance = 0.65, push = 0.8, onBlock = -7, onHit = 5, tier = "Medium", limb = "RearLeg", anim = { archetype = "roundhouse", side = "Rear", height = "High" },
		intent = "Whipping rear roundhouse to the head, light and fast: the knee leads, the lower leg whips at the end, arms circle for balance." },
	{ key = "LowSpin", name = "Low Spin Kick", input = "d+LK", notation = "d+3", startup = 13, active = 2, recovery = 18, damage = 8, height = "Low", range = 4.0, width = 1.4, track = 1, crouching = true, push = 0.3, onBlock = -11, onHit = 4, tier = "Light", limb = "LeadLeg", anim = { archetype = "sweep", side = "Lead", height = "Low", crouch = true, spin = 0.25 },
		intent = "Sinks into a low crouch and the lead leg sweeps a short quick arc into the shin, hands near the floor, stays crouched." },
	{ key = "RisingTornado", name = "Rising Whirlwind", input = "d+LK, RK", notation = "d+3,4", chainFrom = "LowSpin", startup = 20, active = 3, recovery = 24, damage = 12, height = "Mid", range = 3.1, width = 1.4, track = 1.5, advance = 1.5, push = 0.6, onBlock = -15, onHit = "LAUNCH", tier = "Launch", limb = "RearLeg", anim = { archetype = "rising_kick", side = "Rear", height = "Mid", spin = 1.0 },
		intent = "From the low spin she rises while turning, the rear leg kicks upward in a spiral under the chin, body spirals up onto the toes. Combos from the low spin on hit (a low-starter launcher); on block there is a gap to interrupt it." },
	{ key = "RisingPalm", name = "Rising Palm Uppercut", input = "db+RP", notation = "db+2", startup = 15, active = 3, recovery = 22, damage = 13, height = "Mid", range = 3.2, width = 1.2, advance = 0.9, push = 0.6, props = { highCrush = { 1, 7 } }, onBlock = -14, onHit = "LAUNCH", tier = "Launch", limb = "RearArm", anim = { archetype = "uppercut", side = "Rear", height = "Mid", crouch = true },
		intent = "From a crouch, the rear palm drives straight up under the chin while the legs extend, lead hand pulls down, she rises onto the toes." },
	{ key = "ButterflyKick", name = "Butterfly Kick", input = "f+RK", notation = "f+4", startup = 18, active = 4, recovery = 22, damage = 16, height = "Mid", range = 3.85, width = 1.6, track = 1.5, advance = 1.15, push = 1.4, props = { lowCrush = { 6, 16 } }, onBlock = -10, onHit = "KND", tier = "Heavy", limb = "RearLeg", anim = { archetype = "butterfly_kick", side = "Rear", height = "Mid", hop = 1.0, spin = 1.0 },
		intent = "Torso drops horizontal and she spins in the air with both legs scissoring outward (butterfly kick), the rear leg striking the chest; feet leave the floor (low crush)." },
	{ key = "Backfist", name = "Snapping Backfist", input = "b+RP", notation = "b+2", stanceCancel = "Coil", startup = 12, active = 3, recovery = 15, damage = 9, height = "High", range = 3.0, width = 2.0, track = 3, advance = 1.6, push = 0.6, onBlock = -3, onHit = 6, tier = "Light", limb = "RearArm", anim = { archetype = "backfist", side = "Rear", height = "High" },
		intent = "Short snapping backfist with the rear hand across the body to the temple, elbow leads, wrist flicks, quick recoil." },
	{ key = "LowSweep", name = "Floor Sweep", input = "COIL+d+RK", notation = "COIL+d+4", stance = "Coil", startup = 19, active = 4, recovery = 24, damage = 14, height = "Low", range = 3.9, width = 2.4, track = 2, advance = 0.5, crouching = true, push = 0.3, onBlock = -16, onHit = "KND", tier = "Heavy", limb = "RearLeg", anim = { archetype = "sweep", side = "Rear", height = "Low", crouch = true, spin = 1.0 },
		intent = "From the Coil (holding down): she drops into a full crouch on one leg and the wound-up body releases into a full circle, the other leg sweeping flat along the floor (front sweep), hands on the floor; knockdown." },
	{ key = "Elbow", name = "Stepping Elbow", input = "f+LP", notation = "f+1", startup = 13, active = 3, recovery = 15, damage = 12, height = "Mid", range = 2.8, width = 1.3, track = 1.5, advance = 1.2, push = 1.0, onBlock = -3, onHit = 6, tier = "Medium", limb = "LeadArm", anim = { archetype = "elbow", side = "Lead", height = "Mid", lunge = 0.6 },
		intent = "Stomping step forward with a lead elbow driven horizontally into the chest, rear palm pushing the elbow (supported elbow), low stance." },
	{ key = "TornadoKick", name = "Cyclone Kick", input = "ss+RK", notation = "ss+4", startup = 16, active = 3, recovery = 22, damage = 15, height = "High", range = 3.75, width = 2.6, homing = true, advance = 1.35, push = 1.2, onBlock = -9, onHit = "KND", tier = "Heavy", limb = "RearLeg", anim = { archetype = "tornado_kick", side = "Rear", height = "High", spin = 1.0 },
		intent = "From a sidestep, a jumping 360-degree spinning kick: she turns her back, jumps, and the rear leg whips a flat circle at head height that follows the opponent." },
	{ key = "Coil", name = "Coil", input = "LK+RK", notation = "3+4", toStance = "Coil", noHit = true, startup = 6, active = 1, recovery = 1, damage = 0, height = "Mid", range = 2.6, width = 1.2, push = 0, onBlock = 0, onHit = 0, tier = "Light", limb = "Body", anim = { archetype = "parry", side = "Lead", height = "Mid", stance = true },
		intent = "SIGNATURE stance entry (no strike): she winds her whole body like a spring: the shoulders turn away from the opponent, the rear foot pivots, both palms circle in front of her and draw back to the hip, knees bent low (see the stance)." },
	{ key = "CoilWhirl", name = "Whirl Kick", input = "COIL+RK", notation = "COIL+4", stance = "Coil", startup = 12, active = 3, recovery = 18, damage = 10, height = "Mid", range = 3.9, width = 2.2, track = 3, advance = 0.5, push = 0.6, onBlock = -6, onHit = 3, tier = "Medium", limb = "RearLeg", anim = { archetype = "spin_kick", side = "Rear", height = "Mid", spin = 1.0 },
		intent = "The coil releases: she unwinds a full turn on the lead foot and the rear heel whips around into the ribs (spinning heel kick at waist height), arms flung wide. First hit of the whirl (4,4,4)." },
	{ key = "CoilWhirl2", name = "Whirl Kick Second", input = "COIL+RK, RK", notation = "COIL+4,4", chainFrom = "CoilWhirl", delay = 20, startup = 14, active = 3, recovery = 18, damage = 10, height = "High", range = 4.0, width = 2.4, track = 3, advance = 0.4, push = 0.6, onBlock = -7, onHit = 4, tier = "Medium", limb = "RearLeg", anim = { archetype = "tornado_kick", side = "Rear", height = "High", spin = 1.0 },
		intent = "Second hit of the whirl (delayable): the spin keeps going, she hops off the lead foot and the same leg whips a flat circle at head height in the air, landing facing the opponent." },
	{ key = "CoilWhirl3", name = "Whirl Kick Finish", input = "COIL+RK, RK, RK", notation = "COIL+4,4,4", chainFrom = "CoilWhirl2", delay = 20, startup = 17, active = 3, recovery = 24, damage = 13, height = "Mid", range = 4.0, width = 2.4, track = 2, advance = 0.6, push = 1.6, onBlock = -13, onHit = "KND", tier = "Heavy", limb = "RearLeg", anim = { archetype = "spin_kick", side = "Rear", height = "Mid", spin = 1.0 },
		intent = "Third hit of the whirl (delayable): a last, lower, heavier spinning heel kick into the stomach that knocks the opponent down; she finishes the turn crouched with one palm forward." },
	{ key = "Throw", name = "Spinning Arm Toss", input = "LP+LK", notation = "1+3", startup = 12, active = 2, recovery = 34, damage = 17, height = "Throw", range = 3.2, width = 1.4, breakWindow = 20, breakButton = "LeadPunch", duration = 46, impactFrame = 32, tier = "Heavy", limb = "Body", anim = { archetype = "arm_toss" },
		intent = "Catches the opponent's wrist for an arm wheel: draws the wrist down, circles it up and cuts it back over the shoulder, and they fall onto their back." },
	{ key = "ThrowB", name = "Twisting Hip Toss", input = "RP+RK", notation = "2+4", startup = 12, active = 2, recovery = 34, damage = 18, height = "Throw", range = 3.2, width = 1.4, breakWindow = 20, breakButton = "RearPunch", duration = 46, impactFrame = 32, tier = "Heavy", limb = "Body", anim = { archetype = "hip_toss" },
		intent = "Palms on the opponent's chest and hip, she sinks, twists her whole body and uproots them, tossing them in a spiral onto the floor." },
	ultimate({ name = "Monsoon", startup = 19, active = 3, recovery = 29, damage = 32, range = 3.8, advance = 1.0, onBlock = -15, limb = "RearArm", anim = { archetype = "palm", side = "Rear", height = "Mid", lunge = 0.8 },
		cinematic = { duration = 260, impacts = { { frame = 30, share = 0.08 }, { frame = 66, share = 0.12 }, { frame = 104, share = 0.14 }, { frame = 146, share = 0.16 }, { frame = 190, share = 0.18 }, { frame = 240, share = 0.32 } }, endKind = "FaceUp", endDistance = 4.6,
			beats = {
				"f0 (the hit): an armored spinning palm strike to the chest; the opponent is rocked back and Nia flows in close.",
				"f30 impact 1: a double palm strike to the chest (both palms together); the defender's torso is pushed back.",
				"f66 impact 2: she turns and a spinning back-hand chop lands on the side of the neck; the defender's head jerks sideways.",
				"f104 impact 3: she drops into a low spinning sweep; the defender's legs are taken and it floats up, horizontal.",
				"f146 impact 4: she spirals up with a rising spiral kick under the floating body, lifting it higher.",
				"f190 impact 5: in the air at the top, a whirlwind kick (two legs whipping in one turn) across the floating body.",
				"f240 impact 6: she lands, sinks low and blasts a focused two-palm push into the falling defender; it slides across the floor onto its back (FaceUp, 4.6 studs away). Nia finishes in a low stance, palms forward, breathing out.",
			} },
		intent = "ULTIMATE (Surge only, once per round) 'Monsoon': an armored spinning palm strike opens it; on hit the cinematic plays the beats in movesets.md (double palm, spinning chop, sweep, spiral kick, mid-air whirl, two-palm push)." }),
}, {
	combos = {
		{ name = "Palm Lift Flurry", kind = "launch", notation = "db+2, 1, 3, 2,3", damage = 31, difficulty = 3, steps = { { wait = 0, input = "db+2" }, { wait = 32, input = "1" }, { wait = 23, input = "3" }, { wait = 29, input = "2" }, { wait = 8, input = "3" } } },
		{ name = "Coil Whirl", kind = "stance", notation = "db+2, 4, 3+4, COIL+4,4", damage = 32, difficulty = 4, steps = { { wait = 0, input = "db+2" }, { wait = 32, input = "4" }, { wait = 15, input = "3+4" }, { wait = 8, input = "COIL+4" }, { wait = 6, input = "4" } } },
		{ name = "Whirlwind Rise", kind = "low", notation = "d+3,4, 4, 3+4, COIL+4,4", damage = 39, difficulty = 4, steps = { { wait = 0, input = "d+3" }, { wait = 3, input = "4" }, { wait = 50, input = "4" }, { wait = 15, input = "3+4" }, { wait = 8, input = "COIL+4" }, { wait = 6, input = "4" } } },
		{ name = "Monsoon Finish", kind = "ultimate", notation = "d+3,4, 1+2", damage = 44, difficulty = 3, surge = true, steps = { { wait = 0, input = "d+3" }, { wait = 3, input = "4" }, { wait = 50, input = "1+2" } } },
	},
	signature = { kind = "stance", key = "Coil", name = "Coil", summary = "3+4: wind the body like a spring. COIL+4 starts the whirl: three spinning kicks (COIL+4,4,4: mid, high, mid knockdown) whose 2nd and 3rd hits can be delayed; COIL+d+4 floor sweep. Cancel 4 / 2,3 / b+2 into it; hold back to leave." },
	stances = {
		{ key = "Coil", name = "Coil", tag = "COIL", entryFrames = 6, cancelFrom = 6, backExit = 8, maxFrames = 50, counterHit = true,
			entryIntent = "Shoulders turn away, the rear foot pivots, the palms circle and draw back (6 frames).",
			intent = "Coil loop: a low, wound-up stance with the shoulders turned away from the opponent (back half turned), weight on the lead foot, both palms drawn back at the hip and slowly circling, the head looking over the lead shoulder. No guard (hits are counter hits).",
			exitIntent = "Unwinds back to the open kung fu stance, palms forward.", },
	},
})

-- ROSTER FOOTER
Roster.order = { "Kael", "Sierra", "Goran", "Lumi", "Rhys", "Nia" } :: { string }
Roster.characters = characters
Roster.stanceStyles = { boxer = "upright, high tight guard, light bounce on the balls of the feet, narrow stance, chin tucked", kickboxer = "bladed, mid-high guard, rhythmic weight shift front-back, lead foot light", grappler = "wide low base, knees deep, hands open and forward at chest height, heavy slow sway", flow = "loose low stance, constant side-to-side sway with relaxed arms, springy knees", karate = "long front stance, lead hand extended forward at chest height, rear fist chambered near the ribs, very still", kungfu = "low wide stance, lead open palm forward, rear palm guarding the chest, slow circular hand flow" } :: { [string]: string }
Roster.stages = { { id = "MidnightRooftop", displayName = "MIDNIGHT ROOFTOP" }, { id = "TrainingBay", displayName = "TRAINING BAY" }, { id = "HarborDusk", displayName = "HARBOR DUSK" }, { id = "JungleRuins", displayName = "JUNGLE RUINS" }, { id = "SnowSummit", displayName = "SUMMIT OBSERVATORY" } } :: { StageDef }
-- Renamed/removed move keys since OV5 (presentation lookups should use these maps).
Roster.renamedKeys = { Nia = { DragonUppercut = "RisingPalm", CraneKick = "RisingFrontKick" }, Sierra = { SupermanPunch = "HopCross" } } :: { [string]: { [string]: string } }
Roster.removedKeys = { Kael = { "FlickerJab", "StepHook" } } :: { [string]: { string } }

function Roster.has(id: string): boolean
	return characters[id] ~= nil
end

function Roster.get(id: string): CharacterDef
	local def = characters[id]
	if not def then error("Roster: unknown character " .. tostring(id)) end
	return def
end

function Roster.getMove(id: string, key: string): MoveDef
	local m = Roster.get(id).moves[key]
	if not m then error("Roster: " .. id .. " has no move " .. tostring(key)) end
	return m
end

-- Total frames of a move (startup + active + recovery).
function Roster.totalFrames(m: MoveDef): number
	return m.startup + m.active + m.recovery
end

-- Signature stance of a character by key (nil when it has none).
function Roster.stance(id: string, key: string?): StanceDef?
	if key == nil then return nil end
	local c = characters[id]
	return if c then c.stances[key] else nil
end

-- The character's Ultimate (every character has one, key "Ultimate").
function Roster.ultimate(id: string): MoveDef
	return Roster.getMove(id, "Ultimate")
end

-- Threat range from the attacker's starting position (reach plus forward travel).
function Roster.threatRange(m: MoveDef): number
	return m.range + m.advance
end

return Roster
