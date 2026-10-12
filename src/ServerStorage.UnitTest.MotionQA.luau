--!strict
-- MotionQA: smoothness, joint-limit and clipping QA of the fight animation runtime on the REAL fighter rigs.
--
-- Plays views (fighter states, moves, throws, transitions, or a recorded CombatSim fight) through the same path as
-- CharacterPresenter (MotionPlayer.presentFrame: sample -> root placement -> apply -> throw grips -> contact pass) at
-- 60 frames per second on clones of ReplicatedStorage.FightingLab.Characters, and measures every frame:
--   pops        per-part world-rotation change (deg/frame) and limb-tip speed (studs/frame): spikes over an absolute
--               threshold AND over POP_RATIO x the local median (+-6 frames); at transitions (animation key changes and
--               their crossfades) any joint rotating more than TRANSITION_DEG in one frame
--   flips       elbow/knee bend direction (in the parent part's frame) turning > FLIP_DEG in one frame (bent limbs)
--   limits      elbow/knee hyperextension or over-flexion, shoulder/hip twist, wrist, ankle, neck yaw, waist twist
--   self        hand (glove) inside the own head or torso, forearm/upper arm through the torso, legs through each other
--   opponent    striking hand/foot depth into the opponent's body; torsos overlapping outside throws
--   jitter      zig-zag (velocity reversing with speed on both sides) in looping idles and walks
-- Rig geometry is read from the rig itself (part sizes, joints, an optional glove accessory, LeftFist/RightFist parts,
-- an optional FightingLabGloveRadius attribute on the hands), so it works for any fighter proportions.
-- Used by ServerStorage.UnitTest.Cases.MotionQA_Test (targets) and tools/mocap/motionqa_report.luau (full report).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- _G.MotionQALab: an alternative module root (a fresh clone of FightingLab's modules, for hot reloads in a running
-- Studio session where required modules stay cached); characters always come from ReplicatedStorage.FightingLab.
local Lab = (_G :: any).MotionQALab or ReplicatedStorage:WaitForChild("FightingLab")
local Characters = ReplicatedStorage:WaitForChild("FightingLab"):WaitForChild("Characters")
local Config = require(Lab.CombatConfig)
local Roster = require(Lab.Roster)
local MotionPlayer = require(Lab.Client.MotionPlayer)
local ClipLibrary = require(Lab.Client.Motion.ClipLibrary)

local QA = {}
QA.MotionPlayer, QA.Config, QA.ClipLibrary, QA.Roster = MotionPlayer, Config, ClipLibrary, Roster
QA.FLOOR_Y = 260
QA.ORIGIN = Vector3.new(0, QA.FLOOR_Y, 900)

-- Targets / thresholds (studs, degrees, per 60 Hz frame).
QA.T = {
	popDeg = 12, popSpeed = 0.16, popRatio = 4, medDegFloor = 1.5, medSpeedFloor = 0.03,
	transitionDeg = 15, transitionRatio = 1.5,
	flipDeg = 45, straightDeg = 15,
	elbowMax = 160, kneeMax = 165, hyper = 5, shoulderTwist = 120, hipTwist = 80, wrist = 80,
	ankleDorsi = 45, anklePlantar = 80, ankleRoll = 40, ankleYaw = 45, neckYaw = 80, waistTwist = 70,
	selfDepth = 0.05, handHeadDepth = 0.03, strikeDepth = 0.15, bodyOverlap = 0.10,
	-- Jitter: a part turning around three times within 6 frames (a >= 10 Hz shake) at visible speeds both ways: >= 0.02
	-- studs or 2 degrees per frame (about one pixel at the fight camera's ~14 studs on a 1080p screen); contact events (a
	-- foot landing while the pelvis still sinks) turn a part around once.
	jitterPos = 0.02, jitterDeg = 2, jitterWindow = 6, jitterSkip = 12,
}

local PARTS = { "LowerTorso", "UpperTorso", "Head", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot" }
local JOINTS = { "Root", "Waist", "Neck", "LeftShoulder", "LeftElbow", "LeftWrist", "RightShoulder", "RightElbow", "RightWrist", "LeftHip", "LeftKnee", "LeftAnkle", "RightHip", "RightKnee", "RightAnkle" }
local TIPS = { "LeftHand", "RightHand", "LeftFoot", "RightFoot", "Head" }
local LIMBS = {
	LeftArm = { "LeftShoulder", "LeftElbow", "LeftWrist", "UpperTorso" },
	RightArm = { "RightShoulder", "RightElbow", "RightWrist", "UpperTorso" },
	LeftLeg = { "LeftHip", "LeftKnee", "LeftAnkle", "LowerTorso" },
	RightLeg = { "RightHip", "RightKnee", "RightAnkle", "LowerTorso" },
}
QA.PARTS, QA.JOINTS = PARTS, JOINTS

-- Geometry ------------------------------------------------------------------------------------------------------------

local function sdEllipsoid(p: Vector3, r: Vector3): number
	local k0 = Vector3.new(p.X / r.X, p.Y / r.Y, p.Z / r.Z).Magnitude
	local k1 = Vector3.new(p.X / (r.X * r.X), p.Y / (r.Y * r.Y), p.Z / (r.Z * r.Z)).Magnitude
	if k1 < 1e-9 then return -math.min(r.X, r.Y, r.Z) end
	return k0 * (k0 - 1) / k1
end
local function sdRoundBox(p: Vector3, half: Vector3, rr: number): number
	local q = Vector3.new(math.abs(p.X), math.abs(p.Y), math.abs(p.Z)) - (half - Vector3.one * rr)
	local outside = Vector3.new(math.max(q.X, 0), math.max(q.Y, 0), math.max(q.Z, 0)).Magnitude
	return outside + math.min(math.max(q.X, q.Y, q.Z), 0) - rr
end
local function segSegDistance(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3): number
	local d1, d2, r = q1 - p1, q2 - p2, p1 - p2
	local a, e, f = d1:Dot(d1), d2:Dot(d2), d2:Dot(r)
	local s, t
	if a <= 1e-9 and e <= 1e-9 then return (p1 - p2).Magnitude end
	if a <= 1e-9 then
		s, t = 0, math.clamp(f / e, 0, 1)
	else
		local c = d1:Dot(r)
		if e <= 1e-9 then
			t, s = 0, math.clamp(-c / a, 0, 1)
		else
			local b = d1:Dot(d2)
			local denom = a * e - b * b
			s = if denom > 1e-9 then math.clamp((b * f - c * e) / denom, 0, 1) else 0
			t = (b * s + f) / e
			if t < 0 then t, s = 0, math.clamp(-c / a, 0, 1) elseif t > 1 then t, s = 1, math.clamp((b - c) / a, 0, 1) end
		end
	end
	return ((p1 + d1 * s) - (p2 + d2 * t)).Magnitude
end
QA.sdEllipsoid, QA.sdRoundBox, QA.segSegDistance = sdEllipsoid, sdRoundBox, segSegDistance

local function gloveRadius(model: Model, hand: BasePart): (number?, string?)
	local attr = hand:GetAttribute("FightingLabGloveRadius")
	if typeof(attr) == "number" and attr > 0 then return attr, "attribute" end
	local fist = hand:FindFirstChild(if hand.Name == "LeftHand" then "LeftFist" else "RightFist")
	if fist and fist:IsA("BasePart") then return (fist.Size.X + fist.Size.Y + fist.Size.Z) / 6, "fist" end
	for _, a in model:GetChildren() do
		if a:IsA("Accessory") and string.find(string.lower(a.Name), "glove", 1, true) then
			local h = a:FindFirstChild("Handle")
			if h and h:IsA("BasePart") then
				-- One layered accessory holds both gloves (authored in the T-pose: X spans both arms); the glove's own
				-- cross-section is its Y x Z.
				return (h.Size.Y + h.Size.Z) * 0.25, "accessory"
			end
		end
	end
	return nil, nil
end

export type Profile = { ys: { number }, r: { { number } }, n: number, y0: number, y1: number }
export type Geo = {
	head: Vector3, upper: Vector3, lower: Vector3, upperRR: number, lowerRR: number,
	hand: { [string]: { r: number, len: number, gloved: boolean, source: string } },
	limbR: { [string]: number }, foot: { [string]: Vector3 }, profiles: { [string]: Profile }?,
}

-- Radial surface profile of a body part's real collision geometry (MeshPart hulls), in the part's frame: SLICES
-- heights x DIRS directions of rays cast at the part's long axis. sdProfile interpolates it (within ~0.02 studs of the
-- hull surface near it), so tapered torsos and heads are not their bounding boxes.
local SLICES, DIRS = 9, 16
local function profilePart(part: BasePart): Profile?
	local wasQuery = part.CanQuery
	part.CanQuery = true
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { part }
	local size = part.Size
	local far = (size.X + size.Y + size.Z) * 2
	local ys, rings = {}, {}
	local y0, y1 = math.huge, -math.huge
	local any = false
	for i = 0, SLICES - 1 do
		local y = -size.Y * 0.5 + size.Y * (i + 0.5) / SLICES
		local ring = {}
		local hitAny = false
		for j = 0, DIRS - 1 do
			local a = 2 * math.pi * j / DIRS
			local dir = Vector3.new(math.cos(a), 0, math.sin(a))
			local axis = part.CFrame:PointToWorldSpace(Vector3.new(0, y, 0))
			local origin = part.CFrame:PointToWorldSpace(Vector3.new(0, y, 0) + dir * far)
			local hit = workspace:Raycast(origin, axis - origin, params)
			if hit then
				local localHit = part.CFrame:PointToObjectSpace(hit.Position)
				ring[j + 1] = math.max(0, Vector3.new(localHit.X, 0, localHit.Z).Magnitude)
				hitAny = true
			else
				ring[j + 1] = 0
			end
		end
		if hitAny then
			any = true
			y0, y1 = math.min(y0, y), math.max(y1, y)
		end
		table.insert(ys, y)
		table.insert(rings, ring)
	end
	part.CanQuery = wasQuery
	if not any then return nil end
	return { ys = ys, r = rings, n = DIRS, y0 = y0 - size.Y * 0.5 / SLICES, y1 = y1 + size.Y * 0.5 / SLICES }
end
QA.profilePart = profilePart

-- Approximate signed distance of a point (part space) to a profiled part.
local function sdProfile(prof: Profile, p: Vector3): number
	local rho = math.sqrt(p.X * p.X + p.Z * p.Z)
	local a = math.atan2(p.Z, p.X)
	if a < 0 then a += 2 * math.pi end
	local fj = a / (2 * math.pi) * prof.n
	local j0 = math.floor(fj) % prof.n
	local j1 = (j0 + 1) % prof.n
	local tj = fj - math.floor(fj)
	local ys = prof.ys
	local n = #ys
	local y = math.clamp(p.Y, ys[1], ys[n])
	local i0 = 1
	for i = 1, n - 1 do if y >= ys[i] then i0 = i end end
	local i1 = math.min(i0 + 1, n)
	local ti = if i1 > i0 then (y - ys[i0]) / (ys[i1] - ys[i0]) else 0
	local function ringR(i: number): number return prof.r[i][j0 + 1] * (1 - tj) + prof.r[i][j1 + 1] * tj end
	local R = ringR(i0) * (1 - ti) + ringR(i1) * ti
	local radial = rho - R
	local vertical = math.max(prof.y0 - p.Y, p.Y - prof.y1)
	if vertical > 0 then return math.sqrt(math.max(radial, 0) ^ 2 + vertical * vertical) end
	if R <= 1e-3 then return math.max(radial, vertical) end
	return math.max(radial, vertical)
end
QA.sdProfile = sdProfile
local function rigGeometry(model: Model, rig: any): Geo
	local parts = rig.parts
	local function size(n: string): Vector3 return (parts[n] :: BasePart).Size end
	local hand = {}
	for _, n in { "LeftHand", "RightHand" } do
		local part = parts[n] :: BasePart
		local g, source = gloveRadius(model, part)
		if g then
			hand[n] = { r = g, len = g * 0.35, gloved = true, source = source :: string }
		else
			local s = part.Size
			hand[n] = { r = (s.X + s.Z) * 0.25, len = s.Y * 0.32, gloved = false, source = "hand" }
		end
	end
	local limbR = {}
	for _, n in { "LeftUpperArm", "LeftLowerArm", "RightUpperArm", "RightLowerArm", "LeftUpperLeg", "LeftLowerLeg", "RightUpperLeg", "RightLowerLeg" } do
		local s = size(n)
		local r = math.min(s.X, s.Z) * 0.45
		-- Mean radius of the limb's real hull over its middle slices.
		local prof = profilePart(parts[n] :: BasePart)
		if prof then
			local sum, count = 0, 0
			for i = 3, SLICES - 2 do
				for _, v in prof.r[i] do
					if v > 0 then sum += v; count += 1 end
				end
			end
			if count > 0 then r = sum / count end
		end
		limbR[n] = r
	end
	local up, lo = size("UpperTorso") * 0.5, size("LowerTorso") * 0.5
	local profiles = {}
	for _, n in { "Head", "UpperTorso", "LowerTorso" } do
		local prof = profilePart(parts[n] :: BasePart)
		if prof then profiles[n] = prof end
	end
	return {
		head = size("Head") * 0.5 * 0.95, upper = up, lower = lo,
		upperRR = math.min(up.X, up.Z) * 0.45, lowerRR = math.min(lo.X, lo.Z) * 0.45,
		hand = hand, limbR = limbR, foot = { LeftFoot = size("LeftFoot") * 0.5, RightFoot = size("RightFoot") * 0.5 },
		profiles = profiles,
	}
end
QA.rigGeometry = rigGeometry

-- Rigs ---------------------------------------------------------------------------------------------------------------

export type Staged = { id: string, model: Model, rig: any, root: BasePart, geo: Geo, aim: { [string]: number } }

function QA.stage(ids: { string }?, folderName: string?): { [string]: Staged }
	local folder = workspace:FindFirstChild(folderName or "MotionQARigs")
	if folder then folder:Destroy() end
	local newFolder = Instance.new("Folder")
	newFolder.Name = folderName or "MotionQARigs"
	newFolder.Parent = workspace
	local rigs: { [string]: Staged } = {}
	local list = ids or Roster.order
	local n = 0
	for _, id in list do
		for copy = 1, 2 do
			local template = Characters:FindFirstChild(id)
			if not template then error("MotionQA: no character template " .. id) end
			local clone = (template :: Model):Clone()
			clone.Name = "QA_" .. id .. "_" .. copy
			for _, d in clone:GetDescendants() do
				if d:IsA("BasePart") then
					d.Anchored = d.Name == "HumanoidRootPart"; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false
				elseif d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Sound") then
					d:Destroy()
				end
			end
			n += 1
			clone:PivotTo(CFrame.new(QA.ORIGIN + Vector3.new(n * 9, 40, 0)))
			clone.Parent = newFolder
			local rig = MotionPlayer.collectRig(clone)
			local root = clone:FindFirstChild("HumanoidRootPart") :: BasePart
			local staged: Staged = { id = id, model = clone, rig = rig, root = root, geo = rigGeometry(clone, rig), aim = MotionPlayer.standingHeights(rig, id) }
			rigs[if copy == 1 then id else id .. "#2"] = staged
		end
	end
	return rigs
end

function QA.destroy(rigs: { [string]: Staged }?)
	local folder = workspace:FindFirstChild("MotionQARigs")
	if folder then folder:Destroy() end
	if rigs then for _, r in rigs do r.model:Destroy() end end
end

-- Posed part frames of a rig after MotionPlayer.apply (through the joint chain; the engine updates parts next step).
local function posed(rig: any): { [string]: CFrame }
	local cf: { [string]: CFrame } = {}
	local motors = rig.motors
	local rootPart = motors.Root.Part0 :: BasePart
	cf[rootPart.Name] = rootPart.CFrame
	for _, jn in JOINTS do
		local m = motors[jn] :: Motor6D
		local p0, p1 = m.Part0 :: BasePart, m.Part1 :: BasePart
		local parent = cf[p0.Name]
		if parent then cf[p1.Name] = parent * m.C0 * m.Transform * m.C1:Inverse() end
	end
	return cf
end
QA.posed = posed

local function jointPoint(rig: any, cf: { [string]: CFrame }, joint: string): Vector3
	local m = rig.motors[joint] :: Motor6D
	return (cf[(m.Part0 :: BasePart).Name] * m.C0).Position
end

-- Volumes ------------------------------------------------------------------------------------------------------------

-- Signed distance from a world point to the body core (head, chest, pelvis: profiled hulls when available, else the
-- head ellipsoid and rounded boxes).
local function partDistance(geo: Geo, cf: { [string]: CFrame }, name: string, p: Vector3): number
	local prof = geo.profiles and geo.profiles[name]
	local lp = cf[name]:PointToObjectSpace(p)
	if prof then return sdProfile(prof, lp) end
	if name == "Head" then return sdEllipsoid(lp, geo.head) end
	if name == "UpperTorso" then return sdRoundBox(lp, geo.upper, geo.upperRR) end
	return sdRoundBox(lp, geo.lower, geo.lowerRR)
end
QA.partDistance = partDistance
local function coreDistance(geo: Geo, cf: { [string]: CFrame }, p: Vector3, skipHead: boolean?): (number, string)
	local best, which = math.huge, ""
	if not skipHead then
		local d = partDistance(geo, cf, "Head", p)
		if d < best then best, which = d, "Head" end
	end
	local du = partDistance(geo, cf, "UpperTorso", p)
	if du < best then best, which = du, "UpperTorso" end
	local dl = partDistance(geo, cf, "LowerTorso", p)
	if dl < best then best, which = dl, "LowerTorso" end
	return best, which
end

local function handSegment(geo: Geo, cf: { [string]: CFrame }, hand: string): (Vector3, Vector3, number)
	local h = geo.hand[hand]
	local c = cf[hand]
	local axis = c.UpVector * h.len
	return c.Position + axis, c.Position - axis, h.r
end

-- Deepest penetration (radius - distance) of a capsule into a signed-distance field, sampled along the segment.
local function capsuleDepth(a: Vector3, b: Vector3, r: number, sdf: (Vector3) -> (number, string), from: number?): (number, string)
	local best, which = -math.huge, ""
	local u0 = from or 0
	for i = 0, 6 do
		local u = u0 + (1 - u0) * i / 6
		local d, w = sdf(a:Lerp(b, u))
		if r - d > best then best, which = r - d, w end
	end
	return best, which
end

local function limbCapsules(rig: any, geo: Geo, cf: { [string]: CFrame }): { [string]: { a: Vector3, b: Vector3, r: number } }
	local caps = {}
	local function cap(name: string, j0: string, j1: string)
		caps[name] = { a = jointPoint(rig, cf, j0), b = jointPoint(rig, cf, j1), r = geo.limbR[name] }
	end
	cap("LeftUpperArm", "LeftShoulder", "LeftElbow"); cap("LeftLowerArm", "LeftElbow", "LeftWrist")
	cap("RightUpperArm", "RightShoulder", "RightElbow"); cap("RightLowerArm", "RightElbow", "RightWrist")
	cap("LeftUpperLeg", "LeftHip", "LeftKnee"); cap("LeftLowerLeg", "LeftKnee", "LeftAnkle")
	cap("RightUpperLeg", "RightHip", "RightKnee"); cap("RightLowerLeg", "RightKnee", "RightAnkle")
	return caps
end

local function footSegment(geo: Geo, cf: { [string]: CFrame }, foot: string): (Vector3, Vector3, number)
	local half = geo.foot[foot]
	local c = cf[foot]
	local r = math.min(half.X, half.Y) * 0.9
	local len = math.max(half.Z - r, 0.01)
	return c.Position + c.LookVector * len, c.Position - c.LookVector * len, r
end

-- Joint limits -------------------------------------------------------------------------------------------------------

local function relRot(cf: { [string]: CFrame }, parent: string, child: string): CFrame
	return cf[parent].Rotation:Inverse() * cf[child].Rotation
end
-- Twist of a rotation about an axis (radians, signed): swing-twist decomposition.
local function twistAbout(r: CFrame, axis: Vector3): number
	local ax, ang = r:ToAxisAngle()
	local v = ax * math.sin(ang * 0.5)
	local qw = math.cos(ang * 0.5)
	local along = v:Dot(axis)
	local len = math.sqrt(along * along + qw * qw)
	if len < 1e-9 then return 0 end
	return 2 * math.atan2(along / len, qw / len)
end
QA.twistAbout = twistAbout

local function wrapDeg(a: number): number
	local d = math.deg(a)
	while d > 180 do d -= 360 end
	while d < -180 do d += 360 end
	return d
end

-- Returns { [metric] = value } of the joint-limit checks that fail on this pose.
local function jointLimits(cf: { [string]: CFrame }, T: any): { { metric: string, value: number, limit: number, part: string } }
	local out = {}
	local function add(metric: string, value: number, limit: number, part: string) table.insert(out, { metric = metric, value = value, limit = limit, part = part }) end
	for _, side in { "Left", "Right" } do
		-- Elbow: hinge about the upper arm's X axis, flexion positive.
		local e = relRot(cf, side .. "UpperArm", side .. "LowerArm")
		local ex = math.deg(math.atan2(-e.ZVector.Y, e.ZVector.Z))
		local eyz = math.deg(math.acos(math.clamp(e.XVector.X, -1, 1)))
		if ex < -T.hyper then add("limit.elbowHyper", -ex, T.hyper, side .. "Elbow") end
		if ex > T.elbowMax then add("limit.elbowFlex", ex, T.elbowMax, side .. "Elbow") end
		if eyz > 20 then add("limit.elbowOffAxis", eyz, 20, side .. "Elbow") end
		-- Knee: hinge, flexion = negative X rotation.
		local k = relRot(cf, side .. "UpperLeg", side .. "LowerLeg")
		local kx = -math.deg(math.atan2(-k.ZVector.Y, k.ZVector.Z))
		local kyz = math.deg(math.acos(math.clamp(k.XVector.X, -1, 1)))
		if kx < -T.hyper then add("limit.kneeHyper", -kx, T.hyper, side .. "Knee") end
		if kx > T.kneeMax then add("limit.kneeFlex", kx, T.kneeMax, side .. "Knee") end
		if kyz > 20 then add("limit.kneeOffAxis", kyz, 20, side .. "Knee") end
		-- Shoulder and hip twist about the limb's long axis (part Y), relative to the parent.
		local s = relRot(cf, "UpperTorso", side .. "UpperArm")
		local sTw = math.abs(wrapDeg(twistAbout(s, Vector3.yAxis)))
		if sTw > T.shoulderTwist then add("limit.shoulderTwist", sTw, T.shoulderTwist, side .. "Shoulder") end
		local h = relRot(cf, "LowerTorso", side .. "UpperLeg")
		local hTw = math.abs(wrapDeg(twistAbout(h, Vector3.yAxis)))
		if hTw > T.hipTwist then add("limit.hipTwist", hTw, T.hipTwist, side .. "Hip") end
		-- Wrist: any rotation of the hand off the forearm.
		local w = relRot(cf, side .. "LowerArm", side .. "Hand")
		local _, wa = w:ToAxisAngle()
		if math.deg(wa) > T.wrist then add("limit.wrist", math.deg(wa), T.wrist, side .. "Wrist") end
		-- Ankle, from the foot's toe direction in the shin frame (rest: toes along -Z, the shin along +Y): pitch = toes
		-- toward the knee (+, dorsiflexion) or down the shin (-, plantarflexion; -90 = pointed straight down the leg, beyond
		-- = folded backwards); yaw = toes turned sideways; roll = turn about the foot's own long axis (inversion/eversion).
		local a = relRot(cf, side .. "LowerLeg", side .. "Foot")
		local toe = a.LookVector
		local pitch = math.deg(math.atan2(toe.Y, -toe.Z))
		local yaw = math.deg(math.asin(math.clamp(toe.X, -1, 1)))
		local roll = wrapDeg(twistAbout(a, Vector3.zAxis))
		if pitch > T.ankleDorsi then add("limit.ankleDorsi", pitch, T.ankleDorsi, side .. "Ankle") end
		if -pitch > T.anklePlantar then add("limit.anklePlantar", -pitch, T.anklePlantar, side .. "Ankle") end
		if math.abs(roll) > T.ankleRoll then add("limit.ankleRoll", math.abs(roll), T.ankleRoll, side .. "Ankle") end
		if math.abs(yaw) > T.ankleYaw then add("limit.ankleYaw", math.abs(yaw), T.ankleYaw, side .. "Ankle") end
	end
	local n = relRot(cf, "UpperTorso", "Head")
	local _, ny = n:ToEulerAnglesYXZ()
	if math.abs(math.deg(ny)) > T.neckYaw then add("limit.neckYaw", math.abs(math.deg(ny)), T.neckYaw, "Neck") end
	local wst = relRot(cf, "LowerTorso", "UpperTorso")
	local _, wy = wst:ToEulerAnglesYXZ()
	if math.abs(math.deg(wy)) > T.waistTwist then add("limit.waistTwist", math.abs(math.deg(wy)), T.waistTwist, "Waist") end
	return out
end
QA.jointLimits = jointLimits

-- Per-frame record ------------------------------------------------------------------------------------------------------

export type Rec = {
	f: number, key: string?, state: string, move: string?, mf: number, fading: boolean, hitstop: boolean,
	rot: { [string]: CFrame }, pos: { [string]: Vector3 }, jrot: { [string]: CFrame }, bend: { [string]: Vector3? },
	bendDeg: { [string]: number }, tips: { [string]: Vector3 }, lying: boolean,
}

local function bendDirections(rig: any, cf: { [string]: CFrame }): ({ [string]: Vector3? }, { [string]: number })
	local dirs, degs = {}, {}
	for limb, spec in LIMBS do
		local s, e, w = jointPoint(rig, cf, spec[1]), jointPoint(rig, cf, spec[2]), jointPoint(rig, cf, spec[3])
		local u, l = e - s, w - e
		local bend = math.deg(math.acos(math.clamp(u.Unit:Dot(l.Unit), -1, 1)))
		degs[limb] = bend
		local line = w - s
		local dir = line.Unit
		local b = e - (s + dir * (e - s):Dot(dir))
		if b.Magnitude > 1e-4 then dirs[limb] = cf[spec[4]]:VectorToObjectSpace(b.Unit) end
	end
	return dirs, degs
end

local function record(rig: any, cf: { [string]: CFrame }, f: number, slotKey: string?, view: any, fading: boolean, hitstop: boolean): Rec
	local rot, pos, jrot = {}, {}, {}
	for _, n in PARTS do
		rot[n] = cf[n].Rotation
		pos[n] = cf[n].Position
	end
	local hrp = (rig.motors.Root.Part0 :: BasePart).Name
	rot.HumanoidRootPart = cf[hrp].Rotation
	pos.HumanoidRootPart = cf[hrp].Position
	for _, jn in JOINTS do
		local m = rig.motors[jn] :: Motor6D
		jrot[jn] = cf[(m.Part0 :: BasePart).Name].Rotation:Inverse() * cf[(m.Part1 :: BasePart).Name].Rotation
	end
	local bend, bendDeg = bendDirections(rig, cf)
	local tips = {}
	for _, n in TIPS do tips[n] = cf[n].Position end
	local lt = cf.LowerTorso
	return {
		f = f, key = slotKey, state = view.state, move = view.move, mf = view.moveFrame or 0, fading = fading, hitstop = hitstop,
		rot = rot, pos = pos, jrot = jrot, bend = bend, bendDeg = bendDeg, tips = tips,
		lying = math.abs(lt.UpVector.Y) < 0.55,
	}
end

-- Defects ------------------------------------------------------------------------------------------------------------

export type Defect = { fighter: string, case: string, kind: string, frame: number, metric: string, value: number, limit: number, part: string, key: string?, state: string?, move: string?, mf: number?, note: string? }

local function angleDeg(a: CFrame, b: CFrame): number
	local _, ang = (a:Inverse() * b):ToAxisAngle()
	return math.deg(math.abs(ang))
end
QA.angleDeg = angleDeg

local function median(list: { number }): number
	local n = #list
	if n == 0 then return 0 end
	table.sort(list)
	if n % 2 == 1 then return list[(n + 1) // 2] end
	return (list[n // 2] + list[n // 2 + 1]) * 0.5
end

-- Sequence analysis of one subject: pops, transition jumps, bend flips, jitter.
local function analyzeSequence(recs: { Rec }, ctx: any, T: any, out: { Defect }, loop: boolean?)
	local n = #recs
	if n < 3 then return end
	local function defect(rec: Rec, metric: string, value: number, limit: number, part: string, note: string?)
		table.insert(out, { fighter = ctx.fighter, case = ctx.case, kind = ctx.kind, frame = rec.f, metric = metric, value = value, limit = limit, part = part, key = rec.key, state = rec.state, move = rec.move, mf = rec.mf, note = note })
	end
	-- Per-part world rotation change and tip speed series.
	local rotSeries: { [string]: { number } } = {}
	local speedSeries: { [string]: { number } } = {}
	for _, p in PARTS do rotSeries[p] = { 0 } end
	for _, p in TIPS do speedSeries[p] = { 0 } end
	for i = 2, n do
		local a, b = recs[i - 1], recs[i]
		for _, p in PARTS do table.insert(rotSeries[p], angleDeg(a.rot[p], b.rot[p])) end
		for _, p in TIPS do table.insert(speedSeries[p], (b.tips[p] - a.tips[p]).Magnitude) end
	end
	local W = 6
	-- A pop is a SHORT spike: over the absolute threshold, over popRatio x the local median (+-W frames) and at most two
	-- frames wide (frames around it moving at least half as fast). Sustained fast motion (a 5-frame strike, a spin) is
	-- not a pop; transitions are judged separately below.
	local function spikes(series: { [string]: { number } }, absT: number, floorT: number, metric: string)
		for part, s in series do
			local worstI, worstV, worstMed = 0, 0, 0
			for i = 2, n do
				local v = s[i]
				-- (The last two frames cannot be judged: a motion still speeding up when the case ends is not a spike.)
				if v > absT and i <= n - 2 then
					local window = {}
					for j = math.max(2, i - W), math.min(n, i + W) do if j ~= i then table.insert(window, s[j]) end end
					local med = math.max(median(window), floorT)
					local width = 1
					local j = i - 1
					while j >= 2 and s[j] >= 0.5 * v do width += 1; j -= 1 end
					j = i + 1
					while j <= n and s[j] >= 0.5 * v do width += 1; j += 1 end
					if v > T.popRatio * med and width <= 2 then
						-- Report each spike run once (its peak).
						if v > worstV then worstI, worstV, worstMed = i, v, med end
					end
				end
				if worstI > 0 and (i - worstI > 3 or i == n) then
					local r = recs[worstI]
					defect(r, metric, worstV, absT, part, string.format("x%.1f local median", worstV / worstMed))
					worstI, worstV = 0, 0
				end
			end
		end
	end
	spikes(rotSeries, T.popDeg, T.medDegFloor, "pop.rot")
	spikes(speedSeries, T.popSpeed, T.medSpeedFloor, "pop.speed")
	-- Transitions: the frame an animation key changes and the next one (the switch itself; a crossfade's later frames
	-- carry the new clip's own motion, judged by the spike test above). A jump is a joint turning more than
	-- transitionDeg in that frame AND faster than transitionRatio x its own motion just before and just after (a fast
	-- strike chained into another keeps moving fast through the switch: that is speed, not a jump).
	for i = 2, n do
		local a, b = recs[i - 1], recs[i]
		local transition = a.key ~= b.key or (i > 2 and recs[i - 2].key ~= a.key and b.fading)
		if transition then
			local worst, worstJ = 0, ""
			local function around(jn: string): number
				local m = 0
				if i >= 3 then m = math.max(m, angleDeg(recs[i - 2].jrot[jn], recs[i - 1].jrot[jn])) end
				if i + 2 <= n then m = math.max(m, angleDeg(recs[i + 1].jrot[jn], recs[i + 2].jrot[jn])) end
				return m
			end
			for _, jn in JOINTS do
				local d = angleDeg(a.jrot[jn], b.jrot[jn])
				if d > worst and d > T.transitionDeg and d > T.transitionRatio * around(jn) then worst, worstJ = d, jn end
			end
			local root = angleDeg(a.rot.HumanoidRootPart, b.rot.HumanoidRootPart)
			if root > worst and root > T.transitionDeg then worst, worstJ = root, "HumanoidRootPart" end
			if worst > T.transitionDeg then defect(b, "transition.jump", worst, T.transitionDeg, worstJ, tostring(a.key) .. " -> " .. tostring(b.key)) end
		end
	end
	-- Bend-plane flips of bent elbows/knees (directions in the parent part's frame).
	for i = 2, n do
		local a, b = recs[i - 1], recs[i]
		for limb in LIMBS do
			local da, db = a.bend[limb], b.bend[limb]
			if da and db and a.bendDeg[limb] > T.straightDeg and b.bendDeg[limb] > T.straightDeg then
				local d = math.deg(math.acos(math.clamp(da:Dot(db), -1, 1)))
				if d > T.flipDeg then defect(b, "flip", d, T.flipDeg, limb, string.format("bend %.0f->%.0f deg", a.bendDeg[limb], b.bendDeg[limb])) end
			end
		end
	end
	-- Jitter: velocity reversing with visible speed on both sides, twice within jitterWindow frames (>= ~8 Hz shake),
	-- after the case's first frames (the rig settling from its reset pose). Loops only.
	if loop then
		for _, p in PARTS do
			local reversals = {}
			for i = math.max(3, T.jitterSkip), n do
				local r0, r1, r2 = recs[i - 2], recs[i - 1], recs[i]
				local hrp0, hrp1, hrp2 = r0.pos.HumanoidRootPart, r1.pos.HumanoidRootPart, r2.pos.HumanoidRootPart
				local v1 = (r1.pos[p] - hrp1) - (r0.pos[p] - hrp0)
				local v2 = (r2.pos[p] - hrp2) - (r1.pos[p] - hrp1)
				local m1, m2 = v1.Magnitude, v2.Magnitude
				local posRev = m1 > T.jitterPos and m2 > T.jitterPos and v1:Dot(v2) < -0.5 * m1 * m2
				local w1 = (r0.rot[p]:Inverse() * r1.rot[p])
				local w2 = (r1.rot[p]:Inverse() * r2.rot[p])
				local a1, ang1 = w1:ToAxisAngle()
				local a2, ang2 = w2:ToAxisAngle()
				local o1, o2 = r1.rot[p]:VectorToWorldSpace(a1 * ang1), r2.rot[p]:VectorToWorldSpace(a2 * ang2)
				local d1, d2 = math.deg(o1.Magnitude), math.deg(o2.Magnitude)
				local rotRev = d1 > T.jitterDeg and d2 > T.jitterDeg and o1:Dot(o2) < -0.5 * o1.Magnitude * o2.Magnitude
				if posRev or rotRev then table.insert(reversals, i) end
			end
			for k = 3, #reversals do
				-- Oscillation = three reversals within jitterWindow frames (a single contact event — a foot landing, a
				-- heel dropping — turns a part around once or twice, a shake keeps turning it).
				if reversals[k] - reversals[k - 2] <= T.jitterWindow then
					local r = recs[reversals[k]]
					defect(r, "jitter", reversals[k] - reversals[k - 2], T.jitterWindow, p, "zig-zag: 3 reversals")
					break
				end
			end
		end
	end
end
QA.analyzeSequence = analyzeSequence

-- Instantaneous checks of one subject (self-intersection, joint limits) and of the pair (opponent depth, overlap).
local function frameChecks(sub: Staged, cf: { [string]: CFrame }, opp: Staged?, ocf: { [string]: CFrame }?, rec: Rec, ctx: any, T: any, out: { Defect }, opts: any)
	local function defect(metric: string, value: number, limit: number, part: string, note: string?)
		table.insert(out, { fighter = ctx.fighter, case = ctx.case, kind = ctx.kind, frame = rec.f, metric = metric, value = value, limit = limit, part = part, key = rec.key, state = rec.state, move = rec.move, mf = rec.mf, note = note })
	end
	local geo, rig = sub.geo, sub.rig
	if not rec.lying then
		for _, l in jointLimits(cf, T) do defect(l.metric, l.value, l.limit, l.part) end
	else
		-- Lying bodies: only the hinges (a knee or elbow never bends backwards, even on the floor).
		for _, l in jointLimits(cf, T) do
			if string.find(l.metric, "Hyper", 1, true) then defect(l.metric, l.value, l.limit, l.part) end
		end
	end
	-- Hands vs own head / torso.
	for _, hand in { "LeftHand", "RightHand" } do
		local a, b, r = handSegment(geo, cf, hand)
		local dHead = capsuleDepth(a, b, r, function(p) return partDistance(geo, cf, "Head", p), "Head" end)
		ctx.handHead[hand] = math.max(ctx.handHead[hand] or -math.huge, dHead)
		if dHead > T.handHeadDepth then defect("self.handHead", dHead, T.handHeadDepth, hand, if geo.hand[hand].gloved then "glove" else "hand") end
		local dTorso, which = capsuleDepth(a, b, r, function(p) return coreDistance(geo, cf, p, true) end)
		if dTorso > T.selfDepth then defect("self.handTorso", dTorso, T.selfDepth, hand, which) end
	end
	-- Arms through the torso: the limb's CENTRELINE inside the body (a forearm or upper arm pressed against the chest
	-- overlaps the rigid hulls by part of its radius, like soft tissue; the centreline inside = visibly sunk in). Upper
	-- arm from 50% below the shoulder (the shoulder half always runs under the deltoid), the whole forearm.
	local caps = limbCapsules(rig, geo, cf)
	for _, n in { "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm" } do
		local c = caps[n]
		local from = if string.find(n, "Upper", 1, true) then 0.5 else 0
		local d, which = capsuleDepth(c.a, c.b, 0, function(p) return coreDistance(geo, cf, p, false) end, from)
		if d > T.selfDepth then defect("self.armTorso", d, T.selfDepth, n, which) end
	end
	-- Legs through each other (thighs from 35% below the hip).
	local function legPart(name: string): (Vector3, Vector3, number)
		local c = caps[name]
		if string.find(name, "Upper", 1, true) then return c.a:Lerp(c.b, 0.35), c.b, c.r end
		return c.a, c.b, c.r
	end
	for _, pair in { { "LeftUpperLeg", "RightUpperLeg" }, { "LeftLowerLeg", "RightLowerLeg" }, { "LeftUpperLeg", "RightLowerLeg" }, { "LeftLowerLeg", "RightUpperLeg" } } do
		local a1, b1, r1 = legPart(pair[1])
		local a2, b2, r2 = legPart(pair[2])
		local d = r1 + r2 - segSegDistance(a1, b1, a2, b2)
		if d > T.selfDepth then defect("self.legs", d, T.selfDepth, pair[1] .. "/" .. pair[2]) end
	end
	-- Opponent.
	if opp and ocf then
		local ogeo = opp.geo
		local function oppCore(p: Vector3): (number, string) return coreDistance(ogeo, ocf, p, false) end
		if opts.strikeLimb then
			local limb = opts.strikeLimb :: string
			local a, b, r
			if limb == "LeftHand" or limb == "RightHand" then a, b, r = handSegment(geo, cf, limb) else a, b, r = footSegment(geo, cf, limb) end
			-- Depth of the striking hand/foot — and the forearm/shin behind it (a fist that went through a head leaves its
			-- forearm inside) — into the opponent's head and torso (its guard arms are fair contact).
			local d, which = capsuleDepth(a, b, r, oppCore)
			local mid = caps[if limb == "LeftHand" then "LeftLowerArm" elseif limb == "RightHand" then "RightLowerArm" elseif limb == "LeftFoot" then "LeftLowerLeg" else "RightLowerLeg"]
			if mid then
				local dm, wm = capsuleDepth(mid.a, mid.b, mid.r, oppCore)
				if dm > d then d, which = dm, wm end
			end
			if d > (ctx.strikeWorst or -math.huge) then ctx.strikeWorst, ctx.strikeWorstFrame, ctx.strikeWorstPart = d, rec.f, which end
			if opts.contactFrames and opts.contactFrames[rec.mf] and rec.move then
				if d > (ctx.contactWorst or -math.huge) then ctx.contactWorst = d end
				if d > T.strikeDepth then defect("opp.strike", d, T.strikeDepth, limb, which) end
			elseif d > T.strikeDepth and rec.move then
				defect("opp.through", d, T.strikeDepth, limb, which)
			end
		end
		if not opts.throw then
			-- Torso cores as vertical capsules (pelvis bottom to chest top) and the heads as spheres.
			local function core(c: { [string]: CFrame }, g: Geo): (Vector3, Vector3, number)
				local r = math.min(g.upper.X, g.upper.Z) * 0.95
				return c.LowerTorso.Position - c.LowerTorso.UpVector * math.max(g.lower.Y - r, 0), c.UpperTorso.Position + c.UpperTorso.UpVector * math.max(g.upper.Y - r, 0), r
			end
			local a1, b1, r1 = core(cf, geo)
			local a2, b2, r2 = core(ocf, ogeo)
			local d = r1 + r2 - segSegDistance(a1, b1, a2, b2)
			if d > T.bodyOverlap then defect("opp.body", d, T.bodyOverlap, "Torso") end
			local hr1 = (geo.head.X + geo.head.Z) * 0.5
			local hr2 = (ogeo.head.X + ogeo.head.Z) * 0.5
			local dh = hr1 + hr2 - (cf.Head.Position - ocf.Head.Position).Magnitude
			if dh > T.bodyOverlap then defect("opp.body", dh, T.bodyOverlap, "Head") end
		end
	end
end
QA.frameChecks = frameChecks

-- Playback -----------------------------------------------------------------------------------------------------------

-- The presenter's posing path (MotionPlayer.presentFrame); a copy of the round-5 presenter for runtimes without it, so
-- the same harness measures before/after builds.
local function present(entries: { any }, frame: any, origin: Vector3)
	if MotionPlayer.presentFrame then return MotionPlayer.presentFrame(entries, frame, origin, Config) end
	local poses = {}
	for i = 1, 2 do
		local e = entries[i]
		local pose = MotionPlayer.sample(Config, e.view, frame, e.slot)
		local forward = e.view.facing.Unit
		local right = forward:Cross(Vector3.yAxis).Unit
		local o = pose.rootOffset
		local center = Vector3.new(origin.X + e.view.pos.X, origin.Y, origin.Z + e.view.pos.Z) + Vector3.new(0, e.rig.rootHeight + math.max(0, e.view.pos.Y), 0) + right * o.X + Vector3.yAxis * o.Y + forward * o.Z
		e.root.CFrame = CFrame.lookAt(center, center + forward)
		MotionPlayer.apply(e.rig, pose, origin.Y)
		poses[i] = pose
	end
	for pass = 1, 2 do
		for i = 1, 2 do
			local e = entries[i]
			local throw = e.view.throw
			if type(throw) == "table" and (throw.role ~= "Defender") == (pass == 1) then
				MotionPlayer.applyGrips(e.rig, poses[i], e.view, frame, e.slot, entries[3 - i].rig, origin.Y)
			end
		end
	end
	return poses
end
QA.present = present

local function resetRig(rig: any)
	if MotionPlayer.resetRig then MotionPlayer.resetRig(rig) else table.clear(rig.footLock) end
end
QA.resetRig = resetRig

-- A case drives both slots: at(f) -> { views = { v1, v2 }, hitstop, phase, winner, roundOverHold }.
export type Case = {
	label: string, kind: string, ids: { string }, n: number, at: (number) -> any, subjects: { number }, loop: boolean?,
	strike: { slot: number, limb: string, contact: { [number]: boolean } }?, throw: boolean?, meta: any?,
}

local function baseView(state: string, extra: { [string]: any }?): { [string]: any }
	local v: { [string]: any } = { pos = Vector3.zero, facing = Vector3.xAxis, state = state, move = nil, moveFrame = 0, walkPhase = 0, stun = 0, crouched = false, moveX = 0, guard = nil }
	if extra then for k, value in extra do v[k] = value end end
	return v
end
QA.view = baseView

-- Plays a case; returns its defects and per-subject summaries.
function QA.play(rigs: { [string]: Staged }, case: Case, opts: any?): ({ Defect }, any)
	local o = opts or {}
	local T = o.T or QA.T
	local out: { Defect } = {}
	local slots = { 1, 2 }
	local staged: { Staged } = {}
	staged[1] = rigs[case.ids[1]] :: Staged
	staged[2] = rigs[if case.ids[2] == case.ids[1] then case.ids[2] .. "#2" else case.ids[2]] :: Staged
	for i = 1, 2 do
		if not staged[i] then error("MotionQA: rig not staged " .. tostring(case.ids[i])) end
		MotionPlayer.reset(slots[i])
		resetRig(staged[i].rig)
	end
	local recs: { { Rec } } = { {}, {} }
	local ctxs = {}
	for i = 1, 2 do
		ctxs[i] = { fighter = staged[i].id, case = case.label, kind = case.kind, handHead = {} }
	end
	local now = 0
	local t0 = os.clock()
	for f = 1, case.n do
		local info = case.at(f)
		now += 1 / 60
		local views = info.views
		for i = 1, 2 do
			local v = views[i]
			local r = staged[i]
			v.characterId = r.id
			v.rootHeight = r.rig.rootHeight
			v.legLength = r.rig.legLength
			v.aimHeights = r.aim
		end
		local frame = { now = now, dt = 1 / 60, hitstop = info.hitstop or 0, phase = info.phase or "Fight", winner = info.winner or 0, fighters = views, renderFrame = info.renderFrame, entry = info.entry }
		if info.roundOverHold then
			for i = 1, 2 do
				local st = MotionPlayer._slotState(slots[i])
				if st then st.roundOverSince = os.clock() - 10 end
			end
		end
		local entries = {}
		for i = 1, 2 do entries[i] = { rig = staged[i].rig, root = staged[i].root, view = views[i], slot = slots[i] } end
		present(entries, frame, QA.ORIGIN)
		local cfs = { posed(staged[1].rig), posed(staged[2].rig) }
		for _, s in case.subjects do
			local st = MotionPlayer._slotState(slots[s])
			local fading = st ~= nil and st.fadeFrom ~= nil
			local rec = record(staged[s].rig, cfs[s], f, st and st.key, views[s], fading, (info.hitstop or 0) > 0)
			table.insert(recs[s], rec)
			local strike = case.strike
			frameChecks(staged[s], cfs[s], staged[3 - s], cfs[3 - s], rec, ctxs[s], T, out, {
				strikeLimb = if strike and strike.slot == s then strike.limb else nil,
				contactFrames = if strike and strike.slot == s then strike.contact else nil,
				throw = case.throw or views[1].state == "Throw" or views[2].state == "Throw",
			})
		end
		if o.yieldEvery and f % o.yieldEvery == 0 then task.wait() end
	end
	for _, s in case.subjects do analyzeSequence(recs[s], ctxs[s], T, out, case.loop) end
	local summary = { ms = (os.clock() - t0) * 1000, frames = case.n, handHead = { ctxs[1].handHead, ctxs[2].handHead }, strike = nil :: any, recs = if o.keepRecs then recs else nil }
	for _, s in case.subjects do
		if ctxs[s].strikeWorst then summary.strike = { depth = ctxs[s].strikeWorst, frame = ctxs[s].strikeWorstFrame, part = ctxs[s].strikeWorstPart, contact = ctxs[s].contactWorst } end
	end
	return out, summary
end

-- Cases --------------------------------------------------------------------------------------------------------------

local SEP = (Config :: any).Separation or 2.6

local function stats(id: string): any return Roster.get(id).stats end
local function easeOut(t: number): number local x = math.clamp(t, 0, 1); return 1 - (1 - x) * (1 - x) end
local function easeInOut(t: number): number local x = math.clamp(t, 0, 1); return x * x * (3 - 2 * x) end

local function partnerOf(id: string): string return if id == "Kael" then "Sierra" else "Kael" end
QA.partnerOf = partnerOf

local stamp = 0
local function newHit(kind: string, height: string, tier: string, counter: boolean?, side: number?): any
	stamp += 1
	return { kind = kind, height = height, tier = tier, counter = counter == true, frame = stamp, move = "QA", limb = "RearArm", side = side or 1 }
end

-- A sequence builder: segments of views for slot 1 (the subject) with an idle partner in slot 2 at `dist`.
local function sequence(id: string, partner: string, dist: number, segments: { any }, label: string, kind: string, loop: boolean?): Case
	local total = 0
	for _, s in segments do total += s.n end
	local foe = baseView("Idle", { guard = "Stand", pos = Vector3.new(dist, 0, 0), facing = -Vector3.xAxis })
	return {
		label = label, kind = kind, ids = { id, partner }, n = total, subjects = { 1 }, loop = loop,
		at = function(f: number)
			local acc = 0
			for _, s in segments do
				if f <= acc + s.n then
					local v, extra = s.view(f - acc, f)
					local info = { views = { v, table.clone(foe) }, hitstop = if s.hitstop then s.hitstop(f - acc) else 0 }
					if extra then for k, x in extra do info[k] = x end end
					return info
				end
				acc += s.n
			end
			return { views = { baseView("Idle", { guard = "Stand" }), table.clone(foe) } }
		end,
	}
end
QA.sequence = sequence

local function idleSeg(n: number, extra: { [string]: any }?): any
	return { n = n, view = function() return baseView("Idle", extra or { guard = "Stand" }) end }
end

function QA.stateCases(id: string): { Case }
	local partner = partnerOf(id)
	local s = stats(id)
	local cases: { Case } = {}
	local function add(c: Case) table.insert(cases, c) end
	local dist = 4.0
	add(sequence(id, partner, dist, { idleSeg(150) }, "idle", "state", true))
	-- Walks: the sim moves the root at the walk speed and advances walkPhase 9 rad/s.
	local function walkSeg(state: string, n: number, x0: number?): any
		local speed = if state == "Walk" then (s.walkSpeed or 5) else -(s.backSpeed or 4)
		local start = x0 or 0
		return { n = n, endX = start + speed * n / 60, view = function(k: number) return baseView(state, { pos = Vector3.new(start + speed * k / 60, 0, 0), walkPhase = (9 * k / 60) % (math.pi * 2), moveX = if speed > 0 then 1 else -1, guard = if state == "Backwalk" then "Stand" else nil }) end }
	end
	add(sequence(id, partner, 30, { walkSeg("Walk", 150) }, "walk", "state", true))
	add(sequence(id, partner, 30, { walkSeg("Backwalk", 150) }, "backwalk", "state", true))
	local w1 = walkSeg("Walk", 40)
	local w2 = walkSeg("Backwalk", 40, w1.endX)
	add(sequence(id, partner, 30, { idleSeg(20), w1, idleSeg(30, { guard = "Stand", pos = Vector3.new(w1.endX, 0, 0) }), w2, idleSeg(30, { guard = "Stand", pos = Vector3.new(w2.endX, 0, 0) }) }, "idle>walk>idle>backwalk>idle", "transition"))
	add(sequence(id, partner, dist, { idleSeg(20), { n = 70, view = function(k: number) return baseView("Crouch", { crouched = true, guard = "Crouch", crouchFrames = k }) end }, idleSeg(40) }, "idle>crouch>idle", "transition"))
	-- Dashes (ease-out travel; backdash travels over its first 14 frames).
	local function dashSeg(back: boolean): any
		local total = if back then (s.backdashFrames or 18) else (s.dashFrames or 14)
		local distance = if back then (s.backdashDistance or 3) else (s.dashDistance or 3)
		local moveFrames = if back then math.min(14, total) else total
		return { n = total, view = function(k: number)
			local x = distance * easeOut(math.min(k, moveFrames) / moveFrames) * (if back then -1 else 1)
			return baseView(if back then "Backdash" else "Dash", { pos = Vector3.new(x, 0, 0), dashFrame = k, dashTotal = total, dashDirection = if back then -1 else 1 })
		end, endX = distance * (if back then -1 else 1) }
	end
	local dseg = dashSeg(false)
	add(sequence(id, partner, 8, { idleSeg(20), dseg, idleSeg(30, { guard = "Stand", pos = Vector3.new(dseg.endX, 0, 0) }) }, "idle>dash>idle", "transition"))
	local bseg = dashSeg(true)
	add(sequence(id, partner, dist, { idleSeg(20), bseg, idleSeg(30, { guard = "Stand", pos = Vector3.new(bseg.endX, 0, 0) }) }, "idle>backdash>idle", "transition"))
	-- Sidesteps: an eased arc around the partner at constant distance, facing it.
	for _, dir in { 1, -1 } do
		local arc = s.sidestepArc or 1.8
		local endPos = Vector3.zero
		local seg = { n = 22, view = function(k: number)
			local u = easeInOut(math.min(k, 16) / 16)
			local theta = arc * u / dist
			-- Arc about the partner at (dist, 0, 0): stepDir +1 = the fighter's own left (facing +X, left = -Z).
			local rel = Vector3.new(-dist * math.cos(theta), 0, -dir * dist * math.sin(theta))
			local p = Vector3.new(dist, 0, 0) + rel
			endPos = p
			local facing = (Vector3.new(dist, 0, 0) - p).Unit
			return baseView("Sidestep", { pos = p, facing = facing, stepDir = dir, stepFrame = k })
		end }
		add(sequence(id, partner, dist, { idleSeg(20), seg, { n = 30, view = function() return baseView("Idle", { guard = "Stand", pos = endPos, facing = (Vector3.new(dist, 0, 0) - endPos).Unit }) end } }, if dir > 0 then "idle>sidestepL>idle" else "idle>sidestepR>idle", "transition"))
	end
	-- Block and blockstun (standing and crouching), hit reactions.
	local function stunSeg(state: string, hit: any, stunFrames: number, hs: number, extra: { [string]: any }?): any
		return { n = stunFrames + hs, hitstop = function(k: number) return if k <= hs then hs - k + 1 else 0 end, view = function(k: number)
			local v = baseView(state, { lastHit = hit, stun = math.max(1, stunFrames - math.max(0, k - hs)) })
			if extra then for key, x in extra do v[key] = x end end
			return v
		end }
	end
	add(sequence(id, partner, dist, { idleSeg(20), stunSeg("Blockstun", newHit("Block", "Mid", "Medium"), 12, 3, { guard = "Stand" }), idleSeg(30) }, "idle>blockstun>idle", "transition"))
	add(sequence(id, partner, dist, { idleSeg(20, { guard = "Crouch", crouched = true }), stunSeg("Blockstun", newHit("Block", "Low", "Medium"), 12, 3, { guard = "Crouch", crouched = true }), idleSeg(30, { guard = "Crouch", crouched = true }) }, "crouch>crouchBlockstun>crouch", "transition"))
	for _, spec in { { "High", "Light", false }, { "Mid", "Medium", false }, { "Low", "Medium", false }, { "Mid", "Medium", true }, { "High", "Heavy", false } } do
		local hit = newHit(if spec[3] then "Counter" else "Hit", spec[1], spec[2], spec[3])
		local label = "idle>hit" .. spec[1] .. (if spec[3] then "Counter" else spec[2]) .. ">idle"
		add(sequence(id, partner, dist, { idleSeg(20), stunSeg("Hitstun", hit, if spec[2] == "Heavy" or spec[3] then 24 else 18, if spec[2] == "Heavy" then 8 elseif spec[3] then 8 else 6), idleSeg(30) }, label, "transition"))
	end
	add(sequence(id, partner, dist, { idleSeg(20), stunSeg("Stagger", newHit("Parry", "Mid", "Medium"), 26, 6), idleSeg(30) }, "idle>stagger>idle", "transition"))
	-- Launch -> juggle -> fall -> Landing -> getups.
	local g = (Config :: any).Gravity or 44
	local function airSeg(knockdown: string, juggle: boolean): any
		local y, vy, frames, hits = 0.05, (Config :: any).LaunchVelocity or 16, 0, 0
		local hit = newHit("Hit", "Mid", "Launch")
		local locked = false
		local list = {}
		while true do
			frames += 1
			vy -= g / 60
			y += vy / 60
			if juggle and frames == 30 then
				hits += 1; hit = newHit("Hit", "Mid", "Medium"); vy = math.max(vy, 7.5)
			end
			if juggle and frames == 50 then
				hits += 1; hit = newHit("Hit", "High", "Heavy"); locked = true; vy = math.min(vy, 2)
			end
			if y <= 0 then break end
			table.insert(list, { y = y, vy = vy, frames = frames, hits = hits, hit = hit, locked = locked })
			if frames > 120 then break end
		end
		return { n = #list, list = list, view = function(k: number)
			local a = list[k]
			return baseView("Airborne", { pos = Vector3.new(0, a.y, 0), velocityY = a.vy, airFrames = a.frames, airHits = a.hits, lastHit = a.hit, knockdown = if a.locked or not juggle then knockdown else nil })
		end }
	end
	local function landingSeg(knockdown: string, kind: string?): any
		local L = (Config :: any).LandingFrames or 34
		return { n = L, view = function(k: number) return baseView("Landing", { knockdown = knockdown, stun = L - k, getupKind = if k >= 12 then kind else nil, rollDir = 1 }) end }
	end
	local function getupSeg(knockdown: string, kind: string, rollDir: number?): any
		local G = ((Config :: any).GetupFrames or 26) + (if kind ~= "Stand" then ((Config :: any).RollFrames or 10) else 0)
		local R = (Config :: any).RollDistance or 2.2
		local endPos = Vector3.zero
		return { n = G, view = function(k: number)
			local elapsed = k
			local travel = R * easeOut(math.min(elapsed, 10) / 10)
			local p = Vector3.zero
			if kind == "BackRoll" then p = Vector3.new(-travel, 0, 0) elseif kind == "SideRoll" then p = Vector3.new(0, 0, -(rollDir or 1) * travel) end
			endPos = p
			return baseView("Getup", { knockdown = knockdown, stun = G - k + 1, getupKind = kind, rollDir = rollDir or 1, pos = p })
		end, endPos = function() return endPos end }
	end
	for _, kd in { "FaceUp", "FaceDown" } do
		for _, kind in { "Stand", "BackRoll", "SideRoll" } do
			for _, rd in (if kind == "SideRoll" then { 1, -1 } else { 1 }) do
				local gseg = getupSeg(kd, kind, rd)
				local hitSeg = { n = 1, hitstop = function() return 8 end, view = function() return baseView("Landing", { knockdown = kd, stun = 34, lastHit = newHit("Hit", "Mid", "Heavy") }) end }
				local segments = { idleSeg(20), hitSeg, landingSeg(kd, if kind == "Stand" then nil else kind), gseg, { n = 40, view = function() return baseView("Idle", { guard = "Stand", pos = gseg.endPos() }) end } }
				add(sequence(id, partner, dist, segments, string.format("knockdown%s>%s%s>idle", kd, kind, if kind == "SideRoll" then (if rd > 0 then "L" else "R") else ""), "transition"))
			end
		end
	end
	add(sequence(id, partner, dist, { idleSeg(10), airSeg("FaceUp", true), landingSeg("FaceUp", nil), getupSeg("FaceUp", "Stand"), idleSeg(30) }, "launch>juggle>landing>getup>idle", "transition"))
	add(sequence(id, partner, dist, { idleSeg(10), airSeg("FaceDown", false), landingSeg("FaceDown", nil), getupSeg("FaceDown", "Stand"), idleSeg(30) }, "launch>fallFaceDown>getup>idle", "transition"))
	-- KO (grounded, face up and down) and round end.
	for _, kd in { "FaceUp", "FaceDown" } do
		-- One hit for the whole segment (a new hit object every frame read as a new hit every frame).
		local koHit = newHit("Hit", "High", "Heavy")
		add(sequence(id, partner, dist, { idleSeg(20), { n = 90, hitstop = function(k: number) return if k <= 16 then 17 - k else 0 end, view = function() return baseView("KO", { knockdown = kd, lastHit = koHit }) end } }, "idle>KO" .. kd, "transition"))
	end
	add(sequence(id, partner, dist, { idleSeg(30), { n = 150, view = function() return baseView("Idle", { guard = "Stand" }) end } }, "idle>victory", "transition"))
	add(sequence(id, partner, dist, { idleSeg(30), { n = 150, view = function() return baseView("Idle", { guard = "Stand" }) end } }, "idle>defeat", "transition"))
	-- Round end: slot 1 wins (victory) / loses standing (defeat). The phase is applied by the case wrapper below.
	local vic = cases[#cases - 1]
	local def = cases[#cases]
	for _, pair in { { vic, 1 }, { def, 2 } } do
		local c, winner = pair[1], pair[2]
		local inner = c.at
		c.at = function(f: number)
			local info = inner(f)
			if f > 30 then
				info.phase = "RoundOver"
				info.winner = winner
				info.roundOverHold = true
			end
			return info
		end
	end
	return cases
end

-- Move cases: idle -> move -> idle against an idle partner. range "max": the partner stands where the move connects
-- after the sim's full advance (root distance = range); "close": at Separation (keepApart cancels the advance).
function QA.moveCase(id: string, key: string, range: string, partner: string?): Case?
	local m = Roster.getMove(id, key)
	if not m or m.height == "Throw" then return nil end
	local clip = ClipLibrary.forMove(id, key)
	local total = m.startup + m.active + m.recovery
	local crouching = m.crouching == true
	local advance = m.advance or 0
	local reach = m.range or 4
	local dist = if range == "close" then SEP + 0.05 else reach + advance
	local step = advance / math.max(m.startup, 1)
	local limbMap = { LeadArm = "LeftHand", RearArm = "RightHand", LeadLeg = "LeftFoot", RearLeg = "RightFoot" }
	local limb = (clip and clip.tags and type(clip.tags.limb) == "string" and clip.tags.limb) or limbMap[m.limb or ""] or "RightHand"
	local contact = {}
	for f = m.startup + 1, m.startup + m.active do contact[f] = true end
	local LEAD, TAIL = 24, 40
	local p = partner or partnerOf(id)
	local endX = 0
	local c = sequence(id, p, dist, {
		{ n = LEAD, view = function() return baseView(if crouching then "Crouch" else "Idle", { guard = if crouching then "Crouch" else "Stand", crouched = crouching }) end },
		{ n = total, view = function(k: number)
			local state = if k <= m.startup then "Startup" elseif k <= m.startup + m.active then "Active" else "Recovery"
			local x = math.min(step * math.min(k - 1, m.startup), math.max(0, dist - SEP))
			endX = x
			return baseView(state, { move = key, moveFrame = k, stringIndex = 1, crouched = crouching, pos = Vector3.new(x, 0, 0) })
		end },
		{ n = TAIL, view = function() return baseView("Idle", { guard = "Stand", pos = Vector3.new(endX, 0, 0) }) end },
	}, string.format("%s:%s", key, range), "move")
	c.strike = { slot = 1, limb = limb, contact = contact }
	c.meta = { move = key, startup = m.startup, active = m.active, recovery = m.recovery, lead = LEAD, clip = clip and clip.name }
	return c
end

-- String chains: the follow-up starts on the first recovery frame of the previous hit (CombatSim chain rule).
function QA.stringCase(id: string, keys: { string }, partner: string?): Case
	local p = partner or partnerOf(id)
	local first = Roster.getMove(id, keys[1])
	local dist = (first.range or 4) + (first.advance or 0)
	local segs: { any } = { idleSeg(24) }
	local x = 0
	local contact = {}
	for i, key in keys do
		local m = Roster.getMove(id, key)
		local last = i == #keys
		local n = if last then m.startup + m.active + m.recovery else m.startup + m.active
		local step = (m.advance or 0) / math.max(m.startup, 1)
		local x0 = x
		table.insert(segs, { n = n, view = function(k: number)
			local state = if k <= m.startup then "Startup" elseif k <= m.startup + m.active then "Active" else "Recovery"
			x = x0 + math.min(step * math.min(k - 1, m.startup), math.max(0, dist - SEP - x0))
			return baseView(state, { move = key, moveFrame = k, stringIndex = i, crouched = m.crouching == true, pos = Vector3.new(x, 0, 0) })
		end })
		x = x0 + math.min((m.advance or 0), math.max(0, dist - SEP - x0))
	end
	local endX = x
	table.insert(segs, { n = 40, view = function() return baseView("Idle", { guard = "Stand", pos = Vector3.new(endX, 0, 0) }) end })
	local c = sequence(id, p, dist, segs, "string:" .. table.concat(keys, ">"), "transition")
	return c
end

-- Transition cases built from moves: a move interrupted by a hit, blockstun into a counter attack, dash and sidestep
-- into attacks, a whiffed move into a block.
function QA.transitionCases(id: string): { Case }
	local partner = partnerOf(id)
	local cases: { Case } = {}
	local def = Roster.get(id)
	local function firstKey(pred: (any) -> boolean): string?
		local keys = {}
		for key, m in def.moves do if pred(m) then table.insert(keys, key) end end
		table.sort(keys)
		return keys[1]
	end
	local jab = firstKey(function(m) return m.notation == "1" end) or "Jab"
	local heavy = firstKey(function(m) return m.notation == "2" end) or jab
	local dist = 3.4
	-- Move -> hit (counter hit during startup).
	local mj = Roster.getMove(id, heavy)
	local cut = math.max(2, math.floor(mj.startup * 0.7))
	local counterHit = newHit("Counter", "High", "Medium", true)
	table.insert(cases, sequence(id, partner, dist, {
		idleSeg(20),
		{ n = cut, view = function(k: number) return baseView("Startup", { move = heavy, moveFrame = k, stringIndex = 1 }) end },
		{ n = 30, hitstop = function(k: number) return if k <= 8 then 9 - k else 0 end, view = function(k: number) return baseView("Hitstun", { lastHit = counterHit, stun = math.max(1, 22 - math.max(0, k - 8)) }) end },
		idleSeg(30),
	}, string.format("move(%s)>counterHit>idle", heavy), "transition"))
	-- Blockstun -> counter attack (jab on the first free frame).
	local mjab = Roster.getMove(id, jab)
	local blockHit = newHit("Block", "High", "Medium")
	table.insert(cases, sequence(id, partner, dist, {
		idleSeg(20),
		{ n = 15, hitstop = function(k: number) return if k <= 3 then 4 - k else 0 end, view = function(k: number) return baseView("Blockstun", { lastHit = blockHit, stun = math.max(1, 12 - math.max(0, k - 3)), guard = "Stand" }) end },
		{ n = mjab.startup + mjab.active + mjab.recovery, view = function(k: number) return baseView(if k <= mjab.startup then "Startup" elseif k <= mjab.startup + mjab.active then "Active" else "Recovery", { move = jab, moveFrame = k, stringIndex = 1 }) end },
		idleSeg(30),
	}, string.format("blockstun>%s>idle", jab), "transition"))
	-- Dash -> f,f attack (or the jab) from dash frame 3; sidestep -> ss attack (or the jab) from step frame 8.
	local ff = firstKey(function(m) return type(m.notation) == "string" and string.sub(m.notation, 1, 3) == "f,f" end) or jab
	local ss = firstKey(function(m) return type(m.notation) == "string" and string.sub(m.notation, 1, 3) == "ss+" end) or jab
	local s = stats(id)
	local dashTotal, dashDist = s.dashFrames or 14, s.dashDistance or 3
	local mff = Roster.getMove(id, ff)
	local dashX = 0
	table.insert(cases, sequence(id, partner, 7, {
		idleSeg(20),
		{ n = 5, view = function(k: number) dashX = dashDist * easeOut(k / dashTotal); return baseView("Dash", { pos = Vector3.new(dashX, 0, 0), dashFrame = k, dashTotal = dashTotal, dashDirection = 1 }) end },
		{ n = mff.startup + mff.active + mff.recovery, view = function(k: number)
			local x = dashX + (mff.advance or 0) * math.min(k - 1, mff.startup) / math.max(mff.startup, 1)
			return baseView(if k <= mff.startup then "Startup" elseif k <= mff.startup + mff.active then "Active" else "Recovery", { move = ff, moveFrame = k, stringIndex = 1, pos = Vector3.new(x, 0, 0) })
		end },
		{ n = 30, view = function() return baseView("Idle", { guard = "Stand", pos = Vector3.new(dashX + (mff.advance or 0), 0, 0) }) end },
	}, string.format("dash>%s>idle", ff), "transition"))
	local mss = Roster.getMove(id, ss)
	local arc = s.sidestepArc or 1.8
	local ssEnd = Vector3.zero
	local sdist = 4
	table.insert(cases, sequence(id, partner, sdist, {
		idleSeg(20),
		{ n = 9, view = function(k: number)
			local theta = arc * easeInOut(k / 16) / sdist
			local pp = Vector3.new(sdist, 0, 0) + Vector3.new(-sdist * math.cos(theta), 0, -sdist * math.sin(theta))
			ssEnd = pp
			return baseView("Sidestep", { pos = pp, facing = (Vector3.new(sdist, 0, 0) - pp).Unit, stepDir = 1, stepFrame = k })
		end },
		{ n = mss.startup + mss.active + mss.recovery, view = function(k: number)
			local facing = (Vector3.new(sdist, 0, 0) - ssEnd).Unit
			local x = ssEnd + facing * (mss.advance or 0) * math.min(k - 1, mss.startup) / math.max(mss.startup, 1)
			return baseView(if k <= mss.startup then "Startup" elseif k <= mss.startup + mss.active then "Active" else "Recovery", { move = ss, moveFrame = k, stringIndex = 1, pos = x, facing = facing })
		end },
		{ n = 30, view = function() local facing = (Vector3.new(sdist, 0, 0) - ssEnd).Unit; return baseView("Idle", { guard = "Stand", pos = ssEnd + facing * (mss.advance or 0), facing = facing }) end },
	}, string.format("sidestep>%s>idle", ss), "transition"))
	-- Strings (every chain that starts from a starter).
	local chains = {}
	for key, m in def.moves do
		if m.chainFrom ~= nil then chains[key] = m.chainFrom end
	end
	for key in chains do
		local path = { key }
		local cur = chains[key]
		while cur do
			table.insert(path, 1, cur)
			cur = chains[cur]
		end
		-- Only full chains (longest path ending at a key no other chain extends).
		local extended = false
		for _, from in chains do if from == key then extended = true end end
		if not extended then table.insert(cases, QA.stringCase(id, path, partner)) end
	end
	return cases
end

-- Throw cases: the grab connects, both roles play the throw (hitstop on the grab and on the impact, like CombatSim),
-- then the sim pushes them apart (0.45 studs each; 0.6 after a break) and the thrown fighter lies (Landing) and gets
-- up. Broken version: broken at the middle of the break window.
function QA.throwCases(id: string, defender: string?): { Case }
	local d = defender or partnerOf(id)
	local cases: { Case } = {}
	local def = Roster.get(id)
	local keys = {}
	for key, m in def.moves do if m.height == "Throw" then table.insert(keys, key) end end
	table.sort(keys)
	local BREAK = (Config :: any).ThrowBreakFrames or 16
	local HS = ((Config :: any).Hitstop and (Config :: any).Hitstop.Throw) or 8
	local L = (Config :: any).LandingFrames or 34
	local G = (Config :: any).GetupFrames or 26
	for _, key in keys do
		local m = Roster.getMove(id, key)
		local duration = m.duration or 46
		local impactFrame = m.impactFrame or 30
		for _, broken in { false, true } do
			local breakAt = if broken then math.max(2, math.floor((m.breakWindow or 20) * 0.5)) else nil
			local n = if broken then (breakAt :: number) + BREAK else duration
			local LEAD, GRAB, TAIL = 20, m.startup + 1, (if broken then 40 else L + G + 30)
			local throwDist = 2.9
			-- Timeline of throw frames (with the hitstop holds): 0 x HS (grab), 1..n (impact held HS frames, or the break).
			local timeline: { { tf: number, hs: number } } = {}
			for k = 1, HS do table.insert(timeline, { tf = 0, hs = HS - k + 1 }) end
			for tf = 1, n do
				table.insert(timeline, { tf = tf, hs = 0 })
				local hold = (not broken and tf == impactFrame) or (broken and tf == breakAt)
				if hold then for k = 1, HS do table.insert(timeline, { tf = tf, hs = HS - k + 1 }) end end
			end
			local c: Case = {
				label = string.format("throw:%s.%s%s", id, key, if broken then ":broken" else ""), kind = "throw", ids = { id, d }, n = LEAD + GRAB + #timeline + TAIL, subjects = { 1, 2 }, throw = true,
				at = function(f: number)
					local a = baseView("Idle", { guard = "Stand", pos = Vector3.zero, facing = Vector3.xAxis })
					local b = baseView("Idle", { guard = "Stand", pos = Vector3.new(throwDist, 0, 0), facing = -Vector3.xAxis })
					local hs = 0
					if f > LEAD and f <= LEAD + GRAB then
						local k = f - LEAD
						a.state, a.guard, a.move, a.moveFrame, a.stringIndex = if k <= m.startup then "Startup" else "Active", nil, key, k, 1
					elseif f > LEAD + GRAB and f <= LEAD + GRAB + #timeline then
						local step = timeline[f - LEAD - GRAB]
						local tf = step.tf
						hs = step.hs
						local isBroken = broken and tf >= (breakAt :: number)
						local function info(role: string): any
							return { role = role, move = key, archetype = (m.anim and m.anim.archetype) or "slam", frame = tf, duration = duration, impactFrame = impactFrame, breakWindow = m.breakWindow,
								broken = if isBroken then true else nil, breakFrame = if isBroken then breakAt else nil }
						end
						a.state, a.guard, a.throw = "Throw", nil, info("Attacker")
						b.state, b.guard, b.throw = "Throw", nil, info("Defender")
						if not broken and tf >= impactFrame then b.lastHit = { kind = "Throw", height = "Throw", tier = "Heavy", counter = false, frame = 9000 + impactFrame, move = key, limb = "RearArm", side = 0 } end
					elseif f > LEAD + GRAB + #timeline then
						local after = f - LEAD - GRAB - #timeline
						local push = if broken then 0.6 else 0.45
						a.pos = Vector3.new(-push, 0, 0)
						b.pos = Vector3.new(throwDist + push, 0, 0)
						if not broken then
							b.lastHit = { kind = "Throw", height = "Throw", tier = "Heavy", counter = false, frame = 9000 + impactFrame, move = key, limb = "RearArm", side = 0 }
							if after <= L then
								b.state, b.guard, b.knockdown, b.stun = "Landing", nil, "FaceUp", L - after
							elseif after <= L + G then
								b.state, b.guard, b.knockdown, b.stun, b.getupKind = "Getup", nil, "FaceUp", G - (after - L) + 1, "Stand"
							end
						end
					end
					return { views = { a, b }, hitstop = hs }
				end,
			}
			table.insert(cases, c)
		end
	end
	return cases
end

-- Hit cases: the move connects at max range on its first active frame, as CombatSim plays it: the hit frame and the
-- hitstop freeze (Config.Hitstop[tier] (+2 counter), Block 3) repeat the same snapshot, the defender is pushed back
-- push x 0.75 (x 0.35 blocked) in one frame and takes the reaction: Blockstun, Hitstun (+N), Landing (KND: lies 34 f,
-- gets up 26 f) or Airborne (LAUNCH: 16 studs/s up, gravity 44). Both fighters are measured.
function QA.hitCase(id: string, key: string, outcome: string?, partner: string?): Case?
	local m = Roster.getMove(id, key)
	if not m or m.height == "Throw" then return nil end
	local p = partner or partnerOf(id)
	local cfg: any = Config
	local total = m.startup + m.active + m.recovery
	local advance = m.advance or 0
	local dist = (m.range or 4) + advance
	local step = advance / math.max(m.startup, 1)
	local hitFrame = m.startup + 1
	local blocked = outcome == "Block"
	local counter = outcome == "Counter"
	local onHit = if counter and m.onCounter ~= nil then m.onCounter else m.onHit
	local hs = if blocked then (cfg.Hitstop.Block or 3) else ((cfg.Hitstop[m.tier] or 6) + (if counter then (cfg.CounterHitstopBonus or 2) else 0))
	local push = (m.push or 0.5) * (if blocked then 0.35 else 0.75)
	local L, G = cfg.LandingFrames or 34, cfg.GetupFrames or 26
	local hit = newHit(if blocked then "Block" elseif counter then "Counter" else "Hit", m.height, m.tier or "Medium", counter)
	local limbMap = { LeadArm = "LeftHand", RearArm = "RightHand", LeadLeg = "LeftFoot", RearLeg = "RightFoot" }
	local clip = ClipLibrary.forMove(id, key)
	local limb = (clip and clip.tags and type(clip.tags.limb) == "string" and clip.tags.limb) or limbMap[m.limb or ""] or "RightHand"
	local frames: { any } = {}
	local LEAD = 20
	local function attackerView(mf: number): any
		if mf < 1 then return baseView("Idle", { guard = "Stand" }) end
		if mf > total then return baseView("Idle", { guard = "Stand", pos = Vector3.new(advance, 0, 0) }) end
		local state = if mf <= m.startup then "Startup" elseif mf <= m.startup + m.active then "Active" else "Recovery"
		return baseView(state, { move = key, moveFrame = mf, stringIndex = 1, crouched = m.crouching == true, pos = Vector3.new(step * math.min(mf - 1, m.startup), 0, 0) })
	end
	local defX = dist + push
	-- Defender timeline after the hit (k = frames since the hit frame, the hitstop excluded).
	local stun0 = if blocked then math.max(1, (total - hitFrame) + (m.onBlock or 0)) elseif type(onHit) == "number" then math.max(1, (total - hitFrame) + onHit) else 0
	local air: { any } = {}
	if onHit == "LAUNCH" and not blocked then
		local y, vy = 0.05, cfg.LaunchVelocity or 16
		while y > 0 and #air < 120 do
			vy -= (cfg.Gravity or 44) / 60
			y += vy / 60
			table.insert(air, { y = math.max(y, 0), vy = vy })
		end
	end
	local function defenderView(k: number): any
		local base = { pos = Vector3.new(defX, 0, 0), facing = -Vector3.xAxis, lastHit = hit }
		if blocked or type(onHit) == "number" then
			if k < stun0 then
				base.stun = stun0 - k
				if blocked then base.guard = if m.height == "Low" then "Crouch" else "Stand"; base.crouched = m.height == "Low" end
				return baseView(if blocked then "Blockstun" else "Hitstun", base)
			end
			base.guard = "Stand"
			return baseView("Idle", base)
		end
		local kk = k
		if onHit == "LAUNCH" then
			if kk < #air then
				local a = air[kk + 1]
				base.pos = Vector3.new(defX, a.y, 0)
				base.velocityY = a.vy; base.airFrames = kk + 1; base.airHits = 0
				return baseView("Airborne", base)
			end
			kk -= #air
		end
		base.knockdown = "FaceUp"
		if kk < L then base.stun = L - kk; return baseView("Landing", base) end
		kk -= L
		if kk < G then base.stun = G - kk; base.getupKind = "Stand"; return baseView("Getup", base) end
		base.guard = "Stand"
		return baseView("Idle", base)
	end
	local lowBlock = blocked and m.height == "Low"
	local function before(): any
		return baseView(if lowBlock then "Crouch" else "Idle", { guard = if lowBlock then "Crouch" else "Stand", crouched = lowBlock, pos = Vector3.new(dist, 0, 0), facing = -Vector3.xAxis })
	end
	for _ = 1, LEAD do table.insert(frames, { a = attackerView(0), d = before(), hs = 0 }) end
	for mf = 1, hitFrame - 1 do table.insert(frames, { a = attackerView(mf), d = before(), hs = 0 }) end
	for h = 0, hs do table.insert(frames, { a = attackerView(hitFrame), d = defenderView(0), hs = hs - h }) end
	local after = math.max(total - hitFrame, 0) + (if onHit == "KND" or onHit == "LAUNCH" then L + G + #air + 30 else math.max(stun0 - (total - hitFrame), 0) + 30)
	for k = 1, after do table.insert(frames, { a = attackerView(hitFrame + k), d = defenderView(k), hs = 0 }) end
	local contact = {}
	for f = m.startup + 1, m.startup + m.active do contact[f] = true end
	local c: Case = {
		label = string.format("hit:%s.%s:%s", id, key, outcome or "Hit"), kind = "hit", ids = { id, p }, n = #frames, subjects = { 1, 2 },
		at = function(f: number)
			local fr = frames[f]
			return { views = { table.clone(fr.a), table.clone(fr.d) }, hitstop = fr.hs }
		end,
	}
	c.strike = { slot = 1, limb = limb, contact = contact }
	c.meta = { move = key, outcome = outcome or "Hit", hitstop = hs, push = push }
	return c
end

-- Hit cases for every move of a fighter: hit (and block for a sample), plus counter hits on the jab-like moves.
function QA.hitCases(id: string, outcomes: { string }?): { Case }
	local cases: { Case } = {}
	local keys = {}
	for key, m in Roster.get(id).moves do if m.height ~= "Throw" then table.insert(keys, key) end end
	table.sort(keys)
	for _, key in keys do
		for _, outcome in outcomes or { "Hit", "Block" } do
			local c = QA.hitCase(id, key, outcome)
			if c then table.insert(cases, c) end
		end
	end
	return cases
end

-- Every move case of a fighter (all roster moves except throws; throw grab attempts are moves too).
function QA.moveCases(id: string, ranges: { string }?): { Case }
	local cases: { Case } = {}
	local keys = {}
	for key, m in Roster.get(id).moves do table.insert(keys, key) end
	table.sort(keys)
	for _, key in keys do
		for _, range in ranges or { "max" } do
			local c = QA.moveCase(id, key, range)
			if c then table.insert(cases, c) end
		end
	end
	return cases
end

-- Aggregation ----------------------------------------------------------------------------------------------------------

-- Collapses defects to the worst per (fighter, case, metric, part) and counts per category and fighter.
function QA.summarize(defects: { Defect }): any
	local worst: { [string]: Defect } = {}
	local counts: { [string]: { [string]: number } } = {}
	for _, d in defects do
		local k = d.fighter .. "|" .. d.case .. "|" .. d.metric .. "|" .. d.part
		local w = worst[k]
		if not w or d.value - d.limit > w.value - w.limit then worst[k] = d end
	end
	local list = {}
	for _, d in worst do
		table.insert(list, d)
		local cat = string.match(d.metric, "^[^%.]+") or d.metric
		counts[cat] = counts[cat] or {}
		counts[cat][d.fighter] = (counts[cat][d.fighter] or 0) + 1
	end
	table.sort(list, function(a, b) return (a.value / math.max(a.limit, 1e-3)) > (b.value / math.max(b.limit, 1e-3)) end)
	return { list = list, counts = counts }
end

return QA
