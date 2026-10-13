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

	t.test("round 6 (codec v3): Surge, ultUsed, tumble, the signature stance and the Ultimate cinematic survive both codecs", function()
		t.expect.truthy(NetProtocol.validFightCommand("Attack", "Ultimate", 5), "1+2 (Ultimate) is a fight input")
		t.expect.truthy(NetProtocol.validFightCommand("Attack", "Kicks", 6), "3+4 (signature) is a fight input")
		local runner = MatchRunner.new()
		runner:configure({ mode = "Match", p1Id = "Kael", p2Id = "Goran", stageId = "SnowSummit", human1 = true, human2 = true })
		for _ = 1, Config.ReadyFrames + 1 do runner:step() end
		local m = runner.match
		local a, b = m.fighters[1], m.fighters[2]
		a.pos = Vector3.new(0, 0, 0); b.pos = Vector3.new(3, 0, 0); a.facing = Vector3.xAxis; b.facing = -Vector3.xAxis
		a.health = 20
		-- P2 holds forward (no guard) so the Ultimate lands.
		runner:command("Move", 1, 0, 2)
		local surgeEntry: any = runner:step()
		local sawSurge = false
		for _, e in surgeEntry.events do if e.kind == "Surge" and e.attacker == 1 then sawSurge = true end end
		t.expect.truthy(sawSurge, "Surge event on entering Surge")
		runner:command("Attack", "Ultimate", 900, 1)
		local cinematic: any = nil
		for _ = 1, 60 do
			local raw: any = runner:step()
			if raw.fighters[1].state == "Ultimate" and raw.fighters[1].throw and raw.fighters[1].throw.frame >= 5 then cinematic = raw; break end
		end
		assert(cinematic, "the Ultimate lands and its cinematic starts")
		for _, codec in { "binary", "packed" } do
			local wire = if codec == "binary" then NetProtocol.encodeEntry(cinematic, "m#6") else NetProtocol.packEntry(cinematic, "m#6")
			local parsed = RenderBuffer.parse(NetProtocol.unpackEntry(wire))
			assert(parsed, codec .. " parses")
			local pa, pb = parsed.fighters[1] :: any, parsed.fighters[2] :: any
			t.expect.equal(pa.state, "Ultimate", codec .. " attacker state")
			t.expect.equal(pb.state, "Ultimate", codec .. " defender state")
			t.expect.equal(pa.surge, false, codec .. " Surge ends when the Ultimate starts")
			t.expect.equal(pa.ultUsed, true, codec .. " ultUsed")
			t.expect.equal(pb.ultUsed, false, codec .. " defender ultUsed")
			t.expect.equal(pa.throw.archetype, "ultimate", codec .. " cinematic archetype")
			t.expect.equal(pa.throw.move, "Ultimate", codec .. " cinematic move")
			t.expect.equal(pa.throw.role, "Attacker", codec .. " attacker role")
			t.expect.equal(pb.throw.role, "Defender", codec .. " defender role")
			t.expect.equal(pa.throw.duration, cinematic.fighters[1].throw.duration, codec .. " duration")
			t.expect.equal(pa.throw.frame, cinematic.fighters[1].throw.frame, codec .. " cinematic frame")
			t.expect.equal(pa.throw.impactFrame, cinematic.fighters[1].throw.impactFrame, codec .. " first impact")
		end
		local stanceEntry: any = runner:buildEntry({
			{ kind = "Hit", attacker = 1, target = 2, move = "RibRoller", damage = 6, advantage = 0, frame = m.frame, point = Vector3.new(1, 3, 0), combo = 3, air = true, tumble = true, tier = "Medium", archetype = "hook", height = "Mid", limb = "LeadArm" } :: any,
			{ kind = "Hit", attacker = 2, target = 1, move = "Jab", damage = 6, advantage = 8, frame = m.frame, point = Vector3.new(1, 3, 0), combo = 1, air = false, punish = true, tier = "Light", archetype = "straight", height = "High", limb = "LeadArm" } :: any,
		})
		stanceEntry.fighters[1].state = "Stance"; stanceEntry.fighters[1].stance = "Pocket"; stanceEntry.fighters[1].stanceFrame = 7
		stanceEntry.fighters[1].surge = true; stanceEntry.fighters[1].ultUsed = false; stanceEntry.fighters[1].throw = nil
		stanceEntry.fighters[2].state = "Airborne"; stanceEntry.fighters[2].tumble = true; stanceEntry.fighters[2].throw = nil
		for _, codec in { "binary", "packed" } do
			local wire = if codec == "binary" then NetProtocol.encodeEntry(stanceEntry, "m#7") else NetProtocol.packEntry(stanceEntry, "m#7")
			local parsed = RenderBuffer.parse(NetProtocol.unpackEntry(wire))
			assert(parsed, codec .. " parses")
			local pa, pb = parsed.fighters[1] :: any, parsed.fighters[2] :: any
			t.expect.equal(pa.state, "Stance", codec .. " stance state")
			t.expect.equal(pa.stance, "Pocket", codec .. " stance key")
			t.expect.equal(pa.stanceFrame, 7, codec .. " stanceFrame")
			t.expect.equal(pa.surge, true, codec .. " surge flag")
			t.expect.equal(pb.tumble, true, codec .. " tumble flag")
			t.expect.equal(pb.stance, nil, codec .. " no stance")
			t.expect.equal(parsed.events[1].tumble, true, codec .. " tumble hit event")
			t.expect.equal(parsed.events[1].punish, nil, codec .. " no punish flag")
			t.expect.equal(parsed.events[2].punish, true, codec .. " punish hit event")
			t.expect.equal(parsed.events[2].tumble, nil, codec .. " no tumble flag")
		end
		t.expect.truthy(buffer.len(NetProtocol.encodeEntry(stanceEntry, "m#7").b) < 320, "binary entry with two hit events stays small")
	end)

	t.test("round 5 PLAY panel kinds: QuickPlay, CancelQueue and Travel are validated; the server's Teleport notice", function()
		for _, k in { "QuickPlay", "CancelQueue", "Travel" } do t.expect.truthy(NetProtocol.LobbyKinds[k], k .. " is a lobby kind") end
		t.expect.truthy(NetProtocol.DuelKinds.Teleport, "Teleport is a server -> client kind")
		t.expect.falsy(NetProtocol.LobbyKinds.Teleport, "clients cannot send Teleport")
		local kind, duel = NetProtocol.parseLobby("QuickPlay", { mode = "Duel", difficulty = "Insane", junk = 1 })
		t.expect.equal(kind, "QuickPlay")
		t.expect.equal((duel :: any).mode, "Duel")
		t.expect.equal((duel :: any).difficulty, "Normal")
		t.expect.equal((duel :: any).junk, nil)
		local _, cpu = NetProtocol.parseLobby("QuickPlay", { mode = "Cpu", difficulty = "Hard" })
		t.expect.equal((cpu :: any).difficulty, "Hard")
		local _, practice = NetProtocol.parseLobby("QuickPlay", { mode = "Practice", practice = "Cpu", opponent = "Nia" })
		t.expect.equal((practice :: any).practice, "Cpu")
		t.expect.equal((practice :: any).opponent, "Nia")
		local _, noOpponent = NetProtocol.parseLobby("QuickPlay", { mode = "Practice", practice = "Training", opponent = "Mystery" })
		t.expect.equal((noOpponent :: any).opponent, nil, "unknown opponents are dropped")
		for _, bad in { {}, { mode = "Arcade" }, { mode = 5 }, { mode = "Practice" }, { mode = "Practice", practice = "Lesson" } } do
			t.expect.falsy(NetProtocol.parseLobby("QuickPlay", bad), "rejects " .. HttpService:JSONEncode(bad))
		end
		t.expect.falsy(NetProtocol.parseLobby("QuickPlay", "Duel"))
		t.expect.equal(NetProtocol.parseLobby("CancelQueue", nil), "CancelQueue")
		local _, travel = NetProtocol.parseLobby("Travel", { to = "Arena_HarborDusk" })
		t.expect.equal((travel :: any).to, "Arena_HarborDusk")
		t.expect.equal(select(2, NetProtocol.parseLobby("Travel", { to = NetProtocol.PlazaTravel })).to, "Plaza")
		for _, bad in { {}, { to = "" }, { to = 7 }, { to = "../Arena" }, { to = "Arena Harbor" }, { to = string.rep("A", 60) } } do
			t.expect.falsy(NetProtocol.parseLobby("Travel", bad), "rejects travel " .. HttpService:JSONEncode(bad))
		end
		t.expect.truthy(NetProtocol.QuickCpuOfferSeconds >= 10 and NetProtocol.QuickCpuOfferSeconds <= 15, "Fight CPU instead after about 12 s")
		t.expect.truthy(NetProtocol.TeleportDelay > 0 and NetProtocol.TeleportDelay <= 0.3, "the fade covers the move without a long wait")
		t.expect.equal(NetProtocol.PlayerDefaults.QuickQueue, 0)
		t.expect.equal(NetProtocol.PlayerDefaults.QuickStatus, "")
	end)

	t.test("appearance handshake counts the rigid welded gear (FightingLabExtra) too", function()
		local model = Instance.new("Model")
		local hand = Instance.new("Part"); hand.Name = "LeftHand"; hand.Parent = model
		local glove = Instance.new("Part"); glove.Name = "LeftGlove"; glove:SetAttribute(NetProtocol.ExtraAttribute, true); glove.Parent = hand
		local holder = Instance.new("Model"); holder.Name = "RightShoeRigid"; holder:SetAttribute(NetProtocol.ExtraAttribute, true); holder.Parent = hand
		local shoe = Instance.new("Part"); shoe.Name = "RightShoe"; shoe:SetAttribute(NetProtocol.ExtraAttribute, true); shoe.Parent = holder
		local acc = Instance.new("Accessory"); acc.Parent = model
		local a, w, e = NetProtocol.appearanceCounts(model)
		t.expect.equal(a, 1)
		t.expect.equal(w, 0)
		t.expect.equal(e, 2, "two welded parts (the Rigid holder model itself is not a part)")
		t.expect.equal(select(1, NetProtocol.expectedAppearance(model)), nil)
		model:SetAttribute(NetProtocol.AccessoryCountAttribute, 1)
		local wa, ww, we = NetProtocol.expectedAppearance(model)
		t.expect.equal(wa, 1)
		t.expect.equal(ww, 0)
		t.expect.equal(we, 0, "older servers without ExtraCount: no extras expected")
		model:SetAttribute(NetProtocol.ExtraCountAttribute, 2)
		t.expect.equal(select(3, NetProtocol.expectedAppearance(model)), 2)
		model:Destroy()
	end)
end
