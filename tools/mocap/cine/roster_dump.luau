-- Dumps the roster (every fighter's moves, frame data, anim hints, Ultimate cinematic timeline, stances when present) as
-- JSON for the offline clip tools. Runs the shared ReplicatedStorage modules headless under Lune with @lune/roblox types.
--   lune run tools/mocap/cine/roster_dump.luau <src dir> [out.json]
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local src = process.args[1] or "src"
local out = process.args[2]
local PREFIX = "ReplicatedStorage.FightingLab."
local cache: { [string]: any } = {}

local Lab
local function child(name: string) return { __module = name, Name = name, Parent = Lab } end
Lab = setmetatable({ Name = "FightingLab" }, {
	__index = function(_, key)
		if key == "WaitForChild" or key == "FindFirstChild" then return function(_self, n) return child(n) end end
		return child(key)
	end,
})

local loadModule
local function customRequire(target: any)
	if type(target) == "table" and target.__module then return loadModule(target.__module) end
	error("roster_dump: unsupported require " .. tostring(target))
end

function loadModule(name: string)
	if cache[name] ~= nil then return cache[name] end
	local path = src .. "/" .. PREFIX .. name .. ".luau"
	local env = setmetatable({
		script = { Name = name, Parent = Lab }, require = customRequire, typeof = typeof,
		Vector3 = roblox.Vector3, CFrame = roblox.CFrame, Color3 = roblox.Color3, Vector2 = roblox.Vector2, Enum = roblox.Enum,
		workspace = { GetServerTimeNow = function() return 0 end },
	}, { __index = _G })
	local result = luau.load(fs.readFile(path), { debugName = path, environment = env })()
	cache[name] = result
	return result
end

local function plain(v: any, depth: number?): any
	local d = depth or 0
	if d > 6 then return nil end
	local t = typeof(v)
	if t == "table" then
		local o = {}
		for k, x in v do
			if type(k) == "string" or type(k) == "number" then o[k] = plain(x, d + 1) end
		end
		return o
	elseif t == "number" or t == "string" or t == "boolean" then
		return v
	elseif t == "Color3" then
		return { v.R, v.G, v.B }
	elseif t == "Vector3" then
		return { v.X, v.Y, v.Z }
	end
	return nil
end

local Roster = loadModule("Roster")
local dump = { fighters = {} }
for _, id in Roster.order do
	local c = Roster.get(id)
	local moves = {}
	for _, key in c.moveOrder do moves[key] = plain(c.moves[key]) end
	dump.fighters[id] = {
		id = id, stanceStyle = c.stanceStyle, moveOrder = c.moveOrder, moves = moves,
		stances = plain((c :: any).stances), height = c.stats.height,
	}
end
dump.order = Roster.order
local text = serde.encode("json", dump, true)
if out then fs.writeFile(out, text) else print(text) end
