--!strict
-- World.Kit: fast helpers for building anchored world geometry from code (parts, lights, particles, signs).
-- Every helper parents immediately (callers build into unparented Models) and counts what it made so the builder
-- can report budgets. Kit.step() yields when the current slice ran long, keeping the server responsive.
local CollectionService = game:GetService("CollectionService")

local Kit = {}

Kit.OCCLUDER_TAG = "FightingLabCameraOccluder"
-- client-side life (LobbyAmbience): world-specific tags so stage code never double-animates them
Kit.TAG_BLINK = "FightingLabWorldBlink"
Kit.TAG_FLICKER = "FightingLabWorldFlicker"
Kit.TAG_SPIN = "FightingLabWorldSpin"
Kit.TAG_PAD_GLOW = "FightingLabPadGlow"
Kit.TAG_PAD_COLUMN = "FightingLabPadColumn"

export type Props = { [string]: any }

local stats = { parts = 0, lights = 0, emitters = 0, guis = 0, beams = 0 }
Kit.stats = stats

-- Keep-out circles (XZ) registered while the world builds: walkway edges, pocket furniture, stage podiums, status
-- boards and landmarks. Scenery placed later (trees, pines, ruined pillars, the forests) asks Kit.clearSpot first,
-- so nothing ever grows through a wall, a bench or a sign. Kit.reset clears the list.
local keepOuts: { { x: number, z: number, r: number } } = {}

function Kit.keepOut(p: Vector3, radius: number)
	table.insert(keepOuts, { x = p.X, z = p.Z, r = radius })
end

-- Whether a footprint of `radius` at `p` stays clear of every registered keep-out circle.
function Kit.clearSpot(p: Vector3, radius: number): boolean
	for _, k in keepOuts do
		local dx, dz = p.X - k.x, p.Z - k.z
		local reach = k.r + radius
		if dx * dx + dz * dz < reach * reach then
			return false
		end
	end
	return true
end

-- Work is done in slices; between slices the builder yields one frame so the server keeps ticking.
local SLICE = 0.06
local lastYield = os.clock()
local busy = 0 -- seconds of actual build work (excludes time spent yielded)

local SMOOTH = Enum.SurfaceType.Smooth
local QUARTER = math.pi / 2
local UPRIGHT = CFrame.Angles(0, 0, QUARTER) -- cylinder axis (local X) -> world Y

function Kit.reset()
	for k in stats do
		stats[k] = 0
	end
	table.clear(keepOuts)
	lastYield = os.clock()
	busy = 0
end

-- Seconds of build work since reset (wall time minus yields).
function Kit.busySeconds(): number
	return busy + (os.clock() - lastYield)
end

function Kit.step()
	local now = os.clock()
	if now - lastYield > SLICE then
		busy += now - lastYield
		task.wait()
		lastYield = os.clock()
	end
end

-- Yield one frame now (between big sections), accounting the work done so far.
function Kit.yield()
	busy += os.clock() - lastYield
	task.wait()
	lastYield = os.clock()
end

local function finish(p: any, parent: Instance, props: Props?): any
	if props then
		for k, v in props do
			p[k] = v
		end
	end
	p.Parent = parent
	stats.parts += 1
	if stats.parts % 150 == 0 then
		Kit.step()
	end
	return p
end

local function base(p: any, cf: CFrame, size: Vector3, material: Enum.Material, color: Color3): any
	p.Anchored = true
	p.TopSurface = SMOOTH
	p.BottomSurface = SMOOTH
	p.Size = size
	p.CFrame = cf
	p.Material = material
	p.Color = color
	return p
end

-- Solid, walkable/colliding block.
function Kit.block(parent: Instance, cf: CFrame, size: Vector3, material: Enum.Material, color: Color3, props: Props?): Part
	return finish(base(Instance.new("Part"), cf, size, material, color), parent, props)
end

-- Non-colliding decoration (no touch/query cost). Small pieces skip shadows.
function Kit.deco(parent: Instance, cf: CFrame, size: Vector3, material: Enum.Material, color: Color3, props: Props?): Part
	local p = base(Instance.new("Part"), cf, size, material, color)
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	if size.X * size.Y * size.Z < 6 or math.min(size.X, size.Y, size.Z) < 0.15 then
		p.CastShadow = false
	end
	return finish(p, parent, props)
end

-- Neon strip / glowing panel: non-colliding, no shadow.
function Kit.glow(parent: Instance, cf: CFrame, size: Vector3, color: Color3, props: Props?): Part
	local p = base(Instance.new("Part"), cf, size, Enum.Material.Neon, color)
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	return finish(p, parent, props)
end

function Kit.wedge(parent: Instance, cf: CFrame, size: Vector3, material: Enum.Material, color: Color3, props: Props?): WedgePart
	return finish(base(Instance.new("WedgePart"), cf, size, material, color), parent, props)
end

function Kit.cornerWedge(parent: Instance, cf: CFrame, size: Vector3, material: Enum.Material, color: Color3, props: Props?): CornerWedgePart
	return finish(base(Instance.new("CornerWedgePart"), cf, size, material, color), parent, props)
end

-- Upright cylinder centred at cf (cf's Y axis becomes the cylinder axis).
function Kit.cylinder(parent: Instance, cf: CFrame | Vector3, height: number, diameter: number, material: Enum.Material, color: Color3, props: Props?): Part
	local frame = if typeof(cf) == "Vector3" then CFrame.new(cf) else cf
	local p = base(Instance.new("Part"), frame * UPRIGHT, Vector3.new(height, diameter, diameter), material, color)
	p.Shape = Enum.PartType.Cylinder
	return finish(p, parent, props)
end

-- Cylinder spanning two points.
function Kit.rod(parent: Instance, a: Vector3, b: Vector3, diameter: number, material: Enum.Material, color: Color3, props: Props?): Part
	local mid = (a + b) / 2
	local length = (b - a).Magnitude
	local cf = CFrame.lookAt(mid, b) * CFrame.Angles(0, QUARTER, 0)
	local p = base(Instance.new("Part"), cf, Vector3.new(length, diameter, diameter), material, color)
	p.Shape = Enum.PartType.Cylinder
	return finish(p, parent, props)
end

-- Box spanning two points (width x height cross-section).
function Kit.strut(parent: Instance, a: Vector3, b: Vector3, width: number, height: number, material: Enum.Material, color: Color3, props: Props?): Part
	local mid = (a + b) / 2
	local length = (b - a).Magnitude
	local up = if math.abs((b - a).Unit.Y) > 0.98 then Vector3.xAxis else Vector3.yAxis
	local cf = CFrame.lookAt(mid, b, up)
	return finish(base(Instance.new("Part"), cf, Vector3.new(width, height, length), material, color), parent, props)
end

function Kit.ball(parent: Instance, pos: Vector3, diameter: number, material: Enum.Material, color: Color3, props: Props?): Part
	local p = base(Instance.new("Part"), CFrame.new(pos), Vector3.new(diameter, diameter, diameter), material, color)
	p.Shape = Enum.PartType.Ball
	return finish(p, parent, props)
end

-- Ellipsoid (sphere mesh stretched to the part size): foliage, rocks, clouds. Decoration only.
function Kit.blob(parent: Instance, cf: CFrame, size: Vector3, material: Enum.Material, color: Color3, props: Props?): Part
	local p = base(Instance.new("Part"), cf, size, material, color)
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return finish(p, parent, props)
end

function Kit.model(parent: Instance?, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	if parent then
		m.Parent = parent
	end
	return m
end

function Kit.folder(parent: Instance?, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	if parent then
		f.Parent = parent
	end
	return f
end

function Kit.tag(inst: Instance, tag: string)
	CollectionService:AddTag(inst, tag)
end

-- Lights ---------------------------------------------------------------------------------------------------------

function Kit.point(parent: Instance, color: Color3, brightness: number, range: number, shadows: boolean?): PointLight
	local l = Instance.new("PointLight")
	l.Color = color
	l.Brightness = brightness
	l.Range = range
	l.Shadows = shadows == true
	l.Parent = parent
	stats.lights += 1
	return l
end

function Kit.spot(parent: Instance, face: Enum.NormalId, color: Color3, brightness: number, range: number, angle: number, shadows: boolean?): SpotLight
	local l = Instance.new("SpotLight")
	l.Face = face
	l.Color = color
	l.Brightness = brightness
	l.Range = range
	l.Angle = angle
	l.Shadows = shadows == true
	l.Parent = parent
	stats.lights += 1
	return l
end

function Kit.surfaceLight(parent: Instance, face: Enum.NormalId, color: Color3, brightness: number, range: number, angle: number): SurfaceLight
	local l = Instance.new("SurfaceLight")
	l.Face = face
	l.Color = color
	l.Brightness = brightness
	l.Range = range
	l.Angle = angle
	l.Shadows = false
	l.Parent = parent
	stats.lights += 1
	return l
end

-- Particles ------------------------------------------------------------------------------------------------------

function Kit.emitter(parent: Instance, props: Props): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.LightInfluence = 0
	e.LockedToPart = false
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = parent
	stats.emitters += 1
	return e
end

function Kit.numbers(...: number): NumberSequence
	local values = { ... }
	if #values == 1 then
		return NumberSequence.new(values[1])
	end
	local keys = {}
	for i, v in values do
		table.insert(keys, NumberSequenceKeypoint.new((i - 1) / (#values - 1), v))
	end
	return NumberSequence.new(keys)
end

function Kit.colors(a: Color3, b: Color3?): ColorSequence
	return if b then ColorSequence.new(a, b) else ColorSequence.new(a)
end

-- Vertical light column between two attachments (always faces the camera, scrolls slowly).
function Kit.lightColumn(parent: BasePart, bottom: Vector3, height: number, width: number, color: Color3, transparency: number?): Beam
	local a0 = Instance.new("Attachment")
	a0.Name = "ColumnBottom"
	a0.Parent = parent
	a0.Position = parent.CFrame:PointToObjectSpace(bottom)
	local a1 = Instance.new("Attachment")
	a1.Name = "ColumnTop"
	a1.Parent = parent
	a1.Position = parent.CFrame:PointToObjectSpace(bottom + Vector3.new(0, height, 0))
	local b = Instance.new("Beam")
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.Color = ColorSequence.new(color)
	b.LightEmission = 1
	b.LightInfluence = 0
	b.FaceCamera = true
	b.Segments = 1
	b.Width0 = width
	b.Width1 = width * 0.92
	local t = transparency or 0.55
	b.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, t),
		NumberSequenceKeypoint.new(0.55, math.min(1, t + 0.28)),
		NumberSequenceKeypoint.new(1, 1),
	})
	b.Parent = parent
	stats.beams += 1
	return b
end

-- Signage --------------------------------------------------------------------------------------------------------

export type LabelOpts = {
	font: Enum.Font?,
	color: Color3?,
	stroke: Color3?,
	strokeTransparency: number?,
	background: Color3?,
	backgroundTransparency: number?,
	pps: number?,
	light: number?,
	brightness: number?,
	align: Enum.TextXAlignment?,
	padding: number?,
	name: string?,
	maxDistance: number?,
	textSize: number?,
}

function Kit.label(part: BasePart, face: Enum.NormalId, text: string, opts: LabelOpts?): SurfaceGui
	local o: LabelOpts = opts or {}
	local g = Instance.new("SurfaceGui")
	g.Name = o.name or "Sign"
	g.Face = face
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = o.pps or 40
	g.LightInfluence = o.light or 0
	g.Brightness = o.brightness or 1.2
	g.MaxDistance = o.maxDistance or 900
	g.ClipsDescendants = true
	g.ResetOnSpawn = false
	local t = Instance.new("TextLabel")
	t.Name = "Text"
	t.BackgroundColor3 = o.background or Color3.new(0, 0, 0)
	t.BackgroundTransparency = if o.background then (o.backgroundTransparency or 0) else 1
	t.BorderSizePixel = 0
	local pad = o.padding or 0.08
	t.Size = UDim2.fromScale(1 - pad * 2, 1 - pad * 2)
	t.Position = UDim2.fromScale(pad, pad)
	t.Font = o.font or Enum.Font.GothamBlack
	t.Text = text
	if o.textSize then
		-- fixed size, no wrapping (TextScaled always wraps, which can split long words)
		t.TextScaled = false
		t.TextWrapped = false
		t.TextSize = o.textSize
	else
		t.TextScaled = true
	end
	t.TextColor3 = o.color or Color3.new(1, 1, 1)
	t.TextXAlignment = o.align or Enum.TextXAlignment.Center
	t.RichText = true
	if o.stroke then
		t.TextStrokeColor3 = o.stroke
		t.TextStrokeTransparency = o.strokeTransparency or 0.2
	end
	t.Parent = g
	g.Parent = part
	stats.guis += 1
	return g
end

-- Geometry helpers ---------------------------------------------------------------------------------------------

-- Calls fn(i, angle, unitDir) for n evenly spaced angles (radians, bearing-style: 0 = -Z, clockwise from above).
function Kit.around(n: number, offset: number?, fn: (number, number, Vector3) -> ())
	for i = 1, n do
		local a = (offset or 0) + (i - 1) / n * math.pi * 2
		fn(i, a, Vector3.new(math.sin(a), 0, -math.cos(a)))
	end
end

-- Rotation that points a part's -Z (LookVector) along a flat direction.
function Kit.facing(pos: Vector3, dir: Vector3): CFrame
	return CFrame.lookAt(pos, pos + Vector3.new(dir.X, 0, dir.Z))
end

-- Deterministic pseudo-random generator so the world looks the same every server start.
function Kit.rng(seed: number): Random
	return Random.new(seed)
end

function Kit.shade(c: Color3, f: number): Color3
	return Color3.new(math.clamp(c.R * f, 0, 1), math.clamp(c.G * f, 0, 1), math.clamp(c.B * f, 0, 1))
end

function Kit.mix(a: Color3, b: Color3, t: number): Color3
	return a:Lerp(b, t)
end

return Kit
