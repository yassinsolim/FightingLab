--!strict
-- motionthrows: every roster throw (height "Throw") of every fighter is bound to a hand-keyed two-role FLThrow1 clip
-- (attacker + defender + break tracks) and a grab-attempt FLClip1. The defender's floor impact lands on
-- throw.impactFrame and its last frame is FallBack's floor-contact pose (Landing continues from there), the attacker
-- ends in the same displayed stance its grab clip starts from (with the endThrow push baked in), credits are listed.
-- ClipPlayer poses are library axes relative to the fighter's heading: +Z = toward the opponent, so "pushed back" = -Z.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lab = ReplicatedStorage.FightingLab
local Config = require(Lab.CombatConfig)
local Roster = require(Lab.Roster)
local MotionPlayer = require(Lab.Client.MotionPlayer)
local ClipLibrary = require(Lab.Client.Motion.ClipLibrary)
local ClipPlayer = require(Lab.Client.Motion.ClipPlayer)

local LEG = 2.85
local OPTS = { legLength = LEG, scale = 1 }
local FALLBACK_CONTACT = 0.3667 -- FallBack's floor contact (s): Landing after a throw continues from this frame
local END_PUSH = 0.155 -- baked CombatSim.endThrow push (0.45 studs on a mid-size fighter), leg lengths
local BREAK_PUSH = 0.207 -- baked broken-throw push (0.6 studs), leg lengths
-- The long karate and kickboxing stances end each throw with the lead foot stepped clear of the lying defender's
-- raised FallBack foot (no end-pose overlap); Idle's crossfade takes it back to the stance spot. Hands stay strict.
local END_FEET_TOL = 0.62 -- studs
local LIMBS = { "LeftHand", "RightHand", "LeftFoot", "RightFoot" }

type ThrowEntry = { id: string, key: string, move: any }

local function throwMoves(): { ThrowEntry }
	local list: { ThrowEntry } = {}
	for _, id in Roster.order do
		local keys = {}
		for key, m in Roster.get(id).moves do
			if m.height == "Throw" then table.insert(keys, key) end
		end
		table.sort(keys)
		for _, key in keys do table.insert(list, { id = id, key = key, move = Roster.getMove(id, key) }) end
	end
	return list
end

local function angleBetween(a: CFrame, b: CFrame): number
	local _, angle = (a:Inverse() * b):ToAxisAngle()
	return math.abs(math.deg(angle))
end

local function finitePose(pose: any): boolean
	local r = pose.rootOffset
	if r.Magnitude ~= r.Magnitude or r.Magnitude > 20 then return false end
	for _, limb in LIMBS do
		local p = pose.targets[limb].pos
		if p.Magnitude ~= p.Magnitude or p.Magnitude > 20 then return false end
	end
	return true
end

local function view(characterId: string, extra: { [string]: any }): any
	local v: { [string]: any } = { pos = Vector3.zero, facing = Vector3.xAxis, state = "Throw", moveFrame = 0, walkPhase = 0, stun = 0, crouched = false, moveX = 0, characterId = characterId, rootHeight = 3.7, legLength = LEG }
	for k, x in extra do v[k] = x end
	return v
end

return function(t)
	t.test("every roster throw has a two-role clip with break tracks, a grab clip and credits", function()
		local list = throwMoves()
		t.expect.equal(#list, 13, "13 throws on the roster")
		for _, e in list do
			local tag = e.id .. "." .. e.key
			local tc = ClipLibrary.forThrow(e.id, e.key)
			t.expect.truthy(tc ~= nil, tag .. " has an FLThrow1 clip")
			if tc then
				t.expect.equal(tc.name, e.id .. "_" .. e.key, tag .. " fighter-specific clip")
				t.expect.truthy(tc.attacker ~= nil and tc.defender ~= nil, tag .. " attacker and defender tracks")
				t.expect.truthy(tc.breakAttacker ~= nil and tc.breakDefender ~= nil, tag .. " break tracks")
				t.expect.truthy(table.find(tc.sources, "original:motionthrows") ~= nil and #tc.sources >= 2, tag .. " credits (" .. table.concat(tc.sources, ", ") .. ")")
			end
			local grab = ClipLibrary.forMove(e.id, e.key)
			t.expect.truthy(grab ~= nil and (grab :: any).name == e.id .. "_" .. e.key .. "_Grab", tag .. " grab clip bound to the move key")
			if grab then t.expect.truthy(#grab.sources >= 2, tag .. " grab credits") end
		end
		t.expect.truthy(#ClipLibrary.problems() == 0, "no malformed clip modules: " .. table.concat(ClipLibrary.problems(), "; "))
	end)

	t.test("throw clips follow the roster timing: impact on throw.impactFrame, durations, distance, 16-frame breaks", function()
		local breakFrames = Config.ThrowBreakFrames or 16
		for _, e in throwMoves() do
			local tag = e.id .. "." .. e.key
			local tc = ClipLibrary.forThrow(e.id, e.key)
			if not tc then
				t.expect.truthy(false, tag .. " missing")
				continue
			end
			local m = e.move
			t.expect.near(tc.impact, m.impactFrame / m.duration, 1e-3, tag .. " impact = impactFrame / duration")
			t.expect.near(tc.attacker.duration, m.duration / 60, 1 / 60 + 1e-6, tag .. " attacker track spans the throw")
			t.expect.near(tc.defender.duration, m.duration / 60, 1 / 60 + 1e-6, tag .. " defender track spans the throw")
			t.expect.near(tc.distance, 1.0714, 0.01, tag .. " authored root distance (leg lengths)")
			t.expect.near((tc.breakAttacker :: any).duration, breakFrames / 60, 1 / 60 + 1e-6, tag .. " attacker break track length")
			t.expect.near((tc.breakDefender :: any).duration, breakFrames / 60, 1 / 60 + 1e-6, tag .. " defender break track length")
			t.expect.near(MotionPlayer.throwTime(tc.impact, m.impactFrame, m.impactFrame, m.duration), tc.impact, 1e-9, tag .. " runtime maps impactFrame onto the clip impact")
		end
	end)

	t.test("the defender hits the floor on the impact frame and ends on FallBack's floor-contact pose", function()
		local fallBack = ClipLibrary.get("FallBack")
		t.expect.truthy(fallBack ~= nil, "Core FallBack installed")
		if not fallBack then return end
		local contact = ClipPlayer.sample(fallBack, FALLBACK_CONTACT, OPTS)
		for _, e in throwMoves() do
			local tag = e.id .. "." .. e.key
			local tc = ClipLibrary.forThrow(e.id, e.key)
			if not tc then continue end
			local d = tc.defender
			local m = e.move
			local before = ClipPlayer.sample(d, (m.impactFrame - 2) / 60, OPTS)
			local hit = ClipPlayer.sample(d, tc.impact * d.duration, OPTS)
			t.expect.truthy(before.ground < 0.05, string.format("%s not yet down two frames before the impact (ground %.2f)", tag, before.ground))
			t.expect.truthy(hit.ground > 0.95, string.format("%s on the floor at the impact (ground %.2f)", tag, hit.ground))
			local last = ClipPlayer.sample(d, d.duration, OPTS)
			local dRoot = last.rootOffset - contact.rootOffset
			t.expect.near(dRoot.X, 0, 0.06, tag .. " end root X = FallBack contact")
			t.expect.near(dRoot.Y, 0, 0.06, tag .. " end root height = FallBack contact")
			t.expect.near(dRoot.Z, -END_PUSH * LEG, 0.08, tag .. " end root = FallBack contact pushed back by the baked endThrow offset")
			t.expect.truthy(angleBetween(last.rootRot, contact.rootRot) < 3, tag .. " end root rotation = FallBack contact")
			for _, limb in LIMBS do
				local gap = (last.targets[limb].pos - contact.targets[limb].pos).Magnitude
				t.expect.truthy(gap < 0.1, string.format("%s %s ends on the FallBack contact pose (gap %.3f studs)", tag, limb, gap))
			end
			t.expect.truthy(last.ground > 0.95, tag .. " lying at the end")
		end
	end)

	t.test("the attacker ends in the stance its grab clip starts from, pushed back by the baked offset", function()
		for _, e in throwMoves() do
			local tag = e.id .. "." .. e.key
			local tc = ClipLibrary.forThrow(e.id, e.key)
			local grab = ClipLibrary.forMove(e.id, e.key)
			if not tc or not grab then continue end
			local start = ClipPlayer.sample(grab, 0, OPTS)
			local grabEnd = ClipPlayer.sample(grab, grab.duration, OPTS)
			local throwEnd = ClipPlayer.sample(tc.attacker, tc.attacker.duration, OPTS)
			local breakEnd = ClipPlayer.sample(tc.breakAttacker :: any, (tc.breakAttacker :: any).duration, OPTS)
			for name, pose in { throw = throwEnd, ["break"] = breakEnd } do
				local push = if name == "throw" then END_PUSH else BREAK_PUSH
				local dRoot = pose.rootOffset - start.rootOffset
				t.expect.near(dRoot.X, 0, 0.05, tag .. " " .. name .. " end root X")
				t.expect.near(dRoot.Y, 0, 0.05, tag .. " " .. name .. " end root height")
				t.expect.near(dRoot.Z, -push * LEG, 0.06, tag .. " " .. name .. " end pushed back")
				t.expect.truthy(angleBetween(pose.rootRot, start.rootRot) < 2, tag .. " " .. name .. " end facing = stance")
				for _, limb in LIMBS do
					local gap = (pose.targets[limb].pos - start.targets[limb].pos).Magnitude
					local tol = if name == "throw" and (limb == "LeftFoot" or limb == "RightFoot") then END_FEET_TOL else 0.08
					t.expect.truthy(gap < tol, string.format("%s %s end %s = stance (gap %.3f, tol %.2f)", tag, name, limb, gap, tol))
				end
			end
			for _, limb in LIMBS do
				local gap = (grabEnd.targets[limb].pos - start.targets[limb].pos).Magnitude
				t.expect.truthy(gap < 0.08, string.format("%s grab clip returns to the stance (%s gap %.3f)", tag, limb, gap))
			end
		end
	end)

	t.test("grab attempts reach on the roster's first active frame and opt out of the strike aim layer", function()
		for _, e in throwMoves() do
			local tag = e.id .. "." .. e.key
			local grab = ClipLibrary.forMove(e.id, e.key)
			if not grab then
				t.expect.truthy(false, tag .. " grab missing")
				continue
			end
			local m = e.move
			t.expect.near((grab.contact or 0) * grab.duration, (m.startup + 1) / 60, 1 / 60 + 1e-6, tag .. " contact = first active frame")
			t.expect.truthy(grab.tags.aim == false, tag .. " aim layer disabled (hands go to the collar, not a strike height)")
			local timing = { startup = m.startup, active = m.active, recovery = m.recovery }
			t.expect.near(ClipPlayer.moveTime(grab, timing, m.startup + 1), (grab.contact or 0) * grab.duration, 1e-9, tag .. " warp shows the reach on the first active frame")
		end
	end)

	t.test("every throw and break track is finite at every sampled frame", function()
		for _, e in throwMoves() do
			local tc = ClipLibrary.forThrow(e.id, e.key)
			if not tc then continue end
			for name, clip in { attacker = tc.attacker, defender = tc.defender, breakAttacker = tc.breakAttacker, breakDefender = tc.breakDefender } do
				local c = clip :: any
				local n = math.max(math.ceil(c.duration * 30), 1)
				for i = 0, n do
					local pose = ClipPlayer.sample(c, c.duration * i / n, OPTS)
					t.expect.truthy(finitePose(pose), string.format("%s.%s %s finite at %.3f s", e.id, e.key, name, c.duration * i / n))
				end
			end
		end
	end)

	t.test("MotionPlayer poses both roles from the throw clip and the defender is down after the impact", function()
		local ok, err = pcall(function()
			for _, e in throwMoves() do
				local m = e.move
				local tag = e.id .. "." .. e.key
				local function sampleBoth(frameNo: number): (any, any)
					local function state(role: string): any
						return { role = role, move = e.key, archetype = (m.anim and m.anim.archetype) or "slam", frame = frameNo, duration = m.duration, impactFrame = m.impactFrame, breakWindow = m.breakWindow }
					end
					local attacker = view(e.id, { throw = state("Attacker") })
					local defender = view("Sierra", { throw = state("Defender"), pos = Vector3.new(3, 0, 0), facing = -Vector3.xAxis })
					MotionPlayer.reset(41); MotionPlayer.reset(42)
					local frame = { now = 0, hitstop = 0, fighters = { attacker, defender } }
					return MotionPlayer.sample(Config, attacker, frame, 41), MotionPlayer.sample(Config, defender, frame, 42)
				end
				local pa, pd = sampleBoth(2)
				t.expect.truthy(pa.space == "heading" and finitePose(pa), tag .. " attacker posed from the clip")
				t.expect.truthy(pd.space == "heading" and finitePose(pd), tag .. " defender posed from the clip")
				local _, down = sampleBoth(m.impactFrame + 4)
				t.expect.truthy(finitePose(down) and down.rootOffset.Y < -1.2, string.format("%s defender down after the impact (root %.2f)", tag, down.rootOffset.Y))
			end
		end)
		MotionPlayer.reset()
		if not ok then error(err, 0) end
	end)
end
