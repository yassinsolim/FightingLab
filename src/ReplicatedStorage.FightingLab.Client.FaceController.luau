--!strict
-- Facial expressions for fighters with dynamic heads (a FaceControls instance under the head).
-- Fights: updateFromView picks an expression from the fighter's state and eases toward it every frame.
-- Menus: setExpression snaps a clone to a named expression. Heads without FaceControls are a silent no-op.
local M = {}

type Weights = { [string]: number }
type FaceState = { controls: FaceControls?, current: Weights, holdName: string?, holdUntil: number }

local function both(name: string, v: number, out: Weights)
	out["Left" .. name] = v
	out["Right" .. name] = v
end

local function build(spec: (out: Weights) -> ()): Weights
	local out: Weights = {}
	spec(out)
	return out
end

-- FACS weights (0..1) per named expression; tuned to read at fighting-game camera distance.
M.Expressions = {
	Neutral = {},
	Focused = build(function(o)
		both("BrowLowerer", 0.38, o); o.Corrugator = 0.28; both("EyeClosed", 0.12, o); o.LipPresser = 0.3; o.ChinRaiser = 0.18
	end),
	Grit = build(function(o)
		both("BrowLowerer", 0.6, o); o.Corrugator = 0.45; both("EyeClosed", 0.22, o); both("LipStretcher", 0.5, o)
		both("UpperLipRaiser", 0.28, o); o.ChinRaiser = 0.3; both("NoseWrinkler", 0.22, o)
	end),
	Shout = build(function(o)
		both("BrowLowerer", 0.65, o); o.Corrugator = 0.5; both("EyeClosed", 0.16, o); o.JawDrop = 0.5; both("LipStretcher", 0.42, o)
		both("UpperLipRaiser", 0.48, o); both("LowerLipDepressor", 0.38, o); both("NoseWrinkler", 0.28, o)
	end),
	Pain = build(function(o)
		both("EyeClosed", 0.78, o); both("BrowLowerer", 0.5, o); both("InnerBrowRaiser", 0.4, o); both("NoseWrinkler", 0.55, o)
		both("UpperLipRaiser", 0.42, o); o.JawDrop = 0.26; both("LipStretcher", 0.58, o); both("CheekRaiser", 0.42, o)
	end),
	KO = build(function(o)
		both("EyeClosed", 0.96, o); o.JawDrop = 0.32; both("BrowLowerer", 0.08, o)
	end),
	Smile = build(function(o)
		o.LeftLipCornerPuller = 0.68; o.RightLipCornerPuller = 0.4; both("CheekRaiser", 0.32, o); both("EyeClosed", 0.1, o)
		both("BrowLowerer", 0.12, o); both("Dimpler", 0.2, o)
	end),
}

-- Every property any expression touches; written back to 0 when the active expression does not use it.
local ALL: { string } = {}
do
	local seen: { [string]: boolean } = {}
	for _, weights in M.Expressions do
		for name in weights do
			if not seen[name] then seen[name] = true; table.insert(ALL, name) end
		end
	end
	table.sort(ALL)
end

-- Property names are validated once against a real FaceControls so a name the engine lacks is skipped, not fatal.
local validProps: { string }? = nil
local function propsFor(controls: FaceControls): { string }
	local cached = validProps
	if cached then return cached end
	local valid = {}
	for _, name in ALL do
		local ok, value = pcall(function() return (controls :: any)[name] end)
		if ok and typeof(value) == "number" then table.insert(valid, name) end
	end
	validProps = valid
	return valid
end

local states: { [Model]: FaceState } = setmetatable({}, { __mode = "k" }) :: any

local function findControls(model: Model): FaceControls?
	local head = model:FindFirstChild("Head")
	if not head then return nil end
	local controls = head:FindFirstChildWhichIsA("FaceControls", true)
	return controls :: FaceControls?
end

local function stateFor(model: Model): FaceState
	local s = states[model]
	if s and (s.controls == nil or (s.controls :: FaceControls).Parent ~= nil) then return s end
	s = { controls = findControls(model), current = {}, holdName = nil, holdUntil = 0 }
	states[model] = s
	return s :: FaceState
end

local function write(s: FaceState, target: Weights, weight: number, alpha: number)
	local controls = s.controls
	if not controls then return end
	for _, name in propsFor(controls) do
		local goal = (target[name] or 0) * weight
		local cur = s.current[name] or 0
		local nextValue = cur + (goal - cur) * alpha
		if math.abs(nextValue - cur) > 0.002 or (alpha >= 1 and cur ~= goal) then
			s.current[name] = nextValue
			pcall(function() (controls :: any)[name] = math.clamp(nextValue, 0, 1) end)
		end
	end
end

function M.hasFace(model: Model): boolean
	return stateFor(model).controls ~= nil
end

-- Snap a model to an expression (menus, previews). weight scales the whole expression.
function M.setExpression(model: Model, name: string, weight: number?)
	local target = M.Expressions[name]
	if not target then error("FaceController: unknown expression " .. tostring(name)) end
	write(stateFor(model), target, math.clamp(weight or 1, 0, 1), 1)
end

-- Expression for a fighter's simulation state; context = { phase, winner, slot } from the render frame.
function M.expressionFor(view: any, context: any?): (string, number)
	local s = view and view.state or "Idle"
	local phase = context and context.phase
	if (phase == "RoundOver" or phase == "MatchOver") and context and context.winner and context.slot then
		if s == "KO" then return "KO", 1 end
		if context.winner == context.slot then return "Smile", 1 end
	end
	if s == "KO" then return "KO", 1 end
	if s == "Hitstun" or s == "Stagger" or s == "Airborne" or s == "Landing" then return "Pain", 1 end
	if s == "Throw" then
		if view.throw and view.throw.role == "Defender" then return "Pain", 1 end
		return "Shout", 0.85
	end
	if s == "Startup" or s == "Active" then return "Shout", 0.9 end
	if s == "Block" or s == "Blockstun" or s == "Getup" or s == "Recovery" then return "Grit", 0.85 end
	return "Focused", 1
end

-- Per-frame update for in-fight rigs: eases quickly into reactions and relaxes more slowly back to focus.
function M.updateFromView(model: Model, view: any, dt: number, context: any?)
	local s = stateFor(model)
	if not s.controls then return end
	local name, weight = M.expressionFor(view, context)
	local now = os.clock()
	-- Pain and shouts hold briefly so a 3-frame hit still registers on the face.
	if name == "Pain" or name == "Shout" then
		s.holdName = name; s.holdUntil = now + (if name == "Pain" then 0.28 else 0.18)
	elseif s.holdName and now < s.holdUntil and name ~= "KO" and name ~= "Smile" then
		name = s.holdName :: string
	end
	local rate = if name == "Pain" or name == "Shout" or name == "KO" then 26 else 9
	write(s, M.Expressions[name], weight, 1 - math.exp(-rate * math.max(dt, 0)))
end

function M.reset(model: Model)
	local s = states[model]
	if s then write(s, M.Expressions.Neutral, 1, 1) end
	states[model] = nil
end

return M
