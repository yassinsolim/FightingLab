--!strict
-- Round 6 follow-up: whole bodies under the HUD (CameraDirector), on the REAL posed rigs of all six fighters.
--   * Ultimate cinematics: for every attacker and every defender (36 pairings), every 6th cinematic frame, every impact
--     and the last frame, both fighters' head tops, hands and soles projected through the cinematic camera as M.update
--     shows it (M._cinematicShot, the final hit's slow-motion narrowing, the final guard) lie inside CineSafe: between
--     the letterbox bars and under the HUD band; for the attacker's player and the defender's (mirrored shots), at 16:9
--     and 4:3, and the lens never opens wider than CineFitMaxFov.
--   * The fight camera: for every pairing at close, mid, start and far spacing and from both player slots, the plain
--     plan (M._plan, no fit) keeps every fighter's idle head top under the HUD band and the soles in the picture
--     (FightSafe); a pose taller than the plan allows and a throw's close orbit are fitted inside it by M._fitShot.
-- One test per attacker and defender half (each well inside the runner's 5 s).
local Lab = game:GetService("ReplicatedStorage").FightingLab
local Config = require(Lab.CombatConfig)
local Roster = require(Lab.Roster)
local CameraDirector = require(Lab.Client.CameraDirector)
local Cinematic = require(Lab.Client.Motion.Cinematic)
local MotionPlayer = require(Lab.Client.MotionPlayer)
local QA = require(script.Parent.Parent:WaitForChild("MotionQA"))

local FIGHTERS = { "Kael", "Sierra", "Goran", "Lumi", "Rhys", "Nia" }
local EPS = 0.004

local rigs: { [string]: QA.Staged }? = nil
local function staged(): { [string]: QA.Staged }
	if not rigs then rigs = QA.stage() end
	return rigs :: { [string]: QA.Staged }
end

-- Stand-ins for the posed parts (QA.posed: the part frames through the joint chain; the engine moves the parts a step
-- later), with what CameraDirector reads from a part.
local function proxies(sub: QA.Staged, cf: { [string]: CFrame }, out: { any })
	for name, frame in cf do
		local part = sub.rig.parts[name]
		if part then table.insert(out, { Name = name, CFrame = frame, Position = frame.Position, Size = part.Size }) end
	end
end

local function labelled(sub: QA.Staged, cf: { [string]: CFrame }, who: string, out: { any })
	local head = sub.rig.parts.Head :: BasePart
	table.insert(out, { who = who .. " head", p = cf.Head.Position + Vector3.new(0, head.Size.Y * 0.62, 0) })
	for _, n in { "LeftFoot", "RightFoot" } do
		local foot = sub.rig.parts[n] :: BasePart
		table.insert(out, { who = who .. " " .. n, p = cf[n].Position - Vector3.new(0, foot.Size.Y * 0.6, 0) })
	end
	for _, n in { "LeftHand", "RightHand" } do table.insert(out, { who = who .. " " .. n, p = cf[n].Position }) end
end

local function inside(v: Vector2?, s: any): boolean
	return v ~= nil and v.Y >= s.top - EPS and v.Y <= s.bottom + EPS and v.X >= s.left - EPS and v.X <= s.right + EPS
end

-- Plays `aId`'s Ultimate on `dId` (the MotionQA case: the startup at point-blank, then the cinematic at the sim's
-- positions) and checks the framing on the sampled frames. Returns the failures and the widest lens used.
local function cinematicFraming(aId: string, dId: string): ({ string }, number)
	local bad: { string } = {}
	local widest = 0
	local case = QA.ultimateCases(aId, dId)[1]
	if not case then return { aId .. " has no Ultimate cinematic" }, 0 end
	local m = Roster.get(aId).moves.Ultimate
	local LEAD, HIT = 20, m.startup + 1
	local tl = Cinematic.timeline(aId, nil)
	local impacts: { [number]: boolean } = {}
	for _, fr in tl.frames do impacts[fr] = true end
	local st = staged()
	local subs = { st[aId], st[if dId == aId then dId .. "#2" else dId] }
	for i = 1, 2 do
		MotionPlayer.reset(i)
		QA.resetRig(subs[i].rig)
	end
	local now = 0
	for f = LEAD - 6, LEAD + HIT + tl.duration do
		local info = case.at(f)
		local views = info.views
		now += 1 / 60
		for i = 1, 2 do
			views[i].characterId = subs[i].id
			views[i].rootHeight = subs[i].rig.rootHeight
			views[i].legLength = subs[i].rig.legLength
			views[i].aimHeights = subs[i].aim
		end
		local entries = {}
		for i = 1, 2 do entries[i] = { rig = subs[i].rig, root = subs[i].root, view = views[i], slot = i } end
		QA.present(entries, { now = now, dt = 1 / 60, hitstop = 0, phase = "Fight", winner = 0, fighters = views }, QA.ORIGIN)
		local cf = f - LEAD - HIT
		if cf >= 1 and (cf % 6 == 0 or impacts[cf] or cf == tl.duration) then
			local cfs = { QA.posed(subs[1].rig), QA.posed(subs[2].rig) }
			local parts: { any } = {}
			proxies(subs[1], cfs[1], parts)
			proxies(subs[2], cfs[2], parts)
			local points = CameraDirector._framingPointsOf(parts :: any, true)
			local named: { any } = {}
			labelled(subs[1], cfs[1], aId, named)
			labelled(subs[2], cfs[2], dId, named)
			local a = views[1]
			local base = QA.ORIGIN + Vector3.new(a.pos.X, 0, a.pos.Z)
			for _, mirrored in { false, true } do
				for _, aspect in { 16 / 9, 4 / 3 } do
					local shot = CameraDirector._cinematicShot(aId, a.throw, cf, base, a.facing, mirrored, parts :: any, points, aspect)
					local camCF = CFrame.lookAt(shot.pos, shot.look) * CFrame.Angles(0, 0, shot.roll)
					local fov = shot.fov - (if shot.slow then 4 else 0)
					local need = CameraDirector._safeFov(camCF, points, aspect, CameraDirector.CineSafe)
					if need then fov = math.max(fov, math.min(need, CameraDirector.GuardMaxFov)) end
					widest = math.max(widest, fov)
					if fov > CameraDirector.CineFitMaxFov + 0.5 and #bad < 10 then
						table.insert(bad, string.format("%s>%s f%d %s %.2f: lens opened to %.1f deg", aId, dId, cf, if mirrored then "mirrored" else "attacker side", aspect, fov))
					end
					for _, n in named do
						local v = CameraDirector._normalizedViewportPoint(camCF, fov, aspect, n.p)
						if not inside(v, CameraDirector.CineSafe) and #bad < 10 then
							table.insert(bad, string.format("%s>%s f%d %s %.2f: %s at %s", aId, dId, cf, if mirrored then "mirrored" else "attacker side", aspect, n.who,
								if v then string.format("(%.3f, %.3f)", v.X, v.Y) else "behind the lens"))
						end
					end
				end
			end
		end
	end
	return bad, widest
end

-- Idle extents of a fighter: its head top and soles in its own frame (x right, y up, -z forward) over the idle loop.
local idleCache: { [string]: { any } } = {}
local function idlePoints(id: string): { any }
	local cached = idleCache[id]
	if cached then return cached end
	local st = staged()
	local sub = st[id]
	local foe = st[if id == "Kael" then "Sierra" else "Kael"]
	MotionPlayer.reset(1)
	MotionPlayer.reset(2)
	QA.resetRig(sub.rig)
	QA.resetRig(foe.rig)
	local top: any, soles: { [string]: any } = nil, {}
	local now = 0
	for f = 1, 140 do
		now += 1 / 60
		local a = QA.view("Idle", { guard = "Stand", pos = Vector3.zero, facing = Vector3.xAxis })
		local b = QA.view("Idle", { guard = "Stand", pos = Vector3.new(Config.StartDistance, 0, 0), facing = -Vector3.xAxis })
		local views = { a, b }
		for i, s in { sub, foe } do
			views[i].characterId = s.id
			views[i].rootHeight = s.rig.rootHeight
			views[i].legLength = s.rig.legLength
			views[i].aimHeights = s.aim
		end
		QA.present({ { rig = sub.rig, root = sub.root, view = a, slot = 1 }, { rig = foe.rig, root = foe.root, view = b, slot = 2 } },
			{ now = now, dt = 1 / 60, hitstop = 0, phase = "Fight", winner = 0, fighters = views }, QA.ORIGIN)
		if f >= 20 then
			local cf = QA.posed(sub.rig)
			local frame = CFrame.lookAt(QA.ORIGIN, QA.ORIGIN + Vector3.xAxis)
			local head = sub.rig.parts.Head :: BasePart
			local h = frame:PointToObjectSpace(cf.Head.Position + Vector3.new(0, head.Size.Y * 0.62, 0))
			if not top or h.Y > top.Y then top = h end
			for _, n in { "LeftFoot", "RightFoot" } do
				local foot = sub.rig.parts[n] :: BasePart
				local p = frame:PointToObjectSpace(cf[n].Position - Vector3.new(0, foot.Size.Y * 0.6, 0))
				if not soles[n] or p.Y < soles[n].Y then soles[n] = p end
			end
		end
	end
	local list = { { who = "head", p = top }, { who = "LeftFoot", p = soles.LeftFoot }, { who = "RightFoot", p = soles.RightFoot } }
	idleCache[id] = list
	return list
end

return function(t)
	local test, expect = t.test, t.expect

	for _, aId in FIGHTERS do
		for half = 1, 2 do
			local defenders = if half == 1 then { "Kael", "Sierra", "Goran" } else { "Lumi", "Rhys", "Nia" }
			test(string.format("%s's Ultimate keeps both whole bodies between the letterbox bars and under the HUD (defenders %s)", aId, table.concat(defenders, ", ")), function()
				local lines: { string } = {}
				local widest = 0
				for _, dId in defenders do
					local bad, w = cinematicFraming(aId, dId)
					widest = math.max(widest, w)
					for _, line in bad do table.insert(lines, line) end
				end
				expect.truthy(#lines == 0, string.format("%d framing failure(s) (widest lens %.1f deg):\n  %s", #lines, widest, table.concat(lines, "\n  ", 1, math.min(#lines, 12))))
			end)
		end
	end

	for _, aId in FIGHTERS do
		test(aId .. ": the fight camera keeps every idle head under the HUD band and the feet in the picture (all opponents, spacings, slots)", function()
			local lines: { string } = {}
			local safe = CameraDirector.FightSafe
			local spacings = { (Config :: any).Separation or 2.6, 3.2, 4.5, Config.StartDistance, 9 }
			for _, dId in FIGHTERS do
				local pa, pb = idlePoints(aId), idlePoints(dId)
				for _, sep in spacings do
					local posA, posB = Vector3.new(-sep * 0.5, 0, 0), Vector3.new(sep * 0.5, 0, 0)
					local frameA = CFrame.lookAt(posA, posA + Vector3.xAxis)
					local frameB = CFrame.lookAt(posB, posB - Vector3.xAxis)
					local named: { any } = {}
					for _, n in pa do table.insert(named, { who = aId .. " " .. n.who, p = frameA:PointToWorldSpace(n.p) }) end
					for _, n in pb do table.insert(named, { who = dId .. " " .. n.who, p = frameB:PointToWorldSpace(n.p) }) end
					for slot = 1, 2 do
						local a, b = if slot == 1 then posA else posB, if slot == 1 then posB else posA
						local side = Vector3.new(0, 0, if slot == 1 then -1 else 1)
						local plan = CameraDirector._plan(a, b, "Fight", 0, 1 / 60, side, 0, false, nil)
						local camCF = CFrame.lookAt(plan.position, plan.focus)
						for _, aspect in { 16 / 9, 4 / 3 } do
							for _, n in named do
								local v = CameraDirector._normalizedViewportPoint(camCF, plan.fov, aspect, n.p)
								if not inside(v, safe) and #lines < 12 then
									table.insert(lines, string.format("vs %s spacing %.1f slot %d %.2f: %s at %s", dId, sep, slot, aspect, n.who, if v then string.format("(%.3f, %.3f)", v.X, v.Y) else "behind"))
								end
							end
						end
					end
				end
			end
			expect.truthy(#lines == 0, "outside the fight picture:\n  " .. table.concat(lines, "\n  "))
			if aId == "Nia" then
				QA.destroy(rigs)
				rigs = nil
				table.clear(idleCache)
			end
		end)
	end

	test("the headroom fit puts a tall pose and a throw's close orbit inside the fight picture", function()
		local safe = CameraDirector.FightSafe
		local function body(x: number, top: number): { Vector3 }
			return { Vector3.new(x, 0, 0.3), Vector3.new(x, 0, -0.3), Vector3.new(x + 0.2, top, 0) }
		end
		local cases = {
			{ name = "a 7.6-stud jump pose at the start distance", a = Vector3.new(-3.1, 0, 0), b = Vector3.new(3.1, 0, 0), points = { body(-3.1, 6.8), body(3.1, 7.6) }, throw = false },
			{ name = "a throw at point-blank, both upright", a = Vector3.new(-1.3, 0, 0), b = Vector3.new(1.3, 0, 0), points = { body(-1.3, 6.8), body(1.3, 6.8) }, throw = true },
		}
		for _, c in cases do
			local pts: { Vector3 } = {}
			for _, list in c.points do for _, p in list do table.insert(pts, p) end end
			local plan = CameraDirector._plan(c.a, c.b, "Fight", 0, 1 / 60, Vector3.new(0, 0, -1), 0, c.throw, nil)
			local pos, fov, look = CameraDirector._fitShot(plan.position, plan.focus, plan.fov, pts, 16 / 9, { safe = safe, maxFov = CameraDirector.FightFitMaxFov })
			expect.truthy(fov <= CameraDirector.FightFitMaxFov + 1e-3, string.format("%s: lens %.1f deg", c.name, fov))
			local camCF = CFrame.lookAt(pos, look)
			for _, p in pts do
				local v = CameraDirector._normalizedViewportPoint(camCF, fov, 16 / 9, p)
				expect.truthy(inside(v, safe), string.format("%s: point %s at %s", c.name, tostring(p), if v then string.format("(%.3f, %.3f)", v.X, v.Y) else "behind"))
			end
			-- A framing that already fits is left alone.
			local again, fov2, look2 = CameraDirector._fitShot(pos, look, fov, pts, 16 / 9, { safe = safe, maxFov = CameraDirector.FightFitMaxFov })
			expect.truthy((again - pos).Magnitude < 1e-3 and math.abs(fov2 - fov) < 0.05 and (look2 - look).Magnitude < 0.02, c.name .. ": a fitted shot is stable")
		end
	end)
end
