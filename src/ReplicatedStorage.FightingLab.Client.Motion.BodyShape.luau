--!strict
-- Body shapes of a fighter rig for contact checks (runtime strike contact, MotionQA): the head, chest and pelvis as
-- radial profiles of their real collision hulls (rays cast at the part's long axis once per rig: tapered torsos and
-- heads, not bounding boxes), the hands as spheres/capsules (a boxing glove or fist when the rig has one).
local BodyShape = {}

export type Profile = { ys: { number }, r: { { number } }, n: number, y0: number, y1: number }
export type Hand = { r: number, len: number, offset: Vector3, axis: Vector3?, gloved: boolean, source: string }
export type Shape = { profiles: { [string]: Profile }, hand: { [string]: Hand }, half: { [string]: Vector3 } }

BodyShape.CORE = { "Head", "UpperTorso", "LowerTorso" }
local SLICES, DIRS = 9, 16
BodyShape.SLICES, BodyShape.DIRS = SLICES, DIRS

-- Radial surface profile of a part's collision geometry in the part's frame (SLICES heights x DIRS directions), or nil
-- when no ray hits it.
function BodyShape.profilePart(part: BasePart): Profile?
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

-- Approximate signed distance of a point (part space) to a profiled part (negative inside).
function BodyShape.sdProfile(prof: Profile, p: Vector3): number
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
	return math.max(radial, vertical)
end

local function sdEllipsoid(p: Vector3, r: Vector3): number
	local k0 = Vector3.new(p.X / r.X, p.Y / r.Y, p.Z / r.Z).Magnitude
	local k1 = Vector3.new(p.X / (r.X * r.X), p.Y / (r.Y * r.Y), p.Z / (r.Z * r.Z)).Magnitude
	if k1 < 1e-9 then return -math.min(r.X, r.Y, r.Z) end
	return k0 * (k0 - 1) / k1
end
BodyShape.sdEllipsoid = sdEllipsoid

-- The visible hand volume, a capsule in the hand's frame (centre `offset`, direction `axis` — the hand's long axis when
-- nil —, half length `len`, radius `r`): a rigid glove part worn on the hand (a BasePart named "*Glove*" under the hand,
-- measured along its own longest axis — rigid gloves sit toward the wrist, tilted), a FightingLabGloveRadius
-- attribute, a fist part (LeftFist/RightFist), a layered glove accessory; else the open hand as a thin capsule.
function BodyShape.handVolume(model: Instance?, hand: BasePart): Hand
	local attr = hand:GetAttribute("FightingLabGloveRadius")
	if typeof(attr) == "number" and attr > 0 then return { r = attr, len = attr * 0.35, offset = Vector3.zero, gloved = true, source = "attribute" } end
	for _, d in hand:GetDescendants() do
		if d:IsA("BasePart") and string.find(string.lower(d.Name), "glove", 1, true) then
			-- Capsule along the glove's own longest axis (a rigid glove is worn tilted on the hand); a glove is a rounded
			-- mitt, so its radius is about the mean of its two smaller half-widths.
			local rel = hand.CFrame:ToObjectSpace(d.CFrame)
			local s = d.Size * 0.5
			local axes = { { s.X, rel.RightVector }, { s.Y, rel.UpVector }, { s.Z, rel.LookVector } }
			table.sort(axes, function(a, b) return a[1] > b[1] end)
			local r = (axes[2][1] + axes[3][1]) * 0.5 * 0.95
			return { r = r, len = math.max(axes[1][1] - r, 0.02), offset = rel.Position, axis = axes[1][2], gloved = true, source = "rigid" }
		end
	end
	local fist = hand:FindFirstChild(if hand.Name == "LeftHand" then "LeftFist" else "RightFist")
	if fist and fist:IsA("BasePart") then
		local r = (fist.Size.X + fist.Size.Y + fist.Size.Z) / 6
		return { r = r, len = r * 0.35, offset = hand.CFrame:PointToObjectSpace(fist.Position), gloved = true, source = "fist" }
	end
	if model then
		for _, a in model:GetChildren() do
			if a:IsA("Accessory") and string.find(string.lower(a.Name), "glove", 1, true) then
				local h = a:FindFirstChild("Handle")
				if h and h:IsA("BasePart") then
					-- One layered accessory holds both gloves (authored in the T-pose: X spans both arms); a glove's own
					-- cross-section is its Y x Z.
					local r = (h.Size.Y + h.Size.Z) * 0.25
					return { r = r, len = r * 0.35, offset = Vector3.zero, gloved = true, source = "accessory" }
				end
			end
		end
	end
	local s = hand.Size
	return { r = (s.X + s.Z) * 0.25, len = s.Y * 0.32, offset = Vector3.zero, gloved = false, source = "hand" }
end

-- World end points and radius of a hand volume for the hand posed at `cf`.
function BodyShape.handCapsule(h: Hand, cf: CFrame): (Vector3, Vector3, number)
	local c = cf:PointToWorldSpace(h.offset)
	local axis = cf:VectorToWorldSpace(h.axis or Vector3.yAxis) * h.len
	return c + axis, c - axis, h.r
end

-- The shape of a rig (parts by name: RigInfo.parts), profiled once and cached on the table passed in.
function BodyShape.of(holder: any, parts: { [string]: BasePart }, model: Instance?): Shape
	local cached = holder.bodyShape
	if cached then return cached end
	local profiles: { [string]: Profile } = {}
	local half: { [string]: Vector3 } = {}
	for _, name in BodyShape.CORE do
		local part = parts[name]
		if part then
			half[name] = part.Size * 0.5
			local prof = BodyShape.profilePart(part)
			if prof then profiles[name] = prof end
		end
	end
	local hand: { [string]: Hand } = {}
	for _, name in { "LeftHand", "RightHand" } do
		local part = parts[name]
		if part then hand[name] = BodyShape.handVolume(model, part) end
	end
	local shape: Shape = { profiles = profiles, hand = hand, half = half }
	holder.bodyShape = shape
	return shape
end

-- Signed distance from a world point to one core part posed at `cf` (profile, else an ellipsoid of the part box).
function BodyShape.partDistance(shape: Shape, name: string, cf: CFrame, p: Vector3): number
	local lp = cf:PointToObjectSpace(p)
	local prof = shape.profiles[name]
	if prof then return BodyShape.sdProfile(prof, lp) end
	local half = shape.half[name]
	if half then return sdEllipsoid(lp, half) end
	return math.huge
end

-- Signed distance from a world point to the body core (head, chest, pelvis) posed as `frames` (part name -> CFrame).
function BodyShape.coreDistance(shape: Shape, frames: { [string]: CFrame }, p: Vector3, skipHead: boolean?): (number, string)
	local best, which = math.huge, ""
	for _, name in BodyShape.CORE do
		local cf = frames[name]
		if cf and not (skipHead and name == "Head") then
			local d = BodyShape.partDistance(shape, name, cf, p)
			if d < best then best, which = d, name end
		end
	end
	return best, which
end

-- Face landmarks (round 5): the camera-side eye, the nose (bridge to tip) and the mouth, as offsets from the head's
-- FaceFrontAttachment in units of the head's half size (x: + = toward the side the face is seen from, y up, z: + = back
-- into the head), each then snapped onto the head's real surface by a ray cast from in front of the face (the nose and
-- lips sit on the face whatever the head mesh). Used by the runtime's profile clearance (MotionPlayer.clearArms) and by
-- MotionQA's face-visibility measure.
BodyShape.FACE = {
	{ "eye", 0.40, 0.18, 0.10 }, { "eye", 0.24, 0.18, 0.04 }, { "eye", 0.56, 0.17, 0.22 }, { "eye", 0.40, 0.25, 0.10 }, { "eye", 0.40, 0.11, 0.09 },
	{ "nose", 0.0, 0.10, -0.02 }, { "nose", 0.0, -0.02, -0.08 }, { "nose", 0.0, -0.13, -0.12 }, { "nose", 0.12, -0.17, 0.0 },
	{ "mouth", 0.0, -0.36, -0.02 }, { "mouth", 0.20, -0.37, 0.05 }, { "mouth", 0.0, -0.30, -0.04 }, { "mouth", 0.0, -0.43, 0.0 },
}
local landmarkCache: { [Instance]: { [number]: { Vector3 } } } = setmetatable({}, { __mode = "k" }) :: any
-- Head-space landmark points of `head` seen from its right (side = 1) or left (side = -1), cached per head part.
function BodyShape.faceLandmarks(head: BasePart, side: number): { Vector3 }
	local byHead = landmarkCache[head]
	if not byHead then
		byHead = {}
		landmarkCache[head] = byHead
	end
	local cached = byHead[side]
	if cached then return cached end
	local h = head.Size * 0.5
	local att = head:FindFirstChild("FaceFrontAttachment")
	local f = if att and att:IsA("Attachment") then att.Position else Vector3.new(0, 0, -head.Size.Z * 0.45)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { head }
	local wasQuery = head.CanQuery
	head.CanQuery = true
	local list = {}
	for _, l in BodyShape.FACE do
		local lp = Vector3.new(f.X + side * (l[2] :: number) * h.X, f.Y + (l[3] :: number) * h.Y, f.Z + (l[4] :: number) * h.Z)
		local from = head.CFrame:PointToWorldSpace(Vector3.new(lp.X, lp.Y, -h.Z * 2))
		local to = head.CFrame:PointToWorldSpace(Vector3.new(lp.X, lp.Y, h.Z))
		local hit = workspace:Raycast(from, to - from, params)
		if hit then
			local hl = head.CFrame:PointToObjectSpace(hit.Position)
			if math.abs(hl.Z - lp.Z) < h.Z * 0.6 then lp = Vector3.new(lp.X, lp.Y, hl.Z - 0.01) end
		end
		table.insert(list, lp)
	end
	head.CanQuery = wasQuery
	byHead[side] = list
	return list
end

return BodyShape
