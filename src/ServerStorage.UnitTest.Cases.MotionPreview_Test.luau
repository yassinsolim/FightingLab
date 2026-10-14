--!strict
-- Round 7: fighter-select previews stand like the fight (CharacterPresenter.posePreview on the REAL rigs of all six).
-- The user: "character select characters like kael and sierra have their feet jumping but in a weird way that doesnt
-- look normal almost ragdoll like". Round 6 previews pinned the pelvis and raised the floor by the stance's bob instead,
-- without the clip's foot contacts: the bouncing stances (Kael and Lumi: Stance, Sierra: Stance_Kickboxer) moved their
-- feet 0.23-0.42 studs up and down under a still body, and the select (which measured the feet once to stand the rig)
-- showed them sinking up to 0.31 studs into the platform and floating 0.28 over it.
-- Each fighter's preview stance plays one full loop (plus the seam) at 60 fps on a clone whose root stands RootHeight
-- over the floor, as the fighter select stands it now (FighterSelect.placeShown), after half a second of warm-up:
--   * the feet stand on that floor: the lower foot's lowest point stays within FLOOR_SINK .. LOW_MAX of it every frame,
--     and its height range over the loop stays within LOW_RANGE (Sierra's kickboxer bounce lifts both feet up to ~0.15
--     studs at its top, with the body);
--   * no foot moves more than JUMP studs between frames, the loop seam included;
--   * feet do not skate: a toe or heel point touching the floor three frames in a row slides at most SKATE_RATE studs
--     per second of the loop in total;
--   * the body carries the bob: the pelvis moves at least as much as the lower foot does.
-- Main: Kael, Sierra and Lumi fail every check of the bounce; Goran, Rhys and Nia (stand-to-ready captures, still feet)
-- fail only the absolute floor (their constant offset, which the round-6 select measured away).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lab = ReplicatedStorage:WaitForChild("FightingLab")
local Client = Lab:WaitForChild("Client")
local Roster = require(Lab:WaitForChild("Roster"))
local MotionPlayer = require(Client:WaitForChild("MotionPlayer"))
local CharacterPresenter = require(Client:WaitForChild("CharacterPresenter"))
local States = require(Client:WaitForChild("Motion"):WaitForChild("States"))
local ClipLibrary = require(Client:WaitForChild("Motion"):WaitForChild("ClipLibrary"))
local Runner = require(game:GetService("ServerStorage").UnitTest.RunUnitTest)

local FPS = 60
local PLATFORM = 4300.42
local FLOOR_SINK = -0.03
local LOW_MAX = 0.2
local LOW_RANGE = 0.2
local JUMP = 0.12
local SKATE_RATE = 2.0
local TOUCH = 0.012

local function extentY(cf: CFrame, size: Vector3): number
	local r, u, l = cf.RightVector.Y, cf.UpVector.Y, cf.LookVector.Y
	local box = math.abs(r) * size.X + math.abs(u) * size.Y + math.abs(l) * size.Z
	local ellipsoid = math.sqrt((r * size.X) ^ 2 + (u * size.Y) ^ 2 + (l * size.Z) ^ 2)
	return (box + ellipsoid) * 0.25
end

-- Posed part frames through the joint chain (parts move only on the engine's next step).
local function posed(rig: MotionPlayer.RigInfo): { [string]: CFrame }
	local out: { [string]: CFrame } = {}
	for _, name in { "LowerTorso", "LeftFoot", "RightFoot" } do
		local cf = MotionPlayer.partWorld(rig, name)
		if cf then out[name] = cf end
	end
	return out
end

-- The ground box's lowest point as the runtime rests a foot (MotionPlayer extentY), and its toe/heel points.
local function footPoints(chain: any, foot: CFrame): (number, Vector3, Vector3)
	local c = foot * chain.tipBox
	local s: Vector3 = chain.tipSize
	return c.Position.Y - extentY(c, s), (c * Vector3.new(0, -s.Y * 0.5, -s.Z * 0.5)), (c * Vector3.new(0, -s.Y * 0.5, s.Z * 0.5))
end

local function loopSeconds(id: string): number
	local style = Roster.get(id).stanceStyle
	local clip = ClipLibrary.find(States.CLIPS.Stance, States.STYLE_NAMES[style])
	local rate = ((States.STYLES :: any)[style] or States.STYLES.boxer).rate or 1
	return if clip then clip.duration / rate else 2
end

type Frame = { pelvis: number, low: number, bottom: { number }, feet: { CFrame }, toes: { Vector3 }, heels: { Vector3 } }

local function measure(id: string): ({ Frame }, number)
	local template = Lab:WaitForChild("Characters"):FindFirstChild(id) :: Model
	local model = template:Clone()
	model.Name = "PreviewFeet_" .. id
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = d.Name == "HumanoidRootPart"; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false
		end
	end
	local rootHeight = model:GetAttribute("RootHeight") :: number
	local p = Vector3.new(0, PLATFORM + rootHeight, -2600)
	model:PivotTo(CFrame.lookAt(p, p + Vector3.new(-0.34, 0, 0.94)))
	model.Parent = workspace
	local rig = MotionPlayer.collectRig(model)
	local chains = { rig.chains.LeftLeg, rig.chains.RightLeg }
	local frames: { Frame } = {}
	local seconds = loopSeconds(id)
	local n = math.floor(seconds * FPS + 0.5)
	local t0 = 1000 + (string.byte(id, 1) % 7) * 0.13
	for i = -30, n do
		local t = t0 + i / FPS
		CharacterPresenter.posePreview(model, id, "Stance", t)
		if i >= 0 then
			local cf = posed(rig)
			local f: Frame = { pelvis = cf.LowerTorso.Position.Y, low = math.huge, bottom = {}, feet = { cf.LeftFoot, cf.RightFoot }, toes = {}, heels = {} }
			for k = 1, 2 do
				local b, toe, heel = footPoints(chains[k], f.feet[k])
				f.bottom[k], f.toes[k], f.heels[k] = b - PLATFORM, toe, heel
				f.low = math.min(f.low, b - PLATFORM)
			end
			table.insert(frames, f)
		end
	end
	model:Destroy()
	return frames, seconds
end

return function(t: Runner.T)
	for _, id in Roster.order do
		t.test("fighter select preview: " .. id .. "'s stance stands on planted feet under a moving body", function()
			local frames, seconds = measure(id)
			local n = #frames
			t.expect.truthy(n > 60, id .. ": a full stance loop was posed")
			local lowMin, lowMax, pelvisMin, pelvisMax = math.huge, -math.huge, math.huge, -math.huge
			for _, f in frames do
				lowMin, lowMax = math.min(lowMin, f.low), math.max(lowMax, f.low)
				pelvisMin, pelvisMax = math.min(pelvisMin, f.pelvis), math.max(pelvisMax, f.pelvis)
			end
			-- The frame n + 1 is the loop's first frame again: the seam is included.
			local jump, jumpAt, skateDist = 0, 0, 0
			for i = 1, n - 1 do
				local a, b = frames[i], frames[i + 1]
				for k = 1, 2 do
					local d = (b.feet[k].Position - a.feet[k].Position).Magnitude
					if d > jump then jump, jumpAt = d, i end
					local z = frames[math.max(i - 1, 1)]
					for _, pts in { { z.toes[k], a.toes[k], b.toes[k] }, { z.heels[k], a.heels[k], b.heels[k] } } do
						local p0, p1, p2 = pts[1], pts[2], pts[3]
						if i > 1 and p0.Y - PLATFORM <= TOUCH and p1.Y - PLATFORM <= TOUCH and p2.Y - PLATFORM <= TOUCH then
							skateDist += Vector3.new(p2.X - p1.X, 0, p2.Z - p1.Z).Magnitude
						end
					end
				end
			end
			local calib = frames[1].low
			local skateRate = skateDist / seconds
			local summary = string.format("%s: lower foot %+.3f..%+.3f (range %.3f; against the round-6 calibration %+.3f..%+.3f), pelvis range %.3f, worst foot step %.3f studs (frame %d), skate %.2f studs/s",
				id, lowMin, lowMax, lowMax - lowMin, lowMin - calib, lowMax - calib, pelvisMax - pelvisMin, jump, jumpAt, skateRate)
			print("[MotionPreview] " .. summary)
			local failed: { string } = {}
			local function check(ok: boolean, what: string) if not ok then table.insert(failed, what) end end
			check(lowMin >= FLOOR_SINK and lowMax <= LOW_MAX, string.format("the lower foot must stay within %.2f..%.2f of the floor RootHeight under the root", FLOOR_SINK, LOW_MAX))
			check(lowMax - lowMin <= LOW_RANGE, string.format("the lower foot must not travel more than %.2f up and down", LOW_RANGE))
			check(jump <= JUMP, string.format("no foot may move more than %.2f studs in a frame", JUMP))
			check(skateRate <= SKATE_RATE, string.format("feet touching the floor must not skate (%.1f studs/s at most)", SKATE_RATE))
			check(pelvisMax - pelvisMin >= (lowMax - lowMin) - 0.01, "the body must carry the bob (the pelvis moves at least as much as the lower foot)")
			t.expect.truthy(#failed == 0, summary .. "\n    - " .. table.concat(failed, "\n    - "))
		end)
	end

	t.test("fighter select preview: a new pose or place starts the preview over (no foot lock carried across)", function()
		local id = "Kael"
		local template = Lab:WaitForChild("Characters"):FindFirstChild(id) :: Model
		local model = template:Clone()
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then d.Anchored = d.Name == "HumanoidRootPart"; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false end
		end
		local rootHeight = model:GetAttribute("RootHeight") :: number
		model:PivotTo(CFrame.new(0, PLATFORM + rootHeight, -2620))
		model.Parent = workspace
		local rig = MotionPlayer.collectRig(model)
		for i = 0, 20 do CharacterPresenter.posePreview(model, id, "Stance", 50 + i / FPS) end
		-- Moved 30 studs (a pooled rig taken from its park spot): the feet come with the body at once.
		model:PivotTo(CFrame.new(30, PLATFORM + rootHeight, -2620))
		CharacterPresenter.posePreview(model, id, "Stance", 50 + 21 / FPS)
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
		for _, name in { "LeftFoot", "RightFoot" } do
			local foot = MotionPlayer.partWorld(rig, name) :: CFrame
			local flat = Vector3.new(foot.Position.X - root.Position.X, 0, foot.Position.Z - root.Position.Z)
			t.expect.truthy(flat.Magnitude < 2, string.format("%s %s stays under the moved body (%.2f studs from the root)", id, name, flat.Magnitude))
		end
		-- Intro after the stance at an earlier time: posed without error, finite joints.
		CharacterPresenter.posePreview(model, id, "Intro", 3)
		for _, d in model:GetDescendants() do
			if d:IsA("Motor6D") then
				local p = d.Transform.Position
				t.expect.truthy(p.X == p.X and p.Y == p.Y and p.Z == p.Z, "finite " .. d.Name)
			end
		end
		model:Destroy()
	end)
end
