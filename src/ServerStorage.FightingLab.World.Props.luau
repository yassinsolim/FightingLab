--!strict
-- World.Props: reusable, textured set dressing built from primitives (lamps, trees, benches, planters, banners,
-- string lights, crates...). All decoration is anchored; only things people stand on collide.
local Kit = require(script.Parent.Kit)

local Props = {}

local M = Enum.Material

Props.palette = {
	ironDark = Color3.fromRGB(46, 48, 54),
	bronze = Color3.fromRGB(168, 124, 64),
	brass = Color3.fromRGB(196, 160, 86),
	warmLight = Color3.fromRGB(255, 196, 128),
	bark = Color3.fromRGB(104, 78, 56),
	barkDark = Color3.fromRGB(74, 56, 42),
	leafA = Color3.fromRGB(86, 132, 58),
	leafB = Color3.fromRGB(112, 150, 66),
	leafC = Color3.fromRGB(70, 112, 60),
	woodLight = Color3.fromRGB(176, 132, 92),
	woodDark = Color3.fromRGB(110, 78, 54),
	stone = Color3.fromRGB(176, 166, 150),
	soil = Color3.fromRGB(84, 64, 46),
}
local P = Props.palette

-- Classic street lamp: fluted pole, arm, lantern with a warm light. `dir` is the side the lantern hangs towards.
function Props.streetLamp(parent: Instance, pos: Vector3, dir: Vector3?, color: Color3?, height: number?): Model
	local m = Kit.model(parent, "StreetLamp")
	local h = height or 12
	local light = color or P.warmLight
	local d = if dir and dir.Magnitude > 0 then Vector3.new(dir.X, 0, dir.Z).Unit else Vector3.xAxis
	Kit.cylinder(m, pos + Vector3.new(0, 0.5, 0), 1, 1.6, M.Metal, P.ironDark)
	Kit.cylinder(m, pos + Vector3.new(0, 1.4, 0), 0.8, 1.1, M.Metal, P.bronze)
	Kit.cylinder(m, pos + Vector3.new(0, h / 2, 0), h, 0.5, M.Metal, P.ironDark)
	local armEnd = pos + Vector3.new(0, h - 0.4, 0) + d * 2.2
	Kit.strut(m, pos + Vector3.new(0, h - 0.4, 0), armEnd, 0.25, 0.25, M.Metal, P.ironDark)
	Kit.ball(m, pos + Vector3.new(0, h + 0.15, 0), 0.7, M.Metal, P.bronze, { CanCollide = false, CastShadow = false })
	local head = Kit.deco(m, CFrame.new(armEnd - Vector3.new(0, 0.9, 0)), Vector3.new(1.1, 1.3, 1.1), M.Glass, Color3.fromRGB(255, 226, 170), {
		Name = "Lantern",
		Transparency = 0.25,
	})
	Kit.deco(m, CFrame.new(armEnd - Vector3.new(0, 0.18, 0)), Vector3.new(1.5, 0.3, 1.5), M.Metal, P.ironDark)
	Kit.glow(m, CFrame.new(armEnd - Vector3.new(0, 0.95, 0)), Vector3.new(0.55, 0.8, 0.55), light)
	Kit.point(head, light, 1.6, 20, false)
	return m
end

-- Modern pole light (arenas): slim pole + downward spotlight head.
function Props.poleLight(parent: Instance, pos: Vector3, aim: Vector3, color: Color3, height: number, brightness: number?): Model
	local m = Kit.model(parent, "PoleLight")
	Kit.cylinder(m, pos + Vector3.new(0, height / 2, 0), height, 0.45, M.Metal, Color3.fromRGB(70, 74, 82))
	local headPos = pos + Vector3.new(0, height, 0)
	local cf = CFrame.lookAt(headPos, aim)
	local head = Kit.deco(m, cf, Vector3.new(1.6, 0.8, 1.2), M.Metal, Color3.fromRGB(40, 42, 48), { Name = "Head" })
	Kit.glow(m, cf * CFrame.new(0, 0, -0.62), Vector3.new(1.3, 0.55, 0.05), color)
	Kit.spot(head, Enum.NormalId.Front, color, brightness or 2.2, 60, 50, false)
	return m
end

-- Broadleaf tree: trunk with a slight lean and three to five foliage blobs.
function Props.tree(parent: Instance, pos: Vector3, scale: number, rng: Random, leaf: { Color3 }?): Model
	local m = Kit.model(parent, "Tree")
	local s = scale
	local lean = Vector3.new(rng:NextNumber(-0.6, 0.6), 0, rng:NextNumber(-0.6, 0.6)) * s
	local top = pos + Vector3.new(0, 9 * s, 0) + lean
	Kit.rod(m, pos - Vector3.new(0, 0.5, 0), top, 1.3 * s, M.Wood, P.bark, { CanCollide = true })
	Kit.rod(m, pos + Vector3.new(0, 6 * s, 0) + lean * 0.6, pos + Vector3.new(2.4 * s, 9.5 * s, 0.6 * s), 0.6 * s, M.Wood, P.bark, { CanCollide = false })
	local colors = leaf or { P.leafA, P.leafB, P.leafC }
	local n = rng:NextInteger(3, 5)
	for i = 1, n do
		local off = Vector3.new(rng:NextNumber(-2.8, 2.8), rng:NextNumber(-0.8, 2.6), rng:NextNumber(-2.8, 2.8)) * s
		local size = Vector3.new(rng:NextNumber(5.5, 8), rng:NextNumber(4.2, 6), rng:NextNumber(5.5, 8)) * s
		local cf = CFrame.new(top + off) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
		Kit.blob(m, cf, size, M.LeafyGrass, colors[(i - 1) % #colors + 1], { CastShadow = true })
	end
	return m
end

-- Palm: curved segmented trunk and drooping fronds.
function Props.palm(parent: Instance, pos: Vector3, scale: number, rng: Random): Model
	local m = Kit.model(parent, "Palm")
	local s = scale
	local bend = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)).Unit * 2.6 * s
	local prev = pos - Vector3.new(0, 0.5, 0)
	local segments = 5
	for i = 1, segments do
		local t = i / segments
		local nextPos = pos + Vector3.new(0, 13 * s * t, 0) + bend * (t * t)
		Kit.rod(m, prev, nextPos, (1.25 - 0.35 * t) * s, M.Wood, if i % 2 == 0 then P.bark else P.barkDark, { CanCollide = i == 1 })
		prev = nextPos
	end
	local crown = prev
	Kit.ball(m, crown, 1.4 * s, M.Wood, P.barkDark, { CanCollide = false })
	for i = 1, 7 do
		local a = i / 7 * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local tip = crown + dir * 6.5 * s + Vector3.new(0, -2.4 * s, 0)
		local mid = crown + dir * 3.4 * s + Vector3.new(0, 0.6 * s, 0)
		Kit.strut(m, crown, mid, 1.6 * s, 0.12, M.LeafyGrass, P.leafB, { CanCollide = false, CanQuery = false, CanTouch = false })
		Kit.strut(m, mid, tip, 1.3 * s, 0.1, M.LeafyGrass, P.leafA, { CanCollide = false, CanQuery = false, CanTouch = false })
	end
	return m
end

-- Pine from stacked square pyramids (four corner wedges each); optional snow on the upper tiers.
function Props.pine(parent: Instance, pos: Vector3, scale: number, rng: Random, snowy: boolean?): Model
	local m = Kit.model(parent, "Pine")
	local s = scale * rng:NextNumber(0.85, 1.15)
	local trunkH = 2.6 * s
	Kit.cylinder(m, pos + Vector3.new(0, trunkH / 2 - 0.4, 0), trunkH + 0.8, 1 * s, M.Wood, P.barkDark)
	-- four narrowing tiers of corner-wedge pyramids give a slim fir silhouette; snowy firs get a white crown
	local tiers = { { 8.4, 5 }, { 6.8, 4.6 }, { 5.0, 4.2 }, { 3.2, 3.8 } }
	local y = trunkH
	local yaw = rng:NextNumber(0, math.pi / 2)
	local green = Color3.fromRGB(40, 76, 52):Lerp(Color3.fromRGB(58, 96, 60), rng:NextNumber())
	for i, tier in tiers do
		local w, h = tier[1] * s, tier[2] * s
		local centre = pos + Vector3.new(0, y + h / 2, 0)
		local snowTier = snowy and i == #tiers
		for q = 0, 3 do
			local rot = CFrame.Angles(0, yaw + q * math.pi / 2, 0)
			local cf = CFrame.new(centre) * rot * CFrame.new(w / 4, 0, w / 4) * CFrame.Angles(0, math.pi, 0)
			Kit.cornerWedge(m, cf, Vector3.new(w / 2, h, w / 2), if snowTier then M.Snow else M.Grass, if snowTier then Color3.fromRGB(214, 226, 238) else Kit.shade(green, 1 + (i - 1) * 0.06), {
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
			})
		end
		y += h * 0.55
	end
	return m
end

function Props.bush(parent: Instance, pos: Vector3, size: Vector3, color: Color3?, rng: Random?): Part
	local yaw = if rng then rng:NextNumber(0, math.pi) else 0
	return Kit.blob(parent, CFrame.new(pos) * CFrame.Angles(0, yaw, 0), size, M.LeafyGrass, color or P.leafC, { CastShadow = true })
end

function Props.flowers(parent: Instance, centre: Vector3, radius: number, count: number, rng: Random, colors: { Color3 }?)
	local palette = colors or { Color3.fromRGB(255, 120, 96), Color3.fromRGB(255, 210, 90), Color3.fromRGB(240, 120, 200), Color3.fromRGB(255, 250, 240) }
	for _ = 1, count do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = math.sqrt(rng:NextNumber()) * radius
		local p = centre + Vector3.new(math.cos(a) * r, rng:NextNumber(0.1, 0.5), math.sin(a) * r)
		Kit.ball(parent, p, rng:NextNumber(0.35, 0.6), M.SmoothPlastic, palette[rng:NextInteger(1, #palette)], {
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
		})
	end
end

-- Park bench (cf at seat centre on the ground, facing -Z = where sitters look).
function Props.bench(parent: Instance, cf: CFrame, woodColor: Color3?): Model
	local m = Kit.model(parent, "Bench")
	local wood = woodColor or P.woodLight
	Kit.block(m, cf * CFrame.new(0, 1.55, 0), Vector3.new(5.6, 0.25, 1.6), M.WoodPlanks, wood)
	Kit.deco(m, cf * CFrame.new(0, 2.6, 0.75) * CFrame.Angles(math.rad(-12), 0, 0), Vector3.new(5.6, 1.2, 0.2), M.WoodPlanks, wood)
	for _, x in { -2.4, 2.4 } do
		Kit.deco(m, cf * CFrame.new(x, 0.75, 0.05), Vector3.new(0.3, 1.5, 1.5), M.Metal, P.ironDark)
		Kit.deco(m, cf * CFrame.new(x, 2.4, 0.78), Vector3.new(0.25, 1.8, 0.2), M.Metal, P.ironDark)
	end
	return m
end

-- Raised planter with soil, a small tree or bushes and flowers.
function Props.planter(parent: Instance, cf: CFrame, size: Vector3, material: Enum.Material, color: Color3, rng: Random, withTree: boolean?): Model
	local m = Kit.model(parent, "Planter")
	local h = size.Y
	Kit.block(m, cf * CFrame.new(0, h / 2, 0), size, material, color)
	Kit.block(m, cf * CFrame.new(0, h + 0.1, 0), Vector3.new(size.X + 0.5, 0.2, size.Z + 0.5), M.Granite, Kit.shade(color, 0.8))
	Kit.deco(m, cf * CFrame.new(0, h + 0.12, 0), Vector3.new(size.X - 0.8, 0.22, size.Z - 0.8), M.Ground, P.soil, { CastShadow = false })
	local top = (cf * CFrame.new(0, h + 0.2, 0)).Position
	if withTree then
		Props.tree(m, top, rng:NextNumber(0.75, 0.95), rng)
	else
		for _ = 1, 3 do
			Props.bush(m, top + Vector3.new(rng:NextNumber(-size.X / 3, size.X / 3), 0.7, rng:NextNumber(-size.Z / 3, size.Z / 3)), Vector3.new(2.6, 2, 2.6), nil, rng)
		end
	end
	Props.flowers(m, top, math.min(size.X, size.Z) * 0.42, 10, rng)
	return m
end

-- Hanging fabric banner below `top`, facing `facing` (both faces show the colour; optional text on both faces).
function Props.banner(parent: Instance, top: Vector3, facing: Vector3, width: number, height: number, color: Color3, text: string?, textColor: Color3?): Part
	local cf = Kit.facing(top - Vector3.new(0, height / 2, 0), facing)
	local cloth = Kit.deco(parent, cf, Vector3.new(width, height, 0.12), M.Fabric, color, { Name = "Banner", CastShadow = true })
	Kit.deco(parent, cf * CFrame.new(0, height / 2 + 0.1, 0), Vector3.new(width + 0.4, 0.2, 0.2), M.Metal, P.brass)
	Kit.deco(parent, cf * CFrame.new(0, -height / 2 - 0.06, 0), Vector3.new(width, 0.14, 0.16), M.Fabric, Kit.shade(color, 0.6))
	if text then
		-- tall banners stack one letter per line so long words never wrap mid-word
		local shown = if height > width * 1.6 then table.concat(string.split(text, ""), "\n") else text
		for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
			Kit.label(cloth, face, shown, {
				font = Enum.Font.GothamBlack,
				color = textColor or Color3.new(1, 1, 1),
				pps = 24,
				padding = 0.12,
				light = 1,
				brightness = 1,
			})
		end
	end
	return cloth
end

-- Sagging string of bulbs between two points.
function Props.stringLights(parent: Instance, a: Vector3, b: Vector3, count: number, color: Color3, sag: number?, lightEvery: number?)
	local dip = sag or 1.5
	local prev = a
	for i = 1, count do
		local t = i / (count + 1)
		local p = a:Lerp(b, t) - Vector3.new(0, dip * 4 * t * (1 - t), 0)
		Kit.rod(parent, prev, p, 0.06, M.Metal, Color3.fromRGB(30, 30, 30), { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
		local bulb = Kit.ball(parent, p - Vector3.new(0, 0.2, 0), 0.38, M.Neon, color, { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
		if lightEvery and i % lightEvery == 0 then
			Kit.point(bulb, color, 0.8, 9, false)
		end
		prev = p
	end
	Kit.rod(parent, prev, b, 0.06, M.Metal, Color3.fromRGB(30, 30, 30), { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
end

-- Sagging line of small fabric pennants between two points.
function Props.bunting(parent: Instance, a: Vector3, b: Vector3, count: number, colors: { Color3 }, sag: number?)
	local dip = sag or 1.2
	local dir = (b - a).Unit
	local across = Vector3.new(-dir.Z, 0, dir.X)
	local prev = a
	for i = 1, count do
		local t = i / (count + 1)
		local p = a:Lerp(b, t) - Vector3.new(0, dip * 4 * t * (1 - t), 0)
		Kit.rod(parent, prev, p, 0.05, M.Fabric, Color3.fromRGB(230, 226, 214), { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
		local cf = CFrame.lookAt(p, p + across) * CFrame.new(0, -0.5, 0)
		Kit.deco(parent, cf, Vector3.new(0.75, 0.95, 0.05), M.Fabric, colors[(i - 1) % #colors + 1], { Name = "Pennant" })
		prev = p
	end
	Kit.rod(parent, prev, b, 0.05, M.Fabric, Color3.fromRGB(230, 226, 214), { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
end

function Props.crate(parent: Instance, cf: CFrame, size: number, color: Color3?): Part
	local c = Kit.block(parent, cf * CFrame.new(0, size / 2, 0), Vector3.new(size, size, size), M.WoodPlanks, color or P.woodLight)
	Kit.deco(parent, cf * CFrame.new(0, size / 2, 0), Vector3.new(size + 0.06, size * 0.18, size + 0.06), M.Wood, P.woodDark)
	return c
end

function Props.barrel(parent: Instance, pos: Vector3, color: Color3?): Part
	local b = Kit.cylinder(parent, pos + Vector3.new(0, 1.5, 0), 3, 2.2, M.Wood, color or P.woodDark)
	Kit.cylinder(parent, pos + Vector3.new(0, 0.7, 0), 0.22, 2.28, M.Metal, P.ironDark, { CanCollide = false, CanQuery = false, CanTouch = false })
	Kit.cylinder(parent, pos + Vector3.new(0, 2.3, 0), 0.22, 2.28, M.Metal, P.ironDark, { CanCollide = false, CanQuery = false, CanTouch = false })
	return b
end

function Props.rock(parent: Instance, pos: Vector3, size: Vector3, rng: Random, color: Color3?, material: Enum.Material?): Part
	local cf = CFrame.new(pos) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, math.pi), rng:NextNumber(-0.3, 0.3))
	return Kit.blob(parent, cf, size, material or M.Rock, color or Color3.fromRGB(128, 120, 110), { CastShadow = true })
end

-- Small standing lantern (stone/wood/metal post with a glowing box).
function Props.lantern(parent: Instance, pos: Vector3, color: Color3, material: Enum.Material?, baseColor: Color3?, height: number?): Model
	local m = Kit.model(parent, "Lantern")
	local h = height or 3.2
	local mat = material or M.Granite
	local c = baseColor or P.stone
	Kit.block(m, CFrame.new(pos + Vector3.new(0, h / 2 - 0.4, 0)), Vector3.new(0.9, h - 0.8, 0.9), mat, c)
	Kit.block(m, CFrame.new(pos + Vector3.new(0, 0.2, 0)), Vector3.new(1.5, 0.4, 1.5), mat, Kit.shade(c, 0.85))
	local box = Kit.deco(m, CFrame.new(pos + Vector3.new(0, h - 0.1, 0)), Vector3.new(1.4, 1.2, 1.4), mat, c)
	Kit.glow(m, CFrame.new(pos + Vector3.new(0, h - 0.1, 0)), Vector3.new(1.46, 0.6, 0.9), color)
	Kit.glow(m, CFrame.new(pos + Vector3.new(0, h - 0.1, 0)), Vector3.new(0.9, 0.6, 1.46), color)
	Kit.deco(m, CFrame.new(pos + Vector3.new(0, h + 0.65, 0)), Vector3.new(1.9, 0.3, 1.9), mat, Kit.shade(c, 0.8))
	Kit.point(box, color, 1.2, 12, false)
	return m
end

-- City pieces --------------------------------------------------------------------------------------------------

-- Lit windows drawn on one face of a building body (SurfaceGui, no extra parts): floor bands plus a scatter of
-- glowing windows. `face` is a NormalId; the face size comes from the part.
export type WindowOpts = {
	floorHeight: number?,
	bayWidth: number?,
	lit: number?, -- chance a window is lit
	litColors: { Color3 }?,
	band: Color3?,
	bandTransparency: number?,
	pps: number?,
	glass: Color3?, -- unlit window tint (nil = leave the body showing)
	glassTransparency: number?,
	skipBottom: number?, -- studs at the bottom left without windows (shopfront)
}

function Props.windows(part: BasePart, face: Enum.NormalId, rng: Random, o: WindowOpts?): SurfaceGui
	local opts: WindowOpts = o or {}
	local size = part.Size
	local w, h
	if face == Enum.NormalId.Front or face == Enum.NormalId.Back then
		w, h = size.X, size.Y
	elseif face == Enum.NormalId.Left or face == Enum.NormalId.Right then
		w, h = size.Z, size.Y
	else
		w, h = size.X, size.Z
	end
	local pps = opts.pps or 6
	local g = Instance.new("SurfaceGui")
	g.Name = "Windows" .. face.Name
	g.Face = face
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = pps
	g.LightInfluence = 0
	g.Brightness = 1.3
	g.MaxDistance = 1500
	g.ResetOnSpawn = false
	g.ClipsDescendants = true
	local fh = opts.floorHeight or 6
	local bay = opts.bayWidth or 4
	local skip = opts.skipBottom or 0
	local floors = math.floor((h - skip) / fh)
	local bays = math.max(1, math.floor((w - 1) / bay))
	local colors = opts.litColors or { Color3.fromRGB(255, 214, 150), Color3.fromRGB(255, 196, 120), Color3.fromRGB(200, 228, 255) }
	local litChance = opts.lit or 0.3
	local px = function(v: number): number return math.floor(v * pps + 0.5) end
	local marginX = (w - bays * bay) / 2
	-- canvas origin is the top-left of the face; floor f (from the top) spans y = (f - 1) * fh .. f * fh
	for f = 1, floors do
		local y0 = (f - 1) * fh
		if opts.band then
			local band = Instance.new("Frame")
			band.BorderSizePixel = 0
			band.BackgroundColor3 = opts.band
			band.BackgroundTransparency = opts.bandTransparency or 0
			band.Position = UDim2.fromOffset(0, px(y0 + fh - 0.7))
			band.Size = UDim2.fromOffset(px(w), math.max(2, px(0.7)))
			band.Parent = g
		end
		for b = 1, bays do
			local x = marginX + (b - 1) * bay + 0.5
			local isLit = rng:NextNumber() < litChance
			if isLit or opts.glass then
				local win = Instance.new("Frame")
				win.BorderSizePixel = 0
				win.Position = UDim2.fromOffset(px(x), px(y0 + 1.1))
				win.Size = UDim2.fromOffset(px(bay - 1), px(fh - 2.4))
				if isLit then
					win.BackgroundColor3 = colors[rng:NextInteger(1, #colors)]
					win.BackgroundTransparency = rng:NextNumber(0, 0.25)
				else
					win.BackgroundColor3 = opts.glass :: Color3
					win.BackgroundTransparency = opts.glassTransparency or 0.15
				end
				win.Parent = g
			end
		end
	end
	g.Parent = part
	Kit.stats.guis += 1
	return g
end

-- Neon sign: dark backing with a lit text face on both sides and glowing top/bottom bars.
function Props.neonSign(parent: Instance, cf: CFrame, w: number, h: number, text: string, color: Color3, font: Enum.Font?, light: boolean?): BasePart
	local back = Kit.deco(parent, cf, Vector3.new(w, h, 0.6), M.Metal, Color3.fromRGB(24, 24, 30), { Name = "NeonSign" })
	Kit.glow(parent, cf * CFrame.new(0, h / 2 + 0.15, 0), Vector3.new(w + 0.3, 0.3, 0.7), color)
	Kit.glow(parent, cf * CFrame.new(0, -h / 2 - 0.15, 0), Vector3.new(w + 0.3, 0.3, 0.7), color)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		Kit.label(back, face, text, {
			font = font or Enum.Font.Sarpanch,
			color = Color3.new(1, 1, 1):Lerp(color, 0.4),
			stroke = color,
			strokeTransparency = 0,
			pps = 24,
			padding = 0.08,
			brightness = 2.2,
		})
	end
	if light ~= false then
		Kit.point(back, color, 1.4, 20, false)
	end
	return back
end

export type TowerOpts = {
	material: Enum.Material?,
	color: Color3?,
	neon: Color3?,
	faces: { Enum.NormalId }?, -- faces that get windows (default all four)
	lit: number?,
	crown: boolean?,
	mast: boolean?,
	glass: Color3?,
}

-- Skyline tower: one body part with window SurfaceGuis, a cornice, a neon crown outline and optional mast/penthouse.
function Props.tower(parent: Instance, base: Vector3, w: number, d: number, h: number, rng: Random, o: TowerOpts?): Model
	local opts: TowerOpts = o or {}
	local t = Kit.model(parent, "Tower")
	local body = Kit.block(t, CFrame.new(base + Vector3.new(0, h / 2, 0)), Vector3.new(w, h, d), opts.material or M.Concrete, opts.color or Color3.fromRGB(70, 76, 92), { Name = "Body", CanCollide = false })
	for _, face in opts.faces or { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right } do
		Props.windows(body, face, rng, { lit = opts.lit or 0.32, band = Kit.shade(opts.color or Color3.fromRGB(70, 76, 92), 1.35), glass = opts.glass, glassTransparency = 0.05, skipBottom = 0 })
	end
	local top = base + Vector3.new(0, h, 0)
	Kit.deco(t, CFrame.new(top + Vector3.new(0, 0.3, 0)), Vector3.new(w + 0.6, 0.6, d + 0.6), M.Concrete, Kit.shade(opts.color or Color3.fromRGB(70, 76, 92), 0.8), { Name = "Cornice" })
	local neon = opts.neon
	if neon then
		for _, e in { { 0, d / 2 + 0.3, w + 0.6, 0.3 }, { 0, -d / 2 - 0.3, w + 0.6, 0.3 } } do
			Kit.glow(t, CFrame.new(top + Vector3.new(e[1], 0.75, e[2])), Vector3.new(e[3], e[4], e[4]), neon, { Name = "CrownNeon" })
		end
		for _, sx in { -1, 1 } do
			Kit.glow(t, CFrame.new(top + Vector3.new(sx * (w / 2 + 0.3), 0.75, 0)), Vector3.new(0.3, 0.3, d + 0.6), neon, { Name = "CrownNeon" })
		end
	end
	if opts.crown ~= false and rng:NextNumber() < 0.55 then
		Kit.block(t, CFrame.new(top + Vector3.new(w * 0.12, 2.6, -d * 0.1)), Vector3.new(w * 0.45, 4.6, d * 0.45), M.Metal, Color3.fromRGB(120, 126, 136), { Name = "Penthouse", CanCollide = false })
	end
	if opts.mast or (opts.mast == nil and rng:NextNumber() < 0.45) then
		local mast = top + Vector3.new(-w * 0.25, 0, d * 0.1)
		Kit.cylinder(t, mast + Vector3.new(0, 6, 0), 12, 0.45, M.Metal, Color3.fromRGB(150, 154, 160), { CanCollide = false, CastShadow = false })
		local beacon = Kit.glow(t, CFrame.new(mast + Vector3.new(0, 12.4, 0)), Vector3.new(0.8, 0.8, 0.8), Color3.fromRGB(255, 40, 40), { Name = "AirBeacon" })
		Kit.tag(beacon, Kit.TAG_BLINK)
		beacon:SetAttribute("Period", 1.4 + rng:NextNumber())
	end
	return t
end

-- Harbour pieces -----------------------------------------------------------------------------------------------

Props.CONTAINER_COLORS = {
	Color3.fromRGB(176, 58, 44), Color3.fromRGB(40, 92, 150), Color3.fromRGB(46, 128, 92), Color3.fromRGB(220, 132, 40),
	Color3.fromRGB(30, 120, 132), Color3.fromRGB(150, 150, 154), Color3.fromRGB(120, 60, 110), Color3.fromRGB(196, 170, 60),
}

-- Shipping container (20 x 8.6 x 8) standing on cf (cf at the container's floor centre). Ribs on the long faces.
function Props.container(parent: Instance, cf: CFrame, color: Color3, rng: Random, ribs: boolean?): BasePart
	local size = Vector3.new(20, 8.6, 8)
	local mat = if rng:NextNumber() < 0.45 then M.CorrodedMetal else M.Metal
	local body = Kit.block(parent, cf * CFrame.new(0, size.Y / 2, 0), size, mat, color, { Name = "Container" })
	if ribs ~= false then
		for i = -3, 3 do
			for _, sz in { -1, 1 } do
				Kit.deco(parent, cf * CFrame.new(i * 2.7, size.Y / 2, sz * (size.Z / 2 + 0.05)), Vector3.new(0.4, size.Y - 0.6, 0.1), mat, Kit.shade(color, 0.82), { Name = "Rib" })
			end
		end
	end
	local endCf = cf * CFrame.new(size.X / 2 + 0.06, size.Y / 2, 0)
	Kit.deco(parent, endCf, Vector3.new(0.12, size.Y - 0.5, size.Z - 0.5), mat, Kit.shade(color, 0.75), { Name = "Doors" })
	return body
end

-- Gantry crane with a boom pointing along `boomDir` (flat unit vector).
function Props.crane(parent: Instance, base: Vector3, boomDir: Vector3, rng: Random, color: Color3?): Model
	local m = Kit.model(parent, "GantryCrane")
	local red = color or Color3.fromRGB(196, 54, 44)
	local steel = Color3.fromRGB(70, 74, 82)
	local f = CFrame.lookAt(base, base + boomDir) -- local -Z = boom direction
	local legH, span, depth = 30, 14, 10
	for _, lx in { -span / 2, span / 2 } do
		for _, lz in { -depth / 2, depth / 2 } do
			Kit.block(m, f * CFrame.new(lx, legH / 2, lz), Vector3.new(1.4, legH, 1.4), M.Metal, red, { CanCollide = false })
		end
		Kit.block(m, f * CFrame.new(lx, 11, 0), Vector3.new(1.1, 1.1, depth), M.Metal, red, { CanCollide = false })
	end
	for _, lz in { -depth / 2, depth / 2 } do
		Kit.block(m, f * CFrame.new(0, legH + 1, lz), Vector3.new(span + 2, 2, 1.6), M.Metal, red, { CanCollide = false })
	end
	Kit.block(m, f * CFrame.new(0, legH + 3, -14), Vector3.new(3.4, 2.2, 52), M.Metal, red, { Name = "Boom", CanCollide = false })
	Kit.block(m, f * CFrame.new(0, legH + 8, 0), Vector3.new(1.8, 9, 1.8), M.Metal, red, { CanCollide = false })
	Kit.strut(m, (f * CFrame.new(0, legH + 12, 0)).Position, (f * CFrame.new(0, legH + 4, -36)).Position, 0.35, 0.35, M.Metal, steel, { CanCollide = false })
	Kit.strut(m, (f * CFrame.new(0, legH + 12, 0)).Position, (f * CFrame.new(0, legH + 4, 10)).Position, 0.35, 0.35, M.Metal, steel, { CanCollide = false })
	local cab = Kit.block(m, f * CFrame.new(0, legH + 0.2, -5), Vector3.new(3.6, 2.8, 3.2), M.Metal, Color3.fromRGB(236, 232, 224), { Name = "Cab", CanCollide = false })
	Kit.point(cab, Color3.fromRGB(255, 210, 150), 1, 12, false)
	local hookTop = (f * CFrame.new(0, legH + 1.8, -26)).Position
	Kit.rod(m, hookTop, hookTop - Vector3.new(0, 12, 0), 0.2, M.Metal, steel, { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
	Kit.block(m, CFrame.new(hookTop - Vector3.new(0, 13, 0)), Vector3.new(1.8, 1.8, 1.2), M.Metal, Color3.fromRGB(240, 186, 52), { CanCollide = false })
	local tip = Kit.glow(m, f * CFrame.new(0, legH + 3, -40.4), Vector3.new(0.8, 0.8, 0.8), Color3.fromRGB(255, 50, 40), { Name = "AirBeacon" })
	Kit.tag(tip, Kit.TAG_BLINK)
	tip:SetAttribute("Period", 1.2 + rng:NextNumber() * 0.6)
	return m
end

-- Small motor boat: hull, bow wedge, cabin with a lit window, mast lamp. cf at the waterline centre, -Z = bow.
function Props.boat(parent: Instance, cf: CFrame, hullColor: Color3): Model
	local m = Kit.model(parent, "Boat")
	local len, wid = 18, 6
	Kit.block(m, cf * CFrame.new(0, 0, 1.5), Vector3.new(wid, 2.4, len - 5), M.WoodPlanks, hullColor, { Name = "Hull", CanCollide = false })
	Kit.wedge(m, cf * CFrame.new(0, 0, -len / 2 + 2.5), Vector3.new(wid, 2.4, 5), M.WoodPlanks, hullColor, { Name = "Bow", CanCollide = false })
	Kit.deco(m, cf * CFrame.new(0, 1.25, 1.5), Vector3.new(wid + 0.3, 0.2, len - 5), M.Wood, Color3.fromRGB(236, 232, 224), { Name = "Gunwale" })
	Kit.block(m, cf * CFrame.new(0, 2.8, 3.5), Vector3.new(4.4, 2.8, 5), M.WoodPlanks, Color3.fromRGB(236, 232, 224), { Name = "Cabin", CanCollide = false })
	Kit.deco(m, cf * CFrame.new(0, 4.35, 3.5), Vector3.new(5, 0.3, 5.8), M.Metal, Color3.fromRGB(60, 80, 110), { Name = "CabinRoof" })
	local win = Kit.glow(m, cf * CFrame.new(0, 3.1, 0.96), Vector3.new(3.4, 0.9, 0.1), Color3.fromRGB(255, 214, 150), { Transparency = 0.3 })
	Kit.point(win, Color3.fromRGB(255, 200, 140), 0.7, 9, false)
	Kit.rod(m, (cf * CFrame.new(0, 1.3, -2)).Position, (cf * CFrame.new(0, 10, -2)).Position, 0.25, M.Wood, P.barkDark, { CanCollide = false, CastShadow = false })
	Kit.glow(m, cf * CFrame.new(0, 10.2, -2), Vector3.new(0.4, 0.4, 0.4), Color3.fromRGB(255, 240, 200))
	return m
end

-- Mooring bollard (dark iron) standing on `pos`.
function Props.bollard(parent: Instance, pos: Vector3): Model
	local m = Kit.model(parent, "Bollard")
	Kit.cylinder(m, pos + Vector3.new(0, 0.55, 0), 1.1, 1.2, M.Metal, Color3.fromRGB(40, 42, 48))
	Kit.cylinder(m, pos + Vector3.new(0, 1.2, 0), 0.25, 1.6, M.Metal, Color3.fromRGB(40, 42, 48), { CanCollide = false })
	return m
end

-- Paper/silk lantern hanging below `top` (warm glow, optional light).
function Props.hangingLantern(parent: Instance, top: Vector3, color: Color3, size: number?, light: boolean?): Part
	local s = size or 1.2
	Kit.rod(parent, top, top - Vector3.new(0, 0.5, 0), 0.06, M.Metal, Color3.fromRGB(30, 30, 30), { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
	local body = Kit.blob(parent, CFrame.new(top - Vector3.new(0, 0.5 + s * 0.6, 0)), Vector3.new(s, s * 1.2, s), M.Neon, color, { Name = "LanternBody", CastShadow = false })
	Kit.deco(parent, CFrame.new(top - Vector3.new(0, 0.55, 0)), Vector3.new(s * 0.55, 0.12, s * 0.55), M.Wood, P.woodDark, { Name = "LanternCap" })
	if light then
		Kit.point(body, color, 1, 10, false)
	end
	return body
end

return Props
