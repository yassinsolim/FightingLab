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
			local parts, lights = 0, 0
			for _, d in set:GetDescendants() do
				if d:IsA("Light") then
					lights += 1
					expect.falsy(d.Shadows, "set lights cast no shadows: " .. d:GetFullName())
				end
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
			-- round 7 budget: about 600 parts per set (one set, one client), at most two lights
			expect.truthy(parts > 150 and parts <= FightSets.PART_BUDGET, def.stageId .. " set size " .. parts)
			expect.truthy(lights <= 2, def.stageId .. " set lights " .. lights)
			expect.equal(set:GetAttribute("PartCount"), parts, def.stageId .. " PartCount attribute")
			-- round 7: every set surrounds the fight (the district and the stage's own pieces hide during it)
			for b = 0, 359, 30 do
				expect.truthy(FightSets.covers(def, b), def.stageId .. " covers bearing " .. b)
			end
			expect.equal(FightSets.focusBearing(def), 0, def.stageId .. " landmark in the default camera's view (north)")
		end
		expect.equal(#workspace:GetChildren() > 0, true)
		for _, child in workspace:GetChildren() do
			expect.falsy(string.sub(child.Name, 1, 20) == "FightingLabFightSet_", "no set left in the Workspace on the server")
		end
	end)

	-- Round 7: what the fight camera sees round the ring, measured on each set from the four fight-line orientations of
	-- the real CameraDirector framing: something of the set (not sky) stands behind the fighters in every direction,
	-- and each set has a crowd of 3D spectators (no flat silhouettes) and moving life.
	t.test("fight sets fill the fight camera's background in every direction, with a 3D crowd and moving pieces", function()
		local CameraDirector = require(Client:WaitForChild("CameraDirector")) :: any
		local folder = ReplicatedStorage.FightingLab:FindFirstChild(FightSets.FOLDER)
		if not folder then expect.truthy(false, "FightSets folder"); return end
		for _, def in Layout.ARENAS do
			local set = folder:FindFirstChild(def.stageId) :: Model
			-- bearings (from FightOrigin) covered by visible set parts between 38 and 260 studs out that rise above the
			-- fighters' heads (each part marks the 15-degree bins its width spans)
			local hits: { [number]: boolean } = {}
			local people, flatCrowd, animated = 0, 0, 0
			for _, d in set:GetDescendants() do
				if d:IsA("BasePart") and d.Transparency < 0.9 and d.Size.Magnitude > 2 then
					local v = Vector3.new(d.Position.X - def.origin.X, 0, d.Position.Z - def.origin.Z)
					local dist = v.Magnitude
					if dist > 38 and dist < 260 and d.Position.Y + d.Size.Y * 0.4 > def.floorY + 4 then
						local b = math.deg(math.atan2(v.X, -v.Z))
						local half = math.deg(math.atan2(math.max(d.Size.X, d.Size.Z) * 0.5, dist))
						for k = math.floor((b - half) / 15), math.floor((b + half) / 15) do
							hits[k % 24] = true
						end
					end
				elseif d:IsA("Model") and d.Name == "Person" then
					people += 1
				elseif d.Name == "CrowdPanel" then
					flatCrowd += 1
				end
				if d:GetAttribute(FightSets.ANIM_ATTRIBUTE) ~= nil then animated += 1 end
			end
			local missing = {}
			for k = 0, 23 do
				if not hits[k] then table.insert(missing, tostring(k * 15)) end
			end
			expect.truthy(#missing <= 2, def.stageId .. ": empty background bearings " .. table.concat(missing, ","))
			expect.truthy(people >= 20, def.stageId .. ": 3D spectators " .. people)
			expect.equal(flatCrowd, 0, def.stageId .. ": no flat crowd panels")
			expect.truthy(animated >= people, def.stageId .. ": moving pieces " .. animated)
			-- the default fight camera (fight line along X) sees the landmark: a tall piece near bearing 0 in frame
			local plan = CameraDirector._plan(Vector3.new(-3.5, 0, 0), Vector3.new(3.5, 0, 0), "Fight", 0, 1 / 60, Vector3.new(0, 0, -1), 0, false, nil)
			local cam = CFrame.lookAt(def.origin + plan.position, def.origin + plan.focus)
			local inFrame = 0
			for _, d in set:GetDescendants() do
				if d:IsA("BasePart") and d.Transparency < 0.9 then
					local v = CameraDirector._normalizedViewportPoint(cam, plan.fov, 16 / 9, d.Position)
					if v and v.X > 0.05 and v.X < 0.95 and v.Y > 0.02 and v.Y < 0.7 then inFrame += 1 end
				end
			end
			expect.truthy(inFrame >= 30, def.stageId .. ": set pieces in the default fight frame " .. inFrame)
		end
	end)

	t.test("set assets are free Creator Store meshes, credited in the credits data", function()
		local AssetKit = require(WorldModules:WaitForChild("AssetKit"))
		local Credits = require(ReplicatedStorage.FightingLab:WaitForChild("Credits")) :: any
		local credited: { [number]: boolean } = {}
		for _, w in Credits.world or {} do credited[w.id] = true end
		for id in AssetKit.assetIds() do
			expect.truthy(credited[id], "asset " .. id .. " is credited (data/world-assets.json -> Credits.world)")
		end
		for key, a in AssetKit.ASSETS do
			expect.truthy(#a.pieces > 0 and a.height > 0 and a.radius > 0, key .. " asset data")
			for _, p in a.pieces do
				expect.truthy(string.match(p.mesh, "^rbxassetid://%d+$") ~= nil, key .. " mesh id")
			end
		end
		-- the sets carry only parts and meshes from code: no scripts from any model
		local folder = ReplicatedStorage.FightingLab:FindFirstChild(FightSets.FOLDER) :: Instance
		for _, d in folder:GetDescendants() do
			expect.falsy(d:IsA("LuaSourceContainer"), "no script in a set: " .. d:GetFullName())
		end
		local m = AssetKit.place(workspace, "Rock", CFrame.new(0, -500, 0), 2)
		local mesh = m:FindFirstChildWhichIsA("BasePart", true)
		expect.truthy(mesh and mesh:FindFirstChildOfClass("SpecialMesh"), "placed asset pieces are textured meshes")
		expect.equal(m:GetAttribute("AssetId"), AssetKit.ASSETS.Rock.assetId)
		m:Destroy()
	end)

	t.test("during its own fight an arena keeps only its podium: pads, board and banners hide; the floor stack stays", function()
		local model = arenaModel("Arena_HarborDusk") :: Model
		local origin = (model:FindFirstChild("FightOrigin") :: BasePart).Position
		local function hides(name: string): boolean?
			local p = model:FindFirstChild(name, true)
			if not (p and p:IsA("BasePart")) then return nil end
			return StageController.hidesInOwnFight(p, origin)
		end
		for _, name in { "PadP1", "PadP2", "ExitP1", "StatusBoard", "Arrival", "Banner" } do
			expect.equal(hides(name), true, name .. " hides in the fight")
		end
		for _, name in { "FightFloor", "EdgeLine", "EdgeBand", "Apron", "Podium", "FightOrigin", "PreviewCam" } do
			expect.equal(hides(name), false, name .. " stays in the fight")
		end
		-- every barrier post and stage light (on the podium) stays
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and (d.Name == "EdgePost" or d:FindFirstAncestor("StageLights")) then
				expect.falsy(StageController.hidesInOwnFight(d, origin), "stays: " .. d:GetFullName())
			end
		end
	end)

	t.test("set animation: cheer hops up only, sways and sweeps swing about the rest pose, orbits go round", function()
		local SC = StageController :: any
		for _, t0 in { 0, 0.3, 1.1, 2.7 } do
			local cheer = SC.animOffset("Cheer", t0, 6, 0.5, 0)
			expect.truthy(cheer.Position.Y >= -1e-6 and cheer.Position.Y <= 0.5 + 1e-6, "cheer hop in [0, amp]")
			local bob = SC.animOffset("Bob", t0, 2, 0.3, 1)
			expect.truthy(math.abs(bob.Position.Y) <= 0.3 + 1e-6, "bob within amp")
		end
		expect.truthy(SC.animOffset("Sway", 0, 1, 0.1, 0).Position.Magnitude < 1e-6, "sway keeps the pivot")
		local o1 = SC.animOffset("Orbit", 0, 1, 10, 0)
		local o2 = SC.animOffset("Orbit", math.pi / 2, 1, 10, 0)
		expect.truthy(o1.LookVector:Dot(o2.LookVector) < 0.1, "orbit turns a quarter in a quarter period")
		expect.equal(SC.animOffset("Unknown", 1, 1, 1, 1), CFrame.identity)
		-- the map preview is client only
		expect.falsy(SC.previewArena(arenaModel("Arena_SnowSummit")), "no preview on the server")
		expect.equal(SC.previewing(), nil)
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
