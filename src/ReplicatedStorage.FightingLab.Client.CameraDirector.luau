--!strict
local CollectionService = game:GetService("CollectionService")
local Cinematic = require(script.Parent:WaitForChild("Motion"):WaitForChild("Cinematic"))

type Ctx = any
type RenderFrame = any

type CameraPlan = {
	mode: string,
	focus: Vector3,
	position: Vector3,
	fov: number,
	shakeCap: number,
}

local M = {}
local ctx: Ctx? = nil
local camera: Camera? = nil
local requestedMode = "Fight"
local effectiveMode = "Fight"
local camPos = Vector3.new(0, 4.7, 20)
local camLook = Vector3.new(0, 2.75, 0)
local focus = Vector3.zero
local side = Vector3.new(0, 0, -1)
local shake = 0
local impactPush = 0
local impactTilt = 0
-- Shown (eased) versions of the shake, impact push/tilt and hitstop lean (see M.update).
local shakeShown, pushShown, tiltShown, hitLean = 0, 0, 0, 0
local koPresentationUntil = 0
local koPresentationStarted = 0
local orbit = 0
local lastThrowOrbit = 0
-- Round resets (see M._isReset): the frame the sim puts the fighters back on their marks is a hard cut for the bodies
-- (MotionPlayer) and for the camera alike.
local lastPhase: string? = nil
local lastPos: { [number]: Vector3? } = {}
local lastPlan: CameraPlan? = nil
local snapCount = 0
-- Arena space: the fight happens around `origin` (world FightOrigin). The camera only drives the view during a fight
-- session; in the lobby the default Roblox camera follows the player's avatar.
local origin = Vector3.zero
local viewSlot = 1
local active = false
local savedFov: number? = nil

local VALID = { Menu = true, Select = true, Intro = true, Fight = true, KO = true, Victory = true }
local BASE_FOV = 36
local MIN_SHAKE = 0
local MAX_SHAKE = 0.09
local FIGHTER_HEIGHT = 6.0
-- A fighter moving further than this in one frame was put back on its mark (= MotionPlayer.TeleportDistance).
M.TeleportDistance = 3

-- Ultimate presentation (round 6, docs/design/ultimates.md). On UltStart the camera holds still for UltFreeze seconds
-- (the screen flash plays over it), then pushes in on the attacker for UltPushIn seconds and eases back if no cinematic
-- follows. While both fighters are in the cinematic (Motion.Cinematic) the clip's camera keys drive the shot (cuts are
-- hard cuts), kept out of every body part (BodyMargin) and every wall; the final impact's slow motion narrows the lens.
-- After the cinematic the camera glides back to the fight camera over CineReturn seconds.
M.UltFreeze = 0.14
M.UltPushIn = 0.7
M.CineReturn = 0.8
M.BodyMargin = 0.75
local ultStart: { t: number, attacker: number }? = nil
local cineWeight = 0
local cineShot: { pos: Vector3, look: Vector3, fov: number, roll: number }? = nil
local cineShotIndex: number? = nil
local cineExitAt: number? = nil
local cineSlow = false
local cineCuts = 0
local slowShown = 0
local fightFov = BASE_FOV
local function smoothstep(x: number): number local t = math.clamp(x, 0, 1); return t * t * (3 - 2 * t) end
local BODY_PARTS = { "Head", "UpperTorso", "LowerTorso", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot" }
local bodyCache: { [Model]: { BasePart } } = setmetatable({} :: any, { __mode = "k" })

function M.setMode(mode: string)
	assert(VALID[mode] == true, "Unknown camera mode: " .. mode)
	requestedMode = mode
end

function M.impulse(strength: number)
	local c = ctx
	if c and c.gui:GetAttribute("CameraShakeDisabled") == true then return end
	shake = math.clamp(shake + math.max(0, strength), MIN_SHAKE, MAX_SHAKE)
end

local function tierImpactScale(e: CombatEvent): number
	if e.kind == "KO" then return 1.45 end
	if e.kind == "UltHit" then return if e.knockdown == true then 1.45 else 0.95 end
	if e.kind == "UltStart" then return 0 end
	if e.kind == "Surge" then return 0.3 end
	if e.launch == true or e.tier == "Launch" then return 1.15 end
	if e.counter == true then return 1.0 end
	if e.tier == "Heavy" then return 0.82 end
	if e.tier == "Medium" then return 0.55 end
	return 0.24
end

function M.onEvent(e: CombatEvent)
	if e.kind == "UltStart" then
		ultStart = { t = os.clock(), attacker = if e.attacker == 2 then 2 else 1 }
		return
	end
	local scale = tierImpactScale(e)
	if e.kind == "Whiff" or e.kind == "Crush" then scale *= 0.25 end
	impactPush = math.max(impactPush, 0.18 + scale * 0.88)
	-- Tilt away from the attacker as seen on screen (slot 2 views the fight from the other side).
	local attackerOnLeft = ((e.attacker or 1) == 1) == (viewSlot == 1)
	impactTilt = math.clamp(impactTilt + (if attackerOnLeft then -1 else 1) * scale * 0.012, -0.035, 0.035)
	if e.kind == "KO" then
		local now = os.clock()
		koPresentationStarted = now
		koPresentationUntil = now + 1.25
	end
end

function M.getFocus(): Vector3
	return focus
end

local function characterRoot(i: number): BasePart?
	local c = ctx
	if not c then return nil end
	return c.modules.Characters.getRoot(i)
end

local function stateMode(f: RenderFrame): string
	if requestedMode == "Menu" or requestedMode == "Select" then return requestedMode end
	if f.phase == "Ready" then return "Intro" end
	if f.phase == "MatchOver" then return "Victory" end
	if f.ko or f.phase == "RoundOver" then return "KO" end
	return "Fight"
end

local function fighterPos(f: RenderFrame, i: number, fallback: Vector3): Vector3
	local r = f.fighters[i]
	if r then return r.pos end
	-- Before the first snapshot the rigs are still parked in the pool (far below the arena): use the start marks.
	local root = characterRoot(i)
	if root and (root.Position - origin).Magnitude < 60 then return root.Position - origin end
	return fallback
end

local function hasThrow(f: RenderFrame): boolean
	for i = 1, 2 do
		local r = f.fighters[i]
		-- (The Ultimate's cinematic has its own camera; the fight camera keeps its normal plan underneath it.)
		if r and (r :: any).throw ~= nil and not Cinematic.isUltimate((r :: any).throw) then return true end
	end
	return false
end

local function airborneBias(f: RenderFrame): number
	local bottom = math.huge
	local top = -math.huge
	local airborne = false
	for i = 1, 2 do
		local r = f.fighters[i]
		if r then
			bottom = math.min(bottom, r.pos.Y)
			top = math.max(top, r.pos.Y + FIGHTER_HEIGHT)
			if r.state == "Airborne" or r.state == "Landing" or ((r :: any).velocityY or 0) > 2 or ((r :: any).airFrames or 0) > 0 then
				airborne = true
			end
		end
	end
	if not airborne or bottom == math.huge then return 0 end
	return math.clamp(top - bottom - FIGHTER_HEIGHT, 0, 4.8)
end

-- Perpendicular to the fight line with the first fighter on the left of the screen.
local function fightSide(p1: Vector3, p2: Vector3): Vector3
	local axis = Vector3.new((p2 - p1).X, 0, (p2 - p1).Z)
	local forward = if axis.Magnitude > 0.01 then axis.Unit else Vector3.xAxis
	local desired = Vector3.new(forward.Z, 0, -forward.X)
	if desired.Magnitude < 0.01 then desired = Vector3.zAxis end
	return desired.Unit
end

local function sideVector(p1: Vector3, p2: Vector3, previous: Vector3): Vector3
	local desired = fightSide(p1, p2)
	if desired:Dot(previous) < -0.15 then desired = -desired end
	return desired
end

-- The sim's round reset, detected exactly like MotionPlayer's body cut: a new round starts (RoundOver/MatchOver ->
-- Ready) or a fighter jumps further than TeleportDistance in one frame (training/practice resets).
function M._isReset(previousPhase: string?, phase: string?, prev1: Vector3?, pos1: Vector3?, prev2: Vector3?, pos2: Vector3?): boolean
	if (previousPhase == "RoundOver" or previousPhase == "MatchOver") and phase == "Ready" then return true end
	if prev1 and pos1 and (pos1 - prev1).Magnitude > M.TeleportDistance then return true end
	if prev2 and pos2 and (pos2 - prev2).Magnitude > M.TeleportDistance then return true end
	return false
end

local function smooth(current: Vector3, target: Vector3, dt: number, rate: number): Vector3
	return current:Lerp(target, 1 - math.exp(-dt * rate))
end

-- The camera's follow: this frame's first-order step toward the shot (`want`), with the camera's velocity changing by
-- at most MaxCameraAccel (studs/s^2). A shot that jumps (KO framing, throw orbit, a long dash) used to start the camera
-- from rest to 45 studs/s in one frame — a visible jerk; now it takes off over ~4 frames and catches up.
M.MaxCameraAccel = 600
local camVel, lookVel = Vector3.zero, Vector3.zero
local function follow(pos: Vector3, vel: Vector3, want: Vector3, dt: number): (Vector3, Vector3)
	if dt <= 0 then return want, vel end
	local v = (want - pos) / dt
	local dv = v - vel
	local maxDv = M.MaxCameraAccel * dt
	if dv.Magnitude > maxDv then v = vel + dv.Unit * maxDv end
	return pos + v * dt, v
end

local function rotateFlat(v: Vector3, radians: number): Vector3
	local c = math.cos(radians)
	local s = math.sin(radians)
	return Vector3.new(v.X * c - v.Z * s, 0, v.X * s + v.Z * c).Unit
end

function M._screenHeightFraction(distance: number, objectHeight: number, verticalFovDegrees: number): number
	local angular = 2 * math.atan((objectHeight * 0.5) / math.max(0.01, distance))
	return angular / math.rad(verticalFovDegrees)
end

function M._distanceForSeparation(separation: number): number
	-- Neutral spacing (7 studs) frames a 6-stud fighter at ~60% of the screen height (target 55-65%).
	return math.clamp(9.15 + math.max(3.2, separation) * 0.94, 15.0, 24.4)
end

function M._distanceForVerticalFit(separation: number, verticalExcess: number): number
	return math.clamp(M._distanceForSeparation(separation) + math.max(0, verticalExcess) * 1.25, 15.0, 29.8)
end

function M._projectedHeight(cameraCFrame: CFrame, verticalFovDegrees: number, viewportY: number, head: Vector3, foot: Vector3): number
	local function yOf(world: Vector3): number
		local localPoint = cameraCFrame:PointToObjectSpace(world)
		local z = math.max(0.01, -localPoint.Z)
		local focal = (viewportY * 0.5) / math.tan(math.rad(verticalFovDegrees) * 0.5)
		return viewportY * 0.5 - (localPoint.Y / z) * focal
	end
	return math.abs(yOf(head) - yOf(foot)) / viewportY
end

function M._normalizedViewportPoint(cameraCFrame: CFrame, verticalFovDegrees: number, aspect: number, world: Vector3): Vector2?
	if aspect <= 0 then error("aspect must be positive") end
	local localPoint = cameraCFrame:PointToObjectSpace(world)
	local z = -localPoint.Z
	if z <= 0.01 then return nil end
	local tanY = math.tan(math.rad(verticalFovDegrees) * 0.5)
	local x = 0.5 + (localPoint.X / z) / (2 * tanY * aspect)
	local y = 0.5 - (localPoint.Y / z) / (2 * tanY)
	return Vector2.new(x, y)
end

function M._plan(p1: Vector3, p2: Vector3, mode: string, now: number, dt: number, previousSide: Vector3, extraUp: number, throwActive: boolean, winner: number?): CameraPlan
	local flatDelta = Vector3.new((p2 - p1).X, 0, (p2 - p1).Z)
	local separation = math.max(3.2, flatDelta.Magnitude)
	local nextSide = sideVector(p1, p2, previousSide)
	local mid = (p1 + p2) * 0.5
	local verticalExcess = math.clamp(extraUp, 0, 4.8)
	local focusLift = math.min(1.05, verticalExcess * 0.18)
	local desiredFocus = Vector3.new(mid.X, math.min(3.8, 2.75 + focusLift), mid.Z)
	local distance = M._distanceForVerticalFit(separation, verticalExcess)
	local desiredPos = desiredFocus - nextSide * distance + Vector3.new(0, 1.72 + math.min(0.45, verticalExcess * 0.08), 0)
	local desiredFov = math.min(44, BASE_FOV + verticalExcess * 1.35)

	if mode == "Intro" then
		-- Both fighters in a low three-quarter two-shot that slowly swings round to the fight side.
		local sweep = rotateFlat(nextSide, -0.55 + math.sin(now * 0.4) * 0.12)
		desiredFocus = mid + Vector3.new(0, 3.0, 0)
		desiredPos = desiredFocus - sweep * (12.5 + separation * 0.85) + Vector3.new(0, 1.3 + math.sin(now * 0.5) * 0.3, 0)
		desiredFov = 34
	elseif mode == "KO" then
		local loser = if winner == 1 then 2 else 1
		local target = if loser == 1 then p1 else p2
		local other = if loser == 1 then p2 else p1
		-- Low two-shot from the fight side, weighted on the falling loser, slowly drifting: the winner stays in frame
		-- and never ends up between the lens and the body.
		local sweep = rotateFlat(nextSide, math.sin(now * 0.35) * 0.3)
		desiredFocus = target:Lerp(other, 0.3) + Vector3.new(0, 2.0, 0)
		desiredPos = desiredFocus - sweep * (11.5 + separation * 0.6) + Vector3.new(0, 0.9, 0)
		desiredFov = 32
	elseif mode == "Victory" then
		local target = if winner == 2 then p2 else p1
		local opponent = if winner == 2 then p1 else p2
		local toOpponent = Vector3.new((opponent - target).X, 0, (opponent - target).Z)
		local facing = if toOpponent.Magnitude > 0.01 then toOpponent.Unit else Vector3.xAxis
		-- Three-quarter front view of the winner's whole body (head to feet).
		local viewDir = (-nextSide * 0.8 + facing * 0.6).Unit
		local pan = Vector3.new(viewDir.Z, 0, -viewDir.X) * 1.6
		desiredFocus = target + Vector3.new(0, 3.0, 0) + pan
		desiredPos = target + Vector3.new(0, 3.3, 0) + viewDir * 16.5 + pan
		desiredFov = 31
	elseif mode == "Menu" or mode == "Select" then
		local orbitSide = Vector3.new(math.cos(now * 0.25), 0, math.sin(now * 0.25)).Unit
		desiredFocus = Vector3.new(0, 2.4, 0)
		desiredPos = desiredFocus + orbitSide * 18 + Vector3.new(0, 3.6, 0)
		desiredFov = 34
	elseif throwActive then
		lastThrowOrbit += dt * 1.35
		local throwSide = rotateFlat(nextSide, math.sin(lastThrowOrbit) * 0.28)
		desiredFocus = mid + Vector3.new(0, 2.55, 0)
		desiredPos = desiredFocus - throwSide * math.max(12.5, distance - 4.4) + Vector3.new(0, 1.35, 0)
		desiredFov = 31
	end

	return { mode = mode, focus = desiredFocus, position = desiredPos, fov = desiredFov, shakeCap = MAX_SHAKE }
end

-- Arena geometry the world tags as camera occluders is faded by StageController, so it never pushes the camera in.
local OCCLUDER_TAG = "FightingLabCameraOccluder"

local function isOccluder(inst: Instance): boolean
	local parent = inst.Parent
	return CollectionService:HasTag(inst, OCCLUDER_TAG) or (parent ~= nil and parent:IsA("Model") and CollectionService:HasTag(parent, OCCLUDER_TAG))
end

local function clippedPosition(desiredFocus: Vector3, desiredPosition: Vector3): Vector3
	local delta = desiredPosition - desiredFocus
	if delta.Magnitude < 0.1 then return desiredPosition end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	local excludes: { Instance } = {}
	local c = ctx
	if c then
		for i = 1, 2 do
			local rootPart = c.modules.Characters.getRoot(i)
			if rootPart then table.insert(excludes, rootPart.Parent or rootPart) end
		end
	end
	local fx = workspace:FindFirstChild("FightingLabLocalEffects")
	if fx then table.insert(excludes, fx) end
	-- Lobby avatars watching from the arena edge never push the fight camera in.
	for _, player in game:GetService("Players"):GetPlayers() do
		if player.Character then table.insert(excludes, player.Character) end
	end
	for _ = 1, 8 do
		params.FilterDescendantsInstances = excludes
		local result = workspace:Raycast(desiredFocus, delta, params)
		if not result then return desiredPosition end
		if not isOccluder(result.Instance) then
			return result.Position - delta.Unit * 0.35
		end
		table.insert(excludes, result.Instance)
	end
	return desiredPosition
end

-- Pushes a camera position out of the given body parts: every part's box grown by `margin` (BodyMargin). Pure (tests
-- pass posed rigs' parts).
function M._clearOfBodies(pos: Vector3, parts: { BasePart }, margin: number?): Vector3
	local m = margin or M.BodyMargin
	local p = pos
	for _ = 1, 4 do
		local moved = false
		for _, part in parts do
			local cf = part.CFrame
			local half = part.Size * 0.5
			local l = cf:PointToObjectSpace(p)
			local c = Vector3.new(math.clamp(l.X, -half.X, half.X), math.clamp(l.Y, -half.Y, half.Y), math.clamp(l.Z, -half.Z, half.Z))
			local d = l - c
			local dist = d.Magnitude
			if dist < m then
				local dir = if dist > 1e-4 then d / dist elseif l.Magnitude > 1e-4 then l.Unit else Vector3.zAxis
				p += cf:VectorToWorldSpace(dir) * (m - dist + 1e-3)
				moved = true
			end
		end
		if not moved then break end
	end
	return p
end

local function bodyParts(): { BasePart }
	local out: { BasePart } = {}
	local c = ctx
	if not c then return out end
	for i = 1, 2 do
		local model = c.modules.Characters.getModel and c.modules.Characters.getModel(i)
		if model then
			local list = bodyCache[model]
			if not list then
				list = {}
				for _, name in BODY_PARTS do
					local part = model:FindFirstChild(name, true)
					if part and part:IsA("BasePart") then table.insert(list, part) end
				end
				bodyCache[model] = list
			end
			for _, part in list do table.insert(out, part) end
		end
	end
	return out
end

-- A cinematic camera position that is in no body and behind no wall: out of the bodies, clipped by the walls (from the
-- look point), and out of the bodies again (a wall can push the lens back in front of a fighter).
local function safeShot(look: Vector3, pos: Vector3): Vector3
	local parts = bodyParts()
	local p = M._clearOfBodies(pos, parts)
	p = clippedPosition(look, p)
	return M._clearOfBodies(p, parts)
end

-- Framing of a cinematic shot: both fighters whole in the frame (heads and feet, CineFitMargin of headroom). The lens
-- widens up to CineFitMaxFov, then the camera backs off along its look line. Pure (tests pass points).
M.CineFitMaxFov = 50
M.CineFitMargin = 1.12
function M._fitShot(pos: Vector3, look: Vector3, fov: number, points: { Vector3 }, aspect: number?): (Vector3, number)
	if #points == 0 then return pos, fov end
	local delta = look - pos
	if delta.Magnitude < 1e-3 then return pos, fov end
	local dir = delta.Unit
	local right = dir:Cross(Vector3.yAxis)
	right = if right.Magnitude < 1e-3 then Vector3.xAxis else right.Unit
	local up = right:Cross(dir)
	local asp = aspect or (16 / 9)
	local function need(back: number): number
		local eye = pos - dir * back
		local worst = 0
		for _, p in points do
			local v = p - eye
			local z = math.max(v:Dot(dir), 0.3)
			worst = math.max(worst, math.abs(v:Dot(up)) * M.CineFitMargin / z, math.abs(v:Dot(right)) * M.CineFitMargin / (z * asp))
		end
		return worst
	end
	local tanNow = math.tan(math.rad(fov) * 0.5)
	local tanNeed = need(0)
	if tanNeed <= tanNow then return pos, fov end
	local tanMax = math.tan(math.rad(math.max(fov, M.CineFitMaxFov)) * 0.5)
	if tanNeed <= tanMax then return pos, 2 * math.deg(math.atan(tanNeed)) end
	local back = 0
	for _ = 1, 30 do
		back += 0.5
		if need(back) <= tanMax then break end
	end
	return pos - dir * back, 2 * math.deg(math.atan(tanMax))
end

-- Heads and feet of both fighters (posed rigs; else the views: feet on the root, head 6.3 studs up).
local function framingPoints(f: RenderFrame): { Vector3 }
	local out: { Vector3 } = {}
	for _, part in bodyParts() do
		local n = part.Name
		if n == "Head" then
			table.insert(out, part.Position + Vector3.new(0, part.Size.Y * 0.6, 0))
		elseif n == "LeftFoot" or n == "RightFoot" then
			table.insert(out, part.Position - Vector3.new(0, part.Size.Y * 0.6, 0))
		end
	end
	if #out > 0 then return out end
	for i = 1, 2 do
		local v = f.fighters and f.fighters[i]
		if type(v) == "table" and typeof(v.pos) == "Vector3" then
			local base = origin + Vector3.new(v.pos.X, math.max(v.pos.Y, 0), v.pos.Z)
			table.insert(out, base)
			table.insert(out, base + Vector3.new(0, 6.3, 0))
		end
	end
	return out
end

-- Slot 1 watches from the side where P1 is on the left; slot 2 from the opposite side (its fighter on the left).
local function initialSide(slot: number): Vector3
	return if slot == 2 then Vector3.new(0, 0, 1) else Vector3.new(0, 0, -1)
end

function M.beginFight(newOrigin: Vector3, slot: number?)
	origin = newOrigin
	viewSlot = if slot == 2 then 2 else 1
	requestedMode = "Fight"
	side = initialSide(viewSlot)
	shake, impactPush, impactTilt, koPresentationUntil = 0, 0, 0, 0
	shakeShown, pushShown, tiltShown, hitLean = 0, 0, 0, 0
	camVel, lookVel = Vector3.zero, Vector3.zero
	lastPhase, lastPlan = nil, nil
	ultStart, cineWeight, cineShot, cineShotIndex, cineExitAt, cineSlow, slowShown = nil, 0, nil, nil, nil, false, 0
	table.clear(lastPos)
	local cam = workspace.CurrentCamera
	if cam then fightFov = cam.FieldOfView end
	if cam then
		camera = cam
		if not active then savedFov = cam.FieldOfView end
		-- Glide from the lobby view into the intro shot, looking at the fight centre from the first frame.
		focus = origin + Vector3.new(0, 2.75, 0)
		camPos = cam.CFrame.Position
		camLook = focus
		cam.CameraType = Enum.CameraType.Scriptable
	end
	active = true
end

function M.endFight()
	if not active then return end
	active = false
	local cam = workspace.CurrentCamera
	if cam then
		cam.CameraType = Enum.CameraType.Custom
		local player = game:GetService("Players").LocalPlayer
		local character = player and player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then cam.CameraSubject = humanoid end
		cam.FieldOfView = savedFov or 70
	end
	savedFov = nil
end

function M.isActive(): boolean
	return active
end

function M.getViewSlot(): number
	return viewSlot
end

-- Test hook: the camera's smoothed state, the latest plan and how many reset cuts happened.
function M._state(): { camPos: Vector3, camLook: Vector3, focus: Vector3, side: Vector3, plan: CameraPlan?, snaps: number, cinematic: { weight: number, shot: number?, cuts: number, slow: boolean, pushing: boolean } }
	return { camPos = camPos, camLook = camLook, focus = focus, side = side, plan = lastPlan, snaps = snapCount,
		cinematic = { weight = cineWeight, shot = cineShotIndex, cuts = cineCuts, slow = cineSlow, pushing = ultStart ~= nil } }
end

function M.update(f: RenderFrame)
	if not active then return end
	if typeof(f.origin) == "Vector3" then origin = f.origin end
	local cam = camera or workspace.CurrentCamera
	if not cam then return end
	camera = cam
	cam.CameraType = Enum.CameraType.Scriptable
	effectiveMode = stateMode(f)
	-- Plan in arena space with the local fighter as "a" so it stays on the left of the screen.
	local p1 = fighterPos(f, 1, Vector3.new(-3.5, 0, 0))
	local p2 = fighterPos(f, 2, Vector3.new(3.5, 0, 0))
	local cur1: Vector3? = if f.fighters[1] then p1 else nil
	local cur2: Vector3? = if f.fighters[2] then p2 else nil
	local reset = M._isReset(lastPhase, f.phase, lastPos[1], cur1, lastPos[2], cur2)
	lastPhase, lastPos[1], lastPos[2] = f.phase, cur1, cur2
	if reset then
		-- New round: nothing carries over from the KO/victory shot (shake, push, tilt, slow-mo framing).
		shake, impactPush, impactTilt, koPresentationUntil = 0, 0, 0, 0
		shakeShown, pushShown, tiltShown, hitLean = 0, 0, 0, 0
		camVel, lookVel = Vector3.zero, Vector3.zero
	end
	local a, b = p1, p2
	local winner = f.winner
	if viewSlot == 2 then
		a, b = p2, p1
		winner = if f.winner == 1 then 2 elseif f.winner == 2 then 1 else f.winner
	end
	-- The fight line turns smoothly (sidesteps orbit the pair) instead of snapping with every step; a reset puts the
	-- local fighter back on the left at once.
	side = if reset then fightSide(a, b) else smooth(side, sideVector(a, b, side), f.dt, 6.0).Unit
	orbit += f.dt * 0.45
	local plan = M._plan(a, b, effectiveMode, f.now + orbit, f.dt, side, airborneBias(f), hasThrow(f), winner)
	plan.focus += origin
	plan.position += origin
	if f.hitstop and f.hitstop > 0 and effectiveMode == "Fight" then
		plan.fov = math.min(plan.fov, 33)
	end
	-- The hitstop lean-in and the impact push/tilt ease in and out over a few frames: a target that steps in one frame
	-- gave the first-order camera follow a velocity jump (a jerk on every hit).
	local leanTarget = if f.hitstop and f.hitstop > 0 and effectiveMode == "Fight" then 1 else 0
	hitLean += (leanTarget - hitLean) * (1 - math.exp(-f.dt * 22))
	pushShown += (impactPush - pushShown) * (1 - math.exp(-f.dt * 24))
	tiltShown += (impactTilt - tiltShown) * (1 - math.exp(-f.dt * 24))
	plan.position += side * (0.65 * hitLean)
	local now = os.clock()
	if koPresentationUntil > now then
		local t = math.clamp((now - koPresentationStarted) / math.max(0.01, koPresentationUntil - koPresentationStarted), 0, 1)
		plan.position += side * (1.25 * (1 - t)) + Vector3.new(0, 0.55 * (1 - t), 0)
		plan.fov = math.min(plan.fov, 28 + 3 * t)
	end
	plan.position += side * pushShown
	plan.position = clippedPosition(plan.focus, plan.position)
	-- Ultimate activation: the camera holds still for UltFreeze (the flash plays over it), then pushes in on the attacker
	-- and eases back when no cinematic takes over (a blocked or whiffed Ultimate).
	local frozen = false
	local us = ultStart
	if us then
		local el = now - us.t
		if el > M.UltFreeze + M.UltPushIn + 0.6 or effectiveMode ~= "Fight" then
			ultStart = nil
		else
			frozen = el < M.UltFreeze
			local w = smoothstep((el - M.UltFreeze) / 0.22) * (1 - smoothstep((el - M.UltFreeze - M.UltPushIn) / 0.6))
			if w > 0 then
				local head = (if us.attacker == 1 then p1 else p2) + origin + Vector3.new(0, 4.2, 0)
				local away = plan.position - head
				plan.focus = plan.focus:Lerp(head, 0.5 * w)
				plan.position = clippedPosition(plan.focus, plan.position:Lerp(head + (if away.Magnitude > 0.01 then away.Unit else -side) * 10.5, 0.5 * w))
				plan.fov -= 6 * w
			end
		end
	end
	if reset then
		-- Hard cut, the same frame the bodies cut: the camera starts the new round on its shot instead of gliding across.
		focus, camPos, camLook = plan.focus, plan.position, plan.focus
		camVel, lookVel = Vector3.zero, Vector3.zero
		cam.FieldOfView = plan.fov
		fightFov = plan.fov
		snapCount += 1
	elseif frozen then
		camVel, lookVel = Vector3.zero, Vector3.zero
	else
		focus = smooth(focus, plan.focus, f.dt, 8.5)
		camPos, camVel = follow(camPos, camVel, smooth(camPos, plan.position, f.dt, if effectiveMode == "Fight" then 9.8 else 4.2), f.dt)
		camLook, lookVel = follow(camLook, lookVel, smooth(camLook, plan.focus, f.dt, 10.5), f.dt)
	end
	lastPlan = plan
	-- The Ultimate's cinematic: the clip's camera keys (Motion.Cinematic) on top of the fight camera, which keeps
	-- following its own plan underneath so the return after the cinematic glides onto a live shot.
	local aSlot, aId, cineFrame, aView = Cinematic.active(f)
	if aSlot and aView and effectiveMode == "Fight" and typeof(aView.pos) == "Vector3" and typeof(aView.facing) == "Vector3" then
		local tl = Cinematic.timeline(aId, aView.throw)
		local shot = Cinematic.cameraShot(Cinematic.clip(aId), tl, cineFrame :: number, origin + Vector3.new(aView.pos.X, 0, aView.pos.Z), aView.facing, aSlot ~= viewSlot)
		local pos = safeShot(shot.look, shot.pos)
		-- Both fighters whole in the frame (a designed close-up never crops a head or the feet).
		local vp = cam.ViewportSize
		local fitPos, fitFov = M._fitShot(pos, shot.look, shot.fov, framingPoints(f), if vp.Y > 1 then vp.X / vp.Y else nil)
		if (fitPos - pos).Magnitude > 1e-3 then fitPos = safeShot(shot.look, fitPos) end
		pos = fitPos
		shot.fov = fitFov
		local current = cineShot
		if current == nil or cineWeight < 1 or shot.shot ~= cineShotIndex then
			if current ~= nil and cineWeight >= 1 then cineCuts += 1 end
			cineShot = { pos = pos, look = shot.look, fov = shot.fov, roll = shot.roll }
		else
			-- The keyed path is smooth already; the light filter only absorbs the body/wall corrections.
			local k = 1 - math.exp(-f.dt * 30)
			current.pos, current.look = current.pos:Lerp(pos, k), current.look:Lerp(shot.look, k)
			current.fov += (shot.fov - current.fov) * k
			current.roll += (shot.roll - current.roll) * k
		end
		cineShotIndex = shot.shot
		cineSlow = Cinematic.slowMotion(tl, cineFrame :: number)
		cineWeight, cineExitAt, ultStart = 1, nil, nil
	else
		cineSlow = false
		if cineWeight > 0 then
			cineExitAt = cineExitAt or now
			cineWeight = 1 - smoothstep((now - (cineExitAt :: number)) / M.CineReturn)
			if cineWeight <= 1e-3 then cineWeight, cineShot, cineShotIndex, cineExitAt = 0, nil, nil, nil end
		end
	end
	shake = math.max(0, shake - f.dt * 1.55)
	impactPush = math.max(0, impactPush - f.dt * 4.2)
	impactTilt *= math.exp(-f.dt * 8)
	-- Shake at 5-7 Hz (a 14 Hz shake sampled at 60 fps read as jitter), easing in over two frames.
	shakeShown += (shake - shakeShown) * (1 - math.exp(-f.dt * 30))
	local s = Vector3.new(math.sin(f.now * 41), math.cos(f.now * 33), math.sin(f.now * 29) * 0.4) * shakeShown
	if not frozen then fightFov += (plan.fov - fightFov) * (1 - math.exp(-f.dt * 5.5)) end
	slowShown += ((if cineSlow then 1 else 0) - slowShown) * (1 - math.exp(-f.dt * 12))
	local outPos, outLook, outFov, outRoll = camPos, camLook, fightFov, tiltShown
	local cs = cineShot
	if cs and cineWeight > 0 then
		local w = cineWeight
		outPos, outLook = camPos:Lerp(cs.pos, w), camLook:Lerp(cs.look, w)
		outFov, outRoll = fightFov + (cs.fov - fightFov) * w, tiltShown + (cs.roll - tiltShown) * w
		-- The glide back from the last cinematic shot never passes through a fighter.
		if w < 1 then outPos = M._clearOfBodies(outPos, bodyParts()) end
	end
	-- The final hit's slow motion: the lens narrows a little.
	outFov -= 4 * slowShown
	cam.FieldOfView = outFov
	cam.CFrame = CFrame.lookAt(outPos + s, outLook + s * 0.35) * CFrame.Angles(0, 0, outRoll)
	local c = ctx
	if c then
		c.gui:SetAttribute("CameraMode", effectiveMode)
		c.gui:SetAttribute("CameraCinematic", cineWeight > 0)
		c.gui:SetAttribute("CameraCinematicShot", cineShotIndex or 0)
		c.gui:SetAttribute("CameraScreenHeightNeutral", M._screenHeightFraction(M._distanceForSeparation(7), 6.0, BASE_FOV))
		c.gui:SetAttribute("CameraScreenHeightClose", M._screenHeightFraction(M._distanceForSeparation(3.2), 6.0, BASE_FOV))
		c.gui:SetAttribute("CameraScreenHeightMax", M._screenHeightFraction(M._distanceForSeparation(14), 6.0, BASE_FOV))
		c.gui:SetAttribute("CameraPresentationSlowMoMaxSeconds", 1.25)
		c.gui:SetAttribute("CameraPresentationActive", koPresentationUntil > now)
	end
end

function M.init(newCtx: Ctx)
	ctx = newCtx
	camera = workspace.CurrentCamera
	-- The lobby keeps the default Roblox camera; beginFight takes it over.
end

return M
