--!strict
-- Client FightSession state machine driven by fake Duel events and snapshots, with recording stub modules.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lab = ReplicatedStorage:WaitForChild("FightingLab")
local NetProtocol = require(Lab:WaitForChild("NetProtocol"))
local MatchRunner = require(Lab:WaitForChild("MatchRunner"))
local FightSession = require(Lab:WaitForChild("Client"):WaitForChild("FightSession"))

type Log = { { name: string, args: { any } } }

local function recorder(log: Log, moduleName: string): any
	return setmetatable({}, {
		__index = function(_, key: string)
			return function(...)
				table.insert(log, { name = moduleName .. "." .. key, args = { ... } })
				return nil
			end
		end,
	})
end

local function fakeCtx(log: Log): any
	local modules = {}
	for _, name in { "Characters", "Camera", "Hud", "Input", "Stage", "Effects", "Audio", "FighterLighting", "FrontEnd" } do
		modules[name] = recorder(log, name)
	end
	return { gui = Instance.new("ScreenGui"), modules = modules, config = require(Lab.CombatConfig) }
end

local function called(log: Log, name: string): { any }?
	for i = #log, 1, -1 do
		if log[i].name == name then return log[i].args end
	end
	return nil
end

type Fired = { { remote: string, args: { any } } }

local function fakeRemotes(fired: Fired): any
	local function remote(name: string): any
		return { FireServer = function(_, ...) table.insert(fired, { remote = name, args = { ... } }) end }
	end
	return { command = remote("Command"), lobby = remote("Lobby") }
end

local function newSession(): (any, Log, Fired, { string })
	local log: Log = {}
	local fired: Fired = {}
	local controls: { string } = {}
	local session = FightSession.new({
		ctx = fakeCtx(log),
		remotes = fakeRemotes(fired),
		coreGui = false,
		controls = { enable = function() table.insert(controls, "enable") end, disable = function() table.insert(controls, "disable") end },
	})
	return session, log, fired, controls
end

local ORIGIN = Vector3.new(40, 2, -190)

local function matchStart(overrides: { [string]: any }?): { [string]: any }
	local payload: { [string]: any } = {
		matchId = "Arena_Test#7", arenaId = "Arena_Test", stageId = "HarborDusk", origin = ORIGIN, authority = "Server", slot = 1,
		mode = "Match", cpu = false, p1 = { userId = 11, name = "Alpha", fighter = "Kael" }, p2 = { userId = 22, name = "Beta", fighter = "Sierra" },
	}
	for k, v in overrides or {} do payload[k] = v end
	return payload
end

local function packedEntries(matchId: string, count: number, finalPhase: string?): { any }
	local runner = MatchRunner.new()
	runner:configure({ mode = "Match", p1Id = "Kael", p2Id = "Sierra", human1 = true, human2 = true })
	local list = {}
	for i = 1, count do
		if finalPhase and i == count then
			runner.match.phase = finalPhase
			runner.match.scores = { 0, 2 }
		end
		table.insert(list, NetProtocol.packEntry(runner:step(), matchId))
	end
	return list
end

return function(t)
	t.test("screen side keeps the local fighter on the left for either slot", function()
		t.expect.equal(FightSession.screenSide(1, 1), 1)
		t.expect.equal(FightSession.screenSide(2, 1), 2)
		t.expect.equal(FightSession.screenSide(2, 2), 1)
		t.expect.equal(FightSession.screenSide(1, 2), 2)
	end)

	t.test("MatchStart payloads are validated", function()
		t.expect.falsy(FightSession.parseMatchStart(nil))
		t.expect.falsy(FightSession.parseMatchStart({ matchId = "x" }), "origin required")
		local info = FightSession.parseMatchStart({ matchId = "x", origin = Vector3.zero, slot = 2, authority = "Local", p1 = { fighter = "Nope" } })
		assert(info)
		t.expect.equal(info.slot, 2)
		t.expect.equal(info.authority, "Local")
		t.expect.equal(info.p1.fighter, "Kael", "unknown fighters fall back")
		t.expect.equal(info.mode, "Match")
	end)

	t.test("countdown events change state only around the lobby", function()
		local session = newSession()
		local states = {}
		session.Changed:Connect(function(state) table.insert(states, state) end)
		session:handleDuel("Countdown", { arenaId = "Arena_Test", endsAt = 123, side = 2 })
		t.expect.equal(session.current, "Countdown")
		t.expect.equal(session.countdown.side, 2)
		session:handleDuel("CountdownCancelled", { arenaId = "Arena_Test" })
		t.expect.equal(session.current, "Lobby")
		session:handleDuel("Bogus", {})
		t.expect.equal(session.current, "Lobby")
		task.wait()
		t.expect.equal(table.concat(states, ","), "Countdown,Lobby")
	end)

	t.test("server MatchStart enters fight mode in arena space for slot 2", function()
		local session, log, _, controls = newSession()
		session:handleDuel("Countdown", { arenaId = "Arena_Test", endsAt = 1, side = 2 })
		session:handleDuel("MatchStart", matchStart({ slot = 2 }))
		t.expect.equal(session.current, "Fight")
		t.expect.equal(session.slot, 2)
		local camera = called(log, "Camera.beginFight")
		assert(camera)
		t.expect.equal(camera[1], ORIGIN)
		t.expect.equal(camera[2], 2)
		t.expect.equal((called(log, "Hud.setViewSlot") :: any)[1], 2)
		local chars = called(log, "Characters.setCharacters") :: any
		t.expect.equal(chars[1], "Kael")
		t.expect.equal(chars[2], "Sierra")
		t.expect.equal((called(log, "Characters.setOrigin") :: any)[1], ORIGIN)
		t.expect.equal((called(log, "Input.setGameplayEnabled") :: any)[1], true)
		t.expect.equal((called(log, "Hud.setVisible") :: any)[1], true)
		local mine = nil
		for _, entry in log do
			if entry.name == "Hud.setFighterInfo" and entry.args[1] == 2 then mine = entry.args[2] end
		end
		assert(mine)
		t.expect.equal(mine.tag, "YOU")
		t.expect.equal(mine.playerName, "Beta")
		t.expect.equal(controls[#controls], "disable")
	end)

	t.test("snapshots of the session render arena-space frames and MatchOver enters Results", function()
		local session = newSession()
		session:handleDuel("MatchStart", matchStart())
		t.expect.equal(session:step(1 / 60) ~= nil, true)
		for _, packed in packedEntries("Arena_Test#7", 6, nil) do session:handleSnapshot(packed) end
		session:handleSnapshot(packedEntries("Other#1", 1, nil)[1])
		t.expect.equal(session.snapshotsReceived, 6, "other matches are not part of the session")
		local frame = session:step(1 / 60)
		assert(frame)
		t.expect.equal(frame.origin, ORIGIN)
		t.expect.equal(frame.viewSlot, 1)
		t.expect.equal(frame.session, "Fight")
		t.expect.truthy(frame.entry ~= nil)
		local over = packedEntries("Arena_Test#7", 8, "MatchOver")
		session:handleSnapshot(over[#over])
		t.expect.equal(session.current, "Results")
	end)

	t.test("MatchEnd for the session returns to the lobby and restores everything", function()
		local session, log, _, controls = newSession()
		session:handleDuel("MatchStart", matchStart())
		session:handleDuel("MatchEnd", { matchId = "Different#1", winnerSlot = 1 })
		t.expect.equal(session.current, "Fight", "MatchEnd of another match is ignored")
		session:handleDuel("MatchEnd", { matchId = "Arena_Test#7", winnerSlot = 2, reason = "KO", rounds = { p1 = 1, p2 = 2 } })
		t.expect.equal(session.current, "Lobby")
		t.expect.truthy(called(log, "Camera.endFight") ~= nil)
		t.expect.truthy(called(log, "Characters.endFight") ~= nil)
		t.expect.truthy(called(log, "Stage.clearArena") ~= nil)
		t.expect.equal((called(log, "Hud.setVisible") :: any)[1], false)
		t.expect.equal((called(log, "Input.setGameplayEnabled") :: any)[1], false)
		t.expect.equal(controls[#controls], "enable")
		t.expect.equal(session.lastResult.winnerSlot, 2)
		t.expect.equal(session:step(1 / 60), nil, "no fight frame in the lobby")
	end)

	t.test("server sessions forward only fight inputs, with attack ids", function()
		local session, _, fired = newSession()
		session:send("Move", 1, 0, 1)
		t.expect.equal(#fired, 0, "nothing is sent from the lobby")
		session:handleDuel("MatchStart", matchStart())
		session:send("Move", 1, 0, 1)
		session:send("Reset", nil, nil, 1)
		session:send("SetMode", "Training", nil, 1)
		session:send("Attack", "LeadPunch", nil, 1)
		t.expect.equal(#fired, 2)
		t.expect.equal(fired[1].remote, "Command")
		t.expect.equal(fired[1].args[1], "Move")
		t.expect.equal(fired[2].args[1], "Attack")
		t.expect.equal(fired[2].args[3], session.commandId)
		t.expect.equal(session:leave(), true)
		t.expect.equal(fired[3].remote, "Lobby")
		t.expect.equal(fired[3].args[1], "LeaveFight")
	end)

	t.test("practice runs a local runner with practice commands and leaves via the server", function()
		local session, log, fired = newSession()
		t.expect.truthy(session:startPractice({ mode = "Training" }))
		t.expect.equal(fired[1].args[1], "StartPractice")
		t.expect.equal(fired[1].args[2].mode, "Training")
		session:handleDuel("MatchStart", matchStart({ matchId = "Dojo#P1", authority = "Local", mode = "Training", cpu = false, practice = "Training", p2 = { userId = -1, name = "Training Dummy", fighter = "Goran" } }))
		t.expect.equal(session.current, "Practice")
		t.expect.truthy(session.runner ~= nil)
		t.expect.equal(session.runner.match.mode, "Training")
		local frame = nil
		for _ = 1, 5 do frame = session:step(1 / 60) end
		assert(frame)
		t.expect.equal(frame.origin, ORIGIN)
		t.expect.equal(#frame.fighters, 2)
		t.expect.truthy(session:practiceCommand("Spar"))
		t.expect.equal(session.runner.sparring, true)
		t.expect.truthy(session:practiceCommand("Opponent", "Nia"))
		t.expect.equal(session.runner.match.fighters[2].characterId, "Nia")
		t.expect.equal((called(log, "Characters.setCharacters") :: any)[2], "Nia")
		t.expect.truthy(session:practiceCommand("Mode"))
		t.expect.equal(session.runner.match.mode, "Match")
		t.expect.falsy(session:practiceCommand("Explode"))
		session:send("Move", 1, 0, 1)
		t.expect.equal(session.runner.match.fighters[1].input.moveX, 1)
		session:leave()
		t.expect.equal(fired[#fired].args[1], "EndPractice")
		t.expect.equal(session.current, "Practice", "waits for the server to restore the avatar")
		session:handleDuel("MatchEnd", { matchId = "Dojo#P1", winnerSlot = 0, reason = "Practice" })
		t.expect.equal(session.current, "Lobby")
		t.expect.falsy(session:practiceCommand("Reset"))
	end)

	t.test("lobby UI practice switches: SwitchMode targets, toggle and opponent labels", function()
		local session, log = newSession()
		session:handleDuel("MatchStart", matchStart({ matchId = "Dojo#P2", authority = "Local", mode = "Training", cpu = false, practice = "Training", difficulty = "Hard", p2 = { userId = -1, name = "Training Dummy", fighter = "Goran" } }))
		local function opponentTag(): string?
			local args = nil
			for _, entry in log do
				if entry.name == "Hud.setFighterInfo" and entry.args[1] == 2 then args = entry.args[2] end
			end
			return args and args.tag
		end
		t.expect.equal(opponentTag(), "DUMMY")
		t.expect.truthy(session:practiceCommand("SwitchMode", "Cpu"))
		t.expect.equal(session.runner.match.mode, "Match")
		t.expect.equal(session.info.cpu, true)
		t.expect.equal(session.info.practice, "Cpu")
		t.expect.equal(opponentTag(), "CPU · HARD")
		t.expect.truthy(session:practiceCommand("Difficulty", "Easy"))
		t.expect.equal(opponentTag(), "CPU · EASY")
		t.expect.truthy(session:practiceCommand("SwitchMode", "Training"))
		t.expect.equal(session.runner.match.mode, "Training")
		t.expect.equal(opponentTag(), "DUMMY")
		t.expect.truthy(session:practiceCommand("SwitchMode"))
		t.expect.equal(session.runner.match.mode, "Match", "no target toggles")
		t.expect.falsy(session:practiceCommand("SwitchMode", "Bogus"))
		t.expect.truthy(session:practiceCommand("Spar"))
		t.expect.equal(session.runner.match.mode, "Training", "sparring from a CPU match drops to Training")
		t.expect.equal(session.info.mode, "Training")
		t.expect.equal(session.runner.sparring, true)
	end)

	t.test("a forfeit passes through Results with the MatchEnd outcome; KO results carry rounds", function()
		local session = newSession()
		local seen: { { state: string, info: any } } = {}
		session.Changed:Connect(function(state, info) table.insert(seen, { state = state, info = info }) end)
		session:handleDuel("MatchStart", matchStart())
		session:handleDuel("MatchEnd", { matchId = "Arena_Test#7", winnerSlot = 1, reason = "Forfeit", rounds = { p1 = 0, p2 = 1 } })
		task.wait()
		local states = {}
		for _, s in seen do table.insert(states, s.state) end
		t.expect.equal(table.concat(states, ","), "Fight,Results,Lobby")
		local results = seen[2].info
		t.expect.equal(results.winnerSlot, 1)
		t.expect.equal(results.reason, "Forfeit")
		t.expect.equal(results.matchEnd.winnerSlot, 1)
		t.expect.equal(results.rounds.p2, 1)
		t.expect.equal(results.p2.name, "Beta", "keeps the MatchStart payload for the result card")

		local ko = newSession()
		local koSeen: { any } = {}
		ko.Changed:Connect(function(state, info) if state == "Results" then table.insert(koSeen, info) end end)
		ko:handleDuel("MatchStart", matchStart())
		local over = packedEntries("Arena_Test#7", 4, "MatchOver")
		for _, packed in over do ko:handleSnapshot(packed) end
		ko:handleDuel("MatchEnd", { matchId = "Arena_Test#7", winnerSlot = 2, reason = "KO", rounds = { p1 = 0, p2 = 2 } })
		task.wait()
		t.expect.equal(#koSeen, 1, "a KO enters Results once (at MatchOver)")
		t.expect.equal(koSeen[1].winnerSlot, 2)
		t.expect.equal(koSeen[1].rounds.p2, 2)
		t.expect.equal(ko.current, "Lobby")
	end)

	t.test("round 5: PLAY requests go to the Lobby remote, only from the lobby; the server's Teleport notice is forwarded", function()
		local session, _, fired = newSession()
		local got = {}
		local conn = session.Teleport:Connect(function(p: any) table.insert(got, p) end)
		local function last(): (string, any)
			local f = fired[#fired]
			return f.args[1], f.args[2]
		end
		t.expect.truthy(session:quickPlay({ mode = "Duel" }))
		local kind, payload = last()
		t.expect.equal(fired[#fired].remote, "Lobby")
		t.expect.equal(kind, "QuickPlay")
		t.expect.equal(payload.mode, "Duel")
		t.expect.truthy(session:quickPlay({ mode = "Practice", practice = "Cpu", difficulty = "Hard", opponent = "Nia" }))
		kind, payload = last()
		t.expect.equal(payload.practice, "Cpu")
		t.expect.equal(payload.difficulty, "Hard")
		t.expect.equal(payload.opponent, "Nia")
		local count = #fired
		t.expect.falsy(session:quickPlay({ mode = "Arcade" }), "unknown modes are not sent")
		t.expect.equal(#fired, count)
		t.expect.truthy(session:cancelQueue())
		t.expect.equal((last()), "CancelQueue")
		t.expect.truthy(session:travel("Arena_Test"))
		kind, payload = last()
		t.expect.equal(kind, "Travel")
		t.expect.equal(payload.to, "Arena_Test")
		t.expect.falsy(session:travel(""))
		session:handleDuel("Teleport", { reason = "Cpu", arenaId = "Arena_Test", delay = 0.2 })
		session:handleDuel("Teleport", "junk")
		task.wait()
		t.expect.equal(#got, 2)
		t.expect.equal(got[1].reason, "Cpu")
		t.expect.equal(got[1].arenaId, "Arena_Test")
		t.expect.equal(got[1].delay, 0.2)
		t.expect.equal(got[2].reason, "Travel", "bad payloads still fade")
		t.expect.equal(got[2].delay, NetProtocol.TeleportDelay)
		session:handleDuel("MatchStart", matchStart())
		t.expect.equal(session.current, "Fight")
		count = #fired
		t.expect.falsy(session:quickPlay({ mode = "Duel" }), "no PLAY during a fight")
		t.expect.falsy(session:travel("Plaza"), "no travel during a fight")
		t.expect.equal(#fired, count)
		conn:Disconnect()
	end)
end
