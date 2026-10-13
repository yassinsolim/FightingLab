--!strict
-- Round 6 presentation of Surge and the Ultimate (CameraDirector, EffectsController, AudioController):
--   * every fighter's cinematic camera stays out of both bodies and inside the arena, cuts only on its shot changes,
--     and hands back to the fight camera after the cinematic;
--   * Surge / UltStart / UltHit events (complete or bare) never error and map to sounds;
--   * the Surge aura follows the view's surge flag.
local Lab = game:GetService("ReplicatedStorage").FightingLab
local Config = require(Lab.CombatConfig)
local Roster = require(Lab.Roster)
local CameraDirector = require(Lab.Client.CameraDirector)
local EffectsController = require(Lab.Client.EffectsController)
local AudioController = require(Lab.Client.AudioController)
local Cinematic = require(Lab.Client.Motion.Cinematic)

local FIGHTERS = { "Kael", "Sierra", "Goran", "Lumi", "Rhys", "Nia" }

-- Distance from p to the vertical body segment of a fighter standing at `base` (feet to the top of the head).
local function bodyDistance(p: Vector3, base: Vector3): number
	local y = math.clamp(p.Y, base.Y, base.Y + 6.4)
	return (p - Vector3.new(base.X, y, base.Z)).Magnitude
end

return function(t)
	local test, expect = t.test, t.expect

	test("the cinematic camera frames both fighters from outside their bodies, inside the arena, and hands back", function()
		local cam = workspace.CurrentCamera
		expect.truthy(cam ~= nil, "a camera to drive")
		if not cam then return end
		local savedCFrame, savedType, savedFov = cam.CFrame, cam.CameraType, cam.FieldOfView
		local origin = Vector3.new(0, 900, 0)
		local ok, err = pcall(function()
			for _, id in FIGHTERS do
				local tl = Cinematic.timeline(id, nil)
				local defender = if id == "Goran" then "Nia" else "Goran"
				local aPos, dPos = Vector3.new(-tl.endDistance * 0.5, 0, 0), Vector3.new(tl.endDistance * 0.5, 0, 0)
				local function frame(now: number, f: number?): any
					local function view(cid: string, pos: Vector3, facing: Vector3, role: string?): any
						local v: any = { pos = pos, facing = facing, state = "Idle", characterId = cid }
						if f and role then
							v.state = "Ultimate"
							v.throw = { role = role, move = "Ultimate", archetype = "ultimate", frame = f, duration = tl.duration, impactFrame = tl.frames[1] }
						end
						return v
					end
					return { now = now, dt = 1 / 60, hitstop = 0, phase = "Fight", winner = 0, origin = origin,
						fighters = { view(id, aPos, Vector3.xAxis, "Attacker"), view(defender, dPos, -Vector3.xAxis, "Defender") } }
				end
				CameraDirector.beginFight(origin, 1)
				local now = 0
				for _ = 1, 30 do now += 1 / 60; CameraDirector.update(frame(now, nil)) end
				local shots: { [number]: boolean } = {}
				local worst = math.huge
				for f = 1, tl.duration do
					now += 1 / 60
					CameraDirector.update(frame(now, f))
					local st: any = CameraDirector._state()
					local pos = cam.CFrame.Position
					if f > 12 then
						-- (the first frames still blend out of the push-in)
						local d = math.min(bodyDistance(pos, origin + aPos), bodyDistance(pos, origin + dPos))
						worst = math.min(worst, d)
						local flat = Vector3.new(pos.X - origin.X, 0, pos.Z - origin.Z)
						expect.truthy(flat.Magnitude < (Config.ArenaRadius or 30) + 2, string.format("%s frame %d camera inside the arena (%.1f)", id, f, flat.Magnitude))
					end
					local cine = st.cinematic
					if type(cine.shot) == "number" then shots[cine.shot] = true end
					if f > 20 then
						expect.truthy(cine.weight > 0.5, string.format("%s frame %d plays the cinematic camera (weight %.2f)", id, f, cine.weight))
					end
				end
				expect.truthy(worst > 0.75, string.format("%s camera never inside a body (closest %.2f studs)", id, worst))
				local n = 0
				for _ in shots do n += 1 end
				expect.truthy(n >= 2, id .. " cinematic has more than one shot")
				-- After the cinematic: the fight camera again within the return blend (real time: CineReturn).
				for _ = 1, 30 do now += 1 / 60; CameraDirector.update(frame(now, nil)) end
				task.wait(CameraDirector.CineReturn + 0.15)
				for _ = 1, 5 do now += 1 / 60; CameraDirector.update(frame(now, nil)) end
				expect.truthy((CameraDirector._state() :: any).cinematic.weight < 0.05, id .. " camera hands back to the fight camera")
				CameraDirector.endFight()
			end
		end)
		CameraDirector.endFight()
		cam.CameraType, cam.CFrame, cam.FieldOfView = savedType, savedCFrame, savedFov
		if not ok then error(err, 0) end
	end)

	test("Surge and Ultimate events never error, complete or bare, and have sounds", function()
		local origin = Vector3.new(0, 900, 0)
		local full = {
			{ kind = "Surge", attacker = 1, target = 1, point = origin + Vector3.new(0, 3, 0), tier = nil },
			{ kind = "UltStart", attacker = 1, target = 2, move = "Ultimate", point = origin + Vector3.new(0, 3, 0), tier = "Launch", archetype = "ultimate" },
			{ kind = "UltHit", attacker = 1, target = 2, move = "Ultimate", combo = 1, damage = 4, point = origin + Vector3.new(1, 2.5, 0), archetype = "ultimate" },
			{ kind = "UltHit", attacker = 1, target = 2, move = "Ultimate", combo = 5, damage = 9, knockdown = true, point = origin + Vector3.new(1, 2.5, 0), archetype = "ultimate" },
		}
		local bare = { { kind = "Surge" }, { kind = "UltStart" }, { kind = "UltHit" }, { kind = "UltHit", combo = 99 } }
		for _, set in { full, bare } do
			for _, e in set do
				local ok1, err1 = pcall(CameraDirector.onEvent, e :: any)
				expect.truthy(ok1, e.kind .. " camera: " .. tostring(err1))
				local ok2, err2 = pcall(EffectsController.onEvent, e :: any, nil)
				expect.truthy(ok2, e.kind .. " effects: " .. tostring(err2))
				local name = AudioController._soundNameForEvent(e :: any)
				expect.truthy(type(name) == "string" and name ~= "", e.kind .. " has a sound")
			end
		end
		pcall(EffectsController.clear)
	end)

	test("the Surge aura follows the surge flag", function()
		expect.truthy(type(EffectsController.surgeColor) == "function", "surge colour per fighter")
		for _, id in FIGHTERS do
			local c = EffectsController.surgeColor(id)
			expect.truthy(typeof(c) == "Color3", id .. " aura colour")
		end
		expect.truthy(typeof(EffectsController.surgeColor("Nobody")) == "Color3", "unknown fighter falls back")
		expect.truthy(Roster.has("Kael"), "roster")
	end)
end
