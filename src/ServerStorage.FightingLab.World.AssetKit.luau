--!strict
-- World.AssetKit (round 7): free Creator Store meshes placed by code. Each asset is a few textured meshes
-- (SpecialMesh FileMesh on a quiet Part: anchored, no collision, queries or touches), built from the mesh and texture
-- ids of a free model (see data/world-assets.json for the credits) and laid out exactly as in that model. Nothing is
-- inserted or loaded at build time: the ids are plain content the clients stream in, so no script from any model
-- ever reaches the game. Foliage textures with cut-out alpha draw through the transparent pass (Transparency 0.02 or
-- more: at 0 the engine ignores the texture's alpha and the leaves turn into black cards).
--
-- Every asset's pivot is the foot of its trunk (or the middle of its base) on the ground; `height` is its full height
-- at scale 1, `radius` the flat radius of its widest piece (for spacing and the camera-orbit checks).
local Kit = require(script.Parent.Kit)

local AssetKit = {}

export type Piece = {
	name: string,
	mesh: string,
	tex: string?,
	native: Vector3, -- the mesh's own size (MeshPart.MeshSize)
	size: Vector3, -- its size in the asset at scale 1
	pos: Vector3, -- centre relative to the pivot (scale 1)
	yaw: number?, -- degrees about Y (the asset's own layout)
	transparency: number?,
	material: Enum.Material?,
	color: Color3?,
	tint: Color3?, -- SpecialMesh.VertexColor (multiplies the texture)
	shadow: boolean?,
}
export type Asset = { key: string, assetId: number, height: number, radius: number, pieces: { Piece } }

local M = Enum.Material
local rgb = Color3.fromRGB

local function id(n: number): string return "rbxassetid://" .. tostring(n) end

AssetKit.ASSETS = {
	-- "Falling Blossom Cherry Tree" (softlypoetic, 8651908577): a slim trunk under a round, soft pink crown
	CherryTree = {
		key = "CherryTree", assetId = 8651908577, height = 44.5, radius = 20,
		pieces = {
			{ name = "Trunk", mesh = id(743209096), native = Vector3.new(6.8, 11.2, 5.22), size = Vector3.new(19.59, 37.66, 15.23), pos = Vector3.new(0, 18.83, 0), yaw = -90, material = M.Wood, color = rgb(74, 54, 46) },
			{ name = "Blossom", mesh = id(743209371), tex = id(5834464899), native = Vector3.new(13.857, 12.734, 13.761), size = Vector3.new(40.1, 36.85, 39.82), pos = Vector3.new(-1.12, 26.12, 0.88), yaw = -90, transparency = 0.3, shadow = false },
			{ name = "Petals", mesh = id(4665707228), tex = id(4665748451), native = Vector3.new(3.261, 2.907, 2.238), size = Vector3.new(20.33, 0.04, 16.08), pos = Vector3.new(-3.49, 0.08, 5.38), transparency = 0.02, shadow = false },
		},
	},
	-- "Jungle Tree" (TetoBagetto, 136959608628696): a twisted trunk with three broad leaf clusters
	JungleTree = {
		key = "JungleTree", assetId = 136959608628696, height = 40, radius = 13.5,
		pieces = {
			{ name = "Trunk", mesh = id(124549911509894), tex = id(124291912878293), native = Vector3.new(12.38, 21.28, 10.03), size = Vector3.new(21.16, 36.36, 17.13), pos = Vector3.new(0, 18.18, 0), yaw = 90 },
			{ name = "Branches", mesh = id(72043050647727), tex = id(105355134475960), native = Vector3.new(13.9, 10.68, 12.49), size = Vector3.new(23.75, 18.26, 21.34), pos = Vector3.new(0.78, 30.17, 0.95), yaw = 90, transparency = 0.02 },
			{ name = "Leaves", mesh = id(70984680959325), tex = id(139158850712812), native = Vector3.new(14.87, 9.61, 10.57), size = Vector3.new(25.42, 16.42, 18.06), pos = Vector3.new(-2.39, 31.57, 0.75), yaw = 90, transparency = 0.02, shadow = false },
			{ name = "Leaves", mesh = id(95619613439470), tex = id(139158850712812), native = Vector3.new(15.22, 8.26, 7.04), size = Vector3.new(26.0, 14.12, 12.02), pos = Vector3.new(1.3, 31.41, 1.49), yaw = 90, transparency = 0.02, shadow = false },
			{ name = "Leaves", mesh = id(95498768522065), tex = id(139158850712812), native = Vector3.new(15.37, 8.9, 13.48), size = Vector3.new(26.26, 15.21, 23.04), pos = Vector3.new(0.37, 32.07, 1.28), yaw = 90, transparency = 0.02, shadow = false },
		},
	},
	-- one palm of "Trees / Foliage - Tropical, Jungle, Island" (PSY0PZ, 12157426374)
	Palm = {
		key = "Palm", assetId = 12157426374, height = 42, radius = 9.5,
		pieces = {
			{ name = "Bark", mesh = id(1485912779), tex = id(1485917255), native = Vector3.new(2, 31.834, 1.902), size = Vector3.new(2.13, 33.87, 2.02), pos = Vector3.new(0, 16.94, 0) },
			{ name = "Fronds", mesh = id(1485915491), tex = id(1485918076), native = Vector3.new(25.029, 21.952, 21.642), size = Vector3.new(18.59, 16.3, 16.07), pos = Vector3.new(0, 33.93, 0), transparency = 0.06, shadow = false },
		},
	},
	-- broadleaf bushes of the same pack (understory)
	Bush = {
		key = "Bush", assetId = 12157426374, height = 4.2, radius = 3.3,
		pieces = {
			{ name = "Bush", mesh = id(742756209), tex = id(742752684), native = Vector3.new(6.442, 4.138, 6.318), size = Vector3.new(6.442, 4.138, 6.318), pos = Vector3.new(0, 2.07, 0), transparency = 0.02, shadow = false },
		},
	},
	-- "Snowy Pine Tree" (V1VEX, 11590212184): trunk, needles and a snow layer
	SnowPine = {
		key = "SnowPine", assetId = 11590212184, height = 57.3, radius = 13,
		pieces = {
			{ name = "Trunk", mesh = id(739614116), tex = id(739624959), native = Vector3.new(52.57, 1170.53, 50), size = Vector3.new(2.57, 57.29, 2.45), pos = Vector3.new(0, 28.65, 0) },
			{ name = "Needles", mesh = id(739619496), tex = id(11590208891), native = Vector3.new(50, 111.98, 54.01), size = Vector3.new(24.1, 53.98, 26.03), pos = Vector3.new(0, 28.65, 0), transparency = 0.1, shadow = false },
			{ name = "Snow", mesh = id(2312874610), tex = id(11590208891), native = Vector3.new(24.1, 53.98, 26.03), size = Vector3.new(24.1, 53.98, 26.03), pos = Vector3.new(0, 28.65, 0), transparency = 0.1, material = M.Snow, shadow = false },
		},
	},
	-- "Small Snowy Pine Tree" (Striatp, 76188132698241)
	SmallPine = {
		key = "SmallPine", assetId = 76188132698241, height = 15.5, radius = 4.8,
		pieces = {
			{ name = "Pine", mesh = id(6436440031), tex = id(6901062953), native = Vector3.new(9.57, 15.49, 9.57), size = Vector3.new(9.57, 15.49, 9.57), pos = Vector3.new(0, 7.745, 0), transparency = 0.02, shadow = false },
		},
	},
	-- "Realistic Stained Rock (Mesh)" (bearduckmonkey, 4141555239): three weathered stones
	Rock = {
		key = "Rock", assetId = 4141555239, height = 4.1, radius = 4.3,
		pieces = {
			{ name = "Stone", mesh = id(3241165695), tex = id(3241168936), native = Vector3.new(3.74, 2.13, 2.42), size = Vector3.new(7.24, 4.13, 4.68), pos = Vector3.new(0.3, 2.06, -0.2) },
			{ name = "Stone", mesh = id(3241164593), tex = id(3241168936), native = Vector3.new(3.1, 1.99, 1.66), size = Vector3.new(6.01, 3.86, 3.21), pos = Vector3.new(0.88, 1.93, 2.62) },
			{ name = "Stone", mesh = id(3241166357), tex = id(3241168936), native = Vector3.new(3.41, 2.13, 2.33), size = Vector3.new(6.62, 4.13, 4.51), pos = Vector3.new(-0.61, 2.06, -1.97) },
		},
	},
	-- a single stone of the same set (scaled up into boulders and crags)
	Boulder = {
		key = "Boulder", assetId = 4141555239, height = 4.13, radius = 3.7,
		pieces = {
			{ name = "Stone", mesh = id(3241165695), tex = id(3241168936), native = Vector3.new(3.74, 2.13, 2.42), size = Vector3.new(7.24, 4.13, 4.68), pos = Vector3.new(0, 2.06, 0) },
		},
	},
	-- "Medium Moss Boulder" from "Rock realistic" (omarllollo, 9217425479)
	MossRock = {
		key = "MossRock", assetId = 9217425479, height = 9.1, radius = 4.9,
		pieces = {
			{ name = "Stone", mesh = id(5547037341), tex = id(5023755574), native = Vector3.new(3.269, 3.047, 2.549), size = Vector3.new(9.77, 9.11, 7.62), pos = Vector3.new(0, 4.3, 0) },
		},
	},
	-- "Fern Tropical PBR Plants" (Ironsto4032, 119253821008946)
	Fern = {
		key = "Fern", assetId = 119253821008946, height = 3.6, radius = 2.9,
		pieces = {
			{ name = "Fern", mesh = id(6885158676), tex = id(6885161789), native = Vector3.new(0.7147, 0.4676, 0.7571), size = Vector3.new(5.885, 3.594, 5.378), pos = Vector3.new(0, 1.7, 0), yaw = 90, transparency = 0.02, shadow = false },
		},
	},
} :: { [string]: Asset }

-- Credits for every asset key (the free model each mesh set comes from).
function AssetKit.assetIds(): { [number]: boolean }
	local ids = {}
	for _, a in AssetKit.ASSETS do ids[a.assetId] = true end
	return ids
end

-- How far (flat, at `scale`, under any yaw) the pieces that start below `bandTop` studs above the pivot reach from it:
-- the offset of each piece plus its half diagonal. Placement code keeps that much clear of the fight camera's orbit.
function AssetKit.reach(key: string, scale: number, bandTop: number): number
	local a = AssetKit.ASSETS[key]
	assert(a, "AssetKit: unknown asset " .. key)
	local reach = 0
	for _, p in a.pieces do
		if (p.pos.Y - p.size.Y / 2) * scale < bandTop then
			local half = math.sqrt(p.size.X ^ 2 + p.size.Z ^ 2) / 2
			reach = math.max(reach, (Vector3.new(p.pos.X, 0, p.pos.Z).Magnitude + half) * scale)
		end
	end
	return reach
end

export type PlaceOpts = { tint: Color3?, shadows: boolean?, skip: { [string]: boolean }?, name: string? }

-- Places an asset with its pivot (foot of the trunk) at `cf` (Y up) and uniform `scale`; returns its Model (named
-- after the asset key, attribute AssetId). Pieces are quiet decoration; `opts.shadows` lets trunks and stones cast.
function AssetKit.place(parent: Instance, key: string, cf: CFrame, scale: number, opts: PlaceOpts?): Model
	local a = AssetKit.ASSETS[key]
	assert(a, "AssetKit: unknown asset " .. key)
	local o: PlaceOpts = opts or {}
	local m = Kit.model(parent, o.name or a.key)
	m:SetAttribute("AssetId", a.assetId)
	for _, p in a.pieces do
		if o.skip and o.skip[p.name] then continue end
		local size = p.size * scale
		local frame = cf * CFrame.new(p.pos * scale) * CFrame.Angles(0, math.rad(p.yaw or 0), 0)
		local part = Kit.deco(m, frame, size, p.material or M.SmoothPlastic, p.color or Color3.new(1, 1, 1), {
			Name = p.name,
			Transparency = p.transparency or 0,
			CastShadow = (o.shadows == true) and p.shadow ~= false,
		})
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.FileMesh
		mesh.MeshId = p.mesh
		mesh.TextureId = p.tex or ""
		mesh.Scale = size / p.native
		if o.tint and p.tex then
			mesh.VertexColor = Vector3.new(o.tint.R, o.tint.G, o.tint.B)
		elseif p.tint then
			mesh.VertexColor = Vector3.new(p.tint.R, p.tint.G, p.tint.B)
		end
		mesh.Parent = part
	end
	return m
end

return AssetKit
