--!strict
-- Credits data covers every roster fighter; the CREDITS page renders one Row per fighter item and one WorldRow per
-- lobby/arena asset (data.world).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FightingLab = ReplicatedStorage:WaitForChild("FightingLab")
local CreditsScreen = require(FightingLab:WaitForChild("Client"):WaitForChild("CreditsScreen"))
local Credits = require(FightingLab:WaitForChild("Credits")) :: any
local Roster = require(FightingLab:WaitForChild("Roster")) :: any
local Runner = require(game:GetService("ServerStorage").UnitTest.RunUnitTest)

local function printable(s: string): boolean
	return not string.find(s, "[^\32-\126]")
end

return function(t: Runner.T)
	t.test("credits attribute every roster fighter with named creators", function()
		t.expect.equal(#Credits.fighters, #Roster.order)
		local names = {}
		for _, fighter in Credits.fighters do names[string.upper(fighter.name)] = fighter end
		for _, id in Roster.order do
			local fighter = names[string.upper(Roster.get(id).displayName)]
			t.expect.truthy(fighter ~= nil, "credits section for " .. id)
			if fighter then
				t.expect.truthy(#fighter.items > 0, id .. " lists its marketplace items")
				for _, item in fighter.items do
					t.expect.truthy(item.name ~= "" and item.creator ~= "", id .. " item has a name and creator")
					t.expect.truthy(printable(item.name) and printable(item.creator) and printable(item.kind), "in-game credit text is printable ASCII")
				end
			end
		end
		t.expect.truthy(printable(Credits.intro), "intro is printable ASCII")
	end)

	t.test("credits page renders one row per item and scrolls safely", function()
		local holder = Instance.new("Frame")
		local page = CreditsScreen.render(holder)
		local list = page:FindFirstChild("List")
		t.expect.truthy(list ~= nil and list:IsA("ScrollingFrame"), "scrolling list exists")
		local expected = 0
		for _, fighter in Credits.fighters do expected += #fighter.items end
		local rows = 0
		if list then for _, child in list:GetChildren() do if child.Name == "Row" then rows += 1 end end end
		t.expect.equal(rows, expected)
		t.expect.truthy(CreditsScreen.scroll(page, 1) >= 0, "scroll down stays in range")
		t.expect.truthy(CreditsScreen.scroll(page, -1) >= 0, "scroll up stays in range")
		t.expect.truthy(CreditsScreen.hasData(), "credits data module is present")
		holder:Destroy()
	end)

	t.test("lobby and arena assets render as WorldRow entries after the fighters", function()
		-- Generated data: one WorldRow per data.world entry (Creator Store sounds used by the lobby and arenas).
		local holder = Instance.new("Frame")
		local page = CreditsScreen.render(holder)
		local list = page:FindFirstChild("List")
		local world = Credits.world
		local worldRows, lastFighterRow, firstWorldRow = 0, 0, math.huge
		if list then
			for _, child in list:GetChildren() do
				if child.Name == "WorldRow" and child:IsA("TextLabel") then
					worldRows += 1
					firstWorldRow = math.min(firstWorldRow, child.LayoutOrder)
				elseif child.Name == "Row" and child:IsA("TextLabel") then
					lastFighterRow = math.max(lastFighterRow, child.LayoutOrder)
				end
			end
		end
		if world and #world > 0 then
			t.expect.equal(worldRows, #world, "one WorldRow per lobby/arena asset")
			t.expect.truthy(firstWorldRow > lastFighterRow, "LOBBY & ARENAS comes after the fighters")
			local header = list and list:FindFirstChild("WorldHeader")
			t.expect.equal(header and (header :: TextLabel).Text, "LOBBY & ARENAS")
			for _, item in world do
				t.expect.truthy(item.name ~= "" and item.creator ~= "", "world credit has a name and creator")
				t.expect.truthy(printable(item.name) and printable(item.creator), "world credit text is printable ASCII")
			end
		else
			t.expect.equal(worldRows, 0, "no world section without world data")
		end
		holder:Destroy()

		-- Injected data: the section renders whenever data.world is non-empty and is skipped when it is missing.
		local fake = {
			intro = "Test credits.",
			fighters = { { name = "KAEL", items = { { name = "Glove", creator = "Maker", kind = "Layered gloves", id = 1 } } } },
			external = {},
			world = {
				{ name = "Harbor Loop", creator = "Sound Studio", kind = "Audio", usedFor = "Harbor ambience", id = 2 },
				{ name = "Wind Loop", creator = "Sound Studio", kind = "Audio", usedFor = "Summit ambience", id = 3 },
			},
		}
		local fakeHolder = Instance.new("Frame")
		local fakeList = CreditsScreen.render(fakeHolder, nil, fake :: any):FindFirstChild("List")
		local counts: { [string]: number } = {}
		if fakeList then for _, child in fakeList:GetChildren() do counts[child.Name] = (counts[child.Name] or 0) + 1 end end
		t.expect.equal(counts.WorldRow, 2, "world rows render when data.world is non-empty")
		t.expect.equal(counts.Row, 1, "fighter rows are counted separately from world rows")
		local first = fakeList and fakeList:FindFirstChild("WorldRow") :: TextLabel?
		t.expect.truthy(first ~= nil and string.find(first.Text, "Sound Studio", 1, true) ~= nil, "world row names its creator")
		fake.world = nil
		local emptyHolder = Instance.new("Frame")
		local emptyList = CreditsScreen.render(emptyHolder, nil, fake :: any):FindFirstChild("List")
		t.expect.equal(emptyList and emptyList:FindFirstChild("WorldHeader"), nil, "no LOBBY & ARENAS section without world data")
		fakeHolder:Destroy()
		emptyHolder:Destroy()
	end)
	t.test("motion capture & additional credits wrap long attributions instead of truncating", function()
		local cmu = "The data used in this project was obtained from mocap.cs.cmu.edu. The database was created with funding from NSF EIA-0196217."
		local fake = {
			intro = "Test credits.",
			fighters = { { name = "KAEL", items = { { name = "Glove", creator = "Maker", kind = "Layered gloves", id = 1 } } } },
			external = {
				{ credit = "ACCAD Open Motion Project, The Ohio State University", license = "CC BY 3.0", usedFor = "Strikes, kicks and hit reactions" },
				{ credit = cmu, license = "CMU Graphics Lab Motion Capture Database terms", usedFor = "Locomotion" },
				{ credit = "Quaternius Universal Animation Library", license = "CC0", usedFor = "Getups" },
			},
		}
		local holder = Instance.new("Frame")
		holder.Size = UDim2.fromOffset(600, 400)
		local page = CreditsScreen.render(holder, nil, fake :: any)
		local list = page:FindFirstChild("List")
		local header = list and list:FindFirstChild("ExternalHeader") :: TextLabel?
		t.expect.equal(header and header.Text, CreditsScreen.EXTERNAL_HEADER)
		t.expect.equal(CreditsScreen.EXTERNAL_HEADER, "MOTION CAPTURE & ADDITIONAL CREDITS")
		local rows: { TextLabel } = {}
		if list then for _, child in list:GetChildren() do if child.Name == "External" and child:IsA("TextLabel") then table.insert(rows, child) end end end
		t.expect.equal(#rows, 3, "one External row per entry")
		local fighterRow = 0
		if list then for _, child in list:GetChildren() do if child.Name == "Row" then fighterRow = math.max(fighterRow, (child :: any).LayoutOrder) end end end
		for _, row in rows do
			t.expect.truthy(row.TextWrapped, "external rows wrap")
			t.expect.equal(row.TextTruncate, Enum.TextTruncate.None, "external rows are never cut off")
			t.expect.equal(row.AutomaticSize, Enum.AutomaticSize.Y, "external rows grow to fit their lines")
			t.expect.truthy(row.LayoutOrder > fighterRow, "the section comes after the fighters")
		end
		local found = false
		for _, row in rows do if string.find(row.Text, cmu, 1, true) then found = true end end
		t.expect.truthy(found, "the full CMU acknowledgement is shown")
		t.expect.truthy(header ~= nil and header.TextColor3 ~= nil)
		fake.external = {}
		local emptyHolder = Instance.new("Frame")
		local emptyList = CreditsScreen.render(emptyHolder, nil, fake :: any):FindFirstChild("List")
		t.expect.equal(emptyList and emptyList:FindFirstChild("ExternalHeader"), nil, "no section without external credits")
		holder:Destroy(); emptyHolder:Destroy()
	end)
end
