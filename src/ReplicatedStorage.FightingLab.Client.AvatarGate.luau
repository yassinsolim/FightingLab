--!strict
-- Client avatar gate (follow-up to the "player model goes naked" complaint). A character reaches clients before its
-- clothing: measured in Play, the model arrives with 0 accessories, all items follow 0.10-0.12 s later, and meshes
-- and textures finish loading 0.13-0.43 s after the client first sees the character. So every character that
-- appears on this client (the local player's, other players' respawns and fighter swaps, and characters already
-- present when this client joins) stays hidden here (LocalTransparencyModifier = 1, re-applied every frame right
-- after the camera update so the camera's transparency controller cannot undo it) until
--   * its Accessory, WrapLayer and rigid-extra counts (the welded gloves, shoes, belts and fists of the round-4 rigs)
--     reach the AccessoryCount / WrapLayerCount / ExtraCount attributes that the server publishes after dressing
--     (AvatarService.publishAppearance), and
--   * ContentProvider:PreloadAsync over its descendants and every texture id they use that is not fetched yet has
--     finished (in task.spawn, never blocking), and FlashDetector.check says every mesh is fetched and no texture is
--     mid-fetch,
-- or MaxSeconds have passed. The server's own concealment (appearance loaded + dressed + 0.8 s) stays on top.
-- track() is the generic gate: HudController portraits, the FighterSelect tiles and stage rigs and the lobby identity
-- portrait use it to keep fresh clones invisible the same way.
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Lab = script.Parent.Parent
local NetProtocol = require(Lab:WaitForChild("NetProtocol"))
local FlashDetector = require(script.Parent:WaitForChild("FlashDetector"))

local AvatarGate = {}
AvatarGate.MaxSeconds = 3
-- After the preload, layered clothing still refits for a few frames.
AvatarGate.CharacterSettleSeconds = 0.2
AvatarGate.HiddenModifier = 1
AvatarGate.RenderStepName = "FightingLabAvatarGate"

export type Decision = "wait" | "preload" | "release" | "timeout"
export type State = {
	elapsed: number,
	maxSeconds: number,
	minSeconds: number,
	settleSeconds: number,
	needExpected: boolean,
	accessories: number,
	wrapLayers: number,
	wantAccessories: number?,
	wantWrapLayers: number?,
	-- Rigid welded gear (FightingLabExtra parts): present count and the expected count (nil = not checked).
	extras: number?,
	wantExtras: number?,
	preload: string,
	sincePreload: number,
	-- FlashDetector.check after the preload: every mesh fetched, no texture mid-fetch (nil = not checked).
	contentReady: boolean?,
}
export type TrackOptions = {
	hide: (model: Model) -> (),
	show: (model: Model, reason: string) -> (),
	-- Expected counts (nil while unknown): accessories, wrap layers, rigid extras. With needExpected the gate waits for
	-- them; without, nil means "none".
	expected: ((model: Model) -> (number?, number?, number?))?,
	needExpected: boolean?,
	preload: ((list: { any }) -> ())?,
	-- Content readiness after the preload (default FlashDetector.check over the live fetch status).
	contentReady: ((model: Model) -> boolean)?,
	clock: (() -> number)?,
	maxSeconds: number?,
	minSeconds: number?,
	settleSeconds: number?,
	-- Tests poll manual gates themselves; other gates are polled every frame on the client.
	manual: boolean?,
	label: string?,
}

-- Pure gate rule: items first, then one preload, then every asset fetched, then an optional settle; never longer than
-- maxSeconds.
function AvatarGate.decide(s: State): Decision
	if s.elapsed >= s.maxSeconds then return "timeout" end
	local itemsReady: boolean
	if s.wantAccessories == nil then
		itemsReady = not s.needExpected
	else
		itemsReady = s.accessories >= s.wantAccessories and s.wrapLayers >= (s.wantWrapLayers or 0)
			and (s.wantExtras == nil or (s.extras or 0) >= s.wantExtras)
	end
	if not itemsReady then return "wait" end
	if s.preload == "none" then return "preload" end
	if s.preload ~= "done" then return "wait" end
	if s.contentReady == false then return "wait" end
	if s.sincePreload < s.settleSeconds or s.elapsed < s.minSeconds then return "wait" end
	return "release"
end

-- Default content readiness: FlashDetector's live check (meshes fetched, no texture mid-fetch).
function AvatarGate.contentReady(model: Model): boolean
	return FlashDetector.check(model, nil, nil).complete
end

local Gate = {}
Gate.__index = Gate

local active: { [Model]: any } = {}
local history: { string } = {}
local stepping = false
local started = false
local diagnostics: Instance? = nil
local preloadOverride: ((list: { any }) -> ())? = nil

local function defaultPreload(list: { any })
	local override = preloadOverride
	if override then return override(list) end
	ContentProvider:PreloadAsync(list)
end
-- Tests only: replaces ContentProvider:PreloadAsync for gates without their own preload (nil restores it).
function AvatarGate._setPreloadForTests(fn: ((list: { any }) -> ())?) preloadOverride = fn end

local function report(gate: any)
	local function at(t: number?): string
		return if t then string.format("%.2fs", t - gate.started) else "-"
	end
	local text = string.format("%s %s: arrived %d/%d items, items %s, preload done %s, assets %s, shown %s",
		gate.label, gate.reason, gate.firstAccessories, gate.firstWrapLayers, at(gate.itemsAt), at(gate.preloadDoneAt), at(gate.contentAt), at(gate.releasedAt))
	table.insert(history, text)
	while #history > 8 do table.remove(history, 1) end
	local target = diagnostics
	if target then
		target:SetAttribute("AvatarGateLast", text)
		target:SetAttribute("AvatarGateHistory", table.concat(history, " | "))
	end
end

function Gate:release(reason: string, now: number?)
	if self.released then return end
	self.released = true
	self.reason = reason
	self.releasedAt = now or self.clock()
	if active[self.model] == self then active[self.model] = nil end
	if reason ~= "removed" then self.opts.show(self.model, reason) end
	report(self)
end

-- Advances the gate; returns true once the model is shown (or gone).
function Gate:poll(now: number?): boolean
	if self.released then return true end
	local model = self.model
	if not model.Parent then
		self:release("removed", now)
		return true
	end
	local t = now or self.clock()
	local accessories, wrapLayers, extras = NetProtocol.appearanceCounts(model)
	local wantAccessories, wantWrapLayers, wantExtras = nil, nil, nil
	local expected = self.opts.expected
	if expected then wantAccessories, wantWrapLayers, wantExtras = expected(model) end
	local contentReady: boolean? = nil
	if self.preloadState == "done" then
		local check = self.opts.contentReady or AvatarGate.contentReady
		local okCheck, ready = pcall(check, model)
		contentReady = not okCheck or ready == true
		-- The settle time counts from the moment everything is fetched.
		if contentReady and not self.contentAt then self.contentAt = t elseif not contentReady then self.contentAt = nil end
	end
	local decision = AvatarGate.decide({
		elapsed = t - self.started, maxSeconds = self.maxSeconds, minSeconds = self.minSeconds,
		settleSeconds = self.settleSeconds, needExpected = self.needExpected,
		accessories = accessories, wrapLayers = wrapLayers, wantAccessories = wantAccessories, wantWrapLayers = wantWrapLayers,
		extras = extras, wantExtras = wantExtras,
		preload = self.preloadState, sincePreload = if self.preloadState == "done" and self.contentAt then t - self.contentAt else 0,
		contentReady = contentReady,
	})
	if decision == "release" or decision == "timeout" then
		self:release(decision, t)
		return true
	end
	if decision == "preload" then
		self.itemsAt = t
		self.preloadState = "running"
		-- The instances (their meshes load through them) plus every texture id they use that has not finished yet: a
		-- model parked out of sight (or never drawn) has not asked for its textures yet. Mesh ids are never preloaded as
		-- strings (that request fails in Studio and overwrites the instance's Success) and finished ids are skipped so
		-- shared assets are not fetched again.
		local list: { any } = model:GetDescendants()
		for _, id in FlashDetector.pendingTextures(model) do table.insert(list, id) end
		local preload = self.opts.preload or defaultPreload
		task.spawn(function()
			local ok, err = pcall(preload, list)
			if not ok then warn("FightingLab AvatarGate: preload failed for " .. self.label .. ": " .. tostring(err)) end
			self.preloadDoneAt = self.clock()
			self.preloadState = "done"
		end)
	end
	self.opts.hide(model)
	return false
end

-- Polls every automatic gate (the client does this each frame right after the camera update).
function AvatarGate.step(now: number?)
	for _, gate in active do
		if not gate.manual then gate:poll(now) end
	end
end

local function ensureStepping()
	if stepping or not RunService:IsClient() then return end
	stepping = true
	RunService:BindToRenderStep(AvatarGate.RenderStepName, Enum.RenderPriority.Camera.Value + 1, function()
		AvatarGate.step(nil)
	end)
end

-- Starts hiding `model` now; it is shown again by opts.show once the gate opens. One gate per model.
function AvatarGate.track(model: Model, opts: TrackOptions): any
	local previous = active[model]
	if previous then
		previous.released = true
		active[model] = nil
	end
	local clock = opts.clock or os.clock
	local accessories, wrapLayers = NetProtocol.appearanceCounts(model)
	local gate = setmetatable({
		model = model, opts = opts, clock = clock, started = clock(), label = opts.label or model.Name,
		maxSeconds = opts.maxSeconds or AvatarGate.MaxSeconds, minSeconds = opts.minSeconds or 0,
		settleSeconds = opts.settleSeconds or 0, needExpected = opts.needExpected == true, manual = opts.manual == true,
		preloadState = "none", preloadDoneAt = nil :: number?, itemsAt = nil :: number?, contentAt = nil :: number?,
		released = false, reason = nil :: string?, releasedAt = nil :: number?,
		firstAccessories = accessories, firstWrapLayers = wrapLayers,
	}, Gate)
	active[model] = gate
	opts.hide(model)
	if not gate.manual then ensureStepping() end
	return gate
end

function AvatarGate.isGated(model: Instance?): boolean
	return model ~= nil and model:IsA("Model") and active[model :: Model] ~= nil
end

-- Layered clothing refits for a few frames in a freshly parented preview clone.
AvatarGate.PreviewSettleSeconds = 0.25

-- Gates a preview of fighter `id` (viewport portraits, fighter-select tiles and stage rigs): `hide` keeps it out of
-- sight until it carries every item of its template (accessories, wrap layers, rigid gear) and every asset is
-- fetched, then `show` reveals it.
function AvatarGate.trackPreview(model: Model, id: string, hide: (Model) -> (), show: (Model, string) -> (), opts: { label: string?, manual: boolean?, clock: (() -> number)?, preload: ((list: { any }) -> ())?, contentReady: ((Model) -> boolean)? }?): any
	local o = opts or {}
	local inv = FlashDetector.templateInventory(id)
	return AvatarGate.track(model, {
		hide = hide, show = show, label = o.label or ("Preview " .. id),
		expected = function(): (number?, number?, number?)
			if inv then return inv.accessories, inv.wrapLayers, inv.extras end
			return 0, 0, 0
		end,
		settleSeconds = AvatarGate.PreviewSettleSeconds, manual = o.manual, clock = o.clock, preload = o.preload, contentReady = o.contentReady,
	})
end

local function setModifier(model: Model, value: number)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			(d :: any).LocalTransparencyModifier = value
		end
	end
end

function AvatarGate.hideCharacter(model: Model)
	setModifier(model, AvatarGate.HiddenModifier)
end

function AvatarGate.showCharacter(model: Model)
	setModifier(model, 0)
end

export type CharacterOptions = { clock: (() -> number)?, preload: ((list: { Instance }) -> ())?, manual: boolean? }

-- Gates a player character until it matches the server's published appearance and its assets are loaded.
function AvatarGate.gateCharacter(character: Model, opts: CharacterOptions?): any
	local o: CharacterOptions = opts or {}
	return AvatarGate.track(character, {
		hide = AvatarGate.hideCharacter, show = AvatarGate.showCharacter,
		expected = NetProtocol.expectedAppearance, needExpected = true, settleSeconds = AvatarGate.CharacterSettleSeconds,
		clock = o.clock, preload = o.preload, manual = o.manual, label = "Character " .. character.Name,
	})
end

-- Client start: gate every character that appears from now on, and the ones already here.
function AvatarGate.start()
	if started then return end
	started = true
	local function watch(player: Player)
		player.CharacterAdded:Connect(function(character) AvatarGate.gateCharacter(character) end)
		local current = player.Character
		if current then AvatarGate.gateCharacter(current) end
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do watch(player) end
	ensureStepping()
end

-- Diagnostics target (FightingLabHUD): AvatarGateLast / AvatarGateHistory attributes describe recent gates.
function AvatarGate.init(ctx: any)
	diagnostics = if ctx then ctx.gui else nil
end

function AvatarGate.history(): { string }
	return table.clone(history)
end

return AvatarGate
