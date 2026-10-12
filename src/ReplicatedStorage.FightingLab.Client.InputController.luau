--!strict
-- Fight input (OV6 contract section 2). Bindings and labels come from RF.Controls. Only fight commands (Move, Crouch,
-- Attack) and practice commands (Reset, Dummy, Pause) are sent, through ctx.send; nothing fires while gameplay is
-- disabled (lobby, menus). Mechanics live in the authoritative sim: double taps (dash/backdash), 1+3 / 2+4 chords
-- (throws) and throw breaks are detected there, so the online path and the practice path behave the same.
--   D / A        walk forward / back (back also guards), double tap = dash / backdash
--   W tap        one sidestep into the screen (a Move z=+1 pulse)
--   S            press = crouch (crouch guard, instant); a quick tap with nothing else pressed = one sidestep toward
--                the camera (a Move z=-1 pulse on release)
--   U I J K      buttons 1 2 3 4;  O = throw (1+3)
--   G            controls guide (HudController.toggleGuide)
--   practice     R reset, Y dummy behaviour, P / Start pause (T, 1/2/3 and Backspace belong to LobbyUI)
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Controls = require(script.Parent.Parent:WaitForChild("Controls"))

type Ctx = any
local M = {}
local ctx: Ctx? = nil
local gameplayEnabled = false
local menuHandler: ((string) -> ())? = nil
local practiceHandler: ((string, any?) -> boolean?)? = nil
local held: { [string]: { [any]: boolean } } = { fwd = {}, back = {} }
local sentX = 0
local sentCrouch = false
local downSources: { [any]: boolean } = {}
local downTap = { pressedAt = 0, interrupted = false }
local stickState = { x = 0, y = 0 }
local pad: Frame? = nil
local controlsChip: TextButton? = nil
local controlPanelShown = false

M.Controls = Controls

-- Key maps built from Controls -------------------------------------------------------------------------------------

local MOVE_KEYS: { [Enum.KeyCode]: string } = {}
local BUTTON_KEYS: { [Enum.KeyCode]: string } = {}
local GUIDE_KEYS: { [Enum.KeyCode]: boolean } = {}
local PRACTICE_KEYS: { [Enum.KeyCode]: string } = {}
for _, device in { "keyboard", "gamepad" } do
	local function bindMove(action: string, dir: string)
		local code = Controls.keyCode("fight", action, device)
		if code then MOVE_KEYS[code] = dir end
	end
	bindMove("forward", "fwd"); bindMove("back", "back"); bindMove("sidestepIn", "up"); bindMove("sidestepOut", "down"); bindMove("crouch", "down")
	for action, button in Controls.buttons do
		local code = Controls.keyCode("fight", action, device)
		if code then BUTTON_KEYS[code] = button end
	end
	local guide = Controls.keyCode("fight", "guide", device)
	if guide then GUIDE_KEYS[guide] = true end
	for _, action in { "reset", "dummy", "pause" } do
		local code = Controls.keyCode("practice", action, device)
		if code then PRACTICE_KEYS[code] = action end
	end
end
M.MoveKeys = MOVE_KEYS
M.ButtonKeys = BUTTON_KEYS
M.PracticeKeys = PRACTICE_KEYS
local NOTATION: { [string]: string } = { LeadPunch = "1", RearPunch = "2", LeadKick = "3", RearKick = "4", Throw = "1+3" }
local MENU_KEYS: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.Left] = "Left", [Enum.KeyCode.Right] = "Right", [Enum.KeyCode.Up] = "Up", [Enum.KeyCode.Down] = "Down",
	[Enum.KeyCode.DPadLeft] = "Left", [Enum.KeyCode.DPadRight] = "Right", [Enum.KeyCode.DPadUp] = "Up", [Enum.KeyCode.DPadDown] = "Down",
}

-- Sending ----------------------------------------------------------------------------------------------------------

local function noteInput(text: string)
	local c = ctx
	if c and c.modules and c.modules.Hud and c.modules.Hud.recordInput then c.modules.Hud.recordInput(text) end
end
local function send(kind: string, a: any?, b: any?)
	local c = ctx
	if not c then error("InputController.init must run before sending input") end
	c.send(kind, a, b, 1)
end
local function isHeld(dir: string): boolean return next(held[dir]) ~= nil end
local function pushMove()
	local x = (if isHeld("fwd") then 1 else 0) - (if isHeld("back") then 1 else 0)
	if x ~= sentX then sentX = x; send("Move", x, 0) end
end
local function setCrouch(on: boolean)
	if on ~= sentCrouch then sentCrouch = on; send("Crouch", on) end
end
-- A sidestep is a z pulse: the sim reacts to the press edge only, so holding never orbits.
local function sidestep(dir: number)
	send("Move", sentX, dir)
	send("Move", sentX, 0)
	noteInput(if dir > 0 then "SS in" else "SS out")
end
local function interruptTap() downTap.interrupted = true end

local function setHold(dir: string, source: any, down: boolean)
	local wasHeld = isHeld(dir)
	held[dir][source] = if down then true else nil
	if down and not wasHeld then interruptTap(); noteInput(if dir == "fwd" then "f" else "b") end
	pushMove()
end

local function setDown(source: any, down: boolean)
	local was = next(downSources) ~= nil
	downSources[source] = if down then true else nil
	local now = next(downSources) ~= nil
	if now and not was then
		downTap.pressedAt = os.clock()
		downTap.interrupted = false
		setCrouch(true)
		noteInput("d")
	elseif was and not now then
		setCrouch(false)
		if not downTap.interrupted and (os.clock() - downTap.pressedAt) * 1000 <= Controls.tapMs then sidestep(-1) end
	end
end

local function pressButton(button: string)
	interruptTap()
	noteInput(NOTATION[button] or button)
	send("Attack", button)
end

function M.releaseAll()
	for _, sources in held do table.clear(sources) end
	table.clear(downSources)
	stickState.x, stickState.y = 0, 0
	downTap.interrupted = true
	if ctx then
		pushMove()
		setCrouch(false)
	end
end

function M.setGameplayEnabled(b: boolean)
	if gameplayEnabled == b then return end
	gameplayEnabled = b
	if not b then
		M.releaseAll()
	else
		-- Directions already held when the fight starts keep working without a new key press.
		M.releaseAll()
		for code, dir in MOVE_KEYS do
			if (dir == "fwd" or dir == "back") and code.Name ~= "DPadLeft" and code.Name ~= "DPadRight" and UserInputService:IsKeyDown(code) then
				held[dir][code] = true
			end
		end
		pushMove()
	end
	if controlsChip then M.setTouchControlsVisible(controlPanelShown) end
end
function M.isGameplayEnabled(): boolean return gameplayEnabled end
function M.bindMenu(handler: (string) -> ()) menuHandler = handler end
-- Optional override for the practice actions handled here (R / Y / P / Start): handler(action, arg) -> handled?.
function M.bindPractice(handler: ((string, any?) -> boolean?)?) practiceHandler = handler end
local function fireMenu(action: string)
	local h = menuHandler
	if h then h(action) end
end

local function isPractice(): boolean
	local c = ctx
	return c ~= nil and c.gui ~= nil and c.gui:GetAttribute("SessionAuthority") == "Local"
end

local function latestPaused(): boolean
	local c = ctx
	local fs = c and c.modules and c.modules.FightSession
	if not fs or typeof(fs.get) ~= "function" then return false end
	local ok, session = pcall(fs.get)
	if not ok or not session then return false end
	local entry = session.latestEntry
	return entry ~= nil and entry.paused == true
end

-- Practice actions ("Reset", "Dummy" [mode | nil = cycle], "Pause" [bool | nil = toggle]). Returns true if sent.
function M.practice(action: string, arg: any?): boolean
	local h = practiceHandler
	if h then
		local handled = h(action, arg)
		if handled ~= false then return true end
	end
	local c = ctx
	if not c then return false end
	if action == "Reset" then
		M.releaseAll()
		c.send("Reset", nil, nil, 1)
		return true
	elseif action == "Dummy" then
		if arg ~= nil and arg ~= "Stand" and arg ~= "Guard" and arg ~= "Fight" then return false end
		c.send("Dummy", arg, nil, 1)
		return true
	elseif action == "Pause" then
		local paused = if typeof(arg) == "boolean" then arg else not latestPaused()
		M.releaseAll()
		c.send("Pause", paused, nil, 1)
		return true
	end
	return false
end

-- Touch ------------------------------------------------------------------------------------------------------------

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, radius); c.Parent = parent
end
local function button(parent: Frame, name: string, text: string, index: number, color: Color3, rightSide: boolean?): TextButton
	local b = Instance.new("TextButton")
	b.Name, b.Text, b.Font, b.TextSize, b.TextWrapped = name, text, Enum.Font.GothamBold, 12, true
	b.TextColor3, b.BackgroundColor3, b.BackgroundTransparency, b.AutoButtonColor = Color3.new(1, 1, 1), color, 0.18, true
	b.Size = UDim2.fromOffset(76, 38)
	local col = index % 2; local row = math.floor(index / 2)
	if rightSide then b.Position = UDim2.new(1, -160 + col * 80, 1, -140 + row * 42) else b.Position = UDim2.new(0, 10 + col * 80, 1, -140 + row * 42) end
	b.Parent = parent; corner(b, 10); return b
end
local function touchHold(b: TextButton, onChange: (input: InputObject, down: boolean) -> ())
	local active: { [InputObject]: boolean } = {}
	b.InputBegan:Connect(function(input)
		if gameplayEnabled and (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1) then
			active[input] = true; onChange(input, true)
		end
	end)
	UserInputService.InputEnded:Connect(function(input) if active[input] then active[input] = nil; onChange(input, false) end end)
end
local function initTouch(gui: ScreenGui)
	local p = Instance.new("Frame"); p.Name = "TouchButtons"; p.Size = UDim2.fromScale(1, 1); p.BackgroundTransparency = 1; p.Visible = controlPanelShown; p.Parent = gui; pad = p
	local chip = Instance.new("TextButton"); chip.Name = "ControlsToggle"; chip.Size = UDim2.fromOffset(92, 24); chip.Position = UDim2.new(1, -102, 1, -30); chip.BackgroundColor3 = Color3.fromRGB(12,16,24); chip.BackgroundTransparency = 0.25; chip.TextColor3 = Color3.fromRGB(230,236,248); chip.Font = Enum.Font.GothamBold; chip.TextSize = 10; chip.Parent = gui; corner(chip, 8); controlsChip = chip
	chip.Activated:Connect(function() M.releaseAll(); M.setTouchControlsVisible(not controlPanelShown) end)
	local moveColor = Color3.fromRGB(45, 60, 85)
	touchHold(button(p, "Back", "←", 0, moveColor, false), function(input, down) setHold("back", input, down) end)
	touchHold(button(p, "Forward", "→", 1, moveColor, false), function(input, down) setHold("fwd", input, down) end)
	touchHold(button(p, "StepIn", "↑ step", 2, moveColor, false), function(_input, down) if down then interruptTap(); sidestep(1) end end)
	touchHold(button(p, "Down", "↓ crouch / tap step", 3, moveColor, false), function(input, down) setDown(input, down) end)
	local attacks = { { "LeadPunch", "1" }, { "RearPunch", "2" }, { "LeadKick", "3" }, { "RearKick", "4" }, { "Throw", "THROW" } }
	for n, item in attacks do
		button(p, item[1], item[2], n - 1, if item[1] == "Throw" then Color3.fromRGB(160,80,70) else Color3.fromRGB(80,96,126), true).Activated:Connect(function()
			if gameplayEnabled then pressButton(item[1]) end
		end)
	end
	M.setTouchControlsVisible(controlPanelShown)
end
function M.setTouchControlsVisible(b: boolean)
	controlPanelShown = b and UserInputService.TouchEnabled
	if pad then pad.Visible = controlPanelShown end
	if controlsChip then controlsChip.Visible = UserInputService.TouchEnabled and gameplayEnabled; controlsChip.Text = if controlPanelShown then "HIDE TOUCH" else "TOUCH" end
	local c = ctx
	if c then c.gui:SetAttribute("ControlPanelShown", controlPanelShown) end
end

-- Devices ----------------------------------------------------------------------------------------------------------

local function onStick(position: Vector3)
	local hi, lo = Controls.stickThreshold, Controls.stickRelease
	local x = stickState.x
	if position.X > hi then x = 1 elseif position.X < -hi then x = -1 elseif math.abs(position.X) < lo then x = 0 end
	if x ~= stickState.x then
		stickState.x = x
		setHold("fwd", "Thumbstick", x == 1)
		setHold("back", "Thumbstick", x == -1)
	end
	local y = stickState.y
	if position.Y > hi + 0.1 then y = 1 elseif position.Y < -(hi + 0.1) then y = -1 elseif math.abs(position.Y) < lo then y = 0 end
	if y ~= stickState.y then
		local before = stickState.y
		stickState.y = y
		if y == 1 then interruptTap(); sidestep(1) end
		if y == -1 then setDown("Thumbstick", true) elseif before == -1 then setDown("Thumbstick", false) end
	end
end

function M.init(newCtx: Ctx)
	ctx = newCtx
	controlPanelShown = false
	newCtx.gui:SetAttribute("ControlPanelShown", controlPanelShown)
	initTouch(newCtx.gui)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		local key = input.KeyCode
		if not gameplayEnabled then
			if MENU_KEYS[key] then fireMenu(MENU_KEYS[key]); return end
			if key == Enum.KeyCode.Return or key == Enum.KeyCode.ButtonA then fireMenu("Confirm"); return end
			if key == Enum.KeyCode.Backspace or key == Enum.KeyCode.ButtonB then fireMenu("Back"); return end
			return
		end
		if GUIDE_KEYS[key] then
			local hud = newCtx.modules and newCtx.modules.Hud
			if hud and hud.toggleGuide then hud.toggleGuide() end
			return
		end
		if key == Enum.KeyCode.V and RunService:IsStudio() then
			local hud = newCtx.modules and newCtx.modules.Hud
			if hud and hud.toggleDebug then hud.toggleDebug() end
			return
		end
		local practiceAction = PRACTICE_KEYS[key]
		if practiceAction then
			if isPractice() then
				if practiceAction == "reset" then M.practice("Reset") elseif practiceAction == "dummy" then M.practice("Dummy") else M.practice("Pause") end
			end
			return
		end
		local dir = MOVE_KEYS[key]
		if dir == "fwd" or dir == "back" then setHold(dir, key, true) return end
		if dir == "up" then interruptTap(); sidestep(1) return end
		if dir == "down" then setDown(key, true) return end
		local buttonName = BUTTON_KEYS[key]
		if buttonName then pressButton(buttonName) return end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local key = input.KeyCode
		local dir = MOVE_KEYS[key]
		if dir == "fwd" or dir == "back" then
			if held[dir][key] then setHold(dir, key, false) end
		elseif dir == "down" then
			if downSources[key] then setDown(key, false) end
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not gameplayEnabled or input.KeyCode ~= Enum.KeyCode.Thumbstick1 then return end
		onStick(input.Position)
	end)
	UserInputService.WindowFocusReleased:Connect(M.releaseAll)
end

return M
