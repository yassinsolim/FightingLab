--!strict
-- Global combat constants (OV6). Roster owns per-character stats and move data; Config exposes derived metadata
-- (legacy Config.Moves aliases) for presentation modules.
local Roster = require(script.Parent.Roster)

local Config = {
	FPS = 60,
	ArenaRadius = 21,
	Separation = 2.6,
	StartDistance = 6.2,
	BlockMultiplier = 0, -- no chip damage: blocking is always safe from damage (spam cannot chip anyone out)
	Hitstop = { Light = 4, Medium = 6, Heavy = 8, Launch = 10, KO = 16, Block = 3, Throw = 8, Parry = 6, Armor = 4, Crush = 3 },
	CounterDamageMultiplier = 1.25,
	CounterStunBonus = 6,
	CounterHitstopBonus = 2,
	-- Input buffering: attacks pressed up to AttackBuffer frames before the fighter can act still come out.
	AttackBuffer = 8,
	StepBuffer = 6,
	-- Two buttons pressed within ChordFrames form a chord (1+3 / 2+4 throws); a move already started by the first
	-- button is upgraded in place while it is no older than ChordFrames.
	ChordFrames = 3,
	-- Tighter windows for the round-6 chords: 1+2 (the Ultimate) needs both presses on the same or the next frame and
	-- 3+4 (the signature) within 2 frames, so quickly typed 1,2 and 3,4 strings stay strings.
	ChordWindow = { Ultimate = 1, Kicks = 2 },
	-- After a successful throw break both fighters stay locked this many frames (break animation), then neutral.
	ThrowBreakFrames = 16,
	LocalAuthority = true,
	SnapshotEvery = 3,
	CommandBudget = 90,
	KOResetFrames = 240,
	-- Footwork (contract 0.1). Distances/frames per fighter live in Roster stats; these are the shared rules.
	DashTapWindow = 14,
	DashAttackFrame = 3,     -- forward dash can be cancelled into an attack from this frame
	DashChainFrame = 11,     -- a new forward dash can start from this frame of the current one
	BackdashMoveFrames = 14, -- backdash travel happens over these frames, the rest is a short settle
	BackdashChainFrame = 15, -- backdashes chain (double-tap back again) from this frame
	BackdashAttackFrame = 12,
	SidestepFrames = 16,     -- discrete sidestep travel
	SidestepRecovery = 6,    -- short recovery after the travel (no guard, can be cancelled into an attack)
	SidestepAttackFrame = 8, -- sidestep can be cancelled into an attack (ss moves) from this frame
	SidestepGuardFrame = 17, -- holding back from this frame ends the sidestep into standing guard
	CrouchSpeed = 0,         -- crouch is stationary
	LaunchVelocity = 19,
	Gravity = 44,
	JuggleVelocity = 9,
	MaxJuggleExtensions = 4,
	MaxAirHits = 4,
	MaxAirFrames = 110,
	AirHitCeiling = 4.5,
	AirDamageScale = 0.7,
	AirDamageDecay = 0.82,
	-- Knockdown: LandingFrames lying on the floor (getup choice is read here), then GetupFrames standing up
	-- (about 1 s from touching the floor to standing, so falls and getups are not rushed).
	-- Both are fully invulnerable; the first actionable frame after a getup is a guarding frame.
	LandingFrames = 34,
	GetupFrames = 26,
	GetupChoiceFrame = 6,
	RollFrames = 10,         -- extra frames for a back/side roll getup
	RollDistance = 2.2,
	RoundFrames = 60 * 60,
	ReadyFrames = 78,
	RoundBreakFrames = 120,
	WinsNeeded = 2,
	TrainerDecisionFrames = 1,
	TrainerAttackFrames = 9,
	Buttons = { "LeadPunch", "RearPunch", "LeadKick", "RearKick", "Throw", "Throw2", "Ultimate", "Kicks" },
	ButtonNotation = { LeadPunch = "LP", RearPunch = "RP", LeadKick = "LK", RearKick = "RK", Throw = "LP+LK", Throw2 = "RP+RK", Ultimate = "LP+RP", Kicks = "LK+RK" },
	-- Chords: two buttons pressed together. 1+3 = throw (break with 1), 2+4 = throw (break with 2), 1+2 = the Ultimate
	-- (only while it is available; otherwise 1 and 2 stay two presses), 3+4 = the fighter's signature (stance / catch).
	Chords = {
		["LeadPunch+LeadKick"] = "Throw", ["LeadKick+LeadPunch"] = "Throw", ["RearPunch+RearKick"] = "Throw2", ["RearKick+RearPunch"] = "Throw2",
		["LeadPunch+RearPunch"] = "Ultimate", ["RearPunch+LeadPunch"] = "Ultimate", ["LeadKick+RearKick"] = "Kicks", ["RearKick+LeadKick"] = "Kicks",
	},
	-- Round 6: Surge (low-health state) and the Ultimate (CONTRACTS-v6.md, Surge and Ultimate).
	SurgeThreshold = 0.25,        -- a fighter at or below this fraction of its max health (and above 0) enters Surge
	SurgeDamageMultiplier = 1.1,  -- damage a Surging fighter deals (not the Free Training permanent Surge)
	UltComboScale = 0.7,          -- Ultimate damage when it lands on an opponent already in a combo or juggle
	-- Tumble: a tumble move hitting an airborne opponent lifts it again (studs/s) and adds one juggle hit.
	TumbleVelocity = 12,
	-- Ground combo scaling: the Nth consecutive ground hit of a combo deals this fraction (natural 3-hit strings are
	-- unscaled); later hits use ComboScaleMin.
	ComboScale = { [4] = 0.85, [5] = 0.75, [6] = 0.65 },
	ComboScaleMin = 0.6,
	DummyModes = { "Stand", "Guard", "Fight" },
	DefaultP1 = "Kael",
	DefaultP2 = "Sierra",
	DefaultStage = "MidnightRooftop",
}

local function cloneMove(id: string, key: string): { [string]: any }
	local source = Roster.getMove(id, key)
	local activeRecovery = source.active + source.recovery - 1
	local copy = table.clone((source :: any) :: { [string]: any })
	copy.stun = if typeof(source.onHit) == "number" then (source.onHit :: number) + activeRecovery else Config.LandingFrames + Config.GetupFrames
	copy.blockStun = (source.onBlock or 0) + activeRecovery
	copy.launch = source.onHit == "LAUNCH"
	copy.color = if source.tier == "Light" then Color3.fromRGB(80, 220, 255) elseif source.tier == "Medium" then Color3.fromRGB(110, 230, 155) elseif source.tier == "Launch" then Color3.fromRGB(255, 210, 85) else Color3.fromRGB(255, 160, 60)
	copy.label = source.name
	return copy
end

local Moves: { [string]: { [string]: any } } = {}
local MoveOrder: { string } = {}
for _, id in Roster.order do
	local character = Roster.get(id)
	for _, key in character.moveOrder do
		if Moves[key] == nil then
			Moves[key] = cloneMove(id, key)
			table.insert(MoveOrder, key)
		end
	end
end
-- Legacy v1 aliases kept for presentation modules/tests that predate the roster.
Moves.Heavy = cloneMove("Kael", "Overhand")
Moves.Kick = cloneMove("Kael", "Roundhouse")
Moves.LeadKick = cloneMove("Kael", "FrontKick")
Moves.DuckJab = cloneMove("Sierra", "DuckJab")
Moves.BodyPunch = cloneMove("Kael", "BodyBlow")
Moves.ShinTap = cloneMove("Kael", "ShinKick")
Moves.Sweep = cloneMove("Sierra", "LowSweep")
Moves.Rise = cloneMove("Kael", "RisingUppercut")
Config.Moves = Moves
Config.RosterMoveOrder = MoveOrder
Config.MoveOrder = { "Jab", "Heavy", "LeadKick", "Kick", "DuckJab", "BodyPunch", "ShinTap", "Sweep", "Rise" }
Config.MoveTiers = {}
for key, move in Moves do Config.MoveTiers[key] = move.tier end
Config.Standing = { LeadPunch = "Jab", RearPunch = "Cross", LeadKick = "FrontKick", RearKick = "Roundhouse", Throw = "Throw" }
Config.Crouching = { LeadPunch = "DuckJab", RearPunch = "BodyBlow", LeadKick = "ShinKick", RearKick = "LowSweep", Throw = "Throw" }
Config.MaxHealth = Roster.get(Config.DefaultP1).stats.maxHealth
Config.Speed = Roster.get(Config.DefaultP1).stats.walkSpeed
Config.BackSpeed = Roster.get(Config.DefaultP1).stats.backSpeed
Config.SideSpeed = Roster.get(Config.DefaultP1).stats.sideSpeed
Config.DashSpeed = Roster.get(Config.DefaultP1).stats.dashSpeed
Config.DashFrames = Roster.get(Config.DefaultP1).stats.dashFrames

return Config
