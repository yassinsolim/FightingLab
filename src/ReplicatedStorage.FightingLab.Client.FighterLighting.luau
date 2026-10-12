--!strict
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

-- Key/fill/rim strengths come from LightingProfile so readability tuning lives in one place.
local profileModule = script.Parent:FindFirstChild("LightingProfile")
local profile: any = if profileModule and profileModule:IsA("ModuleScript") then require(profileModule) else nil
local fighterLight: any = if profile and profile.data then profile.data.fighterLighting else nil
local KEY = if fighterLight and fighterLight.keyBrightness then fighterLight.keyBrightness else 0.42
local FILL = if fighterLight and fighterLight.fillBrightness then fighterLight.fillBrightness else 0.10
local RIM = if fighterLight and fighterLight.rimBrightness then fighterLight.rimBrightness else 0.24

type RenderFrame = any
type LightSet = { keyPart: Part, rimPart: Part, fillPart: Part, key: PointLight, rim: PointLight, fill: PointLight }

local M = {}
local ctx: any = nil
local folder: Folder? = nil
local lights: { [number]: LightSet } = {}
local active = false

local function getFolder(): Folder
	local existing = folder
	if existing and existing.Parent then return existing end
	local f = Workspace:FindFirstChild("FightingLabFighterLighting")
	if f and f:IsA("Folder") then
		folder = f
		return f
	end
	f = Instance.new("Folder")
	f.Name = "FightingLabFighterLighting"
	f.Parent = Workspace
	folder = f
	return f
end

local function anchor(name: string, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Parent = parent
	return part
end

local function makePoint(name: string, parent: Part, color: Color3, brightness: number, range: number): PointLight
	local light = Instance.new("PointLight")
	light.Name = name
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light.Shadows = false
	light.Parent = parent
	return light
end

local function ensure(i: number): LightSet
	local existing = lights[i]
	if existing and existing.keyPart.Parent then return existing end
	local parent = getFolder()
	local keyPart = anchor("Fighter" .. tostring(i) .. "Key", parent)
	local rimPart = anchor("Fighter" .. tostring(i) .. "Rim", parent)
	local fillPart = anchor("Fighter" .. tostring(i) .. "FaceFill", parent)
	local warm = if i == 1 then Color3.fromRGB(255, 232, 205) else Color3.fromRGB(210, 232, 255)
	local set = {
		keyPart = keyPart,
		rimPart = rimPart,
		fillPart = fillPart,
		key = makePoint("Key", keyPart, warm, 0.42, 10),
		rim = makePoint("Rim", rimPart, Color3.fromRGB(145, 210, 255), 0.24, 9),
		fill = makePoint("FaceFill", fillPart, Color3.fromRGB(255, 246, 232), 0.10, 6),
	}
	lights[i] = set
	return set
end

local function rootForSlot(i: number): BasePart?
	local characters = ctx and ctx.modules and ctx.modules.Characters
	if characters and characters.getRoot then
		local ok, root = pcall(characters.getRoot, i)
		if ok and root and root:IsA("BasePart") then return root end
		return nil
	end
	local render = Workspace:FindFirstChild("FightingLabLocalRender")
	if not render then return nil end
	for _, child in render:GetChildren() do
		if child:IsA("Model") and child.Name:match("^Fighter" .. tostring(i) .. "_") then
			local root = child:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then return root end
		end
	end
	return nil
end

local function suppressLegacyLights(root: BasePart)
	for _, child in root:GetChildren() do
		if child:IsA("Folder") and child.Name:match("^FightingLabFighterLight") then
			for _, d in child:GetDescendants() do
				if d:IsA("Light") then
					d.Enabled = false
				end
			end
		end
	end
end

local function placeSet(i: number, root: BasePart, camera: Camera)
	suppressLegacyLights(root)
	local set = ensure(i)
	local focus = root.Position + Vector3.new(0, 2.35, 0)
	local toCamera = camera.CFrame.Position - focus
	local cameraDir = if toCamera.Magnitude > 0.01 then toCamera.Unit else Vector3.zAxis
	local right = camera.CFrame.RightVector
	local side = if i == 1 then -1 else 1
	set.keyPart.Position = focus + cameraDir * 4.2 + right * side * 1.0 + Vector3.new(0, 1.4, 0)
	set.fillPart.Position = focus + cameraDir * 2.3 + Vector3.new(0, 0.45, 0)
	set.rimPart.Position = focus - cameraDir * 3.2 - right * side * 0.8 + Vector3.new(0, 1.25, 0)
	local stageId = if ctx and ctx.modules and ctx.modules.Stage and ctx.modules.Stage.current then ctx.modules.Stage.current() else ""
	local darkBoost = if stageId == "MidnightRooftop" or stageId == "HarborDusk" then 1.05 else 1.0
	set.key.Brightness = KEY * darkBoost
	set.fill.Brightness = FILL * darkBoost
	set.rim.Brightness = RIM * darkBoost
end

function M.init(newCtx: any)
	ctx = newCtx
	Lighting:SetAttribute("FightingLabFighterLighting", true)
end

-- Fighter key/fill/rim lights exist only during a fight session (they follow the fight rigs).
function M.setActive(on: boolean)
	active = on
	if not on then
		for _, set in lights do
			set.key.Enabled = false
			set.rim.Enabled = false
			set.fill.Enabled = false
		end
		if ctx and ctx.gui then ctx.gui:SetAttribute("FighterLightCount", 0) end
	end
end

function M.update(_frame: RenderFrame)
	if not active then return end
	local camera = Workspace.CurrentCamera
	if not camera then return end
	local count = 0
	for i = 1, 2 do
		local root = rootForSlot(i)
		if root then
			placeSet(i, root, camera)
			local set = lights[i]
			set.key.Enabled = true
			set.rim.Enabled = true
			set.fill.Enabled = true
			count += 3
		end
	end
	if ctx and ctx.gui then
		ctx.gui:SetAttribute("FighterLightCount", count)
		ctx.gui:SetAttribute("FighterContrastEstimate", 0.29)
	end
end

return M
