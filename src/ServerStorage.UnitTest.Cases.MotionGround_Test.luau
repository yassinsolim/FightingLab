--!strict
-- Ground contact: knocked-down and KO fighters rest on the floor (no gap, no penetration) for every roster
-- template; standing, guarding, crouching and airborne poses never sink into the floor.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lab = ReplicatedStorage.FightingLab
local Config = require(Lab.CombatConfig)
local Roster = require(Lab.Roster)
local MotionPlayer = require(Lab.Client.MotionPlayer)
local ClipLibrary = require(Lab.Client.Motion.ClipLibrary)
local ClipPlayer = require(Lab.Client.Motion.ClipPlayer)

local BODY = { "LowerTorso", "UpperTorso", "Head", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot" }
local FLOOR_Y = 120

local function rootCFrame(pos: Vector3, facing: Vector3, rootHeight: number, offset: Vector3, base: Vector3): CFrame
	local floorPos = Vector3.new(base.X + pos.X, base.Y, base.Z + pos.Z)
	local forward = facing.Unit
	local right = forward:Cross(Vector3.yAxis).Unit
	local center = floorPos + Vector3.new(0, rootHeight + math.max(0, pos.Y), 0) + right * offset.X + Vector3.yAxis * offset.Y + forward * offset.Z
	return CFrame.lookAt(center, center + forward)
end

-- Lowest world Y of the visible body (engine part CFrames, same rounded-box measure as the solver).
local function lowestPoint(model: Model): (number, string)
	local lowest, which = math.huge, ""
	for _, name in BODY do
		local part = model:FindFirstChild(name, true)
		if part and part:IsA("BasePart") then
			local y = part.Position.Y - MotionPlayer.extentY(part.CFrame, part.Size)
			if y < lowest then lowest, which = y, name end
		end
	end
	return lowest, which
end

local function stage(id: string, x: number): (Model, any, BasePart)
	local clone = (Lab.Characters:FindFirstChild(id) :: Model):Clone()
	clone.Name = "GroundTest_" .. id
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") then d.Anchored = d.Name == "HumanoidRootPart"; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false end
	end
	clone.Parent = workspace
	local rig = MotionPlayer.collectRig(clone)
	local root = clone:FindFirstChild("HumanoidRootPart") :: BasePart
	return clone, rig, root
end

local function settle()
	RunService.Heartbeat:Wait()
	RunService.Heartbeat:Wait()
end

-- Samples `frames` frames of a state (crossfades finish) and poses the clone like CharacterPresenter does.
local function poseState(rig: any, root: BasePart, id: string, view: { [string]: any }, frames: number, x: number, slot: number): any
	MotionPlayer.reset(slot)
	view.characterId = id
	view.rootHeight = rig.rootHeight
	view.legLength = rig.legLength
	local pose
	for i = 1, frames do
		pose = MotionPlayer.sample(Config, view :: any, { now = i / 60, dt = 1 / 60, hitstop = 0, phase = "Fight", winner = 0, fighters = { view, { pos = Vector3.new(30, 0, 0), facing = -Vector3.xAxis } } }, slot)
	end
	local base = Vector3.new(x, FLOOR_Y, 300)
	root.CFrame = rootCFrame(view.pos, view.facing, rig.rootHeight, pose.rootOffset, base)
	MotionPlayer.apply(rig, pose, FLOOR_Y)
	return pose
end

local function view(state: string, extra: { [string]: any }?): { [string]: any }
	local v: { [string]: any } = { pos = Vector3.zero, facing = Vector3.xAxis, state = state, move = nil, moveFrame = 0, walkPhase = 0, stun = 0, crouched = false, moveX = 0 }
	if extra then for k, value in extra do v[k] = value end end
	return v
end

-- Move-clip sweep (step-in feet, lock release, capped step-ins) ------------------------------------------------------

local LEAD = 6
local SWEEP_SLOT = 47
local FEET = { "LeftFoot", "RightFoot" }
type Staged = { clone: Model, rig: any, root: BasePart }

local function stageAll(): { [string]: Staged }
	local rigs: { [string]: Staged } = {}
	for _, id in Roster.order do
		local clone, rig, root = stage(id, 0)
		rigs[id] = { clone = clone, rig = rig, root = root }
	end
	return rigs
end

local function destroyAll(rigs: { [string]: Staged })
	for _, r in rigs do r.clone:Destroy() end
	MotionPlayer.reset(SWEEP_SLOT)
end

-- Every installed move clip as playable cases { agent, label, id, n, at(f) -> (view, foe, clip?, t?), move, far, throw }:
-- attacks and grab attempts on their fighter's rig, throw tracks (both roles, normal and broken at mid break window)
-- with the defender on all six rigs; max range (the sim carries the root `advance` / startup studs per frame up to and
-- including the first active frame) and close range (Separation: keepApart cancels the advance). LEAD frames of the
-- held stance first.
-- Case groups of the move-clip sweeps (see the step-in and lock-release tests). The throw groups are split by the rig
-- that plays the track (the attacker's own rig for the attacker role, each defender's rig for the defender role).
local RIG_HALVES: { { [string]: boolean } } = { {}, {} }
local HALF_NAMES: { { string } } = { {}, {} }
for i, id in Roster.order do
	local h = if i <= math.ceil(#Roster.order / 2) then 1 else 2
	RIG_HALVES[h][id] = true
	table.insert(HALF_NAMES[h], id)
end
local GROUND_GROUPS: { any } = { { label = "attacks", throw = false } }
for _, far in { true, false } do
	for h = 1, 2 do
		table.insert(GROUND_GROUPS, { label = string.format("throws at %s range, %s rigs", if far then "max" else "close", table.concat(HALF_NAMES[h], ", ")), throw = true, far = far, ids = RIG_HALVES[h] })
	end
end
local function groupCases(cases: { any }, group: any): { any }
	local out = {}
	for _, c in cases do
		if (c.throw == true) == group.throw and (group.far == nil or c.far == group.far) and (group.ids == nil or group.ids[c.id]) then table.insert(out, c) end
	end
	return out
end
local function moveClipCases(rigs: { [string]: Staged }): { any }
	local SEP = (Config :: any).Separation or 2.6
	local BREAK_FRAMES = (Config :: any).ThrowBreakFrames or 16
	local ids: { [string]: string } = {}
	for _, id in Roster.order do ids[string.lower(id)] = id end
	local function agentOf(module: Instance): string
		local node = module
		while node.Parent and node.Parent.Name ~= "Moves" do node = node.Parent end
		return if node.Parent then node.Name else "?"
	end
	local function foeView(id: string, x: number): any
		local r = rigs[id].rig
		return view("Idle", { guard = "Stand", pos = Vector3.new(x, 0, 0), facing = -Vector3.xAxis, characterId = id, rootHeight = r.rootHeight, legLength = r.legLength })
	end
	local function moveSteps(id: string, key: string, m: any, clip: any, far: boolean): (number, (number) -> (any, any, any?, number?))
		local total = m.startup + m.active + m.recovery
		local crouching = m.crouching == true
		local resolved = MotionPlayer.resolveMove(id, key, rigs[id].rig.rootHeight)
		local step = if far then (m.advance or 0) / math.max(m.startup, 1) else 0
		local foe = foeView(id, if far then SEP + step * (m.startup + 1) + 0.5 else SEP)
		return LEAD + total, function(f: number)
			local mf = f - LEAD
			if mf < 1 then return view(if crouching then "Crouch" else "Idle", { crouched = crouching, guard = if crouching then "Crouch" else "Stand" }), foe, nil, nil end
			local state = if mf <= m.startup then "Startup" elseif mf <= m.startup + m.active then "Active" else "Recovery"
			local v = view(state, { move = key, moveFrame = mf, stringIndex = clip.stringIndex, crouched = crouching, pos = Vector3.new(step * math.min(mf, m.startup + 1), 0, 0) })
			return v, foe, clip, ClipPlayer.moveTime(clip, resolved.timing, mf)
		end
	end
	local function throwSteps(attackerId: string, defenderId: string, key: string, m: any, tc: any, role: string, dist: number, breakAt: number?): (number, (number) -> (any, any, any?, number?))
		local duration = m.duration or 46
		local impactFrame = m.impactFrame or 30
		return LEAD + (if breakAt then breakAt + BREAK_FRAMES else duration), function(f: number)
			local tf = f - LEAD
			local a = foeView(attackerId, 0)
			a.facing = Vector3.xAxis
			local d = foeView(defenderId, dist)
			local clip, t = nil, nil
			if tf >= 1 then
				local broken = breakAt ~= nil and tf > breakAt
				local function info(r: string): any
					return { role = r, move = key, archetype = (m.anim and m.anim.archetype) or "slam", frame = tf, duration = duration, impactFrame = impactFrame, breakWindow = m.breakWindow, broken = if broken then true else nil, breakFrame = if broken then breakAt else nil }
				end
				a.state, a.guard, a.throw = "Throw", nil, info("Attacker")
				d.state, d.guard, d.throw = "Throw", nil, info("Defender")
				if broken then
					clip = if role == "Defender" then tc.breakDefender else tc.breakAttacker
					if clip then t = math.clamp((tf - (breakAt :: number)) / BREAK_FRAMES, 0, 1) * clip.duration end
				else
					clip = if role == "Defender" then tc.defender else tc.attacker
					t = MotionPlayer.throwTime(tc.impact, tf, impactFrame, duration) * clip.duration
				end
			end
			if role == "Defender" then return d, a, clip, t end
			return a, d, clip, t
		end
	end
	local cases: { any } = {}
	local index = ClipLibrary.index()
	for _, name in ClipLibrary.list() do
		local entry = index[name]
		if not entry or entry.folder ~= "Moves" or type(entry.raw.move) ~= "string" then continue end
		local agent = agentOf(entry.module)
		local fighter = string.lower(tostring(entry.raw.fighter or "*"))
		local owners = if fighter == "*" then Roster.order else { ids[fighter] }
		for _, id in owners do
			if not id then continue end
			local key = entry.raw.move
			local m = Roster.getMove(id, key)
			if not m then continue end
			if entry.raw.format == ClipLibrary.THROW_FORMAT then
				local tc = ClipLibrary.forThrow(id, key)
				if not (tc and tc.name == name) then continue end
				local breakAt = math.max(2, math.floor((m.breakWindow or 20) / 2))
				for _, far in { true, false } do
					local dist = if far then math.max(m.range or 3.2, SEP + 0.05) else SEP
					for _, broken in { false, true } do
						local b = if broken then breakAt else nil
						local tag = string.format("%s %s%s", name, if far then "max" else "close", if broken then " broken" else "")
						local n, at = throwSteps(id, id, key, m, tc, "Attacker", dist, b)
						table.insert(cases, { agent = agent, clipName = name, label = tag .. " attacker", id = id, n = n, at = at, move = m, far = far, throw = true })
						for _, defender in Roster.order do
							local n2, at2 = throwSteps(id, defender, key, m, tc, "Defender", dist, b)
							table.insert(cases, { agent = agent, clipName = name, label = tag .. " defender " .. defender, id = defender, n = n2, at = at2, move = m, far = far, throw = true })
						end
					end
				end
			else
				local clip = ClipLibrary.get(name)
				if not (clip and ClipLibrary.forMove(id, key, clip.stringIndex) == clip) then continue end
				for _, far in { true, false } do
					local n, at = moveSteps(id, key, m, clip, far)
					table.insert(cases, { agent = agent, clipName = name, label = string.format("%s %s %s", name, id, if far then "max" else "close"), id = id, n = n, at = at, move = m, far = far, throw = false })
				end
			end
		end
	end
	return cases
end

-- Plays one case frame by frame on its staged rig; each(f, pose, view, clip, t) after every apply.
local sweepFrames = 0
local function playCase(rigs: { [string]: Staged }, case: any, each: (number, any, any, any?, number?) -> ())
	local r = rigs[case.id]
	local rig, root = r.rig, r.root
	MotionPlayer.reset(SWEEP_SLOT)
	table.clear(rig.footLock)
	for f = 1, case.n do
		local v, foe, clip, t = case.at(f)
		v.characterId = case.id; v.rootHeight = rig.rootHeight; v.legLength = rig.legLength
		local pose = MotionPlayer.sample(Config, v :: any, { now = f / 60, dt = 1 / 60, hitstop = 0, phase = "Fight", winner = 0, fighters = { foe, v } }, SWEEP_SLOT)
		root.CFrame = rootCFrame(v.pos, v.facing, rig.rootHeight, pose.rootOffset, Vector3.new(0, FLOOR_Y, 300))
		MotionPlayer.apply(rig, pose, FLOOR_Y)
		sweepFrames += 1
		if sweepFrames % 2000 == 0 then RunService.Heartbeat:Wait() end
		each(f, pose, v, clip, t)
	end
end

-- The clip's own sole height (leg lengths above the floor) of each displayed foot at clip time t.
local function clipSoles(clip: any, t: number): (number, number)
	local p = ClipPlayer.sample(clip, t, { mirror = clip.mirror, legLength = 1, scale = 1 })
	local function sole(foot: string): number return 1 + p.rootOffset.Y + (p.targets[foot].pos.Y - ClipPlayer.REF_HIP_Y) / ClipPlayer.REF_LEG end
	return sole("LeftFoot"), sole("RightFoot")
end

local function soleGap(rig: any, foot: string): number
	local tip = rig.tips[foot]
	local chain = rig.chains[if foot == "LeftFoot" then "LeftLeg" else "RightLeg"]
	return (tip * (chain.tipBox or CFrame.identity)).Position.Y - MotionPlayer.extentY(tip, chain.tipSize) - FLOOR_Y
end

local function topList(map: { [string]: number }, n: number): string
	local list = {}
	for k, v in map do table.insert(list, { k = k, v = v }) end
	table.sort(list, function(x, y) return x.v > y.v end)
	local out = {}
	for i = 1, math.min(n, #list) do table.insert(out, string.format("%s %.2f", list[i].k, list[i].v)) end
	return if #out > 0 then table.concat(out, ", ") else "none"
end

return function(t)
	t.test("knocked down and KO fighters rest on the floor (all six, face up and down)", function()
		local worst, worstGap = "", -math.huge
		for index, id in Roster.order do
			local clone, rig, root = stage(id, index * 12)
			for _, case in {
				{ "KO", "FaceUp" }, { "KO", "FaceDown" }, { "Landing", "FaceUp" }, { "Landing", "FaceDown" },
			} do
				-- Mid-Landing (after the fall, before the getup starts), whatever the configured Landing length.
				local landingStun = math.max(1, math.floor((Config.LandingFrames or 26) * 0.35 + 0.5))
				poseState(rig, root, id, view(case[1], { knockdown = case[2], stun = if case[1] == "Landing" then landingStun else 0 }), 90, index * 12, 40)
				settle()
				local lowest, part = lowestPoint(clone)
				local gap = lowest - FLOOR_Y
				t.expect.truthy(gap > -0.04, string.format("%s %s %s sinks %.3f (%s)", id, case[1], case[2], gap, part))
				t.expect.truthy(gap < 0.15, string.format("%s %s %s floats %.3f (%s)", id, case[1], case[2], gap, part))
				t.expect.truthy(math.abs(rig.stats.lowest - gap) < 0.05, string.format("%s %s solver/engine agree (%.3f vs %.3f)", id, case[1], rig.stats.lowest, gap))
				if gap > worstGap then worst, worstGap = id .. " " .. case[1] .. " " .. case[2], gap end
				-- The whole body lies on the floor, not only its thickest part: pelvis, feet and (face up) head rest on it.
				local function partGap(name: string): number
					local p = clone:FindFirstChild(name, true) :: BasePart
					return p.Position.Y - MotionPlayer.extentY(p.CFrame, p.Size) - FLOOR_Y
				end
				local pelvis = partGap("LowerTorso")
				t.expect.truthy(pelvis < (if case[1] == "KO" then 0.1 else 0.12), string.format("%s %s %s pelvis floats %.3f", id, case[1], case[2], pelvis))
				if case[1] == "KO" then
					local feet = math.max(partGap("LeftFoot"), partGap("RightFoot"))
					t.expect.truthy(feet < (if case[2] == "FaceDown" then 0.15 else 0.35), string.format("%s KO %s feet float %.3f", id, case[2], feet))
					if case[2] == "FaceUp" then
						local head = partGap("Head")
						t.expect.truthy(head < 0.2, string.format("%s KO FaceUp head floats %.3f", id, head))
					else
						-- Face down: the shins lie on the floor and the relaxed feet show their soles (instep on the floor).
						local shins = math.max(partGap("LeftLowerLeg"), partGap("RightLowerLeg"))
						t.expect.truthy(shins < 0.15, string.format("%s KO FaceDown shins raised %.3f", id, shins))
						for _, foot in { "LeftFoot", "RightFoot" } do
							local up = (clone:FindFirstChild(foot, true) :: BasePart).CFrame.UpVector.Y
							t.expect.truthy(up < -0.3, string.format("%s KO FaceDown %s not relaxed (instep up %.2f)", id, foot, up))
						end
					end
				end
			end
			clone:Destroy()
		end
		print(string.format("[MotionGround] worst lying gap %.3f studs (%s)", worstGap, worst))
	end)

	t.test("standing, guard, crouch, hit and airborne poses never sink into the floor", function()
		for index, id in Roster.order do
			local clone, rig, root = stage(id, index * 12)
			for _, v in {
				view("Idle"), view("Block"), view("Crouch", { crouched = true }), view("Walk", { moveX = 1 }),
				view("Hitstun", { stun = 12, lastHit = { kind = "Hit", height = "Low", tier = "Heavy", counter = true, frame = 5, move = "X", limb = "LeadLeg", side = 1 } }),
				view("Airborne", { pos = Vector3.new(0, 2.5, 0), velocityY = -6, airFrames = 20, airHits = 1 }),
				view("Getup", { knockdown = "FaceDown", stun = 7 }),
			} do
				poseState(rig, root, id, v, 30, index * 12, 41)
				settle()
				local lowest, part = lowestPoint(clone)
				t.expect.truthy(lowest - FLOOR_Y > -0.04, string.format("%s %s sinks %.3f (%s)", id, v.state, lowest - FLOOR_Y, part))
			end
			clone:Destroy()
		end
	end)

	t.test("planted feet do not skate in the stance or the walk", function()
		-- All six styles: the style yaw turns the stance, never the stride (a turned stride slid wide stances sideways).
		local results = {}
		for _, id in Roster.order do
			for _, case in { { "Idle", 0 }, { "Walk", 1 }, { "Backwalk", -1 } } do
				local state, dir = case[1], case[2]
				local clone, rig, root = stage(id, 0)
				local speed = if dir > 0 then Roster.get(id).stats.walkSpeed elseif dir < 0 then Roster.get(id).stats.backSpeed else 0
				MotionPlayer.reset(42)
				local segStart: { [string]: Vector3? } = {}
				local last: { [string]: Vector3? } = {}
				local worst, worstFoot = 0, ""
				local slid, plantedTime = 0, 0
				local x = 0
				for i = 1, 210 do
					x += dir * speed / 60
					local v = view(state, { pos = Vector3.new(x, 0, 0), moveX = dir, characterId = id, rootHeight = rig.rootHeight, legLength = rig.legLength })
					local pose = MotionPlayer.sample(Config, v :: any, { now = i / 60, dt = 1 / 60, hitstop = 0, phase = "Fight", winner = 0 }, 42)
					root.CFrame = rootCFrame(v.pos, v.facing, rig.rootHeight, pose.rootOffset, Vector3.new(0, FLOOR_Y, 300))
					MotionPlayer.apply(rig, pose, FLOOR_Y)
					if i > 30 then
						for _, foot in { "LeftFoot", "RightFoot" } do
							local contact = (pose.contact and pose.contact[foot]) or 0
							local tip = rig.tips[foot]
							if contact >= 0.9 and tip then
								local p = Vector3.new(tip.Position.X, 0, tip.Position.Z)
								local s = segStart[foot]
								if not s then segStart[foot] = p else
									local d = (p - s).Magnitude
									if d > worst then worst, worstFoot = d, foot end
								end
								local l = last[foot]
								if l then slid += (p - l).Magnitude; plantedTime += 1 / 60 end
								last[foot] = p
							else
								segStart[foot] = nil
								last[foot] = nil
							end
						end
					end
				end
				clone:Destroy()
				local rate = if plantedTime > 0 then slid / plantedTime else 0
				table.insert(results, string.format("%s %s %.3f (%.2f/s)", id, state, worst, rate))
				t.expect.truthy(worst < (if dir == 0 then 0.15 else 0.35), string.format("%s %s planted %s skates %.3f studs", id, state, worstFoot, worst))
				t.expect.truthy(rate < 0.35, string.format("%s %s planted feet slide %.2f studs/s", id, state, rate))
			end
		end
		print("[MotionGround] planted-foot drift (max per contact, mean while planted): " .. table.concat(results, " | "))
	end)

	t.test("planted feet rest on the floor: stances, walks, crouch guard, crouching and low moves, getup ends", function()
		-- Every foot the clip plants shows its lowest point on the floor (flattened sole-down, or on its ball when the leg
		-- is too straight for a flat foot) within 0.03 studs, and no foot ever sinks below -0.03. "Planted" = a sustained
		-- contact: the clip's contact channel (mocap: sole within ~0.045 leg lengths of the floor) leads a touchdown and
		-- lags a lift-off by a frame or two, so the EDGE frames at each end of a contact phase are transitions.
		local TOL, EDGE = 0.03, 2
		local L = Config.LandingFrames or 34
		local FEET = { "LeftFoot", "RightFoot" }
		-- Plays one case on a staged rig; returns the worst error over [from, to] and the planted foot-frame counts.
		local function run(rig: any, root: BasePart, id: string, case: any): (number, string, number, number, number)
			MotionPlayer.reset(44)
			table.clear(rig.footLock)
			local gaps: { [string]: { number } } = { LeftFoot = {}, RightFoot = {} }
			local contacts: { [string]: { number } } = { LeftFoot = {}, RightFoot = {} }
			for f = 1, case.frames do
				local v = case.at(f)
				v.characterId = id; v.rootHeight = rig.rootHeight; v.legLength = rig.legLength
				local foe = { pos = v.pos + Vector3.new(3.5, 0, 0), facing = -Vector3.xAxis, state = "Idle" }
				local pose = MotionPlayer.sample(Config, v :: any, { now = f / 60, dt = 1 / 60, hitstop = 0, phase = "Fight", winner = 0, fighters = { v, foe } }, 44)
				root.CFrame = rootCFrame(v.pos, v.facing, rig.rootHeight, pose.rootOffset, Vector3.new(0, FLOOR_Y, 300))
				MotionPlayer.apply(rig, pose, FLOOR_Y)
				for _, foot in FEET do
					local tip = rig.tips[foot]
					local chain = rig.chains[if foot == "LeftFoot" then "LeftLeg" else "RightLeg"]
					gaps[foot][f] = if tip then (tip * (chain.tipBox or CFrame.identity)).Position.Y - MotionPlayer.extentY(tip, chain.tipSize) - FLOOR_Y else 0
					contacts[foot][f] = (pose.contact and pose.contact[foot]) or 0
				end
			end
			local worst, worstFoot, worstFrame, planted, over = 0, "", 0, 0, 0
			for f = case.from, case.to do
				for _, foot in FEET do
					local sustained = true
					for g = math.max(1, f - EDGE), math.min(case.frames, f + EDGE) do
						if contacts[foot][g] < 0.9 then sustained = false; break end
					end
					local gap = gaps[foot][f]
					local err = if sustained then math.abs(gap) else math.max(0, -gap)
					if sustained then planted += 1; if err > TOL then over += 1 end end
					if err > worst then worst, worstFoot, worstFrame = err, foot, f end
				end
			end
			return worst, worstFoot, worstFrame, planted, over
		end
		local function moveCase(id: string, key: string): any
			local m = Roster.getMove(id, key)
			local lead, total = 12, m.startup + m.active + m.recovery
			local crouching = m.crouching == true
			local function hold(): any return view(if crouching then "Crouch" else "Idle", { crouched = crouching, guard = if crouching then "Crouch" else "Stand" }) end
			-- From a held crouch or stance, then back to it; the sim carries the root by `advance` over the startup.
			return { name = key, frames = lead + total + EDGE + 1, from = lead + 1, to = lead + total, at = function(f)
				local mf = f - lead
				if mf < 1 then return hold() end
				local carried = Vector3.new((m.advance or 0) * math.min(mf, m.startup) / math.max(m.startup, 1), 0, 0)
				if mf > total then local v = hold(); v.pos = carried; return v end
				local state = if mf <= m.startup then "Startup" elseif mf <= m.startup + m.active then "Active" else "Recovery"
				return view(state, { move = key, moveFrame = mf, stringIndex = if m.chainFrom then 2 else 1, crouched = crouching, pos = carried })
			end }
		end
		local report = {}
		local overall, overallWhere = 0, ""
		local sweepPlanted, sweepOver, sweepList = 0, 0, {}
		for _, id in Roster.order do
			local clone, rig, root = stage(id, 0)
			local character = Roster.get(id)
			local walk, back = character.stats.walkSpeed or 5, character.stats.backSpeed or 4
			local cases: { any } = {
				{ name = "Idle", frames = 100, from = 40, to = 100 - EDGE, at = function(_f) return view("Idle", { guard = "Stand" }) end },
				{ name = "Walk", frames = 130, from = 40, to = 130 - EDGE, at = function(f) return view("Walk", { guard = "Stand", moveX = 1, pos = Vector3.new(f * walk / 60, 0, 0) }) end },
				{ name = "Backwalk", frames = 130, from = 40, to = 130 - EDGE, at = function(f) return view("Backwalk", { guard = "Stand", moveX = -1, pos = Vector3.new(-f * back / 60, 0, 0) }) end },
				{ name = "CrouchGuard", frames = 90, from = 30, to = 90 - EDGE, at = function(f) return view("Crouch", { crouched = true, guard = "Crouch", crouchFrames = f }) end },
			}
			-- Crouching and low moves (CrouchJab, DuckJab, LowPunch, low kicks, sweeps...).
			local keys, others = {}, {}
			for key, m in character.moves do
				if m.crouching == true or m.height == "Low" then table.insert(keys, key) elseif m.height ~= "Throw" then table.insert(others, key) end
			end
			table.sort(keys)
			table.sort(others)
			for _, key in keys do table.insert(cases, moveCase(id, key)) end
			-- Getups (stand, back roll, side roll; face up and down): the last frames before the fighter is free again.
			for _, kind in { "Stand", "BackRoll", "SideRoll" } do
				for _, face in { "FaceUp", "FaceDown" } do
					local G = (Config.GetupFrames or 26) + (if kind == "Stand" then 0 else (Config.RollFrames or 10))
					table.insert(cases, { name = "Getup" .. kind .. face, frames = L + G + EDGE + 1, from = L + G - 2, to = L + G, at = function(f)
						if f <= L then return view("Landing", { knockdown = face, stun = L - f, getupKind = if f > 8 then kind else nil, rollDir = 1 }) end
						local u = 1 - (1 - math.clamp((f - L) / 10, 0, 1)) ^ 2
						local pos = if kind == "BackRoll" then Vector3.new(-2.2 * u, 0, 0) elseif kind == "SideRoll" then Vector3.new(0, 0, -2.2 * u) else Vector3.zero
						if f > L + G then return view("Idle", { guard = "Stand", pos = pos }) end
						return view("Getup", { knockdown = face, stun = L + G - f + 1, getupKind = kind, rollDir = 1, pos = pos })
					end })
				end
			end
			for index, case in cases do
				local worst, worstFoot, worstFrame = run(rig, root, id, case)
				if index == 1 then
					-- The analytic foot frames agree with the engine's (part CFrames follow the Motor6Ds after a step).
					settle()
					for _, foot in FEET do
						local part = clone:FindFirstChild(foot, true) :: BasePart
						t.expect.truthy((part.Position - rig.tips[foot].Position).Magnitude < 0.02, string.format("%s %s solver/engine foot agree", id, foot))
					end
				end
				t.expect.truthy(worst <= TOL, string.format("%s %s: planted %s sole gap %.3f studs at frame %d", id, case.name, worstFoot, worst, worstFrame))
				table.insert(report, string.format("%s %s %.3f", id, case.name, worst))
				if worst > overall then overall, overallWhere = worst, id .. " " .. case.name .. " " .. worstFoot end
			end
			-- Information only (clip-level, not asserted): every other move of the fighter.
			for _, key in others do
				local worst, _, _, planted, over = run(rig, root, id, moveCase(id, key))
				sweepPlanted += planted
				sweepOver += over
				if over > 0 then table.insert(sweepList, string.format("%s.%s %.3f (%d f)", id, key, worst, over)) end
			end
			clone:Destroy()
		end
		print(string.format("[MotionGround] planted-foot sole gap: worst %.3f studs (%s); per case: %s", overall, overallWhere, table.concat(report, " | ")))
		print(string.format("[MotionGround] all other moves (information): %d planted foot-frames, %d over %.2f studs: %s", sweepPlanted, sweepOver, TOL, if #sweepList > 0 then table.concat(sweepList, ", ") else "none"))
	end)

	-- The two sweeps over every move clip run in five groups (attacks; throws at max and at close range, each split by
	-- the rig that plays the track) so each test stays well inside the runner's time limit (round 5: the knockdown and
	-- thrown-defender clearance made a throw frame dearer). Same cases, same targets.
	for _, group in GROUND_GROUPS do
		t.test("move clips never lift a foot the clip holds on the floor (every move clip, both throw roles, max and close range): " .. group.label, function()
			-- Step-ins: the sim carries the attacker's root forward by `advance` over the startup (at close range keepApart
			-- cancels it) while the rear foot stays planted or trails, and a keyed clip can place a foot beyond a rig's leg
			-- reach; the IK clamp then lifted the foot off the floor. Wherever the displayed pose's own sole (the clip's,
			-- blended through crossfades) is within GATE leg lengths of the floor, the shown foot's lowest point stays within
			-- TOL studs of the height the runtime intends for it (MotionPlayer rig.footClear: 0 for a planted foot, the clip's
			-- own clearance for a released one; the clip's sole height on this rig when the runtime does not report it).
			-- Every installed move clip (Moves.Strikes / Kicks / Throws: attacks, grab attempts, both throw roles and their
			-- break tracks) on its fighter's rig — throw defenders on all six rigs — at max range (full sim advance) and at
			-- close range (Separation: no advance). A foot the contact aim layer pulls to the opponent (aimWeight > 0) is the
			-- strike itself and is not gated. Information: feet shown more than TOL above the floor at all (clip-side hover:
			-- released near-floor feet, feet of a pelvis posed differently from the clip's).
			local GATE, TOL = 0.05, 0.05
			local rigs = stageAll()
			local cases = groupCases(moveClipCases(rigs), group)
			type Stat = { checked: number, lifts: number, worst: number, where: string, over: number, worstGap: number, gapWhere: string, liftClips: { [string]: number }, gapClips: { [string]: number }, plays: number }
			local stats: { [string]: Stat } = {}
			local played: { [string]: boolean } = {}
			local before = sweepFrames
			for _, case in cases do
				local s = stats[case.agent]
				if not s then
					s = { checked = 0, lifts = 0, worst = 0, where = "-", over = 0, worstGap = 0, gapWhere = "-", liftClips = {}, gapClips = {}, plays = 0 }
					stats[case.agent] = s
				end
				s.plays += 1
				played[case.clipName] = true
				local rig = rigs[case.id].rig
				playCase(rigs, case, function(f: number, pose: any, _v: any, clip: any?, t: number?)
					if not (clip and t) then return end
					local soleL, soleR = clipSoles(clip, t)
					for i, foot in FEET do
						local e = pose.targets[foot]
						-- The displayed pose's own sole (crossfades blend it) when the runtime reports it, else the clip's.
						local sole = (e and e.sole) or (if i == 1 then soleL else soleR)
						if sole <= GATE and not (e and (e.aimWeight or 0) > 0.01) then
							local gap = soleGap(rig, foot)
							local intended = if rig.footClear and rig.footClear[foot] then rig.footClear[foot] else math.max(sole, 0) * rig.legLength
							local lift = gap - intended
							local key = case.label .. " " .. foot
							s.checked += 1
							if lift > TOL then
								s.lifts += 1
								s.liftClips[key] = math.max(s.liftClips[key] or 0, lift)
							end
							if lift > s.worst then s.worst, s.where = lift, string.format("%s f%d", key, f - LEAD) end
							if gap > TOL then
								s.over += 1
								s.gapClips[key] = math.max(s.gapClips[key] or 0, gap)
							end
							if gap > s.worstGap then s.worstGap, s.gapWhere = gap, string.format("%s f%d (clip sole %.3f L)", key, f - LEAD, sole) end
						end
					end
				end)
			end
			destroyAll(rigs)
			local count = 0
			for _ in played do count += 1 end
			local agents = {}
			for agent in stats do table.insert(agents, agent) end
			table.sort(agents)
			print(string.format("[MotionGround] step-in feet: %d move clips played (%d frames); net %s", count, sweepFrames - before, tostring((MotionPlayer :: any).FootReachNet)))
			for _, agent in agents do
				local s = stats[agent]
				print(string.format("[MotionGround] step-in feet %s: %d plays, %d gated foot-frames; lifted above the intended height by > %.2f: %d (worst %.3f, %s) | top: %s", agent, s.plays, s.checked, TOL, s.lifts, s.worst, s.where, topList(s.liftClips, 10)))
				print(string.format("[MotionGround] step-in feet %s (information): displayed sole > %.2f above the floor: %d foot-frames (worst %.3f, %s) | top: %s", agent, TOL, s.over, s.worstGap, s.gapWhere, topList(s.gapClips, 8)))
			end
			t.expect.truthy(count >= 1, "move clips installed")
			for _, agent in agents do
				local s = stats[agent]
				t.expect.truthy(s.lifts == 0, string.format("%s: %d foot-frames lifted off the floor (worst %.3f studs above the intended height, %s)", agent, s.lifts, s.worst, s.where))
			end
		end)
	end

	for _, group in GROUND_GROUPS do
		t.test("a released foot lock lets go smoothly: no foot snaps when its contact drops (every move clip, max and close range): " .. group.label, function()
			-- A planted foot is locked in world space; where the body travels differently from the clip (keepApart capping a
			-- step-in's root, pushback) the anchor holds the foot up to the leash away from the clip's spot. When the contact
			-- drops, the lock lets go over MotionPlayer.FootLockRelease instead of in one frame, and a foot landing again
			-- while still letting go locks where it is shown: around every release and re-landing (the frames up to WINDOW
			-- after a contact below 0.5) the shown foot never moves more than JUMP studs in a frame beyond the clip's own foot
			-- motion (the same play with the leash at 0, where the foot follows the clip) plus a quarter of that foot's speed
			-- over the last frames. Steady locks are not gated: there the reach net may slide a held foot. Every installed
			-- move clip as in the step-in test.
			local JUMP, WINDOW = 0.2, 5
			local rigs = stageAll()
			local cases = groupCases(moveClipCases(rigs), group)
			local leash = MotionPlayer.FootLockLeash
			local worst: { [string]: { v: number, where: string, over: number, clips: { [string]: number } } } = {}
			local ok, err = pcall(function()
				for _, case in cases do
					local rig = rigs[case.id].rig
					local contacts: { [string]: { number } } = { LeftFoot = {}, RightFoot = {} }
					local function path(free: boolean): { [string]: { Vector3 } }
						MotionPlayer.FootLockLeash = if free then 0 else leash
						local out = { LeftFoot = {}, RightFoot = {} }
						playCase(rigs, case, function(f: number, pose: any)
							for _, foot in FEET do
								local p = rig.tips[foot].Position
								out[foot][f] = Vector3.new(p.X, 0, p.Z)
								contacts[foot][f] = (pose.contact and pose.contact[foot]) or 0
							end
						end)
						return out
					end
					local held, free = path(false), path(true)
					local w = worst[case.agent]
					if not w then
						w = { v = 0, where = "-", over = 0, clips = {} }
						worst[case.agent] = w
					end
					for _, foot in FEET do
						local a, b, c = held[foot], free[foot], contacts[foot]
						for f = LEAD + 2, case.n do
							local near = false
							for g = math.max(1, f - WINDOW), f do
								if c[g] < 0.5 then near = true; break end
							end
							if near then
								-- A foot already moving fast (a kick whipping out of its lock, a break shove) may lag and catch up
								-- by a quarter of its recent speed; a foot at rest may not jump.
								local recent = 0
								for g = math.max(LEAD + 2, f - 2), f do recent = math.max(recent, (b[g] - b[g - 1]).Magnitude) end
								local extra = (a[f] - a[f - 1]).Magnitude - (b[f] - b[f - 1]).Magnitude - 0.25 * recent
								if extra > JUMP then
									w.over += 1
									local key = case.label .. " " .. foot
									w.clips[key] = math.max(w.clips[key] or 0, extra)
								end
								if extra > w.v then w.v, w.where = extra, string.format("%s %s f%d", case.label, foot, f - LEAD) end
							end
						end
					end
				end
			end)
			MotionPlayer.FootLockLeash = leash
			destroyAll(rigs)
			if not ok then error(err, 0) end
			local agents = {}
			for agent in worst do table.insert(agents, agent) end
			table.sort(agents)
			for _, agent in agents do
				local w = worst[agent]
				print(string.format("[MotionGround] lock release %s: worst extra foot jump %.3f studs/frame (%s); %d foot-frames over %.2f | top: %s", agent, w.v, w.where, w.over, JUMP, topList(w.clips, 8)))
			end
			for _, agent in agents do
				local w = worst[agent]
				t.expect.truthy(w.over == 0, string.format("%s: a released foot snapped %.3f studs in one frame beyond its clip motion (%s)", agent, w.v, w.where))
			end
		end)
	end

	t.test("a support leg crossing its reach limit never flips its planted foot onto the toes (slow pelvis lift, all six, stance and walk)", function()
		-- Round 4 (Sierra's teep kick at Width .85, max range: a 0.223-stud foot snap on lock release). A planted foot whose
		-- straight leg missed the flat foot by a hair rose onto its ball by the full tiptoe limit (60 degrees) even where
		-- rising did not lift its ankle (a bare foot with the ankle over the toes), the reach net slid its anchor, and the
		-- next frame it slapped flat again. Raising the pelvis slowly (RATE studs a frame, up to TOP above the clip) through
		-- the reach limit and back down, no foot turns more than MAX_STEP degrees in one frame.
		local MAX_STEP, RATE, TOP, LEADF = 30, 0.005, 0.25, 20
		local up = math.floor(TOP / RATE + 0.5)
		local worst, where = 0, "-"
		for _, id in Roster.order do
			local clone, rig, root = stage(id, 0)
			for _, state in { "Idle", "Walk" } do
				MotionPlayer.reset(SWEEP_SLOT)
				MotionPlayer.resetRig(rig)
				local v = view(state, { guard = "Stand", characterId = id, rootHeight = rig.rootHeight, legLength = rig.legLength })
				local base = Vector3.new(0, FLOOR_Y, 300)
				local prev: { [string]: CFrame } = {}
				for i = 1, LEADF + 2 * up + 20 do
					if state == "Walk" then
						v.pos = Vector3.new(i * 0.04, 0, 0)
						v.walkPhase = i * 0.04
					end
					local ctx = { now = i / 60, dt = 1 / 60, hitstop = 0, phase = "Fight", winner = 0, fighters = { v, { pos = Vector3.new(30, 0, 0), facing = -Vector3.xAxis } } }
					local pose = MotionPlayer.sample(Config, v :: any, ctx :: any, SWEEP_SLOT)
					local k = i - LEADF
					local lift = if k <= 0 then 0 elseif k <= up then k * RATE elseif k <= 2 * up then (2 * up - k) * RATE else 0
					pose.rootOffset += Vector3.new(0, lift, 0)
					root.CFrame = rootCFrame(v.pos, v.facing, rig.rootHeight, pose.rootOffset, base)
					MotionPlayer.apply(rig, pose, FLOOR_Y)
					for _, foot in FEET do
						local cf = rig.tips[foot] :: CFrame
						local p = prev[foot]
						if p and i > LEADF + 1 then
							local _, angle = p:ToObjectSpace(cf):ToAxisAngle()
							local deg = math.deg(math.abs(angle))
							if deg > worst then worst, where = deg, string.format("%s %s %s lift %.3f", id, state, foot, lift) end
						end
						prev[foot] = cf
					end
				end
			end
			clone:Destroy()
		end
		MotionPlayer.reset(SWEEP_SLOT)
		print(string.format("[MotionGround] reach-limit pelvis lift: worst foot turn %.1f deg/frame (%s)", worst, where))
		t.expect.truthy(worst <= MAX_STEP, string.format("a foot turned %.1f degrees in one frame at the reach limit (%s)", worst, where))
	end)

	t.test("a step-in held back at Separation does not step in place (every step-in clip, close range)", function()
		-- At close range keepApart cancels a step-in's `advance`: the body stays while the clip steps. A released foot the
		-- clip keeps near the floor (own sole <= 0.12 leg lengths) lifts only the applied / designed share of its clip
		-- clearance (MotionPlayer.sample pose.stepScale), so with no advance applied it stays on the floor (lowest point
		-- within TOL) instead of lifting in place. The designed advance counts from the move's first frame, as the
		-- runtime's; frames before it reaches 0.05 * scale, and the 0.05 s fade-in from the stance, are not gated.
		local TOL, NEAR = 0.05, 0.12
		local rigs = stageAll()
		local cases = moveClipCases(rigs)
		local stats: { [string]: { checked: number, over: number, worst: number, where: string, clips: { [string]: number } } } = {}
		for _, case in cases do
			local m = case.move
			if case.far or case.throw or type(m.advance) ~= "number" or m.advance <= 0 then continue end
			local rig = rigs[case.id].rig
			local scale = MotionPlayer.scaleFromRoot(rig.rootHeight)
			local s = stats[case.agent]
			if not s then
				s = { checked = 0, over = 0, worst = 0, where = "-", clips = {} }
				stats[case.agent] = s
			end
			local startup = math.max(m.startup, 1)
			playCase(rigs, case, function(f: number, pose: any, _v: any, clip: any?, t: number?)
				local mf = f - LEAD
				-- The first frames blend in from the stance (0.05 s fade).
				if not (clip and t) or mf < 4 then return end
				if m.advance / startup * (math.min(mf, startup + 1) - 1) <= 0.05 * scale then return end
				if (pose.ground or 0) > 0.5 then return end
				local soleL, soleR = clipSoles(clip, t)
				for i, foot in FEET do
					local e = pose.targets[foot]
					local sole = (e and e.sole) or (if i == 1 then soleL else soleR)
					if sole <= NEAR and not (e and (e.aimWeight or 0) > 0.01) then
						local gap = soleGap(rig, foot)
						s.checked += 1
						local key = case.label .. " " .. foot
						if gap > TOL then
							s.over += 1
							s.clips[key] = math.max(s.clips[key] or 0, gap)
						end
						if gap > s.worst then s.worst, s.where = gap, string.format("%s f%d", key, mf) end
					end
				end
			end)
		end
		destroyAll(rigs)
		local agents = {}
		for agent in stats do table.insert(agents, agent) end
		table.sort(agents)
		for _, agent in agents do
			local s = stats[agent]
			print(string.format("[MotionGround] capped step-in %s: %d near-floor foot-frames, %d shown > %.2f above the floor (worst %.3f, %s) | top: %s", agent, s.checked, s.over, TOL, s.worst, s.where, topList(s.clips, 8)))
		end
		t.expect.truthy(#agents >= 1, "step-in clips installed")
		for _, agent in agents do
			local s = stats[agent]
			t.expect.truthy(s.over == 0, string.format("%s: %d near-floor foot-frames step in place at close range (worst %.3f studs, %s)", agent, s.over, s.worst, s.where))
		end
	end)
	t.test("a juggle ending face down falls into the knockdown and lands on the floor", function()
		-- combat: a juggle-ending hit keeps the fighter Airborne with `knockdown` set until pos.Y reaches 0, then Landing.
		local clone, rig, root = stage("Nia", 0)
		MotionPlayer.reset(43)
		local g, y, vy = 44, 3.2, 2.0
		local lowestDuringFall = math.huge
		local landingFrames = Config.LandingFrames or 26
		local lyingGap = math.huge
		for i = 1, 120 do
			local v
			if y > 0 then
				vy -= g / 60
				y = math.max(0, y + vy / 60)
			end
			if y > 0 then
				v = view("Airborne", { pos = Vector3.new(0, y, 0), velocityY = vy, airFrames = i, airHits = 2, knockdown = "FaceDown" })
			else
				v = view("Landing", { knockdown = "FaceDown", stun = math.max(0, landingFrames - 6) })
			end
			v.characterId = "Nia"; v.rootHeight = rig.rootHeight; v.legLength = rig.legLength
			local pose = MotionPlayer.sample(Config, v :: any, { now = i / 60, dt = 1 / 60, hitstop = 0, phase = "Fight", winner = 0 }, 43)
			root.CFrame = rootCFrame(v.pos, v.facing, rig.rootHeight, pose.rootOffset, Vector3.new(0, FLOOR_Y, 300))
			MotionPlayer.apply(rig, pose, FLOOR_Y)
			-- The solver's analytic lowest point (checked against the engine in the first test): part CFrames only follow
			-- Motor6D transforms after an engine step.
			local lowest = rig.stats.lowest
			if y > 0 then lowestDuringFall = math.min(lowestDuringFall, lowest) end
			if v.state == "Landing" then lyingGap = lowest; if i > 60 then break end end
		end
		settle()
		local engineLowest = lowestPoint(clone)
		clone:Destroy()
		t.expect.truthy(lowestDuringFall > -0.04, string.format("falling body never sinks (%.3f)", lowestDuringFall))
		t.expect.truthy(lyingGap > -0.04 and lyingGap < 0.15, string.format("landed face down on the floor (gap %.3f)", lyingGap))
		t.expect.truthy(math.abs((engineLowest - FLOOR_Y) - lyingGap) < 0.05, string.format("engine agrees (%.3f vs %.3f)", engineLowest - FLOOR_Y, lyingGap))
	end)

	t.test("solver lifts a sunk pose and keeps the caller's root placement", function()
		local clone, rig, root = stage("Goran", 0)
		local pose = MotionPlayer.toHeading(MotionPlayer.poseFromKey({ t = 0, rootOffset = Vector3.new(0, -4, 0), rootRotation = Vector3.new(math.rad(90), 0, 0) } :: any), 1.2)
		root.CFrame = CFrame.new(0, FLOOR_Y + rig.rootHeight - 4, 300)
		local before = root.CFrame
		MotionPlayer.apply(rig, pose, FLOOR_Y)
		settle()
		t.expect.equal(root.CFrame, before, "root part untouched")
		local lowest = lowestPoint(clone)
		t.expect.truthy(lowest - FLOOR_Y > -0.04 and lowest - FLOOR_Y < 0.15, string.format("lying body on the floor (%.3f)", lowest - FLOOR_Y))
		clone:Destroy()
	end)
end
