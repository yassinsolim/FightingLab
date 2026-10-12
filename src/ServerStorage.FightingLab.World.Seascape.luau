--!strict
-- World.Seascape: the world round the district. The container port on the city quay (north-east, seen behind the
-- Harbor fights), the lighthouse on its rock (east), forests on the southern slopes (snowy pines below the peaks
-- behind the Summit, jungle trees round the Ruins), and palm islets and sailboats on the horizon.
local Kit = require(script.Parent.Kit)
local Props = require(script.Parent.Props)
local Layout = require(script.Parent.Layout)

local Seascape = {}

local M = Enum.Material
local CITY_Y = -1.8 -- top of the city street slab (MidnightRooftop.skyline)

local ISLETS = {
	{ 330, 30, 36 },
	{ 270, 230, 30 },
	{ -310, -20, 40 },
	{ -270, 190, 30 },
	{ -330, -210, 34 },
}

local BOATS = {
	{ 230, -60, 30, Color3.fromRGB(240, 236, 226) },
	{ 300, 140, 80, Color3.fromRGB(230, 90, 70) },
	{ -230, 70, 200, Color3.fromRGB(240, 236, 226) },
	{ -220, -150, 300, Color3.fromRGB(70, 150, 210) },
}

local function sailboat(parent: Instance, cf: CFrame, sail: Color3)
	local b = Kit.model(parent, "Sailboat")
	local base = cf * CFrame.new(0, Layout.WATER_Y + 0.6, 0)
	Kit.block(b, base, Vector3.new(4.2, 2.2, 14), M.WoodPlanks, Color3.fromRGB(236, 232, 222), { Name = "Hull", CanCollide = false })
	Kit.wedge(b, base * CFrame.new(0, 0, -9.5), Vector3.new(4.2, 2.2, 5), M.WoodPlanks, Color3.fromRGB(236, 232, 222), { Name = "Bow", CanCollide = false })
	Kit.block(b, base * CFrame.new(0, 1.9, 3), Vector3.new(3, 1.4, 4), M.WoodPlanks, Color3.fromRGB(150, 116, 84), { Name = "Cabin", CanCollide = false })
	Kit.block(b, base * CFrame.new(0, 10, -1.5), Vector3.new(0.4, 17, 0.4), M.Wood, Color3.fromRGB(120, 92, 66), { Name = "Mast", CanCollide = false })
	Kit.wedge(b, base * CFrame.new(0, 10, 2.1) * CFrame.Angles(0, math.pi, 0), Vector3.new(0.08, 15, 6.6), M.Fabric, sail, { Name = "Sail", CanCollide = false })
	Kit.wedge(b, base * CFrame.new(0, 7.5, -5.2), Vector3.new(0.08, 10, 6.6), M.Fabric, Color3.fromRGB(246, 242, 232), { Name = "Jib", CanCollide = false })
	return b
end

-- Terrain height (and material) under a point, or nil over water.
local function ground(x: number, z: number): number?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	params.IgnoreWater = false
	local hit = workspace:Raycast(Vector3.new(x, 220, z), Vector3.new(0, -300, 0), params)
	if not hit or hit.Material == M.Water then
		return nil
	end
	return hit.Position.Y
end

local function port(m: Model, rng: Random)
	local p = Kit.model(m, "Port")
	for _, x in { 100, 140 } do
		Props.crane(p, Vector3.new(x, CITY_Y, -96), Vector3.new(0, 0, 1), rng)
	end
	local stacks = { 80, 102, 124, 146, 168 }
	for row, z in { -112, -122 } do
		for i, x in stacks do
			local levels = rng:NextInteger(1, 3)
			for level = 1, levels do
				local color = Props.CONTAINER_COLORS[(i * 3 + level + row) % #Props.CONTAINER_COLORS + 1]
				local yaw = if (i + level) % 4 == 0 then math.rad(rng:NextNumber(-3, 3)) else 0
				Props.container(p, CFrame.new(x, CITY_Y + (level - 1) * 8.6, z) * CFrame.Angles(0, yaw, 0), color, rng, row == 1)
			end
		end
		Kit.step()
	end
	for x = 60, 176, 14 do
		Props.bollard(p, Vector3.new(x, CITY_Y, -91.2))
	end
	-- quay edge coping and two sodium floodlight masts over the yard
	Kit.block(p, CFrame.new(118, CITY_Y + 0.15, -90.6), Vector3.new(124, 0.3, 1.2), M.Concrete, Color3.fromRGB(240, 186, 52), { Name = "QuayEdge" })
	for _, x in { 90, 152 } do
		local base = Vector3.new(x, CITY_Y, -104)
		Kit.cylinder(p, base + Vector3.new(0, 9, 0), 18, 0.6, M.Metal, Color3.fromRGB(80, 84, 92), { CanCollide = false })
		local head = Kit.deco(p, CFrame.lookAt(base + Vector3.new(0, 18.4, 0), base + Vector3.new(0, 0, 30)), Vector3.new(2.6, 1, 1.2), M.Metal, Color3.fromRGB(40, 42, 48), { Name = "FloodHead" })
		Kit.glow(p, head.CFrame * CFrame.new(0, 0, -0.62), Vector3.new(2.2, 0.7, 0.05), Color3.fromRGB(255, 190, 110))
		Kit.spot(head, Enum.NormalId.Front, Color3.fromRGB(255, 176, 96), 1.4, 50, 70, false)
	end
	-- freight shed with its name facing the harbour
	local shed = Kit.block(p, CFrame.new(150, CITY_Y + 7, -146), Vector3.new(40, 14, 22), M.CorrodedMetal, Color3.fromRGB(120, 130, 136), { Name = "Shed", CanCollide = false })
	local _ = shed
	Kit.wedge(p, CFrame.new(150, CITY_Y + 16, -140.5) * CFrame.Angles(0, math.pi, 0), Vector3.new(41, 4, 11), M.Metal, Color3.fromRGB(150, 70, 56), { Name = "Roof", CanCollide = false })
	Kit.wedge(p, CFrame.new(150, CITY_Y + 16, -151.5), Vector3.new(41, 4, 11), M.Metal, Color3.fromRGB(150, 70, 56), { Name = "Roof", CanCollide = false })
	local sign = Kit.deco(p, CFrame.new(150, CITY_Y + 11, -134.8), Vector3.new(24, 3.4, 0.4), M.Metal, Color3.fromRGB(240, 236, 226), { Name = "ShedSign" })
	Kit.label(sign, Enum.NormalId.Back, "PIER 9 FREIGHT", { font = Enum.Font.Oswald, color = Color3.fromRGB(40, 60, 90), pps = 30, padding = 0.08, light = 1 })
end

local function lighthouse(m: Model, rng: Random)
	local lh = Kit.model(m, "Lighthouse")
	local base = Vector3.new(152, -5, 68)
	Kit.keepOut(base, 16)
	Props.rock(lh, base + Vector3.new(0, -1, 0), Vector3.new(30, 14, 26), rng, Color3.fromRGB(110, 104, 98))
	Props.rock(lh, base + Vector3.new(10, -2, 8), Vector3.new(14, 8, 12), rng, Color3.fromRGB(96, 92, 88))
	for i = 0, 6 do
		Kit.cylinder(lh, base + Vector3.new(0, 5 + i * 5, 0), 5, 7.4 - i * 0.5, M.Concrete, if i % 2 == 0 then Color3.fromRGB(236, 232, 224) else Color3.fromRGB(196, 54, 44), { Name = "Tower" })
	end
	Kit.cylinder(lh, base + Vector3.new(0, 38, 0), 0.6, 7.6, M.Metal, Color3.fromRGB(40, 40, 46))
	local lampRoom = Kit.cylinder(lh, base + Vector3.new(0, 40.2, 0), 3.8, 4.2, M.Glass, Color3.fromRGB(255, 240, 200), { Name = "LampRoom", Transparency = 0.3 })
	Kit.glow(lh, CFrame.new(base + Vector3.new(0, 40.2, 0)), Vector3.new(1.8, 1.8, 1.8), Color3.fromRGB(255, 236, 180))
	Kit.point(lampRoom, Color3.fromRGB(255, 236, 180), 3, 40, false)
	Kit.cylinder(lh, base + Vector3.new(0, 42.6, 0), 1.2, 5, M.Metal, Color3.fromRGB(196, 54, 44))
	local beam = Kit.deco(lh, CFrame.new(base + Vector3.new(0, 40.2, 0)), Vector3.new(60, 1.4, 1.4), M.Neon, Color3.fromRGB(255, 240, 200), { Name = "LightBeam", Transparency = 0.84 })
	beam:SetAttribute("SpinSpeed", 0.6)
	Kit.tag(beam, Kit.TAG_SPIN)
end

-- A forest tree only grows where nothing else stands (stages, boards, landmarks, the district edge, other trees).
local function freeSpot(x: number, z: number, radius: number): boolean
	local p = Vector3.new(x, 0, z)
	if not Kit.clearSpot(p, radius) then
		return false
	end
	Kit.keepOut(p, radius)
	return true
end

local function forests(m: Model, rng: Random)
	local f = Kit.model(m, "Forests")
	-- snowy pines below the peaks (south-east); spots taken by landmarks are skipped, so try plenty
	for i = 1, 26 do
		local b = math.rad(rng:NextNumber(122, 172))
		local r = rng:NextNumber(112, 165)
		local x, z = math.sin(b) * r, -math.cos(b) * r
		local y = ground(x, z)
		if y and y < 30 and freeSpot(x, z, 2) then
			Props.pine(f, Vector3.new(x, y, z), rng:NextNumber(1.3, 2), rng, y > 6)
		end
		if i % 4 == 0 then Kit.step() end
	end
	-- jungle canopy round the ruins (south-west)
	local leaf = { Color3.fromRGB(56, 104, 48), Color3.fromRGB(72, 120, 54), Color3.fromRGB(46, 88, 42) }
	for i = 1, 32 do
		local b = math.rad(rng:NextNumber(192, 246))
		local r = rng:NextNumber(108, 170)
		local x, z = math.sin(b) * r, -math.cos(b) * r
		local y = ground(x, z)
		if y and y < 34 and freeSpot(x, z, 3) then
			if i % 4 == 0 then
				Props.palm(f, Vector3.new(x, y, z), rng:NextNumber(1.3, 1.7), rng)
			else
				Props.tree(f, Vector3.new(x, y, z), rng:NextNumber(1.8, 2.6), rng, leaf)
			end
		end
		if i % 4 == 0 then Kit.step() end
	end
	-- a few trees on the southern hills between them
	for _ = 1, 10 do
		local b = math.rad(rng:NextNumber(170, 192))
		local r = rng:NextNumber(118, 160)
		local x, z = math.sin(b) * r, -math.cos(b) * r
		local y = ground(x, z)
		if y and y < 30 and freeSpot(x, z, 2) then
			Props.pine(f, Vector3.new(x, y, z), rng:NextNumber(1.2, 1.7), rng, false)
		end
	end
end

local function islets(m: Model, rng: Random)
	local T = workspace.Terrain
	for _, isl in ISLETS do
		local x, z, r = isl[1], isl[2], isl[3]
		T:FillBall(Vector3.new(x, -4 - r * 0.85, z), r, M.Sand)
		T:FillBall(Vector3.new(x, -4 - r * 0.42, z), r * 0.6, M.Grass)
		T:FillBall(Vector3.new(x + r * 0.25, -4 + r * 0.05, z - r * 0.1), r * 0.3, M.Rock)
		for _ = 1, 4 do
			local a = rng:NextNumber(0, math.pi * 2)
			local d = rng:NextNumber(0, r * 0.28)
			local px, pz = x - r * 0.1 + math.cos(a) * d, z + math.sin(a) * d
			local y = ground(px, pz)
			if y and freeSpot(px, pz, 1.5) then
				Props.palm(m, Vector3.new(px, y, pz), rng:NextNumber(1.2, 1.6), rng)
			end
		end
		Kit.step()
	end
	for _, bt in BOATS do
		sailboat(m, CFrame.new(bt[1], 0, bt[2]) * CFrame.Angles(0, math.rad(bt[3]), 0), bt[4])
	end
end

function Seascape.build(parent: Instance?): Model
	local m = Kit.model(nil, "Seascape")
	local rng = Kit.rng(21)
	port(m, rng)
	lighthouse(m, rng)
	forests(m, rng)
	islets(m, rng)
	if parent then
		m.Parent = parent
	end
	return m
end

return Seascape
