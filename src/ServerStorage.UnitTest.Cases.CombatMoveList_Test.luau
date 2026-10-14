--!strict
-- Round 6 move list (Client.MoveList): grouped moves (each once), the COMBOS section/page and the new property chips.
local RS = game:GetService("ReplicatedStorage")
local Lab = RS:WaitForChild("FightingLab")
local Client = Lab:WaitForChild("Client")
local Roster = require(Lab:WaitForChild("Roster"))
local MoveList = require(Client:WaitForChild("MoveList"))

local function count(root: Instance, prefix: string): number
	local n = 0
	for _, child in root:GetChildren() do
		if string.sub(child.Name, 1, #prefix) == prefix then n += 1 end
	end
	return n
end

return function(t)
	local test, expect = t.test, t.expect

	test("moves are grouped signature, strings, launchers, lows, strikes, throws, Ultimate, each move once", function()
		local rank = { Signature = 1, Strings = 2, Launchers = 3, Lows = 4, Strikes = 5, Throws = 6, Ultimate = 7 }
		for _, id in Roster.order do
			local def = Roster.get(id)
			local seen: { [string]: boolean } = {}
			local total, last = 0, 0
			local groups = MoveList.groups(def)
			for _, g in groups do
				expect.truthy(rank[g.id] ~= nil and rank[g.id] > last, id .. " group order " .. g.id)
				last = rank[g.id]
				for _, key in g.keys do
					expect.falsy(seen[key], id .. " " .. key .. " listed once")
					seen[key] = true
					total += 1
				end
			end
			expect.equal(total, #def.moveOrder, id .. " every move listed")
			expect.equal(groups[1].id, "Signature", id .. " signature first")
			expect.equal(groups[#groups].id, "Ultimate", id .. " Ultimate last")
			expect.equal(groups[#groups].keys[1], "Ultimate")
			for _, key in groups[1].keys do
				local mv = def.moves[key]
				expect.truthy(mv.toStance or mv.stance or mv.props.catch or mv.chainFrom, id .. " " .. key .. " belongs to the signature")
			end
		end
	end)

	test("property chips and descriptions name the round 6 mechanics", function()
		for _, id in Roster.order do
			local def = Roster.get(id)
			for _, key in def.moveOrder do
				local mv = def.moves[key]
				local props = MoveList.properties(mv)
				if mv.tumble then expect.truthy(table.find(props, "TUMBLE") ~= nil, id .. " " .. key .. " TUMBLE") end
				if mv.cinematic then expect.truthy(table.find(props, "ULTIMATE") ~= nil, id .. " Ultimate chip") end
				if mv.toStance then expect.truthy(table.find(props, "STANCE") ~= nil, id .. " stance chip") end
				if mv.props.catch then expect.truthy(table.find(props, "CATCH") ~= nil, id .. " catch chip") end
				if mv.height == "Throw" then expect.truthy(table.find(props, "THROW") ~= nil, id .. " throw chip") end
				expect.truthy(#MoveList.describe(mv, def) > 10, id .. " " .. key .. " description")
			end
			local picks = MoveList.signature(def)
			expect.equal(#picks, 3, id .. " three highlight moves")
			expect.truthy(table.find(picks, "Ultimate") ~= nil, id .. " highlights its Ultimate")
		end
	end)

	test("fillList renders group headers, every move and the COMBOS section; fillCombos renders the combo page", function()
		local scroll = Instance.new("ScrollingFrame")
		for _, id in Roster.order do
			local def = Roster.get(id)
			local rows = MoveList.fillList(scroll, def, nil, { rowHeight = 54 })
			expect.equal(rows, #def.moveOrder, id .. " move rows")
			expect.equal(count(scroll, "Move_"), #def.moveOrder, id .. " Move_ rows")
			local frames = 0
			for _, child in scroll:GetChildren() do if child:IsA("Frame") then frames += 1 end end
			expect.equal(frames, #def.moveOrder, id .. " only move rows are Frames (the lobby counts them)")
			expect.equal(count(scroll, "Combo_"), #def.combos, id .. " combo rows")
			expect.truthy(scroll:FindFirstChild("Group_Signature") ~= nil and scroll:FindFirstChild("Group_Ultimate") ~= nil and scroll:FindFirstChild("Group_Combos") ~= nil, id .. " headers")
			local ult = scroll:FindFirstChild("Move_Ultimate") :: Frame
			expect.truthy(ult ~= nil and string.find((ult:FindFirstChild("Name") :: TextLabel).Text, string.upper(def.moves.Ultimate.name), 1, true) ~= nil, id .. " Ultimate row shows its name")
			local combos = MoveList.fillCombos(scroll, def)
			expect.equal(combos, #def.combos, id .. " combo page")
			expect.equal(count(scroll, "Move_"), 0, id .. " the combo page has no move rows")
			for i, combo in def.combos do
				local row = scroll:FindFirstChild("Combo_" .. string.gsub(combo.name, "%W", "")) :: Frame
				expect.truthy(row ~= nil, id .. " " .. combo.name)
				expect.equal((row:FindFirstChild("Damage") :: TextLabel).Text, tostring(combo.damage) .. " DMG")
				-- Round 7: the measured difficulty in words, and the easy first route marked as the place to start.
				expect.equal((row:FindFirstChild("Difficulty") :: TextLabel).Text, MoveList.difficultyText(combo.difficulty), id .. " " .. combo.name .. " difficulty")
				local start = (row:FindFirstChild("Title") :: Frame):FindFirstChild("Start")
				if i == 1 then
					expect.truthy(start ~= nil, id .. " the first route is marked START HERE")
				else
					expect.truthy(start == nil, id .. " " .. combo.name .. " is not marked as the start")
				end
			end
		end
		MoveList.fillList(scroll, Roster.get("Kael"), nil, { combos = false })
		expect.equal(count(scroll, "Combo_"), 0, "combos can be left out")
		scroll:Destroy()
	end)

	test("combo difficulty reads as a word and a 1-5 score", function()
		expect.equal(MoveList.difficultyText(1), "EASY  1/5")
		expect.equal(MoveList.difficultyText(2), "MEDIUM  2/5")
		expect.equal(MoveList.difficultyText(5), "EXPERT  5/5")
		expect.equal(MoveList.difficultyText(9), "EXPERT  5/5", "clamped")
		expect.equal(MoveList.difficultyText(nil), "EASY  1/5", "missing labels read as easy")
	end)
end
