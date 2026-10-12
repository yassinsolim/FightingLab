--!strict
-- Lobby spectators (contract v5 stretch): players near an arena see the fight in 3D. The server sends packed
-- snapshots of nearby matches at 20 Hz; FightSession forwards the ones that are not the local player's match here.
-- Fighters are pooled rigs from CharacterPresenter (no clothing refit), posed with MotionPlayer on unique slots
-- (>= 10) in arena space around the arena's FightOrigin, with simple hit sparks. Nothing is shown while the local
-- player is in a fight session of their own.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Lab = ReplicatedStorage:WaitForChild("FightingLab")
local Config = require(Lab:WaitForChild("CombatConfig"))
local RenderBuffer = require(Lab:WaitForChild("RenderBuffer"))
local NetProtocol = require(Lab:WaitForChild("NetProtocol"))
local MotionPlayer = require(script.Parent:WaitForChild("MotionPlayer"))

type Watched = {
	matchId: string, arenaId: string, origin: Vector3, buffer: RenderBuffer.Buffer, events: RenderBuffer.EventQueue,
	ids: { string }, models: { Model? }, rigs: { MotionPlayer.RigInfo? }, roots: { BasePart? }, slotBase: number, lastSeen: number,
	-- Opponent contact-aim heights per rig (MotionPlayer.standingHeights), so spectated strikes land like the main fight.
	aims: { { [string]: number }? },
	latest: RenderBuffer.Entry?,
}

local M = {}
M.MaxMatches = 2
M.Timeout = 1.25
local ctx: any = nil
local watched: { [string]: Watched } = {}
local freeBases: { number } = { 10, 12, 14, 16 }
local sparks: { { part: BasePart, started: number, size: number } } = {}
local sparkFolder: Folder? = nil
local nextSpark = 1
local SPARK_LIFE = 0.16

local function sessionActive(): boolean
	local session = ctx and ctx.modules and ctx.modules.FightSession
	return session ~= nil and session.isFightActive ~= nil and session.isFightActive()
end

local function presenter(): any
	return ctx and ctx.modules and ctx.modules.Characters
end

local function arenaFor(matchId: string): (string?, Vector3?)
	local stations = Lab:FindFirstChild("Stations")
	local arenaId: string? = nil
	if stations then
		for _, station in stations:GetChildren() do
			if station:GetAttribute("MatchId") == matchId then arenaId = station.Name break end
		end
	end
	arenaId = arenaId or matchId:match("^([^#]+)#")
	if not arenaId then return nil, nil end
	local world = Workspace:FindFirstChild("FightingLabWorld")
	local arenas = world and world:FindFirstChild("Arenas")
	local arena = arenas and arenas:FindFirstChild(arenaId)
	local originPart = arena and arena:FindFirstChild("FightOrigin", true)
	if originPart and originPart:IsA("BasePart") then return arenaId, originPart.Position end
	return nil, nil
end

local function releaseRigs(w: Watched)
	local chars = presenter()
	for i = 1, 2 do
		local model = w.models[i]
		if model and chars and chars.releasePreview then chars.releasePreview(model) end
		w.models[i] = nil
		w.rigs[i] = nil
		w.roots[i] = nil
		w.aims[i] = nil
		MotionPlayer.reset(w.slotBase + i - 1)
	end
end

local function drop(matchId: string)
	local w = watched[matchId]
	if not w then return end
	releaseRigs(w)
	table.insert(freeBases, w.slotBase)
	watched[matchId] = nil
end

function M.clear()
	for matchId in watched do drop(matchId) end
end

local function ensureRigs(w: Watched, entry: RenderBuffer.Entry)
	local chars = presenter()
	if not chars or not chars.acquirePreview then return end
	local ids = { entry.p1Id, entry.p2Id }
	for i = 1, 2 do
		if w.ids[i] ~= ids[i] and w.models[i] then
			chars.releasePreview(w.models[i])
			w.models[i] = nil
		end
		if not w.models[i] then
			local ok, model = pcall(chars.acquirePreview, ids[i])
			if ok and model then
				w.models[i] = model
				w.rigs[i] = MotionPlayer.collectRig(model)
				local okAim, aim = pcall(MotionPlayer.standingHeights, w.rigs[i], ids[i])
				w.aims[i] = if okAim then aim else nil
				local root = model:FindFirstChild("HumanoidRootPart")
				w.roots[i] = if root and root:IsA("BasePart") then root else nil
				w.ids[i] = ids[i]
				MotionPlayer.reset(w.slotBase + i - 1)
			end
		end
	end
end

function M.onSnapshot(raw: unknown)
	if not ctx or sessionActive() then return end
	local matchId = NetProtocol.matchIdOf(raw)
	if not matchId then return end
	local w = watched[matchId]
	if not w then
		local count = 0
		for _ in watched do count += 1 end
		if count >= M.MaxMatches or #freeBases == 0 then return end
		local arenaId, origin = arenaFor(matchId)
		if not arenaId or not origin then return end
		w = {
			matchId = matchId, arenaId = arenaId, origin = origin, buffer = RenderBuffer.new({ period = NetProtocol.SpectatorEvery / Config.FPS, delay = 0.09 }),
			events = RenderBuffer.newEventQueue(), ids = {}, models = {}, rigs = {}, roots = {}, aims = {}, slotBase = table.remove(freeBases, 1) :: number,
			lastSeen = os.clock(), latest = nil,
		}
		watched[matchId] = w
	end
	local unpacked = NetProtocol.unpackEntry(raw)
	local entry = if unpacked then RenderBuffer.parse(unpacked) else nil
	if not entry then return end
	w.lastSeen = os.clock()
	if RenderBuffer.push(w.buffer, entry, workspace:GetServerTimeNow()) then RenderBuffer.clearEvents(w.events) end
	for _, e in entry.events do RenderBuffer.enqueueEvent(w.events, e) end
	w.latest = entry
	ensureRigs(w, entry)
end

local function rootCFrame(pos: Vector3, facing: Vector3, rootHeight: number, offset: Vector3, base: Vector3): CFrame
	local forward = if facing.Magnitude > 0.01 then facing.Unit else Vector3.xAxis
	local right = forward:Cross(Vector3.yAxis)
	right = if right.Magnitude < 0.01 then Vector3.xAxis else right.Unit
	local center = Vector3.new(base.X + pos.X, base.Y + rootHeight + math.max(0, pos.Y), base.Z + pos.Z) + right * offset.X + Vector3.yAxis * offset.Y + forward * offset.Z
	return CFrame.lookAt(center, center + forward)
end

local function spark(at: Vector3, color: Color3, size: number)
	local folder = sparkFolder
	if not folder then return end
	local item = sparks[nextSpark]
	nextSpark = nextSpark % #sparks + 1
	item.part.Color = color
	item.part.CFrame = CFrame.new(at)
	item.part.Transparency = 0.15
	item.size = size
	item.started = os.clock()
end

local function sparkColor(e: RenderBuffer.SnapEvent): Color3
	if e.kind == "Block" then return Color3.fromRGB(120, 190, 255) end
	if e.kind == "KO" or e.counter then return Color3.fromRGB(255, 96, 80) end
	if e.tier == "Heavy" or e.tier == "Launch" then return Color3.fromRGB(255, 170, 80) end
	return Color3.fromRGB(255, 226, 140)
end

local function poseMatch(w: Watched, now: number, dt: number)
	local renderT = RenderBuffer.renderTime(w.buffer, now)
	local entry = w.latest
	if not entry then return end
	local views = {}
	for i = 1, 2 do views[i] = RenderBuffer.sampleAt(w.buffer, i, renderT) end
	if not views[1] or not views[2] then return end
	-- Each fighter aims at the other, so both views carry their aim heights before either is sampled.
	for i = 1, 2 do (views[i] :: any).aimHeights = w.aims[i] end
	for i = 1, 2 do
		local rig, root, view = w.rigs[i], w.roots[i], views[i] :: any
		if rig and root then
			local slot = w.slotBase + i - 1
			-- MotionPlayer looks up "the other fighter" at fighters[1] for slots other than 1, and victory by slot number.
			local frame = {
				now = now, dt = dt, phase = entry.phase, hitstop = entry.hitstop, ko = entry.ko,
				winner = if entry.winner == 1 then w.slotBase elseif entry.winner == 2 then w.slotBase + 1 else 0,
				fighters = { views[3 - i], views[i] },
			}
			view.characterId = w.ids[i]
			view.rootHeight = rig.rootHeight
			view.legLength = rig.legLength
			local ok, pose = pcall(MotionPlayer.sample, Config, view, frame, slot)
			if ok then
				root.CFrame = rootCFrame(view.pos, view.facing, rig.rootHeight, pose.rootOffset, w.origin)
				MotionPlayer.apply(rig, pose, w.origin.Y)
			end
		end
	end
	for _, e in RenderBuffer.drainEvents(w.events, renderT) do
		if e.kind ~= "Whiff" and e.kind ~= "Crush" and e.point then
			spark(w.origin + e.point, sparkColor(e), if e.kind == "KO" then 3.2 elseif e.tier == "Heavy" or e.tier == "Launch" then 2.2 else 1.4)
		end
	end
end

function M.update(_frame: any)
	if not ctx then return end
	if sessionActive() then
		if next(watched) then M.clear() end
	else
		local now = workspace:GetServerTimeNow()
		local clock = os.clock()
		local dt = if typeof(_frame) == "table" and typeof(_frame.dt) == "number" then _frame.dt else 1 / 60
		for matchId, w in watched do
			if clock - w.lastSeen > M.Timeout then drop(matchId) else poseMatch(w, now, dt) end
		end
	end
	local clock = os.clock()
	for _, item in sparks do
		if item.started > 0 then
			local t = (clock - item.started) / SPARK_LIFE
			if t >= 1 then
				item.started = 0
				item.part.Transparency = 1
			else
				local s = item.size * (0.4 + 0.6 * t)
				item.part.Size = Vector3.new(s, s, s)
				item.part.Transparency = 0.15 + 0.85 * t
			end
		end
	end
	if ctx.gui then
		local count = 0
		for _ in watched do count += 1 end
		ctx.gui:SetAttribute("SpectatedMatches", count)
	end
end

function M.init(newCtx: any)
	ctx = newCtx
	local folder = Instance.new("Folder")
	folder.Name = "FightingLabSpectatorFx"
	for i = 1, 8 do
		local p = Instance.new("Part")
		p.Name = "Spark"
		p.Shape = Enum.PartType.Ball
		p.Material = Enum.Material.Neon
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Transparency = 1
		p.Size = Vector3.one
		p.CFrame = CFrame.new(0, -400, 0)
		p.Parent = folder
		sparks[i] = { part = p, started = 0, size = 1 }
	end
	folder.Parent = Workspace
	sparkFolder = folder
end

return M
