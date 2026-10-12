--!strict
-- Reads the world contract (v5 section 3) into plain data the DuelService can use and tests can fake:
-- arenas with fight origins, duel pads, practice pads, exits, plus the lobby spawn points.
export type Pad = { part: BasePart?, position: Vector3, radius: number, side: number, mode: string? }
export type Arena = {
	id: string, stageId: string, displayName: string, kind: string, order: number, model: Model?,
	origin: Vector3, pads: { [number]: Pad }, practicePads: { [string]: Pad }, exits: { [string]: CFrame },
	arrival: CFrame?,
}
export type Index = { arenas: { [string]: Arena }, order: { string }, spawns: { BasePart }, world: Instance? }

local WorldIndex = {}
WorldIndex.DefaultPadRadius = 3.5
-- Quick travel without an Arrival part lands this far behind PadP1 / PadTraining (away from the ring).
WorldIndex.ArrivalFallbackDistance = 6
local STAGE_IDS = { MidnightRooftop = true, HarborDusk = true, JungleRuins = true, SnowSummit = true, TrainingBay = true }

local function findPart(root: Instance, name: string): BasePart?
	local inst = root:FindFirstChild(name, true)
	if inst and inst:IsA("BasePart") then return inst end
	return nil
end

-- Returning players stand at the exit marker and face the fight centre.
function WorldIndex.exitFrame(position: Vector3, origin: Vector3): CFrame
	local target = Vector3.new(origin.X, position.Y, origin.Z)
	if (target - position).Magnitude < 0.1 then return CFrame.new(position) end
	return CFrame.lookAt(position, target)
end

-- Standing on a pad, facing the fight centre (quick play drops players here).
function WorldIndex.padFrame(pad: Pad, origin: Vector3): CFrame
	return WorldIndex.exitFrame(pad.position, origin)
end

-- Quick travel destination of an arena: its Arrival part (world, round 5) facing the ring, else a point
-- ArrivalFallbackDistance studs behind PadP1 (duel) or PadTraining (dojo) on the line from the fight origin.
function WorldIndex.arrivalFrame(arena: Arena): CFrame
	if arena.arrival then return WorldIndex.exitFrame(arena.arrival.Position, arena.origin) end
	local pad = arena.pads[1] or arena.practicePads.Training or arena.pads[2] or arena.practicePads.Cpu
	if not pad then return WorldIndex.exitFrame(arena.origin + Vector3.new(0, 0, 30), arena.origin) end
	local out = Vector3.new(pad.position.X - arena.origin.X, 0, pad.position.Z - arena.origin.Z)
	local dir = if out.Magnitude > 0.01 then out.Unit else Vector3.new(0, 0, 1)
	return WorldIndex.exitFrame(pad.position + dir * WorldIndex.ArrivalFallbackDistance, arena.origin)
end

local function padFrom(part: BasePart, side: number, mode: string?): Pad
	local radius = part:GetAttribute("PadRadius")
	return {
		part = part, position = part.Position, side = side, mode = mode,
		radius = if typeof(radius) == "number" and radius > 0 then radius else WorldIndex.DefaultPadRadius,
	}
end

function WorldIndex.scanArena(model: Instance): Arena?
	local originPart = findPart(model, "FightOrigin")
	if not originPart then
		warn("FightingLab WorldIndex: arena " .. model:GetFullName() .. " has no FightOrigin; skipped")
		return nil
	end
	local origin = originPart.Position
	local id = model:GetAttribute("ArenaId")
	local stageId = model:GetAttribute("StageId")
	local kind = model:GetAttribute("Kind")
	local order = model:GetAttribute("Order")
	local displayName = model:GetAttribute("DisplayName")
	local arena: Arena = {
		id = if typeof(id) == "string" and id ~= "" then id else model.Name,
		stageId = if typeof(stageId) == "string" and STAGE_IDS[stageId] then stageId else "MidnightRooftop",
		kind = if kind == "Practice" then "Practice" else "Duel",
		order = if typeof(order) == "number" then order else 99,
		displayName = if typeof(displayName) == "string" then displayName else model.Name,
		model = if model:IsA("Model") then model else nil,
		origin = origin, pads = {}, practicePads = {}, exits = {}, arrival = nil,
	}
	local arrival = findPart(model, "Arrival")
	if arrival then arena.arrival = arrival.CFrame end
	for side = 1, 2 do
		local pad = findPart(model, "PadP" .. side)
		if pad then
			local attr = pad:GetAttribute("PadSide")
			arena.pads[side] = padFrom(pad, if attr == 1 or attr == 2 then attr :: number else side, nil)
		end
		local exit = findPart(model, "ExitP" .. side)
		if exit then arena.exits["P" .. side] = WorldIndex.exitFrame(exit.Position, origin) end
	end
	for _, mode in { "Training", "Cpu" } do
		local pad = findPart(model, "Pad" .. mode)
		if pad then
			local attr = pad:GetAttribute("PadMode")
			arena.practicePads[mode] = padFrom(pad, 0, if attr == "Training" or attr == "Cpu" then attr :: string else mode)
		end
		local exit = findPart(model, "Exit" .. mode)
		if exit then arena.exits[mode] = WorldIndex.exitFrame(exit.Position, origin) end
	end
	if arena.kind == "Duel" and (not arena.pads[1] or not arena.pads[2]) then
		warn("FightingLab WorldIndex: duel arena " .. arena.id .. " is missing PadP1/PadP2")
	end
	return arena
end

function WorldIndex.scan(world: Instance): Index
	local index: Index = { arenas = {}, order = {}, spawns = {}, world = world }
	local arenas = world:FindFirstChild("Arenas")
	if arenas then
		for _, child in arenas:GetChildren() do
			if child:IsA("Model") or child:IsA("Folder") then
				local arena = WorldIndex.scanArena(child)
				if arena and not index.arenas[arena.id] then
					index.arenas[arena.id] = arena
					table.insert(index.order, arena.id)
				end
			end
		end
	end
	table.sort(index.order, function(a, b)
		local x, y = index.arenas[a], index.arenas[b]
		if x.order ~= y.order then return x.order < y.order end
		return a < b
	end)
	local lobby = world:FindFirstChild("Lobby")
	for _, d in (lobby or world):GetDescendants() do
		if d.Name == "LobbySpawn" and d:IsA("BasePart") then table.insert(index.spawns, d) end
	end
	return index
end

-- Inside the pad cylinder (with a small tolerance) and standing roughly on it.
function WorldIndex.onPad(pad: Pad, position: Vector3?, tolerance: number?): boolean
	if not position then return false end
	local dx, dz = position.X - pad.position.X, position.Z - pad.position.Z
	local r = pad.radius + (tolerance or 0.25)
	if dx * dx + dz * dz > r * r then return false end
	local dy = position.Y - pad.position.Y
	return dy >= -1.5 and dy <= 9
end

return WorldIndex
