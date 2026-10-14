--!strict
-- World_Test: the lobby world built at server start (ServerScriptService.FightingLabWorldBoot) meets the OV6 world
-- contract: names and attributes, a compact layout (every pad a short walk from every spawn, measured with
-- PathfindingService: worst <= 40 and median <= 30 studs of path), an Arrival marker per arena, a visible edge at the
-- fight radius on every stage, a flat fight floor with nothing but the edge barrier near it, no other arena near the
-- middle of a fight camera's frame (the real CameraDirector framing), camera-occluder tags, no overlapping pieces, no
-- terrain under the hardscape, part budget and build time.
-- Run in Play on the server (the world exists only at runtime).
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local WorldModules = ServerStorage.FightingLab.World
local Layout = require(WorldModules.Layout)
local CameraDirector = require(ReplicatedStorage.FightingLab.Client.CameraDirector) :: any

local STAGE_IDS = { MidnightRooftop = true, HarborDusk = true, JungleRuins = true, SnowSummit = true, TrainingBay = true }
-- round 7 budget: the world may grow at most 25 % over main's 3,892 parts (round 6, measured in Play)
local PART_CEILING = 4865
-- and keep its lights few, none casting shadows (main: 92 lights, 0 shadows)
local LIGHT_CEILING = 100
-- walking bounds from every spawn to every pad (studs of PathfindingService path); fixed here, not read from Layout,
-- so an older (wider) layout fails them
local WALK_WORST = 40
local WALK_MEDIAN = 30

local function world(): Instance?
	return workspace:FindFirstChild("FightingLabWorld")
end

local function extents(part: BasePart): (number, number, number)
	local cf, s = part.CFrame, part.Size / 2
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	return math.abs(r.X) * s.X + math.abs(u.X) * s.Y + math.abs(l.X) * s.Z,
		math.abs(r.Y) * s.X + math.abs(u.Y) * s.Y + math.abs(l.Y) * s.Z,
		math.abs(r.Z) * s.X + math.abs(u.Z) * s.Y + math.abs(l.Z) * s.Z
end

-- Shortest horizontal distance from a point to a part's world bounding box.
local function flatDistance(part: BasePart, p: Vector3): number
	local ex, _, ez = extents(part)
	local dx = math.max(math.abs(part.Position.X - p.X) - ex, 0)
	local dz = math.max(math.abs(part.Position.Z - p.Z) - ez, 0)
	return math.sqrt(dx * dx + dz * dz)
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Horizontal distance from a point to the part's actual (oriented) box, measured at the part's height: exact for
-- rails, ropes and posts, where the axis-aligned box of a diagonal rod would reach much closer.
local function orientedFlatDistance(part: BasePart, p: Vector3): number
	local q = Vector3.new(p.X, part.Position.Y, p.Z)
	local l = part.CFrame:PointToObjectSpace(q)
	local h = part.Size / 2
	local clamped = Vector3.new(math.clamp(l.X, -h.X, h.X), math.clamp(l.Y, -h.Y, h.Y), math.clamp(l.Z, -h.Z, h.Z))
	return flat(part.CFrame:PointToWorldSpace(clamped) - q).Magnitude
end

local function topY(part: BasePart): number
	local _, ey = extents(part)
	return part.Position.Y + ey
end

-- Like orientedFlatDistance, but exact for upright cylinders (podium and floor discs) and balls.
local function shapeFlatDistance(part: BasePart, p: Vector3): number
	if part:IsA("Part") then
		local shape = (part :: Part).Shape
		if shape == Enum.PartType.Ball or (shape == Enum.PartType.Cylinder and math.abs(part.CFrame.RightVector.Y) > 0.99) then
			local radius = if shape == Enum.PartType.Ball then part.Size.X / 2 else math.min(part.Size.Y, part.Size.Z) / 2
			return math.max(0, flat(part.Position - p).Magnitude - radius)
		end
	end
	return orientedFlatDistance(part, p)
end

local function bottomY(part: BasePart): number
	local _, ey = extents(part)
	return part.Position.Y - ey
end

local function arenaModel(id: string): Model?
	local w = world()
	local arenas = w and w:FindFirstChild("Arenas")
	local m = arenas and arenas:FindFirstChild(id)
	return if m and m:IsA("Model") then m else nil
end

-- Raycast against the built world only (plus terrain when asked): players and fight rigs standing on pads, exits or
-- the plaza must never decide what the "floor" is.
local function worldRay(origin: Vector3, direction: Vector3, withTerrain: boolean?): RaycastResult?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local include: { Instance } = { world() :: Instance }
	if withTerrain then
		table.insert(include, workspace.Terrain)
	end
	params.FilterDescendantsInstances = include
	return workspace:Raycast(origin, direction, params)
end

local function allParts(): { BasePart }
	local list = {}
	local w = world()
	if w then
		for _, d in w:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(list, d)
			end
		end
	end
	return list
end

local function padNames(def: Layout.ArenaDef): { string }
	return if def.kind == "Practice" then { "PadTraining", "PadCpu" } else { "PadP1", "PadP2" }
end

local function exitNames(def: Layout.ArenaDef): { string }
	return if def.kind == "Practice" then { "ExitTraining", "ExitCpu" } else { "ExitP1", "ExitP2" }
end

local function spawns(): { BasePart }
	local list = {}
	local lobby = (world() :: Instance):FindFirstChild("Lobby")
	for _, d in (lobby :: Instance):GetChildren() do
		if d.Name == "LobbySpawn" and d:IsA("BasePart") then
			table.insert(list, d)
		end
	end
	table.sort(list, function(a, b)
		return (a:GetAttribute("SpawnIndex") or 0) < (b:GetAttribute("SpawnIndex") or 0)
	end)
	return list
end

-- Walking distance along a PathfindingService path (an R15-sized agent that never jumps), or nil when no path.
local function walkDistance(from: Vector3, to: Vector3): number?
	local path = PathfindingService:CreatePath({ AgentRadius = 1.5, AgentHeight = 5, AgentCanJump = false, WaypointSpacing = 4 })
	local ok = pcall(function()
		path:ComputeAsync(from, to)
	end)
	if not ok or path.Status ~= Enum.PathStatus.Success then
		return nil
	end
	local total = 0
	local points = path:GetWaypoints()
	for i = 2, #points do
		total += (points[i].Position - points[i - 1].Position).Magnitude
	end
	return total
end

-- Every spawn -> pad walk measured so far (filled by the per-arena walk tests, completed by the median test).
local walks: { [string]: number } = {}

local function walkKey(spawnIndex: number, arenaId: string, padName: string): string
	return string.format("%d|%s|%s", spawnIndex, arenaId, padName)
end

local function median(values: { number }): number
	local sorted = table.clone(values)
	table.sort(sorted)
	local n = #sorted
	if n == 0 then
		return 0
	end
	return if n % 2 == 1 then sorted[(n + 1) // 2] else (sorted[n // 2] + sorted[n // 2 + 1]) / 2
end

-- The real fight camera (CameraDirector._plan) for a fight at `def` with both fighters on their start marks and the
-- fight line turned `theta` degrees from world X (0 / 90 / 180 / 270 = the four fight-line orientations).
local function fightCamera(def: Layout.ArenaDef, theta: number): (CFrame, number)
	local th = math.rad(theta)
	local dir = Vector3.new(math.cos(th), 0, math.sin(th))
	local side = Vector3.new(dir.Z, 0, -dir.X)
	local a, b = -dir * 3.5, dir * 3.5
	local plan = CameraDirector._plan(a, b, "Fight", 0, 1 / 60, side, 0, false, nil)
	return CFrame.lookAt(def.origin + plan.position, def.origin + plan.focus), plan.fov
end

return function(t)
	local expect = t.expect

	t.test("world is built at server start and WorldReady is set", function()
		local ready = ReplicatedStorage.FightingLab:WaitForChild("WorldReady", 4)
		expect.truthy(ready and ready:IsA("BoolValue"), "WorldReady BoolValue exists")
		expect.equal((ready :: BoolValue).Value, true, "WorldReady value")
		expect.falsy((ready :: Instance):GetAttribute("BuildError"), "no build error")
		local w = world()
		expect.truthy(w and w:IsA("Folder"), "workspace.FightingLabWorld folder")
		local lobby = w and w:FindFirstChild("Lobby")
		local arenas = w and w:FindFirstChild("Arenas")
		expect.truthy(lobby and lobby:IsA("Model"), "Lobby model")
		expect.truthy(arenas and arenas:IsA("Folder"), "Arenas folder")
		expect.equal(workspace.StreamingEnabled, false, "streaming stays off")
	end)

	t.test("lobby has spawns facing the plaza head, fighter kiosk prompt, leaderboard and a signpost", function()
		local lobby = (world() :: Instance):FindFirstChild("Lobby") :: Model
		local list = spawns()
		expect.truthy(#list >= 1, "at least one LobbySpawn")
		local facing = Layout.bearingDir(Layout.SPAWN_FACING)
		for _, s in list do
			expect.truthy(s:IsA("SpawnLocation"), "LobbySpawn is a SpawnLocation")
			local sp = s :: SpawnLocation
			expect.truthy(sp.Neutral and sp.Enabled, "spawn neutral and enabled")
			expect.equal(sp.Duration, 0, "no forcefield")
			expect.truthy(sp.Anchored and sp.CanCollide, "spawn anchored and solid")
			expect.truthy(math.abs(topY(sp) - 0.15) < 0.2, "spawn sits on the plaza floor")
			expect.truthy(sp.CFrame.LookVector:Dot(facing) > 0.98, "spawn faces the plaza head")
			expect.truthy(flat(sp.Position).Magnitude < 10, "spawn on the plaza centre")
		end
		local kiosk = lobby:FindFirstChild("FighterKiosk")
		expect.truthy(kiosk and kiosk:IsA("Model"), "FighterKiosk model")
		local promptPart = (kiosk :: Instance):FindFirstChild("PromptPart")
		expect.truthy(promptPart and promptPart:IsA("BasePart"), "PromptPart")
		local prompt = (promptPart :: Instance):FindFirstChild("ChooseFighter") :: ProximityPrompt
		expect.truthy(prompt and prompt:IsA("ProximityPrompt"), "ChooseFighter prompt")
		expect.equal(prompt.ActionText, "Choose Fighter")
		expect.equal(prompt.ObjectText, "Fighters")
		expect.equal(prompt.HoldDuration, 0)
		expect.equal(prompt.MaxActivationDistance, 10)
		expect.equal(prompt.RequiresLineOfSight, false)
		local board = lobby:FindFirstChild("Leaderboard")
		expect.truthy(board and board:IsA("BasePart"), "Leaderboard part")
		local gui = (board :: Instance):FindFirstChild("LeaderboardGui") :: SurfaceGui
		expect.truthy(gui and gui:IsA("SurfaceGui"), "LeaderboardGui")
		expect.equal(gui.LightInfluence, 0)
		expect.equal(gui.SizingMode, Enum.SurfaceGuiSizingMode.PixelsPerStud)
		local b = board :: BasePart
		expect.near(b.Size.X * gui.PixelsPerStud, 800, 1, "leaderboard canvas width")
		expect.near(b.Size.Y * gui.PixelsPerStud, 600, 1, "leaderboard canvas height")
		-- kiosk and Hall of Champions stand at the head of the plaza, a short walk from the spawn court
		local court = Vector3.zero
		for _, s in list do
			court += flat(s.Position) / #list
		end
		expect.truthy((flat((promptPart :: BasePart).Position) - court).Magnitude < 40, "kiosk console near the spawns")
		expect.truthy((flat(b.Position) - court).Magnitude < 40, "leaderboard near the spawns")
		local post = lobby:FindFirstChild("Signpost")
		expect.truthy(post, "central signpost")
		for _, def in Layout.ARENAS do
			expect.truthy((post :: Instance):FindFirstChild("Arm_" .. def.stageId, true), "signpost arm for " .. def.stageId)
			local model = arenaModel(def.id) :: Model
			expect.truthy(model:FindFirstChild("Gate_" .. def.stageId), "name signage at the stair of " .. def.stageId)
		end
		-- plaza floor top at Y = 0
		local hit = worldRay(Vector3.new(0, 6, -21), Vector3.new(0, -12, 0))
		expect.truthy(hit, "plaza floor in the spawn court")
		expect.truthy(math.abs((hit :: RaycastResult).Position.Y) < 0.1, "plaza floor top at Y=0")
	end)

	t.test("arenas carry the contract attributes, origin and a status board facing the plaza", function()
		local orders: { [number]: boolean } = {}
		for _, def in Layout.ARENAS do
			local model = arenaModel(def.id) :: Model
			expect.truthy(model, "arena model " .. def.id)
			expect.equal(model:GetAttribute("ArenaId"), def.id)
			local stageId = model:GetAttribute("StageId")
			expect.truthy(typeof(stageId) == "string" and STAGE_IDS[stageId], "StageId is a roster stage")
			expect.truthy(typeof(model:GetAttribute("DisplayName")) == "string" and #model:GetAttribute("DisplayName") > 0, "DisplayName")
			local kind = model:GetAttribute("Kind")
			expect.truthy(kind == "Duel" or kind == "Practice", "Kind")
			expect.equal(kind == "Practice", stageId == "TrainingBay", "only the dojo is Practice")
			local order = model:GetAttribute("Order")
			expect.truthy(typeof(order) == "number" and order >= 1 and order <= 5 and not orders[order], "Order unique 1..5")
			orders[order :: number] = true
			local origin = model:FindFirstChild("FightOrigin") :: BasePart
			expect.truthy(origin and origin:IsA("BasePart"), "FightOrigin")
			expect.truthy(origin.Anchored and not origin.CanCollide and not origin.CanQuery and not origin.CanTouch, "FightOrigin is a ghost")
			expect.equal(origin.Transparency, 1)
			expect.near(origin.Size.Magnitude, Vector3.one.Magnitude, 1e-3, "FightOrigin size 1")
			expect.truthy(origin.CFrame.LookVector:Dot(Vector3.new(0, 0, -1)) > 0.9999 and origin.CFrame.UpVector.Y > 0.9999, "identity rotation")
			local d = flat(origin.Position).Magnitude
			expect.truthy(d >= 55 and d <= 85, "arena close to the plaza (" .. math.floor(d) .. " studs)")
			local board = model:FindFirstChild("StatusBoard") :: BasePart
			expect.truthy(board and board:IsA("BasePart"), "StatusBoard")
			local gui = board:FindFirstChild("StatusGui") :: SurfaceGui
			expect.truthy(gui and gui:IsA("SurfaceGui"), "StatusGui")
			expect.equal(gui.LightInfluence, 0)
			expect.equal(gui.AlwaysOnTop, false)
			local idle = board:FindFirstChild("BoardIdle") :: SurfaceGui?
			expect.truthy(idle and idle.ZOffset < gui.ZOffset, "idle face sits under the status gui")
			local toPlaza = flat(-origin.Position).Unit
			expect.truthy(board.CFrame.LookVector:Dot(toPlaza) > 0.9, "board faces the plaza")
			expect.truthy(flat(board.Position - origin.Position):Dot(toPlaza) < -40, "board stands behind the stage")
		end
	end)

	-- Contract D (round 7): the map picker shows each arena with its tagline, theme colour and a beauty shot.
	t.test("every arena carries its map preview: Tagline, ThemeColor and a PreviewCam beauty shot of the ring", function()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { world() :: Instance }
		local themes: { [string]: Color3 } = {}
		for _, def in Layout.ARENAS do
			local model = arenaModel(def.id) :: Model
			local tagline = model:GetAttribute("Tagline")
			expect.truthy(typeof(tagline) == "string" and #tagline >= 8 and #tagline <= 40, def.id .. ": Tagline of 8 to 40 characters")
			local theme = model:GetAttribute("ThemeColor")
			expect.truthy(typeof(theme) == "Color3", def.id .. ": ThemeColor is a Color3")
			if typeof(theme) == "Color3" then
				for otherId, other in themes do
					local d = math.sqrt((theme.R - other.R) ^ 2 + (theme.G - other.G) ^ 2 + (theme.B - other.B) ^ 2)
					expect.truthy(d > 0.2, string.format("%s / %s theme colours tell the arenas apart (%.2f)", def.id, otherId, d))
				end
				themes[def.id] = theme
			end
			-- the anchors and attributes from before stay
			for _, key in { "ArenaId", "StageId", "DisplayName", "Kind", "Order", "FightRadius" } do
				expect.truthy(model:GetAttribute(key) ~= nil, def.id .. " keeps " .. key)
			end
			local cam = model:FindFirstChild("PreviewCam")
			expect.truthy(cam and cam:IsA("BasePart"), def.id .. ".PreviewCam is a BasePart")
			if not (cam and cam:IsA("BasePart")) then continue end
			expect.truthy(cam.Anchored and not cam.CanCollide and not cam.CanQuery and not cam.CanTouch, def.id .. ": PreviewCam is a ghost")
			expect.equal(cam.Transparency, 1, def.id .. ": PreviewCam invisible")
			local origin = (model:FindFirstChild("FightOrigin") :: BasePart).Position
			local cf = cam.CFrame
			local toRing = origin - cf.Position
			expect.truthy(cf.LookVector:Dot(toRing.Unit) > 0.95, def.id .. ": PreviewCam looks at the ring")
			local height = cf.Position.Y - origin.Y
			expect.truthy(height >= 6 and height <= 40, string.format("%s: PreviewCam %.1f studs above the floor", def.id, height))
			local range = flat(toRing).Magnitude
			expect.truthy(range >= 25 and range <= 90, string.format("%s: PreviewCam %.1f studs out", def.id, range))
			-- both circles (the edge ring at the fight radius and an inner circle) fit the frame at 16:9 and 4:3
			local fov = cam:GetAttribute("FieldOfView")
			expect.truthy(typeof(fov) == "number" and fov >= 40 and fov <= 80, def.id .. ": PreviewCam FieldOfView")
			local outside = {}
			for _, aspect in { 16 / 9, 4 / 3 } do
				for k = 0, 15 do
					local a = k * math.pi / 8
					for _, r in { Layout.EDGE_INNER + 0.2, 10 } do
						local p = origin + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
						local v = CameraDirector._normalizedViewportPoint(cf, fov :: number, aspect, p)
						if not (v and v.X > 0.03 and v.X < 0.97 and v.Y > 0.04 and v.Y < 0.96) then
							table.insert(outside, string.format("r%.0f @%d %.2f", r, k, aspect))
						end
					end
				end
			end
			expect.equal(#outside, 0, def.id .. ": ring points outside the PreviewCam frame: " .. table.concat(outside, ", "))
			-- in clear view: nothing solid between the lens and the middle of the ring
			local target = origin + Vector3.new(0, 1, 0)
			local hit = workspace:Raycast(cf.Position, (target - cf.Position) * 0.99, params)
			expect.truthy(hit == nil or hit.Instance.Transparency > 0.5 or flat(hit.Position - origin).Magnitude < Layout.BAND_OUTER + 1,
				def.id .. ": PreviewCam view blocked by " .. (if hit then hit.Instance:GetFullName() else "?"))
			for _, p in workspace:GetPartBoundsInRadius(cf.Position, 1.5) do
				expect.truthy(p.Transparency > 0.9, def.id .. ": PreviewCam inside " .. p:GetFullName())
			end
		end
	end)

	t.test("pads stand on the plaza in front of each stage, outside the ring, barrier and podium, top = plaza + 0.25", function()
		for _, def in Layout.ARENAS do
			local model = arenaModel(def.id) :: Model
			local origin = (model:FindFirstChild("FightOrigin") :: BasePart).Position
			local toPlaza = flat(-origin).Unit
			local right = Vector3.new(-toPlaza.Z, 0, toPlaza.X) * -1
			for i, name in padNames(def) do
				local pad = model:FindFirstChild(name) :: BasePart
				expect.truthy(pad and pad:IsA("BasePart"), def.id .. "." .. name)
				local offset = flat(pad.Position - origin)
				expect.truthy(offset.Magnitude - Layout.PAD_RADIUS > Layout.RAIL_RADIUS + 0.4, name .. " clear of the edge barrier")
				expect.truthy(offset.Magnitude - Layout.PAD_RADIUS >= Layout.STAGE_RADIUS + 0.2, name .. " stands off the podium, on the plaza")
				local angle = math.deg(math.acos(math.clamp(offset.Unit:Dot(toPlaza), -1, 1)))
				expect.truthy(angle < 30, name .. " in front of the stage (" .. math.floor(angle) .. " deg)")
				expect.truthy((offset:Dot(right) < 0) == (i == 1), name .. " on the expected side (slot 1 left, slot 2 right)")
				expect.near(topY(pad), Layout.PAD_TOP, 0.03, name .. " top = plaza + 0.25")
				expect.truthy(pad.Shape == Enum.PartType.Cylinder, name .. " is a cylinder")
				expect.near(pad:GetAttribute("PadRadius") :: number, 3.5, 0.6, name .. " PadRadius")
				expect.truthy(pad.Anchored and pad.CanCollide, name .. " solid")
				if def.kind == "Practice" then
					expect.equal(pad:GetAttribute("PadMode"), if i == 1 then "Training" else "Cpu")
				else
					expect.equal(pad:GetAttribute("PadSide"), i)
				end
				local hit = worldRay(pad.Position + Vector3.new(0, 4, 0), Vector3.new(0, -8, 0))
				expect.truthy(hit and hit.Instance == pad, name .. " is the walkable surface at its centre")
			end
			-- the two pads of an arena and their neighbours' never touch
			local a, b = model:FindFirstChild(padNames(def)[1]) :: BasePart, model:FindFirstChild(padNames(def)[2]) :: BasePart
			expect.truthy(flat(a.Position - b.Position).Magnitude > Layout.PAD_RADIUS * 2 + 3, def.id .. " pads apart")
		end
		local all: { BasePart } = {}
		for _, def in Layout.ARENAS do
			for _, name in padNames(def) do
				table.insert(all, (arenaModel(def.id) :: Model):FindFirstChild(name) :: BasePart)
			end
		end
		for i = 1, #all do
			for j = i + 1, #all do
				expect.truthy(flat(all[i].Position - all[j].Position).Magnitude > Layout.PAD_RADIUS * 2 + 1.5, "pads apart: " .. all[i]:GetFullName() .. " / " .. all[j]:GetFullName())
			end
		end
	end)

	t.test("exits sit beside their pads on the plaza floor, facing the arena", function()
		for _, def in Layout.ARENAS do
			local model = arenaModel(def.id) :: Model
			local origin = (model:FindFirstChild("FightOrigin") :: BasePart).Position
			local pads = padNames(def)
			for i, name in exitNames(def) do
				local exit = model:FindFirstChild(name) :: BasePart
				expect.truthy(exit and exit:IsA("BasePart"), def.id .. "." .. name)
				expect.equal(exit.Transparency, 1)
				expect.truthy(not exit.CanCollide and not exit.CanTouch and exit.Anchored, name .. " ghost")
				local pad = model:FindFirstChild(pads[i]) :: BasePart
				local gap = flat(exit.Position - pad.Position).Magnitude
				expect.truthy(gap > 4.5 and gap < 8, name .. " next to its pad (" .. string.format("%.1f", gap) .. ")")
				expect.truthy(math.abs(exit.Position.Y) < 0.05, name .. " on the plaza floor top")
				local offset = exit.Position - origin
				expect.truthy(flat(offset).Magnitude > Layout.STAGE_RADIUS + 1, name .. " outside the stage")
				expect.truthy(exit.CFrame.LookVector:Dot(flat(-offset).Unit) > 0.98, name .. " faces the arena")
				local hit = worldRay(exit.Position + Vector3.new(0, 4, 0), Vector3.new(0, -8, 0))
				expect.truthy(hit and math.abs(hit.Position.Y) < 0.3 and hit.Instance.CanCollide, name .. " stands on walkable floor")
			end
		end
	end)

	t.test("the camera view from every return point is clear: nothing between the framed camera and the player", function()
		-- after a fight, a practice or a quick travel the client (Client.LobbyCamera) looks over the player's shoulder
		-- at the arena from the plaza side; a lamp post or a sign on that line used to fill the middle of the view
		local LobbyCamera = require(ReplicatedStorage.FightingLab.Client.LobbyCamera)
		local parts = {}
		for _, p in allParts() do
			if p.Transparency < 0.5 then table.insert(parts, p) end
		end
		local function boxDistance(part: BasePart, point: Vector3): number
			local l = part.CFrame:PointToObjectSpace(point)
			local h = part.Size / 2
			local c = Vector3.new(math.clamp(l.X, -h.X, h.X), math.clamp(l.Y, -h.Y, h.Y), math.clamp(l.Z, -h.Z, h.Z))
			return (l - c).Magnitude
		end
		local list = {}
		for _, def in Layout.ARENAS do
			local model = arenaModel(def.id) :: Model
			local points: { BasePart } = {}
			for _, name in exitNames(def) do table.insert(points, model:FindFirstChild(name) :: BasePart) end
			table.insert(points, model:FindFirstChild("Arrival") :: BasePart)
			for _, q in points do
				local root = q.Position + Vector3.new(0, 3, 0)
				local eye = LobbyCamera.frameBehind(CFrame.lookAt(root, root + q.CFrame.LookVector)).Position
				local head = root + Vector3.new(0, 1.6, 0)
				local mid, half = (eye + head) / 2, (head - eye).Magnitude / 2
				local seen: { [BasePart]: boolean } = {}
				for _, p in parts do
					if not seen[p] and (p.Position - mid).Magnitude <= half + p.Size.Magnitude / 2 + 1.5 then
						local samples = math.ceil(half * 4)
						for k = 0, samples do
							local point = eye:Lerp(head, k / samples)
							-- the floor under the player and the step of a pad are not view blockers
							if boxDistance(p, point) < (if k == 0 then 1 else 0.9) and topY(p) > q.Position.Y + 1.2 then
								seen[p] = true
								table.insert(list, string.format("%s.%s: %s", def.id, q.Name, p:GetFullName()))
								break
							end
						end
					end
				end
			end
		end
		expect.equal(#list, 0, "pieces between the return camera and the player: " .. table.concat(list, "; "))
	end)

	t.test("every arena has an Arrival marker on the floor outside the ring, facing it, clear and reachable", function()
		local barriers: { Instance } = {}
		for _, def in Layout.ARENAS do
			table.insert(barriers, (arenaModel(def.id) :: Model):FindFirstChild("Barrier") :: Instance)
		end
		local from = spawns()[1].Position + Vector3.new(0, 3, 0)
		for _, def in Layout.ARENAS do
			local model = arenaModel(def.id) :: Model
			local origin = (model:FindFirstChild("FightOrigin") :: BasePart).Position
			local arrival = model:FindFirstChild("Arrival")
			expect.truthy(arrival and arrival:IsA("BasePart"), def.id .. ".Arrival is a BasePart")
			local a = arrival :: BasePart
			expect.truthy(a.Anchored, "Arrival anchored")
			expect.falsy(a.CanCollide, "Arrival does not collide")
			expect.falsy(a.CanTouch, "Arrival fires no touches")
			expect.truthy(a.Transparency >= 0.99, "Arrival is invisible")
			local offset = flat(a.Position - origin)
			expect.truthy(offset.Magnitude > Layout.RAIL_RADIUS + 1, def.id .. " Arrival outside the ring and its barrier")
			-- upright and facing the ring
			expect.truthy(a.CFrame.UpVector.Y > 0.99, "Arrival upright")
			expect.truthy(a.CFrame.LookVector:Dot(-offset.Unit) > 0.98, def.id .. " Arrival faces the ring")
			-- its bottom face rests on walkable floor
			local bottom = a.Position.Y - a.Size.Y / 2
			local hit = worldRay(a.Position + Vector3.new(0, 4, 0), Vector3.new(0, -10, 0))
			expect.truthy(hit and hit.Instance.CanCollide and math.abs(hit.Position.Y - bottom) < 0.25, def.id .. " Arrival on the floor")
			-- not inside or against any barrier, and nothing solid where a player stands
			for _, barrier in barriers do
				for _, p in barrier:GetDescendants() do
					if p:IsA("BasePart") then
						expect.truthy(orientedFlatDistance(p, a.Position) > 2, def.id .. " Arrival clear of " .. p:GetFullName())
					end
				end
			end
			local params = OverlapParams.new()
			params.FilterType = Enum.RaycastFilterType.Include
			params.FilterDescendantsInstances = { world() :: Instance }
			params.RespectCanCollide = true
			local standing = workspace:GetPartBoundsInBox(CFrame.new(a.Position + Vector3.new(0, 3.2, 0)), Vector3.new(3, 5.6, 3), params)
			local blockers = {}
			for _, p in standing do
				table.insert(blockers, p:GetFullName())
			end
			expect.equal(#blockers, 0, def.id .. " standing room at the Arrival: " .. table.concat(blockers, ", "))
			-- both pads are a few steps away, and players can walk there from the spawn
			for _, name in padNames(def) do
				local pad = model:FindFirstChild(name) :: BasePart
				expect.truthy(flat(pad.Position - a.Position).Magnitude < 15, def.id .. " Arrival near " .. name)
			end
			local path = PathfindingService:CreatePath({ AgentRadius = 1.5, AgentHeight = 5, AgentCanJump = false, WaypointSpacing = 4 })
			local ok = pcall(function()
				path:ComputeAsync(from, a.Position + Vector3.new(0, 3, 0))
			end)
			expect.truthy(ok and path.Status == Enum.PathStatus.Success, def.id .. " Arrival reachable on foot")
			local points = path:GetWaypoints()
			expect.truthy(#points > 0 and flat(points[#points].Position - a.Position).Magnitude < 2.5, def.id .. " path ends at the Arrival")
		end
	end)

	t.test("every stage shows a glowing edge ring at the fight radius and a barrier just outside it", function()
		for _, def in Layout.ARENAS do
			local model = arenaModel(def.id) :: Model
			local origin = (model:FindFirstChild("FightOrigin") :: BasePart).Position
			expect.equal(model:GetAttribute("FightRadius"), Layout.FIGHT_RADIUS, "FightRadius attribute")
			local stage = model:FindFirstChild("Stage") :: Model
			expect.truthy(stage, def.id .. " Stage")
			local line = stage:FindFirstChild("EdgeLine") :: BasePart
			local floor = stage:FindFirstChild("FightFloor") :: BasePart
			expect.truthy(line and line:IsA("BasePart") and floor and floor:IsA("BasePart"), def.id .. " EdgeLine and FightFloor")
			expect.equal(line.Material, Enum.Material.Neon, "edge line glows")
			expect.truthy(line.Transparency < 0.2, "edge line visible")
			local outer = line.Size.Y / 2
			local inner = floor.Size.Y / 2
			expect.truthy(flat(line.Position - origin).Magnitude < 0.05 and flat(floor.Position - origin).Magnitude < 0.05, "rings centred on FightOrigin")
			expect.near((inner + outer) / 2, Layout.FIGHT_RADIUS, 0.5, def.id .. " edge ring at the fight radius")
			expect.truthy(outer - inner >= 0.2, def.id .. " edge ring wide enough to read")
			expect.near(topY(floor), origin.Y, 0.01, "fight floor top is the floor")
			expect.truthy(topY(line) < origin.Y and topY(line) > origin.Y - 0.05, "edge line just under the floor top (no z-fighting)")
			local barrier = model:FindFirstChild("Barrier") :: Model
			expect.truthy(barrier, def.id .. " Barrier")
			local posts, rails = 0, 0
			for _, p in barrier:GetDescendants() do
				if p:IsA("BasePart") then
					if p.Name == "EdgePost" then
						posts += 1
						expect.near(flat(p.Position - origin).Magnitude, Layout.RAIL_RADIUS, 0.3, "post on the barrier circle")
						expect.truthy(p.CanCollide, "posts are solid")
					elseif string.sub(p.Name, 1, 8) == "EdgeRail" or string.sub(p.Name, 1, 8) == "EdgeRope" or string.sub(p.Name, 1, 8) == "EdgeVine" or string.sub(p.Name, 1, 8) == "EdgeCord" then
						rails += 1
						expect.truthy(bottomY(p) >= origin.Y + Layout.RAIL_CLEARANCE - 0.05, "rail leaves room under it: " .. p:GetFullName())
					end
				end
			end
			expect.truthy(posts >= 12, def.id .. " barrier posts")
			expect.truthy(rails >= posts * 2, def.id .. " barrier rails")
		end
	end)

	t.test("fight floor is flat to radius 25 with nothing but the edge barrier rising near the fight", function()
		local parts = allParts()
		for _, def in Layout.ARENAS do
			local model = arenaModel(def.id) :: Model
			local origin = (model:FindFirstChild("FightOrigin") :: BasePart).Position
			local barrier = model:FindFirstChild("Barrier") :: Instance
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { barrier }
			for x = -25, 25, 2.5 do
				for z = -25, 25, 2.5 do
					if x * x + z * z <= 25 * 25 then
						local hit = workspace:Raycast(origin + Vector3.new(x, 8, z), Vector3.new(0, -16, 0), params)
						expect.truthy(hit, string.format("%s floor at (%.1f, %.1f)", def.id, x, z))
						local h = (hit :: RaycastResult).Position.Y - origin.Y
						expect.truthy(h > -0.08 and h < 0.21, string.format("%s floor height %.3f at (%.1f, %.1f)", def.id, h, x, z))
						expect.truthy((hit :: RaycastResult).Instance.CanCollide, "floor collides")
					end
				end
			end
			for _, p in parts do
				if p.Name ~= "FightOrigin" and p.Transparency < 0.99 then
					local dist = shapeFlatDistance(p, origin)
					if dist < Layout.FLOOR_CLEAR_RADIUS then
						local top, bottom = topY(p), bottomY(p)
						local rises = top > origin.Y + 0.3 and bottom < origin.Y + 12
						if rises then
							local ex, _, ez = extents(p)
							local edgePart = p:IsDescendantOf(model) and string.sub(p.Name, 1, 4) == "Edge"
							local postLike = math.max(ex, ez) <= 0.8
							local overhead = bottom >= origin.Y + Layout.RAIL_CLEARANCE - 0.05
							expect.truthy(orientedFlatDistance(p, origin) >= Layout.FIGHT_RADIUS + 0.4, def.id .. ": obstacle inside the fight edge: " .. p:GetFullName())
							expect.truthy(edgePart and (postLike or overhead), def.id .. ": obstacle near the fight floor: " .. p:GetFullName())
						end
					end
				end
			end
		end
	end)

	t.test("everything taller than 1.5 within radius 46 is tagged as a camera occluder", function()
		local parts = allParts()
		for _, def in Layout.ARENAS do
			local origin = def.origin
			for _, p in parts do
				if p.Name ~= "FightOrigin" and p.Transparency < 0.99 and topY(p) > origin.Y + Layout.OCCLUDER_HEIGHT + 1e-3 and flatDistance(p, origin) < Layout.OCCLUDER_RADIUS then
					expect.truthy(CollectionService:HasTag(p, Layout.OCCLUDER_TAG), def.id .. ": untagged occluder " .. p:GetFullName())
				end
			end
		end
	end)

	t.test("nothing taller than a lamp from the lobby stands between a fight camera and its fighters", function()
		-- lobby and grounds pieces are not faded by the fight camera, so they keep out of the camera orbit
		local w = world() :: Instance
		for _, section in { "Lobby", "Walkways" } do
			for _, p in (w:FindFirstChild(section) :: Instance):GetDescendants() do
				if p:IsA("BasePart") and p.Transparency < 0.99 then
					for _, def in Layout.ARENAS do
						if topY(p) > def.origin.Y + Layout.OCCLUDER_HEIGHT then
							expect.truthy(orientedFlatDistance(p, def.origin) >= Layout.CAMERA_ORBIT, def.id .. ": lobby piece inside the camera orbit: " .. p:GetFullName())
						end
					end
				end
			end
		end
	end)

	t.test("no other arena's pieces rise inside a fight camera's orbit (stages stay apart)", function()
		-- a fight only fades its own arena's pieces, so the neighbours' barriers, lights and scenery keep their distance
		local list = {}
		for _, def in Layout.ARENAS do
			for _, other in Layout.ARENAS do
				if other.id ~= def.id then
					for _, p in (arenaModel(other.id) :: Model):GetDescendants() do
						if p:IsA("BasePart") and p.Transparency < 0.99 and p.Name ~= "FightOrigin" and topY(p) > def.origin.Y + Layout.OCCLUDER_HEIGHT then
							local d = shapeFlatDistance(p, def.origin)
							if d < Layout.NEIGHBOUR_CLEARANCE then
								table.insert(list, string.format("%s %.1f from %s", p:GetFullName(), d, def.id))
							end
						end
					end
				end
			end
		end
		expect.equal(#list, 0, "neighbour pieces near a fight: " .. table.concat(list, "; "))
		-- and the stages themselves stand well apart
		for i, a in Layout.ARENAS do
			for j, b in Layout.ARENAS do
				if j > i then
					expect.truthy(flat(a.origin - b.origin).Magnitude >= 58, a.id .. " / " .. b.id .. " apart")
				end
			end
		end
	end)

	t.test("no other arena sits near the middle of a fight camera's frame (real CameraDirector framing)", function()
		-- for each fight-line orientation: another arena's ring centre (floor and chest height) inside the central 60 %
		-- of a 16:9 fight frame and within 60 studs of the lens must be hidden behind solid scenery
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { world() :: Instance }
		local nearest = math.huge
		local bad = {}
		for _, def in Layout.ARENAS do
			for _, theta in { 0, 90, 180, 270 } do
				local cam, fov = fightCamera(def, theta)
				for _, other in Layout.ARENAS do
					if other.id ~= def.id then
						for _, h in { 0, 3 } do
							local target = other.origin + Vector3.new(0, h, 0)
							local v = CameraDirector._normalizedViewportPoint(cam, fov, 16 / 9, target)
							local range = (target - cam.Position).Magnitude
							if v and v.X >= 0.2 and v.X <= 0.8 and v.Y >= 0.2 and v.Y <= 0.8 then
								nearest = math.min(nearest, range)
								if range <= 60 then
									local hit = workspace:Raycast(cam.Position, (target - cam.Position) * 0.97, params)
									if not (hit and hit.Instance.Transparency < 0.5) then
										table.insert(bad, string.format("%s %d: %s at %.1f studs (%.2f, %.2f)", def.id, theta, other.id, range, v.X, v.Y))
									end
								end
							end
						end
					end
				end
			end
		end
		local w = world() :: Instance
		w:SetAttribute("NearestCentralArena", if nearest == math.huge then -1 else math.floor(nearest * 10 + 0.5) / 10)
		expect.equal(#bad, 0, "other arenas in the fight frame: " .. table.concat(bad, "; "))
	end)

	for _, def in Layout.ARENAS do
		t.test("pads of " .. def.id .. " are a short walk from every spawn", function()
			local model = arenaModel(def.id) :: Model
			local list = spawns()
			local worst = 0
			local mine = {}
			for _, name in padNames(def) do
				local pad = model:FindFirstChild(name) :: BasePart
				for k, s in list do
					local d = walkDistance(s.Position + Vector3.new(0, 3, 0), pad.Position + Vector3.new(0, 3, 0))
					expect.truthy(d, string.format("%s: no walking path from spawn %d to %s", def.id, k, name))
					walks[walkKey(k, def.id, name)] = d :: number
					table.insert(mine, d :: number)
					worst = math.max(worst, d :: number)
					expect.truthy((d :: number) <= WALK_WORST, string.format("%s: spawn %d -> %s is %.1f studs of path", def.id, k, name, d :: number))
				end
			end
			model:SetAttribute("WorstWalk", math.floor(worst * 10 + 0.5) / 10)
			model:SetAttribute("MedianWalk", math.floor(median(mine) * 10 + 0.5) / 10)
		end)
	end

	t.test("the median walk from a spawn to a pad is at most 30 studs", function()
		local all = {}
		local list = spawns()
		for _, def in Layout.ARENAS do
			local model = arenaModel(def.id) :: Model
			for _, name in padNames(def) do
				for k, s in list do
					local key = walkKey(k, def.id, name)
					if walks[key] == nil then
						local pad = model:FindFirstChild(name) :: BasePart
						walks[key] = walkDistance(s.Position + Vector3.new(0, 3, 0), pad.Position + Vector3.new(0, 3, 0)) or math.huge
					end
					table.insert(all, walks[key])
				end
			end
		end
		local m = median(all)
		local w = world() :: Instance
		w:SetAttribute("MedianWalk", math.floor(m * 10 + 0.5) / 10)
		expect.truthy(#all == #list * 10, "every spawn -> pad pair measured")
		expect.truthy(m <= WALK_MEDIAN, string.format("median walk %.1f studs over %d spawn -> pad pairs", m, #all))
	end)

	-- soft ground cover (snow drifts, moss, lawns, sand) may wrap round anything standing in it
	local SOFT = {
		[Enum.Material.Snow] = true,
		[Enum.Material.LeafyGrass] = true,
		[Enum.Material.Grass] = true,
		[Enum.Material.Sand] = true,
		[Enum.Material.Ground] = true,
		[Enum.Material.Mud] = true,
	}
	local VEGETATION = { Tree = true, Palm = true, Pine = true }

	t.test("no piece clips into another section (each arena, the lobby, the grounds, the seascape)", function()
		local w = world() :: Instance
		local sections: { Instance } = {}
		for _, m in (w:FindFirstChild("Arenas") :: Instance):GetChildren() do
			table.insert(sections, m)
		end
		for _, name in { "Lobby", "Walkways", "Seascape" } do
			local s = w:FindFirstChild(name)
			expect.truthy(s, name .. " section")
			table.insert(sections, s :: Instance)
		end
		local clips: { [string]: boolean } = {}
		local list = {}
		for i, section in sections do
			local others: { Instance } = {}
			for j, s in sections do
				if j ~= i then
					table.insert(others, s)
				end
			end
			local params = OverlapParams.new()
			params.FilterType = Enum.RaycastFilterType.Include
			params.FilterDescendantsInstances = others
			for _, part in section:GetDescendants() do
				-- stairs and podiums stand on the plaza paving (inlays up to 0.25 high), which is fine
				if part:IsA("BasePart") and part.CanQuery and part.Size.Magnitude < 150 and topY(part) > 0.25 and not SOFT[part.Material] then
					for _, hit in workspace:GetPartsInPart(part, params) do
						if topY(hit) > 0.25 and not SOFT[hit.Material] then
							local a, b = part:GetFullName(), hit:GetFullName()
							local key = if a < b then a .. " <-> " .. b else b .. " <-> " .. a
							if not clips[key] then
								clips[key] = true
								table.insert(list, key)
							end
						end
					end
				end
			end
		end
		expect.equal(#list, 0, "clipping pieces: " .. table.concat(list, "; "))
	end)

	t.test("no tree trunk grows through a structure or another trunk", function()
		local w = world() :: Instance
		local list = {}
		for _, model in w:GetDescendants() do
			if model:IsA("Model") and VEGETATION[model.Name] then
				local params = OverlapParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.FilterDescendantsInstances = { model }
				for _, part in model:GetChildren() do
					if part:IsA("BasePart") and part.Material == Enum.Material.Wood and part.CanQuery then
						for _, hit in workspace:GetPartsInPart(part, params) do
							if hit:IsDescendantOf(w) and topY(hit) > 0.25 and not SOFT[hit.Material] then
								table.insert(list, model:GetFullName() .. " <-> " .. hit:GetFullName())
							end
						end
					end
				end
			end
		end
		expect.equal(#list, 0, "trunks through structures: " .. table.concat(list, "; "))
	end)

	t.test("no two visible floor surfaces share a height where they overlap (no z-fighting)", function()
		local w = world() :: Instance
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local found: { [string]: boolean } = {}
		local list = {}
		local R = 200 -- the whole district plus the stages' scenery (dojo hall, port, skyline streets)
		for x = -R, R, 2 do
			for z = -R, R, 2 do
				if x * x + z * z <= R * R then
					local hits: { RaycastResult } = {}
					local exclude: { Instance } = {}
					local origin = Vector3.new(x + 0.37, 60, z + 0.21)
					for _ = 1, 6 do
						params.FilterDescendantsInstances = exclude
						local r = workspace:Raycast(origin, Vector3.new(0, -80, 0), params)
						if not r then
							break
						end
						if r.Instance:IsDescendantOf(w) then
							table.insert(hits, r)
						end
						table.insert(exclude, r.Instance)
						if #hits >= 3 then
							break
						end
					end
					for i = 2, #hits do
						local a, b = hits[i - 1], hits[i]
						if math.abs(a.Position.Y - b.Position.Y) < 0.006 and a.Normal.Y > 0.99 and b.Normal.Y > 0.99
							and a.Instance.Transparency < 0.9 and b.Instance.Transparency < 0.9 then
							local key = a.Instance:GetFullName() .. " = " .. b.Instance:GetFullName()
							if not found[key] then
								found[key] = true
								table.insert(list, string.format("%s at (%d, %d)", key, x, z))
							end
						end
					end
				end
			end
		end
		expect.equal(#list, 0, "coplanar overlapping surfaces: " .. table.concat(list, "; "))
	end)

	t.test("every pocket between the stages is reachable on foot through a walkway at least 5 studs wide", function()
		local Walkways = require(WorldModules.Walkways)
		local from = spawns()[1].Position + Vector3.new(0, 3, 0)
		for _, g in Walkways.GAPS do
			local target = Layout.polar(g.bearing, 76) + Vector3.new(0, 3, 0)
			local path = PathfindingService:CreatePath({ AgentRadius = 2.5, AgentHeight = 5, AgentCanJump = false, WaypointSpacing = 4 })
			local ok = pcall(function()
				path:ComputeAsync(from, target)
			end)
			expect.truthy(ok and path.Status == Enum.PathStatus.Success, g.kind .. " pocket reachable")
			local total = 0
			local points = path:GetWaypoints()
			for i = 2, #points do
				total += (points[i].Position - points[i - 1].Position).Magnitude
			end
			expect.truthy(total <= 125, string.format("%s pocket is %.1f studs of path from the spawn", g.kind, total))
		end
	end)

	t.test("no terrain under the district's hardscape (no grass can poke through)", function()
		local T = workspace.Terrain
		local R = Layout.DISTRICT_RADIUS
		local region = Region3.new(Vector3.new(-R - 4, -8, -R - 4), Vector3.new(R + 4, 8, R + 4)):ExpandToGrid(4)
		local materials, occupancies = T:ReadVoxels(region, 4)
		local size = materials.Size
		local corner = region.CFrame.Position - region.Size / 2
		local solid, grass = 0, 0
		for x = 1, size.X do
			for y = 1, size.Y do
				for z = 1, size.Z do
					local centre = corner + Vector3.new(x - 0.5, y - 0.5, z - 0.5) * 4
					if flat(centre).Magnitude <= R - 3 then
						local mat = materials[x][y][z]
						local occ = occupancies[x][y][z]
						if occ > 0 and mat ~= Enum.Material.Air and mat ~= Enum.Material.Water then
							if mat == Enum.Material.Grass or mat == Enum.Material.LeafyGrass then
								grass += 1
							end
							if centre.Y + occ * 2 > -6 then
								solid += 1
							end
						end
					end
				end
			end
		end
		expect.equal(grass, 0, "grass voxels under the district")
		expect.equal(solid, 0, "terrain rising into the district slab")
		local hit = worldRay(Vector3.new(30, 20, 30), Vector3.new(0, -40, 0), true)
		expect.truthy(hit and hit.Instance ~= T, "the plaza floor, not terrain, is the ground")
	end)

	t.test("part budget, anchoring and build time", function()
		local w = world() :: Instance
		local parts = allParts()
		expect.truthy(#parts <= Layout.PART_BUDGET, "part count " .. #parts .. " within budget")
		expect.truthy(#parts <= PART_CEILING, "part count " .. #parts .. " within main's + 25 % (" .. PART_CEILING .. ")")
		for _, p in parts do
			if not p.Anchored then
				expect.truthy(false, "unanchored part " .. p:GetFullName())
			end
		end
		local seconds = w:GetAttribute("BuildSeconds")
		expect.truthy(typeof(seconds) == "number", "BuildSeconds recorded")
		expect.truthy((seconds :: number) < 1, string.format("build took %.2f s", seconds :: number))
		expect.equal(w:GetAttribute("PartCount"), #parts, "PartCount attribute matches")
		local lights, emitters, shadows = 0, 0, 0
		for _, d in w:GetDescendants() do
			if d:IsA("Light") then
				lights += 1
				if d.Shadows then shadows += 1 end
			elseif d:IsA("ParticleEmitter") then
				emitters += 1
				expect.truthy(d.Rate <= 40, "particle rate kept low: " .. d:GetFullName())
			end
		end
		expect.truthy(lights <= LIGHT_CEILING, "light count " .. lights)
		expect.equal(shadows, 0, "no world light casts shadows")
		expect.truthy(emitters <= 60, "emitter count " .. emitters)
	end)

	t.test("global lighting is the world's golden-hour setup", function()
		local LightingSetup = require(WorldModules.LightingSetup)
		expect.near(Lighting.ClockTime, LightingSetup.properties.ClockTime, 0.01, "ClockTime")
		local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
		expect.truthy(atmosphere and atmosphere:GetAttribute(LightingSetup.ATTRIBUTE), "world atmosphere")
		local sky = Lighting:FindFirstChildOfClass("Sky")
		expect.truthy(sky and sky:GetAttribute(LightingSetup.ATTRIBUTE), "world sky")
		local skies = 0
		for _, c in Lighting:GetChildren() do
			if c:IsA("Sky") then
				skies += 1
			end
		end
		expect.equal(skies, 1, "exactly one sky")
		local a = Lighting.Ambient
		expect.truthy((a.R + a.G + a.B) / 3 > 0.25, "ambient keeps shadows readable")
	end)

	-- Ceilings from the OV6 round-2 exposure pass (fighters measured from the real fight camera: p95 luma <= 235 and
	-- < 0.5 % near-white with the palest and darkest fighters in every arena). Raising any of these blew pale skin
	-- and platinum hair out to white in the dojo, so they are pinned here.
	t.test("fight exposure stays inside the measured ceilings (no blown-out fighters)", function()
		local LightingSetup = require(WorldModules.LightingSetup)
		expect.truthy(Lighting.ExposureCompensation <= 0, "exposure compensation <= 0 (was +0.15 when fighters clipped)")
		expect.truthy(Lighting.Brightness <= 3.5, "sun brightness <= 3.5")
		local bloom = Lighting:FindFirstChild("FightingLabWorldBloom") :: BloomEffect?
		expect.truthy(bloom and bloom:IsA("BloomEffect"), "world bloom")
		expect.truthy((bloom :: BloomEffect).Threshold >= 2, "bloom only on true highlights (threshold >= 2)")
		expect.truthy((bloom :: BloomEffect).Intensity <= 0.4, "bloom intensity <= 0.4")
		local grade = Lighting:FindFirstChild("FightingLabWorldGrade") :: ColorCorrectionEffect?
		expect.truthy(grade and grade:IsA("ColorCorrectionEffect"), "world grade")
		expect.truthy((grade :: ColorCorrectionEffect).Brightness <= 0.01, "grade adds no brightness")
		expect.truthy((grade :: ColorCorrectionEffect).Contrast <= 0.06, "grade contrast <= 0.06")
		expect.near(LightingSetup.bloom.Threshold, (bloom :: BloomEffect).Threshold, 1e-3, "applied bloom matches the setup")
		-- looking into the low sun: sun rays drew an orange veil over the fight (fighters lost contrast)
		local rays = Lighting:FindFirstChild("FightingLabWorldSunRays") :: SunRaysEffect?
		expect.truthy(rays == nil or rays.Intensity <= 0.03, "sun rays stay a trace (<= 0.03)")
		local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
		expect.truthy(atmosphere and atmosphere.Glare <= 0.3, "atmosphere glare <= 0.3")
		-- every arena's stage spots: soft keys only, and none of them reaches past the stage
		local w = world() :: Instance
		for _, def in Layout.ARENAS do
			local model = arenaModel(def.id) :: Model
			local spots = 0
			for _, d in model:GetDescendants() do
				if d:IsA("SpotLight") and d:FindFirstAncestor("StageLights") then
					spots += 1
					expect.truthy(d.Brightness <= 0.6, string.format("%s stage spot brightness %.2f <= 0.6", def.id, d.Brightness))
					expect.truthy(d.Range <= Layout.STAGE_SPOT_RANGE + 1e-3, def.id .. " stage spot range")
				end
			end
			expect.truthy(spots == 0 or spots == 4, def.id .. " has no or four stage spots")
		end
		-- no other light in the world (lamps, signs, fires) adds more than a soft glow to a fight floor
		for _, def in Layout.ARENAS do
			local centre = def.origin + Vector3.new(0, 3, 0)
			for _, d in w:GetDescendants() do
				if d:IsA("Light") and d.Enabled and not d:FindFirstAncestor("StageLights") then
					local holder = d.Parent
					if holder and holder:IsA("BasePart") and (holder.Position - centre).Magnitude < d.Range then
						expect.truthy(d.Brightness <= 3, "strong light reaching the fight of " .. def.id .. ": " .. d:GetFullName())
					end
				end
			end
		end
	end)

	t.test("signage text is sized to read (scaled, or a fixed size of at least 18 px)", function()
		local w = world() :: Instance
		local labels = 0
		for _, d in w:GetDescendants() do
			if d:IsA("TextLabel") then
				labels += 1
				expect.truthy(d.TextScaled or d.TextSize >= 18, "tiny sign text: " .. d:GetFullName())
			end
		end
		expect.truthy(labels > 20, "world has signage")
	end)

	t.test("pad light columns stay off for busy arenas, occupied pads and nearby cameras", function()
		local LobbyAmbience = require(ReplicatedStorage.FightingLab.Client.LobbyAmbience)
		expect.truthy(LobbyAmbience.columnVisible(nil, false, 60, 0), "free pad seen from afar (no station yet)")
		expect.truthy(LobbyAmbience.columnVisible("Open", false, 60, 0), "open arena")
		expect.truthy(LobbyAmbience.columnVisible("Waiting", false, 60, 0), "free pad of a waiting arena beckons")
		expect.falsy(LobbyAmbience.columnVisible("Waiting", true, 60, 0), "occupied pad")
		for _, state in { "Countdown", "Fighting", "Results" } do
			expect.falsy(LobbyAmbience.columnVisible(state, false, 60, 0), state)
		end
		expect.falsy(LobbyAmbience.columnVisible("Open", false, 10, 2), "camera next to the pad")
		expect.truthy(LobbyAmbience.columnVisible("Open", false, 10, 30), "camera high above the pad")
		expect.falsy(LobbyAmbience.columnVisible("Open", false, 60, 0, true), "every column hides while the local player fights")
		local columns = 0
		for _, beam in CollectionService:GetTagged("FightingLabPadColumn") do
			if beam:IsDescendantOf(world() :: Instance) then
				columns += 1
				local pad = beam.Parent :: Instance
				expect.truthy(pad.Parent and pad.Parent:GetAttribute("ArenaId"), "column pad belongs to an arena: " .. beam:GetFullName())
				expect.truthy(pad:GetAttribute("PadSide") or pad:GetAttribute("PadMode"), "column pad has a slot: " .. beam:GetFullName())
			end
		end
		expect.equal(columns, 10, "one column per pad")
	end)
end
