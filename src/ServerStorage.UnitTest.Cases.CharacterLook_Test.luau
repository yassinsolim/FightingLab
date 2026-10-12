--!strict
-- Fighter look contracts: rig validity, heroic proportions (6.8-7.6 heads tall), head accessories seated on the heads,
-- hair that covers the whole scalp, shoes sized like real shoes as worn that rest on the floor through knockdowns and
-- getups, every authored item applied and textured, fitted fightwear (no ballooning garments), welded extras,
-- originality blocklist, exact credits, and Factory.dressCharacter idempotency on a live-style (unanchored) Humanoid
-- character.
local AssetService = game:GetService("AssetService")
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
-- Scalp coverage (round 3). Seen from behind at the lobby camera, Kael's cornrows stopped at the crown and Rhys's
-- undercut left the back of his head bare, so both read as bald. Rays from behind, the three-quarter-back angle, the
-- sides, the top and the front hairline toward the cranium centre (head frame, 12% of the head height above its
-- centre) must hit hair before head skin. Head and hair are probed through copies of their render meshes with precise
-- collision, so a hair item only counts where it really has geometry. Probes: { azimuth (0 = straight behind, +90 =
-- the fighter's left), elevation above the horizontal, region }. A shaved head is the one exception and must carry no
-- hair at all, so it reads as a clean shave and never as a partial cover with gaps.
local HAIR_PROBES: { { any } } = {}
for _, az in { -45, -30, -15, 0, 15, 30, 45 } do
	for _, el in { -10, 0, 10, 20, 30, 40 } do table.insert(HAIR_PROBES, { az, el, "back" }) end
end
for _, az in { -60, 60 } do
	for _, el in { 0, 15, 30 } do table.insert(HAIR_PROBES, { az, el, "three-quarter back" }) end
end
for _, az in { -90, 90 } do
	for _, el in { 40, 55 } do table.insert(HAIR_PROBES, { az, el, "side" }) end
end
for _, az in { 0, 90, 180, -90 } do
	for _, el in { 65, 80 } do table.insert(HAIR_PROBES, { az, el, "top" }) end
end
table.insert(HAIR_PROBES, { 0, 90, "top" })
table.insert(HAIR_PROBES, { 180, 55, "front hairline" })
local HAIR_MIN_COVERAGE = 0.95 -- a ray may slip through a parting between cornrows
local HAIR_CRANIUM_UP = 0.12
local CLEAN_SHAVEN: { [string]: boolean } = { Goran = true }
-- Shoes (round 3): sized like real shoes as worn. Length 0.15-0.17 x stature, width at most about 1.2 x the bare foot
-- and never wider than the lower leg it sits on, low shoes no higher than the ankle bone, high-tops/boots at most about
-- 0.12 x stature, and the sole on the sole of the foot the ground solver plants. Shoes are rigid catalog meshes (gear
-- role "shoe", seat "sole") so the server measures them exactly. Layered shoes wrap the body's foot cage on the client
-- and rendered 1.5-3.0x the bare foot width on these realistic bodies, so a layered shoe is bounded by its measured
-- render (chroma silhouettes in the characters lab, studs, on the fighter that wore it); an unmeasured one fails.
local SHOE_LENGTH_MIN, SHOE_LENGTH_MAX = 0.15, 0.17
local SHOE_WIDTH_FOOT_MAX = 1.25
local SHOE_HIGH_MAX = 0.125
local SHOE_ANKLE_TOLERANCE = 0.02
local SHOE_SOLE_TOLERANCE = 0.03
-- Shoes on the floor in motion (round 3): the ground solver (MotionPlayer) keeps the foot part's box on the floor, and
-- a real-size shoe is longer than the small bare foot inside it, so its toe or heel sank whenever the foot pitched
-- (knockdowns, getups, rolls: Lumi 0.13, Kael 0.06 studs). Where the bare foot is hidden, CharacterFactory makes the
-- foot part the shoe's ground box (sole proxy), so the shoe may dip at most SHOE_GROUND_TOLERANCE below the box the
-- solver rests on the floor. A visible foot under a low shoe keeps its bare box (its ankle shows above the collar) and
-- publishes FightingLabShoeGroundSize / FightingLabShoeGroundCenter instead; MotionPlayer rests that shoe box on the
-- floor, so the same tolerance applies.
local SHOE_GROUND_TOLERANCE = 0.03
local SHOE_GROUND_VISIBLE_FOOT = SHOE_GROUND_TOLERANCE
local SHOE_GROUND_SLOT = 61
local SHOE_GROUND_FLOOR_Y = 140
local LAYERED_SHOE_RENDERS: { [number]: { length: number, width: number, height: number, sink: number } } = {
	[128212268343103] = { length = 1.62, width = 0.77, height = 1.24, sink = 0.13 }, -- Kael OV6 street high-tops, left
	[110054253690142] = { length = 1.62, width = 0.86, height = 1.26, sink = 0.17 }, -- right
	[140700617127197] = { length = 1.64, width = 0.71, height = 1.04, sink = 0.16 }, -- Goran OV6 combat boots, left
	[100014109264125] = { length = 1.62, width = 0.71, height = 0.99, sink = 0.16 }, -- right
	[106421807303280] = { length = 1.29, width = 0.58, height = 1.31, sink = 0.26 }, -- Lumi OV6 tech sneakers, left
	[77675773538059] = { length = 1.34, width = 0.67, height = 1.33, sink = 0.26 }, -- right
	[120192598736981] = { length = 0.75, width = 0.36, height = 0.53, sink = 0.06 }, -- Nia OV6 slip-ons, left
	[78935764733147] = { length = 0.73, width = 0.35, height = 0.50, sink = 0.04 }, -- right
}
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
	[95546237277345] = "red/black boots described as a film character's costume boots (round 3 shoe search)",
	[107036470464445] = "red/black boots described as a film character's costume boots (round 3 shoe search)",
	[52911219773530] = "bundle of the film-character costume boots",
	[120888448669923] = "skate high-tops with a sneaker brand's side stripe and heel tab",
	[77928379545153] = "skate high-tops with a sneaker brand's side stripe and heel tab",
	[87587200450608] = "bundle of the brand-look skate high-tops",
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

-- Shoes as worn, per foot: rigid shoe gear measured exactly in the foot's frame from its weld (pose-independent),
-- layered shoe accessories looked up in LAYERED_SHOE_RENDERS. Heights are above the sole of the foot.
type ShoeBox = { name: string, layered: boolean, measured: boolean, length: number, width: number, height: number, top: number, sole: number, inside: boolean }
local function shoesOn(model: Model, spec: any): { [string]: { foot: BasePart, bare: Vector3, ankle: number, lowerWidth: number, shoes: { ShoeBox } } }
	local out = {}
	for _, side in { "Left", "Right" } do
		local foot = model:FindFirstChild(side .. "Foot") :: BasePart
		local lower = model:FindFirstChild(side .. "LowerLeg") :: BasePart
		local ankle = foot:FindFirstChild(side .. "AnkleRigAttachment") :: Attachment
		local half = foot.Size * 0.5
		-- a sole proxy (hidden foot under its shoe) keeps the bare foot box in an attribute
		local bareAttr = foot:GetAttribute("FightingLabBareFootSize")
		local bare = if typeof(bareAttr) == "Vector3" then bareAttr else foot.Size
		local entry = { foot = foot, bare = bare, ankle = half.Y + ankle.Position.Y, lowerWidth = lower.Size.X, shoes = {} :: { ShoeBox } }
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("FightingLabRole") == "shoe" then
				local weld = d:FindFirstChildOfClass("Weld")
				if weld and weld.Part0 == foot and weld.Part1 == d then
					local lo = Vector3.new(math.huge, math.huge, math.huge)
					local hi = -lo
					for _, sx in { -0.5, 0.5 } do
						for _, sy in { -0.5, 0.5 } do
							for _, sz in { -0.5, 0.5 } do
								local p = weld.C0 * (d.Size * Vector3.new(sx, sy, sz))
								lo, hi = lo:Min(p), hi:Max(p)
							end
						end
					end
					-- a visible foot must stay inside its shoe (no toes or heel poking out); a hidden one may not
					local inside = foot.Transparency >= 1 or (lo.X <= -half.X + 0.01 and hi.X >= half.X - 0.01 and lo.Z <= -half.Z + 0.01 and hi.Z >= half.Z - 0.01)
					table.insert(entry.shoes, { name = d.Name, layered = false, measured = true, length = hi.Z - lo.Z, width = hi.X - lo.X, height = hi.Y - lo.Y, top = hi.Y + half.Y, sole = lo.Y + half.Y, inside = inside })
				end
			end
		end
		for _, acc in spec.accessories or {} do
			if acc.AccessoryType == side .. "Shoe" then
				local r = LAYERED_SHOE_RENDERS[acc.AssetId]
				table.insert(entry.shoes, {
					name = "layered " .. tostring(acc.AssetId), layered = true, measured = r ~= nil,
					length = if r then r.length else 0, width = if r then r.width else 0, height = if r then r.height else 0,
					top = if r then r.height - r.sink else 0, sole = if r then -r.sink else 0, inside = true,
				})
			end
		end
		out[side] = entry
	end
	return out
end

-- Hair probe: precise-collision copies of the head mesh and of every hair/hat mesh on a Workspace clone, then one ray
-- per HAIR_PROBES direction toward the cranium centre. Returns the fraction that hits hair first and the bare probes.
local preciseMeshes: { [string]: MeshPart } = {}
local function preciseCopy(part: BasePart, folder: Instance): BasePart?
	if not part:IsA("MeshPart") then return nil end
	local meshId = (part :: MeshPart).MeshId
	local proto = preciseMeshes[meshId]
	if not proto then
		local ok, made = pcall(function()
			return AssetService:CreateMeshPartAsync(Content.fromUri(meshId), { CollisionFidelity = Enum.CollisionFidelity.PreciseConvexDecomposition })
		end)
		if not ok or not made then return nil end
		proto = made
		preciseMeshes[meshId] = made
	end
	local copy = (proto :: MeshPart):Clone()
	copy.Size = part.Size
	copy.CFrame = part.CFrame
	copy.Anchored = true
	copy.CanCollide = false
	copy.CanTouch = false
	copy.CanQuery = true
	copy.Transparency = 1
	copy.Parent = folder
	return copy
end

local function hairCoverage(template: Model): (number, { string }, number, string?)
	local model = template:Clone()
	model.Parent = Workspace
	model:PivotTo(CFrame.new(0, 800 + ((model:GetAttribute("RootHeight") :: number?) or 3), 40))
	local folder = Instance.new("Folder")
	folder.Name = "_HairProbe"
	folder.Parent = Workspace
	local head = model:FindFirstChild("Head") :: BasePart
	local headCopy = preciseCopy(head, folder)
	local hairCount, problem = 0, nil
	if not headCopy then problem = "could not load the head mesh " .. tostring((head :: any).MeshId) end
	for _, acc in model:GetChildren() do
		local handle = if acc:IsA("Accessory") and (acc.AccessoryType == Enum.AccessoryType.Hair or acc.AccessoryType == Enum.AccessoryType.Hat) then acc:FindFirstChild("Handle") :: BasePart? else nil
		if handle then
			if preciseCopy(handle, folder) then hairCount += 1 else problem = "could not load the hair mesh of " .. acc.Name end
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { folder }
	local cf = head.CFrame
	local centre = cf * Vector3.new(0, head.Size.Y * HAIR_CRANIUM_UP, 0)
	local reach = head.Size.Magnitude * 1.5
	local covered, bare = 0, {}
	for _, probe in HAIR_PROBES do
		local a, e = math.rad(probe[1]), math.rad(probe[2])
		local dir = cf:VectorToWorldSpace(Vector3.new(-math.sin(a) * math.cos(e), math.sin(e), math.cos(a) * math.cos(e)))
		local hit = Workspace:Raycast(centre + dir * reach, -dir * reach, params)
		if hit and hit.Instance ~= headCopy then
			covered += 1
		else
			table.insert(bare, string.format("%s az %d el %d", probe[3], probe[1], probe[2]))
		end
	end
	folder:Destroy()
	model:Destroy()
	return covered / #HAIR_PROBES, bare, hairCount, problem
end

-- Shoes on the floor in motion: surface points of a shoe mesh (a precise-collision copy probed from six directions),
-- in the shoe's own frame.
local function shoeSurface(part: BasePart, folder: Instance): { Vector3 }?
	local copy = preciseCopy(part, folder)
	if not copy then return nil end
	local origin = CFrame.new(0, 900, 300)
	copy.CFrame = origin
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { copy }
	local s, n = copy.Size, 10
	local points = {}
	for axis = 1, 3 do
		for sign = -1, 1, 2 do
			for i = 0, n do
				for j = 0, n do
					local u, v = (i / n - 0.5) * 1.02, (j / n - 0.5) * 1.02
					local start = if axis == 1 then Vector3.new(sign * s.X, u * s.Y, v * s.Z) elseif axis == 2 then Vector3.new(u * s.X, sign * s.Y, v * s.Z) else Vector3.new(u * s.X, v * s.Y, sign * s.Z)
					local dir = if axis == 1 then Vector3.new(-2 * sign * s.X, 0, 0) elseif axis == 2 then Vector3.new(0, -2 * sign * s.Y, 0) else Vector3.new(0, 0, -2 * sign * s.Z)
					local hit = Workspace:Raycast(origin * start, origin:VectorToWorldSpace(dir), params)
					if hit then table.insert(points, origin:PointToObjectSpace(hit.Position)) end
				end
			end
		end
	end
	copy:Destroy()
	return points
end

local function groundView(state: string, extra: { [string]: any }?): { [string]: any }
	local v: { [string]: any } = { pos = Vector3.zero, facing = Vector3.xAxis, state = state, move = nil, moveFrame = 0, walkPhase = 0, stun = 0, crouched = false, moveX = 0 }
	if extra then for k, value in extra do v[k] = value end end
	return v
end

-- KO face up and face down, and falls into each getup (stand up, back roll, side roll), frame by frame.
local function groundSequences(config: any): { { name: string, frames: { { [string]: any } } } }
	local landing = config.LandingFrames or 34
	local getup = config.GetupFrames or 26
	local out = {}
	for _, knockdown in { "FaceUp", "FaceDown" } do
		local ko = {}
		for _ = 1, 60 do table.insert(ko, groundView("KO", { knockdown = knockdown })) end
		table.insert(out, { name = "KO " .. knockdown, frames = ko })
		for _, kind in { "Stand", if knockdown == "FaceUp" then "BackRoll" else "SideRoll" } do
			local list = {}
			for s = landing, 0, -1 do table.insert(list, groundView("Landing", { knockdown = knockdown, stun = s, getupKind = kind })) end
			local total = getup + (if kind ~= "Stand" then 10 else 0)
			for s = total, 0, -1 do table.insert(list, groundView("Getup", { knockdown = knockdown, stun = s, getupKind = kind })) end
			table.insert(out, { name = "fall " .. knockdown .. " into a " .. kind .. " getup", frames = list })
		end
	end
	return out
end

-- Poses a Workspace clone with the real MotionPlayer (as CharacterPresenter does) and returns, per sequence and shoe,
-- how far the shoe's lowest surface point dips below the floor or below the foot box the ground solver rests on it.
type GroundResult = { name: string, side: string, proxy: boolean, worst: number, frame: number }
local function shoeGround(template: Model, id: string, motion: any, config: any): ({ GroundResult }, string?)
	local model = template:Clone()
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = d.Name == "HumanoidRootPart"
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	model.Parent = Workspace
	local folder = Instance.new("Folder")
	folder.Name = "_ShoeGround"
	folder.Parent = Workspace
	local rig = motion.collectRig(model)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	local shoes = {}
	local problem: string? = nil
	for _, side in { "Left", "Right" } do
		local foot = model:FindFirstChild(side .. "Foot") :: BasePart
		for _, d in foot:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("FightingLabRole") == "shoe" then
				local weld = d:FindFirstChildOfClass("Weld")
				local points = shoeSurface(d, folder)
				if points and weld then
					table.insert(shoes, { side = side, foot = side .. "Foot", chain = rig.chains[side .. "Leg"], c0 = weld.C0, points = points, proxy = foot:GetAttribute("FightingLabSoleProxy") == true })
				else
					problem = "could not sample the shoe mesh " .. d.Name
				end
			end
		end
	end
	local floorY = SHOE_GROUND_FLOOR_Y
	local results: { GroundResult } = {}
	for _, seq in groundSequences(config) do
		motion.reset(SHOE_GROUND_SLOT)
		local worst: { [string]: number } = { Left = math.huge, Right = math.huge }
		local at: { [string]: number } = { Left = 0, Right = 0 }
		for i, v in seq.frames do
			v.characterId = id
			v.rootHeight = rig.rootHeight
			v.legLength = rig.legLength
			local pose = motion.sample(config, v, { now = i / 60, dt = 1 / 60, hitstop = 0, phase = "Fight", winner = 0, fighters = { v, { pos = Vector3.new(30, 0, 0), facing = -Vector3.xAxis } } }, SHOE_GROUND_SLOT)
			-- root placed as CharacterPresenter does: facing +X, so the fighter's right is +Z
			local offset = pose.rootOffset :: Vector3
			local center = Vector3.new(offset.Z, floorY + rig.rootHeight + offset.Y, 600 + offset.X)
			root.CFrame = CFrame.lookAt(center, center + Vector3.xAxis)
			motion.apply(rig, pose, floorY)
			if i > 3 then
				for _, s in shoes do
					local tip = rig.tips[s.foot] :: CFrame
					local footLow = (tip * (s.chain.tipBox or CFrame.identity)).Position.Y - motion.extentY(tip, s.chain.tipSize) - floorY
					local cf = tip * s.c0
					local low = math.huge
					for _, p in s.points do
						local y = (cf * p).Y
						if y < low then low = y end
					end
					local dip = low - floorY - math.min(footLow, 0)
					if dip < worst[s.side] then
						worst[s.side] = dip
						at[s.side] = i
					end
				end
			end
		end
		for _, s in shoes do
			table.insert(results, { name = seq.name, side = s.side, proxy = s.proxy, worst = worst[s.side], frame = at[s.side] })
		end
	end
	motion.reset(SHOE_GROUND_SLOT)
	folder:Destroy()
	model:Destroy()
	return results, problem
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

	-- One test per fighter: each loads two or three meshes with precise collision.
	for _, id in IDS do
		if CLEAN_SHAVEN[id] then
			t.test(id .. "'s shaved head reads as a clean shave, not a partial cover", function()
				local chars = waitForTemplates()
				for _, acc in Specs.specs[id].accessories do
					t.expect.truthy(acc.AccessoryType ~= "Hair" and acc.AccessoryType ~= "Hat", string.format("%s is clean-shaven by design and authors no hair/hat (%s)", id, tostring(acc.AssetId)))
				end
				for _, acc in (chars:FindFirstChild(id) :: Model):GetChildren() do
					if acc:IsA("Accessory") then
						t.expect.truthy(acc.AccessoryType ~= Enum.AccessoryType.Hair and acc.AccessoryType ~= Enum.AccessoryType.Hat, id .. " template wears no hair: " .. acc.Name)
					end
				end
			end)
		else
			t.test(id .. "'s hair covers the whole scalp: back, three-quarter back, sides, top and hairline", function()
				local chars = waitForTemplates()
				local coverage, bare, count, problem = hairCoverage(chars:FindFirstChild(id) :: Model)
				t.expect.equal(problem, nil, id .. " hair probe meshes load")
				t.expect.truthy(count > 0, id .. " wears hair")
				t.expect.truthy(coverage >= HAIR_MIN_COVERAGE, string.format("%s scalp coverage %.0f%% (min %.0f%%), bare at: %s", id, coverage * 100, HAIR_MIN_COVERAGE * 100, table.concat(bare, ", ", 1, math.min(#bare, 10))))
			end)
		end
	end

	t.test("shoes are sized like real shoes as worn and their soles sit on the feet", function()
		local chars = waitForTemplates()
		-- Every violation is collected first, so one run reports all fighters and all bounds.
		local problems: { string } = {}
		local function check(ok: boolean, message: string)
			if not ok then table.insert(problems, message) end
		end
		for _, id in IDS do
			local spec = Specs.specs[id]
			local model = chars:FindFirstChild(id) :: Model
			local stature = proportions(model).stature
			local feet = shoesOn(model, spec)
			local count = #feet.Left.shoes + #feet.Right.shoes
			local style = spec.shoeStyle or (if count > 0 then "high" else "barefoot")
			if style == "barefoot" then
				check(count == 0, id .. " is barefoot by design but wears " .. count .. " shoes")
				continue
			end
			check(style == "high" or style == "low", id .. " shoeStyle must be high, low or barefoot (got " .. tostring(style) .. ")")
			for _, side in { "Left", "Right" } do
				local entry = feet[side]
				check(#entry.shoes == 1, string.format("%s wears %d %s shoes (expected 1)", id, #entry.shoes, side))
				for _, s in entry.shoes do
					local label = string.format("%s %s %s", id, side, s.name)
					check(s.measured, label .. " is not measurable (a layered shoe renders on the client only: wear it as rigid shoe gear or add its measured render)")
					if s.measured then
						local length = s.length / stature
						check(length >= SHOE_LENGTH_MIN and length <= SHOE_LENGTH_MAX, string.format("%s is %.3f x stature long (%.2f studs; %.2f-%.2f)", label, length, s.length, SHOE_LENGTH_MIN, SHOE_LENGTH_MAX))
						check(s.width <= entry.bare.X * SHOE_WIDTH_FOOT_MAX, string.format("%s is %.2f x the bare foot wide (%.2f studs; max %.2f)", label, s.width / entry.bare.X, s.width, SHOE_WIDTH_FOOT_MAX))
						check(s.width <= entry.lowerWidth, string.format("%s is wider than the lower leg it sits on (%.2f vs %.2f studs)", label, s.width, entry.lowerWidth))
						if style == "low" then
							check(s.top <= entry.ankle + SHOE_ANKLE_TOLERANCE, string.format("%s low shoe reaches %.2f studs, above the ankle bone at %.2f", label, s.top, entry.ankle))
						else
							check(s.height <= SHOE_HIGH_MAX * stature, string.format("%s high-top is %.3f x stature tall (%.2f studs; max %.3f)", label, s.height / stature, s.height, SHOE_HIGH_MAX))
						end
						check(math.abs(s.sole) <= SHOE_SOLE_TOLERANCE, string.format("%s sole is %.3f studs off the foot's sole (sinks into or floats above the floor)", label, s.sole))
						check(s.inside, label .. " lets the visible bare foot poke out")
					end
				end
			end
		end
		t.expect.equal(#problems, 0, #problems .. " shoe problems:\n  " .. table.concat(problems, "\n  "))
	end)

	for _, id in IDS do
		if (Specs.specs[id].shoeStyle or "barefoot") == "barefoot" then continue end
		t.test(id .. "'s shoes rest on the floor through knockdowns, falls, getups and rolls", function()
			local chars = waitForTemplates()
			local motion = require(ReplicatedStorage.FightingLab.Client.MotionPlayer) :: any
			local config = require(ReplicatedStorage.FightingLab.CombatConfig) :: any
			local model = chars:FindFirstChild(id) :: Model
			for _, side in { "Left", "Right" } do
				local foot = model:FindFirstChild(side .. "Foot") :: BasePart
				if foot.Transparency >= 1 then
					-- the hidden foot is its shoe's ground box, with the bare foot's height (RootHeight and leg length hold)
					local bare = foot:GetAttribute("FightingLabBareFootSize")
					t.expect.truthy(foot:GetAttribute("FightingLabSoleProxy") == true, id .. " " .. side .. " hidden foot is its shoe's ground box")
					t.expect.truthy(typeof(bare) == "Vector3" and math.abs((bare :: Vector3).Y - foot.Size.Y) < 1e-3, id .. " " .. side .. " ground box keeps the bare foot's height")
				else
					t.expect.truthy(typeof(foot:GetAttribute("FightingLabShoeGroundSize")) == "Vector3", id .. " " .. side .. " visible foot publishes its shoe's ground box")
				end
			end
			local results, problem = shoeGround(model, id, motion, config)
			t.expect.equal(problem, nil, id .. " shoe meshes sample")
			t.expect.truthy(#results > 0, id .. " wears measurable shoes")
			for _, r in results do
				local limit = if r.proxy then SHOE_GROUND_TOLERANCE else SHOE_GROUND_VISIBLE_FOOT
				t.expect.truthy(r.worst >= -limit, string.format("%s %s shoe sinks %.3f studs into the floor (below the foot box the solver rests on it) in the %s, frame %d (max %.2f)", id, r.side, -r.worst, r.name, r.frame, limit))
			end
		end)
	end

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
			-- Rigid catalog gear (shoes, belt) counts as a garment too when it carries its PBR SurfaceAppearance.
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") and d:GetAttribute("FightingLabExtra") == true and d:FindFirstChildOfClass("SurfaceAppearance") then pbrGarments += 1 end
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
