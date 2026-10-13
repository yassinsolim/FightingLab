--!strict
-- Client-only life for the lobby world (started by LightingProfile.apply at client start): duel pads breathe,
-- beacons blink, fires and lanterns flicker, the Ember Beacon's orbit rings and the lighthouse beam turn, and each
-- arena gets a positional ambient loop (re-using the stage ambience sounds already in the game). Pad light columns
-- hide near the camera, on occupied pads, while their arena's station is mid-match and while the local player fights
-- or practises. Cosmetic only.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local M = {}

local TAG_PAD = "FightingLabPadGlow"
local TAG_COLUMN = "FightingLabPadColumn"
local TAG_BLINK = "FightingLabWorldBlink"
local TAG_FLICKER = "FightingLabWorldFlicker"
local TAG_SPIN = "FightingLabWorldSpin"

-- a pad's light column guides people from afar; it is hidden once the camera is this close (it would fill the view)
local COLUMN_HIDE_DISTANCE = 18
-- station states (ReplicatedStorage.FightingLab.Stations.<ArenaId>.State, set by the duel server) in which the
-- arena is mid-match: its columns stay off so the fight camera is clean
local BUSY_STATES = { Countdown = true, Fighting = true, Results = true }

type Pulse = { inst: Instance, base: number, phase: number }
type Spinner = { inst: PVInstance, pivot: CFrame, speed: number }
type Column = { beam: Beam, at: Vector3, arenaId: string?, slot: number }

local started = false
local connection: RBXScriptConnection? = nil
local lab: Instance? = nil
local pulses: { Pulse } = {}
local columns: { Column } = {}
local blinks: { { inst: Instance, period: number, phase: number } } = {}
local flickers: { { light: Light, base: number, seed: number } } = {}
local spinners: { Spinner } = {}
local sounds: { Sound } = {}

local function within(inst: Instance, root: Instance): boolean
	return inst:IsDescendantOf(root)
end

local function collect(world: Instance)
	table.clear(pulses)
	table.clear(columns)
	table.clear(blinks)
	table.clear(flickers)
	table.clear(spinners)
	for _, inst in CollectionService:GetTagged(TAG_COLUMN) do
		if within(inst, world) and inst:IsA("Beam") then
			local holder = inst.Parent
			local column: Column = { beam = inst, at = Vector3.zero, arenaId = nil, slot = 0 }
			if holder and holder:IsA("BasePart") then
				column.at = holder.Position
				local arenaId = holder.Parent and holder.Parent:GetAttribute("ArenaId")
				column.arenaId = if typeof(arenaId) == "string" then arenaId else nil
				local side, mode = holder:GetAttribute("PadSide"), holder:GetAttribute("PadMode")
				column.slot = if typeof(side) == "number" then side elseif mode == "Training" then 1 elseif mode == "Cpu" then 2 else 0
			end
			table.insert(columns, column)
		end
	end
	for _, inst in CollectionService:GetTagged(TAG_PAD) do
		if within(inst, world) then
			local base = if inst:IsA("BasePart") then inst.Transparency elseif inst:IsA("Light") then inst.Brightness else 0
			table.insert(pulses, { inst = inst, base = base, phase = (inst:GetFullName():len() % 7) * 0.9 })
		end
	end
	for _, inst in CollectionService:GetTagged(TAG_BLINK) do
		if within(inst, world) then
			table.insert(blinks, { inst = inst, period = inst:GetAttribute("Period") or 1.5, phase = math.random() })
		end
	end
	for _, inst in CollectionService:GetTagged(TAG_FLICKER) do
		if within(inst, world) and inst:IsA("Light") then
			table.insert(flickers, { light = inst, base = inst.Brightness, seed = math.random() * 100 })
		end
	end
	for _, inst in CollectionService:GetTagged(TAG_SPIN) do
		if within(inst, world) and inst:IsA("PVInstance") then
			table.insert(spinners, { inst = inst, pivot = inst:GetPivot(), speed = inst:GetAttribute("SpinSpeed") or 0.5 })
		end
	end
	-- the beacon's orbit rings are models flagged with SpinSpeed
	for _, d in world:GetDescendants() do
		if d:IsA("Model") and string.sub(d.Name, 1, 9) == "OrbitRing" then
			table.insert(spinners, { inst = d, pivot = d:GetPivot(), speed = d:GetAttribute("SpinSpeed") or 0.3 })
		end
	end
end

local function startSounds(world: Instance)
	for _, s in sounds do
		s:Destroy()
	end
	table.clear(sounds)
	local stages = lab and lab:FindFirstChild("Stages")
	local arenas = world:FindFirstChild("Arenas")
	if not (stages and arenas) then
		return
	end
	for _, arena in arenas:GetChildren() do
		local stageId = arena:GetAttribute("StageId")
		local origin = arena:FindFirstChild("FightOrigin")
		local stage = if typeof(stageId) == "string" then stages:FindFirstChild(stageId) else nil
		local folder = stage and stage:FindFirstChild("Ambience")
		local source = folder and folder:FindFirstChildOfClass("Sound")
		if source and origin and origin:IsA("BasePart") then
			local s = source:Clone()
			s.Name = "LobbyAmbience"
			s.Looped = true
			s.Volume = math.clamp(source.Volume * 2.2, 0.2, 0.7)
			-- compact horseshoe (stages 66 studs from the plaza centre, 62 apart): each loop is full on its own stage and
			-- has faded out before the plaza centre and the neighbouring stages, so the five loops never pile up
			s.RollOffMode = Enum.RollOffMode.InverseTapered
			s.RollOffMinDistance = 14
			s.RollOffMaxDistance = 52
			s.Parent = origin
			s:Play()
			table.insert(sounds, s)
		end
	end
end

-- Whether a pad's light column shows: never while its arena is mid-match or someone holds the pad (the free pad keeps
-- beckoning an opponent), not when the camera is close to it, and none at all while the local player fights or
-- practises (the stages are close together, so other arenas' columns would stand in the fight camera's background).
function M.columnVisible(state: string?, occupied: boolean, flatDistance: number, heightDelta: number, localFight: boolean?): boolean
	if localFight or (state and BUSY_STATES[state]) or occupied then
		return false
	end
	return flatDistance > COLUMN_HIDE_DISTANCE or math.abs(heightDelta) > 14
end

-- The local player's duel states in which the fight camera is up.
local LOCAL_FIGHT_STATES = { Fighting = true, Results = true, Practice = true }

local function station(arenaId: string?): Instance?
	local stations = lab and lab:FindFirstChild("Stations")
	return if stations and arenaId then stations:FindFirstChild(arenaId) else nil
end

local function step(now: number)
	local camera = workspace.CurrentCamera
	if camera then
		local cam = camera.CFrame.Position
		local player = Players.LocalPlayer
		local duel = player and player:GetAttribute("DuelState")
		local localFight = typeof(duel) == "string" and LOCAL_FIGHT_STATES[duel] == true
		for _, c in columns do
			local st = station(c.arenaId)
			local state = st and st:GetAttribute("State")
			local occupant = if st and c.slot > 0 then st:GetAttribute(if c.slot == 1 then "P1UserId" else "P2UserId") else nil
			local flat = Vector3.new(cam.X - c.at.X, 0, cam.Z - c.at.Z).Magnitude
			local show = M.columnVisible(
				if typeof(state) == "string" then state else nil,
				typeof(occupant) == "number" and occupant ~= 0,
				flat,
				cam.Y - c.at.Y,
				localFight
			)
			if c.beam.Enabled ~= show then
				c.beam.Enabled = show
			end
		end
	end
	for _, p in pulses do
		local wave = (math.sin(now * 2.4 + p.phase) + 1) * 0.5
		local inst = p.inst
		if inst:IsA("BasePart") then
			inst.Transparency = math.clamp(p.base - 0.12 + wave * 0.24, 0, 1)
		elseif inst:IsA("Light") then
			inst.Brightness = p.base * (0.75 + wave * 0.5)
		end
	end
	for _, b in blinks do
		local on = ((now / b.period + b.phase) % 1) < 0.5
		local inst = b.inst
		-- a LocalTransparencyModifier of exactly 1 means StageController hid this piece for a local fight: leave it
		if inst:IsA("BasePart") then
			if inst.LocalTransparencyModifier < 1 then inst.LocalTransparencyModifier = if on then 0 else 0.85 end
		elseif inst:IsA("Light") then
			local holder = inst.Parent
			if not (holder and holder:IsA("BasePart") and holder.LocalTransparencyModifier >= 1) then inst.Enabled = on end
		end
	end
	for _, f in flickers do
		local n = (math.noise(now * 7, f.seed) + 1) * 0.5
		f.light.Brightness = f.base * (0.7 + n * 0.5)
	end
	for _, s in spinners do
		if s.inst.Parent then
			s.inst:PivotTo(s.pivot * CFrame.Angles(0, now * s.speed, 0))
		end
	end
end

function M.start()
	if started then
		return
	end
	started = true
	local folder = ReplicatedStorage:WaitForChild("FightingLab")
	lab = folder
	local ready = folder:WaitForChild("WorldReady", 60)
	local world = workspace:WaitForChild("FightingLabWorld", 30)
	if not (ready and world) then
		started = false
		return
	end
	collect(world)
	startSounds(world)
	local accumulator = 0
	connection = RunService.RenderStepped:Connect(function(dt)
		accumulator += dt
		if accumulator < 1 / 30 then
			return
		end
		accumulator = 0
		step(os.clock())
	end)
end

function M.stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	for _, s in sounds do
		s:Destroy()
	end
	table.clear(sounds)
	started = false
end

function M.isRunning(): boolean
	return started and connection ~= nil
end

return M
