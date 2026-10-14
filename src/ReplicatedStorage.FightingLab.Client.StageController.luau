--!strict
-- Arena presentation during a fight (contract v5): arenas are physical models in the lobby world, so nothing is cloned.
-- For the active arena model this module fades FightingLabCameraOccluder-tagged geometry between the fight camera and
-- the fighters, fades other players' avatars that stand in the camera's view of the fighters, runs the arena's
-- FightingLabFlicker / FightingLabBlink tags, and restores every local tweak exactly when the fight ends.
-- Round 6 (look): the occluder tag is shared by every arena (a stage's floor rises above a lower neighbour's floor and
-- carries the tag for that neighbour), so only tagged pieces rising above THIS arena's floor + OCCLUDER_HEIGHT fade:
-- before, the rooftop and summit fight floors faded with their podiums and the neon edge disc under them washed the
-- floor pink / cyan. On the fighting client only, the arena's mood (LightingProfile.applyArena: time of day,
-- atmosphere, grade, depth of field) is applied for the fight, a two-light rig follows the camera (a key from the
-- camera side and the arena's coloured rim from behind the fighters), and the arena's fight-only set dressing
-- (FightSet, client-shown) appears; all of it is undone by clearArena.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local AvatarGate = require(script.Parent:WaitForChild("AvatarGate"))
local LightingProfile = require(script.Parent:WaitForChild("LightingProfile"))

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
-- World.Layout.OCCLUDER_HEIGHT: only pieces rising this far above the active arena's floor can block its camera.
M.OCCLUDER_HEIGHT = 1.5

type Rig = { folder: Folder, key: SpotLight, keyPart: BasePart, rim: SpotLight, rimPart: BasePart }
local rig: Rig? = nil
local fightSet: Instance? = nil
type Person = { frame: GuiObject, base: UDim2, phase: number, rate: number }
local crowdPeople: { Person } = {}
-- Moving set pieces (World.FightSets attribute FightSetAnim): people cheering, lanterns swaying, gulls, searchlights.
-- Each keeps its parts' offsets from its pivot so a whole update is one BulkMoveTo.
type SetAnim = { kind: string, base: CFrame, rate: number, amp: number, phase: number, parts: { BasePart }, offsets: { CFrame } }
local setAnims: { SetAnim } = {}
local animParts: { BasePart } = {}
local animFrames: { CFrame } = {}
local animClock = 0
M.ANIM_ATTRIBUTE = "FightSetAnim"
M.ANIM_HZ = 30
-- The rest of the district is hidden on the fighting client while its fight set is up (round 7: every set surrounds
-- the fight, 360 degrees): the plaza, the other stages, the grounds and the seascape, and the active arena's own
-- pieces outside its podium (status board, pads, stair, in-world backdrop) and its banners. Parts get a
-- LocalTransparencyModifier of 1; lights, emitters, beams and billboards are switched off; SurfaceGuis are pushed out
-- of range through MaxDistance (their Enabled flag belongs to StationBoards). Everything is put back exactly.
type Hidden = { parts: { BasePart }, ltm: { number }, toggled: { Instance }, guis: { any }, guiRange: { number } }
local hidden: Hidden? = nil
local hiddenSet: { [BasePart]: boolean } = {}
-- Map preview (Contract D): the arena shown the way its fighters see it, for a menu camera on its PreviewCam.
local previewModel: Instance? = nil
local previewConn: RBXScriptConnection? = nil
M.HIDE_DISTRICT = true
M.KEEP_RADIUS = 27.6 -- the active arena keeps what stands on its podium (top radius 27): floor, barrier, stage lights
M.HIDE_ROOTS = { "Lobby", "Walkways", "Seascape" }

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

-- Whether a tagged occluder can block the view of a fight whose floor is at `floorY`: its top must rise above the
-- floor + OCCLUDER_HEIGHT (the tag is global; a stage's own floor stack carries it for its lower neighbours).
function M.occluderRelevant(inst: Instance, floorY: number): boolean
	local top = -math.huge
	if inst:IsA("BasePart") then
		local cf, s = inst.CFrame, inst.Size * 0.5
		top = cf.Y + math.abs(cf.RightVector.Y) * s.X + math.abs(cf.UpVector.Y) * s.Y + math.abs(cf.LookVector.Y) * s.Z
	elseif inst:IsA("Model") then
		local cf, size = inst:GetBoundingBox()
		top = cf.Y + size.Y * 0.5
	else
		return true
	end
	return top > floorY + M.OCCLUDER_HEIGHT + 1e-3
end

local function cacheArena(root: Instance)
	for _, inst in tagged("FightingLabCameraOccluder", root) do
		if not M.occluderRelevant(inst, origin.Y) then continue end
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
	local h = hidden
	for _, p in o.parts do
		if not (h and hiddenSet[p]) then p.LocalTransparencyModifier = alpha end
	end
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
	previewModel = nil
	local pc = previewConn
	previewConn = nil
	if pc then pc:Disconnect() end
	LightingProfile.restore()
	local r = rig
	rig = nil
	if r then r.folder:Destroy() end
	local set = fightSet
	fightSet = nil
	table.clear(crowdPeople)
	table.clear(setAnims)
	table.clear(animParts)
	table.clear(animFrames)
	if set then set:Destroy() end
	local h = hidden
	hidden = nil
	table.clear(hiddenSet)
	if h then
		for i, p in h.parts do p.LocalTransparencyModifier = h.ltm[i] end
		for _, inst in h.toggled do (inst :: any).Enabled = true end
		for i, g in h.guis do if g.Parent then g.MaxDistance = h.guiRange[i] end end
	end
end

-- Flat distance from FightOrigin's axis to a part's oriented box (at the part's height).
local function flatDistanceTo(part: BasePart, centre: Vector3): number
	local cf = part.CFrame
	local l = cf:PointToObjectSpace(Vector3.new(centre.X, cf.Y, centre.Z))
	local s = part.Size * 0.5
	local c = cf:PointToWorldSpace(Vector3.new(math.clamp(l.X, -s.X, s.X), math.clamp(l.Y, -s.Y, s.Y), math.clamp(l.Z, -s.Z, s.Z)))
	return Vector3.new(c.X - centre.X, 0, c.Z - centre.Z).Magnitude
end

-- Whether a piece of the active arena hides during its own fight: everything off the podium (outside KEEP_RADIUS),
-- the banners on it (lettered signage that would stand behind the fighters) and its trees (their crowns overhang the
-- podium edge).
M.HIDE_MODELS = { Tree = true, Palm = true, Pine = true, CherryTree = true, JungleTree = true, SnowPine = true, SmallPine = true }
function M.hidesInOwnFight(part: BasePart, centre: Vector3): boolean
	if part.Name == "FightOrigin" or part.Name == "PreviewCam" then return false end
	if string.sub(part.Name, 1, 6) == "Banner" then return true end
	local model = part:FindFirstAncestorWhichIsA("Model")
	if model and M.HIDE_MODELS[model.Name] then return true end
	return flatDistanceTo(part, centre) > M.KEEP_RADIUS
end

-- Hides (locally) everything but the active arena's podium for the fight in `active`; returns how many parts it hid.
local function hideDistrict(active: Instance): number
	local world = workspace:FindFirstChild("FightingLabWorld")
	if not world then return 0 end
	local roots: { Instance } = {}
	for _, name in M.HIDE_ROOTS do
		local r = world:FindFirstChild(name)
		if r then table.insert(roots, r) end
	end
	local arenas = world:FindFirstChild("Arenas")
	if arenas then
		for _, a in arenas:GetChildren() do if a ~= active then table.insert(roots, a) end end
	end
	local h: Hidden = { parts = {}, ltm = {}, toggled = {}, guis = {}, guiRange = {} }
	local function hidePart(p: BasePart)
		table.insert(h.parts, p); table.insert(h.ltm, p.LocalTransparencyModifier)
		p.LocalTransparencyModifier = 1
		hiddenSet[p] = true
	end
	local function hideExtra(d: Instance)
		if d:IsA("SurfaceGui") or d:IsA("BillboardGui") then
			-- out of range instead of disabled: StationBoards owns their Enabled flags
			table.insert(h.guis, d); table.insert(h.guiRange, (d :: any).MaxDistance);
			(d :: any).MaxDistance = 0.001
		elseif d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Light") then
			if (d :: any).Enabled then (d :: any).Enabled = false; table.insert(h.toggled, d) end
		end
	end
	for _, root in roots do
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") then hidePart(d) else hideExtra(d) end
		end
	end
	-- the active arena: only its podium stays
	for _, d in active:GetDescendants() do
		if d:IsA("BasePart") and M.hidesInOwnFight(d, origin) then
			hidePart(d)
			for _, x in d:GetDescendants() do hideExtra(x) end
		end
	end
	-- floating tags in the player's gui that are adorned to hidden pieces (the pad tags)
	local player = Players.LocalPlayer
	local gui = player and player:FindFirstChildOfClass("PlayerGui")
	if gui then
		for _, d in gui:GetDescendants() do
			if d:IsA("BillboardGui") and d.Adornee and d.Adornee:IsA("BasePart") and hiddenSet[d.Adornee :: BasePart] then
				hideExtra(d)
			end
		end
	end
	hidden = h
	return #h.parts
end

-- The camera-following fight light rig (client only): a soft key from the camera side and the arena's coloured rim
-- from behind the fighters. One shadow caster (the key).
local function buildRig(stageId: string): Rig?
	local spec = LightingProfile.rigFor(stageId)
	if not spec then return nil end
	local folder = Instance.new("Folder")
	folder.Name = "FightingLabFightRig"
	local function holder(name: string): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
		p.Transparency = 1; p.Size = Vector3.new(0.2, 0.2, 0.2)
		p.Parent = folder
		return p
	end
	local keyPart, rimPart = holder("Key"), holder("Rim")
	local key = Instance.new("SpotLight")
	key.Name = "FightKey"; key.Face = Enum.NormalId.Front; key.Color = spec.keyColor; key.Brightness = spec.key
	key.Range = 34; key.Angle = 48; key.Shadows = true; key.Parent = keyPart
	local rim = Instance.new("SpotLight")
	rim.Name = "FightRim"; rim.Face = Enum.NormalId.Front; rim.Color = spec.rimColor; rim.Brightness = spec.rim
	rim.Range = 36; rim.Angle = spec.rimAngle or 50; rim.Shadows = false; rim.Parent = rimPart
	folder.Parent = workspace
	return { folder = folder, key = key, keyPart = keyPart, rim = rim, rimPart = rimPart }
end

-- Rig placement for a camera and a fight focus: key above and left of the camera, rim behind the fighters.
function M.rigFrames(camPos: Vector3, focus: Vector3): (CFrame, CFrame)
	local flat = Vector3.new(focus.X - camPos.X, 0, focus.Z - camPos.Z)
	local forward = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
	local right = forward:Cross(Vector3.yAxis)
	local keyPos = focus - forward * 9 - right * 6 + Vector3.new(0, 10, 0)
	local rimPos = focus + forward * 11 + right * 2.5 + Vector3.new(0, 8.5, 0)
	return CFrame.lookAt(keyPos, focus + Vector3.new(0, 1, 0)), CFrame.lookAt(rimPos, focus + Vector3.new(0, 2.2, 0))
end

-- Fight-only set dressing the world keeps for this arena (ReplicatedStorage.FightingLab.FightSets.<StageId>):
-- a clone is shown to the fighting client only, so the plaza behind the stage reads as the arena's own scenery.
local function showFightSet(stageId: string)
	local lab = ReplicatedStorage:FindFirstChild("FightingLab")
	local sets = lab and lab:FindFirstChild("FightSets")
	local template = sets and sets:FindFirstChild(stageId)
	if not template then return end
	local clone = template:Clone()
	clone.Name = "FightingLabFightSet_" .. stageId
	clone.Parent = workspace
	fightSet = clone
	table.clear(crowdPeople)
	table.clear(setAnims)
	for _, d in clone:GetDescendants() do
		if d.Name == "Person" and d:IsA("GuiObject") then
			local phase, rate = d:GetAttribute("Phase"), d:GetAttribute("Rate")
			table.insert(crowdPeople, { frame = d, base = d.Position, phase = if typeof(phase) == "number" then phase else 0, rate = if typeof(rate) == "number" then rate else 2 })
		end
		local kind = d:GetAttribute(M.ANIM_ATTRIBUTE)
		if typeof(kind) == "string" and (d:IsA("Model") or d:IsA("BasePart")) then
			local rate, amp, phase = d:GetAttribute("AnimRate"), d:GetAttribute("AnimAmp"), d:GetAttribute("AnimPhase")
			local base = (d :: PVInstance):GetPivot()
			local a: SetAnim = {
				kind = kind, base = base, parts = {}, offsets = {},
				rate = if typeof(rate) == "number" then rate else 1, amp = if typeof(amp) == "number" then amp else 0,
				phase = if typeof(phase) == "number" then phase else 0,
			}
			local list: { Instance } = d:GetDescendants()
			if d:IsA("BasePart") then table.insert(list, d) end
			for _, p in list do
				if p:IsA("BasePart") then
					table.insert(a.parts, p)
					table.insert(a.offsets, base:ToObjectSpace(p.CFrame))
				end
			end
			table.insert(setAnims, a)
		end
	end
	animClock = 0
end

-- Spectators in the fight set sway a little (a few pixels on their panel).
local function swayCrowd(now: number)
	for _, p in crowdPeople do
		local lift = math.max(0, math.sin(now * p.rate + p.phase)) * 3
		p.frame.Position = p.base - UDim2.fromOffset(0, math.floor(lift + 0.5))
	end
end

-- The offset a set animation applies to its piece's pivot at time `t` (World.FightSets: FightSetAnim, AnimRate,
-- AnimAmp, AnimPhase). Cheer: hops (people); Bob: up and down; Sway: a pendulum about the pivot; Sweep: a yaw
-- swing (searchlights); Orbit: a circle about the pivot (gulls, aircraft).
function M.animOffset(kind: string, t: number, rate: number, amp: number, phase: number): CFrame
	local w = t * rate + phase
	if kind == "Cheer" then
		return CFrame.new(0, amp * math.max(0, math.sin(w)), 0)
	elseif kind == "Bob" then
		return CFrame.new(0, amp * math.sin(w), 0)
	elseif kind == "Sway" then
		return CFrame.Angles(amp * math.sin(w), 0, amp * 0.6 * math.sin(w * 0.8 + 1))
	elseif kind == "Sweep" then
		return CFrame.Angles(0, amp * math.sin(w), 0)
	elseif kind == "Orbit" then
		return CFrame.Angles(0, w, 0) * CFrame.new(0, 0.6 * math.sin(t * 1.3 + phase), 0)
	end
	return CFrame.identity
end

-- Moves every animated set piece (at most ANIM_HZ times a second), all of them in one BulkMoveTo.
local function animateSet(now: number)
	table.clear(animParts)
	table.clear(animFrames)
	for _, a in setAnims do
		local cf = a.base * M.animOffset(a.kind, now, a.rate, a.amp, a.phase)
		for i, p in a.parts do
			table.insert(animParts, p)
			table.insert(animFrames, cf * a.offsets[i])
		end
	end
	if #animParts > 0 then
		workspace:BulkMoveTo(animParts, animFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function M.setArena(model: Instance?, newOrigin: Vector3?)
	M.clearArena()
	arenaModel = model
	origin = newOrigin or Vector3.zero
	if model then
		local stageId = model:GetAttribute("StageId")
		if typeof(stageId) == "string" then currentId = stageId end
		cacheArena(model)
		if typeof(stageId) == "string" and RunService:IsClient() then
			LightingProfile.applyArena(stageId)
			rig = buildRig(stageId)
			showFightSet(stageId)
			if fightSet and M.HIDE_DISTRICT then hideDistrict(model) end
		end
	end
	local c = ctx
	if c and c.gui then
		c.gui:SetAttribute("ArenaOccluders", #occluders)
		c.gui:SetAttribute("ArenaId", if model then model.Name else "")
		c.gui:SetAttribute("ArenaMood", LightingProfile.activeArena() or "")
	end
end

-- Map preview (Contract D, client only): shows an arena the way its fighters see it (its mood, its fight set and the
-- district hidden, the crowd moving) for a menu camera placed on the arena's PreviewCam. `model` is an arena under
-- workspace.FightingLabWorld.Arenas; nil ends the preview. Returns whether a preview is up. clearArena(),
-- setArena() and a new previewArena() replace it; nothing is left behind.
function M.previewArena(model: Instance?): boolean
	M.clearArena()
	if not model or not RunService:IsClient() then return false end
	local stageId = model:GetAttribute("StageId")
	local fo = model:FindFirstChild("FightOrigin")
	if typeof(stageId) ~= "string" or not (fo and fo:IsA("BasePart")) then return false end
	origin = fo.Position
	LightingProfile.applyArena(stageId)
	local cam = model:FindFirstChild("PreviewCam")
	if cam and cam:IsA("BasePart") then LightingProfile.setFocus((cam.Position - origin).Magnitude) end
	showFightSet(stageId)
	if fightSet and M.HIDE_DISTRICT then hideDistrict(model) end
	previewModel = model
	previewConn = RunService.RenderStepped:Connect(function(dt: number)
		if not fightSet then return end
		swayCrowd(os.clock())
		animClock += dt
		if animClock >= 1 / M.ANIM_HZ then
			animClock = 0
			animateSet(os.clock())
		end
	end)
	return true
end

-- The arena being previewed, if any.
function M.previewing(): Instance?
	return previewModel
end

-- Tagged pieces the active arena fades (tests and tools).
function M._occluders(): { Instance }
	local list = {}
	for _, o in occluders do table.insert(list, o.inst) end
	return list
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
	local r = rig
	if r then
		local keyCf, rimCf = M.rigFrames(camPos, cameraFocus)
		r.keyPart.CFrame = keyCf
		r.rimPart.CFrame = rimCf
	end
	LightingProfile.setFocus(len)
	local now = if typeof(f.now) == "number" then f.now else os.clock()
	if fightSet then
		swayCrowd(os.clock())
		animClock += dt
		if animClock >= 1 / M.ANIM_HZ and #setAnims > 0 then
			animClock = 0
			animateSet(os.clock())
		end
	end
	for _, item in flickers do
		local wave = (math.noise(now * item.rate, item.base) + 1) * 0.5
		item.light.Brightness = item.base * (item.min + (item.max - item.min) * wave)
	end
	for _, item in blinks do
		local on = (now % item.period) < item.period * 0.5
		local inst = item.inst
		if inst:IsA("BasePart") then
			if not hiddenSet[inst] then inst.LocalTransparencyModifier = if on then 0 else 0.65 end
		elseif inst:IsA("Light") then
			inst.Enabled = on and item.enabled ~= false
		end
	end
end

function M.init(newCtx: Ctx)
	ctx = newCtx
end

return M
