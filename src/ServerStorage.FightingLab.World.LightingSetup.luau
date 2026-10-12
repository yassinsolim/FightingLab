--!strict
-- World.LightingSetup: global lighting for the lobby world (golden hour / bright dusk), applied by the server at
-- start and replicated to every client. Fights share it (contract section 3); clients may only make small, restored
-- local tweaks. Everything created here is named FightingLabWorld* and carries the FightingLabWorldLighting attribute
-- so client code can recognise (and keep) it.
--
-- Exposure (OV6 round 2): fights are framed by a close fight camera with the fighters' own key/fill/rim lights on
-- top of this sun, so the global exposure is set for the fighters, not for the lobby: exposure -0.1, bloom only on
-- true highlights (threshold 2.5: neon, lamps, the sun), a neutral grade (no added brightness) and only a trace of
-- sun rays. Measured on the fight camera for every arena at four fight-line orientations plus straight into the
-- sun, centre and edge, with the palest (Sierra) and darkest (Nia, Goran) fighters: fighter p95 luma <= 235 and
-- < 0.5 % near-white pixels. The sun keeps its low warm angle and the haze its golden-hour depth.
local Lighting = game:GetService("Lighting")

local LightingSetup = {}

LightingSetup.ATTRIBUTE = "FightingLabWorldLighting"

LightingSetup.properties = {
	ClockTime = 17.4,
	GeographicLatitude = 62,
	Brightness = 3.4,
	Ambient = Color3.fromRGB(100, 90, 96),
	OutdoorAmbient = Color3.fromRGB(150, 136, 132),
	EnvironmentDiffuseScale = 0.55,
	EnvironmentSpecularScale = 0.7,
	ExposureCompensation = -0.1,
	ShadowSoftness = 0.22,
	GlobalShadows = true,
	ColorShift_Top = Color3.fromRGB(90, 52, 14),
	ColorShift_Bottom = Color3.fromRGB(0, 0, 0),
	FogColor = Color3.fromRGB(214, 180, 150),
	FogStart = 0,
	FogEnd = 100000,
}

LightingSetup.atmosphere = {
	Density = 0.3,
	Offset = 0.2,
	Color = Color3.fromRGB(240, 192, 156),
	Decay = Color3.fromRGB(128, 104, 146),
	Glare = 0.25,
	Haze = 1.9,
}

-- A smaller sun disk with less glare and only a trace of sun rays: when a fight camera looks into the low sun the
-- rays drew a flat orange veil over the whole frame (fighters lost contrast); the warm light itself is unchanged.
LightingSetup.sky = {
	SunAngularSize = 9,
	MoonAngularSize = 9,
	StarCount = 1500,
	CelestialBodiesShown = true,
}

LightingSetup.bloom = { Intensity = 0.35, Size = 28, Threshold = 2.5 }
LightingSetup.grade = { Brightness = 0, Contrast = 0.04, Saturation = 0.12, TintColor = Color3.fromRGB(255, 240, 228) }
LightingSetup.sunRays = { Intensity = 0.02, Spread = 0.55 }
LightingSetup.clouds = { Cover = 0.42, Density = 0.55, Color = Color3.fromRGB(255, 236, 222) }

local function make(className: string, name: string, props: { [string]: any }): Instance
	local inst = Instance.new(className)
	inst.Name = name
	for k, v in props do
		(inst :: any)[k] = v
	end
	inst:SetAttribute(LightingSetup.ATTRIBUTE, true)
	inst.Parent = Lighting
	return inst
end

function LightingSetup.apply()
	for k, v in LightingSetup.properties do
		(Lighting :: any)[k] = v
	end
	-- One Sky / Atmosphere may exist at a time, and stale post effects saved with the place would stack with ours.
	for _, child in Lighting:GetChildren() do
		if child:IsA("Sky") or child:IsA("Atmosphere") or child:IsA("PostEffect") or child:IsA("Clouds") then
			child:Destroy()
		end
	end
	make("Sky", "FightingLabWorldSky", LightingSetup.sky)
	make("Atmosphere", "FightingLabWorldAtmosphere", LightingSetup.atmosphere)
	make("BloomEffect", "FightingLabWorldBloom", LightingSetup.bloom)
	make("ColorCorrectionEffect", "FightingLabWorldGrade", LightingSetup.grade)
	make("SunRaysEffect", "FightingLabWorldSunRays", LightingSetup.sunRays)
	-- soft golden-hour clouds (they live under Terrain; replace any older ones)
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if terrain then
		local old = terrain:FindFirstChildOfClass("Clouds")
		if old then
			old:Destroy()
		end
		local clouds = Instance.new("Clouds")
		clouds.Name = "FightingLabWorldClouds"
		for k, v in LightingSetup.clouds do
			(clouds :: any)[k] = v
		end
		clouds:SetAttribute(LightingSetup.ATTRIBUTE, true)
		clouds.Parent = terrain
	end
	Lighting:SetAttribute("FightingLabWorldLightingApplied", true)
end

return LightingSetup
