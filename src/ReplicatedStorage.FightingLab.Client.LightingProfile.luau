--!strict
-- Client lighting profile (OV6). The world owns the lobby's global lighting: the server's World.LightingSetup sets the
-- golden-hour Lighting properties, Sky, Atmosphere and post effects (all tagged with the FightingLabWorldLighting
-- attribute) and every lobby player shares them. This module, applied once at client start by the bootstrap:
--   1. keeps the fighter key/fill/rim strengths that FighterLighting reads (data.fighterLighting);
--   2. removes stale client-side lighting left by older builds (never the world's own effects);
--   3. neutralises the legacy per-stage LightingPresets so loading a stage can never swap global lighting;
--   4. starts LobbyAmbience (client-only pad pulses, beacons, lanterns and positional ambience).
--
-- Round 6 (look): every arena has its own mood for the players fighting there. StageController calls
-- applyArena(stageId) when the local fight starts and restore() when it ends: time of day, ambient, atmosphere, sky,
-- clouds, bloom, colour grade, sun rays, a subtle depth of field (focused on the fighters every frame through
-- setFocus) and the arena's fight light rig (key from the camera side, a coloured rim from behind, see rig below).
-- Only this client changes: lobby players and spectators keep the world's golden hour. Everything changed is
-- recorded first and put back exactly; objects created for a profile carry the FightingLabArenaLook attribute.
-- applyArena does nothing on the server (tests pass an explicit target to exercise it).
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local M = {}

M.WORLD_ATTRIBUTE = "FightingLabWorldLighting"
M.ARENA_ATTRIBUTE = "FightingLabArenaLook"

M.data = {
	fighterLighting = {
		suppressesLegacyStageControllerRootLights = true,
		fillRange = 6,
		rimBrightness = 0.3,
		rimRange = 9,
		darkBoost = 1,
		fillBrightness = 0.18,
		keyRange = 10,
		keyBrightness = 0.55,
	},
}

-- Global Lighting properties a stage preset used to override on load.
M.PRESET_KEYS = {
	"ClockTime", "Brightness", "Ambient", "OutdoorAmbient", "EnvironmentDiffuseScale", "EnvironmentSpecularScale",
	"ExposureCompensation", "GeographicLatitude", "ShadowSoftness", "FogColor", "FogStart", "FogEnd",
}

-- Lighting properties an arena profile may set (and restore() puts back).
M.LIGHTING_KEYS = {
	"ClockTime", "GeographicLatitude", "Brightness", "Ambient", "OutdoorAmbient", "EnvironmentDiffuseScale",
	"EnvironmentSpecularScale", "ExposureCompensation", "ShadowSoftness", "ColorShift_Top", "ColorShift_Bottom",
}

export type Rig = { keyColor: Color3, key: number, rimColor: Color3, rim: number, rimAngle: number? }
export type Profile = {
	name: string, -- mood name shown in docs/evidence
	lighting: { [string]: any },
	atmosphere: { [string]: any },
	sky: { [string]: any },
	clouds: { [string]: any },
	bloom: { [string]: any },
	grade: { [string]: any },
	sunRays: { [string]: any },
	dof: { FarIntensity: number, NearIntensity: number, InFocusRadius: number },
	rig: Rig,
}

local rgb = Color3.fromRGB

-- Readability ceilings for every arena profile (pinned by World_Test). Measured on the real fight camera with both
-- fighters masked (CPU fights, world.md round 6): fighter-pixel luma p95 188-221 (limit 235) and at most 0.5 %
-- near-white pixels in every arena.
M.CEILINGS = { exposure = 0.3, bloomIntensity = 0.9, bloomThresholdMin = 1.35, gradeBrightness = 0.04, gradeContrast = 0.16, sunRays = 0.06, glare = 0.4, dofFar = 0.3, rigKey = 2.4, rigRim = 4.5 }

M.PROFILES = {
	-- Neon midnight above the city: moonlit blue night, wet-looking deck, hot pink/cyan neon blooming.
	MidnightRooftop = {
		name = "Neon Midnight",
		lighting = {
			ClockTime = 0.6, GeographicLatitude = 30, Brightness = 1.6, Ambient = rgb(52, 50, 78), OutdoorAmbient = rgb(78, 72, 118),
			EnvironmentDiffuseScale = 0.45, EnvironmentSpecularScale = 1, ExposureCompensation = 0.15, ShadowSoftness = 0.35,
			ColorShift_Top = rgb(70, 90, 170), ColorShift_Bottom = rgb(40, 0, 50),
		},
		atmosphere = { Density = 0.36, Offset = 0.12, Color = rgb(70, 52, 118), Decay = rgb(28, 22, 70), Glare = 0, Haze = 1.4 },
		sky = { StarCount = 3000, MoonAngularSize = 12, SunAngularSize = 9, CelestialBodiesShown = true },
		clouds = { Cover = 0.5, Density = 0.4, Color = rgb(70, 62, 110) },
		bloom = { Intensity = 0.55, Size = 30, Threshold = 1.9 },
		grade = { Brightness = 0.02, Contrast = 0.14, Saturation = 0.16, TintColor = rgb(232, 230, 255) },
		sunRays = { Intensity = 0, Spread = 0.4 },
		dof = { FarIntensity = 0.22, NearIntensity = 0, InFocusRadius = 16 },
		rig = { keyColor = rgb(238, 226, 255), key = 0.95, rimColor = rgb(255, 70, 200), rim = 2.2, rimAngle = 55 },
	},
	-- Last light over the harbour: the sun sits on the water, long amber shadows, a violet sky behind the cranes.
	HarborDusk = {
		name = "Last Light",
		lighting = {
			ClockTime = 18.05, GeographicLatitude = 22, Brightness = 2.4, Ambient = rgb(92, 72, 84), OutdoorAmbient = rgb(140, 108, 120),
			EnvironmentDiffuseScale = 0.5, EnvironmentSpecularScale = 0.8, ExposureCompensation = 0, ShadowSoftness = 0.18,
			ColorShift_Top = rgb(255, 150, 70), ColorShift_Bottom = rgb(60, 20, 40),
		},
		atmosphere = { Density = 0.34, Offset = 0.18, Color = rgb(255, 168, 120), Decay = rgb(120, 70, 128), Glare = 0.3, Haze = 2.3 },
		sky = { StarCount = 600, MoonAngularSize = 8, SunAngularSize = 14, CelestialBodiesShown = true },
		clouds = { Cover = 0.55, Density = 0.6, Color = rgb(255, 196, 170) },
		bloom = { Intensity = 0.45, Size = 30, Threshold = 2 },
		grade = { Brightness = 0, Contrast = 0.1, Saturation = 0.2, TintColor = rgb(255, 234, 218) },
		sunRays = { Intensity = 0.03, Spread = 0.5 },
		dof = { FarIntensity = 0.18, NearIntensity = 0, InFocusRadius = 16 },
		rig = { keyColor = rgb(255, 214, 170), key = 0.9, rimColor = rgb(150, 120, 255), rim = 2.4, rimAngle = 50 },
	},
	-- Humid golden afternoon in the overgrowth: green haze, dappled sun, warm brazier light.
	JungleRuins = {
		name = "Canopy Haze",
		lighting = {
			ClockTime = 15.6, GeographicLatitude = 18, Brightness = 2.1, Ambient = rgb(70, 84, 62), OutdoorAmbient = rgb(98, 118, 86),
			EnvironmentDiffuseScale = 0.5, EnvironmentSpecularScale = 0.55, ExposureCompensation = -0.25, ShadowSoftness = 0.2,
			ColorShift_Top = rgb(200, 200, 120), ColorShift_Bottom = rgb(16, 32, 8),
		},
		atmosphere = { Density = 0.42, Offset = 0.02, Color = rgb(122, 144, 106), Decay = rgb(58, 80, 54), Glare = 0.1, Haze = 2.1 },
		sky = { StarCount = 0, MoonAngularSize = 8, SunAngularSize = 11, CelestialBodiesShown = true },
		clouds = { Cover = 0.62, Density = 0.55, Color = rgb(232, 240, 222) },
		bloom = { Intensity = 0.34, Size = 26, Threshold = 2.3 },
		grade = { Brightness = 0, Contrast = 0.12, Saturation = 0.12, TintColor = rgb(238, 255, 228) },
		sunRays = { Intensity = 0.04, Spread = 0.6 },
		dof = { FarIntensity = 0.2, NearIntensity = 0, InFocusRadius = 15 },
		rig = { keyColor = rgb(255, 236, 190), key = 0.8, rimColor = rgb(170, 255, 140), rim = 1.8, rimAngle = 50 },
	},
	-- Blue hour on the summit: the sun just under the peaks, stars still out, cold air and warm observatory windows.
	SnowSummit = {
		name = "Blue Hour",
		lighting = {
			ClockTime = 5.85, GeographicLatitude = 40, Brightness = 1.9, Ambient = rgb(88, 94, 116), OutdoorAmbient = rgb(118, 128, 160),
			EnvironmentDiffuseScale = 0.55, EnvironmentSpecularScale = 0.7, ExposureCompensation = 0.1, ShadowSoftness = 0.3,
			ColorShift_Top = rgb(150, 176, 232), ColorShift_Bottom = rgb(20, 20, 50),
		},
		atmosphere = { Density = 0.3, Offset = 0.15, Color = rgb(170, 190, 232), Decay = rgb(96, 104, 168), Glare = 0.1, Haze = 1.5 },
		sky = { StarCount = 2400, MoonAngularSize = 10, SunAngularSize = 10, CelestialBodiesShown = true },
		clouds = { Cover = 0.35, Density = 0.4, Color = rgb(196, 210, 240) },
		bloom = { Intensity = 0.5, Size = 28, Threshold = 1.8 },
		grade = { Brightness = 0, Contrast = 0.12, Saturation = -0.04, TintColor = rgb(236, 242, 255) },
		sunRays = { Intensity = 0, Spread = 0.4 },
		dof = { FarIntensity = 0.2, NearIntensity = 0, InFocusRadius = 16 },
		rig = { keyColor = rgb(255, 226, 196), key = 1.05, rimColor = rgb(180, 214, 255), rim = 1.5, rimAngle = 55 },
	},
	-- Morning calm in the dojo: low sun over the bay, paper-lantern warmth, soft shadows.
	TrainingBay = {
		name = "Morning Calm",
		lighting = {
			ClockTime = 8.6, GeographicLatitude = 34, Brightness = 2.5, Ambient = rgb(98, 90, 92), OutdoorAmbient = rgb(146, 136, 134),
			EnvironmentDiffuseScale = 0.55, EnvironmentSpecularScale = 0.6, ExposureCompensation = -0.05, ShadowSoftness = 0.25,
			ColorShift_Top = rgb(255, 210, 160), ColorShift_Bottom = rgb(30, 20, 20),
		},
		atmosphere = { Density = 0.3, Offset = 0.2, Color = rgb(236, 214, 196), Decay = rgb(150, 128, 146), Glare = 0.2, Haze = 1.5 },
		sky = { StarCount = 0, MoonAngularSize = 8, SunAngularSize = 11, CelestialBodiesShown = true },
		clouds = { Cover = 0.45, Density = 0.5, Color = rgb(255, 240, 230) },
		bloom = { Intensity = 0.35, Size = 26, Threshold = 2.2 },
		grade = { Brightness = 0, Contrast = 0.07, Saturation = 0.06, TintColor = rgb(255, 246, 236) },
		sunRays = { Intensity = 0.03, Spread = 0.5 },
		dof = { FarIntensity = 0.16, NearIntensity = 0, InFocusRadius = 16 },
		rig = { keyColor = rgb(255, 236, 214), key = 0.7, rimColor = rgb(255, 196, 120), rim = 1.8, rimAngle = 50 },
	},
} :: { [string]: Profile }

local function isWorldOwned(inst: Instance): boolean
	return inst:GetAttribute(M.WORLD_ATTRIBUTE) == true or string.sub(inst.Name, 1, 16) == "FightingLabWorld"
end

function M.clearStaleLighting(): number
	local removed = 0
	for _, child in Lighting:GetChildren() do
		local stale = child:IsA("PostEffect") or child:IsA("Atmosphere") or child:IsA("Sky")
		if stale and not isWorldOwned(child) and child:GetAttribute(M.ARENA_ATTRIBUTE) == nil then
			child:Destroy()
			removed += 1
		end
	end
	return removed
end

function M.neutraliseStagePresets(): number
	local lab = ReplicatedStorage:FindFirstChild("FightingLab")
	local stages = lab and lab:FindFirstChild("Stages")
	if not stages then
		return 0
	end
	local cleared = 0
	for _, stage in stages:GetChildren() do
		local preset = stage:FindFirstChild("LightingPreset")
		if preset then
			for _, key in M.PRESET_KEYS do
				if preset:GetAttribute(key) ~= nil then
					preset:SetAttribute(key, nil)
					cleared += 1
				end
			end
			for _, child in preset:GetChildren() do
				child:Destroy()
				cleared += 1
			end
		end
	end
	return cleared
end

function M.apply()
	M.clearStaleLighting()
	M.neutraliseStagePresets()
	local ambience = script.Parent:FindFirstChild("LobbyAmbience")
	if ambience and ambience:IsA("ModuleScript") then
		task.spawn(function()
			local ok, err = pcall(function()
				require(ambience :: ModuleScript).start()
			end)
			if not ok then
				warn("FightingLab LobbyAmbience failed to start: " .. tostring(err))
			end
		end)
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Arena moods (round 6)
--------------------------------------------------------------------------------------------------------------------
function M.profileFor(stageId: any): Profile?
	if typeof(stageId) ~= "string" then return nil end
	return M.PROFILES[stageId]
end

type Saved = { target: Instance, terrain: Instance?, props: { [Instance]: { [string]: any } }, created: { Instance }, stageId: string }
local saved: Saved? = nil
local depth: DepthOfFieldEffect? = nil

-- The effect of a class the world (or this profile) uses; nil when there is none.
local function effectOf(target: Instance, className: string, preferred: string): Instance?
	local named = target:FindFirstChild(preferred)
	if named and named:IsA(className) then return named end
	for _, child in target:GetChildren() do
		if child:IsA(className) and child:GetAttribute(M.ARENA_ATTRIBUTE) == nil then return child end
	end
	return nil
end

local function remember(s: Saved, inst: Instance, props: { [string]: any })
	local record = s.props[inst]
	if not record then
		record = {}
		s.props[inst] = record
	end
	for key in props do
		if record[key] == nil then record[key] = (inst :: any)[key] end
	end
end

local function set(s: Saved, inst: Instance, props: { [string]: any })
	remember(s, inst, props)
	for key, value in props do (inst :: any)[key] = value end
end

-- An effect for the profile: the world's own (recorded and changed) or a new one this client removes on restore.
local function ensure(s: Saved, parent: Instance, className: string, preferred: string, props: { [string]: any }): Instance
	local inst = effectOf(parent, className, preferred)
	if inst then
		set(s, inst, props)
		return inst
	end
	local created = Instance.new(className)
	created.Name = "FightingLabArena" .. className
	created:SetAttribute(M.ARENA_ATTRIBUTE, true)
	for key, value in props do (created :: any)[key] = value end
	created.Parent = parent
	table.insert(s.created, created)
	return created
end

-- Applies an arena's mood to this client. `target` (tests) replaces game.Lighting and skips the client check;
-- returns whether a profile was applied. A second call first restores the previous arena.
function M.applyArena(stageId: any, target: Instance?): boolean
	if target == nil and not RunService:IsClient() then return false end
	local profile = M.profileFor(stageId)
	if saved then M.restore() end
	if not profile then return false end
	local lighting = target or Lighting
	local s: Saved = { target = lighting, terrain = nil, props = {}, created = {}, stageId = stageId :: string }
	saved = s
	set(s, lighting, profile.lighting)
	ensure(s, lighting, "Atmosphere", "FightingLabWorldAtmosphere", profile.atmosphere)
	ensure(s, lighting, "Sky", "FightingLabWorldSky", profile.sky)
	ensure(s, lighting, "BloomEffect", "FightingLabWorldBloom", profile.bloom)
	ensure(s, lighting, "ColorCorrectionEffect", "FightingLabWorldGrade", profile.grade)
	ensure(s, lighting, "SunRaysEffect", "FightingLabWorldSunRays", profile.sunRays)
	local dof = Instance.new("DepthOfFieldEffect")
	dof.Name = "FightingLabArenaDepth"
	dof:SetAttribute(M.ARENA_ATTRIBUTE, true)
	dof.FarIntensity = profile.dof.FarIntensity
	dof.NearIntensity = profile.dof.NearIntensity
	dof.InFocusRadius = profile.dof.InFocusRadius
	dof.FocusDistance = 14
	dof.Parent = lighting
	table.insert(s.created, dof)
	depth = dof
	if target == nil then
		local terrain = workspace:FindFirstChildOfClass("Terrain")
		local clouds = terrain and terrain:FindFirstChildOfClass("Clouds")
		if clouds then
			s.terrain = terrain
			set(s, clouds, profile.clouds)
		end
	end
	return true
end

-- Puts back everything applyArena changed (exact recorded values) and removes what it created.
function M.restore(): boolean
	local s = saved
	if not s then return false end
	saved = nil
	depth = nil
	for inst, props in s.props do
		if inst.Parent ~= nil or inst == s.target then
			for key, value in props do
				pcall(function() (inst :: any)[key] = value end)
			end
		end
	end
	for _, inst in s.created do inst:Destroy() end
	return true
end

function M.activeArena(): string?
	return if saved then saved.stageId else nil
end

-- Keeps the depth of field focused on the fighters (camera-to-focus distance in studs).
function M.setFocus(distance: number)
	local d = depth
	if d and d.Parent and distance == distance then d.FocusDistance = math.clamp(distance, 4, 80) end
end

-- The arena's fight light rig (StageController places it every frame); nil outside an arena mood.
function M.rigFor(stageId: any): Rig?
	local profile = M.profileFor(stageId)
	return if profile then profile.rig else nil
end

return M
