--!strict
-- Fighter look contracts: rig validity, real adult proportions (7.0-7.4 heads tall; per fighter shoulder/head, neck,
-- hand and hair-silhouette bounds on the precise meshes; motion-relevant leg and arm lengths held), head accessories
-- seated on the heads, hair that covers the whole scalp, shoes sized like real shoes as worn that rest on the floor
-- through knockdowns and getups, boxing gloves sized like real gloves that never clip into the head or hide the eyes in
-- guard, gear worn close to the body, every authored item applied and textured, fitted fightwear (no ballooning
-- garments), welded extras, originality blocklist, exact credits, and Factory.dressCharacter idempotency (gear and hand
-- scale) on a live-style (unanchored) Humanoid character. Round 6: one signature detail per fighter (worn, unique, tape
-- seated on the glove cuff) and six silhouettes that differ pairwise in feet, hands, legwear or hair.
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
-- Heroic but believable proportions (measured on the neutral template): realistic adult anatomy stands 7.0-7.4 heads
-- tall (head box incl. the dynamic head's neck stub); below 7 the head reads as a Roblox avatar on the fight camera, above
-- 7.4 the fighter turns pin-headed/lanky (round 4 tightened 6.8-7.6 to the real-adult band).
local MIN_HEADS_TALL = 7.0
local MAX_HEADS_TALL = 7.4
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
-- Round 4 (scaling audit): every fighter in real adult proportion. All silhouettes are measured on the neutral template
-- through precise-collision copies of the meshes (front view = X, side view = Z); renders confirmed them within 1-2%.
-- Head width includes the ears (the head reads at its widest). Shoulders = outer shoulder width deltoid to deltoid on the
-- bare body (upper torso + upper arms, widest row from 0.02 x stature above the shoulder joints to 0.07 x stature
-- below). Neck = narrowest front-view width between the head box bottom and the jaw. Hand length = wrist joint to the
-- farthest point of the hand (fingertips; the relaxed curl shortens a box length), hand width = widest across the palm
-- incl. the relaxed thumb. Hair = head + hair silhouette width.
-- Per-fighter bounds: men 2.8-3.3 shoulder widths per head (Goran, the heavyweight, up to 3.6), women 2.4-2.9. Rhys's
-- head read too big next to the other men (the user named it): on main his frame was the narrowest per head of the men
-- (3.18) and he stood 7.08 heads, so he is held at the top of the men's band (>= 3.25) and >= 7.2 heads tall.
-- Sierra's and Nia's necks are the slender necks of their head meshes (0.428 and 0.448 x head width; the narrowest point
-- is on the head mesh, which scales uniformly, so no body or head scale changes the ratio): bounded at 0.42 and 0.44
-- instead of 0.45. Curly hair may reach 1.4 head widths (Lumi).
type R4Bounds = { shoulder: { number }, neck: number, hair: number?, heads: { number }? }
local R4_BOUNDS: { [string]: R4Bounds } = {
	Kael = { shoulder = { 2.8, 3.3 }, neck = 0.5, hair = 1.3 },
	Sierra = { shoulder = { 2.4, 2.9 }, neck = 0.42, hair = 1.3 },
	Goran = { shoulder = { 2.8, 3.6 }, neck = 0.5 },
	Lumi = { shoulder = { 2.4, 2.9 }, neck = 0.45, hair = 1.4 },
	Rhys = { shoulder = { 3.25, 3.3 }, neck = 0.5, hair = 1.3, heads = { 7.2, 7.4 } },
	Nia = { shoulder = { 2.4, 2.9 }, neck = 0.44, hair = 1.3 },
}
local HAND_LENGTH_MIN, HAND_LENGTH_MAX = 0.10, 0.115 -- x stature
local HAND_WIDTH_MAX = 0.055 -- x stature
-- Motion clips are proportional to the legs and the arm IK to the arm segments: round 4 must not move them. Round-3
-- (main) values measured on the templates: RootHeight, hip joint height above the sole, shoulder->elbow->wrist length.
local R4_LIMBS: { [string]: { rootHeight: number, hip: number, armLeft: number, armRight: number } } = {
	Kael = { rootHeight = 4.113, hip = 3.215, armLeft = 1.704, armRight = 1.669 },
	Sierra = { rootHeight = 4.059, hip = 3.161, armLeft = 1.643, armRight = 1.647 },
	Goran = { rootHeight = 4.095, hip = 3.245, armLeft = 1.901, armRight = 1.926 },
	Lumi = { rootHeight = 4.111, hip = 3.292, armLeft = 1.574, armRight = 1.582 },
	Rhys = { rootHeight = 4.100, hip = 3.155, armLeft = 1.697, armRight = 1.677 },
	Nia = { rootHeight = 3.933, hip = 3.073, armLeft = 1.431, armRight = 1.451 },
}
local LEG_TOLERANCE, ARM_TOLERANCE = 0.01, 0.03
-- Boxing gloves (round 4): real gloves are about 0.17 x stature long (cuff to fist end), as wide as the head and two
-- thirds of its depth. Bounds: length <= 0.18 x stature, width (across the knuckles, hand Z) <= 1.1 x head width, depth
-- (palm to back, hand X) <= 0.9 x head depth. A glove is seated on a closed fist: its fist end lies past the knuckles
-- (0.6 hand lengths from the wrist joint) by the padding, 0.65-0.9 hand lengths from the wrist joint (seated on the open
-- fingertips, 1.0+, it reads long and stands above the eyes in guard), and its cuff wraps the wrist at least 0.4 hand
-- lengths up the forearm (hand length = the hand box, wrist joint to fingertips). Gloves are rigid catalog meshes (gear role
-- "glove") so the server measures them exactly; a layered glove wraps the hand cage on the client (Kael's both-gloves
-- item rendered 1.4 x his head wide on his large hands), so it is bounded by its measured render (larger hand of the
-- chroma silhouettes in the hand frame, studs, top/bottom relative to the hand centre) in the fit it was measured in
-- (fighter and body scales { Height, Width, Depth }, no hand scale); an unmeasured one fails.
local GLOVE_LENGTH_MAX, GLOVE_WIDTH_MAX, GLOVE_DEPTH_MAX = 0.18, 1.1, 0.9
local GLOVE_FIST_MIN, GLOVE_FIST_MAX, GLOVE_CUFF_MIN = 0.65, 0.9, 0.4 -- x hand length, from the wrist joint
local LAYERED_GLOVE_RENDERS: { [number]: { fighter: string, scales: { number }, length: number, width: number, depth: number, top: number, bottom: number } } = {
	[101503419947939] = { fighter = "Kael", scales = { 0.93, 0.96, 0.92 }, length = 0.981, width = 0.822, depth = 0.822, top = 0.558, bottom = -0.441 }, -- OV6 orange
	[81319860328594] = { fighter = "Sierra", scales = { 0.9, 0.76, 0.78 }, length = 0.854, width = 0.514, depth = 0.415, top = 0.511, bottom = -0.345 }, -- OV6 brown
}
-- Eyes (fight camera, guard): head-space eye height = FaceCenterAttachment.Y + k x head height, eyes at +-0.18 x head
-- width (located on front renders of each head, round 4).
local EYE_LEVEL: { [string]: number } = { Kael = 0.0, Sierra = -0.018, Goran = 0.136, Lumi = -0.021, Rhys = 0.086, Nia = 0.026 }
local EYE_SPREAD = 0.18
-- The fight camera looks across the fight line, so it sees faces in profile (74-95 degrees off the face in guard). An
-- eye counts where the camera is in front of the profile line (<= 90 degrees off the face) and sees it past the head and
-- hair; from behind the profile line the head itself hides the eyes, gloves or not.
local EYE_VIEW_MAX_ANGLE = 90
local GLOVE_CLIP_SHRINK = 0.92 -- glove copies shrink about their centre: a glove resting on a cheek is contact, not clipping
-- Gear worn on the body (round 4): protrusion past the bare body <= 0.04 x stature; belts at most 0.06 x stature tall.
-- Rigid gear and rigid accessories are measured on the server (precise silhouettes vs the bare body). Layered gear wraps
-- the body on the client: it is bounded by its measured renders (front and side chroma silhouettes vs the precise
-- bare-body silhouette, studs), one per fit it was measured in: fighter, body scales { Height, Width, Depth } and hand
-- scale (nil = none); a fit that was never measured fails.
-- Nia's waist wrap is a draped sash, its band 0.085 x stature tall (13.8 cm on a 1.62 m woman; a real martial-arts sash
-- is 10-15 cm): sash bands are bounded at 0.09 x stature, and a sash is held to the protrusion bound by its band (its
-- tails hang free from the knot, 0.29 studs off the hip).
local GEAR_PROTRUSION_MAX = 0.04
local BELT_HEIGHT_MAX = 0.06
local SASH_HEIGHT_MAX = 0.09
type GearFit = { fighter: string, scales: { number }, hands: { number }?, protrusion: number, band: number? }
local LAYERED_GEAR_RENDERS: { [number]: { GearFit } } = {
	[114155090849709] = { -- OV6 tactical knee pads (round 3; removed in round 4)
		{ fighter = "Goran", scales = { 0.85, 1.12, 1.12 }, protrusion = 0.355 },
	},
	[17697195879] = { -- wrist sweatbands
		{ fighter = "Goran", scales = { 0.85, 1.12, 1.12 }, protrusion = 0.095 },
		{ fighter = "Goran", scales = { 0.85, 0.91, 0.98 }, hands = { 0.88, 1.18, 0.76 }, protrusion = 0.084 },
	},
	[13048594874] = { -- arm sleeves
		{ fighter = "Lumi", scales = { 0.82, 0.74, 0.76 }, protrusion = 0.094 },
		{ fighter = "Lumi", scales = { 0.82, 0.84, 0.76 }, protrusion = 0.094 },
	},
	[131531879662841] = { -- hand wraps
		{ fighter = "Rhys", scales = { 0.95, 0.86, 0.86 }, protrusion = 0.057 },
		{ fighter = "Rhys", scales = { 0.95, 0.865, 0.86 }, hands = { 1.0, 1.0, 0.88 }, protrusion = 0.058 },
	},
	[93954966441244] = { -- waist wrap (sash): band protrusion and band height
		{ fighter = "Nia", scales = { 0.86, 0.89, 0.8 }, hands = { 1.0, 1.13, 1.0 }, protrusion = 0.159, band = 0.465 },
	},
	-- Round 6 (chroma renders vs the precise bare limb, front and side, in OV6\work\r6-characters\data\r6-items.json)
	[11790893653] = { -- Goran's wrist chain (signature): loose links around the left forearm
		{ fighter = "Goran", scales = { 0.85, 0.91, 0.98 }, hands = { 0.88, 1.18, 0.76 }, protrusion = 0.211 },
	},
	[72553576375381] = { -- Lumi's fingerless grip gloves (signature): flush on the hand and wrist
		{ fighter = "Lumi", scales = { 0.82, 0.84, 0.76 }, protrusion = 0.076 },
	},
}
-- Layered gear items, recognised by their credit kind (garments such as tops, gi, shorts and pants are not gear).
local GEAR_KIND_WORDS = { "hand wrap", "waist wrap", "sweatband", "arm sleeve", "knee pad", "bracer", "belt", "sash", "pouch", "chain", "grip glove" }
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

-- Round 4 helpers ------------------------------------------------------------------------------------------------------

-- Silhouette rows { y, lo, hi } of the union of `copies` (precise copies in Workspace) in frame F: per height y (F
-- space) rays along F's X ("x", front view) or Z ("z", side view), every `spacing` studs across the other horizontal
-- axis inside the copies' box.
local function silhouette(copies: { BasePart }, F: CFrame, axis: string, y0: number, y1: number, dy: number, spacing: number): { { number } }
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = copies
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, c in copies do
		for _, sx in { -0.5, 0.5 } do
			for _, sy in { -0.5, 0.5 } do
				for _, sz in { -0.5, 0.5 } do
					local q = F:PointToObjectSpace(c.CFrame * Vector3.new(c.Size.X * sx, c.Size.Y * sy, c.Size.Z * sz))
					lo, hi = lo:Min(q), hi:Max(q)
				end
			end
		end
	end
	local oLo = (if axis == "x" then lo.Z else lo.X) - 0.02
	local oHi = (if axis == "x" then hi.Z else hi.X) + 0.02
	local n = math.max(4, math.ceil((oHi - oLo) / spacing))
	local rows = {}
	local y = y0
	while y <= y1 + 1e-6 do
		local a0, a1 = math.huge, -math.huge
		for i = 0, n do
			local o = oLo + (oHi - oLo) * i / n
			local a = if axis == "x" then F * Vector3.new(-12, y, o) else F * Vector3.new(o, y, -12)
			local b = if axis == "x" then F * Vector3.new(12, y, o) else F * Vector3.new(o, y, 12)
			local h1 = Workspace:Raycast(a, b - a, params)
			if h1 then
				local p = F:PointToObjectSpace(h1.Position)
				a0 = math.min(a0, if axis == "x" then p.X else p.Z)
				local h2 = Workspace:Raycast(b, a - b, params)
				if h2 then
					local q = F:PointToObjectSpace(h2.Position)
					a1 = math.max(a1, if axis == "x" then q.X else q.Z)
				end
			end
		end
		if a0 <= a1 then table.insert(rows, { y, a0, a1 }) end
		y += dy
	end
	return rows
end

local function widest(rows: { { number } }): number
	local w = 0
	for _, r in rows do w = math.max(w, r[3] - r[2]) end
	return w
end

local function mustCopy(part: BasePart, folder: Instance): BasePart
	local copy = preciseCopy(part, folder)
	assert(copy, "could not load the mesh of " .. part:GetFullName())
	return copy :: BasePart
end

local function attachmentWorld(model: Model, partName: string, attachmentName: string): Vector3
	return ((model:FindFirstChild(partName) :: BasePart):FindFirstChild(attachmentName) :: Attachment).WorldPosition
end

-- Round-4 proportions of a template on a Workspace clone in the neutral pose (precise mesh silhouettes, see R4_BOUNDS).
type R4Body = { stature: number, heads: number, rootHeight: number, hip: number, armLeft: number, armRight: number, headWidth: number, headDepth: number, hairWidth: number?, shoulder: number, neck: number, hands: { [string]: { reach: number, width: number, visible: boolean } } }
local function r4Body(template: Model): R4Body
	local model = template:Clone()
	model.Parent = Workspace
	model:PivotTo(CFrame.new(0, 800 + ((model:GetAttribute("RootHeight") :: number?) or 3), -80))
	local folder = Instance.new("Folder")
	folder.Name = "_R4Body"
	folder.Parent = Workspace
	local function part(name: string): BasePart return model:FindFirstChild(name) :: BasePart end
	local head = part("Head")
	local sole = lowestFootY(model)
	local stature = head.Position.Y + head.Size.Y * 0.5 - sole
	local root = part("HumanoidRootPart")
	local F = CFrame.new(root.Position.X, sole, root.Position.Z)
	local hb = head.Position.Y - head.Size.Y * 0.5 - sole
	local ht = head.Position.Y + head.Size.Y * 0.5 - sole
	local headCopy = mustCopy(head, folder)
	local out: any = { stature = stature, heads = stature / head.Size.Y, rootHeight = (template:GetAttribute("RootHeight") :: number?) or 0, hands = {} }
	out.hip = attachmentWorld(model, "LeftUpperLeg", "LeftHipRigAttachment").Y - sole
	for _, side in { "Left", "Right" } do
		local s = attachmentWorld(model, side .. "UpperArm", side .. "ShoulderRigAttachment")
		local e = attachmentWorld(model, side .. "UpperArm", side .. "ElbowRigAttachment")
		local w = attachmentWorld(model, side .. "LowerArm", side .. "WristRigAttachment")
		out["arm" .. side] = (e - s).Magnitude + (w - e).Magnitude
	end
	out.headWidth = widest(silhouette({ headCopy }, F, "x", hb, ht + 0.05, 0.01, 0.015))
	out.headDepth = widest(silhouette({ headCopy }, F, "z", hb, ht + 0.05, 0.01, 0.015))
	task.wait()
	local hairCopies = { headCopy }
	local top, bottom = ht, hb
	for _, acc in model:GetChildren() do
		if acc:IsA("Accessory") and (acc.AccessoryType == Enum.AccessoryType.Hair or acc.AccessoryType == Enum.AccessoryType.Hat) then
			local handle = acc:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") then
				table.insert(hairCopies, mustCopy(handle, folder))
				top = math.max(top, handle.Position.Y + handle.Size.Magnitude * 0.6 - sole)
				bottom = math.min(bottom, handle.Position.Y - handle.Size.Magnitude * 0.6 - sole)
			end
		end
	end
	if #hairCopies > 1 then out.hairWidth = widest(silhouette(hairCopies, F, "x", math.max(bottom, hb - 0.6), top, 0.01, 0.015)) end
	task.wait()
	-- shoulders: the deltoid band from 0.07 x stature below the shoulder joints to 0.02 x stature above them
	local sY = attachmentWorld(model, "LeftUpperArm", "LeftShoulderRigAttachment").Y - sole
	local torso = { mustCopy(part("UpperTorso"), folder), mustCopy(part("LeftUpperArm"), folder), mustCopy(part("RightUpperArm"), folder) }
	local shoulder = 0
	for _, r in silhouette(torso, F, "x", sY - 0.12 * stature, sY + 0.03 * stature, 0.01, 0.015) do
		if r[1] >= sY - 0.07 * stature and r[1] <= sY + 0.02 * stature then shoulder = math.max(shoulder, r[3] - r[2]) end
	end
	out.shoulder = shoulder
	task.wait()
	local neck = math.huge
	for _, r in silhouette({ headCopy, torso[1] }, F, "x", hb - 0.15, hb + head.Size.Y * 0.45, 0.01, 0.015) do neck = math.min(neck, r[3] - r[2]) end
	out.neck = neck
	task.wait()
	-- hands (hand frame, neutral pose: +Y toward the wrist): reach = wrist joint to the farthest surface point, width =
	-- widest across the palm (Z, includes the relaxed thumb)
	for _, side in { "Left", "Right" } do
		local hand = part(side .. "Hand")
		local wrist = (hand:FindFirstChild(side .. "WristRigAttachment") :: Attachment).WorldPosition
		local copy = mustCopy(hand, folder)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { copy }
		local s, n, H = copy.Size, 18, copy.CFrame
		local reach = 0
		for axis = 1, 3 do
			for sign = -1, 1, 2 do
				for i = 0, n do
					for j = 0, n do
						local u, v = (i / n - 0.5) * 1.02, (j / n - 0.5) * 1.02
						local start = if axis == 1 then Vector3.new(sign * s.X, u * s.Y, v * s.Z) elseif axis == 2 then Vector3.new(u * s.X, sign * s.Y, v * s.Z) else Vector3.new(u * s.X, v * s.Y, sign * s.Z)
						local dir = if axis == 1 then Vector3.new(-2 * sign * s.X, 0, 0) elseif axis == 2 then Vector3.new(0, -2 * sign * s.Y, 0) else Vector3.new(0, 0, -2 * sign * s.Z)
						local hit = Workspace:Raycast(H * start, H:VectorToWorldSpace(dir), params)
						if hit then reach = math.max(reach, (hit.Position - wrist).Magnitude) end
					end
				end
			end
		end
		local width = widest(silhouette({ copy }, H, "z", -s.Y * 0.6, s.Y * 0.6, 0.01, 0.01))
		out.hands[side] = { reach = reach, width = width, visible = hand.Transparency < 1 }
		task.wait()
	end
	folder:Destroy()
	model:Destroy()
	return out :: R4Body
end

-- Bare head width (front, ears included) and depth (side) of a model in Workspace, sampled like r4Body.
local function bareHeadSize(model: Model, folder: Instance): (number, number)
	local head = model:FindFirstChild("Head") :: BasePart
	local copy = mustCopy(head, folder)
	local F = CFrame.new(head.Position.X, 0, head.Position.Z)
	local hb = head.Position.Y - head.Size.Y * 0.5
	local ht = head.Position.Y + head.Size.Y * 0.5
	return widest(silhouette({ copy }, F, "x", hb, ht + 0.05, 0.01, 0.015)), widest(silhouette({ copy }, F, "z", hb, ht + 0.05, 0.01, 0.015))
end

local function sameFit(a: { number }?, b: { number }?): boolean
	if a == nil or b == nil then return a == nil and b == nil end
	for i = 1, 3 do
		if math.abs(a[i] - b[i]) > 1e-3 then return false end
	end
	return true
end

-- The measured render of a layered gear item in the fighter's current fit (body scales and hand scale), if any.
local function layeredGearFit(spec: any, assetId: number): GearFit?
	local s = spec.scales or {}
	local scales = { s.Height or 1, s.Width or 1, s.Depth or 1 }
	for _, fit in LAYERED_GEAR_RENDERS[assetId] or {} do
		if fit.fighter == spec.id and sameFit(fit.scales, scales) and sameFit(fit.hands, spec.handScale) then return fit end
	end
	return nil
end

-- Boxing gloves: rigid gear with role "glove", or a layered item credited as a boxing glove (fingerless grip gloves are
-- open-hand gear, measured as gear close to the body instead).
local function wearsGloves(spec: any): boolean
	for _, g in spec.gear or {} do
		if g.role == "glove" then return true end
	end
	local kinds: { [number]: string } = {}
	for _, s in spec.sourceAssets or {} do kinds[s.id] = string.lower(s.kind) end
	for _, acc in spec.accessories or {} do
		if string.find(kinds[acc.AssetId] or "", "boxing glove", 1, true) then return true end
	end
	return false
end

-- Boxing gloves per hand, in the hand frame (Y along the forearm, Z across the knuckles, X palm to back): rigid glove
-- gear measured exactly from its precise mesh surface through its weld (pose-independent); layered boxing gloves (credit
-- kind "boxing glove") looked up in LAYERED_GLOVE_RENDERS.
type GloveBox = { name: string, measured: boolean, rigid: boolean, length: number, width: number, depth: number, top: number, bottom: number, center: Vector3, part: BasePart?, c0: CFrame? }
local function glovesOn(model: Model, spec: any, folder: Instance): { [string]: { GloveBox } }
	local out: { [string]: { GloveBox } } = { Left = {}, Right = {} }
	for _, side in { "Left", "Right" } do
		local hand = model:FindFirstChild(side .. "Hand") :: BasePart
		for _, d in hand:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("FightingLabRole") == "glove" then
				local weld = d:FindFirstChildOfClass("Weld")
				local points = shoeSurface(d, folder)
				if weld and weld.Part0 == hand and points and #points > 0 then
					local rel = weld.C0 * weld.C1:Inverse()
					local lo = Vector3.new(math.huge, math.huge, math.huge)
					local hi = -lo
					for _, p in points do
						local q = rel * p
						lo, hi = lo:Min(q), hi:Max(q)
					end
					table.insert(out[side], { name = d.Name, measured = true, rigid = true, length = hi.Y - lo.Y, width = hi.Z - lo.Z, depth = hi.X - lo.X,
						top = hi.Y, bottom = lo.Y, center = (lo + hi) * 0.5, part = d, c0 = rel })
				else
					table.insert(out[side], { name = d.Name, measured = false, rigid = true, length = 0, width = 0, depth = 0, top = 0, bottom = 0, center = Vector3.zero })
				end
			end
		end
	end
	local kinds: { [number]: string } = {}
	for _, s in spec.sourceAssets or {} do kinds[s.id] = string.lower(s.kind) end
	for _, acc in spec.accessories or {} do
		if string.find(kinds[acc.AssetId] or "", "boxing glove", 1, true) then
			local r = LAYERED_GLOVE_RENDERS[acc.AssetId]
			local s = spec.scales or {}
			local ok = r ~= nil and r.fighter == spec.id and sameFit(r.scales, { s.Height or 1, s.Width or 1, s.Depth or 1 }) and spec.handScale == nil
			for _, side in { "Left", "Right" } do
				table.insert(out[side], { name = "layered " .. tostring(acc.AssetId), measured = ok, rigid = false,
					length = if ok then r.length else 0, width = if ok then r.width else 0, depth = if ok then r.depth else 0,
					top = if ok then r.top else 0, bottom = if ok then r.bottom else 0, center = if ok then Vector3.new(0, (r.top + r.bottom) * 0.5, 0) else Vector3.zero })
			end
		end
	end
	return out
end

-- Rigid gear (welded extras other than shoes and gloves) and rigid accessories other than hair, hats and face items,
-- measured on a Workspace clone in the neutral pose against the bare body around them (the torso and upper legs for
-- torso items, else the limb part they sit on), world axes: the item's silhouette rows per height (front X, side Z),
-- protrusion = how far a row reaches past the body row at the same height, band = the rows at least 70% as wide as the
-- widest (a sash's hanging tails are not its band). `kind` is the item's credit kind (lower case).
type RigidGear = { name: string, kind: string, height: number, protrusion: number, bandProtrusion: number }
local TORSO_PARTS = { UpperTorso = true, LowerTorso = true }
local function rigidGearOn(template: Model, spec: any): { RigidGear }
	local kinds: { [number]: string } = {}
	for _, s in spec.sourceAssets or {} do kinds[s.id] = string.lower(s.kind) end
	local model = template:Clone()
	model.Parent = Workspace
	model:PivotTo(CFrame.new(0, 800 + ((model:GetAttribute("RootHeight") :: number?) or 3), -120))
	local items: { { part: BasePart, target: BasePart, kind: string, name: string } } = {}
	for _, d in model:GetDescendants() do
		if not d:IsA("BasePart") then continue end
		local acc = d:FindFirstAncestorOfClass("Accessory")
		local role = d:GetAttribute("FightingLabRole")
		if acc == nil and d:GetAttribute("FightingLabExtra") == true and role ~= "shoe" and role ~= "glove" then
			local weld = d:FindFirstChildOfClass("Weld")
			local kind = ""
			for _, g in spec.gear or {} do
				if g.assetId and (g.name or ("Gear_" .. tostring(g.assetId))) == d.Name then kind = kinds[g.assetId] or "" end
			end
			if weld and weld.Part0 then table.insert(items, { part = d, target = weld.Part0, kind = kind, name = d.Name }) end
		elseif acc and d.Name == "Handle" and d:FindFirstChildOfClass("WrapLayer") == nil and acc.AccessoryType ~= Enum.AccessoryType.Hair
			and acc.AccessoryType ~= Enum.AccessoryType.Hat and acc.AccessoryType ~= Enum.AccessoryType.Face then
			local target: BasePart? = nil
			for _, a in d:GetChildren() do
				if a:IsA("Attachment") then
					for _, bodyPart in model:GetChildren() do
						if bodyPart:IsA("BasePart") and bodyPart:FindFirstChild(a.Name) then target = bodyPart end
					end
				end
			end
			local kind = ""
			for _, entry in spec.accessories or {} do
				if not entry.IsLayered and entry.AccessoryType == acc.AccessoryType.Name then kind = kinds[entry.AssetId] or "" end
			end
			if target then table.insert(items, { part = d, target = target, kind = kind, name = acc.Name }) end
		end
	end
	local out: { RigidGear } = {}
	if #items == 0 then
		model:Destroy()
		return out
	end
	local folder = Instance.new("Folder")
	folder.Name = "_R4Gear"
	folder.Parent = Workspace
	local bodyCopies: { [string]: BasePart } = {}
	local function bodyFor(target: BasePart): { BasePart }
		local names = if TORSO_PARTS[target.Name] then { "UpperTorso", "LowerTorso", "LeftUpperLeg", "RightUpperLeg" } else { target.Name }
		local list = {}
		for _, n in names do
			bodyCopies[n] = bodyCopies[n] or mustCopy(model:FindFirstChild(n) :: BasePart, folder)
			table.insert(list, bodyCopies[n])
		end
		return list
	end
	for _, item in items do
		local copy = mustCopy(item.part, folder)
		local F = CFrame.new(item.target.Position)
		local lo, hi = math.huge, -math.huge
		for _, sx in { -0.5, 0.5 } do
			for _, sy in { -0.5, 0.5 } do
				for _, sz in { -0.5, 0.5 } do
					local y = F:PointToObjectSpace(copy.CFrame * Vector3.new(copy.Size.X * sx, copy.Size.Y * sy, copy.Size.Z * sz)).Y
					lo, hi = math.min(lo, y), math.max(hi, y)
				end
			end
		end
		local body = bodyFor(item.target)
		local front = silhouette({ copy }, F, "x", lo, hi, 0.02, 0.02)
		local side = silhouette({ copy }, F, "z", lo, hi, 0.02, 0.02)
		local bodyFront = silhouette(body, F, "x", lo, hi, 0.02, 0.02)
		local bodySide = silhouette(body, F, "z", lo, hi, 0.02, 0.02)
		local maxW = widest(front)
		local bandLo, bandHi = math.huge, -math.huge
		for _, r in front do
			if r[3] - r[2] >= 0.7 * maxW then bandLo, bandHi = math.min(bandLo, r[1]), math.max(bandHi, r[1]) end
		end
		local protrusion, bandProtrusion = 0, 0
		for _, pair in { { front, bodyFront }, { side, bodySide } } do
			for _, r in pair[1] do
				for _, b in pair[2] do
					if math.abs(b[1] - r[1]) < 0.005 then
						local d = math.max(r[3] - b[3], b[2] - r[2])
						protrusion = math.max(protrusion, d)
						if r[1] >= bandLo and r[1] <= bandHi then bandProtrusion = math.max(bandProtrusion, d) end
					end
				end
			end
		end
		table.insert(out, { name = item.name, kind = item.kind, height = if bandHi >= bandLo then bandHi - bandLo + 0.02 else 0, protrusion = protrusion, bandProtrusion = bandProtrusion })
		task.wait()
	end
	folder:Destroy()
	model:Destroy()
	return out
end

-- Glove frames for the clipping and eye checks: guard (Idle: the stance cycle), the fighter's punches (1 and 2) up to
-- their first active frame (full extension) and the hit reactions (High/Mid/Low x Light/Heavy) for 14 frames. Every
-- sequence starts from 20 frames of guard.
local GLOVE_WARMUP = 20
local function gloveSequences(id: string): { { name: string, guard: boolean, frames: { { [string]: any } } } }
	local Roster = require(ReplicatedStorage.FightingLab.Roster) :: any
	local out = {}
	local function sequence(name: string, guard: boolean): { { [string]: any } }
		local frames = {}
		for _ = 1, GLOVE_WARMUP do table.insert(frames, groundView("Idle")) end
		table.insert(out, { name = name, guard = guard, frames = frames })
		return frames
	end
	local guard = sequence("guard", true)
	for _ = 1, 70 do table.insert(guard, groundView("Idle")) end
	local jab: string? = nil
	for _, notation in { "1", "2" } do
		for _, m in Roster.get(id).moves do
			if m.notation == notation then
				jab = jab or m.key
				local frames = sequence(m.key .. " at full extension", false)
				for f = 1, m.startup + 1 do table.insert(frames, groundView("Attack", { move = m.key, moveFrame = f })) end
			end
		end
	end
	for _, height in { "High", "Mid", "Low" } do
		for _, tier in { "Light", "Heavy" } do
			local frames = sequence(height .. " " .. tier .. " hit reaction", false)
			local hit = { frame = 900, move = jab or "Jab", height = height, tier = tier, side = 1, kind = "Hit" }
			for f = 1, 14 do table.insert(frames, groundView("Hitstun", { lastHit = hit, stun = 20 - f })) end
		end
	end
	return out
end

-- An eye on the head surface, in head space: FaceCenterAttachment height + EYE_LEVEL x head height, EYE_SPREAD x head
-- width off the middle, on the face (head space -Z).
local function eyeLocal(head: BasePart, id: string, sign: number, headCopy: BasePart): Vector3?
	local fc = head:FindFirstChild("FaceCenterAttachment") :: Attachment?
	if not fc then return nil end
	local y = fc.Position.Y + (EYE_LEVEL[id] or 0) * head.Size.Y
	local x = sign * EYE_SPREAD * head.Size.X
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { headCopy }
	local from = headCopy.CFrame * Vector3.new(x, y, -head.Size.Z * 2)
	local hit = Workspace:Raycast(from, headCopy.CFrame:VectorToWorldSpace(Vector3.new(0, 0, head.Size.Z * 3)), params)
	if not hit then return nil end
	return headCopy.CFrame:PointToObjectSpace(hit.Position)
end

-- Poses a Workspace clone with the real MotionPlayer (as CharacterPresenter does) through gloveSequences and checks
-- every frame after the warm-up: glove copies shrunk to GLOVE_CLIP_SHRINK about their centre must not overlap the head
-- copy, and in guard no glove may hide an eye the fight camera would otherwise see (CameraDirector's fight plan at
-- neutral spacing, from the player's side of the fight line and from the opponent's side).
type GloveFrameResult = { clips: { string }, covered: { string }, eyeChecks: number, frames: number }
local function gloveFrames(template: Model, spec: any, motion: any, config: any): (GloveFrameResult?, string?)
	local camera = require(ReplicatedStorage.FightingLab.Client.CameraDirector) :: any
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
	folder.Name = "_R4Gloves"
	folder.Parent = Workspace
	local function finish(result: GloveFrameResult?, problem: string?): (GloveFrameResult?, string?)
		motion.reset(SHOE_GROUND_SLOT)
		folder:Destroy()
		model:Destroy()
		return result, problem
	end
	local rig = motion.collectRig(model)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	local head = model:FindFirstChild("Head") :: BasePart
	local headCopy = mustCopy(head, folder)
	headCopy.CFrame = head.CFrame
	local eyes: { Vector3 } = {}
	for _, sign in { -1, 1 } do
		local e = eyeLocal(head, spec.id, sign, headCopy)
		if not e then return finish(nil, spec.id .. " eye surface not found on the head mesh") end
		table.insert(eyes, e)
	end
	local hairs: { { copy: BasePart, rel: CFrame } } = {}
	for _, acc in model:GetChildren() do
		if acc:IsA("Accessory") and (acc.AccessoryType == Enum.AccessoryType.Hair or acc.AccessoryType == Enum.AccessoryType.Hat) then
			local handle = acc:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") then table.insert(hairs, { copy = mustCopy(handle, folder), rel = head.CFrame:ToObjectSpace(handle.CFrame) }) end
		end
	end
	type Held = { side: string, copy: BasePart, rel: CFrame }
	local held: { Held } = {}
	local gloves = glovesOn(model, spec, folder)
	for _, side in { "Left", "Right" } do
		for _, g in gloves[side] do
			if not g.measured then return finish(nil, spec.id .. " " .. side .. " glove " .. g.name .. " is not measurable") end
			if g.rigid and g.part then
				local copy = mustCopy(g.part, folder)
				copy.Size *= GLOVE_CLIP_SHRINK
				table.insert(held, { side = side, copy = copy, rel = g.c0 :: CFrame })
			else
				-- a layered glove as it renders: its measured box around the hand
				local box = Instance.new("Part")
				box.Anchored, box.CanCollide, box.CanTouch, box.CanQuery, box.Transparency = true, false, false, true, 1
				box.Size = Vector3.new(g.depth, g.length, g.width) * GLOVE_CLIP_SHRINK
				box.Parent = folder
				table.insert(held, { side = side, copy = box, rel = CFrame.new(g.center) })
			end
		end
	end
	if #held == 0 then return finish(nil, spec.id .. " wears no gloves") end
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = { headCopy }
	local gloveSet: { [Instance]: boolean } = {}
	local headAndHair: { Instance } = { headCopy }
	for _, h in held do gloveSet[h.copy] = true end
	for _, h in hairs do table.insert(headAndHair, h.copy) end
	local rayHead = RaycastParams.new()
	rayHead.FilterType = Enum.RaycastFilterType.Include
	rayHead.FilterDescendantsInstances = headAndHair
	local rayAll = RaycastParams.new()
	rayAll.FilterType = Enum.RaycastFilterType.Include
	rayAll.FilterDescendantsInstances = { folder }
	local floorY = SHOE_GROUND_FLOOR_Y
	local base = Vector3.new(0, floorY, 600)
	local sep = 3.6
	-- the fighter stands at the arena origin facing +X, the opponent at +sep
	local plan = camera._plan(Vector3.zero, Vector3.new(sep, 0, 0), "Fight", 0, 1 / 60, Vector3.new(0, 0, -1), 0, false, nil)
	local p, f = plan.position :: Vector3, plan.focus :: Vector3
	local cameras = { near = base + p, far = base + Vector3.new(p.X, p.Y, f.Z - (p.Z - f.Z)) }
	local result: GloveFrameResult = { clips = {}, covered = {}, eyeChecks = 0, frames = 0 }
	for _, seq in gloveSequences(spec.id) do
		motion.reset(SHOE_GROUND_SLOT)
		for i, v in seq.frames do
			v.characterId = spec.id
			v.rootHeight = rig.rootHeight
			v.legLength = rig.legLength
			local pose = motion.sample(config, v, { now = i / 60, dt = 1 / 60, hitstop = 0, phase = "Fight", winner = 0, fighters = { v, { pos = Vector3.new(sep, 0, 0), facing = -Vector3.xAxis } } }, SHOE_GROUND_SLOT)
			-- root placed as CharacterPresenter does: facing +X, so the fighter's right is +Z
			local offset = pose.rootOffset :: Vector3
			local center = Vector3.new(offset.Z, floorY + rig.rootHeight + offset.Y, 600 + offset.X)
			root.CFrame = CFrame.lookAt(center, center + Vector3.xAxis)
			motion.apply(rig, pose, floorY)
			if i <= GLOVE_WARMUP and not seq.guard then continue end
			result.frames += 1
			local headWorld = motion.partWorld(rig, "Head") :: CFrame
			headCopy.CFrame = headWorld
			for _, h in hairs do h.copy.CFrame = headWorld * h.rel end
			for _, h in held do
				h.copy.CFrame = (motion.partWorld(rig, h.side .. "Hand") :: CFrame) * h.rel
				if #Workspace:GetPartsInPart(h.copy, overlap) > 0 and #result.clips < 8 then
					table.insert(result.clips, string.format("%s glove inside the head in the %s (frame %d)", h.side, seq.name, i))
				end
			end
			if seq.guard and i % 2 == 0 then
				for side, cam in cameras do
					for k, e in eyes do
						local target = headWorld * e
						local dir = (target - cam) * 1.05
						-- the eye counts when the camera sees the face within EYE_VIEW_MAX_ANGLE and the eye past the head and
						-- hair (a face turned away from the camera shows no eyes, gloves or not)
						local angle = math.deg(math.acos(math.clamp(headWorld.LookVector:Dot((cam - target).Unit), -1, 1)))
						local seen = if angle <= EYE_VIEW_MAX_ANGLE then Workspace:Raycast(cam, dir, rayHead) else nil
						if seen and (seen.Position - target).Magnitude < 0.05 then
							result.eyeChecks += 1
							local first = Workspace:Raycast(cam, dir, rayAll)
							if first and gloveSet[first.Instance] and #result.covered < 8 then
								table.insert(result.covered, string.format("%s eye hidden by a glove in guard (%s fight camera, frame %d, %.0f deg off the face)", if k == 1 then "left" else "right", side, i, angle))
							end
						end
					end
				end
			end
		end
		task.wait()
	end
	return finish(result, nil)
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

	-- Round 4: real adult proportion, measured on the precise meshes (one test per fighter: each loads ~8 meshes).
	for _, id in IDS do
		t.test(id .. " is in real adult proportion: heads tall, shoulders, neck, hands and hair", function()
			local chars = waitForTemplates()
			local b = r4Body(chars:FindFirstChild(id) :: Model)
			local bounds = R4_BOUNDS[id]
			local problems: { string } = {}
			local function check(ok: boolean, message: string)
				if not ok then table.insert(problems, message) end
			end
			local heads = bounds.heads or { MIN_HEADS_TALL, MAX_HEADS_TALL }
			check(b.heads >= heads[1] and b.heads <= heads[2], string.format("%s is %.2f heads tall (%.1f-%.1f)", id, b.heads, heads[1], heads[2]))
			local shoulder = b.shoulder / b.headWidth
			check(shoulder >= bounds.shoulder[1] and shoulder <= bounds.shoulder[2], string.format("%s shoulders are %.2f head widths (%.2f studs over a %.3f head; %.2f-%.2f)", id, shoulder, b.shoulder, b.headWidth, bounds.shoulder[1], bounds.shoulder[2]))
			check(b.neck >= bounds.neck * b.headWidth, string.format("%s neck is %.3f head widths (%.3f studs; min %.2f)", id, b.neck / b.headWidth, b.neck, bounds.neck))
			if b.hairWidth then
				local hair = b.hairWidth / b.headWidth
				check(bounds.hair ~= nil and hair <= bounds.hair, string.format("%s hair silhouette is %.2f head widths (%.3f studs; max %s)", id, hair, b.hairWidth, tostring(bounds.hair)))
			end
			for _, side in { "Left", "Right" } do
				local h = b.hands[side]
				if h.visible then
					local reach, width = h.reach / b.stature, h.width / b.stature
					check(reach >= HAND_LENGTH_MIN and reach <= HAND_LENGTH_MAX, string.format("%s %s hand is %.3f x stature long (%.3f studs wrist to fingertips; %.3f-%.3f)", id, side, reach, h.reach, HAND_LENGTH_MIN, HAND_LENGTH_MAX))
					check(width <= HAND_WIDTH_MAX, string.format("%s %s hand is %.3f x stature wide (%.3f studs; max %.3f)", id, side, width, h.width, HAND_WIDTH_MAX))
				end
			end
			t.expect.equal(#problems, 0, #problems .. " proportion problems:\n  " .. table.concat(problems, "\n  "))
		end, { timeout = 12 }) -- loads ~8 precise meshes over the network: its time follows the network, not the game
	end

	t.test("motion-relevant lengths hold: RootHeight and legs within 1%, arms within 3% of round 3", function()
		local chars = waitForTemplates()
		local problems: { string } = {}
		for _, id in IDS do
			local model = (chars:FindFirstChild(id) :: Model):Clone()
			model.Parent = Workspace
			model:PivotTo(CFrame.new(0, 800 + ((model:GetAttribute("RootHeight") :: number?) or 3), 120))
			local ref = R4_LIMBS[id]
			local sole = lowestFootY(model)
			local now: { [string]: number } = {
				rootHeight = (model:GetAttribute("RootHeight") :: number?) or 0,
				hip = attachmentWorld(model, "LeftUpperLeg", "LeftHipRigAttachment").Y - sole,
			}
			for _, side in { "Left", "Right" } do
				local s = attachmentWorld(model, side .. "UpperArm", side .. "ShoulderRigAttachment")
				local e = attachmentWorld(model, side .. "UpperArm", side .. "ElbowRigAttachment")
				local w = attachmentWorld(model, side .. "LowerArm", side .. "WristRigAttachment")
				now["arm" .. side] = (e - s).Magnitude + (w - e).Magnitude
			end
			model:Destroy()
			for _, key in { "rootHeight", "hip", "armLeft", "armRight" } do
				local tolerance = if key == "armLeft" or key == "armRight" then ARM_TOLERANCE else LEG_TOLERANCE
				local change = now[key] / ref[key] - 1
				if math.abs(change) > tolerance then
					table.insert(problems, string.format("%s %s %.3f -> %.3f (%+.1f%%, max %.0f%%)", id, key, ref[key], now[key], change * 100, tolerance * 100))
				end
			end
		end
		t.expect.equal(#problems, 0, #problems .. " motion-relevant lengths moved:\n  " .. table.concat(problems, "\n  "))
	end)

	for _, id in IDS do
		if not wearsGloves(Specs.specs[id]) then continue end
		t.test(id .. "'s boxing gloves are sized like real gloves and cover the hands", function()
			local chars = waitForTemplates()
			local spec = Specs.specs[id]
			local model = (chars:FindFirstChild(id) :: Model):Clone()
			model.Parent = Workspace
			model:PivotTo(CFrame.new(0, 800 + ((model:GetAttribute("RootHeight") :: number?) or 3), -160))
			local folder = Instance.new("Folder")
			folder.Name = "_R4GloveSize"
			folder.Parent = Workspace
			local head = model:FindFirstChild("Head") :: BasePart
			local stature = head.Position.Y + head.Size.Y * 0.5 - lowestFootY(model)
			local headWidth, headDepth = bareHeadSize(model, folder)
			local gloves = glovesOn(model, spec, folder)
			local problems: { string } = {}
			local function check(ok: boolean, message: string)
				if not ok then table.insert(problems, message) end
			end
			for _, side in { "Left", "Right" } do
				local hand = model:FindFirstChild(side .. "Hand") :: BasePart
				local wrist = (hand:FindFirstChild(side .. "WristRigAttachment") :: Attachment).Position
				check(#gloves[side] == 1, string.format("%s wears %d %s gloves (expected 1)", id, #gloves[side], side))
				for _, g in gloves[side] do
					local label = string.format("%s %s %s", id, side, g.name)
					check(g.measured, label .. " is not measurable (a layered glove renders on the client only: wear it as rigid glove gear or add its measured render)")
					if not g.measured then continue end
					check(g.length <= GLOVE_LENGTH_MAX * stature, string.format("%s is %.3f x stature long, cuff to fist end (%.2f studs; max %.2f)", label, g.length / stature, g.length, GLOVE_LENGTH_MAX))
					check(g.width <= GLOVE_WIDTH_MAX * headWidth, string.format("%s is %.2f head widths wide (%.2f studs over a %.3f head; max %.2f)", label, g.width / headWidth, g.width, headWidth, GLOVE_WIDTH_MAX))
					check(g.depth <= GLOVE_DEPTH_MAX * headDepth, string.format("%s is %.2f head depths deep (%.2f studs over a %.3f head; max %.2f)", label, g.depth / headDepth, g.depth, headDepth, GLOVE_DEPTH_MAX))
					local fist, cuff = (wrist.Y - g.bottom) / hand.Size.Y, (g.top - wrist.Y) / hand.Size.Y
					check(fist >= GLOVE_FIST_MIN and fist <= GLOVE_FIST_MAX, string.format("%s fist end is %.2f hand lengths from the wrist joint (%.2f-%.2f: past the knuckles by the padding)", label, fist, GLOVE_FIST_MIN, GLOVE_FIST_MAX))
					check(cuff >= GLOVE_CUFF_MIN, string.format("%s cuff reaches %.2f hand lengths up the forearm (min %.2f)", label, cuff, GLOVE_CUFF_MIN))
					if g.rigid then
						check(hand.Transparency >= 1, label .. " is a closed glove but the open bare hand stays visible inside it")
					end
				end
			end
			folder:Destroy()
			model:Destroy()
			t.expect.equal(#problems, 0, #problems .. " glove problems:\n  " .. table.concat(problems, "\n  "))
		end)

		t.test(id .. "'s gloves never clip into the head and leave the eyes visible in guard", function()
			local chars = waitForTemplates()
			local motion = require(ReplicatedStorage.FightingLab.Client.MotionPlayer) :: any
			local config = require(ReplicatedStorage.FightingLab.CombatConfig) :: any
			local result, problem = gloveFrames(chars:FindFirstChild(id) :: Model, Specs.specs[id], motion, config)
			t.expect.equal(problem, nil, id .. " gloves and head sample")
			local r = result :: GloveFrameResult
			t.expect.truthy(r.frames > 0, id .. " glove frames were posed")
			t.expect.truthy(r.eyeChecks > 0, id .. "'s eyes are never visible from the fight camera in guard (nothing to check)")
			t.expect.equal(#r.clips, 0, id .. " gloves clip into the head:\n  " .. table.concat(r.clips, "\n  "))
			t.expect.equal(#r.covered, 0, id .. " gloves hide the eyes in guard:\n  " .. table.concat(r.covered, "\n  "))
		end)
	end

	for _, id in IDS do
		t.test(id .. "'s gear sits close to the body: flat belts and sashes, flush pads, sleeves and wraps", function()
			local chars = waitForTemplates()
			local spec = Specs.specs[id]
			local model = chars:FindFirstChild(id) :: Model
			local stature = proportions(model).stature
			local kinds: { [number]: string } = {}
			for _, s in spec.sourceAssets or {} do kinds[s.id] = string.lower(s.kind) end
			local problems: { string } = {}
			local function check(ok: boolean, message: string)
				if not ok then table.insert(problems, message) end
			end
			local function heightLimit(kind: string): number?
				if string.find(kind, "belt", 1, true) then return BELT_HEIGHT_MAX end
				if string.find(kind, "sash", 1, true) or string.find(kind, "waist wrap", 1, true) then return SASH_HEIGHT_MAX end
				return nil
			end
			for _, acc in spec.accessories do
				local kind = kinds[acc.AssetId] or ""
				local isGear = false
				for _, word in GEAR_KIND_WORDS do
					if string.find(kind, word, 1, true) then isGear = true end
				end
				if not (acc.IsLayered and isGear) then continue end
				local label = string.format("%s %s (%s)", id, kind, tostring(acc.AssetId))
				local fit = layeredGearFit(spec, acc.AssetId)
				check(fit ~= nil, label .. " is not measured in this fit (layered gear renders on the client only: add its measured render for these scales)")
				if not fit then continue end
				check(fit.protrusion <= GEAR_PROTRUSION_MAX * stature, string.format("%s stands %.3f x stature off the body (%.3f studs; max %.2f)", label, fit.protrusion / stature, fit.protrusion, GEAR_PROTRUSION_MAX))
				local limit = heightLimit(kind)
				if limit then
					check(fit.band ~= nil and fit.band <= limit * stature, string.format("%s band is %.3f x stature tall (%s studs; max %.2f)", label, (fit.band or 0) / stature, tostring(fit.band), limit))
				end
			end
			for _, g in rigidGearOn(model, spec) do
				local label = string.format("%s %s (%s)", id, g.name, g.kind)
				local limit = heightLimit(g.kind)
				local protrusion = if limit then g.bandProtrusion else g.protrusion
				check(protrusion <= GEAR_PROTRUSION_MAX * stature, string.format("%s stands %.3f x stature off the body (%.3f studs; max %.2f)", label, protrusion / stature, protrusion, GEAR_PROTRUSION_MAX))
				if limit then
					check(g.height <= limit * stature, string.format("%s band is %.3f x stature tall (%.3f studs; max %.2f)", label, g.height / stature, g.height, limit))
				end
			end
			t.expect.equal(#problems, 0, #problems .. " gear problems:\n  " .. table.concat(problems, "\n  "))
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

	-- Round 6: one memorable detail per fighter, authored in the spec (label + the items that carry it) and worn on the
	-- template; no two fighters share a signature item or label. Tape on a glove must be seated on the glove's cuff.
	t.test("each fighter wears one signature detail of its own", function()
		local chars = waitForTemplates()
		local problems: { string } = {}
		local function check(ok: boolean, message: string)
			if not ok then table.insert(problems, message) end
		end
		local owner: { [number]: string } = {}
		local labels: { [string]: string } = {}
		for _, id in IDS do
			local spec = Specs.specs[id]
			local sig = spec.signature
			check(type(sig) == "table" and type(sig.label) == "string" and #sig.label >= 12 and type(sig.assetIds) == "table" and #sig.assetIds > 0,
				id .. " authors a signature { label, assetIds }")
			if type(sig) ~= "table" or type(sig.assetIds) ~= "table" then continue end
			local model = chars:FindFirstChild(id) :: Model
			check(model:GetAttribute("Signature") == sig.label, id .. " template publishes its Signature attribute")
			check(labels[sig.label] == nil, string.format("%s's signature '%s' is already %s's", id, sig.label, tostring(labels[sig.label])))
			labels[sig.label] = id
			local used = usedAssetIds(spec)
			local map = appliedAccessories(model)
			for _, assetId in sig.assetIds do
				check(used[assetId] == true, string.format("%s signature item %d is part of the outfit", id, assetId))
				check(owner[assetId] == nil, string.format("%s signature item %d is already %s's", id, assetId, tostring(owner[assetId])))
				owner[assetId] = id
				local worn = map[assetId] ~= nil
				for _, g in spec.gear or {} do
					if g.assetId == assetId then
						local part = model:FindFirstChild(g.name, true)
						worn = worn or (part ~= nil and part:GetAttribute("FightingLabExtra") == true)
					end
				end
				check(worn, string.format("%s signature item %d is worn on the template", id, assetId))
			end
			-- tape wrapped over a glove: inside the glove's cuff (hand frame), never floating past it
			for _, g in spec.gear or {} do
				if g.role ~= "tape" then continue end
				local clone = model:Clone()
				clone.Parent = Workspace
				clone:PivotTo(CFrame.new(0, 800 + ((clone:GetAttribute("RootHeight") :: number?) or 3), 220))
				local folder = Instance.new("Folder")
				folder.Name = "_R6Tape"
				folder.Parent = Workspace
				local gloves = glovesOn(clone, spec, folder)
				local tape = clone:FindFirstChild(g.name, true) :: BasePart?
				local weld = tape and tape:FindFirstChildOfClass("Weld")
				local side = if string.find(g.target, "Left", 1, true) then "Left" else "Right"
				local glove = gloves[side][1]
				if tape and weld and glove and glove.measured then
					local c, h = weld.C0.Position, tape.Size * 0.5
					check(c.Y - h.Y >= glove.bottom and c.Y + h.Y <= glove.top, string.format("%s %s sits on the glove (%.3f..%.3f inside %.3f..%.3f along the forearm)", id, g.name, c.Y - h.Y, c.Y + h.Y, glove.bottom, glove.top))
					check(math.abs(c.X - glove.center.X) + h.X <= glove.depth * 0.5 + 0.03 and math.abs(c.Z - glove.center.Z) + h.Z <= glove.width * 0.5 + 0.03,
						string.format("%s %s wraps the cuff without standing off it (%.3f x %.3f vs glove %.3f x %.3f)", id, g.name, h.X * 2, h.Z * 2, glove.depth, glove.width))
				else
					check(false, string.format("%s %s and its %s glove are measurable", id, g.name, side))
				end
				folder:Destroy()
				clone:Destroy()
			end
		end
		t.expect.equal(#problems, 0, #problems .. " signature problems:\n  " .. table.concat(problems, "\n  "))
	end)

	-- Round 6: at fight-camera distance a fighter reads by its outline: feet (barefoot, low shoes, boots/high-tops), hands
	-- (boxing gloves, fingerless gloves, wraps, open), legwear (bare shins under shorts or trunks, long pants/tights/gi)
	-- and hair (shaved or a hair item of its own). Every pair of fighters must differ in at least two of the four. On main
	-- Lumi and Goran differed only in hair (both in boots, open hands and long legwear).
	t.test("the six silhouettes differ at fight-camera distance (feet, hands, legwear, hair)", function()
		local chars = waitForTemplates()
		local features: { [string]: { [string]: string } } = {}
		for _, id in IDS do
			local spec = Specs.specs[id]
			local model = chars:FindFirstChild(id) :: Model
			local kinds: { [number]: string } = {}
			for _, s in spec.sourceAssets or {} do kinds[s.id] = string.lower(s.kind) end
			local shoes = 0
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") and d:GetAttribute("FightingLabRole") == "shoe" then shoes += 1 end
			end
			local f = { feet = if shoes == 0 then "barefoot" else tostring(spec.shoeStyle), hands = "open", legs = "shorts", hair = "shaved" }
			if wearsGloves(spec) then f.hands = "boxing gloves" end
			for _, acc in spec.accessories do
				local kind = kinds[acc.AssetId] or ""
				if f.hands == "open" and (string.find(kind, "grip glove", 1, true) or string.find(kind, "fingerless", 1, true)) then f.hands = "fingerless gloves" end
				if f.hands == "open" and string.find(kind, "hand wrap", 1, true) then f.hands = "wraps" end
				for _, word in { "pants", "tights", "leggings", "karate gi" } do
					if string.find(kind, word, 1, true) then f.legs = "long" end
				end
				if acc.AccessoryType == "Hair" then f.hair = tostring(acc.AssetId) end
			end
			for _, acc in model:GetChildren() do
				if acc:IsA("Accessory") and acc.AccessoryType == Enum.AccessoryType.Hair and f.hair == "shaved" then f.hair = "unauthored " .. acc.Name end
			end
			features[id] = f
		end
		local problems: { string } = {}
		for i, a in IDS do
			for j = i + 1, #IDS do
				local b = IDS[j]
				local same = {}
				local differ = 0
				for _, key in { "feet", "hands", "legs", "hair" } do
					if features[a][key] ~= features[b][key] then differ += 1 else table.insert(same, key .. " " .. features[a][key]) end
				end
				if differ < 2 then
					table.insert(problems, string.format("%s and %s differ in %d of feet/hands/legwear/hair (both: %s)", a, b, differ, table.concat(same, ", ")))
				end
			end
		end
		t.expect.equal(#problems, 0, #problems .. " look-alike pairs:\n  " .. table.concat(problems, "\n  "))
	end)

	-- Round 6: the motion runtime sizes each hand from Motion.BodyShape.handVolume, which reads any "*glove*" part or
	-- accessory as a boxing glove; open-hand gear (wraps, fingerless grips) must leave the hand an open hand there, and
	-- every boxing-gloved fighter must read as gloved.
	t.test("the motion runtime reads boxing gloves as gloves and open-hand gear as open hands", function()
		local chars = waitForTemplates()
		local BodyShape = require(ReplicatedStorage.FightingLab.Client.Motion.BodyShape) :: any
		for _, id in IDS do
			local spec = Specs.specs[id]
			local model = chars:FindFirstChild(id) :: Model
			local map = appliedAccessories(model)
			for _, acc in spec.accessories do
				if acc.Name then
					t.expect.truthy(map[acc.AssetId] ~= nil, string.format("%s renamed accessory %d is applied", id, acc.AssetId))
					for _, inst in map[acc.AssetId] or {} do
						t.expect.equal(inst.Name, acc.Name, string.format("%s accessory %d carries its authored instance name", id, acc.AssetId))
					end
				end
			end
			for _, side in { "Left", "Right" } do
				local volume = BodyShape.handVolume(model, model:FindFirstChild(side .. "Hand") :: BasePart)
				t.expect.equal(volume.gloved, wearsGloves(spec), string.format("%s %s hand reads as %s (source %s)", id, side, if volume.gloved then "gloved" else "open", tostring(volume.source)))
			end
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
			local leftHand = character:FindFirstChild("LeftHand") :: BasePart
			local bareHand = leftHand.Size
			local handScale = Vector3.new(table.unpack(spec.handScale or { 1, 1, 1 }))
			local function handIs(expected: Vector3, message: string)
				t.expect.truthy((leftHand.Size - expected).Magnitude < 1e-3, string.format("%s (hand %s, expected %s)", message, tostring(leftHand.Size), tostring(expected)))
				local wrist = leftHand:FindFirstChild("LeftWristRigAttachment") :: Attachment
				for _, d in character:GetDescendants() do
					if d:IsA("Motor6D") and d.Part1 == leftHand then
						t.expect.truthy(d.C1.Position:FuzzyEq(wrist.CFrame.Position, 1e-4), message .. ": the wrist joint follows the scaled wrist attachment")
					end
				end
			end
			t.expect.truthy(spec.handScale ~= nil, "the idempotency fixture fighter has a hand scale")
			Factory.dressCharacter(character, spec)
			local first = extras()
			t.expect.equal(#first, #spec.gear, "Goran gear added once")
			handIs(bareHand * handScale, "hand scale applied once")
			local signature = character:GetAttribute("FightingLabDressed")
			t.expect.truthy(typeof(signature) == "string" and signature ~= "", "dressed signature recorded")
			Factory.dressCharacter(character, spec)
			local second = extras()
			t.expect.equal(#second, #first, "second call adds nothing")
			t.expect.truthy(table.find(second, first[1]) ~= nil, "second call keeps the same gear instances")
			handIs(bareHand * handScale, "second call keeps the hand scale")
			for _, part in second do
				t.expect.falsy(part.Anchored, part.Name .. " unanchored")
				local weld = part:FindFirstChildOfClass("Weld")
				t.expect.truthy(weld and weld.Part0 and weld.Part0:IsDescendantOf(character), part.Name .. " welded to the live rig")
			end
			-- Re-dressing for another fighter swaps the extras, the hand visibility and the hand scale.
			Factory.dressCharacter(character, other)
			t.expect.equal(#extras(), #(other.gear or {}), "re-dress removes the previous fighter's gear")
			t.expect.equal((character:FindFirstChild("LeftHand") :: BasePart).Transparency, if other.hideHands then 1 else 0, "re-dress applies hideHands")
			handIs(bareHand * Vector3.new(table.unpack(other.handScale or { 1, 1, 1 })), "re-dress undoes the previous hand scale")
			Factory.dressCharacter(character, spec)
			t.expect.equal(#extras(), #spec.gear, "dressing back restores the gear")
			t.expect.equal((character:FindFirstChild("LeftHand") :: BasePart).Transparency, if spec.hideHands then 1 else 0, "dressing back restores hands")
			handIs(bareHand * handScale, "dressing back restores the hand scale")
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
