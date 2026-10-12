--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lab = ReplicatedStorage.FightingLab
local Config = require(Lab.CombatConfig)
local Roster = require(Lab.Roster)
local MotionPlayer = require(Lab.Client.MotionPlayer)
local MotionLibrary = require(Lab.Client.MotionLibrary)
local CharacterPresenter = require(Lab.Client.CharacterPresenter)
local Throws = require(Lab.Client.Motion.Throws)
local States = require(Lab.Client.Motion.States)
local ClipLibrary = require(Lab.Client.Motion.ClipLibrary)

local function view(characterId: string, move: string?, moveFrame: number, state: string?): any
	return { pos = Vector3.zero, facing = Vector3.xAxis, state = state or "Idle", move = move, moveFrame = moveFrame, walkPhase = 0, stun = 0, crouched = false, moveX = 0, extrapolated = 0, characterId = characterId, rootHeight = Roster.get(characterId).stats.height * 0.5 }
end
local function finiteVector(v: Vector3): boolean return v.X == v.X and v.Y == v.Y and v.Z == v.Z and math.abs(v.X) < math.huge and math.abs(v.Y) < math.huge and math.abs(v.Z) < math.huge end
local function finiteCFrame(cframe: CFrame): boolean local comps = { cframe:GetComponents() }; for _, n in comps do if n ~= n or math.abs(n) == math.huge then return false end end; return true end
local function activeFrame(characterId: string, moveKey: string): number return Roster.getMove(characterId, moveKey).startup + 1 end
local function target(pose: any, name: string): any local value = pose.targets[name]; if not value then error("missing target " .. name) end; return value end

return function(t)
	t.test("roster exposes every required character", function()
		t.expect.equal(#Roster.order, 6)
		for _, id in Roster.order do t.expect.truthy(Roster.has(id), id .. " exists"); t.expect.truthy(#Roster.get(id).moveOrder >= 10, id .. " has a move list") end
	end)

	t.test("resolves every roster move with finite keyframes", function()
		for _, id in Roster.order do
			for _, moveKey in Roster.get(id).moveOrder do
			local move = Roster.getMove(id, moveKey)
				MotionPlayer.clearCache()
				local resolved = MotionPlayer.resolveMove(id, move.key, Roster.get(id).stats.height * 0.5)
				t.expect.equal(resolved.timing.startup, move.startup, id .. "." .. move.key .. " startup")
				t.expect.equal(resolved.timing.active, move.active, id .. "." .. move.key .. " active")
				t.expect.equal(resolved.timing.recovery, move.recovery, id .. "." .. move.key .. " recovery")
				for _, key in resolved.keyframes do
					t.expect.truthy(type(key.t) == "number", id .. "." .. move.key .. " key has time")
					if key.rootOffset then t.expect.truthy(finiteVector(key.rootOffset), id .. "." .. move.key .. " finite root") end
				end
			end
		end
	end)

	t.test("anim params include side height scale neutral and stance", function()
		local resolved = MotionPlayer.resolveMove("Goran", "ShoulderTackle", 3.15)
		t.expect.equal(resolved.params.side, "Lead")
		t.expect.equal(resolved.params.height, "Mid")
		t.expect.near(resolved.params.scale, 1.05, 0.01)
		t.expect.equal(resolved.params.stance, "grappler")
		t.expect.truthy(resolved.params.neutral.targets ~= nil, "neutral stance is present")
	end)

	t.test("first active frame reaches contractual contact heights", function()
		local checks = { { "Kael", "Jab", "LeftHand" }, { "Sierra", "LegKick", "RightFoot" }, { "Rhys", "SideKick", "LeftFoot" } }
		for _, item in checks do
			local id, moveKey, effector = item[1], item[2], item[3]
			MotionPlayer.reset(1)
			local pose = MotionPlayer.sample(Config, view(id, moveKey, activeFrame(id, moveKey), "Active"), { now = 0, hitstop = 0, fighters = { view(id, moveKey, activeFrame(id, moveKey), "Active"), { pos = Vector3.new(4.0, 0, 0), facing = -Vector3.xAxis } } }, 1)
			local move = Roster.getMove(id, moveKey)
			local y = target(pose, effector).pos.Y
			if move.height == "High" then t.expect.truthy(y > 1.35, moveKey .. " high contact") elseif move.height == "Low" then t.expect.truthy(y < -1.8, moveKey .. " low contact") else t.expect.truthy(y > 0.2 and y < 1.1, moveKey .. " mid contact") end
		end
	end)

	t.test("stance styles produce distinct silhouettes", function()
		local seen: { [string]: boolean } = {}
		for _, id in Roster.order do
			local pose = States.neutral(id, 1)
			local lh = pose.targets and pose.targets.LeftHand and pose.targets.LeftHand.pos or Vector3.zero
			local rf = pose.targets and pose.targets.RightFoot and pose.targets.RightFoot.pos or Vector3.zero
			local signature = string.format("%.1f %.1f %.1f %.1f", lh.X, lh.Z, rf.X, rf.Z)
			t.expect.falsy(seen[signature], "stance for " .. id .. " is unique")
			seen[signature] = true
		end
	end)

	t.test("throw tracks align defender continuously and end grounded", function()
		for _, name in { "clinch_strike", "clinch_knees", "bear_hug_toss", "slam", "flip_toss", "hip_toss", "arm_toss" } do
			local track = Throws[name](50, 34)
			t.expect.equal(track.duration, 50)
			t.expect.equal(track.impactFrame, 34)
			local previous: Vector3? = nil
			for _, key in track.defender do
				local offset = key.rootOffset or Vector3.zero
				t.expect.truthy(finiteVector(offset), name .. " defender offset finite")
				if previous then t.expect.truthy((offset - previous).Magnitude < 3.1, name .. " defender offset continuity") end
				previous = offset
			end
			local contactAttacker = false
			local contactDefender = false
			for _, key in track.attacker do if key.t == 1/3 then contactAttacker = true end end
			for _, key in track.defender do if key.t == 1/3 then contactDefender = true end end
			t.expect.truthy(contactAttacker, name .. " attacker has exact contact key")
			t.expect.truthy(contactDefender, name .. " defender has exact contact key")
			local last = track.defender[#track.defender].rootOffset or Vector3.zero
			t.expect.truthy(last.Y < -0.9, name .. " defender ends lying down")
		end
	end)

	t.test("resolved throw moves expose exact first active contact", function()
		for _, id in Roster.order do
			for _, moveKey in Roster.get(id).moveOrder do
				local move = Roster.getMove(id, moveKey)
				if move.height == "Throw" then
					MotionPlayer.clearCache()
					local resolved = MotionPlayer.resolveMove(id, moveKey, Roster.get(id).stats.height * 0.5)
					local hasContact = false
					for _, key in resolved.keyframes do if key.t == 1 then hasContact = true end end
					t.expect.truthy(hasContact, id .. "." .. moveKey .. " has t=1 contact")
				end
			end
		end
	end)

	t.test("states cover reactions knockdown getup ready victory defeat crush and armor", function()
		for _, height in { "High", "Mid", "Low" } do t.expect.truthy(finiteVector((States.reaction(height, "Heavy", true, 1).rootOffset :: Vector3)), height .. " reaction finite") end
		for _, id in Roster.order do t.expect.truthy(finiteVector((States.ready(id, 1).rootOffset :: Vector3)), id .. " ready"); t.expect.truthy(finiteVector((States.victory(id, 1).rootOffset :: Vector3)), id .. " victory") end
		t.expect.truthy(finiteVector((States.defeat(1).rootOffset :: Vector3)), "defeat")
		t.expect.truthy(finiteVector((States.knockdown(25, 1).rootOffset :: Vector3)), "knockdown")
		t.expect.truthy(finiteVector((States.getup(12, 1).rootOffset :: Vector3)), "getup")
		MotionPlayer.sample(Config, { pos = Vector3.zero, facing = Vector3.xAxis, state = "Idle", move = nil, moveFrame = 0, walkPhase = 0, stun = 0, crouched = false, moveX = 0, characterId = "Kael", crush = "High", armorActive = true }, { now = 0, hitstop = 0 }, 1)
	end)

	t.test("lastHit drives distinct nil-safe reactions", function()
		MotionPlayer.reset()
		local high = MotionPlayer.sample(Config, { pos = Vector3.zero, facing = Vector3.xAxis, state = "Hitstun", move = nil, moveFrame = 0, walkPhase = 0, stun = 18, crouched = false, moveX = 0, characterId = "Kael", lastHit = { kind = "Hit", height = "High", tier = "Light", counter = false, frame = 120, move = "Jab", limb = "LeadArm", side = -1 } }, { now = 0, hitstop = 0 }, 1)
		MotionPlayer.reset()
		local mid = MotionPlayer.sample(Config, { pos = Vector3.zero, facing = Vector3.xAxis, state = "Hitstun", move = nil, moveFrame = 0, walkPhase = 0, stun = 18, crouched = false, moveX = 0, characterId = "Kael", lastHit = { kind = "Counter", height = "Mid", tier = "Heavy", counter = true, frame = 121, move = "Overhand", limb = "RearArm", side = 1 } }, { now = 0, hitstop = 0 }, 1)
		MotionPlayer.reset()
		local low = MotionPlayer.sample(Config, { pos = Vector3.zero, facing = Vector3.xAxis, state = "Hitstun", move = nil, moveFrame = 0, walkPhase = 0, stun = 18, crouched = false, moveX = 0, characterId = "Kael", lastHit = { kind = "Hit", height = "Low", tier = "Medium", counter = false, frame = 122, move = "ShinKick", limb = "LeadLeg", side = -1 } }, { now = 0, hitstop = 0 }, 1)
		MotionPlayer.reset()
		local fallback = MotionPlayer.sample(Config, { pos = Vector3.zero, facing = Vector3.xAxis, state = "Hitstun", move = nil, moveFrame = 0, walkPhase = 0, stun = 18, crouched = false, moveX = 0, characterId = "Kael" }, { now = 0, hitstop = 0 }, 1)
		t.expect.truthy(math.abs(high.neck.X - mid.neck.X) > 0.15, "high snaps head differently than counter mid")
		t.expect.truthy((low.targets.LeftFoot.pos - high.targets.LeftFoot.pos).Magnitude > 0.1, "low reaction knocks the lead leg")
		t.expect.truthy(finiteVector(fallback.rootOffset), "nil lastHit remains finite")
	end)

	t.test("air launch juggle landing getup and ko consume optional fields", function()
		-- Each state is sampled fresh: consecutive samples without elapsed time would sit at the start of a crossfade.
		MotionPlayer.reset()
		local launch = MotionPlayer.sample(Config, { pos = Vector3.new(0, 2, 0), facing = Vector3.xAxis, state = "Airborne", move = nil, moveFrame = 0, walkPhase = 0, stun = 0, crouched = false, moveX = 0, characterId = "Lumi", velocityY = 18, airFrames = 9, airHits = 2, lastHit = { kind = "Hit", height = "Mid", tier = "Launch", counter = true, frame = 20, move = "Uppercut", limb = "RearArm", side = 1 } }, { now = 0, hitstop = 0 }, 1)
		MotionPlayer.reset()
		local falling = MotionPlayer.sample(Config, { pos = Vector3.new(0, 1, 0), facing = Vector3.xAxis, state = "Airborne", move = nil, moveFrame = 0, walkPhase = 0, stun = 0, crouched = false, moveX = 0, characterId = "Lumi", velocityY = -12, airFrames = 40, airHits = 2 }, { now = 0, hitstop = 0 }, 1)
		MotionPlayer.reset()
		local landing = MotionPlayer.sample(Config, { pos = Vector3.zero, facing = Vector3.xAxis, state = "Landing", move = nil, moveFrame = 8, walkPhase = 0, stun = math.max(1, math.floor((Config.LandingFrames or 26) * 0.35 + 0.5)), crouched = false, moveX = 0, characterId = "Lumi", knockdown = "FaceDown" }, { now = 0, hitstop = 0 }, 1)
		MotionPlayer.reset()
		local getup = MotionPlayer.sample(Config, { pos = Vector3.zero, facing = Vector3.xAxis, state = "Getup", move = nil, moveFrame = 18, walkPhase = 0, stun = 4, crouched = false, moveX = 0, characterId = "Lumi", knockdown = "FaceDown" }, { now = 0, hitstop = 0 }, 1)
		MotionPlayer.reset()
		local ko
		for i = 0, 40 do
			ko = MotionPlayer.sample(Config, { pos = Vector3.zero, facing = Vector3.xAxis, state = "KO", move = nil, moveFrame = 60, walkPhase = 0, stun = 0, crouched = false, moveX = 0, characterId = "Lumi", knockdown = "FaceUp" }, { now = i * 0.05, dt = 0.05, hitstop = 0 }, 1)
		end
		t.expect.truthy(launch.ground == 0 and falling.ground == 0, "juggled bodies are never pulled onto the floor")
		t.expect.truthy(falling.rootRotation.X > launch.rootRotation.X + 0.3, "a juggled body tips onto its back as it falls")
		t.expect.truthy(landing.rootOffset.Y < -0.25, "landing hits floor")
		t.expect.truthy(getup.rootOffset.Y > landing.rootOffset.Y, "getup rises")
		t.expect.truthy(ko.rootOffset.Y < -0.6, "ko lies down")
		t.expect.truthy((landing.ground or 0) > 0.5 and (ko.ground or 0) > 0.5, "lying states ask the ground solver to rest the body on the floor")
	end)

	t.test("move anim overrides merge without editing roster", function()
		MotionPlayer.clearCache()
		local resolved = MotionPlayer.resolveMove("Goran", "Bulldozer", Roster.get("Goran").stats.height * 0.5)
		t.expect.equal(resolved.params.lunge, 2.25)
		t.expect.equal(Roster.getMove("Goran", "Bulldozer").anim.lunge, 2.0)
	end)

	t.test("ik solver clamps unreachable targets and follows pole", function()
		local mid, endPos, clamped = MotionPlayer.solveTwoBone(Vector3.zero, Vector3.new(10, 0, 0), 2, 1, Vector3.yAxis)
		t.expect.truthy(clamped, "solver reports clamping")
		t.expect.near(endPos.Magnitude, 2.997, 0.002)
		t.expect.near((mid - Vector3.zero).Magnitude, 2, 0.002)
		local midUp = MotionPlayer.solveTwoBone(Vector3.zero, Vector3.new(2, 0, 0), 1.5, 1.5, Vector3.yAxis)
		local midDown = MotionPlayer.solveTwoBone(Vector3.zero, Vector3.new(2, 0, 0), 1.5, 1.5, -Vector3.yAxis)
		t.expect.truthy(midUp.Y > 0.5, "positive pole")
		t.expect.truthy(midDown.Y < -0.5, "negative pole")
	end)

	t.test("presenter clones every roster template and applies finite transforms", function()
		for _, id in Roster.order do
			local source = Lab.Characters:FindFirstChild(id)
			t.expect.truthy(source and source:IsA("Model"), id .. " template exists")
			local clone = (source :: Model):Clone()
			local rig = MotionPlayer.collectRig(clone)
			local firstMove = Roster.get(id).moveOrder[1]
			local pose = MotionPlayer.sample(Config, view(id, firstMove, activeFrame(id, firstMove), "Active"), { now = 0, hitstop = 0 }, 1)
			MotionPlayer.apply(rig, pose)
			for jointName, motor in rig.motors do t.expect.truthy(finiteCFrame(motor.Transform), id .. " " .. jointName .. " transform finite") end
			clone:Destroy()
		end
	end)

	t.test("posePreview poses viewport clones without moving roots or local fighters", function()
		local source = Lab.Characters:FindFirstChild("Nia")
		t.expect.truthy(source and source:IsA("Model"), "Nia template exists")
		local clone = (source :: Model):Clone()
		local root = clone:FindFirstChild("HumanoidRootPart") :: BasePart
		local originalRoot = root.CFrame
		local beforeFolder = workspace:FindFirstChild("FightingLabLocalRender")
		for _, poseName in { "Stance", "Intro", "Victory", "Defeat", "Guard" } do
			CharacterPresenter.posePreview(clone, "Nia", poseName :: any, 0.75)
			for jointName, motor in MotionPlayer.collectRig(clone).motors do
				t.expect.truthy(finiteCFrame(motor.Transform), "posePreview " .. poseName .. " " .. jointName .. " transform finite")
			end
			t.expect.equal(root.CFrame, originalRoot, "posePreview does not move the clone root")
		end
		t.expect.equal(workspace:FindFirstChild("FightingLabLocalRender"), beforeFolder, "posePreview does not create or replace world fighters")
		t.expect.throws(function() CharacterPresenter.posePreview(clone, "Missing", "Stance" :: any, 0) end, "invalid character id errors")
		t.expect.throws(function() CharacterPresenter.posePreview(clone, "Nia", "Pose" :: any, 0) end, "invalid pose errors")
		clone:Destroy()
	end)
	t.test("hitstop holds the struck frame: the animation clock stops and the contact pose stays on screen", function()
		MotionPlayer.reset(1)
		local f = activeFrame("Kael", "Jab")
		MotionPlayer.sample(Config, view("Kael", "Jab", f - 1, "Startup"), { now = 0.1, dt = 1 / 60, hitstop = 0 }, 1)
		local contact = MotionPlayer.sample(Config, view("Kael", "Jab", f, "Active"), { now = 0.1 + 1 / 60, dt = 1 / 60, hitstop = 0 }, 1)
		-- The sim holds the struck frame through the freeze (the hitstop counts down).
		local held = MotionPlayer.sample(Config, view("Kael", "Jab", f, "Active"), { now = 0.1 + 2 / 60, dt = 1 / 60, hitstop = 4 }, 1)
		local held2 = MotionPlayer.sample(Config, view("Kael", "Jab", f, "Active"), { now = 0.1 + 3 / 60, dt = 1 / 60, hitstop = 3 }, 1)
		t.expect.equal(held.clock, contact.clock, "the animation clock stops in hitstop")
		t.expect.equal(held2.clock, contact.clock, "and stays stopped")
		for _, limb in { "LeftHand", "RightHand", "LeftFoot", "RightFoot" } do
			local d = (target(held2, limb).pos - target(contact, limb).pos).Magnitude
			t.expect.truthy(d < 1e-3, string.format("%s shows the contact frame through the freeze (%.4f studs off)", limb, d))
		end
	end)

	t.test("idle sampling stays finite and within the performance budget", function()
		local start = os.clock()
		local count = 0
		local flight = { Kael = 0, Goran = 0 }
		for i = 1, 240 do
			for slot, id in { "Kael", "Goran" } do
				local pose = MotionPlayer.sample(Config, view(id, nil, 0, "Idle"), { now = i / 60, hitstop = 0 }, slot)
				-- Mocap stances: a boxer's bounce briefly lifts both feet (a real hop); a grappler stays planted.
				if math.min(pose.plantedFeet.LeftFoot, pose.plantedFeet.RightFoot) > 0.75 then flight[id] += 1 end
				count += 1
			end
		end
		local ms = (os.clock() - start) * 1000 / count
		t.expect.truthy(flight.Kael / 240 <= 0.45, string.format("Kael bounce keeps a foot down most of the time (%.0f%% flight)", flight.Kael / 2.4))
		t.expect.truthy(flight.Goran / 240 <= 0.05, string.format("Goran stands on his feet (%.0f%% flight)", flight.Goran / 2.4))
		t.expect.truthy(ms <= 1.5, string.format("%.3f ms/frame", ms))
	end)

	t.test("presenter rejects malformed character templates", function()
		local bad = Instance.new("Model")
		bad.Name = "BadMotionTemplate"
		bad.Parent = Lab.Characters
		t.expect.throws(function() CharacterPresenter.setCharacters("BadMotionTemplate", "Kael") end, "bad template rejected")
		bad:Destroy()
	end)

	t.test("round end: victory and defeat start from the fighter's stance without pops; the next round cuts cleanly", function()
		-- Per-frame motion (heading space, studs) of the pelvis and feet (pops show there first) and of the hands.
		local function delta(a: any, b: any): (number, number)
			local body = (a.rootOffset - b.rootOffset).Magnitude
			local hands = 0
			for limb, e in a.targets do
				local o = b.targets[limb]
				if o then
					local d = (e.pos - o.pos).Magnitude
					if limb == "LeftFoot" or limb == "RightFoot" then body = math.max(body, d) else hands = math.max(hands, d) end
				end
			end
			return body, hands
		end
		local report = {}
		for _, id in Roster.order do
			for _, role in { "Victory", "Defeat" } do
				-- States compares frame.winner with the slot: slot 1 wins, slot 2 loses (a time-out loss, standing).
				local slot = if role == "Victory" then 1 else 2
				local winner = 1
				MotionPlayer.reset(slot)
				local v = view(id, nil, 0, "Idle")
				v.guard = "Stand"
				local now = 0
				local prev = nil
				for _ = 1, 40 do
					now += 1 / 60
					prev = MotionPlayer.sample(Config, v, { now = now, dt = 1 / 60, hitstop = 0, phase = "Fight", winner = 0 }, slot)
				end
				-- Round over: the fighter stands in its idle; skip the final-hit hold, then play the round-end clip.
				now += 1 / 60
				prev = MotionPlayer.sample(Config, v, { now = now, dt = 1 / 60, hitstop = 0, phase = "RoundOver", winner = winner }, slot)
				MotionPlayer._slotState(slot).roundOverSince = os.clock() - 10
				local worst, worstAt, worstHands = 0, 0, 0
				for f = 1, 150 do
					now += 1 / 60
					local pose = MotionPlayer.sample(Config, v, { now = now, dt = 1 / 60, hitstop = 0, phase = "RoundOver", winner = winner }, slot)
					local body, hands = delta(pose, prev)
					if body > worst then worst, worstAt = body, f end
					worstHands = math.max(worstHands, hands)
					prev = pose
				end
				t.expect.equal(MotionPlayer._slotState(slot).key, role, id .. " plays " .. role)
				-- Pelvis/feet 0.2 studs per frame = 12 studs/s (a stepping foot moves ~5); hands 0.45 (fast fist pumps ~20 studs/s).
				t.expect.truthy(worst < 0.2, string.format("%s %s pelvis/feet pop %.3f studs at frame %d", id, role, worst, worstAt))
				t.expect.truthy(worstHands < 0.45, string.format("%s %s hands pop %.3f studs", id, role, worstHands))
				table.insert(report, string.format("%s %s %.3f/%.3f", id, role, worst, worstHands))
			end
		end
		print("[MotionPlayer] round-end max motion per frame (pelvis+feet / hands, studs): " .. table.concat(report, " | "))
		-- Next round: the KO'd loser is back on its mark and stands in the intro pose at once (no morph from lying).
		MotionPlayer.reset(70)
		local loser = view("Goran", nil, 0, "KO")
		loser.knockdown = "FaceUp"
		local now = 0
		for _ = 1, 60 do
			now += 1 / 60
			MotionPlayer.sample(Config, loser, { now = now, dt = 1 / 60, hitstop = 0, phase = "RoundOver", winner = 1 }, 70)
		end
		local fresh = view("Goran", nil, 0, "Idle")
		fresh.pos = Vector3.new(6, 0, 0)
		now += 1 / 60
		local first = MotionPlayer.sample(Config, fresh, { now = now, dt = 1 / 60, hitstop = 0, phase = "Ready", winner = 0 }, 70)
		t.expect.equal(MotionPlayer._slotState(70).key, "Intro", "next round plays the intro")
		t.expect.truthy(MotionPlayer._slotState(70).fadeFrom == nil, "no crossfade out of the KO body")
		MotionPlayer.reset(71)
		local clean = MotionPlayer.sample(Config, fresh, { now = 0, dt = 1 / 60, hitstop = 0, phase = "Ready", winner = 0 }, 71)
		local cutBody, cutHands = delta(first, clean)
		t.expect.truthy(cutBody < 1e-3 and cutHands < 1e-3, "first intro frame = the intro pose itself")
	end)

	t.test("side roll: a log roll that turns toward its travel (full turn face up, half turn face down)", function()
		if not ClipLibrary.get("SideRoll") then return end
		local L, G, R = Config.LandingFrames or 34, Config.GetupFrames or 26, Config.RollFrames or 10
		-- Chest direction in heading space (lying body: rootRot's look vector); rollDir +1 travels to the fighter's left (-X).
		-- The getup crossfades in over up to GetupCrossfadeMax (0.1 s), so the turn is judged on the roll's third frame.
		local function chest(pose: any): Vector3 return (pose.rootRot or CFrame.identity).LookVector end
		for _, face in { "FaceUp", "FaceDown" } do
			for _, dir in { 1, -1 } do
				MotionPlayer.reset(72)
				local towardMax, towardMin, firstChestY = -2, 2, nil
				local towardAtTurn = nil
				for f = 1, L + R do
					local v = view("Kael", nil, 0, if f <= L then "Landing" else "Getup")
					v.knockdown = face
					v.getupKind = if f > 8 then "SideRoll" else nil
					v.rollDir = dir
					v.stun = if f <= L then L - f else L + G + R - f
					local pose = MotionPlayer.sample(Config, v, { now = f / 60, dt = 1 / 60, hitstop = 0, phase = "Fight", winner = 0 }, 72)
					if f > L then
						local c = chest(pose)
						local toward = -c.X * dir
						if not firstChestY then firstChestY = c.Y end
						if f <= L + 8 then towardMax = math.max(towardMax, toward); towardMin = math.min(towardMin, toward) end
						if f == L + 3 then towardAtTurn = toward end
					end
				end
				local tag = string.format("%s rollDir %+d", face, dir)
				if face == "FaceUp" then
					t.expect.truthy(firstChestY > 0.5, tag .. " starts on its back")
					t.expect.truthy((towardAtTurn or -1) > 0.6, string.format("%s: the chest turns toward the travel side first (%.2f)", tag, towardAtTurn or -1))
					t.expect.truthy(towardMax > 0.85, string.format("%s: quarter turn reached (%.2f)", tag, towardMax))
				else
					t.expect.truthy(firstChestY < -0.5, string.format("%s starts on its belly (%.2f)", tag, firstChestY))
					t.expect.truthy(towardMax < 0.35 and towardMin < -0.85, string.format("%s: the back leads the roll (toward %.2f..%.2f)", tag, towardMin, towardMax))
				end
			end
		end
		MotionPlayer.reset(72)
	end)

	-- Round 4 (real play): the renderers interpolate the sim position (practice between two sim frames, server duels
	-- between two snapshots), so a hit push and a round reset reach MotionPlayer over two render frames. Shown position =
	-- view position + the pose's root offset (heading space: +Z forward, +X right).
	local function shownX(v: any, pose: any): number
		local facing = v.facing.Unit
		local right = facing:Cross(Vector3.yAxis)
		return v.pos.X + right.X * pose.rootOffset.X + facing.X * pose.rootOffset.Z
	end

	t.test("a hit push that arrives over two render frames glides instead of jumping on the second one", function()
		MotionPlayer.reset(73)
		local v = view("Kael", nil, 0, "Idle")
		v.guard = "Stand"
		local now, prevX = 0, nil
		local worst = 0
		for f = 1, 50 do
			now += 1 / 60
			if f >= 20 then
				v.state = "Blockstun"
				v.stun = 12
				v.lastHit = { kind = "Block", height = "Mid", tier = "Medium", counter = false, frame = 20, move = "Jab", limb = "LeadArm", side = 1 }
			end
			-- the sim pushes 0.6 studs on frame 20; the renderer shows half of it on frame 20, the rest on frame 21
			if f == 20 then v.pos = Vector3.new(-0.3, 0, 0) elseif f >= 21 then v.pos = Vector3.new(-0.6, 0, 0) end
			local pose = MotionPlayer.sample(Config, v, { now = now, dt = 1 / 60, hitstop = 0, phase = "Fight", winner = 0 }, 73)
			local x = shownX(v, pose)
			if prevX and f >= 18 then worst = math.max(worst, math.abs(x - prevX)) end
			prevX = x
		end
		MotionPlayer.reset(73)
		-- The glide itself peaks at ~0.13 studs/frame for a 0.6-stud push (the whole push used to land in 0.34 + 0.3).
		t.expect.truthy(worst < 0.16, string.format("the pushed body moved %.3f studs in one frame (glide expected)", worst))
	end)

	t.test("a round reset the renderer interpolates shows no in-between frame (the intro starts on the new mark)", function()
		-- Slot 2 (the presenter's slots are 1 and 2; the newest entry's fighters are indexed by slot).
		MotionPlayer.reset(2)
		local v = view("Goran", nil, 0, "KO")
		v.knockdown = "FaceUp"
		v.pos = Vector3.new(-4, 0, 0)
		local entry = { fighters = { { pos = Vector3.new(4, 0, 0) }, { pos = v.pos } } }
		local now = 0
		for _ = 1, 40 do
			now += 1 / 60
			MotionPlayer.sample(Config, v, { now = now, dt = 1 / 60, hitstop = 0, phase = "RoundOver", winner = 1, entry = entry }, 2)
		end
		-- New round: the newest sim entry is on the new mark (7.1 studs away); the render interpolation shows the view at an
		-- in-between spot on the first frame (below TeleportDistance) and on the mark from the next frame on.
		local mark = Vector3.new(3.1, 0, 0)
		local fresh = view("Goran", nil, 0, "Idle")
		local newEntry = { fighters = { { pos = Vector3.new(-3.1, 0, 0) }, { pos = mark } } }
		local shown = {}
		for f = 1, 4 do
			now += 1 / 60
			fresh.pos = if f == 1 then Vector3.new(-4, 0, 0):Lerp(mark, 0.4) else mark
			local pose = MotionPlayer.sample(Config, fresh, { now = now, dt = 1 / 60, hitstop = 0, phase = "Ready", winner = 0, entry = newEntry }, 2)
			shown[f] = shownX(fresh, pose)
		end
		MotionPlayer.reset(2)
		t.expect.truthy(math.abs(shown[1] - mark.X) < 0.6, string.format("first intro frame shown at %.2f, the new mark is %.2f", shown[1], mark.X))
		t.expect.truthy(math.abs(shown[2] - shown[1]) < 0.6, string.format("the body jumped %.2f studs on the frame after the reset", math.abs(shown[2] - shown[1])))
	end)

	t.test("ducking during a blockstun crossfades to the crouching clip on the same stun clock", function()
		MotionPlayer.reset(75)
		local v = view("Kael", nil, 0, "Idle")
		v.guard = "Stand"
		local now = 0
		local prevY, worst, keys = nil, 0, {}
		for f = 1, 40 do
			now += 1 / 60
			if f >= 10 then
				v.state = "Blockstun"
				v.stun = 20
				v.lastHit = { kind = "Block", height = "Mid", tier = "Medium", counter = false, frame = 10, move = "Jab", limb = "LeadArm", side = 1 }
			end
			if f >= 18 then v.crouched = true; v.guard = "Crouch" end
			local pose = MotionPlayer.sample(Config, v, { now = now, dt = 1 / 60, hitstop = 0, phase = "Fight", winner = 0 }, 75)
			keys[f] = MotionPlayer._slotState(75).key
			local y = pose.rootOffset.Y
			if prevY and f >= 16 and f <= 30 then worst = math.max(worst, math.abs(y - prevY)) end
			prevY = y
		end
		MotionPlayer.reset(75)
		t.expect.truthy(keys[17] ~= keys[18], "ducking changes the blockstun request")
		t.expect.truthy(worst < 0.25, string.format("the pelvis dropped %.3f studs in one frame when ducking in blockstun", worst))
	end)
end
