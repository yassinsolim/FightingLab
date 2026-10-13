--!strict
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local States = require(script.Parent.Motion.States)
local Cinematic = require(script.Parent.Motion.Cinematic)

type Ctx = any
type CombatEvent = any

local M = {}
local ctx: Ctx? = nil
local audioFolder: Folder? = nil
local groups: { [string]: SoundGroup } = {}
local music: Sound? = nil
local previousStates: { [number]: string } = {}
local impactTrackers: { [number]: any } = {}
local lastPlayedAt: { [string]: number } = {}
local soundCursor = 0
local cineLast: number? = nil
-- Positional sounds come from arena-space sim positions; they play at origin + position.
local origin = Vector3.zero

local REQUIRED: { string } = {
	"HitLight", "HitMedium", "HitHeavy", "HitLaunch", "Counter", "Block", "Whiff", "ThrowGrab", "ThrowImpact", "ThrowBreak",
	"Parry", "Armor", "Crush", "KO", "Knockdown", "Land", "Dash", "MenuMove", "MenuSelect", "MenuBack", "RoundStart", "MusicBattle", "MusicMenu",
}

local function ensureGroup(name: string, volume: number): SoundGroup
	local existing = SoundService:FindFirstChild("FightingLab" .. name)
	if existing and existing:IsA("SoundGroup") then
		existing.Volume = volume
		groups[name] = existing
		return existing
	end
	local g = Instance.new("SoundGroup")
	g.Name = "FightingLab" .. name
	g.Volume = volume
	g.Parent = SoundService
	groups[name] = g
	return g
end

local function folder(): Folder
	local f = audioFolder
	assert(f, "AudioController used before init")
	return f
end

local function soundTemplate(name: string): Sound
	local s = folder():FindFirstChild(name)
	assert(s and s:IsA("Sound"), "ReplicatedStorage.FightingLab.Audio missing required Sound: " .. name)
	return s
end

local function groupFor(name: string): SoundGroup
	if string.sub(name, 1, 5) == "Music" then return groups.Music end
	if string.sub(name, 1, 8) == "Ambience" then return groups.Ambience end
	return groups.SFX
end

function M.requiredSounds(): { string }
	return table.clone(REQUIRED)
end

function M.assetManifest(): { { name: string, soundId: string, allowed: string } }
	local result = {}
	local f = audioFolder
	for _, name in REQUIRED do
		local soundId = ""
		if f then
			local s = f:FindFirstChild(name)
			if s and s:IsA("Sound") then soundId = s.SoundId end
		end
		table.insert(result, { name = name, soundId = soundId, allowed = "Existing in-place FightingLab Audio folder; no new upload or third-party extraction by camerafx." })
	end
	return result
end

function M._soundNameForEvent(e: CombatEvent): string
	if e.kind == "KO" then return "KO" end
	if e.kind == "Surge" then return "Armor" end
	if e.kind == "UltStart" then return "Parry" end
	if e.kind == "UltHit" then return if e.knockdown == true then "KO" else "HitHeavy" end
	if e.kind == "Block" then return "Block" end
	if e.kind == "Whiff" then return "Whiff" end
	if e.kind == "ThrowStart" then return "ThrowGrab" end
	if e.kind == "ThrowHit" then return "ThrowImpact" end
	if e.kind == "ThrowBreak" then return "ThrowBreak" end
	if e.kind == "Parry" then return "Parry" end
	if e.kind == "Armor" then return "Armor" end
	if e.kind == "Crush" then return "Crush" end
	if e.counter then return "Counter" end
	if e.launch or e.tier == "Launch" then return "HitLaunch" end
	if e.tier == "Heavy" or (e.damage or 0) >= 15 then return "HitHeavy" end
	if e.tier == "Medium" or (e.damage or 0) >= 10 then return "HitMedium" end
	return "HitLight"
end

function M.play(name: string, at: Vector3?)
	local now = os.clock()
	local minGap = if name == "Whiff" or name == "Dash" then 0.055 elseif name == "HitLight" then 0.026 else 0.038
	if (lastPlayedAt[name] or -math.huge) + minGap > now then return end
	lastPlayedAt[name] = now
	local template = soundTemplate(name)
	local s = template:Clone()
	s.SoundGroup = groupFor(name)
	soundCursor = (soundCursor % 17) + 1
	local detune = ((soundCursor % 5) - 2) * 0.018
	local gain = 1 + (((soundCursor * 7) % 5) - 2) * 0.035
	if name == "Counter" or name == "HitLaunch" or name == "KO" then
		gain += 0.08
	end
	s.PlaybackSpeed = math.clamp(template.PlaybackSpeed + detune, 0.82, 1.22)
	s.Volume = math.clamp(template.Volume * gain, 0, 1.4)
	if at then
		local p = Instance.new("Part")
		p.Name = "FightingLabOneShotAudio"
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Transparency = 1
		p.Size = Vector3.new(0.2, 0.2, 0.2)
		p.Position = at
		p.Parent = workspace
		s.RollOffMaxDistance = math.max(s.RollOffMaxDistance, 70)
		s.RollOffMinDistance = math.max(s.RollOffMinDistance, 8)
		s.Parent = p
		Debris:AddItem(p, math.max(1, s.TimeLength + 0.6))
	else
		s.Parent = SoundService
		Debris:AddItem(s, math.max(1, s.TimeLength + 0.6))
	end
	s:Play()
end

function M.playMusic(name: string?)
	local nextSound: Sound? = nil
	if name then
		local template = soundTemplate(name)
		nextSound = template:Clone()
		nextSound.SoundGroup = groups.Music
		nextSound.Looped = true
		nextSound.Volume = 0
		nextSound.Parent = SoundService
		nextSound:Play()
		TweenService:Create(nextSound, TweenInfo.new(0.65), { Volume = template.Volume }):Play()
	end
	local old = music
	music = nextSound
	if old then
		local tween = TweenService:Create(old, TweenInfo.new(0.52), { Volume = 0 })
		tween:Play()
		Debris:AddItem(old, 0.75)
	end
end

-- Surge and Ultimate (round 6): layered from the existing in-game sounds (no new assets), pitched down for weight.
-- Each layer = { sound, playback speed factor, volume factor }.
M.Layers = {
	Surge = { { "Armor", 0.62, 1.1 }, { "Counter", 0.7, 0.75 } },
	UltStart = { { "Parry", 0.64, 1.15 }, { "KO", 0.82, 0.55 } },
	UltHit = { { "HitHeavy", 0.9, 1.15 }, { "Counter", 0.84, 0.6 } },
	UltFinish = { { "KO", 0.84, 1.2 }, { "ThrowImpact", 0.78, 1.0 }, { "HitLaunch", 0.72, 0.8 } },
	UltLand = { { "Knockdown", 0.88, 1.1 }, { "ThrowImpact", 0.9, 0.5 } },
} :: { [string]: { { any } } }

function M.playLayered(kind: string, at: Vector3?)
	local layers = M.Layers[kind]
	if not layers then return end
	for _, layer in layers do
		local name, speed, gain = layer[1] :: string, layer[2] :: number, layer[3] :: number
		local f = audioFolder
		local template = f and f:FindFirstChild(name)
		if template and template:IsA("Sound") then
			local s = template:Clone()
			s.SoundGroup = groupFor(name)
			s.PlaybackSpeed = math.clamp(template.PlaybackSpeed * speed, 0.4, 2)
			s.Volume = math.clamp(template.Volume * gain, 0, 1.6)
			if at then
				local p = Instance.new("Part")
				p.Name = "FightingLabOneShotAudio"
				p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
				p.Transparency = 1
				p.Size = Vector3.new(0.2, 0.2, 0.2)
				p.Position = at
				p.Parent = workspace
				s.RollOffMaxDistance = math.max(s.RollOffMaxDistance, 80)
				s.RollOffMinDistance = math.max(s.RollOffMinDistance, 10)
				s.Parent = p
				Debris:AddItem(p, math.max(1.2, s.TimeLength / math.max(s.PlaybackSpeed, 0.1) + 0.6))
			else
				s.Parent = SoundService
				Debris:AddItem(s, math.max(1.2, s.TimeLength / math.max(s.PlaybackSpeed, 0.1) + 0.6))
			end
			s:Play()
		end
	end
	local c = ctx
	if c then c.gui:SetAttribute("AudioLastLayered", kind) end
end

function M.onEvent(e: CombatEvent)
	local at = if e.point then origin + e.point else nil
	if e.kind == "Surge" or e.kind == "UltStart" or e.kind == "UltHit" then
		M.playLayered(if e.kind == "UltHit" then (if e.knockdown == true then "UltFinish" else "UltHit") else e.kind, at)
		return
	end
	local soundName = M._soundNameForEvent(e)
	M.play(soundName, at)
	if e.launch == true or e.tier == "Launch" then
		M.play("HitHeavy", at)
	elseif e.counter == true and soundName ~= "Counter" then
		M.play("Counter", at)
	end
end

function M.onPhase(old: string, new: string)
	if new == "Ready" then
		M.play("RoundStart")
		M.playMusic("MusicBattle")
	elseif new == "MatchOver" then
		M.playMusic("MusicMenu")
	end
end

function M.setOrigin(o: Vector3)
	origin = o
end

-- Back to the lobby: fight music fades out (lobby ambience belongs to the world's LobbyAmbience).
function M.endFight()
	M.playMusic(nil)
	table.clear(previousStates)
	table.clear(impactTrackers)
end

function M.init(newCtx: Ctx)
	ctx = newCtx
	ensureGroup("Music", 0.78)
	ensureGroup("SFX", 1)
	ensureGroup("Ambience", 0.55)
	local lab = ReplicatedStorage:WaitForChild("FightingLab")
	local folderInst = lab:FindFirstChild("Audio")
	assert(folderInst and folderInst:IsA("Folder"), "ReplicatedStorage.FightingLab.Audio folder is required")
	audioFolder = folderInst
	local missing = {}
	for _, name in REQUIRED do
		local s = folderInst:FindFirstChild(name)
		if not (s and s:IsA("Sound")) then table.insert(missing, name) end
	end
	assert(#missing == 0, "ReplicatedStorage.FightingLab.Audio missing required Sounds: " .. table.concat(missing, ", "))
	newCtx.gui:SetAttribute("AudioStatus", "Ready")
end

-- The defender's body reaching the floor inside the Ultimate's cinematic (its track's floor channel crossing 0.5).
-- Called every frame by EffectsController.update (the client bootstrap does not update this module per frame) and by
-- M.update; a frame is processed once.
local cineNow: number? = nil
function M.updateCinematic(f: any)
	if type(f) ~= "table" or f.now == cineNow then return end
	cineNow = f.now
	if typeof(f.origin) == "Vector3" then origin = f.origin end
	local aSlot, aId, cineFrame, aView = Cinematic.active(f)
	if aSlot and aView then
		local tc = Cinematic.clip(aId)
		if tc then
			local g = Cinematic.defenderGround(tc, Cinematic.timeline(aId, aView.throw), cineFrame :: number)
			if cineLast and cineLast < 0.5 and g >= 0.5 then
				local d = f.fighters[3 - aSlot]
				M.playLayered("UltLand", if d and typeof(d.pos) == "Vector3" then origin + Vector3.new(d.pos.X, 0.2, d.pos.Z) else nil)
			end
			cineLast = g
		end
	else
		cineLast = nil
	end
end

function M.update(f: any)
	if typeof(f.origin) == "Vector3" then origin = f.origin end
	M.updateCinematic(f)
	for i = 1, 2 do
		local r = f.fighters[i]
		if r then
			local prev = previousStates[i]
			if r.state ~= prev then
				if r.state == "Dash" or r.state == "Backdash" or r.state == "Sidestep" then M.play("Dash", origin + r.pos) end
				previousStates[i] = r.state
			end
			-- Body-on-floor thud in sync with the knockdown/KO fall animation (not when the fall starts).
			local tracker = impactTrackers[i]
			if not tracker then
				tracker = States.newImpactTracker()
				impactTrackers[i] = tracker
			end
			local c = ctx
			if States.floorImpact(tracker, r, if c then c.config else nil, f.now) then
				M.play("Knockdown", origin + Vector3.new(r.pos.X, 0.2, r.pos.Z))
			end
		end
	end
end

return M
