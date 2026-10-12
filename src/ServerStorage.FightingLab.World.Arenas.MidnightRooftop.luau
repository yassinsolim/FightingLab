--!strict
-- Arena: Midnight Rooftop (north). The fight stage is the roof of a round podium building at the head of the plaza:
-- dark asphalt deck with a pink neon edge line and a cyan neon light-rail on slim posts, reached by a grand stair.
-- Behind it the city rises: lit towers, neon signs and the Orbit Tower with the arena's big status screen.
local Kit = require(script.Parent.Parent.Kit)
local Props = require(script.Parent.Parent.Props)
local ArenaKit = require(script.Parent.Parent.ArenaKit)
local Layout = require(script.Parent.Parent.Layout)

local Arena = {}

local M = Enum.Material

local C = {
	podium = Color3.fromRGB(58, 64, 82),
	podiumTrim = Color3.fromRGB(34, 36, 46),
	apron = Color3.fromRGB(70, 74, 88),
	band = Color3.fromRGB(38, 40, 50),
	floor = Color3.fromRGB(52, 56, 72),
	stair = Color3.fromRGB(116, 120, 132),
	parapet = Color3.fromRGB(84, 88, 104),
	metal = Color3.fromRGB(120, 126, 136),
	metalDark = Color3.fromRGB(30, 32, 40),
	pink = Color3.fromRGB(255, 72, 196),
	cyan = Color3.fromRGB(60, 220, 255),
	violet = Color3.fromRGB(150, 90, 255),
	amber = Color3.fromRGB(255, 186, 90),
	warm = Color3.fromRGB(255, 206, 150),
	street = Color3.fromRGB(58, 60, 66),
}

local function facade(parent: Instance, def: Layout.ArenaDef)
	-- ribbon of shop windows round the podium (flat panels on the curve), skipping the stair opening
	local f = Kit.model(parent, "Facade")
	local R = Layout.STAGE_RADIUS + 0.02
	local rng = Kit.rng(41)
	for a = 28, 332, 11 do
		local d = Layout.around(def, a)
		local p = def.origin + d * R
		local cf = CFrame.lookAt(Vector3.new(p.X, 2.9, p.Z), Vector3.new(p.X, 2.9, p.Z) + d)
		local lit = rng:NextNumber() < 0.55
		if lit then
			Kit.glow(f, cf, Vector3.new(5.6, 2.6, 0.1), Kit.mix(C.warm, C.cyan, rng:NextNumber() * 0.3), { Name = "ShopGlow", Transparency = 0.45 })
		else
			Kit.deco(f, cf, Vector3.new(5.6, 2.6, 0.1), M.Glass, Color3.fromRGB(60, 84, 112), { Name = "ShopGlass", Reflectance = 0.2 })
		end
		Kit.deco(f, cf * CFrame.new(0, 1.55, 0.05), Vector3.new(6.1, 0.35, 0.3), M.Metal, C.podiumTrim, { Name = "Lintel" })
		Kit.glow(f, CFrame.lookAt(Vector3.new(p.X, 5.35, p.Z), Vector3.new(p.X, 5.35, p.Z) + d) * CFrame.new(0, 0, 0.05), Vector3.new(6.1, 0.14, 0.12), if a % 22 < 11 then C.pink else C.cyan, { Name = "FacadeNeon" })
	end
	-- the arena name in neon either side of the stair (the rooftop's entrance signage)
	local gate = Kit.model(parent, "Gate_" .. def.stageId)
	for _, s in { { -37, "MIDNIGHT", C.pink }, { 37, "ROOFTOP", C.cyan } } do
		local d = Layout.around(def, s[1] :: number)
		local p = def.origin + d * (R + 0.45)
		Props.neonSign(gate, CFrame.lookAt(Vector3.new(p.X, 3.0, p.Z), Vector3.new(p.X, 3.0, p.Z) + d), 14, 3.2, s[2] :: string, s[3] :: Color3, Enum.Font.Sarpanch, false)
	end
end

local function rooftopKit(parent: Instance, def: Layout.ArenaDef)
	local kit = Kit.model(parent, "RoofKit")
	local base = def.floorY - Layout.APRON_DROP
	-- air-handling units on the back corners of the apron (outside the barrier)
	for _, a in { 142, -142 } do
		local d = Layout.around(def, a)
		local p = def.origin + d * 27.6
		local cf = CFrame.lookAt(Vector3.new(p.X, base, p.Z), Vector3.new(p.X, base, p.Z) + d)
		Kit.block(kit, cf * CFrame.new(0, 1.2, 0), Vector3.new(5.2, 2.4, 3.2), M.Metal, C.metal, { Name = "HVAC" })
		for _, fx in { -1.3, 1.3 } do
			Kit.cylinder(kit, (cf * CFrame.new(fx, 2.45, 0)).Position, 0.12, 2.2, M.Metal, C.metalDark, { Name = "Fan", CanCollide = false })
		end
		local vent = Kit.deco(kit, cf * CFrame.new(-2, 3.0, 0.9), Vector3.new(0.6, 1.2, 0.6), M.Metal, C.metalDark, { Name = "Vent" })
		Kit.emitter(vent, {
			Name = "Steam",
			Color = Kit.colors(Color3.fromRGB(220, 220, 230)),
			LightInfluence = 1,
			Size = Kit.numbers(0.6, 2.4),
			Transparency = Kit.numbers(0.6, 1),
			Lifetime = NumberRange.new(2, 3.5),
			Rate = 4,
			Speed = NumberRange.new(1.5, 3),
			SpreadAngle = Vector2.new(10, 10),
			Acceleration = Vector3.new(1.2, 0.4, 0),
			EmissionDirection = Enum.NormalId.Top,
			Texture = "rbxasset://textures/particles/smoke_main.dds",
		})
	end
	-- low cable trays and skylights between them (under 1.5 studs)
	for _, a in { 168, -168 } do
		local d = Layout.around(def, a)
		local p = def.origin + d * 27.5
		local cf = CFrame.lookAt(Vector3.new(p.X, base, p.Z), Vector3.new(p.X, base, p.Z) + d)
		Kit.block(kit, cf * CFrame.new(0, 0.5, 0), Vector3.new(4.4, 1, 3), M.Metal, C.metalDark, { Name = "SkylightFrame" })
		Kit.deco(kit, cf * CFrame.new(0, 1.03, 0), Vector3.new(3.8, 0.06, 2.4), M.Glass, Color3.fromRGB(255, 220, 170), { Name = "Skylight", Transparency = 0.25 })
	end
	-- satellite dishes on the sides
	for _, a in { 100, -100 } do
		local d = Layout.around(def, a)
		local p = def.origin + d * 29
		local foot = Vector3.new(p.X, base, p.Z)
		Kit.cylinder(kit, foot + Vector3.new(0, 1.2, 0), 2.4, 0.4, M.Metal, C.metalDark, { CanCollide = false })
		Kit.cylinder(kit, CFrame.lookAt(foot + Vector3.new(0, 2.8, 0), foot + Vector3.new(0, 4.5, 0) + d * 2) * CFrame.Angles(math.rad(-90), 0, 0), 0.3, 3.4, M.Metal, Color3.fromRGB(220, 222, 228), { Name = "Dish", CanCollide = false })
	end
end

local function skyline(model: Model, def: Layout.ArenaDef)
	local sky = Kit.model(model, "Skyline")
	local rng = Kit.rng(1)
	local groundY = -1.8
	-- city streets north of the district (a hair below the plaza edge)
	Kit.block(sky, CFrame.new(0, groundY - 1, -205), Vector3.new(360, 2, 230), M.Asphalt, C.street, { Name = "Streets" })
	for _, lx in { -62, 62 } do
		Kit.deco(sky, CFrame.new(lx, groundY + 0.03, -205), Vector3.new(0.5, 0.06, 220), M.SmoothPlastic, Color3.fromRGB(230, 200, 90), { Name = "LaneLine" })
	end
	-- Orbit Tower carries the arena's status screen on its south face
	local orbit = Props.tower(sky, Vector3.new(0, groundY, -131), 34, 16, 74, rng, {
		material = M.Concrete, color = Color3.fromRGB(62, 68, 88), neon = C.violet, lit = 0.28,
		faces = { Enum.NormalId.Left, Enum.NormalId.Right, Enum.NormalId.Back }, crown = false, mast = true,
	})
	orbit.Name = "OrbitTower"
	Props.neonSign(orbit, CFrame.new(0, groundY + 66, -122.6), 22, 4.2, "HOTEL ORBIT", C.violet)
	-- the rest of the skyline: { x, z, width, depth, height, neon }
	local towers = {
		{ -46, -128, 22, 20, 58, C.pink }, { 46, -126, 24, 20, 52, C.cyan }, { -82, -142, 24, 24, 86, C.cyan },
		{ 58, -172, 26, 22, 96, C.pink }, { -26, -176, 26, 24, 110, C.violet }, { 24, -198, 28, 24, 124, C.amber },
		{ -120, -118, 24, 24, 48, C.amber }, { -140, -170, 28, 26, 92, C.pink }, { 120, -198, 26, 26, 80, C.cyan },
		{ -70, -222, 30, 26, 132, C.amber }, { 80, -238, 30, 28, 116, C.violet }, { -2, -252, 34, 30, 150, C.cyan },
		{ -168, -120, 22, 22, 40, C.cyan }, { 162, -186, 22, 22, 58, C.amber },
	}
	for _, t in towers do
		local faces = { Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right }
		Props.tower(sky, Vector3.new(t[1] :: number, groundY, t[2] :: number), t[3] :: number, t[4] :: number, t[5] :: number, rng, {
			material = if rng:NextNumber() < 0.5 then M.Concrete else M.Glass,
			color = Kit.mix(Color3.fromRGB(60, 66, 84), Color3.fromRGB(96, 104, 124), rng:NextNumber()),
			neon = t[6] :: Color3,
			faces = faces,
			lit = 0.3,
		})
		Kit.step()
	end
	-- signs on the nearer towers, facing the district
	Props.neonSign(sky, CFrame.new(-46, groundY + 42, -117.6), 16, 4.2, "VOLT CITY", C.cyan)
	Props.neonSign(sky, CFrame.new(46, groundY + 38, -115.6), 16, 4.2, "MIDNIGHT", C.pink)
	Props.neonSign(sky, CFrame.new(-82, groundY + 60, -129.6), 15, 4, "KUMO KARAOKE", C.violet)
	Props.neonSign(sky, CFrame.new(58, groundY + 70, -160.6), 15, 4, "NOVA NOODLE", C.amber)
	-- blade signs down two tower corners
	for _, b in { { -35.4, -118.5, "NOVA", C.pink }, { 35.4, -116.5, "VOLT", C.cyan } } do
		local cf = CFrame.new(b[1] :: number, groundY + 24, b[2] :: number)
		Props.neonSign(sky, cf, 3.4, 15, table.concat(string.split(b[3] :: string, ""), "\n"), b[4] :: Color3, Enum.Font.Sarpanch, false)
	end
	-- water tower on the left tower's roof
	local wt = Kit.model(sky, "WaterTower")
	local wtBase = Vector3.new(-50, groundY + 58, -130)
	for _, p in { Vector3.new(-2.6, 0, -2.6), Vector3.new(2.6, 0, -2.6), Vector3.new(-2.6, 0, 2.6), Vector3.new(2.6, 0, 2.6) } do
		Kit.deco(wt, CFrame.new(wtBase + p + Vector3.new(0, 3, 0)), Vector3.new(0.5, 6, 0.5), M.Metal, C.metalDark)
	end
	Kit.cylinder(wt, wtBase + Vector3.new(0, 9.5, 0), 7, 7.6, M.WoodPlanks, Color3.fromRGB(128, 96, 70), { Name = "Tank", CanCollide = false })
	Kit.cylinder(wt, wtBase + Vector3.new(0, 13.6, 0), 1.2, 5, M.Metal, C.metalDark, { CanCollide = false })
	-- warm street-level glow along the podium's back (seen through the gaps between towers)
	for _, x in { -60, -20, 20, 60 } do
		local lamp = Kit.deco(sky, CFrame.new(x, groundY + 5, -110), Vector3.new(0.4, 0.4, 0.4), M.SmoothPlastic, C.warm, { Name = "StreetGlow", Transparency = 1 })
		Kit.point(lamp, C.warm, 1, 24, false)
	end
end

function Arena.build(def: Layout.ArenaDef): Model
	local model = ArenaKit.new(def)
	ArenaKit.stage(model, def, {
		podiumMaterial = M.Concrete,
		podiumColor = C.podium,
		rimMaterial = M.Metal,
		rimColor = C.podiumTrim,
		apronMaterial = M.Asphalt,
		apronColor = C.apron,
		bandMaterial = M.DiamondPlate,
		bandColor = C.band,
		lineColor = C.pink,
		floorMaterial = M.Asphalt,
		floorColor = C.floor,
		stairMaterial = M.Concrete,
		stairColor = C.stair,
		stairNose = C.cyan,
		cheekMaterial = M.Concrete,
		cheekColor = C.podium,
	})
	facade(model, def)
	ArenaKit.parapet(model, def, 26, 334, 1.1, M.Concrete, C.parapet, C.cyan, M.Neon)
	ArenaKit.barrier(model, def, {
		posts = 20,
		post = function(parent: Instance, base: Vector3, out: Vector3, _i: number)
			local cf = CFrame.lookAt(base, base + out)
			Kit.block(parent, cf * CFrame.new(0, 1.8, 0), Vector3.new(0.32, 3.6, 0.32), M.Metal, C.metalDark, { Name = "EdgePost" })
			Kit.glow(parent, cf * CFrame.new(0, 3.66, 0), Vector3.new(0.42, 0.14, 0.42), C.pink, { Name = "EdgePostCap" })
			Kit.block(parent, cf * CFrame.new(0, 0.1, 0), Vector3.new(0.7, 0.2, 0.7), M.Metal, C.metalDark, { Name = "EdgePostFoot", CanCollide = false })
		end,
		rails = {
			{ height = 1.95, diameter = 0.2, material = M.Neon, color = C.cyan, name = "EdgeRailLow" },
			{ height = 3.35, diameter = 0.2, material = M.Neon, color = C.cyan, name = "EdgeRailTop" },
		},
	})
	ArenaKit.contractPieces(model, def)
	ArenaKit.paintFloor(model, def, {
		lineColor = Color3.fromRGB(240, 240, 250),
		rings = { { 9.5, 0.28, 0.15 }, { 15.5, 0.12, 0.55 } },
		emblem = "MIDNIGHT",
		emblemColor = C.pink,
		emblemFont = Enum.Font.Sarpanch,
		emblemTransparency = 0.6,
		lightInfluence = 0.8,
	})
	rooftopKit(model, def)
	local lights = Kit.model(model, "StageLights")
	for _, a in { 128, 160, -160, -128 } do
		ArenaKit.stageLight(lights, def, a, Color3.fromRGB(232, 222, 255), 12, 1.1, Color3.fromRGB(46, 48, 58))
	end
	ArenaKit.statusBoard(model, def, 18, C.metalDark, M.Metal, nil, function(_cf: CFrame) end)
	skyline(model, def)
	return model
end

return Arena
