--!strict
-- World.Layout: the district's fixed coordinates (pure data, no instances). OV6 round-5 compact layout ("Ember
-- Square"): the spawn court sits at the world origin (floor top Y = 0) in the middle of a horseshoe of five arena
-- stages, 66 studs out and 56 degrees apart. The open side of the horseshoe (north-east) is the plaza head with the
-- Ember Beacon, the Fighter Kiosk and the Hall of Champions. Each stage's two pads stand on the plaza in front of its
-- stair, about 26 studs from the spawn court, so every pad is a short walk (World_Test, PathfindingService:
-- worst <= 40 and median <= 30 studs of path from every spawn). The stages stay 62 studs apart (an 8-stud walkway
-- between neighbouring podiums), so no other arena sits near the middle of a fight camera's frame.
-- Bearings: 0 = north (-Z), 90 = east (+X). Every fight runs along world X around its FightOrigin (identity rotation).
--
-- Each arena is a round podium (radius STAGE_RADIUS) with a short straight stair facing the spawn court. On it: the
-- fight floor (radius 21 = CombatConfig.ArenaRadius) ringed by a glowing edge line and a themed barrier, and a
-- walkway round the barrier. In front of the stair, on the plaza: the two pads (P1 / Training on the left and P2 / Cpu
-- on the right as you walk up to the stage), an exit marker beside each pad and the Arrival marker between them.

export type ArenaDef = {
	id: string,
	stageId: string,
	displayName: string,
	kind: string,
	order: number,
	bearing: number,
	distance: number,
	floorY: number,
	origin: Vector3,
	accent: Color3,
	tagline: string,
	inward: Vector3, -- unit (XZ) from FightOrigin towards the plaza centre
	right: Vector3, -- unit (XZ): screen-right for someone facing the stage from the plaza
	stairWidth: number, -- the stair from the plaza up to the stage
}

local Layout = {}

Layout.ARENA_DISTANCE = 66 -- FightOrigin distance from the spawn court (the plaza centre)
Layout.ARENA_SPACING = 56 -- degrees between neighbouring stages round the horseshoe
Layout.PLAZA_HEAD_BEARING = 38 -- the open side of the horseshoe: beacon, kiosk and hall
Layout.PLAZA_RADIUS = 34 -- the decorated court round the spawn (floor top Y = 0); the pads stand on its rim
Layout.DISTRICT_RADIUS = 100 -- the walkable district floor (edged by a balustrade / quay)
Layout.FIGHT_RADIUS = 21 -- CombatConfig.ArenaRadius: fighters are held inside this circle
Layout.EDGE_INNER = 21 -- the glowing edge line runs from here...
Layout.EDGE_OUTER = 21.4 -- ...to here (centre 21.2), right where a cornered fighter's back foot lands
Layout.BAND_OUTER = 22.4 -- darker edge band between the line and the barrier
Layout.RAIL_RADIUS = 22.75 -- barrier posts stand on this circle; rails/ropes run between them
Layout.RAIL_CLEARANCE = 1.6 -- lowest rail bottom above the floor (bodies lying at the edge slide under it)
Layout.STAGE_RADIUS = 27 -- podium top radius: fight floor, edge, and a walkway round the barrier
-- Pads, exits and the Arrival marker stand on the plaza in front of the stage (arena-local x towards `right`, z
-- towards the plaza; FightOrigin is at z = 0).
Layout.PAD_X = 7.5
Layout.PAD_Z = 41
Layout.PAD_RADIUS = 3.5
Layout.PAD_TOP = 0.25 -- pad top above the plaza floor
-- Exits (where a fight returns its players) stand on the plaza side of their pads, either side of the wayfinding line,
-- facing FightOrigin. Round 6: they used to stand towards the stage, 8 studs from the street lamp in the gap between
-- two stages, and the lobby camera behind a returning player had the lamp post in the middle of the view; now the
-- client frames the return over the player's shoulder (Client.LobbyCamera) along an open line across the plaza.
Layout.EXIT_X = 3
Layout.EXIT_Z = 45
Layout.ARRIVAL_Z = 41 -- between the two pads, facing the ring (quick travel drops players here)
Layout.FLOOR_CLEAR_RADIUS = 25 -- floor is flat to here (bodies knocked down at the edge still lie on it)
Layout.OCCLUDER_RADIUS = 46 -- taller than 1.5 inside this radius => tagged FightingLabCameraOccluder
Layout.OCCLUDER_HEIGHT = 1.5
-- The fight camera orbits up to this far from FightOrigin: nothing from the lobby or the grounds that rises above the
-- fight floor + OCCLUDER_HEIGHT stands inside it (the fight camera only fades its own arena's pieces).
Layout.CAMERA_ORBIT = 36
-- Another arena's pieces that rise above a fight floor + OCCLUDER_HEIGHT stay at least this far from its FightOrigin.
Layout.NEIGHBOUR_CLEARANCE = 32
Layout.SPECTATOR_RADIUS = 30
Layout.BOARD_DISTANCE = 52 -- status boards stand behind the stage (away from the plaza), facing the plaza
Layout.STEP_RISE = 0.6
Layout.STEP_RUN = 1.0
Layout.STAIR_WIDTH = 8
-- Stage-light spots on the apron rim, aimed at the fight floor: a soft key that lifts the floor and the fighters
-- without blowing out pale skin and hair under the golden-hour sun (OV6 round 2 exposure pass: 0.45-0.56 measured
-- at p95 <= 235 on the fighters from the real fight camera; the earlier 1.3-1.6 clipped fair skin to white).
Layout.STAGE_SPOT_BRIGHTNESS = 0.45
Layout.STAGE_SPOT_RANGE = 46
-- Themed ground discs round a stage (jungle grass, summit snow; top 0.02 over the district floor) are centred
-- GROUND_SHIFT studs behind FightOrigin with radius STAGE_RADIUS + GROUND_MARGIN: they reach the district edge at the
-- back, show only a one-stud fringe at the foot of the podium in front (the stair and the pads stand on the plaza
-- paving) and stay clear of each other.
Layout.GROUND_SHIFT = 3
Layout.GROUND_MARGIN = 4
Layout.PART_BUDGET = 9000
Layout.WALK_BUDGET = 40 -- studs of path from any spawn to any pad (worst case, ~2.5 s at WalkSpeed 16)
Layout.WALK_MEDIAN_BUDGET = 30 -- median over every spawn -> pad pair
Layout.OCCLUDER_TAG = "FightingLabCameraOccluder"
-- Terrain stays well below hardscape: the district floor is a 6-stud slab (top 0); no terrain rises above
-- TERRAIN_UNDER_TOP inside the district, and nothing grassy grows under it. The sea surface is at WATER_Y.
Layout.GROUND_Y = -2 -- natural ground just outside the district (2 studs below the plaza)
Layout.WATER_Y = -4
Layout.TERRAIN_UNDER_TOP = -6

-- Stage surface layers (relative to FightOrigin.Y): the fight disc is the floor; rings beneath it show as bands.
Layout.LINE_DROP = 0.02
Layout.BAND_DROP = 0.04
Layout.APRON_DROP = 0.06

local function dir(bearing: number): Vector3
	local r = math.rad(bearing)
	return Vector3.new(math.sin(r), 0, -math.cos(r))
end

local function arena(id: string, stageId: string, displayName: string, kind: string, order: number, bearing: number, distance: number, floorY: number, stairWidth: number, accent: Color3, tagline: string): ArenaDef
	local out = dir(bearing)
	local d = distance
	local r = math.rad(bearing)
	return {
		id = id,
		stageId = stageId,
		displayName = displayName,
		kind = kind,
		order = order,
		bearing = bearing,
		distance = d,
		floorY = floorY,
		origin = Vector3.new(out.X * d, floorY, out.Z * d),
		accent = accent,
		tagline = tagline,
		inward = -out,
		right = Vector3.new(math.cos(r), 0, math.sin(r)),
		stairWidth = stairWidth,
	}
end

-- Clockwise from the plaza head: Harbor (east-south-east, over the harbour basin), Summit (south-south-east, under
-- the peaks), Jungle (south-west, before the jungle hills), the dojo (west, on the bay) and the Rooftop
-- (north-north-west, before the city skyline).
local function bearingOf(k: number): number
	local half = (360 - 4 * Layout.ARENA_SPACING) / 2
	return (Layout.PLAZA_HEAD_BEARING + half + k * Layout.ARENA_SPACING) % 360
end

Layout.ARENAS = {
	arena("Arena_MidnightRooftop", "MidnightRooftop", "Midnight Rooftop", "Duel", 1, bearingOf(4), Layout.ARENA_DISTANCE, 4.2, Layout.STAIR_WIDTH, Color3.fromRGB(255, 72, 196), "Neon rooftop stage above the city lights"),
	arena("Arena_HarborDusk", "HarborDusk", "Harbor Dusk", "Duel", 2, bearingOf(0), Layout.ARENA_DISTANCE, 1.2, Layout.STAIR_WIDTH, Color3.fromRGB(255, 152, 54), "Timber dock ring over the evening tide"),
	arena("Arena_JungleRuins", "JungleRuins", "Jungle Ruins", "Duel", 3, bearingOf(2), Layout.ARENA_DISTANCE, 2.4, Layout.STAIR_WIDTH, Color3.fromRGB(126, 226, 88), "Sun temple ring in the overgrowth"),
	arena("Arena_SnowSummit", "SnowSummit", "Summit Observatory", "Duel", 4, bearingOf(1), Layout.ARENA_DISTANCE, 3.0, Layout.STAIR_WIDTH, Color3.fromRGB(120, 208, 255), "Observatory deck above the snowline"),
	arena("Arena_TrainingBay", "TrainingBay", "Training Bay", "Practice", 5, bearingOf(3), Layout.ARENA_DISTANCE, 1.2, Layout.STAIR_WIDTH, Color3.fromRGB(255, 206, 92), "Open-air dojo on the bay"),
} :: { ArenaDef }

Layout.P1_COLOR = Color3.fromRGB(255, 104, 36)
Layout.P2_COLOR = Color3.fromRGB(38, 196, 255)
Layout.TRAINING_COLOR = Color3.fromRGB(110, 240, 130)
Layout.CPU_COLOR = Color3.fromRGB(196, 110, 255)

-- Spawn court: six spawn medallions in a tight 3 x 2 block on the plaza centre, everyone facing the plaza head (the
-- beacon, kiosk and hall ahead, the Harbor and Rooftop stages to either side).
Layout.SPAWN_FACING = Layout.PLAZA_HEAD_BEARING
Layout.SPAWN_POINTS = (function(): { Vector3 }
	local fwd = dir(Layout.SPAWN_FACING)
	local lat = Vector3.new(-fwd.Z, 0, fwd.X)
	local list = {}
	for _, z in { 2.6, -2.6 } do
		for _, x in { -5.2, 0, 5.2 } do
			table.insert(list, lat * x + fwd * z)
		end
	end
	return list
end)()
Layout.SPAWN_COURT_RADIUS = 9.8 -- the marble court ring round the spawn block

function Layout.byId(id: string): ArenaDef?
	for _, def in Layout.ARENAS do
		if def.id == id then return def end
	end
	return nil
end

-- Unit vector (XZ) from the arena towards the plaza centre: the direction players arrive from.
function Layout.approachDir(def: ArenaDef): Vector3
	return def.inward
end

-- Unit vector (XZ) pointing from the plaza centre towards a bearing.
function Layout.bearingDir(bearing: number): Vector3
	return dir(bearing)
end

-- Point on the plaza floor at a bearing and radius from the centre.
function Layout.polar(bearing: number, radius: number, y: number?): Vector3
	local d = dir(bearing)
	return Vector3.new(d.X * radius, y or 0, d.Z * radius)
end

-- Arena-local frame: x along `right`, z along `inward` (towards the plaza), y up from the floor top.
function Layout.at(def: ArenaDef, x: number, y: number, z: number): Vector3
	return def.origin + def.right * x + Vector3.new(0, y, 0) + def.inward * z
end

-- The same arena-local (x, z) on the plaza floor (Y = 0).
function Layout.plazaPoint(def: ArenaDef, x: number, z: number): Vector3
	local p = def.origin + def.right * x + def.inward * z
	return Vector3.new(p.X, 0, p.Z)
end

-- CFrame in the arena-local frame: LookVector = -inward (facing away from the plaza), RightVector = right.
-- Multiply by CFrame.Angles(0, math.pi, 0) for things that should face the plaza.
function Layout.frame(def: ArenaDef, x: number, y: number, z: number): CFrame
	local p = Layout.at(def, x, y, z)
	return CFrame.lookAt(p, p - def.inward)
end

-- Direction (XZ) at `angle` degrees from the plaza direction, positive towards `right`.
function Layout.around(def: ArenaDef, angle: number): Vector3
	local a = math.rad(angle)
	return def.inward * math.cos(a) + def.right * math.sin(a)
end

-- Pad centres on the plaza floor (Y = 0) for slot 1 (left) and slot 2 (right).
function Layout.padPosition(def: ArenaDef, slot: number): Vector3
	local side = if slot == 1 then -1 else 1
	return Layout.plazaPoint(def, side * Layout.PAD_X, Layout.PAD_Z)
end

function Layout.exitPosition(def: ArenaDef, slot: number): Vector3
	local side = if slot == 1 then -1 else 1
	return Layout.plazaPoint(def, side * Layout.EXIT_X, Layout.EXIT_Z)
end

function Layout.arrivalPosition(def: ArenaDef): Vector3
	return Layout.plazaPoint(def, 0, Layout.ARRIVAL_Z)
end

-- Number of steps from the plaza (Y = 0) up to an arena's apron.
function Layout.stepCount(def: ArenaDef): number
	return math.max(0, math.ceil((def.floorY - Layout.APRON_DROP) / Layout.STEP_RISE - 1e-6))
end

-- Where the stair meets the plaza (centre of its bottom edge), on the floor. The last riser climbs onto the apron,
-- so a stair with n risers has n - 1 treads in front of the podium.
function Layout.stairFoot(def: ArenaDef): Vector3
	local run = math.max(0, Layout.stepCount(def) - 1) * Layout.STEP_RUN
	local p = def.origin + def.inward * (Layout.STAGE_RADIUS + run)
	return Vector3.new(p.X, 0, p.Z)
end

return Layout
