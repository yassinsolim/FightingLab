--!strict
-- Arena: Training Bay (west). An open-air dojo pier on the bay: tatami fight floor with a gold edge
-- line inside a lacquered post fence strung with a red cord and a thick straw rope hung with paper streamers,
-- training dummies and stone lanterns on the deck, cherry trees, and the pagoda-roofed hall over the water behind
-- (it carries the practice board).
local Kit = require(script.Parent.Parent.Kit)
local Props = require(script.Parent.Parent.Props)
local ArenaKit = require(script.Parent.Parent.ArenaKit)
local Layout = require(script.Parent.Parent.Layout)

local Arena = {}

local M = Enum.Material

local C = {
	deck = Color3.fromRGB(182, 140, 98),
	deckDark = Color3.fromRGB(98, 70, 50),
	post = Color3.fromRGB(86, 36, 30),
	lacquer = Color3.fromRGB(150, 44, 38),
	tatami = Color3.fromRGB(200, 190, 136),
	straw = Color3.fromRGB(214, 190, 120),
	red = Color3.fromRGB(184, 42, 36),
	paper = Color3.fromRGB(246, 244, 236),
	gold = Color3.fromRGB(255, 206, 92),
	roof = Color3.fromRGB(56, 60, 70),
	plaster = Color3.fromRGB(236, 228, 210),
	ink = Color3.fromRGB(30, 26, 24),
	blossom = { Color3.fromRGB(250, 186, 206), Color3.fromRGB(244, 160, 190), Color3.fromRGB(255, 210, 222) },
	lantern = Color3.fromRGB(255, 196, 120),
}

local function dummy(parent: Instance, foot: Vector3, facing: Vector3)
	local m = Kit.model(parent, "TrainingDummy")
	local cf = CFrame.lookAt(foot, foot + facing)
	Kit.block(m, cf * CFrame.new(0, 0.2, 0), Vector3.new(2.2, 0.4, 2.2), M.Wood, C.deckDark, { Name = "DummyBase" })
	Kit.cylinder(m, cf * CFrame.new(0, 2.4, 0), 4.4, 1.1, M.Wood, Color3.fromRGB(150, 106, 70), { Name = "DummyTrunk" })
	for _, arm in { { 0.4, 3.4, 0.35 }, { -0.4, 3.4, -0.35 }, { 0, 2.1, 0 } } do
		local a = (cf * CFrame.new(arm[1], arm[2], -0.4)).Position
		local b = (cf * CFrame.new(arm[1] + arm[3], arm[2] - 0.2, -1.9)).Position
		Kit.rod(m, a, b, 0.28, M.Wood, C.deckDark, { Name = "DummyArm", CanCollide = false })
	end
	Kit.cylinder(m, cf * CFrame.new(0, 4.7, 0), 0.25, 1.25, M.Fabric, C.red, { Name = "DummyBand", CanCollide = false })
end

local function cherry(parent: Instance, pos: Vector3, scale: number, rng: Random)
	local t = Props.tree(parent, pos, scale, rng, C.blossom)
	t.Name = "CherryTree"
	return t
end

local function hall(model: Model, def: Layout.ArenaDef, rng: Random): CFrame
	local h = Kit.model(model, "DojoHall")
	local out = -def.inward
	local centre = def.origin + out * 64
	centre = Vector3.new(centre.X, 0, centre.Z)
	local f = CFrame.lookAt(centre, centre + def.inward) -- local -Z faces the stage / plaza
	local W, D = 44, 18
	local deckTop = 1.2
	-- deck on pilings over the bay, joined to the dojo pier by a short boardwalk
	Kit.block(h, f * CFrame.new(0, deckTop - 0.5, 0), Vector3.new(W + 6, 1, D + 6), M.WoodPlanks, C.deck, { Name = "HallDeck" })
	for x = -W / 2, W / 2, 8 do
		for _, z in { -D / 2 - 2, D / 2 + 2 } do
			Kit.cylinder(h, (f * CFrame.new(x, -3.6, z)).Position, 8, 1.2, M.Wood, C.deckDark, { Name = "Piling" })
		end
	end
	local walkFrom = def.origin + out * (Layout.STAGE_RADIUS - 2)
	local walkTo = centre - out * (D / 2 + 3)
	local mid = (walkFrom + walkTo) / 2
	local len = (Vector3.new(walkTo.X, 0, walkTo.Z) - Vector3.new(walkFrom.X, 0, walkFrom.Z)).Magnitude
	-- top 0.14 under the deck: below the whole stage stack it starts on (apron, rim and podium tops at floor - 0.06,
	-- -0.08 and -0.10), so it never shares a height with them where they overlap
	Kit.block(h, CFrame.lookAt(Vector3.new(mid.X, deckTop - 0.64, mid.Z), Vector3.new(walkTo.X, deckTop - 0.64, walkTo.Z)), Vector3.new(8, 1, len), M.WoodPlanks, C.deck, { Name = "Boardwalk" })
	-- posts, plaster walls with lit paper screens on the front, the two-tier roof
	for x = -W / 2 + 1, W / 2 - 1, 7 do
		for _, z in { -D / 2 + 1, D / 2 - 1 } do
			Kit.block(h, f * CFrame.new(x, deckTop + 5, z), Vector3.new(1.1, 10, 1.1), M.Wood, C.post, { Name = "HallPost" })
		end
	end
	-- a hair lower than the posts it runs through, so their tops never coincide
	Kit.block(h, f * CFrame.new(0, deckTop + 4.95, D / 2 - 1), Vector3.new(W - 2, 9.9, 0.6), M.Plaster, C.plaster, { Name = "BackWall" })
	for x = -W / 2 + 4.5, W / 2 - 4.5, 7 do
		local screen = Kit.glow(h, f * CFrame.new(x, deckTop + 4, -D / 2 + 1.2), Vector3.new(5.4, 6.4, 0.1), Color3.fromRGB(255, 226, 170), { Name = "PaperScreen", Transparency = 0.25 })
		local _ = screen
		for k = -1, 1 do
			Kit.deco(h, f * CFrame.new(x + k * 1.8, deckTop + 4, -D / 2 + 1.1), Vector3.new(0.12, 6.4, 0.12), M.Wood, C.post, { Name = "Lattice" })
		end
		Kit.deco(h, f * CFrame.new(x, deckTop + 4, -D / 2 + 1.1), Vector3.new(5.4, 0.12, 0.12), M.Wood, C.post, { Name = "Lattice" })
	end
	local glowAnchor = Kit.deco(h, f * CFrame.new(0, deckTop + 5, -D / 2 + 3), Vector3.new(0.4, 0.4, 0.4), M.SmoothPlastic, C.lantern, { Name = "HallGlow", Transparency = 1 })
	Kit.point(glowAnchor, Color3.fromRGB(255, 210, 150), 1.6, 26, false)
	local function roof(y: number, w: number, d: number, rise: number)
		Kit.wedge(h, f * CFrame.new(0, y + rise / 2, -d / 4) * CFrame.Angles(0, math.pi, 0), Vector3.new(w, rise, d / 2), M.Slate, C.roof, { Name = "Roof", CanCollide = false })
		Kit.wedge(h, f * CFrame.new(0, y + rise / 2, d / 4), Vector3.new(w, rise, d / 2), M.Slate, C.roof, { Name = "Roof", CanCollide = false })
		Kit.deco(h, f * CFrame.new(0, y + rise + 0.2, 0), Vector3.new(w + 0.6, 0.5, 0.8), M.Slate, Kit.shade(C.roof, 0.8), { Name = "Ridge" })
		Kit.deco(h, f * CFrame.new(0, y - 0.15, -d / 2 + 0.1), Vector3.new(w, 0.3, 0.4), M.Wood, C.lacquer, { Name = "Eave" })
		Kit.deco(h, f * CFrame.new(0, y - 0.15, d / 2 - 0.1), Vector3.new(w, 0.3, 0.4), M.Wood, C.lacquer, { Name = "Eave" })
	end
	roof(deckTop + 10, W + 6, D + 8, 4.5)
	Kit.block(h, f * CFrame.new(0, deckTop + 15.5, 0), Vector3.new(W * 0.5, 2.4, D * 0.5), M.Wood, C.post, { Name = "Loft", CanCollide = false })
	roof(deckTop + 16.8, W * 0.62, D * 0.7, 3.4)
	-- banners on the front posts
	local words = { "FOCUS", "BALANCE", "SPIRIT", "RESOLVE" }
	for i, x in { -15, -8, 8, 15 } do
		local top = (f * CFrame.new(x, deckTop + 9.4, -D / 2 - 0.2)).Position
		Props.banner(h, top, def.inward, 1.8, 6.4, if i % 2 == 0 then C.lacquer else C.ink, words[i], C.paper)
	end
	-- hanging lanterns along the eave
	for x = -W / 2 + 2, W / 2 - 2, 6 do
		local top = (f * CFrame.new(x, deckTop + 9.6, -D / 2 - 2.6)).Position
		Props.hangingLantern(h, top, C.lantern, 1.1, false)
	end
	-- a rowboat tied to the hall deck
	Props.boat(h, f * CFrame.new(W / 2 + 10, Layout.WATER_Y + 0.9, 4) * CFrame.Angles(0, math.rad(80), 0), Color3.fromRGB(96, 120, 140))
	local _r = rng
	return f * CFrame.new(0, 0, -D / 2 - 3)
end

function Arena.build(def: Layout.ArenaDef): Model
	local model = ArenaKit.new(def)
	local rng = Kit.rng(5)
	ArenaKit.stage(model, def, {
		podiumMaterial = M.WoodPlanks,
		podiumColor = C.deckDark,
		podiumBottom = -5,
		rimMaterial = M.Wood,
		rimColor = C.lacquer,
		apronMaterial = M.WoodPlanks,
		apronColor = C.deck,
		bandMaterial = M.Wood,
		bandColor = C.lacquer,
		lineColor = C.gold,
		floorMaterial = M.Fabric,
		floorColor = C.tatami,
		stairMaterial = M.WoodPlanks,
		stairColor = Color3.fromRGB(170, 130, 92),
		stairNose = C.gold,
	})
	ArenaKit.barrier(model, def, {
		posts = 16,
		post = function(parent: Instance, base: Vector3, out: Vector3, _i: number)
			local cf = CFrame.lookAt(base, base + out)
			Kit.block(parent, cf * CFrame.new(0, 1.75, 0), Vector3.new(0.46, 3.5, 0.46), M.Wood, C.post, { Name = "EdgePost" })
			Kit.block(parent, cf * CFrame.new(0, 3.58, 0), Vector3.new(0.62, 0.16, 0.62), M.Metal, Color3.fromRGB(196, 160, 86), { Name = "EdgePostCap", CanCollide = false })
		end,
		rails = {
			{ height = 2.0, diameter = 0.2, material = M.Fabric, color = C.red, sag = 0.12, name = "EdgeCord" },
			{ height = 3.25, diameter = 0.5, material = M.Fabric, color = C.straw, sag = 0.28, name = "EdgeRope" },
		},
	})
	-- paper streamers hanging from the straw rope midway between posts
	local streamers = Kit.model(model, "Streamers")
	local base = def.floorY - Layout.APRON_DROP
	ArenaKit.ring(16, 180 / 16 + 360 / 32, function(_i, d)
		local p = Vector3.new(def.origin.X, base, def.origin.Z) + d * (Layout.RAIL_RADIUS * math.cos(math.rad(360 / 32)))
		local top = p + Vector3.new(0, 2.6, 0)
		local cf = CFrame.lookAt(top, top + d)
		Kit.deco(streamers, cf * CFrame.new(0, -0.25, 0), Vector3.new(0.34, 0.5, 0.04), M.Fabric, C.paper, { Name = "EdgeStreamer" })
		Kit.deco(streamers, cf * CFrame.new(0.12, -0.7, 0) * CFrame.Angles(0, 0, math.rad(20)), Vector3.new(0.3, 0.46, 0.04), M.Fabric, C.paper, { Name = "EdgeStreamer" })
	end)
	ArenaKit.contractPieces(model, def)
	ArenaKit.gate(model, def, M.Wood, C.lacquer, Color3.fromRGB(255, 240, 210))
	ArenaKit.paintFloor(model, def, {
		lineColor = C.ink,
		rings = { { 9, 0.5, 0.2 } },
		ringColor = C.ink,
		emblem = "DOJO",
		emblemColor = C.ink,
		emblemFont = Enum.Font.PermanentMarker,
		emblemTransparency = 0.5,
		lightInfluence = 1,
	})
	-- deck dressing: dummies at the back, stone lanterns at the back corners, cherry trees behind the pier's sides
	local dressing = Kit.model(model, "Dressing")
	for _, a in { 146, -146 } do
		local d = Layout.around(def, a)
		local p = def.origin + d * 26.2
		-- side-on to the ring, so the dummy's arms stay over the apron rim
		dummy(dressing, Vector3.new(p.X, base, p.Z), Vector3.new(-d.Z, 0, d.X))
	end
	for _, a in { 116, -116 } do
		local d = Layout.around(def, a)
		local p = def.origin + d * 26.1
		local foot = Vector3.new(p.X, base, p.Z)
		local lantern = Props.lantern(dressing, foot, C.lantern, M.Granite, Color3.fromRGB(150, 146, 136), 3.4)
		-- squared to the ring, so its corners stay outside the flat fight floor's radius
		local turn = CFrame.lookAt(foot, foot - d)
		for _, part in lantern:GetDescendants() do
			if part:IsA("BasePart") then
				part.CFrame = turn * CFrame.new(foot):ToObjectSpace(part.CFrame)
			end
		end
	end
	for _, a in { 112, -112 } do
		local d = Layout.around(def, a)
		-- a cherry whose crown would spread over the fight floor is regrown (then moved out a little)
		for k = 0, 5 do
			local p = def.origin + d * (Layout.STAGE_RADIUS + 5 + (k // 2) * 1.5)
			local tree = cherry(dressing, Vector3.new(p.X, 0, p.Z), rng:NextNumber(1.05, 1.25), rng)
			if ArenaKit.clearOfFightFloor(def, tree) then
				break
			end
			tree:Destroy()
		end
	end
	local lights = Kit.model(model, "StageLights")
	for _, a in { 126, 158, -158, -126 } do
		ArenaKit.stageLight(lights, def, a, Color3.fromRGB(255, 226, 180), 11, 1, C.post, Color3.fromRGB(40, 30, 26))
	end
	-- lantern strings along the two back corners of the deck, hung from brackets just outside the light poles (so they
	-- stay clear of the flat fight floor)
	local tops: { Vector3 } = {}
	for _, a in { 126, 158, -158, -126 } do
		local d = Layout.around(def, a)
		local p = def.origin + d * (Layout.STAGE_RADIUS + 0.2)
		local pole = def.origin + d * (Layout.STAGE_RADIUS - 0.8)
		table.insert(tops, Vector3.new(p.X, base + 10.4, p.Z))
		Kit.rod(dressing, Vector3.new(pole.X, base + 10.4, pole.Z), Vector3.new(p.X, base + 10.4, p.Z), 0.14, M.Wood, C.post, { Name = "LanternBracket", CanCollide = false })
	end
	for _, pair in { { 1, 2 }, { 3, 4 } } do
		Props.stringLights(dressing, tops[pair[1]], tops[pair[2]], 6, C.lantern, 1.4, 3)
	end
	hall(model, def, rng)
	-- the practice board stands on a timber frame above the hall's front roof, like a dojo name board
	ArenaKit.statusBoard(model, def, 27, C.post, M.Wood, nil, function(cf: CFrame)
		local frame = Kit.model(model, "BoardFrame")
		for _, sx in { -9, 9 } do
			local top = cf * CFrame.new(sx, -7.4, 0.7)
			local foot = Vector3.new(top.X, 11.4, top.Z)
			Kit.block(frame, CFrame.new((top.Position + foot) / 2) * cf.Rotation, Vector3.new(0.9, top.Y - foot.Y, 0.9), M.Wood, C.post, { Name = "BoardLeg" })
		end
		Kit.block(frame, cf * CFrame.new(0, -7.6, 0.7), Vector3.new(22, 0.6, 0.8), M.Wood, C.post, { Name = "BoardBeam" })
		Kit.block(frame, cf * CFrame.new(0, 11.3, 0.3), Vector3.new(27, 0.7, 2), M.Wood, C.lacquer, { Name = "BoardRoof" })
	end)
	return model
end

return Arena
