--!strict
-- Builds the FightingLab lobby world at server start: global lighting first (World.LightingSetup), then the island,
-- plaza, walkways and arenas (World.Builder), which finally creates ReplicatedStorage.FightingLab.WorldReady.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local World = ServerStorage:WaitForChild("FightingLab"):WaitForChild("World")

local okLighting, lightingError = pcall(function()
	require(World:WaitForChild("LightingSetup")).apply()
end)
if not okLighting then
	warn("[FightingLabWorld] lighting setup failed: " .. tostring(lightingError))
end

local ok, result = pcall(function()
	return require(World:WaitForChild("Builder")).build()
end)
if ok then
	print(string.format("[FightingLabWorld] built %d parts, %d lights, %d occluders in %.2f s", result.parts, result.lights, result.occluders, result.seconds))
else
	warn("[FightingLabWorld] build failed: " .. tostring(result))
	-- Never leave the game waiting forever: publish the flag with the error so systems can report it.
	local lab = ReplicatedStorage:WaitForChild("FightingLab")
	local ready = lab:FindFirstChild("WorldReady") or Instance.new("BoolValue")
	ready.Name = "WorldReady"
	ready:SetAttribute("BuildError", tostring(result))
	;(ready :: BoolValue).Value = true
	ready.Parent = lab
end
