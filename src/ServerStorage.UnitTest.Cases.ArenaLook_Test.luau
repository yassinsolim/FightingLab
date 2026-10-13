--!strict
-- Round 6 (look): the arenas' fight look. Every arena has a mood (LightingProfile) inside the readability ceilings, and
-- applying one changes this machine's lighting only until restore() puts every value back; the fight's own floor
-- stack never fades as a camera occluder (the rooftop / summit floors used to fade and wash pink / cyan); the fight
-- light rig keeps its key on the camera side and the rim behind the fighters; and the fight-only sets cover the view
-- of the plaza without ever standing between the fight camera and the fighters.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Lighting = game:GetService("Lighting")
local Client = ReplicatedStorage:WaitForChild("FightingLab"):WaitForChild("Client")
local LightingProfile = require(Client:WaitForChild("LightingProfile"))
local StageController = require(Client:WaitForChild("StageController"))
local WorldModules = ServerStorage:WaitForChild("FightingLab"):WaitForChild("World")
local Layout = require(WorldModules:WaitForChild("Layout"))
local FightSets = require(WorldModules:WaitForChild("FightSets"))
local ArenaKit = require(WorldModules:WaitForChild("ArenaKit"))

local function arenaModel(id: string): Model?
	local w = workspace:FindFirstChild("FightingLabWorld")
	local arenas = w and w:FindFirstChild("Arenas")
	local m = arenas and arenas:FindFirstChild(id)
	return if m and m:IsA("Model") then m else nil
end

local function luma(c: Color3): number return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B end

local function snapshot(): { [string]: any }
	local s: { [string]: any } = {}
	for _, key in LightingProfile.LIGHTING_KEYS do s["Lighting." .. key] = (Lighting :: any)[key] end
	for _, child in Lighting:GetChildren() do
		if child:IsA("Atmosphere") then
			for _, k in { "Density", "Offset", "Color", "Decay", "Glare", "Haze" } do s[child.Name .. "." .. k] = (child :: any)[k] end
		elseif child:IsA("BloomEffect") then
			for _, k in { "Intensity", "Size", "Threshold" } do s[child.Name .. "." .. k] = (child :: any)[k] end
		elseif child:IsA("ColorCorrectionEffect") then
			for _, k in { "Brightness", "Contrast", "Saturation", "TintColor" } do s[child.Name .. "." .. k] = (child :: any)[k] end
		elseif child:IsA("SunRaysEffect") then
			for _, k in { "Intensity", "Spread" } do s[child.Name .. "." .. k] = (child :: any)[k] end
		elseif child:IsA("Sky") then
			for _, k in { "StarCount", "MoonAngularSize", "SunAngularSize" } do s[child.Name .. "." .. k] = (child :: any)[k] end
		end
	end
	s.children = #Lighting:GetChildren()
	return s
end

return function(t)
	local expect = t.expect

	t.test("every arena has its own mood inside the readability ceilings", function()
		local C = LightingProfile.CEILINGS
		local names: { [string]: boolean } = {}
		for _, def in Layout.ARENAS do
			local p = LightingProfile.profileFor(def.stageId)
			expect.truthy(p ~= nil, def.stageId .. " has a profile")
			if not p then continue end
			expect.falsy(names[p.name], "moods are distinct: " .. p.name)
			names[p.name] = true
			expect.truthy(p.lighting.ExposureCompensation <= C.exposure, def.stageId .. " exposure")
			expect.truthy(p.bloom.Intensity <= C.bloomIntensity and p.bloom.Threshold >= C.bloomThresholdMin, def.stageId .. " bloom only on highlights")
			expect.truthy(p.grade.Brightness <= C.gradeBrightness and p.grade.Contrast <= C.gradeContrast, def.stageId .. " grade")
			expect.truthy(p.sunRays.Intensity <= C.sunRays and p.atmosphere.Glare <= C.glare, def.stageId .. " no veil over the fighters")
			expect.truthy(p.dof.FarIntensity <= C.dofFar and p.dof.NearIntensity == 0, def.stageId .. " depth of field stays subtle, fighters sharp")
			expect.truthy(p.rig.key <= C.rigKey and p.rig.rim <= C.rigRim, def.stageId .. " rig strengths")
			-- fighters never fall into the dark: enough ambient light reaches them even at night
			local amb = (luma(p.lighting.Ambient) + luma(p.lighting.OutdoorAmbient)) / 2
			expect.truthy(amb >= 0.2, string.format("%s ambient %.2f keeps fighters readable", def.stageId, amb))
		end
		local clocks: { [number]: boolean } = {}
		for _, def in Layout.ARENAS do
			local p = LightingProfile.profileFor(def.stageId)
			if p then clocks[math.floor(p.lighting.ClockTime)] = true end
		end
		local distinct = 0
		for _ in clocks do distinct += 1 end
		expect.truthy(distinct >= 4, "at least four times of day across the five arenas")
		expect.equal(LightingProfile.profileFor("NoSuchStage"), nil)
	end)

	t.test("an arena mood applies to this machine's lighting and restore() puts every value back exactly", function()
		local before = snapshot()
		local ok, err = pcall(function()
			expect.falsy(LightingProfile.applyArena("MidnightRooftop"), "no target on the server: nothing happens")
			expect.equal(LightingProfile.activeArena(), nil)
			expect.truthy(LightingProfile.applyArena("MidnightRooftop", Lighting), "explicit target (tests)")
			expect.equal(LightingProfile.activeArena(), "MidnightRooftop")
			expect.near(Lighting.ClockTime, LightingProfile.PROFILES.MidnightRooftop.lighting.ClockTime, 0.01, "night on the rooftop")
			local dof = Lighting:FindFirstChild("FightingLabArenaDepth")
			expect.truthy(dof and dof:IsA("DepthOfFieldEffect"), "depth of field added for the fight")
			LightingProfile.setFocus(13)
			expect.near((dof :: DepthOfFieldEffect).FocusDistance, 13, 1e-3, "focus follows the fighters")
			-- switching arenas restores first
			expect.truthy(LightingProfile.applyArena("SnowSummit", Lighting))
			expect.near(Lighting.ClockTime, LightingProfile.PROFILES.SnowSummit.lighting.ClockTime, 0.01)
		end)
		LightingProfile.restore()
		local after = snapshot()
		for k, v in before do
			local w = after[k]
			if typeof(v) == "number" then
				expect.near(w, v, 1e-4, "restored " .. k)
			else
				expect.equal(w, v, "restored " .. k)
			end
		end
		expect.equal(Lighting:FindFirstChild("FightingLabArenaDepth"), nil, "depth of field removed")
		expect.equal(LightingProfile.activeArena(), nil)
		expect.falsy(LightingProfile.restore(), "a second restore does nothing")
		if not ok then error(err, 0) end
	end)

	-- Regression (round 6): the occluder tag is global; a stage's floor that rises above a lower neighbour's floor is
	-- tagged for that neighbour, and the fight in the stage itself faded its own floor, podium and neon edge disc.
	t.test("a fight never fades its own floor stack as a camera occluder (rooftop and summit floors stayed solid)", function()
		for _, id in { "Arena_MidnightRooftop", "Arena_SnowSummit", "Arena_TrainingBay" } do
			local model = arenaModel(id)
			expect.truthy(model ~= nil, id .. " exists")
			if not model then continue end
			local origin = (model:FindFirstChild("FightOrigin") :: BasePart).Position
			StageController.setArena(model, origin)
			local faded: { [string]: boolean } = {}
			local tall = 0
			for _, inst in StageController._occluders() do
				faded[inst.Name] = true
				if inst.Name == "EdgePost" or inst.Name == "StatusBoard" then tall += 1 end
			end
			StageController.clearArena()
			for _, name in { "FightFloor", "EdgeLine", "EdgeBand", "Apron", "Rim", "Podium" } do
				expect.falsy(faded[name], id .. ": " .. name .. " must never fade in its own fight")
			end
			expect.truthy(tall > 0, id .. ": tall pieces (barrier posts) still fade")
		end
		-- the rule itself: only pieces rising above the floor + OCCLUDER_HEIGHT can block
		local p = Instance.new("Part")
		p.Size = Vector3.new(10, 0.45, 10); p.CFrame = CFrame.new(0, 4.2 - 0.225, 0)
		expect.falsy(StageController.occluderRelevant(p, 4.2), "a floor disc at the floor")
		expect.truthy(StageController.occluderRelevant(p, 1.2), "the same disc is a wall for a fight 3 studs lower")
		p.Size = Vector3.new(1, 4, 1); p.CFrame = CFrame.new(0, 4.2 + 2, 0)
		expect.truthy(StageController.occluderRelevant(p, 4.2), "a post rising 4 studs")
		p:Destroy()
	end)

	t.test("the fight light rig: key from the camera side, rim behind the fighters, both aimed at them", function()
		local cam = Vector3.new(0, 5, 15)
		local focus = Vector3.new(0, 3, 0)
		local key, rim = StageController.rigFrames(cam, focus)
		local forward = (focus - cam) * Vector3.new(1, 0, 1)
		forward = forward.Unit
		expect.truthy((key.Position - focus):Dot(forward) < 0, "the key stands on the camera's side")
		expect.truthy((rim.Position - focus):Dot(forward) > 0, "the rim stands behind the fighters")
		expect.truthy(key.LookVector:Dot((focus - key.Position).Unit) > 0.95, "key aimed at the fighters")
		expect.truthy(rim.LookVector:Dot((focus - rim.Position).Unit) > 0.95, "rim aimed at the fighters")
		expect.truthy(key.Position.Y > focus.Y and rim.Position.Y > focus.Y, "both from above")
	end)

	t.test("fight sets: one per arena, quiet, inside a budget, never between the fight camera and the fighters", function()
		local folder = ReplicatedStorage.FightingLab:FindFirstChild(FightSets.FOLDER)
		expect.truthy(folder ~= nil, "FightSets folder built with the world")
		if not folder then return end
		local orbit = Layout.CAMERA_ORBIT
		for _, def in Layout.ARENAS do
			local set = folder:FindFirstChild(def.stageId)
			expect.truthy(set ~= nil, def.stageId .. " has a fight set")
			if not set then continue end
			local parts = 0
			for _, d in set:GetDescendants() do
				if d:IsA("BasePart") then
					parts += 1
					expect.truthy(d.Anchored and not d.CanCollide and not d.CanQuery and not d.CanTouch, "quiet part " .. d:GetFullName())
					if d.Transparency < 0.99 then
						-- pieces in the fighters' height band stay outside the camera's orbit
						local cf, s = d.CFrame, d.Size * 0.5
						local ey = math.abs(cf.RightVector.Y) * s.X + math.abs(cf.UpVector.Y) * s.Y + math.abs(cf.LookVector.Y) * s.Z
						local bottom, top = cf.Y - ey, cf.Y + ey
						if bottom < def.floorY + 9 and top > def.floorY then
							local l = cf:PointToObjectSpace(Vector3.new(def.origin.X, cf.Y, def.origin.Z))
							local c = cf:PointToWorldSpace(Vector3.new(math.clamp(l.X, -s.X, s.X), math.clamp(l.Y, -s.Y, s.Y), math.clamp(l.Z, -s.Z, s.Z)))
							local flat = Vector3.new(c.X - def.origin.X, 0, c.Z - def.origin.Z).Magnitude
							expect.truthy(flat >= orbit + 0.5, string.format("%s: %s %.1f studs from the fight (orbit %d)", def.stageId, d.Name, flat, orbit))
						end
					end
				end
			end
			expect.truthy(parts > 40 and parts <= 450, def.stageId .. " set size " .. parts)
			-- the plaza side is covered; the arena's own backdrop side never is
			expect.truthy(FightSets.covers(def, (def.bearing + 180) % 360), def.stageId .. " covers the plaza side")
			expect.falsy(FightSets.covers(def, def.bearing), def.stageId .. " leaves its own backdrop alone")
			if def.stageId ~= "MidnightRooftop" then
				expect.truthy(FightSets.covers(def, 0), def.stageId .. " covers the default camera's view (north)")
			end
		end
		expect.equal(#workspace:GetChildren() > 0, true)
		for _, child in workspace:GetChildren() do
			expect.falsy(string.sub(child.Name, 1, 20) == "FightingLabFightSet_", "no set left in the Workspace on the server")
		end
	end)
	t.test("stair name mats: one word per line at a fixed size that fits, never a word split across lines", function()
		expect.equal(table.concat(ArenaKit.nameLines("Harbor Dusk"), "|"), "HARBOR|DUSK")
		expect.equal(table.concat(ArenaKit.nameLines("Summit Observatory"), "|"), "SUMMIT|OBSERVATORY")
		expect.equal(table.concat(ArenaKit.nameLines("Plaza"), "|"), "PLAZA")
		local mats = 0
		for _, def in Layout.ARENAS do
			local model = arenaModel("Arena_" .. def.stageId)
			local gate = model and model:FindFirstChild("Gate_" .. def.stageId)
			local mat = gate and gate:FindFirstChild("NameMat")
			-- (the rooftop names itself on its podium signs instead of a mat)
			if not mat or not mat:IsA("BasePart") then continue end
			local label = mat:FindFirstChildWhichIsA("SurfaceGui")
			local text = label and label:FindFirstChild("Text") :: TextLabel?
			expect.truthy(text ~= nil, def.stageId .. " name mat lettering")
			if not text then continue end
			mats += 1
			expect.falsy(text.TextScaled, def.stageId .. ": fixed size (TextScaled splits words)")
			expect.falsy(text.TextWrapped, def.stageId .. ": no wrapping")
			local lines = ArenaKit.nameLines(def.displayName)
			expect.equal(text.Text, table.concat(lines, "\n"))
			-- the longest line fits the mat's lettering box at that size (0.78 em per capital)
			local longest = 0
			for _, l in lines do longest = math.max(longest, #l) end
			local boxW = math.max(mat.Size.X, mat.Size.Z) * ArenaKit.NAME_PPS * 0.8
			expect.truthy(text.TextSize * 0.78 * longest <= boxW + 0.5, def.stageId .. " fits")
			expect.truthy(text.TextSize >= 18, def.stageId .. " stays readable (" .. text.TextSize .. " px)")
		end
		expect.truthy(mats >= 4, "the stair name mats were found (" .. mats .. ")")
	end)
end
