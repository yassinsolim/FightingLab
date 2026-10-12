--!strict
-- NetProtocol: lobby payload validation, fight-input whitelist and the packed 60 Hz snapshot codec.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lab = ReplicatedStorage:WaitForChild("FightingLab")
local NetProtocol = require(Lab:WaitForChild("NetProtocol"))
local MatchRunner = require(Lab:WaitForChild("MatchRunner"))
local RenderBuffer = require(Lab:WaitForChild("RenderBuffer"))
local Config = require(Lab:WaitForChild("CombatConfig"))
local HttpService = game:GetService("HttpService")

return function(t)
	t.test("lobby messages are validated and cleaned", function()
		t.expect.truthy(NetProtocol.SpectatorRadius >= 75 and NetProtocol.SpectatorRadius <= 100, "fights stream to nearby lobby players only (arenas sit 66-70 studs from the plaza centre)")
		local kind, payload = NetProtocol.parseLobby("SelectFighter", { id = "Nia", extra = true })
		t.expect.equal(kind, "SelectFighter")
		t.expect.equal((payload :: any).id, "Nia")
		t.expect.equal((payload :: any).extra, nil)
		t.expect.falsy(NetProtocol.parseLobby("SelectFighter", { id = "Mystery" }))
		t.expect.falsy(NetProtocol.parseLobby("Teleport", {}))
		t.expect.falsy(NetProtocol.parseLobby(42, {}))
		local _, cpu = NetProtocol.parseLobby("RequestCpu", { difficulty = "Impossible" })
		t.expect.equal((cpu :: any).difficulty, "Normal")
		local _, practice = NetProtocol.parseLobby("StartPractice", { mode = "Cpu", difficulty = "Hard", opponent = "Goran" })
		t.expect.equal((practice :: any).mode, "Cpu")
		t.expect.equal((practice :: any).opponent, "Goran")
		t.expect.falsy(NetProtocol.parseLobby("StartPractice", { mode = "Arcade" }))
		t.expect.equal(NetProtocol.parseLobby("LeaveFight", "not a table"), "LeaveFight")
	end)

	t.test("only Move, Block, Crouch and Attack are fight inputs", function()
		t.expect.truthy(NetProtocol.validFightCommand("Move", 1, -1))
		t.expect.truthy(NetProtocol.validFightCommand("Block", true, nil))
		t.expect.truthy(NetProtocol.validFightCommand("Crouch", false, nil))
		t.expect.truthy(NetProtocol.validFightCommand("Attack", "LeadKick", 12))
		t.expect.falsy(NetProtocol.validFightCommand("Move", 2, 0))
		t.expect.falsy(NetProtocol.validFightCommand("Reset", nil, nil))
		t.expect.falsy(NetProtocol.validFightCommand("SetMode", "Training", nil))
		t.expect.falsy(NetProtocol.validFightCommand("SelectCharacters", "Kael", "Nia"))
		t.expect.falsy(NetProtocol.validFightCommand("Attack", "Fireball", nil))
	end)

	t.test("packed snapshots round-trip through RenderBuffer.parse and are much smaller", function()
		local runner = MatchRunner.new()
		runner:configure({ mode = "Match", p1Id = "Lumi", p2Id = "Rhys", stageId = "SnowSummit", human1 = true, human2 = true })
		for _ = 1, Config.ReadyFrames + 1 do runner:step() end
		runner:command("Attack", "LeadPunch", 77, 1)
		runner:command("Move", 1, 0, 2)
		local raw = nil
		for _ = 1, 3 do raw = runner:step() end
		raw.matchId = "Arena_A#1"
		local packed = NetProtocol.packEntry(raw, "Arena_A#1")
		t.expect.equal(NetProtocol.matchIdOf(packed), "Arena_A#1")
		local direct = RenderBuffer.parse(raw)
		local viaPack = RenderBuffer.parse(NetProtocol.unpackEntry(packed))
		assert(direct and viaPack)
		for _, key in { "frame", "epoch", "phase", "mode", "timer", "round", "hitstop", "ko", "p1Id", "p2Id", "stageId", "matchId" } do
			t.expect.equal((viaPack :: any)[key], (direct :: any)[key], key)
		end
		for i = 1, 2 do
			local a, b = direct.fighters[i] :: any, viaPack.fighters[i] :: any
			for _, key in { "pos", "facing", "health", "state", "move", "moveFrame", "commandId", "moveStartFrame", "stun", "combo", "crouched", "walkPhase", "moveX", "characterId", "velocityY", "dashDirection" } do
				t.expect.equal(b[key], a[key], "fighter " .. i .. " " .. key)
			end
		end
		t.expect.equal(viaPack.fighters[1].commandId, 77)
		t.expect.equal(viaPack.scores[1], direct.scores[1])
		local function size(v: any): number
			local ok, json = pcall(function()
				return HttpService:JSONEncode(v)
			end)
			return if ok then #json else 0
		end
		-- Vector3s do not JSON-encode; compare the shapes without them.
		local function strip(v: any): any
			if typeof(v) == "Vector3" then return 0 end
			if typeof(v) ~= "table" then return v end
			local out = {}
			for k, x in v do out[k] = strip(x) end
			return out
		end
		local full, small = size(strip(raw)), size(strip(packed))
		t.expect.truthy(small > 0 and small < full * 0.6, ("packed %d vs dictionary %d bytes"):format(small, full))
	end)

	t.test("packed events keep presentation metadata", function()
		local entry = {
			frame = 10, epoch = 2, phase = "Fight", mode = "Match", scores = { 0, 0 },
			fighters = { { pos = Vector3.zero, facing = Vector3.xAxis, health = 100, state = "Idle", moveFrame = 0, stun = 0, combo = 0, crouched = false, walkPhase = 0, moveX = 0, characterId = "Kael" },
				{ pos = Vector3.new(3, 0, 0), facing = -Vector3.xAxis, health = 90, state = "Hitstun", moveFrame = 0, stun = 9, combo = 1, crouched = false, walkPhase = 0, moveX = 0, characterId = "Sierra" } },
			events = { { kind = "Hit", attacker = 1, target = 2, move = "Jab", damage = 10, advantage = 2, frame = 9, point = Vector3.new(1.5, 3.5, 0), combo = 1, air = false, counter = true, tier = "Light", height = "High", limb = "LeadArm" } },
		}
		local parsed = RenderBuffer.parse(NetProtocol.unpackEntry(NetProtocol.packEntry(entry, "m")))
		assert(parsed)
		local e = parsed.events[1]
		t.expect.equal(e.kind, "Hit")
		t.expect.equal(e.counter, true)
		t.expect.equal(e.launch, nil)
		t.expect.equal(e.point, Vector3.new(1.5, 3.5, 0))
		t.expect.equal(e.height, "High")
		t.expect.equal(e.limb, "LeadArm")
		t.expect.equal(parsed.fighters[2].health, 90)
		t.expect.falsy(NetProtocol.unpackEntry({ matchId = "m", p = { 1, 2 } }), "malformed packed entries are rejected")
	end)

	t.test("binary snapshots round-trip with f32 precision and are a fraction of the table form", function()
		local runner = MatchRunner.new()
		runner:configure({ mode = "Match", p1Id = "Nia", p2Id = "Goran", stageId = "JungleRuins", human1 = true, human2 = true })
		for _ = 1, Config.ReadyFrames + 1 do runner:step() end
		runner:command("Attack", "RearKick", 4242, 1)
		runner:command("Move", -1, 1, 2)
		local raw = nil
		for _ = 1, 4 do raw = runner:step() end
		local encoded = NetProtocol.encodeEntry(raw, "Arena_B#9")
		t.expect.equal(typeof(encoded.b), "buffer")
		t.expect.equal(NetProtocol.matchIdOf(encoded), "Arena_B#9")
		local direct = RenderBuffer.parse(raw)
		local viaBinary = RenderBuffer.parse(NetProtocol.unpackEntry(encoded))
		assert(direct and viaBinary)
		for _, key in { "frame", "epoch", "phase", "mode", "timer", "round", "hitstop", "ko", "p1Id", "p2Id", "stageId", "p2Human" } do
			t.expect.equal((viaBinary :: any)[key], (direct :: any)[key], key)
		end
		t.expect.equal(viaBinary.matchId, "Arena_B#9")
		for i = 1, 2 do
			local a, b = direct.fighters[i] :: any, viaBinary.fighters[i] :: any
			for _, key in { "state", "move", "moveFrame", "commandId", "moveStartFrame", "stun", "combo", "crouched", "characterId", "airFrames", "airHits", "dashDirection", "knockdown", "crush", "armorActive" } do
				t.expect.equal(b[key], a[key], "fighter " .. i .. " " .. key)
			end
			t.expect.truthy((b.pos - a.pos).Magnitude < 1e-4, "pos")
			t.expect.truthy((b.facing - a.facing).Magnitude < 1e-4, "facing")
			t.expect.near(b.health, a.health, 1e-3)
			t.expect.near(b.walkPhase, a.walkPhase, 1e-3)
			t.expect.near(b.moveX, a.moveX, 1e-4)
		end
		t.expect.equal(viaBinary.fighters[1].commandId, 4242)
		local packed = NetProtocol.packEntry(raw, "Arena_B#9")
		local function strip(v: any): any
			if typeof(v) == "Vector3" then return { 0, 0, 0 } end
			if typeof(v) ~= "table" then return v end
			local out = {}
			for k, x in v do out[k] = strip(x) end
			return out
		end
		local arrayBytes = #HttpService:JSONEncode(strip(packed.p))
		t.expect.truthy(buffer.len(encoded.b) < arrayBytes * 0.6, ("binary %d vs array %d bytes"):format(buffer.len(encoded.b), arrayBytes))
		t.expect.truthy(buffer.len(encoded.b) < 260, "binary entry stays small: " .. buffer.len(encoded.b))
	end)

	t.test("binary events, throws, hits and unknown strings survive the codec", function()
		local entry = {
			frame = 70000, epoch = 3, phase = "Fight", mode = "Match", scores = { 1, 0 }, round = 2, timer = 1234, winner = 0, reason = "", hitstop = 6, ko = false,
			p1Id = "Kael", p2Id = "Sierra", stageId = "MidnightRooftop", difficulty = "Hard", serverTime = 1791690000.125,
			fighters = {
				{ pos = Vector3.new(-1.25, 0.5, 2), facing = Vector3.new(0.6, 0, 0.8), health = 87, maxHealth = 120, state = "Throw", move = "Throw", moveFrame = 12, stun = 0, combo = 0, crouched = false, walkPhase = 3.75, moveX = 0, characterId = "Kael",
					throw = { role = "Attacker", archetype = "hip_toss", frame = 9, duration = 48, impactFrame = 32 } },
				{ pos = Vector3.new(1.25, 0, 2), facing = Vector3.new(-0.6, 0, -0.8), health = 40, maxHealth = 100, state = "BrandNewState", stun = 14, combo = 2, crouched = true, walkPhase = 0, moveX = -1, characterId = "Sierra",
					lastHit = { kind = "Counter", height = "Mid", tier = "Heavy", counter = true, frame = 69990, move = "Overhand", limb = "RearArm", side = -1 }, knockdown = "FaceDown", velocityY = -3.5, airFrames = 7, airHits = 2, dashDirection = -1 },
			},
			events = {
				{ kind = "ThrowHit", attacker = 1, target = 2, move = "Throw", damage = 18, advantage = -4, frame = 69999, point = Vector3.new(0, 1.2, 2), combo = 0, air = false, knockdown = true, tier = "Heavy", archetype = "hip_toss", height = "Throw", limb = "Body" },
				{ kind = "Whiff", attacker = 2, target = 1, move = "Jab", damage = 0, advantage = 0, frame = 69999, combo = 0, air = false },
			},
		}
		local decoded = NetProtocol.unpackEntry(NetProtocol.encodeEntry(entry, "m#1"))
		assert(decoded)
		t.expect.equal(decoded.frame, 70000)
		t.expect.equal(decoded.difficulty, "Hard")
		t.expect.equal(decoded.serverTime, 1791690000.125)
		local a, b = decoded.fighters[1], decoded.fighters[2]
		t.expect.equal(a.throw.archetype, "hip_toss")
		t.expect.equal(a.throw.impactFrame, 32)
		t.expect.equal(a.maxHealth, 120)
		t.expect.equal(b.state, "BrandNewState", "unknown strings are sent literally")
		t.expect.equal(b.lastHit.kind, "Counter")
		t.expect.equal(b.lastHit.counter, true)
		t.expect.equal(b.lastHit.side, -1)
		t.expect.equal(b.knockdown, "FaceDown")
		t.expect.near(b.velocityY, -3.5, 1e-6)
		t.expect.equal(b.crouched, true)
		t.expect.equal(#decoded.events, 2)
		t.expect.equal(decoded.events[1].knockdown, true)
		t.expect.equal(decoded.events[1].advantage, -4)
		t.expect.equal(decoded.events[1].point, Vector3.new(0, 1.2, 2))
		t.expect.equal(decoded.events[2].point, nil)
		t.expect.falsy(NetProtocol.unpackEntry({ matchId = "x", b = buffer.create(3) }), "truncated buffers are rejected")
		t.expect.truthy(#NetProtocol.StringTable > 100 and #NetProtocol.StringTable < 2000)
	end)

	t.test("guard, sidestep, dash, getup and throw-break fields plus the practice dummy survive both codecs", function()
		local runner = MatchRunner.new()
		runner:command("SetMode", "Training")
		runner:command("Dummy", "Guard")
		local m = runner.match
		local a, b = m.fighters[1], m.fighters[2]
		a.state = "Sidestep"; a.stepDir = -1; a.stepFrame = 7; a.guard = nil
		b.state = "Getup"; b.getupKind = "SideRoll"; b.rollDir = 1; b.guard = nil
		local raw = runner:buildEntry({
			{ kind = "Whiff", attacker = 2, target = 1, move = "Jab", damage = 0, advantage = 0, frame = m.frame, combo = 0, air = false, tier = "Light", archetype = "straight", height = "High", limb = "LeadArm", evaded = true } :: any,
		})
		local rawB = runner:buildEntry({})
		local rawFighter = (rawB :: any).fighters
		rawFighter[1].state = "Dash"; rawFighter[1].dashFrame = 4; rawFighter[1].dashTotal = 14; rawFighter[1].guard = nil; rawFighter[1].stringIndex = 2
		rawFighter[2].state = "Idle"; rawFighter[2].guard = "Crouch"; rawFighter[2].crouched = true; rawFighter[2].crouchFrames = 9
		rawFighter[2].throw = { role = "Defender", archetype = "clinch_strike", frame = 9, duration = 46, impactFrame = 30, move = "Throw", breakWindow = 20, broken = true, breakFrame = 7 }
		for _, codec in { "binary", "packed" } do
			local function roundTrip(entry: any): any
				local wire = if codec == "binary" then NetProtocol.encodeEntry(entry, "m#2") else NetProtocol.packEntry(entry, "m#2")
				local parsed = RenderBuffer.parse(NetProtocol.unpackEntry(wire))
				assert(parsed, codec .. " parses")
				return parsed
			end
			local one = roundTrip(raw)
			t.expect.equal(one.dummy, "Guard", codec .. " dummy")
			t.expect.equal(one.fighters[1].state, "Sidestep", codec)
			t.expect.equal(one.fighters[1].stepDir, -1, codec .. " stepDir")
			t.expect.equal(one.fighters[1].stepFrame, 7, codec .. " stepFrame")
			t.expect.equal(one.fighters[2].getupKind, "SideRoll", codec .. " getupKind")
			t.expect.equal(one.fighters[2].rollDir, 1, codec .. " rollDir")
			t.expect.equal(one.events[1].evaded, true, codec .. " evaded whiff")
			local two = roundTrip(rawB)
			t.expect.equal(two.fighters[1].dashFrame, 4, codec .. " dashFrame")
			t.expect.equal(two.fighters[1].dashTotal, 14, codec .. " dashTotal")
			t.expect.equal(two.fighters[1].stringIndex, 2, codec .. " stringIndex")
			t.expect.equal(two.fighters[2].guard, "Crouch", codec .. " guard")
			t.expect.equal(two.fighters[2].crouchFrames, 9, codec .. " crouchFrames")
			t.expect.equal(two.fighters[2].throw.move, "Throw", codec .. " throw move")
			t.expect.equal(two.fighters[2].throw.breakWindow, 20, codec .. " throw break window")
			t.expect.equal(two.fighters[2].throw.broken, true, codec .. " throw broken flag")
			t.expect.equal(two.fighters[2].throw.breakFrame, 7, codec .. " throw break frame")
			t.expect.equal(one.fighters[1].throw, nil, codec .. " no throw")
		end
		t.expect.truthy(buffer.len(NetProtocol.encodeEntry(rawB, "m#2").b) < 260, "binary entry stays small")
	end)
end
