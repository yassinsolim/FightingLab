--!strict
-- Lobby leaderboard (OV6 look): top 10 players by leaderstats.Wins (ties: Streak, then name) rendered into
-- workspace.FightingLabWorld.Lobby.Leaderboard.LeaderboardGui. Ten fixed rows are built once and updated in place.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Client = script.Parent
local Lab = Client.Parent
local UIHelpers = require(Client.UIHelpers)
local Roster = require(Lab.Roster)

local T = UIHelpers.Theme
local make, text = UIHelpers.make, UIHelpers.text

local Leaderboard = {}
Leaderboard.ROWS = 10

export type Entry = { userId: number, name: string, wins: number, streak: number, fighter: string? }
type Row = { frame: Frame, rank: TextLabel, badge: Frame, name: TextLabel, fighter: TextLabel, wins: TextLabel, streak: TextLabel }
export type Board = { root: Frame, rows: { Row }, empty: TextLabel, count: TextLabel }

local MEDALS = { Color3.fromRGB(255, 204, 72), Color3.fromRGB(206, 214, 230), Color3.fromRGB(222, 146, 92) }

function Leaderboard.sortEntries(entries: { Entry }, limit: number?): { Entry }
	local sorted = table.clone(entries)
	table.sort(sorted, function(a: Entry, b: Entry)
		if a.wins ~= b.wins then return a.wins > b.wins end
		if a.streak ~= b.streak then return a.streak > b.streak end
		return string.lower(a.name) < string.lower(b.name)
	end)
	local n = limit or Leaderboard.ROWS
	while #sorted > n do table.remove(sorted) end
	return sorted
end

local function statValue(stats: Instance?, name: string): number
	local v = stats and stats:FindFirstChild(name)
	if v and (v:IsA("IntValue") or v:IsA("NumberValue")) then return math.floor((v :: any).Value) end
	return 0
end

-- Reads one player's leaderstats (works with any Instance carrying leaderstats, e.g. test doubles).
function Leaderboard.entryFor(player: Instance): Entry
	local stats = player:FindFirstChild("leaderstats")
	local display: any = if player:IsA("Player") then player.DisplayName else player:GetAttribute("DisplayName")
	local fighter = player:GetAttribute("FighterId")
	return {
		userId = if player:IsA("Player") then player.UserId else 0,
		name = if typeof(display) == "string" and display ~= "" then display else player.Name,
		wins = statValue(stats, "Wins"),
		streak = statValue(stats, "Streak"),
		fighter = if typeof(fighter) == "string" then fighter else nil,
	}
end

function Leaderboard.collect(players: { Instance }): { Entry }
	local list = {}
	for _, p in players do table.insert(list, Leaderboard.entryFor(p)) end
	return list
end

local function cell(parent: Instance, name: string, font: Font, color: Color3, x: number, w: number, align: Enum.TextXAlignment): TextLabel
	local label = text(parent, name, "", font, 20, color, { Position = UDim2.fromScale(x, 0.12), Size = UDim2.fromScale(w, 0.76), TextScaled = true, TextXAlignment = align })
	make("UITextSizeConstraint", { MaxTextSize = 64, MinTextSize = 6, Parent = label })
	return label
end

function Leaderboard.build(gui: Instance): Board
	local old = gui:FindFirstChild("FightingLabLeaderboard")
	if old then old:Destroy() end
	local root = make("Frame", { Name = "FightingLabLeaderboard", BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) })
	UIHelpers.gradient(root, Color3.fromRGB(22, 26, 36), Color3.fromRGB(6, 7, 11), 90)
	local content = make("Frame", { Name = "Content", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.94, 0.94), Parent = root })
	make("UIAspectRatioConstraint", { AspectRatio = 4 / 3, Parent = content })
	local brand = text(content, "Brand", '<font color="#F3F5F9">FIGHTING</font><font color="#FF5433">LAB</font>', T.display, 18, T.text, { Position = UDim2.fromScale(0.02, 0.0), Size = UDim2.fromScale(0.4, 0.045), TextScaled = true, RichText = true })
	make("UITextSizeConstraint", { MaxTextSize = 40, Parent = brand })
	local title = text(content, "Title", "TOP DUELISTS", T.display, 40, T.text, { Position = UDim2.fromScale(0.02, 0.04), Size = UDim2.fromScale(0.62, 0.09), TextScaled = true })
	make("UITextSizeConstraint", { MaxTextSize = 96, Parent = title })
	local sub = text(content, "Sub", "Most wins on this server  ·  PvP and CPU duels count", T.medium, 18, T.muted, { Position = UDim2.fromScale(0.02, 0.125), Size = UDim2.fromScale(0.75, 0.04), TextScaled = true })
	make("UITextSizeConstraint", { MaxTextSize = 40, Parent = sub })
	local count = text(content, "Count", "", T.heavy, 18, T.muted, { Position = UDim2.fromScale(0.62, 0.05), Size = UDim2.fromScale(0.36, 0.05), TextScaled = true, TextXAlignment = Enum.TextXAlignment.Right })
	make("UITextSizeConstraint", { MaxTextSize = 40, Parent = count })
	local accent = make("Frame", { Name = "Accent", BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Position = UDim2.fromScale(0.02, 0.176), Size = UDim2.fromScale(0.96, 0.006), Parent = content })
	make("UIGradient", { Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, T.ember), ColorSequenceKeypoint.new(0.6, T.gold), ColorSequenceKeypoint.new(1, T.gold) }), Transparency = UIHelpers.ramp({ { 0, 0 }, { 0.7, 0 }, { 1, 1 } }), Parent = accent })
	local header = make("Frame", { Name = "Columns", BackgroundTransparency = 1, Position = UDim2.fromScale(0.02, 0.19), Size = UDim2.fromScale(0.96, 0.05), Parent = content })
	cell(header, "Rank", T.heavy, T.dim, 0, 0.08, Enum.TextXAlignment.Center).Text = "#"
	cell(header, "Player", T.heavy, T.dim, 0.11, 0.4, Enum.TextXAlignment.Left).Text = "PLAYER"
	cell(header, "Fighter", T.heavy, T.dim, 0.52, 0.2, Enum.TextXAlignment.Left).Text = "FIGHTER"
	cell(header, "Wins", T.heavy, T.dim, 0.73, 0.12, Enum.TextXAlignment.Center).Text = "WINS"
	cell(header, "Streak", T.heavy, T.dim, 0.86, 0.14, Enum.TextXAlignment.Center).Text = "STREAK"
	local rows = {}
	local top, step = 0.25, 0.072
	for i = 1, Leaderboard.ROWS do
		local frame = make("Frame", { Name = "Row" .. i, BackgroundColor3 = if i % 2 == 1 then Color3.fromRGB(26, 30, 42) else Color3.fromRGB(18, 21, 30), BackgroundTransparency = 0.1, BorderSizePixel = 0, Position = UDim2.fromScale(0.02, top + (i - 1) * step), Size = UDim2.fromScale(0.96, step - 0.008), Parent = content })
		UIHelpers.corner(frame, 4)
		if i <= 3 then make("Frame", { Name = "Edge", BackgroundColor3 = MEDALS[i], BorderSizePixel = 0, Size = UDim2.new(0, 4, 1, 0), Parent = frame }) end
		local badge = make("Frame", { Name = "Badge", BackgroundColor3 = if i <= 3 then MEDALS[i] else Color3.fromRGB(40, 46, 62), BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.045, 0.5), Size = UDim2.fromScale(0.05, 0.74), Rotation = 0, Parent = frame })
		make("UIAspectRatioConstraint", { AspectRatio = 1, Parent = badge })
		UIHelpers.corner(badge, 3)
		local rank = text(badge, "Rank", tostring(i), T.display, 20, if i <= 3 then T.ink else T.text, { Size = UDim2.fromScale(1, 1), TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center })
		make("UITextSizeConstraint", { MaxTextSize = 48, Parent = rank })
		local name = cell(frame, "Name", T.bold, T.text, 0.11, 0.4, Enum.TextXAlignment.Left)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local fighter = cell(frame, "Fighter", T.heavy, T.muted, 0.52, 0.2, Enum.TextXAlignment.Left)
		local wins = cell(frame, "Wins", T.display, T.gold, 0.73, 0.12, Enum.TextXAlignment.Center)
		local streak = cell(frame, "Streak", T.display, T.warm, 0.86, 0.14, Enum.TextXAlignment.Center)
		table.insert(rows, { frame = frame, rank = rank, badge = badge, name = name, fighter = fighter, wins = wins, streak = streak })
	end
	local empty = text(content, "Empty", "No duels yet — win one to claim the top spot!", T.bold, 24, T.muted, { Position = UDim2.fromScale(0.05, 0.5), Size = UDim2.fromScale(0.9, 0.08), TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, Visible = false, ZIndex = 3 })
	make("UITextSizeConstraint", { MaxTextSize = 44, Parent = empty })
	root.Parent = gui
	return { root = root, rows = rows, empty = empty, count = count }
end

function Leaderboard.render(board: Board, entries: { Entry }, totalPlayers: number?)
	local sorted = Leaderboard.sortEntries(entries, Leaderboard.ROWS)
	local anyWins = false
	for i, row in board.rows do
		local e = sorted[i]
		row.frame.Visible = e ~= nil
		if e then
			if e.wins > 0 then anyWins = true end
			row.name.Text = e.name
			local def = UIHelpers.fighterDef(Roster, e.fighter)
			row.fighter.Text = if def then def.displayName else "—"
			row.fighter.TextColor3 = if def then def.accentColor else T.dim
			row.wins.Text = tostring(e.wins)
			row.streak.Text = if e.streak > 0 then "x" .. tostring(e.streak) else "—"
			row.streak.TextColor3 = if e.streak >= 3 then T.warm elseif e.streak > 0 then T.gold else T.dim
		end
	end
	board.empty.Visible = not anyWins
	local n = totalPlayers or #entries
	board.count.Text = tostring(n) .. (if n == 1 then " DUELIST ONLINE" else " DUELISTS ONLINE")
end

export type Controller = { stop: () -> (), refresh: () -> (), board: () -> Board? }
export type StartOptions = { gui: () -> Instance?, provider: (() -> { Entry })? }

-- Live wiring: watches every player's leaderstats and FighterId and re-renders (throttled) on changes.
function Leaderboard.start(options: StartOptions): Controller
	local conns: { RBXScriptConnection } = {}
	local perPlayer: { [Player]: { RBXScriptConnection } } = {}
	local board: Board? = nil
	local boardGui: Instance? = nil
	local dirty = true
	local stopped = false

	local function unwatch(player: Player)
		local list = perPlayer[player]
		if list then for _, c in list do c:Disconnect() end end
		perPlayer[player] = nil
		dirty = true
	end
	local function watch(player: Player)
		unwatch(player)
		local list: { RBXScriptConnection } = {}
		perPlayer[player] = list
		local function hookStats(stats: Instance)
			table.insert(list, stats.ChildAdded:Connect(function(v)
				if v:IsA("ValueBase") then table.insert(list, (v :: any).Changed:Connect(function() dirty = true end)) end
				dirty = true
			end))
			for _, v in stats:GetChildren() do
				if v:IsA("ValueBase") then table.insert(list, (v :: any).Changed:Connect(function() dirty = true end)) end
			end
		end
		table.insert(list, player.ChildAdded:Connect(function(child) if child.Name == "leaderstats" then hookStats(child); dirty = true end end))
		table.insert(list, player:GetAttributeChangedSignal("FighterId"):Connect(function() dirty = true end))
		local stats = player:FindFirstChild("leaderstats")
		if stats then hookStats(stats) end
		dirty = true
	end
	for _, p in Players:GetPlayers() do watch(p) end
	table.insert(conns, Players.PlayerAdded:Connect(watch))
	table.insert(conns, Players.PlayerRemoving:Connect(unwatch))

	local function refresh()
		local gui = options.gui()
		if not gui then return end
		if gui ~= boardGui or not board or not board.root.Parent then
			board = Leaderboard.build(gui)
			boardGui = gui
		end
		local entries = Leaderboard.collect(Players:GetPlayers())
		local online = #entries
		if options.provider then
			for _, e in options.provider() do table.insert(entries, e) end
			online = #entries
		end
		Leaderboard.render(board :: Board, entries, online)
		dirty = false
	end
	local elapsed = 0
	table.insert(conns, RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 0.5 then return end
		elapsed = 0
		local gui = options.gui()
		if dirty or gui ~= boardGui or (board and not board.root.Parent) then refresh() end
	end))
	refresh()

	return {
		stop = function()
			if stopped then return end
			stopped = true
			for _, c in conns do c:Disconnect() end
			for p in perPlayer do unwatch(p) end
			if board then board.root:Destroy() end
			board = nil
		end,
		refresh = function() dirty = true; refresh() end,
		board = function() return board end,
	}
end

return Leaderboard
