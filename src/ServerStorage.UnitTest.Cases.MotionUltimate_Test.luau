--!strict
-- motion round 6: the Ultimate's cinematic, the signature stances and the tumble extender on the client.
--   * every fighter's Ultimate plays its own FLThrow1 clip (Moves.Ultimates) on its roster timeline: the clip's impacts
--     land exactly on the roster impact frames, the start clip's catch strike on startup + 1, credits present;
--   * the defender's track ends lying in the endKind pose on its sim spot and the knockdown continues from it;
--   * the presentation time map keeps every impact on its own sim frame and catches up by the last frame;
--   * missing or malformed fields (no roster timeline, no clip, a bare throw table) never error;
--   * signature stances play their entry, loop and exit clips; a tumbling juggled body rolls over (AirTumble).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lab = ReplicatedStorage.FightingLab
local Config = require(Lab.CombatConfig)
local Roster = require(Lab.Roster)
local MotionPlayer = require(Lab.Client.MotionPlayer)
local ClipLibrary = require(Lab.Client.Motion.ClipLibrary)
local ClipPlayer = require(Lab.Client.Motion.ClipPlayer)
local Cinematic = require(Lab.Client.Motion.Cinematic)
local States = require(Lab.Client.Motion.States)

local FIGHTERS = { "Kael", "Sierra", "Goran", "Lumi", "Rhys", "Nia" }

local function finite(v: Vector3): boolean
	return v.X == v.X and v.Y == v.Y and v.Z == v.Z and math.abs(v.X) < 1e6 and math.abs(v.Y) < 1e6 and math.abs(v.Z) < 1e6
end

local function fighterView(id: string, x: number, facing: Vector3, extra: { [string]: any }?): { [string]: any }
	local v: { [string]: any } = { pos = Vector3.new(x, 0, 0), facing = facing, state = "Idle", move = nil, moveFrame = 0, walkPhase = 0, stun = 0,
		crouched = false, moveX = 0, characterId = id, rootHeight = 4.1, legLength = 3.18 }
	if extra then for k, value in extra do v[k] = value end end
	return v
end

-- Both views of an Ultimate cinematic at frame f (attacker slot 1, defender slot 2).
local function ultimateFrame(attacker: string, defender: string, f: number, throwExtra: { [string]: any }?): (any, any, any)
	local tl = Cinematic.timeline(attacker, nil)
	local function info(role: string): any
		local t: { [string]: any } = { role = role, move = "Ultimate", archetype = "ultimate", frame = f, duration = tl.duration, impactFrame = tl.frames[1] }
		if throwExtra then for k, value in throwExtra do t[k] = value end end
		return t
	end
	local a = fighterView(attacker, 0, Vector3.xAxis, { state = "Ultimate", throw = info("Attacker") })
	local d = fighterView(defender, tl.endDistance, -Vector3.xAxis, { state = "Ultimate", throw = info("Defender") })
	return a, d, { now = f / 60, hitstop = 0, fighters = { a, d } }
end

return function(t)
	t.test("every fighter's Ultimate plays its own two-role clip with the impacts on the roster frames", function()
		for _, id in FIGHTERS do
			local move = Roster.getMove(id, "Ultimate")
			t.expect.truthy(type(move.cinematic) == "table", id .. " has a roster cinematic")
			local tc = ClipLibrary.forThrow(id, "Ultimate") :: any
			t.expect.truthy(tc ~= nil, id .. " has an Ultimate clip")
			if not tc then continue end
			t.expect.equal(tc.name, id .. "_Ultimate", id .. " clip is its own")
			t.expect.truthy(#tc.sources > 0, id .. " Ultimate credits its sources")
			local tl = Cinematic.timeline(id, nil)
			t.expect.equal(tl.source, "roster", id .. " timeline comes from the roster")
			t.expect.equal(#tc.impacts, #tl.frames, id .. " clip has one impact per roster impact")
			t.expect.equal(tc.endKind, tl.endKind, id .. " clip ends in the roster endKind")
			for k, f in tl.frames do
				t.expect.near(Cinematic.clipU(tc, tl, Cinematic.displayFrame(tl, f)), tc.impacts[k], 1e-6, string.format("%s impact %d shows on sim frame %d", id, k, f))
			end
			-- The start clip (the move itself: activation, the catch strike, the whiff recovery).
			local start = ClipLibrary.forMove(id, "Ultimate") :: any
			t.expect.truthy(start ~= nil, id .. " has an Ultimate start clip")
			if start then
				local timing = { startup = move.startup, active = move.active, recovery = move.recovery }
				t.expect.near(ClipPlayer.moveTime(start, timing, move.startup + 1), start.contact * start.duration, 1e-9, id .. " start clip contact on startup + 1")
			end
		end
	end)

	t.test("the presentation time map keeps impacts on their frames and catches up by the end", function()
		for _, id in FIGHTERS do
			local tl = Cinematic.timeline(id, nil)
			t.expect.near(Cinematic.displayFrame(tl, 0), 0, 1e-9, id .. " starts on frame 0")
			t.expect.near(Cinematic.displayFrame(tl, tl.duration), tl.duration, 1e-9, id .. " ends on the last frame")
			for _, f in tl.frames do t.expect.near(Cinematic.displayFrame(tl, f), f, 1e-6, id .. " impact frame maps onto itself") end
			local prev = -1
			for f = 0, tl.duration, 0.5 do
				local d = Cinematic.displayFrame(tl, f)
				t.expect.truthy(d >= prev - 1e-9, string.format("%s display time never runs backwards (frame %.1f)", id, f))
				prev = d
			end
			t.expect.truthy(Cinematic.slowMotion(tl, tl.frames[#tl.frames]), id .. " final impact is in slow motion")
			t.expect.truthy(not Cinematic.slowMotion(tl, tl.frames[1]), id .. " first impact is not")
		end
	end)

	t.test("both roles pose finite bodies on every frame; the defender ends lying on its spot", function()
		for _, id in FIGHTERS do
			local defender = if id == "Goran" then "Nia" else "Goran"
			local tl = Cinematic.timeline(id, nil)
			MotionPlayer.reset(1); MotionPlayer.reset(2)
			local last: any = nil
			for f = 1, tl.duration, 3 do
				local a, d, frame = ultimateFrame(id, defender, f)
				local pa = MotionPlayer.sample(Config, a :: any, frame, 1)
				local pd = MotionPlayer.sample(Config, d :: any, frame, 2)
				t.expect.truthy(finite(pa.rootOffset) and finite(pd.rootOffset), string.format("%s frame %d finite", id, f))
				last = pd
			end
			local a, d, frame = ultimateFrame(id, defender, tl.duration)
			MotionPlayer.sample(Config, a :: any, frame, 1)
			last = MotionPlayer.sample(Config, d :: any, frame, 2)
			t.expect.truthy((last.ground or 0) > 0.8, string.format("%s defender lies on the floor at the end (ground %.2f)", id, last.ground or 0))
			t.expect.truthy(math.abs(last.rootOffset.Z) < 1.2 and math.abs(last.rootOffset.X) < 1.2,
				string.format("%s defender ends on its sim spot (offset %.2f, %.2f)", id, last.rootOffset.X, last.rootOffset.Z))
			-- The knockdown continues from the lying pose (Landing with the cinematic's endKind): no pop, on the floor.
			local prevY = last.rootOffset.Y
			local pl: any = last
			for k = 1, 12 do
				local landing = fighterView(defender, tl.endDistance, -Vector3.xAxis, { state = "Landing", knockdown = tl.endKind, stun = Config.LandingFrames - k })
				pl = MotionPlayer.sample(Config, landing :: any, { now = (tl.duration + k) / 60, hitstop = 0, fighters = { fighterView(id, 0, Vector3.xAxis), landing } }, 2)
				t.expect.truthy(math.abs(pl.rootOffset.Y - prevY) < 0.35, string.format("%s knockdown continues without a jump (frame %d, %.2f studs)", id, k, pl.rootOffset.Y - prevY))
				prevY = pl.rootOffset.Y
			end
			t.expect.truthy((pl.ground or 0) > 0.5, string.format("%s knockdown continues on the floor after the cinematic (ground %.2f)", id, pl.ground or 0))
			MotionPlayer.reset(1); MotionPlayer.reset(2)
		end
	end)

	t.test("a lifted or carried Ultimate defender never asks for floor support (the ground solver would pull it down)", function()
		-- Round 6 follow-up (Goran's Landslide): lifted defender keys built from a lying pose inherited its floor-support
		-- weight (ground 1), so MotionPlayer's ground solver pulled the carried body down onto the floor at the attacker's
		-- feet: the knee slam and the shoulder carry never showed, his legs passed through it and once it sank under the
		-- floor. On every frame of every Ultimate's defender track the support weight times the body's height above its
		-- own lying height (the last frame) stays small (a body getting up may still blend out of the floor support).
		local LEG, ROOT = 3.1, 4.0
		for _, id in FIGHTERS do
			local tc = ClipLibrary.forThrow(id, "Ultimate") :: any
			if not tc then continue end
			local track = tc.defender
			local opts = { mirror = track.mirror, legLength = LEG, scale = ROOT / 3 }
			local lying = ClipPlayer.sample(track, track.duration, opts).rootOffset.Y
			local worst, at, height, ground = 0, 0, 0, 0
			for f = 0, track.frames - 1 do
				local pose = ClipPlayer.sample(track, f / track.fps, opts)
				local above = pose.rootOffset.Y - lying
				local pull = (pose.ground or 0) * math.max(0, above - 0.5)
				if pull > worst then worst, at, height, ground = pull, f, above, pose.ground or 0 end
			end
			t.expect.truthy(worst <= 0.8, string.format("%s defender frame %d: floor support %.2f on a body %.2f studs above its lying height", id, at, ground, height))
		end
	end)

	t.test("in Play a fighter's root moves only with the step that shows its joints (no frame mixes two poses)", function()
		-- Round 6 follow-up (Goran's Landslide: Nia's body under the floor for one frame). The engine draws the Motor6D
		-- transforms written the frame before (it moves the parts to them after the picture) but a root part moved this
		-- frame at once, so a frame whose root jumped showed the old pose on the new root. The presenter poses on the new
		-- root, then puts it back where the shown joints belong and moves it on in PreAnimation (here: _flushRoots); a frame
		-- drawn without that step keeps showing the last whole pose.
		local CP = require(Lab.Client.CharacterPresenter)
		local gui = Instance.new("ScreenGui")
		MotionPlayer.reset(1); MotionPlayer.reset(2)
		CP._setContext({ gui = gui, config = Config, modules = {} })
		CP._forceDefer = true
		local ok, err = pcall(function()
			CP.setCharacters("Goran", "Nia")
			local root = CP.getRoot(2) :: BasePart
			local tl = Cinematic.timeline("Goran", nil)
			local function frame(f: number): any
				local _, _, fr = ultimateFrame("Goran", "Nia", f)
				fr.dt, fr.phase, fr.winner, fr.origin = 1 / 60, "Fight", 0, Vector3.zero
				return fr
			end
			CP.update(frame(1))
			CP._flushRoots()
			local shown = root.CFrame
			local biggest, skips = 0, 0
			local f = 2
			while f <= tl.duration do
				CP.update(frame(f))
				t.expect.truthy((root.Position - shown.Position).Magnitude < 1e-4, string.format("frame %d: the picture keeps the root its joints belong to", f))
				if f % 20 == 0 and f < tl.duration then
					-- No animation step between two pictures: still the last whole pose.
					f += 1
					CP.update(frame(f))
					t.expect.truthy((root.Position - shown.Position).Magnitude < 1e-4, string.format("frame %d: a picture without an animation step keeps the last pose", f))
					skips += 1
				end
				CP._flushRoots()
				biggest = math.max(biggest, (root.Position - shown.Position).Magnitude)
				shown = root.CFrame
				f += 1
			end
			t.expect.truthy(skips >= 5, "frames without an animation step were checked")
			t.expect.truthy(biggest > 0.3, string.format("the defender's root moves between frames (largest step %.2f studs)", biggest))
		end)
		CP._forceDefer = nil
		CP._resetForTests()
		gui:Destroy()
		if not ok then error(err, 0) end
	end)

	t.test("missing or malformed cinematic data never errors", function()
		local tl = Cinematic.timeline("Nobody", nil)
		t.expect.equal(tl.source, "default", "an unknown attacker uses the contract template")
		t.expect.equal(#tl.frames, #Cinematic.DEFAULT.impacts, "template impacts")
		local scaled = Cinematic.timeline("Kael", { duration = 120 })
		t.expect.equal(scaled.duration, 120, "a sim duration that differs rescales the timeline")
		t.expect.truthy(scaled.frames[#scaled.frames] <= 120, "rescaled impacts stay inside the cinematic")
		MotionPlayer.reset(1); MotionPlayer.reset(2)
		for _, extra in { { role = "Attacker" }, { role = "Defender" } } do
			-- A bare throw table: no frame, duration, impactFrame or move.
			local v = fighterView("Kael", 0, Vector3.xAxis, { state = "Ultimate", throw = { archetype = "ultimate", role = extra.role } })
			local ok, err = pcall(MotionPlayer.sample, Config, v :: any, { now = 0, hitstop = 0 }, 1)
			t.expect.truthy(ok, "bare " .. extra.role .. " throw table: " .. tostring(err))
		end
		-- No frame table at all, and a frame without the opponent.
		local a = ultimateFrame("Sierra", "Kael", 40)
		t.expect.truthy((pcall(MotionPlayer.sample, Config, a :: any, nil, 1)), "no frame table")
		MotionPlayer.reset(1); MotionPlayer.reset(2)
	end)

	t.test("signature stances play their entry, loop and exit clips", function()
		for _, id in FIGHTERS do
			local def = Roster.get(id)
			for key, st in (def.stances or {}) :: any do
				MotionPlayer.reset(1)
				local entry = ClipLibrary.has("Kick_" .. id .. "_" .. key)
				t.expect.truthy(entry, id .. "." .. key .. " has its entry clip")
				t.expect.truthy(ClipLibrary.has(id .. "_" .. key), id .. "." .. key .. " has its stance clip")
				local seen: { [string]: boolean } = {}
				for sf = 1, st.maxFrames, 2 do
					local v = fighterView(id, 0, Vector3.xAxis, { state = "Stance", stance = key, stanceFrame = sf })
					local req = States.request(v, { now = sf / 60 }, 1, id, 1.35, { clock = sf / 60, keyStarted = 0, key = nil, settling = false, config = Config })
					seen[string.match(req.key, "^[^:]+") or req.key] = true
					local pose = MotionPlayer.sample(Config, v :: any, { now = sf / 60, hitstop = 0 }, 1)
					t.expect.truthy(finite(pose.rootOffset), string.format("%s.%s stance frame %d finite", id, key, sf))
				end
				t.expect.truthy(seen.Sig == true, id .. "." .. key .. " reaches its stance clip")
				-- Leaving the stance into the guard: the exit clip when installed.
				local idle = fighterView(id, 0, Vector3.xAxis)
				local req = States.request(idle, { now = 1 }, 1, id, 1.35, { clock = 1, keyStarted = 0.5, key = "Sig:" .. key, settling = false, config = Config })
				if ClipLibrary.has(id .. "_" .. key .. "Exit") then
					t.expect.equal(req.key, "SigExit:" .. key, id .. "." .. key .. " plays its exit clip")
				else
					t.expect.equal(req.key, "Stance", id .. "." .. key .. " crossfades into the guard")
				end
			end
		end
		MotionPlayer.reset(1)
	end)

	t.test("a tumbling juggled body rolls over in the air", function()
		t.expect.truthy(ClipLibrary.has("AirTumble"), "AirTumble installed")
		local v = fighterView("Rhys", 0, Vector3.xAxis, { state = "Airborne", tumble = true, velocityY = 8, airFrames = 10, airHits = 2,
			pos = Vector3.new(0, 3, 0), lastHit = { kind = "Hit", frame = 100, move = "SpinBackfist", height = "High" } })
		local req = States.request(v, { now = 0 }, 1, "Rhys", 1.35, { clock = 0, keyStarted = 0, key = nil, settling = false, config = Config })
		t.expect.equal(string.sub(req.key, 1, 16), "Airborne:Tumble:", "tumble request")
		MotionPlayer.reset(1)
		local pose = MotionPlayer.sample(Config, v :: any, { now = 0, hitstop = 0 }, 1)
		t.expect.truthy(finite(pose.rootOffset), "tumble pose finite")
		v.tumble = nil
		local plain = States.request(v, { now = 0 }, 1, "Rhys", 1.35, { clock = 0, keyStarted = 0, key = nil, settling = false, config = Config })
		t.expect.truthy(string.sub(plain.key, 1, 16) ~= "Airborne:Tumble:", "no tumble flag, no roll")
		MotionPlayer.reset(1)
	end)
end
