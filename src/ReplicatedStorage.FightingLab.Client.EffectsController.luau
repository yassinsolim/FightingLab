--!strict
local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")
local States = require(script.Parent.Motion.States)
local Cinematic = require(script.Parent.Motion.Cinematic)
local Roster = require(script.Parent.Parent.Roster)

type Ctx = any
type RenderFrame = any
type CombatEvent = any
type EmitRig = {
	part: BasePart,
	core: ParticleEmitter,
	sparks: ParticleEmitter,
	dust: ParticleEmitter,
	embers: ParticleEmitter,
	whoosh: ParticleEmitter,
	ring: BasePart,
	activeRingUntil: number,
	ringStarted: number,
	ringBase: number,
	ringColor: Color3,
}
type TrailRecord = { trail: Trail, a0: Attachment, a1: Attachment }
type EffectSpec = { color: Color3, core: number, sparks: number, dust: number, ring: number, life: number, flashAlpha: number, shake: number }

local M = {}
local ctx: Ctx? = nil
local fxFolder: Folder? = nil
local flashFrame: Frame? = nil
local edgeFrame: Frame? = nil
local pool: { EmitRig } = {}
local nextPool = 1
local trails: { [string]: TrailRecord } = {}
local previousStates: { [number]: string } = {}
local impactTrackers: { [number]: any } = {}
local averageCostMs = 0
local activeEmitters = 0
-- Sim positions (event points, fighter positions) are arena space; effects live at origin + position.
local origin = Vector3.zero

local POOL_SIZE = 32
local RING_LIFE = 0.22
local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local FLASH_TEXTURE = "rbxasset://textures/particles/fire_main.dds"
local GLOW_TEXTURE = "rbxasset://textures/particles/glow_05.dds"
-- Round 6 (Surge / Ultimate): built-in engine textures only.
local SHOCKWAVE_TEXTURE = "rbxasset://textures/particles/explosion01_shockwave_main.dds"
local FLAME_TEXTURE = "rbxasset://textures/particles/fire_main.dds"
local GATHER_TEXTURE = "rbxasset://textures/particles/forcefield_glow_main.dds"
local SURGE_GOLD = Color3.fromRGB(255, 196, 92)

local TierSpec: { [string]: EffectSpec } = {
	Light = { color = Color3.fromRGB(130, 235, 255), core = 5, sparks = 12, dust = 0, ring = 1.15, life = 0.09, flashAlpha = 0.9, shake = 0.028 },
	Medium = { color = Color3.fromRGB(255, 205, 105), core = 8, sparks = 24, dust = 1, ring = 1.65, life = 0.13, flashAlpha = 0.84, shake = 0.042 },
	Heavy = { color = Color3.fromRGB(255, 125, 70), core = 11, sparks = 36, dust = 5, ring = 2.25, life = 0.17, flashAlpha = 0.76, shake = 0.058 },
	Launch = { color = Color3.fromRGB(255, 225, 90), core = 14, sparks = 50, dust = 7, ring = 2.95, life = 0.20, flashAlpha = 0.70, shake = 0.072 },
}

function M._poolSize(): number
	return POOL_SIZE
end

local function folder(): Folder
	local f = fxFolder
	assert(f, "EffectsController used before init")
	return f
end

local function configureEmitter(e: ParticleEmitter, color: Color3)
	e.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
end

local function newEmitterRig(): EmitRig
	local part = Instance.new("Part")
	part.Name = "PooledImpact"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.25, 0.25, 0.25)
	part.Parent = folder()

	local core = Instance.new("ParticleEmitter")
	core.Name = "CoreFlash"
	core.Texture = FLASH_TEXTURE
	core.LightEmission = 1
	core.Lifetime = NumberRange.new(0.08, 0.18)
	core.Speed = NumberRange.new(0, 2)
	core.SpreadAngle = Vector2.new(180, 180)
	core.Rate = 0
	core.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.15), NumberSequenceKeypoint.new(0.25, 0.85), NumberSequenceKeypoint.new(1, 0.08) })
	core.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	core.Parent = part

	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "RadialSparks"
	sparks.Texture = SPARK_TEXTURE
	sparks.LightEmission = 0.95
	sparks.Lifetime = NumberRange.new(0.12, 0.26)
	sparks.Speed = NumberRange.new(18, 34)
	sparks.Drag = 8
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Rate = 0
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.20), NumberSequenceKeypoint.new(1, 0.018) })
	sparks.Parent = part

	local dust = Instance.new("ParticleEmitter")
	dust.Name = "DustPuff"
	dust.Texture = SMOKE_TEXTURE
	dust.Color = ColorSequence.new(Color3.fromRGB(180, 165, 140), Color3.fromRGB(70, 65, 60))
	dust.Lifetime = NumberRange.new(0.28, 0.48)
	dust.Speed = NumberRange.new(4, 9)
	dust.Drag = 4
	dust.SpreadAngle = Vector2.new(80, 80)
	dust.Rate = 0
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1.35) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.24), NumberSequenceKeypoint.new(1, 1) })
	dust.Parent = part

	local embers = Instance.new("ParticleEmitter")
	embers.Name = "ImpactEmbers"
	embers.Texture = GLOW_TEXTURE
	embers.LightEmission = 0.95
	embers.Lifetime = NumberRange.new(0.18, 0.34)
	embers.Speed = NumberRange.new(6, 15)
	embers.Drag = 5
	embers.Acceleration = Vector3.new(0, 8, 0)
	embers.SpreadAngle = Vector2.new(130, 130)
	embers.Rate = 0
	embers.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.13), NumberSequenceKeypoint.new(1, 0.01) })
	embers.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	embers.Parent = part

	local whoosh = Instance.new("ParticleEmitter")
	whoosh.Name = "WhooshStreak"
	whoosh.Texture = GLOW_TEXTURE
	whoosh.LightEmission = 0.8
	whoosh.Lifetime = NumberRange.new(0.10, 0.18)
	whoosh.Speed = NumberRange.new(10, 18)
	whoosh.Drag = 10
	whoosh.SpreadAngle = Vector2.new(20, 20)
	whoosh.Rate = 0
	whoosh.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0.05) })
	whoosh.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	whoosh.Parent = part

	local ring = Instance.new("Part")
	ring.Name = "ShockwaveRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Transparency = 1
	ring.Size = Vector3.new(0.035, 0.45, 0.45)
	ring.Parent = folder()
	return { part = part, core = core, sparks = sparks, dust = dust, embers = embers, whoosh = whoosh, ring = ring, activeRingUntil = 0, ringStarted = 0, ringBase = 0.45, ringColor = Color3.new(1, 1, 1) }
end

local function takeRig(): EmitRig
	local rig = pool[nextPool]
	nextPool = (nextPool % #pool) + 1
	return rig
end

local function flash(frame: Frame?, color: Color3, alpha: number, life: number)
	if not frame then return end
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = alpha
	TweenService:Create(frame, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
end

local function emitImpact(point: Vector3, dir: Vector3, spec: EffectSpec)
	local rig = takeRig()
	rig.part.CFrame = CFrame.lookAt(point, point + dir)
	configureEmitter(rig.core, spec.color)
	configureEmitter(rig.sparks, spec.color)
	configureEmitter(rig.whoosh, spec.color)
	configureEmitter(rig.embers, spec.color)
	rig.core.Lifetime = NumberRange.new(math.max(0.05, spec.life * 0.55), spec.life)
	rig.core:Emit(spec.core)
	rig.sparks:Emit(spec.sparks)
	if spec.dust > 0 then rig.dust:Emit(spec.dust) end
	if spec.sparks > 16 then rig.embers:Emit(math.max(3, math.floor(spec.sparks * 0.22))) end
	rig.ringColor = spec.color
	rig.ringStarted = os.clock()
	rig.activeRingUntil = rig.ringStarted + RING_LIFE
	rig.ring.Color = spec.color
	rig.ring.Transparency = 0.45
	rig.ringBase = spec.ring
	rig.ring.Size = Vector3.new(0.035, spec.ring, spec.ring)
	-- Face the disc toward the camera; seen edge-on from the side view it reads as a thin full-height line.
	local cam = workspace.CurrentCamera
	local toCamera = if cam then cam.CFrame.Position - point else -dir
	local axis = Vector3.new(toCamera.X, 0, toCamera.Z)
	rig.ring.CFrame = CFrame.fromMatrix(point, if axis.Magnitude > 0.01 then axis.Unit else dir, Vector3.yAxis)
	activeEmitters += 1
end

local function emitDust(point: Vector3, count: number, scale: number?)
	local rig = takeRig()
	rig.part.CFrame = CFrame.new(point)
	rig.dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.38 * (scale or 1)), NumberSequenceKeypoint.new(1, 1.25 * (scale or 1)) })
	rig.dust:Emit(count)
	activeEmitters += 1
end

local function emitWhoosh(point: Vector3, dir: Vector3, color: Color3, count: number)
	local rig = takeRig()
	rig.part.CFrame = CFrame.lookAt(point, point + dir)
	configureEmitter(rig.whoosh, color)
	rig.whoosh:Emit(count)
	activeEmitters += 1
end

local function root(index: number): BasePart?
	local c = ctx
	if not c then return nil end
	return c.modules.Characters.getRoot(index)
end

local function eventColor(e: CombatEvent): Color3
	local c = ctx
	if c and e.move and c.config.Moves[e.move] then
		return c.config.Moves[e.move].color
	end
	local spec = TierSpec[tostring(e.tier or "Light")]
	return if spec then spec.color else Color3.fromRGB(255, 255, 255)
end

function M._specForEvent(e: CombatEvent): EffectSpec
	local tier = tostring(e.tier or (if e.launch then "Launch" elseif (e.damage or 0) >= 15 then "Heavy" elseif (e.damage or 0) >= 10 then "Medium" else "Light"))
	local spec = TierSpec[tier] or TierSpec.Light
	if e.kind == "UltHit" then
		-- Every Ultimate impact is heavier than any normal hit; the last one (knockdown) is the finish.
		if e.knockdown == true then return { color = Color3.fromRGB(255, 236, 190), core = 24, sparks = 84, dust = 30, ring = 4.8, life = 0.28, flashAlpha = 0.22, shake = 0.095 } end
		return { color = Color3.fromRGB(255, 214, 140), core = 15, sparks = 48, dust = 6, ring = 3.3, life = 0.21, flashAlpha = 0.62, shake = 0.066 }
	end
	if e.kind == "UltStart" then return { color = Color3.fromRGB(255, 244, 220), core = 0, sparks = 0, dust = 0, ring = 0, life = 0.3, flashAlpha = 0.35, shake = 0 } end
	if e.kind == "Surge" then return { color = SURGE_GOLD, core = 0, sparks = 0, dust = 0, ring = 0, life = 0.3, flashAlpha = 0.8, shake = 0.03 } end
	if e.kind == "Block" then return { color = Color3.fromRGB(120, 190, 255), core = 5, sparks = 18, dust = 0, ring = 1.55, life = 0.13, flashAlpha = 0.87, shake = 0.022 } end
	if e.kind == "ThrowStart" then return { color = Color3.fromRGB(170, 245, 255), core = 4, sparks = 10, dust = 0, ring = 1.35, life = 0.12, flashAlpha = 0.92, shake = 0.018 } end
	if e.kind == "ThrowBreak" then return { color = Color3.fromRGB(245, 250, 255), core = 10, sparks = 34, dust = 2, ring = 2.25, life = 0.18, flashAlpha = 0.68, shake = 0.056 } end
	if e.kind == "ThrowHit" then return { color = Color3.fromRGB(255, 190, 110), core = 12, sparks = 34, dust = 18, ring = 3.0, life = 0.20, flashAlpha = 0.70, shake = 0.07 } end
	if e.kind == "Parry" then return { color = Color3.fromRGB(210, 245, 255), core = 11, sparks = 28, dust = 0, ring = 2.45, life = 0.17, flashAlpha = 0.66, shake = 0.04 } end
	if e.kind == "Armor" then return { color = Color3.fromRGB(190, 205, 220), core = 7, sparks = 20, dust = 0, ring = 1.9, life = 0.15, flashAlpha = 0.78, shake = 0.034 } end
	if e.kind == "Crush" or e.kind == "Whiff" then return { color = Color3.fromRGB(180, 170, 255), core = 0, sparks = 0, dust = 0, ring = 0.9, life = 0.12, flashAlpha = 1, shake = 0.012 } end
	if e.kind == "KO" then return { color = Color3.fromRGB(255, 240, 170), core = 18, sparks = 56, dust = 28, ring = 3.5, life = 0.24, flashAlpha = 0.36, shake = 0.09 } end
	if e.counter then return { color = Color3.fromRGB(255, 72, 105), core = spec.core + 4, sparks = spec.sparks + 12, dust = spec.dust, ring = spec.ring + 0.55, life = math.min(0.23, spec.life + 0.04), flashAlpha = math.min(0.72, spec.flashAlpha - 0.12), shake = math.min(0.08, spec.shake + 0.015) } end
	local airScale = if e.air == true and e.launch ~= true then 0.68 else 1
	return { color = eventColor(e), core = math.max(1, math.floor(spec.core * airScale)), sparks = math.max(2, math.floor(spec.sparks * airScale)), dust = spec.dust, ring = spec.ring * (0.86 + 0.14 * airScale), life = spec.life, flashAlpha = spec.flashAlpha, shake = spec.shake * airScale }
end

-- Surge and Ultimate (round 6, docs/design/ultimates.md) -------------------------------------------------------------
-- Surge aura: a fighter with `surge = true` stands in a slowly pulsing floor ring in its own surge colour, with low
-- flames and a few sparks rising to the waist (never past the shoulders: faces stay clear) and a warm light on the
-- body. The Surge event adds a one-time burst; UltStart gathers energy into the attacker under a screen flash; every
-- UltHit bursts at the striking limb, the last one with a floor shockwave and a full-screen flash; the defender's
-- landing inside the cinematic raises dust. Everything lives in FightingLabLocalEffects (never inside the rigs).
type Aura = { base: Part, flames: ParticleEmitter, sparks: ParticleEmitter, rings: ParticleEmitter, burstRing: ParticleEmitter,
	burstFlames: ParticleEmitter, gather: ParticleEmitter, light: PointLight, on: boolean, color: Color3, id: string? }
local auras: { [number]: Aura } = {}
local lastIds: { [number]: string? } = {}
local cineGround: { key: string, last: number }? = nil
M.AuraRates = { flames = 20, sparks = 7, rings = 1.4 }
M.AuraLight = { brightness = 0.9, range = 7 }

local function seq(points: { { number } }): NumberSequence
	local keys = {}
	for _, p in points do table.insert(keys, NumberSequenceKeypoint.new(p[1], p[2])) end
	return NumberSequence.new(keys)
end

-- A fighter's surge colour: its roster accent made bright and saturated (a grey accent becomes an icy blue-white).
function M.surgeColor(id: string?): Color3
	local ok, def = pcall(function() return if type(id) == "string" and Roster.has(id) then Roster.get(id) else nil end)
	local accent = if ok and type(def) == "table" and typeof(def.accentColor) == "Color3" then def.accentColor else SURGE_GOLD
	local h, s = accent:ToHSV()
	if s < 0.3 then return Color3.fromRGB(165, 205, 255) end
	return Color3.fromHSV(h, math.clamp(s, 0.6, 0.85), 1)
end

local function newAura(i: number): Aura
	local base = Instance.new("Part")
	base.Name = "SurgeAura" .. tostring(i)
	base.Anchored, base.CanCollide, base.CanQuery, base.CanTouch, base.CastShadow = true, false, false, false, false
	base.Transparency = 1
	base.Size = Vector3.new(2.2, 0.2, 2.2)
	base.Parent = folder()
	local function emitter(name: string, texture: string): ParticleEmitter
		local e = Instance.new("ParticleEmitter")
		e.Name = name
		e.Texture = texture
		e.LightEmission = 1
		e.LightInfluence = 0
		e.Rate = 0
		e.Enabled = true
		e.EmissionDirection = Enum.NormalId.Top
		e.Parent = base
		return e
	end
	-- Low flames rising from the floor around the feet: ~2.5 studs at most (waist height).
	local flames = emitter("SurgeFlames", FLAME_TEXTURE)
	flames.Lifetime = NumberRange.new(0.42, 0.7)
	flames.Speed = NumberRange.new(2.6, 4.2)
	flames.SpreadAngle = Vector2.new(8, 8)
	flames.Drag = 1.5
	flames.Size = seq({ { 0, 0.55 }, { 0.6, 0.38 }, { 1, 0.05 } })
	flames.Transparency = seq({ { 0, 0.5 }, { 0.25, 0.42 }, { 1, 1 } })
	flames.RotSpeed = NumberRange.new(-40, 40)
	flames.Rotation = NumberRange.new(0, 360)
	local sparks = emitter("SurgeSparks", SPARK_TEXTURE)
	sparks.Lifetime = NumberRange.new(0.3, 0.5)
	sparks.Speed = NumberRange.new(4.5, 7)
	sparks.Drag = 3
	sparks.SpreadAngle = Vector2.new(18, 18)
	sparks.Size = seq({ { 0, 0.16 }, { 1, 0.02 } })
	-- Flat rings on the floor (a particle's plane is perpendicular to its velocity: straight up = flat).
	local rings = emitter("SurgeRings", SHOCKWAVE_TEXTURE)
	rings.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
	rings.Speed = NumberRange.new(0.01)
	rings.Lifetime = NumberRange.new(0.85)
	rings.LockedToPart = true
	rings.Size = seq({ { 0, 1.6 }, { 1, 4.4 } })
	rings.Transparency = seq({ { 0, 0.55 }, { 0.3, 0.6 }, { 1, 1 } })
	local burstRing = emitter("SurgeBurstRing", SHOCKWAVE_TEXTURE)
	burstRing.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
	burstRing.Speed = NumberRange.new(0.01)
	burstRing.Lifetime = NumberRange.new(0.55)
	burstRing.LockedToPart = true
	burstRing.Size = seq({ { 0, 1.2 }, { 1, 10 } })
	burstRing.Transparency = seq({ { 0, 0.2 }, { 1, 1 } })
	local burstFlames = emitter("SurgeBurstFlames", FLAME_TEXTURE)
	burstFlames.Lifetime = NumberRange.new(0.35, 0.6)
	burstFlames.Speed = NumberRange.new(6, 10)
	burstFlames.SpreadAngle = Vector2.new(14, 14)
	burstFlames.Drag = 3
	burstFlames.Size = seq({ { 0, 0.8 }, { 1, 0.1 } })
	burstFlames.Transparency = seq({ { 0, 0.3 }, { 1, 1 } })
	-- UltStart: energy gathering inward into the attacker (spawned on a sphere around it, moving to its centre).
	local gather = emitter("UltGather", GATHER_TEXTURE)
	gather.Shape = Enum.ParticleEmitterShape.Sphere
	gather.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	gather.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	gather.Lifetime = NumberRange.new(0.22, 0.3)
	gather.Speed = NumberRange.new(12, 16)
	gather.Size = seq({ { 0, 0.12 }, { 0.7, 0.35 }, { 1, 0.02 } })
	gather.Transparency = seq({ { 0, 0.6 }, { 0.5, 0.15 }, { 1, 1 } })
	local light = Instance.new("PointLight")
	light.Name = "SurgeLight"
	light.Shadows = false
	light.Enabled = false
	light.Range = M.AuraLight.range
	local lightAt = Instance.new("Attachment")
	lightAt.Name = "SurgeLightAt"
	lightAt.Position = Vector3.new(0, 2.6, 0)
	lightAt.Parent = base
	light.Parent = lightAt
	return { base = base, flames = flames, sparks = sparks, rings = rings, burstRing = burstRing, burstFlames = burstFlames, gather = gather, light = light, on = false, color = SURGE_GOLD, id = nil }
end

local function auraFor(i: number): Aura?
	if not fxFolder then return nil end
	local a = auras[i]
	if a and a.base.Parent then return a end
	a = newAura(i)
	auras[i] = a
	return a
end

local function setAuraColor(a: Aura, id: string?)
	if a.id == id then return end
	a.id = id
	local color = M.surgeColor(id)
	a.color = color
	local hot = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1):Lerp(color, 0.55)), ColorSequenceKeypoint.new(0.35, color), ColorSequenceKeypoint.new(1, color) })
	for _, e in { a.flames, a.burstFlames, a.sparks, a.gather } do e.Color = hot end
	a.rings.Color = ColorSequence.new(color)
	a.burstRing.Color = ColorSequence.new(color)
	a.light.Color = color
end

local function setAura(a: Aura, on: boolean)
	if a.on == on then return end
	a.on = on
	a.flames.Rate = if on then M.AuraRates.flames else 0
	a.sparks.Rate = if on then M.AuraRates.sparks else 0
	a.rings.Rate = if on then M.AuraRates.rings else 0
	a.light.Enabled = on
end

-- Keeps every fighter's aura under its feet; `surge` comes from the render frame.
local function updateAuras(f: RenderFrame)
	local c = ctx
	if not c then return end
	local showing = f.phase ~= "MatchOver" and f.phase ~= "Lobby"
	for i = 1, 2 do
		local r = f.fighters[i]
		local on = showing and r ~= nil and (r :: any).surge == true
		local a = auras[i]
		if on or a then
			a = auraFor(i)
			if a then
				local part = root(i)
				setAuraColor(a, if r and type(r.characterId) == "string" then r.characterId else nil)
				if part then a.base.CFrame = CFrame.new(Vector3.new(part.Position.X, origin.Y + 0.08, part.Position.Z)) end
				setAura(a, on and part ~= nil)
				if a.on then a.light.Brightness = M.AuraLight.brightness * (0.75 + 0.25 * math.sin(f.now * 4.2 + i)) end
			end
		end
	end
	local active = 0
	for _, a in auras do if a.on then active += 1 end end
	c.gui:SetAttribute("SurgeAuras", active)
end

local function limbPoint(i: number, limb: string?): Vector3?
	local c = ctx
	if not c or not limb then return nil end
	local partName = ({ LeftElbow = "LeftLowerArm", RightElbow = "RightLowerArm", LeftKnee = "LeftLowerLeg", RightKnee = "RightLowerLeg",
		LeftShoulder = "LeftUpperArm", RightShoulder = "RightUpperArm", Body = "UpperTorso" } :: { [string]: string })[limb] or limb
	local model = c.modules.Characters.getModel and c.modules.Characters.getModel(i)
	local part = model and model:FindFirstChild(partName, true)
	if part and part:IsA("BasePart") then
		-- Elbows and knees strike with the joint end of the segment.
		if string.find(limb, "Elbow", 1, true) or string.find(limb, "Knee", 1, true) then return part.Position + part.CFrame.UpVector * part.Size.Y * 0.45 end
		return part.Position
	end
	return nil
end

-- The defender's body reaching the floor inside the cinematic (its track's floor-support channel crossing 0.5).
local function updateCinematicGround(f: RenderFrame)
	local aSlot, aId, cineFrame, aView = Cinematic.active(f)
	if not aSlot or not aView then cineGround = nil; return end
	local tc = Cinematic.clip(aId)
	if not tc then return end
	local tl = Cinematic.timeline(aId, aView.throw)
	local g = Cinematic.defenderGround(tc, tl, cineFrame :: number)
	local key = tostring(aId) .. ":" .. tostring(aSlot)
	local prev = cineGround
	if prev and prev.key == key and prev.last < 0.5 and g >= 0.5 then
		local d = f.fighters[3 - aSlot]
		local part = root(3 - aSlot)
		local at = if part then Vector3.new(part.Position.X, origin.Y + 0.1, part.Position.Z) elseif d then origin + Vector3.new(d.pos.X, 0.1, d.pos.Z) else nil
		if at then
			emitDust(at, 30, 1.5)
			local c = ctx
			if c and c.gui:GetAttribute("CameraShakeDisabled") ~= true then c.modules.Camera.impulse(0.05) end
			if c then c.gui:SetAttribute("UltimateLandings", (c.gui:GetAttribute("UltimateLandings") or 0) + 1) end
		end
	end
	cineGround = { key = key, last = g }
end

-- A flat shockwave ring on the floor at a world point (not attached to anyone).
local floorFx: { part: Part, ring: ParticleEmitter }? = nil
local function floorShockwave(at: Vector3, color: Color3, count: number)
	if not fxFolder then return end
	local fx = floorFx
	if not fx or not fx.part.Parent then
		local part = Instance.new("Part")
		part.Name = "FloorShockwave"
		part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch, part.CastShadow = true, false, false, false, false
		part.Transparency = 1
		part.Size = Vector3.new(0.2, 0.2, 0.2)
		part.Parent = folder()
		local ring = Instance.new("ParticleEmitter")
		ring.Name = "ShockRing"
		ring.Texture = SHOCKWAVE_TEXTURE
		ring.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
		ring.EmissionDirection = Enum.NormalId.Top
		ring.Speed = NumberRange.new(0.01)
		ring.Lifetime = NumberRange.new(0.5, 0.65)
		ring.LightEmission = 1
		ring.LightInfluence = 0
		ring.Rate = 0
		ring.Size = seq({ { 0, 1.0 }, { 1, 12 } })
		ring.Transparency = seq({ { 0, 0.15 }, { 1, 1 } })
		ring.Parent = part
		fx = { part = part, ring = ring }
		floorFx = fx
	end
	local f = fx :: { part: Part, ring: ParticleEmitter }
	f.part.CFrame = CFrame.new(at)
	f.ring.Color = ColorSequence.new(color)
	f.ring:Emit(count)
end

local function surgeBurst(i: number)
	local a = auraFor(i)
	local c = ctx
	if not a or not c then return end
	local part = root(i)
	if part then a.base.CFrame = CFrame.new(Vector3.new(part.Position.X, origin.Y + 0.08, part.Position.Z)) end
	a.burstRing:Emit(2)
	a.burstFlames:Emit(36)
	a.sparks:Emit(24)
	flash(edgeFrame, a.color, 0.72, 0.35)
	c.modules.Characters.setFlash(i, 10)
end

local function ultStartBurst(i: number)
	local a = auraFor(i)
	local c = ctx
	if not a or not c then return end
	local part = root(i)
	if part then a.base.CFrame = CFrame.new(Vector3.new(part.Position.X, origin.Y + 0.08, part.Position.Z)) end
	-- Gather on a sphere around the chest (the emitter's sphere is its part: resized for the burst, then restored).
	a.base.Size = Vector3.new(7, 7, 7)
	a.base.CFrame = a.base.CFrame + Vector3.new(0, 2.6, 0)
	a.gather:Emit(46)
	a.base.Size = Vector3.new(2.2, 0.2, 2.2)
	a.base.CFrame = a.base.CFrame - Vector3.new(0, 2.6, 0)
	a.burstRing:Emit(1)
	if part then emitImpact(part.Position + Vector3.new(0, 0.8, 0), Vector3.yAxis, { color = a.color, core = 10, sparks = 30, dust = 4, ring = 3.0, life = 0.26, flashAlpha = 1, shake = 0 }) end
	c.modules.Characters.setFlash(i, 12)
end

function M.onEvent(e: CombatEvent)
	local c = ctx
	if not c then return end
	if e.kind == "Surge" or e.kind == "UltStart" then
		local i = if e.attacker == 2 then 2 else 1
		if e.kind == "Surge" then
			surgeBurst(i)
		else
			ultStartBurst(i)
			flash(flashFrame, Color3.fromRGB(255, 244, 220), 0.35, 0.32)
		end
		if e.kind == "Surge" and c.gui:GetAttribute("CameraShakeDisabled") ~= true then c.modules.Camera.impulse(0.03) end
		if c.modules.Camera.onEvent then c.modules.Camera.onEvent(e) end
		c.gui:SetAttribute("EffectsFired", (c.gui:GetAttribute("EffectsFired") or 0) + 1)
		c.gui:SetAttribute("LastEffectKind", tostring(e.kind))
		return
	end
	local target = root(e.target or 2)
	local attacker = root(e.attacker or 1)
	local anchor = target or attacker
	if not anchor then return end
	local dir = if attacker and target and (target.Position - attacker.Position).Magnitude > 0.01 then (target.Position - attacker.Position).Unit else Vector3.xAxis
	local point = if e.point then origin + e.point else (anchor.Position + Vector3.new(0, if e.kind == "ThrowHit" then 0.5 else 2.3, 0))
	if e.kind == "UltHit" and not e.point then
		-- The Ultimate's impacts burst at the striking limb named by the clip (hits[combo]), else at the chest.
		local info = Cinematic.hitInfo(lastIds[if e.attacker == 2 then 2 else 1], e.combo)
		point = limbPoint(if e.attacker == 2 then 2 else 1, info and info.limb) or point
	end
	local spec = M._specForEvent(e)
	if e.kind == "Whiff" or e.kind == "Crush" then
		emitWhoosh(point, dir, spec.color, 9)
	else
		emitImpact(point, dir, spec)
	end
	if e.kind == "UltHit" and e.knockdown == true then
		-- The finish: a second burst, a column and a floor shockwave under the defender.
		emitImpact(point + dir * 0.4, -dir, spec)
		emitWhoosh(point, Vector3.yAxis, spec.color, 26)
		if target then
			local a = auras[if e.attacker == 2 then 2 else 1]
			floorShockwave(Vector3.new(target.Position.X, origin.Y + 0.08, target.Position.Z), if a then a.color else spec.color, 2)
		end
	end
	if e.launch == true or e.tier == "Launch" then emitWhoosh(point + Vector3.new(0, 0.35, 0), Vector3.yAxis, spec.color, 18) end
	if e.kind == "ThrowHit" or (e.knockdown and e.kind ~= "UltHit") then emitDust(point - Vector3.new(0, 1.9, 0), 24, 1.25) end
	if e.kind == "UltHit" and e.knockdown == true and target then emitDust(Vector3.new(target.Position.X, origin.Y + 0.1, target.Position.Z), 28, 1.5) end
	if e.kind == "KO" then flash(flashFrame, spec.color, spec.flashAlpha, 0.34) elseif e.counter then flash(edgeFrame, spec.color, spec.flashAlpha, 0.18) else flash(flashFrame, spec.color, spec.flashAlpha, spec.life) end
	if e.kind ~= "Whiff" and e.kind ~= "Crush" then c.modules.Characters.setFlash(e.target, if e.kind == "Block" then 2 else 6) end
	if c.gui:GetAttribute("CameraShakeDisabled") ~= true then c.modules.Camera.impulse(spec.shake) end
	if c.modules.Camera.onEvent then c.modules.Camera.onEvent(e) end
	c.gui:SetAttribute("EffectsFired", (c.gui:GetAttribute("EffectsFired") or 0) + 1)
	c.gui:SetAttribute("LastEffectKind", tostring(e.kind))
end

local function clearRoundVisuals()
	for _, rig in pool do
		rig.ring.Transparency = 1
		rig.activeRingUntil = 0
	end
	for _, record in trails do record.trail.Enabled = false end
	for _, a in auras do setAura(a, false) end
	cineGround = nil
	activeEmitters = 0
end

function M.onPhase(old: string, new: string)
	if new == "Ready" or new == "MatchOver" then clearRoundVisuals() end
end

function M.setOrigin(o: Vector3)
	origin = o
end

-- Fight ended: no ring, trail or screen flash may linger into the lobby.
function M.clear()
	clearRoundVisuals()
	for _, record in trails do
		record.trail:Destroy()
		record.a0:Destroy()
		record.a1:Destroy()
	end
	table.clear(trails)
	table.clear(previousStates)
	table.clear(impactTrackers)
	table.clear(lastIds)
	for _, a in auras do a.base:Destroy() end
	table.clear(auras)
	if flashFrame then flashFrame.BackgroundTransparency = 1 end
	if edgeFrame then edgeFrame.BackgroundTransparency = 1 end
end

local function trailKey(i: number, limb: string): string
	return tostring(i) .. ":" .. limb
end

local function ensureTrail(i: number, limb: string): TrailRecord?
	local c = ctx
	if not c then return nil end
	local key = trailKey(i, limb)
	local current = trails[key]
	local part = c.modules.Characters.getLimbPart(i, limb)
	if not part then return nil end
	-- Pooled fight rigs change between fights: a cached trail must sit on the current rig's limb.
	if current and current.trail.Parent == part then return current end
	if current then
		current.trail:Destroy(); current.a0:Destroy(); current.a1:Destroy()
		trails[key] = nil
	end
	local a0 = Instance.new("Attachment")
	a0.Name = "FightingLabTrailA"
	a0.Position = Vector3.new(0, 0.35, 0)
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Name = "FightingLabTrailB"
	a1.Position = Vector3.new(0, -0.35, 0)
	a1.Parent = part
	local trail = Instance.new("Trail")
	trail.Name = "FightingLabMotionTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Enabled = false
	trail.Lifetime = 0.11
	trail.MinLength = 0.05
	trail.LightEmission = 0.78
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.16), NumberSequenceKeypoint.new(1, 1) })
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0.05) })
	trail.Parent = part
	local record = { trail = trail, a0 = a0, a1 = a1 }
	trails[key] = record
	return record
end

local function updateTrails(f: RenderFrame)
	local c = ctx
	if not c then return end
	for i = 1, 2 do
		local r = f.fighters[i]
		if not r or not r.move then continue end
		local move = c.config.Moves[r.move]
		if not move then continue end
		local tr = ensureTrail(i, move.limb)
		if tr then
			local activeWindow = r.moveFrame >= math.max(1, move.startup - 2) and r.moveFrame <= move.startup + move.active + 1
			local tierSpec = TierSpec[tostring(move.tier or "Light")] or TierSpec.Light
			tr.trail.Color = ColorSequence.new(tierSpec.color)
			tr.trail.Enabled = activeWindow
		end
	end
	for key, record in trails do
		local fighterId = tonumber(string.match(key, "^(%d):"))
		local r = if fighterId then f.fighters[fighterId] else nil
		if not r or not r.move then record.trail.Enabled = false end
	end
end

local function updateHitstopJitter(f: RenderFrame)
	if not f.hitstop or f.hitstop <= 0 then return end
	local entry = f.entry
	local frameNumber = if entry then entry.frame else math.floor(f.renderFrame or 0)
	for i = 1, 2 do
		local r = f.fighters[i]
		local lastHit = r and (r :: any).lastHit
		if r and lastHit and typeof(lastHit) == "table" and typeof(lastHit.frame) == "number" and frameNumber - lastHit.frame <= math.max(2, f.hitstop + 2) then
			local part = root(i)
			if part then
				local side = if (lastHit.side or 1) >= 0 then 1 else -1
				local amp = if lastHit.tier == "Launch" then 0.105 elseif lastHit.tier == "Heavy" then 0.082 elseif lastHit.tier == "Medium" then 0.055 else 0.032
				local pulse = Vector3.new(math.sin(f.now * 155 + i) * amp * side, math.cos(f.now * 131 + i) * amp * 0.36, 0)
				part.CFrame += pulse
			end
		end
	end
end

function M.update(f: RenderFrame)
	local start = os.clock()
	if typeof(f.origin) == "Vector3" then origin = f.origin end
	for _, rig in pool do
		if rig.activeRingUntil > 0 then
			local now = f.now
			if now >= rig.activeRingUntil then
				rig.ring.Transparency = 1
				rig.activeRingUntil = 0
			else
				local t = math.clamp((now - rig.ringStarted) / RING_LIFE, 0, 1)
				local size = rig.ringBase * (1 + t)
				rig.ring.Size = Vector3.new(0.035, size, size)
				rig.ring.Transparency = 0.45 + 0.55 * t
			end
		end
	end
	updateTrails(f)
	updateHitstopJitter(f)
	for i = 1, 2 do
		local r = f.fighters[i]
		lastIds[i] = if r and type(r.characterId) == "string" then r.characterId else lastIds[i]
	end
	updateAuras(f)
	updateCinematicGround(f)
	do
		local c = ctx
		local audio = c and c.modules and c.modules.Audio
		if audio and audio.updateCinematic then
			local ok, err = pcall(audio.updateCinematic, f)
			if not ok then warn("FightingLab: Audio.updateCinematic failed: " .. tostring(err)) end
		end
	end
	for i = 1, 2 do
		local r = f.fighters[i]
		if r then
			local prev = previousStates[i]
			if r.state ~= prev then
				if r.state == "Dash" or r.state == "Backdash" then emitDust(origin + r.pos + Vector3.new(0, 0.1, 0), 10, 0.75) end
				if r.state == "Sidestep" then emitDust(origin + r.pos + Vector3.new(0, 0.1, 0), 6, 0.6) end
				if r.state == "Getup" then emitDust(origin + r.pos + Vector3.new(0, 0.1, 0), 8, 0.8) end
				previousStates[i] = r.state
			end
			-- Dust bursts when the body actually hits the floor (synced with the knockdown/KO fall animation).
			local tracker = impactTrackers[i]
			if not tracker then
				tracker = States.newImpactTracker()
				impactTrackers[i] = tracker
			end
			local c = ctx
			if States.floorImpact(tracker, r, if c then c.config else nil, f.now) then
				emitDust(origin + Vector3.new(r.pos.X, 0.1, r.pos.Z), 26, 1.35)
				if c and c.gui:GetAttribute("CameraShakeDisabled") ~= true then c.modules.Camera.impulse(0.035) end
			end
		end
	end
	averageCostMs += (((os.clock() - start) * 1000) - averageCostMs) * 0.08
	local c = ctx
	if c then
		c.gui:SetAttribute("EffectsCostMs", averageCostMs)
		c.gui:SetAttribute("EffectsPoolSize", POOL_SIZE)
		c.gui:SetAttribute("EffectsActiveEstimate", math.min(activeEmitters, POOL_SIZE))
	end
end

function M.init(newCtx: Ctx)
	ctx = newCtx
	local old = workspace:FindFirstChild("FightingLabLocalEffects")
	if old then old:Destroy() end
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "FightingLabLocalEffects"
	fxFolder.Parent = workspace
	table.clear(pool)
	for i = 1, POOL_SIZE do pool[i] = newEmitterRig() end
	-- Warm particle textures in the background: PreloadAsync can stall on a slow asset fetch, and every later client
	-- module (including the FrontEnd menu) initialises after this one.
	local warm = folder():GetDescendants()
	task.spawn(function() pcall(function() ContentProvider:PreloadAsync(warm) end) end)
	local frame = Instance.new("Frame")
	frame.Name = "FightingLabScreenFlash"
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(1, 1)
	frame.ZIndex = 900
	frame.Parent = newCtx.gui
	flashFrame = frame
	local edge = Instance.new("Frame")
	edge.Name = "FightingLabCounterEdgeFlash"
	edge.BackgroundTransparency = 1
	edge.BorderSizePixel = 0
	edge.Size = UDim2.fromScale(1, 1)
	edge.ZIndex = 899
	edge.Parent = newCtx.gui
	edgeFrame = edge
	newCtx.gui:SetAttribute("EffectsCostMs", 0)
	newCtx.gui:SetAttribute("EffectsPoolSize", POOL_SIZE)
end

return M
