--!strict
-- Arena: Summit Observatory (south-south-east). A snow-dusted rock outcrop raised above the plaza: a polished marble
-- fight floor with an ice-blue edge line inside a steel handrail with a frost LED strip, pines and prayer flags,
-- the observatory dome behind, and the snowy peaks beyond (terrain).
local Kit = require(script.Parent.Parent.Kit)
local Props = require(script.Parent.Parent.Props)
local ArenaKit = require(script.Parent.Parent.ArenaKit)
local Layout = require(script.Parent.Parent.Layout)

local Arena = {}

local M = Enum.Material

local C = {
	rock = Color3.fromRGB(112, 110, 108),
	rockDark = Color3.fromRGB(84, 84, 86),
	slate = Color3.fromRGB(150, 158, 170),
	slateDark = Color3.fromRGB(72, 78, 90),
	marble = Color3.fromRGB(226, 232, 240),
	ice = Color3.fromRGB(120, 208, 255),
	steel = Color3.fromRGB(200, 206, 216),
	steelDark = Color3.fromRGB(70, 76, 86),
	snow = Color3.fromRGB(238, 244, 252),
	dome = Color3.fromRGB(230, 234, 240),
	warm = Color3.fromRGB(255, 214, 160),
	flags = { Color3.fromRGB(60, 120, 220), Color3.fromRGB(240, 240, 240), Color3.fromRGB(220, 60, 50), Color3.fromRGB(60, 170, 90), Color3.fromRGB(250, 200, 60) },
}

local function outcrop(model: Model, def: Layout.ArenaDef, rng: Random)
	local crag = Kit.model(model, "Outcrop")
	local R = Layout.STAGE_RADIUS
	-- boulders strewn round the back of the podium wall (the sides stay clear: the walkways between the stages pass
	-- there; and every boulder stays outside the flat fight floor's radius), snow drifts on the ground around it
	for a = 100, 260, 16 do
		local d = Layout.around(def, a + rng:NextNumber(-4, 4))
		local p = def.origin + d * (R + 4)
		local s = rng:NextNumber(4, 5.6)
		Props.rock(crag, Vector3.new(p.X, rng:NextNumber(0.8, 2.2), p.Z), Vector3.new(s * 1.3, s * 0.8, s), rng, Kit.mix(C.rock, C.rockDark, rng:NextNumber()), M.Rock)
		Kit.keepOut(Vector3.new(p.X, 0, p.Z), s * 0.65)
	end
	for a = 106, 254, 29 do
		local d = Layout.around(def, a + rng:NextNumber(-8, 8))
		local p = def.origin + d * (R + rng:NextNumber(4, 7))
		Kit.blob(crag, CFrame.new(p.X, 0.15, p.Z) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), Vector3.new(rng:NextNumber(7, 11), 1.4, rng:NextNumber(5, 8)), M.Snow, C.snow, { Name = "SnowDrift" })
	end
	-- snow ground round the outcrop (a flat disc a hair above the district floor; see Layout.GROUND_SHIFT), marked
	-- walk-over: PathfindingService would treat its hair-thin rim as a ledge and pinch the walkways beside the stage
	local field = Kit.cylinder(crag, Vector3.new(def.origin.X, -0.2, def.origin.Z) - def.inward * Layout.GROUND_SHIFT, 0.44, (R + Layout.GROUND_MARGIN) * 2, M.Snow, C.snow, { Name = "SnowField", CastShadow = false })
	Kit.passThrough(field)
	-- pines round the back and sides
	local pines = Kit.model(model, "Pines")
	for i = 1, 20 do
		local a = 100 + (i - 1) * (160 / 19) + rng:NextNumber(-3, 3)
		local d = Layout.around(def, a)
		local r = rng:NextNumber(R + 7, R + 15)
		-- pines yield to the district edge, the pockets, the board and the observatory: further out, else left out
		for _, extra in { 0, 4, 8 } do
			local p = def.origin + d * (r + extra)
			local foot = Vector3.new(p.X, 0, p.Z)
			if Kit.clearSpot(foot, 1.6) then
				Kit.keepOut(foot, 1.6)
				Props.pine(pines, foot, rng:NextNumber(1.1, 1.6), rng, true)
				break
			end
		end
		Kit.step()
	end
end

local function observatoryCentre(def: Layout.ArenaDef): Vector3
	-- behind the outcrop and to one side of the status board (57.7 out, 29.5 to the right)
	local c = def.origin - def.inward * 57.7 + def.right * 29.5
	return Vector3.new(c.X, 0, c.Z)
end

local function observatory(model: Model, def: Layout.ArenaDef, rng: Random)
	local obs = Kit.model(model, "Observatory")
	local c = observatoryCentre(def)
	Kit.cylinder(obs, c + Vector3.new(0, 2, 0), 8, 30, M.Rock, C.rockDark, { Name = "Plinth" })
	Kit.cylinder(obs, c + Vector3.new(0, 6.2, 0), 0.5, 30.6, M.Snow, C.snow, { Name = "PlinthSnow", CanCollide = false })
	Kit.cylinder(obs, c + Vector3.new(0, 11, 0), 9.6, 22, M.Concrete, C.dome, { Name = "Drum" })
	Kit.cylinder(obs, c + Vector3.new(0, 16, 0), 0.6, 22.8, M.Metal, C.steelDark, { Name = "DrumRing", CanCollide = false })
	local dome = Kit.ball(obs, c + Vector3.new(0, 16.2, 0), 21.4, M.Metal, C.dome, { Name = "Dome", CanCollide = false })
	local _ = dome
	-- the open slit and the telescope pointing up towards the north-west sky
	local toward = (Vector3.new(def.origin.X, 0, def.origin.Z) - c).Unit
	local slitCf = CFrame.lookAt(c + Vector3.new(0, 22, 0), c + Vector3.new(0, 22, 0) + toward) * CFrame.Angles(math.rad(-38), 0, 0)
	Kit.deco(obs, slitCf * CFrame.new(0, 0, -6.6), Vector3.new(3.6, 0.4, 10), M.Metal, Color3.fromRGB(26, 28, 34), { Name = "Slit" })
	Kit.cylinder(obs, slitCf * CFrame.new(0, 0.6, -10) * CFrame.Angles(math.rad(90), 0, 0), 9, 2.2, M.Metal, Color3.fromRGB(220, 224, 232), { Name = "Telescope", CanCollide = false })
	-- warm windows round the drum and a door facing the arena
	for i = 0, 7 do
		local a = i * math.pi / 4 + 0.2
		local d = Vector3.new(math.sin(a), 0, -math.cos(a))
		local p = c + d * 11.05 + Vector3.new(0, 11, 0)
		Kit.glow(obs, CFrame.lookAt(p, p + d), Vector3.new(2.2, 2.6, 0.1), C.warm, { Name = "Window", Transparency = 0.25 })
	end
	local door = c + toward * 11.1 + Vector3.new(0, 8.6, 0)
	Kit.deco(obs, CFrame.lookAt(door, door + toward), Vector3.new(3, 5, 0.2), M.Wood, Color3.fromRGB(96, 70, 52), { Name = "Door" })
	local lamp = Kit.glow(obs, CFrame.lookAt(door + Vector3.new(0, 3.2, 0.3), door + Vector3.new(0, 3.2, 0.3) + toward), Vector3.new(0.5, 0.5, 0.5), C.warm, { Name = "DoorLamp" })
	Kit.point(lamp, C.warm, 1.2, 14, false)
	-- radio mast with a red beacon beside the dome
	local mast = c + Vector3.new(13, 6, -4)
	Kit.cylinder(obs, mast + Vector3.new(0, 10, 0), 20, 0.5, M.Metal, C.steelDark, { CanCollide = false })
	for k = 1, 4 do
		Kit.block(obs, CFrame.new(mast + Vector3.new(0, 4 + k * 3.5, 0)), Vector3.new(3.2 - k * 0.5, 0.2, 0.2), M.Metal, C.steelDark, { CanCollide = false })
	end
	local red = Kit.glow(obs, CFrame.new(mast + Vector3.new(0, 20.4, 0)), Vector3.new(0.9, 0.9, 0.9), Color3.fromRGB(255, 40, 40), { Name = "AirBeacon" })
	Kit.tag(red, Kit.TAG_BLINK)
	red:SetAttribute("Period", 1.5)
	local _r = rng
end

local function prayerFlags(model: Model, def: Layout.ArenaDef)
	local flags = Kit.model(model, "PrayerFlags")
	-- three tall poles standing on the rocks just behind the podium, so the strings stay outside the fight floor
	local poleTop = def.floorY - Layout.APRON_DROP + 11
	local poles: { Vector3 } = {}
	for _, a in { 118, 180, -118 } do
		local d = Layout.around(def, a)
		local p = def.origin + d * (Layout.STAGE_RADIUS + 3.5)
		local foot = Vector3.new(p.X, 0, p.Z)
		Kit.cylinder(flags, foot + Vector3.new(0, poleTop / 2, 0), poleTop, 0.36, M.Wood, Color3.fromRGB(110, 84, 60), { Name = "FlagPole" })
		Kit.ball(flags, foot + Vector3.new(0, poleTop + 0.2, 0), 0.6, M.Metal, Color3.fromRGB(220, 190, 110), { CanCollide = false })
		table.insert(poles, foot + Vector3.new(0, poleTop - 0.4, 0))
	end
	for i = 1, #poles - 1 do
		Props.bunting(flags, poles[i], poles[i + 1], 12, C.flags, 1.8)
	end
end

function Arena.build(def: Layout.ArenaDef): Model
	local model = ArenaKit.new(def)
	local rng = Kit.rng(4)
	-- the observatory plinth (30 across) is claimed before any pine is placed
	Kit.keepOut(observatoryCentre(def), 16)
	ArenaKit.stage(model, def, {
		podiumMaterial = M.Rock,
		podiumColor = C.rock,
		rimMaterial = M.Slate,
		rimColor = C.slateDark,
		apronMaterial = M.Slate,
		apronColor = C.slate,
		bandMaterial = M.Granite,
		bandColor = Color3.fromRGB(64, 70, 84),
		lineColor = C.ice,
		floorMaterial = M.Marble,
		floorColor = C.marble,
		stairMaterial = M.Slate,
		stairColor = Color3.fromRGB(128, 134, 146),
		stairNose = C.ice,
		cheekMaterial = M.Rock,
		cheekColor = C.rockDark,
	})
	ArenaKit.parapet(model, def, 45, 315, 1.0, M.Slate, C.slateDark, C.snow, M.Snow)
	ArenaKit.barrier(model, def, {
		posts = 20,
		post = function(parent: Instance, base: Vector3, _out: Vector3, _i: number)
			Kit.cylinder(parent, base + Vector3.new(0, 1.8, 0), 3.6, 0.28, M.Metal, C.steel, { Name = "EdgePost" })
			Kit.ball(parent, base + Vector3.new(0, 3.62, 0), 0.38, M.Metal, C.steel, { Name = "EdgePostCap", CanCollide = false })
			Kit.cylinder(parent, base + Vector3.new(0, 0.1, 0), 0.2, 0.7, M.Metal, C.steelDark, { Name = "EdgePostFoot", CanCollide = false })
		end,
		rails = {
			{ height = 2.0, diameter = 0.2, material = M.Metal, color = C.steel, name = "EdgeRailLow" },
			{ height = 3.48, diameter = 0.22, material = M.Metal, color = C.steel, name = "EdgeRailTop" },
		},
		strip = { height = 3.28, color = C.ice, thickness = 0.1 },
	})
	ArenaKit.contractPieces(model, def)
	ArenaKit.gate(model, def, M.Slate, Color3.fromRGB(72, 78, 90), Color3.fromRGB(230, 244, 255))
	ArenaKit.paintFloor(model, def, {
		lineColor = Color3.fromRGB(90, 150, 210),
		rings = { { 9.5, 0.26, 0.2 }, { 12, 0.08, 0.5 } },
		emblem = "SUMMIT",
		emblemColor = Color3.fromRGB(90, 150, 210),
		emblemFont = Enum.Font.GothamBlack,
		emblemTransparency = 0.62,
		lightInfluence = 1,
	})
	outcrop(model, def, rng)
	prayerFlags(model, def)
	local lights = Kit.model(model, "StageLights")
	for _, a in { 132, 158, -158, -132 } do
		ArenaKit.stageLight(lights, def, a, Color3.fromRGB(222, 238, 255), 11, 1, C.steelDark)
	end
	observatory(model, def, rng)
	-- light snowfall over the stage (sparse, so the fight stays readable)
	local sky = Kit.deco(model, CFrame.new(def.origin + Vector3.new(0, 26, 0)), Vector3.new(70, 1, 70), M.SmoothPlastic, C.snow, { Name = "SnowCloud", Transparency = 1 })
	Kit.emitter(sky, {
		Name = "Snowfall",
		Color = Kit.colors(Color3.new(1, 1, 1)),
		LightInfluence = 1,
		LightEmission = 0.2,
		Size = Kit.numbers(0.22, 0.16),
		Transparency = Kit.numbers(0.1, 0.25, 1),
		Lifetime = NumberRange.new(7, 9),
		Rate = 22,
		Speed = NumberRange.new(2.4, 3.4),
		SpreadAngle = Vector2.new(18, 18),
		Acceleration = Vector3.new(0.6, 0, 0.3),
		EmissionDirection = Enum.NormalId.Bottom,
		Shape = Enum.ParticleEmitterShape.Box,
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
	})
	-- status board on a steel frame among the rocks behind the outcrop
	ArenaKit.statusBoard(model, def, 14, C.steelDark, M.Metal, -3, nil)
	return model
end

return Arena
