--!strict
-- Round 6 follow-up: the lobby camera after a return. A fight, a practice or a quick travel puts the player on a return
-- point (an exit or the Arrival) facing the arena; the camera is then framed once over the player's shoulder, looking
-- at the arena from the plaza side (the default camera used to keep the fight camera's direction and could start
-- behind a lamp post).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Client = ReplicatedStorage:WaitForChild("FightingLab"):WaitForChild("Client")
local LobbyCamera = require(Client:WaitForChild("LobbyCamera"))

local function marker(name: string, cf: CFrame, parent: Instance): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CFrame = cf
	p.Parent = parent
	return p
end

return function(t)
	t.test("frameBehind looks over the shoulder: behind, above, toward the player's facing", function()
		local at = CFrame.lookAt(Vector3.new(10, 3, 20), Vector3.new(10, 3, -40))
		local cf = LobbyCamera.frameBehind(at)
		local back = cf.Position - at.Position
		t.expect.truthy(math.abs(Vector3.new(back.X, 0, back.Z).Magnitude - LobbyCamera.DISTANCE) < 1e-3, "at the default camera distance")
		t.expect.truthy(back.Z > 0 and math.abs(back.X) < 1e-3, "behind the player")
		t.expect.truthy(back.Y > 0, "above the player")
		t.expect.truthy(cf.LookVector:Dot(at.LookVector) > 0.9, "looking the way the player faces")
		t.expect.truthy(cf.LookVector.Y < 0, "slightly down")
		-- a tilted root is flattened
		local tilted = LobbyCamera.frameBehind(at * CFrame.Angles(math.rad(30), 0, 0))
		t.expect.truthy((tilted.Position - cf.Position).Magnitude < 1e-3)
	end)

	t.test("after a fight the camera is framed once, when the player stands on a return point", function()
		local folder = Instance.new("Folder")
		local exit = marker("ExitP1", CFrame.lookAt(Vector3.new(0, 0, 0), Vector3.new(0, 0, -50)), folder)
		local root = marker("Root", CFrame.new(40, 3, 40), folder)
		local cam = Instance.new("Camera")
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = CFrame.lookAt(Vector3.new(0, 10, 0), Vector3.new(30, 0, 30))
		cam.Parent = folder
		local tracker = LobbyCamera.new({ camera = function() return cam end, root = function() return root end, markers = function() return { exit } end })
		tracker.step("Lobby", 0)
		tracker.step("Lobby", 0.1)
		t.expect.equal(tracker.aimed(), 0, "nothing in the lobby by itself")
		tracker.step("Fight", 1)
		tracker.step("Results", 1.5)
		tracker.step("Lobby", 2)
		t.expect.truthy(tracker.pending(), "a return is pending")
		tracker.step("Lobby", 2.1)
		t.expect.equal(tracker.aimed(), 0, "the fight camera (Scriptable) still owns the view")
		cam.CameraType = Enum.CameraType.Custom
		tracker.step("Lobby", 2.2)
		t.expect.equal(tracker.aimed(), 0, "the player is not on the return point yet")
		root.CFrame = CFrame.new(1, 3, 1)
		tracker.step("Lobby", 2.3)
		t.expect.equal(tracker.aimed(), 1, "framed once the player stands on the exit")
		t.expect.truthy(cam.CFrame.LookVector:Dot(Vector3.new(0, 0, -1)) > 0.9, "looking at the arena (the exit's facing)")
		t.expect.truthy(cam.CFrame.Position.Z > root.Position.Z + 10, "from the plaza side, behind the player")
		local before = cam.CFrame
		tracker.step("Lobby", 2.4)
		t.expect.equal(tracker.aimed(), 1, "only once per return")
		t.expect.equal(cam.CFrame, before)
		-- a practice ends the same way; a return that never reaches a marker gives up
		tracker.step("Practice", 3)
		root.CFrame = CFrame.new(40, 3, 40)
		tracker.step("Lobby", 4)
		tracker.step("Lobby", 4 + LobbyCamera.WAIT_SECONDS + 0.1)
		t.expect.falsy(tracker.pending(), "gives up after WAIT_SECONDS")
		t.expect.equal(tracker.aimed(), 1)
		folder:Destroy()
	end)

	t.test("quick travel frames the arrival, a CPU match or practice start does not", function()
		local folder = Instance.new("Folder")
		local arrival = marker("Arrival", CFrame.lookAt(Vector3.new(50, 0, 0), Vector3.new(100, 0, 0)), folder)
		local root = marker("Root", CFrame.new(0, 3, 0), folder)
		local cam = Instance.new("Camera")
		cam.CameraType = Enum.CameraType.Custom
		cam.Parent = folder
		local tracker = LobbyCamera.new({ camera = function() return cam end, root = function() return root end, markers = function() return { arrival } end })
		tracker.onTeleport({ reason = "Cpu", delay = 0.4 }, 0)
		t.expect.falsy(tracker.pending(), "a CPU match goes straight into the fight camera")
		tracker.onTeleport({ reason = "Travel", arenaId = "Arena_X", delay = 0.4 }, 1)
		tracker.step("Lobby", 1.1)
		t.expect.equal(tracker.aimed(), 0, "waits for the move")
		root.CFrame = CFrame.new(51, 3, 1)
		tracker.step("Lobby", 1.5)
		t.expect.equal(tracker.aimed(), 1)
		t.expect.truthy(cam.CFrame.LookVector:Dot(Vector3.new(1, 0, 0)) > 0.9, "looking at the arena")
		folder:Destroy()
	end)

	t.test("markers: the world's exits and Arrival markers, nearest within the radius", function()
		local world = Instance.new("Folder")
		local arenas = Instance.new("Folder"); arenas.Name = "Arenas"; arenas.Parent = world
		local a = Instance.new("Model"); a.Name = "Arena_A"; a.Parent = arenas
		local e1 = marker("ExitP1", CFrame.new(0, 0, 0), a)
		marker("ExitP2", CFrame.new(6, 0, 0), a)
		marker("Arrival", CFrame.new(3, 0, -4), a)
		marker("PadP1", CFrame.new(-4, 0, -4), a)
		local list = LobbyCamera.worldMarkers(world)
		t.expect.equal(#list, 3, "exits and the Arrival, not pads")
		t.expect.equal(LobbyCamera.markerAt(list, Vector3.new(0.5, 3, 0.5)), e1)
		t.expect.equal(LobbyCamera.markerAt(list, Vector3.new(30, 3, 30)), nil)
		world:Destroy()
	end)
end
