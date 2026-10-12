--!strict
-- Round 5: the preview / avatar flash detector. A watched fighter model may only be visible while it is complete (every
-- authored accessory, wrap layer and rigid welded extra present, every mesh fetched, no texture mid-fetch); a joint that
-- turns more than JUMP_DEGREES between two visible frames is a pose pop. The detector itself is checked on fake models,
-- then run over the real fighter-select tile portraits: a clone uncovered while it loads is caught as bare frames, and
-- the preview gate keeps every tile covered until its clone is complete (0 bare frames).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lab = ReplicatedStorage:WaitForChild("FightingLab")
local Client = Lab:WaitForChild("Client")
local FlashDetector = require(Client:WaitForChild("FlashDetector"))
local AvatarGate = require(Client:WaitForChild("AvatarGate"))
local FighterSelect = require(Client:WaitForChild("FighterSelect"))
local Roster = require(Lab:WaitForChild("Roster"))

local function part(name: string, parent: Instance, mesh: string?): BasePart
	local p: BasePart = Instance.new("Part")
	p.Name = name
	if mesh then
		-- Scripts cannot set MeshPart.MeshId; a SpecialMesh carries the same kind of mesh id for the detector.
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType.FileMesh
		m.MeshId = mesh
		m.Parent = p
	end
	p.Parent = parent
	return p
end

-- A tiny rig: torso + arm joined by a Motor6D, one accessory with a layered wrap, one rigid glove, a shirt and a face.
local function rig(): (Model, Motor6D)
	local model = Instance.new("Model")
	model.Name = "Preview_Kael_9"
	local torso = part("UpperTorso", model)
	local arm = part("RightUpperArm", model)
	local motor = Instance.new("Motor6D")
	motor.Name = "RightShoulder"; motor.Part0 = torso; motor.Part1 = arm; motor.Parent = arm
	local acc = Instance.new("Accessory"); acc.Parent = model
	-- Layered clothing lives on a MeshPart handle (a WrapLayer must be parented to a MeshPart).
	local handle = Instance.new("MeshPart"); handle.Name = "Handle"; handle.Parent = acc
	local wrap = Instance.new("WrapLayer"); wrap.Parent = handle
	part("Brim", acc, "rbxassetid://111")
	local glove = part("RightGlove", arm, "rbxassetid://222")
	glove:SetAttribute(FlashDetector.EXTRA_ATTRIBUTE, true)
	local shirt = Instance.new("Shirt"); shirt.ShirtTemplate = "rbxassetid://333"; shirt.Parent = model
	local face = Instance.new("Decal"); face.Texture = "rbxassetid://444"; face.Parent = torso
	return model, motor
end

return function(t)
	t.test("inventory and content ids cover accessories, wrap layers, rigid gear, clothing, meshes and textures", function()
		local model = rig()
		local inv = FlashDetector.inventory(model)
		t.expect.equal(inv.accessories, 1)
		t.expect.equal(inv.wrapLayers, 1)
		t.expect.equal(inv.extras, 1, "the welded glove")
		t.expect.equal(inv.clothing, 1)
		local meshes, textures = FlashDetector.contentIds(model)
		t.expect.truthy(table.find(meshes, "rbxassetid://111") ~= nil and table.find(meshes, "rbxassetid://222") ~= nil, "accessory and gear meshes")
		t.expect.truthy(table.find(textures, "rbxassetid://333") ~= nil and table.find(textures, "rbxassetid://444") ~= nil, "shirt and face")
		t.expect.equal(FlashDetector.fighterIdOf(model), "Kael")
		model:Destroy()
	end)

	t.test("check: a missing item, an unfetched mesh or a texture mid-fetch make a model incomplete", function()
		local model = rig()
		local want = FlashDetector.inventory(model)
		local status: { [string]: string } = {}
		local function fetch(id: string): string return status[id] or "Success" end
		t.expect.truthy(FlashDetector.check(model, want, fetch).complete, "everything there and fetched")
		status["rbxassetid://222"] = "Loading"
		local c = FlashDetector.check(model, want, fetch)
		t.expect.falsy(c.complete, "the glove mesh is still loading")
		t.expect.equal(c.loading[1], "rbxassetid://222")
		status["rbxassetid://222"] = "None"
		t.expect.falsy(FlashDetector.check(model, want, fetch).complete, "a mesh nobody fetched yet draws nothing")
		status["rbxassetid://222"] = nil
		status["rbxassetid://333"] = "None"
		t.expect.truthy(FlashDetector.check(model, want, fetch).complete, "a streamed texture (None) is not counted")
		status["rbxassetid://333"] = "Loading"
		t.expect.falsy(FlashDetector.check(model, want, fetch).complete, "a texture mid-fetch is")
		status["rbxassetid://333"] = "Failure"
		local failed = FlashDetector.check(model, want, fetch)
		t.expect.truthy(failed.complete, "a failed asset never finishes: reported, not waited for")
		t.expect.equal(#failed.failed, 1)
		status["rbxassetid://333"] = nil
		local glove = model:FindFirstChild("RightGlove", true) :: Instance
		glove.Parent = nil
		local missing = FlashDetector.check(model, want, fetch)
		t.expect.falsy(missing.complete)
		t.expect.equal(missing.missing[1], "extras 0/1")
		model:Destroy()
	end)

	t.test("preload list: instances plus unfinished textures only (no mesh id strings, nothing fetched twice)", function()
		local model = rig()
		local holder = Instance.new("Folder")
		model.Parent = holder
		local status: { [string]: string } = { ["rbxassetid://444"] = "Success" }
		FlashDetector._setFetchForTests(function(id: string) return status[id] or "None" end)
		local list: { any } = {}
		local ok, err = pcall(function()
			local pending = FlashDetector.pendingTextures(model)
			t.expect.equal(table.concat(pending, ","), "rbxassetid://333", "the face is fetched already; meshes never as strings")
			local gate = AvatarGate.track(model, {
				hide = function() end, show = function() end, manual = true, clock = function() return 0 end,
				preload = function(l: { any }) list = l end, contentReady = function() return false end,
			})
			gate:poll(0)
			task.wait()
			local strings = {}
			for _, item in list do
				if typeof(item) == "string" then table.insert(strings, item) end
			end
			t.expect.equal(table.concat(strings, ","), "rbxassetid://333", "the gate preloads the shirt texture by id, meshes through their instances")
			t.expect.truthy(table.find(list, model:FindFirstChild("Brim", true)) ~= nil, "the instances are preloaded")
			gate:release("removed")
		end)
		FlashDetector._setFetchForTests(nil)
		holder:Destroy()
		if not ok then error(err, 0) end
	end)

	t.test("recorder: bare frames only while visible, pose pops only between visible frames", function()
		local model, motor = rig()
		local want = FlashDetector.inventory(model)
		local loading = true
		local recorder = FlashDetector.newRecorder({ fetch = function(id: string) return if loading and id == "rbxassetid://111" then "Loading" else "Success" end })
		local visible = false
		local function frame() recorder.step({ { key = model, label = "test", model = model, visible = visible, expected = want } }) end
		for _ = 1, 5 do frame() end
		t.expect.equal(recorder.report.bareFrames, 0, "hidden while incomplete: fine")
		visible = true
		frame(); frame()
		t.expect.equal(recorder.report.bareFrames, 2, "visible while the accessory mesh loads: two bare frames")
		loading = false
		frame()
		t.expect.equal(recorder.report.bareFrames, 2)
		-- Smooth motion is fine, a jump is a pop.
		for i = 1, 5 do
			motor.Transform = CFrame.Angles(math.rad(i * 5), 0, 0)
			frame()
		end
		t.expect.equal(recorder.report.pops, 0, "5 degrees per frame is motion")
		motor.Transform = CFrame.Angles(math.rad(90), 0, 0)
		frame()
		t.expect.equal(recorder.report.pops, 1, "65 degrees in one frame is a pop")
		-- A jump while hidden (or on the first visible frame) is not a pop.
		visible = false
		frame()
		motor.Transform = CFrame.identity
		visible = true
		frame()
		t.expect.equal(recorder.report.pops, 1)
		t.expect.truthy(string.find(FlashDetector.summary(recorder.report), "bareFrames=2", 1, true) ~= nil)
		model:Destroy()
	end)

	t.test("preview gate: a template clone stays covered until it has every item of its template and its assets", function()
		local folder = Lab:FindFirstChild("Characters")
		local template = folder and folder:FindFirstChild("Kael")
		if not template then return end
		local inv = FlashDetector.templateInventory("Kael") :: FlashDetector.Inventory
		t.expect.truthy(inv ~= nil and inv.extras >= 1, "Kael's template wears rigid gear (round-4 rig)")
		local clone = template:Clone()
		local holder = Instance.new("WorldModel")
		clone.Parent = holder
		holder.Parent = workspace
		-- Take one glove off: the clone is incomplete.
		local glove: Instance? = nil
		for _, d in clone:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute(FlashDetector.EXTRA_ATTRIBUTE) == true then glove = d; break end
		end
		local gloveParent = (glove :: Instance).Parent
		;(glove :: Instance).Parent = nil
		local now = 0
		local ready = false
		local shown = 0
		local gate = AvatarGate.trackPreview(clone, "Kael", function() end, function() shown += 1 end, {
			manual = true, clock = function() return now end, preload = function() end, contentReady = function() return ready end,
		})
		local ok, err = pcall(function()
			now = 0.1
			t.expect.falsy(gate:poll(now), "a glove is missing")
			;(glove :: Instance).Parent = gloveParent
			now = 0.2
			t.expect.falsy(gate:poll(now), "all items: preload")
			now = 0.5
			t.expect.falsy(gate:poll(now), "assets not fetched yet")
			ready = true
			now = 0.6
			t.expect.falsy(gate:poll(now), "settling")
			now = 0.6 + AvatarGate.PreviewSettleSeconds + 0.01
			t.expect.truthy(gate:poll(now))
			t.expect.equal(shown, 1)
		end)
		holder:Destroy()
		if not ok then error(err, 0) end
	end)

	-- The fighter-select roster tiles, end to end on the server: the detector watches every tile's portrait clone.
	t.test("fighter select tiles: 0 bare frames while clones load (the detector catches an uncovered one)", function()
		local folder = Lab:FindFirstChild("Characters")
		if not (folder and folder:FindFirstChild("Kael")) or not FighterSelect.templatesReady() then return end
		local loading = true
		local function fetch(_id: string): string return if loading then "Loading" else "Success" end
		FlashDetector._setFetchForTests(fetch)
		AvatarGate._setPreloadForTests(function() end)
		local holder = Instance.new("Folder")
		local ctl = FighterSelect.mount({
			parent = holder, previews = true, live = false, canSelect = function() return true, nil end,
			currentFighter = function() return "Kael" end, onConfirm = function() end,
		})
		local ok, err = pcall(function()
			ctl.open("Kael")
			task.wait()
			local strip = holder:FindFirstChild("Roster", true) :: Frame
			t.expect.truthy(strip ~= nil, "roster strip built")
			local recorder = FlashDetector.newRecorder({ fetch = fetch })
			local function observe(): { any }
				local obs = {}
				for _, id in Roster.order do
					local tile = strip:FindFirstChild("Tile_" .. id) :: any
					local vp = tile and tile:FindFirstChild("Bust")
					local world = vp and vp:FindFirstChild("World")
					local model = world and world:FindFirstChildOfClass("Model")
					if model then
						local cover = tile.Cover
						local hidden = cover.Visible and cover.BackgroundTransparency <= 0.02
						table.insert(obs, { key = model, label = "tile:" .. id, model = model, visible = not hidden and vp.ImageTransparency < 0.98, expected = FlashDetector.templateInventory(id) })
					end
				end
				return obs
			end
			local base = os.clock()
			for i = 1, 12 do
				AvatarGate.step(base + i * 0.05)
				recorder.step(observe())
			end
			t.expect.equal(#observe(), #Roster.order, "every tile has its clone")
			t.expect.equal(recorder.report.bareFrames, 0, "covered while loading")
			-- What the old transparent cover did: the detector counts it.
			local kaelCover = (strip:FindFirstChild("Tile_Kael") :: any).Cover
			kaelCover.BackgroundTransparency = 1
			recorder.step(observe())
			t.expect.equal(recorder.report.bareFrames, 1, "an uncovered loading clone is a bare frame")
			kaelCover.BackgroundTransparency = 0
			-- Assets arrive: the gates open, the covers fade, nothing bare.
			loading = false
			for i = 1, 4 do AvatarGate.step(base + 0.6 + i * 0.15) end
			task.wait(0.4)
			for _ = 1, 5 do recorder.step(observe()) end
			local shownTiles = 0
			for _, o in observe() do if o.visible then shownTiles += 1 end end
			t.expect.equal(shownTiles, #Roster.order, "every portrait is shown once complete")
			t.expect.equal(recorder.report.bareFrames, 1, "no bare frame from the real reveal")
		end)
		FlashDetector._setFetchForTests(nil)
		AvatarGate._setPreloadForTests(nil)
		ctl.destroy()
		holder:Destroy()
		if not ok then error(err, 0) end
	end)
end
