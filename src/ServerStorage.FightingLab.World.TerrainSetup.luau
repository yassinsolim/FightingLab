--!strict
-- World.TerrainSetup: everything natural round the district. Sea everywhere (surface at WATER_Y), a rock foundation
-- under the district slab that stays at least 4 studs below it (nothing can show through the paving), snowy
-- mountains in the south-east behind the Summit, jungle hills in the south-west behind the Ruins, rocky hills to the
-- south, the harbour basin (east) and the bay (west) left as open water. No grass is ever placed under hardscape.
-- Smooth terrain draws a solid surface roughly at a fill's top; fills near the district are kept well below it.
local Layout = require(script.Parent.Layout)

local TerrainSetup = {}

local M = Enum.Material
local WATER = Layout.WATER_Y
local BOTTOM = -48

local function cylinder(T: Terrain, x: number, z: number, bottom: number, top: number, radius: number, material: Enum.Material)
	T:FillCylinder(CFrame.new(x, (bottom + top) / 2, z), top - bottom, radius, material)
end

-- A hill: a ball of `material` whose summit is at `top`; ground level material near its foot.
local function hill(T: Terrain, x: number, z: number, radius: number, top: number, material: Enum.Material)
	T:FillBall(Vector3.new(x, top - radius, z), radius, material)
end

TerrainSetup.MOUNTAINS = {
	-- x, z, radius, summit height: snowy peaks south-east and south, behind the Summit Observatory
	{ 95, 235, 95, 82 },
	{ 180, 180, 80, 60 },
	{ 20, 285, 105, 90 },
	{ 255, 255, 110, 74 },
}

TerrainSetup.HILLS = {
	-- x, z, radius, top, material: green foothills south and south-west (jungle behind the Ruins)
	{ -15, 178, 50, 12, M.LeafyGrass },
	{ 55, 170, 45, 12, M.Grass },
	{ -120, 168, 58, 16, M.LeafyGrass },
	{ -70, 222, 70, 32, M.LeafyGrass },
	{ -185, 118, 55, 12, M.LeafyGrass },
	{ -165, 245, 80, 40, M.LeafyGrass },
	{ 125, 128, 40, 8, M.Grass },
}

function TerrainSetup.build()
	local T = workspace.Terrain
	T:Clear()
	T.WaterColor = Color3.fromRGB(18, 76, 98)
	T.WaterTransparency = 0.45
	T.WaterReflectance = 0.6
	T.WaterWaveSize = 0.12
	T.WaterWaveSpeed = 8
	T:SetMaterialColor(M.Grass, Color3.fromRGB(98, 136, 62))
	T:SetMaterialColor(M.LeafyGrass, Color3.fromRGB(74, 118, 52))
	T:SetMaterialColor(M.Sand, Color3.fromRGB(222, 196, 146))
	T:SetMaterialColor(M.Rock, Color3.fromRGB(138, 128, 118))
	T:SetMaterialColor(M.Snow, Color3.fromRGB(238, 244, 252))
	T:SetMaterialColor(M.Mud, Color3.fromRGB(96, 78, 58))
	T:SetMaterialColor(M.Ground, Color3.fromRGB(108, 96, 78))
	T:SetMaterialColor(M.Slate, Color3.fromRGB(100, 104, 110))

	-- open sea over a sandy bed
	T:FillBlock(CFrame.new(0, (WATER + BOTTOM) / 2, 0), Vector3.new(2048, WATER - BOTTOM, 2048), M.Water)
	T:FillBlock(CFrame.new(0, BOTTOM - 4, 0), Vector3.new(2048, 8, 2048), M.Sand)

	-- shelf round the district and a rock foundation under the slab (tops far below the paving)
	cylinder(T, 0, 0, BOTTOM, -20, 190, M.Sand)
	cylinder(T, 0, 0, BOTTOM, -12, Layout.DISTRICT_RADIUS + 4, M.Rock)

	-- southern land: ground that meets the district edge two studs below the plaza, rising into hills
	cylinder(T, 0, 150, BOTTOM, -2, 120, M.Ground)
	cylinder(T, -90, 140, BOTTOM, -2, 80, M.LeafyGrass)
	cylinder(T, 90, 145, BOTTOM, -2, 70, M.Rock)
	for _, h in TerrainSetup.HILLS do
		hill(T, h[1] :: number, h[2] :: number, h[3] :: number, h[4] :: number, h[5] :: Enum.Material)
	end
	for _, mtn in TerrainSetup.MOUNTAINS do
		local x, z, r, top = mtn[1], mtn[2], mtn[3], mtn[4]
		hill(T, x, z, r, top, M.Rock)
		-- a broad snow cap over the upper slopes
		T:FillBall(Vector3.new(x, top - r * 0.62, z), r * 0.72, M.Snow)
	end
	-- jungle floor round the pyramid and a few mud patches
	cylinder(T, -70, 135, -12, -2, 34, M.LeafyGrass)
	cylinder(T, -40, 150, -12, -4.5, 8, M.Mud)
	cylinder(T, -105, 120, -12, -4.5, 7, M.Mud)

	-- keep the district's surroundings clear: carve air above the foundation inside the district circle, the canal
	-- between the district and the city quay, the harbour basin (east) and the bay (west)
	cylinder(T, 0, 0, -10, 40, Layout.DISTRICT_RADIUS + 1, M.Air)
	cylinder(T, 0, 0, -12, -10, Layout.DISTRICT_RADIUS + 1, M.Rock)
	T:FillBlock(CFrame.new(150, -10, -20), Vector3.new(120, 12, 150), M.Water)
	T:FillBlock(CFrame.new(-150, -10, -20), Vector3.new(120, 12, 150), M.Water)
	T:FillBlock(CFrame.new(150, 10, -20), Vector3.new(120, 28, 150), M.Air)
	T:FillBlock(CFrame.new(-150, 10, -20), Vector3.new(120, 28, 150), M.Air)
end

return TerrainSetup
