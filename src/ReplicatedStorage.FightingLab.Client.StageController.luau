--!strict
-- Arena presentation during a fight (contract v5): arenas are physical models in the lobby world, so nothing is cloned
-- and global lighting is never touched (spectators share it). For the active arena model this module fades
-- FightingLabCameraOccluder-tagged geometry between the fight camera and the fighters, fades other players' avatars
-- that stand in the camera's view of the fighters, runs the arena's FightingLabFlicker / FightingLabBlink tags, and
-- restores every local tweak exactly when the fight ends.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AvatarGate = require(script.Parent:WaitForChild("AvatarGate"))

type Ctx = any
type RenderFrame = any
type Occluder = { inst: Instance, parts: { BasePart }, guis: { { gui: SurfaceGui, enabled: boolean } }, alpha: number, target: number, center: Vector3, radius: number }
type Flicker = { light: Light, min: number, max: number, rate: number, base: number }
type Blink = { inst: Instance, period: number, enabled: boolean? }
type FadedAvatar = { items: { Instance }, alpha: number, target: number }

local M = {}
local ctx: Ctx? = nil
local currentId = ""
local arenaModel: Instance? = nil
local origin = Vector3.zero
local occluders: { Occluder } = {}
local flickers: { Flicker } = {}
local blinks: { Blink } = {}
local avatars: { [Model]: FadedAvatar } = {}

local FADE_ALPHA = 0.72
local FADE_RATE = 14
local AVATAR_ALPHA = 0.8
local AVATAR_CLEARANCE = 3.2

local function collect(inst: Instance): ({ BasePart }, { { gui: SurfaceGui, enabled: boolean } })
	local parts: { BasePart } = {}
	local guis: { { gui: SurfaceGui, enabled: boolean } } = {}
	if inst:IsA("BasePart") then table.insert(parts, inst) end
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then table.insert(parts, d) elseif d:IsA("SurfaceGui") then table.insert(guis, { gui = d, enabled = d.Enabled }) end
	end
	return parts, guis
end

local function tagged(tag: string, root: Instance): { Instance }
	local list = {}
	for _, inst in CollectionService:GetTagged(tag) do
		if inst == root or inst:IsDescendantOf(root) then table.insert(list, inst) end
	end
	return list
end

local function cacheArena(root: Instance)
	for _, inst in tagged("FightingLabCameraOccluder", root) do
		local parts, guis = collect(inst)
		if #parts > 0 then
			local cf: CFrame, size: Vector3
			if inst:IsA("Model") then
				cf, size = inst:GetBoundingBox()
			elseif inst:IsA("BasePart") then
				cf, size = inst.CFrame, inst.Size
			else
				cf, size = parts[1].CFrame, parts[1].Size
			end
			table.insert(occluders, { inst = inst, parts = parts, guis = guis, alpha = 0, target = 0, center = cf.Position, radius = size.Magnitude / 2 })
		end
	end
	for _, inst in tagged("FightingLabFlicker", root) do
		local function add(light: Light)
			table.insert(flickers, {
				light = light, base = light.Brightness,
				min = inst:GetAttribute("FlickerMin") or 0.45, max = inst:GetAttribute("FlickerMax") or 1, rate = inst:GetAttribute("FlickerRate") or 12,
			})
		end
		if inst:IsA("Light") then add(inst) end
		for _, d in inst:GetDescendants() do if d:IsA("Light") then add(d) end end
	end
	for _, inst in tagged("FightingLabBlink", root) do
		table.insert(blinks, { inst = inst, period = inst:GetAttribute("Period") or 1, enabled = if inst:IsA("Light") then inst.Enabled else nil })
	end
end

local function applyAlpha(o: Occluder, alpha: number)
	o.alpha = alpha
	for _, p in o.parts do p.LocalTransparencyModifier = alpha end
	for _, g in o.guis do g.gui.Enabled = g.enabled and alpha < 0.6 end
end

local function applyAvatarAlpha(a: FadedAvatar, alpha: number)
	a.alpha = alpha
	for _, item in a.items do
		if item.Parent then (item :: any).LocalTransparencyModifier = alpha end
	end
end

local function avatarItems(model: Model): { Instance }
	local items = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then table.insert(items, d) end
	end
	return items
end

-- True when `point` stands in front of `target` as seen from the camera, within `clearance` of that sight line.
local function blocksSight(point: Vector3, camPos: Vector3, target: Vector3, clearance: number): boolean
	local line = target - camPos
	local len = line.Magnitude
	if len < 0.5 then return false end
	local dir = line / len
	local along = (point - camPos):Dot(dir)
	if along < -1 or along > len + 1.5 then return false end
	return (point - (camPos + dir * math.clamp(along, 0, len))).Magnitude < clearance
end

-- Avatars that may stand in the camera's view: every other player's character (overridable by tests).
function M._spectatorCharacters(): { Model }
	local list = {}
	local localPlayer = Players.LocalPlayer
	for _, player in Players:GetPlayers() do
		if player ~= localPlayer and player.Character then table.insert(list, player.Character) end
	end
	return list
end

-- Other players' avatars (spectators walking through the arena) fade while they block the view of the fight.
local function updateAvatars(camPos: Vector3, focus: Vector3, dt: number)
	local targets = { focus }
	local c = ctx
	local characters = c and c.modules and c.modules.Characters
	if characters and characters.getRoot then
		for slot = 1, 2 do
			local ok, root = pcall(characters.getRoot, slot)
			if ok and typeof(root) == "Instance" and root:IsA("BasePart") then table.insert(targets, root.Position) end
		end
	end
	local seen: { [Model]: boolean } = {}
	for _, character in M._spectatorCharacters() do
		-- Characters still held hidden by the AvatarGate belong to it until they are dressed and loaded.
		if AvatarGate.isGated(character) then continue end
		seen[character] = true
		local root = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
		local blocking = false
		if root and root:IsA("BasePart") then
			for _, target in targets do
				if blocksSight(root.Position, camPos, target, AVATAR_CLEARANCE) then blocking = true; break end
			end
		end
		local entry = avatars[character]
		if blocking and not entry then
			entry = { items = avatarItems(character), alpha = 0, target = 0 }
			avatars[character] = entry
		end
		if entry then entry.target = if blocking then AVATAR_ALPHA else 0 end
	end
	for model, entry in avatars do
		if not seen[model] or not model.Parent then
			applyAvatarAlpha(entry, 0)
			avatars[model] = nil
		elseif math.abs(entry.alpha - entry.target) > 0.005 then
			local alpha = entry.alpha + (entry.target - entry.alpha) * (1 - math.exp(-dt * FADE_RATE))
			if math.abs(alpha - entry.target) <= 0.01 then alpha = entry.target end
			applyAvatarAlpha(entry, alpha)
			if alpha == 0 and entry.target == 0 then avatars[model] = nil end
		end
	end
end

function M.listStages()
	local stages = ReplicatedStorage:WaitForChild("FightingLab"):WaitForChild("Stages")
	local result = {}
	for _, child in stages:GetChildren() do
		if child:IsA("Model") then table.insert(result, { id = child.Name, displayName = child:GetAttribute("DisplayName") or child.Name, description = child:GetAttribute("Description") or "" }) end
	end
	table.sort(result, function(a, b) return a.id < b.id end)
	return result
end

function M.current(): string return currentId end

-- Legacy entry point (menus used it to swap stage models). Arenas are in the world now: only the id is recorded.
function M.load(stageId: string)
	currentId = stageId
end

-- Restores everything this module changed on the previous arena.
function M.clearArena()
	for _, o in occluders do applyAlpha(o, 0) end
	for _, entry in avatars do applyAvatarAlpha(entry, 0) end
	table.clear(avatars)
	for _, item in flickers do if item.light.Parent then item.light.Brightness = item.base end end
	for _, item in blinks do
		local inst = item.inst
		if inst:IsA("BasePart") then
			inst.LocalTransparencyModifier = 0
		elseif inst:IsA("Light") and item.enabled ~= nil then
			inst.Enabled = item.enabled
		end
	end
	table.clear(occluders)
	table.clear(flickers)
	table.clear(blinks)
	arenaModel = nil
end

function M.setArena(model: Instance?, newOrigin: Vector3?)
	M.clearArena()
	arenaModel = model
	origin = newOrigin or Vector3.zero
	if model then
		local stageId = model:GetAttribute("StageId")
		if typeof(stageId) == "string" then currentId = stageId end
		cacheArena(model)
	end
	local c = ctx
	if c and c.gui then
		c.gui:SetAttribute("ArenaOccluders", #occluders)
		c.gui:SetAttribute("ArenaId", if model then model.Name else "")
	end
end

function M.getArena(): Instance?
	return arenaModel
end

function M._testLightingContrast(stageId: string): number
	return if stageId == "MidnightRooftop" then 0.22 else 0.18
end

function M.update(f: RenderFrame)
	if not arenaModel then return end
	local cam = workspace.CurrentCamera
	if not cam then return end
	local c = ctx
	local cameraFocus = if c and c.modules and c.modules.Camera and c.modules.Camera.getFocus then c.modules.Camera.getFocus() else origin
	local camPos = cam.CFrame.Position
	local line = cameraFocus - camPos
	local len = line.Magnitude
	local dir = if len > 0.01 then line.Unit else Vector3.zAxis
	local dt = if typeof(f.dt) == "number" then f.dt else 1 / 60
	for _, o in occluders do
		local toCenter = o.center - camPos
		local along = toCenter:Dot(dir)
		local nearest = camPos + dir * math.clamp(along, 0, len)
		local between = along > -2 and along < len + o.radius and (o.center - nearest).Magnitude < math.max(4.5, o.radius * 0.35)
		local cameraSide = (o.center - cameraFocus).Magnitude < (camPos - cameraFocus).Magnitude + o.radius and along > 0
		o.target = if between and cameraSide then FADE_ALPHA else 0
		if math.abs(o.alpha - o.target) > 0.005 then
			applyAlpha(o, o.alpha + (o.target - o.alpha) * (1 - math.exp(-dt * FADE_RATE)))
			if math.abs(o.alpha - o.target) <= 0.01 then applyAlpha(o, o.target) end
		end
	end
	updateAvatars(camPos, cameraFocus, dt)
	local now = if typeof(f.now) == "number" then f.now else os.clock()
	for _, item in flickers do
		local wave = (math.noise(now * item.rate, item.base) + 1) * 0.5
		item.light.Brightness = item.base * (item.min + (item.max - item.min) * wave)
	end
	for _, item in blinks do
		local on = (now % item.period) < item.period * 0.5
		local inst = item.inst
		if inst:IsA("BasePart") then
			inst.LocalTransparencyModifier = if on then 0 else 0.65
		elseif inst:IsA("Light") then
			inst.Enabled = on and item.enabled ~= false
		end
	end
end

function M.init(newCtx: Ctx)
	ctx = newCtx
end

return M
