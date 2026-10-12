--!strict
-- FightingLab control scheme (OV6 contract section 2): the single source of truth for key bindings and their display
-- labels. InputController reads the bindings; HUD legends, the controls guide, the move list and lobby prompts render
-- labels from here. Binding values are Enum.KeyCode names.
local Controls = {}

Controls.fight = {
	keyboard = {
		forward = "D", back = "A", sidestepIn = "W", sidestepOut = "S", crouch = "S",
		lp = "U", rp = "I", lk = "J", rk = "K", throw = "O", guide = "G",
	},
	gamepad = {
		forward = "DPadRight", back = "DPadLeft", sidestepIn = "DPadUp", sidestepOut = "DPadDown", crouch = "DPadDown",
		lp = "ButtonX", rp = "ButtonY", lk = "ButtonA", rk = "ButtonB", throw = "ButtonR1", guide = "ButtonSelect",
	},
}
Controls.practice = {
	keyboard = { reset = "R", switchMode = "T", easy = "One", normal = "Two", hard = "Three", dummy = "Y", pause = "P", leave = "Backspace" },
	gamepad = { pause = "ButtonStart" },
}
Controls.lobby = {
	keyboard = { interact = "E", menu = "Tab", jump = "Space" },
	gamepad = { interact = "ButtonX", menu = "ButtonY", jump = "ButtonA" },
}
-- Genre notation: buttons 1-4 = left punch, right punch, left kick, right kick.
Controls.notation = { lp = "1", rp = "2", lk = "3", rk = "4", throw = "1+3" }
-- Sim button names (Attack command payloads) per fight action.
Controls.buttons = { lp = "LeadPunch", rp = "RearPunch", lk = "LeadKick", rk = "RearKick", throw = "Throw" }
-- Timing: a down/S press released within tapMs (with no other fight key in between) is a sidestep, otherwise a crouch.
-- Double taps and 1+3 / 2+4 chords are detected by the authoritative sim (CombatConfig.DashTapWindow / ChordFrames).
Controls.tapMs = 150
Controls.stickThreshold = 0.5
Controls.stickRelease = 0.35

-- Plain-language names of every action (legends, tutorials).
Controls.actionText = {
	forward = "Walk forward", back = "Walk back / guard", dash = "Dash", backdash = "Backdash",
	sidestepIn = "Sidestep in", sidestepOut = "Sidestep out", crouch = "Crouch / low guard",
	lp = "Left punch (1)", rp = "Right punch (2)", lk = "Left kick (3)", rk = "Right kick (4)",
	throw = "Throw (1+3)", throw1 = "Throw (1+3)", throw2 = "Throw (2+4)", breakThrow = "Break a throw",
	guard = "Guard", guide = "Controls guide",
	reset = "Reset positions", switchMode = "Training / Versus CPU", easy = "CPU Easy", normal = "CPU Normal", hard = "CPU Hard",
	dummy = "Dummy: stand / guard / fight back", pause = "Pause", leave = "Leave practice",
	interact = "Interact", menu = "Menu", jump = "Jump",
}

local KEY_LABELS: { [string]: string } = {
	One = "1", Two = "2", Three = "3", Four = "4", Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9", Zero = "0",
	Space = "SPACE", Tab = "TAB", Backspace = "BACKSPACE", Return = "ENTER", Escape = "ESC", LeftShift = "SHIFT",
	ButtonX = "X", ButtonY = "Y", ButtonA = "A", ButtonB = "B", ButtonR1 = "RB", ButtonL1 = "LB", ButtonR2 = "RT", ButtonL2 = "LT",
	ButtonStart = "START", ButtonSelect = "SELECT", DPadRight = "→", DPadLeft = "←", DPadUp = "↑", DPadDown = "↓",
	Thumbstick1 = "LS", Thumbstick2 = "RS",
}

local function normDevice(device: string?): string
	return if device == "gamepad" then "gamepad" else "keyboard"
end

-- Display text of one KeyCode name ("One" -> "1", "ButtonR1" -> "RB").
function Controls.keyLabel(keyName: string): string
	return KEY_LABELS[keyName] or string.upper(keyName)
end

local function binding(group: string, action: string, device: string): string?
	local g = (Controls :: any)[group]
	if typeof(g) ~= "table" then return nil end
	local d = g[device]
	if typeof(d) ~= "table" then return nil end
	local v = d[action]
	return if typeof(v) == "string" then v else nil
end

-- Display label for an action, e.g. label("fight", "lp") = "U", label("fight", "dash") = "D D",
-- label("fight", "throw2", "gamepad") = "Y+B", label("practice", "easy") = "1". Unknown actions return "".
function Controls.label(group: string, action: string, device: string?): string
	local dev = normDevice(device)
	if group == "fight" then
		local k = function(a: string): string
			local b = binding("fight", a, dev)
			return if b then Controls.keyLabel(b) else ""
		end
		if action == "dash" then return k("forward") .. " " .. k("forward") end
		if action == "backdash" then return k("back") .. " " .. k("back") end
		if action == "throw1" then return k("lp") .. "+" .. k("lk") end
		if action == "throw2" then return k("rp") .. "+" .. k("rk") end
		if action == "breakThrow" then return k("lp") .. " / " .. k("rp") end
		if action == "guard" then return k("back") end
	end
	local b = binding(group, action, dev)
	return if b then Controls.keyLabel(b) else ""
end

-- Enum.KeyCode for an action (nil if unbound on that device).
function Controls.keyCode(group: string, action: string, device: string?): Enum.KeyCode?
	local b = binding(group, action, normDevice(device))
	if not b then return nil end
	local ok, code = pcall(function() return (Enum.KeyCode :: any)[b] end)
	return if ok then code else nil
end

-- Every KeyCode bound to an action on a device (the gamepad also moves with the left stick, see InputController).
function Controls.keyCodes(group: string, action: string, device: string?): { Enum.KeyCode }
	local code = Controls.keyCode(group, action, device)
	return if code then { code } else {}
end

-- Ordered legend rows for guides: { action, keys, text }.
local LEGENDS: { [string]: { string } } = {
	fight = { "forward", "back", "dash", "backdash", "sidestepIn", "sidestepOut", "crouch", "lp", "rp", "lk", "rk", "throw", "throw1", "throw2", "breakThrow", "guide" },
	practice = { "reset", "switchMode", "easy", "normal", "hard", "dummy", "pause", "leave" },
	lobby = { "interact", "menu", "jump" },
}
function Controls.legend(group: string, device: string?): { { action: string, keys: string, text: string } }
	local rows = {}
	for _, action in LEGENDS[group] or {} do
		local keys = Controls.label(group, action, device)
		if action == "sidestepOut" then keys ..= " (tap)" elseif action == "crouch" then keys ..= " (hold)" elseif action == "sidestepIn" then keys ..= " (tap)" end
		if keys ~= "" and not string.match(keys, "^ %(") then
			table.insert(rows, { action = action, keys = keys, text = Controls.actionText[action] or action })
		end
	end
	return rows
end

local DIRECTION_TEXT: { [string]: { keyboard: string, gamepad: string } } = {
	f = { keyboard = "D", gamepad = "→" }, b = { keyboard = "A", gamepad = "←" }, d = { keyboard = "S", gamepad = "↓" },
	df = { keyboard = "S+D", gamepad = "↘" }, db = { keyboard = "S+A", gamepad = "↙" },
	ss = { keyboard = "W/S", gamepad = "↑/↓" },
}
local BUTTON_ACTION: { [string]: string } = { LP = "lp", RP = "rp", LK = "lk", RK = "rk", ["1"] = "lp", ["2"] = "rp", ["3"] = "lk", ["4"] = "rk" }

local function trim(s: string): string return (string.gsub(s, "^%s*(.-)%s*$", "%1")) end

-- Converts a roster input ("LP, RP", "df+RP", "dash+RP", "f+LP+LK") or numeric notation ("1,2", "df+2") into
-- display keys for a device: keyboard "U, I" / "S+D+I" / "D D+I", gamepad "X, Y" / "↘+Y".
function Controls.formatMoveInput(input: string, device: string?): string
	local dev = normDevice(device)
	local parts = {}
	for part in string.gmatch(input, "[^,]+") do
		local tokens = {}
		local text = trim(part)
		if string.sub(text, 1, 5) == "dash+" then
			table.insert(tokens, Controls.label("fight", "dash", dev))
			text = string.sub(text, 6)
		elseif string.sub(text, 1, 4) == "f,f+" then
			table.insert(tokens, Controls.label("fight", "dash", dev))
			text = string.sub(text, 5)
		end
		for token in string.gmatch(text, "[^+]+") do
			local t = trim(token)
			local action = BUTTON_ACTION[t]
			if action then
				table.insert(tokens, Controls.label("fight", action, dev))
			elseif DIRECTION_TEXT[t] then
				table.insert(tokens, (DIRECTION_TEXT[t] :: any)[dev])
			else
				table.insert(tokens, t)
			end
		end
		table.insert(parts, table.concat(tokens, "+"))
	end
	return table.concat(parts, ", ")
end

-- Numeric genre notation for a roster input: "LP, RP" -> "1,2", "df+RP" -> "df+2", "LP+LK" -> "1+3".
function Controls.notationOf(input: string): string
	local out = string.gsub(input, "LP", "1")
	out = string.gsub(out, "RP", "2")
	out = string.gsub(out, "LK", "3")
	out = string.gsub(out, "RK", "4")
	out = string.gsub(out, "dash%+", "f,f+")
	out = string.gsub(out, ",%s+", ",")
	return out
end

return Controls
