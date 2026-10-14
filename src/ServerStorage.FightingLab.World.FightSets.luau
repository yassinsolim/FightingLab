--!strict
-- World.FightSets: fight-only scenery, one set per arena, kept in ReplicatedStorage.FightingLab.FightSets.<StageId>
-- (never in the Workspace). StageController clones the set of the local player's arena into the Workspace for that
-- player's fight only, so the plaza, the other arenas and the city behind a stage turn into that stage's own world in
-- the fight camera. Lobby players and spectators keep the normal world.
--
-- Round 7 ("map could be better"): every set is built in depth layers for the fight camera (it looks across the ring
-- from about 18 studs, so the band 38-80 studs out fills the frame behind the fighters):
--   near (38-46): the arena's edge of the world: a veranda, an understory, a dock edge, snow drifts, a terrace, and a
--        3D crowd (a few parts per person, swaying and cheering, lit by the scene);
--   mid (46-80): real foliage meshes from free Creator Store models (World.AssetKit, credited) and a landmark in the
--        default camera's view: a vermilion gate before a pagoda, a sun temple, an observatory dome and a radio dish,
--        a berthed freighter, a rooftop bar under a giant billboard;
--   far (90-200): hills, peaks, towers, an aurora; and life: petals, fireflies, god rays, gulls, searchlights, snow.
-- Moving pieces carry the attribute FightSetAnim (Cheer, Bob, Sway, Sweep, Orbit; AnimRate, AnimAmp, AnimPhase) and
-- StageController animates them on the fighting client.
--
-- Every piece stands on a bearing the set covers (FightSets.covers: ARC degrees either side of the arena's plaza
-- direction, plus NORTH_ARC round north, the default fight camera's view, unless the arena's own backdrop is there) and
-- at least MIN_RADIUS from FightOrigin: the fight camera orbits inside 36 studs, so a set piece can never stand between
-- the camera and the fighters (nothing needs fading). Anchored, non-colliding, no queries or touches.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kit = require(script.Parent.Kit)
local Props = require(script.Parent.Props)
local Layout = require(script.Parent.Layout)
local AssetKit = require(script.Parent.AssetKit)

type ArenaDef = Layout.ArenaDef

local FightSets = {}
FightSets.FOLDER = "FightSets"
FightSets.MIN_RADIUS = 38
FightSets.TAG = "FightingLabFightSet"
FightSets.PART_BUDGET = 600 -- parts per set (only one set is ever shown, to one client)
FightSets.ANIM_ATTRIBUTE = "FightSetAnim"

local M = Enum.Material
local rgb = Color3.fromRGB

local GRADIENT = "rbxasset://textures/gradient.png" -- soft band: bright centre line fading to the edges (beams)
local DOT = "rbxasset://textures/smallWhiteCircle.png"
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local function flat(p: Vector3): Vector3 return Vector3.new(p.X, 0, p.Z) end

local function dirOf(bearing: number): Vector3
	local r = math.rad(bearing)
	return Vector3.new(math.sin(r), 0, -math.cos(r))
end

local function diff(a: number, b: number): number
	return math.abs((a - b + 540) % 360 - 180)
end

-- Whether a world bearing (0 = north, clockwise) from FightOrigin is set ground for this arena. Round 7: the sets
-- surround the fight (StageController hides the district and the active arena's own pieces off its podium), so
-- every bearing is set ground. Kept as a function for the builders and tests.
function FightSets.covers(_def: ArenaDef, _bearing: number): boolean
	return true
end

-- Every covered bearing on a `step` grid, in order round the arena.
function FightSets.bearings(def: ArenaDef, step: number): { number }
	local list = {}
	for b = 0, 359, step do
		if FightSets.covers(def, b) then table.insert(list, b) end
	end
	return list
end

-- The bearing of the set's landmark: the default fight camera's view (it looks north across the ring).
function FightSets.focusBearing(_def: ArenaDef): number
	return 0
end

-- Point at a world bearing and radius from FightOrigin, at height y (world).
local function atB(def: ArenaDef, bearing: number, radius: number, y: number): Vector3
	local d = dirOf(bearing)
	return Vector3.new(def.origin.X + d.X * radius, y, def.origin.Z + d.Z * radius)
end

-- Facing the fight (LookVector toward FightOrigin) from a point.
local function facingFight(def: ArenaDef, p: Vector3): CFrame
	local o = Vector3.new(def.origin.X, p.Y, def.origin.Z)
	return CFrame.lookAt(p, o)
end

local function quiet(root: Instance)
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
end

-- Marks a Model or part for StageController's set animation.
local function anim(inst: Instance, kind: string, rate: number, amp: number, phase: number)
	inst:SetAttribute(FightSets.ANIM_ATTRIBUTE, kind)
	inst:SetAttribute("AnimRate", rate)
	inst:SetAttribute("AnimAmp", amp)
	inst:SetAttribute("AnimPhase", phase)
end

local function emitterVolume(parent: Instance, cf: CFrame, size: Vector3, props: Kit.Props): ParticleEmitter
	local volume = Kit.deco(parent, cf, size, M.SmoothPlastic, Color3.new(1, 1, 1), { Name = "EmitterVolume", Transparency = 1, CastShadow = false })
	local e = Instance.new("ParticleEmitter")
	e.LightInfluence = 0
	e.LockedToPart = false
	for k, v in props do (e :: any)[k] = v end
	e.Parent = volume
	return e
end

-- A far layer of hills or mountains round the covered bearings (it closes the horizon in the haze).
local function farHills(def: ArenaDef, set: Model, name: string, colors: { Color3 }, material: Enum.Material, height: { number }, radius: { number }, step: number, seed: number)
	local rng = Kit.rng(seed)
	local hills = Kit.model(set, name)
	for _, b in FightSets.bearings(def, step) do
		local h = rng:NextNumber(height[1], height[2])
		local p = atB(def, b + rng:NextNumber(-6, 6), rng:NextNumber(radius[1], radius[2]), -4 + h * 0.36)
		Kit.blob(hills, facingFight(def, p) * CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), 0), Vector3.new(rng:NextNumber(70, 92), h, rng:NextNumber(46, 60)), material, colors[rng:NextInteger(1, #colors)], { Name = "Hill", CastShadow = false })
	end
	return hills
end

-- A far mountain: a square pyramid of four corner wedges (crisp ridgelines against the sky) with a snow cap pyramid
-- over its upper part. `cf` stands on the mountain's base centre; turned so a ridge faces the fight.
local function mountain(parent: Instance, cf: CFrame, width: number, height: number, rock: Color3, snow: Color3?, snowShare: number?, material: Enum.Material?)
	local function pyramid(base: CFrame, w: number, h: number, mat: Enum.Material, color: Color3, name: string)
		for q = 0, 3 do
			local rot = CFrame.Angles(0, q * math.pi / 2, 0)
			Kit.cornerWedge(parent, base * rot * CFrame.new(w / 4, h / 2, w / 4) * CFrame.Angles(0, math.pi, 0), Vector3.new(w / 2, h, w / 2), mat, color, { Name = name, CastShadow = false })
		end
	end
	local turned = cf * CFrame.Angles(0, math.rad(45), 0)
	pyramid(turned, width, height, material or M.Rock, rock, "Mountain")
	if snow then
		local share = snowShare or 0.38
		local h = height * share
		pyramid(turned * CFrame.new(0, height - h + 0.15, 0), width * share + 0.4, h + 0.2, if material then material else M.Snow, snow, "MountainSnow")
	end
end

-- A soft light shaft (sun through a canopy, a searchlight): a camera-facing beam between two points whose gradient
-- texture fades at both edges.
local function shaft(parent: Instance, a: Vector3, b: Vector3, width0: number, width1: number, color: Color3, transparency: number, name: string?): BasePart
	local holder = Kit.deco(parent, CFrame.new(a), Vector3.new(1, 1, 1), M.SmoothPlastic, Color3.new(1, 1, 1), { Name = name or "Shaft", Transparency = 1, CastShadow = false })
	local a0 = Instance.new("Attachment"); a0.Parent = holder
	local a1 = Instance.new("Attachment"); a1.Parent = holder; a1.Position = holder.CFrame:PointToObjectSpace(b)
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0; beam.Attachment1 = a1
	beam.Width0 = width0; beam.Width1 = width1
	beam.FaceCamera = true; beam.Segments = 1
	beam.Texture = GRADIENT; beam.TextureMode = Enum.TextureMode.Stretch
	beam.LightEmission = 1; beam.LightInfluence = 0
	beam.Color = ColorSequence.new(color)
	beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, transparency), NumberSequenceKeypoint.new(0.7, math.min(1, transparency + 0.05)), NumberSequenceKeypoint.new(1, 1) })
	beam.Parent = holder
	return holder
end

-- Crowd ------------------------------------------------------------------------------------------------------------

-- The set's ground round the podium (StageController hides the district floor during the fight): an inner ring
-- from the podium out to `innerRadius` and the ground beyond it to `outerRadius`, tops at `top` (world Y). Discs are
-- centred on FightOrigin; the podium stands through them.
local function ground(def: ArenaDef, set: Instance, top: number, inner: { number | Enum.Material | Color3 }, outer: { number | Enum.Material | Color3 }?)
	local g = Kit.model(set, "Ground")
	local c = Vector3.new(def.origin.X, 0, def.origin.Z)
	local ri, mi, ci = inner[1] :: number, inner[2] :: Enum.Material, inner[3] :: Color3
	Kit.cylinder(g, c + Vector3.new(0, top - 0.5, 0), 1, ri * 2, mi, ci, { Name = "GroundInner", CastShadow = false })
	if outer then
		local ro, mo, co = outer[1] :: number, outer[2] :: Enum.Material, outer[3] :: Color3
		Kit.cylinder(g, c + Vector3.new(0, top - 0.55, 0), 1, ro * 2, mo, co, { Name = "GroundOuter", CastShadow = false })
	end
	return g
end

-- A string of glowing bulbs between two points with a little sag: one invisible holder part with a wire beam and a
-- bulb beam (a dot texture repeated every `spacing` studs). One part per string instead of two per bulb.
local function bulbString(parent: Instance, a: Vector3, b: Vector3, color: Color3, spacing: number, sag: number, size: number?)
	local holder = Kit.deco(parent, CFrame.new(a), Vector3.new(0.2, 0.2, 0.2), M.SmoothPlastic, Color3.new(1, 1, 1), { Name = "BulbString", Transparency = 1, CastShadow = false })
	local third = (b - a) / 3
	local down = Vector3.new(0, -sag * 1.3, 0)
	local c0, c1 = third + down, third - down
	local function att(pos: Vector3, axis: Vector3): Attachment
		local at = Instance.new("Attachment")
		at.Parent = holder
		local w = axis.Unit
		local up = if math.abs(w.Y) > 0.95 then Vector3.xAxis else Vector3.yAxis
		at.WorldCFrame = CFrame.fromMatrix(pos, w, up:Cross(w).Unit:Cross(w) * -1)
		return at
	end
	local a0, a1 = att(a, c0), att(b, c1)
	local function beam(name: string, width: number, tex: string?, emission: number, transparency: number, col: Color3)
		local bm = Instance.new("Beam")
		bm.Name = name
		bm.Attachment0 = a0; bm.Attachment1 = a1
		bm.CurveSize0 = c0.Magnitude; bm.CurveSize1 = c1.Magnitude
		bm.Width0 = width; bm.Width1 = width; bm.FaceCamera = true; bm.Segments = 16
		if tex then
			bm.Texture = tex; bm.TextureMode = Enum.TextureMode.Static; bm.TextureLength = spacing
		end
		bm.LightEmission = emission; bm.LightInfluence = 1 - emission
		bm.Color = ColorSequence.new(col)
		bm.Transparency = NumberSequence.new(transparency)
		bm.Parent = holder
	end
	beam("Wire", 0.07, nil, 0, 0.1, rgb(24, 24, 28))
	beam("Bulbs", size or 0.5, DOT, 1, 0, color)
	return holder
end

local SKIN = { rgb(255, 214, 180), rgb(236, 188, 150), rgb(204, 146, 104), rgb(160, 106, 72), rgb(112, 74, 50), rgb(78, 52, 38) }
local HAIR = { rgb(28, 22, 18), rgb(58, 38, 26), rgb(104, 70, 40), rgb(196, 160, 104), rgb(18, 18, 22), rgb(132, 54, 34), rgb(222, 214, 196) }

export type CrowdOpts = {
	shirts: { Color3 },
	pants: { Color3 }?,
	cheer: number?, -- share of people with an arm (or both) up
	glow: { Color3 }?, -- light sticks / phone lights in raised hands
	belt: { Color3 }?, -- a belt across the waist (dojo students)
	rows: number?, -- rows one behind the other (each row 2.2 studs further out)
	rise: number?, -- how much higher each row behind stands
	spacing: number?,
	hats: number?, -- share wearing a hard hat or cap (dock workers)
	hatColors: { Color3 }?,
}

-- One spectator facing the fight, feet at cf: legs, a torso with the arms at its sides, a head and (mostly) hair or a
-- hat; a cheering person raises one or both arms (separate parts, maybe holding a light stick). Model "Person" with the
-- Cheer animation (a little bounce; bigger for people with an arm up). About four parts per person.
local function person(parent: Instance, cf: CFrame, s: number, rng: Random, o: CrowdOpts): Model
	local p = Kit.model(parent, "Person")
	local shirt = o.shirts[rng:NextInteger(1, #o.shirts)]
	local pantsList = o.pants or { rgb(36, 38, 48), rgb(52, 56, 72), rgb(70, 60, 50), rgb(28, 28, 30) }
	local pants = pantsList[rng:NextInteger(1, #pantsList)]
	local skin = SKIN[rng:NextInteger(1, #SKIN)]
	local base = cf * CFrame.Angles(0, rng:NextNumber(-0.35, 0.35), 0)
	local cheer = rng:NextNumber() < (o.cheer or 0.3)
	local both = cheer and rng:NextNumber() < 0.35
	local up = if rng:NextNumber() < 0.5 then -1 else 1
	Kit.deco(p, base * CFrame.new(0, 1.25 * s, 0), Vector3.new(1.2, 2.5, 0.8) * s, M.Fabric, pants, { Name = "Legs", CastShadow = false })
	-- the torso includes the arms hanging at the sides (one block), narrower when an arm is up
	local width = if cheer then (if both then 1.75 else 2.2) else 2.6
	local shift = if cheer and not both then -up * 0.22 else 0
	Kit.deco(p, base * CFrame.new(shift * s, 3.55 * s, 0), Vector3.new(width, 2.15, 0.95) * s, M.Fabric, shirt, { Name = "Torso", CastShadow = false })
	if o.belt then
		Kit.deco(p, base * CFrame.new(0, 2.62 * s, 0), Vector3.new(1.8, 0.3, 1.0) * s, M.Fabric, o.belt[rng:NextInteger(1, #o.belt)], { Name = "Belt", CastShadow = false })
	end
	Kit.ball(p, (base * CFrame.new(0, 5.2 * s, 0)).Position, 1.12 * s, M.SmoothPlastic, skin, { Name = "Head", CastShadow = false })
	local hatColors = o.hatColors or { rgb(250, 200, 40) }
	if o.hats and rng:NextNumber() < o.hats then
		Kit.blob(p, base * CFrame.new(0, 5.55 * s, 0), Vector3.new(1.3, 0.62, 1.3) * s, M.SmoothPlastic, hatColors[rng:NextInteger(1, #hatColors)], { Name = "Hat", CastShadow = false })
	elseif rng:NextNumber() < 0.75 then
		Kit.blob(p, base * CFrame.new(0, 5.5 * s, 0.12 * s), Vector3.new(1.18, 0.66, 1.2) * s, M.SmoothPlastic, HAIR[rng:NextInteger(1, #HAIR)], { Name = "Hair", CastShadow = false })
	end
	if cheer then
		for _, side in { -1, 1 } do
			if not (both or side == up) then continue end
			local shoulder = base * CFrame.new(side * 0.95 * s, 4.45 * s, 0)
			local arm = shoulder * CFrame.Angles(0, 0, side * math.rad(rng:NextNumber(150, 172))) * CFrame.new(0, -1.0 * s, 0)
			Kit.deco(p, arm, Vector3.new(0.5, 2.0, 0.6) * s, M.Fabric, shirt, { Name = "Arm", CastShadow = false })
			if o.glow and rng:NextNumber() < 0.7 then
				Kit.glow(p, arm * CFrame.new(0, -1.25 * s, 0), Vector3.new(0.22, 0.75, 0.22) * s, o.glow[rng:NextInteger(1, #o.glow)], { Name = "Glow" })
			end
		end
	end
	anim(p, "Cheer", rng:NextNumber(5, 8), if cheer then rng:NextNumber(0.35, 0.6) else rng:NextNumber(0.08, 0.16), rng:NextNumber(0, 6.28))
	return p
end

-- A crowd standing on an arc round the fight (from bearing b0 to b1 at `radius`), facing it.
local function crowd(def: ArenaDef, set: Instance, b0: number, b1: number, radius: number, footY: number, seed: number, o: CrowdOpts): Model
	local rng = Kit.rng(seed)
	local m = Kit.model(set, "Crowd")
	local spacing = o.spacing or 2.3
	for row = 0, (o.rows or 1) - 1 do
		local r = radius + row * 2.2
		local stepDeg = math.deg(spacing / r)
		local b = b0 + rng:NextNumber(0, stepDeg * 0.5) + (if row % 2 == 1 then stepDeg * 0.5 else 0)
		while b <= b1 do
			if FightSets.covers(def, b) then
				local foot = atB(def, b, r + rng:NextNumber(-0.25, 0.25), footY + row * (o.rise or 0))
				person(m, facingFight(def, foot), rng:NextNumber(0.92, 1.08), rng, o)
			end
			b += stepDeg * rng:NextNumber(0.85, 1.2)
		end
		Kit.step()
	end
	return m
end

-- Foliage ----------------------------------------------------------------------------------------------------------

-- An AssetKit piece on a covered bearing; returns nil when the bearing is not covered. Pieces that reach down into the
-- fighters' height band are pushed out until their boxes clear the camera orbit (ArenaLook_Test checks every part).
local CLEAR_RADIUS = 37.2
local function placeAsset(def: ArenaDef, set: Instance, key: string, bearing: number, radius: number, footY: number, scale: number, rng: Random, opts: AssetKit.PlaceOpts?): Model?
	if not FightSets.covers(def, bearing) then return nil end
	local reach = AssetKit.reach(key, scale, def.floorY + 9 - footY)
	local r = math.max(radius, CLEAR_RADIUS + reach)
	local foot = atB(def, bearing, r, footY)
	return AssetKit.place(set, key, facingFight(def, foot) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0), scale, opts)
end

--------------------------------------------------------------------------------------------------------------------
-- Summit Observatory: snow banks and weathered rocks, snowy firs, the observatory dome and a radio dish on the ridge,
-- crags and far peaks, an aurora over them; snowfall and drifting powder.
--------------------------------------------------------------------------------------------------------------------
local function summit(def: ArenaDef, set: Model)
	local rng = Kit.rng(61)
	local focus = FightSets.focusBearing(def)
	local snow, rockTint = rgb(236, 242, 252), rgb(176, 186, 206)
	ground(def, set, 0.05, { 46, M.Snow, rgb(226, 234, 246) }, { 170, M.Snow, rgb(214, 224, 240) })
	-- near: snow banks round the deck and rocks breaking through them
	local near = Kit.model(set, "SnowBanks")
	for _, b in FightSets.bearings(def, 10) do
		local p = atB(def, b + rng:NextNumber(-3, 3), rng:NextNumber(41.5, 44), rng:NextNumber(0.6, 1.4))
		Kit.blob(near, facingFight(def, p), Vector3.new(rng:NextNumber(10, 14), rng:NextNumber(3.4, 5.2), rng:NextNumber(6, 8)), M.Snow, snow, { Name = "SnowBank", CastShadow = false })
	end
	for i, b in FightSets.bearings(def, 26) do
		if diff(b, focus) < 10 then continue end
		local scale = rng:NextNumber(1.3, 1.9)
		local m = placeAsset(def, near, "Rock", b + rng:NextNumber(-5, 5), rng:NextNumber(43.5, 46), -0.6, scale, rng, { tint = rockTint })
		if m then
			local cf = m:GetBoundingBox()
			Kit.blob(near, CFrame.new(cf.Position + Vector3.new(0, 1.9 * scale, 0)), Vector3.new(5 * scale, 0.9 * scale, 4.4 * scale), M.Snow, snow, { Name = "RockSnow", CastShadow = false })
		end
		if i % 4 == 0 then Kit.step() end
	end
	-- mountaineers and stargazers in bright parkas and beanies, knee-deep in the banks
	local parkas = { rgb(214, 60, 46), rgb(236, 140, 40), rgb(240, 200, 60), rgb(40, 150, 160), rgb(70, 90, 170), rgb(236, 236, 240) }
	local hikers: CrowdOpts = { shirts = parkas, pants = { rgb(40, 44, 56), rgb(60, 64, 80), rgb(28, 30, 38) }, cheer = 0.3, hats = 0.7, hatColors = { rgb(196, 40, 50), rgb(240, 240, 240), rgb(40, 60, 120), rgb(240, 180, 40) }, spacing = 2.7 }
	crowd(def, set, focus - 62, focus - 42, 40.6, 0, 87, hikers)
	crowd(def, set, focus + 24, focus + 46, 40.6, 0, 88, hikers)
	crowd(def, set, focus + 160, focus + 200, 40.6, 0, 89, hikers)
	-- a little brass telescope on a tripod at the rail, looking at the sky
	local scope = Kit.model(set, "Telescope")
	local tp = atB(def, focus - 34, 41, 0)
	for k = 0, 2 do
		local a = k * math.pi * 2 / 3
		Kit.rod(scope, tp + Vector3.new(math.cos(a) * 1.1, 0, math.sin(a) * 1.1), tp + Vector3.new(0, 3.6, 0), 0.16, M.Metal, rgb(40, 42, 50))
	end
	local tube = facingFight(def, tp + Vector3.new(0, 4.1, 0)) * CFrame.Angles(math.rad(35), math.rad(140), 0)
	Kit.cylinder(scope, tube * CFrame.Angles(math.rad(90), 0, 0), 3.4, 0.6, M.Metal, rgb(196, 160, 86), { Name = "Tube" })
	-- firs: small ones by the banks, tall snowy ones round the sides; the default view keeps a gap so the observatory,
	-- the peaks and the aurora show over the rail
	local trees = Kit.model(set, "Firs")
	for _, b in FightSets.bearings(def, 17) do
		if diff(b, focus) < 14 then continue end
		placeAsset(def, trees, "SmallPine", b + rng:NextNumber(-6, 6), rng:NextNumber(45.5, 48.5), 0, rng:NextNumber(0.8, 1.1), rng)
	end
	for _, b in FightSets.bearings(def, 12) do
		if diff(b, focus) < 36 or diff(b, focus + 180) < 26 then continue end
		placeAsset(def, trees, "SnowPine", b + rng:NextNumber(-4, 4), rng:NextNumber(52, 62), -0.5, rng:NextNumber(0.4, 0.52), rng)
		Kit.step()
	end
	-- prayer flags strung between two poles in the default view
	local flags = Kit.model(set, "PrayerFlags")
	local fa, fb = atB(def, focus - 24, 47, 0), atB(def, focus + 6, 49, 0)
	for _, p in { fa, fb } do
		Kit.cylinder(flags, p + Vector3.new(0, 5.5, 0), 11, 0.35, M.Wood, rgb(92, 70, 52), { Name = "FlagPole" })
	end
	Props.bunting(flags, fa + Vector3.new(0, 10.6, 0), fb + Vector3.new(0, 10.6, 0), 16, { rgb(60, 110, 220), rgb(240, 240, 240), rgb(220, 60, 50), rgb(60, 170, 90), rgb(250, 200, 40) }, 2.4)
	-- the observatory dome on the ridge, its slit open and lit, the telescope reaching out
	local obs = Kit.model(set, "Observatory")
	local oc = atB(def, focus + 16, 66, 0)
	local of = facingFight(def, oc)
	local white, band = rgb(232, 236, 242), rgb(70, 78, 96)
	Kit.cylinder(obs, of * CFrame.new(0, 5, 0), 10, 19, M.Concrete, white, { Name = "Drum" })
	Kit.cylinder(obs, of * CFrame.new(0, 10.2, 0), 0.6, 19.8, M.Metal, band, { Name = "Ring" })
	Kit.ball(obs, (of * CFrame.new(0, 10.4, 0)).Position, 19, M.Metal, rgb(214, 222, 232), { Name = "Dome" })
	for k = 0, 5 do
		local y = 11 + k * 1.5
		local z = -math.sqrt(math.max(0, 9.5 ^ 2 - (y - 10.4) ^ 2)) + 0.25
		Kit.deco(obs, of * CFrame.new(0, y, z) * CFrame.Angles(math.rad(-k * 15), 0, 0), Vector3.new(3, 1.6, 0.5), M.SmoothPlastic, rgb(18, 20, 28), { Name = "Slit" })
	end
	Kit.glow(obs, of * CFrame.new(0, 13.6, -7.6), Vector3.new(2.2, 4.6, 0.2), rgb(255, 196, 120), { Name = "SlitGlow", Transparency = 0.25 })
	Kit.cylinder(obs, of * CFrame.new(0, 15.2, -6.4) * CFrame.Angles(math.rad(-55), 0, 0), 7, 1.3, M.Metal, rgb(236, 238, 244), { Name = "BigScope" })
	for _, x in { -6, 0, 6 } do
		Kit.glow(obs, of * CFrame.new(x, 3.2, -9.55) * CFrame.Angles(0, math.rad(x * 3.4), 0), Vector3.new(2.2, 2.4, 0.1), rgb(255, 206, 140), { Name = "Window", Transparency = 0.2 })
	end
	Kit.block(obs, of * CFrame.new(0, 2.2, -9.7), Vector3.new(3.2, 4.4, 0.4), M.Wood, rgb(70, 52, 40), { Name = "Door" })
	-- a radio dish on its pedestal, tilted to the sky
	local dish = Kit.model(set, "RadioDish")
	local dc = atB(def, focus - 30, 63, 0)
	local df = facingFight(def, dc)
	Kit.cylinder(dish, df * CFrame.new(0, 4, 0), 8, 2.4, M.Concrete, white, { Name = "Pedestal" })
	Kit.block(dish, df * CFrame.new(0, 8.6, 0), Vector3.new(3.6, 1.6, 3.6), M.Metal, band, { Name = "Mount" })
	local bowl = df * CFrame.new(0, 13, 0) * CFrame.Angles(math.rad(50), math.rad(25), 0)
	Kit.blob(dish, bowl, Vector3.new(17, 17, 3.2), M.Metal, rgb(226, 230, 238), { Name = "Dish" })
	Kit.rod(dish, (bowl * CFrame.new(0, 0, -1)).Position, (bowl * CFrame.new(0, 0, -7)).Position, 0.3, M.Metal, band, { Name = "Feed" })
	Kit.glow(dish, bowl * CFrame.new(0, 0, -7.2), Vector3.new(0.6, 0.6, 0.6), rgb(255, 60, 60), { Name = "FeedLamp" })
	Kit.step()
	-- far peaks: crisp snowy pyramids whose tips sit inside the fight camera's frame, with sky above them
	local peaks = Kit.model(set, "Peaks")
	for _, b in FightSets.bearings(def, 20) do
		local r = rng:NextNumber(165, 190)
		local h = rng:NextNumber(30, 50)
		mountain(peaks, facingFight(def, atB(def, b + rng:NextNumber(-6, 6), r, -4)) * CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), 0), h * rng:NextNumber(1.7, 2.2), h, rgb(66, 76, 100), rgb(220, 230, 248), rng:NextNumber(0.34, 0.46))
	end
	-- the aurora over the peaks, low enough for the fight camera (which sees about 25 studs up at 60 studs out)
	local sky = Kit.model(set, "Aurora")
	local ribbons = {
		{ -40, 126, 30, 16, rgb(70, 255, 160), rgb(80, 200, 255), 0.25 },
		{ -6, 132, 36, 15, rgb(110, 255, 190), rgb(150, 110, 255), 0.22 },
		{ 30, 124, 29, 14, rgb(80, 240, 200), rgb(90, 150, 255), 0.3 },
		{ 70, 130, 34, 14, rgb(150, 120, 255), rgb(80, 255, 170), 0.34 },
		{ 150, 128, 32, 15, rgb(80, 255, 170), rgb(90, 160, 255), 0.3 },
		{ 216, 126, 30, 15, rgb(120, 255, 200), rgb(140, 110, 255), 0.3 },
		{ 286, 130, 34, 15, rgb(80, 240, 190), rgb(80, 180, 255), 0.3 },
	}
	for i, spec in ribbons do
		local b = focus + (spec[1] :: number)
		local r, y, w = spec[2] :: number, spec[3] :: number, spec[4] :: number
		local a0p, a1p = atB(def, b - 18, r, y), atB(def, b + 18, r, y + 8)
		local anchor = Kit.deco(sky, CFrame.new((a0p + a1p) / 2), Vector3.new(1, 1, 1), M.SmoothPlastic, Color3.new(1, 1, 1), { Name = "AuroraAnchor" .. i, Transparency = 1, CastShadow = false })
		local att0 = Instance.new("Attachment"); att0.Parent = anchor; att0.Position = anchor.CFrame:PointToObjectSpace(a0p)
		local att1 = Instance.new("Attachment"); att1.Parent = anchor; att1.Position = anchor.CFrame:PointToObjectSpace(a1p)
		local beam = Instance.new("Beam")
		beam.Name = "AuroraRibbon"
		beam.Attachment0 = att0; beam.Attachment1 = att1
		beam.Width0 = w; beam.Width1 = w * 0.7; beam.FaceCamera = true; beam.Segments = 30
		beam.CurveSize0 = 26; beam.CurveSize1 = -22
		beam.Texture = GRADIENT; beam.TextureMode = Enum.TextureMode.Stretch
		beam.LightEmission = 1; beam.LightInfluence = 0; beam.Brightness = 2.2
		beam.Color = ColorSequence.new(spec[5] :: Color3, spec[6] :: Color3)
		local t = spec[7] :: number
		beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, t), NumberSequenceKeypoint.new(0.75, t + 0.08), NumberSequenceKeypoint.new(1, 1) })
		beam.Parent = anchor
		anim(anchor, "Sway", 0.18 + i * 0.03, 0.05, i * 1.7)
	end
	-- snowfall over the deck, and powder drifting low over the banks
	emitterVolume(set, CFrame.new(def.origin + Vector3.new(0, 34, 0)), Vector3.new(90, 1, 90), {
		Name = "Snowfall", Rate = 40, Lifetime = NumberRange.new(9, 13), Speed = NumberRange.new(3, 5),
		EmissionDirection = Enum.NormalId.Bottom, SpreadAngle = Vector2.new(12, 12), Acceleration = Vector3.new(1.2, 0, 0.4),
		Size = NumberSequence.new(0.2), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.1, 0.1), NumberSequenceKeypoint.new(0.85, 0.2), NumberSequenceKeypoint.new(1, 1) }),
		Color = ColorSequence.new(rgb(240, 246, 255)), LightInfluence = 0.6, Texture = DOT,
	})
	emitterVolume(set, CFrame.new(atB(def, focus, 42, 2)), Vector3.new(60, 1, 6), {
		Name = "Powder", Rate = 5, Lifetime = NumberRange.new(4, 6), Speed = NumberRange.new(2, 4),
		EmissionDirection = Enum.NormalId.Right, SpreadAngle = Vector2.new(20, 8), Acceleration = Vector3.new(0, 0.3, 0),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 5) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.82), NumberSequenceKeypoint.new(1, 1) }),
		Color = ColorSequence.new(rgb(230, 238, 255)), LightInfluence = 0.8, Texture = SMOKE,
	})
end

--------------------------------------------------------------------------------------------------------------------
-- Jungle Ruins: a fern and broadleaf understory with toppled columns, great jungle trees and palms, the stepped sun
-- temple framed by a ruined gate, a waterfall off a mossy cliff, the canopy and hills; god rays, mist and fireflies.
--------------------------------------------------------------------------------------------------------------------
local function jungle(def: ArenaDef, set: Model)
	local rng = Kit.rng(62)
	local focus = FightSets.focusBearing(def)
	local stone, stoneDark, moss, glyph = rgb(168, 160, 128), rgb(116, 110, 86), rgb(62, 98, 44), rgb(126, 236, 98)
	local leafTint = rgb(206, 236, 196)
	ground(def, set, 0.05, { 47, M.Ground, rgb(86, 74, 52) }, { 170, M.LeafyGrass, rgb(58, 84, 46) })
	-- understory: ferns and broadleaf bushes all round the near edge, mossy boulders among them
	local under = Kit.model(set, "Understory")
	for i, b in FightSets.bearings(def, 7) do
		local key = if i % 3 == 0 then "Bush" else "Fern"
		local s = if key == "Fern" then rng:NextNumber(1.5, 2.1) else rng:NextNumber(1.3, 1.8)
		placeAsset(def, under, key, b + rng:NextNumber(-3, 3), rng:NextNumber(42, 45), -0.2, s, rng, { tint = leafTint })
		if i % 6 == 0 then Kit.step() end
	end
	for _, b in FightSets.bearings(def, 40) do
		if diff(b, focus) < 25 then continue end
		placeAsset(def, under, "MossRock", b + rng:NextNumber(-8, 8), rng:NextNumber(45, 48), -1.2, rng:NextNumber(0.55, 0.8), rng)
	end
	-- explorers and villagers come to watch, in khaki, linen and leaf colours with sun hats
	local garb = { rgb(196, 170, 120), rgb(120, 112, 70), rgb(232, 224, 204), rgb(150, 86, 52), rgb(84, 104, 64), rgb(210, 150, 70) }
	local watch: CrowdOpts = { shirts = garb, pants = { rgb(92, 76, 56), rgb(64, 62, 48), rgb(120, 104, 80) }, cheer = 0.35, hats = 0.45, hatColors = { rgb(214, 190, 136), rgb(176, 150, 100), rgb(90, 74, 52) }, spacing = 2.6 }
	crowd(def, set, focus - 44, focus - 22, 40.4, 0, 84, watch)
	crowd(def, set, focus + 22, focus + 44, 40.4, 0, 85, watch)
	crowd(def, set, focus + 160, focus + 200, 40.4, 0, 86, watch)
	-- toppled, mossy columns and broken drums at the edge of the clearing
	local fallen = Kit.model(set, "Fallen")
	for k, spec in { { focus - 38, 44.5, 0.35 }, { focus + 30, 45, -0.5 }, { focus + 112, 44, 0.2 } } do
		if not FightSets.covers(def, spec[1]) then continue end
		local p = atB(def, spec[1], spec[2], 1.3)
		local cf = facingFight(def, p) * CFrame.Angles(0, math.rad(90) + spec[3], 0) * CFrame.Angles(0, 0, math.rad(90))
		Kit.cylinder(fallen, cf, 11, 2.6, M.Limestone, stone, { Name = "Column" .. k })
		Kit.blob(fallen, cf * CFrame.new(0.9, 1.5, 0), Vector3.new(1.6, 6, 2.6), M.LeafyGrass, moss, { Name = "Moss", CastShadow = false })
		Kit.cylinder(fallen, facingFight(def, atB(def, spec[1] + 7, spec[2] + 1, 0.9)) * CFrame.Angles(0.3, 0, 0.1), 1.8, 3, M.Limestone, stoneDark, { Name = "Drum" })
	end
	-- great jungle trees and palms behind the understory
	local trees = Kit.model(set, "Trees")
	for _, b in FightSets.bearings(def, 15) do
		if diff(b, focus) < 19 or diff(b, focus + 40) < 9 then continue end
		placeAsset(def, trees, "JungleTree", b + rng:NextNumber(-4, 4), rng:NextNumber(49, 57), -0.4, rng:NextNumber(0.78, 1.0), rng, { tint = leafTint })
		placeAsset(def, trees, "Palm", b + 7.5 + rng:NextNumber(-2, 2), rng:NextNumber(55, 63), -0.4, rng:NextNumber(0.55, 0.72), rng)
		Kit.step()
	end
	-- the sun temple: three weathered tiers, a shrine with a glowing doorway and the sun disc above it
	local temple = Kit.model(set, "SunTemple")
	local tc = atB(def, focus, 66, 0)
	local tf = facingFight(def, tc)
	local tiers = { { 34, 4.2, 16 }, { 26, 4.2, 12.5 }, { 18, 4.2, 9 } }
	local y = 0
	for k, t in tiers do
		Kit.block(temple, tf * CFrame.new(0, y + t[2] / 2, 0), Vector3.new(t[1], t[2], t[3]), M.Limestone, if k % 2 == 0 then stoneDark else stone, { Name = "Tier" .. k })
		Kit.blob(temple, tf * CFrame.new(rng:NextNumber(-t[1] / 3, t[1] / 3), y + t[2], -t[3] / 2 + 0.6), Vector3.new(t[1] * 0.35, 1.6, 2.2), M.LeafyGrass, moss, { Name = "Moss", CastShadow = false })
		y += t[2]
	end
	Kit.block(temple, tf * CFrame.new(0, 2.1, -8.6), Vector3.new(7, 4.2, 2.4), M.Limestone, stoneDark, { Name = "Stair" })
	for s = 0, 5 do
		Kit.block(temple, tf * CFrame.new(0, 0.35 + s * 0.7, -10 + s * 0.6), Vector3.new(6, 0.7, 1.4), M.Limestone, stone, { Name = "Step" })
	end
	local shrineY = y
	Kit.block(temple, tf * CFrame.new(0, shrineY + 4, 0), Vector3.new(11, 8, 6.5), M.Limestone, stone, { Name = "Shrine" })
	Kit.block(temple, tf * CFrame.new(0, shrineY + 8.5, 0), Vector3.new(12.4, 1, 7.6), M.Limestone, stoneDark, { Name = "ShrineCap" })
	Kit.deco(temple, tf * CFrame.new(0, shrineY + 2.9, -3.28), Vector3.new(3.6, 5.8, 0.1), M.SmoothPlastic, rgb(12, 16, 10), { Name = "Doorway" })
	Kit.glow(temple, tf * CFrame.new(0, shrineY + 2.4, -3.3), Vector3.new(2.4, 4.2, 0.06), rgb(60, 130, 44), { Name = "DoorGlow", Transparency = 0.6 })
	for _, gx in { -4, 4 } do
		Kit.glow(temple, tf * CFrame.new(gx, shrineY + 5.6, -3.3), Vector3.new(0.9, 0.9, 0.06), glyph, { Name = "Glyph", Transparency = 0.35 })
		Kit.glow(temple, tf * CFrame.new(gx, shrineY + 3.6, -3.3), Vector3.new(0.6, 0.6, 0.06), glyph, { Name = "Glyph", Transparency = 0.5 })
	end
	-- the sun disc: a gold ring with rays, standing on the shrine roof
	local sunC = tf * CFrame.new(0, shrineY + 14.6, 0.4)
	Kit.cylinder(temple, sunC * CFrame.Angles(math.rad(90), 0, 0), 0.7, 8, M.Metal, rgb(196, 152, 64), { Name = "SunDisc" })
	Kit.cylinder(temple, sunC * CFrame.new(0, 0, -0.3) * CFrame.Angles(math.rad(90), 0, 0), 0.3, 4.6, M.Metal, rgb(236, 196, 110), { Name = "SunCore" })
	for k = 0, 11 do
		local a = k * math.pi / 6
		Kit.deco(temple, sunC * CFrame.Angles(0, 0, a) * CFrame.new(0, 5.6, 0), Vector3.new(0.8, 2.4, 0.4), M.Metal, rgb(196, 152, 64), { Name = "SunRay" })
	end
	-- braziers at the foot of the stair (fire, no light)
	for _, bx in { -5.5, 5.5 } do
		local bp = (tf * CFrame.new(bx, 0, -10.5)).Position
		Kit.cylinder(temple, bp + Vector3.new(0, 1.4, 0), 2.8, 0.9, M.Limestone, stoneDark, { Name = "BrazierFoot" })
		local bowl = Kit.cylinder(temple, bp + Vector3.new(0, 3.1, 0), 0.8, 2.6, M.Metal, rgb(90, 70, 50), { Name = "Brazier" })
		Kit.emitter(bowl, {
			Name = "Fire", Rate = 22, Lifetime = NumberRange.new(0.5, 0.9), Speed = NumberRange.new(2, 3.5), SpreadAngle = Vector2.new(12, 12),
			EmissionDirection = Enum.NormalId.Right, Size = Kit.numbers(1.4, 0.2), Transparency = Kit.numbers(0.15, 1),
			Color = Kit.colors(rgb(255, 196, 90), rgb(255, 90, 30)), LightEmission = 1, Texture = "rbxasset://textures/particles/fire_main.dds",
		})
	end
	Kit.step()
	-- the ruined gate in front of the temple: two mossy pillars, a broken lintel, glowing glyph tiles
	local gate = Kit.model(set, "RuinedGate")
	for _, side in { -1, 1 } do
		local foot = atB(def, focus + side * 12.5, 47, 0)
		local cf = facingFight(def, foot)
		Kit.block(gate, cf * CFrame.new(0, 8.5, 0), Vector3.new(4.4, 17, 4.4), M.Limestone, stone, { Name = "GatePillar" })
		Kit.block(gate, cf * CFrame.new(0, 17.4, 0), Vector3.new(5.6, 1, 5.6), M.Limestone, stoneDark, { Name = "GateCap" })
		Kit.block(gate, cf * CFrame.new(0, 0.6, 0), Vector3.new(5.4, 1.2, 5.4), M.Limestone, stoneDark, { Name = "GateBase" })
		Kit.glow(gate, cf * CFrame.new(0, 10, -2.25), Vector3.new(1.3, 1.3, 0.08), glyph, { Name = "GateGlyph", Transparency = 0.05 })
		Kit.glow(gate, cf * CFrame.new(0, 12.6, -2.25), Vector3.new(0.8, 0.8, 0.08), glyph, { Name = "GateGlyph", Transparency = 0.2 })
		Kit.glow(gate, cf * CFrame.new(0, 7.4, -2.25), Vector3.new(0.8, 0.8, 0.08), glyph, { Name = "GateGlyph", Transparency = 0.3 })
		Kit.blob(gate, cf * CFrame.new(side * -0.6, 12.5, -1.6), Vector3.new(3.6, 8, 2.2), M.LeafyGrass, moss, { Name = "GateMoss", CastShadow = false })
		for v = 1, 3 do
			local top = (cf * CFrame.new(side * (v - 2) * 1.2, 17, -2.5)).Position
			Kit.blob(gate, CFrame.new(top - Vector3.new(0, 3 + v, 0)), Vector3.new(0.5, 6 + v * 2, 0.5), M.LeafyGrass, rgb(70, 112, 48), { Name = "Vine", CastShadow = false })
		end
	end
	Kit.strut(gate, atB(def, focus - 15, 47, 18.4), atB(def, focus + 8, 47, 19.6), 3.8, 2.4, M.Limestone, stone, { Name = "Lintel" })
	Kit.block(gate, facingFight(def, atB(def, focus + 17, 45.5, 0.8)) * CFrame.Angles(0.2, 0.5, 0.1), Vector3.new(5, 1.6, 2.6), M.Limestone, stoneDark, { Name = "FallenBlock" })
	-- a waterfall off a mossy cliff to the right of the temple, into a pool
	local falls = Kit.model(set, "Waterfall")
	local wb = focus + 40
	if FightSets.covers(def, wb) then
		for k, spec in { { 0, 0, 5.2 }, { -7, 9, 4.2 }, { 7, 6, 4.6 }, { 0, 16, 3.6 } } do
			local s = spec[3]
			local p = atB(def, wb + spec[1] * 0.6, 68, spec[2] - 2)
			AssetKit.place(falls, "Boulder", facingFight(def, p) * CFrame.Angles(0, k * 1.3, 0), s, { tint = rgb(150, 170, 140) })
		end
		Kit.blob(falls, facingFight(def, atB(def, wb, 66, 22)), Vector3.new(16, 4, 10), M.LeafyGrass, moss, { Name = "CliffMoss", CastShadow = false })
		local top, bottom = atB(def, wb, 63.5, 21), atB(def, wb, 61.5, 1)
		shaft(falls, top, bottom, 4.6, 6.2, rgb(220, 240, 255), 0.22, "Water")
		shaft(falls, top + Vector3.new(0, 0, 0), bottom, 2.2, 3.2, rgb(255, 255, 255), 0.1, "WaterCore")
		Kit.cylinder(falls, CFrame.new(atB(def, wb, 61, 0.15)), 0.3, 16, M.Glass, rgb(70, 130, 120), { Name = "Pool", Transparency = 0.25, Reflectance = 0.2 })
		emitterVolume(falls, CFrame.new(atB(def, wb, 61.5, 1)), Vector3.new(5, 1, 5), {
			Name = "Spray", Rate = 14, Lifetime = NumberRange.new(1.5, 2.5), Speed = NumberRange.new(2, 4), SpreadAngle = Vector2.new(60, 60),
			EmissionDirection = Enum.NormalId.Top, Size = Kit.numbers(2, 6), Transparency = Kit.numbers(0.55, 1),
			Color = Kit.colors(rgb(236, 246, 255)), LightInfluence = 0.8, Texture = SMOKE,
		})
	end
	-- the high canopy (away from the temple, which stays in the sun) and the hills beyond
	local canopy = Kit.model(set, "Canopy")
	for _, b in FightSets.bearings(def, 12) do
		if diff(b, focus) < 34 then continue end
		local p = atB(def, b + rng:NextNumber(-4, 4), rng:NextNumber(64, 74), rng:NextNumber(30, 38))
		Kit.blob(canopy, facingFight(def, p), Vector3.new(rng:NextNumber(38, 50), rng:NextNumber(20, 26), 26), M.LeafyGrass, rgb(44, 82, 42):Lerp(rgb(66, 108, 52), rng:NextNumber()), { Name = "HighCanopy", CastShadow = false })
	end
	farHills(def, set, "JungleHills", { rgb(46, 74, 44), rgb(54, 84, 50), rgb(40, 66, 40) }, M.LeafyGrass, { 62, 84 }, { 112, 128 }, 18, 72)
	-- god rays falling through the canopy onto the temple court
	local rays = Kit.model(set, "GodRays")
	for k, off in { -16, -5, 7, 18 } do
		local foot = atB(def, focus + off, 58 + k * 2, 0)
		local top = foot + Vector3.new(-12, 64, 18)
		shaft(rays, top, foot, 7 + k, 10 + k, rgb(255, 238, 186), 0.84, "GodRay")
	end
	-- mist hugging the ground of the clearing, and fireflies in the shade
	emitterVolume(set, CFrame.new(def.origin + dirOf(focus) * 50 + Vector3.new(0, 1.5, 0)), Vector3.new(70, 1, 24), {
		Name = "GroundMist", Rate = 6, Lifetime = NumberRange.new(9, 14), Speed = NumberRange.new(0.3, 0.8),
		EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(70, 70), Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 8), NumberSequenceKeypoint.new(1, 16) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.84), NumberSequenceKeypoint.new(1, 1) }),
		Color = ColorSequence.new(rgb(214, 232, 206)), LightInfluence = 1, Texture = SMOKE,
		RotSpeed = NumberRange.new(-6, 6),
	})
	emitterVolume(set, CFrame.new(def.origin + Vector3.new(0, 6, 0)), Vector3.new(96, 10, 96), {
		Name = "Fireflies", Rate = 10, Lifetime = NumberRange.new(4, 7), Speed = NumberRange.new(0.2, 0.7),
		SpreadAngle = Vector2.new(180, 180), Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.3), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new(0.1), LightEmission = 1, Color = ColorSequence.new(rgb(220, 255, 140)), Texture = SPARK,
	})
end

--------------------------------------------------------------------------------------------------------------------
-- Training Bay: a garden veranda of lit paper screens under a tiled eave, students watching, cherry trees in bloom
-- over it, stone lanterns and a vermilion gate framing a five-roof pagoda, misty mountains and a snow peak beyond;
-- drifting petals and morning shafts of light.
--------------------------------------------------------------------------------------------------------------------
local function dojo(def: ArenaDef, set: Model)
	local rng = Kit.rng(63)
	local focus = FightSets.focusBearing(def)
	local timber, timberDark, roof, paper = rgb(110, 48, 34), rgb(64, 34, 26), rgb(52, 56, 66), rgb(240, 230, 208)
	local vermilion = rgb(214, 64, 40)
	ground(def, set, 0.05, { 41.5, M.Pebble, rgb(196, 190, 176) }, { 170, M.Grass, rgb(92, 122, 70) })
	-- the veranda: post-and-beam bays with paper screens (a lattice drawn on them), a tiled eave and lanterns
	local veranda = Kit.model(set, "Veranda")
	local step = 15
	for i, b in FightSets.bearings(def, step) do
		local p0, p1 = atB(def, b, 43.5, 0), atB(def, b + step, 43.5, 0)
		local mid = (p0 + p1) / 2
		local along = (p1 - p0).Unit
		local len = (flat(p1) - flat(p0)).Magnitude + 0.3
		local toFight = flat(def.origin - mid).Unit
		local cf = CFrame.lookAt(mid, mid + toFight) -- local X along the wall, -Z (front) to the fight
		local _ = along
		Kit.deco(veranda, cf * CFrame.new(0, 0.55, 0), Vector3.new(len, 1.1, 2.2), M.Wood, timberDark, { Name = "Sill" })
		local screen = Kit.deco(veranda, cf * CFrame.new(0, 3.9, 0.2), Vector3.new(len - 0.9, 5.4, 0.12), M.Fabric, paper, { Name = "Screen", CastShadow = false })
		local g = Instance.new("SurfaceGui")
		g.Name = "Lattice"; g.Face = Enum.NormalId.Front; g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud; g.PixelsPerStud = 12
		g.LightInfluence = 1; g.MaxDistance = 300
		local w, h = (len - 0.9) * 12, 5.4 * 12
		for c = 1, 3 do
			local f = Instance.new("Frame"); f.BorderSizePixel = 0; f.BackgroundColor3 = timberDark
			f.Position = UDim2.fromOffset(math.floor(w * c / 4) - 2, 0); f.Size = UDim2.fromOffset(4, h); f.Parent = g
		end
		for r = 1, 4 do
			local f = Instance.new("Frame"); f.BorderSizePixel = 0; f.BackgroundColor3 = timberDark
			f.Position = UDim2.fromOffset(0, math.floor(h * r / 5) - 2); f.Size = UDim2.fromOffset(w, 4); f.Parent = g
		end
		g.Parent = screen
		Kit.deco(veranda, cf * CFrame.new(len / 2, 3.9, 0), Vector3.new(0.8, 7.8, 0.8), M.Wood, timber, { Name = "Post" })
		Kit.deco(veranda, cf * CFrame.new(0, 7.2, 0), Vector3.new(len + 0.2, 0.7, 1.0), M.Wood, timber, { Name = "Lintel" })
		Kit.deco(veranda, cf * CFrame.new(0, 8.25, -0.9) * CFrame.Angles(math.rad(-20), 0, 0), Vector3.new(len + 0.3, 0.45, 4.4), M.Slate, roof, { Name = "Eave" })
		Kit.deco(veranda, cf * CFrame.new(0, 9.2, 0.7), Vector3.new(len + 0.3, 0.6, 0.7), M.Slate, Kit.shade(roof, 0.8), { Name = "Ridge" })
		if i % 2 == 0 then
			local lantern = Props.hangingLantern(veranda, (cf * CFrame.new(0, 7.0, -1.9)).Position, rgb(255, 176, 96), 1.15, false)
			anim(lantern, "Sway", rng:NextNumber(1.2, 1.7), 0.06, rng:NextNumber(0, 6))
		end
		if i % 4 == 0 then Kit.step() end
	end
	-- students in their training clothes watching from the veranda
	local gi = { rgb(240, 238, 230), rgb(236, 232, 222), rgb(232, 230, 224), rgb(40, 52, 96), rgb(28, 30, 38) }
	local belts = { rgb(28, 26, 26), rgb(28, 26, 26), rgb(196, 60, 46), rgb(70, 110, 200), rgb(236, 190, 50), rgb(90, 150, 70) }
	local opts: CrowdOpts = { shirts = gi, pants = gi, belt = belts, cheer = 0.3, spacing = 2.5 }
	crowd(def, set, focus - 52, focus - 22, 40.4, 0, 81, opts)
	crowd(def, set, focus + 22, focus + 48, 40.4, 0, 82, opts)
	crowd(def, set, focus + 156, focus + 204, 40.4, 0, 83, opts)
	-- cherry trees in bloom over the veranda roof
	local blossom = Kit.model(set, "CherryTrees")
	for _, b in FightSets.bearings(def, 20) do
		if diff(b, focus) < 10 then continue end
		placeAsset(def, blossom, "CherryTree", b + rng:NextNumber(-4, 4), rng:NextNumber(52, 58), 0, rng:NextNumber(0.4, 0.52), rng)
		Kit.step()
	end
	-- stone lanterns flanking the approach to the gate
	local lanterns = Kit.model(set, "StoneLanterns")
	for _, side in { -1, 1 } do
		for k, r in { 49, 55 } do
			local p = atB(def, focus + side * (11 - k), r, 0)
			local c = rgb(150, 146, 136)
			Kit.cylinder(lanterns, p + Vector3.new(0, 0.3, 0), 0.6, 2.6, M.Granite, Kit.shade(c, 0.85))
			Kit.cylinder(lanterns, p + Vector3.new(0, 2, 0), 2.8, 0.9, M.Granite, c)
			Kit.block(lanterns, CFrame.new(p + Vector3.new(0, 3.9, 0)), Vector3.new(1.9, 1.3, 1.9), M.Granite, c)
			Kit.glow(lanterns, CFrame.new(p + Vector3.new(0, 3.9, 0)), Vector3.new(1.96, 0.7, 1.2), rgb(255, 196, 120))
			Kit.wedge(lanterns, CFrame.new(p + Vector3.new(0, 4.9, 0)), Vector3.new(2.8, 0.8, 2.8), M.Granite, Kit.shade(c, 0.9))
		end
	end
	-- the vermilion gate framing the pagoda behind it
	local gate = Kit.model(set, "Gate")
	local gc = atB(def, focus, 60, 0)
	local gf = facingFight(def, gc)
	for _, x in { -7, 7 } do
		Kit.cylinder(gate, gf * CFrame.new(x, 7, 0), 14, 1.5, M.Wood, vermilion, { Name = "Pillar" })
		Kit.cylinder(gate, gf * CFrame.new(x, 0.5, 0), 1, 2.1, M.Wood, timberDark, { Name = "PillarFoot" })
	end
	Kit.block(gate, gf * CFrame.new(0, 11.2, 0), Vector3.new(17, 1, 1.1), M.Wood, vermilion, { Name = "Tie" })
	Kit.block(gate, gf * CFrame.new(0, 13.6, 0), Vector3.new(20, 1.3, 1.8), M.Wood, vermilion, { Name = "Beam" })
	Kit.block(gate, gf * CFrame.new(0, 14.5, 0), Vector3.new(22, 0.7, 2.2), M.Wood, timberDark, { Name = "Cap" })
	for _, s in { -1, 1 } do
		Kit.wedge(gate, gf * CFrame.new(s * 11.6, 14.7, 0) * CFrame.Angles(0, math.rad(90 * s), 0), Vector3.new(2.2, 0.9, 1.4), M.Wood, timberDark, { Name = "CapTip" })
	end
	Kit.block(gate, gf * CFrame.new(0, 12.4, 0), Vector3.new(2.6, 2.4, 0.4), M.Wood, timberDark, { Name = "Plaque" })
	-- the five-roof pagoda beyond the gate
	local pagoda = Kit.model(set, "Pagoda")
	local pc = atB(def, focus, 84, 0)
	local pf = facingFight(def, pc)
	for k = 0, 4 do
		local w = 17 - k * 2.6
		local yk = 1.5 + k * 7.2
		Kit.block(pagoda, pf * CFrame.new(0, yk + 2.4, 0), Vector3.new(w * 0.62, 4.8, w * 0.62), M.Plaster, rgb(238, 228, 208), { Name = "Story" })
		for _, x in { -w * 0.31, w * 0.31 } do
			Kit.block(pagoda, pf * CFrame.new(x, yk + 2.4, -w * 0.31), Vector3.new(0.6, 4.8, 0.6), M.Wood, vermilion, { Name = "StoryPost" })
		end
		Kit.block(pagoda, pf * CFrame.new(0, yk + 5.2, 0), Vector3.new(w, 0.9, w), M.Slate, roof, { Name = "Roof" })
		Kit.block(pagoda, pf * CFrame.new(0, yk + 4.7, 0), Vector3.new(w + 0.4, 0.3, w + 0.4), M.Wood, timber, { Name = "Eave" })
		for _, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
			Kit.wedge(pagoda, pf * CFrame.new(c[1] * w / 2, yk + 5.7, c[2] * w / 2) * CFrame.Angles(0, math.atan2(-c[1], -c[2]), 0), Vector3.new(1.2, 1, 2.6), M.Slate, roof, { Name = "EaveTip" })
		end
		Kit.glow(pagoda, pf * CFrame.new(0, yk + 2.3, -w * 0.31 - 0.06), Vector3.new(w * 0.3, 2.6, 0.08), rgb(255, 214, 150), { Name = "Window", Transparency = 0.25 })
	end
	Kit.cylinder(pagoda, pf * CFrame.new(0, 44, 0), 9, 0.5, M.Metal, rgb(196, 160, 86), { Name = "Spire" })
	for k = 0, 3 do
		Kit.cylinder(pagoda, pf * CFrame.new(0, 41.5 + k * 1.6, 0), 0.25, 1.6 - k * 0.2, M.Metal, rgb(196, 160, 86), { Name = "SpireRing" })
	end
	Kit.step()
	-- misty mountains across the bay and a snow-capped peak behind the pagoda (smooth faces: they read as silhouettes
	-- in the morning haze, below the top of the fight camera's frame)
	local range = Kit.model(set, "Mountains")
	for _, b in FightSets.bearings(def, 26) do
		local h = rng:NextNumber(34, 52)
		mountain(range, facingFight(def, atB(def, b + rng:NextNumber(-7, 7), rng:NextNumber(200, 240), -4)) * CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), 0), h * rng:NextNumber(2.2, 2.8), h, rgb(132, 148, 176), rgb(240, 244, 252), 0.2, M.SmoothPlastic)
	end
	mountain(range, facingFight(def, atB(def, focus + 18, 280, -4)), 170, 74, rgb(126, 142, 172), rgb(244, 246, 252), 0.34, M.SmoothPlastic)
	-- morning light in shafts through the trees
	local rays = Kit.model(set, "MorningRays")
	for k, off in { -40, -20, 26, 48 } do
		local foot = atB(def, focus + off, 50, 0)
		shaft(rays, foot + Vector3.new(14, 54, -10), foot, 6 + k, 9 + k, rgb(255, 232, 196), 0.86, "Ray")
	end
	-- drifting blossom petals (soft pink ovals, tumbling)
	emitterVolume(set, CFrame.new(def.origin + Vector3.new(0, 20, 0)), Vector3.new(76, 1, 76), {
		Name = "Petals", Rate = 16, Lifetime = NumberRange.new(7, 11), Speed = NumberRange.new(1, 2),
		EmissionDirection = Enum.NormalId.Bottom, SpreadAngle = Vector2.new(30, 30), Acceleration = Vector3.new(0.9, -0.25, 0.5),
		Size = NumberSequence.new(0.2), Squash = NumberSequence.new(-0.45),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.08, 0.05), NumberSequenceKeypoint.new(0.9, 0.15), NumberSequenceKeypoint.new(1, 1) }),
		Color = ColorSequence.new(rgb(255, 190, 210), rgb(255, 220, 230)), LightInfluence = 0.7, Texture = DOT,
		RotSpeed = NumberRange.new(-160, 160), Rotation = NumberRange.new(0, 360),
	})
end

--------------------------------------------------------------------------------------------------------------------
-- Harbor Dusk: the dock edge with bollards, crates and dock workers, stacked freight, the lit Pier 9 warehouse, a
-- gantry crane swinging a container, a freighter berthed behind; gulls wheeling in the last light, warm dust.
--------------------------------------------------------------------------------------------------------------------
local function gull(parent: Instance, centre: Vector3, radius: number, rate: number, phase: number)
	local g = Kit.model(parent, "Gull")
	local white, grey = rgb(244, 244, 240), rgb(120, 124, 132)
	Kit.deco(g, CFrame.new(centre + Vector3.new(radius, 0, 0)), Vector3.new(0.5, 0.45, 1.5), M.SmoothPlastic, white, { Name = "Body", CastShadow = false })
	for _, s in { -1, 1 } do
		Kit.deco(g, CFrame.new(centre + Vector3.new(radius + s * 1.25, 0.25, 0)) * CFrame.Angles(0, 0, math.rad(-s * 16)), Vector3.new(2.2, 0.08, 0.7), M.SmoothPlastic, if s < 0 then white else grey, { Name = "Wing", CastShadow = false })
	end
	g.WorldPivot = CFrame.new(centre)
	anim(g, "Orbit", rate, radius, phase)
	return g
end

-- A shipping container in two parts (body and end doors) with its ribs and a stencilled line name drawn on the long
-- faces (SurfaceGui): cf at the floor centre, the length along local X.
local LINES = { "OKTA LINE", "PIER 9", "BLUEFIN", "KESTREL", "MARLOW", "TIDEWAY" }
local function box(parent: Instance, cf: CFrame, color: Color3, rng: Random): BasePart
	local size = Vector3.new(20, 8.6, 8)
	local mat = if rng:NextNumber() < 0.5 then M.CorrodedMetal else M.Metal
	local body = Kit.deco(parent, cf * CFrame.new(0, size.Y / 2, 0), size, mat, color, { Name = "Container" })
	Kit.deco(parent, cf * CFrame.new(size.X / 2 + 0.06, size.Y / 2, 0), Vector3.new(0.12, size.Y - 0.5, size.Z - 0.5), mat, Kit.shade(color, 0.75), { Name = "Doors" })
	local name = LINES[rng:NextInteger(1, #LINES)]
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local g = Instance.new("SurfaceGui")
		g.Name = "Ribs"; g.Face = face; g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud; g.PixelsPerStud = 8
		g.LightInfluence = 1; g.MaxDistance = 400
		for k = 1, 23 do
			local f = Instance.new("Frame"); f.BorderSizePixel = 0; f.BackgroundColor3 = Kit.shade(color, 0.7)
			f.BackgroundTransparency = 0.15; f.Position = UDim2.fromOffset(k * 160 // 24, 3); f.Size = UDim2.fromOffset(2, 63); f.Parent = g
		end
		local t = Instance.new("TextLabel"); t.BackgroundTransparency = 1; t.Font = Enum.Font.GothamBlack
		t.Text = name; t.TextScaled = true; t.TextColor3 = Color3.new(1, 1, 1); t.TextTransparency = 0.25
		t.Position = UDim2.fromOffset(18, 12); t.Size = UDim2.fromOffset(84, 18); t.Parent = g
		g.Parent = body
	end
	return body
end

local function harbor(def: ArenaDef, set: Model)
	local rng = Kit.rng(64)
	local focus = FightSets.focusBearing(def)
	local colors = Props.CONTAINER_COLORS
	ground(def, set, 0.05, { 88, M.WoodPlanks, rgb(116, 90, 68) })
	local water = Kit.cylinder(set, Vector3.new(def.origin.X, -1.9, def.origin.Z), 1, 420, M.Glass, rgb(34, 64, 82), { Name = "Water", Transparency = 0.05, Reflectance = 0.35, CastShadow = false })
	local _ = water
	-- the dock edge: bollards with rope, crates and barrels
	local edge = Kit.model(set, "DockEdge")
	for i, b in FightSets.bearings(def, 15) do
		if diff(b, focus) < 7 then continue end
		local p = atB(def, b + rng:NextNumber(-3, 3), rng:NextNumber(41, 43.5), 0)
		local f = facingFight(def, p)
		local kind = i % 3
		if kind == 0 then
			Props.bollard(edge, p)
			Kit.cylinder(edge, f * CFrame.new(1.6, 0.3, 0.4), 0.6, 2.2, M.Fabric, rgb(196, 170, 120), { Name = "RopeCoil" })
		elseif kind == 1 then
			Props.crate(edge, f * CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), 0), 2.6, rgb(176, 132, 92))
			Props.crate(edge, f * CFrame.new(2.4, 0, 0.6) * CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), 0), 2.2, rgb(150, 112, 80))
		else
			Props.barrel(edge, p, rgb(60, 92, 140))
		end
		if i % 4 == 0 then Kit.step() end
	end
	-- dock workers in overalls and hard hats
	local overalls = { rgb(214, 132, 40), rgb(60, 90, 140), rgb(120, 120, 128), rgb(176, 58, 44), rgb(236, 200, 60) }
	local opts: CrowdOpts = { shirts = overalls, cheer = 0.25, hats = 0.6, hatColors = { rgb(250, 200, 40), rgb(240, 240, 236), rgb(236, 110, 40) }, spacing = 2.6 }
	crowd(def, set, focus - 36, focus - 12, 40.6, 0, 91, opts)
	crowd(def, set, focus + 12, focus + 34, 40.6, 0, 92, opts)
	crowd(def, set, focus + 160, focus + 200, 40.6, 0, 93, opts)
	-- stacked freight
	local quay = Kit.model(set, "Quay")
	for _, b in FightSets.bearings(def, 20) do
		if diff(b, focus) < 21 or diff(b, focus + 42) < 12 then continue end
		local p = atB(def, b + rng:NextNumber(-4, 4), rng:NextNumber(49, 55), 0)
		local cf = facingFight(def, p) * CFrame.Angles(0, math.rad(90 + rng:NextNumber(-8, 8)), 0)
		local stack = rng:NextInteger(1, 3)
		for k = 0, stack - 1 do
			box(quay, cf * CFrame.new(rng:NextNumber(-0.8, 0.8), k * 8.6, 0), colors[rng:NextInteger(1, #colors)], rng)
		end
		Kit.step()
	end
	-- the Pier 9 warehouse in the default camera's view: lit windows, loading bays, its sign and roof lights
	local wp = atB(def, focus, 60, 0)
	local wf = facingFight(def, wp)
	local body = Kit.block(quay, wf * CFrame.new(0, 11, 0), Vector3.new(48, 22, 14), M.CorrodedMetal, rgb(96, 86, 78), { Name = "Warehouse" })
	Props.windows(body, Enum.NormalId.Front, rng, { floorHeight = 4.2, bayWidth = 3.2, lit = 0.42, band = rgb(64, 58, 54), skipBottom = 7, pps = 8, glass = rgb(40, 44, 52), litColors = { rgb(255, 196, 120), rgb(255, 170, 92), rgb(255, 214, 150) } })
	Kit.block(quay, wf * CFrame.new(0, 22.6, 0), Vector3.new(49, 1.2, 15), M.Metal, rgb(60, 56, 54), { Name = "WarehouseRoof" })
	Kit.wedge(quay, wf * CFrame.new(0, 24.2, 3.6) * CFrame.Angles(0, math.pi, 0), Vector3.new(49, 2, 7.4), M.Metal, rgb(70, 66, 62), { Name = "RoofSlope" })
	Kit.wedge(quay, wf * CFrame.new(0, 24.2, -3.6), Vector3.new(49, 2, 7.4), M.Metal, rgb(70, 66, 62), { Name = "RoofSlope" })
	Props.neonSign(quay, wf * CFrame.new(0, 18.6, -7.4), 21, 3.6, "PIER 9 FREIGHT", rgb(255, 152, 54), Enum.Font.Oswald, false)
	for _, x in { -15, 0, 15 } do
		Kit.glow(quay, wf * CFrame.new(x, 2.9, -7.05), Vector3.new(8, 5.6, 0.1), rgb(196, 132, 70), { Name = "LoadingBay", Transparency = 0.45 })
		Kit.deco(quay, wf * CFrame.new(x, 6.1, -7.6), Vector3.new(9, 0.4, 1.4), M.Metal, rgb(50, 48, 46), { Name = "Canopy" })
	end
	for _, x in { -20, -7, 7, 20 } do
		Kit.glow(quay, wf * CFrame.new(x, 23.6, -7.2), Vector3.new(1.2, 0.5, 0.5), rgb(255, 210, 150), { Name = "RoofLamp" })
	end
	-- string lights from the warehouse to two lamp posts on the quay
	local lights = Kit.model(set, "QuayLights")
	for _, s in { -1, 1 } do
		local post = atB(def, focus + s * 24, 50, 0)
		Kit.cylinder(lights, post + Vector3.new(0, 6, 0), 12, 0.45, M.Metal, rgb(46, 48, 54), { Name = "LampPost" })
		Kit.glow(lights, CFrame.new(post + Vector3.new(0, 12.3, 0)), Vector3.new(1.3, 0.8, 1.3), rgb(255, 190, 110), { Name = "SodiumLamp" })
		bulbString(lights, post + Vector3.new(0, 11.6, 0), (wf * CFrame.new(s * 22, 14, -7.3)).Position, rgb(255, 176, 90), 3, 1.6, 0.42)
	end
	-- the gantry crane with a container swinging gently from its hook
	local cranePos = atB(def, focus + 42, 74, 0)
	Props.crane(set, cranePos, dirOf(focus + 200), rng, rgb(196, 54, 44))
	local hang = Kit.model(set, "HangingLoad")
	local boomDir = dirOf(focus + 200)
	local hookTop = cranePos + Vector3.new(0, 31.8, 0) + boomDir * 26
	Kit.rod(hang, hookTop, hookTop - Vector3.new(0, 9, 0), 0.25, M.Metal, rgb(60, 62, 70), { Name = "Cable" })
	box(hang, CFrame.lookAt(hookTop - Vector3.new(0, 17.6, 0), hookTop - Vector3.new(0, 17.6, 0) + boomDir), colors[2], rng)
	hang.WorldPivot = CFrame.new(hookTop)
	anim(hang, "Sway", 0.55, 0.035, 0)
	-- a freighter berthed behind the quay: hull, deck cargo, a white bridge with lit windows and a funnel
	local ship = Kit.model(set, "Freighter")
	local sc = atB(def, focus - 34, 104, -2)
	local sf = facingFight(def, sc) * CFrame.Angles(0, math.rad(90), 0)
	Kit.block(ship, sf * CFrame.new(0, 7, 0), Vector3.new(74, 14, 15), M.Metal, rgb(52, 40, 44), { Name = "Hull" })
	Kit.block(ship, sf * CFrame.new(0, 2, 0), Vector3.new(74.2, 4, 15.2), M.Metal, rgb(150, 48, 40), { Name = "Boot" })
	Kit.wedge(ship, sf * CFrame.new(-44, 7, 0) * CFrame.Angles(0, math.rad(-90), 0), Vector3.new(15, 14, 14), M.Metal, rgb(52, 40, 44), { Name = "Bow" })
	for k = 0, 5 do
		for lvl = 0, rng:NextInteger(1, 2) do
			Kit.block(ship, sf * CFrame.new(-30 + k * 9.5, 15.6 + lvl * 3.4, 0), Vector3.new(9, 3.3, 13), M.Metal, colors[rng:NextInteger(1, #colors)], { Name = "DeckBox" })
		end
	end
	local bridge = Kit.block(ship, sf * CFrame.new(30, 21, 0), Vector3.new(10, 14, 13), M.Metal, rgb(232, 232, 228), { Name = "Bridge" })
	Props.windows(bridge, Enum.NormalId.Left, rng, { floorHeight = 3.5, bayWidth = 2.6, lit = 0.6, band = rgb(200, 200, 196), litColors = { rgb(255, 214, 150), rgb(255, 236, 200) } })
	Props.windows(bridge, Enum.NormalId.Right, rng, { floorHeight = 3.5, bayWidth = 2.6, lit = 0.6, band = rgb(200, 200, 196), litColors = { rgb(255, 214, 150), rgb(255, 236, 200) } })
	Kit.cylinder(ship, sf * CFrame.new(31, 31, 0), 6, 4, M.Metal, rgb(196, 64, 48), { Name = "Funnel" })
	Kit.rod(ship, (sf * CFrame.new(-36, 14, 0)).Position, (sf * CFrame.new(-36, 34, 0)).Position, 0.5, M.Metal, rgb(80, 80, 86), { Name = "Mast" })
	local beacon = Kit.glow(ship, sf * CFrame.new(-36, 34.6, 0), Vector3.new(0.9, 0.9, 0.9), rgb(255, 60, 50), { Name = "MastLamp" })
	beacon:SetAttribute("Period", 1.6)
	Kit.tag(beacon, Kit.TAG_BLINK)
	Kit.step()
	-- far islands on the horizon
	farHills(def, set, "Islands", { rgb(104, 92, 112), rgb(116, 100, 120), rgb(96, 86, 108) }, M.Rock, { 30, 46 }, { 150, 170 }, 24, 74)
	-- gulls wheeling over the quay
	local birds = Kit.model(set, "Gulls")
	for k = 1, 6 do
		local b = focus + rng:NextNumber(-70, 70)
		if FightSets.covers(def, b) then
			gull(birds, atB(def, b, rng:NextNumber(58, 80), rng:NextNumber(24, 40)), rng:NextNumber(9, 18), rng:NextNumber(0.35, 0.6) * (if k % 2 == 0 then 1 else -1), rng:NextNumber(0, 6.28))
		end
	end
	-- warm dust in the low sun
	emitterVolume(set, CFrame.new(def.origin + Vector3.new(0, 8, 0)), Vector3.new(70, 8, 70), {
		Name = "SunDust", Rate = 7, Lifetime = NumberRange.new(6, 9), Speed = NumberRange.new(0.1, 0.3),
		SpreadAngle = Vector2.new(180, 180), Size = NumberSequence.new(0.12), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.3), NumberSequenceKeypoint.new(1, 1) }),
		LightEmission = 0.8, Color = ColorSequence.new(rgb(255, 214, 160)), Texture = SPARK,
	})
end

--------------------------------------------------------------------------------------------------------------------
-- Midnight Rooftop: a party terrace a step below the deck (string lights, a crowd with light sticks, the sky bar),
-- neighbouring rooftops with water tanks and antennas, the NIGHT SHIFT billboard, far towers; searchlights sweeping
-- the clouds, aircraft lights crossing, fine rain.
--------------------------------------------------------------------------------------------------------------------
local function rooftop(def: ArenaDef, set: Model)
	local rng = Kit.rng(65)
	local roofs = Kit.model(set, "Rooftops")
	local neon = { rgb(255, 72, 196), rgb(60, 220, 255), rgb(150, 90, 255), rgb(255, 186, 90) }
	local focus = FightSets.focusBearing(def)
	local deckY = def.floorY - 1.2
	local street = -26
	ground(def, set, deckY, { 49, M.Concrete, rgb(58, 60, 72) })
	Kit.cylinder(set, Vector3.new(def.origin.X, street - 0.5, def.origin.Z), 1, 420, M.Asphalt, rgb(30, 32, 40), { Name = "Streets", CastShadow = false })
	-- the party terrace: decking, a glass balustrade with a neon line, string lights on poles
	local terrace = Kit.model(set, "Terrace")
	local arcStep = 15
	for _, b in FightSets.bearings(def, arcStep) do
		local mid = atB(def, b + arcStep / 2, 43, deckY - 0.45)
		local len = 2 * 48 * math.sin(math.rad(arcStep / 2)) + 0.4
		local f = facingFight(def, mid)
		Kit.deco(terrace, f, Vector3.new(len, 0.9, 9.6), M.WoodPlanks, rgb(64, 52, 46), { Name = "Deck" })
		Kit.deco(terrace, f * CFrame.new(0, 2.1, 5.2), Vector3.new(len, 2.6, 0.2), M.Glass, rgb(120, 150, 200), { Name = "Balustrade", Transparency = 0.6 })
		Kit.glow(terrace, f * CFrame.new(0, 3.45, 5.2), Vector3.new(len, 0.16, 0.3), neon[(b // arcStep) % 2 + 1], { Name = "RailNeon" })
	end
	local poles = {}
	for _, b in FightSets.bearings(def, 20) do
		local p = atB(def, b, 47, deckY)
		Kit.cylinder(terrace, p + Vector3.new(0, 4.5, 0), 9, 0.3, M.Metal, rgb(30, 32, 40), { Name = "LightPole" })
		table.insert(poles, p + Vector3.new(0, 8.8, 0))
	end
	for k = 1, #poles do
		local nxt = poles[k % #poles + 1]
		bulbString(terrace, poles[k], nxt, if k % 2 == 0 then rgb(255, 196, 120) else rgb(255, 110, 200), 2.6, 1.4, 0.42)
	end
	Kit.step()
	-- the crowd with light sticks, two rows deep in front of the default view's landmark and round the terrace
	local party = { rgb(255, 72, 196), rgb(60, 220, 255), rgb(150, 90, 255), rgb(240, 240, 250), rgb(30, 30, 40), rgb(255, 186, 90) }
	local opts: CrowdOpts = { shirts = party, cheer = 0.55, glow = { rgb(255, 72, 196), rgb(60, 220, 255), rgb(190, 255, 120) }, rows = 2, rise = 0.5, spacing = 2.4 }
	crowd(def, set, focus - 26, focus + 26, 39.6, deckY, 101, opts)
	local side: CrowdOpts = table.clone(opts)
	side.rows = 1
	crowd(def, set, focus - 96, focus - 66, 39.6, deckY, 102, side)
	crowd(def, set, focus + 66, focus + 96, 39.6, deckY, 103, side)
	crowd(def, set, focus + 166, focus + 194, 39.6, deckY, 104, side)
	-- the sky bar: a glowing counter under a neon sign
	local bar = Kit.model(set, "SkyBar")
	local bc = atB(def, focus + 46, 44, deckY)
	local bf = facingFight(def, bc)
	Kit.block(bar, bf * CFrame.new(0, 1.8, 0), Vector3.new(9, 3.6, 2.4), M.Marble, rgb(30, 30, 38), { Name = "Counter" })
	Kit.glow(bar, bf * CFrame.new(0, 3.65, -0.4), Vector3.new(9.2, 0.15, 1.6), rgb(60, 220, 255), { Name = "CounterGlow" })
	Kit.block(bar, bf * CFrame.new(0, 4.6, 2.4), Vector3.new(9, 9.2, 0.6), M.Metal, rgb(24, 24, 32), { Name = "BackBar" })
	for k = -3, 3 do
		Kit.glow(bar, bf * CFrame.new(k * 1.2, 5.4 + (k % 2) * 0.3, 2.0), Vector3.new(0.35, 1.1, 0.35), neon[(k % 4) + 1], { Name = "Bottle", Transparency = 0.2 })
	end
	Props.neonSign(bar, bf * CFrame.new(0, 10.4, 2.4), 10, 2.6, "SKY BAR", rgb(255, 72, 196), Enum.Font.Sarpanch, false)
	-- neighbouring rooftops (rising from the street far below)
	for i, b in FightSets.bearings(def, 24) do
		if diff(b, focus) < 14 then continue end
		local r = rng:NextNumber(57, 66)
		local w = rng:NextNumber(18, 24)
		local top = def.floorY + rng:NextNumber(-1, 12)
		local p = atB(def, b + rng:NextNumber(-4, 4), r, street)
		local cf = facingFight(def, p)
		local h = top - street
		local body = Kit.block(roofs, cf * CFrame.new(0, h / 2, 0), Vector3.new(w, h, 16), M.Concrete, rgb(48, 52, 70):Lerp(rgb(70, 74, 96), rng:NextNumber()), { Name = "Building" })
		Props.windows(body, Enum.NormalId.Front, rng, { lit = 0.45, band = rgb(36, 40, 54), floorHeight = 5, bayWidth = 3.4, glass = rgb(26, 30, 44) })
		Kit.glow(roofs, cf * CFrame.new(0, h + 0.2, -8.1), Vector3.new(w, 0.3, 0.3), neon[(i - 1) % #neon + 1], { Name = "RoofNeon" })
		if i % 2 == 1 then
			local tank = cf * CFrame.new(rng:NextNumber(-w / 4, w / 4), h, 2)
			for _, o in { Vector3.new(-1.8, 0, -1.8), Vector3.new(1.8, 0, -1.8), Vector3.new(-1.8, 0, 1.8), Vector3.new(1.8, 0, 1.8) } do
				Kit.deco(roofs, tank * CFrame.new(o + Vector3.new(0, 2.2, 0)), Vector3.new(0.4, 4.4, 0.4), M.Metal, rgb(30, 32, 40))
			end
			Kit.cylinder(roofs, (tank * CFrame.new(0, 7, 0)).Position, 5, 5.4, M.WoodPlanks, rgb(110, 84, 64), { Name = "WaterTank" })
			Kit.cylinder(roofs, (tank * CFrame.new(0, 10.2, 0)).Position, 1.4, 4.6, M.Metal, rgb(40, 42, 50), { Name = "TankCap" })
		else
			local mast = (cf * CFrame.new(rng:NextNumber(-w / 4, w / 4), h, 3)).Position
			Kit.cylinder(roofs, mast + Vector3.new(0, 5, 0), 10, 0.35, M.Metal, rgb(140, 144, 152), { Name = "Antenna", CastShadow = false })
			Kit.glow(roofs, CFrame.new(mast + Vector3.new(0, 10.3, 0)), Vector3.new(0.6, 0.6, 0.6), rgb(255, 40, 40), { Name = "AirBeacon" })
		end
		if i % 3 == 0 then
			Props.neonSign(roofs, cf * CFrame.new(0, h + 3.4, -6), w * 0.7, 3.6, ({ "KUMO KARAOKE", "NOVA NOODLE", "VOLT CITY", "ARCADE 24" })[(i // 3 - 1) % 4 + 1], neon[(i // 3) % #neon + 1], Enum.Font.Sarpanch, false)
		end
		Kit.step()
	end
	-- the NIGHT SHIFT billboard on the roof of the building across the street, in the default view
	local bp = atB(def, focus, 76, def.floorY + 23)
	local bfr = facingFight(def, bp)
	local under = Kit.block(roofs, facingFight(def, atB(def, focus, 80, 0)) * CFrame.new(0, (def.floorY + 11 - street) / 2 + street, 0), Vector3.new(40, def.floorY + 11 - street, 16), M.Concrete, rgb(54, 56, 76), { Name = "Building" })
	Props.windows(under, Enum.NormalId.Front, rng, { lit = 0.5, band = rgb(36, 40, 54), floorHeight = 5, bayWidth = 3.4, glass = rgb(26, 30, 44) })
	Props.neonSign(roofs, bfr, 34, 11, "NIGHT SHIFT", rgb(60, 220, 255), Enum.Font.Sarpanch, false)
	for _, x in { -11, 11 } do
		Kit.block(roofs, bfr * CFrame.new(x, -7.4, 1.5), Vector3.new(1.2, 4.6, 1.2), M.Metal, rgb(30, 32, 40), { Name = "BillboardLeg" })
	end
	-- far towers closing the horizon
	for _, b in FightSets.bearings(def, 36) do
		local p = atB(def, b + rng:NextNumber(-5, 5), rng:NextNumber(100, 124), street)
		Props.tower(roofs, p, rng:NextNumber(20, 28), rng:NextNumber(18, 24), rng:NextNumber(86, 136), rng, { neon = neon[rng:NextInteger(1, #neon)], lit = 0.34, faces = { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right }, mast = false })
		Kit.step()
	end
	-- searchlights from the far roofs sweeping the low clouds
	local lights = Kit.model(set, "Searchlights")
	for k, off in { -60, -8, 52 } do
		local foot = atB(def, focus + off, 108, 46 + k * 6)
		local beam = shaft(lights, foot, foot + Vector3.new(0, 150, 0) + dirOf(focus + off + 180) * 40, 4, 16, rgb(200, 220, 255), 0.72, "Searchlight")
		anim(beam, "Sweep", 0.22 + k * 0.05, 0.55, k * 2.1)
	end
	-- aircraft lights crossing high over the city
	for k = 1, 3 do
		local c = atB(def, focus + (k - 2) * 50, 140, 70 + k * 9)
		local plane = Kit.model(lights, "Aircraft")
		Kit.glow(plane, CFrame.new(c + Vector3.new(60 + k * 10, 0, 0)), Vector3.new(0.9, 0.9, 0.9), if k == 2 then rgb(255, 60, 60) else rgb(255, 255, 255), { Name = "NavLight" })
		plane.WorldPivot = CFrame.new(c)
		anim(plane, "Orbit", 0.05 * (if k % 2 == 0 then -1 else 1), 60 + k * 10, k * 2)
	end
	-- a fine rain over the deck
	emitterVolume(set, CFrame.new(def.origin + Vector3.new(0, 30, 0)), Vector3.new(84, 1, 84), {
		Name = "Drizzle", Rate = 36, Lifetime = NumberRange.new(2.2, 3), Speed = NumberRange.new(16, 20),
		EmissionDirection = Enum.NormalId.Bottom, SpreadAngle = Vector2.new(3, 3), Size = NumberSequence.new(0.06),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.1, 0.55), NumberSequenceKeypoint.new(1, 0.7) }),
		Color = ColorSequence.new(rgb(190, 200, 255)), LightInfluence = 0.4, Texture = SPARK,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
	})
end

local BUILDERS: { [string]: (ArenaDef, Model) -> () } = {
	SnowSummit = summit, JungleRuins = jungle, TrainingBay = dojo, HarborDusk = harbor, MidnightRooftop = rooftop,
}
FightSets.STAGES = { "SnowSummit", "JungleRuins", "TrainingBay", "HarborDusk", "MidnightRooftop" }

export type Report = { parts: number, lights: number, emitters: number, people: number, animated: number }

-- Builds every set into ReplicatedStorage.FightingLab.FightSets (replacing an old folder). Kit's running stats are
-- left as they were: the sets are not part of the world's budget (only one is ever shown, to one client).
function FightSets.build(): ({ [string]: Report }, Folder)
	local lab = ReplicatedStorage:WaitForChild("FightingLab")
	local old = lab:FindFirstChild(FightSets.FOLDER)
	if old then old:Destroy() end
	local saved = table.clone(Kit.stats)
	local folder = Instance.new("Folder")
	folder.Name = FightSets.FOLDER
	local reports: { [string]: Report } = {}
	for _, def in Layout.ARENAS do
		local builder = BUILDERS[def.stageId]
		if builder then
			local set = Instance.new("Model")
			set.Name = def.stageId
			set:SetAttribute("ArenaId", def.id)
			builder(def, set)
			quiet(set)
			local parts, lights, emitters, people, animated = 0, 0, 0, 0, 0
			for _, d in set:GetDescendants() do
				if d:IsA("BasePart") then
					parts += 1
				elseif d:IsA("Light") then
					lights += 1
				elseif d:IsA("ParticleEmitter") then
					emitters += 1
				elseif d:IsA("Model") and d.Name == "Person" then
					people += 1
				end
				if d:GetAttribute(FightSets.ANIM_ATTRIBUTE) ~= nil then animated += 1 end
			end
			set:SetAttribute("PartCount", parts)
			set:SetAttribute("LightCount", lights)
			set:SetAttribute("People", people)
			reports[def.stageId] = { parts = parts, lights = lights, emitters = emitters, people = people, animated = animated }
			set.Parent = folder
			Kit.step()
		end
	end
	for k, v in saved do Kit.stats[k] = v end
	folder.Parent = lab
	return reports, folder
end

return FightSets
