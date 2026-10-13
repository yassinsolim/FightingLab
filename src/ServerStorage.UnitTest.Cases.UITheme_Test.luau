--!strict
-- Round 6 look: the shared "Ember & Steel" UI theme (UIHelpers buttons, panels, slanted caps and segment bars, the same
-- angled language as the fight HUD) and the fighter select's layout and transitions (header, roster grid, selection
-- lift, stat values, a camera fit that keeps every fighter's head in frame).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lab = ReplicatedStorage:WaitForChild("FightingLab")
local Client = Lab:WaitForChild("Client")
local UIHelpers = require(Client:WaitForChild("UIHelpers"))
local FighterSelect = require(Client:WaitForChild("FighterSelect"))
local SelectScene = require(Client:WaitForChild("SelectScene"))
local Roster = require(Lab:WaitForChild("Roster"))

local function holder(): ScreenGui
	local g = Instance.new("ScreenGui")
	g.Name = "UIThemeTest"
	return g
end

-- Mounts a fighter select without the 3D studio (no camera, no previews) on a throwaway ScreenGui.
local function mountSelect(current: string?): (FighterSelect.Controller, Folder, { string })
	local parent = Instance.new("Folder")
	parent.Name = "UIThemeSelect"
	local confirmed: { string } = {}
	local ctl = FighterSelect.mount({
		parent = parent, previews = false, live = false,
		canSelect = function() return true, nil end,
		currentFighter = function() return current end,
		onConfirm = function(id: string) table.insert(confirmed, id) end,
	})
	return ctl, parent, confirmed
end

-- Vertical / horizontal screen position (0..1) of a world point for a camera CFrame and vertical FOV.
local function project(cf: CFrame, fov: number, aspect: number, p: Vector3): (number, number, boolean)
	local v = cf:PointToObjectSpace(p)
	if v.Z >= 0 then return 0, 0, false end
	local tanV = math.tan(math.rad(fov) * 0.5)
	local x = (v.X / -v.Z) / (tanV * aspect)
	local y = (v.Y / -v.Z) / tanV
	return (x + 1) * 0.5, (1 - y) * 0.5, true
end

return function(t)
	t.test("theme: buttons carry the slanted notch, primaries the sheen; it follows focus, selection and enabled", function()
		local g = holder()
		local primary = UIHelpers.button(g, "Go", { text = "GO", primary = true })
		local plain = UIHelpers.button(g, "Pick", { text = "PICK" })
		local pNotch = primary.button:FindFirstChild("Notch") :: Frame?
		local notch = plain.button:FindFirstChild("Notch") :: Frame?
		t.expect.truthy(pNotch ~= nil and pNotch.Visible, "a primary button shows its notch")
		t.expect.truthy(primary.button:FindFirstChild("Sheen") ~= nil, "a primary button has the light sweep")
		t.expect.truthy(plain.button:FindFirstChild("Sheen") == nil, "plain buttons stay flat")
		t.expect.truthy(notch ~= nil and not notch.Visible, "a plain button hides its notch at rest")
		plain.setFocused(true)
		t.expect.truthy(notch and notch.Visible, "focus shows the notch")
		plain.setFocused(false)
		plain.setSelected(true)
		t.expect.truthy(notch and notch.Visible, "selection shows the notch")
		plain.setAccent(Color3.fromRGB(64, 200, 255))
		t.expect.truthy(notch and notch.BackgroundColor3 == Color3.fromRGB(64, 200, 255), "the notch takes the button's accent")
		plain.setEnabled(false)
		t.expect.truthy(notch and not notch.Visible, "a disabled button hides the notch")
		primary.setEnabled(false)
		t.expect.truthy(pNotch and not pNotch.Visible, "a disabled primary hides the notch too")
		local corner = primary.button:FindFirstChildOfClass("UICorner")
		t.expect.truthy(corner ~= nil and corner.CornerRadius.Offset <= 3, "crisp corners")
		g:Destroy()
	end)

	t.test("theme: panels keep a hairline that turns ember at one corner, without adding layout children", function()
		local g = holder()
		local panel = UIHelpers.panel(g, "Panel")
		local stroke = panel:FindFirstChildOfClass("UIStroke")
		local accent = stroke and stroke:FindFirstChild("CornerAccent")
		t.expect.truthy(accent ~= nil and accent:IsA("UIGradient"), "an ember gradient on the panel's stroke")
		local seq = (accent :: UIGradient).Color.Keypoints
		local first = seq[1].Value
		t.expect.truthy(first.R > first.B, "the corner colour is ember (warm)")
		local guiChildren = 0
		for _, c in panel:GetChildren() do if c:IsA("GuiObject") then guiChildren += 1 end end
		t.expect.equal(guiChildren, 0, "no extra frames: callers' list layouts stay untouched")
		g:Destroy()
	end)

	t.test("theme: slant caps split on the right diagonal and segment bars light whole parallelograms", function()
		local g = holder()
		for _, case in { { "TL", false }, { "BR", false }, { "TR", true }, { "BL", true } } do
			local cap = UIHelpers.slantCap(g, "Cap" .. case[1], 12, 20, case[1], Color3.new(1, 0, 0))
			local grad = cap:FindFirstChildOfClass("UIGradient")
			t.expect.truthy(grad ~= nil, "cap " .. case[1] .. " has its cut")
			local expectAngle = math.deg(math.atan2(12, 20))
			local rot = (grad :: UIGradient).Rotation
			t.expect.truthy(math.abs(math.abs(rot) - expectAngle) < 0.01, "cut angle follows the cap's proportions")
			t.expect.equal(rot < 0, case[2], "cap " .. case[1] .. " uses the matching diagonal")
		end
		local bar, set, recolor = UIHelpers.segmentBar(g, "Bar", 10, Color3.new(1, 1, 1), { Size = UDim2.fromOffset(200, 14) })
		set(0.4, false)
		local lit = 0
		for i = 1, 10 do
			local seg = bar:FindFirstChild("S" .. i) :: Frame
			local body = seg:FindFirstChild("Body") :: Frame
			local capL = seg:FindFirstChild("CapL") :: Frame
			local capR = seg:FindFirstChild("CapR") :: Frame
			t.expect.truthy(body ~= nil and capL ~= nil and capR ~= nil, "segment " .. i .. " is a parallelogram")
			t.expect.equal(body.BackgroundTransparency, capL.BackgroundTransparency, "caps light with their body")
			t.expect.equal(body.BackgroundTransparency, capR.BackgroundTransparency, "caps light with their body")
			if body.BackgroundTransparency == 0 then lit += 1 end
		end
		t.expect.equal(lit, 4)
		recolor(Color3.fromRGB(10, 20, 30))
		local s1 = bar:FindFirstChild("S1") :: Frame
		t.expect.equal((s1:FindFirstChild("CapR") :: Frame).BackgroundColor3, Color3.fromRGB(10, 20, 30))
		g:Destroy()
	end)

	t.test("fighter select: header, counter, a 2-column roster grid and the info column", function()
		local ctl, parent = mountSelect("Kael")
		ctl.open()
		t.expect.truthy(ctl.isOpen())
		local body = (ctl.gui :: any).Stage.Body
		t.expect.equal((body:FindFirstChild("Tag") :: TextLabel).Text, "SELECT YOUR FIGHTER")
		t.expect.equal((body:FindFirstChild("Count") :: TextLabel).Text, string.format("01 / %02d", #Roster.order))
		local grid = body:FindFirstChild("Roster") :: Frame
		t.expect.truthy(grid ~= nil, "roster grid")
		local xs, ys = {}, {}
		for i, id in Roster.order do
			local tile = grid:FindFirstChild("Tile_" .. id) :: TextButton
			t.expect.truthy(tile ~= nil, "a portrait card for " .. id)
			t.expect.truthy(tile:FindFirstChild("Bust") ~= nil and tile:FindFirstChild("Cover") ~= nil, "portrait viewport under its cover")
			xs[tile.Position.X.Offset] = true
			ys[tile.Position.Y.Offset] = true
			local _ = i
		end
		local nx, ny = 0, 0
		for _ in xs do nx += 1 end
		for _ in ys do ny += 1 end
		t.expect.truthy(nx <= 3, "two columns (plus the lifted selection)")
		t.expect.equal(ny, math.ceil(#Roster.order / 2), "rows of two")
		local info = body:FindFirstChild("Info") :: Frame
		local def = Roster.get("Kael")
		t.expect.equal((info:FindFirstChild("Name") :: TextLabel).Text, def.displayName)
		local chip = info:FindFirstChild("StyleChip", true)
		t.expect.truthy(chip ~= nil, "the fighting style sits on a slanted chip")
		local values = 0
		for _, d in info:GetDescendants() do
			if d:IsA("TextLabel") and d.Name == "Value" then
				local n = tonumber(d.Text)
				t.expect.truthy(n ~= nil and n >= 1 and n <= 10, "stat values read 1..10")
				values += 1
			end
		end
		t.expect.equal(values, 4, "four stats with their values")
		ctl.destroy()
		parent:Destroy()
	end)

	t.test("fighter select: the ROSTER label reads on any studio light (white on its own dark plate)", function()
		local ctl, parent = mountSelect("Kael")
		ctl.open()
		local label = (ctl.gui :: any).Stage.Body:FindFirstChild("RosterTitle") :: TextLabel
		t.expect.truthy(label ~= nil and label:IsA("TextLabel"), "roster label")
		t.expect.equal(label.Text, "ROSTER")
		t.expect.truthy(label.BackgroundTransparency <= 0.1, "an opaque plate behind the text, not the 3D studio")
		local function lum(c: Color3): number
			local function ch(v: number): number return if v <= 0.03928 then v / 12.92 else ((v + 0.055) / 1.055) ^ 2.4 end
			return 0.2126 * ch(c.R) + 0.7152 * ch(c.G) + 0.0722 * ch(c.B)
		end
		local a, b = lum(label.TextColor3), lum(label.BackgroundColor3)
		local ratio = (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05)
		t.expect.truthy(ratio >= 7, string.format("text / plate contrast %.1f:1", ratio))
		ctl.destroy()
		parent:Destroy()
	end)

	t.test("fighter select transitions: the selection lifts its card, shows its corner and updates the counter", function()
		local ctl, parent, confirmed = mountSelect("Kael")
		ctl.open()
		local grid = (ctl.gui :: any).Stage.Body.Roster
		local function card(id: string): TextButton return grid:FindFirstChild("Tile_" .. id) end
		local first, second = Roster.order[1], Roster.order[2]
		t.expect.truthy((card(first):FindFirstChild("Corner") :: Frame).Visible, "the selected card shows its accent corner")
		t.expect.falsy((card(second):FindFirstChild("Corner") :: Frame).Visible)
		local restX = card(second).Position.X.Offset
		t.expect.truthy(ctl.handleKey(Enum.KeyCode.Right))
		t.expect.equal(ctl.selected(), second)
		task.wait(0.45)
		t.expect.truthy(card(second).Position.X.Offset < restX, "the new selection lifts out of the grid")
		t.expect.truthy((card(second):FindFirstChild("Corner") :: Frame).Visible)
		t.expect.falsy((card(first):FindFirstChild("Corner") :: Frame).Visible, "the old selection settles back")
		local body = (ctl.gui :: any).Stage.Body
		t.expect.equal((body:FindFirstChild("Count") :: TextLabel).Text, string.format("02 / %02d", #Roster.order))
		local name = body.Info:FindFirstChild("Name") :: TextLabel
		t.expect.equal(name.Text, Roster.get(second).displayName)
		t.expect.equal(name.Position, UDim2.fromOffset(0, 0), "the name slide-in has landed")
		t.expect.equal(name.TextTransparency, 0)
		-- gamepad and the other browse keys still work, and confirming reports the pick
		t.expect.truthy(ctl.handleKey(Enum.KeyCode.DPadLeft))
		t.expect.equal(ctl.selected(), first)
		t.expect.truthy(ctl.handleKey(Enum.KeyCode.S))
		t.expect.equal(ctl.selected(), second)
		t.expect.truthy(ctl.confirm())
		t.expect.equal(confirmed[1], second)
		ctl.destroy()
		parent:Destroy()
	end)

	t.test("fighter select: the template's Signature look note shows under the tagline, hidden without it", function()
		local folder = Instance.new("Folder")
		local a = Instance.new("Model"); a.Name = "Kael"; a:SetAttribute("Signature", "  White tape over the glove cuffs "); a.Parent = folder
		local b = Instance.new("Model"); b.Name = "Sierra"; b:SetAttribute("Signature", "   "); b.Parent = folder
		local c = Instance.new("Model"); c.Name = "Lumi"; c:SetAttribute("Signature", 12); c.Parent = folder
		t.expect.equal(FighterSelect.signatureOf("Kael", folder), "White tape over the glove cuffs", "trimmed")
		t.expect.equal(FighterSelect.signatureOf("Sierra", folder), nil, "blank text")
		t.expect.equal(FighterSelect.signatureOf("Lumi", folder), nil, "not a string")
		t.expect.equal(FighterSelect.signatureOf("Goran", folder), nil, "no template")
		folder:Destroy()
		-- the real select: the line follows the template attribute (set for the test, then put back)
		local templates = Lab:FindFirstChild("Characters")
		local first, second = Roster.order[1], Roster.order[2]
		local tFirst = templates and templates:FindFirstChild(first)
		local tSecond = templates and templates:FindFirstChild(second)
		local saved1 = tFirst and tFirst:GetAttribute("Signature")
		local saved2 = tSecond and tSecond:GetAttribute("Signature")
		local ok, err = pcall(function()
			if tFirst then tFirst:SetAttribute("Signature", "Test look note") end
			if tSecond then tSecond:SetAttribute("Signature", nil) end
			local ctl, parent = mountSelect(first)
			ctl.open()
			local info = (ctl.gui :: any).Stage.Body.Info
			local note = info:FindFirstChild("LookNote") :: Frame
			t.expect.truthy(note ~= nil, "the look note line exists")
			if tFirst then
				t.expect.truthy(note.Visible, "shown when the template carries a note")
				t.expect.equal((note:FindFirstChild("Text") :: TextLabel).Text, "Test look note")
			end
			ctl.select(second)
			t.expect.falsy(note.Visible, "hidden for a template without the attribute")
			ctl.destroy()
			parent:Destroy()
		end)
		if tFirst then tFirst:SetAttribute("Signature", saved1) end
		if tSecond then tSecond:SetAttribute("Signature", saved2) end
		if not ok then error(err, 0) end
	end)

	t.test("select camera: every fighter height stays whole at rest and keeps the head in a push", function()
		local aspect = 16 / 9
		for _, h in { 4.6, 5.6, 6.8, 7.6 } do
			for _, push in { 0, 0.35, 1 } do
				local cf, fov = SelectScene.cameraFor(1.3, aspect, push, h)
				local base = SelectScene.ORIGIN + Vector3.new(0, SelectScene.platformY() - SelectScene.ORIGIN.Y, 0)
				local head = base + Vector3.new(0, h, 0)
				local _, headY, front = project(cf, fov, aspect, head)
				t.expect.truthy(front, "fighter in front of the camera")
				t.expect.truthy(headY > 0.01, string.format("head of a %.1f stud fighter inside the frame at push %.2f (y=%.3f)", h, push, headY))
				if push == 0 then
					local x, feetY = project(cf, fov, aspect, base)
					t.expect.truthy(feetY < 0.99, string.format("feet of a %.1f stud fighter inside the frame at rest (y=%.3f)", h, feetY))
					t.expect.truthy(math.abs(x - SelectScene.SCREEN_X) < 0.06, "the fighter stands at SCREEN_X")
				end
			end
		end
		-- without a height the legacy framing still answers
		local cf, fov = SelectScene.cameraFor(0, aspect, 0)
		t.expect.truthy(typeof(cf) == "CFrame" and fov > 10)
	end)
end
