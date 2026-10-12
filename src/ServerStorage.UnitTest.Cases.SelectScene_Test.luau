--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lab = ReplicatedStorage:WaitForChild("FightingLab")
local Client = Lab:WaitForChild("Client")
local SelectScene = require(Client:WaitForChild("SelectScene"))
local Roster = require(Lab:WaitForChild("Roster"))
local Runner = require(game:GetService("ServerStorage").UnitTest.RunUnitTest)

return function(t: Runner.T)
	t.test("cursor wrapping covers roster plus random", function()
		local count = #Roster.order + 1
		t.expect.equal(SelectScene._wrapCursor(1, count), 1)
		t.expect.equal(SelectScene._wrapCursor(0, count), count)
		t.expect.equal(SelectScene._wrapCursor(count + 1, count), 1)
	end)

	t.test("CPU roulette visibly cycles and lands on chosen index", function()
		local seq = SelectScene._roulette(2, #Roster.order, 4)
		t.expect.equal(seq[#seq], 4)
		t.expect.truthy(#seq >= 8)
		local varied = false
		for i = 2, #seq - 1 do
			if seq[i] ~= seq[1] then varied = true end
		end
		t.expect.truthy(varied, "roulette should visibly change before final pick")
	end)

	t.test("module require has no workspace side effects", function()
		t.expect.equal(SelectScene.isActive(), false)
		t.expect.equal(SelectScene.debugInstanceCount(), 0)
		local before = #workspace:GetChildren()
		require(Client.SelectScene)
		t.expect.equal(#workspace:GetChildren(), before)
	end)
end
