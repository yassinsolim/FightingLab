--!strict
-- Mocap clip runtime: FLClip1 decoding, move binding precedence, contact-frame time warp, FLThrow1 two-role throws,
-- mirroring, credits metadata and installed Core clips.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lab = ReplicatedStorage.FightingLab
local Config = require(Lab.CombatConfig)
local Roster = require(Lab.Roster)
local MotionPlayer = require(Lab.Client.MotionPlayer)
local Library = require(Lab.Client.MotionLibrary)
local ClipLibrary = require(Lab.Client.Motion.ClipLibrary)
local ClipPlayer = require(Lab.Client.Motion.ClipPlayer)

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function enc(c: number, v: number): string
	local lo, hi = ClipLibrary.channelRange(c)
	local q = math.clamp(math.floor((v - lo) / (hi - lo) * 4095 + 0.5), 0, 4095)
	local a, b = q // 64, q % 64
	return string.sub(ALPHABET, a + 1, a + 1) .. string.sub(ALPHABET, b + 1, b + 1)
end

-- A small 3-frame clip: neutral body, left hand moving from the chin (frame 1) to full extension (frame 2) and back.
-- `constants` overrides constant channels by 1-based channel index (e.g. the root quaternion 4..7 for a lean).
local function rawClip(extra: { [string]: any }?, constants: { [number]: number }?): { [string]: any }
	local values = table.create(58, 0)
	values[7] = 1; values[11] = 1; values[15] = 1 -- identity quaternions (w)
	for _, base in { 16, 26, 36, 46 } do values[base + 9] = 1 end
	values[19] = -1 -- hand poles down
	values[29] = -1
	values[36 + 1] = -0.95; values[46 + 1] = -0.95 -- feet under the hips
	values[39] = 1; values[49] = 1 -- knee poles forward (+Z pole means backward in clip space; fine for tests)
	values[56] = 1; values[57] = 1
	if constants then for c, v in constants do values[c] = v end end
	local layout = {}
	local data = {}
	for c = 1, 58 do
		if c == 18 then
			table.insert(layout, "v")
			table.insert(data, enc(c, -0.3) .. enc(c, -0.95) .. enc(c, -0.3)) -- left hand z: forward extension at frame 2
		else
			table.insert(layout, "c")
			table.insert(data, enc(c, values[c]))
		end
	end
	local raw: { [string]: any } = { format = "FLClip1", name = "Test", fps = 30, frames = 3, loop = false, speed = 0, travel = { 0, 0, 0 }, contact = 0.5, sources = { "test-source" }, layout = table.concat(layout), data = table.concat(data) }
	if extra then for k, v in extra do raw[k] = v end end
	return raw
end

local function view(characterId: string, move: string?, moveFrame: number, extra: { [string]: any }?): any
	local v: { [string]: any } = { pos = Vector3.zero, facing = Vector3.xAxis, state = if move then "Active" else "Idle", move = move, moveFrame = moveFrame, walkPhase = 0, stun = 0, crouched = false, moveX = 0, characterId = characterId, rootHeight = 3.7, legLength = 2.85 }
	if extra then for k, x in extra do v[k] = x end end
	return v
end

return function(t)
	t.test("FLClip1 decodes to finite channels with unit quaternions", function()
		local clip = ClipLibrary.decode(rawClip(), "Test")
		t.expect.equal(clip.frames, 3)
		t.expect.near(clip.duration, 2 / 30, 1e-6)
		t.expect.equal(#clip.channels, 58)
		local pose = ClipPlayer.sample(clip, 1 / 30, { legLength = 2.85, scale = 1.2 })
		t.expect.truthy(pose.space == "heading", "clip poses are heading space")
		t.expect.truthy(pose.targets.LeftHand.pos.Z > 1.0, "left hand extended forward at the middle frame")
		t.expect.near(pose.rootRot.LookVector.Z, -1, 1e-3, "identity root")
		t.expect.throws(function() ClipLibrary.decode({ format = "FLClip1", fps = 30, frames = 3, layout = "c", data = "AA" }, "Bad") end, "malformed clip errors")
	end)

	t.test("contact warp lands the clip contact exactly on the first active frame and recovery ends at total", function()
		local clip = ClipLibrary.decode(rawClip({ contact = 0.4, recover = 0.7 }), "Warp")
		local timing = { startup = 9, active = 2, recovery = 12 }
		t.expect.near(ClipPlayer.moveTime(clip, timing, 10), 0.4 * clip.duration, 1e-9, "first active frame = contact")
		t.expect.near(ClipPlayer.moveTime(clip, timing, 9 + 2 + 1), 0.7 * clip.duration, 1e-9, "recover mark after the active window")
		t.expect.near(ClipPlayer.moveTime(clip, timing, 23), clip.duration, 1e-9, "last frame = clip end")
		local last = -1
		for f = 0, 23 do
			local x = ClipPlayer.moveTime(clip, timing, f)
			t.expect.truthy(x >= last, "monotonic at frame " .. f)
			last = x
		end
	end)

	t.test("move clips bind by fighter, string index and generic fallback", function()
		-- Precedence is checked on a move key no shipped clip binds, so installed Moves.* clips cannot interfere.
		local PROBE = "UT_BindProbe"
		ClipLibrary.register("UT_Generic_Probe", rawClip({ fighter = "*", move = PROBE }))
		ClipLibrary.register("UT_Kael_Probe", rawClip({ fighter = "KAEL", move = PROBE }))
		ClipLibrary.register("UT_Kael_Probe_S2", rawClip({ fighter = "kael", move = PROBE, stringIndex = 2 }))
		local ok, err = pcall(function()
			t.expect.equal((ClipLibrary.forMove("Kael", PROBE) :: any).name, "UT_Kael_Probe", "fighter-specific beats generic")
			t.expect.equal((ClipLibrary.forMove("Kael", PROBE, 2) :: any).name, "UT_Kael_Probe_S2", "string index preferred")
			t.expect.equal((ClipLibrary.forMove("Sierra", PROBE) :: any).name, "UT_Generic_Probe", "generic for other fighters")
			t.expect.equal(ClipLibrary.forMove("Kael", "NoSuchMove"), nil, "unbound move -> procedural fallback")
			-- A clip bound to a real move drives the pose at the first active frame (it shadows any shipped clip).
			MotionPlayer.clearCache()
			ClipLibrary.register("UT_Kael_Jab", rawClip({ fighter = "Kael", move = "Jab", contact = 0.5 }))
			MotionPlayer.reset(30)
			local first = Roster.getMove("Kael", "Jab").startup + 1
			local pose = MotionPlayer.sample(Config, view("Kael", "Jab", first), { now = 0, hitstop = 0 }, 30)
			t.expect.truthy(pose.targets.LeftHand.pos.Z > 1.0, "clip contact pose at the first active frame")
		end)
		for _, n in { "UT_Generic_Probe", "UT_Kael_Probe", "UT_Kael_Probe_S2", "UT_Kael_Jab" } do ClipLibrary.unregister(n) end
		MotionPlayer.clearCache()
		if not ok then error(err, 0) end
	end)

	t.test("unregistering a test clip gives the binding back to the clip it shadowed", function()
		local PROBE = "UT_ShadowProbe"
		ClipLibrary.register("UT_Shadow_Shipped", rawClip({ fighter = "Nia", move = PROBE }))
		ClipLibrary.register("UT_Shadow_Test", rawClip({ fighter = "Nia", move = PROBE }))
		local ok, err = pcall(function()
			t.expect.equal((ClipLibrary.forMove("Nia", PROBE) :: any).name, "UT_Shadow_Test", "newest registration wins")
			ClipLibrary.unregister("UT_Shadow_Test")
			local back = ClipLibrary.forMove("Nia", PROBE)
			t.expect.equal(back and (back :: any).name, "UT_Shadow_Shipped", "shadowed clip is bound again")
		end)
		ClipLibrary.unregister("UT_Shadow_Test")
		ClipLibrary.unregister("UT_Shadow_Shipped")
		if not ok then error(err, 0) end
		t.expect.equal(ClipLibrary.forMove("Nia", PROBE), nil, "nothing left bound")
	end)

	t.test("contact aim reaches the opponent's height, not the attacker's", function()
		local ok, err = pcall(function()
			MotionPlayer.clearCache()
			ClipLibrary.register("UT_Kael_Jab", rawClip({ fighter = "Kael", move = "Jab", contact = 0.5, tags = { limb = "LeftHand" } }))
			t.expect.equal((ClipLibrary.forMove("Kael", "Jab") :: any).name, "UT_Kael_Jab", "test clip bound")
			local move = Roster.getMove("Kael", "Jab")
			local first = move.startup + 1
			local function handY(opponentRootHeight: number?): number
				MotionPlayer.reset(30)
				local me = view("Kael", "Jab", first)
				local frame: { [string]: any } = { now = 0, hitstop = 0 }
				if opponentRootHeight then
					-- Slot 30 reads fighters[1] as its opponent.
					frame.fighters = { view("Lumi", nil, 0, { rootHeight = opponentRootHeight, pos = Vector3.new(3, 0, 0), facing = -Vector3.xAxis }), me }
				end
				return MotionPlayer.sample(Config, me, frame, 30).targets.LeftHand.pos.Y
			end
			local alone, same, taller, shorter = handY(nil), handY(3.7), handY(4.2), handY(3.4)
			t.expect.near(same, alone, 1e-6, "same-size opponent = own contact height")
			local function expected(rh: number): number
				return Library.contactY(move.height, MotionPlayer.scaleFromRoot(rh)) - Library.contactY(move.height, MotionPlayer.scaleFromRoot(3.7)) + (rh - 3.7)
			end
			t.expect.near(taller - same, expected(4.2), 1e-3, "taller opponent raises the aimed hand by the height difference")
			t.expect.near(shorter - same, expected(3.4), 1e-3, "shorter opponent lowers it")
			t.expect.truthy(taller > same and shorter < same, "aim follows the opponent")
		end)
		ClipLibrary.unregister("UT_Kael_Jab")
		MotionPlayer.clearCache()
		if not ok then error(err, 0) end
	end)

	t.test("contact aim lands at the same height whether the striker leans or stands upright", function()
		local clone = (Lab.Characters:FindFirstChild("Kael") :: Model):Clone()
		for _, d in clone:GetDescendants() do
			if d:IsA("BasePart") then d.Anchored = d.Name == "HumanoidRootPart"; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false end
		end
		clone.Parent = workspace
		local rig = MotionPlayer.collectRig(clone)
		local root = clone:FindFirstChild("HumanoidRootPart") :: BasePart
		local ok, err = pcall(function()
			local move = Roster.getMove("Kael", "LiverHook")
			t.expect.equal(move.height, "Mid", "probe move is a mid")
			local first = move.startup + 1
			local function handY(constants: { [number]: number }?): number
				MotionPlayer.clearCache()
				ClipLibrary.register("UT_Kael_Lean", rawClip({ fighter = "Kael", move = "LiverHook", contact = 0.5, tags = { limb = "LeftHand" } }, constants))
				MotionPlayer.reset(30)
				local me = view("Kael", "LiverHook", first, { rootHeight = rig.rootHeight, legLength = rig.legLength })
				local pose = MotionPlayer.sample(Config, me, { now = 0, hitstop = 0 }, 30)
				local y = 200 + rig.rootHeight + pose.rootOffset.Y
				root.CFrame = CFrame.lookAt(Vector3.new(0, y, 500), Vector3.new(1, y, 500))
				MotionPlayer.apply(rig, pose, 200)
				return rig.tips.LeftHand.Position.Y
			end
			local upright = handY(nil)
			-- Root pitched 40 degrees forward and the chest bent another 25 (x+ leans back): the shoulder drops ~0.6 studs.
			local leaning = handY({ [4] = math.sin(math.rad(-20)), [7] = math.cos(math.rad(-20)), [8] = math.sin(math.rad(-12.5)), [11] = math.cos(math.rad(-12.5)) })
			t.expect.near(leaning, upright, 0.15, string.format("aimed hand leaning %.2f vs upright %.2f", leaning, upright))
		end)
		clone:Destroy()
		ClipLibrary.unregister("UT_Kael_Lean")
		MotionPlayer.clearCache()
		if not ok then error(err, 0) end
	end)

	t.test("measured contact aim: the striking limb reaches the opponent's measured standing height", function()
		-- 1) sample tags the aimed effector with the opponent's measured height (ramping in over the startup).
		local ok, err = pcall(function()
			MotionPlayer.clearCache()
			ClipLibrary.register("UT_Kael_Measured", rawClip({ fighter = "Kael", move = "LiverHook", contact = 0.5, tags = { limb = "LeftHand" } }))
			local move = Roster.getMove("Kael", "LiverHook")
			local heights = { High = 5.1, Mid = 4.0, Low = 1.3 }
			local function aimAt(frameNo: number): any
				MotionPlayer.reset(30)
				local me = view("Kael", "LiverHook", frameNo)
				local opp = view("Nia", nil, 0, { rootHeight = 3.9, aimHeights = heights, pos = Vector3.new(3, 0, 0), facing = -Vector3.xAxis })
				return MotionPlayer.sample(Config, me, { now = 0, hitstop = 0, fighters = { opp, me } }, 30).targets.LeftHand
			end
			local hit = aimAt(move.startup + 1)
			t.expect.near(hit.aimWorldY or -1, heights.Mid, 1e-6, "mid aims at the measured chest height")
			t.expect.near(hit.aimWeight or -1, 1, 1e-6, "full weight on the first active frame")
			local early = aimAt(math.floor(move.startup * 0.75))
			t.expect.truthy((early.aimWeight or 0) > 0 and (early.aimWeight or 1) < 1, "aim ramps in during the startup")
		end)
		ClipLibrary.unregister("UT_Kael_Measured")
		MotionPlayer.clearCache()
		if not ok then error(err, 0) end
		-- 2) apply puts the wrist at that world height through this rig's posed shoulder; 3) heights are sane.
		for _, id in Roster.order do
			local clone = (Lab.Characters:FindFirstChild(id) :: Model):Clone()
			for _, d in clone:GetDescendants() do
				if d:IsA("BasePart") then d.Anchored = d.Name == "HumanoidRootPart"; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false end
			end
			clone.Parent = workspace
			local rig = MotionPlayer.collectRig(clone)
			local root = clone:FindFirstChild("HumanoidRootPart") :: BasePart
			local ok2, err2 = pcall(function()
				root.CFrame = CFrame.lookAt(Vector3.new(0, 300, 700), Vector3.new(1, 300, 700))
				local h = MotionPlayer.standingHeights(rig, id)
				t.expect.truthy(h.High > h.Mid and h.Mid > h.Low and h.Low > 0.5, string.format("%s heights ordered (%.2f %.2f %.2f)", id, h.High, h.Mid, h.Low))
				t.expect.truthy(h.High - h.Mid > 0.5 and h.High - h.Mid < 2, string.format("%s head above chest %.2f", id, h.High - h.Mid))
				local pose = MotionPlayer.namedPose(id, "Stance", 0, rig.rootHeight, rig.legLength)
				local y = 300 + pose.rootOffset.Y
				root.CFrame = CFrame.lookAt(Vector3.new(0, y, 700), Vector3.new(1, y, 700))
				local floor = y - rig.rootHeight - pose.rootOffset.Y
				local m = rig.motors
				-- The arm IK goal is the hand (fist) centre.
				local function handY(): number
					local function through(fr: CFrame, motor: Motor6D): CFrame return fr * motor.C0 * motor.Transform * motor.C1:Inverse() end
					local upper = through(through(root.CFrame, m.Root), m.Waist)
					return through(through(through(upper, m.LeftShoulder), m.LeftElbow), m.LeftWrist).Position.Y
				end
				MotionPlayer.apply(rig, pose, floor)
				local want = handY() - floor - 0.35
				pose.targets.LeftHand.aimWorldY = want
				pose.targets.LeftHand.aimWeight = 1
				MotionPlayer.apply(rig, pose, floor)
				t.expect.near(handY() - floor, want, 0.03, id .. " fist lands on the aimed world height")
			end)
			clone:Destroy()
			if not ok2 then error(err2, 0) end
		end
	end)

	t.test("mirrored clips swap left and right", function()
		local clip = ClipLibrary.decode(rawClip(), "Mirror")
		local plain = ClipPlayer.sample(clip, 1 / 30, { legLength = 2.85, scale = 1 })
		local mirror = ClipPlayer.sample(clip, 1 / 30, { legLength = 2.85, scale = 1, mirror = true })
		t.expect.near(mirror.targets.RightHand.pos.Z, plain.targets.LeftHand.pos.Z, 1e-6, "right hand takes the left hand's path")
		t.expect.near(mirror.targets.RightHand.pos.X, -plain.targets.LeftHand.pos.X, 1e-6, "mirrored across the centre line")
	end)

	t.test("FLThrow1 drives attacker and defender roles with the impact on throw.impactFrame", function()
		local throwRaw = { format = "FLThrow1", fighter = "Goran", move = "UT_Throw", impact = 0.6, distance = 1.0, sources = { "test-source" },
			attacker = rawClip(), defender = rawClip({ contact = nil }) }
		ClipLibrary.register("UT_Goran_Throw", throwRaw)
		local ok, err = pcall(function()
			local tc = ClipLibrary.forThrow("Goran", "UT_Throw")
			t.expect.truthy(tc ~= nil and tc.attacker ~= nil and tc.defender ~= nil, "throw clip resolves with both roles")
			t.expect.near(MotionPlayer.throwTime(0.6, 32, 32, 50), 0.6, 1e-9, "impact frame -> impact time")
			t.expect.near(MotionPlayer.throwTime(0.6, 50, 32, 50), 1, 1e-9, "end of throw -> end of clip")
			local attacker = view("Goran", nil, 0, { state = "Throw", throw = { role = "Attacker", move = "UT_Throw", archetype = "slam", frame = 25, duration = 50, impactFrame = 32 } })
			local defender = view("Kael", nil, 0, { state = "Throw", pos = Vector3.new(3, 0, 0), facing = -Vector3.xAxis, throw = { role = "Defender", move = "UT_Throw", archetype = "slam", frame = 25, duration = 50, impactFrame = 32 } })
			defender.characterId = "Kael"
			attacker.characterId = "Goran"
			-- Fresh slots: a slot with an earlier pose would start the throw with a crossfade (no time passes here).
			MotionPlayer.reset(31); MotionPlayer.reset(32)
			local frame = { now = 0, hitstop = 0, fighters = { attacker, defender } }
			local pa = MotionPlayer.sample(Config, attacker, frame, 31)
			local pd = MotionPlayer.sample(Config, defender, frame, 32)
			t.expect.truthy(pa.space == "heading" and pd.space == "heading", "both roles posed from the clip")
			t.expect.truthy(math.abs(pd.rootOffset.Z - (3 - 1.0 * 2.85)) < 0.05, "defender slid to the authored distance")
		end)
		ClipLibrary.unregister("UT_Goran_Throw")
		MotionPlayer.reset()
		if not ok then error(err, 0) end
	end)

	t.test("throw grips hold the hand on the partner's real body point; the defender glides into the clinch", function()
		local GRIP = { role = "Attacker", limb = "LeftHand", anchor = "Collar", from = 0, to = 1, fade = 0.05 }
		ClipLibrary.register("UT_Kael_GripThrow", { format = "FLThrow1", fighter = "Kael", move = "UT_GripThrow", impact = 0.6, distance = 0.6,
			sources = { "test-source" }, attacker = rawClip(), defender = rawClip({ contact = nil }), grips = { GRIP } })
		local clones: { Model } = {}
		local ok, err = pcall(function()
			t.expect.throws(function()
				ClipLibrary.register("UT_Kael_BadGrip", { format = "FLThrow1", fighter = "Kael", move = "UT_BadGrip", impact = 0.6, distance = 0.8,
					sources = { "test-source" }, attacker = rawClip(), defender = rawClip({ contact = nil }),
					grips = { { role = "Attacker", limb = "LeftHand", anchor = "Nowhere", from = 0, to = 1 } } })
			end, "unknown grip anchor is a decode error")
			t.expect.truthy(ClipLibrary.forThrow("Kael", "UT_BadGrip") == nil, "a clip that fails to decode is not left registered")
			local tc = ClipLibrary.forThrow("Kael", "UT_GripThrow") :: any
			t.expect.truthy(tc.grips ~= nil and #tc.grips == 1 and tc.grips[1].part == "UpperTorso", "grip decoded from its anchor")
			local function throwView(id: string, role: string, f: number, extra: { [string]: any }?): any
				local v = view(id, nil, 0, { state = "Throw", throw = { role = role, move = "UT_GripThrow", archetype = "slam", frame = f, duration = 40, impactFrame = 20 } })
				if extra then for k, x in extra do v[k] = x end end
				return v
			end
			-- 1) Ramp: the defender's distance correction eases in over ThrowAlignFrames.
			for _, f in { 1, 2, 4, 6 } do
				local a = throwView("Kael", "Attacker", f)
				local d = throwView("Nia", "Defender", f, { pos = Vector3.new(3, 0, 0), facing = -Vector3.xAxis })
				MotionPlayer.reset(33)
				local pd = MotionPlayer.sample(Config, d, { now = 0, hitstop = 0, fighters = { a, d } }, 33)
				local x = math.clamp(f / MotionPlayer.ThrowAlignFrames, 0, 1)
				local want = (3 - 0.6 * 2.85) * x * x * (3 - 2 * x)
				t.expect.near(pd.rootOffset.Z, want, 0.02, "defender correction at throw frame " .. f)
			end
			-- 2) Grip on real rigs of different sizes: the attacker's left hand ends on the defender's collar.
			local floorY = 400
			local rigs, roots = {}, {}
			for i, id in { "Kael", "Nia" } do
				local clone = (Lab.Characters:FindFirstChild(id) :: Model):Clone()
				for _, d in clone:GetDescendants() do
					if d:IsA("BasePart") then d.Anchored = d.Name == "HumanoidRootPart"; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false end
				end
				clone.Parent = workspace
				table.insert(clones, clone)
				rigs[i] = MotionPlayer.collectRig(clone)
				roots[i] = clone:FindFirstChild("HumanoidRootPart") :: BasePart
			end
			local a = throwView("Kael", "Attacker", 10, { rootHeight = rigs[1].rootHeight, legLength = rigs[1].legLength })
			local d = throwView("Nia", "Defender", 10, { pos = Vector3.new(2, 0, 0), facing = -Vector3.xAxis, rootHeight = rigs[2].rootHeight, legLength = rigs[2].legLength })
			local frame = { now = 0, hitstop = 0, fighters = { a, d } }
			MotionPlayer.reset(34); MotionPlayer.reset(35)
			local poses = { MotionPlayer.sample(Config, a, frame, 34), MotionPlayer.sample(Config, d, frame, 35) }
			for i, v in { a, d } do
				local forward = v.facing.Unit
				local right = forward:Cross(Vector3.yAxis).Unit
				local off = poses[i].rootOffset
				local center = Vector3.new(v.pos.X, floorY + rigs[i].rootHeight, 600) + right * off.X + Vector3.yAxis * off.Y + forward * off.Z
				roots[i].CFrame = CFrame.lookAt(center, center + forward)
				MotionPlayer.apply(rigs[i], poses[i], floorY)
			end
			local function collar(): Vector3
				local cf = MotionPlayer.partWorld(rigs[2], "UpperTorso") :: CFrame
				local size = rigs[2].parts.UpperTorso.Size
				local at = (ClipLibrary.GRIP_ANCHORS :: any).Collar[2]
				return cf * Vector3.new(at.X * size.X * 0.5, at.Y * size.Y * 0.5, at.Z * size.Z * 0.5)
			end
			local before = (rigs[1].tips.LeftHand.Position - collar()).Magnitude
			t.expect.equal(MotionPlayer.applyGrips(rigs[2], poses[2], d, frame, 2, rigs[1], floorY), 0, "the defender has no grips")
			t.expect.equal(MotionPlayer.applyGrips(rigs[1], poses[1], a, frame, 1, rigs[2], floorY), 1, "one attacker grip applied")
			local after = (rigs[1].tips.LeftHand.Position - collar()).Magnitude
			t.expect.truthy(before > 0.3, string.format("authored hand starts off the collar (%.2f)", before))
			t.expect.truthy(after < 0.06, string.format("hand on the partner's collar after the grip (%.3f)", after))
			-- 3) A broken throw never grips.
			a.throw.broken = true
			t.expect.equal(MotionPlayer.applyGrips(rigs[1], poses[1], a, frame, 1, rigs[2], floorY), 0, "broken throw: no grips")
		end)
		for _, c in clones do c:Destroy() end
		ClipLibrary.unregister("UT_Kael_GripThrow")
		ClipLibrary.unregister("UT_Kael_BadGrip")
		MotionPlayer.reset()
		if not ok then error(err, 0) end
	end)

	t.test("broken throws play the break tracks (or the generic shove) from the break frame, never the rest of the throw", function()
		-- Break track: the left hand fully extended (frame 2 of rawClip) at mid-break.
		local throwRaw = { format = "FLThrow1", fighter = "Goran", move = "UT_BreakThrow", impact = 0.6, distance = 1.0, sources = { "test-source" },
			attacker = rawClip(), defender = rawClip(), breakAttacker = rawClip(), breakDefender = rawClip() }
		ClipLibrary.register("UT_Goran_BreakThrow", throwRaw)
		local ok, err = pcall(function()
			local tc = ClipLibrary.forThrow("Goran", "UT_BreakThrow")
			t.expect.truthy(tc ~= nil and tc.breakAttacker ~= nil and tc.breakDefender ~= nil, "break tracks decode")
			local total = Config.ThrowBreakFrames or 16
			local function sampleAt(role: string, move: string, frameNo: number, broken: boolean, slot: number)
				local v = view("Goran", nil, 0, { state = "Throw", throw = { role = role, move = move, archetype = "slam", frame = frameNo, duration = 50, impactFrame = 32, broken = broken, breakFrame = 10 } })
				v.characterId = "Goran"
				MotionPlayer.reset(slot)
				return MotionPlayer.sample(Config, v, { now = 0, hitstop = 0, fighters = { v, view("Kael", nil, 0, { pos = Vector3.new(3, 0, 0), facing = -Vector3.xAxis }) } }, slot)
			end
			-- Mid-break (half of ThrowBreakFrames after breakFrame = 10) shows the break track's middle frame: hand extended.
			local mid = sampleAt("Attacker", "UT_BreakThrow", 10 + math.floor(total / 2), true, 33)
			local start = sampleAt("Attacker", "UT_BreakThrow", 10, true, 34)
			t.expect.truthy(mid.targets.LeftHand.pos.Z > start.targets.LeftHand.pos.Z + 0.5, "break track time runs from breakFrame over ThrowBreakFrames")
			-- A throw without break tracks falls back to the generic Core.ThrowBreak shove (when installed), not the throw.
			local legacy = sampleAt("Defender", "Throw", 20, true, 35)
			t.expect.truthy(legacy.space == "heading" or ClipLibrary.find("ThrowBreak", nil) == nil, "generic break clip used for throws without break tracks")
			t.expect.truthy(legacy.rootOffset.Y > -1.0, "a broken throw never continues into the slam")
		end)
		ClipLibrary.unregister("UT_Goran_BreakThrow")
		MotionPlayer.reset()
		if not ok then error(err, 0) end
	end)

	t.test("installed clips decode, carry credits and stay within the source budget", function()
		local names = ClipLibrary.list()
		local bytes = 0
		for _, name in names do
			local clip = ClipLibrary.get(name)
			if clip then
				t.expect.truthy(#clip.sources > 0, name .. " lists its sources (credits)")
				local pose = ClipPlayer.sample(clip, clip.duration * 0.5, { legLength = 2.85, scale = 1.2 })
				for limb, e in pose.targets do t.expect.truthy(e.pos.Magnitude < 20, name .. " " .. limb .. " finite") end
				bytes += #(clip.channels) * clip.frames * 2
			end
		end
		t.expect.truthy(#ClipLibrary.problems() == 0, "no malformed clip modules: " .. table.concat(ClipLibrary.problems(), "; "))
		t.expect.truthy(bytes < 2.5 * 1024 * 1024, "clip data budget")
		t.expect.truthy(#ClipLibrary.sourceIds() >= (if #names > 0 then 1 else 0), "credit ids exported")
	end)

	t.test("core states use their mocap clips when installed", function()
		if not ClipLibrary.get("Stance") then return end
		MotionPlayer.reset(33)
		local pose
		for i = 1, 30 do pose = MotionPlayer.sample(Config, view("Kael", nil, 0), { now = i / 60, dt = 1 / 60, hitstop = 0 }, 33) end
		t.expect.truthy(pose.targets.LeftHand.rot ~= nil or pose.targets.LeftFoot.rot ~= nil, "stance pose comes from the clip (foot rotations)")
		MotionPlayer.reset(33)
	end)
end
