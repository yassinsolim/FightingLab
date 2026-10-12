--!strict
-- Fighter look contracts: rig validity, heroic proportions (6.8-7.6 heads tall), head accessories seated on the heads,
-- every authored item applied and textured, fitted fightwear (no ballooning garments), welded extras, originality
-- blocklist, exact credits, and Factory.dressCharacter idempotency on a live-style (unanchored) Humanoid character.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local IDS = { "Kael", "Sierra", "Goran", "Lumi", "Rhys", "Nia" }
local MOTOR_NAMES = {
	Root = true, Waist = true, Neck = true,
	LeftShoulder = true, LeftElbow = true, LeftWrist = true,
	RightShoulder = true, RightElbow = true, RightWrist = true,
	LeftHip = true, LeftKnee = true, LeftAnkle = true,
	RightHip = true, RightKnee = true, RightAnkle = true,
}
-- Every fighter wears at least this many PBR garments; every single worn item must be textured.
local MIN_PBR_GARMENTS = 2
-- Fitted fightwear: layered garments that dress the legs must stay inside this envelope (mesh size on the standard
-- mannequin, studs). Fitted joggers/trunks measure 1.33-1.66 wide and 0.78-0.82 deep; the OV5 wide pants that
-- ballooned in kicks measured 2.52 x 1.21 (cargo) and 2.76 x 1.01 (silk). Shoes taller than SHOE_TUCK_HEIGHT must
-- layer over long pants (higher Order) so cuffs tuck in instead of flaring over the shoe.
local LEG_GARMENT_TYPES = { [Enum.AccessoryType.Pants] = true, [Enum.AccessoryType.Shorts] = true, [Enum.AccessoryType.DressSkirt] = true }
local MAX_LEG_GARMENT_WIDTH = 1.9
local MAX_LEG_GARMENT_DEPTH = 0.95
local SHOE_TUCK_HEIGHT = 0.9
-- One-piece outfits whose mesh also spans the sleeves are checked by eye in wide poses instead (runtime high kick,
-- splits, lunge and crouch shots in OV6\handoff\characters-shots).
local FIT_REVIEWED_ONE_PIECE: { [number]: string } = {
	[16362208023] = "karate gi (jacket + trousers in one layered item)",
}
-- Heroic but believable proportions (measured on the neutral template): realistic 3D-fighter casts stand about 7 heads
-- tall; below 6.8 the head reads as a Roblox avatar on the fight camera, above 7.6 the fighter turns pin-headed/lanky.
local MIN_HEADS_TALL = 6.8
local MAX_HEADS_TALL = 7.6
-- Head accessories (hair, beard) must stay seated after head scaling: their boxes overlap the head box (tolerance in
-- studs) and their centres stay within this many head heights of the head centre.
local HEAD_ACCESSORY_TOLERANCE = 0.05
local HEAD_ACCESSORY_MAX_OFFSET = 0.75
local ROOT_HEIGHT_MIN, ROOT_HEIGHT_MAX = 2, 4.2
-- Assets rejected for logos/text, franchise likeness, costume evocation or ballooning fit; they must never come back.
local BLOCKED: { [number]: string } = {
	[113345926237908] = "compression shirt with chest text",
	[93835319830333] = "sport bra with slogan text",
	[139722674995694] = "kimono with organisation kanji patch",
	[123212969953667] = "torn sleeveless blue gi (evokes a famous fighting-game hero)",
	[140832380856737] = "LUIS Model Man bundle (named game-character likeness)",
	[132568091497519] = "LUIS Model Man head (named game-character likeness)",
	[18456467839] = "Olympic-branded singlet",
	[102403760062527] = "towel with league logo",
	[123583733994002] = "film-character karate headband",
	[186213746067607] = "film-iconic yellow track shoes",
	[123021097004692] = "game-character hair",
	[17420088448] = "anime-character hair",
	[16792685352] = "anime-character hand wrap",
	[94623263727735] = "wide cargo pants that balloon in kicks (OV5 Lumi)",
	[81035324145114] = "wide glossy silk pants that balloon in kicks (OV5 Nia)",
	[115805128224417] = "Muay Thai trunks with printed script text",
	[93692605769537] = "Muay Thai trunks with printed script text",
	[14056493513] = "three-stripe track pants (brand look)",
	[10216549713] = "cosmetics-brand hair",
	[134932291441380] = "anime-character wrist wraps",
}
local BLOCKED_WORDS = { "tekken", "gojo", "naruto", "olympic", "ufc", "nike", "adidas", "jordan", "kung fu panda", "karate kid", "kyokushin", "luis", "wwe", "cena", "baki", "nars", "street fighter", "mortal kombat" }

local function waitForTemplates(): Instance
	local lab = ReplicatedStorage:WaitForChild("FightingLab")
	local ready = lab:WaitForChild("TemplatesReady", 10)
	local deadline = os.clock() + 10
	while ready and ready:IsA("BoolValue") and not ready.Value and os.clock() < deadline do task.wait(0.1) end
	return lab:WaitForChild("Characters")
end

local function countMotors(model: Model): number
	local count = 0
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") and MOTOR_NAMES[d.Name] then count += 1 end
	end
	return count
end

local function appliedAccessories(model: Model): ({ [number]: { Accessory } }, boolean)
	local map: { [number]: { Accessory } } = {}
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local description = humanoid and humanoid:FindFirstChildOfClass("HumanoidDescription")
	local resolved = false
	if description then
		for _, child in description:GetChildren() do
			if child:IsA("AccessoryDescription") then
				local ok, inst = pcall(function() return child:GetAppliedInstance() end)
				if ok and inst and inst:IsA("Accessory") then
					resolved = true
					local list = map[child.AssetId] or {}
					table.insert(list, inst)
					map[child.AssetId] = list
				end
			end
		end
	end
	return map, resolved
end

local function isTextured(accessory: Accessory): (boolean, boolean)
	local handle = accessory:FindFirstChild("Handle")
	if not handle then return false, false end
	local pbr = handle:FindFirstChildOfClass("SurfaceAppearance") ~= nil
	local textured = pbr or (handle:IsA("MeshPart") and handle.TextureID ~= "")
	return textured, pbr
end

local function extraIsTextured(part: BasePart): boolean
	if part:FindFirstChildOfClass("SurfaceAppearance") then return true end
	if part:IsA("MeshPart") and part.TextureID ~= "" then return true end
	local mesh = part:FindFirstChildOfClass("SpecialMesh")
	return mesh ~= nil and mesh.TextureId ~= ""
end

local function usedAssetIds(spec: any): { [number]: boolean }
	local used: { [number]: boolean } = {}
	for _, id in spec.bodyParts or {} do used[id] = true end
	for _, acc in spec.accessories or {} do used[acc.AssetId] = true end
	for _, g in spec.gear or {} do if g.assetId then used[g.assetId] = true end end
	if spec.mood and spec.mood ~= 0 then used[spec.mood] = true end
	return used
end

local function lowestFootY(model: Model): number
	local lowest = math.huge
	for _, name in { "LeftFoot", "RightFoot" } do
		local foot = model:FindFirstChild(name) :: BasePart
		local cf, size = foot.CFrame, foot.Size
		for _, sx in { -0.5, 0.5 } do
			for _, sy in { -0.5, 0.5 } do
				for _, sz in { -0.5, 0.5 } do
					lowest = math.min(lowest, (cf * Vector3.new(size.X * sx, size.Y * sy, size.Z * sz)).Y)
				end
			end
		end
	end
	return lowest
end

-- Neutral-pose silhouette numbers from the rig joints: stature (crown to sole), heads tall, shoulder joint span and
-- leg length (hip joint height) / stature. Templates live outside Workspace where parts keep stale build-time CFrames,
-- so the rig is measured on a temporary Workspace clone (Motor6Ds solve the neutral pose on parenting).
local function proportions(template: Model): { stature: number, heads: number, shoulder: number, leg: number, hip: number }
	local model = template:Clone()
	model.Parent = Workspace
	model:PivotTo(CFrame.new(0, 800 + ((model:GetAttribute("RootHeight") :: number?) or 3), 0))
	local function part(name: string): BasePart return model:FindFirstChild(name) :: BasePart end
	local function joint(partName: string, attachmentName: string): Vector3
		return (part(partName):FindFirstChild(attachmentName) :: Attachment).WorldPosition
	end
	local head = part("Head")
	local sole = lowestFootY(model)
	local stature = head.Position.Y + head.Size.Y * 0.5 - sole
	local shoulder = (joint("LeftUpperArm", "LeftShoulderRigAttachment") - joint("RightUpperArm", "RightShoulderRigAttachment")).Magnitude
	local hipY = joint("LeftUpperLeg", "LeftHipRigAttachment").Y
	model:Destroy()
	return { stature = stature, heads = stature / head.Size.Y, shoulder = shoulder, leg = (hipY - sole) / stature, hip = hipY - sole }
end

-- Accessories attached to the Head on a temporary Workspace clone (neutral pose): does each box touch the head box, and
-- how far (in head heights) is its centre from the head centre? Catches hair/beards left floating after head scaling.
-- Accessories attach through an AccessoryRigidConstraint (Handle attachment -> Head attachment) on current engines, or
-- an AccessoryWeld on older ones; the Humanoid creates either once the rig is in Workspace.
local function attachedToHead(handle: BasePart, head: BasePart): boolean
	for _, joint in handle:GetDescendants() do
		if joint:IsA("RigidConstraint") then
			local a0, a1 = joint.Attachment0, joint.Attachment1
			if (a0 and a0.Parent == head) or (a1 and a1.Parent == head) then return true end
		elseif joint:IsA("JointInstance") then
			if joint.Part0 == head or joint.Part1 == head then return true end
		end
	end
	return false
end

local function headAccessories(template: Model): { { name: string, overlaps: boolean, offset: number } }
	local model = template:Clone()
	model.Parent = Workspace
	model:PivotTo(CFrame.new(0, 800 + ((model:GetAttribute("RootHeight") :: number?) or 3), 0))
	local head = model:FindFirstChild("Head") :: BasePart
	local half = head.Size * 0.5
	local tol = HEAD_ACCESSORY_TOLERANCE
	local out = {}
	for _, acc in model:GetChildren() do
		local handle = if acc:IsA("Accessory") then acc:FindFirstChild("Handle") :: BasePart? else nil
		if handle and attachedToHead(handle, head) then
			local lo = Vector3.new(math.huge, math.huge, math.huge)
			local hi = -lo
			for _, sx in { -0.5, 0.5 } do
				for _, sy in { -0.5, 0.5 } do
					for _, sz in { -0.5, 0.5 } do
						local p = head.CFrame:PointToObjectSpace(handle.CFrame:PointToWorldSpace(handle.Size * Vector3.new(sx, sy, sz)))
						lo = Vector3.new(math.min(lo.X, p.X), math.min(lo.Y, p.Y), math.min(lo.Z, p.Z))
						hi = Vector3.new(math.max(hi.X, p.X), math.max(hi.Y, p.Y), math.max(hi.Z, p.Z))
					end
				end
			end
			local overlaps = hi.X >= -half.X - tol and lo.X <= half.X + tol and hi.Y >= -half.Y - tol and lo.Y <= half.Y + tol
				and hi.Z >= -half.Z - tol and lo.Z <= half.Z + tol
			local offset = head.CFrame:PointToObjectSpace(handle.Position).Magnitude / head.Size.Y
			table.insert(out, { name = acc.Name, overlaps = overlaps, offset = offset })
		end
	end
	model:Destroy()
	return out
end

return function(t)
	local Specs = require(ServerStorage.FightingLab.CharacterSpecs) :: any
	local Factory = require(ServerStorage.FightingLab.CharacterFactory) :: any

	t.test("fighter templates are valid R15 rigs with expressive heads", function()
		local chars = waitForTemplates()
		for _, id in IDS do
			local spec = Specs.specs[id]
			local model = chars:FindFirstChild(id)
			t.expect.truthy(model and model:IsA("Model"), id .. " template exists")
			local rootHeight = (model :: Model):GetAttribute("RootHeight")
			t.expect.truthy(typeof(rootHeight) == "number" and rootHeight >= ROOT_HEIGHT_MIN and rootHeight <= ROOT_HEIGHT_MAX, id .. " RootHeight in [2, 4.2]")
			t.expect.equal(countMotors(model :: Model), 15, id .. " has R15 Motor6Ds")
			for _, side in { "Left", "Right" } do
				local hand = (model :: Model):FindFirstChild(side .. "Hand", true)
				t.expect.truthy(hand and hand:IsA("BasePart"), id .. " " .. side .. "Hand exists")
				t.expect.equal((hand :: BasePart).Transparency, if spec.hideHands then 1 else 0, id .. " " .. side .. "Hand visibility follows hideHands")
				if not spec.fists then
					t.expect.equal((model :: Model):FindFirstChild(side .. "Fist", true), nil, id .. " has no generated fist on " .. side)
				end
			end
			local head = (model :: Model):FindFirstChild("Head", true)
			t.expect.truthy(head and head:FindFirstChildOfClass("FaceControls") ~= nil, id .. " head has FaceControls")
			t.expect.equal((model :: Model):GetAttribute("MissingAccessories") or "", "", id .. " build applied every authored accessory")
		end
	end)

	t.test("silhouettes are heroic but believable and read as different fighters", function()
		local chars = waitForTemplates()
		local p: { [string]: any } = {}
		for _, id in IDS do
			local model = chars:FindFirstChild(id) :: Model
			p[id] = proportions(model)
			t.expect.truthy(p[id].heads >= MIN_HEADS_TALL, string.format("%s is %.2f heads tall (min %.1f, no Roblox-sized heads)", id, p[id].heads, MIN_HEADS_TALL))
			t.expect.truthy(p[id].heads <= MAX_HEADS_TALL, string.format("%s is %.2f heads tall (max %.1f, no pin heads)", id, p[id].heads, MAX_HEADS_TALL))
			t.expect.truthy(p[id].leg >= 0.45 and p[id].leg <= 0.62, string.format("%s leg/stature %.3f is human", id, p[id].leg))
		end
		for _, id in IDS do
			if id ~= "Goran" then
				t.expect.truthy(p.Goran.stature > p[id].stature, "Goran (heavyweight) is taller than " .. id)
				t.expect.truthy(p.Goran.shoulder > p[id].shoulder * 1.2, "Goran (heavyweight) is clearly broader than " .. id)
			end
			if id ~= "Nia" then
				t.expect.truthy(p.Nia.stature < p[id].stature, "Nia (compact) is shorter than " .. id)
			end
			if id ~= "Lumi" then
				-- Smaller heads lengthen everyone's legs relative to stature, so Lumi's long-limbed read is checked as the
				-- longest legs in the cast (hip height) with a leg/stature ratio at the top of the cast.
				t.expect.truthy(p.Lumi.hip >= p[id].hip, string.format("Lumi (long-limbed) has longer legs than %s (hip height %.2f vs %.2f)", id, p.Lumi.hip, p[id].hip))
				t.expect.truthy(p.Lumi.leg >= p[id].leg - 0.005, string.format("Lumi's legs are as long for her height as %s's (%.3f vs %.3f)", id, p.Lumi.leg, p[id].leg))
				t.expect.truthy(p.Lumi.shoulder <= p[id].shoulder * 1.05, string.format("Lumi (light) is no broader than %s (%.2f vs %.2f)", id, p.Lumi.shoulder, p[id].shoulder))
			end
		end
	end)

	t.test("head accessories stay seated on the scaled heads", function()
		-- The check itself tells a seated item from a floating one (synthetic head + hair cap, welded).
		local function fakeHead(handleY: number): { { name: string, overlaps: boolean, offset: number } }
			local fake = Instance.new("Model")
			local head = Instance.new("Part")
			head.Name, head.Size, head.Anchored, head.CFrame = "Head", Vector3.new(1, 1, 1), true, CFrame.new()
			head.Parent = fake
			local acc = Instance.new("Accessory")
			acc.Name = "FakeHair"
			acc.Parent = fake
			local handle = Instance.new("Part")
			handle.Name, handle.Size, handle.Anchored, handle.CFrame = "Handle", Vector3.new(1.1, 0.5, 1.1), true, CFrame.new(0, handleY, 0)
			handle.Parent = acc
			local weld = Instance.new("Weld")
			weld.Part0, weld.Part1, weld.C0 = head, handle, CFrame.new(0, handleY, 0)
			weld.Parent = handle
			local report = headAccessories(fake)
			fake:Destroy()
			return report
		end
		local seated, floating = fakeHead(0.6), fakeHead(2.2)
		t.expect.truthy(#seated == 1 and seated[1].overlaps and seated[1].offset <= HEAD_ACCESSORY_MAX_OFFSET, "a hair cap on the crown counts as seated")
		t.expect.truthy(#floating == 1 and not floating[1].overlaps and floating[1].offset > HEAD_ACCESSORY_MAX_OFFSET, "hair floating above the head is caught")

		local chars = waitForTemplates()
		for _, id in IDS do
			local spec = Specs.specs[id]
			local report = headAccessories(chars:FindFirstChild(id) :: Model)
			local authored = 0
			for _, acc in spec.accessories do
				if acc.AccessoryType == "Hair" or acc.AccessoryType == "Face" or acc.AccessoryType == "Hat" then authored += 1 end
			end
			t.expect.truthy(#report >= authored, string.format("%s has its %d hair/face/hat items on the head (found %d)", id, authored, #report))
			for _, r in report do
				t.expect.truthy(r.overlaps, string.format("%s %s sits on the head (no floating)", id, r.name))
				t.expect.truthy(r.offset <= HEAD_ACCESSORY_MAX_OFFSET, string.format("%s %s centre is %.2f head heights from the head centre (max %.2f)", id, r.name, r.offset, HEAD_ACCESSORY_MAX_OFFSET))
			end
		end
	end)

	t.test("every authored item is applied and textured, nothing glossy-bare or procedural", function()
		local chars = waitForTemplates()
		for _, id in IDS do
			local spec = Specs.specs[id]
			local model = chars:FindFirstChild(id) :: Model
			local map, resolved = appliedAccessories(model)
			local accessories: { Accessory } = {}
			for _, d in model:GetChildren() do if d:IsA("Accessory") then table.insert(accessories, d) end end
			t.expect.truthy(#accessories >= #spec.accessories, id .. " has all " .. #spec.accessories .. " authored accessories (found " .. #accessories .. ")")
			if resolved then
				for _, acc in spec.accessories do
					t.expect.truthy(map[acc.AssetId] ~= nil, id .. " accessory " .. acc.AssetId .. " was applied")
				end
			end
			local pbrGarments = 0
			for _, accessory in accessories do
				local isTex, isPbr = isTextured(accessory)
				t.expect.truthy(isTex, id .. " accessory " .. accessory.Name .. " is textured")
				if isPbr and accessory.AccessoryType ~= Enum.AccessoryType.Hair then pbrGarments += 1 end
			end
			t.expect.truthy(pbrGarments >= MIN_PBR_GARMENTS, string.format("%s wears %d PBR garments (min %d)", id, pbrGarments, MIN_PBR_GARMENTS))
			for _, g in spec.gear or {} do
				t.expect.truthy(type(g.assetId) == "number" and g.band == nil, id .. " gear " .. tostring(g.name) .. " is a textured catalog asset, not a procedural band")
			end
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") and d:GetAttribute("FightingLabExtra") == true then
					t.expect.truthy(extraIsTextured(d), id .. " extra " .. d.Name .. " is textured")
				end
			end
			-- Authored tints must land on the garment's SurfaceAppearance.
			if resolved then
				for _, acc in spec.accessories do
					if acc.Tint then
						local tint = Color3.fromRGB(acc.Tint[1], acc.Tint[2], acc.Tint[3])
						local seen = 0
						for _, inst in map[acc.AssetId] or {} do
							for _, d in inst:GetDescendants() do
								if d:IsA("SurfaceAppearance") then
									seen += 1
									t.expect.near(d.Color.R, tint.R, 0.01, id .. " tint R on " .. acc.AssetId)
									t.expect.near(d.Color.G, tint.G, 0.01, id .. " tint G on " .. acc.AssetId)
									t.expect.near(d.Color.B, tint.B, 0.01, id .. " tint B on " .. acc.AssetId)
								end
							end
						end
						t.expect.truthy(seen > 0, id .. " tinted accessory " .. acc.AssetId .. " has a SurfaceAppearance")
					end
				end
			end
		end
	end)

	t.test("fightwear is fitted: no ballooning leg garments, cuffs tucked into tall shoes", function()
		local chars = waitForTemplates()
		for _, id in IDS do
			local spec = Specs.specs[id]
			local model = chars:FindFirstChild(id) :: Model
			local map = appliedAccessories(model)
			local pantsOrder: number? = nil
			local tallShoeOrder: number? = nil
			for _, acc in spec.accessories do
				for _, inst in map[acc.AssetId] or {} do
					local handle = inst:FindFirstChild("Handle")
					local wrap = handle and handle:FindFirstChildOfClass("WrapLayer")
					if handle and handle:IsA("MeshPart") and wrap then
						local size = handle.MeshSize
						if LEG_GARMENT_TYPES[inst.AccessoryType] and not FIT_REVIEWED_ONE_PIECE[acc.AssetId] then
							t.expect.truthy(size.X <= MAX_LEG_GARMENT_WIDTH and size.Z <= MAX_LEG_GARMENT_DEPTH, string.format("%s leg garment %d is fitted (%.2f x %.2f, max %.2f x %.2f)", id, acc.AssetId, size.X, size.Z, MAX_LEG_GARMENT_WIDTH, MAX_LEG_GARMENT_DEPTH))
						end
						if inst.AccessoryType == Enum.AccessoryType.Pants then
							pantsOrder = math.max(pantsOrder or -math.huge, wrap.Order)
						elseif (inst.AccessoryType == Enum.AccessoryType.LeftShoe or inst.AccessoryType == Enum.AccessoryType.RightShoe) and size.Y >= SHOE_TUCK_HEIGHT then
							tallShoeOrder = math.min(tallShoeOrder or math.huge, wrap.Order)
						end
					end
				end
			end
			if pantsOrder and tallShoeOrder then
				t.expect.truthy(tallShoeOrder > pantsOrder, string.format("%s tall shoes (Order %d) layer over the pants (Order %d)", id, tallShoeOrder, pantsOrder))
			end
		end
	end)

	t.test("gear extras are welded, massless and never collide", function()
		local chars = waitForTemplates()
		for _, id in IDS do
			local spec = Specs.specs[id]
			local model = chars:FindFirstChild(id) :: Model
			local extras = 0
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") and d:GetAttribute("FightingLabExtra") == true then
					extras += 1
					local weld = d:FindFirstChildOfClass("Weld")
					t.expect.truthy(weld and weld.Part1 == d and weld.Part0 and weld.Part0:IsDescendantOf(model), id .. " extra " .. d.Name .. " is welded to the rig")
					t.expect.truthy(d.Massless and not d.Anchored and not d.CanCollide and not d.CanQuery and not d.CanTouch, id .. " extra " .. d.Name .. " is massless/non-colliding")
				end
			end
			t.expect.equal(extras, #(spec.gear or {}) + (if spec.fists then 2 else 0), id .. " extras match the spec")
		end
	end)

	t.test("specs avoid blocked assets and credit exactly the assets used", function()
		for _, id in IDS do
			local spec = Specs.specs[id]
			local used = usedAssetIds(spec)
			for assetId in used do
				t.expect.equal(BLOCKED[assetId], nil, id .. " uses blocked asset " .. assetId)
			end
			local credited: { [number]: boolean } = {}
			for _, s in spec.sourceAssets or {} do
				t.expect.truthy(type(s.name) == "string" and s.name ~= "" and type(s.creator) == "string" and s.creator ~= "" and type(s.kind) == "string" and s.kind ~= "", id .. " credit entry " .. tostring(s.id) .. " is complete")
				t.expect.equal(BLOCKED[s.id], nil, id .. " credits blocked asset " .. tostring(s.id))
				local lowered = string.lower(s.name)
				for _, word in BLOCKED_WORDS do
					t.expect.falsy(string.find(lowered, word, 1, true), id .. " credit '" .. s.name .. "' contains blocked word '" .. word .. "'")
				end
				if not string.find(string.lower(s.kind), "bundle", 1, true) then
					t.expect.truthy(used[s.id], id .. " credits " .. s.id .. " (" .. s.name .. ") which is not used")
					credited[s.id] = true
				end
			end
			for assetId in used do
				t.expect.truthy(credited[assetId], id .. " uses asset " .. assetId .. " without a credit entry")
			end
			t.expect.truthy(type(spec.look) == "string" and #spec.look > 40, id .. " has a look description")
		end
	end)

	t.test("dressCharacter dresses a live-style character idempotently", function()
		local spec = Specs.specs.Goran
		local other = Specs.specs.Kael
		t.expect.truthy(#(spec.gear or {}) > 0, "the idempotency fixture fighter wears welded gear")
		local character = Players:CreateHumanoidModelFromDescription(Factory.describe(spec), Enum.HumanoidRigType.R15)
		local folder = Instance.new("Folder")
		folder.Name = "_CharacterLookTest"
		folder.Parent = Workspace
		character.Parent = folder
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
		root.Anchored = true -- keeps the test rig in place; every other part (and all gear) stays unanchored
		character:PivotTo(CFrame.new(0, 500, 0))
		local function extras(): { BasePart }
			local list = {}
			for _, d in character:GetDescendants() do
				if d:IsA("BasePart") and d:GetAttribute("FightingLabExtra") == true then table.insert(list, d) end
			end
			return list
		end
		local ok, err = pcall(function()
			Factory.dressCharacter(character, spec)
			local first = extras()
			t.expect.equal(#first, #spec.gear, "Goran gear added once")
			local signature = character:GetAttribute("FightingLabDressed")
			t.expect.truthy(typeof(signature) == "string" and signature ~= "", "dressed signature recorded")
			Factory.dressCharacter(character, spec)
			local second = extras()
			t.expect.equal(#second, #first, "second call adds nothing")
			t.expect.truthy(table.find(second, first[1]) ~= nil, "second call keeps the same gear instances")
			for _, part in second do
				t.expect.falsy(part.Anchored, part.Name .. " unanchored")
				local weld = part:FindFirstChildOfClass("Weld")
				t.expect.truthy(weld and weld.Part0 and weld.Part0:IsDescendantOf(character), part.Name .. " welded to the live rig")
			end
			-- Re-dressing for another fighter swaps the extras and the hand visibility.
			Factory.dressCharacter(character, other)
			t.expect.equal(#extras(), #(other.gear or {}), "re-dress removes the previous fighter's gear")
			t.expect.equal((character:FindFirstChild("LeftHand") :: BasePart).Transparency, if other.hideHands then 1 else 0, "re-dress applies hideHands")
			Factory.dressCharacter(character, spec)
			t.expect.equal(#extras(), #spec.gear, "dressing back restores the gear")
			t.expect.equal((character:FindFirstChild("LeftHand") :: BasePart).Transparency, if spec.hideHands then 1 else 0, "dressing back restores hands")
			t.expect.throws(function() Factory.dressCharacter(Instance.new("Model"), spec) end, "a model without a Humanoid is rejected")
		end)
		folder:Destroy()
		if not ok then error(err, 0) end
	end)

	t.test("missingAccessories reports authored items the catalog could not apply", function()
		local chars = waitForTemplates()
		local model = chars:FindFirstChild("Lumi") :: Model
		t.expect.equal(#Factory.missingAccessories(model, Specs.specs.Lumi), 0, "Lumi template applied everything")
		local fake = table.clone(Specs.specs.Lumi)
		fake.accessories = table.clone(fake.accessories)
		table.insert(fake.accessories, { AssetId = 1, AccessoryType = "Hat" })
		local missing = Factory.missingAccessories(model, fake)
		t.expect.equal(#missing, 1, "an accessory that is not on the rig is reported")
		t.expect.equal(missing[1], 1, "the missing asset id is returned")
	end)

	t.test("template rebuild stays within the build budget", function()
		local chars = waitForTemplates()
		local seconds = chars:GetAttribute("TemplateBuildSeconds")
		if typeof(seconds) == "number" then
			-- Target is <= 2 s with a warm asset cache (measured 0.6-1.7 s). Build time also depends on machine load and
			-- asset downloads (3-4 s was measured with several Studios open), so only a pathological build fails the suite.
			if seconds > 2 then warn(string.format("CharacterLook_Test: templates rebuilt in %.2f s (target 2 s)", seconds)) end
			t.expect.truthy(seconds <= 10, string.format("templates rebuilt in %.2f s", seconds))
		end
	end)
end
