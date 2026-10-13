--!strict
-- FightingLab client bootstrap (contract v5). The game opens in the lobby world: the player walks as their fighter
-- with normal Roblox controls and camera, and no fight rig, fight HUD or fight input is active. FightSession switches
-- the presentation modules into fight mode for server duels (60 Hz snapshots) and local practice (local runner), in
-- arena space around the arena's FightOrigin, and back to the lobby afterwards.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Lab = ReplicatedStorage:WaitForChild("FightingLab")
local Config = require(Lab:WaitForChild("CombatConfig"))
local Roster = require(Lab:WaitForChild("Roster"))
local Client = Lab:WaitForChild("Client")

-- First: hide every character that appears on this client until it is dressed and its assets are loaded.
local AvatarGate = require(Client:WaitForChild("AvatarGate"))
AvatarGate.start()

local function optional(name: string): any
	local module = Client:FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok then return result end
		warn("FightingLab: could not load optional client module " .. name .. ": " .. tostring(result))
	end
	return nil
end

local Modules: { [string]: any } = {
	FightSession = require(Client:WaitForChild("FightSession")),
	Input = require(Client:WaitForChild("InputController")),
	Hud = require(Client:WaitForChild("HudController")),
	Camera = require(Client:WaitForChild("CameraDirector")),
	Characters = require(Client:WaitForChild("CharacterPresenter")),
	Effects = require(Client:WaitForChild("EffectsController")),
	Audio = require(Client:WaitForChild("AudioController")),
	Stage = require(Client:WaitForChild("StageController")),
	FrontEnd = require(Client:WaitForChild("FrontEnd")),
}
Modules.FighterLighting = optional("FighterLighting")
Modules.Spectator = optional("SpectatorPresenter")
Modules.AvatarGate = AvatarGate

local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "FightingLabHUD"
gui.ResetOnSpawn = false
gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
gui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local session = Modules.FightSession
local ctx = {
	send = function(kind: string, a: any?, b: any?, slot: number?) session.send(kind, a, b, slot) end,
	setHuman = function(slot: number, isHuman: boolean) session.setHuman(slot, isHuman) end,
	config = Config,
	gui = gui,
	modules = Modules,
}

-- Lighting belongs to the world (set on the server and replicated). LightingProfile.apply() (world agent) only clears
-- stale client-side effects, neutralises legacy stage presets and starts LobbyAmbience; it never sets global lighting.
do
	local lightingProfile = Client:FindFirstChild("LightingProfile")
	if lightingProfile and lightingProfile:IsA("ModuleScript") then
		local ok, err = pcall(function() (require(lightingProfile) :: any).apply() end)
		if not ok then warn("FightingLab: LightingProfile.apply failed: " .. tostring(err)) end
	end
end
for _, name in { "AvatarGate", "FightSession", "Hud", "Input", "Stage", "Characters", "Camera", "Effects", "Audio", "FighterLighting", "Spectator", "FrontEnd" } do
	local module = Modules[name]
	if module and module.init then
		local ok, err = pcall(module.init, ctx)
		if not ok then warn("FightingLab: " .. name .. ".init failed: " .. tostring(err)) end
	end
end
Modules.Input.bindMenu(function(_action: string) end)
do
	local ok, err = pcall(Modules.FrontEnd.start)
	if not ok then warn("FightingLab: FrontEnd.start failed: " .. tostring(err)) end
end

-- Fight rigs are cloned once and pooled (layered clothing refits when a clone appears; the pool keeps that away
-- from fight starts and previews). Templates may be rebuilt by the server at startup, so wait for the flag without
-- blocking the lobby.
task.spawn(function()
	local ready = Lab:WaitForChild("TemplatesReady", 120)
	if ready and ready:IsA("BoolValue") then
		while not ready.Value do ready.Changed:Wait() end
	else
		warn("FightingLab: TemplatesReady flag missing; pooling the saved fighter templates")
	end
	if Modules.Characters.prewarm then Modules.Characters.prewarm(Roster.order) end
end)

if RunService:IsStudio() then
	-- Studio-only review hook: FightingLabHUD.DebugP1Cpu = true lets the CPU drive P1 in practice (CPU vs CPU).
	gui:GetAttributeChangedSignal("DebugP1Cpu"):Connect(function()
		session.setHuman(1, gui:GetAttribute("DebugP1Cpu") ~= true)
	end)
	-- Studio-only measurement hook: toggling FightingLabHUD.ResetLatency clears latency/starvation statistics.
	gui:GetAttributeChangedSignal("ResetLatency"):Connect(function() session.resetLatency() end)
	-- Studio-only practice hook: FightingLabHUD.DebugPractice = "Kind[,arg]" calls FightSession.practiceCommand.
	gui:GetAttributeChangedSignal("DebugPractice"):Connect(function()
		local value = gui:GetAttribute("DebugPractice")
		if typeof(value) ~= "string" then return end
		local kind, arg = string.match(value, "^([^,]+),?(.*)$")
		if kind then gui:SetAttribute("DebugPracticeResult", session.practiceCommand(kind, if arg ~= "" then arg else nil)) end
	end)
end

local lobbyFrame = {
	now = 0, dt = 0, renderFrame = 0, config = Config, fighters = {}, entry = nil, mode = "Lobby", phase = "Lobby",
	timer = 0, scores = { 0, 0 }, round = 0, winner = 0, reason = "", sparring = false, ko = false, paused = false,
	hitstop = 0, origin = Vector3.zero, viewSlot = 1, session = "Lobby", lobby = true,
}

local function safeUpdate(name: string, frame: any)
	local module = Modules[name]
	if module and module.update then
		local ok, err = pcall(module.update, frame)
		if not ok then warn("FightingLab: " .. name .. ".update failed: " .. tostring(err)) end
	end
end

RunService.RenderStepped:Connect(function(dt: number)
	local frame = session.step(dt)
	if frame then
		for _, name in { "Stage", "Characters", "FighterLighting", "Camera", "Effects", "Audio", "Hud" } do safeUpdate(name, frame) end
	end
	if Modules.Spectator then safeUpdate("Spectator", frame or lobbyFrame) end
	if frame then
		safeUpdate("FrontEnd", frame)
	else
		lobbyFrame.now = workspace:GetServerTimeNow()
		lobbyFrame.dt = dt
		lobbyFrame.session = session.state()
		safeUpdate("FrontEnd", lobbyFrame)
	end
end)
