--!strict
-- Preview / avatar flash detector (round 5). A fighter model may only be on screen when it is complete: every authored
-- clothing and gear item present (accessories, layered-clothing wrap layers, the rigid welded gloves, shoes and belts
-- CharacterFactory adds, classic clothing) and every asset that makes it look dressed loaded (meshes, mesh textures,
-- clothing templates, decals, cages). A frame where a watched model is visible but incomplete is a "bare frame"; a joint
-- that turns more than JUMP_DEGREES between two visible frames of the same model is a "pose pop".
--
-- Pure helpers (inventory, contentIds, check, poseOf, maxJointDelta, step) take injected fetch-status functions, so
-- FlashDetector_Test drives them on the server with fake models. FlashDetector.start() is the live recorder used by
-- the Studio QA run (client): it watches the fighter-select stage rigs, every viewport preview in the PlayerGui and
-- the player characters, and LobbyUI/FighterSelect/AvatarGate use check() as their reveal gate.
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local FlashDetector = {}
FlashDetector.JUMP_DEGREES = 30
FlashDetector.EXTRA_ATTRIBUTE = "FightingLabExtra"
FlashDetector.MAX_SAMPLES = 40

export type Inventory = { accessories: number, wrapLayers: number, extras: number, clothing: number }
export type Check = { complete: boolean, missing: { string }, loading: { string }, failed: { string } }
export type FetchStatus = (contentId: string) -> string

-- Authored items in a model: accessories, wrap layers (layered clothing), rigid extras (welded gear / fists marked
-- FightingLabExtra by CharacterFactory) and classic clothing.
function FlashDetector.inventory(model: Instance): Inventory
	local inv: Inventory = { accessories = 0, wrapLayers = 0, extras = 0, clothing = 0 }
	for _, d in model:GetDescendants() do
		if d:IsA("Accoutrement") then
			inv.accessories += 1
		elseif d:IsA("WrapLayer") then
			inv.wrapLayers += 1
		elseif d:IsA("BasePart") and d:GetAttribute(FlashDetector.EXTRA_ATTRIBUTE) == true then
			inv.extras += 1
		elseif d:IsA("Clothing") or d:IsA("ShirtGraphic") then
			inv.clothing += 1
		end
	end
	return inv
end

local function add(list: { string }, seen: { [string]: boolean }, value: any)
	if typeof(value) ~= "string" or value == "" or seen[value] then return end
	-- Engine-bundled content is always available.
	if string.sub(value, 1, 11) == "rbxasset://" then return end
	seen[value] = true
	table.insert(list, value)
end

local function read(inst: Instance, prop: string): any
	local ok, value = pcall(function() return (inst :: any)[prop] end)
	return if ok then value else nil
end

-- Every asset that decides whether a model looks dressed, split in two:
--   meshes   : body, clothing, hair and gear geometry plus layered-clothing cages. A mesh that is not fetched draws
--              nothing (a bare limb, a missing glove), so it must report Success before the model may show.
--   textures : mesh textures, classic clothing templates and decals. The renderer streams many of these itself
--              (ContentProvider then never sees them and reports None while they are drawn), so a texture only
--              counts as missing while ContentProvider is actively fetching it (Loading).
-- SurfaceAppearance maps are left out entirely: they stream through the renderer's texture pipeline and only sharpen.
function FlashDetector.contentIds(model: Instance): ({ string }, { string })
	local meshes, textures, seen = {}, {}, {}
	for _, d in model:GetDescendants() do
		if d:IsA("MeshPart") then
			add(meshes, seen, read(d, "MeshId"))
			add(textures, seen, read(d, "TextureID"))
		elseif d:IsA("FileMesh") then
			add(meshes, seen, read(d, "MeshId"))
			add(textures, seen, read(d, "TextureId"))
		elseif d:IsA("Shirt") then
			add(textures, seen, read(d, "ShirtTemplate"))
		elseif d:IsA("Pants") then
			add(textures, seen, read(d, "PantsTemplate"))
		elseif d:IsA("ShirtGraphic") then
			add(textures, seen, read(d, "Graphic"))
		elseif d:IsA("Decal") then
			add(textures, seen, read(d, "Texture"))
		elseif d:IsA("BaseWrap") then
			add(meshes, seen, read(d, "CageMeshId"))
			if d:IsA("WrapLayer") then add(meshes, seen, read(d, "ReferenceMeshId")) end
		end
	end
	return meshes, textures
end

-- Live fetch status as a string ("Success", "Loading", "None", "Failure", "TimedOut"). Sticky once resolved: an asset
-- that finished stays finished (a later PreloadAsync of the same id from another clone or gate flips ContentProvider's
-- status back to Loading although the asset is already in memory and drawn), and a failed one stays failed.
local fetchOverride: FetchStatus? = nil
local resolved: { [string]: string } = {}
function FlashDetector.fetchStatus(contentId: string): string
	local override = fetchOverride
	if override then return override(contentId) end
	local done = resolved[contentId]
	if done then return done end
	local ok, status = pcall(function() return ContentProvider:GetAssetFetchStatus(contentId) end)
	if not ok or typeof(status) ~= "EnumItem" then return "None" end
	local name = (status :: EnumItem).Name
	if name == "Success" or name == "Failure" or name == "TimedOut" then resolved[contentId] = name end
	return name
end
-- Tests only: a fake asset fetch status for every check (nil restores ContentProvider).
function FlashDetector._setFetchForTests(fn: FetchStatus?) fetchOverride = fn end

-- Ids a preload still has to fetch: textures (meshes load through their MeshPart / SpecialMesh / WrapLayer instances;
-- a string preload of a mesh id fails in Studio and would overwrite the instance's Success) not finished yet.
function FlashDetector.pendingTextures(model: Instance): { string }
	local _, textures = FlashDetector.contentIds(model)
	local out = {}
	for _, id in textures do
		local s = FlashDetector.fetchStatus(id)
		if s ~= "Success" and s ~= "Failure" and s ~= "TimedOut" then table.insert(out, id) end
	end
	return out
end

-- Complete = at least the expected items are present, every mesh is fetched and no texture is mid-fetch. `expected`
-- nil fields are not checked. Failed assets never finish: they are reported apart and do not block the model.
function FlashDetector.check(model: Instance, expected: Inventory?, fetch: FetchStatus?): Check
	local result: Check = { complete = true, missing = {}, loading = {}, failed = {} }
	if expected then
		local have = FlashDetector.inventory(model)
		for _, key in { "accessories", "wrapLayers", "extras", "clothing" } do
			local want = (expected :: any)[key]
			local got = (have :: any)[key]
			if typeof(want) == "number" and got < want then table.insert(result.missing, string.format("%s %d/%d", key, got, want)) end
		end
	end
	local status = fetch or FlashDetector.fetchStatus
	local meshes, textures = FlashDetector.contentIds(model)
	for _, id in meshes do
		local s = status(id)
		if s == "Failure" or s == "TimedOut" then
			table.insert(result.failed, id)
		elseif s ~= "Success" then
			table.insert(result.loading, id)
		end
	end
	for _, id in textures do
		local s = status(id)
		if s == "Failure" or s == "TimedOut" then
			table.insert(result.failed, id)
		elseif s == "Loading" then
			table.insert(result.loading, id)
		end
	end
	result.complete = #result.missing == 0 and #result.loading == 0
	return result
end

-- Every content id of a model (meshes then textures), e.g. for ContentProvider:PreloadAsync.
function FlashDetector.allContent(model: Instance): { string }
	local meshes, textures = FlashDetector.contentIds(model)
	local all = table.clone(meshes)
	for _, id in textures do table.insert(all, id) end
	return all
end

-- Fighter id behind a template or a straight template clone ("Kael": the fight HUD portraits), a pooled rig
-- ("Pool_Kael_3"), a preview ("Preview_Kael", "Preview_Kael_3") or a character (FighterId / FightingLabFighter
-- attributes).
function FlashDetector.fighterIdOf(model: Instance): string?
	local attr = model:GetAttribute("FightingLabFighter") or model:GetAttribute("FighterId")
	if typeof(attr) == "string" and attr ~= "" then return attr end
	local name = model.Name
	local id = string.match(name, "^Pool_([%a]+)_%d+$") or string.match(name, "^Preview_([%a]+)_%d+$") or string.match(name, "^Preview_([%a]+)$")
	if id then return id end
	local lab = game:GetService("ReplicatedStorage"):FindFirstChild("FightingLab")
	local folder = lab and lab:FindFirstChild("Characters")
	if folder and folder:FindFirstChild(name) then return name end
	return nil
end

-- The authored inventory of a fighter: its template in ReplicatedStorage.FightingLab.Characters.
local templateCache: { [string]: Inventory } = {}
function FlashDetector.templateInventory(id: string?, characters: Instance?): Inventory?
	if not id then return nil end
	local cached = templateCache[id]
	if cached then return cached end
	local folder = characters
	if not folder then
		local lab = game:GetService("ReplicatedStorage"):FindFirstChild("FightingLab")
		folder = lab and lab:FindFirstChild("Characters")
	end
	local template = folder and folder:FindFirstChild(id)
	if not template then return nil end
	local inv = FlashDetector.inventory(template)
	if not characters then templateCache[id] = inv end
	return inv
end
function FlashDetector.clearCache() table.clear(templateCache) end

-- Joint pose: Motor6D Transform rotations keyed by "<Part0>/<Motor name>".
export type Pose = { [string]: CFrame }
function FlashDetector.poseOf(model: Instance): Pose
	local pose: Pose = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then
			local p0 = d.Part0
			pose[(if p0 then p0.Name else "?") .. "/" .. d.Name] = d.Transform.Rotation
		end
	end
	return pose
end

-- Largest joint rotation change between two poses, in degrees (and the joint).
function FlashDetector.maxJointDelta(a: Pose, b: Pose): (number, string?)
	local worst, joint = 0, nil
	for key, ra in a do
		local rb = b[key]
		if rb then
			local _, angle = ra:ToObjectSpace(rb):ToAxisAngle()
			local deg = math.deg(math.abs(angle))
			if deg > 180 then deg = 360 - deg end
			if deg > worst then worst, joint = deg, key end
		end
	end
	return worst, joint
end

--------------------------------------------------------------------------------------------------------------------
-- Recorder: feed it one observation per watched model per frame (step), read the report.
--------------------------------------------------------------------------------------------------------------------
export type Observation = { key: any, label: string, model: Instance, visible: boolean, expected: Inventory? }
export type Sample = { frame: number, label: string, kind: string, detail: string, count: number }
export type Report = {
	frames: number, visibleFrames: number, bareFrames: number, pops: number, failedAssets: number,
	byLabel: { [string]: { visible: number, bare: number, pops: number } }, samples: { Sample },
}

function FlashDetector.newRecorder(opts: { fetch: FetchStatus?, jumpDegrees: number? }?)
	local o = opts or {}
	local recorder = {
		fetch = o.fetch, jump = o.jumpDegrees or FlashDetector.JUMP_DEGREES, frame = 0,
		last = {} :: { [any]: { pose: Pose, visible: boolean } },
		report = { frames = 0, visibleFrames = 0, bareFrames = 0, pops = 0, failedAssets = 0, byLabel = {}, samples = {} } :: Report,
		failedSeen = {} :: { [string]: boolean },
	}
	-- Samples are deduplicated per (kind, label, detail); a repeat only bumps the count.
	local sampleIndex: { [string]: Sample } = {}
	local function sample(kind: string, label: string, detail: string)
		local r = recorder.report
		local key = kind .. "|" .. label .. "|" .. detail
		local existing = sampleIndex[key]
		if existing then existing.count += 1; return end
		if #r.samples < FlashDetector.MAX_SAMPLES then
			local s: Sample = { frame = recorder.frame, label = label, kind = kind, detail = detail, count = 1 }
			sampleIndex[key] = s
			table.insert(r.samples, s)
		end
	end
	-- One frame: every watched model's observation. Returns the bare and pop counts of this frame.
	function recorder.step(observations: { Observation }): (number, number)
		recorder.frame += 1
		local r = recorder.report
		r.frames += 1
		local bare, pops = 0, 0
		local seen: { [any]: boolean } = {}
		for _, obs in observations do
			seen[obs.key] = true
			local stats = r.byLabel[obs.label]
			if not stats then stats = { visible = 0, bare = 0, pops = 0 }; r.byLabel[obs.label] = stats end
			local prev = recorder.last[obs.key]
			local pose = FlashDetector.poseOf(obs.model)
			if obs.visible then
				r.visibleFrames += 1
				stats.visible += 1
				local c = FlashDetector.check(obs.model, obs.expected, recorder.fetch)
				for _, id in c.failed do
					if not recorder.failedSeen[id] then recorder.failedSeen[id] = true; r.failedAssets += 1 end
				end
				if not c.complete then
					bare += 1
					stats.bare += 1
					sample("bare", obs.label, table.concat(c.missing, ", ") .. (if #c.loading > 0 then string.format(" loading %d (%s)", #c.loading, c.loading[1]) else ""))
				end
				if prev and prev.visible then
					local delta, joint = FlashDetector.maxJointDelta(prev.pose, pose)
					if delta > recorder.jump then
						pops += 1
						stats.pops += 1
						sample("pop", obs.label, string.format("%s turned %.0f deg in one frame", tostring(joint), delta))
					end
				end
			end
			recorder.last[obs.key] = { pose = pose, visible = obs.visible }
		end
		for key in recorder.last do
			if not seen[key] then recorder.last[key] = nil end
		end
		r.bareFrames += bare
		r.pops += pops
		return bare, pops
	end
	return recorder
end

--------------------------------------------------------------------------------------------------------------------
-- Live watch list (client)
--------------------------------------------------------------------------------------------------------------------
local function guiVisible(obj: Instance): boolean
	local node: Instance? = obj
	while node do
		if node:IsA("GuiObject") then
			if not node.Visible then return false end
		elseif node:IsA("LayerCollector") then
			return (node :: any).Enabled == true
		end
		node = node.Parent
	end
	return false
end

-- An opaque cover drawn over a viewport (FighterSelect tiles, the identity portrait): a visible sibling named "Cover"
-- with an opaque background hides the viewport completely.
local function covered(vp: ViewportFrame): boolean
	local parent = vp.Parent
	if not parent then return false end
	for _, sibling in parent:GetChildren() do
		if sibling ~= vp and sibling.Name == "Cover" and sibling:IsA("GuiObject") and sibling.Visible and sibling.BackgroundTransparency <= 0.02 then
			return true
		end
	end
	return false
end

local function viewportVisible(vp: ViewportFrame): boolean
	return guiVisible(vp) and vp.ImageTransparency < 0.98 and not covered(vp)
end

-- A character or in-world rig shows when one of its body parts renders (server concealment writes 0.999, the client
-- gates write LocalTransparencyModifier = 1).
local BODY = { "Head", "UpperTorso", "LowerTorso", "LeftUpperArm", "RightUpperArm", "LeftUpperLeg", "RightUpperLeg" }
function FlashDetector.bodyRenders(model: Instance): boolean
	for _, name in BODY do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") and part.Transparency < 0.99 and part.LocalTransparencyModifier < 0.99 then return true end
	end
	return false
end

local function onScreen(camera: Camera, model: Model): boolean
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if not root or not root:IsA("BasePart") then return false end
	local _, inView = camera:WorldToViewportPoint(root.Position)
	return inView and (root.Position - camera.CFrame.Position).Magnitude < 400
end

-- A full-screen black fade (fighter select cuts, lobby teleports) hides everything behind it.
local function screenBlack(playerGui: Instance?): boolean
	if not playerGui then return false end
	for _, gui in playerGui:GetChildren() do
		if gui:IsA("ScreenGui") and gui.Enabled and (gui.Name == "FightingLabSelectFade" or gui.Name == "FightingLabTravelFade") then
			local black = gui:FindFirstChild("Black")
			if black and black:IsA("GuiObject") and black.Visible and black.BackgroundTransparency <= 0.02 then return true end
		end
	end
	return false
end

-- Every watched model this frame: viewport previews in the PlayerGui, pooled preview rigs in the local render folder
-- and player characters.
function FlashDetector.observe(): { Observation }
	local out: { Observation } = {}
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	local camera = workspace.CurrentCamera
	local black = screenBlack(playerGui)
	if playerGui then
		for _, vp in playerGui:GetDescendants() do
			if vp:IsA("ViewportFrame") then
				local vpShown = not black and viewportVisible(vp)
				for _, m in vp:GetDescendants() do
					if m:IsA("Model") and m:FindFirstChildOfClass("Humanoid") then
						local id = FlashDetector.fighterIdOf(m)
						table.insert(out, { key = m, label = "viewport:" .. (vp.Parent and vp.Parent.Name or "?") .. "/" .. tostring(id), model = m, visible = vpShown, expected = FlashDetector.templateInventory(id) })
					end
				end
			end
		end
	end
	local render = workspace:FindFirstChild("FightingLabLocalRender")
	if render and camera then
		for _, m in render:GetChildren() do
			if m:IsA("Model") and string.sub(m.Name, 1, 8) == "Preview_" then
				local id = FlashDetector.fighterIdOf(m)
				local shown = not black and FlashDetector.bodyRenders(m) and onScreen(camera, m)
				table.insert(out, { key = m, label = "select:" .. tostring(id), model = m, visible = shown, expected = FlashDetector.templateInventory(id) })
			end
		end
	end
	for _, p in Players:GetPlayers() do
		local character = p.Character
		if character and character.Parent and camera then
			-- The character's own fighter (a fighter change flips the player's FighterId before the old body goes).
			local id = FlashDetector.fighterIdOf(character)
			if not id then
				local attr = p:GetAttribute("FighterId")
				id = if typeof(attr) == "string" then attr else nil
			end
			local shown = not black and FlashDetector.bodyRenders(character) and onScreen(camera, character)
			table.insert(out, { key = character, label = "character:" .. p.Name .. "/" .. tostring(id), model = character, visible = shown, expected = FlashDetector.templateInventory(id) })
		end
	end
	return out
end

-- Live recorder bound after every other render step. Returns { stop = () -> Report, report = () -> Report }.
local running: any = nil
function FlashDetector.start(opts: { jumpDegrees: number?, onFrame: ((bare: number, pops: number) -> ())? }?): any
	if running then running.stop() end
	local o = opts or {}
	local recorder = FlashDetector.newRecorder({ jumpDegrees = o.jumpDegrees })
	local name = "FightingLabFlashDetector"
	local stopped = false
	RunService:BindToRenderStep(name, Enum.RenderPriority.Last.Value + 10, function()
		local ok, bare, pops = pcall(function() return recorder.step(FlashDetector.observe()) end)
		if ok and o.onFrame then o.onFrame(bare, pops) end
	end)
	local handle = {}
	function handle.report(): Report return recorder.report end
	function handle.stop(): Report
		if not stopped then
			stopped = true
			pcall(function() RunService:UnbindFromRenderStep(name) end)
			if running == handle then running = nil end
		end
		return recorder.report
	end
	running = handle
	return handle
end

function FlashDetector.active(): any return running end

-- One-line summary plus per-label and sample lines (QA logs).
function FlashDetector.summary(r: Report): string
	local lines = { string.format("frames=%d visibleModelFrames=%d bareFrames=%d posePops=%d failedAssets=%d", r.frames, r.visibleFrames, r.bareFrames, r.pops, r.failedAssets) }
	local labels = {}
	for label in r.byLabel do table.insert(labels, label) end
	table.sort(labels)
	for _, label in labels do
		local s = r.byLabel[label]
		table.insert(lines, string.format("  %s visible=%d bare=%d pops=%d", label, s.visible, s.bare, s.pops))
	end
	for _, s in r.samples do
		table.insert(lines, string.format("  #%d %s %s %s (x%d)", s.frame, s.kind, s.label, s.detail, s.count))
	end
	return table.concat(lines, "\n")
end

return FlashDetector
