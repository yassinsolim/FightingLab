# combat.md — OV6 combat handoff (sim, controls, movesets, CPU, balance)

Exports: `OV6\handoff\combat-src\` (UTF-8, LF, no BOM). Details: `combat-states.md` (states, snapshot fields, every
move with frame data + animation intent), `combat-balance.md` (exploit search, frame data, CPU numbers).

## Files

| file | status |
|---|---|
| `ReplicatedStorage.FightingLab.CombatSim.luau` | rewritten: guard system, discrete sidestep, committed dash/backdash, chords + throw breaks, tracking/homing, root advance, getup rolls, KO fall, throw-break window, practice dummy |
| `ReplicatedStorage.FightingLab.CombatAI.luau` | **NEW ModuleScript** (the CPU; `Sim.trainerInput` requires it lazily) |
| `ReplicatedStorage.FightingLab.Controls.luau` | **NEW ModuleScript** (single source of truth for keys + labels) |
| `ReplicatedStorage.FightingLab.CombatConfig.luau`, `Roster.luau`, `MatchRunner.luau`, `NetProtocol.luau`, `RenderBuffer.luau` | updated (additive snapshot fields, `Dummy` command, codec v2) |
| `ReplicatedStorage.FightingLab.Client.InputController.luau` | rewritten for the contract §2 scheme |
| tests `CombatSim_Test`, `CombatRoster_Test`, `Difficulty_Test`, `MatchRunner_Test`, `DuelProtocol_Test`, `RenderBuffer_Test` (updated), `Controls_Test`, `CombatAI_Test`, `Balance_Test` (NEW; round 2 updated `CombatAI_Test` and `Balance_Test`; the step-in round updated `CombatRoster_Test` and `CombatAI_Test`; round 4 updated `CombatAI_Test` and `Difficulty_Test`) | |

`SnapshotTiming` is unchanged (not exported).

## Integrator requests done

- Knockdown timing (motioncore request): `CombatConfig.LandingFrames` 26 → **34**, `GetupFrames` 18 → **26** (rolls +10):
  1.0 s from the floor to standing. CPU wake-up/okizeme logic reads the config; tests and `Balance_Test` updated; the
  wake-up search re-run: 0 unblockable setups in 35 956 tests. combat-states.md regenerated, motioncore told.
- `NetProtocol.SpectatorRadius` 150 → **85** (arenas sit 66–70 studs from the plaza centre: the centre still sees every
  arena, a player at one arena no longer streams the far ones). `DuelProtocol_Test` pins it to 75–100.
- motionthrows REQUEST 1 (text only): the animation intents of Kael ThrowB, Goran Throw/ThrowB, Lumi Throw/ThrowB,
  Rhys Throw/ThrowB and Nia Throw now use the §8 wording (what is animated, since the sim never swaps sides).

## Round 2 (CPU for a general player) — changes

Numbers: `combat-balance.md` section 0. Only `CombatAI`, `Roster` (looks/heights) and two tests changed; **no move
key, startup/active or other frame-data change**.

- **Beginner vs Easy fairness (Easy only).** Easy `turnTake` 0.20 → 0.23, plus a per-fighter matchup table
  `CombatAI.Matchups.Easy` (`vs` = the human's fighter, `as` = the CPU's fighter). It scales Easy's chance to
  counter-attack after blocking (`turnScale`), capped at 0.38 so Easy stays below Normal's 0.40.
  - New API: `CombatAI.paramsFor(level, meId, foeId)`. Each brain stores its params at creation.
  - Normal and Hard get their unchanged shared tables.
  - Result: every fighter wins 49–57 % as the beginner and 47–56 % as the Easy CPU (384 matches per cell).
- **Spam tail (Normal and Hard get stronger).** All 19 tail cells ≤ 8 % vs Normal and ≤ 4 % vs Hard at 24 matches
  (worst was 29 % / 21 %). Fixes:
  - a buffered block punish can no longer be replaced by the turn-taking poke (`punishedFor`);
  - a `ducks` read: the opponent's attacks go under highs, so the CPU picks non-highs;
  - a crouch turtle no longer means a crouching attacker;
  - throw streaks count as pressure (the CPU ducks grabs), and the wake-up crouch counts throws;
  - against high spam the CPU stays down and answers;
  - the busy-opponent filter picks moves faster than their usual startup;
  - a reach- and timing-aware step-in after blocking an out-of-reach minus move;
  - when behind with less than 15 s left, the CPU dashes or walks in instead of guarding out the clock.
- **Tools:** setting `CombatAI.trace = true` (or `"full"`) records which decision pressed each CPU move
  (`brain.why`). It's off in the game.
- **Optional Roster add-on (characters.md REQUESTs):** `look` strings for Sierra, Goran, Lumi, Rhys and Nia now
  match the new outfits (Kael unchanged). `stats.height` follows the round-2 statures: Kael 5.95, Sierra 5.85,
  Goran 6.75, Lumi 5.9, Rhys 5.9, Nia 5.5. These are MotionPlayer fallback only; the sim doesn't read them.
- `combat-states.md` regenerated: the frame-number note now says the impact column is the Roster source literal
  (`def.impact`, runtime `def.startup + 1`). This answers a motionkicks question; there was no off-by-one.
- Tests:
  - `CombatAI_Test` +2 cases: "a planned block punish comes out instead of a quick poke" (fails without the fix)
    and "Easy matchup adjustments touch only Easy".
  - `Balance_Test` spam case: now separate targets (Normal ≤ 20 %, Hard ≤ 10 %), plus the old tail moves (Ram Slam,
    Spin Backfist, Teep, Rising Uppercut).

## Step-in round (REQUEST 7, approved) — changes

Numbers: `combat-balance.md` section R7. Only `Roster` (range/advance), `CombatAI` (Easy re-tune + two read fixes)
and two tests changed. **No move key, startup, active, recovery, damage, advantage or push changed.**

- **57 moves step in.** `advance` grows and `range` shrinks by the same amount, so the threat range is unchanged.
  - Built from the motion agents' tip measurements: new range = tip + target surface (High 0.61, Mid 0.47, Low 1.20,
    knees +0.10), rounded to 0.05, floor 2.80. Applied only where the range drops by ≥ 0.20.
  - Table: `combat-balance.md` R7.1 and `OV6\work\combat\stepin-table.txt`. Every low kick is unchanged.
  - motionkicks and motionstrikes got one consolidated table (plus Lumi's three late kicks). motionstrikes has
    re-authored its 22 strikes (contact within 0.08 stud). Nia Rising Tornado stays at 3.10 + 1.50 by agreement.
- **Re-checked:**
  - max-range punishability: unchanged (every launcher and power low 6/6; DoubleHammer 5/6, mirror);
  - spam tail (25 starters, 24 per cell): worst 17 % vs Normal, 4 % vs Hard;
  - CPU spacing: 0 % out-of-range starts at every level; flips, sidesteps and dashes as before.
- **Fallout fixed in `CombatAI`.** Step-ins end closer, inside grab reach: the beginner bot's landed grabs doubled
  and it beat Easy 92 % of the time. Changes:
  - Easy throw break 0.18 → 0.50 (right button 0.58) and `turnTake` 0.23 → 0.30;
  - new Easy-only `crowdJab`: jab back when a masher crowds it;
  - `CombatAI.Matchups.Easy` re-tuned, with new `crowdVs` (Goran 0) and `punishVs` (Goran ×4, capped below Normal);
  - all levels: no high string follow-up into a ducking opponent, and no back-off out of a crouch read.
  - Result: the beginner wins 54.5 % against Easy, and every fighter is at 42.5–63 % in both directions.
  - Cost: Normal now beats Easy 85 % (was 100 %); mash vs Easy 67 % (was 29 %).
- `combat-states.md` regenerated: reach column prints exact values (e.g. `3.55 + 0.65`); the Startup row documents the
  root-motion formula and the step-in.
- Tests:
  - `CombatRoster_Test` + "step-in moves connect at body contact and keep their threat range";
  - `CombatAI_Test` "Easy matchup adjustments touch only Easy" also checks Easy punishes less than Normal and only
    Easy uses `crowdJab`.

## Round 4: the CPU that stayed crouched (ui report) — changes

Numbers: `combat-balance.md` section R4. Changed: `CombatAI` (perception, reads, patience), `CombatSim` (one line:
`setDummy("Fight")` starts a fresh brain), tests `CombatAI_Test` (+4 cases) and `Difficulty_Test` (24 matches per
pairing). **No move, frame data, Roster or protocol change.**

- **Root cause:**
  - `AI.observe` derived a move's start from `frame - moveFrame`, which drifts during hitstop and throws. A single
    throw was remembered as up to 6 throws, and every blocked hit twice.
  - The streak/stance reads (`throwStreak`, `lowStreak`, crouch stance, `ducks`, spam) never aged. "Two throws in a
    row" stayed true forever, and kept the CPU in a crouching `pressure-guard` that never attacked.
- **Fix:**
  - The move start is tracked across hitstop and throws (one attack = one memory). A connected attack still weighs
    double in the pressure `rate`, which keeps the accepted round-3 pace.
  - Reads age on the opponent's free-time clock: 240 free frames for any read, 120 for a low/throw streak, and a
    streak is dropped once the player backs off or sidesteps. Habits fade with time too.
  - A crouch held on a read ends after 1.2 s (1.4 s with a fresh streak) without an attack from the opponent.
  - A new `Params.patience` (Easy 150, Normal 110, Hard 90 frames) makes the CPU act once it has been passive that
    long while the opponent isn't attacking.
  - Wake-up guard no longer walks in standing into a wake-up low.
  - Easy matchup `vs` re-tuned for the corrected perception (Kael 1.25, Lumi 1.0, Nia 1.2).
- **Results:**
  - The lesson flow without ui's reset: all six dummies attack within 2.3–3.8 s and grab the player.
  - After 2 throws, Versus CPUs at every level act within ≤ 2.1 s and never crouch longer than 1.4 s. Before, they
    made no attack at all in 10 s.
  - Longest passive streak in range (CPU vs CPU): 17.9 / 9.8 / 6.8 s → 4.8 / 3.5 / 2.9 s (Easy / Normal / Hard).
  - Spam, beginner, mash, CPU ordering and maxrange targets are all kept.
- **Tools:**
  - `lessonrepro.luau`, `throwidle.luau`;
  - `behaviour.luau` now reports the longest passive streak and unprovoked crouch for every pairing
    (`BEHAVIOUR_DIAG=1` lists the CPU intents of the worst streak);
  - `COMBAT_FIRST` overlays work in every tool, including `testrun.luau`.

## Verification

- Round 4 headless: 126/127 of my cases (the remaining one is the Studio-only FighterRig pose case),
  `inputtest.luau` 0 failures, and every check in `combat-balance.md` R4 re-run (`OV6\work\combat\runs-r4\final\`).
  The new `CombatAI_Test` cases fail on the round-3 CPU (overlay `ab\round3`), as intended.
  - I didn't re-run the Studio suite this round.
  - ui's `UITutorial_Test` plays the lesson against the real CPU dummy, so it should be re-run at integration. My
    headless replica of that flow passes with and without ui's reset.
- Step-in round headless: 122/123 of my cases (the remaining one is the Studio-only FighterRig pose case),
  `inputtest.luau` 0 failures, full exploit search, spam tail, maxrange, behaviour, beginner (4 seeds) and CPU
  matrices re-run (`OV6\work\combat\runs-stepin\`). I didn't re-run the Studio suite: the changes are Roster numbers,
  CPU logic and tests, all run headless.
- Round 2 headless: 121/122 of my cases (the remaining one is the Studio-only FighterRig pose case),
  `inputtest.luau` 0 failures, and the full exploit search re-run (combat-balance.md 0.3). I didn't re-run the
  Studio suite this round: the changes are CPU logic, Roster text/heights and tests, all run headless.
- Round 1 headless (Lune, `OV6\work\combat\harness`): 123/124 of my cases (the FighterRig pose case needs Studio),
  37 + 10 InputController checks (`inputtest.luau`: keys → commands → sim states), exploit search, CPU matrices.
- My Studio (`OV6\work\combat\FightingLab-combat.rbxlx`, base place + combat-src + motioncore-src): full suite
  **272 run, 272 passed, 0 failed** (before and after the knockdown/spectator change). Practice dojo with real key
  input (render positions traced): tap W = one 1.7–2.1 stud step, holding W 2 s = still one step, S tap = step
  toward the camera on release, S hold = stationary crouch, D D = 3.7-stud dash into contact, A A = 3.2-stud
  backdash, chained A A A A = 6.6 studs in 0.9 s. CPU vs CPU on Midnight Rooftop: both stay facing on the fight line
  near the centre, no circling (`OV6\work\combat\shots\cpu-burst-sheet.png`).

## Controls (contract §2) — `RF.Controls`

`Controls.fight.keyboard/gamepad` (forward, back, sidestepIn, sidestepOut, crouch, lp, rp, lk, rk, throw, guide),
`Controls.practice.keyboard/gamepad` (reset, switchMode, easy, normal, hard, dummy, pause, leave),
`Controls.lobby` (interact, menu, jump), `Controls.notation` (lp = "1" …), `Controls.buttons` (sim button names),
`Controls.label(group, action, device?)` (also "dash" = "D D", "backdash", "throw1" = "U+J", "throw2" = "I+K",
"breakThrow" = "U / I", "guard"), `Controls.legend(group, device?)` rows `{action, keys, text}`,
`Controls.formatMoveInput(rosterInput, device?)` ("df+RP" → "S+D+I" / "↘+Y"), `Controls.notationOf(input)`,
`Controls.keyCode(s)`, `Controls.actionText`, `Controls.tapMs` (150).

InputController: S press = crouch immediately; releasing S within 150 ms with nothing else pressed = one sidestep
toward the camera (a `Move z=-1` pulse); W press = one sidestep in. Double taps and chords are detected in the sim
(`DashTapWindow` 14 f, `ChordFrames` 3 f), so online and practice behave the same. Owned keys: D/A/W/S, U/I/J/K/O,
G (→ `ctx.modules.Hud.toggleGuide()`), practice R (Reset), Y (Dummy cycle), P / Start (Pause). LobbyUI keeps T,
1/2/3 and Backspace. New APIs: `Input.practice(action, arg)` ("Reset" | "Dummy" [mode or nil = cycle] | "Pause"
[bool or nil = toggle]) and `Input.bindPractice(handler)` (optional override). Nothing fires while
`setGameplayEnabled(false)`.

Server commands stay Move/Block/Crouch/Attack (`Block` still means "hold back to guard" for old clients).

## REQUESTs

1. **integrator — `ServerStorage.UnitTest.Cases.ClientModules_Test`**: add `"practice", "bindPractice"` to the
   `InputController` API list.
2. **integrator — place setup**: create ModuleScripts `ReplicatedStorage.FightingLab.CombatAI` and
   `ReplicatedStorage.FightingLab.Controls` and the test cases `Controls_Test`, `CombatAI_Test`, `Balance_Test`.
3. **integrator — `CL.FightSession`** (optional): add `Dummy = true` to `PRACTICE_COMMANDS` so
   `FightSession.practiceCommand("Dummy", mode)` works too (InputController already reaches the runner through
   `ctx.send("Dummy")`, which works without this change).
4. ~~motioncore — `VfxFeel_Test` "hitstop freezes both fighters"~~: done by motioncore (P2 dummy "Stand" before the
   jab, exported in motioncore-src).
5. motioncore / move agents (FYI, motioncore confirmed): new states `Sidestep`, `Backdash`, `Getup` rolls
   (`getupKind`, `rollDir`); KO bodies and juggle-ending knockdowns keep falling (`Airborne` with `knockdown` set)
   instead of snapping to the floor; root `advance` is real sim movement (drop cosmetic lunges for moves with
   `advance`); after `ThrowBreak` both fighters stay in `Throw` for 16 f with `throw.broken = true` /
   `throw.breakFrame`, then return to Idle. Sierra's `HopCross` still uses archetype id `superman_punch` (motion-owned
   id; rename optional).
6. **ui**: read keys/labels from `RF.Controls` (labels above), show the practice dummy from `entry.dummy`
   ("Stand" | "Guard" | "Fight") and switch it with `ctx.modules.Input.practice("Dummy", mode)`.
7. ~~**integrator — proposal (from motionkicks)**: long kicks connect at max range while the animated foot is short~~:
   **approved and done** (step-in round above, `combat-balance.md` R7). Motion agents have the final table.
8. **ui — `UIHelpers.rawAttributes` REACH bar** (FYI, sent to ui too): it ranks `max(mv.range)`. After the step-in,
   `range` alone no longer measures reach: Sierra 5.2, Goran 4.8, Rhys 4.65, Nia 4.55, Kael 4.4, Lumi 4.1, so the
   grappler would show the 2nd longest reach. Suggest `stats.preferredRange` (Sierra 4.4, Lumi 4.2, Rhys 4.0, Nia
   3.8, Kael 3.6, Goran 3.2; unchanged), or the threat range `mv.range + (mv.advance or 0)`. (Done by ui in round 2.)
9. **ui (optional, round 4)**: the lesson's throw-break step no longer needs `reset = true` to get a fighting dummy that
   grabs. Without it, my replica of `playLessonInSim` completes all ten steps for all six fighters. Keeping the reset
   is harmless: it restarts from neutral spacing.
