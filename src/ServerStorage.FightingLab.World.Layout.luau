--!strict
-- World.Layout: the district's fixed coordinates (pure data, no instances). OV6 compact layout: a round plaza at the
-- world origin (floor top Y = 0) ringed by five arena stages 70 studs out, so every pad is a short walk from the spawn.
-- Bearings: 0 = north (-Z), 90 = east (+X). Every fight runs along world X around its FightOrigin (identity rotation).
--
-- Each arena is a round podium (radius STAGE_RADIUS) with a straight stair facing the plaza. On it: the fight floor
-- (radius 21 = CombatConfig.ArenaRadius) ringed by a glowing edge line and a themed rail/rope barrier, and the two
-- pads at the front of the stage, 27 studs from FightOrigin, 50 degrees either side of the plaza direction
-- (P1 / Training on the left and P2 / Cpu on the right as you walk up to the stage).

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
	stairWidth: number, -- the plaza stair; the stages behind the spawn get wider stairs, leaving a walkway between them
}

local Layout = {}

Layout.ARENA_DISTANCE = 70 -- FightOrigin distance from the plaza centre (66 for the two stages behind the spawn)
Layout.PLAZA_RADIUS = 36 -- the decorated central plaza (floor top Y = 0)
Layout.DISTRICT_RADIUS = 100 -- the walkable district floor (edged by a balustrade / quay)
Layout.FIGHT_RADIUS = 21 -- CombatConfig.ArenaRadius: fighters are held inside this circle
Layout.EDGE_INNER = 21 -- the glowing edge line runs from here...
Layout.EDGE_OUTER = 21.4 -- ...to here (centre 21.2), right where a cornered fighter's back foot lands
Layout.BAND_OUTER = 22.4 -- darker edge band between the line and the barrier
Layout.RAIL_RADIUS = 22.75 -- barrier posts stand on this circle; rails/ropes run between them
Layout.RAIL_CLEARANCE = 1.6 -- lowest rail bottom above the floor (bodies lying at the edge slide under it)
Layout.STAGE_RADIUS = 31.5 -- podium top radius (fight floor, edge, apron with the pads)
Layout.PAD_OFFSET = 27 -- pads 27 studs from FightOrigin...
Layout.PAD_ANGLE = 50 -- ...50 degrees either side of the plaza direction
Layout.PAD_RADIUS = 3.5
Layout.EXIT_ANGLE = 63 -- exits beside their pads (6 studs further round the stage), facing FightOrigin
Layout.FLOOR_CLEAR_RADIUS = 25 -- floor is flat to here (bodies knocked down at the edge still lie on it)
Layout.OCCLUDER_RADIUS = 46 -- taller than 1.5 inside this radius => tagged FightingLabCameraOccluder
Layout.OCCLUDER_HEIGHT = 1.5
Layout.SPECTATOR_RADIUS = 30
Layout.BOARD_DISTANCE = 52 -- status boards stand behind the stage (away from the plaza), facing the plaza
Layout.STEP_RISE = 0.6
Layout.STEP_RUN = 1.0
Layout.STAIR_WIDTH = 26
-- Stage-light spots on the apron rim, aimed at the fight floor: a soft key that lifts the floor and the fighters
-- without blowing out pale skin and hair under the golden-hour sun (OV6 round 2 exposure pass: 0.45-0.56 measured
-- at p95 <= 235 on the fighters from the real fight camera; the earlier 1.3-1.6 clipped fair skin to white).
Layout.STAGE_SPOT_BRIGHTNESS = 0.45
Layout.STAGE_SPOT_RANGE = 46
-- Themed ground discs round a stage (jungle grass, summit snow; top 0.02 over the district floor) are centred
-- GROUND_SHIFT studs behind FightOrigin with radius STAGE_RADIUS + GROUND_MARGIN: they stop short of the plaza
-- kerb and of each other, and their rims stay on the district floor or under the terrain beyond it.
Layout.GROUND_SHIFT = 7
Layout.GROUND_MARGIN = 9
Layout.PART_BUDGET = 9000
Layout.WALK_BUDGET = 90 -- studs of path from a spawn to any pad (~5.6 s at WalkSpeed 16)
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

Layout.ARENAS = {
	-- the two stages behind the spawn court sit a little closer so their far pads stay a short walk away
	arena("Arena_MidnightRooftop", "MidnightRooftop", "Midnight Rooftop", "Duel", 1, 0, 70, 6, 26, Color3.fromRGB(255, 72, 196), "Neon rooftop stage above the city lights"),
	arena("Arena_HarborDusk", "HarborDusk", "Harbor Dusk", "Duel", 2, 72, 70, 1.2, 30, Color3.fromRGB(255, 152, 54), "Timber dock ring over the evening tide"),
	arena("Arena_JungleRuins", "JungleRuins", "Jungle Ruins", "Duel", 3, 216, 66, 2.4, 36, Color3.fromRGB(126, 226, 88), "Sun temple ring in the overgrowth"),
	arena("Arena_SnowSummit", "SnowSummit", "Summit Observatory", "Duel", 4, 144, 66, 4.2, 34, Color3.fromRGB(120, 208, 255), "Observatory deck above the snowline"),
	arena("Arena_TrainingBay", "TrainingBay", "Training Bay", "Practice", 5, 288, 70, 1.2, 30, Color3.fromRGB(255, 206, 92), "Open-air dojo on the bay"),
} :: { ArenaDef }

Layout.P1_COLOR = Color3.fromRGB(255, 104, 36)
Layout.P2_COLOR = Color3.fromRGB(38, 196, 255)
Layout.TRAINING_COLOR = Color3.fromRGB(110, 240, 130)
Layout.CPU_COLOR = Color3.fromRGB(196, 110, 255)

-- Spawn court: six spawn medallions in two rows north of the Ember Beacon, everyone facing north into the district.
Layout.SPAWN_POINTS = {
	Vector3.new(-6, 0, -11), Vector3.new(0, 0, -11), Vector3.new(6, 0, -11),
	Vector3.new(-6, 0, -16.5), Vector3.new(0, 0, -16.5), Vector3.new(6, 0, -16.5),
}
Layout.SPAWN_COURT_END = 19.5 -- the rooftop's wayfinding line starts beyond the spawn rows
Layout.BEACON_BASIN_RADIUS = 7

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

-- Pad centres (on the floor top) for slot 1 (left) and slot 2 (right).
function Layout.padPosition(def: ArenaDef, slot: number): Vector3
	local side = if slot == 1 then -1 else 1
	return def.origin + Layout.around(def, side * Layout.PAD_ANGLE) * Layout.PAD_OFFSET
end

function Layout.exitPosition(def: ArenaDef, slot: number): Vector3
	local side = if slot == 1 then -1 else 1
	return def.origin + Layout.around(def, side * Layout.EXIT_ANGLE) * Layout.PAD_OFFSET
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
