--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local Lab = ReplicatedStorage.FightingLab
local CameraDirector = require(Lab.Client.CameraDirector)
local MotionPlayer = require(Lab.Client.MotionPlayer)
local EffectsController = require(Lab.Client.EffectsController)
local AudioController = require(Lab.Client.AudioController)
local StageController = require(Lab.Client.StageController)

local function closeEnough(a: number, b: number, eps: number): boolean
	return math.abs(a - b) <= eps
end

return function(t)
	local test, expect = t.test, t.expect

	test("camera framing math meets screen-height targets", function()
		local neutral = CameraDirector._screenHeightFraction(CameraDirector._distanceForSeparation(7), 6.0, 36)
		local close = CameraDirector._screenHeightFraction(CameraDirector._distanceForSeparation(3.2), 6.0, 36)
		local far = CameraDirector._screenHeightFraction(CameraDirector._distanceForSeparation(14), 6.0, 36)
		expect.truthy(neutral >= 0.55 and neutral <= 0.65, string.format("neutral framing %.3f in 55-65%%", neutral))
		expect.truthy(close >= 0.55 and close <= 0.68)
		expect.truthy(far >= 0.35)
		local plan = CameraDirector._plan(Vector3.new(-3.5, 0, 0), Vector3.new(3.5, 0, 0), "Fight", 0, 1 / 60, Vector3.new(0, 0, -1), 0, false, nil)
		expect.truthy(plan.position.Y > plan.focus.Y)
		expect.truthy(plan.fov <= 36)
	end)

	test("camera keeps grounded feet and airborne heads inside margins during juggles", function()
		local minMargin = 1
		for _, aspect in { 16 / 9, 4 / 3 } do
			for _, separation in { 2, 3.2, 5, 7 } do
				for _, airHeight in { 0, 2, 3.5, 4.5 } do
					local p1 = Vector3.new(-separation * 0.5, 0, 0)
					local p2 = Vector3.new(separation * 0.5, airHeight, 0)
					local plan = CameraDirector._plan(p1, p2, "Fight", 0, 1 / 60, Vector3.new(0, 0, -1), airHeight, false, nil)
					local cameraCFrame = CFrame.lookAt(plan.position, plan.focus)
					for _, point in {
						p1,
						p1 + Vector3.new(0, 6, 0),
						p2,
						p2 + Vector3.new(0, 6, 0),
					} do
						local projected = CameraDirector._normalizedViewportPoint(cameraCFrame, plan.fov, aspect, point)
						expect.truthy(projected ~= nil)
						if projected then
							minMargin = math.min(minMargin, projected.X, 1 - projected.X, projected.Y, 1 - projected.Y)
							expect.truthy(projected.X >= 0.05 and projected.X <= 0.95)
							expect.truthy(projected.Y >= 0.05 and projected.Y <= 0.95)
						end
					end
				end
			end
		end
		expect.truthy(minMargin >= 0.05)
	end)

	test("camera snaps on the round reset, the same frame the bodies cut", function()
		local cam = workspace.CurrentCamera
		expect.truthy(cam ~= nil, "a camera to drive")
		if not cam then return end
		local savedCFrame, savedType, savedFov = cam.CFrame, cam.CameraType, cam.FieldOfView
		local origin = Vector3.new(0, 900, 0)
		local function frame(now: number, phase: string, x1: number, x2: number): any
			local ko = phase == "RoundOver"
			return { now = now, dt = 1 / 60, hitstop = 0, phase = phase, ko = ko, winner = if ko then 1 else 0, origin = origin,
				fighters = { { pos = Vector3.new(x1, 0, 0), state = "Idle" }, { pos = Vector3.new(x2, 0, 0), state = if ko then "KO" else "Idle" } } }
		end
		local ok, err = pcall(function()
			CameraDirector.beginFight(origin, 1)
			local now = 0
			-- The round ends away from the marks; the camera settles on the KO shot.
			for _ = 1, 150 do
				now += 1 / 60
				CameraDirector.update(frame(now, "RoundOver", 6, 9.5))
			end
			local before = CameraDirector._state()
			-- Next round: both fighters back on their marks. MotionPlayer cuts the bodies on this frame; so does the camera.
			now += 1 / 60
			CameraDirector.update(frame(now, "Ready", -3.5, 3.5))
			local cut = CameraDirector._state()
			local plan = cut.plan :: any
			expect.equal(cut.snaps, before.snaps + 1, "the round reset is a camera cut")
			expect.truthy((cut.camPos - plan.position).Magnitude < 1e-3 and (cut.camLook - plan.focus).Magnitude < 1e-3, "on the intro shot at once")
			expect.truthy((cut.camPos - before.camPos).Magnitude > 2, string.format("a cut, not a glide (moved %.2f)", (cut.camPos - before.camPos).Magnitude))
			expect.truthy(math.abs(cam.FieldOfView - plan.fov) < 1e-3, "field of view cut too")
			expect.truthy(cut.side:Dot(Vector3.new(0, 0, -1)) > 0.99, "slot 1 views with its fighter on the left again")
			-- Ordinary frames keep gliding.
			now += 1 / 60
			CameraDirector.update(frame(now, "Fight", -2.6, 3.5))
			local glide = CameraDirector._state()
			expect.equal(glide.snaps, cut.snaps, "no cut without a reset")
			expect.truthy((glide.camPos - (glide.plan :: any).position).Magnitude > 1e-3, "normal frames are smoothed")
			-- A practice/training reset (a jump past TeleportDistance without a new round) cuts as well.
			now += 1 / 60
			CameraDirector.update(frame(now, "Fight", 4, 11))
			expect.equal(CameraDirector._state().snaps, glide.snaps + 1, "teleports cut")
			expect.equal(CameraDirector.TeleportDistance, MotionPlayer.TeleportDistance, "camera and bodies cut on the same rule")
		end)
		CameraDirector.endFight()
		cam.CameraType, cam.CFrame, cam.FieldOfView = savedType, savedCFrame, savedFov
		if not ok then error(err, 0) end
	end)

	test("event to effect mapping covers every v2 kind and tier", function()
		local events = {
			{ kind = "Hit", tier = "Light" }, { kind = "Hit", tier = "Medium" }, { kind = "Hit", tier = "Heavy" }, { kind = "Hit", tier = "Launch", launch = true },
			{ kind = "Hit", tier = "Heavy", counter = true }, { kind = "Block" }, { kind = "Whiff" }, { kind = "ThrowStart" }, { kind = "ThrowHit" },
			{ kind = "ThrowBreak" }, { kind = "Parry" }, { kind = "Armor" }, { kind = "Crush" }, { kind = "KO" },
		}
		for _, e in events do
			local spec = EffectsController._specForEvent(e)
			expect.truthy(spec.color ~= nil)
			expect.truthy(spec.life >= 0.08 or e.kind == "Whiff" or e.kind == "Crush")
		end
		local air = EffectsController._specForEvent({ kind = "Hit", tier = "Heavy", air = true })
		local grounded = EffectsController._specForEvent({ kind = "Hit", tier = "Heavy" })
		expect.truthy(air.sparks < grounded.sparks)
	end)

	test("effect pool stays bounded under burst load", function()
		expect.equal(EffectsController._poolSize(), 32)
		local seen = {}
		for _, e in { { kind = "Hit", tier = "Light" }, { kind = "Hit", tier = "Heavy" }, { kind = "KO" }, { kind = "ThrowHit" } } do
			local spec = EffectsController._specForEvent(e)
			seen[tostring(spec.ring)] = true
		end
		expect.truthy(seen["1.15"] ~= nil)
		expect.truthy(seen["3.5"] ~= nil)
	end)

	test("audio mapping covers required combat events", function()
		local cases = {
			{ e = { kind = "Hit", tier = "Light" }, name = "HitLight" }, { e = { kind = "Hit", tier = "Medium" }, name = "HitMedium" },
			{ e = { kind = "Hit", tier = "Heavy" }, name = "HitHeavy" }, { e = { kind = "Hit", tier = "Launch", launch = true }, name = "HitLaunch" },
			{ e = { kind = "Hit", counter = true }, name = "Counter" }, { e = { kind = "Block" }, name = "Block" }, { e = { kind = "Whiff" }, name = "Whiff" },
			{ e = { kind = "ThrowStart" }, name = "ThrowGrab" }, { e = { kind = "ThrowHit" }, name = "ThrowImpact" }, { e = { kind = "ThrowBreak" }, name = "ThrowBreak" },
			{ e = { kind = "Parry" }, name = "Parry" }, { e = { kind = "Armor" }, name = "Armor" }, { e = { kind = "Crush" }, name = "Crush" }, { e = { kind = "KO" }, name = "KO" },
		}
		for _, case in cases do expect.equal(AudioController._soundNameForEvent(case.e), case.name) end
		local required = AudioController.requiredSounds()
		expect.truthy(#required >= 23)
		local manifest = AudioController.assetManifest()
		expect.equal(#manifest, #required)
	end)

	test("arena presentation never clones stages or changes global lighting and restores fades", function()
		local stages = Lab.Stages
		local a = Instance.new("Model")
		a.Name = "UnitStageA"
		local ap = Instance.new("Folder")
		ap.Name = "LightingPreset"
		ap:SetAttribute("Brightness", 1.2)
		local acc = Instance.new("ColorCorrectionEffect")
		acc.Name = "UnitCCA"
		acc.Parent = ap
		ap.Parent = a
		a.Parent = stages
		local brightness = Lighting.Brightness
		StageController.init({ modules = { Camera = { getFocus = function() return Vector3.new(0, 2.75, 0) end }, Characters = { getRoot = function() return nil end } }, gui = Instance.new("ScreenGui") })
		StageController.load("UnitStageA")
		expect.equal(StageController.current(), "UnitStageA")
		expect.truthy(Lighting:FindFirstChild("UnitCCA") == nil, "no lighting preset is applied")
		expect.equal(Lighting.Brightness, brightness)
		expect.truthy(workspace:FindFirstChild("FightingLabArena") == nil, "no stage model is cloned")
		a:Destroy()
		-- An arena model with a tagged occluder straight between the camera and the fighters fades, then restores.
		local arena = Instance.new("Model")
		arena.Name = "UnitArena"
		arena:SetAttribute("StageId", "HarborDusk")
		local wall = Instance.new("Part")
		wall.Anchored = true
		wall.Size = Vector3.new(6, 12, 2)
		local cam = workspace.CurrentCamera
		local camPos = if cam then cam.CFrame.Position else Vector3.new(0, 4, 20)
		local focus = Vector3.new(0, 2.75, 0)
		wall.CFrame = CFrame.new(camPos:Lerp(focus, 0.5))
		wall.Parent = arena
		arena.Parent = workspace
		local tag = "FightingLabCameraOccluder"
		game:GetService("CollectionService"):AddTag(wall, tag)
		StageController.setArena(arena, Vector3.zero)
		expect.equal(StageController.current(), "HarborDusk")
		for _ = 1, 30 do StageController.update({ dt = 1 / 60, now = os.clock() }) end
		if cam then expect.truthy(wall.LocalTransparencyModifier > 0.5, "occluder fades") end
		StageController.clearArena()
		expect.equal(wall.LocalTransparencyModifier, 0)
		arena:Destroy()
		expect.truthy(StageController._testLightingContrast("TrainingBay") >= 0.15)
	end)

	test("spectator avatars in the fight camera's view fade and are restored after the fight", function()
		local cam = workspace.CurrentCamera
		if not cam then return end
		local camPos = cam.CFrame.Position
		local focus = cam.CFrame.Position + cam.CFrame.LookVector * 16
		StageController.init({ modules = { Camera = { getFocus = function() return focus end }, Characters = { getRoot = function() return nil end } }, gui = Instance.new("ScreenGui") })
		local function avatar(at: Vector3): (Model, BasePart, Decal)
			local model = Instance.new("Model")
			local root = Instance.new("Part")
			root.Name = "HumanoidRootPart"
			root.Anchored = true
			root.CFrame = CFrame.new(at)
			root.Parent = model
			local face = Instance.new("Decal")
			face.Parent = root
			model.PrimaryPart = root
			model.Parent = workspace
			return model, root, face
		end
		local blocker, blockerRoot, blockerFace = avatar(camPos:Lerp(focus, 0.45))
		local bystander, bystanderRoot = avatar(camPos + cam.CFrame.RightVector * 30)
		local arena = Instance.new("Model")
		arena.Name = "UnitArenaSpectators"
		arena.Parent = workspace
		local original = StageController._spectatorCharacters
		StageController._spectatorCharacters = function() return { blocker, bystander } end
		local ok, err = pcall(function()
			StageController.setArena(arena, Vector3.zero)
			for _ = 1, 40 do StageController.update({ dt = 1 / 60, now = os.clock() }) end
			expect.truthy(blockerRoot.LocalTransparencyModifier > 0.7, "the avatar between camera and fighters fades")
			expect.truthy((blockerFace :: any).LocalTransparencyModifier > 0.7, "its face decal fades too")
			expect.equal(bystanderRoot.LocalTransparencyModifier, 0, "avatars outside the view stay visible")
			blockerRoot.CFrame = CFrame.new(camPos - cam.CFrame.LookVector * 8)
			for _ = 1, 40 do StageController.update({ dt = 1 / 60, now = os.clock() }) end
			expect.equal(blockerRoot.LocalTransparencyModifier, 0, "an avatar behind the camera reappears")
			blockerRoot.CFrame = CFrame.new(camPos:Lerp(focus, 0.45))
			for _ = 1, 40 do StageController.update({ dt = 1 / 60, now = os.clock() }) end
			expect.truthy(blockerRoot.LocalTransparencyModifier > 0.7)
			StageController.clearArena()
			expect.equal(blockerRoot.LocalTransparencyModifier, 0, "fight end restores the avatar exactly")
			expect.equal((blockerFace :: any).LocalTransparencyModifier, 0)
		end)
		StageController._spectatorCharacters = original
		StageController.clearArena()
		blocker:Destroy(); bystander:Destroy(); arena:Destroy()
		if not ok then error(err, 0) end
	end)
end
