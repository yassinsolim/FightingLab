--!strict
-- World.FightSets (round 6, look): fight-only scenery, one set per arena, kept in
-- ReplicatedStorage.FightingLab.FightSets.<StageId> (never in the Workspace). StageController clones the set of the
-- local player's arena into the Workspace for that player's fight only, so the plaza, the other arenas and the city
-- behind a stage turn into that stage's own world in the fight camera: a snowy ridge with pines and an aurora behind
-- the Summit, a deep canopy and a ruined gate round the Jungle Ruins, a garden wall, cherry trees and a pagoda round
-- the dojo, stacked freight and a crane on the Harbor quay, neighbouring rooftops and a billboard round the Rooftop.
-- Lobby players and spectators keep the normal world.
--
-- Every piece stands on a bearing the set covers (FightSets.covers: ARC degrees either side of the arena's plaza
-- direction, plus NORTH_ARC round north, the default fight camera's view, unless the arena's own backdrop is there) and
-- at least MIN_RADIUS from FightOrigin: the fight camera orbits inside 36 studs, so a set piece can never stand
-- between the camera and the fighters (nothing needs fading). Anchored, non-colliding, no queries or touches.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kit = require(script.Parent.Kit)
local Props = require(script.Parent.Props)
local Layout = require(script.Parent.Layout)

type ArenaDef = Layout.ArenaDef

local FightSets = {}
FightSets.FOLDER = "FightSets"
FightSets.MIN_RADIUS = 38
FightSets.ARC = 105 -- degrees either side of the arena's plaza direction
FightSets.NORTH_ARC = 50 -- and the default fight camera's view (it looks north) unless the arena's own backdrop is there
FightSets.TAG = "FightingLabFightSet"

local M = Enum.Material
local rgb = Color3.fromRGB

local function flat(p: Vector3): Vector3 return Vector3.new(p.X, 0, p.Z) end

local function dirOf(bearing: number): Vector3
	local r = math.rad(bearing)
	return Vector3.new(math.sin(r), 0, -math.cos(r))
end

local function diff(a: number, b: number): number
	return math.abs((a - b + 540) % 360 - 180)
end

-- Whether a world bearing (0 = north, clockwise) from FightOrigin is set ground for this arena.
function FightSets.covers(def: ArenaDef, bearing: number): boolean
	local inward = (def.bearing + 180) % 360
	if diff(bearing, inward) <= FightSets.ARC then return true end
	return diff(bearing, 0) <= FightSets.NORTH_ARC and diff(0, def.bearing) > 60
end

-- Every covered bearing on a `step` grid, in order round the arena.
function FightSets.bearings(def: ArenaDef, step: number): { number }
	local list = {}
	for b = 0, 359, step do
		if FightSets.covers(def, b) then table.insert(list, b) end
	end
	return list
end

-- The bearing the set's landmark faces from: the default camera's view (north) when covered, else the plaza side.
function FightSets.focusBearing(def: ArenaDef): number
	if FightSets.covers(def, 0) and diff(0, def.bearing) > 60 then return 0 end
	return (def.bearing + 180) % 360
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

local function emitterVolume(parent: Instance, cf: CFrame, size: Vector3, props: Kit.Props): ParticleEmitter
	local volume = Kit.deco(parent, cf, size, M.SmoothPlastic, Color3.new(1, 1, 1), { Name = "EmitterVolume", Transparency = 1, CastShadow = false })
	local e = Instance.new("ParticleEmitter")
	e.LightInfluence = 0
	e.LockedToPart = false
	for k, v in props do (e :: any)[k] = v end
	e.Parent = volume
	return e
end

-- A far layer of hills or mountains round the covered bearings (it closes the horizon in the haze: the city towers
-- behind the plaza disappear behind it).
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

-- A row of spectators facing the fight: silhouettes drawn on one transparent panel (a SurfaceGui per panel, no part
-- per person), shaded by the scene's light. StageController makes each "Person" sway (attributes Phase and Rate).
FightSets.CROWD_HEIGHT = 6.6
local function crowd(def: ArenaDef, set: Model, bearing: number, radius: number, width: number, footY: number, palette: { Color3 }, seed: number)
	local rng = Kit.rng(seed)
	local h = FightSets.CROWD_HEIGHT
	local p = atB(def, bearing, radius, footY + h / 2)
	local panel = Kit.deco(set, facingFight(def, p), Vector3.new(width, h, 0.05), M.SmoothPlastic, Color3.new(1, 1, 1), { Name = "CrowdPanel", Transparency = 1, CastShadow = false })
	local pps = 16
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Crowd"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pps
	gui.LightInfluence = 0.85
	gui.Brightness = 1
	gui.MaxDistance = 400
	local x = rng:NextNumber(0.3, 0.9)
	local n = 0
	while x < width - 0.9 do
		n += 1
		local tall = rng:NextNumber(4.7, 5.9)
		local wide = rng:NextNumber(1.25, 1.7)
		local color = palette[rng:NextInteger(1, #palette)]:Lerp(Color3.fromRGB(14, 14, 20), rng:NextNumber(0.25, 0.6))
		local person = Instance.new("Frame")
		person.Name = "Person"
		person.BackgroundTransparency = 1
		person.AnchorPoint = Vector2.new(0.5, 1)
		person.Position = UDim2.fromOffset(math.floor(x * pps), math.floor(h * pps) + 2)
		person.Size = UDim2.fromOffset(math.floor(wide * pps), math.floor(tall * pps))
		person:SetAttribute("Phase", rng:NextNumber(0, 6.28))
		person:SetAttribute("Rate", rng:NextNumber(1.6, 3.2))
		local body = Instance.new("Frame")
		body.Name = "Body"
		body.BackgroundColor3 = color
		body.BorderSizePixel = 0
		body.AnchorPoint = Vector2.new(0.5, 1)
		body.Position = UDim2.fromScale(0.5, 1)
		body.Size = UDim2.fromScale(1, 0.8)
		local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0.38, 0); bc.Parent = body
		body.Parent = person
		local head = Instance.new("Frame")
		head.Name = "Head"
		head.BackgroundColor3 = color:Lerp(Color3.fromRGB(10, 10, 14), 0.25)
		head.BorderSizePixel = 0
		head.AnchorPoint = Vector2.new(0.5, 0)
		head.Position = UDim2.fromScale(0.5, 0)
		head.Size = UDim2.new(0, math.floor(0.82 * pps), 0, math.floor(0.82 * pps))
		local hc = Instance.new("UICorner"); hc.CornerRadius = UDim.new(1, 0); hc.Parent = head
		head.Parent = person
		if rng:NextNumber() < 0.28 then
			-- a raised arm cheering
			local arm = Instance.new("Frame")
			arm.Name = "Arm"
			arm.BackgroundColor3 = color
			arm.BorderSizePixel = 0
			arm.AnchorPoint = Vector2.new(0.5, 1)
			arm.Position = UDim2.fromScale(if rng:NextNumber() < 0.5 then 0.12 else 0.88, 0.32)
			arm.Size = UDim2.new(0, math.floor(0.36 * pps), 0.42, 0)
			arm.Rotation = rng:NextNumber(-18, 18)
			local ac = Instance.new("UICorner"); ac.CornerRadius = UDim.new(1, 0); ac.Parent = arm
			arm.Parent = person
		end
		person.Parent = gui
		x += wide * rng:NextNumber(0.8, 1.15)
	end
	gui.Parent = panel
	panel:SetAttribute("People", n)
	return panel
end

--------------------------------------------------------------------------------------------------------------------
-- Summit Observatory: a snowy ridge with pines, far peaks and an aurora; snowfall over the deck.
--------------------------------------------------------------------------------------------------------------------
local function summit(def: ArenaDef, set: Model)
	local rng = Kit.rng(61)
	local ridge = Kit.model(set, "Ridge")
	local base = -2
	local focus = FightSets.focusBearing(def)
	for i, b in FightSets.bearings(def, 14) do
		local r = rng:NextNumber(48, 58)
		local centrality = 1 - math.min(diff(b, focus), 90) / 90
		local h = rng:NextNumber(14, 24) + centrality * 10
		local p = atB(def, b + rng:NextNumber(-4, 4), r, base + h * 0.45)
		local size = Vector3.new(rng:NextNumber(22, 30), h, rng:NextNumber(14, 20))
		local cf = facingFight(def, p) * CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), 0)
		Kit.blob(ridge, cf, size, M.Rock, rgb(92, 96, 106):Lerp(rgb(124, 128, 138), rng:NextNumber()), { Name = "Crag" })
		Kit.blob(ridge, cf * CFrame.new(0, h * 0.36, 0.6), Vector3.new(size.X * 0.82, h * 0.32, size.Z * 0.86), M.Snow, rgb(236, 242, 250), { Name = "SnowCap" })
		if i % 2 == 0 then
			local foot = atB(def, b + rng:NextNumber(-5, 5), math.max(45, r - rng:NextNumber(4, 7)), 0)
			Props.pine(ridge, foot + Vector3.new(0, rng:NextNumber(0, 3), 0), rng:NextNumber(1.3, 1.8), rng, true)
		end
		Kit.step()
	end
	-- far peaks behind the ridge
	local peaks = Kit.model(set, "Peaks")
	for _, b in FightSets.bearings(def, 26) do
		local r = rng:NextNumber(100, 125)
		local h = rng:NextNumber(46, 70)
		local p = atB(def, b, r, base + h * 0.42)
		local cf = facingFight(def, p)
		Kit.blob(peaks, cf, Vector3.new(rng:NextNumber(52, 70), h, 40), M.Rock, rgb(70, 78, 96), { Name = "Peak", CastShadow = false })
		Kit.blob(peaks, cf * CFrame.new(0, h * 0.3, 1), Vector3.new(40, h * 0.42, 34), M.Snow, rgb(210, 222, 240), { Name = "PeakSnow", CastShadow = false })
	end
	-- an aurora: soft glowing ribbons high over the ridge (beams between anchors, no textures)
	local sky = Kit.model(set, "Aurora")
	for i, spec in { { -50, 0, rgb(80, 255, 170), rgb(90, 160, 255) }, { -5, 18, rgb(120, 255, 200), rgb(160, 110, 255) }, { 42, -12, rgb(90, 240, 190), rgb(70, 140, 255) } } do
		local a0p = atB(def, focus + (spec[1] :: number) - 22, 150, 70 + (spec[2] :: number))
		local a1p = atB(def, focus + (spec[1] :: number) + 22, 150, 76 + (spec[2] :: number))
		local anchor = Kit.deco(sky, CFrame.new((a0p + a1p) / 2), Vector3.new(1, 1, 1), M.SmoothPlastic, Color3.new(1, 1, 1), { Name = "AuroraAnchor" .. i, Transparency = 1, CastShadow = false })
		local att0 = Instance.new("Attachment"); att0.Parent = anchor; att0.Position = anchor.CFrame:PointToObjectSpace(a0p)
		local att1 = Instance.new("Attachment"); att1.Parent = anchor; att1.Position = anchor.CFrame:PointToObjectSpace(a1p)
		local beam = Instance.new("Beam")
		beam.Name = "AuroraRibbon"
		beam.Attachment0 = att0; beam.Attachment1 = att1
		beam.Width0 = 34; beam.Width1 = 26; beam.FaceCamera = true; beam.Segments = 24
		beam.CurveSize0 = 30; beam.CurveSize1 = -24
		beam.LightEmission = 1; beam.LightInfluence = 0; beam.Brightness = 1.4
		beam.Color = ColorSequence.new(spec[3] :: Color3, spec[4] :: Color3)
		beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.7), NumberSequenceKeypoint.new(0.7, 0.76), NumberSequenceKeypoint.new(1, 1) })
		beam.Parent = anchor
	end
	-- snowfall over the deck and the ridge
	emitterVolume(set, CFrame.new(def.origin + Vector3.new(0, 34, 0)), Vector3.new(90, 1, 90), {
		Name = "Snowfall", Rate = 38, Lifetime = NumberRange.new(9, 13), Speed = NumberRange.new(3, 5),
		EmissionDirection = Enum.NormalId.Bottom, SpreadAngle = Vector2.new(12, 12), Acceleration = Vector3.new(1.2, 0, 0.4),
		Size = NumberSequence.new(0.22), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.1, 0.15), NumberSequenceKeypoint.new(0.85, 0.2), NumberSequenceKeypoint.new(1, 1) }),
		Color = ColorSequence.new(rgb(240, 246, 255)), LightInfluence = 0.6, Texture = "rbxasset://textures/particles/sparkles_main.dds",
		RotSpeed = NumberRange.new(-40, 40),
	})
end

--------------------------------------------------------------------------------------------------------------------
-- Jungle Ruins: a dense understory and giant trees, a closed high canopy, hanging vines, a ruined gate with glowing
-- glyphs, ground mist and fireflies.
--------------------------------------------------------------------------------------------------------------------
local function jungle(def: ArenaDef, set: Model)
	local rng = Kit.rng(62)
	local leaf = { rgb(44, 86, 42), rgb(58, 102, 48), rgb(36, 72, 38), rgb(66, 110, 52) }
	local canopy = Kit.model(set, "Canopy")
	local focus = FightSets.focusBearing(def)
	-- understory: low dense foliage that hides the plaza floor and the pads
	for _, b in FightSets.bearings(def, 8) do
		local p = atB(def, b + rng:NextNumber(-3, 3), rng:NextNumber(44.5, 48), rng:NextNumber(2, 4))
		Kit.blob(canopy, facingFight(def, p), Vector3.new(rng:NextNumber(11, 15), rng:NextNumber(7, 10), rng:NextNumber(7, 9)), M.LeafyGrass, leaf[rng:NextInteger(1, #leaf)], { Name = "Understory", CastShadow = false })
	end
	-- giant trees
	for _, b in FightSets.bearings(def, 13) do
		if diff(b, focus) < 14 then continue end -- the gate stands there
		local foot = atB(def, b + rng:NextNumber(-4, 4), rng:NextNumber(47, 56), 0)
		local tree = Props.tree(canopy, foot, rng:NextNumber(2.3, 3), rng, leaf)
		tree.Name = "GiantTree"
		Kit.step()
	end
	-- the high canopy that closes the sky behind the trees (dark, hazy), on far trunks
	for _, b in FightSets.bearings(def, 12) do
		local r = rng:NextNumber(60, 72)
		local p = atB(def, b + rng:NextNumber(-4, 4), r, rng:NextNumber(30, 38))
		Kit.blob(canopy, facingFight(def, p), Vector3.new(rng:NextNumber(40, 52), rng:NextNumber(22, 30), 28), M.LeafyGrass, leaf[rng:NextInteger(1, #leaf)], { Name = "HighCanopy", CastShadow = false })
		Kit.rod(canopy, Vector3.new(p.X, -1, p.Z), Vector3.new(p.X, p.Y - 8, p.Z), rng:NextNumber(3, 4.4), M.Wood, rgb(64, 50, 38), { Name = "FarTrunk", CastShadow = false })
	end
	-- jungle hills on the horizon
	farHills(def, set, "JungleHills", { rgb(46, 74, 44), rgb(54, 84, 50), rgb(40, 66, 40) }, M.LeafyGrass, { 62, 84 }, { 112, 128 }, 18, 72)
	-- hanging vines between the near trees
	local vines = Kit.model(set, "Vines")
	local spots = FightSets.bearings(def, 9)
	for i = 1, 16 do
		local b = spots[rng:NextInteger(1, #spots)]
		local top = atB(def, b + rng:NextNumber(-4, 4), rng:NextNumber(42, 47), rng:NextNumber(21, 27))
		local len = rng:NextNumber(10, 17)
		Kit.blob(vines, CFrame.new(top - Vector3.new(0, len / 2, 0)), Vector3.new(0.7, len, 0.7), M.LeafyGrass, rgb(54, 90, 44), { Name = "Vine" .. i, CastShadow = false })
	end
	-- ruined gate in the default camera's view: two pillars, a broken lintel and glyph tiles
	local gate = Kit.model(set, "RuinedGate")
	local stone, stoneDark, glyph = rgb(164, 154, 124), rgb(118, 110, 88), rgb(126, 226, 88)
	for _, side in { -1, 1 } do
		local foot = atB(def, focus + side * 11, 47, 0)
		local cf = facingFight(def, foot)
		Kit.block(gate, cf * CFrame.new(0, 8, 0), Vector3.new(4.6, 16, 4.6), M.Limestone, stone, { Name = "GatePillar" })
		Kit.block(gate, cf * CFrame.new(0, 16.4, 0), Vector3.new(5.8, 1, 5.8), M.Limestone, stoneDark, { Name = "GateCap" })
		Kit.glow(gate, cf * CFrame.new(0, 9.5, -2.35), Vector3.new(1.3, 1.3, 0.08), glyph, { Name = "GateGlyph", Transparency = 0.05 })
		Kit.glow(gate, cf * CFrame.new(0, 12.2, -2.35), Vector3.new(0.8, 0.8, 0.08), glyph, { Name = "GateGlyph", Transparency = 0.2 })
		Kit.blob(gate, cf * CFrame.new(0, 11, -1.8), Vector3.new(3.8, 9, 2.2), M.LeafyGrass, rgb(54, 88, 42), { Name = "GateMoss" })
	end
	Kit.strut(gate, atB(def, focus - 13, 47, 17.2), atB(def, focus + 7, 47, 18.6), 3.6, 2.4, M.Limestone, stone, { Name = "Lintel" })
	Kit.block(gate, facingFight(def, atB(def, focus + 15, 45, 0.8)) * CFrame.Angles(0.2, 0.5, 0.1), Vector3.new(5, 1.6, 2.6), M.Limestone, stoneDark, { Name = "FallenBlock" })
	-- mist that hugs the ground of the clearing, and fireflies in the shade
	emitterVolume(set, CFrame.new(def.origin + dirOf(focus) * 30 + Vector3.new(0, 1.5, 0)), Vector3.new(70, 1, 50), {
		Name = "GroundMist", Rate = 6, Lifetime = NumberRange.new(9, 14), Speed = NumberRange.new(0.3, 0.8),
		EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(70, 70), Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 8), NumberSequenceKeypoint.new(1, 16) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.84), NumberSequenceKeypoint.new(1, 1) }),
		Color = ColorSequence.new(rgb(214, 232, 206)), LightInfluence = 1, Texture = "rbxasset://textures/particles/smoke_main.dds",
		RotSpeed = NumberRange.new(-6, 6),
	})
	emitterVolume(set, CFrame.new(def.origin + Vector3.new(0, 6, 0)), Vector3.new(80, 10, 80), {
		Name = "Fireflies", Rate = 9, Lifetime = NumberRange.new(4, 7), Speed = NumberRange.new(0.2, 0.7),
		SpreadAngle = Vector2.new(180, 180), Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.28), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new(0.1), LightEmission = 1, Color = ColorSequence.new(rgb(220, 255, 140)),
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
	})
end

--------------------------------------------------------------------------------------------------------------------
-- Training Bay: a garden wall with lanterns, blossoming trees behind it and a pagoda; drifting petals.
--------------------------------------------------------------------------------------------------------------------
local function dojo(def: ArenaDef, set: Model)
	local rng = Kit.rng(63)
	local wall = Kit.model(set, "GardenWall")
	local plaster, timber, roof = rgb(236, 226, 206), rgb(96, 40, 32), rgb(58, 62, 72)
	local focus = FightSets.focusBearing(def)
	local step = 11
	for i, b in FightSets.bearings(def, step) do
		if not FightSets.covers(def, b + step) then continue end
		local p0, p1 = atB(def, b, 42, 0), atB(def, b + step, 42, 0)
		local mid = (p0 + p1) / 2
		local len = (flat(p1) - flat(p0)).Magnitude + 0.4
		local cf = CFrame.lookAt(mid, mid + (p1 - p0).Unit) * CFrame.Angles(0, math.rad(90), 0)
		Kit.block(wall, cf * CFrame.new(0, 3.8, 0), Vector3.new(len, 7.6, 1.4), M.Plaster, plaster, { Name = "WallPanel" })
		Kit.block(wall, cf * CFrame.new(0, 0.6, 0), Vector3.new(len, 1.2, 1.6), M.Wood, timber, { Name = "WallSill" })
		Kit.wedge(wall, cf * CFrame.new(0, 8.15, -0.6) * CFrame.Angles(0, math.pi, 0), Vector3.new(len, 1.1, 1.4), M.Slate, roof, { Name = "WallRoof" })
		Kit.wedge(wall, cf * CFrame.new(0, 8.15, 0.6), Vector3.new(len, 1.1, 1.4), M.Slate, roof, { Name = "WallRoof" })
		Kit.block(wall, cf * CFrame.new(len / 2, 4.2, 0), Vector3.new(0.9, 8.4, 1.8), M.Wood, timber, { Name = "WallPost" })
		if i % 2 == 0 then
			local lanternTop = (cf * CFrame.new(0, 7.5, 1.3)).Position
			Props.hangingLantern(wall, lanternTop, rgb(255, 196, 120), 1, false)
		end
		Kit.step()
	end
	-- blossoming trees behind the wall
	local blossom = { rgb(250, 186, 206), rgb(244, 160, 190), rgb(255, 210, 222) }
	for _, b in FightSets.bearings(def, 16) do
		local foot = atB(def, b + rng:NextNumber(-5, 5), rng:NextNumber(49, 56), 0)
		local t = Props.tree(set, foot, rng:NextNumber(1.8, 2.3), rng, blossom)
		t.Name = "BlossomTree"
		Kit.step()
	end
	-- a five-roof pagoda in the default camera's view
	local pagoda = Kit.model(set, "Pagoda")
	local c = atB(def, focus, 76, 0)
	local f = facingFight(def, c)
	for k = 0, 4 do
		local w = 16 - k * 2.4
		local y = 2 + k * 7
		Kit.block(pagoda, f * CFrame.new(0, y + 2.4, 0), Vector3.new(w * 0.62, 4.8, w * 0.62), M.Plaster, plaster, { Name = "PagodaStory" })
		Kit.block(pagoda, f * CFrame.new(0, y + 5.1, 0), Vector3.new(w, 0.8, w), M.Slate, roof, { Name = "PagodaRoof" })
		Kit.block(pagoda, f * CFrame.new(0, y + 4.6, 0), Vector3.new(w + 0.4, 0.3, w + 0.4), M.Wood, timber, { Name = "PagodaEave" })
		Kit.glow(pagoda, f * CFrame.new(0, y + 2.4, -w * 0.31 - 0.06), Vector3.new(w * 0.3, 2.6, 0.08), rgb(255, 214, 150), { Name = "PagodaWindow", Transparency = 0.25 })
	end
	Kit.cylinder(pagoda, f * CFrame.new(0, 43, 0), 8, 0.5, M.Metal, rgb(196, 160, 86), { Name = "Spire" })
	-- misty blue mountains across the bay close the horizon
	farHills(def, set, "Mountains", { rgb(92, 104, 126), rgb(104, 114, 136), rgb(86, 96, 120) }, M.Rock, { 64, 86 }, { 116, 132 }, 20, 73)
	-- students watching from in front of the wall
	local robes = { rgb(236, 232, 222), rgb(40, 52, 92), rgb(150, 44, 38), rgb(220, 214, 200) }
	for i, off in { -27, -9, 9, 27 } do
		crowd(def, set, focus + off, 39.6, 11, 0, robes, 80 + i)
	end
	-- drifting blossom petals
	emitterVolume(set, CFrame.new(def.origin + Vector3.new(0, 18, 0)), Vector3.new(70, 1, 70), {
		Name = "Petals", Rate = 12, Lifetime = NumberRange.new(7, 11), Speed = NumberRange.new(1, 2),
		EmissionDirection = Enum.NormalId.Bottom, SpreadAngle = Vector2.new(30, 30), Acceleration = Vector3.new(0.8, -0.2, 0.5),
		Size = NumberSequence.new(0.26), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.1, 0.1), NumberSequenceKeypoint.new(0.9, 0.2), NumberSequenceKeypoint.new(1, 1) }),
		Color = ColorSequence.new(rgb(255, 196, 214)), LightInfluence = 0.8, Texture = "rbxasset://textures/particles/sparkles_main.dds",
		RotSpeed = NumberRange.new(-90, 90), Rotation = NumberRange.new(0, 360),
	})
end

--------------------------------------------------------------------------------------------------------------------
-- Harbor Dusk: stacked freight, a lit warehouse and a crane on the quay; warm dust in the low sun.
--------------------------------------------------------------------------------------------------------------------
local function harbor(def: ArenaDef, set: Model)
	local rng = Kit.rng(64)
	local quay = Kit.model(set, "Quay")
	local colors = Props.CONTAINER_COLORS
	local focus = FightSets.focusBearing(def)
	for _, b in FightSets.bearings(def, 24) do
		if diff(b, focus) < 20 then continue end -- the warehouse stands there
		local p = atB(def, b + rng:NextNumber(-4, 4), rng:NextNumber(46, 52), -0.2)
		local cf = facingFight(def, p) * CFrame.Angles(0, math.rad(90 + rng:NextNumber(-8, 8)), 0)
		local stack = rng:NextInteger(2, 3)
		for k = 0, stack - 1 do
			Props.container(quay, cf * CFrame.new(rng:NextNumber(-0.8, 0.8), k * 8.6, 0), colors[rng:NextInteger(1, #colors)], rng, k == stack - 1)
		end
		Kit.step()
	end
	-- warehouse in the default camera's view, with lit loading bays and its sign
	local wp = atB(def, focus, 56, -0.2)
	local wf = facingFight(def, wp)
	local body = Kit.block(quay, wf * CFrame.new(0, 11, 0), Vector3.new(46, 22, 14), M.CorrodedMetal, rgb(92, 84, 78), { Name = "Warehouse" })
	Props.windows(body, Enum.NormalId.Front, rng, { floorHeight = 7, bayWidth = 6, lit = 0.45, band = rgb(64, 58, 54), skipBottom = 6 })
	Kit.block(quay, wf * CFrame.new(0, 22.6, 0), Vector3.new(47, 1.2, 15), M.Metal, rgb(60, 56, 54), { Name = "WarehouseRoof" })
	Props.neonSign(quay, wf * CFrame.new(0, 18.2, -7.4), 20, 3.4, "PIER 9 FREIGHT", rgb(255, 152, 54), Enum.Font.Oswald, false)
	for _, x in { -14, 0, 14 } do
		Kit.glow(quay, wf * CFrame.new(x, 2.8, -7.05), Vector3.new(8, 5.4, 0.1), rgb(255, 186, 110), { Name = "LoadingBay", Transparency = 0.35 })
	end
	-- dock workers watching from the quay
	local overalls = { rgb(214, 132, 40), rgb(60, 90, 140), rgb(120, 120, 128), rgb(176, 58, 44) }
	for i, off in { -22, -4, 14 } do
		crowd(def, set, focus + off, 40, 12, -0.2, overalls, 90 + i)
	end
	-- a dock crane leaning over the freight
	Props.crane(set, atB(def, focus + 40, 70, -0.2), dirOf(focus + 200), rng, rgb(196, 54, 44))
	-- warm dust in the low sun
	emitterVolume(set, CFrame.new(def.origin + Vector3.new(0, 8, 0)), Vector3.new(60, 8, 60), {
		Name = "SunDust", Rate = 6, Lifetime = NumberRange.new(6, 9), Speed = NumberRange.new(0.1, 0.3),
		SpreadAngle = Vector2.new(180, 180), Size = NumberSequence.new(0.12), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.3), NumberSequenceKeypoint.new(1, 1) }),
		LightEmission = 0.8, Color = ColorSequence.new(rgb(255, 214, 160)), Texture = "rbxasset://textures/particles/sparkles_main.dds",
	})
end

--------------------------------------------------------------------------------------------------------------------
-- Midnight Rooftop: neighbouring rooftops with water tanks, antennas and a big neon billboard; drizzle.
--------------------------------------------------------------------------------------------------------------------
local function rooftop(def: ArenaDef, set: Model)
	local rng = Kit.rng(65)
	local roofs = Kit.model(set, "Rooftops")
	local neon = { rgb(255, 72, 196), rgb(60, 220, 255), rgb(150, 90, 255), rgb(255, 186, 90) }
	local focus = FightSets.focusBearing(def)
	for i, b in FightSets.bearings(def, 27) do
		local r = rng:NextNumber(52, 62)
		local w = rng:NextNumber(18, 24)
		local top = def.floorY + rng:NextNumber(-2, 10)
		local p = atB(def, b + rng:NextNumber(-4, 4), r, -2)
		local cf = facingFight(def, p)
		local h = top + 2
		local body = Kit.block(roofs, cf * CFrame.new(0, h / 2, 0), Vector3.new(w, h, 16), M.Concrete, rgb(48, 52, 70):Lerp(rgb(70, 74, 96), rng:NextNumber()), { Name = "Building" })
		Props.windows(body, Enum.NormalId.Front, rng, { lit = 0.42, band = rgb(36, 40, 54), floorHeight = 5, bayWidth = 3.4 })
		Kit.glow(roofs, cf * CFrame.new(0, h + 0.2, -8.1), Vector3.new(w, 0.3, 0.3), neon[(i - 1) % #neon + 1], { Name = "RoofNeon" })
		if i % 2 == 1 then
			local tank = cf * CFrame.new(rng:NextNumber(-w / 4, w / 4), h, 2)
			for _, o in { Vector3.new(-1.8, 0, -1.8), Vector3.new(1.8, 0, -1.8), Vector3.new(-1.8, 0, 1.8), Vector3.new(1.8, 0, 1.8) } do
				Kit.deco(roofs, tank * CFrame.new(o + Vector3.new(0, 2.2, 0)), Vector3.new(0.4, 4.4, 0.4), M.Metal, rgb(30, 32, 40))
			end
			Kit.cylinder(roofs, (tank * CFrame.new(0, 7, 0)).Position, 5, 5.4, M.WoodPlanks, rgb(110, 84, 64), { Name = "WaterTank" })
		else
			local mast = (cf * CFrame.new(rng:NextNumber(-w / 4, w / 4), h, 3)).Position
			Kit.cylinder(roofs, mast + Vector3.new(0, 5, 0), 10, 0.35, M.Metal, rgb(140, 144, 152), { Name = "Antenna", CastShadow = false })
			Kit.glow(roofs, CFrame.new(mast + Vector3.new(0, 10.3, 0)), Vector3.new(0.6, 0.6, 0.6), rgb(255, 40, 40), { Name = "AirBeacon" })
		end
		Kit.step()
	end
	-- a crowd on the neighbouring terrace, a step below the deck
	local party = { rgb(255, 72, 196), rgb(60, 220, 255), rgb(150, 90, 255), rgb(240, 240, 250) }
	for i, off in { -24, -6, 12, 30 } do
		crowd(def, set, focus + off, 39.4, 12, def.floorY - 1.2, party, 100 + i)
	end
	-- a big billboard on the plaza side, lit by its own neon frame
	local bp = atB(def, focus, 70, def.floorY + 16)
	Props.neonSign(roofs, facingFight(def, bp), 30, 9, "NIGHT SHIFT", rgb(60, 220, 255), Enum.Font.Sarpanch, false)
	-- far towers closing the horizon
	for _, b in FightSets.bearings(def, 38) do
		local p = atB(def, b + rng:NextNumber(-5, 5), rng:NextNumber(96, 120), -2)
		Props.tower(roofs, p, rng:NextNumber(20, 28), rng:NextNumber(18, 24), rng:NextNumber(60, 100), rng, { neon = neon[rng:NextInteger(1, #neon)], lit = 0.34, faces = { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right }, mast = false })
		Kit.step()
	end
	-- a fine drizzle over the deck
	emitterVolume(set, CFrame.new(def.origin + Vector3.new(0, 30, 0)), Vector3.new(80, 1, 80), {
		Name = "Drizzle", Rate = 30, Lifetime = NumberRange.new(2.2, 3), Speed = NumberRange.new(16, 20),
		EmissionDirection = Enum.NormalId.Bottom, SpreadAngle = Vector2.new(3, 3), Size = NumberSequence.new(0.06),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.1, 0.55), NumberSequenceKeypoint.new(1, 0.7) }),
		Color = ColorSequence.new(rgb(190, 200, 255)), LightInfluence = 0.4, Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Orientation = Enum.ParticleOrientation.VelocityParallel,
	})
end

local BUILDERS: { [string]: (ArenaDef, Model) -> () } = {
	SnowSummit = summit, JungleRuins = jungle, TrainingBay = dojo, HarborDusk = harbor, MidnightRooftop = rooftop,
}
FightSets.STAGES = { "SnowSummit", "JungleRuins", "TrainingBay", "HarborDusk", "MidnightRooftop" }

export type Report = { parts: number, lights: number, emitters: number }

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
			local parts, lights, emitters = 0, 0, 0
			for _, d in set:GetDescendants() do
				if d:IsA("BasePart") then parts += 1 elseif d:IsA("Light") then lights += 1 elseif d:IsA("ParticleEmitter") then emitters += 1 end
			end
			set:SetAttribute("PartCount", parts)
			reports[def.stageId] = { parts = parts, lights = lights, emitters = emitters }
			set.Parent = folder
			Kit.step()
		end
	end
	for k, v in saved do Kit.stats[k] = v end
	folder.Parent = lab
	return reports, folder
end

return FightSets
