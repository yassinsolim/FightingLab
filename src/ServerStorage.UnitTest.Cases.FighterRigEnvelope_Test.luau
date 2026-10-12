--!strict
local Lab = game:GetService("ReplicatedStorage").FightingLab
local Rig = require(Lab.FighterRig)
local Config = require(Lab.CombatConfig)
local Runner = require(game:GetService("ServerStorage").UnitTest.RunUnitTest)
type TestContext = Runner.T
local palette = { body = Color3.new(0.2, 0.3, 0.4), trim = Color3.new(0.8, 0.8, 0.7), skin = Color3.new(0.8, 0.6, 0.5), visor = Color3.new(0, 1, 1) }
local function bottom(part: BasePart): number
	local cf, half = part.CFrame, part.Size / 2
	return cf.Position.Y - math.abs(cf.RightVector.Y) * half.X - math.abs(cf.UpVector.Y) * half.Y - math.abs(cf.LookVector.Y) * half.Z
end
return function(t: TestContext)
	-- Contract: anticipation pulls back (extension <= 0) through ~65% of startup, then snaps to the peak.
	t.test("every move anticipates, peaks on the first active frame and settles to neutral", function()
		for name, m in Config.Moves do
			local prof = Rig.envelopeProfile(name)
			local antFrame = math.floor(prof.anticipation * m.startup)
			if antFrame >= 1 then
				local e, w = Rig.moveEnvelope(name, antFrame)
				t.expect.truthy(e <= 0, name .. " anticipation must not extend")
				t.expect.truthy(w > 0, name .. " anticipation must wind up")
			end
			local last = Rig.moveEnvelope(name, m.startup)
			t.expect.truthy(last < 1, name .. " must not reach full extension before the first active frame")
			t.expect.equal(Rig.moveEnvelope(name, m.startup + 1), 1)
			t.expect.equal(Rig.moveEnvelope(name, m.startup + m.active), 1)
			t.expect.near(Rig.moveEnvelope(name, m.startup + m.active + m.recovery), 0, 1e-6, name .. " recovery end")
			-- Settling recovery: first half of recovery drops more than half the extension.
			local mid = Rig.moveEnvelope(name, m.startup + m.active + math.ceil(m.recovery / 2))
			t.expect.truthy(mid < 0.5, name .. " recovery should settle faster than linear")
		end
	end)
	-- Most of the extension happens in the final startup frames (snap), not spread evenly over startup.
	t.test("extension is concentrated in the final third of startup", function()
		for name, m in Config.Moves do
			if m.startup >= 6 then
				local twoThirds = Rig.moveEnvelope(name, math.floor(m.startup * 2 / 3))
				t.expect.truthy(twoThirds < 0.25, name .. " extended too early: " .. twoThirds)
			end
		end
	end)
	t.test("punch, kick, rise and sweep use distinct anticipation profiles", function()
		local seen: { [string]: boolean } = {}
		for _, kind in {"Punch", "Kick", "Rise", "Sweep"} do
			local p = Rig.envelopeProfile(kind)
			local key = string.format("%.2f/%.2f", p.pull, p.windup)
			t.expect.falsy(seen[key], kind .. " duplicates another profile")
			seen[key] = true
		end
		t.expect.equal(Rig.envelopeProfile("Jab").kind, "Punch")
	end)
	t.test("idle breathing changes the pose over time and backwalk differs from forward walk", function()
		local a = Rig.targetPose("Idle", nil, 0, 0, 0, false, 0, 0)
		local b = Rig.targetPose("Idle", nil, 0, 0, 0, false, math.pi / 2, 0)
		local differs = false
		for k, v in a do
			if math.abs(v - (b :: any)[k]) > 1e-4 then differs = true end
		end
		t.expect.truthy(differs, "idle phase must advance the idle pose")
		local fwd = Rig.targetPose("Walk", nil, 0, 1, 0, false, 0, 1)
		local back = Rig.targetPose("Walk", nil, 0, 1, 0, false, 0, -1)
		local walkDiffers = false
		for k, v in fwd do
			if math.abs(v - (back :: any)[k]) > 1e-4 then walkDiffers = true end
		end
		t.expect.truthy(walkDiffers, "backwalk must use a distinct stride")
	end)
	t.test("idle, walk and backwalk keep a planted foot without sinking or a large head bob", function()
		local folder = Instance.new("Folder")
		folder.Parent = workspace
		local rig = Rig.new("EnvelopeFixture", palette, folder)
		local ok, err = xpcall(function()
			local heads: { number } = {}
			for _, dir in {1, -1, 0} do
				for step = 0, 11 do
					local phase = step * math.pi / 6
					local state = if dir == 0 then "Idle" else "Walk"
					rig.pose = Rig.targetPose(state, nil, 0, phase, 0, false, phase, dir)
					Rig.apply(rig, Vector3.zero, Vector3.xAxis)
					local lowest = math.huge
					for _, d in rig.model:GetChildren() do
						if d:IsA("BasePart") and (d.Name == "LFoot" or d.Name == "RFoot" or d.Name == "LSole" or d.Name == "RSole") then lowest = math.min(lowest, bottom(d)) end
					end
					t.expect.near(lowest, 0.015, 0.001, state .. " dir " .. dir)
					table.insert(heads, rig.parts.Head.Position.Y)
				end
			end
			local lo, hi = math.huge, -math.huge
			for _, h in heads do lo = math.min(lo, h); hi = math.max(hi, h) end
			t.expect.truthy(hi - lo < 0.45, "head bob " .. (hi - lo))
		end, debug.traceback)
		folder:Destroy()
		if not ok then error(err) end
	end)
end
