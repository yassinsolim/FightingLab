--!strict
-- Studio-only stand-in for the world agent's workspace.FightingLabWorld (contract v5 section 3) so the duel system can
-- be tested without the real world: a plaza with a LobbySpawn, kiosk and leaderboard, one duel arena and the practice
-- dojo, connected by walkways. FightingLabServer builds it only in Studio and only when neither the real world nor
-- ServerScriptService.FightingLabWorldBoot exists.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DevWorld = {}
DevWorld.DuelOrigin = Vector3.new(0, 0, -190)
DevWorld.DojoOrigin = Vector3.new(0, 0, 190)

local function block(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.Concrete
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function marker(parent: Instance, name: string, position: Vector3): Part
	local p = block(parent, name, Vector3.new(1, 1, 1), CFrame.new(position), Color3.new(1, 1, 1))
	p.Transparency = 1
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

local function pad(parent: Instance, name: string, position: Vector3, color: Color3): Part
	local p = block(parent, name, Vector3.new(0.4, 7, 7), CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.Material.Neon)
	p.Shape = Enum.PartType.Cylinder
	p:SetAttribute("PadRadius", 3.5)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 10
	light.Brightness = 1.2
	light.Parent = p
	return p
end

local function statusBoard(parent: Instance, position: Vector3, facing: Vector3): Part
	local board = block(parent, "StatusBoard", Vector3.new(16, 9, 0.6), CFrame.lookAt(position, position + facing), Color3.fromRGB(20, 24, 32), Enum.Material.SmoothPlastic)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "StatusGui"
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.Parent = board
	return board
end

local function arena(parent: Instance, id: string, stageId: string, displayName: string, kind: string, order: number, origin: Vector3): Model
	local model = Instance.new("Model")
	model.Name = id
	model:SetAttribute("ArenaId", id)
	model:SetAttribute("StageId", stageId)
	model:SetAttribute("DisplayName", displayName)
	model:SetAttribute("Kind", kind)
	model:SetAttribute("Order", order)
	local floor = block(model, "Floor", Vector3.new(112, 2, 112), CFrame.new(origin - Vector3.new(0, 1, 0)), Color3.fromRGB(92, 98, 110), Enum.Material.Slate)
	floor:SetAttribute("DevStub", true)
	local ring = block(model, "FightRing", Vector3.new(0.2, 46, 46), CFrame.new(origin + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(128, 120, 104), Enum.Material.WoodPlanks)
	ring.Shape = Enum.PartType.Cylinder
	ring.CanCollide = false
	local originPart = marker(model, "FightOrigin", origin)
	originPart.Size = Vector3.new(1, 1, 1)
	for i = 0, 3 do
		local angle = math.rad(45 + i * 90)
		local at = origin + Vector3.new(math.cos(angle) * 38, 7, math.sin(angle) * 38)
		local pillar = block(model, "Pillar" .. i, Vector3.new(3, 14, 3), CFrame.new(at), Color3.fromRGB(150, 140, 128), Enum.Material.Brick)
		CollectionService:AddTag(pillar, "FightingLabCameraOccluder")
		local lamp = Instance.new("PointLight")
		lamp.Range = 22
		lamp.Brightness = 1.4
		lamp.Color = Color3.fromRGB(255, 226, 180)
		lamp.Parent = pillar
		if i == 0 then
			CollectionService:AddTag(pillar, "FightingLabFlicker")
			pillar:SetAttribute("FlickerMin", 0.6)
		end
	end
	if kind == "Duel" then
		local p1 = pad(model, "PadP1", origin + Vector3.new(-27, 0, 0), Color3.fromRGB(255, 122, 64))
		p1:SetAttribute("PadSide", 1)
		local p2 = pad(model, "PadP2", origin + Vector3.new(27, 0, 0), Color3.fromRGB(70, 190, 255))
		p2:SetAttribute("PadSide", 2)
		marker(model, "ExitP1", origin + Vector3.new(-33, 0.5, 0))
		marker(model, "ExitP2", origin + Vector3.new(33, 0.5, 0))
	else
		local training = pad(model, "PadTraining", origin + Vector3.new(-27, 0, 0), Color3.fromRGB(120, 235, 150))
		training:SetAttribute("PadMode", "Training")
		local cpu = pad(model, "PadCpu", origin + Vector3.new(27, 0, 0), Color3.fromRGB(255, 205, 90))
		cpu:SetAttribute("PadMode", "Cpu")
		marker(model, "ExitTraining", origin + Vector3.new(-33, 0.5, 0))
		marker(model, "ExitCpu", origin + Vector3.new(33, 0.5, 0))
	end
	local towardPlaza = Vector3.new(-origin.X, 0, -origin.Z).Unit
	statusBoard(model, origin - towardPlaza * 44 + Vector3.new(0, 9, 0), towardPlaza)
	model.Parent = parent
	return model
end

function DevWorld.build(): Folder
	local world = Instance.new("Folder")
	world.Name = "FightingLabWorld"
	world:SetAttribute("DevStub", true)
	local lobby = Instance.new("Model")
	lobby.Name = "Lobby"
	block(lobby, "Plaza", Vector3.new(130, 2, 130), CFrame.new(0, -1, 0), Color3.fromRGB(150, 146, 136), Enum.Material.Pavement)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.CFrame = CFrame.new(0, 0.5, 0)
	spawn.Neutral = true
	spawn.Enabled = true
	spawn.Duration = 0
	spawn.Material = Enum.Material.Marble
	spawn.Color = Color3.fromRGB(230, 226, 214)
	spawn.Parent = lobby
	local kiosk = Instance.new("Model")
	kiosk.Name = "FighterKiosk"
	block(kiosk, "Base", Vector3.new(4, 5, 2), CFrame.new(16, 2.5, 0), Color3.fromRGB(60, 70, 90), Enum.Material.Metal)
	local promptPart = block(kiosk, "PromptPart", Vector3.new(3, 2, 0.4), CFrame.new(16, 5.6, -1.1), Color3.fromRGB(90, 200, 255), Enum.Material.Neon)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ChooseFighter"
	prompt.ActionText = "Choose Fighter"
	prompt.ObjectText = "Fighters"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = promptPart
	kiosk.Parent = lobby
	local board = block(lobby, "Leaderboard", Vector3.new(12, 9, 0.6), CFrame.lookAt(Vector3.new(-22, 6, 24), Vector3.new(-22, 6, 0)), Color3.fromRGB(20, 24, 32), Enum.Material.SmoothPlastic)
	local boardGui = Instance.new("SurfaceGui")
	boardGui.Name = "LeaderboardGui"
	boardGui.Face = Enum.NormalId.Front
	boardGui.LightInfluence = 0
	boardGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	boardGui.PixelsPerStud = 66
	boardGui.Parent = board
	block(lobby, "WalkwayNorth", Vector3.new(16, 2, 74), CFrame.new(0, -1, -100), Color3.fromRGB(128, 124, 116), Enum.Material.Cobblestone)
	block(lobby, "WalkwaySouth", Vector3.new(16, 2, 74), CFrame.new(0, -1, 100), Color3.fromRGB(128, 124, 116), Enum.Material.Cobblestone)
	block(lobby, "WalkwayEast", Vector3.new(74, 2, 16), CFrame.new(100, -1, 0), Color3.fromRGB(128, 124, 116), Enum.Material.Cobblestone)
	block(lobby, "WalkwayWest", Vector3.new(74, 2, 16), CFrame.new(-100, -1, 0), Color3.fromRGB(128, 124, 116), Enum.Material.Cobblestone)
	lobby.Parent = world
	local arenas = Instance.new("Folder")
	arenas.Name = "Arenas"
	arena(arenas, "Arena_MidnightRooftop", "MidnightRooftop", "Midnight Rooftop", "Duel", 1, DevWorld.DuelOrigin)
	arena(arenas, "Arena_HarborDusk", "HarborDusk", "Harbor Dusk", "Duel", 2, Vector3.new(190, 0, 0))
	arena(arenas, "Arena_JungleRuins", "JungleRuins", "Jungle Ruins", "Duel", 3, Vector3.new(-190, 0, 0))
	arena(arenas, "Arena_SnowSummit", "SnowSummit", "Summit Observatory", "Duel", 4, Vector3.new(150, 0, 150))
	arena(arenas, "Arena_TrainingBay", "TrainingBay", "Training Bay", "Practice", 5, DevWorld.DojoOrigin)
	arenas.Parent = world
	world.Parent = workspace
	-- Readable daylight for the stand-in only (the real world owns global lighting).
	local Lighting = game:GetService("Lighting")
	Lighting.ClockTime = 16.6
	Lighting.Brightness = 2.6
	Lighting.Ambient = Color3.fromRGB(70, 72, 82)
	Lighting.OutdoorAmbient = Color3.fromRGB(128, 124, 120)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	Lighting.ExposureCompensation = 0
	local lab = ReplicatedStorage:WaitForChild("FightingLab")
	local ready = lab:FindFirstChild("WorldReady") or Instance.new("BoolValue")
	ready.Name = "WorldReady"
	ready:SetAttribute("DevStub", true)
	ready.Parent = lab;
	(ready :: BoolValue).Value = true
	return world
end

return DevWorld
