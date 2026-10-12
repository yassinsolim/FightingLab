--!strict
local Lab = game:GetService("ReplicatedStorage").FightingLab
local Rig = require(Lab.FighterRig)
local Config = require(Lab.CombatConfig)
local Runner = require(game:GetService("ServerStorage").UnitTest.RunUnitTest)
type TestContext = Runner.T
local palette = { body = Color3.fromRGB(39, 65, 86), trim = Color3.fromRGB(211, 202, 177), skin = Color3.fromRGB(205, 160, 125), visor = Color3.new(0, 1, 1) }
local function bottom(part: BasePart): number
	local cf, half = part.CFrame, part.Size / 2
	return cf.Position.Y - math.abs(cf.RightVector.Y) * half.X - math.abs(cf.UpVector.Y) * half.Y - math.abs(cf.LookVector.Y) * half.Z
end
local function fixture(check: (Rig.Rig) -> ())
	local folder = Instance.new("Folder")
	folder.Name = "RigTestFixture"
	folder.Parent = workspace
	local rig = Rig.new("Fixture", palette, folder)
	local ok, err = xpcall(function() check(rig) end, debug.traceback)
	folder:Destroy()
	if not ok then error(err) end
end
return function(t: TestContext)
	-- Core geometry must be the saved authored mesh, not primitive replacements.
	t.test("uses fourteen saved mesh limbs and a sanitized authored head", function()
		fixture(function(rig)
			local count = 0
			for _, part in rig.parts do
				if part:IsA("MeshPart") then
					count += 1
					t.expect.truthy(#part.MeshId > 0)
				end
				t.expect.truthy(part.Anchored)
				t.expect.falsy(part.CanCollide or part.CanQuery or part.CanTouch)
			end
			t.expect.equal(count, 14)
			t.expect.truthy(rig.parts.Head:FindFirstChildOfClass("SpecialMesh"))
			for _, d in rig.model:GetDescendants() do
				t.expect.falsy(d:IsA("LuaSourceContainer") or d:IsA("JointInstance") or d:IsA("Humanoid") or d:IsA("PackageLink"))
			end
		end)
	end)
	-- Grounded stance, crouch, movement, guard and every move must preserve floor contact.
	t.test("grounded poses plant a support foot without sinking", function()
		fixture(function(rig)
			local function check(state: string, move: string?, frame: number, crouched: boolean)
				rig.pose = Rig.targetPose(state, move, frame, 1, 6, crouched)
				Rig.apply(rig, Vector3.zero, Vector3.xAxis)
				local lowest = math.huge
				for _, d in rig.model:GetChildren() do
					if d:IsA("BasePart") and (d.Name == "LFoot" or d.Name == "RFoot" or d.Name == "LSole" or d.Name == "RSole") then lowest = math.min(lowest, bottom(d)) end
				end
				t.expect.near(lowest, 0.015, 0.001, state .. " " .. (move or ""))
			end
			for _, state in {"Idle", "Walk", "Dash", "Step", "Block", "Crouch", "CrouchBlock"} do check(state, nil, 0, state == "Crouch" or state == "CrouchBlock") end
			for name, move in Config.Moves do
				for _, frame in {1, move.startup, move.startup + 1, move.startup + move.active + move.recovery} do check("Active", name, frame, name == "DuckJab" or name == "BodyPunch" or name == "ShinTap" or name == "Sweep") end
			end
		end)
	end)
	-- Knockdown may lie on the floor but no visible part may pass through it.
	t.test("KO landing and getup stay above the floor", function()
		fixture(function(rig)
			for _, state in {"KO", "Landing", "Getup"} do
				rig.pose = Rig.targetPose(state, nil, 0, 0, 8, false)
				Rig.apply(rig, Vector3.zero, Vector3.xAxis)
				for _, d in rig.model:GetChildren() do if d:IsA("BasePart") then t.expect.truthy(bottom(d) >= 0.014, state .. " " .. d.Name) end end
			end
		end)
	end)
	-- Simulation flight must translate the complete mesh rig without being grounded.
	t.test("airborne height translates every part exactly", function()
		fixture(function(rig)
			rig.pose = Rig.targetPose("Airborne", nil, 0, 0, 0, false)
			Rig.apply(rig, Vector3.new(0, 1, 0), Vector3.xAxis)
			local first: {[string]: number} = {}
			for name, part in rig.parts do first[name] = part.Position.Y end
			Rig.apply(rig, Vector3.new(0, 3, 0), Vector3.xAxis)
			for name, part in rig.parts do t.expect.near(part.Position.Y - first[name], 2, 0.001) end
		end)
	end)
	-- Correct authored limbs must retain active color and damage-flash feedback.
	t.test("highlights and flash restore original palette", function()
		fixture(function(rig)
			local color = Color3.new(0, 1, 1)
			Rig.apply(rig, Vector3.zero, Vector3.xAxis, "LeadArm", color)
			t.expect.equal(rig.parts.LForearm.Color, color)
			t.expect.equal(rig.parts.RForearm.Color, palette.skin)
			rig.flash = 1
			Rig.apply(rig, Vector3.zero, Vector3.xAxis)
			t.expect.equal(rig.parts.Torso.Color, Color3.new(1, 1, 1))
			Rig.apply(rig, Vector3.zero, Vector3.xAxis)
			t.expect.equal(rig.parts.Torso.Color, palette.body)
		end)
	end)
	-- Floor alignment and authored structure must be saved, not injected at runtime.
	t.test("TrainingBay stage is clear aligned and script free", function()
		local arena = game:GetService("ReplicatedStorage").FightingLab.Stages.TrainingBay
		t.expect.equal(arena:GetAttribute("CreatorStoreAssetId"), 6968488530)
		local floor = arena:FindFirstChild("Floor")
		assert(floor and floor:IsA("BasePart"))
		t.expect.near(floor.Position.Y + floor.Size.Y / 2, 0, 0.001)
		t.expect.truthy(floor.CanCollide and floor.Size.X > 2 * Config.ArenaRadius and floor.Size.Z > 2 * Config.ArenaRadius)
		for _, d in arena:GetDescendants() do t.expect.falsy(d:IsA("LuaSourceContainer") or d:IsA("PackageLink")) end
	end)
end