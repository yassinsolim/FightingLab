--!strict
-- Rebuilds fighter templates whose saved copy no longer matches ServerStorage.FightingLab.CharacterSpecs, then
-- signals readiness. Clients wait for ReplicatedStorage.FightingLab.TemplatesReady (created here at runtime, so a
-- stale "ready" flag can never be saved into the place) before building their render rigs.
-- Characters attributes report the boot: RebuiltTemplates, FailedTemplates, IncompleteTemplates ("Id:assetIds" of
-- authored catalog items that could not be applied) and TemplateBuildSeconds.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Lab = ReplicatedStorage:WaitForChild("FightingLab")
local Characters = Lab:WaitForChild("Characters")
local ServerLab = ServerStorage:WaitForChild("FightingLab")
local Factory = require(ServerLab:WaitForChild("CharacterFactory"))
local Specs = require(ServerLab:WaitForChild("CharacterSpecs"))

local ready = Instance.new("BoolValue")
ready.Name = "TemplatesReady"
ready.Value = false
ready.Parent = Lab

local rebuilt: { string } = {}
local failed: { string } = {}
local incomplete: { string } = {}
local pending = 0
local started = os.clock()

local function rebuild(id: string, hash: string)
	local ok, result = pcall(Factory.build, Specs.specs[id])
	if ok then
		local model = result :: Model
		model.Name = id
		model:SetAttribute("SpecHash", hash)
		local current = Characters:FindFirstChild(id)
		if current then current:Destroy() end
		model.Parent = Characters
		table.insert(rebuilt, id)
		-- A catalog item that could not be applied leaves the fighter half-dressed: surface it (the Factory warns too).
		local missing = model:GetAttribute("MissingAccessories")
		if typeof(missing) == "string" and missing ~= "" then
			table.insert(incomplete, id .. ":" .. missing)
		end
	else
		-- The saved template stays in place so the game remains playable; the failure is reported, not hidden.
		warn(string.format("FightingLab: could not rebuild %s from CharacterSpecs: %s", id, tostring(result)))
		table.insert(failed, id)
	end
	pending -= 1
end

for _, id in Specs.order do
	local hash = Specs.hashes[id]
	local current = Characters:FindFirstChild(id)
	if not (current and current:GetAttribute("SpecHash") == hash) then
		pending += 1
		task.spawn(rebuild, id, hash)
	end
end
while pending > 0 do task.wait() end

table.sort(rebuilt)
table.sort(failed)
table.sort(incomplete)
Characters:SetAttribute("RebuiltTemplates", table.concat(rebuilt, ","))
Characters:SetAttribute("FailedTemplates", table.concat(failed, ","))
Characters:SetAttribute("IncompleteTemplates", table.concat(incomplete, ";"))
Characters:SetAttribute("TemplateBuildSeconds", os.clock() - started)
ready.Value = true
