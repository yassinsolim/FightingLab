--!strict
-- Lobby camera framing after a return (round 6). When a fight or a practice session ends, the server puts the player
-- on the arena's exit facing the ring, and the default camera would keep the fight camera's last direction, so the
-- view could start behind a lamp post or a sign. Quick travel (the PLAY panel's arenas) has the same problem after its
-- fade. Once the character stands on its return point, the camera is turned once to look over the player's shoulder
-- at the arena (from the open plaza side); the default camera then follows as usual (it keeps that direction and its
-- own zoom).
local Players = game:GetService("Players")

local M = {}

M.DISTANCE = 12.5 -- studs behind the player (the default camera's distance)
M.HEIGHT = 3.2 -- camera height above the root
M.LOOK_HEIGHT = 1.4 -- the point looked at: above the root, ahead of the player
M.LOOK_AHEAD = 6
M.WAIT_SECONDS = 2.5 -- give up when the character has not reached a return point by then
M.MARKER_RADIUS = 5 -- the root is "on" a return point within this flat distance
-- session states a return to the lobby comes from (a match passes through Results before the lobby)
M.RETURN_STATES = { Fight = true, Practice = true, Results = true } :: { [string]: boolean }
M.MARKER_NAMES = { ExitP1 = true, ExitP2 = true, ExitTraining = true, ExitCpu = true, Arrival = true } :: { [string]: boolean }

-- Camera CFrame over the shoulder of a player standing at `at` (facing its LookVector, flattened).
function M.frameBehind(at: CFrame): CFrame
	local look = Vector3.new(at.LookVector.X, 0, at.LookVector.Z)
	if look.Magnitude < 1e-3 then look = Vector3.new(0, 0, -1) end
	look = look.Unit
	local p = at.Position
	local eye = p - look * M.DISTANCE + Vector3.new(0, M.HEIGHT, 0)
	local target = p + look * M.LOOK_AHEAD + Vector3.new(0, M.LOOK_HEIGHT, 0)
	return CFrame.lookAt(eye, target)
end

-- The return point (exit or Arrival) under a position, if any: its facing is the arena's.
function M.markerAt(markers: { BasePart }, position: Vector3): BasePart?
	local best: BasePart? = nil
	local bestDistance = M.MARKER_RADIUS
	for _, m in markers do
		local d = Vector3.new(m.Position.X - position.X, 0, m.Position.Z - position.Z).Magnitude
		if d < bestDistance then best, bestDistance = m, d end
	end
	return best
end

-- Every return point in the world (exits of all arenas, the Arrival markers).
function M.worldMarkers(world: Instance?): { BasePart }
	local list = {}
	local arenas = world and world:FindFirstChild("Arenas")
	if not arenas then return list end
	for _, arena in arenas:GetChildren() do
		for _, child in arena:GetChildren() do
			if child:IsA("BasePart") and M.MARKER_NAMES[child.Name] then table.insert(list, child) end
		end
	end
	return list
end

export type Env = {
	camera: () -> Camera?,
	root: () -> BasePart?,
	markers: () -> { BasePart },
}
export type Tracker = {
	step: (session: string, now: number) -> (),
	onTeleport: (payload: any, now: number) -> (),
	pending: () -> boolean,
	aimed: () -> number,
}

-- Watches the session state (FrontEnd.update) and quick-travel notices; aims once per return.
function M.new(env: Env?): Tracker
	local e: Env = env or {
		camera = function(): Camera? return workspace.CurrentCamera end,
		root = function(): BasePart?
			local character = Players.LocalPlayer and Players.LocalPlayer.Character
			local r = character and character:FindFirstChild("HumanoidRootPart")
			return if r and r:IsA("BasePart") then r else nil
		end,
		markers = function(): { BasePart } return M.worldMarkers(workspace:FindFirstChild("FightingLabWorld")) end,
	}
	local last = ""
	local pendingUntil = 0
	local from: Vector3? = nil -- quick travel: where the character stood when the move was announced
	local aimedCount = 0
	local tracker: Tracker
	local function try(now: number)
		if now > pendingUntil then pendingUntil = 0; return end
		local cam = e.camera()
		local root = e.root()
		if not cam or not root or cam.CameraType == Enum.CameraType.Scriptable then return end
		if from and (root.Position - from).Magnitude < 4 then return end
		local marker = M.markerAt(e.markers(), root.Position)
		if not marker then return end
		local facing = CFrame.lookAt(root.Position, root.Position + marker.CFrame.LookVector)
		cam.CFrame = M.frameBehind(facing)
		pendingUntil = 0
		from = nil
		aimedCount += 1
	end
	tracker = {
		step = function(session: string, now: number)
			if session == "Lobby" and M.RETURN_STATES[last] then
				pendingUntil = now + M.WAIT_SECONDS
				from = nil
			end
			last = session
			if pendingUntil > 0 and session == "Lobby" then try(now) end
		end,
		onTeleport = function(payload: any, now: number)
			local p = if typeof(payload) == "table" then payload else {}
			-- a CPU match or a practice starts at once (the fight camera takes over); a travel lands in the lobby
			if p.reason == "Cpu" or p.reason == "Practice" then return end
			local root = e.root()
			from = if root then root.Position else nil
			pendingUntil = now + M.WAIT_SECONDS + (if typeof(p.delay) == "number" then p.delay else 0)
		end,
		pending = function() return pendingUntil > 0 end,
		aimed = function() return aimedCount end,
	}
	return tracker
end

return M
