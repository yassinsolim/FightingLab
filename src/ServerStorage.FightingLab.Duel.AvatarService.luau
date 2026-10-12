--!strict
-- Lobby avatars (contract v5 section 0/4): every player walks the lobby as their selected fighter, spawned with
-- player:LoadCharacterWithHumanoidDescription(Factory.describe(spec)) (+ Factory.dressCharacter when available).
-- Layered clothing refits asynchronously on every client after a character appears, so a new character stays
-- concealed (and anchored) until its appearance has loaded and clients had time to fit the clothing. While the
-- owner fights or practises, the avatar is frozen in place (anchored, invisible, non-colliding) and restored later
-- without a respawn (a respawn would trigger another refit).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetProtocol = require(ReplicatedStorage:WaitForChild("FightingLab"):WaitForChild("NetProtocol"))

export type Options = {
	factory: any,
	specs: any,
	defaultFighter: string?,
	spawnFrame: (() -> CFrame?)?,
	canRespawn: ((player: Player) -> boolean)?,
	onSpawned: ((player: Player, character: Model) -> ())?,
}

type Saved = { [Instance]: { [string]: any } }
type Record = {
	generation: number, loading: boolean, frozen: boolean, reloadQueued: boolean, spawnAt: CFrame?,
	saved: Saved, concealed: Model?, anchored: boolean, conns: { RBXScriptConnection }, watch: { RBXScriptConnection },
	playerConns: { RBXScriptConnection },
}

local AvatarService = {}
AvatarService.__index = AvatarService

AvatarService.SettleSeconds = 0.8
AvatarService.AppearanceTimeout = 8
AvatarService.RespawnDelay = 2
AvatarService.KillY = -80
-- Concealment value written to Transparency. Anything a script writes while concealed (e.g. dressCharacter hiding
-- the hands of glove fighters) is caught by the change signal and becomes the value restored on reveal, so the
-- sentinel must differ from every value such scripts write (1 and 0).
AvatarService.ConcealTransparency = 0.999

function AvatarService.new(opts: Options)
	local self = setmetatable({}, AvatarService)
	self.factory = opts.factory
	self.specs = opts.specs
	self.defaultFighter = opts.defaultFighter or "Kael"
	self.spawnFrame = opts.spawnFrame
	self.canRespawn = opts.canRespawn
	self.onSpawned = opts.onSpawned
	self.records = {} :: { [Player]: Record }
	return self
end

function AvatarService:record(player: Player): Record
	local rec = self.records[player]
	if rec then return rec end
	rec = {
		generation = 0, loading = false, frozen = false, reloadQueued = false, spawnAt = nil,
		saved = {}, concealed = nil, anchored = false, conns = {}, watch = {}, playerConns = {},
	}
	self.records[player] = rec
	return rec
end

local function disconnectAll(list: { RBXScriptConnection })
	for _, c in list do c:Disconnect() end
	table.clear(list)
end

local function rootOf(character: Model?): BasePart?
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function aliveHumanoid(character: Model?): Humanoid?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then return humanoid end
	return nil
end

-- Puts a character on the floor below `cf` (exit markers may sit at any height; non-colliding markers are ignored).
function AvatarService.placeAt(character: Model, cf: CFrame)
	local root = rootOf(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local height = (if humanoid then humanoid.HipHeight else 2) + (if root then root.Size.Y * 0.5 else 1)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = {}
	for _, p in Players:GetPlayers() do if p.Character then table.insert(exclude, p.Character) end end
	params.FilterDescendantsInstances = exclude
	params.RespectCanCollide = true
	local from = cf.Position + Vector3.new(0, 4, 0)
	local hit = workspace:Raycast(from, Vector3.new(0, -40, 0), params)
	local y = if hit then hit.Position.Y + height + 0.05 else cf.Position.Y + height
	local look = cf.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	local pos = Vector3.new(cf.Position.X, y, cf.Position.Z)
	character:PivotTo(if flat.Magnitude > 0.01 then CFrame.lookAt(pos, pos + flat.Unit) else CFrame.new(pos))
end

local function concealOne(self: any, rec: Record, inst: Instance)
	if rec.saved[inst] then return end
	local sentinel = AvatarService.ConcealTransparency
	if inst:IsA("BasePart") then
		rec.saved[inst] = { Transparency = inst.Transparency, CanCollide = inst.CanCollide, CanQuery = inst.CanQuery, CanTouch = inst.CanTouch }
		inst.Transparency = sentinel
		inst.CanCollide = false
		inst.CanQuery = false
		inst.CanTouch = false
	elseif inst:IsA("Decal") then
		rec.saved[inst] = { Transparency = inst.Transparency }
		inst.Transparency = sentinel
	elseif inst:IsA("Humanoid") then
		rec.saved[inst] = { DisplayDistanceType = inst.DisplayDistanceType }
		inst.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		return
	elseif inst:IsA("BillboardGui") or inst:IsA("SurfaceGui") then
		rec.saved[inst] = { Enabled = inst.Enabled }
		inst.Enabled = false
		return
	else
		return
	end
	-- Keep intentional writes made while concealed (they become the restored value).
	local target = inst :: any
	table.insert(rec.watch, target:GetPropertyChangedSignal("Transparency"):Connect(function()
		local saved = rec.saved[inst]
		if not saved then return end
		local value = target.Transparency
		if value ~= sentinel then
			saved.Transparency = value
			target.Transparency = sentinel
		end
	end))
end

function AvatarService:conceal(player: Player, character: Model)
	local rec = self:record(player)
	if rec.concealed == character then return end
	if rec.concealed then self:reveal(player) end
	rec.concealed = character
	for _, d in character:GetDescendants() do concealOne(self, rec, d) end
	table.insert(rec.watch, character.DescendantAdded:Connect(function(d)
		if rec.concealed == character then concealOne(self, rec, d) end
	end))
	local root = rootOf(character)
	if root then
		rec.anchored = true
		root.Anchored = true
	end
end

function AvatarService:reveal(player: Player)
	local rec = self:record(player)
	local character = rec.concealed
	disconnectAll(rec.watch)
	for inst, props in rec.saved do
		if inst.Parent then
			for key, value in props do (inst :: any)[key] = value end
		end
	end
	table.clear(rec.saved)
	rec.concealed = nil
	if character and rec.anchored then
		local root = rootOf(character)
		if root then root.Anchored = false end
	end
	rec.anchored = false
end

-- Concealed while loading or frozen, visible otherwise.
function AvatarService:apply(player: Player)
	local rec = self:record(player)
	local character = player.Character
	if not character then return end
	if rec.loading or rec.frozen then self:conceal(player, character) else self:reveal(player) end
end

function AvatarService:isLoading(player: Player): boolean
	local rec = self.records[player]
	return rec ~= nil and rec.loading
end

local function specFor(self: any, player: Player): (string, any)
	local id = player:GetAttribute("FighterId")
	local specs = self.specs and self.specs.specs or {}
	if typeof(id) ~= "string" or not specs[id] then id = self.defaultFighter end
	return id :: string, specs[id]
end

local function loadWithDescription(player: Player, description: HumanoidDescription)
	local p: any = player
	local ok = pcall(function() p:LoadCharacterWithHumanoidDescriptionAsync(description) end)
	if not ok then p:LoadCharacterWithHumanoidDescription(description) end
end

local function waitAppearance(player: Player, character: Model, timeout: number)
	if player:HasAppearanceLoaded() then return end
	local done = false
	local conn = player.CharacterAppearanceLoaded:Connect(function(loaded)
		if loaded == character then done = true end
	end)
	local deadline = os.clock() + timeout
	while not done and os.clock() < deadline and character.Parent and not player:HasAppearanceLoaded() do task.wait(0.05) end
	conn:Disconnect()
end

function AvatarService:onCharacterAdded(player: Player, character: Model)
	local rec = self:record(player)
	disconnectAll(rec.conns)
	if rec.concealed and rec.concealed ~= character then
		disconnectAll(rec.watch)
		table.clear(rec.saved)
		rec.concealed = nil
		rec.anchored = false
	end
	if rec.loading or rec.frozen then
		self:conceal(player, character)
		if rec.spawnAt then AvatarService.placeAt(character, rec.spawnAt) end
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
	if humanoid and humanoid:IsA("Humanoid") then
		table.insert(rec.conns, humanoid.Died:Connect(function()
			task.delay(AvatarService.RespawnDelay, function()
				if player.Parent and player.Character == character and not rec.loading then
					local allowed = if self.canRespawn then self.canRespawn(player) else true
					if allowed then self:spawn(player, nil) end
				end
			end)
		end))
	end
end

function AvatarService:attach(player: Player)
	local rec = self:record(player)
	disconnectAll(rec.playerConns)
	table.insert(rec.playerConns, player.CharacterAdded:Connect(function(character)
		self:onCharacterAdded(player, character)
	end))
	if player.Character then self:onCharacterAdded(player, player.Character) end
end

function AvatarService:detach(player: Player)
	local rec = self.records[player]
	if not rec then return end
	rec.generation += 1
	disconnectAll(rec.conns)
	disconnectAll(rec.watch)
	disconnectAll(rec.playerConns)
	self.records[player] = nil
end

-- Loads (or reloads) the player's character as their FighterId. `at` places it there once loaded (respawns at
-- exits, reloads in place); otherwise a LobbySpawn is used. Calls made during a load are coalesced.
function AvatarService:spawn(player: Player, at: CFrame?)
	local rec = self:record(player)
	if at then rec.spawnAt = at end
	if rec.loading then
		rec.reloadQueued = true
		return
	end
	rec.generation += 1
	local generation = rec.generation
	rec.loading = true
	if not at then rec.spawnAt = if self.spawnFrame then self.spawnFrame() else nil end
	local id, spec = specFor(self, player)
	local ok, err = pcall(function()
		if not spec then error("no CharacterSpecs entry for " .. id) end
		loadWithDescription(player, self.factory.describe(spec))
	end)
	if not ok then
		warn(("FightingLab AvatarService: could not load %s as %s (%s); using a default avatar"):format(player.Name, id, tostring(err)))
		pcall(function() (player :: any):LoadCharacter() end)
	end
	if rec.generation ~= generation or not player.Parent then return end
	local character = player.Character
	if character then
		if rec.concealed ~= character then self:conceal(player, character) end
		if rec.spawnAt then AvatarService.placeAt(character, rec.spawnAt) end
		waitAppearance(player, character, AvatarService.AppearanceTimeout)
		if spec and self.factory.dressCharacter and character.Parent then
			local dressed, dressErr = pcall(self.factory.dressCharacter, character, spec)
			if not dressed then warn("FightingLab AvatarService: dressCharacter failed for " .. id .. ": " .. tostring(dressErr)) end
		end
		-- Clients keep the new character hidden until they have this many accessories/wrap layers (Client.AvatarGate).
		if character.Parent then AvatarService.publishAppearance(character) end
		-- Clients fit layered clothing after it replicates; keep the character hidden a little longer.
		task.wait(AvatarService.SettleSeconds)
	end
	if rec.generation ~= generation or not player.Parent then return end
	rec.loading = false
	character = player.Character
	if character and character.Parent then
		if rec.spawnAt and not rec.frozen then AvatarService.placeAt(character, rec.spawnAt) end
		self:apply(player)
		character:SetAttribute("FighterId", id)
		if self.onSpawned then self.onSpawned(player, character) end
	end
	rec.spawnAt = nil
	if rec.reloadQueued then
		rec.reloadQueued = false
		local root = rootOf(player.Character)
		self:spawn(player, if root then root.CFrame else nil)
	end
end

-- Reload in place with the current FighterId (fighter select).
function AvatarService:reload(player: Player)
	local root = rootOf(player.Character)
	local at = if root and aliveHumanoid(player.Character) then root.CFrame else nil
	task.spawn(function() self:spawn(player, at) end)
end

function AvatarService:freeze(player: Player)
	local rec = self:record(player)
	rec.frozen = true
	if player.Character then self:conceal(player, player.Character) end
end

-- Restores a frozen avatar at `at` (the arena exit) without a respawn, or respawns it there when it died.
function AvatarService:unfreeze(player: Player, at: CFrame?)
	local rec = self:record(player)
	rec.frozen = false
	local character = player.Character
	if rec.loading then
		if at then rec.spawnAt = at end
		return
	end
	if not character or not character.Parent or not aliveHumanoid(character) then
		task.spawn(function() self:spawn(player, at) end)
		return
	end
	if at then AvatarService.placeAt(character, at) end
	self:apply(player)
end

-- Publishes the dressed character's accessory and wrap-layer counts (NetProtocol.appearanceCounts) as attributes.
function AvatarService.publishAppearance(character: Model)
	local accessories, wrapLayers = NetProtocol.appearanceCounts(character)
	character:SetAttribute(NetProtocol.AccessoryCountAttribute, accessories)
	character:SetAttribute(NetProtocol.WrapLayerCountAttribute, wrapLayers)
end

-- Players who fall off the world are put back on a lobby spawn (no reload, no refit).
function AvatarService:rescue(player: Player)
	local rec = self.records[player]
	if not rec or rec.loading or rec.frozen then return end
	local character = player.Character
	local root = rootOf(character)
	if not character or not root then return end
	if root.Position.Y > AvatarService.KillY then return end
	local at = if self.spawnFrame then self.spawnFrame() else nil
	if at then
		root.AssemblyLinearVelocity = Vector3.zero
		AvatarService.placeAt(character, at)
	end
end

return AvatarService
