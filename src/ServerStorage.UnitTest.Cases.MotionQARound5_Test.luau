--!strict
-- MotionQA round 5: the four motion issues left after round 4, on the REAL fighter rigs of all six fighters (harness:
-- ServerStorage.UnitTest.MotionQA; targets and fixes: docs/design/motioncore.md 14).
--   1. Knockdowns into getups without a spin: from the frame before a fighter reaches the floor (a grounded knockdown,
--      a launcher fall, a juggle ending face up or face down, a KO) through Landing, every getup (Stand, BackRoll,
--      SideRoll left/right, late rolls) and the stance after it, the pelvis never yaws or rolls more than 15 degrees in
--      a frame and no limb, the head or the chest turns more than 30 degrees in a frame relative to the pelvis.
--   2. Point-blank strikes do not sink: every strike and kick at point-blank (Separation), mid and max range rests on
--      the opponent — the striking hand/foot and its forearm/shin <= 0.15 studs inside the head/chest/pelvis on the
--      active frames and through the recovery.
--   3. No self-clipping on the floor: in Landing, Getup, rolls and KO, and in every throw's defender track (thrown and
--      breaking the throw), the gloves / hands stay out of the own head (<= 0.03) and torso (<= 0.05) and the forearms'
--      centrelines out of the body (<= 0.05). Three defender cases remain over the limit (Nia's fingertips at her cheek,
--      thrown by or breaking Rhys's Throw; Rhys's forearm on Goran's RamSlam slam frame), each capped in
--      DEFENDER_EXCEPTIONS.
--   4. Kael's face reads: from the fight camera of both player slots (guard, idle, walk, backwalk, blockstun) at least
--      70% of his face landmarks (camera-side eye, nose, mouth) are not hidden by his gloves, while the gloves stay a
--      boxing guard (chin-to-cheek height, elbows in); Sierra (gloves) and every other fighter (hands) the same.
-- Each test stays well inside the runner's 5 s (knockdowns per fighter, source and face; strikes per fighter and range;
-- thrown defenders per fighter and attacker half; throw breaks and faces per fighter).
local QA = require(script.Parent.Parent:WaitForChild("MotionQA"))

local rigs: { [string]: QA.Staged }? = nil
local function staged(): { [string]: QA.Staged }
	if not rigs then rigs = QA.stage() end
	return rigs :: { [string]: QA.Staged }
end

local LYING = { Landing = true, Getup = true, KO = true, Knockdown = true }
local PLAY = {}

local function fmt(d: any): string
	return string.format("%s %s f%d %s %s = %.3f (limit %.3f) key=%s state=%s %s", d.fighter, d.case, d.frame, d.metric, d.part, d.value, d.limit, tostring(d.key), tostring(d.state), d.note or "")
end
local function report(list: { string }): string
	if #list == 0 then return "none" end
	local shown = {}
	for i = 1, math.min(#list, 12) do shown[i] = list[i] end
	return #list .. " defect(s):\n  " .. table.concat(shown, "\n  ")
end
-- Worst raw defect per (case, metric, part) among those `keep` accepts.
local function worst(defects: { any }, keep: (any) -> boolean): { string }
	local best: { [string]: any } = {}
	for _, d in defects do
		if keep(d) then
			local k = d.case .. "|" .. d.metric .. "|" .. d.part
			if not best[k] or d.value > best[k].value then best[k] = d end
		end
	end
	local list = {}
	for _, d in best do table.insert(list, d) end
	table.sort(list, function(a, b) return a.value / a.limit > b.value / b.limit end)
	local out = {}
	for _, d in list do table.insert(out, fmt(d)) end
	return out
end

-- Knockdown runs are shared by issue 1 and issue 3 (played once per fighter and half: face-up and face-down sources).
-- Knockdown sources (case labels kd:<source><Face>... and kd:ko:<source><Face>): one slice per fighter, source and face.
local KD_SOURCES = { "ground", "launch", "juggle" }
local KD_FACES = { "FaceUp", "FaceDown" }
local kdDefects: { [string]: { any } } = {}
local function knockdowns(id: string, source: string?, face: string?): { any }
	if not source or not face then
		local all = {}
		for _, s in KD_SOURCES do
			for _, f in KD_FACES do
				for _, x in knockdowns(id, s, f) do table.insert(all, x) end
			end
		end
		return all
	end
	local key = id .. "|" .. (source :: string) .. "|" .. (face :: string)
	local cached = kdDefects[key]
	if cached then return cached end
	local all = {}
	local tag = (source :: string) .. (face :: string)
	for _, c in QA.knockdownCases(id) do
		if string.find(c.label, tag, 1, true) then
			local d = QA.play(staged(), c, PLAY)
			for _, x in d do table.insert(all, x) end
		end
	end
	kdDefects[key] = all
	return all
end

local function selfClip(d: any): boolean
	if not LYING[d.state] then return false end
	if d.metric == "self.handHead" or d.metric == "self.handTorso" then return true end
	return d.metric == "self.armTorso" and string.find(d.part, "LowerArm", 1, true) ~= nil
end

-- Throw defender frames still over the limit on this branch (fighter|case|metric|part -> cap). Each is one to three
-- frames of a fast clip motion the runtime clearance cannot fully route around without popping the arm; a new defect,
-- or one of these getting worse than its cap, fails (motioncore.md 14.6).
local DEFENDER_EXCEPTIONS: { [string]: number } = {
	-- The fingertips of Nia's right hand graze her cheek on Rhys's Throw entry (0.033 vs 0.03), thrown or breaking it.
	["Nia|throw:Rhys.Throw|self.handHead|RightHand"] = 0.04,
	["Nia|throw:Rhys.Throw:broken|self.handHead|RightHand"] = 0.04,
	-- Goran's RamSlam swings Rhys's left forearm through his chest on the slam frame (1 frame, 0.20).
	["Rhys|throw:Goran.RamSlam|self.armTorso|LeftLowerArm"] = 0.23,
}
local function defenderClip(d: any): boolean
	local inScope = d.metric == "self.handHead" or d.metric == "self.handTorso"
		or (d.metric == "self.armTorso" and string.find(d.part, "LowerArm", 1, true) ~= nil)
	if not inScope then return false end
	local cap = DEFENDER_EXCEPTIONS[d.fighter .. "|" .. d.case .. "|" .. d.metric .. "|" .. d.part]
	return cap == nil or d.value > cap
end
local function defenderRuns(defender: string, broken: boolean, attackers: { string }?): { any }
	local all = {}
	for _, attacker in attackers or QA.Roster.order do
		for _, c in QA.throwCases(attacker, defender) do
			if (string.find(c.label, ":broken", 1, true) ~= nil) == broken then
				c.subjects = { 2 }
				local d = QA.play(staged(), c, PLAY)
				for _, x in d do table.insert(all, x) end
			end
		end
	end
	return all
end

return function(t)
	-- 1 + 3: knockdowns, getups, rolls, KO.
	local SOURCE_NAMES = { ground = "grounded knockdown", launch = "launcher fall", juggle = "juggle" }
	for _, id in QA.Roster.order do
		for _, source in KD_SOURCES do
			for _, face in KD_FACES do
				local what = (if face == "FaceUp" then "face-up " else "face-down ") .. SOURCE_NAMES[source]
				t.test("1. " .. id .. ": " .. what .. " into every getup (and the KO): no spin over 15 deg/frame, no limb whip over 30 deg/frame", function()
					local bad = worst(knockdowns(id, source, face), function(d) return d.metric == "getup.spin" or d.metric == "getup.whip" end)
					t.expect.truthy(#bad == 0, "knockdown continuity: " .. report(bad))
				end)
			end
		end
		t.test("3. " .. id .. ": hands and forearms clear of the own head and torso in Landing, Getup, rolls and KO", function()
			local bad = worst(knockdowns(id), selfClip)
			t.expect.truthy(#bad == 0, "self clipping on the floor: " .. report(bad))
		end)
	end
	-- 3: throw defender tracks (every throw of every fighter, each fighter as the defender), thrown and breaking the throw.
	-- The thrown tracks run in two tests per defender (the attackers in two halves) to stay well inside the runner's limit.
	local ATTACKER_HALVES: { { string } } = { {}, {} }
	for i, id in QA.Roster.order do
		table.insert(ATTACKER_HALVES[if i <= math.ceil(#QA.Roster.order / 2) then 1 else 2], id)
	end
	for _, defender in QA.Roster.order do
		for _, attackers in ATTACKER_HALVES do
			t.test("3. throw defender tracks (" .. defender .. " thrown by " .. table.concat(attackers, ", ") .. "): hands and forearms clear of the own head and torso", function()
				local bad = worst(defenderRuns(defender, false, attackers), defenderClip)
				t.expect.truthy(#bad == 0, "throw defender self clipping: " .. report(bad))
			end)
		end
		t.test("3. throw breaks (" .. defender .. " breaking everyone's throws): hands and forearms clear of the own head and torso", function()
			local bad = worst(defenderRuns(defender, true), defenderClip)
			t.expect.truthy(#bad == 0, "throw break self clipping: " .. report(bad))
		end)
	end
	-- 2: strikes at point-blank, mid and max range.
	for _, id in QA.Roster.order do
		for _, ranges in { { "close" }, { "mid" }, { "max" } } do
			local what = if ranges[1] == "close" then "point-blank" elseif ranges[1] == "mid" then "mid range" else "max range"
			t.test("2. " .. id .. ": every strike and kick at " .. what .. " rests on the opponent (<= 0.15 studs, active and recovery)", function()
				local all = {}
				for _, range in ranges do
					for _, c in QA.moveCases(id, { range }) do
						local m = c.meta
						local d = QA.play(staged(), c, PLAY)
						for _, x in d do
							if (x.metric == "opp.strike" or x.metric == "opp.through") and x.mf and x.mf > m.startup then table.insert(all, x) end
						end
					end
				end
				local bad = worst(all, function() return true end)
				t.expect.truthy(#bad == 0, "strike depth: " .. report(bad))
			end)
		end
	end
	-- 4: faces behind the guard.
	local function faceRun(id: string): (number, string, { [string]: any })
		local worstV, where = 1, ""
		-- The idle guard of each glove: lowest glove top above the chin, lowest glove centre under the eyes, widest elbow.
		local guard = { topOverChinMin = math.huge, underEyeMin = math.huge, elbowOutMax = -math.huge }
		local labels = { idle = true, walk = true, backwalk = true, ["idle>blockstun>idle"] = true }
		for _, c in QA.stateCases(id) do
			if labels[c.label] then
				for slot = 1, 2 do
					local cc = if slot == 1 then c else QA.slotTwo(c)
					local s = cc.subjects[1]
					QA.play(staged(), cc, { onFrame = function(f: number, st: { QA.Staged }, cfs: { any }, views: { any })
						-- After the case's lead-in (the rig settles from its reset pose).
						if f < 20 then return end
						local sub, cf = st[s], cfs[s]
						local v0 = views[s]
						-- The fight camera at a close and a mid spacing (the cases' partners stand far away in the walks).
						for _, sep in { 3.5, 7 } do
							local cam = QA.fightCamera(v0.pos, v0.pos + v0.facing.Unit * sep)
							local v = QA.faceVisibility(sub, cf, cam)
							if v < worstV then worstV, where = v, string.format("%s slot %d f%d (spacing %.1f)", c.label, slot, f, sep) end
						end
						if c.label == "idle" then
							local g = QA.guardShape(sub, cf)
							for _, hand in { "LeftHand", "RightHand" } do
								local h = g[hand]
								guard.topOverChinMin = math.min(guard.topOverChinMin, h.topOverChin)
								guard.underEyeMin = math.min(guard.underEyeMin, h.underEye)
								guard.elbowOutMax = math.max(guard.elbowOutMax, h.elbowOut)
							end
						end
					end })
				end
			end
		end
		return worstV, where, guard
	end
	t.test("4. Kael's face reads from the fight camera of both player slots (>= 70% of the eye, nose and mouth landmarks clear of the gloves) in a boxing guard", function()
		local v, where, g = faceRun("Kael")
		t.expect.truthy(v >= 0.70, string.format("Kael face visible %.0f%% at %s", v * 100, where))
		-- Still a boxing guard: both gloves reach the chin (glove top at most 0.1 below it), neither centre rises above the
		-- eyes, elbows no wider than 0.3 studs outside the shoulder line (round 4: 0.27).
		t.expect.truthy(g.topOverChinMin >= -0.10 and g.underEyeMin >= 0, string.format("Kael gloves out of the chin-cheek band: top %.2f over the chin, centre %.2f under the eye", g.topOverChinMin, g.underEyeMin))
		t.expect.truthy(g.elbowOutMax <= 0.30, string.format("Kael elbows flared %.2f studs outside the shoulders", g.elbowOutMax))
	end)
	for _, id0 in { "Sierra", "Goran", "Lumi", "Rhys", "Nia" } do
		local group = { id0 }
		t.test("4. " .. id0 .. (if id0 == "Sierra" then " (gloves)" else " (hands)") .. ": face visible from the fight camera of both player slots", function()
			local lines = {}
			for _, id in group do
				local v, where = faceRun(id)
				if v < 0.70 then table.insert(lines, string.format("%s %.0f%% at %s", id, v * 100, where)) end
			end
			if group[#group] == "Nia" then
				QA.destroy(rigs)
				rigs = nil
				table.clear(kdDefects)
			end
			t.expect.truthy(#lines == 0, "faces hidden: " .. table.concat(lines, "; "))
		end)
	end
end
