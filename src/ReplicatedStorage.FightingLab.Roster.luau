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
export type AnimHint = { archetype: string, side: string?, height: string?, crouch: boolean?, spin: number?, hop: number?, lunge: number? }
export type Parry = { window: { number }, heights: { string }, stagger: number }
export type Props = { highCrush: { number }?, lowCrush: { number }?, armor: { number }?, parry: Parry? }
export type MoveDef = {
	key: string, name: string, input: string, notation: string, chainFrom: string?, startup: number, impact: number, active: number, recovery: number,
	damage: number, height: string, range: number, width: number, push: number, advance: number, track: number, homing: boolean,
	smid: boolean, crouching: boolean, onBlock: number, onHit: number | string, onCounter: (number | string)?, tier: string, limb: string,
	props: Props, anim: AnimHint, intent: string, tags: { [string]: boolean },
	breakWindow: number?, duration: number?, impactFrame: number?, breakButton: string?,
}
export type Stats = {
	maxHealth: number, walkSpeed: number, backSpeed: number, sideSpeed: number, dashSpeed: number, dashDistance: number,
	dashFrames: number, backdashDistance: number, backdashFrames: number, sidestepArc: number, weight: number, height: number,
	preferredRange: number,
}
export type CharacterDef = { id: string, displayName: string, style: string, stanceStyle: string, tagline: string, intro: string, victory: { string }, stats: Stats, look: string, primaryColor: Color3, accentColor: Color3, moves: { [string]: MoveDef }, moveOrder: { string } }
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
	m.props = m.props or {}
	m.intent = m.intent or ""
	m.notation = m.notation or m.input
	if m.homing and m.track < 8 then m.track = 10 end
	local tags: { [string]: boolean } = {}
	if m.height == "Throw" then tags.throw = true
	else
		if m.chainFrom then tags.followup = true end
		if m.onHit == "LAUNCH" then tags.launcher = true end
		if m.height == "Low" then tags.low = true end
		if m.height == "Mid" then tags.mid = true end
		if m.height == "High" then tags.high = true end
		if m.homing or m.track >= 2.5 then tags.tracking = true end
		if m.homing then tags.homing = true end
		if m.props.parry then tags.parry = true end
		if m.startup <= 11 and not m.chainFrom then tags.poke = true end
		if m.onHit == "KND" or m.damage >= 15 or m.props.armor then tags.power = true end
	end
	m.tags = tags
	return (m :: any) :: MoveDef
end

local function stats(s: { [string]: number }): Stats
	s.sideSpeed = s.sidestepArc / 16 * 60
	s.dashSpeed = s.dashDistance / s.dashFrames * 60
	return (s :: any) :: Stats
end

local characters: { [string]: CharacterDef } = {}
local function define(c: { [string]: any }, list: { { [string]: any } })
	local moves: { [string]: MoveDef } = {}
	local order: { string } = {}
	for _, m in list do
		local def = move(m)
		assert(moves[def.key] == nil, "duplicate move " .. def.key)
		moves[def.key] = def
		table.insert(order, def.key)
	end
	c.moves = moves
	c.moveOrder = order
	characters[c.id] = (c :: any) :: CharacterDef
end

-- KAEL: street boxer. Fast hands, punch strings, pressure; few but honest kicks.
define({
	id = "Kael", displayName = "KAEL", style = "Street boxing / pressure", stanceStyle = "boxer",
	tagline = "Pressure-forged striker with calm, heavy hands", intro = "Keep your guard up. It won't help.",
	victory = { "That's how the street keeps score.", "Stay down. You earned the rest." },
	stats = stats({ maxHealth = 100, walkSpeed = 5.0, backSpeed = 4.0, dashDistance = 3.0, dashFrames = 14, backdashDistance = 3.0, backdashFrames = 18, sidestepArc = 1.8, weight = 1.0, height = 5.95, preferredRange = 3.6 }),
	look = "Adult man, athletic boxer build, medium-olive skin, tight black cornrows down to the nape; slate heather sleeveless training hoodie with white trim, red satin boxing trunks, burnt-orange leather boxing gloves, sleek black leather high-top boxing boots.",
	primaryColor = Color3.fromRGB(32, 36, 44), accentColor = Color3.fromRGB(238, 105, 48),
}, {
	{ key = "Jab", name = "Jab", input = "LP", notation = "1", startup = 10, active = 2, recovery = 12, damage = 6, height = "High", range = 4.2, width = 1.2, track = 1.5, push = 0.4, onBlock = 1, onHit = 8, tier = "Light", limb = "LeadArm", anim = { archetype = "straight", side = "Lead", height = "High" },
		intent = "Lead-hand jab from a tight high boxing guard: small step of the lead foot, lead shoulder rolls over the chin, fist snaps straight to head height and back to the cheek; rear hand stays glued to the jaw." },
	{ key = "OneTwo", name = "One-Two", input = "LP, RP", notation = "1,2", chainFrom = "Jab", startup = 10, active = 2, recovery = 14, damage = 8, height = "High", range = 3.95, width = 1.2, track = 1.5, advance = 0.65, push = 0.5, onBlock = -2, onHit = 6, tier = "Light", limb = "RearArm", anim = { archetype = "straight", side = "Rear", height = "High" },
		intent = "Rear straight right thrown as the jab returns: rear heel pivots out, hips and shoulders rotate fully, fist extends to head height, weight finishes over the lead knee." },
	{ key = "LiverHook", name = "Lead Liver Hook", input = "LP, RP, LP", notation = "1,2,1", chainFrom = "OneTwo", startup = 14, active = 3, recovery = 20, damage = 12, height = "Mid", range = 3.9, width = 1.8, track = 3, advance = 0.3, push = 0.9, onBlock = -9, onHit = 3, tier = "Medium", limb = "LeadArm", anim = { archetype = "body_hook", side = "Lead", height = "Mid" },
		intent = "Short lead hook to the opponent's right side (liver): level change by bending both knees, lead elbow bent ninety degrees, torso whips from the hips, fist lands at rib height." },
	{ key = "Cross", name = "Straight Right", input = "RP", notation = "2", startup = 11, active = 2, recovery = 14, damage = 9, height = "High", range = 3.6, width = 1.2, track = 1.5, advance = 1.0, push = 0.5, onBlock = -3, onHit = 5, tier = "Light", limb = "RearArm", anim = { archetype = "straight", side = "Rear", height = "High" },
		intent = "Rear straight right from the guard without the jab: rear foot pivots, hip and shoulder drive through, fist extends at chin height, lead hand covers the face." },
	{ key = "CrossHook", name = "Right Into Body Hook", input = "RP, LP", notation = "2,1", chainFrom = "Cross", startup = 13, active = 3, recovery = 18, damage = 11, height = "Mid", range = 3.9, width = 1.8, track = 3, advance = 0.2, push = 0.8, onBlock = -8, onHit = 3, tier = "Medium", limb = "LeadArm", anim = { archetype = "body_hook", side = "Lead", height = "Mid" },
		intent = "After the straight right, the boxer dips slightly and rips a lead hook to the body: weight shifts onto the lead leg, lead hip turns in, forearm horizontal at stomach height." },
	{ key = "Overhand", name = "Overhand Right", input = "f+RP", notation = "f+2", startup = 16, active = 3, recovery = 18, damage = 15, height = "High", range = 3.6, width = 1.6, track = 2, advance = 1.4, push = 1.0, onBlock = -5, onHit = 6, onCounter = "KND", tier = "Heavy", limb = "RearArm", anim = { archetype = "overhand", side = "Rear", height = "High" },
		intent = "Looping overhand right: step in with the lead foot, rear arm arcs up and over the shoulder and comes down onto the head, upper body rolls forward and down to the left, rear heel lifts." },
	{ key = "BodyBlow", name = "Crouching Body Shot", input = "d+RP", notation = "d+2", startup = 14, active = 3, recovery = 17, damage = 12, height = "Mid", range = 3.8, width = 1.4, track = 1.5, advance = 0.3, push = 0.8, crouching = true, onBlock = -6, onHit = 4, tier = "Medium", limb = "RearArm", anim = { archetype = "body_hook", side = "Rear", height = "Mid", crouch = true },
		intent = "From a deep crouch, rear shovel punch to the stomach: knees stay bent, rear shoulder dips, fist travels forward and slightly upward into the body, chin tucked behind the lead glove." },
	{ key = "RisingUppercut", name = "Rising Uppercut", input = "df+RP", notation = "df+2", startup = 15, active = 3, recovery = 22, damage = 14, height = "Mid", range = 3.9, width = 1.2, advance = 0.3, push = 0.6, props = { highCrush = { 1, 7 } }, onBlock = -14, onHit = "LAUNCH", tier = "Launch", limb = "RearArm", anim = { archetype = "uppercut", side = "Rear", height = "Mid", crouch = true },
		intent = "Rear uppercut rising from a crouch: legs explode upward, hips drive up and forward, rear fist travels vertically from waist to above the head, body ends fully extended on the toes." },
	{ key = "WeaveHook", name = "Weaving Hook", input = "b+RP", notation = "b+2", startup = 17, active = 3, recovery = 19, damage = 15, height = "High", range = 3.7, width = 2.4, homing = true, advance = 0.7, push = 0.9, props = { highCrush = { 4, 14 } }, onBlock = -9, onHit = 4, tier = "Heavy", limb = "LeadArm", anim = { archetype = "weave_hook", side = "Lead", height = "High" },
		intent = "Upper body weaves down and under (U-shaped bob) then comes up with a wide lead hook to the head; the hook sweeps horizontally and turns with the opponent (homing), head stays low until the punch fires." },
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
	{ key = "Throw", name = "Clinch Headbutt", input = "LP+LK", notation = "1+3", startup = 12, active = 2, recovery = 34, damage = 18, height = "Throw", range = 3.2, width = 1.4, breakWindow = 20, breakButton = "LeadPunch", duration = 46, impactFrame = 30, tier = "Heavy", limb = "Body", anim = { archetype = "clinch_strike" },
		intent = "Both hands grab the back of the opponent's neck (collar tie), pull the head down, two short knees to the body, then shove them away so they fall on their back." },
	{ key = "ThrowB", name = "Over-Under Toss", input = "RP+RK", notation = "2+4", startup = 12, active = 2, recovery = 34, damage = 19, height = "Throw", range = 3.2, width = 1.4, breakWindow = 20, breakButton = "RearPunch", duration = 48, impactFrame = 32, tier = "Heavy", limb = "Body", anim = { archetype = "hip_toss" },
		intent = "Over-under body lock: rear arm under the opponent's armpit, lead arm over the shoulder, then a hip lift and dump in front onto their back." },
})

-- SIERRA: kickboxer. Range control with long kicks, teeps and clean angles.
define({
	id = "Sierra", displayName = "SIERRA", style = "Kickboxing / range control", stanceStyle = "kickboxer",
	tagline = "Precision kickboxer with clean angles and fast exits", intro = "Find your range. I already found mine.",
	victory = { "Angles beat anger every time.", "Clean work. Next." },
	stats = stats({ maxHealth = 95, walkSpeed = 5.4, backSpeed = 4.4, dashDistance = 3.3, dashFrames = 14, backdashDistance = 3.2, backdashFrames = 18, sidestepArc = 1.9, weight = 1.05, height = 5.85, preferredRange = 4.4 }),
	look = "Adult woman, lean kickboxer build, fair skin, platinum high ponytail with swept fringe; teal striped training tank over a black sports bra, deep-teal satin kickboxing trunks with black waistband, brown leather boxing gloves, barefoot.",
	primaryColor = Color3.fromRGB(34, 48, 58), accentColor = Color3.fromRGB(77, 219, 205),
}, {
	{ key = "Jab", name = "Range Jab", input = "LP", notation = "1", startup = 10, active = 2, recovery = 12, damage = 5, height = "High", range = 3.95, width = 1.2, track = 1.5, advance = 0.25, push = 0.4, onBlock = 1, onHit = 8, tier = "Light", limb = "LeadArm", anim = { archetype = "straight", side = "Lead", height = "High" },
		intent = "Long lead jab from a bladed kickboxing stance: lead foot slides forward, arm fully extends at head height, rear glove at the cheek, quick return." },
	{ key = "JabKick", name = "Jab Into Teep", input = "LP, LK", notation = "1,3", chainFrom = "Jab", startup = 14, active = 3, recovery = 18, damage = 11, height = "Mid", range = 3.75, width = 1.3, advance = 1.35, push = 1.0, onBlock = -7, onHit = 3, tier = "Medium", limb = "LeadLeg", anim = { archetype = "teep", side = "Lead", height = "Mid" },
		intent = "As the jab retracts, the lead knee lifts and the ball of the foot pushes straight into the stomach (teep); hips thrust forward, upper body leans back, arms stay high." },
	{ key = "Cross", name = "Snapping Cross", input = "RP", notation = "2", startup = 11, active = 2, recovery = 14, damage = 9, height = "High", range = 3.8, width = 1.2, track = 1.5, advance = 0.8, push = 0.5, onBlock = -3, onHit = 5, tier = "Light", limb = "RearArm", anim = { archetype = "straight", side = "Rear", height = "High" },
		intent = "Rear cross to the head: rear heel turns out, hips rotate, arm extends straight, lead hand drops to cover the chin, snaps back to the bladed guard." },
	{ key = "Teep", name = "Long Teep", input = "LK", notation = "3", startup = 13, active = 3, recovery = 17, damage = 11, height = "Mid", range = 3.8, width = 1.3, advance = 1.4, push = 1.4, onBlock = -5, onHit = 3, tier = "Medium", limb = "LeadLeg", anim = { archetype = "teep", side = "Lead", height = "Mid" },
		intent = "Lead-leg push kick at full length: knee chambers high, hips drive the sole of the foot into the belly, supporting foot rises onto the ball, arms hold a high guard." },
	{ key = "TeepKick", name = "Teep Into High Kick", input = "LK, RK", notation = "3,4", chainFrom = "Teep", startup = 16, active = 3, recovery = 20, damage = 12, height = "High", range = 5.2, width = 2.2, track = 3, advance = 0.3, push = 0.8, onBlock = -9, onHit = 4, tier = "Medium", limb = "RearLeg", anim = { archetype = "roundhouse", side = "Rear", height = "High" },
		intent = "The teep foot lands forward and the rear leg immediately whips a roundhouse to the head; full hip rotation, rear arm swings down, kick turns over at head height." },
	{ key = "HighRoundhouse", name = "Head Roundhouse", input = "RK", notation = "4", startup = 14, active = 3, recovery = 20, damage = 13, height = "High", range = 4.5, width = 2.2, track = 3, advance = 0.9, push = 0.8, onBlock = -8, onHit = 5, tier = "Medium", limb = "RearLeg", anim = { archetype = "roundhouse", side = "Rear", height = "High" },
		intent = "Rear-leg roundhouse to the head (Muay Thai style): lead foot pivots on the ball, hips turn over completely, shin swings in a flat arc at head height, rear arm swings back." },
	{ key = "DoubleRoundhouse", name = "Double Roundhouse", input = "RK, RK", notation = "4,4", chainFrom = "HighRoundhouse", startup = 16, active = 3, recovery = 24, damage = 12, height = "Mid", range = 4.35, width = 2.2, track = 3, advance = 0.85, push = 1.2, onBlock = -12, onHit = "KND", tier = "Heavy", limb = "RearLeg", anim = { archetype = "roundhouse", side = "Rear", height = "Mid" },
		intent = "Without planting, the same rear leg chambers again and fires a second roundhouse to the ribs; supporting leg hops slightly to re-balance, arms counter-swing." },
	{ key = "SpinningBackKick", name = "Spinning Back Kick", input = "b+RK", notation = "b+4", startup = 17, active = 3, recovery = 22, damage = 17, height = "Mid", range = 4.25, width = 1.3, advance = 1.15, push = 2.2, onBlock = -8, onHit = "KND", tier = "Heavy", limb = "RearLeg", anim = { archetype = "spinning_back_kick", side = "Rear", height = "Mid", spin = 0.5 },
		intent = "Turn the back to the opponent (head looks over the shoulder), rear leg chambers and thrusts straight back heel-first into the stomach, then the body completes the turn back to stance." },
	{ key = "KneeStrike", name = "Driving Knee", input = "f+LK", notation = "f+3", startup = 14, active = 3, recovery = 17, damage = 13, height = "Mid", range = 2.8, width = 1.3, track = 1.5, advance = 1.6, push = 1.0, onBlock = -5, onHit = 5, tier = "Medium", limb = "LeadLeg", anim = { archetype = "knee", side = "Lead", height = "Mid", lunge = 0.6 },
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
	{ key = "Throw", name = "Clinch Knees", input = "LP+LK", notation = "1+3", startup = 12, active = 2, recovery = 34, damage = 17, height = "Throw", range = 3.2, width = 1.4, breakWindow = 20, breakButton = "LeadPunch", duration = 48, impactFrame = 34, tier = "Heavy", limb = "Body", anim = { archetype = "clinch_knees" },
		intent = "Double collar tie (both hands behind the head), pull down, two alternating knees to the chest, then twist and dump the opponent to the floor." },
	{ key = "ThrowB", name = "Clinch Trip", input = "RP+RK", notation = "2+4", startup = 12, active = 2, recovery = 34, damage = 18, height = "Throw", range = 3.2, width = 1.4, breakWindow = 20, breakButton = "RearPunch", duration = 46, impactFrame = 30, tier = "Heavy", limb = "Body", anim = { archetype = "arm_toss" },
		intent = "Underhook the arm, step across and sweep the opponent's lead leg with the rear leg while turning the shoulders; the opponent spins and lands on their back." },
})

-- GORAN: heavyweight grappler. Armored charges, big throws, slow but heavy strikes.
define({
	id = "Goran", displayName = "GORAN", style = "Heavyweight grappling / armored pressure", stanceStyle = "grappler",
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
	{ key = "Hammer", name = "Hammer Fist", input = "RP", notation = "2", startup = 14, active = 3, recovery = 18, damage = 13, height = "Mid", range = 4.0, width = 1.4, track = 1.5, advance = 0.2, push = 0.9, onBlock = -5, onHit = 4, tier = "Medium", limb = "RearArm", anim = { archetype = "hammer_fist", side = "Rear", height = "Mid" },
		intent = "Rear arm swings up and over like an axe and the bottom of the fist smashes down onto the shoulder/chest; whole body drops with the strike." },
	{ key = "DoubleHammer", name = "Double Hammer", input = "RP, RP", notation = "2,2", chainFrom = "Hammer", startup = 17, active = 3, recovery = 24, damage = 14, height = "Mid", range = 4.0, width = 1.5, track = 1.5, advance = 0.3, push = 1.6, onBlock = -13, onHit = "KND", tier = "Heavy", limb = "LeadArm", anim = { archetype = "hammer_fist", side = "Lead", height = "Mid" },
		intent = "The lead arm follows with a second overhead hammer fist, both shoulders driving down, a step forward into it that flattens the opponent." },
	{ key = "ShoulderTackle", name = "Shoulder Charge", input = "f+RP", notation = "f+2", startup = 18, active = 4, recovery = 20, damage = 18, height = "Mid", range = 2.8, width = 1.5, track = 1, advance = 2.2, push = 2.0, props = { armor = { 6, 17 } }, onBlock = -10, onHit = "KND", tier = "Heavy", limb = "Body", anim = { archetype = "shoulder_tackle", side = "Lead", height = "Mid", lunge = 1.4 },
		intent = "Lowers the lead shoulder, tucks the chin and charges two steps forward, ramming the shoulder into the chest; absorbs one hit while charging (armor)." },
	{ key = "Uppercut", name = "Lifting Uppercut", input = "df+RP", notation = "df+2", startup = 16, active = 3, recovery = 24, damage = 15, height = "Mid", range = 3.9, width = 1.2, advance = 0.2, push = 0.6, props = { highCrush = { 1, 8 } }, onBlock = -15, onHit = "LAUNCH", tier = "Launch", limb = "RearArm", anim = { archetype = "uppercut", side = "Rear", height = "Mid", crouch = true },
		intent = "Squat down, then a huge rear uppercut lifts from the floor to above the head, legs and hips extending, lifting the opponent off their feet." },
	{ key = "KneeLift", name = "Knee Lift", input = "f+LK", notation = "f+3", startup = 14, active = 3, recovery = 18, damage = 13, height = "Mid", range = 2.8, width = 1.3, track = 1.5, advance = 1.2, push = 1.0, onBlock = -5, onHit = 5, tier = "Medium", limb = "LeadLeg", anim = { archetype = "knee", side = "Lead", height = "Mid" },
		intent = "Both hands reach out to grab, then the lead knee drives up into the stomach as the hands pull down; heavy forward step." },
	{ key = "PushKick", name = "Boot Push", input = "LK", notation = "3", startup = 14, active = 3, recovery = 18, damage = 12, height = "Mid", range = 3.8, width = 1.3, advance = 1.2, push = 1.6, onBlock = -4, onHit = 3, tier = "Medium", limb = "LeadLeg", anim = { archetype = "teep", side = "Lead", height = "Mid" },
		intent = "Big flat-footed lead push kick with the boot sole into the belly, upper body leaning back, arms out wide for balance." },
	{ key = "ClubKick", name = "Club Kick", input = "RK", notation = "4", startup = 16, active = 3, recovery = 20, damage = 14, height = "Mid", range = 4.8, width = 2.2, track = 3, advance = 0.2, push = 1.0, onBlock = -8, onHit = 3, tier = "Medium", limb = "RearLeg", anim = { archetype = "roundhouse", side = "Rear", height = "Mid" },
		intent = "Heavy rear-leg body kick thrown like a club: less snap, more weight, hips turn over slowly and the shin lands on the ribs." },
	{ key = "Stomp", name = "Knee Stomp", input = "d+LK", notation = "d+3", startup = 14, active = 3, recovery = 20, damage = 9, height = "Low", range = 3.8, width = 1.3, track = 1, advance = 0.3, push = 0.3, onBlock = -12, onHit = 1, tier = "Medium", limb = "LeadLeg", anim = { archetype = "stomp", side = "Lead", height = "Low" },
		intent = "Lifts the lead knee and stamps the boot down and forward onto the opponent's lead knee/shin; arms stay forward." },
	{ key = "CrouchJab", name = "Low Poke", input = "d+LP", notation = "d+1", startup = 12, active = 2, recovery = 15, damage = 6, height = "Mid", smid = true, range = 3.6, width = 1.2, crouching = true, push = 0.5, onBlock = -5, onHit = 3, tier = "Light", limb = "LeadArm", anim = { archetype = "straight", side = "Lead", height = "Low", crouch = true },
		intent = "From a squat, a short stiff lead punch to the stomach; stays crouched, other hand forward." },
	{ key = "LegHook", name = "Leg Hook Sweep", input = "d+RK", notation = "d+4", startup = 21, active = 4, recovery = 24, damage = 16, height = "Low", range = 3.8, width = 2.2, track = 2, advance = 0.5, crouching = true, push = 0.3, onBlock = -17, onHit = "KND", tier = "Heavy", limb = "RearLeg", anim = { archetype = "sweep", side = "Rear", height = "Low", crouch = true },
		intent = "Drops onto the lead knee and hooks the rear leg around the opponent's ankles, reaping them off their feet; heavy body rotation." },
	{ key = "Haymaker", name = "Wide Haymaker", input = "b+RP", notation = "b+2", startup = 18, active = 3, recovery = 19, damage = 17, height = "High", range = 3.95, width = 2.6, homing = true, advance = 0.55, push = 1.0, onBlock = -9, onHit = 5, tier = "Heavy", limb = "RearArm", anim = { archetype = "hook", side = "Rear", height = "High" },
		intent = "Huge looping rear hook to the head, wound up from behind the hip; the arc sweeps wide and follows a sidestepping opponent (homing)." },
	{ key = "Bulldozer", name = "Bulldozer", input = "dash+RP", notation = "f,f+2", startup = 20, active = 4, recovery = 22, damage = 22, height = "Mid", range = 2.8, width = 1.5, track = 1, advance = 3.0, push = 2.4, props = { armor = { 4, 19 } }, onBlock = -12, onHit = "KND", tier = "Heavy", limb = "Body", anim = { archetype = "shoulder_tackle", side = "Lead", height = "Mid", lunge = 2.0 },
		intent = "Out of a dash, a running double-handed shove/shoulder ram: three heavy running steps, arms forward, absorbs a hit (armor), and bowls the opponent over." },
	{ key = "Throw", name = "Bear Hug Toss", input = "LP+LK", notation = "1+3", startup = 12, active = 2, recovery = 34, damage = 18, height = "Throw", range = 3.2, width = 1.4, breakWindow = 20, breakButton = "LeadPunch", duration = 50, impactFrame = 36, tier = "Heavy", limb = "Body", anim = { archetype = "bear_hug_toss" },
		intent = "Wraps both arms around the opponent's waist, lifts them off the floor with a hip thrust, turns and tosses them face-up in front of him." },
	{ key = "ThrowB", name = "Belly Suplex", input = "RP+RK", notation = "2+4", startup = 12, active = 2, recovery = 34, damage = 20, height = "Throw", range = 3.2, width = 1.4, breakWindow = 20, breakButton = "RearPunch", duration = 52, impactFrame = 38, tier = "Heavy", limb = "Body", anim = { archetype = "slam" },
		intent = "Front body lock, steps in deep, lifts belly to belly, slams forward onto the back." },
	{ key = "RamSlam", name = "Ram Slam", input = "f+LP+LK", notation = "f+1+3", startup = 15, active = 2, recovery = 36, damage = 26, height = "Throw", range = 3.2, width = 1.4, breakWindow = 14, breakButton = "LeadPunch", duration = 58, impactFrame = 42, tier = "Heavy", limb = "Body", anim = { archetype = "slam" },
		intent = "Command grab: lunges forward, scoops the opponent onto his shoulder and drops forward, slamming them flat into the floor (shorter break window)." },
})

-- LUMI: acrobatic freerunner. Mobility, crush moves and tricky angles; light health.
define({
	id = "Lumi", displayName = "LUMI", style = "Acrobatic freerunning", stanceStyle = "flow",
	tagline = "Rooftop freerunner who fights from impossible angles", intro = "Try to keep up. Seriously, try.",
	victory = { "Too slow for the rooftops.", "Gravity's optional. You didn't get the memo." },
	stats = stats({ maxHealth = 90, walkSpeed = 5.7, backSpeed = 4.6, dashDistance = 3.5, dashFrames = 13, backdashDistance = 3.4, backdashFrames = 17, sidestepArc = 2.1, weight = 1.15, height = 5.9, preferredRange = 4.2 }),
	look = "Adult woman, light long-limbed build, deep brown skin, brown eyes, black curly taper with a sports band; olive crop tank, black ribbed techwear arm sleeves, mint slim-fit track pants tucked into black suede split-toe tabi boots, open hands.",
	primaryColor = Color3.fromRGB(35, 40, 48), accentColor = Color3.fromRGB(86, 214, 160),
}, {
	{ key = "Palm", name = "Quick Palm", input = "LP", notation = "1", startup = 10, active = 2, recovery = 12, damage = 5, height = "High", range = 3.95, width = 1.2, track = 1.5, advance = 0.25, push = 0.4, onBlock = 1, onHit = 8, tier = "Light", limb = "LeadArm", anim = { archetype = "palm", side = "Lead", height = "High" },
		intent = "Loose lead palm strike to the face from a bouncy low stance: wrist bent back, heel of the palm snaps forward and back, knees springy." },
	{ key = "PalmHeel", name = "Palm To Spin Heel", input = "LP, RK", notation = "1,4", chainFrom = "Palm", startup = 15, active = 3, recovery = 22, damage = 12, height = "Mid", range = 3.5, width = 1.8, track = 2.5, advance = 1.4, push = 1.0, onBlock = -10, onHit = 3, tier = "Medium", limb = "RearLeg", anim = { archetype = "spin_kick", side = "Rear", height = "Mid", spin = 1.0 },
		intent = "After the palm, she spins a full turn on the lead foot and the rear heel swings around into the ribs (spinning heel kick), arms flung out for momentum." },
	{ key = "SpinBackfist", name = "Spin Backfist", input = "RP", notation = "2", startup = 12, active = 3, recovery = 16, damage = 10, height = "High", range = 3.75, width = 2.0, track = 3, advance = 0.85, push = 0.6, onBlock = -5, onHit = 5, tier = "Medium", limb = "RearArm", anim = { archetype = "spinning_backfist", side = "Rear", height = "High", spin = 1.0 },
		intent = "Quick spin on the lead foot, back turned for a moment, rear arm whips around and the back of the fist hits the side of the head at the end of the turn." },
	{ key = "SnapKick", name = "Snap Kick", input = "LK", notation = "3", startup = 12, active = 3, recovery = 15, damage = 9, height = "Mid", range = 3.8, width = 1.3, advance = 1.0, push = 0.6, onBlock = -4, onHit = 4, tier = "Light", limb = "LeadLeg", anim = { archetype = "front_kick", side = "Lead", height = "Mid" },
		intent = "Fast lead front snap kick to the stomach: knee up, shin snaps out and back like a whip, she bounces on the supporting foot." },
	{ key = "SnapCrescent", name = "Snap Into Crescent", input = "LK, RK", notation = "3,4", chainFrom = "SnapKick", startup = 15, active = 3, recovery = 20, damage = 11, height = "High", range = 3.75, width = 2.2, track = 3, advance = 1.45, push = 0.8, onBlock = -9, onHit = 4, tier = "Medium", limb = "RearLeg", anim = { archetype = "crescent_kick", side = "Rear", height = "High" },
		intent = "The snap kick lands and the rear leg swings a straight-legged outside-to-inside crescent across the head, sweeping arc, arms counter-balance." },
	{ key = "CrescentKick", name = "Crescent Kick", input = "RK", notation = "4", startup = 14, active = 3, recovery = 19, damage = 12, height = "High", range = 3.6, width = 2.4, track = 3, advance = 1.6, push = 0.8, onBlock = -7, onHit = 4, tier = "Medium", limb = "RearLeg", anim = { archetype = "crescent_kick", side = "Rear", height = "High" },
		intent = "Rear-leg crescent kick: straight leg lifts and swings across the face in a wide arc, hips open then close, foot lands back in stance." },
	{ key = "CartwheelKick", name = "Cartwheel Kick", input = "b+LK", notation = "b+3", startup = 18, active = 4, recovery = 20, damage = 15, height = "Mid", range = 3.7, width = 1.6, track = 1.5, advance = 1.5, push = 1.2, props = { highCrush = { 4, 16 } }, onBlock = -9, onHit = "KND", tier = "Heavy", limb = "LeadLeg", anim = { archetype = "cartwheel_kick", side = "Lead", height = "Mid" },
		intent = "Hands go to the floor in a sideways cartwheel (head drops low = high crush) and the lead leg comes over the top into the chest; lands back on her feet." },
	{ key = "FlipKick", name = "Backflip Kick", input = "df+RK", notation = "df+4", startup = 16, active = 3, recovery = 26, damage = 13, height = "Mid", range = 3.1, width = 1.2, advance = 0.9, push = 0.6, props = { lowCrush = { 6, 15 } }, onBlock = -15, onHit = "LAUNCH", tier = "Launch", limb = "RearLeg", anim = { archetype = "flip_kick", side = "Rear", height = "Mid", hop = 1.2 },
		intent = "Standing backflip: the rear foot kicks up under the chin as she flips backwards, feet leave the floor (low crush), lands crouched slightly behind her start." },
	{ key = "SlideKick", name = "Slide Kick", input = "d+RK", notation = "d+4", startup = 18, active = 4, recovery = 24, damage = 13, height = "Low", range = 3.4, width = 1.6, track = 1, advance = 1.8, crouching = true, push = 0.3, props = { highCrush = { 5, 20 } }, onBlock = -16, onHit = "KND", tier = "Heavy", limb = "RearLeg", anim = { archetype = "slide_kick", side = "Rear", height = "Low", crouch = true, lunge = 1.6 },
		intent = "Baseball slide: drops onto the hip and slides feet-first along the floor into the opponent's ankles, rear leg extended, then pops back up." },
	{ key = "QuickLow", name = "Flick Low", input = "d+LK", notation = "d+3", startup = 12, active = 2, recovery = 18, damage = 7, height = "Low", range = 4.0, width = 1.3, track = 1, crouching = true, push = 0.3, onBlock = -11, onHit = 2, tier = "Light", limb = "LeadLeg", anim = { archetype = "low_kick", side = "Lead", height = "Low", crouch = true },
		intent = "From a squat, the lead foot flicks out along the floor into the shin and snaps back; hands near the floor for balance." },
	{ key = "ScissorKick", name = "Scissor Hop Kick", input = "f+RK", notation = "f+4", startup = 16, active = 3, recovery = 20, damage = 14, height = "High", range = 3.5, width = 1.4, track = 1.5, advance = 1.7, push = 1.2, props = { lowCrush = { 5, 14 } }, onBlock = -9, onHit = "KND", tier = "Heavy", limb = "RearLeg", anim = { archetype = "jumping_kick", side = "Rear", height = "High", hop = 0.9 },
		intent = "Jumps off both feet, legs scissor in the air and the rear foot kicks forward at head height; lands on the kicking foot." },
	{ key = "VaultKick", name = "Vault Kick", input = "dash+LK", notation = "f,f+3", startup = 14, active = 3, recovery = 18, damage = 14, height = "Mid", range = 4.1, width = 1.4, track = 1.5, advance = 1.5, push = 1.0, props = { lowCrush = { 3, 12 } }, onBlock = -6, onHit = 4, tier = "Medium", limb = "LeadLeg", anim = { archetype = "jumping_kick", side = "Lead", height = "Mid", hop = 0.7, lunge = 1.0 },
		intent = "Out of a run, she vaults off the rear foot into a flying lead front kick to the chest, body almost horizontal, lands in stance." },
	{ key = "TwirlKick", name = "Twirl Kick", input = "ss+RK", notation = "ss+4", startup = 15, active = 3, recovery = 20, damage = 13, height = "High", range = 3.35, width = 2.6, homing = true, advance = 1.65, push = 0.8, onBlock = -9, onHit = 4, tier = "Medium", limb = "RearLeg", anim = { archetype = "tornado_kick", side = "Rear", height = "High", spin = 1.0 },
		intent = "From a sidestep, a 360-degree turning kick: she spins on the lead foot and the rear leg sweeps a flat circle at head height that tracks the opponent." },
	{ key = "KneeRush", name = "Running Knee", input = "f+LK", notation = "f+3", startup = 13, active = 3, recovery = 17, damage = 12, height = "Mid", range = 2.8, width = 1.3, track = 1.5, advance = 1.6, push = 1.0, onBlock = -4, onHit = 6, tier = "Medium", limb = "LeadLeg", anim = { archetype = "knee", side = "Lead", height = "Mid", lunge = 0.8 },
		intent = "Two quick running steps and a jumping lead knee to the body, arms pumping back, lands on the knee leg." },
	{ key = "Throw", name = "Flip Toss", input = "LP+LK", notation = "1+3", startup = 12, active = 2, recovery = 34, damage = 16, height = "Throw", range = 3.2, width = 1.4, breakWindow = 20, breakButton = "LeadPunch", duration = 46, impactFrame = 32, tier = "Heavy", limb = "Body", anim = { archetype = "flip_toss" },
		intent = "Grabs the opponent's shoulders, springs up and backflips off the opponent's belly, the kick-off drives them onto their back." },
	{ key = "ThrowB", name = "Vault Takedown", input = "RP+RK", notation = "2+4", startup = 12, active = 2, recovery = 34, damage = 17, height = "Throw", range = 3.2, width = 1.4, breakWindow = 20, breakButton = "RearPunch", duration = 46, impactFrame = 30, tier = "Heavy", limb = "Body", anim = { archetype = "arm_toss" },
		intent = "Hooks the neck from the side, springs up and stamps the lead knee; her weight folds them backwards." },
})

-- RHYS: karate counter-striker. Straight mids, a parry, punishes mistakes.
define({
	id = "Rhys", displayName = "RHYS", style = "Karate-based counter striking", stanceStyle = "karate",
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
	{ key = "StraightPunch", name = "Center Punch", input = "RP", notation = "2", startup = 12, active = 3, recovery = 16, damage = 11, height = "Mid", range = 3.8, width = 1.3, track = 1.5, advance = 0.8, push = 0.8, onBlock = -4, onHit = 5, tier = "Medium", limb = "RearArm", anim = { archetype = "straight", side = "Rear", height = "Mid" },
		intent = "Rear reverse punch to the chest from stance (gyaku-zuki): hip rotation first, lead hand chambers back, very straight line, short sharp exhale posture." },
	{ key = "PunchKick", name = "Punch Into High Kick", input = "RP, RK", notation = "2,4", chainFrom = "StraightPunch", startup = 16, active = 3, recovery = 21, damage = 13, height = "High", range = 4.65, width = 2.2, track = 3, advance = 0.55, push = 0.8, onBlock = -9, onHit = 5, tier = "Medium", limb = "RearLeg", anim = { archetype = "roundhouse", side = "Rear", height = "High" },
		intent = "After the center punch, the rear leg fires a snapping roundhouse to the head (mawashi-geri): knee chambers sideways, the instep snaps to the temple, snaps back." },
	{ key = "FrontSnap", name = "Front Snap Kick", input = "LK", notation = "3", startup = 12, active = 3, recovery = 16, damage = 10, height = "Mid", range = 3.8, width = 1.3, advance = 1.0, push = 0.6, onBlock = -3, onHit = 4, tier = "Light", limb = "LeadLeg", anim = { archetype = "front_kick", side = "Lead", height = "Mid" },
		intent = "Lead front snap kick (mae-geri) with the ball of the foot to the stomach: knee lifts high first, shin snaps out, recoils before landing." },
	{ key = "AxeKick", name = "Falling Axe Kick", input = "RK", notation = "4", startup = 19, active = 3, recovery = 18, damage = 16, height = "Mid", range = 3.25, width = 1.4, track = 1.5, advance = 1.65, push = 1.2, onBlock = -2, onHit = "KND", tier = "Heavy", limb = "RearLeg", anim = { archetype = "axe_kick", side = "Rear", height = "Mid" },
		intent = "Rear leg swings straight up above head height and the heel chops down onto the collarbone; body stays upright, arms open for balance." },
	{ key = "Deflect", name = "Deflect", input = "b+LP", notation = "b+1", startup = 3, active = 10, recovery = 22, damage = 0, height = "Mid", range = 2.6, width = 1.6, push = 0, props = { parry = { window = { 4, 13 }, heights = { "High", "Mid" }, stagger = 24 } }, onBlock = 0, onHit = 0, tier = "Light", limb = "LeadArm", anim = { archetype = "parry", side = "Lead", height = "High" },
		intent = "Inside-to-outside sweeping block (uke) with the lead forearm while stepping slightly back; on contact the attacker's arm/leg is knocked aside and they stagger." },
	{ key = "RisingKnee", name = "Rising Knee", input = "df+LK", notation = "df+3", startup = 15, active = 3, recovery = 22, damage = 13, height = "Mid", range = 2.8, width = 1.2, advance = 1.1, push = 0.6, onBlock = -13, onHit = "LAUNCH", tier = "Launch", limb = "LeadLeg", anim = { archetype = "knee", side = "Lead", height = "Mid", crouch = true, hop = 0.4 },
		intent = "From a slight crouch the lead knee drives straight up under the chin with a small jump, both hands pulling down, lifting the opponent." },
	{ key = "LowSweep", name = "Low Reaping Sweep", input = "db+RK", notation = "db+4", startup = 19, active = 4, recovery = 24, damage = 14, height = "Low", range = 3.9, width = 2.4, track = 2, advance = 0.5, crouching = true, push = 0.3, onBlock = -16, onHit = "KND", tier = "Heavy", limb = "RearLeg", anim = { archetype = "sweep", side = "Rear", height = "Low", crouch = true, spin = 0.5 },
		intent = "Drops low on the lead leg, rear leg reaps along the floor in a wide arc at the ankles (ashi-barai style), comes back up in stance." },
	{ key = "LowKick", name = "Low Kick", input = "d+RK", notation = "d+4", startup = 13, active = 2, recovery = 20, damage = 8, height = "Low", range = 4.0, width = 1.4, track = 1, push = 0.3, onBlock = -13, onHit = 1, tier = "Light", limb = "RearLeg", anim = { archetype = "low_kick", side = "Rear", height = "Low" },
		intent = "Short rear-leg low kick to the inside of the knee: quick hip turn, shin chops down, returns to stance immediately." },
	{ key = "LowPunch", name = "Kneeling Punch", input = "d+LP", notation = "d+1", startup = 11, active = 2, recovery = 14, damage = 5, height = "Mid", smid = true, range = 3.8, width = 1.2, crouching = true, push = 0.4, onBlock = -4, onHit = 4, tier = "Light", limb = "LeadArm", anim = { archetype = "straight", side = "Lead", height = "Low", crouch = true },
		intent = "Drops into a low stance and throws a short straight lead punch to the stomach; stays low afterward." },
	{ key = "SpinBackfist", name = "Turning Backfist", input = "b+RP", notation = "b+2", startup = 15, active = 3, recovery = 18, damage = 13, height = "High", range = 4.15, width = 2.6, homing = true, advance = 0.45, push = 0.8, onBlock = -8, onHit = 4, tier = "Medium", limb = "RearArm", anim = { archetype = "spinning_backfist", side = "Rear", height = "High", spin = 1.0 },
		intent = "Steps across and turns his back, the rear backfist whips around in a flat circle to the side of the head, turning with a sidestepping opponent (homing)." },
	{ key = "LungePunch", name = "Lunging Punch", input = "f+RP", notation = "f+2", startup = 16, active = 3, recovery = 20, damage = 16, height = "Mid", range = 3.65, width = 1.3, advance = 1.95, push = 1.2, onBlock = -8, onHit = 5, tier = "Heavy", limb = "RearArm", anim = { archetype = "straight", side = "Rear", height = "Mid", lunge = 1.2 },
		intent = "Long gliding step forward (oi-zuki) covering distance, rear-hand punch to the chest at the end of the slide, body low and straight." },
	{ key = "SideKick", name = "Side Thrust Kick", input = "f+LK", notation = "f+3", startup = 14, active = 3, recovery = 18, damage = 14, height = "Mid", range = 3.85, width = 1.3, advance = 1.45, push = 1.6, onBlock = -6, onHit = 3, tier = "Medium", limb = "LeadLeg", anim = { archetype = "side_kick", side = "Lead", height = "Mid" },
		intent = "Turns sideways, lead knee chambers across the body and the heel thrusts out sideways into the ribs (yoko-geri), body leaning away." },
	{ key = "CrescentStep", name = "Stepping Crescent", input = "ss+RK", notation = "ss+4", startup = 15, active = 3, recovery = 19, damage = 13, height = "Mid", range = 4.25, width = 2.4, track = 4, advance = 0.55, push = 0.8, onBlock = -7, onHit = 4, tier = "Medium", limb = "RearLeg", anim = { archetype = "crescent_kick", side = "Rear", height = "Mid" },
		intent = "From a sidestep, a stepping crescent kick to the ribs: rear leg swings in a wide inward arc at waist height, catching an opponent moving to the side." },
	{ key = "Throw", name = "Hip Throw", input = "LP+LK", notation = "1+3", startup = 12, active = 2, recovery = 34, damage = 18, height = "Throw", range = 3.2, width = 1.4, breakWindow = 20, breakButton = "LeadPunch", duration = 46, impactFrame = 32, tier = "Heavy", limb = "Body", anim = { archetype = "hip_toss" },
		intent = "Grips the sleeve and collar, steps in and takes them down with an outer reap of the lead leg." },
	{ key = "ThrowB", name = "Shoulder Throw", input = "RP+RK", notation = "2+4", startup = 12, active = 2, recovery = 34, damage = 19, height = "Throw", range = 3.2, width = 1.4, breakWindow = 20, breakButton = "RearPunch", duration = 48, impactFrame = 32, tier = "Heavy", limb = "Body", anim = { archetype = "arm_toss" },
		intent = "Arm trap and leg-block takedown, kneeling at the end." },
})

-- NIA: kung-fu-inspired flow fighter. Flowing hand strings and spinning kicks.
define({
	id = "Nia", displayName = "NIA", style = "Kung-fu-inspired whirlwind", stanceStyle = "kungfu",
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
	{ key = "PalmThrust", name = "Palm Thrust", input = "RP", notation = "2", startup = 12, active = 3, recovery = 16, damage = 11, height = "Mid", range = 3.4, width = 1.3, track = 1.5, advance = 1.0, push = 1.2, onBlock = -4, onHit = 5, tier = "Medium", limb = "RearArm", anim = { archetype = "palm", side = "Rear", height = "Mid" },
		intent = "Rear palm thrust to the chest from a low horse-like stance: the hips sink and turn, the heel of the palm pushes forward, the lead hand withdraws to the waist." },
	{ key = "PalmKick", name = "Palm Into Rising Snap Kick", input = "RP, LK", notation = "2,3", chainFrom = "PalmThrust", startup = 14, active = 3, recovery = 19, damage = 11, height = "Mid", range = 3.8, width = 1.3, track = 1.5, advance = 1.0, push = 1.0, onBlock = -8, onHit = 3, tier = "Medium", limb = "LeadLeg", anim = { archetype = "front_kick", side = "Lead", height = "Mid" },
		intent = "The palm withdraws, weight shifts onto the rear leg and the lead foot snaps a front kick into the stomach, then the hands return to a guard as the foot lands back in the low stance." },
	{ key = "RisingFrontKick", name = "Rising Front Kick", input = "LK", notation = "3", startup = 12, active = 3, recovery = 15, damage = 9, height = "Mid", range = 3.6, width = 1.3, advance = 1.2, push = 0.6, onBlock = -3, onHit = 4, tier = "Light", limb = "LeadLeg", anim = { archetype = "front_kick", side = "Lead", height = "Mid" },
		intent = "Lead front kick rising from the low stance: knee up, toes pointed, snaps to the stomach and back, rear palm forward." },
	{ key = "HighKick", name = "Whip Kick", input = "RK", notation = "4", startup = 13, active = 3, recovery = 18, damage = 12, height = "High", range = 4.55, width = 2.2, track = 3, advance = 0.65, push = 0.8, onBlock = -7, onHit = 5, tier = "Medium", limb = "RearLeg", anim = { archetype = "roundhouse", side = "Rear", height = "High" },
		intent = "Whipping rear roundhouse to the head, light and fast: the knee leads, the lower leg whips at the end, arms circle for balance." },
	{ key = "LowSpin", name = "Low Spin Kick", input = "d+LK", notation = "d+3", startup = 13, active = 2, recovery = 18, damage = 8, height = "Low", range = 4.0, width = 1.4, track = 1, crouching = true, push = 0.3, onBlock = -11, onHit = 2, tier = "Light", limb = "LeadLeg", anim = { archetype = "low_kick", side = "Lead", height = "Low", crouch = true },
		intent = "Sinks into a low crouch and the lead leg sweeps a short quick arc into the shin, hands near the floor, stays crouched." },
	{ key = "RisingTornado", name = "Rising Whirlwind", input = "d+LK, RK", notation = "d+3,4", chainFrom = "LowSpin", startup = 22, active = 3, recovery = 24, damage = 12, height = "Mid", range = 3.1, width = 1.4, track = 1.5, advance = 1.5, push = 0.6, onBlock = -15, onHit = "LAUNCH", tier = "Launch", limb = "RearLeg", anim = { archetype = "rising_kick", side = "Rear", height = "Mid", spin = 1.0 },
		intent = "From the low spin she rises while turning, the rear leg kicks upward in a spiral under the chin, body corkscrews up onto the toes (the gap before it can be blocked)." },
	{ key = "RisingPalm", name = "Rising Palm Uppercut", input = "df+RP", notation = "df+2", startup = 15, active = 3, recovery = 22, damage = 13, height = "Mid", range = 3.2, width = 1.2, advance = 0.9, push = 0.6, props = { highCrush = { 1, 7 } }, onBlock = -14, onHit = "LAUNCH", tier = "Launch", limb = "RearArm", anim = { archetype = "uppercut", side = "Rear", height = "Mid", crouch = true },
		intent = "From a crouch, the rear palm drives straight up under the chin while the legs extend, lead hand pulls down, she rises onto the toes." },
	{ key = "ButterflyKick", name = "Butterfly Kick", input = "f+RK", notation = "f+4", startup = 18, active = 4, recovery = 22, damage = 16, height = "Mid", range = 3.85, width = 1.6, track = 1.5, advance = 1.15, push = 1.4, props = { lowCrush = { 6, 16 } }, onBlock = -10, onHit = "KND", tier = "Heavy", limb = "RearLeg", anim = { archetype = "butterfly_kick", side = "Rear", height = "Mid", hop = 1.0, spin = 1.0 },
		intent = "Torso drops horizontal and she spins in the air with both legs scissoring outward (butterfly kick), the rear leg striking the chest; feet leave the floor (low crush)." },
	{ key = "Backfist", name = "Snapping Backfist", input = "b+RP", notation = "b+2", startup = 12, active = 3, recovery = 15, damage = 9, height = "High", range = 3.0, width = 2.0, track = 3, advance = 1.6, push = 0.6, onBlock = -3, onHit = 6, tier = "Light", limb = "RearArm", anim = { archetype = "backfist", side = "Rear", height = "High" },
		intent = "Short snapping backfist with the rear hand across the body to the temple, elbow leads, wrist flicks, quick recoil." },
	{ key = "LowSweep", name = "Floor Sweep", input = "db+RK", notation = "db+4", startup = 19, active = 4, recovery = 24, damage = 14, height = "Low", range = 3.9, width = 2.4, track = 2, advance = 0.5, crouching = true, push = 0.3, onBlock = -16, onHit = "KND", tier = "Heavy", limb = "RearLeg", anim = { archetype = "sweep", side = "Rear", height = "Low", crouch = true, spin = 1.0 },
		intent = "Drops into a full crouch on one leg and spins a full circle with the other leg sweeping flat along the floor (front sweep), hands on the floor." },
	{ key = "Elbow", name = "Stepping Elbow", input = "f+LP", notation = "f+1", startup = 13, active = 3, recovery = 15, damage = 12, height = "Mid", range = 2.8, width = 1.3, track = 1.5, advance = 1.2, push = 1.0, onBlock = -3, onHit = 6, tier = "Medium", limb = "LeadArm", anim = { archetype = "elbow", side = "Lead", height = "Mid", lunge = 0.6 },
		intent = "Stomping step forward with a lead elbow driven horizontally into the chest, rear palm pushing the elbow (supported elbow), low stance." },
	{ key = "TornadoKick", name = "Cyclone Kick", input = "ss+RK", notation = "ss+4", startup = 16, active = 3, recovery = 22, damage = 15, height = "High", range = 3.75, width = 2.6, homing = true, advance = 1.35, push = 1.2, onBlock = -9, onHit = "KND", tier = "Heavy", limb = "RearLeg", anim = { archetype = "tornado_kick", side = "Rear", height = "High", spin = 1.0 },
		intent = "From a sidestep, a jumping 360-degree spinning kick: she turns her back, jumps, and the rear leg whips a flat circle at head height that follows the opponent." },
	{ key = "Throw", name = "Spinning Arm Toss", input = "LP+LK", notation = "1+3", startup = 12, active = 2, recovery = 34, damage = 17, height = "Throw", range = 3.2, width = 1.4, breakWindow = 20, breakButton = "LeadPunch", duration = 46, impactFrame = 32, tier = "Heavy", limb = "Body", anim = { archetype = "arm_toss" },
		intent = "Catches the opponent's wrist for an arm wheel: draws the wrist down, circles it up and cuts it back over the shoulder, and they fall onto their back." },
	{ key = "ThrowB", name = "Twisting Hip Toss", input = "RP+RK", notation = "2+4", startup = 12, active = 2, recovery = 34, damage = 18, height = "Throw", range = 3.2, width = 1.4, breakWindow = 20, breakButton = "RearPunch", duration = 46, impactFrame = 32, tier = "Heavy", limb = "Body", anim = { archetype = "hip_toss" },
		intent = "Palms on the opponent's chest and hip, she sinks, twists her whole body and uproots them, tossing them in a spiral onto the floor." },
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

-- Threat range from the attacker's starting position (reach plus forward travel).
function Roster.threatRange(m: MoveDef): number
	return m.range + m.advance
end

return Roster
