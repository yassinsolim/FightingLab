--!strict
-- motionstrikes coverage: every punch-type move (the move's own last button is 1 or 2, not a throw) of every fighter
-- plays a clip from Motion.Clips.Moves.Strikes; the clip's contact lands on the first active frame (startup + 1);
-- credits are present; channels decode to finite values with unit quaternions; string follow-ups start from the
-- previous hit's cancel pose; the contact pose puts the striking limb in front of the fighter.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lab = ReplicatedStorage.FightingLab
local Config = require(Lab.CombatConfig)
local Roster = require(Lab.Roster)
local MotionPlayer = require(Lab.Client.MotionPlayer)
local ClipLibrary = require(Lab.Client.Motion.ClipLibrary)
local ClipPlayer = require(Lab.Client.Motion.ClipPlayer)

local FIGHTERS = { "Kael", "Sierra", "Goran", "Lumi", "Rhys", "Nia" }
local LIMB = { LeadArm = "LeftHand", RearArm = "RightHand" }

local function strikesFolder(): Instance?
	local clips = Lab.Client.Motion:FindFirstChild("Clips")
	local moves = clips and clips:FindFirstChild("Moves")
	return moves and moves:FindFirstChild("Strikes")
end

-- A string clip belongs to the category of its own last button: punches are LP / RP.
local function isStrike(move: any): boolean
	if move.height == "Throw" then return false end
	local token = string.match(move.input, "[^,]+$") or move.input
	token = string.gsub(token, "^%s+", "")
	local button = string.match(token, "([LR][PK])$")
	return button == "LP" or button == "RP"
end

local function strikeMoves(): { { id: string, key: string, move: any } }
	local out = {}
	for _, id in FIGHTERS do
		local character = Roster.get(id)
		for _, key in character.moveOrder do
			local move = character.moves[key]
			if isStrike(move) then table.insert(out, { id = id, key = key, move = move }) end
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

return function(t)
	t.test("every punch-type move of every fighter resolves to a Moves.Strikes clip", function()
		local folder = strikesFolder()
		t.expect.truthy(folder ~= nil, "Motion.Clips.Moves.Strikes exists")
		local index = ClipLibrary.index()
		local moves = strikeMoves()
		t.expect.equal(#moves, 38, "38 punch-type moves across the roster")
		for _, m in moves do
			local si = if m.move.chainFrom then 2 else nil
			local clip = ClipLibrary.forMove(m.id, m.key, si)
			t.expect.truthy(clip ~= nil, m.id .. "." .. m.key .. " has a clip")
			if clip then
				local entry = index[clip.name]
				t.expect.truthy(entry ~= nil and folder ~= nil and entry.module:IsDescendantOf(folder :: Instance), m.id .. "." .. m.key .. " clip lives in Moves.Strikes")
				t.expect.equal(clip.fighter, string.lower(m.id), m.id .. "." .. m.key .. " is fighter-specific")
				t.expect.equal(clip.move, m.key)
				t.expect.equal(MotionPlayer.resolveMove(m.id, m.key, Roster.get(m.id).stats.height * 0.5).source, "Clip", m.id .. "." .. m.key .. " resolves to the clip")
			end
		end
		t.expect.equal(#ClipLibrary.problems(), 0, "no clip load/duplicate problems: " .. table.concat(ClipLibrary.problems(), "; "))
	end)

	t.test("contact lands exactly on startup + 1; credits present; channels finite with unit quaternions", function()
		for _, m in strikeMoves() do
			local clip = ClipLibrary.forMove(m.id, m.key) :: any
			local name = m.id .. "." .. m.key
			local timing = { startup = m.move.startup, active = m.move.active, recovery = m.move.recovery }
			t.expect.truthy(type(clip.contact) == "number" and clip.contact > 0 and clip.contact < 1, name .. " has a contact mark")
			t.expect.near(ClipPlayer.moveTime(clip, timing, m.move.startup + 1), clip.contact * clip.duration, 1e-9, name .. " contact on the first active frame")
			t.expect.near(ClipPlayer.moveTime(clip, timing, m.move.startup + m.move.active + m.move.recovery), clip.duration, 1e-9, name .. " ends with the move")
			t.expect.truthy(#clip.sources > 0, name .. " credits its sources")
			for _, id in clip.sources do
				t.expect.truthy(string.sub(id, 1, 6) == "accad-" or id == "original:motionstrikes", name .. " source " .. tostring(id) .. " is an accepted catalog id")
			end
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
		end
	end)

	t.test("contact pose: finite body, striking hand in front of the fighter", function()
		for _, m in strikeMoves() do
			MotionPlayer.reset(41)
			local id, key = m.id, m.key
			local view = { pos = Vector3.zero, facing = Vector3.xAxis, state = "Active", move = key, moveFrame = m.move.startup + 1,
				stringIndex = if m.move.chainFrom then 2 else 1, walkPhase = 0, stun = 0, crouched = m.move.crouching == true, moveX = 0,
				characterId = id, rootHeight = 4.1, legLength = 3.18 }
			local pose = MotionPlayer.sample(Config, view :: any, { now = 0, hitstop = 0 }, 41)
			local limb = LIMB[m.move.limb]
			if limb then
				t.expect.truthy(pose.targets[limb].pos.Z > 0.6, id .. "." .. key .. " striking hand forward at contact (" .. string.format("%.2f", pose.targets[limb].pos.Z) .. ")")
			else
				t.expect.truthy(pose.rootOffset.Z > -0.5, id .. "." .. key .. " body stays with the sim root")
			end
		end
		MotionPlayer.reset(41)
	end)

	t.test("string follow-ups start from the previous hit's cancel pose", function()
		for _, m in strikeMoves() do
			local prevKey = m.move.chainFrom
			if prevKey then
				local prevMove = Roster.getMove(m.id, prevKey)
				local prev = ClipLibrary.forMove(m.id, prevKey) :: any
				local clip = ClipLibrary.forMove(m.id, m.key, 2) :: any
				-- The sim starts the follow-up on the previous move's frame startup + active + 1.
				local tPrev = ClipPlayer.moveTime(prev, { startup = prevMove.startup, active = prevMove.active, recovery = prevMove.recovery }, prevMove.startup + prevMove.active + 1)
				local a = ClipPlayer.sample(prev, tPrev, { legLength = 3.18, scale = 1.35 })
				local b = ClipPlayer.sample(clip, 0, { legLength = 3.18, scale = 1.35 })
				local worst = 0
				for _, limb in { "LeftHand", "RightHand", "LeftFoot", "RightFoot" } do
					worst = math.max(worst, (a.targets[limb].pos - b.targets[limb].pos).Magnitude)
				end
				worst = math.max(worst, (a.rootOffset - b.rootOffset).Magnitude)
				t.expect.truthy(worst < 0.25, string.format("%s.%s starts at %s's cancel pose (gap %.3f studs)", m.id, m.key, prevKey, worst))
			end
		end
	end)

	t.test("every clip in Moves.Strikes binds a roster punch-type move", function()
		local folder = strikesFolder()
		local count = 0
		for name, entry in ClipLibrary.index() do
			if folder and entry.module:IsDescendantOf(folder) then
				count += 1
				local raw = entry.raw
				t.expect.truthy(Roster.has(raw.fighter), name .. " fighter " .. tostring(raw.fighter))
				local ok, move = pcall(Roster.getMove, raw.fighter, raw.move)
				t.expect.truthy(ok and isStrike(move), name .. " binds punch-type move " .. tostring(raw.move))
			end
		end
		t.expect.equal(count, 38, "one clip per punch-type move")
	end)
end
