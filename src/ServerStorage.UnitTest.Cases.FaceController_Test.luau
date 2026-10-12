--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Face = require(ReplicatedStorage:WaitForChild("FightingLab"):WaitForChild("Client"):WaitForChild("FaceController"))
local Runner = require(game:GetService("ServerStorage").UnitTest.RunUnitTest)

local function rigWithFace(): (Model, FaceControls?)
	local model = Instance.new("Model")
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Parent = model
	local ok, controls = pcall(function() return Instance.new("FaceControls") end)
	if ok and controls then
		controls.Parent = head
		return model, controls :: FaceControls
	end
	return model, nil
end

return function(t: Runner.T)
	t.test("fighter states map to readable expressions", function()
		t.expect.equal((Face.expressionFor({ state = "Idle" })), "Focused")
		t.expect.equal((Face.expressionFor({ state = "Active" })), "Shout")
		t.expect.equal((Face.expressionFor({ state = "Hitstun" })), "Pain")
		t.expect.equal((Face.expressionFor({ state = "Blockstun" })), "Grit")
		t.expect.equal((Face.expressionFor({ state = "KO" })), "KO")
		t.expect.equal((Face.expressionFor({ state = "Throw", throw = { role = "Defender" } })), "Pain")
		t.expect.equal((Face.expressionFor({ state = "Idle" }, { phase = "MatchOver", winner = 2, slot = 2 })), "Smile")
		t.expect.equal((Face.expressionFor({ state = "Idle" }, { phase = "MatchOver", winner = 1, slot = 2 })), "Focused")
	end)

	t.test("heads without FaceControls are a silent no-op", function()
		local model = Instance.new("Model")
		local head = Instance.new("Part")
		head.Name = "Head"
		head.Parent = model
		t.expect.falsy(Face.hasFace(model))
		Face.setExpression(model, "Shout", 1)
		Face.updateFromView(model, { state = "Hitstun" }, 1 / 60, nil)
		t.expect.throws(function() Face.setExpression(model, "Nope", 1) end, "unknown expression errors")
		model:Destroy()
	end)

	t.test("expressions write FACS weights and ease back toward focus", function()
		local model, controls = rigWithFace()
		if not controls then
			model:Destroy()
			return -- FaceControls cannot be created in this context; the mapping test above still covers the logic.
		end
		Face.setExpression(model, "Shout", 1)
		t.expect.truthy(controls.JawDrop > 0.3, "shout opens the jaw")
		Face.setExpression(model, "Neutral", 1)
		t.expect.equal(controls.JawDrop, 0)
		Face.updateFromView(model, { state = "Hitstun" }, 1, nil)
		t.expect.truthy(controls.LeftEyeClosed > 0.5, "pain squeezes the eyes shut")
		Face.reset(model)
		t.expect.equal(controls.LeftEyeClosed, 0)
		model:Destroy()
	end)
end
