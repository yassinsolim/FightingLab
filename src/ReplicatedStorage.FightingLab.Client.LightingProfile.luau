--!strict
-- Client lighting profile (OV5). The world owns global lighting: the server's World.LightingSetup sets the
-- golden-hour Lighting properties, Sky, Atmosphere and post effects (all tagged with the FightingLabWorldLighting
-- attribute) and fights share them. This module, applied once at client start by the bootstrap:
--   1. keeps the fighter key/fill/rim strengths that FighterLighting reads (data.fighterLighting);
--   2. removes stale client-side lighting left by older builds (never the world's own effects);
--   3. neutralises the legacy per-stage LightingPresets so loading a stage can never swap global lighting;
--   4. starts LobbyAmbience (client-only pad pulses, beacons, lanterns and positional ambience).
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local M = {}

M.WORLD_ATTRIBUTE = "FightingLabWorldLighting"

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

local function isWorldOwned(inst: Instance): boolean
	return inst:GetAttribute(M.WORLD_ATTRIBUTE) == true or string.sub(inst.Name, 1, 16) == "FightingLabWorld"
end

function M.clearStaleLighting(): number
	local removed = 0
	for _, child in Lighting:GetChildren() do
		local stale = child:IsA("PostEffect") or child:IsA("Atmosphere") or child:IsA("Sky")
		if stale and not isWorldOwned(child) then
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

return M
