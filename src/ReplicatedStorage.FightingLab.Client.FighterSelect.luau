--!strict
-- Fighter select (OV6): a cinematic scene instead of an overlay of cards. Choosing a fighter flies the camera at the
-- Fighter Kiosk screen, cuts to a private showcase studio (SelectScene) where the highlighted fighter stands full
-- body in their fight stance (a pooled, already-dressed preview rig from CharacterPresenter.acquirePreview, posed
-- every frame with posePreview), next to big type (name, style, tagline), attribute bars, signature moves and a
-- portrait roster strip. Switching fighters is a lighting cut (lights down, swap at dark, lights up), so a rig is
-- never shown while it is being moved or dressed: no bare-body flashes. Confirm calls env.onConfirm(id) (LobbyUI
-- fires Lobby "SelectFighter" {id}). Without live/previews (tests) it is a plain overlay with the same API.
-- Round 6 (look): a dramatic layout in the fight HUD's angled language: a big header, the name over a slanted style
-- plate, the description, slanted stat bars and the signature moves on the left; the fighter large and lit in the
-- middle; a 2 x 3 roster grid of portrait cards on the right; Back / Confirm bottom right. Transitions slide the info
-- column and the grid in, the name wipes in on every switch and the stat bars fill segment by segment.
local RunService = game:GetService("RunService")

local Client = script.Parent
local Lab = Client.Parent
local UIHelpers = require(Client.UIHelpers)
local MoveList = require(Client.MoveList)
local SelectScene = require(Client.SelectScene)
local AvatarGate = require(Client.AvatarGate)
local HudKit = require(Client.HudKit)
local Roster = require(Lab.Roster)

local T = UIHelpers.Theme
local make, text = UIHelpers.make, UIHelpers.text
local WHITE = Color3.new(1, 1, 1)
local FighterSelect = {}
FighterSelect.WARMUP = 0.6 -- legacy fixed warm-up of a fresh clone (reveals now wait for AvatarGate.trackPreview)
FighterSelect.RELEASE_AFTER = 45 -- seconds closed before pooled previews are released
FighterSelect.FLAG_GRACE = 20 -- seconds without a TemplatesReady flag before the saved templates are used anyway
FighterSelect.POSE_BLEND = 0.22 -- seconds a pose change (stance -> intro on confirm) blends over, so no joint pops

-- Pooled stage rigs that already passed the preview gate (every item and asset there); pooled rigs keep their
-- content between uses, so they are only gated once.
local warmedRigs: { [Model]: boolean } = setmetatable({} :: any, { __mode = "k" })

-- Reveals a preview clone only once it is complete (AvatarGate.trackPreview): `hide` keeps it covered, `show` uncovers.
function FighterSelect.gatePreview(model: Model, id: string, hide: () -> (), show: () -> ()): any
	return AvatarGate.trackPreview(model, id, function() hide() end, function() show() end)
end

local BODY_PARTS: { [string]: boolean } = {
	Head = true, UpperTorso = true, LowerTorso = true, LeftUpperArm = true, LeftLowerArm = true, LeftHand = true,
	RightUpperArm = true, RightLowerArm = true, RightHand = true, LeftUpperLeg = true, LeftLowerLeg = true,
	LeftFoot = true, RightUpperLeg = true, RightLowerLeg = true, RightFoot = true,
}

local function bodyBounds(model: Model): (Vector3, Vector3)
	local minB = Vector3.new(math.huge, math.huge, math.huge)
	local maxB = Vector3.new(-math.huge, -math.huge, -math.huge)
	local found = false
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and BODY_PARTS[d.Name] then
			local cf, size = d.CFrame, d.Size
			for _, sx in { -0.5, 0.5 } do for _, sy in { -0.5, 0.5 } do for _, sz in { -0.5, 0.5 } do
				local p = cf * Vector3.new(size.X * sx, size.Y * sy, size.Z * sz)
				minB = minB:Min(p); maxB = maxB:Max(p); found = true
			end end end
		end
	end
	if not found then
		local cf, size = model:GetBoundingBox()
		return cf.Position - size * 0.5, cf.Position + size * 0.5
	end
	return minB, maxB
end

--------------------------------------------------------------------------------------------------------------------
-- Preview helpers (also used by LobbyUI's identity portrait)
--------------------------------------------------------------------------------------------------------------------
-- The server's FightingLabCharacterBoot rebuilds stale fighter templates at startup and then sets the BoolValue
-- ReplicatedStorage.FightingLab.TemplatesReady. A clone taken before that shows the old saved look, so previews wait
-- for it (places without the boot script fall back to the saved templates after FLAG_GRACE seconds).
local loadedAt = os.clock()
function FighterSelect.templatesReady(): boolean
	local flag = Lab:FindFirstChild("TemplatesReady")
	if flag and flag:IsA("BoolValue") then return flag.Value end
	return os.clock() - loadedAt > FighterSelect.FLAG_GRACE
end

-- Yields until the templates are ready; returns false early once `alive()` turns false.
function FighterSelect.awaitTemplates(alive: () -> boolean): boolean
	while not FighterSelect.templatesReady() do
		if not alive() then return false end
		task.wait(0.2)
	end
	return alive()
end

-- Returns a viewport preview model for `id`, how long to keep it covered after parenting, and a release function.
-- CharacterPresenter.acquirePreview hands out in-world pooled rigs that must never be re-parented (they belong to the
-- fight-rig pool), so ViewportFrames use their own template clones, created once and kept under a cover until warm.
-- `presenter` is only used for posing.
function FighterSelect.acquireModel(_presenter: any, id: string): (Model?, number, () -> ())
	local folder = Lab:FindFirstChild("Characters")
	local source = folder and folder:FindFirstChild(id)
	if not source or not source:IsA("Model") then return nil, 0, function() end end
	local archivable = source.Archivable
	source.Archivable = true
	local clone = source:Clone()
	source.Archivable = archivable
	clone.Name = "Preview_" .. id
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = d.Name == "HumanoidRootPart"
			d.CanCollide = false; d.CanQuery = false; d.CanTouch = false
		end
	end
	return clone, FighterSelect.WARMUP, function() clone:Destroy() end
end

-- The template's one-line look note (string attribute `Signature` that CharacterFactory publishes on each fighter
-- template, e.g. "White tape over the glove cuffs"); nil when the template or the attribute is missing or empty.
function FighterSelect.signatureOf(id: string, folder: Instance?): string?
	local f = folder or Lab:FindFirstChild("Characters")
	local source = f and f:FindFirstChild(id)
	local v = source and source:GetAttribute("Signature")
	if typeof(v) ~= "string" then return nil end
	local trimmed = string.match(v, "^%s*(.-)%s*$")
	return if trimmed and trimmed ~= "" then trimmed else nil
end

function FighterSelect.newViewport(parent: Instance, name: string): (ViewportFrame, Camera, WorldModel)
	local vp: ViewportFrame = make("ViewportFrame", {
		Name = name, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1),
		Ambient = Color3.fromRGB(150, 154, 170), LightColor = Color3.fromRGB(255, 242, 224), Parent = parent,
	})
	local cam: Camera = make("Camera", { FieldOfView = 26, Parent = vp })
	vp.CurrentCamera = cam
	local world: WorldModel = make("WorldModel", { Name = "World", Parent = vp })
	return vp, cam, world
end

-- Points the viewport camera at the model: "Bust" (head and shoulders) or "Full" (whole body), from the side the
-- fighter faces, turned by `yaw` degrees for a three-quarter view. The key light comes from the camera's upper left.
function FighterSelect.frame(vp: ViewportFrame, cam: Camera, model: Model, mode: string, yaw: number?)
	local minB, maxB = bodyBounds(model)
	local height = math.max(maxB.Y - minB.Y, 3)
	local rootPart = model:FindFirstChild("HumanoidRootPart")
	local look = if rootPart and rootPart:IsA("BasePart") then rootPart.CFrame.LookVector else model:GetPivot().LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
	local dir = CFrame.Angles(0, math.rad(yaw or 0), 0):VectorToWorldSpace(flat)
	local center = (minB + maxB) * 0.5
	local target: Vector3
	local extent: number
	local fov: number
	if mode == "Bust" then
		local head = model:FindFirstChild("Head")
		local headPos = if head and head:IsA("BasePart") then head.Position else Vector3.new(center.X, maxB.Y - height * 0.08, center.Z)
		-- Head centred a little above the middle with room for hair and headwear.
		target = headPos - Vector3.new(0, height * 0.035, 0)
		extent = height * 0.42
		fov = 22
	else
		target = center + Vector3.new(0, height * 0.015, 0)
		extent = height * 1.12
		fov = 26
	end
	local distance = (extent * 0.5) / math.tan(math.rad(fov) * 0.5)
	local lift = if mode == "Bust" then height * 0.02 else height * 0.07
	cam.FieldOfView = fov
	cam.CFrame = CFrame.lookAt(target + dir * distance + Vector3.new(0, lift, 0), target)
	local c = cam.CFrame
	vp.LightDirection = (c.LookVector + c.RightVector * 0.45 - c.UpVector * 0.75).Unit
end

local function pose(presenter: any, model: Model, id: string, t: number)
	if presenter and typeof(presenter.posePreview) == "function" then
		pcall(presenter.posePreview, model, id, "Stance", t)
	end
end

-- Cover drawn over a viewport while its clone warms up: accent gradient + monogram.
local function makeCover(parent: Instance, def: any, z: number): Frame
	local cover: Frame = make("Frame", { Name = "Cover", BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = z, Parent = parent })
	UIHelpers.gradient(cover, def.accentColor:Lerp(Color3.new(0, 0, 0), 0.45), Color3.fromRGB(10, 12, 22), 90)
	local mono = text(cover, "Monogram", string.sub(def.displayName, 1, 1), T.display, 40, def.accentColor, { Size = UDim2.fromScale(1, 1), TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 0.35, ZIndex = z })
	make("UITextSizeConstraint", { MaxTextSize = 120, Parent = mono })
	return cover
end

local function fadeOut(cover: Frame)
	local mono = cover:FindFirstChild("Monogram")
	UIHelpers.tween(cover, 0.28, { BackgroundTransparency = 1 })
	if mono then UIHelpers.tween(mono, 0.2, { TextTransparency = 1 }) end
	task.delay(0.3, function() cover.Visible = false end)
end

--------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------
-- Cinematic select (OV6)
--------------------------------------------------------------------------------------------------------------------
export type SelectEnv = {
	parent: Instance,
	presenter: any?,
	previews: boolean?,
	touchOnly: boolean?,
	live: boolean?, -- camera flight + 3D studio (off in tests)
	world: (() -> Instance?)?, -- FightingLabWorld (kiosk screen for the camera flight)
	device: (() -> string)?, -- "keyboard" | "gamepad" | "touch"
	canSelect: () -> (boolean, string?),
	currentFighter: () -> string?,
	onConfirm: (id: string) -> (),
	onClose: (() -> ())?,
	sound: ((name: string) -> ())?,
	blur: boolean?,
}
export type Controller = {
	gui: ScreenGui,
	open: (id: string?) -> (),
	close: () -> (),
	isOpen: () -> boolean,
	selected: () -> string,
	select: (id: string) -> (),
	step: (delta: number) -> (),
	confirm: () -> boolean,
	refresh: () -> (),
	handleKey: (key: Enum.KeyCode) -> boolean,
	previewState: () -> { [string]: any },
	destroy: () -> (),
}

type Tile = { button: TextButton, scale: UIScale, stroke: UIStroke, vp: ViewportFrame, cam: Camera, world: WorldModel, cover: Frame, bar: Frame, name: TextLabel, badge: TextLabel, preview: { model: Model, release: () -> () }?, corner: Frame? }
type StageRig = { model: Model, ready: boolean, warmAt: number, footDelta: number?, height: number?, cold: boolean }

FighterSelect.CUT_DOWN = 0.08 -- lights out before the swap
FighterSelect.CUT_UP = 0.24 -- lights back up after it
FighterSelect.FLIGHT = 0.45 -- camera flight toward the kiosk before the studio
FighterSelect.CONFIRM_HOLD = 0.95 -- seconds the confirmed fighter is shown before the select closes

-- Browsing: every horizontal key, and the vertical ones too (W/S, arrows, D-pad up/down: previous / next fighter).
local LEFT_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.Left] = true, [Enum.KeyCode.A] = true, [Enum.KeyCode.DPadLeft] = true, [Enum.KeyCode.Q] = true, [Enum.KeyCode.ButtonL1] = true,
	[Enum.KeyCode.Up] = true, [Enum.KeyCode.W] = true, [Enum.KeyCode.DPadUp] = true,
}
local RIGHT_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.Right] = true, [Enum.KeyCode.D] = true, [Enum.KeyCode.DPadRight] = true, [Enum.KeyCode.E] = true, [Enum.KeyCode.ButtonR1] = true,
	[Enum.KeyCode.Down] = true, [Enum.KeyCode.S] = true, [Enum.KeyCode.DPadDown] = true,
}
local CONFIRM_KEYS: { [Enum.KeyCode]: boolean } = { [Enum.KeyCode.Return] = true, [Enum.KeyCode.KeypadEnter] = true, [Enum.KeyCode.Space] = true, [Enum.KeyCode.ButtonA] = true }
local BACK_KEYS: { [Enum.KeyCode]: boolean } = { [Enum.KeyCode.Backspace] = true, [Enum.KeyCode.ButtonB] = true, [Enum.KeyCode.Tab] = true }
FighterSelect.KEYS = { left = LEFT_KEYS, right = RIGHT_KEYS, confirm = CONFIRM_KEYS, back = BACK_KEYS }

function FighterSelect.mount(env: SelectEnv): Controller
	local previewsOn = env.previews ~= false
	local live = env.live == true
	local touchOnly = env.touchOnly == true
	local selectedId = Roster.order[1]
	local isOpen = false
	local built = false
	local destroyed = false
	local conns: { RBXScriptConnection } = {}
	local tiles: { [string]: Tile } = {}
	local rigs: { [string]: StageRig } = {}
	local refs: any = {}
	local closedAt = 0
	local token = 0
	local shownId: string? = nil -- fighter currently standing on the platform
	local stageState = { height = nil :: number?, cutT = -1, cutTo = nil :: string?, swapped = false, push = 0, pushGoal = 0, confirmUntil = 0, pose = "Stance", level = 1, openedAt = 0, flight = false }
	local cameraSaved: { type: Enum.CameraType, subject: Instance?, fov: number, cframe: CFrame }? = nil
	local renderBound = false

	local gui: ScreenGui = make("ScreenGui", {
		Name = "FightingLabFighterSelect", ResetOnSpawn = false, ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets, DisplayOrder = 50, Enabled = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = env.parent,
	})
	-- Full-screen black for the camera cuts (above everything, ignores the top-bar inset).
	local fadeGui: ScreenGui = make("ScreenGui", { Name = "FightingLabSelectFade", ResetOnSpawn = false, IgnoreGuiInset = true, ScreenInsets = Enum.ScreenInsets.None, DisplayOrder = 55, Enabled = false, Parent = env.parent })
	local fade: Frame = make("Frame", { Name = "Black", BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = fadeGui })

	local function play(name: string) if env.sound then pcall(env.sound, name) end end
	local function device(): string
		if env.device then
			local ok, d = pcall(env.device)
			if ok and typeof(d) == "string" then return d end
		end
		return if touchOnly then "touch" else "keyboard"
	end
	local function canSelect(): (boolean, string?)
		local ok, allowed, reason = pcall(env.canSelect)
		if not ok then return false, "Unavailable" end
		return allowed == true, reason
	end
	local function current(): string?
		local ok, id = pcall(env.currentFighter)
		return if ok and typeof(id) == "string" then id else nil
	end
	local function presenter(): any return env.presenter end

	-- Layout -------------------------------------------------------------------------------------------------------
	local function buildFooter()
		local footer: Frame = refs.footer
		if not footer then return end
		for _, c in footer:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
		local d = device()
		if d ~= "touch" then
			local gp = d == "gamepad"
			local gd = if gp then "gamepad" else "keyboard"
			UIHelpers.hint(footer, { "←", "→" }, "Browse", { height = 24, device = gd, order = 1, color = T.muted, textSize = 14 })
			UIHelpers.hint(footer, { if gp then "A" else "ENTER" }, "Confirm", { height = 24, device = gd, order = 2, color = T.muted, textSize = 14 })
			UIHelpers.hint(footer, { if gp then "B" else "BACKSPACE" }, "Back", { height = 24, device = gd, order = 3, color = T.muted, textSize = 14 })
		end
	end
	local function build()
		if built then return end
		built = true
		-- Legibility: dark wash behind the info column and the roster strip (reaches under the top bar).
		local wash = make("Frame", { Name = "Wash", BackgroundColor3 = T.bg, BorderSizePixel = 0, Position = UDim2.fromOffset(-200, -200), Size = UDim2.new(0.62, 200, 1, 400), Parent = gui })
		make("UIGradient", { Transparency = UIHelpers.ramp({ { 0, 0.12 }, { 0.55, 0.45 }, { 1, 1 } }), Parent = wash })
		local floor = make("Frame", { Name = "Floor", BackgroundColor3 = T.bg, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, -200, 1, 200), Size = UDim2.new(1, 400, 0.3, 200), Parent = gui })
		make("UIGradient", { Rotation = -90, Transparency = UIHelpers.ramp({ { 0, 0.2 }, { 0.5, 0.6 }, { 1, 1 } }), Parent = floor })
		local stage: Frame = make("Frame", { Name = "Stage", BackgroundTransparency = 1, Parent = gui })
		refs.unfit = UIHelpers.fitToScreen(gui, stage, touchOnly)
		local body: Frame = make("Frame", { Name = "Body", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = stage })
		-- The stage carries the design-space UIScale; the short-screen fit scales the body (one UIScale per object).
		local fit: UIScale = make("UIScale", { Name = "Fit", Parent = body })
		refs.stage, refs.body = stage, body
		local function fitBody()
			local w, h = stage.Size.X.Offset, stage.Size.Y.Offset
			local s = math.clamp(math.min(h / 700, w / 1180), 0.5, 1)
			fit.Scale = s
			body.Size = UDim2.fromOffset(w / s, h / s)
		end
		table.insert(conns, stage:GetPropertyChangedSignal("Size"):Connect(fitBody))
		fitBody()
		-- Header: SELECT YOUR FIGHTER over a slanted ember rule, and the roster position
		local tag = text(body, "Tag", "SELECT YOUR FIGHTER", T.title, 17, T.gold, { Position = UDim2.fromOffset(58, 24), Size = UDim2.fromOffset(420, 20) })
		local rule = HudKit.slab(tag, "Rule", 86, 4, 2, "/", T.ember, 0, { Position = UDim2.fromOffset(0, 24) })
		rule.holder.Name = "Rule"
		refs.count = text(body, "Count", "", T.number, 13, T.muted, { Position = UDim2.fromOffset(154, 42), Size = UDim2.fromOffset(200, 16) })
		-- Info column
		local info: Frame = make("Frame", { Name = "Info", BackgroundTransparency = 1, Position = UDim2.fromOffset(52, 70), Size = UDim2.fromOffset(640, 470), Parent = body })
		refs.info = info
		refs.name = text(info, "Name", "", T.display, 116, T.text, { Size = UDim2.fromOffset(660, 122), Position = UDim2.fromOffset(0, 0), ClipsDescendants = false })
		refs.nameShadow = UIHelpers.textStroke(refs.name, 0.5, 2.5)
		-- the fighting style on a slanted plate in the fighter's colour
		local styleChip = HudKit.chip(info, "StyleChip", "", 28, T.heavy, 15, T.ember, T.ink, "/", { Position = UDim2.fromOffset(4, 126) })
		refs.styleChip = styleChip
		refs.style = styleChip.label
		refs.tagline = text(info, "Tagline", "", T.medium, 19, Color3.fromRGB(226, 230, 238), { Position = UDim2.fromOffset(6, 166), Size = UDim2.fromOffset(500, 50), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
		-- the template's look note (optional): an accent diamond and one muted line right under the tagline
		local note: Frame = make("Frame", { Name = "LookNote", BackgroundTransparency = 1, Position = UDim2.fromOffset(6, 195), Size = UDim2.fromOffset(500, 18), Visible = false, Parent = info })
		refs.noteMark = make("Frame", { Name = "Mark", BackgroundColor3 = T.ember, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 4, 0.5, 0), Size = UDim2.fromOffset(6, 6), Rotation = 45, Parent = note })
		refs.noteText = text(note, "Text", "", T.medium, 14, T.muted, { Position = UDim2.fromOffset(16, 0), Size = UDim2.new(1, -16, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd })
		refs.note = note
		local function placeNote()
			local h = refs.tagline.TextBounds.Y
			note.Position = UDim2.fromOffset(6, 166 + math.clamp(if h > 0 then h else 23, 18, 48) + 6)
		end
		table.insert(conns, refs.tagline:GetPropertyChangedSignal("TextBounds"):Connect(placeNote))
		placeNote()
		local attrs = make("Frame", { Name = "Attributes", BackgroundTransparency = 1, Position = UDim2.fromOffset(6, 236), Size = UDim2.fromOffset(420, 112), Parent = info })
		UIHelpers.list(attrs, false, 8)
		refs.bars = {}
		for i = 1, 4 do
			local r = make("Frame", { Name = "Attr" .. i, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = i, Parent = attrs })
			local label = text(r, "Label", "", T.heavy, 13, T.muted, { Size = UDim2.fromOffset(90, 20) })
			local _, set, recolor = UIHelpers.segmentBar(r, "Bar", 10, T.gold, { Position = UDim2.fromOffset(96, 3), Size = UDim2.new(1, -150, 0, 14) })
			local value = text(r, "Value", "", T.number, 13, T.text, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(44, 20), TextXAlignment = Enum.TextXAlignment.Right })
			refs.bars[i] = { label = label, set = set, recolor = recolor, value = value }
		end
		local sigTitle = text(info, "SignatureTitle", "SIGNATURE MOVES", T.heavy, 12, T.ember, { Position = UDim2.fromOffset(6, 362), Size = UDim2.fromOffset(240, 16) })
		sigTitle.Name = "SignatureTitle"
		refs.signature = make("Frame", { Name = "Signature", BackgroundTransparency = 1, Position = UDim2.fromOffset(6, 382), Size = UDim2.fromOffset(500, 92), Parent = info })
		UIHelpers.list(refs.signature, false, 6)
		refs.infoScale = make("UIScale", { Parent = info })
		-- Stage-side messages: loading shimmer and the confirm stamp.
		refs.loading = text(body, "Loading", "PREPARING FIGHTER...", T.heavy, 16, T.muted, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.6, 0.5), Size = UDim2.fromOffset(320, 24), TextXAlignment = Enum.TextXAlignment.Center, Visible = false })
		local stamp = make("Frame", { Name = "Stamp", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.6, 0.64), Size = UDim2.fromOffset(360, 74), Visible = false, Parent = body })
		HudKit.slab(stamp, "Plate", 360, 74, 24, "/", T.ember, 0, { Size = UDim2.fromScale(1, 1) })
		text(stamp, "Text", "LOCKED IN", T.display, 50, T.ink, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 2 })
		refs.stamp = stamp
		refs.stampScale = make("UIScale", { Parent = stamp })
		-- Roster grid (right): two columns of portrait cards
		local TILE_W, TILE_H, GAP = 104, 120, 10
		local cols = 2
		local rows = math.ceil(#Roster.order / cols)
		-- The grid's label sits on its own dark plate: the studio's accent light pillar (orange, red...) can stand right
		-- behind it, and ember text on an ember pillar disappears.
		local gridTitle = text(body, "RosterTitle", "ROSTER", T.heavy, 12, T.text, {
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -52, 0, 68), Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X,
			TextXAlignment = Enum.TextXAlignment.Center, BackgroundColor3 = T.bg, BackgroundTransparency = 0.04,
		})
		make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = gridTitle })
		UIHelpers.corner(gridTitle, 2)
		UIHelpers.outline(gridTitle, T.ember, 1, 0.15)
		refs.gridTitle = gridTitle
		local strip: Frame = make("Frame", { Name = "Roster", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -52, 0, 92), Size = UDim2.fromOffset(cols * TILE_W + (cols - 1) * GAP, rows * (TILE_H + GAP)), Parent = body })
		refs.strip = strip
		refs.tilePos = function(i: number, lifted: boolean): UDim2
			local col, row = (i - 1) % cols, (i - 1) // cols
			return UDim2.fromOffset(col * (TILE_W + GAP) + (if lifted then -6 else 0), row * (TILE_H + GAP))
		end
		for i, id in Roster.order do
			local def = Roster.get(id)
			local b: TextButton = make("TextButton", { Name = "Tile_" .. id, Text = "", AutoButtonColor = false, BackgroundColor3 = T.panel, BorderSizePixel = 0, ClipsDescendants = true, Position = refs.tilePos(i, false), Size = UDim2.fromOffset(TILE_W, TILE_H), Parent = strip })
			UIHelpers.corner(b, 3)
			UIHelpers.gradient(b, def.accentColor:Lerp(T.bg, 0.55), T.bg, 90)
			local stroke = UIHelpers.outline(b, WHITE, 1, 0.8)
			local vp, cam, world = FighterSelect.newViewport(b, "Bust")
			vp.Size = UDim2.new(1, 0, 1, -24)
			vp.ZIndex = 2
			-- Opaque until the portrait clone is complete (same look as the tile background, with the monogram).
			local cover = make("Frame", { Name = "Cover", BackgroundColor3 = WHITE, BackgroundTransparency = 0, BorderSizePixel = 0, Size = UDim2.new(1, 0, 1, -24), ZIndex = 3, Parent = b })
			UIHelpers.gradient(cover, def.accentColor:Lerp(T.bg, 0.55), T.bg, 90)
			local mono = text(cover, "Monogram", string.sub(def.displayName, 1, 1), T.display, 48, def.accentColor, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })
			mono.TextTransparency = 0.2
			local bar = make("Frame", { Name = "Bar", BackgroundColor3 = def.accentColor, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -24), Size = UDim2.new(1, 0, 0, 3), ZIndex = 4, Parent = b })
			local nameBand = make("Frame", { Name = "NameBand", BackgroundColor3 = T.bg, BackgroundTransparency = 0.05, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 24), ZIndex = 4, Parent = b })
			local name = text(nameBand, "Name", string.upper(def.displayName), T.title, 14, T.muted, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5 })
			-- the accent corner of the selected card
			local corner = UIHelpers.slantCap(b, "Corner", 22, 22, "TR", def.accentColor, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), ZIndex = 6, Visible = false })
			local badge = text(b, "Badge", "IN USE", T.heavy, 9, T.ink, { Position = UDim2.fromOffset(5, 5), Size = UDim2.fromOffset(40, 13), BackgroundTransparency = 0, BackgroundColor3 = T.gold, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5, Visible = false })
			UIHelpers.corner(badge, 2)
			local sc = make("UIScale", { Parent = b })
			tiles[id] = { button = b, scale = sc, stroke = stroke, vp = vp, cam = cam, world = world, cover = cover, bar = bar, name = name, badge = badge, preview = nil, corner = corner }
			table.insert(conns, b.Activated:Connect(function()
				if not isOpen then return end
				if selectedId == id then refs.confirm(); return end
				play("MenuMove")
				refs.select(id)
			end))
		end
		-- Footer: hints + buttons
		local footer: Frame = make("Frame", { Name = "Footer", BackgroundTransparency = 1, Position = UDim2.fromOffset(56, 684), Size = UDim2.fromOffset(640, 28), Parent = body })
		UIHelpers.list(footer, true, 18, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
		refs.footer = footer
		buildFooter()
		local buttons = make("Frame", { Name = "Buttons", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -52, 1, -28), Size = UDim2.fromOffset(420, 52), Parent = body })
		UIHelpers.list(buttons, true, 10, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
		local back = UIHelpers.button(buttons, "Back", { text = "BACK", size = UDim2.fromOffset(120, 48), order = 1, textSize = 16 })
		local confirmB = UIHelpers.button(buttons, "Confirm", { text = "CONFIRM", size = UDim2.fromOffset(220, 52), order = 2, primary = true, font = T.title, textSize = 22 })
		refs.back, refs.confirmB = back, confirmB
		table.insert(conns, back.button.Activated:Connect(function() if isOpen then play("MenuBack"); refs.close() end end))
		table.insert(conns, confirmB.button.Activated:Connect(function() if isOpen then refs.confirm() end end))
	end

	-- Portrait tiles: template clones in ViewportFrames, created once and kept under an opaque cover until the preview
	-- gate says the clone carries every item of its template and every asset is fetched.
	local function coverTile(tile: Tile)
		tile.cover.Visible = true
		tile.cover.BackgroundTransparency = 0
		local mono = tile.cover:FindFirstChild("Monogram") :: TextLabel?
		if mono then mono.TextTransparency = 0.2 end
	end
	local function ensureTilePortraits()
		if not previewsOn then return end
		for _, id in Roster.order do
			local tile = tiles[id]
			if tile and not tile.preview then
				tile.preview = { model = nil :: any, release = function() end }
				coverTile(tile)
				task.spawn(function()
					if not FighterSelect.awaitTemplates(function() return not destroyed and tile.preview ~= nil end) then return end
					local model, _, release = FighterSelect.acquireModel(presenter(), id)
					if not model or destroyed or not tile.preview then if model then release() end; return end
					tile.preview = { model = model, release = release }
					model.Parent = tile.world
					pose(presenter(), model, id, 0)
					FighterSelect.frame(tile.vp, tile.cam, model, "Bust", 16)
					FighterSelect.gatePreview(model, id, function() coverTile(tile) end, function()
						if destroyed or not tile.preview or tile.preview.model ~= model then return end
						fadeOut(tile.cover)
					end)
				end)
			end
		end
	end
	local function releaseTilePortraits()
		for _, tile in tiles do
			local p = tile.preview
			tile.preview = nil
			if p and p.model then p.release() end
			coverTile(tile)
		end
	end

	-- Info column ----------------------------------------------------------------------------------------------------
	local lastInfoId = ""
	local function renderInfo(animate: boolean)
		local def = Roster.get(selectedId)
		local index = table.find(Roster.order, selectedId) or 1
		refs.count.Text = string.format("%02d / %02d", index, #Roster.order)
		local cur = current()
		for id, tile in tiles do
			local sel = id == selectedId
			tile.stroke.Color = if sel then Roster.get(id).accentColor else WHITE
			tile.stroke.Transparency = if sel then 0 else 0.8
			tile.stroke.Thickness = if sel then 3 else 1
			tile.name.TextColor3 = if sel then T.text else T.muted
			tile.badge.Visible = id == cur
			tile.vp.ImageTransparency = if sel then 0 else 0.35
			if tile.corner then tile.corner.Visible = sel end
			local goal = { Position = refs.tilePos(table.find(Roster.order, id) or 1, sel) }
			if animate then UIHelpers.tween(tile.button, 0.16, goal, Enum.EasingStyle.Quart) else tile.button.Position = goal.Position end
			tile.scale.Scale = if sel then 1.05 else 1
		end
		local ok = canSelect()
		refs.confirmB.setEnabled(ok)
		refs.confirmB.label.Text = if selectedId == cur then "KEEP " .. def.displayName else "CONFIRM"
		if lastInfoId == selectedId then return end
		lastInfoId = selectedId
		refs.name.Text = def.displayName
		refs.name.TextColor3 = WHITE
		refs.styleChip.set(string.upper(def.style), def.accentColor, def.accentColor:Lerp(T.ink, 0.86))
		refs.tagline.Text = def.tagline
		local lookNote = FighterSelect.signatureOf(selectedId)
		refs.note.Visible = lookNote ~= nil
		refs.noteText.Text = lookNote or ""
		refs.noteMark.BackgroundColor3 = def.accentColor
		for i, a in UIHelpers.attributes(def) do
			local bar = refs.bars[i]
			bar.label.Text = a.name
			bar.recolor(def.accentColor)
			bar.set(a.value, animate)
			bar.value.Text = tostring(math.clamp(math.floor(a.value * 10 + 0.5), 1, 10))
		end
		for _, c in refs.signature:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
		for i, key in MoveList.signature(def) do
			local mv = def.moves[key]
			local r = make("Frame", { Name = "Sig" .. i, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = i, Parent = refs.signature })
			local n = make("Frame", { Name = "In", BackgroundTransparency = 1, Size = UDim2.fromOffset(96, 26), Parent = r })
			UIHelpers.list(n, true, 0, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
			UIHelpers.notationRow(n, mv.input, { height = 22 })
			text(r, "Name", string.upper(mv.name), T.heavy, 15, T.text, { Position = UDim2.fromOffset(104, 0), Size = UDim2.new(1, -106, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd })
		end
		if animate then
			refs.name.Position = UDim2.fromOffset(-48, 0)
			refs.name.TextTransparency = 0.7
			UIHelpers.tween(refs.name, 0.28, { Position = UDim2.fromOffset(0, 0), TextTransparency = 0 }, Enum.EasingStyle.Quint)
			refs.styleChip.holder.Position = UDim2.fromOffset(-20, 126)
			UIHelpers.tween(refs.styleChip.holder, 0.3, { Position = UDim2.fromOffset(4, 126) }, Enum.EasingStyle.Quint)
			refs.tagline.TextTransparency = 1
			UIHelpers.tween(refs.tagline, 0.3, { TextTransparency = 0 })
			refs.noteText.TextTransparency = 1
			UIHelpers.tween(refs.noteText, 0.35, { TextTransparency = 0 })
		end
	end

	-- 3D studio --------------------------------------------------------------------------------------------------------
	local function parkFrame(): CFrame return CFrame.new(SelectScene.ORIGIN + Vector3.new(0, -9, 0)) end
	local function coldAcquires(): number
		local p = presenter()
		if p and typeof(p.poolStats) == "function" then
			local ok, stats = pcall(p.poolStats)
			if ok and typeof(stats) == "table" and typeof(stats.coldAcquires) == "number" then return stats.coldAcquires end
		end
		return 0
	end
	local function acquireRigs()
		local p = presenter()
		if not p or typeof(p.acquirePreview) ~= "function" then return end
		for _, id in Roster.order do
			if not rigs[id] then
				local before = coldAcquires()
				local ok, model = pcall(p.acquirePreview, id)
				if ok and typeof(model) == "Instance" and model:IsA("Model") then
					local cold = coldAcquires() > before
					-- Parked below the platform until the preview gate has every item and asset of the fighter (pooled
					-- rigs parked out of sight have not even asked for their textures yet).
					local rig: StageRig = { model = model, ready = warmedRigs[model] == true, warmAt = 0, footDelta = nil, cold = cold }
					rigs[id] = rig
					model:PivotTo(parkFrame())
					if not rig.ready then
						FighterSelect.gatePreview(model, id, function() end, function()
							warmedRigs[model] = true
							if rigs[id] == rig then rig.ready = true end
						end)
					end
				end
			end
		end
	end
	local function releaseRigs()
		local p = presenter()
		for id, rig in rigs do
			if p and typeof(p.releasePreview) == "function" then pcall(p.releasePreview, rig.model) end
			rigs[id] = nil
		end
		shownId = nil
	end
	local function footBottom(model: Model): number?
		local lowest: number? = nil
		for _, name in { "LeftFoot", "RightFoot" } do
			local foot = model:FindFirstChild(name, true)
			if foot and foot:IsA("BasePart") then
				local cf, size = foot.CFrame, foot.Size
				for _, sx in { -0.5, 0.5 } do for _, sy in { -0.5, 0.5 } do for _, sz in { -0.5, 0.5 } do
					local y = (cf * Vector3.new(size.X * sx, size.Y * sy, size.Z * sz)).Y
					lowest = if lowest then math.min(lowest, y) else y
				end end end
			end
		end
		return lowest
	end
	-- Top of the head (hair and hats included) in world space, for the camera fit.
	local function headTop(model: Model): number?
		local head = model:FindFirstChild("Head")
		if not (head and head:IsA("BasePart")) then return nil end
		local top = head.Position.Y + head.Size.Y * 0.5
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d.Parent and d.Parent:IsA("Accessory") and (d.Position - head.Position).Magnitude < 2.5 then
				local cf, size = d.CFrame, d.Size
				for _, sx in { -0.5, 0.5 } do for _, sy in { -0.5, 0.5 } do for _, sz in { -0.5, 0.5 } do
					top = math.max(top, (cf * Vector3.new(size.X * sx, size.Y * sy, size.Z * sz)).Y)
				end end end
			end
		end
		return math.min(top, head.Position.Y + 2.2)
	end
	-- A pose change on the shown rig (stance -> intro on confirm) blends from the joints it had, so nothing pops.
	local blend = { model = nil :: Model?, pose = "", from = {} :: { [Motor6D]: CFrame }, started = -math.huge }
	local function captureMotors(model: Model): { [Motor6D]: CFrame }
		local out = {}
		for _, d in model:GetDescendants() do
			if d:IsA("Motor6D") then out[d] = d.Transform end
		end
		return out
	end
	local function poseShown(t: number)
		local id = shownId
		local rig = id and rigs[id]
		if not id or not rig then return end
		local p = presenter()
		if not p or typeof(p.posePreview) ~= "function" then return end
		if blend.model == rig.model and blend.pose ~= stageState.pose then
			blend.from = captureMotors(rig.model)
			blend.started = os.clock()
		elseif blend.model ~= rig.model then
			blend.from = {}
			blend.started = -math.huge
		end
		blend.model = rig.model
		blend.pose = stageState.pose
		pcall(p.posePreview, rig.model, id, stageState.pose, t)
		local u = (os.clock() - blend.started) / FighterSelect.POSE_BLEND
		if u < 1 then
			local e = u * u * (3 - 2 * u)
			for motor, from in blend.from do
				if motor.Parent then motor.Transform = from:Lerp(motor.Transform, e) end
			end
		end
	end
	local function placeShown(id: string?)
		local old = shownId
		if old and rigs[old] and old ~= id then rigs[old].model:PivotTo(parkFrame()) end
		shownId = nil
		if not id then return end
		local rig = rigs[id]
		if not rig or not rig.ready then return end
		shownId = id
		local base = SelectScene.fighterFrame()
		if not rig.footDelta then
			-- First placement: stand the rig on the platform by measuring its posed feet once.
			local humanoid = rig.model:FindFirstChildOfClass("Humanoid")
			local root = rig.model:FindFirstChild("HumanoidRootPart")
			local guess = if humanoid and root and root:IsA("BasePart") then humanoid.HipHeight + root.Size.Y * 0.5 else 3
			rig.model:PivotTo(base + Vector3.new(0, guess, 0))
			poseShown(os.clock())
			local bottom = footBottom(rig.model)
			rig.footDelta = guess + (if bottom then SelectScene.platformY() - bottom else 0)
			local top = headTop(rig.model)
			if top then rig.height = top + (rig.footDelta - guess) - SelectScene.platformY() end
		end
		rig.model:PivotTo(base + Vector3.new(0, rig.footDelta :: number, 0))
		poseShown(os.clock())
	end

	-- Camera ------------------------------------------------------------------------------------------------------------
	local function camera(): Camera? return workspace.CurrentCamera end
	local function aspect(): number
		local cam = camera()
		return if cam and cam.ViewportSize.Y > 0 then cam.ViewportSize.X / cam.ViewportSize.Y else 16 / 9
	end
	local function saveCamera()
		local cam = camera()
		if not cam or cameraSaved then return end
		cameraSaved = { type = cam.CameraType, subject = cam.CameraSubject, fov = cam.FieldOfView, cframe = cam.CFrame }
	end
	local function restoreCamera()
		local cam = camera()
		local saved = cameraSaved
		cameraSaved = nil
		if not cam or not saved then return end
		cam.FieldOfView = saved.fov
		cam.CFrame = saved.cframe
		local players = game:GetService("Players")
		local localPlayer = players.LocalPlayer
		local character = localPlayer and localPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		cam.CameraSubject = humanoid or saved.subject
		cam.CameraType = if saved.type == Enum.CameraType.Scriptable then Enum.CameraType.Custom else saved.type
	end
	local studioTime = 0
	local function renderStudio(dt: number)
		if not isOpen or stageState.flight then return end
		local cam = camera()
		if not cam then return end
		studioTime += dt
		-- Lights: cut between fighters (down, swap at dark, up), confirm flash on top.
		local level = 1
		if stageState.cutT >= 0 then
			stageState.cutT += dt
			local t = stageState.cutT
			if t < FighterSelect.CUT_DOWN then
				level = 1 - t / FighterSelect.CUT_DOWN
			else
				if not stageState.swapped then
					stageState.swapped = true
					placeShown(stageState.cutTo)
					local def = Roster.get(stageState.cutTo or selectedId)
					SelectScene.setAccent(def.accentColor)
					SelectScene.setName(def.displayName)
				end
				local u = math.clamp((t - FighterSelect.CUT_DOWN) / FighterSelect.CUT_UP, 0, 1)
				level = 1 - (1 - u) * (1 - u)
				if u >= 1 then stageState.cutT = -1 end
			end
		end
		if os.clock() < stageState.confirmUntil then
			local k = (stageState.confirmUntil - os.clock()) / FighterSelect.CONFIRM_HOLD
			level += 0.7 * math.max(0, k - 0.6) / 0.4
		end
		-- A rig that is not complete yet waits off-stage (the preview gate flips `ready`), then takes the platform.
		local want = if stageState.cutT >= 0 and not stageState.swapped then shownId else selectedId
		if want and shownId ~= want and stageState.cutT < 0 then
			local rig = rigs[want]
			if rig and rig.ready then placeShown(want) end
		end
		refs.loading.Visible = shownId == nil and isOpen
		SelectScene.setLevel(level)
		stageState.push += (stageState.pushGoal - stageState.push) * math.min(1, dt * 3.2)
		local shownRig = shownId and rigs[shownId]
		local wantHeight = if shownRig and typeof(shownRig.height) == "number" then shownRig.height else nil
		if wantHeight then
			stageState.height = if stageState.height then stageState.height + (wantHeight - stageState.height) * math.min(1, dt * 5) else wantHeight
		end
		local cf, fov = SelectScene.cameraFor(studioTime, aspect(), stageState.push, stageState.height)
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = cf
		cam.FieldOfView = fov
		poseShown(os.clock())
	end
	local function bindRender()
		if renderBound or not live then return end
		renderBound = true
		RunService:BindToRenderStep("FightingLabFighterSelect", Enum.RenderPriority.Camera.Value + 2, renderStudio)
	end
	local function unbindRender()
		if not renderBound then return end
		renderBound = false
		pcall(function() RunService:UnbindFromRenderStep("FightingLabFighterSelect") end)
	end
	-- Camera flight toward the Fighter Kiosk screen (or a short push), fading to black on the way.
	local function flight(seconds: number)
		local cam = camera()
		if not cam then return end
		local start = cam.CFrame
		local goal = start * CFrame.new(0, 0.6, -5)
		local w = env.world and env.world()
		local lobby = w and w:FindFirstChild("Lobby")
		local kiosk = lobby and lobby:FindFirstChild("FighterKiosk")
		local screen = kiosk and (kiosk:FindFirstChild("Screen") or kiosk:FindFirstChild("PromptPart"))
		if screen and screen:IsA("BasePart") and (screen.Position - start.Position).Magnitude < 90 then
			local away = start.Position - screen.Position
			away = Vector3.new(away.X, 0, away.Z)
			local dir = if away.Magnitude > 0.1 then away.Unit else -screen.CFrame.LookVector
			goal = CFrame.lookAt(screen.Position + dir * 3 + Vector3.new(0, 0.4, 0), screen.Position)
		end
		cam.CameraType = Enum.CameraType.Scriptable
		local t0 = os.clock()
		while os.clock() - t0 < seconds and isOpen and not destroyed do
			local u = math.clamp((os.clock() - t0) / seconds, 0, 1)
			local e = u * u * (3 - 2 * u)
			cam.CFrame = start:Lerp(goal, e * e)
			fade.BackgroundTransparency = 1 - math.clamp((u - 0.35) / 0.65, 0, 1)
			RunService.RenderStepped:Wait()
		end
		fade.BackgroundTransparency = 0
	end

	-- Controller ---------------------------------------------------------------------------------------------------------
	local controller: Controller
	-- Roblox's player list (top right) would sit over the cinematic; held hidden while the select is open.
	local holdingList = false
	local function hidePlayerList()
		if not live or holdingList then return end
		holdingList = true
		UIHelpers.holdPlayerList(true)
	end
	local function restorePlayerList()
		if not holdingList then return end
		holdingList = false
		UIHelpers.holdPlayerList(false)
	end
	local function selectId(id: string)
		if not Roster.has(id) or id == selectedId then return end
		selectedId = id
		if not isOpen then return end
		renderInfo(true)
		if live and previewsOn then
			stageState.cutT = 0
			stageState.cutTo = id
			stageState.swapped = false
			stageState.pose = "Stance"
		end
	end
	local function finishClose()
		gui.Enabled = false
		unbindRender()
		releaseRigs()
		SelectScene.close()
		restoreCamera()
		restorePlayerList()
		closedAt = os.clock()
		local myToken = token
		task.delay(FighterSelect.RELEASE_AFTER, function()
			if not isOpen and myToken == token and not destroyed then releaseTilePortraits() end
		end)
	end
	local function close()
		if not isOpen then return end
		isOpen = false
		token += 1
		refs.stamp.Visible = false
		if live and previewsOn and cameraSaved then
			-- Fade to black, restore the lobby camera behind it, fade back in.
			fadeGui.Enabled = true
			local myToken = token
			UIHelpers.tween(fade, 0.18, { BackgroundTransparency = 0 })
			task.delay(0.2, function()
				if myToken ~= token and isOpen then return end
				finishClose()
				UIHelpers.tween(fade, 0.35, { BackgroundTransparency = 1 })
				task.delay(0.36, function() if not isOpen then fadeGui.Enabled = false end end)
				if env.onClose then pcall(env.onClose) end
			end)
		else
			finishClose()
			if env.onClose then pcall(env.onClose) end
		end
	end
	local function open(id: string?)
		if destroyed then return end
		local allowed = canSelect()
		if not allowed then return end
		build()
		buildFooter()
		local cur = current()
		local want = if id and Roster.has(id) then id elseif cur and Roster.has(cur) then cur else Roster.order[1]
		if isOpen then selectId(want); return end
		isOpen = true
		token += 1
		local myToken = token
		selectedId = want
		lastInfoId = ""
		stageState.pose = "Stance"
		stageState.confirmUntil = 0
		stageState.cutT = -1
		refs.stamp.Visible = false
		ensureTilePortraits()
		renderInfo(false)
		play("MenuSelect")
		if not (live and previewsOn) then
			gui.Enabled = true
			return
		end
		-- Cinematic entrance: fly at the kiosk screen into black, cut to the studio, dolly out from close.
		saveCamera()
		hidePlayerList()
		fadeGui.Enabled = true
		stageState.flight = true
		task.spawn(function()
			flight(FighterSelect.FLIGHT)
			if myToken ~= token or not isOpen or destroyed then return end
			SelectScene.open()
			local def = Roster.get(selectedId)
			SelectScene.setAccent(def.accentColor)
			SelectScene.setName(def.displayName)
			SelectScene.setLevel(1)
			acquireRigs()
			placeShown(selectedId)
			stageState.push = 1
			stageState.pushGoal = 0
			studioTime = 0
			stageState.flight = false
			bindRender()
			gui.Enabled = true
			-- UI slides in while the camera settles.
			refs.info.Position = UDim2.fromOffset(4, 70)
			UIHelpers.tween(refs.info, 0.5, { Position = UDim2.fromOffset(52, 70) }, Enum.EasingStyle.Quint)
			refs.strip.Position = UDim2.new(1, 20, 0, 92)
			UIHelpers.tween(refs.strip, 0.45, { Position = UDim2.new(1, -52, 0, 92) }, Enum.EasingStyle.Quint)
			UIHelpers.tween(fade, 0.45, { BackgroundTransparency = 1 })
			task.delay(0.46, function() if myToken == token then fadeGui.Enabled = false end end)
		end)
	end
	local function confirm(): boolean
		if not isOpen then return false end
		local allowed = canSelect()
		if not allowed then return false end
		local cur = current()
		if selectedId == cur then
			play("MenuBack")
			close()
			return false
		end
		local ok, err = pcall(env.onConfirm, selectedId)
		if not ok then warn("FightingLab fighter select: confirm failed: " .. tostring(err)) end
		play("MenuSelect")
		refs.stamp.Visible = true
		refs.stampScale.Scale = 1.6
		UIHelpers.tween(refs.stampScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		if live and previewsOn then
			stageState.pose = "Intro"
			stageState.pushGoal = 0.35
			stageState.confirmUntil = os.clock() + FighterSelect.CONFIRM_HOLD
			local myToken = token
			task.delay(FighterSelect.CONFIRM_HOLD, function() if myToken == token and isOpen then close() end end)
		else
			close()
		end
		return true
	end
	refs.select = function(id: string) selectId(id) end
	refs.close = close
	refs.confirm = confirm

	controller = {
		gui = gui,
		open = open,
		close = close,
		isOpen = function() return isOpen end,
		selected = function() return selectedId end,
		select = function(id: string) selectId(id) end,
		step = function(delta: number)
			local i = table.find(Roster.order, selectedId) or 1
			selectId(Roster.order[((i - 1 + delta) % #Roster.order) + 1])
			play("MenuMove")
		end,
		confirm = confirm,
		refresh = function()
			if not isOpen then return end
			local allowed = canSelect()
			if not allowed then close(); return end
			renderInfo(false)
		end,
		handleKey = function(key: Enum.KeyCode): boolean
			if not isOpen then return false end
			if os.clock() < stageState.confirmUntil then return true end
			if LEFT_KEYS[key] then controller.step(-1); return true end
			if RIGHT_KEYS[key] then controller.step(1); return true end
			if CONFIRM_KEYS[key] then confirm(); return true end
			if BACK_KEYS[key] then play("MenuBack"); close(); return true end
			return false
		end,
		previewState = function()
			local ready, cold = {}, 0
			for id, rig in rigs do ready[id] = rig.ready; if rig.cold then cold += 1 end end
			return { open = isOpen, selected = selectedId, shown = shownId, ready = ready, cold = cold, rigs = #Roster.order, flight = stageState.flight, level = stageState.level }
		end,
		destroy = function()
			if destroyed then return end
			if isOpen then
				isOpen = false
				finishClose()
			end
			destroyed = true
			token += 1
			unbindRender()
			releaseRigs()
			restorePlayerList()
			releaseTilePortraits()
			for _, c in conns do c:Disconnect() end
			table.clear(conns)
			if refs.unfit then refs.unfit() end
			gui:Destroy()
			fadeGui:Destroy()
		end,
	}
	return controller
end

return FighterSelect
