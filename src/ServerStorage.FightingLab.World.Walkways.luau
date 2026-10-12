--!strict
-- World.Walkways (OV6: the district grounds). The walkable district floor round the plaza (a 6-stud slab, top Y = 0,
-- radius 100, so no terrain can show through), its edge (a stone balustrade on the land sides, a quay with bollards
-- and a rail over the water), and the pockets between the stages, each a small destination with a view:
-- night market (NE), sea lookout (ESE), welcome wall (S), beach garden (WSW) and lantern garden (NW).
local Kit = require(script.Parent.Kit)
local Props = require(script.Parent.Props)
local Layout = require(script.Parent.Layout)

local Walkways = {}

local M = Enum.Material
local polar = Layout.polar

local C = {
	floor = Color3.fromRGB(184, 172, 152),
	ring = Color3.fromRGB(160, 146, 126),
	stone = Color3.fromRGB(214, 200, 176),
	stoneDark = Color3.fromRGB(150, 138, 120),
	granite = Color3.fromRGB(88, 82, 80),
	bronze = Color3.fromRGB(176, 128, 62),
	iron = Color3.fromRGB(46, 48, 54),
	warm = Color3.fromRGB(255, 206, 140),
	sand = Color3.fromRGB(226, 204, 158),
	cream = Color3.fromRGB(246, 236, 214),
	ember = Color3.fromRGB(255, 96, 24),
}

-- Gap bearings between neighbouring stages, and whether that edge faces open water.
Walkways.GAPS = {
	{ bearing = 36, water = false, kind = "Market" },
	{ bearing = 108, water = true, kind = "Lookout" },
	{ bearing = 180, water = false, kind = "Welcome" },
	{ bearing = 252, water = true, kind = "Beach" },
	{ bearing = 324, water = false, kind = "Garden" },
}

-- Angular half-width (degrees) a stage podium (or a circle of `radius` round its FightOrigin) occupies on the circle
-- of radius r round the plaza centre.
function Walkways.stageHalfAngle(r: number, d: number?, radius: number?): number
	local dist = d or Layout.ARENA_DISTANCE
	local R = radius or Layout.STAGE_RADIUS
	local c = (r * r + dist * dist - R * R) / (2 * r * dist)
	return math.deg(math.acos(math.clamp(c, -1, 1)))
end

-- Behind a stage whose podium stops short of the district edge, the edge leaves this much room round the podium.
Walkways.BACK_CLEARANCE = 6

-- Lobby pieces taller than a stage floor + 1.5 keep this far from every FightOrigin (outside the fight camera's orbit).
Walkways.CAMERA_CLEARANCE = 37

function Walkways.clearOfFights(p: Vector3, margin: number?): boolean
	for _, def in Layout.ARENAS do
		local d = Vector3.new(p.X - def.origin.X, 0, p.Z - def.origin.Z).Magnitude
		if d < Walkways.CAMERA_CLEARANCE + (margin or 0) then
			return false
		end
	end
	return true
end

local function floor(m: Model)
	local R = Layout.DISTRICT_RADIUS
	Kit.cylinder(m, Vector3.new(0, -3, 0), 6, R * 2, M.Pavement, C.floor, { Name = "DistrictFloor" })
	-- a granite kerb ring where the decorated plaza (Lobby, r 30) meets the outer floor
	Kit.cylinder(m, Vector3.new(0, -0.285, 0), 0.6, 31.4 * 2, M.Granite, C.granite, { Name = "PlazaKerb", CastShadow = false })
end

local function balustrade(m: Model, from: number, to: number, water: boolean)
	local edge = Kit.model(m, if water then "Quay" else "Balustrade")
	local r = Layout.DISTRICT_RADIUS - 0.7
	local step = 4
	local n = math.max(1, math.ceil((to - from) / step))
	local span = (to - from) / n
	for i = 0, n - 1 do
		local a0, a1 = from + i * span, from + (i + 1) * span
		local p0, p1 = polar(a0, r), polar(a1, r)
		local mid = (p0 + p1) / 2
		local len = (p1 - p0).Magnitude + 0.05
		Kit.keepOut(p0, 1.6)
		Kit.keepOut(mid, 1.6)
		Kit.keepOut(p1, 1.6)
		-- alternate segments sit 0.012 apart so the overlapping joints never z-fight
		local cf = CFrame.lookAt(mid, p1) * CFrame.new(0, (i % 2) * 0.012, 0)
		if water then
			-- quay: granite coping and an iron rail on short posts
			Kit.block(edge, cf * CFrame.new(0, 0.2, 0), Vector3.new(1.4, 0.4, len), M.Granite, C.granite, { Name = "Coping" })
			Kit.rod(edge, (cf * CFrame.new(0, 2.3, -len / 2)).Position, (cf * CFrame.new(0, 2.3, len / 2)).Position, 0.18, M.Metal, C.iron, { Name = "QuayRail" })
			Kit.rod(edge, (cf * CFrame.new(0, 1.3, -len / 2)).Position, (cf * CFrame.new(0, 1.3, len / 2)).Position, 0.14, M.Metal, C.iron, { Name = "QuayRail" })
		else
			-- waist-high stone wall with a coping you can lean on
			Kit.block(edge, cf * CFrame.new(0, 0.6, 0), Vector3.new(1.1, 1.2, len), M.Limestone, C.stoneDark, { Name = "Wall" })
			Kit.block(edge, cf * CFrame.new(0, 1.35, 0), Vector3.new(1.5, 0.3, len), M.Limestone, C.stone, { Name = "Coping" })
		end
		local post = if i == n - 1 then p1 else p0
		if (i % 3 == 0 or i == n - 1) and Walkways.clearOfFights(post) then
			local p = post
			local pcf = CFrame.lookAt(p, p + p.Unit)
			if water then
				Kit.block(edge, pcf * CFrame.new(0, 1.2, 0), Vector3.new(0.3, 2.4, 0.3), M.Metal, C.iron, { Name = "RailPost" })
				Props.bollard(edge, p - p.Unit * 1.6)
			else
				Kit.block(edge, pcf * CFrame.new(0, 1.1, 0), Vector3.new(1.8, 2.2, 1.8), M.Limestone, C.stone, { Name = "Pier" })
				Kit.block(edge, pcf * CFrame.new(0, 2.35, 0), Vector3.new(2.2, 0.3, 2.2), M.Metal, C.bronze, { Name = "PierCap" })
				local globe = Kit.ball(edge, (pcf * CFrame.new(0, 3, 0)).Position, 1, M.Neon, C.warm, { Name = "PierLamp", CanCollide = false, CastShadow = false })
				if i % 6 == 0 then
					Kit.point(globe, C.warm, 1, 14, false)
				end
			end
		end
	end
end

local function edges(m: Model)
	-- each gap runs from the stage on its left to the stage on its right
	local byBearing = table.clone(Layout.ARENAS)
	table.sort(byBearing, function(a, b) return a.bearing < b.bearing end)
	for _, g in Walkways.GAPS do
		local left, right = byBearing[#byBearing], byBearing[1]
		for i, def in byBearing do
			if def.bearing < g.bearing then
				left = def
				right = byBearing[i % #byBearing + 1]
			end
		end
		local r = Layout.DISTRICT_RADIUS - 0.7
		-- a stage whose podium stops short of the edge keeps its back free (its trees and ruins grow there)
		local function halfAngle(def: Layout.ArenaDef): number
			if def.distance + Layout.STAGE_RADIUS < r then
				return Walkways.stageHalfAngle(r, def.distance, Layout.STAGE_RADIUS + Walkways.BACK_CLEARANCE)
			end
			return Walkways.stageHalfAngle(r, def.distance)
		end
		local from = left.bearing + halfAngle(left) + 2.5
		local to = right.bearing + (if right.bearing < left.bearing then 360 else 0) - halfAngle(right) - 2.5
		balustrade(m, from, to, g.water)
		Kit.step()
	end
end

-- Food stalls under string lights, tables with umbrellas (north-east, between the rooftop and the harbour).
local STALLS = {
	{ sign = "COUNTER HIT CAFE", stripe = Color3.fromRGB(200, 70, 60) },
	{ sign = "IRON BOWL NOODLES", stripe = Color3.fromRGB(230, 170, 60) },
	{ sign = "TOP-UP TEA", stripe = Color3.fromRGB(90, 150, 70) },
}

local function stall(parent: Instance, cf: CFrame, sign: string, stripe: Color3, rng: Random)
	local st = Kit.model(parent, "Stall")
	Kit.block(st, cf * CFrame.new(0, 0.15, 0.5), Vector3.new(9, 0.3, 6), M.WoodPlanks, Props.palette.woodDark)
	Kit.block(st, cf * CFrame.new(0, 1.7, -1.8), Vector3.new(8, 3.4, 1.4), M.WoodPlanks, Props.palette.woodLight, { Name = "Counter" })
	Kit.deco(st, cf * CFrame.new(0, 3.45, -1.8), Vector3.new(8.4, 0.15, 1.8), M.Wood, Props.palette.woodDark)
	for _, x in { -4, 4 } do
		Kit.block(st, cf * CFrame.new(x, 4, 2.6), Vector3.new(0.4, 8, 0.4), M.Wood, Props.palette.woodDark, { Name = "Post" })
		Kit.deco(st, cf * CFrame.new(x, 3.4, -2.2), Vector3.new(0.35, 6.8, 0.35), M.Wood, Props.palette.woodDark)
	end
	for k = 0, 6 do
		local x = -3.9 + k * 1.3
		Kit.deco(st, cf * CFrame.new(x, 7.3, 0.2) * CFrame.Angles(math.rad(14), 0, 0), Vector3.new(1.3, 0.12, 5.6), M.Fabric, if k % 2 == 0 then stripe else Color3.fromRGB(244, 236, 220), { Name = "Awning" })
	end
	for g = 1, 6 do
		Kit.ball(st, (cf * CFrame.new(-3.3 + g * 0.95, 3.85, -1.8)).Position, rng:NextNumber(0.55, 0.8), M.SmoothPlastic, Color3.fromHSV(rng:NextNumber(), 0.6, 0.95), { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
	end
	local board = Kit.deco(st, cf * CFrame.new(0, 8.6, -2.4), Vector3.new(7, 1.3, 0.25), M.WoodPlanks, Color3.fromRGB(60, 44, 34), { Name = "StallSign" })
	Kit.label(board, Enum.NormalId.Front, sign, { font = Enum.Font.GothamBlack, color = Color3.fromRGB(255, 230, 180), pps = 30, padding = 0.12, light = 0.6, brightness = 1.3 })
	local bulb = Kit.glow(st, cf * CFrame.new(0, 6.6, -0.6), Vector3.new(0.5, 0.5, 0.5), Color3.fromRGB(255, 200, 130))
	Kit.point(bulb, Color3.fromRGB(255, 196, 130), 1.1, 12, false)
end

local function market(m: Model, g: number, rng: Random)
	local mk = Kit.model(m, "NightMarket")
	for i, s in STALLS do
		local b = g + (i - 2) * 6
		local pos = polar(b, 92)
		stall(mk, Kit.facing(pos, -pos.Unit), s.sign, s.stripe, rng)
		Kit.keepOut(pos, 6)
	end
	for _, off in { -5, 5 } do
		local pos = polar(g + off, 84)
		Kit.keepOut(pos, 3)
		local cf = Kit.facing(pos, -pos.Unit)
		Kit.cylinder(mk, pos + Vector3.new(0, 1.6, 0), 0.2, 3, M.WoodPlanks, Props.palette.woodLight, { Name = "TableTop" })
		Kit.cylinder(mk, pos + Vector3.new(0, 0.8, 0), 1.6, 0.3, M.Metal, C.iron, { CanCollide = false })
		Kit.cylinder(mk, pos + Vector3.new(0, 4, 0), 7, 0.18, M.Metal, C.iron, { CanCollide = false })
		Kit.cylinder(mk, pos + Vector3.new(0, 7.3, 0), 0.3, 5.4, M.Fabric, if off < 0 then Color3.fromRGB(196, 72, 64) else Color3.fromRGB(240, 226, 200), { Name = "Umbrella", CanCollide = false })
		for _, s in { -1, 1 } do
			Kit.cylinder(mk, (cf * CFrame.new(s * 1.9, 0.75, 0)).Position, 1.5, 1.1, M.Wood, Props.palette.woodDark, { Name = "Stool" })
		end
	end
	local a, b = polar(g - 9, 97, 0), polar(g + 9, 97, 0)
	for _, p in { a, b } do
		Kit.cylinder(mk, p + Vector3.new(0, 5, 0), 10, 0.35, M.Metal, C.iron, { CanCollide = false })
		Kit.keepOut(p, 1)
	end
	Props.stringLights(mk, a + Vector3.new(0, 9.8, 0), polar(g, 86, 9.4), 7, Color3.fromRGB(255, 214, 140), 1.2, 3)
	Props.stringLights(mk, polar(g, 86, 9.4), b + Vector3.new(0, 9.8, 0), 7, Color3.fromRGB(255, 214, 140), 1.2, 3)
	Kit.cylinder(mk, polar(g, 86, 4.8), 9.6, 0.35, M.Metal, C.iron, { CanCollide = false })
end

-- Viewing deck over the sea: telescopes, benches facing the water, a flag.
local function lookout(m: Model, g: number)
	local lk = Kit.model(m, "SeaLookout")
	for _, off in { -7, 7 } do
		local pos = polar(g + off, 94)
		local cf = Kit.facing(pos, pos.Unit)
		Kit.keepOut(pos, 1.5)
		Kit.cylinder(lk, pos + Vector3.new(0, 1.2, 0), 2.4, 0.4, M.Metal, C.iron, { Name = "ScopePost" })
		Kit.block(lk, cf * CFrame.new(0, 2.7, 0) * CFrame.Angles(math.rad(8), 0, 0), Vector3.new(1, 1, 2.2), M.Metal, Color3.fromRGB(40, 110, 160), { Name = "Telescope", CanCollide = false })
	end
	for _, off in { -8, 0, 8 } do
		local pos = polar(g + off, 90)
		Props.bench(lk, Kit.facing(pos, pos.Unit))
		Kit.keepOut(pos, 3)
	end
	local fp = polar(g, 96.5)
	Kit.keepOut(fp, 1)
	Kit.cylinder(lk, fp + Vector3.new(0, 7, 0), 14, 0.3, M.Metal, Color3.fromRGB(220, 222, 228), { Name = "FlagPole" })
	Props.banner(lk, fp + Vector3.new(0, 13.6, 0) + Vector3.new(0, 0, 0), fp.Unit:Cross(Vector3.yAxis), 4, 2.6, Color3.fromRGB(255, 96, 24), "FIGHTINGLAB", Color3.new(1, 1, 1))
end

-- "EMBER SQUARE / FIGHT DISTRICT" wall facing the plaza (behind the spawn court: the photo spot when you turn round).
local function welcome(m: Model, g: number, rng: Random)
	local s = Kit.model(m, "WelcomeSign")
	local pos = polar(g, 88)
	local cf = Kit.facing(pos, -pos.Unit)
	for sx = -16, 16, 4 do
		Kit.keepOut((cf * CFrame.new(sx, 0, 0)).Position, 3.2)
	end
	for _, sx in { -20.5, 20.5 } do
		Kit.keepOut((cf * CFrame.new(sx, 0, 0)).Position, 3)
	end
	-- and nothing grows in front of it: the wall is seen from the plaza down the walkway between the two stages
	for sx = -16, 16, 8 do
		for _, sz in { -6, -12, -18 } do
			Kit.keepOut((cf * CFrame.new(sx, 0, sz)).Position, 4.5)
		end
	end
	Kit.block(s, cf * CFrame.new(0, 0.5, 0), Vector3.new(36, 1, 5), M.Granite, C.granite, { Name = "Plinth" })
	local wall = Kit.block(s, cf * CFrame.new(0, 4.4, 0.6), Vector3.new(32, 6.8, 2.2), M.Limestone, C.stone, { Name = "NameWall" })
	Kit.deco(s, cf * CFrame.new(0, 7.95, 0.6), Vector3.new(32.6, 0.3, 2.6), M.Metal, C.bronze, { Name = "Cap" })
	Kit.glow(s, cf * CFrame.new(0, 1.2, -0.55), Vector3.new(31, 0.14, 0.1), C.ember, { Name = "Trim" })
	Kit.label(wall, Enum.NormalId.Front, "EMBER SQUARE", {
		font = Enum.Font.GothamBlack,
		color = Color3.fromRGB(70, 46, 30),
		pps = 20,
		padding = 0.06,
		light = 1,
		brightness = 1,
		name = "NameText",
	})
	local sub = Kit.deco(s, cf * CFrame.new(0, 9.1, 0.6), Vector3.new(20, 1.8, 0.4), M.Metal, Color3.fromRGB(40, 34, 30), { Name = "SubPlate" })
	Kit.label(sub, Enum.NormalId.Front, "FIGHTINGLAB  FIGHT DISTRICT", { font = Enum.Font.GothamBold, color = Color3.fromRGB(255, 214, 150), pps = 30, padding = 0.12, brightness = 1.4 })
	for _, sx in { -14, 0, 14 } do
		local cup = Kit.deco(s, cf * CFrame.new(sx, 1.2, -2.4) * CFrame.Angles(math.rad(115), 0, 0), Vector3.new(0.8, 0.8, 0.5), M.Metal, C.iron, { Name = "Uplight" })
		Kit.spot(cup, Enum.NormalId.Front, Color3.fromRGB(255, 220, 180), 1.6, 16, 60, false)
	end
	Props.flowers(s, (cf * CFrame.new(-10, 1, -2)).Position, 3, 12, rng)
	Props.flowers(s, (cf * CFrame.new(10, 1, -2)).Position, 3, 12, rng)
	for _, sx in { -20.5, 20.5 } do
		Props.planter(s, cf * CFrame.new(sx, 0, 0), Vector3.new(4, 1.2, 4), M.Brick, Color3.fromRGB(176, 104, 76), rng, false)
	end
end

-- Sand, palms, loungers and a beach umbrella looking out over the bay (palms stay on the seaward side, well
-- clear of the neighbouring stages' fight cameras).
local function beach(m: Model, g: number, rng: Random)
	local bg = Kit.model(m, "BeachGarden")
	local c = polar(g, 88)
	-- top 0.045: clear of the district floor (0) and of the jungle floor (0.02) that reaches close by
	Kit.cylinder(bg, c + Vector3.new(0, -0.175, 0), 0.44, 24, M.Sand, C.sand, { Name = "SandBed", CastShadow = false })
	Kit.keepOut(c, 12.5)
	for i, pb in { { g - 6, 93 }, { g + 6, 94 }, { g - 1, 96.5 } } do
		local p = polar(pb[1], pb[2])
		Props.palm(bg, Vector3.new(p.X, 0, p.Z), 0.95 + i * 0.07, rng)
		Kit.keepOut(p, 2)
	end
	local out = c.Unit
	local side = Vector3.new(-out.Z, 0, out.X)
	for _, s in { -3, 3 } do
		local p = c + side * s + out * 4
		local cf = Kit.facing(Vector3.new(p.X, 0, p.Z), out)
		Kit.block(bg, cf * CFrame.new(0, 0.7, 0), Vector3.new(2, 0.3, 5), M.Wood, Props.palette.woodLight, { Name = "Lounger" })
		Kit.block(bg, cf * CFrame.new(0, 1.4, 2.2) * CFrame.Angles(math.rad(-35), 0, 0), Vector3.new(2, 0.3, 2), M.Wood, Props.palette.woodLight, { Name = "LoungerBack", CanCollide = false })
		Kit.deco(bg, cf * CFrame.new(0, 0.35, 0), Vector3.new(1.8, 0.7, 4.6), M.Wood, Props.palette.woodDark)
	end
	-- the umbrella shades both loungers (clear of the palms behind them)
	local up = c + out * 4
	Kit.cylinder(bg, Vector3.new(up.X, 3.5, up.Z), 7, 0.25, M.Wood, Props.palette.woodLight, { CanCollide = false })
	Kit.cylinder(bg, Vector3.new(up.X, 6.9, up.Z), 0.4, 6.4, M.Fabric, Color3.fromRGB(40, 150, 170), { Name = "Umbrella", CanCollide = false })
end

-- Cherry trees, stone lanterns, a koi pond with stepping stones and a bench.
local function garden(m: Model, g: number, rng: Random)
	local gd = Kit.model(m, "LanternGarden")
	local c = polar(g, 82)
	Kit.keepOut(c, 13)
	Kit.cylinder(gd, c + Vector3.new(0, -0.2, 0), 0.44, 24, M.Grass, Color3.fromRGB(92, 132, 64), { Name = "Lawn", CastShadow = false })
	Kit.cylinder(gd, c + Vector3.new(0, -0.1, 0), 0.3, 11, M.Slate, Color3.fromRGB(56, 74, 80), { Name = "PondBed", CastShadow = false })
	Kit.cylinder(gd, c + Vector3.new(0, 0.12, 0), 0.06, 10, M.Glass, Color3.fromRGB(70, 150, 170), { Name = "PondWater", Transparency = 0.35, CanCollide = false, CastShadow = false })
	for k = 1, 5 do
		local a = math.rad(k * 72 + 10)
		local p = c + Vector3.new(math.cos(a) * 6.4, 0.18, math.sin(a) * 6.4)
		Kit.cylinder(gd, p, 0.36, 1.8, M.Slate, Color3.fromRGB(120, 122, 126), { Name = "SteppingStone" })
	end
	local out = c.Unit
	local side = Vector3.new(-out.Z, 0, out.X)
	for _, s in { -1, 1 } do
		local p = c + side * s * 9 + out * 2
		local blossom = { Color3.fromRGB(250, 186, 206), Color3.fromRGB(244, 160, 190), Color3.fromRGB(255, 210, 222) }
		Props.tree(gd, Vector3.new(p.X, 0, p.Z), rng:NextNumber(1, 1.2), rng, blossom)
		local q = c + side * s * 5 - out * 7
		Props.lantern(gd, Vector3.new(q.X, 0, q.Z), Color3.fromRGB(255, 196, 120), M.Granite, Color3.fromRGB(150, 146, 136), 3.6)
	end
	local bp = c - out * 10
	Props.bench(gd, Kit.facing(Vector3.new(bp.X, 0, bp.Z), out))
end

function Walkways.build(parent: Instance?): Model
	local m = Kit.model(nil, "Walkways")
	floor(m)
	edges(m)
	local rng = Kit.rng(19)
	for _, g in Walkways.GAPS do
		if g.kind == "Market" then
			market(m, g.bearing, rng)
		elseif g.kind == "Lookout" then
			lookout(m, g.bearing)
		elseif g.kind == "Welcome" then
			welcome(m, g.bearing, rng)
		elseif g.kind == "Beach" then
			beach(m, g.bearing, rng)
		elseif g.kind == "Garden" then
			garden(m, g.bearing, rng)
		end
		Kit.step()
	end
	if parent then
		m.Parent = parent
	end
	return m
end

return Walkways
