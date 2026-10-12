--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local StarterGui = game:GetService("StarterGui")
local MotionPlayer = require(script.Parent.MotionPlayer)
local Roster = require(script.Parent.Parent.Roster)
-- Facial expressions are optional: rigs without a FaceController module (or without FaceControls) still render.
local faceModule = script.Parent:FindFirstChild("FaceController")
local Face: any = if faceModule and faceModule:IsA("ModuleScript") then require(faceModule) else nil

type Ctx = any
type RenderFrame = any
type CharacterInfo = { id: string, displayName: string, tagline: string }
type PreviewPose = "Stance" | "Intro" | "Victory" | "Defeat" | "Guard"
type LiveRig = { model: Model, root: BasePart, rig: MotionPlayer.RigInfo, flash: number, highlight: Highlight, characterId: string, mirrorOutline: boolean, serial: number, use: string?, aimHeights: { [string]: number }? }

local M = {}
local ctx: Ctx? = nil
local renderFolder: Folder? = nil
local localRigs: { LiveRig? } = {}
-- Poses applied to the two fighters this frame (throw grips run once both bodies are posed).
local framePoses: { [number]: MotionPlayer.Pose? } = {}
local selectedIds = { "Kael", "Sierra" }
local lastPreviewSignature = ""
local updateCostMs = 0
local updateCostPeakMs = 0
-- Preview clones (viewport/UI models) keep their rig info so per-frame posePreview calls do not rescan descendants.
local previewRigs: { [Model]: MotionPlayer.RigInfo } = setmetatable({} :: any, { __mode = "k" })
local REQUIRED_PARTS = { "HumanoidRootPart", "LowerTorso", "UpperTorso", "Head", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot" }
local LIMB_MAP: { [string]: string } = { LeadArm = "LeftHand", RearArm = "RightHand", LeadLeg = "LeftFoot", RearLeg = "RightFoot", Head = "Head", Torso = "UpperTorso", Body = "UpperTorso" }

local function labFolder(): Folder
	local lab = ReplicatedStorage:FindFirstChild("FightingLab")
	if not lab or not lab:IsA("Folder") then error("ReplicatedStorage.FightingLab folder is missing") end
	return lab
end
local function charactersFolder(): Folder
	local folder = labFolder():FindFirstChild("Characters")
	if not folder or not folder:IsA("Folder") then error("ReplicatedStorage.FightingLab.Characters folder is missing") end
	return folder
end

local function validateTemplate(model: Instance): Model
	if not model:IsA("Model") then error("Character template " .. model.Name .. " must be a Model") end
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then error("Character template " .. model.Name .. " is missing BasePart HumanoidRootPart") end
	if model.PrimaryPart ~= root then error("Character template " .. model.Name .. " PrimaryPart must be HumanoidRootPart") end
	if not root.Anchored then error("Character template " .. model.Name .. " HumanoidRootPart must be anchored") end
	local rootHeight = model:GetAttribute("RootHeight")
	if typeof(rootHeight) ~= "number" or rootHeight < 2 or rootHeight > 4.2 then error("Character template " .. model.Name .. " needs RootHeight attribute near R15 scale") end
	if typeof(model:GetAttribute("DisplayName")) ~= "string" or typeof(model:GetAttribute("Tagline")) ~= "string" then error("Character template " .. model.Name .. " needs DisplayName and Tagline attributes") end
	for _, partName in REQUIRED_PARTS do
		local part = model:FindFirstChild(partName, true)
		if not part or not part:IsA("BasePart") then error("Character template " .. model.Name .. " missing R15 part " .. partName) end
		if part ~= root and part.Anchored then error("Character template " .. model.Name .. " part " .. partName .. " must be unanchored") end
		if part.CanCollide or part.CanQuery or part.CanTouch then error("Character template " .. model.Name .. " part " .. partName .. " must have collision/query/touch disabled") end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		if humanoid.EvaluateStateMachine then error("Character template " .. model.Name .. " Humanoid EvaluateStateMachine must be false") end
		if humanoid:FindFirstChildOfClass("Animator") then error("Character template " .. model.Name .. " must not contain an Animator") end
	end
	MotionPlayer.collectRig(model)
	for _, d in model:GetDescendants() do if d:IsA("LuaSourceContainer") or d:IsA("Sound") or d:IsA("ProximityPrompt") or d:IsA("ClickDetector") then error("Character template " .. model.Name .. " contains disallowed instance " .. d.ClassName) end end
	return model
end

local function templateById(id: string): Model
	local child = charactersFolder():FindFirstChild(id)
	if not child then error("Unknown FightingLab character id " .. id) end
	return validateTemplate(child)
end

function M.listCharacters(): { CharacterInfo }
	local list: { CharacterInfo } = {}
	for _, id in Roster.order do
		local def = Roster.get(id)
		if charactersFolder():FindFirstChild(id) then validateTemplate(charactersFolder()[id]) end
		table.insert(list, { id = id, displayName = def.displayName, tagline = def.tagline })
	end
	return list
end

local function hideServerPart(d: Instance) if d:IsA("BasePart") then d.LocalTransparencyModifier = 1 end end
local function ensureFolder(): Folder
	local folder = renderFolder
	if folder and folder.Parent then return folder end
	local old = Workspace:FindFirstChild("FightingLabLocalRender")
	if old then old:Destroy() end
	folder = Instance.new("Folder")
	folder.Name = "FightingLabLocalRender"
	folder.Parent = Workspace
	renderFolder = folder
	return folder
end

-- Avatar templates keep their authored skin and clothing colors; recoloring body parts would paint over skin tones.
local function prepareClone(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = 0
			d.CanCollide = false; d.CanQuery = false; d.CanTouch = false
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.EvaluateStateMachine = false
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then animator:Destroy() end
	end
end

-- Rig pool --------------------------------------------------------------------------------------------------------
-- Layered clothing refits asynchronously whenever a clone appears in the Workspace, which shows a bare body for a few
-- frames. Fight rigs and UI previews therefore come from clones made once (prewarm, after TemplatesReady), parked
-- out of sight below the world, kept parented and only moved (PivotTo) between uses. Never re-parent a pooled model.
local PARK_ORIGIN = Vector3.new(0, -320, 0)
M.PoolPerId = 2
M.ParkHidden = false
local pool: { [string]: { LiveRig } } = {}
local poolSerial = 0
local coldAcquires = 0
local origin = Vector3.zero

local function parkFrame(serial: number): CFrame
	-- Below the world, but never below FallenPartsDestroyHeight.
	local y = math.max(PARK_ORIGIN.Y, Workspace.FallenPartsDestroyHeight + 60)
	return CFrame.new(Vector3.new(PARK_ORIGIN.X + (serial % 12) * 7, y, PARK_ORIGIN.Z + math.floor(serial / 12) * 7))
end

local function setLocalVisible(model: Model, visible: boolean)
	local value = if visible then 0 else 1
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then (d :: any).LocalTransparencyModifier = value end
	end
end

local function makeRig(id: string): LiveRig
	local source = templateById(id)
	local clone = source:Clone()
	poolSerial += 1
	local serial = poolSerial
	clone.Name = "Pool_" .. id .. "_" .. serial
	local root = clone:FindFirstChild("HumanoidRootPart")
	assert(root and root:IsA("BasePart"), "Validated character lost HumanoidRootPart after clone")
	root.Anchored = true
	prepareClone(clone)
	-- Mirror matches mark P2 with a warm outline instead of recoloring the avatar.
	local highlight = Instance.new("Highlight")
	highlight.Name = "FlashHighlight"; highlight.Enabled = false; highlight.FillColor = Color3.new(1, 1, 1); highlight.FillTransparency = 1; highlight.OutlineColor = Color3.fromRGB(255, 188, 85); highlight.OutlineTransparency = 1; highlight.DepthMode = Enum.HighlightDepthMode.Occluded; highlight.Parent = clone
	clone:PivotTo(parkFrame(serial))
	if M.ParkHidden then setLocalVisible(clone, false) end
	clone.Parent = ensureFolder()
	local record: LiveRig = { model = clone, root = root, rig = MotionPlayer.collectRig(clone), flash = 0, highlight = highlight, characterId = id, mirrorOutline = false, serial = serial, use = nil }
	local list = pool[id]
	if not list then list = {}; pool[id] = list end
	table.insert(list, record)
	return record
end

local function acquire(id: string, use: string): LiveRig
	local list = pool[id]
	if list then
		for _, record in list do
			if record.use == nil and record.model.Parent then
				record.use = use
				if M.ParkHidden then setLocalVisible(record.model, true) end
				return record
			end
		end
	end
	-- Not prewarmed (templates were late or more rigs are needed): a cold clone may show one refit.
	coldAcquires += 1
	local record = makeRig(id)
	record.use = use
	if M.ParkHidden then setLocalVisible(record.model, true) end
	return record
end

local function release(record: LiveRig)
	record.use = nil
	record.flash = 0
	record.mirrorOutline = false
	record.highlight.Enabled = false
	record.highlight.OutlineTransparency = 1
	record.model.Name = "Pool_" .. record.characterId .. "_" .. record.serial
	for _, motor in record.rig.motors do motor.Transform = CFrame.identity end
	record.model:PivotTo(parkFrame(record.serial))
	if M.ParkHidden then setLocalVisible(record.model, false) end
end

-- Ensures `perId` pooled clones exist for each id (default: two, for mirror matches). Yields between clones.
function M.prewarm(ids: { string }?, perId: number?)
	-- Index the mocap clip modules now (they are only required once) so the first fight frame does not hitch.
	local okIndex, indexErr = pcall(MotionPlayer.warmClips)
	if not okIndex then warn("FightingLab: clip index failed: " .. tostring(indexErr)) end
	local want = perId or M.PoolPerId
	for _, id in ids or Roster.order do
		if Roster.has(id) and charactersFolder():FindFirstChild(id) then
			local list = pool[id]
			local have = if list then #list else 0
			for _ = have + 1, want do
				makeRig(id)
				task.wait()
			end
		end
	end
	M.poolStats()
end

-- A pooled, already-wrapped clone for UI previews (posePreview it, move it with PivotTo; do not re-parent it).
function M.acquirePreview(id: string): Model
	if not Roster.has(id) then error("CharacterPresenter.acquirePreview unknown character id " .. tostring(id)) end
	local record = acquire(id, "preview")
	record.model.Name = "Preview_" .. id .. "_" .. record.serial
	return record.model
end

function M.releasePreview(model: Model)
	for _, list in pool do
		for _, record in list do
			if record.model == model and record.use == "preview" then release(record); return end
		end
	end
end

function M.poolStats(): { [string]: any }
	local total, free = 0, 0
	for _, list in pool do
		for _, record in list do
			total += 1
			if record.use == nil then free += 1 end
		end
	end
	local c = ctx
	if c and c.gui then
		c.gui:SetAttribute("PoolTotal", total)
		c.gui:SetAttribute("PoolFree", free)
		c.gui:SetAttribute("PoolColdAcquires", coldAcquires)
	end
	return { total = total, free = free, coldAcquires = coldAcquires }
end

function M.setCharacters(p1Id: string, p2Id: string)
	if not Roster.has(p1Id) then error("CharacterPresenter: unknown p1 character " .. p1Id) end
	if not Roster.has(p2Id) then error("CharacterPresenter: unknown p2 character " .. p2Id) end
	local ids = { p1Id, p2Id }
	for i = 1, 2 do
		local current = localRigs[i]
		if current and current.characterId ~= ids[i] then
			release(current)
			localRigs[i] = nil
		end
	end
	MotionPlayer.reset(1)
	MotionPlayer.reset(2)
	selectedIds = ids
	for i = 1, 2 do
		local record = localRigs[i] or acquire(ids[i], "fight" .. i)
		localRigs[i] = record
		record.model.Name = "Fighter" .. tostring(i) .. "_" .. ids[i]
		record.mirrorOutline = i == 2 and p1Id == p2Id
		record.highlight.Enabled = record.mirrorOutline
		record.highlight.OutlineTransparency = if record.mirrorOutline then 0.35 else 1
	end
	for i = 3, #localRigs do localRigs[i] = nil end
	M.poolStats()
end

-- Returns the fight rigs to the pool (lobby mode: no fight rig visible).
function M.endFight()
	for i = 1, 2 do
		local record = localRigs[i]
		if record then release(record) end
		localRigs[i] = nil
	end
	MotionPlayer.reset(1)
	MotionPlayer.reset(2)
	M.poolStats()
end

function M.isActive(): boolean
	return localRigs[1] ~= nil and localRigs[2] ~= nil
end

-- World position of the fight centre: sim positions are translated by it (fight axis = world X).
function M.setOrigin(o: Vector3)
	origin = o
end

function M.getModel(i: number): Model? local rig = localRigs[i]; return if rig then rig.model else nil end
function M.getRoot(i: number): BasePart? local rig = localRigs[i]; return if rig then rig.root else nil end
function M.getLimbPart(i: number, limb: string): BasePart?
	local rig = localRigs[i]
	if not rig then return nil end
	local name = LIMB_MAP[limb]
	if not name then error("Unknown FightingLab limb " .. limb) end
	local part = rig.rig.parts[name]
	if not part then error("FightingLab character " .. tostring(i) .. " is missing limb part " .. name) end
	return part
end
function M.setFlash(i: number, frames: number) local rig = localRigs[i]; if rig then rig.flash = math.max(rig.flash, frames) end end

local function rootCFrame(pos: Vector3, facing: Vector3, rootHeight: number, offset: Vector3, base: Vector3): CFrame
	if facing.Magnitude < 0.01 then error("CharacterPresenter received zero facing vector") end
	local floorPos = Vector3.new(base.X + pos.X, base.Y, base.Z + pos.Z)
	local airborne = math.max(0, pos.Y)
	local forward = facing.Unit
	-- Library +X is the fighter's right (forward x up), the same axis MotionPlayer.apply uses for limb targets.
	local right = forward:Cross(Vector3.yAxis)
	if right.Magnitude < 0.01 then right = Vector3.xAxis else right = right.Unit end
	local center = floorPos + Vector3.new(0, rootHeight + airborne, 0) + right * offset.X + Vector3.yAxis * offset.Y + forward * offset.Z
	return CFrame.lookAt(center, center + forward)
end

local function idFromFrame(f: RenderFrame, slot: number): string?
	local view = f.fighters and f.fighters[slot]
	if view and typeof(view.characterId) == "string" and Roster.has(view.characterId) then return view.characterId end
	local direct = if slot == 1 then f.p1Id else f.p2Id
	if typeof(direct) == "string" and Roster.has(direct) then return direct end
	local entry = f.entry
	if entry then
		local top = if slot == 1 then entry.p1Id or entry.snapshot and entry.snapshot.p1Id else entry.p2Id or entry.snapshot and entry.snapshot.p2Id
		if typeof(top) == "string" and Roster.has(top) then return top end
		local fighter = entry.fighters and entry.fighters[slot]
		if fighter and typeof(fighter.characterId) == "string" and Roster.has(fighter.characterId) then return fighter.characterId end
	end
	return nil
end

local function hideScreenGuisForPreview()
	if Workspace:GetAttribute("FightingLabMotionPreview") ~= true then return end
	for _, gui in StarterGui:GetChildren() do if gui:IsA("ScreenGui") then gui.Enabled = false end end
	local player = game:GetService("Players").LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	if playerGui then for _, gui in playerGui:GetChildren() do if gui:IsA("ScreenGui") then gui.Enabled = false end end end
end

local function previewFrame(c: Ctx, f: RenderFrame): RenderFrame
	if Workspace:GetAttribute("FightingLabMotionPreview") ~= true then return f end
	hideScreenGuisForPreview()
	local p1 = Workspace:GetAttribute("FightingLabMotionPreviewCharacter")
	local p2 = Workspace:GetAttribute("FightingLabMotionPreviewP2Character")
	local move = Workspace:GetAttribute("FightingLabMotionPreviewMove")
	local throw = Workspace:GetAttribute("FightingLabMotionPreviewThrow")
	local state = Workspace:GetAttribute("FightingLabMotionPreviewState")
	local frameValue = Workspace:GetAttribute("FightingLabMotionPreviewFrame")
	local phase = Workspace:GetAttribute("FightingLabMotionPreviewPhase")
	local winner = Workspace:GetAttribute("FightingLabMotionPreviewWinner")
	local p2State = Workspace:GetAttribute("FightingLabMotionPreviewP2State")
	local hitHeight = Workspace:GetAttribute("FightingLabMotionPreviewLastHitHeight")
	local hitTier = Workspace:GetAttribute("FightingLabMotionPreviewLastHitTier")
	local hitKind = Workspace:GetAttribute("FightingLabMotionPreviewLastHitKind")
	local hitSide = Workspace:GetAttribute("FightingLabMotionPreviewLastHitSide")
	local p1Id = if typeof(p1) == "string" and Roster.has(p1) then p1 else selectedIds[1]
	local p2Id = if typeof(p2) == "string" and Roster.has(p2) then p2 else selectedIds[2]
	local frameNo = if typeof(frameValue) == "number" then frameValue else 0
	local signature = tostring(p1Id)..":"..tostring(p2Id)..":"..tostring(move)..":"..tostring(throw)..":"..tostring(state)..":"..tostring(frameNo)..":"..tostring(phase)..":"..tostring(winner)..":"..tostring(p2State)
	if signature ~= lastPreviewSignature then
		if p1Id ~= selectedIds[1] or p2Id ~= selectedIds[2] then M.setCharacters(p1Id, p2Id) end
		MotionPlayer.reset(); lastPreviewSignature = signature
	end
	local preview = table.clone(f)
	preview.now = if typeof(f.now) == "number" then f.now else os.clock()
	preview.phase = if typeof(phase) == "string" then phase else "Fight"
	preview.winner = if typeof(winner) == "number" then winner else 0
	preview.hitstop = 0
	local throwName = if typeof(throw) == "string" then throw else nil
	preview.fighters = {
		{ pos = Vector3.new(-2.15, 0, 0), facing = Vector3.xAxis, state = if typeof(state) == "string" then state else "Idle", move = if typeof(move) == "string" and not throwName then move else nil, moveFrame = frameNo, walkPhase = 0.18, stun = 18, crouched = Workspace:GetAttribute("FightingLabMotionPreviewCrouched") == true, moveX = 0, extrapolated = 0, height = 1.9, characterId = p1Id, velocityY = Workspace:GetAttribute("FightingLabMotionPreviewVelocityY"), airFrames = Workspace:GetAttribute("FightingLabMotionPreviewAirFrames"), airHits = Workspace:GetAttribute("FightingLabMotionPreviewAirHits"), knockdown = Workspace:GetAttribute("FightingLabMotionPreviewKnockdown"), lastHit = if typeof(hitKind) == "string" or typeof(hitHeight) == "string" then { kind = if typeof(hitKind) == "string" then hitKind else "Hit", height = if typeof(hitHeight) == "string" then hitHeight else "Mid", tier = if typeof(hitTier) == "string" then hitTier else "Medium", counter = hitKind == "Counter", frame = 0, move = "Preview", limb = "RearArm", side = if typeof(hitSide) == "number" then hitSide else 1 } else nil, throw = if throwName then { role = "Attacker", archetype = throwName, frame = frameNo, duration = 48, impactFrame = 32 } else nil },
		{ pos = Vector3.new(2.15, 0, 0), facing = -Vector3.xAxis, state = if typeof(p2State) == "string" then p2State else "Idle", move = nil, moveFrame = frameNo, walkPhase = 0.68, stun = 18, crouched = false, moveX = 0, extrapolated = 0, height = 1.9, characterId = p2Id, throw = if throwName then { role = "Defender", archetype = throwName, frame = frameNo, duration = 48, impactFrame = 32 } else nil },
	}
	task.defer(function()
		local camera = Workspace.CurrentCamera
		if camera and Workspace:GetAttribute("FightingLabMotionPreview") == true then
			camera.CameraType = Enum.CameraType.Scriptable
			camera.FieldOfView = 34
			local threeQuarter = Workspace:GetAttribute("FightingLabMotionPreviewAngle") == "ThreeQuarter"
			local cameraPosition = if threeQuarter then Vector3.new(6.2, 3.35, 12.4) else Vector3.new(0, 3.25, 14.0)
			camera.CFrame = CFrame.lookAt(cameraPosition, Vector3.new(0, 2.25, 0))
		end
	end)
	return preview
end

-- Humanoids only auto-weld accessories under Workspace; ViewportFrame WorldModel clones keep unwelded handles at the
-- template's stored position, so previews weld each handle to its matching body attachment (as Humanoid:AddAccessory does).
function M.attachAccessories(model: Model): number
	local bodyAttachments: { [string]: Attachment } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Attachment") and d.Parent and d.Parent:IsA("BasePart") and not d:FindFirstAncestorOfClass("Accessory") then
			bodyAttachments[d.Name] = d
		end
	end
	local welded = 0
	for _, accessory in model:GetDescendants() do
		if accessory:IsA("Accessory") then
			local handle = accessory:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") and not handle:FindFirstChildWhichIsA("JointInstance") then
				for _, attachment in handle:GetChildren() do
					local target = if attachment:IsA("Attachment") then bodyAttachments[attachment.Name] else nil
					if target and attachment:IsA("Attachment") then
						local weld = Instance.new("Weld")
						weld.Name = "AccessoryWeld"; weld.Part0 = target.Parent :: BasePart; weld.Part1 = handle
						weld.C0 = target.CFrame; weld.C1 = attachment.CFrame; weld.Parent = handle
						welded += 1
						break
					end
				end
			end
		end
	end
	return welded
end

function M.posePreview(model: Model, characterId: string, pose: PreviewPose, t: number)
	if not Roster.has(characterId) then error("CharacterPresenter.posePreview unknown character id " .. characterId) end
	if typeof(t) ~= "number" or t ~= t or math.abs(t) == math.huge then error("CharacterPresenter.posePreview requires finite time") end
	if pose ~= "Stance" and pose ~= "Guard" and pose ~= "Intro" and pose ~= "Victory" and pose ~= "Defeat" then error("CharacterPresenter.posePreview unknown pose " .. tostring(pose)) end
	local rig = previewRigs[model]
	if not rig then
		M.attachAccessories(model)
		rig = MotionPlayer.collectRig(model)
		previewRigs[model] = rig
	end
	local posed = MotionPlayer.namedPose(characterId, pose, t, rig.rootHeight, rig.legLength)
	-- The in-world presenter lowers the root by rootOffset so planted legs bend. Previews must not move the root
	-- (callers frame the clone afterwards), so the floor is raised by the same amount instead: identical body pose.
	local root = model:FindFirstChild("HumanoidRootPart")
	local floorY: number? = nil
	if root and root:IsA("BasePart") then floorY = root.Position.Y - rig.rootHeight - posed.rootOffset.Y end
	MotionPlayer.apply(rig, posed, floorY)
	if Face then
		local expression = if pose == "Victory" then "Smile" elseif pose == "Defeat" then "Pain" elseif pose == "Intro" then "Grit" else "Focused"
		Face.setExpression(model, expression, if pose == "Defeat" then 0.6 else 1)
	end
end
function M.update(f: RenderFrame)
	local c = ctx
	if not c then return end
	local started = os.clock()
	if typeof(f.origin) == "Vector3" then origin = f.origin end
	f = previewFrame(c, f)
	if not localRigs[1] or not localRigs[2] then M.setCharacters(idFromFrame(f, 1) or selectedIds[1], idFromFrame(f, 2) or selectedIds[2]) end
	local p1 = idFromFrame(f, 1) or selectedIds[1]
	local p2 = idFromFrame(f, 2) or selectedIds[2]
	if p1 ~= selectedIds[1] or p2 ~= selectedIds[2] then M.setCharacters(p1, p2) end
	-- Both views carry their rig data before either fighter is sampled (contact aim reads the opponent's height and its
	-- measured standing head/chest/knee heights).
	for i = 1, 2 do
		local rig = localRigs[i]
		local view = f.fighters[i]
		if rig and view then
			view.characterId = rig.characterId
			view.rootHeight = rig.rig.rootHeight
			view.legLength = rig.rig.legLength
			if not rig.aimHeights then rig.aimHeights = MotionPlayer.standingHeights(rig.rig, rig.characterId) end
			view.aimHeights = rig.aimHeights
		end
	end
	for i = 1, 2 do
		local rig = localRigs[i]
		local view = f.fighters[i]
		framePoses[i] = nil
		if rig and view then
			local pose = MotionPlayer.sample(c.config, view, f, i)
			rig.root.CFrame = rootCFrame(view.pos, view.facing, rig.rig.rootHeight, pose.rootOffset, origin)
			MotionPlayer.apply(rig.rig, pose, origin.Y)
			framePoses[i] = pose
			if Face then Face.updateFromView(rig.model, view, if typeof(f.dt) == "number" then f.dt else 1 / 60, { phase = f.phase, winner = f.winner, slot = i }) end
			if rig.flash > 0 then rig.flash -= 1; rig.highlight.Enabled = true; rig.highlight.FillTransparency = math.clamp(1 - (rig.flash / 6) * 0.55, 0.45, 0.85) else rig.highlight.Enabled = rig.mirrorOutline; rig.highlight.FillTransparency = 1 end
		end
	end
	-- Throw grips: once both bodies are posed, gripping hands/feet reach the partner's real body point (the attacker's
	-- grips first, so a defender's grip on the attacker follows the re-solved arm).
	local rigA, rigB = localRigs[1], localRigs[2]
	if rigA and rigB and framePoses[1] and framePoses[2] then
		for pass = 1, 2 do
			for i = 1, 2 do
				local view = f.fighters[i]
				local throw = view and view.throw
				if type(throw) == "table" and (throw.role ~= "Defender") == (pass == 1) then
					MotionPlayer.applyGrips((localRigs[i] :: LiveRig).rig, framePoses[i] :: MotionPlayer.Pose, view, f, i, (localRigs[3 - i] :: LiveRig).rig, origin.Y)
				end
			end
		end
	end
	-- Rolling cost of posing both fighters (sample + IK + ground solver), for the performance budget.
	local ms = (os.clock() - started) * 1000
	updateCostMs += (ms - updateCostMs) * 0.05
	updateCostPeakMs = math.max(updateCostPeakMs * 0.995, ms)
	c.gui:SetAttribute("PresenterCostMs", updateCostMs)
	c.gui:SetAttribute("PresenterCostPeakMs", updateCostPeakMs)
end

function M.init(newCtx: Ctx)
	ctx = newCtx
	ensureFolder()
	local serverFighters = Workspace:FindFirstChild("FightingLabFighters")
	if serverFighters then for _, d in serverFighters:GetDescendants() do hideServerPart(d) end; serverFighters.DescendantAdded:Connect(hideServerPart) end
end

return M
