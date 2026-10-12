--!strict
local M = {}
function M.buildLadder(order: { string }, playerId: string, count: number, seed: number): { string }
	local result = {}
	local n = math.max(1, #order)
	local cursor = seed
	while #result < count do
		local id = order[((cursor - 1) % n) + 1]
		if id ~= playerId then table.insert(result, id) end
		cursor += 1
	end
	return result
end
function M.nextOpponent(ladder: { string }, fight: number): string
	if #ladder == 0 then error("empty arcade ladder") end
	return ladder[math.clamp(fight, 1, #ladder)]
end
function M.afterResult(fight: number, playerWon: boolean): (string, number)
	if playerWon then
		local nextFight = fight + 1
		return if nextFight > 4 then "Champion" else "ArcadeProgress", nextFight
	end
	return "Continue", fight
end
return M
