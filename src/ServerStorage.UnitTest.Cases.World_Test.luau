--!strict
-- World_Test: the lobby world built at server start (ServerScriptService.FightingLabWorldBoot) meets the OV6 world
-- contract: names and attributes, a compact layout (every pad a short walk from the spawn, measured with
-- PathfindingService), a visible edge at the fight radius on every stage, a flat fight floor with nothing but the
-- edge barrier near it, camera-occluder tags, no terrain under the hardscape, part budget and build time.
-- Run in Play on the server (the world exists only at runtime).
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local WorldModules = ServerStorage.FightingLab.World
local Layout = require(WorldModules.Layout)

local STAGE_IDS = { MidnightRooftop = true, HarborDusk = true, JungleRuins = true, SnowSummit = true, TrainingBay = true }

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

	t.test("lobby has spawns facing the district, fighter kiosk prompt, leaderboard and a signpost", function()
		local lobby = (world() :: Instance):FindFirstChild("Lobby") :: Model
		local list = spawns()
		expect.truthy(#list >= 1, "at least one LobbySpawn")
		for _, s in list do
			expect.truthy(s:IsA("SpawnLocation"), "LobbySpawn is a SpawnLocation")
			local sp = s :: SpawnLocation
			expect.truthy(sp.Neutral and sp.Enabled, "spawn neutral and enabled")
			expect.equal(sp.Duration, 0, "no forcefield")
			expect.truthy(sp.Anchored and sp.CanCollide, "spawn anchored and solid")
			expect.truthy(math.abs(topY(sp) - 0.15) < 0.2, "spawn sits on the plaza floor")
			expect.truthy(sp.CFrame.LookVector:Dot(Vector3.new(0, 0, -1)) > 0.98, "spawn faces north into the district")
			expect.truthy(flat(sp.Position).Magnitude < 20, "spawn near the plaza centre")
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
		-- kiosk and Hall of Champions are a few steps from the spawn court
		local court = Vector3.zero
		for _, s in list do
			court += flat(s.Position) / #list
		end
		expect.truthy((flat((promptPart :: BasePart).Position) - court).Magnitude < 25, "kiosk console near the spawns")
		expect.truthy((flat(b.Position) - court).Magnitude < 25, "leaderboard near the spawns")
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

	t.test("pads sit 27 studs from FightOrigin at the front of the stage, outside the edge, top flush with floor + 0.2", function()
		for _, def in Layout.ARENAS do
			local model = arenaModel(def.id) :: Model
			local origin = (model:FindFirstChild("FightOrigin") :: BasePart).Position
			local toPlaza = flat(-origin).Unit
			local right = Vector3.new(-toPlaza.Z, 0, toPlaza.X) * -1
			for i, name in padNames(def) do
				local pad = model:FindFirstChild(name) :: BasePart
				expect.truthy(pad and pad:IsA("BasePart"), def.id .. "." .. name)
				local offset = flat(pad.Position - origin)
				expect.near(offset.Magnitude, Layout.PAD_OFFSET, 0.6, name .. " 27 studs from FightOrigin")
				expect.truthy(offset.Magnitude - Layout.PAD_RADIUS > Layout.RAIL_RADIUS + 0.4, name .. " clear of the edge barrier")
				local angle = math.deg(math.acos(math.clamp(offset.Unit:Dot(toPlaza), -1, 1)))
				expect.truthy(angle < 70, name .. " at the front of the stage (" .. math.floor(angle) .. " deg)")
				expect.truthy((offset:Dot(right) < 0) == (i == 1), name .. " on the expected side (slot 1 left, slot 2 right)")
				expect.near(topY(pad) - origin.Y, 0.2, 0.03, name .. " top = floor + 0.2")
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
		end
	end)

	t.test("exits sit beside their pads on the stage floor, facing the arena", function()
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
				local offset = exit.Position - origin
				expect.near(offset.Y, 0, 0.05, name .. " on the floor top")
				expect.truthy(flat(offset).Magnitude > Layout.RAIL_RADIUS + 1, name .. " outside the fight edge")
				expect.truthy(exit.CFrame.LookVector:Dot(flat(-offset).Unit) > 0.98, name .. " faces the arena")
				local hit = worldRay(exit.Position + Vector3.new(0, 4, 0), Vector3.new(0, -8, 0))
				expect.truthy(hit and math.abs(hit.Position.Y - origin.Y) < 0.1 and hit.Instance.CanCollide, name .. " stands on walkable floor")
			end
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
					local dist = orientedFlatDistance(p, origin)
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
		-- lobby and grounds pieces are not faded by the fight camera, so they keep out of the camera orbit (r 36)
		local w = world() :: Instance
		for _, section in { "Lobby", "Walkways" } do
			for _, p in (w:FindFirstChild(section) :: Instance):GetDescendants() do
				if p:IsA("BasePart") and p.Transparency < 0.99 then
					for _, def in Layout.ARENAS do
						if topY(p) > def.origin.Y + Layout.OCCLUDER_HEIGHT then
							expect.truthy(orientedFlatDistance(p, def.origin) >= 36, def.id .. ": lobby piece inside the camera orbit: " .. p:GetFullName())
						end
					end
				end
			end
		end
	end)

	for _, def in Layout.ARENAS do
		t.test("pads of " .. def.id .. " are a short walk from every spawn", function()
			local model = arenaModel(def.id) :: Model
			local list = spawns()
			local worst = 0
			for _, name in padNames(def) do
				local pad = model:FindFirstChild(name) :: BasePart
				for _, k in { 1, math.ceil(#list / 2), #list } do
					local from = list[k].Position + Vector3.new(0, 3, 0)
					local d = walkDistance(from, pad.Position + Vector3.new(0, 3, 0))
					expect.truthy(d, string.format("%s: no walking path from spawn %d to %s", def.id, k, name))
					worst = math.max(worst, d :: number)
					expect.truthy((d :: number) <= Layout.WALK_BUDGET, string.format("%s: spawn %d -> %s is %.1f studs of path", def.id, k, name, d :: number))
				end
			end
			model:SetAttribute("WorstWalk", math.floor(worst * 10 + 0.5) / 10)
		end)
	end

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
		for _, p in parts do
			if not p.Anchored then
				expect.truthy(false, "unanchored part " .. p:GetFullName())
			end
		end
		local seconds = w:GetAttribute("BuildSeconds")
		expect.truthy(typeof(seconds) == "number", "BuildSeconds recorded")
		expect.truthy((seconds :: number) < 1, string.format("build took %.2f s", seconds :: number))
		expect.equal(w:GetAttribute("PartCount"), #parts, "PartCount attribute matches")
		local lights, emitters = 0, 0
		for _, d in w:GetDescendants() do
			if d:IsA("Light") then
				lights += 1
			elseif d:IsA("ParticleEmitter") then
				emitters += 1
				expect.truthy(d.Rate <= 40, "particle rate kept low: " .. d:GetFullName())
			end
		end
		expect.truthy(lights <= 220, "light count " .. lights)
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
