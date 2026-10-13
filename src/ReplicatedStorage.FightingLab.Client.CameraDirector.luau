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

-- Fight framing (round 6 follow-up): the lens stays at chest height (4.47 studs) but sits 5% further back and aims higher
-- (focus 3.75 instead of 2.75), so the tallest fighter's head stays under the HUD band (FightSafe.top) at every spacing
-- with the feet still in frame; neutral spacing frames a 6-stud fighter at ~57% of the screen height (target 55-65%).
M.FightFocusHeight = 3.75
M.FightCameraRise = 0.72
M.FightDistanceScale = 1.05

function M._distanceForSeparation(separation: number): number
	local k = M.FightDistanceScale
	return math.clamp((9.15 + math.max(3.2, separation) * 0.94) * k, 15.0 * k, 24.4 * k)
end

function M._distanceForVerticalFit(separation: number, verticalExcess: number): number
	return math.clamp(M._distanceForSeparation(separation) + math.max(0, verticalExcess) * 1.25, 15.0 * M.FightDistanceScale, 29.8)
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
	local desiredFocus = Vector3.new(mid.X, M.FightFocusHeight + focusLift, mid.Z)
	local distance = M._distanceForVerticalFit(separation, verticalExcess)
	local desiredPos = desiredFocus - nextSide * distance + Vector3.new(0, M.FightCameraRise + math.min(0.45, verticalExcess * 0.08), 0)
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
		-- (Closer and orbiting; M.update's headroom fit turns and widens it so both bodies stay under the HUD band.)
		desiredFocus = mid + Vector3.new(0, 3.45, 0)
		desiredPos = desiredFocus - throwSide * math.max(13.5, distance - 3.2) + Vector3.new(0, 0.8, 0)
		desiredFov = 33
	end

	return { mode = mode, focus = desiredFocus, position = desiredPos, fov = desiredFov, shakeCap = MAX_SHAKE }
end

-- Arena geometry the world tags as camera occluders is faded by StageController, so it never pushes the camera in.
local OCCLUDER_TAG = "FightingLabCameraOccluder"

local function isOccluder(inst: Instance): boolean
	local parent = inst.Parent
	return CollectionService:HasTag(inst, OCCLUDER_TAG) or (parent ~= nil and parent:IsA("Model") and CollectionService:HasTag(parent, OCCLUDER_TAG))
end

-- Bodies (any model with a Humanoid: fighters, lobby avatars, posed rigs) never push the camera in; only walls do.
local function isBody(inst: Instance): boolean
	local model = inst:FindFirstAncestorOfClass("Model")
	return model ~= nil and model:FindFirstChildOfClass("Humanoid") ~= nil
end

local function clippedPosition(desiredFocus: Vector3, desiredPosition: Vector3, extraExcludes: { Instance }?): Vector3
	local delta = desiredPosition - desiredFocus
	if delta.Magnitude < 0.1 then return desiredPosition end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	local excludes: { Instance } = {}
	if extraExcludes then for _, inst in extraExcludes do table.insert(excludes, inst) end end
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
		if not isOccluder(result.Instance) and not isBody(result.Instance) then
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

-- Both fighters' body parts for framing and the body checks. Their CFrames are what this frame draws: the engine moves
-- the parts to the Motor6D transforms written this frame only after the picture (a Play capture with markers on both
-- showed the drawn limbs on the parts, not on the joint chain MotionPlayer.partWorld computes), and CharacterPresenter
-- keeps each root with the joints shown (DeferRootToPicture).
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
local function safeShotFor(parts: { BasePart }, models: { Instance }, look: Vector3, pos: Vector3): Vector3
	local p = M._clearOfBodies(pos, parts)
	p = clippedPosition(look, p, models)
	return M._clearOfBodies(p, parts)
end

local function modelsOf(parts: { BasePart }): { Instance }
	local seen: { [Instance]: boolean } = {}
	local out: { Instance } = {}
	for _, part in parts do
		local m = if typeof(part) == "Instance" then part:FindFirstAncestorOfClass("Model") else nil
		if m and not seen[m] then seen[m] = true; table.insert(out, m) end
	end
	return out
end

-- Safe picture areas (normalised viewport, y down) that framing keeps whole bodies inside (heads, hands and feet).
-- CineSafe, the Ultimate: below the HUD band (health bars, names and chips; it covers the top letterbox bar, 0-0.13),
-- above the bottom letterbox bar (0.89-1), in from the sides. FightSafe, the fight: below the HUD band, above the
-- bottom edge (the controls hint sits in the bottom-left corner).
export type SafeArea = { top: number, bottom: number, left: number, right: number }
M.CineSafe = { top = 0.215, bottom = 0.87, left = 0.04, right = 0.96 } :: SafeArea
M.FightSafe = { top = 0.215, bottom = 0.93, left = 0.03, right = 0.97 } :: SafeArea
M.CineFitMaxFov = 50
M.FightFitMaxFov = 44
-- The last word on every fight and cinematic frame (after smoothing, shake and the slow-motion narrowing): the lens widens
-- up to GuardMaxFov when a body still reaches out of its safe area.
M.GuardMaxFov = 70

-- Camera-space tangents of the points in front of the lens `cf` (x right, y up): their bounds and how many there are.
local function tangentBounds(cf: CFrame, points: { Vector3 }): (number, number, number, number, number)
	local x0, x1, y0, y1, n = math.huge, -math.huge, math.huge, -math.huge, 0
	for _, p in points do
		local l = cf:PointToObjectSpace(p)
		local z = -l.Z
		if z > 0.3 then
			local tx, ty = l.X / z, l.Y / z
			x0, x1, y0, y1 = math.min(x0, tx), math.max(x1, tx), math.min(y0, ty), math.max(y1, ty)
			n += 1
		end
	end
	return x0, x1, y0, y1, n
end

-- The smallest tan(vertical fov / 2) that puts every one of those tangents inside `safe`.
local function needTan(x0: number, x1: number, y0: number, y1: number, n: number, aspect: number, safe: SafeArea): number
	if n == 0 then return 0 end
	return math.max(0, y1 / (2 * (0.5 - safe.top)), -y0 / (2 * (safe.bottom - 0.5)), x1 / (2 * aspect * (safe.right - 0.5)), -x0 / (2 * aspect * (0.5 - safe.left)))
end

local function lens(pos: Vector3, dir: Vector3, roll: number): CFrame
	return CFrame.lookAt(pos, pos + dir) * CFrame.Angles(0, 0, roll)
end

-- The narrowest vertical field of view (degrees) that keeps `points` inside `safe` for the camera `cf` (roll included);
-- nil when no point is in front of it. Pure.
function M._safeFov(cf: CFrame, points: { Vector3 }, aspect: number, safe: SafeArea?): number?
	local x0, x1, y0, y1, n = tangentBounds(cf, points)
	if n == 0 then return nil end
	return 2 * math.deg(math.atan(needTan(x0, x1, y0, y1, n, aspect, safe or M.CineSafe)))
end

-- Framing of a shot: `points` (whole bodies) inside the safe area (opts.safe, default CineSafe). The shot first turns as
-- little as it can (pitch and yaw about its own axes, roll kept) to bring the bodies inside the window of the lens they
-- need; a body span too large for the current lens is centred. Then the lens widens up to opts.maxFov (default
-- CineFitMaxFov). Then the camera moves back along opts.away (default: straight back along its look line), turning
-- again at every step, to the nearest place where the widest lens fits (opts.back = false: no move, the lens widens as
-- far as needed). A point behind the lens never fits. A framing that already fits is returned unchanged; every step is
-- continuous in the points, so a moving body never makes the shot jump. Pure (tests pass points). Returns the camera
-- position, the field of view and the look point.
function M._fitShot(pos: Vector3, look: Vector3, fov: number, points: { Vector3 }, aspect: number?, opts: { safe: SafeArea?, roll: number?, maxFov: number?, back: boolean?, away: Vector3? }?): (Vector3, number, Vector3)
	local o = opts or {}
	local delta = look - pos
	if #points == 0 or delta.Magnitude < 1e-3 then return pos, fov, look end
	local s = o.safe or M.CineSafe
	local asp = aspect or (16 / 9)
	local roll = o.roll or 0
	local lookDist = delta.Magnitude
	local tanNow = math.tan(math.rad(fov) * 0.5)
	local tanMax = math.tan(math.rad(math.max(fov, o.maxFov or M.CineFitMaxFov)) * 0.5)
	-- The angle to turn (towards +) so the tangent span [lo, hi] lies inside the window [wLo, wHi]; centred if it is wider.
	local function turn(lo: number, hi: number, wLo: number, wHi: number): number
		if hi - lo >= wHi - wLo then return math.atan((lo + hi) * 0.5) - math.atan((wLo + wHi) * 0.5) end
		if hi > wHi then return math.atan(hi) - math.atan(wHi) end
		if lo < wLo then return math.atan(lo) - math.atan(wLo) end
		return 0
	end
	local function aim(eye: Vector3, from: Vector3): Vector3
		local dir = from
		for _ = 1, 4 do
			local cf = lens(eye, dir, roll)
			local x0, x1, y0, y1, n = tangentBounds(cf, points)
			if n == 0 then break end
			local tanSpan = math.max((y1 - y0) / (2 * (s.bottom - s.top)), (x1 - x0) / (2 * asp * (s.right - s.left)))
			local T = math.clamp(tanSpan, tanNow, tanMax)
			local pitch = turn(y0, y1, -(s.bottom - 0.5) * 2 * T, (0.5 - s.top) * 2 * T)
			local yaw = turn(x0, x1, -(0.5 - s.left) * 2 * T * asp, (s.right - 0.5) * 2 * T * asp)
			if math.abs(pitch) < 1e-4 and math.abs(yaw) < 1e-4 then break end
			local d = CFrame.fromAxisAngle(cf.RightVector, pitch):VectorToWorldSpace(dir)
			d = CFrame.fromAxisAngle(cf.UpVector, -yaw):VectorToWorldSpace(d)
			-- Never look straight up or down.
			if math.abs(d.Unit.Y) > 0.95 then break end
			dir = d.Unit
		end
		return dir
	end
	local function need(eye: Vector3, dir: Vector3): number
		local x0, x1, y0, y1, n = tangentBounds(lens(eye, dir, roll), points)
		if n < #points then return math.huge end
		return needTan(x0, x1, y0, y1, n, asp, s)
	end
	local dir = aim(pos, delta.Unit)
	local tanNeed = need(pos, dir)
	if tanNeed <= tanNow then return pos, fov, pos + dir * lookDist end
	if tanNeed <= tanMax or o.back == false then
		return pos, 2 * math.deg(math.atan(math.min(tanNeed, 1e3))), pos + dir * lookDist
	end
	local away = if o.away and o.away.Magnitude > 1e-3 then o.away.Unit else -dir
	-- The nearest place along `away` where the widest lens fits (bisection, so it changes smoothly from frame to frame).
	local lo, hi = 0, 40
	local hiDir = aim(pos + away * hi, dir)
	if need(pos + away * hi, hiDir) <= tanMax then
		for _ = 1, 20 do
			local mid = (lo + hi) * 0.5
			local d = aim(pos + away * mid, hiDir)
			if need(pos + away * mid, d) <= tanMax then hi, hiDir = mid, d else lo = mid end
		end
	end
	local eye = pos + away * hi
	local tanEye = math.clamp(need(eye, hiDir), tanNow, tanMax)
	return eye, 2 * math.deg(math.atan(tanEye)), eye + hiDir * (lookDist + hi)
end
-- Framing points of posed bodies: the top of each head (hair included), the soles and, with `hands`, the hands. Pure.
function M._framingPointsOf(parts: { BasePart }, hands: boolean?): { Vector3 }
	local out: { Vector3 } = {}
	for _, part in parts do
		local n = part.Name
		if n == "Head" then
			table.insert(out, part.Position + Vector3.new(0, part.Size.Y * 0.62, 0))
		elseif n == "LeftFoot" or n == "RightFoot" then
			table.insert(out, part.Position - Vector3.new(0, part.Size.Y * 0.6, 0))
		elseif hands and (n == "LeftHand" or n == "RightHand") then
			table.insert(out, part.Position)
		end
	end
	return out
end

-- Both fighters' framing points (posed rigs; else the views: feet on the root, head 6.3 studs up).
local function framingPoints(f: RenderFrame, hands: boolean?, parts: { BasePart }?): { Vector3 }
	local out = M._framingPointsOf(parts or bodyParts(), hands)
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

-- One frame of an Ultimate's cinematic camera: the clip's camera key for the attacker at `attackerPos` (world, on the
-- floor) facing `facing` (`mirrored` for the defender's player), out of the bodies (`parts`) and the walls, then turned,
-- widened or backed off so `points` (both whole bodies) stay inside CineSafe. When backing off put the lens into a wall
-- or a body, it is pushed out again and the lens widens from there instead. Pure apart from the wall raycasts: the
-- runtime (M.update) and the framing tests share it.
function M._cinematicShot(aId: string, throw: any, cineFrame: number, attackerPos: Vector3, facing: Vector3, mirrored: boolean, parts: { BasePart }, points: { Vector3 }, aspect: number?): { pos: Vector3, look: Vector3, fov: number, roll: number, shot: number, slow: boolean }
	local tl = Cinematic.timeline(aId, throw)
	local shot = Cinematic.cameraShot(Cinematic.clip(aId), tl, cineFrame, attackerPos, facing, mirrored)
	local models = modelsOf(parts)
	local pos = safeShotFor(parts, models, shot.look, shot.pos)
	-- Backing off moves away from the bodies' middle (and a little up), never through the fighter next to the lens.
	local centre = Vector3.zero
	for _, p in points do centre += p end
	centre /= math.max(1, #points)
	local off = pos - centre
	local flat = Vector3.new(off.X, 0, off.Z)
	local away = if flat.Magnitude > 0.3 then (flat.Unit + Vector3.new(0, 0.3, 0)).Unit else nil
	local fitPos, fitFov, fitLook = M._fitShot(pos, shot.look, shot.fov, points, aspect, { roll = shot.roll, away = away })
	if (fitPos - pos).Magnitude > 1e-3 then
		local clear = safeShotFor(parts, models, fitLook, fitPos)
		if (clear - fitPos).Magnitude > 1e-3 then
			fitPos, fitFov, fitLook = M._fitShot(clear, fitLook, fitFov, points, aspect, { roll = shot.roll, maxFov = M.GuardMaxFov, back = false })
		end
	end
	return { pos = fitPos, look = fitLook, fov = fitFov, roll = shot.roll, shot = shot.shot, slow = Cinematic.slowMotion(tl, cineFrame) }
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
		focus = origin + Vector3.new(0, M.FightFocusHeight, 0)
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
	local vp = cam.ViewportSize
	local aspect = if vp.Y > 1 then vp.X / vp.Y else 16 / 9
	-- Both posed bodies, once per frame; their framing points: heads and feet (the fight), plus hands (the Ultimate).
	local parts = bodyParts()
	local bodyPoints = framingPoints(f, false, parts)
	local wholePoints = framingPoints(f, true, parts)
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
				-- (A gentle move: the headroom fit below keeps both whole bodies inside the letterboxed picture.)
				local head = (if us.attacker == 1 then p1 else p2) + origin + Vector3.new(0, 4.2, 0)
				local away = plan.position - head
				plan.focus = plan.focus:Lerp(head, 0.35 * w)
				plan.position = clippedPosition(plan.focus, plan.position:Lerp(head + (if away.Magnitude > 0.01 then away.Unit else -side) * 10.5, 0.3 * w))
				plan.fov -= 3 * w
			end
		end
	end
	-- Headroom: both whole bodies (real posed heads and feet) inside FightSafe, under the HUD band (CineSafe from the
	-- Ultimate's activation: the letterbox is in). Standing fighters of every height already are on the plan; a jump, a
	-- juggle, a tall pose, a throw's close orbit or the push-in turns the shot as little as needed and widens the lens.
	if effectiveMode == "Fight" then
		local fitPos, fitFov, fitLook = M._fitShot(plan.position, plan.focus, plan.fov, if ultStart then wholePoints else bodyPoints, aspect,
			{ safe = if ultStart then M.CineSafe else M.FightSafe, maxFov = M.FightFitMaxFov })
		if (fitPos - plan.position).Magnitude > 1e-3 then fitPos = clippedPosition(fitLook, fitPos) end
		plan.position, plan.fov, plan.focus = fitPos, fitFov, fitLook
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
		-- Both fighters whole inside the letterboxed picture under the HUD band (a designed close-up never crops a head).
		local shot = M._cinematicShot(aId :: string, aView.throw, cineFrame :: number, origin + Vector3.new(aView.pos.X, 0, aView.pos.Z), aView.facing, aSlot ~= viewSlot, parts, wholePoints, aspect)
		local current = cineShot
		if current == nil or cineWeight < 1 or shot.shot ~= cineShotIndex then
			if current ~= nil and cineWeight >= 1 then cineCuts += 1 end
			cineShot = { pos = shot.pos, look = shot.look, fov = shot.fov, roll = shot.roll }
		else
			-- The keyed path is smooth already; the light filter only absorbs the body/wall/framing corrections.
			local k = 1 - math.exp(-f.dt * 30)
			current.pos, current.look = current.pos:Lerp(shot.pos, k), current.look:Lerp(shot.look, k)
			current.fov += (shot.fov - current.fov) * k
			current.roll += (shot.roll - current.roll) * k
		end
		cineShotIndex = shot.shot
		cineSlow = shot.slow
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
		if w < 1 then outPos = M._clearOfBodies(outPos, parts) end
	end
	-- The final hit's slow motion: the lens narrows a little.
	outFov -= 4 * slowShown
	local outCFrame = CFrame.lookAt(outPos + s, outLook + s * 0.35) * CFrame.Angles(0, 0, outRoll)
	-- Last word (after the smoothing lag, shake, lean and slow motion): a body still reaching out of the safe area widens
	-- the lens. The KO and victory shots are the presentation's own.
	if effectiveMode == "Fight" then
		local cine = cs ~= nil and cineWeight > 0.5
		local need = M._safeFov(outCFrame, if cine then wholePoints else bodyPoints, aspect, if cine or ultStart then M.CineSafe else M.FightSafe)
		if need then outFov = math.max(outFov, math.min(need, M.GuardMaxFov)) end
	end
	cam.FieldOfView = outFov
	cam.CFrame = outCFrame
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
