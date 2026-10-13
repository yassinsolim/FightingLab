--!strict
-- motionkicks coverage: every kick-type move (kicks, knees, sweeps, acrobatic kicks: the move's own last button is 3 or
-- 4 = LK / RK, not a throw) of every fighter plays a clip from Motion.Clips.Moves.Kicks named Kick_<Fighter>_<Key>; the
-- clip's contact lands on the first active frame (startup + 1) and the clip ends with the move; credits are accepted
-- catalog ids; channels decode to finite values with unit quaternions; clips stay in place horizontally (no root
-- travel); the contact pose is finite and the striking foot (or knee) is in front of the fighter; string follow-ups
-- start from the previous move's pose on its last displayed frame (startup + active; the sim starts the follow-up
-- on the next frame).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lab = ReplicatedStorage.FightingLab
local Config = require(Lab.CombatConfig)
local Roster = require(Lab.Roster)
local MotionPlayer = require(Lab.Client.MotionPlayer)
local ClipLibrary = require(Lab.Client.Motion.ClipLibrary)
local ClipPlayer = require(Lab.Client.Motion.ClipPlayer)

local FIGHTERS = { "Kael", "Sierra", "Goran", "Lumi", "Rhys", "Nia" }
local LIMB = { LeadLeg = "LeftFoot", RearLeg = "RightFoot" }
local ACCEPTED_PREFIX = { "accad-", "cmu-", "quat-" }

local function kicksFolder(): Instance?
	local clips = Lab.Client.Motion:FindFirstChild("Clips")
	local moves = clips and clips:FindFirstChild("Moves")
	return moves and moves:FindFirstChild("Kicks")
end

-- A string clip belongs to the category of its own last button: kicks are LK / RK.
local function isKick(move: any): boolean
	if move.height == "Throw" then return false end
	local token = string.match(move.input, "[^,]+$") or move.input
	token = string.gsub(token, "^%s+", "")
	local button = string.match(token, "([LR][PK])$")
	return button == "LK" or button == "RK"
end

local function kickMoves(): { { id: string, key: string, move: any } }
	local out = {}
	for _, id in FIGHTERS do
		local character = Roster.get(id)
		for _, key in character.moveOrder do
			local move = character.moves[key]
			if isKick(move) then table.insert(out, { id = id, key = key, move = move }) end
		end
	end
	return out
end

local function finite(x: number): boolean return x == x and math.abs(x) < math.huge end

local function channelValue(clip: any, c: number, f: number): number
	local v = clip.channels[c]
	if type(v) == "number" then return v end
	return v[f]
end

local function accepted(id: string): boolean
	if id == "original:motionkicks" then return true end
	for _, p in ACCEPTED_PREFIX do
		if string.sub(id, 1, #p) == p then return true end
	end
	return false
end

local function timingOf(move: any)
	return { startup = move.startup, active = move.active, recovery = move.recovery }
end

return function(t)
	t.test("every kick-type move of every fighter resolves to its Moves.Kicks clip", function()
		local folder = kicksFolder()
		t.expect.truthy(folder ~= nil, "Motion.Clips.Moves.Kicks exists")
		local index = ClipLibrary.index()
		local moves = kickMoves()
		t.expect.equal(#moves, 77, "77 kick-type moves across the roster (round 6: + string enders, stance entries and follow-ups, the catch)")
		for _, m in moves do
			local si = if m.move.chainFrom then 2 else nil
			local name = m.id .. "." .. m.key
			local clip = ClipLibrary.forMove(m.id, m.key, si)
			t.expect.truthy(clip ~= nil, name .. " has a clip")
			if clip then
				t.expect.equal(clip.name, "Kick_" .. m.id .. "_" .. m.key, name .. " clip name")
				local entry = index[clip.name]
				t.expect.truthy(entry ~= nil and folder ~= nil and entry.module:IsDescendantOf(folder :: Instance), name .. " clip lives in Moves.Kicks")
				t.expect.equal(clip.fighter, string.lower(m.id), name .. " is fighter-specific")
				t.expect.equal(clip.move, m.key)
				t.expect.equal(MotionPlayer.resolveMove(m.id, m.key, Roster.get(m.id).stats.height * 0.5).source, "Clip", name .. " resolves to the clip")
			end
		end
		t.expect.equal(#ClipLibrary.problems(), 0, "no clip load/duplicate problems: " .. table.concat(ClipLibrary.problems(), "; "))
	end)

	t.test("contact on startup + 1, ends with the move, credits, finite channels, unit quaternions, no root travel", function()
		for _, m in kickMoves() do
			local clip = ClipLibrary.forMove(m.id, m.key) :: any
			local name = m.id .. "." .. m.key
			local timing = timingOf(m.move)
			t.expect.truthy(type(clip.contact) == "number" and clip.contact > 0 and clip.contact < 1, name .. " has a contact mark")
			t.expect.near(ClipPlayer.moveTime(clip, timing, m.move.startup + 1), clip.contact * clip.duration, 1e-9, name .. " contact on the first active frame")
			t.expect.near(ClipPlayer.moveTime(clip, timing, m.move.startup + m.move.active + m.move.recovery), clip.duration, 1e-9, name .. " ends with the move")
			t.expect.truthy(#clip.sources > 0, name .. " credits its sources")
			for _, id in clip.sources do
				t.expect.truthy(accepted(id), name .. " source " .. tostring(id) .. " is an accepted catalog id")
			end
			t.expect.truthy(clip.travel.Magnitude < 1e-6, name .. " is in place horizontally (no root travel)")
			for f = 1, clip.frames do
				for c = 1, ClipLibrary.CHANNELS do
					if not finite(channelValue(clip, c, f)) then error(name .. " channel " .. c .. " frame " .. f .. " is not finite") end
				end
				for _, q in { 4, 8, 12, 22, 32, 42, 52 } do
					local x, y, z, w = channelValue(clip, q, f), channelValue(clip, q + 1, f), channelValue(clip, q + 2, f), channelValue(clip, q + 3, f)
					local len = math.sqrt(x * x + y * y + z * z + w * w)
					if math.abs(len - 1) > 0.02 then error(string.format("%s quaternion %d frame %d length %.3f", name, q, f, len)) end
				end
			end
			local contacts = 0
			for _, c in { 56, 57 } do
				for f = 1, clip.frames do
					local v = channelValue(clip, c, f)
					if v < -0.01 or v > 1.01 then error(string.format("%s contact channel %d frame %d = %.3f", name, c, f, v)) end
					contacts += v
				end
			end
			t.expect.truthy(contacts > 0, name .. " plants at least one foot")
		end
	end)

	t.test("contact pose: finite body, striking foot or knee in front of the fighter", function()
		for _, m in kickMoves() do
			MotionPlayer.reset(43)
			local id, key = m.id, m.key
			local view = { pos = Vector3.zero, facing = Vector3.xAxis, state = "Active", move = key, moveFrame = m.move.startup + 1,
				stringIndex = if m.move.chainFrom then 2 else 1, walkPhase = 0, stun = 0, crouched = m.move.crouching == true, moveX = 0,
				characterId = id, rootHeight = 4.1, legLength = 3.18 }
			local pose = MotionPlayer.sample(Config, view :: any, { now = 0, hitstop = 0 }, 43)
			local clip = ClipLibrary.forMove(id, key) :: any
			local limb = (clip.tags and clip.tags.limb) or LIMB[m.move.limb]
			if m.move.limb == "Body" then
				-- 3+4 signatures (stance entries, the catch): no striking leg; the body stays with the sim root.
				t.expect.truthy(pose.rootOffset.Z > -0.5, id .. "." .. key .. " body stays with the sim root")
				continue
			end
			t.expect.truthy(limb ~= nil, id .. "." .. key .. " has a striking leg")
			local target = pose.targets[limb]
			t.expect.truthy(target ~= nil, id .. "." .. key .. " pose has the " .. tostring(limb) .. " target")
			if target then
				local p = target.pos
				t.expect.truthy(finite(p.X) and finite(p.Y) and finite(p.Z), id .. "." .. key .. " foot target finite")
				-- knees: the foot hangs under the raised knee (in front of the hip); every other kick reaches out
				local minZ = if m.move.anim and m.move.anim.archetype == "knee" then 0.0 else 0.4
				t.expect.truthy(p.Z > minZ, string.format("%s.%s striking foot forward at contact (%.2f)", id, key, p.Z))
			end
		end
		MotionPlayer.reset(43)
	end)

	t.test("string follow-ups start from the previous move's pose on its last displayed frame", function()
		local count = 0
		for _, m in kickMoves() do
			local prevKey = m.move.chainFrom
			if prevKey then
				count += 1
				local prevMove = Roster.getMove(m.id, prevKey)
				local prev = ClipLibrary.forMove(m.id, prevKey) :: any
				local clip = ClipLibrary.forMove(m.id, m.key, 2) :: any
				t.expect.truthy(prev ~= nil, m.id .. "." .. prevKey .. " (previous move) has a clip")
				if prev then
					local tPrev = ClipPlayer.moveTime(prev, timingOf(prevMove), prevMove.startup + prevMove.active)
					local a = ClipPlayer.sample(prev, tPrev, { legLength = 3.18, scale = 1.35 })
					local b = ClipPlayer.sample(clip, 0, { legLength = 3.18, scale = 1.35 })
					local worst = 0
					for _, limb in { "LeftHand", "RightHand", "LeftFoot", "RightFoot" } do
						worst = math.max(worst, (a.targets[limb].pos - b.targets[limb].pos).Magnitude)
					end
					worst = math.max(worst, (a.rootOffset - b.rootOffset).Magnitude)
					t.expect.truthy(worst < 0.35, string.format("%s.%s starts at %s's chain pose (gap %.3f studs)", m.id, m.key, prevKey, worst))
				end
			end
		end
		t.expect.equal(count, 24, "24 kick string follow-ups")
	end)

	t.test("every clip in Moves.Kicks binds a roster kick-type move", function()
		local folder = kicksFolder()
		local count = 0
		for name, entry in ClipLibrary.index() do
			if folder and entry.module:IsDescendantOf(folder) then
				count += 1
				local raw = entry.raw
				t.expect.truthy(Roster.has(raw.fighter), name .. " fighter " .. tostring(raw.fighter))
				local ok, move = pcall(Roster.getMove, raw.fighter, raw.move)
				t.expect.truthy(ok and isKick(move), name .. " binds kick-type move " .. tostring(raw.move))
			end
		end
		t.expect.equal(count, 77, "one clip per kick-type move")
	end)
end
