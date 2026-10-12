--!strict
-- World.Builder: builds workspace.FightingLabWorld (terrain, the district grounds, Ember Square, the five arena stages
-- and the surrounding scenery), tags camera occluders near every fight, then signals
-- ReplicatedStorage.FightingLab.WorldReady (BoolValue = true). Idempotent: an existing world and ready flag are
-- destroyed first. Geometry is built unparented and parented in a few chunks with yields in between, so the server
-- keeps ticking while the world appears.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kit = require(script.Parent.Kit)
local Layout = require(script.Parent.Layout)
local ArenaKit = require(script.Parent.ArenaKit)
local TerrainSetup = require(script.Parent.TerrainSetup)
local Lobby = require(script.Parent.Lobby)
local Walkways = require(script.Parent.Walkways)
local Seascape = require(script.Parent.Seascape)

local Builder = {}

Builder.VERSION = "ov6-world-5"
Builder.WORLD_NAME = "FightingLabWorld"

export type Report = {
	parts: number,
	lights: number,
	emitters: number,
	guis: number,
	beams: number,
	occluders: number,
	seconds: number, -- wall clock, including the frames yielded between chunks
	busySeconds: number, -- build work only
}

Builder.lastReport = nil :: Report?

local function arenaModule(stageId: string): any
	local folder = script.Parent:WaitForChild("Arenas")
	local module = folder:WaitForChild(stageId, 5)
	assert(module and module:IsA("ModuleScript"), "FightingLab world: missing arena module " .. stageId)
	return require(module :: ModuleScript)
end

function Builder.build(): Report
	local started = os.clock()
	Kit.reset()
	local lab = ReplicatedStorage:WaitForChild("FightingLab")
	local oldReady = lab:FindFirstChild("WorldReady")
	if oldReady then
		oldReady:Destroy()
	end
	local old = workspace:FindFirstChild(Builder.WORLD_NAME)
	if old then
		old:Destroy()
	end

	TerrainSetup.build()
	Kit.step()
	local grounds = Walkways.build(nil)
	local lobby = Lobby.build(nil)
	local arenas: { Model } = {}
	for _, def in Layout.ARENAS do
		local model = arenaModule(def.stageId).build(def)
		table.insert(arenas, model)
		Kit.step()
	end
	local seascape = Seascape.build(nil)
	-- the plaza's paving layers and the grounds' lawns and beds are walk-over for PathfindingService (Kit.passThrough)
	Kit.walkOverThin(lobby, 0.3)
	Kit.walkOverThin(grounds, 0.3)

	-- camera occluders: anything taller than floor + 1.5 within radius 46 of a fight centre, from any section
	local occluders = 0
	for i, def in Layout.ARENAS do
		local roots: { Instance } = { arenas[i], grounds, lobby, seascape }
		for j, other in arenas do
			if j ~= i then
				table.insert(roots, other)
			end
		end
		occluders += ArenaKit.tagOccluders(def, roots)
	end

	local world = Instance.new("Folder")
	world.Name = Builder.WORLD_NAME
	world:SetAttribute("Version", Builder.VERSION)
	world.Parent = workspace
	grounds.Parent = world
	Kit.yield()
	lobby.Parent = world
	Kit.yield()
	local arenaFolder = Instance.new("Folder")
	arenaFolder.Name = "Arenas"
	arenaFolder.Parent = world
	for i, model in arenas do
		model.Parent = arenaFolder
		if i % 2 == 0 then
			Kit.yield()
		end
	end
	seascape.Parent = world

	local parts = 0
	for _, d in world:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	local report: Report = {
		parts = parts,
		lights = Kit.stats.lights,
		emitters = Kit.stats.emitters,
		guis = Kit.stats.guis,
		beams = Kit.stats.beams,
		occluders = occluders,
		seconds = os.clock() - started,
		busySeconds = Kit.busySeconds(),
	}
	world:SetAttribute("PartCount", report.parts)
	world:SetAttribute("LightCount", report.lights)
	world:SetAttribute("EmitterCount", report.emitters)
	world:SetAttribute("OccluderCount", report.occluders)
	world:SetAttribute("BuildSeconds", report.seconds)
	world:SetAttribute("BuildBusySeconds", report.busySeconds)
	Builder.lastReport = report

	local ready = Instance.new("BoolValue")
	ready.Name = "WorldReady"
	ready.Value = true
	ready.Parent = lab
	return report
end

return Builder
