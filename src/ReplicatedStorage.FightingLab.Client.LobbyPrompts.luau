--!strict
-- Lobby prompts (split out of LobbyUI, round 5): the custom ProximityPrompt style (every FightingLab prompt drawn as
-- an ember-edged glass pill with the interact key glyph from Controls; on touch the pill itself is the button) and the
-- world prompt set (one local "Fight CPU" prompt per duel circle, one per dojo pad, and the Fighter Kiosk prompt).
-- LobbyUI re-exports both (LobbyUI.PromptStyle, LobbyUI.worldPrompts, LobbyUI.PROMPT_ATTRIBUTE).
local ProximityPromptService = game:GetService("ProximityPromptService")

local Client = script.Parent
local UIHelpers = require(Client.UIHelpers)
local UIState = require(Client.UIState)

local T = UIHelpers.Theme
local make, text = UIHelpers.make, UIHelpers.text
local WHITE = Color3.new(1, 1, 1)

local LobbyPrompts = {}
LobbyPrompts.PROMPT_ATTRIBUTE = "FightingLabPrompt"

--------------------------------------------------------------------------------------------------------------------
-- Prompt style: every FightingLab ProximityPrompt (Style = Custom) is drawn as an ember-edged glass pill with the
-- interact key glyph from Controls; on touch the pill itself is the button.
--------------------------------------------------------------------------------------------------------------------
local PromptStyle = {}
LobbyPrompts.PromptStyle = PromptStyle

function PromptStyle.isOurs(prompt: ProximityPrompt): boolean
	return prompt:GetAttribute(LobbyPrompts.PROMPT_ATTRIBUTE) ~= nil or prompt.Name == "ChooseFighter"
end

-- Builds the billboard for one shown prompt; returns a cleanup function.
function PromptStyle.build(prompt: ProximityPrompt, parent: Instance, device: string): () -> ()
	local adornee = prompt.Parent
	if not adornee then return function() end end
	local accent = T.ember
	local kind = prompt:GetAttribute(LobbyPrompts.PROMPT_ATTRIBUTE)
	if kind == "training" then accent = T.cool elseif kind == "versus" then accent = T.warm elseif kind == "kiosk" or prompt.Name == "ChooseFighter" then accent = T.gold end
	local gui: BillboardGui = make("BillboardGui", {
		Name = "FightingLabPrompt", Adornee = adornee, Size = UDim2.fromOffset(320, 72), AlwaysOnTop = true, LightInfluence = 0,
		ResetOnSpawn = false, Active = true, ClipsDescendants = false, MaxDistance = 60,
	})
	-- Pad prompts sit beside the fighter standing on the pad (not over the body); the kiosk prompt stays centred.
	if kind == "cpu" or kind == "training" or kind == "versus" then gui.SizeOffset = Vector2.new(0.62, 0.15) end
	local pill: TextButton = make("TextButton", { Name = "Pill", Text = "", AutoButtonColor = false, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(300, 60), BackgroundColor3 = T.panel, BackgroundTransparency = 0.08, BorderSizePixel = 0, Parent = gui })
	UIHelpers.corner(pill, 6)
	UIHelpers.outline(pill, WHITE, 1, 0.82)
	UIHelpers.gradient(pill, Color3.fromRGB(30, 35, 48), Color3.fromRGB(10, 12, 18), 90)
	make("Frame", { Name = "Edge", BackgroundColor3 = accent, BorderSizePixel = 0, Size = UDim2.new(0, 4, 1, 0), Parent = pill })
	local scale: UIScale = make("UIScale", { Scale = 0.8, Parent = pill })
	local glyphBox = make("Frame", { Name = "Key", BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 0), Size = UDim2.fromOffset(46, 60), Parent = pill })
	UIHelpers.list(glyphBox, true, 0, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	if device == "touch" then
		local tap = make("Frame", { Name = "Tap", BackgroundColor3 = accent, BorderSizePixel = 0, Size = UDim2.fromOffset(40, 40), Parent = glyphBox })
		UIHelpers.corner(tap)
		text(tap, "Label", "TAP", T.heavy, 13, T.ink, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
	else
		local labelText = UIHelpers.keyLabel("lobby", "interact", device)
		if labelText == "" then labelText = UIHelpers.KEY_TEXT[prompt.KeyboardKeyCode.Name] or prompt.KeyboardKeyCode.Name end
		UIHelpers.glyph(glyphBox, labelText, { height = 38, device = device })
	end
	text(pill, "Action", string.upper(prompt.ActionText), T.title, 22, T.text, { Position = UDim2.fromOffset(72, 8), Size = UDim2.new(1, -84, 0, 28), TextTruncate = Enum.TextTruncate.AtEnd })
	text(pill, "Object", prompt.ObjectText, T.medium, 14, accent:Lerp(WHITE, 0.35), { Position = UDim2.fromOffset(73, 35), Size = UDim2.new(1, -84, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd })
	gui.Parent = parent
	UIHelpers.tween(scale, 0.18, { Scale = 1.08 }, Enum.EasingStyle.Back)
	local conns: { RBXScriptConnection } = {}
	table.insert(conns, pill.Activated:Connect(function()
		prompt:InputHoldBegin()
		task.defer(function() prompt:InputHoldEnd() end)
	end))
	table.insert(conns, prompt.Triggered:Connect(function()
		scale.Scale = 0.96
		UIHelpers.tween(scale, 0.16, { Scale = 1.08 }, Enum.EasingStyle.Back)
	end))
	table.insert(conns, prompt:GetPropertyChangedSignal("ActionText"):Connect(function()
		local a = pill:FindFirstChild("Action") :: TextLabel?
		if a then a.Text = string.upper(prompt.ActionText) end
	end))
	table.insert(conns, prompt:GetPropertyChangedSignal("ObjectText"):Connect(function()
		local o = pill:FindFirstChild("Object") :: TextLabel?
		if o then o.Text = prompt.ObjectText end
	end))
	return function()
		for _, c in conns do c:Disconnect() end
		gui:Destroy()
	end
end

-- Live: draws our prompts while shown. Returns a stop function.
function PromptStyle.start(parent: Instance, device: () -> string): () -> ()
	local shown: { [ProximityPrompt]: () -> () } = {}
	local c1 = ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
		if not PromptStyle.isOurs(prompt) then return end
		local old = shown[prompt]
		if old then old() end
		shown[prompt] = PromptStyle.build(prompt, parent, device())
	end)
	local c2 = ProximityPromptService.PromptHidden:Connect(function(prompt: ProximityPrompt)
		local cleanup = shown[prompt]
		shown[prompt] = nil
		if cleanup then cleanup() end
	end)
	return function()
		c1:Disconnect(); c2:Disconnect()
		for _, cleanup in shown do cleanup() end
		table.clear(shown)
	end
end

--------------------------------------------------------------------------------------------------------------------
-- World prompts: one local ProximityPrompt per duel circle ("Fight CPU"), one per dojo pad, and the kiosk prompt (the
-- world's own server prompt when present, restyled locally; else a local one). Enabled per UIState.prompts.
--------------------------------------------------------------------------------------------------------------------
export type WorldPrompts = { sync: (specs: UIState.PromptSet, arenaId: string?, padSide: number?) -> (), all: () -> { [string]: ProximityPrompt }, destroy: () -> () }

local function newPrompt(parent: Instance, name: string, kind: string, distance: number): ProximityPrompt
	local p: ProximityPrompt = make("ProximityPrompt", {
		Name = name, HoldDuration = 0, MaxActivationDistance = distance, RequiresLineOfSight = false, Enabled = false,
		Style = Enum.ProximityPromptStyle.Custom, Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton,
	})
	p:SetAttribute(LobbyPrompts.PROMPT_ATTRIBUTE, kind)
	p.Parent = parent
	return p
end

local function anchorOn(part: BasePart, height: number): Attachment
	local existing = part:FindFirstChild("FightingLabPromptAnchor")
	if existing and existing:IsA("Attachment") then return existing end
	local a: Attachment = make("Attachment", { Name = "FightingLabPromptAnchor" })
	-- Pads are rotated cylinders: place the anchor in world space above the pad centre.
	a.Position = part.CFrame:PointToObjectSpace(part.Position + Vector3.new(0, height, 0))
	a.Parent = part
	return a
end

local function applyKeys(p: ProximityPrompt)
	local kb = UIHelpers.keyCodes("lobby", "interact", "keyboard")[1]
	local gp = UIHelpers.keyCodes("lobby", "interact", "gamepad")[1]
	if kb then p.KeyboardKeyCode = kb end
	if gp then p.GamepadKeyCode = gp end
end

function LobbyPrompts.worldPrompts(world: () -> Instance?): WorldPrompts
	local created: { Instance } = {}
	local kiosk: ProximityPrompt? = nil
	local kioskOwned = false
	local pads: { [string]: ProximityPrompt } = {} -- "<ArenaId>:<side>" -> Fight CPU prompt
	local dojo: { [string]: { ProximityPrompt } } = { training = {}, versus = {} }
	local dojoPads: { [Instance]: ProximityPrompt } = {}
	local lastScan = -math.huge
	local scannedWorld: Instance? = nil
	local function scan()
		local w = world()
		if not w then return end
		if w == scannedWorld and os.clock() - lastScan < 3 then return end
		lastScan = os.clock()
		scannedWorld = w
		local lobby = w:FindFirstChild("Lobby")
		local kioskModel = lobby and lobby:FindFirstChild("FighterKiosk")
		local promptPart = kioskModel and kioskModel:FindFirstChild("PromptPart")
		if promptPart and promptPart:IsA("BasePart") and (not kiosk or not kiosk.Parent) then
			local existing = promptPart:FindFirstChild("ChooseFighter")
			if existing and existing:IsA("ProximityPrompt") then
				kiosk = existing
				kioskOwned = false
			else
				kiosk = newPrompt(promptPart, "ChooseFighter", "kiosk", 10)
				kioskOwned = true
				table.insert(created, kiosk :: Instance)
			end
			local k = kiosk :: ProximityPrompt
			k.Style = Enum.ProximityPromptStyle.Custom
			k.ActionText = UIState.PROMPT_TEXT.kiosk.action
			k.ObjectText = UIState.PROMPT_TEXT.kiosk.object
			applyKeys(k)
		end
		local arenas = w:FindFirstChild("Arenas")
		if not arenas then return end
		for _, arena in arenas:GetChildren() do
			local kind = arena:GetAttribute("Kind")
			if kind == "Practice" then
				for _, spec in { { "PadTraining", "training" }, { "PadCpu", "versus" } } do
					local pad = arena:FindFirstChild(spec[1])
					if pad and pad:IsA("BasePart") and not dojoPads[pad] then
						local mode = pad:GetAttribute("PadMode")
						local id = if mode == "Cpu" then "versus" elseif mode == "Training" then "training" else spec[2]
						local anchor = anchorOn(pad, 3.2)
						local p = newPrompt(anchor, "FightingLab_" .. id, id, 9)
						applyKeys(p)
						table.insert(created, anchor)
						table.insert(dojo[id], p)
						dojoPads[pad] = p
					end
				end
			else
				for side, padName in { "PadP1", "PadP2" } do
					local key = arena.Name .. ":" .. side
					local pad = arena:FindFirstChild(padName)
					if pad and pad:IsA("BasePart") and (not pads[key] or not pads[key].Parent) then
						local anchor = anchorOn(pad, 3.2)
						local p = newPrompt(anchor, "FightingLab_FightCpu", "cpu", 9)
						applyKeys(p)
						table.insert(created, anchor)
						pads[key] = p
					end
				end
			end
		end
	end
	local function set(p: ProximityPrompt, spec: UIState.PromptSpec, enabled: boolean)
		if p.Enabled ~= enabled then p.Enabled = enabled end
		if p.ActionText ~= spec.action then p.ActionText = spec.action end
		if p.ObjectText ~= spec.object then p.ObjectText = spec.object end
	end
	return {
		sync = function(specs: UIState.PromptSet, arenaId: string?, padSide: number?)
			scan()
			if kiosk and kiosk.Parent then set(kiosk, specs.kiosk, specs.kiosk.enabled) end
			for key, p in pads do
				local mine = arenaId ~= nil and key == arenaId .. ":" .. tostring(padSide)
				set(p, specs.cpu, specs.cpu.enabled and mine)
			end
			for _, p in dojo.training do set(p, specs.training, specs.training.enabled) end
			for _, p in dojo.versus do set(p, specs.versus, specs.versus.enabled) end
		end,
		all = function()
			local out: { [string]: ProximityPrompt } = {}
			if kiosk then out.kiosk = kiosk end
			for key, p in pads do out["cpu:" .. key] = p end
			for i, p in dojo.training do out["training:" .. i] = p end
			for i, p in dojo.versus do out["versus:" .. i] = p end
			return out
		end,
		destroy = function()
			if kiosk and not kioskOwned then kiosk.Style = Enum.ProximityPromptStyle.Default; kiosk.Enabled = true end
			for i = #created, 1, -1 do created[i]:Destroy() end
			table.clear(created); table.clear(pads); table.clear(dojoPads)
			table.clear(dojo.training); table.clear(dojo.versus)
			kiosk = nil
		end,
	}
end

return LobbyPrompts
