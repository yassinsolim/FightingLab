--!strict
-- Controls: the single source of truth for the OV6 control scheme (contract section 2) and its display labels.
local Lab = game:GetService("ReplicatedStorage"):WaitForChild("FightingLab")
local Controls = require(Lab:WaitForChild("Controls"))
local Roster = require(Lab:WaitForChild("Roster"))

return function(t)
	local test, expect = t.test, t.expect

	test("keyboard and gamepad bindings follow the contract scheme", function()
		local k = Controls.fight.keyboard
		local expected = { forward = "D", back = "A", sidestepIn = "W", sidestepOut = "S", crouch = "S", lp = "U", rp = "I", lk = "J", rk = "K", throw = "O", guide = "G" }
		for action, key in expected do expect.equal((k :: any)[action], key, "keyboard " .. action) end
		local g = Controls.fight.gamepad
		local pad = { lp = "ButtonX", rp = "ButtonY", lk = "ButtonA", rk = "ButtonB", throw = "ButtonR1", guide = "ButtonSelect", sidestepIn = "DPadUp", sidestepOut = "DPadDown" }
		for action, key in pad do expect.equal((g :: any)[action], key, "gamepad " .. action) end
		local p = Controls.practice.keyboard
		local practice = { reset = "R", switchMode = "T", easy = "One", normal = "Two", hard = "Three", dummy = "Y", pause = "P", leave = "Backspace" }
		for action, key in practice do expect.equal((p :: any)[action], key, "practice " .. action) end
		expect.equal(Controls.practice.gamepad.pause, "ButtonStart")
		for _, old in { "L", "F", "C", "M" } do
			for action, key in k do expect.truthy(key ~= old, "old key " .. old .. " is no longer bound (" .. action .. ")") end
		end
		expect.truthy(Controls.tapMs >= 100 and Controls.tapMs <= 200, "S tap window stays responsive")
	end)

	test("no key does two jobs except S (tap = sidestep out, hold = crouch)", function()
		for _, device in { "keyboard", "gamepad" } do
			local owner: { [string]: string } = {}
			for _, group in { "fight", "practice" } do
				for action, key in (Controls :: any)[group][device] do
					local shared = (action == "crouch" or action == "sidestepOut") and group == "fight"
					local prev = owner[key]
					if prev and not shared then
						expect.truthy(false, device .. " key " .. key .. " bound to " .. prev .. " and " .. group .. "." .. action)
					end
					if not shared or prev == nil then owner[key] = group .. "." .. action end
				end
			end
			expect.equal(Controls.fight[device].crouch, Controls.fight[device].sidestepOut, device .. " crouch and sidestep out share one key")
		end
	end)

	test("every bound key name is a real KeyCode", function()
		for _, group in { "fight", "practice", "lobby" } do
			for _, device in { "keyboard", "gamepad" } do
				for action in (Controls :: any)[group][device] do
					expect.truthy(Controls.keyCode(group, action, device) ~= nil, group .. "." .. action .. " on " .. device)
					expect.equal(#Controls.keyCodes(group, action, device), 1)
				end
			end
		end
		expect.equal(Controls.keyCode("fight", "nothing"), nil)
	end)

	test("labels describe keys, double taps, chords and throw breaks", function()
		expect.equal(Controls.label("fight", "lp"), "U")
		expect.equal(Controls.label("fight", "rk"), "K")
		expect.equal(Controls.label("fight", "dash"), "D D")
		expect.equal(Controls.label("fight", "backdash"), "A A")
		expect.equal(Controls.label("fight", "throw1"), "U+J")
		expect.equal(Controls.label("fight", "throw2"), "I+K")
		expect.equal(Controls.label("fight", "breakThrow"), "U / I")
		expect.equal(Controls.label("fight", "guard"), "A")
		expect.equal(Controls.label("fight", "throw2", "gamepad"), "Y+B")
		expect.equal(Controls.label("fight", "lp", "gamepad"), "X")
		expect.equal(Controls.label("practice", "easy"), "1")
		expect.equal(Controls.label("practice", "leave"), "BACKSPACE")
		expect.equal(Controls.label("fight", "nope"), "")
		expect.equal(Controls.label("nope", "lp"), "")
		expect.equal(Controls.notation.lp, "1")
		expect.equal(Controls.notation.rk, "4")
		expect.equal(Controls.buttons.lk, "LeadKick")
	end)

	test("legends list every action with plain text for both devices", function()
		for _, device in { "keyboard", "gamepad" } do
			local rows = Controls.legend("fight", device)
			expect.truthy(#rows >= 14, device .. " fight legend rows " .. #rows)
			local seen = {}
			for _, row in rows do
				expect.truthy(#row.keys > 0 and #row.text > 0, row.action)
				seen[row.action] = row.keys
			end
			for _, action in { "dash", "backdash", "sidestepIn", "sidestepOut", "crouch", "throw1", "throw2", "breakThrow" } do
				expect.truthy(seen[action] ~= nil, device .. " legend has " .. action)
			end
			expect.truthy(string.find(seen.sidestepOut, "tap", 1, true) ~= nil, "sidestep out says tap")
			expect.truthy(string.find(seen.crouch, "hold", 1, true) ~= nil, "crouch says hold")
		end
		expect.truthy(#Controls.legend("practice") == 8)
	end)

	test("every roster move input renders on keyboard and gamepad and matches its notation", function()
		expect.equal(Controls.formatMoveInput("LP, RP"), "U, I")
		expect.equal(Controls.formatMoveInput("df+RP"), "S+D+I")
		expect.equal(Controls.formatMoveInput("dash+RP"), "D D+I")
		expect.equal(Controls.formatMoveInput("f+LP+LK"), "D+U+J")
		expect.equal(Controls.formatMoveInput("df+RP", "gamepad"), "↘+Y")
		expect.equal(Controls.formatMoveInput("ss+RK"), "W/S+K")
		expect.equal(Controls.notationOf("LP, RP, LK"), "1,2,3")
		expect.equal(Controls.notationOf("dash+RP"), "f,f+2")
		for _, id in Roster.order do
			local char = Roster.get(id)
			for _, key in char.moveOrder do
				local def = char.moves[key]
				for _, device in { "keyboard", "gamepad" } do
					local text = Controls.formatMoveInput(def.input, device)
					expect.truthy(#text > 0, id .. "." .. key)
					for _, raw in { "LP", "RP", "LK", "RK" } do
						expect.falsy(string.find(text, raw, 1, true), id .. "." .. key .. " shows a raw button name on " .. device .. ": " .. text)
					end
				end
				expect.equal(Controls.notationOf(def.input), def.notation, id .. "." .. key .. " notation")
			end
		end
	end)
end
