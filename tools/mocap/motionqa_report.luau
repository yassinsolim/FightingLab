-- MotionQA report runner (Studio, Play, Server DataModel; paste into execute_luau or the command bar).
-- Plays every QA case (states, moves at max and close range, transitions, strings, throws, the Ultimate cinematic and
-- the signature stances (round 6), a recorded CPU fight) for
-- the fighters in _G.MotionQAFighters (default: all six) on the real rigs and POSTs the defects as JSON to the report
-- sink (_G.MotionQASink, default http://127.0.0.1:35301/report/<tag>-<Fighter>.json; tools/mocap/motionqa_report.py
-- turns them into the ranked markdown report). Returns a one-line summary per fighter.
local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")
-- _G.MotionQA: a harness loaded by a hot-reload bootstrap (fresh module clones); else the installed one.
local QA = _G.MotionQA or require(ServerStorage.UnitTest.MotionQA)
local Roster = QA.Roster
local fighters = _G.MotionQAFighters or Roster.order
local tag = _G.MotionQATag or "report"
local sink = _G.MotionQASink or "http://127.0.0.1:35301/report/"
local parts = _G.MotionQAParts or { "states", "moves", "transitions", "throws", "ultimates", "stances" }
local want = {}
for _, p in parts do want[p] = true end
local rigs = QA.stage(nil)
local lines = {}
for _, id in fighters do
	local cases = {}
	if want.states then for _, c in QA.stateCases(id) do table.insert(cases, c) end end
	if want.moves then for _, c in QA.moveCases(id, { "max", "close" }) do table.insert(cases, c) end end
	if want.transitions then for _, c in QA.transitionCases(id) do table.insert(cases, c) end end
	if want.throws then for _, c in QA.throwCases(id) do table.insert(cases, c) end end
	if want.hits then for _, c in QA.hitCases(id) do table.insert(cases, c) end end
	-- Round 6 (the harness may be newer than the runtime under test: a baseline without them has no such cases).
	if want.ultimates and QA.ultimateCases then for _, c in QA.ultimateCases(id) do table.insert(cases, c) end end
	if want.stances and QA.stanceCases then for _, c in QA.stanceCases(id) do table.insert(cases, c) end end
	local all, summaries = {}, {}
	local frames, t0 = 0, os.clock()
	for _, case in cases do
		local defects, summary = QA.play(rigs, case, { yieldEvery = 60 })
		for _, d in defects do table.insert(all, d) end
		frames += case.n
		table.insert(summaries, { case = case.label, kind = case.kind, frames = case.n, ms = summary.ms, handHead = summary.handHead, strike = summary.strike, meta = case.meta })
		task.wait()
	end
	local collapsed = QA.summarize(all)
	local payload = HttpService:JSONEncode({ fighter = id, tag = tag, frames = frames, seconds = os.clock() - t0, raw = #all, defects = collapsed.list, counts = collapsed.counts, cases = summaries, thresholds = QA.T })
	HttpService:PostAsync(sink .. tag .. "-" .. id .. ".json", payload, Enum.HttpContentType.ApplicationJson)
	local cats = {}
	for cat, per in collapsed.counts do table.insert(cats, cat .. "=" .. tostring(per[id] or 0)) end
	table.sort(cats)
	table.insert(lines, string.format("%s: %d cases, %d frames, %.1fs, %d raw / %d collapsed defects [%s]", id, #cases, frames, os.clock() - t0, #all, #collapsed.list, table.concat(cats, " ")))
end
QA.destroy(rigs)
return table.concat(lines, "\n")
