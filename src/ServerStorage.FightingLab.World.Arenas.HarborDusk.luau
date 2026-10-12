--!strict
-- Arena: Harbor Dusk (east-south-east). A round timber pier by the harbour basin: a canvas fight mat
-- ringed by an orange edge line and two hemp ropes on dock pilings, sodium floodlights and festoon bulbs above the
-- back of the deck, moored boats below it and the harbour signal board out on the water.
local Kit = require(script.Parent.Parent.Kit)
local Props = require(script.Parent.Parent.Props)
local ArenaKit = require(script.Parent.Parent.ArenaKit)
local Layout = require(script.Parent.Parent.Layout)

local Arena = {}

local M = Enum.Material

local C = {
	deck = Color3.fromRGB(150, 114, 82),
	deckDark = Color3.fromRGB(96, 72, 52),
	piling = Color3.fromRGB(74, 58, 44),
	canvas = Color3.fromRGB(214, 202, 178),
	rope = Color3.fromRGB(198, 170, 118),
	orange = Color3.fromRGB(255, 152, 54),
	sodium = Color3.fromRGB(255, 176, 96),
	steel = Color3.fromRGB(70, 74, 82),
	navy = Color3.fromRGB(40, 60, 96),
	white = Color3.fromRGB(236, 232, 224),
	red = Color3.fromRGB(196, 54, 44),
	yellow = Color3.fromRGB(240, 186, 52),
}

local function pierDressing(model: Model, def: Layout.ArenaDef, rng: Random)
	local dock = Kit.model(model, "Dock")
	local base = def.floorY - Layout.APRON_DROP
	local R = Layout.STAGE_RADIUS
	-- pilings round the back half of the pier wall, down into the water (the sides stay clear: the walkways between
	-- the stages pass there)
	for a = 0, 359, 15 do
		local d = Layout.around(def, a)
		if math.abs(ArenaKit.angleOf(def, d)) > 95 then
			local p = def.origin + d * (R + 0.35)
			Kit.cylinder(dock, Vector3.new(p.X, -3.2, p.Z), 9.4, 1.3, M.Wood, C.piling, { Name = "Piling" })
		end
	end
	-- bollards and coiled rope on the back half of the apron rim, fenders on the pier wall
	for _, a in { 100, 130, 160, -160, -130, -100 } do
		local d = Layout.around(def, a)
		local p = def.origin + d * (R - 0.8)
		Props.bollard(dock, Vector3.new(p.X, base, p.Z))
		local f = def.origin + d * (R + 0.9)
		Kit.cylinder(dock, CFrame.lookAt(Vector3.new(f.X, -0.6, f.Z), Vector3.new(f.X, -0.6, f.Z) + d) * CFrame.Angles(math.rad(90), 0, 0), 1.6, 1.8, M.Rubber, Color3.fromRGB(30, 30, 32), { Name = "Fender", CanCollide = false })
	end
	for _, a in { 115, -145 } do
		local d = Layout.around(def, a)
		local p = def.origin + d * (R - 1.0)
		Kit.cylinder(dock, Vector3.new(p.X, base + 0.25, p.Z), 0.5, 1.6, M.Fabric, C.rope, { Name = "RopeCoil", CanCollide = false })
		Kit.cylinder(dock, Vector3.new(p.X, base + 0.55, p.Z), 0.3, 1.0, M.Fabric, Kit.shade(C.rope, 0.85), { Name = "RopeCoil", CanCollide = false })
	end
	-- life ring on a short post by each pad
	for _, a in { 86, -86 } do
		local d = Layout.around(def, a)
		local p = def.origin + d * (R - 0.8)
		local foot = Vector3.new(p.X, base, p.Z)
		Kit.block(dock, CFrame.new(foot + Vector3.new(0, 1.3, 0)), Vector3.new(0.4, 2.6, 0.4), M.Wood, C.piling, { Name = "RingPost" })
		Kit.cylinder(dock, CFrame.lookAt(foot + Vector3.new(0, 2.1, 0), foot + Vector3.new(0, 2.1, 0) + def.inward) * CFrame.Angles(0, math.rad(90), 0), 0.3, 1.8, M.SmoothPlastic, C.orange, { Name = "LifeRing", CanCollide = false })
	end
	-- crates at the back of the apron rim, clear of the flat fight floor
	for _, a in { 148, -150 } do
		local d = Layout.around(def, a)
		local p = def.origin + d * 26.0
		local along = Vector3.new(-d.Z, 0, d.X)
		Props.crate(dock, CFrame.new(p.X, base, p.Z) * CFrame.Angles(0, rng:NextNumber(0, 1), 0), 1.1)
		local q = p + along * 1.5
		Props.crate(dock, CFrame.new(q.X, base, q.Z) * CFrame.Angles(0, rng:NextNumber(0, 1), 0), 0.95)
	end
	-- festoon bulbs strung from bracket ends just outside the floodlight poles, along the two back corners
	local tops: { Vector3 } = {}
	for _, a in { 122, 154, -154, -122 } do
		local d = Layout.around(def, a)
		local p = def.origin + d * (R + 0.2)
		local pole = def.origin + d * (R - 0.8)
		table.insert(tops, Vector3.new(p.X, base + 11.2, p.Z))
		Kit.rod(dock, Vector3.new(pole.X, base + 11.2, pole.Z), Vector3.new(p.X, base + 11.2, p.Z), 0.14, M.Metal, Color3.fromRGB(46, 48, 54), { Name = "FestoonBracket", CanCollide = false })
	end
	for _, pair in { { 1, 2 }, { 3, 4 } } do
		Props.stringLights(dock, tops[pair[1]], tops[pair[2]], 7, Color3.fromRGB(255, 206, 140), 1.2, 4)
	end
	-- moored boats and channel buoys behind the pier
	local out = -def.inward
	local side = def.right
	local water = Layout.WATER_Y
	Props.boat(dock, CFrame.lookAt(def.origin + out * 44 + side * 18 + Vector3.new(0, water - def.floorY + 0.9, 0), def.origin + out * 44 + side * 40 + Vector3.new(0, water - def.floorY + 0.9, 0)), Color3.fromRGB(60, 110, 160))
	Props.boat(dock, CFrame.lookAt(def.origin + out * 46 - side * 20 + Vector3.new(0, water - def.floorY + 0.9, 0), def.origin + out * 52 - side * 40 + Vector3.new(0, water - def.floorY + 0.9, 0)), Color3.fromRGB(170, 60, 50))
	-- channel buoys out in the harbour basin behind the pier ({ out, right } from FightOrigin)
	for i, off in { { 40, -22 }, { 62, -6 }, { 50, 18 } } do
		local p = def.origin + out * off[1] + side * off[2]
		Kit.cylinder(dock, Vector3.new(p.X, water + 0.8, p.Z), 2.6, 1.5, M.SmoothPlastic, if i % 2 == 0 then Color3.fromRGB(60, 170, 80) else Color3.fromRGB(210, 60, 50), { Name = "Buoy", CanCollide = false })
		local lamp = Kit.glow(dock, CFrame.new(p.X, water + 2.5, p.Z), Vector3.new(0.6, 0.6, 0.6), if i % 2 == 0 then Color3.fromRGB(80, 255, 120) else Color3.fromRGB(255, 80, 60))
		Kit.tag(lamp, Kit.TAG_BLINK)
		lamp:SetAttribute("Period", 2 + i * 0.3)
	end
end

function Arena.build(def: Layout.ArenaDef): Model
	local model = ArenaKit.new(def)
	local rng = Kit.rng(2)
	ArenaKit.stage(model, def, {
		podiumMaterial = M.WoodPlanks,
		podiumColor = C.deckDark,
		podiumBottom = -5,
		rimMaterial = M.Wood,
		rimColor = C.piling,
		apronMaterial = M.WoodPlanks,
		apronColor = C.deck,
		bandMaterial = M.WoodPlanks,
		bandColor = Color3.fromRGB(86, 62, 44),
		lineColor = C.orange,
		floorMaterial = M.Fabric,
		floorColor = C.canvas,
		stairMaterial = M.WoodPlanks,
		stairColor = Color3.fromRGB(160, 124, 90),
		stairNose = C.orange,
	})
	ArenaKit.barrier(model, def, {
		posts = 16,
		post = function(parent: Instance, base: Vector3, _out: Vector3, _i: number)
			Kit.cylinder(parent, base + Vector3.new(0, 1.95, 0), 3.9, 0.78, M.Wood, C.piling, { Name = "EdgePost" })
			Kit.cylinder(parent, base + Vector3.new(0, 3.95, 0), 0.18, 0.92, M.Metal, Color3.fromRGB(46, 48, 54), { Name = "EdgePostCap", CanCollide = false })
			Kit.cylinder(parent, base + Vector3.new(0, 2.05, 0), 0.3, 0.86, M.Fabric, C.rope, { Name = "EdgePostLashing", CanCollide = false })
			Kit.cylinder(parent, base + Vector3.new(0, 3.45, 0), 0.3, 0.86, M.Fabric, C.rope, { Name = "EdgePostLashing", CanCollide = false })
		end,
		rails = {
			{ height = 2.05, diameter = 0.34, material = M.Fabric, color = C.rope, sag = 0.18, name = "EdgeRopeLow" },
			{ height = 3.45, diameter = 0.34, material = M.Fabric, color = C.rope, sag = 0.22, name = "EdgeRopeTop" },
		},
	})
	ArenaKit.contractPieces(model, def)
	ArenaKit.gate(model, def, M.WoodPlanks, Color3.fromRGB(96, 72, 52), Color3.fromRGB(255, 232, 200))
	ArenaKit.paintFloor(model, def, {
		lineColor = C.navy,
		rings = { { 9, 0.3, 0.25 }, { 19.6, 0.5, 0.15 } },
		ringColor = C.navy,
		emblem = "PIER 9",
		emblemColor = C.navy,
		emblemFont = Enum.Font.Oswald,
		emblemTransparency = 0.45,
		lightInfluence = 1,
	})
	pierDressing(model, def, rng)
	local lights = Kit.model(model, "StageLights")
	for _, a in { 122, 154, -154, -122 } do
		ArenaKit.stageLight(lights, def, a, C.sodium, 11, 1.25, Color3.fromRGB(88, 70, 54), Color3.fromRGB(40, 40, 44))
	end
	-- the status board stands on a steel frame out on the water behind the pier
	ArenaKit.statusBoard(model, def, 15, C.steel, M.Metal, nil, function(cf: CFrame)
		local frame = Kit.model(model, "BoardFrame")
		for _, sx in { -9, 9 } do
			local top = cf * CFrame.new(sx, -7.5, 0.9)
			local foot = Vector3.new(top.X, Layout.WATER_Y - 3, top.Z)
			Kit.block(frame, CFrame.new((top.Position + foot) / 2) * cf.Rotation, Vector3.new(1, top.Y - foot.Y, 1), M.Metal, C.steel, { Name = "BoardLeg" })
			Kit.cylinder(frame, Vector3.new(foot.X, Layout.WATER_Y, foot.Z), 3, 2.2, M.Concrete, Color3.fromRGB(120, 118, 112), { Name = "BoardPier" })
		end
		Kit.block(frame, cf * CFrame.new(0, -7.6, 0.9), Vector3.new(19, 0.6, 0.8), M.Metal, C.steel, { Name = "BoardBeam" })
		local lamp = Kit.glow(frame, cf * CFrame.new(0, 9.2, 0.4), Vector3.new(0.7, 0.7, 0.7), Color3.fromRGB(255, 60, 50), { Name = "AirBeacon" })
		Kit.tag(lamp, Kit.TAG_BLINK)
		lamp:SetAttribute("Period", 1.6)
	end)
	return model
end

return Arena
