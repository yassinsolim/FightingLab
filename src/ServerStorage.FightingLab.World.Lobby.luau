--!strict
-- World.Lobby: "Ember Square", the round plaza at the heart of the district (floor top Y = 0, origin-centred) and its
-- head on the open side of the stage horseshoe. Contract pieces: six LobbySpawn plates (a tight spawn court on the
-- plaza centre, everyone facing the plaza head), FighterKiosk (PromptPart + ChooseFighter prompt) and the Hall of
-- Champions' Leaderboard flanking the head, and the Signpost with an arm per arena. Dressing: the Ember Beacon
-- fountain tower at the head of the plaza, concentric paving, wayfinding lines in each arena's colour from the spawn
-- court to its pads, lamps, benches and festoon lights. Everything that rises above a fight floor + 1.5 stays outside
-- every fight camera's orbit (Layout.CAMERA_ORBIT from each FightOrigin).
local Kit = require(script.Parent.Kit)
local Props = require(script.Parent.Props)
local Layout = require(script.Parent.Layout)
local AssetKit = require(script.Parent.AssetKit)

local Lobby = {}

local M = Enum.Material

local C = {
	band = Color3.fromRGB(164, 96, 68),
	court = Color3.fromRGB(226, 212, 186),
	courtTile = Color3.fromRGB(204, 186, 158),
	stone = Color3.fromRGB(214, 200, 176),
	granite = Color3.fromRGB(88, 82, 80),
	bronze = Color3.fromRGB(176, 128, 62),
	brass = Color3.fromRGB(204, 166, 92),
	water = Color3.fromRGB(64, 170, 190),
	basinFloor = Color3.fromRGB(48, 92, 104),
	ember = Color3.fromRGB(255, 96, 24),
	emberCore = Color3.fromRGB(255, 176, 90),
	screen = Color3.fromRGB(14, 16, 22),
	metalDark = Color3.fromRGB(42, 44, 52),
	cream = Color3.fromRGB(246, 236, 214),
}
Lobby.colors = C

Lobby.COURT_CENTRE = Vector3.zero
-- The plaza head (the open side of the stage horseshoe): the beacon on its axis, the kiosk and the hall either side,
-- all facing the spawn court and all outside every fight camera's orbit.
Lobby.HEAD_BEARING = Layout.PLAZA_HEAD_BEARING
Lobby.KIOSK_BEARING = Layout.PLAZA_HEAD_BEARING - 21
Lobby.HALL_BEARING = Layout.PLAZA_HEAD_BEARING + 21
Lobby.SIDE_RADIUS = 36
Lobby.BEACON_DISTANCE = 44
Lobby.BEACON_CENTRE = Layout.polar(Layout.PLAZA_HEAD_BEARING, Lobby.BEACON_DISTANCE)
Lobby.BEACON_BASIN_RADIUS = 7
Lobby.SIGNPOST_POSITION = Layout.polar(Layout.PLAZA_HEAD_BEARING, 15.5)

local polar = Layout.polar

local function disc(parent: Instance, radius: number, top: number, material: Enum.Material, color: Color3, props: Kit.Props?, centre: Vector3?): Part
	local h = 0.6
	local c = centre or Vector3.zero
	return Kit.cylinder(parent, Vector3.new(c.X, top - h / 2, c.Z), h, radius * 2, material, color, props)
end

-- Paving: nested discs a hair apart give clean concentric rings without z-fighting (the district floor below is 0).
-- Heights in use: kerb 0.015, band 0.03, court 0.05, beacon band 0.06, court ring 0.07, beacon court 0.08,
-- court inner 0.09, pad halos 0.11, promenade 0.13, wayfinding inlays 0.16-0.19, name mats 0.22.
local function buildPaving(m: Model)
	disc(m, 33.4, 0.03, M.Brick, C.band, { Name = "PlazaBand", CastShadow = false })
	disc(m, 32, 0.05, M.Pavement, C.court, { Name = "PlazaCourt", CastShadow = false })
	disc(m, Layout.SPAWN_COURT_RADIUS + 0.8, 0.07, M.Marble, C.courtTile, { Name = "CourtRing", CastShadow = false })
	disc(m, Layout.SPAWN_COURT_RADIUS, 0.09, M.Pavement, C.court, { Name = "CourtInner", CastShadow = false })
	-- the beacon's own round court at the head of the plaza, and a cream promenade leading to it
	disc(m, Lobby.BEACON_BASIN_RADIUS + 6.4, 0.06, M.Brick, C.band, { Name = "BeaconBand", CastShadow = false }, Lobby.BEACON_CENTRE)
	disc(m, Lobby.BEACON_BASIN_RADIUS + 5.6, 0.08, M.Pavement, C.court, { Name = "BeaconCourt", CastShadow = false }, Lobby.BEACON_CENTRE)
	local head = Layout.bearingDir(Lobby.HEAD_BEARING)
	local p0 = head * (Layout.SPAWN_COURT_RADIUS + 1)
	local p1 = Lobby.BEACON_CENTRE - head * (Lobby.BEACON_BASIN_RADIUS + 5)
	local pm = (p0 + p1) / 2
	Kit.deco(m, CFrame.lookAt(pm + Vector3.new(0, 0.09, 0), pm + Vector3.new(0, 0.09, 0) + head), Vector3.new(5, 0.08, (p1 - p0).Magnitude), M.Marble, C.cream, { Name = "Promenade", CastShadow = false })
	-- wayfinding lines in each arena's colour from the spawn court to the name mat at the foot of its stair (they run
	-- between the arena's two pads, through its Arrival spot)
	for _, def in Layout.ARENAS do
		local dir = Layout.bearingDir(def.bearing)
		local foot = Layout.stairFoot(def)
		local a = dir * (Layout.SPAWN_COURT_RADIUS + 1)
		local b = Vector3.new(foot.X, 0, foot.Z) + def.inward * 4.6
		local mid = (a + b) / 2
		local len = (b - a).Magnitude
		local cf = CFrame.lookAt(mid + Vector3.new(0, 0.12, 0), mid + Vector3.new(0, 0.12, 0) + dir)
		Kit.deco(m, cf, Vector3.new(2.4, 0.08, len), M.Marble, Kit.mix(def.accent, C.cream, 0.5), { Name = "WayLine", CastShadow = false })
		Kit.glow(m, cf * CFrame.new(0, 0.03, 0), Vector3.new(0.5, 0.06, len), def.accent, { Name = "WayGlow", Transparency = 0.1 })
		-- arrow chevrons along the line, pointing at the arena
		for k = 1, math.floor(len / 6) do
			local p = a + dir * (k * 6 - 1)
			local ccf = CFrame.lookAt(p + Vector3.new(0, 0.17, 0), p + Vector3.new(0, 0.17, 0) + dir)
			for _, s in { -1, 1 } do
				Kit.glow(m, ccf * CFrame.new(s * 0.55, 0, 0.4) * CFrame.Angles(0, math.rad(s * 40), 0), Vector3.new(0.3, 0.04, 1.5), def.accent, { Name = "WayChevron", Transparency = 0.15 })
			end
		end
	end
end

-- The Ember Beacon: octagonal fountain basin, slim tiered stone tower, bronze crown and a glowing ember crystal. Built
-- round the origin, then moved to the head of the plaza (Lobby.BEACON_CENTRE).
local function buildBeacon(m: Model)
	local beacon = Kit.model(m, "EmberBeacon")
	local apothem = Lobby.BEACON_BASIN_RADIUS - 0.7
	local side = 2 * apothem * math.tan(math.rad(22.5))
	disc(beacon, apothem + 0.2, 0.2, M.Slate, C.basinFloor, { Name = "BasinFloor" })
	Kit.cylinder(beacon, Vector3.new(0, 0.55, 0), 0.7, apothem * 2, M.Glass, C.water, { Name = "Water", Transparency = 0.42, CanCollide = false, CastShadow = false })
	for i = 0, 7 do
		local a = i * math.pi / 4 + math.pi / 8
		local dir = Vector3.new(math.sin(a), 0, -math.cos(a))
		local centre = dir * apothem + Vector3.new(0, 0.7, 0)
		local cf = CFrame.lookAt(centre, centre + dir)
		Kit.block(beacon, cf, Vector3.new(side + 0.1, 1.4, 1.2), M.Limestone, C.stone, { Name = "Rim" })
		-- caps overlap at the corners: alternate ones sit 0.012 higher so the joints never z-fight
		Kit.block(beacon, cf * CFrame.new(0, 0.8 + (i % 2) * 0.012, 0), Vector3.new(side + 0.4, 0.2, 1.6), M.Marble, C.cream, { Name = "RimCap" })
		local corner = Vector3.new(math.sin(a + math.pi / 8), 0, -math.cos(a + math.pi / 8)) * (apothem / math.cos(math.rad(22.5)))
		Kit.cylinder(beacon, corner + Vector3.new(0, 1, 0), 2, 1.5, M.Limestone, C.stone, { Name = "RimPost" })
		Kit.ball(beacon, corner + Vector3.new(0, 2.25, 0), 0.7, M.Metal, C.brass, { CanCollide = false, CastShadow = false })
		if i % 2 == 0 then
			local spoutPos = dir * 3.2 + Vector3.new(0, 4.6, 0)
			local spout = Kit.deco(beacon, CFrame.lookAt(spoutPos, spoutPos + dir), Vector3.new(0.5, 0.5, 1), M.Metal, C.bronze, { Name = "Spout" })
			Kit.emitter(spout, {
				Name = "Jet",
				Color = Kit.colors(Color3.fromRGB(220, 244, 255)),
				LightEmission = 0.3,
				LightInfluence = 1,
				Size = Kit.numbers(0.3, 0.5, 0.2),
				Transparency = Kit.numbers(0.25, 0.45, 1),
				Lifetime = NumberRange.new(0.55, 0.7),
				Rate = 30,
				Speed = NumberRange.new(5, 6),
				SpreadAngle = Vector2.new(3, 3),
				Acceleration = Vector3.new(0, -30, 0),
				EmissionDirection = Enum.NormalId.Front,
				Texture = "rbxasset://textures/particles/smoke_main.dds",
			})
		end
	end
	-- the fountain is not a short cut: an invisible collider keeps walkers (and paths) round the basin
	Kit.cylinder(beacon, Vector3.new(0, 2, 0), 4, Lobby.BEACON_BASIN_RADIUS * 2 + 0.4, M.SmoothPlastic, C.water, { Name = "BasinCollider", Transparency = 1, CastShadow = false })
	-- tower
	Kit.cylinder(beacon, Vector3.new(0, 1.6, 0), 3.2, 6.4, M.Granite, C.granite, { Name = "Plinth" })
	Kit.cylinder(beacon, Vector3.new(0, 3.5, 0), 0.6, 5.6, M.Marble, C.cream, { Name = "PlinthStep" })
	local tiers = { { 3.8, 17, 4.4 }, { 17.6, 29, 3.6 }, { 29.6, 37, 2.8 } }
	for i, t in tiers do
		local h = t[2] - t[1]
		Kit.cylinder(beacon, Vector3.new(0, t[1] + h / 2, 0), h, t[3], M.Limestone, if i == 2 then C.court else C.stone, { Name = "Shaft" })
		Kit.cylinder(beacon, Vector3.new(0, t[2] + 0.3, 0), 0.6, t[3] + 0.7, M.Metal, C.bronze, { Name = "Band", CanCollide = false })
	end
	for i = 0, 11 do
		local a = i * math.pi / 6
		local p = Vector3.new(math.sin(a) * 2.2, 11, -math.cos(a) * 2.2)
		Kit.deco(beacon, CFrame.lookAt(p, Vector3.new(0, 11, 0)), Vector3.new(0.4, 10, 0.25), M.Limestone, C.cream, { Name = "Flute" })
	end
	local crown = Vector3.new(0, 42.5, 0)
	for i = 0, 3 do
		local a = i * math.pi / 2 + math.pi / 4
		local dir = Vector3.new(math.sin(a), 0, -math.cos(a))
		local foot = dir * 1.3 + Vector3.new(0, 37.5, 0)
		local elbow = dir * 3.2 + Vector3.new(0, 40.2, 0)
		local tip = dir * 2 + Vector3.new(0, 44, 0)
		Kit.strut(beacon, foot, elbow, 0.45, 0.45, M.Metal, C.bronze, { Name = "CrownArm", CanCollide = false })
		Kit.strut(beacon, elbow, tip, 0.4, 0.4, M.Metal, C.bronze, { Name = "CrownArm", CanCollide = false })
		Kit.ball(beacon, elbow, 0.8, M.Metal, C.brass, { CanCollide = false })
	end
	local crystal = Kit.glow(beacon, CFrame.new(crown) * CFrame.Angles(math.rad(45), 0, math.rad(35.26)), Vector3.new(3.8, 3.8, 3.8), C.ember, { Name = "EmberCrystal" })
	Kit.glow(beacon, CFrame.new(crown) * CFrame.Angles(math.rad(45), math.rad(20), math.rad(35.26)), Vector3.new(2.2, 2.2, 2.2), C.emberCore, { Name = "EmberCore" })
	Kit.point(crystal, C.ember, 2, 40, false)
	Kit.emitter(crystal, {
		Name = "Embers",
		Color = Kit.colors(Color3.fromRGB(255, 210, 120), Color3.fromRGB(255, 90, 30)),
		LightEmission = 1,
		Size = Kit.numbers(0.32, 0.2, 0),
		Transparency = Kit.numbers(0, 0.2, 1),
		Lifetime = NumberRange.new(2.5, 4),
		Rate = 10,
		Speed = NumberRange.new(2, 4.5),
		SpreadAngle = Vector2.new(70, 70),
		Acceleration = Vector3.new(1.2, 1.5, 0.6),
		Drag = 0.4,
		EmissionDirection = Enum.NormalId.Top,
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
	})
	-- orbit rings (LobbyAmbience spins them on clients)
	for ring = 1, 2 do
		local rm = Kit.model(beacon, "OrbitRing" .. ring)
		rm:SetAttribute("SpinSpeed", if ring == 1 then 0.35 else -0.25)
		local tilt = CFrame.new(crown) * CFrame.Angles(math.rad(if ring == 1 then 18 else -24), 0, math.rad(if ring == 1 then 8 else -12))
		for i = 0, 15 do
			local a = i / 16 * math.pi * 2
			local cf = tilt * CFrame.new(math.cos(a) * 4.2, 0, math.sin(a) * 4.2) * CFrame.Angles(0, -a, 0)
			Kit.deco(rm, cf, Vector3.new(0.28, 0.28, 1.6), if i % 4 == 0 then M.Neon else M.Metal, if i % 4 == 0 then C.ember else C.brass, { Name = "RingSegment" })
		end
		rm.WorldPivot = tilt
	end
	-- long banners on the tower in the duel colours
	local bannerColors = { Layout.P1_COLOR, Layout.P2_COLOR, Layout.P1_COLOR, Layout.P2_COLOR }
	for i = 0, 3 do
		local a = i * math.pi / 2
		local dir = Vector3.new(math.sin(a), 0, -math.cos(a))
		Props.banner(beacon, dir * 2.05 + Vector3.new(0, 28.2, 0), dir, 2, 8, bannerColors[i + 1], if i % 2 == 0 then "FIGHT" else "LAB", Color3.new(1, 1, 1))
	end
	-- warm uplights washing the tower
	for i = 0, 3 do
		local a = i * math.pi / 2 + math.pi / 4
		local p = Vector3.new(math.sin(a) * 3.6, 3.3, -math.cos(a) * 3.6)
		local cup = Kit.deco(beacon, CFrame.lookAt(p, Vector3.new(0, 22, 0)), Vector3.new(0.8, 0.8, 0.5), M.Metal, C.metalDark, { Name = "Uplight" })
		Kit.spot(cup, Enum.NormalId.Front, Color3.fromRGB(255, 214, 160), 2.6, 32, 30, false)
	end
	local plume = Kit.deco(beacon, CFrame.new(0, 1.2, 0), Vector3.new(10, 0.2, 10), M.SmoothPlastic, C.water, { Name = "PlumeSource", Transparency = 1 })
	Kit.emitter(plume, {
		Name = "Mist",
		Color = Kit.colors(Color3.fromRGB(230, 246, 255)),
		LightInfluence = 1,
		LightEmission = 0.1,
		Size = Kit.numbers(1, 2.2),
		Transparency = Kit.numbers(0.75, 1),
		Lifetime = NumberRange.new(1, 1.8),
		Rate = 8,
		Speed = NumberRange.new(0.8, 2),
		SpreadAngle = Vector2.new(30, 30),
		EmissionDirection = Enum.NormalId.Top,
		Texture = "rbxasset://textures/particles/smoke_main.dds",
	})
	-- move the whole beacon to the head of the plaza (the orbit rings keep their pivots for LobbyAmbience)
	local offset = Lobby.BEACON_CENTRE
	for _, d in beacon:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame += offset
		elseif d:IsA("Model") then
			d.WorldPivot += offset
		end
	end
	beacon.WorldPivot = CFrame.new(offset)
end

local function buildSpawns(m: Model)
	local facing = Layout.bearingDir(Layout.SPAWN_FACING)
	for i, pos in Layout.SPAWN_POINTS do
		local cf = CFrame.lookAt(pos + Vector3.new(0, 0.05, 0), pos + Vector3.new(0, 0.05, 0) + facing)
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "LobbySpawn"
		spawn.Anchored = true
		spawn.Size = Vector3.new(5, 0.2, 5)
		spawn.CFrame = cf
		spawn.Transparency = 1
		spawn.CanCollide = true
		spawn.CastShadow = false
		spawn.Neutral = true
		spawn.Enabled = true
		spawn.Duration = 0
		spawn.AllowTeamChangeOnTouch = false
		spawn:SetAttribute("SpawnIndex", i)
		Kit.passThrough(spawn)
		spawn.Parent = m
		Kit.stats.parts += 1
		-- medallion: bronze ring, ember glow rim, marble disc, bronze and terracotta centre (flush, no glare)
		Kit.cylinder(m, pos + Vector3.new(0, 0.12, 0), 0.08, 4.8, M.Metal, C.bronze, { Name = "SpawnRing", CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
		Kit.cylinder(m, pos + Vector3.new(0, 0.135, 0), 0.08, 4.2, M.Neon, C.ember, { Name = "SpawnGlow", CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false, Transparency = 0.3 })
		Kit.cylinder(m, pos + Vector3.new(0, 0.15, 0), 0.08, 3.9, M.Marble, C.cream, { Name = "SpawnDisc", CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
		Kit.cylinder(m, pos + Vector3.new(0, 0.165, 0), 0.08, 1.6, M.Metal, C.bronze, { Name = "SpawnInner", CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
		Kit.cylinder(m, pos + Vector3.new(0, 0.18, 0), 0.08, 1.1, M.CeramicTiles, C.band, { Name = "SpawnCore", CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
	end
end

-- Fingerpost on the promenade just ahead of the spawn court: one arm per arena, pointing at its stair.
local function buildFingerpost(m: Model)
	local fp = Kit.model(m, "Signpost")
	local base = Lobby.SIGNPOST_POSITION
	Kit.block(fp, CFrame.new(base + Vector3.new(0, 0.4, 0)), Vector3.new(2.4, 0.8, 2.4), M.Granite, C.granite, { Name = "PostBase" })
	Kit.cylinder(fp, base + Vector3.new(0, 6.2, 0), 11.4, 0.55, M.Metal, C.metalDark, { Name = "Post" })
	Kit.ball(fp, base + Vector3.new(0, 12.1, 0), 1, M.Neon, C.ember, { CanCollide = false })
	local arms = table.clone(Layout.ARENAS)
	table.sort(arms, function(a, b) return a.order < b.order end)
	for i, def in arms do
		local foot = Layout.stairFoot(def)
		local dir = Vector3.new(foot.X - base.X, 0, foot.Z - base.Z).Unit
		local y = 10.8 - (i - 1) * 1.15
		local centre = base + Vector3.new(0, y, 0) + dir * 3.7
		local cf = CFrame.lookAt(centre, centre + dir) * CFrame.Angles(0, math.pi / 2, 0)
		local arm = Kit.deco(fp, cf, Vector3.new(6.2, 0.95, 0.2), M.Metal, Color3.fromRGB(28, 30, 38), { Name = "Arm_" .. def.stageId, CastShadow = true })
		Kit.deco(fp, cf * CFrame.new(3.35, 0, 0) * CFrame.Angles(0, 0, math.rad(45)), Vector3.new(0.68, 0.68, 0.2), M.Neon, def.accent, { Name = "ArmTip" })
		Kit.glow(fp, cf * CFrame.new(0, -0.5, 0), Vector3.new(6.2, 0.08, 0.22), def.accent)
		for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
			Kit.label(arm, face, string.upper(def.displayName), {
				font = Enum.Font.GothamBold,
				color = Color3.new(1, 1, 1),
				pps = 40,
				padding = 0.1,
				brightness = 1.4,
			})
		end
	end
end

local function sideFrame(bearing: number): CFrame
	local pos = polar(bearing, Lobby.SIDE_RADIUS)
	local face = Vector3.new(Lobby.COURT_CENTRE.X - pos.X, 0, Lobby.COURT_CENTRE.Z - pos.Z).Unit
	return Kit.facing(pos, face)
end

local function buildKiosk(m: Model)
	local kiosk = Kit.model(m, "FighterKiosk")
	local cf = sideFrame(Lobby.KIOSK_BEARING)
	local accentL, accentR = Layout.P1_COLOR, Layout.P2_COLOR
	Kit.block(kiosk, cf * CFrame.new(0, 0.25, 1.2), Vector3.new(15, 0.5, 9.5), M.Granite, C.granite, { Name = "Dais" })
	Kit.glow(kiosk, cf * CFrame.new(0, 0.3, -3.6), Vector3.new(15, 0.12, 0.2), C.ember, { Name = "DaisTrim" })
	local backwall = Kit.block(kiosk, cf * CFrame.new(0, 5.3, 5.3), Vector3.new(15, 9.6, 1), M.Metal, C.metalDark, { Name = "Backwall" })
	Kit.label(backwall, Enum.NormalId.Back, "FIGHTER\nKIOSK", { font = Enum.Font.GothamBlack, color = Color3.fromRGB(255, 214, 150), pps = 20, padding = 0.2, brightness = 1.3, name = "BackText", textSize = 40 })
	local screen = Kit.deco(kiosk, cf * CFrame.new(0, 5.9, 4.72), Vector3.new(13, 7.2, 0.15), M.SmoothPlastic, C.screen, { Name = "Screen" })
	local sg = Kit.label(screen, Enum.NormalId.Front, "", { pps = 40, brightness = 1.6, name = "KioskScreen" })
	local text = sg:FindFirstChild("Text") :: TextLabel
	text:Destroy()
	local grad = Instance.new("Frame")
	grad.Size = UDim2.fromScale(1, 1)
	grad.BackgroundColor3 = Color3.fromRGB(26, 22, 40)
	grad.BorderSizePixel = 0
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(Color3.fromRGB(70, 30, 20), Color3.fromRGB(16, 40, 64))
	g.Parent = grad
	grad.Parent = sg
	local function line(txt: string, y: number, h: number, font: Enum.Font, color: Color3)
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Position = UDim2.fromScale(0.05, y)
		t.Size = UDim2.fromScale(0.9, h)
		t.Font = font
		t.Text = txt
		t.TextScaled = true
		t.TextColor3 = color
		t.Parent = sg
	end
	line("CHOOSE YOUR FIGHTER", 0.1, 0.24, Enum.Font.GothamBlack, Color3.new(1, 1, 1))
	line("KAEL  ·  SIERRA  ·  GORAN  ·  LUMI  ·  RHYS  ·  NIA", 0.42, 0.12, Enum.Font.GothamBold, Color3.fromRGB(255, 214, 150))
	line("Step up to the console  [E]", 0.68, 0.1, Enum.Font.Gotham, Color3.fromRGB(190, 225, 255))
	for _, s in { -1, 1 } do
		Kit.block(kiosk, cf * CFrame.new(s * 7.2, 5.4, 5.3), Vector3.new(0.9, 10.8, 1.3), M.Metal, Color3.fromRGB(60, 62, 70), { Name = "Pillar" })
		Kit.glow(kiosk, cf * CFrame.new(s * 7.2, 5.4, 4.58), Vector3.new(0.25, 9.6, 0.15), if s < 0 then accentL else accentR, { Name = "PillarGlow" })
	end
	local canopy = Kit.block(kiosk, cf * CFrame.new(0, 11, 2.2), Vector3.new(16, 0.6, 7.6), M.Metal, Color3.fromRGB(52, 54, 62), { Name = "Canopy", CanCollide = false })
	Kit.glow(kiosk, cf * CFrame.new(-4, 10.62, -1.65), Vector3.new(8, 0.2, 0.2), accentL, { Name = "CanopyTrim" })
	Kit.glow(kiosk, cf * CFrame.new(4, 10.62, -1.65), Vector3.new(8, 0.2, 0.2), accentR, { Name = "CanopyTrim" })
	local title = Kit.deco(kiosk, cf * CFrame.new(0, 12.3, 0.4), Vector3.new(11, 2, 0.4), M.Metal, C.metalDark, { Name = "Title" })
	Kit.label(title, Enum.NormalId.Front, "FIGHTER KIOSK", { font = Enum.Font.GothamBlack, color = Color3.fromRGB(255, 226, 170), pps = 30, padding = 0.12, brightness = 1.5 })
	Kit.spot(canopy, Enum.NormalId.Bottom, Color3.fromRGB(255, 236, 210), 2.5, 18, 70, false)
	local console = Kit.block(kiosk, cf * CFrame.new(0, 2.1, -1.4), Vector3.new(2.6, 3.2, 1.6), M.Metal, Color3.fromRGB(56, 58, 66), { Name = "PromptPart" })
	local top = Kit.glow(kiosk, cf * CFrame.new(0, 3.82, -1.5) * CFrame.Angles(math.rad(-28), 0, 0), Vector3.new(2.3, 0.12, 1.4), Color3.fromRGB(110, 210, 255), { Name = "ConsoleScreen" })
	Kit.point(top, Color3.fromRGB(140, 210, 255), 1.2, 8, false)
	Kit.glow(kiosk, cf * CFrame.new(0, 1.2, -2.22), Vector3.new(2.2, 0.15, 0.06), C.ember, { Name = "ConsoleTrim" })
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ChooseFighter"
	prompt.ActionText = "Choose Fighter"
	prompt.ObjectText = "Fighters"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = console
	for i = 1, 6 do
		local x = (i - 3.5) * 2.1
		local col = if i <= 3 then accentL else accentR
		Kit.cylinder(kiosk, (cf * CFrame.new(x, 0.53, -2.7)).Position, 0.06, 1.4, M.Neon, col, { Name = "Badge", CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false, Transparency = 0.35 })
	end
end

local function buildLeaderboard(m: Model)
	local lb = Kit.model(m, "HallOfChampions")
	local cf = sideFrame(Lobby.HALL_BEARING)
	Kit.block(lb, cf * CFrame.new(0, 0.5, 0.8), Vector3.new(21, 1, 4.6), M.Granite, C.granite, { Name = "Base" })
	Kit.block(lb, cf * CFrame.new(0, 1.25, 0.8), Vector3.new(19.6, 0.5, 3.6), M.Marble, C.cream, { Name = "BaseStep" })
	for _, s in { -1, 1 } do
		Kit.block(lb, cf * CFrame.new(s * 9.4, 9.2, 0.8), Vector3.new(1.8, 15.4, 1.8), M.Limestone, C.stone, { Name = "Pillar" })
		Kit.block(lb, cf * CFrame.new(s * 9.4, 17.1, 0.8), Vector3.new(2.4, 0.5, 2.4), M.Metal, C.bronze, { Name = "PillarCap", CanCollide = false })
		Kit.block(lb, cf * CFrame.new(s * 9.4, 1.9, 0.8), Vector3.new(2.4, 0.8, 2.4), M.Metal, C.bronze, { Name = "PillarFoot" })
	end
	local board = Kit.block(lb, cf * CFrame.new(0, 9.4, 0.8), Vector3.new(16, 12, 0.5), M.SmoothPlastic, C.screen, { Name = "Leaderboard", CanCollide = false })
	-- keep the contract name directly under the Lobby model
	board.Parent = m
	local gui = Instance.new("SurfaceGui")
	gui.Name = "LeaderboardGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.ClipsDescendants = true
	gui.MaxDistance = 0
	gui.Parent = board
	Kit.stats.guis += 1
	Kit.deco(lb, cf * CFrame.new(0, 15.65, 0.9), Vector3.new(16.6, 0.3, 0.8), M.Metal, C.bronze)
	Kit.deco(lb, cf * CFrame.new(0, 3.15, 0.9), Vector3.new(16.6, 0.3, 0.8), M.Metal, C.bronze)
	local back = Kit.deco(lb, cf * CFrame.new(0, 9.4, 1.16), Vector3.new(16.6, 12.6, 0.22), M.Metal, Color3.fromRGB(52, 44, 38), { Name = "BackPanel" })
	Kit.label(back, Enum.NormalId.Back, "HALL OF\nCHAMPIONS", { font = Enum.Font.GothamBlack, color = Color3.fromRGB(214, 170, 96), pps = 24, padding = 0.18, light = 0.7, brightness = 1.2, name = "BackText", textSize = 44 })
	local header = Kit.deco(lb, cf * CFrame.new(0, 17.1, 0.8), Vector3.new(16.4, 2.4, 1), M.Metal, Color3.fromRGB(40, 34, 30), { Name = "Header" })
	Kit.label(header, Enum.NormalId.Front, "HALL OF CHAMPIONS", { font = Enum.Font.GothamBlack, color = Color3.fromRGB(255, 214, 140), pps = 30, padding = 0.12, brightness = 1.5 })
	local crest = Kit.glow(lb, cf * CFrame.new(0, 19.2, 0.8) * CFrame.Angles(0, 0, math.rad(45)), Vector3.new(1.6, 1.6, 0.6), C.ember, { Name = "Crest" })
	Kit.point(crest, C.ember, 1.2, 12, false)
	for _, s in { -1, 1 } do
		-- uplights wash the pillars (never the dark screen)
		local cup = Kit.deco(lb, cf * CFrame.new(s * 9.4, 1.6, -1.4) * CFrame.Angles(math.rad(100), 0, 0), Vector3.new(0.9, 0.9, 0.5), M.Metal, C.metalDark, { Name = "Uplight" })
		Kit.spot(cup, Enum.NormalId.Front, Color3.fromRGB(255, 226, 190), 1.4, 18, 20, false)
	end
end

-- Low greenery (round 7): credited fern and bush meshes (World.AssetKit), quiet decoration no taller than 1.5 studs, so
-- nothing new rises into a fight camera's view or stands in anyone's way.
local function greenery(parent: Instance, pos: Vector3, out: Vector3, rng: Random)
	local side = Vector3.new(-out.Z, 0, out.X)
	for _, s in { -1, 1 } do
		local p = pos + side * s * rng:NextNumber(1.3, 1.7) + out * rng:NextNumber(-0.2, 0.2)
		AssetKit.place(parent, "Fern", CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0), rng:NextNumber(0.36, 0.42))
	end
	AssetKit.place(parent, "Bush", CFrame.new(pos + out * 0.5) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0), rng:NextNumber(0.3, 0.34))
end

-- Street lamps on the plaza rim in the gaps between neighbouring stages (outside every fight camera's orbit), benches
-- round the beacon basin, and festoons from the beacon tower to the kiosk and the hall.
local function buildDressing(m: Model)
	local dress = Kit.model(m, "Dressing")
	local green = Kit.model(dress, "Greenery")
	local rng = Kit.rng(71)
	local byBearing = table.clone(Layout.ARENAS)
	table.sort(byBearing, function(a, b) return a.bearing < b.bearing end)
	for i = 1, #byBearing - 1 do
		local a, b = byBearing[i], byBearing[i + 1]
		if b.bearing - a.bearing <= Layout.ARENA_SPACING + 1 then
			local lampPos = polar((a.bearing + b.bearing) / 2, 32.5)
			Props.streetLamp(dress, lampPos, -lampPos.Unit, nil, 11)
			greenery(green, Vector3.new(lampPos.X, 0, lampPos.Z), lampPos.Unit, rng)
		end
	end
	-- benches on the beacon court, facing the fountain from the plaza side, with greenery between them
	local back = -Layout.bearingDir(Lobby.HEAD_BEARING)
	local function turned(deg: number): Vector3
		local r = math.rad(deg)
		return Vector3.new(back.X * math.cos(r) - back.Z * math.sin(r), 0, back.X * math.sin(r) + back.Z * math.cos(r))
	end
	for _, turn in { -62, 0, 62 } do
		local d = turned(turn)
		local pos = Lobby.BEACON_CENTRE + d * (Lobby.BEACON_BASIN_RADIUS + 3.6)
		Props.bench(dress, Kit.facing(pos, -d))
	end
	for _, turn in { -31, 31 } do
		local d = turned(turn)
		local pos = Lobby.BEACON_CENTRE + d * (Lobby.BEACON_BASIN_RADIUS + 2.4)
		greenery(green, Vector3.new(pos.X, 0, pos.Z), d, rng)
	end
	-- festoons from the beacon tower to the kiosk canopy and the hall's header
	local hub = Lobby.BEACON_CENTRE + Vector3.new(0, 18, 0)
	for _, target in { sideFrame(Lobby.KIOSK_BEARING) * CFrame.new(0, 11.4, 2.2), sideFrame(Lobby.HALL_BEARING) * CFrame.new(0, 16.4, 0.2) } do
		local p = target.Position
		local dir = Vector3.new(p.X - hub.X, 0, p.Z - hub.Z).Unit
		Props.stringLights(dress, hub + dir * 2.4, p, 10, Color3.fromRGB(255, 206, 130), 2.2, 5)
	end
end

function Lobby.build(parent: Instance?): Model
	local m = Kit.model(nil, "Lobby")
	buildPaving(m)
	buildBeacon(m)
	Kit.step()
	buildSpawns(m)
	buildFingerpost(m)
	buildKiosk(m)
	buildLeaderboard(m)
	Kit.step()
	buildDressing(m)
	if parent then
		m.Parent = parent
	end
	return m
end

return Lobby
