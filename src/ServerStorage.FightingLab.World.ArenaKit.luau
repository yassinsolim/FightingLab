--!strict
-- World.ArenaKit: the pieces every arena stage shares (OV6). Model attributes and FightOrigin; the round podium with
-- its plaza stair; the fight floor ringed by a glowing edge line at the fight radius and a themed barrier just
-- outside it (rails/ropes with clearance underneath, so a fighter cornered at radius 21 stands against them and a
-- body knocked down at the edge slides under); the pads, exits and Arrival marker on the plaza in front of the stair;
-- the status board; stage lights; and the camera-occluder tagging pass.
local CollectionService = game:GetService("CollectionService")

local Kit = require(script.Parent.Kit)
local Layout = require(script.Parent.Layout)

type ArenaDef = Layout.ArenaDef

local ArenaKit = {}

local M = Enum.Material
local PAD_THICKNESS = 0.4
ArenaKit.PAD_GLOW_TAG = Kit.TAG_PAD_GLOW
ArenaKit.PAD_COLUMN_TAG = Kit.TAG_PAD_COLUMN

function ArenaKit.new(def: ArenaDef): Model
	local model = Instance.new("Model")
	model.Name = def.id
	model:SetAttribute("ArenaId", def.id)
	model:SetAttribute("StageId", def.stageId)
	model:SetAttribute("DisplayName", def.displayName)
	model:SetAttribute("Kind", def.kind)
	model:SetAttribute("Order", def.order)
	model:SetAttribute("AccentColor", def.accent)
	model:SetAttribute("Tagline", def.tagline)
	model:SetAttribute("FightRadius", Layout.FIGHT_RADIUS)
	local origin = Instance.new("Part")
	origin.Name = "FightOrigin"
	origin.Size = Vector3.new(1, 1, 1)
	origin.Transparency = 1
	origin.Anchored = true
	origin.CanCollide = false
	origin.CanQuery = false
	origin.CanTouch = false
	origin.CastShadow = false
	origin.CFrame = CFrame.new(def.origin)
	origin.Parent = model
	model.PrimaryPart = origin
	-- scenery (this stage's and its neighbours') never stands on the podium or through the status board
	Kit.keepOut(def.origin, Layout.STAGE_RADIUS + 1.5)
	Kit.keepOut(def.origin - def.inward * Layout.BOARD_DISTANCE, 16.5)
	-- and nothing grows on the forecourt with the pads
	Kit.keepOut(Layout.plazaPoint(def, 0, Layout.PAD_Z), Layout.PAD_X + Layout.PAD_RADIUS + 4)
	Kit.stats.parts += 1
	return model
end

-- Arena-local position: x towards `right`, y up from the floor top, z towards the plaza.
function ArenaKit.at(def: ArenaDef, x: number, y: number, z: number): Vector3
	return Layout.at(def, x, y, z)
end

-- Upright disc centred on FightOrigin's vertical axis with its top face at `top`.
function ArenaKit.disc(parent: Instance, def: ArenaDef, radius: number, top: number, thickness: number, material: Enum.Material, color: Color3, props: Kit.Props?): Part
	local centre = Vector3.new(def.origin.X, top - thickness / 2, def.origin.Z)
	return Kit.cylinder(parent, centre, thickness, radius * 2, material, color, props)
end

-- Calls fn(i, unitDir, angleRadians) for n evenly spaced directions round the arena (world bearings, `offset` in
-- degrees). Directions are flat unit vectors from FightOrigin.
function ArenaKit.ring(n: number, offset: number, fn: (number, Vector3, number) -> ())
	for i = 1, n do
		local a = math.rad(offset + (i - 1) * 360 / n)
		fn(i, Vector3.new(math.sin(a), 0, -math.cos(a)), a)
	end
end

-- Angle (degrees, -180..180) of a flat direction measured from the arena's plaza direction, positive to the right.
function ArenaKit.angleOf(def: ArenaDef, d: Vector3): number
	local x = d:Dot(def.right)
	local z = d:Dot(def.inward)
	return math.deg(math.atan2(x, z))
end

-- Stage ---------------------------------------------------------------------------------------------------------

export type StageStyle = {
	podiumMaterial: Enum.Material,
	podiumColor: Color3,
	rimMaterial: Enum.Material?,
	rimColor: Color3?,
	apronMaterial: Enum.Material,
	apronColor: Color3,
	bandMaterial: Enum.Material,
	bandColor: Color3,
	lineColor: Color3,
	floorMaterial: Enum.Material,
	floorColor: Color3,
	stairMaterial: Enum.Material,
	stairColor: Color3,
	stairNose: Color3?,
	cheekMaterial: Enum.Material?,
	cheekColor: Color3?,
	groundY: number?,
	podiumBottom: number?,
	skipPodiumBody: boolean?,
	stairWidth: number?,
}

-- Podium (round, radius STAGE_RADIUS) whose top is the apron; fight floor, edge line and edge band nested on it as
-- discs a hair apart (fight floor highest), so every ring is a perfect circle with no coplanar faces.
function ArenaKit.stage(model: Model, def: ArenaDef, s: StageStyle): Model
	local stage = Kit.model(model, "Stage")
	local fy = def.floorY
	local apronTop = fy - Layout.APRON_DROP
	local R = Layout.STAGE_RADIUS
	local ground = s.groundY or 0
	if not s.skipPodiumBody then
		local bottom = s.podiumBottom or (ground - 4)
		local top = apronTop - 0.04
		ArenaKit.disc(stage, def, R - 0.05, top, top - bottom, s.podiumMaterial, s.podiumColor, { Name = "Podium" })
	end
	ArenaKit.disc(stage, def, R, apronTop - 0.02, 0.5, s.rimMaterial or s.podiumMaterial, s.rimColor or s.podiumColor, { Name = "Rim", CastShadow = false })
	ArenaKit.disc(stage, def, R - 0.7, apronTop, 0.5, s.apronMaterial, s.apronColor, { Name = "Apron", CastShadow = false })
	ArenaKit.disc(stage, def, Layout.BAND_OUTER, fy - Layout.BAND_DROP, 0.45, s.bandMaterial, s.bandColor, { Name = "EdgeBand", CastShadow = false })
	local line = ArenaKit.disc(stage, def, Layout.EDGE_OUTER, fy - Layout.LINE_DROP, 0.45, M.Neon, s.lineColor, { Name = "EdgeLine", CastShadow = false })
	line:SetAttribute("InnerRadius", Layout.EDGE_INNER)
	line:SetAttribute("OuterRadius", Layout.EDGE_OUTER)
	ArenaKit.disc(stage, def, Layout.EDGE_INNER, fy, 0.45, s.floorMaterial, s.floorColor, { Name = "FightFloor", CastShadow = false })
	ArenaKit.stairs(stage, def, s)
	return stage
end

-- Straight stair from the plaza up to the apron, facing the plaza. Each step is a solid block reaching back inside
-- the podium; the last riser is the podium's own curved edge.
function ArenaKit.stairs(parent: Instance, def: ArenaDef, s: StageStyle)
	local n = Layout.stepCount(def)
	if n < 1 then return end
	local ground = s.groundY or 0
	local apronTop = def.floorY - Layout.APRON_DROP
	local rise = (apronTop - ground) / n
	local run = Layout.STEP_RUN
	local width = s.stairWidth or def.stairWidth or Layout.STAIR_WIDTH
	local R = Layout.STAGE_RADIUS
	local m = Kit.model(parent, "Stair")
	local backZ = R - 4 -- blocks start inside the podium
	for k = 1, n - 1 do
		local top = ground + k * rise
		local frontZ = R + (n - k) * run
		local depth = frontZ - backZ
		local bottom = ground - 1
		local cf = Layout.frame(def, 0, 0, (frontZ + backZ) / 2)
		local centre = Vector3.new(cf.X, (top + bottom) / 2, cf.Z)
		Kit.block(m, CFrame.new(centre) * cf.Rotation, Vector3.new(width, top - bottom, depth), s.stairMaterial, if k % 2 == 0 then s.stairColor else Kit.shade(s.stairColor, 0.94), { Name = "Step" })
		if s.stairNose then
			local nose = Layout.frame(def, 0, 0, frontZ - 0.2)
			Kit.glow(m, CFrame.new(nose.X, top + 0.015, nose.Z) * nose.Rotation, Vector3.new(width - 0.6, 0.05, 0.22), s.stairNose, { Name = "StepNose", Transparency = 0.25 })
		end
	end
	-- cheek walls following the flight, a little higher than the treads
	local totalRun = (n - 1) * run
	if n >= 3 then
		for _, side in { -1, 1 } do
			local x = side * (width / 2 + 0.6)
			local a = Layout.at(def, x, 0, R + totalRun + 0.4)
			local b = Layout.at(def, x, 0, R - 0.6)
			a = Vector3.new(a.X, ground + 0.5, a.Z)
			b = Vector3.new(b.X, apronTop + 0.55, b.Z)
			local mid = (a + b) / 2
			local len = (b - a).Magnitude
			local cf = CFrame.lookAt(mid, b)
			Kit.block(m, cf, Vector3.new(1.2, 1.1, len), s.cheekMaterial or s.podiumMaterial, s.cheekColor or s.podiumColor, { Name = "Cheek" })
			-- the cheek's lower end sits on a plinth so it meets the plaza cleanly
			local foot = Layout.frame(def, x, 0, R + totalRun + 0.2)
			Kit.block(m, CFrame.new(foot.X, ground + 0.55, foot.Z) * foot.Rotation, Vector3.new(1.4, 1.1, 1.4), s.cheekMaterial or s.podiumMaterial, s.cheekColor or s.podiumColor, { Name = "CheekFoot" })
		end
	end
end

-- Low parapet along the apron edge between two angles (degrees from the plaza direction, positive to the right).
-- Top stays below floor + 1.5 so it never needs camera fading.
function ArenaKit.parapet(parent: Instance, def: ArenaDef, fromAngle: number, toAngle: number, height: number, material: Enum.Material, color: Color3, cap: Color3?, capMaterial: Enum.Material?)
	local m = Kit.model(parent, "Parapet")
	local R = Layout.STAGE_RADIUS - 0.45
	local base = def.floorY - Layout.APRON_DROP
	local stepDeg = 6
	local count = math.max(1, math.ceil((toAngle - fromAngle) / stepDeg))
	local span = (toAngle - fromAngle) / count
	for i = 0, count - 1 do
		local a0 = fromAngle + i * span
		local a1 = a0 + span
		local p0 = def.origin + Layout.around(def, a0) * R
		local p1 = def.origin + Layout.around(def, a1) * R
		local mid = (p0 + p1) / 2
		local len = (p1 - p0).Magnitude + 0.06
		-- alternate segments sit 0.012 apart so the overlapping joints never z-fight
		local y = base + height / 2 + (i % 2) * 0.012
		local cf = CFrame.lookAt(Vector3.new(mid.X, y, mid.Z), Vector3.new(p1.X, y, p1.Z))
		Kit.block(m, cf, Vector3.new(0.9, height, len), material, color, { Name = "ParapetWall" })
		if cap then
			Kit.deco(m, cf * CFrame.new(0, height / 2 + 0.06, 0), Vector3.new(1.15, 0.12, len), capMaterial or M.Concrete, cap, { Name = "ParapetCap" })
		end
	end
	return m
end

-- Barrier ----------------------------------------------------------------------------------------------------------

export type RailSpec = { height: number, diameter: number, material: Enum.Material, color: Color3, sag: number?, name: string? }
export type BarrierStyle = {
	posts: number,
	offset: number?, -- degrees; default half a post spacing so no post sits on a camera or fight axis
	post: (parent: Instance, base: Vector3, out: Vector3, index: number) -> (),
	rails: { RailSpec },
	strip: { height: number, color: Color3, thickness: number? }?,
}

-- Posts stand on the apron at RAIL_RADIUS; rails run between neighbouring posts (optionally sagging like rope).
-- Every rail stays at least RAIL_CLEARANCE above the floor. Parts are named EdgePost* / EdgeRail* / EdgeStrip*.
function ArenaKit.barrier(model: Model, def: ArenaDef, b: BarrierStyle): Model
	local m = Kit.model(model, "Barrier")
	local n = b.posts
	local r = Layout.RAIL_RADIUS
	local base = def.floorY - Layout.APRON_DROP
	local offset = b.offset or (180 / n)
	local points: { Vector3 } = {}
	ArenaKit.ring(n, offset, function(i, d)
		local p = Vector3.new(def.origin.X, base, def.origin.Z) + d * r
		points[i] = p
		b.post(m, p, d, i)
	end)
	for i = 1, n do
		local a = points[i]
		local c = points[i % n + 1]
		for k, rail in b.rails do
			local h = math.max(rail.height, Layout.RAIL_CLEARANCE + Layout.APRON_DROP + rail.diameter / 2)
			local pa = a + Vector3.new(0, h, 0)
			local pc = c + Vector3.new(0, h, 0)
			local sag = rail.sag or 0
			local name = rail.name or ("EdgeRail" .. k)
			if sag > 0 then
				local lowest = h - sag
				local floorClear = Layout.RAIL_CLEARANCE + Layout.APRON_DROP + rail.diameter / 2
				if lowest < floorClear then
					sag = math.max(0, h - floorClear)
				end
				local mid = (pa + pc) / 2 - Vector3.new(0, sag, 0)
				Kit.rod(m, pa, mid, rail.diameter, rail.material, rail.color, { Name = name, CastShadow = false })
				Kit.rod(m, mid, pc, rail.diameter, rail.material, rail.color, { Name = name, CastShadow = false })
			else
				Kit.rod(m, pa, pc, rail.diameter, rail.material, rail.color, { Name = name, CastShadow = false })
			end
		end
		if b.strip then
			local h = b.strip.height
			local t = b.strip.thickness or 0.12
			local pa = a + Vector3.new(0, h, 0)
			local pc = c + Vector3.new(0, h, 0)
			local mid = (pa + pc) / 2
			Kit.glow(m, CFrame.lookAt(mid, pc), Vector3.new(t, t, (pc - pa).Magnitude), b.strip.color, { Name = "EdgeStrip" })
		end
	end
	Kit.step()
	return m
end

-- Paint on the fight floor (a SurfaceGui on a transparent sheet just above it): start marks, centre motif, emblem.
-- The canvas reads upright from the south (slot 1's camera side): canvas X = world +X, canvas up = world -Z.
export type PaintOpts = {
	lineColor: Color3,
	emblem: string?,
	emblemColor: Color3?,
	emblemFont: Enum.Font?,
	emblemTransparency: number?,
	lightInfluence: number?,
	rings: { { number } }?, -- { radius, thickness, transparency }
	ringColor: Color3?,
}

function ArenaKit.paintFloor(model: Model, def: ArenaDef, opts: PaintOpts): BasePart
	local span = 44
	local pps = 16
	local c = def.origin + Vector3.new(0, 0.022, 0)
	local sheet = Kit.deco(model, CFrame.lookAt(c, c + Vector3.xAxis), Vector3.new(span, 0.02, span), M.SmoothPlastic, Color3.new(1, 1, 1), {
		Name = "FloorPaint",
		Transparency = 1,
		CastShadow = false,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Paint"
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pps
	gui.LightInfluence = opts.lightInfluence or 0.9
	gui.Brightness = 1
	gui.MaxDistance = 600
	gui.Parent = sheet
	Kit.stats.guis += 1
	for i, ring in opts.rings or {} do
		local f = Instance.new("Frame")
		f.Name = "Ring" .. i
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(0.5, 0.5)
		f.Size = UDim2.fromOffset(ring[1] * 2 * pps, ring[1] * 2 * pps)
		f.BackgroundTransparency = 1
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = f
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = ring[2] * pps
		stroke.Color = opts.ringColor or opts.lineColor
		stroke.Transparency = ring[3] or 0.2
		stroke.Parent = f
		f.Parent = gui
	end
	-- start marks where fighters begin a round (3.5 studs either side along X)
	for _, sx in { -1, 1 } do
		local mark = Instance.new("Frame")
		mark.Name = "StartMark"
		mark.AnchorPoint = Vector2.new(0.5, 0.5)
		mark.Position = UDim2.new(0.5, sx * 3.5 * pps, 0.5, 0)
		mark.Size = UDim2.fromOffset(0.32 * pps, 2.6 * pps)
		mark.BackgroundColor3 = if sx < 0 then Layout.P1_COLOR else Layout.P2_COLOR
		mark.BackgroundTransparency = 0.2
		mark.BorderSizePixel = 0
		mark.Parent = gui
	end
	if opts.emblem then
		-- the arena's name on the floor behind the fighters for each fight camera: slot 1 looks north from the south
		-- side and reads the copy on the north half (canvas up = north); slot 2 looks south and reads the turned copy
		for _, side in { -1, 1 } do
			local t = Instance.new("TextLabel")
			t.Name = "Emblem"
			t.AnchorPoint = Vector2.new(0.5, 0.5)
			t.Position = UDim2.new(0.5, 0, 0.5, side * 14.5 * pps)
			t.Size = UDim2.fromOffset(16 * pps, 3 * pps)
			t.Rotation = if side > 0 then 180 else 0
			t.BackgroundTransparency = 1
			t.Font = opts.emblemFont or Enum.Font.GothamBlack
			t.Text = opts.emblem
			t.TextScaled = true
			t.TextColor3 = opts.emblemColor or opts.lineColor
			t.TextTransparency = opts.emblemTransparency or 0.55
			t.Parent = gui
		end
	end
	return sheet
end

-- Pads and exits ---------------------------------------------------------------------------------------------------

-- A glowing pad disc on the plaza in front of the stage (top = plaza + PAD_TOP) with halo ring, emblem, light, light
-- column and rising motes.
function ArenaKit.pad(model: Model, def: ArenaDef, name: string, slot: number, color: Color3, attrs: { [string]: any }, emblem: string, caption: string): BasePart
	local r = Layout.PAD_RADIUS
	local centre = Layout.padPosition(def, slot)
	local base = -0.2 -- sunk into the paving
	local thickness = Layout.PAD_TOP - base
	local pad = Kit.cylinder(model, Vector3.new(centre.X, base + thickness / 2, centre.Z), thickness, r * 2, M.Neon, color, {
		Name = name,
		CastShadow = false,
		Transparency = 0.08,
	})
	for key, value in attrs do
		pad:SetAttribute(key, value)
	end
	Kit.passThrough(pad)
	pad:SetAttribute("PadRadius", r)
	pad:SetAttribute("PadColor", color)
	local top = Layout.PAD_TOP
	local glow = Kit.model(model, name .. "Glow")
	-- dark glass centre leaves a bright neon rim
	Kit.cylinder(glow, Vector3.new(centre.X, top + 0.015, centre.Z), 0.03, r * 2 - 1.2, M.Glass, Kit.shade(color, 0.22), {
		Name = "Core",
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Transparency = 0.12,
	})
	-- soft halo on the paving round the pad (top 0.11: clear of every paving disc and inlay height)
	local halo = Kit.cylinder(glow, Vector3.new(centre.X, 0.1, centre.Z), 0.02, r * 2 + 1.6, M.Neon, color, {
		Name = "Halo",
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Transparency = 0.62,
	})
	Kit.tag(halo, ArenaKit.PAD_GLOW_TAG)
	-- emblem reads upright for someone walking up from the plaza (Top-face canvas: up = part -X, right = part -Z)
	local plateCf = CFrame.lookAt(Vector3.new(centre.X, top + 0.04, centre.Z), Vector3.new(centre.X, top + 0.04, centre.Z) + def.right)
	local plate = Kit.deco(glow, plateCf, Vector3.new(r * 1.6, 0.02, r * 1.6), M.SmoothPlastic, color, {
		Name = "Emblem",
		Transparency = 1,
	})
	local gui = Kit.label(plate, Enum.NormalId.Top, emblem, {
		font = Enum.Font.GothamBlack,
		color = Color3.new(1, 1, 1):Lerp(color, 0.35),
		stroke = Kit.shade(color, 0.3),
		strokeTransparency = 0.3,
		pps = 60,
		padding = 0.2,
		brightness = 1.6,
		name = "EmblemGui",
	})
	local sub = Instance.new("TextLabel")
	sub.Name = "Caption"
	sub.BackgroundTransparency = 1
	sub.Size = UDim2.fromScale(0.9, 0.16)
	sub.Position = UDim2.fromScale(0.05, 0.8)
	sub.Font = Enum.Font.GothamBold
	sub.TextScaled = true
	sub.Text = caption
	sub.TextColor3 = Color3.new(1, 1, 1)
	sub.Parent = gui
	local textLabel = gui:FindFirstChild("Text") :: TextLabel
	textLabel.Size = UDim2.fromScale(0.7, 0.5)
	textLabel.Position = UDim2.fromScale(0.15, 0.2)
	local light = Kit.point(pad, color, 2.2, 14, false)
	light.Name = "PadLight"
	Kit.tag(light, ArenaKit.PAD_GLOW_TAG)
	-- slim light column for wayfinding; LobbyAmbience hides it near the camera, on taken pads and during fights
	local column = Kit.lightColumn(pad, Vector3.new(centre.X, top, centre.Z), 11, r * 0.9, color, 0.55)
	column.Name = "PadColumn"
	Kit.tag(column, ArenaKit.PAD_COLUMN_TAG)
	Kit.emitter(pad, {
		Name = "PadMotes",
		Color = Kit.colors(color, Color3.new(1, 1, 1)),
		LightEmission = 1,
		Size = Kit.numbers(0.22, 0.12, 0),
		Transparency = Kit.numbers(0.2, 0.4, 1),
		Lifetime = NumberRange.new(1.4, 2.4),
		Rate = 6,
		Speed = NumberRange.new(2.2, 4),
		SpreadAngle = Vector2.new(8, 8),
		EmissionDirection = Enum.NormalId.Right, -- cylinder axis (local X) points up
		Shape = Enum.ParticleEmitterShape.Box,
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
	})
	return pad
end

-- Invisible marker beside its pad (outside it), on the plaza floor, facing FightOrigin.
function ArenaKit.exit(model: Model, def: ArenaDef, name: string, slot: number): BasePart
	local pos = Layout.exitPosition(def, slot)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = Vector3.new(2, 0.2, 2)
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.CFrame = CFrame.lookAt(pos, Vector3.new(def.origin.X, pos.Y, def.origin.Z))
	p.Parent = model
	Kit.stats.parts += 1
	return p
end

-- Arrival: where quick travel drops a player who wants to watch or walk in. An invisible, non-colliding marker on the
-- plaza floor between the two pads (outside the ring, the barrier and the pads), facing the ring; its bottom face
-- rests on the floor.
function ArenaKit.arrival(model: Model, def: ArenaDef): BasePart
	local pos = Layout.arrivalPosition(def) + Vector3.new(0, 0.1, 0)
	local p = Instance.new("Part")
	p.Name = "Arrival"
	p.Size = Vector3.new(4, 0.2, 4)
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.CFrame = CFrame.lookAt(pos, Vector3.new(def.origin.X, pos.Y, def.origin.Z))
	p.Parent = model
	Kit.stats.parts += 1
	return p
end

-- Standard contract pieces for an arena: pads, exits and the Arrival marker.
function ArenaKit.contractPieces(model: Model, def: ArenaDef)
	if def.kind == "Practice" then
		ArenaKit.pad(model, def, "PadTraining", 1, Layout.TRAINING_COLOR, { PadMode = "Training" }, "TRAIN", "PRACTICE")
		ArenaKit.pad(model, def, "PadCpu", 2, Layout.CPU_COLOR, { PadMode = "Cpu" }, "CPU", "VERSUS CPU")
		ArenaKit.exit(model, def, "ExitTraining", 1)
		ArenaKit.exit(model, def, "ExitCpu", 2)
	else
		ArenaKit.pad(model, def, "PadP1", 1, Layout.P1_COLOR, { PadSide = 1 }, "P1", "STAND TO DUEL")
		ArenaKit.pad(model, def, "PadP2", 2, Layout.P2_COLOR, { PadSide = 2 }, "P2", "STAND TO DUEL")
		ArenaKit.exit(model, def, "ExitP1", 1)
		ArenaKit.exit(model, def, "ExitP2", 2)
	end
	ArenaKit.arrival(model, def)
end

-- Name mat at the stair foot (model Gate_<StageId>): a themed inlay centred on the stair, lettered with the arena
-- name so it reads for someone walking up from the plaza. Flush with the floor, so it never blocks a walkway or a
-- view, and it stays between the two pads.
function ArenaKit.gate(model: Model, def: ArenaDef, material: Enum.Material, color: Color3, textColor: Color3?): Model
	local g = Kit.model(model, "Gate_" .. def.stageId)
	local width = 2 * (Layout.PAD_X - Layout.PAD_RADIUS) - 1
	local depth = 3.6
	local top = 0.22
	local centre = Layout.stairFoot(def) + def.inward * (depth / 2 + 0.4) + Vector3.new(0, top - 0.15, 0)
	-- X runs towards the plaza, so the Top-face canvas reads upright for someone facing the stair
	local cf = CFrame.fromMatrix(centre, def.inward, Vector3.yAxis)
	local mat = Kit.block(g, cf, Vector3.new(depth, 0.3, width), material, color, { Name = "NameMat", CastShadow = false })
	Kit.passThrough(mat)
	for _, s in { -1, 1 } do
		Kit.glow(g, cf * CFrame.new(s * (depth / 2 - 0.25), 0.155, 0), Vector3.new(0.16, 0.02, width - 0.6), def.accent, { Name = "NameMatTrim", Transparency = 0.15 })
	end
	Kit.label(mat, Enum.NormalId.Top, string.upper(def.displayName), {
		font = Enum.Font.GothamBlack,
		color = textColor or Color3.new(1, 1, 1),
		stroke = Kit.shade(def.accent, 0.45),
		strokeTransparency = 0.25,
		pps = 24,
		padding = 0.14,
		light = 0.35,
		brightness = 1.3,
	})
	return g
end

-- Status board -----------------------------------------------------------------------------------------------------

-- Status board: 24 x 13.5 studs (800 x 450 canvas) behind the stage, facing the plaza. While the UI hides the
-- StatusGui (a player's own fight looks at it) an idle face with the arena name shows instead (lower ZOffset).
-- `support(boardCf)` may build a themed mount; otherwise two legs go down to `groundY`.
function ArenaKit.statusBoard(model: Model, def: ArenaDef, height: number, frameColor: Color3, frameMaterial: Enum.Material?, groundY: number?, support: ((CFrame) -> ())?): BasePart
	local base = def.origin - def.inward * Layout.BOARD_DISTANCE
	local centre = Vector3.new(base.X, def.floorY + height, base.Z)
	local cf = CFrame.lookAt(centre, centre + def.inward)
	local board = Kit.block(model, cf, Vector3.new(24, 13.5, 0.6), M.SmoothPlastic, Color3.fromRGB(12, 14, 20), {
		Name = "StatusBoard",
		CanCollide = false,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Name = "StatusGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 800 / 24
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.ClipsDescendants = true
	gui.MaxDistance = 0
	gui.ZOffset = 1
	gui.Parent = board
	Kit.stats.guis += 1
	local idle = Instance.new("SurfaceGui")
	idle.Name = "BoardIdle"
	idle.Face = Enum.NormalId.Front
	idle.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	idle.PixelsPerStud = 20
	idle.LightInfluence = 0
	idle.Brightness = 1.4
	idle.ZOffset = 0
	idle.MaxDistance = 900
	idle.Parent = board
	Kit.stats.guis += 1
	local bg = Instance.new("Frame")
	bg.Name = "Back"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BorderSizePixel = 0
	bg.BackgroundColor3 = Color3.fromRGB(10, 12, 18)
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Kit.shade(def.accent, 0.22), Color3.fromRGB(8, 10, 16))
	grad.Rotation = 90
	grad.Parent = bg
	bg.Parent = idle
	-- the fight camera sees the lower half of the board behind the fighters, so the name sits low (kind tag above)
	local rule = Instance.new("Frame")
	rule.Name = "Rule"
	rule.AnchorPoint = Vector2.new(0.5, 0.5)
	rule.Position = UDim2.fromScale(0.5, 0.5)
	rule.Size = UDim2.fromScale(0.4, 0.012)
	rule.BorderSizePixel = 0
	rule.BackgroundColor3 = def.accent
	rule.Parent = idle
	local name = Instance.new("TextLabel")
	name.Name = "Title"
	name.BackgroundTransparency = 1
	name.AnchorPoint = Vector2.new(0.5, 0.5)
	name.Position = UDim2.fromScale(0.5, 0.68)
	name.Size = UDim2.fromScale(0.86, 0.26)
	name.Font = Enum.Font.GothamBlack
	name.TextScaled = true
	name.Text = string.upper(def.displayName)
	name.TextColor3 = Color3.new(1, 1, 1)
	name.TextStrokeColor3 = def.accent
	name.TextStrokeTransparency = 0.2
	name.Parent = idle
	local tag = Instance.new("TextLabel")
	tag.Name = "Kind"
	tag.BackgroundTransparency = 1
	tag.AnchorPoint = Vector2.new(0.5, 0.5)
	tag.Position = UDim2.fromScale(0.5, 0.4)
	tag.Size = UDim2.fromScale(0.6, 0.1)
	tag.Font = Enum.Font.GothamBold
	tag.TextScaled = true
	tag.Text = if def.kind == "Practice" then "PRACTICE DOJO" else "DUEL ARENA"
	tag.TextColor3 = def.accent
	tag.Parent = idle
	-- bezel, accent trim and name plate
	local mat = frameMaterial or M.Metal
	local fw = 0.7
	Kit.deco(model, cf * CFrame.new(0, 6.75 + fw / 2, 0.15), Vector3.new(25.4, fw, 1.1), mat, frameColor, { Name = "BoardFrame" })
	Kit.deco(model, cf * CFrame.new(0, -6.75 - fw / 2, 0.15), Vector3.new(25.4, fw, 1.1), mat, frameColor, { Name = "BoardFrame" })
	Kit.deco(model, cf * CFrame.new(12 + fw / 2, 0, 0.15), Vector3.new(fw, 13.5, 1.1), mat, frameColor, { Name = "BoardFrame" })
	Kit.deco(model, cf * CFrame.new(-12 - fw / 2, 0, 0.15), Vector3.new(fw, 13.5, 1.1), mat, frameColor, { Name = "BoardFrame" })
	local back = Kit.deco(model, cf * CFrame.new(0, 0, 0.62), Vector3.new(24.6, 13.6, 0.5), mat, Kit.shade(frameColor, 0.7), { Name = "BoardBack" })
	Kit.label(back, Enum.NormalId.Back, string.upper(def.displayName), {
		font = Enum.Font.GothamBlack,
		color = Kit.mix(def.accent, Color3.new(1, 1, 1), 0.35),
		pps = 12,
		padding = 0.16,
		light = 0.6,
		brightness = 1.1,
		name = "BackText",
	})
	Kit.glow(model, cf * CFrame.new(0, -6.75 - fw - 0.12, -0.1), Vector3.new(25.4, 0.22, 0.5), def.accent, { Name = "BoardTrim" })
	Kit.glow(model, cf * CFrame.new(0, 6.75 + fw + 0.12, -0.1), Vector3.new(25.4, 0.22, 0.5), def.accent, { Name = "BoardTrim" })
	local plate = Kit.deco(model, cf * CFrame.new(0, 6.75 + fw + 1.6, 0.1), Vector3.new(18, 2.6, 0.5), mat, Kit.shade(frameColor, 0.7), { Name = "BoardNamePlate" })
	Kit.label(plate, Enum.NormalId.Front, string.upper(def.displayName), {
		font = Enum.Font.GothamBlack,
		color = Color3.new(1, 1, 1),
		stroke = def.accent,
		strokeTransparency = 0.1,
		pps = 30,
		padding = 0.1,
		brightness = 1.5,
	})
	if support then
		support(cf)
	else
		local legY = groundY or 0
		local bottomY = centre.Y - 6.75 - fw
		for _, sx in { -8, 8 } do
			local top = cf * CFrame.new(sx, -6.75 - fw, 0.6)
			local foot = Vector3.new(top.X, legY, top.Z)
			Kit.block(model, CFrame.new((top.Position + foot) / 2) * cf.Rotation, Vector3.new(1.2, bottomY - legY, 1.2), mat, frameColor, { Name = "BoardLeg" })
			Kit.block(model, CFrame.new(foot + Vector3.new(0, 0.3, 0)) * cf.Rotation, Vector3.new(2.4, 0.6, 2.4), mat, Kit.shade(frameColor, 0.8), { Name = "BoardFoot" })
		end
	end
	return board
end

-- Stage lights -----------------------------------------------------------------------------------------------------

-- Light pole on the apron rim aimed at the fight floor: slim pole, lamp head with a glowing lens and a spotlight.
-- `strength` scales Layout.STAGE_SPOT_BRIGHTNESS (1 = the shared fight-floor key; harbor's sodium lamps run a bit
-- warmer/stronger). Kept soft so pale skin and hair never clip under the low sun (World_Test pins the ceiling).
function ArenaKit.stageLight(parent: Instance, def: ArenaDef, angle: number, color: Color3, height: number, strength: number, poleColor: Color3, headColor: Color3?): Model
	local m = Kit.model(parent, "StageLight")
	local d = Layout.around(def, angle)
	-- on the apron rim, clear of the flat fight floor (radius FLOOR_CLEAR_RADIUS) with its lamp heads too
	local base = def.origin + d * (Layout.STAGE_RADIUS - 0.8)
	base = Vector3.new(base.X, def.floorY - Layout.APRON_DROP, base.Z)
	Kit.cylinder(m, base + Vector3.new(0, 0.3, 0), 0.6, 1.2, M.Metal, Kit.shade(poleColor, 0.8), { Name = "LightBase" })
	Kit.cylinder(m, base + Vector3.new(0, height / 2, 0), height, 0.45, M.Metal, poleColor, { Name = "LightPole" })
	local headPos = base + Vector3.new(0, height + 0.4, 0)
	local aim = def.origin + Vector3.new(0, 1, 0)
	local cf = CFrame.lookAt(headPos, aim)
	Kit.deco(m, cf * CFrame.new(0, 0, 0.4), Vector3.new(2.6, 0.25, 0.25), M.Metal, poleColor, { Name = "LightYoke" })
	for _, sx in { -0.75, 0.75 } do
		local head = Kit.deco(m, cf * CFrame.new(sx, 0, 0), Vector3.new(1.1, 1.1, 1.3), M.Metal, headColor or Color3.fromRGB(36, 38, 44), { Name = "LightHead" })
		Kit.glow(m, cf * CFrame.new(sx, 0, -0.67), Vector3.new(0.85, 0.85, 0.05), color, { Name = "LightLens" })
		local _ = head
	end
	local holder = Kit.deco(m, cf * CFrame.new(0, 0, -0.7), Vector3.new(0.2, 0.2, 0.2), M.SmoothPlastic, color, { Name = "LightEmitter", Transparency = 1 })
	local spot = Kit.spot(holder, Enum.NormalId.Front, color, Layout.STAGE_SPOT_BRIGHTNESS * strength, Layout.STAGE_SPOT_RANGE, 48, false)
	spot.Name = "StageSpot"
	return m
end

-- Camera occluders -------------------------------------------------------------------------------------------------

-- Tag every BasePart taller than floor + 1.5 within the occluder radius (contract: the fight camera fades them).
local function horizontalExtents(cf: CFrame, size: Vector3): (number, number, number)
	local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	local ex = math.abs(r.X) * hx + math.abs(u.X) * hy + math.abs(l.X) * hz
	local ey = math.abs(r.Y) * hx + math.abs(u.Y) * hy + math.abs(l.Y) * hz
	local ez = math.abs(r.Z) * hx + math.abs(u.Z) * hy + math.abs(l.Z) * hz
	return ex, ey, ez
end
ArenaKit.extents = horizontalExtents

function ArenaKit.occludes(def: ArenaDef, part: BasePart): boolean
	-- fully invisible helpers (emitter volumes, light anchors, markers) never block the view
	if part.Transparency >= 0.99 then
		return false
	end
	local cf = part.CFrame
	local ex, ey, ez = horizontalExtents(cf, part.Size)
	if cf.Y + ey <= def.origin.Y + Layout.OCCLUDER_HEIGHT + 1e-3 then
		return false
	end
	local dx = math.max(math.abs(cf.X - def.origin.X) - ex, 0)
	local dz = math.max(math.abs(cf.Z - def.origin.Z) - ez, 0)
	return dx * dx + dz * dz < Layout.OCCLUDER_RADIUS * Layout.OCCLUDER_RADIUS
end

function ArenaKit.tagOccluders(def: ArenaDef, roots: { Instance }): number
	local count = 0
	for _, root in roots do
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") and d.Name ~= "FightOrigin" and ArenaKit.occludes(def, d) then
				if not CollectionService:HasTag(d, Layout.OCCLUDER_TAG) then
					CollectionService:AddTag(d, Layout.OCCLUDER_TAG)
					count += 1
				end
			end
		end
		Kit.step()
	end
	return count
end

-- Flat distance from `p` to a part's oriented box (measured at the part's height).
local function boxFlatDistance(d: BasePart, p: Vector3): number
	local cf = d.CFrame
	local q = Vector3.new(p.X, cf.Y, p.Z)
	local l = cf:PointToObjectSpace(q)
	local h = d.Size / 2
	local c = cf:PointToWorldSpace(Vector3.new(math.clamp(l.X, -h.X, h.X), math.clamp(l.Y, -h.Y, h.Y), math.clamp(l.Z, -h.Z, h.Z)))
	return Vector3.new(c.X - q.X, 0, c.Z - q.Z).Magnitude
end

-- Whether every piece of `root` that rises above a neighbouring fight floor + OCCLUDER_HEIGHT stays at least
-- NEIGHBOUR_CLEARANCE (flat, to the piece's oriented box) from that arena's FightOrigin: a fight only fades its own
-- arena's pieces. Scenery placed round the back of a stage checks this and yields when it would crowd a neighbour.
function ArenaKit.clearOfNeighbours(def: ArenaDef, root: Instance): boolean
	local parts: { Instance } = if root:IsA("BasePart") then { root } else root:GetDescendants()
	for _, other in Layout.ARENAS do
		if other.id ~= def.id then
			for _, d in parts do
				if d:IsA("BasePart") then
					local _, ey = horizontalExtents(d.CFrame, d.Size)
					if d.CFrame.Y + ey > other.origin.Y + Layout.OCCLUDER_HEIGHT and boxFlatDistance(d, other.origin) < Layout.NEIGHBOUR_CLEARANCE + 0.5 then
						return false
					end
				end
			end
		end
	end
	return true
end

-- Whether nothing of `root` rises inside the flat fight floor's radius (FLOOR_CLEAR_RADIUS; only the edge barrier
-- stands near the fight). Spreading scenery (trees) checks this and is regrown or moved out when it would.
function ArenaKit.clearOfFightFloor(def: ArenaDef, root: Instance): boolean
	local parts: { Instance } = if root:IsA("BasePart") then { root } else root:GetDescendants()
	for _, d in parts do
		if d:IsA("BasePart") and d.Transparency < 0.99 then
			local _, ey = horizontalExtents(d.CFrame, d.Size)
			local rises = d.CFrame.Y + ey > def.origin.Y + 0.3 and d.CFrame.Y - ey < def.origin.Y + 12
			if rises and boxFlatDistance(d, def.origin) < Layout.FLOOR_CLEAR_RADIUS + 0.3 then
				return false
			end
		end
	end
	return true
end

return ArenaKit
