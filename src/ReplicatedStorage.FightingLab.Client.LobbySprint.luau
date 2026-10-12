--!strict
-- Lobby sprint (round 5). Hold Left Shift on a keyboard, press the left stick on a gamepad (stays on until you stop
-- moving or press it again) or tap the on-screen SPRINT toggle on touch screens; every binding comes from
-- Controls.lobby.sprint. Lobby only: LobbyUI's `allowed()` is false in fights, practice, countdowns and while an overlay
-- (menu, PLAY panel, fighter select, pickers) is open, and the sprint then stops at once.
-- Walk speed ramps 16 -> 28 studs/s (smoothstep over RAMP_UP seconds) and the camera FOV eases FOV_BOOST degrees
-- wider; both ease back over RAMP_DOWN when you let go or stop moving.
local UserInputService = game:GetService("UserInputService")

local LobbySprint = {}
LobbySprint.WALK_SPEED = 16
LobbySprint.SPRINT_SPEED = 28
LobbySprint.RAMP_UP = 0.35
LobbySprint.RAMP_DOWN = 0.25
LobbySprint.FOV_BOOST = 6
-- A gamepad/touch sprint switches itself off after standing still this long once you have moved; before the first step
-- it waits ARM_SECONDS (a tap on SPRINT, then the thumb travels to the stick).
LobbySprint.IDLE_OFF = 0.6
LobbySprint.ARM_SECONDS = 4
LobbySprint.MOVING = 0.1
-- Horizontal root speed (studs/s) that also counts as moving (tap / click-to-move).
LobbySprint.MOVING_SPEED = 4

local function smooth(a: number): number
	return a * a * (3 - 2 * a)
end

-- Next sprint amount (0..1) toward `want` after dt seconds.
function LobbySprint.stepAlpha(alpha: number, want: boolean, dt: number): number
	if want then return math.min(1, alpha + dt / LobbySprint.RAMP_UP) end
	return math.max(0, alpha - dt / LobbySprint.RAMP_DOWN)
end

function LobbySprint.speedFor(alpha: number): number
	return LobbySprint.WALK_SPEED + (LobbySprint.SPRINT_SPEED - LobbySprint.WALK_SPEED) * smooth(math.clamp(alpha, 0, 1))
end

function LobbySprint.fovFor(base: number, alpha: number): number
	return base + LobbySprint.FOV_BOOST * smooth(math.clamp(alpha, 0, 1))
end

export type Env = {
	allowed: () -> boolean,
	humanoid: () -> Humanoid?,
	camera: (() -> Camera?)?,
	-- Overrides Humanoid.MoveDirection (tests).
	moving: (() -> boolean)?,
}
export type Controller = {
	setHeld: (on: boolean) -> (),
	setToggle: (on: boolean) -> (),
	toggle: () -> (),
	toggled: () -> boolean,
	held: () -> boolean,
	alpha: () -> number,
	speed: () -> number,
	sprinting: () -> boolean,
	step: (dt: number) -> (),
	cancel: () -> (),
	onChanged: (fn: (toggled: boolean) -> ()) -> (),
	destroy: () -> (),
}

function LobbySprint.new(env: Env): Controller
	local held, toggledOn = false, false
	local alpha = 0
	local idle = 0
	local movedSinceToggle = false
	local wroteSpeed: number? = nil
	local baseFov: number? = nil
	local wroteFov: number? = nil
	local listeners: { (boolean) -> () } = {}
	local controller: Controller

	local function notify()
		for _, fn in listeners do pcall(fn, toggledOn) end
	end
	local function humanoid(): Humanoid?
		local ok, h = pcall(env.humanoid)
		return if ok and typeof(h) == "Instance" and h:IsA("Humanoid") then h else nil
	end
	local function camera(): Camera?
		if not env.camera then return nil end
		local ok, c = pcall(env.camera :: any)
		return if ok and typeof(c) == "Instance" and c:IsA("Camera") then c else nil
	end
	local function moving(h: Humanoid?): boolean
		if env.moving then
			local ok, m = pcall(env.moving :: any)
			return ok and m == true
		end
		if h == nil then return false end
		if h.MoveDirection.Magnitude > LobbySprint.MOVING then return true end
		-- Tap / click-to-move walks with Humanoid:MoveTo, which leaves MoveDirection at zero: use the root's speed.
		local root = h.RootPart
		if not root then return false end
		local v = root.AssemblyLinearVelocity
		return Vector3.new(v.X, 0, v.Z).Magnitude > LobbySprint.MOVING_SPEED
	end
	local function applySpeed(h: Humanoid?, value: number)
		if not h then return end
		-- Only ever undo our own writes (another system may own the speed in other states).
		if wroteSpeed == nil and math.abs(value - LobbySprint.WALK_SPEED) < 1e-3 then return end
		if h.WalkSpeed ~= value then h.WalkSpeed = value end
		wroteSpeed = if math.abs(value - LobbySprint.WALK_SPEED) < 1e-3 then nil else value
	end
	local function applyFov(value: number?)
		local cam = camera()
		if not cam then return end
		if value == nil then
			if wroteFov ~= nil and baseFov ~= nil then cam.FieldOfView = baseFov end
			wroteFov, baseFov = nil, nil
			return
		end
		if cam.CameraType ~= Enum.CameraType.Custom then return end
		cam.FieldOfView = value
		wroteFov = value
	end
	-- Instant stop (overlays, fights): speed and FOV snap back so nothing captures the boosted values.
	local function cancel()
		local h = humanoid()
		alpha = 0
		idle = 0
		applySpeed(h, LobbySprint.WALK_SPEED)
		applyFov(nil)
		if toggledOn then
			toggledOn = false
			notify()
		end
	end

	controller = {
		setHeld = function(on: boolean) held = on end,
		setToggle = function(on: boolean)
			if toggledOn == on then return end
			toggledOn = on
			idle = 0
			movedSinceToggle = false
			notify()
		end,
		toggle = function() controller.setToggle(not toggledOn) end,
		toggled = function() return toggledOn end,
		held = function() return held end,
		alpha = function() return alpha end,
		speed = function() return LobbySprint.speedFor(alpha) end,
		sprinting = function() return alpha > 0 end,
		step = function(dt: number)
			local okAllowed, allowed = pcall(env.allowed)
			if not okAllowed or not allowed then
				if alpha > 0 or toggledOn or wroteSpeed ~= nil or wroteFov ~= nil then cancel() end
				return
			end
			local h = humanoid()
			local isMoving = moving(h)
			if toggledOn then
				if isMoving then
					idle = 0
					movedSinceToggle = true
				else
					idle += dt
				end
				if idle >= (if movedSinceToggle then LobbySprint.IDLE_OFF else LobbySprint.ARM_SECONDS) then
					toggledOn = false
					notify()
				end
			end
			local want = (held or toggledOn) and isMoving
			alpha = LobbySprint.stepAlpha(alpha, want, dt)
			applySpeed(h, LobbySprint.speedFor(alpha))
			local cam = camera()
			if cam then
				if alpha <= 0 then
					applyFov(nil)
				else
					if baseFov == nil then baseFov = cam.FieldOfView end
					applyFov(LobbySprint.fovFor(baseFov :: number, alpha))
				end
			end
		end,
		cancel = cancel,
		onChanged = function(fn: (boolean) -> ()) table.insert(listeners, fn) end,
		destroy = function()
			cancel()
			table.clear(listeners)
		end,
	}
	return controller
end

-- Live keyboard / gamepad bindings (Controls.lobby.sprint). `keyCodes(device)` returns the bound KeyCodes. Returns a
-- disconnect function.
function LobbySprint.bindInput(controller: Controller, keyCodes: (device: string) -> { Enum.KeyCode }): () -> ()
	local function isKey(code: Enum.KeyCode, device: string): boolean
		for _, k in keyCodes(device) do if k == code then return true end end
		return false
	end
	local c1 = UserInputService.InputBegan:Connect(function(input: InputObject)
		if UserInputService:GetFocusedTextBox() then return end
		if input.UserInputType == Enum.UserInputType.Keyboard and isKey(input.KeyCode, "keyboard") then
			controller.setHeld(true)
		elseif string.sub(input.UserInputType.Name, 1, 7) == "Gamepad" and isKey(input.KeyCode, "gamepad") then
			controller.toggle()
		end
	end)
	local c2 = UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Keyboard and isKey(input.KeyCode, "keyboard") then controller.setHeld(false) end
	end)
	-- Losing focus (alt-tab) never leaves the key "held".
	local c3 = UserInputService.WindowFocusReleased:Connect(function() controller.setHeld(false) end)
	return function() c1:Disconnect(); c2:Disconnect(); c3:Disconnect() end
end

return LobbySprint
