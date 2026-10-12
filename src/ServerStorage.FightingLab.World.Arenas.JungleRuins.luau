--!strict
-- Arena: Jungle Ruins (south-west). An overgrown temple platform: sandstone fight floor with a carved sun,
-- a green glyph edge line inside carved stone posts strung with vine ropes, braziers at the back, broken pillars,
-- giant trees and a stepped pyramid rising out of the jungle behind.
local Kit = require(script.Parent.Parent.Kit)
local Props = require(script.Parent.Parent.Props)
local ArenaKit = require(script.Parent.Parent.ArenaKit)
local Layout = require(script.Parent.Parent.Layout)

local Arena = {}

local M = Enum.Material

local C = {
	stone = Color3.fromRGB(170, 160, 130),
	stoneDark = Color3.fromRGB(122, 114, 92),
	sand = Color3.fromRGB(214, 196, 154),
	cobble = Color3.fromRGB(146, 142, 116),
	moss = Color3.fromRGB(86, 120, 56),
	mossDark = Color3.fromRGB(58, 88, 44),
	vine = Color3.fromRGB(74, 98, 50),
	green = Color3.fromRGB(126, 226, 88),
	terracotta = Color3.fromRGB(176, 92, 58),
	fire = Color3.fromRGB(255, 150, 60),
	leaf = { Color3.fromRGB(62, 110, 52), Color3.fromRGB(78, 128, 58), Color3.fromRGB(50, 92, 46) },
}

local function brazier(parent: Instance, foot: Vector3)
	local m = Kit.model(parent, "Brazier")
	Kit.block(m, CFrame.new(foot + Vector3.new(0, 0.3, 0)), Vector3.new(1.8, 0.6, 1.8), M.Limestone, C.stoneDark)
	Kit.block(m, CFrame.new(foot + Vector3.new(0, 1.3, 0)), Vector3.new(1, 1.6, 1), M.Limestone, C.stone)
	local bowl = Kit.cylinder(m, foot + Vector3.new(0, 2.4, 0), 0.7, 2.2, M.Metal, Color3.fromRGB(70, 56, 40), { Name = "Bowl" })
	local flame = Kit.deco(m, CFrame.new(foot + Vector3.new(0, 2.9, 0)), Vector3.new(1.2, 0.4, 1.2), M.SmoothPlastic, C.fire, { Name = "FlameSource", Transparency = 1 })
	Kit.emitter(flame, {
		Name = "Fire",
		Color = Kit.colors(Color3.fromRGB(255, 210, 120), Color3.fromRGB(255, 80, 30)),
		LightEmission = 1,
		Size = Kit.numbers(1.1, 0.6, 0),
		Transparency = Kit.numbers(0.2, 0.5, 1),
		Lifetime = NumberRange.new(0.5, 0.9),
		Rate = 26,
		Speed = NumberRange.new(2.5, 4),
		SpreadAngle = Vector2.new(12, 12),
		EmissionDirection = Enum.NormalId.Top,
		Texture = "rbxasset://textures/particles/fire_main.dds",
	})
	local light = Kit.point(bowl, C.fire, 1.6, 16, false)
	Kit.tag(light, Kit.TAG_FLICKER)
	return m
end

local function temple(model: Model, def: Layout.ArenaDef, rng: Random)
	local ruins = Kit.model(model, "Ruins")
	local R = Layout.STAGE_RADIUS
	local base = def.floorY - Layout.APRON_DROP
	-- carved frieze round the platform wall with glowing glyph tiles
	for a = 48, 312, 16 do
		local d = Layout.around(def, a)
		local p = def.origin + d * (R + 0.05)
		local cf = CFrame.lookAt(Vector3.new(p.X, 1.2, p.Z), Vector3.new(p.X, 1.2, p.Z) + d)
		Kit.deco(ruins, cf, Vector3.new(5.2, 0.9, 0.2), M.Limestone, C.stoneDark, { Name = "Frieze" })
		if (a // 16) % 2 == 0 then
			Kit.glow(ruins, cf * CFrame.new(0, 0, 0.12), Vector3.new(0.7, 0.5, 0.06), C.green, { Name = "Glyph", Transparency = 0.15 })
		end
	end
	-- moss creeping over the rim and the wall foot
	for a = 54, 306, 24 do
		local d = Layout.around(def, a + rng:NextNumber(-5, 5))
		local p = def.origin + d * (R - 0.3)
		Kit.blob(ruins, CFrame.new(p.X, base + 0.05, p.Z) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), Vector3.new(rng:NextNumber(3, 5), 0.5, rng:NextNumber(1.6, 2.4)), M.LeafyGrass, C.moss, { Name = "Moss" })
		local q = def.origin + d * (R + 0.8)
		Props.bush(ruins, Vector3.new(q.X, 0.6, q.Z), Vector3.new(rng:NextNumber(2.6, 4), rng:NextNumber(1.6, 2.4), rng:NextNumber(2.6, 4)), C.mossDark, rng)
	end
	-- jungle floor round the temple: centred behind the stage (Layout.GROUND_SHIFT) so it stops short of the plaza kerb
	-- and of the Summit's snow field (two coplanar ground discs would z-fight where they overlap); PathfindingService
	-- would treat its hair-thin rim as a ledge and pinch the walkways between the stages, so it is marked walk-over
	local floor = Kit.cylinder(ruins, Vector3.new(def.origin.X, -0.2, def.origin.Z) - def.inward * Layout.GROUND_SHIFT, 0.44, (R + Layout.GROUND_MARGIN) * 2, M.LeafyGrass, Color3.fromRGB(84, 116, 58), { Name = "JungleFloor", CastShadow = false })
	Kit.passThrough(floor)
	-- broken pillars round the back (tall ones fade for the fight camera)
	for i, a in { 112, 138, 164, -166, -140, -114 } do
		local d = Layout.around(def, a)
		local reach = R + rng:NextNumber(4, 7)
		local h = if i % 2 == 0 then rng:NextNumber(9, 13) else rng:NextNumber(4, 7)
		-- ruins yield to the district edge, the pockets and the board: a little further out, else left out
		local spot: Vector3? = nil
		for _, extra in { 0, 4, 8 } do
			local p = def.origin + d * (reach + extra)
			if Kit.clearSpot(p, 2.4) then
				spot = Vector3.new(p.X, 0, p.Z)
				break
			end
		end
		if not spot then
			continue
		end
		local foot: Vector3 = spot
		Kit.keepOut(foot, 2.4)
		Kit.block(ruins, CFrame.new(foot + Vector3.new(0, 0.5, 0)), Vector3.new(3.2, 1, 3.2), M.Limestone, C.stoneDark, { Name = "PillarBase" })
		Kit.cylinder(ruins, foot + Vector3.new(0, 1 + h / 2, 0), h, 2.2, M.Limestone, C.stone, { Name = "Pillar" })
		if h > 8 then
			Kit.block(ruins, CFrame.new(foot + Vector3.new(0, 1.3 + h, 0)) * CFrame.Angles(0, rng:NextNumber(0, 1), 0), Vector3.new(3, 0.6, 3), M.Limestone, C.stoneDark, { Name = "PillarCap" })
		else
			Props.rock(ruins, foot + Vector3.new(rng:NextNumber(-3, 3), 0.6, rng:NextNumber(-3, 3)), Vector3.new(2.6, 1.4, 2), rng, C.stone, M.Limestone)
		end
		Kit.blob(ruins, CFrame.new(foot + Vector3.new(0, 1 + h * 0.6, 0)), Vector3.new(2.8, h * 0.5, 2.8), M.LeafyGrass, C.mossDark, { Name = "Vines", Transparency = 0.1 })
	end
	-- giant trees framing the temple
	local trees = Kit.model(model, "Canopy")
	-- giant trees round the back of the temple; a tree that would crowd a neighbouring fight's camera or lock boughs
	-- with a tree already standing tries further out, else is left out
	local wood: { BasePart } = {}
	for i = 1, 16 do
		local a = 96 + (i - 1) * (168 / 15) + rng:NextNumber(-4, 4)
		local d = Layout.around(def, a)
		local reach = rng:NextNumber(R + 12, R + 22)
		for _, extra in { 0, 5, 10 } do
			local p = def.origin + d * (reach + extra)
			local foot = Vector3.new(p.X, 0, p.Z)
			if Kit.clearSpot(foot, 2.6) then
				local tree = if i % 3 == 0
					then Props.palm(trees, foot, rng:NextNumber(1.2, 1.5), rng)
					else Props.tree(trees, foot, rng:NextNumber(1.6, 2.1), rng, C.leaf)
				if ArenaKit.clearOfNeighbours(def, tree) and not Kit.woodClashes(tree, wood) then
					Kit.keepOut(foot, 2.6)
					Kit.woodParts(tree, wood)
					break
				end
				tree:Destroy()
			end
		end
		Kit.step()
	end
end

local function pyramidCentre(def: Layout.ArenaDef): Vector3
	-- out behind the temple platform, a little to the left of the status board (77.5 out, 19.2 to the left)
	local c = def.origin - def.inward * 77.5 - def.right * 19.2
	return Vector3.new(c.X, -2, c.Z)
end

local function pyramid(model: Model, def: Layout.ArenaDef)
	local pyr = Kit.model(model, "Pyramid")
	local c = pyramidCentre(def)
	local toward = Vector3.new(-c.X, 0, -c.Z).Unit
	local f = CFrame.lookAt(c, c + toward)
	local size = 46
	local tier = 5.2
	for k = 0, 5 do
		local s = size - k * 7
		Kit.block(pyr, f * CFrame.new(0, tier * k + tier / 2, 0), Vector3.new(s, tier, s), M.Limestone, if k % 2 == 0 then C.stone else Kit.shade(C.stone, 0.92), { Name = "Tier", CanCollide = false })
		Kit.deco(pyr, f * CFrame.new(0, tier * (k + 1) - 0.25, -s / 2 - 0.05), Vector3.new(s, 0.5, 0.2), M.Limestone, C.stoneDark, { Name = "TierEdge" })
	end
	-- central stair up the face that looks at the plaza, and the shrine with its glowing stone
	local top = tier * 6
	local run = size / 2 - 4
	local a = (f * CFrame.new(0, 0.4, -size / 2 - 2)).Position
	local b = (f * CFrame.new(0, top, -size / 2 + run)).Position
	Kit.strut(pyr, a, b, 8, 1, M.Limestone, C.stoneDark, { Name = "PyramidStair", CanCollide = false })
	Kit.block(pyr, f * CFrame.new(0, top + 3, 0), Vector3.new(8, 6, 8), M.Limestone, C.stoneDark, { Name = "Shrine", CanCollide = false })
	Kit.block(pyr, f * CFrame.new(0, top + 6.5, 0), Vector3.new(10, 1, 10), M.Limestone, C.stone, { CanCollide = false })
	local gem = Kit.glow(pyr, f * CFrame.new(0, top + 3, -4.1) * CFrame.Angles(0, 0, math.rad(45)), Vector3.new(2, 2, 0.4), C.green, { Name = "SunStone" })
	Kit.point(gem, C.green, 2, 30, false)
	for _, sx in { -5.2, 5.2 } do
		brazier(pyr, (f * CFrame.new(sx, top, -5)).Position)
	end
	-- vines and moss on the tiers
	local rng = Kit.rng(33)
	for _ = 1, 10 do
		local k = rng:NextInteger(0, 4)
		local s = size - k * 7
		local x = rng:NextNumber(-s / 2 + 2, s / 2 - 2)
		Kit.blob(pyr, f * CFrame.new(x, tier * (k + 1) - 1, -s / 2 + 0.3), Vector3.new(rng:NextNumber(3, 6), rng:NextNumber(2, 4), 1.4), M.LeafyGrass, C.mossDark, { Name = "Vines" })
	end
end

function Arena.build(def: Layout.ArenaDef): Model
	local model = ArenaKit.new(def)
	local rng = Kit.rng(3)
	-- the pyramid's footprint (46-stud base) is claimed before any tree is placed
	Kit.keepOut(pyramidCentre(def), 30)
	ArenaKit.stage(model, def, {
		podiumMaterial = M.Limestone,
		podiumColor = C.stone,
		rimMaterial = M.Sandstone,
		rimColor = C.stoneDark,
		apronMaterial = M.Cobblestone,
		apronColor = C.cobble,
		bandMaterial = M.Slate,
		bandColor = Color3.fromRGB(84, 96, 74),
		lineColor = C.green,
		floorMaterial = M.Sandstone,
		floorColor = C.sand,
		stairMaterial = M.Limestone,
		stairColor = Color3.fromRGB(178, 168, 138),
		cheekMaterial = M.Limestone,
		cheekColor = C.stoneDark,
	})
	ArenaKit.barrier(model, def, {
		posts = 12,
		post = function(parent: Instance, base: Vector3, out: Vector3, _i: number)
			local cf = CFrame.lookAt(base, base + out)
			Kit.block(parent, cf * CFrame.new(0, 1.7, 0), Vector3.new(0.9, 3.4, 0.9), M.Limestone, C.stone, { Name = "EdgePost" })
			Kit.block(parent, cf * CFrame.new(0, 3.55, 0), Vector3.new(1.15, 0.3, 1.15), M.Limestone, C.stoneDark, { Name = "EdgePostCap", CanCollide = false })
			Kit.glow(parent, cf * CFrame.new(0, 2.7, -0.46), Vector3.new(0.42, 0.42, 0.04), C.green, { Name = "EdgeGlyph", Transparency = 0.1 })
			Kit.blob(parent, CFrame.new(base + Vector3.new(0, 0.3, 0)), Vector3.new(1.1, 0.6, 1.1), M.LeafyGrass, C.mossDark, { Name = "EdgeMoss" })
		end,
		rails = {
			{ height = 2.1, diameter = 0.3, material = M.Fabric, color = C.vine, sag = 0.3, name = "EdgeVineLow" },
			{ height = 3.3, diameter = 0.32, material = M.Fabric, color = C.vine, sag = 0.4, name = "EdgeVineTop" },
		},
	})
	ArenaKit.contractPieces(model, def)
	ArenaKit.gate(model, def, M.Limestone, Color3.fromRGB(122, 114, 92), Color3.fromRGB(236, 255, 220))
	local paint = ArenaKit.paintFloor(model, def, {
		lineColor = C.terracotta,
		rings = { { 9, 0.42, 0.25 }, { 16, 0.12, 0.55 } },
		ringColor = C.terracotta,
		lightInfluence = 1,
	})
	-- sun rays between the inner rings
	local gui = paint:FindFirstChild("Paint") :: SurfaceGui
	for i = 0, 11 do
		local ray = Instance.new("Frame")
		ray.Name = "Ray"
		ray.AnchorPoint = Vector2.new(0.5, 0.5)
		ray.Position = UDim2.fromScale(0.5, 0.5)
		ray.Size = UDim2.fromOffset(0.3 * gui.PixelsPerStud, 12.4 * gui.PixelsPerStud)
		ray.Rotation = i * 15
		ray.BackgroundColor3 = C.terracotta
		ray.BackgroundTransparency = 0.45
		ray.BorderSizePixel = 0
		ray.Parent = gui
	end
	-- the rays start at the inner ring: a sand-coloured disc covers their inner ends, ringed in terracotta
	local hub = Instance.new("Frame")
	hub.Name = "Hub"
	hub.AnchorPoint = Vector2.new(0.5, 0.5)
	hub.Position = UDim2.fromScale(0.5, 0.5)
	hub.Size = UDim2.fromOffset(8.2 * gui.PixelsPerStud, 8.2 * gui.PixelsPerStud)
	hub.BackgroundColor3 = C.sand
	hub.BackgroundTransparency = 0.1
	hub.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = hub
	local hubStroke = Instance.new("UIStroke")
	hubStroke.Thickness = 0.3 * gui.PixelsPerStud
	hubStroke.Color = C.terracotta
	hubStroke.Transparency = 0.3
	hubStroke.Parent = hub
	hub.Parent = gui
	temple(model, def, rng)
	local fires = Kit.model(model, "Braziers")
	for _, a in { 118, 150, -150, -118 } do
		local d = Layout.around(def, a)
		local p = def.origin + d * (Layout.STAGE_RADIUS - 0.8)
		brazier(fires, Vector3.new(p.X, def.floorY - Layout.APRON_DROP, p.Z))
	end
	pyramid(model, def)
	-- status board between two carved pillars (a temple gate) behind the platform
	ArenaKit.statusBoard(model, def, 14, Color3.fromRGB(70, 60, 46), M.Wood, nil, function(cf: CFrame)
		local gate = Kit.model(model, "BoardGate")
		for _, sx in { -14.4, 14.4 } do
			local top = cf * CFrame.new(sx, 11.2, 0.4)
			local foot = Vector3.new(top.X, -2, top.Z)
			Kit.block(gate, CFrame.new((top.Position + foot) / 2) * cf.Rotation, Vector3.new(3, top.Y - foot.Y, 3), M.Limestone, C.stone, { Name = "GatePillar" })
			Kit.glow(gate, cf * CFrame.new(sx, 2, -1.13), Vector3.new(0.8, 0.8, 0.05), C.green, { Name = "GateGlyph" })
		end
		Kit.block(gate, cf * CFrame.new(0, 12.4, 0.4), Vector3.new(34, 2.4, 3.4), M.Limestone, C.stoneDark, { Name = "GateLintel" })
		Kit.blob(gate, cf * CFrame.new(-8, 13.4, 0.4), Vector3.new(10, 3, 4), M.LeafyGrass, C.mossDark, { Name = "Vines" })
	end)
	return model
end

return Arena
