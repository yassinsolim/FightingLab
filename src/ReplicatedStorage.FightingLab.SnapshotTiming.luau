--!strict
local Config = require(script.Parent.CombatConfig)
local Sim = require(script.Parent.CombatSim)

export type Edge = { epoch: number, phase: string, starts: { number } }
local Timing = {}

function Timing.capture(match: Sim.Match, epoch: number): Edge
	local starts = {}
	for i, f in match.fighters do
		starts[i] = if f.move then match.frame - f.moveFrame + 1 else -1
	end
	return { epoch = epoch, phase = match.phase, starts = starts }
end

function Timing.shouldPublish(previous: Edge, current: Edge, events: number, cadence: number): boolean
	if cadence >= Config.SnapshotEvery or events > 0 or previous.epoch ~= current.epoch or previous.phase ~= current.phase then return true end
	for i, start in current.starts do
		if start >= 0 and start ~= previous.starts[i] then return true end
	end
	return false
end

return Timing
