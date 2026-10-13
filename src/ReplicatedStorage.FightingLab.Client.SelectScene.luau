--!strict
-- Fighter showcase studio (OV6). A local-only, light-tight studio built far from the map: a dark set with a lit
-- platform, accent light blades and the fighter's name written huge on the back wall. FighterSelect places pooled
-- preview rigs (CharacterPresenter.acquirePreview / posePreview) on the platform and flies the camera here.
-- Nothing is created on require; the studio is built once on first use and parented only while it is shown.
-- The legacy SelectScene API (init/showCharacter/showStage/showVS/hide/update/isActive/debugInstanceCount) is kept.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Lab = ReplicatedStorage:WaitForChild("FightingLab")
local Roster = require(Lab:WaitForChild("Roster"))

type Ctx = any
local M = {}
local ctx: Ctx? = nil

-- Studio placement: well outside the map and the arenas, above the fall height.
M.ORIGIN = Vector3.new(0, 900, 3200)
M.PLATFORM_TOP = 0.42
M.CAMERA_DISTANCE = 14
M.CAMERA_FOV = 29
M.LOOK_HEIGHT = 3.15
M.SCREEN_X = 0.6 -- where the fighter stands on screen (0..1: info column on the left, roster grid on the right)
M.FACING_YAW = -20 -- degrees the fighter turns toward the info column

type Studio = {
	model: Model, accentParts: { BasePart }, blades: { BasePart }, beams: { Beam }, keyLight: SpotLight, rims: { SpotLight },
	fill: PointLight, uplight: PointLight, wash: SpotLight, nameLabel: TextLabel, nameStroke: UIStroke, dust: ParticleEmitter,
	ring: BasePart, halo: BasePart, levels: { [Instance]: number }, accent: Color3,
}
local studio: Studio? = nil
local shown = false
local activeKind = ""
local created = 0

local function c(): Ctx
	local v = ctx
	if not v then error("SelectScene.init first") end
	return v
end

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, props: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Name = name; p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = true
	p.Size = size; p.CFrame = cf; p.Color = color; p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	if props then for k, v in props do (p :: any)[k] = v end end
	p.Parent = parent
	created += 1
	return p
end

local function cylinder(parent: Instance, name: string, diameter: number, height: number, center: Vector3, color: Color3, material: Enum.Material, props: { [string]: any }?): Part
	-- Roblox cylinders run along X: rotate so the flat faces point up.
	return part(parent, name, Vector3.new(height, diameter, diameter), CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)), color, material, props)
end

local function build(): Studio
	local existing = studio
	if existing then return existing end
	local o = M.ORIGIN
	local model = Instance.new("Model")
	model.Name = "FightingLabShowcase"
	created += 1
	local floorColor = Color3.fromRGB(14, 16, 22)
	local wallColor = Color3.fromRGB(9, 10, 15)
	-- Light-tight room (no sky, no sun): floor, ceiling and four walls.
	part(model, "Floor", Vector3.new(90, 1, 90), CFrame.new(o + Vector3.new(0, -0.5, 0)), floorColor, Enum.Material.Marble, { Reflectance = 0.12 })
	part(model, "Ceiling", Vector3.new(90, 1, 90), CFrame.new(o + Vector3.new(0, 30.5, 0)), wallColor, Enum.Material.SmoothPlastic)
	part(model, "WallBack", Vector3.new(90, 32, 1), CFrame.new(o + Vector3.new(0, 15, -14)), wallColor, Enum.Material.SmoothPlastic)
	part(model, "WallFront", Vector3.new(90, 32, 1), CFrame.new(o + Vector3.new(0, 15, 45)), wallColor, Enum.Material.SmoothPlastic)
	part(model, "WallLeft", Vector3.new(1, 32, 90), CFrame.new(o + Vector3.new(-45, 15, 0)), wallColor, Enum.Material.SmoothPlastic)
	part(model, "WallRight", Vector3.new(1, 32, 90), CFrame.new(o + Vector3.new(45, 15, 0)), wallColor, Enum.Material.SmoothPlastic)
	-- Backdrop: a panel carrying the giant outlined name (self-lit), with an accent "slash" of light in front of it.
	local backdrop = part(model, "Backdrop", Vector3.new(60, 26, 0.4), CFrame.new(o + Vector3.new(0, 12, -11)), Color3.fromRGB(30, 32, 42), Enum.Material.SmoothPlastic)
	local surface = Instance.new("SurfaceGui")
	-- The camera looks toward -Z, so it sees the backdrop's +Z (Back) face; GUI x runs from world -X to +X.
	surface.Name = "NameWall"; surface.Face = Enum.NormalId.Back; surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 24; surface.LightInfluence = 0; surface.Brightness = 1.4; surface.Parent = backdrop
	local nameLabel = Instance.new("TextLabel")
	-- Centred a little right of the fighter at chest height (world x ~ +1, y ~ 4.6), big enough to run behind him.
	nameLabel.Name = "Name"; nameLabel.BackgroundTransparency = 1; nameLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	nameLabel.Position = UDim2.fromScale(0.52, 0.79); nameLabel.Size = UDim2.fromScale(0.56, 0.42)
	nameLabel.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy, Enum.FontStyle.Italic)
	nameLabel.TextScaled = true; nameLabel.TextColor3 = Color3.fromRGB(255, 200, 69); nameLabel.TextTransparency = 0.93
	nameLabel.Text = ""; nameLabel.Parent = surface
	local nameStroke = Instance.new("UIStroke")
	nameStroke.Thickness = 5; nameStroke.Color = Color3.fromRGB(255, 200, 69); nameStroke.Transparency = 0.52
	nameStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual; nameStroke.LineJoinMode = Enum.LineJoinMode.Miter; nameStroke.Parent = nameLabel
	created += 3
	local accentParts: { BasePart } = {}
	local blades: { BasePart } = {}
	-- The slash: a faint wide band and two thin parallel streaks cutting up and to the right behind the fighter.
	local slashTilt = CFrame.Angles(0, 0, math.rad(58))
	for _, spec in { { "SlashBand", 0, 3.4, 0.94 }, { "SlashA", -2.1, 0.07, 0.42 }, { "SlashB", 2.0, 0.035, 0.58 } } do
		local name, offset, width, base = spec[1] :: string, spec[2] :: number, spec[3] :: number, spec[4] :: number
		local cf = CFrame.new(o + Vector3.new(2.4, 6.2, -10.5)) * slashTilt * CFrame.new(0, offset, 0)
		local p = part(model, name, Vector3.new(40, width, 0.04), cf, Color3.fromRGB(255, 200, 69), Enum.Material.Neon, { CastShadow = false, Transparency = base })
		p:SetAttribute("Base", base)
		table.insert(blades, p)
		table.insert(accentParts, p)
	end
	-- Round 6: two tall light pillars framing the fighter, and a thin floor line running to each.
	for _, sx in { -1, 1 } do
		local pillar = part(model, "Pillar" .. (if sx < 0 then "L" else "R"), Vector3.new(0.18, 20, 0.18), CFrame.new(o + Vector3.new(sx * 6.4, 10, -6.5)), Color3.fromRGB(255, 200, 69), Enum.Material.Neon, { CastShadow = false, Transparency = 0.15 })
		pillar:SetAttribute("Base", 0.15)
		table.insert(accentParts, pillar)
		local line = part(model, "PillarLine" .. (if sx < 0 then "L" else "R"), Vector3.new(0.08, 0.04, 7), CFrame.new(o + Vector3.new(sx * 6.4, 0.02, -3)), Color3.fromRGB(255, 200, 69), Enum.Material.Neon, { CastShadow = false, Transparency = 0.55 })
		line:SetAttribute("Base", 0.55)
		table.insert(accentParts, line)
	end
	local floorBand = part(model, "FloorBand", Vector3.new(60, 0.04, 0.12), CFrame.new(o + Vector3.new(0, 0.02, -10.2)), Color3.fromRGB(255, 200, 69), Enum.Material.Neon, { CastShadow = false, Transparency = 0.72 })
	floorBand:SetAttribute("Base", 0.72)
	table.insert(accentParts, floorBand)
	-- Platform: dark metal disc on a glowing accent ring, with a soft halo on the floor.
	local halo = cylinder(model, "Halo", 15, 0.02, o + Vector3.new(0, 0.012, 0), Color3.fromRGB(255, 200, 69), Enum.Material.Neon, { CastShadow = false, Transparency = 0.92 })
	halo:SetAttribute("Base", 0.92)
	local ring = cylinder(model, "Ring", 9.7, M.PLATFORM_TOP - 0.06, o + Vector3.new(0, (M.PLATFORM_TOP - 0.06) * 0.5, 0), Color3.fromRGB(255, 200, 69), Enum.Material.Neon, { CastShadow = false, Transparency = 0.3 })
	ring:SetAttribute("Base", 0.3)
	cylinder(model, "Platform", 9.1, M.PLATFORM_TOP, o + Vector3.new(0, M.PLATFORM_TOP * 0.5, 0), Color3.fromRGB(26, 29, 38), Enum.Material.Metal, { Reflectance = 0.05 })
	cylinder(model, "PlatformInset", 7.4, 0.02, o + Vector3.new(0, M.PLATFORM_TOP + 0.005, 0), Color3.fromRGB(20, 22, 30), Enum.Material.Slate)
	table.insert(accentParts, halo)
	table.insert(accentParts, ring)
	-- Lights.
	local function rig(name: string, pos: Vector3, target: Vector3): Part
		return part(model, name, Vector3.new(0.2, 0.2, 0.2), CFrame.lookAt(o + pos, o + target), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, { Transparency = 1, CastShadow = false })
	end
	local keyRig = rig("KeyRig", Vector3.new(-7, 10, 9), Vector3.new(0, 3.2, 0))
	local keyLight = Instance.new("SpotLight")
	keyLight.Name = "Key"; keyLight.Brightness = 3.6; keyLight.Range = 32; keyLight.Angle = 42; keyLight.Shadows = true
	keyLight.Color = Color3.fromRGB(255, 238, 220); keyLight.Face = Enum.NormalId.Front; keyLight.Parent = keyRig
	local rims: { SpotLight } = {}
	for _, side in { -1, 1 } do
		local r = rig("RimRig" .. side, Vector3.new(side * 5.5, 8, -6.5), Vector3.new(0, 3.6, 0))
		local rim = Instance.new("SpotLight")
		rim.Name = "Rim"; rim.Brightness = 7; rim.Range = 20; rim.Angle = 55; rim.Shadows = false
		rim.Color = Color3.fromRGB(255, 200, 69); rim.Face = Enum.NormalId.Front; rim.Parent = r
		table.insert(rims, rim)
	end
	local fillRig = rig("FillRig", Vector3.new(7, 4.5, 10), Vector3.new(0, 3, 0))
	local fill = Instance.new("PointLight")
	fill.Name = "Fill"; fill.Brightness = 0.6; fill.Range = 22; fill.Color = Color3.fromRGB(170, 190, 255); fill.Parent = fillRig
	local upRig = rig("UpRig", Vector3.new(0, 0.9, 1.5), Vector3.new(0, 4, 0))
	local uplight = Instance.new("PointLight")
	uplight.Name = "Up"; uplight.Brightness = 1.1; uplight.Range = 9; uplight.Color = Color3.fromRGB(255, 200, 69); uplight.Parent = upRig
	local washRig = rig("WashRig", Vector3.new(0, 0.5, -6), Vector3.new(0, 14, -11))
	local wash = Instance.new("SpotLight")
	wash.Name = "Wash"; wash.Brightness = 2.2; wash.Range = 22; wash.Angle = 80; wash.Face = Enum.NormalId.Front
	wash.Color = Color3.fromRGB(255, 200, 69); wash.Parent = washRig
	created += 6
	-- Light shafts from the ceiling onto the platform, and slow dust in them.
	local beams: { Beam } = {}
	for i, x in { -2.2, 2.2 } do
		local top = part(model, "ShaftTop" .. i, Vector3.new(0.2, 0.2, 0.2), CFrame.new(o + Vector3.new(x * 1.6, 22, -3)), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, { Transparency = 1, CastShadow = false })
		local a0 = Instance.new("Attachment"); a0.Parent = top
		local bottom = part(model, "ShaftBottom" .. i, Vector3.new(0.2, 0.2, 0.2), CFrame.new(o + Vector3.new(x * 0.4, 0.4, 0)), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, { Transparency = 1, CastShadow = false })
		local a1 = Instance.new("Attachment"); a1.Parent = bottom
		local beam = Instance.new("Beam")
		beam.Attachment0 = a0; beam.Attachment1 = a1; beam.Width0 = 2.5; beam.Width1 = 7; beam.FaceCamera = true
		beam.LightEmission = 1; beam.LightInfluence = 0; beam.Segments = 1
		beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.97), NumberSequenceKeypoint.new(0.6, 0.93), NumberSequenceKeypoint.new(1, 1) })
		beam.Color = ColorSequence.new(Color3.fromRGB(255, 230, 190)); beam.Parent = top
		table.insert(beams, beam)
		created += 3
	end
	local dustRig = part(model, "Dust", Vector3.new(10, 6, 6), CFrame.new(o + Vector3.new(0, 5, -1)), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, { Transparency = 1, CastShadow = false })
	local dust = Instance.new("ParticleEmitter")
	dust.Name = "Motes"; dust.Rate = 7; dust.Lifetime = NumberRange.new(5, 8); dust.Speed = NumberRange.new(0.1, 0.35)
	dust.SpreadAngle = Vector2.new(180, 180); dust.Size = NumberSequence.new(0.06); dust.LightEmission = 1; dust.LightInfluence = 0
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.45), NumberSequenceKeypoint.new(1, 1) })
	dust.Color = ColorSequence.new(Color3.fromRGB(255, 220, 160)); dust.Parent = dustRig
	created += 1
	local s: Studio = {
		model = model, accentParts = accentParts, blades = blades, beams = beams, keyLight = keyLight, rims = rims, fill = fill,
		uplight = uplight, wash = wash, nameLabel = nameLabel, nameStroke = nameStroke, dust = dust, ring = ring, halo = halo,
		levels = {}, accent = Color3.fromRGB(255, 200, 69),
	}
	for _, light in { keyLight, rims[1], rims[2], fill, uplight, wash } do s.levels[light] = (light :: any).Brightness end
	studio = s
	return s
end

-- Shows the studio (parents it into the Workspace).
function M.open()
	local s = build()
	s.model.Parent = workspace
	shown = true
	activeKind = "Showcase"
end

-- Hides the studio (unparents it; it is rebuilt never, reused next time).
function M.close()
	local s = studio
	if s then s.model.Parent = nil end
	shown = false
	activeKind = ""
end

function M.studioModel(): Model? return if studio then studio.model else nil end

-- World CFrame for the fighter's root on the platform: facing the camera, turned by FACING_YAW toward the info column.
function M.fighterFrame(): CFrame
	local o = M.ORIGIN
	local toCamera = Vector3.new(0, 0, 1)
	local facing = CFrame.Angles(0, math.rad(M.FACING_YAW), 0):VectorToWorldSpace(toCamera)
	local p = o + Vector3.new(0, M.PLATFORM_TOP, 0)
	return CFrame.lookAt(p, p + facing)
end

function M.platformY(): number return M.ORIGIN.Y + M.PLATFORM_TOP end

-- Camera CFrame and FOV for the showcase. `push` (0..1) pulls the camera in for intros/confirms; `t` drives a slow
-- sway. The look target is shifted so the fighter lands at SCREEN_X whatever the aspect ratio.
-- `height` (optional, studs above the platform) fits the shot to the shown fighter: the whole body stays in frame at
-- rest (tall fighters get a slightly wider shot instead of a cropped head) and a push ends on the head and chest.
function M.cameraFor(t: number, aspect: number, push: number?, height: number?): (CFrame, number)
	local o = M.ORIGIN
	local k = math.clamp(push or 0, 0, 1)
	local fov = M.CAMERA_FOV - k * 3
	local baseDistance, lookY = M.CAMERA_DISTANCE, M.LOOK_HEIGHT + k * 0.5
	if typeof(height) == "number" and height > 1 then
		local h = math.clamp(height, 3, 12)
		local tan0 = math.tan(math.rad(M.CAMERA_FOV) * 0.5)
		local half = (h + 1.4) * 0.5
		baseDistance = math.clamp(half / tan0, M.CAMERA_DISTANCE - 1, M.CAMERA_DISTANCE + 3)
		local view0 = baseDistance * tan0
		local top = M.PLATFORM_TOP + h
		local rest = if view0 >= half then M.PLATFORM_TOP - 0.9 + half else top + 0.5 - view0
		local view1 = baseDistance * 0.61 * math.tan(math.rad(M.CAMERA_FOV - 3) * 0.5)
		lookY = rest + (top + 0.35 - view1 - rest) * k
	end
	local distance = baseDistance * (1 - k * 0.39)
	local yaw = math.rad(math.sin(t * 0.7) * 2.2 + 3)
	local bob = math.sin(t * 0.9) * 0.06
	local target = o + Vector3.new(0, lookY + bob, 0)
	local dir = CFrame.Angles(0, yaw, 0):VectorToWorldSpace(Vector3.new(0, 0, 1))
	local eye = target + dir * distance + Vector3.new(0, -0.1 - k * 0.2, 0)
	local cf = CFrame.lookAt(eye, target)
	-- Shift the view so the fighter sits right of centre (the info column takes the left).
	local halfW = distance * math.tan(math.rad(fov) * 0.5) * math.max(aspect, 0.5)
	local shift = (M.SCREEN_X - 0.5) * 2 * halfW
	cf = cf - cf.RightVector * shift
	return cf, fov
end

-- Accent colour of the highlighted fighter: blades, ring, rims, wash and the name wall.
function M.setAccent(color: Color3)
	local s = build()
	s.accent = color
	for _, p in s.accentParts do p.Color = color end
	for _, rim in s.rims do rim.Color = color end
	s.wash.Color = color
	s.uplight.Color = color
	s.nameLabel.TextColor3 = color
	s.nameStroke.Color = color
	s.dust.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.6))
end

function M.setName(name: string)
	local s = build()
	s.nameLabel.Text = string.upper(name)
end

-- 0 = dark (cut between fighters), 1 = full show lighting, >1 = flash (confirm).
function M.setLevel(level: number)
	local s = studio
	if not s then return end
	for light, base in s.levels do (light :: any).Brightness = base * math.max(0, level) end
	local glow = math.clamp(level, 0, 1)
	for _, p in s.accentParts do
		local base = p:GetAttribute("Base")
		local b = if typeof(base) == "number" then base else 0.25
		p.Transparency = 1 - (1 - b) * glow
	end
	s.nameLabel.TextTransparency = 1 - 0.07 * glow
	s.nameStroke.Transparency = 1 - 0.48 * glow
end

function M.debugInstanceCount(): number return created end
function M.isActive(): boolean return shown end

--------------------------------------------------------------------------------------------------------------------
-- Legacy API (kept for tools and ClientModules_Test). FighterSelect drives the showcase directly.
--------------------------------------------------------------------------------------------------------------------
function M.init(newCtx: Ctx) ctx = newCtx end
function M.showCharacter(id: string?)
	local def = if typeof(id) == "string" and Roster.has(id) then Roster.get(id) else nil
	M.open()
	if def then M.setAccent(def.accentColor); M.setName(def.displayName) end
end
function M.showStage(_id: string?) M.open() end
function M.showVS(_a: string?, _b: string?) M.open() end
function M.hide() M.close() end
function M.update(_frame: any) end
function M.activeKind(): string return activeKind end

function M._wrapCursor(index: number, count: number): number
	if count <= 0 then return 1 end
	return ((index - 1) % count) + 1
end

-- CPU pick animation: visibly cycles through fighters before landing on `final`.
function M._roulette(start: number, count: number, final: number): { number }
	local seq = {}
	local n = math.max(1, count)
	local spins = n * 2 + ((final - start) % n)
	for i = 0, spins do table.insert(seq, ((start - 1 + i) % n) + 1) end
	if seq[#seq] ~= final then table.insert(seq, final) end
	return seq
end

return M
