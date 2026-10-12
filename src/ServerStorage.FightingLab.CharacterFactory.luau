--!strict
-- FightingLab CharacterFactory: builds an original fighter template from a catalog-avatar spec.
-- Runs in Edit mode (command/plugin context) or on the server. Produces a standard R15 Motor6D rig
-- with skinned avatar body parts, layered clothing and accessories, ready for CharacterPresenter.
-- Factory.dressCharacter adds the same non-description extras (accessory tints, gear, fists, hidden hands) to a live
-- player character spawned with player:LoadCharacterWithHumanoidDescription(Factory.describe(spec)).
local AssetService = game:GetService("AssetService")
local InsertService = game:GetService("InsertService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- Tint multiplies the accessory's SurfaceAppearance ColorMap (PBR detail is kept), used to put each fighter's palette
-- on neutral textured garments.
export type Accessory = { AssetId: number, AccessoryType: string, IsLayered: boolean?, Order: number?, Puffiness: number?, Position: { number }?, Rotation: { number }?, Scale: { number }?, Tint: { number }? }
export type FistSpec = { meshId: string, textureId: string?, color: { number }, material: string?, scale: { number }?, offset: { number }?, rotation: { number }? }
export type FistsSpec = { shared: FistSpec?, Left: FistSpec?, Right: FistSpec? }
export type BandSpec = { width: number, inflate: number?, inflateZ: number? }
export type GearSpec = { assetId: number?, band: BandSpec?, name: string?, target: string, color: { number }?, tint: { number }?, material: string?, clearTexture: boolean?, scale: { number }?, fit: { number }?, offset: { number }?, rotation: { number }?, hideTarget: boolean?, seat: string?, role: string? }
export type Spec = {
	id: string,
	displayName: string,
	tagline: string,
	style: string,
	primaryColor: { number },
	accentColor: { number },
	skinColor: { number },
	bodyColors: { [string]: { number } }?,
	scales: { Height: number?, Width: number?, Depth: number?, Head: number?, BodyType: number?, Proportion: number? }?,
	rootHeight: number?,
	bodyParts: { Head: number?, Torso: number?, LeftArm: number?, RightArm: number?, LeftLeg: number?, RightLeg: number? }?,
	face: number?,
	mood: number?,
	accessories: { Accessory }?,
	fists: FistsSpec?,
	gear: { GearSpec }?,
	hideHands: boolean?,
	-- "high" (high-tops/boots), "low" or "barefoot": the shoe-size bounds CharacterLook_Test applies (shoes are gear
	-- with role "shoe", seat "sole").
	shoeStyle: string?,
	shirt: number?,
	pants: number?,
	graphicTShirt: number?,
	sourceAssets: { { id: number, name: string, creator: string, kind: string } }?,
}

local Factory = {}

local BODY_COLOR_FIELDS = { "HeadColor", "TorsoColor", "LeftArmColor", "RightArmColor", "LeftLegColor", "RightLegColor" }
local BODY_COLOR_KEYS = { HeadColor = "Head", TorsoColor = "Torso", LeftArmColor = "LeftArm", RightArmColor = "RightArm", LeftLegColor = "LeftLeg", RightLegColor = "RightLeg" }
local R15_PARTS = { "HumanoidRootPart", "LowerTorso", "UpperTorso", "Head", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot" }
local R15_JOINTS = {
	{ "Root", "HumanoidRootPart", "LowerTorso", "RootRigAttachment" },
	{ "Waist", "LowerTorso", "UpperTorso", "WaistRigAttachment" },
	{ "Neck", "UpperTorso", "Head", "NeckRigAttachment" },
	{ "LeftShoulder", "UpperTorso", "LeftUpperArm", "LeftShoulderRigAttachment" },
	{ "LeftElbow", "LeftUpperArm", "LeftLowerArm", "LeftElbowRigAttachment" },
	{ "LeftWrist", "LeftLowerArm", "LeftHand", "LeftWristRigAttachment" },
	{ "RightShoulder", "UpperTorso", "RightUpperArm", "RightShoulderRigAttachment" },
	{ "RightElbow", "RightUpperArm", "RightLowerArm", "RightElbowRigAttachment" },
	{ "RightWrist", "RightLowerArm", "RightHand", "RightWristRigAttachment" },
	{ "LeftHip", "LowerTorso", "LeftUpperLeg", "LeftHipRigAttachment" },
	{ "LeftKnee", "LeftUpperLeg", "LeftLowerLeg", "LeftKneeRigAttachment" },
	{ "LeftAnkle", "LeftLowerLeg", "LeftFoot", "LeftAnkleRigAttachment" },
	{ "RightHip", "LowerTorso", "RightUpperLeg", "RightHipRigAttachment" },
	{ "RightKnee", "RightUpperLeg", "RightLowerLeg", "RightKneeRigAttachment" },
	{ "RightAnkle", "RightLowerLeg", "RightFoot", "RightAnkleRigAttachment" },
}

local function rgb(c: { number }, label: string): Color3
	assert(#c == 3, "CharacterFactory: " .. label .. " must be {r,g,b}")
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function materialFromName(name: string?): Enum.Material
	if not name then return Enum.Material.SmoothPlastic end
	for _, item in Enum.Material:GetEnumItems() do
		if item.Name == name then return item end
	end
	error("CharacterFactory: unknown Material " .. tostring(name))
end

local function vectorFromArray(values: { number }?, fallback: Vector3, label: string): Vector3
	if not values then return fallback end
	assert(#values == 3, "CharacterFactory: " .. label .. " must be {x,y,z}")
	return Vector3.new(values[1], values[2], values[3])
end

local function accessoryType(name: string): Enum.AccessoryType
	for _, item in Enum.AccessoryType:GetEnumItems() do
		if item.Name == name then
			return item
		end
	end
	error("CharacterFactory: unknown AccessoryType " .. name)
end

function Factory.describe(spec: Spec): HumanoidDescription
	local desc = Instance.new("HumanoidDescription")
	local skin = rgb(spec.skinColor, "skinColor")
	for _, field in BODY_COLOR_FIELDS do
		local override = spec.bodyColors and spec.bodyColors[BODY_COLOR_KEYS[field]]
		;(desc :: any)[field] = if override then rgb(override, field) else skin
	end
	local scales = spec.scales
	if scales then
		desc.HeightScale = scales.Height or 1
		desc.WidthScale = scales.Width or 1
		desc.DepthScale = scales.Depth or 1
		desc.HeadScale = scales.Head or 1
		desc.BodyTypeScale = scales.BodyType or 0
		desc.ProportionScale = scales.Proportion or 0
	end
	local parts = spec.bodyParts
	if parts then
		desc.Head = parts.Head or 0
		desc.Torso = parts.Torso or 0
		desc.LeftArm = parts.LeftArm or 0
		desc.RightArm = parts.RightArm or 0
		desc.LeftLeg = parts.LeftLeg or 0
		desc.RightLeg = parts.RightLeg or 0
	end
	desc.Face = spec.face or 0
	-- Dynamic heads animate through a mood asset; it must not be put in the Face (decal) slot.
	desc.MoodAnimation = spec.mood or 0
	desc.Shirt = spec.shirt or 0
	desc.Pants = spec.pants or 0
	desc.GraphicTShirt = spec.graphicTShirt or 0
	local list = {}
	for _, acc in spec.accessories or {} do
		local entry: { [string]: any } = { AssetId = acc.AssetId, AccessoryType = accessoryType(acc.AccessoryType), IsLayered = acc.IsLayered == true }
		if acc.IsLayered then
			entry.Order = acc.Order or 1
			entry.Puffiness = acc.Puffiness or 1
		end
		if acc.Position then entry.Position = Vector3.new(acc.Position[1], acc.Position[2], acc.Position[3]) end
		if acc.Rotation then entry.Rotation = Vector3.new(acc.Rotation[1], acc.Rotation[2], acc.Rotation[3]) end
		if acc.Scale then entry.Scale = Vector3.new(acc.Scale[1], acc.Scale[2], acc.Scale[3]) end
		table.insert(list, entry)
	end
	desc:SetAccessories(list, true)
	return desc
end

local function ensureR15Motors(model: Model)
	for _, joint in R15_JOINTS do
		local name = joint[1]
		local hasMotor = false
		for _, d in model:GetDescendants() do
			if d:IsA("Motor6D") and d.Name == name then
				hasMotor = true
				break
			end
		end
		if not hasMotor then
			local part0 = model:FindFirstChild(joint[2])
			local part1 = model:FindFirstChild(joint[3])
			assert(part0 and part0:IsA("BasePart"), "CharacterFactory: rig missing " .. joint[2])
			assert(part1 and part1:IsA("BasePart"), "CharacterFactory: rig missing " .. joint[3])
			local a0 = part0:FindFirstChild(joint[4])
			local a1 = part1:FindFirstChild(joint[4])
			assert(a0 and a0:IsA("Attachment"), "CharacterFactory: " .. joint[2] .. " missing " .. joint[4])
			assert(a1 and a1:IsA("Attachment"), "CharacterFactory: " .. joint[3] .. " missing " .. joint[4])
			local motor = Instance.new("Motor6D")
			motor.Name = name
			motor.Part0 = part0
			motor.Part1 = part1
			motor.C0 = a0.CFrame
			motor.C1 = a1.CFrame
			motor.Parent = part0
		end
	end
end

local meshCache: { [string]: MeshPart } = {}

local function firstAssetId(text: string): string
	local id = text:match("%d+")
	assert(id, "CharacterFactory: expected Roblox asset id in " .. text)
	return id
end

local function loadMeshPrototype(meshId: string): MeshPart
	local assetId = firstAssetId(meshId)
	local cached = meshCache[assetId]
	if cached then return cached:Clone() end
	local prototype = AssetService:CreateMeshPartAsync(Content.fromUri("rbxassetid://" .. assetId), { CollisionFidelity = Enum.CollisionFidelity.Box })
	meshCache[assetId] = prototype
	return prototype:Clone()
end

-- Parts the factory adds outside the HumanoidDescription (gear, fists) carry this attribute, so dressCharacter can find
-- and replace exactly its own extras on a live character without touching anything else.
local EXTRA_ATTRIBUTE = "FightingLabExtra"
local HIDDEN_ATTRIBUTE = "FightingLabHiddenByGear"
local DRESSED_ATTRIBUTE = "FightingLabDressed"
local SOLE_PROXY_ATTRIBUTE = "FightingLabSoleProxy"
local BARE_FOOT_SIZE_ATTRIBUTE = "FightingLabBareFootSize"
local GROUND_SIZE_ATTRIBUTE = "FightingLabShoeGroundSize"
local GROUND_CENTER_ATTRIBUTE = "FightingLabShoeGroundCenter"

local function findPart(model: Model, name: string): BasePart
	local part = model:FindFirstChild(name) or model:FindFirstChild(name, true)
	assert(part and part:IsA("BasePart"), "CharacterFactory: rig part missing " .. name)
	return part
end

local function prepareExtraPart(part: BasePart)
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.Anchored = false
	part:SetAttribute(EXTRA_ATTRIBUTE, true)
end

-- Welds by an explicit offset (C0), never from the parts' current CFrames, so the result is identical on an anchored
-- template and on an unanchored character that is walking (or mid-physics-step) while it is dressed.
local function weldTo(target: BasePart, part: BasePart, c0: CFrame, name: string)
	part.CFrame = target.CFrame * c0
	local weld = Instance.new("Weld")
	weld.Name = name
	weld.Part0 = target
	weld.Part1 = part
	weld.C0 = c0
	weld.C1 = CFrame.identity
	weld.Parent = part
end

local function addFist(model: Model, handName: string, spec: FistSpec)
	local hand = findPart(model, handName)
	hand.Transparency = 1
	local fist = loadMeshPrototype(spec.meshId)
	fist.Name = if handName == "LeftHand" then "LeftFist" else "RightFist"
	fist.Color = rgb(spec.color, fist.Name .. ".color")
	fist.Material = materialFromName(spec.material)
	-- Fists sit just past the wrist joint and are sized from the hand's width/depth (the open-hand mesh is long because
	-- of the fingers). `scale` multiplies that default size and `offset` nudges the seated position.
	local wrist = hand:FindFirstChild(if handName == "LeftHand" then "LeftWristRigAttachment" else "RightWristRigAttachment")
	assert(wrist and wrist:IsA("Attachment"), "CharacterFactory: " .. handName .. " needs a wrist rig attachment for fists")
	local scale = vectorFromArray(spec.scale, Vector3.one, fist.Name .. ".scale")
	local baseSize = Vector3.new(math.clamp(hand.Size.X * 1.3, 0.30, 0.55), math.clamp(hand.Size.Y * 0.52, 0.30, 0.42), math.clamp(hand.Size.Z * 1.25, 0.34, 0.60))
	fist.Size = baseSize * scale
	prepareExtraPart(fist)
	local offset = vectorFromArray(spec.offset, Vector3.zero, fist.Name .. ".offset")
	local rotation = vectorFromArray(spec.rotation, Vector3.zero, fist.Name .. ".rotation")
	local seat = CFrame.new(0, wrist.Position.Y - fist.Size.Y * 0.5 - 0.03, 0)
	weldTo(hand, fist, seat * CFrame.new(offset) * CFrame.Angles(math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z)), "FistWeld")
	fist.Parent = hand
end

local function addFists(model: Model, fists: FistsSpec?)
	if not fists then return end
	local left = fists.Left or fists.shared
	local right = fists.Right or fists.shared
	assert(left, "CharacterFactory: fists requires Left or shared")
	assert(right, "CharacterFactory: fists requires Right or shared")
	addFist(model, "LeftHand", left)
	addFist(model, "RightHand", right)
end

local gearCache: { [number]: BasePart } = {}

local function loadGearPart(assetId: number): BasePart
	local cached = gearCache[assetId]
	if cached then return cached:Clone() end
	local asset = InsertService:LoadAsset(assetId)
	local found: BasePart? = nil
	for _, d in asset:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "Handle" then
			found = d
			break
		elseif d:IsA("BasePart") and not found then
			found = d
		end
	end
	assert(found, "CharacterFactory: gear asset " .. tostring(assetId) .. " did not contain a BasePart")
	local prototype = found:Clone()
	asset:Destroy()
	-- Accessory handles carry body-attachment helpers, layered-clothing cages and occasional scripts; a welded gear part
	-- needs none of them (a rigid shoe cut from a layered shoe must not try to wrap onto the body).
	for _, d in prototype:GetDescendants() do
		if d:IsA("Attachment") or d:IsA("LuaSourceContainer") or d:IsA("JointInstance") or d:IsA("WeldConstraint") or d:IsA("Constraint") or d:IsA("TouchTransmitter") or d:IsA("BaseWrap") then
			d:Destroy()
		end
	end
	gearCache[assetId] = prototype
	return prototype:Clone()
end

-- A band is a procedural elliptical ring (tape, armband, sash) sized from the target part's cross-section, so it hugs
-- any body shape: Size = (width along the limb, target.X * inflate, target.Z * inflateZ), turned so its axis is the
-- target's Y axis. No catalog asset is involved. Legacy: since OV6 every shipped fighter wears textured catalog items
-- instead (hand wraps, sash), and CharacterLook_Test rejects untextured bands in the shipped specs.
local BAND_TURN = CFrame.Angles(0, 0, math.rad(90))

local function makeBand(item: GearSpec, target: BasePart): BasePart
	local band = item.band :: BandSpec
	assert(type(band.width) == "number" and band.width > 0, "CharacterFactory: band.width must be a positive number")
	local inflate = band.inflate or 1.1
	local part = Instance.new("Part")
	part.Name = item.name or "Band"
	part.Size = Vector3.new(band.width, target.Size.X * inflate, target.Size.Z * (band.inflateZ or inflate))
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Color = rgb(item.color or { 236, 234, 226 }, part.Name .. ".color")
	part.Material = materialFromName(item.material or "SmoothPlastic")
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Cylinder
	mesh.Parent = part
	return part
end

local function hideGearTarget(target: BasePart, item: GearSpec)
	if item.hideTarget then
		target.Transparency = 1
		target:SetAttribute(HIDDEN_ATTRIBUTE, true)
	end
end

-- Gear parts are parented under their target body part: if a live character's body part is ever replaced, its gear
-- goes with it instead of falling out of the world. Returns the asset ids of gear pieces that could not be loaded.
local function addGear(model: Model, gear: { GearSpec }?): { number }
	local skipped: { number } = {}
	for _, item in gear or {} do
		local target = findPart(model, item.target)
		if item.band then
			local part = makeBand(item, target)
			prepareExtraPart(part)
			local offset = vectorFromArray(item.offset, Vector3.zero, part.Name .. ".offset")
			local rotation = vectorFromArray(item.rotation, Vector3.zero, part.Name .. ".rotation")
			weldTo(target, part, CFrame.new(offset) * CFrame.Angles(math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z)) * BAND_TURN, "GearWeld")
			part.Parent = target
			hideGearTarget(target, item)
			continue
		end
		assert(type(item.assetId) == "number", "CharacterFactory: gear needs an assetId or a band")
		-- A catalog outage must not cost the whole fighter: the gear piece is skipped (and reported) instead, and its
		-- target stays visible.
		local loaded, result = pcall(loadGearPart, item.assetId :: number)
		if not loaded then
			warn(string.format("CharacterFactory: skipped gear %s (%s): %s", tostring(item.name), tostring(item.assetId), tostring(result)))
			table.insert(skipped, item.assetId :: number)
			continue
		end
		hideGearTarget(target, item)
		local part = result :: BasePart
		part.Name = item.name or ("Gear_" .. tostring(item.assetId))
		-- clearTexture drops the asset's own texture so `color` + `material` (e.g. Fabric, Leather) define the look.
		if item.clearTexture and part:IsA("MeshPart") then
			part.TextureID = ""
			for _, d in part:GetDescendants() do
				if d:IsA("SurfaceAppearance") then d:Destroy() end
			end
		end
		if item.color then part.Color = rgb(item.color, part.Name .. ".color") end
		if item.material then part.Material = materialFromName(item.material) end
		if item.tint then
			local tint = rgb(item.tint, part.Name .. ".tint")
			for _, d in part:GetDescendants() do
				if d:IsA("SurfaceAppearance") then d.Color = tint end
			end
		end
		local scale = vectorFromArray(item.scale, Vector3.one, part.Name .. ".scale")
		part.Size = Vector3.new(part.Size.X * scale.X, part.Size.Y * scale.Y, part.Size.Z * scale.Z)
		-- `fit` sizes the gear relative to its target body part instead (robust across body shapes and scales).
		if item.fit then
			local fit = vectorFromArray(item.fit, Vector3.one, part.Name .. ".fit")
			part.Size = Vector3.new(target.Size.X * fit.X, target.Size.Y * fit.Y, target.Size.Z * fit.Z)
		end
		prepareExtraPart(part)
		local offset = vectorFromArray(item.offset, Vector3.zero, part.Name .. ".offset")
		-- `seat = "sole"` (shoes): the part's bottom rests on the target's bottom face, the sole that the ground solver
		-- plants on the floor, so a shoe never sinks into the floor or floats above it; `offset` moves it from there.
		if item.seat == "sole" then
			offset += Vector3.new(0, (part.Size.Y - target.Size.Y) * 0.5, 0)
		elseif item.seat ~= nil then
			error("CharacterFactory: unknown gear seat " .. tostring(item.seat))
		end
		if item.role then part:SetAttribute("FightingLabRole", item.role) end
		local rotation = vectorFromArray(item.rotation, Vector3.zero, part.Name .. ".rotation")
		local isHandFist = (part.Name == "LeftFist" and target.Name == "LeftHand") or (part.Name == "RightFist" and target.Name == "RightHand")
		weldTo(target, part, CFrame.new(offset) * CFrame.Angles(math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z)), if isHandFist then "FistWeld" else "GearWeld")
		-- A skinned catalog mesh (e.g. a layered shoe used as a rigid shoe) parented straight into the rig would be
		-- skinned onto the rig's own parts by bone name and render twisted; inside its own Model it renders as welded.
		local okSkinned, skinned = pcall(function() return part:IsA("MeshPart") and (part :: MeshPart).HasSkinnedMesh end)
		if okSkinned and skinned then
			local holder = Instance.new("Model")
			holder.Name = part.Name .. "Rigid"
			holder:SetAttribute(EXTRA_ATTRIBUTE, true)
			part.Parent = holder
			holder.Parent = target
		else
			part.Parent = target
		end
	end
	return skipped
end

local function applyHandVisibility(model: Model, hideHands: boolean?)
	for _, name in { "LeftHand", "RightHand" } do
		findPart(model, name).Transparency = if hideHands then 1 else 0
	end
end

-- Maps each applied catalog accessory back to its instance through the Humanoid's applied HumanoidDescription.
local function appliedAccessories(model: Model): { [number]: { Accessory } }
	local map: { [number]: { Accessory } } = {}
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local description = humanoid and humanoid:FindFirstChildOfClass("HumanoidDescription")
	if not description then return map end
	for _, child in description:GetChildren() do
		if child:IsA("AccessoryDescription") then
			local ok, inst = pcall(function() return child:GetAppliedInstance() end)
			if ok and inst and inst:IsA("Accessory") then
				local list = map[child.AssetId] or {}
				table.insert(list, inst)
				map[child.AssetId] = list
			end
		end
	end
	return map
end

-- Authored accessories that are not on the rig (asset unavailable, moderated, or an AccessoryType that does not match
-- the catalog asset, which HumanoidDescription silently drops). build() records them in the MissingAccessories
-- attribute so a broken outfit is visible instead of silently shipping a half-dressed fighter.
function Factory.missingAccessories(model: Model, spec: Spec): { number }
	local map = appliedAccessories(model)
	local missing = {}
	for _, acc in spec.accessories or {} do
		if not map[acc.AssetId] then table.insert(missing, acc.AssetId) end
	end
	return missing
end

-- Returns how many SurfaceAppearances were tinted. Tints are cosmetic: a missing accessory is skipped, not fatal
-- (CharacterLook_Test checks that every authored tint landed on the templates).
local function applyTints(model: Model, accessories: { Accessory }?): number
	local tinted = 0
	local map: { [number]: { Accessory } }? = nil
	for _, acc in accessories or {} do
		if acc.Tint then
			local found = map or appliedAccessories(model)
			map = found
			local color = rgb(acc.Tint, "Tint")
			for _, inst in found[acc.AssetId] or {} do
				for _, d in inst:GetDescendants() do
					if d:IsA("SurfaceAppearance") then
						d.Color = color
						tinted += 1
					end
				end
			end
		end
	end
	return tinted
end

local function applyExtras(model: Model, spec: Spec): { number }
	addFists(model, spec.fists)
	local skipped = addGear(model, spec.gear)
	applyHandVisibility(model, spec.hideHands)
	applyTints(model, spec.accessories)
	return skipped
end

local function extrasSignature(spec: Spec): string
	local parts = { spec.id, if spec.hideHands then "hidden-hands" else "hands", if spec.fists then "fists" else "no-fists" }
	for _, g in spec.gear or {} do
		table.insert(parts, string.format("%s@%s", if g.assetId then tostring(g.assetId) else "band:" .. tostring(g.name), g.target))
	end
	for _, a in spec.accessories or {} do
		if a.Tint then table.insert(parts, string.format("%d#%s", a.AssetId, table.concat(a.Tint, ","))) end
	end
	return table.concat(parts, "|")
end

local function intactExtras(character: Model): number
	local count = 0
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute(EXTRA_ATTRIBUTE) == true then
			local weld = d:FindFirstChildOfClass("Weld")
			if weld and weld.Part0 and weld.Part0:IsDescendantOf(character) and weld.Part1 == d then count += 1 end
		end
	end
	return count
end

-- Adds the spec's non-description extras (accessory tints, gear, fists, hidden hands) to a live Humanoid character
-- spawned with player:LoadCharacterWithHumanoidDescription(Factory.describe(spec)). Server-side; call after
-- CharacterAppearanceLoaded. Idempotent: a second call with the same spec only re-asserts tints/hand visibility;
-- a different spec (or damaged extras) replaces the previous extras. Nothing is anchored and every extra is massless
-- and non-colliding, so walking physics are unchanged.
function Factory.dressCharacter(character: Model, spec: Spec): Model
	assert(typeof(character) == "Instance" and character:IsA("Model"), "CharacterFactory.dressCharacter: character must be a Model")
	assert(type(spec) == "table" and type(spec.id) == "string", "CharacterFactory.dressCharacter: spec must be a fighter spec table")
	assert(character:FindFirstChildOfClass("Humanoid"), "CharacterFactory.dressCharacter: " .. character.Name .. " has no Humanoid")
	local signature = extrasSignature(spec)
	local expected = #(spec.gear or {}) + (if spec.fists then 2 else 0)
	if character:GetAttribute(DRESSED_ATTRIBUTE) == signature and intactExtras(character) == expected then
		applyHandVisibility(character, spec.hideHands)
		applyTints(character, spec.accessories)
		return character
	end
	for _, d in character:GetDescendants() do
		if d:GetAttribute(EXTRA_ATTRIBUTE) == true then
			d:Destroy()
		elseif d:IsA("BasePart") and d:GetAttribute(HIDDEN_ATTRIBUTE) == true then
			d.Transparency = 0
			d:SetAttribute(HIDDEN_ATTRIBUTE, nil)
		end
	end
	applyExtras(character, spec)
	character:SetAttribute(DRESSED_ATTRIBUTE, signature)
	character:SetAttribute("FightingLabFighter", spec.id)
	return character
end

local function buildTempFolder(): Folder
	local folder = Workspace:FindFirstChild("_FightingLabCharacterBuildTemp")
	if folder and folder:IsA("Folder") then return folder end
	folder = Instance.new("Folder")
	folder.Name = "_FightingLabCharacterBuildTemp"
	folder.Parent = Workspace
	return folder
end

-- Distance from the root down to the lowest point of the feet, measured in the neutral pose.
local function measureRootHeight(model: Model, root: BasePart): number
	local lowest = math.huge
	for _, name in { "LeftFoot", "RightFoot" } do
		local foot = model:FindFirstChild(name)
		assert(foot and foot:IsA("BasePart"), "CharacterFactory: rig missing " .. name)
		local cf, size = foot.CFrame, foot.Size
		for _, sx in { -0.5, 0.5 } do
			for _, sy in { -0.5, 0.5 } do
				for _, sz in { -0.5, 0.5 } do
					lowest = math.min(lowest, (cf * Vector3.new(size.X * sx, size.Y * sy, size.Z * sz)).Y)
				end
			end
		end
	end
	return root.Position.Y - lowest
end

-- Fight templates only. A shoe is longer than the bare foot inside it, and the ground solver (MotionPlayer) plants,
-- tips onto the ball and lays down the foot part's box; a shoe toe past that box would sink into the floor whenever
-- the foot pitches (rear foot on its ball, lying, getting up). Where the bare foot is hidden under its shoe (boots,
-- high-tops, tabi), the hidden foot part becomes the shoe's ground box: it takes the shoe's length and width and moves
-- under it, keeping its height, bottom face and ankle joint, so RootHeight and leg length do not change. Joints,
-- welds and attachments on the foot are re-expressed so nothing visible moves. The Humanoid's automatic scaling
-- re-derives body part sizes and rig attachments from their OriginalSize / OriginalPosition values whenever a rig is
-- parented into the world, so those are re-expressed too (per axis, with the scale the Humanoid applies to this foot).
-- The bare foot box is kept in the FightingLabBareFootSize attribute. A visible foot (low shoes) keeps its box; its
-- shoe's ground box (foot space: size, centre) is published as FightingLabShoeGroundSize / FightingLabShoeGroundCenter.
local function fitSoleProxies(model: Model)
	for _, name in { "LeftFoot", "RightFoot" } do
		local found = model:FindFirstChild(name)
		if not found or not found:IsA("BasePart") then continue end
		local foot = found :: BasePart
		local lo = Vector3.new(math.huge, math.huge, math.huge)
		local hi = -lo
		for _, d in foot:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("FightingLabRole") == "shoe" then
				local rel = foot.CFrame:ToObjectSpace(d.CFrame)
				local h = d.Size * 0.5
				for _, sx in { -1, 1 } do
					for _, sy in { -1, 1 } do
						for _, sz in { -1, 1 } do
							local p = rel * Vector3.new(h.X * sx, h.Y * sy, h.Z * sz)
							lo = lo:Min(p)
							hi = hi:Max(p)
						end
					end
				end
			end
		end
		if lo.X > hi.X then continue end
		local shift = Vector3.new((lo.X + hi.X) * 0.5, 0, (lo.Z + hi.Z) * 0.5)
		local size = Vector3.new(hi.X - lo.X, foot.Size.Y, hi.Z - lo.Z)
		if foot:GetAttribute(HIDDEN_ATTRIBUTE) ~= true then
			foot:SetAttribute(GROUND_SIZE_ATTRIBUTE, size)
			foot:SetAttribute(GROUND_CENTER_ATTRIBUTE, shift)
			continue
		end
		local back = CFrame.new(-shift)
		local originalSize = foot:FindFirstChild("OriginalSize")
		local scale = if originalSize and originalSize:IsA("Vector3Value") then foot.Size / originalSize.Value else Vector3.one
		for _, d in model:GetDescendants() do
			if d:IsA("JointInstance") then
				if d.Part0 == foot then d.C0 = back * d.C0 end
				if d.Part1 == foot then d.C1 = back * d.C1 end
			elseif d:IsA("WeldConstraint") and (d.Part0 == foot or d.Part1 == foot) then
				error("CharacterFactory: a WeldConstraint on " .. name .. " cannot follow its sole proxy")
			end
		end
		for _, a in foot:GetChildren() do
			if a:IsA("Attachment") then
				a.CFrame = back * a.CFrame
				local originalPosition = a:FindFirstChild("OriginalPosition")
				if originalPosition and originalPosition:IsA("Vector3Value") then originalPosition.Value = a.Position / scale end
			end
		end
		if originalSize and originalSize:IsA("Vector3Value") then originalSize.Value = size / scale end
		foot:SetAttribute(BARE_FOOT_SIZE_ATTRIBUTE, foot.Size)
		foot:SetAttribute(SOLE_PROXY_ATTRIBUTE, true)
		foot.CFrame = foot.CFrame * CFrame.new(shift)
		foot.Size = size
	end
end

function Factory.build(spec: Spec): Model
	local model = Players:CreateHumanoidModelFromDescription(Factory.describe(spec), Enum.HumanoidRigType.R15, Enum.AssetTypeVerification.Always)
	model.Name = spec.id
	for _, name in R15_PARTS do
		local part = model:FindFirstChild(name)
		assert(part and part:IsA("BasePart"), "CharacterFactory: avatar rig is missing " .. name)
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	assert(humanoid, "CharacterFactory: avatar rig has no Humanoid")
	humanoid:BuildRigFromAttachments()
	ensureR15Motors(model)
	humanoid.EvaluateStateMachine = false
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.NameDisplayDistance = 0
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		animator:Destroy()
	end
	for _, d in model:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Anchored = false
			d.Massless = true
		end
	end
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	root.Anchored = true
	root.Transparency = 1
	model.PrimaryPart = root
	model.Parent = buildTempFolder()
	local measuredRootHeight = measureRootHeight(model, root)
	model:PivotTo(CFrame.new(0, measuredRootHeight, 0))
	local rootHeight = measuredRootHeight
	model.Parent = nil
	-- Nothing yields between parenting and here, so concurrent builds never lose the shared measuring folder.
	local temp = Workspace:FindFirstChild("_FightingLabCharacterBuildTemp")
	if temp and #temp:GetChildren() == 0 then temp:Destroy() end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
		end
	end
	local skippedGear = applyExtras(model, spec)
	fitSoleProxies(model)
	model:SetAttribute(DRESSED_ATTRIBUTE, extrasSignature(spec))
	-- Catalog gear that could not be loaded (e.g. a shoe) is just as much a broken outfit as a missing accessory.
	local missing = Factory.missingAccessories(model, spec)
	for _, id in skippedGear do table.insert(missing, id) end
	if #missing > 0 then
		warn(string.format("CharacterFactory: %s is missing authored accessories %s", spec.id, table.concat(missing, ", ")))
	end
	model:SetAttribute("MissingAccessories", table.concat(missing, ","))
	model:SetAttribute("DisplayName", spec.displayName)
	model:SetAttribute("Tagline", spec.tagline)
	model:SetAttribute("Style", spec.style)
	model:SetAttribute("PrimaryColor", rgb(spec.primaryColor, "primaryColor"))
	model:SetAttribute("AccentColor", rgb(spec.accentColor, "accentColor"))
	model:SetAttribute("RootHeight", rootHeight)
	model:SetAttribute("Original", true)
	model:SetAttribute("AvatarBuilt", true)
	local sources = {}
	for _, s in spec.sourceAssets or {} do
		table.insert(sources, string.format("%s %d (%s by %s)", s.kind, s.id, s.name, s.creator))
	end
	model:SetAttribute("SourceAssets", table.concat(sources, "; "))
	return model
end

return Factory


