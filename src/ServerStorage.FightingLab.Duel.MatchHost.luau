--!strict
-- One server-hosted duel: a MatchRunner stepped at 60 Hz by the DuelService, with human slots fed by Command
-- events and an optional CPU slot driven by the sim trainer AI (same network path as PvP).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lab = ReplicatedStorage:WaitForChild("FightingLab")
local Config = require(Lab:WaitForChild("CombatConfig"))
local MatchRunner = require(Lab:WaitForChild("MatchRunner"))
local NetProtocol = require(Lab:WaitForChild("NetProtocol"))

export type Options = {
	matchId: string, arenaId: string, stageId: string, p1Id: string, p2Id: string,
	cpuSlot: number?, difficulty: string?,
}
export type Summary = {
	phase: string, round: number, scores: { number }, health: { number }, timer: number, winner: number, frame: number,
}

local MatchHost = {}
MatchHost.__index = MatchHost

function MatchHost.new(opts: Options)
	local runner = MatchRunner.new()
	runner:configure({
		mode = "Match", p1Id = opts.p1Id, p2Id = opts.p2Id, stageId = opts.stageId,
		difficulty = NetProtocol.validDifficulty(opts.difficulty) or "Normal",
		human1 = opts.cpuSlot ~= 1, human2 = opts.cpuSlot ~= 2,
	})
	local self = setmetatable({
		runner = runner, matchId = opts.matchId, arenaId = opts.arenaId, stageId = opts.stageId,
		cpuSlot = opts.cpuSlot, difficulty = opts.difficulty, lastEntry = nil :: any, steps = 0, costMs = 0,
	}, MatchHost)
	return self
end

-- Routes one validated fight input to a human slot. CPU slots never accept client input.
function MatchHost:command(slot: number, kind: string, a: any?, b: any?): boolean
	if slot ~= 1 and slot ~= 2 or slot == self.cpuSlot then return false end
	if not NetProtocol.validFightCommand(kind, a, b) then return false end
	return self.runner:command(kind, a, b, slot)
end

function MatchHost:step(): { [string]: any }
	local started = os.clock()
	local entry = self.runner:step()
	entry.matchId = self.matchId
	self.lastEntry = entry
	self.steps += 1
	self.costMs += ((os.clock() - started) * 1000 - self.costMs) * 0.05
	return entry
end

function MatchHost:isOver(): boolean
	local entry = self.lastEntry
	return entry ~= nil and entry.phase == "MatchOver"
end

-- Match winner from the round scores (the sim stops in MatchOver as soon as one side reaches WinsNeeded).
function MatchHost:winnerSlot(): number
	local entry = self.lastEntry
	if not entry then return 0 end
	local scores = entry.scores or { 0, 0 }
	if (scores[1] or 0) >= Config.WinsNeeded and (scores[1] or 0) > (scores[2] or 0) then return 1 end
	if (scores[2] or 0) >= Config.WinsNeeded and (scores[2] or 0) > (scores[1] or 0) then return 2 end
	return if entry.phase == "MatchOver" then (entry.winner or 0) else 0
end

function MatchHost:summary(): Summary
	local entry = self.lastEntry
	local match = self.runner.match
	local health = {}
	for i = 1, 2 do
		local f = match.fighters[i]
		health[i] = if f.maxHealth > 0 then math.clamp(f.health / f.maxHealth, 0, 1) else 0
	end
	return {
		phase = match.phase, round = match.round, scores = { match.scores[1], match.scores[2] }, health = health,
		timer = NetProtocol.timerSeconds(match.timer), winner = match.winner, frame = if entry then entry.frame else match.frame,
	}
end

return MatchHost
