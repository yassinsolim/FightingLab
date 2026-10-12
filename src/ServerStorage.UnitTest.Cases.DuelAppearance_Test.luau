--!strict
-- Anti "naked flash" handshake: the server publishes a dressed character's accessory/wrap-layer counts and every
-- client keeps new characters (and fresh HUD portrait clones) hidden until those arrived and their assets loaded.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Lab = ReplicatedStorage:WaitForChild("FightingLab")
local NetProtocol = require(Lab:WaitForChild("NetProtocol"))
local AvatarGate = require(Lab:WaitForChild("Client"):WaitForChild("AvatarGate"))
local AvatarService = require(ServerStorage:WaitForChild("FightingLab"):WaitForChild("Duel"):WaitForChild("AvatarService"))

local function accessory(name: string, layered: boolean): Accessory
	local acc = Instance.new("Accessory")
	acc.Name = name
	-- Layered clothing lives on a MeshPart handle (a WrapLayer must be parented to a MeshPart).
	local handle: BasePart = if layered then Instance.new("MeshPart") else Instance.new("Part")
	handle.Name = "Handle"
	handle.Parent = acc
	if layered then
		local wrap = Instance.new("WrapLayer")
		wrap.Parent = handle
	end
	return acc
end

local function body(): (Model, BasePart, Decal)
	local model = Instance.new("Model")
	model.Name = "GateDummy"
	local torso = Instance.new("Part")
	torso.Name = "UpperTorso"
	torso.Parent = model
	local face = Instance.new("Decal")
	face.Parent = torso
	return model, torso, face
end

return function(t)
	t.test("appearance counts are published by the server after dressing", function()
		local model = body()
		accessory("Hair", false).Parent = model
		accessory("Jacket", true).Parent = model
		accessory("Pants", true).Parent = model
		local accessories, wraps = NetProtocol.appearanceCounts(model)
		t.expect.equal(accessories, 3)
		t.expect.equal(wraps, 2)
		t.expect.equal(NetProtocol.expectedAppearance(model), nil, "unknown until published")
		AvatarService.publishAppearance(model)
		local wantA, wantW = NetProtocol.expectedAppearance(model)
		t.expect.equal(wantA, 3)
		t.expect.equal(wantW, 2)
		model:Destroy()
	end)

	t.test("gate rule: items, then one preload, then settle; capped", function()
		local s: AvatarGate.State = {
			elapsed = 0.1, maxSeconds = 3, minSeconds = 0, settleSeconds = 0.2, needExpected = true,
			accessories = 0, wrapLayers = 0, wantAccessories = nil, wantWrapLayers = nil, preload = "none", sincePreload = 0,
		}
		t.expect.equal(AvatarGate.decide(s), "wait", "server counts not known yet")
		s.wantAccessories, s.wantWrapLayers = 4, 2
		t.expect.equal(AvatarGate.decide(s), "wait", "accessories not replicated yet")
		s.accessories, s.wrapLayers = 4, 1
		t.expect.equal(AvatarGate.decide(s), "wait", "a wrap layer is still missing")
		s.wrapLayers = 2
		t.expect.equal(AvatarGate.decide(s), "preload")
		s.preload = "running"
		t.expect.equal(AvatarGate.decide(s), "wait")
		s.preload, s.sincePreload = "done", 0.05
		t.expect.equal(AvatarGate.decide(s), "wait", "settling")
		s.sincePreload = 0.25
		t.expect.equal(AvatarGate.decide(s), "release")
		s.accessories, s.elapsed = 0, 3
		t.expect.equal(AvatarGate.decide(s), "timeout", "never longer than the cap")
	end)

	t.test("a character stays hidden until late accessories arrive and its preload ends", function()
		local model, torso, face = body()
		model.Parent = workspace
		local now = 0
		local preloads: { { Instance } } = {}
		local resume: (() -> ())? = nil
		local gate = AvatarGate.gateCharacter(model, {
			manual = true, clock = function() return now end,
			preload = function(list)
				table.insert(preloads, list)
				local co = coroutine.running()
				resume = function() task.spawn(co) end
				coroutine.yield()
			end,
		})
		local ok, err = pcall(function()
			t.expect.equal(torso.LocalTransparencyModifier, 1, "hidden on arrival")
			t.expect.equal((face :: any).LocalTransparencyModifier, 1)
			t.expect.truthy(AvatarGate.isGated(model))
			now = 0.05
			t.expect.falsy(gate:poll(now), "no server counts yet")
			-- The dressed items replicate after the model (measured: 0.10-0.12 s later), then the counts.
			local hair = accessory("Hair", false)
			hair.Parent = model
			accessory("Shirt", true).Parent = model
			AvatarService.publishAppearance(model)
			local late = accessory("Belt", false)
			model:SetAttribute(NetProtocol.AccessoryCountAttribute, 3)
			now = 0.12
			t.expect.falsy(gate:poll(now), "one accessory still missing")
			t.expect.equal(#preloads, 0)
			late.Parent = model
			now = 0.13
			t.expect.falsy(gate:poll(now))
			t.expect.equal(#preloads, 1, "preload starts once everything is there")
			t.expect.truthy(#preloads[1] > 4, "preloads the whole character")
			t.expect.equal((hair:FindFirstChild("Handle") :: BasePart).LocalTransparencyModifier, 1, "late parts are hidden too")
			torso.LocalTransparencyModifier = 0 -- e.g. the camera's transparency controller
			now = 0.3
			t.expect.falsy(gate:poll(now), "preload still running")
			t.expect.equal(torso.LocalTransparencyModifier, 1, "re-hidden every poll")
			assert(resume, "preload yielded")
			resume()
			now = 0.35
			t.expect.falsy(gate:poll(now), "settling after the preload")
			now = 0.7
			t.expect.truthy(gate:poll(now))
			t.expect.equal(torso.LocalTransparencyModifier, 0, "shown")
			t.expect.equal((face :: any).LocalTransparencyModifier, 0)
			t.expect.equal(gate.reason, "release")
			t.expect.falsy(AvatarGate.isGated(model))
			t.expect.equal(#preloads, 1)
		end)
		model:Destroy()
		if not ok then error(err, 0) end
	end)

	t.test("the gate never holds a character longer than the cap, and forgets removed ones", function()
		local model, torso = body()
		model.Parent = workspace
		local now = 0
		local gate = AvatarGate.gateCharacter(model, { manual = true, clock = function() return now end, preload = function() end })
		model:SetAttribute(NetProtocol.AccessoryCountAttribute, 5) -- items that never arrive
		now = 2.9
		t.expect.falsy(gate:poll(now))
		t.expect.equal(torso.LocalTransparencyModifier, 1)
		now = AvatarGate.MaxSeconds
		t.expect.truthy(gate:poll(now))
		t.expect.equal(gate.reason, "timeout")
		t.expect.equal(torso.LocalTransparencyModifier, 0)
		local other, otherTorso = body()
		other.Parent = workspace
		local shown = false
		local g2 = AvatarGate.track(other, {
			manual = true, clock = function() return now end, preload = function() end,
			hide = AvatarGate.hideCharacter, show = function() shown = true end,
		})
		other:Destroy()
		t.expect.truthy(g2:poll(now))
		t.expect.equal(g2.reason, "removed")
		t.expect.falsy(shown, "removed models are never shown")
		t.expect.equal(otherTorso.LocalTransparencyModifier, 1)
		model:Destroy()
	end)

	t.test("HUD portraits: new clones stay hidden until ready and are reused, never re-cloned", function()
		local templates = Lab:FindFirstChild("Characters")
		if not (templates and templates:FindFirstChild("Kael") and templates:FindFirstChild("Sierra")) then return end
		local Hud = require(Lab.Client.HudController)
		local gui = Instance.new("ScreenGui")
		Hud.init({ gui = gui, modules = { Characters = { posePreview = function() end, getModel = function() return nil end } } })
		Hud.setViewSlot(1)
		local ok, err = pcall(function()
			local portrait = gui:FindFirstChild("Portrait", true) :: ViewportFrame
			local world = portrait:FindFirstChild("World") :: WorldModel
			local function info(id: string): any
				return { displayName = id, color = Color3.new(1, 1, 1), characterId = id, maxHealth = 100 }
			end
			Hud.setFighterInfo(1, info("Kael"))
			t.expect.equal(#world:GetChildren(), 1)
			t.expect.equal(portrait.ImageTransparency, 1, "hidden until its assets are loaded")
			AvatarGate.step(os.clock() + AvatarGate.MaxSeconds + 1)
			t.expect.equal(portrait.ImageTransparency, 0, "shown once the gate opens")
			local kael = world:GetChildren()[1] :: Model
			local kaelPivot = kael:GetPivot()
			Hud.setFighterInfo(1, info("Sierra"))
			t.expect.equal(#world:GetChildren(), 2)
			t.expect.equal(portrait.ImageTransparency, 1, "a new fighter's clone is gated too")
			t.expect.truthy(kael:GetPivot().Position.Y < -100, "the previous clone is parked, not destroyed")
			AvatarGate.step(os.clock() + AvatarGate.MaxSeconds + 1)
			Hud.setFighterInfo(1, info("Kael"))
			t.expect.equal(#world:GetChildren(), 2, "same fighter again: no new clone")
			t.expect.equal(world:GetChildren()[1], kael)
			t.expect.truthy((kael:GetPivot().Position - kaelPivot.Position).Magnitude < 0.01, "reused at its framed pose")
			t.expect.equal(portrait.ImageTransparency, 0, "a ready clone shows immediately")
			for _ = 1, 3 do Hud.setFighterInfo(1, info("Kael")) end
			t.expect.equal(#world:GetChildren(), 2, "repeated info never rebuilds the portrait")
		end)
		gui:Destroy()
		if not ok then error(err, 0) end
	end)
end
