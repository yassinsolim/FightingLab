--!strict
-- Reusable R15 mesh limbs, customized and posed by FightingLab forward kinematics.
local Config = require(script.Parent.CombatConfig)
-- Presentation-only mesh template (MeshParts + head SpecialMesh, no scripts) is replicated so clients can
-- build local render rigs; the ServerStorage copy remains a server fallback.
local template: Instance? = script.Parent:WaitForChild("FighterMeshTemplate", 10)
if not template and game:GetService("RunService"):IsServer() then
	template = game:GetService("ServerStorage"):WaitForChild("FightingLabAssets"):WaitForChild("FighterMeshTemplate")
end
assert(template and template:IsA("Model"), "FightingLab needs its saved mesh template")
local meshTemplate: Model = template

export type Palette = { body: Color3, trim: Color3, skin: Color3, visor: Color3 }
export type Pose = {
	lean: number, yaw: number, crouch: number, fall: number,
	lShoulder: number, lRoll: number, lElbow: number,
	rShoulder: number, rRoll: number, rElbow: number,
	lHip: number, lHipRoll: number, lKnee: number,
	rHip: number, rHipRoll: number, rKnee: number,
}
export type EnvelopeProfile = { kind: string, anticipation: number, pull: number, windup: number }
export type Rig = {
	model: Model,
	parts: { [string]: BasePart },
	baseColors: { [string]: Color3 },
	pose: Pose,
	flash: number,
	details: { { part: BasePart, anchor: string, offset: CFrame } },
}

local FighterRig = {}
local rad = math.rad

local SPECS: { { name: string, size: Vector3, color: string } } = {
	{ name = "Pelvis", size = Vector3.new(1.5, 0.75, 0.95), color = "trim" },
	{ name = "Torso", size = Vector3.new(1.85, 1.7, 1.0), color = "body" },
	{ name = "Chest", size = Vector3.new(1.45, 0.8, 0.24), color = "body" },
	{ name = "Head", size = Vector3.new(0.92, 1.12, 0.96), color = "skin" },
	{ name = "Visor", size = Vector3.new(0.52, 0.08, 0.05), color = "skin" },
	{ name = "LUpperArm", size = Vector3.new(0.65, 1.1, 0.65), color = "body" },
	{ name = "LForearm", size = Vector3.new(0.56, 1.05, 0.56), color = "skin" },
	{ name = "LGlove", size = Vector3.new(0.62, 0.38, 0.62), color = "trim" },
	{ name = "RUpperArm", size = Vector3.new(0.65, 1.1, 0.65), color = "body" },
	{ name = "RForearm", size = Vector3.new(0.56, 1.05, 0.56), color = "skin" },
	{ name = "RGlove", size = Vector3.new(0.62, 0.38, 0.62), color = "trim" },
	{ name = "LThigh", size = Vector3.new(0.7, 1.2, 0.7), color = "trim" },
	{ name = "LShin", size = Vector3.new(0.62, 1.15, 0.62), color = "body" },
	{ name = "LFoot", size = Vector3.new(0.65, 0.3, 0.95), color = "trim" },
	{ name = "RThigh", size = Vector3.new(0.7, 1.2, 0.7), color = "trim" },
	{ name = "RShin", size = Vector3.new(0.62, 1.15, 0.62), color = "body" },
	{ name = "RFoot", size = Vector3.new(0.65, 0.3, 0.95), color = "trim" },
}

local MESH_NAMES: { [string]: string } = {
	Pelvis = "LowerTorso", Torso = "UpperTorso", Head = "Head",
	LUpperArm = "LeftUpperArm", LForearm = "LeftLowerArm", LGlove = "LeftHand",
	RUpperArm = "RightUpperArm", RForearm = "RightLowerArm", RGlove = "RightHand",
	LThigh = "LeftUpperLeg", LShin = "LeftLowerLeg", LFoot = "LeftFoot",
	RThigh = "RightUpperLeg", RShin = "RightLowerLeg", RFoot = "RightFoot",
}

local LIMB_PARTS = {
	LeadArm = { "LForearm", "LGlove" },
	RearArm = { "RForearm", "RGlove" },
	RearLeg = { "RShin", "RFoot" },
 LeadLeg = { "LShin", "LFoot" },
}

function FighterRig.basePose(): Pose
	return {
		lean = 0, yaw = 0, crouch = 0, fall = 0,
		lShoulder = rad(60), lRoll = rad(-10), lElbow = rad(100),
		rShoulder = rad(55), rRoll = rad(10), rElbow = rad(105),
		lHip = rad(15), lHipRoll = rad(-6), lKnee = rad(-12),
		rHip = rad(-12), rHipRoll = rad(6), rKnee = rad(-18),
	}
end

function FighterRig.new(name: string, palette: Palette, parent: Instance): Rig
	local model = Instance.new("Model")
	model.Name = name
	local parts: { [string]: BasePart } = {}
	local baseColors: { [string]: Color3 } = {}
	for _, spec in SPECS do
		local meshName = MESH_NAMES[spec.name]
		local p: BasePart
		if meshName then
			local source = meshTemplate:FindFirstChild(meshName)
			assert(source and source:IsA("BasePart"), "Missing fighter mesh: " .. meshName)
			p = source:Clone()
			if p:IsA("MeshPart") then
				p.TextureID = ""
			end
		else
			p = Instance.new("Part")
		end
		if spec.name == "Head" then
			local headMesh = p:FindFirstChildOfClass("SpecialMesh")
			assert(headMesh, "Fighter template needs its authored head mesh")
			headMesh.Scale = Vector3.new(0.9, 0.9, 0.9)
		end
		p.Name = spec.name
		p.Size = spec.size
		p.CFrame = CFrame.new(0, -100, 0)
		p:SetAttribute("SourcePart", meshName)
		if spec.name == "Chest" or spec.name == "Visor" then
			p.Transparency = 1
		end
		local c = if spec.color == "body" then palette.body elseif spec.color == "trim" then palette.trim elseif spec.color == "skin" then palette.skin else palette.visor
		p.Color = c
		p.Material = Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = true
		p.Parent = model
		parts[spec.name] = p
		baseColors[spec.name] = c
	end
	local details: { { part: BasePart, anchor: string, offset: CFrame } } = {}
	local function detail(n: string, anchor: string, size: Vector3, offset: CFrame, color: Color3, rounded: boolean, material: Enum.Material?)
		local part = Instance.new("Part")
		part.Name, part.Size, part.CFrame = n, size, CFrame.new(0, -100, 0)
		part.Shape = Enum.PartType.Block
		if rounded then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = part
		end
		part.Color, part.Material = color, material or Enum.Material.SmoothPlastic
		part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
		part.Parent = model
		table.insert(details, { part = part, anchor = anchor, offset = offset })
	end
	local dark = Color3.fromRGB(25, 23, 29)
	local cloth = Enum.Material.SmoothPlastic
	detail("HairCap", "Head", Vector3.new(0.96, 0.52, 0.98), CFrame.new(0, 0.4, 0.04), dark, true)
	detail("Jaw", "Head", Vector3.new(0.71, 0.36, 0.76), CFrame.new(0, -0.39, -0.06), palette.skin, true)
	detail("Nose", "Head", Vector3.new(0.16, 0.25, 0.19), CFrame.new(0, -0.02, -0.46), palette.skin, true)
	detail("Mouth", "Head", Vector3.new(0.28, 0.035, 0.035), CFrame.new(0, -0.24, -0.46), dark, false)
	detail("Neck", "Torso", Vector3.new(0.5, 0.48, 0.5), CFrame.new(0, 0.93, 0), palette.skin, true)
	detail("Belt", "Pelvis", Vector3.new(1.45, 0.16, 0.96), CFrame.new(0, 0.22, 0), palette.body, false, cloth)
	detail("BeltKnot", "Pelvis", Vector3.new(0.26, 0.22, 0.17), CFrame.new(0, 0.22, -0.54), palette.trim, true, cloth)
	for _, side in { -1, 1 } do
		local prefix = if side == -1 then "L" else "R"
		detail(prefix .. "Eye", "Head", Vector3.new(0.17, 0.065, 0.05), CFrame.new(side * 0.22, 0.1, -0.443), Color3.fromRGB(225, 224, 211), false)
		detail(prefix .. "Pupil", "Head", Vector3.new(0.06, 0.07, 0.035), CFrame.new(side * 0.22, 0.1, -0.474), dark, true)
		detail(prefix .. "Brow", "Head", Vector3.new(0.24, 0.055, 0.06), CFrame.new(side * 0.22, 0.2, -0.426) * CFrame.Angles(0, 0, side * 0.13), dark, false)
		detail(prefix .. "Ear", "Head", Vector3.new(0.16, 0.3, 0.17), CFrame.new(side * 0.47, 0, 0), palette.skin, true)
		detail(prefix .. "ShoulderCap", "Torso", Vector3.new(0.61, 0.62, 0.74), CFrame.new(side * 0.88, 0.53, 0), palette.body, true, cloth)
		detail(prefix .. "Lapel", "Torso", Vector3.new(0.14, 1.05, 0.14), CFrame.new(side * 0.22, 0.12, -0.5) * CFrame.Angles(0, 0, side * 0.36), palette.trim, false, cloth)
		detail(prefix .. "Cuff", prefix .. "Forearm", Vector3.new(0.47, 0.25, 0.47), CFrame.new(0, -0.4, 0), palette.body, true, cloth)
		detail(prefix .. "Thumb", prefix .. "Glove", Vector3.new(0.2, 0.3, 0.25), CFrame.new(side * 0.24, 0.05, -0.12), palette.trim, true)
		detail(prefix .. "KneePad", prefix .. "Shin", Vector3.new(0.53, 0.4, 0.22), CFrame.new(0, 0.4, -0.23), palette.trim, true, cloth)
		detail(prefix .. "Sole", prefix .. "Foot", Vector3.new(0.54, 0.1, 0.96), CFrame.new(0, -0.15, 0), dark, false)
		for j = 1, 3 do
			detail(prefix .. "BootLace" .. j, prefix .. "Foot", Vector3.new(0.34, 0.025, 0.04), CFrame.new(0, 0.16, -0.28 + j * 0.15), palette.body, false)
		end
	end
	model:SetAttribute("MeshTemplateAssetId", 9983145752)
	model:SetAttribute("Presentation", "Original FightingLab training outfit on reusable R15 geometry")
	model.PrimaryPart = parts.Pelvis
	model.Parent = parent
	return { model = model, parts = parts, baseColors = baseColors, pose = FighterRig.basePose(), flash = 0, details = details }
end

-- Presentation envelopes: anticipation (pull back + wind-up) over the first `anticipation` share of startup,
-- a fast ease into full extension that peaks exactly on the first active frame, then a settling recovery.
local PROFILES: { [string]: EnvelopeProfile } = {
	Punch = { kind = "Punch", anticipation = 0.65, pull = -0.12, windup = 0.35 },
	Kick = { kind = "Kick", anticipation = 0.65, pull = -0.06, windup = 0.6 },
	Rise = { kind = "Rise", anticipation = 0.7, pull = -0.18, windup = 0.5 },
	Sweep = { kind = "Sweep", anticipation = 0.6, pull = -0.22, windup = 0.45 },
}

function FighterRig.envelopeProfile(moveName: string): EnvelopeProfile
	local named = PROFILES[moveName]
	if named then
		return named
	end
	local m = Config.Moves[moveName]
	return if m.limb == "LeadArm" or m.limb == "RearArm" then PROFILES.Punch else PROFILES.Kick
end

-- Returns (extension, windup). extension <= 0 is anticipation, 1 is full strike, 0 is neutral guard.
function FighterRig.moveEnvelope(moveName: string, moveFrame: number): (number, number)
	local m = Config.Moves[moveName]
	local prof = FighterRig.envelopeProfile(moveName)
	if moveFrame <= m.startup then
		local a = prof.anticipation * m.startup
		if moveFrame <= a then
			local u = math.clamp(moveFrame / a, 0, 1)
			u = u * u * (3 - 2 * u)
			return prof.pull * u, prof.windup * u
		end
		local u = (moveFrame - a) / (m.startup + 1 - a)
		return prof.pull + (1 - prof.pull) * u * u, prof.windup * (1 - u) * (1 - u)
	elseif moveFrame <= m.startup + m.active then
		return 1, 0
	end
	local r = math.clamp((moveFrame - m.startup - m.active) / m.recovery, 0, 1)
	return (1 - r) * (1 - r), 0
end

-- Target pose for a simulation state. moveFrame is 1-based within the move.
-- idlePhase (radians, presentation time) adds breathing/weight shift; direction is +1 forward walk, -1 backwalk.
function FighterRig.targetPose(state: string, moveName: string?, moveFrame: number, walkPhase: number, stun: number, crouched: boolean?, idlePhase: number?, direction: number?): Pose
	local p = FighterRig.basePose()
	if state == "Airborne" then
		p.lean = -0.65; p.lShoulder = rad(135); p.rShoulder = rad(120); p.lElbow = rad(35); p.rElbow = rad(40)
		p.lHip = rad(65); p.rHip = rad(45); p.lKnee = rad(-65); p.rKnee = rad(-50)
	elseif state == "Landing" or state == "Getup" then
		p.fall = if state == "Landing" then 1 else math.clamp(stun / Config.GetupFrames, 0, 1)
		p.lShoulder = rad(100); p.rShoulder = rad(90)
	elseif state == "Dash" then
		p.lean = -0.25; p.crouch = 0.3; p.lHip = rad(40); p.rHip = rad(-40)
	elseif state == "Walk" then
		-- Short guarded stride keeps both feet near the floor so the floor clamp does not bob the head.
		local back = (direction or 1) < 0
		local s = if back then -math.sin(walkPhase) else math.sin(walkPhase)
		local swing = if back then 0.22 else 0.3
		p.lHip, p.rHip = rad(15) + s * swing, rad(-12) - s * swing
		p.lKnee, p.rKnee = -0.2 - math.max(0, -s) * 0.45, -0.2 - math.max(0, s) * 0.45
		p.lean = if back then -0.06 else 0.05
		p.yaw = s * 0.05
	elseif state == "Step" then
		local s = math.sin(walkPhase)
		p.lHipRoll, p.rHipRoll = -0.1 - s * 0.3, 0.1 - s * 0.3
		p.lean, p.crouch = 0.05, 0.15
	elseif state == "Block" or state == "CrouchBlock" or state == "Blockstun" then
		p.lShoulder, p.rShoulder = rad(78), rad(78)
		p.lElbow, p.rElbow = rad(130), rad(130)
		p.lRoll, p.rRoll = rad(18), rad(-18)
		p.crouch, p.lean = 0.2, -0.08
		if state == "Blockstun" then
			p.lean = 0.12
		end
	elseif state == "Hitstun" then
		p.lean = 0.35 + math.min(stun, 10) * 0.02
		p.lShoulder, p.rShoulder = rad(20), rad(25)
		p.lElbow, p.rElbow = rad(40), rad(50)
		p.crouch = 0.2
	elseif state == "KO" then
		p.fall = 1
		p.lShoulder, p.rShoulder = rad(150), rad(140)
		p.lElbow, p.rElbow = rad(10), rad(15)
		p.lHip, p.rHip = rad(5), rad(-5)
		p.lKnee, p.rKnee = rad(-5), rad(-10)
	elseif moveName then
		local m = Config.Moves[moveName]
		local ext, windup = FighterRig.moveEnvelope(moveName, moveFrame)
		if m.limb == "LeadArm" then
			p.lShoulder = rad(60) + ext * rad(30) - windup * 0.3
			p.lElbow = rad(100) * (1 - ext) + windup * 0.4
			p.lRoll = rad(-10) + ext * rad(12)
			p.yaw = -0.25 * ext + windup * 0.3
		elseif m.limb == "RearArm" then
			p.rShoulder = rad(55) + ext * rad(40) - windup * 0.6
			p.rElbow = rad(105) * (1 - ext) + windup
			p.rRoll = rad(10) - ext * rad(16)
			p.yaw = -windup + ext * 0.6
			p.lean = -0.12 * ext
			p.crouch = 0.12 * math.max(ext, 0)
		elseif m.limb == "LeadLeg" then
			p.lHip = rad(15) + ext * rad(if m.height == "Low" then 35 else 85)
			p.lKnee = rad(-12) - windup + ext * rad(8); p.lean = 0.2 * ext; p.yaw = -0.25 * ext
		else
			p.rHip = rad(-12) + ext * rad(97) - windup * 0.4
			p.rKnee = rad(-18) - windup * 1.2 + ext * rad(8)
			p.rHipRoll = ext * rad(-14)
			p.lean = 0.28 * ext
			p.yaw = 0.3 * ext
		end
	end
	if crouched or state == "Crouch" or state == "CrouchBlock" then
		p.crouch = 1.0; p.lHip += rad(40); p.rHip += rad(67); p.lKnee -= rad(98); p.rKnee -= rad(92)
	end
	if moveName == "Rise" or moveName == "Sweep" then
		local ext, windup = FighterRig.moveEnvelope(moveName, moveFrame)
		if moveName == "Rise" then
			p.rShoulder = rad(55) + ext * rad(85) - windup * 0.5; p.rElbow = rad(105) * (1 - ext) + windup * 0.3
			p.lean = -0.2 * ext + windup * 0.25
		else
			p.rHip = rad(18) + ext * rad(47); p.rHipRoll = rad(6) - ext * rad(46) + windup * 0.3; p.yaw = ext * 0.5 - windup * 0.5
		end
	end
	if (state == "Idle" or state == "Crouch") and idlePhase then
		-- Breathing and a slow weight shift; hip angles stay under the foot-planting threshold.
		local breath, shift = math.sin(idlePhase), math.sin(idlePhase * 0.5)
		p.lean += 0.025 * breath; p.lShoulder += 0.045 * breath; p.rShoulder += 0.045 * math.sin(idlePhase + 0.6)
		p.yaw += 0.04 * shift; p.lHipRoll += 0.025 * shift; p.rHipRoll += 0.025 * shift
	end
	return p
end

local POSE_KEYS = { "lean", "yaw", "crouch", "fall", "lShoulder", "lRoll", "lElbow", "rShoulder", "rRoll", "rElbow", "lHip", "lHipRoll", "lKnee", "rHip", "rHipRoll", "rKnee" }

function FighterRig.blend(rig: Rig, target: Pose, alpha: number)
	local cur: { [string]: number } = rig.pose
	local tgt: { [string]: number } = target
	for _, key in POSE_KEYS do
		cur[key] += (tgt[key] - cur[key]) * alpha
	end
end

local function limb(origin: CFrame, pitch: number, roll: number, upperLen: number, bend: number, lowerLen: number): (CFrame, CFrame, CFrame)
	local joint = origin * CFrame.Angles(pitch, 0, roll)
	local upper = joint * CFrame.new(0, -upperLen / 2, 0)
	local mid = joint * CFrame.new(0, -upperLen, 0) * CFrame.Angles(bend, 0, 0)
	local lower = mid * CFrame.new(0, -lowerLen / 2, 0)
	local tip = mid * CFrame.new(0, -lowerLen, 0)
	return upper, lower, tip
end

-- Applies the rig's current pose at a ground position facing a flat direction.
function FighterRig.apply(rig: Rig, groundPos: Vector3, facing: Vector3, highlightLimb: string?, highlightColor: Color3?)
	local p = rig.pose
	local ground = CFrame.lookAt(groundPos, groundPos + facing)
	local hipHeight = 1.2 + 1.15 + 0.25 - p.crouch
	local pelvis: CFrame
	if p.fall > 0.01 then
		pelvis = ground * CFrame.new(0, hipHeight * (1 - p.fall) + 0.45 * p.fall, p.fall * 1.2) * CFrame.Angles(p.fall * rad(85), 0, 0)
	else
		pelvis = ground * CFrame.new(0, hipHeight, 0)
	end
	local torso = pelvis * CFrame.Angles(p.lean, p.yaw, 0) * CFrame.new(0, 1.1, 0)
	local head = torso * CFrame.new(0, 1.3, 0)
	local parts = rig.parts
	local list: { BasePart } = {}
	local cfs: { CFrame } = {}
	local function put(name: string, cf: CFrame)
		table.insert(list, parts[name])
		table.insert(cfs, cf)
	end
	put("Pelvis", pelvis)
	put("Torso", torso)
	put("Chest", torso * CFrame.new(0, 0.25, -0.48))
	put("Head", head)
	put("Visor", head * CFrame.new(0, 0.05, -0.45))
	local lu, lf, lt = limb(torso * CFrame.new(-1.08, 0.6, 0), p.lShoulder, p.lRoll, 1.1, p.lElbow, 1.05)
	put("LUpperArm", lu); put("LForearm", lf); put("LGlove", lt)
	local ru, rf, rt = limb(torso * CFrame.new(1.08, 0.6, 0), p.rShoulder, p.rRoll, 1.1, p.rElbow, 1.05)
	put("RUpperArm", ru); put("RForearm", rf); put("RGlove", rt)
	local tu, ts, tf = limb(pelvis * CFrame.new(-0.42, -0.2, 0), p.lHip, p.lHipRoll, 1.2, p.lKnee, 1.15)
	local grounded = groundPos.Y <= 0.01
	local function foot(tip: CFrame, hip: number): CFrame
		if grounded and p.fall < 0.01 and hip < rad(if p.crouch > 0.5 then 70 else 50) then
			return (CFrame.new(tip.Position) * ground.Rotation) * CFrame.new(0, -0.1, -0.2)
		end
		return tip * CFrame.new(0, -0.1, -0.2)
	end
	put("LThigh", tu); put("LShin", ts); put("LFoot", foot(tf, p.lHip))
	local uu, us, uf = limb(pelvis * CFrame.new(0.42, -0.2, 0), p.rHip, p.rHipRoll, 1.2, p.rKnee, 1.15)
	put("RThigh", uu); put("RShin", us); put("RFoot", foot(uf, p.rHip))
	local anchors: { [string]: CFrame } = {}
	for index, part in list do
		anchors[part.Name] = cfs[index]
	end
	for _, item in rig.details do
		table.insert(list, item.part)
		table.insert(cfs, anchors[item.anchor] * item.offset)
	end
	if grounded then
		local lowest = math.huge
		for index, part in list do
			if p.fall > 0.01 or part.Name == "LFoot" or part.Name == "RFoot" or part.Name == "LSole" or part.Name == "RSole" then
				local cf, half = cfs[index], part.Size / 2
				local bottom = cf.Position.Y - math.abs(cf.RightVector.Y) * half.X - math.abs(cf.UpVector.Y) * half.Y - math.abs(cf.LookVector.Y) * half.Z
				lowest = math.min(lowest, bottom)
			end
		end
		-- Presentation-only floor contact; never changes simulation positions or hit lanes.
		local lift = Vector3.new(0, groundPos.Y + 0.015 - lowest, 0)
		for index, cf in cfs do
			cfs[index] = cf + lift
		end
	end
	workspace:BulkMoveTo(list, cfs, Enum.BulkMoveMode.FireCFrameChanged)

	local lit: { [string]: boolean } = {}
	if highlightLimb and LIMB_PARTS[highlightLimb] then
		for _, n in LIMB_PARTS[highlightLimb] do
			lit[n] = true
		end
	end
	for name, part in parts do
		local want: Color3
		if lit[name] and highlightColor then
			want = highlightColor
		elseif rig.flash > 0 and name ~= "Visor" and name ~= "Chest" then
			want = Color3.new(1, 1, 1)
		else
			want = rig.baseColors[name]
		end
		if part.Color ~= want then
			part.Color = want
		end
	end
	if rig.flash > 0 then
		rig.flash -= 1
	end
end

return FighterRig